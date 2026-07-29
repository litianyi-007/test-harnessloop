---
task_id: exp-p6-B
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
progress_log: ./exp-p6-B-progress.log
raw_log: ./exp-p6-B-output.log
log: ./exp-p6-B-output.log
---

# exp-p6-B · code-review-adversarial · harnessloop `d9989ca` (v0.31.0 / TH-0026)

**评审对象**：`harnessloop` commit `d9989ca70b2eb2f7428aa247ebbb40ad9ac541c6`  
**标题**：`v0.31.0：TH-0026 提示层落地——scope-lock 指向不存在路径不再静默零覆盖（本仓自查 6 例）`  
**方法**：只读。从该 commit blob 抽出 `verify_protocol.py` / `validate.py` / `SKILL.md` 到 `/tmp/th0026-review/`，对纯函数与 `verify_project` 做 tempfile 反证；并对本仓 `.harnessloop/goals/**/rounds/*` 跑一次 d9989ca 门。未改 `harnessloop/` 工作树（工作树当时停在无关的 detached `v0.30.0`）。

**Assumption**：任务未附更细 acceptance 列表时，以 commit message 自述（6 例自查、提示层非违规、层内判据、三条 OUT、G31a–g teeth、四处版本 0.31.0）+ 对抗面 1–6 为验收面。

---

## Summary

Commit `d9989ca` delivers a real, layer-internal, hint-only detector for the two natural scope-lock mistakes that produced silent `rounds_zero_inspected` on this repo (literal `goals/.../` placeholders and missing `goals/<slug>/`). Independent re-run of the d9989ca gate against the live project reports `rounds_scope_lock_round_path_mismatch=6` on exactly the claimed rounds (0003/0005/0006/0007/0008/0009), with zero violations and exit-code neutrality preserved. Segment-wise comparison is load-bearing (G31d’s `xgoals/` control is a genuine counterproof against string `.endswith`).

It is not a full solution to “any wrong path → silent zero.” A pure path-algebra false negative remains: a span whose *first* `rounds/<NNNN>` pair has a correct prefix, but which Rule A’s `normpath` collapses via `..` into the classic missing-slug location, still yields `mismatch=0` + `zero_inspected=1` + empty violations. Combined with bare `\d` in `ROUND_SEGMENT_RE`, note/coverage walk desync on container escapes, and false-positive notes on legitimate non-goal paths like `docs/rounds/0008/…`, the right verdict is **PASS_WITH_NOTE**, not clean PASS.

---

## Files touched

none (read-only review; deliverable is this handoff file only)

Reviewed paths (no edits):

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `ROUND_SEGMENT_RE`, `_span_path_segments`, `scope_lock_round_path_mismatch`, `collect_scope_lock_round_path_mismatch_notes`, `verify_round` coverage bit, human-mode notes |
| `scripts/validate.py` | G31a–g teeth |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN coverage key + OUT upper bounds for TH-0026 |
| `package.json`, `.claude-plugin/marketplace.json`, `plugins/harnessloop/.claude-plugin/plugin.json`, `plugins/harnessloop/.codex-plugin/plugin.json` | version → 0.31.0 (all four) |

---

## Acceptance verification (8/8 criteria exercised)

### 1. Intended shapes flagged (classic missing `goals/<slug>/` + literal `...`) — **PASS**

**Evidence (live project, d9989ca blob):**

```
rounds=14 mismatch=6 zero_inspected=9 rule_a=8 violations=0
notes=6 → rounds 0003,0005,0006 (goals/.../) and 0007,0008,0009 (.harnessloop/rounds/NNNN/)
```

Control unit cases on synthetic `round_dir=…/goals/20260718-002-agent-app/rounds/0008`:

| span | flagged |
|------|---------|
| `.harnessloop/rounds/0008/` | yes |
| `.harnessloop/goals/.../rounds/0008/` | yes |
| `.harnessloop/goals/<slug>/rounds/0008/` | no |
| `goals/<slug>/rounds/0008/` | no |
| `rounds/0008/evidence/` (empty prefix) | no |
| `rounds/0007/` (other round) | no |

### 2. Hint-only: never a violation, never exit 1 — **PASS**

G31f/g shape re-verified independently:

- Project with only mismatched scope-lock (no other artifacts) → `violations == []`, `rounds_scope_lock_round_path_mismatch == 1`
- Two mismatched rounds → count `2`, still `violations == []`

Matches commit’s TH-0008 demotion precedent and SKILL IN text (“Hint only… never a violation, never affects exit code”).

