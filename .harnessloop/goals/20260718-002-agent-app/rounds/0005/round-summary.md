# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0005（实现阶段第五轮 · SG-5 kernel-client 完整化，goal 002 首次以 **continue 驱动 + 关键节点独立审查** 这套机制驱动的执行轮，续 rounds/0002-0004 做法，完整 round → decision → state 回写闭环）
- Scope-lock: rounds/0005/scope-lock.md（v1）
- Started: 2026-07-24
- Completed: 2026-07-24

## What Changed

本轮交付 **SG-5（kernel-client 完整化）完整闭合**：把 SG-4 defer 给 SG-5 的三项（Swift `send` 做实、完整 openclaw→D2 事件适配 11 变体、C# 端功能化 parity）全部做实，并首次让**真实 Swift/C# 客户端**（非探针脚本）驱动完整 agent 轮次跑通 SG-8.5 已证通的全链路，同时补齐跨端 parity 与 NOTE 级收尾。全程由 `$harnessloop-continue` 逐阶段驱动，每阶段写码派主会话 claude-sonnet-5 子代理、主会话只读审查+验收，**关键节点（★审查闸）引入 hopper 异构对抗审（codex/grok 随机池）**，是 scope-lock 中"驱动模型"章节所述机制在本项目的首次完整实战。

**流水线（Stage A → ★审查闸1 → Stage B → Stage C → ★审查闸2 → NOTE-1 收尾）**：

- **Stage A**（Swift `send` 做实 + openclaw→D2 事件适配 11 变体，初版 `a07dc67`）：`OpenclawGatewayKernelClient.send` 走通 `sessions.send`，`EventMapping` 从 SG-4 遗留的 1/11 变体补齐至全部 11 个 `EventMessageUnion` 变体。
  - **★审查闸1 第一轮**：hopper 派 codex（T-044，单 vendor 对抗审）判 **REWORK**——8 处缺陷，含 1 处 **CRITICAL**（凭证明文写入日志）。收残 `db489f0e`，过了自己新写的 13 条测试。
  - **★审查闸1 第二轮（确认性再审）**：codex（T-045）判 **MUST-FIX**——发现 6 处缺陷 M1-M6，其中包括**第一次收残（`db489f0e`）本身引入的新死锁**、残留的凭证泄漏未收干净，以及最关键的**测试是替代场景（假绿根因）**——`db489f0e` 的 13 条测试并未真实驱动待测代码路径。
  - **第二次收残 `f303f608`**：M1-M6 全部收口，并按 T-045 指出的"假绿"根因重写为**真 actor 级测试**，25/25 通过，主会话独立复跑确认。
  - **Stage A 接受**——两轮 ★审查闸1 均未简单放行，第二轮精确揪出第一轮收残引入的次生缺陷与测试有效性问题，收敛于第二次收残，未触发第三轮 MUST-FIX。

- **Stage B**（真 Swift client 驱动完整链 e2e，`02a22c0b`）：增强 `CLIRunner` 做字段级断言，用真实 Swift kernel-client（非探针）驱动隔离 openclaw（provider 指向 D3-proxy）→ D3-proxy → 自托管 new-api（Pi）→ Kimi 上游全链路，完成一次完整 `createSession → seed → send` 轮次，收到 9 条真实 D2 事件并对每条做字段级断言全部 PASS（`seq` 单调递增、`runId` 全程一致、终态唯一、`operationId` 与 `stop()` 返回值一致）；`stop()` 观察到单一终态。new-api 计费日志 id=39 与 `turnComplete.usage` 逐字段吻合（主会话独立查 new-api 日志复验）。这是"客户端证的链"完整版——区别于 SG-8.5 用 node 探针证通的链路，本阶段是**真实产品客户端自己**驱动出的完整链证据。

