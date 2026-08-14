# T-115-grok — rounds/0022 金标 parity「运行时发现」对抗评审

审查对象：`app/contracts/d2/fixtures/` 当前未提交工作区（5 个文件）。只读，未改任何被审文件。
范围契约：`.harnessloop/goals/20260718-002-agent-app/rounds/0022/scope-lock.md`。
对照证据：同目录 `evidence/00`–`18`。规格原文：`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md` §9.3（`design_status: confirmed`）。

假设（一行）：`evidence/13`/`14` 是摘要改按结果筛选之后的权威运行输出；`02`/`03` 是初版摘要仍带方法名清单时的中间产物。

---

## Summary

两端 runner 已删掉执行前硬编码方法名单（`degradeReason` / `DegradeReason`），改为跑完整条 timeline，仅当真实 client 抛出字面 `notImplemented` / `NotImplemented` 才整条 DEGRADED。Swift 上唯一的 interrupt fixture **确实被执行了**，并以 3 条 mismatch 记 FAIL（退出码受影响）；C# 上同一条仍 DEGRADED，但理由已变成运行时捕获的 `NotImplemented`（`id=steer1`），两端摘要分歧可见。`noteRealFailure` / `NoteRealFailure` **不会**把 `rpcRejected(code:"unsupported_interrupt_mode")` 洗成 DEGRADED——本次 Swift FAIL 就是这条路径的实证。残留问题不在判定主路径，而在 `expectOutboundMethodTable` 这份仍按四方法查表的翻译层、以及「整条跑完再 DEGRADED」会吞掉同 fixture 里后续真失败。

## Files touched

评审本身未改文件。被审工作区改动：

- `app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift` — 删除静态 `degradeReason`，新增 `noteRealFailure` + 三条方法真派发
- `app/contracts/d2/fixtures/swift-runner/SwiftRunnerMain.swift` — 摘要改为按 PASS/FAIL/DEGRADED 结果筛选
- `app/contracts/d2/fixtures/csharp-runner/CSharpFixtureRunner.cs` — 镜像 Swift 的运行时发现
- `app/contracts/d2/fixtures/csharp-runner/CSharpRunnerMain.cs` — 同上摘要改写
- `app/contracts/d2/fixtures/README.md` — 记录 rounds/0022 分歧与实测 FAIL 明细

`git diff --name-only -- app/contracts/d2/fixtures/` 仅上述 5 个文件；fixture JSON 与两端 kernel-client 本体未改，符合 scope-lock。

## Acceptance verification (8/8)

对照 scope-lock「Verification Commands Or Checks」，以仓内证据文件为准（本任务只读，未重跑二进制）。

| # | 标准 | 结果 | 证据 |
|---|---|---|---|
| 1 | Swift runner 构建 | PASS | `evidence/04-swift-build.log` 仅既有 warning，无 error；后续 `02`/`13` 已跑出完整 13 条 |
| 2 | C# runner 构建 | PASS | `evidence/05-csharp-build.log:6` `Build succeeded.` |
| 3 | 名单已消失 | PASS（可执行路径） | `evidence/18-scopelock-verification-no-hardcoded-list.txt`：live 字面量检查 `exit=1`（无匹配）。独立复跑 `command grep`：`degradeReason`/`DegradeReason` 函数体已删，`["interrupt","respondApproval","capabilities"]` 只剩注释/README 历史叙述 |
| 4 | Swift interrupt/respondApproval 不再 DEGRADED | PASS | 基线 `00`：`[DEGRADED] soft-steer-then-stop-waits-not-preempts`（静态名单文案）。改后 `13`：`12 PASS / 1 FAIL / 0 DEGRADED`，该条 `[FAIL]`。仓内无任何 fixture 的 `client_call` 使用 `respondApproval`（README 已登记覆盖缺口） |
| 5 | C# 三者仍 DEGRADED，理由来自真实 `NotImplemented` | PASS | `03`/`14`：`[DEGRADED] … id=steer1 … 抛出 NotImplemented：not implemented: interrupt() 本轮 TODO 桩`。对照 `OpenclawGatewayKernelClient.cs:421` 无条件 `throw NotImplemented` |
| 6 | 分歧可见 | PASS | Swift `13`：`真实执行 13/13`，关注列表 `[FAIL]`。C# `14`：`真实执行 12/13`，关注列表 `[DEGRADED]` + 完整 NotImplemented 理由 |
| 7 | app 无回归 | PASS（采信既有证据） | `evidence/09-frame-replay-tests.log` 末行 `=== 结果: 163/163 PASS ===` |
| 8 | 破坏性反证命中 > 0 | PASS | `10-counter-proof-swift-injected-run.txt:32`：`ROUNDS-0022-COUNTER-PROOF: 静态名单命中，未执行 timeline 就整条跳过`。`12-counter-proof-checksums.txt`：还原后四文件 sha256 与注入前逐字节相同 |

