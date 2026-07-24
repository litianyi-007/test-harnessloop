/**
 * D2/D4 金标 parity fixture DSL 的正式 TS 类型定义。
 *
 * 逐字转录自 D4 跨平台架构 v2.2 §4.3「fixture DSL：确定性 action/timeline」
 * （`~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`，`design_status: confirmed`），
 * 是该节 ts 代码块的正式化版本（此前只以 markdown 代码块形式存在，fixtures/README.md 摘要引用，
 * 没有可被 TS 编译器/runner 实际 import 的产物——本文件补齐这条依赖，供 ts-runner/ 使用）。
 *
 * 与 contracts/d2/schema/ 的关系：本文件描述的是 fixture 本身的结构（"一条测试用例长什么样"），
 * 不是 wire 消息的结构（那是 schema/ 的职责）。`WireResponseShorthand`/`WireEventShorthand` 引用
 * `../../../generated/ts/d2`（schema -> TS codegen 产物）的 `ResponseMessage`/`EventMessage`
 * 判别联合，让 fixture 里出现的 wire 消息形状与 schema 保持单一来源，不重复声明。
 */

import type { ResponseMessage, EventMessage } from '../../../generated/ts/d2';

/** D1 KernelPort 的 7+1 个方法名——D4 §4.3 `TimelineOp.client_call.call` 的取值域。 */
export type KernelClientMethod =
  | 'createSession'
  | 'send'
  | 'subscribe'
  | 'interrupt'
  | 'stop'
  | 'respondApproval'
  | 'capabilities'
  | 'queryBilling';

/** D1 §9.3 SessionLockState 四态（本文件只声明类型，状态机本身在 ts-runner/mock-kernel-client.ts）。 */
export type SessionLockState = 'idle' | 'send_pending' | 'interrupt_in_progress' | 'stop_in_progress';

/** D1 v3.5 §2.4/§9.1 OperationOutcome 七态——与 common/errors.schema.json#/$defs/OperationOutcome
 *  同源，此处独立声明是因为 dsl.ts 不依赖 schema/ 目录（fixture DSL 与 wire schema 是两层不同的
 *  正式化产物，故意不交叉 import，避免 fixture 结构定义意外耦合到 wire 消息 JSON Schema 的模块
 *  系统），取值须与该 $defs 手工保持一致。 */
export type OperationOutcome =
  | 'succeeded'
  | 'submitted'
  | 'aborted_no_resend'
  | 'aborted_resend_failed'
  | 'aborted_effect_unknown'
  | 'rejected'
  | 'timed_out';

/** 惯用的「分布式 Omit」——直接对判别联合用 Omit 会先把联合塌陷成单一对象类型再取键，丢失分支
 *  间的相关约束（如 ResponseMessage 的 result/failure 互斥）；本工具类型对每个联合分支单独应用
 *  Omit 再重新 union，保留判别联合结构。仅用于本文件 fixture DSL 的书写便利，不是 codegen 产物。
 *  （D4 §4.3 v2.2 收残：T-030 F-01 第二项引入的同名工具类型，此处逐字对应。） */
export type DistributiveOmit<T, K extends keyof any> = T extends unknown ? Omit<T, K> : never;

/** mock_response 的 message 字段类型——省略 sentAt/direction/id，由 runner 在派发前按虚拟时刻 t
 *  自动补全：sentAt 取该 TimelineOp 的虚拟时刻 t（生成确定性 ISO-8601 字符串，不依赖真实
 *  wall-clock）；direction 固定填 'response'；id 从 replyTo 引用的 client_call 的 outbound 请求里
 *  原样回填。fixture 作者只需写 type + result/failure（+ 可选 sessionId）。 */
export type WireResponseShorthand = DistributiveOmit<ResponseMessage, 'sentAt' | 'direction' | 'id'>;

/** mock_event 的 message 字段类型——省略 sentAt/direction/seq，runner 补全规则：sentAt 同上取
 *  虚拟时刻 t；direction 固定填 'event'；seq 按该 session 已推送事件数递增生成。ts 允许省略，
 *  缺省取与 sentAt 相同的虚拟时刻。sessionId/runId（部分事件类型必填）不属于传输元数据，仍须
 *  fixture 作者显式给出。 */
export type WireEventShorthand = DistributiveOmit<EventMessage, 'sentAt' | 'direction' | 'seq'> & { ts?: string };

