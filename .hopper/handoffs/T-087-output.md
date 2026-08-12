---
task_id: T-087
adapter: grok
model: grok-4.5
status: done
verdict: PASS_WITH_NOTE
mode: background
task_type: code-review-acceptance
reviewed_round: rounds/0012
---

# T-087 — rounds/0012 收盘前验收审查（code-review-acceptance / grok）

**Assumption (one line)**: Paths in the brief are relative to `.harnessloop/goals/20260718-002-agent-app/`; this review is read-only and does not re-dispatch prior adversarial tasks.

**Scope**: read-only final gate. Not a re-run of T-081–T-086; those are background only where residual honesty after their rework is checked.

**Independent machine checks this session**:
- `./app/.build/debug/frame-replay-tests` → **38/38 PASS**
- Parsed `evidence/live/repro-wire-trace.jsonl` → `evt.message.delta` `messageID=f22abd58` delta=`REPRO OK`
- Parsed `evidence/live/raw/wire-trace-inject.jsonl` → two deltas same `runID=5c989156…`, `index=0`, distinct `messageID` `a34542e8` / `84a19277`
- Visually inspected three PNGs (pre-fix doubling / post-fix dual bubble / REPRO OK)
- Confirmed openclaw still has `void runWithDiagnosticTraceContext` at `kernels/openclaw/src/gateway/server/ws-connection/message-handler.ts:476`
- Confirmed `SessionStore.appendAssistantDelta` keys on `messageID` with `=` overwrite (`SessionStore.swift:245-257`)

---

## Summary

rounds/0012 is a real repair-and-re-evidence round, not theater. Message grouping under the C plan is demonstrated end-to-end (schema optional `messageId` → EventMapping → SessionStore → live inject red→green). Client-side subscribe/send write-order is partially closed with a send/stop barrier that matches D1; server-side dispatch race and drop-frame detection remain open and are mostly registered as such. Recipe, isolation (`logging.file`), raw logs, screenshots, and a no-secret repro path exist and were re-run by the main session. Residual honesty debt remains: RAE-0001 condition ③ still literally requires **无丢帧** which this layer cannot assert; a few fossil phrases still overclaim “server subscription established” / “technically infeasible”; scope-lock’s verification table still says `video≥1` after the body revised that away; L1-REPRO still prints stale frame-test counts (31/31, 36/36 vs actual 38/38). **Do not claim full RAE-0001 pass. Technical repair work is acceptably closed with notes.**

## Files touched

none (review-only)

---

## Acceptance verification

### A. Six scope items (1–6)

