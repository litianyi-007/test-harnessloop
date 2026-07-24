---
phase: done
last_progress_at: "2026-07-24T12:31:07.463Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T12:31:07.460Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 456225
adapter_status: success
---
# T-048 对抗审查

## Summary

已完成五项独立对抗核验：Swift runner 的 `client_call` 确实进入 SG-5 真实 actor 方法，事件也确实经过 `handleIncoming`/`EventMapping`，`advance_clock` 当前用例确实靠 SG-5 内部真实 timer 产生 `timed_out`；D1 §6.2 的 pending approval force-deny 缺口也确认属实。与此同时发现四类必须返工的问题：新增 fixture 不是合法、可跨端共用的 D2 shorthand，权威 TS runner 对同一 12 条仅 2 PASS/10 FAIL；Swift `partialMatch` 与 TS 不等价；`expect_outbound` 丢弃 pattern 中除 `type` 外的全部断言；唯一 DEGRADED fixture 还掩盖了缺少 session 初始化这一独立错误。

当前 Swift 实跑为 11 PASS/0 FAIL/1 DEGRADED、exit 0，单跑 `stop-timed-out` 为 2.06s，但“Swift 自己能绿”不足以证明三端金标 parity。另，“swiftc 编译干净”不准确：当前 Apple Swift 6.3.3 默认模式编译成功但有 warning，`SwiftFixtureRunner.swift:86/88` 的 async context 中 `NSLock.lock/unlock` 已提示在 Swift 6 language mode 会成为 error。

## Files touched

- `.hopper/handoffs/T-048-output.md`：按任务要求落盘本只读评审报告；未修改任何评审对象或产品源码。

## Acceptance verification (5/5)

说明：这里的 5/5 表示五项均已核验，不表示五项均通过。

1. **真实 SG-5 client 驱动：部分通过，存在覆盖放水。**
   - `app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift:343-431` 的 `createSession`/`send`/`subscribe`/`stop` 分支直接调用 `OpenclawGatewayKernelClient` 的公开 actor 方法；对应真实实现位于 `app/kernel-client/swift/OpenclawGatewayKernelClient.swift:223-326,345-380,408-530`。
   - `ReplyGate`（runner `:62-98`）让真实 `request()` 悬挂；测试 responder 只在 RPC/transport 边界接管返回值（client `:702-721`），没有绕过 `send()`/`stop()` 的锁、pending-stop、timer 或 catch 分支。
   - `mock_event` 经 `testSupportFeedFrame`（client `:1166-1171`）进入真实 `handleIncoming`（`:806-850`）及 mapper；`observedEvents` 来自真实 `EventMessageUnion` 编码。没有发现把预置 D2 结果直接塞入事件流的短路。
   - 但 `expect_outbound` 只读取 `pattern.type` 并比对底层 RPC 方法名（runner `:470-490`），完全不检查其余 pattern/params；权威 TS runner 会对完整 pattern 做 `partialMatch`（`ts-runner/runner.ts:111-119`）。例如既有 basic fixture 的 `sessionId` 断言（`basic/create-session-subscribe-message-delta.json:47-50`）在 Swift 端被静默忽略，真实 client 即使发错 key/message/includeApprovals 等参数也可能 PASS。结论：是真 client，不是假 client；但 outbound parity 覆盖明显不足。

2. **`advance_clock`/`timed_out`：真实触发，通过但确定性声明过强。**
   - runner 在创建 client 后调用 `testSupportSetStopTimeoutSeconds(1)`（runner `:759-763`）；SG-5 在 `stop()` 内将 override 送入 `waitForPendingStopTerminal`（client `:443-475`），其 timer 真实执行 `Task.sleep` 后调用 `resolvePendingStopWaiter(... .timedOut)`（client `:578-600`）。
   - runner 的 `advance_clock` 没有直接改 client state/outcome；它仅在声明的 `ms >= 1000` 时真实 sleep 1.4s（runner `:649-666`）。独立复现：`/usr/bin/time -p /tmp/t048-swift-fixture-runner app/contracts/d2/fixtures/operation-outcome/stop-timed-out.json` 输出 `1 PASS / 0 FAIL`、`real 2.06`。
   - 备注：这不是真正虚拟时钟，也非严格确定性。timer 是否已开始只靠 mock-response 后 50ms 调度窗口，随后仅留 400ms slack；另有 50/80/150/250ms 固定 sleep（runner `:232-234,442-445,678-687,773-774`）。负载足够高时内部 timer 晚于 runner sleep 启动超过 400ms，紧随其后的断言仍可能抢跑。应增加“waiter 已安装/任务已结算”的显式同步钩子，而不是以固定 sleep 猜调度。

