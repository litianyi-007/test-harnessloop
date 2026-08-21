# Scope Lock — goal 002 / rounds/0023

**开轮时间**：2026-08-14，**动手之前**写就。用户裁定实现 `interrupt(mode:"steer")`。

## Round Objective

**把 `interrupt` 补齐到 confirmed D1 规定的样子**：实现 `mode:"steer"`，
并把 `stop()` 遇 `interrupt_in_progress` 的仲裁从「一律拒绝」改成规格要求的
「**等待，不抢占**」——**两种模式都改**。

## 为什么范围比「加一个模式」大

rounds/0022 让那条从未执行过的 fixture 真跑了起来，并 FAIL。读
`d1-kernelport-spec-v3-6.md`（`design_status: confirmed`，晚于 fixture 转录的 D4 v2.2）
§9.3 后确认：**fixture 是对的，实现有两条偏离**。

| # | 偏离 | 状态 |
|---|---|---|
| 1 | `interruptModes` 该三者俱全，实现只做了 `cancel` | rounds/0022 **已实证** |
| 2 | 锁矩阵「非 idle 一律 reject」，与 §9.3「等待，不抢占」相反 | **代码里存在，但从未被观察到** |

**第 2 条尤其要小心**：评审 T-115 指出，这次 FAIL 的近因是 **steer 在拿锁之前就被
mode guard 拒了**（guard 故意放在锁之前），interrupt 压根没进过 `interrupt_in_progress`。
**所以光实现 steer 不会自动暴露第 2 条——必须专门构造用例。**

## 规格原文（本轮的判据来源，不是转述）

- **§9.3 矩阵**：`interrupt_in_progress` 遇 `send()`/`interrupt()` 才是 reject，
  遇 **`stop()` 是「特殊仲裁」**。
- **steer 专条 / cancel 专条**：规则相同——「**等待，不抢占**」：`stop()` 到达时
  适配器**等待该 RPC 返回**（无法从中截断），返回后 interrupt 按既有规则终态化，
  锁转 `stop_in_progress`，`stop()` 序列正常执行。
- **超时归属**：等待超时是 **`stop()` 自己的 `timed_out`**，**不是** interrupt 的第三个终态
  （v3.4 专门纠正过这一点，v3.3 曾误写成三态）。
- **steer 结果态**：**严格二态 `submitted`/`rejected`**，RPC 本身失败（含网络/连接层）
  归入 `rejected`。**不产生第三个终态。**
- **前置**：无 active run → **同步前置 reject `no_active_run_for_steer`**，
  发生在 operationId 铸造之前，**不产生 OperationOutcome**。

## 四个必须先定死的取舍

### 1. openclaw 侧走哪个 RPC → **实现方查证后决定，并说明依据**

规格 §5/§6.1(a) 写的是 **`chat.send` + `queueMode:"steer"` + `deliver:false`**。
但 openclaw 同时注册了 **`sessions.steer`**（`core-descriptors.ts:334`，
`scope: operator.write`，`advertise: false`，handler 在 `sessions-messaging.ts`）。

**这两者是什么关系、该用哪个，本文件不替实现方裁定**——要读 openclaw 源码确认
`sessions.steer` 内部是否就是 `chat.send`+`queueMode`，然后选一个并**说明依据**。
若两者语义不等价，**如实报告分歧，不要擅自挑一个了事**。

### 2. 「等待，不抢占」怎么实现 → **不得把 `stop()` 变成忙等或无限等**

规格说等待该 RPC 返回。实现必须有**有界等待**，超时按上面的归属规则记成
**`stop()` 自己的 `timed_out`**。**不得**因为等待而产生 interrupt 的第三个终态。

### 3. **那条钉死错误行为的测试怎么改** → 拆成两半，不是整条删

rounds/0020 的 `testSendAndStopRejectedWhileInterruptInFlight` **一半对一半错**：
`send()` 被拒**是对的**（§9.3 矩阵如此），`stop()` 被拒**是错的**。
**保留 send 那一半，把 stop 那一半改成断言「等待而非拒绝」**——不许整条删掉了事。

### 4. **必须专门构造用例暴露第 2 条偏离** → 否则本轮等于没验

