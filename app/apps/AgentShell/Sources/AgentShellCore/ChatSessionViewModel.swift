// 单个会话在壳里的可观察视图模型——包一层 SessionHandle（D1 §2.1 createSession 的返回值，
// app/generated/swift/D2.swift:3829），附加 UI 专属状态（消息列表、是否在等回复、事件流本身是否
// 出错）。

import Foundation
import Observation
import D2Generated

/// **可见性变更（rounds/0013 B2）**：类本身与视图层实际读取的成员改为 `public`（理由同
/// ChatModels.swift 头注释——`AgentShell` 视图层现在跨模块普通 import 消费这个类型）。
/// `inProgressDeltaMessageID` 维持 internal——只有 `SessionStore.swift`（同模块）和本轮新增的
/// `SessionStoreGroupingTests.swift`（`@testable import`）需要读它，`AgentShell` 视图层从不触碰，
/// 不放宽。
@MainActor
@Observable
public final class ChatSessionViewModel: Identifiable {
    /// Identifiable：直接用 D1 §2.1 步骤 1 预分配的 sessionId（不是 kernelSessionId）作为 UI 层的
    /// 稳定标识，和侧栏列表选中状态绑定的 Binding<String?> 共用同一个类型。存成独立的
    /// `nonisolated let`（而不是读 `handle.sessionID` 的计算属性）——`Identifiable.id` 协议要求本身
    /// 是 nonisolated 的，`handle` 是 MainActor 隔离属性，跨隔离域读它需要 `await`，计算属性做不到；
    /// 单独存一份不可变的 `String`（值类型、天然 Sendable）就没有这个问题，Swift 6 语言模式下这是
    /// 标准写法。
    public nonisolated let id: String
    public let handle: SessionHandle
    public var title: String
    public var messages: [ChatMessage] = []

    /// rounds/0017 Change 1：evt.tool_call 驱动的工具调用卡片，按到达顺序 append；evt.tool_result
    /// 到达时原地更新其中一条的 `result`（不新开一行）。和 `messages` 各自独立存储——不能塞进
    /// `messages`（那会破坏"messages 只由 evt.message.delta 驱动"这条既有不变量,
    /// SessionStoreGroupingTests.swift 直接依赖它），交叉时序由 `timeline` 计算属性负责合并。
    public var toolCalls: [ToolCallItem] = []

    /// rounds/0017 Change 1：evt.thinking 驱动，逐条独立 append（不跨事件合并，理由见
    /// `ThinkingItem` 类型定义处的文档注释）。
    public var thinkingItems: [ThinkingItem] = []

    /// send() 已成功发出、但对应 runId 尚未收到 evt.turn_complete/evt.error/evt.session_end 之一
    /// ——呼应 D5.1（~/.llm-wiki/agent-app-design/product/d5-1-message-flow.md）§2 "RUNNING" 状态
    /// 的定义方式（该 runId 尚未出现 TurnCompleteEvent 就算仍在跑）。L1 只取这一个布尔位用来驱动
    /// "有没有在等回复"这一条 UI 最低要求，不做 D5.1 完整的 Turn 状态机（SUBMITTING/INTERRUPTING
    /// 等细分属于 L2 才需要的精细化）。
    public var isWaitingForReply = false

    /// subscribe() 返回的事件流本身（而非某一条 evt.error 消息）中断时记录在这里——和消息流里插入
    /// 的"[错误]"系统行是两回事：这是"整条事件流管道断了"，那是"agent 在这次 run 里报了个错但
    /// 事件流还活着"。两者都要在 UI 上可见（scope-lock RAE-0001 条件④"失败可诊断"）。
    public var streamError: String?

    /// rounds/0015 C：当前等待用户裁决的审批请求（`evt.approval_request` 驱动）。按到达顺序排列，
    /// 一条审批被裁决（内核确认终态）或被 `stop()` 强制终态化后从这里移除——**不保留已终态条目**，
    /// 审批历史浏览明确不在本轮范围内（见 PendingApprovalItem 的"范围克制"注释）。
    public var pendingApprovals: [PendingApprovalItem] = []

    /// evt.message.delta 按 messageID（wire session.message payload.messageId，rounds/0012 ①' 新增
    /// 字段）分组用的映射：key -> 对应消息气泡的 id。**rounds/0012 前**曾用 (runId, index) 做键，
    /// 已被实测证明会在同一 run 产出多条 assistant 消息时撞车导致文本重复；现改用 messageID。分组
    /// 依据与回退策略见 SessionStore.appendAssistantDelta 的文档注释。
    var inProgressDeltaMessageID: [String: UUID] = [:]

