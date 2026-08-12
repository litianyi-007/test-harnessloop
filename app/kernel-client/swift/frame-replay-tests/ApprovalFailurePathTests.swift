// rounds/0016：exec 审批 FSM 的**失败路径 / 超时路径 / 持久化状态**——★审查闸 T-096 判 REWORK
// 的四条边界失败态，各配一条破坏性反证。
//
// rounds/0015 的主判据（审批放行/拒绝端到端）已达成并 live 验证；T-096 指出的是**主路径之外**的
// 四条边界，全都是"出错时会静默变成看起来正常"的那一类：
//
//   ① 溢出 deny 的成功判据 —— 必须是 `applied:true + status:denied`；三种失败响应（RPC 失败 /
//      `applied:false` / 终态非 denied）各须被如实报错，**不可吞掉、不可提前宣称已自动拒绝**。
//   ② 强制 deny 失败后的持久状态 —— 显式持久化 `FORCE_DENY_PENDING_KERNEL_ACK`，此后**只允许
//      幂等 deny 重试**（人工 allow 必须被拒）。
//   ③ `approval.resolve` 的有界等待 —— 到期必须结束 in-flight；**权威 timeout terminal 到达时
//      也必须结束对应 in-flight**，不得永久占位。
//   ④ active terminal 后的 UI 同步 —— 必须**先清除旧卡片、再呈现提升项**（顺序在事件流上可观察）。
//
// **四条反证各自的"拆除点"**（把它改回修前形态，对应测试必然变红——红检查的逐字输出见交回报告）：
//   反证① —— `performQueueOverflowDeny` 里 `guard applied == true` / `guard approvalStatus ==
//             "denied"` 这两道判据，以及 `emitApprovalBufferResolved(reason:.queueOverflow)` 的
//             位置（修前它在 `emitApprovalRequestIfPossible` 里、**先于** RPC 发出）。
//   反证② —— `respondApproval()` 里"关卡 2b"那道 `guard decision.outcome == .deny`。
//   反证③ —— `sendApprovalResolveBounded`（换回裸 `request(method:"approval.resolve")`），以及
//             `handleApprovalTerminalSignal` 开头的 `endApprovalResolveOnAuthoritativeTerminal`。
//   反证④ —— `handleApprovalTerminalSignal` 里那条 `makeApprovalTimeoutErrorEvent` 的产出，
//             以及 `SessionStore.handle` 的 `.approvalRequest` 分支里"先 removeAll 再 append"
//             那两行（修前是无条件 `append`）。

import Foundation
@testable import KernelClient
@testable import AgentShellCore
import D2Generated

// MARK: - 小工具

/// 一个**永不返回**的 `approval.resolve` 桩——复刻"网关还连着、但这条 RPC 的应答永远不来"这个
/// 真实故障形态（服务端 handler 卡住 / 响应帧在中间环节丢失）。反证③ 的两个子场景都靠它：
/// 有界等待到期、以及权威 terminal 结束在途，**都必须在这个桩永不返回的前提下发生**。
actor NeverRespondingResolveGate {
    private(set) var callCount = 0
    func record() { callCount += 1 }
    /// 永久挂起：拿到的 continuation 谁都不会 resume。
    ///
    /// **刻意用 `withUnsafeContinuation` 而不是 `withCheckedContinuation`**：后者在 continuation
    /// 被释放而从未 resume 时会往 stderr 打一条 `SWIFT TASK CONTINUATION MISUSE` ——而"永不 resume"
    /// 在这里**是测试条件本身**，不是 bug。用 checked 版本会把一条故意的条件印成看起来像运行时
    /// 缺陷的告警，污染反证证据（实测：它会插进 stdout 的 evidence 行中间）。这是本文件里唯一一处
    /// `unsafe`，且只出现在测试替身里，生产代码一处没有。
    func blockForever() async {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    }
}

/// 从事件流里挑出 evt.error，打印成可读形态——反证要求"打印实际被破坏的内容"，光有个计数印不出东西。
func describeErrorEvents(_ events: [EventMessageUnion]) -> [String] {
    events.compactMap { event in
        guard case .error(let e) = event else { return nil }
        return "evt.error(code=\(e.payload.code.rawValue), nativeCode=\(e.payload.nativeCode ?? "nil"), message=\(e.payload.message))"
    }
}

/// 溢出场景的现场：depth=1 时喂 A（active）+ B（溢出）。返回溢出的那条 reqId。
/// `resolveStub` 决定内核对**溢出 deny** 的响应形态——三种失败形态各喂一个不同的桩。
func driveQueueOverflow(
    client: OpenclawGatewayKernelClient,
    sessionID: String,
    kernelKey: String,
    runID: String,
    overflowReqID: String,
    resolveStub: @escaping @Sendable (JSONObject) async throws -> JSONObject
) async {
    await client.testSupportSetApprovalBufferDepth(0)
    await client.testSupportStubRPC(method: "approval.resolve", responder: resolveStub)
    // depth=0：第一条就是 active，第二条直接溢出。
    _ = await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: runID,
        approvalID: "\(overflowReqID)-active", toolCallID: "tool-\(overflowReqID)-active",
        commandText: "echo active"
    )
    _ = await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: runID,
        approvalID: overflowReqID, toolCallID: "tool-\(overflowReqID)",
        commandText: "echo overflow"
    )
    // 溢出 deny 是同步占槽位后派生的 Task，给它一个往返窗口。
    try? await Task.sleep(nanoseconds: 120_000_000)
}

