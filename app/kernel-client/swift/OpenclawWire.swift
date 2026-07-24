// openclaw Gateway 原生 wire 协议的最小编解码帮助函数。
//
// 这不是 D2 契约的一部分——是 OpenclawGatewayKernelClient 内部用来跟"已经在运行的 openclaw
// 内核"直接对话的传输层。帧形状与握手/RPC 细节严格对照
// scratchpad/sg4-openclaw-run-recipe.md §2/§3（recipe 里每一帧都逐字段实测过）：
//   请求 {type:"req", id, method, params}
//   响应 {type:"res", id, ok, payload, error}
//   事件 {type:"event", event, payload, seq?, stateVersion?}
//
// 用 [String: Any] + JSONSerialization，而不是为 openclaw 每个方法单独手写一遍 Codable 结构——
// 本轮只需要 connect/sessions.create/sessions.messages.subscribe/sessions.abort/sessions.delete
// 五个 RPC，openclaw 侧完整 wire schema（它自己的 RequestMessage/ResponseMessage/EventMessage
// 判别联合）在这个项目里已经被我们自己设计的 D2/D1 契约取代，没有必要在这里对 openclaw 原生协议
// 再做一遍 quicktype 级别的建模——这是本文件与 D2.swift/DiscriminatedUnions.swift 分工的边界。

import Foundation

typealias JSONObject = [String: Any]

enum OpenclawWireError: Error, CustomStringConvertible {
    case invalidFrame(String)

    var description: String {
        switch self {
        case .invalidFrame(let s): return "invalid wire frame: \(s)"
        }
    }
}

func encodeFrame(_ object: JSONObject) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw OpenclawWireError.invalidFrame("not a valid JSON object: \(object)")
    }
    return try JSONSerialization.data(withJSONObject: object, options: [])
}

func decodeFrame(_ data: Data) throws -> JSONObject {
    guard let obj = try JSONSerialization.jsonObject(with: data, options: []) as? JSONObject else {
        throw OpenclawWireError.invalidFrame("top-level JSON is not an object")
    }
    return obj
}

/// F2（SG-5 rework）：把一个非文本 `Part`（`kind == .fileRef`，携带本地 `path`）编码成 openclaw
/// `normalizeRpcAttachmentsToChatAttachments`（`gateway/server-methods/attachment-normalize.ts:
/// 29-56`）期望的 wire 形状 `{content, mimeType?, fileName?}`。上一轮只发 `{mimeType,path}`——
/// openclaw 那边 `.filter((a) => a.content)` 会把它直接丢弃（`server-methods.test.ts:2693-2699`
/// 明确验证过这一点），发送方完全不知道附件已经静默消失。`content` 是文件内容的 base64 编码
/// （`normalizeAttachmentContent` 接受字符串或 ArrayBuffer/typed-array 的 base64，这里直接给
/// 字符串形态）。D1 `Part.path` 的文件系统坐标空间本身未裁决（D2 v3 §9.2 第 7 条/F-15 开放项）——
/// 这里"读取本地路径、编码成 content"是 kernel-client 自己的合理转换，不是对某个已验证 openclaw
/// schema 的字面翻译。抽成独立的 free function（不是 actor 方法）方便 frame-replay 单测直接调用，
/// 不需要搭一个真实 WS 连接。
func encodeAttachmentForWire(_ part: Part) -> JSONObject? {
    guard let path = part.path else { return nil }
    guard let data = FileManager.default.contents(atPath: path) else {
        // 读不到文件——诚实跳过这一个 attachment，不编造 content，也不让整个 send() 失败。
        return nil
    }
    var obj: JSONObject = ["content": data.base64EncodedString()]
    if let mime = part.mimeType { obj["mimeType"] = mime }
    obj["fileName"] = (path as NSString).lastPathComponent
    return obj
}

