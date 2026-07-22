# 金标 parity fixtures（骨架）

对应 D4 跨平台架构 v2.2 §4「金标 parity 测试」，尤其 §4.3「fixture DSL：确定性
action/timeline」。金标 parity 测试是一组**语言中立的契约一致性用例**——每条用例是一条确定性
action/timeline（client 调用、内核 mock 响应/事件、并发、断连/重连、虚拟时钟推进），两端的
kernel-client 驱动/消费同一条 timeline 后，产生的可观察客户端状态与副作用必须逐字段一致
（D4 §4.1 定义）。

**本轮范围（骨架，不求全）**：只放 2 个语言中立 fixture 样例，验证 DSL 结构本身可用；完整的
D1/D2 状态机 fixture 清单（D4 §4.2 表格：审批五态 FSM、`OperationOutcome` 全集+子集、
`SessionLockState`、握手协商、`capability_changed` 边界、断线重连、三层错误模型、
`res.unknown` 分流、`EmptyPayload` 边界）以及三端 runner（Swift/C#/TS，D4 §4.4）均为后续
轮次交付物，不在本轮范围内。

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
在派发前按虚拟时刻 `t` 自动补全，补全后仍须通过 `contracts/d2/schema/` 校验）——本轮的两个
fixture 样例都用了这种省略写法，是合法而非遗漏（本轮暂无 runner 实现，无法真正跑这两条
fixture；`codegen/scripts/validate-schemas.mjs` 只做 JSON 语法自检，不做 shorthand 补全 +
schema 校验，那是 D4 §4.4 三端 runner 的职责）。

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

本轮只有 `basic/`（新增，非 D4 清单里的分类，用于验证最简 DSL）与 `operation-outcome/`
（转录 D4 既定示例，尚未覆盖该分类要求的完整六态+二态+三态子集）。`OPEN.md` 登记惯例（如
`respondApproval` 命中 `FORCE_DENY_PENDING_KERNEL_ACK` 中间态之后到达，D2 v3 §9.2 第 4 条）
本轮未创建，留待补齐完整 fixture 集合时一并处理。三端 runner（`swift-runner/`、
`csharp-runner/`、`ts-runner/`，D4 §4.4）本轮未创建。
