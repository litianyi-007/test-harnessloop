import {
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { BillingTokenMintResponseDto } from './dto/session-token.dto';
import { SessionTokenService } from './session-token.service';

/** tag: SessionToken（openapi.yaml）——D6 §3/§4.2 安全默认方案 B 的代理端点。 */
@UseGuards(JwtAuthGuard)
@Controller()
export class SessionTokenController {
  constructor(private readonly sessionTokenService: SessionTokenService) {}

  /** operationId: mintSessionBillingToken — openapi 全局 bearerAuth（无覆盖）。 */
  @Post('sessions/:sessionId/billing-token')
  @HttpCode(HttpStatus.CREATED)
  mintSessionBillingToken(
    @Param('sessionId') sessionId: string,
  ): Promise<BillingTokenMintResponseDto> {
    return this.sessionTokenService.mintSessionBillingToken(sessionId);
  }

  /** operationId: revokeSessionBillingToken — openapi 全局 bearerAuth（无覆盖）。 */
  @Delete('sessions/:sessionId/billing-token')
  @HttpCode(HttpStatus.NO_CONTENT)
  revokeSessionBillingToken(
    @Param('sessionId') sessionId: string,
  ): Promise<void> {
    return this.sessionTokenService.revokeSessionBillingToken(sessionId);
  }
}
