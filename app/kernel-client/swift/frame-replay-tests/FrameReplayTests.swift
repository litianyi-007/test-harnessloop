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
// 这个项目不用 XCTest——延续既有风格：每个测试是一个返回 `Bool`（或 `async -> Bool`）的普通函数，
// `runFrameReplayTests()` 依次跑、打印每条的 PASS/FAIL，最后返回总体是否全过。真正的可执行入口在
// `FrameReplayTestMain.swift`（同目录，SG-10 起同属 SwiftPM `frame-replay-tests` executable
// target，见 app/Package.swift）。
//
// 每个测试函数的文档注释都标注了"这条断言在修前（db489f0e）会不会失败"——凡是能够直接构造出"上一轮
// 的实现会给出错误结果"的场景，都写清楚对照的旧行为。
//
// `@testable import KernelClient`：本文件驱动的 `testSupportStubRPC`/`testSupportFeedFrame` 等
// 方法在 KernelClient target 里是 internal（刻意不公开，见 OpenclawGatewayKernelClient.swift
// 里 "MARK: - Test-only 支持面" 的注释）。KernelClient target 在 app/Package.swift 里带了
// `-enable-testing`，`@testable import` 才能跨 target 拿到这批 internal 符号——不是把它们改成了
// public。

import Foundation
@testable import KernelClient
import D2Generated

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
        cachedUsage: nil, forceResolvedApprovals: nil, nextSeq: { counter += 1; return counter }
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
        cachedUsage: nil, forceResolvedApprovals: nil, nextSeq: { counter += 1; return counter }
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
        forceResolvedApprovals: nil, nextSeq: { counter += 1; return counter }
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

// MARK: - rounds/0016：exec.approval.requested（握手补 `exec-approvals` cap 之后才收得到的那条事件）

/// 构造一条真实形状的 `exec.approval.requested` wire 帧——payload 结构逐字对齐
/// `gateway/server-methods/approval-shared.ts:255-264` `buildRequestedApprovalEvent`
/// （`{id, request, createdAtMs, expiresAtMs}`），`request` 字段集取自
/// `infra/exec-approvals.ts:225-253` `ExecApprovalRequestPayload`。
func execApprovalRequestedFrame(
    approvalID: String, kernelKey: String, runID: String?, toolCallID: String?, createdAtMs: Int
) -> JSONObject {
    var request: JSONObject = [
        "command": "echo \(approvalID)",
        "host": "gateway",
        "agentId": "main",
        "warningText": "writes outside workspace",
        "sessionKey": kernelKey,
        "allowedDecisions": ["allow-once", "deny"],
    ]
    if let runID { request["runId"] = runID }
    if let toolCallID { request["toolCallId"] = toolCallID }
    return [
        "type": "event", "event": "exec.approval.requested",
        "payload": [
            "id": approvalID, "request": request,
            "createdAtMs": createdAtMs, "expiresAtMs": createdAtMs + 1_800_000,
        ] as JSONObject,
    ]
}

/// **修前 fail / 修后 pass**：`exec.approval.requested` 此前落在 `handleIncoming` 的 `default:`
/// 分支被原样打印后丢弃（它根本没有 case）。而这条事件恰恰是"补了 `exec-approvals` cap 之后才会
/// 收到"的那条——不认它，补 cap 就只剩"审批不再被 no-approval-route 判死"这一半收益，事件本身仍
/// 然是白收的。
///
/// 本测试同时钉死两件事：
///  1. 只有 `exec.approval.requested` 一条帧（没有 session.approval、也没有
///     agent(stream:"approval")）时也能产出 `evt.approval_request`——它自带 `request.runId` 与
///     `request.toolCallId`，不需要等 agent 帧（`bash-tools.exec-approval-request.ts:97-98` 原样
///     透传）。
///  2. **reqID 必须等于 `payload.id`**，也就是 `approval.resolve` 要的那个 id
///     （`approval-shared.ts:259` `id: record.id`）——对不上就会"弹得出、点了没用"。这里直接断言
///     产出后该 reqID 已进入 respondApproval() 的 pending 表。
func testExecApprovalRequestedAloneProducesApprovalRequest() async -> Bool {
    let name = "rounds/0016: exec.approval.requested alone produces evt.approval_request with the resolve-compatible reqID"
    let client = freshClient()
    let sessionID = "sess-exec-approval-req-1"
    let kernelKey = "kernel-key-exec-approval-req-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let approvalID = "approval-exec-requested-1"
    await client.testSupportFeedFrame(execApprovalRequestedFrame(
        approvalID: approvalID, kernelKey: kernelKey,
        runID: "run-exec-requested-1", toolCallID: "tool-exec-requested-1",
        createdAtMs: 1_784_871_900_000
    ))

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected exactly 1 approvalRequest from exec.approval.requested, got \(events.count) — 修前这条事件落在 default: 分支被丢弃")
    }
    guard e.payload.reqID == approvalID else {
        return fail(name, "reqID 必须逐字等于 exec.approval.requested 的 payload.id（= approval.resolve 的 id），got \(e.payload.reqID)")
    }
    guard e.runID == "run-exec-requested-1", e.payload.toolCallID == "tool-exec-requested-1" else {
        return fail(name, "runID/toolCallID 必须取自 request.runId/request.toolCallId，got runID=\(e.runID) toolCallID=\(e.payload.toolCallID)")
    }
    guard e.payload.timeoutMS == 1_800_000 else {
        return fail(name, "timeoutMS 应为 expiresAtMs-createdAtMs=1800000，got \(e.payload.timeoutMS)")
    }
    // presentation 合成得对不对，用生产代码自己的提炼函数验（UI 卡片读的就是它）。
    let summary = summarizeApprovalPresentation(e.payload)
    guard summary.openclawKind == "exec", summary.commandText == "echo \(approvalID)",
          summary.host == "gateway", summary.agentID == "main",
          summary.allowedDecisions == [.allowOnce, .deny] else {
        return fail(name, "合成的 presentation 不对：kind=\(summary.openclawKind ?? "nil") command=\(summary.commandText ?? "nil") host=\(summary.host ?? "nil") agent=\(summary.agentID ?? "nil") allowed=\(summary.allowedDecisions)")
    }
    // 出站关联：这个 reqID 必须已经在 respondApproval() 的 pending 表里，否则用户点了按钮会被
    // 客户端以 approval_not_pending 拦下——"弹得出、点了没用"。
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "reqID \(approvalID) 未进入 respondApproval() 的 pending 表——出站决策会被自己拦下")
    }
    return pass(name, "只凭 exec.approval.requested 一条帧就产出 approval_request(reqID=\(approvalID))，字段与 approval.resolve 的 id 同源，且已可被 respondApproval() 关联")
}

/// **修前 fail / 修后 pass**（去重反证）：补上映射之后，同一次审批在 wire 上有**两条**独立事件能
/// 触发产出——`session.approval(phase:"pending")`（`operator-approval-session-events.ts:110`，与
/// caps 无关）与 `exec.approval.requested`（`approval-shared.ts:463-471`，被 caps 门禁）。真实到达
/// 顺序是 session.approval 先（`exec-approval-manager.ts:358` 在 register 内发）、
/// exec.approval.requested 后、agent(stream:"approval") 最后
/// （`embedded-agent-subscribe.handlers.tools.ts:1665-1699` 要等两阶段注册返回才发）。
///
/// 本测试按这个真实顺序喂前三条帧，再补一条**重放**的 `session.approval(pending)`——那不是杜撰的
/// 场景：`consumeApprovalReplay` 在断线重连后的 `sessions.messages.subscribe` 响应里，就是把仍处于
/// pending 的审批合成成同样形状的 `session.approval(pending)` 帧再走一遍
/// （见 `OpenclawGatewayKernelClient.consumeApprovalReplay`）。断言调用方**只**收到 1 条
/// approval_request（不是 2 条），且没有留下永远配不上对的孤儿缓冲条目。
func testExecApprovalRequestedDoesNotDoubleEmitWithSessionApproval() async -> Bool {
    let name = "rounds/0016: session.approval + exec.approval.requested + agent(approval) + 重放 三条来源只产出 1 条 approval_request"
    let client = freshClient()
    let sessionID = "sess-exec-approval-dedup-1"
    let kernelKey = "kernel-key-exec-approval-dedup-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let approvalID = "approval-exec-dedup-1"
    let createdAtMs = 1_784_872_000_000
    let sessionApprovalFrame: JSONObject = [
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": createdAtMs, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": [
                    "kind": "exec", "commandText": "echo from-session-approval",
                    "allowedDecisions": ["allow-once", "deny"],
                ] as JSONObject,
                "createdAtMs": createdAtMs, "expiresAtMs": createdAtMs + 1_800_000,
            ] as JSONObject,
        ] as JSONObject,
    ]

    // ① session.approval(pending) 先到——此刻还缺 {runId,toolCallId}，按 M1 被缓冲。
    await client.testSupportFeedFrame(sessionApprovalFrame)
    // ② exec.approval.requested 后到，带来 {runId,toolCallId}——此刻应当立即 join 并产出。
    await client.testSupportFeedFrame(execApprovalRequestedFrame(
        approvalID: approvalID, kernelKey: kernelKey,
        runID: "run-exec-dedup-1", toolCallID: "tool-exec-dedup-1", createdAtMs: createdAtMs
    ))
    // ③ agent(stream:"approval") 最后到——不得触发第二条 approval_request。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": "run-exec-dedup-1", "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": "tool-exec-dedup-1", "approvalId": approvalID] as JSONObject,
            "ts": createdAtMs + 200,
        ] as JSONObject,
    ])
    // ④ 断线重连后 approvalReplay 把同一条仍 pending 的审批重放一遍（合成帧与 ① 同形）——去重闸门
    //   被拿掉时，这一步会拿 ③ 缓存下来的 {runId,toolCallId} 补发出第二条同 reqID 的 approval_request。
    await client.testSupportFeedFrame(sessionApprovalFrame)

    let events = await collectUpTo(stream, maxCount: 3)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected exactly 1 approvalRequest across the four frames, got \(events.count) — 重复交付会让调用方误以为是两次独立审批")
    }
    guard e.payload.reqID == approvalID, e.runID == "run-exec-dedup-1", e.payload.toolCallID == "tool-exec-dedup-1" else {
        return fail(name, "unexpected fields reqID=\(e.payload.reqID) runID=\(e.runID) toolCallID=\(e.payload.toolCallID)")
    }
    // join 用的是内核自己投影出来的那份权威 presentation（来自 session.approval），不是合成的那份。
    let summary = summarizeApprovalPresentation(e.payload)
    guard summary.commandText == "echo from-session-approval" else {
        return fail(name, "已缓冲的 session.approval 权威 presentation 应当优先于合成版本，got commandText=\(summary.commandText ?? "nil")")
    }
    guard await !client.testSupportHasBufferedApproval(approvalID: approvalID) else {
        return fail(name, "四条帧都处理完之后不应该还留着双向 join 缓冲条目（孤儿条目只能等 session 结束才清）")
    }
    return pass(name, "四条帧只产出 1 条 approval_request（reqID=\(approvalID)），采用 session.approval 的权威 presentation，且无孤儿缓冲残留")
}

// MARK: - rounds/0016 live 实测：agent(stream:"lifecycle", phase:"waiting-approval") 关联采集

