// rounds/0021：可自定义透明度（红线：系统无障碍设置永远压过用户滑块）+ 语义色角色映射的入库回归
// 测试。隔离哲学与 KernelShellSettingsTests.swift 完全一致——每个持久化测试用独立的 UserDefaults
// suite 名字字符串（`defer` 用该字符串本身整体清除，不是拿 `UserDefaults` 实例的 `description`，
// 见该文件头注释记录的实测坑）。
//
// 覆盖面对应任务书"At minimum pin"的两条硬要求：
//   1. 透明度偏好（`ChromeTransparencyDefaultsStore`）往返正确。
//   2. `ChromeTransparencyResolver.resolve(...)`——无障碍开关必须压过滑块的任意取值，含两个极值
//      （0.0/1.0）——这是本轮红线的唯一判断落点（AgentShellCore/AppearanceSettings.swift），本文件
//      测试密度也最高地覆盖它。
// 额外覆盖：`ApprovalDecisionSemantics.colorRole(for:)`——"deny 必须映射到危险角色、不是强调色角色"
// 这条判断本身现在可测（此前是内联在 View 里的三元表达式，结构性不可测，见该函数文档注释）。

import Foundation
@testable import AgentShellCore
import D2Generated

// MARK: - 测试专用隔离小工具

private func freshAppearanceSuiteName(_ label: String) -> String {
    "agent-shell-appearance-tests-\(label)-\(UUID().uuidString)"
}

// MARK: - ChromeTransparencyDefaultsStore：往返 + 从未保存 vs. 保存了 0

func testChromeTransparencyDefaultsStoreRoundTripsAndClears() -> Bool {
    let name = "外观设置: ChromeTransparencyDefaultsStore save/load/clear 往返正确，且 load() 对从未写过的 suite 返回 nil"
    let suiteName = freshAppearanceSuiteName("roundtrip")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    guard ChromeTransparencyDefaultsStore.load(userDefaults: defaults) == nil else {
        return fail(name, "expected nil before any save()")
    }
    ChromeTransparencyDefaultsStore.save(0.42, userDefaults: defaults)
    guard ChromeTransparencyDefaultsStore.load(userDefaults: defaults) == 0.42 else {
        return fail(name, "expected round-tripped value 0.42 after save()")
    }
    ChromeTransparencyDefaultsStore.clear(userDefaults: defaults)
    guard ChromeTransparencyDefaultsStore.load(userDefaults: defaults) == nil else {
        return fail(name, "expected nil after clear()")
    }
    return pass(name, "save() 前 load()==nil -> save(0.42) 后 load() 取回原值 -> clear() 后 load() 再次为 nil")
}

/// **专门钉住的边界情形**：保存的值恰好是 `0.0`——`load()` 的实现如果偷懒直接用
/// `userDefaults.double(forKey:)` 的返回值判断"是否存在过"（`0.0` 是它对从未写过的 key 的默认
/// 返回值），会把"用户主动把滑块拖到 0 并保存"误判成"从未保存过"，静默丢弃一个合法保存值。
func testChromeTransparencyDefaultsStoreDistinguishesSavedZeroFromNeverSaved() -> Bool {
    let name = "外观设置: ChromeTransparencyDefaultsStore.load() 能区分「保存了 0.0」与「从未保存过」（不能用 double(forKey:) 的零值默认返回值当判据）"
    let suiteName = freshAppearanceSuiteName("saved-zero")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    ChromeTransparencyDefaultsStore.save(0.0, userDefaults: defaults)
    guard let loaded = ChromeTransparencyDefaultsStore.load(userDefaults: defaults) else {
        return fail(name, "expected non-nil (a real saved value of 0.0), got nil — 说明 load() 把「保存了 0」误判成了「从未保存」")
    }
    guard loaded == 0.0 else {
        return fail(name, "expected loaded value to be exactly 0.0, got \(loaded)")
    }
    return pass(name, "保存 0.0 后 load() 正确返回 Optional(0.0)（不是 nil），证明判据用的是 object(forKey:) != nil 而不是零值猜测")
}

// MARK: - defaultSliderValue：T-114 阻断项②附带发现的回归钉（此前是 0.6，命中错的档位）

