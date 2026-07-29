---
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
end_time: "2026-07-29T14:16:37.092Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 324378
adapter_status: success
last_progress_at: "2026-07-29T14:16:37.093Z"
last_progress: Task completed successfully.
progress_seq: 12
terminal_event_emitted: true
---
# exp-p7-B · code-review-adversarial · harnessloop `7fa902f` (v0.32.0)

**Target:** `7fa902fb97e86dfd2552cfbb3f36f8c6d084e3bf` — batch-2 force layer + record layer (Appendix F reverse: `Predecessor:` not forward `continued:`)  
**Method:** read-only; `git show 7fa902f` + independent tempfile probes that load **only** the commit blob of `verify_protocol.py` (not working-tree HEAD). No edits to the repo.  
**Assumption:** no finer acceptance list was provided beyond the six attack-surface families in the brief; judged against those families plus the commit’s own claims (two structural predecessor constraints, enum-only continuation record, `_uncoded_lines`, G32a–j paired teeth, three OUT bounds in SKILL.md).

---

## Summary

Commit `7fa902f` correctly reverses the unwritable forward `continued:` design into a successor-declared `Predecessor: <NNNN>`, adds an enum-only `Loop continuation: stopped: <reason>` record gate, routes both parsers through `_uncoded_lines`, bumps all four version manifests to 0.32.0, and ships solid G32a–j paired mutations for the happy/error paths the author thought about (missing, forward, self, invalid token, absence, enum membership, unjustified-stop coverage, free-text note, fence shadowing, full-width period on the *value*).

Two ship-blocking false-green paths remain on the predecessor gate: (1) a textbook silent zero-check — `except ValueError: return [], state` when `int(round_dir.name)` fails — which disables every predecessor constraint while still ticking `rounds_predecessor_declared=1`; (2) `PREDECESSOR_VALUE_RE = r"^\d{4}$"` (and `int()`) accepting full-width digits, so a full-width-named predecessor directory plus a full-width value goes green under a claim of “exactly four digits.” SKILL OUT overclaims that once declared the field “must resolve to a real, strictly-earlier round.” Verdict: **REWORK**.

---

## Files touched

none (read-only review; deliverable is this handoff file only)

Reviewed at `7fa902f` (no edits):

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `check_loop_predecessor_declaration` / `check_loop_continuation_declaration` (+~320 lines) |
| `scripts/validate.py` | G32a–j teeth (+~340 lines) |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | coverage IN + three new OUT bullets |
| `plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md` | two optional field lines |
| `package.json`, `.claude-plugin/marketplace.json`, `plugins/harnessloop/.claude-plugin/plugin.json`, `plugins/harnessloop/.codex-plugin/plugin.json` | version → 0.32.0 (all four consistent) |

---

## Acceptance verification (6/6 attack-surface families)

### 1. Parser bypasses (inline / fence / full-width punctuation) — **PASS_WITH_NOTE**

| Probe | Result |
|-------|--------|
| Fenced bad `Predecessor: 0009` then unfenced good `0003` | green (matches G32i claim) |
| Same two lines with fences removed | `loop-predecessor-not-backward` (G32i mutation holds) |
| Only fenced bad value, no unfenced declaration | absence, `predecessor_declared=0` |
| Continuation: fenced bad + unfenced `goal-achieved` | green, `stop_recorded=1` |
| Value-side full-width period `stopped: goal-achieved。` | `loop-continuation-invalid-value` only (G32j holds) |
| Label-side full-width colon `- Predecessor：0003` (U+FF1A) | parsed as **absent** (same family as historical Feedback： escape) |
| 4-space indented bad line shadowing good | red on first unfenced/indent line — **documented OUT** |

No new fence-state-machine regression on the new fields. Label-side full-width colon is a known family defect; for an *optional* field, pure omission is an easier silence path, so this is secondary to F1 (coverage still stays 0 when the label is not recognized).

### 2. Silent zero-check — **FAIL (MUST-FIX)**

Smoking gun in `check_loop_predecessor_declaration` at this commit:

```python
try:
    current_round_num = int(round_dir.name)
except ValueError:
    return [], state   # zero violations, declared stays True
```

