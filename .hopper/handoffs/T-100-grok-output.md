---
task_id: T-100-grok
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
pid: 12654
start_time: "2026-08-12T07:40:40.626Z"
end_time: "2026-08-12T07:48:17.353Z"
exit_code: 0
duration_ms: 456671
mode: background
phase: done
last_progress_at: "2026-08-12T07:48:17.354Z"
last_progress: Task completed successfully.
progress_seq: 17
progress_log: ./T-100-grok-progress.log
raw_log: ./T-100-grok-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-100-grok-output.log
started_by_pid: 12648
last_stream_event: process_alive
last_update: "2026-08-12T07:48:10.700Z"
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

# T-100-grok — grok (background, done)

Output streaming to `T-100-grok-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/11652 chars; complete parsed output is available through `hopper-dispatch --result T-100-grok --full`)_

````
I'll perform an independent adversarial review of the hopper-plugin fix: read the design decisions and implementation, then construct counter-examples and check the four flagged deviations.Working from uncommitted 0.55.0 changes; next I'll read the core implementation, tests, and design decision.Next I'll verify path coverage (background/swarm), run the counter-example tests, and check version/override assertion gaps.Tests still running on some suites; I'll dig the task red-line about ISSUES.md and construct a destructive counter-example in parallel.I'll construct destructive counter-examples with temporary patches (restored after), and finish path/coverage checks.# Adversarial code review — hopper brief-drop fix (0.55.0)

## Summary

The queue-path brief-drop is fixed in the designed shape: `loadTaskSpec` returns `null` (not self-describing prose), `composeTaskContent` merges detailed spec + `### Queue brief` with explicit precedence, placeholders become operator notices only, and empty+empty fail-closed. Independent counter-examples (placeholders restored → 6/11 red; fail-closed removed → 3/11 red) and live runtime checks confirm the brief reaches `composedPrompt` and empty tasks throw. Version guards and related unit suites pass. Residual issues are test-hygiene (no positive assertion for `(--vendor override)`), an acceptable ISSUES.md touch beyond the red line, and a weak/misnamed whitespace-section test — not a reopening of the product defect.

## Files touched

Review-only; **none** modified by this review. Verified working tree for the fix includes (among others):

| Path | Role |
|---|---|
| `cli/src/dispatch.js` | `loadTaskSpec` → `null`; `composeTaskContent`; export/constants |
| `cli/bin/hopper-dispatch` | `specNotice` on `--resolve`/sync/background; `VERSION` |
| `plugins/hopper/cli/**` | vendored sync of the above |
| `tests/unit/dispatch-task-content.test.js` | new 11-case contract suite |
| `tests/unit/resolve-vendor-override.test.js` | non-empty Brief + narrowed `doesNotMatch` |
| `tests/unit/resolve-and-model-hints.test.js` | non-empty Brief fixture debt |
| `tests/unit/readme-version-badge.test.js` | discovery guard for README version badges |
| manifests / `package*.json` / commands / READMEs | 0.54.0 → 0.55.0 |
| `CHANGELOG.md` | 0.55.0 narrative entry |
| `docs/archive/ISSUES.md` | close fixed issue (+ register unrelated open issue) |

## Acceptance verification

### Design Q1–Q4 alignment

| Criterion | Evidence | Result |
|---|---|---|
| **Q1 乙 merge** | `composeTaskContent` both-present path builds `detailed + QUEUE_BRIEF_HEADING + brief + QUEUE_BRIEF_PRECEDENCE_NOTE`; test (a) asserts order + precedence + both in `composedPrompt` | **PASS** |
| **Q2 `string\|null`, export, no `??`** | `export async function loadTaskSpec` returns `null` on ENOENT / no section; compose uses `.trim()` emptiness, not `??` | **PASS** |
| **Q3 placeholder → operator notice** | placeholder strings gone from miss branches; `specNotice` printed in `hopper-dispatch` `--resolve` (stdout), sync/background (stderr); tests assert `PLACEHOLDER_RE` absent from `composedPrompt` | **PASS** |
| **Q4 fail-closed** | throw when both empty; CLI `--resolve` exit 1; tests (d)/(d2)/CLI | **PASS** |

### Fix actually blocks the defect (constructed, not code-read only)

**Live runtime (current code):**

```
loadTaskSpec= null
taskSpec===brief? true
composed has UNIQUE? true
composed has placeholder? false
EMPTY throws: Task T-Y has no task content: ...
both has detailed/brief/heading/precedence/composed? true
```

