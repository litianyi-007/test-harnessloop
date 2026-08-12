// 左侧栏：连接状态指示 + 会话列表 + 新建会话入口。
//
// 全程不使用 .alert()/.sheet()/.confirmationDialog() 等模态 UI——错误一律用内嵌色块文字呈现。
// 这不只是风格选择：scope-lock 验收要求起窗口验证过程中不能触发任何模态对话框，而本壳的默认
// 连接目标在没有本地隔离内核监听时会立刻连接失败（见 ContentView 的 .task 注释）——如果错误呈现
// 用的是 .alert()，仅仅"打开这个 app 看一眼"这个动作本身就会自动弹出一个模态框，直接违反验收
// 约束。内嵌横幅没有这个问题，顺带也更符合"不要求好看，要求能看出状态"的 L1 尺度。

import SwiftUI
// rounds/0013 B2：SessionStore/ChatSessionViewModel 移到 AgentShellCore target 后，本文件里
// `@Environment(SessionStore.self)`、`let session: ChatSessionViewModel` 都直接具名引用这些
// 类型，需要显式 import。
import AgentShellCore

struct SessionListView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            connectionBanner
            if let warning = store.configWarning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // rounds/0017 Change 2：这里此前没有任何自定义不透明背景（`.listStyle(.sidebar)` 已经
            // 是系统侧栏材质），符合任务书 concrete 项 1/2"chrome 让系统材质透出、标准
            // NavigationSplitView 侧栏"——不需要改动。
            List(store.sessions, selection: $store.selectedSessionID) { session in
                SessionRow(session: session)
            }
            .listStyle(.sidebar)

            if let error = store.globalErrorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        store.globalErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                // rounds/0017 Change 2 concrete 项 8：此前是不透明度固定的 `Color.red.opacity(0.12)`
                // ——换成标准 material（跟随 Dark Mode/Increase Contrast/Reduce Transparency 自动
                // 适配），颜色只留在文字/图标上（上面的 `.foregroundStyle(.red)` 本来就是语义色，
                // 不用改）。
                .background(.regularMaterial)
            }
        }
        .frame(minWidth: 240)
        .navigationTitle("会话")
        // "新建会话"本轮搬到窗口工具栏（ContentView.swift `newSessionButton`，rounds/0017 Change 2
        // concrete 项 3）——侧栏底部不再需要这个通栏按钮；行为（同一个 store.createNewSession()
        // 调用、同一个 isCreatingSession 禁用态）完全保留，只是不再是侧栏内容区的一部分，呼应
        // "让内容区/侧栏回归标准布局，操作归工具栏"的现代 macOS 设计语言。
    }

    /// **rounds/0017 返工（code-review-adversarial 判 REWORK，P2 的第二处）**：修前 failed 态的
    /// 背景是 `Color.red.opacity(0.10)`——同一类固定 alpha 不随 Increase Contrast 提升对比度的
    /// 问题（见 MessageBubble 头注释，判据相同）。这里状态信号本来就有两条不依赖背景色的通道：
    /// `connectionColor` 圆点（小号前景字形，同 MessageBubble 图标的道理）+ `connectionText` 直接
    /// 用文字写出"连接失败：…"（内容本身就说明了状态，不依赖颜色）。failed 态额外给一层标准
    /// material 只是让这一行在侧栏里稍微"抬"一点视觉权重，不是唯一的状态信号，因此可以老实换成
    /// material 而不必纠结"颜色该编码在哪"。
    private var connectionBanner: some View {
        HStack(spacing: 6) {
            Circle().fill(connectionColor).frame(width: 8, height: 8)
            Text(connectionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if case .failed = store.connectionStatus {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private var connectionColor: Color {
        switch store.connectionStatus {
        case .notConnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var connectionText: String {
        switch store.connectionStatus {
        case .notConnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected(let scopes): return "已连接（scopes: \(scopes.joined(separator: ", "))）"
        case .failed(let message): return "连接失败：\(message)"
        }
    }
}

private struct SessionRow: View {
    let session: ChatSessionViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                if let last = session.messages.last {
                    Text(last.text.isEmpty ? "…" : last.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if session.isWaitingForReply {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