// MARK: - 反证①：溢出 deny 的三种失败响应各须被如实报错

/// **破坏性反证①**（T-096 第 1 项）。
///
/// 修前的两个洞，本测试各自钉死：
///  - **失败被吞掉**：`performQueueOverflowDeny` 的 `catch` 只 `prettyPrint` 一行 WARN 就返回，
///    调用方一个字节都收不到；而 `applied:false`、"终态非 denied" 这两种失败形态**根本不在
///    `catch` 的覆盖范围内**（它们都是 `ok:true` 的正常返回，见 approval.ts:462-475）——修前
///    代码对这两种情况连一行日志都没有，直接当成功走过去了。
///  - **提前宣称已自动拒绝**：`approval_buffer_resolved(queue_overflow)` 修前在**派发 deny 之前**
///    就发了，壳把它渲染成"已被自动拒绝"。deny 打不成时这句话是假的。
///
/// 四个子场景（三失败 + 一成功对照）逐条断言：`queue_overflow` 事件在且仅在成功判据成立时出现。
func testQueueOverflowDenyFailuresAreReportedNotSwallowed() async -> Bool {
    let name = "rounds/0016 反证① (T-096 第1项): 溢出 deny 的三种失败响应各须如实报错，且不得提前宣称已自动拒绝"

    struct Case {
        let label: String
        let reqID: String
        let stub: @Sendable (JSONObject) async throws -> JSONObject
        let expectQueueOverflowEvent: Bool
        let expectErrorEvent: Bool
        let expectPendingKernelAck: Bool
    }

    let cases: [Case] = [
        Case(
            label: "失败形态①：RPC 抛错",
            reqID: "ovf-rpc-throw",
            stub: { _ in throw KernelClientError.rpcRejected(code: "INTERNAL", message: "boom") },
            expectQueueOverflowEvent: false, expectErrorEvent: true, expectPendingKernelAck: true
        ),
        Case(
            label: "失败形态②：applied:false（ok:true + 终态快照，不是错误码）",
            reqID: "ovf-applied-false",
            stub: { params in
                ["applied": false, "approval": [
                    "id": (params["id"] as? String) ?? "", "status": "allowed",
                    "decision": "allow-once", "reason": "user",
                ] as JSONObject] as JSONObject
            },
            // 内核已持有终态记录，再 deny 也只会再拿一次 applied:false——没有可重试的东西。
            expectQueueOverflowEvent: false, expectErrorEvent: true, expectPendingKernelAck: false
        ),
        Case(
            label: "失败形态③：applied:true 但终态不是 denied",
            reqID: "ovf-not-denied",
            stub: { params in
                ["applied": true, "approval": [
                    "id": (params["id"] as? String) ?? "", "status": "allowed",
                    "decision": "allow-once", "reason": "user",
                ] as JSONObject] as JSONObject
            },
            expectQueueOverflowEvent: false, expectErrorEvent: true, expectPendingKernelAck: true
        ),
        Case(
            label: "成功对照：applied:true + status:denied",
            reqID: "ovf-ok",
            stub: { params in
                ["applied": true, "approval": [
                    "id": (params["id"] as? String) ?? "", "status": "denied",
                    "decision": "deny", "reason": "user",
                ] as JSONObject] as JSONObject
            },
            expectQueueOverflowEvent: true, expectErrorEvent: false, expectPendingKernelAck: false
        ),
    ]

    for testCase in cases {
        let client = freshClient()
        let sessionID = "sess-\(testCase.reqID)"
        let kernelKey = "kernel-key-\(testCase.reqID)"
        let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
        let (tap, tapTask) = startFSMEventTap(stream)
        defer { tapTask.cancel() }

        await driveQueueOverflow(
            client: client, sessionID: sessionID, kernelKey: kernelKey,
            runID: "run-\(testCase.reqID)", overflowReqID: testCase.reqID, resolveStub: testCase.stub
        )

        let events = await tap.drain()
        let overflowEvents = events.compactMap { event -> String? in
            guard case .approvalBufferResolved(let e) = event, e.payload.reqID == testCase.reqID else { return nil }
            return "approval_buffer_resolved(\(e.payload.reqID),\(e.payload.reason.rawValue))"
        }
        let errorEvents = describeErrorEvents(events)
        let ack = await client.testSupportForceDenyPendingKernelAck(reqID: testCase.reqID)

        if testCase.expectQueueOverflowEvent {
            guard overflowEvents.count == 1 else {
                return fail(name, "[\(testCase.label)] 成功判据成立时应恰好产出一条 queue_overflow，实际 \(overflowEvents)"
                    + "；全部事件 = \(events.map { describeEventKindForFSMTest($0) })")
            }
        } else {
            guard overflowEvents.isEmpty else {
                return fail(name, "[\(testCase.label)] **提前宣称已自动拒绝**：deny 未被内核确认，却仍产出了 \(overflowEvents)"
                    + "；全部事件 = \(events.map { describeEventKindForFSMTest($0) })")
            }
        }
        if testCase.expectErrorEvent {
            guard errorEvents.count == 1, errorEvents[0].contains(testCase.reqID) else {
                return fail(name, "[\(testCase.label)] **失败被吞掉**：期望恰好一条如实上报本次失败的 evt.error，"
                    + "实际 \(errorEvents)；全部事件 = \(events.map { describeEventKindForFSMTest($0) })")
            }
        } else {
            guard errorEvents.isEmpty else {
                return fail(name, "[\(testCase.label)] 成功路径不该产出 evt.error，实际 \(errorEvents)")
            }
        }
        guard (ack != nil) == testCase.expectPendingKernelAck else {
            return fail(name, "[\(testCase.label)] FORCE_DENY_PENDING_KERNEL_ACK 期望 \(testCase.expectPendingKernelAck)，"
                + "实际 \(ack.map { "存在（observedFailure=\($0.observedFailure)）" } ?? "不存在")")
        }

        print("  [evidence] \(testCase.label) -> queue_overflow=\(overflowEvents)"
            + " | evt.error=\(errorEvents)"
            + " | FORCE_DENY_PENDING_KERNEL_ACK=\(ack.map { "\($0.origin)/\($0.observedFailure)" } ?? "无")")
    }

    return pass(name, "溢出 deny 的成功判据严格是 applied:true+denied；三种失败响应各产出一条如实的 evt.error 且**不**产出 queue_overflow")
}

