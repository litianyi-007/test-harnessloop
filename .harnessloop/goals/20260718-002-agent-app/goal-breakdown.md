# Goal Breakdown

> **状态标注**：本文件为需求分析（Requirement Analysis）阶段进阶计划，替换此前基于旧业务身份（AgentOps 控制台）的 S1-S7 dev 分解草案。**dev 分解（原型/编码/集成/收口等具体执行子目标）明确推迟，待需求达 dev-readiness gate 并经用户签署后，再次执行 `$harnessloop-goal update` 注入。** 本文件当前只覆盖需求分析各级（RA-L1 → RA-L4），不含任何编码任务。

## Long-Term Goal

以三插件（harnessloop/hopper/kata）全栈驱动，探索性设计并开发一款 agent app（仿 codex app 的消息流客户端）+ console 管理端 + server 后端，全程插件实时进化、里程碑连载直播（详见 goal.md）。

## Requirement Analysis Plan（逐级展开，每级用户确认后再下一级）

- **RA-L1**：顶层域分解（2026-07-18 用户确认，confirmed）——见下方「L1 七支柱」
- **RA-L2**：各支柱逐一展开（每支柱一轮，逐级确认门）；首轮范围：架构核心 P1-P3（用户指定优先，2026-07-18 决策，详见 goal.md「RA-L1 确认与决策」）**——2026-07-18 用户确认，confirmed**，并同步锁定架构决策 X1（本地内核优先）/ X2（统一经 newapi，详见 goal.md「RA-L2 确认与架构决策」）；P4–P7 顺延至后续轮次
- **RA-L3**：关键设计决策与技术选型，细化为 7 项决策议程（2026-07-18 细化，见下方「RA-L3 议程」）
- **RA-L4**：需求规格成型 → **dev-readiness gate**（用户签署）

### RA-L3 议程（7 项决策，2026-07-18 细化）

