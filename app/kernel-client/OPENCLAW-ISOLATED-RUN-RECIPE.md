# SG-4 openclaw kernel 隔离运行 recipe

> **保全说明**：本文件原产于 rounds/0002 de-risk 探针轮的 scratchpad（`sg4-openclaw-run-recipe.md`），
> 因是 SG-5/SG-8 重启隔离内核的可复用操作资产，随 rounds/0002 收盘拷贝进版本控制，内容原样保留
> （仅更新文末的自引用路径）。

状态标注: `[源码]` = 读 `kernels/openclaw/<path>:<line>` 坐实；`[实测]` = 本轮 throwaway 试跑实测（已清理，见文末）；`[推断]` = 未直接验证的推断。

范围: `kernels/openclaw` submodule pin 版本。测试端口 18889，隔离 profile 目录在 scratchpad 下，全程未连接/未干扰用户全局 gateway（`127.0.0.1:18789` / PID 5197）。

---

## 0. 关键发现：之前失败的真实原因（比"读了全局配置"更具体）

已知现场事实说 `gateway:dev` 失败是因为"读了用户全局 `~/.openclaw` 配置，pin 版本 schema 不认 `agents.list`"。源码坐实后，真正机制是**这个 pin commit 自身的一个内部不一致 bug**，和用户全局配置内容其实没有直接关系：

- `--dev` 标志（无论写成 `openclaw --dev gateway` 还是 `openclaw gateway --dev`）最终都会让 `devMode=true`
  `[源码]` `kernels/openclaw/src/cli/gateway-cli/run.ts:688`（`devMode = Boolean(opts.dev) || isDevProfile`）。
- `devMode=true` 时，只要目标 profile 的 `openclaw.json` 不存在（或传了 `--reset`），就会调用
  `ensureDevGatewayConfig()` 写一份新配置
  `[源码]` `kernels/openclaw/src/cli/gateway-cli/run.ts:762-773`。
- `ensureDevGatewayConfig()` 写入的 `agents` 字段用的是 **`list`（数组）** 形状
  `[源码]` `kernels/openclaw/src/cli/gateway-cli/dev.ts:120-134`（`agents: { defaults: {...}, list: [{ id: "dev", ... }] }`）。
- 但这个 pin commit 当前的 zod 配置 schema `AgentsSchema` 只认 **`defaults`/`entries`（record）**，`.strict()` 会拒绝任何多余 key
  `[源码]` `kernels/openclaw/src/config/zod-schema.agents.ts:9-20`。

结论：`--dev` 自举代码和当前 schema 已经不同步——**只要用 `--dev`，哪怕是全新空 profile、从未碰过用户全局配置，也会自己写出一份自己都不认的配置**，必现 "Config validation failed: agents: Unrecognized key: list"。所以本 recipe 的隔离启动**完全不用 `--dev`/profile=dev**，改用显式 env 隔离 + `--allow-unconfigured`，绕开这条自举路径。`[实测]` 已用这条路径把 gateway 跑到 `ready` 且无任何 schema 报错（见 §5）。

---

## 1. 隔离启动命令

```bash
cd kernels/openclaw

PROFILE_DIR=/path/to/a/fresh/empty/dir   # 本轮用的是 scratchpad 下 openclaw-iso/state
PORT=18889                                # 任选空闲端口，本轮验证用 18889
TOKEN=$(openssl rand -hex 24)             # 任意生成一个共享密钥字符串

OPENCLAW_STATE_DIR="$PROFILE_DIR/state" \
OPENCLAW_GATEWAY_PORT="$PORT" \
OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
OPENCLAW_SKIP_CHANNELS=1 \
node scripts/run-node.mjs gateway --port "$PORT" --allow-unconfigured --token "$TOKEN"
```

要点（全部指向确切 env/flag 名）：

