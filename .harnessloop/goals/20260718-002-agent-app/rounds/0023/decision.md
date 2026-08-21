# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .harnessloop/goals/20260718-002-agent-app/rounds/0023/evidence/T-116-codex-review-recovered.md
- Reviewer: codex via hopper T-116（单路，按 scope-lock；沙箱只读未落指定路径，正文从 `.hopper/handoffs/T-116-codex-progress.log` 回收）
- Review verdict: **REWORK**（三条 FAIL，主会话独立复核全部成立后返工；用户 2026-08-21 授权本轮收盘，先例 rounds/0020）
- Review digest: ccd726f54368988ba2b58b78eabb9141e55c578447318a6bbcbc06e65df81a65
- Acceptance evals: none — 本轮为 kernel-client 锁仲裁与 steer 实现，无 runtime eval 台账
- Mechanical gate: 0 / coverage: rounds=30 rule_a_files=268 rule_b_files=3 citations=12 citations_exempt_external=0 citations_suffix_hinted=0 citations_ignored_explicit=14 citations_shape_dropped=1 review_files_with_ignore=3 decision_field_label_not_ascii=0 zero_inspected=11 scope_lock_round_path_mismatch=6 review_declared=25 review_none=4 review_missing_fields=0 review_digest_declared=25 goals_eval_registry_present=1 rounds_eval_ledger_present=6 rounds_eval_ledger_without_decision=0 eval_entries_checked=6 eval_entries_with_evidence=6 eval_entries_evidence_null=0 evals_with_system=1 evals_system_undeclared=0 eval_declaration_ran=6 eval_declaration_none=9 eval_declaration_absent=14 predecessor_declared=0 stop_recorded=0 stop_unjustified=0 mechanical_gate_declared=1 mechanical_gate_nonzero=0 loop_autocontinue_anomaly=0 loop_anomaly_skipped_unparsable=3 external_roots_declared=0 external_roots_available=0 external_citations_checked=0 external_citations_resolved=0 external_citations_not_found=0 external_citations_rejected=0 external_citations_unverifiable=0 external_systems_declared=5 / 2026-08-21 after writing this field; Predecessor omitted — declaring it activates loop-contract-profile-missing because control-contract.md has no Profile: field (contract revision needs user)
- Active goal: 20260718-002-agent-app
- Active round: 0023
- Decision maker: main session（grok-4.6）；用户 2026-08-21 明确接受本次模型不符并授权 0023 收盘（environment.md 期望仍是 claude-opus-5[1m]，未改期望值）
- Timestamp: 2026-08-21

## Reason

**把 `interrupt` 补齐到 confirmed D1 规定的样子**：实现 `mode:"steer"`，
并把 `stop()` 遇 `interrupt_in_progress` 的仲裁从「非 idle 一律拒绝」改成规格
§9.3 要求的「**等待，不抢占**」——两种模式都改。

这是 rounds/0022 把那条从未执行过的金标 fixture 跑起来并 FAIL 之后的直接下一轮。
读 `d1-kernelport-spec-v3-6.md`（`design_status: confirmed`）原文后确认：
**fixture 是对的，实现有两条偏离**——只做 `cancel`；锁矩阵与「等待，不抢占」相反。
第 2 条尤其要小心：0022 的 FAIL 近因是 steer 在拿锁之前就被 mode guard 拒了，
**光实现 steer 不会自动暴露它**，必须专门构造真正进入 `interrupt_in_progress` 的用例。

## 最重要的源码事实：`sessions.steer` 是假同源词

openclaw `sessions.send` / `sessions.steer` 共用 handler，后者只多一个
`interruptIfActive`——为 true 时先 `chat.abort` 再 `chat.send`，语义是 D1 的
`abort_and_resend`，不是软 steer。`queueMode` / `deliver` 在该文件 0 命中，
软注入无法经 `sessions.*` 传下去。名字最像的 RPC 恰恰是错的选项。

实现选了规格原文写的 `chat.send` + `queueMode:"steer"` + `deliver:false`。
T-116 独立读源码核实这条判断成立。

## 评审判 REWORK 三条，全部返工

| # | 发现 | 性质 |
|---|---|---|
| **2** | 「等待，不抢占」没有原子交接：interrupt 的 defer 先把锁写成 `idle`，再唤醒 stop waiter；stop 醒来后才重新抢锁。中间窗口里另一个 `send()`/`interrupt()` 可以插队 | 生产竞态 |
| **7** | `activeRunIDsBySessionID` 只在本 client 自己的 `send()` ack 时插入；`session.message` 已携带权威 `session.activeRunIds` 却只更新了 `lastRunIDBySessionID` | 生产状态缺陷 |
| **5** | runner 出站翻译不自证（担心的没发生），但 `applyMockResponse` 对所有 interrupt 仍按 cancel 合成 `abortedRunId`——日志里出现不可能的 `chat.send result = abortedRunId` | 测试基础设施 |

六条 PASS：steer 的 RPC 选择、`send()` 未被放松、金标 fixture 修改未越界
（独立复核 diff 4 增 1 删，删的是 description 正文）、steer 严格二态、超时归属正确、
机械验证记录完整。

