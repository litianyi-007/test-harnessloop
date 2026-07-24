---
phase: done
last_progress_at: "2026-07-24T18:04:46.273Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T18:04:46.271Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 332717
adapter_status: success
---
# T-051 确认性再审（SG-8.7 Stage A rework 第2轮，单 grok 异构视角）

## Summary

对主仓库 commit `98d38e0e`（收 codex T-050 MUST-FIX 五处的第 2 轮 rework）做了只读确认性再审。基线运行达到声明值：TS fixture runner **13/13 PASS**，Swift fixture runner **12 PASS / 0 FAIL / 1 DEGRADED**（`soft-steer-then-stop` 诚实 DEGRADED）；Ajv 对 13 条默认 fixture 展开后的 **34/34** message 通过 `message.schema.json#/$defs/Message`。T-050 五处均亲手做了“有牙齿”证伪：临时破坏真实 client / mock / expected / expand 后目标 fixture 真 FAIL，并全部 `git checkout`/备份还原。未发现新的“绿灯靠不校验蒙混”表面绕过；`includeApprovals` 等原生字段未跨端断言属诚实 defer，不是假闭合。

## Files touched

- `.hopper/handoffs/T-051-output.md`：按任务要求写入本只读再审报告；评审对象与产品源码均未保留改动（证伪用临时破坏已全部还原）。

## Acceptance verification (2/2 checked; 5/5 T-050 closures closed with teeth)

### 基线运行

```text
$ find app/contracts/d2/fixtures -name '*.json' | sort | xargs node app/contracts/d2/fixtures/ts-runner/runner.ts
13 PASS / 0 FAIL  （=== ALL PASS）

$ swiftc ... -o /tmp/t051-swift-fixture-runner && /tmp/t051-swift-fixture-runner
=== 12 PASS / 0 FAIL / 1 DEGRADED （共 13 条 fixture） ===
# DEGRADED = operation-outcome/soft-steer-then-stop.json（interrupt 仍为 SG-5 notImplemented 桩）
```

独立 Ajv（复用 `ts-runner/runner.ts` 导出的 `expandResponseShorthand` / `expandEventShorthand`，schema `$id/$ref` 规范到 `https://d2.local/` 后编译 `message.schema.json#/$defs/Message`）：

```text
expanded_messages=34  schema_valid=34  schema_invalid=0
event_messages=6  events_with_seq=6
stop_rejected_failure_code=malformed_message
```

### 1. T-050 五处是否真闭合且有牙齿

#### #1 `expect_outbound`：从真实捕获 native params 规范化匹配 — **闭合，有牙齿**

- **静态证据**：`SwiftFixtureRunner.swift` 中 `capturedOutbound` 只存 `(method, params)`（stub 闭包同步收到的真实入参）；`checkExpectOutbound` 调用 `normalizeNativeParams(method:params:...)` 从 `capturedParams` 现算规范化请求，不再把 timeline `args` 塞回 payload。`sessionId` 经 `kernelKeyToDeclaredSessionID` 从真实 `params.key` 反查，查不到显式 `NSNull()`、不 fallback。见 `SwiftFixtureRunner.swift` 约 L220–L225、L249–L250、L589–L658。
- **证伪 A（send.message）**：临时改 `OpenclawGatewayKernelClient.send()` 把 `params.message` 写成 `"T051_WRONG_MESSAGE"`，重编译后跑 `stop-force-denies-pending-approval.json`：

  ```text
  [FAIL] stop-force-denies-pending-approval
         - expect_outbound(send1).payload.text: 期望 run with a pending approval，实际 T051_WRONG_MESSAGE
  ```

  还原后该 fixture 恢复 PASS。
- **证伪 B（abort.key）**：临时改 `sessions.abort` 的 `params.key` 为 `"T051_WRONG_KEY"`：

  ```text
  [FAIL] stop-force-denies-pending-approval
         - expect_outbound(stop1).sessionId: 期望 session-1，实际 nil
  ```

  （错误 key 反查不到声明 session → `sessionId=NSNull()` → pattern 失败。）还原后干净。

#### #2 TS force-deny spec oracle — **闭合，有牙齿**

- **静态证据**：`mock-kernel-client.ts` 的 `call('stop')` 遍历本地 `approvalState`，对 `pending` 推进 `force_denied_on_stop`、push `nativeCallOrder`、写入 `forceResolvedApprovalsByCallId`；`applyEvent(evt.turn_complete)` 用自算列表覆盖/删除 `forceResolvedApprovals`，不读 fixture mock_event 声明值当输入（约 L161–L182、L324–L349）。
- **证伪 A**：只改 `expected.observedEvents[..].forceResolvedApprovals` 为 `["req-WRONG-SHOULD-FAIL"]`：

  ```text
  [FAIL] ... forceResolvedApprovals[0]: 期望 "req-WRONG-SHOULD-FAIL"，实际 "req-force-deny-1"
  ```

  证明实际值来自自算 `req-force-deny-1`，不是 expected 回显。
