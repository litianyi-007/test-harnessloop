---
task_id: T-084
adapter: grok
model: grok-4.5
status: done
phase: done
adapter_status: success
exit_code: 0
---

# T-084 · code-review-adversarial · rounds/0012 ②⑥ 收尾前独立审核（grok 轨，异构独立）

**Task-type**: `code-review-adversarial` · **只读，未改任何代码/文档/状态文件**  
**Vendor**: grok · 与 T-083 同 brief、互不可见  
**Assumption (1 line)**: leader-tasklist T-083/T-084 为完整规格；只读指定证据/源码/race 日志，不参照 T-083 产物。

---

## Summary

对 rounds/0012 主会话就 **② 订阅竞态「未证实故不改」** 与 **⑥ L1-REPRO「无秘密可复现」** 的自利结论做了对抗审。机制修正（本地 continuation 同步注册）大体正确，且 `AsyncThrowingStream.makeStream` 默认 **unbounded** 缓冲，**不是**「消费 Task 还没起来就本地丢事件」；但主会话漏掉了 **SessionStore 在 `subscribe` 调用前即可 `send`** 的本地静默丢弃路径，也跳过了 **openclaw 源码级** 的便宜判定（无订阅者则广播直接 return、无 transcript 回放）。「本轮不改代码」在 scope-lock 字面下仍可成立，但「调查已充分」不成立。`L1-REPRO.md` 秘密面基本干净、§5 label 限制写得够，但 **双终端环境变量交接缺口**、**§6 跑裸二进制而非 `.app`**、**干净机前置不全** 使「任何人干净机可复现」主张不成立；§7 死端口构造有 live 单次实证，但未证明条数稳定。

**Verdict: REWORK**

---

## Files touched

none（只读评审，未修改任何文件）

---

## Acceptance verification (11/11)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| Q1-a | `subscribe` 机制修正 + buffering | **PARTIAL** | 见下 Finding A |
| Q1-b | 两样本是否够撑「不改」+ 便宜确定性验证 | **FAIL 调查充分性** | 见 Finding B |
| Q1-c | 「证不出来就不改」是纪律还是挡箭牌 | **PARTIAL** | 见 Finding C |
| Q1 裁决 | ② 该不该改代码 | **本轮可不改，但不得记成已证伪竞态** | scope-lock:155 + 源码结构风险 |
| Q2-a | L1-REPRO 步骤完整 | **FAIL** | 见 Finding D |
| Q2-b | 真无秘密 / 无环境特有 | **PASS_WITH_NOTE** | 无硬编码 key；双 shell 状态未写清 |
| Q2-c | §7 死端口能否区分修前修后 | **PASS_WITH_NOTE** | live-closure 单次 2 条；条数稳定性未证 |
| Q2-d | §5 label 限制是否让步骤不可用 | **PASS** | §2/§5/§7 交叉引用够用 |
| Q2 裁决 | ⑥ 够不够格当可复现步骤 | **不够格（文档级 REWORK）** | Finding D/E |
| race 日志 | 失败轮是否真是 label | **PASS（主会话这点诚实）** | nopause-2..4 / paused-* / probe-single 均 FATAL label |
| 原始数据 | 与 item2 叙述对照 | **PASS** | nopause-1: subscribe SEND@681 先于 send@692；RECV 亦 subscribe 先 |

### Finding A — Q1(a)：机制修正大体对，但漏了一条本地丢弃路径

**主会话正确点**（`OpenclawGatewayKernelClient.swift:391-422`）：

```swift
let (stream, continuation) = AsyncThrowingStream.makeStream()
eventContinuations[ourSessionID] = continuation   // 同步，在 return 前
Task { ... request("sessions.messages.subscribe", ...) }  // 未 await
return stream
```

- 客户端是 `public actor`（同文件:38）。`subscribe()` 返回时，**本地分发表已有 continuation**。
- Swift 标准库默认：`AsyncThrowingStream.makeStream(..., bufferingPolicy: = .unbounded)`  
  证据：macOS SDK `_Concurrency.swiftinterface` 中 `makeStream` 的默认参数是 `.unbounded`。  
  → **`for try await` 尚未开始时，`continuation.yield` 会缓冲，不会因默认策略丢事件。**  
  主会话「本地续体同步注册 → 不存在本地丢失」对 **「subscribe 已返回之后」** 这一段成立；T-080 把问题说成「stream 返回后本地没人接」需要按 buffering 修正。

