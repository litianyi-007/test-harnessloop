/**
 * TS fixture runner——D4 §4.4「多语言 runner 架构」里 TS runner 的权威金标实现，是 Swift/C# runner
 * 对照的基准 oracle。
 *
 * 职责：读一个 fixture（app/contracts/d2/fixtures/**\/*.json，结构见 ../dsl.ts），按 timeline
 * 顺序对 MockKernelClient（../ts-runner/mock-kernel-client.ts）执行 client_call/expect_outbound/
 * mock_response/mock_event/advance_clock/disconnect/assert_state 等 op，最终比对 `expected` 与
 * 实际可观察状态。
 *
 * **T-048 REWORK #3**：`advance_clock`/`disconnect` 此前只是记录、不触发任何转移——现已接到
 * `MockKernelClient.advanceClock`/`disconnect`，让 stop() 的 timed_out/aborted_effect_unknown
 * 两条路径真正可驱动（见 mock-kernel-client.ts 文件头「T-048 REWORK #3 收残的核心原则」）。
 *
 * 仍然如实标注的简化（不冒充完整 D4 §4.4 runner）：
 * - 不实现 reconnect 期间事件不可见的语义（D1 §9.2/D2 §8，本轮 fixture 未涉及）。
 * - expect_outbound 的 pattern 匹配是『actual 是否包含 pattern 声明的全部字段』的子集匹配，
 *   不是完整 JSON Schema 校验（schema 校验层面的自检已由 codegen/scripts/validate-schemas.mjs
 *   覆盖，职责不重复）。
 */

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import type { ParityFixture, TimelineOp, ClientObservableState } from '../dsl.ts';
import { MockKernelClient } from './mock-kernel-client.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));

/** 虚拟时钟基准——把 fixture 里的整数毫秒 `t` 转成确定性的 ISO-8601 字符串，不依赖真实
 *  wall-clock（D4 §4.3「虚拟时钟」原则）。基准值本身任意，只要跨 op 一致即可。 */
const VIRTUAL_EPOCH = Date.parse('2026-01-01T00:00:00.000Z');
function tToIso(t: number): string {
  return new Date(VIRTUAL_EPOCH + t).toISOString();
}

type Mismatch = string;

/** 子集深度匹配：expected 里出现的每个字段都必须在 actual 里以相等值出现；actual 多出的字段
 *  不算失败（这是『部分状态断言』的语义，D4 §4.3 `Partial<ClientObservableState>`）。 */
function partialMatch(actual: unknown, expected: unknown, path: string): Mismatch[] {
  if (expected === undefined) return [];
  if (expected === null || typeof expected !== 'object') {
    return actual === expected ? [] : [`${path}: 期望 ${JSON.stringify(expected)}，实际 ${JSON.stringify(actual)}`];
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) return [`${path}: 期望数组，实际 ${JSON.stringify(actual)}`];
    if (actual.length !== expected.length) {
      return [`${path}: 期望长度 ${expected.length}，实际长度 ${actual.length}`];
    }
    const out: Mismatch[] = [];
    expected.forEach((item, i) => out.push(...partialMatch(actual[i], item, `${path}[${i}]`)));
    return out;
  }
  if (actual === null || typeof actual !== 'object') {
    return [`${path}: 期望对象 ${JSON.stringify(expected)}，实际 ${JSON.stringify(actual)}`];
  }
  const out: Mismatch[] = [];
  for (const key of Object.keys(expected as Record<string, unknown>)) {
    out.push(
      ...partialMatch(
        (actual as Record<string, unknown>)[key],
        (expected as Record<string, unknown>)[key],
        `${path}.${key}`,
      ),
    );
  }
  return out;
}

function deriveState(client: MockKernelClient): ClientObservableState {
  return {
    sessionLock: client.sessionLock,
    pendingOperations: client.pendingOperations,
    callOutcomes: client.callOutcomes as ClientObservableState['callOutcomes'],
    observedEvents: client.observedEvents,
    // T-048 REWORK #3：approval/ 组新增 fixture 断言 approvalState，此前 deriveState 完全没有
    // 暴露这个字段（MockKernelClient 也没有跟踪），导致 12 条新 fixture 里的 2 条 approval fixture
    // 必然 FAIL——现已补齐，口径对齐 swift-runner 的 `ctx.approvalState`。
    approvalState: client.approvalState,
    // T-050 REWORK #3：暴露给 `expected.nativeCallOrder` 断言（目前只有
    // stop-force-denies-pending-approval.json 用它防 force-deny/abort 顺序回归）。
    nativeCallOrder: client.nativeCallOrder,
  };
}

