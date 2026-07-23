---
phase: failed
last_progress_at: "2026-07-23T04:16:55.803Z"
last_progress: Task failed.
progress_seq: 2
terminal_event_emitted: true
status: failed
end_time: "2026-07-23T04:16:55.802Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 235851
adapter_status: auth-fail
---
# T-042 · D3-proxy session-affinity 计费路由 · 对抗代码审（grok）

**评审对象 commit**：`5fcf9de`（只读）  
**Task-type**：`code-review-adversarial`  
**Verdict**：`REWORK`

---

## Summary

对 commit `5fcf9de` 的 session-proxy / session-token 映射链路做了只读对抗评审。凭证面（静态 key 的 `timingSafeEqual` + 未配置 fail-closed、换凭证后不透传原 Authorization、日志不落 newapi key）总体扎实；fail-closed 主路径（未命中映射默认 reject、aggregate 无 key 拒绝）没有发现“无凭证放行”旁路。但**生产路径改写存在阻断级缺陷**：`stripMountPrefix` 只识别 `/session-proxy`，与 `main.ts` 全局前缀 `api/d3/v1` 组合后 `req.originalUrl` 无法剥离，上游 URL 恒错；集成测试未挂全局前缀，形成自证性假绿。另有内部路由头透传上游、路径穿越/开放代理、客户端断开 abort 监听不严谨等问题，合并前必须修。

## Files touched

- `.hopper/handoffs/T-042-output.md` — 本对抗评审交付物（只写 handoff 输出；未改 `app/` 或其它仓文件）

## Acceptance verification（5/5 已核验；多项不通过）

### 1. 凭证安全 — **部分通过（无明文 key 回显路径；静态鉴权主路径正确）**

| 检查点 | 结论 | 证据 |
|--------|------|------|
| 静态 key 未配置 fail-closed | 通过 | `session-proxy.service.ts:65-75`：`if (!expectedKey)` → `InternalServerErrorException(session_proxy_misconfigured)`，不放行 |
| `timingSafeEqual` | 通过 | `session-proxy.service.ts:94-99`：长度先比，再 `timingSafeEqual`；非 string / 非 Bearer 直接 false |
| 换凭证后原静态 key 不透传 | 通过 | `STRIPPED_REQUEST_HEADERS` 含 `authorization`（`session-proxy.constants.ts:16`）；`buildOutboundHeaders` 再设 `Bearer ${newapiKey}`（`session-proxy.service.ts:278-283`） |
| newapi key 不进日志/错误体 | 通过（应用层） | 所有 `Logger` 只记 sessionId/状态/脱敏 URL（`:146-149,:166-169,:226-228,:257-258`）；异常 `message` 无 key；`redactUrl` 去 query（`:291-293`） |
| 异常栈/响应泄漏 | 未发现应用主动泄漏 | filter 只转发 exception body（`http-exception.filter.ts:26-28`）；key 未进入 throw 载荷 |
| DB 明文存 newapi_key | 已知骨架债，非本次应“修”项 | `session-newapi-token.entity.ts:33-36` 已 x-todo 标注；生产前加密另立项 |

**未发现**：通过错误响应体、回传 header、Logger 明文写出真实 newapi key 的路径。  
**残余风险（NOTE，非本轮阻断）**：上游 newapi 若在 4xx body 中回显 Authorization 相关信息，本代理会原样流式透传（`:236-255`）——属上游契约风险，但 D3 未做响应脱敏。

---

### 2. 代理 hygiene — **不通过（内部路由头透传 + 开放路径）**

| 检查点 | 结论 | 证据 |
|--------|------|------|
| 入站剥离 host/content-length/authorization/hop-by-hop | 基本完整 | `session-proxy.constants.ts:11-23` 覆盖常见 hop-by-hop；缺 `proxy-connection`（次要） |
| 出站剥离 content-length/transfer-encoding | 通过 | `STRIPPED_RESPONSE_HEADERS`（`:26-31`）；body 经 `pipeline` 重写传输方式，避免 CL mismatch |
| body 重序列化后 CL | 请求侧 OK | 剥 CL + `JSON.stringify(req.body)` + fetch 自算 CL（`service.ts:15,211`） |
| **内部路由头是否转发给 newapi** | **失败** | `x-session-affinity` / `session_id` / `x-client-request-id` **不在** `STRIPPED_REQUEST_HEADERS`；`buildOutboundHeaders` 原样拷贝（`:276-279`）→ 上游可见 session 路由身份 |

