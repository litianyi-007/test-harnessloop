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
end_time: "2026-07-27T19:42:46.299Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 336895
adapter_status: success
last_progress_at: "2026-07-27T19:42:46.301Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
---
# T-075 — runtime-evals / 自主化审核独立参照审

## Summary

修订版的 7 个主 GAP 与“散文概念已有、机械判定链失明”的总判断仍成立，但本轮独立复核不支持把 O-1 的“固定执行拓扑”升为 GAP-3 的通用前置，也不支持把 D1 在没有迁移边界时称为“从第一天”可落地。报告尤其漏掉了 delegation probe 的语义假绿，以及多系统 eval 的依赖/并发/同一 attempt 语义。加上正文仍保留已宣称撤回的 B2a 建议，修订版需要一次定向返工。

## Files touched

none（只读评审；仅按任务协议写本交付物 `.hopper/handoffs/T-075-output.md`，未改评审对象、harnessloop 子模块或 `.harnessloop/` 语料。）

## Acceptance verification (4/4)

1. **PASS — 三个争议点均已独立仲裁。** 详见“争议点仲裁”；基线命令 `git rev-parse HEAD && git -C harnessloop rev-parse HEAD` 分别为 `4ea68135668c47e261a90633d038addd803b6fc6` 与 `b389eaca1427af8e88248259e350d02b465434e4`。
2. **PASS — O-1..O-10 已逐条按指定三类复判。** 详见“O-1..O-10 复判”；特别结论是 O-2 属 GAP-4 的观测细节、O-4 属 EV-F 的状态枚举细节，二者都不是独立前置。
3. **PASS — 已给出三方均遗漏的新卡点。** 详见独立章节“## 三方漏网之鱼”；其中环境自检问题有现场反证：`check_setup.py --project . --json` 返回 `complete: true`，但同一输出仍有 `field_todo_count: 12`，而 `state/environment.md` 明写“无独立运行时探针”却自判 `pass`。
4. **PASS — 附录 A.3 四问均给出独立推荐。** 详见独立章节“## A.3 推荐”，每项均含一句话理由。

## 争议点仲裁

### A. 资产 #3：reference-roots 能否“同形扩展”

**裁定：T-074 对“不能照搬现有代码/判定机制”的降级正确，但“服务端点没有同构物”降得过头；更准确的说法是“控制面同形，探针执行器异构”。**

源码显示 reference-roots 的可复用形状并非只有抽象纪律：

- tracked 声明只回答身份/意图，本机 gitignored binding 只回答位置：`verify_protocol.py:385-425`，两个模板分别见 `reference-roots-template.json:1-18`、`reference-roots-local-template.json:1-6`。
- 每次 gate 重新绑定并判 `available`，不可用 fail-closed 且进入 coverage：`verify_protocol.py:1314-1348,2653-2673,2724-2733,2764-2765`。
- 当前 `expect_present` 的具体实现确实只是目录内路径存在性：`verify_protocol.py:1251-1259`；`samefile/stat` 还承担 alias 碰撞和目录身份判断，而不是服务健康语义：`:1262-1268`。

因此服务域完全可以定义同一控制面位置上的“健康/身份断言”，例如 `GET /health` 期望状态码、JSON 字段、服务 identity/version；它在架构位置上就是 sentinel 的同构物。但 HTTP/TCP 探针必须另行定义 method、timeout、TLS、鉴权、重试、副作用等级、响应大小和身份断言，不能复用 `_exists_as`/`samefile`，也不能把一次 liveness 直接等同于后续 eval 的可用性。

对报告的具体修订建议：把 `docs/...audit...md:222-226` 的“服务端点没有同构物”改成“没有可直接复用的文件系统判定器”；保留声明/本机绑定、fail-closed、coverage 这些**机制骨架**，另建 service probe adapter。报告正文 `:74-77` 原有“模式扩展”其实比附录的绝对降级更接近这一裁定。

