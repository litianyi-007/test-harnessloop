---
task_id: exp-p13-B
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
mode: background
phase: done
progress_log: ./exp-p13-B-progress.log
raw_log: ./exp-p13-B-output.log
log: ./exp-p13-B-output.log
---

# exp-p13-B · code-review-adversarial · harnessloop `6d64c26` (v0.36.0 / TH-0025)

**评审对象**：`harnessloop` commit `6d64c2603b6761353dd1a911bd64f670a69cd513`  
**标题**：`v0.36.0 [TH-0025]：删掉插件自带的两句假保证 + 一条计算式 lint 钉住不复发`  
**方法**：只读。`git worktree add --detach /tmp/hl-review-6d64c26 6d64c26`；对照 parent `6d64c26^`；对 G39 逻辑做 tempfile 注入反证；跑完整 `python3 scripts/validate.py`（exit 0）；实证 `channel_params.py add`+`set --value-stdin`。未改 harnessloop 业务工作树。

**Assumption**：任务未附独立 acceptance 列表时，以 commit 自述（删两句假保证、G39 计算式 lint 钉住不复发、TH-0025 保持 open）+ 对抗面 1–6 为验收面。

---

## Summary

Commit `6d64c26` correctly **removes** the two false third-party-guard claims from `harnessloop-loop/SKILL.md` OUT and `verify_protocol.py`'s `_load_external_systems_file` docstring, and replaces them with first-person honest bounds (plugin ships no secret scanner; host must self-supply if it needs one; TH-0025 open). The structural claim that `channel_params.py add` then `set --value-stdin` (no `--sensitivity`) yields `"sensitivity": "unknown"` beside plaintext `"value"` is **empirically true**. Version manifests are consistently `0.36.0`; full `scripts/validate.py` on the commit tree exits 0.

The recurrence pin **G39 does not deliver the commit's "钉住不复发" claim**. Parent-tree replay shows G39 would have caught **only** the verify_protocol form (names `check-secrets.sh` + ownership lexicon), **not** the original SKILL.md form (names a "secret-scanning hook" with no `.sh`). Multiple minimal synonym / window / case bypasses reintroduce the same semantic false guarantee under a green G39; the honest host-handoff phrasing "must supply its own `check-secrets.sh`" is **false-positive red** via `\bowns?\b` matching ordinary English "own". G39 also has **no destructive counterproof teeth** (unlike G28/G34/G35). Comments claiming both TH-0025 sentences "pointed at `check-secrets.sh`" and that G39 "covers exactly the class TH-0025 found" are factually wrong. **Verdict: REWORK.**

---

## Files touched

none (read-only review; deliverable is this handoff file only)

Reviewed paths (no edits):

