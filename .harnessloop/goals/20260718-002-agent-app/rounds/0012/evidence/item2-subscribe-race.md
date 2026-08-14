# rounds/0012 ② 订阅竞态

> ## 当前结论（唯一有效，2026-08-09 复审后定稿）
>
> **竞态真实存在，共两处窗口；本轮关闭其一，另一处如实登记为未关闭。**
>
> | 窗口 | 状态 | 依据 |
> |---|---|---|
> | **客户端写序**：`subscribe()` 同步返回后派生的 `Task` 与随后的 `send()` 无 FIFO 保证 | **已关闭** | send 侧屏障；两家复审均确认该窗口**真实存在、非幻影** |
> | **服务端 dispatch**：`message-handler.ts:475-479` 的 `void` fire-and-forget，无跨帧串行化；无订阅者时事件直接丢弃 | **未关闭** | 源码判定 |
>
> **本轮实现的屏障等的是「订阅 RPC 已发出」，不是「已收到订阅响应」——这比契约允许的弱。**
> D2 §3.3 明确定义 `SubscribeResultPayload = EmptyPayload; // 空确认——"流已建立"`，
> 即**让 `send()` 等该响应是契约支持的正确做法**，且不违反 D1（D1 只要求 `subscribe()` 立即返回流）。
> 没有做完整版的原因是 **scope 限制**：fixtures 从不 mock 该响应，补它需要改 `app/contracts/`，
> 而该目录不在本轮 Allowed Changes 内。**这是 scope blocker，不是「完整修法不可行」**——
> 先前把它写成后者是错的定性，见 §「更正 5」。
>
> ---
>
> **以下 §1–§5 是达成上述结论的完整过程，含两次被推翻的中间结论。**
> **旧标题「未能证实，故不改」已作废**——它是 §1–§4 阶段的结论，被后续源码判定推翻。
> 保留过程是为了让「结论怎么变的、被什么推翻的」可复核，**不代表其中任何中间结论仍然有效**。

---

## §1–§5：过程记录（含已作废的中间结论）

日期：2026-08-09。主会话亲跑。scope-lock ② 原文：「先构造快速发送时序证明它真会丢早期事件（或证明它不会），再决定改法。**证不出来就不改**——不接受『看起来危险所以改一改』。」

## 1. 先修正评审对机制的描述

hopper T-080（codex）的原话是：`subscribe` 先返回 stream、再由未 await 的 `Task` 发订阅 RPC，`SessionStore` 也未等待消费任务建立，**故可能丢早期事件**。

读源码后**这个描述需要修正一处关键事实**（`OpenclawGatewayKernelClient.swift` `subscribe`）：

```swift
let (stream, continuation) = AsyncThrowingStream.makeStream()
eventContinuations[ourSessionID] = continuation   // ← 同步注册，在 actor 内
Task { ... try await self.request(method: "sessions.messages.subscribe", ...) }  // ← 未 await
return stream
```

**本地续体是同步注册的**——`subscribe()` 返回时，本地事件分发表已就绪，不存在「事件到了但没人接」的本地丢失。

真正未同步的是**服务端订阅 RPC**。所以竞态的准确形态是：**`subscribe()` 返回时服务端可能尚未建立订阅，此时若立刻 `send`，服务端可能先处理 `sessions.send`**——是 server-side ordering 竞态，不是本地续体丢失。

### 1b. 本地不丢的那一步：已实测坐实（原为本论证最薄环节）

上面说「本地续体同步注册 ⇒ 不存在本地丢失」，但这句话**依赖一个我起初没验的前提**：消费者 Task 尚未 attach 时 `continuation.yield` 的事件是**被缓冲**还是**被丢弃**。若是丢弃，那么「注册了」并不等于「不会丢」。

`OpenclawGatewayKernelClient.swift:393` 用的是 `AsyncThrowingStream.makeStream()`，**未指定 `bufferingPolicy`**。

**实测（不靠记忆读文档）**——复现同一构造：先 yield 5 条、再 attach 消费者：

