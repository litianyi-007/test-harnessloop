# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0016
- Priority: P2（非官方模板字段，见 TH-0011「分类说明」的统一解释）
- Issue class: skill-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 7 的定案条目
- Created at: 2026-07-26

分类说明：计划原文将此条标注为"workflow-gap"，Record 阶段的 Issue class 枚举无此值；比照 TH-0002 的既有分类惯例（SKILL.md 步骤未完整枚举某类应做的写入动作），归为 skill-gap。

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: n/a（跨全项目历史的结构观察）
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md`（Loop Continuation :491-511）、`.harnessloop/meta/self-audit.md`（15 个全量条目，约 106KB）
- Related handoffs: 无
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §5 item 7、§3.3 条目 11（原"方案C：收官写入集枚举+引用不复述禁令+delta self-audit"提案的证伪理由）
- Related reviews: T-061（同意方案 C 方向错误的判断）
- Related evolution issues: 与 `.harnessloop/meta/evolution-issues/0010-impl-phase-round-bypass-state-drift.md`（TH-0010）相关但不同层——TH-0010 记录的是"实现阶段整体绕开 round 闭环"这一更大的结构性缺口；本条记录的是即便 round 闭环被走了，Loop Continuation 本身列举的写入动作也不完整，是同一类"记录集不完整"问题在更细粒度上的表现

## Expected Harnessloop Behavior

`harnessloop-loop/SKILL.md` 的 Loop Continuation（:491 起）应完整枚举一轮收盘时会被写入的全部协议文件，使换会话/换执行者时不会遗漏。

## Actual Harnessloop Behavior

Loop Continuation 8 个编号步骤里，真正对应"写入动作"的只有 3 个：步骤 2（`round-summary.md`，:496，含 `## Cost` 段）、步骤 3（`decision.md`，:497）、步骤 5（`meta/self-audit.md`，:499，且带条件"when the round exposes loop-health risk"）。但本项目实际收官写入集是 **7 处**：`round-summary.md` / `decision.md` / `self-audit.md` / `state/current.md` / `state/evidence-index.md` / `goal-breakdown.md` / `thresholds.md`——后 4 个（`current.md`/`evidence-index.md`/`goal-breakdown.md`/`thresholds.md`）在 Loop Continuation 的 8 步里完全没有被提及，只活在主会话的隐性习惯里，换一个会话/换一个执行者就会失传（TH-0010 记录的"实现阶段绕开 round 闭环"正是这类失传的一个更大规模的实例）。

此外，步骤 5 的条件触发措辞（"when the round exposes loop-health risk"）在实践中形同虚设——`self-audit.md` 目前累计 **15 个全量条目、约 106KB**，项目并未真的按"仅当有 loop-health risk 时才写"这个条件筛选，而是每轮都写了完整块。

## Minimal Reproduction From Files

1. Read: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md:491-511`（Loop Continuation 完整 8 步）
2. Observe: 步骤 2/3/5 是仅有的三处写入动作；`current.md`/`evidence-index.md`/`goal-breakdown.md`/`thresholds.md` 无一在 8 步中被提及，但 `self-audit.md` 逐条历史记录（如 TH-0010 的补记）显示这 4 份文件在实际收官时确实被同步更新
3. Expected next protocol action: 协议文本应能覆盖实际发生的全部收官写入动作
4. Actual next protocol action: 4/7 处写入动作只存在于主会话习惯里，不在协议正文的枚举范围内

## Attempted Local Mitigation

- Evidence refresh: 已核对 Loop Continuation 8 步与本项目实际收官写入集的差集；已核实 `self-audit.md` 15 个全量条目、约 106KB 的规模事实
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段）

## Suggested Upstream Improvement

- Candidate target: main skill（`harnessloop-loop/SKILL.md` Loop Continuation）
- Proposed smallest change: **本轮只记录不修**——此前"方案 C"（收官写入集枚举 + 引用不复述禁令 + delta self-audit，约 700 行）尝试过用生成器/强制枚举解决这个问题，已被证伪：`SKILL.md:499` 本身就是条件触发规则（"when the round exposes loop-health risk"），但项目照样写了 15 个全量块，证明"写更多规则文本"这条路对本仓已知无效（方案 C 的执行力已被"条件触发规则被无视 15 次"实证证伪，见计划 §3.3 条目 11）。
- 该问题真正不可移植的知识只有"收官到底该写哪七处"这一份清单本身，而不是"如何强制模型遵守"——后者已证伪，前者值得留存以供后续人工参考，故本轮选择只记录、不新增机械或模板约束。
- Why this generalizes beyond this project: 任何"closeout"性质的写入集，只要协议文档只枚举了其中一部分，就会有另一部分退化为"约定俗成而非白纸黑字"，在换执行者/换会话时静默丢失。
- Risks of overfitting: 记录本身零风险（不改代码/协议）；风险在于误读为"应该去补全枚举"——计划明确裁定不应该这么做，方案 C 已证伪。

## Resolution

- Resolution status: open（本轮只记录不修，无对应 E1–E5/B1–B4 承接项）
- Upstream change: 无（本轮不改协议文本）
- Backported to local policy: no
- Backport path: 无
- Follow-up required: 否——本条 disposition 是"记录在案，供后续人工参考"，不建门、不改协议、不排期修复；若后续有新的、不同于方案 C 的思路（例如不依赖模型自觉遵守条件触发规则的机制），可重新评估。
