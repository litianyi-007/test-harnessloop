// SG-4 具体 WS 实现：直接对话一个正在运行的 openclaw Gateway 实例。
//
// 用 Foundation `URLSessionWebSocketTask`，无第三方依赖。握手/RPC 帧序列严格对照
// scratchpad/sg4-openclaw-run-recipe.md §2（鉴权握手）/§3（RPC 帧序列）——每一步都在 recipe 里
// 有逐字段的 `[实测]` 记录，本文件是把那份 recipe 变成可复用的 Swift 客户端代码。
//
// 用 `actor` 承载连接状态（WS task、pending 请求表、事件流表、sessionId 映射表）——并发安全靠
// actor 隔离保证，不需要手写锁。
//
// SG-4 完整实现了 createSession / subscribe / stop 三个方法（L1 闭环范围）；SG-5 Stage A 补上
// send()，并把事件 dispatch 从"只认 session.message"扩展到同时处理 agent(command_output/
// lifecycle)/session.approval/全局 shutdown 四类 wire 事件；本轮（SG-5 rework，对抗审 T-044
// REWORK 后的返工）在此基础上：
//   F1 — send() 加 D1 §9.3 session 级互斥锁（send_pending/stop_in_progress），run/tool/usage 缓存
//        改为 per-run（不是 per-session），避免并发 send/串 run。
//   F2 — attachment 改发 openclaw 期望的 `content`（base64）编码，不再发会被丢弃的 `{mimeType,path}`。
//   F3 — 统一 per-run 单调 seq 域（`nextSeq(runID:sessionID:)`），保留 openclaw 原始 ts，不用 Date()
//        冒充事件发生时刻（`sentAt` 才是 Date()，语义是"适配器本地转发时刻"）。
//   F4 — approval 关联改用 `agent(stream:"approval")` 的准确 `toolCallId`/`approvalId`，去掉"最近
//        一次 toolCall"的猜测。
//   F5 — 新增 `agent(stream:"thinking"/"error"/"item")` dispatch（非 exec 工具、真实 error 流）。
//   F6 — stop() 用adapter 铸造的唯一 operationId 贯穿 Promise -> operation_completed ->
//        turn_complete(cancelled) -> session_end(stopped)；合法无 stopReason 的 phase:end 不再默认
//        error（见 EventMapping.swift）。
//   F7 — prettyPrint 统一递归脱敏 auth/token 等凭证字段，不再明文打印。
//   F8 — shutdown/transportClosed/stop 三条 sessionEnd 路径共享一个"已产出 terminal"标记，去重。
// capabilities 仍是 TODO 桩，理由见 KernelClient.swift 头注释；interrupt() 见下方 rounds/0020 段——
// 只在需要它才能修的地方记 blocker（见交付报告）。
//
// rounds/0015 A/B：`respondApproval()`（D1 §2.6）**不再是桩**——适配到 openclaw `approval.resolve`
// RPC，含决策映射（D2 下划线四值 <-> openclaw 连字符三值，EventMapping.swift ⑦）、发出前的
// `allowedDecisions` 成员校验、以及返回后的终态兑现核对。方法签名一字未动。
//
// rounds/0020：`interrupt()`（D1 §2.4）**不再是桩**——本轮只实现 `mode:"cancel"`：适配到 openclaw
// `sessions.abort`，与 stop() 共享 `forceDenyPendingApprovalsBeforeStop`/`waitForPendingStopTerminal`/
// `emitOperationCompletedMirror` 三个部件（`PendingStop`/`emitOperationCompletedMirror`/
// `mapOpenclawAgentLifecycleToAbortTerminalEvents` 因此各新增一个 `operationKind` 字段/参数，使等待
// 与镜像机制对 stop()/interrupt() 通用而不必各写一份；`stop()` 的全部既有调用点显式传 `.stop`，其
// 可观察行为逐字节未变）——但**从不**发 `sessions.delete`/`session_end`、不 finish 事件流，这是
// interrupt 与 stop 的唯一本质区别（保留会话，用户能在同一 session 上继续 `send()`）。`mode:"steer"`/
// `"abort_and_resend"` 仍显式拒绝 `unsupported_interrupt_mode`，不静默当 cancel 处理。新增
// `SessionLockState.interruptInProgress` 锁态。方法签名一字未动，完整推理见 interrupt() 自己的文档
// 注释。

import Foundation
// `canImport` 门卫理由见 KernelClient.swift 同名注释——这个文件也被 ci.yml 的 flat swiftc
// parity-runner 步骤直接编译，那条路径下没有独立的 D2Generated module。
#if canImport(D2Generated)
import D2Generated
#endif

