# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0008（SG-7 hermes per-session key 接线，api_server 路径 e2e 闭合，已达成）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-25

## Reason

rounds/0008 的验收边界由 scope-lock 明确为一件事：把 PRE-① 源码核验裁定的「hermes 走 `gateway/platforms/api_server.py` HTTP 平台 `model_routes` 特性可实现 per-session baseUrl/key **零内核代码改动**」这一 claim，放到真实运行系统上做 e2e 检验——起隔离 hermes → 两个 session 各持独立 per-session key（映射两个独立 new-api token）→ 真实 Kimi 往返 → new-api 计费日志按 token 正确归因，二选一路径（api_server 零改动 / ACP 小 patch）任一端到端验证通过即可。执行结果：

- **Stage A recipe**（`app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md`）：uv venv py3.11 隔离 + `HERMES_HOME` 隔离 + gateway 起在隔离端口 `:8646`。记录两个真实踩坑：非 editable install 会在 submodule 落 `build/`+被 `.gitignore` 遮蔽的 `hermes_agent.egg-info/`；裸 CLI 无 `HERMES_HOME` 会碰全局 `~/.hermes`。
- **Stage B evidence**（`app/kernel-client/HERMES-RUN-EVIDENCE.md`）：new-api 建 2 测试 token（id=4/5）→ `config.yaml` `model_routes` 两 alias 各持独立 key → 两 session PING-A/B 真实 Kimi 回复 → `/api/log` 逐字段归因：log45→token4（completion 22）/ log46→token5（completion 15），`prompt_tokens=244 + cache_tokens=11264 = 11508` 两条吻合，主会话独立亲查 new-api 复验一致。
- **零改动机制（file:line）**：`api_server.py:1024-1039` 起机解析 `model_routes` / `:1795-1799` `_resolve_route` 按 alias 查表 / `:1885-1913` overlay `model`/`api_key`/`base_url` / `:1934-1936` 传入 `AIAgent`。`git -C kernels/hermes` tracked+untracked+ignored 全程终态全空。

**★审查闸（两审收敛，codex）**：

- **T-055（对抗审）Verdict = REWORK**：核心 e2e 三项（零改动真实性/归因证据真实/e2e 链真实）**全过且更强佐证**——独立挖出隔离 `state.db` 的持久化响应记录（PING-A/B 请求响应逐条、时间戳与计费秒级相关、`request_id` 互异），判定"mock 无法合理解释整条证据链"。REWORK 限定文档+卫生 5 处：egg-info 残留被 `.gitignore` 遮蔽致"无残留"口径过宽；`rm -rf ~/.hermes` 通用收尾不安全；3 处 handler file:line 引用错（`:2863`/`:3983`/`:5025` 映射写反）+ sessions-chat 路径过度声称；`/platform resume api_server` 热加载说法错（源码 resume 仅处理 `EADDRINUSE` 后 paused 平台恢复，新增 alias 唯一可靠路径=重启 gateway）；Pi SQLite 只读 workaround 缺独立远端 stat/hash 佐证。
- **收残（`fead0dde`）**：逐条修 T-055 五处 + 主会话自查另修 1 处 T-055 未列出的错误引用（`:60-64`→`:77-81`）+ 全部 14 项 file:line 引用逐条对源码复核。
- **T-056（收残后确认性再审，codex，接续自己 T-055）Verdict = CONFIRMABLE**：4/5 项逐条闭合亲验（hermes 三态全空、handler 映射与源码一致、sessions-chat 排除精确、`platform resume` 说法删净）+ 抽验 file:line 全一致 + 无新过度声称。核心 e2e 1/2/3 项未重开、未再查 new-api、未再调 Kimi。

**诚实边界（如实入档）**：`model_routes` 是静态注册特性（起机时一次性解析，动态加 alias 唯一实测路径=重启 gateway，与 PRE-① 既有 flag 一致）；ACP 路径（需 <50 行小 patch）本轮**未走、不闭合**；sessions-chat 路径不解析 route，不在闭合范围；Pi SQLite 只读 workaround 无远端前后 stat/hash 独立实证（已标 limitation）；new-api `GET /api/token/:id` 只返回掩码 key，修正 T-009 早期推断（发现级，记 conformance 修正候选，非本轮 scope）。

证据充分（核心 e2e 三项全过 + 隔离 state.db 独立佐证 + 零改动核验 tracked/untracked/ignored 全空 + T-055 REWORK→T-056 CONFIRMABLE 两审收敛 + 诚实边界完整标注）且收敛（收敛守卫全程 1 次 REWORK，未达阈值 3），故本轮 feedback 分类 **positive**。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **零改动 claim 的 e2e 检验方法论再次坐实**：SG-6 openclaw 与 SG-7 hermes 是同一个上游设计裁决（PRE-① C-3 path①"零改动"claim）在两个异构内核上的检验，结局完全不同——openclaw 被 e2e 证伪（3 处极小补丁）、hermes 被 e2e 证实（tracked+untracked+ignored 全程为空）。"源码核验结论必须过 e2e 才算数"这一方法论原则已在两个方向（证伪 + 证实）上各得到一次独立验证，不是单一方向的巧合。
- **C-3 path① 双内核首次实证**：hermes 走原生 `model_routes` 静态配置、不经 D3-proxy，per-session key 本身即归因载体；openclaw 走 header-affinity、经 D3-proxy 换凭证。同一 D1 窄腰承诺（跨内核统一抽象 path①）在两个异构内核上以不同机制真实闭合，是本项目"跨内核抽象"设计假设的首次双实证，非纸面推断。
- **审查者独立佐证挖掘 > 被动核对**：T-055 不仅核对了 brief 指定的核验点，还独立挖出隔离 `state.db` 这一 evidence 文档本身未引用的佐证源，并精确区分"tracked source 零改动"与"工作区零落盘"两个不同口径（前者成立、后者被 ignored egg-info 反证）——延续本项目 rounds/0006/0007 观察到的"异构审查连续抓到主会话/实现方漏掉的真问题"模式，本轮为第 5 次同类观察。
- **文档 file:line 错引用是本轮主要返工源**：REWORK 的 5 处里有 3+1 处（3 处 handler 映射 + 主会话自查另修 1 处）属于 file:line 引用准确性问题，均为机械级、不涉及核心 e2e 结论。这提示 recipe/evidence 类交付物在写作阶段就应对每条源码引用做逐条复核，而非事后靠审查兜底。
- **隔离卫生新纪律**：`.gitignore` 遮蔽的残留（本例中的 `hermes_agent.egg-info/`）用普通 `git status/diff` 查不出来，必须补 `git status --ignored --short` 才能坐实"无残留"——本轮起，隔离运行 recipe 的验收步骤应默认双查（普通 + `--ignored`），不能只查一半就下"无遗留污染"结论。
- **下一步待选**：**SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **SG-8 其余子项**（SG-8.1/8.2/8.3/8.4）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转项）/ 两个 rounds/0007 新发现的 defer 项修复轮（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计决策）/ T-009 token 掩码 conformance 修正 / hopper `||` 表格观察点处理。

