// rounds/0021 Change 2/3：可自定义透明度的解析逻辑 + 语义色角色映射——都是纯函数/纯数据,刻意放在
// `AgentShellCore`（不放在 `AgentShell` 视图层）。
//
// **为什么必须是纯函数,不能就手写在 View 里**：`frame-replay-tests` 依赖 `AgentShellCore`,不依赖
// `AgentShell`（app/Package.swift `frame-replay-tests` target 的 `dependencies` 只列了
// `KernelClient`/`D2Generated`/`AgentShellCore`）——`AgentShell` 与 `frame-replay-tests` 都是
// `executableTarget`,SwiftPM 不允许两个 executable target 互相 import（可执行产物不能被当库使用,
// 见 app/Package.swift `AgentShellCore` target 定义处的注释,这是这个代码库里已经写死的结构限制,
// rounds/0013 B2 就是为了解决同一个问题才把模型层拆出来）。也就是说:如果"系统无障碍设置必须压过
// 用户滑块"这条本轮红线的判断逻辑直接写在某个 SwiftUI View 文件里,它就结构性地不可能被
// frame-replay-tests 单测覆盖——只能靠人眼在真机上切换系统设置肉眼确认,而"肉眼确认"恰恰是本轮任务书
// 明确要防的那类不可回归的验证方式。这里的取舍是:把"给定三个输入,该不该显示透明"这个判断收成一个不
// import SwiftUI/AppKit 的纯函数,视图层只负责"把判断结果换成具体的 Material/Color"这最后一步纯展示
// 转换（该转换逻辑见 AgentShell/LiquidGlassSupport.swift、AgentShell/AppearanceEnvironment.swift,
// 这两个文件本身确实不可测,但它们不再包含任何值得测的判断分支——判断已经在这里被跑过一遍了）。

import Foundation
import D2Generated

// MARK: - 系统无障碍显示状态

/// macOS 系统级无障碍显示状态的一个只读快照——`reduceTransparency` 对应
/// `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`,`increaseContrast` 对应
/// `...ShouldIncreaseContrast`。这个类型本身只是两个布尔量的具名容器,不持有任何 AppKit
/// 引用——真正读取 `NSWorkspace` 的代码在 `AgentShell` 视图层（`AppearanceEnvironment.swift`）,
/// 那里读到值之后构造这个类型的实例传进来,本类型不知道、也不需要知道值是怎么来的。
public struct SystemAccessibilityDisplayState: Equatable, Sendable {
    public var reduceTransparency: Bool
    public var increaseContrast: Bool

