// rounds/0015 C 块：审批 UI 的呈现模型。
//
// 背景（为什么这一块是本轮做的）：这个 mac 壳里的 agent 此前可以在宿主机上**直接执行 shell 命令，
// 没有任何确认关卡**——那不是隔离实例的特例，是 openclaw 未配置审批策略时的内核默认
// （`kernels/openclaw/src/infra/exec-approvals.ts:317-318`：`DEFAULT_SECURITY = "full"`、
// `DEFAULT_ASK = "off"`，`requiresExecApproval` 因此恒为 false，内核从不发起审批）。本轮把
// `ask` 打开（D 块，隔离实例 env 门控）并把壳侧的审批回路补齐（A/B/C 三块）。
//
// 与 ChatModels.swift 同类：这些类型**不是** D1/D2 契约的一部分，是壳自己的呈现模型。D2 只给到
// `evt.approval_request`（`ApprovalRequestEventMessage`）这一个事件，其 `payload.payload` 是
// `JSONAny` 形态的"该 kind 下的不透明详情"——把它解释成可显示字段的是 kernel-client 层的
// `summarizeApprovalPresentation`（EventMapping.swift ⑧），本文件只负责"解释完之后 UI 怎么拿"。

import Foundation
import D2Generated
import KernelClient

/// 一条等待用户裁决的审批请求。
///
/// **范围克制（任务书明确要求）**：只保留"做出这一次裁决"所必需的字段——工具/命令内容、请求上下文、
/// 超时时刻、允许的决策、以及这一条自己的提交中/出错状态。刻意**不做**审批历史浏览（已终态的审批
/// 直接从列表里移除，不留归档视图）、**不做**成本面板。
public struct PendingApprovalItem: Identifiable, Equatable {
    /// D1 §2.6 `respondApproval(reqID:)` 的关联主键（= 内核 approval id，见
    /// `ApprovalRequestEventMessagePayload.reqID` 的契约注释）。同时用作 UI 列表的 `Identifiable.id`
    /// ——审批天然按 reqId 唯一，不需要另铸一个 UUID。
    public let reqID: String
    public var id: String { reqID }

    /// 这条审批归属的 run（D2 事件的 `runID`）与 tool call。UI 上不直接显示，但保留：出问题时
    /// （比如决策发出后 run 已经被 abort）能对上号，且 `stop()` 的强制 deny 也按 run 归集。
    public let runID: String
    public let toolCallID: String

    /// D2 收窄后的 kind（exec/file_write/mcp/sandbox/tool）。openclaw 原始 kind 见 `summary.openclawKind`
    /// ——两者不是一一对应（plugin 与 system-agent 都落到 D2 的 `.tool`），显示时以原始值优先。
    public let kind: KindElement

    /// 从 `payload.payload` 提炼出的可显示详情 + **这条请求自己允许的决策集合**。
    public let summary: ApprovalPresentationSummary

    /// 事件自带的 `ts`（这条审批在内核侧产出的时刻）与 `timeoutMS`（`expiresAtMs - createdAtMs`，
    /// exec 审批的内核默认值是 30 分钟 = 1_800_000ms，见 `exec-approvals.ts:315`
    /// `DEFAULT_EXEC_APPROVAL_TIMEOUT_MS`）。
    public let requestedAt: Date
    public let timeoutMS: Int

    /// 超时时刻。`timeoutMS <= 0`（内核没给出可算的窗口）时为 nil——UI 据此显示"超时未知"，
    /// 而不是显示一个由 0 算出来的、看起来"已经超时"的假倒计时。
    public var expiresAt: Date? {
        guard timeoutMS > 0 else { return nil }
        return requestedAt.addingTimeInterval(Double(timeoutMS) / 1000.0)
    }

    /// 正在等 `respondApproval()` 返回——按钮置灰，防止重复提交（一条审批只有一次机会：内核侧
    /// 首个到达的决策就是终态，见 `approval.resolve` 的 `applied` 语义）。
    public var isSubmitting: Bool = false

    /// 这一条自己的错误（决策被客户端校验拦下、RPC 失败、或内核没兑现决策）。**行内显示**，
    /// 不弹模态、也不并进整条事件流的红色横幅——沿用本壳既有的"错误必须可见但不打断"原则
    /// （ChatModels.swift 对 `.system` 角色的定位、SessionStore.globalErrorMessage 的用法）。
    public var errorMessage: String?

    public init(
        reqID: String, runID: String, toolCallID: String, kind: KindElement,
        summary: ApprovalPresentationSummary, requestedAt: Date, timeoutMS: Int
    ) {
        self.reqID = reqID
        self.runID = runID
        self.toolCallID = toolCallID
        self.kind = kind
        self.summary = summary
        self.requestedAt = requestedAt
        self.timeoutMS = timeoutMS
    }

