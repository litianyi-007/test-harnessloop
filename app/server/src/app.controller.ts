import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

/**
 * 健康检查——不属于 D3 契约业务端点面（openapi.yaml 8 组 tag 均不含本路径），
 * 是标准的基础设施探活接口，main.ts 里特意排除在 `api/d3/v1` 业务前缀之外。
 */
@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get('health')
  getHealth() {
    return this.appService.getHealth();
  }
}
