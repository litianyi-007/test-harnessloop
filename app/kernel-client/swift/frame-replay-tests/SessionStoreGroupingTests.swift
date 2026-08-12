// rounds/0013 B2 —— UI 侧消息分组行为的入库确定性判据。
//
// **本文件解决的问题**：rounds/0012 ①' 把 `SessionStore.appendAssistantDelta` 的分组键从
// `(runId, index)` 改成 `messageID`、追加语义从 `+=` 改成 `=`（见 SessionStore.swift 该方法上方
// 的文档注释），但当时 `frame-replay-tests` target 在 SwiftPM 依赖图上够不到 `AgentShell`
// target（两者都是 executableTarget，SwiftPM 不允许可执行 target 之间互相 import）——
// `FrameReplayTests.swift` 里的 `testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs`
// 因此只能验证 kernel-client 的 wire-mapping 层（`mapOpenclawSessionMessageToKernelEvents`）
// 产出的 `messageID` 互异，验不到 `SessionStore.handle`/`appendAssistantDelta` 是否真的用它正确
// 分组——rounds/0012 §7a 因此被两路对抗评审判"名不副实"。
//
// rounds/0013 B2 把模型层拆成独立的 `AgentShellCore` library target（见 app/Package.swift 该
// target 定义处的注释），`frame-replay-tests` 现在可以 `@testable import AgentShellCore` 直接
// 驱动 `SessionStore.handle(_:for:)`——本文件即该测试。
//
// 和 FrameReplayTests.swift 共享同一个 `frame-replay-tests` target/module，`fail`/`pass` 两个
// 小工具（定义在 FrameReplayTests.swift）无需重新 import 即可直接用。

import Foundation
@testable import AgentShellCore
import D2Generated

/// 构造一条最小合法的 `SessionHandle`——字段取值本身在这个测试里不承载任何断言意义，只是
/// `ChatSessionViewModel.init(handle:title:)` 的必需参数。形状照抄
/// FrameReplayTests.swift 的 `testHandle` 助手（同一个 target 内本可直接复用，这里独立一份是
/// 因为两者分属不同源文件、`testHandle` 本身没有加任何跨文件可见性修饰符之外的特殊语义——保持
/// 本文件自包含，不额外引入"改 FrameReplayTests.swift 的助手可见性"这个不必要的改动）。
private func groupingTestSessionHandle(sessionID: String) -> SessionHandle {
    SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: "kernel-key-\(sessionID)", sessionID: sessionID
    )
}

/// 构造一条 `evt.message.delta` 事件——`MessageDeltaEventMessage` 各字段均为 D2Generated 的
/// public 类型/构造器（app/generated/swift/D2.swift:1555-1669），这里直接构造 Swift 值，不经过
/// JSON wire 解析——本测试要验的是 `SessionStore.handle` 收到这个事件之后的分组行为，不是
/// wire-mapping 层的 JSON 解析（那是 FrameReplayTests.swift 里
/// `testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs` 已经覆盖的另一层）。
private func groupingTestMessageDeltaEvent(
    messageID: String, runID: String, sessionID: String, delta: String
) -> EventMessageUnion {
    .messageDelta(MessageDeltaEventMessage(
        direction: .event,
        payload: MessageDeltaEventMessagePayload(delta: delta, index: 0, messageID: messageID, role: .assistant),
        runID: runID,
        sentAt: Date(),
        seq: 1,
        sessionID: sessionID,
        ts: Date(),
        type: .evtMessageDelta
    ))
}