## 四问（本评审核心）

### ①「运行时发现」是否还有残留查表？

**DEGRADED 判定主路径：没有。** 摘要/报告路径：初版有，现已清掉。翻译层：还有一份**不决定 DEGRADED、但会污染 FAIL 理由**的查表。

可执行判定链：

1. `degradeReason(for:)` / `DegradeReason` 已删除（Swift 原 ~941 行、C# 原 ~1008 行）。
2. 唯一置位点是类型匹配，不认方法名：
   - Swift `SwiftFixtureRunner.swift:313-316`：`guard case KernelClientError.notImplemented(let detail) = error else { return }`
   - C# `CSharpFixtureRunner.cs:188-196`：`error is KernelClientException kce && kce.Kind == KernelClientErrorKind.NotImplemented`
3. 入口只有失败记账：`onCallThrew` / `onStopShapedThrew`（及 C# 镜像）。成功路径不能 DEGRADE。
4. 摘要：当前 `SwiftRunnerMain.swift:99` / `CSharpRunnerMain.cs:105` 是 `results.filter { not passed }` / `Where(r => r.Outcome != Passed)`，不引用任何方法名。`evidence/17-reporting-fix-before-after.diff` 证实主会话抓到的残留清单（`--- interrupt / respondApproval / capabilities 覆盖情况 ---`）已从 `02`/`03` 改成 `13`/`14` 的按结果筛选。独立对照当前源码：那段标题已不存在。

**仍在的查表（N1，中）**：`expectOutboundMethodTable` / `ExpectOutboundMethodTable` 仍只有四项（`req.createSession/send/subscribe/stop`）。

- Swift `SwiftFixtureRunner.swift:768-779` 注释声称「三个方法的翻译层目前不拦截/不记录出站 RPC（刻意没有注册 `testSupportStubRPC`）」——**与同文件 680-684 行矛盾**：`interrupt` 分支**已经**注册了 `sessions.abort` stub 并 `recordOutbound`。
- C# `CSharpFixtureRunner.cs:814-816` 注释更糟，仍写「interrupt/respondApproval/capabilities 对应的 fixture 已被整条 DEGRADED，不会走到这里」——这正是本轮要消灭的旧语义，注释未跟上。
- 后果见下一问：Swift FAIL 的**第一条** mismatch 是「未登记 `req.interrupt`……该 D2 方法本轮 SG-5 未实现」，这句话对 Swift `interrupt()` 是假的（rounds/0020 已实现 `mode:"cancel"`，steer 走的是 `rpcRejected`，不是「未实现到查不到表」）。

这不是 DEGRADED 名单的复活，但是同构的陈旧风险：新实现一个方法，表不会跟着更新，断言文案会继续撒谎。

### ② interrupt fixture 这次是真跑了，还是换了个方式跳过？

**真跑了。** 证据不依赖摘要文案。

`operation-outcome/soft-steer-then-stop.json` timeline：`createSession` → `subscribe` → `interrupt(mode:"steer", id=steer1)` → `expect_outbound(steer1)` → `stop()` → `assert_state@t=25` → `mock_response(replyTo:steer1)`。

基线 `00`（静态跳过）在该条上**没有任何** `sessions.create` / `subscribe` / `abort` 日志，直接 `[DEGRADED]`。

改后 `02`/`13`：

1. 该条之前出现了 `sessions.create` + `sessions.messages.subscribe`（timeline 前两步已执行）。
2. 随后出现 **`SEND req sessions.abort` 且没有对应 RECV**——这是 `t=25` 的 `stop()` 发出的（fixture 没有 `mock_response(replyTo: stop1)`，gate 等到收尾超时）。若仍整条跳过，这条 abort 不会出现。
3. 三条真实 mismatch：
   - `expect_outbound(steer1)` 被跑到（静态跳过根本走不到这条 op）
   - `assert_state@t=25.sessionLock: 期望 interrupt_in_progress，实际 stop_in_progress`——`stop()` 已拿到锁
   - `expected.pendingOperations.steer1: 期望 submitted，实际 nil`——steer 从未进入 operation 通道
