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
    // rounds/0021：侧栏内三条状态横幅（connectionBanner 的 failed 态背景/globalErrorMessage/
    // tokenPlaceholderHint）都要读同一份已解析的 `ChromeMaterialStyle`。
    @Environment(AppearanceSettingsStore.self) private var appearance

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
            // Settings UI 任务书决策③："Do not make the user wait for an opaque `transport
            // error` to discover they never configured anything"——effective token 仍是内建
            // 占位符时主动提示，不等用户先撞见一次连接失败才发现。
            if store.isTokenPlaceholder {
                tokenPlaceholderHint
            }

            // rounds/0017 Change 2：这里没有任何自定义不透明背景（`.listStyle(.sidebar)` 已经是
            // 系统侧栏材质），符合任务书 concrete 项 1/2"chrome 让系统材质透出、标准
            // NavigationSplitView 侧栏"。
            //
            // 视觉/交互打磨任务（2026-08-14）：熊头水印曾经短暂画在这里（`.background` 叠一层
            // `.scrollContentBackground(.hidden)` 关掉系统侧栏材质,好让水印的矢量边缘不被材质高斯
            // 模糊糊掉),后续任务书裁定把水印搬去右侧详情面板、贴右下角、旋转,不再贴在侧栏——见
            // `SessionDetailView.swift` 的 `watermarkBackground`。侧栏因此恢复成搬迁前的样子：
            // 系统 `.sidebar` 材质原样保留,不需要再关掉它。`BearWatermark.swift` 里的形状定义本身
            // 没有跟着搬迁改变（熊长什么样与它被画在哪个视图里结构上无关,见该文件头注释),只是这个
            // 文件不再是它的调用点。
            List(store.sessions, selection: $store.selectedSessionID) { session in
                SessionRow(session: session)
            }
            .listStyle(.sidebar)

            if let error = store.globalErrorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.semanticDanger)
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
                // 适配），颜色只留在文字/图标上。
                // rounds/0021：两处再各进一步——背景固定的 `.regularMaterial` 换成
                // `chromeMaterialBackground(appearance.resolvedStyle)`（用户滑块 + 无障碍红线的解析
                // 结果，与侧栏其它横幅/composer 共享同一个已解析状态，"coherent"，见 ContentView.swift
                // 该行注释）；文字前景色字面量 `.red` 换成 `.semanticDanger`（与 accentColor 结构性
                // 独立的固定语义色，AppearanceEnvironment.swift）。
                .chromeMaterialBackground(appearance.resolvedStyle)
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
    /// rounds/0021：failed 态背景从固定 `.regularMaterial` 换成 `chromeShapeStyle(appearance
    /// .resolvedStyle)`——这里是在一个条件性的 `.background { if … }` 闭包里手写 `Rectangle().fill`
    /// （不是 `.chromeMaterialBackground(_:)` modifier 调用），用免费函数版本
    /// （LiquidGlassSupport.swift `chromeShapeStyle`）就是为了覆盖这种调用形状。
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
                Rectangle().fill(chromeShapeStyle(appearance.resolvedStyle))
            }
        }
    }

    /// 占位符 token 提示——用图标+加粗文字（不是纯背景色）承载"这是个警告"这层语义。
    ///
    /// 来源为环境变量时不显示"前往设置"链接——Settings 面板对这种情况没有效果（环境变量优先级
    /// 更高，改 Settings 不会改变生效值），指错方向本身就是新的一种"改了却没用"困惑，所以改成提示
    /// 检查/取消设置那个环境变量。
    ///
    /// rounds/0021：图标颜色字面量 `.orange` 换成 `.semanticWarning`；背景固定 `.regularMaterial`
    /// 换成 `chromeMaterialBackground(appearance.resolvedStyle)`——与 `connectionBanner`/
    /// `globalErrorMessage` 同一套已解析 chrome 状态（"coherent"，见 ContentView.swift 该行注释）。
    private var tokenPlaceholderHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.semanticWarning)
                Text("尚未配置有效的内核 token")
                    .font(.caption)
                    .bold()
            }
            Group {
                if store.tokenSource == .environmentVariable {
                    Text("AGENT_SHELL_KERNEL_TOKEN 环境变量的值就是内建占位符——请改成真实 token（Settings 面板对此无效，环境变量优先级更高）。")
                } else {
                    Text("当前使用内建占位符，无法完成内核鉴权。")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if store.tokenSource != .environmentVariable {
                SettingsLink {
                    Text("前往设置…")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromeMaterialBackground(appearance.resolvedStyle)
    }

    // rounds/0021：`.connected`/`.failed` 是真正的成功/危险语义状态，字面量换成
    // `.semanticSuccess`/`.semanticDanger`。`.notConnected`（中性）/`.connecting`（进行中，不是
    // "警告"）刻意保留原样——不是每个非中性颜色都属于 success/warning/danger 语义三元组之一，见
    // AppearanceSettings.swift `SemanticColorRole` 文档注释；把它们也塞进三色语义系统会是滥用而
    // 不是覆盖。
    private var connectionColor: Color {
        switch store.connectionStatus {
        case .notConnected: return .gray
        case .connecting: return .yellow
        case .connected: return .semanticSuccess
        case .failed: return .semanticDanger
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
