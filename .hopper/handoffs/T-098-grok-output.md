---
task_id: T-098-grok
adapter: grok
model: grok-4.5
requested_selector: null
effective_selector: grok-4.5
effective_selector_source: policy
selector_kind: unknown
catalog_source_kind: unknown
catalog_source_label: unknown
catalog_observed_at: null
catalog_freshness: unknown
binary_availability: unknown
binary_basename: null
status: done
pid: 61107
start_time: "2026-08-12T06:34:08.024Z"
end_time: "2026-08-12T06:38:16.620Z"
exit_code: 0
duration_ms: 248542
mode: background
phase: done
last_progress_at: "2026-08-12T06:38:16.621Z"
last_progress: Task completed successfully.
progress_seq: 10
progress_log: ./T-098-grok-progress.log
raw_log: ./T-098-grok-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-098-grok-output.log
started_by_pid: 61101
last_stream_event: process_alive
last_update: "2026-08-12T06:38:08.090Z"
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
signal: null
process_cleanup: not-needed
adapter_status: success
---

# T-098-grok — grok (background, done)

Output streaming to `T-098-grok-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10607 chars; complete parsed output is available through `hopper-dispatch --result T-098-grok --full`)_

```
I'll sort the decision backlog as a read-only review: verify each item against the repo, classify U/M/D with evidence, and produce a narrowed options list for the user-must-decide items.Digging into rounds 0014–0016, TH-0031, the hopper brief-drop issue, and D2 error codes for file-level evidence.I have enough evidence to finish the triage, including a contrast against the main session’s pre-registration.# Decision triage (adversarial) — output

## Summary

After source-grounded review of rounds 0014–0016, D2 schemas, hopper issue, TH-0031, and the ~29 `TODO (owner: user)` fields, the backlog collapses from ~12 surface items to **2 user decisions now** (plus one optional batch of suggested field values later). Most A/B/C/E items are engineering judgment or pure deferral. Project nature (**app is means, plugin validation is the purpose**) flips priority: **C1 should outrank A-group**, not trail it. The main session’s pre-reg (`.harnessloop/state/decision-triage-prereg.md`) got A1/A2/B1/C1-authorization/E roughly right, but **over-promoted whole-group D to U** and under-weighted C vs A.

## Files touched

none (read-only; no edits, no process start/stop; gateway / `~/.openclaw` untouched)

## Acceptance verification (6/6)

| # | Criterion | Evidence |
|---|---|---|
| 1 | Each item classified U/M/D with reason | See §分拣 below; every row has class + rationale |
| 2 | Evidence with file:line where repo-backed | e.g. D2 codes `app/contracts/d2/schema/common/errors.schema.json:10-18`; FluffyReason `app/generated/swift/D2.swift:3635-3638`; card clear only on `approvalTimeout` `SessionStore.swift:387-406`; buffer reason two-value `d2.d.ts:985`; capabilities stub `OpenclawGatewayKernelClient.swift:1960-1961`; D1 README placeholder `app/contracts/d1/README.md:1-10` pointing v3-5 while wiki has v3-6; hopper issue `hopper-plugin/ISSUE-queue-brief-dropped-without-leader-tasklist.md:1-7`; TH-0031 `.harnessloop/meta/evolution-issues/0031-…md:72-78`; TODOs non-blocking via TH-0017 resolved + `check_setup` design |
| 3 | U items get real options + costs/irreversibility | §必须用户定 below |
| 4 | Narrowed list, not 12 raw items returned | **2 U-now** (+ optional confirm-on-D-suggestions) |
| 5 | Speculative claims marked | Marked where used (e.g. consumer breadth of `capabilities()` beyond approval path) |
| 6 | Project-nature effect + grouping critique | §分组批判 + priority order |

## Decisions / deviations

- Read main-session pre-reg *after* independent read of sources; used it only for contrast (same method as rounds/0015 channel pre-reg).
- Treated A1+A2 as **one** product/priority decision, not two.
- Split A3 into “pin constant now” (M) vs “implement `capabilities()`” (D).
- Split B1 into “fix stale pointer” (M) vs “copy D1 body into repo” (D).
- Split C1 into “fix is M / push auth already granted” vs “**when** relative to other work is U”.
- **Rejected** “all ~29 TODOs = one U blob”; only a few stop/budget fields are real U.

## Open questions

