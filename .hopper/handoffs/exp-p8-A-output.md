---
task_id: exp-p8-A
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
pid: 63328
start_time: "2026-07-29T14:11:12.809Z"
end_time: "2026-07-29T14:16:48.750Z"
exit_code: 0
duration_ms: 335895
mode: background
phase: done
last_progress_at: "2026-07-29T14:16:48.751Z"
last_progress: Task completed successfully.
progress_seq: 13
progress_log: ./exp-p8-A-progress.log
raw_log: ./exp-p8-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p8-A-output.log
started_by_pid: 63327
last_stream_event: process_alive
last_update: "2026-07-29T14:16:42.995Z"
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

# exp-p8-A — grok (background, done)

Output streaming to `exp-p8-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/11945 chars; complete parsed output is available through `hopper-dispatch --result exp-p8-A --full`)_

````
I'll review commit `a69ae03` adversarially: first inspect the full diff and context, then write the structured review deliverable.Locating the matching task brief and pulling the full commit diff for deep review.Diving into the core implementation: anomaly logic in `verify_protocol.py` and the G33 tests in `validate.py`.I have enough evidence for a hard REWORK. Writing the structured adversarial review deliverable.# Adversarial Code Review — `a69ae03`

**Reviewed object**: `harnessloop` commit `a69ae03d6179cdd07dac82fdd8086051e07e25d3`  
(`v0.33.0` — batch 2 §4 anomaly layer + §5 canonical contract fields + Appendix B.1 / X1 partial close)  
**Mode**: review-only · no edits · tree materialised via `git show a69ae03:…` (worktree HEAD is later; defects re-checked on current tree and still present)

**Assumption (1 line)**: Acceptance surface = commit claims + SKILL Mechanical Gate Boundary / OUT list + G33 teeth intent (brief had no separate AC list).

---

## Summary

Commit `a69ae03` lands a real, carefully designed soft anomaly signal (`loop_autocontinue_anomaly` / `loop_anomaly_skipped_unparsable`), pairs it with one hard violation (`loop-contract-profile-missing`), and adds G33a–i (20 `check()` calls) plus status/continue prose for acknowledgement. Core happy-path logic (standard+yes+positive+all-valid → count 1; strict/no/missing-health → determinate 0; Predecessor-only activation → B.1 red; fence-shadow control) works and is empirically tested.

It does **not** close the X1 “switch held by the audited party” story it claims. The template this same commit introduces (`- Profile: lite | standard | strict | custom`) is a present-but-unrecognized value that **bypasses B.1** while permanently silencing the anomaly into `skipped_unparsable`. Evidence-index aggregation also violates the module’s own Kleene rule: one unparsable health cell swallows a row that is already determinately `missing`. Together with setup still writing only the old “24-field” body, B.1 is easy to never fire in real projects. Verdict is **REWORK**.

---

## Files touched

none (read-only review)

**Files under review (from the commit):**

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | anomaly gate + B.1 + parsers (+563) |
| `scripts/validate.py` | G33a–i teeth (+375) |
| `plugins/harnessloop/skills/harnessloop-{continue,status,loop}/SKILL.md` | consumption + OUT list |
| `…/references/control-contract-{template,profiles}.md` | §5 canonical field surface |
| four version manifests | `0.32.0` → `0.33.0` |

---

## Acceptance verification (5/5)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Diff reviewed at exact commit `a69ae03` (not HEAD) | **PASS** | `git show a69ae03 --stat` → 11 files, +995/−19; isolated import of that blob’s `verify_protocol.py` |
| 2 | Core trigger table (lite/standard fire; strict/no/missing-health don’t; latest-only) | **PASS** | G33a/b/c/d/i shape; live: Profile=`standard` → `anomaly=1`; `strict`/`custom` → 0; Feedback negative → 0 |
| 3 | B.1 activation via `Predecessor:` alone (no `Loop continuation:`) | **PASS** | G33g; live: missing Profile + `- Predecessor: 0001` → `loop-contract-profile-missing` |
| 4 | X1 kill-switch really closed for common contract shapes | **FAIL** | Template / empty / garbage Profile: B.1 silent, anomaly never fires (F1) |
| 5 | Evidence precondition follows stated Kleene polarity | **FAIL** | `missing` + annotated `valid（…）` → `unparsable`, not determinate False (F2); contradicts `_kleene_and` docstring |

---

## Findings

### F1 — MUST FIX · Template / empty / garbage `Profile:` defeats Appendix B.1

**Where**  
- B.1 predicate: `verify_protocol.py:4001` — only `profile_raw is None`  
- Enum normalize: `:3663–3670`, `:3595`  
- Template this commit adds: `control-contract-template.md:11–13`  
- Setup still “24-field content” only: `harnessloop-setup/SKILL.md` S4 (unchanged by this commit)

**Mechanism**  
B.1 fires only when the field line is **absent**. If the line is present with any non-enum text, `profile_raw is not None` → no violation; `_normalize_bare_enum` → `None` → anomaly condition unparsable → permanent skip.

**Live repro** (blob `a69ae03`, activated project with positive feedback + all-valid evidence):

| `Profile:` value | B.1 violation? | anomaly | skip |
|------------------|----------------|---------|------|
| *(line absent)* | **yes** | 0 | 1 |
| *(empty / whitespace)* | **no** | 0 | 1 |
| `lite \| standard \| strict \| custom` **(template default)** | **no** | 0 | 1 |
| `Standard (default)` | **no** | 0 | 1 |
| `standard` | no | **1** | 0 |

The template values this commit introduces are the default shape a half-filled contract keeps. Setup S4 still instructs agents to write the **old 24 free-text leaves**, and profiles.md explicitly says the three canonical fields are **not** in `check_setup`’s completeness manifest — so nothing forces a concrete `Profile: standard`. Once any round writes `- Predecessor:` (optional, migration-silent), the project is “activated” but B.1 never goes red, and the anomaly never can.

**Same class**: `- Auto-continue on positive: yes | no` (template line 12) is an independent silent kill switch with **no** B.1 twin.

**Why author missed it**: G33f/g only exercise true field omission; G33 never fixtures empty line, template multi-value string, or “present but not in enum.” The commit even records fixing “file missing” false positives on G32 fixtures — attention was on absence of the **file**, not on present-but-placeholder **values**.

---

### F2 — MUST FIX · Evidence-index aggregation is not Kleene (swallows determinate `False`)

**Where**: `check_evidence_index_all_valid` `:3769–3778` vs `_kleene_and` `:3781–3803`

```text
for row in data_rows:
    ...
    if value not in EVIDENCE_ARTIFACT_HEALTH_ENUM:
        return None, True   # early exit — forgets any prior missing/stale
    if value != "valid":
        all_valid = False
