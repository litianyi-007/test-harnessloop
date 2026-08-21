// rounds/0023：`interrupt(mode:"steer")`（D1 v3.6 §6.1(a) soft inject）真 actor 级单测 + `stop()`
// 遇 `interrupt_in_progress` 的 §9.3 仲裁修正（steer 侧覆盖；cancel 侧覆盖见 InterruptTests.swift
// `testSendRejectedButStopWaitsThenProceedsWhileInterruptInFlight`）。
//
// 覆盖 scope-lock rounds/0023 全部验收项，逐条对应下面的测试：
//   - steer 二态（submitted/rejected，无第三态）——
//     testInterruptSteerCallsChatSendWithQueueModeSteerDeliverFalseAndSucceedsAsSubmitted /
//     testInterruptSteerRpcFailureIsRejectedNotAThirdOutcome
//   - RPC 选择（chat.send，不是 sessions.abort/sessions.steer/sessions.send）——上面同一条 submitted
//     测试直接断言 params 形状与调用顺序。
//   - 无 active run -> 同步前置 reject，不铸 operationId、不产生 OperationOutcome ——
//     testInterruptSteerNoActiveRunPreRejectsSynchronouslyNoOperationId
//   - steer 不做强制 deny（与 cancel 的行为差异，防将来误合并）——
//     testInterruptSteerDoesNotForceDenyPendingApprovalsUnlikeCancel
//   - 第 2 条偏离（§9.3 仲裁）用 steer 专门构造的用例（取舍 4 允许"steer 或 cancel 均可"，
//     cancel 版本见 InterruptTests.swift；这里是 steer 版本，直接验证本轮新增的 RPC 路径与仲裁的
//     交互）——testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted
//   - 超时归属（stop() 自己的 timed_out，不是 interrupt 的第三终态）——
//     testStopOwnTimeoutWhenArbitrationWaitExceedsBoundIsNeverAnInterruptOutcome
//   - send() 侧未被放松（矩阵只为 stop() 定义仲裁）——testSendStillRejectedWhileSteerInterruptInFlight
//
// rounds/0023 REWORK（T-116 codex 对抗评审 FAIL 2 —— "wait, don't preempt" 缺少原子交接，见
// `OpenclawGatewayKernelClient.swift` `performAtomicInterruptLockHandoff`/
// `InterruptLockArbitrationOutcome` 的完整推理）：
//   - 原子交接反证——一个在交接运行前就已排队等待进入 actor 的第三方 send() 必须永远无法在
//     interrupt()->stop() 的交接瞬间观察到 idle、偷走本该属于等待中 stop() 的锁——
//     testConcurrentSendCannotStealLockDuringAtomicInterruptToStopHandoff
//
// 复用既有测试基础设施（`freshClient`/`testHandle`/`collectUpTo`/`CallOrderLog`/`DispatchFlag`/
// `InterruptRaceBox`，定义分别在 FrameReplayTests.swift 与 InterruptTests.swift，同 target 内可见）。
//
// **建立"活跃 run"的唯一方式是真实 send()**（不是喂合成 agent 帧）——`interrupt(mode:"steer")` 的前置
// 校验读的是 `activeRunIDsBySessionID`，这张表只在 `send()` 拿到 RPC ack 时插入（见
// `OpenclawGatewayKernelClient.swift` 该表的文档注释），本文件全部"有 active run"场景都先真实驱动
// 一次 `send()`，不走捷径。
//
// `@testable import`：同 InterruptTests.swift/FrameReplayTests.swift（两个 target 都带
// `-enable-testing`），拿到 `interrupt()`/`testSupportSetStopArbitrationTimeoutSeconds`/
// `testSupportLockState` 等 internal 符号。

import Foundation
@testable import KernelClient
import D2Generated

// MARK: - 前置校验：无 active run -> 同步 reject，不铸 operationId

