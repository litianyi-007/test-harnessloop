# 真内核 interrupt 证据 —— rounds/0020

**为什么必须有这份东西**：本轮 123 条单元测试**全部 stub 掉 `sessions.abort`**。
「会话在真内核侧是否还活着」在 stub 世界里没有意义——**红线只能由真内核证明**。

**环境**：隔离 openclaw 实例（本轮新起，端口 60445，profile 在 scratchpad 下），
provider=deepseek / model=deepseek-v4-flash，真实模型调用、真实计费。
**用户常驻 gateway（pid 29071）与 `~/.openclaw` 全程未触碰**，每次运行前后单独核对。

跑了四次，改的只有 `SG5_INTERRUPT_AFTER_MS`（打断时机）与提示词长度。

## 四次运行的结果

| # | 打断时机 | `affectedRunId` | assistant delta（前 → 后） | 说明 |
|---|---|---|---|---|
| 1 | 6s | **非空** `de7cefd8…` | 0 → 0 | 真打断了活跃 run，但那时还没出文本 |
| 2 | 25s | **`<nil>`** | **1125 → 0** | 文本确实停了，**但 run 已自然结束**，停不能归因于打断 |
| 3 | 15s | **非空** `ea11e996…` | 0 → 0 | 同 #1 |
| 4 | 21s | **非空** `46f5b7dc…` | 0 → 0 | 同 #1，但该 run 有 **234 条 thinking 事件** |

## 已被真内核证明的（四次全部成立）

| 判据 | 证据 |
|---|---|
| **不发 `session_end`（红线）** | 四次均 `[PASS] interrupt 之后未观察到任何 sessionEnd 事件` |
| **不调 `sessions.delete`（红线）** | interrupt 期间实际 dispatch 的 RPC 只有 **`sessions.abort` 与 `sessions.send`**（后者是打断后补发的第二条消息）。收尾那次 `sessions.delete` 属 `stop()` 的 STEP 4，不是 interrupt |
| **会话真的存活、能接着说下一句** | 四次均 `[PASS] 第二条消息拿到新 runId…与被打断的 runId 不同`。这是**真内核**给的新 runId，不是 stub |
| **真的中止了活跃 run** | #1/#3/#4 的 `affectedRunId` **非空**——按适配器逻辑，非空即 `sessions.abort` 回报它确实中止了一个活跃 run |
| `outcome` | 四次均 `succeeded` |

## 没有被证明的，如实写明

**没有任何一次同时满足「`affectedRunId` 非空」与「打断前已有文本输出」。**
所以「**正在吐字的生成被打断而停下**」这一条，**四次都没有干净地证明**：

- #2 有 1125 → 0 的字符落差，**但 `affectedRunId` 是 `<nil>`**——那个 run 在打断生效前就自己结束了，
  「后 0 字符」可以被自然结束解释，不能归因于 interrupt。
- #1/#3/#4 确实中止了活跃 run，但打断前 assistant delta 是 0。

**根因不是产品，是这条断言测错了通道。** 事件类型分布（#4 全程）：

```
235 evt.thinking      ← 生成几乎全部时间在这里
  1 evt.message.delta ← assistant 文本只在最末尾才出
```

这个模型把绝大部分时间花在 thinking 上，assistant delta 要到最后才吐。
**harness 只统计 assistant delta，对这类模型天然测不到「生成在飞」。**
#4 那个被中止的 run 有 **234 条 thinking 事件**——生成显然在飞，只是不在被统计的通道里。

> **一个不能用来救场的观察**：直接按日志行号数「interrupt 调用行之前/之后的 thinking 数」
> 会得到 0 / 234，看起来正好是想要的结论——**但这个数不可信**。CLI 的事件消费在后台 task 里，
> 打印顺序与 interrupt 调用点没有时序关系。**权威的前后切分是 harness 自己在事件流里打的标记**，
> 而它只数 assistant delta。**不拿一个碰巧好看的数字冒充证据。**

## 遗留

1. **上面那条**：harness 的 delta 统计应扩到 thinking 通道（或改成「该 run 的任意流式活动」），
   才能对 thinking 型模型证明「生成真的停了」。**属 harness 断言缺陷，非产品缺陷。**
2. **按钮的实拍未取得** —— 屏幕处于锁定状态，`screencapture` 拍到的是 macOS 锁屏。
   **这条 CLI 证据顶替不了它**：视图层结构性不可测（`Package.swift:104`，测试 target 依赖
   `AgentShellCore` 而非 `AgentShell`，两个 executableTarget 不能互相 import），
   把 `||` 打成 `&&` 整套测试不会红。**只有实拍能覆盖那个按钮，需要用户解锁后补。**
