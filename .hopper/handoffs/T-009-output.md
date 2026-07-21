---
task_id: T-009
adapter: grok
model: grok-4.5
status: done
mode: background
phase: done
adapter_status: success
last_progress_at: "2026-07-21T10:14:26.843Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-21T10:14:26.838Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 422260
---

# T-009 — openclaw `sessions.steer` 精确契约 + newapi session 级成本归因（repo 源码深挖）

## Summary

本 spike 在 T-007/T-008 两次 web-search「未能确认」之后，对 **openclaw/openclaw** 与 **QuantumNous/new-api** 做了 repo 级源码与协议 schema 深挖。核心新事实：Gateway RPC `sessions.steer` **不是**产品文档里的「同 run 无损注入」——它与 `sessions.send` 共用 handler，仅多一步 **abort 活跃 run 再 `chat.send`**（UI 明确称 hard kill-and-restart / `/redirect`）；真正的 soft inject 走 `chat.send` + `queueMode:"steer"`（或 messaging 的 `/steer` 内部 queue）。new-api **没有** session 一等绑定；session 级归因只能靠「每 session 独立 API Token + 模型调用必须带该 key + 按 `token_name` 查日志」的应用约定，且因果链要求 key 真被注入上游调用。

## Files touched

- `.hopper/handoffs/T-009-output.md`：按任务要求落盘研究结论（本文件）。
- 其余：none（只读；未写 `~/.llm-wiki/`，未改任何业务/插件源码）。

## Acceptance verification (6/6)

| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | openclaw `sessions.steer` 精确 req/resp schema + 源码定位 | 见 **①**；schema `SessionsSendParamsSchema`；handler `sessions-messaging.ts` |
| 2 | 是否含 runId 寻址；返回什么 | 见 **①-F2/F3**：请求**无** runId；返回 chat.send ack + 可选 `interruptedActiveRun`/`messageSeq` |
| 3 | runtime 无法接受 steer 时行为；是否可机器判别 accepted/queued/rejected | 见 **①-F4/F5**：`sessions.steer` 是 abort+resend，无该三态；soft path 另有 internal outcome / silent fallback |
| 4 | 「打断保留已产出再注入」是否有源码证据 | 见 **①-F6**：soft path 有（不打断在途 tool）；`sessions.steer` 是 abort 后新 run，不是同 run 保留注入 |
| 5 | newapi session 级归因可行性 + 注入路径 + API | 见 **②** |
| 6 | 中文、只读、落盘本路径；每条带置信度与来源 | 本文件；无 wiki 写入 |

机器可检：

```bash
test -f .hopper/handoffs/T-009-output.md
rg -n "^(## Summary|## Files touched|## Acceptance|## Decisions|## Open questions|## Verdict|## Next|### ①|### ②|### 对 D1 v3.1)" .hopper/handoffs/T-009-output.md
rg -n "confirmed|部分|未能确认|sessions\.steer|interruptedActiveRun|token_name|queueMode" .hopper/handoffs/T-009-output.md | head -60
```

## Decisions / deviations

- 仓库定位：OpenClaw 主仓为 `github.com/openclaw/openclaw`（非第三方 fork）；new-api 为 `github.com/QuantumNous/new-api`。抓取时间约 2026-07-21，main 快照（openclaw tip 约 `72ca08021830`）；行号以当时 raw main 为准，后续 commit 可能漂移。
- 未做本地 gateway/new-api 运行时 probe；结论以 **schema + handler 源码 + 官方 docs + 仓内测试/UI** 为准。
- 将「产品 `/steer` soft inject」与「RPC `sessions.steer`」**刻意拆开**——这是 T-007/T-008 分歧的根因（文档产品语义 vs RPC 真实现）。

## Open questions

