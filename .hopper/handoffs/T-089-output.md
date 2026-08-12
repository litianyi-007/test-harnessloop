---
task_id: T-089
adapter: grok
model: grok-4.5
status: done
verdict: PASS_WITH_NOTE
mode: background
task_type: code-review-adversarial
reviewed_subject: per-subscription delivery sequence / RAE-0001 condition ③ path adjudication
openclaw_head: c35df878
---

# T-089 · code-review-adversarial · per-subscription 投递序号（grok 轨，异构独立）

**Task-type**: `code-review-adversarial` · **只读，未改任何代码/文档/状态文件**  
**Vendor**: grok · 与 T-088 同 brief、互不可见  
**Assumption (1 line)**: leader-tasklist T-088/T-089 合并 brief 为唯一完整规格；裁决只基于 `kernels/openclaw@c35df878` 源码 + rounds/0012 证据，不参照 T-088 产物。

---

## Summary

独立源码复核确认：主会话「`messageSeq` 不能证无丢帧、本层结构上不可断言」**成立**，但漏报了一层相邻机制——gateway **非 targeted 广播**已有 per-connection frame `seq` + 官方 client `onGap` 缺口检测。该机制对 **RAE 关心的 `session.message` 路径无效**（该路径走 `broadcastToConnIds`，**故意不带 frame `seq`**，且 `dropIfSlow: true` 静默丢弃）。**Q1 结论：没有现成的、能闭合「无丢帧」的机制。** **Q2 正确路径是改 RAE-0001 条件③ 措辞（承认本层测不了丢帧）**，不是在 fork 上新建投递序号，也不是本项目主线去修 openclaw 服务端可靠性。Q3/Q4 仅作若强行建设时的形状与路径，**不推荐现在建设**。

## Files touched

none（只读评审）

## Acceptance verification (4/4)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| Q1 | 自搜 openclaw 是否已有 cursor/watermark/replay/gap/恢复；若有则废 Q2–Q4 | **PASS（无完整机制；有相邻半成品）** | 见 Q1；`server-broadcast.ts:157-268`、`protocol-client.ts:546-552`、`server-session-events.ts:186-260`、`session-history-state.ts:84-152` |
| Q2 | 在「无现成机制」下三选一明确裁决，不和稀泥 | **PASS** | **只改验收条件**（见 Q2） |
| Q3 | 若建则给作用域/协议/兼容/测试形状；扇出下作用域必须说清 | **PASS（条件方案）** | 见 Q3；作用域 = **per connId（连接级 frame 序）**，不是 per-session |
| Q4 | 上游 PR vs fork vs 第三路，给明确建议 | **PASS** | **都不建投递序号**；改条件③；可选客户端/对账弱检测（见 Q4）。PR #118674 = ModelCompatSchema，与投递序号无关 |

### 主会话「已核实事实」独立复核

| 事实 | 主会话声称 | 独立复核 |
|------|------------|----------|
| 1 无订阅者静默丢 | `server-session-events.ts:178-188` early `return` | **成立**（当前 `c35df878` 为 L178–188：先收集 connIds，`size===0` 则 return；**在 messageSeq 计算之前**，故无排队/无重放/无落痕） |
| 2a D2 `seq` 是 client 本地计数 | kernel-client `nextSeq()` | **成立**（`OpenclawGatewayKernelClient.swift` F3 / `nextSeq`；结构上不可能因 wire 丢帧而出现空洞） |
| 2b wire `messageSeq` = transcript 行号/计数 | `server-session-events.ts:189-215` + `readSessionMessageCountAsync` | **成立**；注释原文 *「cursor-compatible live history」*（L191–192） |
| 3 订阅竞态 / `void` 无串行 | `message-handler.ts:475-479` | **成立**（`socket.on("message", … void runWithDiagnosticTraceContext…)` 于 `server/ws-connection/message-handler.ts:475-479`） |
| 4 fork + PR #118674 OPEN | submodule fork / 上游 PR | **成立**：HEAD `c35df878`，remote `litianyi-007/openclaw`；PR **#118674 OPEN**（created 2026-08-03）——但标题是 **ModelCompatSchema 八键漂移**，**不是**投递序号 PR |

---

## Q1 裁决：**没有能解决「无丢帧」的现成机制**

**优先级最高问：主会话是否漏找了？**  
答：**漏找了相邻机制，但那些机制仍然解决不了 RAE-0001 条件③ 的「无丢帧」。** 因此 **Q2–Q4 不废**，但必须把相邻机制写进事实基线，避免第三次「说没有实际有」。

