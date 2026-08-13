// rounds/0020：`interrupt()`（D1 §2.4）真 actor 级单测——本轮只实现 `mode:"cancel"`。
//
// 覆盖 scope-lock rounds/0020 与任务书列出的全部 9 条必须行为，逐条对应下面的测试：
//   1. 会话存活（红线）—— testInterruptCancelSucceedsSessionSurvivesAndSendWorksAfterward
//   2. 从不 dispatch sessions.delete（红线）—— 上面同一条测试直接断言调用顺序；
//      testInterruptNoActiveRunEmitsOperationCompletedMirrorWithInterruptKind /
//      testInterruptTimeoutEmitsOperationCompletedMirror /
//      testInterruptForceDeniesPendingApprovalBeforeAbort 三条各自独立复核（都 stub 了
//      sessions.delete 并记录调用，断言从未被调用）。
//   3. 强制 deny 定序 —— testInterruptForceDeniesPendingApprovalBeforeAbort /
//      testInterruptForceDenyFailureReleasesLockAndCleansPendingEntry
//   4. 按权威 abortedRunId 而非本地缓存判断是否等待 —— testInterruptUsesAuthoritativeAbortedRunIdNotLocalRunIDCache
//   5. abortedRunId==nil -> succeeded + 镜像 —— testInterruptNoActiveRunEmitsOperationCompletedMirrorWithInterruptKind
//   6. 超时 -> timed_out + 镜像 —— testInterruptTimeoutEmitsOperationCompletedMirror
//   7. transport 关闭时如实抛错，不伪装成功 —— testInterruptTransportClosedWhileWaitingDoesNotHangAndEmitsMirror
//   8. 互斥矩阵 + 失败路径释放锁 —— testInterruptRejectedWhileSendInFlight /
//      testSendAndStopRejectedWhileInterruptInFlight /
//      testInterruptForceDenyFailureReleasesLockAndCleansPendingEntry /
//      testInterruptAbortRpcThrowReleasesLockAndEmitsRejectedMirror
//   9. 订阅屏障 —— testInterruptWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc
//   + mode 门禁（steer/abort_and_resend 显式拒绝，不静默当 cancel）——
//     testInterruptUnsupportedModeSteerRejectedNotSilentlyTreatedAsCancel /
//     testInterruptUnsupportedModeAbortAndResendRejectedNotSilentlyTreatedAsCancel
//
// 复用既有测试基础设施（`freshClient`/`testHandle`/`collectUpTo`/`CallOrderLog`/`DispatchFlag`，
// 定义均在 FrameReplayTests.swift，非 `private`，同 target 内可见），只在需要"等 transport 关闭
// 唤醒 vs 有界护栏超时，谁先报告谁赢"这个竞速形状时新写一个 `InterruptRaceBox`（`RaceBox` 在
// FrameReplayTests.swift 里被标了 `private`，文件私有不可跨文件复用；这里改用 actor 隔离而不是
// NSLock 实现同样的语义，顺带避开该文件已有的"NSLock 在 async 上下文不可用"编译警告）。
//
// `@testable import`：同 FrameReplayTests.swift（两个 target 都带 `-enable-testing`），拿到
// `interrupt()`/`testSupportSetInterruptTimeoutSeconds`/`testSupportLockState` 等 internal 符号。

import Foundation
@testable import KernelClient
import D2Generated

// MARK: - 小工具：与 FrameReplayTests.swift 的 RaceBox 同语义，但用 actor 而不是 NSLock

/// "谁先报告谁赢"的最小竞速盒子——用于"real interrupt() vs 有界护栏超时"的场景（同款用途见
/// FrameReplayTests.swift 的 `RaceBox`，那个类型是文件私有的，这里独立实现一份，用 actor 隔离
/// 代替 NSLock，语义等价：第一次 `report` 之后的调用/仍在等待的 `wait()` 都拿到同一个值）。
actor InterruptRaceBox<T> {
    private var value: T?
    private var waiter: CheckedContinuation<T, Never>?

    func report(_ v: T) {
        guard value == nil else { return }
        value = v
        if let w = waiter {
            waiter = nil
            w.resume(returning: v)
        }
    }

    func wait() async -> T {
        if let v = value { return v }
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            waiter = cont
        }
    }
}

// MARK: - Mode 门禁：steer / abort_and_resend 必须显式拒绝，不静默当 cancel 处理

