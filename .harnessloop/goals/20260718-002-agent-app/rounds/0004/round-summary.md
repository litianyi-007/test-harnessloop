# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0004（实现阶段第四轮 · SG-8.5 计费链 e2e，goal 002 首个真正跑通「内核 → D3-proxy → newapi → 上游 LLM」完整链路的执行轮，续 rounds/0002/0003 做法，完整 round → decision → state 回写闭环）
- Scope-lock: rounds/0004/scope-lock.md（v1）
- Started: 2026-07-23
- Completed: 2026-07-23

## What Changed

本轮交付 **SG-8.5（计费链 e2e）完整闭合**：把完整链路 `真 openclaw agent（动态注入真实 sessionId）→ D3-proxy（读 x-session-affinity/按 session 查映射/换凭证）→ 自托管 new-api（树莓派 Pi:3000）→ Kimi 上游` 端到端跑通，证明 per-session 计费归因（C-3 path①）在真实运行系统上成立——这是 goal 002 实现阶段第一次把此前分别验通的各段（SG-4 kernel-client L1 连通、SG-6 D3-proxy 代码、SG-9 newapi 部署）真正串成一条完整链路的运行时闭环。

**分阶段执行（依 scope-lock 分层）**：

- **阶段1（D3 起）**：D3-proxy（`app/server`）本机起，连通 Pi Postgres（synchronize 建表）+ Pi new-api，验通。
- **阶段2（D3→newapi→Kimi 腿）**：seed session→token 映射后直接 curl D3 `/session-proxy` 带 `x-session-affinity`，验证 D3 读 header/查映射/换 Authorization/流式转发对真实 newapi 成立。
- **阶段3（openclaw 腿 → 完整链）**：真实（隔离）openclaw 内核动态注入真实 sessionId → D3-proxy → newapi → Kimi → 经内核事件流回 kernel-client，完整链闭合。

**铁证**：两个不同 session 的真实 sessionId 动态到达 D3-proxy——`016c7dc2-745a-4067-b180-f0a2c8675927`（session A）/`955f0c1f-aadb-4350-93d2-1b0ce2a78caa`（session B），**补丁前 D3 侧观测为 `(missing)`**——证明动态注入 + per-session 精确区分（非静态写死、非聚合归因）。session_A seed 映射后 `send` → Kimi 回复 "PERSESSION-DONE"；new-api 计费落账（`/api/log/` id 19，token `sg8.5-kimi-e2e/id3`，model `kimi-for-coding`，channel `kimi-coding`，prompt 9400/completion 32，与 run usage 精确吻合）。全程未碰用户全局 gateway（本机 18789）；D3（本机 3001）/Pi Postgres/Pi new-api 全程正常运行。

**关键发现与本轮 scope 演化（如实记录，非违规）**：rounds/0004/scope-lock.md 原写 Disallowed Changes 明确"不改 kernels/openclaw 源码"（本轮定位是"接起来跑，不是改组件"）。执行阶段3 时发现，达成真实动态 per-session path① 被 **openclaw 两个真实源码 bug 挡住**：

1. `ModelCompatSchema`（`kernels/openclaw` `src/config/zod-schema.core.ts`）的 zod 校验相对 TS 类型声明遗漏了 6 个已声明的 compat 字段（`sendSessionAffinityHeaders`/`cacheControlFormat`[="anthropic" 字面量]/`openRouterRouting`/`vercelGatewayRouting`/`zaiToolStream`/`supportsLongCacheRetention`），导致部署配置写 `sendSessionAffinityHeaders` 被 `.strict()` 校验直接拒收——这是纯粹的 TS 类型与 zod schema 漂移，不是设计问题。
2. 主对话轮次实际发起模型调用走的是 **transport 热路径**（`openai-completions-transport.ts` + `openai-transport-params.ts::buildOpenAIClientHeaders`），此前根本不透传 `sessionId`、更不会注入 session-affinity header——SG-6 spike 走读坐实的 §2.3 那条"`sendSessionAffinityHeaders` 打开即自动注入三个 header"的注入逻辑，只在 provider-adapter 版本上生效，带静态 apiKey 的自定义 provider（本设计的 D3-proxy 正是这种）走的是 transport 版本，**该版本此前从未被 SG-6 spike 测过**。

