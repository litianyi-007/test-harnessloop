/** openapi.yaml `components.schemas.NewApiTokenAdmin`。 */
export class NewApiTokenAdminDto {
  id!: string;
  tenantId!: string;
  name?: string;
  quota?: number;
  status?: string;
}

/** POST /admin/tenants/{tenantId}/newapi-tokens 请求体（openapi requestBody）。 */
export class CreateTenantNewApiTokenRequestDto {
  quota?: number;
  note?: string;
}

/** openapi.yaml `components.schemas.NewApiUsageLogEntry`。 */
export class NewApiUsageLogEntryDto {
  tokenName?: string;
  modelName?: string;
  quota?: number;
  promptTokens?: number;
  completionTokens?: number;
  useTime?: string;
  channelId?: string;
  group?: string;
}

/** openapi.yaml `components.schemas.NewApiModelChannel`。 */
export class NewApiModelChannelDto {
  channelId?: string;
  modelName?: string;
  pricing?: Record<string, unknown>;
}
