# Goal

## Goal

以三插件（harnessloop 高自动化 / hopper 异构算力低成本 / kata 知识沉淀）全栈驱动，探索性设计并开发一款 **agent app**——产品形态仿照 codex app（以消息流为核心的 agent 客户端）。

- 登录需获取 license；个人用户免费；企业场景支持租户（tenant）概念，租户下坐席（seat）收费
- 配套 **console** 管理端与 **server** 后端
- 全程三插件全栈驱动、插件实时进化、里程碑连载直播
- 本 goal 为探索性项目，失败与成功皆为可接受结果

### 业务技术要点（user-specified 2026-07-18，作为 source-of-truth 锁定）

- **Agent 内核**：默认基于 openclaw 最新稳定分支；支持 hermas 等相似项目内核切换；兼容考虑 codex app sdk / claude code sdk。故需一层内核抽象接口支持核心 agent 抽象
- **消息流屏障**：app 核心 UI（消息流）数据源 与 agent 输入输出消息源 之间需抽象一层屏障，使内核切换对 UI 透明
- **Console 功能面**：license 管理 / 租户管理 / 租户下能力开关（plugin 开关、skill 开关）/ 费用管理 / 基于 newapi 的设置（系统管理员）

### 技术栈偏好与约束（user-specified 2026-07-18）

- **App**：主流做法为前端 + electron，但用户要求不牺牲性能与效果、尽可能原生开发、优先 Mac；需设计一套机制支持 Mac 开发进度同步到 Windows 跟随开发（保留平台特点的同时保证功能与交互细节对齐）
- **Server**：用户不擅长 server 开发，需由我方提供完整调研与选型
- **Console**：技术栈未定（交设计轮），功能面如上（业务技术要点节）

### RA-L1 确认与决策（user-confirmed 2026-07-18，作为 source-of-truth 锁定）

- **决策 1 — 七支柱结构确认**：`goal-breakdown.md` L1 七支柱（P1–P7）顶层域划分经用户确认，粒度与边界无需调整；状态由 pending 转为 confirmed
- **决策 2 — L2 展开顺序**：RA-L2 首轮范围为「架构核心优先」，先展开 P1（产品形态）/ P2（Agent 内核抽象层）/ P3（消息流抽象屏障）三支柱；P4–P7（客户端工程 / 身份与商业化 / Console 管理端 / Server 后端）顺延至后续轮次
- **决策 3 — 仿照 codex app 边界**：仿照对象限定为「功能与交互参照」，具体实现自主设计，不做代码级复制、反编译或资产挪用；合规风险低（仅参照公开可见的产品功能与交互形态进行独立实现，不涉及源码获取或商标冒用）

### RA-L2 确认与架构决策（user-confirmed 2026-07-18，作为 source-of-truth 锁定）

- **RA-L2 架构核心（P1-P3）已确认**：P1 产品形态 / P2 Agent 内核抽象层 / P3 消息流抽象屏障 三支柱展开细化经用户 2026-07-18 确认，状态由 pending 转为 confirmed；P4–P7 顺延至后续轮次
- **决策 X1 — 本地内核优先**：agent 内核在客户端本地运行（非 server 侧托管）。连带影响：客户端须承担本地内核分发；跨平台（Mac→Windows）双实现负担更重；server 收敛为不跑 agent 本体的瘦控制面
- **决策 X2 — 统一经 newapi**：所有内核的 LLM 调用统一经由 newapi 网关，newapi 成为计费/成本/能力开关的统一入口

这两个决策使 server 从重后台收敛为瘦业务控制面。

### RA-L3 D3 确认与决策（user-confirmed 2026-07-21，作为 source-of-truth 锁定）

- **决策 D3 — Server 技术选型确认**：RA-L3 议程 D3（Server 技术选型）经用户 2026-07-21 确认，采纳方案 A：**TypeScript + NestJS + PostgreSQL**。具体：应用内 JWT license 签发/校验/吊销；多租户采用共享库 + `tenant_id`（非独立 schema/数据库）；坐席（seat/membership）与能力开关（feature flags）自建表；new-api 仅作为 Management API 集成对象（token/channel/用量对账等），**非**多租户 SaaS 主账本。依据：T-002 grok 调研（`.hopper/handoffs/T-002-output.md`）。对应设计 wiki 页 `server/server-stack-selection.md` 的 `design_status` 同步由 draft 转 confirmed。

### RA-L3 D1 评审结论与决策（2026-07-21）

