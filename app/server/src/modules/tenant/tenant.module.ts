import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  MembershipEntity,
  SeatEntity,
  TenantEntity,
} from '../../database/entities';
import { AuthModule } from '../auth/auth.module';
import { TenantController } from './tenant.controller';
import { TenantService } from './tenant.service';

/** 模块名 tenant，含 seat/membership（tag: TenantSeat，见 CLAUDE.md 任务描述）。 */
@Module({
  imports: [
    TypeOrmModule.forFeature([TenantEntity, SeatEntity, MembershipEntity]),
    AuthModule,
  ],
  controllers: [TenantController],
  providers: [TenantService],
  exports: [TenantService],
})
export class TenantModule {}
