// Frame-replay 单测——SG-5 rework 轮，第二次收残（对抗审 T-045 codex 确认性再审 MUST-FIX，紧接
// db489f0e 之后）。
//
// T-045 的核心判决是："13/13 PASS 不能支持接收"——现有测试大量是替代/自证场景：F1 直接强制锁态、
// 没测真实获取/释放；F4 固定同一个 run，只测 agent-first 顺序；F6 直接 seed 内部 pendingStop 状态，
// 从不调用真实 `stop()`；F8 用两次同样的 shutdown 帧代替 shutdown+transport close；没有对完整 D2
// JSON 做 encode/decode 断言。本轮重做：能用真实 `send()`/`stop()`/`subscribe()` 方法体和真实
// `testSupportFeedFrame` 事件 dispatch 入口驱动的，一律不再 seed 内部状态——`OpenclawGatewayKernelClient`
// 新增了 `testSupportStubRPC`（按 RPC method 名注册响应/抛错，不需要真实 WebSocket）使得 `send()`/
// `stop()` 本身（含它们发起的 RPC）都可以被真实调用并驱动到底。
//
// 这个项目没有 XCTest/SwiftPM test target——延续既有风格：每个测试是一个返回 `Bool`（或
// `async -> Bool`）的普通函数，`runFrameReplayTests()` 依次跑、打印每条的 PASS/FAIL，最后返回总体
// 是否全过。真正的可执行入口在 `FrameReplayTestMain.swift`。
//
// 每个测试函数的文档注释都标注了"这条断言在修前（db489f0e）会不会失败"——凡是能够直接构造出"上一轮
// 的实现会给出错误结果"的场景，都写清楚对照的旧行为。

import Foundation

// MARK: - 小工具

func fail(_ testName: String, _ reason: String) -> Bool {
    print("  [FAIL] \(testName): \(reason)")
    return false
}

func pass(_ testName: String, _ detail: String) -> Bool {
    print("  [PASS] \(testName): \(detail)")
    return true
}

/// 收集流上最多 `maxCount` 个事件，超过 `timeoutMs` 还没凑够就提前放弃——用于"验证不多不少/验证
/// 目前确实还没有事件"的场景。所有测试里的 `testSupportFeedFrame` 调用都已经在 `await` 返回前完成了
/// `continuation.yield`（AsyncThrowingStream 默认无界缓冲，yield 不阻塞），所以正常情况下这里几乎
/// 不会真的等到超时——超时只在"期望没有更多事件、且确实没有更多事件"时才会触发。
final class EventBox: @unchecked Sendable {
    var events: [EventMessageUnion] = []
}

func collectUpTo(
    _ stream: AsyncThrowingStream<EventMessageUnion, Error>,
    maxCount: Int,
    timeoutMs: UInt64 = 300
) async -> [EventMessageUnion] {
    let box = EventBox()
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            for _ in 0..<maxCount {
                let next: EventMessageUnion?
                do {
                    next = try await iterator.next()
                } catch {
                    break
                }
                guard let event = next else { break }
                box.events.append(event)
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
        }
        await group.next()
        group.cancelAll()
    }
    return box.events
}

func freshClient() -> OpenclawGatewayKernelClient {
    OpenclawGatewayKernelClient(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "dummy-test-token")
}

func testHandle(sessionID: String, kernelKey: String) -> SessionHandle {
    SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: kernelKey, sessionID: sessionID
    )
}

// MARK: - F3：per-run 单调 seq + 保留原始 ts（不用 Date()）——纯函数，未受本轮改动影响，保留回归覆盖

/// **修前（a07dc67）fail / 修后 pass**：`mapOpenclawSessionMessageToKernelEvents` 内部自己从
/// `payload["messageSeq"]` 取 seq——同一条 assistant 消息里的多个 content block（这里用真实样本
/// 形状：text + toolCall 同时出现）会拿到**同一个** `messageSeq` 值。本轮改为调用方按 runId 维护一个
/// 真正递增的计数器，通过 `nextSeq` 闭包传入。
func testSeqOrderingWithinRunAndOriginTS() -> Bool {
    let name = "F3 seq ordering + origin ts"
    let messageTimestampMs = 1_784_876_055_901
    let payload: JSONObject = [
        "sessionKey": "agent:main:dashboard:test",
        "message": [
            "role": "assistant",
            "content": [
                ["type": "text", "text": "先看看目录"],
                ["type": "toolCall", "id": "tool_abc123", "name": "exec", "arguments": ["command": "ls"] as JSONObject],
            ],
            "timestamp": messageTimestampMs,
        ] as JSONObject,
    ]
    var counter = 0
    let events = mapOpenclawSessionMessageToKernelEvents(
        payload, ourSessionID: "s1", runIDHint: "run-1",
        nextSeq: { counter += 1; return counter }
    )
    guard events.count == 2 else {
        return fail(name, "expected 2 events (text + toolCall), got \(events.count)")
    }
    let seqs: [Int] = events.map { event in
        switch event {
        case .messageDelta(let e): return e.seq
        case .toolCall(let e): return e.seq
        default: return -1
        }
    }
    guard seqs == [1, 2] else {
        return fail(name, "expected strictly increasing per-run seq [1,2], got \(seqs)")
    }
    let expectedTS = Date(timeIntervalSince1970: Double(messageTimestampMs) / 1000.0)
    for event in events {
        let ts: Date
        switch event {
        case .messageDelta(let e): ts = e.ts
        case .toolCall(let e): ts = e.ts
        default: continue
        }
        guard abs(ts.timeIntervalSince(expectedTS)) < 0.001 else {
            return fail(name, "ts \(ts) 不等于 message.timestamp 换算值 \(expectedTS)")
        }
    }
    return pass(name, "seq=\(seqs) ts 均等于 message.timestamp（非 Date()）")
}

// MARK: - F6：无 stopReason 的合法 end 不再默认 error（纯函数，回归覆盖）

func testNoStopReasonEndMapsToCompleted() -> Bool {
    let name = "F6 no-stopReason end -> completed (not error)"
    let data: JSONObject = ["phase": "end"]
    var counter = 0
    let event = mapOpenclawAgentLifecycleToTurnComplete(
        data, ourSessionID: "s1", runID: "run-1", originTS: Date(),
        cachedUsage: nil, nextSeq: { counter += 1; return counter }
    )
    guard case .turnComplete(let turnComplete) = event else {
        return fail(name, "expected .turnComplete case")
    }
    guard turnComplete.payload.stopReason == .completed else {
        return fail(name, "expected stopReason=.completed, got \(turnComplete.payload.stopReason)")
    }
    return pass(name, "stopReason=\(turnComplete.payload.stopReason.rawValue)")
}

func testUnknownStopReasonAlsoMapsToCompleted() -> Bool {
    let name = "F6 unrecognized stopReason(toolUse) -> completed"
    let data: JSONObject = ["phase": "end", "stopReason": "toolUse"]
    var counter = 0
    let event = mapOpenclawAgentLifecycleToTurnComplete(
        data, ourSessionID: "s1", runID: "run-1", originTS: Date(),
        cachedUsage: nil, nextSeq: { counter += 1; return counter }
    )
    guard case .turnComplete(let turnComplete) = event, turnComplete.payload.stopReason == .completed else {
        return fail(name, "expected .completed")
    }
    return pass(name, "stopReason=\(turnComplete.payload.stopReason.rawValue)")
}

// MARK: - M2：lifecycle phase:error 不再误报 completed（新增）

