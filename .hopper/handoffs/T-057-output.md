---
phase: done
last_progress_at: "2026-07-25T18:33:29.473Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-25T18:33:29.472Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 222875
adapter_status: success
---
# T-057 对抗审产出（code-review-adversarial · grok · 只读）

**Task**: T-057（rounds/0009 SG-8 收尾批双轨探针证据）  
**Vendor**: grok · 只读 · 无 LLM 计费复验、无 new-api 写操作  
**评审对象**:  
- `.harnessloop/goals/20260718-002-agent-app/rounds/0009/evidence/track-a-openclaw.md`  
- `.harnessloop/goals/20260718-002-agent-app/rounds/0009/evidence/track-b-hermes.md`  
**对照**: `rounds/0009/scope-lock.md` · goal-breakdown SG-8 清单 · D1/PRE-1 文档 · 源码只读（`kernels/{openclaw,hermes}`、`app/server`、`app/contracts`、`app/kernel-client`）

---

## Summary

对 rounds/0009 双轨探针证据做了证伪式对抗核验：五项重点逐条过源码/git，**未发现把失败粉饰为 pass、也未发现 file:line 明显误读**。核心争议项 **SG-8.1④** 的诚实结论是：映射层（`upsert`/`findActive`/真实转发命中）可判 pass，但 **HTTP mint 仍 501，501 解除信号未成立**，不得把子项读成「mint 端到端成功」。发现 ②③④⑤ 均可在源码坐实；PRE-7 阈值数据支持 pass，但严格以 `provider: custom` 配置规避为前提；零内核改动 git 现状与证据一致。**Verdict: PASS_WITH_NOTE**——SG-8 收尾批证据整体成立、可推进收官，但收官文案必须把 mint HTTP stub 与 PRE-7 配置前提写成显式 residual，不能静默折叠进纯 pass。

## Files touched

none（对抗审只读；本文件为 handoff 规定产出落盘）

## Acceptance verification (5/5)

### 1. SG-8.1④ pass 判定诚实性（最重）

| 检查项 | 结果 | 证据 |
|---|---|---|
| 清单原文语义 | 「mint 成功 → 映射表 `revokedAt IS NULL` + `findActive` 命中（**501 解除信号**）」 | `goal-breakdown.md:119`；`scope-lock.md:10` 同口径「mint 成功→…」 |
| HTTP mint 实况 | **仍 501**，`code=newapi_token_id_lookup_unresolved` | 源码：`session-token.controller.ts:21-27` → service → `newapi-client.service.ts:53-63` `throw new NotImplementedException(...)`；证据 curl 与之一致 |
| 探针替代路径 | 直接实例化编译产物 `SessionNewApiTokenMapService.upsert/findActive` | 类/方法文档：`session-newapi-token-map.service.ts:12-21`（铸造链路整体 501，表供未来 mint 接线）+ `:53-56`（**供测试/开发环境手工种入**）——证据路径与源码允许的开发期路径一致，不是私改逻辑 |
| 映射断言本身 | `revokedAt: null` + `findActive` 返回有效 key；且 seed 后真实 session-proxy 转发 200 | 源码 `findActive` 只查 `revokedAt IS NULL`（`:39-50`）；证据 §1④ 步骤 2–3 + 未 seed fail-closed 对照 |
| 501 解除了吗？ | **没有** | 端点仍 `NotImplementedException`；本轮零 `app/` 改动 |

**对抗判定建议（明确）**：

- **不应**把 SG-8.1④ 表述为单一「pass = mint 成功 / 501 已解除」。
- **应**拆成两层：
  1. **映射层 pass**（`upsert` → 行 `revokedAt IS NULL` → `findActive` 命中 → 真实 proxy 转发交叉印证）——本轮证据充分、可采信；
  2. **HTTP mint 端点 stub 残留**（501 未解除，PRE-4/`newapi_token_id_lookup_unresolved` 仍在）——必须作为 **residual / 未解除信号** 进入收官，不得被汇总表一行「pass」吞掉。
- 证据**正文**已写出「真实业务端点 501 + 文档化 upsert 路径」，诚实度高于汇总表；**汇总表措辞偏乐观**，收官读者若只读表会误判 mint e2e 已通。
- 与 scope-lock「探针暴露组件真缺陷=发现而非 blocker」相容：映射层探针合格；mint HTTP 是**已知骨架缺口的再确认**，不是探针造假。

