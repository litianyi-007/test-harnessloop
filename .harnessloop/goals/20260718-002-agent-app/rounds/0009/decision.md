# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0009（SG-8 验收清单收尾批次，SG-8.1/8.2/8.3/8.4①②，双轨探针，已达成）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-26

## Reason

rounds/0009 的验收边界由 scope-lock 明确为一件事：把首批 SG 最后悬着的 SG-8 验收清单收尾批（SG-8.1/SG-8.2/SG-8.3/SG-8.4①②）一次跑通探针拿到证据——全部为探针/验证型工作（跑真实内核收证据，不写产品代码），两内核两侧相互独立，并行双子代理执行（轨 A=openclaw、轨 B=hermes）。SG-8.4③（hermes ACP kernel-client 适配器）因需新写实现级代码，scope-lock 事先明确 defer，不入本轮。执行结果：

- **轨 A（openclaw 侧）**：SG-8.1 四项——①③引用 rounds/0004 强证据 + 本轮轻量复证 pass；②sessionId 逐字节同源（5 处两两相等）pass；**④按措辞纪律拆两层：映射层 pass（真实 mint HTTP 端点仍 501，源码 `newapi-client.service.ts:53-63` `NotImplementedException` 坐实；探针走源码文档化的开发期 `upsert` 路径达成 `revokedAt IS NULL`+`findActive` 命中，被真实转发交叉印证）+ mint HTTP residual（501 未解除，非本轮新发现，结转 D3 业务面第二批）**。SG-8.3 PRE-1(C-1) 三场景响应体差异表 pass，**发现②**：`chat.send` ack 在 steer-注入 vs 空闲新 run 结构完全相同（均 `{runId,status:"started"}`，无区分字段）——D1 §11 C-1 关心的"ack 层机器可区分性"答案为否。SG-8.3 PRE-3(C-4) pass，**发现③**：abort 成功但 resend 失败时不透出 `interruptedActiveRun`（`sessions-messaging.ts:379-389` 三元仅 `ok===true` 拼接，无条件代码事实）。SG-8.4①：新写 Swift 探针入口抓 4 条真实 D2 事件 Ajv 全过，**发现⑤**：`validate-schemas.mjs` 从未真正对实例调用 validator（只编译），探针内已验证可行的 dereference 工作流。SG-8.4②：握手 protocolVersion 单传+不重复（5 次一致）pass；回填重建子项因 `capabilities()`/`capability_changed` 均既有 TODO 桩，如实 defer。
- **轨 B（hermes 侧）**：SG-8.2——D1 指定的 `/api/log/self` 需 cookie 会话不可用 token；**真实等价 `/api/log/token`+Bearer**（同时修正 T-005 早期推断），互验 A/B 各只见己方数据、对抗注入被忽略，零串号，零新 Kimi 调用，PASS。SG-8.3 PRE-7——**发现④**：hermes session/load 在 `provider:auto`+自定义端点下 100% 复现静默失败伪装成功（`session.py:551/651`→`runtime_provider.py:1169`→`server.py:1140-1143`，provider 标签回写 openrouter 后下次冷加载崩溃被吞成 `None`），比 PRE-1 §1.7 猜测的"部分丢失"更严重（零复原+看起来像成功）——上游 hermes bug 候选 + conformance 修正候选，不影响 SG-7 api_server 路径结论。config-only 绕开（`provider:custom`）后 20/20 条、0.79-0.82s（≪10s 阈值）、3/3 一致 → **PASS（带前提）**。hermes-steer 冒烟：与 D1 v3.6 零矛盾，抓到"submitted 不保证实际注入"caveat 的活体实例（steer ack 0.002s 返回但因主 turn 无工具调用挂载点未进最终答案），field_meta/user_message_id 均 None 印证 v3.6-r1，PASS。

