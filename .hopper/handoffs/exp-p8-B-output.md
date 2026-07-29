---
task_id: exp-p8-B
adapter: grok
model: grok-4.5
effective_selector: grok-4.5
task_type: code-review-adversarial
subject: harnessloop commit a69ae03 (v0.33.0 batch-2 §4 anomaly + §5 canonical fields + Appendix B.1)
status: done
---

# Adversarial code review — harnessloop `a69ae03` (v0.33.0)

**Reviewed object**: `harnessloop` commit `a69ae03d6179cdd07dac82fdd8086051e07e25d3`  
(`v0.33.0`：批 2 §4 异常层 + §5 契约 canonical 字段 + 附录 B.1 X1 部分收口)  
**Mode**: review-only · no edits · tree via `git show a69ae03:…` + isolated import of that blob’s `verify_protocol.py` (worktree HEAD is later: `c9c884e` / v0.37.0)  
**Assumption (1 line)**: task id is `exp-p8-B` (hopper-runner); acceptance = commit claims + author-miss defect hunt against the six named attack families.

---

## Summary

Commit `a69ae03` adds the loop-autocontinue anomaly observation layer, three machine-parsed control-contract fields, Appendix B.1’s `loop-contract-profile-missing` hard gate, and nine G33 paired teeth. The intentional fail-closed-toward-silence polarity, Kleene three-valued AND, and mostly honest OUT column are real engineering. But the new evidence-index table reader **does not strip fenced code blocks** and takes the first pipe table it finds — a reproducible false-positive anomaly (against the stated polarity) and a silent false-negative (skip=0, switch held by the audited party). Separately, “latest round” is chosen with `int(round_dir.name)`, which accepts full-width Unicode digits, so a decoy round directory can silently suppress a real anomaly. Empty / template-placeholder `Profile:` values also bypass B.1’s hard X1 gate while only showing as `skipped_unparsable`. **Verdict: FAIL.**

## Files touched

none (read-only review; deliverable only at `.hopper/handoffs/exp-p8-B-output.md`)

## Acceptance verification (6/6 attack families)

### 1. Parser bypasses — **FAIL (evidence table); PASS (Profile fences)**

| Surface | Result |
| --- | --- |
| Fenced `- Profile:` example | **Held** — G33h + `_parse_labeled_line` → `_uncoded_lines` |
| Inline-code whole-line `` `- Profile: strict` `` | **Held** — does not match `- profile:` prefix; real unfenced line wins |
| Full-width colon `- Profile：standard` | Field treated as **absent** → anomaly skip; when activated → `loop-contract-profile-missing` (fail-closed for the hard gate) |
| **Fenced evidence-index table** | **BROKEN** — `_parse_markdown_table` deliberately skips `_uncoded_lines`; first well-formed table wins, even inside ``` |

**Attack F1 — false-positive anomaly (fenced all-valid shadows live missing)**

Minimal fixture (against `git show a69ae03:…/verify_protocol.py`):

```text
# control-contract.md
- Profile: standard
- Auto-continue on positive: yes

# decision.md (rounds/0007)
- Feedback: positive

# evidence-index.md
```
| … | Artifact health | … |
| --- | --- | --- |
| EX | … | valid | …
```