/// F7（CRITICAL，SG-5 rework）：递归脱敏的敏感字段名判定——按 camelCase/snake_case 拆出的**整词**
/// 匹配，不是裸子串匹配。上一轮 `prettyPrint` 把每一帧原样打印，`connect` 请求的
/// `params.auth.token`（共享密钥凭证）会跟着一起进 stdout（可被 CI artifact、终端录屏、支持工单等
/// 渠道泄漏），这是对抗审 T-044 判定的 CRITICAL 缺陷。命中即把整个字段值替换成 `"***REDACTED***"`
/// ——不管原值是字符串/数字/嵌套对象，都不放过（嵌套对象整体替换是有意为之：与其精确挑出对象内部
/// 哪个字段敏感，不如把整个已知敏感的容器打码，避免遗漏同一容器里未来新增的其它凭证字段）。
///
/// **为什么是整词匹配、不是子串匹配**：第一版实现用裸子串 `lower.contains("token")`，实测
/// （真实 openclaw `session.message`/`hello-ok` 快照）会把 `contextTokens`/`inputTokens`/
/// `outputTokens`/`totalTokens` 这些纯粹的"token 计数"字段（不是凭证）一起误伤，白白丢失这些真实
/// 诊断数据的可见性。整词匹配（`token` 单数精确命中 `authToken`/`apiToken`/`params.auth.token`
/// 这类真凭证字段，`tokens` 复数不命中）避免了这个副作用，同时仍然覆盖上面这条 CRITICAL 缺陷本身
/// 关心的字段。
private let sensitiveWords: Set<String> = [
    "auth", "authorization", "token", "secret", "password", "credential", "apikey",
]

/// 把一个 camelCase/snake_case/kebab-case 的 key 拆成小写单词列表——`"contextTokens"` ->
/// `["context","tokens"]`，`"authToken"` -> `["auth","token"]`，`"api_key"` -> `["api","key"]`。
private func lowercasedWords(_ key: String) -> [String] {
    var words: [String] = []
    var current = ""
    for char in key {
        if char == "_" || char == "-" {
            if !current.isEmpty { words.append(current); current = "" }
            continue
        }
        if char.isUppercase, !current.isEmpty {
            words.append(current)
            current = String(char).lowercased()
        } else {
            current.append(Character(char.lowercased()))
        }
    }
    if !current.isEmpty { words.append(current) }
    return words
}

private func isSensitiveKey(_ key: String) -> Bool {
    let words = lowercasedWords(key)
    if words.contains(where: { sensitiveWords.contains($0) }) {
        return true
    }
    // "apiKey"/"api_key" 这类复合词——"api"/"key" 相邻出现才算敏感,不能把"key"单独列为敏感词
    // (RPC 里大量语义完全不同的字段就叫 "key",例如 openclaw 的 session key,不是凭证)。
    guard words.count >= 2 else { return false }
    for i in 0..<(words.count - 1) where words[i] == "api" && words[i + 1] == "key" {
        return true
    }
    return false
}

/// 递归构造一份脱敏副本，供日志/打印使用——原始 `object`/嵌套字典/数组本身不被修改（这是"打印前的
/// 只读转换"，不影响实际发给 openclaw 的请求内容）。
func redactedCopy(_ value: Any) -> Any {
    if let dict = value as? JSONObject {
        var out: JSONObject = [:]
        for (key, nested) in dict {
            out[key] = isSensitiveKey(key) ? "***REDACTED***" : redactedCopy(nested)
        }
        return out
    }
    if let array = value as? [Any] {
        return array.map { redactedCopy($0) }
    }
    return value
}

/// 把收发的每一帧打印出来——这是本轮 SG-4 的验收铁证要求（"把每步的响应/事件打印出来"），不是调试
/// 脚手架，是交付物本身的一部分。**F7 rework**：打印前统一走 `redactedCopy`，递归脱敏
/// auth/token/secret 等凭证字段——这是唯一的调用路径（`OpenclawGatewayKernelClient` 里所有
/// `prettyPrint(...)` 调用点都不需要各自记得脱敏），content 类字段（消息正文/工具输出/审批
/// payload）默认随这条统一路径打印，不再单独提供一个"不脱敏"的旁路。
func prettyPrint(_ label: String, _ object: JSONObject) {
    let safeObject = (redactedCopy(object) as? JSONObject) ?? object
    let data = (try? JSONSerialization.data(withJSONObject: safeObject, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    let text = String(data: data, encoding: .utf8) ?? "<unprintable>"
    print("\n--- \(label) ---\n\(text)")
}