public actor OpenclawGatewayKernelClient: KernelClient {
    private let endpoint: URL
    private let token: String
    private let urlSession: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    private var nextReqID = 0
    /// req id -> 等待该 id 对应 res 帧的 continuation。
    private var pending: [String: CheckedContinuation<JSONObject, Error>] = [:]
    /// 一次性等待"下一条指定名字的 event 帧"——仅用于握手期等 `connect.challenge`
    /// （它是服务端主动推送的 event，不是某个 req 的 res，所以不能走上面的 pending 表）。
    private var oneShotEventWaiters: [String: CheckedContinuation<JSONObject, Error>] = [:]
    /// 我们自己铸造的 SessionHandle.sessionId -> openclaw 原生 key（D1 §2.1：sessionId 是 adapter
    /// 预分配的寻址锚点，kernelSessionId/这里的 key 才是内核认得的、后续 RPC 真正要用的值）。
    private var kernelKeyBySessionID: [String: String] = [:]
    private var eventContinuations: [String: AsyncThrowingStream<EventMessageUnion, Error>.Continuation] = [:]

    // MARK: F1 — send/stop/interrupt 的 session 级互斥锁（D1 v3.1 §9.3，v3.6 继承）
    //
    // rounds/0020：interrupt() 不再是桩，`interrupt_in_progress` 从此是真实可达的锁态——**这条注释
    // 此前说这个分支"本轮不适用"，那个前提随本轮改动失效**（原文见 git blame，此处不再复述）。三个
    // 方法两两互斥：任一方法执行时若锁不是 idle，一律 reject(session_locked)，**不做优先级仲裁**
    // （例如"stop 请求到达时抢占正在进行的 interrupt"）——D1 v3.1 §9.3 本身没有定义任何仲裁语义，
    // 这把锁存在的唯一目的是"同一时刻只有一个方法在真正操作这个 session 的 run 生命周期"，后到者
    // 除了排队等锁释放之外唯一的选择就是被拒绝，不做抢占，与 send()/stop() 已有的既成实现一致。
    private enum SessionLockState: Equatable, CustomStringConvertible {
        case idle
        case sendPending
        case stopInProgress
        case interruptInProgress

        var description: String {
            switch self {
            case .idle: return "idle"
            case .sendPending: return "send_pending"
            case .stopInProgress: return "stop_in_progress"
            case .interruptInProgress: return "interrupt_in_progress"
            }
        }
    }
    private var lockStateBySessionID: [String: SessionLockState] = [:]

    /// NOTE-1（T-047 grok 复核，真挂起 bug 修复）：`waitForPendingStopTerminal` 里 await 着的
    /// `PendingStop.waiter` 现在有三种可能的唤醒结果，不再是单纯的 `Bool`「是否超时」——旧代码只
    /// 区分 true/false 两态，导致"transport 关闭"这个第三种场景无法被安全表达：要么被误当成"没
    /// 超时"（继续假装 succeeded），要么干脆没有任何值可以 resume（旧 bug：pendingStop 被直接从
    /// `pendingStops` 移除，waiter 从此没人 resume，`stop()` 永久挂起）。
    enum StopWaitOutcome {
        /// 由 `handleAgentEvent` 观察到对应的 aborted lifecycle 帧，正常终态确认。
        case terminalObserved
        /// 等待窗口耗尽（生产默认 5 秒），诚实报超时，继续走 delete 收尾。
        case timedOut
        /// 等待过程中 transport 关闭——`resolvePendingStopForTransportClose` 已经代发
        /// `operation_completed(aborted_effect_unknown)` 镜像、标记 `terminalEmitted`，并清理了
        /// 全部派生状态。`stop()` 见到这个值必须如实抛错，不能假装 succeeded/timed_out。
        case transportClosed
    }

    // MARK: F6/M3 — stop() 的 pending 状态（adapter 铸造的唯一 operationId + 等待终态确认）
    private struct PendingStop {
        let operationID: String
        // M3：不再是 let——发起 sessions.abort 之后必须用其权威返回值 abortedRunId 覆盖这里（见
        // stop() 的文档注释），不能一直沿用发起 abort 前可能陈旧的本地缓存值。
        var affectedRunID: String?
        var terminalEmitted: Bool = false
        var waiter: CheckedContinuation<StopWaitOutcome, Never>?
        // D1 §6.2 M3（stop-path 强制 deny rework）：这次 stop() 在发起 sessions.abort 之前、强制 deny
        // 掉的 reqId 列表——由 `forceDenyPendingApprovalsBeforeStop` 在 sessions.abort 之前填好（见
        // stop() 方法体），供 `handleAgentEvent` 的 lifecycle(aborted) 分支把它们塞进这个 run 的
        // `TurnCompleteEvent.forceResolvedApprovals`。空数组（没有 pending approval 需要强制处理）是
        // 绝大多数 stop() 调用的常态，不是遗漏。
        var forceResolvedApprovalReqIDs: [String] = []
        // rounds/0020：这张表（`pendingStops`）现在被 stop()/interrupt() 共享——`waitForPendingStopTerminal`
        // 与 `handleAgentEvent` 的 lifecycle(aborted) 分支都只按 sessionID/`affectedRunID` 匹配，不
        // 区分"这次等待是谁发起的"（两者需要的等待/去重/强制 deny 定序语义逐字相同，见 interrupt()
        // 文档注释"与 stop() 的关系"一节）。这个字段记下真正的发起者，供
        // `emitOperationCompletedMirror`/`mapOpenclawAgentLifecycleToAbortTerminalEvents` 正确标注
        // `OperationCompletedEventMessagePayload.operationKind`——D2 v3 §3.4/§3.5 明确区分
        // interrupt/stop 两种 operationKind，只订阅事件流的观察者不该被一律告知"stop"，即使这次
        // 等待其实是 interrupt() 发起的。`stop()` 的唯一构造点（见其方法体）恒传 `.stop`，因此这个
        // 字段的引入不改变 stop() 任何一次调用的取值，不影响其既有行为。
        let operationKind: OperationKind
    }
    private var pendingStops: [String: PendingStop] = [:]

    /// M3：测试专用的 stop() 等待超时覆盖（秒）——生产默认 5 秒（D1 v3 §9.3），测试用一个短得多的
    /// 值验证"超时"这条路径，不用真的等 5 秒。`nil` 时 stop() 使用生产默认值。
    private var testSupportStopTimeoutSecondsOverride: Int?

    /// rounds/0020：interrupt() 专用的等待超时覆盖——与上面的 `testSupportStopTimeoutSecondsOverride`
    /// **刻意分开**（不是合用一个变量）：两者控制的是同一个 `waitForPendingStopTerminal` 辅助函数，
    /// 但调用方各自把自己的超时值作为参数传入，函数本身并不读任何一个覆盖变量——分开是为了不让
    /// "覆盖 stop() 的测试超时"这个动作意外影响一个恰好并发存在的 interrupt() 调用（反之亦然），
    /// 测试的可读性上也更直接：一条 interrupt() 测试里出现 `testSupportSetInterruptTimeoutSeconds`
    /// 而不是名字带着"Stop"字样的 setter，不需要读者停下来确认"这个名字虽然叫 Stop 但其实对
    /// interrupt() 也生效"。生产默认同为 5 秒（D1 v3 §9.3 的等待预算对 interrupt/stop 没有区分）。
    private var testSupportInterruptTimeoutSecondsOverride: Int?

    /// NOTE-A（T-049 grok 对抗审复核揪出的中等竞态，本轮修复）：`forceDenyPendingApprovalsBeforeStop`
    /// 现在是一个 drain 循环（见该函数文档注释）——每轮结束后重新检查该 session 是否有新到的 pending
    /// 审批，直到某轮检查为空才允许 stop() 继续发 sessions.abort。为防止（理论上不该出现，但不能假装
    /// 不可能）一个持续产生审批请求的 run 让这个循环无限跑下去，加一个迭代轮次上限——生产默认
    /// `forceDenyDrainDefaultMaxRounds`，测试用这个覆盖值验证"超过上限如实 throw、不静默死循环"这条
    /// 路径，不用真的喂 50 轮。`nil` 时使用生产默认值。
    private var testSupportForceDenyDrainMaxRoundsOverride: Int?

    // MARK: F8 — 三条 sessionEnd 路径（shutdown/transportClosed/stop）共享的去重标记
    private var sessionTerminalEmitted: Set<String> = []

    // MARK: - rounds/0012 ② 返工：send 侧屏障（订阅竞态收口，见 subscribe()/send() 文档注释）
    //
    // 上一版把竞态收口放在 subscribe() 自己身上（等订阅 RPC 落地才 return stream）——推翻理由见
    // subscribe() 文档注释（违反 D1、且把 CI flat-swiftc 平价 runner 从 12/0/1 打穿到必然悬挂）。
    // 本版把屏障挪到 send()（以及 stop()，同一屏障复用）开头：等待"该 session 的订阅 RPC 已经
    // dispatch"，不等它的响应——两者的区别、以及为什么只能是前者，完整论证见 send() 文档注释。

    /// 有条目 = 该 session 的 subscribe() 已经被调用，但它背景 Task 里真正发起
    /// `sessions.messages.subscribe` RPC 这一步尚未发生——`send()`/`stop()` 开头据此判断要不要等。
    /// 没有条目（从未 subscribe 过，或已经 dispatch 完毕）的 session 一律不等，见
    /// `awaitSubscriptionRpcDispatchIfPending` 文档注释。
    private var subscriptionDispatchPending: Set<String> = []
    /// 正在 `awaitSubscriptionRpcDispatchIfPending` 里挂起等待的 `send()`/`stop()` 调用——
    /// `markSubscriptionRpcDispatched` 唤醒时一次性清空并 resume 全部（理论上同一 session 同一时刻
    /// 只会有一个 send_pending/stop_in_progress 锁持有者在等，数组只是防御性地允许多个）。
    private var subscriptionDispatchWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    /// Test-only：人为延迟 subscribe() 标记"该 session 订阅 RPC 已 dispatch"的时刻——生产路径恒为
    /// nil，不生效。用于确定性地构造 send 侧屏障的破坏性反证（不加延迟的话，"背景 Task 是否先于
    /// send() 跑到 dispatch 点"取决于 Swift actor 调度巧合，不可靠地复现，见
    /// `testSupportSetSubscribeDispatchDelay` 与 FrameReplayTests.swift 对应测试的文档注释）。
    private var testSupportSubscribeDispatchDelayNanoseconds: UInt64?

    /// subscribe() 同步前缀里调用——登记"这个 session 有一个尚未 dispatch 的订阅 RPC"。必须在
    /// subscribe() 自己的同步代码里调用（`Task {}` 派生之前），这样"登记"这一步严格先于
    /// subscribe() 返回、也严格先于调用方有机会发起任何后续 `send()`/`stop()`（两者对同一个 actor
    /// 的方法调用不可能重叠执行）——不存在"先调用 send() 才补登记"的竞态窗口。
    private func beginTrackingSubscriptionDispatch(sessionID: String) {
        subscriptionDispatchPending.insert(sessionID)
    }

    /// subscribe() 背景 Task 里，真正调用 `request(method:"sessions.messages.subscribe",...)`
    /// **之前**的最后一步——标记"已经 dispatch"并唤醒所有在等待的 `send()`/`stop()`。**不等这条 RPC
    /// 的响应**——`request()` 本身、以及它底层传输（生产是 `URLSessionWebSocketTask.send` 的完成
    /// 回调，测试桩是 `testSupportStubRPC` 闭包）都还没有开始跑，这里只标记"即将把这个 RPC 交出去"
    /// 这一刻。kernelKey 查找失败（unknown session，根本不会真的发起这条 RPC）的分支也调用它——
    /// 否则那种极端情况下会有等待者永久卡住（虽然它们自己的 kernelKey 查找也会紧接着独立失败，双重
    /// 保险不嫌多）。
    private func markSubscriptionRpcDispatched(sessionID: String) {
        subscriptionDispatchPending.remove(sessionID)
        let waiters = subscriptionDispatchWaiters.removeValue(forKey: sessionID) ?? []
        for waiter in waiters { waiter.resume() }
    }

    /// `send()`/`stop()` 开头调用。若该 session 当前有一个尚未 dispatch 的订阅 RPC 在途，挂起直到
    /// `markSubscriptionRpcDispatched` 唤醒；否则（**从未 subscribe 过**，或订阅 RPC 已经 dispatch
    /// 过）立即返回、不挂起——两种"不等"场景共享同一个分支，是有意合并，不是漏判：
    /// "从未 subscribe"根本没有 `subscriptionDispatchPending` 条目可等（要求它去等一个永远不会有人
    /// 调用 `markSubscriptionRpcDispatched` 的信号，就是制造一个永久挂起——D1 §2.2 send() 本身并不
    /// 要求先 subscribe，任务书明确点名的 fixture 场景"只 createSession + send、不 subscribe"必须
    /// 立即可用）。
    private func awaitSubscriptionRpcDispatchIfPending(sessionID: String) async {
        guard subscriptionDispatchPending.contains(sessionID) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            subscriptionDispatchWaiters[sessionID, default: []].append(continuation)
        }
    }

    /// Test-only 存取器——供 subscribe() 背景 Task 读取人为延迟（跨越 actor 隔离需要这一层 `await
    /// self.` 包装，与文件其余 `testSupport*` 方法同款风格）。
    private func subscribeDispatchDelayNanosecondsForTesting() -> UInt64? {
        testSupportSubscribeDispatchDelayNanoseconds
    }

    // MARK: SG-5 事件映射需要的最小逐 session/run 状态缓存
    //
    // openclaw 的 wire 事件本身不总是自带 D2 判别联合要求的全部字段（最典型的是 turnComplete/
    // operationCompleted/approvalRequest 都要求非空的 runID，但 session.approval 事件本身不带
    // runId；approvalRequest 还要求 toolCallID，但 openclaw 的审批 payload 本身不带 toolCallId）。
    // F1 订正：run/tool/usage 三个缓存改为 **per-run**（用 runId 做键），不再是 per-session——
    // per-session 缓存在并发/连续多个 run 的场景下会把上一个 run 的残留值串给下一个 run（对抗审
    // T-044 F1 复现场景），per-run 键天然避免这个问题：新 run 开始时缓存自然是空的。
    private var lastRunIDBySessionID: [String: String] = [:]
    private var runIDsBySessionID: [String: Set<String>] = [:] // 供 session 结束时批量清理 per-run 缓存
    private var lastToolCallIDByRunID: [String: String] = [:]
    private var lastUsageByRunID: [String: (input: Int, output: Int)] = [:]

    // MARK: M1 — approval 双向 join（agent(stream:"approval") <-> session.approval(phase:"pending")）
    //
    // F4 上一轮只缓存 approvalId -> toolCallId，遗漏了这次审批**真实归属的 runId**——`session.approval`
    // 落地时只能退回到全 session 的 `lastRunIDBySessionID`，在多个 run 交替产生审批时会把 approval
    // 错误关联到"当前最新活跃的 run"，而不是这次审批实际所在的 run（对抗审 T-045 M1 复现：
    // agent approval-A(run-A) 之后 agent approval-B(run-B) 到达，把 lastRunIDBySessionID 刷新成
    // run-B，随后姗姗来迟的 session.approval(approval-A) 会被错误按成 run-B）。同时上一轮完全没有
    // 处理"session.approval 先于对应 agent(stream:approval) 帧到达"这个方向——直接丢弃，approval
    // _request 永久丢失，即使 agent 帧随后真的到达也不会补发。本轮改为按 approvalId 做真正的双向
    // 缓冲 join：agent 帧先到就缓冲 {runID,toolCallID}，session.approval 先到就缓冲整个 payload，
    // 谁后到就用先到的那份补全信息，立即产出（且只产出一次）。
    private struct AgentApprovalInfo {
        let runID: String
        let toolCallID: String
    }
    private var agentApprovalInfoByApprovalID: [String: AgentApprovalInfo] = [:]

    private struct PendingSessionApproval {
        let payload: JSONObject
        let ourSessionID: String
    }
    private var pendingSessionApprovalByApprovalID: [String: PendingSessionApproval] = [:]

    /// 上面两张按 approvalId 键控的缓存本身不是 per-session 键，session 结束时要靠这张反向索引才
    /// 知道该批量清哪些 approvalId（M5：避免漏配对的条目永久残留）。
    private var approvalIDsBySessionID: [String: Set<String>] = [:]

    /// rounds/0016：已经被本 session 的审批 FSM **接纳**过的 approvalId（按 session 分桶，session
    /// 结束时随 `clearSessionDerivedCaches` 一起清）。
    ///
    /// 补上 `exec.approval.requested` 映射之后，同一次审批在 wire 上有**两条**独立事件可以触发产出
    /// （`session.approval(pending)` 与 `exec.approval.requested`，见 `handleExecApprovalRequestedEvent`
    /// 文档注释里的到达顺序），若不设闸门就会给调用方发两条 reqID 相同的 `evt.approval_request`。
    /// `pendingApprovalsByReqID` 不能兼任这个闸门——它在 `respondApproval()` 成功后会把条目摘掉，
    /// 之后再来一条同 reqId 的迟到帧又会被当成新审批重新产出。这张表只增不减（session 生命周期内）。
    ///
    /// **rounds/0015 返工（D1 §6.2 pending #2 缓冲策略）语义扩容**：原语义是"已经交付过
    /// approval_request"，现在扩为"**已经进入本 session 的审批 FSM**"——三种归宿之一：已提升为
    /// active pending（真的 yield 了事件）、正躺在 FIFO 缓冲队列里（**没有** yield，见
    /// `bufferedApprovalsBySessionID`）、或因队列溢出被直接强制 deny（同样没有 yield）。扩容的理由
    /// 是原语义在缓冲态下不成立：一条被缓冲的审批"尚未交付"，但**绝不能**被同一次审批的第二条 wire
    /// 事件重新走一遍接纳流程（那会在队列里塞两份同 reqId 的条目）。判定谓词也随之更名为
    /// `approvalAlreadyAdmitted`。
    private var admittedApprovalIDsBySessionID: [String: Set<String>] = [:]

    // MARK: - rounds/0015 返工①：D1 §6.2「pending #2 缓冲策略」审批状态机
    //
    // D1 v3.6:616-624 原文（`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md`）：
    //   - "既有基线要求 pending 上限=1、串行呈现给调用方（同一 session 同一时刻只暴露一个 active
    //     pending 审批请求）"
    //   - "当一条新的 ApprovalRequestEvent 到达、而当前已有一个 active pending 审批尚未终态化时，
    //     适配器把新请求放入本地 FIFO 缓冲队列，**不**立即以任何形式呈现给调用方"
    //   - "缓冲队列深度是**实现定义的有限值**（本 spec 不钉死具体数字，要求实现选定一个有限值并
    //     文档化）；超过该深度时，新到达的审批请求**不进入队列**，适配器直接对其发起
    //     respondApproval(deny)（reason 标注为一个可读的溢出标识，如 queue_overflow）"
    //   - "缓冲请求的终态改为通过新增的 ApprovalBufferResolvedEvent 上报……携带 reqId、
    //     reason（'buffered_timeout' | 'queue_overflow'）"
    //   - "这是**运行时并发分支**，不是 UI 呈现优化——即使调用方从不构建『审批队列』UI，适配器也
    //     必须实现上述缓冲/提升/溢出规则"
    //
    // 修前状态（对抗审 ★ 判 REWORK 的实质发现①，复核属实）：`emitApprovalRequestIfPossible` 对
    // **每一条**到达的审批都直接登记进 `pendingApprovalsByReqID` 并立刻 `continuation.yield`，
    // 没有 active/FIFO/有限深度任何一个概念；`EventMapping.swift` 的
    // `buildApprovalBufferResolvedEvent` 自己的文档注释也承认"本轮仍未接入任何真实触发路径"。

    /// FIFO 缓冲队列深度——D1 §6.2 要求"实现选定一个有限值并**文档化**"，这里就是那个文档化的位置。
    ///
    /// **取 8 的依据**（不是随手一个数）：
    ///  - **下界**：必须 ≥1，否则"缓冲"退化成"第二条就溢出直接 deny"，D1 明写的"不丢弃，缓冲/排队"
    ///    形同虚设。
    ///  - **上界的现实约束**：缓冲期内**内核侧的超时时钟照常跑**（D1 同节："适配器的『延迟暴露』只
    ///    影响调用方何时看到这条请求，不影响、也无法影响内核自己判定它是否超时"）。openclaw exec
    ///    审批默认超时 30 分钟（`DEFAULT_EXEC_APPROVAL_TIMEOUT_MS`，
    ///    `kernels/openclaw/src/infra/exec-approvals.ts:315`），而一个人对着卡片逐条裁决的现实节奏
    ///    是十几秒到一两分钟一条——排在第 9 位之后的请求，等轮到它时多半已经被内核判超时，缓冲它
    ///    只是把"必然的 buffered_timeout"推迟发生，不产生任何真实收益。8 条 ≈ 最坏情况下队尾仍有
    ///    十几分钟余量，落在"排队还有意义"的一侧。
    ///  - **fail-closed 取向**：D1 要求溢出时"直接 deny"而不是无限增长本地状态。深度越大，本地状态
    ///    与内核真实状态偏离的窗口越长；8 是一个能被人肉核对、也不至于把内存/心智负担做大的量级。
    ///
    /// 测试可用 `testSupportSetApprovalBufferDepth` 覆盖成一个更小的值，用 3~4 条帧就能驱动完整的
    /// 「active / 缓冲 / 溢出 / 提升」四条路径，不用真的喂 10 条（覆盖值只影响本 actor 实例）。
    static let approvalBufferDefaultDepth = 8
    private var testSupportApprovalBufferDepthOverride: Int?
    private var approvalBufferDepth: Int { testSupportApprovalBufferDepthOverride ?? Self.approvalBufferDefaultDepth }

    /// 一条**尚未呈现给调用方**的缓冲审批。刻意存"构造 approval_request 所需的三份原始输入"而不是
    /// 存一个已经构造好的 `EventMessageUnion`：
    ///  - `seq` 必须在**真正 yield 的那一刻**才铸造（`nextSeq` 是 per-run 单调递增的交付序号，提前
    ///    铸造会让它与实际交付顺序错位）；
    ///  - `ts`/`timeoutMS` 全部来自内核自己的时间戳（`payload.updatedAtMs` 与
    ///    `approval.expiresAtMs - approval.createdAtMs`，见 EventMapping.swift ④），提升时重新映射
    ///    得到的**绝对到期时刻与原始请求完全一致**——这正是 D1 §6.2 "提升时应据实反映其内核侧计时器
    ///    已消耗的时间/剩余可用时间……不得虚构一个『刚刚开始计时』的假象"要求的效果，而且是靠"不碰
    ///    时间戳"天然达成的，不需要额外算一次剩余时间。
    private struct BufferedApprovalRequest {
        let reqID: String
        let payload: JSONObject
        let runID: String
        let toolCallID: String
    }

    /// 每个 session 当前唯一的 active pending 审批 reqId——D1 §6.2 "同一 session 同一时刻只暴露一个
    /// active pending 审批请求"这条约束的**唯一**执行点（`emitApprovalRequestIfPossible` 的准入判断
    /// 读它，`promoteNextBufferedApprovalIfPossible` 在终态后清它并提升下一条）。
    private var activeApprovalReqIDBySessionID: [String: String] = [:]
    /// 每个 session 的 FIFO 缓冲队列（队头 = 最早到达 = 下一个被提升的候选）。
    private var bufferedApprovalsBySessionID: [String: [BufferedApprovalRequest]] = [:]

    // MARK: - rounds/0015 返工②：approval.resolve 的 per-reqId in-flight 串行化
    //
    // 对抗审 ★ 的实质发现②（复核属实）：`stop()` 进入 `stopInProgress` 后对所有 pending 发强制
    // deny，而 `forceDenyPendingApprovalsBeforeStop` 里每次 `await request("approval.resolve")`
    // 都是一个**重入点**——actor 在这里让出隔离，用户此刻点下审批卡片上的按钮，
    // `respondApproval()` 会看到 `pendingApprovalsByReqID[reqID]` **仍然存在**（该表要等 RPC 返回
    // 才摘条目），于是对**同一个 reqId** 发出第二条 `approval.resolve`。
    //
    // **既有 NOTE-A（第 878-880 行附近）已经否决过的做法不再重做**：那里论证过"让同步 wire
    // dispatch 路径用 `Task { await ... }` fire-and-forget 去发 deny"会重新引入"stop() 不知道这个
    // detached Task 有没有跑完"的竞态。本节的修法**不是**再来一个看不见的 detached Task，而是给每个
    // reqId 一个**在 actor 状态里可见**的 in-flight 记录：
    //   - 谁先拿到这个 reqId 的 in-flight 槽位，谁就是唯一发出 `approval.resolve` 的人；
    //   - 后到者**不发第二条 RPC**，而是 await 该槽位释放，然后重新读 `pendingApprovalsByReqID`
    //     按既成事实行事（D1 §6.2 失败分支 3 的原文要求："适配器尝试强制终态化时收到
    //     `approval_not_pending`，直接放弃这一步……该 reqId **不**出现在
    //     `TurnCompleteEvent.forceResolvedApprovals` 里"）；
    //   - `forceDenyPendingApprovalsBeforeStop` 的 drain 收敛条件因此从"pending 表为空"收紧为
    //     "pending 表为空 **且** 该 session 没有任何在途 `approval.resolve`"——这样既覆盖人工响应，
    //     也覆盖下面缓冲溢出那条**确实**由 detached Task 发起的 deny（它在派生 Task **之前**就同步
    //     登记了 in-flight 槽位，所以 stop() 看得见、等得到，不是 NOTE-A 否决的那种不可见形态）。
    enum ApprovalResolveOrigin: String {
        /// D1 §2.6 `respondApproval()`——用户的人工决策。
        case manual
        /// D1 §6.2 M3 定序——`stop()` 在 `sessions.abort` 之前的强制 deny。
        case forceDenyOnStop
        /// D1 §6.2 缓冲溢出——超过 `approvalBufferDepth` 时适配器自己发起的 fail-closed deny。
        case queueOverflowDeny
    }
    private struct ApprovalResolveInFlight {
        let origin: ApprovalResolveOrigin
        let sessionID: String
        /// rounds/0016（T-096 第 3 项）：同一个 reqId 可以被**先后**占用多次槽位（强制 deny 失败后
        /// 的幂等 deny 重试就是这个形态），`epoch` 是这次占用的唯一标识。有界等待到期/权威 terminal
        /// 结束掉第 N 次占用之后，那条**孤儿 RPC** 仍可能在几十秒后姗姗来迟地返回——它带着自己的
        /// epoch 回来，与当前槽位不匹配时被如实丢弃，绝不会把一个陈旧结果投递进第 N+1 次重试的
        /// 等待里（那会让"重试成功了吗"这个判断建立在上一次的响应上）。
        let epoch: UInt64
        var waiters: [CheckedContinuation<Void, Never>] = []
        /// 有界等待的收件箱：RPC 返回、有界等待到期、权威 terminal 到达，三条路径**恰好一条**能
        /// resume 它（`settled` 是那道闸）。
        var settle: CheckedContinuation<Result<JSONObject, Error>, Never>?
        var settled = false
        /// 防御性：万一 settle 在 `withCheckedContinuation` 注册之前就发生（actor 隔离下不可能——
        /// 派生两个 Task 与注册收件箱之间没有 await——但不假装它绝无可能），结果先存这里，注册时
        /// 立刻取走，不丢。
        var stashedResult: Result<JSONObject, Error>?
    }
    private var approvalResolveInFlightByReqID: [String: ApprovalResolveInFlight] = [:]
    /// 反向索引，供 `forceDenyPendingApprovalsBeforeStop` 的 drain 收敛条件按 session 判空。
    private var approvalResolveInFlightReqIDsBySessionID: [String: Set<String>] = [:]
    private var approvalResolveEpochCounter: UInt64 = 0

    /// **`approval.resolve` 的有界等待上限**（rounds/0016，T-096 第 3 项）。
    ///
    /// 修前：`respondApproval()`/强制 deny/溢出 deny 三条路径打的都是 `request(method:params:)`，
    /// 那是一个**无界** `withCheckedThrowingContinuation`——只有"响应到达"和"transport 断开"两种
    /// 唤醒源。网关进程还活着、WS 还连着、但这条 `approval.resolve` 永远不回应答（服务端 handler
    /// 卡住、或响应帧在中间环节丢失）时，调用方永久挂起，该 reqId 的 in-flight 槽位永久占位，
    /// `stop()` 的 drain 收敛条件（"pending 空 **且** 无在途 resolve"）也就永远不成立——**整条
    /// stop() 跟着挂死**。
    ///
    /// **取 30 秒的依据**：这个值不是"审批的超时"（那是内核的 30 分钟 `DEFAULT_EXEC_APPROVAL_
    /// TIMEOUT_MS`，与本值无关），而是"一次本机 RPC 往返的合理上限"。同文件既有的 `stop()` 等待
    /// 终态用的是 `stopTimeoutSeconds`（默认 30，见 `testSupportSetStopTimeoutSeconds`），量级一致；
    /// 一次 `approval.resolve` 在正常网关上是毫秒级往返，30 秒已经比最坏情况宽出三个数量级。
    ///
    /// **到期不等于失败判据放宽**：到期时抛 `approvalResolveTimedOut`，明确表示"内核侧状态未知"
    /// ——不谎报成功（不会有任何 `approval_buffer_resolved`/兑现核验被跳过），也不谎报"已拒绝"。
    /// 单位是**毫秒**而不是秒：生产取值是 30_000（= 30 秒），测试可覆盖成 120 毫秒之类的量级，
    /// 让"有界等待到期"这条反证在毫秒内跑完而不是真的睡 30 秒——秒粒度的旋钮会逼着测试要么睡满
    /// 一秒、要么把生产语义扭曲成"0 秒超时"。
    static let approvalResolveBoundedWaitDefaultMS = 30_000
    private var testSupportApprovalResolveBoundedWaitMSOverride: Int?
    private var approvalResolveBoundedWaitMS: Int {
        testSupportApprovalResolveBoundedWaitMSOverride ?? Self.approvalResolveBoundedWaitDefaultMS
    }

    // MARK: - rounds/0016（T-096 第 2 项）：`FORCE_DENY_PENDING_KERNEL_ACK` 持久态
    //
    // T-096 原文："显式持久化 `FORCE_DENY_PENDING_KERNEL_ACK`，强制 deny 失败后**只允许幂等 deny
    // 重试**。"
    //
    // 修前的洞：`forceDenyPendingApprovalsBeforeStop` 在"RPC 抛错"或"终态不是 denied"时直接
    // `throw`，`pendingApprovalsByReqID[reqID]` 原样留着（那是刻意的——审批在内核侧可能仍 pending）；
    // 于是**用户随后点"允许一次"会被完整放行**：`respondApproval()` 看到 pending 表里有这一条，
    // 四道关卡逐条通过，一条 `approval.resolve(allow-once)` 就发出去了。也就是说，一次**已经决定
    // 拒绝、只是没打成**的审批，可以被随后的人工操作翻成"允许"，命令真的会执行。这不是理论风险：
    // stop() 的强制 deny 本来就是"用户放弃这次会话"的语义，此刻放行是语义反转。
    //
    // 本态就是那道闸：只要它存在，`respondApproval()` 对任何 allow 档位一律同步拒绝
    // （`ApprovalDecisionError.forceDenyPendingKernelAck`），只放行 deny——而 deny 重试是**幂等**
    // 的：openclaw 侧同一条审批的 deny 打两次，第二次会走 `record.status !== "pending"` 分支回
    // `ok:true + applied:false + 终态快照`（approval.ts:462-475），不会产生第二次副作用。
    //
    // **为什么这个态要能在 pending 表之外独立存在**：缓冲溢出的 deny 针对的 reqId **从未进过
    // pending 表**（它从未被呈现给调用方）。如果这个态寄生在 pending 表上，溢出 deny 失败就无处
    // 记录，也就没有任何重试的抓手。所以它自带 `runID/openclawKind/allowedDecisions`——重试所需的
    // 全部输入，在**发起第一次强制 deny 的那一刻**就冻结下来。
    private struct ForceDenyPendingKernelAck {
        let sessionID: String
        let runID: String
        let openclawKind: String
        let allowedDecisions: [String]
        let origin: ApprovalResolveOrigin
        /// 实际观察到的失败形态（RPC 错误文本 / `applied:false` + 终态快照 / 终态非 denied），
        /// 原样进错误描述与事件 message——调用方看到的是"发生了什么"，不是一句"失败了"。
        var observedFailure: String
        var retryCount: Int = 0
    }
    private var forceDenyPendingKernelAckByReqID: [String: ForceDenyPendingKernelAck] = [:]
    /// 反向索引：session 结束时批量清（同 `pendingApprovalReqIDsBySessionID` 的模式）。
    private var forceDenyPendingKernelAckReqIDsBySessionID: [String: Set<String>] = [:]

    // MARK: M3（D1 §6.2 stop-path 强制 deny）—— approval_request 已经真正产出给调用方之后的"pending，
    // 等待人工决策"态
    //
    // 上面 `agentApprovalInfoByApprovalID`/`pendingSessionApprovalByApprovalID` 只是 join 之前的临时
    // 缓冲区——一旦 join 成功、`emitApprovalRequestIfPossible` 把 approvalRequest 真正 yield 给调用方，
    // 这两张表的条目就被移除了，不再追踪"这个 reqId 现在处于 pending、还没人给出决策"这件事。
    // **rounds/0015 起这个态有两个消费者**（此前只有一个）：`respondApproval()`（D1 §2.6，A 块实现，
    // 人工决策的正常出口）与 `stop()` 的强制 deny（D1 §6.2 M3 定序 + §6.3 stop 黑名单批量 deny，
    // 用户从不决策时的兜底出口）。两者都以这张表为"该 session 名下当前还有哪些审批在 pending"的唯一
    // 权威来源，且都在内核确认终态后把条目摘掉。`openclawKind` 存真实的 openclaw 侧 kind
    // （"exec"/"plugin"/"system-agent"，不是 D2 收窄后的 KindElement）——见
    // `forceDenyPendingApprovalsBeforeStop` 的文档注释。
    /// rounds/0015 A/B：新增 `sessionID` 与 `allowedDecisions` 两个字段。
    /// - `sessionID`：`respondApproval()` 要拒绝"拿 session A 的 handle 去回应属于 session B 的
    ///   审批"这种调用错误，需要知道这个 reqId 的归属会话（此前只有反向索引
    ///   `pendingApprovalReqIDsBySessionID`，正向查不到归属）。
    /// - `allowedDecisions`：**这条审批自己携带的那一份**（openclaw 原始字符串，如
    ///   `["allow-once","deny"]`），是 B 块"客户端侧发出前校验"的唯一依据。**刻意不硬编码**：
    ///   同一个内核在 `ask=always` 与其它配置下给出的集合不同（见 EventMapping.swift
    ///   `makeApprovalResolveParams` 文档注释第 1 条），硬编码任一个都会在另一种配置下把用户的
    ///   "允许"送进服务端的 `forceMalformedDeny`、静默变成 deny。
    private struct PendingApprovalAwaitingDecision {
        let runID: String
        let openclawKind: String
        let sessionID: String
        let allowedDecisions: [String]
    }
    private var pendingApprovalsByReqID: [String: PendingApprovalAwaitingDecision] = [:]
    /// 反向索引：session 结束时批量清理上面这张表——同款模式，仿 `approvalIDsBySessionID`（M5）。
    private var pendingApprovalReqIDsBySessionID: [String: Set<String>] = [:]

    /// NOTE-A（T-049 grok 对抗审复核）：force-deny drain 循环（见 `forceDenyPendingApprovalsBeforeStop`）
    /// 的迭代轮次上限——防御性兜底，不是 D1 协议要求的具体数值。D1 §9 一 session 一次一个 active run +
    /// stop() 已经把该 session 锁进 `stopInProgress`（阻塞新 `send()`，不会有新 run）的前提下，drain
    /// 循环每一轮只可能因为"仍在这个即将被 abort 的、唯一的 run"持续产生新的审批请求而继续——正常场景
    /// 一两轮内必然收敛为空；这里选 50 只是给"理论上不该出现但不能假装不可能"的极端场景（比如一个
    /// bug 让某个 run 疯狂连续请求审批）一个诚实的上限，超限时如实 throw，不是静默死循环。
    private static let forceDenyDrainDefaultMaxRounds = 50

    // MARK: - Test-only：拦截 RPC（不需要真实 WebSocket 连接）
    //
    // M3/M6 rework：真 actor 级测试需要驱动真实的 send()/stop() 方法体本身（包括它们发起的
    // sessions.send/sessions.abort/sessions.delete RPC），而不是像上一轮那样直接 seed 内部状态、
    // 绕开方法体——但这个项目没有真实网络可用。`testSupportRPCResponders` 按 RPC method 名注册一个
    // "request(method:) 被调用时应该返回什么/抛什么错"的闭包；`request()` 内部命中该表时直接走
    // 这条路径，完全不碰 `task`（未连接的 `freshClient()` 场景下 task 本来就是 nil）。生产路径不受
    // 影响——这张表默认为空，`request()` 只有命中表项时才短路。
    private var testSupportRPCResponders: [String: @Sendable (JSONObject) async throws -> JSONObject] = [:]

    // MARK: F3 — per-run 单调 seq 域
    private var seqByRunID: [String: Int] = [:]
    /// 没有 runId 的事件（sessionEnd 等）退化为按 session 走一个独立递增序列——D1 只承诺"同一 runId
    /// 内排序"，这里只是让无 run 归属的事件也至少非递减，不是额外的契约承诺。
    private var seqFallbackBySessionID: [String: Int] = [:]

    public private(set) var lastHandshakeScopes: [String] = []
    public private(set) var lastHandshakeProtocol: Int?

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - 连接 + 握手（recipe §2）

    /// 建立 WS 连接并完成 challenge -> connect 握手，返回 hello-ok 里协商到的 scopes——供调用方
    /// 核验"确实拿到了 operator.write/operator.admin 等写权限"（recipe §2 里最容易踩的坑：
    /// client.id/mode 不是 "cli"/"cli" 时握手仍会成功，但 scopes 会被服务端清空）。
    public func connect() async throws -> [String] {
        let t = urlSession.webSocketTask(with: endpoint)
        self.task = t
        t.resume()
        receiveLoopTask = Task { await self.receiveLoop() }

        let challenge = try await waitForNextEvent(named: "connect.challenge")
        prettyPrint("RECV connect.challenge", challenge)

        // 握手 params 逐字段对照 recipe §2 末尾"一次完整、可复制的最小 connect 请求"。
        let connectParams: JSONObject = [
            "minProtocol": 3,
            "maxProtocol": 4,
            "client": [
                "id": "cli",
                "version": "0.0.1",
                "platform": "darwin",
                "mode": "cli",
            ] as JSONObject,
            // rounds/0016：`caps` 从空数组改为声明 **`"exec-approvals"`**——这是"壳能不能真的收到
            // exec 审批请求"的开关，不是装饰性字段。
            //
            // 内核侧判定在 `kernels/openclaw/src/gateway/server-request-context.ts:116-142`
            // `canDeliverApprovals()`：`operator.admin`/`operator.approvals` 只是**第一道**门（我们
            // 本来就过），第二道门要求下面四者之一为真——`internal.approvalRuntime`（服务端自造的
            // 内部客户端，外部连不上）、`client.id ∈ {openclaw-control-ui}`（全类型）或
            // `{openclaw-macos, openclaw-ios, openclaw-android}`（仅 exec）、`caps` 含
            // `"approvals"`（全类型）或 `"exec-approvals"`（仅 exec）。我们两道都不占，于是
            // `getApprovalClientConnIds()` 永远不把我们算进收件人集合。
            //
            // **后果不只是"少收一条事件"**：`approval-shared.ts:535-556`，当一次审批既没有
            // approval-client、又没有 forwarder/turn-source 路由时，内核**立刻**
            // `manager.expire(id, "no-approval-route")` 把这条审批判死。也就是说没有这个 cap 时，
            // 壳看到的是"审批刚 pending 就 terminal"，不是"审批弹不出来"。
            //
            // 为什么是 `exec-approvals` 而不是别的两种改法：
            //  - **不改 `client.id`**：`"openclaw-macos"` 是一方已发布客户端的稳定 id（同文件
            //    `EXEC_APPROVAL_CLIENT_IDS`），冒名会连带继承内核对该 id 的其它假定（推送/设备
            //    绑定等），不诚实也不安全。`canDeliverApprovals` 上方注释原文写明 caps 这条路
            //    正是给 "newer non-UI bridges" 准备的——我们就是。
            //  - **不声明 `"approvals"`**：那是**全类型**审批（exec/plugin/system-agent）的承诺，
            //    而本壳只实现了 exec 审批 UI（见 EventMapping.swift ④ 与 SessionStore 审批卡片），
            //    声明全类型属于过度承诺，会招来我们渲染不了的 plugin/system-agent 审批。
            //  - openclaw 自己的非 UI 桥接就是这么声明的：`src/acp/server.ts:152`
            //    `caps: [GATEWAY_CLIENT_CAPS.EXEC_APPROVALS, GATEWAY_CLIENT_CAPS.TOOL_EVENTS]`。
            //
            // 字面量取自 `packages/gateway-protocol/src/client-info.ts:83`
            // `GATEWAY_CLIENT_CAPS.EXEC_APPROVALS = "exec-approvals"`；`caps` 的 wire schema 是
            // `Type.Optional(Type.Array(NonEmptyString))`（`schema/frames.ts:45`），不是枚举，
            // 未知取值不会被握手拒绝——所以这里的值必须逐字对上，写错了不会报错、只会静默失效。
            "caps": ["exec-approvals"] as [String],
            "role": "operator",
            "scopes": ["operator.admin"] as [String],
            "auth": ["token": token] as JSONObject,
        ]
        let hello = try await request(method: "connect", params: connectParams)
        prettyPrint("RECV hello-ok (connect response payload)", hello)

        if let proto = hello["protocol"] as? Int {
            lastHandshakeProtocol = proto
        }
        if let auth = hello["auth"] as? JSONObject, let scopes = auth["scopes"] as? [String] {
            lastHandshakeScopes = scopes
        }
        return lastHandshakeScopes
    }

    /// NOTE-3（整洁度，两端核对一致）：C# 侧 `Disconnect()` 原来只 `Abort()` 了 `ClientWebSocket`
    /// 却没有 `Dispose()`（未释放底层非托管资源），已在 C# 侧补上。Swift 这里的等价物是
    /// `URLSessionWebSocketTask.cancel(with:reason:)`——它同时中断挂起的 IO 并让 URLSession 释放
    /// 该 task 的底层资源，是 Foundation 侧“Abort+Dispose”合一的正确收尾调用；`task = nil` 之后
    /// ARC 释放最后一个引用。核对结论：两端在这个方法里语义已经一致，Swift 侧不需要额外改动。
    public func disconnect() {
        receiveLoopTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    // MARK: - KernelClient conformance

    public func createSession(config: Config) async throws -> SessionHandle {
        // D1 §2.1 步骤 1：adapter 本地预分配 sessionId（spec 原文："adapter 本地生成一个 UUID 作为该
        // session 的 sessionId，此时原生内核会话尚不存在"，
        // `~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md:179`）。B1（rounds/0013）
        // 把这一步从 RPC **之后**（旧代码原本在 result 落地之后才分配）挪到 RPC **之前**——除了更
        // 贴合 spec 时序，还让下面的 label 铸造能直接引用它（见 makeSessionLabel 文档注释，
        // OpenclawWire.swift）。RPC 失败时这个 UUID 单纯被丢弃（从未写入 kernelKeyBySessionID、也从未
        // 返回给调用方），没有状态污染。
        let ourSessionID = UUID().uuidString

        // openclaw 侧本轮只透传 label(+model)。D2 Config 的 cwd/newapiEndpoint/toolset/sandbox/
        // approvalProfile/resume 这些字段本轮未接入 openclaw 原生 CreateSessionConfig 的等价物
        // ——两边字段集并非天然一一对应（openclaw 的 sessions.create 走它自己的 schema，见 recipe
        // §3），完整字段级映射留给后续轮次；这里如实标注，不假装已经打通。
        //
        // B1（rounds/0013）：label 曾经硬编码成字面量 "sg4-kernel-client-l1"——openclaw 侧对同一
        // store 内全部会话强制 label 唯一（见 makeSessionLabel 文档注释，OpenclawWire.swift），硬编码
        // 字面量导致同一 openclaw state 目录下第二次 createSession() 必然撞名，RPC 直接
        // `INVALID_REQUEST: label already in use`（本轮已 UI 侧 + CLI 侧双路径实证）。现在按
        // ourSessionID + 本次调用时刻铸造，保证互不相同，同时人眼可辨认。
        var params: JSONObject = ["label": makeSessionLabel(ourSessionID: ourSessionID, createdAt: Date())]
        if let model = config.model {
            params["model"] = model
        }
        let result = try await request(method: "sessions.create", params: params)
        prettyPrint("RECV sessions.create result", result)

        guard let kernelKey = result["key"] as? String else {
            throw KernelClientError.protocolMismatch("sessions.create result missing 'key' field")
        }
        let kernelSessionID = result["sessionId"] as? String

        // 不复用 openclaw 自己返回的 sessionId——两者语义不同（前者是 KernelPort 层面的稳定寻址锚点，
        // 早于原生会话存在；后者是内核自己认得的原生 id），本实现如实保留这个区分，写入
        // SessionHandle.kernelSessionId 的是 openclaw 的 `key`（后续 subscribe/abort/delete 真正
        // 需要用它寻址,不是 `sessionId` 字段）。
        kernelKeyBySessionID[ourSessionID] = kernelKey

        // billing.tokenRef 本轮是占位符——SG-4 没有实现 D1 §7 的 newapi token 铸造（那是 createSession
        // 内部执行序列步骤 2，需要真正调用 newapi POST /api/token/），如实标注，不虚构一个看起来
        // "真实"的值掩盖这个缺口。
        return SessionHandle(
            billing: Billing(tokenRef: "TODO-sg4-no-newapi-token-minted"),
            createdAt: Date(),
            kernel: .openclaw,
            kernelSessionID: kernelSessionID ?? kernelKey,
            sessionID: ourSessionID
        )
    }

    /// D1 §2.2 send()。适配为 openclaw `sessions.send`（recipe §3.3 params:
    /// `{key, agentId?, message, thinking?, attachments?, timeoutMs?, idempotencyKey?}`）。
    ///
    /// **返回语义**（SG-5 实测坐实）：`sessions.send` 的 RPC 响应是一次同步 ack，形状
    /// `{"runId":"...","status":"started","messageSeq":1}`——不是模型的最终输出。真正的 agent
    /// 输出全部经由已建立的 `subscribe()` 事件流异步到达。本实现只取 wire 响应的 `runId` 字段构造
    /// `SendResultPayload(runID:)`。
    ///
    /// **F1 rework**：D1 v3.1 §9.3（v3.6 继承）要求 send() 遵守 session 级 `send_pending` 互斥锁——
    /// 同一 session 不允许两个 `send()` RPC 同时在途。上一轮只在 actor 内保存了 runId 缓存但没有
    /// 锁本身，两个并发 `send()` 都能进入 `await request(...)`，谁的 ack 先回来谁就"赢"，与调用
    /// 顺序无关，导致 `lastRunIDBySessionID` 可能被"后发起但先返回"的调用覆盖成错误值。本轮加锁：
    /// 进入函数时若锁不是 idle 一律 reject(session_locked)，否则在**第一次 await 之前**（因此
    /// actor 不会在这个检查-设置对之间被重入）把锁设成 send_pending，RPC ack 到达（无论成功失败）
    /// 后释放回 idle。
    ///
    /// **rounds/0012 ② 返工：send 侧屏障**（推翻上一版"subscribe() 自己等 ack"的修法，理由见
    /// `subscribe()` 文档注释）。函数体第一行 `await awaitSubscriptionRpcDispatchIfPending(...)`：
    /// 若这个 session 有一个刚调用过、尚未 dispatch 底层 RPC 的 `subscribe()` 在途，先等它 dispatch
    /// 完再往下走；否则立即继续，不引入任何延迟。
    ///
    /// **为什么只等"RPC 已 dispatch"、不等"RPC 已 ack"**（这是本轮设计里唯一违反最初建议方向的
    /// 一处，如实记录取舍）：`evidence/item2-subscribe-race.md` 判定的竞态根因是**服务端**
    /// `void runWithDiagnosticTraceContext(...)`（fire-and-forget）——`sessions.messages.subscribe`
    /// 与 `sessions.send` 两个 handler 并发处理，唯一能从客户端**确证**服务端已经完成订阅登记的
    /// 信号就是收到订阅 RPC 的响应（ack）。但 `app/contracts/d2/fixtures/` 下**除
    /// `basic/create-session-subscribe-message-delta.json` 外的全部 10 个**用到 `subscribe` 的
    /// fixture（`session-lock/send-in-flight-send-pending.json`、`operation-outcome/
    /// stop-no-active-run-succeeded.json` 等——本轮逐个 grep 核对过 timeline，穷尽，不是抽样）都
    /// **从未给 `subscribe` 提供 `mock_response`**，却要求随后的 `send`/`stop` 正常 resolve。这些
    /// fixture 不在本轮允许改动的范围内（硬约束：不改 `app/contracts/` 下任何文件）。若 send()
    /// 真的等 ack，这些 fixture 会在等一个永远不会到达的响应，CI 平价 runner 必然无法达到
    /// 12/0/1——**已实测验证**：本轮开工前跑了一次现有（错误方向）实现的 CI 命令，`swift-runner`
    /// 直接悬挂不退出（比用户报告的"4/8/1"更差，多半是当时的观测方式不同）。因此"等 ack"在**当前
    /// CI 契约测试模型**下不可行，只能退而求其次：**等"RPC 已 dispatch"**——即 `subscribe()` 背景
    /// Task 真正调用 `request(...)` 前的最后一刻（见 `markSubscriptionRpcDispatched`）。
    ///
    /// **这不是"看起来做了点什么"的假修复，但也不是完整修复，如实两面都说**：
    /// - **真实收益**：closes 掉"客户端自己都不能保证 `sessions.messages.subscribe` 帧先于
    ///   `sessions.send` 帧被交给底层传输"这个更差的失效模式——没有这道屏障时，`subscribe()` 背景
    ///   Task 何时真正跑到 `request()` 完全取决于 Swift actor 调度，`send()` 若紧随其后调用，
    ///   结构上可能在订阅 RPC 连**发都没发**的情况下就把 `sessions.send` 发出去（`evidence/
    ///   item2-subscribe-race.md` 承认两次真实观测都是订阅帧领先，但"结构上仍可能反过来"）。加了
    ///   屏障后这一点变成确定性保证，不再依赖调度巧合。
    /// - **未闭合的残余窗口**：即使客户端确定性地保证了"订阅 RPC 先 dispatch"，服务端那两个 handler
    ///   仍然是并发处理、彼此不等待——`evidence/item2-subscribe-race.md` 判定的"「subscribe 帧到达」
    ///   到「其 handler 抵达 dispatch」"这段窗口本身发生在**服务端**，不受客户端 dispatch 顺序影响。
    ///   真正完整闭合它，需要 send() 等 ack（本设计已论证在当前 CI 契约测试模型下不可行）或服务端
    ///   自己序列化处理——**两者都超出本轮范围**，如实记为已知残余风险，留给后续轮次（要么先改
    ///   fixture 让它们能表达"等 ack"的场景，要么去服务端修）。
    ///
    /// **`stop()` 复用同一屏障**（见该方法文档注释）——两者是本轮判断"哪些方法需要等"后的结论，
    /// `interrupt()`/`respondApproval()` 仍是 TODO 桩、没有任何 RPC 可 dispatch，不需要、也没有加。
    public func send(session: SessionHandle, input: Input) async throws -> SendResultPayload {
        await awaitSubscriptionRpcDispatchIfPending(sessionID: session.sessionID)
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        let currentLock = lockStateBySessionID[session.sessionID] ?? .idle
        guard currentLock == .idle else {
            throw KernelClientError.rpcRejected(
                code: "session_locked",
                message: "send() rejected: session \(session.sessionID) lock state is \(currentLock), expected idle (D1 v3.1 §9.3)"
            )
        }
        lockStateBySessionID[session.sessionID] = .sendPending
        defer {
            // send_pending 只是"等待 kernel ack"的极短窗口——ack 到达（无论成功失败）后立刻释放。
            if lockStateBySessionID[session.sessionID] == .sendPending {
                lockStateBySessionID[session.sessionID] = .idle
            }
        }

        var params: JSONObject = [
            "key": kernelKey,
            "message": resolveSendMessageText(from: input),
            "timeoutMs": 0,
        ]
        // F2 rework：openclaw `gateway/server-methods/attachment-normalize.ts:29-56`
        // （`normalizeRpcAttachmentsToChatAttachments`）只保留带 `content` 字段（base64 或字符串）
        // 的附件，`.filter((a) => a.content)` 会把上一轮发送的 `{mimeType,path}` 形状直接丢弃（无
        // content 字段）——见 `server-methods.test.ts:2693-2699` 明确验证这一点。本轮改为读取
        // `Part.path` 指向的本地文件、base64 编码后塞进 `content`；读不到文件就诚实跳过这一个
        // attachment（不编造 content，也不让整个 send() 失败——可能只是这一个 part 路径失效）。
        if input.kind == .structured, let parts = input.parts {
            // encodeAttachmentForWire 是 OpenclawWire.swift 里的纯函数（F2），不依赖 actor 状态，
            // 方便 FrameReplayTests.swift 直接单测。
            let attachments: [JSONObject] = parts.compactMap { part -> JSONObject? in
                guard part.kind != .text else { return nil }
                return encodeAttachmentForWire(part)
            }
            if !attachments.isEmpty {
                params["attachments"] = attachments
            }
        }

        let result = try await request(method: "sessions.send", params: params)
        prettyPrint("RECV sessions.send result", result)

        guard let runID = result["runId"] as? String else {
            throw KernelClientError.protocolMismatch("sessions.send result missing 'runId' field")
        }
        lastRunIDBySessionID[session.sessionID] = runID
        runIDsBySessionID[session.sessionID, default: []].insert(runID)
        return SendResultPayload(runID: runID)
    }

    /// D1 Input -> openclaw `sessions.send.message`（纯文本字符串）的最小转换。`kind:.text` 直接用
    /// `input.text`；`kind:.structured` 把 `parts` 里 `kind:.text` 的段落用换行拼接（非文本 part
    /// 走上面 attachments 分支，不混进正文），三者都拿不到文本时退化为空字符串而不是抛错——openclaw
    /// 的 `SessionsSendParamsSchema.message` 是必填 `Type.String()`，允许空串，比在这里主观拒绝更
    /// 贴近"如实转发调用方输入"的适配器职责。
    private func resolveSendMessageText(from input: Input) -> String {
        if input.kind == .text {
            return input.text ?? ""
        }
        let texts = (input.parts ?? []).compactMap { part -> String? in
            guard part.kind == .text else { return nil }
            return part.text
        }
        return texts.joined(separator: "\n")
    }

    /// D1 §2.3 subscribe。
    ///
    /// **rounds/0012 ② 二次返工（推翻上一版"subscribe() 自己等 ack"的修法）**：上一版把这个方法改成
    /// 内联 `await` `sessions.messages.subscribe` RPC、等它真正落地（或失败）才 `return stream`——
    /// 这个方向被证明是错的，两条独立理由：
    ///
    /// 1. **违反 D1**：`KernelClient.swift` 协议签名的文档注释明文写着——"D1 的 TS 签名里 subscribe
    ///    本身不是 Promise（`subscribe(session): AsyncStream<KernelEvent>`）……语义上仍然等价于
    ///    『拿到一个事件流』……不因为这一处签名调整而改变 D1 的行为语义"。等 ack 才 return，就是把
    ///    "拿到一个事件流"变成了"拿到一个已确认的事件流"，行为语义变了。
    /// 2. **打穿 CI**：`app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift`
    ///    的 `performClientCall` 对 `subscribe` 是**直接 `await client.subscribe(session:)`**（不像
    ///    `send`/`stop` 那样包一层背景 `Task`，见该文件 `case "subscribe":` 与其上方注释——原文
    ///    "真实 subscribe() 同步（在第一次 await 之前）就把 eventContinuations[sessionID] 建好、
    ///    立即返回事件流……若 fixture 没提供 mock_response，gate 永远悬挂也不影响后续任何事件
    ///    观察"）。`subscribe()` 一旦自己先悬挂住等 ack，整条 fixture 时间线推进不下去——本轮开工前
    ///    实测过一次（`swiftc` 编出当时的错误方向实现、跑 CI 同款命令）：进程直接悬挂不退出，比
    ///    此前报告的"4/8/1"更差。
    ///
    /// **本轮改回原形态**：本地事件续体仍然同步注册（`eventContinuations[ourSessionID] =
    /// continuation`，在任何 `await` 之前），真正发 `sessions.messages.subscribe` RPC 的逻辑仍然
    /// 包在一个**不等待的背景 `Task`** 里，`subscribe()` 本身几乎立即返回——D1 契约、CI 兼容性都
    /// 恢复原状。
    ///
    /// **但订阅竞态本身不是假问题**——`evidence/item2-subscribe-race.md`「返工结论」一节已经用
    /// openclaw 服务端源码判定坐实：`sessions.messages.subscribe` 与 `sessions.send` 的 handler 在
    /// 服务端 `void runWithDiagnosticTraceContext(...)`（fire-and-forget）下并发处理，谁先抵达
    /// `dispatch` 无序化保证。这次改为**换个位置**收口——在 `send()`/`stop()` 开头设一道屏障，而不是
    /// 卡在 `subscribe()` 自己身上。`subscribe()` 这边只新增两行配合：进入本方法同步前缀时调用
    /// `beginTrackingSubscriptionDispatch`（登记"这个 session 有一个尚未 dispatch 的订阅 RPC"），
    /// 背景 `Task` 里真正调用 `request(method:"sessions.messages.subscribe",...)` **之前**调用
    /// `markSubscriptionRpcDispatched`（登记完成、唤醒等待中的 `send()`/`stop()`）。完整设计取舍
    /// （尤其是"为什么只等『RPC 已 dispatch』、不等『RPC 已 ack』"，以及这个折衷放弃了什么）记在
    /// `send()` 的文档注释里，不在这里重复。
    ///
    /// **协议签名不带 `throws`**（见 `KernelClient.swift`：`func subscribe(session:) async ->
    /// AsyncThrowingStream<...>`，scope-lock 明文禁止改这 7 个方法签名）——因此订阅 RPC 失败（RPC
    /// 本身抛错，或响应体里 `subscribed:false`）**不能**让本方法向调用方抛错，只能塞进已经交给调用
    /// 方的这个 `AsyncThrowingStream`：`continuation.finish(throwing:)` 让它在第一次
    /// `for try await` 迭代时就抛出同一个错误。调用方现有的错误路径
    /// （`SessionStore.consumeEvents` 的 `session.streamError = describeError(error)` ->
    /// `SessionDetailView` 的红色横幅）原样覆盖这种情况，不需要新的错误通道。这一段行为原样保留自
    /// SG-4/SG-5，未受本轮任何一版改动影响。
    ///
    /// 本地事件续体（`eventContinuations[ourSessionID]`）**仍然在 RPC 之前、同步完成**——这一点没
    /// 变（`evidence/item2-subscribe-race.md` §1b 已实测坐实 `AsyncThrowingStream` 默认
    /// `.unbounded` 缓冲，先注册好续体，之后到达的帧不会因为消费者还没开始 `for try await` 而丢）。
    public func subscribe(session: SessionHandle) async -> AsyncThrowingStream<EventMessageUnion, Error> {
        let ourSessionID = session.sessionID
        let (stream, continuation) = AsyncThrowingStream<EventMessageUnion, Error>.makeStream()
        eventContinuations[ourSessionID] = continuation
        beginTrackingSubscriptionDispatch(sessionID: ourSessionID)

        Task {
            guard let kernelKey = await self.kernelKey(for: ourSessionID) else {
                // 这条 RPC 根本不会被发起——照样标记 dispatch，否则等待中的 send()/stop() 会永久
                // 卡住（它们自己紧随其后的 kernelKey 查找也会独立失败，这里只是不让它们死在屏障上）。
                await self.markSubscriptionRpcDispatched(sessionID: ourSessionID)
                continuation.finish(throwing: KernelClientError.protocolMismatch("unknown session \(ourSessionID)"))
                return
            }
            if let delayNanoseconds = await self.subscribeDispatchDelayNanosecondsForTesting() {
                // Test-only（见 `testSupportSetSubscribeDispatchDelay` 文档注释）——生产路径这里
                // 恒为 nil，下面这行不会被执行到。
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            await self.markSubscriptionRpcDispatched(sessionID: ourSessionID)
            do {
                // includeApprovals:true——不带这个 flag 收不到 session.approval 事件
                // （`SessionsMessagesSubscribeParamsSchema` 的 `includeApprovals` 是 opt-in，默认不
                // 推送），approvalRequest 映射的现场 grounding 全部建立在这个 flag 打开的前提上。
                let result = try await self.request(
                    method: "sessions.messages.subscribe",
                    params: ["key": kernelKey, "includeApprovals": true]
                )
                prettyPrint("RECV sessions.messages.subscribe result", result)
                if let subscribed = result["subscribed"] as? Bool, !subscribed {
                    continuation.finish(throwing: KernelClientError.protocolMismatch("subscribe returned subscribed:false"))
                } else {
                    // M1：消费 subscribe 响应里的 `approvalReplay`（authoritative 的当前 pending
                    // 审批快照，见下方 consumeApprovalReplay 文档注释）。
                    await self.consumeApprovalReplay(result, kernelKey: kernelKey)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    /// D1 §2.4 interrupt —— rounds/0020 起完整实现 `mode:"cancel"`（`steer`/`abort_and_resend` 显式
    /// 拒绝 `unsupported_interrupt_mode`，不静默当 cancel 处理，见下方"支持的 mode"一节）。
    ///
    /// **语义（scope-lock rounds/0020 §Round Objective/红线）**：中止当前 active run，**保留会话**。
    /// 这与 `stop()` 唯一的本质区别——`stop()` 是 `sessions.abort` **+** `sessions.delete`，还会发
    /// `SessionEndEvent(reason:'stopped')` 并 finish 掉事件流（`emitStopSessionEndAndFinish`）：会话
    /// 被销毁了。`interrupt(mode:"cancel")` 只做第一步：中止 run，`sessions.delete`/`session_end`/
    /// finish continuation 三者**一个都不做**——调用方在这次 interrupt 成功之后必须还能对同一个
    /// `session` 再次 `send()`。这条边界是本轮红线，破了就退化成了 `stop()`，本轮等于什么都没做。
    ///
    /// **与 `stop()` 的关系（scope-lock §五个必须先定死的取舍 ①）：各走各的路，不复用 `stop()` 的
    /// 函数体**——`stop()` 的方法体与 `sessions.delete`/`session_end`/事件流 finish 强耦合，硬塞一个
    /// `skipDelete` 布尔进去只会让一个已经很复杂、被几十条测试钉住的函数再长一个分支。这里新写
    /// `interrupt()`，只复用 `stop()` 下面的**部件**：
    ///   - `forceDenyPendingApprovalsBeforeStop`——D1 §6.2 M3 的强制 deny 定序对 interrupt 一字不差
    ///     地成立：审批还在 pending 时直接 abort，会留下"run 已中止、审批却还挂着"的不一致。
    ///   - `waitForPendingStopTerminal` / `PendingStop`（`pendingStops` 表）——等待 aborted-run 终态
    ///     确认的有界等待机制。**这里选择了"复用同一份共享状态"而不是"引入独立机制"**：`PendingStop`
    ///     新增了一个 `operationKind` 字段（见该 struct 文档注释），`handleAgentEvent` 的
    ///     aborted-lifecycle 分支因此对 stop()/interrupt() 触发的等待一视同仁——包括"transport 在
    ///     等待窗口内关闭"这条 `resolvePendingStopForTransportClose` 路径也是**免费**继承来的（不需要
    ///     为 interrupt() 单独重新实现一遍"transport 关闭时怎么办"，避免了独立机制之间未来行为漂移
    ///     的风险）。代价是 `emitOperationCompletedMirror`/`mapOpenclawAgentLifecycleToAbortTerminalEvents`
    ///     都要多接收一个 `operationKind` 参数——两处改动都已确认对 `stop()` 的既有调用点是逐字节不变
    ///     的（它们现在显式传 `.stop`，取值与修前硬编码的 `.stop` 完全相同）。
    ///
    /// **强制 deny 审批（scope-lock §取舍 ②）**：照做，一步不省——见上面对
    /// `forceDenyPendingApprovalsBeforeStop` 的引用，`approval.resolve` 必须严格先于 `sessions.abort`
    /// 被 dispatch（与 `stop()` 完全相同的定序保证，D1 §6.2 M3）。
    ///
    /// **`abortedRunId == nil` 时（scope-lock §取舍 ④）**：沿用 `stop()` 已经实证过的判定（见
    /// `stop()` 文档注释"M3"一节引用的现场证据，`scratchpad/openclaw-iso3` 隔离环境实测）——
    /// `sessions.abort` 诚实回报 `abortedRunId:null` 说明这个 run 早已自然结束，用户点了"中止"而它
    /// 已经停了，**目的达成即 succeeded**，不是错误；但仍要补一条 `operation_completed` 镜像，否则
    /// 只订阅事件流、不等 Promise 的观察者看不到这次操作的终态。**是否需要等待终态，由
    /// `sessions.abort` 自己的返回值（`abortResult["abortedRunId"]`）判断，绝不是本地缓存的
    /// `lastRunIDBySessionID`**——现场证据见 `stop()` 同一段文档注释，这里逐字沿用同一条判定，不重新
    /// 论证一遍。
    ///
    /// **支持的 mode（scope-lock §Scope for this round）**：本轮只实现 `mode:"cancel"`。`"steer"` 与
    /// `"abort_and_resend"` 必须显式拒绝 `unsupported_interrupt_mode`（D2 interrupt.schema.json 失败
    /// 通道点名的取值）——不静默当 cancel 处理，那正是本项目一直在修的"看起来支持、其实做了别的事"。
    /// 这个检查刻意放在**拿锁之前**：它是纯粹的输入校验，与"这个 session 此刻是否忙"无关，客户端传了
    /// 一个本轮压根不支持的 mode，不该逼它等到 session 恰好空闲才收到这个"你传的 mode 不支持"的答复。
    ///
    /// **订阅屏障（scope-lock §取舍 ⑨，`stop()` 文档注释原来"interrupt 因为是桩所以不需要"的理由
    /// 已随本轮失效，需要重新推导，不能直接继承结论）**：**需要**，且理由与 `stop()` 完全相同（不是
    /// "因为 stop() 需要所以照抄"，是同一条底层机制成立的必然结果）——`send()`/`stop()` 文档注释已经
    /// 论证过：`sessions.messages.subscribe` 与 `sessions.send`/`sessions.abort` 的 handler 在
    /// openclaw 服务端 `void runWithDiagnosticTraceContext(...)`（fire-and-forget）下并发处理，谁先
    /// 抵达 dispatch 无序化保证；若我们自己的 `sessions.abort` 先于 `sessions.messages.subscribe`
    /// 抵达服务端，这次 abort 立即触发的 aborted lifecycle 帧就可能在订阅登记生效之前被服务端发出，
    /// 永远收不到。`interrupt(mode:"cancel")` 同样会发 `sessions.abort`、同样要等它触发的 aborted
    /// lifecycle 帧（见上面"与 stop() 的关系"一节），因此面对的是与 `stop()` 完全相同的风险，必须
    /// 共享同一道屏障。
    ///
    /// **互斥（本轮要求 8）**：新增 `SessionLockState.interruptInProgress`——`send()`/`stop()`/
    /// `interrupt()` 三者两两互斥，任一方法执行时若锁不是 idle 一律 reject(session_locked)，不做
    /// 优先级仲裁（见 `SessionLockState` 上方注释）。**每条失败/成功出路都必须释放锁 + 清理
    /// pendingStop 条目**——`stop()` 文档注释"M3 ③"一节记录过一个真实 bug：一次抛错的 RPC 让锁永久
    /// 卡在 in-progress，第二次调用被误判成"另一个操作正在进行"而拒绝。这里用**单个 `defer`**
    /// （而不是像 `stop()` 那样在成功尾声与 catch 块分别手写一遍）覆盖全部出路——`stop()` 的成功
    /// 尾声能把这一步交给 `emitStopSessionEndAndFinish` -> `clearSessionDerivedCaches` 顺带做掉，
    /// `interrupt()` **不能**调用那条链路（那会把整个 session 拆掉，直接违反本轮红线），所以两条
    /// 路径的收尾在这里必须自己承担；`defer` 保证不会像"两处手写"那样漏掉其中一条。
    public func interrupt(session: SessionHandle, options: InterruptRequestMessagePayload) async throws -> InterruptResultPayload {
        await awaitSubscriptionRpcDispatchIfPending(sessionID: session.sessionID)
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        guard options.mode == .cancel else {
            throw KernelClientError.rpcRejected(
                code: "unsupported_interrupt_mode",
                message: "interrupt() rejected: mode '\(options.mode.rawValue)' is not implemented this round " +
                    "(scope-lock rounds/0020 — only mode:\"cancel\" is supported this round); steer/" +
                    "abort_and_resend must not be silently treated as cancel"
            )
        }

        let currentLock = lockStateBySessionID[session.sessionID] ?? .idle
        guard currentLock == .idle else {
            throw KernelClientError.rpcRejected(
                code: "session_locked",
                message: "interrupt() rejected: session \(session.sessionID) lock state is \(currentLock), expected idle (D1 v3.1 §9.3)"
            )
        }
        lockStateBySessionID[session.sessionID] = .interruptInProgress

        let operationID = "op-interrupt-\(UUID().uuidString)"
        let affectedRunIDBeforeAbort = lastRunIDBySessionID[session.sessionID]
        pendingStops[session.sessionID] = PendingStop(
            operationID: operationID, affectedRunID: affectedRunIDBeforeAbort, operationKind: .interrupt
        )
        // 覆盖每一条出路（正常 return、任意一种 throw）——见函数文档注释"互斥"一节：为什么这里用
        // 单个 defer，而不是像 stop() 那样在成功尾声与 catch 块分别手写一遍锁/pendingStop 清理。
        defer {
            pendingStops.removeValue(forKey: session.sessionID)
            lockStateBySessionID[session.sessionID] = .idle
        }

        do {
            let forceResolvedApprovalReqIDs = try await forceDenyPendingApprovalsBeforeStop(sessionID: session.sessionID)
            pendingStops[session.sessionID]?.forceResolvedApprovalReqIDs = forceResolvedApprovalReqIDs

            let abortResult = try await request(method: "sessions.abort", params: ["key": kernelKey])
            prettyPrint("RECV sessions.abort result (interrupt cancel)", abortResult)

            // 与 stop() 逐字相同的判定：是否需要等待终态，由这次 sessions.abort 自己的权威返回值
            // 判断，不是本地缓存的 lastRunIDBySessionID——见函数文档注释"abortedRunId == nil 时"
            // 一节引用的现场证据。
            let actuallyAbortedRunID = abortResult["abortedRunId"] as? String
            var timedOut = false
            if let actuallyAbortedRunID = actuallyAbortedRunID {
                pendingStops[session.sessionID]?.affectedRunID = actuallyAbortedRunID
                let timeoutSeconds = testSupportInterruptTimeoutSecondsOverride ?? 5
                let waitOutcome = await waitForPendingStopTerminal(sessionID: session.sessionID, timeoutSeconds: timeoutSeconds)
                switch waitOutcome {
                case .transportClosed:
                    // 与 stop() 同款诚实处理（见其文档注释"NOTE-1"一节）：`resolvePendingStopForTransportClose`
                    // 已经代发 operation_completed(aborted_effect_unknown) 镜像、标记 terminalEmitted，
                    // 并清理了这个 session 的全部派生状态（含本函数的锁与 pendingStop）。这里绝不能
                    // 假装 succeeded/timed_out 继续往下走——如实抛错，交给下面的 catch 统一收尾（此时
                    // pendingStop/lock 已经是空的，catch 与本函数顶部的 defer 都会是安全的 no-op）。
                    throw KernelClientError.transport("interrupt() aborted: transport closed while waiting for aborted-run terminal confirmation")
                case .timedOut:
                    emitOperationCompletedMirror(
                        sessionID: session.sessionID, operationID: operationID,
                        affectedRunID: actuallyAbortedRunID, outcome: .timedOut, operationKind: .interrupt
                    )
                    // 与 stop() 的"NOTE-2"同款防御性标记：即使本函数当前实现在这之后不再发起任何会
                    // 让出 actor 隔离的 await（没有 sessions.delete 这一步，函数体到这里已经只剩同步
                    // 代码），提前标记 terminalEmitted 仍然让"迟到的 aborted lifecycle 帧被
                    // handleAgentEvent 误判成尚未发过 terminal"这类问题，不会被未来在这之后新增的
                    // await 悄悄重新引入。
                    pendingStops[session.sessionID]?.terminalEmitted = true
                    timedOut = true
                case .terminalObserved:
                    timedOut = false
                }
            } else {
                // sessions.abort 诚实回报 abortedRunId:null——这次 run 早已自然结束，没有可等待的
                // 终态，但 Promise 即将报 succeeded，必须同时给事件流补一条 operation_completed 镜像。
                emitOperationCompletedMirror(
                    sessionID: session.sessionID, operationID: operationID,
                    affectedRunID: nil, outcome: .succeeded, operationKind: .interrupt
                )
            }

            // 红线：到这里为止，本函数从未 dispatch 过 sessions.delete，也从未调用
            // emitStopSessionEndAndFinish/finishEventContinuation——会话继续存活，事件流的
            // continuation 仍然打开，调用方可以在这次 interrupt() 返回之后对同一个 session 再次
            // send()。这正是 interrupt(mode:"cancel") 与 stop() 的唯一本质区别。
            let outcome: PayloadOutcome = timedOut ? .timedOut : .succeeded
            return InterruptResultPayload(
                affectedRunID: actuallyAbortedRunID, detail: nil, interruptedActiveRun: nil, newRunID: nil,
                operationID: operationID, outcome: outcome,
                status: makeJSONAny(abortResult["status"] ?? NSNull())
            )
        } catch {
            // 与 stop() 同款收尾（见其文档注释"M3 ③"一节）：sessions.abort 或
            // forceDenyPendingApprovalsBeforeStop 抛错——补一条 operation_completed(rejected) 镜像
            // （除非某条路径已经先发过别的终态镜像，例如上面 transportClosed 分支——那种情况下
            // pendingStops[session.sessionID] 早已被清空，`?? true` 会让这里正确判定"已经发过了"，
            // 不再重复），再把原始错误重新抛给调用方。锁与 pendingStop 的释放交给函数顶部的
            // defer，不在这里重复处理。
            let alreadyTerminalEmitted = pendingStops[session.sessionID]?.terminalEmitted ?? true
            let affectedRunID = pendingStops[session.sessionID]?.affectedRunID ?? affectedRunIDBeforeAbort
            if !alreadyTerminalEmitted {
                emitOperationCompletedMirror(
                    sessionID: session.sessionID, operationID: operationID,
                    affectedRunID: affectedRunID, outcome: .rejected, operationKind: .interrupt
                )
            }
            throw error
        }
    }

    /// D1 §2.5 stop()。**M3 rework（收 T-045 codex 确认性再审 MUST-FIX，在 F6 基础上第二次收残）**：
    /// F6 只解决了"operationId 不共享"和"delete 前不等终态"两个问题，但重写本身引入/遗留了三类新
    /// 缺陷（codex 独立复现）：
    ///   ① `abortedRunId==nil`（无 active run）与"等待超时"两条路径只让 Promise 知道结果，从不给
    ///      `subscribe()` 事件流补一条 `operation_completed` 镜像——只订阅事件流、不等 Promise 的
    ///      观察者完全看不到这次 stop 操作本身的终态。
    ///   ② active-run 路径把"这次 stop 操作成功与否"和"sessions.delete 这一步资源回收是否成功"
    ///      两件事混为一谈：`handleAgentEvent` 在 delete **之前**就已经用 `succeeded` 发出了
    ///      operation_completed（这个时机是对的，D1 §9.3 要求先有终态再有 session_end），但 Promise
    ///      的 outcome 却在 delete **之后**重新按 `deleted` 布尔值计算——如果 delete 恰好返回
    ///      `deleted:false`，Promise 报 `.rejected`，与已经发出的 Event `.succeeded` 直接矛盾。
    ///      修法：outcome 只由"等没等到终态确认"（timedOut）决定，不再看 `deleted`——delete 是这次
    ///      stop 操作的收尾资源回收步骤，和"abort 本身有没有成功"是两件事，不应该互相污染判定，这样
    ///      Promise 和已经发出的 Event 天然保持一致（因为它们不再有两个独立的信息来源）。
    ///   ③ `sessions.abort`/`sessions.delete` 抛错时整个函数直接向上抛出，`stopInProgress` 锁、
    ///      `pendingStops` 条目都不会被释放——真实复现：第一次 stop() 因传输错误抛出后，锁永久卡在
    ///      `stop_in_progress`，第二次 stop() 会被误判成"另一个 stop 正在进行"而拒绝
    ///      （`session_locked`），即使第一次调用早就已经失败结束。修法：`do/catch` 包裹两次 RPC，
    ///      catch 里统一释放锁 + 清理 pendingStop + 发一条 `operation_completed(outcome:.rejected)`
    ///      镜像，然后把原始错误重新抛给调用方（stop() 这次调用确实失败了，调用方需要知道）。
    ///
    /// `PendingStop.affectedRunID` 在 abort 之后立刻用 `abortResult.abortedRunId`（权威值）覆盖——
    /// 不能一直沿用发起 abort 前的本地缓存 `lastRunIDBySessionID`，那个值可能陈旧，会让
    /// `handleAgentEvent` 里 `pendingForRun.affectedRunID == runID` 的相等判断永远不成立、白等到
    /// 超时（codex 复现的具体机制）。
    ///
    /// **rounds/0012 ② 复用 send() 的订阅 dispatch 屏障**：函数体第一行同样
    /// `await awaitSubscriptionRpcDispatchIfPending(...)`——完整设计取舍见 `send()` 文档注释，这里
    /// 只记为什么 `stop()` 也要等：`stop()` 会在有 active run 时产出 `turn_complete(cancelled)` 等
    /// 事件（见下方 `waitForPendingStopTerminal`），这些事件同样要经过已建立的订阅才能被调用方观察
    /// 到，与 `send()` 面对的是同一类"订阅是否已经登记"的风险，理应共享同一道屏障。`interrupt()`
    /// （rounds/0020 起完整实现 `mode:"cancel"`）出于**同一条理由**同样需要这道屏障——它同样会在
    /// 发起 `sessions.abort` 后经由 `waitForPendingStopTerminal` 产出 `operation_completed`/
    /// `turn_complete(cancelled)`，完整推理见 interrupt() 自己的文档注释，不在这里重复。
    /// `respondApproval()`（rounds/0015 已实现）同样不需要这道屏障，但理由不同、不是"因为它是桩"：
    /// 它只有在**已经收到过** `approval_request` 事件之后才可能被调用，而那条事件只能经由已经建立
    /// 的订阅到达——"订阅已就绪"是它被调用的前提条件，不是需要它自己去等的东西。
    public func stop(session: SessionHandle) async throws -> StopResultPayload {
        await awaitSubscriptionRpcDispatchIfPending(sessionID: session.sessionID)
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        let currentLock = lockStateBySessionID[session.sessionID] ?? .idle
        guard currentLock == .idle else {
            throw KernelClientError.rpcRejected(
                code: "session_locked",
                message: "stop() rejected: session \(session.sessionID) lock state is \(currentLock), expected idle (D1 v3.1 §9.3)"
            )
        }
        lockStateBySessionID[session.sessionID] = .stopInProgress

        let operationID = "op-stop-\(UUID().uuidString)"
        let affectedRunIDBeforeAbort = lastRunIDBySessionID[session.sessionID]
        pendingStops[session.sessionID] = PendingStop(
            operationID: operationID, affectedRunID: affectedRunIDBeforeAbort, operationKind: .stop
        )

        do {
            // D1 §6.2 M3（强制定序，rework）：取消当前 run 之前，若该 session 名下存在 pending
            // 审批，必须先把它们强制 deny 掉、确认内核已接受，才能发起 sessions.abort——见
            // `forceDenyPendingApprovalsBeforeStop` 文档注释。这一步必须在 `sessions.abort` 之前
            // 完成，且失败时（RPC 抛错/内核未确认 denied）不能继续往下发 abort——直接落进下面的
            // catch 统一收尾（锁释放+pendingStop 清理+operation_completed(rejected) 镜像），不能
            // 假装"反正等会儿再看"。
            let forceResolvedApprovalReqIDs = try await forceDenyPendingApprovalsBeforeStop(sessionID: session.sessionID)
            pendingStops[session.sessionID]?.forceResolvedApprovalReqIDs = forceResolvedApprovalReqIDs

            let abortResult = try await request(method: "sessions.abort", params: ["key": kernelKey])
            prettyPrint("RECV sessions.abort result", abortResult)

            // D1 v3 §9.3："stop() 调用时存在 active run，适配器必须先完成该 run 的强制取消并产出
            // TurnCompleteEvent(cancelled)...确认该事件已经进入 subscribe() 流之后，才能产出
            // SessionEndEvent(reason:'stopped')"。有界等待（不是无限悬挂），交由 handleAgentEvent 在
            // 观察到对应 aborted lifecycle 帧时唤醒；超时则诚实继续（不让调用方永久悬挂），并把
            // outcome 记成 .timedOut。
            //
            // **是否需要等待，由 `sessions.abort` 自己的返回值判断，不是本地缓存的 `affectedRunID`**
            // ——现场实测（scratchpad/openclaw-iso3 隔离环境）坐实：`lastRunIDBySessionID` 只在收到
            // 新 run 时刷新，一个 run 正常 turnComplete 之后这个缓存不会被清空；如果 stop() 在该 run
            // 早已自然结束之后才被调用，`sessions.abort` 会诚实回报 `{"abortedRunId":null,
            // "status":"no-active-run"}`——这种情况下压根不会有任何 aborted lifecycle 帧到达。改为
            // 直接读 `abortResult.abortedRunId`——非空才说明这次 abort 真的中止了一个活跃 run，才需要
            // 等待其终态；为 nil 就没有等待的意义。
            let actuallyAbortedRunID = abortResult["abortedRunId"] as? String
            var timedOut = false
            if let actuallyAbortedRunID = actuallyAbortedRunID {
                // M3：用权威值覆盖，不再信任 abort 前的本地缓存（见函数文档注释）。
                pendingStops[session.sessionID]?.affectedRunID = actuallyAbortedRunID
                let timeoutSeconds = testSupportStopTimeoutSecondsOverride ?? 5
                let waitOutcome = await waitForPendingStopTerminal(sessionID: session.sessionID, timeoutSeconds: timeoutSeconds)
                switch waitOutcome {
                case .transportClosed:
                    // NOTE-1（T-047 grok 复核，真挂起 bug 修复）：等待过程中 transport 已经关闭——
                    // `resolvePendingStopForTransportClose`（见 `handleTransportClosed`）已经代发
                    // `operation_completed(aborted_effect_unknown)` 镜像、标记 `terminalEmitted`，
                    // 且 `clearSessionDerivedCaches` 已经清理了包括本函数 `stopInProgress` 锁在内的
                    // 全部派生状态。这里绝不能假装 succeeded/timed_out 继续往下走——`sessions.delete`
                    // 在 transport 已断的情况下多半也会失败，即使侥幸命中测试桩"成功"了，也会跟已经
                    // 发出的镜像终态矛盾（M3 修的正是 Promise/Event 矛盾这类问题）。如实抛错，交给
                    // 下面的 catch 统一收尾——此时 pendingStop/lock 已经是空的，catch 里的清理调用
                    // 都是安全的 no-op。
                    throw KernelClientError.transport("stop() aborted: transport closed while waiting for aborted-run terminal confirmation")
                case .timedOut:
                    // M3：等待超时也必须给事件流补一条 operation_completed 镜像——上一轮只有 Promise
                    // 知道超时了，只订阅事件流的观察者永远看不到这个 run 的终态。
                    emitOperationCompletedMirror(
                        sessionID: session.sessionID, operationID: operationID,
                        affectedRunID: actuallyAbortedRunID, outcome: .timedOut, operationKind: .stop
                    )
                    // NOTE-2：超时路径也要标记 terminalEmitted——否则迟到的 aborted lifecycle 帧仍
                    // 可能在 clearSessionDerivedCaches 清缓存前，被 handleAgentEvent 的
                    // `!pendingForRun.terminalEmitted` 判断当成"还没发过 terminal"又发一组。
                    pendingStops[session.sessionID]?.terminalEmitted = true
                    timedOut = true
                case .terminalObserved:
                    timedOut = false
                }
            } else {
                // M3：这次 stop() 生效时该 run 早已自然结束（sessions.abort 诚实回报
                // abortedRunId:null）——没有可等待的终态，但 Promise 即将报 succeeded，必须同时给
                // 事件流补一条 operation_completed 镜像（上一轮这条路径只发 session_end，事件流
                // 观察者完全看不到这次 stop 操作本身的终态）。
                pendingStops.removeValue(forKey: session.sessionID)
                emitOperationCompletedMirror(
                    sessionID: session.sessionID, operationID: operationID,
                    affectedRunID: nil, outcome: .succeeded, operationKind: .stop
                )
            }

            let deleteResult = try await request(method: "sessions.delete", params: ["key": kernelKey])
            prettyPrint("RECV sessions.delete result", deleteResult)
            let deleted = (deleteResult["deleted"] as? Bool) ?? false
            if !deleted {
                // 诚实记录：delete 未确认成功，但不据此把已经发出/即将返回的 succeeded 倒转成
                // rejected——delete 是会话资源回收的收尾步骤，和"这次 stop 操作本身有没有成功中止
                // run"是两件事，不应该互相污染判定（M3 修的正是这个矛盾）。
                prettyPrint("WARN sessions.delete reported deleted:false after stop() otherwise succeeded", deleteResult)
            }

            emitStopSessionEndAndFinish(session: session)

            // D1 §2.5：stop() 可达的 outcome 子集是 succeeded/timed_out/rejected 三态——本函数只有
            // 走到这里（两次 RPC 都没有抛错）才可能是 succeeded/timed_out，`.rejected` 专属于下面
            // catch 分支代表的"RPC 本身失败"。
            let outcome: StopResultPayloadOutcome = timedOut ? .timedOut : .succeeded
            return StopResultPayload(operationID: operationID, outcome: outcome)
        } catch {
            // M3：sessions.abort/sessions.delete 抛错——释放锁 + 清理 pendingStop + 发一条
            // operation_completed(outcome:.rejected) 镜像，再把原始错误重新抛出。不清理这三样状态
            // 会让该 session 永久卡在 stop_in_progress（复现：第一次 stop 抛错后锁不释放，第二次
            // stop 被 session_locked 拒绝，即使第一次调用早已结束）。
            //
            // NOTE-1 订正（写 NOTE-1 回归测试时坐实的竞态）：只有当"这次 stop() 还没有为任何其它
            // 路径发过终态镜像"时才在这里补发 rejected——否则会跟已经发出的镜像互相矛盾。两个具体
            // 场景都会走到这里却已经发过别的镜像：① NOTE-1 的 transport-closed 路径
            // （resolvePendingStopForTransportClose 已经标记 terminalEmitted=true 并发出
            // aborted_effect_unknown，stop() 随后如实 throw，落进这个 catch）；②"无 active
            // run"分支已经移除 pendingStop 并发出 succeeded，之后 sessions.delete 才抛错。两种情况
            // 都不该再补一条 rejected——那会让同一次 stop() 在事件流里出现两条互相打架的终态。
            let alreadyTerminalEmitted = pendingStops[session.sessionID]?.terminalEmitted ?? true
            let affectedRunID = pendingStops[session.sessionID]?.affectedRunID ?? affectedRunIDBeforeAbort
            if !alreadyTerminalEmitted {
                emitOperationCompletedMirror(
                    sessionID: session.sessionID, operationID: operationID,
                    affectedRunID: affectedRunID, outcome: .rejected, operationKind: .stop
                )
            }
            pendingStops.removeValue(forKey: session.sessionID)
            lockStateBySessionID.removeValue(forKey: session.sessionID)
            throw error
        }
    }

    /// D1 §6.2 M3 + §6.3（stop-path 强制 deny，本轮新增）：在 `stop()` 发起 `sessions.abort` 之前，把
    /// 该 session 当前所有仍处于 pending 的审批（由 `emitApprovalRequestIfPossible` 登记进
    /// `pendingApprovalsByReqID`）逐个强制 deny。
    ///
    /// **openclaw wire grounding（只读参考，未改该文件）**：
    /// `kernels/openclaw/src/gateway/server-methods/approval.ts` 的 `"approval.resolve"` handler——
    /// 这是 openclaw 统一的、kind-agnostic 的审批解决 RPC（`packages/sdk/src/client.ts:943`
    /// `ApprovalsNamespace.respond` 走的也是这一条，只是 SDK 包了一层 `exec.approval.resolve` 别名）。
    /// params schema（`packages/gateway-protocol/src/schema/approvals.ts:245`
    /// `ApprovalResolveParamsSchema`）：`{id, kind, decision}`；成功响应体
    /// （`ApprovalResolveResultSchema`）：`{applied: Bool, approval: {status, ...}}`。**"确认①的
    /// deny 已生效（内核侧确认接受，而非仅适配器本地标记）"由这次 RPC 的 `await` 本身构成**：`await
    /// request(...)` 只有等到 openclaw 真正处理完这条 `approval.resolve` 请求、回一个 `ok:true` 的
    /// 响应帧之后才会返回；`ok:false`（`handleIncoming` 的 "res" 分支）会被 `request()` 转成
    /// `KernelClientError.rpcRejected` 抛出——这里不吞掉这个错误，调用方（`stop()`）会因此中止、
    /// 落进它自己的 catch 分支统一收尾，绝不会在没有真正拿到内核确认的情况下继续往下发
    /// `sessions.abort`（那正是 M3 定序要防止的竞态：deny 还没被内核接受，abort 已经发出去了）。
    /// 拿到 `ok:true` 响应后，本函数还要求 `approval.status == "denied"`——只有这个字段真的是
    /// "denied" 才算数，见下方 guard。
    ///
    /// `approval.resolve` 对 `id` 的路由（`record.kind === "exec" ? execApprovalManager : ...`，见
    /// `approval.ts:492-518`）本身按**服务端已持久化的 record.kind** 选择 manager，不依赖客户端传的
    /// `kind` 字段是否精确匹配——传错 `kind` 只会让服务端把这次决议记成
    /// `reason:"malformed-verdict"`（`applyForcedDeny`）而不是 `"user"`，两者都会落地成
    /// `status:"denied"`。本函数仍然传本地缓存的真实 `openclawKind`（见
    /// `emitApprovalRequestIfPossible`）——如实转发协议要求的字段，不是"反正传错也能过就随便填"。
    ///
    /// 返回值是这一批被强制终态化的 reqId 列表，供调用方（`stop()`）塞进该 run
    /// `TurnCompleteEvent.forceResolvedApprovals`（D1 §6.2 M3："步骤①的强制终态化须同步在该 run 的
    /// `TurnCompleteEvent.forceResolvedApprovals` 中列出"）。没有任何 pending 审批时直接返回空数组、
    /// **不发起任何 RPC**——绝大多数 stop() 调用都会走这条空路径，这也是为什么这个函数不会打破既有的
    /// 26 个 frame-replay 测试（它们都没有 stub `approval.resolve`，真打了这条 RPC 会因为没有测试桩、
    /// 也没有真实连接而 `throw KernelClientError.notConnected`）。
    ///
    /// **NOTE-A（T-049 grok 对抗审复核，本轮修复）drain-loop rework**：上一轮只对 pending reqId 取
    /// **一次快照**再逐个 await deny——若某个 approval 在这 N 个 `approval.resolve` RPC 往返组成的
    /// await 窗口内新到（`emitApprovalRequestIfPossible` 在 actor 重入期间登记进
    /// `pendingApprovalReqIDsBySessionID`），会逃过本轮快照、仍处于 pending 就被随后的
    /// `sessions.abort` 甩下——这正是 D1 §6.2 力保的 exactly-once 想避免的"cancel 已生效、审批还
    /// pending、内核对即将消失的 run 又异步接受一个人工决策"的变体。
    ///
    /// **选型：drain-loop（而非 freeze 登记 + deny late arrival）**。两个方向都能关闭这个窗口，选
    /// drain-loop 的理由：
    /// - **正确性等价，改动面更小**：freeze 方向要求 `emitApprovalRequestIfPossible`（当前是
    ///   `handleAgentEvent`/`handleSessionApprovalEvent`/`consumeApprovalReplay` 这几个纯同步 wire
    ///   dispatch 方法内部的同步调用）在 `stopInProgress` 期间对新到的 approval 立即发一次
    ///   `await request("approval.resolve", ...)`——但这几个 dispatch 方法本身是从 `handleIncoming`
    ///   同步调用的（`receiveLoop` 的热路径），要嵌入一次真正的 RPC await 就必须让它们要么整体变成
    ///   `async`（连锁改动 `handleIncoming`/`receiveLoop` 的调用形状），要么用 `Task { await ... }`
    ///   fire-and-forget——而后者恰好**重新引入同一类竞态**：`stop()` 完全不知道这个 detached Task
    ///   有没有跑完 deny 就已经继续发 `sessions.abort` 了，为了堵住这个新洞，还是得让 `stop()` 在
    ///   abort 前等所有"在途 late-deny"收尾——这就是把 drain-loop 拆成两个协作的地方重新实现一遍，
    ///   状态更分散、更难论证，C# 那边还要多一层"锁外调度 detached 任务"的心智负担。
    /// - **有界性论证**（D1 §9：一个 session 同一时刻只有一个 active run；`stop()` 进入
    ///   `stopInProgress` 早于本函数被调用，`send()` 在锁不是 `idle` 时一律 reject——因此这个 session
    ///   在整段 drain 期间**不会有新 run 被创建**）：drain 期间还能继续冒出新 pending 审批的唯一来源
    ///   是"这次 stop() 即将 abort 的、唯一的那个 run"自己的 agent 事件流仍在正常产出（`sessions.abort`
    ///   要等 drain 完全收敛成空之后才发出，所以这个 run 在 drain 期间确实还活着、还能请求审批）——
    ///   正常场景下这类审批请求本就是有限的一个序列（run 早晚会耗尽待办的 tool call 或自己走向
    ///   lifecycle 结束），drain 循环每一轮重新快照都会把新到的一并收进下一轮，若干轮内必然收敛为空。
    ///   为"理论上不该出现但不能假装不可能"的极端场景（例如一个 bug 让 run 持续不断请求审批）兜底：
    ///   加一个迭代轮次上限（`forceDenyDrainDefaultMaxRounds`/`testSupportForceDenyDrainMaxRoundsOverride`），
    ///   超限**如实 throw**（不是静默截断、也不是假装 succeeded 继续往下 abort），落进 `stop()` 既有
    ///   的 catch 分支统一收尾（锁释放 + pendingStop 清理 + operation_completed(rejected) 镜像）。
    /// - **不重蹈 NOTE-1**：drain 循环增加的是"更多轮的 `approval.resolve` await"，跟 NOTE-1 修的
    ///   "`sessions.abort` 之后等待 aborted lifecycle 终态"是完全不同的 await 点；若 transport 在
    ///   drain 期间关闭，正在等待中的 `approval.resolve` continuation 会被 `failAllPending` 唤醒抛
    ///   transport 错误（此时 `waitForPendingStopTerminal` 的 waiter 还没登记——那是 abort **之后**
    ///   才会 setup 的），错误沿 `await request(...)` 向上抛出，直接落进 `stop()` 的 catch 分支
    ///   （锁释放、pendingStop 清理），不会有任何新的挂起路径。
    ///
    /// **正确性要求**：只有当某一轮开始时重新读取的 `pendingApprovalReqIDsBySessionID[sessionID]`
    /// 恰好为空，才 `break` 出循环、把 `forceResolved` 返回给 `stop()` 去发 `sessions.abort`——这次
    /// "为空"的读取和函数返回之间没有任何 `await`（actor 隔离保证两次挂起点之间对同一个 actor 是
    /// 原子的），因此不存在"检查完为空、返回前又冒出一个新的"这个子窗口。（残留、且是任何设计都无法
    /// 免除的更窄窗口：本函数 `return` 之后、`stop()` 真正把 `sessions.abort` 帧写上线之前那几行
    /// 同步代码之间，理论上仍有一个远小于本函数所修的"N 轮 RPC 往返"窗口——这与"abort 已发出、内核
    /// 尚未真正处理"这类网络延迟本质相同，不是本函数能够或应该负责关闭的范围，见交付报告。）
    /// **rounds/0015 返工②（in-flight 串行化 + D1 §6.2 失败分支 3）**，两处改动：
    ///
    /// 1. **drain 收敛条件从"pending 表为空"收紧为"pending 表为空 **且** 该 session 没有任何在途
    ///    `approval.resolve`"**。修前：用户在本函数某次 `await request(...)` 让出 actor 隔离的窗口
    ///    里点了审批按钮，`respondApproval()` 会对**同一个 reqId** 发出第二条 `approval.resolve`
    ///    （它看到的 `pendingApprovalsByReqID[reqID]` 仍在——该表要等 RPC 返回才摘条目）；即使不撞
    ///    同一个 reqId，一条人工决议也可能在 `sessions.abort` 已经发出之后才落地。现在两者都被这个
    ///    条件挡住：任何在途决议（人工 / 缓冲溢出 deny）都必须先落地，drain 才可能收敛。
    /// 2. **`approval_not_pending` 按 D1 §6.2 失败分支 3 处理，不再一律抛错**。D1 原文：
    ///    "适配器尝试强制终态化时收到 `approval_not_pending`，直接放弃这一步，照常推进到②
    ///    （abort/cancel）——run 本身仍需按 interrupt/stop 的原始意图被中止。该 reqId **不**出现在
    ///    `TurnCompleteEvent.forceResolvedApprovals` 里。" openclaw 侧这个信号的**具体形状**（源码
    ///    实读，不是猜）：`approval.ts:462-475`，`record.status !== "pending"` 时 handler 回的是
    ///    **`ok:true` + `{applied:false, approval:<持久化的终态快照>}`**，不是错误帧——所以判据是
    ///    `applied == false`，而不是"RPC 抛错"。修前的 `guard approvalStatus == "denied"` 在"用户
    ///    抢先 allow-once"这个 D1 明写的真实竞态下会看到 `status:"allowed"`、抛
    ///    `protocolMismatch`，把整个 `stop()` 打成 rejected —— 与 D1 "承认既成事实，不覆盖，照常
    ///    推进到 abort" 正好相反。`id` 压根不存在时 openclaw 走的是另一条路
    ///    （`respondApprovalNotFound` -> `ok:false` + `INVALID_REQUEST`/details.reason=
    ///    `APPROVAL_NOT_FOUND`，同文件 :129-137），那是真错误，继续如实抛出。
    private func forceDenyPendingApprovalsBeforeStop(sessionID: String) async throws -> [String] {
        var forceResolved: [String] = []
        var round = 0
        let maxRounds = testSupportForceDenyDrainMaxRoundsOverride ?? Self.forceDenyDrainDefaultMaxRounds

        while true {
            let reqIDs = pendingApprovalReqIDsBySessionID[sessionID] ?? []
            let inFlight = approvalResolveInFlightReqIDs(sessionID: sessionID)
            if reqIDs.isEmpty && inFlight.isEmpty {
                // 这一刻的快照为空——drain 收敛，没有任何 await 会介入到下面的 break/return 之间，
                // 之后 stop() 才能安全地发 sessions.abort（见函数文档注释"正确性要求"）。
                break
            }
            round += 1
            guard round <= maxRounds else {
                throw KernelClientError.protocolMismatch(
                    "forceDenyPendingApprovalsBeforeStop: exceeded \(maxRounds) drain round(s) for session " +
                    "\(sessionID) while still observing \(reqIDs.count) newly-arrived pending approval(s) " +
                    "and \(inFlight.count) in-flight approval.resolve call(s) " +
                    "during force-deny — refusing to loop indefinitely (NOTE-A drain bound)"
                )
            }

            // 先把在途决议等干净，再动手 deny 剩下的——顺序不可颠倒：一条在途的人工 allow 落地后
            // 会把它自己的 reqId 从 pending 表摘掉，下一轮快照里它就不在了，我们因此**天然**不会
            // 对一个已经被人工终态化的 reqId 再发 deny（D1 失败分支 3 的"承认既成事实"）。
            if !inFlight.isEmpty {
                for reqID in inFlight { await awaitApprovalResolveSettled(reqID: reqID) }
                continue
            }

            // 排序只是让每一轮内部"同一 session 存在多个 pending 审批"这种边缘情况下 RPC 发起顺序在
            // 测试里可预测——不是协议要求的顺序。
            for reqID in reqIDs.sorted() {
                guard let info = pendingApprovalsByReqID[reqID] else { continue }
                // in-flight 槽位没抢到 = 有别的路径（人工决策）正在对这个 reqId 发决议。**不发第二
                // 条 RPC**，等它落地，本轮剩下的交给下一轮快照重新判断。
                guard beginApprovalResolveInFlight(reqID: reqID, sessionID: sessionID, origin: .forceDenyOnStop) else {
                    await awaitApprovalResolveSettled(reqID: reqID)
                    continue
                }
                let result: JSONObject
                do {
                    // rounds/0015 B：wire 字面量改用 `OpenclawApprovalDecisionWire.deny.rawValue`，与
                    // `respondApproval()` 共享同一个决策取值来源（EventMapping.swift ⑦），不再各写各的
                    // 字符串。**刻意不走 `makeApprovalResolveParams` 的 allowedDecisions 成员校验**：这
                    // 是 D1 §6.2 要求的**强制** deny，语义上不受该条请求 presentation 的选项集约束；而
                    // 且 "deny" 由 openclaw schema 保证恒在允许集内（`ApprovalAllowedDecisionsSchema`
                    // 的 `contains: Literal("deny")`，approvals.ts:79）——即便某条请求的 allowedDecisions
                    // 因异常为空，stop() 的强制 deny 也必须照发，不能被一道本不适用的校验挡住。
                    //
                    // rounds/0016（T-096 第 3 项）：改走 `sendApprovalResolveBounded`——无界 await
                    // 时网关不回应答就会让整条 stop() 永久挂死（drain 的收敛条件里"无在途 resolve"
                    // 那一项永远不成立）。
                    result = try await sendApprovalResolveBounded(reqID: reqID, params: [
                        "id": reqID, "kind": info.openclawKind,
                        "decision": OpenclawApprovalDecisionWire.deny.rawValue,
                    ])
                } catch {
                    // rounds/0016（T-096 第 2 项）：强制 deny 失败 -> **先落持久态再抛**。抛出去之后
                    // `pendingApprovalsByReqID[reqID]` 仍然留着（刻意的，见本函数文档注释），修前这
                    // 意味着用户随后点"允许一次"会被完整放行——一次已经决定拒绝、只是没打成的审批
                    // 被人工翻成允许，命令真的执行。持久态就是那道闸。
                    recordForceDenyPendingKernelAck(
                        reqID: reqID, sessionID: sessionID, runID: info.runID,
                        openclawKind: info.openclawKind, allowedDecisions: info.allowedDecisions,
                        origin: .forceDenyOnStop, observedFailure: "approval.resolve 失败：\(error)"
                    )
                    endApprovalResolveInFlight(reqID: reqID)
                    throw error
                }
                endApprovalResolveInFlight(reqID: reqID)
                prettyPrint("RECV approval.resolve result (M3 stop-path force-deny, drain round \(round))", result)

                let approvalStatus = jsonString(jsonObject(result["approval"])?["status"])
                let applied = jsonBool(result["applied"])
                if applied == false {
                    // D1 §6.2 失败分支 3（"已终态"，真正的竞态而不是失败）：审批在我们发起强制 deny
                    // 之前已经被别人终态化。承认既成事实——不覆盖、**不计入 forceResolvedApprovals**、
                    // 照常推进到 sessions.abort。本地 pending 表在这里摘掉（内核侧它早就不是 pending
                    // 了，留着只会让下一轮 drain 又对它发一次注定 applied:false 的 RPC）。
                    prettyPrint("approval.resolve 返回 applied:false（D1 §6.2 分支 3：审批已被抢先终态化，承认既成事实）", [
                        "reqId": reqID, "observedStatus": approvalStatus ?? "nil",
                    ])
                    pendingApprovalsByReqID.removeValue(forKey: reqID)
                    pendingApprovalReqIDsBySessionID[sessionID]?.remove(reqID)
                    if activeApprovalReqIDBySessionID[sessionID] == reqID {
                        promoteNextBufferedApprovalIfPossible(sessionID: sessionID, reasonHint: "D1 §6.2 分支 3 既成事实")
                    }
                    continue
                }
                guard approvalStatus == "denied" else {
                    // `applied:true` 却不是 denied 终态——内核没有把这次强制 deny 落地成我们要求的
                    // 终态。如实抛错，不能假装"已确认生效"（M3 的核心要求就是"确认"，不是"发了请求
                    // 就当数"）。这与上面 `applied:false` 是两件不同的事：那个是"别人先赢了"，这个
                    // 是"我们赢了但结果不对"。
                    // rounds/0016（T-096 第 2 项）：同 catch 分支，抛之前先落 FORCE_DENY_PENDING_KERNEL_ACK。
                    recordForceDenyPendingKernelAck(
                        reqID: reqID, sessionID: sessionID, runID: info.runID,
                        openclawKind: info.openclawKind, allowedDecisions: info.allowedDecisions,
                        origin: .forceDenyOnStop,
                        observedFailure: "applied=true 但终态 status=\(approvalStatus ?? "nil")（不是 denied）"
                    )
                    throw KernelClientError.protocolMismatch(
                        "approval.resolve did not confirm denied status for reqId \(reqID) during stop() force-deny (got status: \(approvalStatus ?? "nil"))"
                    )
                }
                clearForceDenyPendingKernelAck(reqID: reqID, becauseOf: "stop-path 强制 deny 已被内核确认")
                forceResolved.append(reqID)
                pendingApprovalsByReqID.removeValue(forKey: reqID)
                pendingApprovalReqIDsBySessionID[sessionID]?.remove(reqID)
                if activeApprovalReqIDBySessionID[sessionID] == reqID {
                    // D1 五态 FORCE_DENIED_ON_STOP 也是一个合法终态 -> 触发"#2 浮现"。提升上来的
                    // 那一条会被下一轮 drain 快照看到、一并强制 deny——这正是 D1 要的"stop 时该
                    // session 名下不留 pending 审批"，不是多余的一轮。
                    promoteNextBufferedApprovalIfPossible(sessionID: sessionID, reasonHint: "FORCE_DENIED_ON_STOP")
                }
            }
        }
        return forceResolved
    }

    // MARK: - rounds/0015 返工②：per-reqId in-flight 槽位（`approval.resolve` 的唯一发送许可）
    //
    // 设计要点见上方 `approvalResolveInFlightByReqID` 的文档注释。三个原语都是**纯同步**的
    // （除了 `awaitApprovalResolveSettled`，它按定义要挂起）——登记与判定之间不存在 await，actor
    // 隔离因此保证"检查槽位空 -> 占住槽位"这一对是原子的，不存在两个调用方同时认为自己抢到了。

    /// 尝试占住这个 reqId 的 in-flight 槽位。返回 `true` = 抢到了，**你是唯一有权对这个 reqId 发出
    /// `approval.resolve` 的人**；返回 `false` = 别人正在途中，你必须改走"等它落地再按既成事实行事"
    /// 这条路（`awaitApprovalResolveSettled`），**绝不能**再发一条 RPC。
    private func beginApprovalResolveInFlight(
        reqID: String, sessionID: String, origin: ApprovalResolveOrigin
    ) -> Bool {
        guard approvalResolveInFlightByReqID[reqID] == nil else { return false }
        approvalResolveEpochCounter += 1
        approvalResolveInFlightByReqID[reqID] = ApprovalResolveInFlight(
            origin: origin, sessionID: sessionID, epoch: approvalResolveEpochCounter
        )
        approvalResolveInFlightReqIDsBySessionID[sessionID, default: []].insert(reqID)
        return true
    }

    /// 释放槽位并唤醒**全部**等待者。必须在 RPC 的所有出路（成功/抛错/校验不通过）上都被调用，
    /// 否则等待者永久挂起——三个调用点各自用 `defer` 保证这一点。
    private func endApprovalResolveInFlight(reqID: String) {
        guard let record = approvalResolveInFlightByReqID.removeValue(forKey: reqID) else { return }
        approvalResolveInFlightReqIDsBySessionID[record.sessionID]?.remove(reqID)
        if approvalResolveInFlightReqIDsBySessionID[record.sessionID]?.isEmpty == true {
            approvalResolveInFlightReqIDsBySessionID.removeValue(forKey: record.sessionID)
        }
        for waiter in record.waiters { waiter.resume() }
    }

    /// 等这个 reqId 的在途 `approval.resolve` 落地。槽位已空时立即返回（不挂起）。
    private func awaitApprovalResolveSettled(reqID: String) async {
        guard approvalResolveInFlightByReqID[reqID] != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            approvalResolveInFlightByReqID[reqID]?.waiters.append(continuation)
        }
    }

    /// 该 session 名下当前是否还有任何在途 `approval.resolve`——`forceDenyPendingApprovalsBeforeStop`
    /// 的 drain 收敛条件用它（见该函数）。
    private func approvalResolveInFlightReqIDs(sessionID: String) -> [String] {
        Array(approvalResolveInFlightReqIDsBySessionID[sessionID] ?? []).sorted()
    }

    // MARK: - rounds/0016（T-096 第 3 项）：`approval.resolve` 的有界等待
    //
    // **为什么不用 Swift 的 Task 取消来做**（本节唯一的设计取舍，写在这里而不是藏在实现里）：
    // `request(method:params:)` 的等待体是 `withCheckedThrowingContinuation`，它**不是**取消感知的
    // ——对一个挂在这种 continuation 上的 Task 调用 `cancel()` 什么都不会发生，它照样永久挂起。
    // 于是 `withThrowingTaskGroup` 那套"起两个子任务、谁先返回用谁、然后 cancelAll"的常规写法在
    // 这里是**假的**：group 在退出前要等全部子任务结束，而那条 RPC 子任务永远不结束，整个 group
    // 跟着挂死——换句话说，用 task group 写出来的"有界等待"会原封不动地保留它本来要修的那个洞。
    //
    // 改为把"谁先到"这件事做成 **actor 自己的状态**：in-flight 记录里放一个收件箱
    // （`settle` continuation）+ 一道 `settled` 闸，三条路径（RPC 返回 / 有界等待到期 / 内核权威
    // terminal）都调用同一个 `settleApprovalResolve`，恰好一条能兑现。RPC 那条 Task 即使永远不
    // 返回，也只是一个悬着的 Task，**不再挡住任何人**：等待方已经拿到超时错误、in-flight 槽位已经
    // 释放、`stop()` 的 drain 收敛条件已经成立。它日后万一真的返回，带着自己的 `epoch` 回来，与
    // 当前槽位不匹配就被如实丢弃。
    //
    // 这也正是 T-096 第 3 项后半句要求的能力："让**权威 timeout terminal 能结束对应 in-flight**"
    // ——`handleApprovalTerminalSignal` 只要调用同一个 `settleApprovalResolve` 就够了。

    /// 发出一条 `approval.resolve` 并**有界等待**它的结果。调用前必须已经持有这个 reqId 的
    /// in-flight 槽位（`beginApprovalResolveInFlight` 返回 true），否则直接抛
    /// `approvalNotPending`——没有槽位就没有收件箱，也没有权利发这条 RPC。
    private func sendApprovalResolveBounded(reqID: String, params: JSONObject) async throws -> JSONObject {
        guard let record = approvalResolveInFlightByReqID[reqID] else {
            throw ApprovalDecisionError.approvalNotPending(reqID: reqID)
        }
        let epoch = record.epoch
        let timeoutMS = approvalResolveBoundedWaitMS

        // 这两个 Task 与下面 `withCheckedContinuation` 的注册之间**没有 await**，actor 隔离保证
        // 三者是原子的：任何 settle 都只可能发生在收件箱注册完成之后。`stashedResult` 是对这个
        // 论证的防御性兜底，不是它的替代。
        Task {
            do {
                let result = try await self.request(method: "approval.resolve", params: params)
                await self.settleApprovalResolve(reqID: reqID, epoch: epoch, result: .success(result))
            } catch {
                await self.settleApprovalResolve(reqID: reqID, epoch: epoch, result: .failure(error))
            }
        }
        let deadlineTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutMS) * 1_000_000)
            guard !Task.isCancelled else { return }
            await self.settleApprovalResolve(
                reqID: reqID, epoch: epoch,
                result: .failure(ApprovalDecisionError.approvalResolveTimedOut(reqID: reqID, waitedMS: timeoutMS))
            )
        }
        defer { deadlineTask.cancel() }

        let outcome: Result<JSONObject, Error> = await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<JSONObject, Error>, Never>) in
            guard var slot = approvalResolveInFlightByReqID[reqID], slot.epoch == epoch else {
                // 槽位在我们注册之前就被整体清掉了（transport 关闭走 clearSessionDerivedCaches）。
                continuation.resume(returning: .failure(ApprovalDecisionError.approvalNotPending(reqID: reqID)))
                return
            }
            if let stashed = slot.stashedResult {
                slot.stashedResult = nil
                approvalResolveInFlightByReqID[reqID] = slot
                continuation.resume(returning: stashed)
                return
            }
            slot.settle = continuation
            approvalResolveInFlightByReqID[reqID] = slot
        }
        return try outcome.get()
    }

    /// 有界等待收件箱的**唯一**兑现入口。三条路径共用；`settled` 保证恰好一条兑现，其余如实丢弃。
    private func settleApprovalResolve(reqID: String, epoch: UInt64, result: Result<JSONObject, Error>) {
        guard var slot = approvalResolveInFlightByReqID[reqID] else {
            prettyPrint("approval.resolve 结果到达时槽位已释放（孤儿响应，如实丢弃）", [
                "reqId": reqID, "epoch": "\(epoch)",
            ])
            return
        }
        guard slot.epoch == epoch else {
            // 这是**上一次**占用的迟到响应，当前槽位属于另一次决议（典型：强制 deny 失败后的幂等
            // 重试）。投递给它会让"这次重试成功了吗"建立在上一次的响应上——如实丢弃。
            prettyPrint("approval.resolve 结果的 epoch 与当前槽位不符（跨次决议的孤儿响应，如实丢弃）", [
                "reqId": reqID, "arrivedEpoch": "\(epoch)", "currentEpoch": "\(slot.epoch)",
            ])
            return
        }
        guard !slot.settled else {
            prettyPrint("approval.resolve 的有界等待已由更早的一条路径兑现（如实丢弃后到者）", [
                "reqId": reqID, "epoch": "\(epoch)",
            ])
            return
        }
        slot.settled = true
        let continuation = slot.settle
        slot.settle = nil
        if continuation == nil { slot.stashedResult = result }
        approvalResolveInFlightByReqID[reqID] = slot
        continuation?.resume(returning: result)
    }

    /// T-096 第 3 项后半句：**内核给出的权威 timeout terminal 必须能结束对应的 in-flight**。
    /// 内核判超时之后这条在途决议不可能再被兑现，继续等它的响应（可能永远不来）没有任何意义，
    /// 只会让槽位占位、让 `stop()` 的 drain 收敛不了。
    ///
    /// **只对 `status == "expired"` 生效——这个收窄不是保守，是必需的，否则会打断 live 主链。**
    /// T-096 的原话是"权威 **timeout** terminal"，一开始我按更宽的"任何权威 terminal"实现，随后
    /// 逐行读 openclaw 源码发现那样会**回归 rounds/0015 已经 live 验过的主路径**：
    /// `gateway/server-methods/approval.ts:491-540`，`approval.resolve` handler 的顺序是
    /// `applyApprovalDecision(...)`（内部 `emitLifecycle` **广播 terminal 事件**）**先**、
    /// `respond(true, {applied, approval})` **后**——两者走同一条 WS 连接，所以用户点"允许"之后，
    /// `session.approval(phase:"terminal", status:"allowed")` 这一帧**先于**这次 RPC 的响应到达
    /// 我们的 socket。若不加收窄，它会把用户自己那条尚在途的决议判成"不可能被兑现"，
    /// `respondApproval()` 于是抛 `approvalTerminatedByKernelWhileResolving`——**命令实际执行了，
    /// UI 却报错**。`allowed`/`denied` 这两个终态的权威答复本来就是这次 RPC 自己的响应，不需要、
    /// 也不能由广播帧替它下结论。
    ///
    /// `cancelled`（run-aborted / gateway-restart）同样不在这里结束在途：那条路上 RPC 响应仍会
    /// 到达（成功或 `applied:false`），而真正的兜底是 `sendApprovalResolveBounded` 的有界等待
    /// 与 transport 关闭时的显式兑现——两者已经覆盖"响应永远不来"这个一般情形。
    private func endApprovalResolveOnAuthoritativeTerminal(reqID: String, status: String?, reason: String?) {
        guard status == "expired" else { return }
        guard let slot = approvalResolveInFlightByReqID[reqID], !slot.settled else { return }
        prettyPrint("权威 terminal 到达，结束对应的在途 approval.resolve（T-096 第 3 项）", [
            "reqId": reqID, "origin": slot.origin.rawValue,
            "status": status ?? "nil", "reason": reason ?? "nil",
        ])
        settleApprovalResolve(
            reqID: reqID, epoch: slot.epoch,
            result: .failure(ApprovalDecisionError.approvalTerminatedByKernelWhileResolving(
                reqID: reqID, status: status, reason: reason
            ))
        )
    }

    // MARK: - rounds/0016（T-096 第 2 项）：FORCE_DENY_PENDING_KERNEL_ACK 的读写

    /// 记录（或刷新）一条"强制 deny 未被内核确认"的持久态。设计依据见
    /// `forceDenyPendingKernelAckByReqID` 的文档注释。
    private func recordForceDenyPendingKernelAck(
        reqID: String, sessionID: String, runID: String, openclawKind: String,
        allowedDecisions: [String], origin: ApprovalResolveOrigin, observedFailure: String
    ) {
        if var existing = forceDenyPendingKernelAckByReqID[reqID] {
            existing.observedFailure = observedFailure
            existing.retryCount += 1
            forceDenyPendingKernelAckByReqID[reqID] = existing
        } else {
            forceDenyPendingKernelAckByReqID[reqID] = ForceDenyPendingKernelAck(
                sessionID: sessionID, runID: runID, openclawKind: openclawKind,
                allowedDecisions: allowedDecisions, origin: origin, observedFailure: observedFailure
            )
            forceDenyPendingKernelAckReqIDsBySessionID[sessionID, default: []].insert(reqID)
        }
        prettyPrint("APPROVAL FSM 进入 FORCE_DENY_PENDING_KERNEL_ACK（此后只允许幂等 deny 重试）", [
            "reqId": reqID, "sessionId": sessionID, "origin": origin.rawValue,
            "observedFailure": observedFailure,
            "retryCount": "\(forceDenyPendingKernelAckByReqID[reqID]?.retryCount ?? 0)",
        ])
    }

    /// 清掉持久态——**只有两种理由**：(a) 一次 deny 重试真的被内核确认了（`applied:true +
    /// status:denied`）；(b) 内核给出了这条审批的权威终态（再重试也没有意义）。
    private func clearForceDenyPendingKernelAck(reqID: String, becauseOf reason: String) {
        guard let record = forceDenyPendingKernelAckByReqID.removeValue(forKey: reqID) else { return }
        forceDenyPendingKernelAckReqIDsBySessionID[record.sessionID]?.remove(reqID)
        if forceDenyPendingKernelAckReqIDsBySessionID[record.sessionID]?.isEmpty == true {
            forceDenyPendingKernelAckReqIDsBySessionID.removeValue(forKey: record.sessionID)
        }
        prettyPrint("APPROVAL FSM 解除 FORCE_DENY_PENDING_KERNEL_ACK", ["reqId": reqID, "reason": reason])
    }

    /// D1 §6.2 缓冲溢出的 deny。**同步**占住 in-flight 槽位之后才派生 Task——顺序不可颠倒：
    /// 只有先占住槽位，`stop()` 的 drain 收敛条件才可能看见这条在途 deny 并等它落地（这正是
    /// NOTE-A 当年否决 detached Task 方案时点名的那个洞："stop() 完全不知道这个 detached Task 有
    /// 没有跑完 deny 就已经继续发 sessions.abort 了"）。槽位没抢到（同一 reqId 已有别的在途决议——
    /// 理论上不可能，溢出的 reqId 从未进过 pending 表）就什么都不做，绝不发第二条 RPC。
    private func beginQueueOverflowDeny(
        reqID: String, openclawKind: String, sessionID: String, runID: String, allowedDecisions: [String]
    ) {
        guard beginApprovalResolveInFlight(reqID: reqID, sessionID: sessionID, origin: .queueOverflowDeny) else { return }
        Task {
            await self.performQueueOverflowDeny(
                reqID: reqID, openclawKind: openclawKind, sessionID: sessionID,
                runID: runID, allowedDecisions: allowedDecisions
            )
        }
    }

    /// **rounds/0016（T-096 第 1 项）：溢出 deny 的成功判据 = `applied:true` + 终态 `denied`。**
    ///
    /// T-096 原文："溢出 deny 必须以 `applied:true + status:denied` 为成功依据；**失败不可吞掉，
    /// 也不可提前宣称已自动拒绝**。"两句话各修掉一个洞：
    ///
    /// **洞①「失败被吞掉」**：修前这个函数的 `catch` 只 `prettyPrint` 一行 WARN 就返回——那行只进
    /// 本进程的诊断输出，**调用方（壳/UI）一个字节都收不到**，而且 `applied:false` 与"终态不是
    /// denied"这两种失败形态根本不在 `catch` 的覆盖范围内（它们都是 `ok:true` 的正常返回，见
    /// `approval.ts:462-475`：`record.status !== "pending"` 时回的是 `ok:true + {applied:false,
    /// approval:<终态快照>}`，**不是错误帧**）。现在三种形态各自被如实上报：`evt.error` 事件给
    /// 调用方 + `FORCE_DENY_PENDING_KERNEL_ACK` 持久态给后续决策。
    ///
    /// **洞②「提前宣称已自动拒绝」**：修前 `emitApprovalRequestIfPossible` 在**派发 deny 之前**就
    /// 发了 `approval_buffer_resolved(queue_overflow)`，壳把它渲染成"一条未及呈现的请求已被自动
    /// 拒绝"。deny 打不成时这句话是**假的**——那条审批在内核侧仍然 pending，随时可能被别的审批
    /// 客户端放行。现在这条事件挪到本函数、只在成功判据成立时才发。
    ///
    /// **推翻了修前注释里的那条论证**（原文："若把 emit 押后到 RPC 之后，transport 在这期间断开
    /// 就会让这条事件永久丢失……调用方连『有过这么一条审批』都不会知道"）。那条论证的前提不成立：
    /// transport 断开时 `handleTransportClosed` 会给每个活跃 session 产出
    /// `session_end(reason:transport_closed)`，调用方**不会**以为一切正常；而用"提前宣称"去换
    /// "断线时也能收到一条（内容可能是假的）事件"，是拿正确性换覆盖率——D1 §6.2 关心的
    /// "不得让一条从未被看见的请求静默消失"，靠的是**这条请求最终有一个诚实的归宿**，不是靠
    /// "无论如何先发一条说它已经被拒了"。
    private func performQueueOverflowDeny(
        reqID: String, openclawKind: String, sessionID: String, runID: String, allowedDecisions: [String]
    ) async {
        defer { endApprovalResolveInFlight(reqID: reqID) }

        let result: JSONObject
        do {
            // 与 stop-path 强制 deny 同一个理由**刻意不走** `makeApprovalResolveParams` 的
            // allowedDecisions 成员校验：这是适配器的 fail-closed 强制 deny，不受该条请求
            // presentation 选项集的约束，而 "deny" 由 openclaw schema 保证恒在允许集内
            // （`ApprovalAllowedDecisionsSchema` 的 `contains: Literal("deny")`，approvals.ts:79）。
            result = try await sendApprovalResolveBounded(reqID: reqID, params: [
                "id": reqID, "kind": openclawKind,
                "decision": OpenclawApprovalDecisionWire.deny.rawValue,
            ])
        } catch {
            // 失败形态①：RPC 抛错（含有界等待到期、权威 terminal 结束在途、transport 断开）。
            failQueueOverflowDeny(
                reqID: reqID, sessionID: sessionID, runID: runID, openclawKind: openclawKind,
                allowedDecisions: allowedDecisions, observedFailure: "approval.resolve 失败：\(error)"
            )
            return
        }
        prettyPrint("RECV approval.resolve result（D1 §6.2 缓冲溢出 fail-closed deny）", result)

        let applied = jsonBool(result["applied"])
        let approvalStatus = jsonString(jsonObject(result["approval"])?["status"])
        let approvalReason = jsonString(jsonObject(result["approval"])?["reason"])

        // 失败形态②：`applied:false`——**不是错误码**，是 `ok:true` + 终态快照（这条审批在我们
        // 发出 deny 之前就已经被别人终态化了）。无论快照里的终态是什么，"我们这条 deny 被内核
        // 接受了"都不成立，因此不发 `queue_overflow`。
        guard applied == true else {
            failQueueOverflowDeny(
                reqID: reqID, sessionID: sessionID, runID: runID, openclawKind: openclawKind,
                allowedDecisions: allowedDecisions,
                observedFailure: "applied=\(applied.map(String.init) ?? "nil")"
                    + "（内核未采纳本次 deny；它记录的终态是 status=\(approvalStatus ?? "nil")"
                    + " reason=\(approvalReason ?? "nil")）",
                // 内核已经持有一个终态记录，再 deny 一次也只会再拿到一次 applied:false——
                // 没有可重试的东西，不进 FORCE_DENY_PENDING_KERNEL_ACK。
                enterPendingKernelAck: false
            )
            return
        }
        // 失败形态③：`applied:true` 但终态不是 denied——内核采纳了这次调用却写下了别的终态。
        // 这是内核侧的契约异常，绝不当成功。
        guard approvalStatus == "denied" else {
            failQueueOverflowDeny(
                reqID: reqID, sessionID: sessionID, runID: runID, openclawKind: openclawKind,
                allowedDecisions: allowedDecisions,
                observedFailure: "applied=true 但终态 status=\(approvalStatus ?? "nil")"
                    + " reason=\(approvalReason ?? "nil")（不是 denied）"
            )
            return
        }

        // ---- 成功判据成立，此刻才允许宣称"已自动拒绝" ----
        clearForceDenyPendingKernelAck(reqID: reqID, becauseOf: "溢出 deny 已被内核确认（applied:true + denied）")
        emitApprovalBufferResolved(sessionID: sessionID, reqID: reqID, reason: .queueOverflow)
        prettyPrint("APPROVAL FSM 缓冲溢出 deny 已被内核确认（applied:true + status:denied），产出 queue_overflow", [
            "reqId": reqID, "sessionId": sessionID,
        ])
    }

    /// 溢出 deny 三种失败形态的共同出口：**如实上报 + 记持久态**，绝不产出 `queue_overflow`。
    private func failQueueOverflowDeny(
        reqID: String, sessionID: String, runID: String, openclawKind: String,
        allowedDecisions: [String], observedFailure: String, enterPendingKernelAck: Bool = true
    ) {
        prettyPrint("APPROVAL FSM 缓冲溢出 deny **未被内核确认**（不产出 queue_overflow，如实上报 evt.error）", [
            "reqId": reqID, "sessionId": sessionID, "observedFailure": observedFailure,
        ])
        if enterPendingKernelAck {
            recordForceDenyPendingKernelAck(
                reqID: reqID, sessionID: sessionID, runID: runID, openclawKind: openclawKind,
                allowedDecisions: allowedDecisions, origin: .queueOverflowDeny, observedFailure: observedFailure
            )
        }
        guard let continuation = eventContinuations[sessionID] else { return }
        let event = makeApprovalOverflowDenyUnconfirmedErrorEvent(
            reqID: reqID, observedFailure: observedFailure, ourSessionID: sessionID,
            seq: nextSeq(runID: nil, sessionID: sessionID)
        )
        continuation.yield(event)
        wireTraceCollector?.append(event)
    }

    /// D1 §6.2「缓冲请求一旦超时即终态化，不可再提升」+「#1 解决后 #2 浮现」的**内核侧信号入口**。
    ///
    /// openclaw `session.approval(phase:"terminal")` 的 `approval` 字段是 `TerminalApprovalSnapshot`
    /// （`packages/gateway-protocol/src/schema/approvals.ts:217-224`），`status` 四选一：
    /// `allowed`/`denied`/`expired`/`cancelled`，其中 **`expired` 的 reason 只有一个合法取值
    /// `timeout`**（`ApprovalExpiredReasonSchema`，同文件 :59-60）——也就是说
    /// `status == "expired"` 就是 D1 五态里 `TIMED_OUT_DENY` 的内核侧信号，一一对应，不需要猜。
    ///
    /// **这一分支修前是被整条丢弃的**（`handleSessionApprovalEvent` 的 `guard phase == "pending"`
    /// 直接 return）。丢弃"不映射成 D2 事件"这个结论本身没错（terminal 的 reason 词表与 D1
    /// `ApprovalBufferResolvedEvent` 的两值词表确实不相交，见 EventMapping.swift ④），但把它当成
    /// "因此这条 wire 事件对适配器毫无用处"就错了——它是审批 FSM 唯一的内核侧终态输入源，没有它：
    ///  - active pending 被内核超时后永远不会被清掉，缓冲队列里的下一条永远等不到提升；
    ///  - 缓冲期内被内核超时的请求会一直躺在队列里，直到被提升时才发现早就过期（正是 D1 v3.3
    ///    专门修掉的那个 v3.2 矛盾表述）。
    ///
    /// 三条处置分支：
    ///  1. 它是**当前 active pending** -> 清 pending 表 + 清 active 槽位 + 提升下一条。**不**产出
    ///     `ApprovalBufferResolvedEvent`（D1 明写该事件"严格限定"于缓冲期内终态化的请求；一条已经
    ///     呈现给调用方的审批走的是别的可见性通道）。
    ///  2. 它**还在缓冲队列里** -> 从队列移除；`status == "expired"`（reason:timeout）时产出
    ///     `ApprovalBufferResolvedEvent(buffered_timeout)`。
    ///  3. 都不是（早已终态化 / 从未接纳过）-> 无事可做。
    ///
    /// **诚实登记的表达缺口**：分支 2 里若 `status` 是 `cancelled`（reason: run-aborted /
    /// gateway-restart）或 `denied`，D1 给 `ApprovalBufferResolvedEvent.reason` 定的枚举只有
    /// `buffered_timeout | queue_overflow` 两个值（D2 生成码 `FluffyReason` 同样只有这两个），
    /// **没有任何一个能如实表达这两种原因**。这里选择"从队列移除 + 如实打印"，不拿
    /// `buffered_timeout` 冒充——那会把"run 被中止了"谎报成"它超时了"。这两种 reason 的共同点是
    /// 整个 run/session 本来就在走向终结，调用方会经由 `turn_complete`/`session_end` 得知，不构成
    /// D1 所担心的"一条从未被看见的请求静默消失"。这是 D1 词表本身的表达力缺口，记在这里而不是
    /// 用一个假值把它盖住。
    private func handleApprovalTerminalSignal(_ payload: JSONObject, ourSessionID: String) {
        guard let approval = jsonObject(payload["approval"]),
              let approvalID = jsonString(approval["id"]) else { return }
        let status = jsonString(approval["status"])
        let reason = jsonString(approval["reason"])

        // ---- 步骤 0（rounds/0016，T-096 第 3 项后半句）：**权威 terminal 结束对应的 in-flight** ----
        // 这一步必须在下面任何分支之前、且与"这个 reqId 是 active 还是缓冲中"无关：一条正在往返的
        // `approval.resolve` 只要撞上内核给出的权威终态，就不可能再被兑现，继续等它的响应只会让
        // 槽位永久占位（`stop()` 的 drain 收敛条件因此永远不成立）。
        endApprovalResolveOnAuthoritativeTerminal(reqID: approvalID, status: status, reason: reason)
        // 内核已经给出权威终态，`FORCE_DENY_PENDING_KERNEL_ACK` 再重试也没有意义——解除。
        clearForceDenyPendingKernelAck(
            reqID: approvalID, becauseOf: "内核给出权威终态 status=\(status ?? "nil")"
        )

        if activeApprovalReqIDBySessionID[ourSessionID] == approvalID {
            let terminatedRunID = pendingApprovalsByReqID[approvalID]?.runID
            pendingApprovalsByReqID.removeValue(forKey: approvalID)
            pendingApprovalReqIDsBySessionID[ourSessionID]?.remove(approvalID)

            // ---- rounds/0016（T-096 第 4 项）：**先清除旧卡片，再呈现提升项** ----
            // 修前这条内核信号只在适配器内部驱动 FSM，一个字节都没传给调用方：壳那边那张已经死掉的
            // 卡片仍然挂在 `pendingApprovals` 队头，随后提升上来的 #2 被 `append` 到它后面——而 UI
            // 只渲染队头（SessionDetailView 的串行呈现），于是**用户看到的永远是那张点不动的死卡，
            // 提升项在界面上根本不浮现**。
            //
            // `status == "expired"` 时 D2 的 `KernelErrorCode` 里有一个**字面对应**的取值
            // `approval_timeout`（errors.schema.json:10-18），据此产出一条 `evt.error`——它就是
            // "先清除"的那一步，而且**顺序是事件流上可观察的**：先 `evt.error(approval_timeout)`，
            // 后 `evt.approval_request(#2)`，壳按到达顺序处理就自然是"先清后呈现"。
            //
            // `expired` 之外的终态（denied/cancelled/allowed，由别的审批客户端或 run 中止造成）
            // **没有**字面对应的 code——不拿 `approval_timeout` 冒充（那会把"run 被中止"谎报成
            // "它超时了"，与 ④ 里对 `ApprovalBufferResolvedEvent.reason` 词表缺口的处置同源）。
            // 这些情况下"清旧卡"由壳侧的单-active 不变量兜底（新 approval_request 到达即替换），
            // **提升项缺席时旧卡只能靠本地倒计时收尾** —— 这是 D2 词表的表达力缺口，如实登记，
            // 归 rounds/0016 scope-lock 明确排除的"超时态无 D2 对应"设计轮议题。
            if status == "expired", let continuation = eventContinuations[ourSessionID] {
                let event = makeApprovalTimeoutErrorEvent(
                    reqID: approvalID, openclawReason: reason, ourSessionID: ourSessionID,
                    runID: terminatedRunID,
                    seq: nextSeq(runID: terminatedRunID, sessionID: ourSessionID)
                )
                continuation.yield(event)
                wireTraceCollector?.append(event)
                prettyPrint("APPROVAL FSM active pending 被内核判超时 -> evt.error(approval_timeout) 先行清卡", [
                    "sessionId": ourSessionID, "reqId": approvalID, "reason": reason ?? "nil",
                ])
            }

            promoteNextBufferedApprovalIfPossible(
                sessionID: ourSessionID, reasonHint: "active pending 被内核终态化 status=\(status ?? "nil")"
            )
            return
        }

        guard var queue = bufferedApprovalsBySessionID[ourSessionID],
              let index = queue.firstIndex(where: { $0.reqID == approvalID }) else {
            return
        }
        queue.remove(at: index)
        bufferedApprovalsBySessionID[ourSessionID] = queue
        if status == "expired" {
            // D1：缓冲期内被内核判超时 -> 立即终态化为 TIMED_OUT_DENY、移出队列、**不可再提升**，
            // 并通过 ApprovalBufferResolvedEvent 如实上报（不复用 forceResolvedApprovals）。
            emitApprovalBufferResolved(sessionID: ourSessionID, reqID: approvalID, reason: .bufferedTimeout)
        } else {
            prettyPrint("APPROVAL FSM 缓冲条目被内核以非超时原因终态化（D1 reason 词表无对应取值，如实不上报该事件）", [
                "sessionId": ourSessionID, "reqId": approvalID,
                "status": status ?? "nil", "reason": reason ?? "nil",
            ])
        }
    }

    /// M3：为 stop()/interrupt() 不会经过 `handleAgentEvent` 真实 aborted lifecycle 帧的路径（无
    /// active run、等待超时、RPC 抛错）补一条 `operation_completed` 镜像——D1 §9.3 要求 Promise 结果
    /// 与 `subscribe()` 流里的 `operation_completed` 必须是同一个 `{operationId,outcome}`，不能让只
    /// 订阅事件流的观察者完全看不到这次操作的终态。
    ///
    /// rounds/0020：`operationKind` 改为调用方显式传入（此前硬编码 `.stop`）——本函数现在同时服务
    /// stop() 与 interrupt() 两个调用方，若继续硬编码会让 interrupt() 触发的镜像被错误标注成
    /// `operationKind:"stop"`，即"看起来是 stop 其实是 interrupt"的这类静默错标，正是本项目一直在
    /// 防的那一类问题。`stop()` 的全部既有调用点都显式传 `.stop`，取值与修前逐字节相同，不影响其
    /// 既有行为。
    private func emitOperationCompletedMirror(
        sessionID: String, operationID: String, affectedRunID: String?, outcome: PayloadOutcome,
        operationKind: OperationKind
    ) {
        guard let continuation = eventContinuations[sessionID] else { return }
        let opPayload = OperationCompletedEventMessagePayload(
            affectedRunID: affectedRunID, detail: nil, newRunID: nil,
            operationID: operationID, operationKind: operationKind, outcome: outcome
        )
        continuation.yield(.operationCompleted(OperationCompletedEventMessage(
            direction: .event, payload: opPayload, runID: affectedRunID,
            sentAt: Date(), seq: nextSeq(runID: affectedRunID, sessionID: sessionID),
            sessionID: sessionID, ts: Date(), type: .evtOperationCompleted
        )))
    }

    /// stop() 成功路径的收尾：F8 `sessionTerminalEmitted` 去重 + yield `session_end(stopped)` +
    /// finish 事件流（`finishEventContinuation` 内部的 `clearSessionDerivedCaches` 已经覆盖 M5
    /// 要求的全部派生缓存清理，这里只再额外清 `kernelKeyBySessionID`——那张表不是"派生缓存"，是
    /// session 本身是否还存在的权威映射，不属于 `clearSessionDerivedCaches` 的职责范围）。
    private func emitStopSessionEndAndFinish(session: SessionHandle) {
        if !sessionTerminalEmitted.contains(session.sessionID) {
            sessionTerminalEmitted.insert(session.sessionID)
            if let continuation = eventContinuations[session.sessionID] {
                let sid = session.sessionID
                continuation.yield(makeSessionEndEventForStop(
                    ourSessionID: sid,
                    nextSeq: { self.nextSeq(runID: nil, sessionID: sid) }
                ))
            }
        }
        finishEventContinuation(sessionID: session.sessionID)
        kernelKeyBySessionID.removeValue(forKey: session.sessionID)
    }

    /// 等待 `pendingStops[sessionID]` 对应的 run 终态（operation_completed + turn_complete）已被
    /// `handleAgentEvent` 观察并 yield——由该处理器调用
    /// `resolvePendingStopWaiter(outcome:.terminalObserved)` 唤醒；超时（`timeoutSeconds`）则由本
    /// 函数内部起的定时器调用 `resolvePendingStopWaiter(outcome:.timedOut)` 唤醒；NOTE-1：若等待期间
    /// transport 关闭，`resolvePendingStopForTransportClose` 会用 `.transportClosed` 唤醒（见该方法
    /// 文档注释）。`resolvePendingStopWaiter`/`resolvePendingStopForTransportClose` 内部都先取出并
    /// 清空 waiter 再 resume，保证无论哪条路径先到，`CheckedContinuation` 都只会被 resume 恰好一次。
    private func waitForPendingStopTerminal(sessionID: String, timeoutSeconds: Int) async -> StopWaitOutcome {
        guard let pending = pendingStops[sessionID] else {
            // NOTE-1：entry 已经不在——这只可能是 transport 关闭清理路径
            // （clearSessionDerivedCaches）抢在我们拿到 actor 隔离之前就跑完了（例如 sessions.abort
            // RPC 返回、和这里执行之间那个极窄的窗口内 transport 关闭）。这种情况不能假装"没超时、
            // 一切正常"地往下走（旧 bug 的窄化版本）——如实报 .transportClosed，交由 stop() 统一走
            // rethrow 分支。
            return .transportClosed
        }
        guard !pending.terminalEmitted else { return .terminalObserved }
        return await withCheckedContinuation { (continuation: CheckedContinuation<StopWaitOutcome, Never>) in
            self.pendingStops[sessionID]?.waiter = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                await self.resolvePendingStopWaiter(sessionID: sessionID, outcome: .timedOut)
            }
        }
    }

    private func resolvePendingStopWaiter(sessionID: String, outcome: StopWaitOutcome) {
        guard let waiter = pendingStops[sessionID]?.waiter else { return }
        pendingStops[sessionID]?.waiter = nil
        waiter.resume(returning: outcome)
    }

    /// NOTE-1（T-047 grok 复核，真挂起 bug 修复）：transport 关闭时，若该 session 有一个仍在等待
    /// aborted-run 终态确认的 pendingStop（waiter 非空、尚未 terminalEmitted），必须在它被
    /// `clearSessionDerivedCaches` 移除之前做两件事：(a) 补发一条
    /// `operation_completed(aborted_effect_unknown)` 镜像——语义是"我们已经请求了 abort，但
    /// transport 断在确认之前，效果未知"，且必须赶在 `failAllPending` 把这个 session 的
    /// continuation `finish(throwing:)` 之前调用（之后 `yield` 静默丢弃，不抛异常，镜像会永久
    /// 丢失）；(b) 唤醒 `waitForPendingStopTerminal` 里 await 着的那个 waiter，让 `stop()` 不再
    /// 永久挂起（旧 bug：`clearSessionDerivedCaches` 直接 `removeValue` 却不 resume waiter，随后
    /// 超时任务 `resolvePendingStopWaiter` 发现条目已经不在，`guard` 提前 return，continuation
    /// 永不 resume）。调用方（`handleTransportClosed`）必须保证本方法先于该 session 的
    /// continuation 被 `finish` 调用。
    ///
    /// **rounds/0020**：`pendingStops` 现在被 stop()/interrupt() 共享，下面 (a) 步读
    /// `pending.operationKind` 而不再硬编码 `.stop`——transport 在 interrupt() 的等待窗口内关闭时，
    /// 镜像必须如实标注 `operationKind:"interrupt"`，不能因为共享了同一套等待机制就被错报成
    /// stop。本方法其余逻辑（何时唤醒、如何唤醒）对两个调用方完全相同，不需要按来源分支。
    private func resolvePendingStopForTransportClose(sessionID: String) {
        guard let pending = pendingStops[sessionID], let waiter = pending.waiter else {
            // 没有正在等待的 stop()——多半是终态已经被 handleAgentEvent 观察到，或者超时定时器已经
            // 先一步 resolve 过了；这是正常竞态，不是 bug，无事可做。
            return
        }
        pendingStops[sessionID]?.waiter = nil
        pendingStops[sessionID]?.terminalEmitted = true // 先标记再唤醒——resolve 与 remove 之间不留竞态窗口。
        emitOperationCompletedMirror(
            sessionID: sessionID, operationID: pending.operationID,
            affectedRunID: pending.affectedRunID, outcome: .abortedEffectUnknown,
            operationKind: pending.operationKind
        )
        waiter.resume(returning: .transportClosed)
    }

    /// D1 §2.6 respondApproval —— rounds/0015 A 块完整实现（此前是 `throw .notImplemented` 的桩）。
    ///
    /// **签名一个字未动**：D1 七法里 `respondApproval(session:reqID:decision:)` 的形状本来就存在
    /// （KernelClient.swift:96-97），本轮只是把函数体从抛桩换成真实调用——不新增方法、不改参数、
    /// 不改返回类型，因此 D1 窄腰面没有任何变化。
    ///
    /// 适配到 openclaw 的 `approval.resolve` RPC
    /// （`kernels/openclaw/src/gateway/server-methods/approval.ts:436`，kind-agnostic 的统一审批
    /// 解决入口；params/result schema 见 `packages/gateway-protocol/src/schema/approvals.ts:245-256`）。
    /// 复用本类已有的通用 RPC 入口 `request(method:params:)`，不另起传输路径——`stop()` 路径的
    /// `forceDenyPendingApprovalsBeforeStop` 打的也是同一条 RPC，两者共享同一套 pending 表与同一个
    /// wire 值来源（`OpenclawApprovalDecisionWire`）。
    ///
    /// **四道关卡，缺一不可**（前三道在发出 RPC 之前，第四道在返回之后）：
    /// 1. 会话必须是本适配器认得的（`kernelKeyBySessionID`）——未注册的 handle 直接拒绝，理由与
    ///    `send()`/`stop()` 开头的同款 guard 一致。
    /// 2. reqId 必须在 pending 表内，且**归属就是这个 session**——跨会话回应是调用错误，不代打。
    /// 3. `makeApprovalResolveParams` 完成决策映射 + `allowedDecisions` 成员校验 + 参数形状收口
    ///    （见该函数文档注释：不通过校验就发出去的后果是**静默变 deny 且不可逆**）。
    /// 4. `verifyApprovalResolveHonored` 核对内核返回的终态快照确实兑现了这次决策——`ok:true`
    ///    本身**不足以**说明决策被接受（`forceMalformedDeny` 路径同样回 `ok:true`）。
    ///
    /// **pending 表的清理时机**：只有第 4 关也通过（内核确认兑现）才把 reqId 从
    /// `pendingApprovalsByReqID`/`pendingApprovalReqIDsBySessionID` 移除。前三关失败时表项**保留**
    /// ——审批在内核侧仍然 pending，用户改选一个合法决策后应该还能再回应一次；提前删掉会让第二次
    /// 调用得到"approval_not_pending"这种与事实不符的错误。第 4 关失败（内核没兑现）时也移除：
    /// 此时审批已经进了终态（`malformed-verdict` deny 或 expired），再留在 pending 表里只会让随后
    /// 的 `stop()` 对一个已终态的 reqId 再发一次注定失败的强制 deny。
    public func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws {
        guard kernelKeyBySessionID[session.sessionID] != nil else {
            throw KernelClientError.protocolMismatch(
                "respondApproval: unknown sessionId \(session.sessionID) — session was never created/restored by this adapter"
            )
        }

        // 关卡 2a（rounds/0015 返工②，**新增**）：这个 reqId 已经有一条在途 `approval.resolve` 了
        // 吗？有 = `stop()` 的强制 deny（或缓冲溢出 deny）已经先一步抢到了这个 reqId 的 in-flight
        // 槽位，它的 RPC 正在往返途中。此时**绝不能**并行再发一条——那正是本轮返工要修的竞态：两条
        // 路径对同一个 reqId 各发一条 `approval.resolve`。改为等它落地，然后按既成事实重新判定
        // （下面的 pending 表查找会发现这个 reqId 已经被那条路径摘掉，如实报 approval_not_pending）。
        //
        // 这个 await 之后必须**重新**读 pending 表，不能沿用 await 之前读到的任何值——actor 在
        // 挂起期间可以重入，await 之前的读数按定义是陈旧的。
        await awaitApprovalResolveSettled(reqID: reqID)

        // 关卡 2b（rounds/0016，T-096 第 2 项，**新增**）：`FORCE_DENY_PENDING_KERNEL_ACK`。
        // 这条审批曾被适配器强制 deny 而内核**从未确认**——它在内核侧的真实状态未知，最坏情况仍是
        // pending。此时放行任何 allow 档位 = 把一次已经决定拒绝的执行翻成允许，命令真的会跑。
        // **只允许幂等 deny 重试**（openclaw 侧同一条审批 deny 两次的第二次会走
        // `record.status !== "pending"` 分支回 `applied:false`，无第二次副作用，见 approval.ts:462-475）。
        let forceDenyAck = forceDenyPendingKernelAckByReqID[reqID]
        if let ack = forceDenyAck {
            guard ack.sessionID == session.sessionID else {
                throw ApprovalDecisionError.approvalBelongsToAnotherSession(
                    reqID: reqID, ownerSessionID: ack.sessionID, requestedSessionID: session.sessionID
                )
            }
            guard decision.outcome == .deny else {
                throw ApprovalDecisionError.forceDenyPendingKernelAck(
                    reqID: reqID, requested: decision.outcome.rawValue, observedFailure: ack.observedFailure
                )
            }
        }

        // pending 表优先；查不到但持有 FORCE_DENY_PENDING_KERNEL_ACK 时，用**发起第一次强制 deny
        // 那一刻冻结下来的**输入重建（缓冲溢出的 reqId 从未进过 pending 表，这是它唯一的重试抓手）。
        let resolvedInfo: PendingApprovalAwaitingDecision?
        if let pending = pendingApprovalsByReqID[reqID] {
            resolvedInfo = pending
        } else if let ack = forceDenyAck {
            resolvedInfo = PendingApprovalAwaitingDecision(
                runID: ack.runID, openclawKind: ack.openclawKind,
                sessionID: ack.sessionID, allowedDecisions: ack.allowedDecisions
            )
        } else {
            resolvedInfo = nil
        }
        guard let info = resolvedInfo else {
            throw ApprovalDecisionError.approvalNotPending(reqID: reqID)
        }
        guard info.sessionID == session.sessionID else {
            throw ApprovalDecisionError.approvalBelongsToAnotherSession(
                reqID: reqID, ownerSessionID: info.sessionID, requestedSessionID: session.sessionID
            )
        }

        // 关卡 3：映射 + 校验 + 参数收口。抛错时 pending 表**不动**（见文档注释）。`wire` 是同一次
        // 映射算出的结果，留给关卡 4 比对——单一事实来源，不可能与实际发出的值不一致。
        // **刻意排在占槽位之前**：这一关抛错时一条 RPC 都没发出，没有任何在途状态需要别人等。
        //
        // rounds/0016：处于 `FORCE_DENY_PENDING_KERNEL_ACK` 时，成员校验里给 `deny` 补一个位置。
        // 理由与 `forceDenyPendingApprovalsBeforeStop`/`performQueueOverflowDeny` 刻意绕过这道校验
        // 完全同源：`deny` 由 openclaw schema 保证**恒在**允许集内（`ApprovalAllowedDecisionsSchema`
        // 的 `contains: Literal("deny")`，approvals.ts:79），而这是一次**强制 deny 的重试**，语义上
        // 不受该条请求 presentation 选项集的约束——不能被一道本不适用的校验挡住重试。补的**只有
        // `deny` 这一个值**（上面关卡 2b 已经保证只有 deny 能走到这里），任何 allow 档位一律不放宽。
        let effectiveAllowedDecisions: [String]
        if forceDenyAck != nil, !info.allowedDecisions.contains(OpenclawApprovalDecisionWire.deny.rawValue) {
            effectiveAllowedDecisions = info.allowedDecisions + [OpenclawApprovalDecisionWire.deny.rawValue]
        } else {
            effectiveAllowedDecisions = info.allowedDecisions
        }
        let (params, wire) = try makeApprovalResolveParams(
            reqID: reqID, openclawKind: info.openclawKind,
            decision: decision, allowedDecisionsFromRequest: effectiveAllowedDecisions
        )

        // 占住 in-flight 槽位——从这一刻起到 `endApprovalResolveInFlight` 之间，`stop()` 的 drain
        // 循环看得见这条在途决议，会等它落地才收敛（因此 `sessions.abort` 不可能在一条人工决议还
        // 在途时发出）。上面的 `awaitApprovalResolveSettled` 与这里的 `begin` 之间没有 await，
        // actor 隔离保证这一对是原子的；理论上仍抢不到时如实报 approval_not_pending（此刻确实有
        // 别人正在把它终态化），不静默重试。
        guard beginApprovalResolveInFlight(reqID: reqID, sessionID: session.sessionID, origin: .manual) else {
            throw ApprovalDecisionError.approvalNotPending(reqID: reqID)
        }
        defer { endApprovalResolveInFlight(reqID: reqID) }

        // rounds/0016（T-096 第 3 项）：有界等待。无界 await 时网关不回应答就永久挂起——用户点了
        // 一次按钮之后卡片永远停在"提交中"，而且这个 reqId 的 in-flight 槽位永久占位，随后的
        // `stop()` 也跟着挂死（drain 收敛条件里"无在途 resolve"永远不成立）。
        let result: JSONObject
        do {
            result = try await sendApprovalResolveBounded(reqID: reqID, params: params)
        } catch {
            // 这一次决议没有落地。**pending 表不动**（沿用既有纪律：审批在内核侧可能仍 pending，
            // 用户应该还能再试一次）；若这是一次 FORCE_DENY_PENDING_KERNEL_ACK 下的 deny 重试，
            // 刷新持久态里的失败形态与重试计数——持久态**不解除**，闸门继续关着。
            if let ack = forceDenyAck {
                recordForceDenyPendingKernelAck(
                    reqID: reqID, sessionID: session.sessionID, runID: ack.runID,
                    openclawKind: ack.openclawKind, allowedDecisions: ack.allowedDecisions,
                    origin: ack.origin, observedFailure: "deny 重试失败：\(error)"
                )
            }
            throw error
        }
        prettyPrint("RECV approval.resolve result (D1 §2.6 respondApproval)", result)

        // rounds/0016（T-096 第 2 项）：持久态的解除判据——**内核确认了一个 denied 终态**。
        // 两种形态都算数、且都是"这条审批确实已被拒绝"的权威依据：
        //   - `applied:true + status:denied`：本次重试被内核采纳（幂等 deny 的正常成功）；
        //   - `applied:false + status:denied`：内核记录里它**早就**是 denied（第一次强制 deny
        //     其实打成了，只是我们没收到应答）——目标已达成，没有任何可重试的东西。
        // 其余形态（终态是 allowed/expired/cancelled，或仍不确定）**不解除**闸门。注意
        // `applied:false` 仍然会在下面被如实报成 `approval_not_pending`（沿用 rounds/0015 的纪律：
        // 不把"别人写的终态"说成"你这次操作成功了"）——解除闸门与这次调用是否成功是两件事。
        if forceDenyAck != nil,
           jsonString(jsonObject(result["approval"])?["status"]) == "denied" {
            clearForceDenyPendingKernelAck(
                reqID: reqID,
                becauseOf: "deny 重试拿到内核确认的 denied 终态（applied=\(jsonBool(result["applied"]).map(String.init) ?? "nil")）"
            )
        }

        // 无论下面哪一关是否通过，这个 reqId 在内核侧都已经是终态了——先从 pending 表摘掉，再判定。
        pendingApprovalsByReqID.removeValue(forKey: reqID)
        pendingApprovalReqIDsBySessionID[session.sessionID]?.remove(reqID)
        if activeApprovalReqIDBySessionID[session.sessionID] == reqID {
            // D1 §6.2「#1 解决后 #2 浮现」：active pending 达到终态（RESOLVED_ALLOW/RESOLVED_DENY），
            // 把缓冲队列头部提升为新的 active pending。**在判定之前做**——无论内核兑现与否，这条
            // 审批在内核侧都已经终态化，队列没有理由继续被它挡住。
            promoteNextBufferedApprovalIfPossible(sessionID: session.sessionID, reasonHint: "人工决策终态化")
        }

        // 关卡 4a（rounds/0015 返工②，**新增**）：`applied:false` = openclaw 的
        // "approval_not_pending" 信号。源码形状（`approval.ts:462-475`）：`record.status !==
        // "pending"` 时 handler 回 `ok:true` + `{applied:false, approval:<别人赢下的终态快照>}`
        // ——**不是**错误帧。修前这条路径有一个静默成功的洞：用户点"拒绝"、而这条审批刚好已经被
        // `stop()` 强制 deny 掉，快照里 `status:"denied"` 会让 `verifyApprovalResolveHonored`
        // 判定 honored=true，`respondApproval()` 于是**正常返回**，UI 显示"你的拒绝已生效"——但
        // 事实是这次调用什么都没做，终态是别人写的。如实报 approval_not_pending。
        if jsonBool(result["applied"]) == false {
            throw ApprovalDecisionError.approvalNotPending(reqID: reqID)
        }

        try verifyApprovalResolveHonored(reqID: reqID, requested: wire, result: result)
    }

    public func capabilities(session: SessionHandle?) async throws -> CapabilityDescriptorPayload {
        throw KernelClientError.notImplemented("capabilities() 本轮 TODO 桩——未探测 openclaw capabilities 端点")
    }

    // MARK: - 内部：session 映射表 + 事件流生命周期

    /// rounds/00xx C：访问级别从 `private` 放宽到 `internal`（同一 `KernelClient` SwiftPM target 内
    /// 可见，见 app/Package.swift 的 target 划分——CLIRunner.swift 与本文件同属 `KernelClient`
    /// target，`-enable-testing` 之外这是唯一为了跨文件调用而放宽的访问级别，不是 public，不污染
    /// 包外可见的 API 面）——纯为诊断用途暴露：`CLIRunner.runL1CloseLoop` 需要打印 openclaw 真正的
    /// `key`（`sessions.create` 响应里的 `result["key"]`，subscribe/send/abort/delete 全部靠它寻址）
    /// 供事后 `GET /sessions/<key>/history` 对账用。**这不是** `SessionHandle.kernelSessionID`
    /// ——那个字段取的是 wire 响应的 `sessionId`（`kernelSessionID ?? kernelKey` 里 `sessions.create`
    /// 几乎总是带 `sessionId`，所以几乎总是走前一支，从未真正落到 `kernelKey`），两者是 openclaw
    /// 侧两个独立来源的字段（`key` 形如 `agent:<agentId>:dashboard:<uuid>`，见 openclaw
    /// `session-create-service.ts:buildDashboardSessionKey`；`sessionId` 是 `entry.sessionId`，
    /// 另一个独立的 `randomUUID()`），历史查询路由把 URL 路径段当 `key` 用（openclaw
    /// `sessions-history-http.ts:resolveSessionHistoryPath` ->
    /// `resolveGatewaySessionStoreTargetWithStore({ cfg, key: sessionKey })`），不是当 `sessionId`
    /// 用——CLIRunner 打印 SESSION_KEY 时必须用这个方法的返回值，不能用 `handle.kernelSessionID`。
    /// 本方法本身逻辑未改一行，纯访问级别调整。
    func kernelKey(for ourSessionID: String) -> String? {
        kernelKeyBySessionID[ourSessionID]
    }

    /// F3：per-run（或无 run 归属时按 session）单调递增 seq——供所有 mapper 调用的
    /// `nextSeq` 闭包共享同一份 actor 隔离状态。
    private func nextSeq(runID: String?, sessionID: String) -> Int {
        if let runID = runID {
            let next = (seqByRunID[runID] ?? 0) + 1
            seqByRunID[runID] = next
            return next
        }
        let next = (seqFallbackBySessionID[sessionID] ?? 0) + 1
        seqFallbackBySessionID[sessionID] = next
        return next
    }

    /// M5（收 T-045 codex 确认性再审 MUST-FIX）：一个 session 的全部派生缓存——per-run
    /// seq/toolCallId/usage、M1 approval 双向缓冲区（含从未配对成功的孤儿条目）、pendingStop、
    /// session 锁、F8 terminal 去重标记——统一在这里清干净。`finishEventContinuation`（stop()/
    /// 正常 subscribe 流结束）和 `handleTransportClosed`（transport 异常）两条路径都必须调用同一份
    /// 清理，不能像上一轮那样只清一半（前者只清了 per-run 缓存，后者干脆什么都不清；approval 缓存
    /// 更是只有 join 成功时才删除，pending-first 漏配对的条目会永久残留）。
    private func clearSessionDerivedCaches(sessionID: String) {
        for runID in runIDsBySessionID[sessionID] ?? [] {
            seqByRunID.removeValue(forKey: runID)
            lastToolCallIDByRunID.removeValue(forKey: runID)
            lastUsageByRunID.removeValue(forKey: runID)
        }
        runIDsBySessionID.removeValue(forKey: sessionID)
        lastRunIDBySessionID.removeValue(forKey: sessionID)
        seqFallbackBySessionID.removeValue(forKey: sessionID)

        for approvalID in approvalIDsBySessionID[sessionID] ?? [] {
            agentApprovalInfoByApprovalID.removeValue(forKey: approvalID)
            pendingSessionApprovalByApprovalID.removeValue(forKey: approvalID)
        }
        approvalIDsBySessionID.removeValue(forKey: sessionID)
        // rounds/0016：去重闸门本身也是 per-session 派生状态，随 session 一起清（它按 sessionID
        // 分桶，一行就够，不需要反向索引）。
        admittedApprovalIDsBySessionID.removeValue(forKey: sessionID)

        // rounds/0015 返工①：审批 FSM 的两块 per-session 状态同样随 session 一起清。缓冲队列里的
        // 条目**不**补发 `ApprovalBufferResolvedEvent`——session 正在终结，continuation 马上就会被
        // finish（`finishEventContinuation` 路径）或已经被 `finish(throwing:)`（transport 关闭
        // 路径），yield 要么无人消费要么静默丢弃；调用方经由 session_end 得知会话结束，这与
        // `handleApprovalTerminalSignal` 里 cancelled/gateway-restart 那一类的处置是同一条理由。
        activeApprovalReqIDBySessionID.removeValue(forKey: sessionID)
        bufferedApprovalsBySessionID.removeValue(forKey: sessionID)

        // rounds/0015 返工②：in-flight 槽位——**必须唤醒等待者再移除**，同 NOTE-1 对 pendingStop
        // waiter 的纪律（直接 removeValue 会让 `awaitApprovalResolveSettled` 里挂着的调用方永久
        // 挂起）。`endApprovalResolveInFlight` 内部就是"取出 + 清反向索引 + resume 全部 waiter"，
        // 直接复用，不另写一份。在途的那条 RPC 自己会因为 `failAllPending` 抛 transport 错误而
        // 结束，它的 `defer { endApprovalResolveInFlight }` 届时是安全的 no-op。
        //
        // rounds/0016（T-096 第 3 项）：在 `end` 之前先**兑现**每个槽位的有界等待收件箱。真实
        // transport 路径上 `failAllPending` 会让底层 RPC 抛错、经由 `settleApprovalResolve` 自然
        // 兑现；但那条链路依赖"底层 RPC 一定会被唤醒"这个前提（test-stub 路径、以及 session 被
        // 单独清理而 transport 仍活着的路径都不满足它）。在这里显式兑现，"in-flight 不永久占位"
        // 这条保证就不再有前提条件。
        for reqID in approvalResolveInFlightReqIDsBySessionID[sessionID] ?? [] {
            if let slot = approvalResolveInFlightByReqID[reqID], !slot.settled {
                settleApprovalResolve(
                    reqID: reqID, epoch: slot.epoch,
                    result: .failure(KernelClientError.protocolMismatch(
                        "approval.resolve 未落地：session \(sessionID) 的派生状态已被清理（transport 关闭 / 会话终结）"
                    ))
                )
            }
            endApprovalResolveInFlight(reqID: reqID)
        }
        approvalResolveInFlightReqIDsBySessionID.removeValue(forKey: sessionID)

        // rounds/0016（T-096 第 2 项）：FORCE_DENY_PENDING_KERNEL_ACK 同样是 per-session 派生状态
        // ——session 已经终结，这些 reqId 再没有任何重试路径可走，留着只会永久残留。
        for reqID in forceDenyPendingKernelAckReqIDsBySessionID[sessionID] ?? [] {
            forceDenyPendingKernelAckByReqID.removeValue(forKey: reqID)
        }
        forceDenyPendingKernelAckReqIDsBySessionID.removeValue(forKey: sessionID)

        // M3：session 结束时同样清掉"已产出、仍在 pending 等待决策"的审批表——不清理的话，一个从未被
        // stop() 强制处理过的孤儿 reqId（例如 session 走 shutdown/transportClosed 终结，而不是走
        // stop()）会永久残留在 pendingApprovalsByReqID 里。
        for reqID in pendingApprovalReqIDsBySessionID[sessionID] ?? [] {
            pendingApprovalsByReqID.removeValue(forKey: reqID)
        }
        pendingApprovalReqIDsBySessionID.removeValue(forKey: sessionID)

        // NOTE-1 防御性兜底：任何调用路径都不应该在 pendingStop 仍有存活 waiter 时直接
        // removeValue——那样等待中的 stop() 永远等不到 resume（T-047 复现的真挂起 bug）。正常情况下
        // 这里已经是 nil（transport 关闭路径已经由 handleTransportClosed ->
        // resolvePendingStopForTransportClose 提前 resolve 过，且那条路径还会带上 operation_completed
        // 镜像）；这几行只是最后一道防线——没有 continuation 引用发不出镜像，但至少唤醒等待者，绝不
        // 留永久挂起。
        if let danglingWaiter = pendingStops[sessionID]?.waiter {
            pendingStops[sessionID]?.waiter = nil
            pendingStops[sessionID]?.terminalEmitted = true
            danglingWaiter.resume(returning: .transportClosed)
        }
        pendingStops.removeValue(forKey: sessionID)
        lockStateBySessionID.removeValue(forKey: sessionID)
        sessionTerminalEmitted.remove(sessionID)

        // rounds/0012 ②：session 结束时同样清掉订阅 dispatch 屏障的残留状态——正常情况下
        // `subscriptionDispatchPending` 此刻已经不含这个 sessionID（订阅 RPC 早就 dispatch 过了），
        // 这里只是最后一道防线：若 session 在订阅 RPC 尚未 dispatch 完就被 transport 关闭等路径提前
        // 终结，任何仍在 `awaitSubscriptionRpcDispatchIfPending` 里挂起的 send()/stop() 调用会被
        // 唤醒（而不是永久挂起）——它们醒来后走到自己的 kernelKey 查找会独立发现 session 已经不在，
        // 如实报错，不会假装成功。
        subscriptionDispatchPending.remove(sessionID)
        if let waiters = subscriptionDispatchWaiters.removeValue(forKey: sessionID) {
            for waiter in waiters { waiter.resume() }
        }
    }

    private func finishEventContinuation(sessionID: String) {
        eventContinuations[sessionID]?.finish()
        eventContinuations.removeValue(forKey: sessionID)
        clearSessionDerivedCaches(sessionID: sessionID)
    }

    // MARK: - 内部：RPC 请求/响应关联

    private func request(method: String, params: JSONObject) async throws -> JSONObject {
        if let responder = testSupportRPCResponders[method] {
            prettyPrint("SEND req \(method) (test-stubbed, no real transport)", ["method": method, "params": params])
            return try await responder(params)
        }
        guard let task = task else { throw KernelClientError.notConnected }
        nextReqID += 1
        let id = "r\(nextReqID)"
        let frame: JSONObject = ["type": "req", "id": id, "method": method, "params": params]
        prettyPrint("SEND req \(method)", frame)
        let data = try encodeFrame(frame)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONObject, Error>) in
            self.pending[id] = continuation
            task.send(.data(data)) { error in
                if let error = error {
                    Task { await self.failPending(id: id, error: KernelClientError.transport(error.localizedDescription)) }
                }
            }
        }
    }

    private func failPending(id: String, error: Error) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func waitForNextEvent(named eventName: String) async throws -> JSONObject {
        try await withCheckedThrowingContinuation { continuation in
            self.oneShotEventWaiters[eventName] = continuation
        }
    }

    // MARK: - 内部：接收循环

    private func receiveLoop() async {
        guard let task = task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    handleIncoming(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        handleIncoming(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                handleTransportClosed(error: KernelClientError.transport("\(error)"))
                break
            }
        }
    }

    /// 传输中断（真实 WS 断开，或 `testSupportSimulateTransportClosed` 模拟）的统一处理：先尽力给
    /// 每个尚未产出过 terminal 的活跃 session 补一条 sessionEnd(reason:.transportClosed)——F8：与
    /// shutdown/stop 两条路径共享 `sessionTerminalEmitted` 去重标记，不会对同一个 session 重复/
    /// 矛盾地产出 sessionEnd；然后 `failAllPending` 收尾所有还在等待的 RPC/事件流。抽成独立方法只是
    /// 为了让测试能直接触发这条路径（M6：真实驱动 shutdown+transport close 两条路径，不是像上一轮
    /// 那样用两次同样的 shutdown 帧代替）。
    private func handleTransportClosed(error: Error) {
        for (ourSessionID, continuation) in eventContinuations {
            // NOTE-1（T-047 grok 复核，真挂起 bug 修复）：若这个 session 有一个仍在等待
            // aborted-run 终态确认的 pendingStop，必须先把它的
            // operation_completed(aborted_effect_unknown) 镜像 yield 进 continuation、唤醒等待中的
            // stop()，再产出 sessionEnd(transportClosed)——顺序对应 D1 §9.3"先终态、后
            // session_end"的既有约定（stop() 成功路径同样是先 emitOperationCompletedMirror 再
            // emitStopSessionEndAndFinish），也必须赶在下面 failAllPending 把 continuation
            // finish(throwing:) 之前做（之后 yield 静默丢弃）。
            resolvePendingStopForTransportClose(sessionID: ourSessionID)

            guard !sessionTerminalEmitted.contains(ourSessionID) else { continue }
            sessionTerminalEmitted.insert(ourSessionID)
            continuation.yield(makeSessionEndEventForTransportClosed(
                ourSessionID: ourSessionID,
                nextSeq: { self.nextSeq(runID: nil, sessionID: ourSessionID) }
            ))
        }
        failAllPending(error: error)
    }

    private func failAllPending(error: Error) {
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        for (_, waiter) in oneShotEventWaiters {
            waiter.resume(throwing: error)
        }
        oneShotEventWaiters.removeAll()
        // M5：transport 异常路径上一轮只 finish 了 continuation，从不清理per-session派生缓存
        // （seq/toolCallId/usage/approval 双向缓冲/pendingStop/锁/terminal 标记）——这里改为跟
        // `finishEventContinuation` 共享同一份 `clearSessionDerivedCaches`。
        for (sessionID, cont) in eventContinuations {
            cont.finish(throwing: error)
            clearSessionDerivedCaches(sessionID: sessionID)
        }
        eventContinuations.removeAll()
    }

    // MARK: - SG-10 rounds/0012 ① 临时插桩（取证工具，不是修复；见
    // rounds/0012/evidence/item1-mechanism-localization.md §3/§4 与 scope-lock.md ①）
    //
    // `handleSessionMessageEvent`/`handleAgentEvent`/`handleSessionApprovalEvent`/
    // `handleShutdownEvent` 四个被消费 case 现在只有映射失败/旁路才打印（`prettyPrint`），成功产出
    // D2 事件的路径完全静默——rounds/0011 的运行日志因此一条承载 assistant 文本的帧都没留下，无法
    // 判断 content 形状、`index` 取值、delta 是否重复。本节只做观察，不改变任何映射语义或
    // `continuation.yield` 的内容/时序，由 `AGENT_KERNEL_WIRE_TRACE` 环境变量整体开关；未设置时
    // `wireTraceCollector` 全程保持 nil，四个 handler 内部新增的 `wireTraceCollector?.append(event)`
    // 都是 Optional chaining 的 no-op，输出与插桩之前逐字节一致。

    /// 仅在被 `traceWireDispatch` 追踪的分派期间非 nil；四个 handler（及它们共用的
    /// `emitApprovalRequestIfPossible`）内部已有的 `continuation.yield(event)` 调用点各自紧跟一行
    /// `wireTraceCollector?.append(event)`——yield 本身的参数与调用时机一个字都没变，这里只是在同一
    /// 行旁边多看一眼、记下来。
    private var wireTraceCollector: [EventMessageUnion]?

    /// 包一层：`handleIncoming` 分派给四个已消费 case 时统一走这里。`AGENT_KERNEL_WIRE_TRACE` 未设置
    /// 时直接调用 `handler()`，不做任何额外的事——这是"默认关闭"的唯一判断点，函数体第一行就返回。
    /// 设置时打开收集器、跑 handler（handler 内部的 `continuation.yield` 调用不受影响，只是被就地
    /// 多记一笔)、把收集到的事件与原始帧一起落盘。`previousCollector` 保存/恢复是防御性的重入保护
    /// （目前的调用路径下不会真的重入，但成本几乎为零）。
    private func traceWireDispatch(eventName: String, frame: JSONObject, _ handler: () -> Void) {
        guard let tracePath = wireTraceEnabledPath() else {
            handler()
            return
        }
        let previousCollector = wireTraceCollector
        wireTraceCollector = []
        handler()
        let produced = wireTraceCollector ?? []
        wireTraceCollector = previousCollector
        appendWireTraceLine(buildWireTraceRecord(eventName: eventName, frame: frame, produced: produced), toPath: tracePath)
    }

    /// 把一次分派的「wire 帧 + 产出的 D2 事件」拼成一条可写盘的 JSON 对象。`frame` 先过
    /// `redactedCopy`（`OpenclawWire.swift`，F7/M4 rework 记录的敏感键判定，`isSensitiveKey` 文档
    /// 注释）再落盘——复用既有脱敏实现，不新写一套。`produced` 为空时附一份从帧本身摘出的
    /// `emptyHint`（如 `message.role`/`stream`），供人工判断"为什么这条帧没有映射出任何事件"而不用
    /// 每次都展开整份帧。
    private func buildWireTraceRecord(eventName: String, frame: JSONObject, produced: [EventMessageUnion]) -> JSONObject {
        let safeFrame = (redactedCopy(frame) as? JSONObject) ?? frame
        var record: JSONObject = [
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "dispatchCase": eventName,
            "wireFrame": safeFrame,
            "producedCount": produced.count,
            "producedEvents": produced.map { wireTraceEventSummary($0) },
        ]
        if produced.isEmpty, let hint = wireTraceEmptyHint(eventName: eventName, payload: frame["payload"] as? JSONObject) {
            record["emptyHint"] = hint
        }
        return record
    }

    // MARK: - rounds/0012 ③ wire messageSeq 旁路上报（诊断钩子，不是 KernelClient 协议的一部分）
    //
    // 背景（`rounds/0012/evidence/item3-messageseq.md`）：openclaw `session.message` wire 帧的
    // `payload.messageSeq` 是**会话 transcript 的消息计数**（源码判定：
    // `kernels/openclaw/src/gateway/server-session-events.ts:189-215`，"fall back to the current
    // transcript line count for cursor-compatible live history"）——它既不是 D1/D2 承诺的 per-run
    // `seq`（那是 `nextSeq(runID:sessionID:)` 维护的 kernel-client 本地计数器，结构上不可能倒退，见
    // 上面"MARK: F3"小节），也从未出现在 D2 11 变体判别联合的任何一个字段里（`EventMessageUnion`/
    // `MessageDeltaEventMessagePayload` 等逐个检查过，没有一个字段是它）。要在 `CLIRunner` 的
    // `EventAssertionCollector` 上加一条基于它的不变量断言（见 CLIRunner.swift
    // `EventAssertionCollector.recordMessageSeq` 文档注释），必须先想清楚它怎么从这个 actor 内部走
    // 出去——**不能**为此改 D2 schema（塞进某个 payload 会引入一个和"消息标识" `messageID`（rounds/
    // 0012 ①' 新增的那个可选字段）语义完全不同的东西，却挤在同一次 schema 改动窗口里，职责不清），
    // 也**不能**改 `KernelClient` 协议签名（7 个方法本身与这个诊断信号无关）。
    //
    // 选择的路径：**闭包旁路**，不是新开一条 `AsyncStream`。理由与代价：
    //   - 新开一条 `AsyncStream<Int>`（类似 `subscribe()` 自己那一套 continuation 存取/session
    //     键控/finish 生命周期管理）能在类型层面把两个域分得更彻底，但要求这条新流跟主事件流一样
    //     正确处理 session 结束/stop/shutdown/transport-closed 四条收尾路径的 `finish()`，否则
    //     `CLIRunner` 里消费它的那个 Task 会在会话结束后继续挂起——这份复杂度对"只是把一个已经在读
    //     的整数旁路传出去"这件事而言不成比例。
    //   - 复用现成的 `wireTraceCollector` 那条路（env var 开关 + 落盘 JSONL，见上面"SG-10 rounds/
    //     0012 ① 临时插桩"小节）更省事，但那条路径服务的是**离线事后取证**（`CLIRunner` 一次真实
    //     e2e 跑完之后人工翻 JSONL），且默认关闭（依赖 `AGENT_KERNEL_WIRE_TRACE` 环境变量）——
    //     `EventAssertionCollector.printFinalAssertions()` 在 `observeTask` join 之后立即读取收集
    //     器状态，如果 messageSeq 只落在磁盘上，`CLIRunner` 还得反过来在跑完之后单独解析这份 trace
    //     文件才能喂给断言收集器，把一个本该"边收边核对"的实时断言拆成两阶段，还额外要求一个不相关
    //     的环境变量必须被设置——这和被取代的"空 seq 断言"一样脆弱（断言能不能生效取决于一个本不该
    //     相关的开关）。
    //   - 闭包旁路：`CLIRunner` 在 `subscribe()` 之前调用一次 `setWireMessageSeqObserver` 注册，
    //     `handleSessionMessageEvent` 每次读到 `payload.messageSeq` 就同步调一次——不需要开关、不
    //     需要落盘、不需要额外的 stream 生命周期管理，默认（未注册）是纯粹的 no-op。
    //
    // 代价（如实登记，不是没有）：
    //   1. 这是给 `OpenclawGatewayKernelClient` 这个**具体类**新增的公开方法，不在 `KernelClient`
    //      协议 7 方法之列——只持有 `any KernelClient` 抽象类型的调用方看不到这个钩子，这是有意的
    //      （D1 §2 的窄腰协议本就不该为一个诊断信号扩面）。
    //   2. 闭包是从这个 actor **自己的隔离执行上下文**同步调用的，而 `EventAssertionCollector` 的
    //      其余三条不变量都只在 `observeTask` 消费主事件流的那个 Task 里被写——两者是不同的并发上
    //      下文。这个新钩子因此不能沿用"只在 observeTask 里写、join 之后读"那条 happens-before 论
    //      证，`EventAssertionCollector` 那一侧为此新增了一把独立的锁，见该类 `recordMessageSeq`/
    //      `messageSeqLock` 的文档注释。
    //   3. 只在 `handleSessionMessageEvent` 这一条 dispatch 路径调用——如果 openclaw 未来在其它事
    //      件类型上也开始携带 messageSeq，这里不会自动覆盖。现状（`item3-messageseq.md` §1 源码判
    //      定）messageSeq 只出现在 `session.message`，与当前覆盖范围一致，如实标注为当前范围而非
    //      将来的承诺。

    /// 未注册（`nil`，默认值）时 `handleSessionMessageEvent` 里的调用点是纯粹的 no-op，行为与新增
    /// 之前逐字节一致——与 `wireTraceCollector` 同一条"默认关闭、不改变主路径行为"的纪律。
    private var onWireMessageSeqObserved: (@Sendable (Int) -> Void)?

    /// 供 `CLIRunner`（生产路径）与 `FrameReplayTests`（`@testable import`，测试路径）调用——跨
    /// actor 隔离设置上面的钩子，命名与调用约定对齐同文件 `testSupportStubRPC` 那一个已有的
    /// "`@escaping @Sendable` 闭包，通过显式方法赋给 actor-isolated 存储属性"先例，不是本文件第一
    /// 次这么做。
    func setWireMessageSeqObserver(_ observer: @escaping @Sendable (Int) -> Void) {
        onWireMessageSeqObserved = observer
    }

    private func handleIncoming(_ data: Data) {
        guard let frame = try? decodeFrame(data) else { return }
        guard let type = frame["type"] as? String else { return }

        switch type {
        case "res":
            guard let id = frame["id"] as? String else { return }
            guard let continuation = pending.removeValue(forKey: id) else { return }
            let ok = (frame["ok"] as? Bool) ?? false
            if ok {
                let payload = (frame["payload"] as? JSONObject) ?? [:]
                continuation.resume(returning: payload)
            } else {
                let err = (frame["error"] as? JSONObject) ?? [:]
                let code = (err["code"] as? String) ?? "unknown"
                let message = err["message"] as? String
                continuation.resume(throwing: KernelClientError.rpcRejected(code: code, message: message))
            }

        case "event":
            guard let eventName = frame["event"] as? String else { return }
            if let waiter = oneShotEventWaiters.removeValue(forKey: eventName) {
                let payload = (frame["payload"] as? JSONObject) ?? [:]
                waiter.resume(returning: payload)
                return
            }
            // session.message 之外还要分发 agent(command_output/lifecycle/thinking/error/item/
            // approval)、session.approval、全局 shutdown 三类 wire 事件——D2 11 变体里除
            // message_delta/tool_call 之外的大多数都不是从 session.message 来的。
            switch eventName {
            case "session.message":
                traceWireDispatch(eventName: eventName, frame: frame) { handleSessionMessageEvent(frame) }
            case "agent":
                traceWireDispatch(eventName: eventName, frame: frame) { handleAgentEvent(frame) }
            case "session.approval":
                traceWireDispatch(eventName: eventName, frame: frame) { handleSessionApprovalEvent(frame) }
            case "exec.approval.requested":
                // rounds/0016：握手补上 `exec-approvals` cap 之后才会收到这条事件（见 connect() 的
                // caps 注释）。**修前它落在下面的 `default:` 分支被原样打印后丢弃。**
                traceWireDispatch(eventName: eventName, frame: frame) { handleExecApprovalRequestedEvent(frame) }
            case "shutdown":
                traceWireDispatch(eventName: eventName, frame: frame) { handleShutdownEvent(frame) }
            default:
                prettyPrint("RECV event \(eventName) (未处理的旁路事件，原样打印)", frame)
            }

        default:
            break
        }
    }

    /// 按 openclaw 原生 key 反查我们自己铸造的 sessionID——四个事件 handler（session.message/
    /// agent/session.approval）共享同一套"payload.sessionKey -> ourSessionID -> continuation"
    /// 查找逻辑，抽成一个小helper 避免重复。
    private func ourSessionID(forKernelKey kernelKey: String) -> String? {
        kernelKeyBySessionID.first(where: { $0.value == kernelKey })?.key
    }

    private func handleSessionMessageEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        // rounds/0012 ③：wire messageSeq 旁路上报——必须在这里（早于下面 `events.isEmpty` 的 early
        // return），因为 messageSeq 对**每一条** session.message 帧都存在，包括 role=="user" 的回显
        // 帧（`item3-messageseq.md` §2 实测的 `1,1,2,3,3,4,5,6` 序列本身就交替着 user/assistant 两
        // 种角色的帧——两个 1 分别是同一条 user 消息的 status+delta 两帧）。下面
        // `mapOpenclawSessionMessageToKernelEvents` 只关心 role=="assistant"（见 EventMapping.swift
        // 头注释①），那条"只看 assistant"的规则是 D2 事件映射自己的语义，不能延伸到这里——messageSeq
        // 是 transcript 层面的计数，与"这一帧有没有映射出 D2 事件"是两件独立的事。**这是本函数里唯一
        // 一处不产出/不影响任何 D2 事件的旁路代码**——`onWireMessageSeqObserved` 只读，不改变
        // `payload`、不影响下面的映射结果，见该属性上方"MARK: - rounds/0012 ③"的完整文档注释（路径
        // 选择理由 + 代价）。
        if let messageSeq = jsonInt(payload["messageSeq"]) {
            onWireMessageSeqObserved?(messageSeq)
        }

        // 顺带刷新 runId/usage 缓存——session.message 的 session 快照里带 activeRunIds，assistant
        // 消息自己带 usage。F1：usage 缓存改为 **per-run**（用刚刷新出来的 runId 做键），不再是
        // per-session，避免上一个 run 的残留 usage 串给下一个 run 的 turn_complete。
        var currentRunID = lastRunIDBySessionID[ourSessionID]
        if let sessionSnapshot = payload["session"] as? JSONObject,
           let activeRunIDs = sessionSnapshot["activeRunIds"] as? [Any],
           let firstRunID = activeRunIDs.first as? String {
            lastRunIDBySessionID[ourSessionID] = firstRunID
            runIDsBySessionID[ourSessionID, default: []].insert(firstRunID)
            currentRunID = firstRunID
        }
        if let message = payload["message"] as? JSONObject, let usage = message["usage"] as? JSONObject,
           let input = jsonInt(usage["input"]), let output = jsonInt(usage["output"]),
           let runID = currentRunID {
            lastUsageByRunID[runID] = (input: input, output: output)
        }

        let runIDHint = currentRunID
        let sid = ourSessionID
        let events = mapOpenclawSessionMessageToKernelEvents(
            payload, ourSessionID: ourSessionID, runIDHint: runIDHint,
            nextSeq: { self.nextSeq(runID: runIDHint, sessionID: sid) }
        )
        if events.isEmpty {
            prettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一）", frame)
            return
        }
        for event in events {
            if case .toolCall(let toolCall) = event, let runID = runIDHint {
                // F1：per-run 缓存（不是 per-session），approval 的 toolCallId 时序关联（F4 已改用
                // 更权威的 agent(stream:"approval") 来源，这里保留只是为了兼容潜在的其它读者/诊断）。
                lastToolCallIDByRunID[runID] = toolCall.payload.toolCallID
            }
            continuation.yield(event)
            wireTraceCollector?.append(event)
        }
    }

    /// `agent` wire 事件——`payload.stream` 分好几种，本轮 dispatch：`command_output`(phase:end)、
    /// `item`(kind:tool,phase:end，非 exec 工具)、`lifecycle`(phase:end/error)、`thinking`、`error`、
    /// `approval`(只做 toolCallId 关联缓存，不直接产出事件，见 F4)。其余 stream（run_status/usage/
    /// assistant/plan/compaction 等，均为 openclaw 自有 UI 进度信号，D1 11 变体没有对应位置）原样
    /// 打印、不映射。
    private func handleAgentEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        // agent 事件的 payload.runId 是本轮拿到 runIDHint 最可靠的现场来源之一（session.create
        // 之后、真正 send() 之前也可能已经有别的 run 在跑），顺带刷新缓存。
        if let runID = payload["runId"] as? String {
            lastRunIDBySessionID[ourSessionID] = runID
            runIDsBySessionID[ourSessionID, default: []].insert(runID)
        }

        guard let stream = payload["stream"] as? String, let data = payload["data"] as? JSONObject else {
            return
        }
        let runIDHint = lastRunIDBySessionID[ourSessionID]
        // F3：ts 取 `agent` wire 帧外层 payload.ts（openclaw `enrichAgentEvent` 盖章的事件发生时刻，
        // `infra/agent-events.ts:628` `ts: Date.now()`），不用 Date()。
        let originTS = msEpochToDate(jsonInt(payload["ts"]))
        let sid = ourSessionID
        let nextSeqForRun: () -> Int = { self.nextSeq(runID: runIDHint, sessionID: sid) }

        switch stream {
        case "command_output":
            if let event = mapOpenclawAgentCommandOutputToToolResult(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
                wireTraceCollector?.append(event)
            }

        case "item":
            // F5：非 exec 工具的 toolResult 来源。exec 工具（"exec"/"bash"）继续只信任
            // command_output（有真实 output/exitCode），这里显式排除避免同一个 toolCallId 产出两条
            // 矛盾的 toolResult。
            guard jsonString(data["kind"]) == "tool", !isOpenclawExecToolName(jsonString(data["name"])) else {
                break
            }
            if let event = mapOpenclawAgentToolItemToToolResult(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
                wireTraceCollector?.append(event)
            }

        case "thinking":
            if let event = mapOpenclawAgentThinkingToKernelEvent(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
                wireTraceCollector?.append(event)
            }

        case "error":
            if let event = mapOpenclawAgentErrorToKernelEvent(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
                wireTraceCollector?.append(event)
            }

        case "approval":
            // F4/M1：这条 agent 帧本身不直接产出 D2 事件——真正的 approval_request 仍由
            // session.approval(phase:pending) 产出（它才有 timeoutMs/presentation 等完整字段），
            // 这里只是给它提供不会串号的 {runId,toolCallId} 来源。具体的 join 语义见
            // `recordAgentApprovalAssociation` 的文档注释（该 helper 由本分支与
            // `lifecycle`+`phase:"waiting-approval"` 分支共用，两条 stream 都是真实来源）。
            if jsonString(data["phase"]) == "requested",
               let approvalID = jsonString(data["approvalId"]),
               let toolCallID = jsonString(data["toolCallId"]),
               let approvalRunID = runIDHint {
                recordAgentApprovalAssociation(
                    approvalID: approvalID, toolCallID: toolCallID,
                    runID: approvalRunID, ourSessionID: ourSessionID
                )
            }

        case "lifecycle":
            guard let phase = jsonString(data["phase"]) else { break }
            // rounds/0016 live 实测新增的第二条关联来源：`stream:"lifecycle"` +
            // `data.phase:"waiting-approval"`（携带 `approvalId`/`toolCallId`，与
            // `stream:"approval"` + `phase:"requested"` 的字段形状一致）。它**不是** run 终态信号，
            // 在下面的 end/error 判定之前就地消费掉，理由与源码依据见
            // `recordAgentApprovalAssociation` 的文档注释。
            if phase == "waiting-approval" {
                if let approvalID = jsonString(data["approvalId"]),
                   let toolCallID = jsonString(data["toolCallId"]),
                   let approvalRunID = runIDHint {
                    recordAgentApprovalAssociation(
                        approvalID: approvalID, toolCallID: toolCallID,
                        runID: approvalRunID, ourSessionID: ourSessionID
                    )
                }
                break
            }
            guard phase == "end" || phase == "error" else { break }
            guard let runID = runIDHint else {
                // turnComplete/operationCompleted 的 runID 字段在 D2 里是必填——理论上不会缺失
                // （lifecycle 事件本身携带真实 runId），真缺失时诚实跳过，不拿编造值填充。
                break
            }
            let aborted = jsonBool(data["aborted"]) ?? false
            if aborted {
                if var pendingForRun = pendingStops[ourSessionID], pendingForRun.affectedRunID == runID, !pendingForRun.terminalEmitted {
                    // F6：单个 operation_completed + turn_complete(cancelled)，用 stop()/interrupt()
                    // 铸造的唯一 operationId，且对同一次 pendingStop 只做一次（后续同 run 的收尾帧，如
                    // 真实样本里 phase:"end" 之后常跟的 phase:"error","This operation was
                    // aborted" 帧，被下面 else 分支丢弃）。
                    // M3：这次 stop()/interrupt() 在发起 sessions.abort 之前强制 deny 掉的 reqId
                    // （如有）——D1 §6.2 M3 要求同步列进这个 run 的 TurnCompleteEvent.forceResolvedApprovals。
                    let forceResolvedApprovals = pendingForRun.forceResolvedApprovalReqIDs.isEmpty
                        ? nil : pendingForRun.forceResolvedApprovalReqIDs
                    // rounds/0020：`operationKind` 按这次 pendingStop 真正的发起者传（stop()/
                    // interrupt() 共享同一张表，见 `PendingStop.operationKind` 文档注释），不再
                    // 隐式全部标注成 stop。
                    let events = mapOpenclawAgentLifecycleToAbortTerminalEvents(
                        data, ourSessionID: ourSessionID, runID: runID, operationID: pendingForRun.operationID,
                        originTS: originTS, cachedUsage: lastUsageByRunID[runID],
                        forceResolvedApprovals: forceResolvedApprovals, operationKind: pendingForRun.operationKind,
                        nextSeq: nextSeqForRun
                    )
                    for event in events {
                        continuation.yield(event)
                        wireTraceCollector?.append(event)
                    }
                    pendingForRun.terminalEmitted = true
                    pendingStops[ourSessionID] = pendingForRun
                    lastUsageByRunID.removeValue(forKey: runID)
                    resolvePendingStopWaiter(sessionID: ourSessionID, outcome: .terminalObserved)
                } else if pendingStops[ourSessionID] == nil {
                    // 理论上不会出现——stop()/interrupt()（rounds/0020 起两者都会）在发起
                    // sessions.abort 之前必然先在 pendingStops 里登记一条条目，因此任何一条真正由
                    // 我们自己触发的 abort 所产生的 aborted lifecycle 帧，理应总能在上面的分支里找到
                    // 匹配的 pendingStop。这里仍然保留纯防御性兜底：自己派生一个 operationId，保持
                    // "至少不丢事件"的旧行为，同时如实标注这是非预期路径。`operationKind` 没有任何
                    // 发起者信息可用（既不知道是不是我们发起的、更不知道是 stop 还是 interrupt），
                    // 延续修前唯一曾经存在过的取值 `.stop`——这不是"猜它是 stop"，只是在没有信息时
                    // 保持这条从未被真正观察到过的路径的历史输出不变，不引入新的分支语义。
                    let fallbackOperationID = "\(ourSessionID)-abort-\(runID)-unowned"
                    // 这条防御性兜底路径本来就没有关联到任何 stop()/interrupt() 的 pendingStop——
                    // 不存在"这次强制 deny 过谁"的信息可以塞，forceResolvedApprovals 如实传 nil。
                    let events = mapOpenclawAgentLifecycleToAbortTerminalEvents(
                        data, ourSessionID: ourSessionID, runID: runID, operationID: fallbackOperationID,
                        originTS: originTS, cachedUsage: lastUsageByRunID[runID],
                        forceResolvedApprovals: nil, operationKind: .stop, nextSeq: nextSeqForRun
                    )
                    for event in events {
                        continuation.yield(event)
                        wireTraceCollector?.append(event)
                    }
                    lastUsageByRunID.removeValue(forKey: runID)
                }
                // else：已经为这次 stop() 发过 terminal——如实丢弃这条收尾帧，不重复产出。
            } else {
                // M3：极罕见竞态——force-deny 已经生效、sessions.abort 尚未真正让这个 run 落地
                // aborted 状态之前，run 自己先自然完成（这条 lifecycle 帧走的是 aborted:false 分支）。
                // 即便如此，仍要把已经强制 deny 掉的 reqId 挂到这条 TurnCompleteEvent 上——不能因为
                // 走的是"正常结束"分支就丢失这个信息（D1 §6.2 M3 只要求"该 run 的 TurnCompleteEvent"
                // 带上 forceResolvedApprovals，没有区分它是从 aborted 分支还是正常分支产出的）。
                let forceResolvedApprovals: [String]? = {
                    guard let pendingForRun = pendingStops[ourSessionID], pendingForRun.affectedRunID == runID,
                          !pendingForRun.forceResolvedApprovalReqIDs.isEmpty else { return nil }
                    return pendingForRun.forceResolvedApprovalReqIDs
                }()
                let event = mapOpenclawAgentLifecycleToTurnComplete(
                    data, ourSessionID: ourSessionID, runID: runID, originTS: originTS,
                    cachedUsage: lastUsageByRunID[runID], forceResolvedApprovals: forceResolvedApprovals,
                    nextSeq: nextSeqForRun
                )
                continuation.yield(event)
                wireTraceCollector?.append(event)
                lastUsageByRunID.removeValue(forKey: runID)
            }

        default:
            // run_status/usage/assistant/plan/compaction 等：openclaw 自有 UI 进度信号，D1 11 变体
            // 没有对应位置，如实不映射。
            break
        }
    }

    /// 采集 `agent` 帧携带的 `approvalId -> {runId, toolCallId}` 精确关联，并与 `session.approval`
    /// 做双向 join。**两条 stream 都会送这份关联**，本方法被两个分支共用：
    ///
    ///  - `agent(stream:"approval", data.phase:"requested")`
    ///    （`agents/embedded-agent-subscribe.handlers.tools.ts:1665-1699`，经
    ///    `infra/agent-activity-events.ts:76-86` `emitAgentApprovalEvent` 广播）——exec 工具**不**
    ///    内联等待、直接返回 `approval-pending` 工具结果时走这条。
    ///  - `agent(stream:"lifecycle", data.phase:"waiting-approval")`
    ///    （`agents/bash-tools.exec-host-gateway.ts:1085-1091`）——exec 工具**内联等待**网关审批时
    ///    走这条。判别键是同文件 `:414-428` 的 `shouldAwaitGatewayApprovalInline()`：
    ///    `approvalFollowupMode` 未设置且 `isNativeApprovalChannel(turnSourceChannel)` 为真才内联，
    ///    而 webchat 正是 native approval channel（`utils/message-channel.ts:95-105`）。
    ///
    /// **rounds/0016 live 实测坐实**：我们的 mac 壳以 webchat 身份接入，收到的是**后者**——冻结帧
    /// `.harnessloop/goals/20260718-002-agent-app/rounds/0015/evidence/live/raw/approval-frames-extract.json`
    /// 里两条 `agent` 帧均为 `stream:"lifecycle"` / `data.phase:"waiting-approval"`，携带
    /// `approvalId`+`toolCallId`。此前采集处只认 `stream:"approval"`+`phase:"requested"`，这两条帧
    /// 落进 `case "lifecycle"` 被 end/error 守卫丢弃 → `agentApprovalInfoByApprovalID` 始终为空 →
    /// 两条 `session.approval(phase:"pending")` 全被缓冲、`producedEvents` 为空 → UI 无审批卡片。
    /// 两条来源是同一功能的**互斥分支**（而不是"值变了"），因此这里是**兼容**：两条都接。
    ///
    /// M1 订正（沿用）：`runID` 必须是**这一条 agent 帧自己的** `payload.runId`（调用点已用它刷新过
    /// `lastRunIDBySessionID`，此刻 `runIDHint` 精确对应这次审批），而不是等 `session.approval`
    /// 落地时再查全 session 的"最近活跃 run"——那时别的 run 的审批帧插队会串号（对抗审 T-045 M1）。
    /// 按 approvalId 存好 `{runId,toolCallId}` 之后双向 join：
    ///   - 若 `session.approval(pending)` 已先到达并缓冲在 `pendingSessionApprovalByApprovalID`，
    ///     现在信息齐了，立即补发 approvalRequest。
    ///   - 否则缓存 `{runId,toolCallId}`，等 `session.approval` 后到时再用。
    private func recordAgentApprovalAssociation(
        approvalID: String, toolCallID: String, runID: String, ourSessionID: String
    ) {
        // rounds/0016：同 handleSessionApprovalEvent 的理由——`exec.approval.requested`
        // 已经产出过这次审批时，这条最晚到达的 agent 帧不再需要参与 join，缓存它只会留下
        // 一条永远配不上对的孤儿条目。
        guard !approvalAlreadyAdmitted(approvalID, ourSessionID: ourSessionID) else { return }
        approvalIDsBySessionID[ourSessionID, default: []].insert(approvalID)
        if let bufferedSessionApproval = pendingSessionApprovalByApprovalID.removeValue(forKey: approvalID) {
            emitApprovalRequestIfPossible(
                payload: bufferedSessionApproval.payload, ourSessionID: bufferedSessionApproval.ourSessionID,
                runID: runID, toolCallID: toolCallID
            )
            approvalIDsBySessionID[ourSessionID]?.remove(approvalID)
        } else {
            agentApprovalInfoByApprovalID[approvalID] = AgentApprovalInfo(runID: runID, toolCallID: toolCallID)
        }
    }

    /// `session.approval` wire 事件——subscribe() 已在 `sessions.messages.subscribe` 参数里带上
    /// `includeApprovals:true`（见 subscribe() 实现），否则收不到这个事件。
    ///
    /// **M1 订正**：上一轮如果这条 `pending` 帧先于对应的关联 `agent` 帧到达
    /// （`toolCallIDForApprovalID` 查不到），会直接 `return nil`——`approval_request` 就此永久丢失，
    /// 即使 agent 帧随后真的到达也不会补发（对抗审 T-045 M1 第二个 REPRO：反向到达时
    /// `eventTypes=["evt.session_end"]`，approval_request 完全缺席）。本轮改为双向缓冲 join：查不到
    /// 就把整条 payload 按 approvalId 缓冲起来，等 agent 帧补上 `{runId,toolCallId}` 时由
    /// `recordAgentApprovalAssociation` 补发（`handleAgentEvent` 的 `"approval"` 与
    /// `"lifecycle"`+`phase:"waiting-approval"` 两个分支都会走到它，见该方法文档注释）。
    private func handleSessionApprovalEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard eventContinuations[ourSessionID] != nil else { return }

        guard jsonString(payload["phase"]) == "pending" else {
            // terminal 分支：**仍然不映射成任何一个 D2 11 变体**（reason 词表不相交，见
            // EventMapping.swift ④ 的论证，那个结论没变），但 rounds/0015 返工①起它不再被整条
            // 丢弃——它是审批 FSM 唯一的内核侧终态输入源，见 `handleApprovalTerminalSignal`。
            prettyPrint("RECV session.approval（phase:terminal，不映射成 D2 事件，仅驱动审批 FSM）", frame)
            handleApprovalTerminalSignal(payload, ourSessionID: ourSessionID)
            return
        }
        guard let approvalID = (payload["approval"] as? JSONObject)?["id"] as? String else { return }

        // rounds/0016：`exec.approval.requested` 可能已经把这次审批产出过了（它自带
        // {runId,toolCallId}，不需要等 agent 帧）。此时既不能重复产出，也不能把这条 payload 塞进
        // 双向 join 缓冲区——那会变成一条永远等不到配对、只能靠 session 结束才清掉的孤儿条目。
        guard !approvalAlreadyAdmitted(approvalID, ourSessionID: ourSessionID) else {
            prettyPrint("RECV session.approval(phase:pending)（该 approvalId 已由 exec.approval.requested 产出过，跳过）", frame)
            return
        }

        if let agentInfo = agentApprovalInfoByApprovalID.removeValue(forKey: approvalID) {
            // agent(stream:"approval") 已经先到达，缓存里有准确的 {runId,toolCallId}——立即 join。
            approvalIDsBySessionID[ourSessionID]?.remove(approvalID)
            emitApprovalRequestIfPossible(
                payload: payload, ourSessionID: ourSessionID, runID: agentInfo.runID, toolCallID: agentInfo.toolCallID
            )
        } else {
            // M1 双向 join：agent 帧还没到——缓冲这条 session.approval，等它来补发，不再直接丢弃。
            pendingSessionApprovalByApprovalID[approvalID] = PendingSessionApproval(payload: payload, ourSessionID: ourSessionID)
            approvalIDsBySessionID[ourSessionID, default: []].insert(approvalID)
            prettyPrint("RECV session.approval(phase:pending)（关联 agent 帧 stream:approval/lifecycle 尚未到达，缓冲等待补发）", frame)
        }
    }

    /// `exec.approval.requested` wire 事件（rounds/0016 新增）——**只有握手声明了 `exec-approvals`
    /// cap 之后才会收到**（`canDeliverApprovals`，见 `connect()` 里 caps 那段注释）。
    ///
    /// **为什么必须单独处理它**（异构评审提出、本轮逐行核实）：同一次 exec 审批，内核会发出**两条**
    /// 面向客户端的事件，来源与门禁完全不同——
    ///  1. `session.approval(phase:"pending")`：`gateway/operator-approval-session-events.ts:110`
    ///     广播，收件人 = `sessions.messages.subscribe(includeApprovals:true)` 的订阅者 ∩
    ///     `canAccessOperatorApproval`。**与 caps 无关**，补 cap 之前我们就能收到。
    ///  2. `exec.approval.requested`：事件名定在 `gateway/server-methods/exec-approval.ts:406`，
    ///     广播在 `gateway/server-methods/approval-shared.ts:463-471`，收件人 =
    ///     `getApprovalClientConnIds()` → `canDeliverApprovals()` 筛出的连接。**这条才是被 caps
    ///     门禁的那条**，补 cap 之后才会出现在我们的 socket 上。
    ///
    /// 到达顺序（源码时序，非猜测）：1 在 `manager.register()` 内发出
    /// （`exec-approval-manager.ts:358` `emitLifecycle({phase:"pending"})`），2 在紧随其后的
    /// `handlePendingApprovalRequest()` 内发出，而携带 `{approvalId,toolCallId}` 的那条 `agent` 帧
    /// **最晚**。
    ///
    /// **rounds/0016 订正**：那条 `agent` 帧不止一种形状，取决于 exec 是否内联等待网关审批
    /// （`bash-tools.exec-host-gateway.ts:414-428` `shouldAwaitGatewayApprovalInline()`）——不内联时
    /// 是 `agent(stream:"approval",phase:"requested")`，要等两阶段注册返回 `approval-pending` 才发
    /// （`agents/embedded-agent-subscribe.handlers.tools.ts:1665-1699`）；内联等待时（webchat 等
    /// native approval channel，**我们的 mac 壳就是这条**）是
    /// `agent(stream:"lifecycle",phase:"waiting-approval")`（`bash-tools.exec-host-gateway.ts:1085-1091`），
    /// 在 `resolveApprovalForExecution()` 开始等待前发出。两条都由
    /// `recordAgentApprovalAssociation` 采集（见其文档注释与 rounds/0015 冻结帧证据）。
    ///
    /// 这条事件的 payload 是 `{id, request, createdAtMs, expiresAtMs}`
    /// （`approval-shared.ts:255-264` `buildRequestedApprovalEvent`），其中 `request` 是
    /// `ExecApprovalRequestPayload`（`infra/exec-approvals.ts:225-253`），**直接携带
    /// `sessionKey`/`runId`/`toolCallId`**——正是 M1 双向 join 一直要等 agent 帧才凑齐的两个字段
    /// （它们从 `bash-tools.exec-approval-request.ts:97-98` 原样透传进来）。因此这条事件既让
    /// approval_request 早一跳产出，也让"agent 帧因任何原因缺席"不再等于"这次审批永久丢失"。
    ///
    /// **reqID 一致性**（出站 `respondApproval()` 的关联主键，rounds/0015 已实现的路径靠它）：
    /// `payload.id` 就是 `record.id`（`approval-shared.ts:259`），与 `session.approval` 的
    /// `approval.id`、以及 `approval.resolve` 要的 `id` 是同一个值——三处同源，无需任何换算。
    private func handleExecApprovalRequestedEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let approvalID = jsonString(payload["id"]),
              let request = jsonObject(payload["request"]) else { return }
        guard let runID = jsonString(request["runId"]),
              let toolCallID = jsonString(request["toolCallId"]) else {
            // D2 `ApprovalRequestEventMessage` 的 runID/toolCallID 都是必填——真缺失时诚实跳过，
            // 把这次审批交回原有的 session.approval + agent(stream:approval) 双向 join 路径，
            // 不拿占位符顶替。
            prettyPrint("RECV exec.approval.requested（request.runId/toolCallId 缺失，交回 session.approval 路径）", frame)
            return
        }

        // 常见时序（见上）：`session.approval(pending)` 已经先到并被缓冲在
        // `pendingSessionApprovalByApprovalID`（缺 {runId,toolCallId} 发不出去），此刻我们正好补上
        // 这两个字段——直接用那份**内核自己投影出来的权威 payload** 去 join，比下面合成的那份更可信。
        if let buffered = pendingSessionApprovalByApprovalID.removeValue(forKey: approvalID) {
            approvalIDsBySessionID[buffered.ourSessionID]?.remove(approvalID)
            emitApprovalRequestIfPossible(
                payload: buffered.payload, ourSessionID: buffered.ourSessionID, runID: runID, toolCallID: toolCallID
            )
            return
        }

        guard let kernelKey = jsonString(request["sessionKey"]),
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else { return }
        guard eventContinuations[ourSessionID] != nil else { return }
        guard !approvalAlreadyAdmitted(approvalID, ourSessionID: ourSessionID) else { return }

        // session.approval 还没到（或本连接因为别的原因收不到它）——用这条事件自己的字段合成一份与
        // `session.approval(phase:"pending")` **同构**的 payload，交给同一个 mapper
        // （`mapOpenclawSessionApprovalToKernelEvent`）处理，不另起一套构造逻辑。presentation 的
        // 字段名逐字对齐 `packages/gateway-protocol/src/schema/approvals.ts:90-106`
        // `ExecApprovalPresentationSchema`；**没有的字段一律不写入**（不拿占位符或空串填充），
        // 这样 `summarizeApprovalPresentation` 读到 nil 时 UI 会如实少显示一行，而不是显示假值。
        var presentation: JSONObject = ["kind": "exec"]
        if let commandText = jsonString(request["command"])
            ?? (jsonArray(request["commandArgv"])?.compactMap { jsonString($0) }.joined(separator: " ")).flatMap({ $0.isEmpty ? nil : $0 }) {
            presentation["commandText"] = commandText
        }
        for (dst, src) in [("commandPreview", "commandPreview"), ("warningText", "warningText"),
                           ("host", "host"), ("nodeId", "nodeId"), ("agentId", "agentId")] {
            if let value = jsonString(request[src]) { presentation[dst] = value }
        }
        if let allowed = jsonArray(request["allowedDecisions"]) { presentation["allowedDecisions"] = allowed }

        var approval: JSONObject = ["id": approvalID, "status": "pending", "presentation": presentation]
        if let createdAtMs = jsonInt(payload["createdAtMs"]) { approval["createdAtMs"] = createdAtMs }
        if let expiresAtMs = jsonInt(payload["expiresAtMs"]) { approval["expiresAtMs"] = expiresAtMs }
        var synthesized: JSONObject = ["sessionKey": kernelKey, "phase": "pending", "approval": approval]
        // `session.approval` 的 `updatedAtMs` 是"这条事件自己的产出时刻"，`exec.approval.requested`
        // 没有同名字段，语义上最接近的是这次审批的 `createdAtMs`（两条事件在内核里前后脚发出）。
        if let createdAtMs = jsonInt(payload["createdAtMs"]) { synthesized["updatedAtMs"] = createdAtMs }

        emitApprovalRequestIfPossible(
            payload: synthesized, ourSessionID: ourSessionID, runID: runID, toolCallID: toolCallID
        )
    }

    /// rounds/0016 起的闸门谓词；rounds/0015 返工①把语义从"已交付"扩为"**已被审批 FSM 接纳**"
    /// （已提升为 active / 在缓冲队列里 / 因溢出被直接强制 deny 三者之一）——见
    /// `admittedApprovalIDsBySessionID` 的文档注释。
    private func approvalAlreadyAdmitted(_ approvalID: String, ourSessionID: String) -> Bool {
        admittedApprovalIDsBySessionID[ourSessionID]?.contains(approvalID) == true
    }

    /// 用已经确定的 `{runID,toolCallID}`（无论是 agent 帧先到、session.approval 先到、
    /// approvalReplay 重放，还是 rounds/0016 新增的 `exec.approval.requested`）**把一条审批请求交给
    /// 本 session 的审批 FSM**——四条来源路径共享这一个准入口，不重新发明一遍判断，也因此只需要在
    /// 这一处设"同一 approvalId 只接纳一次"的闸门。
    ///
    /// **rounds/0015 返工①（D1 §6.2）：本函数从"构造并 yield"改成"准入判定"。** 三条出路，逐条对应
    /// D1 §6.2「pending #2 缓冲策略」的三个 bullet：
    ///  1. 当前 session **没有** active pending -> 立即提升为 active 并 yield（`presentApprovalRequest`）。
    ///  2. 已有 active pending 且缓冲队列未满 -> **入队，一个字节都不 yield**（D1："不立即以任何形式
    ///     呈现给调用方，不触发新的可见 pending 状态"）。
    ///  3. 已有 active pending 且缓冲队列**已满** -> 不入队，产出
    ///     `ApprovalBufferResolvedEvent(queue_overflow)` 并对它发起强制 deny（D1 fail-closed 取向）。
    ///
    /// 函数名保留 `emitApprovalRequestIfPossible` 不改：四个调用点（`handleSessionApprovalEvent`/
    /// `recordAgentApprovalAssociation`/`handleExecApprovalRequestedEvent`/`consumeApprovalReplay`）
    /// 对它的期待——"信息凑齐了，把这条审批交出去"——在语义上没有变，变的只是"交出去之后 FSM 怎么
    /// 处置"；改名会让四处调用点的 diff 混进本轮真正的行为改动里，反而更难审。
    private func emitApprovalRequestIfPossible(payload: JSONObject, ourSessionID: String, runID: String, toolCallID: String) {
        guard eventContinuations[ourSessionID] != nil else { return }
        let sid = ourSessionID
        guard let approvalID = jsonString(jsonObject(payload["approval"])?["id"]) else { return }
        guard !approvalAlreadyAdmitted(approvalID, ourSessionID: sid) else {
            // 另一条来源事件已经把这次审批交给 FSM 了——如实丢弃。重复接纳的后果不只是"发两条同
            // reqID 的事件"，在缓冲态下还会在队列里塞两份同 reqId 的条目。
            return
        }

        // ---- D1 §6.2 单 active 约束（**破坏性反证 A 的拆除点**：把这个 guard 改成恒真，
        //      testApprovalFSMSerializesToSingleActivePendingAndOverflowsBeyondDepth 必然变红）----
        guard activeApprovalReqIDBySessionID[sid] != nil else {
            _ = presentApprovalRequest(payload: payload, ourSessionID: sid, runID: runID, toolCallID: toolCallID)
            return
        }

        var queue = bufferedApprovalsBySessionID[sid] ?? []
        guard queue.count < approvalBufferDepth else {
            // ---- 溢出：不进队列，直接 fail-closed deny ----
            admittedApprovalIDsBySessionID[sid, default: []].insert(approvalID)
            let presentation = jsonObject(jsonObject(payload["approval"])?["presentation"]) ?? [:]
            let openclawKind = jsonString(presentation["kind"]) ?? "exec"
            let allowedDecisions = (jsonArray(presentation["allowedDecisions"]) ?? []).compactMap { jsonString($0) }
            // **rounds/0016（T-096 第 1 项）：这里不再产出 `approval_buffer_resolved(queue_overflow)`。**
            // 修前是"先 emit 可见性事件、再派发 deny RPC"，理由写的是"溢出是适配器自己的决定，与
            // 内核是否接受这条 deny 是两件事"。那个论证站不住：这条事件在壳里被渲染成**"已被自动
            // 拒绝"**，而 deny 没打成时这条审批在内核侧仍然 pending、随时可能被别的审批客户端放行
            // ——先发就是"提前宣称已自动拒绝"，正是 T-096 点名要禁的。事件改由
            // `performQueueOverflowDeny` 在成功判据（`applied:true + status:denied`）成立时产出；
            // 三种失败形态各自走 `evt.error` + `FORCE_DENY_PENDING_KERNEL_ACK`，一条都不吞。
            beginQueueOverflowDeny(
                reqID: approvalID, openclawKind: openclawKind, sessionID: sid,
                runID: runID, allowedDecisions: allowedDecisions
            )
            prettyPrint("APPROVAL FSM 缓冲溢出（深度 \(approvalBufferDepth) 已满，直接强制 deny，等内核确认后才宣称已拒绝）", [
                "sessionId": sid, "reqId": approvalID,
                "activeReqId": activeApprovalReqIDBySessionID[sid] ?? "nil",
            ])
            return
        }

        // ---- 入队：不 yield 任何事件 ----
        queue.append(BufferedApprovalRequest(reqID: approvalID, payload: payload, runID: runID, toolCallID: toolCallID))
        bufferedApprovalsBySessionID[sid] = queue
        admittedApprovalIDsBySessionID[sid, default: []].insert(approvalID)
        prettyPrint("APPROVAL FSM 缓冲（已有 active pending，本条不呈现给调用方）", [
            "sessionId": sid, "reqId": approvalID,
            "activeReqId": activeApprovalReqIDBySessionID[sid] ?? "nil",
            "bufferedCount": queue.count, "bufferDepth": approvalBufferDepth,
        ])
    }

    /// 真正把一条审批**提升为 active pending 并 yield 给调用方**——原 `emitApprovalRequestIfPossible`
    /// 的构造+登记+yield 三段身体原样搬到这里，一行判定逻辑都没改（改的只是"什么时候轮到它跑"）。
    /// 返回是否成功提升：映射失败（`mapOpenclawSessionApprovalToKernelEvent` 返回 nil，例如
    /// runId/toolCallId 缺失）时返回 false，调用方（提升循环）据此跳过这一条继续找下一条。
    @discardableResult
    private func presentApprovalRequest(
        payload: JSONObject, ourSessionID: String, runID: String, toolCallID: String
    ) -> Bool {
        guard let continuation = eventContinuations[ourSessionID] else { return false }
        let sid = ourSessionID
        guard let event = mapOpenclawSessionApprovalToKernelEvent(
            payload, ourSessionID: ourSessionID, runIDHint: runID, toolCallIDForApprovalID: toolCallID,
            nextSeq: { self.nextSeq(runID: runID, sessionID: sid) }
        ) else { return false }

        // M3（D1 §6.2 stop-path 强制 deny）：approvalRequest 真正产出的这一刻，这个 reqId 进入
        // "pending，等待决策"态。**rounds/0015 起这个态有两个消费者**：`respondApproval()`（人工
        // 决策）与 `stop()` 的强制 deny。openclawKind 取这条 session.approval payload 自己的
        // `approval.presentation.kind`（真实值，不是 D2 收窄后的 KindElement），缺失时兜底 "exec"
        // （openclaw 现场样本里唯一验证过的取值，见 EventMapping.swift
        // `mapOpenclawSessionApprovalToKernelEvent` 文档注释）。
        if case .approvalRequest(let approvalRequestMessage) = event {
            let reqID = approvalRequestMessage.payload.reqID
            let approvalObj = jsonObject(payload["approval"]) ?? [:]
            let presentation = jsonObject(approvalObj["presentation"]) ?? [:]
            let openclawKind = jsonString(presentation["kind"]) ?? "exec"
            // rounds/0015 B：连同这条请求自己的 allowedDecisions 一起缓存——`respondApproval()`
            // 的发出前校验只认这一份，不认任何固定集合（见 PendingApprovalAwaitingDecision
            // 的文档注释）。字段缺失时留空数组：那样任何 allow 决策都会被客户端拦下并报错，
            // 而不是"没读到就当全都允许"乐观放行——后者恰好会撞进服务端的 forceMalformedDeny。
            let allowedDecisions = (jsonArray(presentation["allowedDecisions"]) ?? []).compactMap { jsonString($0) }
            pendingApprovalsByReqID[reqID] = PendingApprovalAwaitingDecision(
                runID: runID, openclawKind: openclawKind, sessionID: sid, allowedDecisions: allowedDecisions
            )
            pendingApprovalReqIDsBySessionID[sid, default: []].insert(reqID)
            // rounds/0015 返工①：这一刻它成为该 session 唯一的 active pending（D1 §6.2）。
            activeApprovalReqIDBySessionID[sid] = reqID
            // rounds/0016：关上这个 reqID 的闸门。刻意**不**跟 `pendingApprovalsByReqID` 共用
            // 一张表——那张表在 respondApproval()/强制 deny 落地后会摘掉条目，之后再来一条同
            // reqId 的迟到帧就会被当成新审批重新产出。
            admittedApprovalIDsBySessionID[sid, default: []].insert(reqID)
        }
        continuation.yield(event)
        wireTraceCollector?.append(event)
        return true
    }

    /// D1 §6.2「#1 解决后 #2 浮现」：active pending 达到**任一**合法终态后调用——清掉 active 槽位，
    /// 从缓冲队列头部开始找下一条仍未终态化的请求提升为新的 active pending。
    ///
    /// D1 原文还有一句"若队列头部的请求已按上一条规则提前终态化，适配器跳过它，继续检查队列中下一
    /// 条"——本实现里"缓冲期内被内核判定终态"的条目在收到内核信号的那一刻就**已经**从队列里移除了
    /// （见 `handleApprovalTerminalSignal`），所以队头恒为未终态条目；下面这个 `while` 循环因此在
    /// 正常路径上恰好迭代一次。保留循环形态是为了覆盖另一种跳过理由：`presentApprovalRequest` 映射
    /// 失败（缓冲时无法预先验证映射是否会成功——预验证要消耗一个 `nextSeq`，那会让交付序号出现空洞）。
    ///
    /// `reasonHint` 只进日志，不影响任何判定。
    private func promoteNextBufferedApprovalIfPossible(sessionID: String, reasonHint: String) {
        activeApprovalReqIDBySessionID.removeValue(forKey: sessionID)
        while var queue = bufferedApprovalsBySessionID[sessionID], !queue.isEmpty {
            let next = queue.removeFirst()
            bufferedApprovalsBySessionID[sessionID] = queue
            if presentApprovalRequest(
                payload: next.payload, ourSessionID: sessionID, runID: next.runID, toolCallID: next.toolCallID
            ) {
                prettyPrint("APPROVAL FSM 提升缓冲队列头部为新的 active pending（\(reasonHint)）", [
                    "sessionId": sessionID, "promotedReqId": next.reqID, "remainingBuffered": queue.count,
                ])
                return
            }
            prettyPrint("APPROVAL FSM 缓冲条目无法映射成 approval_request，跳过继续找下一条", [
                "sessionId": sessionID, "skippedReqId": next.reqID,
            ])
        }
    }

    /// 产出 D1 §6.2 v3.3 新增的第 11 类 KernelEvent `ApprovalBufferResolvedEvent`——**这是本轮之前
    /// 从未被任何代码路径调用过的构造函数**（`EventMapping.swift` 该函数的文档注释原文："本轮仍未
    /// 接入任何真实触发路径"，本轮连同那段陈旧注释一并订正）。`runID` 传 nil：缓冲期内终态化的请求
    /// 从未被呈现，调用方那边没有任何以 runId 为锚的上下文可挂靠，D2 该字段本就允许缺失。
    private func emitApprovalBufferResolved(sessionID: String, reqID: String, reason: FluffyReason) {
        guard let continuation = eventContinuations[sessionID] else { return }
        let event = buildApprovalBufferResolvedEvent(
            reqID: reqID, reason: reason, ourSessionID: sessionID,
            seq: nextSeq(runID: nil, sessionID: sessionID)
        )
        continuation.yield(event)
        wireTraceCollector?.append(event)
    }

    /// M1：消费 `sessions.messages.subscribe` 响应里的 `approvalReplay.approvals`——这是这次
    /// subscribe 建立**之前**就已经处于 pending 状态的审批快照（真实场景：respondApproval 还没
    /// 落地、client 断线重连，或首次 subscribe 时错过了原始 `session.approval(pending)` 广播，只能
    /// 靠这份权威快照补齐——见 openclaw 源码
    /// `gateway/server-methods/sessions-subscriptions.ts:91-121`：`includeApprovals:true` 时
    /// subscribe 的响应本身就带上 `approvalReplay:{sessionKey,updatedAtMs,approvals,truncated}`，
    /// 每个 `approvals[]` 条目与 `session.approval(phase:"pending")` 的 `approval` 字段同构，见
    /// `packages/gateway-protocol/src/schema/approvals.ts` 的 `PendingApprovalSnapshotSchema`）。
    /// 上一轮完全没有读这个字段，这些审批永远不会出现在 D2 事件流里。逐条构造等价的
    /// `session.approval(phase:"pending")` frame，直接调用 `handleSessionApprovalEvent`——走跟真实
    /// wire 事件完全相同的双向 join 逻辑（大多数情况下这里还没有 agent(stream:approval) 帧，会被
    /// 正常缓冲，等随后真实到达的 agent 帧补发）。
    private func consumeApprovalReplay(_ result: JSONObject, kernelKey: String) {
        guard let replay = result["approvalReplay"] as? JSONObject,
              let approvals = replay["approvals"] as? [Any] else {
            return
        }
        let updatedAtMs = replay["updatedAtMs"]
        for case let approval as JSONObject in approvals {
            let syntheticPayload: JSONObject = [
                "sessionKey": kernelKey,
                "updatedAtMs": updatedAtMs as Any,
                "phase": "pending",
                "approval": approval,
            ]
            handleSessionApprovalEvent(["type": "event", "event": "session.approval", "payload": syntheticPayload])
        }
    }

    /// gateway 全局 `shutdown` 事件——对所有当前活跃、尚未产出过 terminal 的 session 各广播一条
    /// sessionEnd(reason:.kernelExited)。F8：与 stop()/transportClosed 两条路径共享
    /// `sessionTerminalEmitted` 去重标记。
    private func handleShutdownEvent(_ frame: JSONObject) {
        prettyPrint("RECV event shutdown（向所有活跃 session 广播 sessionEnd(reason:kernelExited)）", frame)
        for (ourSessionID, continuation) in eventContinuations {
            guard !sessionTerminalEmitted.contains(ourSessionID) else { continue }
            sessionTerminalEmitted.insert(ourSessionID)
            let event = makeSessionEndEventForShutdown(
                ourSessionID: ourSessionID,
                nextSeq: { self.nextSeq(runID: nil, sessionID: ourSessionID) }
            )
            continuation.yield(event)
            wireTraceCollector?.append(event)
        }
    }

    // MARK: - Test-only 支持面（frame-replay 单测用；生产路径不调用）
    //
    // SG-10 起这个项目有了 SwiftPM 包（app/Package.swift），但仍不用 XCTest——延续既有风格。
    // `FrameReplayTests.swift` 现在住在独立的 frame-replay-tests executable target 里，跟这个文件
    // 不再是同一次编译的隐式单一 module；换成 target 级 `-enable-testing` +
    // `@testable import KernelClient`（见 app/Package.swift 里 KernelClient target 的
    // swiftSettings 注释）拿到跨 target 的 internal 访问权限，效果和裸 swiftc 时代"同一次编译"
    // 等价——下面这几个方法因此**不需要**改成 public，原来的 `private` 去掉留到 internal 就够，
    // 一个访问级别都没多动。方法名统一加 `testSupport` 前缀，一眼可辨认，不是生产调用路径的一部分。

    /// 不经过任何 RPC，直接注册一个"已订阅"的假 session——供测试灌入合成 wire 帧。
    func testSupportRegisterSession(ourSessionID: String, kernelKey: String) -> AsyncThrowingStream<EventMessageUnion, Error> {
        kernelKeyBySessionID[ourSessionID] = kernelKey
        let (stream, continuation) = AsyncThrowingStream<EventMessageUnion, Error>.makeStream()
        eventContinuations[ourSessionID] = continuation
        return stream
    }

    /// 把一帧合成的 wire JSON 编码后送进真实的 `handleIncoming` dispatch 入口——测试因此走的是
    /// 生产代码本身的分支/映射逻辑，不是重新实现一遍判断。
    func testSupportFeedFrame(_ frame: JSONObject) {
        guard let data = try? encodeFrame(frame) else { return }
        handleIncoming(data)
    }

    /// 读取当前锁状态的字符串描述（"idle"/"send_pending"/"stop_in_progress"）。
    func testSupportLockState(sessionID: String) -> String {
        (lockStateBySessionID[sessionID] ?? .idle).description
    }

    /// 读取某个 pendingStop 是否已经被标记为"terminal 已产出"（F6 去重的核心状态）。
    func testSupportPendingStopTerminalEmitted(sessionID: String) -> Bool? {
        pendingStops[sessionID]?.terminalEmitted
    }

    /// M3：读取某个 session 当前是否还残留一个 pendingStop 条目——用于验证 stop() 的各条退出路径
    /// （成功/超时/抛错）收尾之后确实清干净了，没有泄漏。
    func testSupportHasPendingStop(sessionID: String) -> Bool {
        pendingStops[sessionID] != nil
    }

    /// 读取某个 session 是否已经产出过 terminal sessionEnd（F8 去重的核心状态）。
    func testSupportSessionTerminalEmitted(sessionID: String) -> Bool {
        sessionTerminalEmitted.contains(sessionID)
    }

    /// rounds/0015 返工①（D1 §6.2 FSM）：读取该 session 当前唯一的 active pending reqId
    /// （没有则 nil）——"同一时刻只暴露一个"这条约束的直接观测点。
    func testSupportActiveApprovalReqID(sessionID: String) -> String? {
        activeApprovalReqIDBySessionID[sessionID]
    }

    /// rounds/0015 返工①：读取该 session FIFO 缓冲队列里的 reqId（按队列顺序，队头在前）。
    func testSupportBufferedApprovalReqIDs(sessionID: String) -> [String] {
        (bufferedApprovalsBySessionID[sessionID] ?? []).map(\.reqID)
    }

    /// rounds/0015 返工①：把 FIFO 缓冲深度覆盖成一个更小的值，用 3~4 条帧驱动完整的
    /// 「active / 缓冲 / 溢出 / 提升」四条路径，不用真喂 `approvalBufferDefaultDepth + 2` 条。
    func testSupportSetApprovalBufferDepth(_ depth: Int) {
        testSupportApprovalBufferDepthOverride = depth
    }

    /// rounds/0015 返工②：读取该 session 当前在途 `approval.resolve` 的 reqId——用于验证
    /// stop() 的 drain 收敛条件确实等到了在途决议落地。
    func testSupportInFlightApprovalResolveReqIDs(sessionID: String) -> [String] {
        approvalResolveInFlightReqIDs(sessionID: sessionID)
    }

    // MARK: rounds/0016（T-096 第 2、3 项）的 test-only 观测/注入面

    /// 这个 reqId 当前是否处于 `FORCE_DENY_PENDING_KERNEL_ACK`；处于时一并返回实际观察到的失败
    /// 形态与重试计数（反证② 要"打印实际被破坏的内容"，光有一个 Bool 印不出东西）。
    func testSupportForceDenyPendingKernelAck(reqID: String) -> (observedFailure: String, retryCount: Int, origin: String)? {
        guard let record = forceDenyPendingKernelAckByReqID[reqID] else { return nil }
        return (record.observedFailure, record.retryCount, record.origin.rawValue)
    }

    func testSupportForceDenyPendingKernelAckReqIDs(sessionID: String) -> [String] {
        Array(forceDenyPendingKernelAckReqIDsBySessionID[sessionID] ?? []).sorted()
    }

    /// 把 `approval.resolve` 的有界等待压到一个测试尺度的值（生产默认 30_000ms）。只影响本 actor
    /// 实例，同 `testSupportSetStopTimeoutSeconds` 的既有形态。
    func testSupportSetApprovalResolveBoundedWaitMS(_ milliseconds: Int) {
        testSupportApprovalResolveBoundedWaitMSOverride = milliseconds
    }

    /// M1/M5：读取某个 approvalId 当前是否还残留在任一方向的双向 join 缓冲区里——用于验证
    /// pending-first/agent-first 两个方向在 join 成功后确实清掉了自己的缓存条目，以及 session
    /// 结束时孤儿条目（从未配对成功的）确实被批量清理。
    func testSupportHasBufferedApproval(approvalID: String) -> Bool {
        agentApprovalInfoByApprovalID[approvalID] != nil || pendingSessionApprovalByApprovalID[approvalID] != nil
    }

    /// M3（D1 §6.2 stop-path 强制 deny 新增）：读取某个 reqId 当前是否仍处于"approval_request 已经
    /// 产出、respondApproval() 尚未落地"的 pending 态——用于验证 stop() 的强制 deny 序列确实把这个
    /// reqId 从 pending 转成了终态（`forceDenyPendingApprovalsBeforeStop` 成功后会把它从这张表移除）。
    func testSupportHasPendingApprovalAwaitingDecision(reqID: String) -> Bool {
        pendingApprovalsByReqID[reqID] != nil
    }

    /// M3/M6：按 RPC method 名注册一个"被调用时应该返回什么/抛什么错"的闭包——供测试真实驱动
    /// `send()`/`stop()` 方法体本身（含它们发起的 `sessions.send`/`sessions.abort`/
    /// `sessions.delete` RPC），不需要一个真实的 WebSocket 连接。见 `request()` 的调用点。
    func testSupportStubRPC(method: String, responder: @escaping @Sendable (JSONObject) async throws -> JSONObject) {
        testSupportRPCResponders[method] = responder
    }

    /// M3：缩短 stop() 等待 aborted-run 终态的超时（生产默认 5 秒），供"超时"路径的测试使用，不用
    /// 真的等 5 秒。
    func testSupportSetStopTimeoutSeconds(_ seconds: Int) {
        testSupportStopTimeoutSecondsOverride = seconds
    }

    /// rounds/0020：同上，缩短的是 interrupt() 自己的等待超时（见
    /// `testSupportInterruptTimeoutSecondsOverride` 文档注释，为什么这是一个独立于 stop() 的变量）。
    func testSupportSetInterruptTimeoutSeconds(_ seconds: Int) {
        testSupportInterruptTimeoutSecondsOverride = seconds
    }

    /// NOTE-A：缩短 force-deny drain 循环的迭代轮次上限（生产默认 50），供"超过上限如实 throw、不
    /// 静默死循环"这条路径的测试使用，不用真的喂 50 轮 late-arrival 才能触发。
    func testSupportSetForceDenyDrainMaxRounds(_ rounds: Int) {
        testSupportForceDenyDrainMaxRoundsOverride = rounds
    }

    /// M6：直接触发 `handleTransportClosed`（真实 WS 断开时 `receiveLoop` 走的同一条路径）——供
    /// 测试验证"shutdown 之后真实 transport close"不会产出第二条矛盾的 sessionEnd，而不是像上一轮
    /// 那样用两次同样的 shutdown 帧代替 transport close。
    func testSupportSimulateTransportClosed() {
        handleTransportClosed(error: KernelClientError.transport("test-simulated transport closed"))
    }

    /// rounds/0012 ②：人为延迟 subscribe() 标记"订阅 RPC 已 dispatch"的时刻——供确定性构造 send/
    /// stop 侧屏障的破坏性反证（不加延迟的话，"背景 Task 是否先于 send()/stop() 跑到 dispatch 点"
    /// 取决于 Swift actor 调度巧合，不可靠地复现）。见 `subscribe()`/`send()` 文档注释与
    /// FrameReplayTests.swift 对应测试。
    func testSupportSetSubscribeDispatchDelay(nanoseconds: UInt64) {
        testSupportSubscribeDispatchDelayNanoseconds = nanoseconds
    }
}

