---
phase: done
last_progress_at: "2026-07-24T19:18:50.497Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-24T19:18:50.496Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 522292
adapter_status: success
---
## Summary

已完成对 commit `505202a5` 的 Stage B C# parity runner 对抗审：三端基线结果与 README 声明一致，C# 确实驱动 SG-5 真实 client，调用顺序、超时结算和当前 fixture 值域上的 `PartialMatch` 也基本可信。发现 1 个必须修复的假绿：真实 C# client 若把 OpenClaw native `message` 字段错写成 D2 层的 `text`，`stop-active-run-succeeded.json` 仍然 PASS；根因是 `NormalizeNativeParams` 会原样保留预存的 `text`，没有强制证明该值来自真实捕获的 `message`。因此“三端当前样本跑绿”成立，但“C# 绿灯能捕获 send native param 形状回归”的核心声明尚不成立。

## Files touched

- `.hopper/handoffs/T-052-output.md`：本次只读审查产物。
- 评审对象源码：none。所有证伪临时改动均已还原；`app/kernel-client/csharp/OpenclawGatewayKernelClient.cs` 最终 blob 为原始 `3992e0f13a79b3309a9c8dfc640d042ed5cd65e5`，`git diff --exit-code --` 返回 0。

## Acceptance verification (5/5)

1. **真驱动 vs mock：通过。**
   - `app/contracts/d2/fixtures/csharp-runner/CSharpFixtureRunner.cs:471-480`、`:501-510`、`:533-549`、`:558-589` 分别给真实 RPC 注册测试 responder，随后调用真实 `CreateSessionAsync`、`SendAsync`、`Subscribe`、`StopAsync`；生产 `RequestAsync` 在 `app/kernel-client/csharp/OpenclawGatewayKernelClient.cs:955-963` 才把真实方法发出的参数交给 responder，不存在 runner 直接伪造 call outcome 的 short-circuit。
   - `ReplyGate`（`CSharpFixtureRunner.cs:69-126`）在同一把锁内处理 resolve-before-wait 和 wait-before-resolve，TCS 使用 `RunContinuationsAsynchronously`；中途状态来自真实方法在 RPC await 前设置的 lock。现有每个 gate 只有一个 waiter，未发现当前 13 条 fixture 可触发的竞态假绿。

2. **native params 捕获：未通过，发现 MUST-FIX 假绿。**
   - 正向证据：捕获发生于真实 stub 闭包（`CSharpFixtureRunner.cs:471-475`、`:501-505`、`:558-566`）；错误 key 反证有效——临时把真实 `sessions.abort.params.key` 改为 `"T052-wrong-key"` 后，命令
     `dotnet build --nologo && dotnet run --no-build -- ../operation-outcome/stop-no-active-run-succeeded.json`
     退出 1，并报 `expect_outbound(stop1).sessionId: 期望 "session-1"，实际 null`，证明 key 反查无 fallback。
   - 阻断反证：临时把真实 client 的 `SendAsync` 从 `["message"] = ResolveSendMessageText(input)` 改为错误 native 形状 `["text"] = ResolveSendMessageText(input)`，再运行
     `dotnet build --nologo && dotnet run --no-build -- ../operation-outcome/stop-active-run-succeeded.json`。
     日志明确打印 `sessions.send.params` 为 `{"key":"openclaw-key-session-1","text":"run something long","timeoutMs":0}`，但结果仍是 `=== 1 PASS / 0 FAIL / 0 DEGRADED ===`、退出码 0。
   - 根因位于 `app/contracts/d2/fixtures/csharp-runner/CSharpFixtureRunner.cs:647-656`：先完整复制 native params；仅当 `message` 存在时才执行 `Remove("message")` 并写 `text`，若真实 client 已错误发送 `text`，该字段会原样留在 payload 中并满足 fixture 的 `payload.text`。这复现了 Stage A 式“看似从真实 params 匹配、实际允许错误字段形状自证”的假绿。Swift 权威实现 `SwiftFixtureRunner.swift:612-623` 具有同样的条件 remap，修复时应同步收口。

