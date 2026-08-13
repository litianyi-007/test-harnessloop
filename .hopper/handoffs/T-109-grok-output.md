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
end_time: "2026-08-12T20:26:28.880Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 266183
adapter_status: success
last_progress_at: "2026-08-12T20:26:28.881Z"
last_progress: Task completed successfully.
progress_seq: 10
terminal_event_emitted: true
---
# T-109-grok — code-review-acceptance (hopper 0.57.0 post-release confirmation)

**Reviewer:** grok (execution agent; one-shot background dispatch)  
**Target repo:** `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/hopper-plugin`  
**Review object:** committed `11d64bc` (`v0.57.0：正文只有一条分隔线的小节，也被当成了一份任务书`)  
**HEAD at review:** `11d64bc2efacace46ff31cbc351194e4ba98bead` (clean; commit is current HEAD)  
**Mode:** read-only on product code; no product edits. Live execution of `loadTaskSpec` via temp fixtures under `os.tmpdir()`.  
**Date:** 2026-08-13  

**Assumption (1 line):** “两处既有文案” means the `composeTaskContent` `specNotice` / throw branches for `NO_SECTION` and `NO_TASKLIST_FILE` (the two pre-REWORK reasons), verified via `resolveDispatch`.

---

## Summary

Commit `11d64bc` (hopper **0.57.0**) reworks the structural-only-body fail-closed path after T-108 REWORK: code fences and 4-space/tab indented lines are treated as opaque content, and `loadTaskSpec` reports three distinct null reasons through optional `diagnostics.reason` / `SPEC_MISS_REASON`. Live execution of `loadTaskSpec` (not code reading alone) accepted **all six required code-block legal specs** with content intact, rejected all six named under-rejection shapes (plus variants) without collateral damage to lookalike legal inputs, and produced three distinguishable miss reasons with truthful compose notices. CHANGELOG’s five residual “still accepted” classes are confirmed real; additional unlisted same-class residuals were also found, which matches (and strengthens) the stated “known, not exhaustive” claim rather than contradicting it.

## Files touched

none (acceptance review only; product tree not modified)

**Files examined (read / executed against):**

| Path | Rationale |
|---|---|
| `cli/src/dispatch.js` | `isStructuralOnlyLine` (:372), `hasSubstantiveContent` (:433), `SPEC_MISS_REASON` (:459), `loadTaskSpec` (:574), `composeTaskContent` notices (:701–745) |
| `plugins/hopper/cli/src/dispatch.js` | Vendored mirror; `diff -q` identical to root |
| `tests/unit/dispatch-task-spec-structural-only.test.js` | 57 unit/e2e cases covering P1/P2/P3 |
| `CHANGELOG.md` §`[0.57.0]` | Claims under acceptance |
| `package.json` | Version `0.57.0` |

## Acceptance verification (4/4)

**Method:** `import { loadTaskSpec, SPEC_MISS_REASON, resolveDispatch } from './cli/src/dispatch.js'`, write real `.hopper/handoffs/leader-tasklist.md` under `mkdtempSync(tmpdir())`, execute. Official suite also run: `node --test tests/unit/dispatch-task-spec-structural-only.test.js` → **57/57 pass**. No mkdtemp EPERM in this environment — all live fixtures completed; zero environment-skipped items.

### Q1 — Over-rejection fixed? (code-block legal specs)

**Required six + extras. All ACCEPTED with content intact.**

