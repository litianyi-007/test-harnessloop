---
phase: done
last_progress_at: "2026-07-24T17:20:28.246Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T17:20:28.245Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 410302
adapter_status: success
---
# T-050 确认性再审

## Summary

已对 commit `1c320553` 逐条复核 T-048 的 finding，并独立运行 TS/Swift 两端 runner。运行表面结果达到声明值：TS `13/13 PASS`，Swift `12 PASS / 0 FAIL / 1 DEGRADED`，当前 Swift 日志也确实显示 `approval.resolve` 先于 `sessions.abort`。但仍有 4 个可复现的实质缺陷：一条 fixture 仍不是 canonical D2、TS event shorthand 未补必填 `seq`、Swift `expect_outbound` 的非 `type` 字段仍未取自真实 outbound、TS force-deny oracle 与顺序断言为空转，因此 Stage A 尚不可确认。

## Files touched

- `.hopper/handoffs/T-050-output.md`：按任务要求写入本只读再审报告；未修改任何评审对象或产品源码。

## Acceptance verification (0/2 passed; 2/2 checked)

1. **T-048 四类缺陷：部分闭合，未达到“真闭合”。**

   - **#5 私有字段与 D2 形状：旧的三类私货已清除，但仍残留 1 条非法 D2 message。**  
     `rg -n '"_openclaw' app/contracts/d2/fixtures` 无输出（`exact_json_key_matches=0`）；`driverHint` 位于 `TimelineOp` 的 `message` 兄弟字段（`app/contracts/d2/fixtures/dsl.ts:88-115`），没有换名后继续塞进封闭 D2 union。`abortedRunId/status` 从已有 active `runId` 派生（`swift-runner/SwiftFixtureRunner.swift:613-629`），非法 stop outcome 已改成 `succeeded`（`operation-outcome/stop-transport-closed-aborted-effect-unknown.json:12`），两条 approval fixture 也已补必填内部 `payload`（`approval/pending-request-agent-first.json:16-23`、`approval/pending-request-session-first.json:16-23`）。
     
     但 `app/contracts/d2/fixtures/operation-outcome/stop-rejected-rpc-failure.json:11` 仍写入 `res.stop.failure.code:"unknown"`。`StopResponseMessage.failure` 只能是 `RejectionFailure | ProtocolFailure`（`app/contracts/d2/schema/methods/stop.schema.json:48-64`），两者枚举分别见 `app/contracts/d2/schema/common/errors.schema.json:20-32,57-68`，均不包含 `unknown`。复现：

     ```text
     $ jq -r '.timeline[] | select(.op=="mock_response" and .message.type=="res.stop") | .message.failure.code // empty' \
         app/contracts/d2/fixtures/operation-outcome/stop-rejected-rpc-failure.json
     unknown
     ```

     独立 Ajv 复校（先按 DSL 手工补齐 shorthand 的 `sentAt/direction/id/seq/ts`，再校验 `message.schema.json#/$defs/Message`）输出：`expanded_messages=34 schema_valid=33 schema_invalid=1`，唯一失败即该行。因此“全部 message canonical D2”不成立；这里要表达 transport/RPC 抛错，应使用 D2 union 外的强类型 driver control，而不是伪造一条非法 D2 response。

   - **#1 `expect_outbound`：matcher 修了，但真实 outbound 字段覆盖仍是表面绕过。**  
     `checkExpectOutbound` 现在确实对完整 `pattern` 调用 `partialMatch`（`app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift:536-566`），`PartialMatch.swift:113-163` 也修正了显式 null、Bool/number 与整数精度三类 T-048 差异；代码语义与 TS `partialMatch`（`ts-runner/runner.ts:40-68`）对当前 JSON 值域等价。
     
     但被匹配的 `normalizedRequest` 不是从捕获到的真实 native `params` 规范化而来，而是直接把 timeline 的 `argsAny` 原样放回 `payload`，`sessionId` 也直接取 fixture response 声明值（`SwiftFixtureRunner.swift:403-405,425-428,454-456,476-479`）。真实 `params` 虽存入 tuple（`:203-206,224-225`），后续只有 method 与手工构造的 normalized request accessor（`:228-234`），没有任何代码读取 `params` 做字段映射。故真实 client 即使把 `sessions.send.params.message`、`sessions.messages.subscribe.params.key/includeApprovals` 或 `sessions.abort.params.key` 发错，完整 pattern 仍可 PASS；这正是 T-048 #1 要关闭的假阴性，不是“调用了 partialMatch”就已闭合。

   - **#2 `advance_clock`：闭合。**  
     `applyAdvanceClock` 已轮询 `ctx.isCallSettled(id:)`，直到 stop wrapper 真正写定 `pendingOperations/callOutcomes`（`SwiftFixtureRunner.swift:248-256,744-790`），不再以固定 sleep 作为“已结算”判据。独立单跑 `stop-timed-out.json` 为 `1 PASS`、`real 1.60`，真实超时仍由 SG-5 的 `Task.sleep -> resolvePendingStopWaiter(.timedOut)` 触发。

   - **#3 DEGRADED 与 Swift 6 锁：闭合。**  
     `soft-steer-then-stop.json:5-8` 已补 `createSession`/`subscribe` 前置条件，`session-lock/OPEN.md:55-66` 已更正旧声称。当前 `interrupt()`、`respondApproval()`、`capabilities()` 仍分别是 `notImplemented` 桩（`app/kernel-client/swift/OpenclawGatewayKernelClient.swift:420-422,804-810`），锁枚举仍无 `interrupt_in_progress`（`:50-67`），approval terminal wire 仍无 D2 可映射落点（`app/kernel-client/swift/EventMapping.swift:520-535`），OPEN.md 的 defer 属实且没有过度 defer。`ReplyGate` 已由 `NSLock` 改为 actor（`swift-runner/SwiftFixtureRunner.swift:81-119`）；编译不再出现 T-048 指出的 `NSLock.lock/unlock` async warning。

   - **TS mock 的一般 stop/lock/outcome 扩展大体按 D1/D2 因果实现，但新增 force-deny 分支并未实现成独立 spec oracle。**  
     `MockKernelClient` 只在收到 `evt.approval_request` 时把状态记为 `pending`（`app/contracts/d2/fixtures/ts-runner/mock-kernel-client.ts:64-67,267-269`）；`stop()` 不执行 pending → `FORCE_DENIED_ON_STOP`、不产生 deny outbound、也不计算 `forceResolvedApprovals`。后者只是把 fixture 自己提供的 `evt.turn_complete.payload.forceResolvedApprovals` 原样转发（`:271-283`）。所以该新增关键场景不是“从 D1/D2 spec 写出的内核期望”，而是把 expected 事实作为输入再回显，TS parity 在此空转。