| # | Item | Ruling | Evidence | “Looks done but isn’t”? |
|---|---|---|---|---|
| ① | 消息分组 | **达成** | Mechanism: `item1-mechanism-localization.md` + `instrumented-run-findings.md` §1 (session.message = full text; collision = two messageIds, same run/index). Fix C: schema optional `messageId` (`app/contracts/d2/schema/events/message-delta.schema.json`), mapping (`EventMapping.swift:208-209`), UI (`SessionStore.swift:245-257`). Live: pre `raw/l1-doubling-reproduced.png` (one bubble, concatenated text); post `live/l1-inject-after-fix.png` (two independent bubbles); inject wire `a34542e8`/`84a19277`. Offline plumbing: `testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs`. | **No** for the defect itself. **Yes if someone treats §7a frame-replay as “UI merge proved”** — L1-REPRO now correctly demotes that (T-085/086 adopted). UI merge has live observation only; D3 dependency-graph gap registered. |
| ② | 订阅竞态 | **部分达成** | Client write-order closed: barrier `awaitSubscriptionRpcDispatchIfPending` on `send`/`stop`; tests `testSendWaits…` / `testStopWaits…` / never-subscribed pass-through. Server still open: `message-handler.ts:476` still `void`. Front matter of `item2-subscribe-race.md` correctly says one closed / one open; ack-wait registered as **scope blocker** (更正 5). | **Borderline**. Current “current conclusion” is honest. Residual overclaim language remains in `SessionStore.swift:18,128` (“服务端订阅确认/已确立”) and fossil lines that still say “CI 契约模型下不可行” after 更正 5 revoked that framing (`item2:238`, `instrumented-run-findings.md` D2 row). |
| ③ | messageSeq / 序列断言 | **部分达成** | Gap “缺 3/5” **voided** as observation bias (`item3-messageseq.md` + struck text in instrumented §2). Implemented what is valid: wire `messageSeq` **monotone non-decreasing** via non-protocol observer; two-domain separation documented; this session **38/38**; destructive invert of the comparator turns exactly the regression test red. **Drop detection not implemented** — correctly argued impossible without per-subscription delivery seq. | **Yes if read against original scope-lock ③** (“真能证伪丢帧” + “人为丢弃一帧变红”). That hard requirement is **not** met; replaced by a weaker, valid ordering assert. This is honest after investigation, **not** the same empty-local-`nextSeq` mistake — but RAE still says 无丢帧. |
| ④ | recipe 文末 | **达成** | `OPENCLAW-ISOLATED-RUN-RECIPE.md` summary command now has `OPENCLAW_WORKSPACE_DIR` (~:276). Command-block enumeration: only intentional historical SG-4 block lacks it (flagged in-prose). Empty 6-line prose window check was destroyed and rewritten (`instrumented-run-findings.md` §6.2). | **No**. |
| ⑤ | 证据自足 + 隔离 | **达成（按修订后契约）** | Evidence has PNG=3, video=0, raw logs/traces plentiful (`live/raw/*`, `raw/*`, race logs). Wire traces + isolation before/after (gateway PID 29071 stable; `~/.openclaw` count 496→496). `logging.file` closes `/tmp/openclaw` leak; start script enforces log path under ISO. User-confirmed 2026-08-09: L1 = 截图+wire, 录屏→L2. | **Partial look-alike risk**: `scope-lock.md:141` verification table **still** requires `video≥1` while body text and data-sources revised it away — same “checklist lag” family. `live-closure.md` §6 still says 录屏字面未满足 (true at write time; stale as final RAE reading after 2026-08-09). |
| ⑥ | 无秘密可复现 | **达成（有环境依赖 note）** | `app/apps/AgentShell/repro/L1-REPRO.md` + `start-isolated-kernel.sh` + `stop-isolated-kernel.sh` (port-based kill, not wrapper-only). Live follow: `l1-repro-followed.png` + `repro-wire-trace.jsonl` `REPRO OK`/`f22abd58`. Secrets as param names only. | **Stale counts** in L1-REPRO (`31/31` §1, `36/36` §7a; actual **38/38**) — following the doc literally can produce a false “fail”. Not hermetic on a clean laptop (toolchain + provider creds + LaunchServices `export` footgun) — already noted by T-086; still true. |

### B. Honesty of registered non-goals (失败找台阶 vs 诚实收窄)

| Registered residual | Honest? | Why |
|---|---|---|
| 服务端 dispatch 竞态未关 | **Yes** | Source still `void` fire-and-forget; front matter + 关键限制 table match reality. |
| ack 版完整修法 = scope blocker | **Mostly yes** | 更正 5 correctly reclassifies “不可行” → scope (`app/contracts/` fixtures). Residual fossil “不可行” in item2:238 / instrumented D2 row is **stale wording**, not a silent re-claim of full closure. |
| 丢帧检测本层做不到 | **Yes** | `messageSeq` is transcript count (`server-session-events.ts:189-215`); gaps can be legitimate; observer path does not claim drop detection. |
| UI 合并无入库确定性判据 (D3) | **Yes after T-085/086 rework** | L1-REPRO §7a now says 名不副实 as “分组主判据”; frame tests only KernelClient. Live dual-bubble remains observational. |

**Judgment**: the four declared non-goals are **honest narrowing**, not “台阶”. The remaining problem is **incomplete strike-through of obsolete phrases**, not fake residuals.