/// **rework（2026-08-14，T-114 codex 对抗评审阻断项②附带发现）的直接回归钉**：默认滑块值必须落在
/// `materialForChromeIntensity`（LiquidGlassSupport.swift，结构性不可测，见该文件头注释）的
/// `.regularMaterial` 分档区间 `[0.4, 0.6)` 内——这里独立复算该区间的两个边界值（不是调用那个
/// private 函数，跨 executableTarget 做不到，见 KernelShellSettingsStorage.swift `defaultSliderValue`
/// 文档注释），只要 `defaultSliderValue` 落在这个区间内，就能推出它在 `materialForChromeIntensity`
/// 里一定命中 `.regularMaterial`。
///
/// **已知的覆盖缺口，如实记录**：这条测试没有、也不可能验证 `materialForChromeIntensity` 本身的
/// 五档划分真的是"`[0.4,0.6)` 对应 `.regularMaterial`"——那份事实只能来自读源码。如果未来有人同时
/// 悄悄改了 `materialForChromeIntensity` 的边界又没有同步改这里的边界常量，这条测试会给出一个虚假
/// 的安全感——这正是阻断项②当初能够潜伏的同一类风险（两处本该同步的事实分别活在不同文件里,没有
/// 任何机制强制它们一起变),这里如实点破,不是假装已经解决。
func testChromeTransparencyDefaultSliderValueLandsInsideRegularMaterialBucket() -> Bool {
    let name = "外观设置: ChromeTransparencyDefaultsStore.defaultSliderValue 落在 materialForChromeIntensity 的 .regularMaterial 半开区间 [0.4, 0.6) 内（T-114 阻断项②：此前的 0.6 不满足这一点）"
    let regularBucketLowerBoundInclusive = 0.4
    let regularBucketUpperBoundExclusive = 0.6
    let value = ChromeTransparencyDefaultsStore.defaultSliderValue
    guard value >= regularBucketLowerBoundInclusive else {
        return fail(name, "defaultSliderValue=\(value) 小于分档下界 \(regularBucketLowerBoundInclusive)，会落进更厚的档位（.thickMaterial 或更厚），不是 .regularMaterial")
    }
    guard value < regularBucketUpperBoundExclusive else {
        return fail(name, "defaultSliderValue=\(value) 不小于分档上界 \(regularBucketUpperBoundExclusive)（半开区间不含上界本身），会落进更薄的档位（.thinMaterial 或更薄）——这正是 T-114 阻断项②附带发现的那个 bug：旧值 0.6 精确落在这个失败条件上")
    }
    return pass(name, "defaultSliderValue=\(value) ∈ [0.4, 0.6)，稳稳落在 .regularMaterial 分档内")
}

/// 简单值回归钉——防止未来有人不经意把这个常量改成任何值（哪怕仍然落在 `[0.4,0.6)` 区间内，比如改成
/// 0.45）却没有意识到这是一个需要重新论证"为什么选这个数"的决定。与上一条互补，不是重复：上一条测
/// 属性（落在正确区间），这一条测精确值（没有人意外改动这个具体数字）。
func testChromeTransparencyDefaultSliderValueIsExactlyPointFive() -> Bool {
    let name = "外观设置: ChromeTransparencyDefaultsStore.defaultSliderValue 精确等于 0.5"
    let value = ChromeTransparencyDefaultsStore.defaultSliderValue
    guard value == 0.5 else {
        return fail(name, "expected 0.5, got \(value)")
    }
    return pass(name, "defaultSliderValue == 0.5")
}

// MARK: - ChromeTransparencyResolver：红线——无障碍开关压过滑块的任意取值（含两个极值）

/// **本轮红线的直接证据 ①**：Reduce Transparency 开启时，滑块处在能想到的任何位置（含两个极值
/// 0.0/1.0）都必须解析成 `.opaque`。
func testResolverReduceTransparencyForcesOpaqueAtEverySliderValueIncludingExtremes() -> Bool {
    let name = "外观设置 红线①: ChromeTransparencyResolver.resolve() 在 reduceTransparency=true 时，滑块任意取值（含 0.0/1.0 两个极值）均解析为 .opaque"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: true, increaseContrast: false)
    let sliderValuesToTry: [Double] = [0.0, 0.001, 0.25, 0.5, 0.75, 0.999, 1.0]
    for sliderValue in sliderValuesToTry {
        let style = ChromeTransparencyResolver.resolve(sliderValue: sliderValue, accessibility: accessibility)
        guard style == .opaque else {
            return fail(name, "sliderValue=\(sliderValue) 本该被无障碍设置压过、解析为 .opaque，实际得到 \(style) —— 无障碍设置没有真正压过用户滑块")
        }
    }
    return pass(name, "sliderValue ∈ \(sliderValuesToTry)（含两个极值 0.0/1.0）在 reduceTransparency=true 下全部解析为 .opaque")
}

