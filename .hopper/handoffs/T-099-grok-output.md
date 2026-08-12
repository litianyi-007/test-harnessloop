---
task_id: T-099-grok
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
pid: 87687
start_time: "2026-08-12T07:16:35.672Z"
end_time: "2026-08-12T07:19:50.652Z"
exit_code: 0
duration_ms: 194927
mode: background
phase: done
last_progress_at: "2026-08-12T07:19:50.653Z"
last_progress: Task completed successfully.
progress_seq: 8
progress_log: ./T-099-grok-progress.log
raw_log: ./T-099-grok-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-099-grok-output.log
started_by_pid: 87681
last_stream_event: process_alive
last_update: "2026-08-12T07:19:35.732Z"
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

# T-099-grok — grok (background, done)

Output streaming to `T-099-grok-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/11413 chars; complete parsed output is available through `hopper-dispatch --result T-099-grok --full`)_

````
I'll do a read-only adversarial design review of the proposed `loadTaskSpec`/brief-merge fix, grounded in the hopper-plugin sources and tests.Checking one more detail on `filter(Boolean)` vs empty-string and how dual-track secondaries were historically “successful.”# Design review: queue brief dropped without leader-tasklist

## Summary

This is a **read-only adversarial design review** of the proposed fix for the silent brief-drop in `loadTaskSpec` / queue-path `resolveDispatch` (hopper-plugin **v0.54.0**). Defect mechanics match the brief: miss/ENOENT paths return a **lying** placeholder that becomes `taskSpec`, while `task.brief` never reaches `composePrompt`, yet dispatch still exits green. **Recommended design: 甲 (detailed ?? brief), `loadTaskSpec` → `string|null`, no placeholder in the vendor prompt, fail-closed when both empty after trim, export + direct tests.** One **blocking adjacent hole**: dual-track H2s like `## T-088 / T-089` make the **second** id a regex miss today — same drop path; brief fallback alone leaves those tasks under-spec’d.

## Files touched

none (review only; no edits, no process start/stop, gateway/`~/.openclaw` untouched)

## Acceptance verification (4/4 design questions + surfaces)

### Q1 — When a detailed spec exists, also merge queue brief?

**Choice: 甲 — `taskSpec ?? brief` (prefer one; detailed wins).**

| Evidence | Location |
|---|---|
| Scaffold contract: full spec lives in `leader-tasklist.md`; queue Brief is the short row text | `cli/src/scaffold.js:249-260` |
| Adhoc path is already “brief IS the spec” | `cli/src/dispatch.js:128-129`, `:162-164` |
| Placeholder **claims** fallback, not merge | `:220`, `:229` |
| `composePrompt` must stay untouched (byte-locked) | `cli/src/tasks.js:160-170`; `tests/unit/tasks.test.js:130/138/150/155` |
| Real dogfood queue: tasks with both use brief as **short summary**, leader-tasklist as **full AC** | e.g. T-001 brief ~123 chars vs multi-line `## T-001` section |

**Why not 乙:**
1. **Authority model** is “leader-tasklist is the contract”; always merging invites stale/short brief vs updated AC, with no precedence rule for the vendor.
2. **`taskTextRequestsReadOnly` already joins `task.brief` + `taskSpec`** (`dispatch.js:254-261`). Folding brief into `taskSpec` **duplicates** brief in that join (filter keeps both). Under 甲 + detailed hit, no duplicate; under brief fallback, `taskSpec === brief` → brief appears twice — harmless for the RO regex, still worse if you also always-merge long texts.
3. The **actual bug** is “no detailed section → empty work”; not “vendor lacked the one-line queue title when AC was present.”

**Tradeoff (accepted):** constraints that exist **only** in Brief while a leader section also exists will **not** enter the prompt (sandbox may still see them via `task.brief`). That matches the scaffold contract: put load-bearing text in leader-tasklist (or omit the section and let Brief be the sole spec).

---

### Q2 — How should `loadTaskSpec` change?

**Recommended shape:**

```text
loadTaskSpec(hopperDir, taskId) → Promise<string | null>
  - hit: trimmed section string
  - miss / ENOENT: null
  - other IO: rethrow (keep current throw path)
  - signature stays (hopperDir, taskId) — do NOT take task
  - export for unit tests of extraction

resolveDispatch call site (task already in scope at :93/:113):
  const detailed = await loadTaskSpec(hopperDir, taskId);
  const brief = typeof task.brief === 'string' ? task.brief.trim() : '';
  // prefer truthy non-empty detailed; '' must not block fallback (use && trim, not ?? alone)
  const taskSpec = (detailed && detailed.trim()) || brief || null;
  if (!taskSpec) throw new Error(...);  // see Q4
  composePrompt(frame, taskSpec, { governance });  // never null/undefined (constraint 6)
```

