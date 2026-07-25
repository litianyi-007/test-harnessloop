# Scope Lock — rounds/0008

## Round Objective

**SG-7 hermes per-session key 接线（二选一路径任一端到端验证）**：把 PRE-①源码核验裁定的「hermes 走 `api_server` HTTP 平台 per-session baseUrl/key = **原生零改动**」这一 claim 放到真实运行系统上 e2e 检验——起隔离 hermes → 两个 session 各持独立 per-session key（映射两个独立 newapi token）→ 真实 Kimi 往返 → new-api 计费日志按 token 正确归因。**这是 C-3 path① 在第二内核上的闭合**，也是 D1 窄腰「跨内核」承诺的第一次双内核实证。

**已知事实基线（不臆造，执行时以 wiki 为准）**：`~/.llm-wiki/agent-app-design/research/pre1-hermes-source-conformance.md`——per-session 支持路径是 `gateway/platforms/api_server.py` 的 `model_routes` / `run_agent.py` AIAgent 可独立传 `base_url`/`api_key`；ACP 路径需小 patch（本轮**不走** ACP 路径，走零改动的 api_server 路径）。`kernel-ecosystem-facts.md` + D6 为 newapi 集成语义权威。**教训对照**：SG-6 的 openclaw「零改动」claim 就是在 e2e 被证伪的（3 处极小补丁）——本轮就是对 hermes 同款 claim 的 e2e 考验，证伪了也是合格产出（如实记录 + 停下走 fork 决策）。

**分层目标（诚实分层）**：
- **Stage A（hermes 隔离运行 recipe）**：kernels/hermes（Python）依赖装入隔离环境（venv 落 scratchpad，不装入系统/不污染 submodule）→ 起 `api_server` HTTP 平台（隔离端口，别撞本机既有服务）→ 最小 session 往返打通。recipe 保全 `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md`（对齐 openclaw recipe 惯例）。
- **Stage B（per-session key e2e）**：new-api（Pi，10.244.132.76:3000）上建/复用两个独立 token（经 root 管理 API，凭证走 gitignored channel-params）→ hermes 两个 session 各配一个 token 为其 per-session key、base_url 指 new-api → 各发最小 prompt → 真实 Kimi 回复 + `new-api /api/log` 两条计费各归对应 token、usage 与响应吻合。**hermes 路径不经 D3-proxy**（per-session key 本身即归因载体，D3-proxy 是 openclaw 缺 per-session key 时的换凭证方案——此差异如实记录，正是 C-3 path① 两内核两种落法的对照）。
- **★审查闸（B 后）**：hopper 异构对抗审——e2e 证据充分性 + **零改动 claim 核验**（`git -C kernels/hermes diff/status` 必须干净）+ 归因断言真实（token/usage 逐字段）+ recipe 可复现性。

**验收（诚实）**：Stage A+B 达成 = SG-7 done（api_server 路径闭合；ACP 路径的"小 patch"选项如实标注为未走、不做）。任一阶段发现必须改 hermes 源码才能通 → 停下记 blocker（零改动 claim 被 e2e 证伪，需用户 fork 决策，同 openclaw 先例）。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| scratchpad（venv/hermes 配置/探针脚本） | 写 | 隔离运行 throwaway；hermes 配置文件放隔离目录不放 submodule 内 |
| `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md` | 新建 | recipe 保全 |
| `app/kernel-client/HERMES-RUN-EVIDENCE.md`（或并入 recipe） | 新建 | e2e 证据 |
| new-api（Pi）token 管理 | 增 token | 仅新增 2 个测试 token（root API）；不动渠道/既有 token/其它服务 |
| `.harnessloop/local/channel-params.json`（gitignored） | 写 | 新 token 参数名记录 |
| `.harnessloop/rounds/0008/` + state、`.hopper/` | 写 | round 收口 + 审查闸 |

## Disallowed Changes

- **改 `kernels/hermes` 源码**（本轮就是零改动 claim 的检验；须改=blocker 停下,fork 决策归用户——同 openclaw 先例）。
- 改 `kernels/openclaw`、`app/server`、`app/contracts`、`app/kernel-client` 既有代码（recipe/evidence 新文件除外）。
- 凭证入 tracked（Kimi key/newapi token 全走 gitignored channel-params/env/隔离配置）。
- 动 Pi 上 new-api 部署本体/渠道配置;动用户本机既有服务(18789 等)。
- 三插件 submodule、wiki(除非 e2e 证伪 claim 需修订 conformance 结论——那记 blocker 由主会话走设计修订,不混入本轮)。

## One-Variable Strict Mode
- Enabled: no（两阶段探针型 e2e）。

## Verification Commands Or Checks

| Check | Method | Expected | Evidence |
|---|---|---|---|
| A: hermes 起 + 最小往返 | 隔离 venv + api_server 起 + session 往返 | 服务健康 + 真实往返 | recipe + 运行日志 |
| B: per-session 归因 | 两 session 两 token 各发最小 prompt → `new-api /api/log` | 两条计费各归对应 token,usage 与响应吻合,真实 Kimi 回复 | 日志逐字段 + API 查询输出 |
| 零改动 | `git -C kernels/hermes status/diff` | 干净(零源码改动) | git 输出 |
| ★审查闸 | hopper codex/grok | PASS/PASS_WITH_NOTE | `.hopper/handoffs/T-05x-output.md` |

## Runtime Recovery Limits
- Recovery: hermes 依赖/启动/配置问题 → 只读诊断 + 调隔离配置迭代（runtime-recoverable）;须改 hermes 源码 = 零改动 claim 证伪 → blocker（human-decision:fork 策略）,停下如实报。
- Cleanup: 收尾 kill 隔离 hermes 进程;venv 留 scratchpad 自然回收;新建的 2 个测试 token 保留（后续轮复用）或收官时统一说明。

## Rollback Condition
零改动 claim 被 e2e 证伪（须改 hermes 源码）→ 停在证伪点,完整记录缺口(哪个文件哪段逻辑挡住)、blocker=human-decision-required(fork 决策),不擅改。conformance wiki 修订由主会话另走设计修订流程。

## Human Confirmation Required
- 各阶段自动化 + 审查闸派发：既定授权（continue 驱动）。
- 真实 Kimi 计费调用：既定授权（最小 prompt,同 SG-8.5/rounds/0005 先例）。
- new-api 新增 2 个测试 token：属既定 newapi 管理面授权范围（SG-9/SG-8.5 先例:root API 建 token）。
- 若零改动证伪 → fork 决策必须回用户（AskUserQuestion）。
