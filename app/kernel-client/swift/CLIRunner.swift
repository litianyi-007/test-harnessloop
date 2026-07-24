// SG-4 Mac 最小壳：跑一次完整 connect -> createSession -> subscribe -> (观察) -> stop
// （sessions.abort + sessions.delete）闭环，把每一步的响应/事件打印出来。
//
// 对着的是本项目 kernels/openclaw submodule 起的隔离内核实例（默认 ws://127.0.0.1:18889），
// 不是用户全局 18789 实例——见 scratchpad/sg4-openclaw-run-recipe.md 现场说明。endpoint/token
// 可用环境变量覆盖，默认值就是本轮任务书给的隔离实例现场参数。

import Foundation

func runL1CloseLoop() async throws {
    let endpointString = ProcessInfo.processInfo.environment["SG4_KERNEL_URL"] ?? "ws://127.0.0.1:18889"
    let token = ProcessInfo.processInfo.environment["SG4_KERNEL_TOKEN"] ?? "sg4kernelclienttoken"
    guard let endpoint = URL(string: endpointString) else {
        throw KernelClientError.transport("invalid endpoint URL: \(endpointString)")
    }

    print("=== SG-4 kernel-client L1 闭环：createSession -> subscribe -> stop ===")
    print("endpoint: \(endpoint.absoluteString)")
    print("timestamp: \(ISO8601DateFormatter().string(from: Date()))")

    let client = OpenclawGatewayKernelClient(endpoint: endpoint, token: token)

    // SG-5 Stage B：断言模式收集器——见文件末 `EventAssertionCollector` 的文档注释。收完一轮后校验
    // seq 单调 / runId 一致 / 终态唯一三个不变量，而不是只靠肉眼看 describeEventFields 的输出。
    let assertionCollector = EventAssertionCollector()

    // STEP 1: connect + 握手
    let scopes = try await client.connect()
    print("\n[STEP 1] connect 完成，hello-ok scopes = \(scopes)")
    guard scopes.contains("operator.write") || scopes.contains("operator.admin") else {
        print("[WARN] scopes 里没有 operator.write/operator.admin，后续写操作大概率会 403 —— " +
              "参见 recipe §2：client.id/mode 必须是 \"cli\"/\"cli\" 才能保留自报 scopes")
        throw KernelClientError.protocolMismatch("missing operator.write/operator.admin scope after handshake")
    }

    // STEP 2: createSession（不传 message/task，零模型调用，见 recipe §3/§4）
    let config = Config(
        approvalProfile: nil,
        cwd: "/tmp/sg4-l1-stub-cwd",
        model: nil,
        newapiEndpoint: NewapiEndpoint(baseURL: "http://localhost:0/sg4-l1-unused", deploymentTokenRef: nil),
        resume: nil,
        sandbox: nil,
        toolset: nil
    )
    let handle = try await client.createSession(config: config)
    print("\n[STEP 2] createSession 完成")
    print("  our sessionId (D1 §2.1 步骤 1 预分配)      = \(handle.sessionID)")
    print("  kernelSessionId (openclaw 原生 key)         = \(handle.kernelSessionID ?? "<nil>")")
    print("  kernel                                     = \(handle.kernel.rawValue)")
    print("  billing.tokenRef (占位，本轮未铸造真 newapi token) = \(handle.billing.tokenRef)")

    // （可选，SG-5 验收用）：d3proxy 这类 per-session 计费代理需要先在外部把
    // handle.sessionID/kernelSessionID 映射进它自己的凭证表才能真正转发成功（见
    // OPENCLAW-ISOLATED-RUN-RECIPE.md 与 scratchpad/openclaw-iso3 现场脚本），createSession 和
    // 真正 send 之间留一个可配置的暂停窗口，给外部脚本一个 seed 的机会——不设置该环境变量时暂停为
    // 0，不影响默认行为。
    if let pauseMs = ProcessInfo.processInfo.environment["SG5_PRE_SEND_PAUSE_MS"].flatMap(UInt64.init),
       pauseMs > 0 {
        print("\n[PAUSE] 等待 \(pauseMs)ms，供外部脚本按 kernelSessionId=\(handle.kernelSessionID ?? "<nil>") seed 计费映射…")
        try await Task.sleep(nanoseconds: pauseMs * 1_000_000)
    }

    // STEP 3: subscribe
    let eventStream = await client.subscribe(session: handle)
    print("\n[STEP 3] subscribe 已发起（sessions.messages.subscribe），开始观察事件…")

    let observeTask = Task<Int, Never> {
        var count = 0
        do {
            for try await event in eventStream {
                count += 1
                print("  [event #\(count)] wireType=\(event.wireType) \(describeEventFields(event))")
                assertionCollector.record(event)
            }
        } catch {
            print("  事件流结束时携带错误: \(error)")
        }
        return count
    }

    // STEP 3.5（可选，SG-5）：send() 现已实现——设置 SG5_SEND_MESSAGE 环境变量即可驱动一次真实
    // send，为 Stage B（真 client 驱动 e2e）铺路。默认不发（不设该变量），行为与 SG-4 时一致：
    // 观察窗口内预期 0 条事件，只证明"订阅已建立、流没有立刻报错"。
    //
    // 注意：真正发出去会触发一次真实模型调用（走 openclaw 配置的 provider），且大概率需要先给
    // 这个 session 的 sessionId 在 D3-proxy 的 `session_newapi_tokens` 表里 seed 一条映射
    // （见 app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md 与 SG-5 现场探针脚本
    // scratchpad/openclaw-iso3/seed-upsert.cjs 风格的做法）——这个壳本身不做 seed，调用方需自行
    // 保证目标 openclaw 实例的 provider 已经能对这个 sessionId 转发成功。
    // SG-5 Stage B：send() 产出的 runId 是断言模式"runId 一致"检查的期望值来源——hoist 到
    // runL1CloseLoop 顶层作用域，好在 STEP 4 之后（stop 完成、observeTask 已 join）传给
    // printFinalAssertions。未走 send() 分支（没设 SG5_SEND_MESSAGE）时保持 nil，断言模式据此自动降级
    // 为"仅报告观察到的集合"，不误报 FAIL。
    var sentRunID: String?

    let sendMessage = ProcessInfo.processInfo.environment["SG5_SEND_MESSAGE"]
    if let sendMessage = sendMessage, !sendMessage.isEmpty {
        print("\n[STEP 3.5] send()：SG5_SEND_MESSAGE 已设置，发送一条真实消息…")
        let input = Input(kind: .text, text: sendMessage, parts: nil)
        let sendResult = try await client.send(session: handle, input: input)
        sentRunID = sendResult.runID
        print("  send() 完成: runId=\(sendResult.runID)（真正的模型输出走 STEP 3 的事件流异步到达）")
        let observeWindowNanos = UInt64(ProcessInfo.processInfo.environment["SG5_SEND_WAIT_MS"].flatMap { UInt64($0) } ?? 60_000) * 1_000_000
        try await Task.sleep(nanoseconds: observeWindowNanos)
        print("  send() 观察窗口结束")
    } else {
        // 本轮没有调用 send()（未设置 SG5_SEND_MESSAGE），观察窗口内预期不会有真实 session.message
        // 事件——这里只是证明"订阅已建立、流没有立刻报错"。
        try await Task.sleep(nanoseconds: 1_500_000_000)
        print("  观察窗口结束（1.5s，未调用 send，预期 0 条事件）")
    }

    // STEP 4: stop（sessions.abort + sessions.delete）——这一步会 finish 事件流的 continuation。
    print("\n[STEP 4] stop（sessions.abort + sessions.delete）")
    let stopResult = try await client.stop(session: handle)
    print("  stop 完成: operationId=\(stopResult.operationID) outcome=\(stopResult.outcome.rawValue)")

    let observedCount = await observeTask.value
    print("  事件流已关闭，观察窗口内共收到 \(observedCount) 条 session.message 事件")

    // SG-5 Stage B：`await observeTask.value` 已经建立了 observeTask 内部所有 `assertionCollector.record`
    // 调用与此刻之间的 happens-before 关系（结构化并发的 join），所以这里读取 collector 状态是安全的，
    // 不需要额外加锁——EventAssertionCollector 全程只在 observeTask 这一个 Task 里被写，join 之后才被读。
    assertionCollector.printFinalAssertions(expectedRunID: sentRunID, expectedOperationID: stopResult.operationID)

    await client.disconnect()
    print("\n=== L1 闭环 CLOSED OK: connect -> createSession -> subscribe -> stop ===")
}