// MARK: - 反证②：强制 deny 失败后的持久状态 + 人工 allow 必须被拒 + 幂等 deny 重试

/// **破坏性反证②**（T-096 第 2 项）。
///
/// 修前的洞：`forceDenyPendingApprovalsBeforeStop` 在"RPC 抛错"或"终态不是 denied"时直接 `throw`，
/// 而 `pendingApprovalsByReqID[reqID]` **原样留着**（那是刻意的——审批在内核侧可能仍 pending）。
/// 于是用户随后点"允许一次"会被**完整放行**：四道关卡逐条通过，一条 `approval.resolve(allow-once)`
/// 就发出去了——一次已经决定拒绝、只是没打成的审批被人工翻成允许，命令真的会执行。
///
/// 三段断言：
///  1. stop() 的强制 deny 失败后，`FORCE_DENY_PENDING_KERNEL_ACK` **确实存在**且带着真实失败形态；
///  2. 此后人工 `allow-once` **被同步拒绝**，且**一条 RPC 都没发出去**（发出去就晚了，不可逆）；
///  3. 人工 `deny` 重试**被放行**，成功后持久态解除。
func testForceDenyFailureBlocksManualAllowAndAllowsIdempotentDenyRetry() async -> Bool {
    let name = "rounds/0016 反证② (T-096 第2项): 强制 deny 失败 -> FORCE_DENY_PENDING_KERNEL_ACK -> 人工 allow 必须被拒、只允许幂等 deny 重试"
    let client = freshClient()
    let sessionID = "sess-force-deny-ack"
    let kernelKey = "kernel-key-force-deny-ack"
    let runID = "run-force-deny-ack"
    let approvalID = "approval-force-deny-ack"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    guard await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: runID,
        approvalID: approvalID, toolCallID: "tool-force-deny-ack", commandText: "rm -rf /tmp/force-deny-ack"
    ) else {
        return fail(name, "前置：审批未能进入 pending-awaiting-decision 态")
    }

    // ---- 第一幕：stop() 的强制 deny 撞上"内核回了 ok:true 但终态是 allowed"（失败形态③） ----
    let paramsBox = ParamsBox()
    let denyShouldFail = FlagBox()
    await denyShouldFail.set(true)
    await client.testSupportStubRPC(method: "approval.resolve") { params in
        await paramsBox.record(params)
        let id = (params["id"] as? String) ?? ""
        if await denyShouldFail.value {
            // applied:true 但终态不是 denied —— 内核采纳了调用却写下了别的终态。
            return ["applied": true, "approval": [
                "id": id, "status": "allowed", "decision": "allow-once", "reason": "user",
            ] as JSONObject] as JSONObject
        }
        return ["applied": true, "approval": [
            "id": id, "status": "denied", "decision": "deny", "reason": "user",
        ] as JSONObject] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }

    let handle = testHandleFor(sessionID, kernelKey)
    var stopError: Error?
    do {
        try await client.stop(session: handle)
    } catch {
        stopError = error
    }
    guard stopError != nil else {
        return fail(name, "强制 deny 未被内核确认时 stop() 必须抛错，实际正常返回了")
    }

    guard let ack = await client.testSupportForceDenyPendingKernelAck(reqID: approvalID) else {
        return fail(name, "**持久态缺失**：强制 deny 失败后必须显式持久化 FORCE_DENY_PENDING_KERNEL_ACK，"
            + "实际查不到该 reqId；stop() 抛的错是 \(stopError.map { "\($0)" } ?? "nil")")
    }
    guard ack.origin == "forceDenyOnStop" else {
        return fail(name, "持久态的 origin 应为 forceDenyOnStop，实际 \(ack.origin)")
    }
    let callsAfterStop = await paramsBox.calls.count

    // ---- 第二幕：人工 allow-once 必须被同步拒绝，且一条 RPC 都不发 ----
    var allowError: Error?
    do {
        try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
            outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil
        ))
    } catch {
        allowError = error
    }
    guard let allowError else {
        return fail(name, "**FORCE_DENY_PENDING_KERNEL_ACK 下的人工 allow-once 本应被拒绝，却成功返回了**"
            + "——一次已决定拒绝、只是没打成的审批被翻成了允许")
    }
    guard case ApprovalDecisionError.forceDenyPendingKernelAck(let deniedReqID, let requested, _) = allowError,
          deniedReqID == approvalID, requested == ApprovalDecisionKindElement.allowOnce.rawValue else {
        return fail(name, "人工 allow-once 应被 forceDenyPendingKernelAck 拒绝，实际抛的是 \(allowError)")
    }
    let callsAfterAllow = await paramsBox.calls.count
    guard callsAfterAllow == callsAfterStop else {
        return fail(name, "**allow 被拒时必须一条 RPC 都不发**（发出去就不可逆），实际多发了 "
            + "\(callsAfterAllow - callsAfterStop) 条：\(await paramsBox.calls)")
    }

    // ---- 第三幕：deny 重试被放行，成功后持久态解除 ----
    await denyShouldFail.set(false)
    do {
        try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
            outcome: .deny, updatedInput: nil, scope: nil, reason: nil
        ))
    } catch {
        return fail(name, "FORCE_DENY_PENDING_KERNEL_ACK 下的幂等 deny 重试本应被放行，却抛了 \(error)")
    }
    let retryCalls = await paramsBox.calls
    guard retryCalls.count == callsAfterAllow + 1,
          retryCalls[retryCalls.count - 1]["decision"] as? String == "deny",
          retryCalls[retryCalls.count - 1]["id"] as? String == approvalID else {
        return fail(name, "deny 重试应恰好多发一条 approval.resolve(deny)，实际 \(retryCalls)")
    }
    guard await client.testSupportForceDenyPendingKernelAck(reqID: approvalID) == nil else {
        return fail(name, "deny 重试拿到内核确认的 denied 终态后，持久态必须解除，实际仍在")
    }

    print("  [evidence] 强制 deny 失败（applied:true 但终态 allowed）-> FORCE_DENY_PENDING_KERNEL_ACK"
        + "（origin=\(ack.origin)，observedFailure=\(ack.observedFailure)）")
    print("  [evidence] 该态下人工 allow-once -> 同步拒绝（\(allowError)），approval.resolve 调用数未变（\(callsAfterStop) -> \(callsAfterAllow)）")
    print("  [evidence] 该态下人工 deny -> 放行、恰好多发一条 approval.resolve(deny)，内核确认 denied 后持久态解除")
    return pass(name, "强制 deny 失败后持久态存在；人工 allow 被同步拒绝且零 RPC；幂等 deny 重试被放行并在确认后解除持久态")
}

