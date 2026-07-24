// 独立可执行入口——跟 app/kernel-client/swift/FrameReplayTestMain.swift 同一惯例：这个项目没有
// SwiftPM/XCTest target，`@main` + `static func main() async` 是『纯 swiftc 编译一个可执行文件』
// 风格下驱动 async 代码的标准做法。
//
// 编译命令（含 D2 生成产物 + DiscriminatedUnions + KernelClient 四件套 + 本 runner 三个文件，
// 不含 app/kernel-client/swift/main.swift/CLIRunner.swift/FrameReplayTest*.swift）：
//
//   swiftc app/generated/swift/D2.swift app/generated/swift/DiscriminatedUnions.swift \
//          app/kernel-client/swift/KernelClient.swift app/kernel-client/swift/OpenclawWire.swift \
//          app/kernel-client/swift/EventMapping.swift \
//          app/kernel-client/swift/OpenclawGatewayKernelClient.swift \
//          app/contracts/d2/fixtures/swift-runner/FixtureDSL.swift \
//          app/contracts/d2/fixtures/swift-runner/PartialMatch.swift \
//          app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift \
//          app/contracts/d2/fixtures/swift-runner/SwiftRunnerMain.swift \
//          -o <output>/swift-fixture-runner
//
// 用法：`<output>/swift-fixture-runner [fixture.json ...]`——不带参数时跑下方 `defaultFixturePaths()`
// 枚举的默认清单（三组新增 fixture + 已有的 basic/operation-outcome 两个 SG-1 fixture）。
// 退出码：全部 PASSED 且无 DEGRADED 之外的失败为 0，任意一条 FAILED 为 1（DEGRADED 不计入失败）。

import Foundation

func defaultFixturePaths() -> [String] {
    let swiftRunnerDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fixturesDir = swiftRunnerDir.deletingLastPathComponent()
    let relativePaths = [
        "basic/create-session-subscribe-message-delta.json",
        "operation-outcome/soft-steer-then-stop.json",
        "operation-outcome/stop-no-active-run-succeeded.json",
        "operation-outcome/stop-active-run-succeeded.json",
        "operation-outcome/stop-timed-out.json",
        "operation-outcome/stop-rejected-rpc-failure.json",
        "operation-outcome/stop-transport-closed-aborted-effect-unknown.json",
        "session-lock/send-in-flight-send-pending.json",
        "session-lock/send-in-flight-rejects-concurrent-stop.json",
        "session-lock/stop-no-active-run-idle-transitions.json",
        "approval/pending-request-agent-first.json",
        "approval/pending-request-session-first.json",
        "approval/stop-force-denies-pending-approval.json",
    ]
    return relativePaths.map { fixturesDir.appendingPathComponent($0).path }
}

@main
struct SwiftRunnerMain {
    static func main() async {
        let argFixtures = Array(CommandLine.arguments.dropFirst())
        let fixturePaths = argFixtures.isEmpty ? defaultFixturePaths() : argFixtures

        var passedCount = 0
        var failedCount = 0
        var degradedCount = 0

        for path in fixturePaths {
            let result = await runFixtureFile(at: path)
            switch result.outcome {
            case .passed:
                passedCount += 1
                print("[PASS] \(result.name) (\(path))")
            case .failed(let mismatches):
                failedCount += 1
                print("[FAIL] \(result.name) (\(path))")
                for m in mismatches { print("       - \(m)") }
            case .degraded(let reason):
                degradedCount += 1
                print("[DEGRADED] \(result.name) (\(path))")
                print("       原因: \(reason)")
            }
        }

        print("")
        print(
            "=== \(passedCount) PASS / \(failedCount) FAIL / \(degradedCount) DEGRADED " +
            "（共 \(fixturePaths.count) 条 fixture） ==="
        )
        exit(failedCount == 0 ? 0 : 1)
    }
}
