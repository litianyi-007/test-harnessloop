// openclaw 事件 -> D2 EventMessageUnion（11 变体）映射。SG-5 完整化。
//
// 现场结论（本轮用 scratchpad/openclaw-iso3 隔离 openclaw + D3-proxy(localhost:3001) + Pi
// Postgres/new-api 真实探针跑出来的，逐条在下面每个函数的文档注释标注 grounding 层级）：
//
//   1. openclaw 的 `session.message` 事件只承载"assistant 助手消息"（text/thinking/toolCall
//      content block）——从未观察到 role="toolResult" 的 session.message 广播（两次独立探针
//      复现同一结论：live 长连接从发送前就订阅、经历完整 toolCall→toolResult→下一轮，始终没有
//      role=toolResult 的 session.message 事件），尽管原始 transcript（sqlite
//      `transcript_events` 表）里确实持久化了 role="toolResult" 的消息——说明
//      `handleTranscriptUpdateBroadcast`（kernels/openclaw/src/gateway/server-session-events.ts）
//      的广播路径在工具结果这一步被跳过，只有真正的模型回合（user/assistant）会广播。
//   2. 工具调用的执行结果实际上是通过一个完全不同的 wire 事件——`agent`（payload.stream 分好几种：
//      run_status/lifecycle/item/command_output/usage/assistant）——实时推送的，其中
//      `stream:"command_output"` 且 `data.phase:"end"` 的形状最贴近 D2 ToolResultEventPayload
//      （output/exitCode/durationMs/cwd 齐备），已用真实 exec 工具调用样本验证两次。
//   3. `session.approval`（需要 `sessions.messages.subscribe` 传 `includeApprovals:true` 才收得到）
//      phase:"pending" 就是 evt.approval_request 的现场原型，已用真实样本验证（把 execAsk 临时
//      patch 成 "always" 触发）。phase:"terminal" 的 reason 词表（user/timeout/malformed-verdict/
//      no-route/run-aborted/gateway-restart/storage-corrupt，见
//      packages/gateway-protocol/src/schema/approvals.ts）与 D1 `ApprovalBufferResolvedEvent` 要求的
//      reason（仅 buffered_timeout/queue_overflow）完全不相交——真实 openclaw 从不产生后者，
//      approval_buffer_resolved 是 D1 §6.2"pending #2 本地缓冲策略"要求适配器自己维护的一个
//      本地状态机产物，respondApproval()/审批缓冲队列本轮未实现，因此本文件不把它接到任何真实
//      wire 事件上——见文末 `buildApprovalBufferResolvedEvent`。
//   4. `agent` 的 `stream:"lifecycle"` 在 `data.phase` 为 "end"/"error" 时是一次 run 的终态信号，
//      `data.aborted` 是判别键：`aborted:false` 对应 evt.turn_complete（真实样本：正常回合结束）；
//      `aborted:true` 对应 evt.operation_completed（真实样本：对一个进行中的 exec 调用发
//      `sessions.abort` 后观察到）。两者共享同一条 wire 信号，用 `aborted` 判别，无需一个"单独的
//      operationId 旁路事件"（openclaw 没有这种东西）。
//   5. gateway 关闭时会给所有连接广播一次全局 `shutdown` 事件（真实样本：向隔离 gateway 发
//      SIGTERM 实测）——本文件把它映射为对所有当前活跃 session 广播 evt.session_end(reason:
//      kernel_exited)。WS 传输层自身断开（receiveLoop 报错、没有先收到 shutdown 帧）走
//      reason: transport_closed，这条路径本身是真代码（OpenclawGatewayKernelClient 里已有的
//      receiveLoop 错误处理），但本轮没有单独构造"纯网络中断、无 shutdown 帧"的现场去验证它，
//      诚实标注为源码/设计推断而非现场实测。
//   6. evt.error 与 evt.capability_changed 本轮均未接到任何真实触发路径：
//      - evt.capability_changed：D1 INV-4 原文就说"能力变更的感知路径是内核 RPC
//        报错(被动发现)+我方 Server 能力开关 override(主动决策)"——即它从来不是一个 kernel 主动
//        push 的事件，需要 capabilities() 方法本身先落地（本轮仍是 TODO 桩）才有基线可 diff。
//      - evt.error：本轮所有现场探针（真实 exec 调用、真实 sessions.abort、真实
//        session.approval 拒绝、真实 gateway shutdown）全部成功或走了已归类的终态路径，
//        没有出现一次真正的 kernel 侧异步错误（provider 报错/鉴权失效/沙箱拒绝）。
//      两者的构造函数仍然写出来（`buildCapabilityChangedEvent`/见下）以证明 D2 payload
//      在类型层面可正确构造，但均未接入任何 dispatch 路径——诚实登记为本轮 blocker 级缺口，
//      留给下一阶段补真实触发场景。

