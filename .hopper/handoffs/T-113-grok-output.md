# T-113-grok — rounds/0020「停止生成」对抗评审（code-review-adversarial）

**审查对象**：`a19c927`（实现）+ `ba614d8`（真内核验证 / CLIRunner）  
**审查性质**：只读；本文件为评审产物，未改任何被审代码。  
**假设（一行）**：实拍 README 与 isolation 日志中的 RPC 计数可信；未重新跑帧回放 / 真内核。

---

## Summary

`interrupt(mode:"cancel")` 的主体实现通过了四条红线中的三条半：不发 `session_end`、不 finish 事件流、不调 `sessions.delete`、不复用 `stop()` 函数体、unsupported mode 显式拒绝、互斥锁用单个 `defer` 覆盖失败路径、强制 deny 与 `stop()` 共用同一 drain 且定序相同。真内核四次与实拍均证明会话在 interrupt 后仍可再 `send()`。

但存在一个**已被实拍钉住、且可由源码路径独立证实**的用户可见缺陷：成功 interrupt 后，openclaw 常见的第二帧 `lifecycle phase:"error" / "This operation was aborted"` 在 `pendingStops` 已被 `defer` 摘掉后落入 `handleAgentEvent` 的 unowned 兜底分支，**写死 `operationKind: .stop`**，映射 outcome 为 `aborted_effect_unknown`，于是 UI 在正确的 `interrupt 已完成：succeeded` 之后再画一条虚假的 `stop 已完成：aborted_effect_unknown`。该缺陷不是 `stop()` 被误调；`sessions.delete=0` 与代码路径一致。

**Verdict 倾向 REWORK**：红线语义大体成立，但「标签说谎」的系统行会在正常成功路径上稳定出现（只要内核发 end→error 双帧），且无回归测试钉住「pending 已清理后的迟到 aborted 帧应静默丢弃 / 不得标成 stop」。

---

## Files touched

审查侧未修改任何文件。被审变更涉及：

| Path | 角色 |
| --- | --- |
| `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` | `interrupt()` 本体、锁态、pendingStop 共享、lifecycle 匹配 / 兜底 |
| `app/kernel-client/swift/EventMapping.swift` | `mapOpenclawAgentLifecycleToAbortTerminalEvents` 增加 `operationKind` 参数 |
| `app/kernel-client/swift/KernelClient.swift` | 协议注释（interrupt 不再是桩） |
| `app/apps/AgentShell/Sources/AgentShellCore/SessionStore.swift` | `interruptCurrentRun` + `handleOperationCompleted` 清 `isWaitingForReply` |
| `app/apps/AgentShell/Sources/AgentShellCore/ChatSessionViewModel.swift` | `isInterrupting` |
| `app/apps/AgentShell/Sources/AgentShell/SessionDetailView.swift` | 发送/停止/停止中 三态同槽按钮 |
| `app/kernel-client/swift/frame-replay-tests/InterruptTests.swift` | 适配器级红线 / 锁 / deny 定序 |
| `app/kernel-client/swift/frame-replay-tests/SessionStoreInterruptTests.swift` | store 层 isWaiting 清理 |
| `app/kernel-client/swift/CLIRunner.swift` | 真内核 `SG5_INTERRUPT_AFTER_MS` 步骤（ba614d8） |
| `.harnessloop/.../rounds/0020/scope-lock.md` + `evidence/` | 范围与证据（非产品代码） |

---

## Acceptance verification（对照 scope-lock 红线 / 四问）

### 1. 不发 `session_end` / 不 finish 事件流 / 不调 `sessions.delete` — **PASS（代码 + 证据）**

对 `interrupt()` 函数体（`OpenclawGatewayKernelClient.swift:940–1051`）做注释剥离后的静态检查：

