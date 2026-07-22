import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { JwtAccessPayload } from '../jwt-payload.interface';

/**
 * 从 JwtAuthGuard 校验通过后挂在 req.user 上的 payload 里取值——
 * 供各 controller 里"当前登录身份"相关端点使用（getMe/getCurrentTenant/getCurrentSeat 等）。
 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): JwtAccessPayload => {
    const request = ctx.switchToHttp().getRequest<{ user: JwtAccessPayload }>();
    return request.user;
  },
);