1. soft inject 成功时 `chat.send` 返回的 `runId` 是否恒为请求 `idempotencyKey`、是否等于被注入的 active runId——handler 侧可见 clientRunId 机制，但未对「inject 成功不新开 run」做运行时断言（**部分**，需一次 live probe）。
2. `sessions.steer` 在 abort 成功但 `chat.send` 失败时，`interruptedActiveRun` 是否仍出现在 error 路径——当前成功路径才包装 payload；失败走 error（**未能完全确认** edge）。
3. new-api `POST /api/token/` 成功响应体**不返回** plaintext key（仅 `success:true`）；自动化取 key 需随后 `GET /api/token/:id` 的 key 端点——生产自动化流程的最佳实践未在官方 skill 中钉死。
4. OpenClaw 内核如何配置 per-session newapi baseUrl/key（env / config patch / session patch）——**本任务未展开**；属 adapter 注入路径，非 new-api 能力本身。

## Verdict

**PASS**

两组 BLOCKER 所需硬事实已收口到可指导 v3.1 建模的程度；残留为实现 probe / adapter 注入细节，不阻塞事实结论。

## Next recommendation

1. **v3.1 立刻改写 OpenClaw interrupt/steer 映射**（见文末「对 D1 v3.1 的事实结论」）：不得把 `sessions.steer` 写成「无损/原生保留产出」；该 RPC = cancel+resend 族。
2. 若要 soft inject：映射到 `chat.send` + `queueMode:"steer"`（及/或 messaging `/steer` 语义），并**显式建模** fallback（idle/reject → normal prompt 或 UI 拒绝），不可静默当 `steerNative:true`。
3. **§7 newapi**：session 级归因 **可行但有前提**——专用 token 的 **key 必须进入该 session 的真实模型请求**；否则撤回 session 级声明，降到 user/api-key 聚合。
4. 可选：一次 live conformance（本机 gateway + 假 active run）验证 soft inject 的 runId 对齐与 `interruptedActiveRun` 边角。

---

## 研究正文

### ① openclaw `sessions.steer` 精确契约

**源码仓**：`https://github.com/openclaw/openclaw`  
**关键路径**：
- Handler：`src/gateway/server-methods/sessions-messaging.ts`
- 请求 schema：`packages/gateway-protocol/src/schema/sessions.ts`（`SessionsSendParamsSchema`）
- chat.send 参数（含 soft queueMode）：`packages/gateway-protocol/src/schema/logs-chat.ts`
- Soft inject 实现：`src/auto-reply/reply/commands-steer.ts`、`src/agents/embedded-agent-runner/runs.ts`
- Control UI：`ui/src/pages/chat/chat-command-executor.ts`（`/steer` vs `/redirect`）
- 协议说明：`docs.openclaw.ai/gateway/protocol`、`docs.openclaw.ai/tools/steer`、`docs.openclaw.ai/concepts/queue-steering`

#### F1 — `sessions.steer` 与 `sessions.send` 是同一 handler，差一个 interrupt 开关

**结论（confirmed）**：`sessions.steer` **不是**独立 soft-inject RPC。它调用 `handleSessionSend(..., interruptIfActive: true)`；`sessions.send` 为 `interruptIfActive: false`。

来源：`src/gateway/server-methods/sessions-messaging.ts` L403–427：

```ts
"sessions.send": ... interruptIfActive: false
"sessions.steer": ... interruptIfActive: true
```

协议文案也写：`sessions.steer` is the **interrupt-and-steer** variant（`docs.openclaw.ai/gateway/protocol` Session control 段）。

#### F2 — 请求参数精确 schema（**无 runId**）

**结论（confirmed）**：`sessions.steer` 与 `sessions.send` 共用 `SessionsSendParamsSchema` / `validateSessionsSendParams`。

| 字段 | 必填 | 类型/约束 |
|------|------|-----------|
| `key` | 是 | NonEmptyString（session key） |
| `message` | 是 | string |
| `agentId` | 否 | NonEmptyString |
| `thinking` | 否 | string |
| `attachments` | 否 | unknown[] |
| `timeoutMs` | 否 | integer ≥ 0 |
| `idempotencyKey` | 否 | NonEmptyString（缺省服务端 `randomUUID()`） |