func testInterruptSteerNoActiveRunPreRejectsSynchronouslyNoOperationId() async -> Bool {
    let name = "rounds/0023 interrupt(mode:\"steer\") with no locally observed active run -> synchronous no_active_run_for_steer reject BEFORE operationId minting, no OperationOutcome, zero RPC dispatched"
    let client = freshClient()
    let sessionID = "sess-steer-no-active-run"
    let kernelKey = "kernel-key-steer-no-active-run"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    // 防御性注册——若前置校验被误删/绕过，这个 stub 会真的被调用，callLog 会诚实暴露它。
    await client.testSupportStubRPC(method: "chat.send") { _ in
        await callLog.record("chat.send")
        return ["runId": "should-never-be-reached", "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "expected interrupt(mode:\"steer\") to throw no_active_run_for_steer when there is no locally observed active run")
    } catch KernelClientError.rpcRejected(let code, _) where code == "no_active_run_for_steer" {
        // 期望路径。
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected(code:\"no_active_run_for_steer\"), got \(error)")
    }

    let order = await callLog.entries
    guard order.isEmpty else {
        return fail(name, "expected zero RPC dispatch for the synchronous pre-reject (no operationId minted, no RPC attempted), got \(order)")
    }
    let lockAfter = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfter == "idle" else {
        return fail(name, "expected lock to remain idle (never entered interrupt_in_progress) for a synchronous pre-reject, got \(lockAfter)")
    }
    let events = await collectUpTo(stream, maxCount: 1, timeoutMs: 150)
    guard events.isEmpty else {
        return fail(name, "expected zero events (no OperationOutcome — the precondition rejects before any operationId is minted), got \(events.count): \(events.map { $0.wireType })")
    }
    return pass(name, "interrupt(mode:\"steer\") 在无本地可观察 active run 时同步 reject(no_active_run_for_steer)：零 RPC 派发、锁保持 idle、零事件（未铸 operationId，不产生 OperationOutcome）")
}

// MARK: - 成功路径：真调用 chat.send，params 形状正确，outcome=.submitted

func testInterruptSteerCallsChatSendWithQueueModeSteerDeliverFalseAndSucceedsAsSubmitted() async -> Bool {
    let name = "rounds/0023 interrupt(mode:\"steer\") with an active run calls chat.send (NOT sessions.abort/sessions.steer/sessions.send) with sessionKey+queueMode:\"steer\"+deliver:false, succeeds as outcome:.submitted, session survives"
    let client = freshClient()
    let sessionID = "sess-steer-succeeds"
    let kernelKey = "kernel-key-steer-succeeds"
    let runID = "run-steer-succeeds-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    let capturedBox = InterruptRaceBox<JSONObject>()
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        await callLog.record("sessions.send")
        return ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { params in
        await callLog.record("chat.send")
        await capturedBox.report(params)
        return ["runId": runID, "status": "queued"] as JSONObject
    }
    // 反证用：若实现回归成调用这些方法之一，callLog 的最终顺序断言会如实暴露，不需要额外 guard。
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    // 建立一个真实活跃 run——interrupt(mode:"steer") 的前置校验依据的是这次 send() ack，不是喂合成帧。
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    guard let result = try? await client.interrupt(session: handle, options: options) else {
        return fail(name, "interrupt(mode:\"steer\") unexpectedly threw")
    }
    guard result.outcome == .submitted else {
        return fail(name, "expected outcome=.submitted, got \(result.outcome)")
    }
    guard result.affectedRunID == nil, result.interruptedActiveRun == nil, result.newRunID == nil else {
        return fail(name, "expected affectedRunID/interruptedActiveRun/newRunID all nil (steer never aborts a run) — got affectedRunID=\(result.affectedRunID ?? "nil"), interruptedActiveRun=\(String(describing: result.interruptedActiveRun)), newRunID=\(result.newRunID ?? "nil")")
    }

    let params = await capturedBox.wait()
    guard (params["sessionKey"] as? String) == kernelKey else {
        return fail(name, "expected chat.send params.sessionKey == kernelKey (\(kernelKey)) — the sessionKey field, NOT the sessions.*-style 'key' field, got \(params)")
    }
    guard params["key"] == nil else {
        return fail(name, "expected chat.send params to NOT contain a 'key' field (that's the sessions.* addressing field name, not chat.send's), got \(params)")
    }
    guard (params["message"] as? String) == "steer text" else {
        return fail(name, "expected chat.send params.message == the interrupt() input text, got \(params["message"] ?? "<missing>")")
    }
    guard (params["queueMode"] as? String) == "steer" else {
        return fail(name, "expected chat.send params.queueMode == \"steer\", got \(params["queueMode"] ?? "<missing>")")
    }
    guard let deliverValue = params["deliver"] as? Bool, deliverValue == false else {
        return fail(name, "expected chat.send params.deliver == false, got \(params["deliver"] ?? "<missing>")")
    }
    guard params["idempotencyKey"] != nil else {
        return fail(name, "expected chat.send params.idempotencyKey to be present (ChatSendParamsSchema requires it, non-optional)")
    }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 300)
    guard events.count == 1, case .operationCompleted(let op) = events[0] else {
        return fail(name, "expected exactly 1 event (operation_completed mirror only — no session_end, no turn_complete, steer doesn't touch run lifecycle), got \(events.count): \(events.map { $0.wireType })")
    }
    guard op.payload.outcome == .submitted, op.payload.operationID == result.operationID, op.payload.operationKind == .interrupt else {
        return fail(name, "operation_completed must mirror the Promise: outcome=.submitted operationKind=.interrupt operationId=\(result.operationID), got outcome=\(op.payload.outcome) operationKind=\(op.payload.operationKind) id=\(op.payload.operationID)")
    }

    // 会话存活 + steer 从不触碰 sessions.abort/sessions.delete（红线，与 cancel 的路径彻底分开）。
    let order = await callLog.entries
    guard order == ["sessions.send", "chat.send"] else {
        return fail(name, "expected RPC call order [sessions.send, chat.send] — steer must NEVER dispatch sessions.abort/sessions.delete/sessions.steer, got \(order)")
    }
    guard let sendAfterwards = try? await client.send(session: handle, input: Input(kind: .text, text: "still alive after steer", parts: nil)) else {
        return fail(name, "RED LINE: send() after a successful steer failed — the session did not survive")
    }

    return pass(name, "interrupt(mode:\"steer\") 真实调用 chat.send（不是 sessions.abort/sessions.steer/sessions.send），params={sessionKey,message,queueMode:\"steer\",deliver:false,idempotencyKey} 均正确、且不含 sessions.* 系列的 'key' 字段，outcome=.submitted，operation_completed 镜像一致，affectedRunID/interruptedActiveRun/newRunID 均为 nil，会话存活（后续 send() 成功返回 runId=\(sendAfterwards.runID)）")
}

