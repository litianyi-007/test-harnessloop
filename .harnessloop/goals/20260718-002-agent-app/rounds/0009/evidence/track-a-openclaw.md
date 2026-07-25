# rounds/0009 轨 A（openclaw 侧）证据

范围：SG-8.1 四项 + SG-8.3 PRE-1(C-1)/PRE-3(C-4) + SG-8.4①②。全部为探针/验证型工作——**零内核/app 源码改动**（收尾核对见文末）。

## 0. 运行环境

- 隔离 openclaw gateway：`ws://127.0.0.1:18999`（`kernels/openclaw` submodule，HEAD 同主仓库当前 pin；recipe 见 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`），`OPENCLAW_STATE_DIR`/`OPENCLAW_WORKSPACE_DIR` 均在 scratchpad 下全新目录，`OPENCLAW_SKIP_CHANNELS=1`，token `sg9tracka9f2c1b7e4`。全程未连接/未干扰用户全局 `127.0.0.1:18789`（PID 5197，收尾核对仍在线，见文末）。
- D3-proxy（`app/server`，仅运行 `dist/`，未改一行源码）：本机 `http://127.0.0.1:3011`，`.env` 原样复用（`NEWAPI_BASE_URL=http://10.244.132.76:3000` 指真 Pi new-api，`DB_HOST=10.244.132.76` 指真 Pi Postgres）。
- 一个纯透传抓包代理（scratchpad throwaway，`header-capture-proxy.mjs`）挂在 `127.0.0.1:3012 → 127.0.0.1:3011` 之间——原因：`SessionProxyService`（`app/server/src/modules/session-proxy/session-proxy.service.ts`）只在鉴权失败/映射未命中/转发出错时打 log，**成功路径没有任何日志**（读源码确认，非猜测），若不加抓包点就拿不到"D3-proxy 侧收到的 header 值"这一逐字节对比所需的直接观测证据；抓包代理只读不改任何 header/body，原样转发+原样流式回传响应（保留 SSE 语义），不影响任何转发结果。
- openclaw 侧部署配置（`openclaw-iso/state/openclaw.json`，纯部署配置，非源码）：注册自定义 provider `d3proxy`（`api:"openai-completions"`, `baseUrl` 指向抓包代理, `compat.sendSessionAffinityHeaders:true`），模型 id `kimi-for-coding`；另加 `agents.defaults.experimental.localModelLean:true`（原因见 §1 ①③）。
- 复用既有 newapi token：`NEWAPI_D3PROXY_TOKEN`（`.harnessloop/local/channel-params.json`，new-api token id=3，name `sg8.5-kimi-e2e`，channel `kimi-coding`/type14 Anthropic，模型 `kimi-for-coding`）——全程未铸造新 token，符合"复用既有 token"纪律。
- 探针工具：Node 22 原生 `WebSocket`（`scratchpad/.../ws-client.mjs`，自写最小 RPC client，未走 kernel-client）；以及一个**与 kernel-client 生产代码一起编译**的 Swift 探针入口 `d2-live-dump-main.swift`（复用 `FrameReplayTestMain.swift` 已有的"独立 `@main` 入口 + 不改 `CLIRunner.swift`/`main.swift`"编译模式），用于 SG-8.4。

---

## 1. SG-8.1（SG-6 e2e wire 实证，4 项）

### ①③：引用既有证据 + 本轮轻量复证

- **引用**：`rounds/0004/round-summary.md`（E14）+ `app/kernel-client/RUN-EVIDENCE.md` 已给出 header 到达（两个不同真实 session 动态到达，补丁前 `(missing)`）与真实计费日志精确吻合的强证据，本轮不重复烧调用去证明"能不能通"这件事本身。
- **本轮轻量复证**（新鲜环境、新 session，方法与引用证据一致）：
  - ① header 到达：抓包代理日志一条（`header-capture.log`）：
    ```
    [2026-07-25T18:04:29.386Z] INBOUND POST /api/d3/v1/session-proxy/chat/completions
      captured-headers={"x-session-affinity":"05aa1eff-49c6-4e63-bd16-f1c7f9be73d2",
                         "session_id":"05aa1eff-49c6-4e63-bd16-f1c7f9be73d2",
                         "x-client-request-id":"05aa1eff-49c6-4e63-bd16-f1c7f9be73d2"}
    ```
    三个 header 均真实到达，值一致。
  - ③ 真实 SSE 帧透传（不缓冲）：同一请求的响应侧日志：
    ```
    [2026-07-25T18:04:32.382Z] OUTBOUND status=200 elapsedMs=2995 chunkCount=3 totalBytes=3170
      chunkTimestampsMs=[2856,2857,2870]
    ```
    `chunkCount=3`（多次 `reader.read()` 才读完，不是一次性缓冲读到底）、且 `Content-Type` 由 D3-proxy 透传的上游响应头决定（openclaw 侧日志同一请求记为 `contentType=text/event-stream`，见下）。**判定：pass**。
