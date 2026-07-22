import { LicenseStatus } from '../../../database/entities';

/**
 * openapi.yaml `components.schemas.License`。
 * `grace_period` 是产品提案而非 D3 confirmed 存在的机制——见 LicenseStatus 类型定义处注释，
 * 此处不重复整段搬运。
 */
export class LicenseDto {
  plan!: string;
  entitlements?: Record<string, unknown>;
  exp?: string;
  status!: LicenseStatus;
  tenantId?: string | null;
}

/** openapi GET /license/public-key 200 响应。 */
export class LicensePublicKeyResponseDto {
  publicKey!: string;
  alg!: 'EdDSA';
  keyId?: string;
}
