import { Module } from '@nestjs/common';
import { SessionTokenModule } from '../session-token/session-token.module';
import { SessionProxyController } from './session-proxy.controller';
import { SessionProxyService } from './session-proxy.service';

/**
 * SG-6（C-3 path① session 级计费归因）的 D3-proxy 实质工作——openclaw 侧按
 * sg6-openclaw-persession-patch-design.md §5.1 配置的 `sendSessionAffinityHeaders`
 * provider，把每个 session 的模型请求打到本模块；本模块按请求头里的 sessionId 换上该
 * session 专属的 newapi 计费凭证后转发给 newapi 上游（含流式）。
 *
 * 复用 `session-token` 模块导出的 `SessionNewApiTokenMapService`（D3 自己维护的
 * session→newapi-token 映射，d6-newapi-integration.md §3.1/§4.2 职责4）做查表，不重复
 * 建表/建 service。
 */
@Module({
  imports: [SessionTokenModule],
  controllers: [SessionProxyController],
  providers: [SessionProxyService],
})
export class SessionProxyModule {}
