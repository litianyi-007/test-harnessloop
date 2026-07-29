---
task_id: exp-p9-B
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
mode: background
phase: done
progress_log: ./exp-p9-B-progress.log
raw_log: ./exp-p9-B-output.log
log: ./exp-p9-B-output.log
---

# exp-p9-B · code-review-adversarial · harnessloop `6c92440` (v0.33.2)

**评审对象**：`harnessloop` commit `6c9244054a666c26d6f6c3e8483d7fa964bc4700`  
**标题**：`v0.33.2 [P0]：修 v0.32.0 的静默放行 + 一次类级扫除（裸 \d 共 5 处，含守卫自己）`  
**方法**：只读。`git worktree add --detach /tmp/hl-review-6c92440-wt 6c92440`；对 commit 树的 `verify_protocol.py` / `validate.py` 做 tempfile 反证；跑完整 `python3 scripts/validate.py`（exit 0）；对照 parent `6c92440^` 确认 X1 与裸 `\d` 基线。未改 harnessloop 工作树业务文件。

**Assumption**：任务未附独立 acceptance 列表时，以 commit 自述（X1 关闭、`[0-9]` 五处扫除、G34a–e / G35a–c teeth、OUT 诚实边界）+ 对抗面 1–6 为验收面。

---

## Summary

Commit `6c92440` correctly closes the v0.32.0 X1 switch in `check_loop_predecessor_declaration`: a round that declares `- Predecessor:` while sitting in a non-`^[0-9]{4}$` directory no longer returns zero violations via `except ValueError: return [], state`. The fix uses fail-closed `loop-predecessor-round-unnumbered`, restricts itself to declaring rounds only (zero-migration preserved), and rejects full-width digits via explicit `[0-9]` rather than bare `\d` / `.isdigit()` / bare `int()` — G34a–e give real paired mutations, including the full-width discriminator G34d.

The five-site `\d` → `[0-9]` sweep (ROUND_SEGMENT / PREDECESSOR_VALUE / LINE_SUFFIX / SEMVER_VERSION / normalize_slug) and the AST-based G35a structural guard (with G35b destructive counterproof and G35c language-fact pins) are real and green on the commit tree (`scripts/validate.py` exit 0; G35a scans 5 plugin `.py` files, zero hits, empty whitelist). OUT-column text honestly registers the still-open broader “any round directory name is accepted by `verify_project`” surface.

Residual (same defect *family*, not the fixed X1 path): `_latest_round_decision_text` still ranks “latest” with bare `int(round_dir.name)`, which accepts full-width digits and non-four-digit numeric names, so a planted `００１０` or `100` directory can suppress or forge `loop_autocontinue_anomaly` (non-exit-code signal only). Its docstring still claims parity with predecessor’s old soft-skip — false after this commit. That is incomplete class hygiene, not a reopening of the predecessor silent-pass. **Verdict: PASS_WITH_NOTE.**

---

## Files touched

none (read-only review; deliverable is this handoff file only)

Reviewed paths (no edits):

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | X1 fix, `ROUND_NAME_STRICT_RE`, three `[0-9]` regex fixes, predecessor gate |
| `scripts/validate.py` | G34a–e + G35a/b/c teeth; `SEMVER_VERSION_RE` `[0-9]` |
| `plugins/harnessloop/skills/harnessloop-loop/scripts/init_project.py` | `normalize_slug` defense-in-depth `[0-9]` |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN/OUT for unnumbered + residual open surface |
| 4 version manifests | `0.33.2` all four (G28 surface) |

---

## Acceptance verification (6/6 attack surfaces + commit claims)

### 1. Silent zero-check (X1) closed for declaring rounds — **PASS**

Parent (`6c92440^`) still had:

```python
try:
    current_round_num = int(round_dir.name)
except ValueError:
    return [], state
```

At `6c92440`, independent tempfile runs against the commit blob:

| fixture | kinds |
|---------|-------|
| dir `abc` + `Predecessor: 0003` (0003 exists) | `loop-predecessor-round-unnumbered` |
| dir `０００７` + `Predecessor: 0003` | `loop-predecessor-round-unnumbered` |
| dir `007` + `Predecessor: 0003` | `loop-predecessor-round-unnumbered` (int succeeds but not four digits) |
| dir `abc`, **no** Predecessor field | `[]` (declared=False) |
| dir `0007` + `Predecessor: 0003` | `[]` |
| dir `0007` + `Predecessor: ０００３` | `loop-predecessor-invalid-value` |
| dir `0000` + `Predecessor: 0003` | `loop-predecessor-not-backward` (not misclassified unnumbered) |

G34a–e all `ok` in full `scripts/validate.py` on the commit worktree.

### 2. Regex class traps (`\d` vs `[0-9]`) on the five claimed sites — **PASS**

At parent: `LINE_SUFFIX_RE`, `ROUND_SEGMENT_RE`, `PREDECESSOR_VALUE_RE` used bare `\d{4}` / `\d+`.  
At `6c92440`: all three + `SEMVER_VERSION_RE` + `normalize_slug` use `[0-9]`.

