---
task_id: exp-p11-B
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
pid: 95215
start_time: "2026-07-29T14:20:47.028Z"
end_time: "2026-07-29T14:26:16.036Z"
exit_code: 0
duration_ms: 328958
mode: background
phase: done
last_progress_at: "2026-07-29T14:26:16.037Z"
last_progress: Task completed successfully.
progress_seq: 12
progress_log: ./exp-p11-B-progress.log
raw_log: ./exp-p11-B-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./exp-p11-B-output.log
started_by_pid: 95212
last_stream_event: process_alive
last_update: "2026-07-29T14:25:47.103Z"
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

# exp-p11-B — grok (background, done)

Output streaming to `exp-p11-B-output.log`. Status updates here.

## Vendor output (parsed)

````
I'll review commit `9dc2f03` only—start with the diff and the adversarial review frame, then hunt the listed attack surfaces.Fetching the full commit diff and locating the task acceptance criteria.Extracting the full implementation and running the G37 tests plus adversarial probes.Running G37 teeth and adversarial repros against the committed code.Testing against the exact commit tree, not later HEAD.Checking one more edge case around required-field exhaustiveness and whether G37 covers `rae-invalid-system`:# Adversarial review — harnessloop `9dc2f03` (v0.34.0 / TH-0019)

**Summary**  
Reviewed only `9dc2f03` (`v0.34.0：TH-0019 外部系统声明 + eval 的 system 绑定`). The design is largely tight: exhaustive keys on `external-systems.json`, no URL/host/path fields, `params` locked to ASCII `^[A-Z][A-Z0-9_]{0,63}$` (not `\w`), `_load_strict_json` wired, today-layer-only operands (no round retro-reddening), and OUT column mostly honest. One reproducible **silent-accept** defect remains: `version` is checked with `!= 1`, so JSON `true` (and float `1.0`) pass as valid version 1—the same bool/int trap this file already hard-guards for `activation_round`. G37e only mutates `2 → 1`, so teeth miss it.

**Files touched**  
none (review only)

**Acceptance verification (attack-surface hunt)**

| # | Surface | Result | Evidence |
|---|---------|--------|----------|
| 1 | Parser bypasses (inline/fence/fullwidth field lines) | N/A → JSON-only parsers | Loaders are JSON (`_load_strict_json` / entry field checks), not markdown `- Label:` parsers. Fullwidth ids/params/system refs correctly rejected (A5/A6). |
| 2 | Silent zero-check on malformed input | **HIT** | See **F1** below. |
| 3 | Regex/`int` Unicode traps | Mostly clean; bool/`==1` trap adjacent | `EXTERNAL_SYSTEM_PARAM_RE`/`ID_RE` use explicit ASCII classes; G37h proves `\w` would pass fullwidth. Version check does not use the activation_round bool guard. |
| 4 | Cross-time-layer joins | Clean | Both operands are today-layer (`evals.json`, `external-systems.json`); violations tagged goal/project, not closed rounds. |
| 5 | Teeth shape / green-by-construction | Mostly real; one gap | G37f/G37h have destructive controls. G37e does not probe `version: true`. No tooth asserts `rae-invalid-system` red. |
| 6 | OUT-column honesty | Mostly honest; small gaps | Secrets-in-`description`, no probe, absence=zero effect, params-not-values are stated. Symlink-on-declaration skip is code-doc only, not OUT. |

**Findings**

### F1 — MUST-FIX — `version: true` / `version: 1.0` silently accepted (silent zero / bool≡int trap)

**Where (commit `9dc2f03`):**  
`plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` in `_load_external_systems_file`:

```python
if data.get("version") != 1:
    return {}, f"{path}: 'version' must be 1"
```

Same file already documents and implements the correct guard for `activation_round`:

```python
isinstance(activation_round, bool) or not isinstance(activation_round, int) or ...
# "a bool is not accepted even though isinstance(True, int) is True"
```

**Minimal attack (exact file):**

```json
{
  "version": true,
  "systems": [
    {"id": "staging-api", "kind": "http", "description": "", "params": []}
  ]
}
```

Write to `.harnessloop/setup/external-systems.json` under a minimal project and run `verify_project`.

