---
requested_selector: null
effective_selector: gpt-5.6-sol
effective_selector_source: policy
selector_kind: unknown
catalog_source_kind: unknown
catalog_source_label: unknown
catalog_observed_at: null
catalog_freshness: unknown
binary_availability: unknown
binary_basename: null
observed_models_json: "[]"
model_attestation_source: null
model_attestation_observed_at: null
resolution_status: unverified
resolution_detail: selector-kind-unknown
diagnostic_code: selector-metadata-cache-missing
adapter_diagnostic_code: none
recovered_output: false
recovered_output_state: no-text
recovered_output_source: none
status: done
phase: done
end_time: "2026-07-28T02:12:30.361Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 403033
adapter_status: success
last_progress_at: "2026-07-28T02:12:30.363Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
---
# T-076 — 批 2 规格「loop 停止落痕」对抗审第 1 轮

## Summary

规格 v1 能把“字段缺失/枚举乱写”变成机械信号，但尚不能可靠记录“实际续了还是停了”，也没有覆盖它声称覆盖的 Stop 与 Auto-Continue 条件并集。现有 14 轮语料中就有一个真实缝隙反例：round 0001 的 feedback 为 negative、无 blocker、无需人确认且下一步可安全 minimal-fix；项目契约因 feedback 非 positive 不允许 auto-continue，而 `loop/SKILL.md` 又要求进入下一修复轮，13 值枚举没有正确停止原因。再叠加可被 `unbounded` 架空的预算支撑、不可证实的 `user-interrupt`、无 successor 核对的 `continued` 与 TH-0017 假绿，本版应返工后再实现。

## Files touched

none（只读评审；仅按任务协议写本交付物 `.hopper/handoffs/T-076-output.md`，未改评审对象、harnessloop 子模块、背景文档或 `.harnessloop/` 语料。）

## Acceptance verification (9/9)

### 1. §2.2 枚举是否完备

**FAIL。存在已经发生、13 值中没有正确值可填的停止。**

具体反例是 `.harnessloop/goals/20260716-001-setup-wizard/rounds/0001/decision.md:3-5,46-52`：

- `Feedback: negative`；
- `Blocker type: none`、`Recovery eligible: yes`；
- 下一动作是 `minimal-fix`；
- `Human confirmation required: no`、`Safe without user input: yes`。

项目契约 `.harnessloop/state/control-contract.md:7` 只允许 `feedback=positive` 自动续，因此该轮不满足契约 Auto-Continue；但 `loop/SKILL.md:557` 对 negative/neutral 且不需人决策明确要求“propose or enter”下一 investigation/fix/rollback。它既不是 goal achieved，也不缺人、访问、写安全、数据契约或阈值；evidence、environment、handoff、strict 人闸、预算和用户打断同样不成立。正确词应至少是 `feedback-not-auto-continuable`（若裁决它应停）或根本不应停（若以 loop step 7 为准），不能冒写已有 13 值。

枚举还有两类未覆盖的真实 profile Stop：`control-contract-profiles.md:38-42` 的 `Model/effort mismatch` 与 strict 下可阻止任何安全推进的 `external-system-unsafe`，二者都不能诚实地压进 `environment-selfcheck-failed` 或 `write-safety-unconfirmed`。此外，14/14 实践里的“agent 收盘后等下一次 continue”，在没有用户主动打断、也没有已声明有限预算时，同样没有合法枚举；若目标是记录偏离，需要 `unjustified-stop`/`protocol-deviation` 这类可记录但判红的值。

证据命令：

```text
$ find .harnessloop/goals -path '*/rounds/*/decision.md' -type f | wc -l
14
$ rg -l --hidden --glob 'decision.md' '^- Feedback: negative' .harnessloop/goals | wc -l
1
$ rg -l --hidden --glob 'decision.md' '^- Loop continuation:' .harnessloop/goals | wc -l
0
```

### 2. §3 “有契约支撑”的核对能否被架空

**FAIL。无需空块，使用规格自身允许的 `unbounded` 就能骗过。**

最小反例：

```markdown
## Round Budget

- Max consecutive auto-continued rounds: unbounded
- Budget checkpoint action: stop-and-report
- Cost budget: not-used
```