| 符号 | 可执行代码命中 |
| --- | --- |
| `sessions.delete` | **0**（仅注释） |
| `emitStopSessionEndAndFinish` | **0** |
| `finishEventContinuation` | **0** |
| `clearSessionDerivedCaches` | **0** |
| `kernelKeyBySessionID.remove` | **0** |

`interrupt()` 唯一 dispatch 的 run 生命周期 RPC 是 `sessions.abort`（`:980`）。  
真内核证据四次均 PASS「无 sessionEnd」且 post-interrupt `send()` 拿到新 runId（`evidence/real-kernel-interrupt.md`）。  
实拍隔离日志：`sessions.abort≥1`，`sessions.delete=0`（`evidence/shots/README.md`）。

### 2. 不把 `steer` / `abort_and_resend` 当 cancel — **PASS**

`:946–953`：mode 校验在**拿锁之前**；非 `.cancel` → `unsupported_interrupt_mode`。  
`InterruptTests` 有两条 mode 门禁测试，并断言 **零 RPC**（不会静默 abort）。

### 3. 不改 `stop()` 既有行为 — **PASS（diff 级）**

`a19c927` 对 `stop()` 的可执行 diff 实质是：

- `PendingStop(..., operationKind: .stop)` 显式化原先隐式的 `.stop`
- `emitOperationCompletedMirror` / lifecycle 映射改为接收参数后，调用点传 `.stop`

`sessions.delete` + `emitStopSessionEndAndFinish` 路径仍在 `stop()` 成功尾声（`:1183–1193`），interrupt 不进入。

### 4. 四问专项

#### ① 会话是否真的存活（不只是没调 delete）

**结论：内核侧存活成立；适配器侧「可继续对话」也成立；但存在「会话活着却被标死一次」的用户可见污染。**

除 delete 外，能使会话**事实上不可用**的路径我逐条核对如下：

| 潜在致死路径 | interrupt 是否触发 | 证据 |
| --- | --- | --- |
| `sessions.delete` | 否 | 函数体 0 次；实拍 delete=0 |
| `emitStopSessionEndAndFinish` → `session_end` + finish stream + 清 `kernelKey` | 否 | 函数体无调用；真内核无 sessionEnd；实拍同会话可再聊 |
| `finishEventContinuation` 单独调用 | 否 | 0 次 |
| `clearSessionDerivedCaches`（transport 死才清） | 否（正常 interrupt） | 不在 interrupt 路径 |
| `lockState` 永久 `interruptInProgress` | 否（有 defer） | 见② |
| `kernelKeyBySessionID` 被摘掉 | 否 | 仅 stop 收尾 / transport 清理 |

**真存活路径**：`kernelKey` 保留 + 事件流 continuation 仍开 + 锁回 idle → 后续 `send()` 合法。真内核四次新 runId 与实拍 `03-session-alive-after-interrupt.png` 一致。

**非致死但会让会话「看起来坏了」的路径**（见缺陷专节）：迟到的 aborted lifecycle 在 stream 仍开的情况下被兜底标成 `stop` / `aborted_effect_unknown`。对 `stop()` 这条路径历史上几乎无害（session 已被 delete、流已 finish，迟到帧到不了 UI）；**interrupt 故意不关流，把这条「从未被真正观察到」的兜底变成了主路径上的可见副作用**。

#### ② 互斥矩阵失败路径是否都释放锁 + 清理 pendingStop — **PASS**

锁模型：`SessionLockState` 增 `interruptInProgress`（`:78–82`）；`send`/`stop`/`interrupt` 均要求 idle，不做抢占。

`interrupt()` 在设锁与登记 `pendingStops` 之后用**单个 defer**（`:971–974`）：

```swift
defer {
    pendingStops.removeValue(forKey: session.sessionID)
    lockStateBySessionID[session.sessionID] = .idle
}
```

覆盖：成功 return、abort 抛错、forceDeny 抛错、transportClosed 后 rethrow（此时 cache 可能已被 transport 路径清过，defer 为安全 no-op）。  
**拿锁之前**失败的路径（unknown session、unsupported mode、session_locked）根本不设锁——正确。

