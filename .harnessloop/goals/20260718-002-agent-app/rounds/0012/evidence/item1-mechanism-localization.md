# rounds/0012 ①③ 机制定位记录

scope-lock 要求「先定位真实机制，再动手改」。本文件是定位结果。**本轮尚未改动任何代码。**

执行者 = 主会话（只读调查）。数据源 = rounds/0011 遗留的运行日志（`scratchpad/shell-run.log` 3030 行、`cli-smoke{,2,3}.log`）+ 源码。

## 结论摘要

| 项 | 定位结果 |
|---|---|
| ① 分组机制 | **仍未定位**，且已排除两条错误路径（见 §1、§2）。定位需要一次带插桩的新跑 —— 因为**成功映射的帧在现有日志里完全不存在**（§3） |
| ③ seq 断言 | **已定位，且我先前对它的定性是错的**（§5）。断言本身没问题，**是我引用错了它守的东西**。正确修法也随之改变（§6） |

---

## 1. 排除路径一：`chat` 事件流与本议题无关

我最初提取并分析的是 `event: "chat"` 帧（28 条），从中得出「`message.content` 是累积量、delta 与 final 同路径」等结论。

**这条路径整条作废。** `OpenclawGatewayKernelClient.swift:1023-1037` 的分派 switch 只有四个 case：`session.message` / `agent` / `session.approval` / `shutdown`，其余落 `default: prettyPrint("...未处理的旁路事件，原样打印")`。日志里那 28 条 `chat` 帧的标题逐字就是这句——**它们从未进入映射**。

连带作废的还有：我先前记下的「wire seq 缺 5、8、9，可能是真丢帧」——那是 `chat` 旁路流的 seq，kernel-client 根本不消费它。

## 2. 排除路径二：`message` 层没有消息标识（结论正确，但查错了层）

我先前记「`message` 载荷没有 `id` 字段，无服务端消息标识可用」。`message.keys = ['__openclaw','content','idempotencyKey','role','timestamp']` —— 这句本身没错。

但**上一层有**。`session.message` 的 **`payload`** 带 `messageId` 与 `messageSeq`（实测 payload 键 40+ 个，两者在列）。我查的是 `message.*`，该查 `payload.*`。

## 3. 为什么①还定位不了：成功映射不留任何痕迹

`handleSessionMessageEvent`（`OpenclawGatewayKernelClient.swift:1074-1085`）的结构是：

```swift
let events = mapOpenclawSessionMessageToKernelEvents(...)
if events.isEmpty {
    prettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一）", frame)
    return
}
for event in events { ...; continuation.yield(event) }
```

**只有映射失败才打日志，成功路径完全静默。** 日志里 7 条 `session.message` 全部带着「未能映射」标题，且 `message.role` 全为 `user`（`mapOpenclawSessionMessageToKernelEvents` 在 `role != "assistant"` 时返回空数组——`EventMapping.swift:172-178`）。

所以：**承载 assistant 文本的那些帧，在现有日志里一条都没有。** 无法从中判断它们的 content 形状、是否累积、`index` 取值、以及为什么注入失败那次重复而成功那次不重复。

`messageSeq` 实测值 `1,1,3,3,5,5,7` 佐证同一结论：这些只是 user 帧，缺掉的偶数位正是成功映射因而未被记录的 assistant 帧。

**这本身是一处 diagnosability 缺陷**，直接关联 scope-lock 的 ⑤（证据自足）：客户端只记录失败帧，原始日志无法重建被消费的事件流。

## 4. ① 的下一步（不是修，是取证）

需要一次带插桩的跑：把**所有** `session.message` 帧（含成功映射的）原样落盘，再对照 UI 呈现。插桩方式待定（临时 prettyPrint / 独立 WS tap 二选一），但**必须能同时看到 wire 帧与它映射出的 D2 事件**，否则仍然对不上。

在此之前**不动分组代码**——scope-lock 明文：不得在未查清机制的情况下按推断改。

## 5. ③ 的定性纠正：断言没问题，是我引用错了

我在 rounds/0011 的判断是「`seq 单调` 是空断言」。**这个定性不准确，需要纠正。**

`EventMapping.swift:138-145` 与 `CLIRunner.swift:181-183` 记录了完整来历：

> D1 v3 §9.2/§3：`seq` 仅承诺"同一 runId 内排序"，不是全局单调、也不是 wire 帧外层 `seq`/`messageSeq` 的直接透传——**上一轮（a07dc67）在 `session.message` 用 `messageSeq`、在 `agent` 事件用 frame 外层 `seq`，两个域混用导致同一个 run 观察到 `2→21→4→30`（对抗审 T-044 F3 复现）**。rework 轮改为：每个 mapper 不再自己从 wire 读 seq，而是通过 `nextSeq` 闭包按 **runId 作用域**取号。

以及 `CLIRunner.swift` 对三条不变量的说明：「这三个不变量都不是随便定的，各自对应 EventMapping 文件头注释里记录的一处真实缺陷/契约点」，其中 seq 单调对应的正是 F3 那次 `2→21→4→30` 回归。

**所以：**

- 本地 `nextSeq()` **不是疏忽，是针对 T-044 评审发现做出的有意设计**。
- 「seq 单调」这条断言**忠实地守着它被设计来守的东西**（F3 回归：同一 run 内 seq 不得倒退）。它不是装饰。
- **错的是我**：我在 rounds/0011 的 round-summary 与证据文件里，把这条断言当成「无丢帧、无乱序」的证据引用。那不是它守的东西，D1 契约也从未让 `seq` 承担这个职责。

codex 的指控「seq 单调不能证明无丢帧」**结论正确**；但据此推出的「断言是空的、应换掉」**方向错了**。断言该留着。

## 6. ③ 的正确修法（据此改写）

不是「把 D2 `seq` 换成 wire 透传」——**那条路 a07dc67 走过，T-044 判它有害，不能重走**。

正确做法是**加一条独立的、不与 D2 `seq` 混域的丢帧检查**：

- 基准用 `session.message` 的 **`payload.messageSeq`**（会话级服务端序号，实测存在）
- 与 D2 `seq`（per-run 排序令牌）**分属两个域，各记各的，绝不互相赋值** —— 这正是 T-044 那次事故的根因
- 断言形态：会话级 `messageSeq` 的缺口必须有解释（本轮已知一种合法解释：assistant 帧与 user 帧交替占号）；无法解释的缺口即判丢帧

**破坏性反证仍是硬要求**：人为丢一帧，该检查必须变红。

**`messageId` / `messageSeq` 目前在全仓被读取 0 次**——三处提及（`CLIRunner.swift:182`、`EventMapping.swift:141`、`OpenclawGatewayKernelClient.swift:310`）**全是注释**，其中两处正是记录 a07dc67 那次失败。

## 7. 本次定位自身的教训

**在 30 分钟里我连续两次在错误对象上建立了完整分析**：先是错误的事件流（`chat` 而非 `session.message`），再是错误的字段层级（`message.*` 而非 `payload.*`）。两次都推进到了「看起来自洽、可以据此动手」的程度。

拦住它们的不是我的谨慎，是 scope-lock 里那条「先定位后动手」的硬要求，以及**代码里前人留下的注释**——如果 `EventMapping.swift:138-145` 没有记下 a07dc67/T-044 那次事故，我这一轮几乎必然会提出「把 seq 改成 messageSeq 透传」，重走一条已被判定有害的路。

这是「注释即制度记忆」的一个实例，值得记下来。
