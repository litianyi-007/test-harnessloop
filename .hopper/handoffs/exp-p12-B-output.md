---
phase: done
last_progress_at: "2026-07-29T14:30:24.425Z"
last_progress: Task completed successfully.
progress_seq: 21
last_stream_event: process_alive
last_update: "2026-07-29T14:30:17.313Z"
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
end_time: "2026-07-29T14:30:24.423Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 577156
adapter_status: success
terminal_event_emitted: true
---
# exp-p12-B · code-review-adversarial · harnessloop `7fd5a3c` (v0.35.0)

**Task-type**: `code-review-adversarial` · **Vendor**: grok · **Mode**: review only (no edits)

**Scope**: ONLY commit `7fd5a3c5ac128166cd5c462bd748d81c3cc38bf1`  
(`v0.35.0：需求链第三环——eval 账本必须引用一份 evidence 产物（链条闭合）`)

**Assumption (one line):** No separate acceptance checklist was attached; criteria are the commit’s own claims plus the six attack families named in the brief.

---

## Summary

Reviewed harnessloop `7fd5a3c` only (HEAD is already `c9c884e` / v0.37 — working tree was not used). The change adds a mandatory per-entry `evidence` field on `acceptance-evals.json`, reusing B2a’s path primitives (`_is_contained` → `lexists` → `is_symlink`/`is_file`) but confining resolution to **this round’s** `evidence/` directory. Full `python3 scripts/validate.py` on an archive of that commit exits 0; G38a–j all green. No reproducible attack was found that makes **verify_project overall green** while a claimed `pass` lacks a real ordinary in-round evidence file. Residual notes: domain-symlink false green inside the helper alone (masked by G17 container gate), fixture pollution of older RAE teeth, G38 isolation that depends on decision.md absence, and a pre-existing null-byte crash path shared with `_is_contained`.

## Files touched

(Review only — none edited. Commit’s own paths:)

| Path | Role in `7fd5a3c` |
|------|-------------------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `check_round_eval_ledger` evidence rules + coverage wiring |
| `scripts/validate.py` | G38a–j mutation teeth (+22 `check(` calls) |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN coverage fields + OUT honesty bounds |
| `package.json` | version → 0.35.0 |
| `.claude-plugin/marketplace.json` | version → 0.35.0 |
| `plugins/harnessloop/.claude-plugin/plugin.json` | version → 0.35.0 |
| `plugins/harnessloop/.codex-plugin/plugin.json` | version → 0.35.0 |

## Acceptance verification (8/8)

Criteria derived from commit body + attack brief. Evidence from code at `7fd5a3c` and live repro against that tree.

| # | Criterion | Evidence | Result |
|---|-----------|----------|--------|
| 1 | Review scope is exactly `7fd5a3c` | `git show 7fd5a3c --stat` → 7 files, +632/−8; analysis used `git show 7fd5a3c:…` / `git archive 7fd5a3c`, not HEAD | OK |
| 2 | `evidence` key always required; value may be null unless `outcome=="pass"` | Code: missing → `eval-ledger-evidence-missing`; null+pass → `eval-ledger-evidence-required-for-pass`; G38b/c exact kinds; independent repro same | OK |
| 3 | Non-null path must land under **this round’s** `evidence/` as ordinary non-symlink file | `_is_contained(candidate, round_dir/"evidence")` then `lexists` then `is_symlink or not is_file`; G38d/e/f/g/h; abs-outside → outside-round | OK |
| 4 | Leaf symlink rejected even if target is inside round | G38g + local repro: `eval-ledger-evidence-not-a-file` | OK |
| 5 | Intermediate **subpath** symlink escape is red | Local: `evidence/sub → /OUT` + `evidence/sub/x.log` → `eval-ledger-evidence-outside-round` | OK |
| 6 | Fabricated content still green (registered upper bound) | G38j + code never reads file bytes | OK |
| 7 | OUT honesty: no claim of “proves eval ran”; skipped≠free pass for positive | SKILL OUT bullets + hard rule still needs `outcome=="pass"`; composition holds by code inspection | OK |
| 8 | Teeth suite green at this commit | Archive `7fd5a3c` + `python3 scripts/validate.py` → exit 0, “Plugin framework validation passed.”; all G38a–j `ok:` | OK |

