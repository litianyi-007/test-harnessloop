import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import type { JwtAccessPayload } from '../jwt-payload.interface';

/**
 * 认证 JWT（access token）校验策略——桩：只做签名/过期校验，不查库确认用户是否仍然存在/
 * 未被吊销（D3 confirmed 文档未定义 token 撤销传播机制，见 d5-6-account-license.md §6.3）。
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.getOrThrow<string>('jwt.accessSecret'),
    });
  }

  validate(payload: JwtAccessPayload): JwtAccessPayload {
    // passport 会把返回值挂到 req.user；真正的"用户是否仍有效"校验留待实现阶段补充。
    return payload;
  }
}
