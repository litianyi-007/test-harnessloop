// rounds/0021 Scope-Lock 修订 v1 -> v2（2026-08-14，最小菜单栏项）：`MenuBarExtra` 的菜单内容与
// label——严格对应修订原文的边界："只加一个 MenuBarExtra：显示 template 图标 + 连接状态 + 当前会话
// 名""不加任何新的内核操作入口——不在菜单栏里发消息、不停止、不审批""既有窗口内的一切行为一字不改"。
//
// 本文件只做两件事：①把 `MenuBarSummary`（AgentShellCore,纯函数,已在 frame-replay-tests 覆盖）算出
// 的两行文案接进 SwiftUI ②提供唯一允许的动作——"显示主窗口"（激活 app + 前置/取消最小化已有窗口,
// 没有窗口时改为创建一个,见 `MenuBarWindowFocus.showMainWindow(openWindow:)` 的 2026-08-14 缺陷修复;
// 不触碰任何 `SessionStore` 的发送/停止/审批方法）。文案判断逻辑本身不写在这里——这里只消费结果、
// 渲染成 `Text`,呼应 AppearanceEnvironment.swift 头注释确立的既定边界（判断在 AgentShellCore,视图层
// 只做最后一步纯展示转换）。

import SwiftUI
import AppKit
import AgentShellCore

/// 菜单内容——`.menuBarExtraStyle(.menu)` 下,`Text`/`Divider`/`Button` 会被渲染成标准下拉菜单的
/// 信息行/分隔线/可点击项（不是任意 SwiftUI 布局容器,`.menu` 样式对内容形状有限制,这也是为什么这里
/// 刻意只用这三种最基础的菜单可用视图,而不是 HStack/VStack 自由排布）。
struct MenuBarContentView: View {
    @Environment(SessionStore.self) private var store
    // 缺陷修复（2026-08-14，live-repro）："显示主窗口"现在需要能真的**创建**一个窗口（不只是前置
    // 已存在的），见下方 `MenuBarWindowFocus.showMainWindow(openWindow:)`。`\.openWindow` 是 SwiftUI
    // 内建环境值（不是本壳自己 `.environment(...)` 注入的自定义对象），任何位于某个 Scene 内的
    // View 都能直接拿到，不需要在 AgentShellApp.swift 里额外接线。
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 第二道防线,不是唯一防线：真正保证"不会撑穿菜单宽度"的是 `MenuBarSummary` 里对 NSError
        // 全文/会话名做的字符数截断（那一层有回归测试保护,见 MenuBarSummaryTests.swift）。这里再叠
        // 一层 `lineLimit(1)` + 固定 `frame(maxWidth:)` 是防御性冗余——万一未来某次改动让这两行绕开
        // `MenuBarSummary` 的纯函数直接拼字符串（比如有人手滑在这里加了字符串插值）,视图层这道防线
        // 仍然兜得住,不会退化回当初"整段 NSError 塞进菜单"的缺陷。这道防线本身结构性地不可测（本文件
        // 头注释已经讲过 SwiftUI 视图代码为什么够不到 frame-replay-tests）,只能靠这行注释 + 本次
        // build 验证过"能编译、语义不冲突",不冒称验证过实际渲染宽度。
        Text(MenuBarSummary.connectionStatusText(store.connectionStatus))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: MenuBarContentView.maxLineWidth, alignment: .leading)
        Text(MenuBarSummary.sessionNameText(selectedSessionTitle))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: MenuBarContentView.maxLineWidth, alignment: .leading)
        Divider()
        // 唯一允许的动作——不是内核操作入口:只做"把主窗口带到前台,不存在就创建一个"这一件事,不调用
        // `SessionStore` 的任何方法。scope-lock 修订原文："A menu item that activates/focuses the
        // main window is fine."——缺陷修复（2026-08-14）之前这里只会"前置已存在的窗口",找不到窗口
        // 时静默无效（见交付报告的 live-repro）;现在改叫 `showMainWindow(openWindow:)`,同一个按钮,
        // 语义从"聚焦"扩成"聚焦,找不到就创建",没有新增任何菜单项。
        Button("显示主窗口") {
            MenuBarWindowFocus.showMainWindow(openWindow: openWindow)
        }
    }

    /// 当前选中会话的标题——`nil` 时 `MenuBarSummary.sessionNameText` 会给出占位文案,这里不重复判断
    /// "有没有会话"这件事,只负责把 `SessionStore` 已有的两步查找（选中 id -> 对应会话）接成一个
    /// `String?` 喂给纯函数。
    private var selectedSessionTitle: String? {
        store.selectedSessionID.flatMap { store.session(for: $0) }?.title
    }

    /// 视图层这道第二防线用的宽度上限——只是一个宽松上界,不是精确量出来的像素值（本文件顶部注释
    /// 已经说明理由）。取值比"`MenuBarSummary` 截断后的字符串在最坏情况（40 个全角 CJK 字符）下
    /// 大致需要的宽度"更宽松一些,正常情况下这道防线不应该是实际生效的那一层、也不该让已经截断过的
    /// 正常文案看起来被二次裁切。
    private static let maxLineWidth: CGFloat = 320
}