这两个 bug 若不修复，path① 在真实运行系统上不成立（只能退回聚合计费或静态 header 方案）。**用户 2 次现场授权**扩展 rounds/0004 scope-lock（分别针对 schema 补丁、transport 补丁），主会话据 control-contract.md 「Irreversible or external-system write」/「contract-insufficient」条款处置——scope-lock 遇到必须修改 Disallowed Changes 里明确禁止的项（改 `kernels/openclaw` 源码）时，正确路径是停下、把裁决交回用户而非擅自扩围，本轮正是这样处置：两次都先停下说明"必须改内核才能通"，用户当场确认后才落地补丁。这属于 **user-confirmed 的 contract-insufficient blocker 处置，非 scope drift/协议违规**。落地的两个极小补丁：

- `4ddcb52`（schema）：`ModelCompatSchema` 补齐前述 6 个字段，解锁部署配置合法通过校验。
- `35f8739`（transport）：transport 热路径补 `sessionId` 透传 + 按 `sendSessionAffinityHeaders` 注入 `session_id`/`x-client-request-id`/`x-session-affinity` 三个 header。

接既有 SG-6 辅助路径补丁 `824adcf`，openclaw submodule HEAD 现为 `35f8739`（补丁链：`35f8739`→`4ddcb52`→`824adcf`→`bb3f6c5`）。**主仓库 submodule 指针尚未更新**（`git status` 显示 `kernels/openclaw` working tree 已指向新 HEAD 但主仓库尚未 commit 该指针变更），留待后续批次处理，本轮不 commit。

**修订后的诚实结论（同步修订 SG-6 设计结论）**：openclaw 达成 per-session path① 需要 **3 处极小补丁**（schema + transport + 辅助路径），而非 SG-6 spike 原判定的"零源码改动"——但仍远小于 PRE-① §2.4 方案A（原生凭证 patch：5 文件、要在 openclaw 里铸造/持有 per-session newapi 凭证，直撞 `AGENTS.md` secrets 红线），方案A 被否决的结论不变、仍成立。**根因**：SG-6 spike 只验证了 TS 类型层声明了 `sendSessionAffinityHeaders`，**没有实际跑一遍 spike 自己 §6 验证计划表列出的"config 校验走一遍"这一验证项**，也没有测试真实运行的 transport 路径（与 provider-adapter 路径是两条不同代码路径，spike 只走读了后者）。这是"下游实现连环证伪上游设计"的**第 5 例**，且本例连环两层：静态 header 方案（provider-adapter 版本的注入逻辑）一度掩盖了真正承载主对话轮次的动态注入机制（transport 版本）其实是死代码——即"表面上机制存在"掩盖了"这条机制走不到实际调用路径"。

