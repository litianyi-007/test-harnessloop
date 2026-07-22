import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ModelsController } from './models.controller';
import { ModelsService } from './models.service';

@Module({
  imports: [AuthModule],
  controllers: [ModelsController],
  providers: [ModelsService],
})
export class ModelsModule {}