**★审查闸（hopper 派 grok，T-057，证伪式对抗审）Verdict = PASS_WITH_NOTE**：五项重点逐条过源码/git，未发现把失败粉饰为 pass、也未发现 file:line 明显误读；发现②③④⑤ 均可在源码坐实、未夸大；PRE-7 阈值数据支持 pass 但严格以 `provider:custom` 为前提；零改动核验（两 submodule + `app/`）本机复验通过。**NOTE（已采纳，本决策文档与 round-summary 均按此措辞落笔）**：①SG-8.1④ 不得写成"mint 成功/501 解除"，须拆两层——映射层 pass、HTTP mint 端点 stub 残留须作 residual 进入收官；②PRE-7 PASS 须与 `provider:auto` 静默失败 bug 同读，不可剥离前置条件单独引用 PASS。若不采纳该 NOTE、把 SG-8.1 写成无保留 full pass，grok 判定应降为 REWORK（文档/措辞级，非证据造假级 FAIL）——本轮已采纳，未触发 REWORK。

**主会话零改动核验（收官亲验）**：hermes 全空（tracked/untracked/ignored/diff --stat 均空，pin 未漂移）；openclaw tracked diff 空、唯一 untracked 为会话前既有的全局 git-ai hook（非本轮产物）、ignored 全为既有 `.gitignore` 命中的构建产物；隔离进程/端口全部清理；用户全局 gateway（18789/PID 5197）未受扰；Pi 测试映射行已清理。

证据充分（双轨探针完整交付 + 5 处发现全部源码坐实 + PRE-7 阈值数据支持 + 零改动双查核验通过）且收敛（★审查闸一次即 PASS_WITH_NOTE，唯一 NOTE 已在收官文案中采纳，0 次 REWORK，未达阈值 3），故本轮 feedback 分类 **positive**。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-8 主体收官——首批 SG（SG-1..SG-9）全部主体达成**：SG-8.1（①②③ pass；④映射层 pass + mint HTTP residual，按措辞纪律拆层）、SG-8.2（done，含 `/api/log/self`→`/api/log/token` 验法修正）、SG-8.3（done，含发现②③④与 PRE-7 阈值判定）、SG-8.4（①done；②连接级子项 done + 回填重建子项 defer；③非本轮 scope，scope-lock 事先 defer）、SG-8.5/8.6/8.7 此前已 done——SG-8 由 pending 转为**主体 done**。至此 SG-1 至 SG-9 全部子目标均已主体达成（各自的 residual/defer 均如实标注，非静默略过），是本项目"每个 SG 逐个走 round 闭环"这一既定纪律自 rounds/0002 起首次完整兑现到全部首批子目标的收官节点。
- **措辞纪律的价值再次坐实**：grok T-057 的核心贡献不是发现新缺陷，而是纠正判定诚实性——SG-8.1④ 的探针本身完全合格（映射层证据充分），但汇总层"pass"措辞若不拆层会让收官读者误判 mint e2e 已通。这与本项目历轮反复观察到的"审查者独立佐证挖掘/纠正判定诚实性"模式一致（T-055 挖 state.db 佐证、T-050 揪表面绕过等），本轮的焦点从"结论是否成立"进一步收窄到"措辞宽窄是否诚实"，是审查机制成熟度的一个新维度。
- **双轨并行方法论首次验证**：本轮是本项目首次对两个独立内核采用并行子代理探针，wall-clock 大致减半、且两轨证据零交叉污染、零冲突合并问题，值得作为后续多内核/多组件探针批的默认执行模式。
- **探针批的发现密度**：5 处发现（②③④⑤ + PRE-7 阈值判定本身）里，2 个是 openclaw 既有行为的 conformance 实况坐实（②③）、1 个是 hermes 真实 bug（④）、1 个是 D3 已知 stub 缺口的再确认（mint 501）、1 个是断言基建缺口（⑤，`validate-schemas.mjs`）——延续本项目"runtime 探针不可被源码核验替代"的方法论观察（第 3 次同类验证，前两次分别是 rounds/0004 SG-8.5 揪出 openclaw 2 处真实 bug、rounds/0006 揪出 SG-5 `stop()` D1 §6.2 缺口）。
- **residual/defer 显式清单（本轮裁定，供第二批 SG 规划参照）**：
  - **mint HTTP 501 未解除**（`newapi_token_id_lookup_unresolved`）→ 结转 **D3 业务面（第二批）**。
  - **SG-8.4②回填重建子项**（protocolVersion 从事件回填重建 `CapabilityDescriptorPayload`）→ 待 `capabilities()`（`OpenclawGatewayKernelClient.swift:808-810`）/`evt.capability_changed`（`EventMapping.swift:701-722`）两处既有 TODO 桩解除后，才具备可探针条件。
  - **SG-8.4③ hermes ACP kernel-client 适配器**（需新写 `createSession`/`subscribe` 闭环）→ **第二批 SG 候选**。
  - **hermes ACP provider-relabel 静默失败 bug（发现④）** → 上游 hermes bug 候选 + conformance 修正候选，部署建议默认 `provider:custom`。
  - **`validate-schemas.mjs` 实例校验缺口（发现⑤）** → 建议后续轮次补进正式 codegen/parity 基建，探针内已验证工作流可直接复用。