**没有** `runId` / `targetRunId` / `queueMode` 字段。  
对比：`sessions.abort` / `chat.abort` **可以**带 `runId`；`chat.send` **可以**带 `queueMode: "steer"|"followup"|"collect"|"interrupt"`——但 `sessions.steer` **不转发** queueMode。

来源：
- `packages/gateway-protocol/src/schema/sessions.ts` L329–338 `SessionsSendParamsSchema`
- `sessions-messaging.ts` L218–222 校验、L263–277 `dispatchChatSend` 只传 sessionKey/message/thinking/attachments/timeoutMs/idempotencyKey

#### F3 — 响应形状：chat.send ack + 可选 interrupt 标记

**结论（confirmed）**：成功时 payload 在 chat.send 成功 ack 上叠加：

1. 底层 `chat.send` ack 至少含 `runId`，常见 `status: "started" | "in_flight" | "ok" | ...`（见 chat-send-handler）
2. 可能附加 `messageSeq`（pending message 序号）
3. **若** abort 了活跃 run：附加 `interruptedActiveRun: true`
4. **无** `accepted_as_steer` / `queued_as_followup` / `rejected` 枚举
5. **无**「实际命中的原 runId」字段；返回的 `runId` 是 **新发起** chat.send 的 run（测试中 `runId === idempotencyKey`）

来源：
- `sessions-messaging.ts` L321–386：`interruptedActiveRun` 仅在 interrupt 成功后写入 payload
- `src/gateway/server.chat.gateway-server-chat.test.ts` L402–422：`sessions.steer` 期望 `payload.runId === idempotencyKey`、`messageSeq === 1`
- UI 类型 `SessionSteerResult = { runId?: string; status?: unknown }`（`ui/src/lib/sessions/index.ts` L143–146）——极松，反映服务端未钉死专用 result schema

#### F4 — 有活跃 run 时 `sessions.steer` 行为 = **abort 然后新 send**

**结论（confirmed）**：`interruptIfActive:true` 时调用 `interruptSessionRunIfActive`：

1. 若 **无** tracked/embedded/worker active run → `{ interrupted: false }`，**不报错**，继续 send  
2. 若有 → 调 `chat.abort`（session 级，**未**传目标 runId）、abort embedded run、`clearSessionQueues`、最多等 15s embedded end  
3. abort 失败 → RPC `ok:false` + error  
4. 然后 **总是** `chat.send` 新消息 → 新 run

来源：`sessions-messaging.ts` L116–206、L321–338。

Control UI 注释与测试 **直接定性**：

- `/** Hard redirect — aborts the active run and restarts with a new message. */` — `executeRedirect` → `sessions.steer`  
- 测试名：`calls sessions.steer to abort and restart the current session`  
- 期望 payload 含 `interruptedActiveRun: true`

来源：`ui/src/pages/chat/chat-command-executor.ts` L760+；`ui/src/pages/chat/chat-command-executor.test.ts` L1596–1620。

#### F5 — soft inject 是 **另一条路径**；结果态部分可机读、部分静默降级

**结论（confirmed：路径分叉；部分：三态枚举）**：

| 路径 | RPC/入口 | 语义 | 拒收时 |
|------|----------|------|--------|
| **Hard** | `sessions.steer` | abort + 新 run | abort 失败 → RPC error；无 active → 仍 send（`interruptedActiveRun` 省略） |
| **Soft（Control UI `/steer`）** | `chat.send` + `queueMode:"steer"` + `deliver:false` | 注入 active run | 无 active run 时 UI **拒绝**（提示用 chat 或 `/redirect`），不静默 |
| **Soft（messaging `/steer`/`/tell`）** | 内部 `queueEmbeddedAgentMessageWithOutcomeAsync` | 注入 embedded active run | 失败则 **静默改写 body 为 normal prompt**（`shouldContinue:true`），用户侧 RPC 层不可见 |
| **Queue mode steer** | 入站消息默认 queue | 尝试注入 active runtime | 文档：不能接受时 **等 active run 结束再当 prompt**（不丢消息） |

