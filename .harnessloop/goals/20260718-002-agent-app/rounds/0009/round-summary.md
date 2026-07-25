# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0009（SG-8 验收清单收尾批次——SG-8.1/SG-8.2/SG-8.3/SG-8.4①②，探针/验证型工作，两内核双轨并行（A=openclaw/B=hermes）执行，第五次完整走 continue 驱动 + 关键节点独立审查机制；SG-8.4③ hermes ACP kernel-client 适配器事先在 scope-lock 中显式 defer，属实现级工作不入本轮）
- Scope-lock: rounds/0009/scope-lock.md（v1）
- Started: 2026-07-25
- Completed: 2026-07-26

## What Changed

本轮把首批 SG 最后悬着的 **SG-8 验收清单收尾批（SG-8.1/8.2/8.3/8.4①②）** 一次清干净——全部为探针/验证型工作（跑真实内核收证据，不写产品代码），两内核两侧相互独立、并行双 Sonnet 子代理执行（轨 A=openclaw 侧，轨 B=hermes 侧），★审查闸经 hopper 派 grok（T-057，异构对抗审）证伪式核验判 **PASS_WITH_NOTE**，主会话独立复验零改动。

**轨 A（openclaw 侧，证据 `rounds/0009/evidence/track-a-openclaw.md`）**：

- **SG-8.1（SG-6 e2e wire 实证，4 项）**：①③引用 rounds/0004 既有强证据 + 本轮新鲜环境轻量复证（header 到达三字段一致、SSE 3-chunk 流式不缓冲）pass；②sessionId 逐字节同源——内核侧 2 处取值 × D3-proxy 侧 3 处取值，5 处两两相等，显式断言成立，pass；**④按措辞纪律拆两层判定：映射层 pass（真实业务 mint HTTP 端点仍 501 `NotImplementedException`，源码 `session-token.controller.ts:21-27` → `newapi-client.service.ts:53-63` 坐实；探针走源码自身文档化的开发期 `upsert` 路径 `session-newapi-token-map.service.ts:53-56` 达成 `revokedAt IS NULL` 行 + `findActive` 命中，且被独立的真实 session-proxy 转发成功交叉印证）+ mint HTTP residual（501 未解除，非本轮新发现，`newapi_token_id_lookup_unresolved` 缺口已登记于 D6 §3.1/§7 #11）——residual 结转 **D3 业务面（第二批）**，不折叠成纯 pass**。
- **SG-8.3 PRE-1(C-1)**：三场景响应体差异表逐字段对照。**发现②**：`chat.send` ack 在 steer-注入活跃 run 与空闲新开 run 两种场景下结构完全相同（均 `{runId, status:"started"}`，无 `messageSeq`/`queued`/`reason` 等可区分字段）——即 D1 §11 C-1 关心的"ack 层机器可区分性"，决定性答案是**否**；源码坐实 `chat-send-handler.ts:270-288` 该 ack 在任何模型调用发起前同步返回。B 场景（拒收）经源码检索确认是通用消息校验（`chat-send-request.ts:167-169`），非 steer 专属拒收分支。判定 pass。
- **SG-8.3 PRE-3(C-4)**：构造"abort 成功、resend 因空消息校验失败"的确定性场景。**发现③**：abort 确实成功（`abortedLastRun:true`/`status:"killed"`），但最终失败响应体里**不透出** `interruptedActiveRun`——源码级根因 `sessions-messaging.ts:379-389` 的三元表达式仅在 `ok===true` 真分支才拼接该字段，是对所有失败态成立的无条件代码事实。判定 pass，支持维持 D1 既定"不透出则上报 `aborted_effect_unknown`"的保守默认，不触发契约修订。
- **SG-8.4①②**：新写 Swift 探针入口 `d2-live-dump-main.swift`（复用 `FrameReplayTestMain.swift` 已有的"独立 `@main` 入口 + 不改生产代码"编译模式），与生产 kernel-client 源码一起编译，抓 4 条真实 D2 事件（`evt.message.delta`/`evt.turn_complete`/`evt.operation_completed`/`evt.session_end`）逐条过 Ajv `message.schema.json`，4/4 PASS。**发现⑤**：本轮第一次真正对实例调用 validator 时才暴露 `app/contracts/d2/codegen/scripts/validate-schemas.mjs` **从未真正对实例调用过 Ajv validator**——该脚本只用 `ajv.addSchema`+`getSchema` 证明 schema 能**编译**（`$ref` 图无悬空引用），fixture 循环只 `JSON.parse`、从未调用 `validateMessage(fixture)`，是第 3 个"断言了个寂寞"式工具链缺口；本轮用 `@apidevtools/json-schema-ref-parser` dereference 展开补出一套可行工作流（探针内产出，未改 `app/` 源码），建议后续轮次补进 `validate-schemas.mjs`。protocolVersion 握手期单传→事件回填重建 round-trip：**连接级子项 pass**（5 次独立握手 `lastHandshakeProtocol` 全部一致=`4`，抓到的全部真实事件帧均无重复携带 protocol 字段）；**回填重建子项如实 defer**——`capabilities()`（`OpenclawGatewayKernelClient.swift:808-810`）与 `evt.capability_changed` dispatch（`EventMapping.swift:701-722`）在 kernel-client 当前实现里均是既有登记在案的 TODO 桩，机制本身未落地，无可执行代码路径可供探针验证，非本轮新增缺口。