- **`OPENCLAW_STATE_DIR`**：state/config 根目录的显式覆盖，优先级最高，且会连带决定默认 `OPENCLAW_CONFIG_PATH`（`<stateDir>/openclaw.json`）与默认 `OPENCLAW_OAUTH_DIR`（`<stateDir>/credentials`）
  `[源码]` `kernels/openclaw/src/config/paths.ts:65-94`（`resolveStateDir`）、`:159-168`（`resolveCanonicalConfigPath`）、`:315-324`（`resolveOAuthDir`）。
  只要目录里没有 `openclaw.json`，`io.load` 走默认配置，不会解析出任何 schema 冲突。
  另有更底层的 `OPENCLAW_HOME` 可以整体挪家目录（影响 `resolveRequiredHomeDir` 进而影响 `~/.openclaw` 默认路径）
  `[源码]` `kernels/openclaw/src/infra/home-dir.ts:45-54`，但**只设 `OPENCLAW_STATE_DIR` 已经足够隔离本任务需要的 state/config/oauth**，更简单、副作用面更小，本轮就是只设了这一个就跑通的。
- **不要传 `--dev` / `--profile dev`**：见 §0，会触发已知 bug。也不需要 `--profile <name>`——`OPENCLAW_STATE_DIR` 一旦显式设置，profile 相关代码只会去尝试填充它（不会覆盖）
  `[源码]` `kernels/openclaw/src/cli/profile.ts:94-101`。
- **`--allow-unconfigured`**：全新空目录没有任何 `gateway.mode=local` 之类的配置，需要这个 flag 才能起
  `[源码]` `kernels/openclaw/src/cli/gateway-cli/run-command.ts:41-45`。
- **`OPENCLAW_GATEWAY_PORT` + `--port`**：两者写一致即可；CLI 侧 `--port` 最终会驱动 `startGatewayServer(port, …)`，默认值 18789
  `[源码]` `kernels/openclaw/src/config/paths.ts:284`（`DEFAULT_GATEWAY_PORT = 18789`）、`kernels/openclaw/src/gateway/server.impl.ts:578-579`（`startGatewayServer(port = 18789, …)`）。env 层面的精确解析逻辑见 `resolveGatewayPort`
  `[源码]` `kernels/openclaw/src/config/paths.ts:361-377`。
- **`OPENCLAW_SKIP_CHANNELS=1`**：跳过 Telegram/Discord 等 channel 自启动，加速启动、避免任何外部网络副作用（非必需，但推荐）
  `[源码]` `kernels/openclaw/src/gateway/server-startup-post-attach.ts:639,676`。
- **`--token "$TOKEN"` / `OPENCLAW_GATEWAY_TOKEN`**：显式把 gateway 鉴权模式钉成 `token` 且值已知，避免服务端启动时随机生成一个我们读不到的临时 token
  `[源码]` `kernels/openclaw/src/cli/gateway-cli/run-command.ts:26-27`、`kernels/openclaw/src/gateway/startup-auth.ts:224-259`（不显式给 token 时会 `crypto.randomBytes(24)` 生成且**不落盘**，只在进程内存里，客户端无法凭空读到）。

`[实测]` 本轮实际执行的命令（用于验证，未改动任何源码）：
```bash
OPENCLAW_STATE_DIR="$SCRATCH/openclaw-iso/state" \
OPENCLAW_GATEWAY_PORT=18889 \
OPENCLAW_GATEWAY_TOKEN=sg4testtoken123456 \
OPENCLAW_SKIP_CHANNELS=1 \
node scripts/run-node.mjs gateway --port 18889 --allow-unconfigured --token sg4testtoken123456 --no-color
```
日志尾端：
```
[gateway] http server listening (14 plugins: ...)
[gateway] ready
```
全程未产生任何 `Config validation failed` 或 `agents: Unrecognized key` 报错——证实 §0 的诊断成立，且隔离方式有效。

---

## 2. 鉴权握手 recipe

- **是否需要配置**：需要，但可以整段显式钉死，不依赖任何"自动生成后不可读"的路径。不给 token 时服务端会启动期随机生成一个 24-byte hex token，**只存在进程内存里、`persistedGeneratedToken:false` 不落盘**，客户端脚本无法读到
  `[源码]` `kernels/openclaw/src/gateway/startup-auth.ts:159-260`。因此 recipe 选择显式传 `OPENCLAW_GATEWAY_TOKEN`/`--token`，让客户端用同一个值。
