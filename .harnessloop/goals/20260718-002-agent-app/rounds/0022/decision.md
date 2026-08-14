# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-115-grok-output.md
- Reviewer: grok（grok-4.6）via hopper T-115（单路，按 scope-lock）
- Review verdict: **PASS_WITH_NOTE**
- Review digest: 9da5cdb4a061599551cf6cfc1cf13154bb8028e7950d8b3bd5973cb364d881df
- Acceptance evals: none — 本轮为 runner 判定机制改造，无 runtime eval 台账
- Acceptance evals detail: n/a
- Active goal: 20260718-002-agent-app
- Active round: 0022
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-14

## Reason

**把金标 parity 套件里那个会静默失效的开关修掉了**——DEGRADED 判定由**硬编码方法名单**
改为**运行时发现**（跑 timeline，client 抛 `notImplemented` 才降级，其它任何结果都是真实
PASS/FAIL），两端同改。

## 它立刻兑现了价值

| 端 | 改动前 | 改动后 |
|---|---|---|
| Swift | 12 PASS / 0 FAIL / **1 DEGRADED**，exit 0 | 12 PASS / **1 FAIL** / 0 DEGRADED，**exit 1** |
| C# | 12 / 0 / 1（理由来自查表） | 12 / 0 / 1（理由**运行时捕获**，且执行到失败点前的真实 RPC 都出现了） |

**那条 fixture 此前从未被执行过。** 现在 Swift 真跑了它并给出三条实质 mismatch，
而 C# 仍诚实降级——**Mac↔Windows 的能力分歧第一次成为机器判据**，两端摘要各自可读出。

## 最重要的正确性属性

**不能把真失败洗成 DEGRADED。** 实现方用单一收口点（`noteRealFailure`/`NoteRealFailure`）
只匹配字面的 `notImplemented`，明确排除语义相近的 `rpcRejected(code:"unsupported_interrupt_mode")`。
本轮的 FAIL 正是靠这条区分才没被误降级。

实现过程中它自己发现并修了一个真 bug：`interrupt`/`respondApproval` 未登记 RPC 门，
导致 fixture 里的 `mock_response` 会让 runner 结构性崩溃（`malformed`），
**把一次真实拒绝洗成崩溃**——与本轮要修的是同一族。

## 主会话复核时又抓到一处同族残留

摘要路径里仍有一份硬编码三元素集合（`watchedMethods`/`WatchedMethods`）。
它**不参与判定**，只决定摘要点名谁——危害小得多，但**同样会过时**：
实现第四个方法，摘要就不再点名它。已改为**按结果筛选**（`outcome != passed`），
彻底不需要清单。复核：两端残留 **0**。

## 本轮暴露、但不在本轮修的

1. **`respondApproval` 零 parity 覆盖** —— 它 rounds/0015 就实现了，
   而三条 `approval/*` fixture 只测事件侧（`createSession`/`subscribe`），
   **从不调用决策路径**。Mac 与 Windows 在审批决策上可以完全分道扬镳而无人发现。
   **这比名单过期严重得多。**
2. **那条 FAIL 是实现偏离规格，不是 fixture 过时** —— 见下。

## 关于那条 FAIL 的裁定（读规格原文坐实）

实施方推测「规格后来简化了，是 fixture 带着过期假设」。**主会话读原文后判定：方向相反。**

`d1-kernelport-spec-v3-6.md`（`design_status: confirmed`，2026-07-23，**晚于** fixture
转录的 D4 v2.2）§9.3 完整互斥矩阵：`interrupt_in_progress` 遇 `send()`/`interrupt()` 才是
reject，**遇 `stop()` 是「特殊仲裁」**。且 steer 与 cancel 各有专条，规则相同：

> **「等待，不抢占」**：适配器**等待该 RPC 返回**（无法从中截断），返回后 interrupt 按既有
> 规则终态化，锁转 `stop_in_progress`，`stop()` 序列正常执行。等待超时是 **`stop()` 自己的**
> `timed_out`，不是 interrupt 的第三个终态。

规格的演进方向是**越来越细**（v3.2 补全矩阵 → v3.3 补 steer/cancel 规则 → v3.6 确认），
不是简化。rounds/0020 的注释也自承「不做优先级仲裁」。

**因此 rounds/0020 的一刀切 `session_locked` 对两种模式都违反 confirmed 规格**，
而它加的 `testSendAndStopRejectedWhileInterruptInFlight` **一半对一半错**
（send 被拒对、stop 被拒错）——**又一次「测试把错误行为钉死」，但这次仲裁者毫无歧义。**

## 独立复核（全部主会话自己跑）

