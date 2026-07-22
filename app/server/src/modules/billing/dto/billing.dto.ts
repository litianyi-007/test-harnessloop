import { LicenseDto } from '../../license/dto/license.dto';
import { SeatDto } from '../../tenant/dto/tenant.dto';

/** openapi.yaml `components.schemas.BillingQuota`（L1 席位/plan 额度）。 */
export class BillingQuotaDto {
  license?: LicenseDto;
  seat?: SeatDto | null;
}

/**
 * openapi.yaml `components.schemas.SessionBillingSnapshot`（L2 newapi 按量用量）。
 * **强约束（d5-4-cost-usage.md §4.4，不得违反）**：失败时不得返回一个字段齐全但数值
 * 虚构/为零的实例——"查询成功但用量为 0"与"查询失败"必须走独立的响应路径，本骨架的
 * billing.service.ts 因此对本端点选择 `NotImplementedException` 而非返回一个"看起来完整
 * 但数值是编的"mock，理由见该 service 内注释。
 */
export class SessionBillingSnapshotDto {
  sessionId!: string;
  tokenRef?: string;
  attribution!: 'session' | 'user_tenant_aggregate';
  windowStart?: string;
  windowEnd?: string;
  requestCount?: number;
  totalQuota?: number;
  rpm?: number | null;
  tpm?: number | null;
  fetchedAt!: string;
  correlatable!: false;
}

/** openapi.yaml `components.schemas.NewApiEndpointConfig`。 */
export class NewApiEndpointConfigDto {
  baseUrl!: string;
  deploymentTokenRef?: string | null;
}
