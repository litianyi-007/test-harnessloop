/**
 * 结构化配置读取（配合 env.validation.ts 的 EnvironmentVariables 校验）。
 * 具体数值来源与 x-todo 标注见 env.validation.ts 类注释，不在此重复。
 */
export default () => ({
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: parseInt(process.env.PORT ?? '3000', 10),

  database: {
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    username: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_DATABASE,
  },

  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET,
    // x-todo：具体有效期数值未在任何 confirmed 文档给出，见 openapi.yaml AuthTokenPair schema
    accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN ?? '15m',
    refreshSecret: process.env.JWT_REFRESH_SECRET,
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN ?? '30d',
  },

  licenseJwt: {
    // x-todo：格式（PEM/base64/JWKS）未定，见 openapi GET /license/public-key
    publicKey: process.env.LICENSE_JWT_PUBLIC_KEY,
    privateKey: process.env.LICENSE_JWT_PRIVATE_KEY,
    keyId: process.env.LICENSE_JWT_KEY_ID,
  },

  newapi: {
    baseUrl: process.env.NEWAPI_BASE_URL,
    // x-todo：admin 凭证形态未经实现前 API 冒烟确认，见 server-stack-selection.md 风险#1
    adminToken: process.env.NEWAPI_ADMIN_TOKEN,
    // x-todo：one-api/new-api 生态惯例是 OpenAI 兼容端点挂在 baseUrl 之下的 /v1 子路径
    // （Management API 走 /api/*，两者共享同一 host，见 newapi-client.service.ts 的
    // /api/token/ 等路径用法）——本字段把这一假设做成可配置项而非硬编码，若目标部署实际
    // 路径不同（如 NEWAPI_BASE_URL 本身已包含 /v1），可覆盖为空字符串。实现前需一次
    // API 冒烟确认（同 d6-newapi-integration.md §4.1"渠道/模型管理"一行已有的纪律）。
    completionsBasePath: process.env.NEWAPI_COMPLETIONS_BASE_PATH ?? '/v1',
  },

  // D3-proxy session-affinity 计费路由代理（SG-6 C-3 path①，
  // sg6-openclaw-persession-patch-design.md §5.1/§5.2）。
  sessionProxy: {
    // openclaw→D3-proxy 的静态部署级鉴权凭证（sg6 doc §5.1 `D3PROXY_STATIC_AUTH_KEY`）——
    // 这是"D3-proxy 认得这是合法的 openclaw 网关实例"这层鉴权，不是 newapi 凭证。
    // x-todo：部署时生成；骨架阶段允许留空，留空时 session-proxy 对所有请求 fail-closed
    // 拒绝（见 session-proxy.service.ts），不会误把未鉴权请求放行。
    staticAuthKey: process.env.SESSION_PROXY_STATIC_AUTH_KEY,
    // 未映射 sessionId 的兜底策略：'reject'（默认，最安全）| 'aggregate'（降级到聚合计费
    // 主体转发，需同时配置 aggregateFallbackNewApiKey，否则 fail-closed 拒绝）。
    // D6 未对此给出定论（见 sg6 doc §5.2 第4条"本页不代其裁决"），本实现按任务要求取
    // 最安全默认，并把切换点做成显式配置，不静默改变计费归因语义。
    unmappedSessionPolicy:
      process.env.SESSION_PROXY_UNMAPPED_SESSION_POLICY ?? 'reject',
    aggregateFallbackNewApiKey:
      process.env.SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY,
  },

  auth: {
    // x-todo：IdP 主体未选定，见 openapi /auth/browser/start
    idpAuthorizationEndpoint: process.env.AUTH_IDP_AUTHORIZATION_ENDPOINT,
  },
});
