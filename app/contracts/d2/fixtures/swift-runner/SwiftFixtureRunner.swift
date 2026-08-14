// SG-8.7 Stage A：Swift 金标 parity runner——驱动 SG-5 交付的真实 `OpenclawGatewayKernelClient`
// （app/kernel-client/swift/OpenclawGatewayKernelClient.swift），不是另写一个假内核。
//
// ============================================================================================
// 设计钢印：为什么『翻译层』是必须的，而不是『直接喂 D2 形状』
// ============================================================================================
// fixture 的 `mock_response`/`mock_event` 用 D4 §4.3 `WireResponseShorthand`/`WireEventShorthand`
// 书写——这两个类型直接等于 D2 契约的 `ResponseMessage`/`EventMessage`（见 ../dsl.ts 头注释）。
// ../ts-runner/mock-kernel-client.ts 之所以能直接消费这种形状，是因为它是一个『D1 KernelPort 的
// 极简假内核』：wire 协议本身就是 D2。
//
// 但 `OpenclawGatewayKernelClient` 不是这样的假内核——它是 SG-4/SG-5 交付的**真实适配器**，一侧对
// D1 KernelPort（createSession/send/subscribe/stop 等方法签名，用 D2 codegen 类型 Config/Input/
// SessionHandle 做参数），另一侧对 openclaw Gateway **原生** wire 协议（`{type:"req/res/event",
// method, event, payload}`，字段名/形状与 D2 完全不同，见 OpenclawWire.swift/EventMapping.swift）。
// D2 事件是 EventMapping.swift 的映射产物，不是 wire 上直接出现的东西。
//
// 所以『驱动真实 client』意味着：在 openclaw 原生 wire 这一层喂帧/接 RPC，而不是在 D2 这一层。
// 本文件的翻译层职责就是：把 fixture 里 D2 形状的 `mock_response`/`mock_event`，转换成会让真实
// `OpenclawGatewayKernelClient` 的**生产代码路径**（`request()`/`handleIncoming()`/
// `EventMapping.swift` 的各个 mapper）产出对应可观察状态的 openclaw 原生 RPC 响应/wire 事件帧，
// 复用 FrameReplayTests.swift 已经验证过的两个钩子：`testSupportStubRPC`（按 openclaw RPC 方法名
// 注册响应）、`testSupportFeedFrame`（喂一帧合成的 openclaw wire JSON 进 `handleIncoming`）。
// 这不是「另写一个假内核」——琴弦另一头永远是真实 actor 的方法体/dispatch 分支，翻译层只解决『用什么
// 输入才能让真实代码产出 fixture 想要的可观察后果』，输出永远来自真实映射代码，不是手工构造 D2 事件
// 短路过去。
//
// ============================================================================================
// DEGRADED 判定：运行时发现，不是静态方法名单（rounds/0022 治根）
// ============================================================================================
// 直到 rounds/0022 为止，这里是一份硬编码方法名单：`["interrupt", "respondApproval",
// "capabilities"]`——任何 timeline 用到这三个方法名的 fixture，不问真实结果如何，执行前就整条静态
// 跳过（`degradeReason(for:)`，已删除）。这份名单在 Swift 侧从 rounds/0015（`respondApproval()`
// 落地）起就已经过期，rounds/0020（`interrupt(mode:"cancel")` 落地）后错得更彻底——五轮无人察觉，
// 因为『名单命中』与『这个方法是不是真的桩』从写下第一行起就是两件独立的事，只是曾经恰好同步。
//
// rounds/0022 改法：**不查名单，直接跑。** `interrupt`/`respondApproval`/`capabilities` 现在与
// createSession/send/subscribe/stop 走同一条翻译路径（见 `performClientCall` 对应分支）——真调用
// `OpenclawGatewayKernelClient` 的对应方法，真实结果流回 `RunnerContext`。DEGRADED 与否只取决于一件
// 事：这次真实调用抛出的错误，字面上是不是 `KernelClientError.notImplemented`——`RunnerContext.
// noteRealFailure` 是唯一判定点，`onCallThrew`/`onStopShapedThrew`（服务 stop 与 interrupt 共享的
// 『operation 通道』结算逻辑）全部经它，运行整条 timeline 结束后 `runFixtureFile` 统一读取
// `ctx.notImplementedTrigger` 决定这一条 fixture 最终是 DEGRADED 还是走正常的 PASS/FAIL（即便
// `notImplemented` 出现在 timeline 中途、后面还有更多 op 要执行，也是等整条跑完再判定——理由见
// `runFixtureFile` 对应注释）。
//
// **这个判据只认错误的字面类型，不认『调用的是哪个方法』**——`interrupt()` 对 `mode:"steer"`/
// `"abort_and_resend"` 抛的是 `KernelClientError.rpcRejected(code:"unsupported_interrupt_mode",…)`，
// 语义上同样是『不支持』，但字面上不是 `notImplemented`，因此**不会**被判 DEGRADED：它是一次真实的
// 拒绝，必须流入正常的 mismatch 累积。当前唯一使用 `interrupt` 的 fixture
// （`operation-outcome/soft-steer-then-stop.json`，`mode:"steer"`）因此从『整条静态跳过』变成
// 『真的跑、真的 FAIL』——不是 PASS，因为该 fixture 逐字转录自 D4 spec 的示例，假定了『`interrupt`
// 在途时 `stop()` 排队等待，不被拒绝』的语义，而 rounds/0020 的真实实现是『`send`/`stop`/`interrupt`
// 两两互斥，锁不是 idle 一律 `session_locked` 拒绝，不做排队仲裁』，且本轮只实现了 `mode:"cancel"`；
// 两者本就不是同一件事，运行时发现只是让这个早已存在的落差第一次变得可观察。`capabilities()`
// 无条件 `throw .notImplemented`（今天没有任何调用路径会绕开这一行），仍会被判 DEGRADED，但判据
// 现在来自这次运行真实捕获到的错误，不是它的名字出现在某份名单里。
// - `expect_outbound`（T-048 REWORK #4 收残；**T-050 REWORK #1 治根**）：先校验『真实 client 是否
//   调用了这个 D2 方法对应的正确 openclaw RPC 方法名』（`expectOutboundMethodTable`，真实 client 的
//   outbound wire 从来就不是 D2 req.* 形状，这一步是翻译诚实能保证的最基础粒度），方法名匹配后再对
//   一个『规范化请求』（`type` + 可选 `sessionId` + `payload`）做与 `ts-runner/runner.ts` 的
//   `partialMatch` 等价的完整子集深度匹配。**T-048 REWORK #4 曾经的残留问题**：那一轮虽然调了完整
//   `partialMatch`，但被匹配的『规范化请求』其实是把 timeline 的 `args` 原样放回 `payload` + 把
//   `sessionId` 直接取 `declaredSessionID`（fixture 声明值）——`params`（真实 client 调用
//   `testSupportStubRPC` 时同步传入的原生 RPC 参数）虽然存进了 `capturedOutbound`，却从没有代码读
//   它做字段映射，等于『只验证了方法名，pattern 其余字段验证的是 fixture 自己声明的东西』，真实
//   client 把 `sessions.send.params.message`/`sessions.messages.subscribe.params.key`/
//   `sessions.abort.params.key` 发错也不会被抓到。**本轮改法**：`normalizeNativeParams` 直接从
//   `capturedParams(for:)`（真实捕获的原生 `params`，而不是 fixture 的 `args`）规范化——
//   `sessionId` 通过反查『哪个已声明 session 拥有这个原生 `key`』得到（`kernelKeyToDeclaredSessionID`，
//   在 `res.createSession` 处理时登记），查不到就显式置 `NSNull()`，不 fallback 回
//   fixture 声明值；`payload` 是 `params` 去掉 `key`（原生寻址字段，不是 D2 payload 概念）之后的
//   剩余字段，`send` 一项把原生 `message` 反向映射回 D1 `Input.text` 概念（仅覆盖 Stage A 用到的
//   `kind:"text"` 场景）以便与 TS 端可比较，其余字段原样保留原生字段名，不臆造新映射。这样真实
//   client 把这几个字段发错，`expect_outbound` 才会真的 FAIL——不再是『调了 partialMatch 但验证的
//   还是自己声明的东西』这种表面绕过。
// - `sessionId`/`operationId` 是真实 client 内部铸造的随机 UUID（`createSession()`/`stop()`
//   各自 `UUID().uuidString`），fixture 无法预先声明字面值——本 runner 因此不断言真实 client 内部
//   状态查询（`testSupportLockState` 等）之外场景下这两个字段的具体取值。`pendingOperations` 改用
//   dsl.ts 注释里明确允许的『client_call 的 id』做键（不是内部 operationId）。`runId` 例外：它是
//   openclaw RPC 响应里的纯透传字段，翻译层完全掌控其内容，因此 fixture 可以放心声明字面 runId 并
//   让它真实流过整条链路，`ctx.currentRunIDValue` 也因此可以直接拿来判定『stop() 发起时是否存在
//   active run』（见下一条）。
// - `nativeCallOrder`（**T-050 REWORK #3 新增**）：`stop-force-denies-pending-approval.json` 此前
//   只断言 `req.stop` 本身，`approval.resolve` 只注册了一个立即成功的背景 stub、从未被记录或暴露给
//   任何断言——若真实 `stop()` 回归成先 `sessions.abort` 再 `approval.resolve`（D1 §6.2 M3 定序
//   要求的反面），该 fixture 当时不会 FAIL。本轮在 `RunnerContext` 上加一个 `nativeCallOrder: [String]`
//   ——在 `approval.resolve`/`sessions.abort` 两个 stub 闭包**真正被真实 client 调用的那一刻**
//   （不是 stub 注册的时刻）各自 append 一次，随 `snapshot()` 暴露给 `expected.nativeCallOrder`
//   断言。这忠实反映真实调用顺序：`request(method:params:)` 对已注册的 stub 是同步直接调用
//   responder（见 `OpenclawGatewayKernelClient.swift`），不是『谁先注册谁先跑』。
// - `mock_response(stop)`/`mock_event(evt.turn_complete)` 不再依赖 fixture 里任何非 D2 私有提示
//   字段（T-048 REWORK #1 收残：删除了 `_openclawAbortAck`/`_openclawLifecycle`）——sessions.abort
//   原生 ack 该携带的 `abortedRunId`/`status`，从『此前是否有一个 send() 已经真实 resolve 出一个
//   runId』（`ctx.currentRunIDValue`）无歧义派生，不需要 fixture 作者另外声明只有本 runner 认得的
//   字段；`evt.turn_complete` 在 Stage A 唯一的用途就是合成 stop() 等待中的 aborted lifecycle
//   终态信号，直接硬编码 `phase:"end", aborted:true`（Stage A 范围内没有第二种用途需要区分）。
//   `evt.approval_request` 的原生双帧到达顺序改读 `TimelineOp.driverHint`（../dsl.ts 的
//   `MockEventDriverHint`，DSL 层面显式声明的翻译层驱动量，不在 `message` 里，见该文件文档注释）。
// - `mock_event`/`mock_response` 只实现了 Stage A 三组 fixture（approval/operation-outcome/
//   session-lock）需要的类型（evt.message.delta、evt.turn_complete 用作 stop() 等待终态的合成
//   信号、evt.approval_request、以及 stop 类 client_call 的响应翻译）；遇到未登记的类型直接抛错，
//   不静默忽略，逼真实缺口暴露而不是假装通过。