### B. D0/D1/D2：D1 是否能从第一天硬起步

**裁定：D1 的 fail-closed 方向正确，但不能无版本、无 opt-in 地作用于全部存量 goal；修订版缺失迁移语义，而且正文仍与附录自相矛盾。**

证据：

- 现有 `thresholds-template.md:11-19` 没有 stable ID；Runtime 表甚至没有 `Applies to`/due 字段。报告 D1 却要求“到期 threshold-id”全 ran（报告 `:303-307`），其输入集合目前无法机械求出。
- 本项目 active goal 的 thresholds 混有历史、已完成、defer、未来批次与每轮规则（`.harnessloop/goals/20260718-002-agent-app/thresholds.md:17-38`）；工作区不存在任何 `eval-results.json`。若按“有 thresholds 行即启用”，首日不是把所有历史轮判死，就是迫使实现者临场猜哪些行到期。
- 现有协议已有明确先例证明迁移必须显式：B2a 对旧 round 是非零迁移，`loop/SKILL.md:455` 明写旧轮预期需要修；不能把这一选择隐含进 rollout。
- 更严重的是，报告主文 `:124-125` 和 EV-D 表 `:264` 仍写“先入账后硬门”，而 A.2 `:294-307` 声称已经撤回。当前文档同时给出两套相反指令。

现实的迁移应是：

1. D0 增加 schema、stable threshold ID、权威 due-set 规则和 `eval_gate_version`，只做 shadow/advisory。
2. 对新 goal 默认启用；对 active legacy goal 由一次显式 migration manifest 把每个 threshold 标为 `due | future | retired | historical`，记录 `activation_round`，不追溯改判旧轮。
3. 只有 opt-in 后的 round fail-closed；一旦某 eval 属本轮 due，不能用任意 `deferred` 换 positive。
4. D1 可以作为迁移期的“ran 完整性门”，但它不满足用户已裁决的完整硬门；“ran=true, pass=false”仍必须在同一次启用中阻断 positive，亦即最终 acceptance 至少要 D2。

### C. O-1：eval 执行者是否是一等前置

**裁定：问题真实，但 T-074/修订版把“执行拓扑”与“结果可信度/授权来源”混为一谈，升为 GAP-3 的通用前置属于过度定性。**

现有协议并非完全没有执行拓扑：

- 项目可在 cost-context-policy 中自定义 execution delegation matrix，协议默认已区分 connectivity、acceptance testing 与 round acceptance：`loop/SKILL.md:408-419`、`cost-context-policy-template.md:38-49`。
- handoff 已能携带 tool/system、read/write scope、account role、credential name、verification method 与 failure handling：`handoff-template.md:8-29,38-50`。
- connectivity skill 已把具体命令、参数、权限、凭证引用和 write-safety 作为执行前置：`harnessloop-connectivity/SKILL.md:14-28,32-43`。

因此核心协议可以保持 executor-neutral，由项目选择 main session、受限子代理或外部 runner。机械门真正必须知道的是：`executor/provenance`、实际 command/plan digest、cwd/environment/system binding、授权引用、exit/result、时间窗和 evidence digest；这些属于 GAP-2 的结果 schema 与 GAP-5 的授权联结。只规定“谁跑”也无法阻止一个执行者伪造 `ran=true`，正如当前机械门明确不判断证据是否真的支持结论（`loop/SKILL.md:459-468`）。

建议把依赖图改为 `EV-C(result+provenance) + EV-E(authorization) + EV-I(due-set) → EV-D(gate)`；EV-H 保留为**项目级执行策略/委派适配**，仅当选用 delegated/write-capable runner 时成为条件前置，而不是所有 hard-gate 项目的普遍前置。

## O-1..O-10 复判

