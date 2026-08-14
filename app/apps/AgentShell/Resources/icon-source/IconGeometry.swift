import CoreGraphics

// AgentShell app-icon 几何定义 —— round 0021 「熊」标两方向共用同一套比例。
//
// 坐标系：100x100，y 向下（和给定设计稿一致的 SVG 习惯），不是 Core Graphics 默认的 y 向上。
// IconRenderer.swift 里为每张位图建 context 时会显式做一次翻转（见 makeBitmapContext），
// 所以这里的每一个坐标都可以直接照抄设计稿数字，不需要再手工反着算 y。
//
// 两个方向共享 ears + head + muzzle 位置这套"熊的比例"（决策文档原话："两个 mark，共享同一只熊
// 的比例"），只是 A1（Dock/Finder，见 IconRenderer.renderA1Tile）把 muzzle 并进外轮廓、
// 用 nose+eyes 两个"洞"露出底下的渐变色磁贴；B1（菜单栏，见 IconRenderer.renderB1Silhouette）
// 只用 ears+head 做轮廓、用眼睛+口鼻三个"洞"露出透明背景，是 template image。
// 两者的"洞"位置/半径并不完全相同（B1 的洞更大、口鼻洞位置更低），照抄设计稿分别列出，
// 不共用一套数字。
enum BearGeometry {

    // MARK: - 耳朵（A1、B1 共用）

    static let earRadius: CGFloat = 14
    static let earLeftCenter = CGPoint(x: 26, y: 33)
    static let earRightCenter = CGPoint(x: 74, y: 33)

    // MARK: - 头部轮廓（A1、B1 共用）
    //
    // 原始 SVG 路径：
    //   M50 87 C31 87 19 74 19 57 C19 41 32 31 50 31 C68 31 81 41 81 57 C81 74 69 87 50 87 Z
    // 四段三次贝塞尔，从底部中点出发逆时针（在 y-down 坐标系里视觉上是绕圈一周）回到起点。