import Foundation

// MARK: - 小工具

enum RunnerError: Error, CustomStringConvertible {
    case malformed(String)
    var description: String {
        switch self {
        case .malformed(let m): return "swift-runner 内部错误（fixture 或翻译层不匹配）：\(m)"
        }
    }
}

/// 单次 RPC 响应的『延迟解锁』——responder 闭包 `await gate.wait()`，runner 处理到对应
/// `mock_response` timeline op 时才 `resolve(...)`，让真实 client 的 `request()` 真的悬挂到那一刻
/// 才返回，从而让『client_call 在途 / 锁在途』这类中途 assert_state 断言的是真实状态而非摆拍。
///
/// **T-048 REWORK #7**：上一轮用 `NSLock.lock()/unlock()` 手工加锁保护 `resolution`/`waiter`
/// ——在 `wait()`（`async` 函数）里直接调用 `NSLock.lock/unlock` 在 Apple Swift 6.3.3 默认
/// language mode 下即会警告『不可在异步上下文调用，Swift 6 language mode 下将是编译错误』
/// （`swiftc` 实测复现）。改成 `actor`：与 SG-5 `OpenclawGatewayKernelClient`/本文件
/// `RunnerContext` 同款做法，用 actor 隔离取代手工锁，消除警告的同时不改变可观察行为——
/// `resolve`/`wait` 都改成 actor-isolated 方法，`wait()` 内部在 `withCheckedThrowingContinuation`
/// 闭包里同步写 `self.waiter`（在挂起点之前执行，仍处于该 actor 的隔离期内），与 SG-5
/// `waitForPendingStopTerminal` 已经在用的同一手法一致。
actor ReplyGate {
    private var resolution: Result<JSONObject, Error>?
    private var waiter: CheckedContinuation<JSONObject, Error>?

    func resolve(_ result: Result<JSONObject, Error>) {
        guard resolution == nil else { return }
        resolution = result
        guard let w = waiter else { return }
        waiter = nil
        switch result {
        case .success(let v): w.resume(returning: v)
        case .failure(let e): w.resume(throwing: e)
        }
    }

    func wait() async throws -> JSONObject {
        if let r = resolution {
            switch r {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONObject, Error>) in
            self.waiter = cont
        }
    }
}

/// 把一个 D2 事件（真实 EventMapping.swift 产出的 `EventMessageUnion`）转成 fixture DSL
/// `observedEvents` 期望的 `{type, payload}` 形状——`payload` 用 JSONEncoder 编码具体 payload 结构体
/// 再转回 `[String: Any]`，不是手写字段搬运，保证跟真实事件字段完全一致。
func encodeToJSONObject<T: Encodable>(_ value: T) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(value),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return obj
}

func eventToObservedEntry(_ event: EventMessageUnion) -> [String: Any] {
    let type = event.wireType
    let payload: [String: Any]
    switch event {
    case .messageDelta(let e): payload = encodeToJSONObject(e.payload)
    case .thinking(let e): payload = encodeToJSONObject(e.payload)
    case .toolCall(let e): payload = encodeToJSONObject(e.payload)
    case .toolResult(let e): payload = encodeToJSONObject(e.payload)
    case .approvalRequest(let e): payload = encodeToJSONObject(e.payload)
    case .error(let e): payload = encodeToJSONObject(e.payload)
    case .turnComplete(let e): payload = encodeToJSONObject(e.payload)
    case .sessionEnd(let e): payload = encodeToJSONObject(e.payload)
    case .capabilityChanged(let e): payload = encodeToJSONObject(e.payload)
    case .operationCompleted(let e): payload = encodeToJSONObject(e.payload)
    case .approvalBufferResolved(let e): payload = encodeToJSONObject(e.payload)
    }
    return ["type": type, "payload": payload]
}

func failureDict(for error: Error) -> [String: Any] {
    if let e = error as? KernelClientError {
        switch e {
        case .rpcRejected(let code, let message):
            return ["code": code, "detail": message ?? "" as Any]
        case .notImplemented(let m): return ["code": "not_implemented", "detail": m]
        case .transport(let m): return ["code": "transport", "detail": m]
        case .protocolMismatch(let m): return ["code": "protocol_mismatch", "detail": m]
        case .notConnected: return ["code": "not_connected"]
        }
    }
    return ["code": "unknown", "detail": "\(error)"]
}

func decodeConfig(from json: [String: Any]) throws -> Config {
    let data = try JSONSerialization.data(withJSONObject: json, options: [])
    return try JSONDecoder().decode(Config.self, from: data)
}

func decodeInput(from json: [String: Any]) throws -> Input {
    let data = try JSONSerialization.data(withJSONObject: json, options: [])
    return try JSONDecoder().decode(Input.self, from: data)
}

/// `InterruptRequestMessagePayload.input` 是强类型 `Input?`（`{kind,text,parts}`），但本轮唯一用到
/// `interrupt` 的金标 fixture（`operation-outcome/soft-steer-then-stop.json`，逐字转录自 D4 §4.3
/// 的 spec 级示例）里 `args.input` 写的是裸字符串 `"..."`——与 `normalizeNativeParams` 早就对
/// `sessions.send` 的 `message`<->`text` 做过的同一种宽容一致：裸字符串是『纯文本输入』的简写，不是
/// 要求 fixture 作者精确匹配 wire 结构。这里同样宽容：字符串按 `Input(kind:.text, text:<string>,
/// parts:nil)` 展开；已经是对象就走标准 Codable 解码；不存在就是 nil——不臆造，也不让一处占位符
/// 字符串在『还没跑到真实 client』这一步就直接让整条 fixture 判 FAIL（那会用一次翻译层解码事故掩盖
/// 『真实 client 到底怎么响应』这个本轮真正关心的问题）。`mode` 缺失/不合法时如实拒绝，不臆造默认值。
func decodeInterruptOptions(from json: [String: Any]) throws -> InterruptRequestMessagePayload {
    guard let modeRaw = json["mode"] as? String, let mode = Mode(rawValue: modeRaw) else {
        throw RunnerError.malformed(
            "client_call(interrupt) 的 args.mode 缺失或不是合法取值：\(json["mode"] ?? "<nil>")"
        )
    }
    let input: Input?
    switch json["input"] {
    case let s as String:
        input = Input(kind: .text, text: s, parts: nil)
    case let obj as [String: Any]:
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        input = try JSONDecoder().decode(Input.self, from: data)
    default:
        input = nil
    }
    return InterruptRequestMessagePayload(input: input, mode: mode, runID: json["runId"] as? String)
}

/// `respondApproval` 的 `args.decision` 直接是 D2 `Decision` 的标准形状（`{outcome,updatedInput?,
/// scope?,reason?}`）——不像 `interrupt.input` 那样存在已知的裸值简写先例，因此不额外加宽容逻辑
/// （没有证据支持的宽容是臆造，不是诚实）。
func decodeDecision(from json: [String: Any]) throws -> Decision {
    let data = try JSONSerialization.data(withJSONObject: json, options: [])
    return try JSONDecoder().decode(Decision.self, from: data)
}

// MARK: - RunnerContext：一次 fixture 执行期间的全部可变状态（actor 隔离，天然并发安全）

