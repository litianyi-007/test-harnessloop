/**
 * 本文件由 codegen 自动生成，不要手工编辑。
 * 源：app/contracts/d2/schema/message.schema.json（+ 其 $ref 的 methods/*、events/*、common/*）
 * 生成命令：npm --prefix app/contracts/d2/codegen run gen:ts
 * 覆盖范围（本轮 PRE-②/SG-1 骨架，非全量）：见 message.schema.json 顶层 $comment 的 TODO 清单。
 * 仅供开发期 fixture 工具 / TS oracle 使用（D4 §1.4/§4.4），不进任何产品打包。
 */

/**
 * 部分覆盖（3/8），见本文件顶层 $comment TODO 清单。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageTODO`'s JSON-Schema
 * via the `definition` "RequestMessage".
 */
export type RequestMessage = CreateSessionRequestMessage | InterruptRequestMessage | RespondApprovalRequestMessage;
export type CreateSessionRequestMessage = RequestEnvelopeBase & {
  type: 'req.createSession';
  id: string;
  /**
   * 不适用——createSession 尚无 session 可寻址，见上方说明。
   */
  sessionId?: string;
  payload: CreateSessionRequestPayload;
};
export type InterruptRequestMessage = RequestEnvelopeBase & {
  type: 'req.interrupt';
  id: string;
  sessionId: string;
  payload: InterruptRequestPayload;
};
export type RespondApprovalRequestMessage = RequestEnvelopeBase & {
  type: 'req.respondApproval';
  id: string;
  sessionId: string;
  payload: RespondApprovalRequestPayload;
};
/**
 * 部分覆盖（3/8，另缺 res.unknown），见本文件顶层 $comment TODO 清单。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageTODO`'s JSON-Schema
 * via the `definition` "ResponseMessage".
 */
export type ResponseMessage =
  | (
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.createSession';
          id: string;
          sessionId?: string;
          result: CreateSessionResultPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.createSession';
          id: string;
          sessionId?: string;
          failure: RejectionFailure | ProtocolFailure;
        }
    )
  | (
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.interrupt';
          id: string;
          sessionId?: string;
          result: InterruptResultPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.interrupt';
          id: string;
          sessionId?: string;
          failure: RejectionFailure | ProtocolFailure;
        }
    )
  | (
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.respondApproval';
          id: string;
          sessionId?: string;
          result: EmptyPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.respondApproval';
          id: string;
          sessionId?: string;
          failure: RejectionFailure | ProtocolFailure;
        }
    );
/**
 * 部分覆盖（5/11），见本文件顶层 $comment TODO 清单。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageTODO`'s JSON-Schema
 * via the `definition` "EventMessage".
 */
export type EventMessage =
  | MessageDeltaEventMessage
  | ToolCallEventMessage
  | ApprovalRequestEventMessage
  | CapabilityChangedEventMessage
  | OperationCompletedEventMessage;
export type MessageDeltaEventMessage = EventEnvelopeBase & {
  type: 'evt.message.delta';
  payload: MessageDeltaPayload;
};
export type ToolCallEventMessage = EventEnvelopeBase & {
  type: 'evt.tool_call';
  payload: ToolCallPayload;
};
export type ApprovalRequestEventMessage = EventEnvelopeBase & {
  type: 'evt.approval_request';
  runId: string;
  payload: ApprovalRequestPayload;
};
export type CapabilityChangedEventMessage = EventEnvelopeBase & {
  type: 'evt.capability_changed';
  payload: CapabilityChangedPayload;
};
export type OperationCompletedEventMessage = EventEnvelopeBase & {
  type: 'evt.operation_completed';
  payload: OperationCompletedPayload;
};
/**
 * 整条连线上出现的任何一条消息都属于且仅属于这三个封闭判别联合之一（D2 v3 §4.1）——本文件是其部分转录，非完整闭合版本。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageTODO`'s JSON-Schema
 * via the `definition` "Message".
 */
export type Message = RequestMessage | ResponseMessage | EventMessage;

export interface MessageRequestMessageResponseMessageEventMessageTODO {
  [k: string]: unknown;
}
/**
 * RequestEnvelope<TType,TPayload> 的公共部分（D2 v3 §2）：direction 固定为 'request'，sentAt 为传输层时间戳。id/sessionId/type/payload 由具体方法 schema（schema/methods/*.schema.json）补充。
 */
export interface RequestEnvelopeBase {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
}
/**
 * 逐字段对应 D1 CreateSessionConfig（D1 v3.5 §2.1），无新增/无精简。
 */