- **决策 D1（阶段性）— 首版 spec 双轨对抗评审 REWORK，不予确认**：RA-L3 议程 D1（内核抽象接口规格）的首版正式 spec（设计 wiki `kernel/d1-kernelport-spec.md`）经**双轨对抗评审**——第三方轨（codex，hopper 派发任务 T-004，`.hopper/handoffs/T-004-output.md`）Verdict **REWORK**，15 findings，5 BLOCKER；内部轨（Sonnet，本会话独立执行）Verdict **negative**，11 项 must-fix——**双双否决**。两轨互相独立执行、互不参照产生内容，仍收敛到同一组 **7 条交集硬伤**：Claude 生命周期不同构 / INV-5 自相矛盾（裂缝下推给 UI/P3 违反自身不变量）/ newapi 计费不可归因到具体 run / capabilities 静态声明违反 INV-4（能力显式声明不变量）/ canUseTool 回调桥接可致永久挂起 / Hermes stop 能力"未能确认"被对照表当作"已确认" / seq 断线重放语义存在悬空引用。评审综合与各自独有发现（codex 8 项 + Sonnet 4 项）详见设计 wiki `research/d1-review-dual-track.md`。
- **核心诊断**："单一窄腰无缝跨四内核"这一核心主张被过度声称；Claude Agent SDK 的生命周期不同构（`query()` 单阶段 vs `createSession()`/`send()` 两阶段）是四内核间最深的一条裂缝，不是字段级适配能抹平的；多个已在 RA-L2/X1/X2 层面确认的架构职责（计费权威在 newapi、内核切换对 UI 透明）在 D1 当前设计里找不到生效路径。
- **落盘处置**：设计 wiki `kernel/d1-kernelport-spec.md` 的 `design_status` 已由 `draft` 改为 `superseded`（正文未删除，保留作审计与 v2 重设计对照基线）；`goal-breakdown.md` RA-L3 议程表 D1 行状态标注同步改为 `negative-rework`。
- **Next（待用户决定）**：D1 v2 重设计方向——是先做 **conformance spike**（锁定四个具体 adapter profile/版本做 7 方法逐项验证，参考 codex Next recommendation）优先验证，还是**直接按两轨建议重构**（生命周期分离 Claude 特例、审批状态机、能力协商模型、newapi 关联字段等）——留待用户在下一轮确认。
- **feedback-policy 适用性说明**：本次 D1 否决属于 `feedback-policy.md`「补充条款：探索性否定结论」的适用范围——D1 是 RA-L3 关键设计决策之一，本次评审否决是**有充分证据支撑的阶段性否定结论**（证据路径可追溯至 `.hopper/handoffs/T-004-output.md` 与设计 wiki `research/d1-review-dual-track.md`，结论基于实际评审产出而非臆测），按该条款应作为**正常迭代（探索成功的一种形式）处理，不计为 negative/失败**；不适用于协议执行故障（本次评审派发与落盘过程本身无执行故障）。

### RA-L3 D1 rework 决策（user-confirmed 2026-07-21，作为 source-of-truth 锁定）

- **决策 ①（v1 scope 收敛）— KernelPort v1 聚焦本地进程内核**：v1 抽象接口范围收敛为 **openclaw（默认）+ hermes** 两个本地进程内核——二者同属本地进程、Gateway 结构契合，可在同一窄腰下合理适配；**codex app sdk / claude code sdk 两内核降为后续 profile**（不在 v1 scope 内，是否及何时展开留待后续轮次视需要另起议程）。此举消解评审对"单一窄腰无缝跨四内核"的"过度声称"批评——SDK 内核在 goal.md「业务技术要点」节原文措辞即为"兼容**考虑**"，非"必须支持"，v1 收窄不违背既有 source-of-truth。
- **决策 ②（rework 方式）— spike-first：先补事实、再重设计**：D1 v2 不直接在 v1 spec 上打补丁重构，而是先执行 **conformance spike**——针对 openclaw + hermes 两个内核，逐项补齐双轨评审标出的"未能确认"事实缺口（如 Hermes stop 能力、newapi 计费查询接口、事件 seq/时间戳原生支持等），落盘为可验证的硬事实基线；再在该硬事实基线上重设计 D1 v2。目的：避免 v2 重蹈 v1"未验证先声称"的覆辙。
- **SDK profile 化对 5 BLOCKER 的消解与残留**：v1 spec 双轨评审第三方轨（codex T-004，`.hopper/handoffs/T-004-output.md`）标出 5 项 BLOCKER。SDK 内核降为后续 profile、不在 v1 scope 后，其中 2 项因"争议主体本轮不在 scope 内"而随之消解：
  - **F-01（Claude 生命周期不同构：`query()` 单阶段 vs `createSession()`/`send()` 两阶段）—— 消解**
  - **F-04（`canUseTool` 回调桥接可致永久挂起）—— 消解**

  其余仍需在 D1 v2（scope=openclaw+hermes）中解决，且对 openclaw+hermes 同样成立、不因 SDK 延后而消解：
  - F-07 — INV-5 自相矛盾（裂缝下推给 UI/P3 违反自身不变量）
  - F-09 — newapi 计费不可归因到具体 run
  - F-11 — capabilities 静态声明违反 INV-4（缺 `capabilities_changed` 事件）
  - F-02 — Hermes stop 能力"未能确认"被对照表当作"已确认"
  - F-12/F-13 — seq / 断线重放语义存在悬空引用
  - error code 枚举不完整（源自内部 Sonnet 轨 11 项 must-fix）
  - run 串行化 / stop 时序（cancel+resend 无 run 级寻址或完成屏障；对应 F-08 及 codex Next recommendation 中"run-targeted cancel 与 terminal barrier"）
  - 多 session 场景未覆盖（源自内部 Sonnet 轨 11 项 must-fix）

### RA-L3 D1 v2 双轨复核决策（2026-07-21）

