---
phase: done
last_progress_at: "2026-07-24T16:00:27.375Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T16:00:27.371Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 216737
adapter_status: success
---
# T-049 · code-review-adversarial · SG-5 stop() D1 §6.2 force-deny 定向补丁

**Task-type**: `code-review-adversarial` · **Vendor**: grok · 只读  
**评审对象**: 主仓库工作区未提交改动（6 文件）  
`app/kernel-client/swift/{OpenclawGatewayKernelClient.swift,EventMapping.swift,FrameReplayTests.swift}`  
`app/kernel-client/csharp/{OpenclawGatewayKernelClient.cs,EventMapping.cs,tests/FrameReplayTests.cs}`  
**权威契约**: D1 `~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md` §6.2（M3 定序 / 批量 deny / turn-complete 先于 session-end）  
**wire 参考**: `kernels/openclaw/src/gateway/server-methods/approval.ts`（`approval.resolve`）

---

## Summary

对本轮 Sonnet 实现的 stop() force-deny 补丁做了异构对抗复核。核心路径正确：`forceDenyPendingApprovalsBeforeStop` 在 `sessions.abort` **之前**对每个 pending reqId 发真实 `approval.resolve {id,kind,decision:"deny"}`，要求响应 `approval.status=="denied"` 才确认，否则 throw，不伪造确认；成功列表写入 `PendingStop.forceResolvedApprovalReqIDs` 并在 aborted-run 与正常完成 race 两处 mapper 填入 `TurnCompleteEvent.forceResolvedApprovals`（空则 nil）。NOTE-1 transport-close-during-wait 路径未回退永久挂起；force-deny 抛错走既有 catch 释放锁/pendingStop。两端实测 **28/28 PASS**，新测真驱动 client（join approval → stop → RPC 顺序 + forceResolved）。残留：**await 窗口内新到的 approval 可逃过本轮 force-deny 快照后仍 pending 就被 abort**（Swift actor 重入 / C# lock 外 await 同类）；无 force-deny 失败/半完成/transport-during-force-deny 回归测。不构成阻断 REWORK，记 **PASS_WITH_NOTE**。

## Files touched

none（只读评审；本文件为 handoff 产出）

**评审阅读面**（未修改）:

| 路径 | 一句话 |
|------|--------|
| `swift/OpenclawGatewayKernelClient.swift` | force-deny 实现 + stop 定序 + pending approval cache + NOTE-1 |
| `swift/EventMapping.swift` | 两处 mapper 接 `forceResolvedApprovals` |
| `swift/FrameReplayTests.swift` | +2 真 client 驱动 force-deny 测 |
| `csharp/OpenclawGatewayKernelClient.cs` | C# parity 镜像 |
| `csharp/EventMapping.cs` | 同上 |
| `csharp/tests/FrameReplayTests.cs` | 同上 |
| D1 §6.2 / openclaw `approval.ts` | 契约与 wire 对照 |

## Acceptance verification (5/5)

### 1. D1 §6.2 M3 定序 + 内核侧确认屏障 — **PASS**

| 检查点 | 结论 | 证据 |
|--------|------|------|
| force-deny **先于** `sessions.abort` | PASS | Swift `stop()`: `458-461` 先 `await forceDeny...` 再 `request("sessions.abort")`；C# `StopAsync`: `434-437` 同序 |
| 真实 RPC 而非本地标记 | PASS | Swift `600-627` / C# `585-627`：`approval.resolve` params `{id, kind, decision:"deny"}` |
| `await request` 构成内核确认屏障 | PASS（openclaw wire） | openclaw `approval.ts` handler 在 `applyApprovalDecision` 完成后再 `respond(true, {applied, approval})`；客户端 `request()` 仅在 `ok:true` 的 res 帧 resume，`ok:false` → `rpcRejected`（Swift `911+` res 分支） |
| 非 `"denied"` 不伪造确认 | PASS | Swift `614-621` / C# `611-618`：`status != "denied"` → `protocolMismatch` throw；不 append 进 forceResolved、不继续 abort |
| RPC 失败不吞 | PASS | `try await request` 抛错 → stop `catch` 统一收尾（Swift `540-563` / C# `502-542`），**不会**在 catch 前发出 abort |
| 无 pending 不发 RPC | PASS | Swift `601-602` / C# `592`：空列表直接 return `[]` |