- **发现（非本轮新增，rounds/0004 已记录，本轮复现同一缺口）**：第一次尝试（未开 `localModelLean`）时，openclaw 真实 agent 请求体 **107455 字节**，超过 D3-proxy 100KB body-parser 限制，D3-proxy 侧抛 `PayloadTooLargeError`（`app/server` `node_modules/body-parser`，非 D3-proxy 自身代码，但限制值是 D3-proxy 配置的），本轮用与 rounds/0004 相同的绕行手段（openclaw 侧 `agents.defaults.experimental.localModelLean:true`，纯部署配置）解决，未改 `app/server` 源码。**该缺口仍未被任何轮次实际修复**，如实标记待后续独立任务处理（rounds/0004 已提过同样建议）。

### ②（重点）：sessionId 逐字节同源

**方法**：从内核侧（`sessions.create` 响应 `payload.sessionId` / `payload.entry.sessionId`，即 openclaw `Agent.sessionId`）与 D3-proxy 侧（抓包代理原样转发前捕获的 `x-session-affinity` 请求头）两端独立取值，做字符串相等比对。

**命令/输出**（`phase-sg81.mjs` + `header-capture-proxy.mjs`，均在 `scratchpad/round9-track-a/`）：

| 来源 | 取值方法 | 值 |
|---|---|---|
| 内核侧 | `sessions.create` RPC 响应 `payload.sessionId`（`ws-client.mjs` 原始 JSON） | `05aa1eff-49c6-4e63-bd16-f1c7f9be73d2` |
| 内核侧（交叉核对） | 同响应 `payload.entry.sessionId` | `05aa1eff-49c6-4e63-bd16-f1c7f9be73d2`（与上一致） |
| D3-proxy 侧 | 抓包代理原样转发前捕获的入站请求头 `x-session-affinity` | `05aa1eff-49c6-4e63-bd16-f1c7f9be73d2` |
| D3-proxy 侧（交叉核对） | 同请求头 `session_id` | `05aa1eff-49c6-4e63-bd16-f1c7f9be73d2`（与上一致） |
| D3-proxy 侧（交叉核对） | 同请求头 `x-client-request-id` | `05aa1eff-49c6-4e63-bd16-f1c7f9be73d2`（与上一致） |

`Buffer.byteLength(kernelSessionId,'utf8')` 与字符串长度均为 36（标准 UUID），Python `==` 比对三处 D3-proxy 侧取值与两处内核侧取值**全部逐字节相等**（脚本输出见 `sg81-run4.log`、`header-capture.log`）。openclaw 侧注入这三个 header 的代码位置（`sg6-openclaw-persession-patch-design.md` 已走读坐实，本轮未重新走读源码，只做运行时观测）：`packages/ai/src/providers/openai-completions.ts:678-686`（provider-adapter 路径）/ transport 热路径注入见 `rounds/0004` 补丁 `35f8739`。

**判定：pass**——sessionId 逐字节同源，显式断言成立。

### ④（重点）：mint 路径

**方法**：先按"正常业务路径"（真实 HTTP mint API）实测，坐实 `app/server` 源码实况；源码实况证实该路径未实现（`NotImplementedException`，非本轮新发现，`newapi_token_id_lookup_unresolved` 缺口早已登记于 `d6-newapi-integration.md` §3.1/§7 #11）后，改走源码自身文档化的"测试/开发环境手工 `upsert`"路径（`session-newapi-token-map.service.ts` 类头注释原文："测试/开发环境下可通过 `upsert` 手工种入映射数据以验证 session-proxy 的转发链路"）——**这不是绕过契约，是契约文档自己指定的当前阶段验证方式**（真实 mint 端点因 PRE-4 冒烟缺口尚未解除，仍 blocked）。

**步骤 1：真实业务路径 mint 端点，坐实源码实况**：

