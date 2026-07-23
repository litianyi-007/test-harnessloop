// SG-4 具体 WS 实现：直接对话一个正在运行的 openclaw Gateway 实例。
//
// 用 Foundation `URLSessionWebSocketTask`，无第三方依赖。握手/RPC 帧序列严格对照
// scratchpad/sg4-openclaw-run-recipe.md §2（鉴权握手）/§3（RPC 帧序列）——每一步都在 recipe 里
// 有逐字段的 `[实测]` 记录，本文件是把那份 recipe 变成可复用的 Swift 客户端代码。
//
// 用 `actor` 承载连接状态（WS task、pending 请求表、事件流表、sessionId 映射表）——并发安全靠
// actor 隔离保证，不需要手写锁。
//
// 本轮只完整实现 createSession / subscribe / stop 三个方法（SG-4 L1 闭环范围）；
// send/interrupt/respondApproval/capabilities 是 TODO 桩，理由见 KernelClient.swift 头注释。

import Foundation

public actor OpenclawGatewayKernelClient: KernelClient {
    private let endpoint: URL
    private let token: String
    private let urlSession: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    private var nextReqID = 0
    /// req id -> 等待该 id 对应 res 帧的 continuation。
    private var pending: [String: CheckedContinuation<JSONObject, Error>] = [:]
    /// 一次性等待"下一条指定名字的 event 帧"——仅用于握手期等 `connect.challenge`
    /// （它是服务端主动推送的 event，不是某个 req 的 res，所以不能走上面的 pending 表）。
    private var oneShotEventWaiters: [String: CheckedContinuation<JSONObject, Error>] = [:]
    /// 我们自己铸造的 SessionHandle.sessionId -> openclaw 原生 key（D1 §2.1：sessionId 是 adapter
    /// 预分配的寻址锚点，kernelSessionId/这里的 key 才是内核认得的、后续 RPC 真正要用的值）。
    private var kernelKeyBySessionID: [String: String] = [:]
    private var eventContinuations: [String: AsyncThrowingStream<EventMessageUnion, Error>.Continuation] = [:]

    public private(set) var lastHandshakeScopes: [String] = []
    public private(set) var lastHandshakeProtocol: Int?

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
        self.urlSession = URLSession(configuration: .default)
    }

    // MARK: - 连接 + 握手（recipe §2）

    /// 建立 WS 连接并完成 challenge -> connect 握手，返回 hello-ok 里协商到的 scopes——供调用方
    /// 核验"确实拿到了 operator.write/operator.admin 等写权限"（recipe §2 里最容易踩的坑：
    /// client.id/mode 不是 "cli"/"cli" 时握手仍会成功，但 scopes 会被服务端清空）。
    public func connect() async throws -> [String] {
        let t = urlSession.webSocketTask(with: endpoint)
        self.task = t
        t.resume()
        receiveLoopTask = Task { await self.receiveLoop() }

        let challenge = try await waitForNextEvent(named: "connect.challenge")
        prettyPrint("RECV connect.challenge", challenge)

        // 握手 params 逐字段对照 recipe §2 末尾"一次完整、可复制的最小 connect 请求"。
        let connectParams: JSONObject = [
            "minProtocol": 3,
            "maxProtocol": 4,
            "client": [
                "id": "cli",
                "version": "0.0.1",
                "platform": "darwin",
                "mode": "cli",
            ] as JSONObject,
            "caps": [] as [String],
            "role": "operator",
            "scopes": ["operator.admin"] as [String],
            "auth": ["token": token] as JSONObject,
        ]
        let hello = try await request(method: "connect", params: connectParams)
        prettyPrint("RECV hello-ok (connect response payload)", hello)

        if let proto = hello["protocol"] as? Int {
            lastHandshakeProtocol = proto
        }
        if let auth = hello["auth"] as? JSONObject, let scopes = auth["scopes"] as? [String] {
            lastHandshakeScopes = scopes
        }
        return lastHandshakeScopes
    }

    public func disconnect() {
        receiveLoopTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    // MARK: - KernelClient conformance

    public func createSession(config: Config) async throws -> SessionHandle {
        // openclaw 侧本轮只透传 label(+model)。D2 Config 的 cwd/newapiEndpoint/toolset/sandbox/
        // approvalProfile/resume 这些字段本轮未接入 openclaw 原生 CreateSessionConfig 的等价物
        // ——两边字段集并非天然一一对应（openclaw 的 sessions.create 走它自己的 schema，见 recipe
        // §3），完整字段级映射留给 SG-4/SG-5 后续；这里如实标注，不假装已经打通。
        var params: JSONObject = ["label": "sg4-kernel-client-l1"]
        if let model = config.model {
            params["model"] = model
        }
        let result = try await request(method: "sessions.create", params: params)
        prettyPrint("RECV sessions.create result", result)

        guard let kernelKey = result["key"] as? String else {
            throw KernelClientError.protocolMismatch("sessions.create result missing 'key' field")
        }
        let kernelSessionID = result["sessionId"] as? String

        // D1 §2.1 步骤 1：adapter 本地预分配 sessionId。本轮用一个新 UUID，不复用 openclaw 自己
        // 返回的 sessionId——两者语义不同（前者是 KernelPort 层面的稳定寻址锚点，早于原生会话
        // 存在；后者是内核自己认得的原生 id），本实现如实保留这个区分，写入
        // SessionHandle.kernelSessionId 的是 openclaw 的 `key`（后续 subscribe/abort/delete 真正
        // 需要用它寻址,不是 `sessionId` 字段）。
        let ourSessionID = UUID().uuidString
        kernelKeyBySessionID[ourSessionID] = kernelKey

        // billing.tokenRef 本轮是占位符——SG-4 没有实现 D1 §7 的 newapi token 铸造（那是 createSession
        // 内部执行序列步骤 2，需要真正调用 newapi POST /api/token/），如实标注，不虚构一个看起来
        // "真实"的值掩盖这个缺口。
        return SessionHandle(
            billing: Billing(tokenRef: "TODO-sg4-no-newapi-token-minted"),
            createdAt: Date(),
            kernel: .openclaw,
            kernelSessionID: kernelSessionID ?? kernelKey,
            sessionID: ourSessionID
        )
    }

    public func send(session: SessionHandle, input: Input) async throws -> SendResultPayload {
        throw KernelClientError.notImplemented(
            "send() defer 到 SG-8.1/L2——本项目隔离 openclaw 内核没有 mock provider，真实调用会触发" +
            "真实模型请求（sessions.create 的 resolved.model 已证实，见 recipe §4），本轮 L1 闭环刻意不跑它"
        )
    }

    public func subscribe(session: SessionHandle) async -> AsyncThrowingStream<EventMessageUnion, Error> {
        let ourSessionID = session.sessionID
        let (stream, continuation) = AsyncThrowingStream<EventMessageUnion, Error>.makeStream()
        eventContinuations[ourSessionID] = continuation

        Task {
            guard let kernelKey = await self.kernelKey(for: ourSessionID) else {
                continuation.finish(throwing: KernelClientError.protocolMismatch("unknown session \(ourSessionID)"))
                return
            }
            do {
                let result = try await self.request(method: "sessions.messages.subscribe", params: ["key": kernelKey])
                prettyPrint("RECV sessions.messages.subscribe result", result)
                if let subscribed = result["subscribed"] as? Bool, !subscribed {
                    continuation.finish(throwing: KernelClientError.protocolMismatch("subscribe returned subscribed:false"))
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    public func interrupt(session: SessionHandle, options: InterruptRequestMessagePayload) async throws -> InterruptResultPayload {
        throw KernelClientError.notImplemented("interrupt() 本轮 TODO 桩——L1 闭环没有 active run 需要 interrupt")
    }

    /// D1 §2.5 stop()。recipe §3 建议：有活跃 run 就先 abort，再 delete 彻底释放会话资源——本轮
    /// Mac 最小壳把 stop() 实现为这两步的组合（abort 负责"停止当前生成"，delete 负责"彻底关闭
    /// /清理会话"），并在 delete 之后把本地的 continuation/映射表一并清理掉。
    public func stop(session: SessionHandle) async throws -> StopResultPayload {
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        let abortResult = try await request(method: "sessions.abort", params: ["key": kernelKey])
        prettyPrint("RECV sessions.abort result", abortResult)

        let deleteResult = try await request(method: "sessions.delete", params: ["key": kernelKey])
        prettyPrint("RECV sessions.delete result", deleteResult)

        finishEventContinuation(sessionID: session.sessionID)
        kernelKeyBySessionID.removeValue(forKey: session.sessionID)

        let abortStatus = (abortResult["status"] as? String) ?? "unknown"
        let deleted = (deleteResult["deleted"] as? Bool) ?? false
        // D1 §2.5：stop() 可达的 outcome 子集是 succeeded/timed_out/rejected 三态。本适配把
        // "abort+delete 都顺利返回、delete 确认 deleted:true"记为 succeeded，否则记为 rejected——
        // 本轮没有构造让 delete 失败的场景，timed_out 分支未被 live 验证过（如实标注）。
        let outcome: StopResultPayloadOutcome = deleted ? .succeeded : .rejected
        let operationID = "\(session.sessionID)-stop-abort_\(abortStatus)"
        return StopResultPayload(operationID: operationID, outcome: outcome)
    }

    public func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws {
        throw KernelClientError.notImplemented("respondApproval() 本轮 TODO 桩——L1 闭环没有触发任何审批请求")
    }

    public func capabilities(session: SessionHandle?) async throws -> CapabilityDescriptorPayload {
        throw KernelClientError.notImplemented("capabilities() 本轮 TODO 桩——未探测 openclaw capabilities 端点")
    }

    // MARK: - 内部：session 映射表 + 事件流生命周期

    private func kernelKey(for ourSessionID: String) -> String? {
        kernelKeyBySessionID[ourSessionID]
    }

    private func finishEventContinuation(sessionID: String) {
        eventContinuations[sessionID]?.finish()
        eventContinuations.removeValue(forKey: sessionID)
    }

    // MARK: - 内部：RPC 请求/响应关联

    private func request(method: String, params: JSONObject) async throws -> JSONObject {
        guard let task = task else { throw KernelClientError.notConnected }
        nextReqID += 1
        let id = "r\(nextReqID)"
        let frame: JSONObject = ["type": "req", "id": id, "method": method, "params": params]
        prettyPrint("SEND req \(method)", frame)
        let data = try encodeFrame(frame)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONObject, Error>) in
            self.pending[id] = continuation
            task.send(.data(data)) { error in
                if let error = error {
                    Task { await self.failPending(id: id, error: KernelClientError.transport(error.localizedDescription)) }
                }
            }
        }
    }

    private func failPending(id: String, error: Error) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: error)
        }
    }

    private func waitForNextEvent(named eventName: String) async throws -> JSONObject {
        try await withCheckedThrowingContinuation { continuation in
            self.oneShotEventWaiters[eventName] = continuation
        }
    }

    // MARK: - 内部：接收循环

    private func receiveLoop() async {
        guard let task = task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    handleIncoming(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        handleIncoming(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                failAllPending(error: KernelClientError.transport("\(error)"))
                break
            }
        }
    }

    private func failAllPending(error: Error) {
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        for (_, waiter) in oneShotEventWaiters {
            waiter.resume(throwing: error)
        }
        oneShotEventWaiters.removeAll()
        for (_, cont) in eventContinuations {
            cont.finish(throwing: error)
        }
        eventContinuations.removeAll()
    }

    private func handleIncoming(_ data: Data) {
        guard let frame = try? decodeFrame(data) else { return }
        guard let type = frame["type"] as? String else { return }

        switch type {
        case "res":
            guard let id = frame["id"] as? String else { return }
            guard let continuation = pending.removeValue(forKey: id) else { return }
            let ok = (frame["ok"] as? Bool) ?? false
            if ok {
                let payload = (frame["payload"] as? JSONObject) ?? [:]
                continuation.resume(returning: payload)
            } else {
                let err = (frame["error"] as? JSONObject) ?? [:]
                let code = (err["code"] as? String) ?? "unknown"
                let message = err["message"] as? String
                continuation.resume(throwing: KernelClientError.rpcRejected(code: code, message: message))
            }

        case "event":
            guard let eventName = frame["event"] as? String else { return }
            if let waiter = oneShotEventWaiters.removeValue(forKey: eventName) {
                let payload = (frame["payload"] as? JSONObject) ?? [:]
                waiter.resume(returning: payload)
                return
            }
            if eventName == "session.message" {
                handleSessionMessageEvent(frame)
            } else {
                prettyPrint("RECV event \(eventName) (未处理的旁路事件，原样打印)", frame)
            }

        default:
            break
        }
    }

    private func handleSessionMessageEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String else {
            return
        }
        guard let ourSessionID = kernelKeyBySessionID.first(where: { $0.value == kernelKey })?.key else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        if let mapped = mapOpenclawSessionMessageToKernelEvent(payload, ourSessionID: ourSessionID) {
            continuation.yield(mapped)
        } else {
            prettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一，TODO 见 SG-5）", frame)
        }
    }
}