### 1.1 已存在、但**不是**投递序号的东西

#### A. `payload.messageSeq`（transcript watermark）

- 赋值与回落：`kernels/openclaw/src/gateway/server-session-events.ts:189-215`
- 语义：transcript 消息计数 / 行号；缺省时 `readSessionMessageCountAsync`
- 注释（L191–192）：*fall back to the current transcript line count for **cursor-compatible live history***
- **不能**证「本订阅收到了几条」：未投递/不展示/系统行可合法占号；实测亦允许同号重复（`item3-messageseq.md`：`1,1,2,3,3,4,5,6`）
- **单调非递减**可写（乱序）；**无缺口**不可写（丢帧）

#### B. History `cursor`（「那个 cursor」是什么？）

- HTTP `/sessions/:key/history` 与 SSE：`sessions-history-http.ts`；游标解析 `session-history-state.ts:84-152`
- `cursor` / `seq:N` 指向 **transcript sequence watermark**
- 分页语义写死为（L129–130）：*「Cursors point at transcript sequence watermarks. The returned page is the window **before** that cursor, matching **older messages** pagination.」*
- **用途**：拉更早历史，或让 live `messageSeq` 与 history 分页对齐（故名 cursor-compatible）
- **不能**用来「补齐丢失的 WS 投递区间」：
  1. 无「from deliverySeq replay buffer」
  2. history 是 **展示投影后的 transcript**，不是 wire 上每一帧 agent/tool 流的完整重放
  3. 即使事后对账，也只能近似核对「最终进 transcript 的消息」，覆盖不了中间流式帧、被 `dropIfSlow` 丢掉的 live 事件

#### C. 连接级 frame `seq` + `onGap`（主会话未写清的相邻机制）

**服务端** `server-broadcast.ts:157-268`：

```text
clientSeq: WeakMap<GatewayWsClient, number>   // per-connection
nextSeq = (clientSeq.get(c) ?? 0) + 1
eventSeq = isTargeted ? undefined : nextSeq   // ★ targeted 故意不带 seq
```

- **非 targeted** `broadcast(...)`：每连接递增 frame `seq`，客户端可做 gap 检测
- **targeted** `broadcastToConnIds(...)`：`eventSeq = undefined`，**整条路径无 frame 序**

**`session.message` 走哪条？** — **targeted + dropIfSlow**（`server-session-events.ts:248-260`）：

```ts
params.broadcastToConnIds("session.message", { … messageSeq … }, connIds, { dropIfSlow: true });
```

因此：

| 路径 | frame `seq`？ | dropIfSlow 丢弃时是否推进序号？ | 客户端能否检出 |
|------|---------------|----------------------------------|----------------|
| `session.message` / 多数 targeted | **无** | targeted 分支丢弃时 **不** 写 `clientSeq`（L242–246） | **不能** |
| 默认 `agent`/`chat`（`broadcast` + sessionKeys） | **有** per-conn | 丢弃时 **会** 推进 `clientSeq`（L243–245） | **能检出 gap**（若客户端接 `onGap`） |
| 无订阅者 early return | 根本不广播 | n/a | **不能**（事件从未编号） |

**官方 client 缺口检测** `packages/gateway-client/src/protocol-client.ts:546-552`：

```ts
if (this.lastSeq !== null && seq > this.lastSeq + 1) {
  this.opts.onGap?.({ expected, received: seq });
}
this.lastSeq = seq;
```

- 只 **通知** gap，**不重传、不补历史**
- README 亦写 *sequence-gap detection*，无 replay 承诺

**本仓 Swift kernel-client**：解析 event 时 **不消费 frame `seq`**，不实现 `onGap`；D2 `.seq` 全是本地 `nextSeq()`。即便 agent 路径 wire 上有 frame `seq`，**当前客户端也没用**。

#### D. Agent payload 内的 `seq`

- `infra/agent-events.ts:627`：`seq: nextSeq` 是 **producer/run 侧** 事件序，随 payload 广播
- **不是**「投递给某订阅者的第几条」；未订阅时同样不投递、不占投递号

#### E. 其它叫 replay 的东西

- 仓库内大量 `replay` 指 **node 会话/媒体/restart sentinel/审批** 等，**不是** WS 订阅事件丢失后的重放缓冲
- 未找到 delivery buffer / redeliver missed gateway events / subscription recovery watermark API

### 1.2 Q1 一句话