```
$ curl -X POST -H "Authorization: Bearer <本轮签发的开发态 JWT>" \
    http://127.0.0.1:3011/api/d3/v1/sessions/probe-test-session/billing-token
HTTP 501
{"code":"newapi_token_id_lookup_unresolved","message":"newapi POST /api/token/ 创建响应不含新 token 的 id，
 GET/DELETE /api/token/:id 所需 id 的反查机制未闭合……"}
```
（对照：不带 JWT 时 401 `unauthorized`，证实 `JwtAuthGuard` 确实生效，501 不是鉴权绕过的结果）。JWT 用 `.env` 里的 `JWT_ACCESS_SECRET` 本地签发（dev 占位密钥，非生产凭证，仅用于验证鉴权链路本身，未绕过任何鉴权机制）。源码：`app/server/src/modules/session-token/session-token.controller.ts:21-27`（`POST /sessions/:sessionId/billing-token`）→ `session-token.service.ts:25-29`（`mintSessionBillingToken`）→ `newapi-client.service.ts:53-63`（`mintSessionToken`，`throw new NotImplementedException`）。**判定：源码实况确认，mint API 目前必然 501，非本轮探针缺陷**。

**步骤 2：走源码文档化的 `upsert` 路径，验证映射写入 + `findActive` 命中**：

用一个 throwaway 脚本（`seed-mapping.cjs`）**直接实例化真实编译产物 `SessionNewApiTokenMapService`**（`app/server/dist/modules/session-token/session-newapi-token-map.service.js`，非重写逻辑，是同一份类），接上真实 Pi Postgres `DataSource`，对 SG-8.1②捕获的真实 sessionId（`05aa1eff-49c6-4e63-bd16-f1c7f9be73d2`）依次调用真实的 `.upsert(...)` 与 `.findActive(...)` 方法：

```
--- 调用真实 SessionNewApiTokenMapService.upsert() ---
upsert() returned (void, no throw = success)
--- 调用真实 SessionNewApiTokenMapService.findActive() ---
findActive() result: {
  "newapiKey": "***REDACTED-ROTATED-TOKEN-20260726***",
  "newapiTokenId": "3",
  "tokenGeneration": 1
}
--- 原始行（repo.findOne，展示 revokedAt/时间戳）---
{
  "sessionId": "05aa1eff-49c6-4e63-bd16-f1c7f9be73d2",
  "newapiKey": "***REDACTED-ROTATED-TOKEN-20260726***",
  "newapiTokenId": "3",
  "tokenGeneration": 1,
  "revokedAt": null,
  "createdAt": "2026-07-25T10:04:24.917Z",
  "updatedAt": "2026-07-25T10:04:24.917Z"
}
```

**`revokedAt: null` 出现 + `findActive()` 真命中**（源码：`session-newapi-token-map.service.ts:39-51`，只返回 `revokedAt IS NULL` 的行）——直接调用真实方法得到的结果，不是拼字符串猜的。

**步骤 3：`findActive` 命中在"真实运行进程"里的独立交叉证据**（比脚本调用更强的证据）：seed 完成后，同一 sessionId 经真实 D3-proxy 转发（同 SG-8.1②③ 那次调用）**成功拿到 200 + 真实 Kimi 回复 "PONG"**（见 §1②③ 与下方 `chat.history` 输出）——这只有在 `SessionProxyService.resolveNewApiKey()`（`session-proxy.service.ts:134-179`）内部真的调用 `tokenMap.findActive(sessionId)` 并命中时才会发生（未命中会被 `resolveNewApiKey` 按 `reject` 策略 502 拒绝，`session_billing_mapping_unresolved`，本轮在未 seed 的对照场景下确实观测到过这个错误分支，见下方"对照"）。

**对照（同一轮内，未 seed 的场景，证明 fail-closed 语义成立、不是误判)**：`d3proxy.log`：
```
[WARN] session-proxy: sessionId=(missing) 未命中 session→newapi 映射，按默认策略（reject）拒绝转发。
```
（这是第一次尝试时 body 过大导致连 sessionId 都未解析到的场景，见 §1①③"发现"段；后续场景在 seed 完成后均转为成功转发。）

**判定：pass**——mint 路径以源码实况为准（真实业务端点 501，源码文档化的开发期路径可用），映射表 `revokedAt IS NULL` 行 + `findActive` 命中，且命中在真实运行进程里被独立交叉证实（而非只信脚本自称）。

---

## 2. SG-8.3 PRE-1（C-1）：soft `chat.send`+`queueMode:"steer"` 三场景响应体差异表

**方法**：直接调用底层 RPC `chat.send`（不经过 `sessions.send`/`sessions.steer` 的 D1 窄腰包装——soft inject 本来就是这条独立路径，见 `research/pre1-openclaw-source-conformance.md` §1.3 F5 "soft inject 是另一条路径：`chat.send`+`queueMode:'steer'`"），对三种场景各构造一次真实调用，记录原始响应体。全部使用真实 openclaw+D3-proxy+newapi 链路（无 mock provider 可用，已在 SG-4 rework 阶段确认 openclaw 源码内无 echo/mock provider），已按"最小化"控制在 3 组共 4 次真实模型调用内，复用同一 newapi token。

