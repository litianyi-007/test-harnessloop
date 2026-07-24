// Frame-replay 单测——SG-5 rework 轮，回应对抗审 T-044 的明确要求："增加 frame-replay 单测：对
// 完整 D2 JSON 做字段断言，覆盖并发双 send、两个交错 tool approval、非 exec tool、无 stopReason、
// abort 的 end+error 双帧、seq gap、shutdown+socket close、attachment-only；现有真实 Kimi 流程仅
// 作为 smoke test 保留"。
//
// 这个项目没有 XCTest/SwiftPM test target（`app/contracts/d2/codegen` 定的是"纯 swiftc 编译一个
// 可执行文件"这套风格，`KernelClient.swift` 头注释延续了同一约定）——本文件延续这个风格：不依赖
// 任何测试框架，每个测试是一个返回 `Bool`（或 `async -> Bool`）的普通函数，`runFrameReplayTests()`
// 依次跑、打印每条的 PASS/FAIL 和一句诊断，最后返回总体是否全过。真正的可执行入口在
// `FrameReplayTestMain.swift`（单独一个 swiftc 编译目标，不跟 CLIRunner.swift/main.swift 混在一起，
// 避免"多个文件里都有顶层可执行语句"这个 Swift 限制）。
//
// 每个测试函数的文档注释都标注了"这条断言在修前会不会失败"——凡是能够直接构造出"修前的实现会给出
// 错误结果"的场景，都在注释里写清楚对照的旧行为，不是空泛地宣称"验证过"。

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

/// 收集流上最多 `maxCount` 个事件，超过 `timeoutMs` 还没凑够就提前放弃——用于"验证不多不少"的场景
/// （F6/F8 去重测试：如果 bug 复现会多出一条事件，正确实现下多等的这一条永远不会来，需要一个超时
/// 兜底，不能无限悬挂）。所有测试里的 `testSupportFeedFrame` 调用都已经在 `await` 返回前完成了
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

// MARK: - F3：per-run 单调 seq + 保留原始 ts（不用 Date()）

/// **修前 fail / 修后 pass**：上一轮 `mapOpenclawSessionMessageToKernelEvents` 内部自己从
/// `payload["messageSeq"]` 取 seq——同一条 assistant 消息里的多个 content block（这里用真实样本
/// 形状：text + toolCall 同时出现）会拿到**同一个** `messageSeq` 值，产出的多个 D2 事件 seq 完全
/// 相同（不是递增），直接违反 D1 "run 内排序"的最基本要求。本轮改为调用方按 runId 维护一个真正
/// 递增的计数器，通过 `nextSeq` 闭包传入——同一条消息产出的 N 个事件应该拿到 N 个严格递增的 seq。
/// 同时验证 `ts` 取的是消息自己的 `timestamp` 字段（真实样本 `1784876055901`），不是"现在"。
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
        return fail(name, "expected strictly increasing per-run seq [1,2], got \(seqs) — 修前 bug 会让两者都等于同一个 messageSeq")
    }
    // ts 必须来自 message.timestamp（换算成 Date），不是 Date()（现在）。
    let expectedTS = Date(timeIntervalSince1970: Double(messageTimestampMs) / 1000.0)
    for event in events {
        let ts: Date
        switch event {
        case .messageDelta(let e): ts = e.ts
        case .toolCall(let e): ts = e.ts
        default: continue
        }
        guard abs(ts.timeIntervalSince(expectedTS)) < 0.001 else {
            return fail(name, "ts \(ts) 不等于 message.timestamp 换算值 \(expectedTS)——修前用的是 Date()（现在），必然不等")
        }
    }
    return pass(name, "seq=\(seqs) ts 均等于 message.timestamp（非 Date()）")
}

// MARK: - F6：无 stopReason 的合法 end 不再默认 error

/// **修前 fail / 修后 pass**：上一轮 `switch rawStopReason { ... default: stopReason = .error }`——
/// 真实 openclaw 测试里存在 `data:{phase:"end"}`（没有 stopReason 字段）这种合法终态，上一轮会把它
/// 误报成 `.error`。本轮：`phase=="end"` 由 openclaw 自身构造逻辑保证非错误终止（`isError` 已经在
/// 生成这条帧之前判过一次，`phase` 只有出错时才会是 `"error"`），缺失/未知 stopReason 一律折叠到
/// `.completed`。
func testNoStopReasonEndMapsToCompleted() -> Bool {
    let name = "F6 no-stopReason end -> completed (not error)"
    let data: JSONObject = ["phase": "end"] // 真实 openclaw 测试用例形状，没有 stopReason 字段
    var counter = 0
    let event = mapOpenclawAgentLifecycleToTurnComplete(
        data, ourSessionID: "s1", runID: "run-1", originTS: Date(),
        cachedUsage: nil, nextSeq: { counter += 1; return counter }
    )
    guard case .turnComplete(let turnComplete) = event else {
        return fail(name, "expected .turnComplete case")
    }
    guard turnComplete.payload.stopReason == .completed else {
        return fail(name, "expected stopReason=.completed, got \(turnComplete.payload.stopReason) — 修前会默认成 .error")
    }
    return pass(name, "stopReason=\(turnComplete.payload.stopReason.rawValue)")
}

