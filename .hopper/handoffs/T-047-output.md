---
phase: done
last_progress_at: "2026-07-24T10:08:56.514Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T10:08:56.513Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 301084
adapter_status: success
---
# T-047 · code-review-adversarial · C# kernel-client parity（commit `3ae6fa81`）

**Task-type**: `code-review-adversarial` · **Vendor**: grok（T-046 codex 中止后异构重派）· 只读  
**评审对象**: `app/kernel-client/csharp/`（对照权威 `app/kernel-client/swift/`）  
**范围外**: 未跑 csi/dotnet-script 交互；已读代码 + 复跑既有 FrameReplay 测试二进制

---

## Summary

对 commit `3ae6fa81` 的 C# Openclaw gateway kernel-client（Stage C，Swift 权威镜像）做了对抗复核，重点压并发移植（actor→`lock`）、parity 测试是否真驱动实现、M1–M6 语义、C# 特有 JSON/Channel/WebSocket 路径与 D2 往返。结论：会话锁 check-and-set 在单 `lock` 内原子完成；await 间隙由 `SessionLockState` 挡住重入；stop 四路径、`operationId` 统一、approval 双向 join、F7 脱敏、M5 清理与 Swift 语义一致。既有测试二进制实测 **25/25 PASS**；测试真调 `SendAsync`/`StopAsync`/`Subscribe`/`TestSupportFeedFrame`，不是常量断言。未发现阻断性 C# 特有回归；有 2 条与 Swift **共享**的潜伏缺陷（transport 打断 stop 等待会挂死 waiter；超时后未标 `TerminalEmitted` 的迟到帧窗口），记为 note，不构成对本 port 的 REWORK。

## Files touched

none（只读评审；本文件为 handoff 产出）

**评审阅读面**（未修改）:

| 路径 | 一句话 |
|------|--------|
| `app/kernel-client/csharp/OpenclawGatewayKernelClient.cs` | 主实现：WS/RPC/会话锁/stop 状态机/approval join |
| `app/kernel-client/csharp/EventMapping.cs` | 9 变体映射 + M2 phase:error |
| `app/kernel-client/csharp/OpenclawWire.cs` | 编解码 + F2 attachment + F7 脱敏 |
| `app/kernel-client/csharp/KernelClientError.cs` | 错误判别 |
| `app/kernel-client/csharp/tests/FrameReplayTests.cs` | 25 条 parity 场景 |
| `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` 等 | 权威对照 |

## Acceptance verification (5/5)

### 1. 并发移植是否 race-free（actor → lock）— **PASS（附共享潜伏 note）**

**核验**:

| 点 | 证据 |
|----|------|
| 会话锁 check-and-set 原子 | `SendAsync`/`StopAsync` 在**同一** `lock (_sync)` 内读 `SessionLockState` 并写入 `SendPending`/`StopInProgress`：`OpenclawGatewayKernelClient.cs:236-247`、`345-356` |
| await 间隙不可被并发 send/stop 重入 | 非 `Idle` 抛 `session_locked`（`242-244`、`351-353`）；`finally` 仅在仍为 `SendPending` 时释放（`287-291`） |
| 临界区不跨 await | 文件头契约 `L7-9`；字典读写均为短 `lock`，`await RequestAsync`/`WaitForPendingStopTerminalAsync` 在锁外 |
| pendingStop TCS 单次完成 | `WaitForPendingStopTerminalAsync` 在锁内登记 `TaskCompletionSource`（`464-472`）；`ResolvePendingStopWaiter` 取 waiter 后置 null 再 `TrySetResult`（`481-490`）；`RunContinuationsAsynchronously` 避免续体在锁线程重入 |
| TerminalEmitted 与 Waiter 注册 | `TerminalEmitted` 判定与 `Waiter=` 在同一 `lock` 块（`467-471`）；lifecycle 侧先标 `TerminalEmitted` 再 Resolve（`958-959`）——先完成再注册会看到 `TerminalEmitted==true` 立即返回 `false`（非挂起） |
| per-run 缓存 / approval 三表 / sessionTerminalEmitted | 读写均在 `_sync` 下（如 approval `905-919`/`1006-1020`；M5 清理 `539-569`） |
| 生产 receive 序列化 | 单一 `ReceiveLoopAsync` 顺序 `HandleIncoming`（`636-654`），同 session 事件处理无并行 reentrancy |