import Foundation

// MARK: - JSON 取值小工具（JSONSerialization 产物的 [String: Any] 上做安全取值）

func jsonInt(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let n = any as? NSNumber { return n.intValue }
    if let d = any as? Double { return Int(d) }
    return nil
}

func jsonString(_ any: Any?) -> String? {
    any as? String
}

func jsonBool(_ any: Any?) -> Bool? {
    if let b = any as? Bool { return b }
    if let n = any as? NSNumber { return n.boolValue }
    return nil
}

func jsonObject(_ any: Any?) -> JSONObject? {
    any as? JSONObject
}

func jsonArray(_ any: Any?) -> [Any]? {
    any as? [Any]
}

/// 把一个内存里的 `Any`（来自 JSONSerialization 解出的 JSON 值）包成 D2 codegen 的 `JSONAny`。
/// `JSONAny` 只暴露 `init(from: Decoder)`（Decodable 要求），没有直接take `Any` 的构造器——这里借道
/// `JSONSerialization` + `JSONDecoder` 往返一次：包一层 `{"v": value}` 再解出来，是因为
/// `JSONSerialization.data(withJSONObject:)` 在顶层只接受 Array/Dictionary，标量值（纯字符串/数字/
/// 布尔）必须先包一层才能序列化。
func makeJSONAny(_ value: Any) -> JSONAny {
    let wrapper: JSONObject = ["v": value]
    guard JSONSerialization.isValidJSONObject(wrapper),
          let data = try? JSONSerialization.data(withJSONObject: wrapper, options: []),
          let decoded = try? JSONDecoder().decode([String: JSONAny].self, from: data),
          let result = decoded["v"] else {
        // "null" 恒可解码（走 JSONAny.init(from:) 的 singleValueContainer + decodeNil 分支），
        // 用作不可序列化输入（例如非 JSON 兼容的 Swift 值）时的诚实兜底，不是伪造业务数据。
        return try! JSONDecoder().decode(JSONAny.self, from: Data("null".utf8))
    }
    return result
}

private func msEpochToDate(_ ms: Int?) -> Date {
    guard let ms = ms else { return Date() }
    return Date(timeIntervalSince1970: Double(ms) / 1000.0)
}

// MARK: - ① session.message -> messageDelta / thinking / toolCall（三种，均现场实测样本 grounding）

