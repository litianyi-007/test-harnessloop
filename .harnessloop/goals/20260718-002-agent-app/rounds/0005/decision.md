# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker；T-046 codex 安全过滤器中止属评审执行层面的可恢复情况，已按既定改派路径当场解除）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Review: .hopper/handoffs/T-047-output.md
- Reviewer: grok via hopper T-047
- Review verdict: pass-with-note
- Review digest: 969f1c4696e8ce85f8eef6267b59d67907478cc085f4dfbdd80a31fe1a8c08ee
- Active goal: 20260718-002-agent-app
- Active round: 0005（SG-5 kernel-client 完整化，闭合客户端交互环）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-24

## Reason

SG-5 的验收边界由 scope-lock 明确为"把 SG-4 defer 给 SG-5 的三项（Swift `send` 做实 + 完整 openclaw→D2 事件适配 11 变体、真 client 驱动 e2e、C# parity）全部做实，并让真实 kernel-client 驱动完整 agent 轮次"，驱动模型为 **continue 驱动 + 关键节点独立审查**（用户 2026-07-24 指定）。执行结果：**A/B/C 三阶段全部达成，两个 ★审查闸均通过**——

- Stage A（`a07dc67`）Swift `send` 做实 + 事件适配 11 变体初版落地，经 ★审查闸1 两轮独立审查（T-044 codex REWORK → 收残 `db489f0e` → T-045 codex 确认性再审 MUST-FIX → 第二次收残 `f303f608`，真 actor 级测试 25/25）真正收敛。
- Stage B（`02a22c0b`）真实 Swift kernel-client（非探针）驱动隔离 openclaw→D3-proxy→自托管 new-api→Kimi 完整链，9 条真实 D2 事件字段级断言全 PASS，new-api 计费 id=39 与 usage 逐字段吻合，主会话独立复验。
- Stage C（`3ae6fa81`）C# kernel-client 从骨架补成功能实现，忠实镜像 Swift 权威实现，25/25 跨端 parity + D2 JSON 往返业务字段一致，经 ★审查闸2（T-046 codex 中止 → 改派 T-047 grok PASS_WITH_NOTE）。
- NOTE-1 收尾（`6cf2dcc5`）：Swift+C# 两端共有的 transport-close-during-stop 永久挂起真实 bug 已修复，复现测试自身又抓出并修复一处次生矛盾事件 bug；两端各加回归单测，Swift 26/26 + C# 26/26，主会话独立复跑双端。

证据充分（每阶段均有独立可核验证据：Stage A 真 actor 级测试+对抗审记录、Stage B live e2e 字段级断言+计费吻合、Stage C 跨端 parity 逐字段一致+异构对抗审、NOTE-1 修前 fail/修后 pass 回归测试）且收敛（收敛守卫未触发第三轮 MUST-FIX，无一处把未证部分表述为已过，defer 项均如实标注），故本轮 feedback 分类 **positive**。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **本轮是 goal 002 首次以"continue 驱动 + 关键节点独立审查"这套机制驱动的完整执行轮**，且首次完整跑通并见效：
  - **★审查闸1（Stage A）验证了确认性再审（第二轮）不可省略**——若只做 T-044 一次性对抗审，第一次收残 `db489f0e` 引入的新死锁与"假绿测试"（替代场景掩盖真实缺陷）将被放过而进入 Stage B。T-045 的确认性再审正是为核验"上一轮收残是否真闭合、有无引入新问题"而设，本轮实证了这一环节的必要性。
  - **★审查闸2（Stage C）的 NOTE-1 同样定位到真实缺陷**——PASS_WITH_NOTE 的 verdict 未导致 NOTE 级发现被降级忽略，NOTE-1 指出的挂起是 Swift+C# 两端共有的真实 bug，修复中复现测试又带出次生矛盾事件 bug 一并收口。**这正是"关键节点独立审查"机制设计的价值所在**——独立于实现方的第三方视角，能揪出实现方自身难以发现的缺陷类别（凭证泄漏、并发死锁、测试有效性、跨端共有的 timing bug）。
- **T-046 codex 安全过滤器中止评审已按既定纪律处置，非静默跳过**：codex 因自身 cybersecurity 过滤器拦截 `csi` 命令、exit 1、无 verdict 产出，主会话未把这一情况误判为"通过"或"沉默即通过"，而是识别为评审执行失败并改派 grok（T-047）完成审查，符合 CLAUDE.md「codex 评审三项强制核对」纪律（未仅凭 exit code 或 codex 自述采信）。已记为 hopper vendor 边用边验证观察点。
- **收敛守卫（连续 MUST-FIX 达第三轮即停报，避免无限收残循环）设置但未触发**：Stage A 经 T-044（REWORK）→ 第一次收残 → T-045（MUST-FIX）→ 第二次收残，第二次收残即彻底收敛，未进入第三轮 MUST-FIX 循环。
- **两个 hopper vendor 观察点已如实记录，作为本项目"边用边验证插件"纪律的产出**：grok 尾部 auth-fail（延续既有 T-042 先例）、codex 安全过滤器中止评审（本轮新增，T-046）——均非阻塞本轮 done 判定，但已记入 round-summary Open Risks，供后续插件迭代参考。
- **诚实 defer 项均已在 round-summary 中明确标注，非本轮遗漏**：`interrupt()`/`respondApproval()`/`capabilities()` 桩；`capability_changed`/`approval_buffer_resolved` 产品逻辑消费路径缺失；C# 侧真实 openclaw live e2e 未做（仅 parity 回归）；非 exec-tool `output` null（协议缺口，非编造）；金标 parity 完整三端 runner 结转 SG-8.7。
- **下一步待选**：**SG-3**（codegen CI 冒烟挂接 + type-level 断言）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针、SG-8.7 完整三端 gold parity runner）/ 副发现与既有决策类待办处理。

