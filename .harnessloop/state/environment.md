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

Observed model: main=claude-opus-5[1m]（系统提示自证，2026-08-04 本会话）；subagent=通过 Agent 工具参数指定 + 任务元数据，无独立运行时探针

Expected effort/reasoning: main=max（用户 2026-08-03 经 /effort 设定，该次操作自述“this session only”——**仅本会话生效，不是持久默认**，新会话会回落到未指定状态，届时此字段需重新核对）；subagent=TODO (owner: user)

Observed effort/reasoning: main=max（本会话，来源同上：用户 /effort 操作的自述，非独立运行时探针）；subagent=TODO (owner: user)

Verification method: Agent 工具参数指定 + 任务元数据（无独立运行时探针验证 subagent 实际使用的模型/effort）

Mismatch action: 委派前跑 $harnessloop-delegation 语义自检；不可验证时回退主会话执行或请求用户确认

Residual risk: subagent 模型无运行时探针验证

## Result

Pass/fail: pass-with-open-items（5 处 TODO (owner: user) 未决；残余风险：subagent 模型无运行时探针验证）

Allowed next actions: TODO (owner: user)

Required human action: TODO (owner: user)

Last checked: 2026-08-04（AUDIT-20260804-PRECONTINUE-SG10 期间核对：此前 Expected model 仍写 claude-fable-5，与本会话实际不符，已按用户裁决更新）
