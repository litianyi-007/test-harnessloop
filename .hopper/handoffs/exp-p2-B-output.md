---
task_id: exp-p2-B
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
pid: 39781
start_time: "2026-07-29T11:46:26.414Z"
end_time: "2026-07-29T11:51:58.688Z"
exit_code: 0
duration_ms: 332197
mode: background
phase: done
last_progress_at: "2026-07-29T11:51:58.689Z"
last_progress: Task completed successfully.
progress_seq: 13
progress_log: ./exp-p2-B-progress.log
raw_log: ./exp-p2-B-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p2-B-output.log
started_by_pid: 39778
last_stream_event: process_alive
last_update: "2026-07-29T11:51:56.486Z"
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

# exp-p2-B — grok (background, done)

Output streaming to `exp-p2-B-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/8663 chars; complete parsed output is available through `hopper-dispatch --result exp-p2-B --full`)_

````
I'll adversarially review harnessloop commit `3a68216` myself: inspect the change, then probe the listed attack surfaces against the parser/normalization and the eight-row table.Next I'll pull the full implementation and related parser/test code so I can attack the new field and the eight-row table.I'll extract the declaration parser and check logic next, then probe the attack surfaces with minimal fixtures.I'll inspect the code exactly as introduced in `3a68216` and run minimal attack fixtures against it.Found a likely parser-bypass: at `3a68216` the new parser may not filter fenced lines. Checking peers and whether that's still true later.Confirming whether the later fence fix covered this field, and probing a few more edge cases.Writing the adversarial review deliverable with reproducible attacks.## Summary

Adversarial review of harnessloop **3a68216** (v0.28.0: optional `Acceptance evals:` declaration vs same-round ledger). The eight-row table, fail-closed unparsable path, and G26 reverse mutations for rows 1–8 are mostly sound as *table logic*. The new field’s parser, however, reintroduces the repo’s known “discussing a marker == enabling it” class: fenced (and HTML-comment) lines are treated as real declarations, so row 2 (`absent + ledger present → red`) is bypassable to a full project green with wrong `rounds_eval_declaration_ran=1`. A second silent-zero path: no `decision.md` at all + ledger present never enters the gate. Migration silence (`absent+absent`) is intentional and documented; value-side full-width punctuation is correctly fail-closed.

## Files touched

none (review only)

## Acceptance verification (6/6 attack-surface probes)

Method: extracted `verify_protocol.py` at `3a68216` to `/tmp/vp_3a68216.py`; tempfile fixtures matching G26’s `_rae_project` scope-lock. No edits to the tree.

| # | Attack surface | Result | Evidence |
|---|---|---|---|
| 1 | Parser bypass (fences/spans) | **HIT (P0)** | See Finding 1 |
| 2 | Fail-open normalization | **OK** | `ran。` / `maybe` → `acceptance-eval-declaration-unparsable` only |
| 3 | Silent zero-check | **HIT (P0)** | See Findings 1–2 |
| 4 | Eight-row table holes/contradictions | **PARTIAL** | Logical 8 rows OK when `decision.md` exists; **missing-file state not covered** (Finding 2); diagnostic text contradicts row 6 (Finding 4) |
| 5 | Migration silence as bypass | **Documented OUT** | `absent+absent` green is intentional; not scored as defect against stated goal |
| 6 | Teeth green-by-construction | **NOTE** | G26a–h reverse mutations are real; **no fence/HTML tooth** so Finding 1 ships green under G26 |

### Finding 1 — P0: fenced template enables `ran` (false green for row 2)

**Root cause** (`parse_acceptance_eval_declaration` @ 3a68216):

```python
for line in decision_text.splitlines():  # no fence filter
    stripped = line.strip()
    if stripped.lower().startswith("- acceptance evals:"):
        return stripped.split(":", 1)[1].strip()
```

`_uncoded_lines` does not exist at this commit. Commit message claims parse is “完全同款” with `parse_review_fields`; both lacked fence filtering — same class later fixed in `da8109c` (v0.29.0) for all three `- <label>:` parsers.

**Minimal attack** (exact contents):

```text
# decision.md
# Decision

