# 金标 parity fixtures（骨架 + SG-1 深化：DSL 正式化/最小 TS runner + SG-8.7 Stage A：Swift 真实 client runner/fixture 扩全）

对应 D4 跨平台架构 v2.2 §4「金标 parity 测试」，尤其 §4.3「fixture DSL：确定性
action/timeline」。金标 parity 测试是一组**语言中立的契约一致性用例**——每条用例是一条确定性
action/timeline（client 调用、内核 mock 响应/事件、并发、断连/重连、虚拟时钟推进），两端的
kernel-client 驱动/消费同一条 timeline 后，产生的可观察客户端状态与副作用必须逐字段一致
（D4 §4.1 定义）。

**SG-1 深化轮新增**：`dsl.ts` 把此前只以 markdown 代码块形式存在的 D4 §4.3 DSL（`ParityFixture`/
`TimelineOp`/`ClientObservableState` 等）正式化为可被编译器检查、可被 runner `import` 的 TS
类型；`ts-runner/` 是按该 DSL 写的最小 runner，能真正读取本轮两个既有 fixture、驱动一个极简
"假内核"（`mock-kernel-client.ts`）执行 timeline、断言最终状态——**打通 TS 一端作样板**（任务
书原话），Swift/C# runner 未做，见文末 TODO。跑法：`npm --prefix ../codegen run run:fixtures`
（或直接 `node ts-runner/runner.ts`，Node 22+ 原生支持直接运行 `.ts` 文件，无需单独构建步骤）。

**范围仍未求全（SG-1 时的状态，历史记录保留）**：当时只放 2 个语言中立 fixture 样例，验证的是
"DSL 结构 + TS runner 机制本身可用"，不是完整覆盖。**SG-8.7 Stage A 已把 `approval`/
`session-lock`/`operation-outcome` 三组扩到共 10 条新 fixture + Swift 真实 client runner**（见文末
「Swift 金标 parity runner」「三组 fixture 覆盖清单」两节）；**T-048 REWORK 轮**（对抗审 codex 判
REWORK 后的收残，见文末「T-048 REWORK 收残记录」一节）删除了 7 条 fixture 里非法塞进 D2 wire
`message` 的 `_openclaw*` 私有字段、修正一条非法 stop response 形状、补齐两条 approval fixture
缺失的必填字段、把 TS 金标 oracle 从"只覆盖 2 条样例"扩到覆盖全部 13 条（含新增的
`stop-force-denies-pending-approval.json`，覆盖本轮新落地的 D1 §6.2 force-deny 能力）、修正了
Swift `PartialMatch`/`expect_outbound` 与 TS 不等价的假阴性、把 `advance_clock` 的确定性从"固定
sleep 猜调度"改成"轮询任务已结算"的同步钩子。握手协商、`capability_changed` 边界、断线重连（除
`disconnect` 触发 transport-closed 外的完整语义）、三层错误模型、`res.unknown` 分流、`EmptyPayload`
边界、C# runner（D4 §4.4）仍是后续轮次交付物，不在本轮范围内。

## fixture DSL 结构（引 D4 §4.3，摘要）

```ts
interface ParityFixture {
  name: string;
  description: string;
  initialState?: Partial<ClientObservableState>;
  timeline: TimelineOp[];              // 按 t（虚拟时刻，毫秒）升序排列的动作序列
  expected: Partial<ClientObservableState>;
}

type TimelineOp =
  | { t; op: 'client_call'; id?; call; args }        // 调用 kernel-client 的一个方法
  | { t; op: 'expect_outbound'; matches; pattern }    // 断言 client 确实发出了匹配的 outbound 消息
  | { t; op: 'mock_response'; replyTo; message }      // 模拟内核对某条 outbound 消息的响应
  | { t; op: 'mock_event'; message }                  // 模拟内核主动推送一个 event
  | { t; op: 'disconnect' } | { t; op: 'reconnect' }  // 模拟传输层断开/重连
  | { t; op: 'advance_clock'; ms }                    // 虚拟时钟前进（不阻塞真实线程）
  | { t; op: 'assert_state'; expected };              // 时间轴中途断言点
```

