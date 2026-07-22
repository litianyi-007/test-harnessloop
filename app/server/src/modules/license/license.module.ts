import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  LicenseEntity,
  LicenseRevocationEntity,
} from '../../database/entities';
import { AuthModule } from '../auth/auth.module';
import { LicenseController } from './license.controller';
import { LicenseJwtService } from './license-jwt.service';
import { LicenseService } from './license.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([LicenseEntity, LicenseRevocationEntity]),
    AuthModule,
  ],
  controllers: [LicenseController],
  providers: [LicenseService, LicenseJwtService],
  exports: [LicenseJwtService],
})
export class LicenseModule {}