| 项 | 独立定性 | 裁定与源码证据 |
|---|---|---|
| **O-1 eval 执行者** | **已被原报告覆盖只是换了说法（且被夸大）** | “执行产生什么可信记录”是 GAP-2/3，“允许什么写”是 GAP-5；main/subagent 的默认选择可由 `cost-context-policy` 矩阵自定义（`loop/SKILL.md:408-419`）。应保留 provenance 契约，不应把固定 topology 设为 GAP-3 普遍前置。 |
| **O-2 round_cost** | **已被原报告覆盖只是换了说法** | GAP-4 已写上下文/成本压力、round 预算与合法 checkpoint（报告 `:138-150`）。协议本身允许非 Claude 或脚本失败时记录 unavailable（`loop/SKILL.md:552`），脚本也声明 multi-session transcript 支持（`round_cost.py:21-24`）；实践中 14 轮有 10 轮 transcript window unavailable、11 轮至少一个 cost 字段 unavailable，说明观测质量差，但不妨碍用轮数/上下文阈值自续。它是 EV-F 的预算信号细节，不是 runtime eval 硬门前置。 |
| **O-3 委派矩阵与写边界** | **已被原报告覆盖只是换了说法** | GAP-5 已抓预授权缺口；handoff 不是“无字段”，已有完整 Tool And Access Contract（`handoff-template.md:24-29`），真正缺的是 machine-enforced authorization ID、资源域与 cleanup outcome。合并进 EV-E/结果 schema 即可。 |
| **O-4 handoff 门闩** | **nice-to-have** | profile 已明确 lite/standard/strict 的 open-handoff 条件（`control-contract-profiles.md:15-19`），loop 也在继续前先 archive closed handoffs（`loop/SKILL.md:549-556`）。未关闭的阻塞 handoff 阻止自续是预期安全行为；EV-F 只需把 `open-handoff` 作为 stop-record 原因，非独立前置。T-074 同时援引 `.hopper/handoffs` 与 round 内 `handoffs/`，但没有先定义两者如何汇入同一个 open/closed 状态。 |
| **O-5 check_setup 与新声明文件** | **nice-to-have** | `FILES_ORDER` 的确只有五文件且 gate-blocking 仅三文件（`check_setup.py:72-80,207-218`），但 external-system 配置可由 active due eval 条件触发，而不必让所有项目 setup 全局阻塞。建议 check_setup advisory + active-goal conditional gate；独立 EV-J 是运维体验，不是 hard-gate 必要依赖。 |
| **O-6 intake 导入旧 eval** | **nice-to-have** | continue 已把 intake 作为单独入口并要求 gate/review（`harnessloop-continue/SKILL.md:22,38`）。用户已裁决的主线是单会话 active loop；旧证据导入、新鲜度映射可 defer，不能称当前自主化前置。 |
| **O-7 channels/connectivity 中间层** | **已被原报告覆盖只是换了说法** | 修订正文已经在 GAP-1 明写模型侧 inventory/探活存在而代码解析为零（报告 `:60-67`）；源码也分别定义 inventory-only 与 declared-check-only（`harnessloop-channels/SKILL.md:22-29`、`harnessloop-connectivity/SKILL.md:32-41`）。这是 EV-B 设计输入，不是新增 blocker。 |
| **O-8 strict 与自续冲突** | **real-blocker（仅对 strict 自续承诺）** | strict 明文要求下一 subgoal 人工确认，且不允许连续无人轮（`control-contract-profiles.md:9,15-19,60`）。若产品宣称 strict 也能单会话连续自续，必须先裁决；若明确 strict 选择安全优先而不承诺无人自续，则是合法 profile 行为。修订版把它并入 EV-F 是对的。 |
| **O-9 scope-lock/thresholds 双登记** | **real-blocker** | `scope-lock-template.md:21-24` 与 `thresholds-template.md:11-19` 都声明验证，但无共同 ID、无权威 due-set。D1 的“缺 ran 不得 positive”在 EV-I 解决前无法计算；依赖图应是 EV-I → D1/EV-D，而不是姊妹项可晚做。 |
| **O-10 gate 不执行命令** | **nice-to-have（必要边界说明，不是缺陷）** | 机械门现有边界已明确“machine-checkable rules”与模型判断分层（`loop/SKILL.md:440-468`）。EV-D 需要写清 ledger verifier 不等于 runner，但这不构成独立演进项，也反向说明 O-1 不必规定唯一执行拓扑。 |