/// **修前（db489f0e）fail / 修后 pass**：上一轮 mapper 完全忽略 `data.phase`，只看 `data.stopReason`
/// ——真实 openclaw 源码（`embedded-agent-subscribe.handlers.lifecycle.ts:176-202`）在
/// `isError==true` 时才把 `phase` 设成 `"error"`，且此时 `terminalStopReason` 的推导直接短路成
/// `undefined`（"stopReason" 字段很可能压根不是 "error" 字面值，甚至缺失）——上一轮的
/// `switch rawStopReason { default: .completed }` 会把这种真实的 assistant 错误终止误报成正常完成。
func testLifecyclePhaseErrorMapsToErrorStopReasonPureMapper() -> Bool {
    let name = "M2 mapper: phase=='error' maps stopReason=.error regardless of stopReason field"
    let data: JSONObject = ["phase": "error", "stopReason": "rpc", "error": "boom"]
    var counter = 0
    let event = mapOpenclawAgentLifecycleToTurnComplete(
        data, ourSessionID: "s1", runID: "run-1", originTS: Date(), cachedUsage: nil,
        nextSeq: { counter += 1; return counter }
    )
    guard case .turnComplete(let e) = event else { return fail(name, "expected .turnComplete") }
    guard e.payload.stopReason == .error else {
        return fail(name, "expected stopReason=.error, got \(e.payload.stopReason) — 修前默认折叠成 .completed")
    }
    return pass(name, "stopReason=\(e.payload.stopReason.rawValue)")
}

/// 同上，但走真实 actor 级 dispatch（`handleAgentEvent` 的 "lifecycle" 分支，`aborted:false`）
/// ——证明的是 handler+mapper 的组合行为，不只是裸调用 mapper 函数本身（codex 复现的 bug 恰好横跨
/// 这两处：handler 把 phase:error 送进 normal turn mapper，mapper 又忽略 phase）。
func testLifecyclePhaseErrorDispatchesAsErrorStopReason() async -> Bool {
    let name = "M2 real dispatch: agent(stream:lifecycle,phase:error,aborted:false) -> turnComplete(stopReason:.error)"
    let client = freshClient()
    let sessionID = "sess-lifecycle-error-1"
    let runID = "run-lifecycle-error-1"
    let kernelKey = "kernel-key-lifecycle-error"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "error", "aborted": false, "error": "boom: assistant error"] as JSONObject,
            "ts": 1_784_871_600_000,
        ] as JSONObject,
    ])

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1, case .turnComplete(let e) = events[0] else {
        return fail(name, "expected exactly 1 turnComplete event, got \(events.count)")
    }
    guard e.payload.stopReason == .error else {
        return fail(name, "expected stopReason=.error, got \(e.payload.stopReason) — 修前会被误报为 .completed")
    }
    return pass(name, "phase:error 正确映射为 turnComplete(stopReason:.error)，未被误报为 completed")
}

// MARK: - M1：approval 双向 join（跨 run 不串号 + pending-first 缓冲 + approvalReplay 消费）

/// **修前（db489f0e）fail / 修后 pass**：`session.approval` 落地时上一轮用全 session 的
/// `lastRunIDBySessionID` 关联 runId——agent approval-B(run-B) 的到达会把这个缓存刷新成 run-B，
/// 随后姗姗来迟的 `session.approval(approval-A)` 会被错误按成 run-B（codex T-045 M1 复现的
/// `REPRO approval_cross_run req=approval-A toolCall=tool-A run=run-B`）。本轮改为按 approvalId
/// 精确缓存这次审批自己的 runId（来自这条 agent 帧自己的 `payload.runId`），不再依赖"当前最新"。
func testApprovalCrossRunDoesNotStealLastActiveRunID() async -> Bool {
    let name = "M1 approval-A keeps its OWN runId (run-A) even after run-B's approval frame arrives"
    let client = freshClient()
    let sessionID = "sess-cross-run-1"
    let kernelKey = "kernel-key-cross-run-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    func agentApprovalFrame(runID: String, approvalID: String, toolCallID: String) -> JSONObject {
        [
            "type": "event", "event": "agent",
            "payload": [
                "runId": runID, "sessionKey": kernelKey, "stream": "approval",
                "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
                "ts": 1_784_871_700_000,
            ] as JSONObject,
        ]
    }
    func sessionApprovalFrame(approvalID: String, createdAtMs: Int) -> JSONObject {
        [
            "type": "event", "event": "session.approval",
            "payload": [
                "sessionKey": kernelKey, "updatedAtMs": createdAtMs, "phase": "pending",
                "approval": [
                    "id": approvalID, "status": "pending",
                    "presentation": ["kind": "exec", "commandText": "echo \(approvalID)"] as JSONObject,
                    "createdAtMs": createdAtMs, "expiresAtMs": createdAtMs + 1_800_000,
                ] as JSONObject,
            ] as JSONObject,
        ]
    }

    // REPRO 顺序（codex 复现）：agent approval-A(run-A) -> agent approval-B(run-B)（刷新
    // lastRunIDBySessionID=run-B) -> session.approval(approval-A) 才姗姗来迟。
    await client.testSupportFeedFrame(agentApprovalFrame(runID: "run-A", approvalID: "approval-A", toolCallID: "tool-A"))
    await client.testSupportFeedFrame(agentApprovalFrame(runID: "run-B", approvalID: "approval-B", toolCallID: "tool-B"))
    await client.testSupportFeedFrame(sessionApprovalFrame(approvalID: "approval-A", createdAtMs: 1_784_871_700_100))

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected exactly 1 approvalRequest, got \(events.count)")
    }
    guard e.runID == "run-A" else {
        return fail(name, "approval-A must keep runId=run-A, got \(e.runID) — 修前会串成 run-B（全 session 最近一次 lastRunIDBySessionID）")
    }
    guard e.payload.toolCallID == "tool-A" else {
        return fail(name, "unexpected toolCallID \(e.payload.toolCallID)")
    }
    let bufferLeaked = await client.testSupportHasBufferedApproval(approvalID: "approval-A")
    guard !bufferLeaked else { return fail(name, "approval-A 的双向 join 缓存应该在成功 join 后被清掉") }
    return pass(name, "approval-A 正确保留 runId=run-A（未被 run-B 的到达串号），join 成功后缓存已清")
}

