---
task_id: exp-p10-B
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
pid: 63395
start_time: "2026-07-29T14:11:13.247Z"
end_time: "2026-07-29T14:15:51.042Z"
exit_code: 0
duration_ms: 277745
mode: background
phase: done
last_progress_at: "2026-07-29T14:15:51.043Z"
last_progress: Task completed successfully.
progress_seq: 11
progress_log: ./exp-p10-B-progress.log
raw_log: ./exp-p10-B-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p10-B-output.log
started_by_pid: 63388
last_stream_event: process_alive
last_update: "2026-07-29T14:15:43.429Z"
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

# exp-p10-B — grok (background, done)

Output streaming to `exp-p10-B-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10955 chars; complete parsed output is available through `hopper-dispatch --result exp-p10-B --full`)_

````
I'll adversarially review harnessloop commit `00b6c73` myself: inspect the diff, then hunt the listed defect families and write the review deliverable.Next I'll compare the new note collector with `verify_round`'s zero-inspected path and inspect related helpers for drift and silent-zero risks.Reproducing the suspected coverage↔notes drift and checking a few edge cases against the live tree.Checking one more honesty angle: whether the note path can still surface outside the project, and whether `collect_zero_inspected_round_notes` exists at commit `00b6c73` with the claimed line numbers.# Adversarial Code Review — `00b6c73`

**Reviewed object**: `harnessloop` commit `00b6c7368f2bae06dce0a4f25ceeb0c60953b768`  
(`v0.33.3` — break out `rounds_zero_inspected` by round name)  
**Mode**: review-only · no edits  
**Assumption**: deliverable is this review body (hopper task `exp-p10-B`); no separate AC list beyond the commit’s own claims + the six attack families in the brief.

---

## Summary

Commit `00b6c73` does the narrow thing it advertises on a normal tree: human-mode only, no new violation kinds, no new coverage keys, exit code unchanged, and on this parent project it prints **9** `note (non-blocking, informational)` lines matching `zero_inspected=9`. G36a–c give real reverse-mutation and subprocess-exit teeth for the happy path.

It does **not** keep its central correctness claim. The notes collector re-walks `goals/*/rounds/*` **without** the G17 containment checks that `verify_project` applies to `goal_dir` / `round_dir`, so a symlink-escaped round that is **skipped** by the real gate (and does **not** increment `rounds_zero_inspected`) still gets an informational note. That falsifies the docstring/commit promise that “a round reported here is always exactly one of the rounds that already incremented the real coverage field.” Repro below: `zero_inspected=1`, notes=2.

---

## Files touched

none (read-only review)

**Files under review (from the commit):**

| Path | Role |
|---|---|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `collect_zero_inspected_round_notes` + `main()` print hook |
| `scripts/validate.py` | G36a–c teeth |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN-column legibility sentence |
| 4 version manifests | `0.33.3` bump |

---

## Acceptance verification (6/6 claims checked)

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | No new violation kind / no new coverage key / no exit-code change for zero-inspected-only projects | **PASS** | G36c: subprocess exit 0; live parent `--json` has same top-level shape; collector only `print`s notes |
| 2 | Human-mode names each zero-inspected round | **PASS** (happy path) | Live parent: `zero_inspected=9` and 9 informational notes |
| 3 | Notes are non-blocking / wording denies “this is a defect” | **PASS** | Note text includes “not a violation, and it does not mean this round has a problem”; printed only outside exit path |
| 4 | “Same primitives as `verify_round` ⇒ notes always ⊆ coverage increments” | **FAIL** | Attack A: `zero_inspected=1`, notes=2 (escaped `0002` noted but not counted) |
| 5 | G36 teeth prove non-vacuous count + real exit 0 | **PASS_WITH_GAP** | G36a reverse mutation + G36b multi-round + G36c subprocess are real; **no** tooth for notes↔coverage parity under G17 escape |
| 6 | SKILL OUT/IN honesty vs code | **PARTIAL** | SKILL correctly says human-only / not in `--json`; overclaims “legibility layer over **the same count**” when counts can diverge |

### Live parent (happy path)

```
zero_inspected=9
informational notes=9
TH-0026 notes=6
violations=0
exit 0
```

---

## Findings (author-miss class)

### F1 — MUST FIX · G17 walk hole + falsified no-drift guarantee

**Where** (at `00b6c73`):  
- Collector walk: `verify_protocol.py:4937–4941` — bare `is_dir()` on `goal_dir` / `round_dir`  
- Real gate walk: `verify_protocol.py:5065–5090` — `_container_escape_violation` on each level, **skip** on escape  
- False guarantee: docstring `4885–4902` and commit body (“不会漂成第二套定义”)

**What happens**

`verify_project` containment-checks `goal_dir` and `round_dir` and **never** calls `verify_round` on an escaping round, so that round contributes **0** to `rounds_zero_inspected`.

`collect_zero_inspected_round_notes` only containment-checks `evidence/` and `reviews/` *inside* whatever `round_dir` `Path.is_dir()` followed. An escaping `rounds/0002 -> <outside>` is still entered, classified as zero files, and noted.

The author reused the *inner* primitives of `verify_round` but not the *outer* walk discipline of `verify_project` — the exact family already called out on the sibling `collect_scope_lock_round_path_mismatch_notes` path.

**Minimal reproducible attack**

```bash
# exact tree
PROJ=/tmp/adv-00b6c73-A
rm -rf "$PROJ" && mkdir -p "$PROJ" "$PROJ/outside" \
  "$PROJ/p/.harnessloop/goals/g1/rounds/0001"
printf '%s\n' '## Allowed Changes' '' '- `app/`' > "$PROJ/outside/scope-lock.md"
printf '%s\n' '## Allowed Changes' '' '- `app/`' > \
  "$PROJ/p/.harnessloop/goals/g1/rounds/0001/scope-lock.md"
ln -s "$PROJ/outside" "$PROJ/p/.harnessloop/goals/g1/rounds/0002"

python3 harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py \
  --project "$PROJ/p"
```

**Expected** (per docstring/commit guarantee):  
`zero_inspected=1` and **exactly 1** informational note (only `…/0001`). Escaped `0002` is a `round-container-escapes-project` violation only.

**Actual** (observed):

```
exit=1
zero_inspected=1
informational notes=2   # includes …/rounds/0002
viol kinds ⊇ {round-container-escapes-project}
```

Same shape with **escaped `goal_dir`** (symlink `goals/g2 -> outside_goal` with a nested empty round): coverage `zero=1`, notes=2.

**Why this matters even though notes are “informational”**

1. The feature’s value *is* “the number, broken open.” If notes ≠ count, the breakdown is not a breakdown of that number.  
2. Written guarantee is false (OUT-column / docstring honesty — attack family 6).  
3. `Path.is_dir()` follows the escape; the collector stats outside the project (G17 spirit). It does not `rglob` outside when evidence/reviews fail containment, so this is weaker than the sibling scope-lock reader hole, but still a real second definition of “zero-inspected rounds.”

**Fix shape**: mirror `verify_project` — `_container_escape_violation` on `goals_dir` / each `goal_dir` / each `round_dir` before any work; **skip** on escape (silent for notes; the violation is already emitted by the main walk). Add G36d: fixture with one clean zero round + one escaped round → `len(notes) == coverage["rounds_zero_inspected"] == 1`.

---

### F2 — NOTE · Escape folded into “neither exists” (documented, still misleading)

**Where**: `4946–4959` + docstring `4921–4927`

When `evidence/` is a symlink escape and `reviews/` is absent:

- coverage correctly sets `rounds_zero_inspected=1` and emits `round-container-escapes-project`
- note reason is **`evidence/ and reviews/ neither exists`**

Docstring admits the fold. Repro’d. Not a silent-zero gate switch (violation is loud). Residual: a reader of notes alone cannot see “escape” vs “absent.”

---

### F3 — NOTE · G36 teeth miss the load-bearing invariant

**Where**: `scripts/validate.py` G36a–c at `00b6c73`

| Tooth | What it proves | What it misses |
|---|---|---|
| G36a | empty round → `zero_inspected=1`; add `reviews/file` → 0 | never calls the notes collector; reverse mutation does not assert notes clear |
| G36b | two empties → count 2; notes name both | never asserts `len(notes) == coverage["rounds_zero_inspected"]` under mixed/escape load |
| G36c | real subprocess exit 0 + banner + one note line | no equality to count; no G17 fixture |

Three reason-tier strings are **untested**. No destructive counterproof against a second walk definition (attack family 5 partial). Happy-path teeth are real; they would stay green with F1 present.

---

### F4 — NOTE · “Never raises” is aspi

... [truncated, 2955 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 277745
- end_time: 2026-07-29T14:15:51.042Z
- log: see `exp-p10-B-output.log` for raw output
