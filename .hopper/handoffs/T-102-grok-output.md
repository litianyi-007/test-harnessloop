---
phase: done
last_progress_at: "2026-08-12T08:42:26.072Z"
last_progress: Task completed successfully.
progress_seq: 16
last_stream_event: process_alive
last_update: "2026-08-12T08:42:15.781Z"
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
end_time: "2026-08-12T08:42:26.069Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 430320
adapter_status: success
terminal_event_emitted: true
---
# T-102-grok — adversarial REWORK re-review (hopper 0.55.0)

**Reviewer:** grok (independent of T-102-codex)  
**Subject root:** `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/hopper-plugin`  
**Subject:** uncommitted working-tree changes (not a commit)  
**Mode:** read-only product review; deliverable is this handoff only  
**Assumption (1 line):** `composeTaskContent` is module-private, so it was exercised through `resolveDispatch` (its sole call site) rather than a direct import.

---

## Summary

The five T-100 REWORK fixes are real, not paper fixes: bare-marker sections now fail closed, `fileExists` only maps ENOENT to false, the three named test tightenings are present and green, CHANGELOG `dispatch.js:N` line refs match the current file, and `queue-brief-dropped-without-leader-tasklist` stays CLOSED. Live execution of `loadTaskSpec` + `resolveDispatch` (compose path) passed 19/19 adversarial fixtures, including all three marker forms with body and without. Residual notes: a latent empty-`composePrompt` chokepoint, structural-only bodies still accepted, a pre-existing short-window section bleed, and ISSUES Resolution still saying「11 条」while the suite has 12 tests — none of these re-open the five REWORK items.

## Files touched

none (review-only; no product edits)

Reviewed surface (read-only):

| Path | Why |
|---|---|
| `cli/src/dispatch.js` | `loadTaskSpec`, `composeTaskContent`, `fileExists`, call chain |
| `plugins/hopper/cli/src/dispatch.js` | vendored mirror of above |
| `cli/bin/hopper-dispatch` / vendored twin | VERSION + `specNotice` operator surface |
| `tests/unit/dispatch-task-content.test.js` | REWORK item (3) regression suite |
| `tests/unit/resolve-vendor-override.test.js` | `(--vendor override)` positive/negative pair |
| `tests/unit/resolve-and-model-hints.test.js` | non-empty Brief fixture debt |
| `tests/unit/readme-version-badge.test.js` | version-badge guard |
| `CHANGELOG.md` | 0.55.0 claims + line refs (item 4) |
| `docs/archive/ISSUES.md` | CLOSED status (item 5) |
| version manifests / READMEs / commands | 0.55.0 consistency (Q6) |
| `cli/src/tasks.js` | negative scope: must be unchanged |

## Acceptance verification (6/6 questions + 5 REWORK items)

### REWORK (1) — `loadTaskSpec` body-after-marker fail-closed

**Status: DONE (executed, not read-only)**

Code (`cli/src/dispatch.js:281-282`):

```js
const afterMarker = section.startsWith(markerText) ? section.slice(markerText.length) : section;
return afterMarker.trim().length > 0 ? section : null;
```

Live runs (import `loadTaskSpec` / `resolveDispatch` from workspace `cli/src/dispatch.js`):

| Fixture | `loadTaskSpec` | `resolveDispatch` (empty Brief) |
|---|---|---|
| `## T-1\n` | `null` | throws `/has no task content/` |
| `**T-1**\n` | `null` | (same contract) |
| `\| T-1 \|\n` | `null` | — |
| `## T-1\n   \n\t\n` | `null` | — |
| `### T-1\n` bodyless | `null` | — |
| CRLF `## T-1\r\n` | `null` | — |

Counter-example from T-100 (heading masquerading as spec) is closed.

### REWORK (2) — `fileExists` only swallows ENOENT

**Status: DONE (code + live probe)**

```js
// cli/src/dispatch.js:351-360
if (err.code === 'ENOENT') return false;
throw err;
```

Live:

- Missing tasklist + non-empty brief → notice `leader-tasklist.md is absent at …` (ENOENT path).
- `leader-tasklist.md` replaced by a directory → `loadTaskSpec` rethrows `EISDIR` (not laundered to null).
- `handoffs/` chmod `000` → `resolveDispatch` rethrows `EACCES` (not “file absent”).

Unit suite covers non-ENOENT on **read** (`EISDIR` test); no dedicated unit for `access()` EACCES on `fileExists` alone — live probe covers behavior.

### REWORK (3) — tests tightened

**Status: DONE; suite green**

Evidence in `tests/unit/dispatch-task-content.test.js`:

