# approval/ 未覆盖场景（SG-8.7 Stage A 诚实登记，不臆造肯定性 fixture）

D1 §6.2 审批状态机全貌是 **PENDING + 四个互斥终态**（`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md` §6.2）：

```
PENDING → RESOLVED_ALLOW       （respondApproval 到达，outcome=allow_once/allow_always）
PENDING → RESOLVED_DENY        （respondApproval 到达，outcome=deny）
PENDING → TIMED_OUT_DENY       （内核侧 fail-closed 超时信号驱动）
PENDING → FORCE_DENIED_ON_STOP （interrupt/stop 命中该 session/run 时，适配器主动强制终态化）
```

**T-048 REWORK 更新**：`FORCE_DENIED_ON_STOP` 本轮已随 SG-5 `stop()` 的 D1 §6.2 force-deny 补丁
落地（见下方「FORCE_DENIED_ON_STOP」一节，原先记录的一致性缺口已修复），本目录新增
`stop-force-denies-pending-approval.json` 覆盖该终态，两端 runner 均已驱动通过。本目录三条
fixture 的覆盖现状：`pending-request-agent-first.json`/`pending-request-session-first.json` 覆盖
**PENDING**（agent-first / session-first 两种到达顺序），`stop-force-denies-pending-approval.json`
覆盖 **FORCE_DENIED_ON_STOP**。`RESOLVED_ALLOW`/`RESOLVED_DENY`/`TIMED_OUT_DENY` 三个终态在
`app/kernel-client/swift/OpenclawGatewayKernelClient.swift`（SG-5 交付、Stage A 只读复用、未改动）
当前实现下**仍不可达**，逐条诚实登记原因，不写一条注定要么造假要么失败的 fixture：

## RESOLVED_ALLOW / RESOLVED_DENY

依赖调用方真实调用 `respondApproval()`——但该方法在 SG-5 仍是 TODO 桩：

```swift
public func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws {
    throw KernelClientError.notImplemented("respondApproval() 本轮 TODO 桩——L1 闭环没有回调过任何真实审批")
}
```

`client_call` 到 `respondApproval` 会被 swift-runner 的 `degradeReason(for:)` 静态扫描到，整条 fixture
自动标记 DEGRADED（跳过，不计入 PASS/FAIL）——不会为了『让它过』去伪造一个绕开真实方法体的假审批
状态机。

## TIMED_OUT_DENY

依赖内核侧 fail-closed 超时信号被适配器观察并终态化。真实 wire 上，这个信号是
`session.approval(phase:"terminal")`——但 `EventMapping.swift` 的
`mapOpenclawSessionApprovalToKernelEvent` 明确诚实标注：

```swift
guard jsonString(payload["phase"]) == "pending" else {
    // terminal 分支：见上方文档注释，D1 11 变体里没有它的对应位置。
    return nil
}
```

即 `phase:"terminal"`（含超时导致的 deny）**完全没有映射到任何 D2 事件**——不是本轮翻译层的缺口，是
SG-5 EventMapping.swift 自己的、有文档注释的既定范围声明（openclaw 的 terminal reason 词表与 D1
`ApprovalBufferResolvedEvent` 要求的词表完全不相交，见该文件头注释③）。没有任何真实 wire 帧能让当前
SG-5 产出『这个 reqId 已超时终态化』的可观察信号，因此无法构造肯定性 fixture。

## FORCE_DENIED_ON_STOP（本轮已修复并覆盖，历史记录保留）

依赖 `stop()`/`interrupt(mode:'cancel')` 在执行取消前，**先**把该 session/run 的 pending approval
强制终态化为 deny，并在随后的 `TurnCompleteEvent.forceResolvedApprovals` 中列出被强制处理的
`reqId`（D1 §6.2 步骤①，MUST）。

**Stage A 原始核查结论（历史记录，问题已修复，不再是当前事实）**：真实 `stop()`
（`OpenclawGatewayKernelClient.swift`）的实现里，从进入方法体到收尾，曾经**没有任何一行代码读取
或处理 `pendingSessionApprovalByApprovalID`/`agentApprovalInfoByApprovalID`**——完全没有执行
D1 §6.2 要求的"强制 deny pending approval"步骤；两处构造 `TurnCompleteEventMessagePayload` 的
调用点也曾**硬编码 `forceResolvedApprovals: nil`**。这是 Stage A 对抗审（T-048 codex）独立确认过的
一个真实 D1 §6.2 一致性缺口。

**T-048 REWORK 更新（本轮已落地修复）**：SG-5 `stop()` 已补上 D1 §6.2 M3 force-deny 补丁——
`forceDenyPendingApprovalsBeforeStop`（`OpenclawGatewayKernelClient.swift`）在发起 `sessions.abort`
之前，对该 session 名下所有仍处于 pending 的审批逐个调用真实 openclaw 统一审批解决 RPC
`approval.resolve`（复用 `packages/gateway-protocol` 的 `ApprovalResolveParamsSchema`），要求响应体
`approval.status == "denied"` 才继续；返回值（被强制处理的 reqId 列表）由 `stop()` 存进
`PendingStop.forceResolvedApprovalReqIDs`，供 `EventMapping.swift` 的
`mapOpenclawAgentLifecycleToAbortTerminalEvents`/`mapOpenclawAgentLifecycleToTurnComplete` 构造
`TurnCompleteEventMessagePayload` 时填入 `forceResolvedApprovals`（不再硬编码 `nil`）。
`stop-force-denies-pending-approval.json`（本目录新增）是该能力的金标 parity 覆盖：swift-runner
在 `performClientCall` 的 `stop` 分支为 `approval.resolve` 注册了一个默认「内核已确认 denied」的
背景桩（对没有 pending 审批的其余 fixture 是安全 no-op），驱动真实 `stop()`/
`forceDenyPendingApprovalsBeforeStop` 方法体本身走一遍这条分支；断言可观察到 RPC 顺序
`approval.resolve` → `sessions.abort`（见 fixture 跑起来时的 SEND/RECV 日志顺序）与最终
`TurnCompleteEvent.forceResolvedApprovals` 含该 reqId。ts-runner 的 `MockKernelClient` 同样按 D1
§6.2 spec 转发 fixture 声明的 `forceResolvedApprovals`（不是照抄 Swift 行为），两端一致通过。
