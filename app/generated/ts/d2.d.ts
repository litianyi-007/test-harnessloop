/**
 * 本文件由 codegen 自动生成，不要手工编辑。
 * 源：app/contracts/d2/schema/message.schema.json（+ 其 $ref 的 methods/*、events/*、common/*）
 * 生成命令：npm --prefix app/contracts/d2/codegen run gen:ts
 * 覆盖范围（本轮 PRE-②/SG-1 骨架，非全量）：见 message.schema.json 顶层 $comment 的 TODO 清单。
 * 仅供开发期 fixture 工具 / TS oracle 使用（D4 §1.4/§4.4），不进任何产品打包。
 */

/**
 * 全覆盖（8/8）：createSession（§3.1）、send（§3.2）、subscribe（§3.3）、interrupt（§3.4）、stop（§3.5）、respondApproval（§3.6）、capabilities（§3.7）、queryBilling（§3.8，"+1"）。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageSG1`'s JSON-Schema
 * via the `definition` "RequestMessage".
 */
export type RequestMessage =
  | CreateSessionRequestMessage
  | SendRequestMessage
  | SubscribeRequestMessage
  | InterruptRequestMessage
  | StopRequestMessage
  | RespondApprovalRequestMessage
  | CapabilitiesRequestMessage
  | QueryBillingRequestMessage;
/**
 * 全覆盖（8/8 + res.unknown）：8 个具体方法 response + UnknownResponseMessage（§3.9，唯一 id 可选的 response 类型，failure 恒为 ProtocolFailure）。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageSG1`'s JSON-Schema
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
          type: 'res.send';
          id: string;
          sessionId?: string;
          result: SendResultPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.send';
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
          type: 'res.subscribe';
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
          type: 'res.subscribe';
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
          type: 'res.stop';
          id: string;
          sessionId?: string;
          result: StopResultPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.stop';
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
    )
  | (
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.capabilities';
          id: string;
          sessionId?: string;
          result: CapabilityDescriptorPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.capabilities';
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
          type: 'res.queryBilling';
          id: string;
          sessionId?: string;
          result: QueryBillingResultPayload;
        }
      | {
          /**
           * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
           */
          sentAt: string;
          direction: 'response';
          type: 'res.queryBilling';
          id: string;
          sessionId?: string;
          failure: BillingQueryFailure | ProtocolFailure;
        }
    )
  | UnknownResponseMessage;
/**
 * 全覆盖（11/11）：message.delta（#1）、thinking（#2）、tool_call（#3）、tool_result（#4）、approval_request（#5）、error（#6）、turn_complete（#7）、session_end（#8）、capability_changed（#9）、operation_completed（#10）、approval_buffer_resolved（#11）。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageSG1`'s JSON-Schema
 * via the `definition` "EventMessage".
 */
export type EventMessage =
  | MessageDeltaEventMessage
  | ThinkingEventMessage
  | ToolCallEventMessage
  | ToolResultEventMessage
  | ApprovalRequestEventMessage
  | ErrorEventMessage
  | TurnCompleteEventMessage
  | SessionEndEventMessage
  | CapabilityChangedEventMessage
  | OperationCompletedEventMessage
  | ApprovalBufferResolvedEventMessage;
/**
 * 整条连线上出现的任何一条消息都属于且仅属于这三个封闭判别联合之一（D2 v3 §4.1）——本文件是其全量转录。
 *
 * This interface was referenced by `MessageRequestMessageResponseMessageEventMessageSG1`'s JSON-Schema
 * via the `definition` "Message".
 */
export type Message = RequestMessage | ResponseMessage | EventMessage;

export interface MessageRequestMessageResponseMessageEventMessageSG1 {
  [k: string]: unknown;
}
/**
 * SG-1 深化：直接内联 sentAt/direction（不用 allOf 复用 common/envelope.schema.json#/$defs/requestEnvelopeBase）——codegen 工具 quicktype 对『allOf 引用外部 $ref 片段』存在已验证的缺陷（allOf 成员会被直接忽略，字段静默丢失，比 oneOf 坍缩更隐蔽；复现见 CODEGEN-FINDINGS.md），改为直接内联是规避写法，语义与 allOf 版本完全等价，Ajv 校验结果不变。
 */
export interface CreateSessionRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.createSession';
  id: string;
  /**
   * 不适用——createSession 尚无 session 可寻址，见上方说明。
   */
  sessionId?: string;
  payload: CreateSessionRequestPayload;
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
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface SendRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.send';
  id: string;
  sessionId: string;
  payload: SendRequestPayload;
}
/**
 * 逐字段对应 D1 KernelInput（D1 v3.5 §2），与 §3.4 interrupt 的 input 字段共享同一判别联合结构，无新增/无精简。
 */