/// 一个可被测试翻转的开关（决定桩这一次该成功还是该失败）。
actor FlagBox {
    private(set) var value = false
    func set(_ newValue: Bool) { value = newValue }
}

// MARK: - 反证③：approval.resolve 的有界等待 + 权威 terminal 结束在途

/// **破坏性反证③**（T-096 第 3 项）。
///
/// 修前：三条 `approval.resolve` 路径打的都是裸 `request(method:params:)`，那是一个**无界**
/// `withCheckedThrowingContinuation`——只有"响应到达"和"transport 断开"两种唤醒源。网关还连着、
/// 但这条 RPC 永远不回应答时：调用方永久挂起、in-flight 槽位永久占位、`stop()` 的 drain 收敛条件
/// （"pending 空 **且** 无在途 resolve"）永远不成立，**整条 stop() 跟着挂死**。
///
/// 两个子场景**都在"桩永不返回"的前提下**跑（`NeverRespondingResolveGate`）：
///  A. 有界等待到期 -> `respondApproval()` 抛 `approvalResolveTimedOut`，in-flight 被结束；
///  B. 权威 timeout terminal 到达 -> 在途决议立刻被结束（不等那个永远不来的应答）。
func testApprovalResolveBoundedWaitAndAuthoritativeTerminalEndInFlight() async -> Bool {
    let name = "rounds/0016 反证③ (T-096 第3项): approval.resolve 有界等待到期 / 权威 timeout terminal 到达 —— in-flight 必须被结束，不得永久占位"

    // ---- 子场景 A：有界等待到期 ----
    do {
        let client = freshClient()
        let sessionID = "sess-bounded-wait"
        let kernelKey = "kernel-key-bounded-wait"
        let approvalID = "approval-bounded-wait"
        _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
        await client.testSupportSetApprovalResolveBoundedWaitMS(150)
        let gate = NeverRespondingResolveGate()
        await client.testSupportStubRPC(method: "approval.resolve") { _ in
            await gate.record()
            await gate.blockForever()
            return [:] as JSONObject // 永远到不了
        }
        guard await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: "run-bounded-wait",
            approvalID: approvalID, toolCallID: "tool-bounded-wait", commandText: "echo bounded"
        ) else {
            return fail(name, "[A] 前置：审批未能进入 pending-awaiting-decision 态")
        }

        let handle = testHandleFor(sessionID, kernelKey)
        let started = Date()
        var caught: Error?
        do {
            try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
                outcome: .deny, updatedInput: nil, scope: nil, reason: nil
            ))
        } catch {
            caught = error
        }
        let elapsedMS = Int(Date().timeIntervalSince(started) * 1000)
        guard let caught else {
            return fail(name, "[A] 应答永不到达时 respondApproval 必须在有界等待到期后抛错，实际正常返回了")
        }
        guard case ApprovalDecisionError.approvalResolveTimedOut(let timedOutReqID, let waitedMS) = caught,
              timedOutReqID == approvalID else {
            return fail(name, "[A] 应抛 approvalResolveTimedOut，实际 \(caught)")
        }
        let inFlight = await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID)
        guard inFlight.isEmpty else {
            return fail(name, "[A] **in-flight 永久占位**：有界等待到期后该 session 不应再有在途 resolve，实际 \(inFlight)")
        }
        let calls = await gate.callCount
        print("  [evidence][A] 桩收到 \(calls) 次 approval.resolve 且**从未返回**；"
            + "有界等待 \(waitedMS)ms 到期后 respondApproval 抛 \(caught)（实测耗时 \(elapsedMS)ms）；"
            + "in-flight 集合已清空 = \(inFlight)")
    }

    // ---- 子场景 B：权威 timeout terminal 结束在途 ----
    do {
        let client = freshClient()
        let sessionID = "sess-authoritative-terminal"
        let kernelKey = "kernel-key-authoritative-terminal"
        let approvalID = "approval-authoritative-terminal"
        _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
        // 有界等待刻意设得很长：本子场景要证明的是**terminal 自己**结束了在途，不是超时兜的底。
        await client.testSupportSetApprovalResolveBoundedWaitMS(600_000)
        let gate = NeverRespondingResolveGate()
        await client.testSupportStubRPC(method: "approval.resolve") { _ in
            await gate.record()
            await gate.blockForever()
            return [:] as JSONObject
        }
        guard await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: "run-authoritative-terminal",
            approvalID: approvalID, toolCallID: "tool-authoritative-terminal", commandText: "echo terminal"
        ) else {
            return fail(name, "[B] 前置：审批未能进入 pending-awaiting-decision 态")
        }

        let handle = testHandleFor(sessionID, kernelKey)
        let respondTask = Task { () -> Error? in
            do {
                try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
                    outcome: .deny, updatedInput: nil, scope: nil, reason: nil
                ))
                return nil
            } catch {
                return error
            }
        }
        // 等这条决议真的进入在途态（槽位可见），再喂 terminal。
        var inFlightBefore: [String] = []
        for _ in 0..<200 {
            inFlightBefore = await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID)
            if inFlightBefore.contains(approvalID) { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard inFlightBefore.contains(approvalID) else {
            return fail(name, "[B] 前置：决议未进入在途态，实际 in-flight = \(inFlightBefore)")
        }

        await client.testSupportFeedFrame([
            "type": "event", "event": "session.approval",
            "payload": [
                "sessionKey": kernelKey, "updatedAtMs": 1_784_873_900_000, "phase": "terminal",
                "approval": [
                    "id": approvalID, "status": "expired", "reason": "timeout",
                    "resolvedAtMs": 1_784_873_900_000,
                ] as JSONObject,
            ] as JSONObject,
        ])

        let respondError = await respondTask.value
        guard let respondError else {
            return fail(name, "[B] 权威 terminal 到达后 respondApproval 必须以错误结束，实际正常返回了")
        }
        guard case ApprovalDecisionError.approvalTerminatedByKernelWhileResolving(let tReqID, let status, let reason) = respondError,
              tReqID == approvalID else {
            return fail(name, "[B] 应抛 approvalTerminatedByKernelWhileResolving，实际 \(respondError)")
        }
        let inFlightAfter = await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID)
        guard inFlightAfter.isEmpty else {
            return fail(name, "[B] **in-flight 永久占位**：权威 terminal 到达后不应再有在途 resolve，实际 \(inFlightAfter)")
        }
        let calls = await gate.callCount
        print("  [evidence][B] 桩收到 \(calls) 次 approval.resolve 且**从未返回**（有界等待设为 600000ms，不可能是它兜的底）；"
            + "喂入 session.approval(phase:terminal,status:expired,reason:timeout) 后 respondApproval 立刻以 "
            + "\(respondError) 结束；in-flight \(inFlightBefore) -> \(inFlightAfter)")
        _ = status
        _ = reason
    }

    return pass(name, "有界等待到期与权威 timeout terminal 两条路径各自结束了对应的 in-flight，槽位不再永久占位")
}