→ **本项对抗结论：判定诚实性 PARTIAL**——证据未隐瞒 501，但子项整体标 pass 相对清单「501 解除信号」**过宽**；建议收官时改写为「映射 pass + mint HTTP residual」。

### 2. 发现 ②③④⑤ 的 file:line 可复现性

#### 发现② openclaw `chat.send` ack：steer 注入 vs 空闲新 run 结构相同

| 断言 | 核验 |
|---|---|
| ack 在模型调用前同步返回 `{runId, status:"started"}` | **属实** `chat-send-handler.ts:270-288`：`ackPayload = { runId, status:"started", ...}` → `respond(true, ackPayload, ...)`，后续 `void gatewayWorkAdmission.run(...)`  detached |
| 不含注入/空闲可区分字段 | **属实**——该 ack 构造与 `queueMode` 无关；证据 A/C 均为 `{"runId":"...","status":"started"}` 与源码一致 |
| 空消息拒收是通用校验 | **属实** `chat-send-request.ts:167-169`：`if (!rawMessage && normalizedAttachments.length === 0) return { ok:false, error:"message or attachment required" }` |

**是否夸大？否。** D1/PRE-1 关心的「ack 层机器可区分性」答案就是「否」；证据把场景 A 内容级观察降为「部分/待确认」而不升级成「steer 退化」——克制、未夸大。

#### 发现③ abort 成功 + send 失败不透出 `interruptedActiveRun`

| 断言 | 核验 |
|---|---|
| 仅在 `ok===true` 时拼接字段 | **属实** `sessions-messaging.ts:379-389`：  
  `ok && payload && typeof payload === "object" ? { ...payload, ...(interruptedActiveRun?{interruptedActiveRun:true}:{}) } : payload`  
  `ok===false` 走假分支，字段结构上不可能出现 |
| 失败场景用空消息触发 | 合法：同上通用校验；且对任意导致 `ok=false` 的 resend 失败同构 |

**是否夸大？否。** 是无条件代码事实 + 运行时构造（`abortedLastRun:true`/`status:"killed"`）双重证据。

#### 发现④ hermes `session/load`：`provider:auto`+自定义端点 → 静默失败伪装成功

| 链路步 | file:line | 核验 |
|---|---|---|
| `_restore` 调 `_make_agent`，异常吞掉 `return None` | `session.py:551-561` | **属实** `except Exception: logger.warning(...); return None` |
| `_make_agent` → `AIAgent(**kwargs)` | `session.py:650-651` | **属实**（证据写 651 命中） |
| 非字面 `custom` 的 requested 被 relabel 为 `openrouter` | `runtime_provider.py:1165-1169` | **属实** `effective_provider = "custom" if requested_norm == "custom" else "openrouter"` |
| `_persist` 把 `state.agent.provider` 写回 model_config | `session.py:425-433` + `update_session_meta` | **属实** |
| `_restore` 再读 `meta.provider` 作为 `requested_provider` | `session.py:529` | **属实** |
| `load_session` 在 state is None 时 warning + `return None` | `server.py:1140-1143` | **属实** |

**机制链完整、可复现（源码推理即可坐实）**；比 PRE-1 §1.7「尽力而为 / 部分丢失」更严重（**零复原**）的定性**成立**。

**细微 NOTE（不推翻发现）**：服务端失败路径是 `return None` + `load_session: session not found` warning；证据中「客户端收到字段全 None 的 `LoadSessionResponse` 对象」属 **ACP 客户端观测层**（本次未重跑 ACP SDK 反序列化）。产品影响仍成立：后续 load 拿不到历史、易被「resp 非 error」路径误判。**未夸大根因；客户端「伪装成功」表述略依赖观测层，建议收官写「服务端 return None + 客户端无历史」更精确。**

与 SG-7 不矛盾：api_server `model_routes` 与 ACP `_persist/_restore` 是独立路径——证据 §2.2 已说明，采纳。

#### 发现⑤ `validate-schemas.mjs` 只编译、不对实例调 validator

| 断言 | 核验 |
|---|---|
| 注册 schema + `getSchema` 仅证明编译 | **属实** `validate-schemas.mjs:45-57` |
| fixture 循环只 `JSON.parse`，不调 `validateMessage(fixture)` | **属实** `:64-69`；全文件无 `validateMessage(` 调用 |
| 文件头注释声称会校验 fixture 实例 | 注释 `:4-6`/`:59-61` 与实现不符——**发现未夸大，甚至脚本自述在过诺** |

**是否夸大？否。**

### 3. SG-8.2 self 端点实况修正 + 不串号证据

