# Adversarial review: harnessloop `aec2de6`

**Commit**: `aec2de67652dbdaa5930dc640ea4b2671b0f99cd`  
**Subject**: CI 修复第二轮：3 条 Windows symlink 语义失败（自 v0.25.0 起一直红）  
**Scope reviewed**: `scripts/validate.py` only (+306/−38). Production `verify_protocol.py` unchanged.  
**Review type**: code-review-adversarial (read-only; no edits to harnessloop).  
**Assumption (1 line)**: task id is `exp-p3-A` from hopper progress; acceptance = brief attack-surface hunt + structured verdict.

---

## Summary

Commit `aec2de6` is a **test-harness adaptation**, not a production containment change: it classifies platform `Path.resolve` behavior for the symlink-then-`..` shape (`canonical` / `lexical` / `unsupported` / loud `unrecognized`), gates the three T-064 MUST-FIX C fixtures that were red on Windows, and adds G30a/G30b teeth so pure-symlink escape stays live everywhere symlinks work. The root-cause claim matches CPython `ntpath.realpath` (first executable step is `path = normpath(path)` before reparse following) and is consistent with local macOS probe results (`canonical`, pure `link/escape.md` → rejected). No reproducible product regression or silent-zero false green was demonstrated on a platform where the escape shape is constructible; residual notes are coverage honesty and still-unverified Windows CI green.

## Files touched

- `harnessloop/scripts/validate.py` — runtime `_dotdot_symlink_semantics` / `_classify_dotdot_symlink_resolution`; gates T-064 MUST-FIX C direct-base + `.gitmodules` mutation control on classification; leaves `.gitmodules` outcome asserts unconditional; adds G30a (pure classifier) + G30b (live pure-symlink reject).

## Acceptance verification (6/6 attack surfaces)

| # | Family | Result | Evidence |
|---|--------|--------|----------|
| 1 | Parser bypasses (inline/fenced/full-width) | **N/A — clean** | Diff is fixture/teeth only; no citation/field parsers, no markdown field reads. `git show aec2de6 --stat` → single file `scripts/validate.py`. |
| 2 | Silent zero-check | **PASS** | Unrecognized classification fails loudly at shared probe: `check(_dotdot_semantics in ("canonical", "lexical", "unsupported"), ...)` (`validate.py` ~2589–2595). Fixture `else:` branches also `check(False, ...)` (~2697–2702, ~2799–2806). Lexical path is `print` skip with explicit reason, not empty success. |
| 3 | Regex class traps (`\d`/`\w`) | **N/A — clean** | No new regex / `int()` digit parsing in this commit. |
| 4 | Cross-time-layer joins | **N/A — clean** | No round/goal joins; only temp fixtures under `.tmp/`. |
| 5 | Teeth shape / green-by-construction | **PASS_WITH_NOTE** | G30b is a real counterproof (live symlink + `_resolve_in_project is None`). G30a is pure `==` on fabricated `Path`s (branch labels only) — acceptable unit tooth but not a filesystem counterproof; see Notes. `.gitmodules` `all(roots…)` is vacuous when `roots==[]` (`all([]) is True`); end-to-end `pkg/modghost.py` dangling assert is the real outcome tooth and stays unconditional. |
| 6 | OUT-column honesty | **PASS_WITH_NOTE** | Commit message honestly states Windows was not run locally and is inference from `ntpath` + CI failure text. Skip text correctly points at pure-symlink coverage, but slightly over-attributes “every platform” to T-063 (git-gated) vs G30b (symlink-gated only). Direct-base mutation control still claims MUST-FIX C is “load-bearing” even on lexical platforms where pre/post-fix both land inside for the fully-cancelled shape. |

### Live checks performed (this reviewer, macOS)

```text
_dotdot_symlink_semantics → canonical
G30b: _resolve_in_project(project, "link/escape.md", project) → None  (with and without outside file)
product still rejects: link/../escape.md, link/sub/../escape.md, link/nested/../escape.md on canonical
ntpath.realpath source (local CPython 3.9): first line of body is `path = normpath(path)`
ntpath.normpath residual analysis:
  link/../escape.md        → C:\project\escape.md     (symlink fully cancelled)
  link/sub/../escape.md    → C:\project\link\escape.md (symlink REMAINS → pure-symlink form)
  link/nested/../escape.md → C:\project\link\escape.md (same)
```

### Why the Windows skip is not a silent hole (reproducible reasoning, not Windows run)

