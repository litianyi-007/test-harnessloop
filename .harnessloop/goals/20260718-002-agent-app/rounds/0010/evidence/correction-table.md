# rounds/0010 修正对照表（SG-11 conformance 修正批）

范围：把 rounds/0008/0009 的 runtime 发现回写进 design wiki（`~/.llm-wiki/agent-app-design`，
独立 git 仓）。逐条对照旧表述 → 新事实 → 证据出处 → 落点 file:line。**不改任何 D1/D2/D5
契约文本语义**——本批全部是 conformance 事实记载/caveat 注记，且均触发的是 D1 自身预写的
既有规则确认分支（C-1/C-4），不构成语义变更。

---

## 1. openclaw ack 层不可区分（C-1 决定性答案）

| 项 | 内容 |
|---|---|
| 旧表述 | D1 §11 C-1 登记为"待验证"：soft `chat.send`+`queueMode:"steer"` 在有 active run 时是否回传可机器区分的 `queued`/`reason` 字段，成功注入与静默降级是否可机器区分——"止步于源码/文档均未写明，只能靠运行时观察才能确定" |
| 新事实 | **决定性答案：不可区分**。场景 A（运行中注入）与场景 C（空闲静默 fallback）响应体完全相同 `{runId, status:"started"}`，无 `messageSeq`/`queued`/`reason` 字段；源码坐实 ack 在模型调用前同步返回，本身不携带"是否注入到活跃 run"信息。场景 B（拒收）是通用请求校验，非 steer 专属。按 D1 §11 C-1 自身预写规则（"若确认不可区分：当前二态设计维持不变，无需进一步降级"），触发既有规则确认分支，**不改 D1 契约文本** |
| 证据出处 | `rounds/0009/evidence/track-a-openclaw.md` §2（三场景响应体差异表）；源码 `chat-send-handler.ts:270-288`、`chat-send-request.ts:167-169`；对抗复核 `.hopper/handoffs/T-057-output.md`（发现②，判定"未夸大"） |
| 落点 | `~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md` 新增 §4（`4.1` L536-569、`4.2` L571-578）；`~/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md` §7 新增「事实④」（L254-271） |

---

## 2. openclaw `interruptedActiveRun` 失败路径不透出（C-4 决定性答案）

| 项 | 内容 |
|---|---|
| 旧表述 | D1 §11 C-4 登记为"待验证"：`sessions.steer` abort 成功但 `chat.send` 本身失败时，error 响应是否透出 `interruptedActiveRun`——"现有源码只展示了成功路径的 payload 结构，失败路径的 error 响应形状……需要真实触发这个具体的失败场景才能看到" |
| 新事实 | **决定性答案：不透出**。构造"400ms 内 abort 真实活跃 run 成功、resend 因空消息通用校验失败"的确定性场景，返回体不含 `interruptedActiveRun`；`abortedLastRun:true`/`status:"killed"` 证实 abort 确实生效。源码级根因：`sessions-messaging.ts:379-389` 三元表达式仅在 `ok===true` 时拼接该字段，`ok===false` 原样返回 `payload`，字段结构上不可能出现——对所有失败态成立的无条件代码事实。按 D1 §11 C-4 既定规则（不透出则统一上报 `aborted_effect_unknown`，不得猜测性上报 `aborted_resend_failed`），本轮结果支持维持既有保守默认，**不改 D1 契约文本** |
| 证据出处 | `rounds/0009/evidence/track-a-openclaw.md` §3；源码 `sessions-messaging.ts:120-210,356-390,379-389`；对抗复核 `.hopper/handoffs/T-057-output.md`（发现③，判定"属实，未夸大"） |
| 落点 | `~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md` 新增 §5（`5.1` L591-614、`5.2` L616-621）；`~/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md` §7 新增「事实⑤」（L274-291） |

---

## 3. hermes `session/load` 静默失败（比 §1.7 原猜测更严重）+ PRE-7 阈值结论 + 上游处置建议