### C. RAE-0001 four Pass conditions (`setup/data-sources.md`)

| # | Condition | Ruling | Basis |
|---|---|---|---|
| ① | 真实往返可见（L1: 截图 + wire trace；录屏不作要求，2026-08-09） | **达成** | `live/l1-repro-followed.png` shows assistant `REPRO OK`; wire carries `messageID=f22abd58`, delta `REPRO OK`. Inject path also UI-visible. |
| ② | 隔离性可证 | **达成** | With `logging.file`: user gateway PID unchanged; `~/.openclaw` file count stable; live-closure claims 0 hits of run/dir ids in global `/tmp/openclaw` after fix (contrast earlier instrumented leak with attribution). Isolation audit files present. Recipe/start-script now require STATE+WORKSPACE+logging.file. |
| ③ | 事件序列与契约一致——**无丢帧、无乱序** | **未完全达成** | **无乱序**: wire `messageSeq` monotone assert + offline destructive proof — good. **无丢帧**: explicitly **not** assertable at this layer; no per-subscription delivery counter; destructive “drop a frame → red” from original scope-lock **not** delivered. Unlike 条件① 录屏, **RAE text for 无丢帧 was not user-revised**. Observed traces look contiguous, but absence of evidence ≠ 无丢帧 proof — the exact 0011 class of mistake if overclaimed. |
| ④ | 失败可诊断（主动注入，非「没坏过」） | **达成** | Inject to dead port: two assistant failure bubbles + distinct messageIDs in wire; UI shows exact failure text. Label-in-use surfaces as operable RPC error (also a product limitation). |

**RAE-0001 overall**: **cannot full-pass**. Conditions ①②④ hold under current contracts; **③ fails the literal “无丢帧” limb**. Round decision must **not** mark RAE outcome=`pass` without either (a) user-confirmed rewrite of ③ into “无乱序 + 可解释的 messageSeq 行为 / 丢帧 out of layer”, or (b) a real delivery-seq signal.

### D. Overturns: traces vs residual contradiction

| Flip | Trace left? | Residual contradiction? |
|---|---|---|
| ① 机制 chat/delta 推断 → session.message + messageId | Yes (`item1` voids chat path; instrumented §1) | No material conflict |
| ①' A→C after T-081/082 + user | Yes (scope-lock ①' +定向解除表) | No |
| ② 未证实不改 → 源码证实改 → v1 ack 被 CI 推翻 → v2 barrier | Yes (item2 archaeology + front “唯一有效”) | **Yes**: SessionStore still says barrier prevents send before **服务端订阅已确立**; item2:238 still “CI…不可行” after 更正 5; instrumented D2 table same |
| ③ messageSeq 有缺口 → 观测偏差无缺口；丢帧不可用 messageSeq | Yes (struck instrumented §2; item3) | No on facts; RAE/scope wording lag is contract lag |
| ⑤ 录屏硬要求 → L1 截图+wire | Yes (data-sources 2026-08-09 注; scope body) | **Yes**: verification table `video≥1` still; live-closure §6 stale as final reading |
| `/tmp/openclaw` 不可隔离 → `logging.file` | Yes (live-closure §4; recipe; start script) | No |

**Judgment**: process archaeology is generally good (better than 0011). Residual live contradictions are **comment/table lag**, concentrated in SessionStore + verification table + a few “不可行” fossils — same disease class as “清单会过时”, smaller surface than pre-T-085.

### E. Process mistakes: recorded vs unrecorded

**Recorded (spot-checked, present in evidence)**: early TMPDIR kill; `rm` success message without verify; empty recipe 6-line check; messageSeq first destructive regex wrong (`seq` vs `messageSeq`); wire-trace missing new `messageID` field; `VAR=x open` vs `export`; wrapper pid ≠ port owner; full-width punctuation unbound; label hardcode invalidating race stats; “env not passed” misread of delayed trace creation.