/// SG-5 rework：codex 对抗审 T-044 指出上一轮 CLIRunner 只打印 `event.wireType`，看不到
/// `runId/seq/ts/toolCallId/output/usage/stopReason` 这些真正能暴露字段级缺陷（seq 倒退、approval
/// 串号、正常 end 误报 error、重复 operation terminal 等）的关键字段——本函数按事件种类逐一取出
/// 这些字段格式化，让 e2e 输出本身就足以肉眼核验映射正确性，不再只证明"有事件流过"。
func describeEventFields(_ event: EventMessageUnion) -> String {
    switch event {
    case .messageDelta(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) delta=\(String(e.payload.delta.prefix(60)).debugDescription)"
    case .thinking(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) visibility=\(e.payload.visibility.rawValue) delta=\(String(e.payload.delta.prefix(60)).debugDescription)"
    case .toolCall(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) toolCallId=\(e.payload.toolCallID) name=\(e.payload.name) status=\(e.payload.status.rawValue)"
    case .toolResult(let e):
        let outputPreview = String(describing: e.payload.output.value)
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) toolCallId=\(e.payload.toolCallID) isError=\(e.payload.isError) durationMs=\(e.payload.durationMS.map(String.init) ?? "-") output=\(String(outputPreview.prefix(80)))"
    case .approvalRequest(let e):
        return "runId=\(e.runID) seq=\(e.seq) ts=\(e.ts) reqId=\(e.payload.reqID) toolCallId=\(e.payload.toolCallID) kind=\(e.payload.kind.rawValue) timeoutMs=\(e.payload.timeoutMS) timeoutAuthority=\(e.payload.timeoutAuthority.rawValue) proposedDecision=\(e.payload.proposedDecision?.rawValue ?? "-")"
    case .error(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) code=\(e.payload.code.rawValue) message=\(e.payload.message.debugDescription) recoverable=\(e.payload.recoverable.rawValue) nativeCode=\(e.payload.nativeCode ?? "-")"
    case .turnComplete(let e):
        return "runId=\(e.runID) seq=\(e.seq) ts=\(e.ts) stopReason=\(e.payload.stopReason.rawValue) usage=\(e.payload.usage.map { "in=\($0.inputTokens ?? -1),out=\($0.outputTokens ?? -1)" } ?? "-") degraded=\(e.payload.degraded?.kind.rawValue ?? "-") forceResolvedApprovals=\(e.payload.forceResolvedApprovals?.joined(separator: ",") ?? "-")"
    case .sessionEnd(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) reason=\(e.payload.reason.rawValue)"
    case .capabilityChanged(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) source=\(e.payload.source.rawValue)"
    case .operationCompleted(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) operationId=\(e.payload.operationID) operationKind=\(e.payload.operationKind.rawValue) outcome=\(e.payload.outcome.rawValue) affectedRunId=\(e.payload.affectedRunID ?? "-") newRunId=\(e.payload.newRunID ?? "-") detail=\(e.payload.detail ?? "-")"
    case .approvalBufferResolved(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) reqId=\(e.payload.reqID) reason=\(e.payload.reason.rawValue)"
    }
}