/// openclaw `session.message` 的 `payload.message` 只在 role=="assistant" 时才可能产出 D2 事件——
/// role=="user" 是调用方自己发的输入回显，D1 的 KernelEvent 流不表达"回显我方输入"这件事（D2
/// MessageDeltaEventMessagePayload.role 这个类型本身就只有一个取值 `.assistant`，quicktype
/// 从 schema 生成时就把这一点固化了）。一条 assistant 消息的 `content` 可以是纯字符串，也可以是
/// 多个 block 的数组（真实样本证实：文本 block 和 toolCall block 可以同时出现在同一条消息里，见
/// EventMapping 头注释①引用的现场 transcript seq 12），因此一条 session.message 可能产出 0~N 个
/// D2 事件，返回值是数组。
///
/// 现场样本（`scratchpad/openclaw-iso3` 隔离 openclaw + D3-proxy + 真实 Kimi，2026-07-24）：
/// ```
/// {"role":"assistant","content":[{"type":"toolCall","id":"tool_...","name":"exec",
///   "arguments":{"command":"ls -la"},"partialArgs":"..."}],
///  "usage":{"input":9288,"output":2346,"cacheRead":0,"cacheWrite":0,"reasoningTokens":0,
///   "totalTokens":11634,"cost":{...}},"stopReason":"toolUse","timestamp":...,"responseId":"..."}
/// ```
/// 和纯文本样本：
/// ```
/// {"role":"assistant","content":[{"type":"text","text":"当前工作目录下的文件有：..."}],
///  "stopReason":"stop", ...}
/// ```
func mapOpenclawSessionMessageToKernelEvents(
    _ payload: JSONObject,
    ourSessionID: String,
    runIDHint: String?
) -> [EventMessageUnion] {
    guard let message = jsonObject(payload["message"]) else { return [] }
    guard jsonString(message["role"]) == "assistant" else {
        // role=="user"：回显，无 D2 对应事件。role=="toolResult" 从未在 session.message 里现场
        // 观察到（见头注释①），如果未来 openclaw 版本改变了这一点、这里会静默丢弃——保留在这里
        // 一并说明，而不是假装处理了一个从未见过的分支。
        return []
    }

    let seq = jsonInt(payload["messageSeq"]) ?? 0
    let sentAt = Date()
    var events: [EventMessageUnion] = []

    // 顶层字段（usage/stopReason/timestamp）是 assistant 消息自己的，不是某个 content block 的——
    // 供 turnComplete 之类的调用方缓存 usage 用，这里只按 content block 逐个产出事件。
    let content = message["content"]
    let blocks: [JSONObject]
    if let arr = jsonArray(content) {
        blocks = arr.compactMap { jsonObject($0) }
    } else if let text = jsonString(content) {
        // 纯字符串 content——SG-4 唯一覆盖过的形状，保留兼容。
        blocks = [["type": "text", "text": text]]
    } else {
        blocks = []
    }

    for (index, block) in blocks.enumerated() {
        guard let type = jsonString(block["type"]) else { continue }
        switch type {
        case "text":
            guard let text = jsonString(block["text"]) else { continue }
            let deltaPayload = MessageDeltaEventMessagePayload(delta: text, index: index, role: .assistant)
            events.append(.messageDelta(MessageDeltaEventMessage(
                direction: .event, payload: deltaPayload, runID: runIDHint,
                sentAt: sentAt, seq: seq, sessionID: ourSessionID, ts: sentAt, type: .evtMessageDelta
            )))

        case "thinking", "reasoning", "redacted_thinking":
            // grounding：源码——kernels/openclaw/src/gateway/chat-display-projection.ts
            // `isAssistantInternalReasoningContentType` 把 "thinking"/"reasoning"/
            // "redacted_thinking" 三个字面量识别为推理类 block（真实存在的类型判别逻辑，本轮
            // 未能现场触发一次真实带 thinking block 的响应——已实测 kimi-for-coding 这个 provider
            // 目录项声明 reasoning:false，sessions.patch 设 thinkingLevel:"high" 被服务端同步拒绝
            // "not supported for d3proxy/kimi-for-coding (use off)"，结构性验证了"当前现场配置下
            // thinking 不可达"，而不是模拟或猜测）。delta 取 text 字段，取不到则退化取
            // openclaw "thinking" 字段名本身（两种拼法都在真实上游 provider 里出现过，源码里
            // sanitizeChatHistoryContentBlock 同时处理 entry.text 与 entry.thinking 两个字段名）。
            let delta = jsonString(block["text"]) ?? jsonString(block["thinking"]) ?? ""
            let visibility: Visibility = type == "redacted_thinking" ? .summary : .raw
            let thinkingPayload = ThinkingEventMessagePayload(delta: delta, visibility: visibility)
            events.append(.thinking(ThinkingEventMessage(
                direction: .event, payload: thinkingPayload, runID: runIDHint,
                sentAt: sentAt, seq: seq, sessionID: ourSessionID, ts: sentAt, type: .evtThinking
            )))

        case "toolCall", "tool_call", "toolUse", "tool_use":
            guard let toolCallID = jsonString(block["id"]), let name = jsonString(block["name"]) else { continue }
            let input = makeJSONAny(block["arguments"] ?? block["input"] ?? [:] as JSONObject)
            let toolCallPayload = ToolCallEventMessagePayload(input: input, name: name, status: .started, toolCallID: toolCallID)
            events.append(.toolCall(ToolCallEventMessage(
                direction: .event, payload: toolCallPayload, runID: runIDHint,
                sentAt: sentAt, seq: seq, sessionID: ourSessionID, ts: sentAt, type: .evtToolCall
            )))

        default:
            // 未识别的 content block type——如实跳过，不臆造映射。
            continue
        }
    }

    return events
}