none that block this triage. (Side items not in the five groups but relevant: hopper `ISSUE-stale-status-on-runner-death`, PATH shim drift, kata usage still thin — noted under plugin priority, not re-opened as U.)

## Verdict

**PASS_WITH_NOTE**

Deliverable is a decision sort, not a code diff. Notes: (1) main-session grouping by technical layer under-ranked plugins; (2) D-group must not be re-exported wholesale to the user.

## Next recommendation

Present the user **only** the two U-now items below (recommend **Option 1: plugin-first**). Main session should autonomously: fix B1 pointer, pin A3 schema constant, schedule C2 fix A, and park A1/A2 as an explicit design-round ticket without asking “how to implement.”

---

# 分拣结果（逐项）

图例：**U** 必须用户 · **M** 主会话自定 · **D** 可延后

### A 组：D1/D2 契约

| 项 | 判 | 理由与依据 |
|---|---|---|
| **A1** 非 `expired` 终态清卡 | **U**（**是否现在开设计轮**） | 工程事实已闭合：D2 `KernelErrorCode` 仅七值，`approval_timeout` 是唯一字面对应审批超时（`errors.schema.json:10-18`）；UI 只对 `.approvalTimeout` 清卡（`SessionStore.swift:387-406`）；`denied`/`cancelled`/`allowed` **没有诚实码**，0016 明确拒绝冒充（`EventMapping.swift:784-805`；`rounds/0016/decision.md:37-44`）。**技术怎么做主会话能写方案**；**值不值得现在付 D2 扩枚举 + 三端 codegen + fixture 成本**，是优先级/可接受不完整度 → **U**。 |
| **A2** buffer `reason` 词表 | **D**（并入 A1） | 词表仅 `buffered_timeout`/`queue_overflow`（`d2.d.ts:985`；`D2.swift:3635-3638`）。`cancelled` 终态化缓冲项无法如实表达；0016 选择不上报而非谎报（`OpenclawGatewayKernelClient.swift:1604-1607`）。**单独开议题价值极低**——A1 若做则顺带；A1 不做则仍可接受「缓冲取消静默」作为已知缺口。与主会话 pre-reg 一致。 |
| **A3** `capabilities()` 桩 | **M**（钉死常量） / **D**（完整实现） | 现为 `notImplemented` 桩（`OpenclawGatewayKernelClient.swift:1960-1961`）。D1 §2.6 要求 `approvalDecisionKinds` 由它门控；实现侧用 openclaw 三值 wire 枚举 + 显式映射（`EventMapping.swift:920-969`），`allow_session` 已 fail-closed。**立刻该做的**是测试把 wire 三值与 schema 钉死（便宜、防漂移）→ **M**。完整 `capabilities()` + `capability_changed` 回填是 SG-8 residual，**不阻断 L1 基本使用**（0016 `Accepted: yes`）→ **D**。*推测*：若未来 UI 依赖 descriptor 其它字段（streaming 等）会变成阻断，但当前壳对 `.capabilityChanged` 是 no-op（`SessionStore.swift:432-433`）。 |

### B 组：项目结构

| 项 | 判 | 理由与依据 |
|---|---|---|
| **B1** 契约正文不在契约目录 | **M**（修指针） / **D**（整本转录） | README 仅 10 行占位且指向 **v3-5**（`app/contracts/d1/README.md:5-10`）；权威正文在 `~/.llm-wiki/.../d1-kernelport-spec-v3-6.md`（`design_status: confirmed`）。0015 已因此让子代理「在 `app/contracts/` 核实 D1」变成不可能指令（`docs/validation-log.md:40`）。**过时指针不修无理由** → **M**。全文拷进 monorepo 是同步成本 vs 单机权威的权衡，README 自己已 defer → **D**，不必问用户「现在拷不拷」。 |

### C 组：插件（项目主目的）

