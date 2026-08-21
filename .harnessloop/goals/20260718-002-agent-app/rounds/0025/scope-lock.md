# Scope Lock — goal 002 / rounds/0025

**开轮时间**：2026-08-22，**动手之前**写就。接 rounds/0024 `Accepted: no` /
feedback `negative`（runtime-recoverable）。用户裁定按建议开本轮。

## Round Objective

**让 macos Actions 上的 `frame-replay-tests` 稳定 174/174。** 只改三条测试的采样方式，
不改产品实现。

## 为什么现在做

0024 把 frame-replay 接进 CI，门立刻红，且两次失败集合不相交：

| run | 结果 | 失败 |
|---|---|---|
| 32474120825 | 173/174 | 仅 0012 固定 200ms（0024 v2 已改轮询，第二次 run 证明修好） |
| 32474519871 | 171/174 | 三条 0023 §9.3 / FAIL2：固定 40–100ms `Task.sleep` 过冲 |

本机 174/174。形状与 0024 v2 相同：固定 sleep 去采一个一两百毫秒的窗口，
GitHub macos runner 上过冲。

## 三条与修法

| # | 测试 | CI 所见 | 修法 |
|---|---|---|---|
| 1 | `InterruptTests.testSendRejectedButStopWaitsThenProceedsWhileInterruptInFlight` | 采锁时已是 `stop_in_progress` | 发射 stop 后有界轮询，**一看到** `interrupt_in_progress` 且 stop 未报告就采样，不再先睡 60ms |
| 2 | `SteerTests.testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted` | 同上 | 同上 |
| 3 | `SteerTests.testConcurrentSendCannotStealLockDuringAtomicInterruptToStopHandoff` | 第三方 send 得到 `unknown session` 而非 `session_locked` | **真牙齿仍是 `sessions.send#2` 未被 dispatch**。`unknown session` 是 stop 先跑完 delete 的合法后续，不是偷锁；断言放宽为「未成功、且未派发 #2」 |

## 本轮不做

- 不改 `OpenclawGatewayKernelClient` / `stop()` / `interrupt()` / `subscribe()`。
- 不 skip、不 `continue-on-error`、不加测试重试洗绿。
- 不改 `.github/workflows/ci.yml`（门已经接上，本轮是让它稳）。
- 不改 C#、fixture JSON、三个插件 submodule。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/kernel-client/swift/frame-replay-tests/InterruptTests.swift` | 改 | 仅测试 #1 的采样 + 可被同 target 共用的轮询小函数 |
| `app/kernel-client/swift/frame-replay-tests/SteerTests.swift` | 改 | 仅测试 #2 的采样与测试 #3 的第三方错误断言 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0025/` | 写 | 本轮产物 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 开轮/收盘 |
| `.hopper/queue.md` | 写 | 若派评审 |

## Disallowed Changes

- `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` 及任何产品实现
- `.github/workflows/ci.yml`、`app/contracts/**`、`app/kernel-client/csharp/`、`kernels/`、三个插件 submodule、`Package.swift`

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 本机 frame-replay | 174/174 exit 0 | `evidence/` 跑测日志 |
| 产品实现未动 | `git diff --stat -- app/kernel-client/swift/OpenclawGatewayKernelClient.swift` 为空 | — |
| push 后 macos `frame-replay-tests` | exit 0 | Actions run URL |
| 无 skip / 无 continue-on-error | diff 不含 | — |

## 红线

- **不得 skip 这三条，不得给 CI step 加 retry。**
- **不得改产品实现来迁就测试窗口。**
- **FAIL2 的 `sessions.send#2` 未 dispatch 断言不得删。** 那才是「没偷到锁」。

## 异构评审

CI yaml 本轮未改。测试改动小，主会话对照 0024 两次失败日志自审即可；不强制派 hopper。
