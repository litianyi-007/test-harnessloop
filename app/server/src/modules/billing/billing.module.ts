import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { LicenseEntity, MembershipEntity } from '../../database/entities';
import { AuthModule } from '../auth/auth.module';
import { NewApiModule } from '../newapi/newapi.module';
import { BillingController } from './billing.controller';
import { BillingService } from './billing.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([LicenseEntity, MembershipEntity]),
    AuthModule,
    NewApiModule,
  ],
  controllers: [BillingController],
  providers: [BillingService],
})
export class BillingModule {}