**O-2/O-4 专项结论**：两者都可以在 EV-F 中顺手处理。O-2 只在项目把“金额预算”设为停止条件时升级为必要数据源；O-4 是已有 profile 条件的可观测化，不是新的自主化前置。

## 三方漏网之鱼

### M-1（real-blocker）：environment/delegation 自检只有“填充度”，会把无 probe 的状态判绿

当前实例直接构成反例：

- `state/environment.md:17,31,37,41` 四次承认 subagent 没有独立 runtime probe，`:33-35,47-49` 仍有 TODO，`:45` 却写 `Pass/fail: pass`。
- delegation skill 规定 observed model/effort 不可验证时必须为 `unknown`、不得标成功（`harnessloop-delegation/SKILL.md:29-35,65-71`）。
- `check_setup.py` 只判断非空/不等于模板，TODO 也计入 filled（`:513-542`）；实跑却返回 environment `filled 21/21`、整体 `complete: true`、同时 `field_todo_count: 12`。
- standard auto-continue 只看 environment self-check=`pass`，strict 还要求实际 delegation 验证（`control-contract-profiles.md:17,41-42,57`）。continue 又只在 `complete=false` 时承诺 surface TODO warning（`harnessloop-continue/SKILL.md:24,28`），因此当前 `complete=true + TODO>0` 会静默穿过 setup 分支。

这会让 delegated runtime eval 在能力、scope、输出路径或实际模型未验证时仍获得“环境 pass”。修复至少需要 machine-readable `delegation_health`、probe artifact/digest、`verified_at`、会话/环境 fingerprint 与风险级适用范围；无 fresh probe 时只允许 main-session fallback 或 read-only conservative 模式，不能用自由文本 `pass（有残余）`满足 hard gate。

### M-2（real-blocker）：多系统 eval 没有依赖 DAG、并发锁与组合结果语义

`thresholds-template.md:11-19` 只有平面行；`data-sources-template.md:16-24` 只有单系统声明；connectivity 只说从各自 verification method 建 plan（`harnessloop-connectivity/SKILL.md:34-41`），没有 `depends_on`、`parallel_group`、`lock/resource key`、barrier、failure propagation 或 compensation。

这会产生三类假绿：

1. B 探针依赖 A 建好的测试资源，却被并发启动，B 的 transient fail 被错误当产品 fail；
2. A/B 各自在不同时间、不同配置快照下 pass，ledger 只见“两项都 pass”，却从未形成一次组合成功；
3. 两探针互相依赖形成 cycle，agent 临场任选顺序，结果不可复现。

建议 eval plan 使用 DAG：stable eval ID、`depends_on`、并发组、共享资源锁、timeout/retry policy、失败传播、cleanup/compensation；cycle 必须 `contract-insufficient`，或显式建一个 composite eval。结果 ledger 必须记录 `attempt_id + plan_digest`，gate 只接受同一 attempt、满足拓扑/屏障的组合结果。

### M-3（real-blocker）：结果可重放，缺少 attempt/freshness/config snapshot 绑定

报告只提出 `threshold-id → ran/pass/fail + evidence path`（报告 `:95-98`），D1 也只做 containment/schema（`:303-307`）。虽然 evidence index 有 Freshness requirement 与 Observed timestamp（`evidence-index-template.md:6-15`），两者没有被接入 eval result 的机械契约；threshold digest 只能防改判据，不能防复制上轮 pass。

最低结果字段应包括 `round_id/attempt_id`、started/finished、threshold digest、plan digest、无 secret 的 system-binding/config fingerprint、executor/provenance、command digest、exit/result、evidence digest 和 freshness evaluation。否则旧 evidence、旧 endpoint 或不同版本服务上的 pass 可以被复制到新 round。