| 项 | 内容 |
|---|---|
| 旧表述 | `pre1-hermes-source-conformance.md` §1.7（第 17 条）登记为"需 runtime 才能定论"：`_replay_session_history` 是"尽力而为"设计，具体退化边界（高延迟/大历史场景下是否会部分丢失）"只能靠真实大会话做一次 live probe 验证" |
| 新事实 | **确定性、100% 复现的会话持久化/恢复往返 bug，比原猜测的"部分丢失"更严重（是"零复原"且"看起来像成功"）**。复现条件：`model.provider:auto`+自定义 base_url（如本项目使用的自建 new-api）、未配置真实 `OPENROUTER_API_KEY`；首次 `session/load` 成功，此后任意独立冷启动 100% 返回 0 条历史。根因链：`_make_agent` 创建时经 `runtime_provider.py:1649-1684` "auto+自定义 base_url" 旁路成功 → 但 `_resolve_openrouter_runtime`（`runtime_provider.py:1165-1169`）把非字面 `"custom"` 的值一律 relabel 为 `"openrouter"` → `_persist` 把该内部标签写回持久化 → `_restore` 读出 `"openrouter"`（非 `"auto"`）不再命中旁路，要求真实 `OPENROUTER_API_KEY`，`init_agent` 抛异常 → 被 `_restore` 的 `except Exception: return None`（`session.py:551-561`）吞掉，ACP 客户端收到字段全 `None` 但非 `None` 对象的 `LoadSessionResponse`，与"加载成功但无历史"结构上无法区分。**PRE-7 阈值判定 PASS（20/20、0.79-0.82s、3/3 一致），但前提是规避该 bug（`provider: custom`），不可剥离前提单读 PASS**。附上游处置建议（报/不报两侧要点，中立呈现，决策留用户） |
| 证据出处 | `rounds/0009/evidence/track-b-hermes.md` §2（SG-8.3 PRE-7）；源码 `acp_adapter/session.py:551,590-659`、`hermes_cli/runtime_provider.py:1165-1169,1649-1684`、`acp_adapter/server.py:1140-1143`；对抗复核 `.hopper/handoffs/T-057-output.md`（发现④，"机制链完整可复现"）；`.hopper/handoffs/T-055-output.md`（背景引用，token 掩码复核来源） |
| 落点 | `~/.llm-wiki/agent-app-design/research/pre1-hermes-source-conformance.md`：§1.7 第 17 条行内 postscript（L112）+ §0 结论速览表第 4 行注记（L43）+ 新增 §4（`4.1` L190-243 根因链、`4.2` L245-262 PRE-7 阈值、`4.3` L263-304 上游处置建议） |

---

## 4. new-api API 实况修正（GET /api/token/:id 掩码 + /api/log/token 鉴权机制）

| 项 | 内容 |
|---|---|
| 旧表述 A | `d6-newapi-integration.md` §4.1（原 L263）：`GET /api/token/:id`（`GetTokenKey`）"confirmed（T-009 N2）——返回 `{key: fullKey}`" |
| 新事实 A | 该端点**实测仅返回掩码 key**（如 `"key":"w83m**********dCjL"`），T-009 的"返回明文"推断在目标 new-api 实例上不成立，与创建响应缺明文/缺 id 是同一个更宽的缺口 |
| 旧表述 B | `d6-newapi-integration.md` §4.1（原 L269）：`GET /api/log/token?key=` "公开（持 token key 即可）confirmed（T-005 C2）——CORS 友好，按 token 查日志" |
| 新事实 B | 真实鉴权机制是 `Authorization: Bearer <token>` header；裸 `?key=` 查询参数在目标实例上返回 `{"message":"Token not provided"}`，T-005 C2 的鉴权方式记录有误。另附背景：D1 §11 C-3 指定验法 `GET /api/log/self?token_name=...` 经同轮实测确认不可行（user-session 鉴权，非 token 自持），替代验法即本行 `GET /api/log/token`+Bearer |
| 证据出处 | `rounds/0009/evidence/track-b-hermes.md` §1（SG-8.2 token 自查互验，含 1.1 指定验法不可行/1.2 替代验法/1.3 互查不串号+参数注入对抗）；`app/kernel-client/HERMES-RUN-EVIDENCE.md`（rounds/0008，token 掩码原始记录）；对抗复核 `.hopper/handoffs/T-055-output.md`（token 掩码独立坐实）、`.hopper/handoffs/T-057-output.md`（§7 #11 再确认对抗复核） |
| 落点 | `~/.llm-wiki/agent-app-design/architecture/d6-newapi-integration.md`：新增 v4 blockquote（L56）+ §4.1 `GET /api/token/:id` 行修正（L269）+ §4.1 `GET /api/log/token` 行修正（L275） |

---

## 5. D3 mint HTTP 501 residual 再确认（无契约变更，只再确认既有登记）

| 项 | 内容 |
|---|---|
| 旧表述 | `d6-newapi-integration.md` §7 #11（原 L422）：`POST /api/token/` 创建响应不含新 token 的 `:id`——"未闭合的功能性缺口……登记为实现前必须冒烟确认的阻断项" |
| 新事实 | 该缺口在 rounds/0009 SG-8.1④ 真实业务 mint 端点（`app/server` `POST /sessions/:sessionId/billing-token`）实测中**再次复现确认仍为 HTTP 501**（`code:newapi_token_id_lookup_unresolved`）——不是新发现，是对既有登记状态的**再确认**；映射层（源码文档化的开发期 `upsert`/`findActive` 路径）已验证可用，但**不构成对本行反查缺口的解除**。措辞纪律采纳 T-057 对抗复核意见：不得把"映射层 pass"等同于"mint 成功/501 已解除" |
| 证据出处 | `rounds/0009/evidence/track-a-openclaw.md` §1 SG-8.1④（含真实业务端点 501 curl 记录、`upsert`/`findActive` 映射层验证、fail-closed 对照）；对抗复核 `.hopper/handoffs/T-057-output.md` §1（"映射 pass + mint HTTP residual，不得等同 mint 成功/501 解除"） |
| 落点 | `~/.llm-wiki/agent-app-design/architecture/d6-newapi-integration.md` §7 #11 行内附注（L428） |