/// **修前 fail / 修后 pass**：live 隔离实例（`ask=always`，客户端已声明 `caps:["exec-approvals"]`）
/// 实测到的 `agent` 关联帧根本不是 `stream:"approval"`+`phase:"requested"`，而是
/// **`stream:"lifecycle"`+`phase:"waiting-approval"`**——webchat 是 native approval channel，exec
/// 走的是内联等待分支（`bash-tools.exec-host-gateway.ts:414-428` `shouldAwaitGatewayApprovalInline()`
/// → `:1085-1091` `emitAgentEvent({stream:"lifecycle", data:{phase:"waiting-approval", ...}})`）。
/// 修前采集处只认 `"requested"`，这条帧落进 `case "lifecycle"` 被 end/error 守卫丢弃，
/// `session.approval(phase:"pending")` 因此永远等不到 `{runId,toolCallId}`，`producedEvents` 为空、
/// UI 上没有审批卡片（界面停在"等待回复…"）。
///
/// 本测试的两条帧**逐字取自冻结的真实 wire trace**，不是构造的：
/// `.harnessloop/goals/20260718-002-agent-app/rounds/0015/evidence/live/raw/approval-frames-extract.json`
/// （同源于 `r15b-wire.jsonl`）。到达顺序也与实测一致：`session.approval` 先、`agent` 后
/// （createdAtMs 1786476738788 → ts 1786476738938）。
func testAgentLifecycleWaitingApprovalJoinsRealFrozenFrames() async -> Bool {
    let name = "rounds/0016 live: agent(stream:lifecycle, phase:waiting-approval) 真实帧能与 session.approval join 出 approval_request"
    let client = freshClient()
    let sessionID = "sess-waiting-approval-live-1"
    // 真实 sessionKey（冻结帧 payload.sessionKey / payload.sourceSessionKey 同值）。
    let kernelKey = "agent:main:dashboard:5f25e610-69b4-4cc6-af3b-fd2d65f0c8ff"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let approvalID = "d09b3b34-874e-4c95-b363-8680c1fb6b20"
    let toolCallID = "call_00_hcUZ27OoJFUsBDkJ08M47382"
    let runID = "6208dd06-d45c-4f46-b146-b1a6164f3675"

    // ① 冻结帧 #1：session.approval(phase:"pending")。字段逐字照抄，含 openclaw 真实送出的 null
    //   （commandPreview/nodeId/warningText），用 NSNull() 如实表示，不悄悄删掉。
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "approval": [
                "createdAtMs": 1_786_476_738_788,
                "expiresAtMs": 1_786_478_538_788,
                "id": approvalID,
                "presentation": [
                    "agentId": "main",
                    "allowedDecisions": ["allow-once", "deny"],
                    "commandPreview": NSNull(),
                    "commandText": "echo APPROVAL_GATE_OK",
                    "host": "gateway",
                    "kind": "exec",
                    "nodeId": NSNull(),
                    "warningText": NSNull(),
                ] as JSONObject,
                "status": "pending",
                "urlPath": "/approve/\(approvalID)",
            ] as JSONObject,
            "phase": "pending",
            "sessionKey": kernelKey,
            "sourceSessionKey": kernelKey,
            "updatedAtMs": 1_786_476_738_788,
        ] as JSONObject,
    ])

    // 此刻还缺 {runId,toolCallId}——按 M1 双向 join 应当处于缓冲态（修前也是这一步，问题在下一步）。
    guard await client.testSupportHasBufferedApproval(approvalID: approvalID) else {
        return fail(name, "expected the real session.approval(pending) frame to be buffered while waiting for the agent frame")
    }

    // ② 冻结帧 #2：agent(stream:"lifecycle", data.phase:"waiting-approval")。**这条就是修前被丢弃的
    //   那条**——把采集处的 phase 判定改回 "requested" 或把它交回 end/error 守卫，本条测试即变红。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "agentId": "main",
            "data": [
                "approvalId": approvalID,
                "phase": "waiting-approval",
                "toolCallId": toolCallID,
            ] as JSONObject,
            "isHeartbeat": false,
            "runId": runID,
            "seq": 623,
            "sessionId": "fb677311-e166-4f60-9ca9-8748b5990594",
            "sessionKey": kernelKey,
            "stream": "lifecycle",
            "ts": 1_786_476_738_938,
        ] as JSONObject,
    ])

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 1, case .approvalRequest(let e) = events[0] else {
        return fail(name, "expected exactly 1 approval_request once the real lifecycle/waiting-approval frame lands, got \(events.count) — 修前这条 agent 帧被 end/error 守卫丢弃，producedEvents 为空、UI 无审批卡片")
    }
    guard e.payload.reqID == approvalID else {
        return fail(name, "reqID 必须是内核的 approvalId \(approvalID)，got \(e.payload.reqID)")
    }
    guard e.payload.toolCallID == toolCallID else {
        return fail(name, "toolCallID 必须取自这条 lifecycle 帧的 data.toolCallId \(toolCallID)，got \(e.payload.toolCallID)")
    }
    guard e.runID == runID else {
        return fail(name, "runID 必须取自这条 agent 帧自己的 payload.runId \(runID)，got \(e.runID)")
    }
    // 卡片能真正渲染出来（而不是只产出一条空壳事件）：presentation 是内核那份权威 payload。
    let summary = summarizeApprovalPresentation(e.payload)
    guard summary.commandText == "echo APPROVAL_GATE_OK" else {
        return fail(name, "UI 卡片的命令文本应当来自真实 presentation，got \(summary.commandText ?? "nil")")
    }
    guard await !client.testSupportHasBufferedApproval(approvalID: approvalID) else {
        return fail(name, "join 成功后不应再残留双向 join 缓冲条目")
    }
    return pass(name, "真实冻结帧 lifecycle/waiting-approval 正确 join 出 approval_request(reqID=\(approvalID), toolCallID=\(toolCallID), runID=\(runID))，命令文本=\(summary.commandText ?? "nil")")
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

// MARK: - M3（D1 §6.2）：stop() 强制定序——pending approval 必须先 force-deny 再 abort

/// 供下面两个新测试记录 RPC 调用顺序的最小线程安全日志——用 `actor` 而不是 `NSLock`（避免重蹈本文件
/// 里 `RaceBox` 已经踩过的"Swift 6 里 NSLock 在 async 上下文不可用"警告）。
actor CallOrderLog {
    private(set) var entries: [String] = []
    func record(_ method: String) { entries.append(method) }
}

/// **修前（SG-8.7 形式化 parity 复核揪出）fail / 修后 pass**：D1 §6.2 M3 定序要求 stop() 在发起
/// `sessions.abort` 之前，若该 run 存在 pending approval，必须先把它强制 deny 掉并确认内核已接受，
/// 再发起 abort；被强制终态化的 reqId 还要同步列进该 run `TurnCompleteEvent.forceResolvedApprovals`。
/// 修前 `stop()` 完全没有这一步——直接发 `sessions.abort`，`forceResolvedApprovals` 两处硬编码 nil。
/// 本测试驱动真实 `stop()` 方法体（不是 seed 内部状态）：先用真实 agent/session.approval 帧走完整的
/// M1 双向 join 产出一条 approvalRequest（这个 reqId 因此真正进入"pending 等待决策"态），再调用
/// `stop()`，用一个调用顺序日志断言 `approval.resolve` 确实先于 `sessions.abort` 被调用，且
/// `TurnCompleteEvent.forceResolvedApprovals` 确实带上了这个 reqId。
func testStopForceDeniesPendingApprovalBeforeAbort() async -> Bool {
    let name = "M3 (D1 §6.2) stop() force-denies pending approval BEFORE sessions.abort; TurnCompleteEvent.forceResolvedApprovals lists it"
    let client = freshClient()
    let sessionID = "sess-stop-force-deny"
    let kernelKey = "kernel-key-stop-force-deny"
    let runID = "run-force-deny-1"
    let approvalID = "approval-force-deny-1"
    let toolCallID = "tool-force-deny-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()

    // 1) 用真实 agent(stream:"approval") + session.approval(phase:"pending") 两条帧走完整 M1 双向
    // join——这是这次审批真正"产出给调用方"的唯一路径,只有走完这条路径,reqId 才会进入 M3 新增的
    // pendingApprovalsByReqID 态。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
            "ts": 1_784_872_000_000,
        ] as JSONObject,
    ])
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_872_000_100, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo force-deny-me"] as JSONObject,
                "createdAtMs": 1_784_872_000_100, "expiresAtMs": 1_784_873_800_100,
            ] as JSONObject,
        ] as JSONObject,
    ])

    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "expected approvalID to be registered as pending-awaiting-decision after the approvalRequest join")
    }

    // 2) 三个 RPC 桩——都记录调用顺序;approval.resolve 额外校验 params 形状 + 回一个真实的 denied
    // 终态响应(不是随便什么 ok:true)。
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

    async let stopResult = client.stop(session: handle)
    // stop() 此刻应该已经完成 force-deny、发起了 sessions.abort、正在等待该 run 的 aborted lifecycle
    // 终态——喂一条真实形状的 aborted lifecycle 帧唤醒等待。
    try? await Task.sleep(nanoseconds: 60_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_000_500,
        ] as JSONObject,
    ])

    guard let result = try? await stopResult else { return fail(name, "stop() unexpectedly threw") }
    guard result.outcome == .succeeded else {
        return fail(name, "expected Promise outcome=.succeeded, got \(result.outcome)")
    }

    // 3) 调用顺序——M3 定序的核心断言：force-deny 必须先于 abort（修前压根没有 approval.resolve 这
    // 一条调用，这条断言在修前会直接 fail）。
    let order = await callLog.entries
    guard order == ["approval.resolve", "sessions.abort", "sessions.delete"] else {
        return fail(name, "expected RPC call order [approval.resolve, sessions.abort, sessions.delete], got \(order) — 修前 approval.resolve 从未被调用")
    }

    // 4) 事件流：approvalRequest（步骤 1 产出）-> operation_completed(succeeded) -> turn_complete
    // (cancelled, forceResolvedApprovals 含 approvalID) -> session_end(stopped)——turn_complete 先于
    // session_end 沿用既有 D1 §9.3 顺序保证。
    let events = await collectUpTo(stream, maxCount: 5)
    guard events.count == 4 else {
        return fail(name, "expected 4 events (approvalRequest + operation_completed + turn_complete + session_end), got \(events.count)")
    }
    guard case .approvalRequest(let approvalEvent) = events[0], approvalEvent.payload.reqID == approvalID else {
        return fail(name, "expected first event approvalRequest(reqID=\(approvalID))")
    }
    guard case .operationCompleted(let op) = events[1], op.payload.outcome == .succeeded else {
        return fail(name, "expected second event operation_completed(succeeded)")
    }
    guard case .turnComplete(let turn) = events[2], turn.payload.stopReason == .cancelled else {
        return fail(name, "expected third event turn_complete(cancelled)")
    }
    guard let forceResolved = turn.payload.forceResolvedApprovals, forceResolved == [approvalID] else {
        return fail(name, "expected turn_complete.forceResolvedApprovals == [\(approvalID)], got \(turn.payload.forceResolvedApprovals.map { "\($0)" } ?? "nil") — 修前这两处硬编码 nil")
    }
    guard case .sessionEnd(let end) = events[3], end.payload.reason == .stopped else {
        return fail(name, "expected fourth event session_end(stopped) — must come AFTER turn_complete (D1 §9.3)")
    }

    // 5) reqId 不再残留在"pending 等待决策"态——force-deny 序列必须把它清掉。
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) == false else {
        return fail(name, "expected approvalID to no longer be pending-awaiting-decision after stop() force-denied it")
    }

    return pass(name, "approval.resolve 先于 sessions.abort 被调用(调用顺序=\(order)),TurnCompleteEvent.forceResolvedApprovals=[\(approvalID)],turn_complete 先于 session_end")
}

