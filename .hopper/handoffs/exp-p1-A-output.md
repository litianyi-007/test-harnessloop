---
task_id: exp-p1-A
adapter: grok
model: grok-4.5
requested_selector: null
effective_selector: grok-4.5
effective_selector_source: policy
status: done
mode: background
phase: done
---

# exp-p1-A · code-review-adversarial · harnessloop `5c7068f` (v0.27.0)

**评审对象**：`harnessloop` commit `5c7068f38cea9bb6de340e3f3be2f22644d671f5`  
**标题**：`v0.27.0: runtime acceptance evals 竖切落地——一条硬规则 + 14 个 fixture 反证`  
**方法**：只读；`git show 5c7068f` + 从该 commit 抽出的 `verify_protocol.py` 做独立 tempfile 反证（不复用 G25 fixture 路径）。未改 `harnessloop/` 工作树。

**Assumption**：本任务无更细 acceptance 列表时，以 commit message 自述的硬规则、14 kinds、fail-closed Feedback、版本 bump、G25 双向 teeth 为验收面。

---

## Summary

This commit lands a real, fixture-backed vertical slice for runtime acceptance evals: one same-round hard rule (`frozen_due_set` all have `outcome=="pass"` or Feedback may not be `positive`), strict JSON loading, registry/ledger shape checks, SKILL IN/OUT honesty, and solid G25 paired mutations for the core path. The intentional OUT bounds (absent ledger = silent; self-reported due set) are documented and pinned by G25l.

However, the hard rule — which the commit itself calls the entire meaning of the slice — has a **false-green escape** via full-width colon on the Feedback label (`- Feedback：positive`). That spelling is treated as “field absent” (zero-migration silence) rather than unparsable, so an unsatisfied due set produces **no** `acceptance-eval-*` violation. That contradicts the commit’s own full-width-punctuation fail-closed claim (which only covers the *value* side, e.g. `positive。`). Combined with release hygiene (`.codex-plugin/plugin.json` left at `0.11.0` while other manifests go to `0.27.0`) and incomplete teeth for 4 of 14 kinds, this is **REWORK**, not a note.

---

## Files touched

none (read-only review; deliverable is this handoff file only)

Reviewed paths (no edits):

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | RAE gate implementation (+594 lines) |
| `scripts/validate.py` | G25a–n teeth (+476 lines) |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN/OUT coverage text |
| `package.json`, `.claude-plugin/marketplace.json`, `plugins/harnessloop/.claude-plugin/plugin.json` | version → 0.27.0 |
| `plugins/harnessloop/.codex-plugin/plugin.json` | **not** bumped (still 0.11.0 at this commit) |

---

## Acceptance verification (6/6 criteria exercised)

### 1. Hard rule: unsatisfied `frozen_due_set` + `Feedback: positive` → red — **PASS (ASCII path only)**

**Evidence (independent fixture against commit blob):**

- Ledger: one entry `eval_id=RAE-0001`, `outcome=fail`, `frozen_due_set=["RAE-0001"]`
- Decision: `- Feedback: positive` (ASCII colon U+003A)
- Result kinds include `acceptance-eval-positive-without-pass`
- Control: flip only `outcome` to `pass` → kind absent (matches G25a/b intent)

Also verified: missing due id entirely with unrelated pass (G25c shape); `skipped` is not pass; `Feedback: negative` does not fire the positive-only rule (G25k shape).

### 2. Fail-closed Feedback normalization for full-width punctuation — **FAIL (label-side escape)**

Commit claims: full-width punctuation must not silently become “not positive”; unparsable → `acceptance-eval-feedback-unparsable`.

| Feedback line | `parse_feedback` raw | acceptance-eval kinds with unsatisfied due |
|---|---|---|
| `- Feedback: positive` | `positive` | `acceptance-eval-positive-without-pass` |
| `- Feedback: positive。` (U+3002) | `positive。` | `acceptance-eval-feedback-unparsable` only (G25n OK) |
| **`- Feedback：positive` (U+FF1A full-width colon)** | **`None` (treated as absent)** | **`[]` — hard rule silent** |
| `- **Feedback:** positive` | `None` | `[]` — also silent |

**Root cause (source):** `parse_feedback` only matches ASCII `"- feedback:"` via `.startswith` after lowercasing the line; it never treats full-width `：` as a label separator. Absent field → intentional zero-migration silence in `verify_round`, which is correct for *true* absence but wrong when the author clearly wrote a Feedback line the IME full-widthed.

**Minimal counter-example (reproduced):** same unsatisfied ledger; only change ASCII `:` → full-width `：` → RAE violation count goes from 1 to 0. This is not theoretical.

Value-side G25n still holds; the hole is the **label separator**, which Chinese authors hit at least as often as trailing `。`.

### 3. Strict JSON / no silent zero-check on bad ledger — **PASS**

- Malformed JSON → `eval-ledger-invalid` (G25g)
- Duplicate key `"outcome": "pass", "outcome": "fail"` → `eval-ledger-invalid` via `object_pairs_hook` (G25m)
- Empty ledger file absent + positive → zero RAE violations (G25l / documented OUT)

**NOTE on G25m narrative:** the commit/test text says plain `json.loads` on the **pass-then-fail** fixture “would have gone GREEN”. Independent check: naive `json.loads` keeps **last** value `"fail"` → hard rule would still red via `positive-without-pass`. The actual silent-green order under naive loads is **fail-then-pass**. Teeth still prove the hook is wired; the destructive-control *story* is inverted for the chosen key order.

### 4. Fourteen kind surface + G25 teeth — **PARTIAL (10/14 kinds named in G25 text)**

