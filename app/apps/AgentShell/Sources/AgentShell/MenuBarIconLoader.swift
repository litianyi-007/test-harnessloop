// rounds/0021 Scope-Lock 修订 v1 -> v2（2026-08-14）：给已经生成、已经随包发布、但此前没有任何代码
// 加载过的 `MenuBarIconTemplate.png`/`@2x`（Resources/icon-source/main.swift 头注释原话："实际调用
// NSImage(named:) 那一行由后续负责菜单栏 UI 的改动去写"）找一个真正的宿主。本文件就是那一行。
//
// ## 两条启动路径,两套 Bundle.main 形状（已用独立探针实测,不是假设）
//
// 本壳一直存在"既可能以裸 SwiftPM 可执行文件运行,也可能以 build-app-bundle.sh 拼出的 .app 运行"这条
// 既定双路径（先例：SessionPersistence.swift `bundleIdentifier` 的文档注释）。这两条路径下
// `Bundle.main` 指向完全不同的目录形状：
//   - `.app` 启动：`Bundle.main.bundleURL` 是 `AgentShell.app/`,`Contents/Resources/` 下有
//     `Info.plist`（build-app-bundle.sh 拷贝的）与两张图标 PNG（同一脚本拷贝）。
//   - 裸二进制启动（`swift build` 产物,`.build/arm64-apple-macosx/debug/AgentShell`）：
//     **`app/Package.swift` 的 `AgentShell` target 没有声明 `resources:`**（已读源码确认,本文件所在
//     改动禁止触碰 `Package.swift`,这个事实无法通过加 `resources:` 绕开）——SwiftPM 因此完全不会把
//     `Resources/` 拷进 `.build` 产物目录。用一个临时探针二进制放进真实的
//     `app/.build/arm64-apple-macosx/debug/` 目录、原地跑起来实测过：`Bundle.main.bundlePath` ==
//     `Bundle.main.resourcePath` == 该目录本身（没有 `Contents/Resources` 这一层）,`Bundle.main.url(
//     forResource:withExtension:)` 对 `MenuBarIconTemplate` 返回 `nil`——这条路径下资源确实找不到,
//     不是猜测。
//
// ## 一个已经实测撞到的坑：绝不能在 `Bundle.main` 单例上直接调 `.image(forResource:)`
//
// 同一次探针实测：在裸二进制那套目录形状下,`Bundle.main.image(forResource:)`
// **直接抛出未捕获的 Objective-C 异常并让整个进程崩溃**——
// `-[NSBundle imageForResource:]: unrecognized selector sent to instance`（`NSImage(named:)`
// 换个 API 试则不崩,只是正常返回 nil）。用同一个路径重新包一层
// `Bundle(url: Bundle.main.bundleURL)` 后再调 `.image(forResource:)` 就不崩、正常返回 nil——两次
// 探针里 `type(of:)` 都报告是 `NSBundle`,问题不在类型本身,而是这个特定单例在这套目录形状下对这一个
// selector 的响应有问题（成因不确定,不重要——重要的是它可复现,规避方法也已经验证有效）。因此本文件
// **全程不直接调用 `Bundle.main.image(forResource:)` 或 `NSImage(named:)`**,统一改为对一个显式构造的
// `Bundle(url:)` 实例调用同一个方法——用真实探针验证过的安全写法,不是绕开一个从未发生过的假想问题。
//
// ## `Bundle(url:).image(forResource:)` 对"Template"文件名后缀 + 平铺 @1x/@2x 的实际行为（已实测,
// 不是沿用 icon-source/main.swift 里那句注释的字面断言）
//
// 用独立探针分别验证过（对同一份真实 `MenuBarIconTemplate.png`/`@2x` 字节,分别测试三种目录形状：
// 裸平铺目录、真实 `.app` 形状的 `Contents/Resources`、以及去掉"Template"后缀的对照组）：
//   1. 平铺目录（没有 `Contents/Resources` 这一层,就是 `Resources/` 本来的样子）与 `.app` 形状,两者
//      通过 `Bundle(url:).image(forResource: "MenuBarIconTemplate")` 加载的结果**完全一致**：
//      `isTemplate == true`,`representations.count == 2`（16x16 与 32x32 两个 `NSBitmapImageRep`
//      都在,`@2x` 文件被自动识别、合并进同一个 `NSImage`,不需要手工再拼一次)。
//   2. 对照组：把同一份文件内容换成不带"Template"后缀的文件名（如 `MenuBarIconPlain.png`）,用**全新
//      进程 + 全新目录**重新跑一遍同一个 API（避免 `NSBundle` 对同一路径的实例级缓存污染对照结果——
//      第一次探针曾在"复用已经访问过的目录"时把这一步跑出误导性的 `nil`,换新目录/新进程后行为
//      稳定复现）：@2x 合并依然发生（`representations.count == 2`,与文件名无关）,但
//      `isTemplate == false`。两相对照,坐实"Template"后缀确实是 `isTemplate` 自动置真的唯一变量。
// 结论：`icon-source/main.swift` 那句注释里"文件名以 Template 结尾,AppKit 会自动置真 isTemplate"
// 对 `Bundle(url:).image(forResource:)` 这条加载路径成立——但本文件**仍然**在加载成功后显式再置一次
// `isTemplate = true`（见下方 `load()`）,不单纯依赖这条约定：这是任务书明确要求的写法（"Confirm
// isTemplate is genuinely true... If it isn't, set it explicitly"）,而且显式赋值的成本是一行代码,
// 换来的是"即便未来某个系统版本收紧/改变这条从未有正式文档保证的约定,本壳也不受影响"。