Template for future rounds (do not treat as this round's claim):

```
- Acceptance evals: ran
```

- Review: none — no third-party review this smoke round
- Reviewer: main-session
- Review verdict: n/a
- Verdict: pass
- Feedback: neutral
```

```json
# evidence/runtime/acceptance-evals.json
{"entries": []}
```

Plus G26-style `scope-lock.md` allowing `rounds/0001/evidence/`.

| | Expected (row 2: field absent + ledger present) | Actual @ 3a68216 |
|---|---|---|
| acceptance-eval kinds | `{acceptance-eval-declaration-missing}` | `{}` |
| total project violations | ≥1 from this gate | **0** |
| `rounds_eval_declaration_ran` | 0 | **1** |
| `parse_acceptance_eval_declaration` | `None` | `'ran'` |

**Control** (same fixture, delete only the three fence lines): `acceptance-eval-declaration-missing` fires. Proves the fence is load-bearing for the green.

**Sibling shape**: HTML comments also enable the marker (`<!--\n- Acceptance evals: ran\n-->` → parse `'ran'`, zero acceptance-eval violations with ledger). Still open on current HEAD; fences fixed later.

**False red twin**: fenced `ran` + no ledger → `acceptance-eval-declared-ran-without-ledger` even when author never declared.

### Finding 2 — P0: no `decision.md` + ledger → total silent green

`check_acceptance_eval_declaration` is only called inside `if decision.exists():` in `verify_round`. File-absent is a stronger “field absent” than empty decision text, but the gate never runs.

**Minimal attack**: same G26 project layout, **write ledger only**, omit `decision.md` entirely.

| | Expected (field absent + ledger → declaration-missing) | Actual |
|---|---|---|
| all violation kinds | contains `acceptance-eval-declaration-missing` | **`[]` (n=0)** |
| `rounds_eval_ledger_present` | 1 | 1 |
| declaration coverage | absent or missing violation | all declaration counters 0 (gate skipped) |

Still reproducible on current HEAD. Pre-existing nesting pattern for B2a/Feedback; **this commit’s new red path inherits it**, so the table’s row 2 is incomplete for the “no decision file” disk state.

### Finding 3 — OK: fail-closed on unparsable / full-width value punctuation

- `- Acceptance evals: ran。` + ledger → only `acceptance-eval-declaration-unparsable`
- `- Acceptance evals: maybe` + no ledger → `acceptance-eval-declaration-unparsable` (not silent absent)
- Normalization is exactly `.strip().lower()`; no punctuation stripping

Meets attack-surface (2) for the **value** side.

### Finding 4 — P2: error text suggests impossible remedy

`acceptance-eval-declaration-missing` detail says declare `ran` **or** `none — <reason> if the ledger is unrelated`. But `none + ledger present` is row 6 → `acceptance-eval-declaration-contradicts-ledger`. Agents following the error string bounce red→red. Not a green bypass; still a table/docs contradiction.

### Finding 5 — intentional: migration silence

`absent + absent = green` is documented OUT (“Narrowed, not closed”). G26e reverse mutation (add only ledger → red) proves that green is not a dead check. **Not a defect against the commit’s stated scope**; remains the residual hide path (delete ledger + omit field, or claim `none` after deleting ledger).

### Finding 6 — teeth

G26a–h cover the eight rows with reverse mutations; G26h set-equality for unparsable is a real independence check. **G26 never exercises fenced/HTML/no-decision inputs**, so Finding 1 ships under a full-green G26 suite — classic “teeth prevent regression of tested shapes, not same bug in a new surface” (exactly what v0.29.0’s commit message later says).

## Decisions / deviations

- Reviewed **code as introduced at 3a68216**, not current HEAD. Fence class was fixed in `da8109c` (v0.29.0); Findings 2 and HTML residual remain on HEAD as of this review.
- Did not treat documented migration silence as a FAIL (matches commit’s own OUT rewrite).
- Did not require live `git show` after temp extract; all attacks run against the extracted 3a68216 module.

## Open questions

- none for the verdict; residual product question (out of scope for this commit’s claim): whether missing `decision.md` should hard-fail independently of every nested gate.

## Verdict

**FAIL**

Primary reason: the new gate’s core red path (row 2: ledger without intentional declaration) is bypassable to full project green via a fenced template line (Finding 1), with a second total silent path when `decision.md` is absent (Finding 2). Fail-closed value normalization and intentional migration silence do not compensate.

## Next recommendation

1. Treat 3a68216 as **not merge-clean on its own**; require the v0.29.0 fence fix (`_uncoded_lines` on `parse_acceptance_eval_declaration`) before trusting this slice — already upstream if HEAD ≥ `

... [truncated, 663 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 332197
- end_time: 2026-07-29T11:51:58.688Z
- log: see `exp-p2-B-output.log` for raw output