需要一次**真正进入 `interrupt_in_progress`** 的 interrupt（steer 或 cancel 均可），
在其 RPC 在途时让 `stop()` 到达，断言：**stop 等待而非被拒**、interrupt 按二态收敛、
锁随后转 `stop_in_progress`、stop 序列正常完成。

## 本轮不做

- **不实现 `abort_and_resend`**（第三种模式，另有 `aborted_no_resend` 等专属语义，独立一轮）。
- **不改 C# 端**（rounds/0022 已裁定：分歧要显出来，不为了数字好看去实现）。
- 不改任何 fixture JSON、不碰 openclaw 源码、不碰三个插件 submodule。
- 不做 `HermesKernelClient`、不做 Windows。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` | 改 | 实现 steer；改锁仲裁；**不改 `send()` 的既有语义** |
| `app/kernel-client/swift/KernelClient.swift`、`EventMapping.swift`、`OpenclawWire.swift` | 改 | 仅为 steer/仲裁所需 |
| `app/kernel-client/swift/frame-replay-tests/` | 写/改 | 新增用例；**改正**取舍 3 点名的那条测试 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0023/` | 写 | 本轮产物与证据 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `app/contracts/**`（**含所有 fixture JSON 与三端 runner**）
- `app/kernel-client/csharp/`、`app/apps/`、`app/generated/`、`app/server/`、`app/parity/`
- `kernels/`、`.github/`、`Package.swift`、三个插件 submodule

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 构建 | `swift build --package-path app` exit 0 | **先看退出码**再看统计数 |
| 回归 | 帧回放 **≥163/163** | 测试输出 |
| **金标 fixture** | `soft-steer-then-stop` 在 Swift runner 上**从 FAIL 转为 PASS** | 改动前后两份 runner 输出对照 |
| **第 2 条偏离已被观察** | 存在一条测试：真正进入 `interrupt_in_progress` 后 `stop()` **等待而非被拒** | 测试名 + 反证 |
| steer 二态 | `submitted`/`rejected` 两态，**无第三态**；RPC 失败归入 `rejected` | 测试 |
| 无 active run | 同步前置 reject `no_active_run_for_steer`，**不铸 operationId** | 测试 |
| 超时归属 | 等待超时是 **`stop()` 的 `timed_out`**，不是 interrupt 的终态 | 测试 |
| send 侧未松动 | `send()` 遇 `interrupt_in_progress` **仍然拒绝** | 取舍 3 保留的那半测试 |
| C# 侧未动 | `git diff --stat` 确认 | — |
| **破坏性反证** | 每条新断言先见红；**打印注入命中数**；**用 sha 验残留，不用 `git checkout --`** | 红绿两份输出 |

## 红线

- **不得把 `send()` 遇 `interrupt_in_progress` 也改成等待**——规格矩阵明写 reject。
- **不得让 steer 产生第三个终态**（v3.4 专门纠正过的坑）。
- **不得整条删掉那条测试**——它有一半是对的。
- **不得改 fixture JSON 让它迁就实现**——金标是契约，本轮是实现向它靠拢。
- **不得为图省事把 `stop()` 的等待做成无界**。

## 异构评审

改动完成后派只读评审，重点问：①steer 的 RPC 选择依据是否成立
②「等待，不抢占」是否真的实现了（自己构造并发场景验，不要只读代码）
③第 2 条偏离是否真的被一条测试观察到了 ④`send()` 侧有没有被顺手放松
⑤有没有新的静默失败路径。

---

## Scope-Lock 修订 v1 → v2（2026-08-15，用户裁定「本轮扩围一起做完」）

**扩围两处**：`app/contracts/d2/fixtures/operation-outcome/soft-steer-then-stop.json`
与 `app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift` 的 outbound 方法表。
两者原在本轮 Disallowed 里。

### 为什么原本禁、现在开

原本禁的理由是**防止「改金标让实现过关」**——那会把契约变成实现的回声。这条理由仍然成立，
**扩围不是撤销它**，而是因为查证后确认：**fixture 自身滞后于规格，且滞后点与本轮实现无关**。

实现方在 steer 落地后报告 fixture 仍 FAIL，并给出两条结构性原因，主会话逐条复核成立：

