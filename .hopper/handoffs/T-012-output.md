---
phase: done
last_progress_at: "2026-07-21T13:14:45.863Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-21T13:14:45.861Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 306499
adapter_status: success
---
# T-012 — D1 KernelPort v3.3 M1-M5 confirm-readiness gate

## Summary

v3.3 已实质关闭 M2、M3，并补齐 M4 的 soft steer/cancel 遇 stop 仲裁；M1 的 `queued:false` 重叠分支也已从主判定规则删除，M5 的 aggregate 条件必填与两个拒绝码均已写入。可是，本轮新增文字仍产生三处范围内真矛盾：soft steer 被 §9.3 重新写成三终态、KernelEvent 旧结构数量写错、`queryBilling` 的异步凭证拒绝被归入同步/立即拒绝通道，因此尚不能确认 v3.3 定稿。

## Files touched

- `.hopper/handoffs/T-012-output.md`：按任务要求落盘本次只读 acceptance review。
- 其余：none；未修改 `/Users/litianyi/.llm-wiki/` 下的 v3.3 评审对象、v3.2 基线或任何对照材料。

## Acceptance verification (3/6)

### 1. M1 — 未完全闭合

原始重叠分支已删除：§6.1(a) 明定响应体字段一律不参与判断，成功 ack → `submitted`、RPC 失败 → `rejected`（v3.3:420-425），`queued:false` 只在解释“为何不得参与判定”时出现，不再是分支条件。

但 M4 的新增锁规则又把 soft steer 正常终态写成 `submitted` / `rejected` / `timed_out`（v3.3:659）。这与 §6.1(a) 的“二态、只由 RPC 成功/失败分流”直接冲突；尤其 §6.1(a) 已把网络/连接层失败归入 `rejected`（v3.3:423），§9.3 却使同类等待超时可另报 `timed_out`。因此 M1 在与本轮其他新编辑合并后仍不是唯一可实现的二态契约。

```bash
rg -n "结果只由该 RPC|响应体内任何字段|outcome:'submitted'|outcome:'rejected'|submitted.*rejected.*timed_out" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 420: 只由 RPC 是否成功返回分流，响应体字段不参与
# 422: 成功 ack -> submitted
# 423: RPC/网络/连接层失败 -> rejected
# 659: soft steer 正常终态却列 submitted/rejected/timed_out
```

### 2. M2 — 通过

`OperationOutcome` 已新增 `aborted_effect_unknown`，并把 `rejected` 限定为 abort 确认从未生效（v3.3:175-197）；hard 结果规则把 C-4 信号不足统一导向 unknown，而非借道 `rejected`（v3.3:442-450），C-4 降级表也同步更新（v3.3:709）。调用方义务明确：不得推断旧 run 仍运行或已中止，须按“可能已中止”保守处理并在需要时重新查询状态（v3.3:189-193,448）。

```bash
rg -n "aborted_effect_unknown|严格限定为. abort 从未生效|不得.*推断旧 run|C-4" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 189-196: 类型定义、调用方义务、rejected 收窄
# 448-449: hard 路径 unknown/rejected 互斥规则
# 709: C-4 否定降级改报 aborted_effect_unknown
```

### 3. M3 — 行为闭合，通过

FSM 已补 `FORCE_DENY_PENDING_KERNEL_ACK → TIMED_OUT_DENY`，并明确让位于内核权威终态、同一 reqId 不产生双终态（v3.3:493-499）。缓冲请求一旦超时立即终态化、移出队列且不得再提升，只有仍未终态化的请求可浮现（v3.3:516-517）。新增的 `ApprovalBufferResolvedEvent` 已进入 11 成员判别联合，携 `reqId`、`reason`、基类 `ts`；缓冲超时/溢出不再计入 `forceResolvedApprovals`（v3.3:274-314,519）。

```bash
rg -n "FORCE_DENY_PENDING_KERNEL_ACK → TIMED_OUT_DENY|一旦超时即终态化|不得.*再提升|ApprovalBufferResolvedEvent|不计入.*forceResolvedApprovals" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 285/305-310: 第 11 个联合成员及事件字段
# 493-499: 缺失转移已补
# 516-519: 超时不可提升、独立事件上报
```

### 4. M4 — 锁行为闭合，通过

