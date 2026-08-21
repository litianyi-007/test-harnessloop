# Round Summary — goal 002 / rounds/0023

**把 `interrupt` 补齐到 confirmed D1：实现软 steer，并把「等待，不抢占」做成原子交接。评审抓住了测试和时序日志都看不见的竞态。**

## 改了什么

实现 `interrupt(mode:"steer")`（`chat.send` + `queueMode:"steer"` + `deliver:false`），
并把 `stop()` 遇 `interrupt_in_progress` 从「一律 `session_locked`」改成规格 §9.3 的
「等待该 RPC 返回，再转 `stop_in_progress`」。`send()` 遇同一把锁仍然拒绝。

金标 `soft-steer-then-stop` 在 Swift runner 上从 FAIL 转为 PASS。
整套 13 条 fixture **13 PASS / 0 FAIL / 0 DEGRADED**。帧回放 **163 → 169 → 174**。

## 最重要的源码事实

`sessions.steer` 与 `sessions.send` 共用 handler，只差 `interruptIfActive`——
那是 abort+resend，不是软 steer。名字最像的 RPC 是错的选项。

## 评审 T-116 判 REWORK，三条全返工

「等待」做到了，交接不是原子的：defer 先把锁写成 `idle` 再唤醒 stop，
中间窗口里另一个 `send()` 可以插队。现已在无 `await` 的同步段内直接把锁交给
唯一的 stop waiter。反证红是 `lock state is send_pending`。

active-run 快照改为全量对账，并让裸 agent 事件也能标记 active。
会话恢复那条路径闭不上：subscribe 响应不含 active run 信息，保持保守拒绝。

runner 入站响应按 mode 分叉，不再给 `chat.send` 配 `abortedRunId`。

## 本轮暴露、留给后续的

会话恢复无 active-run 信号 · `sessionKey`→`sessionId` 未映射 ·
`respondApproval` 零 parity 覆盖 · C# 三方法仍是桩（刻意）·
CI 还不跑 174 条帧回放、还按「1 DEGRADED」描述 Swift parity

## Cost

unavailable: no local transcript source — `round_cost.py` 只读 Claude Code 会话记录；本收盘发生在 Grok 会话。
