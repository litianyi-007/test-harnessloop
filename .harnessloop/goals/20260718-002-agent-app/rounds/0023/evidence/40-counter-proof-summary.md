# rounds/0023 破坏性反证汇总

四条新断言的红/绿反证，逐条记录：注入方式、命中数（0=注入本身无效）、RED 结果、revert、GREEN 结果。
残留一律用 checksum 核验（不用 `git checkout --`，理由见 CLAUDE.md 凭证守门节）。

全部残留核验证据：`10-counter-proof-checksums-before.txt` / `16-counter-proof-checksums-after.txt`
（两份完全一致，`diff` 输出为空）。

| # | 新断言 | 注入方式 | 命中数 | RED 结果 | GREEN 结果（revert 后） |
|---|---|---|---|---|---|
| 1 | steer 走 `chat.send`（不是 `sessions.abort`/`sessions.steer`/`sessions.send`） | 把 `request(method: "chat.send", ...)` 改成 `request(method: "sessions.abort", ...)` | 1 | 整条 suite 挂起（`testInterruptSteerCallsChatSendWithQueueModeSteerDeliverFalseAndSucceedsAsSubmitted` 里等待 `chat.send` 捕获参数的 `InterruptRaceBox.wait()` 永远等不到 report——本身就是比"某条测试 FAIL"更强的红：整条实现路径的可观测行为都变了）。见 `11-counter-proof1-red-build.log`/`11-counter-proof1-red-run.log`（后者只有部分输出，进程被主动终止） | `12-counter-proof1-green-run.log`：169/169 PASS，exit 0 |
| 2 | 无 active run → 同步前置 reject `no_active_run_for_steer`，不铸 operationId | 精确校验条件前加 `false,` 短路整个 `if`，使前置校验永不触发 | 1 | `13-counter-proof2-red-run.log`：168/169，唯一 FAIL 精确是 `testInterruptSteerNoActiveRunPreRejectsSynchronouslyNoOperationId`（"expected interrupt(mode:steer) to throw no_active_run_for_steer..."） | `13-counter-proof2-red-build.log` 之后 revert，重跑：169/169 PASS |
| 3 | `stop()` 遇 `interrupt_in_progress`「等待，不抢占」仲裁 | 精确校验条件前加 `false,` 短路整个仲裁分支，使其永不触发（回退成 rounds/0020 的"一律 reject"） | 1 | `14-counter-proof3-red-run.log`：166/169，精确命中 3 条依赖仲裁机制的测试——cancel 版 `testSendRejectedButStopWaitsThenProceedsWhileInterruptInFlight`、steer 版 `testStopWaitsDuringInFlightSteerThenProceedsToStopInProgressAfterSubmitted`、超时归属 `testStopOwnTimeoutWhenArbitrationWaitExceedsBoundIsNeverAnInterruptOutcome`——三条互不重叠、精确对应仲裁机制的三个观察面 | revert 后：169/169 PASS |
| 4 | steer RPC 失败 → 必须补发 `operation_completed(rejected)` 镜像（catch 块按 mode 区分 `alreadyTerminalEmitted`，不能沿用 cancel 的 `?? true` 默认值） | 把 steer 分支的 `alreadyTerminalEmitted = false` 改回 `= true`（复现"steer 误判成已经有人发过镜像"的 bug 形状） | 1 | `15-counter-proof4-red-run.json`：168/169，精确命中 `testInterruptSteerRpcFailureIsRejectedNotAThirdOutcome`（"expected exactly 1 event..., got 0"） | revert 后：169/169 PASS |

## 残留核验

```
$ shasum -a 256 app/kernel-client/swift/OpenclawGatewayKernelClient.swift \
    app/kernel-client/swift/frame-replay-tests/SteerTests.swift \
    app/kernel-client/swift/frame-replay-tests/InterruptTests.swift
```

四次注入 + revert 全部只动过 `OpenclawGatewayKernelClient.swift`（`SteerTests.swift`/`InterruptTests.swift`
在反证阶段未被触碰）。反证前后该文件 sha256 均为
`732af98144f63e7a796f1a38859c0e403b49ac9a5f13a30b934b49f45506a565`——四轮注入 + revert 之后逐字节相同，
无残留。

## 关于反证 #1 的额外说明（进程挂起）

反证 #1 没有产出一份干净的"[FAIL] ... N/M PASS"文本，而是让整个测试进程挂起超过 180 秒（被主动
`TaskStop` 终止）。根因：`testInterruptSteerCallsChatSendWithQueueModeSteerDeliverFalseAndSucceedsAsSubmitted`
用 `InterruptRaceBox<JSONObject>.wait()`（无超时）等待 `chat.send` stub 闭包报告捕获到的 params——
注入把真实调用换成了 `sessions.abort`，`chat.send` 的 stub 闭包因此永远不会被调用，`report(...)`
永远不会发生，`wait()` 永久挂起。这本身就是一个比"某条断言 FAIL"更强的红色信号（实现路径的可观测
行为整个变了——原本应该调 `chat.send` 却调了别的方法），但也如实暴露了 `InterruptRaceBox.wait()`
无界等待这一测试基础设施的已知边界（不是本轮新增的缺陷，`FrameReplayTests.swift`/`InterruptTests.swift`
既有的其它用法都受益于 stub 闭包本身有超时或必然被调用，没有踩过这个组合）。已确认 revert 之后不产生
任何残留悬挂进程（`ps aux | grep frame-replay-tests` 核实过）。