- **Stage C**（C# kernel-client parity，`3ae6fa81`）：C# 端从 SG-4 遗留的纯接口骨架补成功能实现，忠实镜像 Swift 权威实现——`OpenclawGatewayKernelClient`（1136 行）+ `EventMapping`（397 行）+ `OpenclawWire`（255 行），每处关键逻辑均注对应 Swift 侧 file:line 出处；并发模型从 Swift `actor` 改写为 C# `lock` 短临界区、`stop()` 状态机、双向 approval join、F7 敏感字段脱敏、M5（Stage A 收口的死锁修复）在 C# 侧同步落地。25/25 跨端 parity 测试通过 + 完整 D2 JSON 往返业务字段一致（唯一差异是时间戳格式 `Z` vs `+00:00`，定位为 SG-1 codegen 阶段 `D2.cs` 层的既有差异，非本轮引入，记未来 SG-1 收尾处理）。
  - **★审查闸2 第一次派发**：hopper 派 codex（T-046）——**被 codex 自身 cybersecurity 过滤器中止**，跑 `csi` 命令被拦截，exit 1，无 verdict 产出。记为 hopper 边用边验证观察点（详见下）。
  - **★审查闸2 改派**：hopper 派 grok（T-047）——判 **PASS_WITH_NOTE**：并发锁模型正确、M1-M6 逐条对齐 Swift 权威实现、parity 测试确认为真驱动（非抄 Swift 期望值）25/25、无 C# 特有回归；给出 3 项 NOTE。

- **NOTE-1 收尾（`6cf2dcc5`，Swift+C# 两端同步修）**：修复 T-047 NOTE-1 指出的一处**两端共有的真实 bug**——`transport-close-during-stop` 场景下永久挂起（连接在 `stop()` 等待期间关闭，`PendingStop.Waiter` 从未被 resolve）。改造为三态 waiter，`cleanup` 前先 resolve 并发出 `operation_completed(outcome: aborted_effect_unknown)` 镜像事件；`stop()` 按最终 outcome 分流抛出对应 transport 错误。修复过程中，为该场景编写的复现测试**自己又抓出一个次生矛盾事件 bug**——`catch` 分支在无条件路径下会重复发出第二条镜像事件——一并修复。NOTE-2（超时场景应标记为 `TerminalEmitted`）与 NOTE-3（C# `Dispose` 清理）顺带收尾。两端各新增 NOTE-1 复现单测（修复前 fail、修复后 pass，作为回归护栏）。收尾后 Swift 26/26 + C# 26/26，主会话独立复跑双端确认。

**两个 hopper 边用边验证观察点（如实记录，非本轮修）**：
1. **grok 尾部 auth-fail（T-042 先例）**：grok 派发偶发在任务尾声遇 `XAI_API_KEY` 失效，但审查本身已产出可用 verdict——本轮未复现，仅作既有观察点延续记录。
2. **codex 安全过滤器中止评审（T-046，本轮新观察点）**：codex 跑 `csi`（codex 自身命令）被其内置 cybersecurity 过滤器拦截，进程 exit 1、无 verdict 产出，不是 REWORK/PASS 判定，而是评审本身未能执行完成。已按既定纪律改派 grok（T-047）完成★审查闸2，未强行采信 codex 的 exit code 或自述作为 verdict。已记入 hopper 观察点，供后续插件迭代参考。

**诚实 defer（两端一致，非本轮 scope）**：
- `interrupt()`/`respondApproval()`/`capabilities()` 仍是 `notImplemented` 桩，未在本轮做实。
- `capability_changed`/`approval_buffer_resolved` 两个 D2 事件变体仍 unsupported（Stage A 的 11 变体映射覆盖了这两个变体的**类型/字段结构**，但两端客户端尚无对应的产品逻辑消费路径）。
- C# 侧尚无真实 openclaw live e2e（Stage B 的真实客户端驱动 e2e 目前只在 Swift 端做过；C# 端验证限于跨端 parity 回归，未独立对隔离 openclaw 内核跑一遍）。
- 非 exec-tool 的 `output` 字段观察到 null——这是 openclaw 协议本身的缺口（协议未提供该字段的真实值来源），如实记录为协议现状，非客户端编造。
- 金标 parity 完整三端 runner（Swift/C#/TS 三端 + 完整 fixture 集合）仍结转 **SG-8.7**，本轮仅在 Swift/C# 两端之间做了 parity 回归。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E16 | `app/kernel-client/swift/`（含 tests）+ `app/kernel-client/csharp/`（含 tests）；关键 commits `a07dc67`/`db489f0e`/`f303f608`/`02a22c0b`/`3ae6fa81`/`6cf2dcc5` | static+runtime | Swift 26/26 + C# 26/26 单测（含 M1-M6 与 NOTE-1 的真 actor 级测试）+ Stage B 真实客户端驱动 live e2e（9 条 D2 事件字段级断言全 PASS + new-api 计费 id=39 与 usage 逐字段吻合，主会话独立复验）+ 跨端 parity 逐字段一致（唯一差异为已知的 D2.cs 时间戳格式，记未来 SG-1 收尾）+ 3 次异构对抗审（T-044 codex REWORK → T-045 codex MUST-FIX → T-047 grok PASS_WITH_NOTE）；已登记 `state/evidence-index.md` E16 |