配一条 `Loop continuation: stopped: budget-checkpoint`。按 §3:117-120 的规则，块存在且 Max 非空，因而“有支撑”；但 `unbounded` 明确表示轮数永不到点，成本又 `not-used`，不存在任何可达到的 budget checkpoint。即便把 Max 写成 `3`，规格也没有要求核对前面是否真的连续续了 3 轮。L3（规格 :156）只覆盖“无 Round Budget 块”，没有覆盖 `unbounded`、非正整数、尚未达到或计数重置语义。

`profile-requires-confirmation` 同样缺少可实现的规范解析面：当前项目值是中文自然语言（`.harnessloop/state/control-contract.md:11`），profiles 是英文长句（`control-contract-profiles.md:19`），规格未定义 canonical value、重复字段、首项/末项胜出或否定词解析。一个简单的 `required` 子串匹配甚至会命中 `not required`。因此“真有支撑”是过度声称；当前最多能核对“有一段非空文字”。

### 3. `continued` 是否沦为装饰

**FAIL（字段有审计价值，但 v1 的不可验证边界自我设限过度，且写入时序未闭合）。**

规格 :50-51 定义 `continued` 为“本会话内实际开启下一轮”，而现行 Loop Continuation 顺序是先跑 gate、写本轮 decision，再在 step 6-8 决定下一步（`loop/SKILL.md:549-558`）。若关闭本轮时先写 `continued`，它还是未来承诺，不是已发生事实；若等下一轮创建后回写，首次 gate 会先看到字段缺失，且规格没有定义回写、重跑 gate 和 closed-round 可变性的顺序。

“同一会话”确实无法仅凭项目树证明，但至少可以廉价证伪：`continued` 必须带 `successor_round`，且该 round 目录存在、序号/goal/predecessor 对得上；最高轮写 `continued` 却无 successor 必须红。v1 的 L5 反而要求裸 `continued` 直接通过（规格 :158），所以 agent 可以实际停止、写 `continued`、保持 0 违规。书面断言不是零价值，但在没有最小物证和事件时序时不足以称为“落痕”。

### 4. §4 迁移是否 E1-safe

**NOTE。语义上可接受，但 v1 的论证理由不准确，必须把它明定为 schema migration。**

`decision.md` 不在 Rule A/B 的 artifact 扫描域；源码也明确 Rule A 只看 `evidence/`/`reviews/`（`loop/SKILL.md:477`）。但它并非“不被检”：`verify_protocol.py:2566-2602` 读取其 Verdict/Residuals/Review 字段，新规则还会直接读取 `Loop continuation`。当前 14 份 decision 全无该字段；若先启用 L1，它们会出现 14 条 missing，再靠回填恢复 0，因此字面上确实是“改门正在读取的文件转绿”。

这不等于篡改证据：`historical-unrecorded` 不改变旧 feedback、verdict、finding 或引用对象，只诚实声明旧 schema 当时没记录，和修改历史评审结论不同。可接受条件是把顺序写死为“迁移器只给 activation 之前的 rounds 添加唯一固定值 → 核对除该行外字节不变 → 再启用 gate”，或由 gate 按版本/cutoff 原生识别 legacy；不能仅以“decision 不是评审产物”带过。`historical-unrecorded` 还应只在迁移工具中可写，新轮出现即违规，而不只是散文禁止。

### 5. §2.5 收窄 continue 是否破坏既有用法

**FAIL。按“仅记录在案的停止之后”字面实施会同时切断 legacy 与异常恢复。**

当前最新轮 `.harnessloop/goals/20260718-002-agent-app/rounds/0010/decision.md:68` 明写“下一 continue 开 SG-10”；迁移后它只有 `historical-unrecorded`，既不是 `stopped:<reason>`，也不是 `continued`。用户按现有入口调用 `$harnessloop-continue` 时，v1 没有定义兼容分支。更严重的反例是宿主/进程在 round 收口后、stop 字段写入前异常终止：规格 §6 又显式排除轮内中止（:171），下一会话恰恰需要 continue 救援，却因“没有记录在案的停止”被新输入契约排除。

应保留 `resume/advance` 入口兼容：最近值为 backed `stopped:*` 时正常重入；为 `historical-unrecorded` 或字段缺失时允许 recovery 但发 legacy/unrecorded anomaly；为 `continued` 且 successor 已存在时转到该 successor，而不是只报一句矛盾后继续任意推进。例行推进不再推荐人工调用可以是文档语义，不能成为无恢复分支的前置条件。

### 6. 本规格是否解决真问题

