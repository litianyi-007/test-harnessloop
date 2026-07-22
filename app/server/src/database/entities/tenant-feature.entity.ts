import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * `tenant_features` / `feature_flags`（server-stack-selection.md 六项能力表 #4 能力开关）。
 * JSONB `entitlements`——对应 openapi `FeatureFlags.flags`。原文明确"客户端拉取配置；
 * 不必等于 new-api 模型权限（可叠加）"——这是租户维度的 allowed 层准入开关，
 * 与 D1 `CapabilityDescriptor`（active 层）是两套独立机制（d5-5-capabilities.md §4.0）。
 *
 * 带 `tenant_id`（server-stack-selection.md"所有业务表 tenant_id"）。
 *
 * x-todo：具体 flag 命名/取值集未在 D3 定义，本实体不预设结构，`flags` 按需扩展。
 */
@Entity('tenant_features')
export class TenantFeatureEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'tenant_id', type: 'uuid', unique: true })
  tenantId!: string;

  @Column({ type: 'jsonb', default: {} })
  flags!: Record<string, unknown>;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
