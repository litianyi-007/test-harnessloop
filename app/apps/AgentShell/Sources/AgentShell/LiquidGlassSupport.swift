// rounds/0017 Change 2 —— macOS 26 "Liquid Glass" 视觉语言适配的共享小工具。
//
// 背景与硬约束（任务书原文，逐条对应到这个文件里的选择）：
//   - app/Package.swift 的 `platforms` 仍是 `.macOS(.v14)`、Info.plist 仍是
//     `LSMinimumSystemVersion 14.0`（两者本轮都不能动）——所有 Liquid Glass API 只在 macOS 26+
//     可用，这里每一个能力都用 `if #available(macOS 26, *)` 门控，pre-26 分支落到标准
//     Material/按钮样式，不是"降级成丑"，是"落到系统一直支持、本来就在用的标准外观"。
//   - HIG 分层规则（任务书表格）：sidebar/toolbar/悬浮控件用 Liquid Glass；消息流内容层永远不用
//     glassEffect；审批卡片等内容卡片用标准 material，颜色只出现在按钮背景上。这个文件只提供
//     "按钮/卡片/滚动边缘"三类通用能力，"这个视图该不该用哪一种"的判断留在各自调用点
//     （SessionDetailView/ContentView/SessionListView）。
//   - 不做自定义噪点/颗粒纹理——研究结论（任务书原文）：没有官方 API/HIG 概念支持它，是社区土法
//     （Flutter 等界面库常见的做法），与 Reduce Transparency 冲突，拖性能拖可读性。这个文件不
//     提供、也不会提供这类效果——真需要"这块区域很重要"的强调，用材质层级/色彩/图标，不用纹理。
//
// 全部落在 `AgentShell`（视图层）target——`AgentShellCore` 四个模型文件刻意不 `import SwiftUI`
// （app/Package.swift 对 AgentShellCore target 的注释），这里的内容不应该跨过那条边界。

import SwiftUI
import AppKit
// rounds/0021：`chromeMaterialBackground`/`composerChromeBackground` 消费 `ChromeMaterialStyle`
// （AgentShellCore/AppearanceSettings.swift 的纯函数解析结果），需要显式 import 具名引用这个类型。
import AgentShellCore