4. 该条**没有** `sessions.abort` 的 RECV，也没有第二条 abort：说明 `interrupt(mode:"steer")` **没有**走到 RPC（与 client 在拿锁前 throw `unsupported_interrupt_mode` 一致，`OpenclawGatewayKernelClient.swift:946-952`）。
5. 反证 `10` 注入静态名单后，该条理由变回 `静态名单命中，未执行 timeline 就整条跳过`，且不再出现上述 abort——证明「有 abort + 有 mismatch」才是发现机制，不是另一层跳过。

C# `03`/`14` 同样先 `create`/`subscribe` 再 `SEND sessions.abort` 然后才 `[DEGRADED] … id=steer1 … NotImplemented`。C# 的 DEGRADED 发生在**整条 timeline 跑完之后**，不是执行前短路。`stop()` 的副作用已经发出。

### ③ `noteRealFailure` 会不会把真失败洗成 DEGRADED？

**对 `rpcRejected(code:"unsupported_interrupt_mode")`：不会。** 这是本次最关键的实证路径，分类正确。

类型分流（Swift `failureDict` 188-198 行与 `noteRealFailure` 313-316 行对照）：

| client 抛出 | `noteRealFailure` | 最终判定 |
|---|---|---|
| `KernelClientError.notImplemented` | 置位 | DEGRADED |
| `KernelClientError.rpcRejected(code:"unsupported_interrupt_mode")` | 不匹配，直接 return | 走 mismatch → FAIL |
| `KernelClientError.rpcRejected(code:"session_locked")` | 不匹配 | FAIL（若断言期望成功） |
| `ApprovalDecisionError.approvalNotPending`（非 `KernelClientError`） | 不匹配 | FAIL（`unknown`） |

Swift `interrupt()` 对非 cancel 的 throw 是 **`rpcRejected`，不是 `notImplemented`**（`OpenclawGatewayKernelClient.swift:946-952`）。错误文案里虽然写了 `"is not implemented this round"`，但判定**只认 enum case**，不认字符串。本次 Swift 输出 `1 FAIL / 0 DEGRADED` 就是这条反例的绿证：若被洗掉，会变成 `0 FAIL / 1 DEGRADED`，与基线不可区分。

C# `InterruptAsync` 是无条件 `NotImplemented`（`:421`），DEGRADED 在这里是对的。

#### 构造反例：什么情况下真失败会被洗掉

**CE-A（机制内建，当前 13 条里 C# 这条已踩到边缘）——整条跑完再 DEGRADED，后续真失败被丢。**

`runFixtureFile` / `RunFixtureFileAsync` 明确：中途 `notImplemented` 仍继续执行后续 op，收尾时一旦 `notImplementedTrigger` 有值，**整条**返回 DEGRADED，`accumulatedMismatches` 全部丢弃（Swift `:1210-1229`，C# `:1291-1308`）。

构造：

```
t=0  createSession / subscribe          → 已实现，会出真实 RPC
t=15 interrupt(mode:"steer")            → C#: NotImplemented（置位 trigger）
t=25 stop() + assert_state              → 已实现；C# 03:55 已发出 sessions.abort
t=25 期望 sessionLock=interrupt_in_progress
```

C# 上 `stop()` 的真实行为（abort 已发出、锁态、pendingOperations）若与期望不符，本应是 FAIL，但被 interrupt 的 `NotImplemented` 整条洗成 DEGRADED。作者给了三条理由（fixture 依赖的能力没实现 / 保持「整条是最小单元」/ 拆分太贵）。作为判定机制这说得通；作为「真失败不会被洗」的承诺，**这句话过满**——同 fixture 里已实现方法的回归，在 C# 这条上是看不见的。

**CE-B（今天没有这条 fixture，但机制允许）——后置 `capabilities()` 桩。**

```
interrupt(mode:"steer")  → Swift: rpcRejected → 累积 3 条真实 mismatch
capabilities()           → 两端: notImplemented → 置位 trigger
```

整条变 DEGRADED，steer 的真实 FAIL 消失。当前 13 条没有任何 `client_call: capabilities` / `respondApproval`，所以还没爆。谁以后在同一条 timeline 里顺手加一个 capabilities 探测，就会把前面的真失败吃掉。

**CE-C（client 用错错误类型才会发生；当前 Swift client 没犯）**

若有人把 steer 拒绝写成 `throw .notImplemented("unsupported_interrupt_mode")`，runner **会**洗成 DEGRADED。runner 无法防御 client 谎报 Kind。当前 Swift 实现用的是 `rpcRejected`，frame-replay 也锁了这条（`09` 日志：`interrupt() mode:"steer" rejected with unsupported_interrupt_mode, not silently treated as cancel`）。