func testInterruptUnsupportedModeSteerRejectedNotSilentlyTreatedAsCancel() async -> Bool {
    let name = "rounds/0020 interrupt() mode:\"steer\" rejected with unsupported_interrupt_mode, not silently treated as cancel"
    let client = freshClient()
    let sessionID = "sess-interrupt-steer"
    let kernelKey = "kernel-key-interrupt-steer"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let options = InterruptRequestMessagePayload(input: nil, mode: .steer, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "expected interrupt(mode:\"steer\") to throw unsupported_interrupt_mode")
    } catch KernelClientError.rpcRejected(let code, _) where code == "unsupported_interrupt_mode" {
        // 期望路径
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected(code:\"unsupported_interrupt_mode\"), got \(error)")
    }

    let order = await callLog.entries
    guard order.isEmpty else {
        return fail(name, "expected zero RPC dispatch for an unsupported mode (must not silently treat steer as cancel), got \(order)")
    }
    return pass(name, "mode:\"steer\" 被正确拒绝 unsupported_interrupt_mode，且全程未 dispatch 任何 RPC（未被静默当 cancel 处理）")
}

func testInterruptUnsupportedModeAbortAndResendRejectedNotSilentlyTreatedAsCancel() async -> Bool {
    let name = "rounds/0020 interrupt() mode:\"abort_and_resend\" rejected with unsupported_interrupt_mode, not silently treated as cancel"
    let client = freshClient()
    let sessionID = "sess-interrupt-abortresend"
    let kernelKey = "kernel-key-interrupt-abortresend"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let options = InterruptRequestMessagePayload(input: nil, mode: .abortAndResend, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "expected interrupt(mode:\"abort_and_resend\") to throw unsupported_interrupt_mode")
    } catch KernelClientError.rpcRejected(let code, _) where code == "unsupported_interrupt_mode" {
        // 期望路径
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected(code:\"unsupported_interrupt_mode\"), got \(error)")
    }

    let order = await callLog.entries
    guard order.isEmpty else {
        return fail(name, "expected zero RPC dispatch for an unsupported mode (must not silently treat abort_and_resend as cancel), got \(order)")
    }
    return pass(name, "mode:\"abort_and_resend\" 被正确拒绝 unsupported_interrupt_mode，且全程未 dispatch 任何 RPC")
}

// MARK: - 红线①②：会话存活 + 从不 delete

func testInterruptCancelSucceedsSessionSurvivesAndSendWorksAfterward() async -> Bool {
    let name = "RED LINE rounds/0020: interrupt(mode:\"cancel\") aborts the run but the session survives — no session_end, stream not finished, send() works afterward"
    let client = freshClient()
    let sessionID = "sess-interrupt-survive"
    let kernelKey = "kernel-key-interrupt-survive"
    let runID = "run-interrupt-survive-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        await callLog.record("sessions.send")
        return ["runId": "run-interrupt-survive-2", "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let interruptResult = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 60_000_000) // 足够 interrupt() 真实拿到 abortedRunId、进入等待
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_100_000,
        ] as JSONObject,
    ])

    guard let result = try? await interruptResult else { return fail(name, "interrupt() unexpectedly threw") }
    guard result.outcome == .succeeded else { return fail(name, "expected outcome=.succeeded, got \(result.outcome)") }
    guard result.affectedRunID == runID else { return fail(name, "expected affectedRunID=\(runID), got \(result.affectedRunID ?? "nil")") }

    let events = await collectUpTo(stream, maxCount: 5, timeoutMs: 300)
    for event in events {
        if case .sessionEnd = event {
            return fail(name, "RED LINE VIOLATED: interrupt() emitted a session_end event — got events \(events.map { $0.wireType })")
        }
    }
    guard events.contains(where: {
        if case .operationCompleted(let op) = $0 { return op.payload.outcome == .succeeded && op.payload.operationKind == .interrupt }
        return false
    }) else {
        return fail(name, "expected an operation_completed(succeeded, operationKind:.interrupt) event, got \(events.map { $0.wireType })")
    }

    // RED LINE：continuation 没被 finish——同一个 session 上还能再次 send() 成功，这是本轮存在的
    // 唯一理由（scope-lock「让用户能中止正在生成的回复，而会话继续留着」）。
    guard let sendResult = try? await client.send(session: handle, input: Input(kind: .text, text: "still alive", parts: nil)) else {
        return fail(name, "RED LINE VIOLATED: send() after a successful interrupt() failed — the session did not survive")
    }

    let finalOrder = await callLog.entries
    guard finalOrder == ["sessions.abort", "sessions.send"] else {
        return fail(name, "RED LINE VIOLATED (or ordering wrong): expected final RPC call order [sessions.abort, sessions.send] with sessions.delete NEVER dispatched, got \(finalOrder)")
    }

    return pass(name, "interrupt() 成功中止 run=\(runID)（outcome=.succeeded），全程未 dispatch sessions.delete、未发 session_end、事件流未 finish；同一 session 后续 send() 成功返回新 runId=\(sendResult.runID)")
}