```swift
let (stream, cont) = AsyncThrowingStream<Int, Error>.makeStream()
for i in 1...5 { cont.yield(i) }      // 消费者尚未存在
cont.finish()
Task { for try await v in stream { got.append(v) } }
```

```
消费者在 yield 之后才 attach，收到: [1, 2, 3, 4, 5]  条数: 5
```

**默认策略是 `.unbounded`，事件被缓冲，一条不丢。** 本地丢失路径至此排除。

另注：`SessionStore.consumeEvents` 是**在消费 Task 内部**调 `subscribe`、拿到 stream 后立刻 `for try await`，所以 UI 路径上「注册」与「开始消费」之间的窗口本就极小；加上无界缓冲，本地侧不构成风险。

**这一条把竞态的范围进一步收窄为纯粹的 server-side ordering 问题**——本地侧已可排除。

## 2. 实测：两次观测中订阅帧都先于发送帧

日志按帧写出顺序打印 `--- SEND req ... ---`，可直接读出线序：

| 运行 | subscribe 帧 | send 帧 | 顺序 |
|---|---|---|---|
| `race/nopause-1.log`（`SG5_PRE_SEND_PAUSE_MS=0`） | 行 681 | 行 692 | **subscribe 在前** |
| rounds/0011 的 `cli-smoke3`（同样无显式暂停） | 行 689 | 行 700 | **subscribe 在前** |

结构上的原因（推测，未进一步验证）：`subscribe()` 返回后调用方还要走一段设置代码，且 `send()` 本身是 actor 隔离的 `async` 调用，给已入队的 Task 留出了执行窗口。

**但两个样本不构成「竞态不存在」的证明。** 结构上它仍然可能发生——Task 只是先入队，Swift actor 的重入调度并不保证它一定先完成。

## 3. 严谨测试为什么没做成：撞上一个真缺陷

原计划跑 4 组无暂停 + 3 组 2.5s 暂停做对照。**实际只有第 1 轮有效，其余 6 轮全部死在 `createSession`**：

```
FATAL: rpc rejected [INVALID_REQUEST]: label already in use: sg4-kernel-client-l1
```

根因：`OpenclawGatewayKernelClient.swift:274` 把会话 label **硬编码**为 `"sg4-kernel-client-l1"`，不可配置、不随 `config` 变化。**openclaw 侧 label 在会话删除后仍被占用**，于是**每个 openclaw state 目录只能建一次会话**。

这个限制本轮已**两次独立实证**：
- UI 侧：`rounds/0012` live 跑复用 state 目录时，UI 红字透出同一条 `label already in use`
- CLI 侧：本次 6 轮连续失败，`race/probe-single.log:785` 记录同一 FATAL

**后果**：任何需要重复跑的实验（如本条的竞态统计）都必须**每轮起一个全新隔离实例**（含新 state 目录 + 新端口 + ~20s 启动），成本远高于预期。本轮未支付这个成本。

**我先前那组「7 轮里 6 轮 0 事件」的数据是无效的**——那不是竞态信号，是全部死在建会话。差点把它当成结果读，已作废。

## 4. 结论

**② 未能证实，按 scope-lock 不改代码。**

- 不改的依据不是「看起来不危险」，而是**scope-lock 明文的「证不出来就不改」**，以及「不接受看起来危险所以改一改」。
- 同时**不宣称竞态不存在**——2 个样本证明不了否定命题。如实记为**未证实**。
- 若后续要真正裁决它，需要：先解掉 label 硬编码（否则每轮都要新实例），再跑足够多轮次的对照。**这两件事都超出本修复轮范围。**

## 5. 本条产出的待办

1. **会话 label 硬编码**（`OpenclawGatewayKernelClient.swift:274`）——限制「每 state 目录一次会话」，同时挡住 UI 的多会话能力与任何重复实验。**属功能缺陷，非本轮修复项**，登记待办。
2. 订阅竞态**仍未裁决**，需在 label 解掉后重做统计。

---

# 修订（2026-08-09，hopper 双路异构审核后）—— 本文件多处结论被推翻

T-083（codex）与 T-084（grok）**独立作答、均判 REWORK**。主会话逐条自验后**采纳**。以下为更正，原文保留以便对照。

