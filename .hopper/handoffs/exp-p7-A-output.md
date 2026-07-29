---
task_id: exp-p7-A
adapter: grok
model: grok-4.5
effective_selector: grok-4.5
task_type: code-review-adversarial
subject: harnessloop commit 7fa902f (v0.32.0 batch-2 force+record layers)
status: done
---

# Adversarial code review — harnessloop `7fa902f` (v0.32.0)

## Summary

Commit `7fa902f` implements batch-2's reversed predecessor field and the stop-reason record gate with honest upper bounds, solid fence routing, a matching 18-value enum, and ten G32 paired teeth. The **force layer is not actually forced**: when a round that *declares* `Predecessor:` has a non-numeric directory name, `int(round_dir.name)` fails and the gate **returns zero violations** while still counting `rounds_predecessor_declared` — a complete X1 fail-open of arithmetic and existence constraints. Python's Unicode-aware `\d` further accepts full-width digit round IDs and predecessor values. G32 never probes either path, so teeth give false confidence. **Verdict: REWORK.**

## Files touched

none (read-only review; deliverable only at `.hopper/handoffs/exp-p7-A-output.md`)

Reviewed subject (commit `7fa902fb97e86dfd2552cfbb3f36f8c6d084e3bf`, not modified):

| Path | Role in commit |
|---|---|
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | New `check_loop_predecessor_declaration` / `check_loop_continuation_declaration` + coverage |
| `scripts/validate.py` | G32a–G32j paired teeth |
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | Mechanical Gate Boundary IN/OUT bullets |
| `plugins/harnessloop/skills/harnessloop-loop/references/decision-template.md` | Optional field stubs |
| 4× version manifests | `0.31.0` → `0.32.0` |

## Findings

### F1 — P0 — Declared `Predecessor:` under non-numeric round dir silently disables the force layer

**Where (at `7fa902f`):** `check_loop_predecessor_declaration`:

```python
try:
    current_round_num = int(round_dir.name)
except ValueError:
    return [], state   # declared stays True; zero violations
```

**What breaks:** Once the field is present and the value is four digits, constraints 2–3 (strict `<`, predecessor directory exists) are skipped entirely if this round's own directory name is not int-parseable. The caller still does `coverage["rounds_predecessor_declared"] += 1`.

**Empirical reproduction** (loaded `git show 7fa902f:.../verify_protocol.py` into an isolated module; no repo edits):

| Fixture | `loop-*` kinds | `rounds_predecessor_declared` |
|---|---|---|
| `rounds/abc` + `- Predecessor: 0003` (and `rounds/0003` exists) | **`[]`** | **1** |
| Same shape with well-formed `rounds/0007` + `Predecessor: 0009` | `loop-predecessor-not-backward` | 1 |

So an agent that can choose its round directory name (and `verify_project` accepts any `is_dir()` child under `rounds/`) holds an on/off switch for the entire predecessor force layer. Forward refs, self-refs, and missing predecessors all go green under a non-numeric dir name.

**Why the author would miss it:** The docstring frames this as “a naming-convention violation this check was never designed to police … left unvalidated rather than crashing.” That understates the effect: it is not “we don’t police names,” it is “**declaring the field under a bad name makes the field unconstrained**.” The OUT column registers “never writes `Predecessor:`” and “today’s disk for existence,” but **does not** register this fail-open. G32 fixtures only ever use `0003`/`0007`.

**Severity:** **P0 / ship-blocking** for anything marketed as a force layer. Switch is held by the party under audit (X1).

---

### F2 — P1 — `PREDECESSOR_VALUE_RE = r"^\d{4}$"` is Unicode-aware; full-width round ecosystems go green

**Where:** `PREDECESSOR_VALUE_RE = re.compile(r"^\d{4}$")`, and `int(round_dir.name)` on full-width digit names.

Python 3 `re` `\d` matches Nd (including full-width `０`–`９`); `int("０００７") == 7`.

**Empirical (same harness):**

