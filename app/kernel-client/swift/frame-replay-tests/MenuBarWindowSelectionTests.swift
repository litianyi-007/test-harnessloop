// 缺陷修复（2026-08-14，live-repro）回归测试：`MenuBarWindowSelection.findMainWindowIndex(among:
// mainWindowID:)`（AgentShellCore/MenuBarWindowSelection.swift）——菜单栏"显示主窗口"用它判断
// "现有窗口里有没有一个是主窗口"。SwiftUI 视图代码本身（`MenuBarExtra` 内容、真实 `NSApp.windows`
// 交互）结构性地不可达 frame-replay-tests（`AgentShell`/`frame-replay-tests` 都是
// executableTarget，见 MenuBarSummaryTests.swift 头注释），这里覆盖的是挪出来的纯判断部分——用
// 构造出的 `WindowDescriptor` 数组模拟"主窗口关着、Settings 开着"等真实窗口状态组合，不需要真的
// 起一个窗口系统。

import Foundation
@testable import AgentShellCore

private typealias Descriptor = MenuBarWindowSelection.WindowDescriptor

// MARK: - 核心修复场景：Settings 窗口不能被误认成主窗口

/// **这条测试直接钉住本次修复的理由**：主窗口关着、只有 Settings 面板开着——修前的旧逻辑
/// （"任意可见或已最小化窗口"）会把这唯一的可见窗口（Settings）错认成主窗口，调用方就不会转去
/// `openWindow(id:)`，主窗口永远不会被创建。新逻辑必须返回 `nil`。
func testFindMainWindowIndexReturnsNilWhenOnlyASettingsLikeWindowIsVisible() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 在只有一个 identifier 不匹配的可见窗口（模拟 Settings）时返回 nil"
    let windows = [Descriptor(identifier: "com_apple_SwiftUI_settings_window", isVisible: true, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == nil else {
        return fail(name, "expected nil（不应该把 Settings 窗口错认成主窗口）, got \(String(describing: result))")
    }
    return pass(name, "唯一可见窗口的 identifier 不匹配 \"main\" 前缀时，正确返回 nil，不会误把 Settings 当成主窗口")
}

/// 完全没有窗口（`NSApp.windows` 为空数组）——最直接对应 live-repro 里"零窗口"的那个状态。
func testFindMainWindowIndexReturnsNilForEmptyWindowList() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 在窗口列表为空时返回 nil"
    let result = MenuBarWindowSelection.findMainWindowIndex(among: [], mainWindowID: "main")
    guard result == nil else {
        return fail(name, "expected nil, got \(String(describing: result))")
    }
    return pass(name, "空窗口列表正确返回 nil")
}

// MARK: - 正常找到主窗口