| # | Shape | Body sketch | Result | Content intact |
|---|---|---|---|---|
| 1 | fence + diff | ` ```diff` / `--- a/old` / `+++ b/new` / … | non-null | `--- a/old` present |
| 2 | fence + md table | ` ```markdown` / `\| a \| b \|` / `\|---\|---\|` / `\| \| \|` | non-null | table lines present |
| 3 | fence + shell | ` ```bash` / `npm test` / `echo "---"` | non-null | `npm test` present |
| 4 | indented HR | `    ---` (4 spaces) | non-null | `    ---` keeps indent |
| 5 | indented blockquote | `\t> ` (tab) | non-null | `\t>` present |
| 6 | nested fence | ` ```md` … ` ```js` … `console.log(1)` … | non-null | `console.log(1)` present |
| + | indented empty table | `    \| \| \|` | non-null | indent + cells present |
| + | tilde fence + HR | `~~~\n---\n~~~` | non-null | full fence body present |
| + | fence with blank interior line | ` ```\n \n``` ` | non-null | accepted (any interior line counts) |

**Evidence (live JSON samples):**
- indent HR: `"## T-1\n\n    ---"`
- indent table: `"## T-1\n\n    | | |"`
- tilde: `"## T-1\n\n~~~\n---\n~~~"`
- success path: `diagnostics.reason` left `undefined` on all accepts

**T-108 red-line reproductions (also in official tests 26–28):** indented `---`, tab `>`, indented `| | |` — all non-null. Official P1 suite 26–34 green.

**Mis-reject found:** none.

**Q1 verdict: PASS** — over-rejection is fixed; principle (fence open/close structural; interior + indented code unconditional content) holds under independent construction, not only the packaged fixtures.

### Q2 — Under-rejection supplement effective and no collateral?

**Six named illegal shapes — all rejected with `STRUCTURAL_ONLY_BODY`:**

| Shape | Input | `loadTaskSpec` | `diagnostics.reason` |
|---|---|---|---|
| empty fence | ` ```\n``` ` | `null` | `structural-only-body` |
| borderless table sep | `--- \| ---` | `null` | `structural-only-body` |
| empty checkbox | `- [ ]` | `null` | `structural-only-body` |
| HTML HR | `<hr>`, `<hr/>`, `<HR>` | `null` | `structural-only-body` |
| zero-width only | U+200B, U+200C | `null` | `structural-only-body` |
| bare pipe | `\|`, `\|\|` | `null` | `structural-only-body` |

Also confirmed: `- [x]`, `-|-|-`, empty fence corollary.

**Lookalike legal controls — all ACCEPTED (no collateral):**

| Control | Input | Result |
|---|---|---|
| checkbox with text | `- [ ] real task item` | accept |
| checked with text | `- [x] done item text` | accept |
| `<hr>` + prose | `<hr>\n\nDo the real work.` | accept |
| ZWSP mixed with text | `\u200B real content…` | accept |
| table cell with text | `\| \| REAL_CELL \|` | accept |
| borderless sep + prose | `--- \| ---\nActual requirement…` | accept |
| non-empty fence | ` ```\ncode\n``` ` | accept |

Official P3 suite 35–49 green (11 reject + 4 over-rejection controls).

**Q2 verdict: PASS** for the six named shapes and their stated lookalikes.

### Q3 — Diagnostics tell the truth?

| Path | Setup | `spec` | `diagnostics.reason` | Expected constant |
|---|---|---|---|---|
| no file | no `leader-tasklist.md` | `null` | `no-tasklist-file` | `SPEC_MISS_REASON.NO_TASKLIST_FILE` |
| no section | file has `## T-OTHER` only | `null` | `no-section` | `NO_SECTION` |
| structural only | `## T-1\n\n---` | `null` | `structural-only-body` | `STRUCTURAL_ONLY_BODY` |
| success | `## T-1\n\nReal sentence.` | non-null | **unset** (`undefined`; pre-existing keys preserved) | — |
| omit `diagnostics` | structural body, no out-param | `null` | n/a | return contract unchanged |

**Compose-path wording (via `resolveDispatch`, the only production consumer):**

