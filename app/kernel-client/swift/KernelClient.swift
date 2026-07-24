// SG-4: 手写 D1 KernelPort 窄腰面的 Swift 协议表达。
//
// 权威源：D1 KernelPort 语义契约 ~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-5.md §2。
// 下面 7 个方法逐一对应 D1 §2.1~§2.7（queryBilling 属于 §7 计费查询，不在窄腰 7 方法之列，本轮
// 未纳入协议——D2.swift 已生成其 wire DTO，留给后续轮次）：
//
//   createSession   -> §2.1（SG-4 完整实现，见 OpenclawGatewayKernelClient.swift）
//   send            -> §2.2（SG-5 本轮完整实现：适配为 openclaw `sessions.send`，真实触发过
//                       Kimi 模型调用——`scratchpad/openclaw-iso3` 隔离 openclaw + D3-proxy +
//                       Pi Postgres/new-api 现场验证，见 OpenclawGatewayKernelClient.swift send()
//                       的文档注释）
//   subscribe       -> §2.3（SG-4 完整实现；SG-5 补充 includeApprovals:true）
//   interrupt       -> §2.4（TODO 桩，仍 defer——本轮 send() 用的是"一次性 send 到完"的场景，
//                       没有构造"发送中途 interrupt"的现场）
//   stop            -> §2.5（SG-4 完整实现：适配为 openclaw 的 sessions.abort + sessions.delete，
//                       见 recipe §3 "建议 kernel-client 把 stop 实现为…" 一段）
//   respondApproval -> §2.6（TODO 桩——SG-5 现场触发过一次真实 approvalRequest【见
//                       EventMapping.swift ④】，但本轮没有回调 respondApproval 本身，approval
//                       在现场因无路由自动 timeout-deny）
//   capabilities    -> §2.7（TODO 桩，本轮未探测 openclaw capabilities 端点；evt.capability_changed
//                       的映射也因此没有 baseline 可 diff，见 EventMapping.swift ⑥）
//
// 复用 SG-1 codegen 产物：入参/出参类型直接引用 app/generated/swift/D2.swift 里 quicktype 生成的
// D2 DTO（Config/SessionHandle/Input/SendResultPayload/InterruptRequestMessagePayload/
// InterruptResultPayload/StopResultPayload/Decision/CapabilityDescriptorPayload 等）——这些类型是
// 我们自己设计的 D2 wire schema 的 Swift 落地，KernelClient 协议直接拿它们当"进程内契约"的具体
// 类型，而不是为 KernelPort 另起一套。subscribe() 的事件流元素类型是
// DiscriminatedUnions.swift 手写的 EventMessageUnion（D2 v3 §4.1 十一变体判别联合的 Swift 落地）。
//
// 编译方式（与 SG-1 codegen verify 同一套模式，见
// app/contracts/d2/codegen/package.json 的 verify:swift 脚本）：
//   swiftc KernelClient.swift OpenclawWire.swift EventMapping.swift \
//          OpenclawGatewayKernelClient.swift CLIRunner.swift main.swift \
//          ../../generated/swift/D2.swift ../../generated/swift/DiscriminatedUnions.swift \
//          -o <output>

import Foundation

/// KernelClient 实现内部可能抛出的错误——这是本文件本轮新增的类型，不是 D1/D2 契约本身的一部分
/// （D1 的三层错误模型 RejectionFailureCode/ProtocolFailure/BillingQueryFailure 是"内核语义层"的
/// 失败通道，见 DiscriminatedUnions.swift 的 KernelFailure；本类型是"传输层"的补充，用于表达
/// "连接还没建立""收到的帧解析不出预期字段"这类 wire adapter 自身的问题）。
public enum KernelClientError: Error, CustomStringConvertible {
    case notImplemented(String)
    case transport(String)
    case protocolMismatch(String)
    case rpcRejected(code: String, message: String?)
    case notConnected

    public var description: String {
        switch self {
        case .notImplemented(let m): return "not implemented: \(m)"
        case .transport(let m): return "transport error: \(m)"
        case .protocolMismatch(let m): return "protocol mismatch: \(m)"
        case .rpcRejected(let code, let message): return "rpc rejected [\(code)]: \(message ?? "")"
        case .notConnected: return "kernel client not connected"
        }
    }
}

/// D1 §2 KernelPort 窄腰面协议。实现者（如 OpenclawGatewayKernelClient）负责把这 7 个方法适配到
/// 具体内核（openclaw / hermes）各自的 wire 协议上。
///
/// 全部方法标记 `async`（含 subscribe）——D1 的 TS 签名里 subscribe 本身不是 Promise
/// （`subscribe(session): AsyncStream<KernelEvent>`），但 Swift 侧的具体实现用 `actor`
/// 承载连接状态（WS task/pending 请求表/事件流表），actor 隔离要求跨越隔离边界的方法调用
/// 只能通过 `async` 完成——这里把 subscribe 的协议签名也标成 async，语义上仍然等价于
/// "拿到一个事件流"，只是"拿到"这个动作本身要过一次 actor hop，事件流内部的元素仍然是
/// 异步逐个到达，不因为这一处签名调整而改变 D1 的行为语义。
public protocol KernelClient: AnyObject {
    /// D1 §2.1 createSession。
    func createSession(config: Config) async throws -> SessionHandle

    /// D1 §2.2 send —— SG-5 本轮完整实现（见文件头注释、OpenclawGatewayKernelClient.swift）。
    func send(session: SessionHandle, input: Input) async throws -> SendResultPayload

    /// D1 §2.3 subscribe。
    func subscribe(session: SessionHandle) async -> AsyncThrowingStream<EventMessageUnion, Error>

    /// D1 §2.4 interrupt —— 本轮 TODO 桩。
    func interrupt(session: SessionHandle, options: InterruptRequestMessagePayload) async throws -> InterruptResultPayload

    /// D1 §2.5 stop。
    func stop(session: SessionHandle) async throws -> StopResultPayload

    /// D1 §2.6 respondApproval —— 本轮 TODO 桩。
    func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws

    /// D1 §2.7 capabilities —— 本轮 TODO 桩。
    func capabilities(session: SessionHandle?) async throws -> CapabilityDescriptorPayload
}