**Destructive counter-example A** — temporarily restored the two placeholder `return`s in `loadTaskSpec` (then restored file; `cmp` OK):

- `dispatch-task-content.test.js`: **pass 5 / fail 6** (matches main-session “6/11 red”)
- Failures include: null-contract on miss, `PLACEHOLDER_RE` in prompt, fail-closed (placeholder is truthy “detailed” → no throw), `--resolve` notice path
- Case (a) stays green under new compose: truthy placeholder + brief would still merge — tests that lock “placeholder never enters prompt / null contract / fail-closed” are what go red. That is exactly why the old bug lived under tasks that *had* a leader-tasklist section.

**Destructive counter-example B** — replaced fail-closed throw with silent `{ taskSpec: '' }`:

- **pass 8 / fail 3** (d, d2, CLI fail-closed)

**HEAD baseline still has the old placeholders** (`git show HEAD:cli/src/dispatch.js` lines with `using queue.md brief only`).

### Call-graph / silent-failure surfaces

| Path | Goes through fix? | Notes |
|---|---|---|
| Queue sync (`runDispatch` → `resolveDispatch`) | **Yes** | `composeTaskContent` + stderr notice |
| Queue background (`runBackgroundDispatch` → `resolveDispatch`) | **Yes** | same |
| `executeDispatch` | **Yes** | `resolveDispatch` then `executeWithAdapter` |
| `--resolve` | **Yes** | notice on stdout |
| Ad-hoc | N/A (never broken) | `taskSpec = brief`; empty already rejected; `specNotice: null` |
| Swarm | N/A (never broken) | `planSwarm` requires non-empty brief; each panelist is ad-hoc |

No remaining queue path found that still calls `loadTaskSpec` and feeds its return straight into `composePrompt`. Ad-hoc/swarm never had this bug; they already fail-closed on empty brief. **No new silent “exit 0 with empty task” path** introduced; behavior is **stricter** (new rejects).

`fileExists`/`access` only affects **notice wording** after `loadTaskSpec` already returned `null`; it does not change `taskSpec` content. Non-ENOENT read errors still throw from `loadTaskSpec` before compose.

### Four implementer deviations (adjudicated)

**1. Touched `docs/archive/ISSUES.md` despite red line — acceptable?**  
**Yes, with a note.** Closing `#queue-brief-dropped-without-leader-tasklist` with a Resolution tied to 0.55.0 matches how other fixed issues are closed in that archive and is the right hygiene for a release that claims the fix. The red line’s stated intent was avoiding conflict with a **parallel migration**, not forbidding forever documenting a closed defect.

**Note:** the same diff also **opens** `stale-status-on-runner-death` and moves Open 6→7 / Closed 11→12. That is scope creep beyond “close the fixed issue,” but it is documentation-only and not a product regression. Prefer a separate commit for unrelated issue registration next time.

**2. Narrowed `doesNotMatch(/override/i)` → `/\(--vendor override\)/i` — reason sound? Cost?**  
**Reason fully established; narrowing correct.** Live `--resolve` with the fixture’s `mkdtemp` prefix `hopper-resolve-override-…`:

- path appears in the new leader-tasklist-absent notice  
- bare `/override/i` matches on **no-override** stdout (path + Brief text `"resolve the override"`)  
- marker `/\(--vendor override\)/i` does **not** match on no-override; **does** match when `--vendor grok` is set  

Cost: the negative assertion is now tightly tied to one marker string (see gap below). That is better than a permanently false-positive bare word after notice paths echo absolute temp dirs.

**3. Extra `access()` on fallback — keep signature or return `{spec, reason}`?**  
**Acceptable under locked Q2.** Signature stays `string | null`; distinguishing ENOENT vs “file exists, no section” for operator notice requires a second probe or a richer return type. Extra `access` is one cheap syscall, only on the miss path, and only affects notice text. Changing to `{spec, reason}` would reopen Q2 without material product gain. Keep as-is.

**4. `taskTextRequestsReadOnly` sees brief twice on brief-only path — harmless?**  
**Confirmed harmless for current semantics.** Function joins `task.brief` + `taskSpec` and runs existence regexes (`READ_ONLY_TASK_RE` / `NEGATED_READ_ONLY_RE`). Live checks:

- brief-only with same string twice ≡ brief-only once ≡ taskSpec-only once for positive/negated/Chinese cases  
- empty → false  

No permission widening; still boolean presence, not counting.

### Main-session finding: positive-assert gap on ov

... [truncated, 3652 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 456671
- end_time: 2026-08-12T07:48:17.353Z
- log: see `T-100-grok-output.log` for raw output
