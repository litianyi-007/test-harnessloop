import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { CurrentUser } from './decorators/current-user.decorator';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { AuthService } from './auth.service';
import {
  AuthTokenPairDto,
  BrowserStartRequestDto,
  BrowserStartResponseDto,
  LicenseKeyRedeemRequestDto,
  MeResponseDto,
  RefreshTokenRequestDto,
} from './dto/auth.dto';
import type { JwtAccessPayload } from './jwt-payload.interface';

/**
 * tag: Auth（openapi.yaml）。路由不加 controller 级前缀——直接对齐 openapi path 字面量，
 * 避免 Nest 前缀拼接与契约路径出现偏差。每个路由头注标注对应 openapi `security` 声明。
 */
@Controller()
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /** operationId: authBrowserStart — openapi `security: []`（公开）。 */
  @Post('auth/browser/start')
  authBrowserStart(
    @Body() dto: BrowserStartRequestDto,
  ): BrowserStartResponseDto {
    return this.authService.browserStart(dto);
  }

  /** operationId: authBrowserCallback — openapi `security: []`（公开，系统浏览器命中）。 */
  @Get('auth/browser/callback')
  authBrowserCallback(
    @Query('code') code: string | undefined,
    @Query('state') state: string,
    @Res() res: Response,
  ): void {
    // 见 auth.service.ts handleBrowserCallback：深链回调格式未定，如实抛 501。
    // 保留 @Res() 签名以对齐 openapi "302 重定向" 的响应形状意图（一旦格式裁定后在此处 res.redirect）。
    this.authService.handleBrowserCallback(code, state);
    void res; // TODO：格式裁定后改为 res.redirect(deepLinkUrl)
  }

  /** operationId: authTokenRefresh — openapi `security: []`（公开，凭 refreshToken 本身鉴权）。 */
  @Post('auth/token/refresh')
  authTokenRefresh(
    @Body() dto: RefreshTokenRequestDto,
  ): Promise<AuthTokenPairDto> {
    return this.authService.refreshToken(dto);
  }

  /** operationId: authLogout — openapi 全局 `security: [bearerAuth]`（无覆盖，需登录）。 */
  @UseGuards(JwtAuthGuard)
  @Post('auth/logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  authLogout(): void {
    this.authService.logout();
  }

  /** operationId: authLicenseKeyRedeem — openapi 显式 `security: [bearerAuth]`。 */
  @UseGuards(JwtAuthGuard)
  @Post('auth/license-key/redeem')
  authLicenseKeyRedeem(
    @CurrentUser() user: JwtAccessPayload,
    @Body() dto: LicenseKeyRedeemRequestDto,
  ) {
    return this.authService.licenseKeyRedeem(user.sub, dto);
  }

  /** operationId: getMe — openapi 全局 `security: [bearerAuth]`（无覆盖，需登录）。 */
  @UseGuards(JwtAuthGuard)
  @Get('me')
  getMe(@CurrentUser() user: JwtAccessPayload): MeResponseDto {
    return this.authService.getMe(user);
  }
}
