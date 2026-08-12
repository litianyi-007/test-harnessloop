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
    @State private var store = SessionStore(config: .fromEnvironment())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 780, minHeight: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 单窗口 app：关掉唯一窗口后整个进程退出，而不是变成一个没有窗口、悬在 Dock 里的空壳
    /// ——L1 是最小可见 app，没有"无窗口后台常驻"的产品需求。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