    static func headPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 50, y: 87))
        path.addCurve(
            to: CGPoint(x: 19, y: 57),
            control1: CGPoint(x: 31, y: 87), control2: CGPoint(x: 19, y: 74))
        path.addCurve(
            to: CGPoint(x: 50, y: 31),
            control1: CGPoint(x: 19, y: 41), control2: CGPoint(x: 32, y: 31))
        path.addCurve(
            to: CGPoint(x: 81, y: 57),
            control1: CGPoint(x: 68, y: 31), control2: CGPoint(x: 81, y: 41))
        path.addCurve(
            to: CGPoint(x: 50, y: 87),
            control1: CGPoint(x: 81, y: 74), control2: CGPoint(x: 69, y: 87))
        path.closeSubpath()
        return path
    }

    // MARK: - A1（圆熊，Dock/Finder 磁贴）专用五官
    //
    // muzzle 并入外轮廓（白色实心的一部分，不单独换色——两色熊脸在磁贴尺度上会在 16px 糊成一团，
    // 大块面纯色轮廓反而更接近决策文档点名参照的 DeepSeek 鲸鱼那种极简高辨识度）。
    // nose + eyes 挖空露出磁贴渐变色，而不是像设计稿字面写的那样也填白——
    // 白底上叠白色的 nose/eyes 在视觉上等于没画（两者同色、没有对比度），
    // 挖空能让五官在 128px/256px 预览时读出来，16px 时孔洞本身会被抗锯齿糊掉、
    // 退化成接近纯色轮廓，两种尺度各自都成立。这处偏离设计稿字面描述在任务报告里已如实说明。
    static let muzzleCenter = CGPoint(x: 50, y: 69)
    static let muzzleRX: CGFloat = 15.5
    static let muzzleRY: CGFloat = 11.5

    static let noseCenter = CGPoint(x: 50, y: 62.5)
    static let noseRX: CGFloat = 5.2
    static let noseRY: CGFloat = 4

    static let eyeRadiusA1: CGFloat = 3.6
    static let eyeLeftCenterA1 = CGPoint(x: 38, y: 53)
    static let eyeRightCenterA1 = CGPoint(x: 62, y: 53)

    /// 绕任意定点 (cx,cy) 缩放——x/y 分开给中心点，而不是像最初那版只接受一个共用的 `c`，
    /// 是因为熊的轮廓包围盒本身左右对称（x 中心正好是 50）但上下不对称（耳朵顶到 y=19，
    /// 下巴到 y=87，中心在 53 不是 50）：round 0021 三修（用户要求"撑满尺寸，边缘残缺是
    /// 设计"）把 A1/B1 都从"留白"改成"主动放大到可能出血"，如果还绕 (50,50) 缩放，
    /// 上下出血量会明显不对称（下巴比耳朵先超出画布一大截）,看起来像是"画歪了"而不是
    /// "特意裁切"——绕熊自己包围盒的纵向中心 (50,53) 缩放，出血量上下基本对称，
    /// 读出来才是用户要的"自信的对称裁切"而不是"没算好越界了"。
    /// 写成显式矩阵而不是链式 `.scaledBy().translatedBy()`，是因为链式写法的复合顺序容易
    /// 搞反导致熊偏出中心，这里用"绕定点缩放"的标准展开式 p' = C + s*(p-C) 直接算好
    /// a/d/tx/ty，可以从"中心点必须映射到自己"这一个式子直接验证正确性，不依赖记住 API
    /// 复合顺序。
    static func centeredScale(_ s: CGFloat, aboutX cx: CGFloat = 50, aboutY cy: CGFloat = 50)
        -> CGAffineTransform
    {
        CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: cx * (1 - s), ty: cy * (1 - s))
    }

    /// 熊本体（ears+head）包围盒纵向中心——上面 centeredScale 的默认参照点，也是
    /// a1TileScale/b1SharedScale 都用它做 aboutY 的原因（见 centeredScale 文档）。
    static let bearBoundingBoxCenterY: CGFloat = 53

    /// A1 磁贴里的缩放。round 0021 三修前是 0.72（缩小、四周留白）；用户明确要求"熊头实体的
    /// 尺寸要大一点，尝试撑满尺寸，边缘有残缺是一种设计思路"——改成 1.47（放大、允许出血）。
    /// 具体数值来自实测対比（渲染 0.72/1.0/1.25/1.4/1.47/1.55 几档、每档在 256px 输出上
    /// 实看，见任务记录）：1.4 已经能看到耳朵被磁贴圆角"咬"出弧形缺口（效果正确，见
    /// renderA1Tile 对圆角裁切范围的处理）,1.55 出血明显更多、耳朵开始被磁贴上边缘的直线
    /// 部分整个削平；1.47 是两者之间——耳朵出血够醒目、下巴接近但不越过底边，四周出血量
    /// 目测对称，读出来是"自信的裁切"而不是"画超了"。16px/32px 两档也各自实看过
    /// （renderA1Tile 本来就对每个目标像素尺寸原生栅格化，不是画大图缩小），没有出现
    /// 小尺寸下糊成一团的问题——A1 本来就靠抗锯齿+磁贴色块，不像 B1 16px 那样要抠单像素级的
    /// 眼睛/耳朵分离,缩放大小对它的可读性影响小得多。
    static let a1TileScale: CGFloat = 1.47

    /// B1 32px 及以上（`IconRenderer.renderB1Silhouette`，共享几何）的缩放。round 0021
    /// 三修新增——之前这个尺寸档一直是 `transform: .identity`（不缩放，原始 100 单位
    /// 包围盒自带的留白：横向各留 12、纵向顶部留 19/底部留 13）。用户要求两个 mark 都撑满
    /// 尺寸,这里给到 1.47（和 a1TileScale 同一个数值，两个标共享同一套"放大到多满"的判断，
    /// 不是巧合选的两个不同数——见任务记录：0.72→1.47 那组实验里，A1/B1 两边各自试了同一批
    /// 候选缩放值，1.47 在两边都是"出血明显但没有糊/没有过度裁切"的那一档）。B1 没有磁贴，
    /// 出血直接被 16x16/32x32 画布边界裁掉，不需要额外裁剪路径（A1 需要，见
    /// `IconRenderer.renderA1Tile` 里对磁贴圆角 clip 范围的处理）。
    static let b1SharedScale: CGFloat = 1.47

    // MARK: - B1（剪影熊，菜单栏 template image）专用五官洞
    //
    // 决策文档原话："同一只熊的比例……单色剪影，挖空眼睛和口鼻"——B1 不画 muzzle 实体，
    // 而是把它也变成一个洞（口鼻洞），和两个眼洞一起用 even-odd 从 ears+head 的合并轮廓里
    // 挖穿到透明,让底下的菜单栏背景透出来。三个洞互不相交、也都不碰 ears/head 的接缝，
    // 所以 even-odd 和"外轮廓同向 nonzero + 洞反向 nonzero"这两种实现在这三个洞上结果等价
    // ——IconRenderer 实际用的是后者（配合 transparency layer + .clear blend mode），
    // 原因见 IconRenderer.swift 顶部注释：ears 和 head 两个子路径本身有大面积重叠，
    // 字面 even-odd 会在耳朵和头顶接缝处抠出一个新月形缺口，不是决策文档想要的效果。
    static let eyeRadiusB1: CGFloat = 4.2
    static let eyeLeftCenterB1 = CGPoint(x: 39, y: 58.5)
    static let eyeRightCenterB1 = CGPoint(x: 61, y: 58.5)

    static let muzzleHoleCenter = CGPoint(x: 50, y: 74)
    static let muzzleHoleRX: CGFloat = 8.4
    static let muzzleHoleRY: CGFloat = 5.8

    // MARK: - 磁贴（A1 专用背景）

    static let tileCornerRadius: CGFloat = 22
    /// 渐变色 `#6FB7D8 → #2A5D7E`，从上到下（y 向下坐标系里就是 y=0 → y=100）。
    static let tileGradientTop = (r: 0x6F, g: 0xB7, b: 0xD8)
    static let tileGradientBottom = (r: 0x2A, g: 0x5D, b: 0x7E)
}