测试钉住：

- forceDeny 抛错 → 锁释放 + 第二次 interrupt 不被假 `session_locked`（`InterruptTests` 约 `:499–574`）
- abort 抛错 → 同上 + `operation_completed(rejected, .interrupt)`（约 `:581–624`）
- interrupt 飞行中 send/stop → `session_locked`（约 `:452–495`）

相对 `stop()` 的「成功尾声手写清 + catch 再清」双点维护，interrupt 的单 defer 更不易漏。**未发现「抛错后锁永久卡住」类回归。**

**小注**：UI 层 `isInterrupting` 也有 `defer`（`SessionStore.swift:409–410`）+ 按钮 disable + 二次调用静默 return，与内核锁形成双保险。

#### ③ 强制 deny 定序是否与 `stop()` 等价 — **PASS**

interrupt 与 stop 都调用**同一个** `forceDenyPendingApprovalsBeforeStop`，且都在 `sessions.abort` **之前**（interrupt `:977–980`，stop `:1118` 一带）。  
测试 `testInterruptForceDeniesPendingApprovalBeforeAbort` 断言调用序为  
`[approval.resolve, sessions.abort]`，且 **从不**出现 `sessions.delete`。  
drain 轮次上限、在途 resolve 等待、失败落持久态再抛——与 stop 共享，无第二套语义。

#### ④ 有没有新的静默失败路径 — **FAIL / 有，且一条是用户可见的**

| # | 路径 | 静默程度 | 严重度 |
| --- | --- | --- | --- |
| A | **`pendingStops == nil` 时的 unowned 兜底**（`:2804–2826`）把迟到 aborted 帧标成 `.stop` +（phase=error 时）`aborted_effect_unknown` | UI **大声**说错话（不是静默丢弃） | **高** — 实拍已现 |
| B | `pendingStops` 仍在但 `affectedRunID` 不匹配 / 或 `terminalEmitted==true` → 帧被 else 静默丢弃 | 真正静默 | 中 — 匹配失败时 waiter 走超时（有 outcome），不是永久挂；terminalEmitted 时丢第二帧是有意去重 |
| C | `handleOperationCompleted` 对 **一切** `operationKind:.interrupt` outcome（含 `.rejected`）清 `isWaitingForReply`（`SessionStore.swift:745–747`） | 与 `interruptCurrentRun` 文档「失败不碰 isWaitingForReply」（`:391–394`）**直接矛盾** | 中 — abort RPC 失败但 run 仍在跑时，UI 会假装不在等，同时再画 `[停止失败]` |
| D | 超时路径只发 mirror、不发 turn_complete；依赖 C 清 UI — 有测 | 已覆盖 | 低（设计取舍） |
| E | CLI harness 只计 assistant delta、不计 thinking — 真内核「生成真的在飞被打断」测不干净 | 验证静默缺口 | 低（harness 问题，作者已诚实登记） |
| F | 视图层 `isWaitingForReply \|\| isInterrupting` **结构性不可测** | 回归可静默绿 | 中（实拍已部分覆盖停止按钮；`isInterrupting` 中间态未拍到） |

**没有发现** interrupt 在正常成功路径上把 session 静默 delete/finish 的通道。

---

## 已知缺陷根因裁定：`stop 已完成：aborted_effect_unknown` 系统行

### 实拍事实（已给定）

`evidence/shots/README.md` / `02-after-stop-interrupt-succeeded.png`：

1. `[操作] interrupt 已完成：outcome=succeeded`
2. 紧接着 `[操作] stop 已完成：outcome=aborted_effect_unknown， This operation was aborted`
3. 本轮 `stop()` 未跑：`sessions.delete = 0`

### 独立判定：**主会话怀疑成立；机制可证实，不只是「最可能」**

**来源链路（确定）**：

