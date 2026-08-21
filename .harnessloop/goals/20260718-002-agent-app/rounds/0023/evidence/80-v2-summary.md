# Scope-Lock v1→v2 扩围收尾：`soft-steer-then-stop` FAIL → PASS

## 结论

`soft-steer-then-stop-waits-not-preempts` 在 Swift 金标 parity runner 上**从 FAIL 转为 PASS**。
`13 PASS / 0 FAIL / 0 DEGRADED`，其余 12 条 fixture 零回归。`swift build --package-path app`
exit 0，`frame-replay-tests` **169/169**（本轮 v1 阶段已达成的数字，v2 阶段未再改动 kernel-client
本体，数字不变）。C# 端 `git diff --stat` 为空，未动。

## Before / after 对照

| | before（v1 阶段末，evidence/23） | after（v2，evidence/60） |
|---|---|---|
| 结果 | `[FAIL]`，3 条 mismatch | `[PASS]`，0 条 mismatch |
| `expect_outbound(steer1)` | 未登记『req.interrupt』 | （无 mismatch——真实调用 `chat.send`，深度比对含 `payload.mode` 全部通过） |
| `assert_state@t=25.sessionLock` | 期望 interrupt_in_progress，实际 stop_in_progress | （无 mismatch——真实观测到 `interrupt_in_progress`） |
| `expected.pendingOperations.steer1` | 期望 submitted，实际 nil | （无 mismatch——真实收敛为 `submitted`） |
| 整体判定 | 13 条 fixture：12 PASS / **1 FAIL** / 0 DEGRADED | 13 条 fixture：**13 PASS** / 0 FAIL / 0 DEGRADED |

真实执行 trace（`evidence/60` 第 55-96 行）确认的不只是断言消失，而是机制本身真的发生了：
`sessions.send`（send1，建立 `runId:"run-steer-1"`）→ `chat.send`（steer1，真实携带
`sessionKey/message/queueMode:"steer"/deliver:false/idempotencyKey`）→ 只有在 `chat.send` 的
`RECV` 之后，`sessions.abort`（stop1 自己的调用）才被 dispatch——这正是"stop 等待 steer 的 RPC 返回、
不抢占"这条被测语义的真实发生顺序，不是断言凑巧对上。

## 做了什么（三处，逐一说明依据）

### 1. fixture 补前置步骤（`operation-outcome/soft-steer-then-stop.json`）

在 `subscribe`（sub1）与 `interrupt`（steer1）之间插入三步：`client_call(send1)` +
`expect_outbound(send1)` + `mock_response(send1, runId:"run-steer-1")`。**这是全部改动**——
`steer1`/`stop1` 之后的每一个既有 timeline op、`expected` 块，逐字未动（`git diff` 见
`evidence/62-v2-fixture.diff`，只有 3 行新增 + description 追加说明，无一行删除或修改既有断言）。

### 2. runner 的 outbound 方法表按 mode 分叉（`SwiftFixtureRunner.swift`）

`req.interrupt` 的底层方法随 `payload.mode` 变化（cancel→`sessions.abort`，steer→`chat.send`），
不能塞进原有『D2 方法名 -> 唯一底层方法名』的一对一 `expectOutboundMethodTable`。新增独立的
`expectOutboundInterruptMethodByMode: [String:String]`，`checkExpectOutbound` 对 `req.interrupt`
类型走专门分支：取出 `pattern.payload.mode`，查这张新表；`mode` 缺失或未登记（如
`abort_and_resend`）时**明确报告『未登记』**，不静默套用另一种 mode 的答案。

### 3. 两处未被显式点名、但同一问题的必要延伸（如实说明，未擅自扩大范围）

排查 fixture 补上 send1 之后为何仍 FAIL，逐层定位到两处与"outbound 方法表"同源、但字面上不是那张表
本身的问题——**不修就无法达成"FAIL→PASS"这个明确写在验收表里的目标**，因此一并处理，逐条说明理由：

