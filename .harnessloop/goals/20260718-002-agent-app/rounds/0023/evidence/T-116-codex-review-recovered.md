hopper-dispatch v0.58.0 — dispatching T-116-codex...
  notice: No detailed spec section for T-116-codex in leader-tasklist.md; task content comes from queue.md Brief.
  permission: sandbox=read-only (auto)
  notice: model resolved from AGENTS.md Model rule (task-type 'code-review-adversarial'): verified-latest
  notice: model sentinel 'verified-latest' → gpt-5.6-sol (codex hopper default)
  notice: effort resolved from AGENTS.md Effort policy (task-type 'code-review-adversarial'): xhigh
  note: cache for codex is 24.3d ago; consider `hopper-dispatch --probe codex` to refresh

=== DISPATCH RESULT ===
Task:     T-116-codex (code-review-adversarial)
Vendor:   codex
Status:   success
Duration: 422287ms
Usage:    {"totalTokens":273}

--- OUTPUT ---
**Summary**

完成只读对抗评审，结论为 **REWORK**。steer 的 RPC 选择、`send()` 锁语义和 fixture 扩围均正确，现有证据也达到 169/169 与 13/13；但发现两个生产竞态/状态缺陷，以及一个 runner 假真迹问题。因沙箱只读，未创建 `.hopper/handoffs/T-116-codex-output.md`，完整报告如下。

**Files touched**

none — 全程只读，未创建、修改或删除文件。

**Acceptance verification (7/10)**

1. **PASS — steer RPC 选择成立。** OpenClaw `sessions.send`/`sessions.steer` 共用 handler，后者在 active run 时先执行 `chat.abort`，随后调用 `chat.send`，确属 hard abort+resend；包装层构造的参数没有 `queueMode`/`deliver`。[sessions-messaging.ts:267](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kernels/openclaw/src/gateway/server-methods/sessions-messaging.ts:267)、[sessions-messaging.ts:325](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kernels/openclaw/src/gateway/server-methods/sessions-messaging.ts:325)、[logs-chat.ts:95](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/kernels/openclaw/packages/gateway-protocol/src/schema/logs-chat.ts:95)。直接使用 `chat.send(sessionKey, queueMode:"steer", deliver:false)` 正确。

2. **FAIL — “等待，不抢占”没有原子交接锁。** `interrupt()` 的 defer 先把锁写成 `idle`，再唤醒 stop waiter；stop 醒来后才重新检查并获取锁。[OpenclawGatewayKernelClient.swift:1106](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:1106)、[OpenclawGatewayKernelClient.swift:1374](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:1374)。独立构造的交错为：stop 已等待 → interrupt defer 写 `idle` 并 resume stop → 一个已排队的 send/interrupt actor job 先执行并取得 `idle` → stop 恢复后看到非 idle，抛 `session_locked`。这违反 §9.3 “锁转 `stop_in_progress`、stop 正常执行”；现有测试只有双方竞争，没有第三个 handoff contender。[SteerTests.swift:345](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/frame-replay-tests/SteerTests.swift:345)

3. **PASS — `send()` 未被放松。** 其 guard 仍要求 `currentLock == .idle`，[OpenclawGatewayKernelClient.swift:816](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:816)；记录测试也确认 steer 在途时返回 `session_locked`。[71-v2-FINAL-frame-replay-tests.log:2395](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/71-v2-FINAL-frame-replay-tests.log:2395)

4. **PASS — 金标 fixture 修改未越界。** `git diff --numstat` 为 `4 1`；删除仅为旧 description 行的替换，timeline 只新增 send/expect/response 三个前置步骤。原 `steer1`、`stop1`、两条锁断言和 `expected.pendingOperations` 均未修改。[soft-steer-then-stop.json:9](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/contracts/d2/fixtures/operation-outcome/soft-steer-then-stop.json:9)

5. **FAIL — runner 出站翻译本身不自证，但入站响应仍错误地按 cancel 翻译。** mode-aware stub 能让错误 RPC 得到 `<none>`/notConnected；`queueMode→mode` 也读取真实捕获参数，并先删除潜在原生 `mode`，不会拿 fixture args 自证。[SwiftFixtureRunner.swift:883](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift:883)。但 `applyMockResponse` 对所有 `"interrupt"` 都生成 `sessions.abort` 风格的 `abortedRunId/status:"aborted"`，还设置 stop-terminal 等待状态，[SwiftFixtureRunner.swift:1022](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift:1022)；最终日志因此出现不可能的 “`chat.send` result = abortedRunId”。[60-v2-FINAL-parity-runner-run.log:84](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/60-v2-FINAL-parity-runner-run.log:84)。当前代码因只认 transport success 而通过，但这不是可信的 native-wire 回放。