## Attack-surface hunt (brief families)

### 1. Parser bypasses (inline / fenced / full-width)

**N/A as markdown field parsers.** `evidence` is a JSON object key on a strict-loaded document (`_load_strict_json`).  
- Full-width key `"ｅvidence"` does not satisfy `"evidence" not in entry` → `eval-ledger-evidence-missing` (fail-closed).  
- No fenced/inline prose path can hide the key.  
- Value-side full-width whitespace-only (`\u2003`) → `eval-ledger-evidence-invalid-type` via `.strip()`.

### 2. Silent zero-check

- Ledger file absent → zero violations from this function: **intentional** (pre-existing OUT bound; unchanged polarity).  
- Shape-invalid ledger → single `eval-ledger-invalid`, no per-entry evidence loop: correct all-or-nothing.  
- **Not silent:** missing key, pass+null, outside, missing, dir/symlink, bad type all emit kinds.  
- Domain-level `evidence/` symlink: **helper alone** returns `[]` (see F1) — not a project-level silent zero because G17 `round-container-escapes-project` still reds `verify_project`.

### 3. Regex class traps (`\d` / `\w` / full-width)

This slice adds **no new regex**. Path checks are pathlib + `_is_contained`. No new `\d`/`\w` surface.

### 4. Cross-time-layer joins

Resolution is against `round_dir / evidence` and containment vs **this round’s** `evidence/` only. No read of goal `evals.json`, other rounds, or project-wide paths for this field. Confining to round evidence is correctly argued as TH-0027 class ⑥ (lightest), not a new heavy class.

### 5. Teeth shape / green-by-construction

- G38a–j are paired mutations (red + reflex) for missing / null+pass / outside / not-found / dir / leaf-symlink / type / fabricated upper bound.  
- G38g/h correctly use **membership** not equality (Rule A `round-artifact-is-symlink` co-fires).  
- G38j is an **honest upper-bound tooth**, not a false green.  
- Residual fixture issues under Decisions (F2/F3) — hygiene, not “green by construction of the gate.”

### 6. OUT-column honesty

SKILL.md OUT correctly states: does not prove eval ran; does not read content; disk re-read can retro-red closed rounds (class ⑥); skipped avoids evidence but cannot alone satisfy positive-without-pass. Commit subject “链条闭合” is stronger marketing than the OUT list; the **protocol text** does not over-claim beyond what the code does. Guarding is this gate’s own kinds — does not name another party as the sole guard.

---

## Findings

### F1 — NOTE (not FAIL): `check_round_eval_ledger` alone is green when `evidence/` **itself** is a symlink to outside

**Repro (exact tree of `7fd5a3c`):**

```text
round/evidence -> /tmp/OUTSIDE
/tmp/OUTSIDE/stolen.log  (ordinary file)
/tmp/OUTSIDE/runtime/acceptance-evals.json:
  {"entries":[{"eval_id":"RAE-0001","attempt_id":"0001-a1","outcome":"pass",
    "frozen_due_set":["RAE-0001"],"evidence":"evidence/stolen.log"}]}
```

**Actual:**
- `check_round_eval_ledger(round_dir)` → `[]`, `entries_with_evidence=1`  
  (both sides of `_is_contained` canonicalize into `/tmp/OUTSIDE`, so containment “succeeds”).
- `verify_project(project)` → **still red**: `round-container-escapes-project` only.

**Why not FAIL:** overall gate remains red; no end-to-end green pass for outside content. Intermediate **subpath** symlink (`evidence/sub → outside`) correctly yields `eval-ledger-evidence-outside-round` (domain root is a real directory).

**Why still NOTE:** coverage advertises `eval_entries_with_evidence=1` for a project-external artifact, and the helper’s docstring claim “inside this round’s own evidence/” is only true after resolving a poisoned domain. G17 already forbids reading under an escaped container; ledger check still runs and follows the symlink (pre-existing ledger-read pattern, extended by existence checks on candidates).

### F2 — NOTE: Pre-`G38` RAE fixtures omit `evidence` → permanent `eval-ledger-evidence-missing` co-fire

