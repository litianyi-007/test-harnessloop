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

/// 把收发的每一帧原样打印出来——这是本轮 SG-4 的验收铁证要求（"把每步的响应/事件打印出来"），
/// 不是调试脚手架，是交付物本身的一部分。
func prettyPrint(_ label: String, _ object: JSONObject) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    let text = String(data: data, encoding: .utf8) ?? "<unprintable>"
    print("\n--- \(label) ---\n\(text)")
}