// MARK: - SG-5 Stage B：断言模式（M6 遗留缺口的补完）
//
// Stage A（T-044/T-045）把 CLIRunner 从"只打 wireType"改成了上面这个 `describeEventFields`——逐变体
// 打印字段级明细，但止步于"打印出来给人肉眼看"。Stage B 任务书明确要求再加一层：**收完一轮后自动校验**
// 三个不变量，而不是靠人盯着日志数 seq。这三个不变量都不是随便定的，各自对应 EventMapping.swift 文件头
// 注释里记录的一处真实缺陷/契约点：
//   1. seq 单调（F3）：D1 v3 §9.2/§3 的 seq 承诺范围是"同一 runId 内"，不是全局单调——T-044 对抗审
//      复现过 `2→21→4→30` 这种混用 wire 帧外层 seq 与 messageSeq 导致的倒退。
//   2. runId 一致（M1 的姊妹检查）：同一次 send() 触发的所有 run-scoped 事件应挂在 send() 返回的那一个
//      runId 上，不应该看到"串号"到另一个 runId。
//   3. 终态唯一（M3）：stop() 状态机收敛后的承诺——同一个 operationId 的 evt.operation_completed
//      不应重复广播，一次 stop() 只应换来一条 sessionEnd，一次正常 run 只应有一条 turnComplete。
//
// 这个收集器只在 CLIRunner 这一个"跑一次真实 e2e、边收边核对"的场景下有意义——它不是给 FrameReplayTests
// 用的通用断言库（后者用真正的 XCTest 风格 assert，测的是 replay 固定帧），这里要的是"live 流不知道会收到
// 多少条、什么顺序的事件，收完了才能盘点"。
final class EventAssertionCollector: @unchecked Sendable {
    // 只在 observeTask 这一个 Task 内被 `record` 调用（write），在 `await observeTask.value` join 之后才被
    // `printFinalAssertions` 读取（read）——读写之间由结构化并发的 join 提供 happens-before，不存在真正的并发
    // 访问，`@unchecked Sendable` 只是告诉编译器"这里的隔离性由调用约定保证，不是靠锁"，如实标注不是绕过检查。
    private var lastSeqByRunScope: [String: Int] = [:]
    private var seqViolations: [String] = []
    private var observedRunIDs: Set<String> = []
    private var turnCompleteCountByRun: [String: Int] = [:]
    private var operationCompletedCountByOpID: [String: Int] = [:]
    private var operationCompletedOutcomeByOpID: [String: String] = [:]
    private var sessionEndReasons: [String] = []
    private(set) var totalEvents = 0