**Unrecorded / incomplete of same class**:
1. **L1-REPRO expected PASS counts not bumped to 38/38** after item3 tests — checklist lag after a real add.
2. **`instrumented-run-findings.md` D2 residual row** still “CI 契约模型下不可行” after item2 更正 5 — cross-file consistency not re-enumerated.
3. **scope-lock verification row `video≥1`** not updated when body + data-sources revised — exact 0011 “改了主文漏了摘要/表” shape inside the round’s own contract.

No evidence of a large silent technical failure hidden from the process log.

---

## Decisions / deviations

- Did not re-run full L1 UI + provider path (credentials / interactive); used checked-in live artifacts + independent parse/visual check.
- Did not re-run CI flat-`swiftc` 12/0/1 or comment-out barrier experiment; mechanism inspected in source; frame-replay 38/38 re-run.
- Treated 2026-08-09 user-confirmed L1 evidence rule as authoritative over older scope-lock table cell and live-closure §6 for RAE ① only.
- Verdict vocabulary: chose **PASS_WITH_NOTE** rather than REWORK because technical repairs are real and residuals are mostly documentation/contract-lag; chose not PASS because RAE ③ cannot full-pass and residual overclaim language remains after T-085/086 “must fix before accept” list was only partially applied.

## Open questions

1. Will user confirm rewriting RAE-0001 ③ from “无丢帧、无乱序” to something layer-accurate (e.g. “messageSeq 单调非递减 + D2 seq F3 不变量；丢帧需内核投递序号，本层不做”)?
2. Should ack-aware send (subscribe still immediate) land in a scoped follow-up that may touch `app/contracts/d2/fixtures/`?
3. Who owns a SessionStore-level grouping test so UI merge is not forever “screenshot-only”?

## Verdict

**PASS_WITH_NOTE**

Not REWORK: C-plan grouping is red→green with field-aligned wire; barrier is a real client fix; recipe/isolation/repro/raw evidence are material improvements over 0011; declared residuals are mostly honest.

Not PASS: **RAE-0001 ③ 无丢帧 is not met** under the still-written contract; residual “服务端订阅已确立” / “不可行” / `video≥1` / stale 31·36 counts would let a careless close reintroduce 0011-style greenwash.

### What decision.md should say (recommendation)

- Six-item repair: **closeable with notes** (①④ done; ②③ partial by design; ⑤ under revised L1 evidence rule; ⑥ usable with env notes).
- **RAE-0001 outcome: not full pass** until ③ is revised or drop-detection becomes possible. Do **not** copy 0011’s “四条全达成” error.
- Feedback for the repair objective can be positive-with-residual; **RAE ledger must stay honest**.

### Prescription residuals before archival (not a new design round)

1. Rewrite `SessionStore.swift` header + `:128` — barrier = **本端订阅 RPC 已 dispatch**, not 服务端订阅已确立/确认.
2. Strike or annotate remaining “CI 契约模型下不可行” fossils (`item2:238`, instrumented D2 row) to match 更正 5 (scope blocker).
3. Fix `scope-lock.md` verification table `video≥1` → 截图+wire (align body / data-sources).
4. Fix L1-REPRO expected counts to **38/38** (both §1 and §7a).
5. Optionally note in `live-closure.md` §6 that 录屏 residual was later superseded for L1 by 2026-08-09 contract (keep failure history, mark superseded).

These are **prescription-level** (T-030/T-060 class), not a reason to reopen C-plan or barrier design.

## Next recommendation

1. Main session: apply the five prescription residuals above (doc/comment only).
2. Open user decision on **RAE-0001 ③ wording** (parallel to the 录屏 revision: explicit contract change, not acceptance-time reinterpretation).
3. Write `rounds/0012/decision.md` / `round-summary.md` with **RAE not full-pass** (or pass only after ③ revision) and list server race / drop-frame / SessionStore test / label hardcode as carry-forward.
4. Do **not** re-open subscribe-wait-for-ack; keep server race and ack-send as a scoped follow-up if desired.
5. After prescription residuals, optional narrow re-check is enough; full adversarial re-run of ②⑥ is not required unless claims expand again.