// MARK: - 要求 4：是否等待由权威 abortedRunId 判断，不是本地缓存

func testInterruptUsesAuthoritativeAbortedRunIdNotLocalRunIDCache() async -> Bool {
    let name = "rounds/0020 interrupt(): whether to wait is decided by sessions.abort's own abortedRunId, not the local lastRunIDBySessionID cache"
    let client = freshClient()
    let sessionID = "sess-interrupt-cache-vs-authoritative"
    let kernelKey = "kernel-key-interrupt-cache-vs-authoritative"
    let staleRunID = "run-already-finished-naturally"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // 让 lastRunIDBySessionID 缓存一个"早已自然结束"的 runId——一条 aborted:false 的正常 lifecycle
    // 帧既会刷新这个缓存，也不会清空它（`stop()` 文档注释已经现场实证过这一点；interrupt() 复用的是
    // 同一份缓存）。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": staleRunID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "aborted": false, "stopReason": "stop"] as JSONObject,
            "ts": 1_784_872_000_000,
        ] as JSONObject,
    ])
    _ = await collectUpTo(stream, maxCount: 1, timeoutMs: 200) // 排空这条正常 turn_complete，不影响下面断言

    await client.testSupportSetInterruptTimeoutSeconds(1) // 若实现错误地等一个不存在的终态，1 秒后会超时
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        // 这次 abort 生效时该 run 早已自然结束，openclaw 诚实回报 abortedRunId:null——真实值与本地
        // 缓存的 staleRunID 不同，这正是本测试要区分的两种可能实现。
        ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let start = Date()
    guard let result = try? await client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
    ) else {
        return fail(name, "interrupt() unexpectedly threw")
    }
    let elapsed = Date().timeIntervalSince(start)

    guard result.outcome == .succeeded else {
        return fail(name, "expected outcome=.succeeded (immediate, no wait needed), got \(result.outcome) — 若实现错误地按本地缓存的 staleRunID 去等待一个永远不会到达的 aborted lifecycle 帧，这里会变成 .timedOut")
    }
    guard result.affectedRunID == nil else {
        return fail(name, "expected affectedRunID=nil (not fabricated from the stale local cache), got \(result.affectedRunID ?? "nil")")
    }
    guard elapsed < 0.5 else {
        return fail(name, "interrupt() took \(elapsed)s — too slow for a path that should need no wait at all; suggests it actually waited on the (wrong) cached runId before timing out")
    }
    return pass(name, "interrupt() 正确按 sessions.abort 的权威 abortedRunId:null 立即返回 succeeded（\(String(format: "%.3f", elapsed))s），没有被本地缓存的陈旧 runId=\(staleRunID) 误导去等待一个不存在的终态")
}

// MARK: - 要求 5/2：无 active run -> succeeded + 镜像（operationKind 正确标注为 interrupt）

func testInterruptNoActiveRunEmitsOperationCompletedMirrorWithInterruptKind() async -> Bool {
    let name = "rounds/0020 interrupt() no active run -> operation_completed(succeeded, operationKind:.interrupt) mirror, no session_end"
    let client = freshClient()
    let sessionID = "sess-interrupt-noactive"
    let kernelKey = "kernel-key-interrupt-noactive"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    guard let result = try? await client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
    ) else {
        return fail(name, "interrupt() unexpectedly threw")
    }
    guard result.outcome == .succeeded else { return fail(name, "expected Promise outcome=.succeeded, got \(result.outcome)") }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 300)
    guard events.count == 1 else {
        return fail(name, "expected exactly 1 event (operation_completed mirror only — interrupt() must NOT emit session_end), got \(events.count): \(events.map { $0.wireType })")
    }
    guard case .operationCompleted(let op) = events[0] else {
        return fail(name, "expected the only event to be .operationCompleted, got \(events[0].wireType)")
    }
    guard op.payload.operationID == result.operationID, op.payload.outcome == .succeeded else {
        return fail(name, "operationCompleted must mirror Promise: got id=\(op.payload.operationID) outcome=\(op.payload.outcome), Promise id=\(result.operationID)")
    }
    guard op.payload.operationKind == .interrupt else {
        return fail(name, "expected operationKind=.interrupt (not .stop) — this mirror was triggered by interrupt(), not stop(), got \(op.payload.operationKind)")
    }
    let order = await callLog.entries
    guard order == ["sessions.abort"] else {
        return fail(name, "RED LINE: expected only sessions.abort to be dispatched, sessions.delete must never be called, got \(order)")
    }
    return pass(name, "operationId=\(result.operationID) 双通道 outcome 均为 succeeded，operationKind 正确标注为 interrupt（不是 stop），没有紧跟 session_end（红线：会话存活），sessions.delete 从未被调用")
}

