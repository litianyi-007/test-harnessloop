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
}
