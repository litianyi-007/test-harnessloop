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
    let sendMessage = ProcessInfo.processInfo.environment["SG5_SEND_MESSAGE"]
    if let sendMessage = sendMessage, !sendMessage.isEmpty {
        print("\n[STEP 3.5] send()：SG5_SEND_MESSAGE 已设置，发送一条真实消息…")
        let input = Input(kind: .text, text: sendMessage, parts: nil)
        let sendResult = try await client.send(session: handle, input: input)
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
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) toolCallId=\(e.payload.toolCallID) name=\(e.payload.name)"
    case .toolResult(let e):
        let outputPreview = String(describing: e.payload.output.value)
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) toolCallId=\(e.payload.toolCallID) isError=\(e.payload.isError) durationMs=\(e.payload.durationMS.map(String.init) ?? "-") output=\(String(outputPreview.prefix(80)))"
    case .approvalRequest(let e):
        return "runId=\(e.runID) seq=\(e.seq) ts=\(e.ts) reqId=\(e.payload.reqID) toolCallId=\(e.payload.toolCallID) kind=\(e.payload.kind.rawValue) timeoutMs=\(e.payload.timeoutMS)"
    case .error(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) code=\(e.payload.code.rawValue) message=\(e.payload.message.debugDescription) recoverable=\(e.payload.recoverable.rawValue)"
    case .turnComplete(let e):
        return "runId=\(e.runID) seq=\(e.seq) ts=\(e.ts) stopReason=\(e.payload.stopReason.rawValue) usage=\(e.payload.usage.map { "in=\($0.inputTokens ?? -1),out=\($0.outputTokens ?? -1)" } ?? "-")"
    case .sessionEnd(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) reason=\(e.payload.reason.rawValue)"
    case .capabilityChanged(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) source=\(e.payload.source.rawValue)"
    case .operationCompleted(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) operationId=\(e.payload.operationID) outcome=\(e.payload.outcome.rawValue) affectedRunId=\(e.payload.affectedRunID ?? "-")"
    case .approvalBufferResolved(let e):
        return "runId=\(e.runID ?? "-") seq=\(e.seq) ts=\(e.ts) reqId=\(e.payload.reqID) reason=\(e.payload.reason.rawValue)"
    }
}