- **握手步骤**（`[源码]`+`[实测]` 都对上了）：
  1. 建立 WebSocket 到 `ws://127.0.0.1:<port>`（无需任何 HTTP 头、无需带 query 参数）。
  2. 服务端主动推送第一帧事件：
     ```json
     {"type":"event","event":"connect.challenge","payload":{"nonce":"<uuid>","ts":<epoch-ms>}}
     ```
     `[源码]` `kernels/openclaw/src/gateway/server/ws-connection.ts:428`；`[实测]` 逐字段对上。
  3. 客户端发一个 `req` 帧，`method:"connect"`，`params` 走 `ConnectParamsSchema`
     `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/frames.ts:32-72`。
     **共享密钥（token/password）鉴权时，`nonce` 不需要回传** —— `nonce` 只在 `params.device.signature` 的签名载荷里用到（设备身份鉴权），`ConnectParamsSchema` 顶层没有 `nonce` 字段。`[实测]` 确认：不带 `device` 字段、纯 `auth.token`，握手照样成功。
  4. 服务端校验通过后回一个 `res` 帧，`payload` 是 `HelloOk`（`type:"hello-ok"`，含协商后的 `protocol`、`server.version/connId`、`features.methods/events`、初始 `snapshot`、`auth.role/scopes`、`policy`）
     `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/frames.ts:75-136`。
- **协议版本坑（`[实测]` 踩出来的，源码未直接读到具体协商常量值）**：`minProtocol`/`maxProtocol` 传 `1` 会被拒 `PROTOCOL_MISMATCH`，报错里带 `expectedProtocol:4`；改成 `minProtocol:3, maxProtocol:4` 握手成功，服务端回 `protocol:4`。建议直接抄 `packages/gateway-client` 里的常量（`MIN_CLIENT_PROTOCOL_VERSION`/`PROTOCOL_VERSION`），不要手写数字。
- **`client.id` 是闭集 enum，不能随便写字符串**（`[实测]` 踩出来的）：合法值见 `GATEWAY_CLIENT_IDS`
  `[源码]` `kernels/openclaw/packages/gateway-protocol/src/client-info.ts:16-35`（如 `"cli"`、`"gateway-client"`、`"test"`、`"openclaw-probe"` 等）。
- **拿到 `operator.write` scope 的关键坑（`[实测]`+`[源码]` 一起坐实，这是最容易踩雷的一步）**：
  - 用 `client.id:"test"` / `mode:"backend"`、纯 token 认证、不带 `device` 字段去连，握手能过（`hello-ok`），但服务端因为"无设备身份"会清空自报的 `scopes`
    `[源码]` `kernels/openclaw/src/gateway/server/ws-connection/connect-auth.ts:268-284`（`clearUnboundScopes()`）。
    结果 `hello-ok.auth.scopes` 是空数组，随后 `sessions.create` 会被拒：
    `{"code":"FORBIDDEN","message":"missing scope: operator.write", ...}`（`[实测]`）。
  - 修法：把 `client.id` 设成 `"cli"`、`client.mode` 设成 `"cli"`（即 `GATEWAY_CLIENT_IDS.CLI` + `GATEWAY_CLIENT_MODES.CLI`）。只要连接是 loopback（回环地址+回环 host）、没有浏览器 `Origin` header、且用的是 token/password 共享密钥鉴权，服务端就会判定为"本地 CLI 自证明连接"并保留自报 scopes，不做设备配对
    `[源码]` `kernels/openclaw/src/gateway/server/ws-connection/handshake-auth-helpers.ts:265-276`（`shouldPreserveLocalCliSharedAuthScopes`）+ 其依赖的 `isCliContainerLocalEquivalent`/`resolvePairingLocality`（同文件 `:139-152`, `:213-243`）。
    `[实测]` 换成 `client:{id:"cli",mode:"cli"}` 后，`hello-ok.auth.scopes` 里能拿到请求的 scopes，`sessions.create` 等写操作全部放行。
  - 不需要走设备配对（device identity keypair + `device.pair.approve`）流程——那是给"新设备首次接入、需要人工/策略批准"的场景设计的，对同机 loopback CLI 类客户端没必要，也更复杂（需要生成密钥对、走 pairing 审批）。