/// **回归/parity 检查**：没有 pending approval 的普通 stop() 不应该触发任何 `approval.resolve` 调用
/// （没 stub 该方法时如果真的调用会因为"没有真实连接也没有测试桩"而 `throw
/// KernelClientError.notConnected`,直接让 stop() 失败——本测试因此隐式覆盖"M3 新逻辑不会在无 pending
/// approval 时误触发 RPC"这条要求),且该 run 的 `TurnCompleteEvent.forceResolvedApprovals` 保持 nil,
/// 不因为新增了 M3 逻辑就意外冒出一个空数组或别的值。
func testStopWithNoPendingApprovalLeavesForceResolvedApprovalsNil() async -> Bool {
    let name = "M3 (D1 §6.2) stop() with no pending approval: no approval.resolve call, forceResolvedApprovals stays nil"
    let client = freshClient()
    let sessionID = "sess-stop-no-pending-approval"
    let kernelKey = "kernel-key-stop-no-pending-approval"
    let runID = "run-no-pending-approval-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": ["runId": runID, "sessionKey": kernelKey, "stream": "run_status", "data": [:] as JSONObject] as JSONObject,
    ])
    // 故意不 stub "approval.resolve"——如果 stop() 意外调用了它,会因为没有测试桩/真实连接而抛
    // notConnected,下面的 `try? await stopResult` 会拿到 nil,测试直接 fail。
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    async let stopResult = client.stop(session: handle)
    try? await Task.sleep(nanoseconds: 60_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_100_000,
        ] as JSONObject,
    ])

    guard let result = try? await stopResult else {
        return fail(name, "stop() unexpectedly threw — 若因为误触发 approval.resolve(无 stub) 而抛 notConnected 也会落到这里")
    }
    guard result.outcome == .succeeded else { return fail(name, "expected outcome=.succeeded, got \(result.outcome)") }

    let events = await collectUpTo(stream, maxCount: 4)
    guard events.count == 3, case .operationCompleted = events[0], case .turnComplete(let turn) = events[1] else {
        return fail(name, "expected 3 events (operation_completed + turn_complete + session_end), got \(events.count)")
    }
    guard turn.payload.forceResolvedApprovals == nil else {
        return fail(name, "expected forceResolvedApprovals == nil when there was no pending approval, got \(turn.payload.forceResolvedApprovals ?? [])")
    }
    return pass(name, "无 pending approval 时: 未触发 approval.resolve, forceResolvedApprovals 保持 nil")
}

// MARK: - NOTE-A（T-049 grok 对抗审复核）：force-deny drain 循环闭合 await 窗口逃逸

/// **修前 fail / 修后 pass**：修前 `forceDenyPendingApprovalsBeforeStop` 只对 pending reqId 取一次
/// 快照——若某个 approval 在 `approval.resolve` 的 await 窗口内新到（这里用真实的
/// `agent(stream:"approval")` + `session.approval(phase:"pending")` 两条帧、在 approval-A 的
/// `approval.resolve` 响应闭包**返回前**同步 feed 给 client，借助 actor 重入性确定性地模拟"drain
/// 在途"这个窗口，不依赖任何 sleep/时序竞速），会逃过这一轮快照、永远不会被 force-deny，随后
/// `sessions.abort` 仍会照发——修前这条测试会在"调用顺序断言"处直接 fail（call log 里只有
/// `approval.resolve:\(approvalA)`，没有 approvalB）。本轮改为 drain-loop：每一轮结束后重新检查该
/// session 是否有新到的 pending 审批，直到某轮检查为空才允许 `stop()` 继续发 `sessions.abort`——
/// approvalB 因此在第二轮被同样地 force-deny 并确认，且两次 `approval.resolve` 都先于
/// `sessions.abort`。
func testStopForceDeniesLateArrivingApprovalDuringDrainAwaitWindow() async -> Bool {
    let name = "NOTE-A (T-049) stop() force-deny drain closes await-window escape: approval joined WHILE approval.resolve(A) is in flight is also force-denied before sessions.abort"
    let client = freshClient()
    let sessionID = "sess-stop-force-deny-late-arrival"
    let kernelKey = "kernel-key-stop-force-deny-late-arrival"
    let runID = "run-force-deny-late-1"
    let approvalA = "approval-force-deny-late-A"
    let approvalB = "approval-force-deny-late-B"
    let toolCallA = "tool-force-deny-late-A"
    let toolCallB = "tool-force-deny-late-B"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()

    // 1) 先让 approval-A 走完整 M1 双向 join，进入 pending-awaiting-decision 态——这是 force-deny
    // drain 循环第一轮快照会看到的唯一 reqId。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallA, "approvalId": approvalA] as JSONObject,
            "ts": 1_784_900_000_000,
        ] as JSONObject,
    ])
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_900_000_100, "phase": "pending",
            "approval": [
                "id": approvalA, "status": "pending",
                "presentation": ["kind": "exec", "commandText": "echo late-arrival-A"] as JSONObject,
                "createdAtMs": 1_784_900_000_100, "expiresAtMs": 1_784_901_800_100,
            ] as JSONObject,
        ] as JSONObject,
    ])
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalA) else {
        return fail(name, "expected approvalA to be registered as pending-awaiting-decision before stop()")
    }

    // 2) approval.resolve 的响应闭包本身是在 forceDenyPendingApprovalsBeforeStop 的 `await
    // request(...)` 里被调用——这次响应返回之前，借助 actor 重入性直接调用 `testSupportFeedFrame`
    // 注入 approval-B 的两条真实帧，精确复现 NOTE-A 描述的"drain await 窗口内新到"场景。`reqID ==
    // approvalA` 这个分支只会命中一次——approvalA 一旦被这次 RPC 处理完就从 pending 表移除，不会
    // 再出现在后续任何一轮的快照里，因此不需要额外的"只注入一次"标记（避免捕获可变 var 触发 Swift
    // 6 并发检查）。
    await client.testSupportStubRPC(method: "approval.resolve") { params in
        let reqID = (params["id"] as? String) ?? "?"
        await callLog.record("approval.resolve:\(reqID)")
        if reqID == approvalA {
            await client.testSupportFeedFrame([
                "type": "event", "event": "agent",
                "payload": [
                    "runId": runID, "sessionKey": kernelKey, "stream": "approval",
                    "data": ["phase": "requested", "toolCallId": toolCallB, "approvalId": approvalB] as JSONObject,
                    "ts": 1_784_900_000_200,
                ] as JSONObject,
            ])
            await client.testSupportFeedFrame([
                "type": "event", "event": "session.approval",
                "payload": [
                    "sessionKey": kernelKey, "updatedAtMs": 1_784_900_000_300, "phase": "pending",
                    "approval": [
                        "id": approvalB, "status": "pending",
                        "presentation": ["kind": "exec", "commandText": "echo late-arrival-B"] as JSONObject,
                        "createdAtMs": 1_784_900_000_300, "expiresAtMs": 1_784_901_900_300,
                    ] as JSONObject,
                ] as JSONObject,
            ])
        }
        return ["applied": true, "approval": ["id": reqID, "status": "denied", "decision": "deny", "reason": "user"] as JSONObject] as JSONObject
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

    async let stopResult = client.stop(session: handle)
    try? await Task.sleep(nanoseconds: 60_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_900_001_000,
        ] as JSONObject,
    ])

    guard let result = try? await stopResult else { return fail(name, "stop() unexpectedly threw") }
    guard result.outcome == .succeeded else {
        return fail(name, "expected Promise outcome=.succeeded, got \(result.outcome)")
    }

    // 3) 核心断言——修前：approvalB 会逃过快照，call log 里永远只有 approvalA 一条 approval.resolve；
    // 修后：两次 approval.resolve 都先于 sessions.abort。
    let order = await callLog.entries
    guard let abortIndex = order.firstIndex(of: "sessions.abort"),
          let aIndex = order.firstIndex(of: "approval.resolve:\(approvalA)"),
          let bIndex = order.firstIndex(of: "approval.resolve:\(approvalB)"),
          aIndex < abortIndex, bIndex < abortIndex
    else {
        return fail(name, "expected both approval.resolve(A) and approval.resolve(B) before sessions.abort, got order=\(order) — 修前 approvalB 永远不会出现在这里（逃过 force-deny）")
    }

    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalA) == false else {
        return fail(name, "expected approvalA to no longer be pending-awaiting-decision after stop()")
    }
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalB) == false else {
        return fail(name, "expected approvalB (late arrival) to no longer be pending-awaiting-decision after stop() — 修前这里会是 true，即 NOTE-A 描述的逃逸")
    }

    // 4) forceResolvedApprovals 必须同时列出 A 和 B——这是"内核已确认 both denied"的事件流侧证据。
    let events = await collectUpTo(stream, maxCount: 6)
    guard events.count == 5 else {
        return fail(name, "expected 5 events (approvalRequest(A) + approvalRequest(B) + operation_completed + turn_complete + session_end), got \(events.count)")
    }
    guard case .approvalRequest(let firstApproval) = events[0], firstApproval.payload.reqID == approvalA else {
        return fail(name, "expected first event approvalRequest(reqID=\(approvalA))")
    }
    guard case .approvalRequest(let secondApproval) = events[1], secondApproval.payload.reqID == approvalB else {
        return fail(name, "expected second event approvalRequest(reqID=\(approvalB)) — late arrival must still be delivered to the caller before being force-denied")
    }
    guard case .operationCompleted(let op) = events[2], op.payload.outcome == .succeeded else {
        return fail(name, "expected third event operation_completed(succeeded)")
    }
    guard case .turnComplete(let turn) = events[3], turn.payload.stopReason == .cancelled else {
        return fail(name, "expected fourth event turn_complete(cancelled)")
    }
    guard let forceResolved = turn.payload.forceResolvedApprovals, Set(forceResolved) == Set([approvalA, approvalB]) else {
        return fail(name, "expected turn_complete.forceResolvedApprovals to contain both \(approvalA) and \(approvalB), got \(turn.payload.forceResolvedApprovals.map { "\($0)" } ?? "nil") — 修前只有 \(approvalA)，approvalB 逃逸")
    }
    guard case .sessionEnd(let end) = events[4], end.payload.reason == .stopped else {
        return fail(name, "expected fifth event session_end(stopped)")
    }

    return pass(name, "late-arriving approvalB（在 approval.resolve(A) 的 await 窗口内新到）也被 force-deny，调用顺序=\(order)，forceResolvedApprovals 含两者")
}

