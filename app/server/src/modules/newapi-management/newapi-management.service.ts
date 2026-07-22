import { Injectable } from '@nestjs/common';
import { NewApiClientService } from '../newapi/newapi-client.service';
import {
  CreateTenantNewApiTokenRequestDto,
  NewApiModelChannelDto,
  NewApiTokenAdminDto,
  NewApiUsageLogEntryDto,
} from './dto/newapi-management.dto';

/**
 * newapi Management API 的 D3 代理面（server/console 用：token/channel/用量对账，
 * 见 d6-newapi-integration.md §4）——与 SessionToken 分组的 per-session token 是
 * **两类不同的 token**：本模块服务 Console 侧的租户级 token 生命周期管理，不是
 * D6 §3 注入链的一部分。
 */
@Injectable()
export class NewApiManagementService {
  constructor(private readonly newApiClient: NewApiClientService) {}

  /** 对应 openapi createTenantNewApiToken（按租户/坐席创建 newapi token，admin/console 用）。 */
  createTenantNewApiToken(
    tenantId: string,
    dto: CreateTenantNewApiTokenRequestDto,
  ): Promise<NewApiTokenAdminDto> {
    return this.newApiClient.createTenantToken(tenantId, dto.quota, dto.note);
  }

  /** 对应 openapi revokeTenantNewApiToken（吊销租户级 newapi token）。 */
  revokeTenantNewApiToken(tokenId: string): Promise<void> {
    return this.newApiClient.revokeTenantToken(tokenId);
  }

  /** 对应 openapi getNewApiUsageLogs（用量/日志对账查询，admin 全站）。 */
  async getNewApiUsageLogs(filters: {
    tenantId?: string;
    tokenName?: string;
    since?: string;
    until?: string;
  }): Promise<{ entries: NewApiUsageLogEntryDto[] }> {
    const entries = await this.newApiClient.getUsageLogs(filters);
    return { entries };
  }

  /** 对应 openapi getNewApiModels（newapi 渠道/模型目录）。 */
  async getNewApiModels(): Promise<{ channels: NewApiModelChannelDto[] }> {
    const channels = await this.newApiClient.getModelChannels();
    return { channels };
  }
}