| Case | Expected (per design: version must be integer `1`) | Actual (9dc2f03) |
|------|-----------------------------------------------------|------------------|
| `"version": true` | `external-system-invalid` | **zero violations**, `external_systems_declared=1` |
| `"version": 1.0` | invalid if version is strict int | **zero violations**, `external_systems_declared=1` |
| `"version": 2` (control) | `external-system-invalid` | `external-system-invalid` ✓ |
| `"version": 1` (control) | green | green ✓ |

**Why it matters:**  
Malformed declaration is accepted fail-open (attack family #2). Python `True == 1` / `1.0 == 1` makes the check a false friend. G37e only checks `version: 2`, so CI stays green.

**Fix shape (for implementer; not applied here):**  
Mirror activation_round: reject unless `(not isinstance(v, bool)) and isinstance(v, int) and v == 1`. Add G37 tooth for `version: true` → red and mutation `true → 1` → green. (Note: `_load_versioned_roots` has the same inherited pattern—fix the new loader even if roots stay for a follow-up.)

---

### F2 — NOTE — `evals.json` entry keys still non-exhaustive (URL can sit next to `system`)

**Repro:**

```json
{
  "evals": [{
    "eval_id": "RAE-0001",
    "activation_round": 1,
    "system": "staging-api",
    "endpoint": "https://evil.example.com/api",
    "token": "sk-live-abcdef"
  }]
}
```

with a legal declared `staging-api` → **zero violations**, `evals_with_system=1`.

This is the pre-existing RAE entry style (only known fields checked; unknown keys ignored). TH-0019 correctly exhausts **`external-systems.json`** keys (G37d proves `endpoint` there is red). Claim “schema 里没有任何 URL 字段” holds for the systems file, not for the whole system-binding surface if a future runner reads eval entries. Not a gate security hole today (gate never probes/connects); honesty note for the next chain link.

---

### F3 — NOTE — Symlink declaration loaded (unlike reference-roots)

`load_external_systems` uses `path.is_file()` and does **not** reject `is_symlink()`. A symlink to a valid JSON file loads green (`declared=1`). Reference roots explicitly reject symlinked declaration files so git diff and gate input cannot diverge. Here the design docstring says “no symlink check” deliberately; stakes are lower (no path/URL fields). Not in the OUT list. Optional harden: same symlink rejection as roots, or document under OUT.

---

### F4 — NOTE — Teeth gap: no red assertion for `rae-invalid-system`

G37i only asserts absence of `{rae-invalid-system, rae-system-undeclared}` on a happy path. No case forces `system: ""` / `null` / fullwidth / non-string → `rae-invalid-system`. Implementation does reject those (A6/A10), but teeth do not lock it.

---

**What holds (positive)**

- Extra keys on systems (`endpoint`, top-level junk) → whole-file `external-system-invalid` (G37d/A12).  
- URL-shaped / dotted / slashed / lowercase `params` → invalid (G37g/A7).  
- Fullwidth param names rejected; `\w` would accept (G37h).  
- Duplicate JSON keys → invalid via `_load_strict_json` (G37f + destructive control).  
- Undeclared `system` → `rae-system-undeclared`; absent file + no `system` → silent (G37j/k).  
- Invalid systems file + eval ref → both `external-system-invalid` and `rae-system-undeclared` (A9); no partial trust of systems map.  
- No round-tagged cross-layer join; deleting systems only affects today-layer eval checks (OUT③ accurate).  
- Template has no real host/credential.  
- OUT①②④ match code (no secret scan, no reachability, params are names only).

**Decisions / deviations**

- Reviewed exact tree of `9dc2f03` via `git archive` (workspace HEAD is later: `c9c884e`); attacks run against archived `verify_protocol.py` only.  
- Assumed “version must be 1” means JSON integer `1`, consistent with activation_round’s bool exclusion and G37e’s wording—not “anything that `== 1` in Python”.  
- Did not treat inherited reference-roots `version: true` greenness as absolving the new loader (same trap copied into new code while activation_round already knows better).

**Open questions**  
none

**Verdict**  
**REWORK**

**Next recommendation**

1. Fix F1: strict `version` check (`int` and not `bool`, equal to `1`); add G37 tooth for `version: true` (+ optional `1.0`).  
2. Optional: F3 symlink reject or OUT line; F4 tooth for `rae-invalid-system`; later-chain note that eval entry keys stay non-exhaustive (F2).  
3. Re-run adversarial pass on the fix commit only—do not re-litigate the rest of the design unless the fix widens scope.
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 328958
- end_time: 2026-07-29T14:26:16.036Z
- log: see `exp-p11-B-output.log` for raw output