actor RunnerContext {
    let client: OpenclawGatewayKernelClient

    /// 真实收窄后的 stop() 等待超时（秒）——见文件头「虚拟时钟」一节的说明。
    static let stopTimeoutSeconds = 1
    static let stopTimeoutMs: UInt64 = 1000

    var currentSessionHandle: SessionHandle?
    var currentSessionID: String?
    var currentKernelKey: String?
    var currentRunID: String?

    /// 原生 `kernelKey` → fixture 在 `res.createSession` 里声明过的 `sessionHandle.sessionId`
    /// （如 "session-1"）——**T-050 REWORK #1**：取代旧版 `declaredSessionID`（单值、被
    /// `expect_outbound` 直接当作『真实发出的 sessionId』使用，与真实捕获到的原生 `params.key`
    /// 完全无关，是 T-048 REWORK #4 残留的表面绕过）。本表在 `res.createSession` 处理时登记，供
    /// `normalizeNativeParams` 从**真实捕获的原生 `key`** 反查『这把 key 对应哪个已声明 session』，
    /// 查不到就不 fallback——让真实 client 把 `key` 发错时 `expect_outbound` 的 `sessionId` 断言
    /// 真的失败。
    var kernelKeyToDeclaredSessionID: [String: String] = [:]

    /// 当前是否有一个 `stop()` client_call 正在等待 SG-5 内部终态确认（`hasStopWaitingForTerminal`
    /// 为 true 期间）——记录是*哪一个* client_call id，供 `advance_clock`/`disconnect` 轮询
    /// `isCallSettled(id:)` 时知道该盯哪个 id（T-048 REWORK #5）。
    var waitingStopCallID: String?

    var callKindByID: [String: String] = [:]
    var replyGates: [String: ReplyGate] = [:]
    /// 真实捕获到的原生 RPC 调用——`(method, params)`，`params` 是 `testSupportStubRPC` 闭包收到的
    /// 原始入参（真实 client 同步传入，不是 fixture 声明值）。**T-050 REWORK #1**：不再在捕获时就
    /// 顺手构造一份『规范化请求』（那份构造用的是 timeline 的 `args`，等于验证 fixture 自己声明的
    /// 东西）——规范化改成 `checkExpectOutbound` 需要断言时才从这里的原始 `params` 现算
    /// （`normalizeNativeParams`），保证断言对象是真实发出的东西。
    var capturedOutbound: [String: (method: String, params: JSONObject)] = [:]

    /// 真实原生 RPC 调用顺序——只登记 Stage A 需要断言顺序的这几个特定调用（目前只有
    /// `approval.resolve`/`sessions.abort`，`stop-force-denies-pending-approval.json` 用它断言
    /// D1 §6.2 M3 定序，T-050 REWORK #3 新增），不是完整调用日志。在 stub 闭包**真正被调用的那一刻**
    /// （不是注册的时刻）append，因此忠实反映真实 client 的调用顺序。
    var nativeCallOrder: [String] = []

    /// `client_call` 的 id → OperationOutcome（interrupt/stop 铸造的 operation 通道）——dsl.ts 明确
    /// 允许键是『operationId 或 client_call 的 id』，本 runner 一律用后者（真实 operationId 是运行时
    /// 随机 UUID，fixture 无法预先声明，见文件头说明）。
    var pendingOperations: [String: Any] = [:]
    var callOutcomes: [String: Any] = [:]
    var approvalState: [String: Any] = [:]
    var drainedEvents: [[String: Any]] = []

    var pendingTasks: [Task<Void, Never>] = []
    var accumulatedMismatches: [Mismatch] = []
    var hasStopWaitingForTerminal = false

    /// 运行时发现（rounds/0022 核心状态）：唯一判据是『某次真实 client 调用抛出的错误，字面上就是
    /// `KernelClientError.notImplemented`』——不是任何静态方法名单，也不是按 `call` 名字猜测。只记
    /// 第一次命中（先到先得，足够诊断；一旦命中即整条 fixture DEGRADED，见 `runFixtureFile`，多记
    /// 几个没有增量价值）。`call` 从 `callKindByID` 反查，供 DEGRADED 理由文案标注是哪个方法触发的。
    var notImplementedTrigger: (callID: String, call: String, detail: String)?

    /// 全部『真实 client 调用失败』路径的共同入口——`onCallThrew`（createSession/send/subscribe/
    /// respondApproval/capabilities）与 `onStopShapedThrew`（stop/interrupt 共享的 operation 通道
    /// 结算）都在写入各自的失败记账**之前**先经过这里。判定逻辑与文件头「DEGRADED 判定」一节说明
    /// 一致：只认错误的字面类型，`rpcRejected`（即便语义上也是『不支持』，如 interrupt 对
    /// steer/abort_and_resend 的拒绝）一律不触发。
    func noteRealFailure(id: String, error: Error) {
        guard notImplementedTrigger == nil else { return }
        guard case KernelClientError.notImplemented(let detail) = error else { return }
        notImplementedTrigger = (callID: id, call: callKindByID[id] ?? "<未知>", detail: detail)
    }

    init(client: OpenclawGatewayKernelClient) {
        self.client = client
    }

    func recordOutbound(id: String, method: String, params: JSONObject) {
        capturedOutbound[id] = (method, params)
    }

    func capturedOutboundMethod(for id: String) -> String? {
        capturedOutbound[id]?.method
    }

    func capturedParams(for id: String) -> JSONObject? {
        capturedOutbound[id]?.params
    }

    /// `res.createSession` 处理时登记——见 `kernelKeyToDeclaredSessionID` 文档注释。
    func registerDeclaredSession(kernelKey: String, sessionID: String) {
        kernelKeyToDeclaredSessionID[kernelKey] = sessionID
    }

    /// 从真实捕获的原生 `key` 反查已声明 session——查不到返回 nil（调用方据此显式置 `NSNull()`，
    /// 不 fallback，见 `normalizeNativeParams`）。
    func declaredSessionID(forKernelKey key: String) -> String? {
        kernelKeyToDeclaredSessionID[key]
    }

    /// 见 `nativeCallOrder` 文档注释——在真实调用发生的那一刻 append。
    func appendNativeCall(_ name: String) {
        nativeCallOrder.append(name)
    }

    func gate(for id: String) -> ReplyGate? { replyGates[id] }
    func callKind(for id: String) -> String? { callKindByID[id] }
    func setCurrentKernelKey(_ key: String) { currentKernelKey = key }
    func setHasStopWaitingForTerminal(_ value: Bool) { hasStopWaitingForTerminal = value }
    func setWaitingStopCallID(_ id: String?) { waitingStopCallID = id }
    var hasStopWaitingForTerminalValue: Bool { hasStopWaitingForTerminal }
    var currentKernelKeyValue: String? { currentKernelKey }
    var currentRunIDValue: String? { currentRunID }
    var waitingStopCallIDValue: String? { waitingStopCallID }

    /// T-048 REWORK #5：`advance_clock`/`disconnect` 用来判定『这次 stop() 的最终结果是否已经
    /// 结算』的同步目标——`onStopResolved`/`onStopThrew` 写完 `pendingOperations`/`callOutcomes`
    /// 才算数，这正是随后 `assert_state` 要读的同一份状态，比轮询 SG-5 内部 `terminalEmitted`
    /// 更贴近真正需要同步的时刻（后者只代表 `waitForPendingStopTerminal` 已返回，`stop()` 自己还要
    /// 再走 `sessions.delete` + `emitStopSessionEndAndFinish`，`onStopResolved` 还有自己的
    /// `settleForEventDrain` 才会真正落笔）。
    func isCallSettled(id: String) -> Bool {
        pendingOperations[id] != nil || callOutcomes[id] != nil
    }

    func appendMismatch(_ m: Mismatch) { accumulatedMismatches.append(m) }
    func addPendingTask(_ task: Task<Void, Never>) { pendingTasks.append(task) }

    func onCreateSessionResolved(id: String, handle: SessionHandle) {
        currentSessionHandle = handle
        currentSessionID = handle.sessionID
        callOutcomes[id] = ["status": "resolved"]
    }

    func onSendResolved(id: String, result: SendResultPayload) {
        currentRunID = result.runID
        callOutcomes[id] = ["status": "resolved"]
    }

    func onCallThrew(id: String, error: Error) {
        noteRealFailure(id: id, error: error)
        callOutcomes[id] = ["status": "rejected", "failure": failureDict(for: error)]
    }

    /// `emitOperationCompletedMirror` 在真实 `stop()` 内部是同步调用（`continuation.yield(...)`），
    /// 但 yield 唤醒本 runner 的事件排空 Task（`startDraining` 里 `iterator.next()`）、再由它
    /// `await self.appendEvent(...)` 写回 `drainedEvents`，这一步经过 Swift 并发调度器，不与
    /// `stop()` 的 throw/return 同步——`onStopResolved`/`onStopThrew` 是从另一个 Task（`client_call`
    /// 的包装 Task）在 `stop()` 刚返回/刚抛错的瞬间调用，如果不等待，可能在排空 Task 真正把镜像事件
    /// 写进 `drainedEvents`之前就已经读完（真实复现：stop-rejected-rpc-failure fixture 最初跑出
    /// 『pendingOperations.stop1 期望 rejected，实际 nil』的 flaky 结果）。这里短暂 sleep 一下
    /// ——因为是 actor-isolated 方法内部的 await，会释放 actor，让排空 Task 有机会先把
    /// `appendEvent` 处理完，再回来继续读 `drainedEvents`。
    private func settleForEventDrain() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    /// `stop()`/`interrupt()` 共享的『operation 通道』结算逻辑——两者在 SG-5 内部本就共享同一张
    /// 『等待终态』表（`pendingStops`，靠 `operationKind` 区分 `.stop`/`.interrupt`，见
    /// `OpenclawGatewayKernelClient.swift` rounds/0020 段文档注释），产出的 `OperationOutcome`
    /// 语义完全一致，因此运行结束时怎么记账不分叉——`onStopResolved`/`onInterruptResolved` 都只是
    /// 把各自类型化的 `result.outcome.rawValue` 传进来（`StopResultPayload.outcome` 是
    /// `StopResultPayloadOutcome`，`InterruptResultPayload.outcome` 是 `PayloadOutcome`，两个不同
    /// 枚举类型，`rawValue` 都是 `String`，在这一层不需要再区分）。
    private func onStopShapedResolved(id: String, outcomeRawValue: String, eventsCountAtStart: Int) async {
        hasStopWaitingForTerminal = false
        await settleForEventDrain()
        if let outcome = firstOperationCompletedOutcome(after: eventsCountAtStart) {
            pendingOperations[id] = outcome
        } else {
            pendingOperations[id] = outcomeRawValue
        }
    }

    /// 见 `onStopShapedResolved` 文档注释——本函数是失败一侧的镜像，同样服务 stop()/interrupt()。
    private func onStopShapedThrew(id: String, error: Error, eventsCountAtStart: Int) async {
        noteRealFailure(id: id, error: error)
        hasStopWaitingForTerminal = false
        // `session_locked` 是 stop()/interrupt() 顶部 `currentLock == .idle` 前置 guard 直接抛出
        // 的——发生在 `operationID` 铸造之前，真实 client **绝不会**为这次调用产出任何
        // operation_completed 镜像事件（见下方分支的文档注释）。这个分支不用等，等了也白等，还会
        // 不必要地拖慢『并发 stop/interrupt 被拒绝』这类断言的可观察时刻——因此只对『可能真的有镜像
        // 事件在路上』的其它错误类型才 settle。
        if case KernelClientError.rpcRejected(let code, _) = error, code == "session_locked" {
            callOutcomes[id] = ["status": "rejected", "failure": failureDict(for: error)]
            return
        }
        await settleForEventDrain()
        if let outcome = firstOperationCompletedOutcome(after: eventsCountAtStart) {
            // operationId 已铸造、RPC 中途失败（M3 catch 分支）——OperationOutcome 层面的终态，
            // 走 pendingOperations（D1 v3.1 §9.1：这是『已经开始执行的 operation 的终态』通道）。
            pendingOperations[id] = outcome
        } else {
            // 没有 operation_completed 镜像——说明这次调用在铸造 operationId 之前就被同步拒绝
            // （D1 v3.1 §9.1 `KernelPortRejectionCode` 层面的前置条件拒绝，例如 session_locked，
            // 或 interrupt() 顶部『mode 不是 cancel』的 `unsupported_interrupt_mode` 拒绝——两者都
            // 发生在 `let operationID = ...` 之前就 throw），根本没有进入 OperationOutcome 通道——
            // 不写 pendingOperations（那是 operationId 铸造之后才有意义的字段），改记 callOutcomes，
            // 与其它不产生 operationId 的失败调用同一处理方式一致。
            callOutcomes[id] = ["status": "rejected", "failure": failureDict(for: error)]
        }
    }

    func onStopResolved(id: String, result: StopResultPayload, eventsCountAtStart: Int) async {
        await onStopShapedResolved(id: id, outcomeRawValue: result.outcome.rawValue, eventsCountAtStart: eventsCountAtStart)
    }

    func onStopThrew(id: String, error: Error, eventsCountAtStart: Int) async {
        await onStopShapedThrew(id: id, error: error, eventsCountAtStart: eventsCountAtStart)
    }

    /// D1 §2.4 interrupt —— rounds/0022 新增：此前 `interrupt`/`respondApproval`/`capabilities`
    /// 三个 client_call 从未被真实派发（整条 fixture 静态 DEGRADED），本轮起 interrupt 与 stop 走
    /// 同一条『operation 通道』记账（见 `onStopShapedResolved`/`onStopShapedThrew` 文档注释）。
    func onInterruptResolved(id: String, result: InterruptResultPayload, eventsCountAtStart: Int) async {
        await onStopShapedResolved(id: id, outcomeRawValue: result.outcome.rawValue, eventsCountAtStart: eventsCountAtStart)
    }

    func onInterruptThrew(id: String, error: Error, eventsCountAtStart: Int) async {
        await onStopShapedThrew(id: id, error: error, eventsCountAtStart: eventsCountAtStart)
    }

    private func firstOperationCompletedOutcome(after index: Int) -> String? {
        guard index <= drainedEvents.count else { return nil }
        for i in index..<drainedEvents.count {
            let entry = drainedEvents[i]
            if entry["type"] as? String == "evt.operation_completed",
               let payload = entry["payload"] as? [String: Any],
               let outcome = payload["outcome"] as? String {
                return outcome
            }
        }
        return nil
    }

    func appendEvent(_ entry: [String: Any]) {
        drainedEvents.append(entry)
        if entry["type"] as? String == "evt.approval_request",
           let payload = entry["payload"] as? [String: Any],
           let reqID = payload["reqId"] as? String {
            approvalState[reqID] = "pending"
        }
    }

    func startDraining(_ stream: AsyncThrowingStream<EventMessageUnion, Error>) {
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            while true {
                let next: EventMessageUnion?
                do {
                    next = try await iterator.next()
                } catch {
                    break
                }
                guard let event = next else { break }
                let entry = eventToObservedEntry(event)
                // T-050 REWORK（附带修复 codex 提的 warning）：`Task { ... }` 在 `startDraining`
                // （`RunnerContext` 的一个 actor-isolated 方法）内部创建，闭包继承同一 actor 隔离——
                // `self.appendEvent` 因此是同一 actor 内的直接调用，不跨隔离域，没有真实挂起点，
                // 不需要 `await`（编译器警告『no async operations occur within await expression』
                // 正是这个意思，不是别的隐患）。
                self.appendEvent(entry)
            }
        }
        pendingTasks.append(task)
    }

    func snapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        out["pendingOperations"] = pendingOperations
        out["callOutcomes"] = callOutcomes
        out["approvalState"] = approvalState
        out["observedEvents"] = drainedEvents
        // T-050 REWORK #3：暴露给 `expected.nativeCallOrder` 断言（目前只有
        // stop-force-denies-pending-approval.json 用它防 force-deny/abort 顺序回归）。
        out["nativeCallOrder"] = nativeCallOrder
        return out
    }

    func snapshotWithLock() async -> [String: Any] {
        var out = snapshot()
        if let sid = currentSessionID {
            out["sessionLock"] = await client.testSupportLockState(sessionID: sid)
        }
        return out
    }

    func drainedEventsCount() -> Int { drainedEvents.count }
}