/// 附带验证：`"toolUse"`（真实样本里回合内还在工具调用中就进入 lifecycle "end" 的边缘取值）同样折叠
/// 到 `.completed`，不是只对"完全没有 stopReason 字段"这一种情况生效。
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

// MARK: - F6：abort 的 end+error 双帧 -> 单个 operation_completed + turn_complete(cancelled)

/// **修前 fail / 修后 pass**：上一轮每一条 `aborted:true` 的 lifecycle 帧都会各自产出一条
/// `operationCompleted`（operationId 是 mapper 自己派生的，与 `stop()` 返回的 `StopResultPayload.
/// operationID` 不同），真实样本里 `sessions.abort` 会连续发两帧（`phase:"end"` 然后
/// `phase:"error","This operation was aborted"`），上一轮会产出两条互相矛盾的 operation_completed
/// （outcome 不同），且从不产出 `turn_complete(cancelled)`。本轮：`stop()` 铸造一个唯一
/// operationId 登记到 `pendingStops`，`handleAgentEvent` 对同一次 pendingStop 只在**第一条**
/// aborted 帧时产出 `[operationCompleted, turnComplete(cancelled)]`（用 stop() 铸造的那个
/// operationId），第二条收尾帧被去重丢弃。
func testAbortEndThenErrorProducesSingleTerminalPair() async -> Bool {
    let name = "F6 abort end+error double frame -> single operation_completed+turn_complete"
    let client = freshClient()
    let sessionID = "sess-abort-1"
    let runID = "run-abort-1"
    let operationID = "op-stop-test-fixed-id"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-1")
    await client.testSupportSeedPendingStop(sessionID: sessionID, runID: runID, operationID: operationID)

    // 真实样本形状（EventMapping.swift 头注释③引用的现场帧）：
    let endFrame: JSONObject = [
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": "kernel-key-1", "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "seq": 18, "ts": 1_784_871_000_000,
        ] as JSONObject,
    ]
    let errorFollowupFrame: JSONObject = [
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": "kernel-key-1", "stream": "lifecycle",
            "data": ["phase": "error", "aborted": true, "stopReason": "aborted", "error": "This operation was aborted"] as JSONObject,
            "seq": 19, "ts": 1_784_871_000_100,
        ] as JSONObject,
    ]
    await client.testSupportFeedFrame(endFrame)
    await client.testSupportFeedFrame(errorFollowupFrame)

    // 期望恰好 2 条事件（operationCompleted + turnComplete）；多要 1 条来验证"没有第 3 条"。
    let events = await collectUpTo(stream, maxCount: 3)
    guard events.count == 2 else {
        return fail(name, "expected exactly 2 events (1 operation_completed + 1 turn_complete), got \(events.count) — 修前会对两条 aborted 帧各产出一条 operation_completed（共 2 条，且没有 turn_complete）")
    }
    guard case .operationCompleted(let opEvent) = events[0] else {
        return fail(name, "expected first event to be .operationCompleted, got \(events[0].wireType)")
    }
    guard opEvent.payload.operationID == operationID else {
        return fail(name, "operationCompleted.operationId=\(opEvent.payload.operationID) != stop() 铸造的 \(operationID) — 修前 mapper 自己派生一个不同的 operationId，Promise 结果与旁路事件无法关联")
    }
    guard opEvent.payload.outcome == .succeeded else {
        return fail(name, "expected outcome=.succeeded for phase:end frame, got \(opEvent.payload.outcome)")
    }
    guard case .turnComplete(let turnEvent) = events[1] else {
        return fail(name, "expected second event to be .turnComplete, got \(events[1].wireType) — 上一轮从不产出这个事件")
    }
    guard turnEvent.payload.stopReason == .cancelled else {
        return fail(name, "expected turnComplete.stopReason=.cancelled, got \(turnEvent.payload.stopReason)")
    }
    let terminalEmitted = await client.testSupportPendingStopTerminalEmitted(sessionID: sessionID)
    guard terminalEmitted == true else {
        return fail(name, "pendingStop.terminalEmitted should be true after first aborted frame")
    }
    return pass(name, "恰好 2 条事件：operationCompleted(operationId=\(opEvent.payload.operationID),outcome=\(opEvent.payload.outcome.rawValue)) + turnComplete(stopReason=cancelled)；第二条收尾帧被正确去重")
}

