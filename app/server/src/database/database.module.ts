import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  LicenseEntity,
  LicenseRevocationEntity,
  MembershipEntity,
  SeatEntity,
  TenantEntity,
  TenantFeatureEntity,
  UserEntity,
} from './entities';

/**
 * PostgreSQL + 共享 schema 多租户（server-stack-selection.md 方案 A）。
 *
 * `synchronize` 只在非生产环境启用，作为骨架阶段的开发期便利——**迁移文件本身是 TODO**
 * （任务范围明确"迁移可留 TODO"），生产环境落地前必须换成 TypeORM migration，
 * 不应依赖 `synchronize: true` 做 schema 演进。
 */
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres' as const,
        host: config.get<string>('database.host'),
        port: config.get<number>('database.port'),
        username: config.get<string>('database.username'),
        password: config.get<string>('database.password'),
        database: config.get<string>('database.database'),
        entities: [
          TenantEntity,
          UserEntity,
          SeatEntity,
          MembershipEntity,
          TenantFeatureEntity,
          LicenseEntity,
          LicenseRevocationEntity,
        ],
        // TODO：生产环境前换成 TypeORM migrations（本轮范围明确留空，见 app/server/README.md）。
        synchronize: config.get<string>('nodeEnv') !== 'production',
      }),
    }),
    TypeOrmModule.forFeature([
      TenantEntity,
      UserEntity,
      SeatEntity,
      MembershipEntity,
      TenantFeatureEntity,
      LicenseEntity,
      LicenseRevocationEntity,
    ]),
  ],
  exports: [TypeOrmModule],
})
export class DatabaseModule {}