`mock_response`/`mock_event` 的 `message` 字段是 **shorthand**（`WireResponseShorthand`/
`WireEventShorthand`，D4 §4.3 v2.2 收残：省略 `sentAt`/`direction`/`id`/`seq`，由 runner
在派发前按虚拟时刻 `t` 自动补全）——本轮的两个 fixture 样例都用了这种省略写法，是合法而非遗漏。
**SG-1 深化更新**：`ts-runner/runner.ts` 现已实现 shorthand 自动补全逻辑（`expandResponseShorthand`/
`expandEventShorthand`），两条 fixture 均可用 `npm --prefix ../codegen run run:fixtures` 真正
跑通并断言通过；`codegen/scripts/validate-schemas.mjs` 仍只做 JSON 语法自检，不做 shorthand
补全 + schema 校验（职责边界不变，那是 runner 的职责）。

**T-048 REWORK 新增**：`mock_event` 这一支 TimelineOp 多了一个可选的兄弟字段 `driverHint`
（`MockEventDriverHint`，见 `dsl.ts`）——用于表达『某个 D2 事件在真实 openclaw 原生协议里由多条
独立 wire 帧联合 join 而成时，测试要驱动这些原生帧以什么顺序到达』这类**纯翻译层测试控制信息**，
刻意不放进 `message`（那是封闭的 D2 判别联合，`additionalProperties:false`，容不下任何非 D2
字段）。目前唯一的取值是 `approvalJoinOrder: 'agent_first' | 'session_first'`（`evt.approval_request`
专属，见 `approval/pending-request-*.json` 两条 fixture），TS `MockKernelClient` 完全忽略本字段
（它不模拟原生双帧 join），只有 Swift/C# 这类驱动真实 client 的 runner 会读取。

`ClientObservableState` 关键字段：`sessionLock`（`SessionLockState` 四态）、
`approvalState`、`capabilitySnapshot`、`pendingOperations`（`operationId` → `OperationOutcome`）、
`callOutcomes`（不产生 `operationId` 的方法调用结果，失败联合含 `RejectionFailure |
ProtocolFailure | BillingQueryFailure`）、`observedEvents`（`subscribe()` 收到的事件回调
顺序）。完整定义见 D4 §4.3。

## 本轮的两个样例

| 文件 | 场景 | 展示的 DSL 特性 |
|---|---|---|
| `basic/create-session-subscribe-message-delta.json` | createSession 成功 → subscribe 建流 → 推送一条 `evt.message.delta` | 最简单的 DSL 形态：`client_call`/`expect_outbound`/`mock_response`/`mock_event` 顺序执行，无并发/超时 |
| `operation-outcome/soft-steer-then-stop.json` | `interrupt(mode:'steer')` 在途时 `stop()` 到达——适配器须等待，不得截断 | 并发表达（两个 `client_call` 落在同一条"在途窗口"内）、`assert_state` 中途断言；**逐字转录自 D4 v2.2 §4.3 已定稿的既定金标示例**（非本轮新写），代表 D1 §9.3 session 锁互斥矩阵的核心场景 |

## 未覆盖 / 后续轮次（TODO，引 D4 §4.2/§4.3 fixture 目录组织）

D4 §4.3 定义的完整目录结构（本轮未创建）：

```
parity/
  fixtures/
    approval-fsm/*.json           # 审批五态 FSM 逐条转移
    operation-outcome/*.json      # hard 六态 + soft 二态 + stop() 三态子集
    session-lock/*.json           # SessionLockState 四态完整互斥矩阵
    handshake/*.json              # protocolVersion 握手协商三类结果
    capability-changed/*.json     # schema-negative + reconnect-handshake 两条
    reconnect/*.json              # 断线重连 / 事件不重放
    error-model/*.json            # 三层错误模型不串号
    OPEN.md                       # 登记 D1/D2 尚未裁决、暂不构造肯定性 fixture 的场景
  conformance/                    # 协议声明 vs D1 方法清单的静态比对，非 fixture
```

现有 `basic/`（非 D4 清单里的分类，用于验证最简 DSL）与 `operation-outcome/`（转录 D4 既定
示例，尚未覆盖该分类要求的完整六态+二态+三态子集）。`OPEN.md` 登记惯例（如 `respondApproval`
命中 `FORCE_DENY_PENDING_KERNEL_ACK` 中间态之后到达，D2 v3 §9.2 第 4 条）仍未创建，留待补齐
完整 fixture 集合时一并处理。

