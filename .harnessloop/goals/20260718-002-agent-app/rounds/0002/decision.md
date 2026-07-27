# Decision

- Feedback: positive
- Blocker type: none
- Recovery eligible: 不适用（无 blocker）
- Accepted: yes
- Review: none — 本轮为实现类编码（SG-4 kernel-client + Mac 最小壳），按项目规则 code-impl 一律不派第三方 vendor；验收由主会话独立复验（重编 Swift 壳 + 重跑 live 闭环）完成
- Reviewer: main session (self-verified)
- Review verdict: not-applicable
- Active goal: 20260718-002-agent-app
- Active round: 0002（SG-4 打通真实运行内核，探索性 de-risk 轮）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-23

## Reason

SG-4 的验收边界由 scope-lock 预先诚实分层为 L1（连通闭环，本轮必达）/ L2（`send` 完整闭环，本轮尽力）/ gold parity（明确不做，defer SG-8.7）。执行结果：**L1 已达成**——kernel-client（Swift `swiftc` 编译 exit 0、C# `dotnet build` succeeded）对着真实运行的 openclaw 内核完成 `connect → createSession → subscribe 收真实 KernelEvent 流 → stop` 一次完整闭环（`app/kernel-client/RUN-EVIDENCE.md` 逐帧证据），**且主会话独立复验**（重新编译 Swift 壳 + 重跑一次闭环对着 live 隔离内核，结果与执行子代理报告一致，非仅采信自述）。L2（`send`）经 de-risk 探针坐实无 mock/echo provider、必触发真实模型调用，按 scope-lock Rollback Condition 明确 defer，不构成"L1 达成"之外的额外扣分。

证据充分（编译产物 + live 逐帧证据 + 独立复验）且收敛（L1/L2/parity 边界清晰、无一处把未证部分表述为已过），故本轮 feedback 分类 **positive**。

本轮同时是本项目**首个"scope-lock 先于执行、走完整 round → decision → state 回写闭环"的执行轮**——兑现 evolution-issue 0010 记录的教训（对比 rounds/0001 补记轮坐实的 SG-1/SG-2/SG-6 此前均绕开该闭环）。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-4 的 done 严格限定为「L1 连通闭环」**：`createSession`/`subscribe`/`stop` 对真实运行内核 live 通、经主会话独立复验，达 done 标准。`send`（L2）/完整 openclaw→D2 事件适配（当前仅 1/11 变体）/ gold parity（审批五态/`SessionLockState`，对 SG-1 fixture）/ 计费 token 归因均**未纳入本轮 done 范围**，分别收编 **SG-8.1**（send，待 provider）、**SG-5**（完整事件适配，需真实 send 样本）、**SG-8.7**（gold parity runner 补齐）、**SG-8.5**（计费链）。
- **执行中的偏离已裁定为在 scope-lock 授权范围内**：real running kernel 从"用户全局 gateway 实例"调整为"本项目自建隔离实例"（`ws://127.0.0.1:18889`），因 scope-lock 本身标注本轮为探索性 de-risk 轮、允许探针驱动调整启动配置（Runtime Recovery Limits 条款），且严格遵守了 Disallowed Changes（未改 `kernels/openclaw` 源码）与 Rollback Condition。该调整已在 round-summary 如实记录，未回改 scope-lock 掩盖偏离。
- **下一步待选**：SG-3（codegen 增量，注意与 SG-1 已交付部分不重复）/ **SG-5**（完整 openclaw→D2 事件适配，优先——是 EventMapping 从 1/11 补齐到完整覆盖的必经路径，且需真实 send 样本，与 SG-8.1 存在依赖顺序需评估）/ SG-7（hermes per-session key 接线）/ SG-8（build+run 内核验收批次，SG-4 L1 已为 PRE-1/3/7 runtime 探针提供部分底座）。

## Open Questions Resolved

- de-risk 探针坐实"gateway:dev 启动失败"的真实根因：`--dev` 自举代码（`ensureDevGatewayConfig()`）写出的 `agents.list` 数组形状与本 pin 版本 zod schema（只认 `defaults`/`entries`）不兼容，与"读了用户全局配置"无直接关系——recipe 已避开 `--dev`，用显式 env 隔离启动成功，见 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`。
- `send` 是否可 mock 跑通：不能。源码无 echo/mock/fixture provider，`sessions.create` 响应即带真实 `resolved.model`，一旦 send 必触发真实模型调用——已按 scope-lock 纪律 defer，不擅自发起付费调用。

## Open Questions Deferred

- SG-8.1（send e2e wire）：待真实/廉价 LLM provider 就绪。
- SG-5（完整 openclaw→D2 事件适配，10/11 变体）：需真实 send 触发的 wire 样本，待 SG-8.1 或独立 send 探针提供样本后启动。
- SG-8.7（gold parity runner）：Swift/C#/TS 三端 parity runner 均未建，`app/parity/` 空，待专门批次补齐。
- SG-8.5（计费链 e2e）：newapi 计费 token 归因字段仍为占位符。
- C# 端 live 闭环缺口：`IKernelClient.cs` 本轮只做到接口骨架 + 编译通过，未做实际 WS 连接验证；SG-5（Windows parity 追赶）启动前需先补齐或明确调整 scope。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E12（拟登记） | app/kernel-client/swift/、app/kernel-client/csharp/、app/kernel-client/RUN-EVIDENCE.md | SG-4 L1 达成 + 主会话独立复验的直接依据 |
| recipe 保全 | app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md | de-risk 探针发现（`--dev` 根因、鉴权握手、RPC 帧序列、send provider 结论）的完整依据；SG-5/SG-8 重启隔离内核的可复用资产 |

## Next Action

- Action type: next-subgoal
- Scope-lock required: yes（下一 SG 开 round 时新建 scope-lock）
- Human confirmation required: 否（L1 verdict 基于既有证据 + 主会话独立复验，不需用户确认）
- Safe without user input: yes
- Recovery round objective: 不适用（本轮无 blocker，非 recovery round）
- Disallowed until confirmed: 不得把 SG-4 表述为「完整闭环（含 send/完整事件适配/gold parity）已过」直至 SG-8.1/SG-5/SG-8.7 分别通过；不得借本决策之名对真实付费 LLM 发起未经用户确认的调用
