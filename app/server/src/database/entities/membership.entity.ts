import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export type MembershipStatus = 'invited' | 'active' | 'suspended' | 'removed';

/**
 * `membership`（server-stack-selection.md 六项能力表 #3；role/状态）——单个用户在单个租户下的
 * 成员关系，对应 openapi `Seat` schema（`tenantId`/`role`/`status`，命名沿用 openapi 契约，
 * 与本仓 SeatEntity 是"租户容量" vs "个人成员关系"两个不同粒度，见 seat.entity.ts 头注释）。
 *
 * 带 `tenant_id`（server-stack-selection.md"所有业务表 tenant_id"）。
 *
 * x-todo：
 * - `role` 具体枚举未在 D3/D5.6 定义（openapi Seat.role x-todo），先用自由字符串。
 * - `suspended`/`removed` 状态变更的实时传播机制未确认（d5-6-account-license.md §6.3）。
 */
@Entity('memberships')
export class MembershipEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'tenant_id', type: 'uuid' })
  tenantId!: string;

  @Index()
  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ type: 'varchar', default: 'member' })
  role!: string;

  @Column({ type: 'varchar', default: 'invited' })
  status!: MembershipStatus;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