## DSL 正式化 + TS runner（SG-1 深化新增）

- `dsl.ts`：`ParityFixture`/`TimelineOp`/`ClientObservableState`/`WireResponseShorthand`/
  `WireEventShorthand` 等类型的正式 TS 声明，`WireResponseShorthand`/`WireEventShorthand` 直接
  `import type` `../../../generated/ts/d2`（schema codegen 产物）的 `ResponseMessage`/
  `EventMessage`，与 wire 消息 schema 保持单一来源。
- `ts-runner/mock-kernel-client.ts`：D4 §1.4/§4.4 所称的"开发期契约 oracle"——**T-048 REWORK 已从
  SG-1 时"只覆盖 2 个 fixture"的极简版扩到覆盖本轮全部 13 条**：`send()`/`stop()` 的锁互斥矩阵
  （D1 v3.1 §9.3 规则 1：非 idle 一律 `session_locked` 同步拒绝，不发 outbound；interrupt_in_progress
  期间 stop() 排队不抢占是既有的唯一例外）、stop() 的 OperationOutcome 因果链（有/无 active run、
  RPC 失败、terminal-observed/timed-out/transport-closed 三条互斥收尾路径）、approvalState 记账。
  **核心原则**：这些行为直接从 D1/D2 spec 写出，不是照抄 swift-runner 观察到的真实 client 行为
  再誊抄一遍——否则两端 parity 只是"互相抄"的空转（T-048 codex 对抗审的核心批评），一旦真实
  client 出现偏离 spec 的 bug，两边会一起错得一致。仍然如实标注的简化：`respondApproval`/
  `capabilities`/`queryBilling` 只做"发出 outbound + 等待 resolve/reject"，不模拟业务规则；
  `interrupt` 只实现 soft-steer-then-stop 需要的这一条转移。
- `ts-runner/runner.ts`：读取 fixture、按 timeline 顺序执行、展开 shorthand、比对
  `expected`/`assert_state` 与实际可观察状态（子集深度匹配），报告每条 mismatch。**T-048 REWORK**：
  `advance_clock`/`disconnect` 此前只是记录、不触发任何转移，现已接到
  `MockKernelClient.advanceClock`/`disconnect`（仅在有 stop() 正等待 active run 终态确认时才有
  意义，窄范围声明与 swift-runner 对齐）。
- **已知简化**（如实标注，非"完整 D4 §4.4 runner"）：不实现断线重连（`reconnect`）语义；
  `expect_outbound` 是子集匹配，不做完整 schema 校验（那是 `codegen/scripts/validate-schemas.mjs`
  的职责，不重复）。

跑法：`npm --prefix ../codegen run run:fixtures`（先 `npm run typecheck:fixtures-runner`
用 `tsc --strict` 校验类型，再实际执行），或直接
`node app/contracts/d2/fixtures/ts-runner/runner.ts <fixture ...>` 指定任意子集/全集（不带参数时
跑 `defaultFixturePaths()` 枚举的默认 13 条清单，与 swift-runner `SwiftRunnerMain.swift` 的默认
清单一一对应）。**T-048 REWORK 复验**：`node ts-runner/runner.ts` 对全部 13 条 fixture 跑
**13 PASS / 0 FAIL**。Swift/C# runner（`swift-runner/`、`csharp-runner/`，D4 §4.4）——Swift 见
下一节（SG-8.7 Stage A 新增），C# 仍未创建，TODO。

## Swift 金标 parity runner（SG-8.7 Stage A 新增）

`swift-runner/`（`FixtureDSL.swift` + `PartialMatch.swift` + `SwiftFixtureRunner.swift` +
`SwiftRunnerMain.swift`）驱动的不是一个假内核，而是 SG-5 交付的**真实**
`app/kernel-client/swift/OpenclawGatewayKernelClient.swift`——同一批 fixture JSON，同一套 DSL，
`client_call` 直接调用真实 actor 的 `createSession`/`send`/`subscribe`/`stop` 方法（Config/Input/
SessionHandle 都是 D2 codegen 类型，跟真实方法签名完全一致，无需转换），`mock_response`/`mock_event`
经翻译层转成真实 client 认得的 openclaw 原生 wire 帧/RPC 响应（复用
`app/kernel-client/swift/FrameReplayTests.swift` 已验证过的 `testSupportStubRPC`/
`testSupportFeedFrame` 两个钩子），最终 `ClientObservableState` 逐字段来自真实 actor 状态/真实
`EventMapping.swift` 映射产物的事件流，不是手工构造后短路过去。