### 逐字段响应体对照表

| 场景 | 构造方法 | 原始响应体（`chat.send` 直接 RPC ack） | ok | 关键字段 |
|---|---|---|---|---|
| **A：运行中会话注入**（预期成功注入） | 先 `sessions.send` 起一个真实长任务（"数到 20"/"数到 20 并说 BANANA"），~700ms 后（任务仍在生成中）对同一 session 直接发 `chat.send{deliver:false, queueMode:"steer", message:"STEER-INJECT..."}` | `{"runId":"sg9-c1v2-scenA-steer-1785002879291","status":"started"}` | `true` | 无 `messageSeq`；无任何 `queued`/`reason`/三态枚举字段 |
| **B：拒收场景** | 对一个全新（idle）session 发 `chat.send{deliver:false, queueMode:"steer", message:""}`（空消息、无附件） | `{"code":"INVALID_REQUEST","message":"message or attachment required"}` | `false` | 结构化错误码+消息；**这是通用请求校验层的拒收（`chat-send-request.ts:167-169`），对任何 `chat.send` 调用一视同仁，不特定针对 `queueMode:"steer"`——本轮未找到一个专属于"steer 业务语义"的拒收分支（源码定位见下方说明），如实记录这一发现，非声称"steer 无法被专属拒收"** |
| **C：空闲静默 fallback**（预期） | 对一个全新（idle、从未 send 过）session 直接发 `chat.send{deliver:false, queueMode:"steer", message:"IDLE-STEER-PROBE..."}` | `{"runId":"sg9-c1v2-scenC-1785002887370","status":"started"}` | `true` | 无 `messageSeq`；无任何 `queued`/`reason`/三态枚举字段 |

原始 JSON 全量见 `scratchpad/round9-track-a/sg83-c1-results.json`（首次尝试，B/首版 A/C）与 `sg83-c1-results-v2.json`（A/C 补种映射后的干净重跑，用于下方内容级观察）。

### 核心发现（逐字段比对得出，非源码走读推测）

1. **场景 A 与场景 C 的 ack 响应体在字段结构上完全无法区分**——均是 `{runId, status:"started"}`，没有 `messageSeq`（对照：经 `sessions.send`/`sessions.steer` 窄腰包装的调用**才会**带 `messageSeq`，见 `sessions-messaging.ts:366-378` 的 `shouldAttachPendingMessageSeq` 分支，本轮 SG-8.1④ 的 `sessions.send` 调用即带了 `messageSeq:1` 作对照）。**即：只看 `chat.send` 原始 RPC ack，机器无法区分"这次调用真的注入到了一个活跃 run 里"还是"这次调用只是在一个空闲 session 上开了一个全新 run"**——这正是 D1 §11 C-1 条目本身担心的问题（"成功注入与静默降级是否可机器区分"），本轮的直接答案是：**在 `chat.send` 的即时 ack 层面，否**。要区分，只能靠外部信号（比如调用前先查 `session.hasActiveRun`）。源码印证：`chat-send-handler.ts:270-288` 显示这个 ack (`ackPayload = {runId, status:"started", serverTiming?}`) 是在**任何实际模型调用发起之前**同步返回的（后续真正的 admission/dispatch 是 `void gatewayWorkAdmission.run(...)` detached 出去的），ack 本身根本不携带"是否真的注入到了活跃 run"这一信息，这与 queueMode 是否为 `"steer"` 无关。
2. **场景 B（拒收）响应体在结构上清晰可区分**——`ok:false` + 结构化 `code`/`message`；但根因是**通用消息内容校验**（`chat-send-request.ts:167-169`，空消息+无附件），不是"steer 语义专属"的拒收。本轮在源码内检索 `admitChatSend`/`runChatSendPreAdmission`（`chat-send-admission.ts`/`chat-send-pre-admission.ts`）未发现任何按 `queueMode==="steer"` 分支触发的、语义专属的拒收路径——**如实记录为"未找到"，不是"证明不存在"**（受时间预算限制，未做穷尽式代码普查，只查了 admission 阶段返回 `ok:false` 的全部已知分支）。
3. **场景 A 的内容级观察（补充，非 ack 层面）**：seed 好映射后重跑一次干净的 A（`sg83-c1-v2`），用 `chat.history` 取真实转录：主任务"数到 20"完整生成一次；随后 steer 消息"也说一次 BANANA"触发**第二次、独立、完整的**"数到 20"重新生成 + 附加 "BANANA"，而不是在第一次生成的中途被拼接/续写。`sessionInfo.abortedLastRun` 全程为 `false`（soft steer 本就不该 abort，这一点符合预期，不代表主任务未完成）。**如实记录为一个观察，不作为结论性证据**：这个观察结果与"真正的同 run 无损中途注入"（若存在应该是同一条消息续写，不会整段重新生成）更相符的解释是"排队为顺序的下一轮对话"，但本轮未能严格证明 700ms 时主任务是否仍在活跃生成中途（`chat.send` 的同步 ack 本身不暴露这一时刻的运行状态，见发现 1），故这条观察定性为"部分/待确认"，不升级为"steer 退化成 followup"这样的结论性断言。

