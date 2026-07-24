/**
 * 最小『假内核』kernel-client 参考实现——不是产品代码，是 D4 §1.4/§4.4 所称的「开发期契约
 * oracle」：本轮（T-048 REWORK #3）从 D1/D2 spec 扩到覆盖 approval/operation-outcome/session-lock
 * 三组新增 fixture 需要的行为子集，仍然不是 D1 KernelPort 的完整实现。
 *
 * **T-048 REWORK #3 收残的核心原则**：本文件的 stop()/send() 行为直接从 D1 v3 §9.1/§9.3、D2 v3
 * §3.5 的规则写出（锁互斥矩阵、OperationOutcome 通道划分、stop 收尾事件顺序），不是照抄
 * swift-runner 观察到的真实 client 行为再誊抄一遍——否则两端 parity 只是『互相抄』的空转，一旦真实
 * client 出现偏离 spec 的 bug，两边会一起错得一致，反而掩盖问题（codex T-048 对抗审的核心批评）。
 *
 * 范围仍然明确声明（诚实标注，不冒充完整）：
 * - `respondApproval`/`capabilities`/`queryBilling` 只做「发出 outbound + 等待 resolve/reject」，
 *   不模拟审批终态 FSM/能力协商/计费查询的任何业务规则——本轮新增 fixture 都不涉及这三个方法的
 *   结果处理（`approval/` 组只覆盖到 PENDING + FORCE_DENIED_ON_STOP，不涉及 respondApproval()）。
 * - `interrupt` 只实现 `soft-steer-then-stop.json` 需要的这一条转移（steer 在途时 stop() 到达，
 *   排队不抢占）；其余仲裁分支未实现，标注 TODO。
 * - `advance_clock`/`disconnect` 只在『有一个 stop() 正在等待 active run 终态确认』
 *   （`pendingStopWait` 非空）时才有意义，Stage A 范围外的虚拟时钟/断线重连语义仍是 TODO
 *   （与 swift-runner 同样窄的范围声明对齐，见该文件 `applyAdvanceClock`/`.disconnect` 文档注释）。
 *
 * **T-050 REWORK #2（confirming 再审揪出的空转，本轮修）**：`stop()` 的 D1 §6.2 M3 force-deny 分支
 * 此前只是把 fixture 在 `evt.turn_complete.payload.forceResolvedApprovals` 里声明的值原样转发到
 * `observedEvents`——`approvalState` 从未真正被 stop() 推进到任何强制终态，也从未产出对应的
 * `approval.resolve` outbound；这是 T-048 REWORK #3 声称的『两端独立 oracle』在这一个分支上的例外
 * （空转，不是从 spec 写出）。本轮改为在 `call()` 处理 'stop' 时**独立执行** force-deny（对本地
 * `approvalState` 里仍是 'pending' 的每个 reqId 推进到 'force_denied_on_stop'、记录一次
 * `nativeCallOrder.push('approval.resolve')`），并把由此算出的 reqId 列表存进
 * `forceResolvedApprovalsByCallId`；`evt.turn_complete` 到达时不再读 fixture 声明的
 * `forceResolvedApprovals`，改用这份自己算出的列表覆盖/删除该字段（见 `applyEvent`）。
 */

import type { KernelClientMethod, SessionLockState, OperationOutcome } from '../dsl.ts';

export interface OutboundRecord {
  id: string;
  method: KernelClientMethod;
  message: Record<string, unknown>;
}

export interface PendingCall {
  id: string;
  method: KernelClientMethod;
}

/** stop() 命中一个 active run 时的『等待终态确认』状态——真实 D1 §9.3 语义：sessions.abort 这条底层
 *  RPC ack 只诚实回报『是否存在 active run 被中止』，并不直接决定最终 OperationOutcome；真正的
 *  succeeded/timed_out/aborted_effect_unknown 由后续『aborted lifecycle 事件到达』/『虚拟时钟推进
 *  越过超时阈值』/『transport 断开』三条互斥路径之一决定（对齐 swift-runner 驱动真实 client 的同一套
 *  因果，而不是简单从 mock_response 的 `result.outcome` 直接抄一个值——T-048 REWORK #3 核心）。 */
