# rounds/0012 ③ messageSeq —— 缺口成因查明，且推翻了先前的观测结论

日期：2026-08-09。主会话亲跑。

## 结论

**`messageSeq` 根本没有缺口。** 先前记录的「缺 3、5」是**观测偏差**，不是丢帧。

`messageSeq` 是**会话 transcript 的消息计数**（会话级索引），**不是「投递给本订阅者的第几条」**。因此：

- **「无缺口」不能作为丢帧断言**——即便真有缺口也可能完全合法。
- **`messageSeq` 单独无法检测丢帧。** 能写的有效断言是**单调非递减**（可捕获乱序），不是无缺口。

## 1. 源码判定（走的是 ② 教训里那条免费路径）

`kernels/openclaw/src/gateway/server-session-events.ts:189-215`：

```ts
let messageSeq = asPositiveSafeInteger(update.messageSeq);
if (messageSeq === undefined) {
  // Updates from raw transcript events may not carry seq; fall back to the
  // current transcript line count for cursor-compatible live history.
  ...
  messageSeq = ... await readSessionMessageCountAsync({ ... })
}
```

注释与 `readSessionMessageCountAsync` 共同坐实：**它是 transcript 侧的计数，服务于「cursor-compatible live history」**，与「本订阅收到了几条」无关。

**推论**：transcript 里存在但未以 `session.message` 投递给本订阅者的条目（系统行、工具结果、内部条目等）会占号，**缺口因此是合法的**。写「无缺口」断言必然误报——这正是 scope-lock ③ 写死「两种解释导出完全不同的断言，不许在没查清前二选一」的原因。

## 2. 实测数据：不但缺口合法，本轮压根没有缺口

带插桩的完整 `session.message` 序列（`evidence/raw/wire-trace.jsonl`）：

```
messageSeq=1  role=user       produced=0
messageSeq=1  role=user       produced=0   =持平
messageSeq=2  role=assistant  produced=1   ↑+1
messageSeq=3  role=user       produced=0   ↑+1
messageSeq=3  role=user       produced=0   =持平
messageSeq=4  role=assistant  produced=1   ↑+1
messageSeq=5  role=user       produced=0   ↑+1
messageSeq=6  role=assistant  produced=1   ↑+1
```

**1,1,2,3,3,4,5,6 —— 连续、无缺口、单调非递减，带合法重复**（每条 user 消息产生两帧，同一 transcript 计数）。

`evidence/live/repro-wire-trace.jsonl` 独立复现同一形态：`1,1,2`。

## 3. 纠正先前的错误结论

`instrumented-run-findings.md` §2 记的是「实测 `messageSeq` 序列 `1,1,3,3,5,5,7`，**缺口真实存在**（缺 3、5）」——**这个结论是错的，此处作废。**

**成因**：那次观测发生在**插桩存在之前**。当时 `handleSessionMessageEvent` **只在映射失败时打日志**（`events.isEmpty` 分支），于是日志里只有 `role=user` 的帧（映射器对非 assistant 返回空数组），**assistant 帧一条都不留痕**。我把「日志里没看见的号」当成了「缺失的号」。

补上插桩、看到完整序列后，缺的那些号**正是 assistant 帧**，它们一直都在。

**这与本轮反复出现的同一类错误同形**：`chat` 是错的事件流、`message.*` 是错的字段层级、「本地丢失已排除」说过头、「无手段隔离日志」是因为只搜了 env——**都是在不完整的观测面上得出确定结论**。

## 4. 可写的断言与不可写的断言

| 断言 | 可否 | 理由 |
|---|---|---|
| `messageSeq` **无缺口** | **不可** | transcript 侧计数，未投递条目合法占号 |
| `messageSeq` **单调非递减**（同一 session 内） | **可** | 捕获乱序；重复合法故不能用严格递增 |
| 用 `messageSeq` **检测丢帧** | **不可** | 该字段不承载「投递了几条」的信息，本层无此信号 |

**丢帧检测在本层做不到**——这是如实结论，不是暂缓。要做需要一个 per-subscription 的投递计数，openclaw 当前不提供。**登记为待办，不在本轮伪造一个做不到的断言。**

---

## 5. 实施：只加了那条能写的断言

`EventAssertionCollector`（`CLIRunner.swift`）新增**第 4 条不变量：wire `messageSeq` 单调非递减**。

**两域分离是这次实现的重点**（历史教训：`a07dc67` 混用两域导致 `2→21→4→30` 倒退，由对抗审 T-044 抓出）：

| | 断言 1 | 断言 4（新增） |
|---|---|---|
| 验的对象 | **D2 事件的 `.seq`** —— kernel-client 自己的 per-run 本地计数器 | **wire `payload.messageSeq`** —— openclaw 会话级 transcript 计数 |
| 状态字段 | `lastSeqByRunScope` / `seqViolations` | `lastMessageSeq` / `messageSeqViolationsStorage` |
| 能证伪什么 | 同 run 内 D2 seq 倒退（F3 回归） | wire 侧乱序 |

代码层面的分离手段：两组状态字段互不共享；`recordMessageSeq` 的文档注释点名引用 `EventMapping.swift:138-145` 与 `a07dc67` 事故；hook 签名是 `(Int) -> Void` 传裸整数、**不传 `EventMessageUnion`**，从类型上杜绝两域互相顶替。

`messageSeq` 的进入路径：`OpenclawGatewayKernelClient` 上加一个**非协议**的旁路 hook（`setWireMessageSeqObserver`），在 `handleSessionMessageEvent` 里**早于 `role=="assistant"` 过滤**触发——因为 `messageSeq` 在 user/assistant 帧上都有（实测序列本就是两种角色交替）。**未改 D2 schema、未改协议签名。**

### 验收（主会话独立复跑）

| 检查 | 结果 |
|---|---|
| 洁净重建 + 帧回放 | **38/38 PASS**（36 → +2：倒退检出、合法重复不误报） |
| CI flat-`swiftc` 平价 runner | **12 PASS / 0 FAIL / 1 DEGRADED** |
| `typecheck:swift` / `verify:swift` / `verify:type-fidelity-swift` / TS runner | 全绿 |
| 禁区（`app/contracts` / `app/generated` / `kernels` / `app/server` / `app/deploy` / `app/parity`） | **无新增改动** |

### 破坏性反证（主会话亲做，双向）

把判定改成恒不成立（`if let last = ..., false, messageSeq < last`）→ **37/38**，**恰好「倒退 1,2,1 必须变红」那条转红**；「合法序列 1,1,2,3,3,4,5,6 不误报」那条**仍绿**——证明后者不是靠同一个判定蒙混过关。复原后 38/38。

> 附一次过程失误：第一次破坏用的正则是 `seq < last`，与实际写法 `messageSeq < last` 不符，**未生效**，却跑出 38/38。若不打印实际代码行核对，就会把「没破坏成功」读成「破坏了也不红」。与本轮 §6.2 那次「空检查」同形，第二次才做对。

## 6. 未做，且不打算伪造

**丢帧检测在本层做不到。** `messageSeq` 不承载「投递了几条」的信息，openclaw 亦不提供 per-subscription 投递计数。**本轮不写一个做不到的断言充数**，登记为待办：要做需要内核侧提供投递序号，或客户端与 transcript 做一次全量对账。