| # | 阻塞 | 复核 |
|---|---|---|
| 1 | fixture 的 `client_call` 序列是 `createSession → subscribe → interrupt → stop`，**没有 `send()`**，从未建立 active run | 已核 |
| 2 | runner 的 `expectOutboundMethodTable` 只有 4 条（`createSession`/`send`/`subscribe`/`stop`），**没有 `req.interrupt`** | 已核 |

**第 1 条是契约产物自身的滞后**：该 fixture 逐字转录自 D4 v2.2，
而 **`no_active_run_for_steer` 这条同步前置 reject 是 v3.2 才新增的**（晚于转录）。
于是一个**完全合规**的实现在这条 fixture 上必须同步前置拒绝——
**fixture 期待的状态转移在现行规格下不可能发生。**

**这不是「让测试变绿」，是让契约产物跟上它自己所属的规格。**

### 扩围的硬边界

- **只补 fixture 缺的那一步前置**（建立 active run），**不得削弱任何既有断言**——
  三条 mismatch 必须因为「实现现在对了」而消失，**不是因为断言被改松了**。
- **不得修改 fixture 想验证的语义**：它验的仍是「steer 在途时 stop 等待而非抢占」。
- runner 的 outbound 表补 `req.interrupt` 时注意：**interrupt 的底层 RPC 随 mode 而变**
  （cancel → `sessions.abort`，steer → `chat.send`），**一条平表项可能不够**——
  实现方须处理这个分叉并说明做法，不得为图省事只登记一种而让另一种静默失配。
- **C# 端的同名表**：C# 未实现 interrupt、仍会 DEGRADED，补它等于写死配置。
  **由实现方判断并说明**，不强制。

### 本轮验收表相应恢复为可达

「金标 fixture 从 FAIL 转 PASS」这一项在 v1 下不可达（已由实证确认），
v2 扩围后恢复为**必须达成**，且必须是「实现对了 + fixture 跟上规格」两件事共同促成，
**任何一条靠削弱断言达成即本轮不接受**。

---

## Scope-Lock 修订 v2 → v3（2026-08-15，实施方指出后补记）

**扩围文本对齐**：v2 的措辞只授权了 `SwiftFixtureRunner.swift` 的**「outbound 方法表」**，
而评审 FAIL-5 要求修的是**同一文件的入站翻译**（`applyMockResponse`）。

**这是补记，不是事前授权。** 实施方在返工任务书的明确指示下改了入站路径，
**并主动指出 scope-lock 文本没覆盖它**——判断正确：返工任务书是即时且知情的指令，
但 scope-lock 是范围契约，两者不一致时该被修的是文档，不是默默放过。

**边界不变**：`app/contracts/` 下**仅 `swift-runner/SwiftFixtureRunner.swift` 与
本轮已授权的那条 fixture 可改**；**fixture 的断言仍不得削弱**（评审已独立复核 diff 为 4 增 1 删、
删的是 description 正文）。

## rounds/0023 未闭合的一处真实盲点（如实登记，非疏漏）

FAIL-7 返工中，实施方枚举了 run 变为 active 的全部路径，修好其中两条
（`session.message` 的 `activeRunIds` 快照改为**全量对账**而非并集；裸 `agent` 事件携带
`runId` 时也标记 active），**但第四条无法闭合**：

**会话恢复路径没有 active-run 信号。** 它读了 openclaw 源码
（`sessions-subscriptions.ts:125-137`）确认 `sessions.messages.subscribe` 的响应
只带 `subscribed`/`key`/`approvalReplay`，**不含任何 active run 信息**；
openclaw 唯一的 per-session active-run 信号 `sessions.list` 是一个本适配器从未用过的
批量全会话查询。

**它没有为了闭合而发明一次新的 RPC 调用**——那是实质扩围而非「修快照的维护」——
而是**如实记录，并让前置条件在该情形下保持保守的 `no_active_run_for_steer` 拒绝，
而不是猜着放行**。这个处理符合本轮任务书里那条「不许把前置条件悄悄收窄成凡是能观察到的」。

**后果**：一个刚恢复、自恢复后零事件、且恢复前已有 active run 的会话，
其合法 steer 会被误拒。**已登记为已知缺口，待后续轮（可能与 `HermesKernelClient` 或
capabilities 探测一并解决）。**