/// **本轮红线的直接证据 ②**：Increase Contrast 单独开启（reduceTransparency 仍为 false）时同样必须
/// 压过滑块——任务书原文："Same for Increase Contrast"，不是只有 Reduce Transparency 才生效。
func testResolverIncreaseContrastAloneForcesOpaqueAtEverySliderValueIncludingExtremes() -> Bool {
    let name = "外观设置 红线②: ChromeTransparencyResolver.resolve() 在 increaseContrast=true（reduceTransparency=false）时，滑块任意取值（含 0.0/1.0 两个极值）均解析为 .opaque"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: false, increaseContrast: true)
    let sliderValuesToTry: [Double] = [0.0, 0.001, 0.5, 0.999, 1.0]
    for sliderValue in sliderValuesToTry {
        let style = ChromeTransparencyResolver.resolve(sliderValue: sliderValue, accessibility: accessibility)
        guard style == .opaque else {
            return fail(name, "sliderValue=\(sliderValue) 本该被 increaseContrast 压过、解析为 .opaque，实际得到 \(style)")
        }
    }
    return pass(name, "sliderValue ∈ \(sliderValuesToTry)（含两个极值）在 increaseContrast=true 下全部解析为 .opaque，即便 reduceTransparency 本身是 false")
}

/// 两个无障碍开关同时开启——不是互斥关系，必须同样压过滑块（而不是要求"恰好只开一个"才生效）。
func testResolverBothAccessibilityFlagsOnForcesOpaqueAtSliderExtremes() -> Bool {
    let name = "外观设置 红线③: reduceTransparency 与 increaseContrast 同时为 true 时，滑块两个极值均解析为 .opaque"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: true, increaseContrast: true)
    for sliderValue in [0.0, 1.0] {
        let style = ChromeTransparencyResolver.resolve(sliderValue: sliderValue, accessibility: accessibility)
        guard style == .opaque else {
            return fail(name, "sliderValue=\(sliderValue) 本该解析为 .opaque，实际得到 \(style)")
        }
    }
    return pass(name, "两个无障碍开关同时开启时，滑块两个极值（0.0/1.0）均正确解析为 .opaque")
}

/// **反面验证**：两个无障碍开关都关闭、且滑块 > 0 时，必须真的允许透明——证明上面三条红线测试不是
/// 因为 `resolve()` 无论如何都返回 `.opaque`（一个把所有输入都硬编码成 `.opaque` 的实现会让红线
/// 测试全部"通过"，但那是假阳性）。intensity 必须原样等于传入的滑块值（未被无障碍逻辑意外改写）。
func testResolverAllowsTranslucentWithMatchingIntensityWhenAccessibilityAllowsAndSliderPositive() -> Bool {
    let name = "外观设置: ChromeTransparencyResolver.resolve() 在两个无障碍开关都为 false 且滑块 > 0 时，正确解析为 .translucent(intensity: 滑块值本身)"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: false, increaseContrast: false)
    for sliderValue in [0.01, 0.3, 0.5, 0.7, 1.0] {
        let style = ChromeTransparencyResolver.resolve(sliderValue: sliderValue, accessibility: accessibility)
        guard case .translucent(let intensity) = style else {
            return fail(name, "sliderValue=\(sliderValue) 本该解析为 .translucent，实际得到 \(style) —— 如果这条测试也红,说明 resolve() 把所有输入都硬编码成了 .opaque,上面三条红线测试就是假阳性")
        }
        guard intensity == sliderValue else {
            return fail(name, "expected intensity == sliderValue (\(sliderValue))，实际 intensity=\(intensity)")
        }
    }
    return pass(name, "两个无障碍开关都关闭时，滑块值 ∈ [0.01, 0.3, 0.5, 0.7, 1.0] 均正确解析为 .translucent(intensity: 原值)，证明红线测试不是靠恒返回 .opaque 蒙混过关")
}