| Reason | Observed `specNotice` / throw | Truthful? |
|---|---|---|
| `NO_TASKLIST_FILE` + brief | `leader-tasklist.md is absent at <path>; task content comes from queue.md Brief.` | yes |
| `NO_SECTION` + brief | **exact:** `No detailed spec section for T-1 in leader-tasklist.md; task content comes from queue.md Brief.` | yes; byte-stable vs pre-REWORK |
| `STRUCTURAL_ONLY_BODY` + brief | `leader-tasklist.md HAS a section for T-1, but its body is only structural markdown (no real content — see docs/archive/ISSUES.md#task-spec-structural-only-body-accepted); task content comes from queue.md Brief.` | yes; does **not** say “No detailed spec section” |
| `STRUCTURAL_ONLY_BODY` + empty brief | throw contains `a section for T-1 exists in …` + `structural markdown`; does **not** match `/no section for T-1 in/` | yes |

Code: `composeTaskContent` branches at `cli/src/dispatch.js:721–745`. Official P2 suite 50–57 green.

**Q3 verdict: PASS** — three null causes are distinguishable; success path does not set a reason; the two pre-existing notice texts for missing file / missing section are preserved; structural-only no longer lies as “no section”.

### Q4 — Residual declaration honest?

CHANGELOG lists five residual classes that still pass, with “已知，不穷尽”:

| Claimed residual | Live result | Honest? |
|---|---|---|
| bare subheading only (`### 背景`) | **ACCEPTED** | yes |
| lonely bold markers (`**`) | **ACCEPTED** | yes |
| HTML comment only (`<!-- note -->`) | **ACCEPTED** | yes |
| setext underline only (`===` / `========`) | **ACCEPTED** | yes |
| other invisible Unicode beyond U+200B/C/D/FEFF (U+00AD soft hyphen, U+2060 word joiner) | **ACCEPTED** | yes |

Whitespace-class controls that correctly **reject** (not residuals): U+00A0 nbsp-only, U+2003 em-space, fullwidth spaces, lone U+FEFF — all `structural-only-body` via trim-empty or `INVISIBLE_ONLY_RE`.

**Unlisted same-class residuals found by this review** (still ACCEPTED; supports “不穷尽”, does not break the claim):

