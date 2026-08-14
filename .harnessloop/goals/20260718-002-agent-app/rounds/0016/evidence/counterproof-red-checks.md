# rounds/0016 破坏性反证的红检查（逐字输出）

规则（scope-lock 本轮纪律第 3 条）：**破坏性反证必须先看到红，并打印实际被破坏的内容。**

方法：把生产代码的对应"拆除点"改回**修前形态**，重新 `swift build --package-path app --product
frame-replay-tests` 并跑 `./app/.build/debug/frame-replay-tests`，记录逐字输出，然后原样还原。
每条反证的绿检查见同目录 `rounds0016-counterproofs-green.txt`。

基线：修复前 68/68 PASS；本轮新增 5 条测试后 **73/73 PASS**。

---

## 反证① —— 溢出 deny 的成功判据（T-096 第 1 项）

### ①-a 拆除点：把 `queue_overflow` 事件挪回 RPC **之前**（修前形态 = "提前宣称已自动拒绝"）

`emitApprovalRequestIfPossible` 溢出分支恢复
`emitApprovalBufferResolved(sessionID: sid, reqID: approvalID, reason: .queueOverflow)`
在 `beginQueueOverflowDeny(...)` 之前；`performQueueOverflowDeny` 恢复"成功只打印、失败只 WARN"。

```
  [FAIL] rounds/0016 反证① (T-096 第1项): 溢出 deny 的三种失败响应各须如实报错，且不得提前宣称已自动拒绝: [失败形态①：RPC 抛错] **提前宣称已自动拒绝**：deny 未被内核确认，却仍产出了 ["approval_buffer_resolved(ovf-rpc-throw,queue_overflow)"]；全部事件 = ["approval_request(ovf-rpc-throw-active)", "approval_buffer_resolved(ovf-rpc-throw,queue_overflow)"]
=== 结果: 72/73 PASS ===
```

### ①-b 拆除点：只拆"成功判据"（emit 位置不动）

`performQueueOverflowDeny` 里 `applied`/`approvalStatus` 恒当成 `true`/`"denied"`，catch 分支恢复
"只打一行日志 + 照发 `queue_overflow`"。

```
  [FAIL] rounds/0016 反证① (T-096 第1项): 溢出 deny 的三种失败响应各须如实报错，且不得提前宣称已自动拒绝: [失败形态①：RPC 抛错] **提前宣称已自动拒绝**：deny 未被内核确认，却仍产出了 ["approval_buffer_resolved(ovf-rpc-throw,queue_overflow)"]；全部事件 = ["approval_request(ovf-rpc-throw-active)", "approval_buffer_resolved(ovf-rpc-throw,queue_overflow)"]
=== 结果: 72/73 PASS ===
```

---

## 反证② —— FORCE_DENY_PENDING_KERNEL_ACK（T-096 第 2 项）

### ②-a 拆除点：去掉「只允许幂等 deny 重试」那道闸（持久态照记）

`respondApproval()` 关卡 2b 里的 `guard decision.outcome == .deny else { throw ... }` 删除。

```
  [FAIL] rounds/0016 反证② (T-096 第2项): 强制 deny 失败 -> FORCE_DENY_PENDING_KERNEL_ACK -> 人工 allow 必须被拒、只允许幂等 deny 重试: **FORCE_DENY_PENDING_KERNEL_ACK 下的人工 allow-once 本应被拒绝，却成功返回了**——一次已决定拒绝、只是没打成的审批被翻成了允许
=== 结果: 72/73 PASS ===
```

> 这条红就是 T-096 第 2 项真正防的事故形态：stop() 的强制 deny 没被内核确认，用户随后点"允许一次"
> 被完整放行，命令真的会执行。

### ②-b 拆除点：完全不持久化（修前形态 = 强制 deny 失败只抛错、什么都不记）

`recordForceDenyPendingKernelAck` 开头直接 `return`。

```
  [FAIL] rounds/0016 反证② (T-096 第2项): 强制 deny 失败 -> FORCE_DENY_PENDING_KERNEL_ACK -> 人工 allow 必须被拒、只允许幂等 deny 重试: **持久态缺失**：强制 deny 失败后必须显式持久化 FORCE_DENY_PENDING_KERNEL_ACK，实际查不到该 reqId；stop() 抛的错是 protocol mismatch: approval.resolve did not confirm denied status for reqId approval-force-deny-ack during stop() force-deny (got status: allowed)
=== 结果: 71/73 PASS ===
```

> 71 而不是 72：反证① 的两个"失败后应进入持久态"的子场景同时变红——它们本来就依赖同一份持久态。

---

## 反证③ —— approval.resolve 的有界等待 + 权威 terminal 结束 in-flight（T-096 第 3 项）

**这条反证的红形态是「整个测试进程永久挂死」**，不是一行 FAIL —— 那正是修前缺陷本身：
无界 `withCheckedThrowingContinuation` 只有"响应到达/transport 断开"两个唤醒源，网关还连着但这条
RPC 永远不回应答时，调用方永久挂起、in-flight 槽位永久占位、`stop()` 的 drain 收敛条件永远不成立。

### ③-a 拆除点：`respondApproval()` 换回裸 `request(method:"approval.resolve")`（无界）

