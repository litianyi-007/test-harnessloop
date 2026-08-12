// rounds/0017 Change 1 —— "让 agent 看起来像 agent"：SessionStore.handle() 此前对
// evt.thinking/evt.tool_call/evt.tool_result 一律 `break`（旧版 SessionStore.swift:432-433），
// 本文件直接驱动 `SessionStore.handle(_:for:)`（同 SessionStoreGroupingTests.swift 的做法——走
// `consumeEvents()` 实际分发事件时经过的同一个入口，不是绕过 switch-case 摆一个已知会命中的
// 分支），断言 `session.toolCalls`/`session.thinkingItems`/`session.timeline` 产出正确的呈现条目。
//
// 和 SessionStoreGroupingTests.swift 共享同一个 `frame-replay-tests` target/module，`fail`/`pass`
// 两个小工具（定义在 FrameReplayTests.swift）无需重新 import 即可直接用。

import Foundation
@testable import AgentShellCore
import D2Generated

private func toolRenderingTestSessionHandle(sessionID: String) -> SessionHandle {
    SessionHandle(
        billing: Billing(tokenRef: "test"), createdAt: Date(), kernel: .openclaw,
        kernelSessionID: "kernel-key-\(sessionID)", sessionID: sessionID
    )
}

@MainActor
private func freshToolRenderingSession(id: String) -> (SessionStore, ChatSessionViewModel) {
    let store = SessionStore(config: KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!,
        token: "dummy-test-token",
        configWarning: nil
    ))
    let session = ChatSessionViewModel(handle: toolRenderingTestSessionHandle(sessionID: id), title: "tool rendering test session")
    return (store, session)
}

/// `JSONAny`（D2Generated）只暴露 `init(from: Decoder)`——从一段字面 JSON 文本解码是最直接的构造
/// 方式，不需要借道 KernelClient target 的 internal `makeJSONAny` helper（那是 wire 层从
/// `JSONSerialization` 产物转换用的，这里测试只需要一个合法的 `JSONAny` 实例）。只用于**已经是
/// 合法 JSON 文本**的字面量（例如 `{"command":"ls"}` 这种对象）——任意 Swift 字符串（尤其是可能
/// 含真实换行/引号的输出文本）不要传这里，见下面 `testJSONAnyString` 的文档注释。
private func testJSONAny(_ jsonLiteral: String) -> JSONAny {
    // swiftlint:disable:next force_try —— 测试固定字面量，解码失败就是测试代码本身写错了，让它炸出来。
    try! JSONDecoder().decode(JSONAny.self, from: Data(jsonLiteral.utf8))
}

/// 把任意 Swift 字符串（可能含真实换行/引号/反斜杠等控制字符）安全地编码成 JSON 字符串值再解码成
/// `JSONAny`——**不要**手写 `"\"\(s)\""` 拼引号：当 `s` 本身含真实换行字符时，拼出来的文本对 JSON
/// 语法而言是非法的（JSON 字符串内的控制字符必须转义成 `\n` 两字符序列，不能是原始换行字节，
/// RFC 8259）——这正是本文件早期版本 `testSessionStoreHandleToolResultSurfacesFailureAndPreview`
/// 用多行 `longOutput` 测长文本预览/截断时踩到的坑：`try!` 在 `JSONDecoder` 拒绝非法 JSON 时直接
/// 崩溃，报"Cannot decode JSONAny"。借道 `JSONEncoder().encode(String)` 让标准库负责转义，就不会
/// 再犯同一个错误。
private func testJSONAnyString(_ raw: String) -> JSONAny {
    let encoded = try! JSONEncoder().encode(raw) // swiftlint:disable:this force_try
    return try! JSONDecoder().decode(JSONAny.self, from: encoded) // swiftlint:disable:this force_try
}

private func toolCallEvent(
    toolCallID: String, name: String, argumentsJSON: String, runID: String = "run-tool-1", sessionID: String
) -> EventMessageUnion {
    .toolCall(ToolCallEventMessage(
        direction: .event,
        payload: ToolCallEventMessagePayload(input: testJSONAny(argumentsJSON), name: name, status: .started, toolCallID: toolCallID),
        runID: runID, sentAt: Date(), seq: 1, sessionID: sessionID, ts: Date(), type: .evtToolCall
    ))
}

