# Scope Lock — goal 002 / rounds/0020

**开轮时间**：2026-08-13，**动手之前**写就。用户裁定按 2 → 1 → 3 执行，本轮是**第 3 件**。

## Round Objective

**让用户能中止正在生成的回复，而会话继续留着。**

## 动手前已查清的三件事（不是假设）

### 1. 不需要改 openclaw 源码 —— 已实证

`kernels/openclaw/src/gateway/methods/core-descriptors.ts:231` 注册了 `sessions.abort`
（`scope: operator.write`，`since: <=2026.7`）。读 handler 本体
`server-methods/sessions-abort.ts`（332 行）确认：**它只中止 run，从不删会话**——
返回 `{ok, abortedRunId, status}`，`status` 取 `"aborted"` / `"no-active-run"` / `"timeout"`。

而**我们自己的 `stop()` 一直在用它**（`OpenclawGatewayKernelClient.swift:908`）。

### 2. 「停止生成」≠ `stop()` —— 差在第二步

`stop()` 是 **`sessions.abort` + `sessions.delete`**，最后还发 `SessionEndEvent(reason:'stopped')`
并 finish 掉事件流（`emitStopSessionEndAndFinish`，`:980`）。**它把会话销毁了。**

「停止生成」要的只有第一步：**中止当前 run、保留会话，用户还能接着说下一句**。
所以这是 `interrupt(mode: "cancel")`，不是 `stop()`。

### 3. 契约已经把三种模式写死了

`app/contracts/d2/schema/methods/interrupt.schema.json`：
`mode ∈ {steer, cancel, abort_and_resend}`；`InterruptResultPayload` 必填
`operationId` + `outcome`（OperationOutcome 七态逐字透传，D2 不裁剪）。
失败通道点名了 `unsupported_interrupt_mode` / `no_active_run_for_steer` / `session_locked`。

**本轮只实现 `mode: "cancel"`。** 另两种模式**必须显式抛
`unsupported_interrupt_mode`**，不许悄悄当成 cancel 处理——那正是本项目一直在修的
「看起来支持、其实做了别的事」。

## 现状：`interrupt()` 是桩，且互斥矩阵为此开了个口子

- `OpenclawGatewayKernelClient.swift:841` —— 函数体第一行 `throw .notImplemented`。
- `:61-63` 注释白纸黑字：「interrupt() 本轮仍是 TODO 桩，因此完整互斥矩阵里涉及
  `interrupt_in_progress` 的分支本轮不适用」。`SessionLockState` 只有
  `idle / sendPending / stopInProgress` 三态。
- **本轮让那条注释失效**，必须同步补上 `interruptInProgress` 态与它的互斥判定。

## 五个必须先定死的取舍

### 1. 与 `stop()` 的关系 → **各走各的路，不复用 `stop()` 的函数体**

`stop()` 的方法体（`:879-1012`）与 `sessions.delete`、`session_end`、事件流 finish
强耦合。硬塞一个 `skipDelete` 布尔进去会让一个已经很复杂、被几十条测试钉住的函数
再长一个分支。**新写 `interrupt()`，复用它下面的**部件**——
`forceDenyPendingApprovalsBeforeStop`、`waitForPendingStopTerminal`、
`emitOperationCompletedMirror` ——而不是复用整个函数。

### 2. 强制 deny pending 审批 → **照做，一步不省**

D1 §6.2 M3 的定序理由对 interrupt 一字不差地成立：审批还在 pending 时直接 abort，
会留下「run 已中止、审批却还挂着」的不一致。`stop()` 为此做了 drain 循环
（`forceDenyPendingApprovalsBeforeStop`，含轮次上限与在途决议收敛）。
**interrupt 必须走同一条路**——省掉它就是拿一个已修好的竞态换一点代码量。

### 3. **不发 `session_end`、不 finish 事件流** —— 本轮红线

这是 interrupt 与 stop 的**唯一本质区别**。发了 `session_end` 或 finish 了 continuation，
会话就死了，「保留会话」的整个目的落空。