// MARK: - rounds/0014 会话持久化：SessionRestoring/SessionHistoryProviding 协议落地
//
// 两个协议声明在 KernelClient.swift（与 D1 `KernelClient` 协议相邻但完全独立——不是 D1 七法的
// 一部分，签名可以自由演进，详见该处文档注释）。这个 extension 必须和上面的
// `actor OpenclawGatewayKernelClient` 主体同处一个文件才能直接访问它的 `private` 状态
// （`kernelKeyBySessionID`）与 `private` 方法（`request(method:params:)`）——Swift 的 `private`
// 访问级别以**文件**为界，不是以单个花括号块/extension 为界（SE-0169），因此不需要、也没有放宽任何
// 一个既有符号的访问级别去换取这里的可达性。
extension OpenclawGatewayKernelClient: SessionRestoring, SessionHistoryProviding {
    /// 见 `SessionRestoring` 协议文档注释。播种 `kernelKeyBySessionID`——唯一让 `send()`/`stop()`
    /// 认得这个 sessionID 的映射——然后把一个 `session.sessionID` 正确、其余字段均为占位值的
    /// `SessionHandle` 交给**未经任何改动**的 `subscribe(session:)`，完整复用它内部的订阅 dispatch
    /// 屏障（`beginTrackingSubscriptionDispatch`/`markSubscriptionRpcDispatched`，rounds/0012 两轮
    /// 返工才收敛的行为，见该方法文档注释），不重新实现、不绕过、不精简。`subscribe()` 函数体自
    /// `let ourSessionID = session.sessionID` 这一行开始只读这一个字段——billing/createdAt/
    /// kernelSessionID 全程未被读取（逐行核对过该方法体，见其文档注释与实现）——因此用占位值构造
    /// 这里的 `SessionHandle` 是安全的，不是"凑合过关"。
    ///
    /// 不重新执行 D1 §2.1 的 `sessions.create` RPC：那会在内核侧铸造一个全新会话，而不是让磁盘上
    /// 已经记录、内核里本就存在的那个会话重新变得可寻址——两者是完全不同的操作。
    public func restoreSession(sessionID: String, kernelKey: String) async -> AsyncThrowingStream<EventMessageUnion, Error> {
        kernelKeyBySessionID[sessionID] = kernelKey
        let placeholderHandle = SessionHandle(
            billing: Billing(tokenRef: "restored-session-no-newapi-token-context"),
            createdAt: Date(), kernel: .openclaw, kernelSessionID: kernelKey, sessionID: sessionID
        )
        return await subscribe(session: placeholderHandle)
    }