**主会话漏掉的本地路径**（`SessionStore.swift:96-103, 111-118, 125-134`）：

```swift
// createNewSession:
Task { await self.consumeEvents(for: viewModel) }  // 未 await、不 join
// 返回后 UI 即可点发送

// sendMessage: 不检查订阅是否已建立
_ = try await client.send(...)
```

`consumeEvents` 里才第一次 `await client.subscribe(...)`。若 `send` 的事件在 **`eventContinuations` 登记之前** 到达 receive loop：

```swift
// OpenclawGatewayKernelClient.swift:1109
guard let continuation = eventContinuations[ourSessionID] else { return }  // 静默丢弃
```

这是 **本地静默丢弃**，与「subscribe 返回后 unbounded 缓冲」不是同一条路径。UI 人类操作通常慢到碰不到，但代码契约允许；item2 §1 只修正了 T-080 的描述，**没有攻击 SessionStore 侧「subscribe 调用前可 send」**。

**CLI 路径**（`CLIRunner.swift:77-113`）顺序是 subscribe → observeTask → send，没有 SessionStore 那条洞；竞态收窄为 **subscribe RPC Task 与 send 抢 actor / 抢线上序**。

### Finding B — Q1(b)：存在便宜的确定性验证；「多轮成本高」不能当唯一停手理由

**两样本不够否定竞态**——主会话自己也写了（item2 §2）。同意。

**更便宜、本应做的验证（无需新 state 目录、无需 7 轮）：**

1. **openclaw 源码：无订阅者 = 事件不投递**  
   - 注册只在 `sessions.messages.subscribe` 处理时发生：`kernels/openclaw/src/gateway/server-methods/sessions-subscriptions.ts:90-123`（`subscribeSessionMessageEvents`）。  
   - 广播：`server-session-events.ts:181-187` — `connIds.size === 0` 则 **return**（不投递）。  
   - subscribe 响应 **没有 transcript 回放**（仅 `includeApprovals` 时的 `approvalReplay`，同文件 91-134）。  
   → **若 send 触发的 transcript/agent 事件发生在该连接登记订阅之前，客户端永久看不到这些帧。** 这是服务器语义，不是推测。

2. **actor 调度：subscribe RPC 与 send 可对调线上序**  
   - `subscribe` 内 `Task { await self.kernelKey...; await self.request(...) }` 必须 **重新进入 actor**。  
   - `subscribe` 返回后调用方的 `send()` 也要进同一 actor。  
   - 谁先拿到 actor，谁先 `task.send` 写 WS（`request` @ `:890+`）。  
   - **nopause-1 实测**：subscribe 帧先写出（log 行 681 vs 692），且 **两者都在任一 RECV 之前发出**（704/718）。说明「双 RPC 在途」是常态，不是理论。该次 subscribe 先于 send，**未能压力测试「send 抢先」分支**。

3. **确定性单次构造（仍比「每轮新实例×7」便宜）**  
   - 在测试桩里对 `sessions.messages.subscribe` 人为延迟 / 不注册 continuation 后 feed 帧，可直接证 `guard let continuation` 丢弃（frame-replay 已有 `testSupportRegisterSession` / `testSupportFeedFrame` 基础设施）。  
   - 或临时让 subscribe Task 晚于 send 进 actor（单次 CLI 插桩），不需要 label 解绑。

**结论**：label 硬编码确实让 **多轮统计** 变贵（race 目录 7/8 日志死在 `label already in use`，item2 诚实作废「7 轮 0 事件」——这点通过）。但 **「成本太高所以没做」对源码判定与单次强制竞态不成立**。两样本 + 结构可能 + 停手，**撑不住「调查闭环」**；只撑得住「未在 live 路径打出丢帧样本」。

### Finding C — Q1(c)：纪律方向对，执行有偷懒，尚未到纯挡箭牌

