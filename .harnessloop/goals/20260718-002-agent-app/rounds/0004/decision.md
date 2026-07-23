# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker；过程中的 2 处 contract-insufficient 情形已当场经用户授权解除）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0004（SG-8.5 计费链 e2e 完整闭合）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-23

## Reason

SG-8.5 的验收边界由 scope-lock 预先诚实分层为阶段1（D3 起）/阶段2（D3→newapi→Kimi 腿）/阶段3（openclaw 腿→完整链），且明确"阶段1-2 达成即 SG-8.5 主体，阶段3 达成即完整 per-session 链闭合"。执行结果：**三阶段全部达成**——D3-proxy 本机起并连通 Pi Postgres + Pi new-api；curl 直连验证 D3→newapi→Kimi 腿真实可用；真实（隔离）openclaw 内核动态注入真实 sessionId 完成完整链闭环。铁证：两个不同 session 的真实 sessionId（`016c7dc2-745a-4067-b180-f0a2c8675927`/`955f0c1f-aadb-4350-93d2-1b0ce2a78caa`，补丁前 D3 侧观测为 `(missing)`）动态到达 D3，证明动态注入 + per-session 精确区分；session_A seed 映射后 `send` → Kimi 真实回复 "PERSESSION-DONE"；new-api 计费落账（`/api/log/` id 19，token `sg8.5-kimi-e2e/id3`，model `kimi-for-coding`，channel `kimi-coding`，prompt 9400/completion 32，与 run usage 精确吻合）。全程未碰用户全局 gateway（18789）。

证据充分（三阶段各有独立可核验证据：D3 连通日志/curl 输出/两 session 动态区分+真实回复+计费日志精确吻合）且收敛（无一处把未证部分表述为已过；阶段3 达成，未降级 defer），故本轮 feedback 分类 **positive**。

本轮延续 rounds/0002/0003 建立的做法——**scope-lock 先于执行、走完整 round → decision → state 回写闭环**，是 goal 002 第四个走完整闭环的执行轮，也是首个真正把「内核 → D3-proxy → newapi → 上游 LLM」全链路串通的执行轮。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-8.5 的 done 判定为「完整链 e2e 闭合」级，是本轮 scope-lock 分层里的最高档（阶段3 完整 per-session 链）**——不是阶段1-2 的降级 defer 结果。这是 SG-8.5 与此前各 SG（多为静态编译级/L1 连通级/部署级）的关键区别：SG-8.5 是 goal 002 第一个达到**真实端到端运行**验收级别的子目标。
- **本轮 scope 演化（2 次 user 授权扩围）经裁定为 user-confirmed 的 contract-insufficient blocker 处置，非 scope drift/协议违规**：rounds/0004/scope-lock.md 原 Disallowed Changes 明确"不改 kernels/openclaw 源码"；执行阶段3 时发现 openclaw 存在 2 处真实源码 bug（`ModelCompatSchema` zod 校验遗漏 6 个 compat 字段；transport 热路径不透传 sessionId）挡住真实动态 per-session 归因。按 control-contract.md 「contract-insufficient → Repair contract before execution」的既定处置路径，主会话两次都先停下向用户说明"必须改内核源码才能通、scope-lock 当前明确禁止"，用户当场分别确认（schema 补丁一次、transport 补丁一次）后才落地，未擅自扩围。这与 rounds/0003（Docker Hub 连接重置→配镜像加速器）性质不同——那是 scope-lock 授权范围内的 `runtime-recoverable` 调整；本轮是**触及 Disallowed Changes 明确禁止项**，走的是更严格的"停下+用户现场确认"路径，且已如实记录，未回改 scope-lock 掩盖偏离。
- **SG-6 设计结论同步修订**：SG-6 spike 原判定"openclaw 主路径零源码改动"（复用既有 `sendSessionAffinityHeaders` 开关，纯部署配置）在真实运行系统里被证伪——转为"3 处极小补丁"（schema `4ddcb52` + transport `35f8739` + 既有辅助路径 `824adcf`）。**方案A（原生凭证 patch，5 文件、撞 secrets 红线）被否决的结论不变、仍成立**——本次修订只针对方案B 的"零改动"这一具体声称，不改变"方案B 优于方案A"这一决策方向本身。SG-6 原「done（code+对抗审级）」verdict 不因此撤销（当时验收范围本就是 code 落地 + 对抗审级，不含 e2e）。修订已同步落 SG-6 wiki doc（`~/.llm-wiki/agent-app-design/architecture/sg6-openclaw-persession-patch-design.md`）与 goal-breakdown.md SG-6 行/SG-6 实施收口段。
- **根因裁定**：SG-6 spike 的这次证伪根因是——spike 只验证了 TS 类型层声明了 `sendSessionAffinityHeaders`，**没有实际跑一遍 spike 自己 §6 验证计划表列出的"config 校验走一遍"这一验证项**，也没有测试真实运行的 transport 路径（provider-adapter 路径与 transport 路径是两条独立代码路径，spike 只走读了前者）。归类为"下游实现连环证伪上游设计"第 5 例，且本例连环两层：静态 header 方案一度掩盖了动态注入机制（transport 版本）其实是死代码。
- **未做的第三方对抗审已如实记录为 Open Risk，非 done 判定前提**：本轮 2 处新增 openclaw 补丁未经 codex/grok 对抗审，与 rounds/0002/0003 先例一致（以主会话独立复验的运行时证据为 positive 依据），是否补审留待后续决定。
- **下一步待选**：**SG-5**（Windows C# kernel-client parity 追赶）/ **SG-3**（codegen 增量）/ 决策类待办（2 个 openclaw bug 是否上游 push/开 issue、是否补第三方对抗审、主仓库 commit submodule 指针）/ 副发现处理（body-parser limit、workspace-dir recipe）。