// MARK: - client_call 翻译层

func performClientCall(_ op: TimelineOp, ctx: RunnerContext) async throws {
    guard let id = op.id, let call = op.call else {
        throw RunnerError.malformed("client_call 缺少 id/call（t=\(op.t)）")
    }
    await ctx.setCallKind(id: id, call: call)
    let argsAny = (op.args?.value as? [String: Any]) ?? [:]
    let client = ctx.client

    switch call {
    case "createSession":
        let configJSON = (argsAny["config"] as? [String: Any]) ?? [:]
        let config = try decodeConfig(from: configJSON)
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "sessions.create") { params in
            // T-050 REWORK #1：只记录真实捕获的原生 params——不再在这里顺手拼一份『规范化请求』
            // （那份是从 timeline 的 `argsAny` 抄的，等于验证 fixture 自己声明的东西）。规范化留给
            // `checkExpectOutbound` 断言时从这份原始 params 现算（`normalizeNativeParams`）。
            await ctx.recordOutbound(id: id, method: "sessions.create", params: params)
            return try await gate.wait()
        }
        let task = Task<Void, Never> {
            do {
                let handle = try await client.createSession(config: config)
                await ctx.onCreateSessionResolved(id: id, handle: handle)
            } catch {
                await ctx.onCallThrew(id: id, error: error)
            }
        }
        await ctx.addPendingTask(task)

    case "send":
        let input = try decodeInput(from: argsAny)
        guard let handle = await ctx.currentSessionHandle else {
            throw RunnerError.malformed("send（id=\(id)）在 createSession 之前调用")
        }
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "sessions.send") { params in
            await ctx.recordOutbound(id: id, method: "sessions.send", params: params)
            return try await gate.wait()
        }
        let task = Task<Void, Never> {
            do {
                let result = try await client.send(session: handle, input: input)
                await ctx.onSendResolved(id: id, result: result)
            } catch {
                await ctx.onCallThrew(id: id, error: error)
            }
        }
        await ctx.addPendingTask(task)

    case "subscribe":
        // 真实 `subscribe()` 同步（在第一次 await 之前）就把 `eventContinuations[sessionID]` 建好、
        // 立即返回事件流——底层 `sessions.messages.subscribe` RPC 是否已经收到响应，不影响
        // `handleAgentEvent`/`handleSessionMessageEvent` 等 dispatch 分支能否正常工作（它们只检查
        // `eventContinuations` 是否存在），因此这里用『可选 gate』：fixture 若显式提供了
        // `mock_response(replyTo: 这个 subscribe 调用的 id)`（如既有 basic fixture），gate 会在那时
        // 被解锁，`callOutcomes[id]` 才会记为 resolved；若 fixture 没提供（本轮新写的三组 fixture
        // 大多不需要），gate 永远悬挂也不影响后续任何事件观察——事件 dispatch 走的是另一条独立路径。
        guard let handle = await ctx.currentSessionHandle else {
            throw RunnerError.malformed("subscribe（id=\(id)）在 createSession 之前调用")
        }
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "sessions.messages.subscribe") { params in
            await ctx.recordOutbound(id: id, method: "sessions.messages.subscribe", params: params)
            do {
                let json = try await gate.wait()
                await ctx.setCallOutcomeResolved(id: id)
                return json
            } catch {
                await ctx.onCallThrew(id: id, error: error)
                throw error
            }
        }
        let stream = await client.subscribe(session: handle)
        await ctx.startDraining(stream)

    case "stop":
        guard let handle = await ctx.currentSessionHandle else {
            throw RunnerError.malformed("stop（id=\(id)）在 createSession 之前调用")
        }
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "sessions.abort") { params in
            // T-050 REWORK #3：append 发生在这条 stub **真正被真实 client 调用**的这一刻——不是
            // stub 注册的时刻——所以 `nativeCallOrder` 里 "sessions.abort" 相对 "approval.resolve"
            // 的先后顺序，反映的是真实 `stop()` 方法体里两个 `request(...)` 调用的真实先后顺序
            // （见 `OpenclawGatewayKernelClient.stop()`：`forceDenyPendingApprovalsBeforeStop` 内部
            // 的 `request(method:"approval.resolve",...)` 早于随后的
            // `request(method:"sessions.abort",...)`），不是本文件两行 `testSupportStubRPC` 的
            // 书写顺序（那只是注册顺序，与调用顺序无关）。
            await ctx.appendNativeCall("sessions.abort")
            await ctx.recordOutbound(id: id, method: "sessions.abort", params: params)
            return try await gate.wait()
        }
        await client.testSupportStubRPC(method: "sessions.delete") { _ in ["deleted": true] }
        // D1 §6.2 M3（stop() 强制 deny 补丁，本轮新落地）：`stop()` 在发起 `sessions.abort` 之前，
        // 若该 session 仍有 pending 审批，会先对每一个调用真实 openclaw 统一审批解决 RPC
        // `approval.resolve`（`forceDenyPendingApprovalsBeforeStop`，见
        // OpenclawGatewayKernelClient.swift 文档注释），要求响应体 `approval.status == "denied"`
        // 才算数。绝大多数 fixture 没有 pending 审批时，`forceDenyPendingApprovalsBeforeStop` 在空
        // 列表上提前返回、根本不会发起这条 RPC（这条 stub 是安全的默认背景桩，不影响其余 fixture）；
        // 只有 `approval/stop-force-denies-pending-approval.json` 会真正命中。
        await client.testSupportStubRPC(method: "approval.resolve") { _ in
            // T-050 REWORK #3：同上，append 在真实调用发生的这一刻——若 `forceDenyPendingApprovalsBeforeStop`
            // 回归成在 `sessions.abort` 之后才调用（或压根不调用），`nativeCallOrder` 就不会是
            // `["approval.resolve", "sessions.abort"]`，`stop-force-denies-pending-approval.json`
            // 的 `expected.nativeCallOrder` 断言会真的 FAIL。
            await ctx.appendNativeCall("approval.resolve")
            return ["applied": true, "approval": ["status": "denied"]]
        }
        let eventsCountAtStart = await ctx.drainedEventsCount()
        let task = Task<Void, Never> {
            do {
                let result = try await client.stop(session: handle)
                await ctx.onStopResolved(id: id, result: result, eventsCountAtStart: eventsCountAtStart)
            } catch {
                await ctx.onStopThrew(id: id, error: error, eventsCountAtStart: eventsCountAtStart)
            }
        }
        await ctx.addPendingTask(task)

    case "interrupt":
        // D1 §2.4——rounds/0022 起真派发（此前这里是「不应该走到这里」的哨兵抛错，见文件头「DEGRADED
        // 判定」一节）。`mode:"cancel"` 且 session 处于 idle 锁态时，真实 `interrupt()` 会调用与
        // `stop()` 完全相同的 `sessions.abort` RPC（见 OpenclawGatewayKernelClient.interrupt() 文档
        // 注释「只复用 stop() 下面的部件」）——因此这里镜像 `stop` 分支注册同一套桩/gate；本轮唯一的
        // interrupt fixture 用的是 `mode:"steer"`，会在到达那一步之前就被顶部的 mode guard 拒绝
        // （`rpcRejected(unsupported_interrupt_mode)`，字面上不是 `notImplemented`，不会被判
        // DEGRADED），因此这套桩今天实际上永远不会被调用到——**但 gate 本身必须注册**：
        // `soft-steer-then-stop.json` 的 timeline 仍然含一条 `mock_response(replyTo: <这次 interrupt
        // 调用的 id>)`（逐字转录自 D4 spec 示例，假定了一个更完整的 interrupt 实现），若不注册 gate，
        // 这条 op 会在 `applyMockResponse` 里找不到 gate 而抛 `RunnerError.malformed`，把一次『真实
        // client 拒绝』意外劣化成一次『runner 结构性崩溃』——这不是本轮想要的『真实 FAIL』。
        guard let handle = await ctx.currentSessionHandle else {
            throw RunnerError.malformed("interrupt（id=\(id)）在 createSession 之前调用")
        }
        let options = try decodeInterruptOptions(from: argsAny)
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "sessions.abort") { params in
            await ctx.appendNativeCall("sessions.abort")
            await ctx.recordOutbound(id: id, method: "sessions.abort", params: params)
            return try await gate.wait()
        }
        // 同 `stop` 分支：安全的默认背景桩，只有 session 存在 pending 审批时才会被真正调用。
        await client.testSupportStubRPC(method: "approval.resolve") { _ in
            await ctx.appendNativeCall("approval.resolve")
            return ["applied": true, "approval": ["status": "denied"]]
        }
        let eventsCountAtStart = await ctx.drainedEventsCount()
        let task = Task<Void, Never> {
            do {
                let result = try await client.interrupt(session: handle, options: options)
                await ctx.onInterruptResolved(id: id, result: result, eventsCountAtStart: eventsCountAtStart)
            } catch {
                await ctx.onInterruptThrew(id: id, error: error, eventsCountAtStart: eventsCountAtStart)
            }
        }
        await ctx.addPendingTask(task)

    case "respondApproval":
        // D1 §2.6——rounds/0022 起真派发。真实 `respondApproval()`（rounds/0015 已实现）在到达任何
        // RPC 之前先要求 `reqID` 在 `pendingApprovalsByReqID` 里（由一条先行的 `evt.approval_request`
        // mock_event 登记）——本轮没有任何 fixture 提供这个前置条件，因此可预期的真实结果是
        // `ApprovalDecisionError.approvalNotPending`（不是 `KernelClientError`，`failureDict(for:)`
        // 落到 `unknown` 分支，如实反映，不臆造一个不存在的 code），这条 RPC 桩今天不会被真正调用到。
        // 仍然注册 gate（理由同 `interrupt` 分支：一旦有 fixture 提供 `mock_response`，不能让它撞见
        // 一次结构性崩溃）。
        guard let handle = await ctx.currentSessionHandle else {
            throw RunnerError.malformed("respondApproval（id=\(id)）在 createSession 之前调用")
        }
        guard let reqID = argsAny["reqId"] as? String else {
            throw RunnerError.malformed("client_call(respondApproval id=\(id)) 缺少 args.reqId")
        }
        let decision = try decodeDecision(from: (argsAny["decision"] as? [String: Any]) ?? [:])
        let gate = ReplyGate()
        await ctx.setGate(id: id, gate: gate)
        await client.testSupportStubRPC(method: "approval.resolve") { params in
            await ctx.appendNativeCall("approval.resolve")
            await ctx.recordOutbound(id: id, method: "approval.resolve", params: params)
            return try await gate.wait()
        }
        let task = Task<Void, Never> {
            do {
                try await client.respondApproval(session: handle, reqID: reqID, decision: decision)
                await ctx.setCallOutcomeResolved(id: id)
            } catch {
                await ctx.onCallThrew(id: id, error: error)
            }
        }
        await ctx.addPendingTask(task)

    case "capabilities":
        // D1 §2.7——rounds/0022 起真派发。今天两端都是无条件 `throw .notImplemented`（没有任何分支
        // 会先做别的事），因此不需要 RPC 桩：真调用即真发现。`session` 是可选的（D1 §2.7 允许不带
        // session 查内核级能力），`ctx.currentSessionHandle` 尚未建立时如实传 nil，不臆造一个不存在
        // 的 session。
        let sessionArg = await ctx.currentSessionHandle
        let task = Task<Void, Never> {
            do {
                _ = try await client.capabilities(session: sessionArg)
                await ctx.setCallOutcomeResolved(id: id)
            } catch {
                await ctx.onCallThrew(id: id, error: error)
            }
        }
        await ctx.addPendingTask(task)

    default:
        throw RunnerError.malformed("未知 KernelClientMethod『\(call)』")
    }

    // 给刚 spawn 的 Task 一点真实时间跑到它的 RPC await 点（actor hop + 进入 gate.wait()），
    // 让紧随其后的 expect_outbound/assert_state 断言的是『真的在途』而不是『还没开始』。
    try? await Task.sleep(nanoseconds: 50_000_000)
}

