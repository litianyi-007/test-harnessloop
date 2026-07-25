# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0010（SG-11 conformance 修正批——第二批首轮，轻量文档修订：把 rounds/0008/0009 的 runtime 发现与 T-005/T-009 早期推断修正回写进 design wiki，让 conformance/设计文档重新与 runtime 实况对齐；第六次完整走 continue 驱动 + 关键节点独立审查机制）
- Scope-lock: rounds/0010/scope-lock.md（v1）
- Started: 2026-07-26
- Completed: 2026-07-26

## What Changed

本轮把 rounds/0009（SG-8 收尾批双轨探针）与 rounds/0008 积累的 5 处 runtime 发现（②③④⑤ + D3 mint 501 再确认）以及 T-005/T-009 早期推断修正，**回写进 design wiki**（`~/.llm-wiki/agent-app-design`，独立 git 仓）——目的是让 conformance/设计文档重新对齐 runtime 实况，后续 SG-10 Mac UI 壳等开发建立在修正过的事实上。**本轮不改任何协议契约语义**（D1/D2/D5 契约文本零改动）。

写码/写文档派 claude-sonnet-5 子代理完成，交付 wiki 仓 commit **`da764f8`**（主体，4 文件、+314/-12）+ **`2ee61d2b`**（收残一处引文多余右花括号）：

1. **openclaw ack 层不可区分**（发现②）：`chat.send` ack 在 steer-注入活跃 run 与空闲新开 run 两场景下结构完全相同（均 `{runId, status:"started"}`，无 `messageSeq`/`queued`/`reason` 等可区分字段）——D1 §11 C-1 的决定性答案为**否**，源码坐实 `chat-send-handler.ts:270-288` 该 ack 在任何模型调用发起前同步返回。回写落点：`research/pre1-openclaw-source-conformance.md` 新 §4 + `kernel/kernel-ecosystem-facts.md` §7 新增「事实④」。**C-1 触发的是 D1 §11 自身预写的既有规则确认分支（"不可区分则维持二态不变"）**，不构成新增语义。
2. **`interruptedActiveRun` 失败路径不透出**（发现③）：abort 成功但 resend 因空消息校验失败时，返回体不透出 `interruptedActiveRun`——`sessions-messaging.ts:379-389` 三元表达式仅在 `ok===true` 真分支拼接该字段，是对所有失败态成立的无条件代码事实，支持维持 D1 既定"不透出则上报 `aborted_effect_unknown`"的保守默认。回写落点：`research/pre1-openclaw-source-conformance.md` 新 §5 + `kernel-ecosystem-facts.md` §7 新增「事实⑤」。
3. **hermes `session/load` 静默失败根因链**（发现④）：`model.provider:auto`+自定义 base_url、未配置真实 `OPENROUTER_API_KEY` 场景下，`session/load` 首次成功后此后 100% 复现静默返回 0 条历史，比 §1.7 原猜测的"部分丢失"更严重（是"零复原"且"看起来像成功"）——`session.py:551/651`→`runtime_provider.py:1169`→`server.py:1140-1143` 完整根因链回写；同时附 **PRE-7 阈值结论**（20/20 条、0.792/0.815/0.803s、3/3 一致，`provider:custom` 前提，前提不可剥离单独引用 PASS）+ **§4.3 上游处置建议段**（报 hermes 上游 issue 的草案要点 vs 不报理由并列，中立呈现，决策留给用户）。回写落点：`research/pre1-hermes-source-conformance.md` §1.7 postscript + §0 汇总表注记 + 新 §4。
4. **new-api 两处 API 实况修正**：① `GET /api/token/:id` 实测仅返回掩码 key（T-009 N2"返回明文 `{key: fullKey}`"推断在目标实例上不成立）；② `/api/log/token` 真实鉴权机制是 `Authorization: Bearer <token>` header（T-005 C2 记录的裸 `?key=` 查询参数在目标实例上返回 `"Token not provided"`）。回写落点：`architecture/d6-newapi-integration.md` 新增 v4 conformance 修正 blockquote + §4.1 两处行内修正。
5. **D3 mint HTTP 501 residual 再确认**：真实业务 mint 端点（`POST /sessions/:sessionId/billing-token`）在 rounds/0009 SG-8.1④ 探针中再次复现确认仍为 501（`newapi_token_id_lookup_unresolved`）——非新发现，是对既有登记状态的再确认；映射层（源码文档化的开发期 `upsert`/`findActive` 路径）可用，但不构成对本行反查缺口的解除，措辞纪律采纳 T-057 意见不得等同"mint 成功/501 解除"。回写落点：`d6-newapi-integration.md` §7 #11 行内附注。
6. **validate-schemas 未验实例**（发现⑤）：检索 `~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`（D4 codegen/金标 parity 相关全部章节）与 `kernel-ecosystem-facts.md`，均未发现"`validate-schemas.mjs` 已对实例做校验"或等价断言——**wiki 无落点，wiki 不改**，如实记录于修正对照表（唯一记载）。
7. 每处修正带**修订标注**（wiki 既有惯例：blockquote changelog/revise 注记 + frontmatter `updated`/`sources` 追加，引用 rounds/0009 evidence 与 T-055/T-057 出处）；产出**修正对照表** `rounds/0010/evidence/correction-table.md`（105 行，7 项修正逐条：旧表述→新事实→证据出处→落点 file:line + 红线自查）。