| 判据 | 结果 |
|---|---|
| Swift runner 构建/运行 | exit 0 ／ exit **1**（12 PASS / 1 FAIL / 0 DEGRADED） |
| C# runner 构建/运行 | exit 0 ／ exit 0（12 / 0 / 1，理由运行时捕获） |
| 硬编码清单残留 | **0**（含摘要路径） |
| app 无回归 | `swift build` exit 0 ／ 帧回放 **163/163** |
| fixture JSON 未改 | `git diff --stat` 确认 |

## Open Questions Remaining

1. **`respondApproval` parity 覆盖为零** —— 下一轮补 fixture。
2. **C# 端三个方法仍是桩** —— 本轮**刻意不实现**（红线：不为了让数字好看掩盖分歧）。
3. **rounds/0023 需同时修仲裁规则** —— 用户已裁定实现 `steer`；读规格后发现
   连带必须修 `stop()` 遇 `interrupt_in_progress` 的仲裁（两种模式），并改正那条测试。

## 评审核实了主会话的裁定，并修正了其中一处因果链

**裁定成立**：评审逐行核对 `d1-kernelport-spec-v3-6.md`（`design_status: confirmed`）§9.3 的矩阵与
steer/cancel 两条专条，确认「等待，不抢占」；核对实现原文自承「不做优先级仲裁」；
确认那条把偏离锁成绿的测试存在。**fixture 没有过时，是实现相对 confirmed D1 的缺口。**

**但主会话把两条偏离并成了一句**。评审指出：本次 FAIL 的**近因不是**「stop 抢占了在途的
interrupt」——**steer 在拿锁之前就被 mode guard 拒了**（`:946`，guard 故意放在锁之前），
所以 interrupt 压根没进过 `interrupt_in_progress`。规格偏离实际有两条：

1. **本次已实证**：`interruptModes` 该三者俱全，实现只做了 `cancel`。
2. **代码里存在、本次未观察到**：即便 steer 落地，锁矩阵仍是「非 idle 一律 reject」，
   与 §9.3 相反。**要看到这条，必须先有一次真正进入 `interrupt_in_progress` 的 steer/cancel。**

**这个区分直接影响 rounds/0023 的验收设计**：光实现 steer **不会自动暴露第二条偏离**，得专门构造。

## 收盘前按评审建议补的一刀

两端 runner 里一段过期文案仍在说「该 D2 方法本轮 **SG-5 未实现**」——而实现状态自本轮起
由运行时发现判定，该文案不该再声称任何实现状态。已改写并重跑两端，行为不变、残留 0。

## 本轮的意外产出：hopper 的一个真缺陷（已修）

**评审本身超时三次**，最后一次颗粒无收。追查后定位到 hopper：

vendor 可声明 `bufferedOutput: true`（grok/claude），意为「我端到端缓冲，跑完前不吐字节，
别用 idle 计时器杀我」。该标志**被 `hopper-runner` 尊重**（`idlePoll = (idleMs > 0 && !bufferedOutput)`），
**但 `subprocess.js` 零命中**——而 `hopper-dispatch` 走的正是后者。于是 idle 计时器 spawn 时武装、
永远等不到 data 事件重置，**必在 `DEFAULT_IDLE_TIMEOUT_MS = 180_000` 处开枪**。

**实证**（同一任务、同一 vendor，只改 idle 上限）：

| | 结果 |
|---|---|
| 默认 idle 180s | 180024ms 被杀，**产物 0 字节** |
| `HOPPER_IDLE_TIMEOUT_MS=1500000` | **`Status: success`，399802ms（6.7 分钟），产物 19883 字节** |

该评审真正需要 6.7 分钟，是 180s 的两倍多——**所以它每次都必然被杀**，而
`applyTaskTypeFloor` 给 review 类型抬到的 30 分钟 ceiling **永远轮不到生效**。

**形状**：缓解手段**存在、有文档、甚至挂了具名 issue**（`ISSUE-grok-claude-buffered-output-idle-falsekill`）
——**只是实现在两条通路的其中一条上**。与本轮修的 parity 名单、rounds/0021 的 `:2819`
写死 `.stop`、`focusMainWindow` 静默 return 完全同族。

已修（`subprocess.js` + `dispatch.js` + vendored 副本 + 6 条新测试），
`npm test` **1424 tests / 1422 pass / 0 fail / 2 skipped**，exit 0。
实施方**未 bump 版本**并给了理由（CHANGELOG 是版本键控、无 Unreleased 节，
在禁止提交的前提下 bump 会产生无处安放的孤儿版本）——判断合理，**push 前再 bump**。

实施方还发现**同族的第二处分歧**（mimo 的 `idleHeartbeatRe` 同样只被 `hopper-runner` 消费），
如实标注未修。
