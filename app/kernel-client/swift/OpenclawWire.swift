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
// `canImport` 门卫理由见 KernelClient.swift 同名注释——这个文件也被 ci.yml 的 flat swiftc
// parity-runner 步骤直接编译，那条路径下没有独立的 D2Generated module。
#if canImport(D2Generated)
import D2Generated
#endif

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
/// **M4 rework（收 T-045 codex 确认性再审复现）**：上一轮"整词匹配"本身只覆盖了单数敏感词，
/// `credentials`/`apiKeys`/`secrets` 这些真实 openclaw payload 里常见的**复数**写法——整个 key
/// 就是这一个词（没有 camelCase 边界可分词），永远不等于单数形式，因此完全漏报（凭证泄漏，
/// REPRO `credentials`/`apiKeys` 见 FrameReplayTests.swift）。同时 `token` 是本轮唯一有歧义的
/// 词：它既出现在真凭证字段（`authToken`/`apiToken`/裸 `auth.token`），也出现在纯粹的"用量计数"
/// 字段（`contextTokens`/`tokenBudget`/`inputTokens`/`outputTokens`）——继续用"token 是不是整词
/// 命中"这一个维度已经不够精确，需要看它的**相邻词**才能判断，这正是"更精确的键语义,不是裸子串"
/// 的具体落地：
///  1. 无歧义凭证词（`auth`/`authorization`/`secret`/`password`/`credential`，含常见复数，去掉
///     末尾单个 `s` 再比较）——整词命中即敏感，不需要看上下文。
///  2. `apiKey`/`apiKeys` 复合词——`api` 后紧跟 `key`/`keys` 才算敏感（不能把裸 `key` 单独列为
///     敏感词，openclaw session key 等大量字段就叫 `key`，不是凭证）。
///  3. `token`/`tokens`——裸字段（key 本身就是这一个词）或与 `auth`/`api` 复合（`authToken(s)`/
///     `apiToken(s)`）视为敏感；与已知的计数类限定词（`context`/`input`/`output`/`total`/`max`/
///     `budget`/`count`/`limit`/`usage`/`remaining`）相邻则明确排除，不脱敏——这些正是真实样本里
///     观察到的 token 用量诊断字段，不是凭证。未知限定词默认落回敏感（安全的一侧：宁可多脱敏一个
///     没见过的字段，也不能漏报真凭证）。
private let unambiguousSensitiveSingulars: Set<String> = [
    "auth", "authorization", "secret", "password", "credential",
]
private let tokenCountingQualifiers: Set<String> = [
    "context", "input", "output", "total", "max", "budget", "count", "limit", "usage", "remaining",
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

/// 简单的英语复数去除——只处理"末尾加 s"这一种最常见形态（`credentials` -> `credential`，
/// `secrets` -> `secret`）。这个项目的敏感词表本身都是规则复数，不需要处理不规则变形。
private func singularized(_ word: String) -> String {
    word.hasSuffix("s") && word.count > 1 ? String(word.dropLast()) : word
}

private func isSensitiveKey(_ key: String) -> Bool {
    let words = lowercasedWords(key)

    // ① 无歧义凭证词（含复数）——整词命中（去掉可能的末尾 "s" 再比较）。
    if words.contains(where: { unambiguousSensitiveSingulars.contains(singularized($0)) }) {
        return true
    }

    // ② apiKey/apiKeys 复合词——"api" 后紧跟 "key"/"keys" 才算敏感。
    for i in 0..<words.count where words[i] == "api" && i + 1 < words.count {
        if singularized(words[i + 1]) == "key" { return true }
    }

    // ③ token/tokens——裸字段或与 auth/api 复合视为敏感；与计数类限定词相邻则明确排除（诚实保留
    // 这些真实的用量诊断字段，不误伤）。
    for (i, word) in words.enumerated() where singularized(word) == "token" {
        let hasCountingNeighbor =
            (i > 0 && tokenCountingQualifiers.contains(words[i - 1])) ||
            (i + 1 < words.count && tokenCountingQualifiers.contains(words[i + 1]))
        if hasCountingNeighbor { continue } // 明确排除：token 计数字段，不脱敏
        return true // 裸 token(s) 或与其它未知限定词复合——默认敏感（安全的一侧）
    }

    return false
}

/// B1（rounds/0013）：为 `OpenclawGatewayKernelClient.createSession()` 铸造 openclaw 侧会话 label。
///
/// **背景**：openclaw `sessions.create` 经 `session-create-service.ts:723`
/// （`applySessionsPatchToStore`）转发进 `gateway/sessions-patch.ts:422-441`
/// （`projectSessionsPatchEntry` 的 label 分支）——对同一 store 内**全部**会话强制 label 互不相同
/// （`entry?.label === parsed.label` 逐条比对现有条目，`:435-437`），撞名直接
/// `INVALID_REQUEST: label already in use: <label>`，没有重试机会（本轮逐层读过这条调用链的 openclaw
/// 源码，不是转述任务书）。旧实现写死字面量 `"sg4-kernel-client-l1"`，同一 openclaw state 目录下第二
/// 次 `createSession()` 必然撞上第一次留下的同名条目——本轮已 UI 侧 + CLI 侧双路径实证。
///
/// openclaw 侧 label 规则很宽（`sessions/session-label.ts`）：只要求非空字符串、trim 后 ≤512 字符，
/// **无字符集限制**——设计空间不受某种转义规则约束。
///
/// **方案**：`"sg4-<UTC 时间戳，人眼可读到秒>-<ourSessionID>"`：
/// - 时间戳段落让人在 openclaw 侧扫一眼会话列表就能按创建时间区分多个会话，不是一串除了自己什么都
///   认不出的裸 UUID；
/// - `ourSessionID` 段落是这次 `createSession()` 铸造的 `SessionHandle.sessionID` 本尊（D1 §2.1
///   步骤 1 的预分配 id，`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md:179`）——
///   label 与 SessionHandle 之间因此有精确的双向可查关系：openclaw 侧看到的 label 能直接反查是客户端
///   哪一次 `createSession()` 铸造的，客户端日志/UI 里的 `sessionID` 也能直接在 openclaw 侧按 label
///   搜到对应会话，不需要另外维护一张"两边都要记得同步"的关联表；
/// - 唯一性直接继承 `ourSessionID`（`UUID().uuidString`）本身的低碰撞率保证——时间戳段落只是给人看，
///   不参与唯一性判断，即便两次调用发生在同一秒（连续建会话很容易撞在这一秒）label 依然不同。
///
/// 独立于 actor 之外的纯函数（同款风格见 `encodeAttachmentForWire`）——不依赖任何 actor 状态，方便
/// `FrameReplayTests.swift` 直接单测，不需要搭一个真实连接或 actor 实例。`createdAt` 显式传入（不在
/// 函数内部调用 `Date()`）同样是为了可测试性——测试能用固定日期断言精确的格式化输出。
func makeSessionLabel(ourSessionID: String, createdAt: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return "sg4-\(formatter.string(from: createdAt))-\(ourSessionID)"
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

// MARK: - SG-10 rounds/0012 ① 临时插桩（取证工具，见
// rounds/0012/evidence/item1-mechanism-localization.md §3/§4 与 scope-lock.md ①）
//
// `OpenclawGatewayKernelClient.handleSessionMessageEvent`/`handleAgentEvent`/
// `handleSessionApprovalEvent`/`handleShutdownEvent` 四个被消费 case 现在只有映射失败/旁路才调用
// `prettyPrint`，成功产出 D2 事件的路径完全静默——rounds/0011 的运行日志因此一条承载 assistant 文本
// 的帧都没留下，无法判断 content 形状、`index` 取值、delta 是否重复。下面这组函数是纯粹的取证工具：
// 只读取/摘要已经发生的映射结果，不参与、不影响任何映射决策。调用方（`OpenclawGatewayKernelClient`
// 里的 `traceWireDispatch`）由 `AGENT_KERNEL_WIRE_TRACE` 环境变量整体开关，未设置时这组函数不会被
// 调用，行为与插桩之前逐字节一致。

/// 插桩总开关——未设置该环境变量时返回 nil，调用方必须整体跳过写入路径（这是"默认关闭"的唯一判断
/// 点）。取值是 trace 文件的完整路径。
func wireTraceEnabledPath() -> String? {
    ProcessInfo.processInfo.environment["AGENT_KERNEL_WIRE_TRACE"]
}

/// 把一条 JSON 对象以 JSON Lines 形式追加写入 `path`——每次调用新开文件句柄、写完即关（这是低频的
/// 诊断路径，跟着真实事件到达节奏走，不值得为此长期持有一个跨 actor 方法调用的文件句柄，也避免进程
/// 异常退出时数据留在未 flush 的句柄里）。`path` 不存在时先创建空文件。写入失败（无效 JSON/无权限等）
/// 一律诚实跳过，不抛错、不影响调用方——这是取证工具，不能反过来影响被观察的主路径。
func appendWireTraceLine(_ record: JSONObject, toPath path: String) {
    guard JSONSerialization.isValidJSONObject(record),
          let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
        return
    }
    var line = data
    line.append(0x0A)
    let fm = FileManager.default
    if !fm.fileExists(atPath: path) {
        fm.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    handle.write(line)
}

/// 把一个已经产出的 D2 `EventMessageUnion` 摘成可写盘的 JSON 安全字典：11 变体共有的
/// `wireType`/`seq`/`runID`，`messageDelta` 额外带上**完整、不截断**的 `payload.index`/
/// `payload.delta`——这正是本轮 scope-lock ① 要查的两个字段（index 取值 + delta 文本是否重复）。
/// 这些字段来自我们自己的 D2 映射输出（不是 wire 上的原始任意字段），契约里没有给它们留下承载凭证的
/// 通道，因此不需要再走一次 `redactedCopy`——本文件里只有 `wireFrame`（原始 wire JSON）那一份需要
/// 脱敏，见 `OpenclawGatewayKernelClient.buildWireTraceRecord`。
func wireTraceEventSummary(_ event: EventMessageUnion) -> JSONObject {
    func runIDField(_ value: String?) -> Any { value ?? NSNull() }
    var out: JSONObject = ["wireType": event.wireType]
    switch event {
    case .messageDelta(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
        out["payload"] = ["index": e.payload.index, "delta": e.payload.delta,
                       // rounds/0012 ①' 新增：分组键改用 messageID 后，trace 必须能看见它，
                       // 否则 live 验证读不到该字段会被误判成「映射没传过来」（本轮真踩过一次）。
                       "messageID": e.payload.messageID ?? NSNull()]
    case .thinking(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .toolCall(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .toolResult(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .approvalRequest(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .error(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .turnComplete(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .sessionEnd(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .capabilityChanged(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .operationCompleted(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    case .approvalBufferResolved(let e):
        out["seq"] = e.seq
        out["runID"] = runIDField(e.runID)
    }
    return out
}

/// `produced` 为空时的便利摘要——只是把已经在 `payload` 里的相关字段单独摘出来，方便脚本/人眼不用
/// 逐层展开整份帧；不是我们自己推断出的解释，帧本身才是权威来源（找不到就诚实返回 nil，不编造）。
/// 逐 dispatch case 关注点不同：`session.message` 看 `message.role`（`EventMapping.swift:172-178`
/// 的过滤条件——非 assistant 角色不产出事件）；`agent` 看 `stream`/`data.phase`（`handleAgentEvent`
/// 的 `default: break` 与 `lifecycle` phase 过滤都在这两个字段上判断）；`session.approval` 看
/// `phase`（只有 `pending` 会继续处理，`terminal` 分支已有 `prettyPrint` 记录跳过原因）；`shutdown`
/// 没有已知的"0 事件但需要解释"场景，如实返回 nil。
func wireTraceEmptyHint(eventName: String, payload: JSONObject?) -> JSONObject? {
    switch eventName {
    case "session.message":
        guard let role = (payload?["message"] as? JSONObject)?["role"] else { return nil }
        return ["message.role": role]
    case "agent":
        var hint: JSONObject = [:]
        if let stream = payload?["stream"] { hint["stream"] = stream }
        if let phase = (payload?["data"] as? JSONObject)?["phase"] { hint["data.phase"] = phase }
        return hint.isEmpty ? nil : hint
    case "session.approval":
        guard let phase = payload?["phase"] else { return nil }
        return ["phase": phase]
    default:
        return nil
    }
}
