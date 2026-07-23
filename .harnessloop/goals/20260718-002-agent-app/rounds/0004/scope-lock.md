# Scope Lock

## Round Objective

**SG-8.5 计费链 e2e**——把完整链路 `隔离 openclaw 内核 → D3-proxy(session-affinity 换凭证) → 自托管 new-api(Pi) → Kimi 上游` 端到端跑通，证明 per-session 计费归因（C-3 path①）在真实运行系统上成立。

**已就绪前置**：SG-9 new-api 部署 + 渠道(kimi-coding, type14 Anthropic) + token 已配、**new-api→Kimi 已端到端验通**(真实 PONG，token 在 gitignored channel-params `NEWAPI_D3PROXY_TOKEN`)。SG-4 隔离 openclaw 内核 + kernel-client L1 已通(recipe 在 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`)。SG-6 D3-proxy 代码已收口(T-042)。

**拓扑**：Postgres 起在 Pi Docker（借 Pi 基础设施）；D3-proxy(app/server) 本机跑连 Pi Postgres + Pi new-api；openclaw 本机隔离跑，provider 指向本机 D3-proxy。

**分层目标**：
- **阶段1（D3 起）**：Pi Docker 起 Postgres；D3-proxy 本机配 env 起、连通 Pi Postgres(synchronize 建表)+ Pi new-api。
- **阶段2（D3→new-api→Kimi 腿）**：seed session→token 映射(用 NEWAPI_D3PROXY_TOKEN)；直接 curl D3 `/session-proxy` 带 `x-session-affinity` → 验证 D3 换凭证转发到 new-api → Kimi → 真实回复。这验证 D3-proxy 核心功能(读 header/查映射/换 Authorization/流式转发)对真实 newapi 成立。
- **阶段3（openclaw 腿 → 完整链）**：配隔离 openclaw 的 openai-completions provider(baseUrl→D3-proxy, sendSessionAffinityHeaders on, model kimi-for-coding, 静态 key)；kernel-client createSession → seed 该 session 映射 → send → 完整链 e2e，收到 Kimi 回复经内核事件流回 kernel-client。
- **验收(诚实)**：阶段1-2 达成即 SG-8.5 主体(D3→newapi→Kimi 真实链路通)；阶段3 达成即完整 per-session 链闭合。任一阶段受阻(如 openclaw provider 配置复杂)诚实分层记录、defer 清楚。

## Allowed Changes

| Path/data/tool | Allowed action | Limit |
| --- | --- | --- |
| 树莓派 Pi | 起 Postgres 容器 | 仅新增 d3-postgres 容器(Pi Docker)；不动 new-api/其它 |
| `app/server/.env`(gitignored) | 新建/写 | D3 运行 env(DB 指 Pi、NEWAPI_BASE_URL、SESSION_PROXY_*)；凭证不入库 |
| D3-proxy(app/server) 本机运行 | build + start | 跑 npm build/start；**不改 D3 源码**(SG-6 已收口，本轮是用它不是改它；若必须改停下上报) |
| 隔离 openclaw 内核运行 + 其 state-dir 内 config | 运行 + 配 provider | 在隔离 profile 的 config 里加指向 D3-proxy 的 provider；**不改 kernels/openclaw 源码** |
| `.harnessloop/local/channel-params.json`(gitignored) | 写 | 记录 static key 等参数名 |
| rounds/0004/ + state | 写 | round 收口 |
| scratchpad | 写 | 探针/seed 脚本 |

## Disallowed Changes

- **改 D3-proxy(app/server) 源码 或 kernels/openclaw 源码**——本轮是把已有组件接起来跑，不是改它们。若发现必须改才能通，停下记 blocker 上报(可能是 SG-6 收口漏项，另立)。
- 凭证入任何 tracked 文件(Kimi key/newapi token/DB 密码走 gitignored/env)。
- 动 Pi 上 new-api 或无关服务。
- 三插件/wiki。

## One-Variable Strict Mode
- Enabled: no
- Reason: 多组件集成 e2e，分阶段探针驱动。

## Verification Commands Or Checks

| Check | Method | Expected | Evidence |
| --- | --- | --- | --- |
| Pi Postgres 起 | `ssh pi docker ps \| grep postgres` + D3 连通 | 容器 running，D3 synchronize 建表成功 | D3 启动日志 |
| D3 起 | `npm start`(app/server) → `/health` 或端口 | 进程起、端口 listen、无 DB 错误 | D3 日志 |
| D3→new-api→Kimi | curl D3 `/session-proxy/v1/chat/completions` + `x-session-affinity` + static key，body model=kimi-for-coding | 200 + Kimi 真实回复(经 D3 换凭证) | curl 输出 |
| 完整链 | kernel-client createSession→seed→send | Kimi 回复经内核事件流回 kernel-client | 运行日志 |

## Runtime Recovery Limits
- Recovery round: 可能(D3 起不来/连不通 Pi Postgres/openclaw provider 配置/allowlist 路径 → 只读诊断+调配置迭代)
- Blocker type: 预期 `runtime-recoverable`(配置)；若需改 D3/openclaw 源码=`contract-insufficient` 停下上报
- Cleanup: 结束 kill 本机 D3/openclaw 进程；Pi Postgres 可留(数据卷)或 rm

## Rollback Condition
若阶段3 openclaw provider 配置需改 kernels/openclaw 源码、或 D3-proxy 有 SG-6 未覆盖的 bug 必须改源码，则停在阶段1-2(D3→newapi→Kimi 已证)，阶段3 明确 defer + 记 blocker，不擅改已收口组件。

## Human Confirmation Required
- 起 Pi Postgres + 本机 D3：用户已授权部署/e2e 范畴，无需逐步确认。
- 真实 Kimi 计费调用：用户已提供上游 key 即确认；调用保持最小(小 prompt)。
