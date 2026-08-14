# per-subscription 投递序号 —— 现状调查（rounds/0012 收盘后追加）

日期：2026-08-10。触发：用户要求就「向上游提方案还是先 fork 自行解决」做一轮异构讨论。

## 结论摘要

**openclaw 已经实现了完整的丢帧检测机制——只是没铺到我们走的那条路径上。**

先前记录的「本层做不到丢帧检测、需要内核提供 per-subscription 投递计数」**方向正确但描述不准**：不是「内核没有这个概念」，而是**「内核有这个概念，且已发货，但对 targeted 投递显式关闭」**。

## 1. 已存在的机制（主会话逐行核实）

### 服务端：per-connection 帧序号

`kernels/openclaw/src/gateway/server-broadcast.ts`：

```js
const clientSeq = new WeakMap<GatewayWsClient, number>();   // :157  连接级计数器
...
const nextSeq = (clientSeq.get(c) ?? 0) + 1;                // :229  逐连接递增
...
const eventSeq = isTargeted ? undefined : nextSeq;          // :257  ← targeted 显式不带 seq
if (!isTargeted) { clientSeq.set(c, nextSeq); }             // :258-259
const seqFragment = eventSeq === undefined ? "" : `,"seq":${eventSeq}`;   // :262
```

### 服务端：主动丢弃时序号照样前进

`:242-244`——慢客户端且 `dropIfSlow` 时，帧被丢弃但 `clientSeq` **仍然推进**（仅非 targeted）。**这是有意留下缺口让客户端察觉**，正是丢帧检测该有的语义。

### 客户端：官方 SDK 的缺口回调

`packages/plugin-sdk/dist/packages/gateway-client/src/protocol-client.d.ts:91`（`client.d.ts:99` 与多个 TUI 后端同）：

```ts
onGap?: (info: { expected: number; received: number }) => void;
```

**`expected` / `received` 两个字段直接给出「期望第几个、实际第几个」** —— 客户端据此算出丢了几条。

## 2. 缺口在哪

`session.message` 事件通过 `sessionMessageSubscribers` 投递给**特定 connId**，即 **targeted** 路径 → 命中 `:257` 的 `isTargeted ? undefined : nextSeq` → **帧上没有 `seq` 字段** → 客户端的 `onGap` 永远不会为这条路径触发。

**这是一处显式分支，不是遗漏。** 但代码未说明为何排除；且计数器本就是 per-connection（`WeakMap` 按连接键），技术上把 targeted 纳入并不困难。

## 3. 对先前记录的更正

`item3-messageseq.md` §6 写「要做需要内核侧提供投递序号」——**方向对，但当时不知道该机制已存在**。准确表述应是：

> 需要把 openclaw **已有的** per-connection 帧序号（`clientSeq` + wire `seq` + 客户端 `onGap`）**扩展到 targeted 投递路径**；这比新增一个概念便宜得多。

**这是本轮第三次「主会话说没有、实际有」**：
1. 「无手段隔离 openclaw 日志」→ 实际有 `logging.file`（两家评审同时找到）
2. 「等 ack 违反契约」→ 实际 D2 §3.3 定义 subscribe 响应为「流已建立」（codex 找到）
3. 「内核不提供投递序号」→ 实际广播路径已完整实现（grok 找到，主会话逐行复核）

**共同模式：搜索维度选错，就把「我没找到」当成了「不存在」。** 三次都是异构评审纠正的。

## 4. 异构讨论（T-088 codex / T-089 grok）

**grok（T-089，已完成）裁决**：

| 问 | 裁决 |
|---|---|
| Q1 | `session.message` 路径无完整机制（广播路径有相邻实现） |
| Q2 | 三选一 → **只改验收条件** |
| Q3 | 若硬要建：作用域 = **per connId**，不是 per-session |
| Q4 | **既不走上游也不扩 fork**；可选客户端侧弱对账 |

grok 另纠正一处：PR #118674 是 ModelCompatSchema 的事，**与投递序号无关**——主会话在 brief 里把它当作「上游响应速度」的证据，严格说是另一话题的样本。

**codex（T-088）**：首次派发因 `adapter-timeout` 失败（基线上限 300s，实际跑到 495s 被砍），已加大上限重派，结果待记。

## 5. 待用户裁决

本文件只做事实澄清，**不替用户决定**。三条路仍然是：
1. 改 RAE-0001 条件③ 措辞（grok 推荐；成本最低）
2. 向上游提「把 per-connection seq 扩到 targeted 投递」——**现在知道这是扩展既有机制而非新增概念，提案成本显著低于先前估计**
3. 先在 fork 自行实现（维护成本：每次 rebase 上游）