// MARK: - ② agent(stream:"command_output") -> toolResult（现场实测样本 grounding，仅 exec 工具族）

/// 真实样本（同一 exec 工具调用的完整生命周期，`agent` 事件 `payload.stream` 依次是
/// run_status→item(×N)→command_output(phase delta×N)→item(phase end)→command_output(phase end)）：
/// ```
/// {"stream":"command_output","data":{"itemId":"command:tool_Jd9...","phase":"end",
///   "toolCallId":"tool_Jd9HsUlLKZyhkA7uhkIvInHr","name":"exec",
///   "output":"AGENTS.md\nBOOTSTRAP.md\n...","status":"completed","exitCode":0,
///   "durationMs":20,"cwd":"/Users/.../workspace"}}
/// ```
/// 只取 `phase:"end"` 的 `command_output`（`phase:"delta"` 是流式中间态，不代表工具调用终态；
/// `item` kind:"tool"/"command" 的 phase:"end" 携带同一份信息的另一种"UI 进度条目"形状，两者会
/// 对同一个 toolCallId 各来一次——只选 `command_output` 作为唯一权威来源，避免同一个工具调用
/// 产出两条重复的 D2 toolResult 事件）。
///
/// 范围声明（诚实登记的缺口）：`command_output` 这个 stream 名字本身就是 exec/命令族工具专属——
/// 本轮没有拿到任何非 exec 工具（如内置的 web_search/read_file 等，日志里"tool-search: cataloged
/// 41 tools"证实它们存在）的真实调用样本，不知道它们的结果是否也走 command_output，还是走别的
/// stream 名字（比如更通用的 `item` kind:"tool"）。本函数只对 stream=="command_output" 生效，
/// 其余工具类型的 toolResult 映射本轮未覆盖，留给下一阶段补样本。
func mapOpenclawAgentCommandOutputToToolResult(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    seq: Int
) -> EventMessageUnion? {
    guard jsonString(data["phase"]) == "end" else { return nil }
    guard let toolCallID = jsonString(data["toolCallId"]) else { return nil }

    let status = jsonString(data["status"])
    let exitCode = jsonInt(data["exitCode"])
    let isError = (status == "failed") || ((exitCode ?? 0) != 0)
    let output = makeJSONAny(data["output"] ?? "")
    let durationMS = jsonInt(data["durationMs"])

    let resultPayload = ToolResultEventMessagePayload(
        durationMS: durationMS, isError: isError, output: output, toolCallID: toolCallID
    )
    let now = Date()
    return .toolResult(ToolResultEventMessage(
        direction: .event, payload: resultPayload, runID: runIDHint,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtToolResult
    ))
}

// MARK: - ③ agent(stream:"lifecycle") -> turnComplete / operationCompleted（现场实测样本 grounding）