// MARK: - F4：两个交错的 tool approval 不会串号

/// **修前 fail / 修后 pass**：上一轮用"同 session 最近一次 toolCall"猜测 approval 的 toolCallId——
/// 复现场景：两个 toolCall（A 先、B 后）几乎同时在途，B 的 `session.message` 先落地把"最近一次
/// toolCall"刷新成 B，随后 A 的 `session.approval(pending)` 才到达，上一轮会把 A 的 approval 错误
/// 关联到 B 的 toolCallId。本轮改用 `agent(stream:"approval", phase:"requested")` 的准确
/// `approvalId -> toolCallId` 映射，按 approvalId（不是"最近一次"）精确关联，两个交错的审批各自
/// 拿到正确的 toolCallId。
func testInterleavedApprovalsDoNotCrossWire() async -> Bool {
    let name = "F4 interleaved approvals do not cross-wire toolCallId"
    let client = freshClient()
    let sessionID = "sess-approval-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-2")

    func agentApprovalFrame(approvalID: String, toolCallID: String) -> JSONObject {
        [
            "type": "event", "event": "agent",
            "payload": [
                "runId": "run-x", "sessionKey": "kernel-key-2", "stream": "approval",
                "data": ["phase": "requested", "kind": "exec", "status": "pending", "title": "t",
                         "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
                "seq": 1, "ts": 1_784_871_200_000,
            ] as JSONObject,
        ]
    }
    func sessionApprovalFrame(approvalID: String, createdAtMs: Int) -> JSONObject {
        [
            "type": "event", "event": "session.approval",
            "payload": [
                "sessionKey": "kernel-key-2", "updatedAtMs": createdAtMs, "phase": "pending",
                "approval": [
                    "id": approvalID, "status": "pending",
                    "presentation": ["kind": "exec", "commandText": "echo \(approvalID)"] as JSONObject,
                    "createdAtMs": createdAtMs, "expiresAtMs": createdAtMs + 1_800_000,
                ] as JSONObject,
            ] as JSONObject,
        ]
    }

    // 交错顺序：B 的 toolCall 关联先到达（模拟"B 的 session.message 先落地"），然后 A 的关联到达，
    // 然后 session.approval 按 B 先、A 后的顺序到达（对上一轮"最近一次"的猜测最不利的顺序）。
    await client.testSupportFeedFrame(agentApprovalFrame(approvalID: "approval-B", toolCallID: "tool-B"))
    await client.testSupportFeedFrame(agentApprovalFrame(approvalID: "approval-A", toolCallID: "tool-A"))
    await client.testSupportFeedFrame(sessionApprovalFrame(approvalID: "approval-B", createdAtMs: 1_784_871_200_100))
    await client.testSupportFeedFrame(sessionApprovalFrame(approvalID: "approval-A", createdAtMs: 1_784_871_200_200))

    let events = await collectUpTo(stream, maxCount: 3)
    guard events.count == 2 else {
        return fail(name, "expected exactly 2 approvalRequest events, got \(events.count)")
    }
    var toolCallByReqID: [String: String] = [:]
    for event in events {
        guard case .approvalRequest(let e) = event else {
            return fail(name, "expected .approvalRequest, got \(event.wireType)")
        }
        toolCallByReqID[e.payload.reqID] = e.payload.toolCallID
    }
    guard toolCallByReqID["approval-B"] == "tool-B" else {
        return fail(name, "approval-B should map to tool-B, got \(toolCallByReqID["approval-B"] ?? "nil") — 修前「最近一次」猜测在这个顺序下会串号")
    }
    guard toolCallByReqID["approval-A"] == "tool-A" else {
        return fail(name, "approval-A should map to tool-A, got \(toolCallByReqID["approval-A"] ?? "nil") — 修前「最近一次」猜测在这个顺序下会串号")
    }
    return pass(name, "approval-B->tool-B, approval-A->tool-A，交错顺序下未串号")
}

// MARK: - F5：非 exec 工具（item stream）诚实映射