2. **跨端 parity 与新缺陷：运行数值通过，但关键 parity 断言不成立。**

   - 任务指定命令实跑成功：

     ```text
     $ find app/contracts/d2/fixtures -name '*.json' | sort | \
         xargs node app/contracts/d2/fixtures/ts-runner/runner.ts
     13 PASS / 0 FAIL

     $ swiftc ... -o /tmp/t050-swift-fixture-runner && /tmp/t050-swift-fixture-runner
     === 12 PASS / 0 FAIL / 1 DEGRADED （共 13 条 fixture） ===
     ```

     两端都对同一份 `expected` 做逐字段 partial match，12 条 Swift 可驱动 fixture 均 PASS；唯一 DEGRADED 是已登记的 soft-steer。

   - 当前实现的 force-deny 路径确实被 Swift runner 驱动：单跑输出顺序为

     ```text
     42:--- SEND req approval.resolve
     60:--- SEND req sessions.abort
     86:[PASS] stop-force-denies-pending-approval
     ```

     最终 `TurnCompleteEvent.forceResolvedApprovals` 也由真实 mapper 产出并命中 fixture `expected`（`app/contracts/d2/fixtures/approval/stop-force-denies-pending-approval.json:39-43`）。

   - **但 gold fixture 没有断言 RPC 顺序。**  
     Swift runner 对 `approval.resolve` 只注册一个立即成功的背景 stub（`app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift:482-491`），既不记录它，也不把 native RPC 序列暴露给 `expect_outbound`；fixture 在 stop 段只断言 `req.stop`（`approval/stop-force-denies-pending-approval.json:30-33`）。若实现回归成 `sessions.abort` → `approval.resolve`，abort gate 在 `mock_response` 后释放，后续流程仍可能得到同样 events 并 PASS。结合上项 TS 仅回显 fixture 的 `forceResolvedApprovals`，这条关键 parity 用例目前只能证明“当前日志顺序正确”，不能作为防回归的金标断言。

   - **TS event shorthand 展开还有一个新的 canonical-wire 缺陷。**  
     DSL/README 要求 runner 自动补 `seq`，所有 EventMessage schema 都把 `seq` 列为 required；但 `expandEventShorthand` 只补 `ts/sentAt/direction`，漏掉 `seq`（`app/contracts/d2/fixtures/ts-runner/runner.ts:83-94`）。本轮 13 条含 6 个 `mock_event`；之所以仍 13 PASS，是因为 TS mock 完全不校验/消费该 envelope 字段。这再次说明当前绿灯不能证明 D2 wire parity。