    /// 见 `SessionRestoring` 协议文档注释——纯读，不修改任何状态。通过既有的 internal
    /// `kernelKey(for:)` 访问器反查（零重复实现），供 A 块（`SessionStore` 侧的会话清单持久化）在
    /// `createSession()` 成功后取得这个字段写入磁盘，不需要新增 D1 返回值、不需要改 `SessionHandle`
    /// 的字段集。
    public func currentKernelKey(sessionID: String) async -> String? {
        kernelKey(for: sessionID)
    }

    /// 见 `SessionHistoryProviding` 协议文档注释。循环调用 openclaw `chat.history` RPC
    /// （`kernels/openclaw/src/gateway/server-methods/chat-history-handler.ts:614-627` 的
    /// `chatHistoryHandlers["chat.history"]` -> `handleChatHistoryRequest`——**只读源码验证过，未做
    /// live 验证**，理由与残余风险见 `SessionStore.swift` 选择这条通路的文档注释），直到响应体
    /// `hasMore` 不再是 `true` 为止。
    ///
    /// **翻页字段是 `offset`/`nextOffset`，不是 `nextCursor`**——这是这条 RPC 与本仓 HTTP
    /// `GET /sessions/<key>/history`（`kernels/openclaw/src/gateway/session-history-state.ts`
    /// 的 `buildPaginatedSessionHistory`，字段是 `hasMore`/`nextCursor`；
    /// `app/apps/AgentShell/repro/reconcile-history.py` 对账的正是这一条 HTTP 端点）之间真实存在的
    /// 差异——两条通路在 openclaw 源码里是**两套独立的分页实现**（`chat-history-pages.ts` 的
    /// `readChatHistoryPage`/`resolveChatHistoryNextOffset` 用 `offset` 数值游标；
    /// `session-history-state.ts` 的 `paginateSessionMessages` 用不透明的 `seq:` 前缀字符串
    /// cursor），字段名不能跨两条通路混用、也不能直接照抄 reconcile-history.py 的字段名。这里的循环
    /// 结构——翻页直到 `hasMore` 非真；游标不推进（重复 `nextOffset`）则拒绝继续、如实抛错，不静默
    /// 死循环；迭代次数设硬上限防止服务端分页缺陷造成无限循环——在**精神上**照抄
    /// reconcile-history.py 的 `resolve_online_history`/`MAX_HISTORY_PAGES`（任务书要求参考的翻页
    /// 逻辑），但字段名按这条 RPC 的真实契约改写。
    public func fetchFullHistory(kernelKey: String, pageLimit: Int) async throws -> [HistoryRecord] {
        var collected: [HistoryRecord] = []
        var offset: Int?
        var seenOffsets = Set<Int>()
        var pageCount = 0

        while true {
            pageCount += 1
            guard pageCount <= Self.maxHistoryFetchPages else {
                throw KernelClientError.protocolMismatch(
                    "fetchFullHistory: exceeded \(Self.maxHistoryFetchPages) page(s) for kernelKey " +
                    "\(kernelKey) without hasMore:false — refusing to page forever " +
                    "(mirrors reconcile-history.py's MAX_HISTORY_PAGES guard)"
                )
            }

            var params: JSONObject = ["sessionKey": kernelKey, "limit": pageLimit]
            if let offset { params["offset"] = offset }
            let result = try await request(method: "chat.history", params: params)
            prettyPrint("RECV chat.history result (page \(pageCount))", result)

            guard let rawMessages = result["messages"] as? [Any] else {
                throw KernelClientError.protocolMismatch("chat.history result missing 'messages' array (page \(pageCount))")
            }
            collected.append(contentsOf: rawMessages.compactMap(parseHistoryRecord))

            guard jsonBool(result["hasMore"]) == true else { break }
            guard let nextOffset = jsonInt(result["nextOffset"]) else {
                throw KernelClientError.protocolMismatch(
                    "chat.history result has hasMore:true but is missing an integer 'nextOffset' " +
                    "(page \(pageCount)) — refusing to guess a cursor, that would risk silently " +
                    "truncating history"
                )
            }
            guard !seenOffsets.contains(nextOffset) else {
                throw KernelClientError.protocolMismatch(
                    "chat.history pagination returned a repeated nextOffset=\(nextOffset) " +
                    "(page \(pageCount)) — cursor is not advancing, refusing to loop forever"
                )
            }
            seenOffsets.insert(nextOffset)
            offset = nextOffset
        }

        // 多页翻页得到的顺序是"从新到旧"（每一页的 offset 往更早的消息移动，见上面协议文档注释），
        // 必须重新按 seq 升序排才是聊天界面期望的"从旧到新"阅读顺序。seq 缺失的记录（不应该发生——
        // openclaw `__openclaw.seq` 理应总是存在，但解析层已经诚实允许缺失，见
        // EventMapping.swift `parseHistoryRecord`）在比较时视为与任何一侧都不构成"更早"关系，
        // Swift 5 保证 `sorted(by:)` 稳定，因此这类记录只是保留其原始相对顺序，不会被强行拖到
        // 结果的开头或结尾。
        return collected.sorted { lhs, rhs in
            guard let l = lhs.seq, let r = rhs.seq else { return false }
            return l < r
        }
    }

    /// `fetchFullHistory` 翻页安全上限——与 reconcile-history.py 的 `MAX_HISTORY_PAGES`（10000）
    /// 同一个防御性用途：服务端分页缺陷（游标不推进/`hasMore` 卡 `true`）不应该让客户端无限循环。
    private static let maxHistoryFetchPages = 10000
}