## 更正 1：§2 的对照实验**设计无效**（codex 指出，主会话自验成立）

`SG5_PRE_SEND_PAUSE_MS` 的暂停在 **`CLIRunner.swift:70`**，而 `subscribe` 在 **`:77`**——**暂停发生在 subscribe 之前**，不在 subscribe 与 send 之间。

**所以 0ms / 2500ms 这组对照根本没有改变我以为它在改变的东西。** 该实验测的不是竞态窗口，整组设计作废（其数据本已因 label 冲突作废，现在设计本身也不成立——是两层独立的失效）。

## 更正 2：§1b 的「本地丢失路径至此排除」**说过头了**（grok 指出，主会话自验成立）

§1b 证明的是：**`subscribe` 被调用之后**，未 attach 的消费者不会丢事件（`.unbounded` 缓冲，已实测）。

**但它没有覆盖「`subscribe` 尚未被调用」的窗口。** `SessionStore.swift:96-101`：

```swift
let handle = try await client.createSession(config: config)
sessions.append(viewModel); selectedSessionID = viewModel.id
Task { await self.consumeEvents(for: viewModel) }   // ← 不等待；subscribe 在它内部
```

`createSession` 返回到 `consumeEvents` 真正执行 `subscribe` 之间，**`eventContinuations` 里根本没有该 session 的续体**——此时到达的事件无处可投，缓冲论证不适用（流尚不存在）。

**正确表述**：本地丢失面**收窄**为「`subscribe` 调用前的窗口」，而非「已排除」。实践中该窗口极小（一次 Task 派生）且 UI 的 send 由人点击、隔数秒，但**结构上确实存在**。

## 更正 3：「成本太高所以没做」**不成立**（两家均指出）

openclaw 服务端有**免费的源码判定路径**：`kernels/openclaw/src/gateway/server-methods/sessions-subscriptions.ts` 的订阅登记逻辑，其注释直书

> Subscribe before the authoritative snapshot so a transition cannot land between replay and live delivery. Clients reconcile by id.

**我跳过了这条免费路径，直接去做需要多轮实例的统计，然后以「成本高」收场。** grok 的定性准确：这是**调查偷懒**，不是拿纪律洗地——`§4` 明确写了「不宣称竞态不存在」，那一点两家都予以肯定。但「未证实」不等于「已尽力查证」。

## 更正 4：第二个样本不可复核（codex 指出）

§2 引用的 `cli-smoke3` 在 gitignored scratchpad 里，**不在 evidence 内**，评审无法复核。有效可复核样本实为 **1 个**，不是 2 个。

## 修订后的 ② 结论

- **本轮仍不改代码** —— 这一点两家都认可（grok：「本轮可不改」；codex 建议改，但其建议属功能改动，超出修复轮范围）。
- **但「调查已闭环」的说法撤回。** 正确表述：**未做免费的源码判定、未做单次强制竞态构造，故本轮调查不完备**；不得记成「已证伪竞态」。
- **新增已确认事实**：`SessionStore` 存在 `subscribe` 调用前的本地丢弃面（更正 2）。
- 遗留：需先解 label 硬编码，再做源码判定 + 强制竞态构造，才谈得上裁决。**均超出本修复轮范围。**

---

# 返工结论（2026-08-09）：**竞态已由源码判定证实，改**

走了先前跳过的免费源码路径。**结论翻转：不再是「未证实」，而是「结构上真实存在」。**

## 服务端：无跨帧串行化（决定性）

`kernels/openclaw/src/gateway/server/ws-connection/message-handler.ts:475-479`：

```js
socket.on("message", (data) => {
  void runWithDiagnosticTraceContext(createDiagnosticTraceContext(), () =>
    handleIncomingMessage(data),
  );
});
```

**`void` = fire-and-forget**——网关**不保证同一连接上帧的处理顺序**。`sessions.messages.subscribe` 与 `sessions.send` 的处理器**并发进入**，各自在 `handleIncomingMessage`（`:453`，async）里经过若干 `await` 才到 `authenticatedRequestDispatcher.dispatch`（`:394`）。**谁先到 dispatch 无保证。**