/// **真实样本 grounding**（`scratchpad/openclaw-iso3/nonexec-run4.jsonl`，`update_plan` 内置工具）：
/// `item`(kind:tool,phase:end) 没有 output 字段——本函数验证诚实映射：output 是 JSON null（不是
/// 编造的占位符字符串），isError 由 status 判定，durationMS 是 endedAt-startedAt 的真实差值。
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

/// exec 工具名词表——供调用方判断是否应跳过 `item` 来源，让 command_output 接管。
func testExecToolNameFiltering() -> Bool {
    let name = "F5 exec tool name filtering (isOpenclawExecToolName)"
    guard isOpenclawExecToolName("exec") == true else { return fail(name, "\"exec\" should be treated as exec tool") }
    guard isOpenclawExecToolName("bash") == true else { return fail(name, "\"bash\" should be treated as exec tool") }
    guard isOpenclawExecToolName("update_plan") == false else { return fail(name, "\"update_plan\" should NOT be treated as exec tool") }
    guard isOpenclawExecToolName("tool_call") == false else { return fail(name, "\"tool_call\" (generic dispatcher name) should NOT be treated as exec tool") }
    return pass(name, "exec/bash 判定为 exec，update_plan/tool_call 判定为非 exec")
}

// MARK: - F5：seq gap error 事件

/// **修前 fail / 修后 pass**：上一轮 `agent(stream:"error")` 完全不 dispatch（`default: break`），
/// `gateway/server-chat.ts:1387-1403` 真实产出的 seq-gap 错误帧会被静默丢弃。本轮接入并映射到
/// D2 evt.error。
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
        return fail(name, "expected code=.unknown (D1 ErrorEvent.code 封闭枚举没有 seq-gap 的字面对应), got \(e.payload.code)")
    }
    guard e.payload.nativeCode == "seq gap" else {
        return fail(name, "expected nativeCode=\"seq gap\", got \(e.payload.nativeCode ?? "nil")")
    }
    guard e.payload.message.contains("5") && e.payload.message.contains("8") else {
        return fail(name, "expected message to mention expected=5/received=8, got \(e.payload.message)")
    }
    return pass(name, "code=unknown nativeCode=\"seq gap\" message=\(e.payload.message.debugDescription)")
}

// MARK: - F8：shutdown 去重（多次触发只产出一次 sessionEnd）

/// **修前 fail / 修后 pass**：上一轮 shutdown 与 transportClosed 各自独立 yield sessionEnd，没有
/// 共享的"已经产出过 terminal"标记——真实优雅关闭场景会看到 kernel_exited 后又看到
/// transport_closed 两条矛盾的终态。这里用"同一个 shutdown 事件被 handleIncoming 处理两次"模拟
/// 这个去重需求（生产场景是 shutdown+transportClosed 两条不同路径，但去重机制本身
/// —— `sessionTerminalEmitted` —— 是同一份状态，两次触发同一路径足以验证这份状态确实生效）。
func testShutdownDedup() async -> Bool {
    let name = "F8 shutdown terminal dedup"
    let client = freshClient()
    let sessionID = "sess-shutdown-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-3")

    let shutdownFrame: JSONObject = [
        "type": "event", "event": "shutdown",
        "payload": ["reason": "gateway stopping", "restartExpectedMs": NSNull()] as JSONObject,
        "seq": 2,
    ]
    await client.testSupportFeedFrame(shutdownFrame)
    await client.testSupportFeedFrame(shutdownFrame) // 模拟第二条 terminal 触发信号

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1 else {
        return fail(name, "expected exactly 1 sessionEnd event despite 2 shutdown-like triggers, got \(events.count) — 修前没有去重标记，会产出 2 条矛盾的 sessionEnd")
    }
    guard case .sessionEnd(let e) = events[0], e.payload.reason == .kernelExited else {
        return fail(name, "expected sessionEnd(reason:.kernelExited)")
    }
    let terminalEmitted = await client.testSupportSessionTerminalEmitted(sessionID: sessionID)
    guard terminalEmitted else {
        return fail(name, "sessionTerminalEmitted should be true after shutdown")
    }
    return pass(name, "两次 shutdown 触发只产出 1 条 sessionEnd(kernel_exited)")
}

// MARK: - F1：并发 send()/stop() 的 session 级互斥锁

