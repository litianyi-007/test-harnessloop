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
                .background(Color.red.opacity(0.12))
            }

            Divider()
            Button {
                Task { await store.createNewSession() }
            } label: {
                Label(store.isCreatingSession ? "新建中…" : "新建会话", systemImage: "plus.bubble")
                    .frame(maxWidth: .infinity)
            }
            .disabled(store.isCreatingSession)
            .padding(8)
        }
        .frame(minWidth: 240)
        .navigationTitle("会话")
    }

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
        .background(connectionBackground)
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

    private var connectionBackground: Color {
        if case .failed = store.connectionStatus { return Color.red.opacity(0.10) }
        return Color.clear
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
