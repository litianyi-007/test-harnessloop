import { Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';
import { NewApiClientService } from './newapi-client.service';

/**
 * D6 安全默认（方案 B）下唯一持有 newapi 凭证、直接调用其 Management API 的模块——
 * billing/session-token/newapi-management 均导入本模块消费 `NewApiClientService`，
 * 不各自重复实现 HTTP client。见 newapi-client.service.ts 头注释。
 */
@Module({
  imports: [HttpModule],
  providers: [NewApiClientService],
  exports: [NewApiClientService],
})
export class NewApiModule {}
