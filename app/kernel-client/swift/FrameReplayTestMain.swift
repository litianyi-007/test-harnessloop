// 独立的测试可执行文件入口——不跟 CLIRunner.swift/main.swift 混在一起编译（Swift 顶层可执行语句
// 只能出现在一个字面名为 `main.swift` 的文件里；这里改用 `@main` + `static func main() async`，
// 避免与 `app/kernel-client/swift/main.swift`（生产 CLI 入口）同名冲突）。编译命令（只含 D2 生成
// 产物 + EventMapping/OpenclawWire/KernelClient/OpenclawGatewayKernelClient + 本文件 +
// FrameReplayTests.swift，不含 CLIRunner.swift/main.swift）：
//
//   swiftc app/generated/swift/D2.swift app/generated/swift/DiscriminatedUnions.swift \
//          app/kernel-client/swift/KernelClient.swift app/kernel-client/swift/OpenclawWire.swift \
//          app/kernel-client/swift/EventMapping.swift \
//          app/kernel-client/swift/OpenclawGatewayKernelClient.swift \
//          app/kernel-client/swift/FrameReplayTests.swift \
//          app/kernel-client/swift/FrameReplayTestMain.swift \
//          -o <output>/frame-replay-tests
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