| Path | Role |
|------|------|
| `plugins/harnessloop/skills/harnessloop-loop/SKILL.md` | OUT rewrite (false guarantee → honest first-person) |
| `plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` | docstring rewrite (drop `check-secrets.sh`'s job) |
| `scripts/validate.py` | G39 orphan-`.sh` ownership lint |
| 4 version manifests | `0.35.0` → `0.36.0` |
| `plugins/harnessloop/skills/harnessloop-secrets/scripts/channel_params.py` | claim verification only (not modified by commit) |

---

## Acceptance verification (6/6 attack surfaces + commit claims)

### 1. Product fix: two false guarantees removed — **PASS**

| Site | Parent (`6d64c26^`) | Commit `6d64c26` |
|------|---------------------|------------------|
| SKILL.md OUT | `...is this repository's own secret-scanning hook's job...` | first-person: ships no scanner; host must self-supply; TH-0025 |
| verify_protocol.py docstring | `...this project's own \`check-secrets.sh\`'s job...` | same honest first-person rewrite |

No remaining `check-secrets.sh` under `plugins/harnessloop/` at this commit (`rg` zero hits). New OUT text does **not** name another concrete file as currently guarding; it assigns duty only as a conditional host obligation.

### 2. Structural OUT claim about `channel_params.py` — **PASS**

On a fresh temp project against the commit blob:

```text
add --channel demo --key TOKEN   → sensitivity: "unknown"
set --value-stdin (no --sensitivity)
store: {"sensitivity": "unknown", "storage": "local-file",
        "value": "REDACTED-BY-MAIN-SESSION（原为评审自造的演示假值，形态触发本仓 L2 凭证守门；见文末注）", "status": "present"}
```

Any scanner selecting `sensitivity == "secret"` would report zero coverage while plaintext sits beside it. Claim is load-bearing and true.

### 3. G39 catches the class TH-0025 actually shipped — **FAIL** (reproducible)

**Parent tree under G39 logic** (`6d64c26^` plugin tree, same regex as commit):

```text
hits: 1
  skills/harnessloop-loop/scripts/verify_protocol.py: `check-secrets.sh`
SKILL has "secret-scanning hook": True
SKILL has "check-secrets.sh": False
```

So G39 would have turned the tree red for verify only. The SKILL.md defect **never names a `.sh`**, so it is outside G39's detector by construction.

**Attack A — reinsert exact original SKILL false guarantee into the clean `6d64c26` tree:**

```text
File: plugins/harnessloop/skills/harnessloop-loop/SKILL.md  (append)
Content:
  Secret-shaped text anywhere in this project is this repository's own
  secret-scanning hook's job, never this gate's; the gate has no equivalent
  scanner and none is added here.

Expected (if "钉住不复发" / "covers exactly the class TH-0025 found"): RED, ≥1 hit
Actual: hits=[] → GREEN
```

G39 comments at `scripts/validate.py` (G39 block) claim both TH-0025 sentences "pointing at `check-secrets.sh`" — **false for SKILL.md**. That is OUT-column dishonesty inside the teeth themselves.

### 4. G39 synonym / window / case bypasses (same semantic false guarantee) — **FAIL** (reproducible)

G39 requires: orphan `[A-Za-z0-9_-]+\.sh` **and** ownership lexicon
`job|responsibilit(y|ies)|handles?|owns?|guards?|enforces?` within ±60 chars.

| # | Injection (append to plugin `.md`/`.py`) | Expected if pin holds | Actual |
|---|------------------------------------------|----------------------|--------|
| B | `Secret-shaped text is left to check-secrets.sh; this gate does not scan.` | RED | **GREEN** |
| E | `check-secrets.sh is responsible for scanning secret-shaped text in the host project.` | RED | **GREEN** (`responsible` ≠ `responsibility`) |
| G | `check-secrets.sh's duty is host secret scanning.` | RED | **GREEN** |
| H | `Secret scanning is covered by check-secrets.sh in CI.` | RED | **GREEN** |
| I | `check-secrets.sh will scan secret-shaped text for the host.` | RED | **GREEN** |
| K | `This is the job of the host project's secret scanner which lives in a separate tooling directory and is named check-secrets.sh for historical reasons only.` | RED | **GREEN** (`job` >60 chars from `.sh`) |
| F | `Secret scanning is CHECK-SECRETS.SH's job for the host repository.` | RED | **GREEN** (pattern requires lowercase `.sh`) |
| J | `凭证形态文本由宿主仓 check-secrets.sh 负责扫描，本门不做。` | RED | **GREEN** (no English ownership token) |
| D | `secret-shaped text is this project's own \`check-secrets.sh\`'s job` (positive control) | RED | **RED** ✓ |

So the only reliably caught English shape is roughly "own/job/handles/guards/enforces/responsibility + `*.sh`". The original SKILL shape and several natural false-guarantee phrasings sail through.

### 5. Polarity inversion: honest host handoff is red — **FAIL** (reproducible)

Ruling (commit message): first-person / "host must self-supply" is **legal**; claiming another named party is already guarding is not.

**Attack C:**

```text
A project needing that protection must supply its own check-secrets.sh and CI.

Expected by ruling: GREEN (honest conditional handoff to host)
Actual: hits=['.../SKILL.md: `check-secrets.sh`'] → RED
```

Root cause: `\bowns?\b` matches ordinary English **"own"** ("its own check-secrets.sh"), not only "owns the scan". Teeth punish the honest form the commit itself recommends, while green-lighting Attack B/E/G.

### 6. Attack-surface matrix (repo historical families)

| # | Family | Result on this commit |
|---|--------|----------------------|
| 1 | Parser bypasses (inline / fenced / full-width) | N/A as field parser. Full-width period `check-secrets．sh` **misses** (no `.sh` match). Fenced + "job" **caught** (no fence strip — over-catch, not under). "Discussing marker" with `job` nearby **caught**. |
| 2 | Silent zero-check | No malformed-input early-return that yields zero on error for G39. Clean tree `hits=[]` is correct emptiness, not X1. (Missing `PLUGIN_ROOT` would also green G39 alone; other validate steps would still fail.) |
| 3 | Regex class traps (`\d`/`\w`/full-width) | G39 uses `[A-Za-z0-9_-]` for names — **no** bare `\d`/`\w` trap on this path. |
| 4 | Cross-time-layer joins | N/A — pure today-tree static lint; no round join. |
| 5 | Teeth shape / green-by-construction | **FAIL**: G39 is a single live `check(not hits)` with **zero** G39a/b fixture mutations. Unlike G28/G34/G35, deleting or gutting the ownership regex cannot be forced red by the suite. Commit's "红→绿→红→绿" was manual, not suite-encoded. |
| 6 | OUT-column honesty | **Product OUT text: PASS** (first-person, TH-0025 open, channel_params claim true). **G39 comments + commit "钉住" claim: FAIL** (overclaim class coverage; misstate what SKILL said). |

### 7. Full suite on commit tree — **PASS** (non-decisive)

```text
cd /tmp/hl-review-6d64c26 && python3 scripts/validate.py
→ Plugin framework validation passed.  EXIT:0
ok: no shipped-plugin text ... (TH-0025) (found: [])
```

Green suite does **not** refute F3–F5; it only shows the current tree has no G39-shaped hits.

### 8. Version consistency — **PASS**

All four manifests at `0.36.0`: `package.json`, `.claude-plugin/marketplace.json`, `plugins/harnessloop/.claude-plugin/plugin.json`, `plugins/harnessloop/.codex-plugin/plugin.json`.

---

## Decisions / deviations

- Reviewed **only** `6d64c26` (worktree at that SHA). Current submodule HEAD is later (`c9c884e` / v0.37.0); later commits ignored for findings.
- G39 logic re-executed by extracting the commit's regexes into a pure function over temp plugin copies (same predicates as `validate.py`); not by forking the full 9-stage suite per attack (suite already proven green on clean tree).
- Did not grade "should Harnessloop ship a scanner?" — commit correctly leaves TH-0025 open; review is about honesty + recurrence pin only.

---

## Open questions

- none (bypass matrix is closed by repro; residual design choice is whether to broaden G39 to role-phrases or narrow the claim text)

---

## Verdict

**REWORK**

Not FAIL: the user-facing false guarantees **are** deleted and the replacement OUT text is honest; no new scanner theater; channel_params structural claim holds.  
Not PASS_WITH_NOTE: the commit's second half ("计算式 lint 钉住不复发") is materially oversold, G39 misdescribes the class it covers, and multiple minimal attacks reintroduce the same semantic lie under a green lint while punishing the honest host-handoff form.

---

## Next recommendation

1. **Fix G39 claim/coverage mismatch (blocking):** either  
   - (preferred narrow honesty) rewrite G39 comments + check message to say it only flags **orphan `*.sh` + English ownership lexicon within ±60 chars**, explicitly register as OUT: role-only phrases (`secret-scanning hook's job`), synonyms outside the lexicon, non-`.sh` tools, full-width/case variants, non-English; **or**  
   - (broader pin) add detectors for the **actual SKILL defect class** (third-party "…'s job/responsibility" for secret-scanning without requiring a `.sh` filename), with paired green controls so first-person "we do not scan" stays legal.
2. **Add destructive counterproof teeth (blocking for any "钉住" claim):** G39a inject orphan `evil.sh` + `job` → must red; G39b mutation control removing ownership word or shipping `evil.sh` under `PLUGIN_ROOT` → green; G39c inject exact historical SKILL sentence → red **if** that class is in scope.
3. **Fix polarity of `\bowns?\b`:** do not match bare "own" as possession ("its own `foo.sh`"); require true ownership verbs (`owns`/`owned`/`owning`) or a tighter collocation, so Attack C is green and Attack D stays red.
4. **Keep** the product OUT rewrite and TH-0025-open stance — those parts should survive rework unchanged.
5. After rework, re-run this adversarial frame on the fix commit only (same attack corpus A/B/C/D as oracle).

---

## Findings index (for triage)

| ID | Sev | Title | Repro |
|----|-----|-------|-------|
| F1 | high | G39 misses original SKILL.md false-guarantee class (no `.sh`) | Attack A → GREEN |
| F2 | high | Synonym/window/case bypasses for same semantic claim | Attacks B/E/G/H/I/K/F/J → GREEN |
| F3 | med | Honest "supply its own `check-secrets.sh`" false-positive red | Attack C → RED |
| F4 | med | No G39 destructive counterproof; green-by-construction vs suite | no G39a/b in `validate.py` |
| F5 | low | G39 comments misstate TH-0025 (both sentences "pointed at check-secrets.sh") | parent: SKILL has no `check-secrets.sh` |


---

> **主会话留痕（2026-07-29）**：本文件原文第 76 行含一个**评审自造的演示假值**
> （字符串本身自述 `test-plaintext`），用于复现 `channel_params.py` 在不传
> `--sensitivity` 时落 `sensitivity: "unknown"` 且明文并存的那条发现。
> 该串的**形态**触发了本仓的 L2 凭证守门（`scripts/check-secrets.sh`），
> 拦下了提交——本仓是 PUBLIC，且 2026-07-26 发生过真实凭证经 vendor 产物进公开历史的事故
> （`docs/security-incident-20260726.md`）。
>
> **按守门指引（「确属假值时用 REDACTED 标注」）已就地替换。**
> hopper 的产物本应逐字保留，本次是**有意的例外**，故在此留痕使其可见，而非静默改动。
> **被替换的只是那一个字符串，该条发现的技术内容一字未动。**