| ID | 决策项 | 说明 |
| --- | --- | --- |
| D1 | 内核抽象接口规格 | **negative-rework → D1-spike（conformance 补事实）→ D1 v2（重设计，scope=openclaw+hermes）→ D1 v2 双轨复核 REWORK → D1 v3（局部修复，含 openclaw 原生 steer 事实纠正）→ D1 v3 异构第二轨 REWORK → D1-spike2（steer 语义 conformance）→ D1 v3.1（局部）→ D1 v3.1 聚焦复核 codex REWORK（收敛）→ 待 v3.2 路径决策**（v1 评审否决 2026-07-21；rework 方向 user-confirmed 2026-07-21；v2 双轨复核 2026-07-21；v3 双轨复核（第二轨 codex REWORK 推翻第一轨 grok PASS_WITH_NOTE）2026-07-21；v3.1 聚焦复核（codex T-010 REWORK）2026-07-21，见 goal.md「RA-L3 D1 rework 决策」「RA-L3 D1 v2 双轨复核决策」「RA-L3 D1 v3 双轨复核决策」「RA-L3 D1 v3.1 聚焦复核决策」）：agent 内核抽象接口设计（openclaw 默认 / hermas 等可切 / codex app sdk·claude code sdk 兼容）。首版正式 spec（`kernel/d1-kernelport-spec.md`）经双轨对抗评审——第三方 codex T-004（hopper 派发，`.hopper/handoffs/T-004-output.md`）Verdict REWORK/15 findings/5 BLOCKER；内部 Sonnet 评审 Verdict negative/11 must-fix——双双否决，收敛出 7 条交集硬伤（详见设计 wiki `research/d1-review-dual-track.md`）。spec 的 `design_status` 已同步改为 `superseded`。v2 scope 收窄为 openclaw+hermes（codex/claude sdk 降为后续 profile），先做 D1-spike 补齐"未能确认"事实缺口，再在硬事实基线上重设计 D1 v2。**v2 spec 双轨复核（2026-07-21）**：第三方 grok T-006（hopper 派发，`.hopper/handoffs/T-006-output.md`）Verdict REWORK；内部 Sonnet 复核 Verdict positive-可小修——两轨**分歧**（不同于 v1 的双双否决收敛）；分歧核心是 grok 核实出一处**事实回退**：openclaw 原生有 `sessions.steer`，v2 却当它不存在、设计了 cancel+resend hack，内部 Sonnet 复核未做独立事实核查漏掉此项（详见设计 wiki `research/d1-v2-review-dual-track.md`）。v2 spec 的 `design_status` 已同步改为 `superseded`，待 D1 v3 局部修复（6 条清单，见同一 wiki 页）。**v3 spec 双轨复核（2026-07-21）**：第一轨 grok（T-007，hopper 派发，定向对抗复核）Verdict **PASS_WITH_NOTE**，判无新 BLOCKER、5 残留点均可 DEFER；第二轨 codex（T-008，hopper 派发，**异构第二轨**独立复核，故意换回 codex 保持跨 vendor 多样性，不预设 grok 结论）Verdict **REWORK**，直接推翻第一轨 PASS 结论——独立发现 2 处新 BLOCKER（OpenClaw steer "无损/保留产出"断言与文档内其他段落自相矛盾且 runtime fallback 结果态无法通过契约表达；newapi §7 per-session token 归因链自相矛盾，因果链不成立）+ 3 处 HIGH（Hermes 审批 F-06 未闭合却被误标"已消解"；审批 deny→abort→resend 缺失失败分支；`steerResendRunId`/零 active run 保护未闭合 stop 竞态与旁路可观察性），5 残留点复判中 openclaw steer 精确 RPC schema 由 grok 的 DEFER 升级为 codex 的 BLOCKER（详见设计 wiki `research/d1-v3-review.md`）。v3 spec 的 `design_status` 已同步改为 `superseded`，待 D1 v3.1 局部修复（5 条清单：①定向 conformance sessions.steer 结果态；②修复 F-06；③Hermes steer 降级建模为可观察 operation；④重新设计 §7 session 归因；⑤保持 F-05/F-11/S-09 部分化解并回归复核）。据 T-009 spike（纠正 steer 语义 + §7 条件归因）写出 `kernel/d1-kernelport-spec-v3-1.md`（wiki，651 行，7 处局部修复，详见 §13 变更记录）。**v3.1 聚焦复核（codex T-010，2026-07-21）Verdict REWORK——收敛中，无需推倒架构**：codex（刻意选择，验证自己 T-008 提出的 5 findings 是否真解，reasoning effort xhigh）逐条核验，1/5 完全核销（Hermes CLI/ACP profile 断裂）、4/5 部分修复未闭环（BLOCKER-1 steer 结果态判定规则建立在未确认信号之上；BLOCKER-2 §7 因果矛盾已改正但 sessionId 时序/attribution 证据仍不足；HIGH 审批 deny 失败分支引入无名中间态；HIGH session 锁+operationId 覆盖不完整）；另发现 7 处新矛盾（5 HIGH + 1 MEDIUM + 1 LOW）；DEFER 复判中 `allow_session` 归一与 pending #2 升级为"确认前必解"，soft `chat.send` 响应信号复判为 BLOCKER、不可 DEFER（详见设计 wiki `research/d1-v31-review.md`）。v3.1 spec 的 `design_status` 已同步改为 `superseded`，待 D1 v3.2 路径决策（详见 goal.md「RA-L3 D1 v3.1 聚焦复核决策」）。下一步：待用户在 v3.2 三条路径（诚实收窄 outcome 语义 vs 执行 live probe vs 两者结合）中定夺 |
| D1-spike | KernelPort conformance spike（D1 子步骤） | scope=openclaw+hermes；逐项补齐双轨评审标出的"未能确认"事实缺口（如 Hermes stop 能力、newapi 计费查询接口、事件 seq/时间戳原生支持等），落盘为可验证硬事实基线，作为 D1 v2 重设计输入；user-confirmed 2026-07-21，见 goal.md「RA-L3 D1 rework 决策」 |
| D2 | 消息 schema 规格 | UI 消息流数据源 与 agent 输入输出消息源 之间的屏障层 schema 设计 |
| D3 | Server 技术选型 | **confirmed（user-confirmed 2026-07-21）**：TypeScript + NestJS + PostgreSQL；应用内 JWT license（签发/校验/吊销）+ 共享库多租户（`tenant_id`，非独立 schema/数据库）+ 自建坐席（seat/membership）与能力开关（feature flags）表；new-api 仅作为 Management API 集成对象（token/channel/用量对账等），非多租户主账本。依据：T-002 grok 研究（`.hopper/handoffs/T-002-output.md`）。X1 确定后 server 收敛为瘦控制面（license/租户/坐席/能力开关/费用/newapi 设置），选型范围随之收窄 |
| D4 | Mac→Windows 跟随开发机制 | 保留平台特点的同时保证功能与交互细节对齐 |
| D5 | 仿 codex app 产品规格 | 功能与交互参照（不做代码级复制），产品规格落地 |
| D6 | newapi 集成方式 | X2 确定后，内核 LLM 调用统一经 newapi 网关的具体接入方式 |
| D7 | 本地内核分发打包 | X1 确定后，客户端本地内核的分发打包机制 |