// MARK: - 要求 6/2：超时 -> timed_out + 镜像

func testInterruptTimeoutEmitsOperationCompletedMirror() async -> Bool {
    let name = "rounds/0020 interrupt() waiting for aborted-run terminal times out -> operation_completed(timed_out) mirror, no session_end"
    let client = freshClient()
    let sessionID = "sess-interrupt-timeout"
    let kernelKey = "kernel-key-interrupt-timeout"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportSetInterruptTimeoutSeconds(1)
    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        // 真实存在 active run 需要等待，但本测试故意不喂任何 aborted lifecycle 帧——模拟"该 run 的
        // 终态帧因为某种原因一直没有到达"。
        return ["ok": true, "abortedRunId": "run-interrupt-timeout-1", "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    guard let result = try? await client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
    ) else {
        return fail(name, "interrupt() unexpectedly threw")
    }
    guard result.outcome == .timedOut else { return fail(name, "expected Promise outcome=.timedOut, got \(result.outcome)") }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 500)
    guard events.count == 1 else {
        return fail(name, "expected exactly 1 event (operation_completed(timed_out) mirror only — no session_end), got \(events.count): \(events.map { $0.wireType })")
    }
    guard case .operationCompleted(let op) = events[0], op.payload.outcome == .timedOut, op.payload.operationID == result.operationID else {
        return fail(name, "expected operation_completed(timed_out) mirroring Promise operationId=\(result.operationID)")
    }
    guard op.payload.operationKind == .interrupt else {
        return fail(name, "expected operationKind=.interrupt, got \(op.payload.operationKind)")
    }
    let order = await callLog.entries
    guard order == ["sessions.abort"] else {
        return fail(name, "RED LINE: sessions.delete must never be dispatched by interrupt(), got \(order)")
    }
    let lockAfter = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfter == "idle" else { return fail(name, "expected lock released to idle after timeout, got \(lockAfter)") }
    let pendingAfter = await client.testSupportHasPendingStop(sessionID: sessionID)
    guard !pendingAfter else { return fail(name, "expected pendingStop entry to be cleaned up after timeout") }

    return pass(name, "超时路径 operationId=\(result.operationID) Promise 与 Event 均报 timed_out，operationKind=interrupt，未发 session_end，sessions.delete 从未被调用，锁与 pendingStop 均已清理")
}

// MARK: - 要求 7：transport 在等待窗口内关闭——如实抛错，不伪装成功