- scope-lock ② 明文：**「证不出来就不改」**（scope-lock.md:60）；Rollback：**证不出丢帧 → 不改**（:155）。  
- 0011 的反面是「没证据也宣称成功」；本次是「没打出丢帧样本就不改」——**方向相反，字面纪律一致**，不是同句纪律的简单反用。  
- 减分点：把「没付多轮成本」几乎等同「证不出来」，**跳过免费源码结论**，且未写清 SessionStore 本地洞。这是 **调查偷懒**，不是「故意用纪律洗地宣称竞态不存在」——item2 §4 明确 **「不宣称竞态不存在」**，这点应予肯定。

**问题一裁决**：

| 问题 | 裁决 |
|------|------|
| 本轮要不要改 subscribe/send 时序代码？ | **按 scope-lock：可以不改**（缺 live 丢帧复现） |
| item2「未能证实，故不改」是否可直接收官？ | **否**——须补：源码级条件丢帧语义、SessionStore 预 subscribe 洞、残留风险；不得写成「竞态已排除」 |
| 是否存在「必须立刻改」的阻断级 live bug？ | **未证实**（与主会话一致）；结构风险 **已证实** |

### Finding D — Q2(a)(b)：L1-REPRO 前置与跨 shell 状态有硬洞

文件：`app/apps/AgentShell/repro/L1-REPRO.md`（142 行）。

**成立的部分：**

- 无硬编码 API key；占位符 + channel-params / env 注入声明（:5-6, :46）。  
- 三件隔离配置表（§4）与 `logging.file` 实证引用正确。  
- openclaw 配置走 **JSON5**（`kernels/openclaw/src/config/io.read-helpers.ts` 的 `parseConfigJson5`），§2 示例里的 `//` 注释 **可被接受**（原先怀疑的 jsonc 坑不成立）。  
- frame-replay 期望 **31/31** 与 `runFrameReplayTests` 中 31 个 `results.append` 一致（`:1648-1686`）。

**硬洞（干净机照抄会卡死/跑偏）：**

1. **§3 gateway 前台阻塞，§6 需要同一组 `PORT`/`TOKEN`/`ISO`，全文无「第二终端如何交接」**  
   - §3 的 `node scripts/run-node.mjs gateway ...` 占住当前 shell。  
   - §6 使用 `$PORT`、`$TOKEN` 与 `$(pwd)/wire-trace.jsonl`。  
   - 读者必开第二终端，但第二终端 **没有** 这些变量，也未要求写到文件。  
   - 若第二终端仍停在 `kernels/openclaw` 且用相对路径 `./app/.build/...`，路径错误。  
   → **「任何人」复现的第一道实操门就断。**

2. **干净机前置不全**  
   - 无 `git submodule update --init kernels/openclaw`。  
   - 「`npm i` 过」只是检查列，无安装命令。  
   - 未写 **macOS**（SwiftUI 壳）、Xcode CLT / 完整 Xcode 要求。  
   - 无端口占用检查（只写「任选空闲端口」）。

3. **§1 构建 `.app`，§6 却启动裸 Mach-O**  
   - `build-app-bundle.sh` 明确：裸二进制难拿窗口/键盘焦点，才拼 `AgentShell.app`。  
   - §6 跑的是 `./app/.build/debug/AgentShell`，不是 `open app/.build/AgentShell.app` 或 bundle 内二进制。  
   → 与脚本自身设计矛盾；UI 验收可能「起得来但不好用/无焦点」。

4. **channel-params 怎么落到 `<PROVIDER_*>` 未逐步化**  
   - 写了参数名，没写「从 json 读出后 export / 写入 openclaw.json」的最小命令。

**秘密面**：未发现第二类硬编码凭证。环境特有风险主要是 **shell 状态与绝对路径习惯**，不是泄漏的 secret。

### Finding E — Q2(c)(d)：§7 死端口有单次实证；§5 够用

**§7：**

- 主会话 live 闭环用死端口 `http://127.0.0.1:59999` 打出 **恰好两条** 同 run、同 index=0、不同 messageID 的 assistant 失败文案（`evidence/live/live-closure.md:41-52`），与 0011 撞键形状一致。  
- 因此「死端口 → 两条」**不是纯臆造**。  
- 但全文 **只有一次** 成功构造记录；未证明：永远 2 条、不会 1 条（合并错误文案）或 3 条（重试）。若条数漂移，UI「两个气泡」判据会抖。  
- **更好的机检**其实已在 frame-replay：`testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs`（两帧 feed，断言 messageID 互异）——REPRO §7 未指引读者先跑该单测再上 live，浪费了确定性层。