/// **有界性回归**：force-deny drain 循环必须有迭代轮次上限兜底——构造一个"持续不断产生新 pending
/// 审批"的极端场景（每次 `approval.resolve` 响应返回前都再注入一个新的），把
/// `testSupportSetForceDenyDrainMaxRounds` 调到很小的值（2），断言 `stop()` 在超过这个上限时**如实
/// throw**（不是静默截断继续 abort，也不是无限循环挂起），且既有 M3 catch 分支的收尾（锁释放 +
/// pendingStop 清理 + operation_completed(rejected) 镜像）依然生效——这条新的失败路径不能绕开既有
/// 收尾逻辑。
func testStopForceDenyDrainExceedsRoundCapThrowsAndReleasesLock() async -> Bool {
    let name = "NOTE-A (T-049) stop() force-deny drain exceeding round cap throws honestly (not a silent infinite loop); lock released + pendingStop cleaned"
    let client = freshClient()
    let sessionID = "sess-stop-force-deny-drain-cap"
    let kernelKey = "kernel-key-stop-force-deny-drain-cap"
    let runID = "run-force-deny-drain-cap-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportSetForceDenyDrainMaxRounds(2)

    // 用一个 actor 承载"持续产生新 pending 审批"的计数器——避免在 `@Sendable` RPC 响应闭包里捕获
    // 可变 var（Swift 6 并发检查会拒绝）。
    actor DrainCapFeeder {
        let client: OpenclawGatewayKernelClient
        let sessionID: String
        let kernelKey: String
        let runID: String
        private var counter = 0
        init(client: OpenclawGatewayKernelClient, sessionID: String, kernelKey: String, runID: String) {
            self.client = client
            self.sessionID = sessionID
            self.kernelKey = kernelKey
            self.runID = runID
        }
        @discardableResult
        func feedNext() async -> String {
            counter += 1
            let approvalID = "approval-drain-cap-\(counter)"
            let toolCallID = "tool-drain-cap-\(counter)"
            await client.testSupportFeedFrame([
                "type": "event", "event": "agent",
                "payload": [
                    "runId": runID, "sessionKey": kernelKey, "stream": "approval",
                    "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
                    "ts": 1_784_900_100_000 + Int64(counter) * 100,
                ] as JSONObject,
            ])
            await client.testSupportFeedFrame([
                "type": "event", "event": "session.approval",
                "payload": [
                    "sessionKey": kernelKey, "updatedAtMs": 1_784_900_100_050 + Int64(counter) * 100, "phase": "pending",
                    "approval": [
                        "id": approvalID, "status": "pending",
                        "presentation": ["kind": "exec", "commandText": "echo drain-cap-\(counter)"] as JSONObject,
                        "createdAtMs": 1_784_900_100_050, "expiresAtMs": 1_784_901_900_050,
                    ] as JSONObject,
                ] as JSONObject,
            ])
            return approvalID
        }
    }
    let feeder = DrainCapFeeder(client: client, sessionID: sessionID, kernelKey: kernelKey, runID: runID)
    _ = await feeder.feedNext() // 种下第一个 pending 审批——stop() 调用前就已存在。

    await client.testSupportStubRPC(method: "approval.resolve") { params in
        // 每次 approval.resolve 响应返回前都再注入一个新的 pending 审批——模拟"run 持续不断请求
        // 审批"的极端场景，逼迫 drain 循环一直发现非空快照。
        await feeder.feedNext()
        let reqID = (params["id"] as? String) ?? "?"
        return ["applied": true, "approval": ["id": reqID, "status": "denied", "decision": "deny", "reason": "user"] as JSONObject] as JSONObject
    }
    // 故意不 stub sessions.abort/sessions.delete——drain 理应在到达轮次上限时就 throw，压根不会
    // 发出 sessions.abort；如果它错误地继续往下走，会因为没有 stub 而 notConnected，同样能让下面的
    // "expected .protocolMismatch" 断言失败，暴露出这条回归本身出了问题。
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    do {
        _ = try await client.stop(session: handle)
        return fail(name, "expected stop() to throw once force-deny drain exceeds the round cap, but it returned a result — 未设上限时会在这里静默挂起或无限循环")
    } catch let error as KernelClientError {
        guard case .protocolMismatch(let message) = error, message.contains("drain") else {
            return fail(name, "expected KernelClientError.protocolMismatch mentioning the drain bound, got \(error)")
        }
    } catch {
        return fail(name, "expected KernelClientError.protocolMismatch, got \(error)")
    }

    guard await client.testSupportLockState(sessionID: sessionID) == "idle" else {
        return fail(name, "expected session lock released back to idle after drain-cap failure — 不能重蹈 codex 复现的 second-stop session_locked 类锁泄漏")
    }
    guard await client.testSupportHasPendingStop(sessionID: sessionID) == false else {
        return fail(name, "expected pendingStop to be cleaned up after drain-cap failure")
    }

    return pass(name, "force-deny drain 在持续新到审批下于第 3 轮（上限=2）如实 throw，未静默死循环，session 锁/pendingStop 收尾干净")
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

// MARK: - rounds/0012 ①'：messageID 透传离线破坏性反证（KernelClient/EventMapping 层）

/// **rounds/0013 B2 订正**：下面这段"范围说明"写于 rounds/0012，当时的限制（`frame-replay-tests`
/// 够不到 `SessionStore`、本轮 Allowed Changes 未授权改 Package.swift）**已在 rounds/0013 B2 解除**
/// ——`app/Package.swift` 新增了 `AgentShellCore` library target（模型层从 `AgentShell` 拆出），
/// `frame-replay-tests` 现在显式依赖它并 `@testable import`，`SessionStore.handle(_:for:)` 也从
/// `private` 放宽到 internal（细节见 app/Package.swift 该 target 定义处、
/// SessionStore.swift 该方法上方的文档注释）。**下面这条测试本身没有变**——它验的是
/// kernel-client wire-mapping 层（messageID 透传），这是一个独立、仍然成立的正确性属性，不是
/// SessionStore 分组行为的替代品，继续保留。SessionStore 层的分组行为现在有了直接的入库测试：见
/// 本 target 内 `SessionStoreGroupingTests.swift` 的
/// `testSessionStoreHandleGroupsDistinctMessageIDsAsSeparateMessages`——下面这段关于"SessionStore
/// 的独立验证不在本 target 内、要去任务报告找"的描述已经过时，那条验证现在就在本 target 内、
/// 入库常驻。以下原文保留作为 rounds/0012 时点的历史记录：
///
/// **范围说明（诚实标注,不是回避)**：scope-lock rounds/0012 §①' 要求的破坏性反证原文是"喂两条
/// messageId 不同、runId 相同、index 均为 0 的 session.message 帧,断言它们不被合并成一条"。真正
/// 执行"是否合并成一条气泡"这个决策的代码是 `SessionStore.appendAssistantDelta`
/// （app/apps/AgentShell/Sources/AgentShell/SessionStore.swift）——但 `frame-replay-tests` 这个
/// target 按 app/Package.swift 的依赖声明只依赖 `KernelClient`+`D2Generated`（见该文件
/// `.executableTarget(name: "frame-replay-tests", dependencies: ["KernelClient", "D2Generated"], ...)`），
/// 够不到姊妹 executableTarget `AgentShell`；`SessionStore`/`appendAssistantDelta` 本身也是
/// `private`（Swift 的 file-private 语义,同模块其它文件同样访问不到），本轮 Allowed Changes 也没有
/// 授权改 Package.swift 去连通两者或放宽 SessionStore 的访问级别。（**rounds/0013 起不再成立，见
/// 上方订正**。）
///
/// 因此本测试改为断言 FrameReplayTests 实际够得到的那一层——kernel-client 的真实 dispatch 路径
/// （`handleIncoming` -> `handleSessionMessageEvent` -> `mapOpenclawSessionMessageToKernelEvents`，
/// 全部走生产代码本身,不是重新实现一遍判断)：两条 messageId 不同、runId 相同、index 均为 0
/// 的真实形状 wire 帧,各自产出一个独立的 `evt.message.delta`,且两个事件的 `payload.messageID`
/// 互异、均非 nil。这正是 SessionStore 新分组逻辑赖以工作的必要前提——SessionStore 按 messageID
/// 做字典键分组,这里的 messageID 一旦缺失或雷同,SessionStore 的分组必然失效(退化成到处开新气泡,
/// 或者更糟——错误合并回本轮要修的重复 bug)。（rounds/0012 时点：）SessionStore 实际改动本身的
/// 独立红→绿验证（不在本 target 内,原因见上）记在本轮任务报告"破坏性反证"一节，使用的是从
/// SessionStore.swift 逐字抽出的分组算法本体（非重新实现），针对真实 D2Generated 事件类型在
/// scratchpad 里跑，同样先红后绿。
///
/// **修前 fail / 修后 pass**：本测试断言的 `event.payload.messageID` 字段本身是本轮新增（D2 schema
/// `events/message-delta.schema.json` 的 `MessageDeltaPayload.messageId`，rounds/0012 之前
/// `MessageDeltaEventMessagePayload` 连这个属性都不存在，这条断言字面上无法编写）。红→绿演示：把
/// `EventMapping.swift` 里 `mapOpenclawSessionMessageToKernelEvents` 的
/// `let messageID = jsonString(payload["messageId"])` 临时改回 `let messageID: String? = nil`
/// （模拟"字段已加进 schema/codegen,但适配器还没接上"这一中间态,即本轮 Swift 侧改动之前的状态)、
/// 重新编译重跑,本测试如实变红（两个事件的 messageID 均为 nil）；改回真实读取后重新编译重跑转绿。
/// 实际红/绿两次输出见任务报告，不在此文件重复记录（本文件本身在报告落笔时已经是"改回真实读取"的
/// 绿态最终版本，符合 scope-lock「不得手改 app/generated/」之外的所有既有校验要求）。
func testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs() async -> Bool {
    let name = "rounds/0012 ①' two DIFFERENT assistant messages sharing (runId, index=0) — the old collision shape — get distinct non-nil messageID from the real session.message dispatch path"
    let client = freshClient()
    let sessionID = "sess-dup-msg-1"
    let kernelKey = "kernel-key-dup-msg-1"
    let runID = "run-dup-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // 帧形状照抄真实样本（rounds/0012 evidence/raw/wire-trace.jsonl，见 evidence/
    // instrumented-run-findings.md §1.2 的 REPRO：同一个 runId 下，注入失败先后产出两条不同的
    // assistant 消息帧，真实样本里两者 index 皆为 0——session.message 层不做增量投递，一条消息只有
    // 一个 content block，见该 evidence §1.1）。`session.activeRunIds` 是
    // `handleSessionMessageEvent` 用来刷新 `runIDHint` 缓存的真实字段路径（不是 payload 顶层的
    // 同名字段，见该函数实现）。
    func sessionMessageFrame(messageID: String, messageSeq: Int, text: String) -> JSONObject {
        [
            "type": "event", "event": "session.message",
            "payload": [
                "sessionKey": kernelKey,
                "messageId": messageID,
                "messageSeq": messageSeq,
                "session": ["activeRunIds": [runID]] as JSONObject,
                "message": [
                    "role": "assistant",
                    "content": text,
                    "timestamp": 1_785_926_400_000,
                ] as JSONObject,
            ] as JSONObject,
        ]
    }

    await client.testSupportFeedFrame(sessionMessageFrame(messageID: "msg-dup-A", messageSeq: 4, text: "first reply text"))
    await client.testSupportFeedFrame(sessionMessageFrame(messageID: "msg-dup-B", messageSeq: 6, text: "second reply text"))

    let events = await collectUpTo(stream, maxCount: 2)
    guard events.count == 2 else {
        return fail(name, "expected exactly 2 messageDelta events (one per distinct wire frame), got \(events.count)")
    }
    guard case .messageDelta(let first) = events[0], case .messageDelta(let second) = events[1] else {
        return fail(name, "expected both events to be .messageDelta, got \(events[0].wireType)/\(events[1].wireType)")
    }
    guard first.runID == runID, second.runID == runID, first.payload.index == 0, second.payload.index == 0 else {
        return fail(name, "expected both events to share runId=\(runID) and index=0 (the exact collision shape of the old (runId,index) key), got runIDs=(\(first.runID ?? "nil"),\(second.runID ?? "nil")) indices=(\(first.payload.index),\(second.payload.index))")
    }
    guard let firstID = first.payload.messageID, let secondID = second.payload.messageID else {
        return fail(name, "expected both events to carry a non-nil messageID, got first=\(first.payload.messageID ?? "nil") second=\(second.payload.messageID ?? "nil") — 若 messageID 缺失，SessionStore 无法区分这两条消息，分组会退化或重新引入本轮要修的重复 bug")
    }
    guard firstID != secondID else {
        return fail(name, "expected DISTINCT messageIDs for two distinct wire frames, got both=\(firstID) — 若相同，SessionStore 按 messageID 分组会把两条不同消息误判成同一条，重新引入本轮要修的重复 bug")
    }
    guard firstID == "msg-dup-A", secondID == "msg-dup-B" else {
        return fail(name, "expected messageID to faithfully carry through wire payload.messageId (msg-dup-A/msg-dup-B), got \(firstID)/\(secondID)")
    }
    return pass(name, "两条共享 runId=\(runID)、index=0（旧键会撞车的形状）的不同 assistant 消息，各自的 evt.message.delta.payload.messageID 正确透传且互异（\(firstID) ≠ \(secondID))——SessionStore 按 messageID 分组不会再把它们误判成同一条")
}

// MARK: - rounds/0012 ② 二次返工：subscribe() 恢复 D1 契约（不等 ack）+ send/stop 侧屏障

/// **推翻上一版同名断言（原 `testSubscribeReturnsOnlyAfterServerSubscriptionAckArrives`，断言
/// `subscribe()` 等 ack 才返回）**——那条断言本身就是被推翻的行为，保留会锁死错误方向，已删除，
/// 改成断言相反的事实：`subscribe()` **不等** ack，立即返回。
///
/// 推翻理由（详见 `OpenclawGatewayKernelClient.subscribe()` 文档注释，此处只摘要）：等 ack 违反
/// D1（`KernelClient.swift` 协议文档注释明文："语义上仍然等价于『拿到一个事件流』"），且打穿 CI——
/// `SwiftFixtureRunner.swift` 对 `subscribe` 是直接 `await`（不像 send/stop 包一层背景 Task），
/// 而 `app/contracts/d2/fixtures/` 下 10/11 个用到 `subscribe` 的 fixture 从不给它
/// `mock_response`，等 ack 会让 `subscribe()` 自己悬挂住、拖死整条 fixture 时间线（本轮实测：跑
/// 错误方向实现的 CI 命令，进程直接悬挂不退出）。
///
/// 本测试同样用 150ms 的人为延迟（而不是裸时序竞速）让断言确定性成立，不依赖调度巧合。
func testSubscribeReturnsBeforeServerSubscriptionAckArrives() async -> Bool {
    let name = "rounds/0012 ②（二次返工）subscribe() returns BEFORE sessions.messages.subscribe RPC ack arrives — restores D1 §2.3 (subscribe is not a Promise)"
    let client = freshClient()
    let sessionID = "sess-subscribe-race-1"
    let kernelKey = "kernel-key-subscribe-race-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()

    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        // 人为延迟——模拟"服务端订阅 RPC 尚未落地"的窗口。
        try? await Task.sleep(nanoseconds: 150_000_000)
        await callLog.record("rpc-responded")
        return ["subscribed": true, "key": kernelKey] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let stream = await client.subscribe(session: handle)
    await callLog.record("subscribe-returned")

    // subscribe() 现在立即返回，不再像上一版那样"return 本身就意味着 ack 已到"——必须显式等过
    // 延迟窗口才能观察到"rpc-responded"。固定 200ms 在本机够、在 GitHub macos runner 上不够
    // （Actions 32474120825：order 停在 ["subscribe-returned"]，173/174）。那不是顺序反了，
    // 是还没来得及发生——本测试改写时已经撞过这个坑。改为有界轮询，上限 2s。
    var order: [String] = []
    for _ in 0..<40 {
        order = await callLog.entries
        if order.contains("rpc-responded") { break }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard order == ["subscribe-returned", "rpc-responded"] else {
        return fail(name, "expected subscribe() to return BEFORE the RPC ack, order=\(order) — 上一版（本轮已推翻）会等 ack 才返回，顺序会反过来")
    }

    // 附带确认：本地事件续体在 RPC 完成之前就已经同步注册好（见 evidence/item2-subscribe-race.md
    // §1b「本地不丢的那一步」）——喂一帧真实 wire 事件，能被这个 stream 收到，证明 `subscribe()`
    // 返回的这个 stream 确实是可用的，不是"提前拿到个还没准备好的 stream"。
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.message",
        "payload": [
            "sessionKey": kernelKey,
            "messageId": "msg-subscribe-race-1",
            "messageSeq": 1,
            "session": ["activeRunIds": ["run-subscribe-race-1"]] as JSONObject,
            "message": ["role": "assistant", "content": "hello", "timestamp": 1_785_926_500_000] as JSONObject,
        ] as JSONObject,
    ])
    let events = await collectUpTo(stream, maxCount: 1)
    guard events.count == 1, case .messageDelta = events[0] else {
        return fail(name, "expected the stream returned by subscribe() to still receive events fed after it returns, got \(events.count)")
    }

    return pass(name, "subscribe() 在服务端订阅 RPC ack（人为延迟 150ms）到达之前就已经返回，调用顺序=\(order)，返回的 stream 之后仍能正常收事件——D1 §2.3 契约恢复")
}

