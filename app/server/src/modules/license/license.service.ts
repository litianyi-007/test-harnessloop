import {
  Injectable,
  NotFoundException,
  NotImplementedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { LicenseEntity } from '../../database/entities';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { LicenseDto, LicensePublicKeyResponseDto } from './dto/license.dto';
import { LicenseJwtService } from './license-jwt.service';

@Injectable()
export class LicenseService {
  constructor(
    @InjectRepository(LicenseEntity)
    private readonly licenseRepo: Repository<LicenseEntity>,
    private readonly licenseJwtService: LicenseJwtService,
  ) {}

  /**
   * 对应 openapi getCurrentLicense——真实 DB 读取（非桩），个人 free 用户同样应持有一份
   * `plan=free` License（server-stack-selection.md P0 阶段说明）。当前骨架未接入任何
   * "登录即自动签发 free license"的 onboarding 流程（不在本轮契约端点范围内），
   * 因此全新用户查无记录时如实返回 404 `no_license`——这是 openapi 本身定义的响应分支
   * （d5-6-account-license.md §4.2 标注为"异常态，正常流程不应停留于此"）。
   */
  async getCurrentLicense(user: JwtAccessPayload): Promise<LicenseDto> {
    const license = await this.licenseRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });
    if (!license) {
      throw new NotFoundException({
        code: 'no_license',
        message: '登录成功但账号未绑定任何 license。',
      });
    }
    return this.toDto(license);
  }

  /**
   * 对应 openapi refreshLicense。是否存在 grace_period 中间态、强制在线刷新的具体策略——
   * 均为待产品+安全决策的开放项（openapi License.status description），本骨架不臆造，
   * 如实报告未实现。
   */
  refreshLicense(_user: JwtAccessPayload): never {
    throw new NotImplementedException({
      code: 'license_refresh_policy_undecided',
      message:
        '离线宽限/强制在线刷新策略整体待产品+安全决策（见 openapi License.status ' +
        'description、server-stack-selection.md 不确定与风险第 3 条），本骨架不臆造具体机制。',
    });
  }

  /** 对应 openapi getLicensePublicKey——真实实现，见 LicenseJwtService。 */
  getPublicKey(): Promise<LicensePublicKeyResponseDto> {
    return this.licenseJwtService.getPublicKeyInfo();
  }

  private toDto(license: LicenseEntity): LicenseDto {
    return {
      plan: license.plan,
      entitlements: license.entitlements,
      exp: license.exp?.toISOString(),
      status: license.status,
      tenantId: license.tenantId,
    };
  }
}