- d3 bare `## T-1` + empty Brief → `assert.equal(…, null)` + fail-closed reject (lines 162–177)
- whitespace-only `**T-1**` → strict `assert.equal(spec, null)` (lines 199–208), not the old vacuous or-chain

Evidence in `tests/unit/resolve-vendor-override.test.js`:

- positive `assert.match(r.stdout, /\(--vendor override\)/i)` on both override-order tests (lines 104, 117)
- negative tightened to same marker, not bare `/override/i` (line 181)

Command (not exit-0 worship — TAP body inspected):

```
node --test tests/unit/dispatch-task-content.test.js \
  tests/unit/readme-version-badge.test.js \
  tests/unit/resolve-vendor-override.test.js \
  tests/unit/resolve-and-model-hints.test.js
```

Result: **23/23 pass, fail 0**. No mkdtemp EPERM in this environment (nothing environment-skipped).

### REWORK (4) — CHANGELOG overclaim / line drift

**Status: DONE for every `dispatch.js:N` (and co-cited) ref**

| CHANGELOG citation | Current file content | Match? |
|---|---|---|
| `dispatch.js:174` adhoc `const taskSpec = brief` | L174: `const taskSpec = brief;` | yes |
| `dispatch.js:160-161` adhoc empty reject | L160–161 empty-brief throw | yes |
| swarm `:206-207` empty reject | L206–207 `--swarm requires a non-empty --brief` | yes |
| `dispatch.js:260-282` marker strip range | L260 `markerRe` … L282 `return afterMarker…` | yes |
| `dispatch.js:335` `fileExists` probe site | L335: `const tasklistExists = await fileExists(path);` | yes |
| `tasks.js:154-155` guardrail promise | closed-loop lines present | yes |
| `queue.js:140` empty-string brief | `const brief = map.briefIdx != null ? cells[map.briefIdx] : '';` | yes |

No remaining wrong line numbers among the `dispatch.js:NNN` set in the 0.55.0 entry.

### REWORK (5) — ISSUES stays CLOSED

**Status: DONE**

- Index: `CLOSED 2026-08-12 — fixed in 0.55.0` (`docs/archive/ISSUES.md` ~L37)
- Body: `**状态**：**CLOSED — fixed in 0.55.0**` (~L2194)
- No REOPEN / 撤回 language for this issue
- New open issue `stale-status-on-runner-death` is orthogonal (registered, not a reopen of the queue-brief defect)

Doc nit (not a reopen reason): Resolution still says regression suite「11 条」; file has **12** `test(` calls (d3 added).

---

### Q1 — five items truly landed?

**Yes**, by execution + tests + greps above. Item-by-item:

1. Body-after-marker → `null` + fail-closed: **proven live**  
2. `fileExists` ENOENT-only: **code + EACCES/EISDIR live**  
3. Tests: **present + 23/23 green**  
4. CHANGELOG refs: **all current**  
5. Issue CLOSED retained: **yes**

### Q2 — new criterion false-negatives on three markers?

**No false negatives on the required positive cases** (each executed):

| Marker form | Fixture body | `loadTaskSpec` | merge via `resolveDispatch` |
|---|---|---|---|
| `## T-1` heading | `Body under heading form.` | non-null, body kept | body + `### Queue brief` + queue brief |
| `**T-1**` bold | `Body under bold form.` | non-null | same merge shape |
| `\| T-1 \| … \|` table | `Body under table form.` | non-null | same merge shape |
| bonus `### T-1` | `H3 body.` | non-null | — |

### Q3 — third layer of “looks like content, no task”?

**Same exact shape (marker-only / placeholder-as-spec) on the queue path: no third instance found.**  
`loadTaskSpec` no longer returns placeholders (only comments/tests/CHANGELOG/ISSUES still quote them). Call chain for queue content is single-chokepoint: `resolveDispatch` → `composeTaskContent` → `loadTaskSpec` / brief / `fileExists`.

**Related residual / adjacent shapes (not the fixed REWORK hole, but call-chain honesty):**

1. **Latent empty `composePrompt`** (`cli/src/tasks.js:169`):  
   `parts.push(\`## Task spec\n\n${taskSpec.trim()}\`)`  
   Live: `taskSpec` of `''` / whitespace still yields a `## Task spec` section with empty body — the classic “frame looks full, task is empty” shape **if a caller bypasses** `composeTaskContent` / adhoc / swarm empty guards. Today those three entry points all reject empty brief; this is defense-in-depth debt in `tasks.js` (intentionally unchanged this release), not a live bypass of the five fixes.

