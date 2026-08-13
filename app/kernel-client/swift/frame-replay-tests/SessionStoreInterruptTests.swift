// rounds/0020 —— app 层「停止生成」按钮的落点：`SessionStore.interruptCurrentRun(in:)`
// （D1 §2.4 interrupt 的 UI 入口，本轮只发起 `mode:"cancel"`）+ `SessionStore.handleOperationCompleted`
// 对 evt.operation_completed(operationKind:.interrupt) 的新增处理（任务书第 4 条：`abortedRunId==nil`
// /超时两条路径从不产出 evt.turn_complete，只靠 `.turnComplete` 分支清 `isWaitingForReply` 会让 UI
// 永久卡在"等待回复…"）。
//
// 覆盖面（对应任务书 1-4 条）：
//   ①（第 4 条核心）operation_completed(operationKind:.interrupt) 按 outcome 分流清/不清
//     isWaitingForReply——`PayloadOutcome` 里 interrupt 实际可达的三个取值：abortedRunId==nil 路径的
//     `.succeeded`（清——内核确认没有活跃 run）、等待超时的 `.timedOut`（**T-113 rework 倒转：不
//     清**——sessions.abort 已被接受但没等到收尾帧确认，属于"不确认"而非"确认停止"）、
//     sessions.abort/force-deny 抛错的 `.rejected`（**T-113 rework 倒转：不清**——对内核状态零确认，
//     且与 `interruptCurrentRun` 自己的文档注释 :391-394 直接对齐）各一条，外加一条"不误伤 .stop"的
//     scoping 回归锁。`.timedOut`/`.rejected` 两条测试修前断言的是相反的行为（当时的实现对
//     operationKind==.interrupt 无条件清除，不看 outcome）——那正是 T-113 grok 对抗评审 item 2
//     揪出的缺陷：与 `interruptCurrentRun` 自己的文档论证矛盾，会让"中止失败"的 UI 撒谎说"已经不在
//     等了"。见各测试函数自己的文档注释，倒转的历史与理由都留在原地，不假装从一开始就是这样写的。
//   ②（第 1 条）interruptCurrentRun(in:) 的 guard 语义：未知 sessionID 不误伤其它会话、
//     `isInterrupting` 已经为 true 时不重复派发 RPC（第 3 条"中止在途窗口"的模型层半道防线）。
//   ③（第 1 条）interruptCurrentRun(in:) 如实转发真实 throw（未知 kernelKey -> protocolMismatch）
//     为系统消息，不吞掉；`isInterrupting` 在 defer 里正确复位。
//   ④ interruptCurrentRun(in:) 端到端成功路径——真打一次 `client.interrupt(mode:.cancel)`（用
//     `mode:.steer` 会被拒绝这件事反证真的传了 `.cancel`），产出的真实事件经 `handle()` 处理后
//     `isWaitingForReply` 被正确清掉。
//
// **明确记录的证据缺口（协调者要求如实记录，不要看起来像已覆盖）**：`SessionDetailView.
// composerActionButton` 那个决定"此刻显示发送/停止/停止中"的 `if isWaitingForReply ||
// isInterrupting` 条件本身——本文件、以及这个项目里任何一份测试——都没有一行代码真正执行过它。
// 不只是"没写"，是这个 target 结构性够不到：`frame-replay-tests` 依赖 `["KernelClient",
// "D2Generated", "AgentShellCore"]`（app/Package.swift），不依赖 `AgentShell`；`AgentShell` 是
// `executableTarget`，SwiftPM 不允许可执行 target 互相 import；这个项目也没有 ViewInspector/
// SnapshotTesting/XCUITest 之类的 SwiftUI 视图测试设施（全仓搜索为空）。所以把这个条件从
// `isWaitingForReply || isInterrupting` 改回 `isWaitingForReply` 单独一个，**不会有任何一条自动化
// 测试变红**——本文件对它的"覆盖"完全是间接的：驱动它读取的两个状态位
// （`isWaitingForReply`/`isInterrupting`）在 `SessionStore`/`ChatSessionViewModel` 层的行为，加上
// 代码内联的设计推理注释（该属性文档注释）。这是一处真实、未消除的验证空白，只能靠人读代码/实拍
// 截图核对，不是这份测试文件在假装覆盖它。
//
// `@testable import AgentShellCore` 同 SessionStoreToolRenderingTests.swift；额外 `@testable import
// KernelClient`——`store.client`（本轮从 `private` 放宽到 `private(set) var`，见 SessionStore.swift
// 该属性文档注释）暴露出的是具体类型 `OpenclawGatewayKernelClient`，要调它的 `testSupportRegisterSession`/
// `testSupportStubRPC` 等方法需要这个 target 对 `KernelClient` 模块也有 `@testable` 权限——
// `frame-replay-tests` 对两个模块都开了 `-enable-testing`（app/Package.swift），同一个文件可以
// 同时做两个 `@testable import`，`InterruptTests.swift` 已经是这么做的先例。