**可复现失败场景 A（信息暴露）**：

```http
POST /api/d3/v1/session-proxy/chat/completions
Authorization: Bearer <STATIC>
x-session-affinity: sess-secret-uuid
Content-Type: application/json

{"model":"x"}
```

观察 newapi/假上游收到的请求头：将包含 `x-session-affinity: sess-secret-uuid`（及可能的 `session_id` / `x-client-request-id`）。  
计费归因头本应止于 D3，不应成为 newapi 侧的相关/关联标识。

**可复现失败场景 B（路径穿越 / 超范围代理）**：

在**无全局前缀**的简化挂载下（与集成测试同形）：

```http
POST /session-proxy/../api/token/1
Authorization: Bearer <STATIC>
x-session-affinity: <mapped-session>
```

`stripMountPrefix` → `/../api/token/1`  
`targetUrl` → `{newapiBase}/v1/../api/token/1`  
`new URL(...)` 规范化为 `{newapiBase}/api/token/1`（已用 Node 验证）。  
持静态 key + 有效映射（或 aggregate key）即可把代理打到 completions 以外的 Management 路径。控制器注释虽称“任意 OpenAI-compatible 路径”，但未 allowlist，也未防 `..` 逃逸 `/v1`。

---

### 3. fail-closed 完整性 — **通过（主路径）**

| 分支 | 行为 | 证据 |
|------|------|------|
| sessionId 缺失 | 不查表成功路径；走 unmapped 策略 | `extractSessionId` 返回 null（`:106-120`）；`resolveNewApiKey` 跳过 mapped（`:133-136`） |
| 映射未命中 + 默认 reject | 502 `session_billing_mapping_unresolved`，不 fetch 上游 | `:165-176`；集成测 `:134-149`（`receivedByUpstream` 长度 0） |
| 映射未命中 + aggregate 且无 fallback key | 502 `session_proxy_aggregate_fallback_unconfigured` | `:152-162` |
| 映射未命中 + aggregate 且有 key | 有意降级到聚合主体（非“无凭证”） | `:141-150` |
| 未知 policy 字符串 | 落入默认 reject | 仅 `policy === 'aggregate'` 特殊处理；env `@IsIn(['reject','aggregate'])`（`env.validation.ts:104-105`） |
| 无静态 key / 错静态 key | 500 misconfigured / 401 unauthorized，先于 session 解析后的转发 | `:65-83`；集成测 `:110-130` |

**未发现**“带着错误计费主体却完全无 Authorization 放行”的分支：`buildOutboundHeaders` 恒写 `authorization`（`:283`），且仅在 `resolveNewApiKey` 返回 string 之后才进入 `proxyToNewApi`。

**边界 NOTE（不单独升 REWORK）**：DB 若写入空字符串 `newapiKey: ''`，`findActive` 仍返回对象，会发出 `Authorization: Bearer `——属于脏数据，非未配置旁路；建议 upsert/find 拒绝空 key。

---

### 4. 流式正确性 — **部分通过（主路径流式成立；断开/半包有缺口）**

| 检查点 | 结论 | 证据 |
|--------|------|------|
| 响应真流式不整体缓冲 | 通过 | `Readable.fromWeb` + `pipeline(nodeStream, res)`（`:252-255`）；无 `arrayBuffer()`/`text()` |
| 集成测分块到达 | 测试声称覆盖且本地绿 | 假上游 60ms×2 间隔写 3 chunk（`integration.spec.ts:54-62`）；客户端 `events.length>=2` 且时间跨度 `>=40ms`（`:217-223`）；`npx jest --testPathPatterns='session-proxy|session-newapi-token'` → **9 passed** |
| 客户端断开 abort | **有缺陷** | `req.on('close', () => abortController.abort())`（`:214-215`）：(1) 成功结束后 listener 不移除 → 每请求泄漏；(2) 未判断 `res.writableEnded` / 区分正常结束与中途断开，可能在正常收尾阶段误 abort（通常无害但噪声）；(3) 若 `close` 在 headers 已写、pipeline 中触发，catch 只 `res.end()`（`:256-260`），不向 Nest 抛错——可接受，但无半包诊断 |
| 上游中断 / SSE 半包 | 弱 | pipeline 错误吞掉后 `res.end()`，客户端可能收到截断 SSE 且无错误帧；双写风险低（未再 throw） |
| 上游 fetch 失败 | 通过 | catch → 502 `session_proxy_upstream_unreachable`（`:225-233`），且发生在写 res 之前 |