/** 展开 mock_response/mock_event 的 shorthand——补全 runner 负责补全的传输元数据字段
 *  （D4 §4.3 v2.2 收残：T-030 F-01 第二项 shorthand 自动补全规则）。**导出**（T-050 REWORK #5）：
 *  供一次性 Ajv 严格校验脚本直接复用同一份展开逻辑，不再手工另写一份可能与 runner 本身漂移的复刻。 */
export function expandResponseShorthand(
  shorthand: Record<string, unknown>,
  t: number,
  outboundId: string,
): Record<string, unknown> {
  return { ...shorthand, sentAt: tToIso(t), direction: 'response', id: outboundId };
}

/** T-050 REWORK #5（治根）：`EventMessage` 判别联合的每个分支都把 `seq` 列为 required
 *  （`common/envelope.schema.json#/$defs/eventEnvelopeBase`），DSL/README 也明确规定 runner 负责
 *  按『该 session 已推送事件数递增』补全——上一版只补了 `ts`/`sentAt`/`direction`，漏掉 `seq`，
 *  之所以此前仍然 13/13 PASS，是因为 `MockKernelClient.applyEvent` 从未读取/校验这个 envelope
 *  字段，绿灯掩盖了 canonical-wire 不完整这件事。改为按 `sessionId`（shorthand 自带，事件级必填
 *  字段）分桶维护一个递增计数器，每次该 session 推一个事件就 +1（从 1 开始）；没有 `sessionId`
 *  字段的异常输入退化到一个共享桶，不让函数崩溃。 */
export function expandEventShorthand(
  shorthand: Record<string, unknown>,
  t: number,
  seqBySession: Map<string, number>,
): Record<string, unknown> {
  const sessionKey = typeof shorthand.sessionId === 'string' ? shorthand.sessionId : '__no_session__';
  const seq = (seqBySession.get(sessionKey) ?? 0) + 1;
  seqBySession.set(sessionKey, seq);
  return { ts: tToIso(t), ...shorthand, sentAt: tToIso(t), direction: 'event', seq };
}

export interface RunResult {
  name: string;
  passed: boolean;
  mismatches: Mismatch[];
}