**Minimal attack (exact tree):**

```
project/.harnessloop/goals/g1/rounds/not-a-number/scope-lock.md
project/.harnessloop/goals/g1/rounds/not-a-number/decision.md:
  # Decision

  - Predecessor: 9999
```

| | |
|--|--|
| **Expected** | `loop-predecessor-not-backward` (9999 is not strictly before this round), **or** fail-closed on an unparseable round directory name |
| **Actual** | **zero** `loop-*` violations; `rounds_predecessor_declared == 1` |
| **Control** | same `decision.md` under `rounds/0007/` → `loop-predecessor-not-backward` |

Same silent green with `Predecessor: 0001` when `0001` does not exist (existence check never runs). The switch is the round’s **own directory name**, chosen by the party being gated. G32 never exercises a non-`NNNN` round dir, so this path has no destructive counterproof in teeth.

### 3. Regex class traps (`\d` vs `[0-9]`, `int()` Unicode) — **FAIL (MUST-FIX)**

At `7fa902f`:

- `PREDECESSOR_VALUE_RE = re.compile(r"^\d{4}$")`  (not `[0-9]{4}`)
- `ROUND_SEGMENT_RE` in the same file is also `^\d{4}$` (pre-existing, same class)
- Empirical on this Python: `re.match(r'^\d{4}$', '０００３')` → match; `int('０００３')` → `3`

**Minimal attack 2:**

```
rounds/０００３/decision.md   # full-width digits U+FF10–FF19
rounds/0007/decision.md:
  - Predecessor: ０００３
```

| | |
|--|--|
| **Expected** under the commit’s “exactly four digits” / project `NNNN` convention | `loop-predecessor-invalid-value` (or equivalent reject of non-ASCII digit values) |
| **Actual** | **zero** `loop-*` violations (format passes, arithmetic uses `int` → 3 < 7, `is_dir()` on the full-width path succeeds) |

Note: full-width **value alone** without a matching full-width directory fails closed as `loop-predecessor-missing` (wrong kind, still red). The green path needs the parallel full-width directory. Still a real, reproducible false-green under the stated format claim.

### 4. Cross-time-layer joins — **PASS (honestly bounded)**

- Arithmetic (`raw` vs `round_dir.name`) is same-round operands when the dir name parses.
- Existence is **today’s disk** under the same goal’s `rounds/` — documented in SKILL OUT with the TH-0027 family and the backward-vs-forward asymmetry.
- Other-goal `0003` does not satisfy same-goal existence → `loop-predecessor-missing` (correct).
- No new retroactive-reddening path beyond the already-registered deletion-of-past OUT.

### 5. Teeth quality — **PARTIAL**

G32a–j are real paired mutations (green + minimal flip → red) for the paths they name. Gaps:

| Missing counterproof | Consequence |
|----------------------|-------------|
| Non-numeric / non-`[0-9]{4}` round directory that still declares `Predecessor:` | F1 silent path is green by construction in the test suite |
| Full-width digit value and/or directory | F2 green path untested; G32d only tries `abc` |
| Label-side full-width colon | no tooth |

G32i (fence) and G32j (value full-width period) are strong for their claims.

### 6. OUT-column honesty — **FAIL (overclaim)**

SKILL.md at this commit (OUT) states the gate can guarantee:

> once you declare `Predecessor:`, it must resolve to a real, strictly-earlier round

F1 falsifies that: declare `Predecessor: 9999` under `rounds/not-a-number/` → declare happened, resolution constraints never ran, exit path is clean on `loop-*`. Coverage still reports `predecessor_declared=1`, which reads as successful utilization.

What OUT **does** get right (and matches code):

- absence of the field is silent (zero-migration)
- stop reason is enum-only, not honesty-checked; `unjustified-stop` is legal + separate counter
- existence uses today’s disk; deletion of past can redden citers
- 4-space indented code blocks still visible to parsers
- three upper bounds explicitly entered SKILL, not only the spec

---

## Findings

