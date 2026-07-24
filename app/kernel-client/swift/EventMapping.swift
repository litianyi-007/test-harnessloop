// openclaw 事件 -> D2 EventMessageUnion（11 变体）映射。SG-5 Stage A 大修（对抗审 T-044 REWORK 后的
// rework 轮）。
//
// 现场结论（rework 轮用 scratchpad/openclaw-iso3 重起隔离 openclaw + D3-proxy(localhost:3001) + Pi
// Postgres/new-api 真实探针补测，逐条在下面每个函数的文档注释标注 grounding 层级；上一轮（a07dc67）
// 已有的现场结论原样保留并在此基础上订正）：
//
//   1. openclaw 的 `session.message` 事件只承载"assistant 助手消息"（text/thinking/toolCall
//      content block）——从未观察到 role="toolResult" 的 session.message 广播（两次独立探针
//      复现同一结论：live 长连接从发送前就订阅、经历完整 toolCall→toolResult→下一轮，始终没有
//      role=toolResult 的 session.message 事件），尽管原始 transcript（sqlite
//      `transcript_events` 表）里确实持久化了 role="toolResult" 的消息——说明
//      `handleTranscriptUpdateBroadcast`（kernels/openclaw/src/gateway/server-session-events.ts）
//      的广播路径在工具结果这一步被跳过，只有真正的模型回合（user/assistant）会广播。
//   2. exec 工具调用的执行结果通过 `agent`（payload.stream 分好几种：run_status/lifecycle/item/
//      command_output/usage/assistant/thinking/error/approval/plan）实时推送，其中
//      `stream:"command_output"` 且 `data.phase:"end"` 的形状最贴近 D2 ToolResultEventPayload
//      （output/exitCode/durationMs/cwd 齐备），已用真实 exec 工具调用样本验证两次。
//      **rework 轮新真实样本（`scratchpad/openclaw-iso3/nonexec-run4.jsonl`，真实 Kimi + update_plan
//      工具）坐实：非 exec 工具（如 openclaw 内置 `update_plan`）走的是 `stream:"item"`
//      （`kind:"tool"`，phase:"start"/"end"，字段只有 itemId/title/status/name/meta/toolCallId/
//      startedAt/endedAt）——**没有 command_output 的 output 字段**，也没有观察到任何
//      `stream:"tool"`（handlers.tools.ts 源码里 `emitAgentEvent({stream:"tool",...})` 确实存在、
//      带 `data.result` 完整输出，但本轮真实探针在 `sessions.messages.subscribe` 客户端上从未收到
//      过一条 `stream:"tool"` 事件——gateway 侧似乎只把这个通用 tool 流投给注册为
//      run-scoped "tool event recipient" 的连接，plain subscribe 客户端不在其列，具体注册机制未
//      深挖，诚实登记为协议层未探明的缺口，见 F5 小节）。因此非 exec 工具的 toolResult 只能用
//      `item`(kind:"tool",phase:"end") 的 status 字段做 isError/duration 判定，`output` 字段
//      **诚实置空**（`null`），不编造。
//   3. `session.approval`（需要 `sessions.messages.subscribe` 传 `includeApprovals:true` 才收得到）
//      phase:"pending" 就是 evt.approval_request 的现场原型，已用真实样本验证（把 execAsk 临时
//      patch 成 "always" 触发）。phase:"terminal" 的 reason 词表（user/timeout/malformed-verdict/
//      no-route/run-aborted/gateway-restart/storage-corrupt，见
//      packages/gateway-protocol/src/schema/approvals.ts）与 D1 `ApprovalBufferResolvedEvent` 要求的
//      reason（仅 buffered_timeout/queue_overflow）完全不相交——真实 openclaw 从不产生后者，
//      approval_buffer_resolved 是 D1 §6.2"pending #2 本地缓冲策略"要求适配器自己维护的一个
//      本地状态机产物，respondApproval()/审批缓冲队列本轮未实现，因此本文件不把它接到任何真实
//      wire 事件上——见文末 `buildApprovalBufferResolvedEvent`。
//      **rework 轮订正（F4）**：上一轮的 `toolCallID` 关联用"同 session 最近一次 toolCall"猜测，
//      对抗审 codex 指出会串号（两个 toolCall 交错、旧缓存残留时误配）。openclaw 源码坐实
//      （`embedded-agent-subscribe.handlers.tools.ts:1669-1699`）：exec 审批还会经由
//      `emitAgentApprovalEvent` 广播一条 **`agent(stream:"approval", data.phase:"requested")`**
//      事件，`data.toolCallId`/`data.approvalId` 均为该次审批的**准确值**（不是猜测），且这条
//      `agent` 事件的外层 `payload.runId` 由 `enrichAgentEvent` 统一盖章、可靠。本文件改为：调用方
//      （OpenclawGatewayKernelClient）在收到这条 `agent(stream:"approval")` 时，把
//      `data.approvalId -> data.toolCallId` 的精确映射存进一个按 approvalId 为键的缓存；
//      `session.approval`(phase:"pending") 到达时用 `approval.id` 去查这个缓存，而不是"最近一次
//      toolCall"。两个交错的 pending 审批不会再互相踩，见 `mapOpenclawSessionApprovalToKernelEvent`
//      的新签名 `toolCallIDForApprovalID`。
//   4. `agent` 的 `stream:"lifecycle"` 在 `data.phase` 为 "end"/"error" 时是一次 run 的终态信号，
//      `data.aborted` 是判别键：`aborted:false` 对应 evt.turn_complete（真实样本：正常回合结束）；
//      `aborted:true` 对应 **evt.operation_completed + evt.turn_complete(stopReason:.cancelled) 两者
//      一起**（rework 轮订正，见 F6：D1 §9.3 stop() 事件顺序保证要求"先完成该 run 的强制取消并产出
//      TurnCompleteEvent(stopReason:'cancelled')"，不能只发 operation_completed 不发 turn_complete）。
//      **rework 轮新真实样本**（`scratchpad/openclaw-iso3/nonexec-run4.jsonl`）额外证实：正常回合
//      结束时 lifecycle 会先后发两条几乎相同的帧——`phase:"finishing"` 然后 `phase:"end"`（字段
//      一致，只有 `phase` 不同）——本文件继续只对 `phase == "end"`/`"error"` 触发映射，`"finishing"`
//      如实忽略，避免同一个终态被翻译成两条重复的 D2 事件（未观察到 `"finishing"` 单独出现而没有
//      随后的 `"end"`，如实标注为经验性假设，非源码级证明）。
//   5. gateway 关闭时会给所有连接广播一次全局 `shutdown` 事件（真实样本：向隔离 gateway 发
//      SIGTERM 实测）——本文件把它映射为对所有当前活跃 session 广播 evt.session_end(reason:
//      kernel_exited)。WS 传输层自身断开（receiveLoop 报错、没有先收到 shutdown 帧）走
//      reason: transport_closed；两者互斥去重（F8，见调用方 terminal 状态记录）。
//   6. evt.error（rework 轮由 blocker 转为已接入，F5）：openclaw `gateway/server-chat.ts:1387-1403`
//      源码坐实存在 `agent(stream:"error", data:{reason:"seq gap", expected, received})` 这一真实
//      wire 事件（连接侧收到的 `agent` 事件 seq 与本地期望的 seq 不连续时同步产出）——**diff 不再
//      诚实 defer**，本文件接入并映射到 D2 evt.error（code 用 `.unknown`，因为 D1 ErrorEvent.code
//      封闭枚举里没有专门对应"协议层 seq 断档"的取值，如实标注是推断映射不是字面对应；
//      recoverable 记 `.run`，因为 seq gap 只影响这个 run 的事件流完整性，不代表 session 本身失效）。
//      evt.capability_changed 本轮仍未接到任何真实触发路径：D1 INV-4 原文就说"能力变更的感知路径是
//      内核 RPC 报错(被动发现)+我方 Server 能力开关 override(主动决策)"——即它从来不是一个 kernel
//      主动 push 的事件，需要 capabilities() 方法本身先落地（本轮仍是 TODO 桩）才有基线可 diff，
//      构造函数保留、明确未接入 dispatch，诚实标 unsupported。

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
/// 布尔）必须先包一层才能序列化。`value` 传 `NSNull()` 时往返出的是 JSON `null`——用于诚实表达"这个
/// 字段本轮确实取不到真实值"（如非 exec 工具的 output，见②），不是遗漏，是明确的空值。
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