**主会话独立复验**：wiki diff（`git -C ~/.llm-wiki/agent-app-design show --stat da764f8`）确认仅 4 个 Allowed 文件改动；`kernel/d1-kernelport-spec-v3-6.md`/`d2-message-schema-v3.md`/D5 文件 diff 均为空，未触碰契约文本。

**★审查闸（hopper 派 codex，T-060，单人验收审，只验四件事：修正忠实性/无契约语义夹带/修订标注与上游建议中立性/无落点判定可信度）Verdict = MUST-FIX**：7 项主体事实全部确认成立（无漂移、无粉饰、无语义夹带、上游建议中立、无落点判定可信）；C-1/C-4 落 D1 §11 预写分支的判断经核实成立（D1 §11:817/820 已预写对应确认规则）；4 文件 frontmatter `updated` 全部由 `2026-07-22` 更新到 `2026-07-26`，出处引用齐全；Hermes §4.3 上游建议先列报告草案要点再列不报理由，未见倾向性夹带。**MUST-FIX 仅 2 处机械精度问题**（非事实性错误）：①修正对照表第 3 项引用了父提交（da764f8 之前版本）的旧行号 `L103`/`L34`，`da764f8` 提交后实际行号已变为 `L112`/`L43`；②new-api 修正段落引文多写了一个右花括号（`{key: fullKey}}` 应为 `{key: fullKey}`）。

**处方级收残**：主会话照 codex 处方逐条修正——对照表行号更新为 `L112`/`L43`/`L263-304`（已复核对应当前 commit 的实际行位），d6-newapi-integration.md 与对照表内的多余花括号均已删除（commit `2ee61d2b`）；用 codex 报告中给出的复现命令（`nl -ba research/pre1-hermes-source-conformance.md`、`git show da764f8^:architecture/d6-newapi-integration.md | nl -ba | sed -n '263p'`）自行复验，结果与处方一致。**按 T-030 先例，纯机械精度的处方级 MUST-FIX 收残后不再触发二次送审 gate**（7 项主体事实本身未受质疑）。

**并行 side work（同期，非本轮 scope，如实记）**：用户指定的 harnessloop plugin 自主驱动能力评估调研（T-058 codex + T-059 grok 双轨 + 主会话第一手合成）与本轮并行完成，交付 `docs/harnessloop-evaluation-20260726.md`（commit `c6365aa7`）：光谱定位"证据化控制协议非自主引擎"、14 条问题（S0×3）、12 条候选 evolution issues、3 条保留价值；过程中修 hopper `--search` 旗标漂移（`dispatch.js` env 旁路，submodule 内待正式版本流程）。此调研与 rounds/0010 SG-11 scope 无交叉，仅在同一时间窗口内推进，不计入本轮 scope-lock 验证范围。

