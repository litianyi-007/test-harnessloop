# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0003（实现阶段第三轮 · SG-9 newapi 自托管部署，续 rounds/0002 兑现 evolution-issue 0010 教训，完整 round → decision → state 回写闭环）
- Scope-lock: rounds/0003/scope-lock.md（v1）
- Started: 2026-07-23
- Completed: 2026-07-23

## What Changed

本轮交付 **SG-9（用户 2026-07-23 决策新增子目标）**：把 `github.com/QuantumNous/new-api`（自托管 LLM 网关/计量层，D6 定性的 LLM Transport/Metering Sidecar）部署到用户自有树莓派（`10.244.132.76`，hostname `olegpi`，Ubuntu 24.04.4 aarch64，7.6Gi/4 核/35G），起来并使其管理面可从开发本机（`10.244.132.185`）访问，为 SG-8.5 计费链 e2e（`内核 → D3-proxy → newapi → 上游 LLM`）补上 newapi 这一环。

**部署路径**：Pi 侧装 Docker `29.6.2` + compose `5.3.1`（官方 convenience script，免密 sudo）→ 落地 `app/deploy/newapi/docker-compose.yml`（SQLite 单机模式，镜像 `calciumion/new-api:latest`，版本 v1.0.0-rc.21，port 3000，已版本控制）→ `docker compose up -d` 起容器。

**初始化 + 验证**：new-api 首次 setup（`POST /api/setup`，字段 `confirmPassword` camelCase，`SelfUseModeEnabled=true`）返回"系统初始化成功"，创建 root（role 100 admin）；root 登录成功，会话下发。管理面从开发本机可达验证：`GET /api/status` 200、`GET /api/setup` 显示 `root_init`。

**L1（本轮必达）达成**：Pi Docker 装成 + new-api 容器起（ARM64 镜像跑通）+ 管理面可达 + 可完成初始 admin 初始化——scope-lock 定义的 L1 边界全部兑现。

**L2 defer（access-missing blocker，如实记录，非臆造凑数）**：配置渠道（channel）+ token 需真实上游 LLM 凭证（`NEWAPI_UPSTREAM_LLM_KEY`）——new-api 本身不产生模型输出，渠道需转发到真实上游 provider，用户尚未提供该凭证。按 scope-lock「本轮不做完整计费链」与「无真实上游凭证时不臆造假 key 凑渠道配置」两条纪律，本轮不发起渠道配置，diff 到 **SG-8.5**（该轮同时依赖 D3-proxy 起 + seed 映射，另开轮）。

**一处执行 note（runtime-recoverable，已解，非 blocker）**：部署过程中 Docker Hub 被连接重置（国内网络环境），拉取 `calciumion/new-api:latest` 失败；改为在 Pi 的 Docker daemon 配置 registry 镜像加速器（daocloud 等）后重试，拉取成功。属 scope-lock 「Runtime Recovery Limits」预期内的 `runtime-recoverable` 类问题，未触及 Disallowed Changes，未动 Pi 上无关既有服务。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E13（拟登记，见 evidence-index.md） | `app/deploy/newapi/docker-compose.yml`（版本控制的部署编排） + `.harnessloop/local/channel-params.json`（gitignored，raspberry-pi-deploy channel + newapi channel 参数） | runtime | Pi Docker 装成 + 容器 running + 管理面 `/api/status` 200 从开发机可达 + root `/api/setup` 初始化成功 + root 登录成功（role 100 admin）的逐步证据；凭证值（Pi SSH key 路径已换 ed25519、new-api root 密码）仅记于 gitignored channel-params，未入库 |

## Handoffs Closed

- 无 hopper 派发——本轮为基础设施部署（Pi 装 Docker + 起容器 + 初始化管理面），非对抗/验收评审类任务，未触发 codex/grok 随机池派发；亦非 code-impl 编码任务。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——L1（部署 + 管理面就绪）验收边界内证据充分且收敛：

- Pi 侧 Docker `29.6.2` + compose `5.3.1` 装成，new-api 容器（`calciumion/new-api:latest`，v1.0.0-rc.21，ARM64）running。
- 管理面从开发本机（跨机）可达：`GET /api/status` 200、`GET /api/setup` 显示 `root_init`。
- root 初始化（`POST /api/setup`）与 root 登录均成功，会话下发，坐实管理面不仅"端口通"而是"可实际管理操作"。
- 部署编排 `app/deploy/newapi/docker-compose.yml` 已版本控制，可复现。
- L2（渠道配置）因缺 `NEWAPI_UPSTREAM_LLM_KEY` 如实 defer 至 SG-8.5，未把未证部分表述为已过——无"done 名不副实"风险；scope-lock 明确禁止的"无凭证时臆造假 key 凑配置"未发生。
- 执行中的一处偏离（Docker Hub 连接重置 → 配镜像加速器）属 runtime-recoverable，已在本节如实记录，未回改 scope-lock 掩盖。

无 negative / 未决评审悬置，故本轮 feedback 分类 positive。

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
- Estimated cost: unavailable（执行子代理的实际部署/调试成本已在其原执行会话消耗，未在本次状态回写中单独记账）

## Decision

见 rounds/0003/decision.md：feedback = **positive**；裁决 = SG-9 **L1（部署 + 管理面就绪）达成**，L2（渠道配置）因缺 `NEWAPI_UPSTREAM_LLM_KEY`（access-missing）明确 defer 至 **SG-8.5**；下一步待选 **SG-8.5**（计费链 e2e，blocked 待用户提供上游 LLM 凭证）/ 或其它主推（SG-3/SG-5）。

## Blocker Classification

- Blocker type: access-missing（仅限 L2/SG-8.5 后续路径——本轮 L1 范围内无 blocker）
- Recovery eligible: yes（用户提供 `NEWAPI_UPSTREAM_LLM_KEY` 后即可解除，非需重新设计的阻断）
- Safe next action: 待用户提供上游 LLM 凭证后开 **SG-8.5**（配渠道 + seed 映射 + 起 D3-proxy + 跑计费链 e2e）；凭证到位前可并行推进 **SG-3**（codegen 增量）/ **SG-5**（Windows C# kernel-client parity 追赶）等不依赖上游凭证的子目标
- User input required: 是——`NEWAPI_UPSTREAM_LLM_KEY`（new-api 渠道上游 LLM 凭证）需用户提供，本轮 L1 本身不需要用户进一步确认

## Open Risks

- **SG-9 done 是 L1 级、非完整计费链**：渠道配置 + 完整 e2e（内核→D3-proxy→newapi→上游）均未证，收编 SG-8.5，在其通过前不得把 SG-9 表述为「newapi 全链路已过」。
- **凭证暴露面**：new-api 当前 root 密码存于 gitignored channel-params，实例运行在用户本地网（10.244.x）、自用模式（`SelfUseModeEnabled`）；生产化前应改强密码/加固，本轮未做该项（scope 外）。
- **上游凭证仍缺失**：`NEWAPI_UPSTREAM_LLM_KEY` 是 SG-8.5 启动的硬前提，用户提供时间未知，SG-8.5 在此之前保持 blocked（access-missing），非死循环（有明确解除路径：等待用户输入）。

## Next Proposed Scope

待用户提供 `NEWAPI_UPSTREAM_LLM_KEY` 后开 **SG-8.5**（配渠道 + seed 映射 + 起 D3-proxy + 跑完整计费链 e2e，new-api 侧按 `token_name=session-<id>` 观测隔离归因）；凭证到位前可改推 **SG-3**（codegen 增量，注意与 SG-1 已交付部分不重复）或 **SG-5**（Windows C# kernel-client parity 追赶）。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
