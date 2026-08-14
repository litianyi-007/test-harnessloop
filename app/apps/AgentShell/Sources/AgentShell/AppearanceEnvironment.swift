// rounds/0021 Change 2/3：外观偏好的运行时状态 + 语义色调色板——两者都必须落在 `AgentShell`
// （视图层 target），不是 `AgentShellCore`：
//   - `AppearanceSettingsStore` 要读 `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`
//     （AppKit API），`AgentShellCore` 刻意不 import AppKit/SwiftUI（LiquidGlassSupport.swift 头
//     注释记录的既定边界，四个模型文件与 rounds/0021 新增的 AppearanceSettings.swift 均不例外）。
//   - 语义色本身是 `Color`（SwiftUI 类型），同样过不了那条边界。
// 这两者共同的判断逻辑（"给定滑块值 + 无障碍状态，该不该透明"“deny 决策该映射到哪个语义角色”）已经
// 收在 AgentShellCore/AppearanceSettings.swift 的纯函数里——本文件只做“把值接进来、把角色换成具体
// Color”这两步纯粘合/纯展示工作，不重新判断一次。

import SwiftUI
import AppKit
import AgentShellCore

// MARK: - AppearanceSettingsStore：滑块偏好 + 实时无障碍状态 + 已解析的 chrome 样式

/// 外观偏好的唯一权威来源——全 app 所有 chrome 背景调用点都读同一个实例的 `resolvedStyle`，不各自
/// 重新读 `NSWorkspace`/UserDefaults，保证"同一次无障碍状态变化下，所有 chrome 表面同步更新"（任务
/// 书"coherent"要求的落点之一，另一半落点见 LiquidGlassSupport.swift `chromeMaterialBackground`
/// 头注释）。
///
/// **实时无障碍状态,不是启动时读一次**（任务书原文："a value read once at launch is a silent
/// failure"）——`NSWorkspace` 在 Increase Contrast/Reduce Transparency/Reduce Motion/
/// Differentiate Without Color 等任一开关变化时会广播
/// `accessibilityDisplayOptionsDidChangeNotification`（AppKit 文档原文：'Posted when... any of
/// the accessibility display options change'）。本类型在 `init` 里订阅这个通知，每次收到通知就
/// 重新读取 `NSWorkspace.shared` 的两个属性并写回 `@Observable` 存储属性——SwiftUI 视图凡是读过
/// `resolvedStyle`（或它依赖的 `sliderValue`/`reduceTransparency`/`increaseContrast`）都会在这一刻
/// 自动重新渲染，不需要视图自己订阅任何通知。这就是"live changes propagate"这句话在这个 app 里的
/// 完整实现：通知 -> 本类型的属性变化 -> `@Observable` 追踪 -> 依赖它的 View body 重新求值。
///
/// `@MainActor`——`NSWorkspace`/`UserDefaults`/SwiftUI 状态三者都要求主线程，与 `SessionStore`
/// 同样的既定写法（AgentShellCore/SessionStore.swift 类型声明处）。
@MainActor
@Observable
final class AppearanceSettingsStore {
    /// 用户滑块的当前值,`0...1`——已经从 UserDefaults 恢复(或套用默认值),Settings 面板与所有 chrome
    /// 背景调用点读的是同一份。外部只读,写入必须经 `updateSlider(_:)`(保证"改状态"与"落盘"两件事
    /// 原子地一起发生,不会出现"UI 已经变了但下次启动读到旧值"这种漂移)。
    private(set) var sliderValue: Double

    /// 以下两个属性只在 `init` 与 NSWorkspace 通知回调里被写——外部（Settings 面板）只读，用于展示
    /// "无障碍设置正在生效"提示文案（`accessibilityOverrideActive`）。
    private(set) var reduceTransparency: Bool
    private(set) var increaseContrast: Bool

