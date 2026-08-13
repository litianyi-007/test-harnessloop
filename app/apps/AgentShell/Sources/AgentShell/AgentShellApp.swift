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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 780, minHeight: 520)
        }
        // Settings UI：标准 macOS `Settings` scene——⌘, 与 app 菜单的"设置…"自动路由到这里，不需要
        // 手工接线任何菜单项/快捷键（SwiftUI 对 `Settings` scene 的既有约定）。共享同一个 `store`
        // 实例（`.environment(store)`，与上面 WindowGroup 那份是同一个对象，不是各自新建）——这样
        // Settings 面板里点"保存并重连"才能改到主窗口实际在用的那个连接，而不是一个自己的副本。
        Settings {
            SettingsView()
                .environment(store)
        }
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

    /// 单窗口 app：关掉唯一窗口后整个进程退出，而不是变成一个没有窗口、悬在 Dock 里的空壳
    /// ——L1 是最小可见 app，没有"无窗口后台常驻"的产品需求。**Settings UI 补注**：Settings 窗口
    /// 关掉不算数——这个判断只看主 `WindowGroup` 的窗口，`Settings` scene 是独立窗口，AppKit/
    /// SwiftUI 不会把它计入"最后一个窗口"，行为与加 Settings 之前一致，未验证到需要特殊处理。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
