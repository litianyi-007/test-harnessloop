// AgentShell app-icon 渲染 —— round 0021。用 Core Graphics 直接栅格化到精确像素尺寸的 PNG，
// 不经过任何 SVG 中间格式（本机没有 rsvg-convert/inkscape/ImageMagick/cairosvg，已实测确认，
// 见任务报告）。
//
// 关键约定：BearGeometry 的坐标系是 100x100、y 向下。makeBitmapContext 对每一张位图都建一次
// "翻转"过的 context，让后续绘制调用可以直接照抄设计稿坐标——这一点已经用独立探针脚本实测验证
// （对称探针：一个红块放设计坐标 y 小的一端、一个蓝块放 y 大的一端,验证红块真的落在最终 PNG
// 顶部），不是凭记忆假设。
//
// 踩过的一个坑,写在这里防止以后重犯：**把已经渲染好的 CGImage 合成进另一个"翻转过"的
// context 时（`ctx.draw(image, in: rect)`），图像内容相对该 context 里的路径填充会多翻一次
// 竖直方向**——矩形本身的定位/尺寸不受影响,只有图像内容的上下方向会翻。这是 Core Graphics
// 一个不算冷门但很容易踩的行为（图像合成和路径填充在"翻转 context"里的语义不对称），
// 同样是用探针脚本实测坐实的,不是凭印象。contact sheet 需要合成多张预渲染的图标位图,
// 所以专门包一层 `compositeImage(_:_:in:)` 在每次合成时局部抵消这个多余翻转；
// renderA1Tile/renderB1Silhouette 本身只做路径填充，不受影响，不需要这层包装。
//
// 不进 SwiftPM target（app/Package.swift 没有任何 target 的 path 指向这个目录）——这是一次性
// 构建期工具,不是 app 运行时代码,用 generate-icons.sh 里的裸 `swiftc` 编译执行。

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconGenError: Error, CustomStringConvertible {
    case contextCreationFailed(String)
    case imageDestinationFailed(URL)
    case imageCreationFailed(String)

    var description: String {
        switch self {
        case .contextCreationFailed(let where_): return "创建 CGContext 失败：\(where_)"
        case .imageDestinationFailed(let url): return "写 PNG 失败：\(url.path)"
        case .imageCreationFailed(let where_): return "context.makeImage() 返回 nil：\(where_)"
        }
    }
}

let iconWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let iconBlack = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

// MARK: - 位图 context 与 PNG 写出

/// 建一个 `pixelSize` x `pixelSize` 的 RGBA8、premultiplied、sRGB 位图 context，
/// 并把 CTM 翻成"顶部是设计坐标 y=0、y 向下"，见文件头注释。
func makeBitmapContext(pixelSize: Int) throws -> CGContext {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw IconGenError.contextCreationFailed("sRGB colorspace")
    }
    guard
        let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw IconGenError.contextCreationFailed("bitmap \(pixelSize)x\(pixelSize)")
    }
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    let scale = CGFloat(pixelSize) / 100.0
    ctx.translateBy(x: 0, y: CGFloat(pixelSize))
    ctx.scaleBy(x: scale, y: -scale)
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw IconGenError.imageDestinationFailed(url)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw IconGenError.imageDestinationFailed(url)
    }
}

