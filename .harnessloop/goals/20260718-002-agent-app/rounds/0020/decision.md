# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-113-grok-output.md
- Reviewer: grok（**grok-4.6**）via hopper T-113（单路，按 scope-lock）
- Review verdict: **REWORK**（四条，主会话独立复核全部成立后返工）
- Review digest: 511bcf2c1ae86cd40aae64cd3fea6e39ca2fdaea94180eb19b730756d19a5215
- Acceptance evals: none — 本轮无 runtime eval 台账
- Acceptance evals detail: n/a
- Active goal: 20260718-002-agent-app
- Active round: 0020
- Decision maker: main session（claude-opus-5[1m]）；用户 2026-08-13 裁定按 2→1→3 执行，本轮是第 3 件
- Timestamp: 2026-08-13

## Reason

**「停止生成」达成**：`interrupt(mode:"cancel")` 中止当前 run 而**保留会话**，
区别于既有 `stop()`（abort + delete + session_end + finish 事件流，**它把会话销毁了**）。

**动手前查清三件事，都是实证不是假设**：①不需要改 openclaw 源码——`sessions.abort` 在
`core-descriptors.ts:231` 已注册，读 handler 本体 `sessions-abort.ts`（332 行）确认它只中止 run、
从不删会话；②契约把三种模式写死，本轮只做 cancel，另两种显式抛 `unsupported_interrupt_mode`；
③按钮同位置三态切换而非并排多一个。

帧回放 **102 → 124**。

## 评审判 REWORK 四条，全部返工

| # | 发现 | 性质 |
|---|---|---|
| **①** | interrupt 成功后，**迟到的第二帧**落进 `:2804-2826` 兜底分支，`operationKind` 被**写死成 `.stop`**，UI 弹出一条用户从未发起过的 `[操作] stop 已完成：outcome=aborted_effect_unknown` | **高**，实拍已现 |
| ② | `handleOperationCompleted` 对**一切** `.interrupt` outcome（含 `.rejected`）清 `isWaitingForReply`，与 `interruptCurrentRun` 自己的文档（`:389-394`）**直接矛盾** | 中 |
| ③ | `SessionStore.swift:732-735` 注释描述的机制与代码不符 | 低，但正是本项目的老毛病 |
| ④ | **缺一条测试**：interrupt 终态后、pending 已被 defer 清掉、再来一帧 `phase:"error"` | 正是它让 ① 出厂 |

## 评审做到了主会话没做到的事

主会话在实拍中发现 ① 的症状，但只能说「最可疑是 `:2819`，**未能证实**」。
评审**把整条链路证实了**：openclaw abort 发**两帧**（`end` 然后 `error`，
`EventMapping.swift:459-461` 白纸黑字）→ 第一帧命中 pendingStops 渲染正确的
`interrupt/succeeded` → **`interrupt()` 的 defer 立刻摘表** → 第二帧到达时表已空 →
进兜底 → 写死 `.stop` + `phase≠end` 映射成 `abortedEffectUnknown` + detail 取
`"This operation was aborted"` → **与实拍字符串逐字吻合**。并排除了另外三条可能来源。

**它对主会话一个判断的复核尤其准**：`:2819` 写死 `.stop`——**作为代码考古是对的**
（该分支按构造读不到发起者信息），**作为产品决策在 interrupt 落地后是错的**：
`stop()` 时这条分支实际不可达（会话与流都死了），**而 interrupt 故意保活流，
于是它变成「成功之后可预期的副作用」**。把「没有信息」填成 `.stop` 不是中性默认。

## 主会话自己埋的一个雷，如实记

②那条矛盾里，**钉住错误行为的那条测试是主会话要求补的**。当时主会话探到
「`.rejected` 没有测试覆盖」就要求补测试，**没有问被钉住的行为本身对不对**。
文档的论证更强：中止失败时 run 可能还在跑，清掉等待态会让 UI 撒谎，
且按钮变回「发送」，用户连重试停止都做不到。

**「没有测试覆盖 X」不等于「X 是对的」。** 这是本轮最该记住的一条。

## 返工的两个判断（主会话复核后采纳）