**为什么需要翻译层**：fixture 的 `mock_response`/`mock_event` 是 D2 canonical 形状（`WireResponseShorthand`/
`WireEventShorthand`），TS 的 `MockKernelClient` 本身就是 D1 KernelPort 的假内核，wire 协议等于 D2，
可以直接消费；但 `OpenclawGatewayKernelClient` 是真实适配器，一侧对 D1（D2 类型参数），另一侧对
openclaw Gateway 原生协议（`{type:"req/res/event", method, event, payload}`，与 D2 形状完全不同）——
D2 事件是 `EventMapping.swift` 的映射**产物**，wire 上从不直接出现。翻译层解决『喂什么原生输入才能让
真实代码路径产出 fixture 想要的可观察后果』，输出永远来自真实 mapper，不是伪造。

**T-048 REWORK（对抗审 codex 判 REWORK 后的收残，详见文末专节）核心变化**：
- 此前 7 条新增 fixture 把 `_openclawAbortAck`/`_openclawLifecycle`/`_openclawJoinOrder` 三个非 D2
  字段塞进 `WireResponseShorthand`/`WireEventShorthand` 的 `message`——违反这些类型『直接等于封闭
  D2 判别联合，`additionalProperties:false`』的约束。现已**全部删除**：`sessions.abort` 原生 ack
  该携带的 `abortedRunId`/`status` 改从合法 canonical 字段（`ctx.currentRunIDValue`，即『此前是否
  已有一个 send() 真实 resolve 出一个 runId』）无歧义派生；`evt.turn_complete` 在 Stage A 唯一的
  用途（合成 stop() 等待中的 aborted lifecycle 终态信号）直接硬编码 `phase:"end"`/`aborted:true`；
  `evt.approval_request` 的原生双帧到达顺序改读 DSL 层面显式声明的 `driverHint.approvalJoinOrder`
  （见上文「DSL 正式化」一节），不在封闭的 D2 `message` 联合里。
- `expect_outbound` 此前只比对 `pattern.type`（底层 openclaw RPC 方法名），完全丢弃其余断言字段——
  现在方法名匹配后，继续对一个『规范化请求』（`type` + 可选 `sessionId` + `payload`，在捕获真实
  outbound 的同一时刻构造）做与 TS `runner.ts` 的 `partialMatch` **等价**的完整子集深度匹配，让
  basic fixture 的 `sessionId` 等断言在 Swift 端也真正生效。`sessionId` 用 fixture 自己在
  `res.createSession` 里声明过的值（如 "session-1"），不是真实 client 内部铸造的随机
  `SessionHandle.sessionID`（那个仍然不可断言，原因不变，见下一段）。
- `PartialMatch.swift` 修正了与 TS `partialMatch` 不等价的假阴性：显式 JSON `null` 与『字段完全
  缺失』此前被混为一谈（TS `undefined === null` 是 `false`，旧版一律放行）；Foundation 把 `Bool`
  桥接成 `NSNumber` 后，`true`/`1`、`false`/`0` 曾被误判相等——**实测发现这个问题比预期更深**：
  Swift 的 NSNumber<->Bool 桥接是按数值是否恰好是 0/1 做启发式判断，不是按类型，`is Bool`/
  `as? Bool` 对『刚好是 0/1 的真整数』（如 basic fixture 的 `payload.index:0`）同样会误判为
  Bool，改查 `objCType`（CFBoolean 桥接来的 NSNumber 恒为 `"c"`，Codable 整数是 `"q"`）才可靠
  区分；大整数经 Double 比较丢失精度的问题也已修（优先精确 Int64 比较）。

