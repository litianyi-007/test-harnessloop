// SG-5 Stage C：parity 测试可执行入口——镜像 ../../swift/FrameReplayTestMain.swift（真正驱动
// runFrameReplayTests() 的可执行文件）。`dotnet run` / `dotnet exec` 这个 Exe 即可跑全部场景，
// exit code 0 表示全过，非 0 表示有失败（供 CI/脚本判定）。

using System.Threading.Tasks;

namespace KernelClient.Tests
{
    public static class Program
    {
        public static async Task<int> Main()
        {
            var allPassed = await FrameReplayTests.RunAsync();
            return allPassed ? 0 : 1;
        }
    }
}