### 4. `abortedRunId == nil` 时 → **报 succeeded，不是报错**

沿用 `stop()` 已经实证过的判定（`:958-968`）：run 早已自然结束时 `sessions.abort`
诚实回报 `abortedRunId: null`。用户点了停止、而它已经停了——**目的达成即 succeeded**，
但仍要补一条 `operation_completed` 镜像，否则只订阅事件流的观察者看不到这次操作的终态。

### 5. 按钮什么时候出现 → **有 active run 时替换发送按钮，而不是并排多一个**

并排放两个按钮要求用户判断此刻该点哪个。**同一个位置、随状态切换**，
和主流 chat 客户端一致，也不需要新的解释。

## 本轮不做

- **不实现 `steer` 与 `abort_and_resend`**（显式抛 `unsupported_interrupt_mode`）。
- **不改 `stop()` 的任何既有语义**——它的几十条测试必须一条不红。
- **不碰 openclaw 源码**（已证明不需要）。
- 不碰三个插件 submodule、不碰 `app/generated/`、`app/contracts/`。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` | 改 | 实现 `interrupt()`；新增 `interruptInProgress` 锁态与互斥判定；**不改 `stop()` 既有行为** |
| `app/kernel-client/swift/KernelClient.swift` | 改 | 只更新过时注释（`interrupt` 不再是 TODO 桩） |
| `app/kernel-client/swift/EventMapping.swift` | 改 | **v2 扩围，见下方「Scope-Lock 修订」**——只加一个 `operationKind` 形参并透传 |
| `app/apps/AgentShell/Sources/AgentShellCore/` | 改/写 | 运行态跟踪 + `interruptCurrentRun` 入口 |
| `app/apps/AgentShell/Sources/AgentShell/SessionDetailView.swift` | 改 | 发送/停止按钮切换 |
| `app/kernel-client/swift/frame-replay-tests/` | 写 | 回归测试 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0020/` | 写 | 本轮产物 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `kernels/openclaw/` **任何文件**
- `app/generated/`、`app/contracts/`、`app/server/`、`app/parity/`、`.github/`
- `Package.swift` 的 platforms、`Info.plist` 的最低版本
- **`stop()` 的既有行为**（它的测试是本轮的回归护栏，不是可调整对象）

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 构建 | `swift build --package-path app` exit 0 | 直接捕获退出码 |
| 回归 | 帧回放 **≥102/102**（本轮新增测试后更高） | 测试输出 |
| **会话存活（红线）** | interrupt 后**无** `session_end`、事件流**未** finish、同一 session 能再次 `send()` 成功 | 测试 |
| **不发 delete（红线）** | interrupt 全程**从不** dispatch `sessions.delete` | 调用顺序日志断言 |
| 强制 deny 定序 | `approval.resolve` 严格先于 `sessions.abort` | 调用顺序日志断言 |
| 无 active run | `abortedRunId:null` → `outcome=.succeeded` + 补发 `operation_completed` 镜像 | 测试 |
| 互斥矩阵 | interrupt 进行中再调 send/stop/interrupt → `session_locked`；**且失败路径释放锁** | 测试 |
| 不支持的 mode | `steer`/`abort_and_resend` → `unsupported_interrupt_mode` | 测试 |
| **`stop()` 无回归** | 既有 stop 相关测试**一条不红** | 测试输出 |
| **破坏性反证** | 每条新断言都先看到红，**且注入命中数 > 0** | 注入命中计数 + 红/绿两次输出 |
| 实拍 | 真内核下点停止：生成中断、会话仍在、还能接着发下一句 | 截图 |

## 红线

- **不得发 `session_end`、不得 finish 事件流、不得调 `sessions.delete`。**
  违反即本轮不接受——那就退化成了 `stop()`，本轮等于什么都没做。
