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

/// 一条 thinking 呈现单元——**rounds/0019 修复：同一 runId 内的所有 evt.thinking 合并进同一个折叠
/// 块**，取代上一轮（rounds/0017 Change 1）"逐条独立成行、刻意不跨事件合并"的设计。
///
/// **旧设计为什么错，以及为什么当时看起来合理**：旧版的理由是 D2 `ThinkingEventMessagePayload` 只有
/// `delta`/`visibility` 两个字段，没有类似 `messageId` 的分组键；而 `delta` 的真实语义因来源不同而
/// 不同（EventMapping.swift ⑤ 与①的文档注释：`agent(stream:"thinking")` 里是"相对上一次的增量"，
/// `session.message` 的 thinking content block 里是"这条已落地消息自带的完整推理投影"）——D2 事件
/// 本身在 UI 这一层无法区分两者来自哪条通道，于是套用了 `appendAssistantDelta` 那条"缺 identity 时
/// 宁可多开一行，也不要瞎猜一个键去合并"的教训，选择了"永远不合并"这个看似最保守的选项。
///
/// **这个"保守"选项被 rounds/0019 现场抓包证明是更严重的缺陷**（真实 openclaw + 真实 LLM，
/// `.harnessloop/goals/20260718-002-agent-app/rounds/0019/evidence/shots/13-approval-card.png`/
/// `14-tool-result.png`）：一段连续推理被切成十几二十个折叠块，短则两三个字符，`TOOLROW_DEMO_OK`
/// 这样一个单词被从中腰斩成 `_D` 和 `` `EMO_OK`.... `` 两条独立事件——真正的回复内容被挤出屏幕外，
/// 不是"退化成多几块"的小代价，是彻底不可读。"永远不合并"回避了一个理论上的错误合并风险，却在现场
/// 制造了一个确定发生、更糟的可读性缺陷；"缺 identity 时不要瞎猜"这条原则本身没有错，错的是
/// "runId 也不算数"这个判断——runId 并不是猜的，见下段。
///
/// **合并键 = runId（不是猜的，是排除法 + 现场验证的结论）**：D2 payload 确实没有 messageId，但
/// `ThinkingEventMessage` 信封层有 `runId`（D2.swift `ThinkingEventMessage.runID`，可选，"沿用
/// EventEnvelope 默认可选"）——这是 D2 层面唯一现存、能标识"这是不是同一轮推理"的字段。用 runId
/// 分组不会破坏 `SessionStoreGroupingTests` 锁死的 assistant 文本分组不变量（两条不同 messageId
/// 共享同一个 runId 仍产生两个气泡）——那条不变量管的是完全独立存储的 `session.messages`
/// （`messageID` 分组键），这里管的是 `session.thinkingItems`（`runID` 分组键），两个数组、两套键，
/// 互不干扰。runId 缺失时的回退与 `appendAssistantDelta` 处理 messageId 缺失同一原则不变：不复用
/// 任何既有分组键，直接开一条新行。
///
/// **合并语义 = `+=` 追加（不是 `=` 覆盖，与 assistant 文本相反）**：判定依据见
/// `SessionStore.handleThinking` 的文档注释（EventMapping.swift ⑤ 第 616 行 `data["delta"]` 优先于
/// `data["text"]`，且文档注释明说前者是"相对上一次已发送内容的增量"）；现场抓包的分片顺序拼接后是
/// 连贯文本、且单词被腰斩，与"增量、需拼接"吻合，与"每帧完整全文"矛盾。
///
/// **已知未解决的残留问题（如实登记，不是本次修复的范围）**：EventMapping.swift ①的文档注释指出
/// 同一次真实推理理论上可能同时经 session.message（完整投影）与 agent(stream:"thinking")（增量流）
/// 两条通道各自广播一次，D2 payload 结构上无法区分事件来自哪条通道。若两条通道真的在同一个 run 里
/// 都触发，`+=` 会把后到的"完整投影"当成又一段增量接在已拼好的文本后面，产生内容重复——但这不是
/// 本次修复引入的新问题：旧实现同样会把两条通道的内容都渲染出来，只是表现成"多出几行几乎一样的
/// 文本"而不是"一段文本里夹了一次重复"，两种实现都没有真正解决它，本次修复的目标是现场坐实、确定
/// 发生的"逐 delta 拆行"缺陷，不是这个尚未现场观测到、协议结构上也无法可靠区分的理论场景。
public struct ThinkingItem: Identifiable {
    public let id = UUID()
    /// **rounds/0019：从 `let` 改为 `var`**——同一轮推理的后续 delta 需要能原地追加到已有文本上
    /// （`SessionStore.handleThinking` 的 `+=`），不再是构造时一次性写死。
    public var text: String
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
