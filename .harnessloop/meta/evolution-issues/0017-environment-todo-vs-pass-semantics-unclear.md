# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0017
- Priority: P2 · 待定（非官方模板字段，见 TH-0011「分类说明」的统一解释；「待定」为计划原文标注，表示分类本身待裁定后可能改变）
- Issue class: documentation-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 8 的定案条目
- Created at: 2026-07-26

分类说明：本条按 harnessloop-issue skill 的 Record Workflow 第 4 条（"若分类不确定，用 documentation-gap 处理不清楚的用户可见行为"）暂定为 documentation-gap；计划原文本身标注为"[P2] 待定"，需先裁定这是项目侧数据错误还是脚本语义缺口，才能决定最终分类与是否改脚本，裁定前不应改脚本（详见下方 Actual Behavior 的双解读并存说明）。

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（`state/environment.md` 是项目级文件，非绑定单一 goal）
- Active round path: n/a
- State files: `.harnessloop/state/environment.md`（`## Detection`/`## Model And Effort`/`## Result` 三段）、`harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py`（`field_todo_count` 设计意图，见模块 docstring :42-46）
- Related handoffs: 无
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §5 item 8
- Related reviews: 无
- Related evolution issues: 无直接关联既有条目；与 TH-0012（Verdict/Residuals 词汇缺口）在"部分通过如何表达"这一主题上可能同构，值得后续一并评估是否合并处理（见下方 Suggested Upstream Improvement）

## Expected Harnessloop Behavior

`state/environment.md` 的 `## Result` 段 `Pass/fail` 判定与同文件内其余字段的完整度之间的关系应该是清楚的——要么 TODO 字段参与判定（此时 `Pass/fail: pass` 与存在 TODO 矛盾，应报告为未完成），要么明确不参与判定（此时不构成矛盾，但协议应有文档说明为什么）。

## Actual Harnessloop Behavior

`state/environment.md` 当前状态（已实测确认）：`## Detection` 的 `Unavailable tools` 为 `TODO (owner: user)`；`## Model And Effort` 的 `Expected effort/reasoning`（subagent 部分）与 `Observed effort/reasoning` 均为 `TODO (owner: user)`；`## Result` 的 `Allowed next actions`、`Required human action` 也都是 `TODO (owner: user)`——全文件共 **5 处**字面 `TODO (owner: user)`（`grep -c` 实测确认）。但同一份文件的 `## Result` 段写的是 `Pass/fail: pass（残余风险：subagent 模型无运行时探针验证）`。

与此并行，`check_setup.py --project . --json` 对本项目实跑输出 `complete: true`、`filled: 5/5`，同时 `field_todo_count: 12`——脚本自身模块 docstring（`check_setup.py:42-46`）已明确设计意图：`field_todo_count` 是"叶字段值为字面 TODO 的计数"，且"Neither counter participates in `gate_blocking` or `complete`"——即按脚本自己的既有设计，TODO 计数本就不参与 pass/fail 判定，不是一个未声明的语义缺口，而可能是 `TODO (owner: user)` 这个写法本身就是"owner 归属占位符"（即"这件事该由谁做，尚待用户回答"，而非"这项检查未完成"）的合法设计意图。

两种解读目前都说得通，协议文本没有明确取舍：
- (a) `TODO (owner: user)` 是合规的、设计上就不阻塞判定的占位符，`Pass/fail: pass` 与 `field_todo_count: 12` 井水不犯河水，无需改动；
- (b) `TODO (owner: user)` 只是项目自己在填写时偷懒留下的未完成项，`Pass/fail: pass` 掩盖了这一点，应该改为 partial/pending 之类的措辞。

## Minimal Reproduction From Files

1. Read: `.harnessloop/state/environment.md`（全文件 5 处 `TODO (owner: user)`）
2. Observe: `grep -c "TODO (owner: user)" .harnessloop/state/environment.md` → 5；`python3 harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py --project . --json` → `complete: true`、`filled: 5/5`、`field_todo_count: 12`
3. Expected next protocol action: 协议文档应明确 TODO 占位符与 pass/fail 判定之间的关系，使这种共存不需要每次靠读者自行判断是否矛盾
4. Actual next protocol action: 两个信号（字面 TODO 存在 + Pass/fail: pass）并存，协议文本未对此关系做出裁定

## Attempted Local Mitigation