**§5 label：**

- 硬编码 `OpenclawGatewayKernelClient.swift:274` `"sg4-kernel-client-l1"` 属实。  
- race 日志二次实证：`nopause-2.log:784`、`probe-single.log:785` 等 `label already in use`。  
- L1-REPRO §2「每次全新目录」、§5 全文、§7「全新目录重跑」交叉引用 **足以避免「失败一次想原地重试」的坑**，若读者读到 §5。  
- 不构成「整份步骤不可用」，只构成 **每次复现成本 = 新实例启动**。

**问题二裁决**：

| 问题 | 裁决 |
|------|------|
| ⑥ 是否够格作为 scope-lock「完整、无秘密重放步骤」？ | **不够格** — 缺跨终端交接与干净机引导；§6 启动方式可疑 |
| 无秘密主张 | **基本成立** |
| §7 验证方法 | **有 live 单次支撑，稳定性未证；应并列 frame-replay 机检** |
| §5 | **写清了，不否决整份文档** |

---

## Decisions / deviations

- 未启动 live openclaw/UI（brief 允许源码 + 既有日志裁决；且标签硬编码会污染用户环境）。依赖：race 日志、live-closure、SDK swiftinterface、openclaw/Swift 源码。  
- 未读 T-083 产物（异构独立要求）。  
- 「本轮不改 ② 代码」与「REWORK 文档/证据」同时成立：REWORK 打在 **收官叙事与 L1-REPRO 可执行性**，不是强制本轮重写 subscribe。

---

## Open questions

1. openclaw 单连接上 `sessions.send` handler 是否与 message 帧处理严格串行到「subscribe 登记 happens-before send 副作用」——未跟完 `authenticated-request-dispatch` 全路径；即使串行，**客户端仍可能先写出 send 帧**（actor 竞态）。  
2. 死端口路径是否在 openclaw 版本升级后仍稳定产出 **恰好 2** 条 `session.message` assistant。  
3. SessionStore 是否应在产品层硬性 `await subscribe 建立后再 enable 发送`——属功能改进，超出本轮 scope，但是真洞。

---

## Verdict

**REWORK**

| 对象 | 子裁决 |
|------|--------|
| ② 代码是否修改 | **维持不改**（scope-lock 字面；无 live 丢帧样本） |
| ② 证据/收官表述 | **REWORK** — 补源码条件语义、SessionStore 洞、明确「未证伪」≠「已排除」；承认跳过便宜验证 |
| ⑥ L1-REPRO | **REWORK** — 至少补：双终端 env 交接、repo root 约定、submodule/npm/macOS 前置、§6 改用 `.app`、§7 并列 frame-replay 31/31 与 wire 断言 |
| 整体 rounds/0012 ②⑥ 能否直接收官 | **否**，先收文档洞再过闸 |

---

## Next recommendation

1. **改 `item2-subscribe-race.md`（文档）**：写入 Finding A/B；结论改为「live 未打出丢帧样本 → 本轮不改代码；服务器语义下竞态命中会丢；SessionStore 存在 subscribe 前 send 的本地丢弃面；未做源码/单次强制竞态前不得声称调查完备」。  
2. **改 `L1-REPRO.md`（文档）**：第二终端 `export PORT TOKEN ISO` 模板；固定「仓库根」；`git submodule update --init` + `npm i`；`open app/.build/AgentShell.app`；§7 先跑 `frame-replay-tests` 再 live 死端口。  
3. **② 代码**：本修复轮可不动；登记 backlog——(i) label 可配置 (ii) `subscribe` await RPC 完成再返回或 SessionStore 发送门闸。  
4. 文档改完后可 **acceptance 短确认**（不必再开完整对抗轮），再判 RAE/round 收口。  
5. 对照 T-083（codex）异构结论时，以 **两份独立 finding 并集** 为准，勿只取附和项。
