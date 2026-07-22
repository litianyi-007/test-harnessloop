// 手写的判别联合包装类型——非 quicktype 产物。
//
// 背景：quicktype 对 JSON Schema `oneOf` 判别联合会把所有分支合并成一个『每个字段都可选』的
// 单一 struct（result/failure 同时可选、11 事件合并成一个 payload:Any 的结构、三层错误合并成
// 一个巨大枚举），完全丢失判别——已在 CODEGEN-FINDINGS.md 记录复现过程。D2.swift（quicktype
// 生成）里的具体消息类型（CreateSessionRequestMessage、11 个 XxxEventMessage、RejectionFailure/
// ProtocolFailure/BillingQueryFailure 等）本身是正确、忠实的叶子 DTO，本文件在它们之上手写三处
// 判别联合包装，作为『需要何种后处理才能让判别联合在 Swift 存活』的具体答案与证据。
//
// 本文件覆盖任务书要求的最小判别测试三项：
//   ① result/failure 互斥（以 createSession 为代表）—— D2Response<Success,Failure> 泛型 enum。
//   ② 11 事件按 type 判别的联合 —— EventMessageUnion enum。
//   ③ 三层错误联合（RejectionFailure|ProtocolFailure|BillingQueryFailure）—— KernelFailure enum。
//
// 范围声明：本文件只覆盖『最小判别测试』要求的代表性子集（createSession 一个方法 + 11 事件 +
// 三层错误），不是把全部 8 个方法的 ResponseMessage 都手写一遍——D2Response<Success,Failure> 是
// 通用泛型包装，把它套到其余 7 个方法上是机械重复劳动（每个方法只需声明一个 Failure 的具体判别
// 类型，如 CreateSessionFailure），本轮不做，留作后续轮次按同一模式扩展。

import Foundation

// MARK: - ① result/failure 互斥判别联合（createSession 代表）

/// createSession 专属的失败判别联合：RejectionFailure | ProtocolFailure（D2 v3 §3.9）。
/// 两者结构均为 {code, detail?}，但 code 各自的枚举取值集合互不相交（RejectionFailureCode 8 个
/// 值 vs ProtocolFailure 的 FailureCode 3 个值）——Swift 的 RawRepresentable enum 解码在遇到
/// 不认识的原始值时会直接失败，这正是下方 `init(from:)` 级联 try? 能够正确判别的基础。
public enum CreateSessionFailure: Codable {
    case rejection(RejectionFailure)
    case protocolFailure(ProtocolFailure)

    public init(from decoder: Decoder) throws {
        if let r = try? RejectionFailure(from: decoder) {
            self = .rejection(r)
            return
        }
        if let p = try? ProtocolFailure(from: decoder) {
            self = .protocolFailure(p)
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "CreateSessionFailure: code 既不属于 RejectionFailureCode 也不属于 ProtocolFailure 的 FailureCode"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rejection(let r): try r.encode(to: encoder)
        case .protocolFailure(let p): try p.encode(to: encoder)
        }
    }
}

/// 通用的 result/failure 互斥判别联合包装——对应 D2 v3 §2 ResponseEnvelope<TType,TSuccess,TFailure>
/// 的 `result: T; failure?: never` / `result?: never; failure: F` 判别语义。解码时显式核对『恰好
/// 一个键存在』，同时拒绝『两者都在』与『两者都不在』——这是 quicktype 坍缩掉的确切语义，手写
/// 后在此处找回。
public enum D2Response<Success: Codable, Failure: Codable>: Codable {
    case result(Success)
    case failure(Failure)

    private enum CodingKeys: String, CodingKey {
        case result
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasResult = container.contains(.result)
        let hasFailure = container.contains(.failure)
        guard hasResult != hasFailure else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "D2Response 必须恰好携带 result 或 failure 之一（互斥判别联合），实际 hasResult=\(hasResult) hasFailure=\(hasFailure)"
            ))
        }
        if hasResult {
            self = .result(try container.decode(Success.self, forKey: .result))
        } else {
            self = .failure(try container.decode(Failure.self, forKey: .failure))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .result(let value):
            try container.encode(value, forKey: .result)
        case .failure(let value):
            try container.encode(value, forKey: .failure)
        }
    }
}

public typealias CreateSessionResponseBody = D2Response<CreateSessionResultPayload, CreateSessionFailure>

// MARK: - ② 11 事件按 type 判别的联合（D2 v3 §4.1 EventMessage）