**可复现失败场景 C（资源/竞态，可靠性）**：

对长 SSE 连接完成正常收完后，检查 `AbortController` 是否仍被 `req 'close'` 触发；反复打流式请求后观察 listener 累积（`req.listeners('close').length` 在 handler 内若可插桩会随请求增长）。更稳写法：

```ts
const onClose = () => { if (!res.writableEnded) abortController.abort(); };
req.on('close', onClose);
try { ... } finally { req.off('close', onClose); }
```

---

### 5. 逻辑/边界 + 测试诚实性 — **不通过（生产 URL 错 + 测试自证）**

#### 5.1 阻断缺陷：`stripMountPrefix` 与全局前缀不兼容

- 生产：`main.ts:11` → `app.setGlobalPrefix('api/d3/v1', ...)`
- 控制器文档自承完整路径为 `{host}/api/d3/v1/session-proxy/*`（`session-proxy.controller.ts:14-18`）
- 剥离常量：`SESSION_PROXY_MOUNT_PATH = '/session-proxy'`（`constants.ts:34`）
- 实现：仅 `originalUrl.startsWith('/session-proxy')` 才 slice（`service.ts:264-268`）
- 拼接：`targetUrl = baseUrl + completionsBasePath + stripMountPrefix(originalUrl)`（`:202`）

**可复现失败场景 D（生产必现错 URL）**：

| 入站 `req.originalUrl` | `stripMountPrefix` 结果 | 上游 target（`completionsBasePath=/v1`） |
|------------------------|-------------------------|------------------------------------------|
| `/session-proxy/chat/completions`（测试形态） | `/chat/completions` | `{newapi}/v1/chat/completions` ✅ |
| `/api/d3/v1/session-proxy/chat/completions`（生产形态） | **原样未剥** | `{newapi}/v1/api/d3/v1/session-proxy/chat/completions` ❌ |

Node 复现（评审时执行）：

```text
in="/api/d3/v1/session-proxy/chat/completions"
stripped="/api/d3/v1/session-proxy/chat/completions"
target="http://newapi.example/v1/api/d3/v1/session-proxy/chat/completions"
```

→ 生产环境凡走全局前缀的请求，**命中映射后仍会打到 newapi 错误路径**（404/上游业务失败），计费归因链路不可用。

#### 5.2 集成测试未覆盖其声称的生产行为（自证性）

- 测试创建 Nest app **未** `setGlobalPrefix('api/d3/v1')`（`integration.spec.ts:98-99`）
- 请求打 `/session-proxy/chat/completions`，恰好让 `startsWith('/session-proxy')` 成立（`:160-169` 断言 upstream `/v1/chat/completions`）
- **未测**：全局前缀、sessionId 缺失、aggregate 分支、静态 key 未配置、authorization 剥离否定断言、内部头不外泄、path `..` 拒绝、客户端中途断开
- 映射单测（`session-newapi-token-map.service.spec.ts`）只验证 repo mock 调用形状，不涉及代理安全

本地实测：`npx jest --testPathPatterns='session-proxy|session-newapi-token' --no-coverage` → **2 suites / 9 tests passed**——在错误生产模型下全绿，**假阴性风险高**。

#### 5.3 其它边界

| 项 | 结论 |
|----|------|
| `extractSessionId` 数组头 | 取 `candidate[0]`（`:117-118`）合理；多值歧义时静默取首，可接受 |
| GET/HEAD 无 body | `hasBody` 排除（`:206-211`）正确 |
| 非 JSON / 未解析 body | `JSON.stringify(req.body ?? {})` 对非 json Content-Type 可能变成 `{}` 丢原始体——chat completions 场景可接受，通配代理则脆 |
| 默认补 `content-type: application/json` | 对无 body 的 GET 也补（`:284-286`），轻微怪异 |

---

## Decisions / deviations