/// 把 openclaw wire 上的毫秒 epoch 数字字段转成 `Date`——用于 F3：D2 `KernelEventBase.ts` 语义是
/// "事件发生时刻"，必须取 openclaw 原始 payload/message 自带的时间戳，不能用 `Date()`（那是适配器
/// 本地处理/转发时刻，属于 envelope 的 `sentAt` 语义，两者是 D2 v3 §2 明确分开的两个字段）。
/// 缺失时退化到 `Date()` 只发生在 openclaw 自己也没有提供任何时间戳的合成事件上（如 transport_closed，
/// 没有更早的 wire 帧可以取时间戳），且发生处均有单独注释标注。
func msEpochToDate(_ ms: Int?) -> Date {
    guard let ms = ms else { return Date() }
    return Date(timeIntervalSince1970: Double(ms) / 1000.0)
}

// MARK: - F3：per-run seq 生成器契约
//
// D1 v3 §9.2/§3：`seq` 仅承诺"同一 runId 内排序"，不是全局单调、也不是 wire 帧外层 `seq`/
// `messageSeq` 的直接透传——上一轮（a07dc67）在 `session.message` 用 `messageSeq`、在 `agent` 事件用
// frame 外层 `seq`，两个域混用导致同一个 run 观察到 `2→21→4→30`（对抗审 T-044 F3 复现）。
// rework 轮改为：每个 mapper 函数都不再自己从 wire 读 seq，而是通过调用方传入的 `nextSeq` 闭包按
// **runId 作用域**取号——闭包本身由 `OpenclawGatewayKernelClient`（actor 隔离，状态安全）按
// `runID ?? sessionID` 维护一个从 1 开始递增的计数器，保证同一 run 内先产出的事件 seq 更小。

// MARK: - ① session.message -> messageDelta / thinking / toolCall（三种，均现场实测样本 grounding）