interface PendingStopWait {
  /** 这次 stop() client_call 的 id（本文件 `pendingOperations`/`callOutcomes` 用 client_call id
   *  做键，不是内部 operationId，见 dsl.ts 对该字段的注释）。 */
  id: string;
  affectedRunId: string;
  /** T-050 REWORK #2 新增：这次 stop() 在 `call()` 里（D1 §6.2 M3 定序要求的『先 force-deny 再
   *  abort』时机）**独立算出**的『被强制 deny 的 reqId 列表』——不是从 fixture 的
   *  `evt.turn_complete.payload.forceResolvedApprovals` 读来的，见 `call()` 的 'stop' 分支与
   *  `applyEvent` 的 `evt.turn_complete` 分支。 */
  forceResolvedApprovalReqIds: string[];
}

/** stop() 测试专用超时阈值——与 swift-runner `RunnerContext.stopTimeoutSeconds = 1`
 *  （`testSupportSetStopTimeoutSeconds` 收窄后的值）对齐的独立约定：D1 生产默认是 5000ms
 *  （D1 v3 §9.3），两端各自把『测试环境下多久算跨越了超时阈值』定为同一个显式常量，不是从 fixture
 *  里读来的，也不是照抄对方的实现——只是两个独立 oracle 对『测试环境阈值』这个约定值凑巧需要一致
 *  （否则同一条 `advance_clock` op 在两端会得出不同结论），如实标注这一层对齐关系。 */
export const TEST_STOP_TIMEOUT_MS = 1000;

export class MockKernelClient {
  sessionLock: SessionLockState = 'idle';
  currentSessionId: string | undefined;
  /** 最近一次 send() 真实 resolve 出的 runId——D1 §9.3 stop() 的『是否存在 active run』判定完全从
   *  这个 canonical 事实无歧义派生，不依赖 mock_response 里任何装饰性字段（T-048 REWORK #1 对齐：
   *  swift-runner 同样从 `ctx.currentRunIDValue` 派生）。 */
  currentRunId: string | undefined;
  pendingOperations: Record<string, OperationOutcome | 'in_flight'> = {};
  callOutcomes: Record<string, { status: 'resolved'; value?: unknown } | { status: 'rejected'; failure: unknown }> = {};
  observedEvents: Array<{ type: string; payload?: unknown }> = [];
  /** T-048 REWORK #3 新增：`respondApproval()` 本轮仍是 TODO 桩范围之外——approvalState 只记录
   *  PENDING（`evt.approval_request` 到达即置 'pending'），与 swift-runner `ctx.approvalState`
   *  的记账口径一致。 */
  approvalState: Record<string, string> = {};
  /** T-050 REWORK #3 新增：与 swift-runner `RunnerContext.nativeCallOrder` 同一目的——只登记
   *  Stage A 需要断言顺序的这几个特定动作（`approval.resolve`/`sessions.abort`），供
   *  `stop-force-denies-pending-approval.json` 的 `expected.nativeCallOrder` 断言防回归。TS 端
   *  没有真实原生 RPC 层，这里在 `call()` 自己的执行顺序里 push——即『force-deny 循环必须先于
   *  产出 req.stop outbound』这条 D1 §6.2 M3 定序要求，由本文件自己的代码顺序保证，若未来谁把两步
   *  顺序调换，这里记录下来的顺序就会真实反映出来。 */
  nativeCallOrder: string[] = [];