## Handoffs Closed

- hopper 派发 4 次，均已闭合（`.hopper/queue.md` 对应行 status=done/failed）：
  - **T-044**（codex，code-review-adversarial）：Stage A 初版对抗审，Verdict REWORK（8 findings，含 1 CRITICAL）→ 已收残 `db489f0e`。
  - **T-045**（codex，code-review-acceptance）：Stage A 收残确认性再审，Verdict MUST-FIX（M1-M6）→ 已收残 `f303f608`。
  - **T-046**（codex，code-review-adversarial）：★审查闸2 首次派发，**failed**——codex 自身 cybersecurity 过滤器中止（跑 `csi` 被拦，exit 1，无 verdict）→ 已改派 T-047。
  - **T-047**（grok，code-review-adversarial）：★审查闸2 重派，Verdict PASS_WITH_NOTE（3 项 NOTE）→ NOTE-1 已收尾 `6cf2dcc5`，NOTE-2/NOTE-3 已顺带处理。
- 每次 codex 评审完成/中止后均按 CLAUDE.md「codex 评审三项强制核对」核对：(a) 实际审查对象与 brief 指定目标一致（T-044 对 `a07dc67`、T-045 对 `db489f0e`、T-046 意图对 `3ae6fa81`）；(b) 产物落在 brief 指定路径（`.hopper/handoffs/T-0xx-output.md`）；(c) 未仅凭 exit code 或 codex 自述采信——T-046 exit 1 且无 verdict 时未误判为"通过"或"沉默即通过"，而是识别为评审未执行完成并改派。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-5（kernel-client 完整化）完整闭合，两个 ★审查闸均已通过，证据充分且收敛：

- **★审查闸1（Stage A）**：经两轮独立审查真正收敛——T-044（codex）判 REWORK，揪出 CRITICAL 级凭证明文入日志缺陷；第一次收残 `db489f0e` 后，T-045（codex，确认性再审）未简单放行，反而独立发现"收残本身引入了新死锁"以及"测试是替代场景、假绿掩盖真实缺陷"这一更深层问题；第二次收残 `f303f608` 按精确指出的 M1-M6 收口 + 重写为真 actor 级测试，25/25 通过。**这正是独立审查机制的价值所在**——若只做一次性对抗审而无确认性再审，第一次收残引入的新死锁与假绿测试将被放过。
- **Stage B（真 client 驱动 e2e）**：真实 Swift 客户端（非探针）驱动的完整链路，9 条 D2 事件字段级断言全 PASS，计费日志与运行时 usage 逐字段吻合，主会话独立复验（独立查 new-api 日志）。
- **★审查闸2（Stage C）**：首次派发（T-046，codex）遭遇 codex 自身安全过滤器中止（非 REWORK/PASS，而是评审未能执行），按既定纪律未强行采信、改派 grok（T-047），判 PASS_WITH_NOTE——并发锁模型正确、M1-M6 逐条对齐、parity 测试真实性确认（非抄 Swift 期望值）、无 C# 特有回归。
- **NOTE-1 收尾**：T-047 的 NOTE-1 揪出的是 Swift+C# **两端共有的真实 bug**（transport-close-during-stop 永久挂起），修复过程中复现测试自身又带出一个次生矛盾事件 bug——**这也是独立审查机制的价值**：NOTE 级发现同样定位到真实缺陷，未因 verdict 已是 PASS_WITH_NOTE 而被忽略。
- 收敛守卫设置（连续 MUST-FIX 达第 3 轮即停报，而非无限收残）**在本轮全程未被触发**——Stage A 两轮（T-044 REWORK → T-045 MUST-FIX）后第二次收残即彻底收敛，未进入第三轮。
- 两个 hopper vendor 边用边验证观察点（grok 尾部 auth-fail 先例、codex 安全过滤器中止评审）已如实记录，属本项目"边用边验证插件"的既定纪律产出，非隐瞒。
- 诚实 defer 项（`interrupt`/`respondApproval`/`capabilities` 桩、`capability_changed`/`approval_buffer_resolved` unsupported、C# 侧真 openclaw live e2e、非 exec-tool output null、gold parity 完整三端）均已如实标注，未顺带声称已完成。

无 negative / 未决评审悬置，故本轮 feedback 分类 **positive**。

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