- **证伪 B**：临时禁止 `forceDenied.push(reqId)`（仍改 approvalState / nativeCallOrder）：

  ```text
  [FAIL] ... forceResolvedApprovals: 期望数组，实际 undefined
  ```

  证明 `turn_complete` 不再透传 fixture 声明的列表。两处均已还原，fixture PASS。

#### #3 fixture 断言 RPC 顺序（`nativeCallOrder`）— **闭合，有牙齿**

- **静态证据**：Swift 在 `approval.resolve` / `sessions.abort` stub **被真实 client 调用的那一刻** `appendNativeCall`（非注册时）；TS 在 `call('stop')` 代码顺序里先 resolve 后 abort。fixture `approval/stop-force-denies-pending-approval.json:32,40` 断言 `["approval.resolve","sessions.abort"]`。
- **证伪 A（TS expected 反序）**：

  ```text
  [FAIL] assert_state@t=36.nativeCallOrder[0]: 期望 "sessions.abort"，实际 "approval.resolve"
  ```

- **证伪 B（TS mock 交换 push 顺序）**：同样 FAIL，实际顺序变为 abort→resolve。
- **证伪 C（真实 Swift `stop()` 交换两次 `request` 顺序）**：abort 先于 force-deny；日志可见 `sessions.abort` 先于 `approval.resolve`，fixture FAIL：

  ```text
  [FAIL] assert_state@t=36.nativeCallOrder: 期望长度 2，实际长度 1
         expected.nativeCallOrder[0]: 期望 approval.resolve，实际 sessions.abort
         expected.nativeCallOrder[1]: 期望 sessions.abort，实际 approval.resolve
  ```

  （中间态 length=1 是因为 abort 阻塞在 gate 上时 force-deny 尚未执行；最终 expected 仍捕获反序。牙齿成立。）client 已还原。

#### #4 无非法 D2 message — **闭合**

- `stop-rejected-rpc-failure.json:11` 现为 `"code":"malformed_message"`，属于 `ProtocolFailure` 合法枚举（`errors.schema.json:61-64`），不再是非法 `unknown`。
- Ajv：`expanded_messages=34 schema_valid=34 schema_invalid=0`。
- `rg '"_openclaw'` 对 fixture JSON message 键的历史私货问题不在本轮 T-050 五处残留列表内（上轮已清）；本轮未再引入非法字段。

#### #5 `expandEventShorthand` 补 `seq` — **闭合，有牙齿**

- **静态证据**：`runner.ts:104-112` 按 `sessionId` 分桶递增 `seq`，每条 fixture 独立 `seqBySession` Map（约 L132）。
- **证伪**：临时去掉返回值中的 `seq` 后 Ajv：

  ```text
  expanded_messages=34  schema_valid=28  schema_invalid=6
  event_messages=6  events_with_seq=0
  ```

  恰 6 条 `mock_event` 展开失败。还原后 34/34、6/6 带 seq。

### 2. 有无新的表面绕过

| 检查项 | 结论 |
| --- | --- |
| `includeApprovals` 等 native 字段是否被断言 | **诚实未跨端断言，合理 defer，非遗漏型假闭合**。真实 Swift subscribe 发 `includeApprovals:true`（日志可见）；`normalizeNativeParams` 会把它留在 payload 里，但 fixture 均未在 `expect_outbound` 里断言该字段。TS mock 的 `req.subscribe.payload` 仍是 `{}`。若强行跨端断言会立刻打穿 TS/Swift 语义差——Stage A 选择不断言，与 D2 `req.subscribe` 空 payload 模型一致，OPEN/README 对“翻译边界 / 不可翻译点”保持诚实，不是“声称覆盖却不校验”。 |
| 两端 `partialMatch` 语义 | 当前 JSON 值域等价：子集深度匹配、数组等长、显式 null ≠ 字段缺失；Swift 侧 `PartialMatch.swift` 对 Bool/NSNumber/`objCType` 与 Int64 精度的 T-048 修复仍在。两端对同一批 `expected` 字段一致 PASS（12 条可驱动 fixture）。 |
| DEGRADED / OPEN.md | `soft-steer-then-stop` 仍因 `interrupt` 桩诚实 DEGRADED；`session-lock/OPEN.md`、`approval/OPEN.md` 对 respondApproval 终端态、interrupt_in_progress、approval timeout 等不可达场景仍登记，无过度 defer 到“已覆盖却 DEGRADED 掩盖”。force-deny 段已更新为“已修复并断言顺序+自算”。 |
| TS force-deny 是否“假 outbound” | TS 不把 `approval.resolve` 记入 `outbound` Map，只记 `nativeCallOrder` + 状态机 + `forceResolvedApprovals`。fixture 也不对 resolve 做 `expect_outbound`——断言的是顺序与终态字段，与 mock 能力匹配。Swift 侧真实走过 resolve RPC stub。两端独立 oracle 在**被断言的维度**上有牙齿，不构成新的“回显 expected”病。 |
| 其它 pattern 覆盖面 | 多条 fixture 的 createSession 仍只断言 `type`；subscribe 多数无 `expect_outbound`（basic 有 `sessionId`）。这是 pattern 覆盖范围选择，不是“matcher 丢弃字段”类假阴性——凡 pattern 声明的字段，Swift 已从真实 params 匹配（#1 已证伪）。 |