**CE-D（反向误伤，保守）**

`executeOp` 抛 `RunnerError.malformed` 时，catch 直接 `.failed`，**不再看** `notImplementedTrigger`（Swift `:1203-1204`）。若先命中 notImplemented、再因缺 gate 结构性崩溃，会把本该 DEGRADED 报成 FAIL。作者给 interrupt/respondApproval 预注册 gate，正是为堵这条。方向与「洗成 DEGRADED」相反。

**结论**：`rpcRejected` vs `notImplemented` 的收口本身是紧的，本次 steer 路径没有被洗。会洗的是「同 fixture 里后出现的 `notImplemented` 覆盖先出现的真失败」，这是整条 DEGRADED 语义的代价，不是类型匹配写错。

### ④ 有没有新的静默失败路径？

有，三条，按严重度：

**S1（中）——partial execution + 整条 DEGRADED。** 见 CE-A。C# 03 已观察到 `SEND sessions.abort` 且无 RECV：`stop()` 挂在 gate 上，150ms 收尾后结果被丢。新 client 每条 fixture 重建，不污染下一条，但本条上的 stop 回归静默。

**S2（中）——`expect_outbound` 表未登记 `req.interrupt`。** 见 ①。即便将来 Swift `mode:"cancel"` 真发出 `sessions.abort` 且 `recordOutbound` 已记下，`expect_outbound(pattern.type=req.interrupt)` 仍会走「未登记」分支，**无视已记录的 outbound**。这是新的假失败通道：本轮让 interrupt 真跑之后才暴露。今日被 steer 拒绝「没有 outbound」盖住，所以还没单独成祸。

**S3（低，前瞻）——C# interrupt/respondApproval 只 `SetGate`、不注册 RPC stub。** 今日安全（方法体第一步就 throw NotImplemented，到不了 RPC）。C# 一旦按 Swift 落地 `mode:"cancel"`，`mock_response` 仍能找到 gate，但 `sessions.abort` 没有 stub，真实/测试 RPC 会落到未拦截路径。Swift 这边 interrupt 已登记 stub；stop 随后再登记一次会覆盖同 method 的 stub——当前 fixture 里 interrupt 不用 abort，所以没撞上。若以后出现「cancel 在途 + stop 到达」的 fixture，两边会抢同一条 `sessions.abort` stub。

另外已核对、**不是**新静默失败：

- `capabilities` 不注册 stub：两端都是无条件 notImplemented，合理。
- `mock_response(replyTo:steer1)` 在调用已拒绝后仍 resolve 一个无人等待的 gate：浪费，不改判定。
- DEGRADED 仍不进退出码：C# 仍 exit 0。scope-lock 允许，摘要现在能看见。不是新的，是旧契约保留。

RPC 门：Swift interrupt 登记了 `sessions.abort` + 背景 `approval.resolve`；respondApproval 登记了 `approval.resolve`。C# 三者都登记了 gate，RPC stub 仅 Swift interrupt 有。按「今天会不会结构性崩溃」计，门是齐的；按「将来 cancel 真发出 RPC」计，C# 缺 stub。

## 主会话规格裁定核实

主会话裁定：Swift 这条 FAIL 是**实现偏离 confirmed 规格，不是 fixture 过时**。规格依据：`interrupt_in_progress` 遇 `stop()` 是「特殊仲裁」而非 reject；steer 与 cancel 各有专条，规则均为「**等待，不抢占**」。

**规格原文核验（未误读条文本身）：**

`d1-kernelport-spec-v3-6.md` 顶部 `design_status: confirmed`。§9.3 矩阵（约 762 行）：

> `interrupt_in_progress` × `stop()` = **特殊仲裁**（不是 `session_locked` reject）

steer 专条（约 770 行）：

> 规则是**等待，不抢占**：`stop()` 到达时若锁状态为 `interrupt_in_progress` 且当前 operation 是 soft steer，适配器**等待该 RPC 返回**

cancel 专条（约 772 行）：同样「**等待，不抢占**」。

实现原文（`OpenclawGatewayKernelClient.swift:931-933`，rounds/0020）：

> `send()`/`stop()`/`interrupt()` 三者两两互斥，任一方法执行时若锁不是 idle 一律 reject(`session_locked`)，**不做优先级仲裁**