    public init(reduceTransparency: Bool, increaseContrast: Bool) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

// MARK: - chrome 层材质的解析结果

/// chrome 背景该渲染成什么——`AgentShell` 视图层（`LiquidGlassSupport.swift` 的
/// `chromeMaterialBackground`/`composerChromeBackground`）只消费这个结果做展示,不再重新判断一次
/// "现在到底该不该透明"。
public enum ChromeMaterialStyle: Equatable, Sendable {
    /// 不透明——要么是无障碍设置压过了用户滑块,要么是用户自己把滑块拉到了最不透明的一端。两种
    /// 成因视图层不需要区分,统一渲染成真正不透明的系统窗口背景色（不是"看起来最不透明的材质",
    /// 见 `chromeShapeStyle` 的实现选择）。
    case opaque
    /// 允许透明,`intensity` ∈ (0, 1] 是已经夹到合法范围的用户滑块值——能走到这个 case 就已经确定
    /// 无障碍开关允许透明,视图层可以放心地把 `intensity` 映射成材质浓淡,不需要再检查一次。
    case translucent(intensity: Double)
}

/// **本轮红线的唯一判断落点**——`ChromeTransparencyResolver.resolve(...)`。不 import SwiftUI/
/// AppKit,任何输入组合的输出都是确定性的,可以在 frame-replay-tests 里直接断言。
public enum ChromeTransparencyResolver {
    /// - Parameters:
    ///   - sliderValue：Settings 面板滑块的当前值,预期落在 `0...1`,但这里不假设调用方已经做过
    ///     校验——越界值会被夹到 `0...1`（防御性:滑块 UI 正常不会产出越界值,但持久化里存了一个
    ///     旧格式/被外部工具改过的 UserDefaults 值这种情况并非不可能,不能让一个越界的 Double 顺着
    ///     精度链一路传到渲染层产出未定义行为）。
    ///   - accessibility：系统无障碍显示状态的快照。
    ///
    /// **优先级判断只有一行,但这一行就是任务书原文"the system always wins"的完整代码化**：
    /// `reduceTransparency` 或 `increaseContrast` 任一为 true——不要求两者同时为 true——就直接返回
    /// `.opaque`,不看 `sliderValue` 究竟是多少,即便它是 `1.0`（"我要最大透明度"这个最极端的用户
    /// 意愿表达）也一样。这是"无论滑块在哪"这句话在代码里唯一可能被违反的地方,也是本文件测试覆盖
    /// 密度最高的一行。
    public static func resolve(
        sliderValue: Double,
        accessibility: SystemAccessibilityDisplayState
    ) -> ChromeMaterialStyle {
        guard !accessibility.reduceTransparency, !accessibility.increaseContrast else {
            return .opaque
        }
        let clamped = min(max(sliderValue, 0), 1)
        // 滑块本身被用户拉到 0（"我自己选择不透明"）——与无障碍覆盖是两种不同的成因,但视图层不需要
        // 区分,统一走同一个 .opaque case（见该 case 的文档注释）。
        guard clamped > 0 else { return .opaque }
        return .translucent(intensity: clamped)
    }
}

// MARK: - composer 玻璃背景层的强度 -> 不透明度映射（macOS 26 专用，rework 新增）

/// rework（2026-08-14，T-114 codex 对抗评审阻断项②）：composer 在 macOS 26 上用真正的
/// `SwiftUICore.Glass`/`glassEffect` 渲染 chrome 背景，不是 `Material`——直接读了本机安装的
/// macOS 26.5 SDK 里 `SwiftUICore.swiftinterface` 的 `Glass` 类型真实声明（`grep -n "struct Glass"`
/// 定位，交付报告 verification 记录了完整命中文本）：公开 API 只有 `.regular`/`.clear`/`.identity`
/// 三个静态成员与 `.tint(_:)`/`.interactive(_:)` 两个修饰方法，**没有连续的强度/不透明度参数**——
/// 不能像 `LiquidGlassSupport.swift` 的 `materialForChromeIntensity` 那样直接把 `intensity` 换成
/// 一个系统预定义级别。视图层（`LiquidGlassSupport.swift` `composerChromeBackground`）改用"把玻璃
/// 渲染成独立背景层、只调这一层的不透明度"这个技巧；而"该不透明度具体是多少"这个可能出错的数值边界
/// 判断收在这里，不写在视图文件里——与 `ChromeTransparencyResolver`/`ApprovalDecisionSemantics`
/// 同一条理由（本文件头注释）：`AgentShell` 是 executableTarget，`frame-replay-tests` 没有任何路径
/// 能 import 它，写在视图文件里的任何数值边界就只能靠人眼在真机上拖滑块肉眼确认——这正是本轮阻断项
/// ②本身发生的方式（该数值边界此前根本没有被写出来，也就没有任何东西能钉住它）。
public enum ComposerGlassLayerOpacity {
    /// 不透明度下限——`intensity` 趋近 1（用户想要的透明度最大）时,玻璃层也不应该淡到肉眼无法分辨
    /// "这里有一层玻璃 chrome"和"这里什么都没有"的地步,那是"消失",不是"更透明的玻璃"。没有做成
    /// 可配置项——本轮任务书没有要求这一层再套一个用户可调参数，属于过度设计。
    public static let minOpacity: Double = 0.35
    /// 不透明度上限——`intensity` 趋近 0（但严格 `>0`，见 `resolve(intensity:)` 参数文档）时，玻璃层
    /// 应该最贴近"regular 玻璃"本来的样子，即完全不透明（`1.0`）。
    public static let maxOpacity: Double = 1.0