/// **修前 fail / 修后 pass**：上一轮 `session.approval(pending)` 先到达时，`toolCallIDForApprovalID`
/// 查不到（agent 帧还没来），mapper 直接返回 nil——approval_request 永久丢失，即使 agent 帧随后真的
/// 到达也不会补发（codex 复现：`REPRO approval_pending_first eventTypes=["evt.session_end"]`，
/// approval_request 完全缺席）。本轮双向缓冲：session.approval 先到就缓冲整条 payload，等 agent 帧
/// 补上 {runId,toolCallId} 后由 handleAgentEvent 补发。
func testApprovalPendingFirstIsBufferedNotDropped() async -> Bool {
    let name = "M1 session.approval arriving BEFORE its agent(stream:approval) frame is buffered, not dropped"
    let client = freshClient()
    let sessionID = "sess-pending-first-1"
    let kernelKey = "kernel-key-pending-first-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let approvalID = "approval-pending-first-1"
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_871_800_000, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo pending-first"] as JSONObject,
                "createdAtMs": 1_784_871_800_000, "expiresAtMs": 1_784_873_600_000,
            ] as JSONObject,
        ] as JSONObject,
    ])

    // agent 帧还没到——修前会直接丢弃这条 approval_request，即便 agent 帧随后到达也不会补发。用
    // 内部缓冲状态断言"此刻确实还在等待"，不额外调用一次 `collectUpTo`——`AsyncThrowingStream` 的
    // 单一底层缓冲区一次只服务一个挂起的 `next()` waiter，对同一个 stream 连续调用两次
    // `collectUpTo`（各自新建一个 iterator）会让第一次超时放弃时那个 iterator 的 `next()` 调用仍
    // 挂起在等待，之后真正产出的事件会被这个"孤儿" iterator 截走，第二次 `collectUpTo` 反而永远收
    // 不到——这正是本轮 M6 在设计这批新测试时踩到的一个真实 harness 陷阱，避免的办法就是每个 stream
    // 只调用一次 `collectUpTo`。
    let bufferedBeforeAgentFrame = await client.testSupportHasBufferedApproval(approvalID: approvalID)
    guard bufferedBeforeAgentFrame else { return fail(name, "expected the pending session.approval to be buffered while waiting for the agent frame") }

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": "run-pending-first-1", "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": "tool-pending-first-1", "approvalId": approvalID] as JSONObject,
            "ts": 1_784_871_800_100,
        ] as JSONObject,
    ])

    let events = await collectUpTo(stream, maxCount: 1)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected the buffered session.approval to be emitted once the agent frame supplies runId/toolCallId, got \(events.count) — 修前这条 approval_request 永久丢失")
    }
    guard e.payload.reqID == approvalID, e.payload.toolCallID == "tool-pending-first-1", e.runID == "run-pending-first-1" else {
        return fail(name, "unexpected joined fields reqID=\(e.payload.reqID) toolCallID=\(e.payload.toolCallID) runID=\(e.runID)")
    }
    let bufferAfterJoin = await client.testSupportHasBufferedApproval(approvalID: approvalID)
    guard !bufferAfterJoin else { return fail(name, "buffer entry should be cleared after successful join") }
    return pass(name, "session.approval 先到时被正确缓冲，agent 帧补上后正确补发 approvalRequest(reqID=\(approvalID))")
}

/// **修前 fail / 修后 pass**：上一轮完全不读 `sessions.messages.subscribe` 响应里的 `approvalReplay`
/// 字段——这是断线重连/首次 subscribe 时用来补齐"建立 subscribe 之前就已经 pending"的审批的权威
/// 快照（openclaw `gateway/server-methods/sessions-subscriptions.ts:91-121`）。本轮 `subscribe()`
/// 通过真实方法体（用 `testSupportStubRPC` 桩替代网络）读取并消费它，走跟真实 `session.approval`
/// 事件完全相同的双向 join 逻辑。
func testApprovalReplayConsumedFromSubscribeResponse() async -> Bool {
    let name = "M1 subscribe() consumes approvalReplay + joins with later agent approval frame"
    let client = freshClient()
    let sessionID = "sess-replay-1"
    let kernelKey = "kernel-key-replay-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let approvalID = "approval-replay-1"
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        [
            "subscribed": true,
            "key": kernelKey,
            "approvalReplay": [
                "sessionKey": kernelKey,
                "updatedAtMs": 1_784_871_300_000,
                "truncated": false,
                "approvals": [
                    [
                        "id": approvalID, "status": "pending",
                        "presentation": ["kind": "exec", "commandText": "echo replay"] as JSONObject,
                        "createdAtMs": 1_784_871_300_000, "expiresAtMs": 1_784_873_100_000,
                        "urlPath": "/approve/\(approvalID)",
                    ] as JSONObject,
                ],
            ] as JSONObject,
        ] as JSONObject
    }

    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    let stream = await client.subscribe(session: handle)
    // 让 subscribe() 内部的背景 Task 真正跑完 RPC + consumeApprovalReplay（真实异步时序，不是 seed）。
    try? await Task.sleep(nanoseconds: 150_000_000)

    // 此时 approvalReplay 里的这条 pending 审批还没有对应的 agent(stream:approval) 帧——按 M1 双向
    // join，应该被缓冲，还不能产出 approvalRequest。用内部缓冲状态断言，不额外调用一次
    // `collectUpTo`（同一个 stream 连续调用两次 `collectUpTo` 会让第一次超时放弃的 iterator 截走
    // 后续真正产出的事件，见 `testApprovalPendingFirstIsBufferedNotDropped` 的注释）。
    guard await client.testSupportHasBufferedApproval(approvalID: approvalID) else {
        return fail(name, "expected the approvalReplay entry to be buffered awaiting the agent frame — 修前完全不读这个字段，连缓冲都不会发生")
    }

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": "run-replay-1", "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": "tool-replay-1", "approvalId": approvalID] as JSONObject,
            "ts": 1_784_871_300_500,
        ] as JSONObject,
    ])

    let events = await collectUpTo(stream, maxCount: 1)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected exactly 1 approvalRequest after agent frame arrives, got \(events.count)")
    }
    guard e.payload.reqID == approvalID, e.payload.toolCallID == "tool-replay-1", e.runID == "run-replay-1" else {
        return fail(name, "unexpected fields reqID=\(e.payload.reqID) toolCallID=\(e.payload.toolCallID) runID=\(e.runID)")
    }
    return pass(name, "approvalReplay 里的 pending 审批被正确缓冲，agent 帧补上后正确 join 产出 approvalRequest(reqID=\(approvalID))")
}

// MARK: - F5：非 exec 工具（item stream）诚实映射（纯函数，回归覆盖）

func testNonExecToolItemHonestMapping() -> Bool {
    let name = "F5 non-exec tool (item stream) honest output=null"
    let data: JSONObject = [
        "itemId": "tool:tool_p8yLr7taJUMG2ePajv3zPtmR", "phase": "end", "kind": "tool",
        "title": "tool_call", "status": "completed", "name": "tool_call",
        "toolCallId": "tool_p8yLr7taJUMG2ePajv3zPtmR",
        "startedAt": 1_784_876_075_348, "endedAt": 1_784_876_075_377,
    ]
    var counter = 0
    guard let event = mapOpenclawAgentToolItemToToolResult(
        data, ourSessionID: "s1", runIDHint: "run-1", originTS: Date(), nextSeq: { counter += 1; return counter }
    ) else {
        return fail(name, "expected non-nil toolResult event")
    }
    guard case .toolResult(let e) = event else {
        return fail(name, "expected .toolResult case")
    }
    guard e.payload.toolCallID == "tool_p8yLr7taJUMG2ePajv3zPtmR" else {
        return fail(name, "unexpected toolCallID \(e.payload.toolCallID)")
    }
    guard e.payload.isError == false else {
        return fail(name, "expected isError=false for status=completed")
    }
    guard e.payload.durationMS == 29 else {
        return fail(name, "expected durationMS=29 (endedAt-startedAt), got \(e.payload.durationMS.map(String.init) ?? "nil")")
    }
    guard e.payload.output.value is JSONNull else {
        return fail(name, "expected output to be JSON null (honest gap, no output field observed on wire), got \(e.payload.output.value)")
    }
    return pass(name, "toolCallId=\(e.payload.toolCallID) isError=false durationMS=29 output=null（诚实,非编造）")
}

func testExecToolNameFiltering() -> Bool {
    let name = "F5 exec tool name filtering (isOpenclawExecToolName)"
    guard isOpenclawExecToolName("exec") == true else { return fail(name, "\"exec\" should be treated as exec tool") }
    guard isOpenclawExecToolName("bash") == true else { return fail(name, "\"bash\" should be treated as exec tool") }
    guard isOpenclawExecToolName("update_plan") == false else { return fail(name, "\"update_plan\" should NOT be treated as exec tool") }
    guard isOpenclawExecToolName("tool_call") == false else { return fail(name, "\"tool_call\" (generic dispatcher name) should NOT be treated as exec tool") }
    return pass(name, "exec/bash 判定为 exec，update_plan/tool_call 判定为非 exec")
}

// MARK: - F5：seq gap error 事件（纯函数，回归覆盖）

