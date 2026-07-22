import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { LicenseEntity, MembershipEntity } from '../../database/entities';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { NewApiClientService } from '../newapi/newapi-client.service';
import {
  BillingQuotaDto,
  NewApiEndpointConfigDto,
  SessionBillingSnapshotDto,
} from './dto/billing.dto';

@Injectable()
export class BillingService {
  constructor(
    @InjectRepository(LicenseEntity)
    private readonly licenseRepo: Repository<LicenseEntity>,
    @InjectRepository(MembershipEntity)
    private readonly membershipRepo: Repository<MembershipEntity>,
    private readonly newApiClient: NewApiClientService,
    private readonly config: ConfigService,
  ) {}

  /**
   * 对应 openapi getBillingQuota（L1 席位/plan 额度，d5-4-cost-usage.md §2.2）——真实 DB
   * 读取（非桩）：个人免费 tier 与企业按坐席共用同一形状，企业分支 `seat` 有值，个人分支为 null。
   */
  async getBillingQuota(user: JwtAccessPayload): Promise<BillingQuotaDto> {
    const license = await this.licenseRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });
    const membership = await this.membershipRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });

    return {
      license: license
        ? {
            plan: license.plan,
            entitlements: license.entitlements,
            exp: license.exp?.toISOString(),
            status: license.status,
            tenantId: license.tenantId,
          }
        : undefined,
      seat: membership
        ? {
            tenantId: membership.tenantId,
            role: membership.role,
            status: membership.status,
          }
        : null,
    };
  }

  /**
   * 对应 openapi queryBillingUsage（L2 newapi 按量用量，经 D3 代理）。
   *
   * **为什么这里选 `NotImplementedException` 而不是返回一个"看起来完整"的 mock**：
   * d5-4-cost-usage.md §4.4 强约束——"不得静默展示一个字段齐全但数值虚构/为零的
   * `SessionBillingSnapshot`"，"查询成功但用量为 0"与"查询失败"必须走独立响应路径。
   * 本骨架尚未真正接入 newapi（见 NewApiClientService.queryUsage 注释里列出的具体缺口），
   * 若在此处返回一个 requestCount=0/totalQuota=0 的假快照，会被 UI 误读为"这个部署真的
   * 没有用量"，这正是该强约束明确禁止的行为——因此如实抛错，而不是"看起来实现了"。
   *
   * TODO（生产实现）：真正接入后，内部失败应映射为 openapi 定义的 502
   * `billing_query_subject_unresolved`，而不是这里骨架阶段的 501。
   */
  queryBillingUsage(
    _user: JwtAccessPayload,
    params: { sessionId?: string; windowStart?: string; windowEnd?: string },
  ): Promise<SessionBillingSnapshotDto> {
    return this.newApiClient.queryUsage(params);
  }

  /**
   * 对应 openapi getNewApiEndpointConfig——`baseUrl` 为部署时静态配置（真实实现，读 env）；
   * `deploymentTokenRef` 取值取决于 path①/path② 与 openclaw/hermes patch 落地状态
   * （见 d6-newapi-integration.md §2.2 v3 收口、主仓库 goal SG-6/SG-7），本骨架阶段
   * 该字段固定返回 `null` 并标 TODO，不冒充已裁决的部署状态。
   */
  getNewApiEndpointConfig(): NewApiEndpointConfigDto {
    return {
      baseUrl: this.config.get<string>('newapi.baseUrl') ?? '',
      // TODO：path②(aggregate) 下必填，取值来自部署配置；path①下可省略。
      // 当前依 SG-6(openclaw patch)/SG-7(hermes 接线) 落地状态决定，骨架阶段先固定 null。
      deploymentTokenRef: null,
    };
  }
}
