import { IsOptional, IsString } from 'class-validator';

/** POST /auth/browser/start 请求体（openapi authBrowserStart requestBody）。 */
export class BrowserStartRequestDto {
  @IsOptional()
  @IsString()
  returnDeepLink?: string;
}

/** POST /auth/browser/start 200 响应（openapi authBrowserStart responses.200）。 */
export class BrowserStartResponseDto {
  authorizationUrl!: string;
  state!: string;
}

/** POST /auth/token/refresh 请求体（openapi authTokenRefresh requestBody）。 */
export class RefreshTokenRequestDto {
  @IsString()
  refreshToken!: string;
}

/**
 * openapi.yaml `components.schemas.AuthTokenPair`。
 * x-todo：`accessTokenExpiresAt`/`refreshTokenExpiresAt` 具体有效期数值未定，见 schema description。
 */
export class AuthTokenPairDto {
  accessToken!: string;
  refreshToken!: string;
  accessTokenExpiresAt?: string;
  refreshTokenExpiresAt?: string;
}

/** POST /auth/license-key/redeem 请求体（openapi authLicenseKeyRedeem requestBody）。 */
export class LicenseKeyRedeemRequestDto {
  @IsString()
  licenseKey!: string;
}

/**
 * openapi.yaml `components.schemas.MeResponse`。
 * x-todo：`authMethod` 枚举 `license_key` 分支能否单独构成身份仍是开放项，见 schema description。
 */
export class MeResponseDto {
  userId!: string;
  email?: string;
  displayName?: string;
  authMethod?: 'browser_oauth' | 'license_key';
}