/// 把一张已经渲染好的 CGImage 合成进 `ctx`（`ctx` 可能是翻转过的 context）,
/// 局部抵消"图像合成在翻转 context 里比路径填充多翻一次"的既有行为——见文件头坑位说明。
func compositeImage(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

// MARK: - 形状填充小工具

private func ellipseRect(center: CGPoint, rx: CGFloat, ry: CGFloat) -> CGRect {
    CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
}
private func fillEllipse(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat) {
    ctx.fillEllipse(in: ellipseRect(center: center, rx: rx, ry: ry))
}
private func fillCircle(_ ctx: CGContext, center: CGPoint, r: CGFloat) {
    fillEllipse(ctx, center: center, rx: r, ry: r)
}

// MARK: - 熊身主体：ears+head 合并轮廓 + 挖空五官洞

/// A1（Dock/Finder,磁贴上的圆熊）与 B1（菜单栏剪影熊）共用的画法：
///
/// 1. 在一个 transparency layer 里先实心画 ears + head（A1 还要加 muzzle）,颜色都是同一个
///    `fillColor`——重叠部分反正是同色不透明,画几遍效果都一样,不需要为了"并集"去手工控制
///    子路径缠绕方向（ears 和 head 在给定坐标下有相当大的重叠面积,字面 even-odd 会在接缝处
///    抠出一个新月形缺口,不是想要的效果；见 IconGeometry.swift 对应注释）。
/// 2. 切到 `.clear` blend mode,在同一个 transparency layer 里画"洞"（A1 是 nose+eyes,
///    B1 是 eyes+muzzle 洞）——`.clear` 只把这一层内部已经画的像素变透明,不会波及这层
///    之外、更早画好的背景（比如 A1 的磁贴渐变色）,这正是用 transparency layer 包一层的目的。
/// 3. 结束 transparency layer,应用调用方给的整体变换（比如 A1 在磁贴里居中缩小到 72%）。
enum BearVariant: Equatable {
    case a1
    case b1
}

func drawBearMark(_ ctx: CGContext, variant: BearVariant, fillColor: CGColor, transform: CGAffineTransform) {
    ctx.saveGState()
    ctx.concatenate(transform)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(fillColor)
    fillCircle(ctx, center: BearGeometry.earLeftCenter, r: BearGeometry.earRadius)
    fillCircle(ctx, center: BearGeometry.earRightCenter, r: BearGeometry.earRadius)
    ctx.addPath(BearGeometry.headPath())
    ctx.fillPath()
    if variant == .a1 {
        fillEllipse(
            ctx, center: BearGeometry.muzzleCenter, rx: BearGeometry.muzzleRX, ry: BearGeometry.muzzleRY)
    }

    ctx.setBlendMode(.clear)
    switch variant {
    case .a1:
        fillEllipse(ctx, center: BearGeometry.noseCenter, rx: BearGeometry.noseRX, ry: BearGeometry.noseRY)
        fillCircle(ctx, center: BearGeometry.eyeLeftCenterA1, r: BearGeometry.eyeRadiusA1)
        fillCircle(ctx, center: BearGeometry.eyeRightCenterA1, r: BearGeometry.eyeRadiusA1)
    case .b1:
        fillCircle(ctx, center: BearGeometry.eyeLeftCenterB1, r: BearGeometry.eyeRadiusB1)
        fillCircle(ctx, center: BearGeometry.eyeRightCenterB1, r: BearGeometry.eyeRadiusB1)
        fillEllipse(
            ctx, center: BearGeometry.muzzleHoleCenter, rx: BearGeometry.muzzleHoleRX,
            ry: BearGeometry.muzzleHoleRY)
    }
    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: - 磁贴背景（A1 专用）

/// 只画渐变——不再自己 save/clip/restore。round 0021 三修之前这个函数自己包一层
/// save/clip/restore，磁贴圆角裁切范围只在这个函数内部生效，画完渐变就恢复了；当时
/// 熊本体缩小留白（0.72 倍），从来不会碰到裁切边界，这个"裁切范围太窄"的问题一直没暴露。
/// 三修把熊放大到会出血（`BearGeometry.a1TileScale` 1.47），如果还用旧写法，熊出血的部分
/// 会画在磁贴圆角裁掉的透明缺角里、变成"漂在磁贴外面的白色碎片"，不是用户要的"被磁贴圆角
/// 裁切"的效果。改法：裁切范围的 save/clip 移到调用方（`renderA1Tile`），一路开到熊也画完
/// 才 restore，磁贴渐变和熊身共用同一次裁切——出血部分因此被磁贴的圆角边界干净切掉，
/// 而不是画到圆角外面的透明区域。
func drawTileGradient(_ ctx: CGContext) {
    let top = BearGeometry.tileGradientTop
    let bottom = BearGeometry.tileGradientBottom
    let topColor = CGColor(
        srgbRed: CGFloat(top.r) / 255, green: CGFloat(top.g) / 255, blue: CGFloat(top.b) / 255, alpha: 1)
    let bottomColor = CGColor(
        srgbRed: CGFloat(bottom.r) / 255, green: CGFloat(bottom.g) / 255, blue: CGFloat(bottom.b) / 255,
        alpha: 1)
    if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(
            colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0, 1])
    {
        ctx.drawLinearGradient(
            gradient, start: CGPoint(x: 50, y: 0), end: CGPoint(x: 50, y: 100), options: [])
    }
}

// MARK: - 顶层渲染入口

/// A1 圆熊：磁贴 + 白色熊身（nose/eyes 挖空露出磁贴渐变色）。用于 .icns 的每一张位图。
///
/// 磁贴圆角裁切（`clip()`）在这里统一建立、渐变和熊身都画在同一次裁切范围内才 restore——
/// 熊放大到 `BearGeometry.a1TileScale`（round 0021 三修，1.47）之后会主动出血，
/// 出血的部分需要被磁贴的圆角边界裁掉（看起来像"熊比磁贴大，被磁贴的形状裁切"），
/// 而不是画到圆角之外的透明缺角里变成飘着的白色碎片——`drawTileGradient` 的文档注释
/// 有完整对比。
func renderA1Tile(pixelSize: Int) throws -> CGImage {
    let ctx = try makeBitmapContext(pixelSize: pixelSize)
    ctx.saveGState()
    let tileRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let clipPath = CGPath(
        roundedRect: tileRect, cornerWidth: BearGeometry.tileCornerRadius,
        cornerHeight: BearGeometry.tileCornerRadius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()
    drawTileGradient(ctx)
    let transform = BearGeometry.centeredScale(
        BearGeometry.a1TileScale, aboutX: 50, aboutY: BearGeometry.bearBoundingBoxCenterY)
    drawBearMark(ctx, variant: .a1, fillColor: iconWhite, transform: transform)
    ctx.restoreGState()
    guard let image = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("renderA1Tile(\(pixelSize))")
    }
    return image
}

/// B1 剪影熊：透明背景 + 纯色（通常是黑）熊身剪影,eyes+muzzle 挖空到透明。
/// `fillColor` 可传入白色,仅用于 contact sheet 模拟系统在深色菜单栏下的 template 反色效果——
/// 实际入库的 MenuBarIconTemplate.png 资产本身必须是纯黑+alpha（见 main.swift）。
///
/// 只用于 32px 及以上——16px 有专门的 `renderB1SilhouetteSmall16`（见该函数文档与
/// IconGeometry.swift 的 BearGeometrySmall16 注释：同一份 100x100 几何直接缩到 16px
/// 读不出熊，用户实拍验收后打回重做）。
///
/// round 0021 三修之前这里传的是 `.identity`（不缩放）——熊本体（ears+head）的原始包围盒
/// 自带留白（横向各留 12 单位、纵向顶部留 19/底部留 13），从来没有主动撑满过画布。
/// 用户要求两个 mark 都撑满、允许出血,这里改用 `BearGeometry.b1SharedScale`（1.47，
/// 绕熊自己包围盒纵向中心 `bearBoundingBoxCenterY` 缩放，理由见该常量文档）。B1 没有磁贴，
/// 出血部分直接被这个函数自己建的 16x16/32x32 画布边界裁掉（`makeBitmapContext` 建出的
/// context 本来就不比目标像素尺寸大），不需要像 A1 那样额外建裁切路径。
func renderB1Silhouette(pixelSize: Int, fillColor: CGColor) throws -> CGImage {
    let ctx = try makeBitmapContext(pixelSize: pixelSize)
    let transform = BearGeometry.centeredScale(
        BearGeometry.b1SharedScale, aboutX: 50, aboutY: BearGeometry.bearBoundingBoxCenterY)
    drawBearMark(ctx, variant: .b1, fillColor: fillColor, transform: transform)
    guard let image = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("renderB1Silhouette(\(pixelSize))")
    }
    return image
}

