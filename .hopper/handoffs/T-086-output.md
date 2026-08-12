---
task_id: T-086
adapter: grok
model: grok-4.5
status: done
verdict: REWORK
mode: background
---

# T-086 — rounds/0012 ②⑥ 返工后复审（code-review-adversarial / grok）

**Assumption (one line)**: leader-tasklist has no separate T-086 section beyond the shared T-085/T-086 brief; this review follows that brief only and did not read T-085.

**Scope**: read-only. No code edits.

**Reviewed objects**:
- `.harnessloop/goals/20260718-002-agent-app/rounds/0012/evidence/item2-subscribe-race.md` (full)
- `app/apps/AgentShell/repro/L1-REPRO.md` + `start-isolated-kernel.sh` + `stop-isolated-kernel.sh`
- `app/kernel-client/swift/OpenclawGatewayKernelClient.swift` (`subscribe`/`send`/`stop`/barrier)
- `app/kernel-client/swift/KernelClient.swift`
- `app/kernel-client/swift/frame-replay-tests/FrameReplayTests.swift` (new barrier + messageID tests)
- `app/apps/AgentShell/Sources/AgentShell/SessionStore.swift`
- `rounds/0012/evidence/live/` (`repro-wire-trace.jsonl`, `l1-repro-followed.png`, `live-closure.md`)
- D1 v3.6 §2.3; C# `OpenclawGatewayKernelClient.Subscribe`; openclaw `message-handler.ts:475-479`; fixture set under `app/contracts/d2/fixtures/`

**Independent machine check**: `./app/.build/debug/frame-replay-tests` → **36/36 PASS** (this review session).

---

## Summary

The rework is a **partial, real fix**, not pure theater: the send/stop-side “subscription RPC dispatched” barrier is structurally sound for a genuine client-side write-order race, and overturning subscribe-wait-for-ack was correct under D1 + fixtures. However, residual **overclaims** remain in the evidence doc and SessionStore comments (“两处窗口分别收口”, “服务端订阅已确立”), the **server-side race is still open** (admitted in one place, contradicted in another), and §7a as the **primary** criterion for “消息分组修复” is name-mismatched (it tests KernelClient messageID plumbing, not SessionStore grouping). That honesty gap is the same class of defect T-083/T-084 already punished. **Verdict: REWORK.**

## Files touched

none (review-only)

---

## Five targeted rulings

### (1) send-side barrier waits for “RPC dispatched” not “acked” — real close or performance?

#### (1a) What does the barrier actually close? Is the client/server split accurate?

**Ruling: mostly accurate, with two precision corrections.**

Implementation (`OpenclawGatewayKernelClient.swift:149-178, 540-582, 422-423, 621-622`):

1. `subscribe()` sync prefix: register continuation + `beginTrackingSubscriptionDispatch` → spawn unstructured `Task` → **return stream immediately**.
2. Background Task: optional test delay → **`markSubscriptionRpcDispatched`** → then `request("sessions.messages.subscribe", ...)`.
3. `send()`/`stop()` first line: `await awaitSubscriptionRpcDispatchIfPending`.

What it **does** close:
- **Client-side ordering of “enter request() for subscribe before enter request() for send/stop”** when both target the same session and subscribe was already called. Without the barrier, after `subscribe()` returns the actor is free; the unstructured Task must re-hop onto the actor, and a subsequent `await send()` can hop first and call `request("sessions.send")` before subscribe’s Task ever reaches `request("sessions.messages.subscribe")`. That is a real structural window (see 1b).

What it **does not** close:
- **Server-side concurrent handlers** — openclaw `kernels/openclaw/src/gateway/server/ws-connection/message-handler.ts:475-479` still does `void runWithDiagnosticTraceContext(..., handleIncomingMessage)`. Confirmed in source this session. Authors correctly leave this open in the “关键限制” table (`item2-subscribe-race.md:203-210`).
- **Ack / “subscription established on server”** — deliberately not waited. Name “已发出” is slightly strong: mark runs **before** `request()` (`:559-567`), not after WS write completion. In practice, because mark and the subsequent `request()` run contiguously on the actor, and `request()` calls `task.send` before its first suspension (`:1081-1087`), the effective guarantee is closer to “subscribe’s WS send was *initiated* before send can start its request” than “wire flush complete” — still not server ack.

**Split accuracy**: “client write-order closed / server dispatch still open” is the right architecture. Authors’ own wording in `send()` docs (`:406-418`) matches. **Do not treat this as full race closure.**

#### (1b) Did the client write-order race exist under Swift actor semantics, or is the barrier consoling a phantom?

**Ruling: the race is real for programmatic callers; near-zero probability on the human UI path.**

