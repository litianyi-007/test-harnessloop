---
task_id: exp-p11-A
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
pid: 95211
start_time: "2026-07-29T14:20:46.968Z"
end_time: "2026-07-29T14:25:49.353Z"
exit_code: 0
duration_ms: 302340
mode: background
phase: done
last_progress_at: "2026-07-29T14:25:49.353Z"
last_progress: Task completed successfully.
progress_seq: 12
progress_log: ./exp-p11-A-progress.log
raw_log: ./exp-p11-A-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p11-A-output.log
started_by_pid: 95210
last_stream_event: process_alive
last_update: "2026-07-29T14:25:47.040Z"
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

# exp-p11-A — grok (background, done)

Output streaming to `exp-p11-A-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/10728 chars; complete parsed output is available through `hopper-dispatch --result exp-p11-A --full`)_

````
I'll review only harnessloop commit `9dc2f03`: inspect the diff and task acceptance criteria, then produce the adversarial review deliverable.Pulling the full diff and key changed sections for a defect hunt.Extracting the full implementation of the new loaders and call-site wiring for edge-case analysis.Probing edge cases the author may have missed: invalid-file + system refs, symlink policy, coverage double-count, and G18 sync.Found a crash path on unhashable `kind`. Re-running focused repros with a solid fixture.Goals live under `.harnessloop/goals/`. Re-running edge cases with the correct fixture layout.Goals live under `.harnessloop/goals/` — re-running edge cases with the correct layout.Checking one more contract detail: whether the loader docstring promises no exceptions, and how similar enum checks handle types.# Adversarial Code Review — harnessloop `9dc2f03`

**Reviewed object**: `9dc2f038c9a51ecd469ed34fbd224fa00676d645`  
(`v0.34.0` TH-0019 external-system declaration + eval `system` binding)  
**Mode**: review-only · no edits · code loaded via `git show 9dc2f03:…` and exercised in-process  
**Assumption**: scope is this commit only (not later v0.35+ work).

---

## Summary

Commit `9dc2f03` lands the TH-0019 first link: a versioned `.harnessloop/setup/external-systems.json` schema (exhaustive keys, no URL/host/path surface), optional `system` on `<goal>/evals.json`, project-level coverage fields, SKILL.md IN/OUT documentation, template, version bump to **0.34.0**, and G37a–G37k bidirectional teeth (+26 `check()` calls). The security shape for `params` (ASCII `[A-Z0-9_]`, not `\w`) and all-or-nothing invalidation are real and tested. Independently, the new loader **crashes with `TypeError`** on unhashable `kind` values (`list`/`dict`) instead of returning `external-system-invalid`, violating its own “any structural problem → `({}, message)`” contract and aborting the mechanical gate. That is a must-fix before release trust.

## Files touched

| Path | Rationale |
|------|-----------|
| `package.json` | version → 0.34.0 |
| `.claude-plugin/marketplace.json` | version → 0.34.0 |
| `plugins/harnessloop/.claude-plugin/plugin.json` | version → 0.34.0 |
| `plugins/harnessloop/.codex-plugin/plugin.json` | version → 0.34.0 |
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | `load_external_systems` / registry `system` / coverage / main print |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | IN/OUT + External System Declarations section |
| `plugins/harnessloop/skills/harnessloop-loop/references/external-systems-template.json` | placeholder template (no real endpoint/secret) |
| `scripts/validate.py` | G37a–G37k teeth |

Review artifacts written: **none**.

## Acceptance verification

No separate formal AC list was supplied beyond “review this commit, hunt defects, review-only.” Criteria below are derived from the commit’s own claims and exercised against the tree at `9dc2f03`.

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Version manifests aligned at 0.34.0 | **PASS** | All four versioned manifests show `"version": "0.34.0"` |
| 2 | Schema has no URL/host/path field; extra keys invalidate | **PASS** | `_EXTERNAL_SYSTEM_ALLOWED_KEYS = {id,kind,description,params}`; repro with `"endpoint"` → `external-system-invalid` |
| 3 | URL-shaped `params` rejected by construction | **PASS** | G37g; `EXTERNAL_SYSTEM_PARAM_RE = ^[A-Z][A-Z0-9_]{0,63}$` |
| 4 | Full-width param names rejected (`[A-Z0-9_]`, not `\w`) | **PASS** | G37h; fullwidth id also rejected by `EXTERNAL_SYSTEM_ID_RE` |
| 5 | `system` optional; undeclared id → `rae-system-undeclared` | **PASS** | G37i/j/k; live repro undeclared `nope` |
| 6 | Absence of declaration file = zero behavior | **PASS** | G37k; `load_external_systems`: `if not path.is_file(): return {}, []` |
| 7 | Coverage fields wired without per-round multiplication | **PASS** | Two-round fixture: `evals_with_system=1`, `external_systems_declared=1`, `rounds=2` |
| 8 | Loader never raises on structural problems (docstring contract) | **FAIL** | `"kind": ["http"]` and `"kind": {"x":1}` → **`TypeError: unhashable type: 'list'/'dict'`** inside `_load_external_systems_file` at `if kind not in EXTERNAL_SYSTEM_KINDS` |
| 9 | Symlink declaration rejected like `reference-roots.json` | **FAIL (policy gap)** | Working symlink to outside file loads green (`declared=1`, `evals_with_system=1`); broken symlink treated as absent (`is_file() False`) |
| 10 | Template free of real credentials/endpoints | **PASS** | Placeholder ids/params only |
| 11 | G37 teeth bidirectional & count claim | **PASS (delta)** | +26 `check()` (494→520); claim “551→577” uses a different baseline number but same **+26** |

**Acceptance verification: 8/11 hard claims hold; 1 crash defect + 1 policy gap.**

---

## Findings (defects the author would miss)

### F1 — BLOCKER · Gate crash on unhashable `kind`

**Where**: `verify_protocol.py` `_load_external_systems_file`  
```python
kind = raw.get("kind")
if kind not in EXTERNAL_SYSTEM_KINDS:  # frozenset membership hashes `kind`
```

**Repro** (tree at `9dc2f03`, minimal RAE fixture):

```json
{"version":1,"systems":[{"id":"s1","kind":["http"],"description":"","params":[]}]}
```

→ `TypeError: unhashable type: 'list'` from `load_external_systems` → `verify_project`. Same for `"kind": {"x": 1}`.

**Why it matters**

- Docstring of `_load_external_systems_file` promises: on **ANY** structural problem return `({}, message)`, never partial trust / never raise.
- A mechanical gate that throws leaves no structured `external-system-invalid`, can abort JSON mode / CI mid-run, and is fail-open relative to “always produce a verdict.”
- Hashable wrong types (`1`, `true`) correctly become `external-system-invalid`; only unhashables crash — easy to miss when G37c only mutates the string `"websocket"`.
- Contrast sibling fields: `id` / `description` / `params` all `isinstance` before use; `kind` does not.

**Fix shape** (guidance only):  
`if not isinstance(kind, str) or kind not in EXTERNAL_SYSTEM_KINDS:`  
plus a G37 letter that proves list/dict `kind` is red, not a traceback.

---

### F2 — MEDIUM · Symlink policy inconsistent with `reference-roots.json`

`load_reference_roots` (same file, same era of threat model) rejects symlinked declaration files so “what a reviewer sees in the diff and what the gate loads can never be two different files.”

`load_external_systems` explicitly skips that check. Live:

| Path state | Behavior |
|------------|----------|
| Symlink → outside valid JSON | **Accepted**, ids load, evals go green |
| Broken symlink | `is_file()` false → **silent absence** (not `external-system-invalid`) |
| Directory at that path | Same as absence |

For a file the commit markets as **versioned / git-committed / reviewer-facing metadata**, this is the same class of “diff vs runtime load” split reference-roots already closed. The docstring’s “no symlink check” is honest but **not** mirrored in SKILL.md OUT, so consumers infer stronger guarantees than the gate enforces.

Not a credential-exfiltration path by itself (still no network), but it **does** undermine declaration integrity for the one hard rule this feature owns (id-reference).

---

### F3 — LOW · Invalid declaration + `system` refs → dual, misleading violations

When `external-systems.json` exists but is invalid, `systems={}` and every well-formed `system: "<id>"` also emits `rae-system-undeclared` with detail *“is not declared in external-systems.json”* — even if that id appears in the broken file.

Repro: unknown key `endpoint` + `system: "staging-api"` →  
`{external-system-invalid, rae-system-undeclared}`.

Fail-closed is fine; the **message** misattributes “undeclared” when the real fault is “declaration untrusted.” Prefer suppressing cross-ref checks when the declaration load failed, or reword detail to “no trusted declaration (file invalid or absent).”

---

### F4 — LOW · Teeth bl

... [truncated, 2728 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 302340
- end_time: 2026-07-29T14:25:49.353Z
- log: see `exp-p11-A-output.log` for raw output
