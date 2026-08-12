---
task_id: T-097
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
pid: 56908
start_time: "2026-08-12T03:38:16.881Z"
end_time: "2026-08-12T03:42:18.641Z"
exit_code: 0
duration_ms: 241706
mode: background
phase: done
last_progress_at: "2026-08-12T03:42:18.644Z"
last_progress: Task completed successfully.
progress_seq: 10
progress_log: ./T-097-progress.log
raw_log: ./T-097-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-097-output.log
started_by_pid: 56903
last_stream_event: process_alive
last_update: "2026-08-12T03:42:16.948Z"
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

# T-097 — grok (background, done)

Output streaming to `T-097-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10615 chars; complete parsed output is available through `hopper-dispatch --result T-097 --full`)_

````
I'll independently review the four approval-FSM boundary fixes with code reading and constructed counterexamples—no edits, no process changes.Reading the critical implementation sections and evidence files next.Checking where openclaw actually emits the terminal approval event relative to the RPC response — the claimed ordering is load-bearing.## Summary

Adversarial read-only review of rounds/0016’s four approval-FSM boundary fixes. Implementation matches the stated intent: overflow deny is success-gated, `FORCE_DENY_PENDING_KERNEL_ACK` blocks allow-without-RPC, bounded resolve wait uses actor settle/epoch (not task groups), and active-timeout UI clear-then-promote is dual-layered. All four implementer corrections to codex T-096 hold; openclaw source confirms terminal lifecycle emits before `respond(true, …)` on the durable path. Residual risk is evidence completeness (live allow→execute not re-run), not a found implementation defect that should force REWORK.

## Files touched

none (review only)

## Acceptance verification (12/12)

### 1. Overflow deny success criteria

| Check | Evidence |
|---|---|
| Strict success = `applied==true && status=="denied"` | `OpenclawGatewayKernelClient.swift:1523–1546` dual guards; emit only at `:1550` |
| Failures → `failQueueOverflowDeny` | catch `:1506–1512`, `applied!=true` `:1523–1534`, non-denied `:1538–1545` → `:1557` |
| `queue_overflow` not pre-emitted | admission branch only `beginQueueOverflowDeny` `:2862–2872`; no emit before RPC |
| `applied:false` does not enter FORCE_DENY | `enterPendingKernelAck: false` at `:1532` |

**Counterexample (constructed, not code-skim):**  
RPC throw / `applied:false` / `applied:true+allowed` must never produce `approval_buffer_resolved(queue_overflow)`. Green evidence:

```
失败形态① RPC 抛错 -> queue_overflow=[] | evt.error=[…queue_overflow_deny_unconfirmed…] | FORCE_DENY=…
失败形态② applied:false -> queue_overflow=[] | FORCE_DENY=无
失败形态③ applied:true 非 denied -> queue_overflow=[] | FORCE_DENY=…
成功对照 -> queue_overflow=[…queue_overflow] | evt.error=[]
```
(`rounds0016-counterproofs-green.txt` L1–5; red demolitions in `counterproof-red-checks.md` ①-a/b)

**Swallow path hunt:** No remaining “warn-only” overflow path. One doc drift only: older comment at `:2832` still says overflow “产出 queue_overflow 并对它发起强制 deny”; body is correct.

### 2. `FORCE_DENY_PENDING_KERNEL_ACK`

| Check | Evidence |
|---|---|
| Persistent state | struct `:411–424`; record on stop-path fail `:1175–1179`, `:1208–1214`; overflow fail `:1564–1568` |
| Gate 2b: allow rejected, zero RPC | `:1827–1843` before slot/RPC |
| Clear criteria | deny retry with `status=="denied"` (any applied) `:1920–1934`; authoritative terminal any status `:1622–1625`; session clear `:2055–2060` |

**Stuck-forever hunt:**  
- `applied:false` correctly excluded → avoids un-clearable retry loop (kernel will keep returning `applied:false`).  
- Clear paths: successful denied, kernel terminal, session teardown.  
- Residual: synthetic `applied:true+allowed` (test-only anomaly) can leave the gate until terminal/session end; not a live openclaw deny path.

Green: allow-once rejected with call count `1→1`; deny retry clears (`rounds0016-counterproofs-green.txt` L6–9; red ②-a/b).

### 3. Bounded `approval.resolve` wait

| Check | Evidence |
|---|---|
| Implementation | `sendApprovalResolveBounded` `:1302`, `settleApprovalResolve` `:1350`, `endApproval…Terminal` `:1398` |
| Default 30s | `approvalResolveBoundedWaitDefaultMS = 30_000` `:384` |
| Actor inbox + settled + epoch | `:341–358`, `:1349–1376` |
| No task-group wait | Comment `:1282–1288` rejects `withThrowingTaskGroup`; implementation uses detached RPC Task + deadline Task + continuation inbox |

**Is the “continuation not cancel-aware” rationale sound?** Yes. `request()` waits on `withCheckedThrowingContinuation`; cancelling a sibling Task does not resume it. A task-group that waits for all children would re-introduce hang-on-missing-response.

**Permanent occupancy hunt:**  
- Timeout settles and `defer { endApprovalResolveInFlight }` releases the slot.  
- `expired` terminal settles in-flight independently (red ③-b proves this is not just timeout covering).  
- `clearSessionDerivedCaches` forces settle then end `:2042–2051`.  
- Late orphan RPC dropped by epoch/settled.  
- Residual: orphan Task may remain suspended after timeout (no slot occupancy, no drain block) — acceptable leak of a hung Task, not a permanent FSM lock.

Green: A timeout 160ms; B terminal ends in-flight with 600s bound (`rounds0016-counterproofs-green.txt` L10–12).

### 4. Active terminal → UI sync + badge

| Check | Evidence |
|---|---|
| Adapter order: `evt.error(approval_timeout)` then promote | `:1649–1664` yield error before `promoteNextBufferedApprovalIfPossible` |
| Shell: removeAll then append | `SessionStore.swift:364–377` |
| Shell: `approvalTimeout` clears cards | `SessionStore.swift:399–405` |
| Badge deleted | `SessionDetailView.swift:97–114` only renders `pendingApprovals.first`; no `count-1` badge |

Green: event stream `["error","approval_request(ui-b)"]`; cards `[ui-a]→[]→[ui-b]`; second guarantee replace-on-request; badge structural proof buffered=2 shell-visible badge digit=0 (`rounds0016-counterproofs-green.txt` L15–20).

---

### Implementer corrections to codex T-096

| # | Claim | Verdict |
|---|---|---|
| **①** Narrow authoritative-terminal settle to `status=="expired"` | **Holds.** Durable path: `resolveDetailed` → `settleLocalFromStore` → `emitLifecycle({phase:"terminal"})` (`exec-approval-manager.ts:506–511,620`) **before** `respond(true,{applied,approval})` (`approval.ts:540`). Wide “any terminal” would abort the user’s own allow/deny after kernel applied it. Regression test nails this (`green.txt` L13–14; red ③-c). Residual after narrow: non-expired external terminals rely on RPC result or 30s bound — correct. |
| **②** Exclude `applied:false` from FORCE_DENY | **Holds.** `applied:false` means durable terminal already exists; deny retries only re-get `applied:false` (approval.ts:460–471). Entering FORCE_DENY would create an un-clearable gate. |
| **③** Delete badge; cannot wire real buffer count inside red lines | **Holds.** Buffer never yields `approval_request` (D1 §6.2 “不触发新的可见 pending 状态”). Shell can only see active; `count-1` is structurally wrong (test: real buffered 2, fabricated badge 0). True count needs D1 surface or side channel — both out of scope. Delete is the only T-096-compliant option. |
| **④** Refuse to map non-`expired` terminals to `approval_timeout` | **Holds.** D2 `KernelErrorCode` enum is only `rate_limited|kernel_crashed|auth_failed|sandbox_denied|network_lost|approval_timeout|unknown` (`errors.schema.json:10–18`). Mapping cancelled/denied/allowed → `approval_timeout` is a lie; using `unknown` would still be a fake semantic. Defer to D2 is correct; scope-lock already excludes contract edits. |

---

### Regressions / new races / silent failures

| Item | Severity | Notes |
|---|---|---|
| Wide terminal settle (pre-narrow) would break live allow path | **Avoided** | Regression test present |
| Orphan RPC Task after timeout | Low | Slot released; drain not blocked |
| Active `denied`/`cancelled`/`allowed` without promote | Known gap | Dead card until local timer / next request; honest D2 registration, not a silent success |
| Overflow doc comment at `:2832` stale | Cosmetic | Body correct |
| FORCE_DENY after stop-path fail + failed stop leaves session locked until caller handles error | Pre-existing shape | Gate correctly blocks subsequent allow |

No new “claim success while kernel still pending” path found for the four items.

### Evidence sufficiency

| Item | Support quality |
|---|---|
| ① Overflow | **Strong** — 4 stubs + red demolitions of pre-emit and weak success criteria |
| ② FORCE_DENY | **Strong** — allow zero-RPC + deny clears; reds for missing gate/state |
| ③ Bounded wait | **Strong** — hang-on-red for unbounded; independent terminal path with 6

... [truncated, 2615 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 241706
- end_time: 2026-08-12T03:42:18.641Z
- log: see `T-097-output.log` for raw output
