// AgentShell 图标生成器入口 —— round 0021。
//
// 用法： generate-icons <输出目录>
// 产出（写在 <输出目录> 下,由 generate-icons.sh 负责后续 iconutil 转换与落盘到 Resources/）：
//   AppIcon.iconset/icon_*.png   —— 10 张标准 iconset 命名的 PNG（A1,磁贴+白色熊身）
//   MenuBarIconTemplate.png      —— 16x16,纯黑+alpha（B1,菜单栏 template image）
//   MenuBarIconTemplate@2x.png   —— 32x32,同上
//   icon-contact-sheet.png       —— A1/B1 在 16/32/64/128/256、浅/深底下的对照表
//
// 裸 swiftc 编译（不是 SwiftPM target），入口文件按惯例叫 main.swift,和
// app/kernel-client/swift/cli/main.swift 同一约定。

import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("generate-icons: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: generate-icons <output-dir>")
}
let outputDir = URL(fileURLWithPath: arguments[1], isDirectory: true)

do {
    let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    // 标准 macOS iconset 命名（iconutil 认这个约定）。7 个不同像素尺寸对应 10 个文件名——
    // 16@2x 和 32@1x 都是 32px、128@2x 和 256@1x 都是 256px、256@2x 和 512@1x 都是 512px,
    // 按尺寸缓存渲染结果,不用重复画。
    let iconsetEntries: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    var renderedBySize: [Int: CGImage] = [:]
    for (name, px) in iconsetEntries {
        let image: CGImage
        if let cached = renderedBySize[px] {
            image = cached
        } else {
            image = try renderA1Tile(pixelSize: px)
            renderedBySize[px] = image
        }
        let fileURL = iconsetDir.appendingPathComponent("\(name).png")
        try writePNG(image, to: fileURL)
        print("wrote \(fileURL.lastPathComponent) (\(px)x\(px) px)")
    }

    // 菜单栏 template PNG：纯黑 + alpha,文件名以 "Template" 结尾——AppKit 对这个命名约定
    // 会自动把 isTemplate 置真（Sources/ 不在本任务范围内,实际调用 NSImage(named:) 那一行
    // 由后续负责菜单栏 UI 的改动去写；这里只保证资产本身符合约定、随 bundle 一起落地）。
    //
    // 16px 用专版渲染器，不是共享几何缩小——用户把第一版 16px 实拍放大后判定读不出熊
    // （头顶太平、耳朵是方角缺口、口鼻洞在这个尺寸反而最显眼、眼睛洞画不出来只糊像素），
    // 完整实测记录见 IconGeometry.swift 的 BearGeometrySmall16 与 IconRenderer.swift 的
    // renderB1SilhouetteSmall16 文档注释。
    let menuBar16 = try renderB1SilhouetteSmall16(fillColor: iconBlack)
    try writePNG(menuBar16, to: outputDir.appendingPathComponent("MenuBarIconTemplate.png"))
    print("wrote MenuBarIconTemplate.png (16x16 px, dedicated pixel-grid design)")

    // 32px 判过：用户实拍验收（8x 硬边放大 + 网格线检查）确认共享几何在这个尺寸下
    // 头/耳/眼/口鼻四个部件都读得清楚，不需要专版，继续用 renderB1Silhouette。
    let menuBar32 = try renderB1Silhouette(pixelSize: 32, fillColor: iconBlack)
    try writePNG(menuBar32, to: outputDir.appendingPathComponent("MenuBarIconTemplate@2x.png"))
    print("wrote MenuBarIconTemplate@2x.png (32x32 px, shared geometry)")

    let sheet = try renderContactSheet()
    try writePNG(sheet, to: outputDir.appendingPathComponent("icon-contact-sheet.png"))
    print("wrote icon-contact-sheet.png (\(sheet.width)x\(sheet.height) px)")

} catch {
    fail("\(error)")
}
