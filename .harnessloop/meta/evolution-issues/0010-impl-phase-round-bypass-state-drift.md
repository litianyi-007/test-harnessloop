# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0010
- Issue class: skill-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-fable-5（main session）+ round+meta cluster 子代理，于 goal 002 实现阶段状态归位批次
- Created at: 2026-07-23

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: 仅引用 commit 短号与 state 文件段落摘要，未粘贴任何 hopper/对抗审 transcript 原文
- Safe evidence summaries only: yes

## Context

- Active goal path: .harnessloop/goals/20260718-002-agent-app/
- Active round path: .harnessloop/goals/20260718-002-agent-app/rounds/0001/（本批补建的实现阶段首轮 · 补记 + 状态归位）
- State files: state/current.md、state/evidence-index.md、state/self-check.md、goals/20260718-002-agent-app/goal-breakdown.md、thresholds.md、feedback-policy.md、data-contract.md（本批回写前均滞后于实交付）
- Related handoffs: hopper T-041（codex D4 v2.3 复核 MUST-FIX→confirmed）、T-042（grok SG-6 D3-proxy 对抗审 REWORK→收口）
- Related evidence: SG-1 `0b4b79c`（起步 `08508d4`）/ SG-2 `da95155` / SG-6 `5fcf9de`→`c69041e`（openclaw fork submodule `824adcf`、指针 `5b133b7`、状态 `399c793`）/ goal 002 进实现阶段 `cfa3106`
- Related reviews: grok T-042（SG-6 D3-proxy 对抗审）、codex T-041（D4 v2.3 复核）

## Expected Harnessloop Behavior

harnessloop 在实现阶段应保证：每个已交付子目标（SG）经由 round → decision → feedback → state 回写通道闭环，使四份 state 文件（current / evidence-index / self-check + goal contract）持续与实交付事实同步；且 self-audit 的 Deterministic Signals 或 harnessloop-continue gate 应能在「距上次 round 收盘已累积 N 个交付物 / 实交付与 state 声明分叉」时给出**可观测机械信号**，阻止 state 静默滞后。

## Actual Harnessloop Behavior

goal 002 自进入实现阶段（`cfa3106`）后，SG-1（`0b4b79c`）/ SG-2（`da95155`）/ SG-6（`5fcf9de`→`c69041e`，openclaw `824adcf`）三个子目标以及 T-041 / T-042 两次第三方对抗审，均在**无 harnessloop round** 的情况下完成——实现走 hopper 对抗审即验收，未经 round → decision → state 回写通道。后果是四份 state 文件集体滞后：

- `goal-breakdown.md` SG-1 / SG-2 仍标 `pending`，与实交付 `done` 自相矛盾；
- `state/current.md` 整份冻在 PRE-①（07-23 之前），`Active round: 无`、`Next proposed action` 仍指 PRE-5/PRE-6；
- `state/evidence-index.md` 仅 E1-E5（均属已归档 setup-wizard goal），goal 002 从设计到实现**零 evidence 入索引**；
- `state/self-check.md` 冻在 setup-wizard（Last checked 07-16）。

关键点：整个滞后过程中，harnessloop **没有任何机械信号**提示「实现阶段已绕开 round 闭环 / state 已分叉」——直到外部五路审计发现该结构缺口，才触发本批补救。这是本项目（以真实 app 验证 harnessloop 的实验）暴露的框架级观察点。观察到的症状表现为 evidence-drift + goal-breakdown 自相矛盾，但其**根因**是框架缺少一个检出「长实现阶段绕开 round」的守卫（skill-gap）。

## Minimal Reproduction From Files