/// 滑块本身被用户拖到 0——即便两个无障碍开关都是 false，这也是"用户自己选择不透明"，同样解析为
/// `.opaque`（与无障碍覆盖是不同的成因，但视图层不需要区分，见 `ChromeMaterialStyle.opaque` 文档
/// 注释）。
func testResolverSliderValueZeroIsOpaqueEvenWithoutAnyAccessibilityOverride() -> Bool {
    let name = "外观设置: ChromeTransparencyResolver.resolve() 在滑块=0.0 且两个无障碍开关都为 false 时，仍解析为 .opaque（用户自己选择不透明）"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: false, increaseContrast: false)
    let style = ChromeTransparencyResolver.resolve(sliderValue: 0.0, accessibility: accessibility)
    guard style == .opaque else {
        return fail(name, "expected .opaque, got \(style)")
    }
    return pass(name, "sliderValue=0.0、无无障碍覆盖时，resolve() 正确解析为 .opaque")
}

/// 防御性夹紧：越界滑块值（负数/大于 1）不应该产出越界的 `intensity`，也不应该在负值上意外绕过
/// opaque 判断。
func testResolverClampsOutOfRangeSliderValues() -> Bool {
    let name = "外观设置: ChromeTransparencyResolver.resolve() 把越界滑块值夹到 [0,1] 再判断（负数落到 .opaque，大于 1 的值夹到 intensity=1.0）"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: false, increaseContrast: false)

    let negativeStyle = ChromeTransparencyResolver.resolve(sliderValue: -0.5, accessibility: accessibility)
    guard negativeStyle == .opaque else {
        return fail(name, "sliderValue=-0.5 应该被夹到 0 后判定为 .opaque，实际得到 \(negativeStyle)")
    }

    let overOneStyle = ChromeTransparencyResolver.resolve(sliderValue: 1.7, accessibility: accessibility)
    guard case .translucent(let intensity) = overOneStyle, intensity == 1.0 else {
        return fail(name, "sliderValue=1.7 应该被夹到 intensity=1.0 的 .translucent，实际得到 \(overOneStyle)")
    }
    return pass(name, "sliderValue=-0.5 -> .opaque（夹到 0）；sliderValue=1.7 -> .translucent(intensity: 1.0)（夹到上限）")
}

// MARK: - ApprovalDecisionSemantics：deny -> danger（不是 accent），其余 -> accent

/// **任务书硬要求的直接证据**："the approval card's deny action must read as danger under every
/// configuration"——这条判断此前内联在 SessionDetailView 的三元表达式里，结构性不可测（见
/// `ApprovalDecisionSemantics.colorRole(for:)` 文档注释）；挪到 AgentShellCore 之后在这里钉住。
func testApprovalDecisionSemanticsMapsDenyToDangerRoleNotAccent() -> Bool {
    let name = "外观设置: ApprovalDecisionSemantics.colorRole(for: .deny) == .danger（不是 .accent）——审批卡「拒绝」必须读成危险色，不能被主题强调色吃掉"
    let role = ApprovalDecisionSemantics.colorRole(for: .deny)
    guard role == .danger else {
        return fail(name, "expected .danger for .deny, got \(role)")
    }
    guard role != .accent else {
        return fail(name, "危险角色不能等于强调角色——两者必须是互斥的枚举值")
    }
    return pass(name, "colorRole(for: .deny) == .danger，且与 .accent 明确不相等")
}

/// 其余三种决策（allow_once/allow_always/allow_session）都应该跟随主题强调色，不应该被误判成
/// danger/success/warning 中的任何一个——防止"只要不是 deny 就该是危险色"或"所有决策都判 danger"
/// 这类过度收紧/过度放宽的错误实现蒙混过关。
func testApprovalDecisionSemanticsMapsAllowVariantsToAccentRole() -> Bool {
    let name = "外观设置: ApprovalDecisionSemantics.colorRole(for:) 对 allow_once/allow_always/allow_session 均返回 .accent（不是 .danger，也不是 success/warning）"
    let allowDecisions: [ApprovalDecisionKindElement] = [.allowOnce, .allowAlways, .allowSession]
    for decision in allowDecisions {
        let role = ApprovalDecisionSemantics.colorRole(for: decision)
        guard role == .accent else {
            return fail(name, "decision=\(decision.rawValue) 期望 .accent，实际得到 \(role)")
        }
    }
    return pass(name, "allow_once/allow_always/allow_session 三种决策的 colorRole 均为 .accent")
}

