// 会话详情面板的熊头水印——视觉打磨任务（继 rounds/0021 液态玻璃/透明度之后）新增,2026-08-14
// 从左侧会话列表搬到这里。落点：`SessionDetailView.swift` 把它放进整个详情面板 `VStack` 的
// `.background(...)`（`watermarkBackground` 属性）——旋转、缩放、右下角贴角怎么算的取舍见那处的
// 文档注释;本文件只管"熊头长什么样"这一件事,不关心调用方把它画在哪个视图、转了多少度。
//
// ## 熊的形状怎么进到这个 target 里,以及为什么不是另外两种做法
//
// `Resources/icon-source/`（`IconGeometry.swift`/`IconRenderer.swift`）明确是一个**构建期工具**，
// 不是 app target——`app/Package.swift` 里没有任何 `.target`/`.executableTarget` 的 `path` 指向
// `apps/AgentShell/Resources/icon-source`（已读源码逐条核对过,不是猜测），`IconRenderer.swift` 自己
// 的头注释也写明"不进 SwiftPM target...是一次性构建期工具,不是 app 运行时代码"。这排除了两种更直接
// 的做法：
//
//   1. **把 icon-source 加成 AgentShell target 的依赖**——任务书明确点名不要这样做（"do not add it
//      as a dependency"）,而且这么做需要改 `Package.swift`,本轮该文件本身是禁止改动项。
//   2. **改用加载一张预渲染的位图资产**——`AgentShell` target 没有 `resources:` 声明（见
//      `Package.swift`,本轮只读不改）,新增一份随包资源要么需要补 `Package.swift`（禁止），要么走
//      `MenuBarIconLoader.swift` 那种"运行时探测候选目录"的手法（对已生成的固定尺寸
//      `MenuBarIconTemplate.png` 这类资产是合理选择,但水印需要**无级适配任意尺寸的、可被用户拖动
//      改变宽度的侧栏面板**,位图缩放会糊,矢量天然不会——这正是任务书那句"prefer something that
//      stays crisp at any size"点名的取舍）。再造一条图标生成流水线去产出"水印专用"位图，又会碰到
//      "不得修改图标生成器"这条约束。
//
// 因此选择任务书给出的第一个选项：把轮廓**重新表达成这个 target 里的 SwiftUI `Shape`**，不依赖、
// 不引用 icon-source 的任何一行代码。下面的坐标是照着 `IconGeometry.swift` 的 `BearGeometry`/
// `eyeRadiusB1`/`muzzleHoleCenter` 等常量文档描述的比例**独立誊写**的（耳朵圆心/半径、头部四段贝塞尔、
// B1 变体的两个眼洞与口鼻洞——不是 A1 变体那套，因为 A1 需要磁贴渐变色打底、鼻子与口鼻不挖空,是给
// Dock 图标用的组合，水印只需要单色剪影，B1 的"洞"设计本来就是为单色场景做的），让水印仍然读得出
// "是同一只熊"，但两套坐标结构上互不耦合——以后改任何一边都不会牵动另一边，也不构成对 icon-source
// 的依赖。

import SwiftUI