import Foundation
@testable import AgentShellCore
@testable import KernelClient
import D2Generated

// MARK: - 小工具

/// 构造 (store, session) 一对——`session` 尚未注册进 `store.sessions`（是否注册、是否同时给
/// `store.client` 播种 kernelKey，由各测试按需自己决定），只提供最小公共构造步骤。复用
/// FrameReplayTests.swift 的 `testHandle`（非 private，同 target 可见，`InterruptTests.swift` 已经
/// 是这么复用的先例）。
@MainActor
private func freshInterruptUISession(id: String, kernelKey: String) -> (SessionStore, ChatSessionViewModel) {
    let store = SessionStore(config: KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!,
        token: "dummy-test-token",
        configWarning: nil
    ))
    let session = ChatSessionViewModel(handle: testHandle(sessionID: id, kernelKey: kernelKey), title: "interrupt UI test session")
    return (store, session)
}

/// 构造一条 `evt.operation_completed`——字段形状照抄 SessionStoreToolRenderingTests.swift 的同名私有
/// helper（那个是 private，跨文件不可复用，这里独立一份）。
private func interruptUIOperationCompletedEvent(
    operationID: String, operationKind: OperationKind, outcome: PayloadOutcome,
    affectedRunID: String?, sessionID: String
) -> EventMessageUnion {
    .operationCompleted(OperationCompletedEventMessage(
        direction: .event,
        payload: OperationCompletedEventMessagePayload(
            affectedRunID: affectedRunID, detail: nil, newRunID: nil,
            operationID: operationID, operationKind: operationKind, outcome: outcome
        ),
        runID: affectedRunID, sentAt: Date(), seq: 1, sessionID: sessionID, ts: Date(), type: .evtOperationCompleted
    ))
}

// MARK: - ①核心（任务书第 4 条）：operation_completed(operationKind:.interrupt) 兜底清 isWaitingForReply

/// **这是任务书第 4 条明确要求的那条测试**："abortedRunId==nil path" —— `OpenclawGatewayKernelClient
/// .interrupt()` 对应分支只调用 `emitOperationCompletedMirror`，从不产出 evt.turn_complete（源码
/// 实测见该方法文档注释"abortedRunId == nil 时"一节）。若 `SessionStore` 只靠 `.turnComplete` 分支
/// 清 `isWaitingForReply`，composer 会在这条路径下永久卡在"等待回复…"。
@MainActor
func testSessionStoreOperationCompletedInterruptNoActiveRunClearsWaitingForReply() -> Bool {
    let name = "rounds/0020 (task item 4, core): evt.operation_completed(operationKind:.interrupt, outcome:.succeeded, affectedRunId:nil) — the abortedRunId==nil path, which never emits turn_complete — clears session.isWaitingForReply"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-noactive-ui-1", kernelKey: "kernel-key-interrupt-noactive-ui-1")
    session.isWaitingForReply = true

    store.handle(
        interruptUIOperationCompletedEvent(
            operationID: "op-noactive-1", operationKind: .interrupt, outcome: .succeeded,
            affectedRunID: nil, sessionID: session.id
        ),
        for: session
    )

    guard session.isWaitingForReply == false else {
        return fail(name, "expected isWaitingForReply to be cleared by the interrupt operation_completed mirror (this path never emits turn_complete — see OpenclawGatewayKernelClient.interrupt()'s 'abortedRunId == nil 时' doc section), got still true — composer would be stuck showing '等待回复…' forever")
    }
    return pass(name, "operation_completed(operationKind:.interrupt, outcome:.succeeded, affectedRunId:nil) correctly clears isWaitingForReply even though no turn_complete was ever emitted for this operation")
}

