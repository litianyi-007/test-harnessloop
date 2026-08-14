# 金标 parity fixtures（骨架 + SG-1 深化：DSL 正式化/最小 TS runner + SG-8.7 Stage A：Swift 真实 client runner/fixture 扩全 + Stage B：C# 真实 client runner，三端 parity 收官）

对应 D4 跨平台架构 v2.2 §4「金标 parity 测试」，尤其 §4.3「fixture DSL：确定性
action/timeline」。金标 parity 测试是一组**语言中立的契约一致性用例**——每条用例是一条确定性
action/timeline（client 调用、内核 mock 响应/事件、并发、断连/重连、虚拟时钟推进），两端的
kernel-client 驱动/消费同一条 timeline 后，产生的可观察客户端状态与副作用必须逐字段一致
（D4 §4.1 定义）。

**SG-1 深化轮新增**：`dsl.ts` 把此前只以 markdown 代码块形式存在的 D4 §4.3 DSL（`ParityFixture`/
`TimelineOp`/`ClientObservableState` 等）正式化为可被编译器检查、可被 runner `import` 的 TS
类型；`ts-runner/` 是按该 DSL 写的最小 runner，能真正读取本轮两个既有 fixture、驱动一个极简
"假内核"（`mock-kernel-client.ts`）执行 timeline、断言最终状态——**打通 TS 一端作样板**（任务
书原话）。跑法：`npm --prefix ../codegen run run:fixtures`
（或直接 `node ts-runner/runner.ts`，Node 22+ 原生支持直接运行 `.ts` 文件，无需单独构建步骤）。
**SG-8.7 Stage A/B 已分别补齐 Swift/C# 真实 client runner**（见文末「三端 parity」一节）。

**范围仍未求全（SG-1 时的状态，历史记录保留）**：当时只放 2 个语言中立 fixture 样例，验证的是
"DSL 结构 + TS runner 机制本身可用"，不是完整覆盖。**SG-8.7 Stage A 已把 `approval`/
`session-lock`/`operation-outcome` 三组扩到共 10 条新 fixture + Swift 真实 client runner**（见文末
「Swift 金标 parity runner」「三组 fixture 覆盖清单」两节）；**T-048 REWORK 轮**（对抗审 codex 判
REWORK 后的收残，见文末「T-048 REWORK 收残记录」一节）删除了 7 条 fixture 里非法塞进 D2 wire
`message` 的 `_openclaw*` 私有字段、修正一条非法 stop response 形状、补齐两条 approval fixture
缺失的必填字段、把 TS 金标 oracle 从"只覆盖 2 条样例"扩到覆盖全部 13 条（含新增的
`stop-force-denies-pending-approval.json`，覆盖本轮新落地的 D1 §6.2 force-deny 能力）、修正了
Swift `PartialMatch`/`expect_outbound` 与 TS 不等价的假阴性、把 `advance_clock` 的确定性从"固定
sleep 猜调度"改成"轮询任务已结算"的同步钩子。**T-050 REWORK 轮**（confirming 再审 MUST-FIX 收残，
见文末「T-050 REWORK 收残记录」一节）把 `expect_outbound` 从"顺手拿 timeline 的 args 拼一份规范化
请求"改成直接从真实捕获的原生 RPC `params` 现算；把 TS 的 D1 §6.2 force-deny 从"回显 fixture 声明的
`forceResolvedApprovals`"改成自己独立计算；新增 `nativeCallOrder` 断言 force-deny 必须先于 abort；
修了最后一条非法 D2 message；补齐 TS event shorthand 遗漏的 `seq`。握手协商、`capability_changed`
边界、断线重连（除 `disconnect` 触发 transport-closed 外的完整语义）、三层错误模型、`res.unknown`
分流、`EmptyPayload` 边界、C# runner（D4 §4.4）仍是后续轮次交付物，不在本轮范围内。

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
跑 `defaultFixturePaths()` 枚举的默认 13 条清单，与 swift-runner `SwiftRunnerMain.swift`/
csharp-runner `CSharpRunnerMain.cs` 的默认清单一一对应）。**T-048 REWORK 复验**：`node
ts-runner/runner.ts` 对全部 13 条 fixture 跑 **13 PASS / 0 FAIL**。Swift/C# runner
（`swift-runner/`、`csharp-runner/`，D4 §4.4）——见下两节（SG-8.7 Stage A/B 新增）与文末「三端
parity」总节。

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
  T-048 REWORK 这一轮改成方法名匹配后继续对一个『规范化请求』做与 TS `runner.ts` 的 `partialMatch`
  等价的完整子集深度匹配，但那份『规范化请求』其实是把 timeline 的 `args` 原样放回 `payload`、
  `sessionId` 直接取 fixture 声明值——**T-050 REWORK（confirming 再审 MUST-FIX 治根）**指出这仍是
  表面绕过：真实捕获的原生 `params` 存进了 `capturedOutbound` 却从没有代码读它做字段映射，真实
  client 把 `sessions.send.params.message`/`sessions.messages.subscribe.params.key`/
  `sessions.abort.params.key` 发错也不会被抓到。本轮改为 `normalizeNativeParams` 直接从**真实捕获
  的原生 `params`**（不是 timeline 的 `args`）现算：`sessionId` 反查『哪个已声明 session 拥有这个
  原生 key』（`kernelKeyToDeclaredSessionID`），查不到就显式置 `NSNull()`，不 fallback 回声明值；
  `payload` 是 `params` 去掉 `key` 后的剩余字段（`send` 一项把原生 `message` 映射回 D1 `Input.text`
  以便跨语言比较，其余字段原样保留原生字段名）。`basic/`、`operation-outcome/stop-active-run-succeeded.json`
  等多条 fixture 的 pattern 也相应补上了 `sessionId`/`payload.text` 深度断言。已实测反证：临时让
  真实 `sessions.send()` 在 `message` 参数末尾追加一段乱码、临时让真实 `subscribe()` 发一个错误的
  `key`，两个场景下 `expect_outbound` 均立即 FAIL（验证后已复原，未改动
  `OpenclawGatewayKernelClient.swift` 一行）。
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