Kinds with dedicated G25 assertions:  
`acceptance-eval-positive-without-pass`, `acceptance-eval-feedback-unparsable`, `eval-ledger-attempt-id-round-mismatch`, `eval-ledger-frozen-due-set-missing`, `eval-ledger-frozen-due-set-inconsistent`, `eval-ledger-invalid`, `eval-ledger-invalid-outcome`, `rae-invalid`, `rae-duplicate-eval-id`, `rae-invalid-activation-round`.

Kinds implemented but **not** named in any G25 assertion string:
- `rae-invalid-eval-id`
- `eval-ledger-invalid-attempt-id`
- `eval-ledger-frozen-due-set-invalid-type`
- `eval-ledger-frozen-due-set-invalid-element`

Implementation of those four was spot-checked by reading code paths; lack of paired red/green teeth is a coverage claim gap, not proof they are dead code.

### 5. Version bump consistency for v0.27.0 — **FAIL**

At tree `5c7068f`:

| File | version |
|------|---------|
| `package.json` | 0.27.0 |
| `.claude-plugin/marketplace.json` | 0.27.0 |
| `plugins/harnessloop/.claude-plugin/plugin.json` | 0.27.0 |
| **`plugins/harnessloop/.codex-plugin/plugin.json`** | **0.11.0** (unchanged from parent) |

`scripts/validate.py` `validate_manifests()` at this commit checks names/licenses only — **no** cross-manifest version equality — so CI green does not catch this. Same defect class as the historical “forgot `.codex-plugin` for 18 minors” incident.

### 6. Documented OUT bounds honesty — **PASS**

SKILL.md OUT column and commit message correctly state: (a) missing ledger ⇒ zero hard-rule violations; (b) due-set completeness not checked (self-reported). G25l pins (a) as an executable assertion. These are intentional product limits, not hidden false greens *if* the ledger file is present and Feedback is parseable.

---

## Findings (severity-ordered)

### F1 — MUST-FIX / REWORK · Hard-rule false green via full-width Feedback colon

- **What:** `- Feedback：positive` + unsatisfied due set → no `acceptance-eval-*` kind.
- **Why it matters:** Commit message: the hard rule is “本竖切的全部意义”. Escaping it with a single IME character while keeping human-readable “positive” intent is a live false green on that rule.
- **Why author likely missed it:** G25n only mutates the *value* (`positive。`); no tooth mutates the *separator*. Parser reuses “absent = silent” from E4/zero-migration without distinguishing “line looks like Feedback but separator is wrong”.
- **Fix direction (for implementer, not done here):** either accept full-width `：` as label separator, or if a line matches `feedback` + full-width colon treat as unparsable (fail-closed), never as absent.

### F2 — Medium · Release metadata incomplete

- `.codex-plugin/plugin.json` remains `0.11.0` on a v0.27.0 release commit; three other manifests bumped.
- No version-equality tooth in `validate_manifests` at this commit.

### F3 — Low · G25m destructive-control claim false for chosen key order

- Hook wiring is real; narrative “plain loads → green” needs the reverse duplicate-key order.

### F4 — Low · Four kind codes lack paired G25 teeth

- Claim “14 kinds + G25a–n every bidirectional” overstates coverage for eval_id / attempt-id shape / due-set type+element.

### F5 — Note · Ledger `eval_id` presence/format not enforced

- Docstring schema shows `eval_id` on entries; implementation never emits a ledger-side invalid-eval-id kind. Hard rule still cannot credit a pass without a matching string `eval_id`, so integrity impact is low; schema honesty is the issue.
- Related silent forms: empty `{}` ledger ⇒ vacuous empty due set + positive is green (consistent with “empty entries ⇒ empty due”); bold markdown Feedback label also silent (same absent path as F1).

### Not defects (called out so they are not re-litigated)

- Absent ledger ⇒ hard rule silent — **documented OUT**, G25l.
- Incomplete self-reported `frozen_due_set` — **documented OUT**.
- Symlink ledger: pre-existing `round-artifact-is-symlink` still reds the round; not a clean overall green via symlink alone.
- `evals.json` never joined into the hard rule — intentional same-round construction.

---

## Decisions / deviations

- Reviewed the commit tree at `5c7068f` via `git show` + imported blob, not whatever is currently on `HEAD` (workspace is later, e.g. 0.36.x), so findings are about the shipped vertical slice as of that commit.
- Did not treat later historical fixes (if any) as evidence; only independent repro against this blob.
- No edits, no push, no re-dispatch.

---

## Open questions

- none that block the verdict. Optional product choice: should missing `Feedback` on a round that *has* a non-empty ledger with unsatisfied dues also fail-closed? Currently silent by design (zero-migration); F1 is worse because the author *did* write Feedback.

---

## Verdict

**REWORK**

Blocking: **F1** hard-rule false green via full-width colon (and same absent-path family for other non-ASCII/markdown label spellings).  
Non-blocking but should ride along: **F2** codex-plugin version lag; **F3–F4** teeth honesty.

---

## Next recommendation

1. Fix `parse_feedback` (or the hard-rule branch) so a Feedback line with full-width `：` cannot be classified as “absent”; add a G25 paired tooth: unsatisfied due + `Feedback：positive` must red (`unparsable` or `positive-without-pass`, pick one and stick to fail-closed).
2. Bump `plugins/harnessloop/.codex-plugin/plugin.json` with the release (or add a discover-all-manifests version equality check so this cannot recur).
3. Optionally extend G25 to the four untested kinds and correct the G25m naive-loads narrative (use fail-then-pass order if claiming “would go green”).
4. Re-run this adversarial review on the fix commit before calling the vertical slice’s hard rule production-safe.