/// **反证③ 的配套回归**：`status:"allowed"` 的 terminal **不得**打断用户自己那条在途决议。
///
/// 这条测试是本轮实现过程中发现的一个**会打断 live 主链**的坑，写成回归钉死：
/// openclaw `approval.resolve` handler 的顺序是 `applyApprovalDecision(...)`（内部广播 terminal
/// 事件）**先**、`respond(true, ...)` **后**（`approval.ts:491-540`），两者同一条 WS 连接——所以
/// 用户点"允许"之后，`session.approval(phase:terminal, status:allowed)` 这一帧**先于**这次 RPC
/// 的响应到达。若把 T-096 第 3 项的"权威 timeout terminal 结束 in-flight"实现成"任何权威
/// terminal 都结束 in-flight"，这一帧就会把用户自己的决议判死：**命令实际执行了，UI 却报错**。
func testAllowedTerminalDoesNotAbortTheUsersOwnInFlightDecision() async -> Bool {
    let name = "rounds/0016 回归 (反证③ 配套): status:allowed 的 terminal 先于 RPC 响应到达时，不得打断用户自己那条在途决议"
    let client = freshClient()
    let sessionID = "sess-allowed-terminal-race"
    let kernelKey = "kernel-key-allowed-terminal-race"
    let approvalID = "approval-allowed-terminal-race"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportSetApprovalResolveBoundedWaitMS(600_000)

    let gate = ApprovalResolveGate()
    await client.testSupportStubRPC(method: "approval.resolve") { params in
        // 按住响应，模拟"terminal 广播帧已经到了、RPC 响应还没回"的真实窗口。
        await gate.wait()
        return ["applied": true, "approval": [
            "id": (params["id"] as? String) ?? "", "status": "allowed",
            "decision": "allow-once", "reason": "user",
        ] as JSONObject] as JSONObject
    }
    guard await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: "run-allowed-terminal-race",
        approvalID: approvalID, toolCallID: "tool-allowed-terminal-race", commandText: "echo APPROVAL_GATE_OK"
    ) else {
        return fail(name, "前置：审批未能进入 pending-awaiting-decision 态")
    }

    let handle = testHandleFor(sessionID, kernelKey)
    let respondTask = Task { () -> Error? in
        do {
            try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
                outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil
            ))
            return nil
        } catch {
            return error
        }
    }
    var inFlight: [String] = []
    for _ in 0..<200 {
        inFlight = await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID)
        if inFlight.contains(approvalID) { break }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    guard inFlight.contains(approvalID) else {
        return fail(name, "前置：决议未进入在途态，实际 in-flight = \(inFlight)")
    }

    // 内核的 terminal 广播先到（status:allowed，用户自己那次决议的结果）
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_873_000_000, "phase": "terminal",
            "approval": [
                "id": approvalID, "status": "allowed", "decision": "allow-once",
                "reason": "user", "resolvedAtMs": 1_784_873_000_000,
            ] as JSONObject,
        ] as JSONObject,
    ])
    // 然后 RPC 响应才回来
    await gate.open()

    if let error = await respondTask.value {
        return fail(name, "**live 主链被打断**：用户点『允许一次』本应成功，却因为先到的 terminal(allowed) 广播帧被判成 \(error)")
    }
    print("  [evidence] terminal(status:allowed) 先于 approval.resolve 响应到达（openclaw approval.ts:491-540 的真实顺序）"
        + "；respondApproval 仍正常成功返回，未被误判为 approvalTerminatedByKernelWhileResolving")
    return pass(name, "只有 status:expired 的权威 terminal 才结束在途决议；allowed/denied 的终态由这次 RPC 自己的响应负责")
}

