// 缺陷修复（2026-08-14，live-repro：菜单栏"显示主窗口"在无窗口时静默无效，见交付报告）：把
// "在一组窗口里找出哪一个是主窗口"这个纯判断逻辑收进 AgentShellCore——与 MenuBarSummary.swift
// 同一条理由，这里不重复整段论证，只重复其中直接适用的一句：`AgentShell`/`frame-replay-tests`
// 都是 executableTarget，SwiftPM 不允许两个 executable target 互相 import，可推导的判断逻辑
// 必须收在两边都能 import 的 library target 里，才谈得上"入库测试覆盖"。
//
// 本文件不 import AppKit——`NSWindow` 一律在调用方（`MenuBarExtraContent.swift`）被拍扁成
// `WindowDescriptor`（只保留判断需要的三个字段）再传进来，这里只做纯粹的数组查找，任何输入组合
// 的输出都是确定性的，不依赖真实窗口系统状态、不需要 GUI 环境即可测试。

import Foundation

/// "显示主窗口"应该前置（或据以判定"需要新建"）哪一个窗口——不是"随便一个可见窗口"，见
/// `findMainWindowIndex` 文档注释里对这条区分的具体理由。
public enum MenuBarWindowSelection {
    /// 单个窗口与判断相关的最小信息——`identifier` 对应 `NSWindow.identifier?.rawValue`。
    public struct WindowDescriptor: Equatable {
        public let identifier: String?
        public let isVisible: Bool
        public let isMiniaturized: Bool

        public init(identifier: String?, isVisible: Bool, isMiniaturized: Bool) {
            self.identifier = identifier
            self.isVisible = isVisible
            self.isMiniaturized = isMiniaturized
        }
    }

    /// 在 `windows`（`NSApp.windows` 的一份快照）里找出主窗口的下标，找不到时返回 `nil`——调用方
    /// 应把 `nil` 理解为"需要调用 `openWindow(id:)` 新建一个"，而不是再次静默放弃。
    ///
    /// **两个条件缺一不可**：
    /// 1. 可见或已最小化——已经关闭/尚未真正出现的窗口不该被前置。
    /// 2. `identifier` 以 `mainWindowID` 为前缀——`WindowGroup(id: mainWindowID)` 场景创建的窗口，
    ///    其 `NSWindow.identifier` 固定以这个字符串开头（SwiftUI 用它做窗口归属/状态恢复标识，
    ///    已实机验证：见交付报告"显示主窗口 duplicate-window 验证"一节，连续两次点击时第二次
    ///    命中的正是这个分支、`kCGWindowNumber` 与第一次相同，证明识别到的是同一个真实窗口）。
    ///
    /// **条件 2 是这次修复的核心，不是可有可无的加固**：修前的逻辑（`MenuBarWindowFocus.
    /// focusMainWindow()` 旧版本）是"`NSApp.windows` 里任意可见或已最小化窗口"，配的文档注释断言
    /// "此刻结构性地至多只有主窗口与 Settings 窗口两种，不存在需要选择的歧义"——rounds/0021 加入
    /// `AppearanceSettingsStore`/`Settings` scene 后，这条断言本身没错（确实只有这两种），但"没有
    /// 歧义"是错的：主窗口关着、只有 Settings 面板开着时，旧逻辑会把 Settings 错认成"主窗口"，前置
    /// 的是 Settings，主窗口仍然没有出现——缺陷换了个更隐蔽的形式继续存在（用户点了"显示主窗口"、
    /// 也确实有个窗口被前置了，唯独不是他要的那个）。加上 identifier 前缀过滤后，Settings 场景窗口
    /// 的 identifier 不匹配 `mainWindowID` 前缀，不会被选中，调用方会正确地转去 `openWindow(id:)`。
    ///
    /// 用 `hasPrefix` 而不是精确相等：SwiftUI 对 `WindowGroup(id:)` 场景创建的窗口，`identifier`
    /// 实测形如 `"\(mainWindowID)-AppWindow-1"`（多实例场景会在末尾递增），不是原样等于 `mainWindowID`
    /// 本身——精确相等会让这条判断在所有真实场景下都失配。
    public static func findMainWindowIndex(among windows: [WindowDescriptor], mainWindowID: String) -> Int? {
        windows.firstIndex { window in
            guard window.isVisible || window.isMiniaturized else { return false }
            guard let identifier = window.identifier else { return false }
            return identifier.hasPrefix(mainWindowID)
        }
    }
}
