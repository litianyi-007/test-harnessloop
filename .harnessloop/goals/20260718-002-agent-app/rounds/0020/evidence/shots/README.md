# rounds/0020 实拍 —— 停止按钮

**用户 2026-08-13 解锁屏幕后补拍。** 此前一次尝试拍到的是 macOS 锁屏，
已如实记录为阻断而非伪造成功（见 `../real-kernel-interrupt.md`）。

**为什么这几张图不可省**：视图层**结构性不可测**——`Package.swift:104` 里
`frame-replay-tests` 依赖的是 `AgentShellCore` 而非 `AgentShell`，而 `AgentShell` 是
`executableTarget`，SwiftPM 不允许两个 executableTarget 互相 import（`Package.swift:70-79`
自己就记着这件事）。仓内也没有任何 SwiftUI 视图测试工具。
**把按钮条件里的 `||` 打成 `&&`，123 条测试一条都不会红。只有实拍能覆盖它。**

环境：隔离 openclaw（端口 57532，profile 在 scratchpad 下，拍完已拆除）、
provider=deepseek / deepseek-v4-flash，真实模型调用。
用户常驻 gateway（pid 29071）与 `~/.openclaw` 全程未触碰。

## 01-generating-stop-button-visible.png

**生成进行中**。一张图里同时拍到四件事：

- 右上 **`等待回复…`** 转圈（`isWaitingForReply == true`）
- 输入框右侧 **`■ 停止`**——**就在 `发送` 原来的位置上**，是同位置替换而不是并排多一个按钮
  （scope-lock 取舍 #5）
- **`推理` 行**——rounds/0019 修的思考流合并，这里是它第一次被实拍到
- **两条 `exec` 工具行**（`成功 2,658ms lines: 3000` / `成功 82ms`）——
  **这顺带补上了 rounds/0019 明确登记的证据缺口「工具调用/结果行未被触发」**

## 02-after-stop-interrupt-succeeded.png

**点下 `停止` 之后**。系统行：**`[操作] interrupt 已完成：outcome=succeeded`**。
按钮已变回 `发送`，转圈消失。

同时内核侧实测（隔离实例日志）：

| RPC | 次数 |
|---|---|
| `sessions.abort` | **3**（有） |
| **`sessions.delete`** | **0（红线成立）** |

**这张图里还有一个缺陷，见下方「实拍抓到的缺陷」。**

## 03-session-alive-after-interrupt.png

**打断之后在同一个会话里继续发消息**，assistant 回出 **`The session is active.`**
——`会话 4` 从头到尾是同一个会话，历史完整保留。
**这是「中止 run 但保留会话」这条红线唯一的端到端证明。**

> 输入框里的字被输入法弄乱了（`R 二品旅游 withexactlyfourwords…`）——
> 那是 GUI 自动化经由 IME 键入的问题，不是产品问题。模型仍然照办了。

## 04-stale-session-send-failed.png

**不是缺陷，但值得留一张**：app 从磁盘恢复了上一个（已被我拆掉的）内核实例的会话，
向新内核发消息得到 `[发送失败] rpc rejected [INVALID_REQUEST]: session not found`。
**按钮据此正确地退回了 `发送` 态**（`isWaitingForReply` 在发送失败分支被清掉，
`SessionStore.swift:350`）——**失败路径的 UI 行为也被这张图顺带证明了。**

## 实拍抓到的缺陷：一条用户从未发起过的 `stop` 系统行

02 那张图里，`interrupt 已完成：outcome=succeeded` **下面紧跟着**：

```
[操作] stop 已完成： outcome=aborted_effect_unknown， This operation was aborted
```

**用户按的是「停止生成」（interrupt），从头到尾没有发起过 `stop`。**

**可以确证的部分**：`stop()` **这一轮根本没有运行过**——它必然 dispatch `sessions.delete`，
而隔离内核日志里 `sessions.delete` **恰好是 0**。所以这条系统行描述的是一个**没有发生过的操作**，
标签是错的，与它由哪个分支发出无关。

**未能确证的部分（如实标注）**：最可疑的来源是
`OpenclawGatewayKernelClient.swift:2819` 那条防御性兜底分支——它在
`pendingStops[sessionID] == nil` 时把 `operationKind` **写死成 `.stop`**。
interrupt 的 pendingStop 在函数返回时就被 `defer` 摘掉了，一条**迟到的** aborted lifecycle 帧
正好会落进这条分支。但 app 的 stdout 不打印 `operationKind`/`operationId`，
**我无法从现有日志把它钉死**，所以这只是最可能的机制，不是已证实的机制。

**这条要单独记一笔**：我在本轮代码复核时**看过 `:2819`，并判定「这不是漏改，
因为该分支按构造就没有发起者信息可读」**。那个判断在**代码正确性**上仍然成立，
但**我低估了它的用户可见后果**——它会在用户按下「停止」之后，
弹出一条说「stop 已完成」且 outcome 看起来像出了错（`aborted_effect_unknown`）的系统行。
**代码层面「没有信息可填」不等于产品层面「可以随便填一个」。**

## 本轮仍未取得的实拍

- **`isInterrupting` 那个禁用中间态**没有单独拍到。它的窗口很短
  （interrupt RPC 往返期间），本次连拍没有捕捉到。
  它的 store 侧逻辑有测试与反证覆盖，但**视图层那一半仍然只靠读代码**。
