// 独立的测试可执行文件入口——不跟 CLIRunner.swift/main.swift 混在一起编译（Swift 顶层可执行语句
// 只能出现在一个字面名为 `main.swift` 的文件里；这里改用 `@main` + `static func main() async`，
// 避免与 `app/kernel-client/swift/cli/main.swift`（生产 CLI 入口）同名冲突）。
//
// SG-10 起这是 SwiftPM `frame-replay-tests` executable target（app/Package.swift）的入口，
// 和 FrameReplayTests.swift 同目录、同一个 target——`runFrameReplayTests()` 因此仍是同模块调用，
// 不需要跨模块访问。构建/运行方式：
//
//   swift build --package-path app --product frame-replay-tests
//   ./app/.build/debug/frame-replay-tests
//
// 退出码：全部通过为 0，任意一条 FAIL 为 1（供 CI/脚本判定，不依赖肉眼看 PASS/FAIL 字样）。

import Foundation

@main
struct FrameReplayTestMain {
    static func main() async {
        let allPassed = await runFrameReplayTests()
        exit(allPassed ? 0 : 1)
    }
}