**外部资料依赖标注**：D1 / D6 / D7 依赖 openclaw / hermas / newapi / codex app sdk / claude code sdk 的真实资料（接口文档、能力范围、集成方式等），资料**待用户提供或 hopper 调研**，调研完成前不得臆造（见 data-contract.md）。

### 架构骨架（2026-07-18，随 RA-L2 确认 + X1/X2 决策落盘）

客户端本地运行 agent 内核（openclaw 默认，hermas 等可切换）+ 内核抽象层（D1）+ 消息屏障（D2，隔离 UI 消息流数据源 与 内核输入输出消息源，使内核切换对 UI 透明）+ UI（消息流为核心，仿 codex app 产品形态）；内核的 LLM 调用统一经 newapi 网关（X2，计费/成本/能力开关统一入口）。Server 收敛为瘦业务控制面（X1）：只管 license / 租户 / 坐席 / 能力开关 / 费用 / newapi 设置，不跑 agent 本体。Console 是 server 数据面的管理界面，管理端功能面对应上述 server 职责。

**横切（按触发发生，不占级编号）**：

- **插件进化流**：由 RA-L1–L4 各级实战触发的三插件改进，沿用 TH-xxxx 编号与版本发布留痕惯例，发布节奏不与 RA 级绑定
- **连载内容流**：里程碑驱动的文章连载，成稿至 PR wiki `drafts/`，发布节奏不与 RA 级绑定

## L1 七支柱（2026-07-18 用户确认，confirmed）

| ID | 支柱 | 概要 | 状态 |
| --- | --- | --- | --- |
| P1 | 产品形态 | 仿 codex app，消息流为核心 | confirmed |
| P2 | Agent 内核抽象层 | openclaw 默认 / hermas 等可切 / codex·claude sdk 兼容 | confirmed |
| P3 | 消息流抽象屏障 | UI 消息流数据源 与 agent 输入输出消息源 之间的屏障层，使内核切换对 UI 透明 | confirmed |
| P4 | 客户端工程 | 原生优先 · Mac 优先 · Mac→Windows 跟随开发机制 | confirmed |
| P5 | 身份与商业化 | license / 租户 / 坐席 / 能力开关 / 费用 | confirmed |
| P6 | Console 管理端 | license 管理 / 租户管理 / 能力开关 / 费用管理 / 基于 newapi 的设置 | confirmed |
| P7 | Server 后端 | 完整调研选型（用户不擅长 server 开发，由我方提供） | confirmed |

## Discovery Handoffs

| Handoff | Purpose | Inputs | Output path | Status |
| --- | --- | --- | --- | --- |
| （RA-L2 尚未开启，无已派发 handoff） | | | | |

## Subgoals（需求分析阶段，非 dev 分解）