- **决策 D1（v2 阶段）— v2 spec 双轨复核 REWORK，两轨分歧，不予确认**：RA-L3 议程 D1 的 v2 正式 spec（设计 wiki `kernel/d1-kernelport-spec-v2.md`，scope=openclaw+hermes）经**双轨复核**——第三方轨（grok，hopper 派发任务 T-006，`.hopper/handoffs/T-006-output.md`）Verdict **REWORK**（3 处 BLOCKER + 2 处 HIGH）；内部轨（Sonnet，本会话独立执行）Verdict **positive-可小修**（对 v2 §10 自评"10 条已消解"逐条复核，判 7 条真消解、3 条部分消解，未判出任何一条未消解）。**两轨 verdict 分歧**——不同于 v1 spec 双轨评审的"双双否决、收敛出交集硬伤"，本次是"一负一正"。
- **分歧的核心与价值**：分歧集中在 F-07（INV-5 自相矛盾）一项，根源是一处**事实回退**——grok 核实出 openclaw 原生支持 `sessions.steer`（设计 wiki `kernel-ecosystem-facts.md` 第 42 行明确列出，且与 T-003 原始研究产物一致），但 v2 spec §5/§6.1/§8 在没有新否定证据的情况下，把这一已确认事实静默抹除，断言 openclaw 无原生 steer、仅走 abort，进而设计了内部 cancel+resend 降级路径整条替代覆盖 openclaw——grok 判定这是 v1 F-02 类问题（"未能确认"当"已确认"处理）的同类复发，方向相反但性质相同（这次是把"已确认"当"不存在"处理）。**内部 Sonnet 复核未做独立的官方文档/事实基线交叉核查，沿用了 v2 正文的表述，因而漏掉了这条事实回退**，误判 F-07 为真消解，是两轨分歧的根本原因。这一分歧证明：第三方异构复核（不同 vendor、强制 web-search 交叉官方文档）能够抓到同源内部复核（未独立核查事实、容易沿用被评审对象自身叙事）的系统性盲区——分歧本身不是噪声，而是保留双轨复核流程（尤其保留异构第三方轨）的直接证据与理由。
- **落盘处置**：设计 wiki `kernel/d1-kernelport-spec-v2.md` 的 `design_status` 已由 `draft` 改为 `superseded`（正文未删除，保留作审计与 v3 修订对照基线），顶部已加双轨复核 REWORK 通知；综合复核结论见设计 wiki `research/d1-v2-review-dual-track.md`；`goal-breakdown.md` RA-L3 议程表 D1 行状态标注同步更新为"D1 v2 双轨复核 REWORK→D1 v3"。
- **D1 v3 局部修复清单（6 条，非推倒重来）**：两轨均认为 v2 的 scope 收窄、F-02/F-03/F-09/F-10/F-14、SDK 延后方向正确，只需局部修复：① openclaw 采用原生 `sessions.steer`（cancel+resend 降级路径收窄为仅 hermes）→ 同时溶解 INV-5/F-07 三处互斥与 `nextRunId` 时序悖论；② 审批超时终态触发机制（`timeoutAuthority` 字段钉死 openclaw/hermes 双时钟权威）；③ cancel+resend（收窄后）完成屏障零 active run 竞态（补超时与失败路径）；④ `degraded`↔`forceResolvedApprovals` 定序（grok 独立同判 BLOCKER，两轨在此项收敛）；⑤ F-05（`updatedInput`）/F-11（capabilities override 通道）从"已消解"降级为"部分化解"的诚实表述；⑥ 加 `protocolVersion`/`contractVersion` 字段（呼应 v1 遗留 S-09，两轮独立评审均指出但未落地）。详见设计 wiki `research/d1-v2-review-dual-track.md` 第 4 节。
- **feedback-policy 探索条款适用性说明**：本次 v2 复核分歧属于 `feedback-policy.md`「补充条款：探索性否定结论」的适用范围——D1 是 RA-L3 关键设计决策之一，本次复核（含其内部分歧）是**有充分证据支撑的阶段性结论**（证据路径可追溯至 `.hopper/handoffs/T-006-output.md` 与设计 wiki `research/d1-v2-review-dual-track.md`，结论基于实际复核产出而非臆测，且两轨分歧本身已被溯源到具体可核验的事实回退，不是主观判断分歧），按该条款应作为**正常迭代（探索成功的一种形式）处理，不计为 negative/失败**；不适用于协议执行故障（本次两轮 hopper 派发与设计 wiki 落盘过程本身均无执行故障）。

### RA-L3 D1 v3 双轨复核决策（2026-07-21）

