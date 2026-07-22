import { plainToInstance } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
  validateSync,
} from 'class-validator';

/**
 * D3 env schema.
 *
 * 事实源：server/server-stack-selection.md（栈选型：NestJS + PostgreSQL + JWT + Ed25519 License）、
 * architecture/d6-newapi-integration.md §3.2（D3 持有 newapi admin/租户级凭证，全程代理，client 不直连）。
 *
 * x-todo（本文件如实标注，不臆造具体数值——见各字段注释）：
 * - JWT access/refresh 具体有效期数值未在任何 D3/D5.6 confirmed 文档给出（openapi.yaml
 *   AuthTokenPair schema 逐字段标注 x-todo），此处仅给出可运行的默认值，不代表已裁决的产品参数。
 * - License Ed25519 公钥/私钥的分发/轮换格式（PEM vs JWKS）未定（openapi.yaml
 *   GET /license/public-key x-todo），此处按最简单的 PEM 字符串环境变量占位。
 * - newapi Management API 的 admin 凭证形态（长期 token？API key？）未在实现前完成冒烟确认
 *   （server-stack-selection.md 不确定与风险第 1 条、d6-newapi-integration.md §4.1），此处先用
 *   一个不透明的 bearer token 字符串占位。
 */
export class EnvironmentVariables {
  @IsOptional()
  @IsIn(['development', 'test', 'production'])
  NODE_ENV?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(65535)
  PORT?: number;

  // ── PostgreSQL（server-stack-selection.md 方案 A：PostgreSQL + 共享 schema + tenant_id）──
  @IsString()
  DB_HOST!: string;

  @IsInt()
  @Min(1)
  @Max(65535)
  DB_PORT!: number;

  @IsString()
  DB_USERNAME!: string;

  @IsString()
  DB_PASSWORD!: string;

  @IsString()
  DB_DATABASE!: string;

  // ── 认证 JWT（access/refresh，"我是谁"，与 License JWT 是两个不同凭证）──
  @IsString()
  JWT_ACCESS_SECRET!: string;

  @IsOptional()
  @IsString()
  JWT_ACCESS_EXPIRES_IN?: string; // x-todo：具体数值未定，默认仅供本地可跑，见类注释

  @IsString()
  JWT_REFRESH_SECRET!: string;

  @IsOptional()
  @IsString()
  JWT_REFRESH_EXPIRES_IN?: string; // x-todo：同上

  // ── License JWT（Ed25519，"有权用什么"，应用内签发校验）──
  @IsOptional()
  @IsString()
  LICENSE_JWT_PUBLIC_KEY?: string; // x-todo：格式（PEM/base64 raw/JWKS）未定，见 openapi GET /license/public-key

  @IsOptional()
  @IsString()
  LICENSE_JWT_PRIVATE_KEY?: string; // 签发端用；MVP 若只做校验骨架可留空

  @IsOptional()
  @IsString()
  LICENSE_JWT_KEY_ID?: string; // x-todo：密钥轮换后 keyId 标识方式未定

  // ── newapi Management API（D6 安全默认方案 B：D3 全程代理，持 admin/租户级凭证）──
  @IsOptional()
  @IsString()
  NEWAPI_BASE_URL?: string;

  @IsOptional()
  @IsString()
  NEWAPI_ADMIN_TOKEN?: string; // x-todo：长期 admin token 形态/RBAC 未经实现前 API 冒烟确认

  // ── 浏览器登录回流（IdP 主体未选定，x-todo，见 openapi /auth/browser/start）──
  @IsOptional()
  @IsString()
  AUTH_IDP_AUTHORIZATION_ENDPOINT?: string;
}

export function validateEnv(config: Record<string, unknown>) {
  const validatedConfig = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validatedConfig, {
    skipMissingProperties: false,
  });

  if (errors.length > 0) {
    throw new Error(
      `D3 server 环境变量校验失败：\n${errors
        .map((e) => Object.values(e.constraints ?? {}).join('; '))
        .join('\n')}`,
    );
  }
  return validatedConfig;
}
