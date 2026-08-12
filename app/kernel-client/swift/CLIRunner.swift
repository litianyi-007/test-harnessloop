// SG-4 Mac 最小壳：跑一次完整 connect -> createSession -> subscribe -> (观察) -> stop
// （sessions.abort + sessions.delete）闭环，把每一步的响应/事件打印出来。
//
// 对着的是本项目 kernels/openclaw submodule 起的隔离内核实例（默认 ws://127.0.0.1:18889），
// 不是用户全局 18789 实例——见 scratchpad/sg4-openclaw-run-recipe.md 现场说明。endpoint/token
// 可用环境变量覆盖，默认值就是本轮任务书给的隔离实例现场参数。

import Foundation
// `canImport` 门卫理由见 KernelClient.swift 同名注释。CLIRunner.swift 目前没有被任何 flat swiftc
// 命令引用（不在 ci.yml 的 parity-runner 步骤里），这里加同样的门卫纯粹是跟其余 4 个 kernel-client
// 文件保持一致，避免以后有人依样画瓢新增一条 flat 编译命令时又要单独想起这一处。
#if canImport(D2Generated)
import D2Generated
#endif

/// SG-10 起为 public：这是 kernel-client-cli executable target（app/kernel-client/swift/cli/
/// main.swift）跨模块调用的入口。裸 swiftc 时代 main.swift 和本文件同一次编译成隐式单一 module，
/// 不需要显式访问级别；拆成 SwiftPM 包后二者是两个不同 target，跨 target 调用必须是 public——
/// 这是唯一一处因为拆包而不得不放宽的访问级别（其余 internal 符号靠 frame-replay-tests target
/// 的 `-enable-testing` + `@testable import` 保持原有 internal 不变，见 app/Package.swift 注释）。
/// 函数体本身与 D1 §2 语义无关，未改一行逻辑。
public func runL1CloseLoop() async throws {
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
    // seq 单调 / runId 一致 / 终态唯一 / wire messageSeq 单调非递减四个不变量，而不是只靠肉眼看
    // describeEventFields 的输出。
    let assertionCollector = EventAssertionCollector()

    // rounds/0012 ③：注册 wire messageSeq 观察者——必须在 STEP 3 subscribe() 之前完成（实际上早于
    // 第一条 session.message 帧到达即可，这里选在 client 创建后立即注册，最简单、不依赖后续任何步骤
    // 顺序）。路径选择理由 + 代价见 OpenclawGatewayKernelClient.setWireMessageSeqObserver 的文档
    // 注释；`assertionCollector.recordMessageSeq` 与下面 STEP 3 的 observeTask 循环里调用的
    // `assertionCollector.record(_:)` 是两个不同的调用方/并发上下文，绝不可互相替代或混用数据源——
    // 见 EventAssertionCollector.recordMessageSeq 文档注释"两域绝不可混用"的说明。
    await client.setWireMessageSeqObserver { [assertionCollector] seq in
        assertionCollector.recordMessageSeq(seq)
    }

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

    // rounds/00xx C：RAE-0001 条件③(b) 对账要用 GET /sessions/<key>/history，这条路由要的是 openclaw
    // 的 `key` 字段（openclaw `sessions-history-http.ts:resolveSessionHistoryPath` 把 URL 路径段
    // 当 `key` 传给 `resolveGatewaySessionStoreTargetWithStore`），**不是**上面刚打印的
    // kernelSessionId——`OpenclawGatewayKernelClient.createSession()` 写入
    // `SessionHandle.kernelSessionID` 的是 wire 响应的 `sessionId` 字段（`kernelSessionID ??
    // kernelKey`，而 `sessions.create` 几乎总是带 `sessionId`，所以几乎总是走前一支），跟真正用于
    // subscribe/send/abort/delete 寻址、也是 history 路由要的那个 `key` 是两个独立来源的字段
    // （openclaw `session-create-service.ts:buildDashboardSessionKey` 与 `sessions-create.ts` 的
    // `key: created.key` / `sessionId: created.entry.sessionId` 各自独立生成）。这里用
    // `client.kernelKey(for:)`（本轮把它从 private 放宽到 internal，见该方法文档注释）取真正的
    // `key`，并按任务要求核实它是否与 kernelSessionID 恰好相同——不假设，交给运行时判断。
    let historyQueryKey = await client.kernelKey(for: handle.sessionID)
    if let historyQueryKey = historyQueryKey {
        print("[C] SESSION_KEY=\(historyQueryKey)")
        if historyQueryKey != handle.kernelSessionID {
            print("[C] NOTE: SESSION_KEY（openclaw `key` 字段，history 查询要用这个）与上面打印的 " +
                  "kernelSessionID（openclaw `sessionId` 字段，值=\(handle.kernelSessionID ?? "<nil>")）" +
                  "不是同一个值——GET /sessions/<key>/history 对账请认准 SESSION_KEY，用 " +
                  "kernelSessionID 会查错会话。")
        }
    } else {
        print("[C] WARN: 未能取得 openclaw key（unknown session \(handle.sessionID)）——SESSION_KEY 打印跳过，" +
              "事后无法用它查 history。")
    }

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

    // rounds/00xx C：RAE-0001 条件③(b) 取数需要"同一会话内多轮往返"，单条 SG5_SEND_MESSAGE 拿不到
    // ——新增 SG5_SEND_MESSAGES（复数，`||` 分隔多条消息）依次发送，每条之间等 SG5_SEND_WAIT_MS
    // （复用既有变量/默认值 60000ms，不新增一套等待配置）。纯加法：与 SG5_SEND_MESSAGE（单数）互不
    // 影响——两个都设时复数优先（打印一行提示，不静默吞掉单数）；只设单数、或都不设时，落进下面
    // `else if`/`else` 分支，分支体与此前逐字一致，一个字符没动。
    //
    // `sentRunID` 在多轮分支里刻意保持 nil（不赋值成最后一轮的 runId）：`EventAssertionCollector`
    // 断言 2/3（见文件末文档注释）按"单一期望 runId"设计——多轮场景下每一轮 send() 都会产生一个新
    // runId，天然存在多个合法 runId，把其中任意一个塞进 `printFinalAssertions(expectedRunID:)` 都会
    // 让其余轮次的合法 runId 被误判成"非期望" FAIL。传 nil 让断言 2/3 走既有的"无期望值"SKIP 分支——
    // 那个分支本身会把观察到的完整 runId 集合、以及各 run 各自的 turnComplete 计数打印出来，多轮场景
    // 下这份"如实报告观察到的集合"反而比强行代入单一期望值更准确，不是能力退化，也没有改
    // `EventAssertionCollector` 一个字。
    let sendMessage = ProcessInfo.processInfo.environment["SG5_SEND_MESSAGE"]
    let sendMessagesRaw = ProcessInfo.processInfo.environment["SG5_SEND_MESSAGES"]
    if let sendMessagesRaw = sendMessagesRaw, !sendMessagesRaw.isEmpty {
        if let sendMessage = sendMessage, !sendMessage.isEmpty {
            print("\n[STEP 3.5] 提示：SG5_SEND_MESSAGE 与 SG5_SEND_MESSAGES 同时设置，本轮以复数" +
                  "（多轮模式）为准，单数被忽略。")
        }
        let observeWindowNanos = UInt64(ProcessInfo.processInfo.environment["SG5_SEND_WAIT_MS"].flatMap { UInt64($0) } ?? 60_000) * 1_000_000
        let rounds = sendMessagesRaw.components(separatedBy: "||")
        print("\n[STEP 3.5] send()（多轮）：SG5_SEND_MESSAGES 已设置，共 \(rounds.count) 轮，依次发送…")
        for (index, roundMessage) in rounds.enumerated() {
            let roundNumber = index + 1
            let input = Input(kind: .text, text: roundMessage, parts: nil)
            let sendResult = try await client.send(session: handle, input: input)
            print("  [round \(roundNumber)/\(rounds.count)] send() 完成: runId=\(sendResult.runID)")
            try await Task.sleep(nanoseconds: observeWindowNanos)
            print("  [round \(roundNumber)/\(rounds.count)] 观察窗口结束")
        }
    } else if let sendMessage = sendMessage, !sendMessage.isEmpty {
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
    //
    // rounds/00xx C：SG5_SKIP_STOP=1 时跳过这一步——让会话在 openclaw 侧存活，事后可用上面打印的
    // SESSION_KEY 查 GET /sessions/<key>/history（stop() 里的 sessions.delete 会把会话删掉，history
    // 就再也查不到了）。下面 `else` 分支是原有默认路径，逐字未动。
    let skipStop = ProcessInfo.processInfo.environment["SG5_SKIP_STOP"] == "1"
    // 只有真正调用了 stop() 才有 operationId——skip-stop 时没有 stop 操作，保持 nil 让断言 3
    // （operationCompleted 唯一性）走 `printFinalAssertions` 既有的"无期望值，只报告有没有重复"分支，
    // 不会因为"没有 stop 操作"而被误判。
    var stopOperationID: String?

    if skipStop {
        print("\n[STEP 4] SG5_SKIP_STOP=1，跳过 stop()（sessions.abort + sessions.delete）——" +
              "会话在 openclaw 侧保留存活，事后可用上面的 SESSION_KEY 查 GET /sessions/<key>/history。")
        // 不调用 stop() 就没有任何路径会 finish 掉 STEP 3 那个事件流的 continuation
        // （`emitStopSessionEndAndFinish` 只在 `OpenclawGatewayKernelClient.stop()` 内部调用）——若
        // 像非 skip-stop 路径那样直接 `await observeTask.value`，`for try await` 会永远等下一条事件，
        // 整个函数、进而整个 CLI 进程会永久挂起，不满足"进程正常退出"的红线要求。
        //
        // 解法：先 `observeTask.cancel()`，再 `await observeTask.value`——`AsyncThrowingStream`
        // （`.makeStream()` 产出的这一种）对"消费者 Task 被 cancel"是协作式响应的：`for try await`
        // 会在下一次挂起点检测到取消、正常结束循环（不是 throw，返回值就是取消前已经数到的 count），
        // 不需要引入额外的超时竞速。这不是凭记忆假设——交付前用独立最小复现脚本验证过（continuation
        // 全程不 finish 的 `AsyncThrowingStream`，consumer task 消费到一半 `cancel()`：`for try
        // await` 立即正常退出，`await task.value` 在 <1ms 内返回，计数与取消前已 yield 的条数一致；
        // `cancel()` + `await .value` 之后再 `continuation.yield`/`continuation.finish` 也都不会
        // 崩溃，只是没有消费者在听）。
        observeTask.cancel()
    } else {
        print("\n[STEP 4] stop（sessions.abort + sessions.delete）")
        let stopResult = try await client.stop(session: handle)
        print("  stop 完成: operationId=\(stopResult.operationID) outcome=\(stopResult.outcome.rawValue)")
        stopOperationID = stopResult.operationID
    }

    // SG-5 Stage B（skip-stop 分支同样成立）：`await observeTask.value` 建立了 observeTask 内部所有
    // `assertionCollector.record` 调用与此刻之间的 happens-before 关系（结构化并发的 join）——
    // skip-stop 分支上面先 `cancel()` 再走到这里 `await .value`，同样先 join 才读，不直接读
    // collector，这个前提没有被破坏。之后读取 collector 状态是安全的，不需要额外加锁——
    // EventAssertionCollector 全程只在 observeTask 这一个 Task 里被写，join 之后才被读。
    let observedCount = await observeTask.value
    if skipStop {
        print("  事件流已停止观察（SG5_SKIP_STOP=1：未调用 stop()，不会有 sessionEnd；本地主动 " +
              "cancel 观察任务后干净退出），观察窗口内共收到 \(observedCount) 条 session.message 事件")
    } else {
        print("  事件流已关闭，观察窗口内共收到 \(observedCount) 条 session.message 事件")
    }

    assertionCollector.printFinalAssertions(expectedRunID: sentRunID, expectedOperationID: stopOperationID)

    await client.disconnect()
    if skipStop {
        print("\n=== L1 闭环 OPEN（SG5_SKIP_STOP=1，会话未 stop，可事后查 history）: " +
              "connect -> createSession -> subscribe -> (send) ===")
    } else {
        print("\n=== L1 闭环 CLOSED OK: connect -> createSession -> subscribe -> stop ===")
    }
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
// 不变量，而不是靠人盯着日志数 seq。这些不变量都不是随便定的，各自对应 EventMapping.swift 文件头注释
// 里记录的一处真实缺陷/契约点，或（断言 4）rounds/0012 的一次现场纠偏：
//   1. seq 单调（F3）：D1 v3 §9.2/§3 的 seq 承诺范围是"同一 runId 内"，不是全局单调——T-044 对抗审
//      复现过 `2→21→4→30` 这种混用 wire 帧外层 seq 与 messageSeq 导致的倒退。**这条验的是 D2
//      `EventMessageUnion` 每个 case 自带的 `.seq` 字段**——`OpenclawGatewayKernelClient.nextSeq
//      (runID:sessionID:)` 维护的 kernel-client 本地计数器（`(seqByRunID[runID] ?? 0) + 1`），结构
//      上不可能倒退（rounds/0012 scope-lock ③ 由此指出：这条断言对"丢帧"这类真实故障一无所证，见
//      断言 4）。
//   2. runId 一致（M1 的姊妹检查）：同一次 send() 触发的所有 run-scoped 事件应挂在 send() 返回的那一个
//      runId 上，不应该看到"串号"到另一个 runId。
//   3. 终态唯一（M3）：stop() 状态机收敛后的承诺——同一个 operationId 的 evt.operation_completed
//      不应重复广播，一次 stop() 只应换来一条 sessionEnd，一次正常 run 只应有一条 turnComplete。
//   4. **wire messageSeq 单调非递减（rounds/0012 ③ 新增）**：验的是 openclaw `session.message` wire
//      帧自己的 `payload.messageSeq`——**不是**上面断言 1 验的那个 D2 `.seq`。两者是完全不同的两个
//      域，千万不能混用或互相赋值——`EventMapping.swift:138-145`（"MARK: - F3：per-run seq 生成器
//      契约"）记录着这个项目自己吃过的教训：`a07dc67` 那一轮就是在 `session.message` 用
//      `messageSeq`、在 `agent` 事件用 wire 帧外层 `seq`，两个域混用导致同一个 run 观察到
//      `2→21→4→30`（对抗审 T-044 复现，就是上面第 1 点提到的那次）。`messageSeq` 从未进入 D2 判别
//      联合的任何字段，走的是完全独立的旁路——见 `recordMessageSeq` 与
//      `OpenclawGatewayKernelClient.setWireMessageSeqObserver` 的文档注释。这条断言**只捕获乱序/
//      倒退**，`item3-messageseq.md` §4 已经把边界钉死：**不**声称"无缺口"（transcript 侧计数，未
//      投递给本订阅者的条目合法占号，缺口不代表丢帧），也**不**声称能检测丢帧（该字段不承载"投递了
//      几条"的信息，本层没有这个信号）——这两点是本轮反复强调的纪律，这里如实标注，不越界断言。
//
// 断言 1-3 只在 CLIRunner 这一个"跑一次真实 e2e、边收边核对"的场景下有完整意义（`runId`/
// `operationId` 这些期望值只有真实 `send()`/`stop()` 才产出）——它们不是给 FrameReplayTests 用的
// 通用断言库（后者用真正的自写 assert 风格，测的是 replay 固定帧）。断言 4 是例外：它的数据源
// （`messageSeq` 整数序列）不依赖任何"这是一次真实 e2e"的上下文，`FrameReplayTests.swift`
// （`testWireMessageSeqAcceptsRealLegalNonDecreasingSequence`/`testWireMessageSeqDetectsRegression`，
// rounds/0012 ③）因此直接构造合成 wire 帧序列驱动它，覆盖"合法重复不误报"与"倒退必须变红"两个方向。
final class EventAssertionCollector: @unchecked Sendable {
    // 断言 1-3 的状态：只在 observeTask 这一个 Task 内被 `record` 调用（write），在
    // `await observeTask.value` join 之后才被 `printFinalAssertions` 读取（read）——读写之间由结构
    // 化并发的 join 提供 happens-before，不存在真正的并发访问，`@unchecked Sendable` 只是告诉编译
    // 器"这里的隔离性由调用约定保证，不是靠锁"，如实标注不是绕过检查。
    private var lastSeqByRunScope: [String: Int] = [:]
    private var seqViolations: [String] = []
    private var observedRunIDs: Set<String> = []
    private var turnCompleteCountByRun: [String: Int] = [:]
    private var operationCompletedCountByOpID: [String: Int] = [:]
    private var operationCompletedOutcomeByOpID: [String: String] = [:]
    private var sessionEndReasons: [String] = []
    private(set) var totalEvents = 0

    // 断言 4 的状态（rounds/0012 ③）：**不能**沿用上面那条 happens-before 论证——`recordMessageSeq`
    // 的调用方是 `OpenclawGatewayKernelClient` 自己的 actor 隔离执行上下文
    // （`handleSessionMessageEvent` 同步调用 `setWireMessageSeqObserver` 注册的闭包），跟
    // `record(_:)` 的调用方（`observeTask` 消费主事件流的循环）是两个不同的并发上下文；即使 actor
    // 的串行执行 + yield/finish 的 continuation 恢复大概率也能提供足够的跨线程可见性（这正是上面那
    // 条论证成立的根本原因），那也是一个更微妙、依赖"这次调用之后一定还有一次 yield 或 finish 把它
    // 带过 happens-before 边界"的论证——三个字段体量很小、锁的临界区极短，直接上锁换一个不需要读者
    // 重新验证微妙论证的结论，这笔成本值得付（详见 `recordMessageSeq` 文档注释）。
    private let messageSeqLock = NSLock()
    private var lastMessageSeq: Int?
    private var messageSeqViolationsStorage: [String] = []
    private var messageSeqObservedCountStorage = 0

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

    /// 断言 4（rounds/0012 ③）：由 `OpenclawGatewayKernelClient.setWireMessageSeqObserver` 注册的
    /// 闭包调用——每观察到一次 wire `session.message` 帧的 `payload.messageSeq` 就调用一次。
    /// **这是本收集器唯一一条不消费 `EventMessageUnion` 的断言**：`messageSeq` 是 openclaw 自己的
    /// transcript 消息计数字段（`item3-messageseq.md` §1 源码判定：
    /// `kernels/openclaw/src/gateway/server-session-events.ts:189-215`），从未进入 D2 11 变体判别
    /// 联合的任何字段——逐个检查过 `EventMessageUnion` 的 case，没有一个携带它，所以没法从 `record(_:)`
    /// 的参数里派生，只能走这条独立旁路。
    ///
    /// **两域绝不可混用**：断言 1（`lastSeqByRunScope`）验的是 D2 `EventMessageUnion` 每个 case 自带
    /// 的 `.seq`——`OpenclawGatewayKernelClient.nextSeq(runID:sessionID:)` 维护的 kernel-client 本地
    /// per-run 计数器，结构上不可能倒退。这里验的是 wire `payload.messageSeq`——openclaw 自己的
    /// session 级 transcript 计数，跟 D2 `.seq` 是两个完全独立、字面上不存在换算关系的域。**千万不要
    /// 试图把两者互相赋值或从一个反推另一个**——`a07dc67` 那一轮正是把这两个域混用（`session.message`
    /// 用 `messageSeq`、`agent` 事件用 wire 帧外层 `seq`），导致同一个 run 观察到 `2→21→4→30`（对抗审
    /// T-044 复现，见 `EventMapping.swift:138-145`）。
    ///
    /// **单调非递减，不是严格递增**：用 `<` 判违例（不是 `<=`）——`item3-messageseq.md` §2 实测坐实
    /// 合法重复（同一条 user 消息产生 status+delta 两帧、transcript 计数持平，真实样本
    /// `1,1,2,3,3,4,5,6`），严格递增会对合法重复误报。
    ///
    /// **只捕获乱序/倒退，不声称检测丢帧**：`item3-messageseq.md` §4 明文——`messageSeq` 不承载
    /// "投递了几条"的信息，transcript 侧未投递给本订阅者的条目也会合法占号（缺口≠丢帧），本层没有能
    /// 检测丢帧的信号。这条断言只对"看到的号往回走"这一件事负责，不多不少。
    ///
    /// **单 session 假设**：不按 sessionID 分桶（不像断言 1 按 runID 分桶）——`CLIRunner.runL1CloseLoop`
    /// 一次 close loop 只开一个 session，这里的"上一次观察到的 messageSeq"因此天然就是"这一个 session
    /// 的上一次"。如果这个收集器未来要服务多 session 场景，这里需要仿断言 1 的 `lastSeqByRunScope`
    /// 改成按 sessionID 分桶——如实标注为当前的一个范围限制，不是遗漏。
    ///
    /// 并发说明见上面 `messageSeqLock` 声明处的注释。
    func recordMessageSeq(_ messageSeq: Int) {
        messageSeqLock.lock()
        defer { messageSeqLock.unlock() }
        messageSeqObservedCountStorage += 1
        if let last = lastMessageSeq, messageSeq < last {
            messageSeqViolationsStorage.append(
                "期望 messageSeq>=\(last)（单调非递减，合法重复允许 ==），实际 messageSeq=\(messageSeq)（第 \(messageSeqObservedCountStorage) 次观察）"
            )
        }
        lastMessageSeq = messageSeq
    }

    /// 供 `printFinalAssertions` 与 `FrameReplayTests`（`@testable import`）读取断言 4 当前状态的
    /// 快照——同样过锁，不依赖"读者出现的时刻锁一定已经没有竞争者"这个额外假设（虽然实践中确实如此，
    /// 见 `recordMessageSeq` 文档注释的论证）。
    func messageSeqSnapshot() -> (observedCount: Int, violations: [String]) {
        messageSeqLock.lock()
        defer { messageSeqLock.unlock() }
        return (messageSeqObservedCountStorage, messageSeqViolationsStorage)
    }

    /// 收完一轮（`stop()` 已返回、`observeTask` 已 join）后调用一次，打印四项断言的 PASS/FAIL/WARN/SKIP
    /// 结论。`expectedRunID` 传 `send()` 返回的 `SendResultPayload.runID`（没走 send() 分支时传 nil，
    /// 断言 2/3 里 run 相关的部分会降级为 SKIP，不误判 FAIL）；`expectedOperationID` 传 `stop()` 返回的
    /// `StopResultPayload.operationID`。断言 4（wire messageSeq）不需要任何期望值参数——它只检查"看到
    /// 的号有没有往回走"，不依赖 send()/stop() 的返回值。
    func printFinalAssertions(expectedRunID: String?, expectedOperationID: String?) {
        print("\n=== [断言模式] 字段级不变量校验（共 \(totalEvents) 条 D2 事件；另有 messageSeq 独立计数，见断言 4） ===")

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

        // 断言 4（rounds/0012 ③）：wire messageSeq 单调非递减——见 recordMessageSeq 文档注释（唯一一
        // 条不消费 D2 event 的断言，数据来自 OpenclawGatewayKernelClient.setWireMessageSeqObserver
        // 旁路，与断言 1 的 D2 `.seq` 是两个绝不可混用的域）。0 次观察时降级为 SKIP，不误判 FAIL——
        // CLIRunner 没走 send() 分支、或全程没有任何 session.message 帧到达都是合法的"没有数据可
        // 判"，不是失败。
        let messageSeqResult = messageSeqSnapshot()
        if messageSeqResult.observedCount == 0 {
            print("  [SKIP] wire messageSeq 单调非递减：本轮未观察到任何 session.message 帧（未注册 setWireMessageSeqObserver，或注册了但全程 0 条 session.message 帧）")
        } else if messageSeqResult.violations.isEmpty {
            print("  [PASS] wire messageSeq 单调非递减：\(messageSeqResult.observedCount) 次观察全部非递减，无倒退")
        } else {
            print("  [FAIL] wire messageSeq 单调非递减：\(messageSeqResult.violations.count) 处违例")
            for v in messageSeqResult.violations { print("    - \(v)") }
        }

        print("=== [断言模式] 结束 ===")
    }
}
