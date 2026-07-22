import {
  Injectable,
  NotFoundException,
  NotImplementedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MembershipEntity, TenantEntity } from '../../database/entities';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import {
  CreateInvitationResponseDto,
  SeatDto,
  TenantDto,
} from './dto/tenant.dto';

@Injectable()
export class TenantService {
  constructor(
    @InjectRepository(TenantEntity)
    private readonly tenantRepo: Repository<TenantEntity>,
    @InjectRepository(MembershipEntity)
    private readonly membershipRepo: Repository<MembershipEntity>,
  ) {}

  /**
   * 对应 openapi getCurrentTenant——真实 DB 读取（非桩）。
   * x-todo（d5-6-account-license.md §6.4）：一账号是否可属于多个 tenant 未确认，本骨架
   * 假设单一有效工作区，只取第一条 membership。
   */
  async getCurrentTenant(user: JwtAccessPayload): Promise<TenantDto> {
    const membership = await this.membershipRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });
    if (!membership) {
      // 个人 free 用户没有企业 tenant 概念（openapi Tenant.kind description）。
      return { kind: 'personal', id: null, name: null };
    }
    const tenant = await this.tenantRepo.findOne({
      where: { id: membership.tenantId },
    });
    return {
      kind: 'enterprise',
      id: tenant?.id ?? null,
      name: tenant?.name ?? null,
    };
  }

  /** 对应 openapi getCurrentSeat——真实 DB 读取（非桩）。 */
  async getCurrentSeat(user: JwtAccessPayload): Promise<SeatDto> {
    const membership = await this.membershipRepo.findOne({
      where: { userId: user.sub },
      order: { createdAt: 'DESC' },
    });
    if (!membership) {
      // "个人 free 用户无 seat/membership 概念"（openapi 404 description）。
      throw new NotFoundException({
        code: 'no_seat',
        message: '个人 free 用户无 seat/membership 概念。',
      });
    }
    return {
      tenantId: membership.tenantId,
      role: membership.role,
      status: membership.status,
    };
  }

  /**
   * 对应 openapi createInvitation。是否需要管理员审批、用户如何被通知——均未能确认
   * （x-todo #8，见 d5-6-account-license.md §4.3/§5.3/§9），且本骨架未建 Invitation
   * 持久化实体（不在任务给定的 6 实体清单内）——如实报告未实现，不生成一个不会被
   * 持久化/审批的"假邀请"。
   */
  createInvitation(_user: JwtAccessPayload): CreateInvitationResponseDto {
    throw new NotImplementedException({
      code: 'invitation_flow_undecided',
      message:
        '邀请审批/通知机制未能确认（见 d5-6-account-license.md §4.3/§5.3/§9），' +
        '且 Invitation 持久化实体不在本轮 TypeORM 实体范围内，本骨架不臆造具体行为。',
    });
  }
}