## C# 金标 parity runner（SG-8.7 Stage B 新增）

`csharp-runner/`（`FixtureDsl.cs` + `PartialMatch.cs` + `CSharpFixtureRunner.cs` +
`CSharpRunnerMain.cs`）逐机制镜像 `swift-runner/`（Swift 侧是本轮的权威参考实现，已过
T-048/T-050/T-051 三轮异构对抗审收敛），驱动的同样不是假内核，而是 SG-5 交付的**真实**
`app/kernel-client/csharp/OpenclawGatewayKernelClient.cs`——同一批 fixture JSON、同一套 DSL，
`client_call` 直接调用真实类的 `CreateSessionAsync`/`SendAsync`/`Subscribe`/`StopAsync`（`Config`/
`Input`/`SessionHandle` 都是 D2 codegen 类型），`mock_response`/`mock_event` 经翻译层转成真实
client 认得的 openclaw 原生 wire 帧/RPC 响应（复用 `app/kernel-client/csharp/tests/FrameReplayTests.cs`
已验证过的 `TestSupportStubRpc`/`TestSupportFeedFrame` 两个钩子），最终 `ClientObservableState`
逐字段来自真实实例状态/真实 `EventMapping.cs` 映射产物的事件流，不是手工构造后短路过去。

**逐机制对照 Swift（从第一行就带着 Stage A 已付学费的纪律，不重新踩坑）**：

- **真 client 驱动**：`client_call` 的 `createSession`/`send`/`subscribe`/`stop` 四个分支各自注册
  `TestSupportStubRpc` 桩（`sessions.create`/`sessions.send`/`sessions.messages.subscribe`/
  `sessions.abort`+`sessions.delete`+`approval.resolve`），再 `Task.Run` 真调用对应的 `*Async`
  方法/`Subscribe`，`ReplyGate`（`lock`+`TaskCompletionSource` 实现，语义对应 Swift `actor
  ReplyGate`）让 RPC 真悬挂到 runner 处理对应 `mock_response` 的那一刻才返回。
- **`expect_outbound` 从真实捕获的 native params 匹配**：`RecordOutbound` 只记录 `TestSupportStubRpc`
  闭包同步收到的原始 `params`（不是 timeline 的 `args`/fixture 声明值）；`NormalizeNativeParams`
  在断言时才现算规范化请求——`sessionId` 反查 `kernelKeyToDeclaredSessionId`（查不到显式置
  `JsonNullMarker.Instance`，不 fallback），`sessions.send` 把原生 `message` 映射回 `text`，逐字
  对应 Swift `normalizeNativeParams`。