func testInterruptTransportClosedWhileWaitingDoesNotHangAndEmitsMirror() async -> Bool {
    let name = "rounds/0020 interrupt(): transport closes while awaiting aborted-run terminal -> no permanent hang, throws honestly (does not fake success), operation_completed(aborted_effect_unknown) mirror + lock/pendingStop cleaned"
    let client = freshClient()
    let sessionID = "sess-interrupt-transport-closed"
    let kernelKey = "kernel-key-interrupt-transport-closed"
    let runID = "run-interrupt-transport-closed-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    // 生产默认超时（5 秒）——刻意不缩短，用来证明 interrupt() 是被 transport-close 路径主动唤醒的，
    // 不是靠超时兜底"侥幸"返回（同 stop() 既有测试的既定手法）。
    await client.testSupportSetInterruptTimeoutSeconds(5)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    enum RaceResult {
        case completed(Result<InterruptResultPayload, Error>)
        case timedOut
    }
    let box = InterruptRaceBox<RaceResult>()

    // Task A：真实驱动 interrupt()——若实现有 NOTE-1 那类 bug，这个 task 会在 transport 关闭后
    // 永久卡住，从此再也不会调用 box.report(...)，永远是孤儿 task，但不阻塞下面 box.wait()。
    Task {
        do {
            let result = try await client.interrupt(
                session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
            )
            await box.report(.completed(.success(result)))
        } catch {
            await box.report(.completed(.failure(error)))
        }
    }
    // Task B：40ms 后触发 transport 关闭。
    Task {
        try? await Task.sleep(nanoseconds: 40_000_000)
        await client.testSupportSimulateTransportClosed()
    }
    // Task C：2 秒有界护栏（远小于 5 秒生产超时）——若 Task A 永久挂起，由这个 task 兜底让
    // box.wait() 有限时间内返回，而不是把测试也一起拖死。
    Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await box.report(.timedOut)
    }

    let raceResult = await box.wait()
    switch raceResult {
    case .timedOut:
        return fail(name, "interrupt() 在 transport 关闭后 2 秒内仍未返回/抛错——永久挂起复现")
    case .completed(.success(let result)):
        return fail(name, "expected interrupt() to throw a transport error after transport closed mid-wait, got a result instead (outcome=\(result.outcome)) — faking success is exactly the historical bug class this round must not reintroduce")
    case .completed(.failure(let error)):
        guard case KernelClientError.transport = error else {
            return fail(name, "expected KernelClientError.transport, got \(error)")
        }
    }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 500)
    guard events.count == 2 else {
        return fail(name, "expected 2 events (operation_completed(aborted_effect_unknown) mirror + session_end(transport_closed) — the latter comes from the pre-existing whole-transport-died path shared by every session, unrelated to interrupt()'s own red line), got \(events.count)")
    }
    guard case .operationCompleted(let op) = events[0], op.payload.outcome == .abortedEffectUnknown, op.payload.affectedRunID == runID else {
        return fail(name, "expected first event operation_completed(aborted_effect_unknown) affectedRunID=\(runID), got \(events[0].wireType)")
    }
    guard op.payload.operationKind == .interrupt else {
        return fail(name, "expected operationKind=.interrupt, got \(op.payload.operationKind)")
    }
    guard case .sessionEnd(let end) = events[1], end.payload.reason == .transportClosed else {
        return fail(name, "expected second event sessionEnd(reason:.transportClosed)")
    }

    let hasPendingStopAfter = await client.testSupportHasPendingStop(sessionID: sessionID)
    guard !hasPendingStopAfter else { return fail(name, "expected pendingStop to be cleaned up after transport-closed cleanup") }

    return pass(name, "transport 在等待窗口内关闭：interrupt() 未永久挂起，如实抛出 transport 错误（未伪装成功），operation_completed(aborted_effect_unknown, operationKind:interrupt) 镜像先于 session_end(transport_closed) 发出（后者是既有的整链路 transport 关闭机制，与本轮红线无关），pendingStop 清理干净")
}

// MARK: - 要求 8：互斥矩阵