/// D2 v3 §4.1 EventMessage 的完整判别联合——按 wire 上的 `type` 字段路由到 11 个具体事件消息
/// 类型之一（每个类型本身由 quicktype 正确生成，见 D2.swift）。quicktype 若直接喂 oneOf 会把
/// 11 者合并成一个 `payload: Any?` 的单一结构，彻底丢失『payload 形状取决于 type』这一核心判别
/// ——本 enum 手写找回。
public enum EventMessageUnion: Codable {
    case messageDelta(MessageDeltaEventMessage)
    case thinking(ThinkingEventMessage)
    case toolCall(ToolCallEventMessage)
    case toolResult(ToolResultEventMessage)
    case approvalRequest(ApprovalRequestEventMessage)
    case error(ErrorEventMessage)
    case turnComplete(TurnCompleteEventMessage)
    case sessionEnd(SessionEndEventMessage)
    case capabilityChanged(CapabilityChangedEventMessage)
    case operationCompleted(OperationCompletedEventMessage)
    case approvalBufferResolved(ApprovalBufferResolvedEventMessage)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "evt.message.delta": self = .messageDelta(try MessageDeltaEventMessage(from: decoder))
        case "evt.thinking": self = .thinking(try ThinkingEventMessage(from: decoder))
        case "evt.tool_call": self = .toolCall(try ToolCallEventMessage(from: decoder))
        case "evt.tool_result": self = .toolResult(try ToolResultEventMessage(from: decoder))
        case "evt.approval_request": self = .approvalRequest(try ApprovalRequestEventMessage(from: decoder))
        case "evt.error": self = .error(try ErrorEventMessage(from: decoder))
        case "evt.turn_complete": self = .turnComplete(try TurnCompleteEventMessage(from: decoder))
        case "evt.session_end": self = .sessionEnd(try SessionEndEventMessage(from: decoder))
        case "evt.capability_changed": self = .capabilityChanged(try CapabilityChangedEventMessage(from: decoder))
        case "evt.operation_completed": self = .operationCompleted(try OperationCompletedEventMessage(from: decoder))
        case "evt.approval_buffer_resolved": self = .approvalBufferResolved(try ApprovalBufferResolvedEventMessage(from: decoder))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "EventMessageUnion: 未知事件 type '\(type)'，不属于 D2 v3 §4.1 的 11 类判别联合之一"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .messageDelta(let v): try v.encode(to: encoder)
        case .thinking(let v): try v.encode(to: encoder)
        case .toolCall(let v): try v.encode(to: encoder)
        case .toolResult(let v): try v.encode(to: encoder)
        case .approvalRequest(let v): try v.encode(to: encoder)
        case .error(let v): try v.encode(to: encoder)
        case .turnComplete(let v): try v.encode(to: encoder)
        case .sessionEnd(let v): try v.encode(to: encoder)
        case .capabilityChanged(let v): try v.encode(to: encoder)
        case .operationCompleted(let v): try v.encode(to: encoder)
        case .approvalBufferResolved(let v): try v.encode(to: encoder)
        }
    }

    /// 供最小判别测试使用：返回本 case 对应的 wire type 字面量，用于断言『解码后落入的 case
    /// 确实对应输入 JSON 的 type 字段』，而不仅仅是『解码没抛错』。
    public var wireType: String {
        switch self {
        case .messageDelta: return "evt.message.delta"
        case .thinking: return "evt.thinking"
        case .toolCall: return "evt.tool_call"
        case .toolResult: return "evt.tool_result"
        case .approvalRequest: return "evt.approval_request"
        case .error: return "evt.error"
        case .turnComplete: return "evt.turn_complete"
        case .sessionEnd: return "evt.session_end"
        case .capabilityChanged: return "evt.capability_changed"
        case .operationCompleted: return "evt.operation_completed"
        case .approvalBufferResolved: return "evt.approval_buffer_resolved"
        }
    }
}

// MARK: - ③ 三层错误联合（D1 v3.5 §9.1 / D2 v3 §6）

/// 三层严格不混淆的失败通道，合并表达为一个 Swift 判别联合，仅供『三层不串号』最小判别测试使用
/// ——D2 v3 本身并没有一个跨三层的联合类型（三层在 wire 上出现于不同上下文：RejectionFailure 是
/// 7 个方法的同步拒绝、ProtocolFailure 并入每个 response 的 failure、BillingQueryFailure 专属
/// queryBilling），本 enum 是测试脚手架，不是对 D2 契约新增类型。级联 try? 能够正确判别的原因
/// 同 CreateSessionFailure：三者的 code 枚举值集合两两不相交。
public enum KernelFailure: Codable {
    case rejection(RejectionFailure)
    case protocolFailure(ProtocolFailure)
    case billing(BillingQueryFailure)

    public init(from decoder: Decoder) throws {
        if let r = try? RejectionFailure(from: decoder) {
            self = .rejection(r)
            return
        }
        if let p = try? ProtocolFailure(from: decoder) {
            self = .protocolFailure(p)
            return
        }
        if let b = try? BillingQueryFailure(from: decoder) {
            self = .billing(b)
            return
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "KernelFailure: code 不属于三层错误模型（KernelPortRejectionCode / ProtocolFailure 码 / billing_query_subject_unresolved）中的任何一层"
        ))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rejection(let v): try v.encode(to: encoder)
        case .protocolFailure(let v): try v.encode(to: encoder)
        case .billing(let v): try v.encode(to: encoder)
        }
    }
}
