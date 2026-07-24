# Scope Lock — rounds/0006

## Round Objective

**SG-8.7 金标 parity runner 补齐（横切）**：把 SG-5 已用 ad-hoc `FrameReplayTests` 证过的 Swift/C# 跨端一致，**正式化为三端金标 parity runner 基建**——TS 金标 runner（已存在）+ 新建 Swift runner + 新建 C# runner，三端读**同一组 JSON fixture**（同一 `dsl.ts` DSL）、驱动各自 mock 内核、产出**同一 `ClientObservableState`**（sessionLock / approvalState / pendingOperations / callOutcomes / observedEvents），逐字段比对。并把 fixture 从当前 2 个扩到三组全集（审批五态 FSM / `OperationOutcome` 七态全集 / `SessionLockState` 四态），产出可挂到 SG-4/SG-5 验收列的三端 parity 报告。

**现状（据实核验，2026-07-24）**：
- 金标 parity 基建实际在 `app/contracts/d2/fixtures/`（**不是** goal-breakdown SG-8.7 文本里写的空目录 `app/parity/`）：`dsl.ts`（DSL 正式类型定义，逐字转录 D4 §4.3）+ `ts-runner/runner.ts`（TS 金标 runner，最小版，已诚实标注 `advance_clock`/`disconnect` 为 no-op）+ `ts-runner/mock-kernel-client.ts`（覆盖现有 2 fixture 的极简假内核）。
- 现有 fixture 仅 **2 个**：`operation-outcome/soft-steer-then-stop.json`（interrupt(steer) 在途 + stop 到达的锁矩阵）、`basic/create-session-subscribe-message-delta.json`。
- `app/parity/` 空目录（0 文件）。
- **runner 落点决策**：三端 runner 与其消费的 DSL + fixture 共址于 `app/contracts/d2/fixtures/{ts-runner,swift-runner,csharp-runner}/`（TS 已在此），比另立 `app/parity/` 反向 import contracts 更内聚。SG-8.7 文本里的 `app/parity/` 是 fixture 尚未落到 contracts/d2 前写的旧指向——本轮据实归位，在 goal-breakdown/round-summary 注明此归位。

## 驱动模型：continue 驱动 + 关键节点独立审查（延续 rounds/0005 机制）

由 `$harnessloop-continue` 逐阶段驱动；每阶段内**尽量自动化**（写码派主会话 claude-sonnet-5 子代理，主会话只读审+验收）；**关键节点异构对抗审**（hopper 派 codex/grok 随机池）。REWORK→收残在 client scope 内自动进行。**收敛守卫**：同一阶段第 3 轮 MUST-FIX → 停下 checkpoint 用户。

### 阶段与审查闸

| 阶段 | 内容 | 执行 | 闸 |
|---|---|---|---|
| **A** | **Swift runner + fixture 扩全**：`swift-runner/` 建 Swift fixture runner（解析同一 JSON fixture、按 timeline 驱动一个 Swift mock 内核、产出 `ClientObservableState`，对 `expected` 逐字段比对）；fixture 从 2 扩到**三组全集**：审批五态 FSM（D1 §6.2 + foundation §5.4）/ `OperationOutcome` 七态全集（succeeded/submitted/aborted_no_resend/aborted_resend_failed/aborted_effect_unknown/rejected/timed_out）/ `SessionLockState` 四态（idle/send_pending/interrupt_in_progress/stop_in_progress）。**`advance_clock` 须真实推进虚拟时钟触发 `timed_out` 类转移**（补 TS runner 现有 no-op 缺口，覆盖 timed_out fixture）。 | Sonnet 子代理 | **★审查闸1**（A 后）：异构对抗审 Swift runner 正确性 + fixture 是否真覆盖三组 FSM 全集 + advance_clock 时钟语义；REWORK 则收残再进 B |
| **B** | **C# runner + 三端跨端 parity**：`csharp-runner/` 建 C# runner（镜像 Swift runner，消费同一 fixture）；建**三端 parity 断言**（TS/Swift/C# 对全部 fixture 产出的 `ClientObservableState` 逐字段一致），产出 parity 报告；TS 金标 runner 若需同步补齐 advance_clock 时钟语义以对齐三端，一并补（属 runner 基建，不算越界）。 | Sonnet 子代理 | **★审查闸2**（B 后）：异构对抗审 C# runner parity + 三端一致性（是否真三端跑同一 fixture、是否真逐字段、有无某端偷偷降级/跳过）；REWORK 则收残 |
| **C** | **D4 §4.6 产品行为 parity 首批（按需，可 defer）**：读 D5 相关页，挑首批产品状态机（草稿态 Chat 生命周期 / archive 正交语义 / 能力 toggle 两层模型等候选），按 D4 §4.6 **三分类**（可自动化 fixture / 手工 parity checklist 非自动 / OPEN-deferred 依赖未裁决外部契约）落地：能 fixture 化的建 fixture 进三端 runner，不能的落 checklist，依赖 D3 API 契约未定的标 OPEN/deferred。 | Sonnet 子代理 | **★审查闸3**（C 后，若本轮做）：审分类是否诚实（尤其"标 fixture 化实为占位""该 OPEN 的却硬编期望值"） |