一次完整、可复制的最小 `connect` 请求（`[实测]` 原样用过）：
```json
{
  "type": "req",
  "id": "r1",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 4,
    "client": { "id": "cli", "version": "0.0.1", "platform": "darwin", "mode": "cli" },
    "caps": [],
    "role": "operator",
    "scopes": ["operator.admin"],
    "auth": { "token": "<TOKEN>" }
  }
}
```

---

## 3. RPC 帧序列（createSession / subscribe / send / stop）

信封统一格式 `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/frames.ts:148-171`：
- 请求：`{type:"req", id, method, params}`
- 响应：`{type:"res", id, ok, payload, error}`
- 事件：`{type:"event", event, payload, seq?, stateVersion?}`

方法名与 scope 见方法目录 `[源码]` `kernels/openclaw/src/gateway/methods/core-descriptors.ts:213-245`（`sessions.create` scope=dynamic≈operator.write, `sessions.send`/`sessions.abort`=operator.write, `sessions.messages.subscribe`/`unsubscribe`=operator.read, `sessions.delete`=dynamic）。

### createSession → `sessions.create`
Params schema `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/sessions-create.ts:7-62`：所有字段皆可选（`key/agentId/label/model/thinkingLevel/task/message/attachments/worktree/...`）。**不传 `message`/`task` 就不会触发任何模型调用**（见 §4）。

`[实测]` 请求：
```json
{"type":"req","id":"r2","method":"sessions.create","params":{"label":"sg4-probe-session"}}
```
`[实测]` 响应 payload（Result schema `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/sessions.ts:389-400`）：
```json
{
  "ok": true,
  "key": "agent:main:dashboard:0962d246-292f-4fe5-aa7d-cdfb4f6d2e1d",
  "sessionId": "e505dd3d-8107-4e04-a732-19596d999540",
  "entry": { "sessionId": "...", "sessionFile": "sqlite:main:...", "updatedAt": 1784787132053, "label": "sg4-probe-session", "spawnDepth": 0, "parentSessionKey": "agent:main:main" },
  "runStarted": false,
  "resolved": { "modelProvider": "openai", "model": "gpt-5.6-sol" }
}
```
`key` 是后续 `send`/`subscribe`/`abort`/`delete` 都要用的会话标识。`resolved` 字段说明即便不发消息，服务端也会把"如果发送会用哪个 provider/model"解出来放在结果里（见 §4，这里是 `openai/gpt-5.6-sol`，是这台机器 openclaw 配置的默认模型，不是 mock）。

### subscribe → `sessions.messages.subscribe`
Params schema `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/sessions.ts:414-419`：`{key, agentId?, includeApprovals?}`。

`[实测]` 请求/响应：
```json
{"type":"req","id":"r3","method":"sessions.messages.subscribe","params":{"key":"agent:main:dashboard:0962d246-292f-4fe5-aa7d-cdfb4f6d2e1d"}}
→ {"subscribed":true,"key":"agent:main:dashboard:0962d246-292f-4fe5-aa7d-cdfb4f6d2e1d"}
```
订阅后，该 session 的更新会以 `{"type":"event","event":"session.message",...}` 推给这个连接，payload 形状是 `{sessionKey, agentId?, message, messageId?, messageSeq?, senderIsOwner?, ...sessionSnapshot}`
`[源码]` `kernels/openclaw/src/gateway/server-session-events.ts:245-262`（这段是运行时组装逻辑，不是独立 typebox schema——顶层 `EventFrameSchema.payload` 就是 `Type.Unknown()`，事件 payload 形状由各发送点自己定义）。

注：`sessions.subscribe`（不带 `.messages.`）是订阅"会话列表变化"（`sessions.changed` 事件），跟"订阅某一个 session 的消息流"是两个不同方法，别搞混——本任务要的是后者。