### 3. Layer-internal operands (no disk-existence join) — **PASS**

`scope_lock_round_path_mismatch` only reads:

- span string segments
- `round_dir.name`
- `round_dir.parent.parent.relative_to(project)` (path algebra on the scope-lock’s own location)

No `.exists()` on the span path. Renaming/deleting an unrelated directory cannot flip this hint via existence. This correctly avoids the E1 trap the commit describes.

### 4. Segment comparison, not string `.endswith` — **PASS** (teeth have real counterproof)

G31d fixture: `xgoals/<slug>` **does** `.endswith("goals/<slug>")` as raw text, but pure function still flags. Independent check:

```
naive: "xgoals/20260718-002-agent-app".endswith("goals/20260718-002-agent-app") == True
fn:    scope_lock_round_path_mismatch("xgoals/…/rounds/0008/", …) is not None
```

This is not green-by-construction; it would fail under a string implementation.

### 5. Version consistency 0.31.0 (4 manifests) — **PASS**

At `d9989ca`, all four version files are `0.31.0` (including `.codex-plugin/plugin.json` — unlike the v0.27.0 incident).

### 6. OUT-column honesty vs delivered behavior — **PASS_WITH_NOTE** (see F5)

OUT lists three upper bounds; (2) different-round left alone and (3) not every zero_inspected are accurate and G31e pins (2). Bound (1) is mostly right for “need disk for arbitrary typos,” but overstates that *every* remaining wrong shape needs disk — pure `..` normalization would close F1 without a today-layer join (see below).

### 7. Silent-zero disease fully closed for all pure path wrong shapes? — **FAIL (F1)**

Reproducible false negative (exact fixture):

```text
# <project>/.harnessloop/goals/demo-goal/rounds/0008/scope-lock.md
# Scope Lock

## Allowed Changes

- `.harnessloop/goals/demo-goal/rounds/0008/../../../rounds/0008/`
```

(No `evidence/` / `reviews/` files.)

| Signal | Expected if TH-0026 closed the disease class | Actual (d9989ca) |
|--------|-----------------------------------------------|------------------|
| `rounds_scope_lock_round_path_mismatch` | ≥1 | **0** |
| pure `scope_lock_round_path_mismatch(...)` | note | **None** |
| `rounds_zero_inspected` | 1 | 1 |
| `violations` | [] (hint-only OK) | [] |
| Rule A effective path (`normpath` from project) | n/a | `…/.harnessloop/goals/rounds/0008` (missing slug — classic non-existent auth location) |

**Root cause:** algorithm takes the *first* adjacent `rounds/<NNNN>` pair and compares the *unnormalized* prefix. `_span_path_segments` drops `""` and `"."` but **keeps `".."`**. Rule A’s `is_under` uses `os.path.normpath`, so authorization and TH-0026 disagree on the same span string.

This is not “needs disk existence.” Collapsing `..` is pure segment algebra on the span (same layer as today’s check). Control: same tree with span `.harnessloop/rounds/0008/` → `mismatch=1` as intended.

### 8. Attack-family checklist (repo history) — **mixed**

| Family | Result |
|--------|--------|
| 1. Parser bypasses (inline / fence / full-width punct) | **Inherited, not regressed.** `extract_allowed_spans` still treats every backtick in `## Allowed Changes` as authorization (discussion ≡ enable). Fenced lines *with* ticks still extract; full-width backticks extract nothing. TH-0026 runs on whatever extract returns — prose mention of a wrong path correctly *notes* it (helpful); it does not invent a new parser. |
| 2. Silent zero-check / early return | **Partial.** Target shapes no longer silent. But F1 restores silent zero for a pure-path wrong shape. Also: `relative_to` ValueError → `return None` (documented degrade-to-silence for hints). |
| 3. Regex class traps `\d` vs `[0-9]` | **Present (F2).** At d9989ca: `ROUND_SEGMENT_RE = re.compile(r"^\d{4}$")`. Python: `re.match(r'^\d{4}$', '０００８')` is True; `[0-9]{4}` is False. Impact masked because `segments[i+1] != round_dir.name` fails for full-width vs ASCII directory names — latent footgun, no G31 tooth. (Later tree history fixed bare `\d` class-wide in v0.33.2; that fix is **not** in this commit.) |
| 4. Cross-time-layer joins | **Avoided for the main predicate** (good). Residual: notes walk is today’s tree (acceptable for human display); goal renames would re-label historical spans (hint-only). |
| 5. Teeth shape vs property | **Mostly good.** G31d has destructive counterproof. G31 does **not** pin `..` collapse, bare `\d`, or non-goal `docs/rounds/NNNN` false positives. |
| 6. OUT-column honesty | **Mostly good; F5 note** on “all other shapes need disk.” |

