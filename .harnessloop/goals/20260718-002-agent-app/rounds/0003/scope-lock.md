# Scope Lock

## Round Objective

**SG-9 newapi 自托管部署（用户 2026-07-23 决策：newapi 作为本全栈方案的独立组件，部署到自有树莓派）**——把 `github.com/QuantumNous/new-api`（自托管 LLM 网关/计量层，D6 定性的 LLM Transport/Metering Sidecar）部署到树莓派（`10.244.132.76`，Ubuntu 24.04 aarch64），起来并可访问其管理面，为 SG-8.5 计费链 e2e（`内核 → D3-proxy → newapi → 上游 LLM`）提供 newapi 这一环。

**本轮分层目标（诚实边界）**：
- **L1（本轮必达）**：Pi 装 Docker + new-api 容器起来 + 管理面可达（http://10.244.132.76:<port> 返回、可完成初始 admin 初始化）。ARM64 镜像跑通。
- **L2（本轮尽力）**：new-api 配一个渠道(channel)+ 一把 token，**但配渠道需真实上游 LLM 凭证**（`NEWAPI_UPSTREAM_LLM_KEY`，channel-params 标 missing）——无凭证则渠道配置 defer，先把实例起稳、管理面通。
- **本轮不做**：完整计费链 e2e（openclaw→D3-proxy→newapi→上游），那是 SG-8.5，依赖本轮 newapi 就绪 + 上游凭证 + D3-proxy 起 + seed 映射，另开轮。

## Allowed Changes

| Path/data/tool | Allowed action | Limit |
| --- | --- | --- |
| 树莓派 `10.244.132.76`（ubuntu，SSH key 认证） | 装 Docker + 部署 new-api 容器 + 配置 | 用户授权部署目标；装 Docker、拉官方 new-api 镜像、起容器、初始化管理面；不动 Pi 上其它既有服务 |
| `.harnessloop/local/channel-params.json`（gitignored） | 写 | 记录 Pi + newapi channel 参数名/host（**不记密码/凭证值**） |
| `app/`（若需部署编排文件，如 `app/deploy/newapi/`） | 新建 | new-api 部署编排（compose/脚本），凭证走 env/ignored 不入库 |
| `.harnessloop/goals/.../rounds/0003/` + goal-breakdown（SG-9 行） | 写 | round 三文件 + 新增 SG-9 子目标（用户已授权 newapi 部署在计划内） |
| scratchpad | 写 | 部署脚本/日志 throwaway |

## Disallowed Changes

- **凭证入库**：Pi 密码、new-api admin token、上游 LLM key 一律不写入任何 tracked 文件（走 channel-params.json[gitignored] / env / Pi 本地）。
- 动 Pi 上与本部署无关的既有服务/数据。
- 三插件 submodule、kernels、wiki（本轮是部署，不碰这些）。
- 借本轮启动 SG-8.5 完整计费链 e2e 的编码（本轮只到 newapi 实例就绪）。
- 在无真实上游 LLM 凭证时臆造/硬编一个假 key 去"凑"渠道配置通过——渠道配置诚实 defer 到凭证就绪。

## One-Variable Strict Mode

- Enabled: no
- Variable: 不适用（基础设施部署轮，多步骤：装 Docker → 部署 → 配置）
- Reason: 首次远程部署含多个环节，探针驱动、逐步验证。

## Verification Commands Or Checks

| Check | Command or method | Expected result | Evidence path |
| --- | --- | --- | --- |
| Pi Docker 就绪 | `ssh pi 'docker --version && docker ps'` | Docker 版本 + daemon 在跑 | rounds/0003 evidence |
| new-api 容器起 | `ssh pi 'docker ps \| grep new-api'` + `curl http://10.244.132.76:<port>/api/status`（或首页） | 容器 running + HTTP 响应 | 部署日志 + curl 输出 |
| 管理面可达 | 本机 `curl http://10.244.132.76:<port>` | 返回 new-api 前端/status | curl 输出 |
| （L2）渠道+token | new-api 管理 API 建 channel（需上游 key）+ 建 token | 若上游 key 可得则配成；否则 defer 说明 | 管理面截图/API 响应 或 defer 说明 |

## Runtime Recovery Limits

- Recovery round: 可能（Docker 装失败/镜像 ARM64 不匹配/端口冲突/new-api 启动配置问题 → 允许只读诊断 + 调整部署参数迭代）
- Blocker type: 预期可能 `runtime-recoverable`（部署配置）或 `access-missing`（上游 LLM 凭证不可得 → 渠道配置 defer）
- Disallowed triggers or writes: 不写凭证入库、不动 Pi 无关服务
- Cleanup/write confirmation required before: 在 Pi 上装 Docker/起容器属用户已授权部署动作，无需逐步确认；配置真实上游 LLM 计费调用需凭证就绪 + 到 SG-8.5 e2e 时才发生

## Rollback Condition

若部署过程发现 ARM64 镜像不可用、或 Pi 资源/网络不支持、或需要动 Pi 上无关既有服务才能部署，则停下上报用户，不强行部署。new-api 实例若起坏可 `docker rm` 干净回滚（数据在挂载卷，可清）。

## Human Confirmation Required

- 在 Pi 上装 Docker + 部署 new-api：**用户已明确授权**（"部署到树莓派上"），无需逐步确认。
- 配置渠道触发**真实上游 LLM 计费调用**：需 `NEWAPI_UPSTREAM_LLM_KEY` 就绪（用户提供）——凭证即确认；无凭证则渠道配置 defer。