At `7fd5a3c`, G25/G26/G27/`G37i`-style ledgers still write entries **without** the `evidence` key. Suite stays green because assertions are mostly membership (`"X" in kinds` / `not in kinds`). Live log noise example (G27a):

```text
got ['acceptance-eval-declaration-missing', 'acceptance-eval-positive-without-pass', 'eval-ledger-evidence-missing']
```

Messages that say “turns it green” mean “that specific kind is gone,” not “project clean.” Not a production bypass; weakens fixture clarity.

### F3 — NOTE: G38 zero-violation isolation depends on **no** `decision.md`

At `7fd5a3c`, G38 does **not** call `_rae_write_decision`. Ledger present + decision absent is still silent for B2a / acceptance-eval-declaration / (later) eval-ledger-without-decision — so `not violations` and `kinds == {single kind}` hold. Valid at this commit; **latent brittleness** if a later gate requires decision whenever a ledger exists (observed historically on main after this commit — cited only as confirmation of the fixture assumption, not as review of later code).

### F4 — NOTE: JSON `\u0000` in `evidence` crashes via `_is_contained` → CLI exit 1

Legal JSON: `"evidence":"evidence/run.log\u0000evil"`.  
`path.resolve(strict=False)` raises `ValueError: embedded null byte`.  
`verify_protocol.py --project …` → **returncode 1** with traceback (not a clean violation kind; **not** silent green). Same primitive as B2a `Review:` paths; new JSON field makes `\u0000` easier to inject than markdown. Fail-closed in exit code, ugly as accounting.

### F5 — NOTE: Absolute teeth count wording

Commit claims teeth 577 → **601** (+24). Measured at this archive: `check(` 515 → 537 (**+22**); runtime `ok:` lines on this machine **603** with claude validate enabled. Delta direction matches G38; absolute 577/601 is not a machine-checkable single counter in the script.

---

## Decisions / deviations

- Reviewed **code at `7fd5a3c` only** via `git archive` / `git show`; ignored HEAD’s v0.36/v0.37 changes except to avoid contaminating analysis.
- Registered OUT bounds (fabricated file green; no content/system match; skipped incentive alignment) treated as design, not defects — G38j/c pin them.
- Domain-symlink helper false green classified NOTE not FAIL because overall `verify_project` remains red.
- Did not re-dispatch or edit production code.

## Open questions

- none that block the verdict  
- (optional follow-up) whether `check_round_eval_ledger` should refuse to run / report a dedicated kind when `evidence/` fails `_container_escape_violation`, so coverage cannot claim `with_evidence` for escaped trees

## Verdict

**PASS_WITH_NOTE**

No FAIL-class defect: no minimal attack produces overall green while a `pass` entry lacks a real ordinary file under this round’s non-escaped `evidence/`. Notes are helper/coverage honesty under domain symlink, fixture hygiene, G38 isolation assumptions, and shared null-byte crash path.

## Next recommendation

1. **Accept** v0.35.0 requirement-③ gate as shipped; do not block on F1–F5.  
2. **Hygiene (non-blocking):** backfill `"evidence": null` (or real paths) into older G25–G27 ledger fixtures so co-fire noise dies; give G38 a minimal compliant `decision.md` so zero-violation teeth survive future “ledger ⇒ decision” rules.  
3. **Optional hardening:** if domain-symlink coverage honesty matters, short-circuit evidence resolution when `evidence/` is a container escape (or assert `not evidence_root.is_symlink()` before counting `entries_with_evidence`).  
4. No rework cycle required for this commit’s production logic on the evidence discrimination table alone.

## Vendor output (parsed)

````
I'll review only harnessloop commit `7fd5a3c` as the adversarial code-review agent, starting with the commit itself and the task handoff materials.Pulling the full patch and focusing on the new validation logic and tests.Reading the implementation of `check_round_eval_ledger` evidence handling and comparing it to `check_review_declaration`.Attack A looks like a real bypass — verifying whether Rule A or other gates still catch a symlinked `evidence/` root.Checking whether older RAE fixtures still include `evidence` — a missing field would break G25 after this commit.Pre-existing G25 ledgers omit `evidence` — running the test suite to see if that breaks green paths.Validating at the exact commit tree — HEAD may have moved past `7fd5a3c`.Reviewing the tree at `7fd5a3c` only — HEAD already includes later commits.Writing the independent adversarial review to the hopper handoff path for `exp-p12-B`.# exp-p12-B · code-review-adversarial · harnessloop `7fd5a3c` (v0.35.0)