- **`performClientCall` 的 `"interrupt"` case 只注册 `sessions.abort` 一个 stub**（cancel 专用），
  从未注册 `chat.send`。没有 stub 时 `request(method:"chat.send",...)` 在测试环境（无真实
  WebSocket）下同步抛 `notConnected`——这正是 scope-lock v2 原文警告的"只登记一种而让另一种静默
  失配"，只是发生在 stub 注册这一层，不是 `expectOutboundMethodTable` 比对那一层。改为按
  `options.mode` 分叉注册：`cancel` 注册 `sessions.abort`，`steer` 注册 `chat.send`，
  `abort_and_resend`（本轮未实现）不注册任何 stub（该 mode 会在 mode guard 处同步拒绝，从不到达
  RPC 层）。
- **`normalizeNativeParams` 不认识 `chat.send` 的原生字段 `queueMode`**——D2 抽象层的字段名是
  `mode`（`InterruptRequestMessagePayload.mode`），但 `chat.send` 的原生 wire 字段是 `queueMode`
  （`ChatSendParamsSchema`）。这与既有的 `sessions.send` 的 `message`→`text` 重映射是同一类问题
  （原生字段名 ≠ D2 抽象字段名），按同一条纪律（先剥掉目标/源两个键，源字段存在才写回目标字段，
  避免"native 层意外携带 `mode` 字段就自证通过"的假绿）新增 `chat.send` 分支的
  `queueMode`→`mode` 重映射。

**未做的事，及为什么**：`normalizeNativeParams` 里 `key`→`sessionId` 的重映射**未**扩展到
`chat.send` 的 `sessionKey` 字段——`chat.send` 用 `sessionKey`，不是 `key`，因此当前实现下
`chat.send` 请求的规范化结果里没有 `sessionId` 字段。**这不影响本轮验收**：
`soft-steer-then-stop.json` 的 `expect_outbound(steer1).pattern` 只断言 `type`+`payload.mode`，
从未断言 `sessionId`，`partialMatch` 只比对 pattern 里出现的字段（这是本 runner 全部既有 fixture
的共同前提，其它 pattern 同样只断言部分字段）。如实登记为**已知、当前不影响任何断言的空白**：未来
若有 fixture 需要断言 `chat.send` 请求的 `sessionId`，需要再补一次这类 method-keyed 的重映射分支。

## C# 端判断：不改，理由

`app/kernel-client/csharp/OpenclawGatewayKernelClient.cs:420-421` 核实（只读）：`InterruptAsync`
仍是单表达式函数体，无条件 `throw new KernelClientException(KernelClientErrorKind.NotImplemented, ...)`
——本轮"不改 C# 端"未变。`RunFixtureFileAsync`（C# 镜像 Swift 的 `runFixtureFile`）在整条 timeline
跑完后，**先**检查 `notImplementedTrigger` 是否置位，若置位直接返回 `DEGRADED`，**跳过**对
`accumulatedMismatches`/`ExpectOutboundMethodTable` 的进一步处理——即无论 C# 侧的
`ExpectOutboundMethodTable` 有没有 `req.interrupt` 条目，`soft-steer-then-stop` 在 C# runner 上
的终判都会是 `DEGRADED`（由 `InterruptAsync` 的无条件抛错决定，与这张表的内容无关）。

补一条 C# 端的 `req.interrupt` 条目会是**永远不会被真正走到、也无法被反证验证**的死配置——本轮的
破坏性反证纪律要求"每条新断言先见红"，而这条配置在当前 C# 实现下**没有任何执行路径能让它见红**
（DEGRADED 判定发生在这张表被查询之前）。判断：**不加**。等 C# 真正落地 `interrupt()` 那一轮，
补表与补实现同轮完成，两者互为印证，而不是现在先补一份无法验证、可能与未来真实实现脱节的配置。

## 反证表（v2 新增逻辑，每条含命中数/RED/revert/GREEN）