| ID | Sev | Family | Finding |
|----|-----|--------|---------|
| **F1** | **MUST-FIX** | Silent zero-check | `except ValueError: return [], state` after `int(round_dir.name)` zeros the entire predecessor gate while leaving `declared=True`. Repro: `rounds/not-a-number` + `- Predecessor: 9999` → 0 loop violations; control under `0007` → `not-backward`. |
| **F2** | **MUST-FIX** | Regex `\d` / `int()` Unicode | `PREDECESSOR_VALUE_RE = ^\d{4}$` accepts full-width digits; with a full-width-named predecessor dir, value `０００３` is green. |
| **F3** | Medium | OUT honesty | SKILL claims “once declared → real strictly-earlier round”; F1 is a counterexample. Docstring even describes the silent path as intentional (“left unvalidated rather than crashing”) without registering it as an OUT switch. |
| **F4** | Low | Teeth gap | G32a–j never open F1/F2; green-by-construction for those paths. |
| F5 | Note | Parser (optional field) | Full-width label colon → absence (not unparsable). Secondary for optional fields. |
| F6 | Note | Symlink predecessor | `is_dir()` accepts a symlink at `rounds/NNNN` pointing outside the goal. Spec only requires a directory entry under same-goal `rounds/`; not claimed as identity-hard. |

**Not defects (by design / honest OUT):**

- Field absence silence (migration / “once declare, self-consistent”)
- `unjustified-stop` not red
- No judgment of stop-reason honesty
- No mandate to write `Predecessor:`
- Existence on today’s disk (registered TH-0027-class)
- 18-member enum matches spec §3.1 transcription
- Version manifests all `0.32.0` (including `.codex-plugin`)
- Continuation fail-closed on garbage / full-width value punctuation
- Fence routing for both new fields

---

## Decisions / deviations

- Reviewed the **exact `7fa902f` blob**, not post-fix HEAD (later history may have closed F1/F2; that does not change this commit’s verdict).
- Did not treat “non-numeric round dirs are rare” as mitigating F1: `verify_project` enumerates whatever sits under `rounds/`, and the exception handler is an open switch on the gated party’s own path component.
- Did not FAIL the whole reverse-direction design: Appendix F’s write-order argument and the arithmetic-before-filesystem order are sound; defects are implementation switches, not the design reverse itself.

---

## Open questions

none blocking.

Optional product question (out of scope for this commit): should round-directory naming be policed project-wide, not only when `Predecessor:` is declared? F1’s fail-closed fix can stay declaration-scoped without answering that.

---

## Verdict

**REWORK**

Blocking: **F1**, **F2** (with **F3** as the honesty ride-along that must be fixed with them).  
Non-blocking: F4–F6.

---

## Next recommendation

1. **Fail-closed when the declaring round’s own name is not four ASCII digits** (`^[0-9]{4}$`, never `\d` / `.isdigit()`): e.g. `loop-predecessor-round-unnumbered`. Scope to rounds that declared `Predecessor:` so non-declaring legacy dirs stay migration-silent.
2. **Change `PREDECESSOR_VALUE_RE` to `^[0-9]{4}$`** (and sweep any sibling `^\d{4}$` in the same format role, including `ROUND_SEGMENT_RE` if still bare `\d`).
3. **Add G3x teeth** that are true destructive counterproofs: (a) dir `not-a-number` + `Predecessor: 9999` must red; (b) full-width value/dir must not green under ASCII convention.
4. **Rewrite the OUT bullet** so it no longer claims “once declared → must resolve…” without the round-name precondition, or state the precondition explicitly.
5. Re-run adversarial review on the fix commit before treating batch-2 force layer as production-safe.

---

## Appendix — independent probe commands (reproducible)

```bash
cd /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop
# Load ONLY the 7fa902f blob of verify_protocol.py, build the F1 tree above, call verify_project.
# Observed: loop kinds=[], predecessor_declared=1
# Control under rounds/0007: loop-predecessor-not-backward
```

Source anchors at `7fa902f`:

- `PREDECESSOR_VALUE_RE = re.compile(r"^\d{4}$")`
- `try: current_round_num = int(round_dir.name) / except ValueError: return [], state`
- SKILL OUT: “once you declare `Predecessor:`, it must resolve to a real, strictly-earlier round”

