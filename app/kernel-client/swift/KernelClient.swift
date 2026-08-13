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
//   interrupt       -> §2.4（rounds/0020 起完整实现 `mode:"cancel"`：适配为 openclaw
//                       `sessions.abort`，语义是"中止当前 run、保留会话"——与 stop() 的关键区别是
//                       不发 sessions.delete/session_end、不 finish 事件流，见
//                       OpenclawGatewayKernelClient.swift interrupt() 的文档注释。`steer`/
//                       `abort_and_resend` 两种 mode 仍未实现，显式拒绝 unsupported_interrupt_mode，
//                       不静默当 cancel 处理）
//   stop            -> §2.5（SG-4 完整实现：适配为 openclaw 的 sessions.abort + sessions.delete，
//                       见 recipe §3 "建议 kernel-client 把 stop 实现为…" 一段）
//   respondApproval -> §2.6（rounds/0015 A/B 完整实现：适配为 openclaw `approval.resolve`，含
//                       D2 四值 <-> openclaw 三值的显式决策映射、发出前按**该条请求自带的**
//                       allowedDecisions 做成员校验、以及返回后核对内核终态确实兑现了决策——
//                       见 OpenclawGatewayKernelClient.respondApproval() 与 EventMapping.swift ⑦。
//                       `allow_session` 在 openclaw 无对应档位，按 D1 §2.6 明文要求**同步拒绝**
//                       unsupported_approval_decision，不静默降级）
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
// 编译方式（SG-10 起改为 SwiftPM 包，见 app/Package.swift；不再是裸 swiftc 编译）：
//   swift build --package-path app
// 本文件所在的 KernelClient library target 依赖 D2Generated target（app/generated/swift 的
// quicktype 产物 + 手写判别联合），CLI 入口挪到了 kernel-client/swift/cli/main.swift（独立
// executable target），frame-replay 单测挪到了 kernel-client/swift/frame-replay-tests/
// （另一个独立 executable target，`@testable import KernelClient`）。D1 §2 的 7 个方法签名与
// 语义本身未受此次改造影响。

import Foundation
// `canImport` 门卫：这个文件除了 SwiftPM（这里 D2Generated 是真实独立 module）之外，还被
// `.github/workflows/ci.yml`「Swift golden parity runner」步骤和裸 swiftc 一起拍平编译
// （连同 D2.swift/DiscriminatedUnions.swift + app/contracts/d2/fixtures/swift-runner/ 四个文件，
// 是一次隐式单一 module，没有名为 D2Generated 的可 import 模块）。加 `#if canImport` 让两种编译
// 方式都成立，不需要为了迁 SwiftPM 去改 ci.yml 或 app/contracts/ 下的文件（两者均不在本轮改动
// 范围内）。
#if canImport(D2Generated)
import D2Generated
#endif

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

    /// D1 §2.4 interrupt —— rounds/0020 起完整实现 `mode:"cancel"`（其余两种 mode 显式拒绝
    /// `unsupported_interrupt_mode`）。见 `OpenclawGatewayKernelClient.interrupt()` 的文档注释。
    func interrupt(session: SessionHandle, options: InterruptRequestMessagePayload) async throws -> InterruptResultPayload

    /// D1 §2.5 stop。
    func stop(session: SessionHandle) async throws -> StopResultPayload

    /// D1 §2.6 respondApproval —— 本轮 TODO 桩。
    func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws

    /// D1 §2.7 capabilities —— 本轮 TODO 桩。
    func capabilities(session: SessionHandle?) async throws -> CapabilityDescriptorPayload
}

// MARK: - rounds/0014 会话持久化：加法式可选能力协议（不是 D1 七法的一部分）
//
// D1 KernelPort spec（v3-x §2）没有定义"恢复一个此前进程创建的会话"或"拉取历史消息"——这两个操作
// 是本轮任务书要求的、mac 壳重启后找回会话所需的新增量。scope-lock 明文禁止修改上面 `KernelClient`
// 协议已有的 7 个方法签名；这里新增两个**独立的、可选的、加法式**协议，与 `KernelClient` 协议平行
// 存在,不修改它一个字符。具体实现类可以选择遵循（`OpenclawGatewayKernelClient` 在
// OpenclawGatewayKernelClient.swift 底部的独立 extension 里实现了两者）,也可以不遵循——调用方
// （`SessionStore`）用 `client as? SessionRestoring` 做运行时能力探测,不假设每个 `KernelClient`
// 实现都支持会话持久化,不支持时优雅降级（不恢复/不持久化,而不是崩溃或编译期硬耦合）。

/// 让壳把"进程重启前创建过的会话"重新接回一个新的 `KernelClient` 实例。
///
/// 背景：D1 §2.1 `createSession()` 内部会在 adapter 侧铸造一个 `SessionHandle.sessionID`，并把它
/// 映射到内核原生的寻址锚点（`OpenclawGatewayKernelClient.kernelKeyBySessionID`，openclaw 语境下
/// 就是 `sessions.create` 响应里的 `key` 字段）——这张映射表是 adapter 实例的**进程内存状态**,新
/// 进程启动、new 出一个新的 `OpenclawGatewayKernelClient` 时它必然是空的,即使磁盘上持久化了会话
/// 清单（`SessionHandle` 本身，见 D2.swift:3842，是 `Codable` 的）,`send()`/`stop()`/`subscribe()`
/// 三个 D1 方法此刻仍然完全不认得这个 `sessionID`（各自开头都是
/// `guard let kernelKey = kernelKeyBySessionID[session.sessionID] else { throw ... }`）。
/// `SessionRestoring` 就是补这条缝的加法式协议——重新播种这张映射表 + 重新建立事件订阅,不重新执行
/// D1 §2.1 的 `sessions.create` RPC（那会在内核侧铸造一个全新会话,不是"找回"已经存在的那个）。
public protocol SessionRestoring: AnyObject {
    /// 播种 sessionID -> kernelKey 映射 + 重新建立事件流——语义上相当于"跳过 `sessions.create`
    /// RPC 的 `createSession()`"接上"`subscribe()`（D1 §2.3）"。返回值形状与
    /// `KernelClient.subscribe(session:)` 完全一致,调用方可以复用同一套事件消费逻辑
    /// （`SessionStore.consumeEvents`）,不需要为恢复流程另开一条分支——恢复出来的会话因此不是
    /// 只读快照,后续新事件会正常经由这个流到达（rounds/0014 D 块要求）。
    func restoreSession(sessionID: String, kernelKey: String) async -> AsyncThrowingStream<EventMessageUnion, Error>