Independent checks:

```
ROUND_NAME_STRICT_RE.match('０００７')     → False
PREDECESSOR_VALUE_RE.match('０００３')     → False
ROUND_SEGMENT_RE.match('０００８')         → False
SEMVER_VERSION_RE.match('０.３３.２')      → False
strip_locator_suffix('foo.py:１２')       → 'foo.py:１２'  (not stripped)
re.match(r'^\d{4}$', '０００７')          → match   (language fact)
re.match(r'^[0-9]{4}$', '０００７')        → no match
int('０００７') == 7                       → True
```

AST scan of all 5 plugin `.py` files at this commit: **zero** bare-`\d` patterns outside character classes (matches G35a).

### 3. Parser bypasses on `parse_loop_predecessor_declaration` — **PASS** (known OUT gaps registered)

Same `_uncoded_lines` family as Feedback/Review/Acceptance evals:

| input | parsed raw | notes |
|-------|------------|-------|
| `- Predecessor: 0003` | `0003` | live |
| fenced bad then unfenced good | `0003` | fence stripped (G32i) |
| fenced only | `None` | absence |
| `` `- Predecessor: 0003` `` whole-line inline code | `None` | does not `startswith("- predecessor:")` after strip — correct for rendered non-field |
| mid-line “discussing …” | `None` | not a label line |
| full-width colon `Predecessor：` | `None` | absence (optional field → silent; same family as other label parsers) |
| 4-space indented “code block” | `0003` | **still live** — documented OUT for all `_uncoded_lines` callers, not introduced here |

No new fenced-shadow or “discussing = enabling” hole specific to this field.

### 4. Cross-time-layer joins — **PASS** (honest, not expanded)

Constraint 4 still checks predecessor **directory existence on today’s disk** — can retroactively redden a citing round if the predecessor dir is deleted. SKILL OUT explicitly registers this and contrasts it with the withdrawn forward-`continued:` design. Arithmetic constraints 2–3 use only this round’s own name + declared value (after ROUND_NAME_STRICT). No new cross-round join introduced.

### 5. Teeth quality (shape vs property; green-by-construction) — **PASS_WITH_NOTE**

| tooth | property vs shape | destructive counterproof? |
|-------|-------------------|---------------------------|
| G34a | property (abc → unnumbered; rename → clear) | yes, paired mutation |
| G34b | property (no field → green; add field → red) | yes |
| G34c | property (3-digit int-success still red) | yes |
| G34d | property (full-width name red despite isdigit/int/\d) | yes + language preconditions |
| G34e | negative control (0000 is numbered, not-backward) | yes |
| G35a | **implementation shape** (no bare `\d` in `re.*` AST) | walk not empty (scanned≥5); whitelist empty asserted |
| G35b | detector can fire | yes (`^\d{4}$` → True; `[0-9]` → False) |
| G35c | language facts | pinned, not production path |

**NOTE**: G35a is deliberately shape-level (correct for regression class). Property coverage for full-width is strong on **ROUND_NAME_STRICT** (G34d) but there is no G34-style end-to-end tooth that `PREDECESSOR_VALUE_RE` / `LINE_SUFFIX_RE` / `ROUND_SEGMENT_RE` reject full-width in the live gate — only the shared shape guard. Residual risk is low while G35a stays green.

### 6. OUT-column honesty — **PASS_WITH_NOTE**

**Honest:**

- SKILL IN describes `loop-predecessor-round-unnumbered` + `[0-9]` not `\d`/`.isdigit()`.
- SKILL OUT #500: unnumbered **only** for declaring rounds; not a project-wide name rule; `verify_project` still accepts any dir name.
- Commit message OUT: same residual surface called out.

**Stale / incomplete honesty (NOTE, F2 below):**

- `_latest_round_decision_text` docstring still says it mirrors predecessor’s “left unvalidated rather than crashing” treatment. After this commit, predecessor **fail-closes** for declaring rounds; the sibling still soft-skips non-int names and **trusts** any `int()`-parseable name (including full-width and `100`). Doc claims a shared convention that no longer holds.

### 7. Commit plumbing — **PASS**

- Version `0.33.2` on all four manifests.
- Full `python3 scripts/validate.py` on detached `6c92440` worktree: **exit 0**, Plugin framework validation passed; G34/G35 block all `ok`.

---

## Findings (author-miss class)

### F1 — NOTE / SHOULD FIX · bare `int(round_dir.name)` still selects “latest” (same digit family, different switch)

**Where**: `verify_protocol.py` `_latest_round_decision_text` (~L3913–3955 at commit)

```python
numbered.append((int(round_dir.name), round_dir))  # bare int: full-width OK
...
_, latest_round_dir = max(numbered, key=lambda pair: pair[0])
```

**Why it is the same family**: G34d/G35c themselves pin `int('０００７') == 7`. The commit fixed predecessor’s trust in `int(name)` by gating with `ROUND_NAME_STRICT_RE` first, then swept **regex** `\d` class-wide — but left this consumer of raw `int(name)` unchanged. G35 only scans `re.<func>(pattern)` literals; it cannot see bare `int()`.