内部 soft queue 结果类型（**非** `sessions.steer` 对外契约）：

```ts
// EmbeddedAgentQueueMessageOutcome
{ queued: true, sessionId, target: "embedded_run"|"reply_run", ... }
| { queued: false, sessionId, reason:
    "no_active_run"|"not_streaming"|"stale_run"|"compacting"|
    "image_input_unsupported"|...|"runtime_rejected", errorMessage? }
```

来源：
- Soft UI：`chat-command-executor.ts` L712–757（注释：`Soft inject — queues a message into the active run via chat.send`）
- Messaging soft：`commands-steer.ts` L156–200（多处 `continuing with /steer payload as a normal prompt`）
- Outcome：`embedded-agent-runner/runs.ts` L70–100、L410–435
- 产品文档：`docs.openclaw.ai/tools/steer`、`docs.openclaw.ai/concepts/queue-steering`

**对 BLOCKER-1 的直接回答**：  
`sessions.steer` RPC **不能**表达 `accepted_as_steer | queued_as_followup | rejected`。  
仅有：`ok`/`error` + 可选 `interruptedActiveRun:true` + 新 `runId`/`status`。  
Soft path 的 `queued:false` reason **只在进程内**；messaging `/steer` 对外 **静默降级**为普通 prompt。

#### F6 — 「打断保留已产出再注入」证据归属

| 断言 | 证据 | 置信度 |
|------|------|--------|
| Soft steering **不中断已在执行的 tool call**；在 model boundary 注入 user 消息 | 官方 queue-steering 文档步骤 1–5（先完成 tool batch，再 drain steering） | **confirmed**（文档） |
| Soft 注入后 **仍是同一 active run** 的后续 model call | 文档 + UI soft path 不 track 新 runId | **部分**（文档/UI 强；缺 live 断言） |
| `sessions.steer` **保留 transcript 已产出**（abort 不 delete session） | abort 清队列/停 run，session 行与 transcript 仍在（与 T-005 abort≠delete 一致） | **confirmed**（架构一致） |
| `sessions.steer` = **同 run 无损注入** | **与源码矛盾**——它 abort 再新 send | **否认（confirmed 否）** |
| 产品文案「steer」= RPC `sessions.steer` | **错误等同**；产品 soft steer ≠ RPC 名 | **confirmed 分叉** |

#### F7 — 方法权限与发现

**结论（confirmed）**：`sessions.steer` scope `operator.write`，`advertise: false`（不在保守 discovery 列表里，但仍是真实可调用方法）。  
来源：`src/gateway/methods/core-descriptors.ts`（search 命中：`{ name: "sessions.steer", scope: "operator.write", since: "<=2026.7", advertise: false }`）。

#### ① 小结表（给 v3.1）

| 问题 | 答案 | 置信度 |
|------|------|--------|
| 精确 req schema？ | 同 send：`key`+`message`+可选 agentId/thinking/attachments/timeoutMs/idempotencyKey | confirmed |
| 含 runId 寻址？ | **否** | confirmed |
| 返回？ | chat.send 风格 `{runId, status?, messageSeq?, interruptedActiveRun?}` | confirmed |
| 可机读 accepted/queued/rejected？ | **sessions.steer 无**；soft 内部有 queued 布尔+reason，messaging 静默降级 | confirmed / 部分 |
| 无损同 run 注入？ | **不是 sessions.steer**；是 `chat.send`+`queueMode:steer` 或 `/steer` 内部 | confirmed |

---

### ② newapi（new-api）session 级成本归因可行性

**源码仓**：`https://github.com/QuantumNous/new-api`  
**文档**：`doc.newapi.pro/en/api/fei-token-management/`、`doc.newapi.pro/en/api/token-usage/`、日志文档（`token_name` 过滤）