3. **nativeCallOrder / advance_clock：通过。**
   - `sessions.abort` 与 `approval.resolve` 仅在 responder 被真实 client 调用时追加（`CSharpFixtureRunner.cs:558-577`），不是注册时追加；基线运行 `stop-force-denies-pending-approval` PASS，真实 RPC 日志顺序为 `approval.resolve` 后 `sessions.abort`，与 expected 完全一致。
   - `ApplyAdvanceClockAsync` 在 `CSharpFixtureRunner.cs:918-941` 轮询 `IsCallSettled`；真实 SG-5 定时器在 `OpenclawGatewayKernelClient.cs:764-787` 使用 `Task.Delay(timeoutSeconds)`。单跑 `stop-timed-out.json` 的 `/usr/bin/time -p` 结果为 `real 2.16` 秒并 PASS，明显跨过注入的 1 秒内部 timer，未发现 runner 直接铸造 `timed_out` 的路径。

4. **PartialMatch 三端等价：当前 fixture 值域上通过。**
   - `PartialMatch.cs:142-195` 对缺失值与显式 JSON null 分流、对象按 expected 子集递归、数组强制等长并逐项匹配；bool 必须两侧均为 `System.Boolean`，不会发生 Swift/Foundation 的 `NSNumber` 0/1 桥接误判，README 的“C# 无需 objCType workaround”论证成立。
   - 当前 13 条 fixture 的数字均为普通 JSON 整数/小数范围（扫描最大值 `1800000`），C# 的 `long`/`double` 统一与 TS `number` 在该值域等价；未发现当前样本上的数值精度、显式 null 或数组长度放水。阻断缺陷发生在进入 matcher 前的 native 参数规范化，不在 matcher 本体。

5. **三端 parity / DEGRADED / teeth：矩阵通过，但 teeth 覆盖不足。**
   - TS：`find app/contracts/d2/fixtures -name '*.json' -not -path '*/bin/*' -not -path '*/obj/*' | sort | xargs node app/contracts/d2/fixtures/ts-runner/runner.ts`，实测 13 条 `[PASS]`、`ALL PASS`。
   - Swift：按 README 的 `swiftc ... -o /tmp/T-052-swift-fixture-runner && /tmp/T-052-swift-fixture-runner`，实测 `12 PASS / 0 FAIL / 1 DEGRADED`。
   - C#：`dotnet build --nologo && dotnet run --no-build`，build 为 `0 Warning(s) / 0 Error(s)`，runner 为 `12 PASS / 0 FAIL / 1 DEGRADED`。
   - Swift/C# 的静态扫描集合均为 `interrupt`、`respondApproval`、`capabilities`（C#：`CSharpFixtureRunner.cs:998-1012`；Swift：`SwiftFixtureRunner.swift:932-942`），本次两端唯一 DEGRADED 均为 `soft-steer-then-stop` 的 `interrupt` TODO，原因同口径。
   - README 第 1 个 teeth 的**精确错值**反证已独立复现：把 `message` 值写死为 `"T-STAGEB-TEETH-WRONG-MESSAGE"` 后退出 1，报 `expect_outbound(send1).payload.text` 不匹配；第 2 个 teeth 的调用时刻记录与基线顺序断言吻合，第 3 个 teeth 的 matcher 调用链也确实覆盖 timeline/final expected。三项报告本身可信，但第 1 项只证明“正确字段上的错误值”会失败，没有覆盖“错误字段名恰好等于规范化目标名”的旁路，因而不足以支撑完整声明。

## Decisions / deviations

- 将五个“对抗核验重点”视为五项 acceptance verification；五项均已执行，其中第 2 项发现阻断缺陷。
- 按任务授权做了三次单行临时证伪：错误 `message` 值（预期 FAIL）、错误 `key`（预期 FAIL）、错误字段名 `text`（异常 PASS）。每次均用反向补丁还原；最终重新 build、单跑恢复 PASS，并以 blob/hash + `git diff --exit-code` 复核无源码残留。
- 仅使用允许的 `dotnet build` / `dotnet run` / `node` / `swiftc`，未调用 `csi`、`dotnet-script` 或任何 C# 交互工具。`dotnet` 生成的忽略项 `csharp-runner/bin/`、`obj/` 不是源码变更。

## Open questions

none

## Verdict

REWORK

## Next recommendation

先修 `CSharpFixtureRunner.cs:647-656`：对 `sessions.send` 必须显式要求捕获到 native `message`，并在映射前移除/拒绝原生 payload 中预存的 `text`；缺少 `message` 时应产生 mismatch（或写入显式 null marker 使现有 expected 必然失败），不能让错误的 `text` 自己满足 D2 `payload.text`。同步修正 Swift 的同构逻辑，加入“生产 client 把 `message` 改名为 `text` 时 fixture 必须 FAIL”的回归 teeth，然后重跑三端 13/13、12/13、12/13 与三类反证后再进闸。