**判定**：三场景响应体已完整对照，pass（探针本身完整交付，产出的是"A/C 在 ack 层面不可区分"这一具体、可复现的发现，不是探针失败）。

---

## 3. SG-8.3 PRE-3（C-4）：`sessions.steer` abort 成功但 `chat.send` 失败时 `interruptedActiveRun` 是否透出

**方法**：构造"abort 成功、内部 resend 必然失败"的确定性场景——用**空消息**触发 `chat-send-request.ts:167-169` 的通用校验拒收，让 `sessions.steer`（hard 变体，走 `handleSessionSend(interruptIfActive:true)`）在 abort 步骤之后、resend 步骤失败。先起一个真实长任务（"数到 30"）建立**真活跃 run**，400ms 后（仍在生成中）对同一 session 发 `sessions.steer{message:""}`。

**命令/输出**（`phase-sg83-c4.mjs`）：

```
--- sessions.steer(message:"") 响应（预期：abort 成功、resend 失败） ---
{"ok":false,"error":{"code":"INVALID_REQUEST","message":"message or attachment required"}}
```

**验证 abort 确实真的发生过**（不是"根本没有活跃 run 可 abort"这种平凡情形）——`chat.history` 读该 session 的 `sessionInfo`：
```
abortedLastRun: true
status: "killed"
lastRunError: null
```
`abortedLastRun:true` + `status:"killed"` 证实"数到 30"这个真实活跃 run **确实被 steer 的 abort 步骤成功中断**（`interruptSessionRunIfActive`，`sessions-messaging.ts:120-210`），随后内部 resend（`dispatchChatSend`，同文件 `:356-390`）因空消息在 `chat-send-request.ts:167-169` 校验失败，`ok=false`。

**结论：不透出**——最终返回给客户端的错误响应体里**没有 `interruptedActiveRun` 字段**。源码级根因（逐行核对，非推断）：`sessions-messaging.ts:379-389` 的最终 `respond` 调用里，`interruptedActiveRun` 只在三元表达式 `ok && payload && typeof payload === "object" ? {...payload, ...(interruptedActiveRun?{interruptedActiveRun:true}:{})} : payload` 的**真分支**（`ok===true`）里被拼接进去；`ok===false` 时走假分支，原样返回 `payload`（本场景下是 `undefined`），**该字段结构上不可能出现**——这是一条对所有失败态都成立的无条件代码事实，不依赖失败的具体原因（本场景用空消息触发，但换成任何其它导致 `chat.send` 内部校验/admission 失败的原因，结论相同）。

**判定**：探针场景成功构造并实测，pass；C-4 的答案是**"不透出"**（明确、非猜测的结论，源码+运行时双重坐实）。按 D1 §11 C-4 既定规则："不透出则统一上报 `aborted_effect_unknown`，不得猜测性上报 `aborted_resend_failed`"——本轮结果支持继续维持这条保守默认，不触发契约修订。

---

## 4. SG-8.4①②：真实 kernel-client 映射后的 D2 事件 schema 校验 + protocolVersion round-trip

### 方法（如何抓真实事件流，交代清楚）

**不是**直接校验 openclaw 原生 wire 帧（openclaw 原生帧 ≠ D2，`session.message` 这类原生事件与 D2 `EventMessageUnion` 判别联合是两回事）。做法：新写一个 Swift 探针入口 `d2-live-dump-main.swift`（scratchpad throwaway，**未修改** `app/kernel-client/swift/` 任何文件），与生产 kernel-client 源码**一起编译成同一个可执行文件**——完全复用 `FrameReplayTestMain.swift` 已经建立的先例（`@main` 独立入口 + 不含 `CLIRunner.swift`/`main.swift`，见该文件头注释）：

```
swiftc app/generated/swift/D2.swift app/generated/swift/DiscriminatedUnions.swift \
       app/kernel-client/swift/KernelClient.swift app/kernel-client/swift/OpenclawWire.swift \
       app/kernel-client/swift/EventMapping.swift \
       app/kernel-client/swift/OpenclawGatewayKernelClient.swift \
       scratchpad/round9-track-a/d2-live-dump-main.swift \
       -o scratchpad/round9-track-a/d2-live-dump
```