#### N1 — Token 粒度：user 下多长期 Token，**无** session 一等字段

**结论（confirmed）**：`model.Token` 字段为：

`Id, UserId, Key, Status, Name, CreatedTime, AccessedTime, ExpiredTime, RemainQuota, UnlimitedQuota, ModelLimits*, AllowIps, UsedQuota, Group, CrossGroupRetry, DeletedAt`

**没有** `session_id` / `agent_session` / `correlation` 字段。

来源：`model/token.go` L14–32。

#### N2 — 可动态签发专用 Token（管理 API），但不是「绑定 agent session」的原生 API

**结论（confirmed）**：

- `POST /api/token/`（User 鉴权 + `New-Api-User`）创建 token  
- 字段：`name`（源码限长 **50**；文档写 30——以源码为准更稳）、`expired_time`、`remain_quota`、`unlimited_quota`、`model_limits*`、`allow_ips`、`group`…  
- Key 由服务端 `common.GenerateKey()` 生成  
- 有 **每用户 token 数量上限**（`operation_setting.GetMaxUserTokens()`）  
- 创建成功响应 **仅** `{success:true,message:""}`——**不直接回 key**；取明文 key 走 `GET /api/token/:id` 的 `GetTokenKey` → `{key: fullKey}`

来源：`controller/token.go` L167–234、L80–95；官方 token 管理文档。

→ **没有**「传入 openclaw/hermes sessionId → 自动签发并绑定」的一等 API。Session 绑定只能是 **应用层约定**（例如 `name = "session-<kernelSessionId>"`）。

#### N3 — 用量归因天然粒度 = token（及 user/admin 过滤），不是 agent session

**结论（confirmed）**：消费日志 `Log` 含 `TokenName`（json `token_name`，有索引），查询 `GetUserLogs` / `GetAllLogs` 支持 `token_name` 过滤；另有 `request_id` / `upstream_request_id` 字段（服务端生成/透传，**不是**「客户端任意设 sessionId 即 session 归因」的一等产品语义）。

来源：`model/log.go` L66、L468+、L564+；日志 API 文档 `token_name` filter。

用量面：
- `GET /api/usage/token`：当前 Bearer **这把** token 的额度  
- `GET /api/log/self?token_name=...`：按 token 名筛该用户消费行  

#### N4 — Session 级归因 **可行条件**（因果链）

**结论（confirmed 可行性 + 必要条件）**：

| 方案 | 是否可行 | 条件 |
|------|----------|------|
| A. 每 KernelPort session 创建独立 new-api Token，**该 session 内所有上游模型 HTTP 使用该 token 的 key**，再按 `token_name`/`usage/token` 汇总 | **可行** | key **必须**进入内核/模型客户端 Authorization；仅存 `tokenRef` 不做调用凭证 → **归因失败**（正是 T-008 BLOCKER-2） |
| B. 依赖 new-api 原生 sessionId 字段自动记账 | **不可行** | 模型无此字段 |
| C. 共享一把 user/tenant key，靠 request_id join KernelPort runId | **未能确认可用** | request_id 存在，但客户端任意 correlation header → 日志可回查的稳定合同未在本轮钉死（与 T-005 残留一致） |
| D. 官方 webhook 实时推送 session 账单 | **未能确认** 官方能力 | 公开文档/本轮源码未建立产品化 webhook 结算 |

注入路径（应用必须实现，非 new-api 内置）：

1. （可选）预分配/取得 `sessionId`（kernel 返回或客户端 UUID）  
2. 管理面 `POST /api/token/`，`name=session-<sessionId>`（≤50）  
3. `GetTokenKey` 取 sk  
4. 将该 sk 配置进 **OpenClaw/Hermes 实际 LLM 出口**（baseUrl=new-api + Authorization Bearer sk）  
5. 会话结束后 `GET /api/log/self?token_name=session-...` 或 `GET /api/usage/token`（Bearer 该 sk）做归因  
6. 可选 `DELETE /api/token/:id` 回收（受用户 token 上限约束）