---

## Findings (severity-ordered)

### F1 — Medium: `..` collapse false negative restores silent zero (pure path algebra)

See acceptance §7. Minimal attack above. **Fix direction (no disk join):** normalize `..` (and reject/`flag` escape-above-root) in `_span_path_segments` *or* compare the normpath’d span prefix against the real prefix; still layer-internal.

### F2 — Low/latent: bare `\d` in `ROUND_SEGMENT_RE` (attack family 3)

```python
# d9989ca verify_protocol.py ~line 640
ROUND_SEGMENT_RE = re.compile(r"^\d{4}$")  # Unicode digits match
```

No G31 tooth. Equality to `round_dir.name` currently prevents false flags on full-width round tokens, but this is the exact class trap this repo has shipped before.

### F3 — Low: `collect_scope_lock_round_path_mismatch_notes` ignores container-escape discipline

`verify_project` skips symlink-escaping round dirs (`round-container-escapes-project`) and does not count them. `collect_*` walks `goals/*/rounds/*` with bare `is_dir()` / `read_text`, so it can print TH-0026 notes for rounds that contributed **0** to `rounds_scope_lock_round_path_mismatch` coverage.

**Repro:** symlink `rounds/0008` → outside tree with a mismatched scope-lock → coverage mismatch=0, notes length=1, plus an escape violation from the real gate.

### F4 — Low: false-positive note on legitimate non-goal paths containing `rounds/<thisNNNN>`

```text
## Allowed Changes
- `docs/rounds/0008/design-notes.md`
```

→ `mismatch=1` even though this is not an attempt to authorize the harnessloop round directory. Hint-only, so no exit-code damage; still noise and trains authors to ignore the note.

### F5 — Doc nit: OUT bound (1) slightly overclaims

SKILL says other wrong shapes “need a disk-existence join.” F1 shows at least one wrong shape is closed by pure normalization. Prefer: “shapes not expressible as (this-round number + wrong prefix), without path normalization / disk.”

### Non-findings (explicitly checked, clean)

- Four-way version bump to 0.31.0 including `.codex-plugin/plugin.json`
- Demotion to hint is consistent in code, SKILL IN text, and G31f/g
- Empty prefix / other-round OUT items behave as documented
- Live 6-case self-check claim is true under independent re-run
- Adding a coverage key is additive to `--json` `coverage` object; top-level `{project,violations,coverage}` shape unchanged (commit’s “不改 --json schema” is acceptable if read as violations/top-level, not “coverage keys frozen”)

---

## Decisions / deviations

- Reviewed **blob `d9989ca`**, not the submodule working tree (was detached at `v0.30.0` without this code). Function bodies for TH-0026 helpers match what `git show d9989ca` contains.
- Did not treat “hint does not clear `zero_inspected`” as a defect — commit and OUT explicitly scope value as visibility, not reducing 9→0.
- Did not FAIL solely on F2 because full-width digits do not currently bypass the intended ASCII cases.

---

## Open questions

- none that block the verdict; optional product call: should TH-0026 only fire when the span looks harnessloop-shaped (prefix contains `.harnessloop` or `goals`), to kill F4?

---

## Verdict

**PASS_WITH_NOTE**

Primary claim holds: the two natural silent-zero scope-lock shapes this repo actually shipped are now visible as a coverage counter + human notes, without permanent-red violations or an E1 disk join. Residual algorithm hole (F1 `..` / first-match vs Rule A normpath), latent `\d`, notes walk desync, and non-goal false positives keep this from a clean PASS.

---

## Next recommendation

1. **Accept v0.31.0 / TH-0026 as fixed-by-demotion for the documented shapes**; do not reopen as hard violations (would permanent-red closed rounds 0003–0009).
2. **Follow-up (small, pure):** normalize or reject `..` in `_span_path_segments` before prefix comparison; add G31h tempfile identical to F1 (expect `mismatch==1`); switch `ROUND_SEGMENT_RE` to `^[0-9]{4}$` with a full-width non-match tooth (align with later class-wide discipline).
3. Optional: gate the hint on harnessloop-ish prefixes to remove `docs/rounds/NNNN` false positives; align `collect_*` with `_container_escape_violation` so notes ⊆ coverage.
4. No rework required on the demotion decision, SKILL OUT items (2)(3), or the 6-case self-check evidence.