// MARK: - 失败路径：RPC 失败 -> rejected（抛错 + 镜像），不是第三终态

func testInterruptSteerRpcFailureIsRejectedNotAThirdOutcome() async -> Bool {
    let name = "rounds/0023 interrupt(mode:\"steer\"): chat.send RPC failure (incl. transport-level) is rejected via thrown error + operation_completed(rejected) mirror, never a third outcome; lock released; second attempt not falsely session_locked"
    let client = freshClient()
    let sessionID = "sess-steer-rpc-fails"
    let kernelKey = "kernel-key-steer-rpc-fails"
    let runID = "run-steer-rpc-fails-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        throw KernelClientError.transport("simulated: connection reset mid steer")
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "expected interrupt(mode:\"steer\") to rethrow the chat.send failure")
    } catch KernelClientError.transport(let message) {
        guard message.contains("simulated") else { return fail(name, "unexpected transport error message \(message)") }
    } catch {
        return fail(name, "expected KernelClientError.transport, got \(error)")
    }

    let lockAfterFailure = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterFailure == "idle" else {
        return fail(name, "expected lock released to idle after chat.send throw, got \(lockAfterFailure)")
    }
    guard await client.testSupportHasPendingStop(sessionID: sessionID) == false else {
        return fail(name, "expected no pendingStop entry — steer never populates pendingStops in the first place (see performSoftSteerInterrupt doc comment)")
    }

    let events = await collectUpTo(stream, maxCount: 2, timeoutMs: 300)
    guard events.count == 1, case .operationCompleted(let op) = events[0] else {
        return fail(name, "expected exactly 1 event (operation_completed(rejected) mirror), got \(events.count): \(events.map { $0.wireType })")
    }
    guard op.payload.outcome == .rejected, op.payload.operationKind == .interrupt else {
        return fail(name, "expected operation_completed(rejected, operationKind:.interrupt), got outcome=\(op.payload.outcome) operationKind=\(op.payload.operationKind)")
    }
    guard op.payload.affectedRunID == nil else {
        return fail(name, "expected affectedRunID=nil on the rejected mirror (steer never aborts a run, even on failure), got \(op.payload.affectedRunID ?? "nil")")
    }

    // 关键复现（同 cancel 既有测试的既定手法，见 InterruptTests.swift
    // testInterruptAbortRpcThrowReleasesLockAndEmitsRejectedMirror）：第二次 interrupt(steer) 不应该
    // 被 session_locked 拒绝——它应该照样命中同一个失败的 chat.send stub，再次抛出同样的错误，证明
    // 锁真的被释放了（本次会话仍有 activeRunID，前置校验不会拦截这次重试）。
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "expected second interrupt(mode:\"steer\") to also throw the stubbed chat.send failure")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        return fail(name, "second interrupt(mode:\"steer\") incorrectly rejected with session_locked — 锁没有被正确释放")
    } catch KernelClientError.transport {
        return pass(name, "chat.send 失败时 interrupt(mode:\"steer\") 如实抛出 transport 错误（未合成任何『第三终态』），operation_completed(rejected, operationKind:.interrupt, affectedRunID:nil) 镜像已发出，锁正确释放为 idle（无 pendingStop 残留——steer 从不使用它），第二次调用正常再次尝试（而不是被 session_locked 挡住）")
    } catch {
        return fail(name, "unexpected error on second interrupt(mode:\"steer\"): \(error)")
    }
}

// MARK: - steer 不做强制 deny（与 cancel 的行为差异）