- **决策 D1（v3 阶段）— v3 spec 异构第二轨复核 REWORK，推翻第一轨 PASS，不予确认**：RA-L3 议程 D1 的 v3 正式 spec（设计 wiki `kernel/d1-kernelport-spec-v3.md`，scope=openclaw+hermes，v2 局部修订版）先经**第一轨**复核——grok（hopper 派发任务 T-007，`.hopper/handoffs/T-007-output.md`，定向对抗复核）Verdict **PASS_WITH_NOTE**：核实 v2→v3 六条修复清单均真实落地，官方文档核查后判定 OpenClaw `sessions.steer` 产品级 inject 语义部分可确认，无新 BLOCKER，5 残留点（openclaw steer 精确 schema / `server_override` 生产通道 / 完成屏障超时上限 / `protocolVersion` 无协商流程 / 独立复核本身）均判 **DEFER**。按双轨复核纪律，随后追加**异构第二轨**——codex（hopper 派发任务 T-008，`.hopper/handoffs/T-008-output.md`，故意换回 codex 与 T-007 grok 形成跨 vendor 多样性，不预设 grok 结论）Verdict **REWORK**，明确写出"不认可 grok T-007 的 PASS_WITH_NOTE"，直接**推翻**第一轨结论。
- **两轨分歧的性质与异构价值**：与 v2 阶段"内部 vs 第三方"的分歧不同，本次是**两个独立第三方异构 vendor 之间**的分歧。两轨都认可"v3 声称的 6 处修复文本上真实存在"，分歧不在"改没改"，而在"改得够不够"——grok 的核实方法是逐条对照 diff/字段是否新增 + 官方文档核实产品级语义是否存在，足以确认 v3 未臆造能力，但不足以发现"v3 在同一文档内部对同一能力做出强弱不一致的两种断言"（OpenClaw steer 既称"无损/保留产出"又承认"是否保留已产出未能确认"），也不足以发现"新字段是否覆盖所有失败/竞态分支"。codex 独立发现 **2 处新 BLOCKER**：①OpenClaw steer 结果态无支撑——`interrupt()` 返回值没有 `accepted_as_steer/queued_as_followup` 等结果态，runtime 拒收退化为普通 prompt 时无法被 UI/P3 感知，违反 INV-4/INV-5；②newapi §7 归因链自相矛盾——`tokenRef` 明确不用于模型调用、不注入模型请求，却要靠其 `token_name` 查日志做 session 级归因，因果链不成立，`createSession` 时序也未闭合。另有 **3 处 HIGH**：Hermes 审批 F-06（`allow_session` 无法在 `allow_once/allow_always/deny` 中无损归一、pending #2 缓冲策略未定、CLI/ACP profile 断裂）仍未闭合却被 v3 误标"已消解"；审批 deny→abort→resend 缺失 deny 失败/超时/已终态三分支；`steerResendRunId`/零 active run 保护只闭合主调用方，未闭合 `stop()` 竞态与旁路消费者可观察性。5 残留点复判中，openclaw steer 精确 RPC schema 由 grok 的 DEFER **升级为 codex 的 BLOCKER**（不只是字段未知，runtime fallback 会改变逻辑结果、现有返回类型/事件无法表达）；其余仍可 DEFER 但需带门闩条件。综合分析详见设计 wiki `research/d1-v3-review.md`。
- **教训——异构第二轨推翻第一轨 PASS 的价值**：本次分歧证明，单轨 PASS_WITH_NOTE（即便该轨诚实、有官方文档支撑）不能被视为终局；第二只独立、异构（不同 vendor、不预设前一轨结论）的复核眼睛，系统性地追问了第一轨未追问的"语义闭环"问题——不只是"该能力是否存在/是否臆造"，还要追问"该能力的所有失败/退化/竞态分支是否都能被契约表达"。这是继 v2 阶段"第三方抓到内部同源盲区"之后，双轨（乃至多轨）复核纪律第二次证明其必要性，且这次证明的是"第三方轨之间也不能只跑一条就收敛"。
- **落盘处置**：设计 wiki `kernel/d1-kernelport-spec-v3.md` 的 `design_status` 已由 `draft` 改为 `superseded`（正文未删除，保留作审计与 v3.1 修订对照基线），顶部已加"经异构第二轨 codex REWORK，待 v3.1"说明段；综合复核结论见设计 wiki `research/d1-v3-review.md`；`goal-breakdown.md` RA-L3 议程表 D1 行状态标注同步更新为"D1 v3 异构第二轨 REWORK→D1-spike2(steer 语义 conformance)→D1 v3.1(局部)"。
- **D1 v3.1 修复计划（5 项，codex Next recommendation，非推倒重来）**：①定向 conformance `sessions.steer`——把 `accepted_as_steer | queued_as_followup | rejected` 等结果态、实际命中 runId 与返回 schema 纳入 `interrupt()` 结果/事件，删除"无损/原生保留产出"断言；②修复 F-06——加入 `allow_session` 或写明严格等价映射，定义第 2 个 pending 的缓冲/超时策略，钉死 Hermes ACP-only 或拆 profile；③将 Hermes steer 降级建模为可观察 operation——同一 session 锁覆盖 `send/interrupt/stop`，统一 Promise 失败通道，补 deny-confirm/resend 失败与 timeout 上限；④重新设计 §7——先取得/预分配 sessionId，再让该 session 的真实模型调用使用专用 newapi token，若做不到则撤回 session 级归因声明；⑤保持 F-05/F-11/S-09 为部分化解，修后再跑一次聚焦上述四项的回归复核。详见设计 wiki `research/d1-v3-review.md` 第 6 节。
- **收敛趋势**：v1 全推倒重来（两轨双双否决，15+11 项 must-fix）→ v2 局部修复 6 条（双轨复核分歧，内部漏判、第三方抓到）→ v3 局部修复 6 条（双轨复核再次分歧，这次是两个独立第三方之间）→ v3.1 局部修复仅 5 条、且聚焦在更窄的语义闭环问题（结果态/归因链/竞态），不再触及架构层设计。每一轮复核发现的问题范围持续收窄、粒度持续变细，反映设计本身在收敛而非原地打转。
- **feedback-policy 探索条款适用性说明**：本次 v3 复核分歧属于 `feedback-policy.md`「补充条款：探索性否定结论」的适用范围——D1 是 RA-L3 关键设计决策之一，本次复核（含两轨分歧）是**有充分证据支撑的阶段性结论**（证据路径可追溯至 `.hopper/handoffs/T-007-output.md`、`.hopper/handoffs/T-008-output.md` 与设计 wiki `research/d1-v3-review.md`，结论基于实际复核产出而非臆测），按该条款应作为**正常迭代（探索成功的一种形式）处理，不计为 negative/失败**；不适用于协议执行故障（本次两轮 hopper 派发与设计 wiki 落盘过程本身均无执行故障）。

### RA-L3 D1 v3.1 聚焦复核决策（2026-07-21）

