import { randomUUID } from 'node:crypto';
import {
  Injectable,
  NotImplementedException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  AuthTokenPairDto,
  BrowserStartRequestDto,
  BrowserStartResponseDto,
  LicenseKeyRedeemRequestDto,
  MeResponseDto,
  RefreshTokenRequestDto,
} from './dto/auth.dto';
import type { JwtAccessPayload } from './jwt-payload.interface';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
  ) {}

  /**
   * 对应 openapi authBrowserStart。真实 IdP 主体未选定（x-todo，见
   * d5-6-account-license.md §3.1"IdP 主体本身...未选定"）——若配置了
   * `AUTH_IDP_AUTHORIZATION_ENDPOINT` 则生成真实可用的授权 URL（机制本身已实现，
   * 非桩）；未配置时如实报告 501，不伪造一个假的 IdP 地址。
   */
  browserStart(dto: BrowserStartRequestDto): BrowserStartResponseDto {
    const idpEndpoint = this.config.get<string>(
      'auth.idpAuthorizationEndpoint',
    );
    const state = randomUUID();

    if (!idpEndpoint) {
      throw new NotImplementedException({
        code: 'idp_not_configured',
        message:
          'IdP 主体未选定（见 openapi /auth/browser/start x-todo）。' +
          '配置 AUTH_IDP_AUTHORIZATION_ENDPOINT 后本端点即可生成真实授权 URL。',
      });
    }

    const url = new URL(idpEndpoint);
    url.searchParams.set('state', state);
    if (dto.returnDeepLink) {
      url.searchParams.set('redirect_uri', dto.returnDeepLink);
    }
    return { authorizationUrl: url.toString(), state };
  }

  /**
   * 对应 openapi authBrowserCallback。深链回调具体线上参数格式（token 直接带回 vs
   * 一次性 code + exchange）未定（x-todo #5，openapi.yaml GET /auth/browser/callback），
   * 本骨架不臆造具体机制，如实报告未实现。
   */
  handleBrowserCallback(_code: string | undefined, _state: string): never {
    throw new NotImplementedException({
      code: 'browser_callback_format_undecided',
      message:
        '深链回调具体线上参数格式未定（token 直接带回 vs 一次性 code + exchange），' +
        '见 openapi.yaml GET /auth/browser/callback x-todo，本骨架不臆造具体机制。',
    });
  }

  /**
   * 对应 openapi authTokenRefresh。JWT 签发/校验机制本身是真实实现（非桩）——
   * 具体有效期数值/refresh 失败重试策略未定（x-todo #6），仅用可运行的默认值占位。
   */
  async refreshToken(dto: RefreshTokenRequestDto): Promise<AuthTokenPairDto> {
    const refreshSecret = this.config.getOrThrow<string>('jwt.refreshSecret');
    let payload: JwtAccessPayload;
    try {
      payload = await this.jwtService.verifyAsync<JwtAccessPayload>(
        dto.refreshToken,
        { secret: refreshSecret },
      );
    } catch {
      // 对应认证状态机 reauth_required（d5-6-account-license.md §3.2）。
      throw new UnauthorizedException({
        code: 'reauth_required',
        message: 'refresh token 失效/过期，需要重新登录。',
      });
    }
    return this.issueTokenPair({
      sub: payload.sub,
      email: payload.email,
      authMethod: payload.authMethod,
    });
  }

  /** 对应 openapi authLogout。TODO：refresh token 撤销/黑名单存储尚未实现。 */
  logout(): void {
    // TODO：当前无 session/refresh-token 存储层，登出只是 client 侧丢弃 token 的语义。
  }

  /**
   * 对应 openapi authLicenseKeyRedeem。是否可脱离登录使用、身份来源如何——
   * 均为待产品/D3 决策的开放项（x-todo #4，见 d5-6-account-license.md §3.1/§9），
   * 本骨架不擅自选定其中一种,如实报告未实现。
   */
  licenseKeyRedeem(_userId: string, _dto: LicenseKeyRedeemRequestDto): never {
    throw new NotImplementedException({
      code: 'license_key_path_undecided',
      message:
        'License key 直填路径的身份来源未裁决（见 d5-6-account-license.md §3.1/§9），' +
        '本骨架不擅自选定"独立认证路径"还是"登录后兑换"。',
    });
  }

  /** 对应 openapi getMe——直接投影 JWT payload（真实逻辑，非桩）。 */
  getMe(user: JwtAccessPayload): MeResponseDto {
    return {
      userId: user.sub,
      email: user.email ?? undefined,
      authMethod: user.authMethod ?? undefined,
    };
  }

  /** 签发 access+refresh 一对 JWT（真实逻辑）。供 login 落地后与 refreshToken 复用。 */
  async issueTokenPair(payload: JwtAccessPayload): Promise<AuthTokenPairDto> {
    const accessExpiresIn = this.config.get<string>('jwt.accessExpiresIn');
    const refreshSecret = this.config.getOrThrow<string>('jwt.refreshSecret');
    const refreshExpiresIn = this.config.get<string>('jwt.refreshExpiresIn');

    // 见 auth.module.ts 同款注释：`expiresIn` 的 `StringValue` 字面量类型无法在编译期
    // 从运行时 env 字符串收窄，这里做受控 cast，不改变运行时行为。
    const accessToken = await this.jwtService.signAsync(payload, {
      expiresIn: accessExpiresIn as unknown as number,
    });
    const refreshToken = await this.jwtService.signAsync(payload, {
      secret: refreshSecret,
      expiresIn: refreshExpiresIn as unknown as number,
    });

    return { accessToken, refreshToken };
  }
}
