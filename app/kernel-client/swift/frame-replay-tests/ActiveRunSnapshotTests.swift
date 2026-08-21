// rounds/0023 REWORK（T-116 codex 对抗评审 FAIL 7 —— active-run 本地快照维护不完整，见
// `OpenclawGatewayKernelClient.swift` `activeRunIDsBySessionID` 上方的完整文档注释）。
//
// **缺陷复述**：`activeRunIDsBySessionID` 此前只在**本 client 自己的** `send()` 拿到 RPC ack 时插入、
// 在 `handleAgentEvent` 观察到 lifecycle 终态帧时移除——完全没有处理"权威的 `session.message`
// `session.activeRunIds` 快照"（openclaw 每条 session.message 帧的 session 快照里都会带，反映的是
// **整个 session**当前的活跃 run 全集，与是谁启动的无关）。既有的 session-restore 场景、由其它
// client/入口启动的 run，因此会被这张表永远漏记——`interrupt(mode:'steer')` 的前置校验会对着一个
// 明明有 active run 的 session 错误同步 reject `no_active_run_for_steer`（假阴性：拒绝了一次合法的
// 用户意图）。反向问题同样真实：全量快照里的 `activeRunIds:[]`（explicit "现在真的没有任何 active
// run 了"）必须能清掉本地陈旧记录，只加不减的逻辑会让一个早已消失的 run 永远赖在"活跃"集合里，让后续
// steer 的前置校验对着一个不存在的 run 误判"有"（假阳性）。
//
// 本文件覆盖 T-116 REWORK brief 点名的"每一种 run 变得活跃的方式"：
//   1. session.message 的 activeRunIds 快照能识别本 client 之外启动的 run（含既有 restore 场景的
//      核心信号来源）——testSessionMessageSnapshotMarksExternallyStartedRunActive
//   2. 同一权威快照做的是**全量同步**、不是并集追加——一条后续到达的空快照必须能清掉陈旧记录——
//      testSessionMessageSnapshotFullyReconcilesRemovingStaleActiveRuns
//   3. 单靠 agent 流事件（没有任何 session.message）本身也能确立"这个 run 活跃"——覆盖"一个尚未产出
//      任何 assistant 文本、仍在 tool-call/thinking 中的 run"这条路径——
//      testAgentEventAloneMarksRunActiveWithoutSessionMessage
//   4. 自我一致性检查：一条从未见过的 runId 直接携带 lifecycle 终态帧（phase:"end"）到达时，不会
//      因为本轮新增的"任意 agent 事件插入"逻辑而在同一次函数调用内留下"先插入、终态摘除却棋差一招"
//      的残留——插入与摘除在同一段不含 await 的同步代码里互相抵消，不留可观察窗口——
//      testAgentLifecycleEndForNeverSeenRunDoesNotLeaveStaleActiveEntry
//
// 复用既有测试基础设施（`freshClient`/`testHandle`/`fail`/`pass`，定义在 FrameReplayTests.swift，
// 同 target 内可见）。`@testable import`：同其余 frame-replay-tests 文件。

import Foundation
@testable import KernelClient
import D2Generated

// MARK: - #1：session.message 的 activeRunIds 快照识别本 client 之外启动的 run

func testSessionMessageSnapshotMarksExternallyStartedRunActive() async -> Bool {
    let name = "rounds/0023 REWORK FAIL7 #1: a run reported via session.message's session.activeRunIds snapshot — never started by this client's own send() — is recognized as active by the local snapshot, and interrupt(mode:\"steer\") on it is accepted (not falsely rejected as no_active_run_for_steer)"
    let client = freshClient()
    let sessionID = "sess-fail7-external-run"
    let kernelKey = "kernel-key-fail7-external-run"
    let externalRunID = "run-started-elsewhere-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let beforeFrame = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard beforeFrame.isEmpty else {
        return fail(name, "test setup invariant violated: expected empty activeRunIDs before any frame, got \(beforeFrame)")
    }

    // 这个 run 从未经由本 client 的 send() 启动——唯一的信号来源是权威的 session.message
    // session.activeRunIds 快照（例如：一个既有 restore 场景恢复后收到的第一条消息，或另一个 client
    // 入口启动的 run）。
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.message",
        "payload": [
            "sessionKey": kernelKey,
            "session": ["activeRunIds": [externalRunID]] as JSONObject,
            "message": [
                "role": "assistant",
                "content": "hello from an externally-started run",
                "timestamp": 1_785_926_400_000,
            ] as JSONObject,
        ] as JSONObject,
    ])

    let afterFrame = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard afterFrame == [externalRunID] else {
        return fail(name, "expected activeRunIDs == {\(externalRunID)} after the session.message snapshot, got \(afterFrame)")
    }

    await client.testSupportStubRPC(method: "chat.send") { _ in
        ["runId": externalRunID, "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    guard let result = try? await client.interrupt(session: handle, options: options) else {
        return fail(name, "FAIL7 REGRESSION: interrupt(mode:\"steer\") threw instead of being accepted — the externally-started run was not recognized as active")
    }
    guard result.outcome == .submitted else {
        return fail(name, "expected outcome=.submitted, got \(result.outcome)")
    }

    _ = await collectUpTo(stream, maxCount: 3, timeoutMs: 200) // 排空事件，不重复断言事件形状（既有测试已覆盖）
    return pass(name, "session.message 的 session.activeRunIds 快照（externalRunID=\(externalRunID)，从未经由本 client 的 send() 启动）被正确同步进本地快照（testSupportActiveRunIDs 断言一致），interrupt(mode:\"steer\") 据此被正确接受（outcome=.submitted），未被误判 no_active_run_for_steer")
}