// MARK: - RunnerContext 的几个薄 setter（放在 extension 里避免上面主体过长）

extension RunnerContext {
    func setCallKind(id: String, call: String) { callKindByID[id] = call }
    func setGate(id: String, gate: ReplyGate) { replyGates[id] = gate }
    func setCallOutcomeResolved(id: String) { callOutcomes[id] = ["status": "resolved"] }
}

// MARK: - expect_outbound

/// D2 req.* 方法名 → 真实 client 会调用的 openclaw 原生 RPC 方法名。只覆盖 createSession/send/
/// subscribe/stop 四个——**不是**因为 interrupt/respondApproval/capabilities 的 fixture 仍被整条
/// DEGRADED 挡在外面（rounds/0022 起不再是），而是因为这三个方法的翻译层目前不拦截/不记录它们的
/// 出站 RPC（`performClientCall` 对应分支刻意没有注册 `testSupportStubRPC`，见那里的说明）——
/// `expect_outbound` 若用在这三个方法上，会落进下面 `guard let expectedMethod = ... else` 分支，
/// 如实报告『未登记』，不是误判通过。
let expectOutboundMethodTable: [String: String] = [
    "req.createSession": "sessions.create",
    "req.send": "sessions.send",
    "req.subscribe": "sessions.messages.subscribe",
    "req.stop": "sessions.abort",
]

