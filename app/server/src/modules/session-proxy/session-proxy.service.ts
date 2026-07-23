import { timingSafeEqual } from 'crypto';
import type { IncomingHttpHeaders } from 'http';
import { Readable } from 'stream';
import { pipeline } from 'stream/promises';
import type { ReadableStream as NodeWebReadableStream } from 'stream/web';
import {
  BadGatewayException,
  Injectable,
  InternalServerErrorException,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import { SessionNewApiTokenMapService } from '../session-token/session-newapi-token-map.service';
import {
  CLIENT_REQUEST_ID_HEADER,
  SESSION_AFFINITY_HEADER,
  SESSION_ID_HEADER,
  SESSION_PROXY_MOUNT_PATH,
  STRIPPED_REQUEST_HEADERS,
  STRIPPED_RESPONSE_HEADERS,
} from './session-proxy.constants';

/**
 * D3-proxy 核心转发逻辑——SG-6(C-3 path① session 级计费归因)的实质工作。
 *
 * openclaw 侧按 sg6-openclaw-persession-patch-design.md §5.1 配置的
 * `sendSessionAffinityHeaders` provider，把每个 session 的模型请求打到本 service（携带
 * 静态部署级 `Authorization` + `x-session-affinity`/`session_id`/`x-client-request-id`
 * 三个等价 header，值均为 sessionId）。本 service：
 *   1. 校验静态 openclaw→proxy key（先于任何 sessionId 解析——sessionId 不是凭证）。
 *   2. 读 sessionId，在 D3 自己的 session→newapi-token 映射（`SessionNewApiTokenMapService`）
 *      里查出该 session 对应的真实 newapi 凭证。
 *   3. 未命中时按可配置策略处理（默认拒绝+结构化日志，见 `resolveNewApiKey`）。
 *   4. 换凭证转发给 newapi 上游，流式透传响应（含 SSE）。
 *
 * 安全纪律：newapi 真实 key 只存在于本进程内存/DB，绝不回显给 openclaw、绝不写入日志
 * （下方所有 `Logger` 调用均只记 sessionId/状态码/目标 host，不记任何 header 明文）。
 */
@Injectable()
export class SessionProxyService {
  private readonly logger = new Logger(SessionProxyService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly tokenMap: SessionNewApiTokenMapService,
  ) {}

  async forward(req: Request, res: Response): Promise<void> {
    this.assertStaticAuth(req);

    const sessionId = this.extractSessionId(req);
    const newapiKey = await this.resolveNewApiKey(sessionId);

    await this.proxyToNewApi(req, res, newapiKey, sessionId);
  }

  /**
   * 步骤1：先校验 openclaw→proxy 的静态部署凭证，确认请求确实来自合法部署的 openclaw
   * 网关实例——这一步必须先于读取 sessionId（sg6 doc §5.2 第1条：sessionId 本身不是
   * 凭证，不能仅凭它出现就授予任何转发权限）。
   */
  private assertStaticAuth(req: Request): void {
    const expectedKey = this.config.get<string>('sessionProxy.staticAuthKey');
    if (!expectedKey) {
      // fail-closed：未配置静态 key 时拒绝一切请求，而不是"没配置就放行"。
      this.logger.error(
        'session-proxy 未配置 SESSION_PROXY_STATIC_AUTH_KEY，按 fail-closed 拒绝所有请求',
      );
      throw new InternalServerErrorException({
        code: 'session_proxy_misconfigured',
        message: 'D3-proxy 静态鉴权凭证未配置，无法校验请求来源',
      });
    }

    if (!this.isValidStaticKey(req.headers['authorization'], expectedKey)) {
      this.logger.warn('session-proxy 收到静态鉴权失败的请求，已拒绝转发');
      throw new UnauthorizedException({
        code: 'session_proxy_unauthorized',
        message: 'invalid or missing openclaw->proxy static Authorization key',
      });
    }
  }

  private isValidStaticKey(
    authHeader: string | string[] | undefined,
    expectedKey: string,
  ): boolean {
    if (typeof authHeader !== 'string') return false;
    const match = /^Bearer\s+(.+)$/i.exec(authHeader);
    if (!match) return false;

    const providedBuf = Buffer.from(match[1]);
    const expectedBuf = Buffer.from(expectedKey);
    // 长度不同时 timingSafeEqual 会抛错，先短路；这里泄露的只是"长度是否匹配"这一比特
    // 信息，可接受（同 bcrypt/jwt 校验的通行做法一致）。
    if (providedBuf.length !== expectedBuf.length) return false;
    return timingSafeEqual(providedBuf, expectedBuf);
  }

  /**
   * 步骤2：读 `x-session-affinity`（或等价的 `session_id`/`x-client-request-id`，
   * sg6 doc 确认三者同值）取得 sessionId。
   */
  private extractSessionId(req: Request): string | null {
    const candidates: (string | string[] | undefined)[] = [
      req.headers[SESSION_AFFINITY_HEADER],
      req.headers[SESSION_ID_HEADER],
      req.headers[CLIENT_REQUEST_ID_HEADER],
    ];
    for (const candidate of candidates) {
      if (typeof candidate === 'string' && candidate.length > 0) {
        return candidate;
      }
      if (Array.isArray(candidate) && candidate.length > 0 && candidate[0]) {
        return candidate[0];
      }
    }
    return null;
  }

  /**
   * 步骤2/3：查 D3 自己的 session→newapi-token 映射；未命中时按 §4 条"未映射兜底"策略
   * 处理——默认 `reject`（结构化日志 + 明确拒绝，不静默把请求归到任意计费主体）；
   * 可切换为 `aggregate`（降级到部署级聚合计费 key，需显式配置
   * `SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY`，否则同样 fail-closed 拒绝，不允许
   * 无凭证放行）。这是 d6-newapi-integration.md §2.2 path②（aggregate）在 session-proxy
   * 层面的落点；D6/sg6 均未对"D3-proxy 侧未命中映射时具体怎么办"给出定论
   * （sg6 doc §5.2 第4条"本页不代其裁决"），本实现按任务 brief 要求取最安全默认。
   */
  private async resolveNewApiKey(sessionId: string | null): Promise<string> {
    if (sessionId) {
      const mapped = await this.tokenMap.findActive(sessionId);
      if (mapped) return mapped.newapiKey;
    }

    const policy =
      this.config.get<string>('sessionProxy.unmappedSessionPolicy') ?? 'reject';

    if (policy === 'aggregate') {
      const aggregateKey = this.config.get<string>(
        'sessionProxy.aggregateFallbackNewApiKey',
      );
      if (aggregateKey) {
        this.logger.warn(
          `session-proxy: sessionId=${sessionId ?? '(missing)'} 未命中 session→newapi 映射，` +
            '按已配置的 aggregate 兜底策略降级为聚合计费主体转发——本次调用将无法归因到具体 session。',
        );
        return aggregateKey;
      }
      this.logger.error(
        `session-proxy: sessionId=${sessionId ?? '(missing)'} 未命中映射，兜底策略配置为 ` +
          'aggregate 但未设置 SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY，fail-closed 拒绝' +
          '（不允许无凭证放行）。',
      );
      throw new BadGatewayException({
        code: 'session_proxy_aggregate_fallback_unconfigured',
        message:
          '兜底策略为 aggregate 但聚合计费 key 未配置，已拒绝转发（可切换为 reject 或补配 ' +
          'SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY）。',
      });
    }

    // 默认分支：reject。
    this.logger.warn(
      `session-proxy: sessionId=${sessionId ?? '(missing)'} 未命中 session→newapi 映射，` +
        '按默认策略（reject）拒绝转发。可切换为 aggregate（见 ' +
        'SESSION_PROXY_UNMAPPED_SESSION_POLICY 配置），切换前需先配置聚合计费兜底 key。',
    );
    throw new BadGatewayException({
      code: 'session_billing_mapping_unresolved',
      message:
        'sessionId 未能映射到有效的 newapi 凭证，已按默认安全策略拒绝转发（可切换为聚合' +
        '计费兜底，见 SESSION_PROXY_UNMAPPED_SESSION_POLICY 配置）。',
    });
  }

  /**
   * 步骤4：换凭证转发给 newapi 上游，流式透传响应（关键：不缓冲整个响应体，逐 chunk
   * 转发，正确支持 SSE）。用 Node 原生 `fetch`（Node 22 全局可用）发起上游请求，
   * `Readable.fromWeb` 把 Web Streams 的响应体转成 Node stream 后 `pipeline` 到 Express
   * 的 `res`（`res` 本身是可写流），全程不做 `await response.text()`/`arrayBuffer()`
   * 这类会整体缓冲的操作。
   */
  private async proxyToNewApi(
    req: Request,
    res: Response,
    newapiKey: string,
    sessionId: string | null,
  ): Promise<void> {
    const baseUrl = this.config.get<string>('newapi.baseUrl');
    if (!baseUrl) {
      this.logger.error('session-proxy: newapi.baseUrl 未配置，无法转发');
      throw new BadGatewayException({
        code: 'session_proxy_upstream_unconfigured',
        message: 'newapi baseUrl 未配置',
      });
    }
    const completionsBasePath =
      this.config.get<string>('newapi.completionsBasePath') ?? '/v1';
    const targetUrl = `${baseUrl.replace(/\/$/, '')}${completionsBasePath}${this.stripMountPrefix(req.originalUrl)}`;

    const outboundHeaders = this.buildOutboundHeaders(req.headers, newapiKey);
    const method = req.method;
    const hasBody = method !== 'GET' && method !== 'HEAD';
    // req.body 已被 Nest/express 默认 body-parser（application/json）解析为对象——这里原样
    // 重新序列化转发，不改写任何业务字段。x-todo：这不是零拷贝的原始 body 流式转发（大 body
    // 场景有一次额外的解析/再序列化开销），但对 chat completions 这类有界大小的请求体是
    // 可接受的简化；本实现的"流式"重点在响应侧（见下方），不在请求体侧。
    const body = hasBody ? JSON.stringify(req.body ?? {}) : undefined;

    // 客户端断开连接时中止上游请求，避免资源泄漏。
    const abortController = new AbortController();
    req.on('close', () => abortController.abort());

    let upstreamResponse: globalThis.Response;
    try {
      upstreamResponse = await fetch(targetUrl, {
        method,
        headers: outboundHeaders,
        body,
        signal: abortController.signal,
      });
    } catch (err) {
      this.logger.error(
        `session-proxy: 转发到 newapi 上游失败 sessionId=${sessionId ?? '(missing)'} ` +
          `target=${this.redactUrl(targetUrl)}: ${(err as Error).message}`,
      );
      throw new BadGatewayException({
        code: 'session_proxy_upstream_unreachable',
        message: 'newapi 上游不可达',
      });
    }

    res.status(upstreamResponse.status);
    upstreamResponse.headers.forEach((value, key) => {
      if (!STRIPPED_RESPONSE_HEADERS.has(key.toLowerCase())) {
        res.setHeader(key, value);
      }
    });

    if (!upstreamResponse.body) {
      res.end();
      return;
    }

    try {
      // fetch 的全局 Response.body（lib.dom 的 ReadableStream 类型）与 Node
      // `Readable.fromWeb` 期望的 `node:stream/web` ReadableStream 结构等价但类型声明
      // 不同源，需要一次显式类型转换（不是 `any` 逃逸，转换目标是具体的 Node 类型）。
      const nodeStream = Readable.fromWeb(
        upstreamResponse.body as unknown as NodeWebReadableStream<Uint8Array>,
      );
      await pipeline(nodeStream, res);
    } catch (err) {
      this.logger.error(
        `session-proxy: 流式转发中断 sessionId=${sessionId ?? '(missing)'}: ${(err as Error).message}`,
      );
      if (!res.writableEnded) res.end();
    }
  }

  private stripMountPrefix(originalUrl: string): string {
    if (originalUrl.startsWith(SESSION_PROXY_MOUNT_PATH)) {
      return originalUrl.slice(SESSION_PROXY_MOUNT_PATH.length) || '/';
    }
    return originalUrl;
  }

  private buildOutboundHeaders(
    reqHeaders: IncomingHttpHeaders,
    newapiKey: string,
  ): Record<string, string> {
    const headers: Record<string, string> = {};
    for (const [key, value] of Object.entries(reqHeaders)) {
      if (value === undefined) continue;
      if (STRIPPED_REQUEST_HEADERS.has(key.toLowerCase())) continue;
      headers[key] = Array.isArray(value) ? value.join(', ') : value;
    }
    // 换凭证：静态 openclaw→proxy key → 该 session 真实 newapi key。newapi 真实 key 全程
    // 不出现在任何日志里（见类头注释）。
    headers['authorization'] = `Bearer ${newapiKey}`;
    if (!headers['content-type']) {
      headers['content-type'] = 'application/json';
    }
    return headers;
  }

  /** 日志脱敏：只留 host+path，不带 query string（谨慎起见，即便当前未预期敏感 query）。 */
  private redactUrl(url: string): string {
    return url.split('?')[0];
  }
}
