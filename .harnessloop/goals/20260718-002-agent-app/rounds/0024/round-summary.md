# Round Summary — goal 002 / rounds/0024

**把 frame-replay 接进 CI。门立刻红了，而且两次红的不是同一条——本机绿不是 CI 绿。本轮不接受。**

## 改了什么

macos job 增加 SwiftPM 整包构建与 `frame-replay-tests`。Swift 金标步骤的文案从
「12 + 1 DEGRADED」改为 13/0/0。C# 未动。

v2：0012 subscribe 测试的固定 200ms 等待改成 2s 上限轮询（Actions 32474120825 抓到）。

## 为什么不接受

Actions macos 两次 frame-replay 分别 173/174 与 171/174，失败集合不相交。
剩下三条是 0023 用 40–100ms `Task.sleep` 采样锁窗口的测试，调度一过冲就看到抢占或 unknown session。

## Cost

unavailable: no local transcript source — Grok 会话。
