import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NewApiModule } from '../newapi/newapi.module';
import { SessionTokenController } from './session-token.controller';
import { SessionTokenService } from './session-token.service';

@Module({
  imports: [AuthModule, NewApiModule],
  controllers: [SessionTokenController],
  providers: [SessionTokenService],
})
export class SessionTokenModule {}