    // `@ObservationIgnored` + `nonisolated(unsafe)`——两处都不是可省略的样板：
    //   - `deinit` 在 Swift 里永远是 nonisolated（即便宿主类标了 `@MainActor`），不能同步读取一个
    //     actor-isolated 存储属性；这个属性只是一个不透明的观察者 token，本身不参与任何需要隔离
    //     保护的可变状态（`init` 里写一次、`deinit` 里读一次用于注销，中间从不被并发读写）。
    //   - **实测坐实,踩了两次坑**：① 先试的朴素 `nonisolated`——编译器先给了个"has no effect...
    //     consider using 'nonisolated'"的警告建议，改过去之后才发现真正的错误在别处："'nonisolated'
    //     cannot be applied to mutable stored properties"，且报错来自 `@ObservationTracked`
    //     宏展开——`@Observable` 宏默认把类里*每一个*存储属性都包一层 `@ObservationTracked`
    //     （变成"计算属性 + 底层 `_foo` 存储"的展开形态），朴素 `nonisolated` 不能加在这种宏展开出
    //     的可变存储上。② 补加 `@ObservationIgnored` 让这个属性彻底跳过 `@Observable` 宏的包装
    //     （这个观察者 token 本来也不需要参与 SwiftUI 的变化追踪——没有任何视图会绑定它），
    //     它才变回一个真正的朴素存储属性，`nonisolated(unsafe)` 才生效（这次不再是"no effect"）。
    @ObservationIgnored
    nonisolated(unsafe) private var accessibilityObserver: NSObjectProtocol?
    private let userDefaults: UserDefaults

    /// - Parameter userDefaults：默认 `.standard`；测试/预览可传入隔离实例。这个类型本身不在
    ///   `frame-replay-tests` 里被直接构造（它 import AppKit，测试 target 只 `@testable import
    ///   AgentShellCore/KernelClient`，见本文件头注释的边界说明）——这个参数留着是为了未来如果
    ///   真的需要在 AgentShell 里做非默认 suite 的场景（比如 SwiftUI Preview）时不必再改签名，
    ///   不是当前就有测试在用它。
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.sliderValue = ChromeTransparencyDefaultsStore.load(userDefaults: userDefaults)
            ?? ChromeTransparencyDefaultsStore.defaultSliderValue
        self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        // rework（2026-08-14，T-114 codex 对抗评审阻断项①）：修前这里错订在 `NotificationCenter
        // .default` 上——`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 的官方
        // 文档原文（`NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification` 页面 Discussion
        // 小节）明确写着："To receive this notification, use `NSWorkspace.notificationCenter` to
        // register for it. If you use a different notification center to register, you won't
        // receive the notification."——即订在默认中心上不是"效果稍差"，是**结构性永远收不到**：
        // `init` 里读到的启动快照会成为这个类型此生唯一的一份数据,运行期切换 Reduce Transparency/
        // Increase Contrast 不会触发任何回调,`reduceTransparency`/`increaseContrast` 两个
        // `@Observable` 属性永远不变,依赖它们的 SwiftUI 视图自然也永远不会因为无障碍状态变化而
        // 重新渲染——这是一个新的静默失败路径,且恰好与本类型开头文档注释宣称的"实时无障碍状态,不是
        // 启动时读一次"这句话直接矛盾。
        //
        // 同一页文档 Discussion 小节还明确了 `object:` 该填什么："The notification object is the
        // shared `NSWorkspace` instance."——`object: NSWorkspace.shared` 这个过滤条件本身在修前就是
        // 对的（问题只出在订的中心,不出在 object 过滤),这里原样保留,不因为"顺手都改一遍"而引入新的
        // 不确定性。
        self.accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            // 通知本身已经指定 `queue: .main`，回调保证在主线程触发；`Task { @MainActor in }`
            // 是给 Swift 类型检查器看的显式隔离声明（这个闭包参数类型是普通 `@Sendable`，不是
            // 静态 `@MainActor`-isolated），不是为了真的跳一次线程。
            Task { @MainActor in
                guard let self else { return }
                self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
        }
    }

    deinit {
        // 必须从注册时的同一个中心注销——`NotificationCenter.default.removeObserver(...)` 对一个
        // 注册在 `NSWorkspace.shared.notificationCenter` 上的 token 是静默无效调用（不会崩溃、也不
        // 报错，只是没有实际取消订阅的效果），与上面订阅处犯的是同一类错误，这里同步改正。
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    /// 全 app chrome 背景调用点的唯一输入——纯函数调用,判断逻辑不在这里(见
    /// `ChromeTransparencyResolver.resolve` 文档注释)。
    var resolvedStyle: ChromeMaterialStyle {
        ChromeTransparencyResolver.resolve(
            sliderValue: sliderValue,
            accessibility: SystemAccessibilityDisplayState(
                reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
            )
        )
    }

    /// 无障碍开关此刻是否正在生效——Settings 面板据此显示提示文案,让用户知道"滑块设置没有丢,只是
    /// 被更高优先级的系统设置暂时压过"(而不是误以为保存失败)。
    var accessibilityOverrideActive: Bool { reduceTransparency || increaseContrast }

    /// 熊头水印是否应该渲染——纯粘合调用,判断逻辑在
    /// `WatermarkVisibilityResolver.resolve(accessibility:)`（AgentShellCore/AppearanceSettings.swift，
    /// 含"为什么只看 increaseContrast、不看 reduceTransparency"的文档注释),本属性只负责把已经在
    /// 追踪的两个 `@Observable` 布尔量包成该函数需要的 `SystemAccessibilityDisplayState` 入参——
    /// 与 `resolvedStyle` 同一种"View 只做最后一步纯展示转换"的写法。
    var showsDecorativeWatermark: Bool {
        WatermarkVisibilityResolver.resolve(
            accessibility: SystemAccessibilityDisplayState(
                reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
            )
        )
    }

    /// Settings 面板滑块拖动时调用——"改状态"与"落盘"在同一次调用里发生,不会出现两者不同步。
    func updateSlider(_ newValue: Double) {
        sliderValue = newValue
        ChromeTransparencyDefaultsStore.save(newValue, userDefaults: userDefaults)
    }
}