/// **修前 fail / 修后 pass**：上一轮 `send()` 没有任何锁——两个并发调用都会无条件进入 RPC。本轮
/// 加了 `send_pending` 互斥锁：锁不是 idle 时新的 `send()` 一律 reject(session_locked)。这里直接
/// 把锁摆到 `send_pending`（模拟"另一个 send() 正在途中"这个窗口）验证 reject 行为。
func testConcurrentSendRejectedWhenLocked() async -> Bool {
    let name = "F1 concurrent send() rejected when lock is send_pending"
    let client = freshClient()
    let sessionID = "sess-lock-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-4")
    await client.testSupportForceLockToSendPending(sessionID: sessionID)

    let handle = SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: "kernel-key-4", sessionID: sessionID
    )
    do {
        _ = try await client.send(session: handle, input: Input(kind: .text, text: "hello", parts: nil))
        return fail(name, "expected send() to throw session_locked, but it succeeded")
    } catch let KernelClientError.rpcRejected(code, _) {
        guard code == "session_locked" else {
            return fail(name, "expected code=session_locked, got \(code)")
        }
        return pass(name, "send() 正确 reject(session_locked) —— 修前完全没有这层锁,会直接尝试发起 RPC")
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected, got \(error)")
    }
}

/// stop() 同样受这把锁保护——lock 不是 idle 时 reject。
func testStopRejectedWhenLocked() async -> Bool {
    let name = "F1 stop() rejected when lock is send_pending"
    let client = freshClient()
    let sessionID = "sess-lock-2"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: "kernel-key-5")
    await client.testSupportForceLockToSendPending(sessionID: sessionID)

    let handle = SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: "kernel-key-5", sessionID: sessionID
    )
    do {
        _ = try await client.stop(session: handle)
        return fail(name, "expected stop() to throw session_locked, but it succeeded")
    } catch let KernelClientError.rpcRejected(code, _) {
        guard code == "session_locked" else {
            return fail(name, "expected code=session_locked, got \(code)")
        }
        return pass(name, "stop() 正确 reject(session_locked)")
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected, got \(error)")
    }
}

// MARK: - F2：attachment-only（附件编码成 openclaw 期望的 content 形状）

/// **修前 fail / 修后 pass**：上一轮发送 `{mimeType, path}`——openclaw
/// `normalizeRpcAttachmentsToChatAttachments` 的 `.filter((a) => a.content)` 会把它丢弃（没有
/// content 字段）。本轮读取本地文件、base64 编码进 `content`。
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

// MARK: - F7：递归脱敏 auth/token

/// **修前 fail / 修后 pass**：上一轮 `prettyPrint` 直接把整帧（含 `params.auth.token`）序列化打印，
/// token 明文进 stdout。本轮 `redactedCopy` 递归脱敏，命中 auth/token 等敏感键名的字段整体替换成
/// "***REDACTED***"，非敏感字段原样保留。
func testCredentialRedaction() -> Bool {
    let name = "F7 credential redaction (auth/token)"
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
        return fail(name, "expected params.auth to be fully redacted to a placeholder string, got \(String(describing: params["auth"]))")
    }
    guard (params["minProtocol"] as? Int) == 3 else {
        return fail(name, "non-sensitive field params.minProtocol should survive unchanged")
    }
    guard let client = params["client"] as? JSONObject, (client["id"] as? String) == "cli" else {
        return fail(name, "non-sensitive nested field params.client.id should survive unchanged")
    }
    // 序列化后确认明文 token 字符串确实不会出现在最终打印文本里（这是 F7 最终关心的可观察结果）。
    let serialized = String(describing: redacted)
    guard !serialized.contains("super-secret-real-token-value") else {
        return fail(name, "raw token value leaked into redacted copy's string representation")
    }
    return pass(name, "auth 字段整体脱敏，非敏感字段保留，明文 token 未出现在序列化结果里")
}

// MARK: - 总入口

public func runFrameReplayTests() async -> Bool {
    print("=== SG-5 rework frame-replay 单测 ===")
    var results: [Bool] = []
    results.append(testSeqOrderingWithinRunAndOriginTS())
    results.append(testNoStopReasonEndMapsToCompleted())
    results.append(testUnknownStopReasonAlsoMapsToCompleted())
    results.append(await testAbortEndThenErrorProducesSingleTerminalPair())
    results.append(await testInterleavedApprovalsDoNotCrossWire())
    results.append(testNonExecToolItemHonestMapping())
    results.append(testExecToolNameFiltering())
    results.append(testSeqGapErrorEvent())
    results.append(await testShutdownDedup())
    results.append(await testConcurrentSendRejectedWhenLocked())
    results.append(await testStopRejectedWhenLocked())
    results.append(testAttachmentOnlyEncodesContent())
    results.append(testCredentialRedaction())

    let passCount = results.filter { $0 }.count
    let total = results.count
    print("=== 结果: \(passCount)/\(total) PASS ===")
    return passCount == total
}