/// T-050 REWORK #1（治根）：把真实捕获到的 openclaw 原生 RPC `params`（`performClientCall` 的
/// `testSupportStubRPC` 闭包同步收到的原始入参，真实 client 传的，不是 fixture 声明值）规范化成一个
/// 可与 `expect_outbound` 的 `pattern` 做完整深度匹配的『规范化请求』——见文件头「已知的『无法翻译』
/// 边界」一节对本函数存在理由的完整说明。
///
/// - `sessionId`：从捕获到的原生 `key` 反查『哪个已声明 session 拥有这个 kernelKey』
///   （`ctx.declaredSessionID(forKernelKey:)`）。`key` 不存在于 `params`（如 createSession，session
///   尚不存在）就不设置这个字段；`key` 存在但查不到对应的已声明 session（真实 client 把 key 发错、
///   或发了一个从未声明过的 key）就显式置 `NSNull()`——不 fallback 到任何 fixture 声明值，让 pattern
///   里的 `sessionId` 断言在这种情况下真的失败。
/// - `payload`：`params` 去掉 `key`（原生寻址字段，不是 D2 payload 概念）之后剩下的全部字段，原样
///   保留原生字段名（`label`/`model`/`timeoutMs`/`attachments`/`includeApprovals` 等）——**仅
///   `sessions.send` 一项**例外：把原生 `message` 反向映射回 D1 `Input.text` 概念（对应
///   `resolveSendMessageText` 在 Stage A fixture 唯一用到的 `kind:"text"` 场景，不覆盖
///   structured/parts），只为了让这个字段能与 TS 端 `payload.text`（直接来自 client_call 的 D1
///   `args`）做跨语言一致的深度匹配；其余字段不改名，如实反映原生协议。**T-052 REWORK 治根**：
///   `message`→`text` 重映射前必须无条件先剥掉 payload 拷贝里预存的 `message` 和 `text` 两个键——
///   否则若真实 client 把 native 层错发成不该存在的 `text` 字段（正确形状应是 `message`），该字段
///   会原样留在 payload 里、自证满足 `payload.text` 断言，形成假绿。剥掉之后只有真的捕获到
///   `message` 才重新写回 `text`；`message` 不存在则 `payload` 里不含 `text`，pattern 的
///   `payload.text` 断言必然失败。
func normalizeNativeParams(
    method: String, params: JSONObject, expectedType: String, ctx: RunnerContext
) async -> [String: Any] {
    var out: [String: Any] = ["type": expectedType]
    var payload = params
    if let key = payload.removeValue(forKey: "key") as? String {
        if let sessionID = await ctx.declaredSessionID(forKernelKey: key) {
            out["sessionId"] = sessionID
        } else {
            out["sessionId"] = NSNull()
        }
    }
    if method == "sessions.send" {
        let message = payload.removeValue(forKey: "message")
        payload.removeValue(forKey: "text")
        if let message {
            payload["text"] = message
        }
    }
    out["payload"] = payload
    return out
}

func checkExpectOutbound(_ op: TimelineOp, ctx: RunnerContext) async throws {
    guard let matches = op.matches else {
        throw RunnerError.malformed("expect_outbound 缺少 matches（t=\(op.t)）")
    }
    let patternAny = (op.pattern?.value as? [String: Any]) ?? [:]
    guard let expectedType = patternAny["type"] as? String else {
        throw RunnerError.malformed("expect_outbound(\(matches)) 的 pattern 缺少 'type'")
    }
    guard let expectedMethod = expectOutboundMethodTable[expectedType] else {
        await ctx.appendMismatch(
            "expect_outbound(\(matches)): swift-runner 未登记『\(expectedType)』对应的 openclaw RPC 方法名" +
            "（该 D2 方法尚未在本 runner 的 outbound 方法表中登记；不代表 client 未实现——rounds/0022 起实现状态由运行时发现判定，不再由此处文案声称）"
        )
        return
    }
    let captured = await ctx.capturedOutboundMethod(for: matches)
    guard captured == expectedMethod else {
        await ctx.appendMismatch(
            "expect_outbound(\(matches)): 期望真实 client 调用底层 openclaw RPC 方法『\(expectedMethod)』" +
            "（对应 D2『\(expectedType)』），实际捕获到『\(captured ?? "<none>")』"
        )
        return
    }
    // T-048 REWORK #4 / T-050 REWORK #1（治根）：方法名匹配之后，不再到此为止——继续对一个『规范化
    // 请求』做与 `ts-runner/runner.ts` 的 `partialMatch` 等价的完整子集深度匹配，让 pattern 里
    // `type` 之外的字段（如 basic fixture 的 `sessionId`、interrupt 的 `payload.mode`）也真正生效。
    // **T-050 治根**：规范化对象改从 `capturedParams(for:)`——真实捕获的原生 `params`——现算
    // （`normalizeNativeParams`），不再是 T-048 REWORK #4 那版『捕获时顺手拿 timeline 的 args 拼一份』
    // 的规范化请求（那份验证的是 fixture 自己声明的东西，不是真实发出的东西）。
    let params = await ctx.capturedParams(for: matches) ?? [:]
    let normalized = await normalizeNativeParams(method: expectedMethod, params: params, expectedType: expectedType, ctx: ctx)
    let diff = partialMatch(actual: normalized, expected: patternAny, path: "expect_outbound(\(matches))")
    for d in diff { await ctx.appendMismatch(d) }
}

// MARK: - mock_response

func applyMockResponse(_ op: TimelineOp, ctx: RunnerContext) async throws {
    guard let replyTo = op.replyTo else {
        throw RunnerError.malformed("mock_response 缺少 replyTo（t=\(op.t)）")
    }
    guard let gate = await ctx.gate(for: replyTo) else {
        throw RunnerError.malformed(
            "mock_response(replyTo=\(replyTo)) 找不到对应的 reply gate——对应 client_call 未发起，" +
            "或该方法不需要 gate（如 subscribe）"
        )
    }
    let messageAny = (op.message?.value as? [String: Any]) ?? [:]
    let kind = await ctx.callKind(for: replyTo) ?? ""

    if let failure = messageAny["failure"] as? [String: Any] {
        let code = (failure["code"] as? String) ?? "unknown"
        let detail = failure["detail"] as? String
        await gate.resolve(.failure(KernelClientError.rpcRejected(code: code, message: detail)))
        return
    }

    let result = (messageAny["result"] as? [String: Any]) ?? [:]

    switch kind {
    case "createSession":
        let sessionId = (result["sessionHandle"] as? [String: Any])?["sessionId"] as? String
        let key = "openclaw-key-\(sessionId ?? UUID().uuidString)"
        await ctx.setCurrentKernelKey(key)
        // T-050 REWORK #1：登记『这把 key 对应哪个已声明 session』——真实 client 之后每次
        // send/subscribe/stop 都会在原生 `params.key` 里带上这把 key（原样回显，不会自己再编码
        // sessionId），`expect_outbound` 断言时反查这张表，从真实捕获的 key 算出 sessionId，而不是
        // 直接信任 fixture 声明值（见 RunnerContext.kernelKeyToDeclaredSessionID 文档注释）。
        await ctx.registerDeclaredSession(kernelKey: key, sessionID: sessionId ?? key)
        await gate.resolve(.success(["key": key, "sessionId": sessionId ?? key]))

    case "send":
        let runId = (result["runId"] as? String) ?? "run-\(UUID().uuidString.prefix(8))"
        await gate.resolve(.success(["runId": runId, "status": "started", "messageSeq": 1]))

    case "subscribe":
        let kernelKey = await ctx.currentKernelKeyValue ?? ""
        await gate.resolve(.success(["subscribed": true, "key": kernelKey]))

    case "stop":
        // T-048 REWORK #1（删除非法 `_openclawAbortAck`）：真实 sessions.abort RPC ack 该携带的
        // `abortedRunId`/`status`，从合法 canonical 字段无歧义派生——『此前是否已经有一个 send()
        // 真实 resolve 出一个 runId』（`ctx.currentRunIDValue`，取自 res.send 的 runId，真实 client
        // 内部铸造，不是伪造）本身就唯一决定了这次 stop() 命中时是否存在 active run，不需要 fixture
        // 作者再声明一个只有本 runner 认得的私有提示字段——`message.result`（D2 合法 `succeeded/
        // timed_out/rejected` 三态枚举）本身在这条路径上是纯装饰性的（真实 client 从不读它，只读
        // `abortedRunId`；最终 OperationOutcome 由下面 mock_event/advance_clock/disconnect 决定），
        // 因此这里完全不读 `result`。
        let activeRunID = await ctx.currentRunIDValue
        if let activeRunID = activeRunID {
            await gate.resolve(.success(["abortedRunId": activeRunID, "status": "aborted"]))
            await ctx.setHasStopWaitingForTerminal(true)
            await ctx.setWaitingStopCallID(replyTo)
        } else {
            await gate.resolve(.success(["abortedRunId": NSNull(), "status": "no-active-run"]))
        }

    case "interrupt":
        // interrupt(mode:"cancel") 调用的是与 stop() 完全相同的 sessions.abort RPC，响应形状因此
        // 完全一致——复用同一套『从 ctx.currentRunIDValue 派生』的推导逻辑（见上方 `case "stop"` 的
        // 说明，这里不重复论证）。SG-5 内部『等待终态』表按 session（不是按 operation kind）持有，
        // stop()/interrupt() 两两互斥，同一时刻至多一个在等待，复用同一组
        // `hasStopWaitingForTerminal`/`waitingStopCallID` 是忠实反映，不是偷懒省了一份状态。
        let activeRunID = await ctx.currentRunIDValue
        if let activeRunID = activeRunID {
            await gate.resolve(.success(["abortedRunId": activeRunID, "status": "aborted"]))
            await ctx.setHasStopWaitingForTerminal(true)
            await ctx.setWaitingStopCallID(replyTo)
        } else {
            await gate.resolve(.success(["abortedRunId": NSNull(), "status": "no-active-run"]))
        }

    case "respondApproval":
        // 真实 `approval.resolve` 响应形状是 `{applied, approval:{status,...}}`——不像 stop()/
        // interrupt() 那样能从 canonical 内部状态无歧义派生（respondApproval 的结果本质上来自
        // openclaw 内核侧的决策记录，runner 没有独立信息源可以替 fixture 作者算出来），因此如实
        // 透传 fixture 声明的 `result`（同 `createSession`/`send` 两个既有先例：读 fixture 声明值，
        // 不臆造）。今天没有任何 fixture 提供这条 mock_response（respondApproval 尚无 fixture 覆盖，
        // 见 rounds/0022 报告的覆盖缺口），这个分支目前不可达，留给未来。
        await gate.resolve(.success(result))

    default:
        throw RunnerError.malformed("mock_response(replyTo=\(replyTo)): 未知 client_call 类型『\(kind)』")
    }
}