frame-replay 还把这个偏离锁成了绿测试（`09`：`send() and stop() are both rejected with session_locked while a REAL interrupt() is in flight`）。

**裁定成立：fixture 没有过时。** 它逐字转录 D4 示例，编码的是 confirmed §9.3，不是一份过期草稿。FAIL 暴露的是 SG-5 相对 D1 的缺口。

**主会话有一处归因混写，但不构成误读规格：**

本次跑出来的 `sessionLock: 期望 interrupt_in_progress，实际 stop_in_progress`，**近因不是**「stop 拒绝/抢占了已在途的 interrupt」。steer 在**拿锁之前**就被 `unsupported_interrupt_mode` 拒绝（`:946` 的 mode guard 故意放在锁前面），锁从未进入 `interrupt_in_progress`；随后 `stop()` 面对的是 `idle`，合法转入 `stop_in_progress`。§9.3 的「等待，不抢占」在这次运行里**没有被观察到**，因为根本没进入该格子。

规格偏离其实有两条，本次 fixture 只实证了第一条：

1. **已实证**：openclaw 的 `interruptModes` 规格是三者俱全（§4.1），`mode:"steer"` 应映射 `chat.send`+`queueMode:"steer"`（§5/§6.1(a)）。实现只做了 `cancel`，其余 `unsupported_interrupt_mode`。这是实现不完整，不是 fixture 错。
2. **代码里存在、本次未观察到**：即便 steer 落地，锁矩阵仍是「非 idle 一律 reject」，与 §9.3 仲裁相反。要看到这条，得先有一次真正进入 `interrupt_in_progress` 的 steer/cancel。

主会话把两条并成一句「实现偏离规格」——结论对，对「这条 FAIL 的近因」略混。没有把规格读反。

## Decisions / deviations

- 未重跑 runner / `swift build` / frame-replay：采信 `evidence/04,05,08,09,13,14`。判定与源码、基线 diff 交叉核对一致。
- `expectOutboundMethodTable` 视为「残留查表」的一部分（问 ① 要求含摘要/报告；我把同文件里仍按方法名短路的断言表一并算上）。它不推翻 DEGRADED 主路径。
- CE-A 记为设计代价，不单独把本轮打成 REWORK：scope-lock 取舍 1 写明「整条跑完再判定」，作者是故意的。

## Open questions

1. 下一轮若补 `mode:"steer"` 或 C# `interrupt`，`expectOutboundMethodTable` 是否同步加 `req.interrupt`？steer 的真实 RPC 按规格是 `chat.send` 不是 `sessions.abort`，表项不能简单抄 stop。
2. 整条 DEGRADED 是否要在摘要里至少列出被丢弃的 mismatch 条数（不改变判定，只防止 CE-A 完全看不见）？
3. rounds/0020 的「不做仲裁」是持久产品决策，还是确认要对齐 §9.3？这决定 soft-steer fixture 在 steer 落地之后会不会继续红。

## Verdict

**PASS_WITH_NOTE**

运行时发现的主契约成立：名单从可执行路径消失，Swift interrupt 真跑并真实 FAIL，`rpcRejected(unsupported_interrupt_mode)` 没有被洗成 DEGRADED，C# 仍按真实 `NotImplemented` 降级，两端分歧在按结果筛选的摘要里可见。不够打 REWORK。不够打纯 PASS，是因为 `expectOutboundMethodTable` 仍在用过期「未实现」文案当第一条 FAIL 理由，且整条 DEGRADED 会静默丢掉同 fixture 里已实现方法的失败。

## Next recommendation

1. **本轮可收**：判定机制达到 scope-lock 目标，不必为了对齐数字去实现 C# 三方法或改 fixture JSON。
2. **收盘前建议补一刀（小，仍在 runner 范围内）**：修掉 `expectOutboundMethodTable` 两端过期注释；`req.interrupt` 未登记时的文案不要再写「SG-5 未实现」。不必本轮把 interrupt 加进表——steer 此刻没有 outbound，加了只会换一条同样红的「无 outbound」理由，但至少不再撒谎。
3. **不要在本轮修 Swift FAIL**：它是实现相对 confirmed D1 的缺口第一次变得可观察，正是本轮要的输出。
4. **后续轮（超出 0022）**：C# `interrupt(mode:"cancel")` 落地时必须补 RPC stub；补 steer 时按 §5 走 `chat.send`+`queueMode:"steer"`，并单独决定是否把锁矩阵从「一律 reject」改回 §9.3「等待，不抢占」。在那之前不要改这条金标 fixture。
