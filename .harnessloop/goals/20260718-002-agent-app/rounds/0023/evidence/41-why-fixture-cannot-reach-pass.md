# 为什么 `soft-steer-then-stop` 在本轮约束下不可能转成 PASS（而不是 FAIL→PASS）

> **本文档已被后续事件超越，原样保留作审计对照，不代表最终状态。** 本文档写于 Scope-Lock v1
> 约束下（`app/contracts/**` 禁止改动）——分析本身成立，也正是这份分析促成了用户裁定
> Scope-Lock v1→v2 扩围（见 `scope-lock.md` 底部"Scope-Lock 修订 v1 → v2"一节）。v2 扩围后，本文档
> 点名的两条阻塞（fixture 缺 `send()`、runner 表缺 `req.interrupt`）**已被直接修复**，另发现并修复
> 了第三条同源问题（`performClientCall` 的 stub 注册同样按 mode 二选一，未注册 `chat.send`）。
> `soft-steer-then-stop` 现已 **PASS**（13/13，0 FAIL，0 DEGRADED）。完整过程见
> `80-v2-summary.md`，最终 runner 输出见 `60-v2-FINAL-parity-runner-run.log`。

## 结论先行（v1 阶段，历史记录）

`soft-steer-then-stop-waits-not-preempts` 在实现 steer + 仲裁修正**之后仍然 FAIL**——但**三条
mismatch 里换掉了两条**，第三条的措辞不变但根因换了。这不是本轮实现有缺陷，是这条金标 fixture 与
`app/contracts/**`（本轮不可改）两者本身，在"不改 fixture、不改 runner"的约束下**结构性无法同时满足
它自己写下的全部断言**。证据见 `22`/`23`（after 状态构建+运行）对照 `02`/`03`（before 状态）。

## before / after mismatch 对照

| mismatch | before（rounds/0022 状态，evidence/03） | after（本轮，evidence/23） |
|---|---|---|
| `expect_outbound(steer1)` | `swift-runner 未登记『req.interrupt』对应的 openclaw RPC 方法名` | **一字不差，仍然是同一条**——`expectOutboundMethodTable`（`SwiftFixtureRunner.swift:774-779`）只登记了 `req.createSession/send/subscribe/stop` 四项，没有 `req.interrupt`。这张表在 `app/contracts/` 下，本轮禁止改。**这一条 mismatch 与 steer 是否实现、是否进入 interrupt_in_progress 完全无关——无论我怎么实现，这一条都会命中。** |
| `assert_state@t=25.sessionLock` | `期望 interrupt_in_progress，实际 stop_in_progress` | **仍然是这句话**，但近因换了：before 是"steer 在拿锁之前被 `unsupported_interrupt_mode` 拒绝"（T-115 已指出）；after 是"steer 在拿锁之后、真正设置 `interruptInProgress` 之前，被 `no_active_run_for_steer` 前置校验拒绝"——见下节。**两次都是"零 RPC 派发、锁全程未离开 idle"，表现完全一致，但触发的 code 不同**（`unsupported_interrupt_mode` → `no_active_run_for_steer`）。 |
| `expected.pendingOperations.steer1` | `期望 submitted，实际 nil` | 同上，不变——interrupt() 从未铸造 operationId，`pendingOperations` 里自然没有这个键。 |

`13/13` 真实执行、`12 PASS / 1 FAIL / 0 DEGRADED`——tally 与 before 完全相同，其余 12 条 fixture 零回归
（`evidence/23` 摘要区）。

## 根因：fixture 的 timeline 从未建立"活跃 run"

`operation-outcome/soft-steer-then-stop.json` 完整 timeline：

```
t=0  createSession(c1)
t=0  expect_outbound(c1, req.createSession)
t=5  mock_response(c1)
t=10 client_call(sub1, subscribe)
t=15 client_call(steer1, interrupt, {mode:"steer", input:"..."})
t=15 expect_outbound(steer1, req.interrupt{mode:"steer"})
t=25 client_call(stop1, stop)
t=25 assert_state(sessionLock == interrupt_in_progress)
t=65 mock_response(steer1, {operationId:"op-steer-1", outcome:"submitted"})
t=66 assert_state(sessionLock == stop_in_progress)
```

**从未出现 `client_call: send`**。D1 v3.6 §6.1(a)（本轮 authority spec）明文要求 `interrupt(mode:"steer")`
在**本地快照**（`activeRunIds`）为空时**同步 reject**（`no_active_run_for_steer`），**发生在锁转移/
operationId 铸造之前**：

> "前置同步校验（发生在 operationId 铸造之前，走 §9.1 KernelPortRejectionCode 通道，不产生
> OperationOutcome）：调用前先查本地快照的 `activeRunIds`——若为空，同步 reject
> （`no_active_run_for_steer`），不发起 RPC，不铸造 `operationId`"

这条前置校验是 v3.2 才正式钉死的规则（对照 `d1-kernelport-spec-v3-6.md:502` "v3.2 澄清"一句）——
金标 fixture 本身"逐字转录自 D4 跨平台架构 v2.2 §4.3"，**早于**这条前置校验被钉死，其作者写这条
timeline 时关注的是"§9.3 锁仲裁时序"，完全没有考虑"steer 需要先有一个活跃 run 才能被调用"这个前提
（fixture 全程没有 `client_call: send`，`mock_event` 也没有，本地 `activeRunIDsBySessionID` 在
`interrupt(steer)` 被调用的那一刻必然为空——这是 timeline 结构本身决定的，不是运行时偶然）。