**`sessionId`/`operationId` 仍不可断言字面值**——真实 client 内部铸造的随机 UUID
（`createSession()`/`stop()` 各自 `UUID().uuidString`，`createSession()` 甚至明确不复用 openclaw
自己返回的 `sessionId`，见 `OpenclawGatewayKernelClient.swift` 该处文档注释），fixture 无法预先
声明字面值。`pendingOperations` 按 dsl.ts 允许的『client_call 的 id』做键。详细设计说明、已知边界
见 `swift-runner/SwiftFixtureRunner.swift` 文件头注释。

**虚拟时钟 / `advance_clock`**：SG-5 的 `stop()` 超时机制基于 `Task.sleep` 真实挂钟时间，没有可注入
的虚拟时钟接口（Stage A 只读复用 SG-5，未改动）。runner 复用 SG-5 已提供的测试专用钩子
`testSupportSetStopTimeoutSeconds` 把生产 5 秒超时收窄到 1 秒——**T-048 REWORK #5**：此前用『固定
sleep 猜调度』（mock_response 后固定 50ms 窗口 + advance_clock 再加固定 400ms slack）判断 SG-5
内部定时器"应该"已经到期，高负载下两次固定猜测都可能不够，导致断言抢跑（codex 复现）。现在改用
显式『任务已结算』同步钩子：轮询 `ctx.isCallSettled(id:)`（复用 runner 自己在
`onStopResolved`/`onStopThrew` 里写入的 `pendingOperations`/`callOutcomes`，正是随后 `assert_state`
要读的同一份状态）直到 SG-5 内部定时器真正到期、`stop()` 走完收尾链路、真正把结果写定为止，不再
凭空猜测该等多久（`disconnect` op 的等待同理改为轮询）。真实触发机制完全不变——`resolvePendingStopWaiter(outcome:.timedOut)` 依旧是 SG-5 内部真实的
`Task.sleep` 定时器触发，未改 SG-5 一个字节。已验证：连续多次跑（含人为加满 CPU 负载的压力测试）
结果稳定为 `stop-timed-out.json` 单独耗时约 1.6 秒，整条 suite 约 7 秒，无 flake。

**编译+跑法**（`swift-runner/SwiftRunnerMain.swift` 文件头有同一段可复制命令）：

```
swiftc app/generated/swift/D2.swift app/generated/swift/DiscriminatedUnions.swift \
       app/kernel-client/swift/KernelClient.swift app/kernel-client/swift/OpenclawWire.swift \
       app/kernel-client/swift/EventMapping.swift \
       app/kernel-client/swift/OpenclawGatewayKernelClient.swift \
       app/contracts/d2/fixtures/swift-runner/FixtureDSL.swift \
       app/contracts/d2/fixtures/swift-runner/PartialMatch.swift \
       app/contracts/d2/fixtures/swift-runner/SwiftFixtureRunner.swift \
       app/contracts/d2/fixtures/swift-runner/SwiftRunnerMain.swift \
       -o /tmp/swift-fixture-runner && /tmp/swift-fixture-runner
```

不带参数时按内置清单跑 13 条 fixture（`basic/`/`operation-outcome/`/`session-lock/`/`approval/`
全部，含 T-048 REWORK 新增的 `approval/stop-force-denies-pending-approval.json`），**T-048 REWORK
复验实测 12 PASS / 0 FAIL / 1 DEGRADED**（`operation-outcome/soft-steer-then-stop.json` 因 timeline
用到 `client_call: interrupt`——SG-5 该方法仍是 TODO 桩——被 `degradeReason(for:)` 静态扫描自动标记
DEGRADED，不计入 PASS/FAIL，也不强行伪造通过；该 fixture 本轮已补上 `createSession`/`subscribe`
前置步骤，修正了此前"从未 createSession 就调 interrupt/stop"的独立缺陷，DEGRADED 只是覆盖缺口，
不再掩盖其它问题），整条 suite 约 7 秒（`stop-timed-out.json` 单独约 1.6 秒），连续多次 + 人为加满
CPU 负载复验均稳定无 flake。也可传具体 fixture 路径只跑一部分。

## 三组 fixture 覆盖清单（SG-8.7 Stage A 新增，供 Swift 真实 client parity 用）

### `operation-outcome/`（`OperationOutcome` 七态：`succeeded`/`submitted`/`aborted_no_resend`/`aborted_resend_failed`/`aborted_effect_unknown`/`rejected`/`timed_out`）

