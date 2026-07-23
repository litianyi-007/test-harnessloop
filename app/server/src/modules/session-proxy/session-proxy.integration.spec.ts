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
 * D3-proxy 集成测试——不依赖真实 DB（不通过 SessionProxyModule/SessionTokenModule 的
 * TypeOrmModule.forFeature 链路，直接 mock `SessionNewApiTokenMapService`），但用真实的
 * Nest HTTP 层（Express 5 + path-to-regexp v8，同生产 main.ts 一致的路由注册方式）+ 一个
 * 真实的本地 HTTP 服务器充当"假 newapi 上游"，验证：
 *   1. 静态 openclaw→proxy key 校验（缺失/错误均拒绝，且不触达上游）。
 *   2. session→newapi 映射未命中时按默认策略（reject）拒绝，且不触达上游。
 *   3. 命中映射后：Authorization 换成真实 newapi key 转发；响应按 chunk 流式透传（非
 *      整体缓冲）。
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

    const configValues: Record<string, unknown> = {
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
    await app.init();
    await app.listen(0);
    const httpServer = app.getHttpServer() as HttpServer;
    appPort = (httpServer.address() as AddressInfo).port;
  });

  afterEach(async () => {
    await app.close();
  });

  describe('静态 key 校验', () => {
    it('缺失 Authorization 时拒绝（401），不触达上游', async () => {
      const res = await request(app.getHttpServer() as HttpServer)
        .post('/session-proxy/chat/completions')
        .send({ model: 'x' });

      expect(res.status).toBe(401);
      expect((res.body as StructuredErrorBody).code).toBe(
        'session_proxy_unauthorized',
      );
      expect(receivedByUpstream).toHaveLength(0);
    });

    it('Authorization 错误时拒绝（401），不触达上游', async () => {
      const res = await request(app.getHttpServer() as HttpServer)
        .post('/session-proxy/chat/completions')
        .set('Authorization', 'Bearer wrong-key')
        .send({ model: 'x' });

      expect(res.status).toBe(401);
      expect(receivedByUpstream).toHaveLength(0);
    });
  });

  describe('session→newapi 映射未命中兜底', () => {
    it('默认 reject 策略：拒绝转发（502），不触达上游', async () => {
      tokenMap.findActive.mockResolvedValue(null);

      const res = await request(app.getHttpServer() as HttpServer)
        .post('/session-proxy/chat/completions')
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
  });

  describe('命中映射：换凭证转发 + 流式透传', () => {
    it('转发到上游时 Authorization 已换成真实 newapi key，请求体原样透传', async () => {
      tokenMap.findActive.mockResolvedValue({
        newapiKey: 'sk-real-newapi-key',
        newapiTokenId: null,
        tokenGeneration: 1,
      });

      await request(app.getHttpServer() as HttpServer)
        .post('/session-proxy/chat/completions')
        .set('Authorization', `Bearer ${STATIC_KEY}`)
        .set('x-session-affinity', 'sess-abc')
        .send({ model: 'gpt-x', messages: [{ role: 'user', content: 'hi' }] });

      expect(receivedByUpstream).toHaveLength(1);
      const upstreamReq = receivedByUpstream[0];
      expect(upstreamReq.url).toBe('/v1/chat/completions');
      expect(upstreamReq.headers['authorization']).toBe(
        'Bearer sk-real-newapi-key',
      );
      expect(JSON.parse(upstreamReq.body)).toEqual({
        model: 'gpt-x',
        messages: [{ role: 'user', content: 'hi' }],
      });
    });

    it('响应按 chunk 流式透传给调用方，而非整体缓冲后一次性返回', async () => {
      tokenMap.findActive.mockResolvedValue({
        newapiKey: 'sk-real-newapi-key',
        newapiTokenId: null,
        tokenGeneration: 1,
      });

      const events = await new Promise<{ t: number; chunk: string }[]>(
        (resolve, reject) => {
          const collected: { t: number; chunk: string }[] = [];
          const start = Date.now();
          const req = http.request(
            {
              host: '127.0.0.1',
              port: appPort,
              path: '/session-proxy/chat/completions',
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
  });
});
