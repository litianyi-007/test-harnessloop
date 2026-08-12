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
end_time: "2026-08-12T09:36:30.653Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 442596
adapter_status: success
last_progress_at: "2026-08-12T09:36:30.657Z"
last_progress: Task completed successfully.
progress_seq: 16
terminal_event_emitted: true
---
# T-103-grok — code-review-acceptance (hopper 0.55.0 pre-release)

**Reviewer:** grok (heterogeneous dual-path; independent of T-103-codex)  
**Target repo:** `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/hopper-plugin`  
**Scope:** full uncommitted working tree (20 modified + 3 untracked test files)  
**Mode:** read-only on product code; no edits to hopper-plugin  
**Date:** 2026-08-12  

**Assumption (1 line):** “dispatch.js 及其调用链” includes `composePrompt` in `tasks.js` (direct callee) and `queue.js` brief parsing (upstream of resolveDispatch), for Q3 family inventory.

---

## Summary

This change set ships hopper **0.55.0**: `loadTaskSpec` no longer returns self-describing placeholders; queue brief and detailed spec are merged (or fail-closed); section-END detection is a **union** of unconditional H2 boundaries plus known-other-id markers (three forms), with earliest match winning. Live execution of `loadTaskSpec` (not code-reading alone) confirms both halves of the union work, and H3/H4, line-start bold, and in-body markdown tables are not over-truncated. Release metadata is consistent at 0.55.0, vendored `plugins/hopper/cli` copies of `dispatch.js` and `hopper-dispatch` match sources, `cli/src/tasks.js` is byte-identical to HEAD, and CHANGELOG 0.55.0 line anchors match the current file. Residual same-family issues (structural-only body; `composePrompt` empty-spec depth) are already registered Open and unfixed by design this release.

## Files touched

| Path | Rationale |
|---|---|
| `cli/src/dispatch.js` | Core fix: `loadTaskSpec` union boundaries, null-not-prose, `composeTaskContent` merge/fail-closed, `fileExists` ENOENT-only |
| `plugins/hopper/cli/src/dispatch.js` | Vendored mirror of the above (byte-identical) |
| `cli/bin/hopper-dispatch` | VERSION → 0.55.0 (+ minor surface for notices/resolve) |
| `plugins/hopper/cli/bin/hopper-dispatch` | Vendored mirror |
| `package.json`, `package-lock.json` | Version 0.55.0 (lockfile root was stale at 0.50.0 → corrected) |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (top + plugins[0]) | Version pins |
| `.codex-plugin/plugin.json`, `plugins/hopper/.codex-plugin/plugin.json`, `plugins/hopper/kimi.plugin.json` | Version pins |
| `commands/smoke.md`, `commands/vendors.md` | Banner version strings |
| `README.md`, `README.en.md`, `README.ja.md` | Version badge 0.50.0 → 0.55.0 |
| `CHANGELOG.md` | 0.55.0 entry (content + boundary/union narrative + tests) |
| `docs/archive/ISSUES.md` | Close `queue-brief-dropped-…`; open/register residual family issues + index recount |
| `tests/unit/dispatch-task-content.test.js` | **untracked** — content merge / fail-closed / placeholder ban |
| `tests/unit/dispatch-task-spec-boundary.test.js` | **untracked** — root causes (a)(b), over-truncation, union defects |
| `tests/unit/readme-version-badge.test.js` | **untracked** — discovery guard for README version badges |
| `tests/unit/resolve-and-model-hints.test.js` | Non-empty Brief so fixtures exercise intended diagnostics under fail-closed |
| `tests/unit/resolve-vendor-override.test.js` | Non-empty Brief + tighter override-marker assertions |
| `cli/src/tasks.js` | **none** (unchanged; verified MD5 == HEAD) |

## Acceptance verification (5/5 questions)

### Q1 — Union implementation: both halves actually fire (live `loadTaskSpec`)

**Method:** imported `loadTaskSpec` from `./cli/src/dispatch.js`, wrote real `handoffs/leader-tasklist.md` under temp dirs, executed — not static review.

| Case | Input shape | otherTaskIds | Result | Pass |
|---|---|---|---|---|
| Q1a | Long T-1 body (120×`A`) then **unknown** `## T-91` with `SECRET_ADHOC_T91` | `['T-1','T-2']` (T-91 absent) | Own body kept; secret **not** leaked; `## T-91` not in section | **YES** |
| Q1a short | Short body `short` then `## T-91` / `SECRET_SHORT` | with and without ids | Spec is `## T-1\n\nshort` only; no leak either mode | **YES** |
| Q1b bold | Long T-1 then `**T-2** SECRET_T2_BOLD…` | `['T-1','T-2']` | Own body kept; secret not leaked | **YES** |
| Q1b table | Long T-1 then `\| T-2 \| … SECRET_T2_TABLE …` | `['T-1','T-2']` | Own body kept; secret not leaked | **YES** |
| CONTROL (proves id-half is load-bearing) | Same bold T-2 successor | **omitted** | `SECRET_T2_BOLD_NO_IDS` **leaks** into T-1 | Expected: id-half inactive |
| Earliest-wins | Bold T-2 before H2 T-3 | `['T-1','T-2','T-3']` | Cuts before bold secret; H2 secret also excluded | **YES** |