/// B1 16px 专版：直接在 16x16 像素网格上画，关闭抗锯齿求硬边——不是把 `BearGeometry` 的
/// 100 单位坐标换算到 16px 再栅格化，是专门给这一个具体尺寸设计的形状（头+两只支棱出去的
/// 圆耳+两只干净整像素眼睛,不画口鼻洞）。完整实测记录见 IconGeometry.swift 里
/// `BearGeometrySmall16` 的文档注释。不接收 pixelSize 参数——这就是"16px 该长什么样"这一个
/// 具体设计，不是可以传参缩放的通用函数；32px 及以上请用 `renderB1Silhouette(pixelSize:fillColor:)`。
func renderB1SilhouetteSmall16(fillColor: CGColor) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let ctx = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        throw IconGenError.contextCreationFailed("renderB1SilhouetteSmall16")
    }
    // 硬边光栅化（不抗锯齿）：16px 的像素预算太小，半透明边缘只会糊成灰蒙蒙一片,
    // 不如让系统按"像素中心是否落在路径内"直接判定非黑即透明——这也是眼睛洞能精确
    // 对应单个像素、不粘连的前提（见 BearGeometrySmall16 注释）。
    ctx.setShouldAntialias(false)
    ctx.setAllowsAntialiasing(false)
    ctx.translateBy(x: 0, y: 16)
    ctx.scaleBy(x: 1, y: -1)

    typealias g = BearGeometrySmall16
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(fillColor)
    fillCircle(ctx, center: g.headCenter, r: g.headR)
    fillCircle(ctx, center: CGPoint(x: g.headCenter.x - g.earDX, y: g.earCY), r: g.earR)
    fillCircle(ctx, center: CGPoint(x: g.headCenter.x + g.earDX, y: g.earCY), r: g.earR)
    ctx.setBlendMode(.clear)
    fillCircle(
        ctx, center: CGPoint(x: g.headCenter.x - g.eyeDX, y: g.headCenter.y + g.eyeDY), r: g.eyeR)
    fillCircle(
        ctx, center: CGPoint(x: g.headCenter.x + g.eyeDX, y: g.headCenter.y + g.eyeDY), r: g.eyeR)
    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()

    guard let image = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("renderB1SilhouetteSmall16")
    }
    return image
}