### run 1
```
=== [interrupt 步骤断言] ===
  operationId=op-interrupt-FD17E73F-DFF4-453C-8A75-EC1CF2E2B9CA outcome=succeeded affectedRunId=de7cefd8-f7a3-4958-b729-d738b7efc29e
  [PASS] interrupt 之后未观察到任何 sessionEnd 事件（期望：无——interrupt(mode:.cancel) 不应终结会话）
  [PASS] 第二条消息拿到新 runId=4695a9ed-bafd-4384-8937-c9ad192fb534，与被打断的 runId=de7cefd8-f7a3-4958-b729-d738b7efc29e 不同——session 确实存活且可以继续对话
  runId=de7cefd8-f7a3-4958-b729-d738b7efc29e 的 assistant delta 字符数：interrupt 前 0 字符，interrupt 后 0 字符
    [WARN] interrupt 前字符数为 0——SG5_INTERRUPT_AFTER_MS=6000ms 内还没收到任何该 run 的 delta，没能证明"generation 真的在飞"就已经打断，考虑调大这个值
=== [interrupt 步骤断言] 结束 ===
```
### run 2
```
=== [interrupt 步骤断言] ===
  operationId=op-interrupt-DADAA1C6-3880-4E1B-A605-FDCD92A50753 outcome=succeeded affectedRunId=<nil>
  [PASS] interrupt 之后未观察到任何 sessionEnd 事件（期望：无——interrupt(mode:.cancel) 不应终结会话）
  [PASS] 第二条消息拿到新 runId=46476a3d-c317-4f24-9d72-d5674a24afe9，与被打断的 runId=22436a99-fe34-48b6-a709-25097c4e492f 不同——session 确实存活且可以继续对话
  runId=22436a99-fe34-48b6-a709-25097c4e492f 的 assistant delta 字符数：interrupt 前 1125 字符，interrupt 后 0 字符
    [PASS] interrupt 后此 run 的 delta 字符数为 0——generation 确实停了，不只是 RPC 返回了 200
=== [interrupt 步骤断言] 结束 ===
```
### run 3
```
=== [interrupt 步骤断言] ===
  operationId=op-interrupt-33711637-547C-45C8-B1C3-95ECC789DE01 outcome=succeeded affectedRunId=ea11e996-4873-4a91-bcf8-2cd8b5ddeb09
  [PASS] interrupt 之后未观察到任何 sessionEnd 事件（期望：无——interrupt(mode:.cancel) 不应终结会话）
  [PASS] 第二条消息拿到新 runId=d125832b-44cc-4c03-a114-ce7dcb2c725f，与被打断的 runId=ea11e996-4873-4a91-bcf8-2cd8b5ddeb09 不同——session 确实存活且可以继续对话
  runId=ea11e996-4873-4a91-bcf8-2cd8b5ddeb09 的 assistant delta 字符数：interrupt 前 0 字符，interrupt 后 0 字符
    [WARN] interrupt 前字符数为 0——SG5_INTERRUPT_AFTER_MS=15000ms 内还没收到任何该 run 的 delta，没能证明"generation 真的在飞"就已经打断，考虑调大这个值
=== [interrupt 步骤断言] 结束 ===
```
### run 4
```
=== [interrupt 步骤断言] ===
  operationId=op-interrupt-1A84DDF9-FAC3-40C3-9B68-77EE04C33909 outcome=succeeded affectedRunId=46f5b7dc-b51c-46db-b7f8-fd16d0e24e07
  [PASS] interrupt 之后未观察到任何 sessionEnd 事件（期望：无——interrupt(mode:.cancel) 不应终结会话）
  [PASS] 第二条消息拿到新 runId=0fb90409-97c4-4dab-bd6b-eefaf80846f8，与被打断的 runId=46f5b7dc-b51c-46db-b7f8-fd16d0e24e07 不同——session 确实存活且可以继续对话
  runId=46f5b7dc-b51c-46db-b7f8-fd16d0e24e07 的 assistant delta 字符数：interrupt 前 0 字符，interrupt 后 0 字符
    [WARN] interrupt 前字符数为 0——SG5_INTERRUPT_AFTER_MS=21000ms 内还没收到任何该 run 的 delta，没能证明"generation 真的在飞"就已经打断，考虑调大这个值
=== [interrupt 步骤断言] 结束 ===
```