- **`nativeCallOrder` 真实调用时刻追加**：`approval.resolve`/`sessions.abort` 两个 stub 闭包**被真实
  client 调用的那一刻**（不是注册的时刻）`AppendNativeCall`，暴露给 `expected.nativeCallOrder` 断言
  （`stop-force-denies-pending-approval.json`）。
- **`advance_clock`/`disconnect` 轮询"任务已结算"**：`PollUntilSettledAsync` 轮询 `ctx.IsCallSettled`
  （复用 `OnStopResolvedAsync`/`OnStopThrewAsync` 写入的 `pendingOperations`/`callOutcomes`），不是
  固定 `Task.Delay` 猜调度；`TestSupportSetStopTimeoutSeconds(1)` 把生产 5 秒超时收窄到 1 秒，真实
  触发 SG-5 内部 `Task.Delay(timeoutSeconds)` 定时器产出 `timed_out`。
- **soft-steer 诚实 DEGRADED**：`DegradeReason` 静态扫描 timeline，含 `interrupt`/`respondApproval`/
  `capabilities` 任一 client_call 就整条标记 DEGRADED（C# `InterruptAsync`/`RespondApprovalAsync`/
  `CapabilitiesAsync` 同样是 SG-5 TODO 桩，`throw KernelClientException(NotImplemented,...)`），不
  伪造假内核让它"通过"。
- **`PartialMatch` 与 TS/Swift 语义等价，但省掉了 Swift 需要的 Bool/NSNumber workaround**：C#
  `object` 装箱后运行时类型精确保留（装箱 `bool` 恒为 `System.Boolean`，不会被启发式误判成数字
  0/1），`ScalarsEqual` 因此不需要 `PartialMatch.swift` 那段 `objCType` 判别逻辑——这是语言运行时
  差异带来的合理简化，`PartialMatch.cs` 文件头注释记录了这个刻意的差异，不是漏做。显式 JSON `null`
  与"字段完全缺失"仍严格区分（`JsonNullMarker.Instance` vs C# `null`，见该文件 `JsonNullMarker` 的
  文档注释——特别记录了这个哨兵值**只能**用于 runner 自己的 actual/expected 统一值域，绝不能泄漏进
  喂给真实 client 的 wire `JSONObject`，那边的『JSON null』语义仍是裸 C# `null`，跟 `OpenclawWire.cs`
  自己的 `ConvertElement` 一致）。

**C# 与 Swift 的表达差异（刻意记录，不是漂移）**：C# 没有 Swift `actor` 隔离，`RunnerContext`/
`ReplyGate` 改用 `lock` 保护可变状态——与 `OpenclawGatewayKernelClient.cs` 自己既定的 `_sync` 模式
一致，不是本 runner 独创；`OpenclawGatewayKernelClient` 的全部 `TestSupport*` 钩子在 C# 侧是**同步**
方法（不像 Swift 需要在几乎每个调用点 `await` actor hop），`RunnerContext` 因此比 Swift 版本少了很多
`async`/`await` 噪音，只有真正跨越 `Task.Delay`（`OnStopResolvedAsync`/`OnStopThrewAsync` 的
event-drain settle、`ApplyMockEventAsync` 的双帧间隔、`ApplyAdvanceClockAsync`/`disconnect` 的轮询）
的地方才是 `async`。

**编译+跑法**（`CSharpRunnerMain.cs` 文件头有同一段可复制命令；不依赖 xunit/NuGet 网络 restore，
直接把 `KernelClient` 项目源文件连同 runner 本体一起编译成一个 Exe，同
`app/kernel-client/csharp/tests/KernelClientTests.csproj` 既定风格）：

```
cd app/contracts/d2/fixtures/csharp-runner
dotnet build
dotnet run --no-build
```

不带参数时按 `CSharpRunnerMain.DefaultFixturePaths()` 枚举的内置清单跑 13 条 fixture（与
`ts-runner/runner.ts`/`swift-runner/SwiftRunnerMain.swift` 的默认清单一一对应），**实测
12 PASS / 0 FAIL / 1 DEGRADED**（`operation-outcome/soft-steer-then-stop.json` 因 timeline 用到
`client_call: interrupt` 被 `DegradeReason` 静态扫描自动标记 DEGRADED，同 Swift 侧同一条、同一原因）。
也可传具体 fixture 路径只跑一部分，如 `dotnet run --no-build -- ../approval/stop-force-denies-pending-approval.json`。

