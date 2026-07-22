import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MembershipEntity, TenantFeatureEntity } from '../../database/entities';
import { AuthModule } from '../auth/auth.module';
import { CapabilitiesController } from './capabilities.controller';
import { CapabilitiesService } from './capabilities.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([TenantFeatureEntity, MembershipEntity]),
    AuthModule,
  ],
  controllers: [CapabilitiesController],
  providers: [CapabilitiesService],
})
export class CapabilitiesModule {}
