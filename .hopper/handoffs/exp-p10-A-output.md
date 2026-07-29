---
task_id: exp-p10-A
adapter: grok
model: grok-4.5
requested_selector: null
effective_selector: grok-4.5
effective_selector_source: policy
status: done
mode: background
phase: done
progress_log: ./exp-p10-A-progress.log
raw_log: ./exp-p10-A-output.log
log: ./exp-p10-A-output.log
---

# Adversarial Code Review — harnessloop `00b6c73`

**Reviewed object**: `harnessloop` commit `00b6c7368f2bae06dce0a4f25ceeb0c60953b768`  
(`v0.33.3` — break `rounds_zero_inspected` out by round name in human-mode notes)  
**Mode**: review-only · no edits · tree materialised via `git show 00b6c73:…` into an isolated temp import (worktree HEAD is later: `c9c884e` / v0.37.0)

**Assumption**: brief had no separate AC list; acceptance surface = commit message claims + SKILL.md text this commit itself adds + the design invariant the new docstring asserts (notes ≡ coverage definition of zero-inspected; no new kind/key/exit-code change).

---

## Summary

Commit `00b6c73` correctly demotes zero-inspection to a **legibility** problem rather than a new gate: human-mode prints one non-blocking note per empty round, reuses `_scan_round_artifacts` for the file-count side of the definition, leaves `--json` / exit code / violation kinds untouched, and G36a–c give real teeth for the happy path (count, sum-across-rounds, real subprocess exit 0 + banner + note substring).

It does **not** keep the invariant it advertises. The notes collector only containment-checks `evidence/` and `reviews/`; it never G17-checks `goals_dir` / `goal_dir` / `round_dir` the way `verify_project` does before calling `verify_round`. Empirically, a symlink-escaped round or goal is **skipped by coverage** but **still emits a note** (coverage 1 / notes 2). That falsifies the docstring’s “never a second, drifting definition” claim, the SKILL.md line this commit adds (“legibility layer over the same count”), and the commit message’s “保证就是让计数 +1 的那些轮”. Same class of G17 notes-walk hole previously called on the sibling TH-0026 collector — this commit only half-learned that lesson.

---

## Files touched

none (read-only review; deliverable is this handoff file only)

**Files under review (from the commit):**

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `collect_zero_inspected_round_notes` + `main()` human-mode print |
| `scripts/validate.py` | G36a / G36b / G36c teeth (+8 checks claimed) |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | documents the new note lines on the `rounds` / `rounds_zero_inspected` IN bullet |
| 4 version manifests | `0.33.3` (package.json, marketplace.json, .claude-plugin/plugin.json, .codex-plugin/plugin.json) |

---

## Acceptance verification (6/6 claims exercised)

Task brief had no machine-checkable AC list. Verification against the commit’s own claims:

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | No new violation kind / coverage key / exit-code change | **PASS** | Diff only adds collector + print branch under human mode (`verify_protocol.py:5258–5260` at commit). G36c subprocess `returncode == 0` on zero-only project. `--json` path still dumps only `verify_project` result. |
| 2 | Notes reuse same primitives as `verify_round` for zero-file decision | **PASS (partial)** | Per-container path uses `_container_escape_violation` + `_scan_round_artifacts` (`:4946–4954`). File-count side matches `verify_round` for **non-escaped** rounds (clean 3-round probe: reasons correct, `len(notes)==coverage`). |
| 3 | “Round reported here is always exactly one that incremented coverage — never a drifting definition” | **FAIL** | Escaped `round_dir` symlink probe (00b6c73 blob): `coverage.rounds_zero_inspected=1`, `coverage.rounds=1`, notes=**2** (includes escaped `0002`). Escaped `goal_dir` symlink: coverage zero=1, notes=**2**. |
| 4 | SKILL: “legibility layer over the **same** count … never a new judgment” | **FAIL** | Same repro as #3. Count and note list diverge under the G17 fixtures SKILL itself documents two sentences earlier on the same bullet. |
| 5 | G36 teeth prove boundary holds | **PASS_WITH_GAP** | G36a: zero_inspected 1→0 reverse mutation. G36b: sum=2 + both round names in notes. G36c: real subprocess exit 0 + banner + note prefix. **Missing**: note_count==coverage under escape; reason paths 2/3; “no problem” wording coexisting with real escape violations. |
| 6 | Version bump consistent 0.33.3 | **PASS** | All four manifests in commit show `"version": "0.33.3"`. |

