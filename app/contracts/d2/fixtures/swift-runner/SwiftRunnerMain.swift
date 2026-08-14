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
// 退出码：全部 PASSED 且无 DEGRADED 之外的失败为 0，任意一条 FAILED 为 1（DEGRADED 不计入失败——
// rounds/0022 起这一点没变，但摘要末尾新增的「覆盖判定」区块让 DEGRADED 不再是『不计入失败且无人
// 可见』：一眼能看到本端真正执行了哪些 fixture、跳过了哪些、为什么。**这份摘要完全按这次运行的真实
// 结果（PASS/FAIL/DEGRADED）筛选要点名的 fixture，不引用任何方法名单**——2026-08-14 复核发现初版在
// 这里也硬编码了一份 `["interrupt","respondApproval","capabilities"]`（只用于决定摘要里点名哪些
// fixture，不影响 PASS/FAIL/DEGRADED 判定本身，但仍是同一种「新增一个方法、名单不会跟着更新」的
// 陈旧风险），已改为按结果筛选：新实现一个方法、它的 fixture 从 DEGRADED/FAIL 变回 PASS 后，摘要会
// 自动不再点名它，没有名单需要维护，也就没有名单会漏改。

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
        var results: [FixtureRunResult] = []

        for path in fixturePaths {
            let result = await runFixtureFile(at: path)
            results.append(result)
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

        // --- 覆盖判定（rounds/0022：运行时发现，不是静态方法名单）---
        // 回答 scope-lock 取舍 2 要求的问题：「哪一端覆盖了这条 fixture、哪一端没有，为什么」——完全
        // 按这次运行的真实结果（`result.outcome`）筛选，不引用任何方法名（也不查『哪些方法曾经被
        // 旧名单挡住』这类历史信息）：新增一个方法、它的 fixture 只要不再是 PASS 就会自动出现在下面，
        // 变回 PASS 就自动消失——没有名单要维护，也就没有名单会漏改。
        print("")
        print("--- 覆盖判定（运行时发现：DEGRADED 与否取决于这次真实运行是否捕获到 notImplemented，不查表）---")
        let executedCount = passedCount + failedCount
        print("真实执行并给出 PASS/FAIL 判定：\(executedCount)/\(fixturePaths.count)")
        print("运行时发现 DEGRADED（真实捕获 notImplemented，跳过，不计入 PASS/FAIL）：\(degradedCount)/\(fixturePaths.count)")
        print("")
        print("需要关注的 fixture（本次结果是 FAIL 或 DEGRADED 的，按结果筛选，一个不漏；PASS 的已在上方逐条打印，不重复）：")
        let attention = results.filter { if case .passed = $0.outcome { return false }; return true }
        if attention.isEmpty {
            print("  （无——本次全部真实执行且全部 PASS）")
        } else {
            for result in attention {
                switch result.outcome {
                case .passed:
                    continue
                case .failed:
                    print("  - \(result.name) [FAIL]（明细见上方 [FAIL] 段）")
                case .degraded(let reason):
                    print("  - \(result.name) [DEGRADED] \(reason)")
                }
            }
        }

        exit(failedCount == 0 ? 0 : 1)
    }
}
