import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NewApiModule } from '../newapi/newapi.module';
import { NewApiManagementController } from './newapi-management.controller';
import { NewApiManagementService } from './newapi-management.service';

@Module({
  imports: [AuthModule, NewApiModule],
  controllers: [NewApiManagementController],
  providers: [NewApiManagementService],
})
export class NewApiManagementModule {}
