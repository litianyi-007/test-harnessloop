---
task_id: exp-p1-B
adapter: grok
model: grok-4.5
task_type: code-review-adversarial
status: done
review_target: harnessloop@5c7068f38cea9bb6de340e3f3be2f22644d671f5
verdict: REWORK
---

# exp-p1-B · code-review-adversarial · harnessloop `5c7068f` (v0.27.0 RAE 竖切)

## Summary

Reviewed harnessloop commit `5c7068f` (runtime acceptance-evals vertical slice: one hard rule + 14 kinds + G25a–G25n bidirectional teeth). The hard rule is correctly same-round-only (no cross-time join), strict JSON duplicate-key rejection is real, outcome/eval-id regexes correctly avoid `\d`, and the two OUT upper bounds are honestly documented and pinned. **However, Feedback line recognition is fail-open on full-width / near-miss label syntax** (treated as *absent* → zero-migration silence) while value-side full-width punctuation is fail-closed — a reproducible silent green under the commit’s own threat model. First-occurrence / code-fence marker matching also lets a human-visible later `Feedback: positive` be ignored after an earlier example line. Verdict: **REWORK**.

## Files touched

none (read-only review; deliverable only at `.hopper/handoffs/exp-p1-B-output.md`)

Review surface (read, not modified):

- `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` — RAE gate implementation
- `scripts/validate.py` — G25a–G25n teeth
- `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` — IN/OUT coverage text
- version manifests (`package.json`, marketplace/plugin.json) — bump only, not re-audited beyond presence

## Acceptance verification (5/5 attack surfaces)

Method: detached worktree at exact `5c7068f` (`/tmp/hl-rae-review-5c7068f`), load that commit’s `verify_protocol.py` via `importlib`, run minimal fixtures. Working tree HEAD is newer (has post-slice kinds); **all findings below are against `5c7068f` only**.

| # | Attack surface | Result | Evidence |
|---|----------------|--------|----------|
| 1 | Parser bypasses (marker discussion / full-width punct) | **FAIL (2 repros)** | F1, F2 below |
| 2 | Silent zero-check on malformed input | **PASS with documented OUT** | Invalid JSON → `eval-ledger-invalid`; shape errors itemized; missing file / empty due are **documented** OUT (G25l), not hidden |
| 3 | Regex class traps (`\d` / `int()` / Unicode digits) | **PASS** | `RAE_EVAL_ID_RE = ^RAE-[0-9]{4}$`, `ATTEMPT_ID_RE = ^([0-9]{4})-a[0-9]{1,3}$`; full-width digits rejected (`eval-ledger-invalid-attempt-id` / `-frozen-due-set-invalid-element`); `activation_round` bool excluded + teeth |
| 4 | Cross-time-layer joins | **PASS (by construction)** | Hard rule operands = same round’s ledger + same round’s `decision.md` only; `evals.json` never read by the rule; registry validated only against itself |
| 5 | Teeth assert implementation shape / green-by-construction | **PASS_WITH_NOTE** | G25a–n mostly mutation-paired; **gap**: G25n only covers *value* full-width period, not *label/colon* full-width — teeth green while F1 lives |

Control (sanity):

```text
decision.md:  - Feedback: positive
ledger:       outcome=fail, frozen_due_set=["RAE-0001"]
→ RAE kinds: ['acceptance-eval-positive-without-pass']   # OK
```

```text
same + outcome=pass → RAE kinds: []   # OK
```

### F1 — MUST-FIX · Full-width colon (and near-miss label syntax) = silent green

**Surface:** parser + silent zero (commit claims fail-closed Feedback handling for full-width punctuation; only value side is closed).

**Root cause:** `parse_feedback` only matches ASCII `- feedback:` after `strip().lower()`. Non-matching lines return `None`, which `verify_round` treats as **absent** (zero-migration silence), not as unparsable.

```python
# 5c7068f parse_feedback
if stripped.lower().startswith("- feedback:"):
    return stripped.split(":", 1)[1].strip()
return None
# verify_round: if raw_feedback is None:  # stay silent
```

**Minimal attack (exact files):**

`decision.md`:
```markdown
# Decision

- Feedback：positive
```
(colon is U+FF1A FULLWIDTH COLON; bytes `ef bc 9a`)

`evidence/runtime/acceptance-evals.json`:
```json
{"entries": [{"eval_id": "RAE-0001", "attempt_id": "0001-a1", "outcome": "fail", "frozen_due_set": ["RAE-0001"]}]}
```

**Expected (per stated discipline):** `acceptance-eval-feedback-unparsable` and/or `acceptance-eval-positive-without-pass` (must not be silent while a human reads “Feedback: positive”).

