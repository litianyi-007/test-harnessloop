import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { BillingService } from './billing.service';
import {
  BillingQuotaDto,
  NewApiEndpointConfigDto,
  SessionBillingSnapshotDto,
} from './dto/billing.dto';

/** tag: Billing（openapi.yaml）——L1 席位/plan 额度 + L2 newapi 按量用量（经 D3 代理）。 */
@Controller()
export class BillingController {
  constructor(private readonly billingService: BillingService) {}

  /** operationId: getBillingQuota — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('billing/quota')
  getBillingQuota(
    @CurrentUser() user: JwtAccessPayload,
  ): Promise<BillingQuotaDto> {
    return this.billingService.getBillingQuota(user);
  }

  /** operationId: queryBillingUsage — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('billing/usage')
  queryBillingUsage(
    @CurrentUser() user: JwtAccessPayload,
    @Query('sessionId') sessionId?: string,
    @Query('windowStart') windowStart?: string,
    @Query('windowEnd') windowEnd?: string,
  ): Promise<SessionBillingSnapshotDto> {
    return this.billingService.queryBillingUsage(user, {
      sessionId,
      windowStart,
      windowEnd,
    });
  }

  /** operationId: getNewApiEndpointConfig — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('tenant/current/newapi-endpoint-config')
  getNewApiEndpointConfig(): NewApiEndpointConfigDto {
    return this.billingService.getNewApiEndpointConfig();
  }
}