func testInterruptSteerDoesNotForceDenyPendingApprovalsUnlikeCancel() async -> Bool {
    let name = "rounds/0023 interrupt(mode:\"steer\") does NOT force-deny pending approvals (unlike cancel/stop) — steer never aborts the run, so D1 §6.2 M3's force-deny precondition does not apply"
    let client = freshClient()
    let sessionID = "sess-steer-pending-approval"
    let kernelKey = "kernel-key-steer-pending-approval"
    let runID = "run-steer-pending-approval-1"
    let approvalID = "approval-steer-pending-1"
    let toolCallID = "tool-steer-pending-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
            "ts": 1_784_900_000_000,
        ] as JSONObject,
    ])
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_900_000_100, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo steer-pending-approval"] as JSONObject,
                "createdAtMs": 1_784_900_000_100, "expiresAtMs": 1_784_901_800_100,
            ] as JSONObject,
        ] as JSONObject,
    ])
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "expected approvalID to be registered as pending-awaiting-decision before interrupt(steer)")
    }

    let approvalResolveCalled = DispatchFlag()
    await client.testSupportStubRPC(method: "approval.resolve") { _ in
        await approvalResolveCalled.markDispatched()
        return ["applied": true, "approval": ["id": approvalID, "status": "denied", "decision": "deny", "reason": "user"] as JSONObject] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        ["runId": runID, "status": "queued"] as JSONObject
    }

    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    guard let result = try? await client.interrupt(session: handle, options: options) else {
        return fail(name, "interrupt(mode:\"steer\") unexpectedly threw")
    }
    guard result.outcome == .submitted else {
        return fail(name, "expected outcome=.submitted, got \(result.outcome)")
    }

    guard await approvalResolveCalled.dispatched == false else {
        return fail(name, "RED LINE VIOLATED: interrupt(mode:\"steer\") called approval.resolve — steer must NOT force-deny pending approvals (unlike cancel/stop); it never aborts the run, the pending approval should remain untouched")
    }
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "expected the pending approval to remain pending-awaiting-decision after a successful steer — it must survive completely untouched")
    }

    _ = await collectUpTo(stream, maxCount: 5, timeoutMs: 200) // 排空 approvalRequest + operation_completed，不在本测试重复断言事件形状（成功路径已由上面那条测试覆盖）
    return pass(name, "interrupt(mode:\"steer\") 成功（outcome=.submitted）但从未调用 approval.resolve，pending 审批原样保留——steer 不 abort run，D1 §6.2 M3 的强制 deny 前提不适用，与 cancel/stop 的既有行为形成对照")
}

// MARK: - 取舍 4：真正构造用例暴露第 2 条偏离（steer 版本）——stop() 等待，不抢占

func testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted() async -> Bool {
    let name = "rounds/0023 §9.3 arbitration (steer variant): stop() WAITS (not rejected) while a REAL interrupt(mode:\"steer\") is in flight; steer resolves .submitted unaffected; lock moves to stop_in_progress; stop() proceeds and succeeds"
    let client = freshClient()
    let sessionID = "sess-steer-arbitration"
    let kernelKey = "kernel-key-steer-arbitration"
    let runID = "run-steer-arbitration-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        await callLog.record("sessions.send")
        return ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        await callLog.record("chat.send")
        try? await Task.sleep(nanoseconds: 200_000_000)
        return ["runId": runID, "status": "queued"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        // rounds/0023 注：stop() 自己这次 sessions.abort 刻意回报 abortedRunId:null——本测试要验证
        // 的是"§9.3 仲裁本身"（stop() 是否等待、interrupt 是否被保护、锁是否按序转移），不是 stop()
        // 后续等待 aborted lifecycle 终态那条已经被 InterruptTests.swift/既有 stop() 测试充分覆盖
        // 的独立机制——若这里回报一个非空 abortedRunId 却不喂对应的终态帧，stop() 会老老实实等满
        // 生产默认 5 秒才超时，把本测试的意图（验证仲裁转移）淹没在一个无关的等待里。
        //
        // 100ms 的延迟是刻意的：`abortedRunId:null` 分支本身不需要等待任何终态帧，会近乎瞬间完成
        // （abort -> succeeded -> sessions.delete -> 返回），比下面"仲裁成功后锁应转 stop_in_progress"
        // 这一步的探测窗口（interrupt 解决后 30ms）快得多，会让那个检查点在 stop() 早已完全跑完、锁
        // 已经回到 idle 之后才执行，不是在验证"转移到了 stop_in_progress"，而是在验证一个不存在的
        // 时序假设。加一点延迟让 stop_in_progress 这个中间态有真实、可被观察到的存续时间。
        try? await Task.sleep(nanoseconds: 100_000_000)
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    async let interruptTask = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 40_000_000)
    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock=interrupt_in_progress while interrupt(mode:\"steer\") RPC in flight, got \(lockDuringFlight) — 说明锁没有被真实获取（这正是 T-115 指出的旧近因：mode guard 在拿锁之前就把 steer 挡了下来，本轮已消除那条前置拒绝路径）")
    }

    let stopBox = InterruptRaceBox<Result<StopResultPayload, Error>>()
    let stopTask = Task<Void, Never> {
        do {
            let result = try await client.stop(session: handle)
            await stopBox.report(.success(result))
        } catch {
            await stopBox.report(.failure(error))
        }
    }
    let waitWindow = await observeStopWaitingOnInterrupt(
        client: client, sessionID: sessionID, stopHasReported: { await stopBox.hasReported }
    )
    if waitWindow.stopReportedEarly {
        _ = try? await interruptTask
        return fail(name, "stop() 在 interrupt(mode:\"steer\") 仍在飞行期间就已经报告结果——应当等待，不该立即 reject（旧行为）或立即抢占成功（同样违反『不抢占』）")
    }
    guard waitWindow.sawWaitWindow else {
        _ = try? await interruptTask
        return fail(name, "expected lock to remain interrupt_in_progress while stop() waits for the in-flight steer, got \(waitWindow.lastLock) — stop() 抢占了锁")
    }

    guard let interruptResult = try? await interruptTask else {
        return fail(name, "interrupt(mode:\"steer\") unexpectedly threw")
    }
    guard interruptResult.outcome == .submitted else {
        return fail(name, "expected interrupt(mode:\"steer\") outcome=.submitted despite stop() arbitrating against it, got \(interruptResult.outcome) — 仲裁等待不应该影响 interrupt() 自己的终态判定，且严格二态、不产生第三态")
    }

    // interrupt() Promise 一返回，stop() 应该几乎立刻把锁转成 stop_in_progress——这是"等待，不抢占"
    // 仲裁成功后的既定下一步，不需要再等 stop() 自己那次 sessions.abort（它还要再等 0ms，本测试的
    // sessions.abort stub 无延迟，但真实调度仍需要一点余量）才发生。
    try? await Task.sleep(nanoseconds: 30_000_000)
    let lockAfterSteerResolved = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterSteerResolved == "stop_in_progress" else {
        return fail(name, "expected lock=stop_in_progress shortly after the in-flight steer resolved, got \(lockAfterSteerResolved) — stop() 没有在仲裁成功后正常推进")
    }

    let stopOutcome = await stopBox.wait()
    switch stopOutcome {
    case .success(let stopResult):
        guard stopResult.outcome == .succeeded else {
            return fail(name, "expected stop() outcome=.succeeded once it proceeded, got \(stopResult.outcome)")
        }
    case .failure(let error):
        return fail(name, "expected stop() to eventually succeed after waiting for the in-flight steer, not throw \(error)")
    }
    stopTask.cancel() // stopTask 早已跑完；习惯性收尾。

    let finalOrder = await callLog.entries
    guard finalOrder == ["sessions.send", "chat.send", "sessions.abort", "sessions.delete"] else {
        return fail(name, "expected RPC call order [sessions.send, chat.send(steer), sessions.abort(stop), sessions.delete(stop)], got \(finalOrder)")
    }

    return pass(name, "steer 在途时 stop() 真实等待（lock 全程保持 interrupt_in_progress，t≈100ms 时仍未报告结果）；steer 完成后（outcome=.submitted，严格二态、未受仲裁影响）锁立即转 stop_in_progress，stop() 随后正常推进并成功完成（RPC 顺序=\(finalOrder)）——这正是取舍 4 要求的『真正进入 interrupt_in_progress 的 steer + stop() 到达』构造，真实并发驱动，不是摆拍")
}