func testSeqGapErrorEvent() -> Bool {
    let name = "F5 seq-gap agent(stream:error) -> evt.error"
    let data: JSONObject = ["reason": "seq gap", "expected": 5, "received": 8]
    var counter = 0
    guard let event = mapOpenclawAgentErrorToKernelEvent(
        data, ourSessionID: "s1", runIDHint: "run-1", originTS: Date(), nextSeq: { counter += 1; return counter }
    ) else {
        return fail(name, "expected non-nil error event")
    }
    guard case .error(let e) = event else {
        return fail(name, "expected .error case")
    }
    guard e.payload.code == .unknown else {
        return fail(name, "expected code=.unknown, got \(e.payload.code)")
    }
    guard e.payload.nativeCode == "seq gap" else {
        return fail(name, "expected nativeCode=\"seq gap\", got \(e.payload.nativeCode ?? "nil")")
    }
    guard e.payload.message.contains("5") && e.payload.message.contains("8") else {
        return fail(name, "expected message to mention expected=5/received=8, got \(e.payload.message)")
    }
    return pass(name, "code=unknown nativeCode=\"seq gap\" message=\(e.payload.message.debugDescription)")
}

// MARK: - F8/M5：shutdown 去重 + 真实 transport close（不再用两次同样的 shutdown 帧代替）

/// **修前 fail / 修后 pass**：上一轮 shutdown 与 transportClosed 各自独立 yield sessionEnd，没有
/// 共享的"已经产出过 terminal"标记。M6 要求不再用"喂两次同样的 shutdown 帧"代替 shutdown+transport
/// close——本轮用 `testSupportSimulateTransportClosed()` 真实触发 `receiveLoop` 遇到传输错误时走的
/// 同一条 `handleTransportClosed` 路径。
func testShutdownThenTransportCloseDedup() async -> Bool {
    let name = "F8/M6 shutdown then REAL transport-close dedup"
    let client = freshClient()
    let sessionID = "sess-shutdown-transport-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-shutdown-transport")

    let shutdownFrame: JSONObject = [
        "type": "event", "event": "shutdown",
        "payload": ["reason": "gateway stopping", "restartExpectedMs": NSNull()] as JSONObject,
        "seq": 2,
    ]
    await client.testSupportFeedFrame(shutdownFrame)

    let terminalAfterShutdown = await client.testSupportSessionTerminalEmitted(sessionID: sessionID)
    guard terminalAfterShutdown else { return fail(name, "sessionTerminalEmitted should be true right after shutdown") }

    // 真实传输层断开（不是又喂一遍同一个 shutdown 帧）。
    await client.testSupportSimulateTransportClosed()

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1, case .sessionEnd(let e) = events[0], e.payload.reason == .kernelExited else {
        return fail(name, "expected exactly 1 sessionEnd(kernel_exited) from shutdown, no second one from transport close, got \(events.count) — 修前 shutdown/transportClosed 各自独立 yield,会看到两条矛盾终态")
    }
    return pass(name, "shutdown 后真实 transport close 未产出第二条矛盾的 sessionEnd（去重生效）")
}

// MARK: - M1：send()/stop() 会话锁——真实获取/拒绝/自动释放（不再强行摆状态）