- `OpenclawGatewayKernelClient` is an actor. `subscribe()` has **no suspension point** between `Task {}` and `return stream`. The unstructured Task is **not** enqueued as the next actor job; it must later `await self.…` to re-enter.
- After `subscribe` returns, caller’s `await send()` is a competing actor hop. Swift concurrency does **not** promise the background Task runs before the next external call.
- **CLIRunner path** (`CLIRunner.swift:77` then optional immediate send at `:109-113`) is exactly this shape — no human delay.
- **UI path** (`SessionStore.swift:139-144`): session is only appended after `subscribe()` returns; user must click send. Human latency ≫ actor schedule jitter → practical risk low, structural risk still real for automation/tests.

Therefore: barrier is **not** pure self-consolation. It hardens a window that actor semantics leave open. Calling it “the race is fixed” without “for client dispatch ordering only” would be wrong.

#### (1c) Barrier tests: prove barrier, or self-certify?

**Ruling: they prove the mechanism works under forced delay + destructive coupling to production lines — not natural production frequency. Not pure tautology; not field proof.**

Evidence:
- `testSendWaits…` / `testStopWaits…` (`FrameReplayTests.swift:1774-1852`) inject `testSupportSetSubscribeDispatchDelay(200ms)`, poll send/abort dispatch at t=100ms (must still be false) and after window (must be true).
- Without artificial delay, the pending window collapses under typical scheduling — tests would be flaky or green-for-the-wrong-reason. Authors document this honestly (`:1760-1767`, `OpenclawGatewayKernelClient.swift:139-142`).
- Destructive anti-proof claim (comment out two `await awaitSubscriptionRpcDispatchIfPending` → 34/36) is the right shape; this review did **not** re-run the comment-out experiment (read-only / cost), but the tests clearly fail if `sendDispatchFlag` / `abortDispatchFlag` go true early — and those flags are set only inside the real `request()` stub path that production code reaches after the barrier.

**What they do not prove**: that the race fires at non-trivial rate in UI production without the test delay; that server race is closed; that SessionStore grouping is fixed.

---

### (2) Was overturning v1 (subscribe waits for ack) justified? Or should fixtures change?

**Ruling: overturning v1 was correct. Fixtures encode D1, not accidental old behavior. Rework direction is right; residual incompleteness is choosing not to enable send-wait-for-ack via fixture evolution (scope-limited, not directionally wrong).**

Independent D1 / cross-end check (not just `KernelClient.swift` comments):

| Source | subscribe shape |
|---|---|
| D1 v3.6 §2.3 | `function subscribe(session): AsyncStream<KernelEvent>` — **not** `Promise<…>` |
| C# `IKernelClient.Subscribe` | returns `IAsyncEnumerable` **synchronously**; fire-and-forget `Task.Run` for RPC (`OpenclawGatewayKernelClient.cs:378-417`) |
| Swift protocol | `async -> AsyncThrowingStream` (async only for actor hop); docs state non-Promise semantics (`KernelClient.swift:74-79, 87-88`) |
| SwiftFixtureRunner | explicit “optional gate”: subscribe returns stream even if mock never resolves (`SwiftFixtureRunner.swift:487-494`) |

Fixture inventory (this session, full scan of `app/contracts/d2/fixtures/**/*.json`):

- 13 fixtures call `subscribe`
- **only 1** provides `mock_response` for it (`basic/create-session-subscribe-message-delta.json`)
- **12** leave subscribe unmocked

Authors wrote “10/11” — **count is off by ~2**, minor. Direction stands: making `subscribe()` itself wait for ack hangs the runner when the gate never opens (documented design of optional gate).

**Counterfactual the authors under-emphasize**: one *could* keep subscribe immediate (D1-faithful) **and** make `send()` wait for **ack** if fixtures grew `mock_response` for every subscribe + runner always resolved gates. That would close more of the **server** window from the client side. That requires `app/contracts/` changes, which they treat as out of scope. So:

- “Fixture should change so subscribe waits” → **NO**
- “Fixture could change so send waits for ack while subscribe stays immediate” → **YES, possible, deferred**
- “v1 was wrong” → **YES**

Not a reason to reverse the second-edition direction.

---

### (3) Can L1-REPRO really run on a clean machine?

**Ruling: substantially improved after rework; pid/wrapper issue is now documented and scripted. Still not “anyone clean laptop one-shot” — several environment and TOCTOU dependencies remain.**

**Fixed relative to the brief’s explicit worry (wrapper pid / port 53709):**