### Repro — F1 G17 coverage↔notes drift (isolated 00b6c73 import)

```
# fixture: legit empty round 0001 + rounds/0002 -> outside tree (no evidence/reviews)
coverage rounds:          1
coverage zero_inspected:  1
viol kinds:               {round-container-escapes-project}
notes count:              2   # includes escaped 0002
```

```
# fixture: goals/escaped-goal -> outside + legit goal
coverage rounds: 1  zero: 1
notes count:     2   # includes escaped-goal/rounds/0001
```

`verify_project` skips escaped goal/round after `_container_escape_violation` (`:5065–5087` at commit).  
`collect_zero_inspected_round_notes` walks with bare `is_dir()` / `iterdir()` and only checks **evidence/reviews** containers (`:4937–4954`).

---

## Findings (author-miss class)

### F1 — MUST FIX · G17 hole + coverage↔notes drift in `collect_zero_inspected_round_notes`

**Where (at 00b6c73):** `verify_protocol.py:4937–4978` vs `verify_project` walk at `:5047–5087`  
**Claim broken:** docstring `:4897–4901` (“always exactly one of the rounds that already incremented… never a second, drifting definition”); commit message (“保证就是让计数 +1 的那些轮”); SKILL.md IN bullet this commit adds.

The collector containment-checks only `evidence/` and `reviews/`. It does **not**:

1. check `goals_dir` before listing goals  
2. check each `goal_dir` before opening `rounds/`  
3. check each `round_dir` before treating it as a zero-inspected candidate  

`Path.is_dir()` / `.iterdir()` follow symlinks. Effects:

1. **Notes over-report vs coverage** (repro above: 1 vs 2).  
2. **Outside walk**: for a symlink-escaped `goal_dir`, `rounds_dir.iterdir()` lists a tree outside the project — the exact class G17 / PR-2 forbids for the real gate, and the class already called on the sibling TH-0026 notes collector.  
3. G36 never asserts `len(notes) == coverage["rounds_zero_inspected"]` under an escape fixture, so the teeth green-path the false invariant.

**Fix shape** (either is fine; second is stronger):

- Mirror `verify_project`: `_container_escape_violation` on `goals_dir` / `goal_dir` / `round_dir` before any descent; skip escaped nodes without scanning.  
- Or stop double-walking: emit notes from the same pass that increments `rounds_zero_inspected` so the two cannot drift by construction.

Add a G36 tooth: one legit zero round + one escaped round symlink → `zero_inspected == 1`, `len(notes) == 1`, note path is only the legit round.

---

### F2 — SHOULD FIX · Note boilerplate lies when zero-inspect co-occurs with real violations

**Where:** note template at `:4973–4977`; escape-fold design at `:4920–4926`.

Every note ends with:

> not a violation, and it does not mean this round has a problem.

Empirically, when `evidence/` is itself a symlink escape:

- `verify_round` still sets `rounds_zero_inspected = 1` (no scanned files) **and** emits `round-container-escapes-project`  
- collector emits the note with reason folded to “neither exists”  
- the note still asserts the round has no problem

Same for symlink-only artifacts under `reviews/` (`round-artifact-is-symlink` + zero_inspected + note “no problem”).

Hint-only is fine; **absolute** “no problem / not a violation” is not, when the only reason there was nothing to inspect is a loud containment failure. Soften wording to something like “zero-inspect itself is not an additional violation” without denying co-occurring kinds.

---

### F3 — SHOULD FIX · “Never raises / worst case missed note” is aspirational, not implemented

**Where:** docstring `:4928–4930` vs body `:4937–4978`.

Sibling `collect_scope_lock_round_path_mismatch_notes` wraps the only fallible IO in `try/except OSError` and continues (`:4874–4877`).  
`collect_zero_inspected_round_notes` has **no** exception shield around `iterdir` / `is_dir` / `_scan_round_artifacts` (`rglob`). Only `relative_to` is guarded.

`main()` prints notes **after** `verify_project` already succeeded (`:5258–5260`). An exception in the human-only second pass can still abort the process after a clean gate computation — contradicting “never a crash of the real gate”. Even if rare on owner-writable trees, the discipline claim is copy-pasted without the sibling’s actual defence.

---