一个**完全遵照 confirmed v3.6 规格**实现的 `interrupt(mode:"steer")`，跑在这条 fixture 上，**必然**
在 t=15 同步 reject（`no_active_run_for_steer`），零 RPC 派发，锁全程停在 idle——`stop()` 在 t=25
到达时看到的是 `idle`，正常走既有路径直接转 `stop_in_progress`，与 before 状态呈现的
`assert_state@t=25` 失败**表现完全相同**（"期望 interrupt_in_progress，实际 stop_in_progress"），
只是这次锁没进 `interrupt_in_progress` 的原因，从"mode 不支持"换成了"没有前提条件"。

## 两条独立、各自单独就足以挡住 PASS 的理由

1. **`expectOutboundMethodTable` 缺 `req.interrupt`**——这是 runner 自身的登记缺口，与 steer 是否
   真的执行完全无关：即便 fixture 补上 `send()`、即便 steer 真的成功发出 `chat.send`，`checkExpectOutbound`
   函数第一步 `guard let expectedMethod = expectOutboundMethodTable[expectedType] else { ...
   appendMismatch(...) }` 依然会先于任何进一步比对命中——`req.interrupt` 这个 key 根本不在表里。
   这一条**单独就足以**保证至少 1 条 mismatch，与本轮任何实现选择无关。T-115 评审的 Open questions
   #1 已经预见到这个缺口（"steer 的真实 RPC 按规格是 `chat.send` 不是 `sessions.abort`，表项不能
   简单抄 stop"），但没有下文——本轮实测坐实了它。
2. **fixture 缺 `send()`，spec 缺前置校验豁免**——见上节，两者叠加使得"steer RPC 真的在途"这个
   fixture 想要展示的场景，在"忠实实现 confirmed spec"的前提下**永远不会发生**。

**两条中任何一条单独存在都足以让 PASS 不可达**，本轮同时踩中两条。修复路径都落在 `app/contracts/**`
（`expectOutboundMethodTable` 加一行 + fixture timeline 补一个 `send()`/`mock_response` 对），均在
本轮 scope-lock 的 Disallowed Changes 明文范围内（"`app/contracts/**`（含所有 fixture JSON 与三端
runner）"），不属于本轮可动的文件。

## 我验证过的替代路径，为什么都不成立

- **换一个"更像 sessions.abort"的 RPC 让它命中现成的 stub**：会违反 D1 §6.1(a)/§5 的 RPC 选择（详见
  交付报告"RPC 选择"一节的源码引用）——`sessions.abort`/`sessions.steer` 都不含 `queueMode`/`deliver`
  语义，选它们意味着放弃"真正实现 steer 的软注入语义"，本末倒置。且即便这么做，`expectOutboundMethodTable`
  的缺口依然存在，仍然拿不到 PASS——多输一层正确性，换不来一分。
- **放宽"本地快照为空即拒绝"的判据**（比如把"从未观察到"当成"可能有"而不是"确定没有"）：与 spec
  原文"若为空，同步 reject"逐字相反，是我不愿意做的"绕开问题而不是解决问题"。
- **在 `interrupt()` 内部悄悄给 fixture 场景开后门**（比如识别某个 session 从不校验）：明确违反
  scope-lock 红线"不得改 fixture JSON 让它迁就实现"背后的精神——这等价于反过来让*实现*迁就 fixture
  的一个已知过时前提，同样不诚实。

## 我做了什么来弥补

金标 fixture 本身不可能在本轮达到 PASS，但**它想验证的机制本身**（interrupt_in_progress 真进入、
stop() 等待不抢占、steer 二态收敛、锁转 stop_in_progress、stop 序列正常完成）**已经被独立的
frame-replay 单测完整、真实地验证过**——`SteerTests.swift` 的
`testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted`
逐步骤复刻了这条 fixture 的并发结构（真实 send() 建立 active run → interrupt(steer) 真实在途 →
stop() 到达时观察锁仍是 `interrupt_in_progress` → steer 收敛 submitted → 锁转 stop_in_progress →
stop() 正常完成），用真实并发（不是摆拍）驱动，且通过了破坏性反证（见
`40-counter-proof-summary.md` 第 3 行）。这条测试证明的不是"这条金标 fixture 能不能过"，是"§9.3
仲裁 + steer 二态这套机制本身是不是真的做对了"——答案是做对了，只是这条特定的金标 fixture 因为自己
的历史局限（早于 v3.2 前置校验规则）与 runner 自己的登记缺口，在本轮不能改 `app/contracts/**`
的前提下无法被用来展示这一点。

## 给下一轮的建议（不在本轮执行）

1. `expectOutboundMethodTable` 加一行 `"req.interrupt": <视 mode 而定的方法名>`——steer 是
   `"chat.send"`，若未来实现 `abort_and_resend` 则是 `"sessions.steer"`，两者不能共用一行（同一个
   D2 方法 `req.interrupt` 对应不同底层方法，取决于 `payload.mode`，需要比现有"D2 方法名 → 固定
   底层方法名"一对一映射更复杂的登记方式）。
2. 在 `soft-steer-then-stop.json` 的 timeline 里，`t=15` 的 `client_call(steer1)` 之前插入一次
   `client_call: send` + `mock_response`（仿照本文件其余 fixture 的既有写法），让本地 `activeRunIds`
   在 steer 被调用时非空，使 fixture 的场景与 confirmed v3.6 §6.1(a) 的前置校验相容。