/// openclaw `session.message` 的 `payload.message` 只在 role=="assistant" 时才可能产出 D2 事件——
/// role=="user" 是调用方自己发的输入回显，D1 的 KernelEvent 流不表达"回显我方输入"这件事（D2
/// MessageDeltaEventMessagePayload.role 这个类型本身就只有一个取值 `.assistant`，quicktype
/// 从 schema 生成时就把这一点固化了）。一条 assistant 消息的 `content` 可以是纯字符串，也可以是
/// 多个 block 的数组（真实样本证实：文本 block 和 toolCall block 可以同时出现在同一条消息里），
/// 因此一条 session.message 可能产出 0~N 个 D2 事件，返回值是数组，`nextSeq()` 每产出一个事件调用
/// 一次，保证同一条消息里的多个 block 拿到严格递增的 run 内 seq（F3）。
///
/// 现场样本（`scratchpad/openclaw-iso3`，D3-proxy + 真实 Kimi）：
/// ```
/// {"role":"assistant","content":[{"type":"toolCall","id":"tool_...","name":"exec",
///   "arguments":{"command":"ls -la"},"partialArgs":"..."}],
///  "usage":{"input":9288,"output":2346,...},"stopReason":"toolUse","timestamp":1784...,
///  "responseId":"..."}
/// ```
/// `timestamp` 字段（ms epoch）是本条 assistant 消息真正产出的时刻——F3 要求的 `ts` 就取这里，
/// 不用 `Date()`。
func mapOpenclawSessionMessageToKernelEvents(
    _ payload: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    nextSeq: () -> Int
) -> [EventMessageUnion] {
    guard let message = jsonObject(payload["message"]) else { return [] }
    guard jsonString(message["role"]) == "assistant" else {
        // role=="user"：回显，无 D2 对应事件。role=="toolResult" 从未在 session.message 里现场
        // 观察到（见头注释①），如果未来 openclaw 版本改变了这一点、这里会静默丢弃——保留在这里
        // 一并说明，而不是假装处理了一个从未见过的分支。
        return []
    }

    let sentAt = Date()
    let originTS = msEpochToDate(jsonInt(message["timestamp"]))
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
                sentAt: sentAt, seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtMessageDelta
            )))

        case "thinking", "reasoning", "redacted_thinking":
            // grounding：源码——kernels/openclaw/src/gateway/chat-display-projection.ts
            // `isAssistantInternalReasoningContentType` 把 "thinking"/"reasoning"/
            // "redacted_thinking" 三个字面量识别为推理类 block。这是 thinking 的第二个来源
            // （第一个来源是下面 handleAgentEvent 的 `agent(stream:"thinking")`，F5 新增，
            // 源码级 grounding：`embedded-agent-subscribe.ts:1226-1254` `emitReasoningStream`）——
            // 两者不冲突：session.message 里的 thinking block 是"这条已落地的 assistant 消息带的
            // 完整推理内容投影"，agent(stream:"thinking") 是"逐 token 的推理增量流"，同一次真实推理
            // 可能两条路径都会各自产出一次 D2 thinking 事件，这是 openclaw 自身双通道广播的忠实反映，
            // 不是本文件重复映射的 bug。
            let delta = jsonString(block["text"]) ?? jsonString(block["thinking"]) ?? ""
            let visibility: Visibility = type == "redacted_thinking" ? .summary : .raw
            let thinkingPayload = ThinkingEventMessagePayload(delta: delta, visibility: visibility)
            events.append(.thinking(ThinkingEventMessage(
                direction: .event, payload: thinkingPayload, runID: runIDHint,
                sentAt: sentAt, seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtThinking
            )))

        case "toolCall", "tool_call", "toolUse", "tool_use":
            guard let toolCallID = jsonString(block["id"]), let name = jsonString(block["name"]) else { continue }
            let input = makeJSONAny(block["arguments"] ?? block["input"] ?? [:] as JSONObject)
            let toolCallPayload = ToolCallEventMessagePayload(input: input, name: name, status: .started, toolCallID: toolCallID)
            events.append(.toolCall(ToolCallEventMessage(
                direction: .event, payload: toolCallPayload, runID: runIDHint,
                sentAt: sentAt, seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtToolCall
            )))

        default:
            // 未识别的 content block type——如实跳过，不臆造映射。
            continue
        }
    }

    return events
}

// MARK: - ② agent(stream:"command_output") -> toolResult（exec 工具族，现场实测样本 grounding）

/// 真实样本（同一 exec 工具调用的完整生命周期，`agent` 事件 `payload.stream` 依次是
/// run_status→item(×N)→command_output(phase delta×N)→item(phase end)→command_output(phase end)）：
/// ```
/// {"stream":"command_output","data":{"itemId":"command:tool_Jd9...","phase":"end",
///   "toolCallId":"tool_Jd9HsUlLKZyhkA7uhkIvInHr","name":"exec",
///   "output":"AGENTS.md\nBOOTSTRAP.md\n...","status":"completed","exitCode":0,
///   "durationMs":20,"cwd":"/Users/.../workspace"}}
/// ```
/// 只取 `phase:"end"` 的 `command_output`（`phase:"delta"` 是流式中间态，不代表工具调用终态）。
/// `originTS` 取 `agent` wire 帧外层 `payload.ts`（openclaw `enrichAgentEvent` 在事件产生时盖章的
/// 真实时刻，见 `infra/agent-events.ts:628` `ts: Date.now()`），不用 `Date()`（F3）。
///
/// 范围声明（rework 轮 F5 用真实非 exec 工具样本坐实的结论，取代上一轮"未拿到样本"的开放问题）：
/// `command_output` 这个 stream 名字确认只属于 exec/命令族工具（真实样本：`update_plan` 这个非 exec
/// 内置工具走的是 `stream:"item"`，从未产出 `command_output`，见文件头注释②与
/// `mapOpenclawAgentToolItemToToolResult`）。本函数只对 stream=="command_output" 生效。
func mapOpenclawAgentCommandOutputToToolResult(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    originTS: Date,
    nextSeq: () -> Int
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
    return .toolResult(ToolResultEventMessage(
        direction: .event, payload: resultPayload, runID: runIDHint,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtToolResult
    ))
}