### M-4（real-blocker）：测试资源 cleanup 只有预授权计划，没有 acceptance outcome

报告 GAP-5 建议声明 cleanup contract（报告 `:169-177`），connectivity 也只在执行前要求 rollback/test-resource 细节（`harnessloop-connectivity/SKILL.md:24,38-43`），但拟议 eval ledger 没有 `cleanup_required/cleanup_status/cleanup_evidence`。因此业务探针可以 pass、round positive，同时遗留 token、账号、队列消息或测试数据。

对带写 eval，positive 应同时要求 cleanup=`pass`；若资源有意保留，必须引用有期限的 retention authorization，并把过期清理变成后续 hard obligation。

## A.3 推荐

1. **EV-D 最小 teeth：以 D2 为正式 hard gate；D1 仅作 activation-gated 迁移阶段。** 理由：用户裁决同时要求“未跑”和“未过”都不得 positive，只有 ran 完整性不够。
2. **外部系统采用独立 versioned JSON + gitignored local binding；不做全局 gate_blocking，而对 active due eval 条件阻塞。** 理由：保留单一机器 schema 与本机秘密/endpoint 分离，同时不让无外部系统的项目被空配置拖死；data-sources 只做人读视图。
3. **默认由 main session/其直接调用的受控 runner 执行；fresh delegation probe 通过后，项目才可切到预授权子代理写。** 理由：当前 environment probe 可假绿，先选可审计的保守默认，再由项目矩阵覆盖。
4. **本项目按“standard + 结构化测试资源预授权”运行，不降成 strict；strict 保持逐 checkpoint 人闸。** 理由：当前 contract 已明确 positive 自动进下一子目标（`state/control-contract.md:7-11`），生产/不可逆写仍停人（`:22`），这与用户的单会话自续主线最匹配。

## Decisions / deviations

- 假设：任务所称“只读”排除 hopper 规定的交付文件本身；未修改任何被审代码、文档或状态文件。
- `real-blocker` 指在相应能力被承诺时会让 hard gate 无法正确裁决或让自主执行越过安全边界；profile/入口未启用时的条件缺口不一律升级为全局 blocker。
- 未采用 T-074 的结论作为事实来源；所有关键裁定重新对照 `b389eac` 源码与当前 14 轮语料。
- 另发现修订残留事实错误：报告 `:331` 仍写“20 轮”，而磁盘计数为 goal 001=`4`、goal 002=`10`。

## Open questions

none

## Verdict

**REWORK**

核心 7 GAP 不需要推翻，但修订版目前不只是措辞问题：中央分步建议在主文与附录中互相冲突；D1 缺 stable ID、权威 due-set、activation/version 和 legacy migration；O-1 被错误放成普遍前置而 O-9 才是 D1 的真实前置；环境 probe 假绿、多系统 DAG/同一 attempt、结果 freshness 与 cleanup outcome 四项仍未进入卡点清单。上述问题会直接改变 EV-C/D/H/I 的依赖与验收，不宜以 PASS_WITH_NOTE 进入立项。

## Next recommendation

先对报告做一次定向修订，不重写 7 GAP：

1. 删除 `:124-125` 与 `:264` 的旧“纯先入账”表述，补 `eval_gate_version + activation_round + legacy migration manifest`，并把 EV-I 放到 D1/EV-D 之前。
2. 将 O-1 拆成“核心 provenance/authorization 字段”（并入 EV-C/E）与“项目 executor policy”（条件式 EV-H），不规定唯一全局拓扑。
3. 新增 delegation-probe 语义门、多系统 eval DAG/锁/attempt、freshness/config fingerprint、cleanup outcome 四个卡点。
4. 把资产 #3 改成“控制面同形、probe adapter 异构”，并修正方法节残留的 20→14。
5. 修订后再做一次只盯依赖图、迁移状态机与 hard-gate acceptance 的轻量复核；无需重审已确认的 7 GAP 事实证据。