3. **覆盖缺口与 DEGRADED 诚实性：SG-5 阻塞事实成立，但 DEGRADED 还掩盖独立 fixture 错误。**
   - `interrupt()`、`respondApproval()`、`capabilities()` 确为 `throw .notImplemented`（client `:379-380,629-634`）；真实锁枚举也确实只有 `idle/sendPending/stopInProgress`，没有 `interruptInProgress`（client `:55-67`）。因此 `submitted`、`aborted_no_resend`、`aborted_resend_failed`、`interrupt_in_progress`、approval allow/deny 终态当前确被 SG-5 卡住，不是作者“嫌难不写”。
   - `session.approval(phase:"terminal")` 被 SG-5 明确跳过（client `:1070-1073`；mapper `EventMapping.swift:521-535`），所以 `TIMED_OUT_DENY` 当前也无可观察落点。`approval/OPEN.md` 对这些事实的登记基本准确。
   - `degradeReason` 确实报告 DEGRADED 而非 PASS（runner `:704-745`），当前原因“interrupt TODO”属实；但它在执行任何 timeline 前整条返回，掩盖了 `soft-steer-then-stop.json:5-7` 从未 `createSession` 就调用 `interrupt`/`stop` 的独立错误。真实 runner 对 `stop` 明确要求已有 `currentSessionHandle`（runner `:411-414`），故 `session-lock/OPEN.md:55-58` 所称“interrupt 落地后 fixture 无需修改即可通过”不成立。该 DEGRADED 不是假 PASS，但也不能视为只有 SG-5 TODO 一个阻塞。

4. **D1 §6.2 force-deny 缺口：确认是真实 conformance 缺口。**
   - 权威 D1 `d1-kernelport-spec-v3.md:515` 明确要求：pending approval 先推进 `FORCE_DENIED_ON_STOP`、向内核 deny 并确认生效，之后才可 abort；同一 reqId 必须进入 `TurnCompleteEvent.forceResolvedApprovals`。`:523-526` 还要求 stop 黑名单命中时批量 deny；`:622` 再次要求 turn-complete 携带该列表后才能 session-end。
   - SG-5 `stop()` 在 `OpenclawGatewayKernelClient.swift:408-530` 设置锁和 pending-stop 后直接于 `:427` 发 `sessions.abort`；无 pending approval 查询、无 deny RPC、无 deny 确认屏障。`rg -n 'pendingSessionApproval|agentApprovalInfo|approval.resolve|forceResolvedApprovals'` 显示 approval cache 仅用于 join/清理，stop 路径没有消费它们。
   - 两个 turn-complete mapper在 `EventMapping.swift:409,459` 均硬编码 `forceResolvedApprovals: nil`。因此主会话/Sonnet 没有误读：这是 SG-5 实质未实现项，且 `stop()` 被标为完整实现却无对应 TODO，SG-5 “done”确被高估。

5. **fixture 语义与 `partialMatch`：不通过。**
   - **非法/臆造字段。** 7 条新增 fixture 把 `_openclawAbortAck`、`_openclawLifecycle`、`_openclawJoinOrder` 塞进 `WireResponseShorthand`/`WireEventShorthand` 的 `message`（可用 `rg -n '_openclawAbortAck|_openclawLifecycle|_openclawJoinOrder' app/contracts/d2/fixtures/{approval,operation-outcome,session-lock}` 复现）。但 `dsl.ts:50-60` 声明 shorthand 直接来自封闭 D2 unions；stop/approval/turn-complete schema 均 `additionalProperties:false`。这些字段不是 D2/D1 字段，而是未进入 DSL 类型的 Swift 私货。
   - **不可能的 stop response。** `operation-outcome/stop-transport-closed-aborted-effect-unknown.json:12` 写了 `res.stop.result.outcome:"aborted_effect_unknown"`，而 D2 stop schema `methods/stop.schema.json:8-16` 只允许 `succeeded|timed_out|rejected`。transport close 场景本来不应伪造一条成功 D2 stop response；Swift 实际从 transport-close 的 `operation_completed` 得到该七态，TS mock 却从这条非法 response 直接赋值，两端因果语义不同。
   - **approval shorthand 缺必填字段。** 两条 approval fixture 的 `message.payload`（各自 `:16-22`）缺 D2 必填的内部不透明 `payload`；`events/approval-request.schema.json:22` 明确将其列入 required，且 fixture 顶层还携带非法 `_openclawJoinOrder`（各自 `:23`）。
   - **权威 TS runner 不兼容。** 复现命令：
     `fixture_args=($(find app/contracts/d2/fixtures/{basic,operation-outcome,session-lock,approval} -maxdepth 1 -name '*.json' | sort)); node app/contracts/d2/fixtures/ts-runner/runner.ts "${fixture_args[@]}"`
     返回 exit 1，仅 basic、soft-steer 两条 PASS，其余新增 10 条全部 FAIL。故 README 所称“语言中立、同一批 fixture”在当前交付中不成立，不能直接进入 C# Stage B。
   - **Swift matcher 不等价。** TS `partialMatch` 仅对 `undefined` 视为不断言，显式 `null` 必须与 actual 严格相等（`ts-runner/runner.ts:37-41`）；Swift 却把 `JSONNull`/`NSNull` 一律当作通过（`PartialMatch.swift:16-20,45-47`）。此外 Swift `numericValue` 接受 `NSNumber`（`:23-28`），而 Foundation 的 Bool 也桥接为 NSNumber；按原函数复现得到 `true_vs_1=true false_vs_0=true`，TS 严格比较均为 false。大整数经 Double 比较还会丢失精度。该 matcher 会把真实 mismatch 放过，并非仅注释差异。