- **决策 D1（v3.1 阶段）— v3.1 spec 聚焦复核 REWORK，收敛中，不予确认**：RA-L3 议程 D1 的 v3.1 局部修订 spec（设计 wiki `kernel/d1-kernelport-spec-v3-1.md`，据 T-009 conformance spike 二次纠正 openclaw steer 精确语义 + §7 条件式归因）先经**主会话只读审查**，当时判为可通过（PASS）；随后按框架纪律追加**聚焦复核**（非重新双轨全审，单轨即可，因 v3.1 只是针对 T-008 5 findings 的局部修复，不是全新 spec）——codex（hopper 派发任务 T-010，`.hopper/handoffs/T-010-output.md`，**刻意选择**：v3.1 修复的 5 findings 正是 codex 自己在 T-008 提出的，由原提出者验证"是否真解 + 修复有无引入新矛盾"最有效，reasoning effort **xhigh**，只读）逐条核验后 Verdict **REWORK**，推翻了主会话只读审查的 PASS 判断。
- **核销结果**：1/5 findings 完全核销（Hermes CLI/ACP profile 断裂——§4.2/§5/§8 落地且忠实于事实基线）；4/5 部分修复但未闭环——①BLOCKER-1（OpenClaw steer 结果态）：hard/soft 拆分与 Hermes soft reject 已真实落地，但 soft 结果判定规则（无新 runId→succeeded 等）建立在 `chat.send` 是否返回 `queued/reason` **仍未确认**之上，把未确认信号当成契约分支；②BLOCKER-2（newapi §7 因果链）：token+按 token 查询的核心矛盾已改正，但 `SessionHandle.sessionId` 与 token 铸造时序仍未闭合、`attribution` 自诊断证据不足；③HIGH（审批 deny→abort→resend 失败分支）：三分支已加，但 deny RPC 失败引入的中间态没有名字/转移/重试规则，与保留的 v3 四态终态模型矛盾；④HIGH（session 锁+operationId/统一通道）：Promise 终态词汇表已加，但断线重放承诺与"事件不重放"的既有规则矛盾，锁矩阵不完整。另发现 **7 处新矛盾**（5 HIGH + 1 MEDIUM + 1 LOW）：`affectedRunId` 在合法 hard 路径上不可构造、hard partial failure 缺终态、operation 可观察性与事件不重放冲突、session 锁不是完整互斥矩阵、审批失败引入第五种未建模状态、billing attribution 证据不足、§10 统计自相矛盾。DEFER 复判中，`allow_session` 归一与 pending #2 由此前的可延后升级为"确认前必解"（HIGH）；soft `chat.send` 响应/结果信号复判为 **BLOCKER、不可 DEFER**——直接决定 `OperationOutcome` 是否真实。综合分析详见设计 wiki `research/d1-v31-review.md`。
- **方法论观察一——单轨放行、深轨抓，第三次出现**：本项目已三次出现"较浅核实方法放行、更深/异构方法抓到"的模式——v2 阶段内部 Sonnet 复核（同源、未做独立事实核查）放行、第三方 grok 抓到事实回退；v3 阶段第一轨 grok（核对字段/diff 是否落地）判 PASS_WITH_NOTE、第二轨 codex（追问断言是否自洽、新字段是否覆盖所有失败分支）判 REWORK 推翻；v3.1 阶段主会话只读审查判可通过、codex 聚焦复核（xhigh 推理强度）判 REWORK 推翻。本轮之新在于"较浅一方"从第三方 vendor 换成了**主会话本身的只读审查环节**——说明只读审查同样存在与 v3 阶段 grok-T-007 同构的系统性盲区（倾向于确认"改动确实存在"，不足以逐条推演"改动是否覆盖了所有运行时分支"），不能替代聚焦复核，聚焦复核这一步骤本身的必要性因此被再次证明。
- **方法论观察二——头号 BLOCKER 呈现新性质：live-probe-limited，设计迭代关不掉**：此前三轮（v1→v2、v2→v3、v3→v3.1）的 BLOCKER 均可通过"更多研究/更深源码调研 + 重新设计"化解——T-005/T-007/T-009 分别用官方文档核查、repo 级源码深挖收口了此前"未能确认"的事实缺口。但本轮头号 BLOCKER（soft `chat.send` 的 ack/`queued`/`reason` 与 runId 语义）不属于这一类：T-009 已做过 repo 级源码深挖，其 Open Questions 已明确写出"需一次 live probe"；T-010 独立复核后同样提出"能否通过 live probe 得到稳定、可机器判别信号"。两轮独立调研收敛到同一结论——**这个 BLOCKER 不能靠再读一次源码或再改一版 spec 关闭，只能靠真实调用 OpenClaw runtime 做一次 live probe**。这是本项目 D1 五轮迭代以来第一次出现"设计迭代本身无法收敛该 BLOCKER"的情况。
- **落盘处置**：设计 wiki `kernel/d1-kernelport-spec-v3-1.md` 的 `design_status` 已由 `draft` 改为 `superseded`（正文未删除，保留作 v3.2 修订基线与审计对照），顶部已加"经 codex T-010 REWORK，待 v3.2"说明段；综合复核结论见设计 wiki `research/d1-v31-review.md`；`goal-breakdown.md` RA-L3 议程表 D1 行状态标注同步更新为"D1 v3.1 聚焦复核 codex REWORK（收敛）→待 v3.2 路径决策"。
- **骨架五轮未倒的收敛趋势**：v1 全推倒重来（两轨双双否决，15+11 项 must-fix）→ v2 局部修复 6 条（双轨复核分歧，内部漏判、第三方抓到）→ v3 局部修复 6 条（双轨复核再次分歧，两个独立第三方之间）→ v3.1 局部修复 5 条（聚焦复核发现 1 未核销 BLOCKER 需 live probe + 4 部分修复 + 7 新矛盾）。5 轮迭代中，KernelPort 7 方法骨架、9→10 类 KernelEvent 判别联合、CapabilityDescriptor 定位、newapi 计费边车不进入调用路径这一整体架构从未被要求推倒重来——每轮问题范围持续收窄、粒度持续变细（从架构级互斥 → 事实回退 → 语义闭环 → 现在的可观察性边角与 live-probe-limited blocker），反映设计本身在收敛，而不是原地打转，但也尚未达到可升 `confirmed` 的门槛。
- **v3.2 三路径待用户定**：①**诚实收窄路径**——不做 live probe，直接收窄 `OperationOutcome` 公开契约（承认 soft steer 结果不可靠判定，对外只暴露"已尝试"而非三态区分），代价是产品能力表达变弱但可立即推进；②**live probe 路径**——实际调用 OpenClaw runtime 做一次探针，观察 `chat.send + queueMode:"steer"` 的真实响应体后再钉死契约，代价是需要真实环境与执行时间，且是本项目 D1 迭代以来第一次需要"跳出纯规格设计"的步骤；③**两路径结合**——先按①诚实收窄发布 v3.2 使其可评估为 confirmed 候选，同时并行安排 live probe，probe 结果证实更强的三态信号后再发 v3.3 恢复完整表达。三条路径均不需要推倒 KernelPort 现有骨架。下一步：待用户在三条路径间决定，决定后再驱动 v3.2 起草。
- **feedback-policy 探索条款适用性说明**：本次 v3.1 聚焦复核结论（含推翻主会话只读审查 PASS 判断）属于 `feedback-policy.md`「补充条款：探索性否定结论」的适用范围——D1 是 RA-L3 关键设计决策之一，本次复核是**有充分证据支撑的阶段性结论**（证据路径可追溯至 `.hopper/handoffs/T-010-output.md`、`.hopper/handoffs/T-009-output.md` 与设计 wiki `research/d1-v31-review.md`，结论基于实际复核产出而非臆测），按该条款应作为**正常迭代（探索成功的一种形式）处理，不计为 negative/失败**；主会话只读审查的误判本身计入「方法论观察一」作为框架纪律教训记录，不视为协议执行故障（本次 hopper 派发与设计 wiki 落盘过程本身无执行故障）。