  /** 已发出、尚未收到 mock_response 的 outbound 记录，供 expect_outbound / mock_response 引用。 */
  private outbound = new Map<string, OutboundRecord>();
  /** soft interrupt 在途时被 stop() 命中——记录『排队中的 stop 调用 id』，等 interrupt resolve
   *  后才真正把锁转为 stop_in_progress（D1 §9.3「等待，不抢占」规则，本轮唯一实现的转移）。 */
  private queuedStopWhileInterrupt: string | undefined;
  /** T-048 REWORK #3 新增：stop() 命中 active run 时的等待态，见 `PendingStopWait` 文档注释。 */
  private pendingStopWait: PendingStopWait | undefined;
  /** T-050 REWORK #2 新增：`call()` 处理 'stop' 时（D1 §6.2 M3 force-deny 时机）算出的『被强制
   *  deny 的 reqId 列表』，按这次 stop() 的 client_call id 记账——`applyStopResponse` 稍后把它
   *  搬进 `PendingStopWait.forceResolvedApprovalReqIds`（若确实进入等待态），或者在『没有 active
   *  run，立即结算』的路径上就没有 turn_complete 事件可以附着，直接丢弃（这条路径的失败/立即成功
   *  也不会产生任何 forceResolvedApprovals，符合 D1 §6.2：该字段严格限定于经由 turn_complete 的
   *  stop 场景）。 */
  private forceResolvedApprovalsByCallId: Record<string, string[]> = {};
  private eventSeq = 0;

  private emit(type: string, payload: unknown): void {
    this.observedEvents.push({ type, payload });
  }

  /** 执行一次 client_call：构造对应的 req.* outbound 消息（供 expect_outbound 断言），
   *  同步应用极简的 sessionLock 转移规则。返回本次调用的 outbound 记录——**若这次调用在锁互斥矩阵
   *  下被同步拒绝（D1 v3.1 §9.1 KernelPortRejectionCode 层面，未铸造 operationId），返回 undefined
   *  且不注册任何 outbound**，对齐真实 client『锁不满足前置条件时在任何 RPC 发出之前就 throw』的
   *  行为（swift-runner 侧同理：`session_locked` 由 stop()/send() 顶部 guard 直接抛出，从不到达
   *  `request()`）。 */
  call(id: string, method: KernelClientMethod, args: unknown): OutboundRecord | undefined {
    const payload = (args ?? {}) as Record<string, unknown>;
    const sessionId = this.currentSessionId;

    // D1 v3.1 §9.3 规则 1：send()/stop() 在锁不是 idle（且不是 interrupt_in_progress 的『排队』
    // 特例）时一律同步 reject(session_locked)——发生在 operationId 铸造之前，不发起任何 RPC。
    if (method === 'send' && this.sessionLock !== 'idle') {
      this.callOutcomes[id] = { status: 'rejected', failure: { code: 'session_locked' } };
      return undefined;
    }
    if (method === 'stop' && this.sessionLock !== 'idle' && this.sessionLock !== 'interrupt_in_progress') {
      this.callOutcomes[id] = { status: 'rejected', failure: { code: 'session_locked' } };
      return undefined;
    }

    let type: string;
    const message: Record<string, unknown> = {};

    switch (method) {
      case 'createSession':
        type = 'req.createSession';
        message.payload = payload;
        break;
      case 'send':
        type = 'req.send';
        message.payload = payload;
        message.sessionId = sessionId;
        this.sessionLock = 'send_pending';
        break;
      case 'subscribe':
        type = 'req.subscribe';
        message.payload = {};
        message.sessionId = sessionId;
        break;
      case 'interrupt':
        type = 'req.interrupt';
        message.payload = payload;
        message.sessionId = sessionId;
        // 极简锁转移：idle -> interrupt_in_progress（本轮只需覆盖这一条起始转移）。
        if (this.sessionLock === 'idle') {
          this.sessionLock = 'interrupt_in_progress';
        }
        this.pendingOperations[id] = 'in_flight';
        break;
      case 'stop': {
        type = 'req.stop';
        message.payload = {};
        message.sessionId = sessionId;
        // D1 §6.2 M3（T-050 REWORK #2：独立从 spec 实现，不回显 fixture）：stop() 在发起
        // sessions.abort 之前，必须先把本 session 所有仍处于 PENDING 的审批强制推进到
        // FORCE_DENIED_ON_STOP——本段从本文件自己跟踪的 `approvalState` 局部推导被强制 deny 的
        // reqId 列表，不读 fixture 在 `evt.turn_complete.payload.forceResolvedApprovals` 里声明
        // 的值当输入（那是 T-050 confirming 再审揪出的问题：此前只是把这个字段原样转发，TS parity
        // 在这里完全空转）。`nativeCallOrder` 依次 push 'approval.resolve'（每条 pending 各一次）
        // 再 push 'sessions.abort'——这个顺序就是这段代码本身的执行顺序，正是 D1 §6.2 M3 定序要求
        // 断言的东西：force-deny 必须先于 abort。
        const forceDenied: string[] = [];
        for (const reqId of Object.keys(this.approvalState)) {
          if (this.approvalState[reqId] === 'pending') {
            this.nativeCallOrder.push('approval.resolve');
            this.approvalState[reqId] = 'force_denied_on_stop';
            forceDenied.push(reqId);
          }
        }
        if (forceDenied.length > 0) this.forceResolvedApprovalsByCallId[id] = forceDenied;
        this.nativeCallOrder.push('sessions.abort');
        if (this.sessionLock === 'interrupt_in_progress') {
          // D1 §9.3：soft steer 在途时 stop() 到达——排队等待，不改变当前锁状态，不得抢占。
          this.queuedStopWhileInterrupt = id;
        } else if (this.sessionLock === 'idle') {
          this.sessionLock = 'stop_in_progress';
        }
        this.pendingOperations[id] = 'in_flight';
        break;
      }
      case 'respondApproval':
        type = 'req.respondApproval';
        message.payload = payload;
        message.sessionId = sessionId;
        break;
      case 'capabilities':
        type = 'req.capabilities';
        message.payload = payload;
        break;
      case 'queryBilling':
        type = 'req.queryBilling';
        message.payload = payload;
        message.sessionId = sessionId;
        break;
      default:
        throw new Error(`MockKernelClient: 未知方法 '${method}'（TODO：本轮只实现 8 个方法的极简路径）`);
    }
    message.type = type;
    message.id = id;

    const record: OutboundRecord = { id, method, message };
    this.outbound.set(id, record);
    return record;
  }

