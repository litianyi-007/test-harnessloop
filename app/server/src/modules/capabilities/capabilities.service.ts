import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MembershipEntity, TenantFeatureEntity } from '../../database/entities';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { FeatureFlagsDto } from './dto/feature-flags.dto';

@Injectable()
export class CapabilitiesService {
  constructor(
    @InjectRepository(TenantFeatureEntity)
    private readonly tenantFeatureRepo: Repository<TenantFeatureEntity>,
    @InjectRepository(MembershipEntity)
    private readonly membershipRepo: Repository<MembershipEntity>,
  ) {}

  /**
   * 对应 openapi getFeatureFlags——真实 DB 读取（非桩）。这是租户维度的 allowed 层准入开关，
   * 与 D1 `CapabilityDescriptor`（active 层）是两套独立机制，会叠加生效
   * （d5-5-capabilities.md §4.0，本骨架只实现 allowed 层这一半）。
   */
  async getFeatureFlags(user: JwtAccessPayload): Promise<FeatureFlagsDto> {
    const membership = await this.membershipRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });
    if (!membership) {
      // 个人 free 用户无租户，暂无 tenant_features 记录可拉取。
      return { flags: {} };
    }
    const tenantFeature = await this.tenantFeatureRepo.findOne({
      where: { tenantId: membership.tenantId },
    });
    return { flags: tenantFeature?.flags ?? {} };
  }
}