## Vendor output (parsed) _(preview 8000/564469 chars; complete parsed output is available through `hopper-dispatch --result T-075 --full`)_

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
session id: 019fa514-c7ce-7f13-98bb-290131659dbc
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

## T-075（runtime-evals/自主化审核 — codex 独立参照审）

**Task-type**: `code-review-adversarial` · **只读评审，不改任何代码/文档**

**评审对象**：`docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（**修订版**，
commit `4ea6813`——已吸收第 1 轮对抗核实）。
**先读**：`.hopper/handoffs/T-074-output.md`（grok 第 1 轮，判 PASS_WITH_NOTE）。
**对照源码**：harnessloop submodule `b389eac`（v0.26.0）+ 本项目 `.harnessloop/`（14 轮）。

**你的角色是第二家独立参照**，不是复读 T-074。四项：

1. **仲裁三个争议点**（双方立场并列给你，请按源码证据独立裁定，不预设谁对）：
   - **争议 A（资产 #3）**：原报告称 reference-roots 两文件模式可"同形扩展"到服务
     端点域；T-074 降级为"纪律可借、机制不可照搬"（理由：expect_present 是磁盘
     sentinel、服务端点无同构物、available 语义完全不同）。哪个表述准确？降级是否
     过度（例如：探活 sentinel 是否其实可以定义为"GET <path> 期望 <status/字段>"
     的服务域同构物）？
   - **争议 B（分步安全性）**：原报告建议"B2a 式先入账后硬门"；T-074 判其在硬门
     裁决下危险并给出 D0/D1/D2 替代（D1 起即带"缺 ran 记录不得 positive"）。
     D1 的"半个硬门"起步是否现实——一个从未有过 eval 结果文件的项目，第一天就要求
     缺 ran 即不得 positive，会不会把所有存量 goal 直接判死？迁移语义谁来定义？
   - **争议 C（O-1 定性）**：T-074 把"eval 执行者未建模"判为与 GAP-2/3 同级的一等
     卡点。是否成立？还是执行拓扑本可以留给各项目的 cost-context-policy/委派矩阵
     自定义、协议只需定义结果文件契约（即 O-10 的"账本核对"边界已经足够）？
2. **核实 O-1..O-10 有没有被夸大**：逐条判 real-blocker / nice-to-have / 已被原报告
   覆盖只是换了说法。特别审 O-2（round_cost 交互）与 O-4（handoff 门闩）是不是
   "自主化的真实前置"还是"可以在 EV-F 里顺手处理的细节"。
3. **三方漏网之鱼**：原报告 + T-074 都没抓到的、会卡「配置化外部系统 + runtime evals
   硬门 + 单会话多轮自续」的点。提示两个没人碰过的面：环境自检
   （state/environment.md 的 delegation probe）与多系统 eval 的**并发/顺序**语义
   （两个系统的探针互相依赖时协议怎么表达）。
4. **对附录 A.3 的四个开放问题给出你的独立推荐**（一句话理由即可）——供用户裁决时
   参照，不替用户决。

**验收**：逐项给裁定 + 源码证据。产物落 `.hopper/handoffs/T-075-output.md`，含
`## Verdict`（对**修订版报告**整体判 PASS / PASS_WITH_NOTE / REWORK）、
`## Files touched`（应为 none）、独立成节的 `## 三方漏网之鱼` 与 `## A.3 推荐`。