### RA-L3 D1 正式定稿（2026-07-21）

- **①最终状态 — D1 KernelPort v3.4 design_status: confirmed，正式定稿**：RA-L3 议程 D1（内核抽象接口规格）的最终 gate——codex **T-013** confirm-readiness gate（`.hopper/handoffs/T-013-output.md`，接续 T-012，刻意沿用 codex：T-012 点名的 3 处残留由同一评审方终验最有效，定向核验 v3.4 收尾的 3 处机械级残留是否真闭合、有无引入新矛盾，只读）Verdict **PASS(CONFIRMABLE)**：6/6 核验项全部通过——§9.3 soft steer 严格二态与 §6.1(a) 自洽（`stop()` 等待超时归为 `stop()` 自身的 `timed_out`，不是 steer 第三终态）、`queryBilling` 同步/异步失败通道分层唯一确定（`billing_query_subject_unresolved` 已移出同步 `KernelPortRejectionCode`，改列该方法专属的异步 Promise rejection）、§3 事件计数"十类"与 INV-2/§6.1a/§9.2/§16 全文口径一致，三处均闭合且未引入任务范围内的新矛盾。用户据此确认**正式定稿**：设计 wiki `kernel/d1-kernelport-spec-v3-4.md` 的 `design_status` 已由 `draft` 改为 `confirmed`（标题下方新增定稿标注段，注明 T-013 PASS(CONFIRMABLE) 与 §11 五个 C-item 结转实现阶段），`goal-breakdown.md` RA-L3 议程表 D1 行状态同步为 **done/confirmed（v3.4 定稿基线）**。
- **②完整弧摘要（v1→v3.4，五版九轮一 spike 收敛）**：v1（首版正式 spec）经双轨对抗评审（codex T-004 REWORK/15 findings/5 BLOCKER × 内部 Sonnet negative/11 must-fix）**双双否决** → **rework 决策**：scope 收窄为 openclaw+hermes，先做 D1-spike（T-005，conformance 补事实）再重设计 → v2（scope 收窄后重设计）经双轨复核**分歧**（grok T-006 REWORK × 内部 Sonnet positive-可小修），第三方抓到内部漏判的**事实回退**（openclaw 原生 `sessions.steer` 被 v2 误当不存在）→ v3（局部修复 6 条）经双轨复核（grok T-007 **PASS_WITH_NOTE** × codex T-008 **REWORK**，**异构第二轨推翻第一轨 PASS**）→ D1-spike2（T-009，repo 级源码深挖二次纠正 steer 精确语义 + §7 归因链）→ v3.1（局部修复 5 条）经 codex T-010 聚焦复核 **REWORK**（1/5 完全核销、4/5 部分修复未闭环，头号 BLOCKER 定性为 **live-probe-limited**、设计迭代本身无法收敛）→ v3.2（**诚实收窄**，非新调研，新增 §11 C-item 清单 C-1~C-5）经 codex T-011 confirm-readiness gate **MUST-FIX**（M1-M5，均设计文本内可关、无需 spike）→ v3.3（最小闭合修订，仅关 M1-M5）经 codex T-012 定向重跑 **MUST-FIX**（本轮新增文字自身产生 3 处机械级新矛盾）→ v3.4（收尾微修，仅关 T-012 点名 3 处）经 codex **T-013 最终 gate PASS(CONFIRMABLE)**，正式定稿。全弧共 **5 版 9 轮 1 spike 收敛**：5 个正式版本节点（v1/v2/v3/v3.1→v3.2→v3.3→v3.4 一脉局部收敛为定稿基线）、9 轮对抗/聚焦/confirm-readiness 评审（T-004/T-006/T-007/T-008/T-010/T-011/T-012/T-013 + 1 次独立内部 Sonnet 评审）、1 次源码级 conformance spike（T-009；T-005 为一般事实调研，非源码级 spike）。详见设计 wiki `research/d1-review-dual-track.md`、`research/d1-v2-review-dual-track.md`、`research/d1-v3-review.md`、`research/d1-v31-review.md` 及本节以上各「RA-L3 D1 ... 决策」小节。
- **③三条方法论产出**：
  - **异构第二眼推翻第一眼**：v3 阶段两个独立第三方 vendor 之间出现分歧——grok T-007 判 PASS_WITH_NOTE，codex T-008（异构第二轨，不预设 grok 结论）判 REWORK 并直接推翻；v3.1 阶段同构再现——codex T-010（聚焦复核）推翻了主会话只读审查给出的 PASS 判断。两次分歧证明单轨/单眼评审（即便有官方文档支撑）不能被视为终局，尤其在"断言内部自洽性""新字段是否覆盖所有失败/竞态分支"这类深层缺陷上，往往只有更深或更异构的第二眼才能抓到。
  - **诚实收窄**：v3.2 阶段面对被两轮独立调研（T-009 repo 级源码深挖、T-010 聚焦复核）共同判定为 **live-probe-limited**（无法靠再研究/再设计关闭）的头号 BLOCKER（soft `chat.send` ack 精确语义），放弃继续推倒重设计，转为把建立在未确认信号上的契约分支显式**收窄**到可靠子集（三态→二态）、并将无法在设计阶段确认的事实缺口登记为 §11 C-item（注明为何设计阶段关不掉/实现阶段如何验/不成立时如何降级）。这一动作是让 D1 从"迭代五轮仍在收敛"变成"可定稿"的关键机制：定稿不等于事实全部确认，而是未确认之处已被诚实挂牌且契约行为良定义。
  - **评审强度按决策关键性分级**：D1（核心内核抽象架构决策）全程采用最高强度——双轨对抗评审 → 异构第二轨 → 聚焦复核 → confirm-readiness gate 逐级加严直至 codex 终验（T-013），耗费 9 轮评审 + 1 次源码 spike 方才收敛定稿；相较之下，用户已为 D2（消息 schema 规格，屏障层设计，架构杠杆效应低于 D1）预定明显更低的强度（见下④），体现评审资源应按该决策对整体架构的影响面分级投入，而非对 RA-L3 全部 7 项决策一视同仁地套用 D1 级别的加严流程。