Fully-cancelled shape `link/../escape.md` cannot construct an outside landing via Windows `normpath`-first realpath; it folds to the in-project basename. Shapes where `..` only cancels *interior* segments leave `link/...`, which is exactly G30b’s vector (`link/escape.md`). So gating the T-064 C *fully-cancelled* counterexample on `lexical` does not drop the residual dangerous form, provided G30b (and T-063 when git exists) stay live — which this commit explicitly preserves for G30b.

### Attempted attacks that did **not** yield FAIL

1. **Mis-probe with relative tmp paths** → classification `unrecognized` (absolute `REPO_ROOT/.tmp` avoids this; production probe uses absolute `REPO_ROOT / ".tmp"`).
2. **Pure symlink with target file present** → still `None` from `_resolve_in_project` (containment, not absence).
3. **Vacuous `all([])` alone** → weak tooth, but paired e2e dangling check remains; not a regression introduced as the sole guard.

## Decisions / deviations

- No Windows runner available here either; Windows-green claim treated as **author-stated inference**, same honesty bar as the commit message.
- Did not re-run full `scripts/validate.py` (long suite); exercised new helpers + production `_resolve_in_project` / `submodule_roots` in isolation.
- Did not treat “missing positive lexical assertion” as FAIL: no minimal attack shows a shipping false green on a constructible escape; it is a coverage note.

## Open questions

1. Will the next `windows-latest` CI job actually go green, including Path equality under any `\\?\` extended-length prefix quirks for the probe’s `resolved == inside_target` test?
2. Should the lexical branch grow a **positive** pin (e.g. `_resolve_in_project(..., "link/../escape.md", ...)` returns the in-project coincidental path, and/or an explicit `link/nested/../escape.md` → same as G30b residual) so Windows behavior is locked rather than only skipped?
3. Worth a one-line honesty fix in skip text: “G30b (and T-063 when git is available)” instead of implying T-063 is unconditional on every platform?

## Verdict

**PASS_WITH_NOTE**

No FAIL-grade defect with a reproducible minimal attack against production containment or against a silent-zero gate. The change correctly distinguishes “escape shape not constructible on this platform” from “skip the protection,” keeps pure-symlink rejection live (G30b), fails loud on unknown semantics, and matches CPython’s documented Windows realpath order. Notes are residual test honesty/coverage, not open containment holes on platforms where the documented counterexample still fires (macOS/Linux).

## Next recommendation

1. **Land and wait for the next `windows-latest` validate job** — treat that as the real confirmation of the lexical branch (author already said so).
2. Optional small follow-up (non-blocking): add lexical **positive** asserts + tighten skip-message attribution (T-063 vs G30b); optional residual fixture `link/nested/../escape.md` as documentation that partial-`..` reduces to G30b’s form under `ntpath.normpath`.
3. No production code change required from this review; no rework gate on `aec2de6` itself.

---

## Finding detail (for auditors)

### F1 — NOTE — G30a green-by-construction

**Where**: `validate.py` G30a block (~5107+).  
**What**: Classifier tests only `Path == Path` with fabricated absolute paths; never touches disk or the shared probe.  
**Why not FAIL**: Spec property of the pure function is equality of three inputs; G30b + top-level recognized-class check supply live teeth.  
**Destructive counterproof for G30b** (macOS):

```python
# project/link -> outside/; outside/escape.md exists
verify_protocol._resolve_in_project(project, "link/escape.md", project)  # → None
# If _is_contained degraded to lexical is_under only, this would return non-None (pre-T-063).
```

### F2 — NOTE — Lexical direct-base has no positive pin

**Where**: `elif _dotdot_semantics == "lexical": print(skipped...)` for direct-base unit+e2e.  
**What**: Windows neither asserts rejection nor documents acceptance of the coincidental in-project file.  
**Risk**: Over-reject regressions on Windows for fully-cancelled paths would not be caught by these fixtures.  
**Why not FAIL**: Fully-cancelled path is not an escape on lexical realpath; residual forms covered by G30b.

### F3 — NOTE — Skip text over-attributes T-063

**Where**: lexical skip message (~2673–2685).  
**What**: Claims T-063 MUST-FIX 2 runs live on every platform; that fixture is behind `git_available` (~2474–2572). G30b is the unconditional (symlink-only) tooth.  
**Why not FAIL**: Combined coverage intent is correct; wording slightly overstates T-063’s gate.

### F4 — NOTE — Windows still inference

**Where**: commit message “未能本地验证…下一次 windows CI 才算数”.  
**What**: Same limitation for this review. Verdict does not certify Windows green.