## Vendor output (parsed) _(preview 8000/368310 chars; full raw stream in `T-052-output.log`)_

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
session id: 019f9588-f706-70b2-8a07-b88600b58655
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

## T-052（SG-8.7 ★审查闸2：Stage B C# 金标 parity runner 对抗审，单 codex）

**Task-type**: `code-review-adversarial` · **Vendor**: codex（轮换,T-051 为 grok；⚠️ **工具约束:可跑 `dotnet build`/`dotnet run`/node/swiftc,严禁 `csi`/`dotnet-script` 等 C# 交互工具**——T-046 先例:跑 csi 触发你自身安全过滤器致评审中止）· 只读

**评审对象**（主仓库 commit `505202a5`）：`app/contracts/d2/fixtures/csharp-runner/`（`FixtureDsl.cs`/`PartialMatch.cs`/`CSharpFixtureRunner.cs`/`CSharpRunnerMain.cs`/`CSharpRunner.csproj`）+ README 三端 parity 节。**权威对照**：已 validated 的 `swift-runner/`（T-048→T-050→T-051 三审收敛,commit `98d38e0e`）+ `ts-runner/` + `dsl.ts`；被驱动的 SG-5 真实 C# client `app/kernel-client/csharp/`（stop force-deny + NOTE-A 已修,30/30,grok T-049 PASS_WITH_NOTE）。`git show 505202a5`。

**背景**：Stage A 的 Swift runner 经三轮审查才挤干"绿灯≠真 parity"的水分（臆造字段/自构 request 匹配/空转 oracle/不断言顺序/漏 seq）。Stage B 声称把全套纪律镜像到 C# runner：三端矩阵 TS 13/13 + Swift 12/13 + C# 12/13（同一 expected、DEGRADED 同因），3 处 teeth 反证（错 param/错顺序/放水 matcher→FAIL）均还原。主会话已独立复跑三端 + C# 端 teeth 亲证。由 Sonnet 所写,需异构对抗复核。

**对抗核验重点（找真缺陷 + 可复现;重点证伪"C# 绿灯是否真能证明它声称的东西"）**：
1. **真驱动 vs mock**：`CSharpFixtureRunner.cs` 的 `client_call` 是否真调 `OpenclawGatewayKernelClient` 的 `CreateSessionAsync`/`SendAsync`/`Subscribe`/`StopAsync`（经 `TestSupportStubRpc`/喂帧钩子）？有无任何 short-circuit 预置状态绕过真实 client 代码路径？`ReplyGate`（lock+TCS）是否真让 RPC 在途、中途 assert 观察真实状态（对照 Swift 的 actor ReplyGate,C# lock 版有无竞态）？
2. **native params 匹配是否真捕获**：`NormalizeNativeParams` 是否从 stub 闭包运行时捕获的真实 `params` 规范化（非 timeline args 回放）？`message`→`text` 反映射、key 反查 sessionId、无 fallback（缺失→null 标记）是否与 swift-runner 语义一致？**证伪**：临时改真实 C# client 发错 native param → fixture 应 FAIL（改完 `git checkout` 还原）。
3. **nativeCallOrder/advance_clock**：顺序是否真实调用时刻记录（非注册时）？advance_clock 是否轮询 `IsCallSettled` 且 timed_out 真由 SG-5 内部 `Task.Delay` timer 触发（可计时验证）？
4. **PartialMatch 三端等价**：C# 的对称统一值域实现与 Swift（非对称+objCType workaround）/TS 在当前 fixture JSON 值域上是否行为等价？其文档化的"C# 无需 objCType workaround"论证是否成立？有无放水路径（如 number 精度/显式 null/数组长度）？
5. **三端 parity 声明与 teeth 可信度**：亲跑三端（TS 排除 bin/obj 污染:`find ... -not -path '*/bin/*' -not -path '*/obj/*'`）确认 13/13、12/13、12/13 且 DEGRADED 同因；`DegradeReason` 静态扫描是否与 swift-runner 同口径（interrupt/respondApproval/capabilities 桩）？报告声称的 3 处 teeth 是否可信（可抽验其一）？有无 Stage A 式表面绕过在 C# 端复发（如某字段仅 C# 端不校验）？

