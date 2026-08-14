# Round Summary — goal 002 / rounds/0022

**把金标 parity 套件里那个会静默失效的开关修掉了。它当场兑现了价值，而追查评审超时又挖出 hopper 一个真缺陷。**

## 改了什么

DEGRADED 判定由**硬编码方法名单**改为**运行时发现**：跑 timeline，client 抛 `notImplemented`
才降级，其它任何结果都是真实 PASS/FAIL。两端同改。

| 端 | 改动前 | 改动后 |
|---|---|---|
| Swift | 12 PASS / 0 FAIL / **1 DEGRADED**，exit 0 | 12 PASS / **1 FAIL** / 0 DEGRADED，**exit 1** |
| C# | 12 / 0 / 1（理由查表） | 12 / 0 / 1（理由**运行时捕获**） |

**那条 fixture 此前从未被执行过。** 现在 Swift 真跑了它并给出三条实质 mismatch，
C# 仍诚实降级——**Mac↔Windows 的能力分歧第一次成为机器判据**。

## 最重要的正确性属性：不能把真失败洗成 DEGRADED

单一收口点只匹配字面的 `notImplemented`，明确排除语义相近的
`rpcRejected(code:"unsupported_interrupt_mode")`。**本轮的 FAIL 正是靠这条区分才没被误降级。**
评审专门构造反例复核了这一点，结论是收口紧的。

## 主会话复核抓到的同族残留

摘要路径里还剩一份硬编码三元素集合，**不参与判定**、只决定点名谁——危害小得多，
但同样会过时。已改为**按结果筛选**，两端残留 0。

## 评审核实了裁定，并修正了一处因果链

**裁定成立**（fixture 没过时，是实现偏离 confirmed §9.3），但**主会话把两条偏离并成了一句**：
本次 FAIL 的近因是 **steer 在拿锁之前就被 mode guard 拒了**，interrupt 压根没进过
`interrupt_in_progress`。**所以「锁矩阵违反 §9.3」这条本次并未被观察到**——
rounds/0023 光实现 steer 不会自动暴露它，得专门构造。

## 意外产出：hopper 的 idle false-kill（已修）

评审连续三次超时、最后一次颗粒无收。追查发现：`bufferedOutput` 标志
**被 `hopper-runner` 尊重、被 `subprocess.js` 忽略**，而 `hopper-dispatch` 走后者。
端到端缓冲的 vendor 因此必在 180s 被杀，30 分钟的 review ceiling 永远轮不到生效。

**同一任务、同一 vendor，只改 idle 上限**：180024ms 被杀 / 0 字节 → **success，399802ms，19883 字节**。
该评审真正需要 6.7 分钟。

**缓解手段存在、有文档、挂了具名 issue——只实现在两条通路的其中一条上。**
与本轮修的 parity 名单同族。已修，`npm test` 1424/1422 pass/0 fail。

## 本轮暴露、留给后续的

`respondApproval` **零 parity 覆盖**（rounds/0015 就实现了，三条 approval fixture 只测事件侧）·
C# 三方法仍是桩（**刻意不实现**，红线）· mimo `idleHeartbeatRe` 同族分歧未修
