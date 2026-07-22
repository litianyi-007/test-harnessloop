// 共享的『叶子类型』注册表——Swift/C# 两个 codegen 脚本共用。
//
// 背景（详见 ../../CODEGEN-FINDINGS.md 的判别联合坍缩发现）：quicktype 对 JSON Schema `oneOf`
// 判别联合会做『结构相容即合并』的类型统一（unifyClasses），当 oneOf 分支之间共享大量同名字段
// （我们的 D2 消息恰好如此：sentAt/direction/type/id/sessionId 等 envelope 字段所有分支都有）时，
// quicktype 会把所有分支合并成一个『每个字段都可选』的单一结构，判别联合荡然无存——`combineClasses`
// 推断开关对此无效（该合并发生在 oneOf 解析阶段，不是后续的 class-combining 图重写阶段）。
// 反之，若把每个具名类型作为独立的 top-level 分别喂给 quicktype（不经过它自己解析 oneOf），
// 哪怕结构高度相似（如 RejectionFailure/ProtocolFailure/BillingQueryFailure 都是 {code,detail?}），
// quicktype 也能正确保留为互不相干的独立类型——这是本文件枚举『叶子类型』（非 oneOf 本身）作为
// 独立 top-level 逐个喂给 quicktype 的依据。
//
// 因此本文件只列出『非顶层 oneOf』的具名类型（8 个方法的 request 消息、11 个事件消息、
// UnknownResponseMessage、以及只被 response oneOf 分支引用、若不显式列出就不会被自动生成的
// result/failure 叶子 payload）——4 类顶层判别联合（RequestMessage/ResponseMessage/EventMessage/
// Message）与 8 个方法各自的 *ResponseMessage（oneOf 判别 result/failure）**刻意不在此列**，
// 由各语言 generate-*.mjs 脚本手工/半自动组装判别联合包装类型，见 CODEGEN-FINDINGS.md。

export const leafTypes = [
  // ---- 8 个方法的 request 消息（allOf 合并，非 oneOf，可放心整体喂给 quicktype） ----
  { schema: 'methods/create-session.schema.json', def: 'CreateSessionRequestMessage' },
  { schema: 'methods/send.schema.json', def: 'SendRequestMessage' },
  { schema: 'methods/subscribe.schema.json', def: 'SubscribeRequestMessage' },
  { schema: 'methods/interrupt.schema.json', def: 'InterruptRequestMessage' },
  { schema: 'methods/stop.schema.json', def: 'StopRequestMessage' },
  { schema: 'methods/respond-approval.schema.json', def: 'RespondApprovalRequestMessage' },
  { schema: 'methods/capabilities.schema.json', def: 'CapabilitiesRequestMessage' },
  { schema: 'methods/query-billing.schema.json', def: 'QueryBillingRequestMessage' },

  // ---- 11 个事件消息（allOf 合并，非 oneOf） ----
  { schema: 'events/message-delta.schema.json', def: 'MessageDeltaEventMessage' },
  { schema: 'events/thinking.schema.json', def: 'ThinkingEventMessage' },
  { schema: 'events/tool-call.schema.json', def: 'ToolCallEventMessage' },
  { schema: 'events/tool-result.schema.json', def: 'ToolResultEventMessage' },
  { schema: 'events/approval-request.schema.json', def: 'ApprovalRequestEventMessage' },
  { schema: 'events/error.schema.json', def: 'ErrorEventMessage' },
  { schema: 'events/turn-complete.schema.json', def: 'TurnCompleteEventMessage' },
  { schema: 'events/session-end.schema.json', def: 'SessionEndEventMessage' },
  { schema: 'events/capability-changed.schema.json', def: 'CapabilityChangedEventMessage' },
  { schema: 'events/operation-completed.schema.json', def: 'OperationCompletedEventMessage' },
  { schema: 'events/approval-buffer-resolved.schema.json', def: 'ApprovalBufferResolvedEventMessage' },

  // ---- res.unknown（allOf 合并，本身不是 oneOf，见 methods/unknown-response.schema.json $comment） ----
  { schema: 'methods/unknown-response.schema.json', def: 'UnknownResponseMessage' },

  // ---- 只被 response oneOf 分支引用、需显式列出才会生成的叶子 result payload ----
  { schema: 'methods/create-session.schema.json', def: 'CreateSessionResultPayload' },
  { schema: 'methods/send.schema.json', def: 'SendResultPayload' },
  { schema: 'methods/interrupt.schema.json', def: 'InterruptResultPayload' },
  { schema: 'methods/stop.schema.json', def: 'StopResultPayload' },
  { schema: 'methods/query-billing.schema.json', def: 'QueryBillingResultPayload' },
  { schema: 'common/capability-descriptor.schema.json', def: 'CapabilityDescriptorPayload' },

  // ---- 三层失败类型（D2 v3 §6）——刻意作为 3 个独立 top-level 喂给 quicktype，
  //      验证『结构相似但语义不同』的类型在不经过 oneOf 解析时能否保持独立（见 CODEGEN-FINDINGS.md）。
  { schema: 'common/errors.schema.json', def: 'RejectionFailure' },
  { schema: 'common/errors.schema.json', def: 'ProtocolFailure' },
  { schema: 'common/errors.schema.json', def: 'BillingQueryFailure' },

  // ---- 精确空对象（root schema 本身就是该类型，无 $defs 包装） ----
  { schema: 'common/empty-payload.schema.json', def: null },
];