// MARK: - B1 16px 专版（round 0021 二次修订，用户实拍验收后打回重做）

/// 用户把入库的 16x16 `MenuBarIconTemplate.png` 放大到 256（最近邻，不插值）实看之后判定：
/// 由 `BearGeometry` 的 100x100 几何直接栅格化到 16px 读不出熊——头顶部近乎一条平线、
/// 两侧近乎垂直，读成盾牌/徽章而不是圆头；两耳退化成顶部两个方角缺口，没有"从头部两侧
/// 支棱出去"的圆耳读法；口鼻洞（rx 8.4 ry 5.8 换算到 16px）在这个尺寸反而成了最显眼、
/// 最方正的一块色斑，喧宾夺主；两个眼洞（r=4.2 换算到 16px 约 0.67px）画不出来，
/// 只会糊两三个邻近像素。根因是"一份 100x100 几何直接缩到 16px"——16px 的像素预算
/// （约 12x12 的有效可见区）装不下"头+耳+口鼻+双眼"四个独立可辨的形状，必须做减法，
/// 不是把数值改小就能救。
///
/// 这里是专门在 16x16 像素网格上重新设计的版本——不是把 `BearGeometry` 的 100 单位数字
/// 换算到 16 再抠图，圆心/半径都是直接针对 16x16 网格试出来的（过程见任务记录：渲染了
/// 9 版参数、每版都用 16x 最近邻放大 + 网格线实看，不是凭感觉一次定案）。目标读法用户
/// 原话「一个圆再加两个小圆」——Mickey Mouse 剪影那种经典读法：
///
/// - 耳朵中心特意放到比头部左右边界更靠外（`earDX` > `headR` 到头心的水平投影），
///   这样耳朵在头部两侧真正"支棱"出去，两侧和顶部中央都露出背景，不再是方角缺口。
/// - 口鼻洞整个去掉——16px 装不下还占最显眼位置的部件，去掉比留着糊成一块方斑更干净。
/// - 两只眼睛保留：圆心刻意落在非整数网格坐标、半径给到刚好覆盖一个像素中心，配合
///   `renderB1SilhouetteSmall16` 关闭抗锯齿的硬边光栅化，实测（放大检查）每只眼睛精确
///   对应一个干净的整像素、互不粘连——按"能做到干净就留、留不干净就去掉"的标准留下，
///   不是无条件让步给细节。
///
/// 32px 及以上仍然复用共享的 `BearGeometry`（`IconRenderer.renderB1Silhouette(pixelSize:)`）——
/// 对照表新增的 8x 硬边放大检查行证实 32px 下头/耳/眼/口鼻四个部件都读得清楚，不需要专版；
/// 64px 以上更宽裕，同样不动。
///
/// **round 0021 三修**：用户看过实拍确认第二版（下面这些数字原来的样子）"读出来是熊"之后，
/// 提出新方向——"熊头实体的尺寸要大一点，尝试撑满尺寸，边缘有残缺是一种设计思路"，
/// 两个标都要撑满、允许出血，不是缺陷。这里的数字整体调大了一档（headR 4.7→5.7、
/// earR 2.1→2.4、earCY 3.3→2.4），效果：
///
/// - 耳朵顶部精确落在 y=0（触边）、左右各出血约 0.1 单位（对称，两侧一致）。
/// - 下巴（头底部）落在 y≈16.1，出血约 0.1 单位——和耳朵的出血量基本对齐，
///   不是"一边撑爆一边留白"的失衡效果。
/// - 耳朵依然明显比头部"支棱"更宽（earDX 5.7 仍然大于 headR 5.7 到头心的水平投影），
///   round 0021 二修确立的"耳朵是独立圆、不是方角缺口"这条没有被这次放大牺牲掉——
///   实测放大 16x 检查过，耳朵内侧和头部之间依然有清楚的豁口,不会因为整体变大就重新
///   糊回方角缺口（这正是二修抓出来的失败模式，三修没有重犯）。
/// - 两只眼睛半径保持 0.5 不变——试过 0.6，16px 硬边光栅化下和 0.5 输出的像素完全一样
///   （像素中心测试对这点小数变化不敏感），没必要为了"看起来该配合头变大"而改一个
///   实际不影响输出的数字。
///
/// 完整候选对比（当前值 vs 三档递增）见任务记录；决策依据是 16x 最近邻放大 + 网格线实看，
/// 外加在模拟浅色菜单栏背景上的真实尺寸（不放大）单独确认过依然可读，不是只看放大图。
enum BearGeometrySmall16 {
    static let headCenter = CGPoint(x: 8, y: 10.4)
    static let headR: CGFloat = 5.7
    static let earR: CGFloat = 2.4
    /// 耳心到头心的水平距离——刻意大于 headR，让耳朵露出头部轮廓之外（见上方说明）。
    static let earDX: CGFloat = 5.7
    static let earCY: CGFloat = 2.4
    static let eyeR: CGFloat = 0.5
    static let eyeDX: CGFloat = 2.2
    /// 相对 headCenter.y 的偏移（0 = 与头心同高）。
    static let eyeDY: CGFloat = 0.0
}