/// 把一张已经栅格化好的图标位图按整数倍放大（最近邻,不插值）,叠一层像素网格线——
/// 专门给"按实际像素看清楚"的检查用（contact sheet 的像素级检查行），不是常规展示。
/// 内部用的是一个普通（未翻转）context 走 `draw(in:)`，这在正常场景下没问题——只有当
/// *目的地* 是翻转过的 context 时合成才需要 `compositeImage` 那层修正（见文件头坑位说明），
/// 这个函数自己新建的 context 从未翻转，不受影响；但这个函数产出的图像后续如果要贴进
/// contact sheet 那种翻转过的画布，调用方仍然要走 `compositeImage`，和贴其他图标位图一视同仁。
func magnifyWithPixelGrid(_ image: CGImage, factor: Int, gridColor: CGColor) throws -> CGImage {
    let w = image.width * factor
    let h = image.height * factor
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        throw IconGenError.contextCreationFailed("magnifyWithPixelGrid")
    }
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setStrokeColor(gridColor)
    ctx.setLineWidth(1)
    for i in 0...image.width {
        let x = CGFloat(i * factor)
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: CGFloat(h)))
    }
    for i in 0...image.height {
        let y = CGFloat(i * factor)
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: CGFloat(w), y: y))
    }
    ctx.strokePath()
    guard let outImage = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("magnifyWithPixelGrid")
    }
    return outImage
}

// MARK: - 文字标签（contact sheet 用）

