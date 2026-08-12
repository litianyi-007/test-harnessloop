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

    public init(handle: SessionHandle, title: String) {
        self.id = handle.sessionID
        self.handle = handle
        self.title = title
    }
}