export interface SendRequestPayload {
  /**
   * D1 v3.5 §2 KernelInput 判别联合，逐字对应 D2 v3 §3.2 SendRequestPayload.input 同款结构。
   */
  input:
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
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface SubscribeRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.subscribe';
  id: string;
  sessionId: string;
  payload: EmptyPayload;
}
export interface EmptyPayload {}
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface InterruptRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.interrupt';
  id: string;
  sessionId: string;
  payload: InterruptRequestPayload;
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
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface StopRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.stop';
  id: string;
  sessionId: string;
  payload: EmptyPayload;
}
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface RespondApprovalRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.respondApproval';
  id: string;
  sessionId: string;
  payload: RespondApprovalRequestPayload;
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
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface CapabilitiesRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.capabilities';
  id: string;
  /**
   * 可选——D1 capabilities(session?: SessionHandle) 的可选参数，同 createSession 并列为本联合仅有的两个例外。
   */
  sessionId?: string;
  payload: CapabilitiesRequestPayload;
}
export interface CapabilitiesRequestPayload {
  /**
   * UI 可选声明自己认识的 wire 协议版本集合（如 ["kernelport/1"]），供 §7.2 握手协商流程使用（v3 新增，消解 codex T-017 HIGH#3）。
   */
  supportedProtocolVersions?: string[];
}
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 create-session.schema.json 同处注释），语义与 allOf 版本等价。
 */
