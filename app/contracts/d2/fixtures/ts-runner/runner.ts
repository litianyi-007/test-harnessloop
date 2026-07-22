/**
 * 最小 TS fixture runner——D4 §4.4「多语言 runner 架构」里 TS runner 的最初一版：只打通 TS 一端
 * 作样板（任务书原话），Swift/C# runner 见 CODEGEN-FINDINGS.md「TODO」标注，本轮不做。
 *
 * 职责：读一个 fixture（app/contracts/d2/fixtures/**\/*.json，结构见 ../dsl.ts），按 timeline
 * 顺序对 MockKernelClient（../ts-runner/mock-kernel-client.ts，一个只覆盖本轮两个 fixture 所需
 * 行为的极简假内核）执行 client_call/expect_outbound/mock_response/mock_event/assert_state 等
 * op，最终比对 `expected` 与实际可观察状态。
 *
 * 已知简化（诚实标注，不冒充完整 D4 §4.4 runner）：
 * - 不实现虚拟时钟推进触发超时（advance_clock 目前只是记录，不触发任何 timed_out 类转移）。
 * - 不实现 disconnect/reconnect 期间事件不可见的语义（D1 §9.2/D2 §8，两个现有 fixture 未涉及）。
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
  };
}

/** 展开 mock_response/mock_event 的 shorthand——补全 runner 负责补全的传输元数据字段
 *  （D4 §4.3 v2.2 收残：T-030 F-01 第二项 shorthand 自动补全规则）。 */
function expandResponseShorthand(
  shorthand: Record<string, unknown>,
  t: number,
  outboundId: string,
): Record<string, unknown> {
  return { ...shorthand, sentAt: tToIso(t), direction: 'response', id: outboundId };
}
function expandEventShorthand(shorthand: Record<string, unknown>, t: number): Record<string, unknown> {
  return { ts: tToIso(t), ...shorthand, sentAt: tToIso(t), direction: 'event' };
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
        const expanded = expandEventShorthand(op.message as unknown as Record<string, unknown>, op.t);
        client.applyEvent(expanded);
        break;
      }
      case 'disconnect':
      case 'reconnect':
        // TODO（本轮未实现，见文件顶部简化声明）：断线期间事件不可见语义。
        break;
      case 'advance_clock':
        // TODO（本轮未实现）：虚拟时钟推进触发超时类转移。
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

async function main() {
  const argFixtures = process.argv.slice(2);
  const fixturePaths =
    argFixtures.length > 0
      ? argFixtures.map((p) => resolve(process.cwd(), p))
      : [
          join(__dirname, '..', 'basic', 'create-session-subscribe-message-delta.json'),
          join(__dirname, '..', 'operation-outcome', 'soft-steer-then-stop.json'),
        ];

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