**注意（`dotnet build`/`run` 的产物污染）**：`csharp-runner/` 目录本身在 `fixtures/` 树内，`dotnet
build` 会在原地生成 `bin/`/`obj/`（已 `.gitignore`，同 `app/kernel-client/csharp/.gitignore` 既定
做法），其中含若干 `*.json`（`project.assets.json`/`*.deps.json` 等 NuGet/构建元数据，不是 fixture）。
若要跑本文档「三端 parity」一节给出的 `find app/contracts/d2/fixtures -name '*.json' | ... |
xargs node ts-runner/runner.ts` 这类"扫描全部 fixture json"命令，建议先 `dotnet clean`（或 `rm -rf
csharp-runner/{bin,obj}`）清掉这些构建产物，避免被误当成 fixture 传给 TS/Swift runner。

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

## T-050 REWORK 收残记录（confirming 再审 MUST-FIX，本节汇总，逐条见对应文件内的 `T-050 REWORK` 标注）

T-050（codex confirming 再审，接续自己的 T-048）确认 T-048 REWORK 的 advance_clock/DEGRADED/Swift 6
锁三类缺陷真闭合，但揪出 5 处仍是"表面绕过/绿灯不能证明它声称的东西"，全部收残：

1. **`expect_outbound` 治根**：`normalizeNativeParams`（`SwiftFixtureRunner.swift`）改为直接从真实
   捕获的原生 `params` 现算规范化请求（`sessionId` 反查 `kernelKeyToDeclaredSessionID`，查不到显式
   置 `NSNull()`，不 fallback；`payload` 是 `params` 去掉 `key` 后的剩余原生字段，`send` 一项把
   `message` 映射回 `text`），不再是 T-048 REWORK #4 那版"顺手拿 timeline 的 `args` 拼一份"。多条
   fixture 的 pattern 补上 `sessionId`/`payload.text` 深度断言。反证：临时破坏真实 `send()`/
   `subscribe()` 的对应字段，`expect_outbound` 均真实 FAIL（验证后已复原）。
2. **TS force-deny 从空转改为独立 spec oracle**：`mock-kernel-client.ts` 的 `call()` 处理 'stop' 时
   独立对本地 `approvalState` 执行 D1 §6.2 force-deny（推进 pending reqId 到
   `force_denied_on_stop`、push `nativeCallOrder`），`evt.turn_complete` 转发时用这份自算列表覆盖
   payload，不再读 fixture 声明的 `forceResolvedApprovals` 当输入。反证：临时让这段计算不记录任何
   reqId，`expected.observedEvents[2].payload.forceResolvedApprovals` 立即 FAIL（验证后已复原）。
3. **gold fixture 新增 `nativeCallOrder` 顺序断言**：两端各自独立记录 `approval.resolve`/
   `sessions.abort` 的调用顺序（Swift 在真实 native RPC stub 被调用的那一刻 append；TS 在 `call()`
   的代码顺序里 push），`stop-force-denies-pending-approval.json` 新增 `expected.nativeCallOrder:
   ["approval.resolve", "sessions.abort"]`。反证：临时把真实 `stop()` 里两次 `request()` 调用顺序
   颠倒，该 fixture 立即 FAIL（验证后已复原，未改动 `OpenclawGatewayKernelClient.swift`）。
4. **修最后 1 条非法 D2 message**：`stop-rejected-rpc-failure.json` 的 `res.stop.failure.code:
   "unknown"` 不在 `RejectionFailure | ProtocolFailure` 枚举里——改用 `ProtocolFailure` 的合法值
   `malformed_message`（这次要表达的是底层 RPC 交换本身坏了，属于消息层协议错误）。改完后对全部 13
   条默认 fixture 的 34 条展开 message 跑 Ajv 2020 严格校验（复用 `runner.ts` 导出的
   `expandResponseShorthand`/`expandEventShorthand`，不是另写一份可能漂移的复刻），结果
   `expanded_messages=34 schema_valid=34 schema_invalid=0`。
5. **补 `seq`**：`expandEventShorthand`（`ts-runner/runner.ts`）此前只补 `ts`/`sentAt`/`direction`，
   漏了 `EventMessage` 判别联合每个分支都要求的 `seq`（`common/envelope.schema.json#/$defs/
   eventEnvelopeBase`）。改为按 `sessionId` 分桶维护一个递增计数器（每条 fixture 独立从 1 开始，不
   是模块级共享状态）。反证：临时去掉 `seq` 字段重跑上述 Ajv 校验，34 条里有 6 条（全部 `mock_event`
   展开的消息）变成 schema 不合法；补回后恢复 34/34。