## Decisions / deviations

- 按任务专用 verdict 词表使用 `MUST-FIX`，不使用通用 frame 的 `REWORK`。
- `rg '_openclaw'` 会命中文档中的历史说明；判定“删净 JSON message”采用精确 key 搜索和结构化 JSON 遍历，结果均为 0。
- Swift 编译仍有 4 条“no async operations occur within await”warning，其中 1 条在 runner、3 条在已修复 SG-5；它们不是 T-048 的 `NSLock` 问题，也不影响本次 verdict。
- 除 `/tmp/t050-swift-fixture-runner` 与审查输出外未写入任何文件；commit `1c320553` 的 22 个变更文件均位于允许的 `app/contracts/d2/fixtures/` 范围。

## Open questions

none

## Verdict

MUST-FIX

## Next recommendation

暂不进入 Stage B C# runner。先完成四项最小收残：把 transport/RPC 抛错建模为 D2 `message` union 外的强类型 driver op；让 TS event expansion 真正补 `seq` 并把 34 条 expanded message 的 Ajv 校验纳入常规命令；让 Swift `expect_outbound` 从捕获的 native `params` 做规范化并覆盖 `key/message/includeApprovals`；让两端 force-deny oracle 独立计算终态并把 `approval.resolve(deny, reqId)` → `sessions.abort` 顺序作为机器断言。随后重跑 schema 校验、TS 13/13、Swift 12 PASS/1 DEGRADED，再做一次 confirming review。

## Vendor output (parsed) _(preview 8000/582261 chars; full raw stream in `T-050-output.log`)_

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
session id: 019f951e-4ea0-79a1-8264-fb82c3c06fc0
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

# Task-type: code-review-acceptance

Anchor: `.hopper/tasks/code-review-acceptance.md::root`

## Purpose

Verify a change against its stated acceptance criteria. Review only — no edits.

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

## T-050（SG-8.7 Stage A rework 确认性再审，单 codex，接续 T-048）

**Task-type**: `code-review-acceptance` · **Vendor**: codex（接续自己 T-048 REWORK，复核收残是否真闭合；同 T-044→T-045 confirming 模式）· 只读 · **三项强制核对**

**评审对象**（主仓库 commit `1c320553`，收 T-048 REWORK 的 Stage A rework，只读）：`app/contracts/d2/fixtures/`（`swift-runner/`、`ts-runner/{runner,mock-kernel-client}.ts`、`dsl.ts`、各 fixture JSON 含新增 `approval/stop-force-denies-pending-approval.json`、`{approval,session-lock}/OPEN.md`、`README.md`）。对照你自己 T-048 的 5 项 finding（`.hopper/handoffs/T-048-output.md`）。`git show 1c320553`。**注**：SG-5 `stop()` 的 force-deny 缺口已另在 commit `ed90f138` 修复（D1 §6.2 + NOTE-A drain-loop，grok T-049 PASS_WITH_NOTE），本轮 runner 驱动的是已修复的 stop()。