**结论**：未发现与 T-050 同类的新表面绕过（匹配自构 request / 回显 expected / 顺序只可观察不断言 / 漏 required 字段靠 mock 不校验蒙混）。

## Decisions / deviations

- 任务专用 verdict 词表使用 `CONFIRMABLE` / `MUST-FIX`，不使用通用 frame 的 `PASS`/`REWORK`。
- Ajv 加载：仓库自带 `validate-schemas.mjs` 只编译 schema 图、不校验展开 message；本轮用临时脚本把相对 `$id/$ref` 规范为 `https://d2.local/...` 后校验 34 条展开 message（脚本仅在 `/tmp`，未写入仓库）。
- #1 证伪选用 `send.message` 与 `sessions.abort.key`（T-050 点名的字段）；subscribe.key 未再重复动手（机制与 abort.key 同为 key→sessionId 反查，#1b 已覆盖该路径）。
- 所有证伪临时改动均已还原：`OpenclawGatewayKernelClient.swift`、`mock-kernel-client.ts`、`runner.ts`、fixture JSON 与备份 diff 干净；`git status` 对评审对象无残留。

## Open questions

none

## Verdict

**CONFIRMABLE**

（五处真闭合且有牙齿 + 基线 13/13 与 12/1 DEGRADED + Ajv 34/34 + 无新表面绕过 → Stage A 可终收。）

## Next recommendation

进入 **Stage B（C# runner）**。Stage A 金标与 Swift/TS 双端 runner 可作为 C# 对照基线；实现时注意：