/// **T-113 rework（grok 对抗评审 item 2）倒转**：这条测试修前断言 `.timedOut` 清
/// `isWaitingForReply`——理由是"这条路径同样从不产出 turn_complete"。那个源码事实没有错，但从它推出
/// "所以要清"这一步是错的：`.timedOut` 意味着 `sessions.abort` **已经**被内核接受、返回了一个真实的
/// `abortedRunId`（证明确实有一个活跃 run、内核确认接手了它的 abort），只是我们没能在本地等待窗口内
/// 等到它的收尾帧——这与"这个 run 已经不在跑了"完全是两回事，`.timedOut` 就是字面意思：**不确认**。
/// 现在改为断言相反的行为：`.timedOut` **不清** `isWaitingForReply`（`handleOperationCompleted` 现在
/// 的条件是 `operationKind==.interrupt && outcome==.succeeded`，见该方法文档注释完整推理）——这不会
/// 让 UI 永久卡死：T-113 item 1 已经修好的兜底分支意味着，只要那条迟到的终态帧真的到达（openclaw
/// 现场行为：几乎总会到），会补发一条 `turn_complete(cancelled)`，经由本文件下面
/// `testInterruptCurrentRunSuccessPathDispatchesCancelModeEndToEndAndClearsWaitingForReply` 覆盖的
/// 同一条 `.turnComplete` 分支把 `isWaitingForReply` 补清；即使那条帧彻底丢失，按钮此刻仍然可点
/// （`isWaitingForReply` 还是 true），用户可以手动再点一次"停止"来恢复。
@MainActor
func testSessionStoreOperationCompletedInterruptTimeoutDoesNotClearWaitingForReply() -> Bool {
    let name = "T-113 item 2 (inverted): evt.operation_completed(operationKind:.interrupt, outcome:.timedOut) does NOT clear session.isWaitingForReply — sessions.abort was accepted (real abortedRunId) but we never confirmed the run actually stopped, so the UI must not claim it isn't waiting anymore"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-timeout-ui-1", kernelKey: "kernel-key-interrupt-timeout-ui-1")
    session.isWaitingForReply = true

    store.handle(
        interruptUIOperationCompletedEvent(
            operationID: "op-timeout-1", operationKind: .interrupt, outcome: .timedOut,
            affectedRunID: "run-timeout-1", sessionID: session.id
        ),
        for: session
    )

    guard session.isWaitingForReply == true else {
        return fail(name, "expected isWaitingForReply to remain true for outcome:.timedOut — we never confirmed the run actually stopped (sessions.abort returned a real abortedRunId but no terminal frame arrived within the wait window); clearing it here would falsely tell the UI 'not waiting anymore' and flip the composer button back to 发送 while the run may still be streaming, got false")
    }
    return pass(name, "operation_completed(operationKind:.interrupt, outcome:.timedOut) correctly leaves isWaitingForReply untouched — only a confirmed outcome:.succeeded may clear it; the 停止 button remains available for the user to retry")
}

/// **T-113 rework（grok 对抗评审 item 2）倒转**：这条测试修前的名字是
/// "...RejectedAlsoClearsWaitingForReply"，断言 `.rejected` 会清 `isWaitingForReply`——那条测试的
/// 历史需要如实记录：它是协调者（我，在更早一轮）自己要求补上的，当时只是发现 `.rejected` 这个取值
/// 缺测试覆盖就直接补了一条钉住"当时代码实际怎么做"的测试，**没有先核对那个行为本身是否正确**。
/// 现在核对下来它是错的——`interruptCurrentRun` 自己的文档注释（SessionStore.swift:391-394）早就
/// 论证过"中止失败不代表这个 run 已经不在跑了，贸然清掉会让 UI 撒谎说'已经不在等了'"，而 `.rejected`
/// 正是"中止失败"本身（`sessions.abort`/`forceDenyPendingApprovalsBeforeStop` 抛错，对内核状态
/// **零确认**）——旧测试钉住的行为与项目自己已经写下的设计原则直接矛盾，不能因为"当时测试是绿的"
/// 就当作正确性的证明。这里不是删掉旧测试，是倒转它断言的方向，并把这段历史留在注释里，不假装它
/// 从一开始就是这样写的。
@MainActor
func testSessionStoreOperationCompletedInterruptRejectedDoesNotClearWaitingForReply() -> Bool {
    let name = "T-113 item 2 (inverted — see comment for why the original test pinned the wrong behaviour): evt.operation_completed(operationKind:.interrupt, outcome:.rejected) does NOT clear session.isWaitingForReply — a failed abort attempt gives zero confirmation the run stopped; clearing it would make the UI lie and strand the user unable to retry 停止"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-rejected-ui-1", kernelKey: "kernel-key-interrupt-rejected-ui-1")
    session.isWaitingForReply = true

    store.handle(
        interruptUIOperationCompletedEvent(
            operationID: "op-rejected-1", operationKind: .interrupt, outcome: .rejected,
            affectedRunID: nil, sessionID: session.id
        ),
        for: session
    )

    guard session.isWaitingForReply == true else {
        return fail(name, "expected isWaitingForReply to remain true for outcome:.rejected — matches interruptCurrentRun's own doc comment (SessionStore.swift:391-394): a failed interrupt attempt does not mean the run isn't still going, clearing it would make the UI falsely claim 'not waiting anymore' AND flip the button back to 发送, leaving the user unable to even retry 停止, got false")
    }
    return pass(name, "operation_completed(operationKind:.interrupt, outcome:.rejected) correctly leaves isWaitingForReply untouched, matching interruptCurrentRun's documented rationale — the 停止 button remains available so the user can retry")
}