/// **回归覆盖**：订阅 RPC 失败（`subscribed:false`）时——协议签名不带 `throws`（不可改），
/// `subscribe()` 本身不能抛错，只能把错误封进已经返回的 `stream`。验证 `for try await` 在第一次
/// 迭代就抛出。这条断言在本轮两版实现下都成立（不依赖"等不等 ack"这个已经翻转的前提，与上面那条
/// 测试相互独立）——错误路径原样保留自 SG-4/SG-5，未受 subscribe() 本轮任何一版改动影响。
func testSubscribeEmbedsRpcFailureIntoStreamNotThrownDirectly() async -> Bool {
    let name = "rounds/0012 ② subscribe() cannot throw (protocol signature has no `throws`) — RPC failure (subscribed:false) is embedded into the returned stream instead"
    let client = freshClient()
    let sessionID = "sess-subscribe-fail-1"
    let kernelKey = "kernel-key-subscribe-fail-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        ["subscribed": false] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    // 编译期事实：`subscribe()` 的返回类型是 `AsyncThrowingStream<...>`,不是
    // `throws -> AsyncThrowingStream<...>`——这一行如果哪天签名被改成带 throws,这里会编译失败,是
    // 对"不得改协议签名"这条硬约束的一个免费的编译期回归守卫。
    let stream: AsyncThrowingStream<EventMessageUnion, Error> = await client.subscribe(session: handle)

    var iterator = stream.makeAsyncIterator()
    do {
        _ = try await iterator.next()
        return fail(name, "expected the stream's first iteration to throw after subscribed:false")
    } catch KernelClientError.protocolMismatch(let message) {
        guard message.contains("subscribed:false") else {
            return fail(name, "unexpected protocolMismatch message: \(message)")
        }
    } catch {
        return fail(name, "expected KernelClientError.protocolMismatch, got \(error)")
    }
    return pass(name, "subscribed:false 未让 subscribe() 抛错（签名不允许），而是封进 stream，for-try-await 第一次迭代即抛出 protocolMismatch")
}

// MARK: - rounds/0012 ② 三次返工：send/stop 侧屏障——破坏性反证

/// 供下面两个屏障测试记录"某个 RPC 是否已经被真正 dispatch"的最小线程安全标记（同款 `actor` 模式见
/// 上面 `CallOrderLog`）。用布尔值而不是 `CallOrderLog` 的字符串数组，是因为这两个测试要的是"在某个
/// 时间点轮询是否已发生"，不是"事后比较两者的相对顺序"（相对顺序在两个独立 stub 闭包之间依赖
/// actor 调度细节、不适合作断言对象，见 `send()` 文档注释与这两个测试自己的说明）。
actor DispatchFlag {
    private(set) var dispatched = false
    func markDispatched() { dispatched = true }
}

/// **破坏性反证（scope-lock rounds/0012 ②「关掉竞态」要求，本轮三次返工后的最终修法）**：证明
/// `send()` 不会在 `subscribe()` 的底层 RPC 被 dispatch 之前，就先 dispatch 它自己的
/// `sessions.send` RPC。
///
/// **为什么用轮询两个时间点、不用比较两个 stub 闭包的调用顺序**：`subscribe()` 与 `send()` 各自的
/// RPC dispatch 发生在两个独立的 Swift 并发单元里（前者在 `subscribe()` 派生的背景 `Task`，后者在
/// `send()` 自己的调用者）——两者"谁先进 actor 队列"这类微观调度细节不在 Swift 并发模型的文档承诺
/// 范围内（`evidence/item2-subscribe-race.md` 原话："Swift actor 的重入调度并不保证它一定先完成"）。
/// 若测试断言依赖这种微观时序，测试本身就会重蹈评审已经指出过的"看起来测了、其实测的是调度巧合"覆辙。
/// 改用**远大于任何调度抖动量级**的人为延迟（200ms）划出一个宽窗口，在窗口内、窗口后**分别**轮询
/// `send()` 是否已经 dispatch 它自己的 RPC——这个断言只依赖"200ms ≫ 微观调度抖动"这一个粗粒度前提，
/// 不依赖两个 stub 谁先进队列。
///
/// **修前（本节 send/stop 侧屏障加入之前）fail / 修后 pass**：`send()` 加屏障之前，函数体第一行就是
/// `kernelKeyBySessionID` 查找，不等待任何信号——人为延迟窗口内 `send()` 会立刻走到自己的
/// `request(method:"sessions.send",...)`，`dispatchedEarly` 会是 `true`，第一个 `guard` 就会
/// `fail`。本测试写完后，先临时注释掉 `send()` 里 `await awaitSubscriptionRpcDispatchIfPending(...)`
/// 这一行验证过确实变红（见任务报告"破坏性反证"一节的红态输出），再取消注释验证转绿。
func testSendWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc() async -> Bool {
    let name = "rounds/0012 ② send-side barrier: send() does not dispatch sessions.send before subscribe()'s sessions.messages.subscribe has been dispatched"
    let client = freshClient()
    let sessionID = "sess-send-barrier-1"
    let kernelKey = "kernel-key-send-barrier-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportSetSubscribeDispatchDelay(nanoseconds: 200_000_000)
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        ["subscribed": true, "key": kernelKey] as JSONObject
    }
    let sendDispatchFlag = DispatchFlag()
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        await sendDispatchFlag.markDispatched()
        return ["runId": "run-send-barrier-1", "status": "started", "messageSeq": 1] as JSONObject
    }

    _ = await client.subscribe(session: handle) // 立即返回（D1 契约），背景 Task 因人为延迟 200ms 还未真正 dispatch 它的 RPC
    let sendTask = Task<Void, Never> {
        _ = try? await client.send(session: handle, input: Input(kind: .text, text: "hi", parts: nil))
    }

    // 延迟窗口前半段（100ms < 200ms）：subscribe 的 RPC 此刻应该仍未 dispatch，send() 应该仍被屏障
    // 拦住，尚未 dispatch 它自己的 RPC。
    try? await Task.sleep(nanoseconds: 100_000_000)
    guard await sendDispatchFlag.dispatched == false else {
        return fail(name, "send() 的底层 sessions.send RPC 在 subscribe() 的 RPC dispatch 完成之前（人为延迟窗口内，t=100ms<200ms）就已经发出——屏障未生效")
    }

    // 延迟窗口彻底过去 + 150ms 余量：send() 应该已经被放行，完成了它自己的 RPC dispatch。
    try? await Task.sleep(nanoseconds: 250_000_000)
    guard await sendDispatchFlag.dispatched else {
        return fail(name, "等 subscribe RPC dispatch 完成（200ms）后又等了 250ms，send() 仍未 dispatch 它自己的 RPC——屏障是否卡死、或漏放行？")
    }
    await sendTask.value
    return pass(name, "send() 的底层 sessions.send RPC 严格晚于 subscribe() 的底层 sessions.messages.subscribe RPC dispatch（人为 200ms 延迟窗口内未提前发出，窗口后确实发出）——send 侧屏障生效")
}

/// **stop() 复用同一屏障**——镜像上面的 send() 测试，验证对象换成 `stop()` 与它的
/// `sessions.abort` RPC。这里的 session 从未 `send()` 过（没有 active run），走 `stop()` 的
/// "abortedRunId:null" 分支（`OpenclawGatewayKernelClient.stop()` 里 `actuallyAbortedRunID ==
/// nil` 的 else 分支），不需要额外驱动 turn_complete 之类的终态帧就能让 `stop()` 完整走完并返回。
func testStopWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc() async -> Bool {
    let name = "rounds/0012 ② send-side barrier also covers stop(): stop() does not dispatch sessions.abort before subscribe()'s sessions.messages.subscribe has been dispatched"
    let client = freshClient()
    let sessionID = "sess-stop-barrier-1"
    let kernelKey = "kernel-key-stop-barrier-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportSetSubscribeDispatchDelay(nanoseconds: 200_000_000)
    await client.testSupportStubRPC(method: "sessions.messages.subscribe") { _ in
        ["subscribed": true, "key": kernelKey] as JSONObject
    }
    let abortDispatchFlag = DispatchFlag()
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await abortDispatchFlag.markDispatched()
        return ["status": "no-active-run"] as JSONObject // abortedRunId 缺失 -> stop() 的"无 active run"分支
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] as JSONObject }

    _ = await client.subscribe(session: handle)
    let stopTask = Task<Void, Never> {
        _ = try? await client.stop(session: handle)
    }

    try? await Task.sleep(nanoseconds: 100_000_000)
    guard await abortDispatchFlag.dispatched == false else {
        return fail(name, "stop() 的底层 sessions.abort RPC 在 subscribe() 的 RPC dispatch 完成之前（人为延迟窗口内，t=100ms<200ms）就已经发出——屏障未生效")
    }

    try? await Task.sleep(nanoseconds: 250_000_000)
    guard await abortDispatchFlag.dispatched else {
        return fail(name, "等 subscribe RPC dispatch 完成（200ms）后又等了 250ms，stop() 仍未 dispatch 它自己的 sessions.abort RPC——屏障是否卡死、或漏放行？")
    }
    await stopTask.value
    return pass(name, "stop() 的底层 sessions.abort RPC 严格晚于 subscribe() 的底层 sessions.messages.subscribe RPC dispatch——send() 与 stop() 共享的屏障对 stop() 同样生效")
}