// MARK: - ②b agent(stream:"item", kind:"tool") -> toolResult（非 exec 工具族，F5 rework 轮新增）

/// **真实样本 grounding**（`scratchpad/openclaw-iso3/nonexec-run4.jsonl`，真实 Kimi + 内置
/// `update_plan` 工具，2026-07-24 rework 轮隔离环境重新探针）：
/// ```
/// {"stream":"item","data":{"itemId":"tool:tool_p8yLr7taJUMG2ePajv3zPtmR","phase":"end","kind":"tool",
///   "title":"tool_call","status":"completed","name":"tool_call",
///   "toolCallId":"tool_p8yLr7taJUMG2ePajv3zPtmR","startedAt":1784876075348,"endedAt":1784876075377}}
/// ```
/// 对照同一次真实调用的 `session.message` toolCall content block：
/// `{"type":"toolCall","id":"tool_p8yLr7taJUMG2ePajv3zPtmR","name":"tool_call",
///   "arguments":{"id":"openclaw:core:update_plan","args":{...}}}`——`item.data.toolCallId` 与
/// `session.message` toolCall block 的 `id` 字段**逐字相同**，证实这条 item 事件确实是那次
/// toolCall 的终态回执，关联是可靠的（不是猜测）。
///
/// **诚实的缺口（F5 open question 的现场结论，非臆造）**：这条 `item` 事件只有
/// itemId/phase/kind/title/status/name/meta/toolCallId/startedAt/endedAt——**没有任何 output/
/// result 字段**。openclaw 源码里确实存在一个专门携带完整输出的通用事件
/// （`embedded-agent-subscribe.handlers.tools.ts:1615-1628`，`emitAgentEvent({stream:"tool",
/// data:{phase:"result", result: eventResult, ...}})`，`eventResult` 对非 exec 工具就是完整
/// `sanitizeToolResult(result)`），但本轮用真实 `sessions.messages.subscribe`
/// （`includeApprovals:true`）客户端反复探针，**从未收到过一条 `stream:"tool"` 的 `agent` wire
/// 事件**——gateway 侧似乎要求连接先被登记为该 run 的"tool event recipient"才能收到这条通用
/// tool 流（`gateway/server-chat.ts` 里 `runToolRecipients`/`broadcastToConnIds("agent", ...)` 一带
/// 的分发逻辑指向这个方向，但具体登记 RPC/时机本轮未定位到，属于协议层未探明的缺口，如实标注，
/// 不是本文件的映射 bug）。因此非 exec 工具的 `output` 字段本函数诚实置为 JSON `null`
/// （`makeJSONAny(NSNull())`），`isError` 用 `status != "completed"` 判定（真实可用），`durationMS`
/// 用 `endedAt - startedAt` 换算（真实可用，非编造）。
///
/// **去重规则**：exec 工具（`isExecToolName`：`"exec"`/`"bash"`）同时会产出这条 `item` 事件
/// **和**权威的 `command_output`（真正带 output/exitCode）——调用方（`handleAgentEvent`）按
/// `data.name` 排除 exec 工具族，只对非 exec 工具调用本函数，避免同一个 toolCallId 产出两条互相
/// 矛盾的 D2 toolResult（一条有真实 output、一条 output 是 null）。
func mapOpenclawAgentToolItemToToolResult(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    originTS: Date,
    nextSeq: () -> Int
) -> EventMessageUnion? {
    guard jsonString(data["kind"]) == "tool" else { return nil }
    guard jsonString(data["phase"]) == "end" else { return nil }
    guard let toolCallID = jsonString(data["toolCallId"]) else { return nil }

    let status = jsonString(data["status"])
    let isError = status != "completed"
    let durationMS: Int?
    if let started = jsonInt(data["startedAt"]), let ended = jsonInt(data["endedAt"]) {
        durationMS = max(0, ended - started)
    } else {
        durationMS = nil
    }
    // 诚实置空——见函数文档注释的"诚实的缺口"一段,不编造 output。
    let output = makeJSONAny(NSNull())

    let resultPayload = ToolResultEventMessagePayload(
        durationMS: durationMS, isError: isError, output: output, toolCallID: toolCallID
    )
    return .toolResult(ToolResultEventMessage(
        direction: .event, payload: resultPayload, runID: runIDHint,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtToolResult
    ))
}

/// exec 工具名词表——与 openclaw `embedded-agent-subscribe.handlers.tools.ts:362-364`
/// `isExecToolName` 逐字对应（`toolName === "exec" || toolName === "bash"`），供调用方判断
/// 一次 `agent(stream:"item", kind:"tool")` 是否应该跳过（让权威的 command_output 来源接管）。
func isOpenclawExecToolName(_ name: String?) -> Bool {
    name == "exec" || name == "bash"
}

// MARK: - ③ agent(stream:"lifecycle") -> turnComplete / operationCompleted（现场实测样本 grounding）