// MARK: - WatermarkVisibilityResolver：视觉/交互打磨任务——会话列表熊头水印的无障碍抑制判断
//
// 覆盖面对应 `WatermarkVisibilityResolver.resolve(accessibility:)` 文档注释里立的两条断言：
//   ① Increase Contrast 开启时（不论 Reduce Transparency 是什么取值）水印必须隐藏。
//   ② 这个判断刻意与 `ChromeTransparencyResolver` 不对称——单独开 Reduce Transparency（Increase
//      Contrast 保持关闭）不应该压制水印,证明①不是"只要任一无障碍开关开启就隐藏"这种更粗放、
//      与 `ChromeTransparencyResolver` 撞车但文档注释明确说没有采用的实现。
//   ③ 反面验证：两个开关都关闭时水印必须显示——防止"恒返回 false"这种蒙混过关的实现让①②假阳性。

/// **直接证据**：Increase Contrast 开启时,不论 Reduce Transparency 是 true 还是 false,水印都必须
/// 隐藏——这是文档注释里"红线只看 increaseContrast"的正面断言。
func testWatermarkVisibilityResolverHidesWatermarkWheneverIncreaseContrastIsOn() -> Bool {
    let name = "外观设置 水印: WatermarkVisibilityResolver.resolve() 在 increaseContrast=true 时返回 false（隐藏），不论 reduceTransparency 取值"
    for reduceTransparency in [false, true] {
        let accessibility = SystemAccessibilityDisplayState(
            reduceTransparency: reduceTransparency, increaseContrast: true)
        let visible = WatermarkVisibilityResolver.resolve(accessibility: accessibility)
        guard visible == false else {
            return fail(
                name,
                "reduceTransparency=\(reduceTransparency)、increaseContrast=true 时应返回 false，实际得到 \(visible)")
        }
    }
    return pass(name, "increaseContrast=true 时，reduceTransparency 取 false/true 均正确返回 false（隐藏水印）")
}

/// **不对称性的直接证据**：单独开启 Reduce Transparency（Increase Contrast 保持关闭）不应该隐藏
/// 水印——证明这个判断与 `ChromeTransparencyResolver`（两个开关任一即压过）刻意不同,不是漏写了
/// 第二个条件。
func testWatermarkVisibilityResolverIgnoresReduceTransparencyAlone() -> Bool {
    let name = "外观设置 水印: WatermarkVisibilityResolver.resolve() 在 reduceTransparency=true 但 increaseContrast=false 时仍返回 true（不隐藏）——与 ChromeTransparencyResolver 刻意不对称"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: true, increaseContrast: false)
    let visible = WatermarkVisibilityResolver.resolve(accessibility: accessibility)
    guard visible == true else {
        return fail(
            name,
            "reduceTransparency=true、increaseContrast=false 时期望 true（水印不该被 Reduce Transparency 单独压制），实际得到 \(visible)")
    }
    return pass(name, "单独开启 reduceTransparency 时 resolve() 仍返回 true，证明判断只看 increaseContrast")
}

/// **反面验证**：两个无障碍开关都关闭时水印必须显示——防止上面两条测试是靠一个恒返回 `false` 的
/// 实现蒙混过关（那样①会通过，②会失败；只有这条也通过才说明实现是真的在读 `increaseContrast`
/// 而不是忽略输入）。
func testWatermarkVisibilityResolverShowsWatermarkWhenNoAccessibilityOverrideIsActive() -> Bool {
    let name = "外观设置 水印: WatermarkVisibilityResolver.resolve() 在两个无障碍开关都为 false 时返回 true（显示），证明不是靠恒返回 false 蒙混过关"
    let accessibility = SystemAccessibilityDisplayState(reduceTransparency: false, increaseContrast: false)
    let visible = WatermarkVisibilityResolver.resolve(accessibility: accessibility)
    guard visible == true else {
        return fail(name, "两个开关都关闭时期望 true，实际得到 \(visible)")
    }
    return pass(name, "两个无障碍开关都关闭时，resolve() 正确返回 true（显示水印）")
}

// MARK: - ComposerGlassLayerOpacity：T-114 codex 对抗评审阻断项②——macOS 26 composer 玻璃背景层的
// 强度 -> 不透明度映射。这是阻断项②修复里唯一被挪进 AgentShellCore、因而可测的部分（`glassEffect`
// 本身的调用点仍在 LiquidGlassSupport.swift，结构性不可测，见该文件文档注释与本轮交付报告）。