- Evidence refresh: 已实测 `grep -c` 与 `check_setup.py --json` 输出，确认两个数字（5 处 TODO、`field_todo_count: 12`）均可复现
- Scope narrowing: n/a
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: **需要**——本条的最终分类与处置依赖用户/主会话对(a)/(b)两种解读的裁定，裁定前不应改脚本（遵循计划原文纪律）

## Suggested Upstream Improvement

- Candidate target: 待裁定后确定 —— docs（`check_setup.py` 模块 docstring 或 `state/environment.md` 模板注释）或 template（`environment.md` 模板/填写规范）
- Proposed smallest change: 计划裁定为 **[P2] 待定**——需先裁定这是项目侧数据错误还是脚本语义缺口，裁定前不要改脚本。
  - 若裁定为 (a)：只需要在 `check_setup.py` 模块 docstring 或 `state/environment.md` 模板注释里补一句显式说明"`TODO (owner: user)` 是设计上的 owner 占位符，不代表未完成"，消解"看起来矛盾"的观感。
  - 若裁定为 (b)：需要 `environment.md` 模板或填写规范上收紧，要求 `Pass/fail` 判定前先清空所有 owner 占位符，或改为可以表达"pass-with-open-owner-items"的措辞——与 TH-0012 的 Verdict/Residuals 思路同构，值得留意是否可合并处理。
- Why this generalizes beyond this project: 任何用"字面 TODO 占位符 + 独立 Pass/fail 字段"这种模式记录环境自检状态的协议，都会遇到"占位符是否算未完成"这一未声明的语义问题。
- Risks of overfitting: 待裁定后评估；本条记录阶段不做取舍。

## Resolution

- Resolution status: open（待定——需先裁定语义再决定是否改脚本，本轮不改）
- Upstream change: 待裁定
- Backported to local policy: no
- Backport path: 无
- Follow-up required: 是——待用户/主会话对 (a)/(b) 两种解读做出裁定后，再决定候选目标（docs 说明 vs 模板收紧）与是否与 TH-0012 合并处理。

---

## 2026-07-28 更新：范围扩大 + 裁定依据出现（main-session ruling under user delegation）

本条原记为"两种解读都说得通、协议未裁定"。runtime-evals 审核第 2 轮独立参照审
（`.hopper/handoffs/T-075-output.md` M-1）给出了**裁定所需的下游后果**，使 (a)/(b)
不再对称：

**新证据（已由主会话独立复核）**：
- `control-contract-profiles.md:17,41-42,57`：standard 档 auto-continue **只看**
  environment self-check = `pass`；strict 档还要求实际 delegation 验证。
- `harnessloop-continue/SKILL.md:24,28`：continue **只在 `complete=false` 时**承诺
  surface TODO warning。本项目实跑 `complete: true` + `field_todo_count: 12` ——
  该组合**静默穿过** setup 分支，TODO 从不出现在任何门前。
- `harnessloop-delegation/SKILL.md:29-35,65-71`：observed model/effort 不可验证时
  必须写 `unknown`、不得标成功；而本项目 `state/environment.md:45` 写的是
  `Pass/fail: pass（残余风险：subagent 模型无运行时探针验证）`——自由文本"pass 带
  残余"绕过了该纪律。

**因此后果不再是文档洁癖**：委派执行的 runtime eval 会在「能力、scope、输出路径、
实际模型均未验证」的情况下拿到"环境 pass"，进而被 auto-continue 放行。这是硬门
语境下的假绿通道。

**裁定**：采解读 (b) 的实质，但落点不在措辞而在**机器可读字段**——
- `state/environment.md` 增机器可读 `delegation_health`（含 probe artifact/digest、
  `verified_at`、会话/环境 fingerprint、适用风险级）；
- 无新鲜 probe 时，只允许 main-session 执行或 read-only 保守模式，**不得**用自由文本
  `pass（有残余）`满足硬门；
- setup/continue 对「complete=true 且 field_todo_count>0」必须显式暴露，不再静默。

**归属**：TH-0021（eval 硬门）的**条件前置**——仅当项目选用委派/可写 runner 时成为
阻塞项（见审核报告附录 C.1 争议 C 裁定：协议保持 executor-neutral）。
**原「EV-K 另立新 issue」的计划撤销**：本条已覆盖，重复立项无必要。
