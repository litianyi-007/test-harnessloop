import { All, Controller, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { SessionProxyService } from './session-proxy.service';

/**
 * D3-proxy 对外暴露的反向代理入口——不是 openapi.yaml 8 组 tag 之一的"契约业务端点"
 * （JWT bearer 鉴权 + 结构化 DTO），而是 openclaw→newapi 的透传通道：静态部署凭证鉴权，
 * 原样转发任意 OpenAI-completions 兼容路径（`chat/completions`/`completions`/... 均由
 * 下方通配路由统一处理，不逐一枚举），响应含流式 SSE。因此**不**加 `JwtAuthGuard`——
 * 鉴权方式是 `SessionProxyService` 内部校验的静态 openclaw→proxy key（见该 service
 * `assertStaticAuth`），与其它模块"登录用户 JWT"是两套完全不同的鉴权语义，不应混用
 * 同一个 Guard。
 *
 * **挂载路径**：随 `main.ts` 既有全局前缀落在 `{host}/api/d3/v1/session-proxy/*`。本次
 * 实现选择不去折腾 `setGlobalPrefix` 的 wildcard `exclude`——该机制在不同 path-to-regexp
 * 版本间（本仓库锁定 v8，Express 5）行为不完全一致，属于不必要的额外风险面，收益
 * （路径"更好看"）不足以抵消。openclaw 侧部署配置 provider baseUrl 时按这个完整路径
 * 填写（如 `https://<host>/api/d3/v1/session-proxy`）即可，功能不受影响。
 */
@Controller('session-proxy')
export class SessionProxyController {
  constructor(private readonly sessionProxyService: SessionProxyService) {}

  @All('*splat')
  async forward(@Req() req: Request, @Res() res: Response): Promise<void> {
    await this.sessionProxyService.forward(req, res);
  }
}