// MARK: - 超时归属：stop() 自己的 timed_out，不是 interrupt 的第三终态

func testStopOwnTimeoutWhenArbitrationWaitExceedsBoundIsNeverAnInterruptOutcome() async -> Bool {
    let name = "rounds/0023 取舍 2/超时归属: when stop()'s arbitration wait exceeds its bound, the timeout is stop()'s OWN outcome:.timed_out — never a third outcome for the still in-flight interrupt(mode:\"steer\"), which independently resolves to one of its own two outcomes afterward"
    let client = freshClient()
    let sessionID = "sess-steer-arbitration-timeout"
    let kernelKey = "kernel-key-steer-arbitration-timeout"
    let runID = "run-steer-arbitration-timeout-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportSetStopArbitrationTimeoutSeconds(1) // 生产 5 秒太慢，收窄到 1 秒验证超时路径
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        // 故意让这次 RPC 比 stop() 的 1 秒仲裁上限更晚返回（1.6 秒）——证明超时确实是 stop() 自己的
        // 判断（在 RPC 仍然真实在途时就诚实放弃），不是 interrupt() 提前收敛或被强行结束。
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        return ["runId": runID, "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    async let interruptTask = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 40_000_000)
    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock=interrupt_in_progress while interrupt(mode:\"steer\") RPC in flight, got \(lockDuringFlight)")
    }

    let start = Date()
    guard let stopResult = try? await client.stop(session: handle) else {
        _ = try? await interruptTask
        return fail(name, "expected stop() to return normally (outcome:.timedOut), not throw")
    }
    let elapsed = Date().timeIntervalSince(start)
    guard stopResult.outcome == .timedOut else {
        _ = try? await interruptTask
        return fail(name, "expected stop() outcome=.timedOut once its 1s arbitration bound was exceeded, got \(stopResult.outcome)")
    }
    guard elapsed < 1.5 else {
        _ = try? await interruptTask
        return fail(name, "stop() took \(elapsed)s — expected it to time out at ~1s (the arbitration bound), not wait for the still-pending 1.6s chat.send")
    }

    // stop() 放弃等待的这一刻，interrupt(mode:"steer") 仍然真实在途——它的 RPC 还要再等 ~1s 才会
    // 返回。锁此刻必须仍是 interrupt_in_progress（stop() 从未抢占、从未触碰它），不是任何其它取值。
    let lockRightAfterStopGivesUp = await client.testSupportLockState(sessionID: sessionID)
    guard lockRightAfterStopGivesUp == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock to still be interrupt_in_progress immediately after stop() gives up (steer's RPC is genuinely still in flight, stop() never touched the lock on timeout), got \(lockRightAfterStopGivesUp)")
    }

    // stop() 的 timed_out 必须有自己的 operationId + operation_completed(timed_out, operationKind:.stop) 镜像。
    let eventsAfterStopTimeout = await collectUpTo(stream, maxCount: 1, timeoutMs: 300)
    guard eventsAfterStopTimeout.count == 1, case .operationCompleted(let stopOp) = eventsAfterStopTimeout[0] else {
        return fail(name, "expected exactly 1 event (stop()'s own operation_completed(timed_out) mirror), got \(eventsAfterStopTimeout.count): \(eventsAfterStopTimeout.map { $0.wireType })")
    }
    guard stopOp.payload.outcome == .timedOut, stopOp.payload.operationKind == .stop, stopOp.payload.operationID == stopResult.operationID else {
        return fail(name, "expected operation_completed(timed_out, operationKind:.stop) mirroring stop()'s own operationId=\(stopResult.operationID), got outcome=\(stopOp.payload.outcome) operationKind=\(stopOp.payload.operationKind) id=\(stopOp.payload.operationID)")
    }

    // interrupt(mode:"steer") 仍然独立在途（它完全不知道 stop() 已经放弃等待）——继续等它，它应该在
    // ~1.6 秒标记正常收敛为 .submitted，不受 stop() 超时影响，也绝不会自己冒出一个第三终态。
    guard let interruptResult = try? await interruptTask else {
        return fail(name, "expected the still in-flight interrupt(mode:\"steer\") to eventually resolve normally, not throw")
    }
    guard interruptResult.outcome == .submitted else {
        return fail(name, "expected interrupt(mode:\"steer\") to still resolve as .submitted (unaffected by stop()'s earlier timeout — never a third outcome), got \(interruptResult.outcome)")
    }

    let lockAfterSteerFinallyResolved = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterSteerFinallyResolved == "idle" else {
        return fail(name, "expected lock=idle after the (by-then-unwaited-for) steer resolved on its own — stop() already gave up and never claimed stop_in_progress for this attempt, got \(lockAfterSteerFinallyResolved)")
    }

    return pass(name, "stop() 的仲裁等待在 1 秒上限到期后诚实返回它自己的 outcome=.timedOut（operationId=\(stopResult.operationID)，耗时\(String(format: "%.2f", elapsed))s，锁在那一刻仍真实为 interrupt_in_progress），双通道均标注 operationKind=.stop；仍在途的 interrupt(mode:\"steer\") 之后独立收敛为它自己的 outcome=.submitted（约 1.6s 时），从未被合成出任何第三终态")
}