1. openclaw 对 abort 的真实样本形状（代码注释与 `EventMapping.swift:456–461` 写死）：  
   `lifecycle phase:"end", aborted:true` **常跟**  
   `lifecycle phase:"error", aborted:true, error:"This operation was aborted"`。

2. **第一帧 phase=end**（interrupt 等待窗口内，`pendingStops` 命中）：  
   `mapOpenclawAgentLifecycleToAbortTerminalEvents(..., operationKind: pending.operationKind /* .interrupt */, ...)`  
   → `outcome = succeeded`（phase=="end"）  
   → UI：`[操作] interrupt 已完成：outcome=succeeded`  
   → `terminalEmitted=true`，唤醒 waiter → `interrupt()` return。

3. **`defer` 立刻摘掉 `pendingStops` 并放锁**（`:971–974`）。  
   这是 interrupt 相对 stop 的关键差异：stop 成功后 session/流已死，迟到帧通常到不了观察者；interrupt **故意保活流**。

4. **第二帧 phase=error** 到达时：  
   - 第一分支要求 `pendingStops != nil && affectedRunID==runID && !terminalEmitted` → 失败（表已空）  
   - `else if pendingStops[ourSessionID] == nil` → **进入 unowned 兜底**（`:2804–2826`）  
   - `operationKind: .stop` **写死**（`:2819`）  
   - `operationID = "\(sessionID)-abort-\(runID)-unowned"`  
   - phase≠end → `outcome = .abortedEffectUnknown`（`EventMapping.swift:483`）  
   - `detail = data["error"]` = `"This operation was aborted"`（`:484`）  
   - `SessionStore.handleOperationCompleted` 渲染模板：  
     `"[操作] \(operationKind) 已完成：outcome=\(outcome)，\(detail)"`  
     → **精确匹配实拍字符串**。

5. **排除项**：  
   - 不是 `stop()`：会 delete；日志 delete=0。  
   - 不是 `resolvePendingStopForTransportClose`：那条读 `pending.operationKind`，会标 **interrupt** 且通常伴随 transport 关闭 / session_end。  
   - 不是 `emitOperationCompletedMirror` 的成功路径：成功 mirror 的 detail 为 nil，且 kind 为 interrupt。

### 对「`:2819` 不是漏改」判断的复核

scope-lock v1→v2 与代码注释说：该分支「按构造没有发起者信息，保持历史输出 `.stop`」。

- **作为代码考古**：正确——进入条件是 `pendingStops==nil`，确实读不到 PendingStop。  
- **作为产品决策**：在 interrupt 落地后**错误**——该分支不再是「理论上不会出现」：  
  **interrupt 成功返回后摘表 + 流仍开 + 内核常发第二帧 error**，使该分支成为**可预期的成功后副作用**。  
- 把「没有信息」填成 **`.stop`** 不是中性默认：它主动伪造一次用户从未发起的操作，且 outcome 看起来像出错（`aborted_effect_unknown`）。  
  中性做法应是：**直接丢弃** unowned aborted 帧，或标为未知/不渲染，而不是假装 stop。

### 用户可见后果

1. 成功停止生成后出现一条**错误标签 + 错误 outcome 观感**的系统行（像二次失败）。  
2. 与 rounds/0019「标签说谎比不显示更糟」同一族。  
3. 额外 yield 一组 `turn_complete(cancelled)`（fallback 同样返回两事件）——当前 UI 多半幂等，但污染事件流与未来观察者。  
4. **自动化测试未覆盖**「interrupt 终态后、pending 已清理、再注入 phase=error aborted 帧」——`InterruptTests` 在 pending 仍在时验证第一帧，**没有**复现 defer 之后的第二帧。

### 顺带纠正 SessionStore 注释中的机制描述

`SessionStore.swift:732–735` 写：`terminalEmitted` 已 true 时迟到帧会「落进防御性兜底」。  
源码事实：

