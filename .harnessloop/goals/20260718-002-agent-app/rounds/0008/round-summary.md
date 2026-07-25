# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0008（SG-7 hermes per-session key 接线——PRE-① 裁定的「api_server HTTP 平台 per-session baseUrl/key 零改动」claim 的 e2e 检验；continue 驱动 + 关键节点独立审查，本项目第四次完整走该机制；单阶段轮，二选一路径任一端到端验证）
- Scope-lock: rounds/0008/scope-lock.md（v1）
- Started: 2026-07-25
- Completed: 2026-07-25

## What Changed

本轮交付 **SG-7 hermes per-session key 接线（api_server `model_routes` 路径 e2e 闭合）**——把 PRE-① 源码核验裁定的「hermes 走 `gateway/platforms/api_server.py` HTTP 平台 `model_routes` 特性可实现 per-session baseUrl/key **零内核代码改动**」这一 claim，放到真实运行系统上做 e2e 检验，对照 SG-6 openclaw 同款「零改动」claim 在 rounds/0004 被 e2e 证伪（需 3 处极小补丁）的先例。写码派主会话 claude-sonnet-5 子代理执行；主会话独立复验（亲查 new-api 计费日志 + hermes git 状态）；关键节点（★审查闸）hopper 派 codex 两轮（对抗审 + 收残后确认性再审）。

**核心结论：claim 经真实系统 e2e 检验成立**——与 SG-6 openclaw 同款 claim 被 e2e 证伪（3 补丁）构成两内核完美对照。这是 **C-3 path① 双内核首次闭合**、也是 D1 窄腰「跨内核」承诺的第一次双实证：openclaw 走 header-affinity，经 D3-proxy 换凭证；hermes 走原生 per-session key 直连 new-api（不经 D3-proxy），per-session key 本身即归因载体——同一 path① 两种落法，均在真实系统上跑通。

**交付内容（commit `47177412` 实现 + `fead0dde` 收 T-055 REWORK 残留）**：

- **Stage A recipe**（`app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md`）：uv venv py3.11 隔离安装 + `HERMES_HOME` 隔离 + gateway 起在隔离端口 `:8646`（`pyproject.toml:10` version `0.19.0`，pin `17155e3ae04d376dd8eba2e65f3dd966e67ab1ba`，与 PRE-① 引用基线一致）。记录两个真实踩坑：①非 editable install 会在 submodule 工作区落 `build/` 与被 `.gitignore:59` 遮蔽的 `hermes_agent.egg-info/`（原始记录称"不会往 submodule 写"被 T-055 证伪，已收残为如实记录 + 双查验收：普通 `git status/diff` + `git status --ignored --short`）；②裸 `hermes` CLI 未设 `HERMES_HOME` 会碰全局 `~/.hermes`（已隔离规避，`rm -rf ~/.hermes` 的通用收尾也已从"直接执行"改为"前置校验（存在 `config.yaml`/`state.db`/`sessions/` 即停止自动清理）+ 精确删除 0 字节文件 + 仅 `rmdir` 空目录"，护既有用户状态）。
- **Stage B evidence**（`app/kernel-client/HERMES-RUN-EVIDENCE.md`）：new-api（Pi）建 2 个测试 token（id=4/5，名称 `sg7-hermes-session-a`/`b`）→ 凭证入 gitignored `.harnessloop/local/channel-params.json` → 隔离 `config.yaml` 的 `platforms.api_server.extra.model_routes` 配两个 alias，各绑定一个独立 key → 两 session 各发最小 prompt（PING-A/PING-B）→ 真实 Kimi 回复 → new-api `/api/log` 逐字段归因：**log45→token_id=4（`sg7-hermes-session-a`，completion_tokens=22）/ log46→token_id=5（`sg7-hermes-session-b`，completion_tokens=15）**，两条均 `prompt_tokens=244 + cache_tokens=11264 = 11508`、`model_name=kimi-for-coding`、`channel_name=kimi-coding`，与 Hermes 侧记录的 usage 逐字段吻合。**主会话独立亲查 new-api 复验一致**（root 只读登录，`GET /api/log/`/`GET /api/token/` 现场核对）。
- **零改动机制（file:line，T-056 全部抽验一致）**：`gateway/platforms/api_server.py:1024-1039` gateway 起机时解析 `model_routes` 配置块构造静态映射；`:1795-1799` `_resolve_route` 按请求 model alias 查表；`:1885-1913` 在无 session `/model` override 时 overlay `model`/`api_key`/`base_url`；`:1934-1936` 把 overlay 后的参数传入 `AIAgent`。`_resolve_route(` 调用点仅 3 处（`:2863` `_handle_chat_completions`、`:3983` `_handle_responses`、`:5025` `_handle_runs`/`/v1/runs`），`_handle_session_chat`（`:2550-2575`）**不解析、不传入 route**，明确排除在闭合范围外。`git -C kernels/hermes status/diff`（tracked + untracked + ignored）全程终态全空——收残后 4 条命令输出均为空，`egg-info`/`build` 均 `absent`。

