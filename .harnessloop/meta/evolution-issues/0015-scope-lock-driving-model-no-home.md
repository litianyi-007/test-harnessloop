# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0015
- Priority: P2（非官方模板字段，见 TH-0011「分类说明」的统一解释）
- Issue class: template-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 6 的定案条目
- Created at: 2026-07-26

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: `.harnessloop/goals/20260718-002-agent-app/rounds/0005/`（首次出现自创驱动模型小节的轮次）
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/scope-lock-template.md`（八节：Round Objective/Allowed Changes/Disallowed Changes/One-Variable Strict Mode/Verification Commands Or Checks/Runtime Recovery Limits/Rollback Condition/Human Confirmation Required）
- Related handoffs: 无
- Related evidence: `.harnessloop/goals/20260718-002-agent-app/rounds/0005/scope-lock.md:9`（"驱动模型…（用户 2026-07-24 指定）"原文）；`docs/harnessloop-evolution-plan-20260726.md` §5 item 6、§3.3 条目 1
- Related reviews: T-061（§3 同意计划裁定，无误杀）
- Related evolution issues: 无直接关联既有条目

## Expected Harnessloop Behavior

`scope-lock-template.md` 应为"驱动模型 / 阶段与闸位 / 验收分层"这类项目常用的执行元信息提供合法落点，使项目不需要每次自行发明格式。

## Actual Harnessloop Behavior

`scope-lock-template.md` 现有八节（Round Objective/Allowed Changes/Disallowed Changes/One-Variable Strict Mode/Verification Commands Or Checks/Runtime Recovery Limits/Rollback Condition/Human Confirmation Required）没有一节是为"本轮由谁/什么机制驱动"设计的。本项目 `rounds/0005/scope-lock.md:9` 起自创了 `## 驱动模型：continue 驱动 + 关键节点独立审查（用户 2026-07-24 指定）` 一整节外加"阶段与审查闸"表格，此后共 6 个 round 反复自创同类内容，形态分裂成至少三种：表格（如 0005）、三行散文、并行轨小节（如 0009 的轨 A/轨 B 双轨并行结构），因为模板给不出统一落点。

## Minimal Reproduction From Files

1. Read: `.harnessloop/goals/20260718-002-agent-app/rounds/0005/scope-lock.md:9-15`（自创"驱动模型"小节 + "阶段与审查闸"表格）
2. Observe: 对比 `rounds/0009/scope-lock.md`（并行双轨散文形态：轨 A openclaw / 轨 B hermes），同一类"驱动力归属"信息的呈现形态因轮而异，无统一结构
3. Expected next protocol action: 该类信息应有一个模板认可的落点，形态可以稳定
4. Actual next protocol action: 每轮各自决定怎么写，6 轮出现至少 3 种不同形态

## Attempted Local Mitigation

- Evidence refresh: 已核实 `rounds/0005/scope-lock.md:9` 原文；已对照 `rounds/0009` 的并行双轨结构确认形态差异
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段）

## Suggested Upstream Improvement

- Candidate target: template（`scope-lock-template.md`）
- Proposed smallest change（B3，后做第二批，见 `docs/harnessloop-evolution-plan-20260726.md` §3.2，**尚未执行**）：`scope-lock-template.md` 加 `## Driving Model (optional — delete when not applicable; never write "N/A")`，正文是**三条提示句而非字段**——阶段与闸位 / 验收分层（must/best-effort/deferred + 承接方）/ 收敛守卫何时停下问人。
- 明确不硬化为必填字段或表格的理由（计划 §3.3 条目 1 证伪原文）：`rounds/0005/scope-lock.md:9` 原文写着"驱动模型…（用户 2026-07-24 指定）"，阶段/闸模型来自**用户指令**，不是"模板里看不到这个选项"；"已收敛的形状"实测只在 2/10 轮以表格出现，`0009` 是并行双轨散文——把品味硬化成顺序表会**逼真实轮次撒谎**。
- Why this generalizes beyond this project: 任何走"多阶段 + 异构审查闸"这种驱动模型的项目，都需要一个合法的地方写清楚"这轮谁在开车、验收怎么分层"，而不是每次自己发明格式。
- Risks of overfitting: 中——如果做成必填字段/表格而非"可选提示句"，会与不需要该信息的简单轮次冲突；计划已选择"提示句"这一较低风险形态。

## Resolution

- Resolution status: open（计划已定案，B3，第二批"后做"，前置条件：E1–E5 跑满 1 轮）
- Upstream change: 待评估/待执行
- Backported to local policy: no
- Backport path: 待定 → `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/scope-lock-template.md`
- Follow-up required: 是——排期晚于 E1–E5（需先跑满一轮观察新协议下的实际使用形态，再决定提示句的具体措辞）；无机械 teeth（纯提示句无法验证是否起作用，计划明确排除在有 teeth 的五条之外，避免稀释本轮验收纪律）。
