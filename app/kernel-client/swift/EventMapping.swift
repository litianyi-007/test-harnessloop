// openclaw `session.message` 事件 -> D2 EventMessageUnion（11 变体）映射。
//
// 现状诚实说明：openclaw 的 `session.message` payload 形状是运行时组装出来的
// （recipe §3 引用 `kernels/openclaw/src/gateway/server-session-events.ts:245-262`
// ——"这段是运行时组装逻辑，不是独立 typebox schema"），本轮 L1 闭环没有触发任何真实
// `sessions.send`（见 recipe §4 与 KernelClient.swift 的 send() TODO 桩），因此这条映射路径在
// 本轮 live 闭环里从未被真实 openclaw 数据驱动过、只能先写出"能想到的最常见形状"。
//
// 只覆盖一种最容易辨认的形状——`message.role` + `message.text`/`message.content` 的文本增量，
// 映射到 D2 MessageDeltaEventMessage（EventMessageUnion.messageDelta）。其余情况（工具调用/
// 工具结果/思考过程/审批请求/回合结束/会话结束/能力变更/操作完成/审批缓冲终态化，共 9 类）本轮
// 一律返回 nil，由调用方原样打印 raw 帧 + 标注 TODO——这是诚实的范围声明，不是遗漏：完整的
// openclaw -> D2 事件字段级适配是 SG-5"完整 openclaw→D2 事件适配"的工作范围，需要先拿到真实
// send() 产生的样本才能定案每种事件的判别规则,本轮不能假装已经做完。

import Foundation

func mapOpenclawSessionMessageToKernelEvent(_ payload: JSONObject, ourSessionID: String) -> EventMessageUnion? {
    guard let message = payload["message"] as? JSONObject else { return nil }

    if let role = message["role"] as? String,
       let text = (message["text"] as? String) ?? (message["content"] as? String) {
        let seq = (payload["messageSeq"] as? Int) ?? 0
        let deltaPayload = MessageDeltaEventMessagePayload(
            delta: text,
            index: 0,
            role: Role(rawValue: role) ?? .assistant
        )
        let event = MessageDeltaEventMessage(
            direction: .event,
            payload: deltaPayload,
            runID: nil,
            sentAt: Date(),
            seq: seq,
            sessionID: ourSessionID,
            ts: Date(),
            type: .evtMessageDelta
        )
        return .messageDelta(event)
    }

    // TODO（SG-5）：tool_call / tool_result / thinking / approval_request / turn_complete /
    // session_end / capability_changed / operation_completed / approval_buffer_resolved 这
    // 9 类事件本轮均未映射，返回 nil 交给调用方原样打印 + 标注 TODO。
    return nil
}