/// 耳朵 + 头部轮廓（不含洞）。`Shape.fill()` 默认按 nonzero 缠绕规则填充（不是 even-odd）——两只
/// 耳朵圆与头部路径虽然大面积重叠，但只要子路径同向缠绕（`Path.addEllipse`/贝塞尔路径都是一致的
/// 缠绕方向），nonzero 规则会把重叠区域自然合并成并集，不会在耳朵与头顶接缝处抠出新月形缺口——
/// 这正是 `IconGeometry.swift` 头注释里说明"字面 even-odd 在耳朵/头部接缝处不成立"、
/// `IconRenderer.swift` 改用 transparency-layer 手工绕过的同一个问题，SwiftUI 这里不需要那层手工
/// 绕过，因为默认填充规则本来就是 nonzero。
private struct BearHeadOutline: Shape {
    func path(in rect: CGRect) -> Path {
        // 设计坐标系 100x100（沿用 icon 几何的比例基准）。等比缩放（取宽高较小者，不拉伸变形）、
        // 绕熊本体包围盒的实际竖直中心（53，不是几何画布中点 50——耳朵顶到 y=19、下巴到 y=87，
        // 真正的视觉中心在 53，直接用画布中点会让水印在给定的矩形里看起来偏上，见
        // `IconGeometry.swift` `bearBoundingBoxCenterY` 的同一条理由）居中放进调用方给的 `rect`。
        //
        // 刻意不做 icon 那套"放大到出血"的处理（`BearGeometry.b1SharedScale` = 1.47）——那是给
        // 16-32px 图标在极小画布上争取最大辨识度的取舍，水印是背景纹理，"低对比度、安安静静"
        // 才是这里的目标，1.0 倍（贴着 100x100 设计框内切）自带的留白（横向各 12、纵向顶部 19/
        // 底部 13）反而是这里想要的呼吸感，不是要修的"缺陷"。
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * s
        let oy = rect.midY - 53 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        path.addEllipse(
            in: CGRect(x: pt(26, 33).x - 14 * s, y: pt(26, 33).y - 14 * s, width: 28 * s, height: 28 * s))
        path.addEllipse(
            in: CGRect(x: pt(74, 33).x - 14 * s, y: pt(74, 33).y - 14 * s, width: 28 * s, height: 28 * s))

        // 头部轮廓——四段三次贝塞尔，从底部中点出发逆时针回到起点（与 icon 源几何同一条路径的
        // 独立誊写，见本文件头注释）。
        path.move(to: pt(50, 87))
        path.addCurve(to: pt(19, 57), control1: pt(31, 87), control2: pt(19, 74))
        path.addCurve(to: pt(50, 31), control1: pt(19, 41), control2: pt(32, 31))
        path.addCurve(to: pt(81, 57), control1: pt(68, 31), control2: pt(81, 41))
        path.addCurve(to: pt(50, 87), control1: pt(81, 74), control2: pt(69, 87))
        path.closeSubpath()
        return path
    }
}

/// 两个眼洞 + 一个口鼻洞——从 `BearHeadOutline` 里挖空（见 `BearHeadWatermark`），给水印保留
/// "一个圆再加两个小圆"这种一眼认得出是熊的读法（同 `IconGeometry.swift` 里
/// `BearGeometrySmall16` 文档注释点名的 Mickey-Mouse 式识别度），而不是一坨没有五官、可能被看成
/// 云朵或盾牌的纯色团块。坐标取自 icon 几何 B1（剪影）变体的洞位置——B1 本来就是为单色剪影场景
/// 设计的洞，比 A1（鼻子单独挖空、口鼻并入轮廓,是给磁贴渐变底色配色用的）更贴合水印的单色需求。
private struct BearHeadHoles: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * s
        let oy = rect.midY - 53 * s
        func ellipseRect(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: ox + (cx - rx) * s, y: oy + (cy - ry) * s, width: rx * 2 * s, height: ry * 2 * s)
        }
        var path = Path()
        path.addEllipse(in: ellipseRect(39, 58.5, 4.2, 4.2))
        path.addEllipse(in: ellipseRect(61, 58.5, 4.2, 4.2))
        path.addEllipse(in: ellipseRect(50, 74, 8.4, 5.8))
        return path
    }
}

/// 公开入口：`BearHeadOutline` 填 `color`，`BearHeadHoles` 用 `.blendMode(.destinationOut)` 在
/// `.compositingGroup()` 内挖空——这是 SwiftUI 里对应 `IconRenderer.swift`
/// "transparency layer + `.clear` blend mode" 那套手法的等价写法：`.compositingGroup()` 强制这个
/// `ZStack` 先渲染进自己的离屏缓冲区，`.destinationOut` 因此只会擦除**这个缓冲区内部**、这一步之前
/// 已经画好的像素（即 `BearHeadOutline` 的填充），不会波及调用方在这个 view 背后放的任何内容
/// （例如 `SessionDetailView` 的消息流/composer 背景）——两层任何一层放错顺序或漏加
/// `compositingGroup()` 都会让挖空效果要么不生效、要么误伤背景，这也是为什么这两步被封成一个
/// 不可拆分的 View 而不是留给调用点自己组合。
///
/// 是纯矢量 `Shape`，不是位图——在调用点给它的任意尺寸下都用同一套路径重新栅格化，不会像位图那样
/// 在放大或面板尺寸变化时出现锯齿/模糊。也没有深浅色适配的额外代码：`color` 由调用点传入
/// （`SessionDetailView` 传 `.primary.opacity(...)`——`Color.primary` 本身就是浅色下近黑、深色下
/// 近白的系统动态色，水印因此不需要在这个文件里写任何 `#available`/`colorScheme` 分支）。
struct BearHeadWatermark: View {
    var color: Color

    var body: some View {
        ZStack {
            BearHeadOutline().fill(color)
            BearHeadHoles().fill(Color.black).blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