**与 D1 原文对照**：§6.2 M3「① 先 FORCE_DENIED_ON_STOP + 向内核 deny → ② 确认①生效后才 abort」在 stop 成功路径上落地；`forceResolvedApprovals` 同步列出（见焦点 3）。

### 2. 新增 await 的并发回归（最重）— **PASS_WITH_NOTE**

#### 2a. 与 NOTE-1 / pendingStop / session lock 交互 — **无永久挂起回归**

| 场景 | 行为 | 结论 |
|------|------|------|
| force-deny 抛错（RPC/status） | 落入 stop `catch`：若未 terminalEmitted 则 mirror rejected；`pendingStops.remove` + 锁清除；rethrow | 不卡 `stop_in_progress`（Swift `553-563` / C# `515-541`） |
| force-deny 在途 transport 关闭 | `failAllPending` 唤醒 in-flight `approval.resolve` continuation（throw）；此时 waiter **尚未**登记（waiter 只在 abort 返回后的 `waitForPendingStopTerminal` 登记）→ RPC 失败 → catch 清理 | **不永久挂起** |
| abort 后等待终态时 transport 关闭 | 既有 NOTE-1：`resolvePendingStopForTransportClose` 发 mirror + resume `.transportClosed`，stop 抛错 | 既有路径完好（测试 `NOTE-1 ... transport closes while awaiting` 两端 PASS） |
| force-deny 成功后 abort/delete 抛错 | 同既有 M3 catch + `alreadyTerminalEmitted` 去重 | 不重蹈锁泄漏 |

**结论**：force-deny 插入的 N 个 await **未**重蹈 NOTE-1「pendingStop 被 remove 却不 resume waiter」类永久挂起；锁/pendingStop 在失败路径可释放。

#### 2b. 残留竞态 NOTE-A（可复现，非 hang）— await 窗口逃逸 pending

**缺陷**：force-deny **一次性快照** session 下 reqId 列表，串行 await 期间（Swift：actor 在 `await request` 时允许其他 actor 任务进入；C#：`lock` 外 `await RequestAsync`）`emitApprovalRequestIfPossible` 仍可登记**新的** pending approval，且 **不会**被本轮循环 deny，随后 `sessions.abort` 仍会发出。

| | 行号 |
|--|------|
| 快照 | Swift `601` `let reqIDs = pendingApprovalReqIDsBySessionID[sessionID] ?? []`；C# `587-591` `ToList()` 后释放锁 |
| 无再扫描 | 循环结束直接 `return forceResolved`（Swift `627` / C# `627`），stop 立刻 abort |
| 登记不看 stop 锁 | Swift `1231-1237` / C# emit 路径：`stopInProgress` 时仍可 insert pending |

**可复现草图**（测试桩已具备）:

1. join 产出 approval-A 进入 pending  
2. stub `approval.resolve` 内 `Task.sleep` / `await Task.Delay` 数百 ms  
3. sleep 期间 `testSupportFeedFrame` 再 join approval-B  
4. 观察 call log：只有 A 的 `approval.resolve`，无 B；随后 `sessions.abort`  
5. B 仍 `testSupportHasPendingApprovalAwaitingDecision(B)==true` 且内核侧仍可能 pending  

这正是 D1 M3 要关的「abort 已出、审批还 pending、内核可能仍接受人工决策」窗口的变体——只是触发依赖 stop 过程中**新到**的 approval（D1 有界缓冲=1 降低概率，但适配器**未强制**上限=1）。

#### 2c. 多 pending 半完成态 — **NOTE-B**

循环内：成功才 `remove` 本地 cache 并 append forceResolved；中途 throw 时：

- 已成功 deny 的 reqId：内核已 denied + 本地已清  
- 未处理的 reqId：本地仍 pending；session 仍存活（abort 未发）  
- 调用方可重试 stop；已清的不会二次 resolve  

D1 名义上界=1 时半完成罕见。无测试覆盖。可接受的 fail-closed 行为，但**未文档化**「半完成后 retry 语义」。

### 3. forceResolvedApprovals 填充 — **PASS**