/// `!aborted` 分支：正常回合结束 -> turnComplete。
///
/// **F6 订正**：上一轮把"合法 `phase:end` 但没有 `stopReason`"默认记成 `.error`，对抗审 codex 指出
/// openclaw 测试里确实存在 `data:{phase:"end"}`（无 stopReason）这种合法终态，不该被误报成错误。
/// 源码坐实（rework 轮新读 `kernels/openclaw/src/agents/embedded-agent-subscribe.handlers.lifecycle.ts:
/// 176-202`）：`phase` 只有在 `isError`（= 上一条 assistant 消息自己的 `stopReason === "error"`）时
/// 才会是 `"error"`，否则一律是 `"end"`（或 `"finishing"`，本文件不处理，见头注释④）——也就是说
/// **`phase == "end"` 这个事实本身，由 openclaw 自己的构造逻辑保证 `isError == false`**，缺失
/// `stopReason` 只代表"没有更细的终止原因可报"，不代表出错。因此缺失/未知取值一律折叠到
/// `.completed`，不再默认 `.error`。
/// 真实取值来源（同文件 `terminalStopReason` 变量）：非 error 分支的 `stopReason` 落回"上一条
/// assistant 消息自己的 `stopReason`"——真实样本观察到 `"stop"`（正常结束）与 `"toolUse"`（回合内
/// 还在工具调用中就进入了 lifecycle "end"，边缘情况，同样折叠进 `.completed`，因为 `aborted:false`
/// + `phase:"end"` 已经由 openclaw 保证"不是错误终止"）。`"max_turns"`/`"maxTurns"` 本轮仍未现场
/// 观察到，映射到 `.maxTurns`维持上一轮的推断标注，未改判。
///
/// **M2 订正（收 T-045 codex 确认性再审 MUST-FIX）**：上一轮只看 `data.stopReason`，完全忽略
/// `data.phase` 本身——但源码坐实（同一个 `embedded-agent-subscribe.handlers.lifecycle.ts:176-202`
/// `emitLifecycleTerminal`）：当 `isError==true` 时 `phase` 被设成 `"error"`，且 `terminalStopReason`
/// 的推导对 `isError` 分支直接短路成 `undefined`（`(!isError && isAssistantMessage(lastAssistant) ?
/// lastAssistant.stopReason : undefined)`——也就是说 `phase:"error"` 这一帧的 `data.stopReason`
/// 很可能根本不是 `"error"` 字面值（甚至可能完全缺失），只有 `phase` 字段本身能可靠地表达"这是一次
/// assistant 错误终止"。上一轮 handler 把 `phase=="error"` 的帧也送进这个 mapper（`aborted==false`
/// 分支两者都会进来），但 mapper 只看 `stopReason`，于是被这个"缺省折叠成 completed"的逻辑一并误报
/// 成 `.completed`——一次真实的 assistant 错误被报告成"正常完成"。修法：`phase=="error"` 优先于
/// `stopReason` 判定，直接映射 `.error`（D2 `StopReason` 枚举本身就有这个取值，语义精确对应，不是
/// 推断）；只有 `phase != "error"` 时才继续走 `stopReason` 的 max_turns/completed 折叠逻辑。
func mapOpenclawAgentLifecycleToTurnComplete(
    _ data: JSONObject,
    ourSessionID: String,
    runID: String,
    originTS: Date,
    cachedUsage: (input: Int, output: Int)?,
    nextSeq: () -> Int
) -> EventMessageUnion {
    let phase = jsonString(data["phase"])
    let rawStopReason = jsonString(data["stopReason"])
    let stopReason: StopReason
    if phase == "error" {
        // M2：phase 本身就是 assistant 错误终止的权威信号——不看 stopReason 字段是否存在/取值
        // 为何，直接映射 error，别再忽略 phase。
        stopReason = .error
    } else {
        switch rawStopReason {
        case "max_turns", "maxTurns":
            stopReason = .maxTurns // 推断：本轮未现场观察到这个取值，维持上一轮标注
        default:
            // "stop"/"toolUse"/nil/其余未知取值：aborted:false + phase:"end" 由 openclaw 自身构造
            // 逻辑保证非错误终止（见函数文档注释），一律记 completed，不再默认 error（F6）。
            stopReason = .completed
        }
    }
    let usage = cachedUsage.map { Usage(inputTokens: $0.input, outputTokens: $0.output) }
    let turnPayload = TurnCompleteEventMessagePayload(
        degraded: nil, forceResolvedApprovals: nil, stopReason: stopReason, usage: usage
    )
    return .turnComplete(TurnCompleteEventMessage(
        direction: .event, payload: turnPayload, runID: runID,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtTurnComplete
    ))
}