附带修复 `SwiftFixtureRunner.swift` 里 1 条 "no async operations occur within await" warning
（`startDraining` 内 `Task {}` 闭包继承同一 actor 隔离，`self.appendEvent` 不跨隔离域，去掉多余的
`await` 即可）；SG-5 `kernel-client.swift` 的另外 3 条同类 warning 不在本轮 scope，未触碰。

两端复验：`node ts-runner/runner.ts` 全部 13 条 **13 PASS / 0 FAIL**（TS force-deny 现在是自己算的，
不是回显）；swift-fixture-runner **12 PASS / 0 FAIL / 1 DEGRADED**（`expect_outbound` 现在真匹配
native params，`stop-force-denies-pending-approval.json` 断言 RPC 顺序）。

## 三端 parity（SG-8.7 Stage B 收官）

TS（假内核，D1/D2 spec oracle）+ Swift/C#（驱动各自真实 `OpenclawGatewayKernelClient`）三端对同一批
13 条 fixture、同一份 `expected` 逐字段跑 parity，三端各自跑法：

| 端 | 跑法 | 结果 |
|---|---|---|
| TS | `find app/contracts/d2/fixtures -name '*.json' \| sort \| xargs node app/contracts/d2/fixtures/ts-runner/runner.ts`（或 `npm --prefix ../codegen run run:fixtures`） | **13 PASS / 0 FAIL** |
| Swift | `swiftc app/generated/swift/D2.swift app/generated/swift/DiscriminatedUnions.swift app/kernel-client/swift/{KernelClient,OpenclawWire,EventMapping,OpenclawGatewayKernelClient}.swift app/contracts/d2/fixtures/swift-runner/{FixtureDSL,PartialMatch,SwiftFixtureRunner,SwiftRunnerMain}.swift -o /tmp/swift-fixture-runner && /tmp/swift-fixture-runner` | **12 PASS / 1 FAIL / 0 DEGRADED**（rounds/0022 起，见下方） |
| C# | `cd app/contracts/d2/fixtures/csharp-runner && dotnet build && dotnet run --no-build` | **12 PASS / 0 FAIL / 1 DEGRADED** |

（TS 用假内核覆盖全部 13 条，包括用到 `interrupt()` 的 `soft-steer-then-stop.json`——D1/D2 spec 里
`interrupt(mode:'steer')` 是已定义行为，TS oracle 按 spec 实现了它。Swift/C# 驱动的是 SG-5 交付的
真实 client——`capabilities()` 本轮两端仍均是 TODO 桩；`interrupt()`/`respondApproval()` **Swift 侧
已分别在 rounds/0020/0015 落地**，只是 C# 侧仍是 TODO 桩，这正是下方 rounds/0022 一节要讲的分歧。）

### rounds/0022：DEGRADED 判定改为运行时发现，Mac↔Windows 分歧首次可见

此前两端 `DEGRADED` 由**逐字相同的硬编码方法名单** `["interrupt", "respondApproval",
"capabilities"]` 决定——任何 fixture 的 timeline 用到这三个方法名，执行前就整条静态跳过，不问真实
结果。这份名单在 Swift 侧从 rounds/0015（`respondApproval()` 落地）起就已经过期，rounds/0020
（`interrupt(mode:"cancel")` 落地）后错得更彻底——五轮无人察觉，因为套件报的是「12 PASS / 0 FAIL /
1 DEGRADED」，DEGRADED 不计入退出码，`SwiftRunnerMain.swift` 一直如实标注这一点，但摘要本身没有把
「哪些 fixture 被静态挡住、挡住的理由是否还站得住」这件事说清楚。

**改法**：不再查表，直接跑。`interrupt`/`respondApproval`/`capabilities` 现在与
createSession/send/subscribe/stop 走同一条翻译路径，真调用两端各自的 `OpenclawGatewayKernelClient`。
DEGRADED 与否只取决于一件事——这次真实调用抛出的错误，字面上是不是 `notImplemented`
（Swift `KernelClientError.notImplemented`／C# `KernelClientException(NotImplemented,...)`）；任何
其它错误（包括语义上也是"不支持"的 `rpcRejected`）都流入正常的 PASS/FAIL 判定，不被 DEGRADED 收编。