/// SwiftUI 对 `WindowGroup(id:)` 场景创建的窗口，`identifier` 实测形如
/// `"main-AppWindow-1"`（见 MenuBarWindowSelection.swift 文档注释），不是原样等于 `"main"`——
/// 这条测试钉住"必须用 `hasPrefix`，精确相等会在真实场景下永远失配"。
func testFindMainWindowIndexMatchesRealisticSwiftUIAssignedIdentifierWithSuffix() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 匹配 SwiftUI 实际赋值的 \"main-AppWindow-1\" 这类带后缀 identifier"
    let windows = [Descriptor(identifier: "main-AppWindow-1", isVisible: true, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == 0 else {
        return fail(name, "expected index 0, got \(String(describing: result))")
    }
    return pass(name, "identifier \"main-AppWindow-1\" 通过 hasPrefix(\"main\") 正确匹配到主窗口")
}

/// identifier 恰好等于 `mainWindowID`（没有后缀）也应该匹配——`hasPrefix` 天然覆盖精确相等这个
/// 特例，不需要额外分支。
func testFindMainWindowIndexMatchesExactIdentifierEqualToMainWindowID() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 匹配 identifier 恰好等于 mainWindowID（无后缀）的窗口"
    let windows = [Descriptor(identifier: "main", isVisible: true, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == 0 else {
        return fail(name, "expected index 0, got \(String(describing: result))")
    }
    return pass(name, "identifier 精确等于 \"main\" 时同样正确匹配")
}

/// 已最小化但不在 `isVisible` 意义上可见——原逻辑（`focusMainWindow` 旧版本）同样接受这种状态，
/// 新逻辑必须保留这条行为（不能因为加了 identifier 过滤就意外收窄了可最小化窗口的覆盖）。
func testFindMainWindowIndexMatchesMiniaturizedMainWindow() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 匹配已最小化（不在 Dock 之外可见）的主窗口"
    let windows = [Descriptor(identifier: "main-AppWindow-1", isVisible: false, isMiniaturized: true)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == 0 else {
        return fail(name, "expected index 0（已最小化窗口应该被选中以便调用方 deminiaturize）, got \(String(describing: result))")
    }
    return pass(name, "已最小化（isVisible=false, isMiniaturized=true）的主窗口正确被选中")
}

/// 多窗口场景：主窗口不在数组第 0 位——防止实现偷懒地假设"匹配到的一定是第一个元素"，必须真的按
/// 下标返回、且下标是主窗口真实所在的位置。
func testFindMainWindowIndexReturnsCorrectIndexWhenMainWindowIsNotFirst() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 在主窗口不是数组第一个元素时仍返回正确下标"
    let windows = [
        Descriptor(identifier: "com_apple_SwiftUI_settings_window", isVisible: true, isMiniaturized: false),
        Descriptor(identifier: "main-AppWindow-1", isVisible: true, isMiniaturized: false),
    ]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == 1 else {
        return fail(name, "expected index 1（主窗口在第二个位置）, got \(String(describing: result))")
    }
    return pass(name, "Settings 窗口排在前面时，正确跳过它、返回主窗口的真实下标 1")
}

// MARK: - 防御性边界

/// `identifier` 为 `nil`（理论上不该发生，但窗口系统的可选值不该被强解包）——不应该崩溃，也不应该
/// 被当成匹配。
func testFindMainWindowIndexTreatsNilIdentifierAsNonMatch() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 把 identifier == nil 的窗口当成不匹配（不崩溃、不误判）"
    let windows = [Descriptor(identifier: nil, isVisible: true, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == nil else {
        return fail(name, "expected nil, got \(String(describing: result))")
    }
    return pass(name, "identifier 为 nil 时安全返回 nil，未强解包崩溃")
}

/// identifier 前缀匹配、但既不可见也未最小化（比如刚被 `close()` 但对象还短暂留在数组里的边缘态）——
/// 不应该被选中去前置一个实际上已经不在的窗口。
func testFindMainWindowIndexIgnoresMatchingIdentifierThatIsNeitherVisibleNorMiniaturized() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 忽略 identifier 匹配但既不可见也未最小化的窗口"
    let windows = [Descriptor(identifier: "main-AppWindow-1", isVisible: false, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == nil else {
        return fail(name, "expected nil, got \(String(describing: result))")
    }
    return pass(name, "identifier 匹配但 isVisible=false 且 isMiniaturized=false 时正确返回 nil")
}

/// **防止用 `contains` 蒙混过关的反向用例**：identifier 里包含 `mainWindowID` 这个子串、但不是
/// 前缀（比如误把这里实现成 `contains` 而不是 `hasPrefix`，这条测试就会失败）——不应该匹配。
func testFindMainWindowIndexRejectsIdentifierThatContainsButDoesNotStartWithMainWindowID() -> Bool {
    let name = "菜单栏窗口选择: findMainWindowIndex 拒绝仅仅\"包含\"而非\"以…开头\"mainWindowID 的 identifier（防 contains 误实现）"
    let windows = [Descriptor(identifier: "settings-main-panel", isVisible: true, isMiniaturized: false)]
    let result = MenuBarWindowSelection.findMainWindowIndex(among: windows, mainWindowID: "main")
    guard result == nil else {
        return fail(name, "expected nil（\"settings-main-panel\" 只是包含 \"main\" 子串，不是以它开头）, got \(String(describing: result))")
    }
    return pass(name, "identifier 只包含 \"main\" 子串但不以它开头时正确返回 nil，证明用的是 hasPrefix 不是 contains")
}
