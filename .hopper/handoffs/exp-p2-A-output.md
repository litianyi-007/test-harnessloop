---
task_id: exp-p2-A
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
pid: 39777
start_time: "2026-07-29T11:46:26.343Z"
end_time: "2026-07-29T11:51:39.683Z"
exit_code: 0
duration_ms: 313292
mode: background
phase: done
last_progress_at: "2026-07-29T11:51:39.684Z"
last_progress: Task completed successfully.
progress_seq: 12
progress_log: ./exp-p2-A-progress.log
raw_log: ./exp-p2-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p2-A-output.log
started_by_pid: 39775
last_stream_event: process_alive
last_update: "2026-07-29T11:51:26.392Z"
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

# exp-p2-A — grok (background, done)

Output streaming to `exp-p2-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/8818 chars; complete parsed output is available through `hopper-dispatch --result exp-p2-A --full`)_

````
I'll review harnessloop commit `3a68216` adversarially: inspect the diff and surrounding context, then write a review-only `output.md`.Digging into edge cases: parsing, `REVIEW_NONE_RE`, ledger presence, version consistency, and whether G26 tests actually hold.Independently re-ran the eight-row judgment table and G26a–h; drafting the adversarial review deliverable.# Adversarial review · harnessloop `3a68216` (v0.28.0)

## Summary

Independently reviewed commit `3a682165f377865996fbe873e9c16f9a29c02df6` (v0.28.0 second RAE vertical slice: optional `- Acceptance evals:` self-consistency against same-round ledger presence). The eight-row judgment table is implemented correctly, stays same-round (no `activation_round` join), fail-closes on unparsable values, and G26a–h bidirectional teeth all pass under independent re-execution (0 failures). Residual issues are packaging version drift, a misleading remediation string, and an incomplete “absent” definition when `decision.md` itself is missing—not a fail-open of the declared eight-row table. Verdict: **PASS_WITH_NOTE**.

## Files touched

none (review only; no edits to harnessloop or other trees)

## Acceptance verification (8/8 table rows + packaging/hygiene)

Assumption (1 line): “acceptance criteria” for this minimal brief = the commit’s own eight-row table + claim that declarations must be self-consistent once written; residual OUT gap is acknowledged, not treated as a defect.

### Eight-row judgment table — **PASS** (independently reproduced)

Loaded `verify_protocol.py` at `3a68216` into a temp import path and drove `verify_project` on minimal round fixtures:

| row | field | ledger | expected | observed kinds | cov |
|-----|-------|--------|----------|----------------|-----|
| 1 | absent | absent | green | `[]` | `_absent=1` |
| 2 | absent | present | `…-declaration-missing` | `['acceptance-eval-declaration-missing']` | `_absent=1` |
| 3 | `ran` | present | green | `[]` | `_ran=1` |
| 4 | `ran` | absent | `…-declared-ran-without-ledger` | match | `_ran=1` |
| 5 | `none — <reason>` | absent | green | `[]` | `_none=1` |
| 6 | `none — <reason>` | present | `…-declaration-contradicts-ledger` | match | `_none=1` |
| 7 | `none —` empty | either | `…-none-reason-empty` | match (absent ledger) | `_none=1` |
| 8 | unparsable (`ran。`) | either | `…-declaration-unparsable` only | `{'acceptance-eval-declaration-unparsable'}` | no counter |

Also confirmed: bare `none`, `none—`, whitespace-only reason → empty-reason; `RAN` padding / CRLF / BOM file → green with ledger; case-folded label `- Acceptance Evals: None — because` → green.

### G26a–h teeth — **PASS**

Extracted G26 block from `scripts/validate.py` at `3a68216`, dedented, executed against the same commit’s `verify_protocol`. **Result: failures=0** (all primary claims + reverse mutations, including G26e “add only ledger → red” and G26h set-equality on unparsable).

### Same-round / no cross-layer join — **PASS**

`check_acceptance_eval_declaration(round_dir, decision_text, ledger_present)` takes `ledger_state["present"]` already computed in `verify_round`; no read of `<goal>/evals.json` / `activation_round` in this path (confirmed by code inspection of the new function and its sole call site).

### SKILL IN / template / coverage wiring — **PASS**

- New coverage keys present in `_empty_coverage`, `main()` coverage line (`eval_declaration_ran|none|absent`), and SKILL.md IN bullet.
- OUT column rewritten as “Narrowed, not closed” with honest residual (neither field nor ledger).
- `decision-template.md` adds the optional field with migration-silent note.

### Packaging version consistency — **FAIL (NOTE-1)**

At `3a68216`:

```text
package.json                                              0.28.0
.claude-plugin/marketplace.json                           0.28.0
plugins/harnessloop/.claude-plugin/plugin.json            0.28.0
plugins/harnessloop/.codex-plugin/plugin.json             0.11.0
```

This commit is explicitly a **v0.28.0** release bump but leaves the Codex plugin manifest 17+ minors behind. Codex install path advertises the wrong version. (Later repo history adds G28 discovery guard; that does not clear the defect at this commit.)

### Error-message remediation honesty — **FAIL (NOTE-2)**

`acceptance-eval-declaration-missing` detail (source at commit):

> … must declare `Acceptance evals: ran` **(or `none — <reason>` if the ledger is unrelated to this round's own claim)**

Following that advice with a present ledger:

```text
F2_FOLLOW_ADVICE_KINDS: ['acceptance-eval-declaration-contradicts-ledger']
```

The parenthetical is dead-end guidance: with a ledger present, only `ran` (or deleting the ledger) is consistent. `none` is never a valid fix for row 2.

### “Absent” when `decision.md` is missing — **NOTE-3**

Fixture: ledger present, **no** `decision.md`:

```text
F3_NO_DECISION_ACCEPT_KINDS: []
F3_LEDGER_PRESENT_COV: 1  ABSENT_COV: 0
```

Row 2 of the table is implemented as “field line absent **inside an existing decision.md**,” not “declaration absent as a round fact.” A ledger-only round bypasses `declaration-missing` and is not counted in `_absent`. Same structural pattern as B2a/Feedback (gates gated on `decision.exists()`), but it is an incomplete reading of “absent + present = red” and is not documented in the OUT residual (which only mentions neither-field-nor-ledger).

### Coverage teeth — **NOTE-4**

G26 asserts violation kinds only; no check asserts `rounds_eval_declaration_{ran,none,absent}` increments. A coverage-print regression could ship while kinds stay correct. Independent fixtures above show counters work today; teeth do not lock them.

### Commit-message absolute teeth count — **NOTE-5**

Message claims `validate.py 412 → 430`. Raw `check(` count at parent/commit: **346 → 364** (Δ +18, matching G26’s 18 `check()` calls). Delta is real; absolute numbers are wrong.

## Findings (author-miss class)

| ID | Sev | Title | Repro / evidence |
|----|-----|-------|------------------|
| **NOTE-1** | Medium | Release bumps 3/4 semver manifests; Codex plugin left at 0.11.0 | `git show 3a68216:plugins/harnessloop/.codex-plugin/plugin.json` → `"version": "0.11.0"` vs others `0.28.0` |
| **NOTE-2** | Low–Med | `declaration-missing` detail recommends `none` while ledger exists → immediately contradicts-ledger | follow advice → `acceptance-eval-declaration-contradicts-ledger` |
| **NOTE-3** | Low | No `decision.md` + ledger present → zero acceptance-eval-* kinds; not in OUT residual | fixture above |
| **NOTE-4** | Low | G26 does not lock coverage counters | code: G26 only filters violation kinds |
| **NOTE-5** | Nit | Absolute teeth count in commit message wrong | 346→364 not 412→430 |

**Not counted as defects (intentional / correct):**
- Migration-silent absent+absent (documented OUT upper bound; G26e reverse mutation proves check is live).
- Empty-reason prioritized over contradicts-ledger when both could apply (single, more specific kind).
- Reuse of `REVIEW_NONE_RE` (optional dash; `none reason` without dash still parses)—consistent with B2a Review.
- Strict `- acceptance evals:` prefix (requires space after `-`)—same convention as Feedback/Review.

## Decisions / deviations

- Did not treat the documented residual (“must declare” not enforceable by this mechanical gate) as a finding; OUT text matches implementation.
- Did not treat pre-existing `decision.md`-as-directory `IsADirectoryError` crash as introduced by this commit (shared `decision.exists()` → `read_text` path predates the slice).
- Did not require G28 (added later in history) to exist at this commit; only scored the drift present here.

## Open questions

- none (for merge of the vertical-slice logic). Packaging drift and error-string fix are clear.

## Verdict

**PASS_WITH_NOTE**

Primary feature is sound: once you declare, self-consistency against same-round ledger presence is mechanically enforced with real bidirectional teeth. Notes are packaging hygiene, operator-fac

... [truncated, 818 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 313292
- end_time: 2026-07-29T11:51:39.683Z
- log: see `exp-p2-A-output.log` for raw output