1. Read: `goals/20260718-002-agent-app/goal-breakdown.md` SG-1 / SG-2 行（补记前标 `pending`）、`state/current.md` line 3-4（`Active round: 无`、`Next proposed action` 指 PRE-5/6）、`state/evidence-index.md`（仅 E1-E5，全属 setup-wizard goal）
2. Observe: 实交付 commit `0b4b79c` / `da95155` / `c69041e` 与 openclaw submodule `824adcf` 均已落地，但**无对应 `rounds/`、无 evidence 入索引、goal-breakdown 状态与实交付矛盾**
3. Expected next protocol action: self-audit / continue gate 检出「实现交付物累积但无 round 收盘」→ 给出信号提示回归 round 闭环 / 阻断继续
4. Actual next protocol action: **无信号**，实现持续推进、state 持续滞后，直到外部审计（五路）发现结构缺口才触发本批补救

## Attempted Local Mitigation

- Evidence refresh: 本批 state 回写补 evidence-index E6+（SG-1/2/6 + T-041/T-042 + PRE-① 两页），并刷新 E3 submodule HEAD
- Scope narrowing: 补建 rounds/0001 作为「补记 + 状态归位」轮，仅追认已交付工作，不重跑任何业务
- Contract revision: goal-breakdown SG-1/2 `pending`→`done`（限定静态级）、SG-6 done 限定为 code+对抗审级（e2e defer SG-8.1）、新增 SG-8 收编此前悬空的 build+run 验收；thresholds / feedback-policy / data-contract 同步回填（由本批 goal-contract / state cluster）
- Handoff change: 无
- Rollback: 无
- Human confirmation: 用户已批准全量补救（①状态回写 ②定义 SG-8 验收 ③开实现阶段 round + self-audit ④记本 evolution-issue）

## Suggested Upstream Improvement

- Candidate target: main skill（`harnessloop-loop` 的 self-audit Deterministic Signals 表 + `harnessloop-continue` gate）
- Proposed smallest change: 在 self-audit Deterministic Signals 表增一行「距上次 round 收盘的交付物/commit 计数（dead-reckoning）」，阈值形如「实现阶段累积 N 个交付物未收盘 round → warn / 阻断」；或在 continue gate 增一个「实现活动与 active round 存在性一致性」检查——当 goal 处于实现阶段、且自上次 round 收盘后有新 commit / 子目标状态变更但无新 round 时，给出机械信号。**须与 CLAUDE.md「拉取式设计原则」相容**：该守卫是 self-audit 侧的**只读检测信号**，不得反向要求在 round-summary / decision 模板里插入新记录钩子。
- Why this generalizes beyond this project: 任何长实现阶段、主会话高频借外部对抗审（hopper / codex / grok）即验收的 harnessloop 项目，都可能在「每次对抗审都像已闭环」的错觉下绕开 round → state 回写通道，使 state 静默滞后。这不是本项目特有，而是「实现阶段用外部评审替代内部 round」这一工作模式的通用陷阱。
- Risks of overfitting: 中——「交付物计数」的粒度（commit vs 子目标状态变更 vs 文件）与阈值 N 需项目可配，否则对纯设计/调研阶段（本就少 round）或单 round 内多 commit 的正常节奏会误报；建议阈值项目可配、且**仅在 goal 标记为实现阶段（RA-L5 / IMPL）时启用**。

## Resolution

- Resolution status: open（本批已用补救闭环缓解症状——rounds/0001 补记 + state 回写归位；框架侧 dead-reckoning 守卫是否落地待评估）
- Upstream change: 待评估（本批未改 harnessloop 源码——遵循 harnessloop 协议文本零改动约束，仅记录框架级观察）
- Backported to local policy: no（本批为一次性补救，刻意不新增本地记录钩子，遵循 CLAUDE.md「拉取式设计原则」与「协议文本不因存在而改一字」约束）
- Backport path: 无
- Follow-up required: 是——(1) 评估 dead-reckoning 信号是否值得进 self-audit / continue gate 及其误报风险与项目可配阈值设计；(2) 本 goal 后续 SG-3/4/5/7/8 须**逐个走 round → decision → feedback → state 回写闭环**，以验证本批补救闭环能否防止 state 再次滞后（本 issue 的实测收敛判据）
