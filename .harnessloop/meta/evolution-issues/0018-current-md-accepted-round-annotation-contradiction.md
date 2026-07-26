# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0018
- Priority: P3（非官方模板字段，见 TH-0011「分类说明」的统一解释；计划原文标注为"state-hygiene"，该值不在 Record 阶段 Issue class 枚举中，故 Issue class 字段另择 `contradiction`，见下方分类说明）
- Issue class: contradiction
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 9 的定案条目
- Created at: 2026-07-26

分类说明：计划原文用"state-hygiene"描述本条性质，Record 阶段 Issue class 枚举无此值；本条内容本质是`current.md`的批注文本与`decision.md`的实际记录相矛盾，直接匹配枚举内已有的 `contradiction` 值，故采用该值。

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: n/a（跨 `current.md` 与 goal 002 全部 10 轮 `decision.md` 的横向比对）
- State files: `.harnessloop/state/current.md`（:9 `Last accepted round` 行）
- Related handoffs: 无
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §2.1 表格行 G
- Related reviews: 无
- Related evolution issues: 无直接关联既有条目

## Expected Harnessloop Behavior

`state/current.md` 的 `Last accepted round` 字段及其附带注解，应与协议实际记录的 `Accepted:` 值保持一致，且该字段的作用域（是"全项目"还是"当前 active goal"）应有协议口径可依。

## Actual Harnessloop Behavior

`current.md:9` 原文为：`- Last accepted round: 20260716-001-setup-wizard/0004（沿用既有历史；本 goal 尚无已接受轮次）`。字段值本身（`20260716-001-setup-wizard/0004`）对 **goal 001** 而言是正确的、有历史依据的；但括号里的注解"本 goal 尚无已接受轮次"与 **goal 002** 的实际记录矛盾——goal 002 十份 `decision.md` 逐份 grep `Accepted: yes` = **10/10 命中**（`rounds/0001` 至 `rounds/0010` 各一处）。矛盾的根源是 `Last accepted round` 这个字段的作用域协议从未定义过（是全局最后一次接受、还是当前 active goal 内最后一次接受），导致注解在切换 active goal 后没有被同步更新，读起来像是在断言"goal 002 无 accepted round"，而这是假的。

## Minimal Reproduction From Files

1. Read: `.harnessloop/state/current.md:9`
2. Observe: `grep -c "Accepted: yes" .harnessloop/goals/20260718-002-agent-app/rounds/*/decision.md` → 10 处命中（`rounds/0001`–`rounds/0010` 各 1），与 `current.md:9` 括号注解"本 goal 尚无已接受轮次"直接矛盾
3. Expected next protocol action: 注解应准确反映当前 active goal（goal 002）的实际 accepted 记录，或该字段应明确其作用域不随 active goal 切换
4. Actual next protocol action: 注解仍停留在 goal 002 尚未产生任何 accepted round 时写下的措辞，未随后续 10 轮全部 `Accepted: yes` 的事实更新

## Attempted Local Mitigation

- Evidence refresh: 已 `sed -n '9p'` 确认 `current.md` 原文；已逐份 grep goal 002 十份 `decision.md` 确认 10/10 `Accepted: yes`
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段；实际清账动作留待项目侧后续 round/self-audit 执行）

## Suggested Upstream Improvement

- Candidate target: 项目侧一次编辑（`current.md`）+ template（`references/current-state-template.md` 或等价文件，加口径注释）
- Proposed smallest change: 计划裁定为项目侧一次编辑清账 + 模板加 1 行口径注释，**不建门**——这不是需要机械检测的问题：字面矛盾只有人读才会发现，机械上两处字段分属不同文件、不同粒度，做跨文件一致性检测正是本轮判据明确排除的"新解析器/跨文件 join"类工作（见 `docs/harnessloop-evolution-plan-20260726.md` §4 核心裁定判据）。
  - 项目侧动作（本条记录任务本身未执行，留待后续 round/self-audit 处理）：编辑 `current.md:9`，去掉或改写"本 goal 尚无已接受轮次"这句过期注解，使其与 goal 002 的实际 accepted 记录一致（或明确该字段就是"全局最后一次"，不随 active goal 切换）。
  - 框架侧动作（建议）：在 `references/current-state-template.md`（或等价模板）的 `Last accepted round` 字段旁加一行注释，声明该字段的作用域口径（全局 vs 当前 goal），避免后续项目重复同一混淆。
- Why this generalizes beyond this project: 任何维护"当前状态摘要 + 历史批注"这种模式的协议字段，只要字段作用域没有被显式定义，就会在跨 goal/跨阶段时出现批注过期的问题。
- Risks of overfitting: 低——纯文档口径澄清，不引入判定逻辑。

## Resolution

- Resolution status: open（项目侧一次编辑清账 + 模板加口径注释；不建门）
- Upstream change: 待执行（模板注释部分）
- Backported to local policy: no（项目侧编辑本身不算"上游改动的本地回填"，是独立的项目侧清账动作，尚未执行）
- Backport path: 无
- Follow-up required: 是——(1) 项目侧后续 round 或 self-audit 中编辑 `current.md:9` 清账；(2) 框架侧评估是否要给 `Last accepted round` 字段补口径注释。