| Option | Verdict |
|---|---|
| Return `null`, caller falls back | **Yes** — pure I/O loader; composition at call site |
| Change signature to take `task` / merge inside | **No** — mixes FS extraction with product coalesce; harder to unit-test extraction vs policy |
| Export | **Yes** — today only reachable via `resolveDispatch`; dual-track regex needs direct cases |
| Return `''` + `?? brief` | **No** — `'' ?? brief` stays `''` (nullish only); use empty-string-aware coalesce |

Constraint 6: `composePrompt` does `taskSpec.trim()` (`tasks.js:169`) — any `null`/`undefined` is a loud TypeError. Coalesce **before** compose; do not rely on the throw as product UX.

---

### Q3 — Honest copy for the two lying paths; keep placeholders in the prompt?

**Delete both placeholders from the vendor-facing `taskSpec`.**

| Path today | Lie | After |
|---|---|---|
| `:220` section miss | “using queue.md brief only” while brief is **not** used | return `null` → caller uses brief or throws |
| `:229` ENOENT | same | same |

- **If brief is used as the sole spec:** put **only** the brief text into `## Task spec` (mirror adhoc / `dispatch-governance.test.js:89-90`). No diagnostic prose inside the prompt.
- **Optional operator signal (stderr / `--resolve` notice), not vendor prompt:** e.g. `notice: no leader-tasklist section for T-090; using queue Brief as taskSpec`. That closes the false-confidence loop documented in `ISSUE-queue-brief-dropped-without-leader-tasklist.md` (`--resolve` prints Brief + composed length while prompt lacks brief).
- **Do not** replace the lie with a softer lie still claiming brief inclusion unless the code path has already committed the brief into `taskSpec`.

---

### Q4 — Fail-closed when spec and brief are both empty?

**Throw (fail-closed). Mirror adhoc/swarm.**

| Parallel | Evidence |
|---|---|
| Adhoc | `dispatch.js:148-149` rejects empty brief |
| Swarm | `dispatch.js:191-192` same |
| Queue empty Brief default | `queue.js:140` → `''` (not null) |

**Fixture impact (constraint 2):**

| Fixture | Brief | leader-tasklist | Fail-closed? |
|---|---|---|---|
| `tests/unit/host-detect.test.js:147-150` | `"test"` (Brief column) | none | **Stays green** under 甲 (fallback to `"test"`) |
| `tests/unit/resolve-and-model-hints.test.js:43-48` | **no Brief column → `''`** | none (dir created empty) | **Goes red** if `resolveDispatch` / `--resolve` runs |

That red is **fixture debt, not product green**. Those tests target HOPPER-1 unregistered-vendor / model-in-Vendor diagnostics; they should set a non-empty Brief (or a one-line leader section) so the content gate and the vendor gate stay orthogonal. **Do not** keep a contentless queue path green to protect that fixture.

Whitespace-only brief: treat as empty via `.trim()` before the empty check.

---

### Unlisted impact surfaces (searched; not “not found” by one keyword)

| Surface | Effect of 甲+null+fail-closed |
|---|---|
| **`--resolve`** (`cli/bin/hopper-dispatch:961-966`) | Already prints `Brief:` and composed length separately — root of false confidence. After fix, length must grow when falling back to brief; optionally print `taskSpecSource=leader\|brief`. |
| **Sync + background + swarm-via-background** | Queue path all go through `resolveDispatch` (`:1110-1112`, `:1273-1275`); one fix covers them. Swarm/adhoc already OK. |
| **`taskTextRequestsReadOnly` / sandbox** | Brief already influences RO; fallback makes `taskSpec` carry the same RO keywords the vendor sees — **aligns** prompt and sandbox. Always-merge would double-count text. |
| **`plugins/hopper/cli/src/dispatch.js`** | Vendored twin of `cli/src/dispatch.js` — **must** `npm run sync:plugin` or the installed plugin keeps the bug. |
| **Prompt delivery / size budgets** | Longer prompts when brief was previously dropped; pointer-file path already exists for large prompts (`resolvePromptDelivery`). |
| **Dual-track H2 matcher (blocking adjacent)** | Current regex: `^##+\s+${id}\b` (`:215-217`). Dogfood `leader-tasklist.md` uses `## T-088 / T-089（...）`. **Mechanical count on this project’s queue: 12/90 task ids miss the regex**, including T-015/T-017/…/T-089 (second track) and T-090 (true absence). Second-track

... [truncated, 3413 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 194927
- end_time: 2026-08-12T07:19:50.652Z
- log: see `T-099-grok-output.log` for raw output
