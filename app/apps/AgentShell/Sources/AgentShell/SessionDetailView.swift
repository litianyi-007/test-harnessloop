// 右侧：当前会话的消息流渲染 + 输入框/发送（任务书 UI 最低要求第三、四条）。
//
// rounds/0017 两项改动都主要落在这个文件：
//   - Change 1（让 agent 看起来像 agent）：`messageList` 从只渲染 `session.messages`（纯文本气泡）
//     改成渲染 `session.timeline`（`ChatMessage`/`ToolCallItem`/`ThinkingItem` 按到达顺序合并的
//     统一视图，见 AgentShellCore/ConversationItems.swift），新增 `ToolCallRow`/`ThinkingRow` 两个
//     呈现组件。
//   - Change 2（Liquid Glass 视觉升级）：审批卡片与错误横幅换成标准 material（不是 glassEffect——
//     HIG 分层：消息流本身是内容层，审批卡片是内容层卡片，两者都不该用 glassEffect，见
//     LiquidGlassSupport.swift 头注释引用的任务书分层表）、滚动列表加滚动边缘效果、决策按钮用
//     Liquid Glass 按钮样式（颜色只落在按钮背景上，卡片本身不带色块）。

import SwiftUI
// rounds/0013 B2：SessionStore/ChatSessionViewModel/ChatMessage 移到 AgentShellCore target
// 后，本文件里 `@Environment(SessionStore.self)`、`let session: ChatSessionViewModel`、
// `let message: ChatMessage` 都直接具名引用这些类型，需要显式 import。
import AgentShellCore

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var store
    let session: ChatSessionViewModel

    @State private var draftText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            if !session.pendingApprovals.isEmpty {
                Divider()
                approvalSection
            }
            if let streamError = session.streamError {
                streamErrorBanner(streamError)
            }
            Divider()
            composer
        }
        .navigationTitle(session.title)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(session.title).font(.headline)
            Text("kernel=\(session.handle.kernel.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if session.isWaitingForReply {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("等待回复…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
    }

    /// rounds/0017 Change 1：渲染 `session.timeline`（消息/工具调用/thinking 按到达顺序合并的
    /// 统一视图）而不是此前只渲染 `session.messages`（纯文本气泡）——这是"让 agent 看起来像
    /// agent"这条改动的核心落点：工具调用/结果/思考现在和对话文本出现在同一条时间线里，而不是
    /// 只有"你说一句它说一句"。
    ///
    /// Change 2：`.softScrollEdgeEffect` 让滚动到顶部/底部时内容在 header/composer 下方自然虚化
    /// （任务书 concrete 项 4），macOS 26+ 生效、更早系统是 no-op（见 LiquidGlassSupport.swift）。
    private var messageList: some View {
        let items = session.timeline
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text("还没有消息，在下方输入并发送")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(items) { item in
                        TimelineRow(item: item).id(item.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .softScrollEdgeEffect([.top, .bottom])
            .onChange(of: items.count) {
                if let last = items.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    /// rounds/0015 C：待审批请求区。放在消息流与输入框**之间**——它是阻塞性的（agent 正卡在这条
    /// 审批上等人回答），比输入框更需要被看到，但又不该盖住上方的对话上下文（用户往往要看了前文
    /// 才知道这条命令合不合理）。刻意不用 `.alert`/`.sheet`：本壳全程不弹模态（见
    /// SessionStore.globalErrorMessage 的注释——scope-lock 验收要求起窗口验证过程中不能有模态挡住
    /// 界面），审批也不例外；何况模态会把"看前文再决定"这件事变得不可能。
    ///
    /// **rounds/0015 返工①（D1 §6.2）：改为串行呈现——只渲染队头那一条卡片。**
    ///
    /// 此前这里把 `session.pendingApprovals` **全部平铺**，注释还把它写成一个刻意的产品选择
    /// （"用户需要知道总共有几条在等，而不是被一条条推着做决定"）。那个选择与 D1 §6.2 直接冲突：
    /// "同一 session 同一时刻只暴露一个 active pending 审批请求"，且 D1 末句明写这**不是** UI
    /// 呈现优化而是运行时并发分支。真正的收口做在适配器层（`OpenclawGatewayKernelClient` 的审批
    /// FSM：第二条及以后的请求进 FIFO 缓冲队列，根本不 yield `approval_request`），所以正常情况下
    /// `pendingApprovals` 里本就只会有一条。
    ///
    /// **rounds/0016（T-096 第 4 项）：删掉了那行"另有 N 条审批在排队"的队列徽标。**
    ///
    /// T-096 原文："队列徽标应接真实缓冲计数或删除（不得显示编造的数字）。"这里选**删除**，理由是
    /// "接真实缓冲计数"在当前架构下做不到、也不该做：
    ///  - 那个 N 取的是 `session.pendingApprovals.count - 1`，而这个数组里**只可能**装适配器真正
    ///    yield 过 `approval_request` 的条目。缓冲队列里的请求按 D1 §6.2 从不被 yield，所以这个
    ///    数字与真实缓冲深度**没有任何关系**——rounds/0016 起 `SessionStore` 对 `.approvalRequest`
    ///    改为"先清旧卡再呈现"之后，它更是恒为 0，这一行连触发的机会都没有了。
    ///  - 要拿到真实缓冲计数，只能让壳绕过 D2 事件流去问适配器要内部状态——那要么改 D1 七法窄腰
    ///    （本轮红线明令禁止），要么在契约之外另开一条侧信道（架构上更糟）。而且 D1 §6.2 原文要求
    ///    缓冲中的请求"不立即以任何形式呈现给调用方，**不触发新的可见 pending 状态**"，一个实时
    ///    队列徽标恰恰是它要防的那种可见状态。
    ///  - 缓冲请求的可见性由 D1 指定的通道负责，不由徽标负责：它们终态化时会经
    ///    `approval_buffer_resolved`（buffered_timeout / queue_overflow）在会话流里留下系统行。
    ///
    /// rounds/0017 Change 2：外层此前自带一层 `Color.orange.opacity(0.08)` 背景，和内层
    /// `ApprovalCard` 自己的卡片背景形成"色块套色块"的双重着色——删掉外层背景，卡片视觉身份完全
    /// 交给 `ApprovalCard` 自己的 `contentCardBackground()`（标准 material，任务书对审批卡片的
    /// 明确要求），这里只做纯布局（padding），不再重复上色。
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let head = session.pendingApprovals.first {
                ApprovalCard(approval: head, sessionID: session.id)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// rounds/0017 Change 2 concrete 项 8：此前是 `Color.red` 实心背景 + 白字——换成标准 material
    /// （自动适配 Dark Mode/Increase Contrast/Reduce Transparency）+ 语义红前景色 + 图标（给不依赖
    /// 颜色的第二条信号）。这是一条贯穿整个内容区宽度的状态横幅，不是一张"嵌套在窗口里的卡片"，
    /// 所以不用 `contentCardBackground()`（那个方法专为"需要圆角、可能嵌套同心圆角"的卡片设计）——
    /// 直接铺满宽度的 material，不裁形状。
    private func streamErrorBanner(_ message: String) -> some View {
        Label("事件流中断：\(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入消息…", text: $draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)
            Button("发送", action: send)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .prominentActionButtonStyle()
        }
        .padding(10)
    }

    private func send() {
        let text = draftText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draftText = ""
        Task { await store.sendMessage(text, in: session.id) }
    }
}

/// rounds/0017 Change 1：`session.timeline` 的每个条目按类型分派到对应的呈现组件。
private struct TimelineRow: View {
    let item: ConversationItem

    var body: some View {
        switch item {
        case .message(let message):
            MessageBubble(message: message)
        case .toolCall(let tool):
            ToolCallRow(tool: tool)
        case .thinking(let thinking):
            ThinkingRow(thinking: thinking)
        }
    }
}

/// 一条 evt.tool_call/evt.tool_result 呈现——任务书原话："a distinct, compact row … visually
/// different from user/assistant bubbles"；"Pair toolResult with its originating toolCall …
/// show success/failure plus a collapsed result preview that can be expanded."
///
/// 内容层元素——背景用标准 material（`contentCardBackground`），不用 `glassEffect`：HIG 分层表
/// 明确"消息流本身是内容层，永远不对气泡用 glassEffect"，工具调用行是消息流的一部分，同一条规则
/// 适用，不因为它是新加的就单独破例。
private struct ToolCallRow: View {
    let tool: ToolCallItem
    @State private var isResultExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tool.name)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                    if !tool.argumentSummary.isEmpty {
                        Text(tool.argumentSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if let result = tool.result {
                    resultDisclosure(result)
                } else {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("运行中…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCardBackground(cornerRadius: 8)
    }

    @ViewBuilder
    private func resultDisclosure(_ result: ToolResultSummary) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isResultExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isResultExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text(result.isError ? "失败" : "成功")
                    .font(.caption2)
                    .foregroundStyle(result.isError ? .red : .green)
                if let ms = result.durationMS {
                    Text("\(ms)ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !isResultExpanded, !result.preview.isEmpty {
                    Text(result.preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)

        if isResultExpanded {
            Text(result.full.isEmpty ? "(空结果)" : result.full)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .insetContentBackground()
        }
    }

    private var statusIconName: String {
        guard let result = tool.result else { return "wrench.and.screwdriver" }
        return result.isError ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        guard let result = tool.result else { return .secondary }
        return result.isError ? .red : .green
    }
}

/// 一条 evt.thinking 呈现——任务书原话："Show thinking in a visually de-emphasized way, collapsed
/// by default. Respect thinkingVisibility if the payload carries it." D2 payload 的 `visibility`
/// 字段就是 wire 层对"thinkingVisibility 协商结果"的落地（D2 schema events/thinking.schema.json
/// 的 `$comment`：'visibility 对应 CapabilityDescriptorPayload.thinkingVisibility 协商结果'）——
/// "尊重"体现在：`.raw`/`.summary` 都默认折叠、弱化展示，但标签如实区分两者（`.summary` 对应
/// `redacted_thinking` 内容块，见 EventMapping.swift ①，即内核自己对这段内容做过脱敏/摘要），不
/// 把"摘要"包装成"完整原始推理"冒充。
private struct ThinkingRow: View {
    let thinking: ThinkingItem
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(thinking.text.isEmpty ? "(空)" : thinking.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                Text(visibilityLabel)
                if !isExpanded, !thinking.text.isEmpty {
                    Text(thinking.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
    }

    private var visibilityLabel: String {
        switch thinking.visibility {
        case .raw: return "推理"
        case .summary: return "推理摘要"
        }
    }
}

/// 一条待裁决审批的卡片：呈现「要执行什么 + 为什么要问 + 还剩多久 + 允许哪些决策」四件事，并把
/// 用户的选择回传。字段来源与取舍见 `PendingApprovalItem`（AgentShellCore/ApprovalModels.swift）。
///
/// rounds/0017 Change 2：内容层卡片，标准 material（`contentCardBackground`），不是
/// `glassEffect`——任务书对审批卡片的明确硬约束。颜色只落在决策按钮的 tint 上
/// （`peerActionButtonStyle(tint:)`），卡片本身、命令预览、错误提示都不再用固定不透明度的
/// `Color.orange`/`Color.red` 色块，换成语义色前景 + material/层级填充背景，跟随 Dark Mode/
/// Increase Contrast 自动适配。
private struct ApprovalCard: View {
    @Environment(SessionStore.self) private var store
    let approval: PendingApprovalItem
    let sessionID: String

    var body: some View {
        // TimelineView 每秒重算一次剩余时间——倒计时是 UI 的呈现职责，模型层不持有定时器
        // （PendingApprovalItem.remainingSeconds(now:) 是纯函数，把"现在几点"当参数传进去）。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = approval.hasLocallyExpired(now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                    Text(approval.headline).font(.headline)
                    Spacer()
                    Text(countdownLabel(now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(expired ? .red : .secondary)
                }

                // 要执行的东西本身——等宽字体 + 可选中，命令必须能被逐字读清、能复制出去核对。
                Text(approval.bodyText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetContentBackground()

                if let reason = approval.reasonText {
                    Text("原因：\(reason)").font(.caption).foregroundStyle(.orange)
                }
                if let agentID = approval.summary.agentID {
                    Text("请求方 agent=\(agentID)  reqId=\(approval.reqID)")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }

                // 内核声明了、但本适配器认不出的决策取值——如实显示，不假装它不存在（见
                // ApprovalPresentationSummary.unmappedAllowedDecisions 的文档注释）。
                if !approval.summary.unmappedAllowedDecisions.isEmpty {
                    Text("内核还允许本壳不支持的决策：\(approval.summary.unmappedAllowedDecisions.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let error = approval.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentCardBackground(cornerRadius: 4)
                        .textSelection(.enabled)
                }

                decisionButtons(expired: expired)
            }
            .padding(10)
            .contentCardBackground(cornerRadius: 8)
        }
    }

    /// **按钮完全由这条请求自己的 `allowedDecisions` 决定**，不是固定的一组按钮——`ask=always` 的
    /// 实例上内核只给 `["allow-once","deny"]`（`resolveExecApprovalAllowedDecisions`），此时就只
    /// 渲染两个按钮。渲染一个内核不接受的选项，点下去的后果是被服务端 `forceMalformedDeny` 静默
    /// 改写成 deny（见 makeApprovalResolveParams 文档注释），所以"不渲染"本身就是一道防线。
    ///
    /// rounds/0017 Change 2：每个决策按钮用 `peerActionButtonStyle(tint:)`——"平级选项"玻璃样式
    /// （不是 `prominentActionButtonStyle`：这几个按钮谁都不比谁更"首选"，D1 契约允许任意子集/顺序
    /// 出现，硬编码其中一个更突出是编造了一个协议没有承诺的优先级），tint 按语义区分允许/拒绝——
    /// 这正是任务书"颜色只出现在按钮背景上"的落点。
    @ViewBuilder
    private func decisionButtons(expired: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(approval.offeredDecisions, id: \.rawValue) { decision in
                // tint 直接内联判断（`decision == .deny`），不拆成一个带显式类型标注的独立函数——
                // `AgentShell` target 依赖图上只列了 `AgentShellCore`（不直接依赖 `D2Generated`，
                // 见 app/Package.swift 该 target 定义处的注释），这个文件本来就不 `import
                // D2Generated`，只能靠类型推断使用 `ApprovalDecisionKindElement` 的值（`decision`
                // 参数由 `approval.offeredDecisions` 的元素类型推断得到），不能在函数签名里显式
                // 拼出这个类型名——和本文件其它地方（`kind.rawValue`、`session.handle.kernel.
                // rawValue`）用的是同一条既有约束，不是这里新引入的限制。
                Button(approvalDecisionButtonLabel(decision)) {
                    Task { await store.respondToApproval(reqID: approval.reqID, decision: decision, in: sessionID) }
                }
                .peerActionButtonStyle(tint: decision == .deny ? .red : .accentColor)
                .disabled(approval.isSubmitting || expired)
            }
            if approval.isSubmitting {
                ProgressView().controlSize(.small)
            }
            Spacer()
            // 两种情况下这张卡片可能已经没法再操作了，各留一个"关掉"的出口，避免卡片永久赖在界面上：
            //   - 已过本地倒计时：内核大概率已 timeout-deny，再点决策无意义；
            //   - 出过错：错误可能是"决策已在内核侧终态化"（例如内核没兑现、或审批在 RPC 在途期间
            //     被 stop() 强制 deny），此时再点任何按钮都只会得到 approval_not_pending。
            //     **不自动移除**——错误信息必须先被用户看到，由用户自己确认后关掉。
            if expired || approval.errorMessage != nil {
                Button("关闭") { store.dismissApproval(reqID: approval.reqID, in: sessionID) }
            }
        }
    }

    private func countdownLabel(now: Date) -> String {
        guard let remaining = approval.remainingSeconds(now: now) else {
            return "超时未知" // timeoutMS 不可算时如实说，不显示一个假的 00:00
        }
        if remaining == 0 { return "已超时（本地判断）" }
        return String(format: "剩余 %02d:%02d", remaining / 60, remaining % 60)
    }
}

/// **rounds/0017 返工（code-review-adversarial 判 REWORK，P2）**：修前这里仍是
/// `Color.accentColor/.gray/.orange.opacity(...)` 三个固定不透明度色块当气泡背景——不只是没有
/// 严格执行任务书"内容层必须 standard material"的硬约束，更实际的问题是**无障碍**：固定 alpha
/// 的颜色叠加不会随用户打开的 Increase Contrast 设置自动提高对比度（系统 material/层级前景色会，
/// 手写的 `Color(...).opacity(...)` 不会——两者是完全不同的渲染路径），评审判定这是阻断项。
///
/// 修法选了"严格执行硬约束"这一支（而不是退而求其次换层级填充色）：背景统一换成
/// `contentCardBackground()`（标准 material，和工具调用行/审批卡同一个助手，Dark Mode/Increase
/// Contrast/Reduce Transparency 全部由系统负责，不再有任何一处手写不透明度）；发言者的区分改由
/// **对齐 + 角色标签 + 小图标**三重信号共同承担，不再依赖气泡底色——图标本身的着色是小号前景
/// 字形而不是大面积背景填充，不重演同一类问题。
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: roleIconName)
                        .font(.caption2)
                        .foregroundStyle(roleIconColor)
                    Text(roleLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.text.isEmpty ? " " : message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .contentCardBackground(cornerRadius: 10)
            }
            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "我"
        case .assistant: return "assistant"
        case .system: return "系统"
        }
    }

    private var roleIconName: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "info.circle.fill"
        }
    }

    /// 沿用修前三种气泡底色本来的语义配色（accent/中性/橙），只是把着色对象从"大面积背景填充"
    /// 换成"一个小号图标字形"——小号前景字形不会重演"固定 alpha 背景不随 Increase Contrast 提升
    /// 对比度"这个问题：文字本体的对比度由它下面的 `contentCardBackground()`（标准 material）
    /// 保证，图标只是一个锦上添花的、不承载必读信息的辅助扫视线索。
    private var roleIconColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .secondary
        case .system: return .orange
        }
    }
}