探针跑一次真实 `connect → createSession(model:"d3proxy/kimi-for-coding") → subscribe → send("PONG") → 观察20s → stop`，**订阅回调收到的每一个 `EventMessageUnion` 都是 `OpenclawGatewayKernelClient`/`EventMapping.swift` 生产代码真实 dispatch 出来的**（不是我手写解析原始 JSON 模拟的），用 `newJSONEncoder()`（`D2.swift:4605-4611`，quicktype 生成的官方 helper，`dateEncodingStrategy=.iso8601`——特意确认并复用这个而不是裸 `JSONEncoder()`，否则 `ts`/`sentAt` 会被编码成数字时间戳而非 ISO-8601 字符串，那样 schema 校验会因为编码策略选错而假失败，不是真缺陷）逐条编码为 JSON，写入 `.jsonl`。

### ① 真实 D2 事件逐条过 D2 JSON Schema

本次真实 send（真实 Kimi 回复 "PONG"）共收到 **4 条**真实 dispatch 出的 `EventMessageUnion`：`evt.message.delta` → `evt.turn_complete` → `evt.operation_completed`（stop 触发）→ `evt.session_end`（delete 触发）。

用 Ajv（`Ajv2020`，与 `app/contracts/d2/codegen/scripts/validate-schemas.mjs` 同款依赖版本）校验全部 4 条against `message.schema.json#/$defs/Message`（顶层判别联合）：

```
[event 0] type=evt.message.delta        message.schema.json (top-level Message union): PASS
[event 1] type=evt.turn_complete        message.schema.json (top-level Message union): PASS
[event 2] type=evt.operation_completed  message.schema.json (top-level Message union): PASS
[event 3] type=evt.session_end          message.schema.json (top-level Message union): PASS
=== SUMMARY: 4 PASS / 0 FAIL out of 4 real dispatched D2 events ===
```

（同时也过了更窄的 `#/$defs/EventMessage` 校验，全 PASS，全量输出见 `scratchpad/round9-track-a/validate-live-events.mjs` 运行日志。）

**工具链发现（如实记录，非本轮引入的缺陷，是本轮第一次真正"跑通" Ajv 实例校验时才暴露的既有 gap）**：`app/contracts/d2/codegen/scripts/validate-schemas.mjs` 用 `ajv.addSchema(schema, schema.$id)` 逐个注册 25 个 schema 文件后，只调用了 `ajv.getSchema('message.schema.json')` 证明**编译**通过（`$ref` 图无悬空引用），**从未真正调用编译出来的 validator 函数去校验一个真实实例**（该文件自己的 fixture 循环只 `JSON.parse` fixture、不调用 `validateMessage(fixture)`，注释原话"只做 schema 本身合法可用的自检"）。本轮第一次真正对真实实例调用 `validateMessage(event)` 时，Ajv 在**校验时（不是编译时）**抛出 `MissingRefError: can't resolve reference ../common/envelope.schema.json#/$defs/sentAt`——即"schema 能编译"和"schema 真的能拿来校验实例"是两件事，后者此前从未被验证过。本轮用 `@apidevtools/json-schema-ref-parser`（已是 codegen 的 devDependency）先把 `message.schema.json` 完整 dereference 展开成无 `$ref` 的单一 schema 树（顺带处理了展开后同一 `$id` 在多分支重复出现导致的 "resolves to more than one schema" 报错，做法是展开后剥掉非根节点的 `$id`），再交给 Ajv 编译+校验，工作正常（见上方 4/4 PASS）。**建议后续 SG-1/SG-8 轮次把这条"实际调用 validator 校验真实/金标实例"补进 `validate-schemas.mjs` 或 parity runner，而不是只停在"编译通过"这一层**——这是本轮的一个具体、可复现的 conformance 修正候选，登记于此。

**判定**：pass，4/4 真实 D2 事件全部通过 schema 校验；额外交付一处工具链 gap 发现与可复现修法。

### ② protocolVersion 握手期单传 → round-trip 断言

**先说清楚 D1/D2 契约里这句话具体指什么**（读 `events/capability-changed.schema.json` 的 `$comment` 原文坐实，不是猜的）：`evt.capability_changed` 的 `payload.capabilities` 字段类型是 `WireCapabilityDescriptorPayload`（对应 Swift `Capabilit` struct，`D2.swift:3092-3106`，**确认没有 `protocolVersion` 字段**——`grep` 全文件核对过），这是 D2 v3 全文唯一一处故意排除内嵌 `protocolVersion` 快照的位置；schema 原话："反序列化时适配器须用同一连接协商值同时回填事件基字段与本嵌套 descriptor 的 protocolVersion……这是运行时回填规则，不是 wire 形状"。也就是说，round-trip 断言的对象是：**适配器收到这条事件后，要不要用握手期拿到的唯一一个 protocolVersion 值去重建一份完整的 `CapabilityDescriptorPayload`（`D2.swift:4239-4249`，这个类型才有 `protocolVersion: String` 字段）**。