### send → `sessions.send`（选做，见 §4 结论未在闭环里跑）
Params schema `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/sessions.ts:403-411`：
```json
{"key": "<session-key>", "agentId": "optional", "message": "hello", "thinking": "optional", "attachments": [], "timeoutMs": 0, "idempotencyKey": "optional"}
```

### stop → `sessions.abort`（中断当前 run）或 `sessions.delete`（彻底关闭/删除会话）
`sessions.abort` params `[源码]` `kernels/openclaw/packages/gateway-protocol/src/schema/sessions.ts:428-432`：`{key?, runId?, agentId?}`。
`[实测]` 请求/响应（当时没有活跃 run，返回干净的"无需中断"状态，不是错误）：
```json
{"type":"req","id":"r4","method":"sessions.abort","params":{"key":"agent:main:dashboard:..."}}
→ {"ok":true,"abortedRunId":null,"status":"no-active-run"}
```
`[实测]` `sessions.delete` 请求/响应（真正把这个测试 session 关闭/清理掉）：
```json
{"type":"req","id":"r5","method":"sessions.delete","params":{"key":"agent:main:dashboard:..."}}
→ {"ok":true,"key":"agent:main:dashboard:...","deleted":true,"archived":["<path>/e505dd3d-....jsonl.deleted.<ts>.zst"]}
```
建议 kernel-client 把"stop"实现为：有活跃 run 就先 `sessions.abort`，然后（如果要真正释放会话资源而不只是中断本轮）再 `sessions.delete`；只是"停止当前生成"就只用 `sessions.abort`。

---

## 4. send 是否需要真 provider —— 结论：**需要，本轮 defer**

- 源码里没有找到任何 echo/mock/fixture provider（搜了 `src/config/model-provider-config.ts`、`src/llm/providers/`、`extensions/*`、`src/test-helpers/`，没有 `echo`/`mock`/`fake`/`fixture` provider 的注册或实现）。
- `[实测]` 佐证：即便完全不传 `message`/`task`，`sessions.create` 的响应里也带了 `resolved:{modelProvider:"openai", model:"gpt-5.6-sol"}`——说明服务端在 create 阶段就已经把"如果要 send，会用哪个真实 provider/model"解析出来了，这是这台机器 openclaw 配置里的真实默认模型，不是占位符。
- 结论：`sessions.send` 一定会触发真实模型调用（除非配置一个真的可用的 provider/凭证，比如已登录的 `claude-cli`/`openai` 等——但那仍是"真"调用，只是复用已有登录态，不是 mock）。
- 因此，按照任务纪律（"若必须真 provider，明说，则 send 部分本轮 defer"）：**本轮不跑 `sessions.send`**，只验证 `createSession → subscribe → stop` 闭环（已在 §3/§5 完整跑通，且全程无模型调用、无网络出站）。

---

## 5. 健康判据 + `[实测]` 试跑记录

**判定"这个隔离 gateway 真 ready"的两个信号**（都在 `[实测]` 里观察到）：
1. **端口 LISTEN**：`lsof -iTCP:<port> -sTCP:LISTEN` 能看到目标 node 进程（本轮是新起的 PID，和用户全局 PID 5197 不同）。
2. **stdout 出现 `[gateway] ready`**：这是 CLI 侧启动流程打的最终就绪日志
   `[源码]` 日志行本身在 `[实测]` 输出里逐字出现（`2026-07-23T14:09:54.159+08:00 [gateway] ready`），对应源码 `kernels/openclaw/src/cli/gateway-cli/run.ts` 启动流程末尾的就绪打点（本轮未逐行对源码行号，凭实测日志坐实其存在与含义）。
   更强的判据是能收到 WS 首帧 `connect.challenge`——这证明 HTTP upgrade + WS 服务端逻辑已经在跑，比单纯端口 LISTEN 更可信（端口 LISTEN 但进程可能还在启动中）。

