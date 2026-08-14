// SG-8.7 Stage B：独立可执行入口——镜像 ../swift-runner/SwiftRunnerMain.swift（同款『不带 SwiftPM/
// XCTest，直接编译一个可执行文件』风格，C# 侧对应用 `dotnet run`/`dotnet build` 驱动一个 Exe 项目，见
// CSharpRunner.csproj）。
//
// 用法：`dotnet run --project app/contracts/d2/fixtures/csharp-runner -- [fixture.json ...]`——不带
// 参数时跑下方 `DefaultFixturePaths()` 枚举的默认清单（与 ts-runner/runner.ts、swift-runner 的默认
// 清单逐条对齐：basic 1 + operation-outcome 6 + session-lock 3 + approval 3 = 13 条）。
// 退出码：全部 PASSED 且无 DEGRADED 之外的失败为 0，任意一条 FAILED 为 1（DEGRADED 不计入失败——
// rounds/0022 起这一点没变，但摘要末尾新增的「覆盖判定」区块让 DEGRADED 不再是『不计入失败且无人
// 可见』：一眼能看到本端真正执行了哪些 fixture、跳过了哪些、为什么。**这份摘要完全按这次运行的真实
// 结果（PASS/FAIL/DEGRADED）筛选要点名的 fixture，不引用任何方法名单**——2026-08-14 复核发现初版在
// 这里也硬编码了一份 `["interrupt","respondApproval","capabilities"]`（只用于决定摘要里点名哪些
// fixture，不影响 PASS/FAIL/DEGRADED 判定本身，但仍是同一种「新增一个方法、名单不会跟着更新」的
// 陈旧风险），已改为按结果筛选：新实现一个方法、它的 fixture 从 DEGRADED/FAIL 变回 PASS 后，摘要会
// 自动不再点名它，没有名单需要维护，也就没有名单会漏改；这份摘要与 swift-runner 的同名区块逐字段
// 对齐，方便人工对照两端输出直接看出分歧。

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
            var results = new List<FixtureRunResult>();

            foreach (var path in fixturePaths)
            {
                var result = await CSharpFixtureRunner.RunFixtureFileAsync(path);
                results.Add(result);
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

            // --- 覆盖判定（rounds/0022：运行时发现，不是静态方法名单）---
            // 回答 scope-lock 取舍 2 要求的问题：「哪一端覆盖了这条 fixture、哪一端没有，为什么」——
            // 完全按这次运行的真实结果（`result.Outcome`）筛选，不引用任何方法名（也不查『哪些方法
            // 曾经被旧名单挡住』这类历史信息）：新增一个方法、它的 fixture 只要不再是 PASS 就会自动
            // 出现在下面，变回 PASS 就自动消失——没有名单要维护，也就没有名单会漏改。
            Console.WriteLine();
            Console.WriteLine("--- 覆盖判定（运行时发现：DEGRADED 与否取决于这次真实运行是否捕获到 NotImplemented，不查表）---");
            var executedCount = passedCount + failedCount;
            Console.WriteLine($"真实执行并给出 PASS/FAIL 判定：{executedCount}/{fixturePaths.Count}");
            Console.WriteLine($"运行时发现 DEGRADED（真实捕获 NotImplemented，跳过，不计入 PASS/FAIL）：{degradedCount}/{fixturePaths.Count}");
            Console.WriteLine();
            Console.WriteLine("需要关注的 fixture（本次结果是 FAIL 或 DEGRADED 的，按结果筛选，一个不漏；PASS 的已在上方逐条打印，不重复）：");
            var attention = results.Where(r => r.Outcome != FixtureRunOutcomeKind.Passed).ToList();
            if (attention.Count == 0)
            {
                Console.WriteLine("  （无——本次全部真实执行且全部 PASS）");
            }
            else
            {
                foreach (var result in attention)
                {
                    switch (result.Outcome)
                    {
                        case FixtureRunOutcomeKind.Failed:
                            Console.WriteLine($"  - {result.Name} [FAIL]（明细见上方 [FAIL] 段）");
                            break;
                        case FixtureRunOutcomeKind.Degraded:
                            Console.WriteLine($"  - {result.Name} [DEGRADED] {result.DegradedReason}");
                            break;
                    }
                }
            }

            return failedCount == 0 ? 0 : 1;
        }
    }
}