---

## 6. validate-schemas 未验实例（无落点判定）

| 项 | 内容 |
|---|---|
| 判定 | **无落点，wiki 不改**。发现⑤（`app/contracts/d2/codegen/scripts/validate-schemas.mjs` 只对 schema 做 `ajv.addSchema`+`getSchema` 编译期自检，从未对真实/金标实例调用 `validateMessage(fixture)` 校验）是应用侧 codegen 工具链的实现细节 gap，不是 wiki 设计文档对"该脚本会校验实例"做出过的断言。逐一核查 `~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`（D4 codegen/金标 parity 相关全部章节，含 §3.4/§3.5/§3.5a/§3.6/§4 金标 parity fixture 设计、`allOf`/`oneOf` codegen 边界修正段落）与 `kernel-ecosystem-facts.md`，均未发现"`validate-schemas.mjs` 已对实例做校验"或等价的断言性叙述——D4 §4 描述的"金标 parity fixture"是三端 client 代码的行为一致性测试（`codegen/verify/{swift,csharp}` 真实编译+运行时断言），与本发现所指的 schema 自检脚本（`app/contracts/d2/codegen/scripts/validate-schemas.mjs`）是不同的工具，不存在需要对齐的矛盾表述 |
| app 侧落点 | `app/contracts/d2/codegen/scripts/validate-schemas.mjs`（本轮发现的原始出处）；rounds/0009 已验证一套可行的 dereference 工作流（`@apidevtools/json-schema-ref-parser` 展开 `$ref` 后再交 Ajv 编译+校验）可供后续任务直接复用，建议登记为独立的 harnessloop evolution issue 或结转到后续 SG，不在本轮 wiki 回写范围内 |
| 证据出处 | `rounds/0009/evidence/track-a-openclaw.md` §4①（SG-8.4①，工具链发现段） |
| 落点 | 无（wiki 无需改，本表即为唯一记载） |

---

## 7. 每处修正的修订标注情况汇总

| 修正项 | wiki 文件 | 修订标注方式 |
|---|---|---|
| 1 (C-1) | `research/pre1-openclaw-source-conformance.md` | 顶部 blockquote 新增"2026-07-26 追加"段 + §4/§5 各自开头 blockquote 标注"修订标注"+ frontmatter `updated: 2026-07-26`/`sources` 追加 |
| 2 (C-4) | 同上 | 同上（§5） |
| 3 (hermes §1.7 + PRE-7 + 上游建议) | `research/pre1-hermes-source-conformance.md` | 顶部 blockquote 新增"2026-07-26 追加"段 + §1.7 表格行内 postscript + §0 汇总表注记 + §4 开头 blockquote 标注 + frontmatter `updated`/`sources` 追加 |
| 4 (new-api API 实况) | `architecture/d6-newapi-integration.md` | 新增"v4 conformance 修正"顶部 blockquote（沿用既有 v1→v2→v2.1→v2.2→v3→v4 累积式版本注记惯例）+ 两处表格行内"v4 修正"标注 + frontmatter `updated`/`sources` 追加 |
| 5 (D3 mint 501 再确认) | 同上 | §7 #11 行内"v4 再确认"标注 |
| 6 (validate-schemas) | 无 wiki 改动 | 本对照表即为唯一记载 |
| 4/5 兼用引用 | `kernel/kernel-ecosystem-facts.md` | §7 新增「事实④」「事实⑤」+ intro 段落新增一句 + 研究出处/交叉引用两节追加 rounds/0009 出处 + frontmatter `updated`/`sources` 追加 |

---

## 红线自查

- 未改 D1/D2/D5 任何契约文本语义（行为规范/字段/状态机）——本批全部改动落在
  `research/pre1-*.md`（`design_status: draft`，本就是 conformance 核验页，非契约本身）与
  `architecture/d6-newapi-integration.md`/`kernel/kernel-ecosystem-facts.md`（消费 D1 结论
  做事实记载的下游文档，编辑范围严格限定在"事实行"与"changelog blockquote"，未触碰
  `kernel/d1-kernelport-spec-v3-6.md` 一个字）。
- C-1/C-4 均触发的是 D1 §11 自身预写的既有规则确认分支（"若确认不可区分/不透出：维持
  现状不升级"），不构成新增语义。
- 未动本仓 `app/`/`kernels/`/三插件；本表所有凭证引用均已脱敏（token 值全部用掩码/占位
  形式呈现，与源 evidence 一致）。
- 未报告任何 hermes 上游 issue——仅在 wiki 页内写建议草案，报/不报决策留待用户。
- 无需动契约语义的发现——本轮 7 项修正均无需触及 D1/D2/D5 契约文本即可完整记载，无
  blocker 需要上报。