**诚实 defer 边界**：Stage A/B（三端 runner 基建 + 三组 FSM 全集 fixture + 跨端逐字段 parity）达成即满足 SG-8.7 **主体**（"runner 补齐"核心 pass 条件——三端 runner 在全部 kernel-client 层 fixture 上逐字段一致，挂 SG-4/SG-5 验收列）。Stage C（§4.6 产品行为层 parity）依赖读 D5 多页 + 需分类判断，若单轮成本超限，**明确 defer 为后续轮**（记 blocker/结转），不硬塞。以 Stage A/B 是否达成判 SG-8.7 主体 done、Stage C 达成程度如实标注。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/contracts/d2/fixtures/swift-runner/`、`csharp-runner/` | 新建 | Swift/C# fixture runner + 各自 mock 内核 |
| `app/contracts/d2/fixtures/**/*.json` | 新建/扩 | 三组 FSM 全集 fixture（审批五态/OperationOutcome 七态/SessionLockState 四态）+（Stage C）产品行为 fixture |
| `app/contracts/d2/fixtures/ts-runner/`、`dsl.ts` | 改 | 仅为对齐三端补齐 advance_clock 时钟语义/DSL 缺口；不改 fixture 语义 |
| `app/contracts/d2/fixtures/README.md` | 改 | 记三端 runner + fixture 覆盖面 |
| `app/parity/` | —（不新建） | runner 归位到 contracts/d2/fixtures，app/parity 保持空（或删空目录，收尾定） |
| `.harnessloop/goals/.../rounds/0006/` + state | 写 | round 逐阶段收口 |
| `.hopper/`（queue/handoffs） | 写 | 审查闸派发记录 |
| scratchpad | 写 | 探针/临时 |

## Scope 扩张记录（user-confirmed 2026-07-24，★审查闸1 T-048 触发）

**背景**：Stage A 的形式化 parity 复核（Stage A 子代理 flag + codex T-048 二次独立确认）揪出 SG-5 `stop()` 一个真实 D1 §6.2 conformance 缺口——abort 前未 force-deny 待决审批（未执行 M3 定序：①推进 `FORCE_DENIED_ON_STOP`+deny+确认→②才 abort），且 `EventMapping.swift:409/459`（C# 对应处）硬编 `forceResolvedApprovals: nil`，`stop()` 被标"完整"却无 TODO 声明，SG-5「done」被高估。此缺口按本 scope-lock Rollback Condition 停下上报，**用户裁定：现在定向补丁修 SG-5 `stop()`（2026-07-24，AskUserQuestion）**，故本轮 scope 扩张纳入该定向修复。

**新增 Allowed（仅此定向修复）**：`app/kernel-client/{swift,csharp}/` 的 `stop()` 路径 + `EventMapping` 的 `forceResolvedApprovals` 填充 + 对应 `FrameReplayTests`：实现 D1 §6.2 M3 定序（stop 有 pending approval 时先 force-deny 推进 `FORCE_DENIED_ON_STOP`+向内核 deny+确认生效→才 abort，`TurnCompleteEvent.forceResolvedApprovals` 列出被强制终态化 reqId）。Swift 权威 + C# parity 镜像，保 26/26 + 跨端一致。走一轮 ★对抗审。**边界**：仅补 stop-path force-deny（D1 §6.2），不借机实现 `respondApproval()`/`interrupt()` 等其它 SG-5 桩（若 force-deny 确需大量新 deny-RPC 基建，Sonnet 停下报边界，不 scope 蔓延）。

## Disallowed Changes

- 改 `app/kernel-client/{swift,csharp}/` 的 SG-5 已收口实现（**例外见上「Scope 扩张记录」：stop() D1 §6.2 定向修复已 user-confirmed 纳入**；此外 runner 复用其类型/逻辑可 import，但不改其它行为；若 parity 再暴露别的 kernel-client 真 bug，停下记 blocker 上报，不擅改）。
- 改 `app/contracts/d2/schema/`、`app/generated/`（codegen 产物属 SG-1/SG-3；runner 只消费不改；若发现 schema/codegen bug 记 blocker）。
- 改 `kernels/openclaw`/`app/server`/newapi 源码。
- 凭证入 tracked。
- 三插件 submodule、wiki（除非审查发现需修 D4/D5 设计 doc，那走设计 doc 修订不混入本轮代码）。
- 借本轮启动 SG-3/SG-7/UI 等其它子目标编码。

## One-Variable Strict Mode
- Enabled: no
- Reason: 多阶段 runner 基建 + fixture 扩全 + 跨端 parity，分阶段推进。

## Verification Commands Or Checks

| Check | Method | Expected | Evidence |
|---|---|---|---|
| A: Swift runner + fixture | `swiftc` 编译 swift-runner + 跑全部 fixture | exit 0，全 fixture Swift 端 `expected` 逐字段过 | runner 输出 |
| A: fixture 三组全集 | 审批五态/OperationOutcome 七态/SessionLockState 四态 覆盖清点 + advance_clock 触发 timed_out | 三组 FSM 状态/转移全覆盖，timed_out 由虚拟时钟真实触发（非 no-op） | fixture 清单 + runner 日志 |
| A 审查闸1 | hopper 派 codex/grok 审 | PASS/PASS_WITH_NOTE（REWORK 则收残） | `.hopper/handoffs/T-0xx-output.md` |
| B: C# runner + 三端 parity | `dotnet run` csharp-runner + 三端比对脚本 | 三端对全部 fixture 产出 `ClientObservableState` 逐字段一致 | 三端 parity 报告 |
| B 审查闸2 | hopper 派 codex/grok 审 C# parity + 三端一致性 | PASS（REWORK 则收残） | handoff |
| C（若做）: 产品行为 parity 首批 | D4 §4.6 三分类落地 + 能 fixture 化的进三端 runner | 分类诚实、fixture 化项三端一致、OPEN/checklist 如实标注 | §4.6 parity 分类表 + fixture |

## Runtime Recovery Limits
- Recovery round: 可能（runner 编译/fixture 表达/三端不一致 → 只读诊断 + 调实现迭代）
- Blocker type: 预期 `runtime-recoverable`（实现）；若 parity 暴露 kernel-client/schema/codegen 真 bug（须改已收口组件）= `contract-insufficient` 停下上报
- Cleanup: runner 是常驻测试基建，保留

## Rollback Condition
若某阶段发现必须改 SG-5 kernel-client 或 SG-1/SG-3 codegen/schema 源码才能通（如某 fixture 揭示 kernel-client 行为与 D1 契约不符、或生成类型缺字段挡住 runner），停在该阶段边界、明确 defer + 记 blocker，不擅改已 validated 组件。

## Human Confirmation Required
- 各阶段自动化执行 + 审查闸派发：用户已授权"continue 驱动 + 关键节点独立审查"（2026-07-24，延续 rounds/0005），无需逐阶段确认。
- Stage C 是否本轮做 vs defer：由主会话按 Stage A/B 收尾时的剩余成本判断，defer 则如实记，不需另行 gate（属本轮 scope 内的诚实分层）。
- 审查闸 REWORK 的收残：属本轮 recovery，自动进行；若收残需改已收口组件（越出 runner scope）则停下上报。
