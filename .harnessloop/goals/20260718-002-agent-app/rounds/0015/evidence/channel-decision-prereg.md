# rounds/0015 —— channel 取舍：主会话**先行登记**自己的答案（异构评审回来之前）

**为什么要先写**：T-094 已同时派给 codex 与 grok 做独立分析。若等它们回来再写自己的判断，
很难保证不是被它们带过去的。**先登记，再对照**——分歧点才有意义。

登记时间：2026-08-12，T-094 双路仍在运行中，主会话尚未看到任何一方的产物。

## 主会话的答案：用 **`webchat`**，不用 `tui`

### 依据

1. `INTERNAL_MESSAGE_CHANNEL = **"webchat"**` —— `kernels/openclaw/src/utils/message-channel-constants.ts:4`
   （另见 `src/plugin-sdk/channel-config-helpers.ts:42` 同值）。
2. 判定函数的 `enabled` 分支实际接受**三种**：**无 channel / `webchat` / `tui`**
   —— `src/infra/exec-approval-surface.ts:63-64`。
3. **`extensions/` 下没有 dashboard 插件**（实测 `ls -d extensions/*dashboard*` 无匹配）。
   所以 `dashboard` 是一个**没有插件的裸 channel 名**，`resolveChannelApprovalCapability`
   查不到能力 → 落进 `unsupported`。**这解释了为什么默认就打不通。**

### 为什么 `webchat` 优于 `tui`

- `webchat` 是 openclaw **自己的「内部聊天 channel」常量**；一个原生聊天壳在语义上正属此类。
- `tui` 是**终端 UI**。我们不是终端。借它能过路由，但那是**冒充一个我们不是的东西**，
  且内核别处若有「假定对端是终端」的渲染/分段逻辑，会踩到与我们无关的行为。
- 「无 channel」看似最干净，但 key 格式 `agent:<agentId>:<channel>:<uuid>` 是否允许缺段、
  缺段后别处解析会不会崩，**未验**——比 `webchat` 风险高。

### 主会话尚未查清、指望异构评审补的

- **Q1**：channel=="webchat" 在 openclaw 里还会影响什么（渲染/分段/投递/history 归类）？
  我只查了审批这一条链，**没有横向排查副作用**。
- **Q3**：有没有第四条路（`dashboard` 声明 `approvalCapability`、某种能力协商、注册为审批方的 RPC）。
  这一条我**没查**——正是最容易「只搜一处就下结论」的地方。

## 对照结果（2026-08-12，T-094 双路回来后填）

### 结论：**主会话的预登记答案（`webchat`）是错的——盯错了门**

| 项 | 主会话预登记 | codex | grok | 实际 |
|---|---|---|---|---|
| 提到 `webchat` | ✅ 推荐 | **0 次** | 10 次 | 与本问题无关 |
| 提到 `tui` | 评估后否决 | 5 次 | 21 次 | 同上，无关 |
| **找到第四条路** | ❌ **没查**（预登记时已自认这是最可能漏的地方） | — | ✅ **找到了** | ✅ 正解 |

### grok 找到、主会话完全没查的正解

审批能不能送到客户端，**不止 channel 那一道门**，还有一道**投递门**
`canDeliverApprovals`（`kernels/openclaw/src/gateway/server-request-context.ts:118-142`，主会话已逐行核实）：

```js
// 注释原文：Stable ids preserve shipped clients while explicit caps describe newer non-UI bridges.
const hasApprovalScope = scopes.includes("operator.admin") || scopes.includes("operator.approvals");
if (!hasApprovalScope) return false;
return (
  internal?.approvalRuntime === true ||
  ALL_APPROVAL_CLIENT_IDS.has(client.id) ||                    // 仅 openclaw-control-ui
  hasGatewayClientCap(caps, GATEWAY_CLIENT_CAPS.APPROVALS) ||
  (approvalKind === "exec" &&
    (EXEC_APPROVAL_CLIENT_IDS.has(client.id) ||                // openclaw-macos/ios/android
     hasGatewayClientCap(caps, GATEWAY_CLIENT_CAPS.EXEC_APPROVALS))) || ...
);
```

**内核为我们这类客户端准备了正规通路**：注释明写 caps 是给「newer non-UI bridges」的。
而我们握手时发的是 `client.id="cli"`、**`caps=[]`**、`scopes=["operator.admin"]`
（`OpenclawGatewayKernelClient.swift:310-322`）——scope 那道门本来就过，**卡在 caps 是空的**。

正解 = **握手声明 `"exec-approvals"`**（`client-info.ts:83`）。
既不是伪造 channel，也不是冒充 `openclaw-macos`。

### 这次异构评审值在哪

- 主会话把三条候选路（`webchat` / `tui` / 无 channel）分析得很细，**但三条都在错误的那道门上**。
- **预登记救了这次复盘**：我在看到任何一方产物之前写下「Q3 这一条我没查——正是最容易只搜一处
  就下结论的地方」，事后证明答案正在那里。**若不先登记，很难分清是我原本就知道还是被带过去的。**
- 两路结果**并不一致**：codex 全文 0 次提及 `webchat`、也没给出投递门；grok 给了。
  **双路的价值在这里体现了一次**——单派 codex 这轮会继续在 channel 上打转。

### 顺带暴露的第二个问题

grok 提到 gateway 是向有能力的客户端广播 **`exec.approval.requested`**，
而我们的 `EventMapping.swift` ④ 段映射的是 **`session.approval`**。
若两者不是同一事件，补了 cap 也会「送到了但渲染不出来」。已并入实现任务核查。

