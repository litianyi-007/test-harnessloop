# Data Contract

标准四类证据（`static`/`dynamic`/`runtime`/`source`）+ `human-confirmation` 沿用协议既定定义（见 `harnessloop-evidence` SKILL）。下表列出本 goal 特有的具体证据源实例。

## Valid Evidence Sources

| Source | Type | Access method | Freshness | Validation method | Drift risk | Credential requirement |
| --- | --- | --- | --- | --- | --- | --- |
| `.hopper/queue.md` + 派发产物 | dynamic/source | 本地文件读取 | 随每次 dispatch 刷新 | 与 `hopper:status`/`hopper:result` 输出比对 | 中——RA-L3 调研任务量增加后需评估产物质量一致性 | 无 |
| `.harnessloop/goals/**`（本 goal 及既有 goal） | source | 本地文件读取 | 随每轮/每级刷新 | 与 `verify_protocol.py` 输出比对 | 低（单机协议门保障） | 无 |
| kata wiki（`test-harnessloop` + `surebeli-ip` 双 wiki） | source | 本地文件读取 @ git HEAD | 随 `wiki-ingest`/`wiki-sync` 刷新 | `wiki-lint`/`wiki-graph` 走查 | 中——多机 `wiki-sync` 冲突风险 | 无 |
| COST-LOG（round_cost 记账，具体路径待 dev-readiness 后确定） | dynamic | 本地文件读取 | 每轮刷新 | 与各轮 `round-summary.md` Cost 节比对 | 低 | 无 |
| PR wiki `drafts/`（里程碑连载） | dynamic/human-confirmation | 本地文件读取 + 用户发布确认 | 每次成稿刷新 | 用户确认 + diff 比对 | 低 | 无 |
| human-confirmation（用户决策记录） | human-confirmation | AskUserQuestion 留痕 + `goal.md` 引用 | 决策发生时冻结 | 与 `goal.md` Required Human Decisions 对照 | 低 | 无 |
| newapi（计费/成本证据源，待 PRE-4 冒烟接入） | dynamic | D6 集成方式已定稿（`architecture/d6-newapi-integration.md` v3，path① 默认）；实际证据接入待 **PRE-4 冒烟**确认 `POST /api/token/` 创建响应可否反查 `:id` + 渠道/模型管理 REST 路径核实（blocked-待真实 newapi 部署）；隔离归因验法 = 查 `/api/log/self?token_name=session-<id>`（D1 §11 C-3，落 SG-8.5 计费链 e2e） | 接入后随每次内核 LLM 调用（经 D3-proxy 换 scoped key）刷新 | 与 newapi `token_name=session-<id>` 用量日志比对 | 中——PRE-4 冒烟 pass condition 需先写死（newapi `:id` 反查端点/旁路信号/弃用三选一），接入前仅架构承诺、非实测计费事实 | 待接入后确定（可能需 newapi API key，按 `harnessloop-secrets` 流程登记） |

**hopper handoff→证据桥接约定（已定义，2026-07-23）**：RA-L3 起本 goal 大量以 hopper 派发的第三方 vendor 对抗审/研究产物为证据，桥接三角链条如下——**①派发**：主会话在 `.hopper/queue.md` 写任务行（`Vendor` 列 codex/grok 二选一，实现类 `code-impl` 绝不派第三方）；**②执行落盘**：vendor 产物固定落 `.hopper/handoffs/T-xxx-output.md`（如 D1 评审 T-004/T-006/T-008/T-010..T-013/T-040、D2 评审 T-014..T-020、D4 复核 T-041、SG-6 对抗审 T-042）；**③证据引用**：goal 契约/round/wiki 引用该 handoff 路径 + 对应 commit 作为 `dynamic`/`source` 证据，`hopper:result`/`hopper:status` 可复核。**codex 三项强制核对**（codex 沙箱不可靠降级为只读 + 跨仓 review 被全局 skill 劫持的已知问题，见 CLAUDE.md / `hopper-plugin/ISSUE-codex-review-hijack.md`）：每次 codex 评审完成后核对 (a) 审查对象=brief 指定目标、(b) 产物落 brief 指定路径、(c) 不凭 exit 0 / codex 自述 success 采信——须在引用前核对。此前「待定」摩擦点据此关闭。

**外部项目形态待确认（owner 细化，2026-07-18）**：openclaw / hermas / newapi / codex app sdk / claude code sdk 均为外部项目，其实际形态、接口、能力范围**待 RA-L3 调研确认**，在调研完成前**禁止臆造其能力**（不得凭记忆或训练知识断言这些项目具备某功能/接口，须以 RA-L3 实际调研产物——如项目仓库/文档/hopper research 产物——为准）。owner 明确落到 RA-L3 七项决策议程（见 goal-breakdown.md「RA-L3 议程」）：

