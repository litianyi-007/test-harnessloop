// rounds/0017 Change 1 —— 让 agent 看起来像 agent：SessionStore.handle() 此前对 evt.thinking/
// evt.tool_call/evt.tool_result 三个 D2 变体一律 `break`（SessionStore.swift:432-433 旧版），UI
// 只看得到"用户说一句、assistant 答一句"，agent 实际做了什么（调了哪个工具、传了什么参数、跑出
// 什么结果）全部不可见，除非恰好触发一张审批卡片。本文件是这三个变体的呈现模型——和 ChatModels.swift/
// ApprovalModels.swift 同类：不是 D1/D2 契约的一部分，是壳自己的呈现层。

import Foundation
import D2Generated

/// 一次工具调用在消息流里的呈现单元。**通常**由 evt.tool_call 创建，随后若/当匹配的
/// evt.tool_result 到达（按 toolCallId 配对——D2 ToolResultEventMessagePayload.toolCallID 的契约
/// 就是拿来对上 evt.tool_call 的 toolCallID，见两个 payload 各自的字段注释），原地补上 `result`，
/// 不新开一行。**但两者到达顺序在协议层没有保证**（rounds/0017 返工，P1 REWORK 坐实过一次真实
/// 时序：evt.tool_result 先到）——`toolCallID` 相同的 call/result 无论谁先谁后，最终都必须收敛成
/// **同一条** `ToolCallItem`，不能因为先到的是哪一个就产生两条同 id 的卡片。配对逻辑分别在
/// `SessionStore.handleToolCall`/`handleToolResult`，两者互为对称：先到的一方建行，后到的一方按
/// `toolCallID` 查表原地补全，谁都不会覆盖已经落在这张卡片上的另一半信息。
public struct ToolCallItem: Identifiable {
    /// toolCallId 本身天然唯一（同一次调用只会有一个 evt.tool_call），直接拿来当
    /// `Identifiable.id`，不额外铸 UUID——和 `PendingApprovalItem` 用 reqID 当 id 是同一个先例。
    public let id: String

    /// **rounds/0017 返工（code-review-adversarial 判 REWORK，P1）**：`name`/`argumentSummary`
    /// 从 `let` 改成 `var`——`evt.tool_result` 有可能先于它自己的 `evt.tool_call` 到达
    /// （`SessionStore.handleToolResult` 的"孤儿"分支会先建一张占位项），随后姗姗来迟的
    /// `evt.tool_call` 必须能**原地**把占位名/空摘要改写成真实值，而不是新建第二条同 `id` 的
    /// `ToolCallItem`（那会让 `ConversationItem.id` 在 `timeline` 里出现重复，破坏 SwiftUI
    /// `ForEach` 的唯一 identity 要求——真实 bug，不是风格问题，见 `SessionStore.handleToolCall`
    /// 的文档注释）。`id`/`timelineSeq` 仍然是 `let`：一旦这个 toolCallId 的行第一次出现在
    /// `toolCalls` 里（不论是从 call 观测到的还是从 result 观测到的），它的身份和 timeline 位置
    /// 就固定了，只有内容字段可以之后被原地补全。
    public var name: String
    /// 从 payload.input（JSONAny，见 JSONPreview.swift）提炼出的单行摘要，供折叠态展示。
    public var argumentSummary: String
    /// 见 ChatMessage.timelineSeq 的文档注释——同一套跨数组合并排序机制，不重复解释。
    let timelineSeq: Int
    public var result: ToolResultSummary?

    public init(id: String, name: String, argumentSummary: String, timelineSeq: Int, result: ToolResultSummary? = nil) {
        self.id = id
        self.name = name
        self.argumentSummary = argumentSummary
        self.timelineSeq = timelineSeq
        self.result = result
    }
}

/// 配对到某条 `ToolCallItem` 上的结果——由 evt.tool_result 产生。`preview`/`full` 均来自
/// payload.output（JSONAny）经 JSONPreview 提炼，前者截断供折叠态展示，后者不截断供展开态展示。
public struct ToolResultSummary: Equatable {
    public let isError: Bool
    public let durationMS: Int?
    public let preview: String
    public let full: String

    public init(isError: Bool, durationMS: Int?, preview: String, full: String) {
        self.isError = isError
        self.durationMS = durationMS
        self.preview = preview
        self.full = full
    }
}

/// 一条 thinking 呈现单元。evt.thinking 逐条独立成行——**刻意不做跨事件合并**：D2
/// `ThinkingEventMessagePayload` 只有 `delta`/`visibility` 两个字段，没有任何类似 `messageId` 的
/// 分组键；而这条 `delta` 的真实语义因来源不同而不同（EventMapping.swift ⑤ 与①的文档注释：
/// `agent(stream:"thinking")` 里是"相对上一次的增量"，`session.message` 的 thinking content block
/// 里是"这条已落地消息自带的完整推理投影"）——D2 事件本身在 UI 这一层已经无法区分两者。
/// `SessionStore.appendAssistantDelta` 的文档注释记录过同一类教训（旧分组键 (runId,index) 撞车
/// 导致两条不同消息的文本被错误拼接）："缺 identity 时宁可多开一条气泡，也不要瞎猜一个键去分组/
/// 合并"。这里应用同一条原则：每条 evt.thinking 独立成一行折叠展示，代价是同一次真正的增量推理流
/// 会显示成多个小块而不是一整段，但不会重演"猜错合并语义导致内容错误拼接/覆盖"的同构缺陷。
public struct ThinkingItem: Identifiable {
    public let id = UUID()
    public let text: String
    public let visibility: Visibility
    let timelineSeq: Int

    public init(text: String, visibility: Visibility, timelineSeq: Int) {
        self.text = text
        self.visibility = visibility
        self.timelineSeq = timelineSeq
    }
}

/// `ChatSessionViewModel.timeline` 把 `messages`/`toolCalls`/`thinkingItems` 三个独立存储的数组
/// 按 `timelineSeq` 合并排序后转成的统一呈现类型——视图层只需要对着 `timeline` 做一次 `ForEach`，
/// 不必自己操心三类事件的交叉时序（也无法：三个数组各自的内部顺序含义不同，见
/// `ChatSessionViewModel.timeline` 的文档注释）。三个 case 分别包一层已有的呈现模型，不重复定义
/// 字段。
public enum ConversationItem: Identifiable {
    case message(ChatMessage)
    case toolCall(ToolCallItem)
    case thinking(ThinkingItem)

    public var id: String {
        switch self {
        case .message(let m): return "message-\(m.id.uuidString)"
        case .toolCall(let t): return "toolCall-\(t.id)"
        case .thinking(let t): return "thinking-\(t.id.uuidString)"
        }
    }

    var timelineSeq: Int {
        switch self {
        case .message(let m): return m.timelineSeq
        case .toolCall(let t): return t.timelineSeq
        case .thinking(let t): return t.timelineSeq
        }
    }
}