/// `aborted` 是判别键——两条真实样本：
///  - 正常回合结束：`{"phase":"end","stopReason":"stop","aborted":false,...}` -> turnComplete。
///  - 对一个进行中的 exec 调用发 `sessions.abort` 后：先是
///    `{"phase":"end","status":"cancelled","aborted":true,"stopReason":"rpc",...}`，随后
///    `{"phase":"error","aborted":true,"stopReason":"aborted","error":"This operation was
///    aborted",...}` -> 均归为 operationCompleted（本轮 interrupt() 未实现，凡是 aborted:true
///    观察到的操作一律记 operationKind:.stop，因为触发路径是 KernelClient.stop() 调用的
///    sessions.abort）。
/// usage 参数是调用方（OpenclawGatewayKernelClient）按 session 缓存的"最近一次 assistant
/// session.message.usage"，因为 lifecycle 事件本身不带 input/output token 数（只有一个独立的
/// `agent`/`stream:"usage"` 事件只报 outputTokens 累计值，字段集不对齐 D2 Usage{inputTokens,
/// outputTokens} 的语义，不采用）。
func mapOpenclawAgentLifecycleToKernelEvent(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    seq: Int,
    cachedUsage: (input: Int, output: Int)?
) -> EventMessageUnion? {
    let phase = jsonString(data["phase"])
    guard phase == "end" || phase == "error" else { return nil }
    let aborted = jsonBool(data["aborted"]) ?? false
    let rawStopReason = jsonString(data["stopReason"])
    let now = Date()

    guard let runID = runIDHint else {
        // turnComplete/operationCompleted 的 runID 字段在 D2 里是必填——lifecycle 事件本身携带
        // 真实 runId（payload.runId，由调用方通过 runIDHint 传入），理论上不会缺失；一旦真的缺失
        // 就诚实跳过，不拿一个编造值填充必填字段。
        return nil
    }

    if !aborted {
        let stopReason: StopReason
        switch rawStopReason {
        case "stop": stopReason = .completed
        case "max_turns", "maxTurns": stopReason = .maxTurns // 推断：本轮未现场观察到这个取值
        default: stopReason = .error // 推断兜底：非 aborted 且不是已知"正常结束"字样时，保守记 error
        }
        let usage = cachedUsage.map { Usage(inputTokens: $0.input, outputTokens: $0.output) }
        let turnPayload = TurnCompleteEventMessagePayload(
            degraded: nil, forceResolvedApprovals: nil, stopReason: stopReason, usage: usage
        )
        return .turnComplete(TurnCompleteEventMessage(
            direction: .event, payload: turnPayload, runID: runID,
            sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtTurnComplete
        ))
    }

    // aborted == true -> operationCompleted。outcome 判别：真实样本里 phase=="end" 时
    // status=="cancelled"（sessions.abort 的 RPC 结果本身也确认了 outcome:"aborted"）记
    // succeeded（"这次 abort 操作成功执行了"，不是"这次 run 成功完成"——两者是不同维度）；
    // phase=="error" 那条后续帧语义不够确定（可能是 abort 生效后的收尾错误，也可能是别的失败），
    // 保守记 abortedEffectUnknown，不假装知道更多。
    let outcome: PayloadOutcome = phase == "end" ? .succeeded : .abortedEffectUnknown
    let operationID = "\(ourSessionID)-abort-\(runID)"
    let detail = jsonString(data["error"])
    let opPayload = OperationCompletedEventMessagePayload(
        affectedRunID: runID, detail: detail, newRunID: nil,
        operationID: operationID, operationKind: .stop, outcome: outcome
    )
    return .operationCompleted(OperationCompletedEventMessage(
        direction: .event, payload: opPayload, runID: runID,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtOperationCompleted
    ))
}

// MARK: - ④ session.approval -> approvalRequest（现场实测样本 grounding；terminal 分支见下方说明）