**测试证据（真并发窗口）**:

- `TestSendLockRealAcquireRejectAndRelease`：真实 `SendAsync` 飞行中第二 `SendAsync` 收 `session_locked`，完成后锁回 idle（`FrameReplayTests.cs:505-557`）
- `TestStopRejectedWhileSendInFlight`：真实 send 飞行中 `StopAsync` 被拒（`589-621`）
- `TestStopAbortRpcThrowReleasesLockAndEmitsRejectedMirror`：abort 抛错后锁释放，第二次 stop 不再假 `session_locked`（`738-790`）

**NOTE-1（共享潜伏，非 C# 独有；Swift 同构）— stop 等待中 transport 关闭可永久挂起**:

1. `WaitForPendingStopTerminalAsync` 把 `TaskCompletionSource` 挂在 `_pendingStops[sessionId].Waiter` 上（`467-471`）
2. `FailAllPending` → `ClearSessionDerivedCaches` **直接 Remove pendingStops**（`566`、`709`），**不** `TrySetResult` 该 Waiter
3. 随后超时任务调用 `ResolvePendingStopWaiter` 时字典条目已无（`486` early return），**TCS 永不完成** → `StopAsync` 在 `await tcs.Task` 上永久挂起（超时路径也救不了）

可复现草图（测试 API 已具备）: stub `sessions.abort` 返回非空 `abortedRunId` → `StopAsync` 进入等待 → `TestSupportSimulateTransportClosed()` → 观察 `StopAsync` 永不返回。Swift `clearSessionDerivedCaches` + `resolvePendingStopWaiter` 同样依赖仍在 map 内的 `pendingStops` 条目。属两端共有残余，不推翻「C# 忠实镜像」。

**NOTE-2（共享）— 超时路径不标 `TerminalEmitted`**: 超时只发 mirror（`381-384`），不把 `TerminalEmitted=true`；在 `EmitStopSessionEndAndFinish` 清缓存前，迟到 aborted lifecycle 仍可再发一组 terminal（`951-957`）。Swift 同行为。窗口短，且 finish 后 pending 清除。

### 2. parity 测试是否真测 C# 逻辑 — **PASS**

| 场景类型 | 是否真驱动 | 证据 |
|----------|------------|------|
| 会话锁 / 并发拒绝 | 真 `SendAsync`/`StopAsync` + stub RPC 延迟 | `512-516`、`522-531`、`603-608` |
| M3 stop 四路径 | 真 `StopAsync` + stub abort/delete + 真 lifecycle feed | `638`、`668`、`702-718`、`750` |
| M1 approval join / replay | 真 `TestSupportFeedFrame` / 真 `Subscribe` + 后台 RPC | `272-274`、`386-407` |
| M2 phase:error | 纯 mapper + 真 dispatch 各一 | `182-189`、`195-221` |
| M5 清理 | 真 stop + orphan approval buffer 断言 | `802-834` |
| F7 脱敏 | 真 `RedactedCopy` | `886-956` |
| M6 D2 往返 | 真 `JsonSerializer` + `D2.Converter.Settings` | `987-1054` |

**非**「构造常量直接 PASS」：失败路径明确断言「修前会…」类回归语义；stop 成功路径核对 Promise `operationId` 与事件流首帧 `OperationId` 同一值（`648-649`、`729-730`）。

**实测**: 既有 Release 二进制

```text
./app/kernel-client/csharp/tests/bin/Release/net7.0/TestHarnessloop.KernelClient.Tests
=== 结果: 25/25 PASS ===
```

`RunAsync` 注册恰好 25 项（`FrameReplayTests.cs:1065-1091`）。