第 2 条是「测试全绿、时序日志也好看，但仍然错」的那一类：`chat.send → sessions.abort`
的顺序是对的，断言也测不出——现有测试只有双方竞争，没有第三个 handoff contender。
只有盯着锁的状态迁移才能发现。这正是对抗评审该干的活。

## 返工怎么闭合（主会话独立复核）

1. **原子交接**：`notifyInterruptLockReleaseWaiters`（写 `.idle` 再 resume）换成
   `performAtomicInterruptLockHandoff`——无 `await` 的同步段内：有 waiter 则直接写
   `.stopInProgress` 并唤醒唯一赢家（`.acquired`），其余标 `.lockClaimedByAnotherWaiter`。
   锁在有 waiter 登记期间从不可观察为 `idle`。`stop()` 在 `.acquired` 上不再重新抢锁。
   测试钩子 `testSupportSetInterruptPreHandoffBlockingDelay` 是 `private var`、默认 nil，
   生产代码 0 命中（与 rounds/0019 那个把真 token 打进正式包的钩子不同类）。
   反证红：第三方 `send()` 偷走锁，stop 被拒，message 读 `lock state is send_pending`。
2. **快照全量对账**：`session.activeRunIds` 出现即整集替换（含空集清除）；裸 agent
   事件携带 `runId` 也标记 active。第四条路径**无法闭合**：`sessions.messages.subscribe`
   的响应不含 active run 信息（`sessions-subscriptions.ts:125-137`），唯一 per-session
   信号 `sessions.list` 是本适配器从未用过的批量查询。**没有为了闭合而发明一次新 RPC**，
   该情形保持保守 `no_active_run_for_steer`。已登记为已知缺口。
3. **入站按 mode 分叉**：steer 合成 `chat.send` 形状（`runId`/`status`），不再给
   `chat.send` 配 `abortedRunId`。搜了第四层：该文件只剩已知三处 mode 敏感分支。

返工后帧回放 **169 → 174**（+5：FAIL2 ×1 + FAIL7 ×4）。

## 独立复核（本 Grok 会话 2026-08-21 复跑，不沿用冻结日志）

源文件 SHA 与返工收尾一致：
`OpenclawGatewayKernelClient.swift` `f72a9036c22d…684e7d`，
`SwiftFixtureRunner.swift` `fb3a77e6fdcb…54029e`。

| 判据 | 结果 | 证据 |
|---|---|---|
| `swift build --package-path app` | exit 0 | `evidence/99-resume-swiftpm-build.log` |
| 帧回放 | **174/174 PASS**，exit 0 | `evidence/99-resume-frame-replay-tests.log` |
| Swift 金标 parity | **13 PASS / 0 FAIL / 0 DEGRADED**，exit 0 | `evidence/99-resume-parity-runner.log` |
| C# 端 | `git diff --stat -- app/kernel-client/csharp` 为空 | 本会话 |
| fixture JSON | `git diff --numstat` = 4 增 1 删（删 description） | 本会话 |
| send() 遇 interrupt_in_progress | 仍 reject | T-116 PASS-3；返工未改这条 guard |

## Scope-lock 三次修订

- v1→v2：用户裁定扩围，补 fixture 缺的前置 `send()` + runner outbound 表按 mode 分叉。
  **不是让测试迁就实现**——`no_active_run_for_steer` 是 v3.2 才新增的，fixture 转录自更早的 D4 v2.2。
- v2→v3：实施方指出 v2 文本只授权了 outbound 方法表，而 FAIL-5 修的是同一文件的入站翻译。
  **这是补记，不是事前授权。** 即时指令与范围契约不一致时，该被修的是文档。

## Open Questions Remaining

1. **会话恢复路径没有 active-run 信号** —— 刚恢复、自恢复后零事件、恢复前已有 active run
   的会话，合法 steer 会被误拒。不发明新 RPC；待后续轮。
2. **`chat.send` 的 `sessionKey` → `sessionId` 派生未做** —— 本 fixture 不断言 `sessionId`，
   不阻塞；未来断言该字段的 fixture 必须补映射。
3. **`respondApproval` 零 parity 覆盖** —— rounds/0022 登记，未补。
4. **C# 端三个方法仍是桩** —— 本轮刻意不实现（红线：不为了数字好看掩盖分歧）。
5. **CI 仍不跑 174 条帧回放、仍按「12 PASS + 1 DEGRADED」描述 Swift parity** ——
   0023 scope-lock 禁止改 `.github/`，下一轮做。
6. **返工后的最终形态未再经独立 hopper 评审** —— 与 rounds/0020 同形；用户 2026-08-21
   授权收盘。T-116 三条 FAIL 的反证红绿均留在 `evidence/94`–`97`。

## Next Action

- Action type: next-subgoal
- Scope-lock required: yes
- Human confirmation required: no
- Safe without user input: yes
- Recovery round objective: n/a
- Disallowed until confirmed: n/a

下一轮：把 `frame-replay-tests`（174/174）和 Swift 金标 13/13 接进 CI。
hopper 的 1424 条是否同轮挂上，开轮时再定——它要 checkout submodule，比 Swift 那两步重。
