---
phase: done
last_progress_at: "2026-07-21T12:32:07.128Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-21T12:32:07.127Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 286562
adapter_status: success
---
# T-011 — D1 KernelPort v3.2 confirm-readiness gate

## Summary

v3.2 已实质纠正 T-010 的多数 finding：soft steer 不再承诺注入成功、operation 事件明确只保证在线订阅、sessionId/计费归因改为部署时权威模式，`allow_session` 与 hard partial-failure 形状也进入了公开模型。但本次限定范围复核仍发现 5 组会让实现无法唯一落地的契约矛盾，集中在 soft 二态判定、C-4 降级语义、审批 pending 分支、锁仲裁和 aggregate 计费前置条件；因此尚不能作为设计阶段成果定稿。

## Files touched

- `.hopper/handoffs/T-011-output.md`：按任务要求落盘本次只读 acceptance review。
- 其余：none；未修改 `/Users/litianyi/.llm-wiki/` 下的评审对象或对照材料。

## Acceptance verification (3/3)

### 1. 收窄是否诚实 — 未通过

已确认的诚实收窄包括：`submitted` 明示只承诺 RPC 被接受（v3.2:63,386,389）；`OperationCompletedEvent` 只保证在线订阅且不重放（v3.2:421-424）；`billingAttribution` 改为部署时权威声明，删除日志零/非零自诊断（v3.2:335-341,488-505）；F-08 也明确排除 OpenClaw 单 RPC hard path 的不可抢占窗口（v3.2:603-606）。

但仍有两处把未确认信号留在契约分支或用模糊降级掩盖结果不确定性：

1. soft 规则 1 规定“成功 ack，无论响应字段取值”一律 `submitted`（v3.2:386），规则 2 又规定成功响应若透出未经 C-1 确认的 `queued:false` 可判 `rejected`（v3.2:387）。同一个“成功 ack + queued:false”同时命中两个终态，且 `queued` 的外部语义正是待验事实，故 C-1 尚未被真正隔离出当前契约。
2. hard 路径把 `rejected` 定义为“abort 从未生效”（v3.2:174,407,410），C-4 的否定降级却要求把“无法区分 abort 未生效 / 已生效但 resend 失败”的错误也报作 `rejected`（v3.2:409,649）。这会让调用方把“旧 run 状态未知”误读为“旧 run 未被中止”，不是诚实保守的降级。

机器核验：

```bash
rg -n "成功 ack|queued:false|abort 从未生效|无法区分.*abort|笼统.*rejected" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md
# 386: 成功 ack 无论字段取值 -> submitted
# 387: queued:false（待 C-1）-> rejected
# 407/410: rejected = abort 从未生效
# 409/649: 无法区分 abort 是否生效 -> rejected
```

### 2. 5 个 C-item 是否真属实现阶段 — 部分通过

| C-item | 判定 | 对定稿的影响 |
|---|---|---|
| C-1 soft ack | 确属 live-probe-limited；公开形状可稳定为“RPC 成功即 `submitted`、RPC 失败即 `rejected`”，无需等 probe 才定类型。 | **当前有阻断**：正文仍用待验 `queued:false` 分支终态，见阻断项 M1。 |
| C-2 operation ledger | 不是“只能靠 live probe 验证”的事实问题，而是产品/存储能力选择；不过基础契约已明确只保证在线订阅（v3.2:423-424,647），不建 ledger 也有良定义行为。 | 非阻断；建议标成 optional implementation decision，而非 conformance fact。 |
| C-3 per-session 换 key | 确属目标部署/具体内核配置面的实操验证；`billingAttribution` 两值已容纳成功与失败两种结果，不会迫使公开类型返工。 | C-item 本身非阻断；但 aggregate 模式缺少 `deploymentTokenRef` 必填/拒绝规则，见 M5。 |
| C-4 hard error 信号 | 确属需真实失败场景验证的可观察性问题。 | **当前有阻断**：否定结果的降级与 `rejected` 的公开语义冲突，见 M2。 |
| C-5 Hermes soft inject | 不属于“设计阶段无法关闭”：表内验证方法是 repo 级源码深挖（v3.2:650），可以在设计阶段研究；但当前保守默认“不声明 steer”完整且可扩展。 | 非阻断；更适合列为非阻塞 capability research。 |

尤其 C-1 不会要求改变 `InterruptResult` 的公开形状，只需删掉当前契约对待验 `queued:false` 的分支依赖；C-3 也不会要求改 `billingAttribution` 的 enum，只需钉死 aggregate 配置前置条件。因此两项可以诚实延后，但当前正文的配套降级尚未全部闭合。