// MARK: - send() 侧未被放松（矩阵只为 stop() 定义仲裁）

func testSendStillRejectedWhileSteerInterruptInFlight() async -> Bool {
    let name = "rounds/0023: send() is still rejected(session_locked) — NOT waiting — while a REAL interrupt(mode:\"steer\") is in flight (§9.3 matrix: interrupt_in_progress × send() = reject, no arbitration defined for send)"
    let client = freshClient()
    let sessionID = "sess-steer-vs-send"
    let kernelKey = "kernel-key-steer-vs-send"
    let runID = "run-steer-vs-send-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return ["runId": runID, "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    async let interruptTask = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 40_000_000)
    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock=interrupt_in_progress while interrupt(mode:\"steer\") RPC in flight, got \(lockDuringFlight)")
    }

    do {
        _ = try await client.send(session: handle, input: Input(kind: .text, text: "should be rejected", parts: nil))
        _ = try? await interruptTask
        return fail(name, "expected send() to be rejected while interrupt(mode:\"steer\") is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        _ = try? await interruptTask
        return pass(name, "send() 在 interrupt(mode:\"steer\") 飞行期间被正确 reject(session_locked)，未进入任何等待——矩阵只为 stop() 定义仲裁，send() 侧未被本轮放松")
    } catch {
        _ = try? await interruptTask
        return fail(name, "unexpected error from send(): \(error)")
    }
}

// MARK: - REWORK（T-116 codex 对抗评审 FAIL 2）：原子交接反证

