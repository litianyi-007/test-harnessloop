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

    // STEP 3: subscribe
    let eventStream = await client.subscribe(session: handle)
    print("\n[STEP 3] subscribe 已发起（sessions.messages.subscribe），开始观察事件…")

    let observeTask = Task<Int, Never> {
        var count = 0
        do {
            for try await event in eventStream {
                count += 1
                print("  [event #\(count)] wireType=\(event.wireType)")
            }
        } catch {
            print("  事件流结束时携带错误: \(error)")
        }
        return count
    }

    // 本轮没有调用 send()（defer，见 recipe §4），观察窗口内预期不会有真实 session.message
    // 事件——这里只是证明"订阅已建立、流没有立刻报错"。
    try await Task.sleep(nanoseconds: 1_500_000_000)
    print("  观察窗口结束（1.5s，未调用 send，预期 0 条事件）")

    // STEP 4: stop（sessions.abort + sessions.delete）——这一步会 finish 事件流的 continuation。
    print("\n[STEP 4] stop（sessions.abort + sessions.delete）")
    let stopResult = try await client.stop(session: handle)
    print("  stop 完成: operationId=\(stopResult.operationID) outcome=\(stopResult.outcome.rawValue)")

    let observedCount = await observeTask.value
    print("  事件流已关闭，观察窗口内共收到 \(observedCount) 条 session.message 事件")

    await client.disconnect()
    print("\n=== L1 闭环 CLOSED OK: connect -> createSession -> subscribe -> stop ===")
}
