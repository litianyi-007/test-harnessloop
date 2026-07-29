---
task_id: exp-p9-A
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
pid: 63356
start_time: "2026-07-29T14:11:12.994Z"
end_time: "2026-07-29T14:15:53.912Z"
exit_code: 0
duration_ms: 280870
mode: background
phase: done
last_progress_at: "2026-07-29T14:15:53.913Z"
last_progress: Task completed successfully.
progress_seq: 11
progress_log: ./exp-p9-A-progress.log
raw_log: ./exp-p9-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p9-A-output.log
started_by_pid: 63354
last_stream_event: process_alive
last_update: "2026-07-29T14:15:43.174Z"
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

# exp-p9-A — grok (background, done)

Output streaming to `exp-p9-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10822 chars; complete parsed output is available through `hopper-dispatch --result exp-p9-A --full`)_

````
I'll independently review harnessloop commit `6c92440` and write the adversarial review deliverable—no edits, no delegation.Digging into edge cases in the G35 scanner, predecessor check, and remaining bare `\d` usage.Functional matrix confirmed the primary fix. Checking one more residual path, then writing the deliverable for `exp-p9-A`.# Adversarial Code Review — `6c92440`

**Reviewed object**: `harnessloop` commit `6c9244054a666c26d6f6c3e8483d7fa964bc4700`  
(`v0.33.2` P0: close predecessor silent pass-through + class-level bare-`\d` sweep)  
**Mode**: review-only · no edits · tree via `git show 6c92440:…` + isolated import of that blob’s `verify_protocol.py`  
**Assumption (1 line)**: task id is `exp-p9-A` (hopper-runner ancestor); acceptance = commit claims + author-miss defect hunt.

---

## Summary

Commit `6c92440` correctly closes a real X1 switch in `check_loop_predecessor_declaration`: a declaring round whose directory name was not `int()`-parseable used to return **zero** violations. The fix is fail-closed (`loop-predecessor-round-unnumbered`), scoped only to rounds that declared `- Predecessor:`, and uses `^[0-9]{4}$` rather than bare `\d` / `.isdigit()` — with G34a–e teeth that actually discriminate those alternatives (including full-width `０００７`). The class-level regex sweep (5 sites + AST G35a/b/c) is real and well-motivated. Residual author-miss: the sibling “latest round” selector still trusts `int(round_dir.name)` (full-width wins ranking), and its docstring still claims the predecessor gate’s removed “left unvalidated” behaviour.

## Files touched

none (read-only review)

**Files under review (from the commit):**

| Path | Role |
|---|---|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | Fail-closed predecessor gate + 4× `[0-9]` regex fixes |
| `plugins/harnessloop/skills/harnessloop-loop/scripts/init_project.py` | `normalize_slug` defense-in-depth |
| `scripts/validate.py` | G34a–e + G35a/b/c teeth; `SEMVER_VERSION_RE` |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN/OUT documentation of new kind |
| 4 version manifests | `0.33.0` → `0.33.2` |

## Acceptance verification (6/6 claims checked)

Task brief had no separate AC list. Checked against the commit’s own claims:

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | Declaring round with non-`NNNN` dir → `loop-predecessor-round-unnumbered` (no silent empty return) | **PASS** | `verify_protocol.py:3454–3475`; live matrix: `abc`+`Predecessor: 0003` → `['loop-predecessor-round-unnumbered']` |
| 2 | Undeclared rounds with any dir name stay silent | **PASS** | early `raw is None` return; G34b; live: `xyz` no field → `OK`, `declared=False` |
| 3 | Use `[0-9]{4}` not `\d` / `.isdigit()` (full-width blocked) | **PASS** | `ROUND_NAME_STRICT_RE` `:3325`; live `０００７` → unnumbered; language facts: `re.match(r'^\d{4}$','０００７')` True, `[0-9]` False, `int==7` |
| 4 | Same class fixed at `LINE_SUFFIX_RE` / `ROUND_SEGMENT_RE` / `PREDECESSOR_VALUE_RE` / `SEMVER_VERSION_RE` / `normalize_slug` | **PASS** | diff; live: full-width pred value → `invalid-value`; `ROUND_SEGMENT_RE` fw False; strip leaves `foo.py:１２` unstripped |
| 5 | G35 AST scanner + non-vacuous counter-proof; validate +23 checks | **PASS** | G35a/b/c in `validate.py`; 23 added `check(` lines; 520→543 arithmetic holds |
| 6 | Four manifests bumped consistently to 0.33.2 | **PASS** | `package.json` + marketplace + claude/codex plugin.json all `0.33.2` at commit |

**Live functional matrix** (blob import of `check_loop_predecessor_declaration` at `6c92440`):

```
'abc'      + Pred 0003   → loop-predecessor-round-unnumbered
'０００７'  + Pred 0003   → loop-predecessor-round-unnumbered
'0004'     + Pred 0003   → OK  (0003 exists)
'0005'     + Pred ０００３ → loop-predecessor-invalid-value
'007'      + Pred 0003   → loop-predecessor-round-unnumbered  (int('007') would have worked)
'0000'     + Pred 0003   → loop-predecessor-not-backward
'0006'     + Pred 0006   → loop-predecessor-not-backward  (self)
'0008'     + Pred 0009   → loop-predecessor-not-backward  (forward)
'xyz'      + (absent)    → OK
```

## Findings (author-miss class)

### F1 — SHOULD FIX · same Unicode-digit class still open in `_latest_round_decision_text`

**Where**: `verify_protocol.py:3913–3960` (at `6c92440`)

```python
try:
    numbered.append((int(round_dir.name), round_dir))
except ValueError:
    continue
...
_, latest_round_dir = max(numbered, key=lambda pair: pair[0])
```

The commit’s entire thesis is that `int()` / bare `\d` / `.isdigit()` all accept full-width digits (`int("００１０") == 10`). That path was closed for predecessor arithmetic via `ROUND_NAME_STRICT_RE`, but **not** for “which round is latest” used by `check_loop_autocontinue_anomaly`.

**Live probe** (same `int()` rule):

```
candidates: '0009', '００１０', 'abc'
latest selection: (10, '００１０')   # full-width beats ASCII 0009
```

Effects:

1. A full-width-named directory can become the “latest” round for the anomaly signal even when a higher-looking ASCII name does not exist, or can outrank a real ASCII round with a smaller int value.
2. Docstring at `:3920–3924` still says this **mirrors** `check_loop_predecessor_declaration`’s *“left unvalidated rather than crashing”* treatment — that paragraph was **deleted** by this same commit. The comment is now actively false and teaches the next reader the pre-fix semantics.

Impact is observation-layer (`loop_autocontinue_anomaly` never changes exit code), so not the same severity as the closed X1 switch — but it is the **exact class** the commit claims to have generalized, left on the next `int(round_dir.name)` call site in the same file.

**Fix shape**: reuse `ROUND_NAME_STRICT_RE` (or share one helper) before `int()`; drop/replace the stale “left unvalidated” sentence; add a G34-style tooth that full-width cannot win `max()`.

### F2 — NOTE · G35 teeth have known static blind spots (partially documented)

**Where**: `_g35_iter_patterns` / `_pattern_has_bare_backslash_d` in `scripts/validate.py`

| Hole | Detected? | Notes |
|---|---|---|
| `re.compile(r'\d')` positional | yes | covered |
| `re.compile(pattern=r'\d')` keyword | **no** | only `node.args[0]` |
| `from re import compile; compile(r'\d')` | **no** | requires `re.<attr>` |
| `p=r'\d'; re.compile(p)` | **no** | non-literal → yield nothing |
| `r'[\d_]'` class form | **no** | intentional; G35b documents it |

G35b’s destructive counter-proof is good for the detector function itself, not for end-to-end “any future bare digit validation is impossible.” Acceptable as a structural floor; do not treat G35a as a completeness proof.

### F3 — NOTE · docstring still says “two structural constraints”

**Where**: `check_loop_predecessor_declaration` header `:3352`

Body now lists **four** constraints (value format → own-name strict → arithmetic → existence). Header still says “Appendix F.2's two structural constraints.” Minor, but this module’s docs are load-bearing for the next agent.

### F4 — NOTE · no dedicated tooth for full-width **predecessor value**

G34a–e hammer **round directory names**. Full-width `Predecessor: ０００３` correctly yields `loop-predecessor-invalid-value` in live probe (via `PREDECESSOR_VALUE_RE`), but nothing in G34 asserts that kind. Relying on G35a + code inspection is thinner than the rest of this batch’s mutation-paired style.

### F5 — NOTE · invalid-value user detail still says “four digits” not “ASCII digits”

**Where**: detail string after `PREDECESSOR_VALUE_RE` failure

After this commit’s careful ASCII wording everywhere else, the operator-facing invalid-value message is the one place that still under-specifies, which matters if someone pastes full-width digits and needs to understand why.

---

## What is solid (credit)

- **Real bug, real close**: the old `except ValueError: return [], state` was an X1 switch held by the audited round; fail-closed only when the field is declared is the right zero-migration cut.
- **Author’s first 

... [truncated, 2822 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 280870
- end_time: 2026-07-29T14:15:53.912Z
- log: see `exp-p9-A-output.log` for raw output