**Verdict**：`PASS`（C# runner 可信、三端 parity 真成立 → SG-8.7 主体达成）| `PASS_WITH_NOTE` | `REWORK`（逐条给 `app/contracts/d2/fixtures/csharp-runner/<file>:<line>` + 可复现）| `FAIL`。
**产出**：五项逐条 + verdict。落盘 `.hopper/handoffs/T-052-output.md`。**Read-only**：审查不改任何文件（证伪临时改动必须还原并说明）；忽略跨仓/别目录全局 skill。中文。

codex
我将直接做只读对抗审查：先锁定两处目标 commit 与工作树基线，再逐项核验真实 client 路径、参数捕获、时序、matcher 语义和三端运行结果；仅写入指定的 `T-052-output.md`，任何临时证伪改动都会在最终校验前还原。
  → 确认仓库、commit、工作树与评审文件基线
  • 静态审查 C# runner、真实 client、Swift/TS 权威实现
  • 运行三端矩阵并执行至少一项可复现 teeth 证伪
  • 汇总结论并写入 T-052-output.md
  • 复核仅输出文件发生变化
exec
/bin/zsh -lc 'rg --files app/contracts/d2/fixtures/csharp-runner app/contracts/d2/fixtures/swift-runner app/contracts/d2/fixtures/ts-runner app/kernel-client/csharp | sort' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
exec
/bin/zsh -lc 'rg -n "parity|C#|Swift|TypeScript|13/13|12/13|DEGRADED" app/contracts/d2/fixtures/README.md app/contracts/d2/README.md README.md 2>/dev/null' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 0ms:
app/contracts/d2/fixtures/README.md:1:# 金标 parity fixtures（骨架 + SG-1 深化：DSL 正式化/最小 TS runner + SG-8.7 Stage A：Swift 真实 client runner/fixture 扩全 + Stage B：C# 真实 client runner，三端 parity 收官）
app/contracts/d2/fixtures/README.md:3:对应 D4 跨平台架构 v2.2 §4「金标 parity 测试」，尤其 §4.3「fixture DSL：确定性
app/contracts/d2/fixtures/README.md:4:action/timeline」。金标 parity 测试是一组**语言中立的契约一致性用例**——每条用例是一条确定性
app/contracts/d2/fixtures/README.md:15:**SG-8.7 Stage A/B 已分别补齐 Swift/C# 真实 client runner**（见文末「三端 parity」一节）。
app/contracts/d2/fixtures/README.md:19:`session-lock`/`operation-outcome` 三组扩到共 10 条新 fixture + Swift 真实 client runner**（见文末
app/contracts/d2/fixtures/README.md:20:「Swift 金标 parity runner」「三组 fixture 覆盖清单」两节）；**T-048 REWORK 轮**（对抗审 codex 判
app/contracts/d2/fixtures/README.md:25:Swift `PartialMatch`/`expect_outbound` 与 TS 不等价的假阴性、把 `advance_clock` 的确定性从"固定
app/contracts/d2/fixtures/README.md:32:分流、`EmptyPayload` 边界、C# runner（D4 §4.4）仍是后续轮次交付物，不在本轮范围内。
app/contracts/d2/fixtures/README.md:69:（它不模拟原生双帧 join），只有 Swift/C# 这类驱动真实 client 的 runner 会读取。
app/contracts/d2/fixtures/README.md:89:parity/
app/contracts/d2/fixtures/README.md:119:  再誊抄一遍——否则两端 parity 只是"互相抄"的空转（T-048 codex 对抗审的核心批评），一旦真实
app/contracts/d2/fixtures/README.md:135:跑 `defaultFixturePaths()` 枚举的默认 13 条清单，与 swift-runner `SwiftRunnerMain.swift`/
app/contracts/d2/fixtures/README.md:137:ts-runner/runner.ts` 对全部 13 条 fixture 跑 **13 PASS / 0 FAIL**。Swift/C# runner
app/contracts/d2/fixtures/README.md:139:parity」总节。
app/contracts/d2/fixtures/README.md:141:## Swift 金标 parity runner（SG-8.7 Stage A 新增）
app/contracts/d2/fixtures/README.md:143:`swift-runn

... [truncated, 360310 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 522292
- end_time: 2026-07-24T19:18:50.496Z
- log: see `T-052-output.log` for raw output