/// 真实样本（`sessions.messages.subscribe` 必须带 `includeApprovals:true` 才收得到这个事件；把
/// 会话 execAsk 临时 patch 成 "always" 才能在这个隔离环境里真正触发一次审批，默认策略 DEFAULT_ASK
/// 是 "off"——见 kernels/openclaw/src/infra/exec-approvals.ts:318）：
/// ```
/// {"sessionKey":"...","sourceSessionKey":"...","updatedAtMs":1784871218655,"phase":"pending",
///  "approval":{"id":"d7085add-...","status":"pending",
///    "presentation":{"kind":"exec","commandText":"echo hello-sg5","commandPreview":null,
///      "warningText":null,"host":"gateway","nodeId":null,"agentId":"main",
///      "allowedDecisions":["allow-once","deny"]},
///    "urlPath":"/approve/d7085add-...","createdAtMs":1784871218655,
///    "expiresAtMs":1784873018655}}
/// ```
/// 字段映射:
///  - reqID = approval.id ——D2 ApprovalRequestEventMessagePayload.reqID 的文档注释原文就是
///    "respondApproval() 的关联主键(= 内核 approval id,非 toolCallId)"，与 openclaw 的 approval.id
///    语义完全对上。
///  - kind：openclaw `ApprovalKindSchema` 只有 exec/plugin/system-agent 三个值，D2 `KindElement`
///    是 exec/file_write/mcp/sandbox/tool 五个值——只有 "exec" 直接对上（真实样本验证）。
///    "plugin"/"system-agent" 本轮没有现场样本，映射到 `.tool` 只是"最不失真的通用兜底"，未经验证，
///    不是 grounding 结论。
///  - timeoutMS = expiresAtMs - createdAtMs（真实样本算出 1800000ms = 30min）。
///  - timeoutAuthority = .documented——D1 spec 原文注释就是"openclaw 'documented'；hermes
///    'best_effort'"，这是 D1 设计文本自带的定性，不是本文件现场测出来的一个数字。
///  - toolCallID：**openclaw 的 approval payload 本身不携带 toolCallId 字段**
///    （`ExecApprovalPresentationSchema` 字段集：kind/commandText/commandPreview/warningText/
///    host/nodeId/agentId/allowedDecisions/agentId，没有 toolCallId——已读源码确认）。真实现场
///    观察到的顺序是：触发审批的那次 exec toolCall 的 session.message 事件总是先于对应的
///    session.approval(pending) 到达；本函数用调用方传入的 `lastToolCallIDHint`（同一 session
///    内"最近一次见到的 toolCallId"）做时序关联，这是**推断关联**，不是直接字段引用——如实标注：
///    并发多个未决 toolCall 时可能关联错，本轮样本（单一 toolCall 在途）没有暴露这个问题，
///    留给后续硬化。
///  - payload（JSONAny，D1 定义为"该 kind 下的不透明详情"）：取 `approval.presentation` 整体
///    包装——openclaw 没有另外一个字段专门叫"payload"，presentation 是这里语义最贴近的现场数据。
///  - proposedDecision：openclaw 真实样本没有这个字段，如实置 nil，不编造。
///
/// phase:"terminal" 分支：真实样本观察到 reason 取值是 openclaw 自己的
/// `ApprovalTerminalReasonSchema`（user/timeout/malformed-verdict/no-route/run-aborted/
/// gateway-restart/storage-corrupt——本轮实测拿到一次 "no-route"，因为没有任何客户端调用
/// approval.resolve 就到期/无路由自动 deny 了），这个词表和 D1 `ApprovalBufferResolvedEvent` 要求的
/// reason（仅 buffered_timeout/queue_overflow）完全不相交，因此 phase:"terminal" 不映射到 D2 11
/// 变体中的任何一个——如实返回 nil（不是遗漏，是诚实的"没有对应的 D2 事件"结论）。
func mapOpenclawSessionApprovalToKernelEvent(
    _ payload: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    lastToolCallIDHint: String?,
    seq: Int
) -> EventMessageUnion? {
    guard jsonString(payload["phase"]) == "pending" else {
        // terminal 分支：见上方文档注释，D1 11 变体里没有它的对应位置。
        return nil
    }
    guard let approval = jsonObject(payload["approval"]) else { return nil }
    guard let reqID = jsonString(approval["id"]) else { return nil }
    guard let toolCallID = lastToolCallIDHint else {
        // 没有任何 toolCall 关联线索——诚实跳过，不拿占位符填必填字段。
        return nil
    }
    guard let runID = runIDHint else {
        // ApprovalRequestEventMessage.runID 是必填字段——lifecycle/session.message 事件本应已经
        // 让调用方缓存到当前 session 的 runId；真缺失时诚实跳过，不拿 reqID/toolCallID 顶替一个
        // 语义完全不同的字段。
        return nil
    }

    let presentation = jsonObject(approval["presentation"]) ?? [:]
    let openclawKind = jsonString(presentation["kind"])
    let kind: KindElement = openclawKind == "exec" ? .exec : .tool // 见上方文档注释，非 exec 未验证

    let createdAtMs = jsonInt(approval["createdAtMs"])
    let expiresAtMs = jsonInt(approval["expiresAtMs"])
    let timeoutMS = (createdAtMs != nil && expiresAtMs != nil) ? (expiresAtMs! - createdAtMs!) : 0

    let approvalPayload = ApprovalRequestEventMessagePayload(
        kind: kind,
        payload: makeJSONAny(presentation),
        proposedDecision: nil,
        reqID: reqID,
        timeoutAuthority: .documented,
        timeoutMS: timeoutMS,
        toolCallID: toolCallID
    )
    let now = msEpochToDate(jsonInt(payload["updatedAtMs"]))
    return .approvalRequest(ApprovalRequestEventMessage(
        direction: .event, payload: approvalPayload, runID: runID,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtApprovalRequest
    ))
}

