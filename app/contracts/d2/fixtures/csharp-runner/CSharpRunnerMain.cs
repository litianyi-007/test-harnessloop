// SG-8.7 Stage B：独立可执行入口——镜像 ../swift-runner/SwiftRunnerMain.swift（同款『不带 SwiftPM/
// XCTest，直接编译一个可执行文件』风格，C# 侧对应用 `dotnet run`/`dotnet build` 驱动一个 Exe 项目，见
// CSharpRunner.csproj）。
//
// 用法：`dotnet run --project app/contracts/d2/fixtures/csharp-runner -- [fixture.json ...]`——不带
// 参数时跑下方 `DefaultFixturePaths()` 枚举的默认清单（与 ts-runner/runner.ts、swift-runner 的默认
// 清单逐条对齐：basic 1 + operation-outcome 6 + session-lock 3 + approval 3 = 13 条）。
// 退出码：全部 PASSED 且无 DEGRADED 之外的失败为 0，任意一条 FAILED 为 1（DEGRADED 不计入失败）。

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace CSharpRunner
{
    public static class CSharpRunnerMain
    {
        /// <summary>用 `[CallerFilePath]` 捕获本文件的编译期绝对路径——对应 Swift 侧 `#filePath` 的
        /// 同款技巧，让默认 fixture 清单的路径解析不依赖 `dotnet run`/`dotnet build` 的工作目录或
        /// bin/ 输出目录布局。</summary>
        private static string ThisFilePath([System.Runtime.CompilerServices.CallerFilePath] string path = "") => path;

        private static List<string> DefaultFixturePaths()
        {
            var runnerDir = Path.GetDirectoryName(ThisFilePath())!; // .../fixtures/csharp-runner
            var fixturesDir = Path.GetDirectoryName(runnerDir)!; // .../fixtures
            var relativePaths = new[]
            {
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
            };
            return relativePaths.Select(p => Path.Combine(fixturesDir, p)).ToList();
        }

        public static async Task<int> Main(string[] args)
        {
            var fixturePaths = args.Length > 0 ? args.ToList() : DefaultFixturePaths();

            var passedCount = 0;
            var failedCount = 0;
            var degradedCount = 0;

            foreach (var path in fixturePaths)
            {
                var result = await CSharpFixtureRunner.RunFixtureFileAsync(path);
                switch (result.Outcome)
                {
                    case FixtureRunOutcomeKind.Passed:
                        passedCount++;
                        Console.WriteLine($"[PASS] {result.Name} ({path})");
                        break;
                    case FixtureRunOutcomeKind.Failed:
                        failedCount++;
                        Console.WriteLine($"[FAIL] {result.Name} ({path})");
                        foreach (var m in result.Mismatches) Console.WriteLine($"       - {m}");
                        break;
                    case FixtureRunOutcomeKind.Degraded:
                        degradedCount++;
                        Console.WriteLine($"[DEGRADED] {result.Name} ({path})");
                        Console.WriteLine($"       原因: {result.DegradedReason}");
                        break;
                }
            }

            Console.WriteLine();
            Console.WriteLine(
                $"=== {passedCount} PASS / {failedCount} FAIL / {degradedCount} DEGRADED （共 {fixturePaths.Count} 条 fixture） ===");
            return failedCount == 0 ? 0 : 1;
        }
    }
}
