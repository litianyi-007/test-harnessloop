---
task_id: exp-p12-A
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
pid: 95239
start_time: "2026-07-29T14:20:47.160Z"
end_time: "2026-07-29T14:27:44.879Z"
exit_code: 0
duration_ms: 417672
mode: background
phase: done
last_progress_at: "2026-07-29T14:27:44.880Z"
last_progress: Task completed successfully.
progress_seq: 15
progress_log: ./exp-p12-A-progress.log
raw_log: ./exp-p12-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p12-A-output.log
started_by_pid: 95238
last_stream_event: process_alive
last_update: "2026-07-29T14:27:17.238Z"
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

# exp-p12-A — grok (background, done)

Output streaming to `exp-p12-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/9322 chars; complete parsed output is available through `hopper-dispatch --result exp-p12-A --full`)_

````
I'll review only harnessloop commit `7fd5a3c` adversarially: inspect the diff and hunt for defects the author would miss, with no edits.Pulling the full implementation diffs next so I can review the validation logic in detail.G25 fixtures may lack the new required `evidence` key — checking whether that breaks existing tests.Running the validate suite at that commit to confirm whether G25 fixtures without `evidence` actually fail.HEAD is two commits ahead; I'll re-run validation against exactly `7fd5a3c`.## Summary

Reviewed **only** harnessloop commit `7fd5a3c5ac128166cd5c462bd748d81c3cc38bf1` (`v0.35.0`: eval ledger must reference an evidence artifact). Method: detached worktree at that commit, full `git show`, line-level read of `check_round_eval_ledger` vs `check_review_declaration`/`_is_contained`, edge probes (dir / `../` / missing prefix / hardlink / fabricated content), and full `python3 scripts/validate.py` on the commit tree (**exit 0**, G38a–j all green). No production logic escape found that breaks the stated upper bound; residual notes are fixture hygiene, authoring footguns, and test isolation brittleness—not red-gate bugs.

**Assumption (one line):** Task brief had no separate acceptance checklist; criteria below are derived from the commit’s own claims (evidence field always required; pass forbids null; path under this round’s `evidence/`; ordinary non-symlink file; honest OUT bounds; G38 bidirectional teeth).

## Files touched

none (read-only review)

Reviewed paths (commit surface only):

| Path | Role in commit |
|------|----------------|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `check_round_eval_ledger` evidence gate + coverage/main counters |
| `scripts/validate.py` | G38a–j mutation teeth |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | Coverage metrics + OUT-column honesty |
| `package.json`, `.claude-plugin/marketplace.json`, `plugins/harnessloop/.claude-plugin/plugin.json`, `plugins/harnessloop/.codex-plugin/plugin.json` | Version `0.34.0` → `0.35.0` |

## Acceptance verification (7/7)

| # | Criterion | Evidence | Result |
|---|-----------|----------|--------|
| 1 | Scope is exactly `7fd5a3c` | `git show 7fd5a3c --stat` → 7 files, +632/−8; review limited to that tree via worktree | OK |
| 2 | `evidence` key always required; null OK except `outcome=="pass"` | Code: missing → `eval-ledger-evidence-missing`; null+pass → `eval-ledger-evidence-required-for-pass`; G38b/c green on exact kinds | OK |
| 3 | Non-null path must be ordinary file under **this round’s** `evidence/` | `_is_contained(candidate, round_dir/"evidence")` then `lexists` then `is_symlink or not is_file`; G38d/e/f/g/h | OK |
| 4 | Symlink leaf rejected even when target inside round | G38g: `eval-ledger-evidence-not-a-file` + mutation control proves containment holds | OK |
| 5 | Symlink escape → outside-round (not silent pass) | G38h: `eval-ledger-evidence-outside-round` | OK |
| 6 | Registered upper bound: fabricated content still green | G38j: `not violations` with invented log text | OK |
| 7 | Full teeth suite at this commit | `python3 scripts/validate.py` in worktree at `7fd5a3c` → exit 0, “Plugin framework validation passed.” Runtime `ok:` 579→603 (+24); `check(` 515→537 | OK (absolute 577/601 claim is ±2 platform-dependent; delta matches) |

## Findings (adversarial)

### F1 — PASS: Core gate matches the stated contract and reuses proven primitives

Implementation order is the same family as B2a `Review:`:

1. key presence  
2. null vs pass  
3. type/non-empty string  
4. `_is_contained` (canonical both sides) against **`round_dir/evidence`**, not project root  
5. `os.path.lexists`  
6. leaf `is_symlink` **or** not `is_file` → one combined kind  

Confining resolution to the round’s own `evidence/` is the right TH-0027 class-⑥ choice: existence re-reads disk, so project-wide paths would be a heavier retroactive-red class. Docstrings and SKILL OUT explicitly refuse “this proves the eval ran,” and G38j makes that executable. Version manifests all four move to `0.35.0`.

### F2 — NOTE: Pre-existing G25/G26/G27 ledger fixtures were not migrated

This commit makes `evidence` **always required**, but earlier RAE teeth still write:

```json
{"eval_id":"RAE-0001","attempt_id":"0001-a1","outcome":"pass","frozen_due_set":["RAE-0001"]}
```

with **no** `evidence` key. Membership assertions (`"X" in kinds` / `not in kinds`) still pass, so the suite stays green—but pollution is real. At `7fd5a3c`, G27a reports:

```text
got ['acceptance-eval-declaration-missing', 'acceptance-eval-positive-without-pass', 'eval-ledger-evidence-missing']
```

So “green mutation control” for older letters no longer means “ledger is fully clean.” Production claim “zero migration, no ledgers in the wild” can still be true; **in-repo teeth** are the ones left inconsistent. Not a gate logic bug; it weakens isolation and will bite any future exact-set assertion.

### F3 — NOTE: G38 “zero violations / only this kind” isolation depends on no `decision.md`

`_rae_project` does not write `decision.md`. At `7fd5a3c`, ledger + no decision ⇒ no B2a / acceptance-eval-declaration violations, so G38a `not violations` and G38b `kinds == {"eval-ledger-evidence-missing"}` hold.

That is valid isolation **at this commit**, but it means G38a does **not** prove “a realistic round with Feedback/Review/Acceptance-evals fields goes green solely by adding a legal evidence path.” Any later gate of the form “ledger present ⇒ decision must exist” breaks G38 unless fixtures gain a compliant `decision.md` (this later happened on main at v0.37—latent brittleness confirmed by history, not by editing this commit).

### F4 — NOTE: Path is round-relative, not evidence-root-relative (authoring footgun)

Resolution is `candidate = round_dir / evidence`. Empirically at this logic:

| Written `evidence` | File on disk | Result |
|--------------------|--------------|--------|
| `evidence/x.log` | `…/evidence/x.log` | green |
| `./evidence/x.log` | same | green |
| `runtime/x.log` | `…/evidence/runtime/x.log` | **`eval-ledger-evidence-outside-round`** |
| `evidence` / `evidence/.` / `evidence/runtime` | directory | `eval-ledger-evidence-not-a-file` |

Agents who treat the field as “path under evidence/” (drop the `evidence/` prefix) get a red that looks like an escape, not a path-base mistake. Schema example in the docstring is correct; there is still **no** `acceptance-evals.json` template under `references/` teaching the field.

### F5 — NOTE: `outcome: "pass"` still satisfies the hard rule even when evidence path is bad

With `Feedback: positive`, due id present, `outcome: "pass"`, and `evidence: "evidence/nope.log"`:

- `acceptance-eval-positive-without-pass` does **not** fire (pass entry exists)
- `eval-ledger-evidence-not-found` **does** fire → overall mechanical red

So there is no false-green for the gate as a whole. The orthogonality is intentional and fine; worth knowing when reading coverage/`got` lists: “pass without positive-without-pass” ≠ “evidence OK.”

### F6 — PASS side (what was hunted and did not break)

- Hardlink to a real file inside `evidence/` → green (same upper bound as fabricated bytes; leaf is ordinary file).  
- Escape via `../` and via symlink target outside both caught.  
- Invalid types (`""`, `42`) → `eval-ledger-evidence-invalid-type`; counters neither with_evidence nor evidence_null.  
- Coverage keys present in `_empty_coverage`, per-round assign, project `+=` accumulate, `main()` print.  
- No version split across the four manifests in this commit.

## Decisions / deviations

- Used a detached worktree at `7fd5a3c` because repo `HEAD` is already `c9c884e` (v0.37); reviewing working-tree HEAD would contaminate later gates (`eval-ledger-without-decision`, etc.).
- Did not treat registered OUT bounds (fabricated file, no content read, skipped↔pass incentive) as defects—they are explicit design, pinned by G38j/c.
- Did not expand review into commi

... [truncated, 1322 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 417672
- end_time: 2026-07-29T14:27:44.879Z
- log: see `exp-p12-A-output.log` for raw output