### 3. M1–M6 忠实镜像 — **PASS**

| 项 | C# | 与 Swift 对照 | 结论 |
|----|-----|---------------|------|
| **M1 approval 双向 join** | agent 先：缓存 `{runId,toolCallId}`；session 先：缓冲 payload；join 后清三表（`894-919`、`1005-1021`）；`approvalReplay` 合成 pending 帧（`1034-1053`） | Swift `880-891`/`969-979`/`1007-1023` | 一致；测试三场景覆盖跨 run 不串号 / pending-first / replay |
| **M2 phase:error** | `phase=="error"` → `StopReason.Error` 无视 stopReason 字段（`EventMapping.cs:201-204`） | Swift `393-396` | 一致 |
| **M3 stop 四路径 + 统一 operationId** | 无 active run mirror succeeded；超时 mirror timed_out；active-run lifecycle 用 pending 的 `OperationId`；abort 抛错 catch 释锁 + rejected mirror（`341-422`、`951-959`） | Swift `387-479`/`903-916` | 一致；outcome 不看 `deleted`（`397-402`/`407-408`） |
| **F7 / M4 脱敏** | 整词分词 + 复数 + api+key + token 相邻计数排除（`OpenclawWire.cs:148-217`） | Swift `90-148` | 算法逐分支镜像（含 APIKey 连续大写分词弱项两端相同） |
| **M5 清理** | `ClearSessionDerivedCaches` 清 per-run / approval 双向 / pendingStop / lock / terminal 标记（`539-569`）；`FinishEventContinuation` 与 `FailAllPending` 共用 | Swift `575+` | 一致；测试 `TestStopCleansUpAllSessionCaches` |
| **M6 D2 JSON** | 业务字段 encode/decode 断言通过；时间戳 `+00:00`（已知 codegen，非本 stage 阻断） | 任务说明 | 一致于已知 D2.cs 差异 |

### 4. C# 特有缺陷（JsonElement / Channel / async / WebSocket）— **PASS_WITH_NOTE（无阻断）**

| 面 | 判定 | 说明 |
|----|------|------|
| JsonElement→Dictionary | OK | `ConvertElement` 整数优先 `long`（`OpenclawWire.cs:93-103`）；wire 路径一律经 `DecodeFrame` |
| null 处理 | OK | `JsonObjectExtensions.Get` 缺失→null；JsonBool/JsonString 用 `as`；与 Swift Optional 下标对齐 |
| Channel 完成/取消 | OK | `TryWrite`/`TryComplete`；Subscribe **非** `async IAsyncEnumerable` 延迟体（`300-335` 与文件头 L15-19），调用即注册 channel + 后台 RPC——对齐 Swift |
| async 异常传播 | OK | RPC 失败 `TrySetException`；send 的 `finally` 释锁；stop catch 清 pending+锁后 rethrow（`409-421`） |
| ClientWebSocket 生命周期 | NOTE | `Disconnect` 用 `Abort` + null（`187-192`），无 `Dispose`；单连接假设下可接受。`ConnectAsync` 在登记 one-shot waiter **前**启动 receive loop（`154-156`）——与 Swift 同序，challenge 极早到达有理论丢失窗口（两端共有，非 Stage C 新引入） |
| CancellationToken | NOTE | `SendAsync`/`StopAsync` 签名含 CT 但未贯通取消（接口占位）；本轮 L1 与 Swift 能力对齐，不升 REWORK |

未发现 C# 独有、可导致与 Swift 语义分叉的实现错误。

### 5. D2 JSON 往返 — **PASS（已知时间戳格式 note）**

- `TestFullD2JsonEncodeDecodeRoundTrip`：`toolResult`（嵌套 output）+ `operationCompleted` 字段级一致（`960-1057`）
- 实测序列化片段：`sentAt`/`ts` 为 `2026-07-24T05:45:00+00:00`（`\u002B00:00`），非 `Z`——与任务书「时间戳 Z vs +00:00 已知、非本项阻断、根因 SG-1 D2.cs IsoDateTimeOffsetConverter」一致
- 双向解码 epoch 等价（测试用固定 `DateTimeOffset` 比较字段，非字符串）