// MARK: - #2：全量同步（不是并集追加）——空快照必须清掉陈旧记录

func testSessionMessageSnapshotFullyReconcilesRemovingStaleActiveRuns() async -> Bool {
    let name = "rounds/0023 REWORK FAIL7 #2: session.message's session.activeRunIds snapshot performs a FULL reconciliation (not a union-only add) — a later snapshot reporting activeRunIds:[] must clear the stale locally-recorded run, and a subsequent interrupt(mode:\"steer\") must then correctly reject no_active_run_for_steer"
    let client = freshClient()
    let sessionID = "sess-fail7-stale-reconcile"
    let kernelKey = "kernel-key-fail7-stale-reconcile"
    let runID = "run-fail7-stale-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    await client.testSupportFeedFrame([
        "type": "event", "event": "session.message",
        "payload": [
            "sessionKey": kernelKey,
            "session": ["activeRunIds": [runID]] as JSONObject,
            "message": ["role": "assistant", "content": "first snapshot: run is active", "timestamp": 1_785_926_400_000] as JSONObject,
        ] as JSONObject,
    ])
    let afterFirst = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard afterFirst == [runID] else {
        return fail(name, "test setup invariant violated: expected activeRunIDs == {\(runID)} after the first snapshot, got \(afterFirst)")
    }

    // 后续快照显式报告"现在真的没有任何 active run 了"——这条信息本身必须能清掉上面刚刚记下的陈旧
    // 记录，不是被一个只加不减的 union 逻辑悄悄吞掉。
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.message",
        "payload": [
            "sessionKey": kernelKey,
            "session": ["activeRunIds": [] as [Any]] as JSONObject,
            "message": ["role": "assistant", "content": "second snapshot: no active runs anymore", "timestamp": 1_785_926_401_000] as JSONObject,
        ] as JSONObject,
    ])
    let afterSecond = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard afterSecond.isEmpty else {
        return fail(name, "FAIL7 REGRESSION: expected activeRunIDs to be cleared to empty after a snapshot explicitly reporting activeRunIds:[], but stale entry survived: \(afterSecond)")
    }

    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "FAIL7 REGRESSION: expected interrupt(mode:\"steer\") to reject no_active_run_for_steer against the now-empty snapshot, but it was accepted — the stale run is still being treated as active somewhere")
    } catch KernelClientError.rpcRejected(let code, _) where code == "no_active_run_for_steer" {
        // 期望路径。
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected(code:\"no_active_run_for_steer\"), got \(error)")
    }

    return pass(name, "第一条快照（activeRunIds:[\(runID)]）正确记为活跃；第二条快照（activeRunIds:[]，全量同步而非并集追加）正确清空本地记录（testSupportActiveRunIDs 断言一致）；随后 interrupt(mode:\"steer\") 正确同步 reject(no_active_run_for_steer)——陈旧记录未能让一次针对不存在的 run 的 steer 被误判为合法")
}

// MARK: - #3：单靠 agent 流事件（没有任何 session.message）也能确立"run 活跃"