/// 菜单栏图标——`MenuBarIconLoader.templateImage` 加载失败时（理论上不该发生,两条候选目录都探测
/// 不到时才会是 nil,见该类型文档注释）退化成一个中性 SF Symbol,而不是让整个菜单栏项无图标、在系统
/// 菜单栏里呈现成一个空白点击区域——"有个能点的东西、样子不对"比"完全找不到这个功能入口"更容易被
/// 用户理解成"这里有点小问题",而不是误以为这个功能压根不存在。SF Symbols 本身默认按 template 语义
/// 渲染,不需要额外处理。
struct MenuBarLabel: View {
    var body: some View {
        if let image = MenuBarIconLoader.templateImage {
            // `.renderingMode(.template)`——任务书明确点名这里不能想当然："MenuBarExtra with a
            // SwiftUI Image may not preserve template rendering the way an NSImage does." 已经用
            // 独立探针实测过（不是查文档/猜),不是假设：临时搭了一个三窗口对照 SwiftUI app,加载与
            // 生产代码同一份真实 `MenuBarIconTemplate.png`（同一个 `Bundle(url:).image(forResource:)`
            // 调用),在 `.preferredColorScheme(.light)`/`.preferredColorScheme(.dark)` 两个真实窗口
            // 里分别渲染"加 `.renderingMode(.template)`"与"不加、只留 `NSImage.isTemplate == true`"
            // 两个变体。结果：**两个变体在 dark 窗口里都正确反色成白色熊**——`Image(nsImage:)`
            // 本身已经会遵循底层 `NSImage.isTemplate`,`.renderingMode(.template)` 在这个具体场景下
            // 实测不是必需项,不是"可能不生效"。这里仍然显式保留它：零成本,且让"这张图会不会跟随
            // 菜单栏明暗反色"这件事由一个本文件写死、有正式文档保证的 SwiftUI API 兜底声明一遍,不必
            // 要求未来的读者去信一个只验证过一次、未必所有 macOS 版本都保证的隐式传导关系。
            Image(nsImage: image)
                .renderingMode(.template)
        } else {
            Image(systemName: "circle.dashed")
        }
    }
}

/// "显示主窗口"动作的唯一落点。
///
/// **缺陷修复（2026-08-14，live-repro）**：旧版本（`focusMainWindow()`）只做"前置一个已存在的窗口"，
/// 找不到窗口时 `guard` 直接静默 `return`——旧文档注释据此断言"`NSApp.windows` 结构性地至多只有
/// 主窗口与 Settings 窗口两种，不存在需要选择的歧义"，把"不创建新窗口"说成理所当然。这条断言在
/// `MenuBarExtra` 加入之前成立（那时唯一窗口关掉 `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`
/// 就会终止整个进程，"点菜单时没有窗口"根本不是一个能达到的状态）——`MenuBarExtra` 让 app 可以
/// 合法地在零窗口状态下继续存活（该方法现在返回 `false`，见 `AgentShellApp.swift` 头部对这个决定
/// 的完整论证），"没有窗口"从理论上不会发生变成了正常操作路径里随时会出现的状态，而这个函数当时
/// 唯一的应对是什么都不做——这就是那个缺陷。
///
/// 现在两步都做：
/// 1. 已有窗口——只前置/取消最小化，不创建新的（`MenuBarWindowSelection.findMainWindowIndex`
///    负责"这个窗口是不是主窗口"这个判断，AgentShellCore 里的纯函数，已有回归测试覆盖）。
/// 2. 没有——调用 `openWindow(id:)` 真正创建一个。
///
/// **`openWindow` 在已有一个窗口时会不会又开一个重复的？——已实机验证，不是继续沿用旧注释里
/// "本壳从未验证过这一点"的未决担忧**：连续两次点击"显示主窗口"，`kCGWindowNumber`
/// （每个真实 WindowServer 窗口的唯一编号）在两次点击前后保持不变——第二次命中的是上面第 1 步
/// （前置分支），`openWindow` 根本没有被第二次调用。见交付报告 verification 一节的实测记录。
enum MenuBarWindowFocus {
    /// 与 `AgentShellApp.swift` 的 `WindowGroup(id:)` 共享的同一个字符串常量——单一定义、两处
    /// 引用，改一处忘改另一处会在 `MenuBarWindowSelection` 的匹配逻辑里失配（编译期不会报错，但
    /// `findMainWindowIndex` 会永远找不到主窗口、每次点击都会新开一个），所以两边都读这一个值，
    /// 不是各自硬编码字符串。
    static let mainWindowID = "main"

    static func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows
        let descriptors = windows.map {
            MenuBarWindowSelection.WindowDescriptor(
                identifier: $0.identifier?.rawValue,
                isVisible: $0.isVisible,
                isMiniaturized: $0.isMiniaturized
            )
        }
        if let index = MenuBarWindowSelection.findMainWindowIndex(among: descriptors, mainWindowID: mainWindowID) {
            let window = windows[index]
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: mainWindowID)
    }
}