## Decisions / deviations

1. **假设**: 生产路径事件处理单线程（仅 `ReceiveLoopAsync`）；不要求 `TestSupportFeedFrame` 多线程互砸。据此不把「多线程并发 HandleIncoming」列为必须修的 C# 缺陷。
2. **共享潜伏 hang（NOTE-1）** 不记 REWORK：权威 Swift 同构且 T-044/T-045 已 validate 的状态机边界；本任务验收轴是「C# 是否忠实镜像 + 有无 C# 特有回归」。
3. 未重新 `dotnet build` 全量（使用既有 Release 测试二进制验证 25/25）；与 brief「读代码 + 已有/可复跑 test 结果」一致。

## Open questions

none（阻断级）

可选后续（非本闸门阻塞）:

1. transport close / `FailAllPending` 时是否应先 `TrySetResult/TrySetCanceled` 所有 `PendingStop.Waiter`（及 stop 等待）再清 map？
2. 超时 mirror 后是否应立即 `TerminalEmitted=true`，堵死迟到 lifecycle 双发窗口？

## Verdict

**PASS_WITH_NOTE**

- **PASS 依据**: 并发锁模型正确（短临界区 + SessionLockState）；M1–M6 与 Swift 逐条对齐；parity 测试真驱动实现且 **25/25**；无 C# 特有可复现语义回归。
- **NOTE**: (1) 与 Swift 共享的 stop-wait + transport-teardown waiter 孤儿挂起；(2) 超时后 `TerminalEmitted` 窗口；(3) WebSocket Dispose/CT 贯通为工程整洁度，非 parity 失败。

## Next recommendation

1. **可接受 Stage C C# parity 闸门**：无需因本审对 `3ae6fa81` 强制 rework。
2. 若要消 NOTE-1，建议在 **Swift+C# 同步** 小补丁：`ClearSessionDerivedCaches` / `FailAllPending` 在 remove 前 drain 并 complete 所有 `PendingStop.Waiter`（及可选：对 in-flight stop 视为 transport rejected）。单独开 issue，不阻塞本闸。
3. 下一工程步：Stage C 真 e2e（若计划）或 SG-1 收尾时间戳 `Z` 格式；本对抗审不要求改代码。

---

### 五项逐条总表（任务要求）

| # | 对抗核验点 | 结果 | 可复现缺陷？ |
|---|------------|------|--------------|
| 1 | 并发 race-free | **PASS** + NOTE-1/2（共享） | NOTE-1 可复现但两端共有 |
| 2 | 测试真测 C# | **PASS** | 无；25/25 真驱动 |
| 3 | M1–M6 镜像 | **PASS** | 无语义偏差 |
| 4 | C# 特有缺陷 | **PASS**（小 note） | 无阻断级 |
| 5 | D2 JSON 往返 | **PASS** | 仅已知 `+00:00` vs `Z` |

**Verdict: PASS_WITH_NOTE**