**副发现（记录，非本轮修，不在本轮 scope 内处理）**：
- 隔离运行还需要额外设置 `OPENCLAW_WORKSPACE_DIR`，`app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 待补这一条（recipe 更新不在本轮 scope，属 app/ 文档，本轮纪律不改 app/）。
- 真实 agent 请求体 ~107KB，超过 `app/server` 100KB 的 body-parser 限制；本轮用 `localModelLean`（缩减请求体的变通配置）绕过，未改 `app/server` 源码；建议后续独立任务调大该限制。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E14 | app/deploy/newapi（Pi new-api 运行）+ app/server（D3-proxy 本机运行）+ kernels/openclaw submodule 补丁 `4ddcb52`/`35f8739`（接既有 `824adcf`）+ scratchpad/openclaw-iso3/（隔离内核 + seed 探针脚本，throwaway） | runtime | 两个不同真实 session 的 sessionId 动态到达 D3（补丁前 `(missing)`）+ Kimi 真实回复 "PERSESSION-DONE" + new-api `/api/log/` id 19 计费落账（token/model/channel/prompt-completion token 数与 run usage 精确吻合）；已登记 `state/evidence-index.md` E14 |

## Handoffs Closed

- 无 hopper 派发——本轮为运行时集成 e2e（起 D3-proxy、seed 映射、跑真实链路）+ 2 处 openclaw 内核补丁，属 code-impl 类工作，按既定规则一律由主会话 claude-sonnet-5 子代理执行，不派第三方 vendor（hopper 不参与实现类任务）。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-8.5 计费链 e2e 完整闭合，证据充分且收敛：

- 两个不同 session 的真实 sessionId（`016c7dc2-...`/`955f0c1f-...`）动态到达 D3-proxy，补丁前为 `(missing)`——直接对照证明修复生效、且 per-session 精确区分成立（非静态/非聚合）。
- session_A seed 映射后 `send` 收到 Kimi 真实回复 "PERSESSION-DONE"，经内核事件流回 kernel-client。
- new-api 计费日志（id 19）token/model/channel/prompt-completion token 数与 run usage 精确吻合，证明计费归因链逐跳可观测且隔离。
- 阶段1-2（D3→newapi→Kimi 真实链路通）与阶段3（完整 per-session 链）均达成，scope-lock 定义的"分层验收（诚实分层，任一阶段受阻则明确 defer）"未触发降级，全部阶段达成。
- 本轮 scope 演化（2 处 openclaw 补丁）均经用户现场确认，且如实记录于本文件与 decision.md，未隐瞒/未回改 scope-lock 掩盖偏离。
- SG-6 设计结论已据本轮实证同步修订（零改动→3 处极小补丁），修订未推翻方案A 被否决的结论，且未影响 SG-6 原「code+对抗审级 done」verdict 本身。

**未做的第三方对抗审**：本轮 2 处新增 openclaw 补丁（`4ddcb52`/`35f8739`）未经 codex/grok 第三方对抗审——与 rounds/0002（SG-4）、rounds/0003（SG-9）先例一致，均以主会话独立复验的运行时证据（两 session 动态区分 + 真实回复 + 计费日志精确吻合）作为 positive 判定依据，未强制要求对抗审；已在 Open Risks 中记录为后续可选加固项（非本轮 done 判定的前提）。

无 negative / 未决评审悬置，故本轮 feedback 分类 **positive**。

## Cost

Paste the output of `<skill-dir>/scripts/round_cost.py` here (claude-code
environments only; other environments record cost as `unavailable: no local
transcript source`). Do not read transcript files into the session; only the
script's summary enters context.

- Transcript window: unavailable — 本轮回写子代理无独立执行 transcript 窗口访问权限
- Input tokens: unavailable
- Cache write tokens: unavailable
- Cache read tokens: unavailable
- Output tokens: unavailable
- Protocol-attributed (heuristic): unavailable
- Estimated cost: unavailable（执行子代理的实际部署/调试/补丁开发成本已在其原执行会话消耗，未在本次状态回写中单独记账）

## Decision

见 rounds/0004/decision.md：feedback = **positive**；裁决 = **SG-8.5 done（计费链 e2e 完整闭合，C-3 path① 端到端成立）**；**SG-6 设计结论同步修订**（零源码改动→3 处极小补丁，方案A 被否决结论不变）；本轮 2 次 scope 扩围裁定为 user-confirmed 的 contract-insufficient blocker 处置，非违规；下一步待选 **SG-5**（kernel-client send 完整实现）/ **SG-3**（CI 冒烟）/ 决定 2 个 openclaw bug 是否上游 push 或另开 issue / 主仓库更新 `kernels/openclaw` submodule 指针 / 副发现（body-parser limit、`OPENCLAW_WORKSPACE_DIR` recipe）后续处理。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker——过程中遇到的 2 处 contract-insufficient 情形均已当场经用户授权解除，不构成收盘时的阻断）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待选 **SG-5**（Windows C# kernel-client parity 追赶，注意其"复用 SG-4 fixture 集合"依赖仍待 SG-8.7 parity runner）/ **SG-3**（codegen 增量：CI 冒烟挂接 + type-level 断言）/ 决定 2 个 openclaw bug（`4ddcb52`/`35f8739`）是否上游 push 给 openclaw 官方仓库或另开 evolution-issue 记录 / 主仓库 commit `kernels/openclaw` submodule 指针（35f8739）/ 处理副发现（`app/server` body-parser limit 调大、`OPENCLAW-ISOLATED-RUN-RECIPE.md` 补 `OPENCLAW_WORKSPACE_DIR`）
- User input required: 否（SG-8.5 本身已完整交付，闭合不需用户进一步确认）——但"2 个 openclaw bug 是否上游 push/开 issue"这一后续决策，以及是否投入资源给 SG-8.5 新增补丁做第三方对抗审，属于需要用户或后续轮次裁决的独立待办，不阻塞本轮收盘

## Open Risks

- **SG-8.5 新增的 2 处 openclaw 补丁（`4ddcb52`/`35f8739`）未经第三方对抗审**——与既有 SG-6 补丁（`824adcf`，经 grok T-042 对抗审）不同，本轮补丁仅有主会话独立复验（真实 e2e 运行证据），未派 codex/grok 复核；建议后续视风险决定是否补一轮对抗审，非本轮 done 判定前提。
- **openclaw submodule HEAD 已推进（现 `35f8739`）但主仓库指针未更新**——按 CLAUDE.md「主仓库 commit 时注意 submodule 指针」纪律，需待后续批次把主仓库指针 commit 对齐（本轮不 commit，留待主会话统一处理）。
- **2 个 openclaw 真实 bug 是否上游反馈未决**——`4ddcb52`（schema 漂移）与 `35f8739`（transport 热路径缺失 sessionId 透传）均是 openclaw 上游代码的真实缺陷（非本项目 fork 专属逻辑），是否 push 给上游仓库或另开 issue 记录待后续决定，暂只记于本 fork submodule。
- **副发现未处理**：`OPENCLAW_WORKSPACE_DIR` 隔离依赖未写入 recipe；`app/server` 100KB body-parser 限制在真实 agent 请求（~107KB）场景下需绕过（`localModelLean`），建议后续独立任务调大限制——均非本轮 scope，如实记录待办。
- **SG-8 其余子项仍 pending**：SG-8.1（本轮证据实质上已覆盖其 4 项 pass 条件里的绝大部分，但本轮未正式对 SG-8.1 清单逐条勾稽收口，留待后续轮次显式核对再关闭该子项，避免"顺带声称"未经逐条核对的验收项）/SG-8.2（hermes）/SG-8.3（PRE-1/3/7 探针）/SG-8.4（conformance 闭环）/SG-8.6（CI 守门）/SG-8.7（gold parity runner）均未推进，SG-8 整体状态维持 pending。

## Next Proposed Scope

**SG-8.5 已闭合**，goal 002 首个完整计费链 e2e 达成。下一步从以下几项中择一或并行：**SG-5**（Windows C# kernel-client parity 追赶）/ **SG-3**（codegen 增量：CI 冒烟挂接 + type-level 断言）/ **决策类待办**（2 个 openclaw bug 是否上游 push/开 issue；是否为 `4ddcb52`/`35f8739` 补一轮第三方对抗审；主仓库 commit `kernels/openclaw` 指针）/ **副发现处理**（`app/server` body-parser limit、`OPENCLAW-ISOLATED-RUN-RECIPE.md` 补 workspace-dir）。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