1. **兜底分支改为「无身份则不作身份声明」**：`operationID`/`operationKind` 改为可选，
   两者为 nil 时**只发 `turn_complete(cancelled)`、不发 `operation_completed`**。
   `turn_complete` 不携带 operationKind，只断言「这个 run 确实被 abort 了」——这件事无论
   谁发起都为真，因此真正「非我方发起的 abort」仍被如实反映，UI 也不会永远转圈。
2. **`.timedOut` 与 `.rejected` 同等对待，都不清等待态**（实施方超出任务书自行判断，
   主会话复核后采纳）：`.timedOut` 意味着 abort 被接受但**没等到终态确认**，
   认知上更接近「不知道停没停」而非「已知停了」。不清的代价只是转圈久一点，
   且**因为 ① 的修复，迟到帧现在会以 `turn_complete` 正确幸存**，会自愈。

## 独立复核（全部主会话自己跑）

| 判据 | 结果 |
|---|---|
| 构建 / 帧回放 | exit 0 ／ **124/124**（基线 102 → 115 → 123 → 124） |
| 红线：不调 `sessions.delete` | interrupt 函数体内 `request(method:)` 只有 `sessions.abort` 一处；出现的 4 处 `sessions.delete` 与 1 处 `emitStopSessionEndAndFinish` **全是注释** |
| 红线：真内核 | 隔离 openclaw 实测 `sessions.abort` 有、**`sessions.delete` 为 0** |
| `stop()` 无回归 | 四处调用点仍传 `.stop`，落在 `stop()` 体内的改动全是「隐式 `.stop` → 显式 `.stop`」 |
| **主会话反证 1**（实施方未打过的方向） | 让锁**从未被设置**（而非让检查失效）：命中 1 → 115 掉到 114 → 还原 115，逐字节一致 |
| **主会话反证 2**（探缺失的测试） | 排除 `.rejected` → **122/122 全绿，什么都没红** → 据此要求补测（但**没问行为对不对**，见上） |
| **主会话反证 3**（返工后） | 把清除条件从 `.succeeded` 改成 `.rejected` → **124 掉到 121（3 条红）** → 还原 124，sha 一致 |
| 禁改路径 | `kernels/openclaw` 0 个被跟踪文件改动、指针未动 |

## Main-Session Decision On Scope Boundary

- **scope-lock 两次扩围，均留痕**：v1→v2 `EventMapping.swift`（实施方主动点名，
  避免复制 30 行解读逻辑造成两份必然漂移的副本）；v2→v3 `CLIRunner.swift`
  （**123 条单元测试全部 stub 掉 `sessions.abort`，红线只能由真内核证明**）。
- **隔离实例两次起停均收干净**（端口释放、目录删除、凭证副本 0），
  用户常驻 gateway（pid 29071）与 `~/.openclaw` 全程未触碰。

## Open Questions Resolved

- **「停止生成」是不是 `stop()`** → **不是**。差在第二步：`stop()` 还会 delete 会话。
- **要不要改 openclaw 源码** → **不要**。`sessions.abort` 现成且只中止 run。
- **没有发起者信息时该填什么** → **什么都不填**。填一个「历史默认值」等于伪造。

## Open Questions Remaining

1. **`isInterrupting` 的禁用中间态未拍到** —— 窗口太短（interrupt RPC 往返期间），
   连拍没捕捉到。store 侧有测试与反证，**视图层那一半仍只靠读代码**。
2. **视图层结构性不可测** —— `Package.swift:104` 测试 target 依赖 `AgentShellCore` 而非
   `AgentShell`，两个 executableTarget 不能互相 import。把按钮条件的 `||` 打成 `&&`，
   124 条测试一条不会红。**只有实拍能覆盖。**
3. **真内核「正在吐字被打断」未干净证明** —— CLI harness 只统计 assistant delta，
   而该模型 235 条 thinking 只配 1 条 delta。**属 harness 断言缺陷，非产品缺陷。**
4. **hopper 派发状态假阴性** —— T-113 报 `Status: timeout`（180s adapter-timeout），
   **产物却是完整的 259 行评审**。与 hopper 那条「exit 0 但任务没送到」正好反过来，同族。