| 分支 | Swift | C# | 空/nil 语义 |
|------|-------|-----|-------------|
| aborted lifecycle + pendingStop 匹配 | `1115-1127`：`isEmpty ? nil : list` | `1234-1245`：`Count==0 ? null : ToArray()` | 无 force-deny → **nil**（非空数组） |
| 正常完成 race（aborted:false + pendingStop 有 force list） | `1151-1164` | `1266-1283` | 无匹配 → nil |
| 无主 aborted 兜底 | `1134-1144` 硬传 nil | `1250-1258` null | 正确（无 stop 上下文） |
| EventMapping 透传 | `409-415` / `463-471` | `221` / `255` | 调用方决定 nil vs 列表 |

新测断言：有 pending 时 `forceResolvedApprovals == [approvalID]`；无 pending 时保持 nil（不是 `[]`）。

### 4. C# parity 忠实 — **PASS（附与 Swift 同构的 NOTE-A）**

| 维度 | 结论 |
|------|------|
| 结构 | `PendingApprovalAwaitingDecision` / `_pendingApprovalsByReqId` / `_pendingApprovalReqIdsBySessionId` / `ForceResolvedApprovalReqIds` 与 Swift 字段一一对应 |
| lock 模型 | 读 snapshot、读 info、写 remove 均在 `_sync` 内；`await RequestAsync` 在锁外——正确避免跨 await 持锁 |
| check-consume | 成功路径 `lock` 内 Remove reqId；与 Swift actor 串行消费语义等价 |
| 失败/catch | 与 Swift 同构的 `alreadyTerminalEmitted` 默认 true 当 entry 已无 |
| race | 与 Swift 共享 NOTE-A（快照后 await 窗口），非 C# 独有移植错误 |

未发现 C# 独有的 force-deny 双重 deny / 丢列表 / 错锁死。

### 5. 测试真实性 + 边界 + TODO 桩未偷实现 — **PASS_WITH_NOTE**

**真驱动**（非 seed 内部态）:

- Swift `testStopForceDeniesPendingApprovalBeforeAbort`（`749-859`）：真实 feed agent+session.approval join → 断言 pending 登记 → stub 三 RPC + call order log → 真 `client.stop` → feed aborted lifecycle → 断言顺序 `["approval.resolve","sessions.abort","sessions.delete"]` + forceResolved + turn_complete 先于 session_end + pending 清除  
- Swift `testStopWithNoPendingApprovalLeavesForceResolvedApprovalsNil`（`867-910`）：**故意不 stub** `approval.resolve`；若误调会 notConnected 失败  
- C# `TestStopForceDeniesPendingApprovalBeforeAbort` / `TestStopWithNoPendingApprovalLeavesForceResolvedApprovalsNil`（`753-933`）镜像  

**实测**:

```
Swift frame-replay-tests: 28/28 PASS
C# KernelClient.Tests (dotnet run): 28/28 PASS
```

**TODO 桩仍在**（未借机实现）:

| 方法 | Swift | C# |
|------|-------|-----|
| `interrupt` | `404-405` notImplemented | `399` NotImplemented |
| `respondApproval` | `726-727` | `743-744` |
| `capabilities` | `730-731` | `746-747` |

**测试缺口 NOTE-C**（建议后续补，不阻断本轮）:

1. `approval.resolve` 返回 `status!="denied"` → stop throw、无 abort、锁释放  
2. force-deny 在途 transport close → 不 hang  
3. NOTE-A：delay resolve 期间第二 approval 逃逸  
4. 多 pending 中途失败半完成  

## Decisions / deviations

- **假设（1 行）**：openclaw `await request` 的 ok 响应等价 D1「内核侧确认接受」——与 `approval.ts` handler 定序一致；未跑真实 gateway 集成。  
- 半完成多 pending / await 窗口逃逸记 note 而非 REWORK：主路径定序与确认屏障成立；D1 有界缓冲=1 使逃逸需额外并发到达；现测 28/28 绿且无 hang 回归。

## Open questions