2. **Structural-only “body” after marker still accepted** (live):  
   `## T-1\n\n---`, `***`, `|---|`, `` ` ` ``, `<!-- -->`, and table residue `| T-1 |   |` all return non-null. Heuristic is “any non-whitespace after marker,” not “semantic task text.” Weaker cousin of the bodyless hole; would need a product rule to tighten.

3. **Pre-existing short section window** (`rest.slice(50).search(/^##\s+/m)`):  
   Live: file `## T-1\n## T-2\nreal body for t2 only` → `loadTaskSpec(T-1)` returns **both** headings plus T-2 body. Wrong-task content, not empty-task content. Pre-existing, not introduced by REWORK.

**adhoc / swarm empty brief:** already fail-closed (L160–161, L206–207) — not a third hole.

### Q4 — every CHANGELOG `dispatch.js:N`?

All verified against current `cli/src/dispatch.js` (table under REWORK 4). **Consistent.**

### Q5 — keep CLOSED / reject “withdraw issue closure”?

**Overturn stands.**

- Reported defect: placeholder became Task spec; queue Brief never composed; vendor still exit 0 / done.  
- Workspace behavior now: merge brief+spec, operator notice instead of placeholder-in-prompt, fail-closed when both empty, bodyless marker treated as absence.  
- Therefore “fixed in 0.55.0” is an accurate description of this release candidate’s behavior for the filed issue.  
- Bodyless-marker was a residual of the *same* release’s first cut, now also fixed; it does not justify reopening as if the original fix never landed.  
- Caveats (notes, not overturn-killers): 0.55.0 not yet committed/tagged; Resolution「11 条」stale vs 12 tests.

### Q6 — scope / regression

| Check | Result |
|---|---|
| `cli/src/tasks.js` dirty bytes | **0** (`git diff -- cli/src/tasks.js`) |
| Version everywhere | **0.55.0** in package.json, package-lock, both plugin.json, marketplace (top + plugins[0]), codex plugin ×2, kimi.plugin.json, both hopper-dispatch `VERSION`, smoke.md, vendors.md, three README badges |
| Vendored `cli/src/dispatch.js` | **byte-identical** to `plugins/hopper/cli/src/dispatch.js` |
| Vendored `cli/bin/hopper-dispatch` | **byte-identical** |
| Placeholder prose still returned by code? | **No** (only docs/comments/tests quote historical strings) |

Scope of the uncommitted tree is broader than the five bullets (full 0.55.0 feature: merge, notices, version bump, ISSUES open item, etc.) — expected for the release branch under re-review; no unsolicited rewrite of `tasks.js`.

### Environment / unrun items

- **mkdtemp EPERM:** none. All fixtures and the 23-test batch ran successfully.  
- **Not product failures:** n/a.  
- **composeTaskContent** not directly importable (non-exported); verified via `resolveDispatch` only — noted in assumption line.

## Decisions / deviations

- Treated “execute composeTaskContent” as “execute its only production path (`resolveDispatch`)” because the function is intentionally non-exported.  
- Did not grade structural-only bodies or short-window bleed as REWORK for *this* five-item re-review; recorded under Q3 as residual/pre-existing.  
- Did not reopen ISSUES solely for the「11 条」vs 12 count drift.

## Open questions

1. Should `composePrompt` fail-closed on empty/whitespace `taskSpec` as defense-in-depth (would touch `tasks.js`, currently frozen by Q6)?  
2. Should body-after-marker require something stronger than `.trim().length > 0` (reject HR-only / table-residue-only sections)?  
3. Is the `rest.slice(50)` section window intentional enough to keep, or should a follow-up issue track cross-section bleed for short tasklists?

## Verdict

**PASS_WITH_NOTE**

All five REWORK items hold under live execution and targeted tests. Notes are residual Q3 shapes + ISSUES test-count drift — not regressions of the five fixes, not grounds for another REWORK of this batch.

## Next recommendation

1. **Ship 0.55.0** from this workspace state (version + vendored already consistent).  
2. **Patch ISSUES Resolution**「11 条」→「12 条」in the same commit or a docs follow-up (optional, low risk).  
3. **Optional follow-ups** (new issues, not blockers): empty-`composePrompt` guard; structural-body policy; short-window section boundary.  
4. Do **not** reopen `queue-brief-dropped-without-leader-tasklist` on the evidence of this re-review.

## Vendor output (parsed)