/// **"从未 subscribe 就 send"不能永久挂起**（scope-lock rounds/0012 ②任务书明确要求的边界情况）。
/// `testSupportRegisterSession` 只建立 `kernelKeyBySessionID` 映射与本地事件流，刻意**不**经过真实
/// `subscribe()`——这正是"这个 session 从未 subscribe 过"的字面构造（本文件另外 29 个复用它的既有
/// 测试，事实上一直隐式覆盖着这条路径没出过问题；本测试把它显式化、独立断言，不再依赖"顺带覆盖"）。
/// 用一个"send() vs 300ms 超时"的竞速（同款 `withTaskGroup` 模式见 `collectUpTo`）——若 `send()`
/// 挂在一个永远不会有人调用 `markSubscriptionRpcDispatched` 的信号上，超时会先赢，测试即失败。
func testSendProceedsImmediatelyWhenSessionWasNeverSubscribed() async -> Bool {
    let name = "rounds/0012 ② send-side barrier: a session that was never subscribe()'d does not hang send() forever"
    let client = freshClient()
    let sessionID = "sess-never-subscribed-1"
    let kernelKey = "kernel-key-never-subscribed-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey) // 从不调用真实 subscribe()
    await client.testSupportStubRPC(method: "sessions.send") { _ in
        ["runId": "run-never-subscribed-1", "status": "started", "messageSeq": 1] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)

    let outcomeBox = DispatchOutcomeBox()
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            do {
                _ = try await client.send(session: handle, input: Input(kind: .text, text: "hi", parts: nil))
                await outcomeBox.set("resolved")
            } catch {
                await outcomeBox.set("threw: \(error)")
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await outcomeBox.set("timed-out")
        }
        await group.next()
        group.cancelAll()
    }
    let outcome = await outcomeBox.value
    guard outcome == "resolved" else {
        return fail(name, "expected send() to resolve promptly for a session that was never subscribe()'d, got outcome=\(outcome ?? "nil") — nil/timed-out 意味着 send() 挂在了一个永远不会触发的订阅 dispatch 信号上")
    }
    return pass(name, "send() 对一个从未调用过 subscribe() 的 session 正常、及时地完成（未永久悬挂等一个永远不会来的订阅 dispatch 信号）")
}

/// 供上面那条"从未 subscribe"测试记录首个完成结果的最小线程安全盒子——同款 `actor` 模式见
/// `CallOrderLog`/`DispatchFlag`，只是多存一个可空字符串而不是布尔/数组。
actor DispatchOutcomeBox {
    private(set) var value: String?
    func set(_ v: String) {
        if value == nil { value = v }
    }
}

// MARK: - rounds/0012 ③：wire messageSeq 单调非递减断言（EventAssertionCollector 断言 4）
//
// 两条测试对应 scope-lock ③ 的硬要求"断言写完后必须人为丢弃一帧，确认它变红"，且明确要求同时证明
// "合法重复不会误报"——只证明"倒退会红"不够。两条测试都走真实的 `handleSessionMessageEvent` dispatch
// 路径（`testSupportFeedFrame`），不是直接摆数据进 `EventAssertionCollector.recordMessageSeq`——这样
// 才能同时验证"messageSeq 怎么进到断言收集器"这条旁路本身
// （`OpenclawGatewayKernelClient.setWireMessageSeqObserver`）确实工作，不只是验证 `recordMessageSeq`
// 这一个方法自己的判定逻辑。

/// **绿方向**：8 条真实 session.message 帧，messageSeq 序列逐条照抄 rounds/0012
/// `evidence/item3-messageseq.md` §2 的实测原始数据（`1,1,2,3,3,4,5,6`，user/assistant 角色交替，
/// 每条 user 消息产生 status+delta 两帧、transcript 计数持平）——不是构造出来的合成场景。断言必须判定
/// **0 违例**：这是"断言别对合法重复误报"这一半，如果这里反而报了违例，说明用 `<` 判违例（而不是
/// `<=`）这个关键细节做错了。同时断言观察计数 == 8（不是 3，即只数 assistant 帧的次数）——证明旁路
/// 调用点确实放在了 `mapOpenclawSessionMessageToKernelEvents` 的 role=="assistant" 过滤**之前**，
/// role=="user" 的回显帧不会被漏计。
func testWireMessageSeqAcceptsRealLegalNonDecreasingSequence() async -> Bool {
    let name = "rounds/0012 ③ wire messageSeq 单调非递减断言：真实合法序列 1,1,2,3,3,4,5,6（含重复）不误报"
    let client = freshClient()
    let sessionID = "sess-messageseq-legal-1"
    let kernelKey = "kernel-key-messageseq-legal-1"
    let runID = "run-messageseq-legal-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let collector = EventAssertionCollector()
    await client.setWireMessageSeqObserver { seq in collector.recordMessageSeq(seq) }

    // (messageSeq, role) 逐条照抄 item3-messageseq.md §2 的实测序列。
    let sequence: [(seq: Int, role: String)] = [
        (1, "user"), (1, "user"), (2, "assistant"), (3, "user"),
        (3, "user"), (4, "assistant"), (5, "user"), (6, "assistant"),
    ]
    for (i, entry) in sequence.enumerated() {
        let frame: JSONObject = [
            "type": "event", "event": "session.message",
            "payload": [
                "sessionKey": kernelKey,
                "messageId": "msg-\(i)",
                "messageSeq": entry.seq,
                "session": ["activeRunIds": [runID]] as JSONObject,
                "message": [
                    "role": entry.role,
                    "content": entry.role == "assistant" ? "assistant reply #\(i)" : "user turn #\(i)",
                    "timestamp": 1_785_926_400_000 + i,
                ] as JSONObject,
            ] as JSONObject,
        ]
        await client.testSupportFeedFrame(frame)
    }
    // 3 条 assistant 帧会各产出 1 条 messageDelta——顺带排空主事件流,证明新增的旁路没有扰乱既有的 D2
    // dispatch 路径。不断言这 3 条事件本身（那是 item①/F3 测试的职责),只是安全排空。
    _ = await collectUpTo(stream, maxCount: 3)

    let snapshot = collector.messageSeqSnapshot()
    guard snapshot.observedCount == sequence.count else {
        return fail(name, "expected observer to fire \(sequence.count) times (once per session.message frame, including role=='user'), got \(snapshot.observedCount) — 说明旁路调用点被放到了 assistant-only 过滤之后")
    }
    guard snapshot.violations.isEmpty else {
        return fail(name, "expected 0 violations for legal 1,1,2,3,3,4,5,6, got \(snapshot.violations.count): \(snapshot.violations)")
    }
    return pass(name, "8 条真实序列 messageSeq=1,1,2,3,3,4,5,6（含 2 组合法重复）全部判定非递减，0 违例，观察计数=\(snapshot.observedCount)")
}

/// **红方向**：人为构造一次倒退（`1,2,1`）——scope-lock ③ 的硬要求"断言写完后必须人为丢弃一帧，确认
/// 它变红"。这条序列本身不是任何真实样本（现场从未观察到 messageSeq 倒退），是刻意构造的破坏性反证，
/// 与文件里其它"人为构造异常场景以证明断言不是空转"的测试同一纪律（如
/// `testStopForceDenyDrainExceedsRoundCapThrowsAndReleasesLock` 人为压低 round cap）。
func testWireMessageSeqDetectsRegression() async -> Bool {
    let name = "rounds/0012 ③ wire messageSeq 单调非递减断言：人为倒退 1,2,1 必须变红"
    let client = freshClient()
    let sessionID = "sess-messageseq-regress-1"
    let kernelKey = "kernel-key-messageseq-regress-1"
    let runID = "run-messageseq-regress-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let collector = EventAssertionCollector()
    await client.setWireMessageSeqObserver { seq in collector.recordMessageSeq(seq) }

    let sequence = [1, 2, 1] // 第三条相对第二条倒退——人为丢弃/乱序的破坏性反证。
    for (i, seq) in sequence.enumerated() {
        let frame: JSONObject = [
            "type": "event", "event": "session.message",
            "payload": [
                "sessionKey": kernelKey,
                "messageId": "msg-regress-\(i)",
                "messageSeq": seq,
                "session": ["activeRunIds": [runID]] as JSONObject,
                "message": [
                    "role": "assistant",
                    "content": "reply #\(i)",
                    "timestamp": 1_785_926_400_000 + i,
                ] as JSONObject,
            ] as JSONObject,
        ]
        await client.testSupportFeedFrame(frame)
    }
    _ = await collectUpTo(stream, maxCount: 3)

    let snapshot = collector.messageSeqSnapshot()
    guard snapshot.observedCount == 3 else {
        return fail(name, "expected observer to fire 3 times, got \(snapshot.observedCount)")
    }
    guard snapshot.violations.count == 1 else {
        return fail(name, "expected exactly 1 violation for regressing 1,2,1, got \(snapshot.violations.count): \(snapshot.violations)")
    }
    return pass(name, "倒退帧被正确抓到（1 处违例）：\(snapshot.violations[0])")
}

// MARK: - B1（rounds/0013）：createSession() label 唯一性
//
// openclaw `sessions.create` 经 `session-create-service.ts:723`（`applySessionsPatchToStore`）转发进
// `gateway/sessions-patch.ts:422-441`（label 分支）——对同一 store 内**全部**会话强制 label 互不相同
// （`entry?.label === parsed.label` 逐条比对现有条目，`:435-437`），撞名直接
// `INVALID_REQUEST: label already in use: <label>`，没有重试机会（本轮在 openclaw 源码里逐层核对过
// 这条调用链，不是转述任务书）。旧实现在 `OpenclawGatewayKernelClient.createSession()` 里把 label
// 写死成字面量 `"sg4-kernel-client-l1"`，同一 openclaw state 目录下第二次 `createSession()` 必然撞上
// 第一次留下的同名条目——本轮已 UI 侧 + CLI 侧双路径实证（`app/apps/AgentShell/repro/L1-REPRO.md` §5
// 修复前版本）。

/// **纯函数测试**（同款风格见 `testAttachmentOnlyEncodesContent`）：固定 `ourSessionID` + 固定
/// `Date`，断言 `makeSessionLabel` 产出的 label 同时满足 scope-lock B1 的两条要求——"人眼可辨认"
/// （含可读时间戳，不是裸 UUID）与"保证唯一/可反查"（尾部就是传入的 `ourSessionID` 原文，供人在
/// openclaw 侧按 label 反查是客户端哪一次 createSession() 铸造的）。
func testMakeSessionLabelIsHumanReadableAndTraceableToSessionID() -> Bool {
    let name = "B1 (rounds/0013): makeSessionLabel 产出人眼可辨认(含时间戳)且可反查(含完整 ourSessionID)的 label"
    let sessionID = "b1-fixed-uuid-aaaa-bbbb-cccccccccccc"
    // 2026-08-08 12:34:56 UTC 的固定 epoch 秒数（python3 -c "import datetime;
    // print(datetime.datetime.utcfromtimestamp(1786192496))" 核对过）——避免测试结果随运行机器
    // 所在时区漂移。
    let fixedDate = Date(timeIntervalSince1970: 1_786_192_496)
    let label = makeSessionLabel(ourSessionID: sessionID, createdAt: fixedDate)

    guard label != sessionID else {
        return fail(name, "label 不应该只是一串裸 UUID（scope-lock 明文要求「别只有一串裸 UUID」）")
    }
    guard label.hasSuffix(sessionID) else {
        return fail(name, "expected label to end with the exact ourSessionID '\(sessionID)' for reverse lookup, got '\(label)'")
    }
    guard label.hasPrefix("sg4-") else {
        return fail(name, "expected label to start with a recognizable 'sg4-' prefix, got '\(label)'")
    }
    // 时间戳段落必须是 label 前缀与 sessionID 后缀之间人眼可读的一段——形如 8 位日期 + 'T' + 6 位
    // 时间 + 'Z'（yyyyMMdd'T'HHmmss'Z'，共 16 字符）。
    let timestampSegment = label
        .dropFirst("sg4-".count)
        .dropLast(sessionID.count + 1) // 再去掉 sessionID 前面那个连字符
    guard timestampSegment.count == 16, timestampSegment.contains("T"), timestampSegment.hasSuffix("Z") else {
        return fail(name, "expected a human-readable yyyyMMdd'T'HHmmss'Z' timestamp segment between prefix and sessionID, got segment '\(timestampSegment)' from label '\(label)'")
    }
    return pass(name, "label='\(label)'：前缀 sg4- + 可读时间戳段 '\(timestampSegment)' + 完整 ourSessionID 后缀，人眼可辨认且可反查")
}