**Code anchors (inspected after run):**  
- H2 half: `cli/src/dispatch.js:355` `searchSpace.search(/^##\s+/m)`  
- Id half: `cli/src/dispatch.js:362-368` `markerAlternation(idsPattern)` over known other ids  
- Wiring: `resolveDispatch` always passes `otherTaskIds: tasks.map(t => t.id)` at `:125-131`

**Conclusion Q1:** Union is real, not either/or. H2 half terminates unknown adhoc headings under the real dispatch path; id half terminates bold/table successors. Control without `otherTaskIds` still leaks bold T-2 — proving the id half is what stops that form.

### Q2 — Over-truncation (H3/H4, line-start bold, body tables)

Live runs:

| Fixture | Must keep | Result |
|---|---|---|
| `### 背景` / `#### 细节` / `### 验收` with KEEPME_* markers | Full subsections with **and** without `otherTaskIds` | All KEEPME_* present; full text returned |
| Line-start `**Bold**` + unknown `**T-9**` + rest marker | All three | All present |
| Markdown table `\| foo \| bar \|` + post-table marker | Table + continuation | Both present |

**Unit tests:** `node --test tests/unit/dispatch-task-spec-boundary.test.js tests/unit/dispatch-task-content.test.js tests/unit/readme-version-badge.test.js` → **27/27 pass, 0 fail** (duration ~247ms). `mkdtemp` worked in this environment — **no EPERM**; nothing environment-failed to list as skipped.

**Conclusion Q2:** No over-truncation on the three required shapes. H2-only unconditional check (not `##+`) is what preserves subsections.

### Q3 — Fifth place in the “looks like content, does not carry a task” family?

**Known four (brief):**  
1. No leader-tasklist entry → self-describing placeholder as spec — **fixed** (null + brief merge / operator notice)  
2. Bare marker (`## T-1` with no body) treated as non-empty — **fixed** (`afterMarker.trim()` at `:380-381`)  
3. Cross-task boundary leak — **fixed** (union boundaries)  
4. `queue.js` unescaped-pipe brief truncation — **Open, unfixed** (`queue-brief-truncated-by-unescaped-pipe`)

**Live hunt for a fifth inside `dispatch.js` + call chain:**

| # | Shape | Location | Status |
|---|---|---|---|
| **5** | Body is only structural markup (`---`, `\|---\|---\|`, `>`) → still non-null “spec” | `loadTaskSpec` `:380-381` (non-whitespace only) | **Open, unfixed** — `task-spec-structural-only-body-accepted` |
| 6 (related) | `composePrompt` accepts empty/whitespace `taskSpec` without throw | `cli/src/tasks.js:160-170` | **Open, unfixed** — `composeprompt-no-fail-closed-on-empty-spec` (defense-in-depth; upstream `composeTaskContent` currently blocks the queue path) |

**Live evidence for #5:**

```
T-1 null? false  preview "## T-1\n\n---"
T-2 null? false  preview "## T-2\n\n|---|---|"
T-3 null? false  preview "## T-3\n\n>"
T-4 null? false  preview "## T-4\n\nReal content line."   // control
```

**Live evidence for #6:** `composePrompt('# Frame', '')` and whitespace-only → no throw; `## Task spec` section body is empty (`"\n\n\n"` after the heading).

**Conclusion Q3:** **Yes — there is a fifth** (structural-only body still accepted as a valid detailed spec). It is already registered Open for this release and is not fixed here. A sixth (composePrompt lack of fail-closed) sits one hop into the call chain and is also registered Open; `tasks.js` is intentionally untouched this release.

### Q4 — Release readiness

| Check | Evidence | Result |
|---|---|---|
| Version everywhere 0.55.0 | `package.json`, lockfile root + `packages[""]`, both marketplace version fields, plugin.json ×2, codex plugin.json ×2, kimi.plugin.json, `const VERSION` in both bins, smoke/vendors banners, README badges | **PASS** |
| Vendored copies sync | `diff -q cli/src/dispatch.js plugins/hopper/cli/src/dispatch.js` → identical; bins identical | **PASS** |
| `cli/src/tasks.js` 一字未改 | `git diff` empty; MD5 `aefed731e48ee1edb4833df69a79f938` == `git show HEAD:cli/src/tasks.js` | **PASS** |
| CHANGELOG `dispatch.js` line refs vs current file | See table below | **PASS** |
| ISSUES Open/Closed counts vs entries | Index claims Open **10** (10 rows), Closed **12** (12 rows), NMR **2** (2 rows); 24 indexed ↔ body anchors present | **PASS** |

**CHANGELOG 0.55.0 line-ref audit (current `cli/src/dispatch.js`, 936 lines):**