/// **修前 fail / 修后 pass**：上一轮 `send()` 没有任何锁——两个并发调用都会无条件进入 RPC。本轮
/// 加了 `send_pending` 互斥锁。本测试用一个真实的、有延迟窗口的 RPC 桩，验证：(a) 第一次 send()
/// 真实进入飞行时锁确实是 send_pending（不是靠测试强行摆的）；(b) 第二次并发 send() 被真实拒绝；
/// (c) 第一次完成后锁自动释放回 idle。
func testSendLockRealAcquireRejectAndRelease() async -> Bool {
    let name = "M1 send() real session lock: acquire during in-flight RPC, reject concurrent, auto-release after"
    let client = freshClient()
    let sessionID = "sess-send-real-lock"
    let kernelKey = "kernel-key-send-real-lock"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms 窗口,足够第二次并发 send() 在这期间被拒绝
        return ["runId": "run-real-lock-1", "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let initialLock = await client.testSupportLockState(sessionID: sessionID)
    guard initialLock == "idle" else { return fail(name, "expected initial lock idle, got \(initialLock)") }

    async let firstSend = client.send(session: handle, input: Input(kind: .text, text: "first", parts: nil))
    try? await Task.sleep(nanoseconds: 40_000_000) // 40ms,足够第一次 send() 真实拿到锁、进入 RPC 等待

    let lockDuringFlight = await client.testSupportLockState(sessionID: sessionID)
    guard lockDuringFlight == "send_pending" else {
        return fail(name, "expected lock=send_pending while first send() RPC in flight, got \(lockDuringFlight) — 说明锁没有被真实获取")
    }

    do {
        _ = try await client.send(session: handle, input: Input(kind: .text, text: "second", parts: nil))
        return fail(name, "expected concurrent second send() to be rejected while first is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        // 期望路径
    } catch {
        return fail(name, "unexpected error from concurrent send(): \(error)")
    }

    guard let firstResult = try? await firstSend, firstResult.runID == "run-real-lock-1" else {
        return fail(name, "first send() did not complete as expected")
    }

    let lockAfter = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfter == "idle" else { return fail(name, "expected lock released back to idle after first send() completes, got \(lockAfter)") }

    return pass(name, "真实并发下: 第一次 send() 在飞行中持锁 send_pending,第二次被拒 session_locked,完成后锁自动释放回 idle")
}

/// **修前 fail / 修后 pass**（针对 M3 的姊妹场景）：send() 的 RPC 失败时也必须释放锁——上一轮
/// send() 用 `defer` 已经处理了这一点，本测试是"真实调用+真实失败"的端到端验证，不是走查代码。
func testSendLockReleasedAfterRpcFailure() async -> Bool {
    let name = "M1 send() lock released to idle after RPC throws"
    let client = freshClient()
    let sessionID = "sess-send-fail-lock"
    let kernelKey = "kernel-key-send-fail-lock"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        throw KernelClientError.transport("simulated send failure")
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    do {
        _ = try await client.send(session: handle, input: Input(kind: .text, text: "x", parts: nil))
        return fail(name, "expected send() to throw")
    } catch KernelClientError.transport {
        // 期望路径
    } catch {
        return fail(name, "unexpected error \(error)")
    }

    let lock = await client.testSupportLockState(sessionID: sessionID)
    guard lock == "idle" else { return fail(name, "expected lock idle after send() RPC failure, got \(lock)") }
    return pass(name, "send() RPC 抛错后锁正确释放回 idle")
}

/// stop() 同样受这把锁保护——用一个真实在飞行中的 send() 制造窗口,验证 stop() 被真实拒绝(不是强行
/// 摆锁状态)。
func testStopRejectedWhileSendInFlight() async -> Bool {
    let name = "M1 stop() rejected with session_locked while a REAL send() is in flight"
    let client = freshClient()
    let sessionID = "sess-stop-vs-send"
    let kernelKey = "kernel-key-stop-vs-send"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return ["runId": "run-x", "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let sendTask = client.send(session: handle, input: Input(kind: .text, text: "x", parts: nil))
    try? await Task.sleep(nanoseconds: 40_000_000)

    do {
        _ = try await client.stop(session: handle)
        _ = try? await sendTask
        return fail(name, "expected stop() to be rejected while send() is in flight")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        _ = try? await sendTask
        return pass(name, "stop() 在真实 send() 飞行期间被正确 reject(session_locked)")
    } catch {
        _ = try? await sendTask
        return fail(name, "unexpected error \(error)")
    }
}

// MARK: - M3：stop() 状态机——真实调用四条路径 + 锁/pendingStop 清理

/// **修前 fail / 修后 pass**：上一轮 `abortedRunId==nil` 路径只发 session_end，从不发
/// operation_completed 镜像——只订阅事件流、不等 Promise 的观察者完全看不到这次 stop 操作本身的终态。
func testStopNoActiveRunEmitsOperationCompletedMirror() async -> Bool {
    let name = "M3 stop() no active run -> operation_completed(succeeded) mirror + Promise succeeded"
    let client = freshClient()
    let sessionID = "sess-stop-noactive"
    let kernelKey = "kernel-key-stop-noactive"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    guard let result = try? await client.stop(session: handle) else { return fail(name, "stop() unexpectedly threw") }
    guard result.outcome == .succeeded else { return fail(name, "expected Promise outcome=.succeeded, got \(result.outcome)") }

    let events = await collectUpTo(stream, maxCount: 3)
    guard events.count == 2 else {
        return fail(name, "expected 2 events (operation_completed mirror + session_end), got \(events.count) — 修前这条路径只发 session_end,完全没有 operation_completed 镜像")
    }
    guard case .operationCompleted(let op) = events[0] else {
        return fail(name, "expected first event .operationCompleted, got \(events[0].wireType)")
    }
    guard op.payload.operationID == result.operationID, op.payload.outcome == .succeeded else {
        return fail(name, "operationCompleted must mirror Promise: got id=\(op.payload.operationID) outcome=\(op.payload.outcome), Promise id=\(result.operationID)")
    }
    guard case .sessionEnd(let end) = events[1], end.payload.reason == .stopped else {
        return fail(name, "expected second event sessionEnd(reason:.stopped)")
    }
    return pass(name, "operationId=\(result.operationID) 双通道 outcome 均为 succeeded,session_end(stopped) 紧随其后")
}

/// **修前 fail / 修后 pass**：等待超时同样没有 operation_completed 镜像。用
/// `testSupportSetStopTimeoutSeconds` 缩短超时,不需要真等 5 秒。
func testStopTimeoutEmitsOperationCompletedMirror() async -> Bool {
    let name = "M3 stop() waiting for aborted-run terminal times out -> operation_completed(timed_out) mirror"
    let client = freshClient()
    let sessionID = "sess-stop-timeout"
    let kernelKey = "kernel-key-stop-timeout"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportSetStopTimeoutSeconds(1)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        // 真实存在 active run 需要等待,但本测试故意不喂任何 aborted lifecycle 帧——模拟"该 run 的
        // 终态 lifecycle 帧因为某种原因一直没有到达"。
        ["ok": true, "abortedRunId": "run-timeout-1", "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    guard let result = try? await client.stop(session: handle) else { return fail(name, "stop() unexpectedly threw") }
    guard result.outcome == .timedOut else {
        return fail(name, "expected Promise outcome=.timedOut, got \(result.outcome)")
    }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 500)
    guard events.count == 2 else {
        return fail(name, "expected 2 events (operation_completed(timed_out) mirror + session_end), got \(events.count) — 修前这条路径 Promise 会报 timedOut 但 Event 完全没有镜像")
    }
    guard case .operationCompleted(let op) = events[0], op.payload.outcome == .timedOut, op.payload.operationID == result.operationID else {
        return fail(name, "expected operation_completed(timed_out) mirroring Promise operationId=\(result.operationID)")
    }
    return pass(name, "超时路径 operationId=\(result.operationID) Promise 与 Event 均报 timed_out")
}

/// **修前 fail / 修后 pass**：active-run 路径在 delete 之前就已经通过 handleAgentEvent 发出
/// operation_completed(succeeded)；若随后 sessions.delete 返回 deleted:false,上一轮 Promise 会
/// 重新按 deleted 计算成 .rejected,与已经发出的 Event 矛盾。本轮 outcome 只看 timedOut,不再看
/// deleted,两者必然一致。同时验证 aborted 帧驱动出的 operation_completed+turn_complete(cancelled)
/// +session_end(stopped) 三件套顺序。
func testStopDeleteFailureDoesNotContradictAlreadyEmittedOutcome() async -> Bool {
    let name = "M3 stop() active-run success + sessions.delete deleted:false must not contradict already-emitted operation_completed(succeeded)"
    let client = freshClient()
    let sessionID = "sess-stop-deletefail"
    let kernelKey = "kernel-key-stop-deletefail"
    let runID = "run-deletefail-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // 用一条无害的 run_status 帧模拟"目前有一个活跃 run"这一前置状态（刷新 lastRunIDBySessionID），
    // 不经过内部 seed，走真实 agent 事件 dispatch。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": ["runId": runID, "sessionKey": kernelKey, "stream": "run_status", "data": [:] as JSONObject] as JSONObject,
    ])

    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": false] as JSONObject }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let stopResult = client.stop(session: handle)
    // stop() 此刻已经发起 sessions.abort 并开始等待该 run 的 aborted lifecycle 终态——喂一条真实
    // 形状的 aborted lifecycle 帧,唤醒等待、发出 operation_completed(succeeded)+turn_complete(cancelled)。
    try? await Task.sleep(nanoseconds: 60_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_871_400_000,
        ] as JSONObject,
    ])

    guard let result = try? await stopResult else { return fail(name, "stop() unexpectedly threw") }
    guard result.outcome == .succeeded else {
        return fail(name, "expected Promise outcome=.succeeded despite sessions.delete deleted:false, got \(result.outcome) — 修前会把它翻成 .rejected,与已经发出的 operation_completed(succeeded) 矛盾")
    }

    let events = await collectUpTo(stream, maxCount: 4)
    guard events.count == 3 else {
        return fail(name, "expected exactly 3 events (operation_completed + turn_complete(cancelled) + session_end(stopped)), got \(events.count)")
    }
    guard case .operationCompleted(let op) = events[0], op.payload.outcome == .succeeded, op.payload.operationID == result.operationID else {
        return fail(name, "expected first event operation_completed(succeeded) matching Promise operationId")
    }
    guard case .turnComplete(let turn) = events[1], turn.payload.stopReason == .cancelled else {
        return fail(name, "expected second event turn_complete(cancelled)")
    }
    guard case .sessionEnd(let end) = events[2], end.payload.reason == .stopped else {
        return fail(name, "expected third event session_end(stopped)")
    }
    return pass(name, "operationId=\(result.operationID): Promise=.succeeded, Event.outcome=.succeeded 一致,即使 sessions.delete 报告 deleted:false")
}

