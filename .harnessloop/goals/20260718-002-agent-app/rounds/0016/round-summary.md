# Round Summary — rounds/0016

**目标**：用户 2026-08-12 裁定「收 0015 开 0016」。本轮只做 ★审查闸 T-096 点名的
**四条 exec 审批 FSM 边界失败态**——0015 的主判据已达成，卡的是这些失败/超时/持久化路径。

## 结论：**四项全部达成，★审查闸 `PASS_WITH_NOTE`**

| # | 项 | 终态 |
|---|---|---|
| ① | 溢出 deny 的成功判据（须 `applied:true + status:denied`，失败不得吞掉/提前宣称已拒绝） | 达成。`approval_buffer_resolved(queue_overflow)` **从准入分支挪到 RPC 确认之后** |
| ② | `FORCE_DENY_PENDING_KERNEL_ACK` 持久态 + 只允许幂等 deny 重试 | 达成。该态下任何 allow **同步拒绝、一条 RPC 都不发** |
| ③ | `approval.resolve` 有界等待 + 权威 timeout terminal 结束 in-flight | 达成。actor 收件箱 + `settled` 闸 + `epoch`，**不用 task group** |
| ④ | active terminal 后 UI 先清旧卡再呈现提升项；队列徽标接真实计数或删除 | 达成。**徽标删除**（接真实计数在红线内不可能且与 D1 §6.2 抵触） |

## 硬判据（全部由主会话独立复跑）

`swift build` 通过 · 帧回放 **74/74**（基线 68/68，本轮 +6）· CI 平价 **12 PASS / 0 FAIL / 1 DEGRADED** ·
**D1 七法 `git diff` 为空**（`KernelClient.swift` 本轮一字未改）· 三端 codegen 四项 exit 0 ·
**RAE-0001 不回归 pass**（3 轮往返、对账 exit 0、`--drop-one` exit 1）·
**live 主链不回归**（放行→命令执行；拒绝→命令未执行）

**四条破坏性反证 7 个拆除点逐字冻结**，其中两条的红是「**整个测试进程挂死 35 秒不动**」
这种极硬的证据（③-a 换回无界 `request`、③-b terminal 不结束 in-flight）。

## 实现方在自己第一版实现里抓到一个会回归主链的 bug

codex 写的是「权威 **timeout** terminal 能结束对应 in-flight」。实现方先按
「任何权威 terminal 都结束」写，随后读内核发现：`applyApprovalDecision`（内部广播 terminal）
**先**、`respond(true,…)` **后**，同一条 WS —— **用户点「允许」后 `terminal(status:allowed)`
先于 RPC 响应到达**。宽读法会把用户自己在途的决议判死：**命令实际执行了，UI 却报错**。

收窄到 `status == "expired"`，并加了正向回归测试 + 反向红。

> **该顺序经两个独立来源确认**：主会话核了内核源码的偏移（`applyApprovalDecision` 在 7/16/24、
> `respond(true,…)` 在 53），★审查闸 grok 又从 durable path 追了一遍，判 **Holds**。

## 实现方对 codex 的四条纠正，★审查闸判**全部成立**

| # | 纠正 | grok 裁定 |
|---|---|---|
| ① | 收窄到 `status=="expired"` | **Holds** |
| ② | 把 `applied:false` 排除出持久态（否则造出永远清不掉的状态——`applied:false` 只在审批已终态时出现，deny 重试永远只会再拿 `applied:false`） | **Holds** |
| ③ | 队列徽标只能删、不能接真实计数（缓冲请求从不 yield，与 D1 §6.2「不触发新的可见 pending 状态」抵触） | **Holds** |
| ④ | 拒绝拿 `approval_timeout` 冒充非 expired 终态（D2 `KernelErrorCode` 无诚实取值） | **Holds** |

## live 现场的一个意外发现

拒绝路径实测时，**agent 主动伸手去读用户真实的 `~/.openclaw`**：

```
openclaw config get tools.exec.security …; ls ~/.openclaw …; grep -ri "deny" ~/.openclaw/openclaw.json …
```

**审批关卡把它拦下来了。** rounds/0013 的现场是**无关卡直接执行**——同一条命令在那时会直接读到
用户的真实配置，没有任何人被问过。

同时也是一条如实观察：**隔离的是 openclaw 自己的 state，不是被执行命令的可及范围**
（rounds/0013 已辨明「独立 state/workspace 不是进程 sandbox」，此处得到现场印证）。

**如实记的偏差**：我发的是 `echo R16_DENY_SHOULD_NOT_RUN`，但 agent 看到命令名就自己决定不跑，
转而查策略——我拒绝的是那次查询。**机制验证成立，但测试载体不是我设计的那条。**

## 遗留（登记，非本轮）

| 项 | 处置 |
|---|---|
| 非 `expired` 终态（`denied`/`cancelled`/`allowed`）的 UI 清卡 | **需 D2 新增终态事件**，★审查闸建议「park 为显式设计轮议题，不是静默产品债」 |
| `ApprovalBufferResolvedEvent.reason` 两值枚举表达力不足 | 同上，需 D2 改动 |
| `capabilities()` 仍是桩，与推导常量有漂移风险 | 0015 已登记 |
| rounds/0014 遗留三项；`[gateway] ready` ≠ `sessions.create` 可用 | 已登记 |