/// **回归/scoping 锁**：`operationKind:.stop` 的 operation_completed 不应被这条新逻辑影响——`stop()`
/// 的全部路径最终都会发 `session_end`（`.sessionEnd` 分支早就清着这个位），本轮修复精确只对应
/// interrupt 的缺口，不应该意外扩大到 stop。若这条测试和上面两条同时绿，说明修复的 `if` 条件确实是
/// `operationKind == .interrupt`，不是无条件清除。
@MainActor
func testSessionStoreOperationCompletedStopDoesNotClearWaitingForReplyThroughThisPath() -> Bool {
    let name = "rounds/0020 regression guard: evt.operation_completed(operationKind:.stop) does NOT trigger the interrupt-specific isWaitingForReply clearing (stop()'s own session_end handler already owns that job)"
    let (store, session) = freshInterruptUISession(id: "sess-stop-opcompleted-ui-1", kernelKey: "kernel-key-stop-opcompleted-ui-1")
    session.isWaitingForReply = true

    store.handle(
        interruptUIOperationCompletedEvent(
            operationID: "op-stop-1", operationKind: .stop, outcome: .succeeded,
            affectedRunID: nil, sessionID: session.id
        ),
        for: session
    )

    guard session.isWaitingForReply == true else {
        return fail(name, "expected isWaitingForReply to remain UNTOUCHED by a .stop-kind operation_completed mirror (the rounds/0020 fix is scoped to operationKind==.interrupt only), got false — the fix over-reached beyond the documented interrupt-only gap")
    }
    return pass(name, "operation_completed(operationKind:.stop) leaves isWaitingForReply untouched, confirming the rounds/0020 fix is precisely scoped to interrupt (not an unconditional clear)")
}

// MARK: - ②（任务书第 1/3 条）：interruptCurrentRun(in:) 的 guard 语义

/// 未知 sessionID：no-op，且不误伤任何其它已注册会话的状态——`session(for:)` 必须按 id 精确匹配，
/// 不能"随便抓一个"。
@MainActor
func testInterruptCurrentRunOnUnknownSessionIDIsNoOpAndLeavesOtherSessionsUntouched() async -> Bool {
    let name = "rounds/0020: interruptCurrentRun(in:) on a sessionID absent from store.sessions is a no-op — does not touch any OTHER registered session's state"
    let (store, decoySession) = freshInterruptUISession(id: "sess-interrupt-decoy-1", kernelKey: "kernel-key-interrupt-decoy-1")
    store.testSupportRegisterSession(decoySession)
    // 注意：这里刻意不给 `store.client` 播种这个 sessionID 的 kernelKey——如果 guard 失效、错误地
    // 操作了 decoySession，紧接着的 `client.interrupt()` 会因为 unknown session 抛错，从而在
    // decoySession.messages 上留下痕迹，让下面的断言能捕捉到这个失效（见反证记录）。

    await store.interruptCurrentRun(in: "sess-interrupt-does-not-exist")

    guard decoySession.isInterrupting == false, decoySession.messages.isEmpty else {
        return fail(name, "expected the one registered (but differently-id'd) session to be completely untouched, got isInterrupting=\(decoySession.isInterrupting) messages=\(decoySession.messages.map(\.text))")
    }
    return pass(name, "interruptCurrentRun(in: <unknown id>) left the only registered session (a different id) entirely untouched — session(for:) matches by id, not 'any session'")
}