- `pending` 仍在且 `terminalEmitted==true` → 走 **else 静默丢弃**（`:2827`），**不进**兜底。  
- 进兜底的充要条件是 **`pendingStops[session]==nil`**（表已摘）。  

实拍缺陷对应的是后者（defer 摘表），不是「terminalEmitted 仍占着表」。

---

## Decisions / deviations

- 未重跑 `swift test` / 真内核；采信 commit 声称的 123 帧回放与 `evidence/` 原文。  
- 未打开实拍 PNG 做像素级 OCR；字符串对齐以 README 转写 + 源码模板为准（模板与转写逐字段吻合）。  
- Verdict 取 **REWORK** 而非 FAIL：红线「保留会话」在内核与再发送意义上已成立；失败点是成功路径上的错误操作标签，属于必须修的产品缺陷，不是整轮作废。

---

## Open questions

1. openclaw 是否在所有 abort 路径都保证 end→error 双帧，还是仅部分模型/工具路径？实拍与注释都显示「常跟」，足以当主路径处理。  
2. unowned 兜底在 **仅 stop 时代**是否曾被 live 观察到？若从未，interrupt 保活流是第一次把它暴露给用户。  
3. `.rejected` 时清 `isWaitingForReply` 是有意牺牲（防永久转圈）还是文档/代码未对齐？需要产品裁定。

---

## Verdict

**REWORK**

红线中的「不删会话 / 不 finish 流 / 不 delete / 不改 stop 主体 / mode 门禁 / 锁释放 / deny 定序」审查通过；  
**成功 interrupt 后伪造 `stop`+`aborted_effect_unknown` 系统行**是已证实的用户可见缺陷，且根因就在被怀疑的 `:2819` 写死 `.stop` 与 defer 摘表的交互，必须修后再验。

---

## Next recommendation

1. **修 unowned 兜底（优先）**（任选其一，推荐 a）：  
   - **(a)** `pendingStops == nil` 时对 aborted lifecycle **完全不 yield**（丢弃）——与「本来就没有匹配的用户操作」一致；  
   - **(b)** 若必须 yield，`operationKind` 不得写 `.stop`；应使用不会渲染成「用户发起了 stop」的值，或 UI 对 `*-unowned` operationId 不画系统行。  
2. **加帧回放回归**：interrupt 成功（或 timeout 标记 terminal 后摘表）→ 再注入 `phase:error, aborted:true, error:"This operation was aborted"` → 断言 **零** `operationKind==.stop` 的 `operation_completed`，且消息列表不出现 `stop 已完成`。  
3. **对齐 rejected 与 isWaitingForReply**：要么 catch 路径不发会清 waiting 的 mirror，要么改文档承认「中止失败也强制退出等待态」，并接受 run 可能仍在生成的风险。  
4. 修完后用同一实拍剧本重拍 02：期望只剩一条 `interrupt 已完成：succeeded`（或 timed_out），**不得**再出现 stop 行。  
5. harness 若要证明「生成在飞被打断」，把 delta 统计扩到 thinking（作者已记，属验证债非本缺陷阻塞）。

---

## 附录：关键代码锚点

| 主题 | 位置 |
| --- | --- |
| `interrupt()` 本体 + defer 清锁/pending | `OpenclawGatewayKernelClient.swift:940–1051` |
| lifecycle 匹配 / unowned 兜底写死 `.stop` | 同文件 `:2777–2827` |
| phase→outcome（error→aborted_effect_unknown） | `EventMapping.swift:471–508` |
| UI 系统行模板 | `SessionStore.swift:718–723` |
| interrupt 成功清 waiting | `SessionStore.swift:745–747` |
| 与 catch「失败不碰 waiting」的矛盾 | `SessionStore.swift:391–394` vs `:745–747` |
| 实拍缺陷记录 | `.../evidence/shots/README.md`「实拍抓到的缺陷」节 |
| 真内核会话存活 | `.../evidence/real-kernel-interrupt.md` |