- **下一步待选（第二批 SG 规划）**：**Mac app UI 壳**（D5 产品 UI 细节）/ **D3 server 业务面**（含 mint HTTP 501 解除）/ **hermes ACP kernel-client 适配器**（SG-8.4③）/ **Stage C 产品行为 parity 结转**（D4 §4.6，rounds/0006 结转项）/ 两个 rounds/0007 defer 项修复轮（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计裁决）/ **conformance 修正批**（本轮发现②③④⑤ + T-005/T-009/PRE-1 早期推断修正）/ hopper `||` 表格观察点处理。**规划本身属 goal 级决策，需用户参与。**

## Open Questions Resolved

- **D1 §11 C-1「ack 层是否可机器区分注入成功 vs 静默降级」**：本轮证实——`chat.send` 即时 ack（`{runId,status:"started"}`）不携带任何注入结果信号，A（活跃 run 注入）与 C（空闲新开 run）场景响应体结构完全相同，答案为**否**；要区分只能靠外部信号（如调用前先查 `session.hasActiveRun`）。
- **D1 §11 C-4「abort 成功但 resend 失败时是否透出 `interruptedActiveRun`」**：本轮证实——**不透出**，源码级无条件代码事实（`sessions-messaging.ts:379-389`），支持继续维持 D1 既定"不透出则统一上报 `aborted_effect_unknown`"的保守默认，不触发契约修订。
- **PRE-7「hermes ACP session/load 历史 replay 可靠性阈值」**：本轮判定 **PASS（有条件）**——≥20 条不丢顺序保持、≤10s（实测 0.79-0.82s）、3 次一致三项全达，但**前提是规避了发现④记录的 `provider:auto` relabel 静默失败 bug**；若不做该配置层规避，判定会是 FAIL（0/20）。
- **D1 §11 C-3「hermes per-session token 归因是否可通过 self-query 互验不串号」**：本轮证实——**互查不串号成立**，但 D1 原文指定的 `/api/log/self?token_name=...` 验法本身不可行（user-session 鉴权），真实可用的等价验法是 `/api/log/token`+Bearer；已如实修正。
- **SG-8.4②「protocolVersion 握手期单传→事件回填重建 round-trip」的连接级半条**：本轮证实——5 次独立握手协议版本值全部一致（`4`），事件帧从不重复携带 protocol 字段，"握手期单传、不重复"在本轮环境下经验成立。

## Open Questions Deferred

