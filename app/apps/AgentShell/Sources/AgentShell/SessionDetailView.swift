// 右侧：当前会话的消息流渲染 + 输入框/发送（任务书 UI 最低要求第三、四条）。

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
                Text("事件流中断：\(streamError)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.messages.isEmpty {
                        Text("还没有消息，在下方输入并发送")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(session.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.messages.count) {
                if let last = session.messages.last {
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
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let head = session.pendingApprovals.first {
                ApprovalCard(approval: head, sessionID: session.id)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
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

/// 一条待裁决审批的卡片：呈现「要执行什么 + 为什么要问 + 还剩多久 + 允许哪些决策」四件事，并把
/// 用户的选择回传。字段来源与取舍见 `PendingApprovalItem`（AgentShellCore/ApprovalModels.swift）。
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
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

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
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .textSelection(.enabled)
                }

                decisionButtons(expired: expired)
            }
            .padding(10)
            .background(Color.orange.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// **按钮完全由这条请求自己的 `allowedDecisions` 决定**，不是固定的一组按钮——`ask=always` 的
    /// 实例上内核只给 `["allow-once","deny"]`（`resolveExecApprovalAllowedDecisions`），此时就只
    /// 渲染两个按钮。渲染一个内核不接受的选项，点下去的后果是被服务端 `forceMalformedDeny` 静默
    /// 改写成 deny（见 makeApprovalResolveParams 文档注释），所以"不渲染"本身就是一道防线。
    @ViewBuilder
    private func decisionButtons(expired: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(approval.offeredDecisions, id: \.rawValue) { decision in
                Button(approvalDecisionButtonLabel(decision)) {
                    Task { await store.respondToApproval(reqID: approval.reqID, decision: decision, in: sessionID) }
                }
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

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 3) {
                Text(roleLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text.isEmpty ? " " : message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private var background: Color {
        switch message.role {
        case .user: return Color.accentColor.opacity(0.20)
        case .assistant: return Color.gray.opacity(0.15)
        case .system: return Color.orange.opacity(0.20)
        }
    }
}