`[实测]` 试跑全过程摘要：
- 隔离目录：`$SCRATCH/openclaw-iso/state`（scratchpad 下，全新空目录，跑完后仍在，内容仅为本次测试产生的 sqlite/session 文件，未清理——如需彻底清理可 `rm -rf`，不影响任何其他系统）。
- 启动日志关键行：
  ```
  2026-07-23T14:09:52.488+08:00 [gateway] loading configuration…
  2026-07-23T14:09:53.970+08:00 [gateway] http server listening (14 plugins: ...)
  2026-07-23T14:09:54.159+08:00 [gateway] ready
  ```
  全程**没有**任何 `Config validation failed`/`Unrecognized key` 报错，证实 §0 诊断（问题在 `--dev` 自举代码而非"读全局配置"本身）。
- 握手 + RPC 闭环：见 §2/§3，逐帧文本已贴出，`createSession → subscribe(messages) → abort → delete` 全部 `ok:true`。
- 清理：`kill -TERM` 两个相关 PID（CLI wrapper 97018 + 实际 gateway 子进程 97253），~3 秒内进程自行退出（graceful shutdown），未需要 `SIGKILL`。收尾核对：
  - `lsof -iTCP:18889` 无输出（端口已释放）。
  - `lsof -iTCP:18789` 仍显示 PID 5197 在监听，`ps -p 5197` 显示该进程持续运行、uptime 未受影响——**全程未连接、未干扰、未重启用户全局 gateway**。
- 遗留文件：`kernels/openclaw` 源码**零改动**（全程只读）；`/tmp/openclaw/openclaw-<date>.log` 这个日志目录不受 `OPENCLAW_STATE_DIR` 控制、是个全局固定路径（本轮未深挖其覆盖 env，只读到 append 而非覆盖行为），如果后续要更严格的日志隔离需要再查一下有没有单独的日志目录 env override——这是本轮唯一没有完全钉死的隔离维度，不影响本任务的验收目标（RPC 闭环 + 不碰用户 gateway 状态/端口/配置）。

---

## 回主会话摘要（供上层引用）

1. 隔离启动一行命令 + 端口：
   ```
   OPENCLAW_STATE_DIR=<fresh-empty-dir> OPENCLAW_GATEWAY_PORT=18889 OPENCLAW_GATEWAY_TOKEN=<token> OPENCLAW_SKIP_CHANNELS=1 node scripts/run-node.mjs gateway --port 18889 --allow-unconfigured --token <token>
   ```
   端口 18889（任选空闲端口即可）。**关键：不要加 `--dev`**——`--dev` 自举代码在这个 pin commit 里写出的 `agents.list` 配置和当前 schema 不兼容，必现 "Unrecognized key: list"，这是本轮找到的真实根因（比"读了用户全局配置"更精确）。
2. 鉴权：需要配（显式传 `--token`/`OPENCLAW_GATEWAY_TOKEN`，别指望读随机生成的临时 token，它不落盘）。客户端一句话：收到 `connect.challenge` 事件后，直接发 `connect` 请求带 `auth.token`（共享密钥场景下 nonce 不用回传），`client.id`/`client.mode` 必须用 `"cli"`/`"cli"` 才能在无设备配对的情况下保留 `operator.write` 等写权限 scope（用 `test`/`backend` 会握手成功但 scope 被清空，写操作全部 403）。
3. send 能否 mock 跑通：**不能，本轮 defer**。源码里没有 echo/mock provider，`sessions.create` 返回的 `resolved.model` 证实会打真实模型。`createSession → subscribe → stop` 这个闭环（L1，不含 send）已经**完整实测跑通**，全程零模型调用。
4. 无 blocker，未改内核。已清理试跑进程，用户全局 gateway（18789/PID 5197）全程未受干扰。

Recipe 原始产出路径（rounds/0002 de-risk 探针轮 scratchpad，throwaway）：
`scratchpad/sg4-openclaw-run-recipe.md`（本文件为其拷贝进版本控制的正式副本，供 SG-5/SG-8 重启隔离内核复用）。
试跑脚本（可复用做后续验证，非业务代码，仍留 scratchpad）：`scratchpad/rpc-probe.mjs`