    /// 每收到一条 `EventMessageUnion` 就调用一次。只做记账，不打印——打印集中在 `printFinalAssertions`，
    /// 避免"边收边判"和"收完再判"两套输出交织，日志读起来更清楚。
    func record(_ event: EventMessageUnion) {
        totalEvents += 1
        let (runID, seq, kind) = envelope(event)

        // 断言 1 的记账：seq 的单调性只在"同一作用域"内有意义——D1 只承诺 runId 内单调，没有 runId 的
        // 事件（如 kernel 全局 shutdown 广播的 sessionEnd）退化用一个固定的 "<no-run>" 桶，同样要求桶内
        // 单调，但不与任何真正的 runId 桶混在一起比较。
        let scopeKey = runID ?? "<no-run>"
        if let last = lastSeqByRunScope[scopeKey], seq <= last {
            seqViolations.append("scope=\(scopeKey) 期望 seq>\(last)，实际 seq=\(seq)（kind=\(kind)）")
        }
        lastSeqByRunScope[scopeKey] = seq

        if let runID = runID {
            observedRunIDs.insert(runID)
        }

        switch event {
        case .turnComplete(let e):
            turnCompleteCountByRun[e.runID, default: 0] += 1
        case .operationCompleted(let e):
            operationCompletedCountByOpID[e.payload.operationID, default: 0] += 1
            operationCompletedOutcomeByOpID[e.payload.operationID] = e.payload.outcome.rawValue
        case .sessionEnd(let e):
            sessionEndReasons.append(e.payload.reason.rawValue)
        default:
            break
        }
    }

    private func envelope(_ event: EventMessageUnion) -> (runID: String?, seq: Int, kind: String) {
        switch event {
        case .messageDelta(let e): return (e.runID, e.seq, "messageDelta")
        case .thinking(let e): return (e.runID, e.seq, "thinking")
        case .toolCall(let e): return (e.runID, e.seq, "toolCall")
        case .toolResult(let e): return (e.runID, e.seq, "toolResult")
        case .approvalRequest(let e): return (e.runID, e.seq, "approvalRequest")
        case .error(let e): return (e.runID, e.seq, "error")
        case .turnComplete(let e): return (e.runID, e.seq, "turnComplete")
        case .sessionEnd(let e): return (e.runID, e.seq, "sessionEnd")
        case .capabilityChanged(let e): return (e.runID, e.seq, "capabilityChanged")
        case .operationCompleted(let e): return (e.runID, e.seq, "operationCompleted")
        case .approvalBufferResolved(let e): return (e.runID, e.seq, "approvalBufferResolved")
        }
    }