**★审查闸（两审收敛，codex 两轮，第二轮为收残后确认性再审）**：

- **T-055（code-review-adversarial，codex）Verdict = REWORK**：核心 e2e 三项（零改动真实性 / 归因证据真实 / e2e 链与 usage 算术真实）**全部通过、且证据比原始 evidence 更强**——独立挖出隔离 `state.db` 的持久化响应记录（session A/B 的 `PING-A`/`PING-B` 请求响应逐条、`input_tokens=244`/`output_tokens=22/15` 与 new-api 日志逐项相等、时间戳精确到同一秒、`request_id` 互异），判定"mock/固定串无法合理解释整条证据链"。REWORK 限定在文档与卫生 5 处：①egg-info 残留被 `.gitignore` 遮蔽，原文"不会往 submodule 写"口径过宽；②`rm -rf ~/.hermes` 作为通用收尾不安全（护用户既有状态诉求）；③3 处 handler file:line 引用错（`:2863`/`:3983`/`:5025` 三者映射写反）+ sessions-chat 路径过度声称；④`/platform resume api_server` 热加载说法错（源码 resume 仅处理 `EADDRINUSE` 后 paused 平台恢复，不能热加载新 alias，唯一可靠路径=重启 gateway）；⑤Pi 源 SQLite 只读 workaround 缺独立的远端前后 stat/hash 佐证。
- **收残（`fead0dde`）**：逐条修 T-055 五处 + 主会话自查另修 1 处 T-055 未列出的错误引用（`:60-64`→`:77-81`）+ 全部 14 项 file:line 引用逐条对源码复核。
- **T-056（code-review-acceptance，codex，接续自己的 T-055）Verdict = CONFIRMABLE**：4/5 项逐条闭合亲验（hermes tracked+untracked+ignored 全空；3 处 handler 映射与源码一致；sessions-chat 排除精确；`platform resume` 热加载说法已删净，仅保留否定性纠错）+ 抽验关键 file:line（含新增 `:77-81`/`:2550-2575`）全一致 + 无新引入的过度声称。核心 e2e 结论（T-055 已过的 1/2/3 项）未重开、未再查 new-api、未再调 Kimi。

**诚实边界（如实入档）**：

- `model_routes` 是**静态注册**特性——gateway 起机时一次性解析，动态新增 alias 唯一实测路径是重启 gateway 进程，与 PRE-① 既有 flag 一致，非本轮新缺口。
- **ACP 路径（需 <50 行小 patch）本轮未走、不闭合**——本轮只验证了 api_server 路径。
- **sessions-chat 路径**（`/api/sessions/{id}/chat`）不解析 route，不在本轮闭合范围。
- **Pi SQLite 只读 workaround** 没有远端前后 stat/hash 或命令 transcript 的独立实证，已如实标注为 limitation，不影响已验证的核心 e2e 归因结论。
- **new-api `GET /api/token/:id` 只返回掩码 key**——发现级修正 T-009 早期推断，记为 conformance 修正候选（非本轮 scope，未擅改 conformance wiki）。

**收敛守卫**：1 次 REWORK（阈值 3，第 3 个 MUST-FIX 才 checkpoint 用户），未触发。