- **不得改 `stop()` 的既有行为**。
- **不得把 `steer`/`abort_and_resend` 悄悄当 cancel 处理。**
- **破坏性反证必须先看到红，且必须打印注入命中数**——命中 0 个位置的注入什么都没证明
  （本项目已两次踩中）。

## 异构评审

改动完成后派只读评审，重点问：①会话是否真的存活（而不只是没调 delete）
②互斥矩阵的失败路径是否都释放锁 ③强制 deny 定序是否与 `stop()` 等价
④有没有新的静默失败路径。

---

## Scope-Lock 修订 v1 → v2（2026-08-13，实施中）

**扩围一个文件：`app/kernel-client/swift/EventMapping.swift`。**

走的是 `control-contract.md` 既定的「Scope-lock mutation: main session 自主（版本递增留痕）」
授权路径，**不是事后追认**——实施方在报告里主动点名了这处越界并给了理由，
主会话复核后判定成立，在此留痕。

**为什么必须动它**：v1 的第 2 条取舍要求复用 `stop()` 的等待机制而不是复制一份。
但复用的那条路径上，`handleAgentEvent` 产出中止终态事件是靠
`mapOpenclawAgentLifecycleToAbortTerminalEvents`（在 `EventMapping.swift` 里），
而它**把 `operationKind: .stop` 写死了**——照原样复用，interrupt 触发的每一条终态事件
都会被标成 `stop`，**标签说谎**（rounds/0019 刚判过一次「标签说谎比不显示更糟」）。

两条路：①在 `OpenclawGatewayKernelClient.swift` 里复制约 30 行「怎么解读 openclaw 的
aborted lifecycle 帧」；②给那个函数加一个 `operationKind` 形参。**选 ②**——
①会造出两份同一语义的解读逻辑、日后必然漂移，而「两份会漂移的清单」正是本项目
反复在修的那类缺陷。

**改动幅度**：`EventMapping.swift` 的实际代码 diff 只有 3 行——加一个形参、把写死的
`.stop` 换成该形参。`stop()` 侧全部调用点显式传 `.stop`，**值不变**。

**复核结论**：`stop()` 的可观察行为逐处核对为**未变**——落在 `stop()` 函数体内的代码
改动全部是「原先隐式的 `.stop` 变成显式的 `.stop`」，无一处语义变化；
帧回放 **115/115**（102 基线一条不红）。

**一处特别核对**：`:2819` 把 `operationKind` 写死成 `.stop` 而没有像 `:2793` 那样读
`pendingForRun.operationKind`——**这不是漏改**。该分支的进入条件是
`pendingStops[ourSessionID] == nil`，**按构造就不存在可读的发起者信息**；
代码注释也如实写了「不是『猜它是 stop』，只是在没有信息时保持这条从未被真正观察到过的
路径的历史输出不变」。判定成立。

---

## Scope-Lock 修订 v2 → v3（2026-08-13，验证阶段）

**扩围一个文件：`app/kernel-client/swift/CLIRunner.swift`**（新增一个 env 开关的 interrupt 步骤）。

**为什么**：本 scope-lock 的验证表要求「真内核下点停止：生成中断、会话仍在、还能接着发下一句」。
**这条红线单元测试结构性证明不了**——123 条测试全部 stub 掉 `sessions.abort`，
「会话在真内核侧是否还活着」在 stub 世界里没有意义。`kernel-client-cli` 是本项目既定的
真内核 harness（`SG5_SEND_MESSAGE`/`SG5_SKIP_STOP` 等步骤全是同一形状的 env 开关），
加一个同形状的开关是最小改动。

**同时如实记录一个当下无法消除的阻断**：**实拍（截图）本轮取不到——屏幕处于锁定状态**
（`screencapture` 拍到的是 macOS 锁屏）。用户不在机器前，GUI 自动化也无法可靠驱动。
**不拿 CLI 证据冒充截图证据**：这两者证明的不是同一件事——
CLI 证明适配器语义在真内核上成立，**证明不了那个按钮**（视图层结构性不可测，见下）。
按钮的实拍留作明确的证据缺口。