全部残留由 sha256 核验（不用 `git checkout --`）。两份文件的"正确终态"checksum：
`SwiftFixtureRunner.swift` = `79356932a3b4bf11a4a60f14e344aad562a12fddc9bbcb37e5e81ef993a54175`；
`soft-steer-then-stop.json` = `fd2758d1f10e649e15b01dda770f749501ce8afcb8425560b84134f55526e6d9`。
四轮注入 + revert 之后，两份 checksum 均逐字节复原（每轮独立核验，见下表"复原后 checksum"列）。

| # | 新逻辑 | 注入方式 | 命中数 | RED（具体 mismatch） | 复原后 checksum |
|---|---|---|---|---|---|
| A | fixture 的 `send1` 前置步骤是否真的必要 | 删除 `send1` 三行（timeline 退回 v1 形状），**保留全部 runner v2 修复** | 3（3 处待删行） | `expect_outbound(steer1)` 实际捕获 `<none>`；`sessionLock` 仍是 `stop_in_progress`；`pendingOperations.steer1` 仍是 `nil`——与 v1 阶段的原始 FAIL **逐字相同**，证明 runner 修对了也救不了一个没有前置状态的 fixture | `soft-steer-then-stop.json` = `fd2758d1...`（与正确终态一致） |
| B | `expectOutboundInterruptMethodByMode` 是否真的在被查询 | 把 `"steer"` 的映射从 `chat.send` 改成 `sessions.abort` | 1 | `expect_outbound(steer1)`：期望 `sessions.abort`，实际捕获到 `chat.send`——证明真实 client 调用对了，是**测试自己的期望表**被注入错了，方向验证到位 | `SwiftFixtureRunner.swift` = `79356932...`（与正确终态一致） |
| C | mode-aware stub 注册是否真的必要 | 把 `switch options.mode` 的两个分支替换成恒定注册 `sessions.abort`（旧行为） | 1 | `expect_outbound(steer1)` 实际捕获 `<none>`；`pendingOperations.steer1` 变成 `rejected`（不是 A 组的 `nil`——这次是 operationId 已铸造、RPC 真失败，precondition 已经过了，只是没 stub 接住 chat.send，两种红的形状不同，互相佐证两处改动各自独立生效） | `SwiftFixtureRunner.swift` = `79356932...`（与正确终态一致） |
| D | `queueMode`→`mode` 重映射是否真的必要 | 把 `chat.send` 分支的重映射短路成永不执行 | 1 | `expect_outbound(steer1).payload.mode`：期望 `steer`，实际 `nil`——与最初发现这个缺口时观察到的 mismatch **逐字相同** | `SwiftFixtureRunner.swift` = `79356932...`（与正确终态一致） |

未观察到任何一次反证过程中出现进程挂起（与 v1 阶段 CP-1 不同——那次挂起源自本项目 Swift 单测
`InterruptRaceBox.wait()` 无超时，这里的反证跑的是 fixture parity runner 本身，其 `mock_response`
在调用已失败/已被错误处理后仍会尝试 resolve 一个可能无人等待的 gate，属已知、良性的 no-op，见
`SwiftFixtureRunner.swift` 文件头"另外已核对、不是新静默失败"一节）。

## 原始输出文件索引

- `50-v2-pre-edit-checksums.txt`：v2 编辑前两份文件的 checksum。
- `60-v2-FINAL-parity-runner-run.log`：最终态完整 runner 输出（13/13 PASS，含 `soft-steer-then-stop`
  完整真实 trace）。
- `61-v2-FINAL-parity-runner-build.log`：最终态构建日志（exit 0）。
- `62-v2-fixture.diff` / `63-v2-runner.diff`：两份文件相对 git HEAD 的完整 diff。
- `70-v2-FINAL-swiftpm-build.log` / `71-v2-FINAL-frame-replay-tests.log`：`swift build
  --package-path app`（exit 0）与 `frame-replay-tests`（169/169, exit 0）的最终复验，确认 v2 阶段
  未影响 kernel-client 本体与既有单测。