| 外部项目 | 调研内容 | Owner（RA-L3 议程项） |
| --- | --- | --- |
| openclaw / hermas | 内核形态、切换机制 | D1（内核抽象接口规格） |
| openclaw / hermas | 本地分发打包方式 | D7（本地内核分发打包） |
| newapi | 网关集成方式、计费/成本/能力开关接口 | D6（newapi 集成方式） |
| newapi | server 侧对接可行性（作为瘦控制面选型的一部分） | D3（Server 技术选型） |
| codex app sdk / claude code sdk | 内核兼容性 | D1（内核抽象接口规格） |

资料**待用户提供或 hopper 调研**。

## Valid Tools And Systems

| Tool/system | Purpose | Read/write scope | Account role | Verification command | Failure handling | Local parameter reference |
| --- | --- | --- | --- | --- | --- | --- |
| hopper dispatch/probe/result | RA-L3 技术选型调研佐证（含 server 完整调研、外部项目形态调研） | 只读（研究/调研任务） | TODO (owner: user) | `hopper:status` / `hopper:result` | TODO (owner: RA-L2/RA-L3) | 无 |
| kata wiki-ingest / wiki-query | 需求分析各级展开文档与调研产物的知识沉淀 | 读写（wiki 页面） | TODO (owner: user) | kata `wiki-lint` / `wiki-query` | TODO (owner: RA-L2/RA-L3) | 无 |
| `verify_protocol.py` | 机械协议门 | 只读 | TODO (owner: user) | `python3 <plugin-cache>/skills/harnessloop-loop/scripts/verify_protocol.py --project 本项目` | 定位失败原因后修复重跑 | 无 |
| app/server（NestJS 后端运行时，D3 定稿 TS+NestJS+PostgreSQL，2026-07-23 登记） | server 侧 license/tenant/seat/feature-flags/usage_ledger + D3-proxy session-affinity 计费路由运行时证据源 | 读写（`app/server/`，含 D3-proxy 映射表/凭证换发） | 实现阶段主会话 sonnet 子代理（`code-impl` 不派第三方） | 静态：`npm run build` / `npm run test`（jest 18-19）/ `npm run lint`（eslint）；运行时（build+run）：`npm run start` 起进程探 `/health` + D3-proxy 转发探针（收编入 SG-8.1/SG-8.5） | 静态失败定位后修复重跑；运行时失败落 SG-8 批次 evidence 逐项排查 | 无（D3-proxy 换发的 newapi scoped key 走 `harnessloop-secrets`，接入待 PRE-4） |
| agent app client（Mac/Windows 原生）/ console 管理端运行时 | 三端 client/console 系统本体（app client 首批 SG-4/SG-5，console 第二批） | 读写（`app/` 各端，具体范围随 SG-4/SG-5 及第二批 console 展开） | 实现阶段主会话 sonnet 子代理 | app client 运行时验法收编入 SG-4/SG-8（Mac 壳 createSession/subscribe 闭环 + parity）；console 待第二批开门后回填 | 运行时失败落对应 round/SG-8 evidence 排查 | 无（涉 license 服务/云服务凭证时按 `harnessloop-secrets` 登记） |

## Local Channel Parameter Requirements

| Channel ID | Parameter key | Sensitivity | Storage | Required for | Must be present before |
| --- | --- | --- | --- | --- | --- |

需求分析阶段暂无已知外部凭证需求。RA-L3 技术选型确定后，若涉及 license 服务、newapi、云服务或第三方 API/SDK（openclaw/hermas/codex app sdk/claude code sdk 等），按 `harnessloop-secrets` 流程补充本表并在 `.harnessloop/local/channel-params.json` 中登记本地参数引用。

## Invalid Evidence

- 未经 probe 的 vendor 能力假设（例如未经 `hopper:probe` 实测的 vendor 能力声称）
- 未落盘的口头结论（会话内讨论但未写入 goal 契约文件或 wiki 的结论，不可作为证据引用）
- openclaw / hermas / newapi / codex app sdk / claude code sdk 的能力或接口声称：均为外部项目，实际形态与接口**待 RA-L3 调研确认**，禁止凭记忆或训练知识臆造其能力（见上方「外部项目形态待确认」）
- `harnessloop/examples/mock-project/`：已知系统性落后模板（沿用既有 goal 20260716-001-setup-wizard 的既定失效判断，无需重新评估）

## Secret Handling

- Do not store secret values in Harnessloop files.
- Store secret names, local parameter keys, required scopes, configured storage, and verification commands only.
- Use `.harnessloop/local/channel-params.json` for local ignored values or provider references.

## Revision Policy

- Human confirmation required for source changes: yes
- Human confirmation required for threshold changes: yes
