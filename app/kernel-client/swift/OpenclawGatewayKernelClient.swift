// SG-4 具体 WS 实现：直接对话一个正在运行的 openclaw Gateway 实例。
//
// 用 Foundation `URLSessionWebSocketTask`，无第三方依赖。握手/RPC 帧序列严格对照
// scratchpad/sg4-openclaw-run-recipe.md §2（鉴权握手）/§3（RPC 帧序列）——每一步都在 recipe 里
// 有逐字段的 `[实测]` 记录，本文件是把那份 recipe 变成可复用的 Swift 客户端代码。
//
// 用 `actor` 承载连接状态（WS task、pending 请求表、事件流表、sessionId 映射表）——并发安全靠
// actor 隔离保证，不需要手写锁。
//
// SG-4 完整实现了 createSession / subscribe / stop 三个方法（L1 闭环范围）；SG-5 本轮补上
// send()，并把事件 dispatch 从"只认 session.message"扩展到同时处理 agent(command_output/
// lifecycle)/session.approval/全局 shutdown 四类 wire 事件，为 EventMapping.swift 完整覆盖 D2
// 11 变体提供真实触发路径（见该文件头注释①~⑥ 的逐条 grounding）。interrupt/respondApproval/
// capabilities 仍是 TODO 桩，理由见 KernelClient.swift 头注释。

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

    // MARK: SG-5 新增：事件映射需要的最小逐 session 状态缓存
    //
    // openclaw 的 wire 事件本身不总是自带 D2 判别联合要求的全部字段（最典型的是 turnComplete/
    // operationCompleted/approvalRequest 都要求非空的 runID，但 session.approval 事件本身不带
    // runId；approvalRequest 还要求 toolCallID，但 openclaw 的审批 payload 本身不带 toolCallId——
    // 见 EventMapping.swift ③④ 的文档注释）。这三个字典只做"记住同一 session 内最近一次见到的
    // 真实值，供后续同 session 的事件借用"，不做任何跨 session 关联、不编造数据；缺失时对应的
    // mapper 会诚实返回 nil 而不是用占位符填充必填字段。
    private var lastRunIDBySessionID: [String: String] = [:]
    private var lastToolCallIDBySessionID: [String: String] = [:]
    private var lastUsageBySessionID: [String: (input: Int, output: Int)] = [:]

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

    /// D1 §2.2 send()。适配为 openclaw `sessions.send`（recipe §3.3 params:
    /// `{key, agentId?, message, thinking?, attachments?, timeoutMs?, idempotencyKey?}`）。
    ///
    /// **返回语义**（SG-5 实测坐实，`scratchpad/openclaw-iso3` 隔离 openclaw + D3-proxy + 真实
    /// Kimi）：`sessions.send` 的 RPC 响应是一次同步 ack，形状
    /// `{"runId":"...","status":"started","messageSeq":1}`——不是模型的最终输出。真正的 agent
    /// 输出（assistant 文本/工具调用/工具结果/回合结束……）全部经由已建立的 `subscribe()` 事件流
    /// 异步到达（`session.message`/`agent`/`session.approval` 等 wire 事件，见 EventMapping.swift）。
    /// 这与 D1 SendResultPayload 的窄腰语义完全对应：`send()` 只承诺"这次输入被接受、拿到一个
    /// runId"，不承诺任何输出内容——因此本实现只取 wire 响应的 `runId` 字段构造
    /// `SendResultPayload(runID:)`，忽略 `status`/`messageSeq` 这两个 openclaw 专有、D1 SendResultPayload
    /// 没有对应字段的值。
    ///
    /// 拿到 runId 后立刻缓存到 `lastRunIDBySessionID`——EventMapping 里 turnComplete/
    /// operationCompleted/approvalRequest 三个必填 runID 字段都是从这个缓存借的（见类头 SG-5
    /// 状态缓存注释），subscribe() 的事件处理路径也会在观察到 `agent` 事件的 payload.runId 时
    /// 持续刷新它，send() 这里只是最早的一次写入来源。
    public func send(session: SessionHandle, input: Input) async throws -> SendResultPayload {
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        var params: JSONObject = [
            "key": kernelKey,
            "message": resolveSendMessageText(from: input),
            "timeoutMs": 0,
        ]
        // 结构化 attachments 透传——openclaw `SessionsSendParamsSchema.attachments` 本身是
        // `Type.Array(Type.Unknown())`（recipe/源码均未见到逐字段 schema），这里只在 D1 Input
        // 确有非文本 part 时才附带一个最小 {mimeType?, path?} 形状，如实标注：这不是对着某个
        // 已验证的 openclaw attachment schema 抄的，是"尽量不丢信息"的最佳努力透传，未 grounding。
        if input.kind == .structured, let parts = input.parts {
            let attachments: [JSONObject] = parts.compactMap { part in
                guard part.kind != .text else { return nil }
                var obj: JSONObject = [:]
                if let mime = part.mimeType { obj["mimeType"] = mime }
                if let path = part.path { obj["path"] = path }
                return obj.isEmpty ? nil : obj
            }
            if !attachments.isEmpty {
                params["attachments"] = attachments
            }
        }

        let result = try await request(method: "sessions.send", params: params)
        prettyPrint("RECV sessions.send result", result)

        guard let runID = result["runId"] as? String else {
            throw KernelClientError.protocolMismatch("sessions.send result missing 'runId' field")
        }
        lastRunIDBySessionID[session.sessionID] = runID
        return SendResultPayload(runID: runID)
    }

    /// D1 Input -> openclaw `sessions.send.message`（纯文本字符串）的最小转换。`kind:.text` 直接用
    /// `input.text`；`kind:.structured` 把 `parts` 里 `kind:.text` 的段落用换行拼接（非文本 part
    /// 走上面 attachments 分支，不混进正文），三者都拿不到文本时退化为空字符串而不是抛错——openclaw
    /// 的 `SessionsSendParamsSchema.message` 是必填 `Type.String()`，允许空串（recipe 未标注拒绝
    /// 空消息），比在这里主观拒绝更贴近"如实转发调用方输入"的适配器职责。
    private func resolveSendMessageText(from input: Input) -> String {
        if input.kind == .text {
            return input.text ?? ""
        }
        let texts = (input.parts ?? []).compactMap { part -> String? in
            guard part.kind == .text else { return nil }
            return part.text
        }
        return texts.joined(separator: "\n")
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
                // includeApprovals:true——SG-5 新增：不带这个 flag 收不到 session.approval 事件
                // （recipe 未记录、本轮现场探针实测坐实：`SessionsMessagesSubscribeParamsSchema`
                // 的 `includeApprovals` 是 opt-in，默认不推送），approvalRequest 映射的现场 grounding
                // 全部建立在这个 flag 打开的前提上（见 EventMapping.swift ④）。
                let result = try await self.request(
                    method: "sessions.messages.subscribe",
                    params: ["key": kernelKey, "includeApprovals": true]
                )
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
        // SG-5 状态缓存一并清理，避免长生命周期的 client 无限累积已经 stop() 掉的 session 的
        // runId/toolCallId/usage 缓存。
        lastRunIDBySessionID.removeValue(forKey: sessionID)
        lastToolCallIDBySessionID.removeValue(forKey: sessionID)
        lastUsageBySessionID.removeValue(forKey: sessionID)
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
                // SG-5：传输中断前先尽力给每个活跃 session 的事件流补一条 sessionEnd
                // (reason:.transportClosed)——本轮未现场实测这条路径本身（现场实测的是"先收到
                // 全局 shutdown 事件、WS 随后才断开"这条更常见的优雅关闭路径，见
                // makeSessionEndEventForShutdown 的文档注释），是源码/设计层面的合理补全：调用方
                // 不应该只看到事件流因为一个裸 Error 而 finish、却不知道"session 结束"这件事本身
                // 也是 D1 11 变体之一。
                for (ourSessionID, continuation) in eventContinuations {
                    continuation.yield(makeSessionEndEventForTransportClosed(ourSessionID: ourSessionID, seq: 0))
                }
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
            // SG-5：session.message 之外还要分发 agent(command_output/lifecycle)、
            // session.approval、全局 shutdown 三类 wire 事件——D2 11 变体里除
            // message_delta/thinking/tool_call 之外的大多数（tool_result/turn_complete/
            // operation_completed/approval_request/session_end）都不是从 session.message 来的，
            // 见 EventMapping.swift 头注释①~⑤ 的现场 grounding。
            switch eventName {
            case "session.message":
                handleSessionMessageEvent(frame)
            case "agent":
                handleAgentEvent(frame)
            case "session.approval":
                handleSessionApprovalEvent(frame)
            case "shutdown":
                handleShutdownEvent(frame)
            default:
                prettyPrint("RECV event \(eventName) (未处理的旁路事件，原样打印)", frame)
            }

        default:
            break
        }
    }

    /// 按 openclaw 原生 key 反查我们自己铸造的 sessionID——四个事件 handler（session.message/
    /// agent/session.approval）共享同一套"payload.sessionKey -> ourSessionID -> continuation"
    /// 查找逻辑，抽成一个小helper 避免重复。
    private func ourSessionID(forKernelKey kernelKey: String) -> String? {
        kernelKeyBySessionID.first(where: { $0.value == kernelKey })?.key
    }

    private func handleSessionMessageEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        // 顺带刷新 runId/usage 缓存——session.message 的 session 快照里带 activeRunIds，assistant
        // 消息自己带 usage，这两个都是别的事件（approvalRequest/turnComplete）必填字段的唯一
        // 现场来源（见 EventMapping.swift 头注释与状态缓存字段的文档注释）。
        if let sessionSnapshot = payload["session"] as? JSONObject,
           let activeRunIDs = sessionSnapshot["activeRunIds"] as? [Any],
           let firstRunID = activeRunIDs.first as? String {
            lastRunIDBySessionID[ourSessionID] = firstRunID
        }
        if let message = payload["message"] as? JSONObject, let usage = message["usage"] as? JSONObject,
           let input = jsonInt(usage["input"]), let output = jsonInt(usage["output"]) {
            lastUsageBySessionID[ourSessionID] = (input: input, output: output)
        }

        let events = mapOpenclawSessionMessageToKernelEvents(
            payload, ourSessionID: ourSessionID, runIDHint: lastRunIDBySessionID[ourSessionID]
        )
        if events.isEmpty {
            prettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一）", frame)
            return
        }
        for event in events {
            if case .toolCall(let toolCall) = event {
                // approvalRequest 的 toolCallID 借用"同 session 最近一次 toolCall"做时序关联
                // （openclaw 审批 payload 本身不带 toolCallId，见 EventMapping.swift ④ 文档注释）。
                lastToolCallIDBySessionID[ourSessionID] = toolCall.payload.toolCallID
            }
            continuation.yield(event)
        }
    }

    /// `agent` wire 事件——`payload.stream` 分好几种，本轮只把 `command_output`(phase:end) 映射到
    /// toolResult、`lifecycle`(phase:end/error) 映射到 turnComplete/operationCompleted；其余
    /// stream（run_status/item/usage/assistant，均为 openclaw 自有 UI 进度信号，D1 11 变体没有
    /// 对应位置）原样打印、不映射，见 EventMapping.swift ②③ 的现场 grounding 与范围声明。
    private func handleAgentEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        // agent 事件的 payload.runId 是本轮拿到 runIDHint 最可靠的现场来源之一（session.create
        // 之后、真正 send() 之前也可能已经有别的 run 在跑），顺带刷新缓存。
        if let runID = payload["runId"] as? String {
            lastRunIDBySessionID[ourSessionID] = runID
        }

        guard let stream = payload["stream"] as? String, let data = payload["data"] as? JSONObject else {
            return
        }
        let seq = jsonInt(frame["seq"]) ?? (jsonInt(payload["seq"]) ?? 0)
        let runIDHint = lastRunIDBySessionID[ourSessionID]

        switch stream {
        case "command_output":
            if let event = mapOpenclawAgentCommandOutputToToolResult(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, seq: seq
            ) {
                continuation.yield(event)
            }
        case "lifecycle":
            if let event = mapOpenclawAgentLifecycleToKernelEvent(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, seq: seq,
                cachedUsage: lastUsageBySessionID[ourSessionID]
            ) {
                continuation.yield(event)
            }
        default:
            // run_status/item/usage/assistant 等：openclaw 自有 UI 进度信号，D1 11 变体没有对应
            // 位置，如实不映射（不是遗漏，见 EventMapping.swift ②③ 范围声明）。
            break
        }
    }

    /// `session.approval` wire 事件——subscribe() 已在 `sessions.messages.subscribe` 参数里带上
    /// `includeApprovals:true`（见 subscribe() 实现），否则收不到这个事件。
    private func handleSessionApprovalEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard let continuation = eventContinuations[ourSessionID] else { return }

        let seq = jsonInt(frame["seq"]) ?? 0
        if let event = mapOpenclawSessionApprovalToKernelEvent(
            payload, ourSessionID: ourSessionID,
            runIDHint: lastRunIDBySessionID[ourSessionID],
            lastToolCallIDHint: lastToolCallIDBySessionID[ourSessionID],
            seq: seq
        ) {
            continuation.yield(event)
        } else {
            prettyPrint("RECV session.approval（phase:terminal 或缺关联字段，D1 11 变体无对应/跳过）", frame)
        }
    }

    /// gateway 全局 `shutdown` 事件——对所有当前活跃 session 各广播一条 sessionEnd(reason:
    /// .kernelExited)，见 EventMapping.swift ⑤ 的现场 grounding（对隔离 gateway 发 SIGTERM 实测）。
    private func handleShutdownEvent(_ frame: JSONObject) {
        let seq = jsonInt(frame["seq"]) ?? 0
        prettyPrint("RECV event shutdown（向所有活跃 session 广播 sessionEnd(reason:kernelExited)）", frame)
        for (ourSessionID, continuation) in eventContinuations {
            continuation.yield(makeSessionEndEventForShutdown(ourSessionID: ourSessionID, seq: seq))
        }
    }
}
