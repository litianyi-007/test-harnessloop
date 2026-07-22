/**
 * 最小『假内核』kernel-client 参考实现——不是产品代码，是 D4 §1.4/§4.4 所称的「开发期契约
 * oracle」：只实现跑通本轮两个既有 fixture 所需的最小行为子集，不是 D1 KernelPort 的完整实现。
 *
 * 范围明确声明（诚实标注，不冒充完整）：
 * - 只实现 §9.3 SessionLockState 状态机里「soft steer 在途时 stop() 到达——必须等待，不得抢占」
 *   这一条转移规则（对应 operation-outcome/soft-steer-then-stop.json fixture）；四态互斥矩阵的
 *   其余组合（cancel/abort_and_resend 与 stop 的抢占仲裁分支、send_pending 态等）均未实现，
 *   标注 TODO，留给后续轮次补齐完整状态机时一并处理。
 * - createSession/subscribe 走最简路径：不做取消订阅、不做多订阅者广播、不做重连语义。
 * - respondApproval/capabilities/queryBilling 只做「发出 outbound + 等待 resolve/reject」，
 *   不模拟审批 FSM/能力协商/计费查询的任何业务规则——本轮两个 fixture 都不涉及这三个方法。
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

export class MockKernelClient {
  sessionLock: SessionLockState = 'idle';
  currentSessionId: string | undefined;
  pendingOperations: Record<string, OperationOutcome | 'in_flight'> = {};
  callOutcomes: Record<string, { status: 'resolved'; value?: unknown } | { status: 'rejected'; failure: unknown }> = {};
  observedEvents: Array<{ type: string; payload?: unknown }> = [];

  /** 已发出、尚未收到 mock_response 的 outbound 记录，供 expect_outbound / mock_response 引用。 */
  private outbound = new Map<string, OutboundRecord>();
  /** soft interrupt 在途时被 stop() 命中——记录『排队中的 stop 调用 id』，等 interrupt resolve
   *  后才真正把锁转为 stop_in_progress（D1 §9.3「等待，不抢占」规则，本轮唯一实现的转移）。 */
  private queuedStopWhileInterrupt: string | undefined;
  private eventSeq = 0;

  /** 执行一次 client_call：构造对应的 req.* outbound 消息（供 expect_outbound 断言），
   *  同步应用极简的 sessionLock 转移规则。返回本次调用的 outbound 记录。 */
  call(id: string, method: KernelClientMethod, args: unknown): OutboundRecord {
    const payload = (args ?? {}) as Record<string, unknown>;
    const sessionId = this.currentSessionId;
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
      case 'stop':
        type = 'req.stop';
        message.payload = {};
        message.sessionId = sessionId;
        if (this.sessionLock === 'interrupt_in_progress') {
          // D1 §9.3：soft steer 在途时 stop() 到达——排队等待，不改变当前锁状态，不得抢占。
          this.queuedStopWhileInterrupt = id;
        } else if (this.sessionLock === 'idle') {
          this.sessionLock = 'stop_in_progress';
        }
        this.pendingOperations[id] = 'in_flight';
        break;
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

    if ('result' in expanded) {
      this.callOutcomes[replyTo] = { status: 'resolved', value: expanded.result };
      if (record.method === 'createSession') {
        const result = expanded.result as { sessionHandle?: { sessionId?: string } };
        this.currentSessionId = result.sessionHandle?.sessionId;
      }
      if (record.method === 'interrupt' || record.method === 'stop') {
        const result = expanded.result as { outcome?: OperationOutcome };
        if (result?.outcome) this.pendingOperations[replyTo] = result.outcome;
      }
    } else if ('failure' in expanded) {
      this.callOutcomes[replyTo] = { status: 'rejected', failure: expanded.failure };
    }

    // interrupt resolve 后，若有排队中的 stop，锁才真正转为 stop_in_progress
    // （D1 §9.3「等待，不抢占」规则的后半段：steer 按二态收敛后锁转 stop_in_progress）。
    if (record.method === 'interrupt' && this.queuedStopWhileInterrupt) {
      this.sessionLock = 'stop_in_progress';
      this.queuedStopWhileInterrupt = undefined;
    }
  }

  /** 应用一条（已由 runner 补全 shorthand 的）event 消息——简化版：不做订阅者过滤/多订阅者广播，
   *  只要 subscribe() 已被调用过就记录（TODO：完整实现需要按 D1 §9.2 F-13 处理订阅生命周期）。 */
  applyEvent(expanded: Record<string, unknown>): void {
    this.eventSeq += 1;
    this.observedEvents.push({ type: expanded.type as string, payload: expanded.payload });
  }
}