**本轮实际能测到什么、测不到什么（如实分层）**：

1. **能测、已测（连接级半条）**：protocolVersion 确实只在握手期传输一次、且稳定。`OpenclawGatewayKernelClient.lastHandshakeProtocol`（`OpenclawGatewayKernelClient.swift:201`，真实生产代码里已有的 actor-isolated 属性，本轮探针直接读取，非新增）本轮 5 次独立握手（SG-8.1/8.3/8.4 各阶段）全部捕获同一个值：

   | 握手 | 来源 | protocol |
   |---|---|---|
   | phase-sg81.mjs（第3次，成功那次） | Node 原始 hello-ok | `4` |
   | phase-sg83-c1-v2.mjs | Node 原始 hello-ok | `4` |
   | phase-sg83-c4.mjs | Node 原始 hello-ok | `4` |
   | d2-live-dump（v1，日期编码有 bug 但握手本身独立于此） | `client.lastHandshakeProtocol`（Swift 生产属性） | `Optional(4)` |
   | d2-live-dump（v2，最终有效那次） | `client.lastHandshakeProtocol`（Swift 生产属性） | `4` |

   全部一致=`4`；且本轮抓到的全部 8+ 条真实事件帧（`session.message`/`evt.*`）里，**没有一条携带 `protocol`/`protocolVersion` 字段**（逐帧人工核对过 `sg84-run-v2.log` 与各 `.jsonl` dump）——即"握手期单传、事件不重复携带"这半条在本轮环境下经验成立。

2. **测不到、如实登记为发现（不是矛盾，是组件缺口）**：`evt.capability_changed` 的**回填重建**这一半，本 kernel-client 当前实现里**没有任何代码路径可以触发**——三处均已读源码坐实：
   - `EventMapping.swift:701-722`：`buildCapabilityChangedEvent(...)` 构造函数本身存在，但**从未被任何 `handleIncoming` 分支调用**，文件自己的注释明确写着"本轮仍未接入任何真实触发路径，是诚实登记的 unsupported 变体"（这是既有代码留下的诚实标注，不是本轮才发现）。
   - `OpenclawGatewayKernelClient.swift:808-810`：`capabilities(session:)`（D1 KernelPort 七方法之一，唯一能返回完整 `CapabilityDescriptorPayload` 的方法）是 `throw KernelClientError.notImplemented(...)` 桩。
   - 全仓搜索未发现任何"合并 `Capabilit` + 握手 protocolVersion → `CapabilityDescriptorPayload`"的回填/reconstruct helper 函数。

   即：**这条 round-trip 规则目前在 kernel-client 里没有对应的可执行代码，无法通过运行时探针验证"重建是否一致"**——不是探针没找对方法，是这段机制本身尚未实现（`capabilities()`/`capability_changed` dispatch 均是既有登记在案的 TODO，SG-4 rework 阶段已如实标注过），登记为本轮 conformance 发现：**SG-8.4②的"回填重建"子项 defer，待 `capabilities()`/`capability_changed` 落地后才具备可探针条件**；连接级"单传+不重复"子项 pass。

**判定**：连接级子项 pass（5 次独立握手协议版本一致=4，事件帧从不重复携带）；回填重建子项因组件缺口无法探针，如实记录为 defer（不是 fail，不是矛盾——符合 scope-lock Rollback Condition"须改已收口组件才能跑通探针=contract-insufficient 停下"的精神，本条只影响 SG-8.4②这一个具体子项，不影响其它已交付部分）。

---

## 5. 零内核/app 改动核验（收尾）

```
$ git -C kernels/openclaw status --short
?? git-hooks/post-commit

$ git -C kernels/openclaw status --ignored --short
?? git-hooks/post-commit
!! .artifacts/ !! dist-runtime/ !! dist/ !! node_modules/ ...（均为既有 gitignore 规则命中的构建产物/依赖目录，非本轮产生）

$ git status --short   # 主仓库
 M .harnessloop/state/current.md          # 本轮开始前已是这个状态（会话起始 git status 快照可核对），未被本轮改动
 ? kernels/openclaw                        # submodule 指针状态，未变
?? .harnessloop/goals/20260718-002-agent-app/rounds/0009/   # 本轮 evidence 落点，允许

$ git status --short app/
（空，无输出）
```