**观察到的分歧**（两端摘要末尾新增的「覆盖判定」区块，逐字段对齐，人工对照即可看出）：

| 端 | `soft-steer-then-stop-waits-not-preempts` 判定 | 为什么 |
|---|---|---|
| Swift | **FAIL**（真实执行，此前从未跑过） | `interrupt()` 对该 fixture 的 `mode:"steer"` 抛的是 `rpcRejected(code:"unsupported_interrupt_mode")`——字面上不是 `notImplemented`，因此不再 DEGRADED；真实执行后，`expect_outbound`/`assert_state`/`expected.pendingOperations` 三处均与 fixture 期望不符（详见下方「实测差异」） |
| C# | 仍 DEGRADED，但理由改为运行时真实捕获 | `InterruptAsync` 本轮无条件 `throw NotImplemented`，判据来自这一次运行实际捕获到的异常，不再是查表 |

**实测差异**（Swift 侧 FAIL 的完整明细）：

```
[FAIL] soft-steer-then-stop-waits-not-preempts
       - expect_outbound(steer1): swift-runner 未登记『req.interrupt』对应的 openclaw RPC 方法名（该 D2 方法本轮 SG-5 未实现，或超出 Stage A 翻译范围）
       - assert_state@t=25.sessionLock: 期望 interrupt_in_progress，实际 stop_in_progress
       - expected.pendingOperations.steer1: 期望 submitted，实际 nil
```

`sessionLock` 那一条尤其说明问题：该 fixture 逐字转录自 D4 spec 的示例，假定「`interrupt` 在途时
`stop()` 到达会排队等待，不被抢占」；而 rounds/0020 落地的真实语义是「`send`/`stop`/`interrupt`
两两互斥，锁不是 idle 一律 `session_locked` 拒绝，不做优先级仲裁」，且本轮只实现了
`mode:"cancel"`。两者本就不是同一件事——运行时发现只是让这个早已存在的落差第一次变得可观察，不是
新引入的问题。**不修复它**（红线：本轮只改判定机制，不改 fixture、不改两端 kernel client）。

**破坏性反证**（临时把判定改回硬编码名单式静态短路，验证后已删除，byte-for-byte 校验无残留）：两端
各自在 `RunFixtureFileAsync`/`runFixtureFile` 里临时插入「`callsUsed` 命中三方法名单即在执行 timeline
前直接返回 DEGRADED」，命中 **1 处**（`soft-steer-then-stop.json`，与「只有这一条 fixture 真正调用
interrupt」的既有事实一致）；注入后两端均恢复为改动前的 `12 PASS / 0 FAIL / 1 DEGRADED`，Swift 侧的
DEGRADED 理由文案变回注入的静态标记（证明真实机制确实在起作用，不是摆设）；还原后 `shasum -a 256`
核对四个改动文件与注入前逐字节相同。

**respondApproval 的覆盖缺口（本轮顺带发现，未修复）**：`respondApproval()` 在 Swift 侧已于
rounds/0015 落地，但枚举全部 13 条 fixture 的 `client_call.call` 取值（`command grep -o
'"call"[[:space:]]*:[[:space:]]*"[a-zA-Z]*"' app/contracts/d2/fixtures/**/*.json`）后确认：**没有
任何一条 fixture 把 `respondApproval` 当作 `client_call` 使用**——三条 `approval/*` fixture 只覆盖
了"审批请求到达、进入 `pending` 态"（事件侧），`stop-force-denies-pending-approval.json` 覆盖的是
`stop()` 内部自动触发的强制 deny（同一条 `approval.resolve` RPC，但走的是 `forceDenyPendingApprovalsBeforeStop`
这条内部路径，不是 D1 §2.6 `respondApproval()` 方法本身）。也就是说，D1 审批状态机的
`RESOLVED_ALLOW`/`RESOLVED_DENY`（真实用户点了"允许"/"拒绝"）**两个终态从未被任何金标 fixture 驱动
过**——这是一个比本节标题问题更值得关注的跨端一致性缺口：`respondApproval()` 的 Swift/C# 分歧（Swift
已实现、C# 仍是桩）此刻完全没有 parity 测试盯着。本轮不补 fixture（写 fixture 不在 scope 内），如实
登记。