/// **修前 fail / 修后 pass**：`sessions.abort` 抛错时上一轮直接向上抛出，`stopInProgress` 锁和
/// `pendingStops` 条目永远不释放——第二次 stop() 会被误判成"另一个 stop 正在进行"而拒绝
/// （`session_locked`），即使第一次调用早就已经失败结束（codex 复现：
/// `REPRO first_stop_error=... lock_after_stop_error=stop_in_progress second_stop_error=rpc rejected
/// [session_locked]`）。本轮 catch 里统一释放锁+清理 pendingStop+发 operation_completed(rejected)
/// 镜像。
func testStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror() async -> Bool {
    let name = "M3 stop() sessions.abort throws -> lock released + pendingStop cleaned + operation_completed(rejected) mirror; second stop() not falsely session_locked"
    let client = freshClient()
    let sessionID = "sess-stop-abort-throws"
    let kernelKey = "kernel-key-stop-abort-throws"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        throw KernelClientError.transport("simulated: kernel client not connected")
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    do {
        _ = try await client.stop(session: handle)
        return fail(name, "expected stop() to rethrow the abort RPC error")
    } catch KernelClientError.transport(let message) {
        guard message.contains("simulated") else { return fail(name, "unexpected transport error message \(message)") }
    } catch {
        return fail(name, "expected KernelClientError.transport, got \(error)")
    }

    let lockAfterFailure = await client.testSupportLockState(sessionID: sessionID)
    guard lockAfterFailure == "idle" else {
        return fail(name, "expected lock released to idle after abort throw, got \(lockAfterFailure) — 修前锁永久卡在 stop_in_progress")
    }
    let pendingAfterFailure = await client.testSupportHasPendingStop(sessionID: sessionID)
    guard !pendingAfterFailure else { return fail(name, "expected pendingStop to be cleaned up after abort throw") }

    let events = await collectUpTo(stream, maxCount: 1, timeoutMs: 200)
    guard events.count == 1, case .operationCompleted(let op) = events[0], op.payload.outcome == .rejected else {
        return fail(name, "expected operation_completed(rejected) mirror after abort throw, got \(events.count) events")
    }

    // 关键复现：第二次 stop() 不应该被 session_locked 拒绝——它应该照样命中同一个 stub,再次抛出同样
    // 的 transport 错误,证明锁真的被释放了(不是被绕过)。
    do {
        _ = try await client.stop(session: handle)
        return fail(name, "expected second stop() to also throw the stubbed transport error")
    } catch KernelClientError.rpcRejected(let code, _) where code == "session_locked" {
        return fail(name, "second stop() incorrectly rejected with session_locked — 锁没有被正确释放,复现了修前的永久锁死缺陷")
    } catch KernelClientError.transport {
        return pass(name, "第一次 stop() 抛错后锁正确释放为 idle + pendingStop 清理 + operation_completed(rejected) 镜像已发出;第二次 stop() 正常再次尝试(而不是被 session_locked 挡住)")
    } catch {
        return fail(name, "unexpected error on second stop(): \(error)")
    }
}

/// M5：stop() 成功收尾后,pendingStop/锁/terminal 标记/未匹配成功的 approval 缓冲全部清理干净——
/// 覆盖"没有匹配上的条目最终也要在 session 结束时被清掉"这一要求(不是只清匹配成功的)。
func testStopCleansUpAllSessionCaches() async -> Bool {
    let name = "M5 stop() success cleans up pendingStop/lock/terminal flag/orphaned approval buffer"
    let client = freshClient()
    let sessionID = "sess-cleanup-1"
    let kernelKey = "kernel-key-cleanup-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // 留一个"从未匹配上"的 pending-first 审批缓冲。
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_871_500_000, "phase": "pending",
            "approval": [
                "id": "approval-orphan-1", "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo orphan"] as JSONObject,
                "createdAtMs": 1_784_871_500_000, "expiresAtMs": 1_784_873_300_000,
            ] as JSONObject,
        ] as JSONObject,
    ])
    guard await client.testSupportHasBufferedApproval(approvalID: "approval-orphan-1") else {
        return fail(name, "expected the orphan pending-first approval to be buffered before cleanup")
    }

    await client.testSupportStubRPC(method: "sessions.abort") { _ in ["ok": true, "abortedRunId": NSNull(), "status": "no-active-run"] as JSONObject }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    _ = try? await client.stop(session: handle)

    guard await client.testSupportLockState(sessionID: sessionID) == "idle" else { return fail(name, "lock should be cleared (idle) after stop()") }
    guard await client.testSupportHasPendingStop(sessionID: sessionID) == false else { return fail(name, "pendingStop should be removed after stop()") }
    guard await client.testSupportSessionTerminalEmitted(sessionID: sessionID) == false else {
        return fail(name, "sessionTerminalEmitted should be cleared after full session teardown — 修前这个标记永远不清,长连接下会无限增长")
    }
    guard await client.testSupportHasBufferedApproval(approvalID: "approval-orphan-1") == false else {
        return fail(name, "orphaned pending-first approval buffer should be cleaned up on session teardown — 修前只有 join 成功才清,漏配对的条目永久残留")
    }
    return pass(name, "stop() 收尾后 lock/pendingStop/terminal 标记/未匹配的 approval 缓冲全部清理干净")
}

/// NOTE-1（T-047 grok 复核 SG-5 rounds/0005 主 NOTE，真挂起 bug 回归守卫）。
///
/// **修前 fail / 修后 pass**：stop() 发起 sessions.abort 得到非空 abortedRunId 后进入
/// `waitForPendingStopTerminal` 等待——此时 transport 关闭（`handleTransportClosed` ->
/// `failAllPending` -> `clearSessionDerivedCaches`）。修前 `clearSessionDerivedCaches` 直接
/// `pendingStops.removeValue(forKey:)`，完全不管条目里还挂着一个活的 waiter；随后无论是超时定时器
/// 触发 `resolvePendingStopWaiter`，还是任何别的路径，都会因为 `pendingStops[sessionID]` 查不到而
/// `guard` 提前 return——`CheckedContinuation` 永不 resume，`await` 永久悬挂，`stop()` 这次调用永远
/// 不返回（本测试用"跟 2 秒护栏赛跑"证伪：修前会在 2 秒边界判定失败，而不是等到真正的测试超时——
/// 如果不设这个有界护栏，修前版本会把整个测试进程挂死）。
///
/// 修后：`resolvePendingStopForTransportClose` 在 `handleTransportClosed` 的 sessionEnd 之前、
/// `failAllPending` 把 continuation `finish(throwing:)` 之前，为这个仍在等待的 pendingStop 补发一条
/// `operation_completed(aborted_effect_unknown)` 镜像 + 唤醒 waiter；`stop()` 收到
/// `StopWaitOutcome.transportClosed` 之后如实抛 `KernelClientError.transport`，不假装
/// succeeded/timed_out。
/// stop()（真实驱动，可能永久挂起）与一个有界超时护栏之间的"谁先报告谁赢"竞态盒——**故意不用**
/// `withTaskGroup`：task group 的 `body` 在返回前会隐式等待全部子任务真正结束（`cancelAll()` 只是
/// 请求协作式取消，`withCheckedContinuation` 不参与协作取消），如果 `stop()` 真的（修前）永久卡在
/// 一个从不会被 resume 的 `CheckedContinuation` 上，`withTaskGroup` 本身就会跟着永远不返回——
/// 那样就测不出"修前会挂起"这件事本身，只会把整个测试进程一起拖死。这里改用两个非结构化的
/// `Task { }`：谁先调用 `report` 谁的结果被采纳，另一个（修前场景里就是那个永久卡住的 stop()）
/// 继续作为被遗弃的孤儿 task 在后台挂着，不阻塞测试函数返回。
private final class RaceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    private var waiter: CheckedContinuation<T, Never>?

    func report(_ v: T) {
        lock.lock()
        guard value == nil else { lock.unlock(); return }
        value = v
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: v)
    }

    func wait() async -> T {
        lock.lock()
        if let v = value {
            lock.unlock()
            return v
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            self.waiter = cont
            lock.unlock()
        }
    }
}