import AppKit
import Foundation

public enum MenuBarIconLoader {
    /// 惰性求值一次、缓存进程生命周期——`AgentShellApp.body` 每次任意 `@Observable` 状态变化都会
    /// 重新求值（`store`/`appearance` 几乎每个事件 delta 都会变),菜单栏图标不应该跟着重复走一遍
    /// 目录探测 + 文件 I/O + 图像解码。`static let` 是 Swift 里"恰好求值一次、线程安全"的标准写法。
    public static let templateImage: NSImage? = load()

    private static func load() -> NSImage? {
        for directory in candidateResourceDirectories() {
            guard let bundle = Bundle(url: directory) else { continue }
            if let image = bundle.image(forResource: "MenuBarIconTemplate") {
                // 显式再置一次——理由见本文件头注释最后一段。即便这一行此刻是"重复设置一个已经是
                // true 的值",保留它不是无意义的仪式,是任务书明确要求、且防御未来行为漂移的一行。
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    /// 按优先级排列的候选资源目录：
    ///   1. `Bundle.main.bundleURL`——`.app` 启动时这是 bundle 根目录,`Bundle(url:).image(
    ///      forResource:)` 会自动向下找 `Contents/Resources/`（已实测,见头注释探针 3）。裸二进制
    ///      启动时这是 `.build/arm64-apple-macosx/<config>/`——图片不在那里,这一步会自然落空、
    ///      不崩溃（见头注释踩坑记录),继续尝试下一个候选。
    ///   2. 从可执行文件路径向上走、找到 SwiftPM 包根（`app/`）后拼出源码 `Resources/` 目录——只有
    ///      裸二进制启动才会走到这一步（第 1 步已经能覆盖 `.app` 启动)。这不是"猜"：SwiftPM 的
    ///      产物目录形状是固定约定（`<package>/.build/<triple>/<config>/<executable>`),`app/`
    ///      本身在这条链路上的相对位置是结构性稳定的,不随 debug/release、也不随
    ///      `.build/debug`（符号链接到 `arm64-apple-macosx/debug`）这类路径别名而改变——两种情形下
    ///      只是需要向上走的层数不同,循环本身不关心具体层数,只要求存在性检查命中就停。
    private static func candidateResourceDirectories() -> [URL] {
        var directories: [URL] = [Bundle.main.bundleURL]

        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var probe = executableURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        for _ in 0..<8 {
            let candidate = probe.appendingPathComponent("apps/AgentShell/Resources", isDirectory: true)
            let markerFile = candidate.appendingPathComponent("MenuBarIconTemplate.png")
            if fileManager.fileExists(atPath: markerFile.path) {
                directories.append(candidate)
                break
            }
            let parent = probe.deletingLastPathComponent()
            if parent == probe { break } // 到达文件系统根,不再继续
            probe = parent
        }
        return directories
    }
}