**轨 B（hermes 侧，证据 `rounds/0009/evidence/track-b-hermes.md`）**：

- **SG-8.2（token 自查互验，验法修正）**：D1 §11 C-3 指定的 `GET /api/log/self?token_name=...` 实测**不可行**——该端点鉴权模型是已登录用户会话（cookie），不接受裸 API token 作 Bearer 凭证，与"token 自持查自己"的假设不符；同时修正 T-005 早期推断的裸 `?key=` 查询参数用法。**真实等价替代验法为 `GET /api/log/token` + `Authorization: Bearer <token>`**：复用 SG-7 既有计费记录（token_id=4/5），token A 只见己方 3 条、token B 只见己方 1 条，对抗测试（Bearer A + query 注入 `token_name=<对方>`）仍只返回 A 的数据，零串号；零新 Kimi 调用。判定 PASS（含验法修正，非 SG-7 admin API 现场核对的替代路径，而是清单指定验法的真实等价物）。
- **SG-8.3 PRE-7（session/load replay 阈值）**：**发现④**——用 rounds/0008 recipe 原样的 `model.provider: auto` 配置起步，第一次 `session/load` 成功（20/20 条），但**此后所有独立子进程的 `session/load` 调用 100% 复现返回 0 条历史**。根因逐文件坐实（`acp_adapter/session.py:551/651` → `runtime_provider.py:1169` 非字面 `custom` 的 requested 被 relabel 为 `openrouter` → `_persist` 把该内部标签写回持久化 → `_restore` 下次读出 `openrouter` 不再命中"auto+自定义 base_url"旁路 → `init_agent` 抛 `RuntimeError: No LLM provider configured` → `_restore` 自身 `except Exception: return None` 把异常静默吞掉 → `server.py:1140-1143` `load_session` 返回一个字段全 `None` 但非 `None` 对象本身的 `LoadSessionResponse`，与"加载成功但恰好无历史"结构上无法区分）。这是一个**确定性、100% 可复现**的 ACP 会话持久化↔恢复往返 bug，比 PRE-1 §1.7 原本担心的"部分丢失"更严重（是"零复原"且"看起来像成功"），**不影响 SG-7 api_server `model_routes` 路径结论**（两条是 hermes 内独立的会话/凭证管理路径）。**变通复测**：把 scratchpad throwaway `hermes-home/config.yaml` 的 `model.provider` 由 `auto` 改为 `custom`（纯配置改动，零 `kernels/hermes` 源码改动），create 与 restore 走同一分支，不再有非对称性。3 次独立冷启动测量：**20/20 条，顺序保持（SEED-01..10 交替），耗时 0.792s/0.815s/0.803s（远低于 10s 阈值），3 次一致**。**PRE7_REPLAY_VERDICT: PASS——但该判定成立的前提是以 `provider: custom` 配置规避了发现④记录的静默失败 bug；若沿用 recipe 原始 `provider: auto` 配置，阈值判定会是 FAIL（0/20，完全空载而非部分丢失），二者必须一并读，不得只读 PASS**。
- **SG-8.3 hermes-steer-runtime 冒烟**：运行中注入场景（`state.is_running:true`）steer 请求 0.002s 几乎瞬时返回，先收到与源码 `_cmd_steer:1996-1998` 字面拼接逐字节吻合的 ack 文案，确认真软注入路径被触发；但主 turn 因全程未调用任何工具（无"下一次工具结果"挂载点），最终产出未包含 steer 注入内容——是 D1 v3.6 反复强调的"`submitted` 不承诺已注入生效，只承诺 RPC 被接受"这一设计约束的一次运行时活体坐实，非矛盾。空闲注入场景（`state.is_running:false`）耗时 4.117s、无 ack 文案，按文档化 idle-rewrite 路径整段重写为新 turn。两场景 `PromptResponse.field_meta`/`user_message_id` 均为 `None`，与 v3.6-r1（T-040）源码结论逐字吻合。判定 PASS，与 D1 v3.6 完全吻合、未发现矛盾。