/// **T-114 阻断项②的直接证据**：composer 玻璃背景层的不透明度必须随 intensity 变化，不能像修前那样
/// 对任意输入都渲染同一份固定玻璃（阻断项②原文："macOS 26 的输入区玻璃分支丢弃了滑块强度"）。这里
/// 取三个不同的 intensity 并断言两两不相等——一个忽略参数、恒返回常量的实现会让这条测试失败。
func testComposerGlassLayerOpacityVariesWithIntensity() -> Bool {
    let name = "外观设置 composer 玻璃: ComposerGlassLayerOpacity.resolve(intensity:) 对不同 intensity 返回不同的不透明度（不是修前那种恒定值）"
    let low = ComposerGlassLayerOpacity.resolve(intensity: 0.1)
    let mid = ComposerGlassLayerOpacity.resolve(intensity: 0.5)
    let high = ComposerGlassLayerOpacity.resolve(intensity: 1.0)
    guard low != mid, mid != high, low != high else {
        return fail(name, "intensity=0.1/0.5/1.0 应该产出三个互不相同的不透明度，实际得到 \(low)/\(mid)/\(high) —— 如果这条测试失败，说明 resolve() 退化成了忽略参数、恒返回常量的实现，与 T-114 阻断项②修前的 bug 是同一类失败")
    }
    return pass(name, "intensity=0.1 -> \(low)，0.5 -> \(mid)，1.0 -> \(high)，三者互不相同，证明不透明度确实随 intensity 变化")
}

/// 方向性证据：intensity 越大（用户越想要透明），不透明度必须越低——这是"更透明"这个产品意图在数值
/// 上唯一站得住的落点；反过来（intensity 越大不透明度越高）会是一个方向搞反的实现，真机上会看成
/// "滑块拖到最透明一侧，composer 反而更像一块实心玻璃"这种和用户意图相反的效果。
func testComposerGlassLayerOpacityDecreasesAsIntensityIncreases() -> Bool {
    let name = "外观设置 composer 玻璃: ComposerGlassLayerOpacity.resolve(intensity:) 随 intensity 增大单调递减（intensity 越大越透明，玻璃层不透明度应越低）"
    let samples: [Double] = [0.01, 0.2, 0.4, 0.6, 0.8, 1.0]
    var previous: Double?
    for intensity in samples {
        let opacity = ComposerGlassLayerOpacity.resolve(intensity: intensity)
        if let previous {
            guard opacity < previous else {
                return fail(name, "intensity=\(intensity) 的不透明度 \(opacity) 应该严格小于上一个采样点的 \(previous)，方向搞反了")
            }
        }
        previous = opacity
    }
    return pass(name, "intensity ∈ \(samples) 时，resolve() 的返回值严格单调递减")
}

/// 边界证据：intensity 趋近/到达两个极值时，不透明度必须落在 `[minOpacity, maxOpacity]` 内——既不能
/// 因为公式写反而跌出下限（对应"消失"，见 `ComposerGlassLayerOpacity` 文档注释里对下限存在理由的
/// 论证），也不能超出上限（SwiftUI 会把 `.opacity(...)` 的入参悄悄夹到 `[0,1]`，掩盖一个本该在源头
/// 就写对的公式错误）。用 epsilon 容差比较，不用 `==`——避免把浮点舍入误差误判成逻辑错误。
func testComposerGlassLayerOpacityStaysWithinDeclaredBoundsAtExtremes() -> Bool {
    let name = "外观设置 composer 玻璃: ComposerGlassLayerOpacity.resolve(intensity:) 在 intensity 两个极值附近，返回值落在 [minOpacity, maxOpacity] 内"
    let epsilon = 0.0000001

    let nearZero = ComposerGlassLayerOpacity.resolve(intensity: 0.0001)
    guard nearZero <= ComposerGlassLayerOpacity.maxOpacity,
          nearZero > ComposerGlassLayerOpacity.maxOpacity - 0.01 else {
        return fail(name, "intensity≈0 时期望不透明度非常接近 maxOpacity=\(ComposerGlassLayerOpacity.maxOpacity)，实际得到 \(nearZero)")
    }

    let atOne = ComposerGlassLayerOpacity.resolve(intensity: 1.0)
    guard abs(atOne - ComposerGlassLayerOpacity.minOpacity) < epsilon else {
        return fail(name, "intensity=1.0 期望约等于 minOpacity=\(ComposerGlassLayerOpacity.minOpacity)，实际得到 \(atOne)")
    }

    return pass(name, "intensity≈0 -> \(nearZero)（贴近 maxOpacity），intensity=1.0 -> \(atOne)（约等于 minOpacity），两端都在声明的范围内")
}