> openclaw **有** transcript 游标（`messageSeq`/`cursor`）和 **非 targeted** 连接级 frame 序 + gap **检测回调**；**没有** per-subscription 投递序号、**没有** 丢帧重放、**没有** 订阅恢复。  
> RAE 主路径 `session.message` **被故意做成 targeted 无 frame seq + dropIfSlow 静默丢**。  
> **现成机制不能闭合「无丢帧」。Q2–Q4 继续。**

---

## Q2 裁决：**正确路径 = 只改验收条件（第三项）**

在 Q1 无完整机制前提下，三选一：

| 选项 | 裁决 | 理由 |
|------|------|------|
| 建投递序号 → 客户端检出丢帧 | **否（本项目现在不做）** | 检出 ≠ 不丢；协议扩展+双端+测试成本高；对象是第三方内核；**偏离「验证三插件」目的** |
| 改服务端不丢（修竞态/确认/重放） | **产品正确但非本项目主路径** | `void` 并发与 no-subscriber drop 是真问题；修它是 **openclaw 可靠性工程**，不是 harnessloop/hopper/kata 验证闭环的必要步骤；工作量与维护面远大于改一行 RAE 措辞 |
| **什么都不建，只改 RAE-0001 条件③** | **是（唯一正确的默认）** | 与 2026-08-09 条件①「录屏→截图」同形：**显式改契约**，承认可测边界；成本≈0；诚实，不把「结构不可满足」拖成永久 fail 或伪造断言 |

### 反方三条的独立判定

1. **「该做不丢而不是丢了能发现」**  
   产品视角成立；**项目视角不成立为阻断**。AgentShell/L1 是验证载体，不是交付商业内核。把 openclaw 做成可靠消息总线超出 goal 002 L1 与插件验证目的。

2. **「第三方内核可观测性扩展是否越界」**  
   **越界（对本仓默认目的）**。fork 上已有 per-session 补丁与 OPEN 的 config PR，再加协议字段 = 持续 rebase 税。除非用户把目标改成「产品化 AgentShell + 自维内核」，否则不应开这条线。

3. **「直接改条件③」**  
   **成立**。`decision.md` 已把「无丢帧」标为 `human-decision-required` 且未在验收时私自改标准——纪律正确。本评审建议用户在三条里 **选改措辞**。

### 推荐的条件③ 改写方向（供用户确认，本任务不改文件）

保持可机器检查的部分，删掉结构不可满足的部分，例如：

- **保留**：无乱序——wire `messageSeq` 单调非递减（已有断言 + 破坏性反证）；D2 事件本地 `seq` 不倒退（回归守卫，**不**冒充丢帧证据）
- **删除/降级**：「无丢帧」→ **已知缺口 / out-of-layer**：openclaw 对 `session.message` 为 best-effort targeted 投递（无 per-sub 投递序、无重放）；不在 L1 声称可证伪丢帧
- **可选弱增强（非必须）**：run 结束后对 `chat.history`/transcript 与观察到的 assistant `messageSeq` 做 **事后对账**（只覆盖最终进 transcript 的消息，**明确不覆盖** 流式中间帧与 dropIfSlow）

---

## Q3 若强行建：形状（不推荐，仅闭合 brief）

**作用域：per WebSocket connection（`connId` / `GatewayWsClient`），不是 per-session，也不是全局。**

| 错误作用域 | 为什么错 |
|------------|----------|
| 全局递增 | 多连接、多会话混流；空洞无法归因 |
| 仅 per-session | 同一 `sessionKey` **扇出多个 connId**（`server-session-events.ts:178-185` + `broadcastToConnIds`）；A 连接丢了、B 连接收到时，session 级序号仍连续 → **假绿** |
| per (session × conn) 投递号 | 正确但更重；对单订阅读者与「连接级 frame 序」几乎同效 |

**更小、且与现网协议同构的做法**（若一定要动内核）：

1. **改 `server-broadcast.ts`**：targeted 路径也写 `clientSeq` 并附 frame `"seq"`；`dropIfSlow` 丢弃时同样推进序号（与非 targeted 对称）  
   - 这样 **不引入新字段名**，官方 `onGap` 语义立刻覆盖 `session.message`  
   - 兼容：老客户端忽略未知/已有可选 `seq`（协议已允许 event 带 `seq`）  
2. **Swift kernel-client**：跟踪 frame `seq`，gap → 日志/断言失败（检测），**仍无重放**  
3. **测试**：  
   - 单测 broadcaster：targeted + dropIfSlow 时序号仍递增、对端见 gap  
   - 双连接同 session：各自独立序号，互不干扰  
   - 无订阅者：仍无序号（事件未进入 broadcast）——**检测仍覆盖不了「订阅前丢失」**；那要 **订阅确认屏障 + 服务端串行** 或 **subscribe 后 history 快照**  