| … | Artifact health | … |
| --- | --- | --- |
| E1 | … | missing | …
```

| Expected | Actual (reproduced) |
| --- | --- |
| `loop_autocontinue_anomaly=0` (live table not all-valid) | `loop_autocontinue_anomaly=1`, `loop_anomaly_skipped_unparsable=0` |

This **violates the design polarity** the commit itself states: false alarms destroy the ack mechanism; the code path prefers silence — yet here it alarms on a documentation fence.

**Attack F1b — silent false-negative (fenced missing shadows live valid)**

Same setup with fenced `health=missing` first, live `health=valid` second:

| Expected | Actual |
| --- | --- |
| `anomaly=1` (or at least `skipped_unparsable>0` if table considered untrustworthy) | `anomaly=0`, `skipped_unparsable=0` — ordinary non-trigger, **no visibility** |

Author-note in `_parse_markdown_table` calls fenced examples “out of scope.” That is not registered as an OUT bullet for *polarity inversion*, and G33 never teeth it. G33h only covers Profile fences.

### 2. Silent zero-check — **FAIL (partial)**

| Path | Silent? | Notes |
| --- | --- | --- |
| Unparsable preconditions for anomaly | No | Counted in `loop_anomaly_skipped_unparsable` (intentional) |
| Fenced evidence table with determinate False (F1b) | **Yes** | `skipped=0` — looks like honest “no anomaly” |
| Empty `- Profile:` when activated | Soft | No `loop-contract-profile-missing`; only `skipped=1` |
| Missing `control-contract.md` entirely | Documented | OUT + `check_setup.gate_blocking` (other mechanism) |
| Missing Auto-continue field when activated | Soft | No hard gate (B.1 only closes Profile absence) |

**Attack X1-residual — empty Profile bypasses B.1 hard gate**

```text
# Activated: rounds/0003 has `- Predecessor: 0001`
# control-contract.md
- Profile:
- Auto-continue on positive: yes
# evidence all valid, Feedback positive
```

| Expected if X1 closes “no usable Profile” | Actual |
| --- | --- |
| `loop-contract-profile-missing` | **no** that violation; `anomaly=0`, `skipped_unparsable=1` |
| `parse_control_contract_profile` | `''` (not `None`) — field “present” |

Same shape with template leftover `- Profile: lite | standard | strict | custom`. B.1 letter (“no field at all”) is satisfied; B.1 spirit (switch not held by audited party) is not. OUT item on general unparsable is honest; empty-vs-absent is the gap.

### 3. Regex / `int()` Unicode traps — **FAIL**

New code path `_latest_round_decision_text`:

```python
numbered.append((int(round_dir.name), round_dir))
```

`int("００１０") == 10`. Full-width digit round directories are treated as later than ASCII `0009`.

**Attack I1 — decoy full-width round hides anomaly**

```text
rounds/0009/decision.md   → Feedback: positive
rounds/００１０/decision.md → Feedback: negative   # U+FF10–U+FF19
Profile=standard, Auto-continue=yes, evidence all valid
```

| Expected if “latest” means ASCII round id | Actual |
| --- | --- |
| anomaly=1 (from 0009) | anomaly=0, skipped=0 |
| Without decoy directory | anomaly=1 |

Silent non-trigger (no skip counter). Same family the repo later named for predecessor arithmetic (`6c92440`); **introduced here** on the anomaly “latest” selector and **still present on current HEAD** for this call site.

No `\d` in the new enum parsers (good). Evidence separator uses `:?-+:?` (ASCII-safe).

### 4. Cross-time-layer joins — **PASS_WITH_NOTE**

- Anomaly uses **today’s** project-level `control-contract.md` + `evidence-index.md` + each goal’s **latest** round Feedback only (OUT item 4: deliberate; G33i locks it).
- Activation scans any historical `Predecessor:` / `Loop continuation:` — intentional B.1 on/off, not per-round retroactive red.
- No new Rule-A/B-style “closed round judged by later tree shape” beyond the already-registered family. Acceptable for an observation signal that never changes exit code.

### 5. Teeth quality — **PASS_WITH_NOTE**

G33a–G33i are real paired mutations (flip Feedback / Profile / evidence health / fence markers / latest-only), not green-by-construction. Gaps relative to defects found:

| Missing tooth | Would catch |
| --- | --- |
| Fenced evidence-index table first-wins | F1 / F1b |
| Empty / placeholder Profile under activation | X1 residual |
| Full-width digit round as “latest” | I1 |
| Missing Auto-continue field under activation | residual X1 for the other field |

### 6. OUT-column honesty — **PASS_WITH_NOTE**

**Honest and useful:**
- Two of four §4.1 preconditions unimplemented → count is upper bound.
- Conservative polarity is itself a switch; B.1 closes only wholly-absent Profile.
- Ack consumption is skill prose only.
- File-missing vs field-missing split + `check_setup` cross-ref.
- Only latest round evaluated.

**Under-disclosed relative to code:**
- Evidence-index first-table-wins without fence stripping can invert the evidence condition (false positive *and* silent false negative) — not listed as an OUT bullet, while the IN column reads as “every data row of evidence-index.md … = valid” implying the live table.
- Docstring “out of scope” is not the same as OUT-column registration of polarity risk.

Canonical fields **do** fix T-077 Chinese「不需要」substring false-positive on free-text Auto-Continue rows (reproduced: free-text 不需要 + canonical `yes` → anomaly fires correctly).

---

## Findings (severity order)

### F-01 [P0] Fenced evidence-index table inverts anomaly polarity  
**Family**: parser bypass + silent zero  
**Where**: `_parse_markdown_table` / `check_evidence_index_all_valid` (new in a69ae03)  
**Repro**: Attack F1 / F1b above (exact outputs reproduced against a69ae03 blob).  
**Why author missed**: docstring treats evidence-index as “structured table file, not free-form prose”; G33h only fences Profile lines; G33d/e only mutate live-table health / file absence.

### F-02 [P0] `int(round_dir.name)` lets full-width round dirs steal “latest”  
**Family**: regex/int Unicode trap + silent zero  
**Where**: `_latest_round_decision_text`  
**Repro**: Attack I1 above.  
**Why author missed**: G33i only compares ASCII `0003` vs `0007`; same class later partially fixed for predecessor in `6c92440`, not for this call site.

### F-03 [P1] Empty / template-placeholder `Profile:` bypasses B.1 hard gate  
**Family**: silent-zero residual of X1  
**Where**: `profile_raw is None` test in `check_loop_autocontinue_anomaly`  
**Repro**: Attack X1-residual above.  
**Mitigation already present**: `skipped_unparsable=1` keeps soft visibility; not a hard red.

### F-04 [P2] Missing Auto-continue field has no B.1 twin  
Documented partial X1 (Profile only). Same switch shape for anomaly silence; only skip count. Acceptable if intentional; should stay in OUT (it is, under general unparsable).

### Non-findings (good)

- G33h fenced Profile first-wins: correct and reverse-mutated.
- Kleene AND: determinate False wins over unparsable (avoids blaming the wrong precondition).
- Anomaly never in `violations` / never changes exit code (as claimed).
- Activation includes `Predecessor:` alone (G33g).
- status/continue SKILL prose correctly labels ack as discipline not mechanical force.

## Decisions / deviations

- Reviewed exact tree of `a69ae03` via `git show` + isolated import; did not require worktree checkout.
- Did not re-score later commits (`6c92440` predecessor fix does **not** fix F-02 on current HEAD either; F-01 also still present on HEAD) — noted only as residual, not as this commit’s credit.
- Severity of F-01 elevated to P0 because it produces **false positives**, which the commit’s own rationale calls the mechanism-killing failure mode.

## Open questions

none (all FAIL items have minimal repros)

## Verdict

**FAIL**

Three reproducible defects with exact expected-vs-actual outputs: (1) fenced evidence table false positive, (2) fenced evidence table silent false negative, (3) full-width digit “latest” decoy. Any one of (1) or (2)/(3) is enough for FAIL under the stated attack families; together they show the observation layer’s inputs are still partially held by the audited party.

## Next recommendation

1. **Must-fix before treating §4 as shippable:**
   - Run evidence-index text through `_uncoded_lines` (or otherwise ignore fenced tables) before `_parse_markdown_table`; prefer the **last** unfenced table or the first table under a known heading if multiple live tables exist.
   - Select latest round with ASCII-only names: `re.fullmatch(r"[0-9]{4}", name)` (or the later `ROUND_NAME_STRICT_RE` pattern), never bare `int(name)`.
2. **Should-fix for B.1 spirit:** treat empty / non-enum `Profile:` when activated as `loop-contract-profile-missing` (or a sibling kind), not only `skipped_unparsable`.
3. **Teeth:** add G33 paired fixtures for F1, F1b, I1, and empty Profile under activation (destructive reverse required).
4. **OUT:** register evidence-index multi-table / fence handling explicitly if any residual remains after the fix.
5. Do **not** promote anomaly to a hard gate until F-01 polarity is closed — false alarms are worse than silence for this signal.