extension View {
    /// 一个场景里"最突出的那一个"操作——例如工具栏的新建会话、或一组决策里官方建议的默认选项。
    /// macOS 26+ 用系统 Liquid Glass 的 prominent 玻璃样式（`.glassProminent`，WWDC25 新 API，
    /// 视觉上是玻璃质感，但仍然自动适配 Dark Mode/Increase Contrast/Reduce Transparency——这正是
    /// 用系统样式而不是手工模拟玻璃的原因），更早的系统回退到 `.borderedProminent`（pre-26 本来
    /// 就在用的标准"突出按钮"样式，不是为了凑数临时挑的替代品）。
    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 一组"平级选项"按钮（例如审批卡片上并排的多个决策按钮——D1 契约允许每条请求携带不同的
    /// `allowedDecisions` 子集，没有哪一个天然该比其它更突出，见 ApprovalModels.swift
    /// `offeredDecisions` 的文档注释）。macOS 26+ 用非 prominent 的玻璃样式（`.glass`），更早的
    /// 系统回退到 `.bordered`。`tint` 就是任务书"颜色只出现在按钮背景上"的落点——卡片本身
    /// （`contentCardBackground`）不带颜色，区分"允许/拒绝"语义全靠这里的 tint。
    @ViewBuilder
    func peerActionButtonStyle(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass).tint(tint)
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }

    /// 内容层卡片背景——**必须是标准 material，不是 glassEffect**（任务书硬约束原文：审批卡片等
    /// 内容卡片"content-layer card using standard material; tint only on the button
    /// background"；消息流本身"content layer — never glassEffect on message bubbles"）。这个
    /// 方法只封装"标准 material 该配哪种形状"这一件事，从不在内部调用 `glassEffect`——调用点因此
    /// 结构性地不可能在内容层意外引入玻璃。
    ///
    /// macOS 26+ 用 `ConcentricRectangle()` 当形状——嵌套在窗口/侧栏等容器内的卡片，系统据此把
    /// 圆角计算成与外层容器"同心"（任务书 concrete 项 7：容器嵌套在窗口内时用同心圆角），比手写
    /// 固定 `cornerRadius` 更贴合当前 HIG；更早的系统没有这个类型，回退到普通
    /// `RoundedRectangle(cornerRadius:)`（`cornerRadius` 参数只在这个分支生效）。
    @ViewBuilder
    func contentCardBackground(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26, *) {
            self.background(.regularMaterial, in: ConcentricRectangle())
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// 卡片内部"次级/内嵌"小容器的背景（例如审批卡片里等宽命令预览的底色、工具调用结果展开后的
    /// 预览块）——用层级填充色 `.fill.tertiary` 取代固定灰度 `Color.gray.opacity(...)`：前者是
    /// SwiftUI 早就有的语义填充样式（不是 Liquid Glass API），本身就跟着 Dark Mode/Increase
    /// Contrast 走，不需要 `#available` 门控。放在这个文件只是因为它和上面几个方法同属"卡片视觉
    /// 语言"这一组调用点复用的小工具，不是因为它本身是新 API。
    func insetContentBackground(cornerRadius: CGFloat = 6) -> some View {
        self.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 消息流滚动列表的滚动边缘效果——让顶部/底部内容在滚动时于 header/composer 下方自然虚化，
    /// 而不是硬切边（任务书 concrete 项 4）。macOS 26+ 专属 API，更早系统没有对应能力；pre-26
    /// 分支刻意什么都不做（标准 ScrollView 本来的样子），不手工模拟一个只有旧系统才"缺"的效果——
    /// 那样做的成本和收益不成比例，也和"不引入自定义视觉特效"的克制精神相冲突。
    @ViewBuilder
    func softScrollEdgeEffect(_ edges: Edge.Set) -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    // MARK: - rounds/0021：chrome 层透明度（深化 + 可自定义），红线落点见 chromeShapeStyle

    /// chrome 层通栏背景（工具栏下的状态条/侧栏内的横幅——如 SessionListView 的连接状态条/全局
    /// 错误横幅/token 占位符提示，SessionDetailView 的 streamErrorBanner）——它们此前统一用固定的
    /// `.background(.regularMaterial)`（rounds/0017 Change 2 的既有选择），本轮换成读取
    /// `ChromeTransparencyResolver` 的解析结果，让"用户滑块 + 无障碍红线"在这些既有 chrome 表面上
    /// 也生效，不只是新加的 composer 一处——任务书原文"Deepening means making the chrome layer
    /// genuinely materials-based and coherent"，coherent 的落点就在这里：同一次渲染里,所有 chrome
    /// 表面读的是同一个已解析的 `ChromeMaterialStyle`（调用方传入,这个方法自己不重新计算),不会出现
    /// "composer 已经因为 Reduce Transparency 变不透明了,侧栏横幅却还是半透明"这种不一致。
    ///
    /// 不裁形状（沿用这些调用点此前就没有 `in:` 参数的既有写法——它们都是贴边通栏,不是浮动卡片）。
    @ViewBuilder
    func chromeMaterialBackground(_ style: ChromeMaterialStyle) -> some View {
        self.background(chromeShapeStyle(style))
    }

    /// composer 输入区容器专用——scope-lock 点名的"chrome 深化"落点：这里此前完全没有背景（纯布局
    /// `HStack` + `padding`），是四个既定 chrome 表面（窗口背景/工具栏/侧栏/输入区容器）里唯一一个
    /// 「从无到有」的，不是「把已有材质换个来源」。
    ///
    /// 浮动圆角样式（不是贴边通栏矩形）——呼应 macOS 26 系统 app（备忘录/信息新版排版）把输入区处理成
    /// 一个悬浮的圆角玻璃卡片、不贴满宽度直角条的观感，视觉上更贴近"深化"而不是"从无到有地填一块灰
    /// 底"。调用点（SessionDetailView.composer）配合加了左右/底部 padding，让这个背景形状真正"浮"
    /// 在窗口内容区里，不是紧贴窗口边缘。
    ///
    /// macOS 26+ 且非不透明时，用真正的 `glassEffect` view modifier——本文件此前所有方法都只用
    /// `Material`（`contentCardBackground`/`insetContentBackground`）或玻璃**按钮样式**
    /// （`.glass`/`.glassProminent`，那是系统按钮外观，不是这个 view modifier），这是本文件第一处
    /// 把 `glassEffect` 本身用在 chrome 容器背景上——即"深化"的字面落点。`ConcentricRectangle`
    /// 沿用 `contentCardBackground` 同款理由（嵌套在窗口内的容器，圆角与外层窗口同心）。
    ///
    /// **红线落点**：`.opaque` 分支——不论 macOS 版本——一律渲染真正不透明的系统窗口背景色，无条件
    /// 生效（不再看 `#available`）：无障碍设置必须在任何 macOS 版本上都压过用户滑块，不是 26+ 独占
    /// 的能力。`style` 本身只由调用方已经跑过 `ChromeTransparencyResolver.resolve(...)` 的结果决定，
    /// 这个方法不重新判断"现在该不该透明"。
    ///
    /// rework（2026-08-14，T-114 codex 对抗评审阻断项②）：修前 `.translucent` 分支没有解出关联值
    /// （连 `case .translucent(let intensity)` 都没写),macOS 26 上不论滑块在哪,composer 背景永远
    /// 渲染同一份固定的 `.glassEffect(.regular, ...)`——滑块对这一个表面在 26 上彻底没有效果,是一条
    /// 新的静默失败路径,且恰好发生在本机能实跑验证的分支上（本机 26.6）。
    ///
    /// **修法,以及为什么不是"直接把 intensity 传给 glassEffect"**：直接读了本机安装的 macOS 26.5
    /// SDK 里 `SwiftUICore.swiftinterface` 的 `Glass` 类型真实声明（交付报告 verification 记录了
    /// 具体搜索方法与命中行号）——`Glass` 的公开 API 只有 `.regular`/`.clear`/`.identity` 三个静态
    /// 成员,以及 `.tint(_:)`/`.interactive(_:)` 两个修饰方法,**没有任何连续的强度/不透明度参数**。
    /// 这不是本文件此前漏调用了什么,是这个类型的公开契约里根本不存在这样一个入参——"直接传
    /// intensity"在这份 SDK 上连编译都通不过,不是"能做但没做"。
    ///
    /// 因此这里改用"把玻璃渲染成一个独立背景层,只对这一层本身调节不透明度"：`intensity` 越大
    /// （用户越想要透明),这层玻璃的不透明度越低,composer 背后的内容透得越多——方向上呼应
    /// `materialForChromeIntensity` 里"intensity 越大越趋近 `.ultraThinMaterial`"；`intensity` 越
    /// 接近 0（但严格 `>0`——`0` 本身已经在 `ChromeTransparencyResolver` 里被折成 `.opaque`,不会
    /// 到达这里),玻璃层不透明度越接近 1,最贴近"regular 玻璃"本来的样子。下限夹在
    /// `AgentShellCore.ComposerGlassLayerOpacity.resolve(intensity:)` 里,不允许降到 0——真降到 0
    /// 时这块 chrome 会跟"完全没有背景"在肉眼下无法区分,那是"消失",不是"更透明的玻璃",超出了这个
    /// 滑块本该表达的产品意图。这个纯数值映射本身不写在这个文件里（尽管这里是唯一调用点)——与
    /// `ChromeTransparencyResolver`/`ApprovalDecisionSemantics` 同一条理由（AgentShellCore/
    /// AppearanceSettings.swift 头注释）：`AgentShell` 是 executableTarget,`frame-replay-tests`
    /// 没有任何路径能 import 它,写在这里的任何数值边界就只能靠人眼在真机上拖滑块肉眼确认,收进
    /// AgentShellCore 才能被单测钉住。
    ///
    /// 玻璃层用 `.background { }` 闭包单独构造背景,不再像修前那样直接对 `self` 调
    /// `.glassEffect(...)`——`.opacity(...)` 必须只作用在背景玻璃这一层,不能连累 composer 里的
    /// 文本框/发送按钮一起变淡（那两个是内容,红线要求"透明度只用在 chrome"、不能波及可交互内容的
    /// 可读性/可用性）；直接对 `self` 调用后再叠 `.opacity(...)` 做不到这种分层,这是这里改成
    /// `Color.clear.glassEffect(...)` 放进 `.background { }` 闭包、而不是原地加一个修饰符的原因。
    @ViewBuilder
    func composerChromeBackground(_ style: ChromeMaterialStyle) -> some View {
        switch style {
        case .opaque:
            if #available(macOS 26, *) {
                self.background(chromeShapeStyle(style), in: ConcentricRectangle())
            } else {
                self.background(chromeShapeStyle(style), in: RoundedRectangle(cornerRadius: 16))
            }
        case .translucent(let intensity):
            if #available(macOS 26, *) {
                self.background {
                    Color.clear
                        .glassEffect(.regular, in: ConcentricRectangle())
                        .opacity(ComposerGlassLayerOpacity.resolve(intensity: intensity))
                }
            } else {
                self.background(chromeShapeStyle(style), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// 把已解析的 `ChromeMaterialStyle` 转成一个可以喂给任意 `.fill(...)`/`.background(...)` 调用点的
/// `ShapeStyle`——类型擦除（`AnyShapeStyle`）是因为两个分支底层类型不同（`Color` vs `Material`），
/// 调用点不需要关心具体是哪一个。免费函数（不是 `View` extension 方法）：`SessionListView` 的
/// `connectionBanner` 需要在一个条件性的 `.background { if … { Rectangle().fill(...) } }` 闭包
/// 里使用它（不方便再套一层 `.background(...)` modifier），这个签名两种调用形状都能覆盖。
///
/// **红线的第二处落点**：`.opaque` 用 `Color(nsColor: .windowBackgroundColor)`——一个真正不透明的
/// 系统语义色，不是"看起来最不透明的材质"（`Material` 的官方文档说材质本身会自动适配 Reduce
/// Transparency/Increase Contrast，但红线要求这里不依赖那份信任、自己再把关一次——两层任何一层单独
/// 失效都不会让透明背景漏给不该看见它的人）。
func chromeShapeStyle(_ style: ChromeMaterialStyle) -> AnyShapeStyle {
    switch style {
    case .opaque:
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    case .translucent(let intensity):
        return AnyShapeStyle(materialForChromeIntensity(intensity))
    }
}

/// 用户滑块的连续值（`(0,1]`，`0` 本身已经在 `ChromeTransparencyResolver` 里被折成 `.opaque`，
/// 不会到达这里）分五档映射到系统 `Material` 的五个官方级别——离散化是有意的：`Material` 只提供这
/// 五个级别，不是一个连续参数，且这五个级别都各自有 Apple 调过的具体数值、都文档化为会自动适配
/// Dark Mode/Increase Contrast/Reduce Transparency（这一点在不透明分支之外仍然成立，是本方法能够
/// 安全使用 `Material` 而不是自己拿 `Color(...).opacity(...)` 手搭一个的原因——后者不会自动适配，
/// 见 SessionDetailView.swift 里 `MessageBubble` 头注释记录的历史教训）。
private func materialForChromeIntensity(_ intensity: Double) -> Material {
    switch intensity {
    case ..<0.2: return .ultraThickMaterial
    case ..<0.4: return .thickMaterial
    case ..<0.6: return .regularMaterial
    case ..<0.8: return .thinMaterial
    default: return .ultraThinMaterial
    }
}

// rework（2026-08-14，T-114 阻断项②修法的数值部分）：`(0,1]` 的滑块强度 -> composer 玻璃背景层
// 不透明度这个映射本来可以照抄 `materialForChromeIntensity` 写成这个文件里的一个 private 函数——
// 但那样会重蹈本文件所有"判断逻辑"此前已经吃过的同一个结构性亏：`AgentShell` 是 executableTarget，
// `frame-replay-tests` 没有任何路径能 import 它，写在这里的任何数值边界（下限夹到多少、线性插值的
// 斜率对不对）就只能靠人眼在真机上拖滑块肉眼确认——AgentShellCore/AppearanceSettings.swift 头注释
// 反复强调的"结构性不可测"在这里同样成立，没有理由这一处例外。因此实际的纯数值映射收进
// `AgentShellCore.ComposerGlassLayerOpacity.resolve(intensity:)`（该类型文档注释含完整理由与
// SDK 依据），本文件只剩下调用它这一步。