6. **PASS — steer 严格二态。** 成功只产出 `submitted`；RPC throw 统一镜像为 `rejected`，未引入第三态。[OpenclawGatewayKernelClient.swift:1257](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:1257)

7. **FAIL — active-run 本地快照维护不完整。** 新集合只在本 client 的 `send()` ack 时插入、terminal lifecycle 时删除。[OpenclawGatewayKernelClient.swift:317](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:317)。然而既有 `session.message` 已直接携带权威 `session.activeRunIds`，当前代码读取它却只更新 `lastRunIDBySessionID`，完全不更新新集合。[OpenclawGatewayKernelClient.swift:2917](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/OpenclawGatewayKernelClient.swift:2917)。结果可能对恢复/外部启动且已观察到的 active run 错报 `no_active_run_for_steer`；反向也无法用空快照清除陈旧 active 状态。现有 steer 测试明确只覆盖“先由本 client send”的路径。

8. **PASS — 超时归属正确。** 仲裁超时返回 stop 自己的 `.timedOut` 并保持 interrupt 在途；记录测试为约 1.07 秒后 stop timed_out、steer 随后独立 submitted。[71-v2-FINAL-frame-replay-tests.log:2359](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/71-v2-FINAL-frame-replay-tests.log:2359)

9. **PASS — 机械验证记录完整。** 当前文件 SHA-256 与收尾证据一致；记录构建 `BUILD_EXIT=0`，[70-v2-FINAL-swiftpm-build.log:3](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/70-v2-FINAL-swiftpm-build.log:3)，frame replay `169/169, TEST_EXIT=0`，[71-v2-FINAL-frame-replay-tests.log:2396](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/71-v2-FINAL-frame-replay-tests.log:2396)，fixture runner `13 PASS / 0 FAIL / 0 DEGRADED`。[60-v2-FINAL-parity-runner-run.log:661](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/60-v2-FINAL-parity-runner-run.log:661)

10. **PASS — C# 未动、破坏性反证有留痕。** `git diff --stat -- app/kernel-client/csharp` 为空；四项实现反证和四项 v2 runner/fixture 反证均记录命中数、RED/GREEN 与复原 SHA。[40-counter-proof-summary.md:9](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/40-counter-proof-summary.md:9)、[80-v2-summary.md:85](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/80-v2-summary.md:85)

**Decisions / deviations**

- 五问裁决：① RPC 选择成立；②普通两方场景会等待，但完整 §9.3 仲裁不成立；③ send 未放松；④ fixture 未削弱断言；⑤新增 runner 假真迹路径，且 active-run 快照存在漏同步。
- `sessionKey→sessionId` 已知缺口判定为本轮非阻塞：当前 fixture 不断言 `sessionId`，且 actor 测试直接断言实际 `sessionKey == kernelKey`。[SteerTests.swift:126](/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/app/kernel-client/swift/frame-replay-tests/SteerTests.swift:126)。但未来任何要求 `req.interrupt.sessionId` 的 fixture 都必须补映射。
- 只读约束下未重新运行会更新 `.build`/临时目录的命令；使用了与当前 SHA 一致的冻结日志。
- OpenClaw 被核实的 tracked source 无 diff；子仓仍有未归因的 `?? git-hooks/post-commit`。

**Open questions**

- `kernels/openclaw/git-hooks/post-commit` 的归属无法由当前任务文件确定；若按负范围字面验收，需要单独清理或确认其为既有环境文件。

**Verdict**

**REWORK**

**Next recommendation**

实现 interrupt→stop 的原子锁转移，避免中间暴露 `idle`；用完整 `session.activeRunIds` 快照同步 active 集合，包括空集合清除；并让 runner 的 `applyMockResponse(interrupt)` 按真实捕获方法区分 `sessions.abort` 与 `chat.send`。随后新增“handoff 时第三个 send/interrupt 竞争”、恢复会话 active 快照、空快照清理及真实 chat.send ack 四类测试，再复跑 169/169、13/13 与破坏性反证。
--- END OUTPUT ---
