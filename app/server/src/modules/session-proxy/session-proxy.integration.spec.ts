import http, { type Server as HttpServer } from 'http';
import type { AddressInfo } from 'net';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { SessionNewApiTokenMapService } from '../session-token/session-newapi-token-map.service';
import { SessionProxyController } from './session-proxy.controller';
import { SessionProxyService } from './session-proxy.service';

/** 结构化错误响应体形状（同 http-exception.filter.ts 的 `{code, message}` 约定）。 */
interface StructuredErrorBody {
  code: string;
  message?: string;
}

/**
 * 生产同款全局前缀（同 `main.ts:11` 的 `app.setGlobalPrefix('api/d3/v1', ...)`）。
 *
 * T-042 对抗审 P0/P2 finding：旧版本这个测试文件没有挂这个前缀，请求直接打
 * `/session-proxy/chat/completions`，恰好让当时的 `stripMountPrefix`（只认
 * `/session-proxy` 前缀的字符串剥离）蒙混过关——生产环境实际请求路径是
 * `/api/d3/v1/session-proxy/...`，旧实现剥不掉这段前缀，上游 target 恒错，但
 * "无全局前缀"的测试全绿掩盖了这个问题（自证性假绿）。本文件现在必须挂与生产
 * 完全一致的全局前缀，请求也打完整生产路径，否则测试形状本身就不诚实。
 */
const GLOBAL_PREFIX = 'api/d3/v1';
const MOUNT_PATH = `/${GLOBAL_PREFIX}/session-proxy`;

/**
 * D3-proxy 集成测试——不依赖真实 DB（不通过 SessionProxyModule/SessionTokenModule 的
 * TypeOrmModule.forFeature 链路，直接 mock `SessionNewApiTokenMapService`），但用真实的
 * Nest HTTP 层（Express 5 + path-to-regexp v8，同生产 main.ts 一致的路由注册方式，
 * 包括同款 `setGlobalPrefix`）+ 一个真实的本地 HTTP 服务器充当"假 newapi 上游"，验证：
 *   1. 静态 openclaw→proxy key 校验（缺失/错误/未配置均拒绝，且不触达上游）。
 *   2. session→newapi 映射未命中时按策略（reject/aggregate）处理，且不允许无凭证放行。
 *   3. 命中映射后：在生产全局前缀下，上游收到的 path 正确改写；Authorization 换成
 *      真实 newapi key；内部路由头（x-session-affinity 等）与原始静态 Authorization
 *      不透传给上游；响应按 chunk 流式透传（非整体缓冲）。
 *   4. 下游路径 allowlist 生效：非 allowlist 路径与路径穿越（`..`）均被拒绝，不触达
 *      上游。
 *
 * 真实 openclaw/newapi 的端到端连通性验证不在本测试范围（见任务报告 defer 项）。
 */