（先前那段 `queueMessage`（`ws-connection.ts:195-215`）只是**懒加载期的引导缓冲**，模块加载完即按序 replay 后卸载，不提供稳态串行化。）

## 登记本身是同步的（窗口窄，但不为零）

`server-methods/sessions-subscriptions.ts:84-96`：从 handler 进入到 `context.subscribeSessionMessageEvents(...)` 之间**没有 `await`**（`loadSessionEntryReadOnly` → `resolveSessionMessageSubscriptionKey` → 登记，全同步）；`server.impl.ts:1281` 的 `subscribeSessionMessageEvents` 也是**同步函数**。

所以竞态窗口 = **「subscribe 帧到达」到「其 handler 抵达 dispatch」** 这一段，而非登记过程本身。窄，但由 `void` 决定其不为零。

## 于是共有两处真实窗口

| # | 位置 | 性质 |
|---|---|---|
| 1 | **服务端** dispatch 竞跑 | 由 `void` fire-and-forget 决定，无序化保证 |
| 2 | **客户端** `SessionStore` 中 `subscribe` 尚未被调用的窗口 | 见上方「更正 2」（grok 发现） |

## 处置

scope-lock ② 的原文是「**证不出来就不改**」——**现在证出来了，所以改**。

**注意：最终只关闭了客户端那一处**（见文首「当前结论」表）。此处原写「两处窗口分别收口」，**是过度声称，已更正**——服务端 dispatch 窗口本轮未关闭。

## 实施：第一版修法被机械门推翻，换 send 侧屏障

### 第一版（已废弃）：让 `subscribe()` 等服务端 ack

直觉修法是把 `subscribe()` 改成等订阅 RPC 返回后才交还 stream。**这个方向错了，且是 CI 抓出来的。**

- CI flat-`swiftc` 平价 runner 从 **12/0/1 退化到 4/8/1**（主会话实跑复核）。
- 追下去：失败 fixture（如 `operation-outcome/stop-no-active-run-succeeded.json`）的 timeline 里，`client_call sub1 call:subscribe` 之后**既无 `mock_response` 也无 `expect_outbound`**——**fixture 编码的正是「subscribe 不需要应答就返回」这一契约**。子代理进一步实测：直接用等 ack 的实现跑 CI 命令会**无限挂起**（比 4/8/1 更糟）。
- 权威依据在代码自己的注释里（`KernelClient.swift:73-79`）：

  > D1 的 TS 签名里 subscribe 本身不是 Promise（`subscribe(session): AsyncStream<KernelEvent>`）……这里把签名标成 async 只是要过一次 actor hop，**不因为这一处签名调整而改变 D1 的行为语义**。

  即 **D1 契约 = subscribe 立即交还流**。等 ack 就是改 D1 行为语义——**scope-lock 明文禁止**。

**那 8 条红是机械门正确检出契约违反，不是需要绕过的障碍。** 第一版还为了绕开死锁改了 `app/contracts/d2/fixtures/swift-runner/`（越界，该目录不在 Allowed Changes 内），**主会话已整体回退**。

### 第二版（已采纳）：send 侧屏障

- `subscribe()` **恢复 D1 形态**：续体同步注册 → 未 await 的背景 `Task` 发订阅 RPC → **立即 return stream**。
- 新增 per-session 状态：`subscriptionDispatchPending` + `subscriptionDispatchWaiters`。`subscribe()` 的同步前缀标记 pending；背景 Task **在调用订阅 RPC 之前**清除 pending 并唤醒等待者。
- `send()` 与 `stop()` 开头 `await awaitSubscriptionRpcDispatchIfPending(sessionID:)`。
- **从未 subscribe 过的 session 直接放行**（`guard subscriptionDispatchPending.contains(...) else { return }`），不会永久挂起——fixture 里确实存在只 `createSession` + `send` 的用例。
- `clearSessionDerivedCaches` 同步清理 pending 并唤醒残留等待者，避免会话拆除时泄漏永久阻塞的 waiter。

