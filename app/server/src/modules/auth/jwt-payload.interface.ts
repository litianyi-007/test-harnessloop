import { AuthMethod } from '../../database/entities';

/**
 * 认证 JWT（access token）payload——回答"我是谁"，与 License JWT（"有权用什么"，
 * 见 license/license-jwt.service.ts）是两个不同的凭证面（d5-6-account-license.md §4.1）。
 *
 * x-todo：字段集是本骨架的实现假设，D3 confirmed 文档只给出"JWT access/refresh"的技术选型
 * 结论，未逐条定义 payload 形状。
 */
export interface JwtAccessPayload {
  sub: string; // userId
  email?: string | null;
  authMethod?: AuthMethod | null;
}