**收敛守卫**：1 次 MUST-FIX（阈值 3），未触发——处方级收残即闭合，未进入返工循环。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E21 | wiki commits `da764f8`/`2ee61d2b`（`~/.llm-wiki/agent-app-design`）+ `rounds/0010/evidence/correction-table.md` | static | SG-11 conformance 修正批：7 项修正（openclaw ack 不可区分/interruptedActiveRun 不透出/hermes session-load 静默失败根因链+PRE-7 阈值+上游建议/new-api 两处 API 实况修正/D3 mint 501 residual 再确认/validate-schemas 无落点）全部回写 4 个 wiki 文件，零契约语义变更；验证方法=hopper 派 codex T-060 逐条确认审+主会话对处方级 MUST-FIX 自验（复现命令核对行号与引文）；claim 关系=supports（conformance 文档与 runtime 实况重新对齐）；可复现（wiki 仓 commit 固定，`git show`/`git diff` 可重跑；对照表常驻 `rounds/0010/evidence/`）；已登记 `state/evidence-index.md` E21 |

## Handoffs Closed

- hopper 派发 1 次，已闭合（`.hopper/queue.md` 对应行 status=done）：
  - **T-060**（codex，code-review-acceptance）：rounds/0010 SG-11 conformance 修正批确认审，Verdict **MUST-FIX**（7 项主体事实全确认，无漂移/无夹带/上游建议中立；仅 2 处机械精度问题——对照表旧行号漂移 + 引文多余花括号）→处方级收残（非返工，7 项主体判定未被推翻）。
- 按 CLAUDE.md「codex 评审三项强制核对」（本轮随机落在 codex）：(a) 实际审查对象为 brief 指定的 wiki commit `da764f8` + `rounds/0010/evidence/correction-table.md`，与 scope-lock 修正清单 7 项一致；(b) 产物落在 `.hopper/handoffs/T-060-output.md`；(c) 未仅凭 exit code 或自述采信——verdict 附带本机可复现命令（`nl -ba`、`git diff-tree`、`git show --unified=0 | rg`）与逐条 file:line 核验表，非空转自述。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-11 conformance 修正批（第二批首轮）证据充分且收敛：

- **7 项修正全部落地、逐条有出处**：openclaw ack 不可区分/interruptedActiveRun 不透出/hermes session-load 静默失败根因链+PRE-7 阈值+上游建议/new-api 两处 API 实况修正/D3 mint 501 residual 再确认/validate-schemas 无落点（app 侧记录、wiki 无需改）——均回写 4 个 wiki 文件 + 修正对照表，每处均有修订标注与 frontmatter `updated`/`sources`。
- **零契约语义变更**：`git diff-tree` 确认仅 4 个 Allowed 文件改动，D1/D2/D5 契约文本零改动；C-1/C-4 均触发 D1 §11 自身预写的既有规则确认分支（"不可区分/不透出则维持现状"），经 codex 核实 D1 §11:817/820 确有对应预写文本，判断成立。
- **★审查闸单次收敛**：codex T-060 判 MUST-FIX，但 7 项主体事实全部确认无漂移/无粉饰/无语义夹带/上游建议中立——MUST-FIX 范围仅限 2 处机械精度问题（父提交行号漂移、多余花括号），主会话照处方收残 + 用 codex 给出的复现命令自验，按 T-030 先例处方级修正不再 gate，未触发二次送审。
- **上游建议中立性确认**：hermes §4.3 报/不报建议先列报告草案要点、再列不报理由，最后明确"决策留用户"，codex 逐句核对未发现倾向性夹带。
- **无落点判定可信**：validate-schemas 项经 D4/facts 定向检索确认无相关断言性叙述，codex 认可该判断可信。

**待用户决策（本轮不擅自裁定）**：hermes session/load 静默失败 bug **报不报上游 issue**——`research/pre1-hermes-source-conformance.md` §4.3 已备中立建议（报的草案要点 vs 不报理由并列），本轮仅完成建议文本回写，是否实际上报交用户在收官报告中决定。

无 negative/未决评审悬置（MUST-FIX 已处方级收残），故本轮 feedback 分类 **positive**。

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
- Estimated cost: unavailable（执行子代理的实际写作/收残驱动成本已在其原执行会话消耗，未在本次状态回写中单独记账；hopper T-060 实测成本见 `.hopper/handoffs/T-060-output.md` 元数据 `duration_ms: 386069`）