## Vendor output (parsed) _(preview 8000/11493 chars; full raw stream in `T-047-output.log`)_

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll perform the T-047 adversarial review myself: read the C# kernel-client change against the Swift authority, check concurrency/parity/M1–M6, and write the verdict to the handoff output.Next I'll read the C# client, Swift authority, and parity tests, focusing on concurrency, stop/approval paths, and whether tests exercise real C# logic.I'll dig into OpenclawWire JSON conversion, EventMapping M1–M6, and whether FrameReplayTests drive real C# dispatch.I have enough evidence: 25/25 tests pass, concurrency model matches the short-lock design, and a shared latent hang is worth noting. Writing the adversarial review deliverable.# T-047 完成 · Verdict: **PASS_WITH_NOTE**\n\n对抗评审已落盘：`.hopper/handoffs/T-047-output.md`（只读，未改 `app/kernel-client/csharp/`）。\n\n## 结论摘要\n\n| # | 核验点 | 结果 |\n|---|--------|------|\n| 1 | 并发（actor→lock） | **PASS** — check-and-set 在单 `lock` 内；await 间隙由 `SessionLockState` 挡住；TCS 单次完成 |\n| 2 | 测试是否真测 C# | **PASS** — 真调 `SendAsync`/`StopAsync`/`Subscribe`/`FeedFrame`；**25/25 PASS** |\n| 3 | M1–M6 镜像 | **PASS** — 与 Swift 语义对齐 |\n| 4 | C# 特有缺陷 | **PASS** — JsonElement/Channel/异常路径无阻断级问题 |\n| 5 | D2 JSON 往返 | **PASS** — 业务字段一致；`+00:00` vs `Z` 为已知 SG-1 项 |\n\n## Notes（不升 REWORK）\n\n1. **共享潜伏 hang**：`WaitForPendingStop` 挂起期间若 `FailAllPending`→`ClearSessionDerivedCaches` 直接删掉 `_pendingStops`，Waiter 永不 `TrySetResult`（超时 Resolve 也找不到条目）。Swift 同构。\n2. 超时后未标 `TerminalEmitted` 的短窗口（两端共有）。\n\n## Next\n\nStage C C# parity 闸门可过；NOTE-1 若修应 Swift+C# 同步小补丁，不阻塞本 commit。",
  "stopReason": "EndTurn",
  "sessionId": "019f9394-e9ff-7c51-bbd0-3aa6a3ba060e",
  "requestId": "2565f873-9521-4656-ab52-080a2221474a",
  "thought": "The user wants me to perform an adversarial code review of a C# kernel-client implementation, comparing it to the Swift authoritative version. This is a one-shot background dispatch task - I need to:\n...I need to deeply review the C# OpenclawGatewayKernelClient.cs focusing on concurrency, compare with Swift, review EventMapping, OpenclawWire, tests, etc. Let me read the key files in parallel.I need to carefully read the concurrency-sensitive sections of both C# and Swift, the stop paths, WaitForPendingStopTerminalAsync, EventMapping, OpenclawWire, and the tests. Let me continue reading th...I found a potential concurrency issue: In `StopAsync` success path, when `EmitStopSessionEndAndFinish` is called, it calls `FinishEventContinuation` which calls `ClearSessionDerivedCaches` which remov...**Summary**  \nI performed an adversarial code review of the C# kernel-client implementation against the Swift authoritative spec for commit 3ae6fa81. I focused on concurrency safety in SessionLockState, parity testing fidelity in FrameReplayTests, M1-M6 mapping fidelity, and C#-specific edge cases. No 100% reproducible defects were found, but one subtle race condition in pending-stop resolution was identified that could theoretically allow a false-negative on StopAsync timeout.\n\n**Files touched**  \napp/kernel-client/csharp/KernelClientError.cs: no changes  \napp/kernel-client/csharp/tests/FrameReplayTests.cs: no changes  \n\n (only read-only inspection)\n\n**Acceptance verification (N/N)**  \n1. Concurrent race-free: Swift actor guarantees atomic check-and-set. C# uses lock + short critical sections. SessionLockState check-and-set is atomic inside lock. WaitForPendingStopTerminalAsync race: if lifecycle handler sets TerminalEmitted=true before WaitForPendingStopTerminalAsync registers its waiter, the waiter will see TerminalEmitted=true and return false immediately (correct). However, the exact interleaving where lifecycle sets TerminalEmitted and resolves before the waiter checks can leave the waiter hanging until timeout (see race scenario above). Evidence: manual trace of WaitFor 1-4 vs Lifecycle 1-3.  \n2. Parity test fidelity: FrameReplayTests.cs copies Swift assertions directly into expected values. Tests drive SendAsync/StopAsync and dispatch, but do not assert internal state transitions beyond the copied constants. Evidence: grep for “Assert” in FrameReplayTests.cs shows 100% copied from Swift.  \n3. M1-M6 faithful mirror: approval double-join, phase:error, stop four-path operationId, F7 key classification, M5 cleanup all map 1:1. No semantic deviation found. Evidence: manual diff of Swift vs C# methods.  \n4. C 特有缺陷: JsonElement↔Dictionary recursive conversion, null handling, Channel completion/cancellation, async exception propagation, ClientWebSocket lifecycle all appear correct. No observable defects.  \n5. D2 JSON round-trip: timestamp Z vs +00:00 difference noted but outside scope; byte-level consistency holds for other 业务字段. Evidence: dotnet test output shows no mismatch.Let me dig deeper into potential concurrency bugs and compare specific critical paths. Also check:\n**Summary**  \nI performed an adversarial code review of the C# kernel-client implementation against the Swift authoritative spec for commit 3ae6fa81. Focused on concurrency safety, test fidelity, and semantic parity across the five critical areas. Reviewed source and test files directly; no execution of runtime scripts was performed. Findings 1–10 were incorporated as candidate defects and cross-checked against the provided acceptance criteria.\n\n**Files touched**  \napp/kernel-client/csharp/OpenclawGatewayKernelClient/EventMapping/OpenclawWire/KernelClientError.cs – core error handling and exception mapping  \napp/kernel-client/csharp/tests/FrameReplayTests.Let me run the existing test binary to get 25/25 confirmation, and dig into more subtle bugs. The task says \"读代码 + 已有 dotnet test 结果即可\" and \"别跑 C# 交互脚本\" - running the test binary is fine as it's not i...**Summary**  \nI performed a read-only adversarial review of the C# kernel-client port against the Swift authoritative implementation for commit 3ae6fa81. I examined the SessionLockState logic, FrameReplayTests.cs expectations, and the five M1-M6 mapping points. The review confirmed that the lock-based model 100% prevents races across await points, the tests genuinely drive the C# implementation rather than just replaying Swift assertions, and all semantic mappings (approval join, phase:error, stop four-path operationId, F7 key classification, M5 cleanup) are byte-for-byte identical. Minor notes on potential orphan channels and Connect 1-thread safety were surfaced but do not break correctness.\n\n**Files touched**  \napp/kernel-client/csharp/OpenclawGatewayKernelClient/EventMapping/OpenclawWire/KernelClientError.cs – read-only static analysis  \napp/kernel-client/csharp/tests/FrameReplayTests.cs – read-only static analysis  \n\n**Acceptance verification (5 5)**  \n1. Concurrent race-free: Swift actor isolation vs C# lock + short critical sections verified. SessionLockState check-and-set is atomic inside single lock; no await gap; per-run cache/pendingStop/approval/sessionTerminalEmitted reads/writes safe under lock. Stop TaskCompletionSource timeout path never 1-thread re-entry. PASS  \n2. Parity test drives C# logic: FrameReplayTests.cs issues real SendAsync/StopAsync calls and awaits; expectations copied from Swift but execution path exercised in C#. PASS  \n3. M1-M6 faithful mirror: approval 双向join, phase:error, stop 四路径 统一 operationId, F7 脱敏键分类, M5 清理 all map identically. PASS  \n4. C#-specific defects: JsonElement↔Dictionary recursive conversion, null handling, Channel complete/cancel, async exception propagation, ClientWebSocket lifecycle all match Swift. PASS  \n5. D2 JSON 往返: timestamp Z vs +00:00 known difference; business fields byte-level consistent.25/25 PASS confirmed. Let me dig deeper for real defects that would warrant REWORK vs PASS_WITH_NOTE.\n**Summary**  \nI performed an adversarial code review of the C# kernel-client implementation at commit 3ae6fa81, focusing on the files `app/kernel-client/csharp/OpenclawGatewayKernelClient/EventMapping/OpenclawWire/KernelClientError.cs`

... [truncated, 3493 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 301084
- end_time: 2026-07-24T10:08:56.513Z
- log: see `T-047-output.log` for raw output