## Open Questions Resolved

- **hermes api_server `model_routes` per-session 零改动 claim 是否经得起 e2e 检验**：本轮证实成立——`git -C kernels/hermes` 全程 tracked+untracked+ignored 均为空，机制 file:line 全部与源码实况一致，两个独立 new-api token 隔离归因逐字段吻合，独立审查者额外佐证（state.db）判定 mock 无法合理解释整条证据链。
- **C-3 path① 是否能在第二个异构内核上以不同机制同样闭合**：本轮证实——hermes 用原生 per-session key 直连（不经 D3-proxy）而非 openclaw 的 header-affinity 换凭证方案，同一设计承诺、两种落法，均真实闭合。
- **`.gitignore` 遮蔽的隔离残留是否会被常规 `git status` 漏检**：本轮证实会——`hermes_agent.egg-info/` 被 `.gitignore:59` 遮蔽，普通 `git status/diff` 看不到，需 `--ignored` 才能查出，已固化为隔离 recipe 的双查纪律。

## Open Questions Deferred

- **ACP 路径的 per-session key 接线**：PRE-① 判定需要一个 <50 行小 patch（`acp_adapter/session.py::_make_agent` + `acp_adapter/server.py::set_config_option`），本轮明确未走，若后续需要 ACP 传输下的 per-session key 仍需单独立项。
- **new-api `GET /api/token/:id` 只返回掩码 key 的 conformance 修正**：发现级修正 T-009 早期推断，是否需要修订相关 conformance wiki 留待后续处理，非本轮裁定。
- **Pi 源 SQLite workaround 的独立实证补强**：是否需要为"只读、未写"补充远端前后 stat/hash 或 transcript 级证据，留待后续轮评估必要性，非本轮阻断。
- **两个 rounds/0007 defer 项**（TS `EmptyPayload` 精度缺陷修复方案 / 解码边界是否需要 strict-decode）：延续 rounds/0007 decision.md 已记录的 deferred 状态，本轮未触碰，留待 SG-1 后续收尾轮 / 后续轮或设计修订评估。
- **hopper `||` 表格解析观察点是否升级为 evolution issue**：延续 rounds/0007 记录，留待主会话/用户后续决定。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E19 | `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md` + `HERMES-RUN-EVIDENCE.md`；commits `47177412`/`fead0dde` | SG-7 done 的直接依据：真实 Kimi 两 session 归因 e2e（new-api log45/46→token4/5 逐字段，主会话亲查）+ 隔离 state.db 独立佐证（T-055 挖出）+ 零改动核验（hermes tracked+untracked+ignored 全空）+ T-055 REWORK→T-056 CONFIRMABLE 两审收敛 |
| E11 | `~/.llm-wiki/agent-app-design/research/pre1-hermes-source-conformance.md` | PRE-① 原始 claim 的权威来源，本轮 e2e 检验的对象；claim 本身内容本轮未修订，仅新增 e2e 实证层 |
| E14 | `app/server`（D3-proxy）+ `kernels/openclaw` 补丁 `4ddcb52`/`35f8739` | SG-6 openclaw 同款"零改动"claim 被 e2e 证伪的先例，本轮用作两内核对照的直接参照 |

## Next Action

- Action type: 收盘 → 待选下一 SG 开新 round（或续做 SG-8 剩余子项/defer 项/结转项）
- Scope-lock required: yes（下一 SG 或 SG-8 子项/defer 项/结转项开 round 时新建 scope-lock）
- Human confirmation required: 否（SG-7 已完整交付，闭合不需用户进一步确认）
- Safe without user input: yes（本轮收盘）；下一步若改推 SG-8.x/Stage C/两个 defer 项，一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 从 **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **SG-8 其余子项**（SG-8.1/8.2/8.3/8.4）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转项）/ 两个 rounds/0007 新发现的 defer 项（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计决策）/ T-009 token 掩码 conformance 修正 / hopper `||` 表格观察点中择一或并行，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 ACP 路径的 per-session key 接线表述为"已完成"（明确未走）；不得把 SG-8.2 表述为"已 done"（其验收清单指定的 `/api/log/self?token_name=session-<id>` 互验路径本轮未走，SG-8.2 如实保持 pending）；不得把 Stage C（D4 §4.6 产品行为 parity）或 SG-8 其余子项表述为"已完成"（均为独立结转/pending 项，本轮未触碰）
