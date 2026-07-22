import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export type TenantKind = 'personal' | 'enterprise';

/**
 * `tenant`（server-stack-selection.md 六项能力表 #2 多租户）。
 *
 * 注意：这是租户本身的记录，不带 `tenant_id` 列——D3 源文档原文是"`tenant` + 所有业务表
 * `tenant_id`"，`tenant` 自己就是那个 id 的持有者，其余业务表（Membership/Seat/TenantFeature/
 * License 等）才需要外键 `tenantId`。
 *
 * x-todo（openapi.yaml Tenant schema/路径描述）：
 * - 用户可见文案（工作区/组织/团队）未冻结，`name` 字段先用中性命名。
 * - 一账号是否可属于多个 tenant 未确认，本骨架假设单一有效 tenant（见 d5-6-account-license.md §6.4）。
 */
@Entity('tenants')
export class TenantEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', default: 'personal' })
  kind!: TenantKind;

  @Column({ type: 'varchar', nullable: true })
  name!: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