func testStopTransportClosedWhileWaitingDoesNotHangAndEmitsMirror() async -> Bool {
    let name = "NOTE-1 (T-047) stop() transport closes while awaiting aborted-run terminal -> no permanent hang, operation_completed(aborted_effect_unknown) mirror before session_end(transport_closed)"
    let client = freshClient()
    let sessionID = "sess-stop-transport-closed-midwait"
    let kernelKey = "kernel-key-stop-transport-closed-midwait"
    let runID = "run-transport-closed-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    // 生产默认超时（5 秒）——刻意不缩短，用来证明 stop() 是被 transport-close 路径主动唤醒的，不是
    // 靠超时兜底"侥幸"返回。
    await client.testSupportSetStopTimeoutSeconds(5)
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    enum RaceResult {
        case completed(Result<StopResultPayload, Error>)
        case timedOut
    }

    let box = RaceBox<RaceResult>()

    // Task A：真实驱动 stop()——修前这个 task 会在 transport 关闭后永久卡住，从此再也不会调用
    // box.report(...)，永远是孤儿 task，但不阻塞下面 box.wait()。
    Task {
        do {
            let result = try await client.stop(session: handle)
            box.report(.completed(.success(result)))
        } catch {
            box.report(.completed(.failure(error)))
        }
    }
    // Task B：40ms 后触发 transport 关闭——独立于下面的护栏 task，保证无论调度顺序如何都会真的
    // 触发这次关闭。
    Task {
        try? await Task.sleep(nanoseconds: 40_000_000) // 足够 stop() 真实拿到 abortedRunId、进入 waitForPendingStopTerminal 等待
        await client.testSupportSimulateTransportClosed()
    }
    // Task C：2 秒有界护栏（远小于 5 秒生产超时）——修前 Task A 永久挂起时，由这个 task 兜底让
    // box.wait() 有限时间内返回，而不是把测试也一起拖死。
    Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        box.report(.timedOut)
    }

    let raceResult = await box.wait()

    switch raceResult {
    case .timedOut:
        return fail(name, "stop() 在 transport 关闭后 2 秒内仍未返回/抛错——永久挂起复现（修前的确切 bug，NOTE-1 描述的场景）")
    case .completed(.success(let result)):
        return fail(name, "expected stop() to throw a transport error after transport closed mid-wait, got a result instead (outcome=\(result.outcome))")
    case .completed(.failure(let error)):
        guard case KernelClientError.transport = error else {
            return fail(name, "expected KernelClientError.transport, got \(error)")
        }
    }

    let events = await collectUpTo(stream, maxCount: 3, timeoutMs: 500)
    guard events.count == 2 else {
        return fail(name, "expected 2 events (operation_completed(aborted_effect_unknown) mirror + session_end(transport_closed)), got \(events.count) — 修前这条路径完全没有镜像（waiter 从未被 resume，continuation 也没收到任何 operation_completed）")
    }
    guard case .operationCompleted(let op) = events[0], op.payload.outcome == .abortedEffectUnknown, op.payload.affectedRunID == runID else {
        return fail(name, "expected first event operation_completed(aborted_effect_unknown) affectedRunID=\(runID), got \(events[0].wireType)")
    }
    guard case .sessionEnd(let end) = events[1], end.payload.reason == .transportClosed else {
        return fail(name, "expected second event sessionEnd(reason:.transportClosed) — operation_completed 镜像必须先于 session_end,对应 D1 §9.3 既有顺序约定")
    }

    let hasPendingStopAfter = await client.testSupportHasPendingStop(sessionID: sessionID)
    guard !hasPendingStopAfter else { return fail(name, "expected pendingStop to be cleaned up after transport-closed cleanup") }

    return pass(name, "transport 在等待窗口内关闭: stop() 未永久挂起,如实抛出 transport 错误,operation_completed(aborted_effect_unknown affectedRunID=\(runID)) 镜像先于 session_end(transport_closed) 发出,pendingStop 清理干净")
}

// MARK: - F2：attachment-only（附件编码成 openclaw 期望的 content 形状，纯函数，回归覆盖）

func testAttachmentOnlyEncodesContent() -> Bool {
    let name = "F2 attachment-only encodes content (not {mimeType,path})"
    let tmpDir = FileManager.default.temporaryDirectory
    let fileURL = tmpDir.appendingPathComponent("frame-replay-attachment-\(UUID().uuidString).txt")
    let fileBytes = Data("hello-sg5-attachment".utf8)
    do {
        try fileBytes.write(to: fileURL)
    } catch {
        return fail(name, "failed to write temp fixture file: \(error)")
    }
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let part = Part(kind: .fileRef, text: nil, mimeType: "text/plain", path: fileURL.path)
    guard let encoded = encodeAttachmentForWire(part) else {
        return fail(name, "expected non-nil encoded attachment")
    }
    guard encoded["path"] == nil else {
        return fail(name, "encoded attachment must NOT carry a bare 'path' field — openclaw would silently drop it (no content)")
    }
    guard let content = encoded["content"] as? String else {
        return fail(name, "expected 'content' field (base64), got keys \(encoded.keys.sorted())")
    }
    guard let decoded = Data(base64Encoded: content), decoded == fileBytes else {
        return fail(name, "content did not base64-decode back to the original file bytes")
    }
    guard (encoded["mimeType"] as? String) == "text/plain" else {
        return fail(name, "expected mimeType=text/plain to be preserved")
    }
    return pass(name, "content(base64) 正确还原原始字节，且不再携带裸 path 字段")
}

// MARK: - M4：脱敏——复数/常见变体漏报 + token 计数字段误伤

/// **修前（db489f0e）fail / 修后 pass**：敏感词表只有单数整词——`credentials`/`apiKeys`/`secrets`
/// 这些真实 payload 里常见的复数写法，整个 key 就是这一个词，永远不等于单数形式，完全漏报。
/// `authToken`/`apiToken` 复合词凭证字段同样必须脱敏。
func testRedactionCoversPluralsAndCommonVariants() -> Bool {
    let name = "M4 redaction covers plurals + common credential variants"
    let cases: [(String, Any)] = [
        ("credentials", "live-credential-value"),
        ("apiKeys", "live-api-key-value"),
        ("secrets", "live-secret-value"),
        ("authToken", "live-auth-token-value"),
        ("apiToken", "live-api-token-value"),
        ("password", "live-password-value"),
        ("token", "live-bare-token-value"),
    ]
    for (key, value) in cases {
        let obj: JSONObject = [key: value]
        guard let redacted = redactedCopy(obj) as? JSONObject, (redacted[key] as? String) == "***REDACTED***" else {
            return fail(name, "expected \(key) 整体脱敏, got \(String(describing: (redactedCopy(obj) as? JSONObject)?[key])) — 修前 \(key) 会漏报(复数/未覆盖变体)")
        }
    }
    return pass(name, "credentials/apiKeys/secrets(复数)、authToken/apiToken(复合)、password/token(裸字段) 全部正确脱敏")
}

/// **修前 fail / 修后 pass**：`tokenBudget` 这类含单数 "token" 的计数字段被误伤（当前敏感词表把
/// 任何含整词 "token" 的字段都判定敏感）。`contextTokens`/`inputTokens`/`outputTokens` 附带验证
/// 不回归。
func testRedactionExcludesTokenCountingFields() -> Bool {
    let name = "M4 redaction excludes token-counting fields (contextTokens/tokenBudget/inputTokens/outputTokens)"
    let cases: [(String, Int)] = [
        ("contextTokens", 200_000),
        ("tokenBudget", 128_000),
        ("inputTokens", 9288),
        ("outputTokens", 2346),
    ]
    for (key, value) in cases {
        let obj: JSONObject = [key: value]
        guard let redacted = redactedCopy(obj) as? JSONObject, (redacted[key] as? Int) == value else {
            return fail(name, "expected \(key)=\(value) 保持不脱敏, got \(String(describing: (redactedCopy(obj) as? JSONObject)?[key])) — 误伤了 token 计数字段")
        }
    }
    return pass(name, "contextTokens/tokenBudget/inputTokens/outputTokens 均保持原值，未被误伤")
}

