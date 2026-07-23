# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0001（实现阶段首轮 · 补记 + 状态归位轮，非新业务执行）
- Scope-lock: rounds/0001/scope-lock.md（v1）
- Started: 2026-07-23
- Completed: 2026-07-23

## What Changed

实现阶段（RA-L5 / IMPL）自 goal 002 进实现阶段（commit `cfa3106`）后，SG-1 / SG-2 / SG-6 三个子目标与 T-041 / T-042 两次第三方对抗审均已实交付落地，但**从未经由 harnessloop round → decision → feedback → state 回写通道闭环**——实现走 hopper 对抗审即验收，导致四份 state 文件集体滞后于实交付事实（详见 self-audit.md goal 002 条目与 evolution-issue TH-0010）。本轮为**补记 + 状态归位轮**：把下列已交付工作**追认**为实现阶段首轮已交付、补建实现阶段首轮闭环，不重跑任何业务、不新增业务产出。

**本轮追认为已交付的工作项**（真值取自 remediation-spec §A 地基事实，均为既有 commit，不臆测）：

- **SG-1**（`contracts/d2` 机器可读 schema + 三端 codegen + 判别联合存活 + fixture runner 骨架）：commit `0b4b79c`（起步 `08508d4`）。产物 `app/contracts/d2/`、`app/generated/{ts,swift,csharp}/`、`app/contracts/d2/CODEGEN-FINDINGS.md`、`app/contracts/d2/codegen/verify/{swift,csharp}`。验收级别＝**静态级**（D2 v3 判别联合递归闭包转录 JSON Schema 2020-12 + schema 自检 + tsc/quicktype 三端编译过）。范围边界：只到「骨架 + TS runner」，Swift/C# parity runner 与三组 fixture 完整补齐结转 SG-8.7。
- **SG-2**（D3 OpenAPI 契约草案 + NestJS 8 模块骨架，可编译）：commit `da95155`。产物 `app/server/src/`（TypeORM 实体 + JWT/Ed25519 license + newapi D3 代理桩）。验收级别＝**静态级**（编译通过）。业务逻辑完整性 + D3-proxy 计费路由 e2e 结转 SG-8.1 / SG-8.5。
- **SG-6**（方案B：openclaw 主路径零改 + 辅助小 patch + D3-proxy session-affinity 路由）：impl `5fcf9de` → grok 对抗审 T-042 判 REWORK（`362b04e`）→ 收口 `c69041e` → openclaw submodule 指针 `5b133b7`（fork 补丁 submodule commit `824adcf`）→ 状态 `399c793`。验收级别＝**code 落地 + grok 对抗审级**（build / jest 18-19 / eslint 全过，静态级 + 对抗审 REWORK 逐条复现坐实→收口）。**e2e wire 未证**（真 `x-session-affinity` header 透传 / 真 newapi SSE / mint 写映射表 `revokedAt IS NULL` 行均 defer build+run，收编入 SG-8.1）。
- **T-041**（codex D4 v2.3 定稿复核）：D4 codegen 边界据 SG-1 代码修正，commit `c82d6bd` / `9795755` / `59cf86d` + wiki `eb3ca73`；经 codex 复核 MUST-FIX → 收口 confirmed。
- **T-042**（grok SG-6 D3-proxy 对抗审）：REWORK（P0 生产 URL 改写 + P1 路径穿越/开放代理 + P1 内部路由头外泄 + P2 abort hygiene/测试缺口）→ 主会话独立复现坐实 → 收口 `c69041e`。
- **PRE-①**（内核源码一致性只读核验，非 live-probe）：`~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md` + `pre1-hermes-source-conformance.md`（裁定 C-3 path① 对两内核成立；hermes 原生零改 / openclaw 中等量级 patch）。

## Evidence Produced

> 本轮为补记轮，不新增业务产出——下列证据均为**既有实交付物**（commit / 对抗审报告 / 源码核验页），本轮只做追认与归位。各条的**正式索引登记（evidence-index.md E6+）由本批 state 回写同步**（round+meta cluster 不写 evidence-index.md，避免越界）。物理产物落 `app/` 与 hopper handoffs / design-wiki，不在 `rounds/0001/` 内复制。

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| SG-1 产物 | app/contracts/d2/、app/generated/{ts,swift,csharp}/、app/contracts/d2/CODEGEN-FINDINGS.md、app/contracts/d2/codegen/verify/{swift,csharp}（commit `0b4b79c`，起步 `08508d4`） | static + runtime | D2 v3 判别联合→JSON Schema 2020-12 + 三端 codegen + tsc/quicktype 编译过；拟登记 evidence-index E6+ |
| SG-2 产物 | app/server/src/（commit `da95155`） | runtime | NestJS 8 模块骨架编译通过；拟登记 E6+ |
| SG-6 产物 | app/server（D3-proxy `5fcf9de`→`c69041e`）+ kernels/openclaw submodule `824adcf`（指针 `5b133b7`） | runtime | build/jest 18-19/eslint 全过（静态级）；e2e wire defer SG-8.1；拟登记 E6+ |
| T-041 复核 | codex D4 v2.3 复核（MUST-FIX→收口 confirmed，`c82d6bd`/`9795755`/`59cf86d` + wiki `eb3ca73`） | source | 对抗审证据；拟登记 E6+ |
| T-042 复核 | grok SG-6 D3-proxy 对抗审（REWORK→收口 `c69041e`，hopper handoff） | dynamic | 对抗审证据；拟登记 E6+ |
| PRE-① 源码核验 | ~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md、pre1-hermes-source-conformance.md | source | 只读源码一致性核验；拟登记 E6+ |