// MARK: - 反证④：active terminal -> 先清旧卡、再呈现提升项

/// **破坏性反证④**（T-096 第 4 项）。
///
/// 修前两处各自制造同一个后果：
///  - 适配器侧：`handleApprovalTerminalSignal` 只在内部驱动 FSM，**一个字节都没传给调用方**——
///    壳根本不知道队头那张卡已经死了；
///  - 壳侧：`SessionStore.handle` 的 `.approvalRequest` 分支无条件 `append`，而
///    `SessionDetailView` 只渲染队头——于是提升上来的 #2 被挤在死卡后面，**在界面上根本不浮现**。
///
/// 本测试同时钉死两侧，并且断言**顺序在事件流上可观察**：先 `evt.error(approval_timeout)`
/// （= 清），后 `evt.approval_request(#2)`（= 呈现）。
@MainActor
func testActiveApprovalTimeoutClearsStaleCardBeforePresentingPromotedOne() async -> Bool {
    let name = "rounds/0016 反证④ (T-096 第4项): active timeout -> 先清旧卡（evt.error/approval_timeout）再呈现提升项（#2 在 UI 上浮现）"
    let client = freshClient()
    let sessionID = "sess-active-timeout-ui"
    let kernelKey = "kernel-key-active-timeout-ui"
    let runID = "run-active-timeout-ui"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let (tap, tapTask) = startFSMEventTap(stream)
    defer { tapTask.cancel() }
    await client.testSupportSetApprovalBufferDepth(2)

    for approvalID in ["ui-a", "ui-b"] {
        _ = await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: runID,
            approvalID: approvalID, toolCallID: "tool-\(approvalID)", commandText: "echo \(approvalID)"
        )
    }
    try? await Task.sleep(nanoseconds: 40_000_000)
    let phase1 = await tap.drain()
    guard phase1.count == 1, case .approvalRequest(let reqA) = phase1[0], reqA.payload.reqID == "ui-a" else {
        return fail(name, "前置：只应先呈现 ui-a，实际 \(phase1.map { describeEventKindForFSMTest($0) })")
    }
    guard await client.testSupportBufferedApprovalReqIDs(sessionID: sessionID) == ["ui-b"] else {
        return fail(name, "前置：ui-b 应在缓冲队列里")
    }

    // ---- active（ui-a）被内核判超时 ----
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_873_900_000, "phase": "terminal",
            "approval": [
                "id": "ui-a", "status": "expired", "reason": "timeout", "resolvedAtMs": 1_784_873_900_000,
            ] as JSONObject,
        ] as JSONObject,
    ])
    try? await Task.sleep(nanoseconds: 40_000_000)
    let phase2 = await tap.drain()

    // ① 事件流上"先清后呈现"的顺序必须可观察
    guard phase2.count == 2 else {
        return fail(name, "active 超时后应恰好产出两条事件（先 evt.error(approval_timeout) 再 approval_request(ui-b)），"
            + "实际 \(phase2.count) 条：\(phase2.map { describeEventKindForFSMTest($0) })")
    }
    guard case .error(let timeoutError) = phase2[0], timeoutError.payload.code == .approvalTimeout else {
        return fail(name, "**第一条必须是清旧卡的 evt.error(approval_timeout)**，实际 "
            + "\(describeEventKindForFSMTest(phase2[0]))；两条事件 = \(phase2.map { describeEventKindForFSMTest($0) })")
    }
    guard case .approvalRequest(let reqB) = phase2[1], reqB.payload.reqID == "ui-b" else {
        return fail(name, "第二条应是提升项 approval_request(ui-b)，实际 \(describeEventKindForFSMTest(phase2[1]))")
    }
    guard await client.testSupportActiveApprovalReqID(sessionID: sessionID) == "ui-b" else {
        return fail(name, "active 槽位应已提升为 ui-b")
    }

    // ② 壳侧：按事件流的**真实顺序**喂给 SessionStore，断言 UI 上真的先清后现
    let store = SessionStore(config: KernelShellConfig(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "t", configWarning: nil))
    let session = ChatSessionViewModel(handle: testHandleFor(sessionID, kernelKey), title: "t")
    store.handle(phase1[0], for: session)
    guard session.pendingApprovals.map(\.reqID) == ["ui-a"] else {
        return fail(name, "前置：壳应先显示 ui-a 的卡片，实际 \(session.pendingApprovals.map(\.reqID))")
    }
    store.handle(phase2[0], for: session)
    let afterClear = session.pendingApprovals.map(\.reqID)
    guard afterClear.isEmpty else {
        return fail(name, "**旧卡未被清除**：收到 evt.error(approval_timeout) 后卡片列表应为空，实际 \(afterClear)")
    }
    store.handle(phase2[1], for: session)
    let afterPromote = session.pendingApprovals.map(\.reqID)
    guard afterPromote == ["ui-b"] else {
        return fail(name, "**提升项未在 UI 上浮现**：应恰好只剩 ui-b 一张卡片，实际 \(afterPromote)")
    }

    // ③ 壳侧的第二道保证：即使旧卡因为任何原因还在（没收到 evt.error），提升项到达时也必须**先清后现**
    //    ——UI 只渲染队头，append 到死卡后面等于不浮现。
    let session2 = ChatSessionViewModel(handle: testHandleFor(sessionID, kernelKey), title: "t2")
    store.handle(phase1[0], for: session2)
    store.handle(phase2[1], for: session2)
    let replaced = session2.pendingApprovals.map(\.reqID)
    guard replaced == ["ui-b"] else {
        return fail(name, "**先清后呈现被破坏**：新 approval_request 到达时旧卡必须先被清掉，"
            + "队头才会是提升项；实际卡片列表 \(replaced)（队头 = \(replaced.first ?? "nil")）")
    }

    print("  [evidence] 事件流顺序：\(phase2.map { describeEventKindForFSMTest($0) })"
        + "（第一条 code=\(timeoutError.payload.code.rawValue) nativeCode=\(timeoutError.payload.nativeCode ?? "nil")）")
    print("  [evidence] 壳侧卡片：[ui-a] -收到 evt.error(approval_timeout)-> \(afterClear) -收到 approval_request(ui-b)-> \(afterPromote)")
    print("  [evidence] 第二道保证：旧卡仍在时直接投递 approval_request(ui-b) -> 卡片列表 \(replaced)（队头即提升项，不是死卡）")
    return pass(name, "active terminal 驱动 UI 先清旧卡再呈现提升项，顺序在事件流上可观察；壳侧对 approval_request 的替换语义提供第二道保证")
}