/// **B2 核心测试**：喂两条 messageId 不同、runId 相同、index 均为 0 的 `evt.message.delta`
/// ——这正是 rounds/0011 造成文本重复的撞键形状（旧分组键 `(runId, index)` 会让两者相同，被
/// 误判成"同一条消息的后续分段"）——断言 `SessionStore.handle` 产生两个独立的
/// `session.messages` 条目，而不是被合并/追加成一条。
///
/// 直接驱动 `handle(_:for:)`（本轮为此把它从 `private` 放宽到 internal，见 SessionStore.swift
/// 该方法文档注释）而不是更底层的 `appendAssistantDelta`——`handle` 是 `consumeEvents()` 实际
/// 消费事件流时调用的入口（`for try await event in stream { handle(event, for: session) }`），
/// 走这一层是走真实分发路径，不是绕过 switch-case 直接摆一个已知会命中 `.messageDelta` 分支的
/// 调用。
///
/// **修前（rounds/0011 形态：分组键 `(runId,index)` + `+=` 追加）会 fail，修后（rounds/0012
/// 形态：分组键 `messageID` + `=` 覆盖）pass**——这是本轮任务书要求的破坏性反证，实际红/绿两次
/// 输出记在任务报告，不在此文件重复（本文件落笔时是"分组键 messageID"的绿态最终版本）。
@MainActor
func testSessionStoreHandleGroupsDistinctMessageIDsAsSeparateMessages() -> Bool {
    let name = "rounds/0013 B2: SessionStore.handle() with two DIFFERENT messageId sharing (runId, index=0) — the rounds/0011 collision shape — produces TWO separate session.messages, not one merged bubble"

    let store = SessionStore(config: KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!,
        token: "dummy-test-token",
        configWarning: nil
    ))
    let sessionID = "sess-grouping-b2-1"
    let session = ChatSessionViewModel(handle: groupingTestSessionHandle(sessionID: sessionID), title: "grouping test session")
    let runID = "run-grouping-b2-shared"

    let firstEvent = groupingTestMessageDeltaEvent(
        messageID: "msg-grouping-b2-A", runID: runID, sessionID: sessionID, delta: "first reply text"
    )
    let secondEvent = groupingTestMessageDeltaEvent(
        messageID: "msg-grouping-b2-B", runID: runID, sessionID: sessionID, delta: "second reply text"
    )

    store.handle(firstEvent, for: session)
    store.handle(secondEvent, for: session)

    guard session.messages.count == 2 else {
        return fail(name, "expected 2 separate session.messages entries, got \(session.messages.count) (texts=\(session.messages.map(\.text))) — 若被合并成 1 条，说明分组逻辑把两条不同 messageId 的消息错误地判成了同一条的后续分段（rounds/0011 的原始缺陷）")
    }
    guard session.messages[0].role == .assistant, session.messages[1].role == .assistant else {
        return fail(name, "expected both messages role == .assistant, got \(session.messages[0].role)/\(session.messages[1].role)")
    }
    guard session.messages[0].text == "first reply text" else {
        return fail(name, "expected first message text == \"first reply text\" (not concatenated with the second), got \"\(session.messages[0].text)\"")
    }
    guard session.messages[1].text == "second reply text" else {
        return fail(name, "expected second message text == \"second reply text\" (a fresh bubble, not appended onto the first), got \"\(session.messages[1].text)\"")
    }
    guard session.messages[0].id != session.messages[1].id else {
        return fail(name, "expected distinct ChatMessage.id for the two bubbles, both were \(session.messages[0].id)")
    }
    guard session.inProgressDeltaMessageID.count == 2,
          session.inProgressDeltaMessageID["msg-grouping-b2-A"] == session.messages[0].id,
          session.inProgressDeltaMessageID["msg-grouping-b2-B"] == session.messages[1].id else {
        return fail(name, "expected inProgressDeltaMessageID to hold 2 distinct entries keyed by messageID, got \(session.inProgressDeltaMessageID)")
    }

    return pass(name, "两条共享 runId=\(runID)、index=0（rounds/0011 撞键形状）、messageID 不同的 evt.message.delta，经 SessionStore.handle() 后正确产生 2 条独立 session.messages（文本互不污染，各自的气泡 id 与 inProgressDeltaMessageID 记录一致）")
}