    /// 收完一轮（`stop()` 已返回、`observeTask` 已 join）后调用一次，打印三项断言的 PASS/FAIL/WARN/SKIP
    /// 结论。`expectedRunID` 传 `send()` 返回的 `SendResultPayload.runID`（没走 send() 分支时传 nil，
    /// 断言 2/3 里 run 相关的部分会降级为 SKIP，不误判 FAIL）；`expectedOperationID` 传 `stop()` 返回的
    /// `StopResultPayload.operationID`。
    func printFinalAssertions(expectedRunID: String?, expectedOperationID: String?) {
        print("\n=== [断言模式] 字段级不变量校验（共 \(totalEvents) 条事件） ===")

        // 断言 1：seq 在各自作用域（runId，或无 runId 事件的 <no-run> 桶）内严格单调递增。
        if seqViolations.isEmpty {
            print("  [PASS] seq 单调：所有 run/session 作用域内 seq 严格递增，无倒退/重复（\(lastSeqByRunScope.count) 个作用域）")
        } else {
            print("  [FAIL] seq 单调：\(seqViolations.count) 处违例")
            for v in seqViolations { print("    - \(v)") }
        }

        // 断言 2：runId 一致——不应观察到 expectedRunID 之外的其它 runId。
        if let expectedRunID = expectedRunID {
            let unexpected = observedRunIDs.subtracting([expectedRunID])
            if unexpected.isEmpty && observedRunIDs.contains(expectedRunID) {
                print("  [PASS] runId 一致：所有携带 runId 的事件均为期望值 \(expectedRunID)")
            } else if unexpected.isEmpty {
                print("  [WARN] runId 一致：未观察到任何携带期望 runId(\(expectedRunID)) 的事件（可能全程只收到 session 级事件，未观察到 run-scoped 事件）")
            } else {
                print("  [FAIL] runId 一致：观察到非期望 runId：\(unexpected.sorted())")
            }
        } else {
            print("  [SKIP] runId 一致：本轮未调用 send()（无期望 runId），仅报告观察到的集合：\(observedRunIDs.sorted())")
        }

        // 断言 3：终态唯一——turnComplete 每个 run 恰好 1 条、operationCompleted 每个 operationId 恰好 1
        // 条且与 stop() 返回值一致、sessionEnd 整个连接生命周期恰好 1 条。
        var terminalOK = true
        if let expectedRunID = expectedRunID {
            let tcCount = turnCompleteCountByRun[expectedRunID] ?? 0
            if tcCount == 1 {
                print("  [PASS] turnComplete 唯一：run=\(expectedRunID) 恰好 1 条")
            } else {
                terminalOK = false
                print("  [FAIL] turnComplete 唯一：run=\(expectedRunID) 出现 \(tcCount) 条（期望恰好 1 条）")
            }
        } else {
            print("  [SKIP] turnComplete 唯一：无期望 runId，跳过（观察到 \(turnCompleteCountByRun.count) 个 run 各自的 turnComplete 计数：\(turnCompleteCountByRun)）")
        }

        let dupOps = operationCompletedCountByOpID.filter { $0.value != 1 }
        if !dupOps.isEmpty {
            terminalOK = false
            print("  [FAIL] operationCompleted 唯一：以下 operationId 出现次数≠1：\(dupOps)")
        } else if let expectedOperationID = expectedOperationID {
            if let outcome = operationCompletedOutcomeByOpID[expectedOperationID] {
                print("  [PASS] operationCompleted 唯一且 operationId 一致：\(expectedOperationID) outcome=\(outcome)")
            } else {
                terminalOK = false
                print("  [FAIL] operationCompleted：未观察到期望 operationId=\(expectedOperationID) 的事件；实际集合=\(operationCompletedCountByOpID.keys.sorted())")
            }
        } else {
            print("  [PASS] operationCompleted 唯一：未见重复 operationId（共 \(operationCompletedCountByOpID.count) 个）")
        }

        if sessionEndReasons.count == 1 {
            print("  [PASS] sessionEnd 唯一：reason=\(sessionEndReasons[0])")
        } else if sessionEndReasons.isEmpty {
            terminalOK = false
            print("  [FAIL] sessionEnd 唯一：全程未收到 sessionEnd 事件（stop() 后预期恰好 1 条）")
        } else {
            terminalOK = false
            print("  [FAIL] sessionEnd 唯一：出现 \(sessionEndReasons.count) 条（\(sessionEndReasons)），期望恰好 1 条")
        }

        print(terminalOK ? "  [PASS] 终态唯一（综合三项）" : "  [FAIL] 终态唯一（综合，见上方明细）")
        print("=== [断言模式] 结束 ===")
    }
}