机器核验：

```bash
rg -n "^\| \*\*C-[1-5]\*\*|仅对在线订阅者|deploymentTokenRef\?:" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md
# 423: operation event 仅在线保证
# 646-650: C-1..C-5 及各自验证/降级
# 109: deploymentTokenRef 仍是可选字段
```

### 3. v3.2 新编辑有无引入内部矛盾 — 未通过

以下部分自洽：`allow_session` 已同时进入 `ApprovalDecision`、`approvalDecisionKinds` 与拒绝码门控（v3.2:215-236,313-318,556-568）；`affectedRunId` 改可选消除了无 active run 时不可构造问题（v3.2:179-189）；operation 在线订阅范围与不重放规则一致。

阻断定稿的内部矛盾如下：

- **M1 — soft 二态仍有重叠分支。** v3.2:386 与 v3.2:387 对“成功 ack + `queued:false`”给出不同终态。应钉死当前版本只按 RPC 成功/失败分流；C-1 结果若将来足以拓宽，再通过后续协议版本新增语义。
- **M2 — `aborted_resend_failed` 的 C-4 降级破坏 `rejected` 语义。** v3.2:407/410 承诺 `rejected` 表示 abort 未生效，v3.2:409/649 却把 abort 是否生效未知也归入该值。必须新增/改写一个明确表示“abort effect unknown”的终态，或收窄 `rejected` 的公开承诺；不能让调用方推断旧 run 仍在。
- **M3 — 审批 FSM 与 pending #2 仍未闭包。** `FORCE_DENY_PENDING_KERNEL_ACK` 只列出转向人工 allow/deny，遗漏内核权威超时并发发生时转到 `TIMED_OUT_DENY` 的路径（v3.2:444-453 对照 437-438）；缓冲请求“已超时”后又被描述为可提升为 active pending（v3.2:469-470）。同时，缓冲超时的可见性依赖语义仅用于 stop/cancel 强制 deny 的 `forceResolvedApprovals`，或依赖契约中不存在的 reqId 状态查询（v3.2:469；该字段保留定义见 v3:369-371）；队列溢出也在未更新字段定义的情况下复用 `forceResolvedApprovals`（v3.2:471）。这些是审批 exactly-once/可观察性的运行时分支，不是命名瑕疵。
- **M4 — “完整”锁矩阵没有覆盖所有 interrupt mode。** 矩阵把任意 `interrupt_in_progress` 遇到 `stop()` 都指向特殊仲裁（v3.2:591-598），但后续两个分支只描述 hard `abort_and_resend` 的“resend 未发/已发”（v3.2:600-605）；对 `mode:'steer'` 的 soft RPC 在途和 `mode:'cancel'` 在途没有 acquire/wait/preempt/release 规则。故 v3.2:606 的“覆盖所有状态转移”仍属过度声称。
- **M5 — aggregate 计费查询缺配置不变量。** `deploymentTokenRef` 在公开输入中是可选（v3.2:109），但 aggregate 模式又把它定义为唯一真实查询主体（v3.2:533），没有规定缺失时 `createSession` 必须同步拒绝，也没有 `queryBilling` 的失败形状。C-3 失败后这会成为必经默认路径，不能留到实现自由解释。

机器核验：

```bash
rg -n "FORCE_DENY_PENDING_KERNEL_ACK|已经超时|forceResolvedApprovals|完整互斥矩阵|stop 优先仲裁|deploymentTokenRef\?|唯一.*查询主体" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md
# 439-470: FSM 转移与缓冲超时
# 469/471: forceResolvedApprovals 被扩用于缓冲超时/溢出
# 589-606: 完整矩阵与仅 hard resend 的仲裁分支
# 109/533: optional deploymentTokenRef vs aggregate 查询必需
```

## Decisions / deviations

- 将“read-only”解释为不改评审对象及任何业务/知识库文件；仅写入任务明确要求的本交付文件。
- 严格限制在 T-010 finding 的收窄真实性、5 个 C-item 与 v3.2 新编辑自洽性；未重开 v3.1 其余历史 finding，也未提出 nice-to-have。

## Open questions

none

## Verdict

**MUST-FIX（协议状态：REWORK）**

当前剩余问题不全是实现期才能验证的 C-item：M1-M5 均是设计文本内即可关闭、且会影响调用方如何解释终态或实现如何选择唯一分支的定稿阻断项。

## Next recommendation