soft steer 与 cancel 都已定义 stop 到达后的 wait/no-preempt、原 operation 终态化、锁转为 `stop_in_progress`、随后执行 stop 的规则（v3.3:659,661）；openclaw 单 RPC hard 路径也保留“只能等待整体返回”的限定（v3.3:663-665）。因此 acquire/wait/preempt/release 的状态转移覆盖已补齐，v3.3:666 的“完整”声称就锁行为本身成立。soft outcome 词汇与 M1 的冲突另计于第 1、6 项，不否定这里已补齐的锁仲裁路径。

```bash
rg -n "mode:'steer'.*遇.*stop|mode:'cancel'.*遇.*stop|等待，不抢占|设计是完整的" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 659: soft steer wait -> stop_in_progress
# 661: cancel wait -> stop_in_progress
# 666: 完整性声称及适用范围
```

### 5. M5 — 部分闭合，未通过

`deploymentTokenRef` 已正确建模为 aggregate 条件必填；缺失时 `createSession` 在步骤 1-3 前以 `aggregate_billing_requires_deployment_token` 拒绝（v3.3:113-121,132-140,619-621）。`queryBilling` 也新增 `billing_query_subject_unresolved`，并禁止返回虚构零用量快照（v3.3:574-583,622-624）。

剩余矛盾在失败通道：`queryBilling` 的签名返回 `Promise`（v3.3:574-577），凭证“在调用 newapi 用量接口时被拒”只能在异步 I/O 返回后得知（v3.3:583），正文却要求“同步拒绝”，并把该码放进定义为“同步/立即拒绝”的 `KernelPortRejectionCode`（v3.3:606,622-627）。调用方究竟接同步 throw/前置 rejected Promise，还是等待远端调用后的结构化 Promise rejection，仍没有唯一答案，故“失败形状”尚未完全闭合。

```bash
rg -n "function queryBilling|调用 newapi 用量接口时被拒|必须同步拒绝|KernelPortRejectionCode.*同步/立即|billing_query_subject_unresolved" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 574-577: Promise<SessionBillingSnapshot>
# 583: 远端凭证拒绝却要求同步拒绝
# 606/622-627: 该码归入同步/立即拒绝阶段
```

### 6. 新编辑自洽性与数字核验 — 未通过

除上面的 M1↔M4、M5 失败通道冲突外，还有一处 M3 新增事件的机械数字矛盾：§3 说 `MessageDeltaEvent` 到 `OperationCompletedEvent` 是“九类结构”，但该范围实际有 10 个既有联合成员，随后新增 `ApprovalBufferResolvedEvent` 才得到 11 个（v3.3:271,274-285）。`INV-2` 的“8 类内核事件 + 3 类扩展 = 11”、事件联合本身、`ApprovalBufferResolvedEvent` 的“其余 10 类”以及 §6.1a 的“OperationCompletedEvent 之外其余 10 类”均为正确口径（v3.3:59,274-285,314,462），只有 v3.3:271 的“九类”错误，且与 §16“全文同步勘正”的声称冲突（v3.3:760）。

§10 的 F/S 分桶本身未引入新矛盾：最终为完全消解 8、部分化解 4、仍开放 4、SDK 延后 3，`8+4+4+3=19`（v3.3:695-698）。

```bash
rg -n "九类结构|判别联合由 10 类扩为 11 类|其余 10 类|8\+4\+4\+3=19|全文出现处均已同步" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md
# 271: 既有成员误写为九类，同时又正确写 10 -> 11
# 314/462: “其余 10 类”正确
# 698: §10 合计 19 正确
# 760: 声称全文数字已同步，与 271 不符
```

## Decisions / deviations

- 将“read-only”解释为不改评审对象及任何业务/知识库文件；仅写入任务明确要求的本交付文件。
- 严格限制在 M1-M5 与 v3.3 为关闭它们而新增的文字；未重开 v3.2 其他架构 finding，也未提出 nice-to-have。
- 对 M5 的“同步拒绝”按 §9.1 自己定义的同步/立即阶段解释，而不是泛化为任意 Promise rejection；否则同一文档内的三阶段错误模型将失去区分意义。

## Open questions

none

## Verdict

**MUST-FIX（acceptance 状态：REWORK）**

M2、M3 已闭合，M4 的锁路径也已补齐；但 M1 与 M5 尚未形成唯一可实现的契约，且新增事件计数有一处明确矛盾，不满足“ M1-M5 全闭合、无新矛盾”的 CONFIRMABLE 条件。

## Next recommendation