| 检查项 | 结果 |
|---|---|
| D1/清单指定 `/api/log/self?token_name=...` | 证据：Bearer sk-token → Unauthorized；cookie 用户会话 → success——与「token 自持」假设不符。**指定验法不可行**判定合理 |
| 替代 `GET /api/log/token` + `Authorization: Bearer` | 证据实测：裸 `?key=` 失败，Bearer 成功；纠正 T-005 细节——合理 |
| 互验不串号 | A(token_id=4)→3 条全 A；B(token_id=5)→1 条全 B；`request_id` 与 admin 全量交叉——**充分** |
| 参数注入对抗 | Bearer A + query `token_name=...-b` 仍只见 A——**加强「以 Bearer 为准」** |
| 零新 Kimi 调用 | 复用 SG-7 日志——符合 scope |

**是否充分支持「不串号」？是**（token 级隔离在 new-api 侧）。scope-lock 已允许「self API 不符则如实 + 替代验法」——**SG-8.2 PASS 成立**，附带实况修正应进收官/D1 或调研文档。

### 4. PRE-7 阈值判定

| 阈值（scope-lock） | 证据数据 | 是否支持 |
|---|---|---|
| ≥20 条、不丢、顺序保持 | 3× **20/20**，SEED-01..10 交替 | 是 |
| ≤10s | **0.792 / 0.815 / 0.803 s** | 是（远低于 10s） |
| 连续 3 次一致 | 条数/顺序/量级一致 | 是 |

**workaround `model.provider: auto → custom`**：  
- 仅改 scratchpad `hermes-home/config.yaml`（throwaway），**非** `kernels/hermes` 源码；  
- 与 `runtime_provider.py:1169` 字面 `custom` 不被 relabel 一致——**config-only、零内核改动成立**。

**诚实前提**：证据已写明——原始 `provider:auto` 下阈值会 **FAIL（0/20）**。PASS **有条件**，不可剥离前置 bug 只读 PASS。  
→ **PRE7_REPLAY_VERDICT: PASS（有配置前提）** 被数据与源码共同支持。

### 5. 零改动 + 判定汇总表

**本机 git 复验（对抗审时点）**：

```
$ git -C kernels/openclaw status --short
?? git-hooks/post-commit          # 与证据一致：会话前既有 untracked hook，非本轮产物

$ git -C kernels/openclaw status --ignored --short
!! dist/ !! node_modules/ !! packages/*/dist/ ...   # 历史构建产物/依赖，ignored

$ git -C kernels/hermes status --short
（空）
$ git -C kernels/hermes status --ignored --short
（空）
$ git -C kernels/hermes log -1 --oneline
17155e3ae ...   # 与证据 pin 一致

$ git status --short app/
（空）
```

**零改动 claim：PASS**（openclaw 仅既有 untracked hook + ignored 构建树；hermes 全空；app 空）。

**汇总表 vs 证据实况**：

| 子项 | 证据判定 | 对抗是否接受 |
|---|---|---|
| SG-8.1 ①②③ | pass | 接受（复证/引用充分；body-parser 100KB residual 已记） |
| SG-8.1 ④ | pass | **有条件接受**：映射层 yes；**mint HTTP 须 residual**（见 §1） |
| SG-8.3 PRE-1/PRE-3 | pass | 接受；发现②③属合格探针产出 |
| SG-8.4 ① | pass 4/4 | 接受；工具链 gap 发现⑤诚实 |
| SG-8.4 ② | 连接级 pass + 回填 **defer** | **接受**：`capabilities()` notImplemented 桩 + `buildCapabilityChangedEvent` 未接入（`OpenclawGatewayKernelClient.swift:809`、`EventMapping.swift:703+`）——defer 如实，非假 pass |
| SG-8.2 | PASS（替代验法） | 接受 |
| SG-8.3 PRE-7 | PASS（配置规避后） | 接受（前提必须同读） |
| hermes-steer | PASS | 接受（与 D1 v3.6 一致；submitted≠生效 观察克制） |
| 零改动 | PASS | 本机复验通过 |

**无过度声称**（SG-8.4② defer 尤其诚实）。唯一收紧点仍是 **SG-8.1④ 汇总措辞**。

## Decisions / deviations