/// `aborted` 分支：**F6 订正**——上一轮只发一条 `operationCompleted`，且其 `operationId` 是
/// mapper 自己派生的 `"\(ourSessionID)-abort-\(runID)"`，与 `OpenclawGatewayKernelClient.stop()`
/// 返回给调用方的 `StopResultPayload.operationID`（上一轮是完全不同的
/// `"\(sessionID)-stop-abort_\(status)"`）互不相同，调用方拿到的 Promise 结果和异步旁路事件根本无法
/// 关联；D1 v3 §9.3"stop 的事件顺序保证"还要求这次强制取消**必须**同时产出
/// `TurnCompleteEvent(stopReason:'cancelled')`，上一轮完全没发。
///
/// rework 轮修法：`operationID` 改为**调用方（`stop()`）在发起 `sessions.abort` 之前就已经铸造好**
/// 的唯一值，通过参数传入（不再自己派生）；本函数一次性返回 `[operationCompleted, turnComplete]`
/// 两个事件（顺序即数组顺序，调用方按序 yield，先 operation_completed 后 turn_complete，符合
/// 任务书 F6 要求的"单个 operation_completed → turn_complete(cancelled) → session_end(stopped)"
/// 序列的前两段）。调用方负责保证本函数对同一次 stop() 只被调用一次（同一个 run 的第二条 aborted
/// 帧——真实样本里 `phase:"end"` 之后常跟一条 `phase:"error",error:"This operation was aborted"`
/// 的收尾帧——被调用方去重，不再产出第二组 operationCompleted/turnComplete，见
/// `OpenclawGatewayKernelClient.handleAgentEvent` 的 pendingStop 状态机）。
///
/// outcome 判别（同上一轮，未改判）：真实样本里 phase=="end" 时 status=="cancelled"（sessions.abort
/// 的 RPC 结果本身也确认了 outcome:"aborted"）记 succeeded（"这次 abort 操作成功执行了"）；
/// phase=="error" 那条后续帧语义不够确定，保守记 abortedEffectUnknown。
func mapOpenclawAgentLifecycleToAbortTerminalEvents(
    _ data: JSONObject,
    ourSessionID: String,
    runID: String,
    operationID: String,
    originTS: Date,
    cachedUsage: (input: Int, output: Int)?,
    nextSeq: () -> Int
) -> [EventMessageUnion] {
    let phase = jsonString(data["phase"])
    let outcome: PayloadOutcome = phase == "end" ? .succeeded : .abortedEffectUnknown
    let detail = jsonString(data["error"])
    let opPayload = OperationCompletedEventMessagePayload(
        affectedRunID: runID, detail: detail, newRunID: nil,
        operationID: operationID, operationKind: .stop, outcome: outcome
    )
    let operationCompletedEvent = EventMessageUnion.operationCompleted(OperationCompletedEventMessage(
        direction: .event, payload: opPayload, runID: runID,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtOperationCompleted
    ))

    let usage = cachedUsage.map { Usage(inputTokens: $0.input, outputTokens: $0.output) }
    let turnPayload = TurnCompleteEventMessagePayload(
        degraded: nil, forceResolvedApprovals: nil, stopReason: .cancelled, usage: usage
    )
    let turnCompleteEvent = EventMessageUnion.turnComplete(TurnCompleteEventMessage(
        direction: .event, payload: turnPayload, runID: runID,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtTurnComplete
    ))

    return [operationCompletedEvent, turnCompleteEvent]
}

