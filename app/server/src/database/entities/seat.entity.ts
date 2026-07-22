import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * `seat`（server-stack-selection.md 六项能力表 #3 收费坐席）——租户级坐席容量配置。
 * P0 阶段原文："P0 用 `memberships` + `seat_limit`"，即坐席容量（`seat_limit`）与
 * 个人成员关系（membership，见 membership.entity.ts）是两个不同粒度的概念：
 * 本实体持有"这个租户一共能开多少个坐席"，MembershipEntity 持有"具体某个用户在这个租户下
 * 的角色/状态"。两者按 `tenantId` 关联，不建外键约束（P0 骨架从简，迁移见 TODO）。
 *
 * 带 `tenant_id`（server-stack-selection.md"所有业务表 tenant_id"）。
 */
@Entity('seats')
export class SeatEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'tenant_id', type: 'uuid', unique: true })
  tenantId!: string;

  // x-todo：调额/坐席数变更的传播机制未定（d5-6-account-license.md §6.3/§9）
  @Column({ name: 'seat_limit', type: 'int' })
  seatLimit!: number;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