    /// rounds/0017 Change 1：`messages`/`toolCalls`/`thinkingItems` 三个独立存储的数组按
    /// `timelineSeq` 合并排序后的统一呈现视图——`SessionDetailView` 只需要对着这一个数组做一次
    /// `ForEach`，不必自己操心三类事件的交叉时序。
    ///
    /// 每次访问都重新 `append`+`sorted`（O(n log n)）——这个壳是演示/验证场景，单会话消息量级
    /// 不构成性能问题；换成增量维护一个已排序数组会让三处独立的 append 点（handle() 的
    /// messageDelta/toolCall/thinking 分支）都要多做一次插入定位，复杂度增加但这个量级下换不来
    /// 实际收益。`sorted(by:)` 是稳定排序（Swift 标准库保证），`timelineSeq` 相同时保留原始
    /// 相对顺序，不会出现同 key 乱序的问题（正常不会发生同 key——`allocateLiveTimelineSeq()` 严格
    /// 递增；防御性地记录这一点)。
    public var timeline: [ConversationItem] {
        var items: [ConversationItem] = []
        items.reserveCapacity(messages.count + toolCalls.count + thinkingItems.count)
        items.append(contentsOf: messages.map(ConversationItem.message))
        items.append(contentsOf: toolCalls.map(ConversationItem.toolCall))
        items.append(contentsOf: thinkingItems.map(ConversationItem.thinking))
        return items.sorted { $0.timelineSeq < $1.timelineSeq }
    }

    /// `timeline` 统一排序键分配器——不用 `Date()`（wall-clock）。理由：`SessionStore.backfillHistory`
    /// （rounds/0014 C）与 `consumeEvents`（本类型实时事件消费循环）各自独立并发运行
    /// （backfillHistory 文档注释："两者各自独立并发运行,理论上一个新事件有可能在这次历史回填完成
    /// 之前就先到达"），历史回填有可能在若干实时事件已经落地之后才完成。若用 `Date()` 排序，"迟到"
    /// 的历史消息会因为 `Date()` 更大而被排到实时消息后面，打破 `session.messages.insert(contentsOf:
    /// at:0)` 已经确立的产品选择——历史消息恒定渲染在这个会话所有实时内容之前，不因为回填完成得晚
    /// 就被实时项挤到中间（同一条文档注释："无论谁先谁后都不会丢内容——最坏情况只是历史消息与这条
    /// "抢跑"的实时消息在时间上略微交错"，即数组位置才是这里的产品承诺，不是挂钟时间）。显式计数器
    /// 不依赖任何挂钟时间假设，只依赖"SessionStore 调用 allocate*() 的顺序即真实处理顺序"这一点——
    /// 这个类是 `@MainActor` 隔离的，同一个会话不会有两次并发调用互相竞争这两个计数器。
    private var nextLiveTimelineSeq = 0

    /// `allocateHistoryTimelineSeqs(count:)` 已经分配出去的最小键——独立于 `nextLiveTimelineSeq`
    /// 维护，保证即使该方法被调用不止一次（当前实际调用模式是每个会话恰好一次，见该方法文档注释），
    /// 后一批历史键仍然严格小于前一批，不会两批区间重叠。
    private var historyTimelineSeqCeiling = 0

    /// 实时到达的一条 message/toolCall/thinking 项在 `SessionStore` 构造它的当下取号，严格递增。
    func allocateLiveTimelineSeq() -> Int {
        defer { nextLiveTimelineSeq += 1 }
        return nextLiveTimelineSeq
    }

    /// `SessionStore.backfillHistory()` 批量取号——一次性返回一段恒为负数的区间（因此恒小于
    /// `allocateLiveTimelineSeq()` 此前或此后任何一次的结果，也恒小于本方法自己此前任何一次调用
    /// 分配过的区间），数组下标 0（records 里最早的历史记录，`historyChatMessage(from:)` 的调用
    /// 顺序）拿到本批次最小的键，使整批历史消息在合并后的 `timeline` 里始终排在这个会话所有实时项
    /// 之前——无论 backfillHistory() 这次调用相对 consumeEvents() 实际完成得多晚。每个会话目前只会
    /// 被调用一次（`restorePersistedSessionsIfNeeded()` 对每条持久化记录只触发一次
    /// backfillHistory）；`historyTimelineSeqCeiling` 的存在是为了不依赖"只调用一次"这个假设也能
    /// 给出正确答案（万一未来加了分页加载更多历史，多次调用会各自拿到一段全新的、比之前任何一次
    /// 结果都更小的负数区间，不会互相碰撞）。
    func allocateHistoryTimelineSeqs(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let ceiling = min(historyTimelineSeqCeiling, nextLiveTimelineSeq) - count
        historyTimelineSeqCeiling = ceiling
        return (0..<count).map { ceiling + $0 }
    }

    public init(handle: SessionHandle, title: String) {
        self.id = handle.sessionID
        self.handle = handle
        self.title = title
    }
}