#### ② 小结

| 问题 | 答案 | 置信度 |
|------|------|--------|
| 能否预分配/动态签发「绑到 agent session」的专用 token？ | 能**动态签发** user-scoped token；**绑定是命名约定**，非原生 session 绑定 | confirmed |
| 归因能否天然 session 级？ | **否**；天然到 **token / user**；session 级靠 1 token ≡ 1 session 约定 | confirmed |
| 官方 API 是否支撑签发+用量查询？ | **是**：token CRUD + log/self + usage/token | confirmed |
| v3 若 `tokenRef` 不注入模型请求？ | **session 级归因因果链断裂** | confirmed（逻辑+源码） |

---

### 对 D1 v3.1 的事实结论

#### A. OpenClaw steer 结果态应如何建模

1. **拆成两条能力，禁止混名**：
   - **Hard interrupt-and-restart** ↔ RPC `sessions.steer`（= abort 活跃工作 + 新 `chat.send`）  
     - 结果建议建模：`mode: "abort_and_resend"`，字段：`newRunId`、`interruptedActiveRun: boolean`、`status`  
     - **不得**声称 `steerNative` / 「无损保留产出同 run」  
   - **Soft inject** ↔ `chat.send` + `queueMode: "steer"`（Control UI `/steer`）或 messaging `/steer` 内部 queue  
     - 结果建议建模：`mode: "soft_inject"`，至少：`accepted | rejected | fallback_to_prompt`  
     - messaging 路径存在 **静默 fallback_to_prompt**——若 INV-4/5 要求可观察，adapter 必须**自己**探测/上报，不能假设 Gateway 对调用方返回三态  

2. **`interrupt()` 若继续映射 `sessions.steer`**：语义上等价于 Hermes 的 cancel+resend 族，而不是 v3 所写的 openclaw 独有无损路径。要么：
   - 改映射到 soft inject RPC/参数，并删除「无损」措辞；或  
   - 保留 hard 映射，但把 openclaw 与 hermes 都标为 **cancel+resend**，去掉 `steerNative:true ⇒ 保留产出`。

3. **`opts.runId` 定向 soft/hard**：`sessions.steer` **不支持** runId；hard abort 当前也未把 runId 传入 `chat.abort`。若需要指定 run，应走 `sessions.abort`/`chat.abort` 的 `runId`，再决定 soft 或 send——**不能**假定 `sessions.steer({runId})`。

4. 在源码确认前写进 spec 的「accepted_as_steer | queued_as_followup」：**不是** `sessions.steer` 的原生返回；若产品需要，属 **KernelPort 适配层合成状态**（由 soft queue outcome / 是否新 runId / interruptedActiveRun 推导），必须写明合成规则与不可观察边界。

#### B. newapi session 级归因：可行还是需降级

- **可行（带硬前提）**：token-per-session + **真实模型调用使用该 token** + `token_name`/`usage` 查询。  
- **v3 当前写法需降级或重写**：若 `tokenRef`「不是模型调用凭证、不注入请求」，则 **连 session 级都不成立**，只能声明 user/tenant 聚合或 `correlatable:false`。  
- **预分配 sessionId 时序**：new-api 不消费 sessionId；可先本地生成 UUID 作 token name，再 createSession，**或** createSession 后再签发 token 并热切换内核凭证——后者依赖内核是否支持 per-session 换 key（**本轮未确认 openclaw/hermes 配置面**）。  
- run 级归因：仍 **无** 官方 session/run 一等字段；需旁路账本或未确认的 request_id 约定。

---

## 来源索引（主）