// MARK: - ④ session.approval -> approvalRequest（现场实测样本 grounding；toolCallID 关联 F4 rework）

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
///    "plugin"/"system-agent" 本轮没有现场样本，映射到 `.tool` 只是"最不失真的通用兜底"，未经验证。
///  - timeoutMS = expiresAtMs - createdAtMs（真实样本算出 1800000ms = 30min）。
///  - timeoutAuthority = .documented——D1 spec 原文注释就是"openclaw 'documented'；hermes
///    'best_effort'"，这是 D1 设计文本自带的定性，不是本文件现场测出来的一个数字。
///  - **toolCallID（F6 rework 订正，取代上一轮的"最近一次 toolCall"猜测）**：openclaw 的
///    `session.approval` payload 本身仍然不携带 toolCallId 字段（`ExecApprovalPresentationSchema`
///    字段集确认无此字段）。上一轮用调用方传入的"同 session 最近一次 toolCallId"做时序关联，被
///    codex 对抗审指出会串号（两个 toolCall 交错、或旧缓存残留时误配）。rework 轮改为：调用方
///    (`OpenclawGatewayKernelClient`) 从**另一个更权威的真实来源**——`agent(stream:"approval",
///    data.phase:"requested")`，其 `data.approvalId`/`data.toolCallId` 都是这次审批的准确值
///    （见 `embedded-agent-subscribe.handlers.tools.ts:1669-1699`）——按 `approvalId` 建立一个精确
///    的一次性缓存，本函数的 `toolCallIDForApprovalID` 参数就是"用 `approval.id` 去查这个缓存"的
///    结果，不再是"最近一次"的猜测。缺失时仍诚实跳过（不拿占位符顶替）。
///  - payload（JSONAny，D1 定义为"该 kind 下的不透明详情"）：取 `approval.presentation` 整体
///    包装——openclaw 没有另外一个字段专门叫"payload"，presentation 是这里语义最贴近的现场数据。
///  - proposedDecision：openclaw 真实样本没有这个字段，如实置 nil，不编造。
///  - **ts（F3 rework 新增）**：取 `payload.updatedAtMs`（这条 session.approval 事件自己的
///    产出时刻），`sentAt` 改为 `Date()`（适配器本地转发时刻）——上一轮把两者都设成
///    `updatedAtMs`，混淆了 envelope `sentAt` 与业务 `ts` 两个不同语义（D2 v3 §2）。
///
/// phase:"terminal" 分支：真实样本观察到 reason 取值是 openclaw 自己的
/// `ApprovalTerminalReasonSchema`（user/timeout/malformed-verdict/no-route/run-aborted/
/// gateway-restart/storage-corrupt），这个词表和 D1 `ApprovalBufferResolvedEvent` 要求的
/// reason（仅 buffered_timeout/queue_overflow）完全不相交，因此 phase:"terminal" 不映射到 D2 11
/// 变体中的任何一个——如实返回 nil。
func mapOpenclawSessionApprovalToKernelEvent(
    _ payload: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    toolCallIDForApprovalID: String?,
    nextSeq: () -> Int
) -> EventMessageUnion? {
    guard jsonString(payload["phase"]) == "pending" else {
        // terminal 分支：见上方文档注释，D1 11 变体里没有它的对应位置。
        return nil
    }
    guard let approval = jsonObject(payload["approval"]) else { return nil }
    guard let reqID = jsonString(approval["id"]) else { return nil }
    guard let toolCallID = toolCallIDForApprovalID else {
        // 没有从 agent(stream:"approval") 观察到这次 approvalId 对应的 toolCallId——诚实跳过，
        // 不拿"最近一次"占位符顶替（F4：那正是上一轮被判定会串号的做法）。
        return nil
    }
    guard let runID = runIDHint else {
        // ApprovalRequestEventMessage.runID 是必填字段——真缺失时诚实跳过。
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
    let originTS = msEpochToDate(jsonInt(payload["updatedAtMs"]))
    return .approvalRequest(ApprovalRequestEventMessage(
        direction: .event, payload: approvalPayload, runID: runID,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtApprovalRequest
    ))
}

// MARK: - ⑤ agent(stream:"thinking") -> thinking（F5 rework 新增，源码级 grounding）

/// 真实源码（`kernels/openclaw/src/agents/embedded-agent-subscribe.ts:1226-1254`
/// `emitReasoningStream`）：
/// ```ts
/// emitAgentEvent({ runId: params.runId, stream: "thinking", data: { text: trimmed, delta } });
/// ```
/// `data.delta` 是相对上一次已发送内容的增量，`data.text` 是累计全文——D2 `ThinkingEventMessagePayload`
/// 只要 `delta`，直接取 `data.delta`。`visibility` 这条流本身不携带脱敏/摘要标记，`.raw` 是最贴近
/// "逐 token 实时推理流"语义的取值（与 `session.message` 里未打 `redacted_thinking` 标记的
/// thinking block 用同一取值一致）。
///
/// **本轮未能现场触发一次真实带 thinking 内容的响应**（`d3proxy/kimi-for-coding` provider 目录项
/// 声明 `reasoning:false`，结构性验证了"当前现场配置下 thinking 不可达"）——这是源码级 grounding
/// （dispatch 路径确实存在、字段确实这样取），不是现场实测；诚实标注，与上一轮 SG-5 对同一限制的
/// 标注一致。
func mapOpenclawAgentThinkingToKernelEvent(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    originTS: Date,
    nextSeq: () -> Int
) -> EventMessageUnion? {
    let delta = jsonString(data["delta"]) ?? jsonString(data["text"]) ?? ""
    let thinkingPayload = ThinkingEventMessagePayload(delta: delta, visibility: .raw)
    return .thinking(ThinkingEventMessage(
        direction: .event, payload: thinkingPayload, runID: runIDHint,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtThinking
    ))
}

// MARK: - ⑥ agent(stream:"error") -> error（F5 rework 新增，取代上一轮的 defer）

/// 真实源码（`kernels/openclaw/src/gateway/server-chat.ts:1387-1403`）：连接侧观察到某个 run 的
/// `agent` 事件 `seq` 与本地记录的期望值不连续时，同步广播一条：
/// ```ts
/// broadcast("agent", { runId, stream: "error", ts, sessionKey, data: { reason: "seq gap", expected, received } }, ...)
/// ```
/// 这是本轮唯一有源码级确切字段坐实的 `agent(stream:"error")` 形状；`infra/agent-events.ts:35-49`
/// 的 `AgentEventStream` 类型声明还列了这个 stream 名字本身是协议一等公民（不是旁路），但具体还有
/// 哪些场景会产出 `stream:"error"`、携带什么别的 `data` 形状，本轮未逐一穷举源码调用点——因此本函数
/// 对"seq gap"形状做精确字段映射，对其余未知形状做尽力而为的兜底（取 `data.reason`/`data.message`
/// 任意能找到的字符串字段拼一条 message，不假装认得全部变体）。
///
/// 字段映射：
///  - code：D1 `ErrorEvent.code` 是封闭枚举（approval_timeout/auth_failed/kernel_crashed/
///    network_lost/rate_limited/sandbox_denied/unknown），"seq gap"（协议层事件序号断档）没有
///    一个字面对应的取值——映射到 `.unknown` 是诚实的推断，不是字面对应，如实标注。
///  - message：拼一条人类可读的诊断信息（"event stream seq gap: expected X, got Y"），不编造。
///  - nativeCode：D2 文档注释里明确"调试参考，非契约稳定字段"——直接塞 `"seq gap"` 这个 openclaw
///    自己的 `reason` 字面值，供调试用，不承诺稳定。
///  - recoverable：`.run`——seq gap 只影响这一个 run 的事件流完整性（调用方可能错过了几条中间
///    事件），不代表整个 session 已经失效，`.run` 比 `.session`/`.none` 更贴近这个语义，如实标注为
///    推断而非字面对应（D1 没有为"seq gap"这个具体场景钉死 recoverable 取值）。
func mapOpenclawAgentErrorToKernelEvent(
    _ data: JSONObject,
    ourSessionID: String,
    runIDHint: String?,
    originTS: Date,
    nextSeq: () -> Int
) -> EventMessageUnion? {
    let reason = jsonString(data["reason"])
    let message: String
    let nativeCode: String?
    if reason == "seq gap" {
        let expected = jsonInt(data["expected"])
        let received = jsonInt(data["received"])
        message = "event stream seq gap: expected \(expected.map(String.init) ?? "?"), got \(received.map(String.init) ?? "?")"
        nativeCode = "seq gap"
    } else {
        // 未穷举的形状——尽力而为拼一条诊断信息，不假装认得。
        message = reason ?? jsonString(data["message"]) ?? "unrecognized agent error stream payload"
        nativeCode = reason
    }
    let errorPayload = ErrorEventMessagePayload(
        code: .unknown, message: message, nativeCode: nativeCode, recoverable: .run
    )
    return .error(ErrorEventMessage(
        direction: .event, payload: errorPayload, runID: runIDHint,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtError
    ))
}

// MARK: - ⑦ 全局 shutdown -> 逐 session 广播 sessionEnd(reason: kernelExited)（现场实测样本 grounding）

/// 真实样本（对隔离 gateway 发 SIGTERM 实测）：
/// ```
/// {"type":"event","event":"shutdown","payload":{"reason":"gateway stopping",
///   "restartExpectedMs":null},"seq":2}
/// ```
/// （随后 WS 以 close code 1012 关闭。）`payload.reason` 是自由字符串，不对这个字符串做匹配，只把
/// "收到 shutdown 事件"这件事本身当作触发条件，映射为 D2 sessionEnd(reason: .kernelExited)——这是
/// gateway 级、不分 session 的广播，因此对当前所有活跃 session 各产出一条。这条 wire 帧本身没有
/// 携带一个"事件发生时刻"字段，`ts` 诚实退化为 `Date()`（F3：没有更早的 wire 时间戳可用，不是没做）。
func makeSessionEndEventForShutdown(ourSessionID: String, nextSeq: () -> Int) -> EventMessageUnion {
    let now = Date()
    let payload = SessionEndEventMessagePayload(reason: .kernelExited)
    return .sessionEnd(SessionEndEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: nextSeq(), sessionID: ourSessionID, ts: now, type: .evtSessionEnd
    ))
}