/// `isInterrupting` 已经是 true 时（模拟"中止请求已经在途"）：模型层 guard 必须在真正调用
/// `client.interrupt()` 之前就短路——用一个记录调用的 RPC 桩证明零 RPC 派发,不是靠"结果凑巧一样"
/// 蒙混过关。
@MainActor
func testInterruptCurrentRunSkipsDispatchWhenAlreadyInterrupting() async -> Bool {
    let name = "rounds/0020 (task item 3, model-layer half of the defense): interruptCurrentRun(in:) never calls client.interrupt() when session.isInterrupting is already true"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-already-1", kernelKey: "kernel-key-interrupt-already-1")
    store.testSupportRegisterSession(session)
    _ = await store.client.testSupportRegisterSession(ourSessionID: session.id, kernelKey: "kernel-key-interrupt-already-1")
    let callLog = CallOrderLog()
    await store.client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    session.isInterrupting = true // 模拟"已经有一次 interrupt 在途"

    await store.interruptCurrentRun(in: session.id)

    let order = await callLog.entries
    guard order.isEmpty else {
        return fail(name, "expected ZERO RPC dispatch (client.interrupt() must never even be called) while isInterrupting was already true, got \(order)")
    }
    guard session.isInterrupting == true else {
        return fail(name, "expected isInterrupting to remain true (this call should be a pure no-op — it must not even flip it false via its own defer), got false")
    }
    return pass(name, "a second interruptCurrentRun() call while one was already in flight (isInterrupting==true) dispatched zero RPCs and left isInterrupting untouched — the model-layer guard short-circuits before ever reaching client.interrupt()")
}

// MARK: - ③（任务书第 1 条）：如实转发失败，不吞掉

/// 真实 throw（未知 kernelKey -> `KernelClientError.protocolMismatch`，不需要任何网络 I/O 就能
/// 确定性触发——`client.interrupt()` 的第一道 guard 在任何 RPC dispatch 之前就会命中）经
/// `interruptCurrentRun` 转成一条 `[停止失败]` 系统消息，且 `isInterrupting` 正确复位。
@MainActor
func testInterruptCurrentRunSurfacesThrownErrorAsSystemMessageAndResetsInterruptingFlag() async -> Bool {
    let name = "rounds/0020 (task item 1): interruptCurrentRun(in:) surfaces a REAL thrown error from client.interrupt() as a '[停止失败]' system message — does not swallow it — and resets isInterrupting back to false afterward"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-fail-1", kernelKey: "kernel-key-interrupt-fail-1")
    store.testSupportRegisterSession(session)
    // 有意不给 `store.client` 播种这个 sessionID 的 kernelKey——`client.interrupt()` 的第一道 guard
    // （`kernelKeyBySessionID[session.sessionID]` 查不到）会真实抛出
    // `KernelClientError.protocolMismatch`，不需要任何网络 I/O 就能触发这条失败路径,是一个真实、
    // 确定性的 throw，不是模拟/伪造的。

    await store.interruptCurrentRun(in: session.id)

    guard session.isInterrupting == false else {
        return fail(name, "expected isInterrupting to be reset to false after the throw (via defer), got still true")
    }
    guard let last = session.messages.last, last.role == .system, last.text.contains("停止失败") else {
        return fail(name, "expected a system message surfacing the failure ('[停止失败] ...'), got messages=\(session.messages.map { ($0.role, $0.text) }) — the error must not be silently swallowed")
    }
    guard last.text.contains("unknown session") else {
        return fail(name, "expected the surfaced error text to include the real underlying protocolMismatch description ('unknown session ...'), got '\(last.text)'")
    }
    return pass(name, "a real thrown KernelClientError.protocolMismatch from client.interrupt() (unknown session — no kernelKey registered) was honestly surfaced as a system message ('\(last.text)'), not swallowed; isInterrupting correctly reset to false")
}

// MARK: - ④ 端到端成功路径