    /// 直接从 D2 事件构造——UI 层不碰 `JSONAny`，解释工作全部由 kernel-client 的
    /// `summarizeApprovalPresentation` 完成（理由见该函数文档注释）。
    public init(event: ApprovalRequestEventMessage) {
        self.init(
            reqID: event.payload.reqID,
            runID: event.runID,
            toolCallID: event.payload.toolCallID,
            kind: event.payload.kind,
            summary: summarizeApprovalPresentation(event.payload),
            requestedAt: event.ts,
            timeoutMS: event.payload.timeoutMS
        )
    }

    /// 卡片标题栏上那行"这是什么审批"。exec 审批取 openclaw 原始 kind + host，其余 kind 取
    /// presentation 的 title；都没有时退回 D2 的 kind——不编造。
    public var headline: String {
        if let title = summary.title, !title.isEmpty { return title }
        let kindLabel = summary.openclawKind ?? kind.rawValue
        if let host = summary.host, !host.isEmpty { return "\(kindLabel) @ \(host)" }
        return kindLabel
    }

    /// 卡片正文：要执行的东西本身。exec 是 `commandText`（命令全文），plugin/system-agent 是
    /// `description`。两者都没有时如实说明——**不拿 kind 名冒充命令内容**。
    public var bodyText: String {
        if let command = summary.commandText, !command.isEmpty { return command }
        if let detail = summary.detailText, !detail.isEmpty { return detail }
        return "(内核未提供可显示的详情)"
    }

    /// 「请求原因」。openclaw 的 exec presentation **没有独立的 reason 字段**
    /// （`ExecApprovalPresentationSchema` 字段集：kind/commandText/commandPreview/warningText/
    /// host/nodeId/agentId/allowedDecisions），最接近的就是 `warningText`（内核为什么觉得这条命令
    /// 需要人来看一眼，例如 heredoc、allowlist 计划在本平台不可用）。没有 warningText 时返回 nil，
    /// UI 就不显示这一行——**不编造一段"原因"文本**。
    public var reasonText: String? {
        guard let warning = summary.warningText, !warning.isEmpty else { return nil }
        return warning
    }

    /// 剩余时间（秒，向下取整，不为负）。UI 每秒重算一次（`TimelineView`），模型自己不持有定时器。
    public func remainingSeconds(now: Date = Date()) -> Int? {
        guard let expiresAt else { return nil }
        return max(0, Int(expiresAt.timeIntervalSince(now)))
    }

    /// 本地判断已过内核给出的超时窗口。**只是本地判断**：真正的终态由内核持有，openclaw 的
    /// `session.approval(phase:"terminal")` 事件在 D2 十一变体里没有对应位置
    /// （EventMapping.swift ④ 文档注释：terminal reason 词表与 D1 `ApprovalBufferResolvedEvent`
    /// 完全不相交，如实不映射），所以壳收不到"它超时了"的推送。这里据倒计时到零把卡片标成已超时、
    /// 按钮停用，是诚实呈现"这条大概率已经失效"，不是声称内核已确认——用词上也保持这个分寸。
    public func hasLocallyExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// UI 该渲染哪些决策按钮。**只来自这条请求自己携带的 `allowedDecisions`**（经
    /// `d2ApprovalDecisionKind(forOpenclawWire:)` 翻译），不是固定四个按钮。
    ///
    /// `allow_session` 结构性地不会出现在这里——openclaw 的 `ApprovalAllowedDecisionsSchema` 元素
    /// 类型就是三值闭合联合，没有 session 档位（完整依据见
    /// `openclawApprovalDecisionWire(forD2:)` 的文档注释）。也就是说"UI 上不提供该选项"不是靠一句
    /// 过滤实现的，而是数据本身就到不了这里；即便将来内核真的新增了 session 语义的值，它也会先
    /// 落进 `summary.unmappedAllowedDecisions`（显示成"不支持的选项"），而不会变成一个点了会被
    /// 静默改写的按钮。
    public var offeredDecisions: [ApprovalDecisionKindElement] { summary.allowedDecisions }
}

/// 决策按钮上的中文标签。deny 与 allow 分列，`allow_always` 明确点出"以后不再询问"——这是持久化
/// 授权，用户必须知道自己在授什么。
public func approvalDecisionButtonLabel(_ kind: ApprovalDecisionKindElement) -> String {
    switch kind {
    case .allowOnce: return "允许一次"
    case .allowAlways: return "总是允许（持久化，以后不再询问）"
    case .allowSession: return "本会话内允许"
    case .deny: return "拒绝"
    }
}