/// WS 传输层自身断开（receiveLoop 报错、没有先收到 shutdown 帧）的 sessionEnd 合成——
/// **本轮未现场实测**（没有单独构造"纯网络中断、无 shutdown 帧"的场景），是源码/设计层面的推断。
/// F8：调用方必须保证这条与 `makeSessionEndEventForShutdown`/`makeSessionEndEventForStop` 三者
/// 对同一个 session 只产出其中一条（去重逻辑在 `OpenclawGatewayKernelClient` 的 terminal 状态记录，
/// 不在本函数——本函数本身仍是纯字段构造，不做去重判断）。
func makeSessionEndEventForTransportClosed(ourSessionID: String, nextSeq: () -> Int) -> EventMessageUnion {
    let now = Date()
    let payload = SessionEndEventMessagePayload(reason: .transportClosed)
    return .sessionEnd(SessionEndEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: nextSeq(), sessionID: ourSessionID, ts: now, type: .evtSessionEnd
    ))
}

/// stop() 序列成功收尾后的 sessionEnd(reason:.stopped)——F6 rework 新增：上一轮 `stop()` 从未产出
/// 这个事件，只是单纯 `finish()` 掉 continuation，调用方完全看不到"会话是怎么结束的"这一 D1 11
/// 变体之一。`.stopped` 是 D2 `PurpleReason` 枚举里专门为这个场景准备的取值（上一轮代码从未使用过）。
func makeSessionEndEventForStop(ourSessionID: String, nextSeq: () -> Int) -> EventMessageUnion {
    let now = Date()
    let payload = SessionEndEventMessagePayload(reason: .stopped)
    return .sessionEnd(SessionEndEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: nextSeq(), sessionID: ourSessionID, ts: now, type: .evtSessionEnd
    ))
}

// MARK: - ⑧ 两个仍诚实标 unsupported 的变体：capabilityChanged / approvalBufferResolved

/// evt.capability_changed 的构造函数——**本轮仍未接入任何真实触发路径，是诚实登记的 unsupported
/// 变体（不是遗漏）**。D1 INV-4 原文（~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md）
/// 明确写着"能力变更的感知路径仍是内核 RPC 报错(被动发现)+我方 Server 能力开关 override(主动决策)"
/// ——即这个事件从设计上就不是 kernel 主动 push 的，而是适配器自己在两种情况下合成：①调用某个方法
/// 时收到一个"因为能力不支持"形状的 RPC 拒绝（被动发现，需要先有一版 baseline capabilities 才谈得上
/// "变了"）；②运维/我方 Server 主动切换某个能力开关（主动决策）。这两条路径都依赖 `capabilities()`
/// 方法本身已经落地（本轮仍是 TODO 桩，见 KernelClient.swift 头注释），因此本函数只证明 D2
/// payload 在类型层面能正确构造，未被任何 handleIncoming 分支调用。
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

/// evt.approval_buffer_resolved 的构造函数——**本轮仍未接入任何真实触发路径，是诚实登记的
/// unsupported 变体（不是遗漏）**。D1 §6.2"pending #2 缓冲策略"要求适配器自己维护一个"当前
/// session 是否已有一条 pending 审批、第二条到达时先本地缓冲、缓冲期超时或队列溢出时才终态化"的
/// 小状态机；respondApproval() 本身在本轮仍是 TODO 桩（见 KernelClient.swift 头注释），这个本地
/// 缓冲状态机自然也未实现——因此没有任何代码路径会产生 reqID/reason(buffered_timeout|
/// queue_overflow) 这两个字段的真实值。已用真实探针核实：openclaw 原生 `session.approval`
/// phase:"terminal" 的 reason 词表（user/timeout/malformed-verdict/no-route/run-aborted/
/// gateway-restart/storage-corrupt）与 D1 这里要求的词表完全不相交，说明这条事件本质上是纯适配器
/// 内部状态机的产物，不是"翻译 openclaw 已有的某个 wire 事件"就能解决的——留给 respondApproval()
/// 落地时一并实现。
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
    var counter = 0
    let nextSeq: () -> Int = { counter += 1; return counter }
    return mapOpenclawSessionMessageToKernelEvents(payload, ourSessionID: ourSessionID, runIDHint: nil, nextSeq: nextSeq).first
}