/// 端到端：`interruptCurrentRun` 真打一次 `client.interrupt(mode:.cancel)`（stub 的 `sessions.abort`
/// 回 `abortedRunId:null` —— 无 active run 分支，不需要额外喂 aborted lifecycle 帧就能立即
/// succeeded），产出的真实 evt.operation_completed 事件被排空、喂给 `handle()` 后
/// `isWaitingForReply` 被正确清掉，且没有失败系统消息。
@MainActor
func testInterruptCurrentRunSuccessPathDispatchesCancelModeEndToEndAndClearsWaitingForReply() async -> Bool {
    let name = "rounds/0020: interruptCurrentRun(in:) end-to-end — dispatches a real client.interrupt(mode:.cancel) call, produces a real operation_completed event, and once that event is drained through SessionStore.handle, isWaitingForReply is cleared with no failure message appended"
    let (store, session) = freshInterruptUISession(id: "sess-interrupt-e2e-1", kernelKey: "kernel-key-interrupt-e2e-1")
    store.testSupportRegisterSession(session)
    session.isWaitingForReply = true
    let stream = await store.client.testSupportRegisterSession(ourSessionID: session.id, kernelKey: "kernel-key-interrupt-e2e-1")
    let callLog = CallOrderLog()
    await store.client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }

    await store.interruptCurrentRun(in: session.id)

    guard session.isInterrupting == false else {
        return fail(name, "expected isInterrupting reset to false after a successful call, got true")
    }
    guard !session.messages.contains(where: { $0.text.contains("停止失败") }) else {
        return fail(name, "expected NO failure message on the success path, got \(session.messages.map(\.text))")
    }
    let order = await callLog.entries
    guard order == ["sessions.abort"] else {
        return fail(name, "expected exactly one real sessions.abort RPC dispatch (proving interruptCurrentRun really called client.interrupt(), not a no-op), got \(order)")
    }

    // 排空这次 interrupt() 真实产出的事件（走的是 `testSupportRegisterSession` 返回的同一条
    // stream），模拟生产环境 `consumeEvents()` 会做的事——喂给 `handle()`，验证 isWaitingForReply
    // 真的被清掉，不是这个测试自己伪造一条 operation_completed 事件来单独验证 handle() 的逻辑
    // （那部分已经被上面「①核心」的三条测试独立覆盖）。
    let events = await collectUpTo(stream, maxCount: 2, timeoutMs: 300)
    guard events.count == 1, case .operationCompleted(let op) = events[0],
          op.payload.operationKind == .interrupt, op.payload.outcome == .succeeded else {
        return fail(name, "expected exactly 1 real operation_completed(operationKind:.interrupt, outcome:.succeeded) event from the real interrupt() call, got \(events.count): \(events.map { $0.wireType })")
    }
    store.handle(events[0], for: session)

    guard session.isWaitingForReply == false else {
        return fail(name, "expected isWaitingForReply to be cleared after the real end-to-end event was processed through handle(), got still true")
    }
    return pass(name, "interruptCurrentRun(in:) dispatched a real client.interrupt(mode:.cancel) call (1 real sessions.abort RPC, order=\(order)), produced a real operation_completed(interrupt,succeeded) event, and processing it through handle() correctly cleared isWaitingForReply end-to-end")
}

// MARK: - 汇总入口

func runSessionStoreInterruptTests() async -> [Bool] {
    var results: [Bool] = []
    // 这几个函数本身虽是同步的（不带 `async`），但标了 `@MainActor`——从这个非隔离的 `async` 汇总
    // 函数调用需要 `await` 完成一次 actor hop（同 FrameReplayTests.swift 里对
    // testSessionStoreHandleToolCallProducesToolCallItem 等同类型函数的既有调用方式）。
    results.append(await testSessionStoreOperationCompletedInterruptNoActiveRunClearsWaitingForReply())
    results.append(await testSessionStoreOperationCompletedInterruptTimeoutDoesNotClearWaitingForReply())
    results.append(await testSessionStoreOperationCompletedInterruptRejectedDoesNotClearWaitingForReply())
    results.append(await testSessionStoreOperationCompletedStopDoesNotClearWaitingForReplyThroughThisPath())
    results.append(await testInterruptCurrentRunOnUnknownSessionIDIsNoOpAndLeavesOtherSessionsUntouched())
    results.append(await testInterruptCurrentRunSkipsDispatchWhenAlreadyInterrupting())
    results.append(await testInterruptCurrentRunSurfacesThrownErrorAsSystemMessageAndResetsInterruptingFlag())
    results.append(await testInterruptCurrentRunSuccessPathDispatchesCancelModeEndToEndAndClearsWaitingForReply())
    return results
}