    /// - Parameter intensity：预期是 `ChromeTransparencyResolver.resolve(...)` 已经产出的
    ///   `.translucent(intensity:)` 关联值，落在 `(0, 1]`——本函数不重新校验/夹紧这个前提（调用方
    ///   只在已经匹配到 `.translucent` case 之后才会调用这里，越界输入不是这个函数需要防御的场景，
    ///   防御性夹紧已经在 `ChromeTransparencyResolver.resolve` 做过一次，不在这里重复）。
    /// - Returns: `intensity` 越大（用户越想要透明），返回值越小（玻璃层不透明度越低，composer
    ///   背后的内容透得越多）；`intensity` 越接近 0，返回值越接近 `maxOpacity`。线性插值，不是像
    ///   `materialForChromeIntensity` 那样离散分档——`Material` 有五个 Apple 定义好的具体级别可以
    ///   离散映射，`Glass` 唯一可调的维度只有这一层背景本身的不透明度，是一个连续量，没有理由为了
    ///   "看起来和 Material 那边一样分五档"而人为切成五段离散台阶。
    public static func resolve(intensity: Double) -> Double {
        maxOpacity - (maxOpacity - minOpacity) * intensity
    }
}

// MARK: - 装饰性水印（会话列表熊头水印）的无障碍抑制判断

/// 会话列表面板背景的熊头水印是否应该渲染——视觉打磨任务（继 rounds/0021 液态玻璃/透明度之后）新增。
/// 与 `ChromeTransparencyResolver` 同一个理由放在这里：视图层（`AgentShell/BearWatermark.swift`
/// 的 `BearHeadWatermark` 与 `AgentShell/SessionListView.swift` 的调用点）都不 import SwiftUI 之外
/// 的任何逻辑判断——"给定当前无障碍状态，该不该画这个水印"收成一个纯函数，才能被 frame-replay-tests
/// 覆盖（结构性限制见本文件头注释）。
///
/// **只看 `increaseContrast`，不看 `reduceTransparency`**——这是一个刻意的、和 `ChromeTransparencyResolver`
/// 不对称的选择,不是遗漏：
///   - 水印本身是内容层的一块纯色低透明度填充（`BearHeadWatermark` 从不调用 `glassEffect`/`Material`——
///     本轮红线"glass belongs to chrome, never the content layer"的直接落点，见 scope-lock
///     rounds/0021 两条修订）,不是一层会被 Reduce Transparency 定义为目标的"透光材质"。Reduce
///     Transparency 在 HIG 里明确针对的是"透过它能看见背后内容"的材质/虚化效果,水印结构上从来
///     不是这类效果,谈不上"该不该降级"。
///   - Increase Contrast 则精确命中这个场景：它的目的就是让前景内容不被弱对比度的装饰性元素干扰
///     ——低对比度装饰性水印正是这个开关点名要处理的对象类别。
/// 若未来出现"水印也该在 Reduce Transparency 下隐藏"的具体产品决定,应该在这里显式加第二个条件、
/// 并补一条新测试钉住,而不是在视图层悄悄叠加判断（那样会重新制造本文件头注释警告过的"结构性不可测"
/// 问题）。
public enum WatermarkVisibilityResolver {
    /// - Returns: `true` 表示水印应该渲染,`false` 表示应该完全隐藏（不是"渲染但透明度为 0"——
    ///   调用点用 `if appearance.showsDecorativeWatermark` 直接跳过绘制,见
    ///   `SessionListView.body` 里 `List` 的 `.background { ... }` 闭包）。
    public static func resolve(accessibility: SystemAccessibilityDisplayState) -> Bool {
        !accessibility.increaseContrast
    }
}

// MARK: - 语义色角色

/// 语义色的角色分类——只由"这是什么状态"决定,不由"主题强调色现在是什么颜色"决定。任务书原文：
/// "Success / warning / danger are semantic and must not be absorbed by whatever accent the
/// theme uses."`.accent` 这个 case 存在的意义恰恰是划清界限：凡是"就该跟着主题走"的场景（比如
/// 审批卡片里非拒绝类的决策按钮）显式落在这一个独立的 case 上,和 danger/success/warning 三个语义
/// case 在类型层面就是互斥的枚举值,不存在"这个按钮到底该算语义色还是强调色"的中间地带。
public enum SemanticColorRole: Equatable, Sendable {
    case danger
    case success
    case warning
    case accent
}

/// 审批决策 -> 语义色角色的唯一收口点。
///
/// **修前**（rounds/0017 起)这条映射一直是内联在 `SessionDetailView.swift` 视图代码里的一个三元
/// 表达式（`decision == .deny ? .red : .accentColor`）——效果是对的,但纯判断逻辑埋在 View 文件里
/// 意味着"deny 必须映射到危险色、且不能被主题强调色吃掉"这件事本身**不可能被自动化测试覆盖**（结构性
/// 限制见本文件头注释）,只能等真人切到某个特殊主题时肉眼发现问题。
///
/// 本轮把判断本身挪到这里：`SessionDetailView` 现在只做"把 role 换成具体 Color"这一步纯展示转换
/// （`SemanticColorRole.color`,定义在 `AppearanceEnvironment.swift`,因为它要用到 `Color`/`NSColor`,
/// 这两个类型本文件不能 import）,不再自己判断"这个决策算不算危险"。
public enum ApprovalDecisionSemantics {
    public static func colorRole(for decision: ApprovalDecisionKindElement) -> SemanticColorRole {
        decision == .deny ? .danger : .accent
    }
}