export interface CreateSessionRequestPayload {
  config: {
    cwd: string;
    model?: string;
    newapiEndpoint: {
      baseUrl: string;
      /**
       * 条件必填——billingAttribution 为 user_tenant_aggregate 时缺失将触发 createSession 同步拒绝 aggregate_billing_requires_deployment_token（D1 v3.5 §2.1 步骤 0）。JSON Schema 层面不表达跨字段条件必填，忠实标注为可选，业务前置校验在实现层完成（呼应 D2 v3 §3.6 respondApproval 段落同类边界说明）。
       */
      deploymentTokenRef?: string;
    };
    toolset?: {
      allow?: string[];
      deny?: string[];
    };
    sandbox?: 'read-only' | 'workspace-write' | 'full-access';
    approvalProfile?: 'auto' | 'manual' | 'plan';
    resume?: {
      sessionId: string;
    };
  };
}
export interface InterruptRequestPayload {
  mode: 'steer' | 'cancel' | 'abort_and_resend';
  /**
   * 仅在 mode:'abort_and_resend' 且需要精确定向某个 run 时有意义。
   */
  runId?: string;
  /**
   * 仅 mode:'steer'（新内容）或 mode:'abort_and_resend'（重发内容）时需要；mode:'cancel' 应省略。
   */
  input?:
    | {
        kind: 'text';
        text: string;
      }
    | {
        kind: 'structured';
        parts: (
          | {
              kind: 'text';
              text: string;
            }
          | {
              kind: 'file_ref';
              /**
               * 文件系统坐标空间未裁决——D1 F-15 开放项，D2 已固化字段上线（D2 v3 §9.2 第 7 条）。
               */
              path: string;
              mimeType?: string;
            }
        )[];
      };
}
export interface RespondApprovalRequestPayload {
  reqId: string;
  decision:
    | {
        outcome: 'allow_once';
        updatedInput?: unknown;
      }
    | {
        outcome: 'allow_always';
        scope?: string;
        updatedInput?: unknown;
      }
    | {
        outcome: 'allow_session';
        scope?: string;
        updatedInput?: unknown;
      }
    | {
        outcome: 'deny';
        reason?: string;
      };
}
/**
 * 逐字段对应 D1 SessionHandle（D1 v3.5 §2）。kernel 字段的已知张力见 D2 v3 §9.2 第 1 条（S-08 回指，D1 INV-1 未裁决）。
 */
export interface CreateSessionResultPayload {
  sessionHandle: {
    sessionId: string;
    kernelSessionId?: string;
    kernel: 'openclaw' | 'hermes';
    createdAt: string;
    billing: {
      tokenRef: string;
    };
  };
}
/**
 * 7 个真正的 KernelPort 方法共用的同步/立即拒绝失败形状（D2 v3 §3）。
 */
export interface RejectionFailure {
  /**
   * 方法调用同步/立即拒绝码（D1 v3.5 §9.1）。billing_query_subject_unresolved 已于 v3.4 移出本枚举，改列 queryBilling 专属异步失败码，见 BillingQueryFailure。
   */
  code:
    | 'session_not_found'
    | 'session_already_stopped'
    | 'unsupported_interrupt_mode'
    | 'approval_not_pending'
    | 'no_active_run_for_steer'
    | 'session_locked'
    | 'unsupported_approval_decision'
    | 'aggregate_billing_requires_deployment_token';
  /**
   * 非稳定字段，透传调试信息。
   */
  detail?: string;
}
/**
 * D2 专属、不出现在 D1 任何地方的消息层协议错误（D2 v3 §7.4）。unsupported_protocol_version 仅在握手路径触发（res.capabilities 的 failure，D2 v3 §7.2 第 3 步）；malformed_message/unknown_message_type 适用于任意方法的 request 本身损坏或 type 不可辨认的场景。已并入 §3.9 全部 8 个具体方法 response 的 failure 联合以及 res.unknown 的 failure 类型。
 */
export interface ProtocolFailure {
  code: 'malformed_message' | 'unsupported_protocol_version' | 'unknown_message_type';
  detail?: string;
}
/**
 * D1 OperationOutcome 七态逐字透传，D2 不裁剪（D2 v3 §3.4）。
 */