```
I'll perform an independent adversarial review of the five REWORK fixes in hopper-plugin: inspect the uncommitted diff, execute `loadTaskSpec`/`composeTaskContent` against real cases, then write the verdict to the handoff file.Next I'll extract the five fix points from the diff and run `loadTaskSpec`/`composeTaskContent` against real fixtures.Running live fixtures for the five REWORK claims and hunting third-layer empty-content bypasses.Five REWORK fixes verified by live execution; writing the adversarial review deliverable.# T-102-grok — adversarial REWORK re-review (hopper 0.55.0)

**Reviewer:** grok (independent of T-102-codex)  
**Subject:** uncommitted workspace in `hopper-plugin`  
**Assumption (1 line):** `composeTaskContent` is private; exercised via `resolveDispatch` (sole call site).

---

## Summary

The five T-100 REWORK fixes hold under live execution, not just code reading: bare-marker sections fail closed, `fileExists` only maps ENOENT to false, the three test tightenings are present and green (23/23), every CHANGELOG `dispatch.js:N` matches the current file, and the queue-brief issue stays CLOSED. Residual notes only — latent empty `composePrompt`, structural-only bodies still accepted, pre-existing short-window section bleed, ISSUES saying「11 条」while tests are 12 — none re-break the five items.

## Files touched

none (review-only)

## Acceptance verification (6/6)

### REWORK 1 — body-after-marker fail-closed — **DONE (executed)**

Live `loadTaskSpec` → `null` for `## T-1\n`, `**T-1**\n`, `| T-1 |\n`, whitespace-only body, bodyless `### T-1`, CRLF bodyless. Empty Brief + bare `## T-1` → `resolveDispatch` throws `/has no task content/`.

### REWORK 2 — `fileExists` ENOENT-only — **DONE**

Code rethrows non-ENOENT. Live: EISDIR on read; EACCES on unreadable `handoffs/` — not laundered to “absent”.

### REWORK 3 — tests — **DONE; 23/23 green**

- d3 bare `## T-1` + strict `assert.equal(spec, null)` present  
- `(--vendor override)` positive matches on both override tests; negative uses marker not bare `/override/i`  
- `node --test` on the four unit files: **pass 23 / fail 0**; no mkdtemp EPERM

### REWORK 4 — CHANGELOG line refs — **DONE**

| Ref | Current line | OK |
|---|---|---|
| `:174` | `const taskSpec = brief;` | yes |
| `:160-161` | adhoc empty reject | yes |
| `:206-207` | swarm empty reject | yes |
| `:260-282` | marker strip block | yes |
| `:335` | `fileExists` call | yes |

### REWORK 5 — ISSUES CLOSED — **DONE**

Index + body remain **CLOSED — fixed in 0.55.0**; no reopen/withdraw. Nit: Resolution still says 11 tests; file has 12.

### Q1 — five items landed? **Yes** (see above; executed).

### Q2 — marker false-negatives? **No**

Heading / bold / table forms **with body** each accepted live; merge includes body + `### Queue brief`.

### Q3 — third layer?

**Same hole (marker-only / placeholder-as-spec) on queue path: no third live instance.** Single chokepoint: `resolveDispatch` → `composeTaskContent` → `loadTaskSpec`.

Residuals (not REWORK of these five):

1. **`composePrompt`** still emits empty `## Task spec` if given empty/whitespace — latent; blocked today by queue/adhoc/swarm guards.  
2. **Structural-only body** (`---`, `***`, table residue) still accepted.  
3. **Pre-existing** `rest.slice(50)` short-window: `## T-1\n## T-2\nbody` makes T-1 absorb T-2 (wrong content, not empty).

### Q4 — line refs? **All match.**

### Q5 — keep CLOSED? **Overturn stands.** Reported defect is fixed in this 0.55.0 candidate; bodyless residual is fixed in the same release, not grounds to withdraw closure.

### Q6 — scope/regression

| Check | Result |
|---|---|
| `cli/src/tasks.js` | dirty bytes **0** |
| versions | **0.55.0** everywhere required |
| vendored dispatch + bin | **byte-identical** |

**Environment skips:** none (no EPERM).

## Decisions / deviations

Used `resolveDispatch` for private `composeTaskContent`. Did not grade residual Q3 shapes as failure of the five REWORK items.

## Open questions

1. Empty-`composePrompt` defense-in-depth (would touch `tasks.js`)?  
2. Stronger-than-whitespace body policy?  
3. Track short-window section bleed as a separate issue?

## Verdict

**PASS_WITH_NOTE**

## Next recommendation

Ship 0.55.0 from this tree; optionally fix ISSUES「11→12 条」; file optional follow-ups for Q3 residuals — **do not** reopen `queue-brief-dropped-without-leader-tasklist`.

---

Deliverable written to `.hopper/handoffs/T-102-grok-output.md`.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 430320
- end_time: 2026-08-12T08:42:26.069Z
- log: see `T-102-grok-output.log` for raw output