## Handoffs Closed

- 实现阶段的两次第三方对抗审 hopper handoff（T-041 codex D4 复核、T-042 grok SG-6 D3-proxy 对抗审）在其原派发时已闭合（收口 commit 各自落地），本轮追认其闭合状态，不重开。
- goal-breakdown.md「Discovery Handoffs」表为空——实现阶段派发走 hopper 通道而非 harnessloop discovery handoff，无 harnessloop 侧 open handoff 需闭合。

## Review Result

**positive（追认）**——本轮不新增评审，只把各交付物在其**原验收级别**已通过的事实归位：

- SG-1 / SG-2：静态编译级（schema 自检 + 三端 codegen tsc/quicktype 编译过 / NestJS 编译过）。
- SG-6：code 落地 + grok 对抗审级（T-042 REWORK 逐条主会话独立复现坐实 → `c69041e` 收口，build/jest 18-19/eslint 全过）。**e2e wire 明确未证**，defer 至 SG-8.1，故 SG-6 的 done 严格限定为 code+对抗审级，非端到端。
- T-041：codex D4 复核 MUST-FIX → 收口 confirmed。

证据充分且收敛（每个交付物都有 commit + 对应验收级别的通过记录），无 negative / 未决评审悬置，故本轮 feedback 分类 positive。

## Cost

Paste the output of `<skill-dir>/scripts/round_cost.py` here (claude-code
environments only; other environments record cost as `unavailable: no local
transcript source`). Do not read transcript files into the session; only the
script's summary enters context.

- Transcript window: unavailable — 补记轮无独立执行 transcript 窗口
- Input tokens: unavailable
- Cache write tokens: unavailable
- Cache read tokens: unavailable
- Output tokens: unavailable
- Protocol-attributed (heuristic): unavailable
- Estimated cost: unavailable（本轮为「补记 + 状态归位」轮，SG-1/2/6 与 T-041/T-042 的实交付成本已在各自原执行会话消耗，未在本轮单独记账；补记动作本身的成本并入本批 remediation 批次，不单列）

## Decision

见 rounds/0001/decision.md：feedback = **positive**（追认，有证据、收敛）；SG-6 的 done 范围边界明确限定为 **code 落地 + 对抗审级**（e2e wire defer SG-8.1）；下一步待选 **SG-3 / SG-4 / SG-5 / SG-7 / SG-8**。本轮为状态归位补记，非新业务执行，无故障定位需求。

## Blocker Classification

- Blocker type: none（本轮为补记闭环，无阻断）
- Recovery eligible: 不适用（无 blocker）
- Safe next action: 本批收盘后待选 SG-3（注意与 SG-1 已交付 codegen 的 scope 边界）/ SG-4（Mac 最小壳打通运行内核，是 SG-8 各探针/e2e 的依赖底座）/ SG-5 / SG-7 / SG-8
- User input required: 否（补记基于既有 commit + 对抗审证据，不需用户确认）——但后续 SG-8 各 e2e/探针项仍依赖用户安排真实 newapi 环境（PRE-4）及 SG-4/SG-7 运行内核落地（PRE-1/3/7），属独立的下一步待办，不阻塞本补记轮收盘

## Open Risks

- **SG-6 done 是 code+对抗审级、非 e2e**：真 header 透传 / 真 newapi SSE / mint 写映射表三项 e2e wire 仍未证，收编 SG-8.1，SG-4 运行内核就绪后方可闭合；在 SG-8.1 通过前不得把 SG-6 表述为「端到端已过」。
- **实现阶段绕开 round 闭环的结构缺口**：本轮补记只归位到 SG-1/2/6，若后续 SG 继续绕开 round→state 回写通道，state 会再次滞后——已记 evolution-issue TH-0010（框架级观察：是否需「距上次 round 收盘 N 个交付物」的 dead-reckoning 守卫），后续 SG 须逐个走 round 闭环。
- **PRE-1/3/4/7 环境依赖未解**：runtime 探针与计费链 e2e 依赖真实 openclaw/hermes/newapi 运行内核，PRE-4 待用户安排 newapi，PRE-1/3/7 待 SG-4/SG-7 运行内核落地。
- **hopper 边用边验证观察点**：grok（T-042）本次尾部 `auth-fail`（XAI_API_KEY 失效），审查已完整产出（真跑），但后续 grok 派发需重新登录（已恢复）。

## Next Proposed Scope

实现阶段后续从 SG-3 / SG-4 / SG-5 / SG-7 / SG-8 中择一开新 round，且**每个 SG 逐个走 round → decision → feedback → state 回写闭环**（不再绕开），验证本轮补救闭环能否防止 state 再次滞后。优先建议 **SG-4**（Mac 最小壳打通真实运行内核）——它是 SG-8 全部 runtime 探针 / e2e wire（含 SG-6 defer 的 SG-8.1、SG-8.2 hermes、SG-8.3 PRE-1/3/7 探针、SG-8.4 conformance、SG-8.5 计费链）的依赖底座；SG-3（codegen 增量：CI 冒烟挂接 + EmptyPayload/WireCapabilityDescriptorPayload type-level 断言，注意与 SG-1 已交付部分不重复）可并行推进。