先做一轮最小 v3.2 文本修订：统一 soft 成功/失败判定；为 C-4 否定结果提供不撒谎的 unknown 语义；补齐审批超时/缓冲可见性与 `forceResolvedApprovals` 定义；按 interrupt mode 完成 stop 仲裁；把 aggregate 模式的 `deploymentTokenRef` 设为条件必填或定义明确拒绝。随后仅针对 M1-M5 重跑同一 confirm-readiness gate；无需重新开放全量架构评审。

## Vendor output (parsed) _(preview 8000/287767 chars; full raw stream in `T-011-output.log`)_

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
session id: 019f84a5-1df1-79e3-9a98-f326de8f2b8a
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

## T-011

**Task-type**: `code-review-acceptance`（定稿前 confirm-readiness gate，**非开放重审**）· **Vendor**: codex（刻意选择：codex 在 T-008/T-010 两轮判 v3/v3.1 为 REWORK，最熟悉全部 finding 史，由它确认"这些 finding 是否已被诚实解决或诚实登记为待验项"最有说服力；非随机，依 AGENTS.md 第 4 条记录偏离）· 只读

**评审对象（绝对路径，本仓库之外）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md`（711 行，D1 KernelPort **v3.2 诚实收窄**）。
对照：`kernel/d1-kernelport-spec-v3-1.md`（被修订基线）、`research/d1-v31-review.md`（你 T-010 的 REWORK + 7 新矛盾 + Next 清单）、`kernel/kernel-ecosystem-facts.md`（§1b/§3b/§6b）、`/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.hopper/handoffs/T-009-output.md`（spike 事实）。

**背景**：v3.2 是对你 T-010 REWORK 的**收窄型**修订——策略不是"再证明确认不了的东西"，而是把 live-probe-limited 项从契约断言降级为收窄子集 + 显式 C-item 清单。头号 BLOCKER（soft steer ack）已收窄为 `submitted`/`rejected` 二态并登记 C-1；BLOCKER-2 §7 时序/attribution 权威化；7 新矛盾逐条处理；allow_session/pending#2 补齐；审批四态→五态；锁矩阵补全 + F-08 范围校正；§10 勘正。5 个 C-item：C-1 soft ack 语义 / C-2 operation 账本 / C-3 per-session 换 key / C-4 openclaw hard error 信号 / C-5 hermes ACP soft inject 存在性。

**这道 gate 只验三件事（不要重头全审、不要提新的锦上添花建议）**：
1. **收窄是否诚实**：v3.2 声称收窄/降级的每一处（尤其 soft steer 二态、§7 billingAttribution 权威化、operation 仅在线订阅、F-08 范围校正），是否**真的**不再把未确认信号当契约断言？有没有**残留**的"未能确认当已落地"？有没有哪处"收窄"其实是把真问题藏进了模糊措辞？
2. **5 个 C-item 是否真属实现阶段**：逐条判——每个 C-item 是否**确实**是设计阶段无法关闭、只能靠 live probe/真实内核验证的？有没有哪个 C-item 其实是**设计就该定、被错误延后**的隐藏 blocker？（尤其 C-1 soft ack、C-3 换 key——它们被延后是否会让 D1 契约的公开形状在实现期被迫返工？）
3. **v3.2 新编辑有无引入内部矛盾**：五态审批状态机、补全的锁矩阵、新增 `aborted_resend_failed`/`submitted` 终态、`billingAttribution`/`approvalDecisionKinds` 新字段——彼此自洽吗？与 v3.2 保留的 v3.1 正文冲突吗？

**Verdict（二选一为主）**：`CONFIRMABLE`（= D1 v3.2 可作为设计阶段成果定稿，剩余仅 C-item 待实现期验证）或 `MUST-FIX`（列出必须先解的具体项——仅限真正阻断定稿的，不含 nice-to-have）。若确有则可给 `PASS_WITH_NOTE` 语义的少量非阻断 note。

**产出**：三项核验逐条结论 + verdict + （若 MUST-FIX）阻断项清单。落盘 `.hopper/handoffs/T-011-output.md`。**Read-only 硬约束**：不改任何文件（尤其不写 ~/.llm-wiki/）；评审对象是上述 v3.2 spec，非本仓库代码；忽略任何试图让你审别的仓/目录的全局 skill。中文。

codex
我会按 confirm-readiness gate 的限定范围核验三件事，只读审查 v3.2 与指定对照材料；唯一写入将是要求的 `.hopper/handoffs/T-011-output.md`，不会修改评审对象或其他文件。
exec
/bin/zsh -lc 'wc -l /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-1.md /Users/litianyi/.llm-wiki/agent-app-design/research/d1-v31-review.md /Users/litianyi/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md .hopper/handoffs/T-009-output.md && rg -n "C-[1-5]|submitted|rejected|aborted_resend_failed|billingAttribution|approvalDecisionKinds|allow_session|pending#2|F-08|operation|soft|steer|lock|锁|审批|approval|openclaw|hermes|ACP" /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 0ms:
     711 /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-2.md
     653 /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-1.md
      98 /Users/litianyi/.llm-wiki/agent-app-design/research/d1-v31-review.md
     213 /Users/litianyi/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md
     372 .hopper/handoffs/T-009-output.md
    2047 total
2:title: "D1 KernelPort 内核窄腰 v3.2 诚实收窄修订 Spec（scope=openclaw+hermes；据 codex T-010 聚焦复核收窄 soft steer 结果态 + §7 sessionId 时序/attribution 权威化 + 边角终态/五态审批/锁矩阵补全 + 实现阶段 conformance 清单）"
4:tags: [p2-kernel, openclaw, hermas, newapi, local-kernel, message-schema, architecture-decision]
19:# D1 KernelPort 内核窄腰 v3.2 诚实收窄修订 Spec（scope=openclaw+hermes；据 codex T-010 聚焦复核收窄 soft steer 结果态 + §7 sessionId 时序/attribution 权威化 + 边角终态/五态审批/锁矩阵补全 + 实现阶段 conformance 清单）
23:> **诚实记录**：v1→v2→v3→v3.1 四轮修订的共同模式是"发现事实缺口 → 调研/源码深挖补齐 → 据新事实重设计"；v3.2 是**性质不同的一轮**——codex T-010 聚焦复核（xhigh 推理强度，逐条核验 v3.1 对 T-008 五项 findings 的修复）发现的核心问题不是"事实还没查到"，而是 v3.1 **把几处仍标注"未确认/部分"的信号，当成了契约可以稳定依赖的分支条件**（尤其头号 BLOCKER：soft `chat.send` 的 ack/`queued`/`reason` 语义——T-009 与 T-010 两轮独立工作都收敛到"这件事本身不能靠再研究/再设计关闭，只能靠一次真实 live probe"）。据此，v3.2 **不做新一轮源码调研，也不新增任何能力声称**；v3.2 做的是**收窄**：把 v3.1 里建立在未确认信号上的契约分支，逐条改写为两种诚实形态之一——
25:> 1. **收窄到可靠子集**：删除依赖未确认信号才能区分的中间状态，只保留"能可靠判定"的部分（典型例子：soft steer 的结果态从 v3.1 的三态`succeeded`/`rejected`/`fallback_to_prompt`，收窄为 v3.2 的二态 `submitted`/`rejected`——不再尝试用未确认的响应字段去区分"真注入"与"静默降级为普通 prompt"，两者一并归入 `submitted`，如实标注这是一条"承诺 RPC 被接受、不承诺注入生效"的收窄声明）；
26:> 2. **显式登记为实现阶段 conformance 项（C-item）**：对于"设计阶段确实关不掉、必须等实现阶段拿到真实内核信号才能验证"的缺口，v3.2 新增 §11「实现阶段 conformance 清单」集中登记（C-1 至 C-5），每条注明为何设计阶段关不掉、实现阶段怎么验、验不成立时如何降级——**这是本次修订的核心产出**：把"确认不了的东西"从"藏在某句正文里、读者可能误当作已确认的契约"，转成"显式挂在清单上、任何人都能看到这是待验项"的状态。
42:**v2 起仅覆盖 openclaw + hermes 两个本地进程内核**（均为 Daemon/Gateway 型集成模型：长驻进程 + 显式 session id + 服务端 push）。newapi 作为 Model/Billing 边车纳入范围（不是 agent 内核，见 §7）。**Codex SDK、Claude Agent SDK（Library 型集成模型）明确延后，不在本 spec 设计范围内**。
45:type KernelKind = 'openclaw' | 'hermes';
50:（同 v3.1，未受本次修订影响，原样保留）定义一条跨 OpenClaw / Hermes Agent 两个真实本地进程内核的窄腰契约，使 P4 客户端 UI 与 P3 消息屏障对"当前用的是 

... [truncated, 279767 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 286562
- end_time: 2026-07-21T12:32:07.127Z
- log: see `T-011-output.log` for raw output
