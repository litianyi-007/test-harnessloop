import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * openapi `License.status` 枚举。`grace_period` 是 d5-6-account-license.md §4.2 的产品提案，
 * **不是** D3 confirmed 存在此机制——本实体仍收录该值以覆盖两种可能性，是否启用待产品+安全决策
 * （见 openapi.yaml License schema description 原文诚实标注，此处不重复整段搬运）。
 */
export type LicenseStatus =
  | 'no_license'
  | 'pending_activation'
  | 'active'
  | 'expiring_soon'
  | 'grace_period'
  | 'expired'
  | 'revoked';

/**
 * `license`（server-stack-selection.md 六项能力表 #1）——应用内签发 Ed25519 JWT，
 * `plan`/`entitlements`/`exp`/`status`，配 `licenses` + `revocations` 两张表
 * （本骨架的 revocations 见 license-revocation.entity.ts）。
 *
 * 带 `tenant_id`（server-stack-selection.md"所有业务表 tenant_id"）——
 * 个人 free license 的 `tenantId` 为 null（openapi License.tenantId 说明"企业坐席绑定的
 * tenant；个人 free license 为 null"）。
 *
 * x-todo：
 * - `plan` 具体枚举值未定死（P0 阶段只提到"个人 free / 企业 paid plan"），先用自由字符串。
 * - 离线宽限/强制在线刷新策略整体待产品+安全决策（见 `status` 类型注释）。
 */
@Entity('licenses')
export class LicenseEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'tenant_id', type: 'uuid', nullable: true })
  tenantId!: string | null;

  // 个人 free license 绑定到具体用户；企业 license 通过 tenantId + membership 间接关联用户。
  @Index()
  @Column({ name: 'user_id', type: 'uuid', nullable: true })
  userId!: string | null;

  @Column({ type: 'varchar', default: 'free' })
  plan!: string;

  @Column({ type: 'jsonb', default: {} })
  entitlements!: Record<string, unknown>;

  @Column({ type: 'timestamptz' })
  exp!: Date;

  @Column({ type: 'varchar', default: 'active' })
  status!: LicenseStatus;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