/// **FAIL 2 反证**：T-116 独立构造的交错是——`stop()` 已挂起等待 in-flight `interrupt()` 释放锁 →
/// `interrupt()` 的 defer 把锁写成 `.idle` 并 resume `stop()` 的续体 → 一个**已经在排队等待进入
/// actor** 的 `send()`/`interrupt()` job 先被调度、看到 `.idle`、抢走了锁 → `stop()` 的续体终于被
/// 调度时重新检查锁，看到的已经不是 `.idle`，只能诚实抛 `session_locked`。这条交错在旧代码里真实
/// 可达（`notifyInterruptLockReleaseWaiters` 先写 `.idle` 再唤醒，两步之间没有原子性保证），但窗口
/// 本身只有微秒级（`interrupt()` 那段不含 `await` 的同步收尾代码的真实执行时长），无法用真实调度时序
/// 可靠、确定性地命中——这正是为什么现有的
/// `testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted` 测的只是双方竞争
/// （interrupt 与 stop），从未引入过第三个 handoff contender，测不出这条漏洞（T-116 原话："现有测试
/// 只有双方竞争，没有第三个 handoff contender"）。
///
/// **本测试怎么确定性地构造这条窗口**：用 `testSupportSetInterruptPreHandoffBlockingDelay` 这个
/// test-only 钩子，让 `interrupt()` 的 `defer` 在真正运行原子交接逻辑之前先做一段**真阻塞**
/// （`Thread.sleep`，不是 `Task.sleep`）——这不是伪造交接逻辑本身（`performAtomicInterruptLockHandoff`
/// 一个 `await` 都没有，真实生产代码路径逐字节执行，交接怎么判定、锁写成什么值，全部是真实代码在真实
/// 决定），只是把这段原本微秒级、无法可靠命中的窗口人为拉宽到 200ms，使得"第三方 job 在交接运行前就
/// 已经排队等待进入 actor"这个场景可以被确定性构造，而不必赌运气。第三方是一次真实的第二个 `send()`
/// 调用——若它能观察到 `.idle` 并抢到锁，会真实驱动它自己的 `sessions.send` RPC（刻意 stub 成悬置
/// 300ms 才返回，这样即使它"赢了"，`stop()` 随后的重新检查也一定会撞见一个明确非 idle 的锁状态，不
/// 会因为它凑巧已经跑完而被掩盖成假阴性）。
///
/// **反证记录（本轮）**：临时把 `performAtomicInterruptLockHandoff` 还原成旧版"先写 idle、再唤醒"
/// 两步式实现后单独重跑本测试，红：`stop()` 被 `session_locked` 拒绝、第三方 `send()` 成功偷到锁
/// （`sessions.send#2` 被真实调用）；恢复原子交接实现后重跑，绿：见下方断言。完整命令与产物见
/// `rounds/0023/evidence/`。
func testConcurrentSendCannotStealLockDuringAtomicInterruptToStopHandoff() async -> Bool {
    let name = "rounds/0023 REWORK FAIL2: interrupt()->stop() 的原子交接必须让一个在交接运行前就已排队等待进入 actor 的第三方 send() 永远无法观察到 idle、偷走本该属于等待中 stop() 的锁"
    let client = freshClient()
    let sessionID = "sess-fail2-atomic-handoff"
    let kernelKey = "kernel-key-fail2-atomic-handoff"
    let runID = "run-fail2-atomic-handoff-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    let sendCallCounter = RPCCallCounter()

    await client.testSupportStubRPC(method: "sessions.send") { _ in
        sendCallCounter.count += 1
        let n = sendCallCounter.count
        await callLog.record("sessions.send#\(n)")
        if n == 1 {
            return ["runId": runID, "status": "started", "messageSeq": 1] as JSONObject
        } else {
            // 第三方 send() 若真的偷到了锁会走到这里——刻意让它悬置 300ms 才返回，确保 stop() 随后
            // 的重新检查（若发生）撞见的是明确的 `send_pending`，不是一个凑巧已经跑完、被掩盖成假
            // 阴性的空窗。
            try? await Task.sleep(nanoseconds: 300_000_000)
            return ["runId": "run-stolen-by-third-contender", "status": "started", "messageSeq": 2] as JSONObject
        }
    }
    await client.testSupportStubRPC(method: "chat.send") { _ in
        await callLog.record("chat.send")
        try? await Task.sleep(nanoseconds: 100_000_000) // RPC 在 t≈100ms 时返回
        return ["runId": runID, "status": "queued"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }

    // 把 interrupt() 那段本来只有微秒级的"RPC 已返回、原子交接尚未运行"窗口人为拉宽到 200ms——见本
    // 函数文档注释"本测试怎么确定性地构造这条窗口"一节。
    await client.testSupportSetInterruptPreHandoffBlockingDelay(nanoseconds: 200_000_000)

    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    guard (try? await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))) != nil else {
        return fail(name, "test setup failed: send() unexpectedly threw")
    }

    async let interruptTask = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 30_000_000) // t≈30ms
    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock=interrupt_in_progress while interrupt(mode:\"steer\") RPC in flight, got \(lockDuringFlight)")
    }

    let stopBox = InterruptRaceBox<Result<StopResultPayload, Error>>()
    let stopTask = Task<Void, Never> {
        do {
            let result = try await client.stop(session: handle)
            await stopBox.report(.success(result))
        } catch {
            await stopBox.report(.failure(error))
        }
    }
    try? await Task.sleep(nanoseconds: 40_000_000) // 累计 t≈70ms —— chat.send 的 100ms 窗口还没到期
    guard await stopBox.hasReported == false else {
        _ = try? await interruptTask
        return fail(name, "stop() 在 chat.send 的 100ms 窗口结束前就已经报告结果——测试的时序前提不成立，不构成有效反证")
    }

    // chat.send 在 t≈100ms 返回；interrupt() 的 defer 随后真阻塞 200ms（t≈100..300ms）才运行原子
    // 交接。在 t≈130ms（早于 t=300ms 交接时刻、留足 170ms 余量）发起第三方 send()——它试图进入 actor
    // 的这次尝试，此刻 actor 确实正忙（阻塞在 Thread.sleep 里，不是挂起），因此保证被排队等待，不会
    // 立即以"锁仍是 interrupt_in_progress"被正确拒绝掉——这正是本反证要构造的"已排队的第三方 job"。
    try? await Task.sleep(nanoseconds: 60_000_000) // 累计 t≈130ms
    let thirdContenderBox = InterruptRaceBox<Result<SendResultPayload, Error>>()
    let thirdContenderTask = Task<Void, Never> {
        do {
            let result = try await client.send(session: handle, input: Input(kind: .text, text: "steal attempt", parts: nil))
            await thirdContenderBox.report(.success(result))
        } catch {
            await thirdContenderBox.report(.failure(error))
        }
    }

    guard let interruptResult = try? await interruptTask else {
        return fail(name, "interrupt(mode:\"steer\") unexpectedly threw")
    }
    guard interruptResult.outcome == .submitted else {
        return fail(name, "expected interrupt(mode:\"steer\") outcome=.submitted (原子交接是纯 actor 内部信号，不应该影响 interrupt() 自己的终态判定), got \(interruptResult.outcome)")
    }

    let stopOutcome = await stopBox.wait()
    switch stopOutcome {
    case .success(let stopResult):
        guard stopResult.outcome == .succeeded else {
            return fail(name, "expected stop() outcome=.succeeded once it received the atomic handoff, got \(stopResult.outcome)")
        }
    case .failure(let error):
        return fail(name, "FAIL2 REGRESSION: stop()（本该收到原子交接、直接持有锁）被拒绝：\(error)——这正是本反证要防的：一个并发排队的 send() 在交接窗口内偷走了本该属于它的锁")
    }

    let thirdContenderOutcome = await thirdContenderBox.wait()
    switch thirdContenderOutcome {
    case .success:
        return fail(name, "FAIL2 REGRESSION: 第三方 send()（在交接运行前就已排队等待进入 actor）成功获取了锁（观察到了 idle）——它偷走了本该属于等待中 stop() 的原子交接")
    case .failure(let error):
        // session_locked：send 在 stop 仍持锁时跑到了锁检查。
        // protocolMismatch(unknown session)：handoff 之后 actor 邮箱 FIFO，stop 先跑完
        // abort+delete，send 再进——Actions 32474519871 的形状。两者都不是偷锁；
        // 偷锁的证据是下面 sessions.send#2 被 dispatch。
        let didNotSteal: Bool
        if case KernelClientError.rpcRejected(let code, _) = error, code == "session_locked" {
            didNotSteal = true
        } else if case KernelClientError.protocolMismatch(let message) = error,
                  message.contains("unknown session") {
            didNotSteal = true
        } else {
            didNotSteal = false
        }
        guard didNotSteal else {
            return fail(name, "expected 第三方 send() 被 session_locked 拒绝或因 stop 已拆掉会话而 unknown session, got \(error)")
        }
    }

    stopTask.cancel() // 已经跑完；习惯性收尾。
    thirdContenderTask.cancel() // 已经跑完；习惯性收尾。

    let order = await callLog.entries
    guard !order.contains("sessions.send#2") else {
        return fail(name, "FAIL2 REGRESSION: 第三方 send() 的 sessions.send RPC 被真实 dispatch 了（\(order)）——正确行为是在锁检查阶段就同步拒绝，从未到达 RPC 派发这一步")
    }

    return pass(name, "interrupt(mode:\"steer\") 的 RPC 在 t≈100ms 返回后，原子交接被人为阻塞 200ms 才运行；一个在 t≈130ms（交接运行前）就已排队等待进入 actor 的第三方 send() 全程未能观察到锁为 idle，被正确 session_locked 拒绝（未派发 sessions.send RPC，RPC 调用序=\(order)）；等待中的 stop() 收到原子交接（outcome=.succeeded），未受这个并发竞争者影响——原子交接把锁从 interrupt_in_progress 直接写成 stop_in_progress，从未经过、也从未呈现过任何可被外部观察到的 idle 状态")
}

// MARK: - 汇总入口

func runSteerTests() async -> [Bool] {
    var results: [Bool] = []
    results.append(await testInterruptSteerNoActiveRunPreRejectsSynchronouslyNoOperationId())
    results.append(await testInterruptSteerCallsChatSendWithQueueModeSteerDeliverFalseAndSucceedsAsSubmitted())
    results.append(await testInterruptSteerRpcFailureIsRejectedNotAThirdOutcome())
    results.append(await testInterruptSteerDoesNotForceDenyPendingApprovalsUnlikeCancel())
    results.append(await testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted())
    results.append(await testStopOwnTimeoutWhenArbitrationWaitExceedsBoundIsNeverAnInterruptOutcome())
    results.append(await testSendStillRejectedWhileSteerInterruptInFlight())
    results.append(await testConcurrentSendCannotStealLockDuringAtomicInterruptToStopHandoff())
    return results
}
