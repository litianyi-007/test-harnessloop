// 主窗口：左右分栏——左=会话列表，右=当前会话消息流（任务书 UI 最低要求第一条）。

import SwiftUI
// rounds/0013 B2：SessionStore 移到 AgentShellCore target 后，`@Environment(SessionStore.self)`
// 直接具名引用这个类型，需要显式 import。
import AgentShellCore

struct ContentView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        NavigationSplitView {
            SessionListView()
        } detail: {
            if let id = store.selectedSessionID, let session = store.session(for: id) {
                // .id(session.id) 强制在切换会话时重建 SessionDetailView（含它内部的输入框草稿
                // @State），避免草稿文本跨会话串台——L1 没有"保留每个会话未发送草稿"的产品需求。
                SessionDetailView(session: session)
                    .id(session.id)
            } else {
                emptyDetail
            }
        }
        // rounds/0017 Change 2 concrete 项 3："Add a real Toolbar with grouped actions; primary
        // action as a prominent glass button where available." ——"新建会话"从此前侧栏底部的
        // 通栏按钮（SessionListView 旧版）搬到这里：现代 macOS 原生 app（Notes/Mail/Reminders）
        // 的"新建"动作统一放在窗口工具栏而不是侧栏内容区，工具栏本身又是 HIG 明确划给 Liquid
        // Glass 的功能层（任务书分层表："sidebar, toolbar, floating controls -> Liquid Glass"）
        // ——`.primaryAction` 是 SwiftUI 对"这个窗口最主要的一个操作"的标准 placement，不论侧栏/
        // 详情哪一侧在前台都可见，天然适合一个"不属于任何单个会话、随时可点"的全局动作。
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newSessionButton
            }
        }
        .task {
            // 应用启动即尝试连接——不要求用户先点一次什么才能看到连接状态；本步不连真实 openclaw
            // 实例（任务书硬约束7），默认回环地址在没有本地隔离实例监听时会自然连接失败，这本身
            // 正好练到了"失败要在 UI 上可见"这条 UI 最低要求，不是缺陷。
            await store.connectIfNeeded()
            // rounds/0014：紧接着尝试恢复上一次进程持久化的会话清单（若连接失败，
            // restorePersistedSessionsIfNeeded() 内部会诚实放弃，不重复报错——见该方法文档注释）。
            await store.restorePersistedSessionsIfNeeded()
        }
    }

    /// 工具栏的主操作——`prominentActionButtonStyle()`（LiquidGlassSupport.swift）在 macOS 26+
    /// 渲染成 Liquid Glass 的 `.glassProminent` 按钮样式，更早系统回退到一直都在用的
    /// `.borderedProminent`。行为与此前 SessionListView 里的旧按钮完全一致（同一个
    /// `store.createNewSession()` 调用、同一个 `isCreatingSession` 禁用态），只是搬了位置、换了
    /// 视觉样式。
    private var newSessionButton: some View {
        Button {
            Task { await store.createNewSession() }
        } label: {
            if store.isCreatingSession {
                ProgressView().controlSize(.small)
            } else {
                Label("新建会话", systemImage: "plus.bubble")
            }
        }
        .disabled(store.isCreatingSession)
        .help("新建会话")
        .prominentActionButtonStyle()
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("选择左侧会话，或点击工具栏的“新建会话”开始")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