func testInterruptRejectedWhileSendInFlight() async -> Bool {
    let name = "rounds/0020 mutual exclusion: interrupt() rejected with session_locked while a REAL send() is in flight"
    let client = freshClient()
    let sessionID = "sess-interrupt-vs-send"
    let kernelKey = "kernel-key-interrupt-vs-send"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return ["runId": "run-x", "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let sendTask = client.send(session: handle, input: Input(kind: .text, text: "x", parts: nil))
    try? await Task.sleep(nanoseconds: 40_000_000)

    do {
        _ = try await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
        _ = try? await sendTask
        return fail(name, "expected interrupt() to be rejected while send() is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        _ = try? await sendTask
        return pass(name, "interrupt() 在真实 send() 飞行期间被正确 reject(session_locked)")
    } catch {
        _ = try? await sendTask
        return fail(name, "unexpected error \(error)")
    }
}

func testSendAndStopRejectedWhileInterruptInFlight() async -> Bool {
    let name = "rounds/0020 mutual exclusion: send() and stop() are both rejected with session_locked while a REAL interrupt() is in flight"
    let client = freshClient()
    let sessionID = "sess-send-stop-vs-interrupt"
    let kernelKey = "kernel-key-send-stop-vs-interrupt"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let interruptTask = client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
    try? await Task.sleep(nanoseconds: 40_000_000)

    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "interrupt_in_progress" else {
        _ = try? await interruptTask
        return fail(name, "expected lock=interrupt_in_progress while interrupt() RPC in flight, got \(lockDuringFlight) — 说明锁没有被真实获取")
    }

    do {
        _ = try await client.send(session: handle, input: Input(kind: .text, text: "x", parts: nil))
        _ = try? await interruptTask
        return fail(name, "expected send() to be rejected while interrupt() is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        // 期望路径
    } catch {
        _ = try? await interruptTask
        return fail(name, "unexpected error from send(): \(error)")
    }

    do {
        _ = try await client.stop(session: handle)
        _ = try? await interruptTask
        return fail(name, "expected stop() to be rejected while interrupt() is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        // 期望路径
    } catch {
        _ = try? await interruptTask
        return fail(name, "unexpected error from stop(): \(error)")
    }

    _ = try? await interruptTask
    return pass(name, "interrupt() 飞行期间锁态真实为 interrupt_in_progress；send()/stop() 均被正确 reject(session_locked)")
}

func testInterruptForceDenyFailureReleasesLockAndCleansPendingEntry() async -> Bool {
    let name = "rounds/0020 interrupt(): forceDenyPendingApprovalsBeforeStop throwing releases the lock + cleans pendingStop (and never reaches sessions.abort); second interrupt() is not falsely session_locked"
    let client = freshClient()
    let sessionID = "sess-interrupt-forcedeny-fail"
    let kernelKey = "kernel-key-interrupt-forcedeny-fail"
    let runID = "run-forcedeny-fail-1"
    let approvalID = "approval-forcedeny-fail-1"
    let toolCallID = "tool-forcedeny-fail-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
            "ts": 1_784_872_200_000,
        ] as JSONObject,
    ])
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_872_200_100, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo interrupt-forcedeny-fail"] as JSONObject,
                "createdAtMs": 1_784_872_200_100, "expiresAtMs": 1_784_874_000_100,
            ] as JSONObject,
        ] as JSONObject,
    ])
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "expected approvalID to be registered as pending-awaiting-decision before interrupt()")
    }

    let callLog = CallOrderLog()
    await client.testSupportStubRPC(method: "approval.resolve") { _ in
        await callLog.record("approval.resolve")
        throw KernelClientError.transport("simulated approval.resolve failure")
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    do {
        _ = try await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
        return fail(name, "expected interrupt() to rethrow the approval.resolve failure")
    } catch KernelClientError.transport(let message) {
        guard message.contains("simulated") else { return fail(name, "unexpected transport error message \(message)") }
    } catch {
        return fail(name, "expected KernelClientError.transport, got \(error)")
    }

    // 定序核查：force-deny 失败必须挡住 sessions.abort，不能"反正 deny 没打成也继续 abort"。
    let orderAfterFirstFailure = await callLog.entries
    guard orderAfterFirstFailure == ["approval.resolve"] else {
        return fail(name, "expected only approval.resolve to have been dispatched (sessions.abort must NOT fire when force-deny fails), got \(orderAfterFirstFailure)")
    }

    let lockAfterFailure = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterFailure == "idle" else {
        return fail(name, "expected lock released to idle after forceDeny failure, got \(lockAfterFailure) — 锁永久卡死的那类历史 bug 复现")
    }
    guard await client.testSupportHasPendingStop(sessionID: sessionID) == false else {
        return fail(name, "expected pendingStop to be cleaned up after forceDeny failure")
    }

    // 关键复现（同 stop() 既有测试的既定手法）：第二次 interrupt() 不应该被 session_locked 拒绝
    // ——它应该照样命中同一个失败的 approval.resolve stub，再次抛出同样的错误，证明锁真的被释放了
    // （不是被绕过）。
    do {
        _ = try await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
        return fail(name, "expected second interrupt() to also throw the stubbed approval.resolve failure")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        return fail(name, "second interrupt() incorrectly rejected with session_locked — 锁没有被正确释放，复现了历史上那类永久锁死缺陷")
    } catch KernelClientError.transport {
        return pass(name, "第一次 interrupt() 因 approval.resolve 失败而抛错（sessions.abort 从未被调用），锁正确释放为 idle + pendingStop 清理；第二次 interrupt() 正常再次尝试（而不是被 session_locked 挡住）")
    } catch {
        return fail(name, "unexpected error on second interrupt(): \(error)")
    }
}

