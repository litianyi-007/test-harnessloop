import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SessionNewApiTokenEntity } from '../../database/entities';
import { AuthModule } from '../auth/auth.module';
import { NewApiModule } from '../newapi/newapi.module';
import { SessionNewApiTokenMapService } from './session-newapi-token-map.service';
import { SessionTokenController } from './session-token.controller';
import { SessionTokenService } from './session-token.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([SessionNewApiTokenEntity]),
    AuthModule,
    NewApiModule,
  ],
  controllers: [SessionTokenController],
  providers: [SessionTokenService, SessionNewApiTokenMapService],
  // SessionNewApiTokenMapService 导出给 session-proxy 模块消费（D3-proxy 查表用）。
  exports: [SessionNewApiTokenMapService],
})
export class SessionTokenModule {}
