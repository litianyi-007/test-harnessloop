# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0014
- Priority: P1（非官方模板字段，见 TH-0011「分类说明」的统一解释）
- Issue class: template-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 5 的定案条目
- Created at: 2026-07-26

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: n/a（跨全 goal 生命周期的结构观察）
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/goal-breakdown-template.md`（`## Subgoals`，:25-28）、`.harnessloop/goals/20260718-002-agent-app/goal-breakdown.md`（法定表 :176-185；自造表「首批开发子目标」:91 起、「SG-8 验收清单」:115 起、「第二批开发子目标」:158 起）
- Related handoffs: 无
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §5 item 5、§3.3 条目 6（原簇2-P3 提案的证伪理由，"根因移入 B4"）
- Related reviews: T-061（§3 抽检确认"簇2 三提案全砍"结论无误杀）
- Related evolution issues: 无直接关联既有条目

## Expected Harnessloop Behavior

`goal-breakdown-template.md` 的 `## Subgoals` 表（:25-28，列为 ID / Subgoal / Depends on / Evidence required / Validation method / Risk）应能承载实现阶段真实使用的子目标追踪粒度，使项目不需要另起自造表格。

## Actual Harnessloop Behavior

本项目法定 `## Subgoals` 表（`goal-breakdown.md:176-185`）装的是需求分析阶段已死的 **RA-L1..RA-L4** 四行，自 RA-L4 之后再未更新；真实的 **SG-1..SG-14**（实现阶段子目标，`goal-breakdown.md` 内 `SG-1` 字面出现 60 次、精确边界匹配 15 次）住在项目自己另起的表格/小节里——「首批开发子目标」（:91 起）、「SG-8 验收清单」（:115 起）、「第二批开发子目标」（:158 起）——用的是自造的中文小节标题而非模板既有的表格列（ID/Subgoal/Depends on/Evidence required/Validation method/Risk）。

## Minimal Reproduction From Files

1. Read: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/goal-breakdown-template.md:25-28`（模板 `## Subgoals` 表结构）
2. Observe: `.harnessloop/goals/20260718-002-agent-app/goal-breakdown.md:176-185`（法定表内容止步于 RA-L1..RA-L4）；`grep -n "^## \|^### " goal-breakdown.md` 可见实现阶段内容全部落在「实现阶段（RA-L5 / IMPL）议程」等自造 `###` 小节下，不在法定 `## Subgoals` 表内；`grep -c "SG-1\b" goal-breakdown.md` = 15，`grep -o "SG-1" goal-breakdown.md | wc -l` = 60
3. Expected next protocol action: 实现阶段子目标应能沿用或扩展法定 `## Subgoals` 表结构记录
4. Actual next protocol action: 项目另起 5 张自造表/小节（含自造"状态"中文列），法定表冻结在需求分析阶段不再更新

## Attempted Local Mitigation

- Evidence refresh: 已实测 `grep`/`wc` 确认法定表内容与自造表结构差异；已用 T-061 抽检确认该证伪结论无误杀
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段）

## Suggested Upstream Improvement

- Candidate target: template（`goal-breakdown-template.md`）
- Proposed smallest change（B4，后做第二批，见 `docs/harnessloop-evolution-plan-20260726.md` §3.2，**尚未执行**）：`goal-breakdown-template.md` 承认"每阶段一张表"，或独立新增 `## Implementation Subgoals` 小节；**不配 lint、不配迁移脚本**。
- 根因判定（计划 §3.3 条目 6 证伪理由）：法定表是需求分析阶段的形状，不是"缺两列"能补齐的问题——原簇2-P3 提案（Status/Rounds 列 + 迁移脚本）已被证伪：法定 `## Subgoals` 内 >600 字符行 = **0**，可迁移单元格 = **0**，其 teeth(a) 的断言循环一次都不会执行，落点是本项目已废弃的死表。
- Why this generalizes beyond this project: 需求分析→实现两阶段子目标的追踪粒度和列语义本来就不同，任何走过这两阶段的 goal 都会撞上同一形状不匹配问题，不是本项目特有的表格设计失误。
- Risks of overfitting: 低——只是承认既有实践形态（每阶段一张表），不建 lint/迁移脚本（迁移目标本身为空）。

## Resolution

- Resolution status: open（计划已定案，B4，第二批"后做"，前置条件：无——可立即排，但计划建议先跑满 E1–E5 一轮再排）
- Upstream change: 待评估/待执行
- Backported to local policy: no
- Backport path: 待定 → `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/goal-breakdown-template.md`
- Follow-up required: 是——排期上晚于 E1–E5（本轮五条先做项），不晚于 B1/B2（TH-0008 的解锁链条）；无独立 teeth（纯结构承认，不建门）。