**FAIL。它解决了“字段有没有”，尚未解决“停止有没有真实落痕”，因此不能预期改变 14/14 的实践。**

两个确定性绕过均被 v1 明确放行：

1. agent 每轮实际停止，写 `stopped: user-interrupt`；该值没有 trigger/reference 支撑检查，L2/L3/L4/L5 全通过。
2. agent 每轮实际停止，写 `continued`；L5 要求值本身通过，且 v1 不核对 successor。

所以可以构造“仍然 14/14 停止 + 0 违规 + coverage 显示 14 次用户打断”或“14 次 continued”的绿灯。`loop_stops_by_reason` 能让统计异常更易被人发现，是有用的观测底座，但不是足以改变行为的机制。最低充分条件见独立章节“落痕是否足以改变实践”。

### 7. §1.1 内部不一致是否属实；13 值是否覆盖两套并集

**FAIL（内部不一致属实；“13 值覆盖并集”不属实）。**

独立核对结果：

- `loop/SKILL.md:560-567` 的确是六个 `Stop only when` 条件。
- `control-contract-profiles.md:15-19` 的确是 feedback/evidence/environment/handoff/human-confirmation 五个不同构的 Auto-Continue 字段。
- 二者不是互补集合：Auto-Continue 条件失败不总等于必须停止。`loop/SKILL.md:557-558` 对 negative/neutral 或 runtime-recoverable blocked 明确给出可自主进入的恢复路径，而 profiles 的 `Feedback class`（尤其 standard 只接受 positive）会否掉 auto-continue。profiles 自己另有真正的 Stop Conditions（`:34-43`），v1 只比较 Auto-Continue 表也不完整。

13 值实际覆盖了协议六项，加上 evidence/environment/handoff/strict confirmation 四项，再加 budget/user/historical 三项；漏掉五个 Auto-Continue 字段中的 `Feedback class`。真实缝隙就是 round 0001：negative + blocker none + no human + safe minimal-fix。按契约它不能 auto-continue，按 loop step 7 它应 enter 下一轮；若选择停，没有 reason，若选择续，又违反 standard 的 allowed-when。必须先裁决优先级，再设计枚举；不能用枚举掩盖矛盾。

### 8. §3 能/不能清单是否诚实

**FAIL。“能”部分把弱存在性包装成支撑，“不能”部分又漏掉了多项廉价可证伪检查。**

可确定做到但 v1 自我放弃的检查包括：

- `budget-checkpoint`：要求有限正整数 Max，并从前序 `continued` 事件计算连续轮数；`unbounded`/未达到必须 unbacked。
- `continued`：要求 successor round 存在并反向引用当前 round。它不能证明 same-session，但能抓住“无下一轮却自称已续”。
- `evidence-health-failed`：从 `state/evidence-index.md` 的 `Artifact health` 与 acceptance relevance 至少核对声明支撑。
- `open-handoff-blocking`：对 Harnessloop 自有 round handoff 解析 `Status` 并排除 `archive/`；跨 `.hopper/handoffs` 的汇入边界需另定，但这不是放弃自有 handoff 核对的理由。
- `environment-selfcheck-failed`：至少可核对 `state/environment.md` 的声明值不是 pass；语义是否可信是 TH-0017 的另一层。
- `historical-unrecorded`：依据 activation/cutoff 禁止新轮使用，而不只是计数。

真正无法由当前仓库单独证明的是“用户是否真的打断”“agent 是否因某心理原因偷懒”“successor 是否在同一宿主会话启动”。规格应把“证明真实原因”拆成：可派生事实、可要求 trigger reference、只能人工复核三层，而不是一概写成不能核对。

### 9. 与 TH-0017 的联动

**FAIL。`environment-selfcheck-failed` 不会普遍形同虚设，但对 TH-0017 已证明的这类失败，在当前项目中确实是死值。**

现场复跑：

```text
$ python3 -B harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py --project . --json
"complete": true
"gate_blocking": false
"field_todo_count": 12
```

同一份 `.harnessloop/state/environment.md:17,31,37,41` 明写无独立 runtime probe/残余风险，`:11,33-35,47-49` 有 5 个 TODO，`:45` 却是 `Pass/fail: pass`。`check_setup.py:513-542` 又把 TODO 非空值计作 filled，于是 `complete=true + TODO=12` 静默穿过 continue 只在 `complete=false` 时展示的 warning 分支（`harnessloop-continue/SKILL.md:24,28`）。Auto-Continue 看见的是 `pass`，实际未验证的环境不会产生 `environment-selfcheck-failed`，所以新增枚举捕捉不到恰好促成它立项的假绿。