| Fixture | Result |
|---|---|
| `Predecessor: ０００３` while only ASCII `0003` exists | `loop-predecessor-missing` (format accepted; lookup uses the full-width string) |
| `Predecessor: ０００３` **and** dir `rounds/０００３` | **green** |
| current dir `rounds/０００７` + `Predecessor: 0003` (ASCII) | **green** |

Same file already has the correct ASCII-only pattern for attempt IDs:

```text
ATTEMPT_ID_RE = re.compile(r"^([0-9]{4})-a[0-9]{1,3}$")
```

…while the new code comment claims it “reuses … `ROUND_SEGMENT_RE` exactly,” and `ROUND_SEGMENT_RE` is itself `r"^\d{4}$"` — so the bug was **copied from a pre-existing wrong convention** next to a correct one.

**Severity:** P1. Not the cheapest bypass (needs matching full-width dirs), but it admits a parallel non-ASCII round-id space the gate treats as first-class, and it poisons any future “four digits means ASCII NNNN” assumption.

---

### F3 — P1 — G32 teeth give false confidence (blind to F1/F2)

G32a–G32j are well-built paired mutations for the happy path:

- missing / not-backward / self / invalid value / absence-silent  
- enum member / unjustified-stop / free-text note  
- fence routing (G32i)  
- full-width **period** fail-closed on stop reason (G32j)

They never:

1. Name a round directory anything other than `\d{4}`-shaped ASCII, or  
2. Feed full-width digits into `Predecessor:` / round dir names, or  
3. Assert that `declared=True` cannot coexist with zero structural checks.

Production code contains an explicit `except ValueError: return [], state` branch with **zero** destructive anti-proof. That is exactly the teeth failure mode this project has burned on before: green suite, live X1 switch.

**Severity:** P1 process defect; it is why F1 shipped.

---

### F4 — P2 — Protocol close-out still does not instruct writing the new fields

At `7fa902f`, “After each completed round” step 3 still only **must** declare Review / Reviewer / Review verdict. It never says:

- when continuing: write `- Predecessor: <prior>` on the **new** round, or  
- when stopping: write `- Loop continuation: stopped: <reason>`.

`decision-template.md` adds both as optional, migration-silent lines. SKILL OUT honestly says absence is invisible. Net effect: the force/record **checkers** land, but the agent-facing **write path** does not change — so production coverage stays `predecessor_declared=0 stop_recorded=0` forever until some other text teaches agents to write the fields.

This is partially intentional (zero-migration, Appendix F upper bound ①). It is still a delivery gap relative to the commit title “强制层 + 记录层落地”: what landed is the validator half.

**Severity:** P2 product completeness (not a logic crash).

---

### F5 — P2 — Template points agents at an enum that SKILL.md does not list

`decision-template.md`:

> `<reason>` must be one of the enumerated values in `harnessloop-loop/SKILL.md`'s Mechanical Gate Boundary

SKILL’s new bullet only names **categories** plus a few examples (`budget-checkpoint` / `user-interrupt` / `unjustified-stop`). The full 18-token frozenset lives only in `verify_protocol.py`’s `LOOP_STOP_REASON_ENUM`.

**Enum content itself is correct** (spot-checked against `docs/loop-stop-record-spec-20260728.md` §3.1: 6+5+4+2+1 = 18, set equality holds). The defect is **discoverability / single source of truth for authors**, not enum drift.

**Severity:** P2 docs wiring.

---

### What is solid (do not rework these away)

1. **Appendix F reverse is the right design** for the close-time gate: forward `continued:` is structurally unwritable when the successor does not exist yet; backward `Predecessor:` is.  
2. **Check order** arithmetic-before-filesystem is real (G32b: forward ref red even when the named round is absent).  
3. **Fence routing via `_uncoded_lines`** is real (G32i paired control).  
4. **`unjustified-stop` not red + `rounds_stop_unjustified` subset** matches §3.2; G32g holds.  
5. **Stop-reason fail-closed** on lookalikes (full-width period) holds; legacy `continued:` form correctly becomes `loop-continuation-invalid-value`.  
6. **Version bump** is consistent across all four manifests to `0.32.0`.  
7. **OUT column honesty** on (absence / reason honesty / today’s-disk existence) is unusually good — which makes F1’s *missing* OUT entry worse by contrast.