## Decisions / deviations

- 判定 **REWORK** 的依据不是已诚实登记的 SG-5 TODO 本身，而是 Stage A 新交付的 fixture/runner 违反自身“语言中立金标”与 TS parity 语义，并存在可复现的假阴性匹配。
- 按任务允许范围额外执行了 Swift 编译与两端 runner；只生成 `/tmp` 可执行物/临时输出，未改评审对象。
- `approval/OPEN.md` 对 D1 §6.2 缺口的结论予以确认；该缺口应另立 SG-5 conformance 修复，不应靠 runner 翻译层伪造。

## Open questions

none

## Verdict

REWORK

## Next recommendation

先不要进入 C# runner。先完成以下收残并用同一条命令回归：

1. 保持 `mock_response.message`/`mock_event.message` 为合法 D2 shorthand；把 native transport 控制建模成 DSL 中显式、强类型的 driver-control（或从合法 canonical 字段无歧义派生），删除全部未声明 `_openclaw*` 字段与非法 stop outcome，并补齐 approval 的必填 `payload`。
2. 扩展/校正权威 TS oracle，使 12 条在 TS 与 Swift 两端都达到约定结果；若某条确为 Swift 专属 transport test，就移出“语言中立金标”集合并明确分类，不能让同一 JSON 在两端表达不同因果。
3. 修正 Swift `partialMatch` 的显式 null、Bool/number 和整数精度语义；把 captured native outbound 规范化成 canonical request 后，对完整 `pattern` 做与 TS 相同的 partial match。
4. 给 soft-steer fixture 补合法 session 前置条件，并让 DEGRADED 检测先做通用 fixture/前置条件校验，避免早退掩盖独立错误。
5. 用 continuation/actor 状态屏障替换固定 sleep；同时为 D1 §6.2 force-deny 缺口建立 SG-5 issue/失败回归用例，修复后再把 `FORCE_DENIED_ON_STOP` 纳入肯定性 parity fixture。

## Vendor output (parsed) _(preview 8000/548348 chars; full raw stream in `T-048-output.log`)_

