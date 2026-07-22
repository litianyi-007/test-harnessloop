import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import {
  CreateInvitationResponseDto,
  SeatDto,
  TenantDto,
} from './dto/tenant.dto';
import { TenantService } from './tenant.service';

/** tag: TenantSeat（openapi.yaml）——租户/坐席/角色只读呈现 + 邀请发起。 */
@Controller()
export class TenantController {
  constructor(private readonly tenantService: TenantService) {}

  /** operationId: getCurrentTenant — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('tenant/current')
  getCurrentTenant(@CurrentUser() user: JwtAccessPayload): Promise<TenantDto> {
    return this.tenantService.getCurrentTenant(user);
  }

  /** operationId: getCurrentSeat — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('tenant/current/seat')
  getCurrentSeat(@CurrentUser() user: JwtAccessPayload): Promise<SeatDto> {
    return this.tenantService.getCurrentSeat(user);
  }

  /** operationId: createInvitation — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Post('tenant/current/invitations')
  @HttpCode(HttpStatus.CREATED)
  createInvitation(
    @CurrentUser() user: JwtAccessPayload,
  ): CreateInvitationResponseDto {
    return this.tenantService.createInvitation(user);
  }
}
