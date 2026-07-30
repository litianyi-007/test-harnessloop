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

Expected model: main=claude-fable-5/xhigh；write-subagent=claude-sonnet-5（Agent 工具 model:"sonnet" 参数指定）

Observed model: main=claude-fable-5（系统提示自证）；subagent=通过 Agent 工具参数指定 + 任务元数据，无独立运行时探针

Expected effort/reasoning: main=ultracode/xhigh；subagent=TODO (owner: user)

Observed effort/reasoning: TODO (owner: user)

Verification method: Agent 工具参数指定 + 任务元数据（无独立运行时探针验证 subagent 实际使用的模型/effort）

Mismatch action: 委派前跑 $harnessloop-delegation 语义自检；不可验证时回退主会话执行或请求用户确认

Residual risk: subagent 模型无运行时探针验证

## Result

Pass/fail: pass-with-open-items（5 处 TODO (owner: user) 未决；残余风险：subagent 模型无运行时探针验证）

Allowed next actions: TODO (owner: user)

Required human action: TODO (owner: user)

Last checked: 2026-07-16
