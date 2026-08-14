// SG-10 L1 Mac UI 壳入口。
//
// SwiftUI 的 `App` 协议本身会驱动 NSApplication 的启动流程，但这套流程默认假设自己跑在一个由
// Xcode 工程生成、经 LaunchServices 正常注册的 .app bundle 里。本轮 scope-lock 硬约束1明确要求
// 不建 .xcodeproj、改用 SwiftPM + 手工组装 bundle（见 build-app-bundle.sh）——手工组装的 bundle
// 在某些启动路径下（尤其是从命令行直接跑裸二进制、或 bundle 是刚刚才拼出来、Launch Services
// 数据库还没认全它）不会自动把自己变成前台常规 App（没有 Xcode 工程帮你把 NSApplication 的这些
// 细节接好）。AppDelegate 里显式 setActivationPolicy(.regular) + activate(ignoringOtherApps:) 是
// 本文件唯一"因为不用 Xcode 工程而不得不手动补上"的部分。

import SwiftUI
import AppKit
// rounds/0013 B2：SessionStore 移到 AgentShellCore target 后，这里直接具名引用
// `SessionStore(config:)` 需要显式 import（不是成员访问链，是构造器调用本身）。
import AgentShellCore

@main
struct AgentShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Settings UI：改用 `.resolved()`（env > 已保存设置 > 内建默认值）而不是 `.fromEnvironment()`
    // （只有 env > 内建默认值两级）——这是本轮唯一一处需要改的生产代码调用点，`fromEnvironment()`
    // 本身连一个字符都没有变过（见 KernelShellConfig.swift 该函数上方的文档注释），两个函数并存。
    @State private var store = SessionStore(config: .resolved())
    // rounds/0021：外观偏好（透明度滑块 + 实时无障碍状态）——与 `store` 同样的 `@State` + `.environment`
    // 接线方式，同样在 WindowGroup 与 Settings 两个 scene 之间共享同一个实例（不是各自新建）：
    // Settings 面板拖动滑块必须实时反映到主窗口的 chrome 背景上，而不是要求用户先关掉 Settings
    // 窗口才看到效果。
    @State private var appearance = AppearanceSettingsStore()
    // rework（2026-08-14，T-114 codex 对抗评审 hardening 项）：`MenuBarExtra(isInserted:content:
    // label:)` 需要一个绑定——理由见下方 `MenuBarExtra` 调用点的完整论证。恒为 `true`：本轮
    // scope-lock 修订只授权"给图标一个宿主"，没有授权任何"隐藏/显示菜单栏图标"的用户可控开关，
    // 这个状态不接任何 UI 控件，唯一的写入路径是 SwiftUI 在用户用系统菜单栏管理手势（⌘拖出菜单栏）
    // 主动移除这个项时自动写回 `false`——那之后菜单栏图标消失，但（这正是选这个初始化器的原因）
    // app 本身不会跟着退出。
    @State private var isMenuBarExtraInserted = true

    var body: some Scene {
        // rework（2026-08-14，T-114 codex 对抗评审 hardening 项①）：`WindowGroup` 换成
        // `Window`——已直接核对 Apple 官方文档坐实两件事（不是采信评审的转述，交付报告
        // verification 记录了取证方法）：
        //   1. `OpenWindowAction` 文档："如果目标是 `WindowGroup`，系统建一个新窗口；如果目标是
        //      `Window`，系统把已存在的那一个 order front"——`Window` 天生只有一个实例，
        //      `openWindow(id:)` 打给它在语义上不可能产出重复窗口，不需要任何应用层判断。
        //   2. 本 app 从未有过、也不打算有"同时开两个主窗口"的产品需求——`newSessionButton`
        //      （ContentView.swift）新建的是**会话**（侧栏里的一条数据，切换靠选中态，不开新
        //      OS 窗口）；全仓只有 MenuBarExtraContent.swift 一处 `openWindow` 调用；没有
        //      `.commands`/`@SceneStorage` 依赖多实例语义。`MenuBarWindowSelection` 自己的文档
        //      注释更是早就断言"结构性地至多一个主窗口"——`Window` 只是把这条断言从"代码相信"
        //      变成"类型系统保证"，不是引入新约束。
        //   显式 `id`——菜单栏"显示主窗口"需要用 `openWindow(id:)` 精确点名"前置/新建的是这一个
        //   场景"。`MenuBarWindowFocus.mainWindowID`（MenuBarExtraContent.swift）是同一个常量的
        //   唯一定义，这里与该处共享同一个值,不是各自硬编码。标题"Agent Shell"只是这个场景在系统
        //   "个 Window"菜单里的条目文案与初始 fallback 标题——`SessionDetailView`/`SessionListView`
        //   已有的 `.navigationTitle(...)` 会在内容渲染后接管实际标题栏文字（既有行为，`Window`
        //   与 `WindowGroup` 在这一点上一致，不受这次切换影响）。
        //
        //   **保留、不删** `MenuBarWindowSelection.findMainWindowIndex` 与
        //   `MenuBarWindowFocus.showMainWindow` 里既有的手动查找/前置/取消最小化逻辑——那部分处理
        //   的是"已存在的窗口被最小化了，需要 `deminiaturize` 才能真的可见"，`Window` 场景的
        //   "order front"文档原文没有明确覆盖这一步，删掉这段已被测试覆盖的代码换不来任何额外收益，
        //   只会丢掉一层已验证的保护。两层叠加：`Window` 从类型系统层面排除了"重复创建"，既有的
        //   `findMainWindowIndex` 分支继续负责"已存在但被最小化"这个 `Window` 文档没写清楚的细节
        //   ——即便未来 `NSWindow.identifier` 的具体格式漂移导致这层查找失配，回退路径
        //   （`openWindow(id:)`）也不再可能产出第二个主窗口，这正是评审指出的"标识格式漂移风险"
        //   在结构上被兜住的地方。
        Window("Agent Shell", id: MenuBarWindowFocus.mainWindowID) {
            ContentView()
                .environment(store)
                .environment(appearance)
                .frame(minWidth: 780, minHeight: 520)
        }
        // Settings UI：标准 macOS `Settings` scene——⌘, 与 app 菜单的"设置…"自动路由到这里，不需要
        // 手工接线任何菜单项/快捷键（SwiftUI 对 `Settings` scene 的既有约定）。共享同一个 `store`/
        // `appearance` 实例（`.environment(...)`，与上面 WindowGroup 那份是同一个对象，不是各自
        // 新建）——这样 Settings 面板里点"保存并重连"/拖动透明度滑块才能改到主窗口实际在用的那个
        // 连接/外观状态，而不是一个自己的副本。
        Settings {
            SettingsView()
                .environment(store)
                .environment(appearance)
        }
        // rounds/0021 Scope-Lock 修订 v1 -> v2：最小菜单栏项——给已经生成、已经随包发布的
        // MenuBarIconTemplate.png/@2x（Resources/icon-source/main.swift）一个真正的宿主。只共享
        // `store`（菜单内容需要连接状态 + 当前会话名）,不共享 `appearance`——菜单内容严格限定为
        // scope-lock 修订原文列出的三项（图标/连接状态/会话名),不涉及任何 chrome 材质/透明度渲染,
        // `.menu` 样式的下拉菜单本身也不支持自定义背景材质。
        //
        // rework（2026-08-14，T-114 codex 对抗评审 hardening 项②）：改用带 `isInserted` 的初始化器
        // ——已直接核对 Apple 官方文档坐实（不是采信评审转述，交付报告 verification 记录了取证
        // 方法）：修前用的 `init(content:label:)` 的文档原文是——"Important: When this item is
        // removed from the system menu bar by the user, the application will be automatically
        // quit. **As such, it should not be used in conjunction with other scene types in your
        // App.**"——而这个 app 恰恰同时声明了 `Window` 与 `Settings` 两个其它 scene,是文档明确点名
        // 不该出现的组合：用户一旦用系统菜单栏管理手势把这个图标拖走,行为落在 Apple 未承诺的范围
        // 之外（搜索证实这类组合下确实有过 SwiftUI scene 层面的已知 bug 报告）。`init(isInserted:
        // content:label:)` 没有这条"移除即退出"的文档约束,就是为"菜单栏项之外还有主窗口/设置"这种
        // 形态设计的——绑定 `$isMenuBarExtraInserted`（属性文档见上方声明处：恒为 `true`,不接任何
        // UI,唯一的写入方是系统在用户主动移除时回写）。
        MenuBarExtra(isInserted: $isMenuBarExtraInserted) {
            MenuBarContentView()
                .environment(store)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // rounds/0019 评审 Q1（红线）：本方法此前在这里调用过一个 `SelfTestHooks.runIfRequestedAndExit()`
        // 诊断钩子——按特定环境变量把真实 Keychain token 原样 `print` 到 stdout，用于在没有 GUI
        // 自动化工具的沙箱里实测 ad-hoc 签名下的 Keychain 持久化。评审用
        // `strings app/.build/AgentShell.app/Contents/MacOS/AgentShell` 证实这些入口已经编进正式
        // 发行的 app 二进制——stdout 一旦被重定向/采集，token 就明文落盘，直接踩本轮红线（"token
        // 绝不明文落盘"）。已改用真实 GUI 自动化（System Events 输入真实 token、点击真实按钮、真实
        // quit/relaunch）验证同一件事，因此**整个 SelfTestHooks.swift 文件已删除**，不是禁用/改名
        // ——正式构建里不再存在任何能打印真实 token 的代码路径，见交付报告的 `strings` 核对结果。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// **缺陷修复（2026-08-14，live-repro）——身份决定：菜单栏常驻 app，不是"关窗口即退出"的
    /// 单窗口 app。**
    ///
    /// 这条注释此前断言"关掉唯一窗口后整个进程退出……L1 是最小可见 app，没有'无窗口后台常驻'的
    /// 产品需求"——`MenuBarExtra`（rounds/0021 Scope-Lock 修订 v1→v2）加入之后这句断言就已经和
    /// 代码实际状态脱节了：菜单栏项本身就是"给用户一个不依赖任何窗口存在的常驻入口"，而它唯一提供
    /// 的动作又恰恰是"显示主窗口"——两者合起来就是在断言一个"无窗口后台常驻"的产品形态，旧注释却
    /// 还说这个形态不存在。选哪一种身份是二选一，不能各说各话（这正是这次修复要处理的不一致本身，
    /// 不只是把 `guard` 补全）：
    ///   (A) 单窗口 app——关窗口即退出，菜单栏"显示主窗口"因此只可能是个聚焦动作，永远没有
    ///       "创建"的必要，因为退出之后菜单栏项本身也不存在了。
    ///   (B) 菜单栏常驻 app——无窗口是合法状态，"显示主窗口"必须能真的创建窗口。
    /// 选 (B)：这是 rounds/0021 用户裁定新增 `MenuBarExtra` 的唯一理由（"系统栏图标"本就是给一个
    /// 不依赖窗口存在的常驻入口），选 (A) 等于把刚授权的功能架空——用户关一次窗口，菜单栏项连同
    /// 它提供的唯一动作就永久失去意义（app 已经退出，没有进程去响应菜单点击）。因此这里改成
    /// `false`：关闭主窗口不再终止进程，app 继续以菜单栏项的形式存活，`MenuBarWindowFocus.
    /// showMainWindow(openWindow:)`（MenuBarExtraContent.swift）在这个状态下调用
    /// `openWindow(id:)` 真正创建一个新窗口，不再是旧版本那样对着空 `NSApp.windows` 静默无效。
    ///
    /// **Settings UI 补注（延续自修前）**：这个判断只看主 `WindowGroup` 的窗口，`Settings` scene
    /// 是独立窗口，AppKit/SwiftUI 不会把它计入"最后一个窗口"——这一点不受本次修复影响，`false`
    /// 同样只对主窗口的关闭生效。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