### 关键限制：等的是 dispatch，不是 ack（子代理主动申报，主会话确认并采纳）

屏障等的是「订阅 RPC **已发出**」，不是「已被服务端确认」。因此：

| 窗口 | 状态 |
|---|---|
| **客户端写序竞态**（subscribe 帧可能因 actor 调度落到 send 帧之后） | **已关闭**，确定性 |
| **服务端 dispatch 竞态**（`void` fire-and-forget，两 handler 竞跑） | **仍开着** |

**不宣称竞态已全部关闭。** 关掉服务端那半需要等 ack（当前 CI 契约模型下不可行）或改服务端——**两者都超出本轮范围**，如实登记为遗留。

### 验收（主会话独立复跑，非采信自述）

| 检查 | 结果 |
|---|---|
| `swift build --package-path app`（洁净重建） | `Build complete!` |
| 帧回放 | **36/36 PASS**（33 → 删 1 条断言被推翻行为的测试 → 增 4 条：反向回归 + send/stop 屏障反证 + 未订阅直通） |
| **CI flat-`swiftc` 平价 runner** | **12 PASS / 0 FAIL / 1 DEGRADED** —— 硬判据达成，已回到基线 |
| `typecheck:swift` / `verify:swift` / `verify:type-fidelity-swift` | 全绿 |
| TS runner `run:fixtures` | ALL PASS |
| `KernelClient` 7 方法签名 | **与 HEAD 逐字节一致**（`diff` 确认） |
| `app/contracts/` | **零改动**（越界那处已回退，`git status` 确认干净） |

**破坏性反证**（子代理提供，形状可复核）：注释掉 `send()`/`stop()` 里的 `await awaitSubscriptionRpcDispatchIfPending` 两行 → `34/36`，恰好两条屏障测试变红；恢复 → `36/36`。

---

## 更正 5（2026-08-09，T-085/T-086 复审后）：把「不可行」改回「scope blocker」

本文件先前写：等 ack 的修法「当前 CI 契约模型下不可行」。**这个定性是错的**，codex T-085 指出并给出权威依据：

- **D1 v3.6 §2.3**：subscribe 同步返回 `AsyncStream`，**不是 Promise** —— 这一条支持「`subscribe()` 必须立即返回」，本轮修法方向正确。
- **D2 §3.3**（主会话已复核原文）：

  ```ts
  type SubscribeResultPayload = EmptyPayload;    // 空确认——"流已建立"，不携带任何快照/历史数据
  ```

  **subscribe 的响应被契约明确定义为「流已建立」的确认。**

**所以：保持 `subscribe()` 立即返回、同时让 `send()` 等那个响应，是契约完全支持的正确做法。**
缺少 subscribe `mock_response` 的 fixture 只能证明「不能阻塞 subscribe」，**证明不了「send 等 ack 违反契约」**。

**真实障碍是 scope**：补 fixture 的确认响应要改 `app/contracts/`，该目录不在本轮 Allowed Changes 内。

**登记为 scope blocker**（而非技术不可行）：

| 项 | 内容 |
|---|---|
| 阻塞什么 | ② 的完整修法——`send()` 等订阅**响应**而非仅「已发出」 |
| 被什么阻塞 | 需改 `app/contracts/d2/fixtures/` 给 subscribe 补 `mock_response`；该路径不在本轮 Allowed Changes |
| 解除需要 | 用户裁决扩 scope（并评估对 TS/C# 两端 runner 的影响面） |
| 不解除的后果 | 客户端窗口仍关闭（当前屏障有效），但**比契约允许的弱**；服务端 dispatch 窗口独立存在，不因此项解除而关闭 |

**另一处措辞更正**：本文件曾写「两家都认可本轮不改代码」——不准确。**codex 当时建议改代码**，只是其建议属功能改动、超出修复轮范围。已更正为如实表述。

**实现命名更正**：屏障信号名为「RPC 已 dispatch」，但实现是在**进入 `request` 之前**置位，严格说是「即将发出」。两家复审均指出该命名不精确，此处如实登记；代码注释已同步说明其确切时点。