// MARK: - ⑤ 全局 shutdown -> 逐 session 广播 sessionEnd(reason: kernelExited)（现场实测样本 grounding）

/// 真实样本（对隔离 gateway 发 SIGTERM 实测）：
/// ```
/// {"type":"event","event":"shutdown","payload":{"reason":"gateway stopping",
///   "restartExpectedMs":null},"seq":2}
/// ```
/// （随后 WS 以 close code 1012 关闭。）`payload.reason` 是自由字符串（真实值 "gateway stopping"，
/// 不是 kernels/openclaw/src/gateway/server-close.ts 类型标注的字面量 "shutdown"|"restart"
/// 之一——说明broadcast 前这个字段被格式化过；不对这个字符串做匹配，只把"收到 shutdown 事件"这件事
/// 本身当作触发条件），映射为 D2 sessionEnd(reason: .kernelExited)——这是 gateway 级、不分 session
/// 的广播，因此对当前所有活跃 session 各产出一条。
func makeSessionEndEventForShutdown(ourSessionID: String, seq: Int) -> EventMessageUnion {
    let now = Date()
    let payload = SessionEndEventMessagePayload(reason: .kernelExited)
    return .sessionEnd(SessionEndEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtSessionEnd
    ))
}

/// WS 传输层自身断开（receiveLoop 报错、没有先收到 shutdown 帧）的 sessionEnd 合成——
/// **本轮未现场实测**（没有单独构造"纯网络中断、无 shutdown 帧"的场景），是源码/设计层面的推断：
/// OpenclawGatewayKernelClient 的 receiveLoop 在 `task.receive()` 抛错时，除了现有的
/// `failAllPending(error:)`（让 pending RPC continuation 收到 transport 错误）之外，理应也让活跃
/// session 的事件流收到一个"session 因传输中断而结束"的信号——D1 SessionEndEvent 的
/// reason:transport_closed 正是为这种场景设计的。
func makeSessionEndEventForTransportClosed(ourSessionID: String, seq: Int) -> EventMessageUnion {
    let now = Date()
    let payload = SessionEndEventMessagePayload(reason: .transportClosed)
    return .sessionEnd(SessionEndEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtSessionEnd
    ))
}