func testInterruptAbortRpcThrowReleasesLockAndEmitsRejectedMirror() async -> Bool {
    let name = "rounds/0020 interrupt(): sessions.abort throws -> lock released + pendingStop cleaned + operation_completed(rejected, operationKind:.interrupt) mirror; second interrupt() not falsely session_locked"
    let client = freshClient()
    let sessionID = "sess-interrupt-abort-throws"
    let kernelKey = "kernel-key-interrupt-abort-throws"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        throw KernelClientError.transport("simulated: kernel client not connected")
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    do {
        _ = try await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
        return fail(name, "expected interrupt() to rethrow the abort RPC error")
    } catch KernelClientError.transport(let message) {
        guard message.contains("simulated") else { return fail(name, "unexpected transport error message \(message)") }
    } catch {
        return fail(name, "expected KernelClientError.transport, got \(error)")
    }

    let lockAfterFailure = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterFailure == "idle" else {
        return fail(name, "expected lock released to idle after abort throw, got \(lockAfterFailure) — 修前(stop()同类)锁会永久卡在 in-progress")
    }
    guard await client.testSupportHasPendingStop(sessionID: sessionID) == false else {
        return fail(name, "expected pendingStop to be cleaned up after abort throw")
    }

    let events = await collectUpTo(stream, maxCount: 1, timeoutMs: 200)
    guard events.count == 1, case .operationCompleted(let op) = events[0], op.payload.outcome == .rejected else {
        return fail(name, "expected operation_completed(rejected) mirror after abort throw, got \(events.count) events")
    }
    guard op.payload.operationKind == .interrupt else {
        return fail(name, "expected operationKind=.interrupt on the rejected mirror, got \(op.payload.operationKind)")
    }

    // 关键复现：第二次 interrupt() 不应该被 session_locked 拒绝——它应该照样命中同一个 stub，再次
    // 抛出同样的 transport 错误，证明锁真的被释放了。
    do {
        _ = try await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
        return fail(name, "expected second interrupt() to also throw the stubbed transport error")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        return fail(name, "second interrupt() incorrectly rejected with session_locked — 锁没有被正确释放")
    } catch KernelClientError.transport {
        return pass(name, "第一次 interrupt() 抛错后锁正确释放为 idle + pendingStop 清理 + operation_completed(rejected, operationKind:interrupt) 镜像已发出；第二次 interrupt() 正常再次尝试（而不是被 session_locked 挡住）")
    } catch {
        return fail(name, "unexpected error on second interrupt(): \(error)")
    }
}

// MARK: - 要求 3：强制 deny 定序（+ 顺带复核红线②：sessions.delete 从未出现）

func testInterruptForceDeniesPendingApprovalBeforeAbort() async -> Bool {
    let name = "rounds/0020 (D1 §6.2) interrupt() force-denies pending approval BEFORE sessions.abort; sessions.delete never dispatched; TurnCompleteEvent.forceResolvedApprovals lists it; no session_end"
    let client = freshClient()
    let sessionID = "sess-interrupt-force-deny"
    let kernelKey = "kernel-key-interrupt-force-deny"
    let runID = "run-interrupt-force-deny-1"
    let approvalID = "approval-interrupt-force-deny-1"
    let toolCallID = "tool-interrupt-force-deny-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
            "ts": 1_784_872_300_000,
        ] as JSONObject,
    ])
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_872_300_100, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo interrupt-force-deny-me"] as JSONObject,
                "createdAtMs": 1_784_872_300_100, "expiresAtMs": 1_784_874_100_100,
            ] as JSONObject,
        ] as JSONObject,
    ])
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "expected approvalID to be registered as pending-awaiting-decision after the approvalRequest join")
    }

    await client.testSupportStubRPC(method: "approval.resolve") { params in
        await callLog.record("approval.resolve")
        guard (params["id"] as? String) == approvalID, (params["decision"] as? String) == "deny" else {
            throw KernelClientError.protocolMismatch("unexpected approval.resolve params: \(params)")
        }
        return ["applied": true, "approval": ["id": approvalID, "status": "denied", "decision": "deny", "reason": "user"] as JSONObject] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let interruptResult = client.interrupt(
        session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil)
    )
    try? await Task.sleep(nanoseconds: 60_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_300_500,
        ] as JSONObject,
    ])

    guard let result = try? await interruptResult else { return fail(name, "interrupt() unexpectedly threw") }
    guard result.outcome == .succeeded else { return fail(name, "expected Promise outcome=.succeeded, got \(result.outcome)") }

    let order = await callLog.entries
    guard order == ["approval.resolve", "sessions.abort"] else {
        return fail(name, "expected RPC call order [approval.resolve, sessions.abort] with sessions.delete NEVER dispatched (RED LINE), got \(order)")
    }

    let events = await collectUpTo(stream, maxCount: 4)
    guard events.count == 3 else {
        return fail(name, "expected 3 events (approvalRequest + operation_completed + turn_complete — NO session_end), got \(events.count): \(events.map { $0.wireType })")
    }
    guard case .approvalRequest(let approvalEvent) = events[0], approvalEvent.payload.reqID == approvalID else {
        return fail(name, "expected first event approvalRequest(reqID=\(approvalID))")
    }
    guard case .operationCompleted(let op) = events[1], op.payload.outcome == .succeeded, op.payload.operationKind == .interrupt else {
        return fail(name, "expected second event operation_completed(succeeded, operationKind:.interrupt)")
    }
    guard case .turnComplete(let turn) = events[2], turn.payload.stopReason == .cancelled else {
        return fail(name, "expected third event turn_complete(cancelled)")
    }
    guard let forceResolved = turn.payload.forceResolvedApprovals, forceResolved == [approvalID] else {
        return fail(name, "expected turn_complete.forceResolvedApprovals == [\(approvalID)], got \(turn.payload.forceResolvedApprovals.map { "\($0)" } ?? "nil")")
    }

    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) == false else {
        return fail(name, "expected approvalID to no longer be pending-awaiting-decision after interrupt() force-denied it")
    }

    return pass(name, "approval.resolve 先于 sessions.abort 被调用（调用顺序=\(order)，sessions.delete 全程未出现），TurnCompleteEvent.forceResolvedApprovals=[\(approvalID)]，会话未终结（无 session_end）")
}

