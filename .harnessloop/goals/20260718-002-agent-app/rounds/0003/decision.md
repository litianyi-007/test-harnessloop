# Decision

- Feedback: positive
- Blocker type: access-missing（仅限 L2/后续 SG-8.5 路径；本轮 L1 范围本身无 blocker）
- Recovery eligible: yes（待用户提供 `NEWAPI_UPSTREAM_LLM_KEY` 即可解除）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0003（SG-9 newapi 自托管部署到树莓派）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-23

## Reason

SG-9 的验收边界由 scope-lock 预先诚实分层为 L1（Pi 装 Docker + new-api 容器起 + 管理面可达，本轮必达）/ L2（配渠道 + token，本轮尽力，但明确标注需真实上游 LLM 凭证）/ 完整计费链 e2e（明确不做，defer SG-8.5）。执行结果：**L1 已达成**——树莓派（`10.244.132.76`，Ubuntu 24.04.4 aarch64）装成 Docker `29.6.2` + compose `5.3.1`，`app/deploy/newapi/docker-compose.yml`（SQLite 单机模式、镜像 `calciumion/new-api:latest` v1.0.0-rc.21、port 3000）起容器成功；管理面从开发本机（`10.244.132.185`）可达，`GET /api/status` 200、`GET /api/setup` 显示 `root_init`；root 初始化（`POST /api/setup`）与登录均成功（role 100 admin，会话下发）。

**L2（配渠道）经 access-missing 阻断，按纪律明确 defer**：配渠道 + token 需真实上游 LLM 凭证 `NEWAPI_UPSTREAM_LLM_KEY`——new-api 本身不产生模型输出，渠道必须转发到真实上游 provider 才有意义。用户尚未提供该凭证，scope-lock 明确禁止"无凭证时臆造假 key 凑配置"，故本轮如实 defer，不构成"L1 达成"之外的额外扣分。

证据充分（Docker/compose 版本 + 容器 running + 管理面逐步操作证据：status/setup/root 登录）且收敛（L1/L2/完整 e2e 边界清晰、无一处把未证部分表述为已过），故本轮 feedback 分类 **positive**。

本轮延续 rounds/0002 建立的做法——**scope-lock 先于执行、走完整 round → decision → state 回写闭环**，兑现 evolution-issue 0010 记录的教训（对比 rounds/0001 补记轮坐实的 SG-1/SG-2/SG-6 此前均绕开该闭环）。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-9 的 done 严格限定为「L1 部署 + 管理面就绪」**：Pi Docker 装成 + new-api 容器 running + 管理面可达（从开发机跨机验证）+ root setup/login 成功，达 done 标准。**L2（渠道配置）与完整计费链 e2e 均未纳入本轮 done 范围**，收编 **SG-8.5**（新一轮，blocked 待用户提供 `NEWAPI_UPSTREAM_LLM_KEY` + D3-proxy 起 + seed 映射）。
- **执行中的一处偏离已裁定为在 scope-lock 授权范围内**：Docker Hub 被连接重置（国内网络）→ 配置 registry 镜像加速器（daocloud 等）后重试拉取成功，属 scope-lock「Runtime Recovery Limits」预期内的 `runtime-recoverable` 类问题，未触及 Disallowed Changes（未动 Pi 上无关既有服务、未把凭证写入 tracked 文件），已在 round-summary 如实记录，未回改 scope-lock 掩盖偏离。
- **安全备注已如实登记**：new-api 当前 root 密码存于 gitignored `channel-params.json`；实例运行在用户本地网（`10.244.x`）、自用模式（`SelfUseModeEnabled=true`）；生产化前应改强密码/加固，本轮范围不含该项加固工作。
- **下一步待选**：**SG-8.5**（计费链 e2e，优先——但 blocked 待用户提供上游 LLM 凭证，凭证到位前无法启动配渠道环节）/ 或改推 **SG-3**（codegen 增量）/ **SG-5**（Windows C# kernel-client parity 追赶），两者均不依赖上游 LLM 凭证，可在等待用户输入期间并行推进。

## Open Questions Resolved

- Pi 环境就绪性：`10.244.132.76`（hostname `olegpi`，Ubuntu 24.04.4 aarch64，7.6Gi/4 核/35G）资源与架构均满足 new-api ARM64 镜像运行需求，已实证（容器 running，管理面响应正常）。
- Docker Hub 连接重置的根因与解法：国内网络环境直连 Docker Hub 被重置，非 Pi 本身故障；配置 registry 镜像加速器（daocloud 等）后拉取成功，问题已解，可复现（compose 文件 + 加速器配置均可复用）。

## Open Questions Deferred

- SG-8.5（计费链 e2e）：待用户提供 `NEWAPI_UPSTREAM_LLM_KEY`（new-api 渠道上游 LLM 凭证）后启动；还需 D3-proxy 起 + seed 映射两项前置。
- new-api 生产化加固（强密码/凭证轮换等）：本轮 scope 外，暂无独立 SG 编号，待后续评估是否需要专项子目标。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E13（拟登记） | `app/deploy/newapi/docker-compose.yml` + `.harnessloop/local/channel-params.json`（gitignored） | SG-9 L1 达成（部署 + 管理面就绪）的直接依据：容器 running + 管理面从开发机可达 + root setup/login 成功的逐步证据 |

## Next Action

- Action type: human-input
- Scope-lock required: yes（SG-8.5 开 round 时新建 scope-lock）
- Human confirmation required: 是——`NEWAPI_UPSTREAM_LLM_KEY`（new-api 渠道上游 LLM 凭证）需用户提供后 SG-8.5 才能启动
- Safe without user input: 否（SG-8.5 路径）；是（L1 本身已完成，若改推 SG-3/SG-5 则不需用户输入）
- Recovery round objective: 不适用（本轮无 blocker，L1 已达成；SG-8.5 的 access-missing blocker 待用户输入解除，非需 recovery round）
- Disallowed until confirmed: 不得把 SG-9 表述为「渠道配置/完整计费链 e2e 已过」直至 SG-8.5 通过；不得在无真实上游 LLM 凭证时臆造/硬编假 key 去配渠道
