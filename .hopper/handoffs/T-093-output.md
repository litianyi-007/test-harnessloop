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
end_time: "2026-08-11T07:49:51.585Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 267788
adapter_status: success
last_progress_at: "2026-08-11T07:49:51.586Z"
last_progress: Task completed successfully.
progress_seq: 10
terminal_event_emitted: true
---
# T-093 — code-review-adversarial · rounds/0014 会话持久化 A/B/C/D

**Reviewer**: grok (hopper EXECUTION agent, read-only)  
**Anchor**: `.hopper/tasks/code-review-adversarial.md::root`  
**Scope**: rounds/0014 session persistence (A 清单 / B 映射 / C history / D 再订阅)  
**Assumption (1 line)**: Live acceptance intended ≥2 sessions *with messages each*; evidence only exercised messages on 会话1 — 会话2 list recovery is proven, its history path is not.

---

## Summary

Independently reviewed the rounds/0014 session-persistence change (read-only): D1 `KernelClient` seven method signatures are unchanged and the new restore/history APIs sit in separate additive protocols; persistence is fail-safe and keeps `kernelKey` distinct from `kernelSessionID`; pagination has solid unit + mutation counterproofs with only edge-type notes (non-bool `hasMore`, no cross-page dedupe). Live restart recovery for 会话1 is well evidenced (screenshots + `messageSeq` 2→4 on the same `sessionKey`); multi-page live history and 会话2 non-empty history were not exercised. No MUST-FIX that blocks the main “restart then continue same kernel session” criterion.

## Files touched

none (review only; no edits)

Reviewed (not modified):

| Path | Role |
|---|---|
| `app/apps/AgentShell/Sources/AgentShellCore/SessionPersistence.swift` | A: disk list shape / load-save fail-safe |
| `app/apps/AgentShell/Sources/AgentShellCore/SessionStore.swift` | A/B/C/D orchestration |
| `app/kernel-client/swift/KernelClient.swift` | D1 seven methods + additive protocols |
| `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` | `restoreSession` / `fetchFullHistory` |
| `app/kernel-client/swift/EventMapping.swift` | `parseHistoryRecord` / text extract (0014 addition) |
| `app/kernel-client/swift/frame-replay-tests/SessionPersistenceTests.swift` | A + 反证1 |
| `app/kernel-client/swift/frame-replay-tests/SessionRestoreHistoryTests.swift` | B/D + C 反证2 |
| `.harnessloop/goals/.../rounds/0014/scope-lock.md` | standards + mid-round corrections |
| `.harnessloop/goals/.../rounds/0014/evidence/live/**` | restart / corrupt / wire / counterproof |

## Acceptance verification (6/6 questions answered; scope-lock checks partially verified)

### Q1 — D1 红线

| Check | Result | Evidence |
|---|---|---|
| D1 七法签名逐字未变 | **PASS** | Working-tree `KernelClient` protocol body has exactly 7 methods; `restoreSession`/`fetchFullHistory` are **not** in that body. Extracted signatures: `createSession` / `send` / `subscribe` / `interrupt` / `stop` / `respondApproval` / `capabilities` (lines 82–100). |
| 新增能力在独立加法式协议 | **PASS** | `SessionRestoring` + `SessionHistoryProviding` declared after the `KernelClient` closing brace (`KernelClient.swift:103–160`). |
| 未改 D1 语义（含 subscribe 派发屏障） | **PASS_WITH_NOTE** | `restoreSession` seeds `kernelKeyBySessionID` then calls **unmodified** `subscribe(session:)` (`OpenclawGatewayKernelClient.swift:1835–1841`). `subscribe` still: sync local continuation + `beginTrackingSubscriptionDispatch` → return stream immediately; background Task marks dispatch then RPC (`:553–595`). Send-side barrier unchanged. **No re-entry into “subscribe awaits ack” regression.** |
| 帧映射语义未改 | **PASS for 0014 intent** | 0014-only addition in `EventMapping.swift` is history parse helpers (`:773–816`). `messageID` on message.delta is rounds/0012 work already in tree, not a new 0014 mapping change. |

**Note (not D1 break)**: `SessionStore` holds a concrete `OpenclawGatewayKernelClient` and calls restore/history directly (`SessionStore.swift:58,217,259`). Comments in `KernelClient.swift:110` still describe `as? SessionRestoring` capability probing — documentation drift only; L1 has no alternate client.

### Q2 — 持久化正确性与安全