### F4 — SHOULD FIX · G36 teeth miss the load-bearing invariant and 2/3 reason paths

**Where:** `scripts/validate.py:7503–7605` (G36a–c).

| Covered | Not covered |
|---------|-------------|
| zero_inspected 0/1/2 | `len(notes) == coverage["rounds_zero_inspected"]` under escape |
| reverse mutation on coverage | reverse mutation on **notes** clearing |
| subprocess exit 0 + banner substring | reason path “both exist empty” |
| both round **names** appear (G36b) | reason path “only one exists” |
| | G17 skip of escaped goal/round |
| | note must not claim “no problem” when escape violation present |

G36a never even calls `collect_zero_inspected_round_notes` — only coverage. The function this batch is named for is exercised only in G36b/c, and only on the “neither exists” shape produced by `_loop_round`.

---

### F5 — NOTE · Grammar / copy quality in the “neither” reason

**Where:** `:4959`

```text
evidence/ and reviews/ neither exists
```

Should be “neither … nor … exists” / “neither exists” → “do not exist”. Human-facing string on every all-absent zero round; easy miss, low severity.

---

### F6 — NOTE · Double walk cost is accepted but unguarded against future drift

Same architectural choice as TH-0026 notes: second independent walk to avoid growing `verify_project`’s 2-tuple. Acceptable for a hint, but F1 shows the cost of that choice without shared walk predicates. If more human-only collectors appear, factor a single “safe rounds iterator” that both gates and notes use.

---

## What is solid (credit)

- **Right product call**: zero-inspect is a documented boundary, not a defect — do not invent a violation kind. Matches SKILL “nothing to check ≠ checked and clean”.  
- **Reason taxonomy is useful** on the happy path: neither / both-empty / only-one — all three fire correctly on clean fixtures.  
- **File-count side really reuses `_scan_round_artifacts`**: symlink-only artifact tree correctly contributes 0 files (same as gate).  
- **G36c is a real tooth**: subprocess exit code, not `violations == []` alone.  
- **Non-blocking print placement** mirrors TH-0026 and does not touch `--json`.  
- **Version bump hits all four manifests** (G28 surface).  
- **Does not claim to fix TH-0026 residual wrong attribution** in prose while still improving the underlying “number nobody can act on” problem.

---

## Decisions / deviations

- Judged against tree at `00b6c73` only (blob import); later commits on HEAD not used to excuse or aggravate findings, except as historical context that the sibling G17 notes hole was already a known class.  
- Severity: F1 is REWORK-grade because the commit’s central correctness claim is “notes ≡ coverage rounds”, not merely “print something useful on the happy path”. Happy-path usefulness alone would be PASS_WITH_NOTE.

---

## Open questions

- none that block the verdict. Product choice only: whether escaped containers should get a distinct fourth reason string instead of folding into “does not exist” (docstring currently chooses fold; F2 is about the “no problem” trailer, not the fold itself).

---

## Verdict

**REWORK**

Happy-path legibility works and the non-blocking demotion is correct. Ship-blocking for this change’s own stated invariant: **notes can name rounds that never incremented `rounds_zero_inspected`**, and the collector can **list/stat outside the project** via escaped goal/round symlinks — while docstring, commit message, and the SKILL sentence this commit adds all promise the opposite.

---

## Next recommendation

1. **Must**: G17-guard `goals_dir` / `goal_dir` / `round_dir` in `collect_zero_inspected_round_notes` (or derive notes from the verify pass). Fixture: legit zero + escaped symlink round → `len(notes) == coverage["rounds_zero_inspected"] == 1`.  
2. **Must**: G36 tooth that locks claim #3 (count equality under escape), not only name-substring presence on clean trees.  
3. **Should**: soften note trailer so it cannot deny co-occurring `round-container-escapes-project` / `round-artifact-is-symlink`.  
4. **Should**: `try/except OSError` around the scan loop to match sibling “never crash the gate” discipline; fix “neither exists” grammar.  
5. **Should**: G36 cases for both-empty and only-one-exists reason strings.  
6. Re-run self-host: expect previous 9 informational notes to remain 9, exit 0, and a synthetic escape fixture to show notes==coverage.

---

**Review target confirmation**: commit `00b6c7368f2bae06dce0a4f25ceeb0c60953b768` only (`git show 00b6c73` + isolated import of that tree’s `verify_protocol.py`). Not the worktree HEAD, not another repo.