## Open Questions Resolved

- **C-3 path① 在真实运行系统上是否成立**：成立——本轮首次给出完整链路的真实运行证据（两 session 动态区分 + 真实回复 + 计费日志精确吻合），此前 PRE-①（只读源码核验）与 SG-6（code+对抗审级）均未做过真实 e2e，本轮补上。
- **SG-6"零源码改动"声称是否经得住真实运行系统检验**：不成立——已据实修订为"3 处极小补丁"，根因已定位（spike 未跑自己 §6 验证项 + 未测 transport 路径），详见上方。
- **scope-lock Disallowed Changes 撞线时应如何处置**：本轮验证了既定路径（停下→向用户说明→现场确认→落地→如实记录）可行，两次均按此路径处置，未发生"先斩后奏"的协议违规。

## Open Questions Deferred

- **2 个 openclaw 真实 bug（`4ddcb52`/`35f8739`）是否上游 push 给 openclaw 官方仓库、或另开 evolution-issue 记录**：待后续决定，非本轮 scope。
- **是否为 `4ddcb52`/`35f8739` 补一轮第三方对抗审（codex/grok）**：待后续决定，非本轮 done 判定前提。
- **主仓库 `kernels/openclaw` submodule 指针 commit（现工作区已指向 `35f8739`，主仓库尚未 commit 该指针变更）**：留待主会话统一处理，本轮不 commit。
- **副发现**：`app/server` 100KB body-parser 限制建议调大（真实 agent 请求 ~107KB 需绕过）；`app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 待补 `OPENCLAW_WORKSPACE_DIR` 隔离依赖条目——均记录为后续独立待办，非本轮 scope（本轮纪律不改 app/）。
- **SG-8.1 清单的正式收口**：本轮证据实质上覆盖 SG-8.1 四项 pass 条件里的大部分（header 真到达/sessionId 动态区分/mint 写映射表行），但未逐条正式勾稽核对（尤其"真 newapi SSE 帧透传，帧序不乱不缓冲"这一项本轮未专门验证），留待后续轮次显式核对再关闭，不在本轮顺带声称。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E14 | app/deploy/newapi + app/server（D3-proxy 运行）+ kernels/openclaw 补丁（`4ddcb52`/`35f8739`）+ scratchpad/openclaw-iso3/ | SG-8.5 done（完整链 e2e 闭合）的直接依据：两 session 动态区分 + Kimi 真实回复 + new-api 计费日志精确吻合 |
| E13 | app/deploy/newapi/docker-compose.yml + gitignored channel-params.json | SG-9 newapi 实例就绪（本轮前置底座之一），追溯依据 |
| E8 | app/server（D3-proxy session-affinity 路由）+ SG-6 design spec | SG-6 code+对抗审级 done 的既有依据；本轮不撤销该 verdict，仅修订其援引的"零改动"设计前提 |
| E12 | app/kernel-client/（swift/csharp）+ RUN-EVIDENCE.md | SG-4 L1 连通闭环（本轮前置底座之一），追溯依据 |

## Next Action

- Action type: 收盘 → 待选下一 SG 开新 round，或先处理决策类待办
- Scope-lock required: yes（下一 SG 开 round 时新建 scope-lock）
- Human confirmation required: 否（SG-8.5 本身已完整交付，闭合本身不需用户进一步确认）——但"2 个 openclaw bug 是否上游 push/开 issue"、"是否补第三方对抗审"、"主仓库 submodule 指针 commit 时机"三项决策类待办，待后续与用户或主会话统一裁定
- Safe without user input: yes（本轮收盘）；下一步若改推 SG-3/SG-5，一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 从 **SG-5**（Windows C# kernel-client parity 追赶）/ **SG-3**（codegen 增量）/ 决策类待办 / 副发现处理中择一或并行，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 SG-8.1 清单表述为"已正式收口"直至逐条核对（尤其真实 newapi SSE 帧透传这一项）；不得把 2 个 openclaw bug 的"是否上游反馈"默认为"不需要"或默认为"已经处理"——该决策明确 deferred，未裁定