**★审查闸（hopper 派 grok，T-057，证伪式对抗审）Verdict = PASS_WITH_NOTE**：五项重点逐条过源码/git，**未发现把失败粉饰为 pass、也未发现 file:line 明显误读**；发现②③④⑤ 均在源码坐实、未夸大；PRE-7 阈值数据支持 pass（严格以 `provider: custom` 前提）；零改动核验（两 submodule + `app/`）本机复验通过。**唯一 NOTE（必须写入本轮收官文案，已采纳）**：SG-8.1④ 不得写成"mint 成功/501 解除"，须拆两层——映射层 pass、HTTP mint 端点 stub 残留须作为 residual 进入收官（本 round-summary 已按此措辞落笔，见上方轨 A ④）；PRE-7 PASS 须与 `provider: auto` 静默失败 bug 同读，不可剥离前置条件单独引用 PASS。grok verdict 同时确认：若不采纳 NOTE①、把 SG-8.1 写成无保留 full pass，则应降为 REWORK（文档/判定措辞级，非证据造假级 FAIL）——本轮按 NOTE 采纳，故未触发 REWORK。

**主会话零改动核验（亲验，收官核对）**：`kernels/hermes` 全空（`git status`/`--ignored --short`/`diff --stat` 三查均空，pin `17155e3ae` 未漂移）；`kernels/openclaw` tracked diff 空、唯一 untracked 为会话前既有的 `git-hooks/post-commit`（全局 git-ai hook，非本轮产物）、ignored 全为既有 `.gitignore` 命中的构建产物/依赖目录（`dist/`/`node_modules/` 等）；隔离进程（openclaw 18999、D3-proxy 3011、抓包代理 3012）与 hermes ACP 子进程全部清理，`lsof`/`ps` 收尾核对无残留；用户全局 gateway（`127.0.0.1:18789`，PID 5197）收尾仍正常监听，全程未被连接；Pi 上本轮新增的 8 行测试映射数据已清理，rounds/0004/0008 遗留既有行未触碰。

**收敛守卫**：0 次 REWORK（阈值 3），全程未触发——grok 一次即判 PASS_WITH_NOTE，NOTE 在收官措辞层面直接采纳，未触发返工循环。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E20 | `rounds/0009/evidence/track-a-openclaw.md` + `rounds/0009/evidence/track-b-hermes.md` | runtime | SG-8 收尾批双轨探针：SG-8.1①②③④、SG-8.2、SG-8.3 PRE-1/PRE-3/PRE-7+steer 冒烟、SG-8.4①②，5 处发现（②③④⑤，均 file:line 坐实）+ PRE-7 阈值数据（20/20 条、0.79-0.82s、3 次一致，含 `provider:custom` 前提）；验证方法=双轨探针 + hopper 派 grok T-057 证伪式对抗审 PASS_WITH_NOTE + 主会话零改动亲验；claim 关系=supports（SG-8.1②④映射层/8.2/8.3/8.4①②各判定成立，5 项发现坐实）；可复现（探针脚本/recipe 均留痕，见各轨 evidence 文末产出文件清单）；已登记 `state/evidence-index.md` E20 |

## Handoffs Closed

- hopper 派发 1 次，已闭合（`.hopper/queue.md` 对应行 status=done）：
  - **T-057**（grok，code-review-adversarial）：rounds/0009 SG-8 收尾批双轨探针证据对抗审，Verdict **PASS_WITH_NOTE**（五项重点逐条核验，未发现粉饰/误读；SG-8.1④ 判定诚实性 NOTE 已采纳；PRE-7 前提须同读 NOTE 已采纳）。
- 按 CLAUDE.md「codex 评审三项强制核对」（本轮随机落在 grok，同一纪律适用）：(a) 实际审查对象为 brief 指定的 `rounds/0009/evidence/track-a-openclaw.md` + `track-b-hermes.md`，与 scope-lock/goal-breakdown SG-8 清单/D1/PRE-1 对照，一致；(b) 产物落在 `.hopper/handoffs/T-057-output.md`；(c) 未仅凭 exit code 或自述采信——verdict 附带本机 git 复验命令输出（openclaw/hermes 两 submodule + `app/`）与逐条 file:line 核验表，非空转自述。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-8 收尾批（SG-8.1/8.2/8.3/8.4①②）证据充分且收敛：