| ID | Subgoal | Depends on | Evidence required | Validation method | Risk |
| --- | --- | --- | --- | --- | --- |
| RA-L1 | 顶层域分解：七支柱（P1–P7）结构呈现 | 无 | 本文件「L1 七支柱」表 + 用户确认记录（2026-07-18） | 用户确认门（已通过，2026-07-18） | 七支柱粒度与边界经用户 2026-07-18 确认，无需调整；RA-L2 首轮（架构核心 P1-P3）已据此展开 |
| RA-L2 | 各支柱（P1–P7）逐一展开：每支柱产出细化需求点；首轮范围＝架构核心 P1-P3（用户指定优先，2026-07-18 决策） | RA-L1（已确认，2026-07-18） | 各支柱展开文档 + 架构决策 X1/X2（见 goal.md「RA-L2 确认与架构决策」） | 每支柱一轮，用户逐级确认门（首轮 P1-P3 已通过，2026-07-18） | 首轮（P1-P3）confirmed，2026-07-18；P4–P7 顺延后续轮次，展开时需标注与已确认架构（X1 本地内核优先 / X2 统一经 newapi）的交叉引用 |
| RA-L3 | 关键设计决策与技术选型：细化为 7 项决策议程 D1-D7（内核抽象接口 / 消息 schema / Server 选型 / Mac→Windows 跟随开发 / 仿 codex app 产品规格 / newapi 集成方式 / 本地内核分发打包，见上「RA-L3 议程」表） | RA-L2（已确认，2026-07-18） | 调研文档（含 hopper research 产物，D3 已授权首战）+ 设计决策记录 | 对抗性设计评审 + 用户确认技术选型 | D3 server 调研为 hopper research 首次实战，产物质量未知；D1/D6/D7 依赖 openclaw/hermas/newapi/codex-app-sdk/claude-code-sdk 真实资料，待用户提供或 hopper 调研，调研完成前禁止臆造能力（见 data-contract.md） |
| RA-L4 | 需求规格成型：汇总 RA-L1–L3 产出为 dev-ready 规格文档 | RA-L3（用户确认后） | dev-ready 规格文档 | 用户签署 dev-readiness gate | 规格可能存在遗漏或内部不一致，签署前需自洽性检查（见 thresholds.md） |

**dev 分解（原型/编码/集成/收口）**：TODO (owner: 待 RA-L4 dev-readiness gate 用户签署后，再次执行 `$harnessloop-goal update` 注入)——本次 material change 明确推迟，非遗漏。

## Tasks

| ID | Task | Parent subgoal | Scope boundary | Evidence required | Validation method |
| --- | --- | --- | --- | --- | --- |
| （RA-L1 已确认；RA-L2 首轮（架构核心 P1-P3）展开中，task 级按需补充本表） | | | | | |

## Main-Session Decision

Chosen sequence: RA-L1 → RA-L2 → RA-L3 → RA-L4 → dev-readiness gate（签署后注入 dev 分解）；插件进化流与连载内容流为横切线，随各级触发产出，不独占级编号、不阻塞需求分析主线推进。

Rejected alternatives: 已否决"直接展开全量 dev 分解（原 S1-S7）"——用户 2026-07-18 明确指令需求分析阶段逐级展开、每级用户确认后再下一级，dev 推迟至 dev-ready 后再议，故不采用一次性展开。

Reasoning: 业务与技术栈本轮经用户重定（agent app 仿 codex app + 内核抽象 + 消息流屏障 + Mac 优先原生开发 + Mac→Windows 跟随开发机制 + server 调研待定 + console 功能面锁定），此前基于旧业务身份（AgentOps 控制台）的 S1-S7 dev 分解已不适用，故整体替换为需求分析进阶计划。逐级确认门的设计目的：避免在技术栈与内核抽象等高不确定性设计决策未澄清前过早锁定 dev 分解，尤其 server（用户不擅长）与内核抽象（涉及 openclaw/hermas/两 SDK 兼容）需要 RA-L3 完整调研支撑，不能凭假设展开。