  getOutbound(id: string): OutboundRecord | undefined {
    return this.outbound.get(id);
  }

  /** 应用一条（已由 runner 补全 shorthand 的）response 消息。 */
  applyResponse(replyTo: string, expanded: Record<string, unknown>): void {
    const record = this.outbound.get(replyTo);
    if (!record) {
      throw new Error(`applyResponse: 找不到 replyTo='${replyTo}' 对应的 outbound 记录`);
    }

    if (record.method === 'stop') {
      this.applyStopResponse(replyTo, expanded);
      return;
    }

    if ('result' in expanded) {
      this.callOutcomes[replyTo] = { status: 'resolved', value: expanded.result };
      if (record.method === 'createSession') {
        const result = expanded.result as { sessionHandle?: { sessionId?: string } };
        this.currentSessionId = result.sessionHandle?.sessionId;
      }
      if (record.method === 'send') {
        const result = expanded.result as { runId?: string };
        this.currentRunId = result?.runId;
        if (this.sessionLock === 'send_pending') this.sessionLock = 'idle';
      }
      if (record.method === 'interrupt') {
        const result = expanded.result as { outcome?: OperationOutcome };
        if (result?.outcome) this.pendingOperations[replyTo] = result.outcome;
      }
    } else if ('failure' in expanded) {
      this.callOutcomes[replyTo] = { status: 'rejected', failure: expanded.failure };
      if (record.method === 'send' && this.sessionLock === 'send_pending') this.sessionLock = 'idle';
    }

    // interrupt resolve 后，若有排队中的 stop，锁才真正转为 stop_in_progress
    // （D1 §9.3「等待，不抢占」规则的后半段：steer 按二态收敛后锁转 stop_in_progress）。
    if (record.method === 'interrupt' && this.queuedStopWhileInterrupt) {
      this.sessionLock = 'stop_in_progress';
      this.queuedStopWhileInterrupt = undefined;
    }
  }

