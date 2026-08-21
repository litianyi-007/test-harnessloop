# rounds/0023 REWORK — counter-proof summary

Closes three FAIL findings from T-116 codex adversarial review (`T-116-codex-review-recovered.md`).
Raw red/green logs referenced below are siblings in this directory.

## Mechanical checkpoints (final, clean state)

| Check | Result | Evidence |
|---|---|---|
| `swift build --package-path app` exit | **0** | `90-rework-swiftpm-build.log` |
| `frame-replay-tests` tally | **174/174 PASS**, exit 0 (was 169/169; +5 new tests: 1 FAIL2 + 4 FAIL7) | `91-rework-frame-replay-tests.log` |
| Swift parity runner | **13 PASS / 0 FAIL / 0 DEGRADED**, exit 0 (unchanged from pre-rework) | `93-rework-parity-runner-run.log` |
| `git diff --stat -- app/kernel-client/csharp` | empty (C# untouched) | shell, this session |
| Fixture JSON files touched this rework | **0** (only `soft-steer-then-stop.json`'s pre-existing v1→v2 diff remains, untouched this session) | shell, this session |

## FAIL 2 — atomic interrupt→stop handoff

**Fix**: `OpenclawGatewayKernelClient.swift` — `notifyInterruptLockReleaseWaiters` (write `.idle`,
then resume — two steps, race window between them) replaced by `performAtomicInterruptLockHandoff`
(single synchronous, `await`-free function: either releases to `.idle` with no waiter, or writes
the lock **directly** to `.stopInProgress` on behalf of exactly one waiter and resumes it with a new
`.acquired` outcome — the lock never passes through an externally observable idle state when a
waiter exists). `stop()`'s call site no longer re-checks/re-acquires the lock on `.acquired` — it
trusts the handoff. New test-only hook `testSupportSetInterruptPreHandoffBlockingDelay` (real
`Thread.sleep`, not `Task.sleep` — does not yield the actor) widens the otherwise microsecond-scale
window deterministically for the counter-proof below.

**New test**: `testConcurrentSendCannotStealLockDuringAtomicInterruptToStopHandoff`
(`SteerTests.swift`).

| Counter-proof | Sites matched | Result |
|---|---|---|
| Revert `performAtomicInterruptLockHandoff` to old two-step behavior (unconditional `.idle` + resume-all with `.notInFlight`, which the existing call site already treats as "go recheck the lock yourself" — a minimal, single-site revert reusing an existing enum case rather than reintroducing removed code) | **1** (the function body) | **RED** — `94-rework-counterproof-fail2-red-run.log`: `stop()` rejected with `session_locked`, message reads `lock state is send_pending` — the third-contender `send()` demonstrably stole the lock. 173/174 PASS (only this test failed), exit 1. |
| Restore fix, re-verify | — | **GREEN** — `91-rework-frame-replay-tests.log`: 174/174, `sessions.send#2` never dispatched (rejected before RPC). |
| Checksum of restored file vs. pre-revert fixed state | — | **byte-identical** (`sha256: f72a9036c2...5684e7d`) |

## FAIL 7 — active-run snapshot completeness

**Fix** (two independent update points, `OpenclawGatewayKernelClient.swift`):
1. `handleSessionMessageEvent` — `session.activeRunIds` snapshot now does a **full reconciliation**
   (`activeRunIDsBySessionID[sid] = Set(...)`) whenever the field is present, not a union-only add
   gated on non-empty `.first`. Closes both directions: runs started outside this client's own
   `send()` (e.g. restored/externally-started) are now recognized; an explicit `activeRunIds:[]`
   now clears stale local records.
2. `handleAgentEvent` — any agent-stream event carrying a `runId` (not just `session.message`) now
   marks that run active. Closes the path where a run is still deep in tool-calls/thinking and has
   never produced an assistant-text `session.message`.

Residual, explicitly documented (not closed this round): a freshly `restoreSession`'d session with
zero observed events since resubscription and a pre-existing active run remains invisible to the
snapshot — confirmed via read-only source check that `sessions.messages.subscribe`'s response
carries no active-run field (`kernels/openclaw/src/gateway/server-methods/sessions-subscriptions.ts:125-137`).
Conservative reject (`no_active_run_for_steer`) is kept as the explicit fallback rather than guessing.

**New tests** (`ActiveRunSnapshotTests.swift`, 4 total): `#1` external run via session.message
snapshot; `#2` full reconciliation clears stale entries; `#3` agent-event-alone marks active; `#4`
self-consistency (terminal frame for a never-seen run leaves no residue).

| Counter-proof | Sites matched | Result |
|---|---|---|
| Revert `handleSessionMessageEvent` to old union-only/first-only logic | **1** | **RED** — `95-rework-counterproof-fail7a-red-run.log`: tests `#1` and `#2` fail (`expected activeRunIDs == {...}, got []`); `#3`/`#4`/FAIL2 test unaffected. 172/174, exit 1. |
| Restore, checksum verified byte-identical | — | confirmed |
| Revert `handleAgentEvent`'s new unconditional insert | **1** | **RED** — `96-rework-counterproof-fail7b-red-run.log`: only test `#3` fails (`expected activeRunIDs == {...}, got []`); `#1`/`#2`/`#4`/FAIL2 test unaffected. 173/174, exit 1. |
| Restore, checksum verified byte-identical | — | confirmed |
| Final re-verify | — | **GREEN** — `91-rework-frame-replay-tests.log`: 174/174. |

## FAIL 5 — inbound interrupt response mode-awareness

**Fix**: `SwiftFixtureRunner.swift` — `applyMockResponse`'s `case "interrupt":` now looks up the
call's mode (new `RunnerContext.interruptModeByID`, set in `performClientCall` alongside the
existing mode-aware outbound stub registration) and synthesizes a `chat.send`-shaped response
(`runId`/`status`) for `steer`, instead of unconditionally synthesizing a `sessions.abort`-shaped
response (`abortedRunId`/`status:"aborted"`) for every mode. Steer no longer spuriously sets
`hasStopWaitingForTerminal`/`waitingStopCallID` (it never uses that machinery — fire-and-return).

This is the **third layer** of the round's "registered one [mode], let the other silently mismatch"
shape (after the outbound stub registration and the `queueMode→mode` remap, both already PASS per
the review). Searched for a fourth: grepped the full file for every mode-sensitive branch
(`"cancel"`/`"steer"`/`mode ==`) — only the three known sites exist. Also checked the TS runner
(`mock-kernel-client.ts`) for the same shape — structurally not applicable there (it's a D2-shaped
mock kernel, not a native-wire translator, so it echoes fixture-declared D2 responses directly and
has no cancel/steer response-shape divergence to mistranslate). **No fourth instance found.**

Since the gold fixture (`soft-steer-then-stop.json`) never asserts on the exact response body (only
on `outcome`/`sessionLock`/RPC-call-order — confirmed by reading `case "interrupt":`'s pre-existing
"不读 result" convention), this fix does not flip that fixture's PASS/FAIL — the counter-proof is
log-based: the actual (fabricated vs. honest) wire shape observed in the runner's own trace output.

| Counter-proof | Sites matched | Result |
|---|---|---|
| Revert `applyMockResponse`'s `case "interrupt":` to the unconditional `sessions.abort`-shaped synthesis | **1** | **RED** (log-level, not PASS/FAIL-level — expected, see above) — `97-rework-counterproof-fail5-red-parity-run.log`: `RECV chat.send result (interrupt steer)` shows `{"abortedRunId":"run-steer-1","status":"aborted"}` — an impossible shape for a real `chat.send` response. Parity runner still 13/0/0 (fixture doesn't observe this field). |
| Restore, checksum verified byte-identical | — | confirmed |
| Final re-verify | — | **GREEN** — `93-rework-parity-runner-run.log` / `93b-...`: `RECV chat.send result (interrupt steer)` now shows `{"runId":"run-steer-1","status":"queued"}`; 13/0/0 unchanged. |

## Residue verification (checksums, not `git checkout --`)

```
OpenclawGatewayKernelClient.swift   sha256: f72a9036c22dfb9c0c4c5fb81e1750ac39eab94b2674e2c9e7505259a5684e7d
SwiftFixtureRunner.swift            sha256: fb3a77e6fdcb06d47a161ad59bb19400c83379decfe13b5676deda487954029e
```
Both confirmed identical before every revert and after every restore, across all four
revert/restore cycles (FAIL2 ×1, FAIL7 ×2, FAIL5 ×1).