**一致性依据**：12 条可驱动 fixture 上，Swift/C# 对同一份 fixture `expected` 做逐字段子集深度匹配
（`PartialMatch.swift`/`PartialMatch.cs`，语义与 TS `partialMatch` 等价，差异只在 C# 不需要 Swift
的 Bool/NSNumber 桥接 workaround，见上文「C# 金标 parity runner」一节），断言维度完全相同：
`pendingOperations`/`callOutcomes`/`approvalState`/`observedEvents`/`sessionLock`/`nativeCallOrder`。
`stop-force-denies-pending-approval.json` 额外要求两端 `nativeCallOrder` 均为
`["approval.resolve","sessions.abort"]`——C# 端已实测通过（见下方反证 2）。`includeApprovals` 等
openclaw 原生特有字段两端均**诚实未跨端断言**（T-051 记录的既定 defer，非遗漏型假闭合）：C# 真实
`Subscribe()` 也发 `includeApprovals:true`（见 `OpenclawGatewayKernelClient.cs`），但 fixture 的
`expect_outbound` 从未在 `req.subscribe` 的 `payload` 里断言该字段——若强行跨端断言会打穿 TS 假内核
（`payload` 恒为 `{}`）与两个 native 端的语义差，Stage A 已判定保持不断言更诚实，Stage B 沿用同一
判断，不新增。

### 3 处"有牙齿"反证（临时改动，验证后已全部还原）

1. **真实 client 发错 native param**：临时把 `OpenclawGatewayKernelClient.cs` `SendAsync` 里的
   `["message"] = ResolveSendMessageText(input)` 改成写死 `"T-STAGEB-TEETH-WRONG-MESSAGE"`，重新
   `dotnet build` 后单跑 `stop-active-run-succeeded.json`：
   ```
   [FAIL] stop-active-run-succeeded
          - expect_outbound(send1).payload.text: 期望 "run something long"，实际 "T-STAGEB-TEETH-WRONG-MESSAGE"
   ```
   `git checkout -- app/kernel-client/csharp/OpenclawGatewayKernelClient.cs` 还原，`git status`
   确认无残留。
2. **交换 stop() 的 force-deny/abort 调用顺序**：临时把 `StopAsync` 里
   `ForceDenyPendingApprovalsBeforeStopAsync(...)` 与 `RequestAsync("sessions.abort", ...)` 两行
   互换（abort 先发），单跑 `stop-force-denies-pending-approval.json`：
   ```
   [FAIL] stop-force-denies-pending-approval
          - assert_state@t=36.nativeCallOrder: 期望长度 2，实际长度 1
          - expected.nativeCallOrder[0]: 期望 "approval.resolve"，实际 "sessions.abort"
          - expected.nativeCallOrder[1]: 期望 "sessions.abort"，实际 "approval.resolve"
   ```
   还原后同一命令恢复 PASS，`git status` 确认无残留。
3. **破坏 `PartialMatch`**：临时把 `PartialMatch.cs` 的字符串比较从 `sa == sb` 反转成 `sa != sb`
   （标量匹配核心），重新 `dotnet build` 后跑全部 13 条：
   ```
   === 0 PASS / 12 FAIL / 1 DEGRADED （共 13 条 fixture） ===
   ```
   12 条可驱动 fixture 全部真实 FAIL（证明 `PartialMatch` 不是被绕过的桩，逐条断言真的在被求值），
   还原后恢复 `12 PASS / 0 FAIL / 1 DEGRADED`。`csharp-runner/PartialMatch.cs` 是 Stage B 本轮新增
   文件（未纳入 git），手工核对还原后内容与上文「逐机制对照」描述一致，非 git diff（无历史版本可
   比对）。

### 已知边界（诚实记录，非隐瞒）

- `csharp-runner/` 未包含在既有 SG-5 frame-replay 测试范围内，是本轮新写的独立可执行程序；三端
  parity 的"跨端一致"结论仅覆盖本 README 引用的 13 条金标 fixture，不代表覆盖 D1/D2 全部方法/
  事件类型（见前两节「未覆盖/后续轮次」「三组 fixture 覆盖清单」的既有 TODO 登记，Stage B 未扩大
  fixture 覆盖面，只补齐 C# 驱动端）。
- 未发现真实跨端 parity bug——12 条可驱动 fixture 在 TS/Swift/C# 三端对同一 `expected` 逐字段一致
  PASS，无需报告 blocker。