/// 供下面这条测试记录每次 `sessions.create` RPC 实际发出的 `params["label"]`——同款 `actor` 捕获盒
/// 模式见 `CallOrderLog`/`DispatchOutcomeBox`，这里存字符串数组（保留调用顺序，供断言按下标比较
/// "第一次"与"第二次"分别拿到什么）。
actor CapturedLabelsBox {
    private(set) var labels: [String] = []
    func record(_ label: String) { labels.append(label) }
}

/// **破坏性反证核心（scope-lock rounds/0013 B1 硬要求）**：同一个 `OpenclawGatewayKernelClient`
/// 实例连续调用两次 `createSession()`，两次真正发给 openclaw 的 `sessions.create` RPC
/// `params["label"]` 必须不同——这是本轮要修的 bug 本身的直接断言，不是绕道验证某个内部状态。
///
/// **修前（本轮改动之前 `:337` 的 `"sg4-kernel-client-l1"` 字面量）这条测试必须失败**：两次调用会
/// 拿到完全相同的 label，`labels[0] != labels[1]` 判定为 false——已实测确认（交付报告有红→绿两段
/// 实际输出）。
///
/// 不驱动真实网络——`testSupportStubRPC(method: "sessions.create")` 桩替代 RPC 响应（`request()`
/// 对已注册方法名的短路机制，见该方法文档注释），真实调用的是 `createSession(config:)` 方法体本身
/// （不是 seed 内部状态），捕获它真正构造、真正发出的 `params`。两次调用返回相同的桩造 `key`/
/// `sessionId` 是有意的——本测试只关心 label 是否不同，`SessionHandle.sessionID`（`ourSessionID`）
/// 由 actor 内部各自铸造，与桩造的返回值无关，混用同一份桩造返回值不影响这条断言的有效性。
func testCreateSessionAssignsDistinctLabelsAcrossConsecutiveCalls() async -> Bool {
    let name = "B1 (rounds/0013): 同一 client 连续 createSession() 两次，两次的 label 不同（openclaw 侧 label 全 store 唯一，撞名即 INVALID_REQUEST）"
    let client = freshClient()
    let captured = CapturedLabelsBox()

    await client.testSupportStubRPC(method: "sessions.create") { params in
        guard let label = params["label"] as? String, !label.isEmpty else {
            throw KernelClientError.protocolMismatch("sessions.create params missing non-empty 'label': \(params)")
        }
        await captured.record(label)
        return ["key": "kernel-key-b1-label-test", "sessionId": "kernel-session-b1-label-test"] as JSONObject
    }

    let config = Config(
        approvalProfile: nil, cwd: "/tmp/frame-replay-tests-b1-cwd", model: nil,
        newapiEndpoint: NewapiEndpoint(baseURL: "http://127.0.0.1:0/frame-replay-tests-unused", deploymentTokenRef: nil),
        resume: nil, sandbox: nil, toolset: nil
    )

    guard let firstHandle = try? await client.createSession(config: config) else {
        return fail(name, "first createSession() unexpectedly threw")
    }
    guard let secondHandle = try? await client.createSession(config: config) else {
        return fail(name, "second createSession() unexpectedly threw")
    }

    let labels = await captured.labels
    guard labels.count == 2 else {
        return fail(name, "expected sessions.create to be called exactly twice, observed \(labels.count) calls: \(labels)")
    }
    guard labels[0] != labels[1] else {
        return fail(name, "expected two distinct labels across consecutive createSession() calls, both were '\(labels[0])' — openclaw would reject the second with INVALID_REQUEST: label already in use")
    }
    guard firstHandle.sessionID != secondHandle.sessionID else {
        return fail(name, "expected distinct SessionHandle.sessionID across calls, both were '\(firstHandle.sessionID)'")
    }

    return pass(name, "两次 createSession() 的 label 分别是 '\(labels[0])' 与 '\(labels[1])'，互不相同；SessionHandle.sessionID 分别是 \(firstHandle.sessionID)/\(secondHandle.sessionID)")
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
    // rounds/0016：握手补 `exec-approvals` cap 之后才收得到的 `exec.approval.requested`——映射本身
    // 与"同一次审批不得重复交付"的去重闸门。
    results.append(await testExecApprovalRequestedAloneProducesApprovalRequest())
    results.append(await testExecApprovalRequestedDoesNotDoubleEmitWithSessionApproval())
    // rounds/0016 live 实测：webchat（native approval channel）走 exec 内联等待分支，关联帧是
    // agent(stream:"lifecycle", phase:"waiting-approval")，帧数据取自冻结的真实 wire trace。
    results.append(await testAgentLifecycleWaitingApprovalJoinsRealFrozenFrames())
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
    results.append(await testStopForceDeniesPendingApprovalBeforeAbort())
    results.append(await testStopWithNoPendingApprovalLeavesForceResolvedApprovalsNil())
    results.append(await testStopForceDeniesLateArrivingApprovalDuringDrainAwaitWindow())
    results.append(await testStopForceDenyDrainExceedsRoundCapThrowsAndReleasesLock())
    results.append(await testStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror())
    results.append(await testStopCleansUpAllSessionCaches())
    results.append(await testStopTransportClosedWhileWaitingDoesNotHangAndEmitsMirror())
    results.append(testAttachmentOnlyEncodesContent())
    results.append(testRedactionCoversPluralsAndCommonVariants())
    results.append(testRedactionExcludesTokenCountingFields())
    results.append(testCredentialRedactionRegressionRealFrame())
    results.append(testFullD2JSONEncodeDecodeRoundTrip())
    results.append(await testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs())
    results.append(await testSubscribeReturnsBeforeServerSubscriptionAckArrives())
    results.append(await testSubscribeEmbedsRpcFailureIntoStreamNotThrownDirectly())
    results.append(await testSendWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc())
    results.append(await testStopWaitsForPendingSubscriptionDispatchBeforeItsOwnRpc())
    results.append(await testSendProceedsImmediatelyWhenSessionWasNeverSubscribed())
    results.append(await testWireMessageSeqAcceptsRealLegalNonDecreasingSequence())
    results.append(await testWireMessageSeqDetectsRegression())
    results.append(testMakeSessionLabelIsHumanReadableAndTraceableToSessionID())
    results.append(await testCreateSessionAssignsDistinctLabelsAcrossConsecutiveCalls())
    // rounds/0013 B2（SessionStoreGroupingTests.swift）：入库测试直接验 SessionStore 的分组行为
    // ——上面 testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs 只验 kernel-client
    // wire-mapping 层的 messageID 透传，够不到 SessionStore 本身；这条新测试驱动
    // SessionStore.handle() 真实分发路径，直接断言 session.messages 的分组结果。
    results.append(await testSessionStoreHandleGroupsDistinctMessageIDsAsSeparateMessages())

    // rounds/0017 Change 1（SessionStoreToolRenderingTests.swift）："让 agent 看起来像 agent"——
    // evt.tool_call/evt.tool_result/evt.thinking/evt.operation_completed 此前在 SessionStore.handle()
    // 里一律 `break`，本轮渲染出来；这些测试同样驱动 handle() 真实分发路径（同上面 B2 的做法），
    // 断言 session.toolCalls/session.thinkingItems/session.timeline/session.messages 的产出。
    results.append(await testSessionStoreHandleToolCallProducesToolCallItem())
    results.append(await testSessionStoreHandleToolResultPairsWithMatchingToolCall())
    results.append(await testSessionStoreHandleToolResultSurfacesFailureAndPreview())
    results.append(await testSessionStoreHandleOrphanToolResultDoesNotSilentlyDrop())
    // rounds/0017 返工（code-review-adversarial 判 REWORK，P1）：evt.tool_result 先于它自己的
    // evt.tool_call 到达时，姗姗来迟的 tool_call 必须原地补全孤儿占位项，不能追加出第二条同 id 的
    // ToolCallItem（破坏 SwiftUI ForEach 的唯一 identity 契约）——上一条
    // testSessionStoreHandleOrphanToolResultDoesNotSilentlyDrop 只验了"孤儿本身不丢"，验不到
    // "后续 call 到达时是否正确合并"，这条新测试补上这个顺序。
    results.append(await testSessionStoreHandleToolCallAfterOrphanResultFillsInPlaceNotADuplicateRow())
    // rounds/0019：live capture（真实 openclaw + 真实 LLM）坐实"逐条 evt.thinking 独立成行、不合并"
    // 是渲染缺陷，不是设计克制——一段推理被切成十几二十个折叠块，单词被从中腰斩。上一行原是
    // testSessionStoreHandleThinkingEventsDoNotMerge（断言不合并，锁死了这个缺陷本身），改写为断言
    // 正确的按 runId 合并行为；新增一条现场分片序列回放测试，逐字取自 evidence/shots/
    // 14-tool-result.png。两条测试均见 SessionStoreToolRenderingTests.swift。
    results.append(await testSessionStoreHandleThinkingEventsMergeBySameRunID())
    results.append(await testSessionStoreHandleThinkingMergesLiveCaptureFragmentSequence())
    results.append(await testSessionStoreHandleThinkingPreservesSummaryVisibility())
    results.append(await testSessionStoreTimelineInterleavesEventsInArrivalOrder())
    results.append(await testSessionStoreHandleOperationCompletedRendersSystemMessage())

    // rounds/0014（会话持久化）：SessionRestoreHistoryTests.swift —— B(适配器状态重建)/
    // D(重新订阅)/C(历史回填分页) 三块在 KernelClient 层的真 actor 级验证。
    results.append(await testRestoreSessionSeedsKernelKeyAndReestablishesEventFlow())
    results.append(await testRestoreSessionDoesNotCallSessionsCreateRpc())
    results.append(await testFetchFullHistoryPaginatesAcrossMultiplePages())
    results.append(await testFetchFullHistoryRejectsRepeatedNextOffsetInsteadOfLoopingForever())
    results.append(testParseHistoryRecordExtractsStringAndBlockContentIgnoringNonTextBlocks())

    // rounds/0014（会话持久化）：SessionPersistenceTests.swift —— A(会话清单持久化) 块，含反证1
    // （坏数据不得永久卡死壳）的自动化版本。
    results.append(testSessionPersistenceRoundTripsSavedSessions())
    results.append(testSessionPersistenceCorruptFileFallsBackToEmptyListWithoutCrashing())
    results.append(testSessionPersistenceResetRemovesFileAndSubsequentLoadIsEmpty())
    results.append(testSessionPersistenceMissingFileReturnsEmptyWithoutCreatingAnything())

    // rounds/0015（exec 工具审批）：ApprovalDecisionTests.swift —— A(respondApproval 真打 RPC)/
    // B(决策映射 + 每条请求自带 allowedDecisions 的发出前校验，含反证①②)/C(审批 UI 卡片生命周期)。
    results.append(contentsOf: await runApprovalDecisionTests())

    // rounds/0016（★审查闸 T-096 的四条边界失败态）：ApprovalFailurePathTests.swift ——
    // ①溢出 deny 的成功判据 / ②FORCE_DENY_PENDING_KERNEL_ACK / ③approval.resolve 有界等待 +
    // 权威 terminal 结束 in-flight / ④active terminal 后的 UI 同步（先清旧卡再呈现提升项）。
    results.append(contentsOf: await runApprovalFailurePathTests())

    // Settings UI（KernelShellSettingsTests.swift）：env > 已保存设置 > 内建默认值 精度链
    // （endpoint 走 UserDefaults、token 走 Keychain）、来源标注与生效值的一致性、占位符判定谓词、
    // fromEnvironment() 行为未变回归锁、Keychain/UserDefaults 存储层往返、
    // SessionStore.reconnect(with:) 的展示态更新与会话清空。
    results.append(testResolvedEndpointPrefersEnvironmentOverStoredAndDefault())
    results.append(testResolvedEndpointPrefersStoredOverDefaultWhenEnvAbsent())
    results.append(testResolvedEndpointFallsBackToBuiltInDefaultWhenNothingSet())
    // rounds/0019 评审 Q3：env 非法时的级联行为 + source 如实标注（评审给出的直接复现构造）。
    results.append(testResolvedEndpointCascadesToStoredSettingWhenEnvURLIsInvalid())
    results.append(testResolvedEndpointFallsBackToDefaultWhenEnvURLIsInvalidAndNoStoredValue())
    results.append(testResolvedTokenPrefersEnvironmentOverStoredAndDefault())
    results.append(testResolvedTokenPrefersStoredOverDefaultWhenEnvAbsent())
    results.append(testResolvedTokenFallsBackToBuiltInDefaultWhenNothingSet())
    results.append(testEndpointAndTokenSourcesResolveIndependently())
    results.append(testIsTokenPlaceholderTrueForDefaultTokenAndFalseForRealToken())
    results.append(testFromEnvironmentBehaviorUnchangedWhenBothEnvVarsSet())
    results.append(testFromEnvironmentBehaviorUnchangedWhenNeitherEnvVarSet())
    results.append(testFromEnvironmentBehaviorUnchangedForInvalidURLWarningPath())
    results.append(testKeychainTokenStoreSavesReadsUpdatesAndDeletes())
    results.append(testKeychainTokenStoreReadReturnsNilForNeverUsedServiceAccount())
    results.append(testKeychainTokenStoreDeleteIsIdempotentWhenNothingStored())
    results.append(testKernelEndpointDefaultsStoreRoundTripsAndClears())
    results.append(await testSessionStoreReconnectUpdatesDisplayStateAndResetsSessions())

    // rounds/0020（D1 §2.4）：InterruptTests.swift —— interrupt(mode:"cancel") 的完整实现：会话存活
    // 红线、从不 delete 红线、强制 deny 定序、权威 abortedRunId 判定、无 active run/超时/transport
    // 关闭三条终态镜像、互斥矩阵（新增 interruptInProgress 锁态）、订阅屏障、mode 门禁。
    results.append(contentsOf: await runInterruptTests())

    // rounds/0020（app 层）：SessionStoreInterruptTests.swift —— 「停止生成」按钮的 SessionStore
    // 落点：interruptCurrentRun(in:) 的 guard 语义/失败转发/端到端成功路径，以及
    // handleOperationCompleted 对 operationKind:.interrupt 的兜底清 isWaitingForReply（任务书第 4
    // 条：abortedRunId==nil/超时两条路径从不产出 turn_complete，只靠 .turnComplete 清会永久卡住）。
    results.append(contentsOf: await runSessionStoreInterruptTests())

    // rounds/0021（外观：可自定义透明度 + 语义色）：AppearanceSettingsTests.swift —— 透明度偏好
    // 持久化往返（含"保存了 0"与"从未保存"的区分）、本轮红线（ChromeTransparencyResolver.resolve()
    // 在 Reduce Transparency/Increase Contrast 任一开启时压过滑块的任意取值，含两个极值）、反面
    // 验证（两个开关都关闭时确实允许透明，证明红线测试不是靠恒返回 .opaque 蒙混过关）、越界滑块值
    // 夹紧、以及 ApprovalDecisionSemantics.colorRole(for:) 的 deny->danger / allow*->accent 映射。
    results.append(testChromeTransparencyDefaultsStoreRoundTripsAndClears())
    results.append(testChromeTransparencyDefaultsStoreDistinguishesSavedZeroFromNeverSaved())
    // rework（2026-08-14，T-114 codex 对抗评审阻断项②附带发现）：defaultSliderValue 此前是 0.6，
    // 落进的其实是 .thinMaterial（半开区间 [0.4,0.6) 不含 0.6 本身），与文档注释宣称的 .regularMaterial
    // 矛盾——改成 0.5 并在这里补两条回归钉（见 AppearanceSettingsTests.swift 该函数群文档注释）。
    results.append(testChromeTransparencyDefaultSliderValueLandsInsideRegularMaterialBucket())
    results.append(testChromeTransparencyDefaultSliderValueIsExactlyPointFive())
    results.append(testResolverReduceTransparencyForcesOpaqueAtEverySliderValueIncludingExtremes())
    results.append(testResolverIncreaseContrastAloneForcesOpaqueAtEverySliderValueIncludingExtremes())
    results.append(testResolverBothAccessibilityFlagsOnForcesOpaqueAtSliderExtremes())
    results.append(testResolverAllowsTranslucentWithMatchingIntensityWhenAccessibilityAllowsAndSliderPositive())
    results.append(testResolverSliderValueZeroIsOpaqueEvenWithoutAnyAccessibilityOverride())
    results.append(testResolverClampsOutOfRangeSliderValues())
    results.append(testApprovalDecisionSemanticsMapsDenyToDangerRoleNotAccent())
    results.append(testApprovalDecisionSemanticsMapsAllowVariantsToAccentRole())

    // 视觉/交互打磨任务（继 rounds/0021 之后，2026-08-14）：会话列表熊头水印的无障碍抑制判断
    // ——WatermarkVisibilityResolver.resolve()。水印本身（BearWatermark.swift 的
    // BearHeadWatermark/SessionListView 的调用点）是纯 SwiftUI 视图代码,结构性不可测（见本文件头
    // 注释与任务报告）；这三条测试覆盖的是唯一被收成纯函数、因而可测的部分——"给定无障碍状态，
    // 该不该画这个水印"，含它与 ChromeTransparencyResolver 刻意不对称的那一半（只看
    // increaseContrast，不看 reduceTransparency）。
    results.append(testWatermarkVisibilityResolverHidesWatermarkWheneverIncreaseContrastIsOn())
    results.append(testWatermarkVisibilityResolverIgnoresReduceTransparencyAlone())
    results.append(testWatermarkVisibilityResolverShowsWatermarkWhenNoAccessibilityOverrideIsActive())

    // rework（2026-08-14，T-114 codex 对抗评审阻断项②）：ComposerGlassLayerOpacity.resolve(intensity:)
    // ——macOS 26 composer 玻璃背景层的强度->不透明度映射,阻断项②修复里唯一被挪进 AgentShellCore、
    // 因而可测的部分（glassEffect 调用点本身仍在视图层,结构性不可测,见 AppearanceSettingsTests.swift
    // 该函数群文档注释）。
    results.append(testComposerGlassLayerOpacityVariesWithIntensity())
    results.append(testComposerGlassLayerOpacityDecreasesAsIntensityIncreases())
    results.append(testComposerGlassLayerOpacityStaysWithinDeclaredBoundsAtExtremes())

    // rounds/0021 Scope-Lock 修订 v1 -> v2（2026-08-14，最小菜单栏项）：MenuBarSummaryTests.swift ——
    // `MenuBarSummary.connectionStatusText(_:)`/`sessionNameText(_:)` 两个纯函数，供 `MenuBarExtra`
    // 内容视图消费（视图本身结构性不可测，见该文件头注释）。覆盖四个 ConnectionStatus case 的文案、
    // .connected 态刻意不泄漏 scopes 列表、以及会话名 nil/非 nil 两态（含"占位文案不能是空字符串"
    // 这条边界）。
    results.append(testMenuBarConnectionStatusTextForNotConnected())
    results.append(testMenuBarConnectionStatusTextForConnecting())
    results.append(testMenuBarConnectionStatusTextForConnectedOmitsScopesList())
    results.append(testMenuBarConnectionStatusTextForFailedIncludesMessage())
    results.append(testMenuBarSessionNameTextForNilShowsPlaceholderNotEmptyString())
    results.append(testMenuBarSessionNameTextForSelectedSessionReturnsItsTitleVerbatim())

    // 本轮缺陷修复（2026-08-14）：MenuBarSummary 的截断行为——NSError 全文/用户自定会话名都不受
    // 长度控制，此前会原样塞进菜单把宽度撑穿屏幕（用户实测踩到）。覆盖真实量级的长 NSError 文案、
    // 长会话名、naive UTF-16 截断会切碎的 CJK+emoji 组合、40/41 字符两侧的边界值，以及"短字符串
    // 完全不受影响"这条最容易漏掉的反向断言。
    results.append(testMenuBarConnectionStatusTextForFailedTruncatesRealisticLongNSErrorMessage())
    results.append(testMenuBarSessionNameTextTruncatesLongPastedSessionName())
    results.append(testMenuBarSessionNameTextTruncatesCJKStringWithoutSplittingASurrogatePairEmojiAtTheBoundary())
    results.append(testMenuBarSessionNameTextAtExactCapPassesThroughWithoutEllipsis())
    results.append(testMenuBarSessionNameTextOneCharacterOverCapGetsTruncated())
    results.append(testMenuBarConnectionStatusTextForFailedShortMessagePassesThroughCompletelyUnchanged())

    // 缺陷修复（2026-08-14，live-repro）：MenuBarWindowSelectionTests.swift —— `MenuBarWindowSelection.
    // findMainWindowIndex(among:mainWindowID:)`，`MenuBarWindowFocus.showMainWindow(openWindow:)`
    // 判断"现有窗口里有没有一个是主窗口"用的纯函数（视图/AppKit 交互本身结构性不可测，见该文件头
    // 注释）。核心覆盖：只有 Settings 窗口可见时不能被误认成主窗口（这正是本次修复要解决的缺陷本身）、
    // 空窗口列表、真实 SwiftUI 赋值形态（"main-AppWindow-1"）、已最小化窗口、主窗口不在数组首位、
    // nil identifier 防御、以及一条专门防止"用 contains 而不是 hasPrefix"偷懒实现的反向用例。
    results.append(testFindMainWindowIndexReturnsNilWhenOnlyASettingsLikeWindowIsVisible())
    results.append(testFindMainWindowIndexReturnsNilForEmptyWindowList())
    results.append(testFindMainWindowIndexMatchesRealisticSwiftUIAssignedIdentifierWithSuffix())
    results.append(testFindMainWindowIndexMatchesExactIdentifierEqualToMainWindowID())
    results.append(testFindMainWindowIndexMatchesMiniaturizedMainWindow())
    results.append(testFindMainWindowIndexReturnsCorrectIndexWhenMainWindowIsNotFirst())
    results.append(testFindMainWindowIndexTreatsNilIdentifierAsNonMatch())
    results.append(testFindMainWindowIndexIgnoresMatchingIdentifierThatIsNeitherVisibleNorMiniaturized())
    results.append(testFindMainWindowIndexRejectsIdentifierThatContainsButDoesNotStartWithMainWindowID())

    // rounds/0023（D1 v3.6 §6.1(a) + §9.3 仲裁修正）：SteerTests.swift —— interrupt(mode:"steer")
    // 完整实现（chat.send+queueMode:"steer"+deliver:false，严格二态 submitted/rejected，无 active
    // run 的同步前置 reject，不做强制 deny）+ stop() 遇 interrupt_in_progress 的"等待，不抢占"仲裁
    // 修正（steer 侧构造；cancel 侧构造见 InterruptTests.swift 重命名后的
    // testSendRejectedButStopWaitsThenProceedsWhileInterruptInFlight）。
    results.append(contentsOf: await runSteerTests())

    // rounds/0023 REWORK（T-116 codex 对抗评审 FAIL 7）：ActiveRunSnapshotTests.swift ——
    // `activeRunIDsBySessionID` 快照维护补齐"既有 session-restore/由本 client 之外的方式启动的
    // run"这条此前完全没有信号来源的路径，外加全量同步（不是并集追加）与自我一致性检查。
    results.append(contentsOf: await runActiveRunSnapshotTests())

    let passCount = results.filter { $0 }.count
    let total = results.count
    print("=== 结果: \(passCount)/\(total) PASS ===")
    return passCount == total
}
