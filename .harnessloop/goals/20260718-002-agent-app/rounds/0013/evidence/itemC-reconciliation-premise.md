# rounds/0013 C —— 对账前提复核（动手之前）

scope-lock C 写死：「对账可行性依据（codex 已给，**主会话未复核**，本轮须先复核）……**先验证这两处确实能对上，再动手建对账**。」本文件即该复核。

## 结论：**前提成立，可以建对账**。codex 的两条依据一真、一「引错目录但内容属实」。

## 依据 1：实时帧携带 messageId/messageSeq —— **成立**

`kernels/openclaw/src/gateway/server-session-events.ts`（codex 引 `:238-255`，实测该区间）：

```js
...(typeof update.messageId === "string" ? { id: update.messageId } : {}),   // 顶层 id
...(messageSeq !== undefined ? { seq: messageSeq } : {}),                     // 顶层 seq
    ...(typeof update.messageId === "string" ? { messageId: update.messageId } : {}),   // payload.messageId
    ...(messageSeq !== undefined ? { messageSeq } : {}),                                // payload.messageSeq
```

**同一对值在帧的两个位置各出现一次**（顶层 `id`/`seq` 与 payload 内 `messageId`/`messageSeq`）。我们的 wire trace 取的是后者。

## 依据 2：history 读取附加同样的 id/seq —— **成立，但 codex 的路径写错了**

codex 引的是 `src/sessions/session-transcript-readers.ts:214-226` —— **该文件不存在**。

按本轮纪律第 5 条（「我没找到」不等于「不存在」，先换搜索维度），改按文件名搜，真文件是
**`src/gateway/session-transcript-readers.ts`**（728 行）—— 只是**目录写错**（`src/sessions/` → `src/gateway/`），内容属实：

```js
:136   ...(typeof record.id === "string" ? { id: record.id } : {}),
:154   return record ? [{ ...record, seq: entry.seq }] : [];
:221   ...(record.id ? { id: record.id } : {}),
:225   seq: record.seq,
:500   messageId: string,                                    // 按 messageId 查单条
:513   return { found: true, message: found.message, oversized: false, seq: found.seq };
```

**history 侧确实带同一套 `id`/`seq`**，且提供按 `messageId` 精确查单条的通路。

> **记一笔**：若照 codex 给的路径直接去看，会得到「文件不存在 → 依据不成立 → C 方案作废」的错误结论。**这正是本轮纪律第 5 条要防的**——只不过这次是别人引错、我差点照单接收。

## 依据 3（codex 未提，主会话补）：拉 history 的 RPC 与调法

方法名 **`chat.history`**（我们此前只用过 5 个方法，这是新的）。参数形状取自 openclaw 自己的两处真实调用点：

- `src/tui/gateway-chat.ts:287` —— `{ sessionKey, agentId?, limit }`
- `src/agents/run-wait.ts:337-339` —— `{ sessionKey, limit: 50 }`，返回 `{ messages: Array<unknown> }`

`sessionKey` 即 `sessions.create` 返回的 `key`（我们已在 `kernelKeyBySessionID` 里存了）。

## 依据 4（2026-08-11 补，字段级复核）：两侧 id/seq **同源同键** —— **成立**

依据 1、2 只证到「两处各自都带 id/seq」，**没证它们是同一套**。两个集合各自有 id 但语义不同，
对账一样会假绿。补此复核：

两侧调的是**同一个函数** `attachOpenClawTranscriptMeta(message, meta)`
（`src/gateway/session-utils.fs.ts:145`），它把 meta 挂在 **`message.__openclaw`** 下：

| 侧 | 调用点 | 传入的 meta |
|---|---|---|
| 实时 | `server-session-events.ts:240-244` | `{ id: update.messageId, seq: messageSeq }` |
| history | `session-transcript-readers.ts:220-226` | `{ id: record.id, seq: record.seq }` |

而实时帧**同时**在 payload 顶层再发一份 `messageId: update.messageId` / `messageSeq`
（`:253-254`）——**与它自己 `__openclaw.id`/`.seq` 同一个变量**。故：

```
wire 侧 payload.messageId  ≡  该消息的 __openclaw.id  ≡  history 侧 __openclaw.id
wire 侧 payload.messageSeq ≡  该消息的 __openclaw.seq ≡  history 侧 __openclaw.seq
```

**对账键成立。** 另核 `__openclaw` 不会在 history 返回前被投影剥掉：
`chat-display-projection.ts:1810-1816` 读到后原样写回。

## 依据 5（2026-08-11 补）：拉 history 走 **HTTP**，不必改 Swift 客户端

依据 3 给的是 JSON-RPC 调法。实测另有一条 **HTTP** 路由，对本轮更合适：

- 路由：`GET /sessions/<sessionKey>/history?limit=N`（`sessions-history-http.ts:53`）
- 鉴权：shared-secret bearer —— 该路由**刻意**采用此模型，token/password bearer 即授予默认
  operator scope，无需额外 scope 头（`:120-122` 的注释是明写的设计意图）
- 返回：`{ messages: [...] }`，每条带 `__openclaw.{id,seq}`

**选它的理由**：对账脚本可完全落在 `repro/`（scope-lock 允许），**不必给
`KernelClient` 加第 8 个方法，也不碰 `app/kernel-client/swift/`**——避免与 B2 的重构冲突，
也不触碰「不改协议签名」的红线。

> **纠错留痕**：我先前一轮搜索得出「`src/gateway/` 里没有 `chat.history` handler」，**是错的**。
> 真 handler 在 `src/gateway/server-methods/chat-history-handler.ts:615`。根因不是搜索维度，
> 是**我自己的 `head -10` 把结果截掉了**——同一族的「我没找到 ≠ 不存在」，这次的凶手是截断。

## 对账方案（据此可实施）

1. 受控会话内跑若干轮往返，wire trace 收集所有 assistant `evt.message.delta` 的 `(messageID, messageSeq)`
2. 运行结束后 `GET /sessions/<key>/history`，收集其 assistant 消息的 `(__openclaw.id, __openclaw.seq)`
3. **断言：wire 侧集合 ⊆ history 侧集合，且 history 里的 assistant 消息在 wire 侧全部出现**
4. **破坏性反证**：从 wire 集合中删一条 assistant 消息 → 对账**必须变红**

**这是零协议改动的真丢帧检测**，正是 2026-08-10 修订后的条件③(b)(c) 所要求的。