| Check | Result | Evidence |
|---|---|---|
| 凭证泄漏风险 | **PASS_WITH_NOTE** | Persisted fields: `handle` + `kernelKey` + `title` + `createdAt`. Live shape (`README-persistence-shape.txt`): `tokenRef` is `TODO-sg4-no-newapi-token-minted` only; endpoint/token not stored. Author documents future risk if real token minting lands (`SessionPersistence.swift:12–17`). **No live credential in frozen evidence.** |
| `kernelKey` ≠ `kernelSessionID` | **PASS** | Live record shows distinct values: `kernelSessionId=838df057-…` vs `kernelKey=agent:main:dashboard:6cc1b04c-…` (`README-persistence-shape.txt:18–21`). A-path persists both; history/send address via `kernelKey` only (`SessionStore.backfillHistory`, `fetchFullHistory(kernelKey:)`). |
| 坏数据 / 版本不匹配 fail-safe | **PASS** | `load()` any read/decode failure → `[]`, stderr only, no throw (`SessionPersistence.swift:93–103`). Version is written, not branched; bad schema → same empty-list path (documented `:49–51`). Unit 反证1: corrupt JSON → empty, then save+load works (`SessionPersistenceTests.swift:53–88`). Live: `sessions-json-CORRUPTED.txt` + `r14-corrupt.png` (empty list, 已连接, 可新建). |
| 永久卡死路径 | **No permanent stuck path found** | Corrupt → empty; missing file → empty without create (`testSessionPersistenceMissingFile…`); `reset()` deletes file; save failures ignored (best-effort). Concurrent multi-process last-writer-wins possible but not “stuck”. |
| 并发写 | **NOTE** | `save` uses `.atomic` full overwrite; `SessionStore` is `@MainActor` so single-process writes serialize. Two app instances on same `AGENT_SHELL_STATE_DIR` can clobber each other (last wins) — not a crash, possible silent list loss. |

### Q3 — 翻页 `hasMore` / `nextOffset`

**Unit + main-session mutation (existing):**  
- Green: `=== 结果: 50/50 PASS ===` (this review re-ran `./app/.build/debug/frame-replay-tests`).  
- Main-session destructive mutation after first page force-break → **48/50** (pagination + stuck-cursor tests red) (`counterproof-pagination-main-session.txt`).

**Independent counterexamples (this review, Python mirror of Swift loop + `jsonBool`/`jsonInt` rules):**

| Case | Behavior | Severity |
|---|---|---|
| Happy 2-page `hasMore:true,nextOffset:5` then false | offsets `[None,5]`, texts sorted by seq | OK — matches unit test |
| Mutation first-page-only | drops page-2 records | Confirms counterproof necessity |
| `hasMore` missing | stops after page 1 | **Safe** if server omits when done; **silent truncate** if server meant more without flag |
| `hasMore: "true"` (string) | treated non-true → stop | **Silent truncate** on non-bool; openclaw emits real bool (`chat-history-handler.ts:494–498`) |
| `hasMore: 1` (NSNumber-like) | pages (boolValue path) | OK for JSONSerialization |
| `nextOffset: "5"` / missing | **throws** | Fail-closed — good |
| Repeated `nextOffset` | **throws** | Fail-closed — good |
| Page order inverted | final sort by `seq` recovers order | OK |
| Dup same `seq` across pages | **no dedupe** — both kept | NOTE if server overlaps pages |
| Missing `seq` | stable comparator returns false when either nil | Order among null-seq not strictly chronological |

**漏页 / 死循环:**  
- Dead-loop: blocked by `seenOffsets` + `maxHistoryFetchPages=10000`.  
- Missed pages: only if client stops while server still has more — **non-bool/missing `hasMore`** is the residual silent path; integer/`true` path is correct.  
- **Live multi-page was not exercised**: both `chat.history` RECV in `r14-app2.log` are page 1 with `hasMore:false` (会话1: 2 roles; 会话2: empty messages).

### Q4 — 恢复后语义等价

