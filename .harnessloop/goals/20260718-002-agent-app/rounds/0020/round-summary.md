# Round Summary — goal 002 / rounds/0020

**用户裁定的第 3 件：停止按钮。** 帧回放 102 → 124。

## 一句话：「停止生成」不是 `stop()`，差在第二步

`stop()` 是 `sessions.abort` + `sessions.delete` + `session_end` + finish 事件流——
**它把会话销毁了**。「停止生成」只要第一步：**中止当前 run、保留会话、用户接着说下一句**。

动手前查清三件事，都是读源码实证：`sessions.abort` 在 openclaw 已注册且**只中止 run 从不删会话**
（handler 本体 332 行读完）；契约把 `steer/cancel/abort_and_resend` 三种模式写死，本轮只做
cancel、另两种显式抛 `unsupported_interrupt_mode`；按钮同位置三态切换而非并排多一个。

**因此不需要改 openclaw 源码。**

## 实拍抓到测试抓不到的缺陷——本轮第二次

用户解锁屏幕后补拍。三张图证明完整链路：生成中 `■ 停止` 就在 `发送` 原位 →
点下后 `[操作] interrupt 已完成：outcome=succeeded`、内核侧 `sessions.abort` 有而
**`sessions.delete` 为 0** → 同一会话继续发消息，assistant 回出 `The session is active.`

**同一张图暴露一个缺陷**：`interrupt 已完成` 下面紧跟一条
`[操作] stop 已完成：outcome=aborted_effect_unknown`——**用户从未发起过 `stop`**。

第一次点停止时差点误报成功：反应过来去查内核日志，`sessions.abort` 是 **0**，
说明那次 run 在点击前就自己结束了，按钮只是「显示正确」而非「动作生效」。重做才拿到真的。

## 评审证实了主会话证不出的东西

主会话只能说「最可疑是 `:2819`，**未能证实**」。评审把链路钉死：
openclaw abort 发**两帧**（`end` 然后 `error`）→ 第一帧命中 pendingStops 渲染正确 →
**`interrupt()` 的 defer 立刻摘表** → 第二帧到达时表已空 → 进兜底 → 写死 `.stop` →
`phase≠end` 映射成 `abortedEffectUnknown` → **与实拍字符串逐字吻合**。另排除三条来源。

**关键洞察**：`stop()` 时这条兜底分支实际不可达（会话与流都死了），
**而 interrupt 故意保活流，于是它从「理论上不会出现」变成「成功之后可预期的副作用」**。

## 主会话自己埋的一个雷

`.rejected` 清等待态与 `interruptCurrentRun` 自己的文档直接矛盾——
**而钉住这个错误行为的测试是主会话要求补的**。当时探到「`.rejected` 没覆盖」就要求补，
**没问被钉住的行为对不对**。文档论证更强：中止失败时 run 可能还在跑，清掉会让 UI 撒谎，
按钮变回「发送」，用户连重试都做不到。

**「没有测试覆盖 X」不等于「X 是对的」。**

## 硬判据（全部主会话独立复跑）

构建 exit 0 · 帧回放 **124/124** · interrupt 函数体内只有一处 RPC 且是 `sessions.abort`
（出现的 4 处 `sessions.delete` 全是注释）· 真内核 `sessions.delete` = 0 ·
`stop()` 四处调用点仍传 `.stop`、体内改动全是「隐式→显式」·
**三条主会话自己的反证**（115→114、122 全绿暴露缺测、124→121）均先见红后还原、sha 逐字节一致

## 四条如实登记的缺口

`isInterrupting` 中间态未拍到 · **视图层结构性不可测**（`||` 打成 `&&` 一条测试不会红）·
真内核「正在吐字被打断」未干净证明（harness 只统计 assistant delta，而该模型
235 条 thinking 只配 1 条 delta，属 harness 缺陷）· hopper 报 `Status: timeout`
而产物是完整 259 行评审（与「exit 0 但任务没送到」正好反过来）