v1 不应声称“不依赖批 1 的任何产出”后又把该枚举当可靠条件。最低修订是：环境状态采用 `pass | fail | unknown | stale` 的机器值，TODO/probe 缺失不能归 pass；停止原因相应改为能覆盖 `unknown/stale` 的 `environment-selfcheck-unhealthy`，并规定 TH-0017/EV-K（以及委派场景的 delegation health）修复前，此原因只能作为未验证声明，不得算 backed。

## 落痕是否足以改变实践

**结论：v1 的落痕不足以改变实践，但不应废弃整个方向；它是观测底座，不是完成态。**

要让“没有继续”既可见又不越权强迫 agent，至少需要以下闭环：

1. 把字段改成事件记录并解决时序：`continued` 必须带 `successor_round`；`stopped` 必须带 `reason` 和可用时的 `trigger_ref`。事件发生后再写，并在下一次 status/continue/CI 最迟补跑 reconciliation gate。
2. 允许 `unjustified-stop`/`protocol-deviation` 被诚实记录，但它必须产生违规；否则真实偏离没有词汇，只会逼 agent 说谎。
3. 对可派生原因做支撑核对：有限预算及实际计数、successor、evidence health、environment 状态、handoff 状态、goal 状态。`user-interrupt` 至少要引用宿主可见的用户消息/event；没有事件源时标为 unverifiable，不算 backed。
4. 先裁决 feedback/profile/loop step 7 的优先级，并把 profiles 的完整 Stop Conditions（含 model/effort mismatch、external-system-unsafe）纳入 taxonomy。
5. coverage 除原因分布外增加 `continued_with_successor`、`continued_without_successor`、`stops_backed/unbacked/unjustified` 与按 profile 的 continuation rate。lite/standard 在 positive、健康且无 backed stop 的末轮，应在下一次门运行时明确报 anomaly；这不是强制宿主继续，而是让“不续”不能保持绿灯。

有了这些，协议仍不能控制 agent 的采样/宿主生命周期，却能在下一次可观察时点确定地抓住“自称续但没 successor”和“停了但无可支持原因”。这才会把偏离成本从“多写一个可随便填的字段”提高到“留下不可伪装为正常的红/异常记录”。

## Decisions / deviations

- 以工作区当前 `docs/loop-stop-record-spec-20260728.md` v1 与 harnessloop submodule `b389eaca1427af8e88248259e350d02b465434e4` 为评审基线；与任务指定 `b389eac` 一致。
- 将“Acceptance verification (9/9)”解释为九个评审靶子均已给出确定判定与反例，不表示九项均通过。
- 假设审计报告所称 14/14“由 continue 人工推进”可信；不借宿主 transcript 反推每轮精确 session 边界。核心 FAIL 均有项目树/协议文本的独立反例，不依赖该假设。
- 未修改规格或实现；所有修复内容仅为下一版建议。

## Open questions

- `Feedback class` 不满足时，权威语义究竟是“停止”还是按 loop step 7/8 自动开恢复轮？v2 必须给唯一优先级。
- `user-interrupt` 的权威事件 ID/消息引用由哪个宿主层提供？若没有来源，应否只允许 `unverifiable-user-interrupt` 并判 NOTE/违规？
- “open handoff”只指 Harnessloop round 内 handoff，还是也汇入 `.hopper/handoffs`？在核对 `open-handoff-blocking` 前必须确定命名空间。

## Verdict

REWORK

## Next recommendation

先出 v2，不进入实现。v2 至少应：补齐 feedback/model-effort/external-unsafe/unjustified taxonomy；把 Round Budget 改成可解析 schema 并验证有限值与实际计数；为 `continued` 增 successor 物证和写入/reconciliation 时序；为所有可派生 stop reason 增 backing；把 continue 的 legacy/异常恢复分支写清；将 TH-0017 修复设为 environment-backed 判定的前置或显式降级。完成后用本文 round 0001、`unbounded budget`、假 `continued`、假 `user-interrupt`、`complete=true+TODO=12` 五个 fixture 做第二轮异构对抗审。

## Vendor output (parsed) _(preview 8000/357309 chars; complete parsed output is available through `hopper-dispatch --result T-076 --full`)_