**观察点**：codex T-055 审查质量高——独立找到 state.db 佐证并区分"tracked source 零改动"与"工作区零落盘"两个不同口径（前者成立、后者被 ignored egg-info 反证），异构审查连续第 5 轮抓到主会话/实现方漏掉的真问题（延续 T-048/T-050/T-052 等观察）。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E19 | `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md` + `app/kernel-client/HERMES-RUN-EVIDENCE.md`；commits `47177412`（实现）、`fead0dde`（收 T-055 REWORK） | runtime | SG-7 hermes per-session key e2e：真实 Kimi 两 session 归因 e2e（new-api log45/46→token4/5 逐字段，主会话亲查）+ 隔离 state.db 独立佐证（T-055 挖出）+ 零改动核验（hermes tracked+untracked+ignored 全空）+ 两审收敛（T-055 REWORK→T-056 CONFIRMABLE）；已登记 `state/evidence-index.md` E19 |

## Handoffs Closed

- hopper 派发 2 次，均已闭合（`.hopper/queue.md` 对应行 status=done）：
  - **T-055**（codex，code-review-adversarial）：SG-7 hermes per-session key e2e 对抗审，Verdict **REWORK**（核心 e2e 三项全过且证据更强，限文档+卫生 5 处）→ 已收残 `fead0dde`。
  - **T-056**（codex，code-review-acceptance，接续 T-055）：收残确认性再审，Verdict **CONFIRMABLE**（4/5 项逐条闭合亲验 + 抽验 file:line 全一致 + 无新过度声称）。
- 按 CLAUDE.md「codex 评审三项强制核对」：(a) T-055 实际审查对象为 brief 指定的主仓库 commit `47177412`（`HERMES-ISOLATED-RUN-RECIPE.md`+`HERMES-RUN-EVIDENCE.md`），T-056 审查对象为 `fead0dde`，均一致；(b) 产物落在 `.hopper/handoffs/T-055-output.md`/`T-056-output.md`；(c) 未仅凭 exit code 或 codex 自述采信——两份 verdict 均附具体核验操作记录（git 状态命令输出、new-api 现场查询、源码 file:line 抽验），非空转自述。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-7 hermes api_server 路径 per-session key 接线已完整 e2e 验证，证据充分且收敛：

- **零改动 claim 经真实系统检验成立**：`git -C kernels/hermes` tracked/untracked/ignored 全程终态全空（收残后核实），机制 file:line 全部与源码实况一致（T-056 抽验无误）。
- **归因 e2e 真实**：两个独立 new-api token 隔离归因，逐字段吻合（usage/model/channel/时间戳），独立审查者额外挖出隔离 `state.db` 的持久化响应佐证整条证据链，判定"mock 无法合理解释"。
- **两内核完美对照**：与 SG-6 openclaw 同款"零改动"claim 被 e2e 证伪（3 补丁）形成鲜明对比——hermes 走原生 `model_routes` 静态配置、不经 D3-proxy，per-session key 本身即归因载体；openclaw 走 header-affinity、经 D3-proxy 换凭证。同一 D1 窄腰承诺（C-3 path①）在两个异构内核上分别以不同机制真实闭合，是本项目"跨内核抽象"设计假设的首次双实证。
- **★审查闸两轮收敛**：T-055 REWORK 限定在文档表述与隔离卫生（均为机械/措辞级，非核心结论级）；收残后 T-056 CONFIRMABLE，4/5 项逐条闭合亲验、无新错误引入。收敛守卫（1 次 REWORK，阈值 3）未触发。
- **诚实边界完整标注**：`model_routes` 静态注册 caveat、ACP 路径未走、sessions-chat 路径排除、Pi SQLite workaround limitation、new-api token 掩码发现均如实记录，未过度声称。

无 negative/未决评审悬置，故本轮 feedback 分类 **positive**。

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
- Estimated cost: unavailable（执行子代理的实际编码/审查驱动成本已在其原执行会话消耗，未在本次状态回写中单独记账）

## Decision