    /// 反向查询当前映射表里某个 sessionID 对应的 kernelKey（openclaw `key`）。
    ///
    /// 存在的理由：`createSession()`（D1 §2.1，签名不可改）的返回值 `SessionHandle` 没有为
    /// kernelKey 留字段（它只暴露 `kernelSessionID`,那是 openclaw 侧另一个独立字段,取自
    /// `sessions.create` 响应的 `sessionId`,不是 `key`——两者的区别见
    /// OpenclawGatewayKernelClient.createSession() 文档注释,混用会查到不存在的会话）。rounds/0014
    /// A 块的会话清单持久化必须把 kernelKey 存进磁盘（不存 = 重启后 `restoreSession` 永远没有
    /// 参数可传,这张映射表就播种不回来）,但 `SessionStore` 所在的 `AgentShellCore` 模块看不到
    /// adapter 内部的私有映射表——这个方法是取得它的唯一加法式入口,不需要为此新增 D1 返回值。
    func currentKernelKey(sessionID: String) async -> String?
}

/// 让壳拉取一个已存在会话的历史消息，用于重启后回填 UI（rounds/0014 C 块）。D1 没有定义这个操作；
/// openclaw 通过 `chat.history` RPC 提供
/// （`kernels/openclaw/src/gateway/server-methods/chat-history-handler.ts` 的
/// `chatHistoryHandlers["chat.history"]`）。
public protocol SessionHistoryProviding: AnyObject {
    /// 拉取一个会话的**全部**历史消息——内部翻页直到服务端报告没有更多为止，返回时已经按时间从旧到
    /// 新排好序（可以直接顺序插入 UI 消息列表，不需要调用方自己再排一次）。
    ///
    /// `kernelKey` 是直接参数,不隐式读内部映射表——`SessionRestoring.restoreSession` 与本方法是
    /// 两个独立职责,调用方（见 SessionStore.swift 恢复流程的文档注释,说明了为什么两者要并发调用
    /// 而不是相互等待）可能先播种映射、也可能先拉历史,这个方法不应该隐式假设前者已经发生。
    ///
    /// `pageLimit` 是每页请求的消息条数上限（直接透传给 `chat.history` 的 `limit` 参数）——协议不
    /// 提供默认值（Swift 协议要求不能带默认参数),调用方自行选择,`OpenclawGatewayKernelClient` 侧
    /// 的实现文档注释里记录了它对 openclaw 服务端默认值（200）的参照。
    func fetchFullHistory(kernelKey: String, pageLimit: Int) async throws -> [HistoryRecord]
}

/// 从 openclaw `chat.history` RPC 响应 `messages[]` 数组的单条记录里提炼出的最小字段集合。
///
/// 不是 D2 契约类型——D1/D2 没有为"历史消息"定义 wire DTO（`EventMessageUnion` 十一变体里最接近的
/// `MessageDeltaEventMessage` 是流式增量而不是已落地的历史记录,字段形状也不同：历史记录没有
/// run 归属、没有 D1 `seq`(per-run 单调计数),只有 openclaw 自己的 transcript `__openclaw.seq`）。
/// 这是 kernel-client 层为这个新增量协议自建的最小值类型,呼应 `ChatModels.swift`
/// 头注释"UI 层自建、无 D1/D2 原生对应"的同一条先例。
public struct HistoryRecord: Equatable, Sendable {
    /// openclaw `__openclaw.id`——transcript 消息的稳定标识。缺失（形状异常的记录）时为 nil,不臆造。
    public let id: String?
    /// openclaw `__openclaw.seq`——transcript 序号,用于翻页游标与最终按时间排序。缺失时为 nil。
    public let seq: Int?
    /// openclaw 原始 role 字符串（"user"/"assistant"/其它）——刻意不收窄成 `ChatRole`,history
    /// 消息可能出现 wire 事件解析（`EventMapping.swift` ①)从未处理过的 role 取值,收窄成宽度不够的
    /// 枚举会在这里丢信息；由调用方（`SessionStore`）决定如何把任意 role 字符串映射到 UI 的三态
    /// `ChatRole`。
    public let role: String
    /// 已从 `content`（纯字符串或 `[{type:"text",text}]` 块数组）提炼出的可读文本；非 "text" 类型
    /// 的 block（toolCall/thinking 等）被忽略,提炼规则与
    /// `app/apps/AgentShell/repro/reconcile-history.py` 的 `extract_assistant_text()` 保持一致。
    public let text: String

    public init(id: String?, seq: Int?, role: String, text: String) {
        self.id = id
        self.seq = seq
        self.role = role
        self.text = text
    }
}