**Minimal reproducible attack** (commit blob, tempfile project with Profile=standard, Auto-continue on positive=yes, evidence-index all valid):

**A — suppress anomaly**

```
rounds/0008/decision.md  → Feedback: neutral
rounds/0009/decision.md  → Feedback: positive, Predecessor: 0008   # real latest
rounds/００１０/decision.md → Feedback: negative                   # full-width name, int=10
```

Expected if “latest” means four-digit ASCII max: anomaly **1** (0009 positive).  
Actual: `_latest_round_decision_text` returns ００１０’s decision → `loop_autocontinue_anomaly=0`.

**B — forge anomaly**

```
rounds/0009/decision.md  → Feedback: negative
rounds/００１０/decision.md → Feedback: positive
```

Actual: `loop_autocontinue_anomaly=1` while true ASCII-latest is negative.

**C — non-fullwidth shape**

Directory name `100` (`int=100`) beats `0009` (`int=9`) the same way.

**Severity bound**: anomaly is **never a violation / never exit code** (SKILL IN already says so). Impact is signal integrity for batch-3, not hard-gate bypass. Predecessor X1 remains closed. Planting a fake round dir is loud on disk.

**Fix shape**: rank latest only among `ROUND_NAME_STRICT_RE.match(name)` directories (or require `^[0-9]{4}$` before `int`); align docstring; add a G33-style tooth that full-width / three-digit names cannot win “latest.”

### F2 — NOTE · stale docstring after this commit

Same function claims predecessor still soft-skips unparsable names. That was true in v0.32.0 / parent; this commit inverted it for declaring rounds. **Introduced inconsistency by this change** (did not update the sibling comment). Pure honesty debt; no behavioral effect beyond misleading the next editor into re-copying the soft-skip pattern.

### F3 — NOTE · property teeth gap for non-ROUND_NAME sites

`LINE_SUFFIX_RE` / `PREDECESSOR_VALUE_RE` / `ROUND_SEGMENT_RE` full-width behavior is correct in code (independent probes above) but only G35 shape + SEMVER pattern string check guards them. One end-to-end tooth each (or one parameterized table) would match the discipline G34d sets for ROUND_NAME. Not ship-blocking while G35a is green.

### Non-findings (credit)

- **X1 fix is real**, not vacuous: G34b proves green-without-field flips red when only the field is added; G34a proves red-with-bad-name flips green when only the directory is renamed.
- **Scope discipline**: not a general round-name rule; OUT and G34b agree.
- **Full-width on predecessor *value*** fail-closes as `invalid-value`, not silent absence.
- **AST over text for G35**: correctly ignores comment prose that still quotes `\d` while documenting the bug.
- **G35b** prevents green-by-construction on the detector.
- **Fence / first-occurrence** for Predecessor already covered (G32i) and reconfirmed.
- Four-manifest version bump consistent at `0.33.2`.

---

## Decisions / deviations

- Judged tree **exactly at `6c92440`**, not worktree HEAD (`c9c884e` / later). Worktree materialised via `git worktree add --detach`.
- Treated F1 as NOTE rather than REWORK because: (1) primary P0 X1 is closed with destructive teeth; (2) residual only pollutes a non-exit-code anomaly signal; (3) commit’s structural claim was about bare **`\d` regex**, which is fully met under `plugins/harnessloop/`.
- Full-width colon → silent optional absence is **not** scored as FAIL (same optional-field upper bound as `- Acceptance evals:` / undeclared Predecessor).

---

## Open questions

- none that block the verdict. Product fork for a future issue: whether “latest” and project-wide round names should require `^[0-9]{4}$` (would be the broader evolution item SKILL OUT already defers).

---

## Verdict

**PASS_WITH_NOTE**

Primary P0 is fixed correctly; class-level bare-`\d` sweep + G35 teeth are real and green. Residual F1/F2 are the same *digit/int* family left on the anomaly “latest” path, with a stale docstring — track and fix, do not reopen the predecessor gate design.

---

## Next recommendation

1. **Should (same class hygiene)**: teach `_latest_round_decision_text` to only consider `ROUND_NAME_STRICT_RE` names; skip others the way non-int names are skipped today. Add a paired mutation tooth (full-width higher-int dir must not change anomaly vs ASCII-only tree).
2. **Should**: rewrite that function’s docstring so it no longer claims predecessor still soft-skips.
3. **Optional**: one property tooth each for PREDECESSOR full-width value → `invalid-value`, LINE_SUFFIX full-width not stripped, ROUND_SEGMENT full-width not a TH-0026 pair.
4. Leave project-wide round-name policing as its own evolution issue (OUT already correct).
5. No rework required on the predecessor fail-closed path itself before accepting v0.33.2’s P0 claim.

---

**Review target confirmation**: commit `6c9244054a666c26d6f6c3e8483d7fa964bc4700` only. Parent X1 / bare-`\d` baselines verified via `git show 6c92440^:…`. Full validate run: exit 0 on detached worktree. Review only — zero edits to plugin source.
