---
task_id: exp-p6-A
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
pid: 31862
start_time: "2026-07-29T13:59:59.618Z"
end_time: "2026-07-29T14:04:45.675Z"
exit_code: 0
duration_ms: 286010
mode: background
phase: done
last_progress_at: "2026-07-29T14:04:45.676Z"
last_progress: Task completed successfully.
progress_seq: 11
progress_log: ./exp-p6-A-progress.log
raw_log: ./exp-p6-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p6-A-output.log
started_by_pid: 31847
last_stream_event: process_alive
last_update: "2026-07-29T14:04:29.677Z"
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

# exp-p6-A — grok (background, done)

Output streaming to `exp-p6-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10083 chars; complete parsed output is available through `hopper-dispatch --result exp-p6-A --full`)_

````
I'll adversarially review harnessloop commit `d9989ca` myself: inspect the diff, hunt for missed defects, and write the review deliverable.Examining the new functions and surrounding gate logic in detail.Checking Python 3.9 compatibility, double-walk consistency, and edge cases the author may have missed.Working tree is behind the reviewed commit — locating `d9989ca` and reviewing that tree directly.# Adversarial Code Review — `d9989ca`

**Reviewed object**: `harnessloop` commit `d9989ca70b2eb2f7428aa247ebbb40ad9ac541c6`  
(`v0.31.0` TH-0026 scope-lock round-path mismatch hint layer)  
**Mode**: review-only · no edits · tree materialised via `git show d9989ca:…` (worktree HEAD was behind this commit)

---

## Summary

Commit `d9989ca` correctly implements the TH-0026 *hint* (not violation) for scope-lock spans that name this round’s number with the wrong path prefix. On the parent project it surfaces the claimed 6 historical cases, leaves `violations == []` / exit 0, and G31a–g give real teeth for the pure function and non-blocking integration.

The implementation still reopens the G17 “never read escaped scope-lock” invariant in the human-mode notes collector (empirically: coverage count 1, notes 2 when a symlink-escaped round is present), uses Unicode-aware `^\d{4}$` for round segments (later classed as a real TH-0026 failure mode in v0.33.2), and will false-positive on legitimate non-harnessloop paths that merely contain a `rounds/<NNNN>` segment. Core detection is good; protocol-discipline and edge correctness need rework before this is “closed.”

---

## Files touched

none (read-only review)

**Files under review (from the commit):**

| Path | Role |
|---|---|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | Core algorithm + coverage + notes collector |
| `scripts/validate.py` | G31a–g teeth |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | Mechanical-gate boundary docs |
| 4 version manifests | `0.30.0` → `0.31.0` |

---

## Acceptance verification

Task brief had no machine-checkable AC list beyond “adversarially review `d9989ca`.” Verification against the commit’s own claims:

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | Layer-internal only (no disk existence of span path) | **PASS** | `scope_lock_round_path_mismatch` only uses `round_dir.name` / `parent.parent.relative_to(project)` (`verify_protocol.py:658–734` at commit) |
| 2 | Hint only — no violations / exit code change | **PASS** | Parent project: `violations=0`; G31f/g assert `not violations` |
| 3 | Hits the 6 real shapes in this repo | **PASS** | Loaded d9989ca tree → parent: `rounds_scope_lock_round_path_mismatch=6`, notes for 0003/0005/0006 (`...`) and 0007/0008/0009 (missing `goals/<slug>/`) |
| 4 | Segment-wise not string-wise suffix | **PASS** | G31d + live probe: `xgoals/<slug>/rounds/0008/` flagged |
| 5 | G17: escaped container scope-lock never read | **FAIL** | Notes collector walks with bare `is_dir()` / `read_text` and no `_container_escape_violation` (`:3803–3840`); repro below |
| 6 | Round id is four *ASCII* digits as docs imply | **FAIL** | `ROUND_SEGMENT_RE = re.compile(r"^\d{4}$")` (`:640`); fullwidth `０００８` matches |

**G17 repro** (d9989ca code, temp tree: legitimate mismatch round `0001` + symlink `0002` → outside):

```
coverage_mismatch = 1
coverage_rounds   = 1
viol kinds        = {round-container-escapes-project}
notes_count       = 2   # includes escaped 0002
```

So human notes can (a) over-report vs coverage and (b) read `scope-lock.md` outside the project — the exact class SKILL.md still forbids in the bullet *above* the new field (`SKILL.md:448`).

---

## Findings (author-miss class)

### F1 — MUST FIX · G17 hole in `collect_scope_lock_round_path_mismatch_notes`

**Where**: `verify_protocol.py:3803–3840` vs `verify_project` walk at `:3887–3931`

`verify_project` containment-checks `goals_dir` / each `goal_dir` / each `round_dir` and **skips** escaped rounds without reading their scope-lock (PR-2 / G17). The notes collector re-walks with:

```python
for goal_dir in sorted(p for p in goals_dir.iterdir() if p.is_dir()):
    ...
    for round_dir in sorted(p for p in rounds_dir.iterdir() if p.is_dir()):
        ...
        spans = extract_allowed_spans(scope_lock.read_text(...))