| Concern | Assessment |
|---|---|
| `send` / `stop` addressing | **Equivalent for cold restart**: mapping reseeded; `SessionStore.sendMessage` uses persisted real `session.handle` (not the placeholder) (`SessionStore.swift:216–217,284–291`). |
| Event stream live (not snapshot) | **PASS**: unit feeds frame after `restoreSession` → messageDelta; live AFTER-RESTART arrives on restored session. |
| `subscribe` barrier | **Shared path** with create — restore does not bypass. |
| Placeholder handle in `restoreSession` | `kernelSessionID: kernelKey` (`OpenclawGatewayKernelClient.swift:1837–1840`) is **wrong field value**, but `subscribe` only reads `session.sessionID` for map lookup. Safe today; **latent footgun** if later code trusts that handle. |
| Per-session adapter caches | On new process: `lockStateBySessionID` idle; `lastRunIDBySessionID` / approval join tables / `seqByRunID` empty. **Correct for cold restart.** In-flight mid-send across kill is inherently lost. Pending approvals can re-enter via `approvalReplay` on the same `subscribe` path (`:585–587`) — L1 does not render them. |
| UI state | Restored `ChatSessionViewModel` starts with empty messages then history insert-at-0; `isWaitingForReply` false. Concurrent history Task + event Task intentionally race-safe by insert-not-replace (`SessionStore.swift:233–237`) but **no id-based dedupe** if history and live ever overlap same transcript lines. |
| History vs new-session | Restored sessions show transcript; newly created sessions start empty — intentional product difference, not a send/stop asymmetry. |

**Verdict on Q4:** Restored ≈ newly created for L1 send/subscribe/stop after cold restart. Residual notes only (placeholder field, no history↔live dedupe, empty caches).

### Q5 — 证据是否支撑「重启恢复」主判据

| Claim | Supported by | Strength |
|---|---|---|
| 两会话回到列表 | `r14-after.png` / `r14-cont.png` + persistence shape 2 records | **Strong** |
| 会话1 历史恢复 | `r14-after.png` SESSION-ONE; `r14-app2.log` `chat.history` RECV with user+assistant for key `6cc1b04c-…` | **Strong** |
| 恢复后可继续同一内核会话 | `r14-run1.jsonl` messageSeq **1–2** + `r14-run2.jsonl` messageSeq **3–4** on **same** `sessionKey=agent:main:dashboard:6cc1b04c-…` and same `sessionId=838df057-…`; `r14-cont.png` AFTER-RESTART | **Strong (best wire proof)** |
| WS `chat.history` live (not only unit) | `r14-app2.log` SEND/RECV `chat.history` with `sessionKey` matching persisted `kernelKey` | **Strong for single-page path** |
| 坏数据不卡死 | corrupt file + `r14-corrupt.png` | **Strong** |
| 翻页 live | **Not in live traces** (both histories ≤1 page; 会话2 empty) | **Unit + mutation only** |
| 「两个会话各自历史都在」 | 会话2: pre-restart already empty UI; `chat.history` RECV roles=`[]`; **no `SESSION-TWO` anywhere in app1 log** | **Weak / incomplete vs scope-lock wording** |
| RAE-0001 不回归 | No `evidence/runtime/acceptance-evals.json` under rounds/0014 | **Not frozen in this round’s evidence tree** (declaration gap if claimed) |

**Still partly declaration-backed:** multi-page pagination production path (unit-proven); “≥2 sessions each with messages” full matrix (only 会话1 had messages).

### Q6 — scope-lock 中途更正是否诚实

| Correction | Assessment |
|---|---|
| (1) HTTP → WS `chat.history` | **Honest and explicit** (`scope-lock.md:53–60`): names brief vs lock inconsistency, accepts WS with cost “must live-prove WS”, and live app2 log does prove WS. Matches discipline §4 (改标准，不事后放宽验收解释). |
| (2) `nextCursor` → `nextOffset` | **Honest and source-grounded** (`scope-lock.md:62–69`): cites two openclaw pagination implementations; implementation matches WS handler (`chat-history-handler.ts:494–498,584–585`). |
| Other silent relaxations? | **No hidden redefinition found** in code vs corrected lock. Residual: live “两会话各有历史” and RAE-0001 freeze are **evidence completeness** issues, not post-hoc standard rewrites. Exec-policy defer is explicit out-of-scope. |

### Scope-lock verification commands (spot)

| Check | This review |
|---|---|
| frame-replay ≥41/41 (now 50/50 with 0014 tests) | **PASS** re-run → `50/50 PASS` |
| D1 signatures | **PASS** (above) |
| 重启恢复主判据 | **PASS for 会话1 + list(2)**; 会话2 history matrix incomplete |
| 恢复后可继续 | **PASS** (messageSeq 2→4 + cont shot) |
| 破坏性反证 | **PASS** (unit + live corrupt shot) |
| 翻页反证 | **PASS** (unit + main-session mutation record; independent sim) |
| CI 平价 12/0/1 / typecheck / RAE-0001 | **Not re-executed in this review** (out of adversarial code focus; no frozen RAE artifact in 0014 evidence) |

## Decisions / deviations