## Vendor output (parsed)

````
I'll adversarially review harnessloop commit `7fa902f` myself: inspect the diff, probe the listed attack surfaces, and write the review deliverable.Next I'll pull the full new gate implementations and probe the known attack surfaces with minimal fixtures.Noticing a possible `\d` vs `[0-9]` trap — verifying that and other attack surfaces against the exact commit tree.A later commit fixed silent-pass from bare `\d` — I'll reproduce the exact attack on `7fa902f` and keep probing other surfaces.Reproducing the silent-pass and probing remaining attack surfaces against the exact `7fa902f` tree.Writing the adversarial review deliverable to the hopper handoff path for this task (`exp-p7-B`).# exp-p7-B · code-review-adversarial · harnessloop `7fa902f` (v0.32.0)

**Target:** `7fa902fb97e86dfd2552cfbb3f36f8c6d084e3bf`  
**Method:** read-only; commit blob probes only. Deliverable also at `.hopper/handoffs/exp-p7-B-output.md`.

---

## Summary

Batch-2 lands a sound reverse design (`Predecessor:` on the successor, enum-only stop record, `_uncoded_lines`, G32a–j paired teeth, honest absence/unjustified-stop OUT text, four manifests at 0.32.0). Two ship-blocking false-greens remain on the predecessor gate: a silent `except ValueError: return [], state` that zeros every constraint while ticking `predecessor_declared=1`, and `^\d{4}$` + `int()` accepting full-width digits so a full-width-named predecessor goes green. SKILL overclaims “once declared → real strictly-earlier round.”

## Files touched

none (read-only)

## Acceptance verification (6/6)

| Family | Result |
|--------|--------|
| 1. Parser bypasses (fence / full-width value / 4-space OUT) | **PASS_WITH_NOTE** — G32i/j hold; label-side full-width colon → absence (secondary for optional field) |
| 2. Silent zero-check | **FAIL** — F1 below |
| 3. Regex `\d` / `int()` Unicode | **FAIL** — F2 below |
| 4. Cross-time joins | **PASS** — existence on today’s disk registered OUT; same-goal only |
| 5. Teeth | **PARTIAL** — G32a–j real pairs; no counterproof for F1/F2 |
| 6. OUT honesty | **FAIL** — overclaim vs F1 |

### F1 (MUST-FIX) — silent zero-check

```python
try:
    current_round_num = int(round_dir.name)
except ValueError:
    return [], state
```

**Minimal tree:** `rounds/not-a-number/decision.md` with `- Predecessor: 9999`  
**Expected:** `loop-predecessor-not-backward` or fail-closed on unparseable round name  
**Actual:** zero `loop-*` violations; `rounds_predecessor_declared == 1`  
**Control:** same file under `rounds/0007/` → `loop-predecessor-not-backward`

### F2 (MUST-FIX) — `\d` full-width green

`PREDECESSOR_VALUE_RE = r"^\d{4}$"`; `re.match` and `int('０００３')==3`.  
**Tree:** `rounds/０００３/` + `rounds/0007` with `- Predecessor: ０００３` → **green** under a claim of “exactly four digits.”

## Decisions / deviations

Reviewed exact `7fa902f` blob, not later HEAD. Design reverse itself is sound; defects are implementation switches.

## Open questions

none

## Verdict

**REWORK**

Blocking: **F1**, **F2** (+ **F3** OUT overclaim). Non-blocking: teeth gap, label full-width colon note, symlink-as-dir note.

## Next recommendation

1. Fail-closed when a *declaring* round’s dir name is not `^[0-9]{4}$` (never `\d` / `.isdigit()`).  
2. `PREDECESSOR_VALUE_RE` → `^[0-9]{4}$`; sweep sibling bare `\d` format regexes.  
3. Add teeth that open F1/F2 (destructive counterproof).  
4. Fix the OUT bullet so it matches the real guarantee.  
5. Re-run adversarial review on the fix before calling batch-2 force layer production-safe.
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 324378
- end_time: 2026-07-29T14:16:37.092Z
- log: see `exp-p7-B-output.log` for raw output
