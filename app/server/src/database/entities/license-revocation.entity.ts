import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * `revocations`（server-stack-selection.md"`licenses` + `revocations` 两张表"，方案 A 明确列出）。
 *
 * **补充实体说明**：任务给定的 6 个必需实体清单（License/Tenant/Seat/Membership/
 * TenantFeature/User）未逐条点名本表，但 `revocations` 是 server-stack-selection.md
 * （design_status: confirmed）原文明确列出的第二张 License 相关表——没有它，
 * "纯离线 JWT 无法即时吊销，需要吊销列表/在线校验"这条 confirmed 结论就无法落地为可编译的骨架
 * （license-jwt.service.ts 的校验逻辑需要查询这张表判断 `jti` 是否已被吊销）。因此本骨架
 * 按已确认来源新增此表，不是臆造契约外字段。
 *
 * 带 `tenant_id`（冗余自所属 License，便于按租户批量吊销/审计查询）。
 */
@Entity('license_revocations')
export class LicenseRevocationEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'license_id', type: 'uuid' })
  licenseId!: string;

  @Index()
  @Column({ name: 'tenant_id', type: 'uuid', nullable: true })
  tenantId!: string | null;

  // License JWT 的 `jti`（JWT ID）——x-todo：签发时是否携带 jti 声明未在源文档确定，
  // license-jwt.service.ts 校验骨架按"若存在 jti 则查表"实现，不强制要求。
  @Index({ unique: true })
  @Column({ name: 'license_jti', type: 'varchar', nullable: true })
  licenseJti!: string | null;

  @CreateDateColumn({ name: 'revoked_at' })
  revokedAt!: Date;

  @Column({ type: 'varchar', nullable: true })
  reason!: string | null;
}