- **mint HTTP 端点 501 解除**：真实业务路径的 newapi token id 反查机制未闭合（`newapi_token_id_lookup_unresolved`），非本轮 scope，结转 D3 业务面第二批。
- **SG-8.4②回填重建子项**：`capabilities()`/`evt.capability_changed` 在 kernel-client 侧均是既有 TODO 桩，机制本身未实现，待其落地后可重新排期。
- **SG-8.4③ hermes ACP kernel-client 适配器**：scope-lock 事先明确 defer（需新写实现级代码），候选第二批 SG，本轮未走。
- **hermes ACP provider-relabel 静默失败 bug（发现④）的上游处置**：是否 push 补丁给 hermes 上游或另开 issue，留待后续决策，非本轮阻断。
- **`validate-schemas.mjs` 实例校验缺口（发现⑤）的正式修复**：留待后续轮次补进正式 codegen/parity 基建，非本轮 scope。
- **openclaw ack 层不可区分（发现②）/interruptedActiveRun 不透出（发现③）的产品/契约层面处置**：是否需要额外状态查询或事件观察机制来满足未来产品需求，留待后续设计决策，非本轮阻断。
- **T-005/T-009/PRE-1 早期推断的多处 runtime 修正批量整理**：new-api `/api/log/token` 鉴权/`id` 字段语义修正（本轮）、`GET /api/token/:id` 掩码 key 修正（rounds/0008）、PRE-1 §1.7 严重度低估修正（本轮），建议归入 conformance 修正批统一处理，留待后续轮次。
- **两个 rounds/0007 defer 项**（TS `EmptyPayload` 精度缺陷修复方案 / 解码边界是否需要 strict-decode）：延续既有 deferred 状态，本轮未触碰。
- **hopper `||` 表格解析观察点是否升级为 evolution issue**：延续 rounds/0007/0008 记录，留待主会话/用户后续决定。
- **第二批 SG 规划本身**：属 goal 级决策，需用户参与，本轮不擅自裁定方向。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E20 | `rounds/0009/evidence/track-a-openclaw.md` + `track-b-hermes.md` | SG-8 主体收官的直接依据：双轨探针完整交付（SG-8.1①②③④/SG-8.2/SG-8.3 PRE-1/PRE-3/PRE-7+steer 冒烟/SG-8.4①②）+ 5 处发现（②③④⑤，均 file:line 坐实）+ PRE-7 阈值数据 + hopper T-057 证伪式对抗审 PASS_WITH_NOTE + 主会话零改动亲验 |
| E19 | `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md` + `HERMES-RUN-EVIDENCE.md` | rounds/0008 SG-7 交付物，本轮 SG-8.2/PRE-7 复用其隔离环境与既有 token（id=4/5）/计费记录，未新调 Kimi |
| E14 | `app/server`（D3-proxy）+ `kernels/openclaw` 补丁 `4ddcb52`/`35f8739` | SG-8.1①③既有强证据引用来源，本轮轻量复证的对照基线 |
| E11 | `~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md` + `pre1-hermes-source-conformance.md` | PRE-① 原始 claim 与 §1.7 replay 可靠性猜测的权威来源，本轮 SG-8.3 PRE-7 探针即对 §1.7 的 runtime 检验对象 |

## Next Action

- Action type: 收盘 → 首批 SG 全清宣告 → 待用户参与的第二批 SG 规划
- Scope-lock required: yes（第二批 SG 或任一候选方向开 round 时新建 scope-lock）
- Human confirmation required: 是（第二批 SG 规划方向属 goal 级决策，需用户参与选定；本轮收盘本身不需要用户进一步确认）
- Safe without user input: yes（本轮收盘、SG-8 主体 done、首批 SG 全清宣告均不需要用户进一步确认）；下一步一旦选定方向并启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 待用户参与确定第二批 SG 方向（候选：Mac app UI 壳 / D3 server 业务面[含 mint HTTP 501 解除] / hermes ACP kernel-client 适配器[SG-8.4③] / Stage C 产品行为 parity 结转 / 两个 rounds/0007 defer 项修复轮 / conformance 修正批 / hopper `||` 表格观察点）后，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 SG-8.1④ 表述为"mint 成功/501 已解除"（映射层 pass，HTTP mint 仍 501 residual）；不得把 SG-8.4②表述为完整 done（连接级子项 done，回填重建子项 defer）；不得把 SG-8.4③表述为已完成（scope-lock 事先 defer，非本轮 scope）；不得未经用户参与就擅自裁定第二批 SG 方向并直接开工