```

Top-level docstring of `_kleene_and` correctly states: known `False` wins over unknown. **Within** the evidence table that is not implemented: any single non-enum cell (real project style `valid（静态级；e2e 部分 blocked）`) forces the **entire** evidence condition to unparsable, even when another row is already bare `missing`.

**Live repro**:

| rows | result |
|------|--------|
| `valid` + `missing` | determinate not-all-valid (`anomaly=0`, `skip=0`) |
| `valid` + `valid（…）` | unparsable (`skip=1`) |
| **`missing` + `valid（…）`** | **unparsable (`skip=1`)** ← should be False under stated Kleene |

Commit message correctly diagnoses the parent project’s E8 annotation. The `_kleene_and` docstring (`:3795–3797`) incorrectly claims the real run was “E4 determinately not all valid” — that story is false under this implementation whenever any annotated cell exists alongside E4. F2 is both a logic bug against stated semantics and a self-contradiction in the same batch’s comments.

---

### F3 — SHOULD · `$harnessloop-continue` step 4 assumes a verify run that only step 3 (positive-only) may have performed

**Where**: `harnessloop-continue/SKILL.md:30–31` (steps 3–4 at `a69ae03`)

- Step 3: run `verify_protocol.py` **only if** latest feedback is `positive`.  
- Step 4: “Read **that same** `verify_protocol.py --json` run’s …” for anomaly / B.1.

For non-positive feedback there is no “same run.” Agents following the text literally can skip anomaly/B.1 surfacing on the path where human acknowledgement is still required. Status skill always runs verify — continue is the weaker of the two consumers.

---

### F4 — SHOULD · G33 teeth miss the kill-switch shapes that matter

20 checks / 9 letters match `500 → 520`. Paired mutations on G33a/b/d/g/h are real.

Missing teeth that would have caught F1/F2:

| Missing fixture | Would catch |
|-----------------|-------------|
| Profile line empty / `lite \| standard \| …` after activation → must B.1 **or** must not silently skip

... [truncated, 3945 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 335895
- end_time: 2026-07-29T14:16:48.750Z
- log: see `exp-p8-A-output.log` for raw output