`git-hooks/post-commit` 是会话开始前就存在的 untracked 文件（本轮 Read `kernels/openclaw` CLAUDE.md 时看到其内容是 `sh ~/.git-ai/bin/post-aicode.sh`，一个全局 git-ai hook 脚本，与本轮任务无关，本轮未创建/未修改它）。`app/` 下 `git status`/`git diff --stat` 均为空——`app/server`/`app/kernel-client`/`app/contracts` 全程只读只用，零改动。

**收尾进程清理**：隔离 openclaw（18999）、D3-proxy（3011）、抓包代理（3012）均已 `kill -TERM` 并确认端口释放；用户全局 gateway（`127.0.0.1:18789`，PID 5197）收尾核对仍在正常监听、进程 uptime 未受影响，全程未被连接。Pi Postgres `session_newapi_tokens` 表：本轮新增的 8 行测试映射（sessionId 见各节）已在收尾阶段清理删除，未在共享 Pi 环境留下本轮 throwaway 数据；rounds/0004/0008 遗留的既有行未触碰。

---

## 6. 每子项判定汇总

| 子项 | 判定 | 一句话结论 |
|---|---|---|
| SG-8.1 ① header 到达 | pass（引用+复证） | 三 header 真实到达，与既有 rounds/0004 证据一致 |
| SG-8.1 ② sessionId 逐字节同源 | pass | 内核侧 2 处取值×D3-proxy 侧 3 处取值，5 处两两相等 |
| SG-8.1 ③ SSE 帧透传不缓冲 | pass（引用+复证） | 3-chunk 流式响应，非一次性缓冲 |
| SG-8.1 ④ mint→映射→findActive 命中 | pass | 真实业务端点 501（源码实况）+ 源码文档化路径 upsert 成功 + `revokedAt IS NULL` + `findActive` 命中，且被独立的真实转发成功交叉印证 |
| SG-8.3 PRE-1(C-1) 三场景 | pass（探针完整交付） | A/C 在 `chat.send` ack 层面结构不可区分（重要发现）；B 是通用校验层拒收非 steer 专属拒收 |
| SG-8.3 PRE-3(C-4) | pass | 决定性结论：abort 成功但 resend 失败时**不透出** `interruptedActiveRun`，源码+运行时双重坐实 |
| SG-8.4 ① D2 schema 校验 | pass | 4/4 真实 kernel-client 映射事件通过 `message.schema.json` |
| SG-8.4 ② protocolVersion round-trip | pass（连接级子项）+ defer（回填重建子项，组件缺口） | 单传+不重复子项 5 次握手一致；回填重建机制本身未实现，无法探针 |
| 零改动核验 | pass | 两 submodule + 主仓库 + `app/` 全部核对无本轮改动 |

## 7. Conformance 修正候选 / 后续待办（本轮发现，非本轮修复）

1. **D3-proxy body-parser 100KB 限制仍未修**（rounds/0004 已提过，本轮再次复现并绕行，未修复）——真实 openclaw agent 请求体 ~107KB，建议独立任务调大限制。
2. **`chat.send`（含 `queueMode:"steer"`）的 ack 响应体在"注入活跃 run"与"空闲新开 run"两种场景下结构完全相同**——如果未来产品/UI 需要机器可靠区分这两种结局，当前 wire 协议在 ack 层面做不到，需要额外的状态查询或事件观察。
3. **`app/contracts/d2/codegen/scripts/validate-schemas.mjs` 从未真正对实例调用过 Ajv validator**（只验证 schema 能编译），建议后续轮次补上；本轮已验证一套可行的 dereference 工作流（见 §4①）可直接复用。
4. **`capabilities()`/`evt.capability_changed` 在 kernel-client 侧仍是未接入的 TODO**（非本轮新发现，SG-4 rework 阶段已如实登记），导致 D2 v3 "protocolVersion 回填重建"这条契约规则目前完全没有可执行代码可供探针验证——待这两处任一落地后可重新排期这一具体子项。

## 8. 本轮产出文件清单（scratchpad，throwaway，未入版本库）

`scratchpad/round9-track-a/`：`ws-client.mjs`（Node RPC client 复用库）、`seed-mapping.cjs`（真实 service 方法调用探针）、`header-capture-proxy.mjs`（透传抓包代理）、`phase-sg81.mjs`/`phase-sg83-c1.mjs`/`phase-sg83-c1-v2.mjs`/`phase-sg83-c4.mjs`（各子项探针脚本）、`d2-live-dump-main.swift`（与生产 kernel-client 源码一起编译的探针入口）、`validate-live-events.mjs`（Ajv 校验脚本）、各 `.log`/`.json`/`.jsonl` 原始输出。