/// `output` 是工具的**原始输出文本**（例如 exec 的 stdout）——和真实映射代码
/// （`EventMapping.swift` `mapOpenclawAgentCommandOutputToToolResult`：
/// `let output = makeJSONAny(data["output"] ?? "")`）一致地把它当一个纯字符串值编码，不是预先
/// 拼好的 JSON 文本，调用方不需要关心转义。
private func toolResultEvent(
    toolCallID: String, isError: Bool, durationMS: Int?, output: String, runID: String = "run-tool-1", sessionID: String
) -> EventMessageUnion {
    .toolResult(ToolResultEventMessage(
        direction: .event,
        payload: ToolResultEventMessagePayload(durationMS: durationMS, isError: isError, output: testJSONAnyString(output), toolCallID: toolCallID),
        runID: runID, sentAt: Date(), seq: 2, sessionID: sessionID, ts: Date(), type: .evtToolResult
    ))
}

private func thinkingEvent(delta: String, visibility: Visibility, runID: String = "run-tool-1", sessionID: String) -> EventMessageUnion {
    .thinking(ThinkingEventMessage(
        direction: .event,
        payload: ThinkingEventMessagePayload(delta: delta, visibility: visibility),
        runID: runID, sentAt: Date(), seq: 1, sessionID: sessionID, ts: Date(), type: .evtThinking
    ))
}

private func operationCompletedEvent(
    operationID: String, operationKind: OperationKind, outcome: PayloadOutcome, detail: String?,
    runID: String = "run-op-1", sessionID: String
) -> EventMessageUnion {
    .operationCompleted(OperationCompletedEventMessage(
        direction: .event,
        payload: OperationCompletedEventMessagePayload(
            affectedRunID: runID, detail: detail, newRunID: nil,
            operationID: operationID, operationKind: operationKind, outcome: outcome
        ),
        runID: runID, sentAt: Date(), seq: 1, sessionID: sessionID, ts: Date(), type: .evtOperationCompleted
    ))
}