- 假设工作区当前文件与 commit `5fcf9de` 一致（`git show 5fcf9de --stat` 与工作区路径对齐）；未 checkout detached，按当前树只读审。
- mint 写入 501-blocked / 映射表生产为空：按 brief 视为诚实状态，**不**记为本轮缺陷。
- DB 明文 `newapi_key`：作者已 x-todo，记 NOTE 不单独否决。
- 未对真实 newapi/openclaw 做联调；路径/header 结论由源码 + Node URL 规范化 + 现有集成测推导。

## Open questions

1. openclaw provider `baseUrl` 是否固定为 `https://<host>/api/d3/v1/session-proxy`，且 path 是否再拼 `/v1/chat/completions`（可能导致双重 `/v1`）？需与 sg6 部署约定对齐 allowlist。
2. aggregate fallback key 的权限边界是否等同普通 session token，还是更宽？若更宽，路径穿越风险权重上升。
3. 是否允许代理任意 OpenAI 路径，还是仅 `chat/completions`（及明确白名单）？

## Verdict

**REWORK**

理由（须修后再审，按优先级）：

1. **P0 · 生产 URL 改写错误** — `session-proxy.service.ts:202,264-268` + `constants.ts:34` vs `main.ts:11`；场景 D。无全局前缀的测试全绿不能证明可上线。
2. **P1 · 开放代理 / 路径穿越** — 字符串拼接 path + 无 allowlist；场景 B，可逃逸到 `{newapi}/api/...`。
3. **P1 · 内部路由头透传上游** — `x-session-affinity` 等未进 `STRIPPED_REQUEST_HEADERS`；场景 A，与“凭证/归因只存 D3”安全模型不一致。
4. **P2 · 流式断开 hygiene** — `req.on('close')` 无 off、无 `writableEnded` 守卫；场景 C。
5. **P2 · 测试缺口** — 必须补：`setGlobalPrefix` 同生产、断言 upstream path、断言内部头不出现、否定 path `..`、aggregate/misconfigured 分支。

凭证 fail-closed 与换 Authorization 主逻辑**不应**被上述问题连带判为“完全不可信”，但在 P0 未修前**不能** PASS / PASS_WITH_NOTE。

## Next recommendation

1. 修复 path 剥离：用完整挂载前缀（如 `/api/d3/v1/session-proxy`）或 `req.params.splat` / `originalUrl` 中最后一次 mount 段；禁止依赖“无全局前缀”的测试形状。
2. 对上游 path 做 allowlist（至少 `^/v1/(chat/)?completions$` 或配置表）+ 拒绝 `..` / 绝对 URL；`new URL(path, base)` 规范化后校验 host 仍为 newapi。
3. 将 `SESSION_AFFINITY_HEADER` / `SESSION_ID_HEADER` / `CLIENT_REQUEST_ID_HEADER` 加入 `STRIPPED_REQUEST_HEADERS`（或等价出站黑名单）。
4. 加固 abort 监听；补集成测覆盖全局前缀与场景 A/B/D。
5. 修完后重跑本对抗审（T-042 同类）+ 现有 jest；通过后再合入/推进 SG-6 验收。

---

## 五项结论速览

| # | 对抗核验点 | 结果 |
|---|------------|------|
| 1 | 凭证安全（泄漏 / timingSafeEqual / 不透传静态 key） | 主路径通过；无应用层 key 回显 |
| 2 | 代理 hygiene（头剥离 / CL / 内部头） | **不通过**：内部亲和头外泄；开放 path |
| 3 | fail-closed（未命中/无凭证不放行） | 通过 |
| 4 | 流式正确性 | 主路径通过；断开 abort **有缺口** |
| 5 | 逻辑边界 + 测试是否自证 | **不通过**：生产 strip 错；测试假绿 |

**Verdict: REWORK**

## Vendor output (parsed)

_(vendor produced no parsed text; see `T-042-output.log` for the raw output stream.)_

## Status (background completion)
- queue_status: failed
- adapter_status: auth-fail
- exit_code: 0
- duration_ms: 235851
- end_time: 2026-07-23T04:16:55.802Z

### Adapter error
```
grok is not authenticated or was blocked by its permission mode. Set XAI_API_KEY / run `grok login --device-auth`. hopper passes --permission-mode bypassPermissions + --always-approve for headless dispatch.
```
- log: see `T-042-output.log` for raw output