- **④D2 决策待启（评审强度已定，起草暂停）**：用户已确定 **D2（消息 schema 规格）评审强度为「中等：起草+双轨一次（grok+codex）」**——即 D2 起草完成后只需一轮双轨对抗评审（grok+codex）即可进入用户确认决策，不套用 D1 历经的"聚焦复核→confirm-readiness gate 逐级加严直至终验"多轮收敛流程。**但 D2 目前暂停**：本节仅落盘该强度决策本身，D2 起草尚未启动，待用户下一步明确 go-ahead 后再行发起。
- **⑤5 个 C-item 清单结转实现阶段（源设计 wiki §11，v3.2 新增，v3.3/v3.4 未改写正文，仅同步措辞）**：
  - **C-1** soft `chat.send`+`queueMode:"steer"` 的精确 ack/结果信号语义（是否回传 `queued`/`reason`；成功注入与静默降级是否可机器区分）——实现阶段需一次 live probe：起本机 openclaw gateway 实例，构造有 active run 的 session，比对三种场景响应体差异
  - **C-2** operation 是否需要持久化账本（ledger），支撑断线重连/审计场景按 `operationId` 查询历史终态——实现团队架构决策，不做则 `OperationCompletedEvent` 仅对在线订阅者保证的行为已是显式契约，无需额外降级
  - **C-3** openclaw/hermes 是否支持 per-session 换模型出口 key/baseUrl（§7 注入链契约可行性前提）——需在目标部署环境实操验证；不可行则 `billingAttribution` 声明为 `'user_tenant_aggregate'`，走已定义的聚合降级路径
  - **C-4** openclaw `sessions.steer` abort 成功但 `chat.send` 失败时，error 响应是否透出 `interruptedActiveRun`（决定 `aborted_resend_failed` 在 openclaw 侧能否被可靠构造）——不透出则统一上报 `aborted_effect_unknown`，不得猜测性上报 `aborted_resend_failed`
  - **C-5** hermes ACP 是否具备任何形式的同 run 软注入机制——非阻塞性验证项，未验证或确认不存在时，`interruptModes` 对 hermes 维持不含 `'steer'` 的保守默认值
  
  五项均已在 spec §11 注明验证方法与不成立时的降级路径，本次定稿不改写清单本身，进入实现阶段后须逐条验证并记录结果，验证结果不阻塞本次定稿判断。

## Non-Goals

