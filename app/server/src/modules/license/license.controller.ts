import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { LicenseDto, LicensePublicKeyResponseDto } from './dto/license.dto';
import { LicenseService } from './license.service';

/** tag: License（openapi.yaml）。 */
@Controller()
export class LicenseController {
  constructor(private readonly licenseService: LicenseService) {}

  /** operationId: getCurrentLicense — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('license/current')
  getCurrentLicense(
    @CurrentUser() user: JwtAccessPayload,
  ): Promise<LicenseDto> {
    return this.licenseService.getCurrentLicense(user);
  }

  /** operationId: refreshLicense — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Post('license/refresh')
  refreshLicense(@CurrentUser() user: JwtAccessPayload) {
    return this.licenseService.refreshLicense(user);
  }

  /** operationId: getLicensePublicKey — openapi `security: []`（公开）。 */
  @Get('license/public-key')
  getLicensePublicKey(): Promise<LicensePublicKeyResponseDto> {
    return this.licenseService.getPublicKey();
  }
}