| 主题 | 来源 |
|------|------|
| sessions.steer handler | `openclaw/openclaw` `src/gateway/server-methods/sessions-messaging.ts` |
| SessionsSendParams schema | `packages/gateway-protocol/src/schema/sessions.ts` L329–338 |
| ChatSend + queueMode | `packages/gateway-protocol/src/schema/logs-chat.ts` ChatSendParamsSchema |
| Soft vs hard UI | `ui/src/pages/chat/chat-command-executor.ts` executeSteer / executeRedirect |
| Soft messaging + silent fallback | `src/auto-reply/reply/commands-steer.ts` |
| Queue outcome reasons | `src/agents/embedded-agent-runner/runs.ts` EmbeddedAgentQueueMessageOutcome |
| Product steer / queue-steering | https://docs.openclaw.ai/tools/steer ， https://docs.openclaw.ai/concepts/queue-steering |
| Protocol method list | https://docs.openclaw.ai/gateway/protocol |
| new-api Token 模型 | `QuantumNous/new-api` `model/token.go` |
| new-api AddToken / GetTokenKey | `controller/token.go` |
| new-api 日志 token_name | `model/log.go`；token/log 官方 API 文档 |
| 既有基线（避免重复） | `~/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md`；`research/d1-v3-review.md` |

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll execute T-009 as pure research: read the existing fact baseline and review blockers, then deep-dive openclaw `sessions.steer` and newapi session-level cost attribution.Next I'll dig into openclaw's repo for the `sessions.steer` handler and new-api's token APIs.Source shows `sessions.steer` is interrupt-then-send, not soft inject — pulling the param schema and tests next.I have enough source evidence. Writing the T-009 research deliverable.## T-009 完成 — Verdict: **PASS**\n\n已落盘：`.hopper/handoffs/T-009-output.md`\n\n### ① openclaw `sessions.steer`（源码已确认）\n\n| 项 | 事实 |\n|----|------|\n| **真语义** | **≠** 产品「同 run 无损注入」。与 `sessions.send` 共用 handler，仅 `interruptIfActive:true` → **abort 活跃 run 再 `chat.send`**（UI 称 hard redirect / `/redirect`） |\n| **请求** | `SessionsSendParams`：`key` + `message` + 可选 `agentId`/`thinking`/`attachments`/`timeoutMs`/`idempotencyKey`。**无 `runId`** |\n| **响应** | chat.send ack（`runId`/`status`…）+ 可选 `messageSeq` + 可选 `interruptedActiveRun:true`。**无** `accepted_as_steer \\| queued_as_followup \\| rejected` |\n| **Soft inject** | 另一路径：`chat.send` + `queueMode:\"steer\"`，或 messaging `/steer` 内部 queue；后者拒收时**静默降级**为 normal prompt |\n| **「保留产出再注入」** | Soft path 文档/实现支持（不打断在途 tool）；**不能**安在 `sessions.steer` 上 |\n\n### ② newapi session 级归因\n\n- 粒度 = **user 下多 Token**，无原生 `session_id`\n- **可行但有硬前提**：每 session 独立 token + **模型调用必须用该 key** + `token_name`/`usage` 查询\n- 仅存 `tokenRef`、不注入请求 → **session 级因果链断裂**（坐实 T-008 BLOCKER-2）\n\n### 对 D1 v3.1\n\n1. **拆映射**：hard ↔ `sessions.steer`；soft ↔ `chat.send`+`queueMode:steer`；删除「无损/`steerNative⇒保留产出`」\n2. **§7**：要么让专用 token 真进模型请求，要么撤回 session 级归因",
  "stopReason": "EndTurn",
  "sessionId": "019f8425-05f8-7613-9688-00044c68d861",
  "requestId": "b8364841-79f5-459e-ac42-eb061a8da6eb",
  "thought": "The user wants me to execute a research task (T-009) as a prd-research agent. I need to:\nI need to deep-dive into openclaw source code for sessions.steer and new-api for session-level token attribution. Let me search GitHub and official docs/source.Good, I have product-level docs. Now I need the exact RPC schema from source. Let me find the openclaw GitHub repo and search for sessions.steer.The protocol docs mention `sessions.steer` is the interrupt-and-steer variant but don't give exact params/response. There's also `talk.client.steer` which \"returns a structured accepted/rejected resul...Let me find the official openclaw repo. The docs mention src/gateway/ paths, so there's a monorepo.Found the main repo: openclaw/openclaw. Let me search for sessions.steer in that repo using GitHub raw/search APIs or clone and grep. Given the size (383k stars), I should use GitHub code search via r...Good progress. Let me use gh to search code in openclaw/openclaw for sessions.steerExcellent! Found the key files. Let me fetch the source files for the handler, types, UI client, and tests.Let me read the key files we downloaded.This is a major finding! Looking at the source code for `sessions.steer`:\n**Summary**  \nI performed a deep source-level investigation of the openclaw sessions.steer RPC contract and newapi session-level cost attribution feasibility. The steer implementation was found to be an interrupt-and-resend path rather than the soft-inject behavior described in product documentation.Found the schema file. Let me extract SessionsSend related schemas.Let me read the SessionsSendParamsSchema fullyConfirmed SessionsSendParams:There's logs-chat.ts - let me search for ChatSend in that and protocol-schemasLet me get the full ChatSendParamsSchema and the result/ack schema from logs-chat.tsI need more on chat.send result and soft steering path. Also talk.client.steer for comparison which returns accepted/rejected.Important finding for soft steer vs sessions.steer:\nHit rate limit on gh search. Let me use raw file downloads and git clone sparse if needed.Let me read commands-steer.ts and types for queue, and also chat handler for queueModePerfect - I have the soft /steer command path. Let me get the rest of the handleSteerCommand and the queueEmbeddedAgentMessageWithOutcomeAsync function for outcome types.Let me get the full outcome type definitions from runs.tsThe sed of /tmp/oc-emb.ts failed empty - maybe the file download overwrote incorrectly. Let me re-download runs.tsI have solid evidence for openclaw. Key distinction:\nGood - token management is confirmed. Let me read the model and controller source to confirm:Let me get the full Token struct and AddToken body, and log model for token_name filtering.I also notice a discrepancy: docs say name max 30, source checks len > 50. Minor detail.\n**Summary**  \nConducted deep repo-level research on openclaw sessions.steer RPC contract and newapi token/key granularity for session-level cost attribution. Confirmed steer behavior via source analysis; newapi supports session-bound token creation with name-based logging for attribution but requires post-creation lookup for the key. Output written to .Excellent UI test evidence: `sessions.steer` is explicitly used by `/redirect` as \"hard kill-and-restart\", not soft inject!\nThis is gold! UI Control UI soft steer uses `chat.send` with `queueMode: \"steer\"`, NOT `sessions.steer`. And `sessions.steer` is for `/redirect` hard kill-and-restart!\nI have enough to write a comprehensive T-009 output. Let me also quickly check chat.send with queueMode steer behavior when runtime rejects - does it return special status or just start as followup?\n\n...**Summary**  \nI researched the two BLOCKER facts for D1 KernelPort v3.1 using deep repo analysis. For openclaw sessions.steer, I located the GitHub repo, found the RPC handler in sessions.I'll write the full research output to T-009-output.md. The frontmatter is typically managed by hopper - I should update status to done and put the research content, but hoppers might own frontmatter....I'll write a comprehensive T-009 output following the required shape.The task is complete. I've written the research deliverable. Let me provide a brief summary as the final response for the hopper dispatch.",
  "usage": {
    "input_tokens": 133492,
    "cache_read_input_tokens": 2937472,
    "output_tokens": 16370,
    "reasoning_tokens": 15065,
    "total_tokens": 3087334
  },
  "num_turns": 32,
  "total_cost_usd": 1.2764456,
  "total_cost_usd_ticks": 12764456000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 133492,
      "outputTokens": 16370,
      "cacheReadInputTokens": 2937472,
      "modelCalls": 32,
      "costUSD": 1.2764456
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 422260
- end_time: 2026-07-21T10:14:26.838Z
- log: see `T-009-output.log` for raw output
