import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import {
  CreateTenantNewApiTokenRequestDto,
  NewApiModelChannelDto,
  NewApiTokenAdminDto,
  NewApiUsageLogEntryDto,
} from './dto/newapi-management.dto';
import { NewApiManagementService } from './newapi-management.service';

/** tag: NewApiManagement（openapi.yaml）——newapi Management API 的 D3 代理面。 */
@UseGuards(JwtAuthGuard)
@Controller()
export class NewApiManagementController {
  constructor(
    private readonly newApiManagementService: NewApiManagementService,
  ) {}

  /** operationId: createTenantNewApiToken — openapi 全局 bearerAuth（无覆盖）。 */
  @Post('admin/tenants/:tenantId/newapi-tokens')
  @HttpCode(HttpStatus.CREATED)
  createTenantNewApiToken(
    @Param('tenantId') tenantId: string,
    @Body() dto: CreateTenantNewApiTokenRequestDto,
  ): Promise<NewApiTokenAdminDto> {
    return this.newApiManagementService.createTenantNewApiToken(tenantId, dto);
  }

  /** operationId: revokeTenantNewApiToken — openapi 全局 bearerAuth（无覆盖）。 */
  @Delete('admin/newapi-tokens/:tokenId')
  @HttpCode(HttpStatus.NO_CONTENT)
  revokeTenantNewApiToken(@Param('tokenId') tokenId: string): Promise<void> {
    return this.newApiManagementService.revokeTenantNewApiToken(tokenId);
  }

  /** operationId: getNewApiUsageLogs — openapi 全局 bearerAuth（无覆盖）。 */
  @Get('admin/newapi/usage-logs')
  getNewApiUsageLogs(
    @Query('tenantId') tenantId?: string,
    @Query('tokenName') tokenName?: string,
    @Query('since') since?: string,
    @Query('until') until?: string,
  ): Promise<{ entries: NewApiUsageLogEntryDto[] }> {
    return this.newApiManagementService.getNewApiUsageLogs({
      tenantId,
      tokenName,
      since,
      until,
    });
  }

  /** operationId: getNewApiModels — openapi 全局 bearerAuth（无覆盖）。 */
  @Get('admin/newapi/models')
  getNewApiModels(): Promise<{ channels: NewApiModelChannelDto[] }> {
    return this.newApiManagementService.getNewApiModels();
  }
}