// MARK: - 队列徽标：不得显示编造的数字

/// T-096 第 4 项后半句："队列徽标应接真实缓冲计数或删除（不得显示编造的数字）。"
///
/// 本项目选**删除**（理由见 `SessionDetailView.approvalSection` 的文档注释）。这条测试钉死的是
/// 那个理由本身**在数据上成立**：缓冲中的请求从不进 `pendingApprovals`，所以任何从这个数组算出来
/// 的"排队条数"都与真实缓冲深度无关——适配器缓冲了 2 条时，壳这边能看到的数字是 0。
@MainActor
func testShellCannotDeriveBufferedApprovalCountFromItsOwnState() async -> Bool {
    let name = "rounds/0016 (T-096 第4项后半): 队列徽标不得显示编造的数字 —— 壳侧结构性拿不到真实缓冲计数"
    let client = freshClient()
    let sessionID = "sess-badge"
    let kernelKey = "kernel-key-badge"
    let runID = "run-badge"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let (tap, tapTask) = startFSMEventTap(stream)
    defer { tapTask.cancel() }
    await client.testSupportSetApprovalBufferDepth(4)

    for approvalID in ["badge-a", "badge-b", "badge-c"] {
        _ = await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: runID,
            approvalID: approvalID, toolCallID: "tool-\(approvalID)", commandText: "echo \(approvalID)"
        )
    }
    try? await Task.sleep(nanoseconds: 40_000_000)
    let realBuffered = await client.testSupportBufferedApprovalReqIDs(sessionID: sessionID)
    guard realBuffered == ["badge-b", "badge-c"] else {
        return fail(name, "前置：适配器缓冲队列应为 [badge-b, badge-c]，实际 \(realBuffered)")
    }

    let store = SessionStore(config: KernelShellConfig(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "t", configWarning: nil))
    let session = ChatSessionViewModel(handle: testHandleFor(sessionID, kernelKey), title: "t")
    for event in await tap.drain() { store.handle(event, for: session) }

    let shellVisible = session.pendingApprovals.map(\.reqID)
    let fabricatedBadgeNumber = max(0, shellVisible.count - 1)
    guard shellVisible == ["badge-a"] else {
        return fail(name, "壳侧应只看到 active 那一条，实际 \(shellVisible)")
    }
    guard fabricatedBadgeNumber != realBuffered.count else {
        return fail(name, "本测试的前提被推翻了：`pendingApprovals.count - 1` 竟然等于真实缓冲深度 "
            + "\(realBuffered.count)——若真如此，徽标就不是编造的，本测试与 SessionDetailView 的删除理由都要重写")
    }
    print("  [evidence] 适配器真实缓冲 = \(realBuffered)（\(realBuffered.count) 条）；"
        + "壳侧 pendingApprovals = \(shellVisible)；旧徽标会显示的数字 = \(fabricatedBadgeNumber) —— 与真实值不符，故删除而非"
        + "「接一个拿不到的计数」")
    return pass(name, "缓冲请求从不进入壳侧状态，`count - 1` 与真实缓冲深度无关；徽标按 T-096 的两个选项之一删除")
}

// MARK: - 注册

func runApprovalFailurePathTests() async -> [Bool] {
    var results: [Bool] = []
    results.append(await testQueueOverflowDenyFailuresAreReportedNotSwallowed())
    results.append(await testForceDenyFailureBlocksManualAllowAndAllowsIdempotentDenyRetry())
    results.append(await testApprovalResolveBoundedWaitAndAuthoritativeTerminalEndInFlight())
    results.append(await testAllowedTerminalDoesNotAbortTheUsersOwnInFlightDecision())
    results.append(await testActiveApprovalTimeoutClearsStaleCardBeforePresentingPromotedOne())
    results.append(await testShellCannotDeriveBufferedApprovalCountFromItsOwnState())
    return results
}