export async function runFixture(fixturePath: string): Promise<RunResult> {
  const raw = await readFile(fixturePath, 'utf8');
  const fixture = JSON.parse(raw) as ParityFixture;

  const client = new MockKernelClient();
  if (fixture.initialState?.sessionLock) client.sessionLock = fixture.initialState.sessionLock;

  const mismatches: Mismatch[] = [];
  // T-050 REWORK #5：每条 fixture 一个独立的按-session seq 计数器——不能用模块级共享状态，否则
  // 同一进程里连续跑多条 fixture（`main()` 的循环）会让后一条 fixture 的 seq 从上一条的残留值继续
  // 累加，不是『该 session 已推事件数递增』（每条 fixture 从零开始才对）。
  const seqBySession = new Map<string, number>();

  for (const op of fixture.timeline as TimelineOp[]) {
    switch (op.op) {
      case 'client_call': {
        const id = op.id ?? `anon-${op.t}`;
        client.call(id, op.call, op.args);
        break;
      }
      case 'expect_outbound': {
        const record = client.getOutbound(op.matches);
        if (!record) {
          mismatches.push(`expect_outbound@t=${op.t}: 找不到 id='${op.matches}' 的 outbound 记录`);
          break;
        }
        const diff = partialMatch(record.message, op.pattern, `expect_outbound(${op.matches})`);
        mismatches.push(...diff);
        break;
      }
      case 'mock_response': {
        const record = client.getOutbound(op.replyTo);
        if (!record) {
          mismatches.push(`mock_response@t=${op.t}: 找不到 replyTo='${op.replyTo}' 的 outbound 记录`);
          break;
        }
        const expanded = expandResponseShorthand(op.message as unknown as Record<string, unknown>, op.t, record.id);
        client.applyResponse(op.replyTo, expanded);
        break;
      }
      case 'mock_event': {
        const expanded = expandEventShorthand(op.message as unknown as Record<string, unknown>, op.t, seqBySession);
        client.applyEvent(expanded);
        break;
      }
      case 'disconnect':
        // T-048 REWORK #3：接到 MockKernelClient.disconnect()——若有 stop() 正在等待 active run
        // 终态确认，按 D1 §9.2 NOTE-1 因果补 aborted_effect_unknown 镜像 + session_end
        // (transport_closed)；其余断线重连语义仍是 TODO（见 mock-kernel-client.ts 文档注释）。
        client.disconnect();
        break;
      case 'reconnect':
        // TODO（本轮未实现，见文件顶部简化声明）：断线重连语义。
        break;
      case 'advance_clock':
        // T-048 REWORK #3：接到 MockKernelClient.advanceClock()——若有 stop() 正在等待 active run
        // 终态确认且 ms 跨越 TEST_STOP_TIMEOUT_MS 阈值，按 D1 §9.3 因果补 timed_out 镜像 +
        // session_end(stopped)。
        client.advanceClock(op.ms);
        break;
      case 'assert_state': {
        const diff = partialMatch(deriveState(client), op.expected, `assert_state@t=${op.t}`);
        mismatches.push(...diff);
        break;
      }
      default: {
        const _exhaustive: never = op;
        throw new Error(`未知 TimelineOp: ${JSON.stringify(_exhaustive)}`);
      }
    }
  }

  const finalDiff = partialMatch(deriveState(client), fixture.expected, 'expected');
  mismatches.push(...finalDiff);

  return { name: fixture.name, passed: mismatches.length === 0, mismatches };
}

/** 不带路径参数时的默认清单——与 swift-runner `SwiftRunnerMain.swift` 的 `defaultFixturePaths()`
 *  对齐（T-048 REWORK 后共 13 条：basic 1 + operation-outcome 6 + session-lock 3 + approval 3）。 */
function defaultFixturePaths(): string[] {
  const relativePaths = [
    ['basic', 'create-session-subscribe-message-delta.json'],
    ['operation-outcome', 'soft-steer-then-stop.json'],
    ['operation-outcome', 'stop-no-active-run-succeeded.json'],
    ['operation-outcome', 'stop-active-run-succeeded.json'],
    ['operation-outcome', 'stop-timed-out.json'],
    ['operation-outcome', 'stop-rejected-rpc-failure.json'],
    ['operation-outcome', 'stop-transport-closed-aborted-effect-unknown.json'],
    ['session-lock', 'send-in-flight-send-pending.json'],
    ['session-lock', 'send-in-flight-rejects-concurrent-stop.json'],
    ['session-lock', 'stop-no-active-run-idle-transitions.json'],
    ['approval', 'pending-request-agent-first.json'],
    ['approval', 'pending-request-session-first.json'],
    ['approval', 'stop-force-denies-pending-approval.json'],
  ];
  return relativePaths.map(([dir, file]) => join(__dirname, '..', dir, file));
}

async function main() {
  const argFixtures = process.argv.slice(2);
  const fixturePaths = argFixtures.length > 0 ? argFixtures.map((p) => resolve(process.cwd(), p)) : defaultFixturePaths();

  let anyFailed = false;
  for (const fixturePath of fixturePaths) {
    const result = await runFixture(fixturePath);
    if (result.passed) {
      console.log(`[PASS] ${result.name} (${fixturePath})`);
    } else {
      anyFailed = true;
      console.log(`[FAIL] ${result.name} (${fixturePath})`);
      for (const m of result.mismatches) console.log(`       - ${m}`);
    }
  }
  if (anyFailed) process.exit(1);
  console.log('\n=== ALL PASS（TS fixture runner 全部通过） ===');
}

main().catch((err) => {
  console.error('[runner] 失败：', err);
  process.exit(1);
});