- **双轨探针证据完整**：轨 A openclaw 侧 SG-8.1 四项（①②③pass、④映射层pass+mint HTTP residual）+ SG-8.3 PRE-1/PRE-3（发现②③，均 pass）+ SG-8.4①②（发现⑤，连接级pass+回填defer）；轨 B hermes 侧 SG-8.2（验法修正后PASS）+ SG-8.3 PRE-7（发现④，PASS 有条件）+ hermes-steer 冒烟（PASS）。
- **5 处发现全部源码坐实、未夸大**：②openclaw ack 层不可区分（`chat-send-handler.ts:270-288`）、③abort成功+resend失败不透出（`sessions-messaging.ts:379-389`）、④hermes provider-relabel 静默失败（`session.py:551/651`→`runtime_provider.py:1169`→`server.py:1140-1143`）、⑤`validate-schemas.mjs` 未真正调 validator（该脚本自身）——grok 逐条对源码/git 复验，判定"均可复现、未发现夸大"。
- **★审查闸一次收敛**：grok T-057 证伪式对抗审 PASS_WITH_NOTE，未触发 REWORK；唯一 NOTE（SG-8.1④ 拆层措辞、PRE-7 前提同读）已在本轮收官文案中采纳落笔，不需要重跑探针、不需要改内核。
- **零改动核验双查通过**：两 submodule（含 `--ignored`）+ `app/` 全部核对无本轮改动，主会话独立亲验与探针文档记录一致。
- **诚实边界完整标注**：mint HTTP 501 residual（结转 D3 业务面第二批）、SG-8.4②回填重建子项 defer（待 `capabilities()`/`capability_changed` 落地）、SG-8.4③ hermes ACP kernel-client 适配器（scope-lock 事先 defer，候选第二批 SG）均如实记录，未过度声称。

**SG-8 主体收官——首批 SG（SG-1..SG-9）全部主体达成**：SG-8.1（①②③pass；④映射pass+mint HTTP residual，按措辞纪律）、SG-8.2（done，含验法修正）、SG-8.3（done，含5发现引用）、SG-8.4（①done；②连接级子项done+回填重建子项defer；③scope-lock事先defer，非本轮scope）、SG-8.5/8.6/8.7 此前已 done——SG-8 整体状态由 pending 转为**主体 done**（八项子项中七项 done、一项子子项 defer，均如实标注，无子项被静默略过）。

无 negative/未决评审悬置，故本轮 feedback 分类 **positive**。

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
- Estimated cost: unavailable（执行子代理的实际探针驱动成本已在其原执行会话消耗，未在本次状态回写中单独记账；hopper T-057 实测成本见 `.hopper/handoffs/T-057-output.md` Vendor output：`total_cost_usd: 0.3642512`）

## Decision

见 rounds/0009/decision.md：feedback = **positive**；裁决 = **SG-8 主体收官**（SG-8.1 按措辞纪律拆层判定/SG-8.2 done 含验法修正/SG-8.3 done 含 5 发现引用/SG-8.4 部分 done+部分 defer）；**首批 SG（SG-1..SG-9）全部主体达成宣告**；residual/defer 显式清单：mint HTTP 501→结转 D3 业务面（第二批）、SG-8.4②回填重建→待 `capabilities()`/`capability_changed` 桩解除后、SG-8.4③ hermes ACP kernel-client 适配器→第二批候选；收敛守卫（0 次 REWORK）未触发；下一步为**第二批 SG 规划**（候选：Mac app UI 壳 / D3 server 业务面[含 mint HTTP 501 解除] / hermes ACP kernel-client 适配器[SG-8.4③] / Stage C 产品行为 parity 结转 / defer 修复轮[TS `EmptyPayload` 精度缺陷 + 解码边界 strict-decode 设计裁决] / conformance 修正批[发现②③④⑤ + T-005/T-009/PRE-1 早期推断修正]），**规划本身属 goal 级决策，需用户参与**。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker；探针暴露的发现④/⑤均为 conformance 修正候选而非 blocker，未触发 Rollback Condition 的 contract-insufficient 停下路径）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待用户参与的**第二批 SG 规划**决策（见下方 Next Proposed Scope）；SG-8.4②回填重建子项待 `capabilities()`/`capability_changed` 落地后可重新排期；mint HTTP 501 解除待 D3 业务面第二批工作包
- User input required: 是（第二批 SG 规划属 goal 级决策，需用户参与选定方向；本轮收盘本身不需要用户进一步确认）

