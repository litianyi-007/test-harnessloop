# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0013
- Priority: P1（非官方模板字段，见 TH-0011「分类说明」的统一解释）
- Issue class: skill-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 4 的定案条目
- Created at: 2026-07-26

分类说明：计划原文将此条标注为"workflow-gap"，但 harnessloop-issue 的 Record 阶段 Issue class 枚举无此值；比照 TH-0002（同样是"SKILL.md 未要求记录/触发某个动作"）的既有分类惯例，归为 skill-gap——根因是 Loop Continuation 步骤未要求把机械门的执行结果写回 `decision.md`，而不是缺一个模板字段本身（该字段由 E4 一并新增，两者同一个 PR2 落地，但根因层面彼此独立，故与 TH-0012 分开记录）。

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: n/a（跨 goal 002 全部 10 轮的横向观察）
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md`（Loop Continuation 步骤 1，:495）、`harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md`（:9 `Accepted:` 行）
- Related handoffs: 无
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §2.1 表格行 B
- Related reviews: T-061（`.hopper/handoffs/T-061-output.md`，对 0/10 数字的独立复算确认）
- Related evolution issues: `.harnessloop/meta/evolution-issues/0011-verify-rule-a-zero-inspected-blind-pass.md`（TH-0011：同一根因链条的上一环——即便门被正确调用且结果可信，其执行痕迹也从未进入被检的协议工件）；`.harnessloop/meta/evolution-issues/0012-decision-verdict-residual-vocabulary-gap.md`（TH-0012：同一 PR2 落地，但根因是词汇枚举缺口而非留痕缺口）

## Expected Harnessloop Behavior

`decision.md` 应能留痕"机械门本轮是否被跑过、结果如何"，使"门是否被执行"这件事本身可被后续审查者机械核对，而不是只能相信模型的自我叙述。

## Actual Harnessloop Behavior

goal 002 十份 `decision.md` 逐份 `grep verify_protocol` = **0/10 命中**。门是否被执行、执行结果如何，在协议内完全不可查——这与 TH-0011 描述的"门空跑"是同一根因链条的下一环：即便门被跑了（正如 `SKILL.md:495` Loop Continuation 步骤 1 已要求"Run the mechanical protocol gate ... If it exits non-zero, this round must not be marked positive"），其执行痕迹也不会进入任何被检的协议工件。

## Minimal Reproduction From Files

1. Read: `.harnessloop/goals/20260718-002-agent-app/rounds/{0001..0010}/decision.md`
2. Observe: `rg -c verify_protocol .harnessloop/goals/20260718-002-agent-app/rounds/*/decision.md` → 全部为 0（或无命中）
3. Expected next protocol action: 每份 `decision.md` 应能 grep 到门的 exit code 与覆盖遥测行
4. Actual next protocol action: 无一份 `decision.md` 提及 `verify_protocol`，"这个门十轮里连被声称跑过都没有"

## Attempted Local Mitigation

- Evidence refresh: 已逐份 grep goal 002 十份 `decision.md` 确认 0/10 命中；已用 T-061 独立复算确认无出入
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段）

## Suggested Upstream Improvement

- Candidate target: template（`decision-template.md`）+ main skill（`harnessloop-loop/SKILL.md` Loop Continuation）
- Proposed smallest change（已定案，见 `docs/harnessloop-evolution-plan-20260726.md` §3.1 E3，**尚未执行**）：
  1. `decision-template.md` `- Accepted:`(:9) 之后加一行：`- Mechanical gate: <exit-code> / <verify_protocol.py 的 coverage 行原文> / <运行时刻>`。
  2. `harnessloop-loop/SKILL.md` Loop Continuation 步骤 1 末尾加一句："Record the gate's exit code and its coverage line verbatim in decision.md. A round whose decision.md lacks this line has not completed step 1."
  3. 依赖 E2（coverage 行必须先存在，否则抄的是会撒谎的满分横幅，见 TH-0011）。
- **T-061 遗漏项 #1（并入本条，不另开新提案包——理由：同一落点、同一 PR，紧随实现即可）**：门收据宜由脚本落盘而非仅靠模型抄写——`verify_protocol.py` 成功/失败时另写 `rounds/NNNN/mechanical-gate.json`（exit、coverage、utc），`decision.md` 只引用该文件路径；比"模板行由模型手抄"更难伪造，建议作为 E3 的实现增强或紧随 PR 落地。
- 已知局限（计划自承）：这条会退化成套话（模型复制粘贴 coverage 行），但严格优于无记录；它买的是审计轨迹，不是控制力，必须照这个卖。
- Why this generalizes beyond this project: 任何要求"轮次收盘前先跑机械门"的协议，只要门的执行结果不进入被检工件，就无法与"从未跑过"区分——这是执行留痕缺失这一类问题的通用形态。
- Risks of overfitting: 低——只新增一行留痕字段，不改变门本身的判定逻辑。

## Resolution

- Resolution status: open（计划已定案，由 E3 关闭，PR2 = E3+E4，尚未执行）
- Upstream change: 待执行
- Backported to local policy: no
- Backport path: 待定 → `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md`、`harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md`
- Follow-up required: 是——**teeth**：基线是 0/10；下一轮若 `decision.md` 仍无此行，本条按计划判定失败并回滚。若审查（E5(b) 审查必查项）也报不出来，则本条无牙齿，当场降级为纯建议并记入 `self-audit`，不留着当假绿（计划 §6 回退条款）。