describe('SessionProxy (integration, DB-free)', () => {
  let app: INestApplication;
  let appPort: number;
  let fakeUpstream: HttpServer;
  let fakeUpstreamPort: number;
  let receivedByUpstream: {
    headers: http.IncomingHttpHeaders;
    url: string | undefined;
    body: string;
  }[];
  let tokenMap: { findActive: jest.Mock };
  let configValues: Record<string, unknown>;

  const STATIC_KEY = 'test-openclaw-proxy-static-key';

  beforeAll(async () => {
    fakeUpstream = http.createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', () => {
        receivedByUpstream.push({
          headers: req.headers,
          url: req.url,
          body: Buffer.concat(chunks).toString('utf8'),
        });

        res.writeHead(200, { 'Content-Type': 'text/event-stream' });
        res.write('data: chunk-1\n\n');
        setTimeout(() => {
          res.write('data: chunk-2\n\n');
          setTimeout(() => {
            res.write('data: chunk-3\n\n');
            res.end();
          }, 60);
        }, 60);
      });
    });
    await new Promise<void>((resolve) =>
      fakeUpstream.listen(0, '127.0.0.1', resolve),
    );
    fakeUpstreamPort = (fakeUpstream.address() as AddressInfo).port;
  });

  afterAll(async () => {
    await new Promise<void>((resolve) => fakeUpstream.close(() => resolve()));
  });

  beforeEach(async () => {
    receivedByUpstream = [];
    tokenMap = { findActive: jest.fn() };

    // 用 `let` 捕获、按引用读取——个别测试用例会在发请求前直接改这个对象的字段
    // （比如把 staticAuthKey 置为 undefined、切换 unmappedSessionPolicy），
    // `ConfigService` mock 的 `get` 每次调用都读取当前值，不是构造时的快照。
    configValues = {
      'sessionProxy.staticAuthKey': STATIC_KEY,
      'sessionProxy.unmappedSessionPolicy': 'reject',
      'newapi.baseUrl': `http://127.0.0.1:${fakeUpstreamPort}`,
      'newapi.completionsBasePath': '/v1',
    };

    const moduleRef: TestingModule = await Test.createTestingModule({
      controllers: [SessionProxyController],
      providers: [
        SessionProxyService,
        {
          provide: ConfigService,
          useValue: { get: (key: string) => configValues[key] },
        },
        { provide: SessionNewApiTokenMapService, useValue: tokenMap },
      ],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix(GLOBAL_PREFIX, { exclude: ['health'] });
    await app.init();
    await app.listen(0);
    const httpServer = app.getHttpServer() as HttpServer;
    appPort = (httpServer.address() as AddressInfo).port;
  });

  afterEach(async () => {
    await app.close();
  });

  const postJson = (path: string) =>
    request(app.getHttpServer() as HttpServer).post(path);

  describe('静态 key 校验', () => {
    it('缺失 Authorization 时拒绝（401），不触达上游', async () => {
      const res = await postJson(`${MOUNT_PATH}/chat/completions`).send({
        model: 'x',
      });

      expect(res.status).toBe(401);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_proxy_unauthorized',
      );
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('Authorization 错误时拒绝（401），不触达上游', async () => {
      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', 'Bearer wrong-key')
        .send({ model: 'x' });

      expect(res.status).toBe(401);
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('静态 key 未配置时 fail-closed 拒绝（500），不触达上游', async () => {
      configValues['sessionProxy.staticAuthKey'] = undefined;

      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .send({ model: 'x' });

      expect(res.status).toBe(500);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_proxy_misconfigured',
      );
      expect(receivedByUpstream).toHaveLength(0);
    });
  });

  describe('session→newapi 映射未命中兜底', () => {
    it('默认 reject 策略：拒绝转发（502），不触达上游', async () => {
      tokenMap.findActive.mockResolvedValue(null);

      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'unmapped-session-id')
        .send({ model: 'x' });

      expect(res.status).toBe(502);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_billing_mapping_unresolved',
      );
      expect(tokenMap.findActive).toHaveBeenCalledWith('unmapped-session-id');
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('sessionId 缺失（未带任何亲和头）：跳过查表，直接按默认策略拒绝（502），不触达上游', async () => {
      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .send({ model: 'x' });

      expect(res.status).toBe(502);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_billing_mapping_unresolved',
      );
      expect(tokenMap.findActive).not.toHaveBeenCalled();
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('aggregate 策略但未配置兜底 key：fail-closed 拒绝（502），不触达上游', async () => {
      tokenMap.findActive.mockResolvedValue(null);
      configValues['sessionProxy.unmappedSessionPolicy'] = 'aggregate';

      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'unmapped-session-id')
        .send({ model: 'x' });

      expect(res.status).toBe(502);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_proxy_aggregate_fallback_unconfigured',
      );
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('aggregate 策略且已配置兜底 key：降级放行并换成聚合 key 转发（不是无凭证放行）', async () => {
      tokenMap.findActive.mockResolvedValue(null);
      configValues['sessionProxy.unmappedSessionPolicy'] = 'aggregate';
      configValues['sessionProxy.aggregateFallbackNewApiKey'] =
        'sk-aggregate-fallback';

      const res = await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'unmapped-session-id')
        .send({ model: 'x' });

      expect(res.status).toBe(200);
      expect(receivedByUpstream).toHaveLength(1);
      expect(receivedByUpstream[0].headers['authorization']).toBe(
        'Bearer sk-aggregate-fallback',
      );
    });
  });

  describe('命中映射：生产路径改写 + 换凭证转发 + header 剥离 + 流式透传', () => {
    beforeEach(() => {
      tokenMap.findActive.mockResolvedValue({
        newapiKey: 'sk-real-newapi-key',
        newapiTokenId: null,
        tokenGeneration: 1,
      });
    });

    it('生产全局前缀下，上游收到的 path 正确改写为 completionsBasePath + chat/completions（T-042 P0 自证）', async () => {
      await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'sess-abc')
        .send({ model: 'gpt-x', messages: [{ role: 'user', content: 'hi' }] });

      expect(receivedByUpstream).toHaveLength(1);
      const upstreamReq = receivedByUpstream[0];
      // 关键自证断言：若 P0 未修（旧 stripMountPrefix 只认 `/session-proxy` 前缀），
      // 挂了 `api/d3/v1` 全局前缀后，`req.originalUrl` 会是
      // `/api/d3/v1/session-proxy/chat/completions`，剥不掉前缀，最终上游 target 会是
      // `/v1/api/d3/v1/session-proxy/chat/completions` 这种错误 path——本断言必 fail。
      expect(upstreamReq.url).toBe('/v1/chat/completions');
      expect(upstreamReq.headers['authorization']).toBe(
        'Bearer sk-real-newapi-key',
      );
      expect(JSON.parse(upstreamReq.body)).toEqual({
        model: 'gpt-x',
        messages: [{ role: 'user', content: 'hi' }],
      });
    });

    it('转发到上游的请求头不含内部路由头，也不含原始静态 Authorization（T-042 P1 自证）', async () => {
      await postJson(`${MOUNT_PATH}/chat/completions`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'sess-abc')
        .set('session_id', 'sess-abc')
        .set('x-client-request-id', 'sess-abc')
        .send({ model: 'gpt-x' });

      expect(receivedByUpstream).toHaveLength(1);
      const upstreamHeaders = receivedByUpstream[0].headers;
      expect(upstreamHeaders['x-session-affinity']).toBeUndefined();
      expect(upstreamHeaders['session_id']).toBeUndefined();
      expect(upstreamHeaders['x-client-request-id']).toBeUndefined();
      expect(upstreamHeaders['authorization']).not.toBe(`Bearer ${STATIC_KEY}`);
      expect(upstreamHeaders['authorization']).toBe(
        'Bearer sk-real-newapi-key',
      );
    });

    it('响应按 chunk 流式透传给调用方，而非整体缓冲后一次性返回', async () => {
      const events = await new Promise<{ t: number; chunk: string }[]>(
        (resolve, reject) => {
          const collected: { t: number; chunk: string }[] = [];
          const start = Date.now();
          const req = http.request(
            {
              host: '127.0.0.1',
              port: appPort,
              path: `${MOUNT_PATH}/chat/completions`,
              method: 'POST',
              headers: {
                Authorization: `Bearer ${STATIC_KEY}`,
                'x-session-affinity': 'sess-stream',
                'content-type': 'application/json',
              },
            },
            (res) => {
              res.on('data', (buf: Buffer) => {
                collected.push({
                  t: Date.now() - start,
                  chunk: buf.toString('utf8'),
                });
              });
              res.on('end', () => resolve(collected));
              res.on('error', reject);
            },
          );
          req.on('error', reject);
          req.end(JSON.stringify({ model: 'gpt-x', stream: true }));
        },
      );

      // 至少收到 2 个独立到达的 chunk（上游分 3 次 write，中间各 sleep 60ms）——
      // 若实现是"整体缓冲后一次性转发"，客户端几乎必然把全部内容合并为极少数（通常 1个）
      // 紧邻到达的 data 事件，且首尾到达时间差会趋近于 0，而不会呈现出跨越 ~120ms 的分布。
      expect(events.length).toBeGreaterThanOrEqual(2);
      const firstT = events[0].t;
      const lastT = events[events.length - 1].t;
      expect(lastT - firstT).toBeGreaterThanOrEqual(40);

      const fullBody = events.map((e) => e.chunk).join('');
      expect(fullBody).toContain('chunk-1');
      expect(fullBody).toContain('chunk-2');
      expect(fullBody).toContain('chunk-3');
    });

    it('下游路径不在 allowlist 内时拒绝（403），不触达上游（T-042 P1 allowlist 自证）', async () => {
      const res = await postJson(`${MOUNT_PATH}/embeddings`)
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'sess-abc')
        .send({ input: 'x' });

      expect(res.status).toBe(403);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_proxy_path_not_allowed',
      );
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('路径穿越（`..`）被拒绝（400），不触达上游（T-042 P1 场景 B 自证）', async () => {
      // 用原始 socket 级 http.request（而非 supertest/superagent）——superagent 在发出
      // 请求前会用 URL 解析把 `/../` 规范化掉，测不到服务端对"字面上带 `..` 的原始请求
      // 路径"的防御；真实攻击者可以用裸 HTTP 客户端发出未规范化的请求行，评审报告的
      // 场景 B 正是用这种方式复现的。
      const status = await new Promise<number>((resolve, reject) => {
        const req = http.request(
          {
            host: '127.0.0.1',
            port: appPort,
            path: `${MOUNT_PATH}/../api/token/1`,
            method: 'POST',
            headers: {
              Authorization: `Bearer ${STATIC_KEY}`,
              'x-session-affinity': 'sess-abc',
              'content-type': 'application/json',
            },
          },
          (res) => {
            res.resume();
            res.on('end', () => resolve(res.statusCode ?? -1));
            res.on('error', reject);
          },
        );
        req.on('error', reject);
        req.end(JSON.stringify({}));
      });

      expect(status).toBe(400);
      expect(receivedByUpstream).toHaveLength(0);
    });
  });
});