export interface QueryBillingRequestMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'request';
  type: 'req.queryBilling';
  id: string;
  sessionId: string;
  payload: QueryBillingRequestPayload;
}
export interface QueryBillingRequestPayload {
  window?: {
    from: string;
    to: string;
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
export interface SendResultPayload {
  runId: string;
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
/**
 * D1 §2.5：stop() 可达的 OperationOutcome 子集，仅三态——succeeded/timed_out/rejected（其余四态对 stop() 语义上不适用，D2 v2 §3.5 已更正 v1『类型层面允许全部七态通过检查』的自相矛盾表述）。
 */
export interface StopResultPayload {
  operationId: string;
  outcome: 'succeeded' | 'timed_out' | 'rejected';
}
/**
 * 握手响应 res.capabilities 的成功 result（D2 v3 §7）——protocolVersion 在此出现一次是允许且必要的（§7.1 权威值的唯一来源）。逐字段对应 D1 §4.1，无新增/无精简。
 */
export interface CapabilityDescriptorPayload {
  /**
   * wire 层单一契约版本标识，握手期确定，唯一权威值（D1 v3.5：连接级契约版本，D2 v3 §7.1）。当前基线 'kernelport/1'。
   */
  protocolVersion: string;
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
/**
 * 逐字段对应 D1 SessionBillingSnapshot（D1 §7）。correlatable 恒为字面量 false——D1 未来若确认可关联，须走版本升级，本 schema 不预先改变这个字面量类型。
 */
export interface QueryBillingResultPayload {
  sessionId: string;
  tokenRef: string;
  attribution: 'session' | 'user_tenant_aggregate';
  windowStart: string;
  windowEnd: string;
  requestCount: number;
  totalQuota: number;
  rpm: number;
  tpm: number;
  fetchedAt: string;
  correlatable: false;
}
/**
 * queryBilling 专属的独立失败类型——不使用 RejectionFailure，不与 KernelPortRejectionCode 共享枚举空间（D1 v3.5 §9.1、D2 v3 §3.8）。
 */
export interface BillingQueryFailure {
  code: 'billing_query_subject_unresolved';
  detail?: string;
}
/**
 * SG-1 深化：直接内联 sentAt/direction，不用 allOf——原写法虽不含 oneOf（本类型只有一种形状），但 SG-1 深化验证发现 quicktype 对『allOf 引用外部 $ref 片段』本身就有独立于 oneOf 坍缩的缺陷（allOf 成员被直接忽略、字段静默丢失，见 CODEGEN-FINDINGS.md），故本类型同样改为直接内联，规避写法，语义与 allOf 版本等价。
 */
export interface UnknownResponseMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'response';
  type: 'res.unknown';
  /**
   * 允许缺失——触发条件已收紧为『原 request 本身不可辨认』，天然没有 id 可回填。
   */
  id?: string;
  sessionId?: string;
  failure: ProtocolFailure;
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（allOf 成员被直接忽略、字段静默丢失，见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface MessageDeltaEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.message.delta';
  payload: MessageDeltaPayload;
}
export interface MessageDeltaPayload {
  role: 'assistant';
  delta: string;
  index: number;
  /**
   * 对应 wire session.message 事件外层 payload.messageId（不是 message.id——message 对象本身不带任何标识字段，见 rounds/0012 evidence/item1-mechanism-localization.md §2）。openclaw 为每条落地的消息（user/assistant）分配的全局唯一 id，每帧互异（实测样本见 rounds/0012 evidence/instrumented-run-findings.md §1.3）——是消费方做消息分组/去重的正确键，取代此前错误使用的 (runId,index) 复用键：index 只是单条 assistant 消息内的 content-block 下标，每条新消息都从 0 重新计数，同一 run 产出多条 assistant 消息时会撞出相同的 (runId,index) 组合，导致文本被错误地追加拼接（根因坐实见 rounds/0012 evidence/instrumented-run-findings.md §1.2）。可选字段（不在 required 里）：rounds/0012 新增，现存消费方（C#/TS 端、FrameReplayTests 里的历史帧）不携带该字段，不得因缺失而失败。
   */
  messageId?: string;
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface ThinkingEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.thinking';
  payload: ThinkingPayload;
}
export interface ThinkingPayload {
  delta: string;
  visibility: 'summary' | 'raw';
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface ToolCallEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.tool_call';
  payload: ToolCallPayload;
}
export interface ToolCallPayload {
  toolCallId: string;
  name: string;
  input: unknown;
  status: 'started';
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface ToolResultEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.tool_result';
  payload: ToolResultPayload;
}
export interface ToolResultPayload {
  toolCallId: string;
  output: unknown;
  isError: boolean;
  durationMs?: number;
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。runId 在本事件类型上必填（D2 v3 §4 表格），与其余 9 个 runId 可选的事件类型不同。
 */
export interface ApprovalRequestEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.approval_request';
  runId: string;
  payload: ApprovalRequestPayload;
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
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface ErrorEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.error';
  payload: ErrorPayload;
}
export interface ErrorPayload {
  /**
   * ErrorEvent.code 的唯一契约稳定取值集合（D1 v3-kernel-spec §9，D1 v3.5 §9.1 声明本枚举『保持不变，同 v3.1』）。
   */
  code:
    | 'rate_limited'
    | 'kernel_crashed'
    | 'auth_failed'
    | 'sandbox_denied'
    | 'network_lost'
    | 'approval_timeout'
    | 'unknown';
  message: string;
  /**
   * 调试参考，非契约稳定字段，UI 不得对其分支判断。
   */
  nativeCode?: string;
  recoverable: 'run' | 'session' | 'none';
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。runId 在本事件类型上必填（D2 v3 §4 表格），与其余 9 个 runId 可选的事件类型不同。
 */
export interface TurnCompleteEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.turn_complete';
  runId: string;
  payload: TurnCompletePayload;
}
export interface TurnCompletePayload {
  stopReason: 'completed' | 'cancelled' | 'error' | 'max_turns';
  /**
   * openclaw 走原生 sessions.steer 完成 mode:'abort_and_resend' 时同样产出本标注（该 RPC 本质也是 abort+resend）；mode:'steer'（soft，仅 openclaw）不产生 degraded——它是真正的同 run 注入，没有『这次转向丢弃了未产出内容』需要告知。
   */
  degraded?: {
    kind: 'abort_and_resend';
  };
  forceResolvedApprovals?: string[];
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
  };
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface SessionEndEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.session_end';
  payload: SessionEndPayload;
}
export interface SessionEndPayload {
  reason: 'stopped' | 'kernel_exited' | 'transport_closed' | 'error';
}
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface CapabilityChangedEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.capability_changed';
  payload: CapabilityChangedPayload;
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
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface OperationCompletedEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.operation_completed';
  payload: OperationCompletedPayload;
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
/**
 * SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
 */
export interface ApprovalBufferResolvedEventMessage {
  /**
   * ISO-8601 UTC，本消息被封套/序列化发出的时刻——纯 D2 传输层字段，非 D1 业务语义（D2 v3 §2 MessageEnvelopeBase.sentAt）。
   */
  sentAt: string;
  direction: 'event';
  seq: number;
  sessionId: string;
  runId?: string;
  /**
   * D1 KernelEventBase.ts 的逐字透传位——业务语义：事件发生时刻，与 sentAt（封套发出时刻）是两个独立字段（D2 v3 §2 修复 1）。
   */
  ts: string;
  type: 'evt.approval_buffer_resolved';
  payload: ApprovalBufferResolvedPayload;
}
export interface ApprovalBufferResolvedPayload {
  reqId: string;
  reason: 'buffered_timeout' | 'queue_overflow';
}