/// **测试 1**：单独一条 evt.tool_call -> `session.toolCalls` 恰好一条，字段透传正确，`result`
/// 尚未到达时为 nil（"进行中"态，SessionDetailView.ToolCallRow 据此显示 ProgressView）。
@MainActor
func testSessionStoreHandleToolCallProducesToolCallItem() -> Bool {
    let name = "rounds/0017 Change 1: SessionStore.handle() with evt.tool_call produces a ToolCallItem in session.toolCalls"
    let (store, session) = freshToolRenderingSession(id: "sess-tool-call-1")

    store.handle(
        toolCallEvent(toolCallID: "tool_abc123", name: "exec", argumentsJSON: #"{"command":"ls -la"}"#, sessionID: session.id),
        for: session
    )

    guard session.toolCalls.count == 1 else {
        return fail(name, "expected 1 ToolCallItem, got \(session.toolCalls.count)")
    }
    let item = session.toolCalls[0]
    guard item.id == "tool_abc123" else {
        return fail(name, "expected ToolCallItem.id == toolCallId 'tool_abc123', got '\(item.id)'")
    }
    guard item.name == "exec" else {
        return fail(name, "expected ToolCallItem.name == 'exec', got '\(item.name)'")
    }
    guard item.argumentSummary.contains("ls -la") else {
        return fail(name, "expected argumentSummary to surface the input JSON, got '\(item.argumentSummary)'")
    }
    guard item.result == nil else {
        return fail(name, "expected result == nil before any evt.tool_result arrives (in-flight state), got \(String(describing: item.result))")
    }
    return pass(name, "evt.tool_call{toolCallId:tool_abc123,name:exec} 经 handle() 后 session.toolCalls 恰好一条，字段透传正确，result 为 nil（进行中态）")
}

/// **测试 2**：先 tool_call 后 tool_result（同一 toolCallId）——按任务书要求"pair toolResult with
/// its originating toolCall"：**原地补上结果，不新开一行**（`session.toolCalls.count` 仍是 1）。
@MainActor
func testSessionStoreHandleToolResultPairsWithMatchingToolCall() -> Bool {
    let name = "rounds/0017 Change 1: evt.tool_result with matching toolCallId pairs onto the existing ToolCallItem (not a new row)"
    let (store, session) = freshToolRenderingSession(id: "sess-tool-pair-1")

    store.handle(
        toolCallEvent(toolCallID: "tool_pair1", name: "exec", argumentsJSON: #"{"command":"echo hi"}"#, sessionID: session.id),
        for: session
    )
    store.handle(
        toolResultEvent(toolCallID: "tool_pair1", isError: false, durationMS: 42, output: "hi\n", sessionID: session.id),
        for: session
    )

    guard session.toolCalls.count == 1 else {
        return fail(name, "expected toolResult to pair onto the SAME ToolCallItem (count stays 1), got \(session.toolCalls.count) — a new row would mean pairing failed")
    }
    guard let result = session.toolCalls[0].result else {
        return fail(name, "expected session.toolCalls[0].result to be populated after evt.tool_result, got nil")
    }
    guard result.isError == false else {
        return fail(name, "expected isError == false, got true")
    }
    guard result.durationMS == 42 else {
        return fail(name, "expected durationMS == 42, got \(String(describing: result.durationMS))")
    }
    guard result.full == "hi\n" else {
        return fail(name, "expected full output == 'hi\\n' (the exec stdout string, decoded from JSONAny, not re-quoted), got '\(result.full)'")
    }
    return pass(name, "tool_call(tool_pair1) + tool_result(tool_pair1) 配对成功：session.toolCalls 仍为 1 条，result.isError=false, durationMS=42, full='hi\\n'")
}

/// **测试 3**：failure 路径——tool_result 的 isError=true 时正确透传，且 preview 是 full 的可读
/// 截断/压平（折叠态展示），不是原样多行文本。
@MainActor
func testSessionStoreHandleToolResultSurfacesFailureAndPreview() -> Bool {
    let name = "rounds/0017 Change 1: evt.tool_result with isError=true surfaces failure; preview is a flattened/truncated view of full"
    let (store, session) = freshToolRenderingSession(id: "sess-tool-fail-1")

    store.handle(
        toolCallEvent(toolCallID: "tool_fail1", name: "exec", argumentsJSON: #"{"command":"false"}"#, sessionID: session.id),
        for: session
    )
    let longOutput = "line1\nline2\n" + String(repeating: "x", count: 200)
    store.handle(
        toolResultEvent(toolCallID: "tool_fail1", isError: true, durationMS: nil, output: longOutput, sessionID: session.id),
        for: session
    )

    guard let result = session.toolCalls.first(where: { $0.id == "tool_fail1" })?.result else {
        return fail(name, "expected a paired result for tool_fail1, found none")
    }
    guard result.isError else {
        return fail(name, "expected isError == true, got false")
    }
    guard result.durationMS == nil else {
        return fail(name, "expected durationMS == nil (payload carried none), got \(String(describing: result.durationMS))")
    }
    guard !result.preview.contains("\n") else {
        return fail(name, "expected preview to be flattened (no raw newlines, for a single-line collapsed row), got '\(result.preview)'")
    }
    guard result.preview.count <= 130 else {
        return fail(name, "expected preview to be truncated to a short summary, got \(result.preview.count) chars: '\(result.preview)'")
    }
    guard result.full == longOutput else {
        return fail(name, "expected full (expanded view) to preserve the untruncated output including newlines, got '\(result.full)'")
    }
    return pass(name, "isError=true 正确透传；preview 已压平/截断（\(result.preview.count) chars，无换行）供折叠态展示，full 保留原始多行文本（\(result.full.count) chars）供展开态展示")
}

/// **测试 4**：孤儿 tool_result（没有先观察到匹配的 tool_call）——理论上不该发生（见
/// `SessionStore.handleToolResult` 文档注释），但协议层未来变化/竞态发生时不该让这条结果静默消失。
/// 退化成一张独立的占位卡片，而不是被吞掉。
@MainActor
func testSessionStoreHandleOrphanToolResultDoesNotSilentlyDrop() -> Bool {
    let name = "rounds/0017 Change 1: evt.tool_result with NO prior matching evt.tool_call still renders (does not silently drop)"
    let (store, session) = freshToolRenderingSession(id: "sess-tool-orphan-1")

    store.handle(
        toolResultEvent(toolCallID: "tool_orphan1", isError: false, durationMS: 5, output: "orphan output", sessionID: session.id),
        for: session
    )

    guard session.toolCalls.count == 1 else {
        return fail(name, "expected an orphan placeholder ToolCallItem to be created, got \(session.toolCalls.count) toolCalls (0 would mean the event was silently dropped)")
    }
    guard session.toolCalls[0].id == "tool_orphan1" else {
        return fail(name, "expected placeholder id == 'tool_orphan1', got '\(session.toolCalls[0].id)'")
    }
    guard session.toolCalls[0].result?.full == "orphan output" else {
        return fail(name, "expected the orphan result payload to still be attached, got \(String(describing: session.toolCalls[0].result))")
    }
    return pass(name, "孤儿 evt.tool_result（无匹配 toolCallId 的先行 tool_call）没有被静默丢弃：产出一张占位 ToolCallItem，result 数据完整保留")
}

/// **测试 4b（P1 REWORK，code-review-adversarial 判 REWORK 后新增）**：孤儿 evt.tool_result 建了
/// 占位项之后，姗姗来迟的 evt.tool_call **必须原地补全那张占位项**，不能再追加第二条同
/// toolCallId 的 ToolCallItem。
///
/// 这是评审指出的真实 bug（不是风格问题）：修前 `handleToolCall` 无条件 `append`，命中这个时序
/// 时会在 `session.toolCalls`（进而 `session.timeline`）里留下两条 `id` 完全相同的
/// `ConversationItem`——SwiftUI `ForEach` 要求数据源里的 id 唯一，重复 id 会让它的 diff/更新行为
/// 未定义；而且语义上更糟：`result` 永远留在先到的占位项上，新追加的这条却是 `result == nil`，
/// 呈现出"一张有结果没名字的卡片 + 一张有名字永远转圈的卡片"，实际是同一次调用被拆成了两张。
@MainActor
func testSessionStoreHandleToolCallAfterOrphanResultFillsInPlaceNotADuplicateRow() -> Bool {
    let name = "rounds/0017 P1 REWORK: evt.tool_call arriving AFTER an orphaned evt.tool_result fills the existing placeholder in place, does not create a duplicate ToolCallItem with the same id"
    let (store, session) = freshToolRenderingSession(id: "sess-tool-result-before-call-1")

    // 结果先到：走"孤儿"分支，产出一张占位 ToolCallItem（同 testSessionStoreHandleOrphanToolResultDoesNotSilentlyDrop）。
    store.handle(
        toolResultEvent(toolCallID: "tool_late_call1", isError: false, durationMS: 7, output: "done", sessionID: session.id),
        for: session
    )
    guard session.toolCalls.count == 1 else {
        return fail(name, "setup failed: expected the orphan result to create exactly 1 placeholder, got \(session.toolCalls.count)")
    }

    // 姗姗来迟的 call。
    store.handle(
        toolCallEvent(toolCallID: "tool_late_call1", name: "exec", argumentsJSON: #"{"command":"sleep 1 && echo done"}"#, sessionID: session.id),
        for: session
    )

    guard session.toolCalls.count == 1 else {
        return fail(name, "expected the late-arriving tool_call to fill the EXISTING placeholder in place (count stays 1), got \(session.toolCalls.count) — a second row means the id-collision bug is back")
    }
    let item = session.toolCalls[0]
    guard item.id == "tool_late_call1" else {
        return fail(name, "expected the single item's id to still be 'tool_late_call1', got '\(item.id)'")
    }
    guard item.name == "exec" else {
        return fail(name, "expected name to be filled in from the late-arriving tool_call ('exec'), got '\(item.name)' — if this still shows the orphan placeholder text, the call did not get merged in")
    }
    guard item.argumentSummary.contains("sleep 1") else {
        return fail(name, "expected argumentSummary to be filled in from the late-arriving tool_call, got '\(item.argumentSummary)'")
    }
    guard let result = item.result, result.full == "done" else {
        return fail(name, "expected the result attached by the earlier orphan tool_result to be PRESERVED after the call fills in, got \(String(describing: item.result))")
    }

    // 唯一性判定的核心：整条 timeline 里这个 toolCallId 只能贡献一个 ConversationItem.id
    // （SwiftUI ForEach 的 identity 契约就是靠这个撑住的）。
    let timelineIDs = session.timeline.map(\.id)
    let toolCallItemIDs = timelineIDs.filter { $0 == "toolCall-tool_late_call1" }
    guard toolCallItemIDs.count == 1 else {
        return fail(name, "expected exactly 1 ConversationItem with id 'toolCall-tool_late_call1' in session.timeline, found \(toolCallItemIDs.count) — duplicate ids break SwiftUI ForEach identity")
    }

    return pass(name, "evt.tool_result 先到产出占位项，随后 evt.tool_call 原地补全 name='exec'/argumentSummary（含 'sleep 1'），保留已有 result='done'；session.toolCalls 与 session.timeline 均只贡献 1 条、id 无重复")
}

/// **测试 5**：thinking 逐条独立成行，不跨事件合并——两条 evt.thinking 各自产出独立的
/// `ThinkingItem`，第二条不覆盖/拼接第一条。理由见 `ThinkingItem` 类型定义处的文档注释（D2
/// thinking payload 没有分组键，猜一个会重演 rounds/0011 的同构缺陷）。
@MainActor
func testSessionStoreHandleThinkingEventsDoNotMerge() -> Bool {
    let name = "rounds/0017 Change 1: two evt.thinking events produce two independent ThinkingItems (no cross-event merge)"
    let (store, session) = freshToolRenderingSession(id: "sess-thinking-1")

    store.handle(thinkingEvent(delta: "先看看目录结构", visibility: .raw, sessionID: session.id), for: session)
    store.handle(thinkingEvent(delta: "再决定下一步", visibility: .raw, sessionID: session.id), for: session)

    guard session.thinkingItems.count == 2 else {
        return fail(name, "expected 2 independent ThinkingItems, got \(session.thinkingItems.count) (texts=\(session.thinkingItems.map(\.text))) — merging would collapse them into 1")
    }
    guard session.thinkingItems[0].text == "先看看目录结构", session.thinkingItems[1].text == "再决定下一步" else {
        return fail(name, "expected each ThinkingItem to keep its own delta text unmodified, got \(session.thinkingItems.map(\.text))")
    }
    guard session.thinkingItems[0].visibility == .raw else {
        return fail(name, "expected visibility == .raw to be threaded through from the payload, got \(session.thinkingItems[0].visibility)")
    }
    return pass(name, "两条 evt.thinking 各自产出独立 ThinkingItem（未合并/覆盖），visibility 字段正确透传")
}

/// **测试 6**：`visibility == .summary`（对应 redacted_thinking，见 EventMapping.swift ①）同样被
/// 忠实透传，不被悄悄改写成 `.raw`——ThinkingRow 用这个字段区分"推理"/"推理摘要"两种标签，不能把
/// 已脱敏内容冒充成完整原始推理。
@MainActor
func testSessionStoreHandleThinkingPreservesSummaryVisibility() -> Bool {
    let name = "rounds/0017 Change 1: evt.thinking with visibility=summary is preserved as-is, not silently upgraded to raw"
    let (store, session) = freshToolRenderingSession(id: "sess-thinking-summary-1")

    store.handle(thinkingEvent(delta: "[redacted]", visibility: .summary, sessionID: session.id), for: session)

    guard session.thinkingItems.count == 1, session.thinkingItems[0].visibility == .summary else {
        return fail(name, "expected 1 ThinkingItem with visibility == .summary, got \(session.thinkingItems.map { ($0.text, $0.visibility) })")
    }
    return pass(name, "visibility=summary 原样保留，未被升级成 raw")
}

/// **测试 7（核心）**：混合事件序列（message -> toolCall -> thinking -> toolResult(配对) ->
/// message）经 `session.timeline` 合并后，**保持真实到达顺序**——这是"让 agent 看起来像
/// agent"这条改动的核心承诺：工具调用/思考必须出现在它们真实发生的时间点，而不是被甩到消息列表
/// 末尾或按类型分组。toolResult 因为配对到已有的 toolCall 上，不产生新的 timeline 条目
/// （5 个事件 -> 4 个 timeline 条目）。
@MainActor
func testSessionStoreTimelineInterleavesEventsInArrivalOrder() -> Bool {
    let name = "rounds/0017 Change 1 (核心): session.timeline interleaves message/toolCall/thinking in true arrival order, not grouped by type"
    let (store, session) = freshToolRenderingSession(id: "sess-timeline-order-1")

    store.handle(.messageDelta(MessageDeltaEventMessage(
        direction: .event,
        payload: MessageDeltaEventMessagePayload(delta: "我先看看目录", index: 0, messageID: "msg-order-1", role: .assistant),
        runID: "run-order-1", sentAt: Date(), seq: 1, sessionID: session.id, ts: Date(), type: .evtMessageDelta
    )), for: session)
    store.handle(toolCallEvent(toolCallID: "tool_order1", name: "exec", argumentsJSON: #"{"command":"ls"}"#, sessionID: session.id), for: session)
    store.handle(thinkingEvent(delta: "目录看起来是空的", visibility: .raw, sessionID: session.id), for: session)
    store.handle(toolResultEvent(toolCallID: "tool_order1", isError: false, durationMS: 3, output: "", sessionID: session.id), for: session)
    store.handle(.messageDelta(MessageDeltaEventMessage(
        direction: .event,
        payload: MessageDeltaEventMessagePayload(delta: "目录是空的，我先创建一个文件", index: 0, messageID: "msg-order-2", role: .assistant),
        runID: "run-order-1", sentAt: Date(), seq: 2, sessionID: session.id, ts: Date(), type: .evtMessageDelta
    )), for: session)

    let items = session.timeline
    guard items.count == 4 else {
        return fail(name, "expected 4 timeline items (2 messages + 1 toolCall(paired) + 1 thinking; the tool_result should NOT add a 5th), got \(items.count)")
    }

    func describe(_ item: ConversationItem) -> String {
        switch item {
        case .message: return "message"
        case .toolCall: return "toolCall"
        case .thinking: return "thinking"
        }
    }
    let kinds = items.map(describe)
    guard kinds == ["message", "toolCall", "thinking", "message"] else {
        return fail(name, "expected arrival-order sequence [message, toolCall, thinking, message], got \(kinds) — tool calls/thinking must appear where they actually happened, not grouped or reordered")
    }

    guard case .toolCall(let toolItem) = items[1] else {
        return fail(name, "expected items[1] to be the toolCall entry")
    }
    guard toolItem.result != nil else {
        return fail(name, "expected the toolCall entry to already carry its paired result (tool_result arrived before the second message), got nil")
    }
    guard case .message(let firstMessage) = items[0], firstMessage.text == "我先看看目录" else {
        return fail(name, "expected items[0] to be the first assistant message with its original text")
    }
    guard case .message(let secondMessage) = items[3], secondMessage.text == "目录是空的，我先创建一个文件" else {
        return fail(name, "expected items[3] to be the second assistant message with its original text")
    }

    return pass(name, "5 个事件（message/toolCall/thinking/toolResult/message）经 timeline 合并后产出 4 条、顺序为 [message,toolCall(已配对结果),thinking,message]——与真实到达顺序一致")
}

/// **测试 8**：evt.operation_completed 渲染成一条系统消息（不是静默 break）——见
/// `SessionStore.handleOperationCompleted` 的文档注释：这个变体只由 stop()/interrupt() 触发，L1
/// 本身不调用两者，但事件流不是"只包含本壳发起操作"的过滤流，保留渲染防止"发生过却无声"。
@MainActor
func testSessionStoreHandleOperationCompletedRendersSystemMessage() -> Bool {
    let name = "rounds/0017 Change 1: evt.operation_completed appends a system ChatMessage (not a silent break)"
    let (store, session) = freshToolRenderingSession(id: "sess-opcompleted-1")

    store.handle(
        operationCompletedEvent(
            operationID: "op-1", operationKind: .stop, outcome: .succeeded, detail: "aborted by user",
            sessionID: session.id
        ),
        for: session
    )

    guard let last = session.messages.last else {
        return fail(name, "expected evt.operation_completed to append a system ChatMessage, got session.messages empty")
    }
    guard last.role == .system else {
        return fail(name, "expected role == .system, got \(last.role)")
    }
    guard last.text.contains("stop"), last.text.contains("succeeded"), last.text.contains("aborted by user") else {
        return fail(name, "expected the system message to surface operationKind/outcome/detail, got '\(last.text)'")
    }
    return pass(name, "evt.operation_completed(kind=stop,outcome=succeeded,detail='aborted by user') 渲染成一条系统消息：'\(last.text)'")
}