/// 把一行文字渲染成一张紧贴文字包围盒的 CGImage,后续用 `compositeImage` 贴到 sheet 里——
/// 用独立小 context 画文字可以完全绕开"CoreText 在翻转 context 里要不要额外转 textMatrix"
/// 这一层问题（这张小 image 自己是不是翻转过的 context 画的不重要,`compositeImage` 合成
/// 到 sheet 时统一按"合成需要局部抵消翻转"处理,和贴一张图标位图完全一视同仁）。
func renderTextImage(_ text: String, fontSize: CGFloat, color: CGColor, bold: Bool = false) throws
    -> CGImage
{
    let baseFont =
        CTFontCreateUIFontForLanguage(.system, fontSize, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    var font = baseFont
    if bold,
        let boldFont = CTFontCreateCopyWithSymbolicTraits(
            baseFont, fontSize, nil, .traitBold, .traitBold)
    {
        font = boldFont
    }
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let attrString = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attrString)
    let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
    let width = max(1, Int(ceil(bounds.width)) + 4)
    let height = max(1, Int(ceil(fontSize * 1.5)))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        throw IconGenError.contextCreationFailed("text image '\(text)'")
    }
    ctx.textPosition = CGPoint(x: 2, y: CGFloat(height) * 0.3)
    CTLineDraw(line, ctx)
    guard let image = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("text image '\(text)'")
    }
    return image
}

// MARK: - Contact sheet：两个标 x 五个尺寸 x 浅/深底,一张 PNG 看全

/// contact sheet 的像素级检查行需要的高度（顶部小标题 + 一行 4 个放大 8x 的格子 +
/// 各自的说明文字）。拆成常量是因为总画布高度要在建 context *之前* 就算出来。
private let pixelCheckSectionHeight: CGFloat = 380