func testAgentEventAloneMarksRunActiveWithoutSessionMessage() async -> Bool {
    let name = "rounds/0023 REWORK FAIL7 #3: a bare agent-stream event (thinking) carrying a runId — with NO session.message ever observed for it, and never started via this client's own send() — is by itself enough to mark the run active in the local snapshot, so interrupt(mode:\"steer\") on it is accepted"
    let client = freshClient()
    let sessionID = "sess-fail7-agent-only"
    let kernelKey = "kernel-key-fail7-agent-only"
    let runID = "run-fail7-agent-only-1"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    let before = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard before.isEmpty else {
        return fail(name, "test setup invariant violated: expected empty activeRunIDs before any frame, got \(before)")
    }

    // 一个尚未产出任何 assistant 文本（因此从未触发过 session.message）、仍在 tool-call/thinking 中
    // 的 run——它存在的唯一证据是这条 agent 流事件本身。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "thinking",
            "data": ["text": "considering next steps..."] as JSONObject,
            "ts": 1_784_900_000_000,
        ] as JSONObject,
    ])

    let after = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard after == [runID] else {
        return fail(name, "FAIL7 REGRESSION: expected activeRunIDs == {\(runID)} after a bare agent(stream:\"thinking\") event, got \(after) — an agent-stream-only run (never seen via session.message or this client's own send()) is not being recognized as active")
    }

    await client.testSupportStubRPC(method: "chat.send") { _ in
        ["runId": runID, "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    guard let result = try? await client.interrupt(session: handle, options: options) else {
        return fail(name, "FAIL7 REGRESSION: interrupt(mode:\"steer\") threw instead of being accepted — the agent-stream-only run was not recognized as active")
    }
    guard result.outcome == .submitted else {
        return fail(name, "expected outcome=.submitted, got \(result.outcome)")
    }

    _ = await collectUpTo(stream, maxCount: 3, timeoutMs: 200)
    return pass(name, "一条不携带任何 session.message 的裸 agent(stream:\"thinking\") 事件（runId=\(runID)）单独就把该 run 标记为活跃（testSupportActiveRunIDs 断言一致），interrupt(mode:\"steer\") 据此被正确接受——补上了『run 只产出 agent 流活动、从未触发 session.message』这条此前完全没有信号来源的路径")
}

// MARK: - #4：自我一致性——终态帧不会因为新增的"任意事件即插入"逻辑而留下残留

func testAgentLifecycleEndForNeverSeenRunDoesNotLeaveStaleActiveEntry() async -> Bool {
    let name = "rounds/0023 REWORK FAIL7 #4 self-consistency: a lifecycle phase:\"end\" event for a runId never seen before does NOT leave it marked active afterward — the new unconditional insert (any agent event with a runId) and the pre-existing terminal-frame removal happen within the same synchronous handleAgentEvent call and cancel out, leaving no observable window"
    let client = freshClient()
    let sessionID = "sess-fail7-terminal-self-consistency"
    let kernelKey = "kernel-key-fail7-terminal-self-consistency"
    let runID = "run-fail7-never-seen-before-then-ends-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // 这个 runId 此前从未出现在任何帧里——直接喂一条它的 lifecycle 终态帧（phase:"end"）。本轮新增的
    // "任意携带 runId 的 agent 事件都插入 activeRunIDsBySessionID"逻辑会在 handleAgentEvent 顶部先
    // 插入它，但该函数下方既有的终态摘除逻辑会在**同一次函数调用**里紧接着把它摘除——两者之间没有
    // 任何 await，不存在"先插入、终态摘除却棋差一招"的可观察窗口。
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "aborted": false] as JSONObject,
            "ts": 1_784_900_000_000,
        ] as JSONObject,
    ])

    let after = await client.testSupportActiveRunIDs(sessionID: sessionID)
    guard after.isEmpty else {
        return fail(name, "FAIL7 REGRESSION (self-consistency): expected activeRunIDs to remain empty after a lifecycle end frame for a never-before-seen runId, but found \(after) — the new unconditional insert is leaking a stale active entry for an already-terminal run")
    }

    await client.testSupportStubRPC(method: "chat.send") { _ in
        ["runId": runID, "status": "queued"] as JSONObject
    }
    let handle = testHandle(sessionID: sessionID, kernelKey: kernelKey)
    let options = InterruptRequestMessagePayload(input: Input(kind: .text, text: "steer text", parts: nil), mode: .steer, runID: nil)
    do {
        _ = try await client.interrupt(session: handle, options: options)
        return fail(name, "FAIL7 REGRESSION (self-consistency): expected interrupt(mode:\"steer\") to reject no_active_run_for_steer, but it was accepted — a run whose only ever-observed frame was its own terminal lifecycle end was treated as active")
    } catch KernelClientError.rpcRejected(let code, _) where code == "no_active_run_for_steer" {
        // 期望路径。
    } catch {
        return fail(name, "expected KernelClientError.rpcRejected(code:\"no_active_run_for_steer\"), got \(error)")
    }

    return pass(name, "一条从未见过的 runId 直接携带 lifecycle phase:\"end\" 帧到达时，本轮新增的『任意 agent 事件即插入』与既有的终态摘除逻辑在同一次同步函数调用里正确互相抵消（testSupportActiveRunIDs 断言为空），随后 interrupt(mode:\"steer\") 正确 reject(no_active_run_for_steer)——自我一致性成立，新增逻辑没有引入回归")
}

// MARK: - 汇总入口

func runActiveRunSnapshotTests() async -> [Bool] {
    var results: [Bool] = []
    results.append(await testSessionMessageSnapshotMarksExternallyStartedRunActive())
    results.append(await testSessionMessageSnapshotFullyReconcilesRemovingStaleActiveRuns())
    results.append(await testAgentEventAloneMarksRunActiveWithoutSessionMessage())
    results.append(await testAgentLifecycleEndForNeverSeenRunDoesNotLeaveStaleActiveEntry())
    return results
}
