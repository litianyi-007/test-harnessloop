import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * 对应 openapi.yaml 全局 `security: [bearerAuth: []]`——挂在每个未显式 `security: []`
 * 覆盖的端点上（各 controller 里逐路由标注对应哪一条 openapi security 声明）。
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