/// F7 CRITICAL 场景的回归覆盖：`connect` 请求里 `params.auth.token` 整体脱敏，非敏感字段原样保留，
/// 且脱敏结果的字符串表示里不含明文 token 值。
func testCredentialRedactionRegressionRealFrame() -> Bool {
    let name = "F7 regression: credential redaction (auth/token) on a realistic connect frame"
    let frame: JSONObject = [
        "type": "req", "id": "r1", "method": "connect",
        "params": [
            "minProtocol": 3,
            "auth": ["token": "super-secret-real-token-value"] as JSONObject,
            "client": ["id": "cli", "mode": "cli"] as JSONObject,
        ] as JSONObject,
    ]
    guard let redacted = redactedCopy(frame) as? JSONObject,
          let params = redacted["params"] as? JSONObject else {
        return fail(name, "unexpected redacted shape")
    }
    guard let auth = params["auth"] as? String, auth == "***REDACTED***" else {
        return fail(name, "expected params.auth to be fully redacted, got \(String(describing: params["auth"]))")
    }
    guard (params["minProtocol"] as? Int) == 3 else {
        return fail(name, "non-sensitive field params.minProtocol should survive unchanged")
    }
    guard let client = params["client"] as? JSONObject, (client["id"] as? String) == "cli" else {
        return fail(name, "non-sensitive nested field params.client.id should survive unchanged")
    }
    let serialized = String(describing: redacted)
    guard !serialized.contains("super-secret-real-token-value") else {
        return fail(name, "raw token value leaked into redacted copy's string representation")
    }
    return pass(name, "auth 字段整体脱敏，非敏感字段保留，明文 token 未出现在序列化结果里")
}

// MARK: - M6：完整 D2 JSON encode/decode 字段断言

/// **M6 新增**：上一轮没有对完整 D2 JSON 做 encode/decode 断言。本测试构造两个有代表性的判别联合
/// 变体（`toolResult` 带嵌套 JSONAny output；`operationCompleted` 覆盖 M3 用到的 outcome 枚举 +
/// 可选字段），完整走 `JSONEncoder`/`JSONDecoder`，逐字段断言往返一致（不仅仅是"没抛错"）。
func testFullD2JSONEncodeDecodeRoundTrip() -> Bool {
    let name = "M6 完整 D2 JSON encode/decode 字段断言（toolResult + operationCompleted）"
    let now = Date(timeIntervalSince1970: 1_784_871_900)

    let toolResultPayload = ToolResultEventMessagePayload(
        durationMS: 42, isError: false,
        output: makeJSONAny(["stdout": "hello", "lines": [1, 2, 3]] as JSONObject),
        toolCallID: "tool-roundtrip-1"
    )
    let toolResultEvent = EventMessageUnion.toolResult(ToolResultEventMessage(
        direction: .event, payload: toolResultPayload, runID: "run-roundtrip-1",
        sentAt: now, seq: 7, sessionID: "sess-roundtrip-1", ts: now, type: .evtToolResult
    ))

    guard let data = try? JSONEncoder().encode(toolResultEvent) else { return fail(name, "toolResult encode failed") }
    guard let decoded = try? JSONDecoder().decode(EventMessageUnion.self, from: data) else { return fail(name, "toolResult decode failed") }
    guard case .toolResult(let decodedToolResult) = decoded else { return fail(name, "decoded into wrong case: \(decoded.wireType)") }
    guard decodedToolResult.payload.toolCallID == "tool-roundtrip-1",
          decodedToolResult.payload.durationMS == 42,
          decodedToolResult.payload.isError == false,
          decodedToolResult.runID == "run-roundtrip-1",
          decodedToolResult.seq == 7,
          decodedToolResult.sessionID == "sess-roundtrip-1",
          decodedToolResult.type == .evtToolResult
    else {
        return fail(name, "toolResult round-tripped scalar fields do not match original")
    }
    guard let outputDict = decodedToolResult.payload.output.value as? [String: Any],
          (outputDict["stdout"] as? String) == "hello",
          let lines = outputDict["lines"] as? [Any], lines.count == 3
    else {
        return fail(name, "nested JSONAny output did not round-trip structurally: \(decodedToolResult.payload.output.value)")
    }

    let opPayload = OperationCompletedEventMessagePayload(
        affectedRunID: "run-op-1", detail: "aborted by user", newRunID: nil,
        operationID: "op-roundtrip-1", operationKind: .stop, outcome: .timedOut
    )
    let opEvent = EventMessageUnion.operationCompleted(OperationCompletedEventMessage(
        direction: .event, payload: opPayload, runID: "run-op-1",
        sentAt: now, seq: 9, sessionID: "sess-roundtrip-1", ts: now, type: .evtOperationCompleted
    ))
    guard let opData = try? JSONEncoder().encode(opEvent) else { return fail(name, "operationCompleted encode failed") }
    guard let opDecoded = try? JSONDecoder().decode(EventMessageUnion.self, from: opData) else { return fail(name, "operationCompleted decode failed") }
    guard case .operationCompleted(let decodedOp) = opDecoded else { return fail(name, "decoded into wrong case: \(opDecoded.wireType)") }
    guard decodedOp.payload.operationID == "op-roundtrip-1",
          decodedOp.payload.outcome == .timedOut,
          decodedOp.payload.affectedRunID == "run-op-1",
          decodedOp.payload.newRunID == nil,
          decodedOp.payload.operationKind == .stop,
          decodedOp.payload.detail == "aborted by user"
    else {
        return fail(name, "operationCompleted round-tripped fields do not match")
    }

    return pass(name, "toolResult(嵌套 JSONAny output)与 operationCompleted 两个变体的完整 D2 JSON encode/decode 均字段级一致")
}

// MARK: - 总入口

public func runFrameReplayTests() async -> Bool {
    print("=== SG-5 rework 第二次收残（T-045 MUST-FIX）frame-replay 真 actor 级单测 ===")
    var results: [Bool] = []
    results.append(testSeqOrderingWithinRunAndOriginTS())
    results.append(testNoStopReasonEndMapsToCompleted())
    results.append(testUnknownStopReasonAlsoMapsToCompleted())
    results.append(testLifecyclePhaseErrorMapsToErrorStopReasonPureMapper())
    results.append(await testLifecyclePhaseErrorDispatchesAsErrorStopReason())
    results.append(await testApprovalCrossRunDoesNotStealLastActiveRunID())
    results.append(await testApprovalPendingFirstIsBufferedNotDropped())
    results.append(await testApprovalReplayConsumedFromSubscribeResponse())
    results.append(testNonExecToolItemHonestMapping())
    results.append(testExecToolNameFiltering())
    results.append(testSeqGapErrorEvent())
    results.append(await testShutdownThenTransportCloseDedup())
    results.append(await testSendLockRealAcquireRejectAndRelease())
    results.append(await testSendLockReleasedAfterRpcFailure())
    results.append(await testStopRejectedWhileSendInFlight())
    results.append(await testStopNoActiveRunEmitsOperationCompletedMirror())
    results.append(await testStopTimeoutEmitsOperationCompletedMirror())
    results.append(await testStopDeleteFailureDoesNotContradictAlreadyEmittedOutcome())
    results.append(await testStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror())
    results.append(await testStopCleansUpAllSessionCaches())
    results.append(await testStopTransportClosedWhileWaitingDoesNotHangAndEmitsMirror())
    results.append(testAttachmentOnlyEncodesContent())
    results.append(testRedactionCoversPluralsAndCommonVariants())
    results.append(testRedactionExcludesTokenCountingFields())
    results.append(testCredentialRedactionRegressionRealFrame())
    results.append(testFullD2JSONEncodeDecodeRoundTrip())

    let passCount = results.filter { $0 }.count
    let total = results.count
    print("=== 结果: \(passCount)/\(total) PASS ===")
    return passCount == total
}
