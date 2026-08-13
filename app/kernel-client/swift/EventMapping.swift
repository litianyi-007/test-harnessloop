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
//      对抗审 codex 指出会串号（两个 toolCall 交错、旧缓存残留时误配）。openclaw 源码坐实：exec
//      审批还会经由一条 `agent` 事件广播 `data.approvalId`+`data.toolCallId`（均为该次审批的
//      **准确值**，不是猜测），且这条 `agent` 事件的外层 `payload.runId` 由 `enrichAgentEvent`
//      统一盖章、可靠。**rounds/0016 订正（live 实测）**：这条关联帧有**两种**形状，取决于 exec
//      工具是否内联等待网关审批（`bash-tools.exec-host-gateway.ts:414-428`
//      `shouldAwaitGatewayApprovalInline()`）——
//        - 不内联（直接返回 `approval-pending` 工具结果）：
//          **`agent(stream:"approval", data.phase:"requested")`**
//          （`embedded-agent-subscribe.handlers.tools.ts:1665-1699` `emitAgentApprovalEvent`）。
//        - 内联等待（webchat 等 native approval channel 走这条，**我们的 mac 壳就是这条**）：
//          **`agent(stream:"lifecycle", data.phase:"waiting-approval")`**
//          （`bash-tools.exec-host-gateway.ts:1085-1091`）。真实冻结帧见
//          `rounds/0015/evidence/live/raw/approval-frames-extract.json`。
//      本文件改为：调用方（OpenclawGatewayKernelClient）在收到**上述任一条** `agent` 帧时，把
//      `data.approvalId -> data.toolCallId` 的精确映射存进一个按 approvalId 为键的缓存（见
//      `recordAgentApprovalAssociation`）；`session.approval`(phase:"pending") 到达时用
//      `approval.id` 去查这个缓存，而不是"最近一次 toolCall"。两个交错的 pending 审批不会再互相
//      踩，见 `mapOpenclawSessionApprovalToKernelEvent` 的新签名 `toolCallIDForApprovalID`。
//   4. `agent` 的 `stream:"lifecycle"` 在 `data.phase` 为 "end"/"error" 时是一次 run 的终态信号
//      （`phase:"waiting-approval"` 同样走 lifecycle，但那是上面第 3 条的审批关联帧，不是终态），
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
// `canImport` 门卫理由见 KernelClient.swift 同名注释——这个文件也被 ci.yml 的 flat swiftc
// parity-runner 步骤直接编译，那条路径下没有独立的 D2Generated module。
#if canImport(D2Generated)
import D2Generated
#endif

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
            // rounds/0012 ①' C 方案：messageID 取自本函数入参 `payload`（session.message 事件的
            // 外层 payload，与 `message` 同级）的 `messageId` 键——**不是** `message["messageId"]`，
            // `message` 对象本身没有任何标识字段（见 D2 schema events/message-delta.schema.json
            // 新增字段的 description，以及 rounds/0012 evidence/item1-mechanism-localization.md
            // §2 的实测坐实）。缺失时诚实置 nil（不编造），调用方（SessionStore）据此决定分组回退
            // 策略。这是本函数本轮唯一的行为变化，其余映射逻辑不变。
            let messageID = jsonString(payload["messageId"])
            let deltaPayload = MessageDeltaEventMessagePayload(delta: text, index: index, messageID: messageID, role: .assistant)
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
    forceResolvedApprovals: [String]?,
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
    // M3（D1 §6.2，本轮新增）：调用方（`OpenclawGatewayKernelClient.handleAgentEvent`）只在这个 run
    // 恰好也是当前 stop() 正在处理、且确实强制 deny 过审批的那个 run 时才会传非 nil 值——这是罕见的
    // "aborted:false 分支恰好赶上了 stop() 的 force-deny 竞态窗口"场景（见调用点文档注释），绝大多数
    // 正常回合结束都会传 nil，不是本函数自己判断的。
    let turnPayload = TurnCompleteEventMessagePayload(
        degraded: nil, forceResolvedApprovals: forceResolvedApprovals, stopReason: stopReason, usage: usage
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
///
/// **rounds/0020**：新增 `operationKind` 参数（此前硬编码 `.stop`）——`interrupt()`（D1 §2.4，
/// `mode:"cancel"`）与 `stop()` 共享同一个 `OpenclawGatewayKernelClient.pendingStops` 等待/去重机制
/// （见该文件 `PendingStop.operationKind` 的文档注释），这个函数是那套机制观察到真实 aborted
/// lifecycle 帧之后、实际构造 `operation_completed`/`turn_complete` 事件的地方——若继续硬编码
/// `.stop`，interrupt() 触发的这次终态会被事件流的观察者误读成一次 stop 操作。调用方
/// （`OpenclawGatewayKernelClient.handleAgentEvent`）按 `pendingForRun.operationKind` 传入真正的
/// 发起者。
///
/// **T-113 rework（grok 对抗评审 item 1）**：`operationID`/`operationKind` 改为 `String?`/
/// `OperationKind?`——上一段留的"唯一的例外是 unowned 防御性兜底分支……理论上不会出现"这句判断
/// 本身就是本次要修的缺陷根源，**已被实拍证伪**：`interrupt()` 顶部覆盖全部出路的 `defer` 会在函数
/// 返回前把 `pendingStops[sessionID]` 整条同步摘掉（中间不存在任何 `await`），openclaw 对同一次
/// abort 常发的第二条收尾帧（`phase:"error",aborted:true,"This operation was aborted"`，真实样本见
/// 本文件上方注释）到达时，`pendingStops[ourSessionID]` 已经是 nil——unowned 兜底分支因此在
/// interrupt() 成功路径上是**可预期**的，不是"理论上"。此前它把 `operationKind` 硬编码成 `.stop`
/// 传进来，于是这里画出一条冒充 `stop()` 的 `operation_completed`（rounds/0020
/// `evidence/shots/README.md` 02 号截图实拍钉住："[操作] stop 已完成：outcome=aborted_effect_unknown"
/// ——用户从未点过 stop）。
///
/// 修法：调用方对"无主"（没有匹配上任何 pendingStop）的帧传 `operationID: nil, operationKind: nil`；
/// 本函数据此**不构造/不返回** `operationCompleted` 事件——`OperationKind`（D2 生成类型，
/// `app/generated/swift/D2.swift:3472-3475`）只有 `.interrupt`/`.stop` 两个取值，没有第三个"不知道是
/// 谁"的选项，无主帧无论标成哪一个都是在冒充一次没有身份信息支撑的用户操作，而
/// `SessionStore.handleOperationCompleted` 是 `evt.operation_completed` 唯一的渲染点，会把编造值
/// 直接画成系统行。但**仍然返回** `turnComplete(stopReason:.cancelled)`——它不携带 `operationKind`
/// 这类身份声明，只诚实反映"这个 run 确实被 abort 了"，这件事从 `data.aborted==true` 就能确定，与
/// 是谁发起的无关。保留它是为了不退化掉这个兜底分支最初存在的理由：真正"无主"的场景（例如同一
/// session 被另一个客户端/来源摘掉了 run，我们自己从未登记过 pendingStop）如果连 turnComplete 都不
/// 发，等待中的 UI 会永远转圈——`SessionStore.handle` 的 `.turnComplete` 分支会清 `isWaitingForReply`
/// 且不产出任何系统行，是这里能给出的最诚实的信号。
func mapOpenclawAgentLifecycleToAbortTerminalEvents(
    _ data: JSONObject,
    ourSessionID: String,
    runID: String,
    operationID: String?,
    originTS: Date,
    cachedUsage: (input: Int, output: Int)?,
    forceResolvedApprovals: [String]?,
    operationKind: OperationKind?,
    nextSeq: () -> Int
) -> [EventMessageUnion] {
    var events: [EventMessageUnion] = []

    // seq 分配顺序刻意保持"先 operationCompleted、后 turnComplete"（与修前逐字节相同）——只在真正
    // 构造并返回 operationCompleted 时才为它消耗一个 nextSeq() 调用，`operationID == nil` 的无主
    // 路径不再为一个不会被返回的事件白占一个 seq 值。
    if let operationID, let operationKind {
        let phase = jsonString(data["phase"])
        let outcome: PayloadOutcome = phase == "end" ? .succeeded : .abortedEffectUnknown
        let detail = jsonString(data["error"])
        let opPayload = OperationCompletedEventMessagePayload(
            affectedRunID: runID, detail: detail, newRunID: nil,
            operationID: operationID, operationKind: operationKind, outcome: outcome
        )
        events.append(.operationCompleted(OperationCompletedEventMessage(
            direction: .event, payload: opPayload, runID: runID,
            sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtOperationCompleted
        )))
    }

    let usage = cachedUsage.map { Usage(inputTokens: $0.input, outputTokens: $0.output) }
    // M3（D1 §6.2，本轮新增）：`forceResolvedApprovals` 由调用方（`stop()` 铸造的 `PendingStop.
    // forceResolvedApprovalReqIDs`，见 `OpenclawGatewayKernelClient.forceDenyPendingApprovalsBeforeStop`）
    // 传入——这个 run 被 stop() 强制取消之前，如果有 pending 审批被强制 deny 掉，reqId 就会出现在
    // 这里；上一轮这里硬编码 nil，是 SG-8.7 形式化 parity 复核揪出的缺口（D1 §6.2 M3 定序完全没有
    // 落地）。无主路径（见上）调用方恒传 nil——不存在"这次强制 deny 过谁"的信息可以塞。
    let turnPayload = TurnCompleteEventMessagePayload(
        degraded: nil, forceResolvedApprovals: forceResolvedApprovals, stopReason: .cancelled, usage: usage
    )
    events.append(.turnComplete(TurnCompleteEventMessage(
        direction: .event, payload: turnPayload, runID: runID,
        sentAt: Date(), seq: nextSeq(), sessionID: ourSessionID, ts: originTS, type: .evtTurnComplete
    )))

    return events
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

/// evt.approval_buffer_resolved 的构造函数。
///
/// **rounds/0015 返工①：本函数已接入真实触发路径，此前这里的整段"仍未接入/留给 respondApproval()
/// 落地时一并实现"的注释是陈旧的（连同它里面"respondApproval() 本身在本轮仍是 TODO 桩"那句——
/// respondApproval() 在 rounds/0015 A 块就已经实现，见 `OpenclawGatewayKernelClient.respondApproval`
/// 的四道关卡），本轮一并订正。**
///
/// 现在的唯一调用点是 `OpenclawGatewayKernelClient.emitApprovalBufferResolved`，它有两个上游：
///  - `queue_overflow`：`emitApprovalRequestIfPossible` 的准入判定发现 FIFO 缓冲队列已满
///    （深度 `approvalBufferDefaultDepth`，D1 §6.2 要求"实现选定一个有限值并文档化"，取值依据见
///    该常量的文档注释），按 D1 的 fail-closed 取向直接对新到的请求发强制 deny；
///  - `buffered_timeout`：`handleApprovalTerminalSignal` 观察到一条**仍在缓冲队列里、从未被提升
///    为 active pending**的请求被内核判定超时（openclaw `session.approval(phase:"terminal")` 的
///    `approval.status == "expired"`，其 reason 由 schema 收窄为唯一取值 `timeout`，见
///    `packages/gateway-protocol/src/schema/approvals.ts:59-60`）。
///
/// 此前那段注释里关于"词表不相交"的观察本身**没错、也仍然成立**：openclaw 原生 terminal reason
/// 词表（user/timeout/malformed-verdict/no-route/run-aborted/gateway-restart/storage-corrupt）与
/// 本事件的两值词表（buffered_timeout/queue_overflow）确实不相交——这条事件不是"翻译某个 wire
/// 事件"，而是**适配器自己的缓冲状态机**的产物。错的是从这个观察推出的"所以现在没法实现"：状态机
/// 本来就该由适配器实现（D1 §6.2 末句原文明写"这是**运行时并发分支**，不是 UI 呈现优化——即使调用
/// 方从不构建『审批队列』UI，适配器也必须实现上述缓冲/提升/溢出规则"）。terminal 词表在这里的真实
/// 作用是**输入信号**（`expired` ⟺ TIMED_OUT_DENY），不是输出映射。
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

// MARK: - rounds/0016（T-096 第 1、4 项）：审批失败态/超时态的 evt.error 出口
//
// **为什么是 `evt.error` 而不是新造一个事件**：D2 的 `KernelErrorCode`
// （`app/contracts/d2/schema/common/errors.schema.json:10-18`，生成码 `PayloadCode`）是一个
// **七值封闭枚举**，其中 `approval_timeout` 是一个**字面对应**本场景的契约稳定取值——不是"找一个
// 差不多的坑位塞进去"，是这个枚举本来就为审批超时留了一个坑位。这一点与 ④ 里
// `ApprovalBufferResolvedEvent.reason` 那个两值词表的情形**恰好相反**：那里确实没有任何取值能
// 表达 `cancelled`/`denied`，所以那里选择了如实不上报；这里有字面对应，就该用。
//
// 两个构造函数各自的触发点：
//  - `makeApprovalTimeoutErrorEvent`：**active pending** 审批被内核判超时
//    （`session.approval(phase:"terminal")` + `status:"expired"`，其 reason 由 openclaw schema
//    收窄为唯一取值 `timeout`）。这是 T-096 第 4 项要求的"active terminal 驱动 UI 先清旧卡"的
//    唯一契约内通道——修前这条内核信号只在适配器内部驱动 FSM，一个字节都没传给调用方，UI 因此
//    会把一张已死的卡片一直挂在队头，把随后**提升上来的那条**挤到看不见的位置。
//  - `makeApprovalOverflowDenyUnconfirmedErrorEvent`：D1 §6.2 缓冲溢出的 fail-closed deny
//    **没有被内核确认**（T-096 第 1 项："失败不可吞掉，也不可提前宣称已自动拒绝"）。修前这条
//    失败只 `prettyPrint` 一行就吞掉了，而调用方在此之前**已经**收到了一条
//    `approval_buffer_resolved(queue_overflow)`——即"提前宣称已自动拒绝"。现在那条事件只在
//    `applied:true + status:denied` 时才发，失败走这里如实上报。
//    code 取 `.unknown`（这一条**没有**字面对应的枚举取值，`approval_timeout` 是超时专用，拿它
//    冒充会把"deny 没打成"谎报成"它超时了"——如实标注为无对应，同本文件既有的 seq-gap 处置）。

/// active pending 审批被内核判超时（TIMED_OUT_DENY）。`recoverable: .run`——超时只让这一次 tool
/// call 被 fail-closed 拒绝，run 自身仍在继续（agent 会收到"被拒绝"的工具结果并往下走），
/// 不代表整个 session 失效。`nativeCode` 放 openclaw 自己的 terminal reason 字面值（`"timeout"`），
/// 按 D2 该字段的契约注释仅供调试，UI 不得对其分支判断。
func makeApprovalTimeoutErrorEvent(
    reqID: String,
    openclawReason: String?,
    ourSessionID: String,
    runID: String?,
    seq: Int
) -> EventMessageUnion {
    let now = Date()
    let payload = ErrorEventMessagePayload(
        code: .approvalTimeout,
        message: "审批 \(reqID) 已被内核判定超时（fail-closed 拒绝），该请求不再等待人工裁决",
        nativeCode: openclawReason,
        recoverable: .run
    )
    return .error(ErrorEventMessage(
        direction: .event, payload: payload, runID: runID,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtError
    ))
}

/// 缓冲溢出的强制 deny 未被内核确认。message 里**逐字带上实际观察到的失败形态**（RPC 错误文本 /
/// `applied:false` + 终态快照 / `applied:true` 但终态非 denied），这样调用方看到的是"发生了什么"
/// 而不是一句"失败了"。`recoverable: .run` 同上。
func makeApprovalOverflowDenyUnconfirmedErrorEvent(
    reqID: String,
    observedFailure: String,
    ourSessionID: String,
    seq: Int
) -> EventMessageUnion {
    let now = Date()
    let payload = ErrorEventMessagePayload(
        code: .unknown,
        message: "审批 \(reqID)：等待队列已满，适配器发起的自动拒绝**未被内核确认**（\(observedFailure)）"
            + "——这条请求在内核侧可能仍然 pending，不要当作已被拒绝",
        nativeCode: "queue_overflow_deny_unconfirmed",
        recoverable: .run
    )
    return .error(ErrorEventMessage(
        direction: .event, payload: payload, runID: nil,
        sentAt: now, seq: seq, sessionID: ourSessionID, ts: now, type: .evtError
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

// MARK: - rounds/0014 ⑦ chat.history 消息解析（`SessionHistoryProviding` 用，见 KernelClient.swift
// `HistoryRecord`/`SessionHistoryProviding` 协议文档注释）
//
// openclaw `chat.history` RPC 响应 `messages[]` 数组里的单条记录，与 `session.message` wire 事件里
// `payload.message`（见①的 `mapOpenclawSessionMessageToKernelEvents`）是同一套 openclaw
// "显示消息"投影形状：`{role: string, content: string | [{type:"text",text:string}, ...],
// __openclaw?: {id, seq, ...}}`（源码 grounding：
// kernels/openclaw/src/gateway/chat-display-projection.ts:41-43 的 `RoleContentMessage` 类型 +
// 同文件多处 `message["__openclaw"]` 读取/写入）。但这是**历史**消息，不是 assistant-only 的流式
// delta——role 可以是 "user"，也可能是①从未处理过的其它取值（system/工具相关标记等）——不能照抄
// ①"非 assistant 直接丢弃整条"的策略，历史消息本来就该原样呈现双方（乃至更多角色）的完整对话。

/// text 抽取规则与 `app/apps/AgentShell/repro/reconcile-history.py` 的
/// `extract_assistant_text()`（本轮任务书唯一点名要求参考的既有对账逻辑）保持一致：`content` 是
/// 纯字符串就直接用；是数组就只拼接 `type=="text"` 的 block（thinking/toolCall 等其它 block 类型
/// 被忽略，不混进正文，与①对 `session.message` 的 block 分类判别同一套 `type` 字面量集合但抽取
/// 目的不同——①要把每个 block 拆成独立事件，这里只要拼出一段可读全文）；两者都不是就诚实返回空
/// 串，不臆造。
func extractHistoryMessageText(from content: Any?) -> String {
    if let text = jsonString(content) { return text }
    if let blocks = jsonArray(content) {
        return blocks.compactMap { block -> String? in
            guard let obj = jsonObject(block), jsonString(obj["type"]) == "text" else { return nil }
            return jsonString(obj["text"])
        }.joined()
    }
    return ""
}

/// 把 `chat.history` `messages[]` 里的一条原始 JSON 记录解析成 `HistoryRecord`。
///
/// 宽容度刻意与 wire 事件解析（①「role 非 assistant 就静默丢弃整个事件」/ D1 事件流协议签名不带
/// `throws` 时把错误封进 stream）不同：`raw` 不是 JSON 对象就返回 nil（一条格式错误的记录被跳过，
/// 不拖垮整批历史的显示——历史回填是只读展示，`OpenclawGatewayKernelClient.fetchFullHistory` 用
/// `compactMap` 调用本函数，nil 直接从结果里消失，不中止整页解析）；role 缺失/非字符串时退化为
/// "unknown" 而不是跳过整条记录——一条 role 异常的历史消息仍然值得展示给用户看（配合
/// `SessionStore` 侧对未知 role 的兜底渲染），不应该让它从历史里悄悄消失。
func parseHistoryRecord(_ raw: Any) -> HistoryRecord? {
    guard let obj = jsonObject(raw) else { return nil }
    let role = jsonString(obj["role"]) ?? "unknown"
    let text = extractHistoryMessageText(from: obj["content"])
    let meta = jsonObject(obj["__openclaw"])
    return HistoryRecord(id: jsonString(meta?["id"]), seq: jsonInt(meta?["seq"]), role: role, text: text)
}

// MARK: - ⑦ 审批决策映射（rounds/0015 B 块）：D2 四值 <-> openclaw 三值，显式写死
//
// **本节所在文件的选择不是随意的**：`.github/workflows/ci.yml` 的「Swift golden parity runner」
// 步骤用裸 `swiftc` **逐个列出**参与编译的文件（D2.swift / DiscriminatedUnions.swift /
// KernelClient.swift / OpenclawWire.swift / EventMapping.swift / OpenclawGatewayKernelClient.swift
// + fixtures runner 四个），`ci.yml` 不在本轮可改范围内。因此 `OpenclawGatewayKernelClient`
// 依赖的任何新符号都必须落在这份既有清单里的某个文件中——新建 `ApprovalDecisionMapping.swift`
// 会让 parity runner 直接编译失败。审批决策映射本身就是"openclaw wire 值 <-> D2 契约值"的转换，
// 与本文件既有的六节事件映射同类，放这里是语义正确的归属，不是为了迁就 CI 的将就。

/// openclaw 侧 `approval.resolve` 接受的决策取值——**权威来源**是 gateway protocol schema
/// `kernels/openclaw/packages/gateway-protocol/src/schema/approvals.ts:25-29`
/// `ApprovalDecisionSchema = Union([Literal("allow-once"), Literal("allow-always"), Literal("deny")])`
/// （`kernels/openclaw/src/mcp/channel-shared.ts:88` 的 `ApprovalDecision` 是同一组值的 MCP 侧
/// 副本）。**只有三个值，没有任何 session 语义的档位**——这一条是 `allow_session` 处置决策的事实基础，
/// 见 `openclawApprovalDecisionWire(forD2:)` 的文档注释。
///
/// 用枚举而不是裸字符串常量：raw value 写错一个字母（下划线/连字符是这里最容易犯的错）在
/// `makeApprovalResolveParams` 的单测里会立刻变红（rounds/0015 反证②），而散落的字符串字面量不会。
public enum OpenclawApprovalDecisionWire: String, CaseIterable {
    case allowOnce = "allow-once"
    case allowAlways = "allow-always"
    case deny = "deny"
}

/// D2 `ApprovalDecisionKindElement`（`app/generated/swift/D2.swift:1231-1236`，四值、**下划线**）
/// -> openclaw wire 决策（三值、**连字符**）。**逐个 case 显式写死，不做任何字符串替换**
/// （`replacingOccurrences(of:"_",with:"-")` 这类"看起来对"的通用变换恰好会把 `allow_session`
/// 变成一个 openclaw 根本不认识的 `allow-session`，而服务端对不认识的 decision 的处置是静默转 deny，
/// 见 `makeApprovalResolveParams` 文档注释——碰运气的代价是用户点"允许"却被拒，且没有任何报错）。
///
/// **`allow_session` 返回 nil（= 明确不支持），这是本轮的核心处置决策，依据有三条：**
///
/// 1. **结构性证明：openclaw 的每条审批请求的 `allowedDecisions` 里，永远不可能出现 session 语义的
///    值。** `allowedDecisions` 的 schema 是
///    `ApprovalAllowedDecisionsSchema = Type.Array(ApprovalDecisionSchema, {minItems:1, maxItems:3,
///    uniqueItems:true, contains: Literal("deny")})`（approvals.ts:75-82），元素类型就是上面那个
///    三值闭合联合。也就是说这不是"目前恰好没见过"，而是**协议层面不可能取到**——三处
///    presentation（exec/plugin/system-agent，approvals.ts:99/117/127）全部引用这同一个数组 schema
///    （system-agent 更是硬编码成 `["allow-once","deny"]` 的二元组）。任务书要求"先去核实每条请求的
///    `allowedDecisions` 里是否真的从不出现 session 语义的值"——核实结论是：从不，且由 schema 保证。
/// 2. **D1 契约明文要求同步拒绝，禁止静默降级。** `app/contracts/d2/schema/methods/
///    respond-approval.schema.json:34`（经 codegen 落到 D2.swift:1166-1167 `Decision` 的文档注释）
///    原文："由 capabilities().approvalDecisionKinds 门控，未声明支持时实现须**同步拒绝**
///    `unsupported_approval_decision`，**不得静默降级为 allow_once**。" 因此把 `allow_session`
///    降级成 `allow-once`（"反正都是允许"）是被契约明确禁止的——它会把"本次运行内一直允许"
///    悄悄变成"只允许这一次"，用户以为授了更大的权限，实际没有；反过来若降级成 `allow-always`
///    则是用户以为只授本会话、实际被永久持久化，那是更严重的**过度授权**。两个方向都不可接受。
/// 3. **UI 侧不提供该选项（任务书倾向，本轮采纳）**：`ApprovalPresentationSummary.allowedDecisions`
///    只会由 `d2ApprovalDecisionKind(forOpenclawWire:)` 从该条请求真实携带的 `allowedDecisions`
///    反向映射得出，而依据第 1 条那里面永远不会有 session 值——所以审批 UI 结构性地不可能渲染出
///    "本会话内允许"按钮，不给内核兑现不了的承诺。第 2 条的同步拒绝是**第二道防线**：即使将来有
///    别的调用方绕过 UI 直接用 `.allowSession` 调 `respondApproval()`，也会拿到明确的错误而不是
///    一个被悄悄改写的决策。
public func openclawApprovalDecisionWire(forD2 kind: ApprovalDecisionKindElement) -> OpenclawApprovalDecisionWire? {
    switch kind {
    case .allowOnce: return .allowOnce
    case .allowAlways: return .allowAlways
    case .allowSession: return nil // 见上：openclaw 无对应档位，明确不支持，不降级
    case .deny: return .deny
    }
}

/// 反向：openclaw wire 决策字符串 -> D2 `ApprovalDecisionKindElement`。用于把一条审批请求自带的
/// `presentation.allowedDecisions`（openclaw 原始字符串数组）翻译成 UI 可直接渲染的 D2 枚举。
/// 认不出的取值返回 nil——调用方（`ApprovalPresentationSummary`）把它们如实收进
/// `unmappedAllowedDecisions` 而不是静默丢弃，见那里的文档注释。
public func d2ApprovalDecisionKind(forOpenclawWire raw: String) -> ApprovalDecisionKindElement? {
    switch OpenclawApprovalDecisionWire(rawValue: raw) {
    case .allowOnce: return .allowOnce
    case .allowAlways: return .allowAlways
    case .deny: return .deny
    case nil: return nil
    }
}

/// `respondApproval()` 路径上、在**发出 RPC 之前**就能判定的失败，以及内核事后未兑现决策的判定。
/// 不复用 `KernelClientError`（KernelClient.swift）——那是"传输层"的补充错误通道，本类型是审批
/// 决策语义层自己的失败集合，独立命名更便于 UI 分别呈现（`SessionStore` 把它渲染成审批卡片上的
/// 行内错误，而不是整条事件流的红色横幅）。
public enum ApprovalDecisionError: Error, CustomStringConvertible {
    /// D2 有、openclaw 没有的决策档位（当前唯一成员：`allow_session`）。对应 D1 §9.1 同步拒绝码
    /// `unsupported_approval_decision`（D2.swift:4488）。
    case unsupportedApprovalDecision(requested: ApprovalDecisionKindElement, kernelSupports: [String])
    /// 决策本身 openclaw 认识，但**不在这条请求各自携带的 `allowedDecisions` 里**（最典型：
    /// `ask=always` 的实例上 `allowedDecisions` 只有 `["allow-once","deny"]`，此时 `allow_always`
    /// 就属于这一类）。这是本轮头号风险的拦截点，见 `makeApprovalResolveParams`。
    case decisionNotAllowedForThisRequest(reqID: String, requested: String, allowed: [String])
    /// D1 `Decision.updatedInput`（改写待执行内容后再放行）在 openclaw 的 `approval.resolve`
    /// 参数里没有任何承载位置——见 `makeApprovalResolveParams` 文档注释。
    case unsupportedUpdatedInput(reqID: String)
    /// 适配器本地不认识这个 reqId（从未产出过 / 已经终态化）。
    case approvalNotPending(reqID: String)
    /// reqId 存在，但属于另一个 session——跨会话回应是明确的调用错误，不代打。
    case approvalBelongsToAnotherSession(reqID: String, ownerSessionID: String, requestedSessionID: String)
    /// RPC 成功返回了，但内核记录的终态与我们请求的决策不一致——**这正是"静默变 deny"真正发生时
    /// 的样子**（`reason:"malformed-verdict"` 是它的签名）。绝不把这种情况当成功。
    case kernelDidNotHonorDecision(
        reqID: String, requested: String,
        observedStatus: String?, observedDecision: String?, observedReason: String?, applied: Bool?
    )

    // MARK: rounds/0016（T-096 第 2、3 项）——失败态与超时态各自的**显式**错误，不复用上面任何一个
    //
    // 三条都刻意独立成 case 而不是塞进 `approvalNotPending`：它们的处置方式互不相同（第一条要求
    // 调用方改选 deny 重试、第二条允许原样重试、第三条不允许任何重试），如果压成同一个错误码，
    // UI 只能给出一句含糊的"失败了"，调用方也无从判断"我现在还能做什么"。

    /// **`FORCE_DENY_PENDING_KERNEL_ACK`**（T-096 第 2 项）：这条审批曾被适配器发起过一次
    /// **强制 deny**（`stop()` 的 M3 定序 deny，或 D1 §6.2 缓冲溢出的 fail-closed deny），而内核
    /// **从未确认**（RPC 抛错 / `applied:false` / 终态不是 denied）。此时这条审批在内核侧的真实状态
    /// **未知**——最坏情况它仍然 pending，一次"允许"会让一条适配器已经决定拒绝的命令真的执行。
    /// 因此这个持久态下**只允许幂等的 deny 重试**，任何 allow 档位一律同步拒绝。
    case forceDenyPendingKernelAck(reqID: String, requested: String, observedFailure: String)
    /// `approval.resolve` 的**有界等待**到期（T-096 第 3 项）。修前这条 RPC 是无界 await：网关不回
    /// 应答就永久挂起，in-flight 槽位随之永久占位，`stop()` 的 drain 收敛条件（"无在途 resolve"）
    /// 也就永远不成立。到期后如实抛出——审批在内核侧的状态未知，不谎报成功也不谎报失败。
    case approvalResolveTimedOut(reqID: String, waitedMS: Int)
    /// 在这条 `approval.resolve` 往返途中，**内核自己**给出了这条审批的权威终态
    /// （`session.approval(phase:"terminal")`，典型是 `status:"expired"/reason:"timeout"`）。
    /// 内核的终态是权威的，我们这次在途决议已经不可能被兑现——立即结束这个 in-flight（不等它的
    /// 响应，那个响应可能永远不来），并如实告知调用方终态是什么。
    case approvalTerminatedByKernelWhileResolving(reqID: String, status: String?, reason: String?)

    public var description: String {
        switch self {
        case .unsupportedApprovalDecision(let requested, let supports):
            return "unsupported_approval_decision: 决策 '\(requested.rawValue)' 在 openclaw 侧没有对应档位"
                + "（内核仅支持 \(supports.joined(separator: "/"))）——按 D1 §2.6 同步拒绝，不静默降级"
        case .decisionNotAllowedForThisRequest(let reqID, let requested, let allowed):
            return "决策 '\(requested)' 不在审批 \(reqID) 自带的 allowedDecisions \(allowed) 内——"
                + "已在客户端拦截；若发给服务端会被 forceMalformedDeny 静默改写成 deny"
        case .unsupportedUpdatedInput(let reqID):
            return "审批 \(reqID)：openclaw approval.resolve 无法承载 Decision.updatedInput"
                + "（params schema 是 closedObject{id,kind,decision}），拒绝静默丢弃改写内容"
        case .approvalNotPending(let reqID):
            return "approval_not_pending: 审批 \(reqID) 不在本适配器的 pending 表内（从未产出，或已终态化）"
        case .approvalBelongsToAnotherSession(let reqID, let owner, let requested):
            return "审批 \(reqID) 属于 session \(owner)，不是 \(requested)——拒绝跨会话回应"
        case .kernelDidNotHonorDecision(let reqID, let requested, let status, let decision, let reason, let applied):
            return "审批 \(reqID)：请求决策 '\(requested)'，但内核记录的终态是 status=\(status ?? "nil")"
                + " decision=\(decision ?? "nil") reason=\(reason ?? "nil") applied=\(applied.map(String.init) ?? "nil")"
                + "——决策未被兑现，不当作成功"
        case .forceDenyPendingKernelAck(let reqID, let requested, let observedFailure):
            return "FORCE_DENY_PENDING_KERNEL_ACK: 审批 \(reqID) 的强制 deny 未被内核确认"
                + "（\(observedFailure)），内核侧真实状态未知——此状态下只允许幂等 deny 重试，"
                + "拒绝决策 '\(requested)'"
        case .approvalResolveTimedOut(let reqID, let waitedMS):
            return "审批 \(reqID)：approval.resolve 超过有界等待上限 \(waitedMS)ms 仍无应答——"
                + "已结束该 in-flight（不永久占位），内核侧状态未知，不当作成功也不当作已拒绝"
        case .approvalTerminatedByKernelWhileResolving(let reqID, let status, let reason):
            return "审批 \(reqID)：决议在途期间内核给出权威终态 status=\(status ?? "nil")"
                + " reason=\(reason ?? "nil")——本次决议不可能被兑现，已结束该 in-flight"
        }
    }
}

/// 构造一条 `approval.resolve` 的 params，并在构造过程中完成**全部发出前校验**。这是本轮 B 块
/// 「响应前必须在客户端侧校验」的唯一落点——`respondApproval()` 与任何未来的调用方都只能经由它拼参数。
///
/// **为什么必须在客户端拦（而不是"发出去让服务端把关"）**：openclaw
/// `gateway/server-methods/approval.ts:476-486` 的判定是
/// ```ts
/// const decisionAllowed = requestedDecision === "deny" ||
///   (requestedDecision !== null && record.presentation.allowedDecisions.includes(requestedDecision));
/// const kindMatches = resolveParams?.kind === record.presentation.kind;
/// const forceMalformedDeny = !validParams || !kindMatches || !decisionAllowed;
/// ```
/// 三者任一不满足 -> `forceMalformedDeny` -> `applyForcedDeny`，审批被**终态化为 denied**
/// （`reason:"malformed-verdict"`），而这条 RPC 本身**仍然返回 `ok:true`**。也就是说：用户点的
/// "允许"会静默变成"拒绝"，且**不可逆**（审批已经进终态，没有第二次机会重发正确的决策）。所以
/// 这里的校验不是防御性冗余，是唯一一次机会。
///
/// 三项逐条对应：
/// 1. **`allowedDecisions` 每条请求各自携带、不能硬编码**——参数 `allowedDecisionsFromRequest`
///    要求调用方传入这条审批**自己**的那一份（适配器把它随 `approval_request` 一起缓存在
///    `pendingApprovalsByReqID`）。实测同一个内核在不同配置下就会给出不同集合：`ask=always` 时是
///    `["allow-once","deny"]`（`resolveExecApprovalAllowedDecisions`，
///    `kernels/openclaw/src/infra/exec-approvals.ts:2805-2814`，因为"每次都问"与"永久放行"语义冲突），
///    其余情况才是三值全集 `DEFAULT_EXEC_APPROVAL_DECISIONS`。硬编码成任一个都会在另一种配置下出错。
/// 2. **`kind` 必须与该条请求的 `presentation.kind` 一致**——同样取自缓存的真实值
///    （"exec"/"plugin"/"system-agent"，openclaw 侧原始取值；**不能**用 D2 的 `KindElement` 反推，
///    那是个有损映射：`plugin` 与 `system-agent` 都被映射成 D2 的 `.tool`，见
///    `mapOpenclawSessionApprovalToKernelEvent`）。
/// 3. **params 必须恰好是 `{id, kind, decision}` 三个键**——`ApprovalResolveParamsSchema` 是
///    `closedObject`（`closed-object.ts`：`additionalProperties: false`），多一个键就 `!validParams`，
///    同样落进 `forceMalformedDeny`。所以这里返回的字典字面量刻意只有三项，且不接受调用方追加。
///
/// `Decision.updatedInput` 非 nil 时直接拒绝：openclaw 的 params 里没有承载位置，静默丢弃会让
/// "我改写了命令再放行"变成"原样放行原始命令"——这是比静默 deny 更危险的静默 allow。
/// `Decision.scope`/`.reason` 则是**可以**安全忽略的说明性字段（内核自己记录 resolver 归属与
/// `reason:"user"`，不接受客户端指定），忽略它们不改变任何一侧的执行语义，故不报错。
/// 返回 `(params, wire)` 两项而不是只返回 params：调用方在 RPC 返回后还要用 `wire` 去核对内核终态
/// 是否兑现了这次决策（`verifyApprovalResolveHonored`）。让本函数一并交出它已经算好的那个值，
/// 而不是让调用方再调一次映射函数——后者会在调用方那里留下一个**永远不可能命中**的 `guard ... else
/// { throw }` 分支（本函数已经保证映射成功了），那种假装可达的死分支既误导读者也无法被测试覆盖。
func makeApprovalResolveParams(
    reqID: String,
    openclawKind: String,
    decision: Decision,
    allowedDecisionsFromRequest: [String]
) throws -> (params: JSONObject, wire: OpenclawApprovalDecisionWire) {
    guard decision.updatedInput == nil else {
        throw ApprovalDecisionError.unsupportedUpdatedInput(reqID: reqID)
    }
    guard let wire = openclawApprovalDecisionWire(forD2: decision.outcome) else {
        throw ApprovalDecisionError.unsupportedApprovalDecision(
            requested: decision.outcome,
            kernelSupports: OpenclawApprovalDecisionWire.allCases.map(\.rawValue)
        )
    }
    guard allowedDecisionsFromRequest.contains(wire.rawValue) else {
        throw ApprovalDecisionError.decisionNotAllowedForThisRequest(
            reqID: reqID, requested: wire.rawValue, allowed: allowedDecisionsFromRequest
        )
    }
    // 恰好三个键，见文档注释第 3 条。
    return (["id": reqID, "kind": openclawKind, "decision": wire.rawValue], wire)
}

/// `approval.resolve` 返回后，判断内核是否**真的**兑现了我们请求的决策。
///
/// 响应体是 `ApprovalResolveResultSchema = {applied: Bool, approval: TerminalApprovalSnapshot}`
/// （approvals.ts:252-256）。终态快照四选一：`allowed`（带 `decision: allow-once|allow-always`）/
/// `denied`（`decision:"deny"`，`reason` ∈ user|malformed-verdict|no-route|storage-corrupt）/
/// `expired`（reason:timeout）/ `cancelled`（reason:run-aborted|gateway-restart）。
///
/// 判定规则：请求 deny 就必须看到 `denied`，请求任一 allow 档就必须看到 `allowed` **且**
/// `decision` 与我们发出的那个值逐字相等。后半句不是多余——`forceMalformedDeny` 之外，若将来内核
/// 把 `allow-always` 降级成 `allow-once` 落库，这里同样会揪出来。
///
/// 这是与 `makeApprovalResolveParams` 客户端前置校验**互补的第二道防线**：前者防我们自己发错，
/// 后者防"发对了但内核出于别的原因没兑现"（例如审批在 RPC 在途期间超时 -> `expired`）。任务书
/// "不得仅凭 exit 0 / 自述 success 采信"的纪律在这条 RPC 上的具体落地。
func verifyApprovalResolveHonored(reqID: String, requested: OpenclawApprovalDecisionWire, result: JSONObject) throws {
    let approval = jsonObject(result["approval"])
    let status = jsonString(approval?["status"])
    let decision = jsonString(approval?["decision"])
    let reason = jsonString(approval?["reason"])
    let applied = jsonBool(result["applied"])

    let honored: Bool
    switch requested {
    case .deny:
        honored = (status == "denied")
    case .allowOnce, .allowAlways:
        honored = (status == "allowed" && decision == requested.rawValue)
    }
    guard honored else {
        throw ApprovalDecisionError.kernelDidNotHonorDecision(
            reqID: reqID, requested: requested.rawValue,
            observedStatus: status, observedDecision: decision, observedReason: reason, applied: applied
        )
    }
}

// MARK: - ⑧ 审批呈现摘要（rounds/0015 C 块：审批 UI 需要的字段，从 D2 事件里提炼）

/// 审批 UI 要渲染的最小字段集合，从 `ApprovalRequestEventMessagePayload.payload`（`JSONAny`，
/// 内容是 openclaw 的 `approval.presentation` 原样包装，见
/// `mapOpenclawSessionApprovalToKernelEvent`）里提炼。
///
/// 不是 D1/D2 契约类型——D2 把 presentation 定义成"该 kind 下的不透明详情"（`JSONAny`），要在 UI 上
/// 显示"到底要执行什么命令"就必须有人负责把这坨不透明详情解释成具体字段。这件事放在 kernel-client
/// 层（而不是 `AgentShellCore`）：presentation 的字段形状是 **openclaw wire 知识**
/// （`ExecApprovalPresentationSchema` 等三个 schema），与本文件其余六节事件映射同源；放 UI 层会让
/// wire 知识泄漏进壳，且 `frame-replay-tests` 也更难直接覆盖。呼应 `HistoryRecord`（KernelClient.swift）
/// 的同一条先例："UI 层需要、D1/D2 无原生对应"的最小值类型由 kernel-client 提供。
public struct ApprovalPresentationSummary: Equatable {
    /// openclaw 原始 kind："exec" / "plugin" / "system-agent"。保留原值而不是用 D2 的 `KindElement`
    /// ——后者是有损的（plugin 与 system-agent 都落到 `.tool`）。
    public let openclawKind: String?
    /// exec 审批：待执行的命令全文（`ExecApprovalPresentationSchema.commandText`）。
    public let commandText: String?
    /// plugin / system-agent 审批：标题。
    public let title: String?
    /// plugin / system-agent 审批：说明文本。
    public let detailText: String?
    /// exec 审批的告警文本（如 heredoc/allowlist 计划不可用的提示）——**"请求原因"在 openclaw 的
    /// exec presentation 里没有独立字段**，这个 `warningText` 与 `host` 是仅有的两处上下文，如实
    /// 呈现，不编造一段"原因"。
    public let warningText: String?
    /// 执行宿主（"gateway"/"sandbox"/node 名）。
    public let host: String?
    /// 请求方 agent id。
    public let agentID: String?
    /// 这条请求**自己**允许的决策，已翻译成 D2 枚举供 UI 直接渲染按钮。顺序保持 openclaw 给出的原序。
    public let allowedDecisions: [ApprovalDecisionKindElement]
    /// `allowedDecisions` 里本适配器**认不出**的原始取值（当前 openclaw schema 下恒为空）。
    /// 如实保留而不是静默丢弃：将来内核新增决策档位时，UI 至少能显示"有一个我不认识的选项"，
    /// 而不是让它凭空消失、用户永远看不到一个本该可用的按钮。
    public let unmappedAllowedDecisions: [String]

    public init(
        openclawKind: String?, commandText: String?, title: String?, detailText: String?,
        warningText: String?, host: String?, agentID: String?,
        allowedDecisions: [ApprovalDecisionKindElement], unmappedAllowedDecisions: [String]
    ) {
        self.openclawKind = openclawKind
        self.commandText = commandText
        self.title = title
        self.detailText = detailText
        self.warningText = warningText
        self.host = host
        self.agentID = agentID
        self.allowedDecisions = allowedDecisions
        self.unmappedAllowedDecisions = unmappedAllowedDecisions
    }
}

/// 从一条 `evt.approval_request` 的 payload 提炼 `ApprovalPresentationSummary`。
///
/// `payload.payload` 是 `JSONAny`，其 `.value` 在 presentation 为 JSON 对象时就是 `[String: Any]`
/// （quicktype 生成的 `JSONAny` 解码规则）。取不到对象时返回一个全 nil / 空数组的摘要——UI 侧据此
/// 显示"这条审批没有可读详情"，而不是崩溃或伪造内容。
public func summarizeApprovalPresentation(_ payload: ApprovalRequestEventMessagePayload) -> ApprovalPresentationSummary {
    let presentation = jsonObject(payload.payload.value) ?? [:]
    let rawAllowed = (jsonArray(presentation["allowedDecisions"]) ?? []).compactMap { jsonString($0) }
    var mapped: [ApprovalDecisionKindElement] = []
    var unmapped: [String] = []
    for raw in rawAllowed {
        if let kind = d2ApprovalDecisionKind(forOpenclawWire: raw) {
            mapped.append(kind)
        } else {
            unmapped.append(raw)
        }
    }
    return ApprovalPresentationSummary(
        openclawKind: jsonString(presentation["kind"]),
        commandText: jsonString(presentation["commandText"]),
        title: jsonString(presentation["title"]),
        detailText: jsonString(presentation["description"]),
        warningText: jsonString(presentation["warningText"]),
        host: jsonString(presentation["host"]),
        agentID: jsonString(presentation["agentId"]),
        allowedDecisions: mapped,
        unmappedAllowedDecisions: unmapped
    )
}