4. **重连**：frame `seq` 随连接生命周期；重连归零；要跨重连必须另建 durable watermark + history 补洞（又回到 transcript 层，不是 live 帧）

**结论**：即便做成「连接级 frame 序覆盖 targeted」，也只得到 **丢帧可观测**，得不到 **不丢**；订阅前窗口与无订阅者丢弃仍在。对 RAE「无丢帧」字面，**检测方案永远不够**，除非把条件改成「可检测 gap 时必须红」。

---

## Q4 裁决：**不要为投递序号走上游 PR，也不要为它扩 fork；第三路优先**

| 路径 | 建议 |
|------|------|
| 上游 PR 新增协议字段 / 改 broadcast 序号语义 | **不作为本项目下一步**。#118674 已说明「小、有 proof、ready」仍可 OPEN 多日；**投递序/可靠性** 类 PR 更重、更易被要求 issue 先讨论、接受概率不确定。若将来产品化再开 **issue 陈述 silent drop + targeted 无 seq**，附最小 repro |
| fork 自维投递序 | **否**。已有 fork pin（`c35df878`）维护 per-session 等补丁；再叠协议行为 = 每次上游 rebase 回归面。**项目目的是验三插件**，openclaw 只是载体之一（hermes 等并排） |
| **第三路（推荐组合）** | ① **改 RAE-0001 条件③**（主路径，user-confirmed）② 登记 openclaw 服务端竞态/`dropIfSlow`/no-subscriber 为 **known kernel limitation**（不阻塞 L1）③ 可选：history 事后对账作 **弱、有界** 诊断 ④ **不** 在 kernel-client 伪造投递序 |

**#118674 澄清**：该 PR 是 config schema 漂移修复，**不能**当作「投递序号已在上游排队」的证据；只能当作「上游合入节奏不可控」的旁证。

---

## Decisions / deviations

1. **未顺着主会话直接设计「per-subscription 投递序号」**——Q1 优先；结论是改验收条件。  
2. **补充主会话未写清的 frame `seq`/`onGap`**——这是「说没有实际有」类风险点，但 **不改变**「session.message 路径仍不可证无丢帧」的结论。  
3. **未把「修服务端不丢」列为 L1 阻断修复**——产品正确 ≠ 本仓库当前正确优先级。  
4. 未读取 / 未对照 T-088 产物（brief 要求互不可见）。

## Open questions

1. 用户是否确认条件③改写文案（本任务只给方向，不落盘改 `data-sources.md` / evals）。  
2. AgentShell 若未来产品化，是否单独立项「openclaw 投递可靠性」（串行 subscribe、取消 targeted 去 seq、或 durable replay）——**超出 T-089 范围**。  
3. 条件③ 若改成「可检测 gap 必须红」，是否愿意 **最小改 broadcast 给 targeted 补 frame seq + Swift onGap**（仍非「无丢帧」字面，而是「有序可观测」）——可选，非默认。

## Verdict

**PASS_WITH_NOTE**

- **PASS**：四问均有明确、可源码锚定的裁决；主会话核心事实（messageSeq 非投递序、无订阅者静默丢、void 竞态、本层不能证无丢帧）经独立复核成立；推荐路径单一且可执行（改条件③）。  
- **NOTE**：主会话表述「openclaw 不提供投递序号」对 **per-subscription / session.message** 成立，但对 **全 gateway** 略绝对——存在非 targeted 的 per-connection frame `seq` + `onGap`；须写入事实基线以免被下次评审用「又漏了」打回。该 NOTE **不** 推翻「不要现在建投递序号 / 应改验收条件」。

## Next recommendation

1. **用户裁决（唯一阻塞）**：按 Q2 改写 RAE-0001 条件③ / `data-sources.md` / 相关 scope 措辞为「无乱序可断言 + 丢帧为本层已知缺口」，然后重跑/重记 RAE outcome（或标记 condition 修订后的 pass 规则）。  
2. **不要** 开 T-xxx 去实现 per-subscription 投递序号或扩 fork 协议。  
3. **不要** 等 #118674 或新上游 PR 来解锁 L1。  
4. 服务端 `void` 竞态与 silent drop 保持 **登记 known limitation**；若以后产品化再单独立项。  
5. 可选文档债：在 `item3-messageseq.md` / decision 事实表补一行「frame `seq` 存在但 targeted/`session.message` 不适用」，防止第三次漏找。
