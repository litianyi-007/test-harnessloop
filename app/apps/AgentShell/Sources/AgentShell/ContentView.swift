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

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("选择左侧会话，或点击“新建会话”开始")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