1. stopInProgress 期间是否应**拒绝/缓冲**新 `approvalRequest` 登记（或 force-deny 结束前 while-drain 直到 pending 空）以彻底闭合 NOTE-A？  
2. force-deny 失败时，已 deny 的 reqId 是否需要出现在某条 `operation_completed(rejected)` 的 detail/旁路字段（当前仅 throw，事件流可能只有 rejected mirror、无 forceResolved 列表——因 turn_complete 未产出）？  
3. `approval.resolve` 对已 terminal 的 id 返回 `applied:false` + 既有 status：若 status 恰为 `denied` 会当成功（合理）；若为 allow 终态则 throw 并中止 abort——是否符合产品「stop 必须尽量 cancel」偏好？

## Verdict

**PASS_WITH_NOTE**

- **PASS 部分**：D1 §6.2 M3 主路径定序正确；真实 `approval.resolve` + `status=="denied"` 屏障；失败不伪造确认；`forceResolvedApprovals` 两分支 + nil 语义正确；C# 忠实；NOTE-1 无 hang 回归；两端 28/28；TODO 桩未偷实现。  
- **NOTE**：NOTE-A await 窗口新 pending 可逃过 force-deny；NOTE-B 多 pending 半完成未测；NOTE-C 失败/transport-during-force-deny 无回归测。

## Next recommendation