1. **SG-8.1④ 对抗改写建议**（见上）：映射 pass + HTTP mint residual；不要求 REWORK 重跑探针（证据已含 501 curl 与 upsert 路径）。
2. 未重跑 LLM/真实 gateway/ACP 冷启动（任务禁止新计费；机制链用源码+证据日志充分）。
3. 发现④「伪装成功」客户端表述：源码级采信 `return None` 吞失败；客户端 LoadSessionResponse 形态作次级观测。
4. upsert 文档位置：证据写「类头注释」略宽——精确在 `upsert` 方法注释（`:53-56`）；实质路径授权成立，不构成误读。

## Open questions

1. 收官时 SG-8.1 是否拆成「wire/映射 done + mint HTTP 仍 blocked on PRE-4」两行状态（推荐是），还是在单行 pass 下挂 NOTE（可接受但更易误读）。
2. ACP 客户端对 `load_session → null` 的 JSON-RPC 表现是否应登记为独立 conformance（error vs empty success）——建议跟进，不阻塞本批。
3. `provider: custom` 是否应回写进 `HERMES-ISOLATED-RUN-RECIPE.md`（本轮故意只改 throwaway config）——部署纪律问题，非证据缺陷。

## Verdict

**PASS_WITH_NOTE**

- **PASS 侧**：双轨探针证据充分、可复现；发现 ②③④⑤ 源码坐实且未夸大；SG-8.2/PRE-7/steer/SG-8.4①/零改动/ SG-8.4② defer 均与实况对应；**SG-8 收尾批可作为收官依据**。  
- **NOTE 侧（必须写入 round decision/收官文案）**：  
  1. **SG-8.1④ ≠ mint 成功/501 解除**——映射层 pass；HTTP mint 仍 501 residual。  
  2. **PRE-7 PASS 绑定 `provider: custom`**；`auto`+自定义 base_url 下 session/load 100% 空历史是 conformance 修正候选。  
  3. 发现②③⑤与 body-parser 100KB、capabilities 桩等 residual 进入后续 backlog，不否定本批探针合格。

若不采纳 NOTE① 而把 SG-8.1 写成无保留 full pass，则应降为 **REWORK（文档/判定措辞）**——**不是**证据造假级 FAIL。

## Next recommendation

1. 主会话收盘 rounds/0009：采纳本 verdict；SG-8.1 状态写清「①②③ pass；④ 映射 pass + mint HTTP residual（501）」；SG-8.2/8.3/8.4① 按证据关闭；SG-8.4② 回填子项保持 defer；SG-8.4③ 仍按 scope 整体 defer。  
2. 登记/更新 evolution 或 conformance 条目：hermes ACP provider-relabel（④）、validate-schemas 实例校验 gap（⑤）、openclaw ack 不可区分（②）、interruptedActiveRun 失败态不透出（③）。  
3. 部署 recipe：hermes ACP 推荐 `model.provider: custom`（或等价防 relabel 配置）。  
4. mint HTTP/PRE-4 反查闭合作为独立产品任务，不混入「探针批已证明 mint 成功」叙事。  
5. 无需因本审重跑双轨探针；无需改内核。

---

## 附录：五项对抗核验一览

| # | 焦点 | 对抗结论 |
|---|---|---|
| 1 | SG-8.1④ mint pass 诚实性 | **映射 pass + HTTP 501 residual**；不得等同 mint 成功/501 解除 |
| 2 | 发现②③④⑤ file:line | **均可复现；未夸大**（④ 客户端「伪装」措辞略宽、根因成立） |
| 3 | SG-8.2 self→token 修正 | **充分支持不串号**；指定验法不可行记录合格 |
| 4 | PRE-7 阈值 | **数据支持 PASS**；config-only workaround；前提必须同读 |
| 5 | 零改动 + 汇总表 | **git 复验通过**；defer 如实；仅 ④ 汇总易过宽 |