## Open Risks

- **mint HTTP 端点仍 501**——`newapi_token_id_lookup_unresolved`（PRE-4 冒烟缺口再确认，非本轮新增），真实业务 mint API 路径尚未闭合，结转 D3 业务面（第二批）。
- **SG-8.4②回填重建子项无可执行代码可探针**——`capabilities()`（`OpenclawGatewayKernelClient.swift:808-810`）与 `evt.capability_changed` dispatch（`EventMapping.swift:701-722`）均是既有登记在案的 TODO 桩，待其落地后才具备重新排期该子项的条件。
- **SG-8.4③ hermes ACP kernel-client 适配器未走**——scope-lock 事先明确 defer，需新写 HermesACP kernel-client 适配器（实现级工作，非探针批 scope），候选第二批 SG。
- **hermes ACP provider-relabel 静默失败 bug（发现④）**——`model.provider:auto`+自定义 base_url（本项目一直在用的部署形态）+ 未配置真实 `OPENROUTER_API_KEY` 时，任何 `session/load`/`session/resume` 在首次连接之后会 100% 静默拿到空历史，登记为上游 hermes bug 候选 + conformance 修正候选，部署 recipe 建议默认改 `provider:custom`。
- **`validate-schemas.mjs` 实例校验缺口（发现⑤）**——从未真正对 fixture/实例调用 Ajv validator，仅证明 schema 可编译；本轮已验证一套可行的 dereference 工作流（探针内），建议后续轮次补进正式 codegen 脚本或 parity runner。
- **openclaw ack 层不可区分（发现②）/interruptedActiveRun 失败态不透出（发现③）**——均为对现有 D1/D2 契约行为的具体、可复现坐实（非缺陷），如未来产品/UI 需要机器可靠区分这些场景，当前 wire 协议在 ack 层做不到，需额外状态查询或事件观察，登记为 conformance 修正候选/产品需求输入。
- **D3-proxy body-parser 100KB 限制仍未修**（rounds/0004 已提过，本轮再次复现并绕行，仍未修复）——真实 openclaw agent 请求体 ~107KB，建议独立任务调大限制。
- **T-005/T-009/PRE-1 早期推断的多处 runtime 修正待批量整理**——new-api `/api/log/token` 鉴权方式（应为 Bearer header 而非裸 `?key=`）与 `id` 字段语义（局部序号而非全局主键，本轮 T-005 修正）、new-api `GET /api/token/:id` 只返回掩码 key（T-009 修正，rounds/0008 已记）、PRE-1 §1.7 对 session/load 丢失严重度的低估（本轮发现④修正），建议归入 conformance 修正批统一处理，非阻断。
- **两个 rounds/0007 遗留 defer 项延续未修**：TS `EmptyPayload` 精度缺陷（SG-1 codegen scope）、Swift/C# 解码边界静默忽略未知键（D1/D2 级 strict-decode 设计决策），本轮 scope 不含，仍待后续轮或设计修订处理。
- **hopper `||` 表格解析观察点**——延续 rounds/0007/0008 记录，是否升级为 hopper 插件 evolution issue 待主会话/用户后续决定。

## Next Proposed Scope

**SG-8 验收清单收尾批（SG-8.1/8.2/8.3/8.4①②）已达成——首批 SG（SG-1..SG-9）全部主体完成**。下一步是**第二批 SG 规划**，候选方向（供用户参与决策）：

1. **Mac app UI 壳**（D5 产品 UI 细节，此前明确未纳入首批）。
2. **D3 server 业务面**（含 mint HTTP 501 解除、成本展示/归因查询等 D6 剩余部分）。
3. **hermes ACP kernel-client 适配器**（SG-8.4③，本轮 scope-lock 事先 defer）。
4. **Stage C 产品行为 parity 结转**（D4 §4.6，rounds/0006 结转项）。
5. **两个 rounds/0007 defer 项修复轮**（TS `EmptyPayload` 精度缺陷 / 解码边界 strict-decode 设计裁决）。
6. **conformance 修正批**（本轮发现②③④⑤ + T-005/T-009/PRE-1 早期推断修正的批量整理与 wiki 回写）。
7. **hopper `||` 表格观察点处理**（是否升级为 hopper 插件 evolution issue）。

**规划属 goal 级决策，需用户参与**；确定方向后继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