````
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
session id: 019fa678-975c-76c3-abbb-ba77f648962b
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

## T-076（批 2 规格「loop 停止落痕」— 对抗审第 1 轮）

**Task-type**: `code-review-adversarial` · **只读评审，不改任何代码/文档**

**评审对象**：`docs/loop-stop-record-spec-20260728.md`（v1）。
**背景**：`docs/harnessloop-runtime-evals-autonomy-audit-20260728.md` GAP-4 与附录 C；
`.harnessloop/meta/evolution-issues/0023-loop-stop-leaves-no-trace.md`；
两轮审核核实产物 `.hopper/handoffs/T-074-output.md` / `T-075-output.md`。
**源码**：harnessloop submodule `b389eac`（v0.26.0）。

**评审语境**：这是**自主性机制**的规格，目标是让「loop 没有继续」这件事留下痕迹。
它刻意不强制自续（协议管不了 agent 行为，只能管记录）。

**逐条回答 §7 的 6 个靶子**，其中第 6 个允许判定本规格无效。另加三项：

7. **§1.1 那条协议内部不一致**（Stop 条件 vs Auto-Continue 条件两套不同构）是否属实？
   请独立核对 `loop/SKILL.md:560-567` 与 `control-contract-profiles.md:15-19`，
   并判断 §2.2 的 13 值枚举是否真的覆盖了两套的**并集**——构造一个落在缝里的真实停止。
8. **§3 的能/不能清单是否诚实**：有没有它声称"能核对"、实际核对不了的？
   有没有它声称"不能"、其实可以廉价做到的（那属于自我设限）？
9. **与 TH-0017（环境自检 pass 语义）的联动**：枚举里的
   `environment-selfcheck-failed` 依赖 environment self-check 的判定，而 TH-0017
   已证明该判定当前可假绿（`Pass/fail: pass` 与 5 个 TODO 并存、check_setup
   complete=true+todo=12 静默穿门）。这会不会让这个枚举值形同虚设？

**验收**：逐项 PASS / FAIL / NOTE + 具体反例构造，不接受"可能存在风险"。产物落
`.hopper/handoffs/T-076-output.md`，含 `## Verdict`、`## Files touched`（应为 none）、
独立成节的 `## 落痕是否足以改变实践`。

codex
我会按只读对抗审执行：独立核对规格、协议源码、审计背景与两轮既有核实，并只生成指定评审产物 `.hopper/handoffs/T-076-output.md`，不改评审对象或任何源码。
exec
/bin/zsh -lc "sed -n '1,260p' docs/loop-stop-record-spec-20260728.md && sed -n '520,600p' loop/SKILL.md && sed -n '1,120p' control-contract-profiles.md" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 exited 1 in 0ms:
# loop 停止落痕 + 轮次预算 + 档位分层 — 规格 v1（2026-07-28）

> 对应 **TH-0023**（loop 停止不落痕）。批 2 独立小规格，**不依赖批 1 的任何产出**。
> 起因：`docs/harnessloop-runtime-evals-autonomy-audit-20260728.md` GAP-4，
> 经 T-074 补 O-2/O-4、T-075 补 O-8 档位分层后定稿裁决（附录 C.4 批 2）。
>
> 状态：**规格草案，待异构对抗审**。实现未开始，机械门在 v0.26.0。
> 授权：main-session ruling under user delegation 2026-07-28（附录 B）。

## 1. 问题

协议**明文要求**单会话多轮自续，实践 **14/14 轮**全部停在等人——而这个偏离
**不留任何痕迹、不被任何机制标红**。

证据：
- `loop/SKILL.md:556` step 6：positive 且 goal 未达成 → `continue to the next subgoal
  or task`。`:560-567` "Stop only when" 六条穷举，**不含**「等用户敲 continue」。
- 本项目 `state/control-contract.md` 的 Auto-Continue 段逐字写着
  「不需要——满足以上条件时自动进入下一子目标」（standard 档），且 14 轮里
  绝大多数轮次 feedback=positive、无 open handoff 阻塞、environment self-check=pass
  ——**契约允许自续，实际没有自续，无人发现**。
- 协议无停止记录机制：`decision-template.md` 无停止原因字段；self-audit 确定性信号
  清单不含停止事件；coverage 无停止计数。
- `state/current.md` 的 `Next proposed action` 一律以「下一 continue 开 SG-X」收尾。

