# Environment Self-Check

## Detection

Detected environment: claude-code

Detected from: Claude Code 会话（系统提示声明模型 claude-fable-5）

Available tools: Agent 工具（后台子代理，支持 model 参数）、Workflow 编排

Unavailable tools: TODO (owner: user)

## Delegation

Expected mechanism: Agent 工具（后台子代理，支持 model 参数）+ Workflow 编排，均可用

Observed mechanism: 通过 Agent 工具参数指定 model + 任务元数据；无独立运行时探针

Can create independent task: 可（P0 批次已实证，见 docs/validation-log.md 2026-07-16 条目）

Can constrain read/write scope: 可约束只读（P0 批次已实证）

Can require output path: 可指定输出路径（P0 批次已实证）

Can verify evidence citations: 返回带路径引用（P0 批次已实证）

## Model And Effort

Expected model: main=claude-opus-5[1m]（Opus 5, 1M context；用户 2026-08-03 经 /model 切换，该次操作自述“saved as your default for new sessions”，故为持久默认）；write-subagent=claude-sonnet-5（Agent 工具 model:"sonnet" 参数指定，未变） (user-confirmed 2026-08-04)

Observed model: main=claude-opus-5[1m]（系统提示自证，2026-08-04 本会话）；**subagent=claude-sonnet-5（2026-08-05 实跑探针已验证）**——传 `model:"sonnet"` 起的子代理逐字自报「You are powered by the model named Sonnet 5. The exact model ID is claude-sonnet-5.」，与期望一致。注：子代理**无法自证是谁以什么参数启动它**（其原话：无法确定），故严格说这是调用方一侧的端到端观测，非被调方自证。

Expected effort/reasoning: main=max（用户 2026-08-03 经 /effort 设定，该次操作自述“this session only”——**仅本会话生效，不是持久默认**，新会话会回落到未指定状态，届时此字段需重新核对）；**subagent（写入类）=xhigh**(user-confirmed 2026-08-05)——**此值须由调用方在每次 Agent 调用时显式传 `effort: "xhigh"`**，省略即继承会话 effort、该声明随即失效。**⚠ 该期望值不可由被调方验证**，见下 Verification method。

Observed effort/reasoning: main=max（本会话，来源同上：用户 /effort 操作的自述，非独立运行时探针）；**subagent=不可观测**——2026-08-05 实跑身份自报探针，子代理明确回答其上下文中**没有任何关于 effort/reasoning 的说明**（原文：「没有。我的上下文里没有任何关于推理强度/effort/reasoning level 的明确说明。」）。只能由调用方单方面断言传了什么，无法由被调方自证用了什么。

Verification method: **模型**=运行时探针可验（2026-08-05 已实跑：子代理自报模型 id，与所传参数一致）；**effort**=**原理上不可由此机制验证**——Agent 工具 schema 里 `opts.effort` 是调用方可设的（low|medium|high|xhigh|max），但被调方上下文中不含任何 effort 信息，无从自报。即「可设不可观测」。要验证只能换机制（行为侧推断，或信任调用方自身记录）。

Mismatch action: 委派前跑 $harnessloop-delegation 语义自检；不可验证时回退主会话执行或请求用户确认

Residual risk: **subagent 的 effort 不可验证**（模型侧此前的同名风险已于 2026-08-05 由实跑探针消除）。具体：写入类子代理声明 effort=xhigh，但该声明只能由调用方单方面保证；若某次调用漏传 `effort` 参数，会静默回落为继承会话 effort，而**没有任何机械信号会提示这次回落**。

## Result

Pass/fail: pass-with-open-items（TODO (owner: user) 未决若干；残余风险：**subagent 的 effort 不可验证**——模型侧的同名风险已于 2026-08-05 由实跑探针消除）

Allowed next actions: TODO (owner: user)

Required human action: TODO (owner: user)

Last checked: 2026-08-05（$harnessloop-delegation：实跑 subagent 身份自报探针；模型侧验证通过、effort 侧确认不可观测；subagent 写入类 effort 期望值经用户裁决定为 xhigh）