- Treated L1 “cold restart” as the equivalence bar for Q4 (not mid-flight approval/send recovery).
- Independently simulated pagination instead of only trusting main-session counterproof text; did not re-apply the force-break source mutation (would require write; review is read-only) — used behavioral model + re-ran green suite.
- Did not re-run full CI parity / typecheck / RAE-0001 live matrix; noted absence of RAE freeze under 0014 evidence.

## Open questions

1. Was 会话2 intentionally left without messages in live验收, or did send fail silently? Evidence shows zero `SESSION-TWO` in app1 log and empty `chat.history` for key `59dd711c-…`.
2. Should `PersistedSessionFile.version` ever be checked (fail closed vs wipe) when schema evolves beyond “decode fails → empty”?
3. When real newapi tokens land, will `SessionHandle.billing.tokenRef` be excluded from `sessions.json` before shipping?
4. Should `fetchFullHistory` dedupe by `__openclaw.id` / `seq` if openclaw ever overlaps pages?

## Verdict

**PASS_WITH_NOTE**

No MUST-FIX that invalidates A/B/C/D for the demonstrated 会话1 restart-and-continue path. Notes are residual risk / evidence completeness, not red-line D1 breaks or stuck-shell failures.

### Notes (ranked)

1. **Evidence gap (medium)**: Scope-lock “≥2 会话各发数条消息且历史都在” is only fully proven for 会话1; 会话2 list+mapping restore is proven, history content is not.  
2. **Live multi-page gap (low–medium)**: Production multi-page relies on unit + mutation; live traces never needed page 2.  
3. **`hasMore` non-boolean → silent stop (low)** under real openclaw bool contract.  
4. **No cross-page id/seq dedupe (low)**.  
5. **`restoreSession` placeholder sets `kernelSessionID = kernelKey` (low, latent)**.  
6. **RAE-0001 not frozen under rounds/0014/evidence (process)**.  
7. **Future credential in `tokenRef` if minting goes live (documented by author)**.

## Next recommendation

1. Accept 0014 implementation for the main blocker (restart recovers list + 会话1 history + continue same kernel session) with the NOTES above.  
2. Before closing the round, either (a) freeze a second-session non-empty history live shot + wire, or (b) explicitly amend scope-lock verification wording if only “≥1 session with full history + ≥2 sessions in list” was intended.  
3. Optionally freeze a multi-page live `chat.history` (or keep unit+mutation as the declared pagination proof — already strong).  
4. Do **not** block on D1 red-line; do not reopen additive protocols into `KernelClient`.  
5. Track latent `kernelSessionID` placeholder and `tokenRef` persistence as follow-ups when billing/approval work lands (post-0014).

## Vendor output (parsed)

```
I'll perform an adversarial code review of the rounds/0014 session-persistence work: read the scoped sources, tests, and evidence, then write the deliverable to `.hopper/handoffs/T-093-output.md`.Next I'll inspect `fetchFullHistory`/`restoreSession`, EventMapping history parsing, and the live evidence for restart recovery.Digging into D1 signature diffs, adapter per-session state, app logs, and constructing independent pagination counterexamples.I have enough evidence for a full adversarial review. Writing the deliverable.## Deliverable

Written to `.hopper/handoffs/T-093-output.md`.

## Verdict: **PASS_WITH_NOTE**

| Q | Result |
|---|---|
| **Q1 D1 红线** | Seven method signatures unchanged; restore/history live in additive protocols; `restoreSession` reuses unmodified `subscribe` (send barrier intact) |
| **Q2 持久化** | Fail-safe on corrupt/missing data; `kernelKey` ≠ `kernelSessionID` in live shape; no credential endpoint/token on disk (placeholder `tokenRef` only) |
| **Q3 翻页** | Unit 50/50 + main-session 48/50 mutation hold; independent counterexamples: non-int `nextOffset` throws, stuck cursor throws; non-bool `hasMore` is residual silent-stop |
| **Q4 恢复语义** | Cold-restart send/subscribe/stop equivalent; caches empty as expected; latent note: placeholder handle sets `kernelSessionID = kernelKey` |
| **Q5 证据** | 会话1 restart + continue proven (`messageSeq` 2→4, same `sessionKey`); multi-page live and 会话2 non-empty history **not** exercised |
| **Q6 scope-lock** | Both mid-round corrections (WS path, `nextOffset`) are explicit and source-grounded — not silent acceptance relaxations |

**No MUST-FIX.** Main residual: live matrix only fully proves one session’s history; list recovery for two sessions is solid.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 267788
- end_time: 2026-08-11T07:49:51.585Z
- log: see `T-093-output.log` for raw output