**只验两件事**：
1. **T-048 的 REWORK 四类缺陷是否真闭合**（逐条对你原 finding 核实修法正确、非表面绕过）：
   - **#5 臆造非 D2 字段**：`_openclawAbortAck`/`_openclawLifecycle`/`_openclawJoinOrder` 是否真从所有 fixture 的 JSON message 里删净（`rg '"_openclaw'`）？替代方案是否合法——`abortedRunId`/`status` 改从 canonical 派生、approval join-order 改用 DSL 层 `driverHint` 兄弟字段（`dsl.ts` `MockEventDriverHint`）是否**真在封闭 D2 `message` 联合之外**（不是换个名字继续塞私货）？非法 stop outcome（`aborted_effect_unknown`）与 approval 缺 payload 是否修？全部 message 是否 canonical D2（可对 `schema/` 判别联合复校）？
   - **#1 expect_outbound 放水**：是否改为对完整 pattern 做 partialMatch（不再只比 `type`）？Swift `PartialMatch.swift` 与 TS `partialMatch` 是否**真等价**？
   - **#2 advance_clock 脆弱**：是否改为轮询"任务已结算"同步钩子（非固定 sleep 猜调度）？
   - **#3 DEGRADED 掩盖**：soft-steer 是否补了 createSession、OPEN.md 错误声称是否更正？
   - **TS mock 扩展**：`mock-kernel-client.ts` 从 2→13 覆盖，是否**从 D1/D2 spec 写内核期望行为**，还是照抄 Swift client 实际行为（后者=parity 空转）？Swift6 NSLock→actor 是否修？
2. **跨端 parity 是否真成立 + 有无新缺陷**：独立跑 `find app/contracts/d2/fixtures -name '*.json' | sort | xargs node app/contracts/d2/fixtures/ts-runner/runner.ts`（应 13/13）+ 编译跑 swift-runner（应 12 PASS/1 DEGRADED）；两端对同一批可驱动 fixture 的 `expected` 是否逐字段一致？新增 `stop-force-denies-pending-approval` fixture 是否真驱动 SG-5 force-deny（RPC 顺序 approval.resolve→sessions.abort + forceResolvedApprovals）？OPEN.md 标注的"卡住态"（respondApproval/interrupt/capabilities 桩、interrupt_in_progress 枚举缺失）是否属实、无过度 defer？

**Verdict**：`CONFIRMABLE`（四类缺陷真闭合 + parity 真成立 + 无新缺陷 → Stage A 可接受、进 Stage B C# runner）| `MUST-FIX`（仅列问题点 + `app/contracts/d2/fixtures/<file>:<line>` + 可复现）。
**产出**：两项逐条 + verdict。落盘 `.hopper/handoffs/T-050-output.md`。**Read-only**：不改任何文件；可跑 node/swiftc 复核（勿跑 csi 等触发安全过滤器的 C# 交互）；忽略跨仓/别目录全局 skill。中文。

codex
我会按 T-050 的三项强制核对做只读确认性再审：先还原 T-048 findings 与 `1c320553` 变更，再分别跑 TS/Swift runner，并逐项核对 canonical D2、partialMatch、时钟同步、DEGRADED 与 force-deny 证据；仅写入要求的审查产物 `.hopper/handoffs/T-050-output.md`。
  → 读取 T-048 结论、目标 commit 与 D2 schema/spec，建立逐项核对表
  • 静态审查 runner、mock、DSL、fixtures 与 OPEN.md，核验四类缺陷和新扩展
  • 独立运行 TS 与 Swift runner，并比较跨端 expected/parity 和 force-deny 顺序
  • 检查范围与新缺陷，写入 T-050 中文审查报告
exec
/bin/zsh -lc "pwd && git status --short && git rev-parse --show-toplevel && sed -n '1,260p' .hopper/handoffs/T-048-output.md && git show --stat --oneline --decorate --no-renames 1c320553 && git show --format=fuller --no-ext-diff --no-renames --name-status 1c320553" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 477ms:
 M .harnessloop/state/current.md
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 ? kernels/openclaw
?? .harnessloop/goals/20260718-002-agent-app/rounds/0006/
?? .hopper/handoffs/T-048-output-raw.txt
?? .hopper/handoffs/T-048-output.log
?? .hopper/handoffs/T-048-output.md
?? .hopper/handoffs/T-048-progress.log
?? .hopper/handoffs/T-049-output.log
?? .hopper/handoffs/T-049-output.md
?? .hopper/handoffs/T-049-progress.log
?? .hopper/handoffs/T-050-output.log
?? .hopper/handoffs/T-050-output.md
?? .hopper/handoffs/T-050-progress.log
/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
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

1. **真实 SG-5

... [truncated, 574261 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 410302
- end_time: 2026-07-24T17:20:28.245Z
- log: see `T-050-output.log` for raw output