**偏离零成本 → 实践必然漂移。** 这是「绿灯≠真守门」的自主性版本：协议文本许诺了
自续，没有 teeth 保证它。

### 1.1 顺带暴露的协议内部不一致（本规格必须一并处理）

「协议的 Stop 条件」与「契约的 Auto-Continue 条件」是**两套**、且不同构：

| | 出处 | 内容 |
|---|---|---|
| 协议 Stop 条件 | `loop/SKILL.md:560-567` | goal 达成 / 缺人输入 / 缺访问事实 / 写安全未确认 / 数据契约不可满足 / 阈值不可评估 |
| 契约 Auto-Continue 条件 | `control-contract-profiles.md:15-19` | feedback class / evidence health / environment self-check / open handoffs / human confirmation |

一个「evidence health 不合格」或「有 open handoff」导致的停止，**合法**（契约不允许
自续），但它**不在协议的 Stop 清单里**——按 SKILL.md 字面读，它是非法停止。
枚举必须同时覆盖两套，否则合法停止会被新机制误判为违规。

## 2. 设计

### 2.1 `decision.md` 新增 `Loop continuation:` 字段

```
- Loop continuation: continued | stopped: <reason> | historical-unrecorded
```

`continued` 的含义**只有一个**：本会话内实际开启了下一轮（或 goal 已完成前的最后
一次推进）。**不是**「本可以继续」。

### 2.2 停止原因枚举（覆盖两套条件 + 三个此前静默的原因）

| 原因 | 来源 | 说明 |
|---|---|---|
| `goal-achieved` | 协议 Stop | goal 完成，正常终止 |
| `missing-human-input` | 协议 Stop | 需要业务/风险/验收判断 |
| `missing-access-facts` | 协议 Stop | 缺端点/凭证/权限/工具事实 |
| `write-safety-unconfirmed` | 协议 Stop | 需要写但缺 dry-run/回滚/确认 |
| `data-contract-unsatisfiable` | 协议 Stop | 数据契约无法满足 |
| `threshold-unevaluable` | 协议 Stop | 验证阈值无法评估 |
| `evidence-health-failed` | 契约 Auto-Continue | 证据健康度不满足自续条件 |
| `open-handoff-blocking` | 契约 Auto-Continue | 有未关闭/阻塞的 handoff（T-074 O-4） |
| `environment-selfcheck-failed` | 契约 Auto-Continue | 环境自检不为 pass（与 TH-0017 联动） |
| `profile-requires-confirmation` | 契约 Auto-Continue | **strict 档**逐 subgoal 人闸（T-075 O-8） |
| **`budget-checkpoint`** | **新增，合法** | 达到契约声明的轮次/成本预算，主动 checkpoint |
| **`user-interrupt`** | **新增，合法** | 用户主动打断 |
| `historical-unrecorded` | 迁移专用 | 本规格生效前的轮次，当时未记录——**不得**用于新轮 |

**`budget-checkpoint` 与 `user-interrupt` 是本规格的核心产出之一**：它们此前是
*静默逃逸*——真实发生、协议无词汇、于是不留痕。给它们合法枚举值，等于把「实践里
真正发生的停止」从暗处搬到台面，而不是假装它们不该发生。

### 2.3 `control-contract.md` 新增 `Round Budget` 块

```
## Round Budget

- Max consecutive auto-continued rounds: <int> | unbounded
- Budget checkpoint action: stop-and-report | ask-user
- Cost budget: <说明> | not-used
```

**诚实标注**：成本维度**不作为主判据**。`round_cost.py` 依赖本机 transcript 窗口，
本项目 14 轮中多数轮次至少一个 cost 字段为 `unavailable`（子代理/回写会话无窗口，
`loop/SKILL.md:552` 本就允许记 unavailable）。**轮数是可靠维度，成本是提示性维度**
——规格不假装能用一个系统性失真的信号做硬约束（T-074 O-2）。

### 2.4 档位分层：自续词汇不得越过 profile

- **lite / standard**：满足契约 Auto-Continue 条件即应自续；停止必须落痕。
- **strict**：`control-contract-profiles.md:9,:60` 明文要求逐 subgoal 人工确认、
  且不允许连续无人轮。strict 档下 `stopped: p

... [truncated, 349309 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 403033
- end_time: 2026-07-28T02:12:30.361Z
- log: see `T-076-output.log` for raw output