## Open Questions Resolved

- **continue 驱动 + 关键节点独立审查这套机制是否在真实多阶段任务中可行**：可行——本轮完整走过 A→★1(两轮)→B→C→★2→NOTE 收尾全流程，每个阶段的独立审查均定位到真实缺陷（CRITICAL 凭证泄漏、死锁、假测试根因、两端共有挂起 bug），机制本身未空转，亦未因某一 vendor（codex）执行失败而卡死（改派 grok 后正常完成）。
- **"确认性再审"（同一 vendor 对自己上一轮 findings 的收残做二次核验）是否有必要独立于首次对抗审存在**：本轮证实必要——T-045 发现的问题（收残引入新死锁、假绿测试）如果没有这一步会被放过，直接进入 Stage B 会在更下游被发现或被完全遗漏。
- **codex 因自身安全过滤器无法完成评审时应如何处置**：本轮验证了既定路径（不采信 exit code/自述 → 识别为评审失败 → 改派同池另一 vendor）可行，`.hopper/queue.md` T-046 行如实标记 `failed`（非误标为 done/PASS）。

## Open Questions Deferred

- **C# 侧真实 openclaw live e2e**：仅做了跨端 parity 回归，未独立跑一遍真实内核驱动的完整轮次，留待后续（非本轮 done 判定前提，parity 回归已充分证明两端行为一致）。
- **`interrupt()`/`respondApproval()`/`capabilities()` 三桩何时做实**：待后续 SG，非本轮 scope。
- **`capability_changed`/`approval_buffer_resolved` 产品逻辑消费路径**：类型/字段映射已在 Stage A 覆盖，产品逻辑消费待后续 SG。
- **D2.cs 时间戳格式差异（`Z` vs `+00:00`）**：定位为 SG-1 codegen 既有差异，记未来 SG-1 收尾处理，非本轮引入。
- **金标 parity 完整三端 runner（Swift/C#/TS + 完整 3 组 fixture）**：结转 **SG-8.7**。
- **2 个 hopper vendor 观察点（grok auth-fail 先例、codex 安全过滤器中止评审）是否需要插件侧适配**：留待后续决定，非本轮 scope。
- **rounds/0004 遗留决策类待办**（2 个 openclaw bug 上游 push/开 issue、主仓库 submodule 指针 commit 时机等）：若尚未处理，继续作为独立待办延续，不属于本轮 SG-5 范围。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E16 | `app/kernel-client/swift/`（含 tests）+ `app/kernel-client/csharp/`（含 tests）；commits `a07dc67`/`db489f0e`/`f303f608`/`02a22c0b`/`3ae6fa81`/`6cf2dcc5` | SG-5 done（kernel-client 完整化闭合）的直接依据：Swift+C# 双端 26/26 测试 + Stage B live e2e 字段级断言与计费吻合 + 跨端 parity 逐字段一致 + 3 次异构对抗审（T-044/T-045/T-047） |
| E14 | `app/deploy/newapi` + `app/server` + `kernels/openclaw` 补丁 | SG-8.5 计费链 e2e（本轮前置底座之一，Stage B 复用其现场 D3-proxy/Pi 组件），追溯依据 |
| E12 | `app/kernel-client/`（swift/csharp）+ `RUN-EVIDENCE.md` | SG-4 L1 连通闭环（本轮起点，SG-4 defer 给 SG-5 的三项已在本轮做实），追溯依据 |

## Next Action

- Action type: 收盘 → 待选下一 SG 开新 round
- Scope-lock required: yes（下一 SG 开 round 时新建 scope-lock）
- Human confirmation required: 否（SG-5 本身已完整交付，闭合本身不需用户进一步确认）
- Safe without user input: yes（本轮收盘）；下一步若改推 SG-3/SG-7/SG-8.x，一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 从 **SG-3**（codegen 增量）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针 + SG-8.7 gold parity runner）/ 副发现与决策类待办中择一或并行，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 C# 侧真实 openclaw live e2e 表述为"已完成"（目前仅 parity 回归）；不得把 `interrupt`/`respondApproval`/`capabilities` 三桩默认为"已做实"；不得把 2 个 hopper vendor 观察点默认为"已解决"——均明确 deferred，未裁定