```

`Path.is_dir()` follows symlinks. Effects:

1. **Reads outside the project** when `rounds/<n>` is a symlink escape — contradicts `SKILL.md:448` (“scope-lock included, is never read”).
2. **Coverage ↔ notes drift**: count from `verify_round` can be `N` while notes print `N+K` escaped extras (repro: 1 vs 2).
3. No G31 coverage of the collector path (G31f/g only assert `verify_project` coverage/violations).

**Fix shape**: mirror `verify_project` (and the later `collect_zero_inspected_round_notes` pattern): `_container_escape_violation` at each level before `read_text`; ideally derive notes from the same pass that increments coverage so the two cannot drift.

---

### F2 — MUST FIX (correctness class) · `ROUND_SEGMENT_RE` uses bare `\d`

**Where**: `verify_protocol.py:640`

```python
ROUND_SEGMENT_RE = re.compile(r"^\d{4}$")
```

Python 3 `re` treats `\d` as Unicode decimal digits by default. Confirmed:

- `re.match(r'^\d{4}$', '０００８')` → match  
- `re.match(r'^[0-9]{4}$', '０００８')` → no match  

**Failure mode**: span `…/rounds/０００８/…` with ASCII round dir `0008` → regex matches the fullwidth token → `segments[i+1] != round_name` → treated as **different round** (OUT list item 2) → **silent miss**. Same class of bug later fixed repo-wide in `6c92440` (v0.33.2), which explicitly names `ROUND_SEGMENT_RE` / TH-0026.

**Fix**: `r"^[0-9]{4}$"` (and a tooth that fullwidth does not match).

---

### F3 — SHOULD FIX · False positive on non-harnessloop `rounds/<NNNN>` paths

**Where**: algorithm step 1–4 at `:707–734`

Any Allowed Changes span whose **first** `rounds/<this-round>` pair has a non-suffix prefix is flagged. Live probe:

```
app/game/rounds/0008/level.json  →  FLAGGED
```

That is a plausible real scope-lock for game/content trees. Hint-only, so it does not fail the gate, but it injects noise into the signal TH-0026 exists to make trustworthy.

**Mitigations** (pick one): require span prefix to start with `.harnessloop` / `goals` / be under known harnessloop roots before judging; or only run when the span’s first `rounds/<n>` is the path *being authorized as this round’s directory*, not any substring.

---

### F4 — NOTE · First `rounds/<NNNN>` only

**Where**: `:705–709` (`break` on first match)

```
.harnessloop/rounds/0007/../rounds/0008/  →  not flagged
```

First pair is `rounds/0007` (different round → `None`); later wrong-prefix `rounds/0008` never inspected. Rare, but the “first match” rule is undocumented in SKILL OUT list.

---

### F5 — NOTE · Docs claim “JSON coverage schema unchanged”

**Where**: `verify_protocol.py:4077–4079`, commit message; vs `_empty_coverage` key at `:3723` and SKILL `:449`

Notes correctly stay human-only, but a **new** `coverage` key is always present in `--json`. That is an additive schema change. SKILL is more honest (“does not appear in `--json` beyond the coverage count”); the `main()` comment overclaims.

---

### F6 — NOTE · G31 gaps

G31a–g nail the pure function and non-blocking integration well (especially G31d’s anti-`endswith` fixture). Missing teeth that would have caught F1–F3:

- no test that `collect_*` skips escaped containers / note count == coverage  
- no fullwidth/`\d` case  
- no `app/.../rounds/0008/...` non-flag control  
- no literal `...` placeholder span (covered only indirectly by “wrong segment”)

---

## What is solid (credit)

- E1 discipline: hint not violation is the right demotion for already-closed rounds; matches TH-0008 precedent.
- Layer-internal operands only: avoids the disk-existence join two reviews already killed for evals.
- Real self-host hit rate: 6/6 on parent project, including the surprising `...` placeholder shape.
- G31d is a genuine dest

... [truncated, 2083 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 286010
- end_time: 2026-07-29T14:04:45.675Z
- log: see `exp-p6-A-output.log` for raw output
