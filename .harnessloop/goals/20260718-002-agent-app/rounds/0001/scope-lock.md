# Scope Lock

## Round Objective

**补记 + 状态归位**——把实现阶段（RA-L5 / IMPL）自 goal 002 进实现阶段（`cfa3106`）后已实交付、但从未经 harnessloop round 闭环的工作项（SG-1 `0b4b79c` / SG-2 `da95155` / SG-6 `5fcf9de→c69041e` + openclaw `824adcf` / T-041 codex D4 复核 / T-042 grok SG-6 对抗审），**追认为实现阶段首轮（rounds/0001）已交付**，并把四份滞后的 state 文件回写归位到实交付事实。**本轮不重跑任何业务、不新增业务产出**，仅做状态归位、契约状态修正与实现阶段首轮闭环补建。

## Allowed Changes

| Path/data/tool | Allowed action | Limit |
| --- | --- | --- |
| .harnessloop/goals/20260718-002-agent-app/rounds/0001/（round-summary.md / scope-lock.md / decision.md） | 写 | 本轮 round 目录三文件（round+meta cluster） |
| .harnessloop/meta/self-audit.md | 追加 | 仅新增 goal 002 条目（round+meta cluster） |
| .harnessloop/meta/evolution-issues/0010-*.md | 新建 | 仅本 issue 文件（round+meta cluster） |
| .harnessloop/goals/20260718-002-agent-app/goal-breakdown.md / goal.md / thresholds.md / data-contract.md / feedback-policy.md | 写 | 契约状态归位 + SG-8 定义（goal-contract cluster，非本 cluster） |
| .harnessloop/state/current.md / evidence-index.md / self-check.md | 写 | state 回写归位（state cluster，非本 cluster） |

> 说明：Allowed Changes 表列出本轮（＝本次 remediation 批次）touch 的全部路径以保留审计完整性；round+meta cluster **只负责 rounds/0001/ 三文件 + self-audit.md + evolution-issues/0010**，其余由 goal-contract / state cluster 执行，各 cluster 不越界改他人文件。

## Disallowed Changes

- 任何 `app/` 业务源码、`kernels/openclaw` / `kernels/hermes` submodule、三插件 submodule——本轮为状态归位，不动业务/内核/插件代码。
- 追认之外的**新业务执行**（不得借补记轮之名开始 SG-3/4/5/7/8 的任何编码或运行）。
- 篡改既有 commit / HEAD 事实——追认只引用 remediation-spec §A 已核实真值，不臆造 commit。
- rounds/0001/ 内复制粘贴 `app/` 大产物或 hopper transcript 原文（只引用路径与摘要）。

## One-Variable Strict Mode

- Enabled: no
- Variable: 不适用（补记 + 状态归位轮，非单变量隔离验证轮）
- Reason: 本轮不做实验性验证，只把既有实交付事实归位进 harnessloop state。

## Verification Commands Or Checks

| Check | Command or method | Expected result | Evidence path |
| --- | --- | --- | --- |
| 追认真值一致性 | 本轮引用的 commit（`0b4b79c`/`da95155`/`5fcf9de`/`c69041e`/`824adcf`/`c82d6bd` 等）与 remediation-spec §A 地基事实逐条比对 | 全部一致，无臆造 | remediation-spec.md §A |
| SG-1/2 静态级已过（追认，非本轮重跑） | 各交付物原验收级别：SG-1 schema 自检 + 三端 codegen tsc/quicktype 编译 / SG-2 NestJS 编译 | 原执行会话已过（本轮不重跑） | app/contracts/d2、app/generated、app/server/src |
| SG-6 code+对抗审级已过（追认） | grok T-042 REWORK 逐条复现→`c69041e` 收口；build/jest 18-19/eslint | 原执行会话已过；e2e wire 明确 defer SG-8.1 | app/server；hopper T-042 handoff |

## Runtime Recovery Limits

- Recovery round: no
- Blocker type: 不适用（无 blocker）
- Allowed observation targets: 不适用
- Disallowed triggers or writes: 不适用
- Cleanup/write confirmation required before: 不适用

## Rollback Condition

若追认过程中发现某交付物的 commit / 验收级别与 remediation-spec §A 真值不符（例如 SG-6 实为 e2e 已过而非仅 code+对抗审级，或反之），则不得追认该项为 done，须退回由主会话据实修正真值后重记本轮，不得据错误真值归位。

## Human Confirmation Required

无（本轮为补记 + 状态归位，追认基于既有 commit + 对抗审证据，不涉及不可逆写入或外部系统变更；全量补救方案已由用户批准，见 remediation-spec 抬头）。后续 SG-8 各 e2e/探针项对真实环境（newapi / 运行内核）的依赖属独立下一步待办，不在本轮 scope 内、不阻塞本轮收盘。