// MARK: - 要求 9：订阅屏障

func testInterruptWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc() async -> Bool {
    let name = "rounds/0020 subscription barrier also covers interrupt(): interrupt() does not dispatch sessions.abort before subscribe()'s sessions.messages.subscribe has been dispatched"
    let client = freshClient()
    let sessionID = "sess-interrupt-barrier-1"
    let kernelKey = "kernel-key-interrupt-barrier-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportSetSubscribeDispatchDelay(nanoseconds: 200_000_000)
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        ["subscribed": true, "key": kernelKey] as JSONObject
    }
    let abortDispatchFlag = DispatchFlag()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await abortDispatchFlag.markDispatched()
        return ["status": "no-active-run"] as JSONObject // abortedRunId 缺失 -> "无 active run" 分支，interrupt() 不需要额外驱动终态帧就能返回
    }

    _ = await client.subscribe(session: handle) // 立即返回（D1 契约），背景 Task 因人为延迟 200ms 还未真正 dispatch 它的 RPC
    let interruptTask = Task<Void, Never> {
        _ = try? await client.interrupt(session: handle, options: InterruptRequestMessagePayload(input: nil, mode: .cancel, runID: nil))
    }

    // 延迟窗口前半段（100ms < 200ms）：subscribe 的 RPC 此刻应该仍未 dispatch，interrupt() 应该仍被
    // 屏障拦住，尚未 dispatch 它自己的 RPC。
    try? await Task.sleep(nanoseconds: 100_000_000)
    guard await abortDispatchFlag.dispatched == false else {
        return fail(name, "interrupt() 的底层 sessions.abort RPC 在 subscribe() 的 RPC dispatch 完成之前（人为延迟窗口内，t=100ms<200ms）就已经发出——屏障未生效")
    }

    // 延迟窗口彻底过去 + 150ms 余量：interrupt() 应该已经被放行，完成了它自己的 RPC dispatch。
    try? await Task.sleep(nanoseconds: 250_000_000)
    guard await abortDispatchFlag.dispatched else {
        return fail(name, "等 subscribe RPC dispatch 完成（200ms）后又等了 250ms，interrupt() 仍未 dispatch 它自己的 sessions.abort RPC——屏障是否卡死、或漏放行？")
    }
    await interruptTask.value
    return pass(name, "interrupt() 的底层 sessions.abort RPC 严格晚于 subscribe() 的底层 sessions.messages.subscribe RPC dispatch（人为 200ms 延迟窗口内未提前发出，窗口后确实发出）——send()/stop() 共享的屏障对 interrupt() 同样生效")
}

// MARK: - 汇总入口

func runInterruptTests() async -> [Bool] {
    var results: [Bool] = []
    results.append(await testInterruptUnsupportedModeSteerRejectedNotSilentlyTreatedAsCancel())
    results.append(await testInterruptUnsupportedModeAbortAndResendRejectedNotSilentlyTreatedAsCancel())
    results.append(await testInterruptCancelSucceedsSessionSurvivesAndSendWorksAfterward())
    results.append(await testInterruptUsesAuthoritativeAbortedRunIdNotLocalRunIDCache())
    results.append(await testInterruptNoActiveRunEmitsOperationCompletedMirrorWithInterruptKind())
    results.append(await testInterruptTimeoutEmitsOperationCompletedMirror())
    results.append(await testInterruptTransportClosedWhileWaitingDoesNotHangAndEmitsMirror())
    results.append(await testInterruptRejectedWhileSendInFlight())
    results.append(await testSendAndStopRejectedWhileInterruptInFlight())
    results.append(await testInterruptForceDenyFailureReleasesLockAndCleansPendingEntry())
    results.append(await testInterruptAbortRpcThrowReleasesLockAndEmitsRejectedMirror())
    results.append(await testInterruptForceDeniesPendingApprovalBeforeAbort())
    results.append(await testInterruptWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc())
    return results
}