| Cited | Actual content | Match |
|---|---|---|
| `:180` | `const taskSpec = brief;` | yes |
| `:166-167` | adhoc empty-brief throw | yes |
| `:212-213` (swarm) | swarm empty-brief throw | yes |
| `:332-381` | marker match through afterMarker fail-closed return | yes (range covers strip+body check) |
| `:436` | `const tasklistExists = await fileExists(path);` | yes (call site as described) |
| `:321-382` | entire `loadTaskSpec` | yes |
| `:125-131` | `composeTaskContent({… otherTaskIds …})` | yes |

**Note (not a count failure):** Closed-index row `prompt-artifact-lifecycle-and-windows-permissions` still has status text “open — recorded, not fixed” in the table — pre-existing catalog semantics debt; claimed Closed **count** still equals table row count.

### Q5 — Anything that should **not** ship with this release?

Reviewed full `git status` / diffs:

- All product/doc/test changes are in-scope for the content-merge + boundary-union + version bump story.  
- README badge drift fix (0.50.0→0.55.0) and lockfile root version (0.50.0→0.55.0) are **corrective**, not scope creep.  
- Fixture Brief cells + override-marker assertion hardening are necessary so fail-closed does not break unrelated tests.  
- Untracked tests **must** be committed with the release (otherwise CHANGELOG claims 12+14 cases without shipping them).  
- No secrets, no unrelated feature work, no `tasks.js` mutation, no sandbox/permission policy loosening.

**Conclusion Q5:** No “should not ship” product changes. Ensure the three `??` test files are included in the release commit.

### Tests run (not exit-0 worship)

```
node --test \
  tests/unit/dispatch-task-spec-boundary.test.js \
  tests/unit/dispatch-task-content.test.js \
  tests/unit/readme-version-badge.test.js
→ tests 27, pass 27, fail 0
```

Plus independent live fixtures for Q1/Q2/Q3 (outputs above). Full `npm test` suite was **not** waited to completion here (backgrounded; may hang on known open issue `progress-watch-hang`); targeted suite + live extraction are the evidence base.

**Environment failures:** none (mkdtemp succeeded throughout).

## Decisions / deviations

- Did not treat “Closed” table semantic inconsistency on `prompt-artifact-…` as a Q4 fail: the brief requires **count == entries**, which holds.  
- Counted structural-only body as the **fifth** family member; composePrompt empty-spec as related call-chain depth, not a second fifth.

## Open questions

none (residuals already filed: structural-only body; composePrompt fail-closed depth; queue pipe truncation).

## Verdict

**PASS_WITH_NOTE**

Union boundary fix is live-verified; over-truncation guards hold; release metadata and vendored sync are clean; `tasks.js` untouched; CHANGELOG line anchors accurate; ISSUES index counts match. Notes: (1) fifth same-family defect (structural-only body) remains Open by registration — not a regression of this fix; (2) commit the three untracked test files with the release; (3) known full-suite hang issue is pre-existing and not introduced here.

## Next recommendation

1. Commit entire working tree **including** the three untracked unit tests; tag/publish **0.55.0**.  
2. Do **not** block 0.55.0 on structural-only / composePrompt depth / pipe truncation — they are registered Open with severity low/medium and out of this release’s stated scope.  
3. Next evolution slice: tighten `loadTaskSpec` body predicate beyond “non-whitespace” (structural-only), then optionally fail-closed inside `composePrompt` without changing happy-path bytes.  
4. Optional: reclassify or move `prompt-artifact-lifecycle-and-windows-permissions` out of Closed if its status text is still “open”.

## Vendor output (parsed)

```
I'll run the acceptance review on hopper-plugin's uncommitted work: extract and exercise `loadTaskSpec`, then check release readiness against the five questions.Next I'll extract `loadTaskSpec` and run the Q1/Q2 fixtures, then check release readiness.Running live `loadTaskSpec` fixtures for Q1/Q2, then release-readiness checks for Q3–Q5.Writing the acceptance review deliverable. Unit tests: 27/27 passed; live `loadTaskSpec` runs confirm both halves of the union.## Deliverable

Acceptance review written to `.hopper/handoffs/T-103-grok-output.md`.

### Verdict: **PASS_WITH_NOTE**

| Q | Result |
|---|---|
| **Q1** Union both halves | Live `loadTaskSpec`: unknown `## T-91` cuts under `otherTaskIds`; known bold/table T-2 cuts; without `otherTaskIds`, bold T-2 still leaks (control) |
| **Q2** Over-truncation | H3/H4, line-start bold, body tables all kept; 27/27 unit tests green |
| **Q3** Fifth failure shape | **Yes** — structural-only body (`---`, `\|---\|`, `>`) still accepted; already Open as `task-spec-structural-only-body-accepted` |
| **Q4** Release ready | 0.55.0 everywhere; vendored `dispatch.js`/bin identical; `tasks.js` unchanged; CHANGELOG line refs match; ISSUES Open 10 / Closed 12 / NMR 2 match row counts |
| **Q5** Should-not-ship | None; include the 3 untracked test files in the release commit |

**Notes:** Residual Open issues (structural-only, composePrompt empty-spec, pipe truncation) are registered, not regressions. No mkdtemp EPERM here — all live fixtures ran.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 442596
- end_time: 2026-08-12T09:36:30.653Z
- log: see `T-103-grok-output.log` for raw output