func renderContactSheet() throws -> CGImage {
    let sizes = [16, 32, 64, 128, 256]
    // 布局常量统一用 CGFloat（不是 Int）——sheet 画布的像素尺寸只在建 CGContext 那一刻转 Int 一次，
    // 其余全部留在 CGFloat 里做,避免像素网格算术和 CGRect/CGPoint 之间来回转型。
    let cellDisplay: CGFloat = 150
    let cellGap: CGFloat = 24
    let topMargin: CGFloat = 70
    let bottomMargin: CGFloat = 30
    let leftMargin: CGFloat = 30
    let rightMargin: CGFloat = 30
    let rowContentHeight = cellDisplay + 30
    let rowGap: CGFloat = 22

    struct Row {
        let label: String
        let isDark: Bool
        let variant: BearVariant
        let fill: CGColor
    }
    let lightGroundColor = CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    let darkGroundColor = CGColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    let rows: [Row] = [
        Row(label: "A1 圆熊 · 浅色底（磁贴自带渐变,不随环境变化）", isDark: false, variant: .a1, fill: iconWhite),
        Row(label: "A1 圆熊 · 深色底（同一张图,不需要适配）", isDark: true, variant: .a1, fill: iconWhite),
        Row(
            label: "B1 剪影熊 · 浅色底（template 原色：黑,入库资产就是这个）", isDark: false, variant: .b1,
            fill: iconBlack),
        Row(
            label: "B1 剪影熊 · 深色底（模拟系统 template 反色：白,非入库资产,仅供对照）",
            isDark: true, variant: .b1, fill: iconWhite),
    ]

    // 行标签列宽按实际渲染出的文字宽度算，不是猜一个常量——上一版拿固定 300 硬编码，
    // 长一点的标签（比如"深色底"那两行）文字比 300 宽，第一格图标画在标签之上，
    // 尾巴被盖掉一截，人眼读起来就是断句。既然文字图片本来就要渲染出来才能贴图，
    // 干脆先把所有行标签渲染一遍量出最大宽度，再拿这个真实宽度定版式，从根上不会再截断。
    let rowLabelImages = try rows.map {
        try renderTextImage($0.label, fontSize: 14, color: CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1))
    }
    let rowLabelWidth = (rowLabelImages.map { CGFloat($0.width) }.max() ?? 0) + 16

    let widthF =
        leftMargin + rowLabelWidth + CGFloat(sizes.count) * cellDisplay
        + CGFloat(sizes.count - 1) * cellGap + rightMargin
    let gridSectionBottom =
        topMargin + CGFloat(rows.count) * rowContentHeight + CGFloat(rows.count - 1) * rowGap
    let heightF = gridSectionBottom + pixelCheckSectionHeight + bottomMargin
    let width = Int(widthF.rounded(.up))
    let height = Int(heightF.rounded(.up))

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        throw IconGenError.contextCreationFailed("contact sheet")
    }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

    let title = try renderTextImage(
        "AgentShell 图标对照表 — round 0021（A1 Dock/Finder ・ B1 菜单栏）", fontSize: 20,
        color: CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1), bold: true)
    compositeImage(
        ctx, title,
        in: CGRect(x: leftMargin, y: 22, width: CGFloat(title.width), height: CGFloat(title.height)))

    for (rowIndex, row) in rows.enumerated() {
        let rowTop = topMargin + CGFloat(rowIndex) * (rowContentHeight + rowGap)

        let labelImg = rowLabelImages[rowIndex]
        let labelY = rowTop + (cellDisplay - CGFloat(labelImg.height)) / 2
        compositeImage(
            ctx, labelImg,
            in: CGRect(
                x: leftMargin, y: labelY, width: CGFloat(labelImg.width),
                height: CGFloat(labelImg.height)))

        for (colIndex, size) in sizes.enumerated() {
            let cellX = leftMargin + rowLabelWidth + CGFloat(colIndex) * (cellDisplay + cellGap)
            let cellRect = CGRect(x: cellX, y: rowTop, width: cellDisplay, height: cellDisplay)

            let groundColor = row.isDark ? darkGroundColor : lightGroundColor
            let groundPath = CGPath(roundedRect: cellRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
            ctx.setFillColor(groundColor)
            ctx.addPath(groundPath)
            ctx.fillPath()
            ctx.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 0.4))
            ctx.setLineWidth(1)
            ctx.addPath(groundPath)
            ctx.strokePath()

            // 图标按目标像素尺寸原生栅格化（不是画大图再缩小）,再用最近邻放大贴到 sheet 里——
            // 这样才是"16px 真实会长什么样",不是"看起来很精细的大图缩略图"。
            // B1 的 16px 列必须走专版渲染器——这一列展示的必须是实际入库的那张 PNG 长什么样,
            // 不能是共享几何缩下来的、已经被判定读不出熊的那版,否则这张对照表本身就在
            // 用两套不同的画法误导人（下面新增的像素级检查行同理，同一个原则）。
            let icon: CGImage
            switch row.variant {
            case .a1: icon = try renderA1Tile(pixelSize: size)
            case .b1:
                icon =
                    size == 16
                    ? try renderB1SilhouetteSmall16(fillColor: row.fill)
                    : try renderB1Silhouette(pixelSize: size, fillColor: row.fill)
            }
            let iconDisplaySize: CGFloat = min(cellDisplay - 24, 118)
            let iconRect = CGRect(
                x: cellRect.midX - iconDisplaySize / 2,
                y: cellRect.midY - iconDisplaySize / 2 - 6,
                width: iconDisplaySize, height: iconDisplaySize)
            ctx.saveGState()
            ctx.interpolationQuality = .none
            compositeImage(ctx, icon, in: iconRect)
            ctx.restoreGState()

            let captionColor =
                row.isDark
                ? CGColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1)
                : CGColor(srgbRed: 0.3, green: 0.3, blue: 0.33, alpha: 1)
            let caption = try renderTextImage("\(size)px", fontSize: 12, color: captionColor)
            let capX = cellRect.midX - CGFloat(caption.width) / 2
            let capY = cellRect.maxY - CGFloat(caption.height) - 6
            compositeImage(
                ctx, caption,
                in: CGRect(x: capX, y: capY, width: CGFloat(caption.width), height: CGFloat(caption.height)))
        }
    }

    // MARK: 像素级检查行（round 0021 二次修订新增）
    //
    // 用户验收要求："regenerate 之后放大实际写出的 16x16/32x32 文件（最近邻，不是平滑插值）
    // 看一眼，不能自己凭意图判定"——上面 5 列的对照表格子本来就已经是原生栅格化 + 最近邻贴图
    // （见上面注释），但格子里的图标只有 ~118px 显示尺寸、边界之间没有网格线，肉眼数不清
    // 究竟是几个像素、边缘是不是硬边。这里单独加一行，把实际入库的 16px/32px 文件按用户
    // 要求的 8x 放大、叠像素网格线，浅/深底（深底是模拟 template 反色，非入库资产）各一份，
    // 一共 4 格，可以数格子核对。
    let checkSectionTop = gridSectionBottom + 26
    let checkTitle = try renderTextImage(
        "像素级检查：MenuBarIconTemplate 实际文件，最近邻放大 8x，网格线标出像素边界（非入库资产的格子已注明）",
        fontSize: 14, color: CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1), bold: true)
    compositeImage(
        ctx, checkTitle,
        in: CGRect(
            x: leftMargin, y: checkSectionTop, width: CGFloat(checkTitle.width),
            height: CGFloat(checkTitle.height)))

    struct PixelCheckCell {
        let caption: String
        let isDark: Bool
        let image: CGImage
    }
    let magnifyFactor = 8
    let gridColorOnLight = CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 0.35)
    let gridColorOnDark = CGColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 0.35)
    let small16Black = try renderB1SilhouetteSmall16(fillColor: iconBlack)
    let small16White = try renderB1SilhouetteSmall16(fillColor: iconWhite)
    let shared32Black = try renderB1Silhouette(pixelSize: 32, fillColor: iconBlack)
    let shared32White = try renderB1Silhouette(pixelSize: 32, fillColor: iconWhite)
    let checkCells = [
        PixelCheckCell(
            caption: "16px · 黑（入库资产原样）", isDark: false,
            image: try magnifyWithPixelGrid(small16Black, factor: magnifyFactor, gridColor: gridColorOnLight)),
        PixelCheckCell(
            caption: "16px · 白（模拟深色反色，非入库）", isDark: true,
            image: try magnifyWithPixelGrid(small16White, factor: magnifyFactor, gridColor: gridColorOnDark)),
        PixelCheckCell(
            caption: "32px · 黑（入库资产原样）", isDark: false,
            image: try magnifyWithPixelGrid(shared32Black, factor: magnifyFactor, gridColor: gridColorOnLight)),
        PixelCheckCell(
            caption: "32px · 白（模拟深色反色，非入库）", isDark: true,
            image: try magnifyWithPixelGrid(shared32White, factor: magnifyFactor, gridColor: gridColorOnDark)),
    ]

    // 每格的槽位宽度取"图标宽度"和"说明文字宽度"两者较大值——上面 rowLabelWidth 犯过的
    // 错误（按图标/固定常量留位置，文字比它宽就被下一格的底板盖掉尾巴）这里不重犯：
    // 说明文字和图标一样，也是先渲染出来量了真实宽度才排版。
    let checkCellTop = checkSectionTop + CGFloat(checkTitle.height) + 16
    let checkCaptionHeight: CGFloat = 20
    let checkCaptionColor: (Bool) -> CGColor = { isDark in
        isDark
            ? CGColor(srgbRed: 0.85, green: 0.85, blue: 0.87, alpha: 1)
            : CGColor(srgbRed: 0.3, green: 0.3, blue: 0.33, alpha: 1)
    }
    let checkCaptionImages = try checkCells.map {
        try renderTextImage($0.caption, fontSize: 12, color: checkCaptionColor($0.isDark))
    }
    var checkCellX = leftMargin
    for (index, cell) in checkCells.enumerated() {
        let cellW = CGFloat(cell.image.width)
        let cellH = CGFloat(cell.image.height)
        let captionImg = checkCaptionImages[index]
        let slotWidth = max(cellW, CGFloat(captionImg.width))

        let plateRect = CGRect(
            x: checkCellX - 10, y: checkCellTop - 10, width: slotWidth + 20,
            height: cellH + 20 + checkCaptionHeight)
        let plateColor =
            cell.isDark
            ? CGColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        ctx.setFillColor(plateColor)
        let platePath = CGPath(roundedRect: plateRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(platePath)
        ctx.fillPath()

        compositeImage(
            ctx, cell.image,
            in: CGRect(x: checkCellX, y: checkCellTop, width: cellW, height: cellH))

        compositeImage(
            ctx, captionImg,
            in: CGRect(
                x: checkCellX, y: checkCellTop + cellH + 6, width: CGFloat(captionImg.width),
                height: CGFloat(captionImg.height)))

        checkCellX += slotWidth + 40
    }

    guard let image = ctx.makeImage() else {
        throw IconGenError.imageCreationFailed("contact sheet")
    }
    return image
}