- 不承诺生产级上线或商业化——本 goal 是探索性实验，失败与成功皆为可接受的结果
- 需求分析阶段不跳级展开——须逐级（RA-L1 → RA-L2 → RA-L3 → RA-L4）用户确认后再进入下一级
- 不在需求达 dev-ready 前进入编码——dev 分解推迟至 dev-readiness gate 后注入（见 goal-breakdown.md）
- 不自研 LLM
- 插件（harnessloop/hopper/kata）的进化仅由本 goal 的实战需求驱动，不做推测性功能开发

## Success Condition

本 goal 为探索性 goal，成功定义为「探索定义」：以下三项皆有落盘证据即视为成功（包括证据充分的失败/否定结论）。

1. **可行性结论**（含失败分析亦可）
2. **插件进化**——≥ 5 项由本 goal 实战触发的改进发布至上游三插件（沿用 TH-xxxx 编号与版本发布留痕惯例）
3. **内容连载**——≥ 3 篇里程碑文章成稿至 PR wiki `drafts/`

**近期里程碑**：需求设计逐级展开至 dev-readiness 并经用户签署，届时再次执行 `$harnessloop-goal update` 注入 dev 子目标。当前阶段仅做需求分析，不做编码。

## Acceptance Criteria

| Criterion | Evidence required | Verification method | Human confirmation required |
| --- | --- | --- | --- |
| 1. RA-L1 顶层域（七支柱）结构经用户确认 | goal-breakdown.md RA-L1 表 + 用户确认记录 | 用户逐级确认门 | 是 |
| 2. RA-L2 各支柱展开逐一经用户确认 | 各支柱展开文档 + 用户确认记录 | 用户逐级确认门（每支柱一轮） | 是 |
| 3. RA-L3 关键设计决策与技术选型经用户确认（server 完整调研 / 内核抽象接口设计 / 消息流屏障设计 / Mac→Windows 跟随开发机制设计 / 仿 codex app 产品规格） | 调研文档 + 设计决策记录 | 对抗性设计评审 + 用户确认技术选型 | 是 |
| 4. 需求规格成型并达 dev-readiness，用户签署 | dev-readiness 规格文档 + 用户签署记录 | 用户签署门 | 是 |
| 5. 插件进化 ≥ 5 项发布（横切，不受需求分析进度阻塞） | 各插件版本发布记录（TH-xxxx 编号） | 与插件仓库/CHANGELOG 比对 | 否 |
| 6. 里程碑文章 ≥ 3 篇成稿至 PR wiki `drafts/`（横切） | ≥ 3 篇文章成稿文件 | 用户发布确认 | 是 |

## Required Human Decisions

- 每一级需求展开的确认（逐级门）
- 技术选型确认
- dev-readiness 签署
- 每篇连载发布确认

## Source Of Truth

本 goal.md 的 user-specified 段（Goal / 业务技术要点 / 技术栈偏好与约束 三节，2026-07-18 用户重定）+ 本轮及后续 AskUserQuestion 留痕。

| Document or system | Path or URL | Trust level | Last verified |
| --- | --- | --- | --- |
| 用户业务与技术栈重定指令 | 本 `goal.md`（Goal / 业务技术要点 / 技术栈偏好与约束 三节） | 权威（source-of-truth 锁定） | 2026-07-18 |
| RA-L1 确认与三项决策（七支柱确认 / L2 展开顺序 / 仿照 codex app 边界） | 本 `goal.md`（RA-L1 确认与决策节）+ `goal-breakdown.md`（L1 七支柱表 confirmed / RA-L2 首轮范围） | 权威（source-of-truth 锁定） | 2026-07-18 |
| RA-L2 架构核心确认 + 架构决策 X1/X2（本地内核优先 / 统一经 newapi） | 本 `goal.md`（RA-L2 确认与架构决策节）+ `goal-breakdown.md`（RA-L2 confirmed / RA-L3 七项议程 D1-D7） | 权威（source-of-truth 锁定） | 2026-07-18 |
| RA-L3 D3 确认（Server 技术选型 = TypeScript+NestJS+PostgreSQL） | 本 `goal.md`（RA-L3 D3 确认与决策节）+ `goal-breakdown.md`（RA-L3 议程表 D3 confirmed）+ `.hopper/handoffs/T-002-output.md`（T-002 grok 研究） | 权威（source-of-truth 锁定） | 2026-07-21 |
| AskUserQuestion 留痕（本轮及后续逐级确认） | 会话内留痕，逐级确认发生时冻结 | 权威 | 随逐级确认更新 |

## Status

**proposed（2026-07-18，material change：业务与技术栈重定）**

本 goal 处于 propose 阶段，当前子阶段为需求分析（Requirement Analysis）。五份契约文件（本文件 + goal-breakdown.md + thresholds.md + data-contract.md + feedback-policy.md）已按新业务身份重写落盘，无 `rounds/` 目录、无执行轮。dev 分解明确推迟至需求达 dev-ready 并经用户签署后注入（届时再次执行 `$harnessloop-goal update`）。RA-L1 顶层域结构（七支柱 P1–P7）已经用户 2026-07-18 确认（见 goal-breakdown.md「L1 七支柱」表，状态 confirmed）。RA-L2 首轮（架构核心 P1-P3）已经用户 2026-07-18 确认（见上「RA-L2 确认与架构决策」节），并同步锁定两项架构级决策 X1（本地内核优先）/ X2（统一经 newapi），server 由此收敛为瘦业务控制面。下一步：RA-L3 议程（7 项决策 D1-D7，见 goal-breakdown.md）确认中，pending 用户确认。
