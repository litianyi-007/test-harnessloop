# Scope Lock — goal 002 / rounds/0024

**开轮时间**：2026-08-21，**动手之前**写就。用户裁定「0023 返工回来后补 CI」。

## Round Objective

**结束「所有绿都是本机绿」里最危险的两块**：把 `frame-replay-tests` 和 Swift 金标
parity runner 的**现行真实结果**接到 GitHub Actions macos job。一次坏提交会红，
而不是靠人发现。

## 为什么现在做

rounds/0023 把 Swift 金标从「1 FAIL」修成 **13 PASS / 0 FAIL / 0 DEGRADED**，
帧回放 **174/174**。0023 scope-lock 禁止改 `.github/`，所以这两项绿当时接不进去。

CI macos job 现在的 Swift parity 步骤注释仍写「12 PASS + 1 expected DEGRADED」——
那是 0022 之前的账。0022 把判定改成运行时发现之后，那条 fixture 会真实 FAIL
（exit 1）；0023 才把它修绿。注释与期望必须跟上，否则后人会把 13/0/0 读成「还该有一条降级」。

## 本轮做

| # | 改动 | 成功判据 |
|---|---|---|
| 1 | macos job 增加 `swift build --package-path app --product frame-replay-tests` + 跑 `./app/.build/debug/frame-replay-tests` | 该 step 失败即 job 红；本地已是 exit 0 / 174/174 |
| 2 | 同一 job 的 Swift 金标步骤：注释与成功条件改为 **13 PASS / 0 FAIL / 0 DEGRADED，exit 0** | 不改 runner 源码；只改 workflow 文案与（如有）断言 |
| 3 | 可选、便宜：同一 job 先 `swift build --package-path app`（整包可编译），再跑 frame-replay | 失败即红 |

## 本轮不做

- **不改 C# 端期望**——C# 仍是 12 PASS + 1 DEGRADED（interrupt 是桩），那是诚实分歧，0022 红线。
- **不把 hopper 的 ~1424 条测试挂上**——要 checkout `hopper-plugin` submodule，比 Swift 两步重，另开一轮。
- 不改 `app/` 产品代码、不改 fixture JSON、不改三个插件 submodule。
- 不改 ubuntu job 的 TS/C# 链（已在跑）。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `.github/workflows/ci.yml` | 改 | 只加 macos Swift 构建/帧回放步骤，并改 Swift parity 步骤的注释/期望；不放水（无 `continue-on-error`、无 `\|\| true`） |
| `app/kernel-client/swift/frame-replay-tests/FrameReplayTests.swift` | 改 | **仅** `testSubscribeReturnsBeforeServerSubscriptionAckArrives` 的等待/轮询窗口（v2）；不得改产品实现 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0024/` | 写 | 本轮产物 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 若派评审 |

## Disallowed Changes

- `app/**`（含 fixture、runner、kernel-client、apps）
- `kernels/`、三个插件 submodule、`Package.swift`

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| workflow 无 `continue-on-error` / `\|\| true` | 本轮新增步骤 0 处 | `git diff .github/workflows/ci.yml` |
| 本地 frame-replay | 已在 0023 复跑 174/174 exit 0，本轮不重跑产品测试 | `rounds/0023/evidence/99-resume-frame-replay-tests.log` |
| 本地 Swift parity | 已在 0023 复跑 13/0/0 exit 0 | `rounds/0023/evidence/99-resume-parity-runner.log` |
| C# 步骤文案未改成 PASS | 仍允许 1 DEGRADED | diff |
| push 后 macos job | 新增步骤绿；Swift parity 绿 | Actions run URL |

## 红线

- **不得为了让 CI 绿而把 174 写成软断言、或把 FAIL 洗成 DEGRADED。**
- **不得顺手改 app 代码。** CI 是守门，不是修产品的借口。
- **不得 checkout kernels/ 或任何 secret。**

---

## Scope-Lock 修订 v1 → v2（2026-08-21，CI 第一次跑就红）

**扩围一处**：`app/kernel-client/swift/frame-replay-tests/FrameReplayTests.swift`
里 `testSubscribeReturnsBeforeServerSubscriptionAckArrives` 的等待窗口。

Actions run `32474120825`：ubuntu 绿、SwiftPM 整包构建绿、**frame-replay 173/174**。
唯一红的是 rounds/0012 那条「subscribe() 在 ack 前返回」——order=`["subscribe-returned"]`，
RPC ack 在 200ms 窗口内没被记上。测试自己的注释已经写过这个坑：不加足够等待会恒为此形，
**不是顺序反了，是还没来得及发生**。本机 200ms 够，GitHub macos runner 不够。

**扩围的硬边界**：只放宽这条测试的等待/轮询，**不得改 `subscribe()` 产品实现**，
不得动其它测试。CI 红了才允许碰测试，不是预先改产品去迁就 CI。

---

## 异构评审

改动完成后可视情况派只读评审，重点问：①新增步骤是否真能红 ②C# 期望有没有被顺手改掉
③有没有 `continue-on-error` / `|| true`。CI yaml 小、主会话也可自审后收。
