# session-lock/ 未覆盖场景（SG-8.7 Stage A 诚实登记）

D1 v3.1 §9.3（`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-1.md`）定义的
`SessionLockState` 是四态：

```ts
type SessionLockState =
  | 'idle'
  | 'send_pending'          // send() 已发起，等待 kernel ack
  | 'interrupt_in_progress' // interrupt() 的适配器内部多步序列执行中
  | 'stop_in_progress';     // stop() 的适配器内部多步序列执行中
```

本目录的三条 fixture（`send-in-flight-send-pending.json`、
`send-in-flight-rejects-concurrent-stop.json`、`stop-no-active-run-idle-transitions.json`）覆盖了
`idle` / `send_pending`（进入 + 转移 + 退出）/ `stop_in_progress`（进入 + 转移 + 退出）三态。

## interrupt_in_progress——本轮不可达，诚实降级

`app/kernel-client/swift/OpenclawGatewayKernelClient.swift` 的锁状态机本身**只声明了三态**：

```swift
private enum SessionLockState: Equatable, CustomStringConvertible {
    case idle
    case sendPending
    case stopInProgress
    // 没有 interruptInProgress——见下方文档注释
}
```

文件内的头注释明确交代了这是有意的范围收窄，不是遗漏：

> interrupt() 本轮仍是 TODO 桩，因此完整互斥矩阵里涉及 interrupt_in_progress 的分支（stop 优先仲裁
> 等）本轮不适用——这里只需要覆盖 send()/stop() 两两互斥：任一方法执行时若锁不是 idle，一律
> reject(session_locked)，不做特殊仲裁。

`interrupt()` 方法体本身也确认了这一点（`KernelClient.swift`/`OpenclawGatewayKernelClient.swift`）：

```swift
public func interrupt(session: SessionHandle, options: InterruptRequestMessagePayload) async throws -> InterruptResultPayload {
    throw KernelClientError.notImplemented("interrupt() 本轮 TODO 桩——L1 闭环没有 active run 需要 interrupt")
}
```

调用即抛错，没有任何锁状态转移、没有任何 RPC 发出——`interrupt_in_progress` 这个态在当前 SG-5
实现下**根本无法被进入**，不是"能进入但难以在测试里精确断言"的工程难度问题，是这条状态转移本身尚未
实现。

已有的 `operation-outcome/soft-steer-then-stop.json`（逐字转录自 D4 v2.2 §4.3 既定金标示例，正是
`interrupt_in_progress → stop_in_progress`"等待，不抢占"这条转移的代表性场景）会被 swift-runner 的
`degradeReason(for:)` 静态扫描到（timeline 里有 `client_call: interrupt`），整条 fixture 自动标记
DEGRADED（跳过，不计入 PASS/FAIL）——`ts-runner/` 仍可正常对它驱动 `MockKernelClient` 通过，两个
runner 对同一份 fixture 的覆盖能力本来就不对称，如实记录，不强求同步。

**T-048 REWORK 更正（codex 复现的独立缺陷，收 T-048 REWORK #6）**：本节此前声称"届时
`soft-steer-then-stop.json` 应该可以不经修改直接被 swift-runner 真实驱动通过"——**这个声称原先
不成立**：当时的 timeline 从未 `createSession` 就直接调用 `interrupt`/`stop`，而真实 `stop()`
（swift-runner `performClientCall` 的 `stop` 分支）明确要求已有 `currentSessionHandle`
（`guard let handle = await ctx.currentSessionHandle else { throw ... }`），即使 `interrupt()`
真的落地，这条 fixture 仍会在 `stop` 分支直接抛错、无法通过——这是一个被 DEGRADED 状态掩盖、从未
真正暴露的独立错误（DEGRADED 让 timeline 在执行任何 op 之前就整条短路返回，所以这个缺陷此前从未
被任何 runner 真正跑到）。**本轮已在 fixture 里补上 `createSession`/`subscribe` 前置步骤**（timeline
的 t 值相应整体后移），让上面这句声称重新成立：留给后续实现 `interrupt()` 的 SG 轮次一并补齐
`interrupt_in_progress` 态与 D1 v3.1 §9.3 规则 2/3 的完整仲裁逻辑（stop 优先仲裁、interrupt 到达
时锁为 stop_in_progress 一律 reject(`session_already_stopped`)），届时 `soft-steer-then-stop.json`
应该可以不经进一步修改直接被 swift-runner 真实驱动通过（现在已经具备正确的会话前置条件）。