| 项 | 判 | 理由与依据 |
|---|---|---|
| **C1** hopper brief-drop | **M**（修+发） / **U**（**仅时机/插队**） | 高严重度、已取证、未修（`hopper-plugin/ISSUE-queue-brief-dropped-without-leader-tasklist.md:1-7,33-47`；`rounds/0013/evidence/hopper-defect-queue-brief-dropped.md`）。三绿灯假成功直接打在对抗审可信度上——正是 CLAUDE.md 强制核对要防的事。`CLAUDE.md` 已写四仓 push 批次授权 + hopper 7 处版本文件流程 → **再问「能不能 push」是越权推卸**。插件迭代是本项目目的 → **修是 M**。唯一 U：**相对 A-设计轮 / 继续 app 抛光，是否现在插队**。 |
| **C2** TH-0031 | **M**（默认 A） / **D**（紧迫性） | P3 观测项；开新轮无 `decision.md` 会让 `loop_anomaly_skipped_unparsable` 无改善地下降（issue 全文 + `validation-log.md:93-104`）。候选 A/B/C 已写清，作者倾向 A（分离计数）。纯机械门可观测性，有明确更优解 → **M 选 A**；不阻断任何 round → 时机 **D**（可挂在下一次 harnessloop 改动批）。**不必问用户「A 还是 B」。** |

### D 组：~29× `TODO (owner: user)`

| 项 | 判 | 理由与依据 |
|---|---|---|
| **D 整组** | **大部分 D；少数 U（见下）** | TH-0017 **resolved**（`v0.40.0`）：字面 `TODO (owner: user)` **不**参与 `gate_blocking`/`complete`（issue:0017；`check_setup` 设计）。`Environment mismatch` **已 user-confirmed 填过**（`control-contract.md:63-69`）。把「~29 处」整包丢回用户 = 违反「收窄」要求。active goal 相关且仍空、真正改代理停续行为的只剩：`Missing evidence` / `Model/effort mismatch` / `Contract cannot be evaluated`（`control-contract.md:62,70-71`）与 `cost-context-policy` 的 Input/Output limit（`:68-70`）——这些才是 **U**；data-sources 新鲜度、归档 goal 001 的 TODO、self-audit 叙述里的 TODO → **D/M 自填或忽略**。 |

### E 组：纯 backlog

| 项 | 判 | 理由与依据 |
|---|---|---|
| 非布尔 `hasMore` 静默停止 | **M**（下次摸该代码时 fail-closed） / **D**（单开轮） | 0014 审查闸 note；主会话刻意不在评审后改（`rounds/0014/decision.md:36-38,64`）。工程上「静默截断」与项目一贯 fail-closed 取向冲突 → 修法明确；**不单开用户决策**。 |
| placeholder `kernelSessionID`=kernelKey | **M/D** 同上 | 0014 note 2；已知混淆源，顺手修即可。 |
| live 未覆盖多页历史 | **D** | 覆盖缺口，非产品语义。 |
| `[gateway] ready` ≠ `sessions.create` 可用 | **M** | repro 工具就绪判据错误（`validation-log.md:51`）；纯工程，修脚本即可。**勿碰用户常驻 gateway。** |
| 收窄 `AgentShellCore` public | **D** | 0013 Q3 重构建议，收敛守卫明确不做（`rounds/0013/decision.md:40,56`）。 |

---

# 分组批判（主会话清单本身）

1. **按技术层（A 契约 / B 结构 / C 插件…）排序，与项目目的冲突。** CLAUDE.md：app 是手段，三插件验证才是目的。C1 是已坐实的高严重度插件缺陷；A1 是已 park 的 app/D2 设计债。**把 A 放在 C 前面会诱导用户先批「设计轮」而继续用 adhoc 绕过 hopper 真洞。**
2. **A1/A2/A3 不该三问。** A2 附着 A1；A3 大半是测试钉死，不是用户议题。
3. **B1 被写成「结构落差 U」过重。** 真动作是一分钟改 README 指针。
4. **D 组用 `owner: user` 字面量绑架分拣** 是错的——TH-0017 已裁定这些可以合法挂着且不阻断；只有少数 stop/budget 字段改行为。
5. **E 组正确标 backlog**，但其中 hasMore / ready 判据是主会话应默认修的 M，不是「排序而已」的纯 D。
6. **清单漏了同族插件债**（非本任务强制，但影响优先级）：`ISSUE-stale-status-on-runner-death`、PATH 上 stale `hopper-dispatch` shim（`validation-log.md:77-83`）。若只修 brief-drop 而忽略「假 in-progress / 错 shim」，验证回路仍脆。

与主会话 pre-reg 对照：同意 A1=U、A2 并入、B1=M、C1 授权已有/时机 U

... [truncated, 2607 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 248542
- end_time: 2026-08-12T06:38:16.620Z
- log: see `T-098-grok-output.log` for raw output