## Decision

见 rounds/0010/decision.md：feedback = **positive**；裁决 = **SG-11 done**（7 项修正全落，零契约语义变更，codex T-060 MUST-FIX 为处方级机械精度问题，已收残不再 gate）；side work（harnessloop plugin 自主驱动能力评估调研）并行交付注记；用户决策点（hermes 上游 issue 报不报）显式列出；收敛守卫（1 次 MUST-FIX，阈值 3）未触发；下一步为 **SG-10 Mac UI 壳主线启动**（第二批 SG 已 user-confirmed：主线＝Mac UI 壳优先；随行项 SG-12/13/14 穿插）。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker；MUST-FIX 为处方级机械精度问题，已收残闭合，未触发 Rollback Condition 的 contract-insufficient 停下路径）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: **SG-10 Mac UI 壳主线 L1**（最小可见 app）启动，新开 scope-lock；hermes 上游 issue 报不报待用户决策（非阻断，`research/pre1-hermes-source-conformance.md` §4.3 建议已备）
- User input required: 是（hermes 上游 issue 报不报为决策类待办，非本轮收盘阻断项）

## Open Risks

- **hermes session/load 静默失败 bug 上游处置未决**——报/不报 hermes 上游 issue、部署 recipe 是否默认改 `provider:custom`，均待用户决策，wiki `research/pre1-hermes-source-conformance.md` §4.3 已备中立建议草案。
- **D3 mint HTTP 端点仍 501**——`newapi_token_id_lookup_unresolved`，本轮只是再确认 wiki 登记与 runtime 实况一致，解除仍待 D3 业务面（第二批候选，未被本轮触碰）。
- **validate-schemas 实例校验缺口（发现⑤）未修**——本轮判定"wiki 无落点"，实际脚本修复仍是应用侧 codegen 工具链的待办，非本轮 scope，建议登记为独立 harnessloop evolution issue 或结转到后续 SG。
- **openclaw ack 层不可区分/interruptedActiveRun 不透出**——本轮只是把既有决定性答案回写进 wiki 事实记载，产品/契约层面是否需要额外状态查询或事件观察机制以满足未来产品需求，仍留待后续设计决策。
- **SG-8.4②回填重建子项/SG-8.4③ hermes ACP kernel-client 适配器**——延续 rounds/0009 记录，均为第二批 SG 候选（SG-13 承接 SG-8.4③），本轮未触碰。
- **两个 rounds/0007 defer 项**（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计裁决）——第二批 SG-12 候选，本轮未触碰。
- **side work（harnessloop plugin 评估调研）产出的 14 条问题/12 条候选 evolution issues**——非本轮 scope，已交付 `docs/harnessloop-evaluation-20260726.md`，后续是否登记为正式 evolution issues 待处理。

## Next Proposed Scope

**SG-11 conformance 修正批（第二批首轮）已达成**。下一步：

1. **SG-10 Mac UI 壳主线 L1**（最小可见 app：窗口+会话列表+新建会话+消息流渲染，连隔离 openclaw 真实往返）——第二批 SG 主线，已 user-confirmed 优先启动，新开 scope-lock。
2. **候选穿插**：SG-12（defer 修复轮：TS `EmptyPayload` 精度缺陷 + strict-decode 设计裁决）/ SG-13（hermes ACP kernel-client 适配器，承接 SG-8.4③）——按批次序建议在 SG-10 各阶段间穿插。
3. **SG-14**（Stage C 产品行为 parity）随 SG-10 各阶段同步交付，非独立大轮。
4. **待用户决策**：hermes session/load 静默失败 bug 报不报上游 issue（`research/pre1-hermes-source-conformance.md` §4.3 已备草案，交用户决定）。

第二批 SG 方向本身已于 2026-07-26 user-confirmed（详见 `goal-breakdown.md`「第二批开发子目标（SG-10..SG-14）」小节），本轮收盘不需要用户就此再次确认；继续逐个走 round → decision → feedback → state 回写闭环。
