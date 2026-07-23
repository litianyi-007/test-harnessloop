# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0002（实现阶段第二轮 · SG-4 打通真实运行内核，探索性 de-risk 轮）
- Scope-lock: rounds/0002/scope-lock.md（v1）
- Started: 2026-07-23
- Completed: 2026-07-23

## What Changed

本轮是本项目**首个「scope-lock 先于执行、走完整 round → decision → state 回写」的执行轮**——兑现 evolution-issue 0010 记录的教训（rounds/0001 补记轮坐实：SG-1/SG-2/SG-6 此前均绕开 round 闭环、走 hopper 对抗审即验收）。scope-lock 先锁定 SG-4 的验收边界（诚实分层：L1 连通性必达 / L2 完整闭环尽力 / gold parity 明确不做），再动手执行，执行过程中的一处偏离（见下）已在收盘时如实记录，未回改 scope-lock 掩盖。

**SG-4 L1（连通闭环）已达成，并经主会话独立复验**：kernel-client 对着真实运行的 openclaw 内核完成 `connect → createSession → subscribe 收真实 KernelEvent 流 → stop` 一次完整闭环。主会话独立复验方式：重新编译 Swift 壳（`swiftc` exit 0）+ 重跑一次闭环对着 live 隔离内核，确认结果与执行子代理报告一致。

**执行中的关键偏离（如实记录）**：scope-lock 原定"对手动启动的本地 openclaw gateway"（隐含用户全局 `ws://127.0.0.1:18789` 实例）验证；de-risk 探针发现该端口正是用户全局 gateway 常驻进程（PID 5197）后，改为在全新隔离目录起**本项目自建的独立 openclaw 内核实例**（`ws://127.0.0.1:18889`），全程未连接/未干扰用户全局 gateway。这一调整是本轮 de-risk 性质的应有产物（scope-lock 本就标注"探索性，须先 de-risk 探针摸清"），未改内核源码、未违反 Disallowed Changes 与 Rollback Condition。

**de-risk 关键发现**：openclaw `--dev` flag 自身调用 `ensureDevGatewayConfig()` 写出 `agents.list`（数组形状），与本 pin 版本的 zod schema（`AgentsSchema` 只认 `defaults`/`entries`）不兼容，必现 "Config validation failed: agents: Unrecognized key: list"——这是比"读了用户全局配置"更精确的根因（`--dev` 自举代码本身与当前 schema 不同步，全新空 profile 也会踩雷）。recipe 因此避开 `--dev`，改用 `OPENCLAW_STATE_DIR`（全新空目录）+ `--allow-unconfigured` + 显式 `--token` + `client:{id:"cli",mode:"cli"}` 握手（保留 `operator.write` 等自报 scope，避免设备配对流程），成功隔离启动于端口 18889。完整 recipe 已保全至 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`（供 SG-5/SG-8 重启隔离内核复用）。

**本轮 defer（诚实分层，避免"done 名不副实"）**：
- `send`（`sessions.send`）：源码核验坐实无 echo/mock/fixture provider，`sessions.create` 响应即带真实 `resolved:{modelProvider:"openai",model:"gpt-5.6-sol"}`——一旦 send 必触发真实模型调用。按 scope-lock Rollback Condition（"若 send 强依赖真实付费 LLM 且无安全 mock/廉价路径，则停在 L1 边界"），本轮不发起 send，defer 至 **SG-8.1**。
- 完整 openclaw → D2 事件适配（`EventMapping.swift` 当前仅映射 `session.message` 1/11 变体）：其余 10/11 变体需真实 send 样本才能适配，defer 至 **SG-5**。
- `respondApproval`/`capabilities`：`OpenclawGatewayKernelClient.swift` 当前为 `notImplemented` 桩，后续补齐。
- gold parity（审批五态 / `SessionLockState` 四态，对 SG-1 fixture）：Swift/C# parity runner 尚未建（`app/parity/` 空），defer 至 **SG-8.7**。
- newapi 计费 token 归因：D1 §7 定义的字段本轮仍为占位符，待 **SG-8.5**。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E12（拟登记，见 evidence-index.md） | app/kernel-client/swift/（KernelClient.swift、OpenclawGatewayKernelClient.swift、OpenclawWire.swift、EventMapping.swift、CLIRunner.swift、main.swift）+ app/kernel-client/csharp/（IKernelClient.cs + csproj）+ app/kernel-client/RUN-EVIDENCE.md | runtime | swiftc 编译 exit 0 + dotnet build succeeded + 对隔离内核 `ws://127.0.0.1:18889` 的 live 闭环逐帧证据（连接/createSession/subscribe/abort/delete 全 `ok:true`，退出码 0）；主会话独立复验通过 |
| recipe 保全 | app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md（拷贝自 scratchpad/sg4-openclaw-run-recipe.md） | source | openclaw 隔离启动/鉴权握手/RPC 帧序列/send provider 结论的完整源码级 recipe，可复用重启隔离内核 |