见 rounds/0008/decision.md：feedback = **positive**；裁决 = **SG-7 done（api_server `model_routes` 路径 e2e 闭合；零改动 claim 经真实系统检验成立；ACP 路径未走，如实标注未闭合）**；与 SG-6 构成 C-3 path① 双内核对照（hermes 零改动成立 vs openclaw 需 3 补丁——同一 claim、两种命运）；收敛守卫（1 次 REWORK）未触发；下一步待选 **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **SG-8 其余子项**（SG-8.1/8.2/8.3/8.4）/ **Stage C**（D4 §4.6 产品行为 parity，rounds/0006 结转项）/ 两个 rounds/0007 defer 修复轮（TS `EmptyPayload` 精度缺陷 + 解码边界 strict-decode 设计裁决）/ T-009 token 掩码 conformance 修正 / hopper `||` 表格观察点处理。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker；零改动 claim 未被证伪，未触发 Rollback Condition 的 fork 决策路径）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待选 **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针，隔离内核底座已具备）/ **SG-8 其余子项**（SG-8.1 SG-6 e2e wire 补证/SG-8.2 hermes `/api/log/self` 互验路径补测/SG-8.3 runtime 探针/SG-8.4 kernel-client↔真实内核 conformance 闭环）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转的独立工作包）/ 两个 rounds/0007 新发现的 defer 项（TS `EmptyPayload` 精度缺陷修复归 SG-1；解码边界 strict-decode 设计决策归后续轮/设计修订）/ T-009 token 掩码推断的 conformance 修正（发现级，非阻断）/ hopper `||` 表格解析观察点（是否升级为 evolution issue 待定）
- User input required: 否（SG-7 已完整交付，闭合不需用户进一步确认）

## Open Risks

- **ACP 路径未走**——PRE-① 判定该路径需要一个 <50 行小 patch（接线 `acp_adapter/session.py::_make_agent` 与 `acp_adapter/server.py::set_config_option`），本轮明确未走、不闭合，若后续需要 ACP 传输下的 per-session key，仍需单独立项。
- **`model_routes` 静态注册边界**——动态新增 session 池 alias 唯一实测路径是重启 gateway 进程，非运行时热加载（`/platform resume api_server` 已证实不适用于新增 alias 场景），生产化前需评估该运维约束是否可接受。
- **Pi 源 SQLite workaround 独立实证缺口**——只读 scp 查询后即删的操作语义合理，但缺远端前后 stat/hash 或 transcript 的独立佐证，已如实标注为 limitation，未影响本轮核心结论。
- **new-api `GET /api/token/:id` 只返回掩码 key**——发现级修正 T-009 早期推断，记为 conformance 修正候选，非本轮 scope，未擅改 wiki。
- **两个 rounds/0007 遗留 defer 项延续未修**：TS `EmptyPayload` 精度缺陷（SG-1 codegen scope）、Swift/C# 解码边界静默忽略未知键（D1/D2 级 strict-decode 设计决策），本轮 scope 不含，仍待后续轮或设计修订处理。
- **hopper `||` 表格解析观察点**——延续 rounds/0007 记录，是否升级为 hopper 插件 evolution issue 待主会话/用户后续决定。

## Next Proposed Scope

**SG-7 hermes per-session key 接线（api_server 路径）已达成**。下一步从以下几项中择一或并行：**SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **SG-8 其余子项**（SG-8.1/8.2/8.3/8.4）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转的独立工作包）/ 两个 rounds/0007 新发现的 defer 项修复轮（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计决策）/ T-009 token 掩码 conformance 修正 / hopper `||` 表格观察点处理。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。**首批 SG 完成度盘点**：SG-1..SG-7 + SG-9 全部 done（SG-1 有 defer 注记），SG-8 剩 SG-8.1/8.2/8.3/8.4 四项 pending（SG-8.2 虽由 SG-7 承接，但其验收清单指定的具体验证方法 `/api/log/self?token_name=session-<id>` 互验本轮未走——本轮走的是 admin API `/api/log/` 现场核对，非该清单字面指定路径，故 SG-8.2 如实保持 pending，仅 SG-8.5/8.6/8.7 已 done）。
