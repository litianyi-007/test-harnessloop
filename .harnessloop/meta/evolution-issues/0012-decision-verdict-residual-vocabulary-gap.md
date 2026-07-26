# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0012
- Priority: P1（非官方模板字段，见 TH-0011 「分类说明」的统一解释）
- Issue class: template-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 3 的定案条目
- Created at: 2026-07-26

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: `.harnessloop/goals/20260718-002-agent-app/goal.md`
- Active round path: n/a（跨 goal 002 全部 10 轮的横向观察，非单一 round）
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md`（`Feedback:` :6、`Accepted:` :9）
- Related handoffs: hopper T-044/T-045（rounds/0005 REWORK→MUST-FIX）、T-048/T-050/T-051（rounds/0006 Stage A：REWORK→MUST-FIX→CONFIRMABLE）、T-052/T-053（rounds/0006 Stage B：REWORK→CONFIRMABLE）
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §2.1 表格行 C
- Related reviews: T-061（对该数字与判据的独立复算确认，`.hopper/handoffs/T-061-output.md`）
- Related evolution issues: 无直接关联既有条目（本条与 TH-0013 同属计划 PR2，但根因不同——本条是词汇枚举缺口，TH-0013 是执行留痕缺口）

## Expected Harnessloop Behavior

`decision-template.md` 的 `Feedback`/`Accepted` 枚举应能表达"轮内经历多次 REWORK/MUST-FIX 才收盘"与"一次干净通过"之间的区别，不应让两种性质不同的收盘方式在协议留痕层面完全无法区分。

## Actual Harnessloop Behavior

`decision-template.md` :6 的 `Feedback: positive | negative | neutral | blocked` 与 :9 的 `Accepted: yes | no` 加起来只有粗粒度的二值×四值组合。goal 002 十份 `decision.md` 逐份核实为 **10/10 Feedback: positive + Accepted: yes**，但其中 `rounds/0005`、`rounds/0006` 都是轮内多次 REWORK/MUST-FIX 之后才收盘的 round——0005：codex T-044 REWORK → codex T-045 MUST-FIX；0006 Stage A：codex T-048 REWORK → codex T-050 MUST-FIX → grok T-051 CONFIRMABLE，Stage B：codex T-052 REWORK → codex T-053 CONFIRMABLE——与一次干净通过的 round（如 `rounds/0007`、`rounds/0008`）在 `decision.md` 留痕层面完全无法区分。`rounds/0001` 的 `Accepted: yes` 后面缀了中文括号注解"（追认已交付工作、归位状态）"——诚实性目前完全依赖模型主动往枚举值后面塞自然语言注解来维持，协议本身没有提供合法字段承载这类信息。

## Minimal Reproduction From Files

1. Read: `.harnessloop/goals/20260718-002-agent-app/rounds/{0001..0010}/decision.md` 的 `Feedback`/`Accepted` 行
2. Observe: `grep "Feedback:\|Accepted:" rounds/*/decision.md` → 10/10 均为 `positive`/`yes`；对照 `round-summary.md` 可见 0005/0006 两轮内部审查往返次数（2-3 次 REWORK/MUST-FIX）远高于其余轮次，但 `decision.md` 无法体现这种差异
3. Expected next protocol action: 收盘留痕应能区分"零往返直接通过"与"多次 REWORK 后收盘"
4. Actual next protocol action: 两者在 `decision.md` 里得到完全相同的 `positive`/`yes` 记录，唯一的区分手段是模型自愿在 `Accepted: yes` 后面手写中文注解

## Attempted Local Mitigation

- Evidence refresh: 已逐份 grep goal 002 十份 `decision.md` 核实 10/10 塌缩为 `positive`/`yes`；已用 T-061 独立复算确认无出入
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段）

## Suggested Upstream Improvement

- Candidate target: template（`decision-template.md`）+ validation script（`verify_protocol.py`）+ main skill（`harnessloop-status/SKILL.md`）
- Proposed smallest change（已定案，见 `docs/harnessloop-evolution-plan-20260726.md` §3.1 E4，**尚未执行**）：
  1. `decision-template.md` `- Feedback:`(:6) 之后加两行：`- Verdict: pass | pass-with-residual | fail | inconclusive`、`- Residuals: none | <一行一条：声称了什么/哪部分未覆盖/defer 去向>`。
  2. `verify_protocol.py` 加约 5 行规则：同一份 `decision.md` 内 `Verdict: pass` 且 `Residuals` 非 `none` → violation kind `verdict-residual-contradiction`。硬性设计约束：只做同文件内两个枚举行的比较，不解析散文、不做路径解析、不跨文件 join、不做值归一化。
  3. `harnessloop-status/SKILL.md` Output Contract 加 1 行，报本 goal 内 `pass`/`pass-with-residual` 的分布。
  4. 零迁移验证：对 14 个既有 round（无这两字段）必须不报错（缺字段不判违规，只在两字段都存在时比较）——已实测确认成立。
- 实现隐患（执行时注意，T-061 提醒）：枚举比较建议做 `strip().lower()`，否则 `Verdict: Pass`（大写）会假绿放过矛盾。
- 已知局限（计划自承，T-061 认可接受）：`pass-with-residual` 会沦为默认对冲词，没有任何机械手段能防住；本条买到的只是"`Verdict: pass` 且 `Residuals` 非 `none`"这个可 grep 的矛盾，不是诚实性强制，status 分布行只让漂移可见，不是控制。
- Why this generalizes beyond this project: 任何要求"轮次收盘时留一句判断"的协议，都会遇到"部分通过"这个中间态无枚举可用、只能靠自然语言注解硬撑的问题。
- Risks of overfitting: 低——同文件内两个字面枚举值的比较，不引入新解析器/路径解析/跨文件 join。

## Resolution

- Resolution status: open（计划已定案，由 E4 关闭，PR2 = E3+E4，尚未执行）
- Upstream change: 待执行
- Backported to local policy: no
- Backport path: 待定 → `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md`、`harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py`、`harnessloop/plugins/harnessloop/skills/harnessloop-status/SKILL.md`
- Follow-up required: 是——(1) 执行后对 14 个既有 round 回归验证零新红；(2) 双向 mutation teeth 需进 `validate.py`（pass/fail 两方向都必须翻转）；(3) 连续观察 3 轮，若 `pass` 占比持续为 0（即 `pass-with-residual` 完全吞并 `pass`），按计划回退条款（见 `docs/harnessloop-evolution-plan-20260726.md` §6）只保留 `Residuals` 字段、删除 `Verdict` 判定规则（约 5 行）。
