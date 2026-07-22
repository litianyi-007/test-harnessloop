import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

export type AuthMethod = 'browser_oauth' | 'license_key';

/**
 * 认证身份（"我是谁"）——对应 openapi `MeResponse`。
 * D1/D2 协议里没有原生对应，纯应用层认证凭证的持有者
 * （d5-6-account-license.md §2 命名映射表"账号/登录身份"行）。
 *
 * `currentTenantId`：x-todo（d5-6-account-license.md §6.4）——一账号是否可属于多个 tenant
 * 未确认，本骨架按"假设主路径为单一有效工作区上下文"存这一个当前 tenant 外键；
 * 若未来确认支持多 tenant，需要改为独立的 user-tenant 多对多关系，本字段届时废弃/迁移。
 */
@Entity('users')
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', nullable: true, unique: true })
  email!: string | null;

  @Column({ name: 'display_name', type: 'varchar', nullable: true })
  displayName!: string | null;

  @Column({ name: 'auth_method', type: 'varchar', nullable: true })
  authMethod!: AuthMethod | null;

  @Column({ name: 'current_tenant_id', type: 'uuid', nullable: true })
  currentTenantId!: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