见 rounds/0005/decision.md：feedback = **positive**；裁决 = **SG-5 done（kernel-client 完整化闭合客户端交互环，A/B/C 三阶段 + 两个 ★审查闸全部达成）**；**continue 驱动 + 关键节点独立审查机制首次完整实战并验证有效**（★1 揪出并修复 CRITICAL 凭证泄漏 + 死锁 + 假测试根因，★2 揪出真实两端共有挂起 bug）；收敛守卫未触发第 3 轮 MUST-FIX（Stage A 第二次收残即收敛）；下一步待选 **SG-3**（codegen CI 冒烟挂接）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针、SG-8.7 gold parity runner 完整三端）/ 既有副发现处理。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker——T-046 codex 安全过滤器中止属评审执行层面的可恢复情况，已按既定改派路径当场解除，不构成收盘时的阻断）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待选 **SG-3**（codegen 管线增量：CI 冒烟挂接 + `EmptyPayload`/`WireCapabilityDescriptorPayload` type-level 断言）/ **SG-7**（hermes per-session key 接线，二选一路径任一端到端验证）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针待重启隔离内核后执行；SG-8.7 金标 parity runner 补齐三端 + 三组 fixture）/ 副发现（`app/server` body-parser limit 调大、`OPENCLAW-ISOLATED-RUN-RECIPE.md` 补 `OPENCLAW_WORKSPACE_DIR`、2 个 openclaw bug 上游反馈决策类待办若尚未处理）
- User input required: 否（SG-5 本身已完整交付，闭合不需用户进一步确认）

## Open Risks

- **C# 侧尚无真实 openclaw live e2e**——Stage B 的真实客户端驱动 e2e 目前只在 Swift 端做过一次；C# 端的验证限于跨端 parity 回归（对同一组 fixture/事件样本逐字段比对），未独立对隔离 openclaw 内核跑一遍完整轮次。建议后续补一次 C# 端 live e2e，非本轮 done 判定前提（parity 回归已充分证明两端行为一致）。
- **`interrupt()`/`respondApproval()`/`capabilities()` 仍是桩**——两端一致，D1 KernelPort 窄腰 7 方法中这 3 个仍返回 `notImplemented`，如实记录，非本轮 scope。
- **`capability_changed`/`approval_buffer_resolved` 两个 D2 事件变体产品逻辑消费路径缺失**——Stage A 的类型/字段映射已覆盖，但两端客户端尚无实际消费这两类事件的产品逻辑，需后续 SG 补齐。
- **非 exec-tool `output` 字段观察为 null**——诚实记录为 openclaw 协议本身缺口（协议未提供该字段真实值来源），非客户端实现缺陷，非编造掩盖。
- **金标 parity 完整三端 runner 未建**——本轮仅达成 Swift/C# 两端 parity 一致；TS 端 runner 及完整三组 fixture（审批五态 FSM/`OperationOutcome` 全集/`SessionLockState` 四态）仍结转 **SG-8.7**。
- **D2.cs 时间戳格式差异（`Z` vs `+00:00`）**——跨端 parity 测试中观察到的唯一差异，定位为 SG-1 codegen 阶段既有的 D2.cs 层差异，非本轮引入，记未来 SG-1 收尾处理。
- **两个 hopper vendor 边用边验证观察点未处理，仅记录**：grok 尾部 auth-fail（先例，T-042）、codex 安全过滤器中止评审（本轮新增，T-046，跑 `csi` 被拦）——均为"边用边验证插件"纪律下的观察产出，是否需要插件侧适配（如 codex 安全过滤器白名单/降级提示）留待后续决定，非本轮 scope。
- **rounds/0004 遗留的决策类待办**（2 个 openclaw bug 是否上游 push/开 issue、主仓库 submodule 指针 commit 时机等）——若尚未在本轮之外处理，仍作为独立待办延续，不属于本轮 SG-5 范围。

## Next Proposed Scope

**SG-5 已闭合**，goal 002 客户端交互环首次完整闭合（Swift+C# 双端 kernel-client 可信、跨端 parity、经 3 次异构对抗审 + 真实客户端驱动 e2e）。下一步从以下几项中择一或并行：**SG-3**（codegen 增量：CI 冒烟挂接 + type-level 断言）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针 + SG-8.7 gold parity runner 完整三端 + D4 §4.6 产品逻辑层 parity 首批 5 类）/ 副发现与决策类待办处理。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