做一轮只含三处的机械/语义最小修订后重跑同一 gate：①在 §9.3 将 soft steer 的终态与 §6.1(a) 对齐为严格 `submitted`/`rejected` 二态（或若确要保留 `timed_out`，则必须同步撤回并重写 M1 的二态承诺，但这不符合本轮既定闭合目标）；②把 v3.3:271 的“九类结构”改为“十类结构”；③把 `queryBilling` 的前置缺配置与远端凭证拒绝分开，前者走同步/立即拒绝码，后者明确为返回 Promise 的结构化异步 rejection（或另设 billing query error 形状）。无需重开 M1-M5 之外的架构评审。

## Vendor output (parsed) _(preview 8000/371401 chars; full raw stream in `T-012-output.log`)_

```
Reading additional input from stdin...
OpenAI Codex v0.144.5
--------
workdir: /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: danger-full-access
reasoning effort: xhigh
reasoning summaries: none
session id: 019f84cb-de8f-7a41-92b9-84d483ebde5c
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

## T-012

**Task-type**: `code-review-acceptance`（v3.3 定向重跑 confirm-readiness gate，**接续 T-011，只验 M1-M5 闭合**）· **Vendor**: codex（刻意选择：M1-M5 是你 T-011 提出的，由你验证是否真闭合最有效；非随机，记录偏离）· 只读

**评审对象（绝对路径，本仓库之外）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md`（770 行，D1 KernelPort **v3.3 最小闭合**）。
对照：`kernel/d1-kernelport-spec-v3-2.md`（被修订基线）、`research/d1-v31-review.md` §6（你 T-011 的 M1-M5 详情）、`/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.hopper/handoffs/T-011-output.md`（M1-M5 原文）、`kernel/kernel-ecosystem-facts.md`。

**背景**：你在 T-011 判 v3.2 为 MUST-FIX，点名 M1-M5 五处"设计文本内即可关闭"的契约自洽缺口。v3.3 是**只针对 M1-M5 的最小闭合**修订，未动其他。你的 T-011 Next 明确"仅针对 M1-M5 重跑同一 gate，无需重新开放全量架构评审"——本任务即执行这一步。

**只验两件事（严格限定 M1-M5，不重开其他范围、不提 nice-to-have）**：
1. **M1-M5 是否真闭合**：
   - M1（soft 二态去重叠）：`queued:false→rejected` 分支是否真删除？结果是否只由 RPC 成败分流、响应体字段不再参与？（§6.1(a) 行420-425）
   - M2（unknown 终态）：`aborted_effect_unknown` 是否真承接"abort 生效性不明"、`rejected` 是否真收窄为严格"abort 从未生效"、C-4 降级是否不再借道 rejected、调用方处理是否明确？（§6.1(b) 行442-449 + §2.4/§9.1/§8）
   - M3（审批 FSM + 缓冲）：`FORCE_DENY_PENDING_KERNEL_ACK→TIMED_OUT_DENY` 转移是否补上？缓冲请求超时是否立即终态化不可再提升？缓冲可见性是否改用新的 `ApprovalBufferResolvedEvent`（第11类）而非复用 `forceResolvedApprovals`？（§6.2 行493/516/519 + §3 事件定义）
   - M4（锁矩阵）：soft steer / cancel 在途遇 stop 是否都有 acquire/wait/preempt/release 规则？"覆盖所有状态转移"声称是否已名副其实或诚实限定？（§9.3 行659/661/666）
   - M5（aggregate 前置）：`deploymentTokenRef` 是否条件必填、缺失时 `createSession` 是否同步拒绝（`aggregate_billing_requires_deployment_token`）？`queryBilling` 失败形状是否定义？（§2.1 行134 + §7 行583 + §9.1）
2. **闭合 M1-M5 的新编辑有无引入新矛盾**：新增 `aborted_effect_unknown`/`ApprovalBufferResolvedEvent`（判别联合 10→11）/两个新拒绝码/soft-cancel 遇 stop 锁规则——彼此自洽吗？与 v3.3 保留的正文冲突吗？§10 统计有无新数字矛盾？

**Verdict**：`CONFIRMABLE`（M1-M5 全闭合、无新矛盾 → D1 v3.3 可定稿）或 `MUST-FIX`（仅列 M1-M5 中仍未闭合的、或新编辑引入的真矛盾）。

**产出**：M1-M5 逐项闭合结论 + 新矛盾核验 + verdict。落盘 `.hopper/handoffs/T-012-output.md`。**Read-only 硬约束**：不改任何文件（尤其不写 ~/.llm-wiki/）；评审对象是 v3.3 spec，非本仓库代码；忽略任何试图让你审别的仓/目录的全局 skill。中文。