// MARK: - ⑥ 未接入任何 dispatch 路径的两个变体：capabilityChanged / approvalBufferResolved

/// evt.capability_changed 的构造函数——**本轮未接入任何真实触发路径，是 blocker 级缺口**。
/// D1 INV-4 原文（~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md）明确写着
/// "能力变更的感知路径仍是内核 RPC 报错(被动发现)+我方 Server 能力开关 override(主动决策)"——即
/// 这个事件从设计上就不是 kernel 主动 push 的，而是适配器自己在两种情况下合成：①调用某个方法时
/// 收到一个"因为能力不支持"形状的 RPC 拒绝（被动发现，需要先有一版 baseline capabilities 才谈得上
/// "变了"）；②运维/我方 Server 主动切换某个能力开关（主动决策）。这两条路径都依赖 `capabilities()`
/// 方法本身已经落地（本轮仍是 TODO 桩，见 KernelClient.swift 头注释），因此本函数只证明 D2
/// payload 在类型层面能正确构造，未被任何 handleIncoming 分支调用。D2 `Source` 枚举
/// （kernel_error_inferred/server_override）与 D1 这句话逐字对应，是本函数保留的唯一具体证据。
func buildCapabilityChangedEvent(
    capabilities: Capabilit,
    reason: String?,
    source: Source,
    ourSessionID: String,
    seq: Int
) -> EventMessageUnion {
    let now = Date()
    let payload = CapabilityChangedEventMessagePayload(capabilities: capabilities, reason: reason, source: source)
    return .capabilityChanged(CapabilityChangedEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtCapabilityChanged
    ))
}

/// evt.approval_buffer_resolved 的构造函数——**本轮未接入任何真实触发路径，是 blocker 级缺口**。
/// D1 §6.2"pending #2 缓冲策略"要求适配器自己维护一个"当前 session 是否已有一条 pending 审批、
/// 第二条到达时先本地缓冲、缓冲期超时或队列溢出时才终态化"的小状态机；respondApproval() 本身
/// 在本轮仍是 TODO 桩（见 KernelClient.swift 头注释），这个本地缓冲状态机自然也未实现——因此没有
/// 任何代码路径会产生 reqID/reason(buffered_timeout|queue_overflow) 这两个字段的真实值。已用真实
/// 探针核实：openclaw 原生 `session.approval` phase:"terminal" 的 reason 词表
/// （user/timeout/malformed-verdict/no-route/run-aborted/gateway-restart/storage-corrupt）与
/// D1 这里要求的词表完全不相交，说明这条事件本质上是纯适配器内部状态机的产物，不是"翻译 openclaw
/// 已有的某个 wire 事件"就能解决的——留给 respondApproval() 落地时一并实现。
func buildApprovalBufferResolvedEvent(
    reqID: String,
    reason: FluffyReason,
    ourSessionID: String,
    seq: Int
) -> EventMessageUnion {
    let now = Date()
    let payload = ApprovalBufferResolvedEventMessagePayload(reason: reason, reqID: reqID)
    return .approvalBufferResolved(ApprovalBufferResolvedEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtApprovalBufferResolved
    ))
}

// MARK: - 兼容旧调用点：SG-4 遗留的单事件签名（main.swift/CLIRunner.swift 尚未升级前的过渡）

/// SG-4 遗留签名的薄包装——OpenclawGatewayKernelClient 本轮已经改用
/// `mapOpenclawSessionMessageToKernelEvents`（数组版本，见①），这个函数只保留给还没升级的调用点，
/// 取数组第一个元素。**不建议新代码调用**。
func mapOpenclawSessionMessageToKernelEvent(_ payload: JSONObject, ourSessionID: String) -> EventMessageUnion? {
    mapOpenclawSessionMessageToKernelEvents(payload, ourSessionID: ourSessionID, runIDHint: nil).first
}