| 文件 | 覆盖的 outcome | 场景 |
|---|---|---|
| `soft-steer-then-stop.json`（既有，SG-1 转录） | `submitted`（经 interrupt） | interrupt(steer) 在途时 stop() 到达——**Swift 侧 DEGRADED**：需要 `client_call: interrupt`，SG-5 该方法仍是 TODO 桩，见 `session-lock/OPEN.md` |
| `stop-no-active-run-succeeded.json` | `succeeded` | stop() 时无 active run，sessions.abort 诚实回报 `abortedRunId:null` |
| `stop-active-run-succeeded.json` | `succeeded`（有 active run 分支） | send() 产生 run-1 后 stop()，真实 aborted lifecycle 帧唤醒等待，产出 operation_completed+turn_complete(cancelled)+session_end 三件套 |
| `stop-timed-out.json` | `timed_out` | 有 active run 但从未收到 aborted lifecycle 帧——真实触发 SG-5 内部超时定时器 |
| `stop-rejected-rpc-failure.json` | `rejected` | 底层 sessions.abort RPC 本身抛错（M3 catch 分支：释放锁+清理+补发 rejected 镜像） |
| `stop-transport-closed-aborted-effect-unknown.json` | `aborted_effect_unknown` | stop() 等待终态期间传输层关闭（NOTE-1 T-047 真挂起 bug 修复路径） |

`submitted`（经非降级路径）/`aborted_no_resend`/`aborted_resend_failed` 三态**本轮未构造肯定性
fixture**——均需要 `interrupt()` 真正落地才能驱动真实 client 到达，SG-5 该方法仍是 TODO 桩，详见
`approval/OPEN.md`/`session-lock/OPEN.md` 的对应说明（诚实登记，不伪造）。

### `session-lock/`（`SessionLockState` 四态：`idle`/`send_pending`/`interrupt_in_progress`/`stop_in_progress`）

| 文件 | 覆盖的转移 |
|---|---|
| `send-in-flight-send-pending.json` | `idle → send_pending`（send() 真实在途）`→ idle`（ack 到达自动释放） |
| `send-in-flight-rejects-concurrent-stop.json` | `send_pending` 期间并发 `stop()` 被真实拒绝（`session_locked`，走 `callOutcomes` 不是 `pendingOperations`——发生在 operationId 铸造之前） |
| `stop-no-active-run-idle-transitions.json` | `idle → stop_in_progress`（stop() 真实在途，期间并发 `send()` 被拒绝）`→ idle` |

`interrupt_in_progress` 本轮**不可达**——SG-5 的锁状态机本身只声明三态（无
`interruptInProgress` case），`interrupt()` 调用即抛 `notImplemented`，没有任何转移可驱动。详见
`session-lock/OPEN.md`。

### `approval/`（D1 §6.2 审批状态机五态：`PENDING` + 四终态 `RESOLVED_ALLOW`/`RESOLVED_DENY`/`TIMED_OUT_DENY`/`FORCE_DENIED_ON_STOP`）

| 文件 | 覆盖的状态 |
|---|---|
| `pending-request-agent-first.json` | `PENDING`，`agent(stream:approval)` 帧先于 `session.approval(pending)` 到达（M1 双向 join 的一个方向，到达顺序声明在 `driverHint.approvalJoinOrder`，见 DSL 正式化一节） |
| `pending-request-session-first.json` | `PENDING`，到达顺序相反——`session.approval` 先被缓冲，等 agent 帧补上 `{runId,toolCallId}` 才补发（T-045 codex 复现过的回归缺陷修复路径） |
| `stop-force-denies-pending-approval.json`（T-048 REWORK 新增） | `FORCE_DENIED_ON_STOP`——`stop()` 在发起 `sessions.abort` 之前先对 pending 审批发 `approval.resolve`(deny) 并等待内核确认，`TurnCompleteEvent.forceResolvedApprovals` 含该 reqId |