1. **可合入本补丁**（缺口主路径已收）。  
2. 跟进小修（非本轮阻断）：force-deny 改为 **drain 循环**（do { snapshot; deny all } while pending 非空）或 `stopInProgress` 下冻结 approval 登记；补 NOTE-C 三条负面测。  
3. 无需为 C# 单独再开 port 修复——与 Swift 同构。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll perform the adversarial review of the SG-5 stop() force-deny patch myself: read D1 §6.2, inspect Swift/C# stop paths and tests, then write `T-049-output.md`.Reading the stop/force-deny implementations, tests, and openclaw approval wire in detail.Tests are 28/28 on both ends. Writing the adversarial review deliverable with the five focus areas and residual concurrency notes.## T-049 完成\n\n对抗审已落盘：`.hopper/handoffs/T-049-output.md`\n\n### Verdict: **PASS_WITH_NOTE**\n\n| 焦点 | 结论 |\n|------|------|\n| 1. D1 §6.2 M3 定序 | **PASS** — force-deny 真先于 `sessions.abort`；`await approval.resolve` + `status==\"denied\"` 才确认，否则 throw |\n| 2. 并发 / NOTE-1 | **PASS_WITH_NOTE** — 无永久挂起回归；catch 正确释锁。残留 **NOTE-A**：await 窗口内新到的 approval 可逃过本轮快照后仍 pending 就被 abort |\n| 3. forceResolvedApprovals | **PASS** — aborted + 正常完成 race 两处均填；空 → nil |\n| 4. C# parity | **PASS** — lock 外 await，与 Swift 同构（共享 NOTE-A） |\n| 5. 测试 + TODO 桩 | **PASS** — 真驱动 client；`interrupt`/`respondApproval`/`capabilities` 仍是 TODO |\n\n### 实测\n- Swift frame-replay：**28/28 PASS**\n- C# frame-replay：**28/28 PASS**\n\n### 建议\n主路径可合入。后续非阻断：force-deny drain 循环或 `stopInProgress` 冻结新 approval 登记，并补失败/半完成/transport-during-force-deny 负面测。",
  "stopReason": "EndTurn",
  "sessionId": "019f94d8-052a-7022-aa4a-1ddaf8aacdba",
  "requestId": "01259910-9cca-4e1b-b09e-eff4049dac42",
  "thought": "The user wants me to perform an adversarial code review of a specific change related to stop() force-deny functionality. I'm the execution agent - I need to review the code myself, not delegate, and p...Good progress. Let me read the key implementation sections in detail for both Swift and C#, the tests, openclaw approval.resolve, and EventMapping forceResolvedApprovals.Let me continue reading the EventMapping changes, tests for force-deny, request() transport handling during force-deny, and the openclaw approval.resolve handler. Also need to check half-completed mul...Let me dig deeper into potential concurrency issues:\n**Summary**  \nI performed an adversarial code review of the stop() path changes in both Swift and C# kernel clients, focusing on D1 §6.2 force-deny ordering, concurrency safety, and parity. The implementation correctly places forceDenyPendingApprovalsBeforeStop before sessions.I'm building a thorough adversarial review. Let me identify real defects:\n**Summary**  \nI performed an adversarial code review of the stop() path changes in both Swift and C# kernel clients, focusing on D1 §6.2 force-deny ordering, concurrent regression risks, approval cache handling, and test fidelity. The review confirmed correct sequencing, proper error propagation, and no new dead locks, though minor parity gaps in C# locking and test boundary coverage were noted.\n\n**Files touched**  \napp/kernel-client/swift/OpenclawGatewayKernelClient.swift: forceDenyPendingApprovalsBeforeStop and stop() integration  \napp/kernel-client/csharp/OpenclawGatewayKernelClient.cs: equivalent force-deny logic and EventMapping.cs:409/459  \napp/kernel-client/swift/FrameReplayTests.swift and csharp/FrameReplayTests.cs: new stop-with-pending-approval tests\n\n**Acceptance verification (5/5)**  \n1. D1 §6.2 M3 ordering: force-deny precedes sessions.abort; await approval.resolve returns only after kernel applies decision; non-denied status or RPC failure throws (verified via grep in approval.ts handler and client call sites).  \n2. Concurrent regression: force-deny await under stopInProgress is covered by existing NOTE-1 transport-close logic; no hang or deadlock introduced (tested via manual 6cf2dcc5 comparison). Half-completed multi-pending handled by cache cleanup on throw.  \n3. forceResolvedApprovals: both aborted-run and race branches correctly populate reqIds; nil semantics preserved when no pending (grep confirmed).  \n4. C# parity: lock snapshot + per-iteration lock release matches Swift actor isolation; however, await gap allows new pending registration (see Decisions).  \n5. Test reality: new tests drive client join → stop → RPC order and assert forceResolvedApprovals (verified by running FrameReplayTests).C# JsonObj can return null, then `.Get(\"status\")` is called on null - extension method handles null:\ndotnet test returned quickly with exit 0 - might not have run tests properly. Let me check.Both 28/28 PASS. Now I need to finalize the adversarial review.\n**Summary**  \nI performed an adversarial code review of the stop() force-deny patch across Swift and C# kernel clients, focusing on D1 §6.2 ordering, concurrency safety, and test coverage. The implementation correctly places forceDeny before sessions.abort and uses real RPC status checks, but a subtle re entrancy window in Swift actors allows new approvals to arrive mid-force-deny, potentially leaving them un-denied before abort. C# parity holds with explicit locking, and tests drive the expected RPC sequence. Verdict is PASS_WITH_NOTE due to this medium-severity gap.\n\n**Files touched**  \n- app/kernel-client/swift OpenclawGatewayKernelClient.swift: forceDenyPendingApprovalsBeforeStop and PendingApprovalAwaitingDecision cache  \n- app/kernel-client/csharp  OpenclawGatewayKernelClient.cs and EventMapping.cs: equivalent force-deny logic and cache handling  \n- app/kernel-client/swift  FrameReplayTests.swift: added 28 28 test cases exercising stop with approvals  \n- app/kernel-client/csharp  FrameReplayTests.There's already a T-049-output.md - I should overwrite it with my review as the execution agent.I need to write the full output.md content. Looking at other T-*-output.md files for format - the hopper metadata frontmatter might get updated by hopper itself. I should write the review content. Loo...I'll write the full T-049 output.md with the review content. Hopper may update frontmatter later; I'll write a complete deliverable body similar to T-047.I've completed the adversarial review and written the output. Let me mark todos complete.The task is complete. I've written the full adversarial review to the required path. Summarize for the user/dispatcher.",
  "usage": {
    "input_tokens": 93752,
    "cache_read_input_tokens": 834944,
    "output_tokens": 10438,
    "reasoning_tokens": 9163,
    "total_tokens": 939134
  },
  "num_turns": 13,
  "total_cost_usd": 0.5006152,
  "total_cost_usd_ticks": 5006152000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 93752,
      "outputTokens": 10438,
      "cacheReadInputTokens": 834944,
      "modelCalls": 13,
      "costUSD": 0.5006152
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 216737
- end_time: 2026-07-24T16:00:27.371Z
- log: see `T-049-output.log` for raw output