codex
我将按只读对抗评审执行：核对修订版报告、T-074 与 `b389eac` 源码及本项目 14 轮材料，只写交付文件 `.hopper/handoffs/T-075-output.md`，不修改评审对象或源码。
exec
/bin/zsh -lc "pwd && git status --short && git submodule status && sed -n '1,260p' .hopper/handoffs/leader-tasklist.md && sed -n '1,320p' .hopper/handoffs/T-074-output.md" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 646ms:
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 ? kernels/openclaw
?? .hopper/handoffs/T-075-output.log
?? .hopper/handoffs/T-075-output.md
?? .hopper/handoffs/T-075-progress.log
 b389eaca1427af8e88248259e350d02b465434e4 harnessloop (heads/main)
 cabb1711838d49061bf1bf096903e8fb0d4818d4 hopper-plugin (heads/main)
 dada4fb5b5d2d47777a2bf79a9665d4191b22483 kata (heads/main)
 17155e3ae04d376dd8eba2e65f3dd966e67ab1ba kernels/hermes (heads/main)
 c35df878383c05bbbe738ecec472acccd0ca38f0 kernels/openclaw (heads/agent-app-persession)
# Leader Tasklist

Full task specs live here. Each task in `queue.md` references a section below by
its ID (the dispatcher pulls this section as the task spec).

---

## T-EXAMPLE-001

**Goal**: Describe what to build or verify in one or two sentences.

**Acceptance criteria** (prefer machine-checkable — a shell command or grep that proves each):
1. ...
2. ...

**Files allowed to touch** (positive scope): ...

**Files MUST NOT touch** (negative scope): ...

**Budget**: time and vendor-cost ceiling.

---

## T-001

**Task-type**: `code-review-adversarial` · **Vendor**: codex (随机结果，见 `.hopper/AGENTS.md`)

**Goal**: 对 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop`
仓库的 commit `6936fbc`（setup wizard 完整实现：新 `harnessloop-setup` skill +
`check_setup.py` + `control-contract-profiles.md` + 四个既有 SKILL 的接线改动 +
`scripts/validate.py` 新增第 3 阶段）做一次**只读**对抗评审，不修改任何文件。

**评审对象**：
- Commit: `6936fbc63497ba7619acaccc177a13c976f4202e`，取 diff 用
  `git -C harnessloop show 6936fbc`（或 `git -C harnessloop show --stat 6936fbc`
  先看改动文件清单）。
- 涉及文件（相对 `harnessloop/` 仓库根）：
  1. `plugins/harnessloop/skills/harnessloop-setup/SKILL.md`（新增）
  2. `plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py`（新增）
  3. `plugins/harnessloop/skills/harnessloop-loop/references/control-contract-profiles.md`（新增）
  4. 四个既有 SKILL 的接线改动：
     `plugins/harnessloop/skills/harnessloop-continue/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-init/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-loop/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-status/SKILL.md`
  5. `scripts/validate.py`（新增 stage 3）

**评审焦点**（按重要性排序）：
1. **`check_setup.py` 的判定算法边界**：字段切片匹配逻辑、TODO/none-哨兵正则
   的边界条件（漏检/误检）、`gate_blocking` 判定的两档（模板/缺失 vs
   advisory-complete）是否有遗漏或误判分支。
2. **SKILL 文本与脚本行为的一致性**：`harnessloop-setup/SKILL.md`、
   `harnessloop-status/SKILL.md`、`harnessloop-continue/SKILL.md` 等文本描述
   的行为，是否与 `check_setup.py` 的实际输出（`--json` 契约、exit
   码 0/1/2、字段计数）一致，有无文档与实现漂移。
3. **`scripts/validate.py` 新增断言的证伪力**：新 stage 3 的 28 项断言是否
   真能在对应缺陷注入时失败（而非无论实现对错都通过的"假阳性绿灯"）。
4. **Python 3.9 兼容性**：`check_setup.py` 及 `validate.py` 改动是否使用了
   3.9 之后才引入的语法/标准库特性（本机 `python3 = 3.9.4`，见
   `.harnessloop/setup/data-sources.md` 底部注）。

**Read-only 要求（硬约束）**：
- 不得修改、创建或删除 `harnessloop/` 仓库或本仓库中的任何文件。
- 结论写入 hoppe

... [truncated, 556469 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 336895
- end_time: 2026-07-27T19:42:46.299Z
- log: see `T-075-output.log` for raw output