  /** D1 v3 §9.3 stop() 的核心因果——从 spec 写出，不从 `expanded.result.outcome` 直接抄值
   *  （T-048 REWORK #3 核心，见文件头注释）：
   *  - `failure`：底层 RPC 本身失败（M3 catch 分支）——operationId 已铸造，直接产出
   *    operation_completed(rejected) 镜像，**不**产出 session_end（真实 stop() 的 catch 分支只清理
   *    状态+补镜像+重新抛错，不会走到 `emitStopSessionEndAndFinish`），锁释放回 idle。
   *  - `result` 且没有 active run（`this.currentRunId` undefined）：sessions.abort 诚实回报『没有
   *    可等待的终态』，立即产出 succeeded + session_end(stopped)。
   *  - `result` 且有 active run：**不**立即结算——记录 `pendingStopWait`，真正的 OperationOutcome
   *    由随后到达的 `evt.turn_complete`（terminal-observed）/`advance_clock`（timed-out）/
   *    `disconnect`（transport-closed）三条互斥路径之一决定，见 `resolveStopWait`。 */
  private applyStopResponse(replyTo: string, expanded: Record<string, unknown>): void {
    if ('failure' in expanded) {
      this.emit('evt.operation_completed', { outcome: 'rejected', operationKind: 'stop' });
      this.pendingOperations[replyTo] = 'rejected';
      this.sessionLock = 'idle';
      this.callOutcomes[replyTo] = { status: 'rejected', failure: expanded.failure };
      return;
    }

    if (this.currentRunId === undefined) {
      this.emit('evt.operation_completed', { outcome: 'succeeded', operationKind: 'stop' });
      this.emit('evt.session_end', { reason: 'stopped' });
      this.pendingOperations[replyTo] = 'succeeded';
      this.sessionLock = 'idle';
      return;
    }

    // T-050 REWORK #2：把 `call()` 处理这次 stop() 时（force-deny 时机）独立算出的 reqId 列表
    // 搬进等待态——不存在就是空数组（这次 stop() 没有命中任何 pending 审批，`evt.turn_complete`
    // 转发时会删掉 payload 里的 forceResolvedApprovals 字段，即使 fixture 误声明了这个字段）。
    const forceResolvedApprovalReqIds = this.forceResolvedApprovalsByCallId[replyTo] ?? [];
    delete this.forceResolvedApprovalsByCallId[replyTo];
    this.pendingStopWait = { id: replyTo, affectedRunId: this.currentRunId, forceResolvedApprovalReqIds };
  }

  private resolveStopWait(outcome: 'succeeded' | 'timed_out' | 'aborted_effect_unknown', sessionEndReason: string): void {
    const wait = this.pendingStopWait;
    if (!wait) return;
    this.emit('evt.operation_completed', { outcome, operationKind: 'stop', affectedRunId: wait.affectedRunId });
    this.pendingOperations[wait.id] = outcome;
    this.sessionLock = 'idle';
    this.pendingStopWait = undefined;
    this.currentRunId = undefined;
    // session_end 在 turn_complete 分支（succeeded 经 terminal-observed）里由调用方
    // （`applyEvent` 的 evt.turn_complete 分支）在转发完 turn_complete 本身之后再补——保持
    // operation_completed -> turn_complete -> session_end 这个 D1 v3 §9.3 规定的顺序；
    // timed_out/aborted_effect_unknown 两条路径没有 turn_complete，直接在这里补。
    if (outcome !== 'succeeded') {
      this.emit('evt.session_end', { reason: sessionEndReason });
    }
  }