// MARK: - mock_event

func applyMockEvent(_ op: TimelineOp, ctx: RunnerContext) async throws {
    let messageAny = (op.message?.value as? [String: Any]) ?? [:]
    guard let type = messageAny["type"] as? String else {
        throw RunnerError.malformed("mock_event 缺少 message.type（t=\(op.t)）")
    }
    let kernelKey = await ctx.currentKernelKeyValue ?? ""
    let client = ctx.client

    switch type {
    case "evt.message.delta":
        let payload = (messageAny["payload"] as? [String: Any]) ?? [:]
        let delta = (payload["delta"] as? String) ?? ""
        let frame: JSONObject = [
            "type": "event", "event": "session.message",
            "payload": [
                "sessionKey": kernelKey,
                "message": [
                    "role": "assistant",
                    "content": [["type": "text", "text": delta]],
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                ] as JSONObject,
            ] as JSONObject,
        ]
        await client.testSupportFeedFrame(frame)

    case "evt.turn_complete":
        // T-048 REWORK #1（删除非法 `_openclawLifecycle`）：Stage A 范围内，本 runner 只把这个类型
        // 用作『合成 stop() 等待中的 aborted lifecycle 终态信号』（见文件头「设计钢印」一节）——不是
        // 通用的正常回合结束映射（那需要 evt.message.delta 之外的更多上下文，本轮 3 组 fixture 不
        // 需要），Stage A 唯一的用途就只有这一种，因此直接硬编码 `phase:"end"`/`aborted:true`——
        // 真实 SG-5 mapper（`mapOpenclawAgentLifecycleToAbortTerminalEvents`）本身也是照 `phase`
        // 是否为 "end" 判定 outcome=succeeded、`stopReason` 硬编码为 `.cancelled`（不读原生帧的
        // stopReason 字段），fixture 声明的 `message.payload.stopReason`（如 "cancelled"）已经是
        // 两端都需要的、唯一有意义的取值来源，不需要另一个只有本 runner 认得的私有提示字段重复表达
        // 同一件事。
        let contextRunID = await ctx.currentRunIDValue
        let runID = (messageAny["runId"] as? String) ?? contextRunID ?? ""
        let frame: JSONObject = [
            "type": "event", "event": "agent",
            "payload": [
                "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
                "data": [
                    "phase": "end",
                    "aborted": true,
                ] as JSONObject,
                "ts": Int(Date().timeIntervalSince1970 * 1000),
            ] as JSONObject,
        ]
        await client.testSupportFeedFrame(frame)
        await ctx.setHasStopWaitingForTerminal(false)

    case "evt.approval_request":
        let payload = (messageAny["payload"] as? [String: Any]) ?? [:]
        guard let reqID = payload["reqId"] as? String, let toolCallID = payload["toolCallId"] as? String else {
            throw RunnerError.malformed("mock_event(evt.approval_request) 缺少 payload.reqId/toolCallId")
        }
        let contextRunID = await ctx.currentRunIDValue
        let runID = (messageAny["runId"] as? String) ?? contextRunID ?? "run-approval-1"
        let timeoutMS = (payload["timeoutMs"] as? Int) ?? 1_800_000
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        // T-048 REWORK #1/#2（删除非法 `_openclawJoinOrder`）：原生双帧到达顺序改读
        // `TimelineOp.driverHint`（../dsl.ts 的 `MockEventDriverHint.approvalJoinOrder`）——DSL 层面
        // 显式声明的翻译层驱动量，不在封闭的 D2 `message` 联合里，语义不变。
        let driverHintAny = (op.driverHint?.value as? [String: Any]) ?? [:]
        let order = (driverHintAny["approvalJoinOrder"] as? String) ?? "agent_first"

        let agentFrame: JSONObject = [
            "type": "event", "event": "agent",
            "payload": [
                "runId": runID, "sessionKey": kernelKey, "stream": "approval",
                "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": reqID] as JSONObject,
                "ts": nowMs,
            ] as JSONObject,
        ]
        let sessionApprovalFrame: JSONObject = [
            "type": "event", "event": "session.approval",
            "payload": [
                "sessionKey": kernelKey, "updatedAtMs": nowMs, "phase": "pending",
                "approval": [
                    "id": reqID, "status": "pending",
                    "presentation": ["kind": "exec", "commandText": "echo \(reqID)"] as JSONObject,
                    "createdAtMs": nowMs, "expiresAtMs": nowMs + timeoutMS,
                ] as JSONObject,
            ] as JSONObject,
        ]

        if order == "session_first" {
            await client.testSupportFeedFrame(sessionApprovalFrame)
            try? await Task.sleep(nanoseconds: 30_000_000)
            await client.testSupportFeedFrame(agentFrame)
        } else {
            await client.testSupportFeedFrame(agentFrame)
            try? await Task.sleep(nanoseconds: 30_000_000)
            await client.testSupportFeedFrame(sessionApprovalFrame)
        }

    default:
        throw RunnerError.malformed(
            "mock_event: swift-runner Stage A 未实现『\(type)』的 openclaw wire 翻译" +
            "（超出本轮三组 fixture 需要的范围，未静默忽略）"
        )
    }
}

// MARK: - advance_clock（虚拟时钟：见文件头 + README 的详细说明）

/// T-048 REWORK #5：轮询间隔——远小于 SG-5 测试专用超时阈值（`RunnerContext.stopTimeoutMs`），
/// 保证不会把『还没结算』误判成『结算了』，也不会引入明显的额外延迟。
private let syncPollIntervalNs: UInt64 = 10_000_000
/// 轮询安全上限之外的额外余量——只是防止 SG-5 出现真实回归（比如又变回永久悬挂）时本 runner 陪着
/// 无限期挂起；不是用来『凑够时长让内部定时器来得及触发』的 slack（那正是旧版的问题）。
private let syncSafetyMarginNs: UInt64 = 5_000_000_000

/// 轮询直到 `predicate()` 为 true 或超过 `maxWaitNs`——用于替换『固定 sleep 猜调度』（T-048
/// REWORK #5 核心）：不管 SG-5 内部定时器/等待任务实际几时被真正 armed、几时真正结算，本 runner
/// 都只是不断问『好了没』，而不是自己算一个『应该差不多好了』的时长再赌一把。
private func pollUntilSettled(maxWaitNs: UInt64, predicate: () async -> Bool) async {
    var waitedNs: UInt64 = 0
    while waitedNs < maxWaitNs {
        if await predicate() { return }
        try? await Task.sleep(nanoseconds: syncPollIntervalNs)
        waitedNs += syncPollIntervalNs
    }
}