```
RED③-a: *** 35s 后进程仍在运行 = 永久挂死 ***
RED③-a 日志最后一条测试结果行：
  [PASS] rounds/0016 反证① (T-096 第1项): 溢出 deny 的三种失败响应各须如实报错，且不得提前宣称已自动拒绝: 溢出 deny 的成功判据严格是 applied:true+denied；三种失败响应各产出一条如实的 evt.error 且**不**产出 queue_overflow
RED③-a 是否出现过反证③的任何 evidence 行：0 条
```

（对照：修后同一条测试 160ms 内完成，见绿检查 `[evidence][A]`。）

### ③-b 拆除点：有界等待保留，但 `handleApprovalTerminalSignal` 不再调用 `endApprovalResolveOnAuthoritativeTerminal`

子场景 A（只依赖有界等待）照常通过；子场景 B（有界等待刻意设为 600000ms，只能靠权威 terminal
结束在途）永久挂死——证明**这条修复不是被超时兜底顺带盖住的**，它自己有独立效果。

```
*** 35s 后进程仍在输出/挂起 —— kill ***
(已 kill，说明进程未自行结束 = 挂死)
--- 子场景 A（未被拆，应完成） ---
  [evidence][A] 桩收到 1 次 approval.resolve 且**从未返回**；有界等待 150ms 到期后 respondApproval 抛 审批 approval-bounded-wait：approval.resolve 超过有界等待上限 150ms 仍无应答——已结束该 in-flight（不永久占位），内核侧状态未知，不当作成功也不当作已拒绝（实测耗时 160ms）；in-flight 集合已清空 = []
--- 子场景 B（被拆）evidence 次数：0 ；整轮结果行次数：0 ---
```

> 采集方式说明：Swift 的 `print` 在 stdout 非 tty 时是块缓冲的，`kill -9` 会丢掉未 flush 的输出，
> 因此 ③-b 用 `python3 -c 'pty.fork()'` 起一个伪终端采集（行缓冲），才能看到"A 完成、B 挂死"这个
> 分界。③-a 没有这个需要——它连 A 都到不了，最后一条 flush 出来的结果行就是反证① 的 PASS。

### ③-c 拆除点（**反向红**）：按 T-096 字面「权威 terminal」的**宽读法**实现

`endApprovalResolveOnAuthoritativeTerminal` 去掉 `guard status == "expired"`，即"任何权威 terminal
都结束在途决议"。这是本轮实现过程中先写出来、随后逐行读 openclaw 源码才发现**会打断 live 主链**的
版本，写成回归钉死：

```
  [FAIL] rounds/0016 回归 (反证③ 配套): status:allowed 的 terminal 先于 RPC 响应到达时，不得打断用户自己那条在途决议: **live 主链被打断**：用户点『允许一次』本应成功，却因为先到的 terminal(allowed) 广播帧被判成 审批 approval-allowed-terminal-race：决议在途期间内核给出权威终态 status=allowed reason=user——本次决议不可能被兑现，已结束该 in-flight
=== 结果: 73/74 PASS ===
```

依据（源码实读，不是推断）：`kernels/openclaw/src/gateway/server-methods/approval.ts:491-540`，
`approval.resolve` handler 的顺序是 `applyApprovalDecision(...)`（内部 `emitLifecycle` 广播
terminal 事件）**先**、`respond(true, {applied, approval})` **后**，两者走同一条 WS 连接——所以
用户点"允许"之后，`session.approval(phase:terminal, status:allowed)` 这一帧**先于**这次 RPC 的
响应到达我们的 socket。宽读法会把用户自己那条尚在途的决议判死：**命令实际执行了，UI 却报错**。

---

## 反证④ —— active terminal 后的 UI 同步（T-096 第 4 项）

### ④-a 拆除点：适配器不再把"active 已被内核判超时"告诉调用方

`handleApprovalTerminalSignal` 里 `makeApprovalTimeoutErrorEvent` 的产出被短路（修前形态：
这条内核信号只在适配器内部驱动 FSM，一个字节都不外发）。

```
  [FAIL] rounds/0016 反证④ (T-096 第4项): active timeout -> 先清旧卡（evt.error/approval_timeout）再呈现提升项（#2 在 UI 上浮现）: active 超时后应恰好产出两条事件（先 evt.error(approval_timeout) 再 approval_request(ui-b)），实际 1 条：["approval_request(ui-b)"]
=== 结果: 72/73 PASS ===
```

### ④-b 拆除点：`SessionStore` 恢复"无条件 append"（不先清旧卡）

```
  [FAIL] rounds/0016 反证④ (T-096 第4项): active timeout -> 先清旧卡（evt.error/approval_timeout）再呈现提升项（#2 在 UI 上浮现）: **先清后呈现被破坏**：新 approval_request 到达时旧卡必须先被清掉，队头才会是提升项；实际卡片列表 ["ui-a", "ui-b"]（队头 = ui-a）
=== 结果: 72/73 PASS ===
```

> `SessionDetailView` 只渲染 `pendingApprovals.first`——队头是 `ui-a`（已死的那张卡）就意味着
> **提升上来的 #2 在界面上根本不浮现**，这正是 T-096 第 4 项点名的失败态。

---

## 还原核对

红检查全部结束后，两个被改过的文件用红检查前的副本原样还原，重跑：

```
Build complete!
=== 结果: 73/73 PASS ===
```