  /** 应用一条（已由 runner 补全 shorthand 的）event 消息——简化版：不做订阅者过滤/多订阅者广播，
   *  只要 subscribe() 已被调用过就记录（TODO：完整实现需要按 D1 §9.2 F-13 处理订阅生命周期）。 */
  applyEvent(expanded: Record<string, unknown>): void {
    this.eventSeq += 1;
    const type = expanded.type as string;
    const payload = expanded.payload as Record<string, unknown> | undefined;

    if (type === 'evt.approval_request' && payload?.reqId) {
      this.approvalState[payload.reqId as string] = 'pending';
    }

    if (type === 'evt.turn_complete' && this.pendingStopWait) {
      // D1 v3 §9.3：terminal-observed 路径——先补 operation_completed(succeeded) 镜像，再转发
      // turn_complete，最后补 session_end(stopped)。
      // **T-050 REWORK #2（治根）**：`forceResolvedApprovals` 不再原样透传 fixture 声明值——那是
      // 把 expected 事实当输入再回显，TS parity 在这里空转（T-050 confirming 再审揪出的问题）。
      // 改为用 `wait.forceResolvedApprovalReqIds`（`call()` 处理这次 stop() 时，从本文件自己的
      // `approvalState` 独立算出的列表，见 `PendingStopWait` 文档注释）覆盖——没有强制 deny 任何
      // 审批就删掉这个字段（即使 fixture 在 `mock_event` 里误声明了它），忠实反映『这是适配器自己
      // 决定要不要填的字段，不是内核 wire 帧原生携带的东西』（真实 Swift 端同理：
      // `TurnCompleteEvent.forceResolvedApprovals` 由 `stop()` 铸造的 `PendingStop.
      // forceResolvedApprovalReqIDs` 提供，EventMapping.swift 从不读取原生 wire 帧本身的这个字段）。
      const wait = this.pendingStopWait;
      this.emit('evt.operation_completed', { outcome: 'succeeded', operationKind: 'stop', affectedRunId: wait.affectedRunId });
      this.pendingOperations[wait.id] = 'succeeded';
      this.sessionLock = 'idle';
      this.pendingStopWait = undefined;
      this.currentRunId = undefined;
      const outgoingPayload: Record<string, unknown> = { ...(payload ?? {}) };
      if (wait.forceResolvedApprovalReqIds.length > 0) {
        outgoingPayload.forceResolvedApprovals = wait.forceResolvedApprovalReqIds;
      } else {
        delete outgoingPayload.forceResolvedApprovals;
      }
      this.observedEvents.push({ type, payload: outgoingPayload });
      this.emit('evt.session_end', { reason: 'stopped' });
      return;
    }

    this.observedEvents.push({ type, payload });
  }

  /** T-048 REWORK #3：虚拟时钟推进——只在『有一个 stop() 正在等待 active run 终态确认』时才有意义
   *  （对齐 swift-runner `applyAdvanceClock` 的同一窄范围声明），`ms` 跨越 `TEST_STOP_TIMEOUT_MS`
   *  阈值时判定为超时，产出 operation_completed(timed_out) + session_end(stopped)。 */
  advanceClock(ms: number): void {
    if (!this.pendingStopWait) return;
    if (ms < TEST_STOP_TIMEOUT_MS) return;
    this.resolveStopWait('timed_out', 'stopped');
  }

  /** T-048 REWORK #3：断线——只在『有一个 stop() 正在等待 active run 终态确认』时才有意义（其余
   *  断线重连语义本轮未实现，TODO，对齐 swift-runner 同样窄的范围声明）。真实 D1 §9.2/NOTE-1
   *  因果：transport 断开时若仍有 stop() 在等待，适配器必须补发一条 aborted_effect_unknown 镜像
   *  （效果未知，不是失败也不是成功）后再产出 session_end(transport_closed)，不能让等待者永久悬挂。 */
  disconnect(): void {
    if (!this.pendingStopWait) return;
    this.resolveStopWait('aborted_effect_unknown', 'transport_closed');
  }
}