export interface InterruptResultPayload {
  operationId: string;
  /**
   * 仅确有 active run 被 abort 时出现，不得虚构。
   */
  affectedRunId?: string;
  /**
   * 已铸造 operationId 的 operation 终态七态（D1 v3.5 §2.4/§9.1）。res.interrupt/res.stop 的 result.outcome 与 evt.operation_completed.outcome 共享同一词汇表；stop() 只可达其中三态子集（succeeded/timed_out/rejected，D1 §2.5），hard abort_and_resend 可达六态子集（全集去掉仅 soft 可达的 submitted，D4 §4.2）——本枚举忠实保留全部七态，子集约束是文档级约束，不在 schema 层面按 method 拆分（同 D2 v3 §3.5 stop() 的既有处理方式）。
   */
  outcome:
    | 'succeeded'
    | 'submitted'
    | 'aborted_no_resend'
    | 'aborted_resend_failed'
    | 'aborted_effect_unknown'
    | 'rejected'
    | 'timed_out';
  /**
   * 仅 mode:'abort_and_resend' 且 outcome:'succeeded' 时有意义。
   */
  newRunId?: string;
  /**
   * 仅 mode:'abort_and_resend'。
   */
  interruptedActiveRun?: boolean;
  /**
   * 非稳定字段，透传底层 ack 的 status，仅供调试。
   */
  status?: {
    [k: string]: unknown;
  };
  /**
   * 非稳定字段。
   */
  detail?: string;
}
export interface EmptyPayload {}
/**
 * EventEnvelope<TType,TPayload> 的公共部分（D2 v3 §2）：direction 固定为 'event'，seq/sessionId/ts 全局必填，runId 默认可选——部分事件类型（evt.approval_request/evt.turn_complete）在各自 schema 里把 runId 收紧为必填（D2 v3 §4 表格 envelope runId 列）。
 */
export interface EventEnvelopeBase {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  /**
   * D1 KernelEventBase.seq 的线上表示，仅同一 runId 内排序、不重放（D1 §9.2、D2 v3 §8）。
   */
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
}
export interface MessageDeltaPayload {
  role: 'assistant';
  delta: string;
  index: number;
}
export interface ToolCallPayload {
  toolCallId: string;
  name: string;
  input: unknown;
  status: 'started';
}
export interface ApprovalRequestPayload {
  /**
   * respondApproval() 的关联主键（= 内核 approval id，非 toolCallId）。
   */
  reqId: string;
  /**
   * 关联到对应 evt.tool_call 的 toolCallId，审计/展示用，非 respondApproval 关联键。
   */
  toolCallId: string;
  kind: 'exec' | 'tool' | 'mcp' | 'sandbox' | 'file_write';
  payload: unknown;
  proposedDecision?: 'allow_once' | 'allow_always' | 'deny';
  timeoutMs: number;
  /**
   * openclaw 'documented'；hermes 'best_effort'（约 60s，非官方承诺）——UI 不得在 'best_effort' 上做精确倒计时。
   */
  timeoutAuthority: 'documented' | 'best_effort';
}
export interface CapabilityChangedPayload {
  source: 'server_override' | 'kernel_error_inferred';
  capabilities: WireCapabilityDescriptorPayload;
  reason?: string;
}
/**
 * evt.capability_changed 专属的 wire 快照类型（D2 v3 v3-r1/r2，消解 codex T-018/T-019）：排除 protocolVersion——该字段已在握手期传输过一次且连接内恒定，逐事件重复既无信息增量也违反 §7.1『不再逐事件重复』规则。反序列化时由适配器用同一连接协商值同时回填事件基字段与本嵌套 descriptor 的 protocolVersion（D2 v3 §4 反序列化重建规则扩展）。
 */
export interface WireCapabilityDescriptorPayload {
  kernel: 'openclaw' | 'hermes';
  kernelVersion?: string;
  snapshotAt: string;
  tools: {
    discoverable: boolean;
    names?: string[];
  };
  approvalGranularity: 'per-tool' | 'per-command' | 'batch';
  approvalKinds: ('exec' | 'tool' | 'mcp' | 'sandbox' | 'file_write')[];
  approvalDecisionKinds: ('allow_once' | 'allow_always' | 'allow_session' | 'deny')[];
  interruptModes: ('steer' | 'cancel' | 'abort_and_resend')[];
  streamingGranularity: 'token-delta' | 'chunk' | 'message-only';
  sessionResume: boolean;
  thinkingVisibility: 'none' | 'summary' | 'raw';
  sandboxLevels?: ('read-only' | 'workspace-write' | 'full-access')[];
  usageReporting: 'none' | 'best-effort' | 'authoritative';
  billingAttribution: 'session' | 'user_tenant_aggregate';
}
export interface OperationCompletedPayload {
  operationId: string;
  operationKind: 'interrupt' | 'stop';
  /**
   * 已铸造 operationId 的 operation 终态七态（D1 v3.5 §2.4/§9.1）。res.interrupt/res.stop 的 result.outcome 与 evt.operation_completed.outcome 共享同一词汇表；stop() 只可达其中三态子集（succeeded/timed_out/rejected，D1 §2.5），hard abort_and_resend 可达六态子集（全集去掉仅 soft 可达的 submitted，D4 §4.2）——本枚举忠实保留全部七态，子集约束是文档级约束，不在 schema 层面按 method 拆分（同 D2 v3 §3.5 stop() 的既有处理方式）。
   */
  outcome:
    | 'succeeded'
    | 'submitted'
    | 'aborted_no_resend'
    | 'aborted_resend_failed'
    | 'aborted_effect_unknown'
    | 'rejected'
    | 'timed_out';
  affectedRunId?: string;
  newRunId?: string;
  detail?: string;
}