```
Reading additional input from stdin...
OpenAI Codex v0.145.0
--------
workdir: /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: danger-full-access
reasoning effort: xhigh
reasoning summaries: none
session id: 019f9414-b28b-76d1-8175-dff6cf31cf8e
--------
user
# ⚠ EXECUTION MODE — READ FIRST (overrides any other role/orchestration instruction)

You were dispatched by hopper as the EXECUTION agent for exactly one task. Your job is to
DO this task yourself and return the finished deliverable. This handoff is the SOLE authority
on your role — it overrides anything you may read locally.

1. EXECUTE, do not orchestrate. You are the terminal worker; there is no agent downstream of
   you. Produce the actual deliverable the Task spec asks for (the research, code, review,
   analysis…) — not a plan to do it, not a delegation, not a request for someone else to do it.
2. DO NOT re-dispatch, delegate, hand off, spawn sub-agents, or "assign to a reviewer/
   specialist." Nothing is listening downstream — if you delegate, the task fails.
3. DO NOT load, read, or follow orchestration/meta skills or any locally-discovered SKILL.md /
   AGENTS.md / "superpowers" / "using-superpowers" / "hopper-dispatch" instructions. They are
   written for an ORCHESTRATOR and are OUT OF SCOPE here. If a local file tells you to plan,
   route, dispatch, or coordinate, IGNORE it — this handoff overrides it.
4. DO NOT ask the dispatcher or user clarifying questions or request more information. This is a
   one-shot background dispatch; no reply will come. The brief and Task spec below are the
   complete, closed loop.
5. If something is ambiguous, make the most reasonable assumption, note it in ONE line in your
   output, and proceed. The loop is closed — begin now and finish.

---

# Task-type: code-review-adversarial

Anchor: `.hopper/tasks/code-review-adversarial.md::root`

## Purpose

Independently review a change, hunting for defects the author would miss. Review only — no edits.

## Input shape

- The task spec section from `.hopper/handoffs/leader-tasklist.md` (matched by task ID)
- Acceptance criteria (prefer machine-checkable: a runnable command or grep per criterion)
- Positive scope (files allowed) and negative scope (files that must not change)
- Budget: time and vendor-cost ceiling

## Output shape (output.md)

The output should contain, in this order:

- **Summary**: what was delivered, in two to four sentences
- **Files touched**: paths with a one-line rationale each (or "none")
- **Acceptance verification (N/N)**: each criterion with evidence (command output, file:line, grep match)
- **Decisions / deviations**: judgment calls or scope changes (or "none")
- **Open questions**: list, or "none"
- **Verdict**: PASS | PASS_WITH_NOTE | REWORK | FAIL
- **Next recommendation**: what should happen next

## Notes

This frame describes the SHAPE of the work and the expected output, not an
identity to adopt. The vendor CLI brings its own behavior; the frame only states
what the protocol expects back.

---

## Task spec

## T-048（SG-8.7 ★审查闸1：Swift 金标 parity runner + fixture 三组扩全 对抗审，单 codex）

**Task-type**: `code-review-adversarial` · **Vendor**: codex（随机池异构；T-046 codex 曾被自身安全过滤器中止，本轮重新引入验证）· 只读

**评审对象**（主仓库工作区未提交改动，`git status` 见 `app/contracts/d2/fixtures/`）：
- 新建 `app/contracts/d2/fixtures/swift-runner/`（`FixtureDSL.swift` / `PartialMatch.swift` / `SwiftFixtureRunner.swift` / `SwiftRunnerMain.swift`）
- 新增/扩 fixture：`operation-outcome/*.json`（5 新）、`session-lock/*.json`（3 新）、`approval/*.json`（2 新）+ `{approval,session-lock}/OPEN.md` + `README.md`
- **权威对照**：DSL 规格 `app/contracts/d2/fixtures/dsl.ts` + TS 金标 `ts-runner/runner.ts`/`mock-kernel-client.ts`；被驱动的 SG-5 真实客户端 `app/kernel-client/swift/`（只读复用，本轮未改，已 T-044/045 validated）；D1 契约 `~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md`。

**背景**：SG-8.7 = 把 SG-5 ad-hoc FrameReplayTests 证过的跨端一致，正式化为三端金标 parity runner。Stage A 建 Swift runner + fixture 从 2 扩到 12。**主会话已独立复验**：swiftc 编译干净、11 PASS/0 FAIL/1 DEGRADED、exit 0、总耗时 ~7.6s（stop-timed-out ~1.9s）。由 Sonnet 所写，需异构对抗复核。

**对抗核验重点（找真缺陷 + 可复现）**：
1. **runner 是否真驱动 SG-5 真实客户端，还是伪装的 mock（最重）**：核实 `SwiftFixtureRunner.swift` 的 `client_call` 是否真调 `OpenclawGatewayKernelClient` actor 的真实方法、`mock_response`/`mock_event` 是否经 `testSupportStubRPC`/`testSupportFeedFrame` 喂给真实 client 的 `request()`/`handleIncoming`/`EventMapping` 代码路径产出可观察态——**有没有任何一处 short-circuit 成预置常量/绕过真实 client 逻辑**？`ReplyGate` 让 RPC 真在途、中途 `assert_state` 观察的是不是真 actor 态？
2. **advance_clock 是否真触发 timed_out，还是伪造状态**：核实它是否经 SG-5 的 `testSupportSetStopTimeoutSeconds` 把 5s 缩到 1s、再 `Task.sleep` 真跨阈值触发 SG-5 内部 timer + `resolvePendingStopWaiter(outcome:.timedOut)`——而非直接把 state 设成 timed_out。`stop-timed-out.json` 真耗时是不是佐证（~1.9s）？确定性来源是否是固定常量（非测量/探测）？
3. **覆盖缺口是否真被 SG-5 卡住，还是避重就轻**：`OPEN.md` 声称 3 个 OperationOutcome 态（submitted/aborted_no_resend/aborted_resend_failed）需 `interrupt()`、`interrupt_in_progress` 锁态在真实 client 枚举里不存在、approval 四终态本轮不可驱动——**逐条对 `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` 源码核实这些确因 SG-5 的 TODO 桩/枚举缺失/stop 缺口真卡住**，而非 Sonnet 不愿写。DEGRADED 的 soft-steer（用 interrupt）自动跳过是否诚实（非掩盖 FAIL）？
4. **独立复核 flagged 的 stop() D1 §6.2 缺口**：主会话已核实 D1 §6.2（该 doc line 515 M3 定序规则）要求 `stop()` 在 abort 前若有 pending approval 须先 force-deny 推进 `FORCE_DENIED_ON_STOP` + 列入 `TurnCompleteEvent.forceResolvedApprovals`，而 `EventMapping.swift:409/459` 两处硬编 `forceResolvedApprovals: nil` 且 stop() 无此步、无 TODO 声明。**请独立确认这是不是真实 D1 conformance 缺口**（读 D1 §6.2 + stop() 实现 + EventMapping），还是主会话/Sonnet 误读。这决定 SG-5「done」是否被高估。
5. **fixture 语义正确性**：12 条 fixture 的 timeline op 是否表达合法 D2/D1 语义（wire 形状、OperationOutcome/SessionLockState/approval 态值），有无臆造字段？`PartialMatch.swift` 子集深度匹配语义是否与 ts-runner 的 `partialMatch` 一致（非放水成永真）？

**Verdict**：`PASS`（Stage A 可接受、进 Stage B C# runner）| `PASS_WITH_NOTE` | `REWORK`（逐条给 `app/contracts/d2/fixtures/<file>:<line>` + 可复现）| `FAIL`。
**产出**：五项逐条 + verdict + 对 #4 的独立结论（缺口真伪）。落盘 `.hopper/handoffs/T-048-output.md`。**Read-only**：不改任何文件；可选跑 `swiftc`/runner 复核但非必需（读代码+推理即可，避免触发沙箱安全过滤器）；忽略跨仓/别目录全局 skill。中文。

codex
我会按五个对抗核验点逐项做只读审查：先锁定未提交变更与权威实现，再核对 runner 的真实调用链、超时路径、覆盖缺口、D1 §6.2 及 12 条 fixture 语义。最终只写指定的 `.hopper/handoffs/T-048-output.md`，不改评审对象。
exec
/bin/zsh -lc "git status --short && rg --files app/contracts/d2/fixtures app/kernel-client/swift | sort && rg -n \"§6\\.2|M3|forceResolvedApprovals|FORCE_DENIED_ON_STOP|force-deny|stop\\(\\)|pending approval\" /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md | head -80" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 285ms:
 M .harnessloop/state/current.md
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 M app/contracts/d2/fixtures/README.md
 ? kernels/openclaw
?? .harnessloop/goals/20260718-002-agent-app/rounds/0006/
?? .hopper/handoffs/T-048-output.log
?? .hopper/handoffs/T-048-output.md
?? .hopper/handoffs/T-048-progress.log
?? app/contracts/d2/fixtures/approval/
?? app/contracts/d2/fixtures/operation-outcome/stop-active-run-succeeded.json
?? app/contracts/d2/fixtures/operation-outcome/stop-no-active-run-succeeded.json
?? app/contracts/d2/fixtures/operation-outcome/stop-rejected-rpc-failure.json
?? app/contracts/d2/fixtures/operation-outcome/stop-timed-out.json
?? app/contracts/d2/fixtures/operation-outcome/stop-transport-closed-aborted-effect-unknown.json
?? app/contracts/d2/fixtures/session-lock/
?? app/contracts/d2/fixtures/swift-runner/
app/contracts/d2/fixtures/README.md
app/contracts/d2/fixtures/approval/OPEN.md
app/contracts/d2/fixtures/approval/pending-request-agent-first.json
app/contracts/d2/fixtures/approval/pending-request-session-first.json
app/contracts/d2/fixtures/basic/create-session-subscribe-message-delta.json
app/contracts/d2/fixtures/dsl.ts
app/contracts/d2/fixtures/operation-outcome/soft-steer-then-stop.json
app/contracts/d2/fixtures/operation-outcome/stop-active-run-succeeded.json
app/contracts/d2/fixtures/operation-ou

... [truncated, 540348 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 456225
- end_time: 2026-07-24T12:31:07.460Z
- log: see `T-048-output.log` for raw output