- `app/apps/AgentShell/repro/stop-isolated-kernel.sh` exists (1881 bytes, mode +x).
- It kills **port listener** (TERM→KILL via `lsof`), then wrapper pid, verifies port free, optional `rm -rf` of `/tmp/l1-repro`.
- `L1-REPRO.md` §8 documents why not `kill $(cat gateway.pid)` and points at the script.
- Live author run: `repro-wire-trace.jsonl` shows `messageID=f22abd58`, delta `'REPRO OK'` (this session parsed).

**Still machine-local / fragile:**

| Risk | Evidence |
|---|---|
| Heavy toolchain | macOS 14+, Swift 6.x, Node engines from openclaw, **pnpm 11.2.2**, `git submodule` + `pnpm install --frozen-lockfile` |
| Credentials required | `L1_PROVIDER_*` must come from gitignored channel-params / env — no public dry-run path for full UI round-trip |
| `pick_free_port` TOCTOU | bind port 0 → close → later use (`start-isolated-kernel.sh:32-41`); classic race under concurrent starts |
| `run-node.mjs` wrapper | start script backgrounds `node scripts/run-node.mjs gateway` — may rebuild; slow/fail if dist/state dirty on clean clone |
| LaunchServices env | documented correctly (`export` not prefix); still a footgun if operator ignores it → app falls back to `ws://127.0.0.1:18889` + placeholder token (`KernelShellConfig.swift:18-19`) |
| Human-only UI steps | click / paste / IME notes; no automated UI assert in §7a |
| `/tmp` multi-user | `conn.env` holds TOKEN in cleartext under `/tmp/l1-repro` |
| Screen recording | `live-closure.md` already admits scope-lock 录屏 unmet — unrelated to this rework but still not “full L1 clean close” |

**Conclusion for (3)**: the specific killer (pid file = wrapper, port lives on) is **addressed in docs+script**. Clean-machine “follow the doc and green” still depends on preinstalled stack + live provider credentials + careful env export. Not a pure author-machine secret path anymore; not hermetic either.

---

### (4) After two conclusion flips, is `item2-subscribe-race.md` still self-consistent?

**Ruling: chronologically readable with intentional archaeology, but contains at least one live internal contradiction and one stale H1.**

Structure is honest about history: original “未证实故不改” → 更正 1–4 after T-083/T-084 → 返工结论 “源码证实，改” → v1 废弃 / v2 采纳. That part is good.

**Hard inconsistency still standing:**

1. **`item2-subscribe-race.md:175`**: “两处窗口分别收口”
2. **Same file `:203-210`**: server dispatch race **仍开着**

Those cannot both be true. The table at `:166-171` lists:
- window 1 = **server**
- window 2 = **SessionStore pre-subscribe**

What rework actually did:
- Window 2: largely closed by `SessionStore` awaiting `subscribe()` before appending session (`SessionStore.swift:139-144`) — local continuation exists before UI can send.
- **Additional** client write-order race (Task vs send): closed by barrier.
- Window 1 server: **not** closed.

So “两处窗口分别收口” is **false** and not struck through. This is the same overclaim family as pre-T-083.

**Other honesty issues:**
- H1 still: “查证结论：**未能证实，故不改**” — fine as fossil if you read the whole file; toxic if anyone cites the title alone.
- SessionStore header/comments (`:18-19, :125-128`) still say the barrier prevents send before “**服务端订阅确认/已确立**”. Barrier only waits for **client dispatch mark**, not server ack. **Overclaim.**
- Fixture count “10/11” vs measured **12/13 unmocked** — minor.
- “已发出” vs mark-before-`request()` — mild wording inflation already discussed.

---

### (5) Is §7a really a deterministic primary criterion for “消息分组修复”?

**Ruling: 名不副实 as primary criterion for grouping. Deterministic and valuable as messageID plumbing proof; not a SessionStore grouping test.**

Facts:
- `testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs` (`FrameReplayTests.swift:1590-1643`) drives KernelClient `testSupportFeedFrame` and asserts two `evt.message.delta` events carry distinct non-nil `messageID`s for the old collision shape (same runId, index=0).
- Frame-replay target depends on **KernelClient only** (`@testable import KernelClient`). It cannot call `SessionStore`.
- Actual grouping change lives in `SessionStore.swift:225-255` (`inProgressDeltaMessageID` keyed by `messageID`).
- L1-REPRO §7 title: “验证**消息分组修复**”; §7a elevates this test as **主判据**.

So 7a proves: **EventMapping + dispatch path preserve distinct messageIDs** — a **necessary** condition for the C-plan fix. It does **not** prove: SessionStore opens two bubbles, does not merge, does not concatenate. A regression that reverts SessionStore to `(runID,index)` while leaving messageID mapping intact would still show **36/36 green** under 7a.