## Acceptance verification (6/6)

Adversarial review acceptance (machine-checkable where possible):

### 1. Commit subject is `7fa902f` and only that change was reviewed

**PASS**

```text
$ git -C harnessloop rev-parse 7fa902f
7fa902fb97e86dfd2552cfbb3f36f8c6d084e3bf
$ git -C harnessloop show 7fa902f --stat
# 8 files, +752/-5 — verify_protocol.py / validate.py / SKILL.md / decision-template / 4 version files
```

### 2. Force-layer predecessor constraints hold for well-formed round names

**PASS (happy path only)**

G32a/b/c/d/e logic re-derived from source + independent fixtures with `0003`/`0007`: not-backward, self, invalid value, missing, absence-silent all behave as documented.

### 3. No fail-open when the field is declared

**FAIL — F1**

```text
rounds/abc + decision "- Predecessor: 0003" + rounds/0003 exists
  → loop kinds = []
  → rounds_predecessor_declared = 1
  → exit path: zero predecessor violations
```

### 4. Digit pattern is ASCII-only four digits

**FAIL — F2**

```text
re.match(r'^\d{4}$', '０００３') → match
int('０００７') → 7
fullwidth current round + ASCII predecessor → green
```

### 5. Stop-reason enum is the §3.1 18-set; unjustified-stop not red

**PASS**

```text
len(LOOP_STOP_REASON_ENUM) == 18
set equality with §3.1 listing: yes
stopped: unjustified-stop → no loop-* violation; rounds_stop_unjustified == 1
```

### 6. New fields route through `_uncoded_lines` (fence cannot shadow)

**PASS**

G32i construction: fenced bad + unfenced good → green; remove only fence markers → `loop-predecessor-not-backward`.

**Score: 4/6 PASS, 2/6 FAIL (F1, F2).**

## Decisions / deviations

- Reviewed the tree **at commit `7fa902f`**, not `HEAD` (later `6c92440` / v0.33.2 fixes related issues; those fixes are **out of scope as evidence of author intent**, and were not used as a substitute for independent reproduction — F1/F2 were re-derived from `7fa902f` source + live Python behavior).
- Spec body in the consuming project still documents pre-Appendix-F `continued:`; this review grades the **implementation claim** (Appendix F reverse + §3 record), not whether the prose body of the external spec was rewritten.
- Did not re-run full `scripts/validate.py` (long suite); G32 logic was reviewed statically and force-layer defects were reproduced with a direct `verify_project` load of the commit blob.

## Open questions

- none that block the verdict  
- (non-blocking) Whether project-wide round-directory name validation should become a separate evolution issue vs only fail-closing inside the predecessor gate — either closes F1; the global rule is the larger product decision.

## Verdict

**REWORK**

Primary blocker: **F1** (declared `Predecessor:` + non-numeric round dir → complete silent disable of the force layer, with coverage still incrementing). Secondary required fix in the same pass: **F2** (`[0-9]{4}` not `\d{4}`, for both predecessor values and the current-round name check) + teeth that red-team both (F3). F4/F5 should ship in the same batch if the goal is real adoption, not only a green validator.

## Next recommendation

1. **Fail-closed on current-round identity before any arithmetic:** if `- Predecessor:` is declared and `round_dir.name` is not `^[0-9]{4}$`, emit a dedicated violation (e.g. `loop-predecessor-round-unnumbered`); never `return [], state`.  
2. **Replace every new (and, ideally, `ROUND_SEGMENT_RE`) `\d{4}` with `[0-9]{4}`**, consistent with `ATTEMPT_ID_RE`.  
3. **Add paired G32 teeth:** non-numeric dir + declared Predecessor must red; full-width digits must red (or be explicitly rejected by the ASCII pattern).  
4. **Register the residual** in SKILL OUT if any round-name policy remains intentionally partial.  
5. **Wire write instructions** into close-out / continue path (or accept that coverage stays zero and stop calling it “落地” without that).  
6. After the fix commit, re-run adversarial review only on the force-layer fail-open + Unicode + teeth — not a full re-litigation of Appendix F direction.