**Actual on `5c7068f`:**
```text
parse_feedback → None
RAE kinds → []   # silent green on the hard rule
```

Same class (silent green + fail ledger):

| Line | parse_feedback | RAE |
|------|----------------|-----|
| `- Feedback：positive` (U+FF1A) | `None` | silent |
| `- Feedback : positive` (space before `:`) | `None` | silent |
| `- Feedback\u00a0: positive` (NBSP before `:`) | `None` | silent |
| `－ Feedback: positive` (U+FF0D fullwidth hyphen) | `None` | silent |
| `- Feedback: positive。` (G25n value) | `'positive。'` | `acceptance-eval-feedback-unparsable` ✅ |

**Why not theoretical:** commit message + SKILL text explicitly cite this project’s Chinese full-width punctuation in `decision.md` as the reason value-side fail-open is dangerous. F1 is the same threat class on the *label/colon*, which humans still read as Feedback and which G25n does not cover.

### F2 — MUST-FIX · First-occurrence + code-fence: “discussing the marker == enabling it”

**Surface:** parser bypass (historical bite named in the task brief).

**Root cause:** first matching line wins; fenced code lines still match after `strip()` (no fence/prose awareness).

**Minimal attack:**

`decision.md`:
```markdown
# Decision

```md
- Feedback: negative
```

- Feedback: positive
```

Same fail ledger as F1.

**Expected:** authoritative field is the later real `Feedback: positive` → `acceptance-eval-positive-without-pass`.

**Actual:**
```text
parse_feedback → 'negative'
RAE kinds → []   # hard rule only constrains positive; example line wins
```

Audited party gets green with a fail due-set while a skimming human reads the last bullet as `positive`.

### N1 — NOTE · Documented upper bounds are real doors (honest, not hidden)

These are **not** silent defects of the implementation; they are the vertical slice’s declared OUT. Confirming they work as stated:

| Escape | Behavior | Doc |
|--------|----------|-----|
| No `acceptance-evals.json` + `Feedback: positive` | 0 RAE violations | SKILL OUT + G25l |
| `frozen_due_set: []` (or empty `entries`) + positive | 0 hard-rule violations | SKILL OUT (self-reported due set) |

Do not treat these as F-findings for *this* slice; they matter for product honesty when claiming “acceptance evals gate Feedback”.

### N2 — NOTE · What is solid (credit)

- Strict loader: duplicate keys → `eval-ledger-invalid` / `rae-invalid`; plain `json.loads` keeps last key (G25m destructive control proven).
- Hard rule uses exact `outcome == "pass"` (no case fold); `"pass "` / `True` → invalid + without-pass.
- `bool` excluded from `activation_round` (Python `isinstance(True, int)` trap).
- No registry↔ledger join on the hard rule path (cross-time avoided).
- Coverage counters split goal vs round correctly in design.

## Decisions / deviations

- Assumption (1 line): task ID for this hopper dispatch is `exp-p1-B` (from `HOPPER_ADAPTER_OPTS.logFile`); review object is exactly commit `5c7068f` as briefed, not later HEAD.
- Did not re-run full `scripts/validate.py` G25 suite end-to-end (long); reimplemented the attack surface matrix against the commit’s module API instead — sufficient for adversarial claims requiring minimal repros.
- Did not treat post-`5c7068f` working-tree kinds (`acceptance-eval-declaration-missing`, `eval-ledger-evidence-missing`, …) as part of this commit’s defense or debt.

## Open questions

- none that block the verdict. Product choice remains: whether missing ledger stays OUT forever or becomes a later mandatory-file gate (out of this slice).

## Verdict

**REWORK**

Must-fix before treating the RAE Feedback hard rule as fail-closed:

1. **F1** — any *written* Feedback line that is near-miss / full-width on the label or separator must not collapse to absent silence; report `acceptance-eval-feedback-unparsable` (or accept only a single canonical form and reject lookalikes closed). Add teeth for full-width colon at minimum (mirror G25n’s threat model).
2. **F2** — stop letting fenced/example `- Feedback:` lines arm or disarm the gate (e.g. last non-fenced occurrence, or require a fixed decision-template section and ignore fenced lines). Add a bidirectional tooth.

Do **not** block the slice for N1 (documented OUT) or for architecture of same-round-only operands.

## Next recommendation

1. Fix `parse_feedback` fail-closed asymmetry (F1) and marker-in-prose/fence (F2); extend G25 with full-width colon + fenced first-wins mutation pairs.
2. Re-run this adversarial suite (F1/F2 + existing G25a–n controls) on the fix commit.
3. Keep OUT list honesty for missing ledger / incomplete due set; if product needs those closed later, that is a separate, explicit cross-layer design — not a silent extension of this rule.
