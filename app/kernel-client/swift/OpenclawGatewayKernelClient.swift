// SG-4 具体 WS 实现：直接对话一个正在运行的 openclaw Gateway 实例。
//
// 用 Foundation `URLSessionWebSocketTask`，无第三方依赖。握手/RPC 帧序列严格对照
// scratchpad/sg4-openclaw-run-recipe.md §2（鉴权握手）/§3（RPC 帧序列）——每一步都在 recipe 里
// 有逐字段的 `[实测]` 记录，本文件是把那份 recipe 变成可复用的 Swift 客户端代码。
//
// 用 `actor` 承载连接状态（WS task、pending 请求表、事件流表、sessionId 映射表）——并发安全靠
// actor 隔离保证，不需要手写锁。
//
// SG-4 完整实现了 createSession / subscribe / stop 三个方法（L1 闭环范围）；SG-5 Stage A 补上
// send()，并把事件 dispatch 从"只认 session.message"扩展到同时处理 agent(command_output/
// lifecycle)/session.approval/全局 shutdown 四类 wire 事件；本轮（SG-5 rework，对抗审 T-044
// REWORK 后的返工）在此基础上：
//   F1 — send() 加 D1 §9.3 session 级互斥锁（send_pending/stop_in_progress），run/tool/usage 缓存
//        改为 per-run（不是 per-session），避免并发 send/串 run。
//   F2 — attachment 改发 openclaw 期望的 `content`（base64）编码，不再发会被丢弃的 `{mimeType,path}`。
//   F3 — 统一 per-run 单调 seq 域（`nextSeq(runID:sessionID:)`），保留 openclaw 原始 ts，不用 Date()
//        冒充事件发生时刻（`sentAt` 才是 Date()，语义是"适配器本地转发时刻"）。
//   F4 — approval 关联改用 `agent(stream:"approval")` 的准确 `toolCallId`/`approvalId`，去掉"最近
//        一次 toolCall"的猜测。
//   F5 — 新增 `agent(stream:"thinking"/"error"/"item")` dispatch（非 exec 工具、真实 error 流）。
//   F6 — stop() 用adapter 铸造的唯一 operationId 贯穿 Promise -> operation_completed ->
//        turn_complete(cancelled) -> session_end(stopped)；合法无 stopReason 的 phase:end 不再默认
//        error（见 EventMapping.swift）。
//   F7 — prettyPrint 统一递归脱敏 auth/token 等凭证字段，不再明文打印。
//   F8 — shutdown/transportClosed/stop 三条 sessionEnd 路径共享一个"已产出 terminal"标记，去重。
// interrupt/respondApproval/capabilities 仍是 TODO 桩，理由见 KernelClient.swift 头注释——本轮未
// 触碰这三个方法体，只在需要它们才能修的地方记 blocker（见交付报告）。

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

    // MARK: F1 — send/stop 的 session 级互斥锁（D1 v3.1 §9.3，v3.6 继承）
    //
    // interrupt() 本轮仍是 TODO 桩，因此完整互斥矩阵里涉及 interrupt_in_progress 的分支（stop 优先
    // 仲裁等）本轮不适用——这里只需要覆盖 send()/stop() 两两互斥：任一方法执行时若锁不是 idle，
    // 一律 reject(session_locked)，不做特殊仲裁。
    private enum SessionLockState: Equatable, CustomStringConvertible {
        case idle
        case sendPending
        case stopInProgress

        var description: String {
            switch self {
            case .idle: return "idle"
            case .sendPending: return "send_pending"
            case .stopInProgress: return "stop_in_progress"
            }
        }
    }
    private var lockStateBySessionID: [String: SessionLockState] = [:]

    // MARK: F6 — stop() 的 pending 状态（adapter 铸造的唯一 operationId + 等待终态确认）
    private struct PendingStop {
        let operationID: String
        let affectedRunID: String?
        var terminalEmitted: Bool = false
        var waiter: CheckedContinuation<Bool, Never>?
    }
    private var pendingStops: [String: PendingStop] = [:]

    // MARK: F8 — 三条 sessionEnd 路径（shutdown/transportClosed/stop）共享的去重标记
    private var sessionTerminalEmitted: Set<String> = []

    // MARK: SG-5 事件映射需要的最小逐 session/run 状态缓存
    //
    // openclaw 的 wire 事件本身不总是自带 D2 判别联合要求的全部字段（最典型的是 turnComplete/
    // operationCompleted/approvalRequest 都要求非空的 runID，但 session.approval 事件本身不带
    // runId；approvalRequest 还要求 toolCallID，但 openclaw 的审批 payload 本身不带 toolCallId）。
    // F1 订正：run/tool/usage 三个缓存改为 **per-run**（用 runId 做键），不再是 per-session——
    // per-session 缓存在并发/连续多个 run 的场景下会把上一个 run 的残留值串给下一个 run（对抗审
    // T-044 F1 复现场景），per-run 键天然避免这个问题：新 run 开始时缓存自然是空的。
    private var lastRunIDBySessionID: [String: String] = [:]
    private var runIDsBySessionID: [String: Set<String>] = [:] // 供 session 结束时批量清理 per-run 缓存
    private var lastToolCallIDByRunID: [String: String] = [:]
    private var lastUsageByRunID: [String: (input: Int, output: Int)] = [:]
    /// F4：`agent(stream:"approval", phase:"requested")` 的 approvalId -> toolCallId 精确映射，
    /// 取代上一轮"同 session 最近一次 toolCall"的猜测。一次性缓存，用过即清（同一个 approvalId
    /// 不会有第二次 pending）。
    private var toolCallIDByApprovalID: [String: String] = [:]

    // MARK: F3 — per-run 单调 seq 域
    private var seqByRunID: [String: Int] = [:]
    /// 没有 runId 的事件（sessionEnd 等）退化为按 session 走一个独立递增序列——D1 只承诺"同一 runId
    /// 内排序"，这里只是让无 run 归属的事件也至少非递减，不是额外的契约承诺。
    private var seqFallbackBySessionID: [String: Int] = [:]

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
        // §3），完整字段级映射留给后续轮次；这里如实标注，不假装已经打通。
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
    /// **返回语义**（SG-5 实测坐实）：`sessions.send` 的 RPC 响应是一次同步 ack，形状
    /// `{"runId":"...","status":"started","messageSeq":1}`——不是模型的最终输出。真正的 agent
    /// 输出全部经由已建立的 `subscribe()` 事件流异步到达。本实现只取 wire 响应的 `runId` 字段构造
    /// `SendResultPayload(runID:)`。
    ///
    /// **F1 rework**：D1 v3.1 §9.3（v3.6 继承）要求 send() 遵守 session 级 `send_pending` 互斥锁——
    /// 同一 session 不允许两个 `send()` RPC 同时在途。上一轮只在 actor 内保存了 runId 缓存但没有
    /// 锁本身，两个并发 `send()` 都能进入 `await request(...)`，谁的 ack 先回来谁就"赢"，与调用
    /// 顺序无关，导致 `lastRunIDBySessionID` 可能被"后发起但先返回"的调用覆盖成错误值。本轮加锁：
    /// 进入函数时若锁不是 idle 一律 reject(session_locked)，否则在**第一次 await 之前**（因此
    /// actor 不会在这个检查-设置对之间被重入）把锁设成 send_pending，RPC ack 到达（无论成功失败）
    /// 后释放回 idle。
    public func send(session: SessionHandle, input: Input) async throws -> SendResultPayload {
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        let currentLock = lockStateBySessionID[session.sessionID] ?? .idle
        guard currentLock == .idle else {
            throw KernelClientError.rpcRejected(
                code: "session_locked",
                message: "send() rejected: session \(session.sessionID) lock state is \(currentLock), expected idle (D1 v3.1 §9.3)"
            )
        }
        lockStateBySessionID[session.sessionID] = .sendPending
        defer {
            // send_pending 只是"等待 kernel ack"的极短窗口——ack 到达（无论成功失败）后立刻释放。
            if lockStateBySessionID[session.sessionID] == .sendPending {
                lockStateBySessionID[session.sessionID] = .idle
            }
        }

        var params: JSONObject = [
            "key": kernelKey,
            "message": resolveSendMessageText(from: input),
            "timeoutMs": 0,
        ]
        // F2 rework：openclaw `gateway/server-methods/attachment-normalize.ts:29-56`
        // （`normalizeRpcAttachmentsToChatAttachments`）只保留带 `content` 字段（base64 或字符串）
        // 的附件，`.filter((a) => a.content)` 会把上一轮发送的 `{mimeType,path}` 形状直接丢弃（无
        // content 字段）——见 `server-methods.test.ts:2693-2699` 明确验证这一点。本轮改为读取
        // `Part.path` 指向的本地文件、base64 编码后塞进 `content`；读不到文件就诚实跳过这一个
        // attachment（不编造 content，也不让整个 send() 失败——可能只是这一个 part 路径失效）。
        if input.kind == .structured, let parts = input.parts {
            // encodeAttachmentForWire 是 OpenclawWire.swift 里的纯函数（F2），不依赖 actor 状态，
            // 方便 FrameReplayTests.swift 直接单测。
            let attachments: [JSONObject] = parts.compactMap { part -> JSONObject? in
                guard part.kind != .text else { return nil }
                return encodeAttachmentForWire(part)
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
        runIDsBySessionID[session.sessionID, default: []].insert(runID)
        return SendResultPayload(runID: runID)
    }

    /// D1 Input -> openclaw `sessions.send.message`（纯文本字符串）的最小转换。`kind:.text` 直接用
    /// `input.text`；`kind:.structured` 把 `parts` 里 `kind:.text` 的段落用换行拼接（非文本 part
    /// 走上面 attachments 分支，不混进正文），三者都拿不到文本时退化为空字符串而不是抛错——openclaw
    /// 的 `SessionsSendParamsSchema.message` 是必填 `Type.String()`，允许空串，比在这里主观拒绝更
    /// 贴近"如实转发调用方输入"的适配器职责。
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
                // includeApprovals:true——不带这个 flag 收不到 session.approval 事件
                // （`SessionsMessagesSubscribeParamsSchema` 的 `includeApprovals` 是 opt-in，默认不
                // 推送），approvalRequest 映射的现场 grounding 全部建立在这个 flag 打开的前提上。
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

    /// D1 §2.5 stop()。**F6 rework**：上一轮把 stop() 实现为"abort -> delete -> finish 流"三步，
    /// 存在两个严重缺陷（对抗审 T-044 复现）：
    ///   ① 返回给调用方的 `StopResultPayload.operationID` 是 `"\(sessionID)-stop-abort_\(status)"`，
    ///      与 EventMapping 里 lifecycle 映射自己派生的 `"\(sessionID)-abort-\(runID)"` 完全不同，
    ///      调用方的 Promise 结果和异步 `operation_completed` 事件根本无法关联。
    ///   ② delete 之后立刻 `finishEventContinuation`（= 立刻 finish 流），如果该 run 的强制取消
    ///      产生的 `turn_complete(cancelled)`/`operation_completed` 事件恰好还没被 receiveLoop 处理
    ///      完，调用方永远收不到这两个 D1 §9.3 明确要求的必需终态。
    ///
    /// 本轮修法：
    ///   1. 在发起 `sessions.abort` **之前**就铸造一个唯一 operationId，登记到 `pendingStops`
    ///      （连同"这次 stop 生效前活跃的 runId"），供 `handleAgentEvent` 观察到对应的 aborted
    ///      lifecycle 帧时使用**同一个** operationId 构造 operation_completed，不再自己派生。
    ///   2. abort 之后、delete 之前，有界等待（`waitForPendingStopTerminal`，非无限悬挂）该 run 的
    ///      operation_completed + turn_complete(cancelled) 已经被 `handleAgentEvent` 观察并 yield
    ///      完成——只有等到确认（或超时）才继续，避免过早 finish 流。
    ///   3. delete 之后、finish 流之前，yield 一条 `session_end(reason:.stopped)`（上一轮从未产出
    ///      这个事件）。
    ///   4. `StopResultPayload.operationID` 返回同一个铸造好的值，`outcome` 在等待超时时诚实记
    ///      `.timedOut`（D1 §2.5 stop() 可达 outcome 子集本就包含这一态），否则按 delete 是否成功
    ///      记 succeeded/rejected（同上一轮）。
    public func stop(session: SessionHandle) async throws -> StopResultPayload {
        guard let kernelKey = kernelKeyBySessionID[session.sessionID] else {
            throw KernelClientError.protocolMismatch("unknown session \(session.sessionID)")
        }

        let currentLock = lockStateBySessionID[session.sessionID] ?? .idle
        guard currentLock == .idle else {
            throw KernelClientError.rpcRejected(
                code: "session_locked",
                message: "stop() rejected: session \(session.sessionID) lock state is \(currentLock), expected idle (D1 v3.1 §9.3)"
            )
        }
        lockStateBySessionID[session.sessionID] = .stopInProgress

        let operationID = "op-stop-\(UUID().uuidString)"
        let affectedRunID = lastRunIDBySessionID[session.sessionID]
        pendingStops[session.sessionID] = PendingStop(operationID: operationID, affectedRunID: affectedRunID)

        let abortResult = try await request(method: "sessions.abort", params: ["key": kernelKey])
        prettyPrint("RECV sessions.abort result", abortResult)

        // D1 v3 §9.3："stop() 调用时存在 active run，适配器必须先完成该 run 的强制取消并产出
        // TurnCompleteEvent(cancelled)...确认该事件已经进入 subscribe() 流之后，才能产出
        // SessionEndEvent(reason:'stopped')"。有界等待（不是无限悬挂），交由 handleAgentEvent 在
        // 观察到对应 aborted lifecycle 帧时唤醒；超时则诚实继续（不让调用方永久悬挂），并把
        // outcome 记成 .timedOut。
        //
        // **是否需要等待，由 `sessions.abort` 自己的返回值判断，不是本地缓存的 `affectedRunID`**
        // ——现场实测（scratchpad/openclaw-iso3 隔离环境）坐实：`lastRunIDBySessionID` 只在收到新
        // run 时刷新，一个 run 正常 turnComplete 之后这个缓存不会被清空；如果 stop() 在该 run 早已
        // 自然结束之后才被调用，`sessions.abort` 会诚实回报 `{"abortedRunId":null,
        // "status":"no-active-run"}`——这种情况下压根不会有任何 aborted lifecycle 帧到达，若仍然
        // 用 `affectedRunID != nil` 去等待，会白白悬挂满 5 秒、还诚实性错误地把 outcome 报成
        // `.timedOut`（本轮真实探针复现过这个具体场景：`sessions.send` 的模型回复早已完成，
        // stop() 才被调用，`abortedRunId` 为 nil，若仍等待就是在等一个永远不会来的事件）。改为
        // 直接读 `abortResult.abortedRunId`——非空才说明这次 abort 真的中止了一个活跃 run，才需要
        // 等待其终态；为 nil 就没有等待的意义，直接把这次 pendingStop 标记掉，不留悬空 waiter。
        var timedOut = false
        let actuallyAbortedRunID = abortResult["abortedRunId"] as? String
        if actuallyAbortedRunID != nil {
            timedOut = await waitForPendingStopTerminal(sessionID: session.sessionID, timeoutSeconds: 5)
        } else {
            pendingStops.removeValue(forKey: session.sessionID)
        }

        let deleteResult = try await request(method: "sessions.delete", params: ["key": kernelKey])
        prettyPrint("RECV sessions.delete result", deleteResult)
        let deleted = (deleteResult["deleted"] as? Bool) ?? false

        // F8：session_end(stopped) 必须在 finish 流之前 yield，且与 shutdown/transportClosed 两条
        // 路径共享同一个"这个 session 是否已经产出过 terminal"标记，避免重复/矛盾的 sessionEnd。
        if !sessionTerminalEmitted.contains(session.sessionID) {
            sessionTerminalEmitted.insert(session.sessionID)
            if let continuation = eventContinuations[session.sessionID] {
                let sid = session.sessionID
                continuation.yield(makeSessionEndEventForStop(
                    ourSessionID: sid,
                    nextSeq: { self.nextSeq(runID: nil, sessionID: sid) }
                ))
            }
        }

        finishEventContinuation(sessionID: session.sessionID)
        kernelKeyBySessionID.removeValue(forKey: session.sessionID)
        pendingStops.removeValue(forKey: session.sessionID)
        lockStateBySessionID.removeValue(forKey: session.sessionID)

        // D1 §2.5：stop() 可达的 outcome 子集是 succeeded/timed_out/rejected 三态。
        let outcome: StopResultPayloadOutcome = timedOut ? .timedOut : (deleted ? .succeeded : .rejected)
        return StopResultPayload(operationID: operationID, outcome: outcome)
    }

    /// 等待 `pendingStops[sessionID]` 对应的 run 终态（operation_completed + turn_complete）已被
    /// `handleAgentEvent` 观察并 yield——由该处理器调用 `resolvePendingStopWaiter(timedOut:false)`
    /// 唤醒；超时（`timeoutSeconds`）则由本函数内部起的定时器调用 `resolvePendingStopWaiter
    /// (timedOut:true)` 唤醒。`resolvePendingStopWaiter` 内部先取出并清空 waiter 再 resume，保证
    /// 无论两条路径谁先到，`CheckedContinuation` 都只会被 resume 恰好一次。
    private func waitForPendingStopTerminal(sessionID: String, timeoutSeconds: Int) async -> Bool {
        guard let pending = pendingStops[sessionID], !pending.terminalEmitted else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.pendingStops[sessionID]?.waiter = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                await self.resolvePendingStopWaiter(sessionID: sessionID, timedOut: true)
            }
        }
    }

    private func resolvePendingStopWaiter(sessionID: String, timedOut: Bool) {
        guard let waiter = pendingStops[sessionID]?.waiter else { return }
        pendingStops[sessionID]?.waiter = nil
        waiter.resume(returning: timedOut)
    }

    public func respondApproval(session: SessionHandle, reqID: String, decision: Decision) async throws {
        throw KernelClientError.notImplemented("respondApproval() 本轮 TODO 桩——L1 闭环没有回调过任何真实审批")
    }

    public func capabilities(session: SessionHandle?) async throws -> CapabilityDescriptorPayload {
        throw KernelClientError.notImplemented("capabilities() 本轮 TODO 桩——未探测 openclaw capabilities 端点")
    }

    // MARK: - 内部：session 映射表 + 事件流生命周期

    private func kernelKey(for ourSessionID: String) -> String? {
        kernelKeyBySessionID[ourSessionID]
    }

    /// F3：per-run（或无 run 归属时按 session）单调递增 seq——供所有 mapper 调用的
    /// `nextSeq` 闭包共享同一份 actor 隔离状态。
    private func nextSeq(runID: String?, sessionID: String) -> Int {
        if let runID = runID {
            let next = (seqByRunID[runID] ?? 0) + 1
            seqByRunID[runID] = next
            return next
        }
        let next = (seqFallbackBySessionID[sessionID] ?? 0) + 1
        seqFallbackBySessionID[sessionID] = next
        return next
    }

    private func finishEventContinuation(sessionID: String) {
        eventContinuations[sessionID]?.finish()
        eventContinuations.removeValue(forKey: sessionID)
        // per-run 缓存一并清理，避免长生命周期的 client 无限累积已经 stop() 掉的 session 名下所有
        // run 的 seq/toolCallId/usage 缓存（F1：缓存改成 per-run 键之后，这里改为按
        // `runIDsBySessionID` 记录的清单批量清）。
        for runID in runIDsBySessionID[sessionID] ?? [] {
            seqByRunID.removeValue(forKey: runID)
            lastToolCallIDByRunID.removeValue(forKey: runID)
            lastUsageByRunID.removeValue(forKey: runID)
        }
        runIDsBySessionID.removeValue(forKey: sessionID)
        lastRunIDBySessionID.removeValue(forKey: sessionID)
        seqFallbackBySessionID.removeValue(forKey: sessionID)
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
                // 传输中断前先尽力给每个尚未产出过 terminal 的活跃 session 补一条
                // sessionEnd(reason:.transportClosed)——F8：与 shutdown/stop 两条路径共享
                // `sessionTerminalEmitted` 去重标记，不会对同一个 session 重复/矛盾地产出 sessionEnd。
                for (ourSessionID, continuation) in eventContinuations {
                    guard !sessionTerminalEmitted.contains(ourSessionID) else { continue }
                    sessionTerminalEmitted.insert(ourSessionID)
                    continuation.yield(makeSessionEndEventForTransportClosed(
                        ourSessionID: ourSessionID,
                        nextSeq: { self.nextSeq(runID: nil, sessionID: ourSessionID) }
                    ))
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
            // session.message 之外还要分发 agent(command_output/lifecycle/thinking/error/item/
            // approval)、session.approval、全局 shutdown 三类 wire 事件——D2 11 变体里除
            // message_delta/tool_call 之外的大多数都不是从 session.message 来的。
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
        // 消息自己带 usage。F1：usage 缓存改为 **per-run**（用刚刷新出来的 runId 做键），不再是
        // per-session，避免上一个 run 的残留 usage 串给下一个 run 的 turn_complete。
        var currentRunID = lastRunIDBySessionID[ourSessionID]
        if let sessionSnapshot = payload["session"] as? JSONObject,
           let activeRunIDs = sessionSnapshot["activeRunIds"] as? [Any],
           let firstRunID = activeRunIDs.first as? String {
            lastRunIDBySessionID[ourSessionID] = firstRunID
            runIDsBySessionID[ourSessionID, default: []].insert(firstRunID)
            currentRunID = firstRunID
        }
        if let message = payload["message"] as? JSONObject, let usage = message["usage"] as? JSONObject,
           let input = jsonInt(usage["input"]), let output = jsonInt(usage["output"]),
           let runID = currentRunID {
            lastUsageByRunID[runID] = (input: input, output: output)
        }

        let runIDHint = currentRunID
        let sid = ourSessionID
        let events = mapOpenclawSessionMessageToKernelEvents(
            payload, ourSessionID: ourSessionID, runIDHint: runIDHint,
            nextSeq: { self.nextSeq(runID: runIDHint, sessionID: sid) }
        )
        if events.isEmpty {
            prettyPrint("RECV session.message（未能映射到 D2 KernelEvent 11 变体之一）", frame)
            return
        }
        for event in events {
            if case .toolCall(let toolCall) = event, let runID = runIDHint {
                // F1：per-run 缓存（不是 per-session），approval 的 toolCallId 时序关联（F4 已改用
                // 更权威的 agent(stream:"approval") 来源，这里保留只是为了兼容潜在的其它读者/诊断）。
                lastToolCallIDByRunID[runID] = toolCall.payload.toolCallID
            }
            continuation.yield(event)
        }
    }

    /// `agent` wire 事件——`payload.stream` 分好几种，本轮 dispatch：`command_output`(phase:end)、
    /// `item`(kind:tool,phase:end，非 exec 工具)、`lifecycle`(phase:end/error)、`thinking`、`error`、
    /// `approval`(只做 toolCallId 关联缓存，不直接产出事件，见 F4)。其余 stream（run_status/usage/
    /// assistant/plan/compaction 等，均为 openclaw 自有 UI 进度信号，D1 11 变体没有对应位置）原样
    /// 打印、不映射。
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
            runIDsBySessionID[ourSessionID, default: []].insert(runID)
        }

        guard let stream = payload["stream"] as? String, let data = payload["data"] as? JSONObject else {
            return
        }
        let runIDHint = lastRunIDBySessionID[ourSessionID]
        // F3：ts 取 `agent` wire 帧外层 payload.ts（openclaw `enrichAgentEvent` 盖章的事件发生时刻，
        // `infra/agent-events.ts:628` `ts: Date.now()`），不用 Date()。
        let originTS = msEpochToDate(jsonInt(payload["ts"]))
        let sid = ourSessionID
        let nextSeqForRun: () -> Int = { self.nextSeq(runID: runIDHint, sessionID: sid) }

        switch stream {
        case "command_output":
            if let event = mapOpenclawAgentCommandOutputToToolResult(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
            }

        case "item":
            // F5：非 exec 工具的 toolResult 来源。exec 工具（"exec"/"bash"）继续只信任
            // command_output（有真实 output/exitCode），这里显式排除避免同一个 toolCallId 产出两条
            // 矛盾的 toolResult。
            guard jsonString(data["kind"]) == "tool", !isOpenclawExecToolName(jsonString(data["name"])) else {
                break
            }
            if let event = mapOpenclawAgentToolItemToToolResult(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
            }

        case "thinking":
            if let event = mapOpenclawAgentThinkingToKernelEvent(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
            }

        case "error":
            if let event = mapOpenclawAgentErrorToKernelEvent(
                data, ourSessionID: ourSessionID, runIDHint: runIDHint, originTS: originTS, nextSeq: nextSeqForRun
            ) {
                continuation.yield(event)
            }

        case "approval":
            // F4：只做 approvalId -> toolCallId 的精确关联缓存，不直接产出 D2 事件——真正的
            // approval_request 仍由 session.approval(phase:pending) 产出（它才有 timeoutMs/
            // presentation 等完整字段），这里只是给它提供一个不会串号的 toolCallId 来源。
            if jsonString(data["phase"]) == "requested",
               let approvalID = jsonString(data["approvalId"]),
               let toolCallID = jsonString(data["toolCallId"]) {
                toolCallIDByApprovalID[approvalID] = toolCallID
            }

        case "lifecycle":
            guard let phase = jsonString(data["phase"]), phase == "end" || phase == "error" else { break }
            guard let runID = runIDHint else {
                // turnComplete/operationCompleted 的 runID 字段在 D2 里是必填——理论上不会缺失
                // （lifecycle 事件本身携带真实 runId），真缺失时诚实跳过，不拿编造值填充。
                break
            }
            let aborted = jsonBool(data["aborted"]) ?? false
            if aborted {
                if var pendingForRun = pendingStops[ourSessionID], pendingForRun.affectedRunID == runID, !pendingForRun.terminalEmitted {
                    // F6：单个 operation_completed + turn_complete(cancelled)，用 stop() 铸造的
                    // 唯一 operationId，且对同一次 pendingStop 只做一次（后续同 run 的收尾帧，如
                    // 真实样本里 phase:"end" 之后常跟的 phase:"error","This operation was
                    // aborted" 帧，被下面 else 分支丢弃）。
                    let events = mapOpenclawAgentLifecycleToAbortTerminalEvents(
                        data, ourSessionID: ourSessionID, runID: runID, operationID: pendingForRun.operationID,
                        originTS: originTS, cachedUsage: lastUsageByRunID[runID], nextSeq: nextSeqForRun
                    )
                    for event in events { continuation.yield(event) }
                    pendingForRun.terminalEmitted = true
                    pendingStops[ourSessionID] = pendingForRun
                    lastUsageByRunID.removeValue(forKey: runID)
                    resolvePendingStopWaiter(sessionID: ourSessionID, timedOut: false)
                } else if pendingStops[ourSessionID] == nil {
                    // 理论上不会出现——interrupt() 本轮未实现，没有别的方法会产生 aborted:true 且
                    // 没有对应 pendingStop 的 lifecycle 帧。防御性兜底：自己派生一个 operationId，
                    // 保持"至少不丢事件"的旧行为，同时如实标注这是非预期路径。
                    let fallbackOperationID = "\(ourSessionID)-abort-\(runID)-unowned"
                    let events = mapOpenclawAgentLifecycleToAbortTerminalEvents(
                        data, ourSessionID: ourSessionID, runID: runID, operationID: fallbackOperationID,
                        originTS: originTS, cachedUsage: lastUsageByRunID[runID], nextSeq: nextSeqForRun
                    )
                    for event in events { continuation.yield(event) }
                    lastUsageByRunID.removeValue(forKey: runID)
                }
                // else：已经为这次 stop() 发过 terminal——如实丢弃这条收尾帧，不重复产出。
            } else {
                let event = mapOpenclawAgentLifecycleToTurnComplete(
                    data, ourSessionID: ourSessionID, runID: runID, originTS: originTS,
                    cachedUsage: lastUsageByRunID[runID], nextSeq: nextSeqForRun
                )
                continuation.yield(event)
                lastUsageByRunID.removeValue(forKey: runID)
            }

        default:
            // run_status/usage/assistant/plan/compaction 等：openclaw 自有 UI 进度信号，D1 11 变体
            // 没有对应位置，如实不映射。
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

        let runIDHint = lastRunIDBySessionID[ourSessionID]
        let approvalID = (payload["approval"] as? JSONObject)?["id"] as? String
        // F4：用 approvalId 去查"更权威的 agent(stream:approval) 来源"缓存的精确 toolCallId，
        // 取代上一轮"最近一次 toolCall"的猜测。
        let toolCallIDForApprovalID = approvalID.flatMap { toolCallIDByApprovalID[$0] }
        let sid = ourSessionID

        if let event = mapOpenclawSessionApprovalToKernelEvent(
            payload, ourSessionID: ourSessionID,
            runIDHint: runIDHint,
            toolCallIDForApprovalID: toolCallIDForApprovalID,
            nextSeq: { self.nextSeq(runID: runIDHint, sessionID: sid) }
        ) {
            // 用过就清掉，避免这张一次性关联表无限增长（同一个 approvalId 不会有第二次 pending）。
            if let approvalID = approvalID {
                toolCallIDByApprovalID.removeValue(forKey: approvalID)
            }
            continuation.yield(event)
        } else {
            prettyPrint("RECV session.approval（phase:terminal 或缺关联字段，D1 11 变体无对应/跳过）", frame)
        }
    }

    /// gateway 全局 `shutdown` 事件——对所有当前活跃、尚未产出过 terminal 的 session 各广播一条
    /// sessionEnd(reason:.kernelExited)。F8：与 stop()/transportClosed 两条路径共享
    /// `sessionTerminalEmitted` 去重标记。
    private func handleShutdownEvent(_ frame: JSONObject) {
        prettyPrint("RECV event shutdown（向所有活跃 session 广播 sessionEnd(reason:kernelExited)）", frame)
        for (ourSessionID, continuation) in eventContinuations {
            guard !sessionTerminalEmitted.contains(ourSessionID) else { continue }
            sessionTerminalEmitted.insert(ourSessionID)
            continuation.yield(makeSessionEndEventForShutdown(
                ourSessionID: ourSessionID,
                nextSeq: { self.nextSeq(runID: nil, sessionID: ourSessionID) }
            ))
        }
    }

    // MARK: - Test-only 支持面（frame-replay 单测用；生产路径不调用）
    //
    // 这个项目没有 XCTest/SwiftPM test target（`app/contracts/d2/codegen` 同一套"纯 swiftc 编译"
    // 风格），`FrameReplayTests.swift` 和这个文件在同一次 swiftc 调用里编译成同一个隐式 module——
    // 没有 `@testable import` 机制，`private` 是文件级作用域。下面这几个方法把"搭建一个已订阅的
    // 假 session、灌入合成 wire 帧、读取内部锁/终态状态"这三件事暴露成 internal（去掉 `private`），
    // 让测试文件可以直接驱动真实的 `handleIncoming` -> dispatch -> mapping 流水线，而不需要一个真
    // WebSocket 连接。方法名统一加 `testSupport` 前缀，一眼可辨认，不是生产调用路径的一部分。

    /// 不经过任何 RPC，直接注册一个"已订阅"的假 session——供测试灌入合成 wire 帧。
    func testSupportRegisterSession(ourSessionID: String, kernelKey: String) -> AsyncThrowingStream<EventMessageUnion, Error> {
        kernelKeyBySessionID[ourSessionID] = kernelKey
        let (stream, continuation) = AsyncThrowingStream<EventMessageUnion, Error>.makeStream()
        eventContinuations[ourSessionID] = continuation
        return stream
    }

    /// 把一帧合成的 wire JSON 编码后送进真实的 `handleIncoming` dispatch 入口——测试因此走的是
    /// 生产代码本身的分支/映射逻辑，不是重新实现一遍判断。
    func testSupportFeedFrame(_ frame: JSONObject) {
        guard let data = try? encodeFrame(frame) else { return }
        handleIncoming(data)
    }

    /// 读取当前锁状态的字符串描述（"idle"/"send_pending"/"stop_in_progress"）。
    func testSupportLockState(sessionID: String) -> String {
        (lockStateBySessionID[sessionID] ?? .idle).description
    }

    /// 测试专用：直接把某个 session 的锁状态摆到 send_pending，模拟"另一个 send() 正在途中"，
    /// 不需要真的发起一次网络请求来制造这个窗口。
    func testSupportForceLockToSendPending(sessionID: String) {
        lockStateBySessionID[sessionID] = .sendPending
    }

    /// 测试专用：模拟"这个 session 上有一个 run 正在被 stop() 强制取消"——不经过真实
    /// `sessions.abort` RPC，直接登记 `pendingStops` 与 `lastRunIDBySessionID`，供随后灌入的
    /// aborted lifecycle 帧走真实的去重 dispatch 逻辑。
    func testSupportSeedPendingStop(sessionID: String, runID: String, operationID: String) {
        lastRunIDBySessionID[sessionID] = runID
        runIDsBySessionID[sessionID, default: []].insert(runID)
        pendingStops[sessionID] = PendingStop(operationID: operationID, affectedRunID: runID)
    }

    /// 读取某个 pendingStop 是否已经被标记为"terminal 已产出"（F6 去重的核心状态）。
    func testSupportPendingStopTerminalEmitted(sessionID: String) -> Bool? {
        pendingStops[sessionID]?.terminalEmitted
    }

    /// 读取某个 session 是否已经产出过 terminal sessionEnd（F8 去重的核心状态）。
    func testSupportSessionTerminalEmitted(sessionID: String) -> Bool {
        sessionTerminalEmitted.contains(sessionID)
    }
}
