# rounds/0015 —— live 验收遇阻：审批请求**根本没送到客户端**

**状态**：主判据未达成。**停下报告，不在机制未查透时改代码**（本轮纪律第 1 条）。
代码侧 A/B/C/D 四块均已实现且离线判据全绿（61/61、CI 12/0/1、D1 七法未变、codegen 4/4）——
**卡住的是内核侧的投递路由，不是我们的实现**。

## 现象（live，隔离实例 `ask=always`）

配置已确认写入：`tools = {"exec": {"ask": "always"}}`（冻结于 `live/raw/isolated-config-tools.json`）。

让 agent 执行 `echo APPROVAL_TEST_OK`，UI 里 assistant 的回复是（截图
`live/shots/r15-headless-refusal.png`）：

> The command was **blocked** — it didn't run.
>
> `exec denied: Headless runs cannot wait for interactive exec approval.`
> `Effective host exec policy: security=full ask=always askFallback=deny`
>
> This environment (headless, `ask=always`, no fallback) can't wait for interactive
> approval, so the shell call was refused outright. Nothing executed, no output produced.

**审批请求从未产生**，UI 上自然也不会出现审批卡片。命令**没有执行**——就结果而言是安全的，
但这不是「用户拒绝」，是**内核认为无人可问，直接按 `askFallback=deny` 拒绝**。

> 注：上面那段话是**模型的转述**，不是内核原文。内核里可核实的串是
> `askFallback`（`src/infra/exec-approvals.ts:273,430`，默认 `"deny"`）与下面的 reason 码。

## 机制（已查到的，逐条有出处）

| # | 事实 | 出处 |
|---|---|---|
| 1 | 内核有「**interactive approval client**」这一概念；无可用者时明确报「no interactive approval client is currently available」 | `src/infra/exec-approval-reply.ts:554` |
| 2 | 本次的拒绝原因码是 **`initiating-platform-unsupported`** | `exec-approval-reply.ts:33,541`；`agents/embedded-agent-subscribe.handlers.tools.ts:805,827` |
| 3 | 是否可交互由 **`initiatingSurface`** 分类决定，取值含 `disabled` / `unsupported` | `agents/bash-tools.exec-host-shared.ts:277-289` |
| 4 | `askFallback` 默认 `"deny"`，可选 `deny` / `allowlist` / `full` | `infra/exec-approvals.ts:430,967-973` |
| 5 | **存在专门的审批 scope：`operator.approvals`** | `gateway/operator-scopes.ts:6`；`gateway/exec-approval-ios-push.ts:35` |
| 6 | **我们的壳连上去拿到的 scopes 是 `operator.admin`**（UI 左栏「已连接 (scopes: operator.admin)」，多轮截图可证） | rounds/0013–0015 截图 |

## 真因（已查透，2026-08-12 补——**两条原假设都不对**）

`resolveApprovalInitiatingSurfaceState`（`src/infra/exec-approval-surface.ts:54-68`）**按 `channel` 分类，
完全不看 scope**：

```js
const channel = normalizeMessageChannel(params.channel);
if (!channel || channel === INTERNAL_MESSAGE_CHANNEL || channel === "tui") {
  return { kind: "enabled", channel, channelLabel, accountId };   // ← 无 channel 反而可审批
}
const capability = resolveChannelApprovalCapability(getChannelPlugin(channel));
```

- **H-A（申请 `operator.approvals` scope）—— 不成立。** scope 与该分类无关。
  客户端确实只申请了 `["operator.admin"]`（`OpenclawGatewayKernelClient.swift:320`），
  但改它**不会**影响 `initiatingSurface`。
- **H-B（结构上只认 TUI/Telegram）—— 也不对。** `!channel` 分支直接返回 `enabled`；
  **无 channel 是可审批的**，并非只有特定 channel 才行。

**真因**：我们的会话**带着一个 channel**，而该 channel 的插件没有审批能力，于是落到
`unsupported`。旁证：`sessions.create` 返回的 key 形如 `agent:main:**dashboard**:<uuid>`
（rounds/0013–0015 多次实测），即 channel = `dashboard`。

### 新的待验假设（比原来两条精确得多）

- **H-C**：`createSession` 时若不带 channel（或带一个有审批能力的 channel），
  `initiatingSurface` 即为 `enabled`，审批请求会正常投递到客户端。
  → 需先查清 `sessions.create` 的 channel 参数如何决定、我们的适配器现在传了什么、
  以及 D1 的 `Config` 里有没有对应位置。**改动可能落在 `createSession` 的参数上——
  那是 D1 七法之一，务必确认「传不同参数」不等于「改签名」。**
- **H-D**：`dashboard` channel 插件本可声明审批能力（`resolveChannelApprovalCapability`），
  只是没声明 → 那属内核侧改动，**超出本轮范围**。

## 已经确定不是问题的地方

- **配置没写错**：`tools.exec.ask=always` 实际落进了隔离实例的 `openclaw.json`。
- **我们的实现没跑偏**：出站 `approval.resolve`、decision 映射、`allowedDecisions` 逐请求校验、
  post-RPC 兑现核验，离线判据全绿；反证① 由主会话独立复验（去掉客户端校验 → 61/61 掉到 59/61，
  且失败文本显示内核把「允许」静默改写成 `denied/malformed-verdict` 而 RPC 仍回 `applied=true`）。
- **命令确实没执行**：就安全结果而言，当前状态比 rounds/0013 的「无关卡直接执行」**严格得多**。

## 建议的下一步

1. **先验 H-C**（在本轮 Allowed Changes 内、且属 scope-lock 的 runtime-recoverable 诊断）：
   查清 `sessions.create` 的 channel 从哪来、我们的适配器现在传了什么、能否不带 channel 或
   换一个有审批能力的。**注意红线**：`createSession` 是 D1 七法之一——**改传参不等于改签名**，
   但要逐字确认签名未动。
2. H-C 若不成立（例如 channel 是内核强制赋予、客户端无从影响）→ 落到 H-D，属内核侧改动，
   **超出本轮范围**，需归设计轮或走上游。
3. 无论如何**不接受**把 `ask` 关掉或改 `askFallback` 当作「通过」——
   那与用户裁定的「ask + 审批 UI」不是一回事（scope-lock 的 Rollback Condition 已明写）。

## 一处自我纠错留痕

本文件初稿列了 H-A（申请 `operator.approvals` scope）与 H-B（结构上只认特定 channel）两条假设，
并建议「先验 H-A（便宜）」。**两条都是错的**，而且我差点就照着 H-A 去改握手参数了——
那会是一次「按推断改代码」，正是本轮纪律第 1 条要防的。

救回来的动作是**多读了一层**：不停在「reason 码 = initiating-platform-unsupported」，
而是去读产生该码的判定函数本身。**读到判定函数才发现它压根不看 scope。**