1. C# 的 `expect_outbound` 必须同样从**真实捕获的 native params**规范化，禁止 timeline args 回填。
2. force-deny 路径必须独立计算 `forceResolvedApprovals` 并机器断言 `nativeCallOrder = [approval.resolve, sessions.abort]`。
3. event shorthand 必须补 `seq`；CI 建议把“展开后 Ajv 34/34”收成固定命令，避免再次靠 mock 不读 envelope 蒙混。
4. `includeApprovals` 等 openclaw 原生特有字段继续作为翻译边界文档化；若 Stage B 要跨端断言，需先统一三端 D2 可见模型，而不是在某一端偷偷透传。
5. 仍诚实 DEGRADED 的 interrupt / respondApproval 桩能力属 SG-5 产品缺口，不阻塞 Stage A 收口，可另开产品任务。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll execute T-051 as a read-only acceptance review: load the T-050 findings and commit `98d38e0e`, then falsify each of the five closures and scan for new green-light bypasses.Next I'll inspect the rework code paths for all five T-050 findings and run the baseline fixture suite.I'll run the baseline suite next, then falsify each T-050 claim with temporary breaks that get reverted.Compiling the Swift runner and running Ajv validation, then performing hands-on falsification for each finding.Ajv loader needs the project's schema setup; next I'll use the existing validator and run the Swift suite plus falsification tests.Baseline is green (TS 13/13, Swift 12/1 DEGRADED). Next I'll hands-on falsify each of the five T-050 closures and fix Ajv loading.#2 and #3 pass on the TS side. Next: fix Ajv validation and falsify #1/#3 on the real Swift client.#1 and Ajv 34/34 confirmed. Continuing falsification for Swift RPC order, abort key, and `seq`.Writing the T-051 acceptance report to disk.# T-051 完成\n\n只读确认性再审已落盘：`.hopper/handoffs/T-051-output.md`\n\n## Verdict: **CONFIRMABLE**\n\n### 基线\n| 检查 | 结果 |\n|---|---|\n| TS runner | **13/13 PASS** |\n| Swift runner | **12 PASS / 0 FAIL / 1 DEGRADED**（soft-steer 诚实降级） |\n| Ajv expanded Message | **34/34 valid**（含 6 条 event 均带 `seq`） |\n\n### T-050 五处（均亲手证伪，临时改动已还原）\n1. **#1 expect_outbound**：真 client 发错 `send.message` / `abort.key` → fixture **FAIL**\n2. **#2 TS force-deny oracle**：改 expected 或禁 stash → **FAIL**（自算，非回显）\n3. **#3 nativeCallOrder**：反序 expected / mock / 真 `stop()` → **FAIL**\n4. **#4 D2 canonical**：`malformed_message` 合法；Ajv 34/34\n5. **#5 seq**：去掉 `seq` → 恰 6 条 event schema 失败；补回 34/34\n\n### 新表面绕过\n未发现。`includeApprovals` 未跨端断言属诚实 defer（TS mock payload `{}` vs Swift 真发 flag），不是“声称覆盖却不校验”。\n\n### Next\nStage A 可终收 → **进 Stage B（C# runner）**，并沿用上述有牙齿的断言纪律。",
  "stopReason": "EndTurn",
  "sessionId": "019f9548-1135-7611-83f8-b6d4303b2880",
  "requestId": "e265dde9-fb2e-4a31-b6bc-1cee04e6ba3d",
  "thought": "The user wants me to perform a code-review-acceptance task (T-051) as an execution agent. I need to:\nGood, I have the T-050 findings and the commit. Now I need to carefully review the key files and run falsification tests. Let me read the relevant source files.I have a good picture of the code changes. Now I need to:\nTS suite passes 13/13. Now I need to:Now I'll:\n1. Compile and run Swift runnerThe Ajv script failed because of schema loading issues. Let me check how the project's existing validate-schemas.mjs works, and also look for any existing Ajv validation script that was used in the re...Baseline:\n- TS: 13/13 PASS**Summary**  \nI performed a full read-only code review of the fixtures in `app/contracts/d2/fixtures/` against the five MUST-FIX items from T-050. I executed the prescribed falsification tests for each criterion, using temporary modifications that were immediately reverted with `git checkout`.#2 and #3 falsifications work on TS side. Now I need to:\nThe Ajv relative ref issue - schemas have $id like `methods/create-session.schema.json` and refs like `../common/envelope.schema.json#/$defs/sentAt`. When Ajv resolves relative refs from baseId `metho...**Summary**  \nI performed a full read-only review of the SG-8.7 Stage A rework fixtures under `app/contracts/d2/fixtures/` against the five T-050 MUST-FIX items plus new surface-bypass checks. All five original criteria were re-verified with targeted proof-of-failure tests ( 1-3 temporary edits reverted via `git checkout` ). Additional Ajv validation for criterion #4 was executed using a custom loadSchema resolver that correctly resolves relative refs from `methods/*.schema.json` base URIs, confirming 34/34 Message schemas validate cleanly and `stop-rejected` malformed_message is accepted.Excellent! #1 falsification works, Ajv 34/34. Now:Interesting observation on #3 Swift falsification:**Summary**  \nI performed a read-only verification of the T-050 five findings on the SG-8.7 Stage A fixtures under commit 98d38e0e. For each criterion I either confirmed the fix is closed and has teeth or produced a reproducible counter-example that would cause the fixture to fail. I also scanned for new surface bypasses and ran the full test harness (13/13 TS + 12/13 Swift).  All five original findings hold; no new bypasses were found.  Verdict: CONFIRMABLE.I have enough evidence to write the report. Let me also note about includeApprovals:\n**Summary**  \nI performed a read-only code review of the fixtures in `app/contracts/d2/fixtures/` against the five MUST-FIX items from T-050. I verified each criterion by attempting reproducible proof-of-failure tests (temporary edits followed by `git checkout`), ran the harness commands to confirm 13 13 TS and 12 13 Swift parity, and examined cross-end consistency for fields like `includeApprovals`. All five criteria are closed with independent teeth; no new surface bypasses were found that would allow green lights for unasserted claims.HEAD is at 98d38e0e. Clean. Write the report now.Report written. Mark todo complete. The task is done.I've completed the T-051 acceptance review. Provide a concise summary for the dispatcher/user.",
  "usage": {
    "input_tokens": 107261,
    "cache_read_input_tokens": 1045376,
    "output_tokens": 19240,
    "reasoning_tokens": 7329,
    "total_tokens": 1171877
  },
  "num_turns": 15,
  "total_cost_usd": 0.6435748,
  "total_cost_usd_ticks": 6435748000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 107261,
      "outputTokens": 19240,
      "cacheReadInputTokens": 1045376,
      "modelCalls": 15,
      "costUSD": 0.6435748
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 332717
- end_time: 2026-07-24T18:04:46.271Z
- log: see `T-051-output.log` for raw output