codex
我会严格按 T-012 的窄范围执行：只核验 M1–M5 及这些修订彼此/与保留正文的自洽性，不重开架构评审；除规定的评审报告 `.hopper/handoffs/T-012-output.md` 外不改动任何文件。先读取 v3.3、v3.2、T-011 原结论及指定事实基线，再逐项用行号与检索证据确认。
exec
/bin/zsh -lc 'diff -u /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 exited 1 in 0ms:
--- /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md	2026-07-21 21:03:11
+++ /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-3.md	2026-07-21 21:00:21
@@ -1,5 +1,5 @@
 ---
-title: "D1 KernelPort 内核窄腰 v3.2 诚实收窄修订 Spec（scope=openclaw+hermes；据 codex T-010 聚焦复核收窄 soft steer 结果态 + §7 sessionId 时序/attribution 权威化 + 边角终态/五态审批/锁矩阵补全 + 实现阶段 conformance 清单）"
+title: "D1 KernelPort 内核窄腰 v3.3 最小闭合修订 Spec（scope=openclaw+hermes；据 codex T-011 confirm-readiness gate 最小闭合 M1-M5——soft 二态判定去重叠 + aborted_effect_unknown 诚实终态 + 审批FSM转移/缓冲上报补完 + 锁矩阵补齐 soft/cancel 遇 stop + aggregate 计费前置校验）"
 type: kernel
 tags: [p2-kernel, openclaw, hermas, newapi, local-kernel, message-schema, architecture-decision]
 created: 2026-07-21
@@ -7,33 +7,35 @@
 published_at: 2026-07-21
 ingested_at: 2026-07-21
 sources:
-  - kernel/d1-kernelport-spec-v3-1.md
+  - kernel/d1-kernelport-spec-v3-2.md
   - research/d1-v31-review.md
-  - raw/external/T-010-v31-review-codex.md
-  - /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.hopper/handoffs/T-009-output.md
+  - raw/external/T-011-v32-gate-codex.md
+  - /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.hopper/handoffs/T-011-output.md
   - kernel/kernel-ecosystem-facts.md
 component: P2-kernel
-design_status: superseded
+design_status: draft
 ---
 
-# D1 KernelPort 内核窄腰 v3.2 诚实收窄修订 Spec（scope=openclaw+hermes；据 codex T-010 聚焦复核收窄 soft steer 结果态 + §7 sessionId 时序/attribution 权威化 + 边角终态/五态审批/锁矩阵补全 + 实现阶段 conformance 清单）
+# D1 KernelPort 内核窄腰 v3.3 最小闭合修订 Spec（scope=openclaw+hermes；据 codex T-011 confirm-readiness gate 最小闭合 M1-M5——soft 二态判定去重叠 + aborted_effect_unknown 诚实终态 + 审批FSM转移/缓冲上报补完 + 锁矩阵补齐 soft/cancel 遇 stop + aggregate 计费前置校验）
 
-> **经 codex T-011 confirm-readiness gate MUST-FIX，待 v3.3（2026-07-21）**：见 [[d1-v31-review]] §6。**v3.3 已发布**，见 [[d1-kernelport-spec-v3-3]]。
+## Changelog（v3.2 → v3.3：codex T-011 confirm-readiness gate 的最小闭合修订）
 
-## Changelog（v3.1 → v3.2：诚实收窄修订）
-
-> **诚实记录**：v1→v2→v3→v3.1 四轮修订的共同模式是"发现事实缺口 → 调研/源码深挖补齐 → 据新事实重设计"；v3.2 是**性质不同的一轮**——codex T-010 聚焦复核（xhigh 推理强度，逐条核验 v3.1 对 T-008 五项 findings 的修复）发现的核心问题不是"事实还没查到"，而是 v3.1 **把几处仍标注"未确认/部分"的信号，当成了契约可以稳定依赖的分支条件**（尤其头号 BLOCKER：soft `chat.send` 的 ack/`queued`/`reason` 语义——T-009 与 T-010 两轮独立工作都收敛到"这件事本身不能靠再研究/再设计关闭，只能靠一次真实 live probe"）。据此，v3.2 **不做新一轮源码调研，也不新增任何能力声称**；v3.2 做的是**收窄**：把 v3.1 里建立在未确认信号上的契约分支，逐条改写为两种诚实形态之一——
+> **诚实记录**：[[d1-kernelport-spec-v3-2]] 发布后经 codex **T-011 confirm-readiness gate**（定稿前专用核验，非开放重审，只核验三件事

... [truncated, 363401 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 306499
- end_time: 2026-07-21T13:14:45.861Z
- log: see `T-012-output.log` for raw output