**Verdict: PASS_WITH_NOTE** · Review only · Deliverable: `.hopper/handoffs/exp-p12-B-output.md`

---

## Summary

Reviewed **only** `7fd5a3c5ac128166cd5c462bd748d81c3cc38bf1` (v0.35.0 eval-ledger `evidence` field). Analysis used `git show` / `git archive` of that commit — not HEAD (`c9c884e` / v0.37). The gate reuses B2a primitives (`_is_contained` → `lexists` → `is_symlink`/`is_file`) confined to **this round’s** `evidence/`. Full validate on that tree exits **0**; G38a–j all green. No attack found that makes **verify_project overall green** for a `pass` without a real ordinary in-round evidence file.

## Files touched

none (review only)

## Acceptance verification (8/8)

| # | Criterion | Result |
|---|-----------|--------|
| 1 | Scope exactly `7fd5a3c` | OK |
| 2 | Key always required; null OK unless `outcome=="pass"` | OK (G38b/c + code) |
| 3 | Non-null → ordinary file under this round’s `evidence/` | OK (G38d–h) |
| 4 | Leaf symlink inside still red | OK |
| 5 | Intermediate subpath symlink escape red | OK (live repro) |
| 6 | Fabricated content green (registered upper bound) | OK (G38j) |
| 7 | OUT honesty (no “proves ran”; skipped ≠ free positive) | OK |
| 8 | Teeth suite green at this commit | OK (`validate.py` exit 0) |

## Findings (none FAIL)

| ID | Level | One-liner |
|----|-------|-----------|
| **F1** | NOTE | When `evidence/` **itself** is a symlink to outside, `check_round_eval_ledger` alone returns green + `with_evidence=1`; **verify_project still red** via `round-container-escapes-project` |
| **F2** | NOTE | Pre-G38 RAE fixtures omit `evidence` → permanent `eval-ledger-evidence-missing` co-fire; membership teeth still pass |
| **F3** | NOTE | G38 zero-violation isolation depends on **no** `decision.md` (silent at this commit) — latent fixture brittleness |
| **F4** | NOTE | JSON `\u0000` in path crashes `_is_contained` → CLI exit 1 (not silent green; shared primitive) |
| **F5** | NOTE | Claimed teeth 577→601 vs measured `check(` +22 / ~603 `ok:` — delta direction OK, absolute soft |

### Minimal repro for F1 (helper-only false green)

```text
round/evidence -> /tmp/OUTSIDE
/tmp/OUTSIDE/stolen.log
ledger evidence: "evidence/stolen.log", outcome: "pass"
→ check_round_eval_ledger: [] 
→ verify_project: {round-container-escapes-project}
```

Subpath symlink (`evidence/sub → outside`) correctly yields `eval-ledger-evidence-outside-round`.

## Attack families (brief)

1. **Parser bypass** — N/A (JSON key, not markdown); full-width key → missing  
2. **Silent zero** — only intentional ledger-absent silence; domain-symlink not overall silent  
3. **`\d`/`\w`** — no new regex  
4. **Cross-time join** — none; round-local only (TH-0027 class ⑥)  
5. **Teeth** — bidirectional mutations; G38j honest upper bound  
6. **OUT honesty** — protocol text matches code; subject “链条闭合” is stronger marketing than OUT

## Decisions / deviations

Reviewed archived `7fd5a3c` only; registered OUT bounds not treated as defects; F1 not escalated to FAIL because overall gate stays red.

## Open questions

none blocking

## Next recommendation

1. **Accept** v0.35.0 requirement-③ as shipped.  
2. Non-blocking hygiene: backfill `evidence` in G25–G27 fixtures; give G38 a minimal `decision.md`.  
3. Optional: refuse/count carefully when `evidence/` is a container escape.  
4. No production rework required for the discrimination table itself.
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 577156
- end_time: 2026-07-29T14:30:24.423Z
- log: see `exp-p12-B-output.log` for raw output