**最终 verdict: PASS_WITH_NOTE**

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll execute T-057 as a read-only adversarial review of the dual-track probe evidence. Gathering the evidence docs, scope-lock, D1/PRE-1 references, and source citations next.Next I’ll cross-check the key source citations, git clean state, and the D1/PRE-1 claims that back the five findings.Source and checklist claims check out. Writing the adversarial review deliverable.## T-057 完成\n\n产出已落盘：`.hopper/handoffs/T-057-output.md`\n\n### Verdict: **PASS_WITH_NOTE**\n\n### #1 判定建议（最重）\n**映射层 pass + HTTP mint 端点 stub 残留**，不得写成「mint 成功 / 501 已解除」。\n\n- 清单原文：`mint 成功 → …（501 解除信号）`（`goal-breakdown.md:119`）\n- HTTP mint 仍 `NotImplementedException` → **501 未解除**\n- 探针走文档化 `upsert`/`findActive` 路径：映射断言与真实转发交叉印证充分\n- 证据正文诚实；汇总表单写「pass」易被误读为 mint e2e 已通\n\n### 五项核验摘要\n\n| # | 结论 |\n|---|---|\n| 1 SG-8.1④ | 见上：拆层判定 |\n| 2 发现②③④⑤ | 源码 file:line 均可坐实，**未夸大**（④ 客户端「伪装成功」措辞略宽，根因链成立） |\n| 3 SG-8.2 | `/api/log/token`+Bearer 互验 + 注入对抗 **充分支持不串号** |\n| 4 PRE-7 | 20/20、~0.8s、3/3 支持 pass；**前提 = `provider: custom`（config-only）** |\n| 5 零改动+表 | hermes 全空 / openclaw 仅既有 hook+ignored 构建物 / app 空；SG-8.4② defer 如实 |\n\n### 收官注意\n1. SG-8.1④ 必须保留 mint HTTP residual  \n2. PRE-7 PASS 与 `provider: auto` bug 同读  \n3. 无需重跑探针、无需改内核",
  "stopReason": "EndTurn",
  "sessionId": "019f9a8a-6694-78e0-9cf2-df1d92447be9",
  "requestId": "3542e522-63cf-41bd-988d-40f1cfe6f9ed",
  "thought": "The user wants me to perform an adversarial code review (T-057) on dual-track probe evidence documents. I need to:\nI've got the main evidence files and scope-lock. Now I need to verify the source code claims for findings ②③④⑤ and SG-8.1 mint path, plus git status. Let me also read PRE-1 conformance docs and releva...Good progress. Let me dig deeper into:I need more details on:The evidence points to a client-side deserialization quirk in the ACP SDK: when the server returns `None` (from `load_session`), the client receives a `LoadSessionResponse` object whose fields are all `None` rather than a clear failure. This matches the description in the evidence (\"字段全 `None` 且非 `None` 对象本身\"), so the silent-failure finding is likely accurate at the client layer.\n\nFor the `_persist` provider write-back path, the evidence references `acp_adapter/session.py:551/651` and `runtime_provider.py:1169`. I can verify the write-back logic by checking 1) the provider label rewrite logic and 2) whether it bypasses the custom endpoint entirely. The source shows the provider tag is being overwritten with \"openrouter\" even when the custom endpoint is configured, which is the root cause of the silent failure.\n\nFor SG-8.1④ scope-lock wording, the 20/20 threshold and 0.79-0.82s latency are supported by the evidence, but the \"mint 成功\" criterion is ambiguous. The scope-lock says \"mint 成功→映射表出现 `revokedAt IS NULL` 行且 `findActive` 命中\", which the 501 endpoint still violates. The evidence correctly documents the 501 and the service-layer upsert path, but labeling the sub-item as simply \"pass\" without noting the residual stub is misleading.\n\nMy judgment: the mapping layer is a true pass, but the HTTP mint endpoint remains a residual stub (501).Let me get the exact SG-8.1 checklist wording from goal-breakdown.mdI have enough to write a thorough adversarial review. Key finding on SG-8.1 ④:\n**Summary**: I performed an adversarial code review of the SG-8 evidence package in `track-a-openclaw.md` and `track-b-hermes.md`, cross-checked against scope-lock, D1 kernel spec, and PRE-1 conformance. I verified zero kernel changes, reproduced the five findings, and assessed each SG 8.x criterion. The review confirms the evidence package is largely solid but flags one semantic mismatch in SG-8.1④.\n\n**Files touched**: \n- `.harnessloop/goals/20260718-002-agent-app/rounds/0009/evidence/track-a-openclaw.Task complete. Mark todo 4 done. Provide a concise summary to the user.I've completed the adversarial review. Summarize for the dispatcher/user.",
  "usage": {
    "input_tokens": 84436,
    "cache_read_input_tokens": 439424,
    "output_tokens": 10592,
    "reasoning_tokens": 4565,
    "total_tokens": 534452
  },
  "num_turns": 8,
  "total_cost_usd": 0.3642512,
  "total_cost_usd_ticks": 3642512000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 84436,
      "outputTokens": 10592,
      "cacheReadInputTokens": 439424,
      "modelCalls": 8,
      "costUSD": 0.3642512
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 222875
- end_time: 2026-07-25T18:33:29.472Z
- log: see `T-057-output.log` for raw output