`RESOLVED_ALLOW`/`RESOLVED_DENY`/`TIMED_OUT_DENY` 三个终态本轮**仍不可达**：前两者需要
`respondApproval()`（TODO 桩）；`TIMED_OUT_DENY` 需要 `session.approval(phase:"terminal")` 的映射
（`EventMapping.swift` 自己明确标注"D1 11 变体没有它的对应位置"，如实跳过）。**`FORCE_DENIED_ON_STOP`
本轮已随 SG-5 `stop()` 的 D1 §6.2 force-deny 补丁落地**（复用 openclaw 统一 `approval.resolve`
RPC）——Stage A 核查曾发现这一步骤在真实 `stop()` 里完全没有实现（两处
`TurnCompleteEventMessagePayload` 构造点都硬编码 `forceResolvedApprovals: nil`）这一真实一致性
缺口，本轮已修复并新增 `stop-force-denies-pending-approval.json` 覆盖，两端 runner 均驱动通过。
详见 `approval/OPEN.md`。

## T-048 REWORK 收残记录（对抗审 codex 判 REWORK，本节汇总，逐条见对应文件内的 `T-048 REWORK` 标注）

T-048（对抗审）确认 Swift runner 确实驱动 SG-5 真实 client（非 mock）、`advance_clock` 确实触发
`timed_out`、覆盖缺口确因 SG-5 桩卡住——但揪出 4 类必须返工的真缺陷，本轮逐条收残：

1. **删除臆造非 D2 字段**：7 条 fixture 里的 `_openclawAbortAck`/`_openclawLifecycle`/
   `_openclawJoinOrder` 全部删除——`abortedRunId`/`status` 改从合法 canonical 字段
   （`ctx.currentRunIDValue`）无歧义派生；`evt.turn_complete` 的合成信号直接硬编码；
   `approvalJoinOrder` 迁到 DSL 层面显式声明的 `driverHint` 兄弟字段（不在封闭的 D2 `message`
   联合里）。
2. **修非法 D2 形状**：`stop-transport-closed-aborted-effect-unknown.json` 曾写
   `res.stop.result.outcome:"aborted_effect_unknown"`，但 `methods/stop.schema.json` 只允许
   `succeeded|timed_out|rejected`——改为 `succeeded`（诚实表达"底层 RPC ack 本身成功"，最终
   outcome 由 disconnect 触发的真实因果链路产出）；两条 approval fixture 补齐了 D2 必填的内部
   不透明 `payload` 字段（`events/approval-request.schema.json` 的 `ApprovalRequestPayload.payload`
   required）。
3. **两端金标 parity**：`ts-runner/mock-kernel-client.ts` 从"只覆盖 2 个 fixture"扩到覆盖全部 13
   条——`send()`/`stop()` 锁互斥矩阵、stop() 的 OperationOutcome 因果链（有/无 active run、RPC
   失败、terminal-observed/timed-out/transport-closed 三条互斥收尾路径）、approvalState 记账，
   均从 D1/D2 spec 写出，不照抄 Swift 观察到的行为。`node ts-runner/runner.ts` 全部 13 条
   **13 PASS / 0 FAIL**；swift-fixture-runner **12 PASS / 0 FAIL / 1 DEGRADED**。
4. **`expect_outbound` 改全 pattern 匹配**：方法名匹配后继续对规范化请求（`type`+可选
   `sessionId`+`payload`）做与 TS `partialMatch` 等价的完整子集深度匹配。`PartialMatch.swift`
   同步修正三类假阴性（显式 null vs 字段缺失、Bool/NSNumber 桥接、大整数精度），详见上文
   「Swift 金标 parity runner」一节。

另有 3 项非"4 类缺陷"但任务书要求的修项：**advance_clock 同步钩子化**（轮询"任务已结算"取代固定
sleep，见上文）；**soft-steer-then-stop.json 补 createSession 前置步骤**（修正 DEGRADED 掩盖的独立
错误，同步更正 `session-lock/OPEN.md` 的错误声称）；**stop-force-denies-pending-approval.json 新增**
（覆盖本轮新落地的 D1 §6.2 force-deny 能力，两端一致）。`SwiftFixtureRunner.swift` 的 `ReplyGate`
改用 `actor` 取代 `NSLock`（Swift 6 language mode 下 `NSLock.lock/unlock` 在 async 上下文会是编译
错误，`swiftc` 实测复现过这条警告，现已消除）。
