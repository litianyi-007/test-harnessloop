/**
 * 对应 openapi.yaml `components.schemas.Error`。
 * 已知协议层错误码举例（不臆造未列出的，见 openapi Error.code description）：
 * `billing_query_subject_unresolved`、`no_license`、
 * `aggregate_billing_requires_deployment_token`（内核拒绝码，非本 API 直接返回，仅说明性列举）。
 */
export class ErrorDto {
  code!: string;
  message!: string;
  details?: Record<string, unknown>;
}