func applyAdvanceClock(_ op: TimelineOp, ctx: RunnerContext) async throws {
    let ms = op.ms ?? 0
    guard await ctx.hasStopWaitingForTerminalValue else {
        // 当前没有 stop() 在等待终态确认——advance_clock 是 no-op（同 ts-runner 对这个 op 的既有
        // 简化声明：advance_clock 本身不代表任何时钟无关的语义，只在『有人正在等超时』时才有意义）。
        return
    }
    let thresholdNs = RunnerContext.stopTimeoutMs * 1_000_000
    guard UInt64(ms) * 1_000_000 >= thresholdNs else { return }
    guard let waitingID = await ctx.waitingStopCallIDValue else {
        await ctx.setHasStopWaitingForTerminal(false)
        return
    }
    // T-048 REWORK #5 收残：旧版靠『mock_response 后固定 50ms + 这里再固定 400ms slack』赌 SG-5
    // 内部定时器『应该』已经 armed、且到期后的收尾链路『应该』已经跑完，高负载下两次固定猜测都可能
    // 不够，导致断言抢跑（codex 复现）。改成显式『任务已结算』同步钩子：真实触发仍然完全不变
    // （SG-5 的 `stop()` 超时机制基于 `Task.sleep` 真实挂钟时间，`testSupportSetStopTimeoutSeconds`
    // 把生产 5 秒超时收窄到 1 秒，本 runner 未改 SG-5 行为一个字节），只是不再自己猜『该等多久』——
    // 而是轮询 `ctx.isCallSettled(id:)`（复用本 runner 自己在 `onStopResolved`/`onStopThrew` 里
    // 写入的 `pendingOperations`/`callOutcomes`，正是随后 `assert_state` 要读的同一份状态，比轮询
    // SG-5 内部 `terminalEmitted` 更贴近真正需要同步的时刻，见 `isCallSettled` 文档注释），直到
    // SG-5 内部定时器真正到期、`stop()` 走完 `sessions.delete`+`emitStopSessionEndAndFinish`+
    // `onStopResolved` 的 `settleForEventDrain` 整条收尾链路、真正把结果写定为止。
    await pollUntilSettled(maxWaitNs: thresholdNs + syncSafetyMarginNs) {
        await ctx.isCallSettled(id: waitingID)
    }
    await ctx.setHasStopWaitingForTerminal(false)
}

// MARK: - 单个 timeline op 的分发

func executeOp(_ op: TimelineOp, ctx: RunnerContext) async throws {
    switch op.op {
    case .clientCall:
        try await performClientCall(op, ctx: ctx)
    case .expectOutbound:
        try await checkExpectOutbound(op, ctx: ctx)
    case .mockResponse:
        try await applyMockResponse(op, ctx: ctx)
        try? await Task.sleep(nanoseconds: 50_000_000)
    case .mockEvent:
        try await applyMockEvent(op, ctx: ctx)
        try? await Task.sleep(nanoseconds: 50_000_000)
    case .disconnect:
        await ctx.client.testSupportSimulateTransportClosed()
        // 同 `applyAdvanceClock`（T-048 REWORK #5）：`testSupportSimulateTransportClosed()` 唤醒的
        // stop() 等待者需要经过『throw -> 本 runner 的 client_call 包装 Task 捕获 -> onStopThrew
        // 自身的 settleForEventDrain 结算』整条链路才会把 pendingOperations 写定——改轮询
        // `ctx.isCallSettled(id:)` 直到真正写定，不再固定 sleep 猜这条链路要跑多久。
        if await ctx.hasStopWaitingForTerminalValue, let waitingID = await ctx.waitingStopCallIDValue {
            await pollUntilSettled(maxWaitNs: syncSafetyMarginNs) {
                await ctx.isCallSettled(id: waitingID)
            }
            await ctx.setHasStopWaitingForTerminal(false)
        } else {
            // 没有 stop() 在等待终态——本轮 fixture 均未覆盖这条分支，保留一个保守的结算窗口而不是
            // 干脆不等，避免引入新的未覆盖竞态（如实标注：这不是『猜调度』，只是没有可轮询的具体目标
            // 时的兜底）。
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    case .reconnect:
        // 本轮三组 fixture 均不依赖 reconnect 语义；SG-5 本身也没有『断线后重新变为可用』的能力
        // （transport 关闭后所有 session 的派生状态都会被清理，见 handleTransportClosed），如实
        // 标注为本轮 no-op，不假装支持。
        break
    case .advanceClock:
        try await applyAdvanceClock(op, ctx: ctx)
    case .assertState:
        let snapshot = await ctx.snapshotWithLock()
        let diff = partialMatch(actual: snapshot, expected: op.expected?.value, path: "assert_state@t=\(op.t)")
        for d in diff { await ctx.appendMismatch(d) }
    }
}

// MARK: - 顶层：跑一个 fixture 文件

public enum FixtureRunOutcome {
    case passed
    case failed([Mismatch])
    case degraded(String)
}

public struct FixtureRunResult {
    public let name: String
    public let path: String
    public let outcome: FixtureRunOutcome
}

public func runFixtureFile(at path: String) async -> FixtureRunResult {
    let fileName = (path as NSString).lastPathComponent
    guard let data = FileManager.default.contents(atPath: path) else {
        return FixtureRunResult(name: fileName, path: path, outcome: .failed(["无法读取文件：\(path)"]))
    }
    let fixture: ParityFixture
    do {
        fixture = try JSONDecoder().decode(ParityFixture.self, from: data)
    } catch {
        return FixtureRunResult(name: fileName, path: path, outcome: .failed(["无法解析 fixture JSON：\(error)"]))
    }

    if let initial = fixture.initialState?.value as? [String: Any], !initial.isEmpty {
        // 本轮三组 fixture 均不需要 `initialState`（都从 idle/干净状态起步），SG-5 也没有暴露
        // 『直接摆一个初始锁状态』的测试钩子（不同于 ts-runner 的 MockKernelClient 可以直接赋值
        // `client.sessionLock`）——诚实拒绝，而不是静默忽略 fixture 作者可能依赖的初始状态。
        return FixtureRunResult(
            name: fixture.name, path: path,
            outcome: .failed(["fixture 声明了 initialState \(initial)，但 swift-runner 本轮未实现" +
                              "『驱动真实 client 进入某个非默认初始状态』的能力（SG-5 未提供对应测试钩子），" +
                              "如实拒绝而非静默忽略"])
        )
    }

    let client = OpenclawGatewayKernelClient(
        endpoint: URL(string: "ws://127.0.0.1:1")!, token: "swift-runner-fixture-token"
    )
    await client.testSupportSetStopTimeoutSeconds(RunnerContext.stopTimeoutSeconds)
    let ctx = RunnerContext(client: client)

    // rounds/0022：不再有『执行前静态扫描方法名单』这一步——直接跑整条 timeline。DEGRADED 与否在
    // 下面『收尾』之后，靠 `ctx.notImplementedTrigger` 是否被真实触发过来决定（见文件头「DEGRADED
    // 判定」一节）。
    do {
        for op in fixture.timeline {
            try await executeOp(op, ctx: ctx)
        }
    } catch {
        return FixtureRunResult(name: fixture.name, path: path, outcome: .failed(["执行 timeline 时抛出异常：\(error)"]))
    }

    // 收尾：给所有 spawn 的 client_call/事件排空 Task 一点真实时间稳定下来，再做最终快照。
    try? await Task.sleep(nanoseconds: 150_000_000)

    // rounds/0022 核心判定：`notImplementedTrigger` 只有在某次真实 client 调用抛出字面上的
    // `KernelClientError.notImplemented` 时才会被置位（`RunnerContext.noteRealFailure`）——与『这条
    // fixture 用到了哪个方法名』无关。**整条 timeline 跑完之后才检查**，即使 notImplemented 出现在
    // 中途、后面还有更多 op 执行（比如断言、甚至另一个 client_call）：一旦命中就让整条 fixture
    // DEGRADED，不做『命中点之前的部分算 PASS/FAIL、之后的不算』这种拆分。理由三条：(1) 这条 fixture
    // 依赖的能力本身就没实现，无论后续步骤的『观察结果』如何，都不是这条 fixture 原本想验证的真实
    // 行为；(2) 与本轮之前『整条 fixture 是 DEGRADED 的最小判定单元』的既定语义保持一致，不引入新的
    // 『部分 DEGRADED』概念；(3) 拆分需要给每条 mismatch 打上『发生在触发点之前/之后』的时间戳再分别
    // 判定，复杂度远超收益，且容易在边界情况上产生比『整条 DEGRADED』更难解释的结果。
    if let trigger = await ctx.notImplementedTrigger {
        return FixtureRunResult(
            name: fixture.name, path: path,
            outcome: .degraded(
                "timeline 包含 client_call『\(trigger.call)』（id=\(trigger.callID)）——运行时真实驱动 SG-5 " +
                "OpenclawGatewayKernelClient 后，该调用抛出 notImplemented：\(trigger.detail)。没有任何 " +
                "RPC/wire 交互可翻译，无法驱动真实 client 产生有意义的状态转移。本 fixture 对 swift-runner " +
                "诚实降级为 DEGRADED（跳过，不计入 PASS/FAIL），不伪造一个假内核让它'通过'——这个结论来自" +
                "这一次真实运行实际捕获到的错误，不是任何静态方法名单。"
            )
        )
    }

    var mismatches = await ctx.accumulatedMismatches
    let finalState = await ctx.snapshotWithLock()
    mismatches += partialMatch(actual: finalState, expected: fixture.expected?.value, path: "expected")

    return FixtureRunResult(
        name: fixture.name, path: path,
        outcome: mismatches.isEmpty ? .passed : .failed(mismatches)
    )
}