## Handoffs Closed

- 无 hopper 派发——本轮为实现类编码（kernel-client 骨架 + Mac 最小壳打通运行内核），按既定规则一律由主会话 claude-sonnet-5 子代理执行，不派第三方 vendor。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——L1（连通闭环）验收边界内证据充分且收敛：

- 客户端可编译（Swift `swiftc` exit 0，C# `dotnet build` succeeded）。
- 对真实运行内核（本项目自建隔离实例，非 mock）完成 `connect → createSession → subscribe → stop` 完整闭环，逐帧证据齐全（`RUN-EVIDENCE.md`）。
- **主会话独立复验**：不仅采信执行子代理报告，主会话重新编译并重跑一次闭环对着 live 隔离内核，结果一致。
- L2（`send`）/完整事件适配/gold parity 均按 scope-lock 诚实分层明确 defer，未把未证部分表述为已过——无"done 名不副实"风险。
- 执行中的一处偏离（真实内核实例从"用户全局"调整为"本项目自建隔离实例"）已如实记录在 What Changed，不构成对 scope-lock 的隐性违反（scope-lock 本身标注本轮为探索性 de-risk 轮，允许探针驱动调整）。

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
- Estimated cost: unavailable（执行子代理的实际开发/调试成本已在其原执行会话消耗，未在本次状态回写中单独记账）

## Decision

见 rounds/0002/decision.md：feedback = **positive**；裁决 = SG-4 **L1（连通闭环）达成**，验收边界严格限定 L1（`createSession`/`subscribe`/`stop` 对真实运行内核 live 通），L2（`send`）/ 完整事件适配 / gold parity 明确 defer（收编入 SG-8.1、SG-5、SG-8.7）；下一步待选 **SG-5 / SG-3 / SG-7 / SG-8**。

## Blocker Classification

- Blocker type: none
- Recovery eligible: 不适用（无 blocker）
- Safe next action: 待选 **SG-5**（Windows C# kernel-client parity 追赶——但 SG-4 本轮只交付 Swift 端 live 闭环，C# 端仅接口骨架编译过，尚无 live 闭环，SG-5 启动前需先补 C# 端 live 验证或调整 SG-5 scope）/ **SG-3**（codegen 增量，注意与 SG-1 已交付部分不重复）/ **SG-7**（hermes per-session key 接线）/ **SG-8**（build+run 内核验收批次，SG-4 L1 已为其提供部分底座）
- User input required: 否（L1 verdict 基于既有编译产物 + live 闭环证据 + 主会话独立复验，不需用户确认）——但 L2 `send` 一旦要发起真实付费 LLM 调用仍需用户确认（scope-lock Human Confirmation Required 条款），本轮未触发

## Open Risks

- **SG-4 done 是 L1 级、非完整闭环**：`send`/完整事件适配/gold parity/计费归因均未证，分别收编 SG-8.1/SG-5/SG-8.7/SG-8.5，在这些子项通过前不得把 SG-4 表述为「完整闭环已过」。
- **本轮验证对象是本项目自建隔离内核实例，非用户全局 gateway 实例**：两者是同一份 pin 版本源码的不同运行实例，行为应一致，但严格讲"对着真实运行内核"验证的是隔离实例；若后续发现隔离实例与全局实例有配置差异导致的行为不一致，需重新探针。
- **C# 端尚无 live 闭环**：`IKernelClient.cs` 只有接口骨架 + `dotnet build` 编译通过，未对内核做实际 WS 连接验证，SG-5（Windows parity 追赶）启动前需明确这一缺口。
- **EventMapping 覆盖率低**：11 个 D2 EventMessageUnion 变体中仅映射 1 个（`session.message`），其余 10 个需真实 send 触发才能观察真实 wire 形态并适配，是 SG-5 的核心工作量来源。

## Next Proposed Scope

实现阶段继续从 **SG-3 / SG-5 / SG-7 / SG-8** 中择一开新 round，**每个 SG 逐个走 round → decision → feedback → state 回写闭环**（本轮起兑现，不再绕开）。优先建议 **SG-5**（完整 openclaw → D2 事件适配，需真实 `send` 样本，是 EventMapping 从 1/11 补齐到完整覆盖的必经路径）或 **SG-8** 的部分子项（SG-4 L1 已为 PRE-1/3/7 runtime 探针底座提供基础，可评估哪些 SG-8 子项现在具备启动条件）。SG-3（codegen 增量）可并行推进，注意与 SG-1 已交付部分不重复。