/** D2 v3 §6 三层错误模型内联在这里的并集写法（供 callOutcomes 字段使用，取并集而非按 method
 *  精确判别是 D4 §4.3 v2.2 收残的既定简化处理，见 ClientObservableState.callOutcomes 注释）。 */
export interface RejectionFailureLike { code: string; detail?: string }
export interface ProtocolFailureLike { code: string; detail?: string }
export interface BillingQueryFailureLike { code: string; detail?: string }

/** 时间轴上某一时刻可观察的客户端状态快照——`initialState`/`expected`/`assert_state.expected`
 *  三处共用同一个类型（D4 §4.3 v2.2.1 收残：T-029 F-01，此前 `expected` 误引用未定义的
 *  `ClientObservation`，统一改用本类型）。 */
export interface ClientObservableState {
  sessionLock?: SessionLockState;
  approvalState?: Record<string /* reqId */, string /* ApprovalFsmState，D1 §6.2 五态+中间态 */>;
  capabilitySnapshot?: Record<string, unknown>; // CapabilityDescriptorPayload 的运行期快照
  /** operationId 或 client_call 的 id → OperationOutcome（interrupt/stop 铸造的 operation 通道） */
  pendingOperations?: Record<string, OperationOutcome | 'in_flight'>;
  /** client_call 的 id → 该次调用的结算结果（覆盖 respondApproval/capabilities/queryBilling 等
   *  不产生 operationId、因而不出现在 pendingOperations 里的方法）。失败联合取三层并集而非按
   *  method 精确判别，是 D4 §4.3 v2.2 收残注明的既定简化处理，本文件逐字沿用。 */
  callOutcomes?: Record<
    string,
    | { status: 'resolved'; value?: unknown }
    | { status: 'rejected'; failure: RejectionFailureLike | ProtocolFailureLike | BillingQueryFailureLike }
  >;
  /** subscribe() 收到的事件回调顺序与字段值，按观察到的先后顺序排列。 */
  observedEvents?: Array<{ type: string; payload?: unknown }>;
}

/** `mock_event` 专属的翻译层驱动控制量——**不属于** D2 wire 事件本身（那是 `message` 字段的职责，
 *  一个封闭的 `additionalProperties:false` D2 判别联合，容不下任何非 D2 字段）。只在某个 D2 事件在
 *  真实 openclaw 原生协议里由多条独立 wire 帧联合 join 而成时才需要——D2 `evt.*` 事件本身是已经
 *  join 完成的单一逻辑事件，没有"到达顺序"这个概念，这类纯翻译层测试控制信息只能作为 TimelineOp
 *  的兄弟字段单独声明（T-048 REWORK #1/#2 收残：此前 `_openclawJoinOrder` 被非法塞进
 *  `message`，违反封闭联合的 `additionalProperties:false`，现改用本字段）。TS `MockKernelClient`
 *  不模拟这层原生 join 细节，完全忽略本字段；只有驱动真实 client 的 runner（Swift/C#）会读取它。 */
export interface MockEventDriverHint {
  /** `evt.approval_request` 专属：SG-5 M1 双向 join 逻辑需要联合 `agent(stream:'approval')` 与
   *  `session.approval(phase:'pending')` 两条独立原生帧才能产出这一条 D2 事件——本字段声明测试
   *  驱动这两条原生帧的到达顺序，纯粹是"走哪条 join 分支"的翻译层测试控制量，不影响 D2 事件本身
   *  的内容。 */
  approvalJoinOrder?: 'agent_first' | 'session_first';
}

export type TimelineOp =
  | { t: number; op: 'client_call'; id?: string; call: KernelClientMethod; args: unknown }
  | { t: number; op: 'expect_outbound'; matches: string; pattern: Record<string, unknown> }
  | { t: number; op: 'mock_response'; replyTo: string; message: WireResponseShorthand }
  | { t: number; op: 'mock_event'; message: WireEventShorthand; driverHint?: MockEventDriverHint }
  | { t: number; op: 'disconnect' }
  | { t: number; op: 'reconnect' }
  | { t: number; op: 'advance_clock'; ms: number }
  | { t: number; op: 'assert_state'; expected: ClientObservableState };

export interface ParityFixture {
  name: string;
  description: string;
  initialState?: ClientObservableState;
  timeline: TimelineOp[];
  expected: ClientObservableState;
}
