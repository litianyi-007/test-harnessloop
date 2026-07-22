import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import type { JwtAccessPayload } from '../auth/jwt-payload.interface';
import { CapabilitiesService } from './capabilities.service';
import { FeatureFlagsDto } from './dto/feature-flags.dto';

/** tag: Capabilities（openapi.yaml）。 */
@Controller()
export class CapabilitiesController {
  constructor(private readonly capabilitiesService: CapabilitiesService) {}

  /** operationId: getFeatureFlags — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('tenant/current/feature-flags')
  getFeatureFlags(
    @CurrentUser() user: JwtAccessPayload,
  ): Promise<FeatureFlagsDto> {
    return this.capabilitiesService.getFeatureFlags(user);
  }
}