// MARK: - 语义色调色板——与 accentColor 独立定义

// **实测坐实的写法选择**：`extension Color { static let semanticDanger = ... }`（先前的写法）编译
// 通不过 `.foregroundStyle(.semanticDanger)`/`.tint(.semanticDanger)` 这类调用点——
// `foregroundStyle(_:)`/`tint(_:)` 的参数类型是 `some ShapeStyle`（一个 opaque 协议类型），Swift
// 的隐式成员语法（`.xxx`）在这种"参数类型是协议、不是具体类型"的位置只会在**该协议本身**（或对它的
// 约束扩展）上找静态成员，不会去每一个"恰好符合协议"的具体类型（如 `Color`）上找。SwiftUI 内建的
// `.red`/`.orange`/`.green` 之所以能在这些位置直接用，是因为 Apple 把它们定义在
// `extension ShapeStyle where Self == Color { static var red: Color { ... } }` 这样的**约束
// 协议扩展**里，不是 `extension Color`。这里照抄同一个模式——改了写法之后，`Color.semanticDanger`
// （具体类型上下文）与 `.foregroundStyle(.semanticDanger)`（协议参数位置）两种调用点都能解析。
extension ShapeStyle where Self == Color {
    /// 危险语义色——固定系统红,不从 `accentColor`/任何主题变量派生(任务书硬约束："Success /
    /// warning / danger are semantic and must not be absorbed by whatever accent the theme
    /// uses"）。用 `NSColor.systemRed`（而不是 SwiftUI 的 `Color.red` 字面量）：前者在浅色/深色
    /// 模式下都有 Apple 调过的具体数值，且明确属于 AppKit"系统语义色板"这一组（与
    /// `.systemGreen`/`.systemOrange` 同源），比通用的 `Color.red` 更贴合"这是一个语义状态色"的
    /// 意图，也让三个语义色在定义方式上彼此一致（全部走 `NSColor.system*`，不是两个用字面量、一个
    /// 用系统色这种不一致的写法）。
    static var semanticDanger: Color { Color(nsColor: .systemRed) }
    /// 成功语义色。
    static var semanticSuccess: Color { Color(nsColor: .systemGreen) }
    /// 警告语义色。
    static var semanticWarning: Color { Color(nsColor: .systemOrange) }
}

extension SemanticColorRole {
    /// `AgentShellCore` 判断出的角色 -> 具体 `Color` 的最后一步纯展示转换——本类型自己不做任何
    /// "这个场景该算哪个角色"的判断（那部分在 `ApprovalDecisionSemantics.colorRole(for:)`，是
    /// 纯函数、可测）。`.accent` 显式映射到 `Color.accentColor`（跟随主题）——三个语义 case 与这一
    /// 个 case 在这里被分别处理成两条完全不共享数值来源的代码路径，这正是"独立定义、保持独立"的
    /// 字面落点：修改 `.semanticDanger` 的定义永远不会意外改到 `.accentColor` 的值，反之亦然。
    var color: Color {
        switch self {
        case .danger: return .semanticDanger
        case .success: return .semanticSuccess
        case .warning: return .semanticWarning
        case .accent: return .accentColor
        }
    }
}