| Unlisted shape | Notes |
|---|---|
| `<hr class="x">`, `<hr id="a">`, `<hr data-x="1" />` | `HTML_HR_RE` (`:346`) only matches bare `<hr>` / `<hr/>` — **attribute form slips through** |
| empty HTML tags: `<br>`, `<div></div>`, `<p></p>`, `<h1></h1>` | not in structural list |
| empty markdown links/images: `[]()`, `![]()` | accepted |
| lonely `__` / `~~` | same family as claimed `**` |
| ordered empty checkbox `1. [ ]` | `BARE_CHECKBOX_RE` only allows `[-*+]` bullets; `+ [ ]` / `* [ ]` reject, but `1. [ ]` accepts |
| malformed checkbox `- []` / `- [  ]` | space/shape miss → accept |
| reference defs / footnotes / TOC / wiki-link empties / `$$` | accepted |
| mixed thematic `-* -` | by design (HR requires same repeated char) |
| emoji-only `✅`, bare `:`, `\`, `&nbsp;` entity text | accepted |

None of these re-open the T-108 over-rejection red line; they are under-rejection residuals, and CHANGELOG already disclaims exhaustiveness.

**Q4 verdict: PASS** — the five listed classes are true; unlisted peers exist and are consistent with “不穷尽”.

### Environment / suite notes

| Check | Result |
|---|---|
| `node --test tests/unit/dispatch-task-spec-structural-only.test.js` | **57 pass / 0 fail** |
| `node scripts/sync-vendored-plugin.mjs --check` | exit 0, in sync |
| `package.json` version | `0.57.0` |
| mkdtemp EPERM | **none** — no tests skipped for environment |
| Items not run due to sandbox | **none** |

## Decisions / deviations

- Nested-fence acceptance was verified as “section returns non-null with interior text present.” The fence state machine is not a full nested CommonMark parser (first non-close interior line short-circuits to content); that is sufficient for the fail-closed content predicate and matches the stated principle.
- Two early harness self-check “fails” on indent-table / tilde-fence were false positives from `!includes(...) === false` operator precedence in the reviewer’s probe script; re-run with correct predicates showed both accepted with full content. Not a product defect.
- Unlisted residuals (esp. `<hr attrs>`, `1. [ ]`) recorded as notes under Q4, not as REWORK of the stated rework goals.

## Open questions

none that block acceptance of this rework.

Optional follow-ups (out of scope for this confirmation):
1. Extend `HTML_HR_RE` to allow attributes, or document `<hr …>` as residual.
2. Decide whether ordered-list empty checkboxes (`1. [ ]`) should join `BARE_CHECKBOX_RE`.

## Verdict

**PASS_WITH_NOTE**

All four acceptance questions pass under live `loadTaskSpec` execution against `11d64bc`. The T-108 over-rejection red line is repaired; the six under-rejection supplements hold without collateral; diagnostics distinguish three null causes and no longer lie about “missing section” when the section exists but is structural-only; residual claims are honest and explicitly non-exhaustive. Notes only: additional unlisted under-rejection peers (notably attributed `<hr …>` and `1. [ ]`) exist beyond the CHANGELOG list — expected under “不穷尽”, not a regression of the rework.

## Next recommendation

1. Treat 0.57.0 structural-only + diagnostics rework as **accepted** for release confirmation.  
2. Optionally file a low-severity residual issue for attributed HTML HR / ordered empty checkboxes if under-rejection hygiene is desired later — do **not** block on them (red line remains over-rejection).  
3. No further REWORK required on the P1/P2/P3 items that T-108 raised.

## Vendor output (parsed)

```
I'll run a read-only acceptance review of hopper 0.57.0 at `11d64bc`, focusing on `loadTaskSpec` over-rejection, under-rejection, diagnostics truthfulness, and residual claims—then write the verdict to the handoff file.Next I'll read `loadTaskSpec` / `hasSubstantiveContent` and the structural-only tests so I can run the six acceptance probes directly.I'll execute `loadTaskSpec` live against constructed fixtures for Q1–Q4, and inspect the diagnostic message paths.Q1’s two “fails” look like harness bugs (operator precedence); rechecking those cases plus compose notice wording and the official unit suite.All four questions verified by live `loadTaskSpec` execution. Writing the acceptance deliverable.## T-109-grok done

**Verdict: PASS_WITH_NOTE**  
Deliverable: `.hopper/handoffs/T-109-grok-output.md`  
Target: hopper-plugin `11d64bc` (0.57.0)

### Four questions (live `loadTaskSpec`, not code-only)

| Q | Result |
|---|---|
| **Q1** over-rejection | **PASS** — all 6 required code-block specs accepted with content intact (diff / md table / shell / indented `---` / tab `>` / nested fence); no mis-reject |
| **Q2** under-rejection | **PASS** — empty fence, `--- \| ---`, `- [ ]`, `<hr>`, ZWSP, bare `\|` all → `null` + `structural-only-body`; lookalikes with real text still accepted |
| **Q3** diagnostics | **PASS** — three reasons distinct; success path leaves `reason` unset; structural notice says section **exists**; `NO_SECTION` wording byte-stable |
| **Q4** residuals | **PASS** — five CHANGELOG residual classes confirmed; unlisted peers found (`<hr class="x">`, `1. [ ]`, empty HTML tags, …) consistent with “不穷尽” |

### Suite / env
- Official suite: **57/57** green  
- Vendored sync: exit 0  
- **No mkdtemp EPERM** — nothing skipped for environment  

### Note (not blocking)
Attributed HTML HR (`<hr class="x">`) and ordered empty checkbox (`1. [ ]`) still slip through — under-rejection residuals, not a reopening of the T-108 over-rejection red line.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 266183
- end_time: 2026-08-12T20:26:28.880Z
- log: see `T-109-grok-output.log` for raw output
