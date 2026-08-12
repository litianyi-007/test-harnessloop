---
task_id: T-094-grok
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
pid: 64488
start_time: "2026-08-11T19:06:29.019Z"
end_time: "2026-08-11T19:13:27.456Z"
exit_code: 0
duration_ms: 418387
mode: background
phase: done
last_progress_at: "2026-08-11T19:13:27.457Z"
last_progress: Task completed successfully.
progress_seq: 15
progress_log: ./T-094-grok-progress.log
raw_log: ./T-094-grok-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-094-grok-output.log
started_by_pid: 64477
last_stream_event: process_alive
last_update: "2026-08-11T19:12:59.092Z"
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

# T-094-grok — grok (background, done)

Output streaming to `T-094-grok-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/14599 chars; complete parsed output is available through `hopper-dispatch --result T-094-grok --full`)_

````
I'll do a read-only adversarial analysis of the openclaw kernel for the four questions, starting from the approval surface, session key parsing, and every place that special-cases `tui` or channel shape.Next I'll map session-key parsing, `dashboard`/`webchat` channel plugins, and every runtime branch that keys off `"tui"`.Client capability negotiation looks like the real path — digging into how `exec-approvals` caps and approval events are gated.I have enough source evidence for all four questions. Writing the closed-loop adversarial review deliverable.# Adversarial review: exec-approval surface for AgentShell

## Summary

OpenClaw separates **two gates** for exec approval: (A) whether the *turn-source channel* is a supported initiating surface, and (B) whether a connected Gateway client is registered as an approval recipient. Borrowing session-key channel `tui` only helps gate A, and only if `messageProvider`/`turnSourceChannel` actually becomes `"tui"`. For AgentShell’s real path (`sessions.send` → `chat.send`), Provider is hard-coded to internal `webchat`, so the binding failure is almost certainly **gate B** (client id `cli` + `caps: []`), not the `dashboard` session-key segment alone. The first-party path for external shells is client capability negotiation (`exec-approvals` / `approvals`) plus `operator.approvals`/`operator.admin` scopes—not session-key spoofing.

## Files touched

none (read-only analysis)

## Acceptance verification (4/4)

### Q1 — Side effects of channel == `"tui"`

**Important distinction:** real TUI session keys are typically `agent:<id>:tui-<suffix>` (rest is a label, not channel `tui`). Evidence: TUI tests use keys like `agent:main:tui-next` (`kernels/openclaw/src/tui/gateway-chat.test.ts:869-878`). A custom key `agent:main:tui:<uuid>` makes channel segment `"tui"` via `parseAgentSessionKey` rest head.

#### Places where channel string `"tui"` changes kernel behavior

| # | Behavior change | Evidence |
|---|---|---|
| 1 | **Exec/plugin initiating surface forced `enabled`** (same as empty/`webchat`) | `exec-approval-surface.ts:63-65`, also `96-98`, `123-125`, `144-146` |
| 2 | **Human label becomes `"terminal UI"`** | `exec-approval-surface.ts:24-26` |
| 3 | **Turn-source chat route is disabled** — webchat/tui do *not* count as channel turn-source routes; they depend on live Gateway approval clients | `approval-turn-source.ts:12-17` (comment lines 13-14) |
| 4 | **Forwarder accepts `tui`/`webchat` as normalizable turn-source, but exec forwarding still strips non-deliverable channels** | `exec-approval-forwarder.ts:303-311` (accept), `314-321` (exec strips non-deliverable) |
| 5 | **Markdown capable** (no plain-text downgrade) | `message-channel.ts:122-124` |
| 6 | **Not a deliverable message channel** — no Telegram-style outbound plugin delivery | `message-channel-normalize.ts:40-42` + `CHANNEL_IDS` catalog (tui not listed); forwarder delivery requires `isDeliverableMessageChannel` (`exec-approval-forwarder.ts:358-360`) |

#### Client-id `"openclaw-tui"` (orthogonal to session channel)

| # | Behavior | Evidence |
|---|---|---|
| 7 | Counted as operator UI client | `message-channel.ts:64-70` |
| 8 | **Hard-coded only for plugin approvals**, not exec | `server-request-context.ts:114` (`PLUGIN_APPROVAL_CLIENT_IDS`), vs `108-112` (`EXEC_APPROVAL_CLIENT_IDS` = macos/ios/android) |
| 9 | Real TUI advertises **plugin-approvals only**, not `exec-approvals` | `tui/gateway-chat.ts:162-167` |

#### What does *not* special-case session channel `"tui"` (searched)

- No dedicated message segmentation/attachment downgrade path keyed on session-key channel `"tui"` beyond markdown capability above.
- No heartbeat/liveness assumption on channel `"tui"` in infra approval path (heartbeat is a separate internal non-delivery channel: `message-channel-constants.ts:19-25`).
- CLI/onboard/doctor `"tui"` hits are the **TUI command**, not session channel routing.

**Real cost of borrowing `tui` as session-key channel:**

1. **Semantic lie** — system text says “terminal UI” (`exec-approval-surface.ts:24-26`).
2. **Does not deliver approvals by itself** — `hasApprovalTurnSourceRoute("tui") === false` (`approval-turn-source.ts:15-17`); still need gate B clients.
3. **Does not register you as TUI client** — client id/caps are independent (`tui/gateway-chat.ts:156-167`).
4. **History/key namespace pollution** — sessions land under `...:tui:...` and look like TUI-owned keys to operators/tools reading session lists.
5. **Low functional blast radius on render path** if only the key segment changes and chat path still stamps Provider=`webchat` (see Q2/Q4).

### Q2 — No-channel / empty channel / `INTERNAL_MESSAGE_CHANNEL`

| Claim | Verdict | Evidence |
|---|---|---|
| `!channel` ⇒ initiating surface **enabled** | **True** | `exec-approval-surface.ts:63-65` |
| `INTERNAL_MESSAGE_CHANNEL` exact value | **`"webchat"`** | `message-channel-constants.ts:4` |
| Is `webchat` more honest than `tui`? | **Yes for UI clients** — label is “Web UI” (`exec-approval-surface.ts:27-29`); chat path already stamps it (`chat-send-user-turn.ts:159-160`) | |
| Key parse format | `agent:<agentId>:<rest...>` with non-empty agentId and rest | `session-key-utils.ts:267-287` (`parts.length < 3 \|\| !parts[1] \|\| !parts[2]` → null) |
| Empty channel segment `agent:main::uuid` | **Illegal / unparsable** (`parts[2] === ""`) | same as above |
| Key without “channel” concept | Legal if rest is non-empty, e.g. `agent:main:main`, `agent:main:my-label` | `toAgentStoreSessionKey` (`routing/session-key.ts:109-128`); default create uses `agent:<id>:dashboard:<uuid>` (`session-create-service.ts:222-224`) |
| `sessions.create.key` optional | Yes | `sessions-create.ts` schema lines 7-8 |
| Custom key accepted | Yes, via `toAgentStoreSessionKey`; only catalog sessions force dashboard prefix | `session-create-service.ts:339-377`, `436` |

**Does “no channel” break other things?**

- Initiating surface: **safe** (`!channel` → enabled).
- Approval *delivery* still requires connected approval clients (`approval-shared.ts:486-510`, `server-request-context.ts:116-141`).
- `hasApprovalTurnSourceRoute` also false for empty/webchat/tui (`approval-turn-source.ts:15-17`) — same “need live UI client” model.
- Session key channel hint for `dashboard` is extracted (`session-delivery.ts:27-36`) but is **not deliverable**, so it does not create external delivery routes.

**AgentShell path note (source-backed):** `sessions.send` delegates to `chat.send` (`sessions-messaging.ts:267-286`), and `chat.send` user-turn stamps `Provider: INTERNAL_MESSAGE_CHANNEL` (`webchat`) at `chat-send-user-turn.ts:159-160`. So for the shipped shell path, turn-source channel should already be **`webchat` (enabled)**, independent of the `dashboard` key segment—unless some other runtime path overwrites Provider/OriginatingChannel.

### Q3 — Fourth path (multi-dimension search)

Searched: channel plugins `approvalCapability`, gateway client caps/ids, approval RPC/events, dashboard as channel, macOS first-party connect, MCP/ACP bridges.

#### Path A — Client capability negotiation (designed for non-channel UIs)

```text
GATEWAY_CLIENT_CAPS.APPROVALS = "approvals"
GATEWAY_CLIENT_CAPS.EXEC_APPROVALS = "exec-approvals"
GATEWAY_CLIENT_CAPS.PLUGIN_APPROVALS = "plugin-approvals"
```

Evidence: `packages/gateway-protocol/src/client-info.ts:81-93`.

Delivery check (`canDeliverApprovals`):

1. Client must have scope `operator.admin` **or** `operator.approvals` (`server-request-context.ts:124-128`).
2. **Plus** one of:
   - `internal.approvalRuntime === true`, or
   - client id in hard-coded sets, or
   - advertised cap (`server-request-context.ts:131-140`).

Hard-coded sets:

- All approvals: `openclaw-control-ui` (`104-106`)
- Exec: `openclaw-macos`, `openclaw-ios`, `openclaw-android` (`108-112`)
- Plugin only: `openclaw-tui` (`114`)

When clients exist, gateway broadcasts `exec.approval.requested` to their connIds (`approval-shared.ts:463-471`

... [truncated, 6599 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 418387
- end_time: 2026-08-11T19:13:27.456Z
- log: see `T-094-grok-output.log` for raw output