7b correctly demotes live dual-bubble observation (failover/retry instability). That honesty is good — and makes the gap in 7a sharper: with 7b auxiliary and 7a not touching SessionStore, **no machine-checkable primary criterion covers the actual grouping logic**.

---

## Acceptance verification (5/5 targeted questions)

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1a | Barrier closes what authors claim (client write-order; not server) | **PASS with precision notes** | Code `:149-178,:422-423,:559-567`; openclaw `message-handler.ts:475-479` still `void`; authors’ own residual table `:203-210` |
| 1b | Client race exists under actor semantics | **PASS (exists)** | Unstructured `Task` after sync return; CLIRunner `:77→113`; not phantom |
| 1c | Barrier tests non-self-serving | **PASS_WITH_NOTE** | Forced 200ms delay + dual-time poll; destructive shape claimed; not natural-frequency proof |
| 2 | Overturn v1 justified by D1 not just fixtures | **PASS** | D1 v3.6 §2.3 non-Promise; C# sync return; 12/13 fixtures unmocked by design of optional gate |
| 3 | Repro clean-machine + pid honesty | **PASS_WITH_NOTE** | `stop-isolated-kernel.sh` + L1-REPRO §8 address wrapper/port; stack/credentials/TOCTOU remain |
| 4 | item2 self-consistent after flips | **FAIL** | `:175` “两处窗口分别收口” vs `:203-210` server still open; SessionStore “服务端订阅已确立” overclaim |
| 5 | 7a is honest primary for grouping fix | **FAIL** | Tests KernelClient messageID only; SessionStore grouping untested; title claims 分组修复 |

(Framed as the five brief questions; 1 split into a/b/c as the brief required.)

---

## Decisions / deviations

- Did not re-run CI flat-`swiftc` 12/0/1 or the comment-out barrier destructive experiment (cost; mechanism inspected in source; frame-replay 36/36 re-run locally).
- Did not re-run full L1 UI repro (credentials + interactive UI); used checked-in `repro-wire-trace.jsonl` / screenshot artifacts.
- Did not read T-085 (mutual invisibility).

## Open questions

1. Will a follow-up round change fixtures to allow **send-side wait-for-ack** (keeping subscribe immediate) so the server half can close without violating D1?
2. Should C# parity get the same barrier? Current `OpenclawGatewayKernelClient.cs` Subscribe has **no** equivalent (grep: no matches) — Mac L1-only may excuse this for now, but D4 parity debt grows.
3. Who owns a SessionStore-level unit/UI test for two-bubble grouping so 7a stops carrying a name it cannot defend?

---

## Verdict

**REWORK**

Not because the barrier is fake — it isn’t. Because the rework still **overclaims closure** in the evidence document and SessionStore comments, and because the **primary acceptance criterion for ①' grouping** still does not exercise the grouping code. Same honesty failure mode as the previous round, smaller surface, still blocking if “收官” means “claims match reality.”

### What is good enough to keep
- Second-edition architecture (subscribe immediate + send/stop dispatch barrier).
- Explicit residual server race in the 关键限制 table (keep; fix the contradictory “两处都收口” sentence).
- stop script + pid/wrapper documentation.
- 36/36 frame-replay including barrier anti-proof tests.
- Live REPRO OK artifact (`messageID=f22abd58`).

### Must fix before accept
1. **Strike or rewrite** `item2-subscribe-race.md:175` “两处窗口分别收口” to match reality: SessionStore pre-subscribe + client write-order closed; **server still open**.
2. **Rewrite SessionStore comments** (`:18-19, :125-128`) that claim barrier ensures “服务端订阅确认/已确立” — downgrade to “订阅 RPC 已在本端 dispatch（非服务端 ack）”.
3. **Rename / re-scope §7a** in L1-REPRO: primary offline criterion = “messageID 透传/撞键形状不丢 identity”；**either** add a SessionStore-level test for two-bubble grouping **or** explicitly state that grouping logic is accepted by code review + optional 7b, not by 7a.
4. (Recommended, not strictly same class) Fix fixture count 10/11 → 12/13; consider H1 banner “SUPERSEDED — see 返工结论”.

## Next recommendation

Main session: apply the three must-fix honesty patches (doc + SessionStore comments + L1-REPRO 7a framing). Optionally add a minimal SessionStore pure-function or harness test for messageID grouping. Do **not** re-open subscribe-wait-for-ack. After doc/comment (and ideally SessionStore test) land, re-dispatch a **narrow acceptance** review (not full open adversarial) on those three lines only. Server race remains a registered residual — acceptable only if no document claims it closed.
