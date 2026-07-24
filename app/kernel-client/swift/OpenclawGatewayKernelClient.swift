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

    // MARK: F6/M3 — stop() 的 pending 状态（adapter 铸造的唯一 operationId + 等待终态确认）
    private struct PendingStop {
        let operationID: String
        // M3：不再是 let——发起 sessions.abort 之后必须用其权威返回值 abortedRunId 覆盖这里（见
        // stop() 的文档注释），不能一直沿用发起 abort 前可能陈旧的本地缓存值。
        var affectedRunID: String?
        var terminalEmitted: Bool = false
        var waiter: CheckedContinuation<Bool, Never>?
    }
    private var pendingStops: [String: PendingStop] = [:]

    /// M3：测试专用的 stop() 等待超时覆盖（秒）——生产默认 5 秒（D1 v3 §9.3），测试用一个短得多的
    /// 值验证"超时"这条路径，不用真的等 5 秒。`nil` 时 stop() 使用生产默认值。
    private var testSupportStopTimeoutSecondsOverride: Int?

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

    // MARK: M1 — approval 双向 join（agent(stream:"approval") <-> session.approval(phase:"pending")）
    //
    // F4 上一轮只缓存 approvalId -> toolCallId，遗漏了这次审批**真实归属的 runId**——`session.approval`
    // 落地时只能退回到全 session 的 `lastRunIDBySessionID`，在多个 run 交替产生审批时会把 approval
    // 错误关联到"当前最新活跃的 run"，而不是这次审批实际所在的 run（对抗审 T-045 M1 复现：
    // agent approval-A(run-A) 之后 agent approval-B(run-B) 到达，把 lastRunIDBySessionID 刷新成
    // run-B，随后姗姗来迟的 session.approval(approval-A) 会被错误按成 run-B）。同时上一轮完全没有
    // 处理"session.approval 先于对应 agent(stream:approval) 帧到达"这个方向——直接丢弃，approval
    // _request 永久丢失，即使 agent 帧随后真的到达也不会补发。本轮改为按 approvalId 做真正的双向
    // 缓冲 join：agent 帧先到就缓冲 {runID,toolCallID}，session.approval 先到就缓冲整个 payload，
    // 谁后到就用先到的那份补全信息，立即产出（且只产出一次）。
    private struct AgentApprovalInfo {
        let runID: String
        let toolCallID: String
    }
    private var agentApprovalInfoByApprovalID: [String: AgentApprovalInfo] = [:]

    private struct PendingSessionApproval {
        let payload: JSONObject
        let ourSessionID: String
    }
    private var pendingSessionApprovalByApprovalID: [String: PendingSessionApproval] = [:]

    /// 上面两张按 approvalId 键控的缓存本身不是 per-session 键，session 结束时要靠这张反向索引才
    /// 知道该批量清哪些 approvalId（M5：避免漏配对的条目永久残留）。
    private var approvalIDsBySessionID: [String: Set<String>] = [:]

    // MARK: - Test-only：拦截 RPC（不需要真实 WebSocket 连接）
    //
    // M3/M6 rework：真 actor 级测试需要驱动真实的 send()/stop() 方法体本身（包括它们发起的
    // sessions.send/sessions.abort/sessions.delete RPC），而不是像上一轮那样直接 seed 内部状态、
    // 绕开方法体——但这个项目没有真实网络可用。`testSupportRPCResponders` 按 RPC method 名注册一个
    // "request(method:) 被调用时应该返回什么/抛什么错"的闭包；`request()` 内部命中该表时直接走
    // 这条路径，完全不碰 `task`（未连接的 `freshClient()` 场景下 task 本来就是 nil）。生产路径不受
    // 影响——这张表默认为空，`request()` 只有命中表项时才短路。
    private var testSupportRPCResponders: [String: @Sendable (JSONObject) async throws -> JSONObject] = [:]

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
                } else {
                    // M1：消费 subscribe 响应里的 `approvalReplay`（authoritative 的当前 pending
                    // 审批快照，见下方 consumeApprovalReplay 文档注释）——上一轮完全没有读这个字段。
                    await self.consumeApprovalReplay(result, kernelKey: kernelKey)
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

    /// D1 §2.5 stop()。**M3 rework（收 T-045 codex 确认性再审 MUST-FIX，在 F6 基础上第二次收残）**：
    /// F6 只解决了"operationId 不共享"和"delete 前不等终态"两个问题，但重写本身引入/遗留了三类新
    /// 缺陷（codex 独立复现）：
    ///   ① `abortedRunId==nil`（无 active run）与"等待超时"两条路径只让 Promise 知道结果，从不给
    ///      `subscribe()` 事件流补一条 `operation_completed` 镜像——只订阅事件流、不等 Promise 的
    ///      观察者完全看不到这次 stop 操作本身的终态。
    ///   ② active-run 路径把"这次 stop 操作成功与否"和"sessions.delete 这一步资源回收是否成功"
    ///      两件事混为一谈：`handleAgentEvent` 在 delete **之前**就已经用 `succeeded` 发出了
    ///      operation_completed（这个时机是对的，D1 §9.3 要求先有终态再有 session_end），但 Promise
    ///      的 outcome 却在 delete **之后**重新按 `deleted` 布尔值计算——如果 delete 恰好返回
    ///      `deleted:false`，Promise 报 `.rejected`，与已经发出的 Event `.succeeded` 直接矛盾。
    ///      修法：outcome 只由"等没等到终态确认"（timedOut）决定，不再看 `deleted`——delete 是这次
    ///      stop 操作的收尾资源回收步骤，和"abort 本身有没有成功"是两件事，不应该互相污染判定，这样
    ///      Promise 和已经发出的 Event 天然保持一致（因为它们不再有两个独立的信息来源）。
    ///   ③ `sessions.abort`/`sessions.delete` 抛错时整个函数直接向上抛出，`stopInProgress` 锁、
    ///      `pendingStops` 条目都不会被释放——真实复现：第一次 stop() 因传输错误抛出后，锁永久卡在
    ///      `stop_in_progress`，第二次 stop() 会被误判成"另一个 stop 正在进行"而拒绝
    ///      （`session_locked`），即使第一次调用早就已经失败结束。修法：`do/catch` 包裹两次 RPC，
    ///      catch 里统一释放锁 + 清理 pendingStop + 发一条 `operation_completed(outcome:.rejected)`
    ///      镜像，然后把原始错误重新抛给调用方（stop() 这次调用确实失败了，调用方需要知道）。
    ///
    /// `PendingStop.affectedRunID` 在 abort 之后立刻用 `abortResult.abortedRunId`（权威值）覆盖——
    /// 不能一直沿用发起 abort 前的本地缓存 `lastRunIDBySessionID`，那个值可能陈旧，会让
    /// `handleAgentEvent` 里 `pendingForRun.affectedRunID == runID` 的相等判断永远不成立、白等到
    /// 超时（codex 复现的具体机制）。
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
        let affectedRunIDBeforeAbort = lastRunIDBySessionID[session.sessionID]
        pendingStops[session.sessionID] = PendingStop(operationID: operationID, affectedRunID: affectedRunIDBeforeAbort)

        do {
            let abortResult = try await request(method: "sessions.abort", params: ["key": kernelKey])
            prettyPrint("RECV sessions.abort result", abortResult)

            // D1 v3 §9.3："stop() 调用时存在 active run，适配器必须先完成该 run 的强制取消并产出
            // TurnCompleteEvent(cancelled)...确认该事件已经进入 subscribe() 流之后，才能产出
            // SessionEndEvent(reason:'stopped')"。有界等待（不是无限悬挂），交由 handleAgentEvent 在
            // 观察到对应 aborted lifecycle 帧时唤醒；超时则诚实继续（不让调用方永久悬挂），并把
            // outcome 记成 .timedOut。
            //
            // **是否需要等待，由 `sessions.abort` 自己的返回值判断，不是本地缓存的 `affectedRunID`**
            // ——现场实测（scratchpad/openclaw-iso3 隔离环境）坐实：`lastRunIDBySessionID` 只在收到
            // 新 run 时刷新，一个 run 正常 turnComplete 之后这个缓存不会被清空；如果 stop() 在该 run
            // 早已自然结束之后才被调用，`sessions.abort` 会诚实回报 `{"abortedRunId":null,
            // "status":"no-active-run"}`——这种情况下压根不会有任何 aborted lifecycle 帧到达。改为
            // 直接读 `abortResult.abortedRunId`——非空才说明这次 abort 真的中止了一个活跃 run，才需要
            // 等待其终态；为 nil 就没有等待的意义。
            let actuallyAbortedRunID = abortResult["abortedRunId"] as? String
            var timedOut = false
            if let actuallyAbortedRunID = actuallyAbortedRunID {
                // M3：用权威值覆盖，不再信任 abort 前的本地缓存（见函数文档注释）。
                pendingStops[session.sessionID]?.affectedRunID = actuallyAbortedRunID
                let timeoutSeconds = testSupportStopTimeoutSecondsOverride ?? 5
                timedOut = await waitForPendingStopTerminal(sessionID: session.sessionID, timeoutSeconds: timeoutSeconds)
                if timedOut {
                    // M3：等待超时也必须给事件流补一条 operation_completed 镜像——上一轮只有 Promise
                    // 知道超时了，只订阅事件流的观察者永远看不到这个 run 的终态。
                    emitOperationCompletedMirror(
                        sessionID: session.sessionID, operationID: operationID,
                        affectedRunID: actuallyAbortedRunID, outcome: .timedOut
                    )
                }
            } else {
                // M3：这次 stop() 生效时该 run 早已自然结束（sessions.abort 诚实回报
                // abortedRunId:null）——没有可等待的终态，但 Promise 即将报 succeeded，必须同时给
                // 事件流补一条 operation_completed 镜像（上一轮这条路径只发 session_end，事件流
                // 观察者完全看不到这次 stop 操作本身的终态）。
                pendingStops.removeValue(forKey: session.sessionID)
                emitOperationCompletedMirror(
                    sessionID: session.sessionID, operationID: operationID,
                    affectedRunID: nil, outcome: .succeeded
                )
            }

            let deleteResult = try await request(method: "sessions.delete", params: ["key": kernelKey])
            prettyPrint("RECV sessions.delete result", deleteResult)
            let deleted = (deleteResult["deleted"] as? Bool) ?? false
            if !deleted {
                // 诚实记录：delete 未确认成功，但不据此把已经发出/即将返回的 succeeded 倒转成
                // rejected——delete 是会话资源回收的收尾步骤，和"这次 stop 操作本身有没有成功中止
                // run"是两件事，不应该互相污染判定（M3 修的正是这个矛盾）。
                prettyPrint("WARN sessions.delete reported deleted:false after stop() otherwise succeeded", deleteResult)
            }

            emitStopSessionEndAndFinish(session: session)

            // D1 §2.5：stop() 可达的 outcome 子集是 succeeded/timed_out/rejected 三态——本函数只有
            // 走到这里（两次 RPC 都没有抛错）才可能是 succeeded/timed_out，`.rejected` 专属于下面
            // catch 分支代表的"RPC 本身失败"。
            let outcome: StopResultPayloadOutcome = timedOut ? .timedOut : .succeeded
            return StopResultPayload(operationID: operationID, outcome: outcome)
        } catch {
            // M3：sessions.abort/sessions.delete 抛错——释放锁 + 清理 pendingStop + 发一条
            // operation_completed(outcome:.rejected) 镜像，再把原始错误重新抛出。不清理这三样状态
            // 会让该 session 永久卡在 stop_in_progress（复现：第一次 stop 抛错后锁不释放，第二次
            // stop 被 session_locked 拒绝，即使第一次调用早已结束）。
            let affectedRunID = pendingStops[session.sessionID]?.affectedRunID ?? affectedRunIDBeforeAbort
            emitOperationCompletedMirror(
                sessionID: session.sessionID, operationID: operationID,
                affectedRunID: affectedRunID, outcome: .rejected
            )
            pendingStops.removeValue(forKey: session.sessionID)
            lockStateBySessionID.removeValue(forKey: session.sessionID)
            throw error
        }
    }

    /// M3：为 stop() 不会经过 `handleAgentEvent` 真实 aborted lifecycle 帧的路径（无 active run、
    /// 等待超时、RPC 抛错）补一条 `operation_completed` 镜像——D1 §9.3 要求 Promise 结果与
    /// `subscribe()` 流里的 `operation_completed` 必须是同一个 `{operationId,outcome}`，不能让只
    /// 订阅事件流的观察者完全看不到这次 stop 操作的终态。
    private func emitOperationCompletedMirror(
        sessionID: String, operationID: String, affectedRunID: String?, outcome: PayloadOutcome
    ) {
        guard let continuation = eventContinuations[sessionID] else { return }
        let opPayload = OperationCompletedEventMessagePayload(
            affectedRunID: affectedRunID, detail: nil, newRunID: nil,
            operationID: operationID, operationKind: .stop, outcome: outcome
        )
        continuation.yield(.operationCompleted(OperationCompletedEventMessage(
            direction: .event, payload: opPayload, runID: affectedRunID,
            sentAt: Date(), seq: nextSeq(runID: affectedRunID, sessionID: sessionID),
            sessionID: sessionID, ts: Date(), type: .evtOperationCompleted
        )))
    }

    /// stop() 成功路径的收尾：F8 `sessionTerminalEmitted` 去重 + yield `session_end(stopped)` +
    /// finish 事件流（`finishEventContinuation` 内部的 `clearSessionDerivedCaches` 已经覆盖 M5
    /// 要求的全部派生缓存清理，这里只再额外清 `kernelKeyBySessionID`——那张表不是"派生缓存"，是
    /// session 本身是否还存在的权威映射，不属于 `clearSessionDerivedCaches` 的职责范围）。
    private func emitStopSessionEndAndFinish(session: SessionHandle) {
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

    /// M5（收 T-045 codex 确认性再审 MUST-FIX）：一个 session 的全部派生缓存——per-run
    /// seq/toolCallId/usage、M1 approval 双向缓冲区（含从未配对成功的孤儿条目）、pendingStop、
    /// session 锁、F8 terminal 去重标记——统一在这里清干净。`finishEventContinuation`（stop()/
    /// 正常 subscribe 流结束）和 `handleTransportClosed`（transport 异常）两条路径都必须调用同一份
    /// 清理，不能像上一轮那样只清一半（前者只清了 per-run 缓存，后者干脆什么都不清；approval 缓存
    /// 更是只有 join 成功时才删除，pending-first 漏配对的条目会永久残留）。
    private func clearSessionDerivedCaches(sessionID: String) {
        for runID in runIDsBySessionID[sessionID] ?? [] {
            seqByRunID.removeValue(forKey: runID)
            lastToolCallIDByRunID.removeValue(forKey: runID)
            lastUsageByRunID.removeValue(forKey: runID)
        }
        runIDsBySessionID.removeValue(forKey: sessionID)
        lastRunIDBySessionID.removeValue(forKey: sessionID)
        seqFallbackBySessionID.removeValue(forKey: sessionID)

        for approvalID in approvalIDsBySessionID[sessionID] ?? [] {
            agentApprovalInfoByApprovalID.removeValue(forKey: approvalID)
            pendingSessionApprovalByApprovalID.removeValue(forKey: approvalID)
        }
        approvalIDsBySessionID.removeValue(forKey: sessionID)

        pendingStops.removeValue(forKey: sessionID)
        lockStateBySessionID.removeValue(forKey: sessionID)
        sessionTerminalEmitted.remove(sessionID)
    }

    private func finishEventContinuation(sessionID: String) {
        eventContinuations[sessionID]?.finish()
        eventContinuations.removeValue(forKey: sessionID)
        clearSessionDerivedCaches(sessionID: sessionID)
    }

    // MARK: - 内部：RPC 请求/响应关联

    private func request(method: String, params: JSONObject) async throws -> JSONObject {
        if let responder = testSupportRPCResponders[method] {
            prettyPrint("SEND req \(method) (test-stubbed, no real transport)", ["method": method, "params": params])
            return try await responder(params)
        }
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
                handleTransportClosed(error: KernelClientError.transport("\(error)"))
                break
            }
        }
    }

    /// 传输中断（真实 WS 断开，或 `testSupportSimulateTransportClosed` 模拟）的统一处理：先尽力给
    /// 每个尚未产出过 terminal 的活跃 session 补一条 sessionEnd(reason:.transportClosed)——F8：与
    /// shutdown/stop 两条路径共享 `sessionTerminalEmitted` 去重标记，不会对同一个 session 重复/
    /// 矛盾地产出 sessionEnd；然后 `failAllPending` 收尾所有还在等待的 RPC/事件流。抽成独立方法只是
    /// 为了让测试能直接触发这条路径（M6：真实驱动 shutdown+transport close 两条路径，不是像上一轮
    /// 那样用两次同样的 shutdown 帧代替）。
    private func handleTransportClosed(error: Error) {
        for (ourSessionID, continuation) in eventContinuations {
            guard !sessionTerminalEmitted.contains(ourSessionID) else { continue }
            sessionTerminalEmitted.insert(ourSessionID)
            continuation.yield(makeSessionEndEventForTransportClosed(
                ourSessionID: ourSessionID,
                nextSeq: { self.nextSeq(runID: nil, sessionID: ourSessionID) }
            ))
        }
        failAllPending(error: error)
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
        // M5：transport 异常路径上一轮只 finish 了 continuation，从不清理per-session派生缓存
        // （seq/toolCallId/usage/approval 双向缓冲/pendingStop/锁/terminal 标记）——这里改为跟
        // `finishEventContinuation` 共享同一份 `clearSessionDerivedCaches`。
        for (sessionID, cont) in eventContinuations {
            cont.finish(throwing: error)
            clearSessionDerivedCaches(sessionID: sessionID)
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
            // F4/M1：这条 agent 帧本身不直接产出 D2 事件——真正的 approval_request 仍由
            // session.approval(phase:pending) 产出（它才有 timeoutMs/presentation 等完整字段），
            // 这里只是给它提供不会串号的 {runId,toolCallId} 来源。
            //
            // M1 订正：`approvalRunID` 必须取**这一条 agent 帧自己的** `runIDHint`（上面已经用这条
            // 帧自带的 `payload.runId` 刷新过 `lastRunIDBySessionID`，此刻 `runIDHint` 精确对应
            // 这次审批），而不是等到 `session.approval` 落地时再去查全 session 的
            // `lastRunIDBySessionID`——那时如果又有别的 run 的 approval 帧插队到达，会把这次审批
            // 错误关联到"当前最新活跃的 run"（对抗审 T-045 M1 复现的具体机制）。按 approvalId 存好
            // {runId,toolCallId} 之后，双向 join：
            //   - 若 `session.approval(pending)` 已经先到达并缓冲（`pendingSessionApprovalByApprovalID`
            //     有这个 approvalId 的条目）——现在信息齐了，立即补发 approvalRequest（上一轮这个
            //     方向完全没处理，session.approval 先到时直接丢弃，approval_request 永久丢失）。
            //   - 否则缓存 {runId,toolCallId}，等 `session.approval` 后到时再用。
            if jsonString(data["phase"]) == "requested",
               let approvalID = jsonString(data["approvalId"]),
               let toolCallID = jsonString(data["toolCallId"]),
               let approvalRunID = runIDHint {
                approvalIDsBySessionID[ourSessionID, default: []].insert(approvalID)
                if let bufferedSessionApproval = pendingSessionApprovalByApprovalID.removeValue(forKey: approvalID) {
                    emitApprovalRequestIfPossible(
                        payload: bufferedSessionApproval.payload, ourSessionID: bufferedSessionApproval.ourSessionID,
                        runID: approvalRunID, toolCallID: toolCallID
                    )
                    approvalIDsBySessionID[ourSessionID]?.remove(approvalID)
                } else {
                    agentApprovalInfoByApprovalID[approvalID] = AgentApprovalInfo(runID: approvalRunID, toolCallID: toolCallID)
                }
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
    ///
    /// **M1 订正**：上一轮如果这条 `pending` 帧先于对应的 `agent(stream:"approval")` 帧到达
    /// （`toolCallIDForApprovalID` 查不到），会直接 `return nil`——`approval_request` 就此永久丢失，
    /// 即使 agent 帧随后真的到达也不会补发（对抗审 T-045 M1 第二个 REPRO：反向到达时
    /// `eventTypes=["evt.session_end"]`，approval_request 完全缺席）。本轮改为双向缓冲 join：查不到
    /// 就把整条 payload 按 approvalId 缓冲起来，等 agent 帧补上 `{runId,toolCallId}` 时由
    /// `handleAgentEvent` 的 "approval" 分支补发。
    private func handleSessionApprovalEvent(_ frame: JSONObject) {
        guard let payload = frame["payload"] as? JSONObject,
              let kernelKey = payload["sessionKey"] as? String,
              let ourSessionID = ourSessionID(forKernelKey: kernelKey) else {
            return
        }
        guard eventContinuations[ourSessionID] != nil else { return }

        guard jsonString(payload["phase"]) == "pending" else {
            // terminal 分支：D1 11 变体没有它的对应位置（见 EventMapping.swift 文档注释），如实跳过。
            prettyPrint("RECV session.approval（phase:terminal，D1 11 变体无对应，跳过）", frame)
            return
        }
        guard let approvalID = (payload["approval"] as? JSONObject)?["id"] as? String else { return }

        if let agentInfo = agentApprovalInfoByApprovalID.removeValue(forKey: approvalID) {
            // agent(stream:"approval") 已经先到达，缓存里有准确的 {runId,toolCallId}——立即 join。
            approvalIDsBySessionID[ourSessionID]?.remove(approvalID)
            emitApprovalRequestIfPossible(
                payload: payload, ourSessionID: ourSessionID, runID: agentInfo.runID, toolCallID: agentInfo.toolCallID
            )
        } else {
            // M1 双向 join：agent 帧还没到——缓冲这条 session.approval，等它来补发，不再直接丢弃。
            pendingSessionApprovalByApprovalID[approvalID] = PendingSessionApproval(payload: payload, ourSessionID: ourSessionID)
            approvalIDsBySessionID[ourSessionID, default: []].insert(approvalID)
            prettyPrint("RECV session.approval(phase:pending)（agent(stream:approval) 尚未到达，缓冲等待补发）", frame)
        }
    }

    /// 用已经确定的 `{runID,toolCallID}`（无论是 agent 帧先到、session.approval 先到、还是
    /// approvalReplay 重放）产出一条 approvalRequest 事件——三条来源路径共享这一份构造+yield 逻辑，
    /// 不重新发明一遍判断。
    private func emitApprovalRequestIfPossible(payload: JSONObject, ourSessionID: String, runID: String, toolCallID: String) {
        guard let continuation = eventContinuations[ourSessionID] else { return }
        let sid = ourSessionID
        if let event = mapOpenclawSessionApprovalToKernelEvent(
            payload, ourSessionID: ourSessionID, runIDHint: runID, toolCallIDForApprovalID: toolCallID,
            nextSeq: { self.nextSeq(runID: runID, sessionID: sid) }
        ) {
            continuation.yield(event)
        }
    }

    /// M1：消费 `sessions.messages.subscribe` 响应里的 `approvalReplay.approvals`——这是这次
    /// subscribe 建立**之前**就已经处于 pending 状态的审批快照（真实场景：respondApproval 还没
    /// 落地、client 断线重连，或首次 subscribe 时错过了原始 `session.approval(pending)` 广播，只能
    /// 靠这份权威快照补齐——见 openclaw 源码
    /// `gateway/server-methods/sessions-subscriptions.ts:91-121`：`includeApprovals:true` 时
    /// subscribe 的响应本身就带上 `approvalReplay:{sessionKey,updatedAtMs,approvals,truncated}`，
    /// 每个 `approvals[]` 条目与 `session.approval(phase:"pending")` 的 `approval` 字段同构，见
    /// `packages/gateway-protocol/src/schema/approvals.ts` 的 `PendingApprovalSnapshotSchema`）。
    /// 上一轮完全没有读这个字段，这些审批永远不会出现在 D2 事件流里。逐条构造等价的
    /// `session.approval(phase:"pending")` frame，直接调用 `handleSessionApprovalEvent`——走跟真实
    /// wire 事件完全相同的双向 join 逻辑（大多数情况下这里还没有 agent(stream:approval) 帧，会被
    /// 正常缓冲，等随后真实到达的 agent 帧补发）。
    private func consumeApprovalReplay(_ result: JSONObject, kernelKey: String) {
        guard let replay = result["approvalReplay"] as? JSONObject,
              let approvals = replay["approvals"] as? [Any] else {
            return
        }
        let updatedAtMs = replay["updatedAtMs"]
        for case let approval as JSONObject in approvals {
            let syntheticPayload: JSONObject = [
                "sessionKey": kernelKey,
                "updatedAtMs": updatedAtMs as Any,
                "phase": "pending",
                "approval": approval,
            ]
            handleSessionApprovalEvent(["type": "event", "event": "session.approval", "payload": syntheticPayload])
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

    /// 读取某个 pendingStop 是否已经被标记为"terminal 已产出"（F6 去重的核心状态）。
    func testSupportPendingStopTerminalEmitted(sessionID: String) -> Bool? {
        pendingStops[sessionID]?.terminalEmitted
    }

    /// M3：读取某个 session 当前是否还残留一个 pendingStop 条目——用于验证 stop() 的各条退出路径
    /// （成功/超时/抛错）收尾之后确实清干净了，没有泄漏。
    func testSupportHasPendingStop(sessionID: String) -> Bool {
        pendingStops[sessionID] != nil
    }

    /// 读取某个 session 是否已经产出过 terminal sessionEnd（F8 去重的核心状态）。
    func testSupportSessionTerminalEmitted(sessionID: String) -> Bool {
        sessionTerminalEmitted.contains(sessionID)
    }

    /// M1/M5：读取某个 approvalId 当前是否还残留在任一方向的双向 join 缓冲区里——用于验证
    /// pending-first/agent-first 两个方向在 join 成功后确实清掉了自己的缓存条目，以及 session
    /// 结束时孤儿条目（从未配对成功的）确实被批量清理。
    func testSupportHasBufferedApproval(approvalID: String) -> Bool {
        agentApprovalInfoByApprovalID[approvalID] != nil || pendingSessionApprovalByApprovalID[approvalID] != nil
    }

    /// M3/M6：按 RPC method 名注册一个"被调用时应该返回什么/抛什么错"的闭包——供测试真实驱动
    /// `send()`/`stop()` 方法体本身（含它们发起的 `sessions.send`/`sessions.abort`/
    /// `sessions.delete` RPC），不需要一个真实的 WebSocket 连接。见 `request()` 的调用点。
    func testSupportStubRPC(method: String, responder: @escaping @Sendable (JSONObject) async throws -> JSONObject) {
        testSupportRPCResponders[method] = responder
    }

    /// M3：缩短 stop() 等待 aborted-run 终态的超时（生产默认 5 秒），供"超时"路径的测试使用，不用
    /// 真的等 5 秒。
    func testSupportSetStopTimeoutSeconds(_ seconds: Int) {
        testSupportStopTimeoutSecondsOverride = seconds
    }

    /// M6：直接触发 `handleTransportClosed`（真实 WS 断开时 `receiveLoop` 走的同一条路径）——供
    /// 测试验证"shutdown 之后真实 transport close"不会产出第二条矛盾的 sessionEnd，而不是像上一轮
    /// 那样用两次同样的 shutdown 帧代替 transport close。
    func testSupportSimulateTransportClosed() {
        handleTransportClosed(error: KernelClientError.transport("test-simulated transport closed"))
    }
}
