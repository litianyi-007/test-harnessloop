# Scope Lock

## Round Objective

**SG-5 kernel-client 完整化——闭合客户端交互环**：把 SG-4 交付的 kernel-client 骨架(Swift `send`/`interrupt` 等为 `notImplemented` 桩、EventMapping 仅 1/11 变体、C# 仅接口骨架)补成**真 client 能驱动完整 agent 轮次**,让实际 Swift/C# 客户端(非探针)驱动 SG-8.5 已证通的全链 `client send → openclaw(d3proxy provider) → D3-proxy(per-session 换凭证) → 自托管 new-api → Kimi → 事件流回 client 并映射为 D2 KernelEvent`。

**scope 澄清(据实,非扩张)**：goal-breakdown 原 SG-5="C# parity+金标回归",SG-4 把"完整 openclaw→D2 事件适配(10/11 变体)"明确 defer 给 SG-5;`send` 能力已在 SG-8.5 用 node 探针端到端证过,本轮做的是让**真 kernel-client** 自己驱动它(客户端侧完成)+ 事件适配 + 跨端 parity。故本轮 SG-5 涵盖:Swift send/事件适配 + 客户端驱动 e2e + C# parity + 金标回归(与 SG-8.7 衔接)。

## 驱动模型:continue 驱动 + 关键节点独立审查(用户 2026-07-24 指定)

本轮由 **`$harnessloop-continue` 逐阶段驱动**;每阶段内**尽量自动化**(写码派主会话 claude-sonnet-5 子代理,主会话只读审+验收);**关键节点引入独立性审查**(异构对抗:hopper 派 codex/grok 随机池)。`current.md` 的 Next proposed action 记录当前阶段;每次 continue 推进一个阶段/闸。

### 阶段与审查闸

| 阶段 | 内容 | 执行 | 闸 |
|---|---|---|---|
| **A** | Swift `send` 做实(`OpenclawGatewayKernelClient.send` 走 `sessions.send`)+ **完整 openclaw→D2 事件适配**(EventMapping 补齐 11 个 `EventMessageUnion` 变体:tool_call/tool_result/thinking/approval_request/turn_complete/session_end/capability_changed/operation_completed/approval_buffer_resolved 等,据 D1 KernelPort 语义 + D2 事件 schema + 真实 openclaw `session.message` 帧) | Sonnet 子代理 | **★审查闸1**(A 后):异构对抗审 send 实现 + 事件适配正确性(对 D1/D2 契约 + openclaw 帧);REWORK 则先收残再进 B |
| **B** | **真 Swift client 驱动 e2e**:重起隔离 openclaw(d3proxy provider,复用 SG-8.5 现场 D3-proxy 3001/Pi 组件)→ Swift kernel-client `createSession→send→subscribe 收 agent 输出事件并映射为 D2 KernelEvent→stop` 完整轮 → new-api 计费落账印证 | 主会话驱动 + 独立复验 | 功能证成(非审查闸;客户端证的链 vs SG-8.5 探针证的链) |
| **C** | **C# kernel-client parity**:`IKernelClient` 从接口骨架补成功能实现(send + 事件适配,引用 D2 C# DTO);Swift/C# 跨端在已落地 fixture 上逐字段一致 | Sonnet 子代理 | **★审查闸2**(C 后):异构对抗审 C# parity + 跨端一致性(衔接 SG-8.7 金标 parity) |

**金标 parity runner(SG-8.7)**：本轮至少让 Swift/C# 两端对同一组 fixture 产生逐字段一致的可观察状态(SG-5 验收列);完整三端 runner 基建若超本轮成本,明确标注结转 SG-8.7。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/kernel-client/swift/`、`app/kernel-client/csharp/` | 写 | send 实现 + EventMapping 补齐 + C# 功能化 |
| `app/parity/`（若建 parity fixture/runner） | 新建 | Swift/C# 跨端一致性 fixture/断言 |
| 隔离 openclaw 运行(scratchpad profile,d3proxy provider) | 运行 | B 阶段 e2e;**不改 kernels/openclaw 源码**(用 fork 补丁后的版本);别碰用户 18789 |
| `.harnessloop/goals/.../rounds/0005/` + state | 写 | round 逐阶段收口 |
| `.hopper/`（queue/handoffs） | 写 | 审查闸派发记录 |
| scratchpad | 写 | 探针/隔离配置 throwaway |

## Disallowed Changes

- 改 `kernels/openclaw`/`app/server`/newapi 源码——本轮是补 client,不动已收口的内核/server(若必须改,停下记 blocker 上报)。
- 凭证入 tracked(Kimi key/newapi token/static key 走 gitignored channel-params/env)。
- 三插件 submodule、wiki(除非审查发现需修设计 doc)。
- 借本轮启动 SG-3/SG-7/UI 等其它子目标的编码。

## One-Variable Strict Mode
- Enabled: no
- Reason: 多阶段客户端完整化 + 双端 parity,分阶段推进。

## Verification Commands Or Checks

| Check | Method | Expected | Evidence |
|---|---|---|---|
| A: send+事件适配编译 | `swiftc` 编译 kernel-client(引用 app/generated/swift) | exit 0 | 编译输出 |
| A 审查闸1 | hopper 派 codex/grok 审 send/事件适配 | PASS/PASS_WITH_NOTE(REWORK 则收残) | `.hopper/handoffs/T-0xx-output.md` |
| B: 客户端驱动 e2e | Swift client 对隔离 openclaw send → 收 agent 输出事件(映射 D2)+ new-api `/api/log/` 计费条目 | 真实 Kimi 回复经 client 事件流 + 计费落账 | 运行日志 + new-api log |
| C: C# 功能 + 跨端 parity | `dotnet build/test` + Swift/C# 同 fixture 逐字段一致 | 编译过 + parity 一致 | parity 报告 |
| C 审查闸2 | hopper 派 codex/grok 审 C# parity | PASS(REWORK 则收残) | handoff |

## Runtime Recovery Limits
- Recovery round: 可能(隔离 openclaw 起不来/事件帧与预期不符/parity 不一致 → 只读诊断+调实现迭代)
- Blocker type: 预期 `runtime-recoverable`(实现);若发现须改内核/server 源码=`contract-insufficient` 停下上报
- Cleanup: B 阶段隔离 openclaw 用后 kill;现场 D3/Pi 组件保持(SG-5 各阶段复用)或收尾统一停

## Rollback Condition
若某阶段发现必须改 kernels/openclaw 或 app/server 源码才能通(如事件帧缺字段、D3-proxy 需改),停在该阶段边界、明确 defer + 记 blocker,不擅改已收口/已 validated 组件。

## Human Confirmation Required
- 各阶段自动化执行 + 审查闸派发:用户已授权"continue 驱动 + 关键节点独立审查",无需逐阶段确认。
- B 阶段 send e2e 触发真实 Kimi 计费:用户已提供上游 key 即确认;调用保持最小 prompt。
- 审查闸 REWORK 的收残:属本轮 recovery,自动进行;若收残需改内核/server(越出 client 范围)则停下上报。
