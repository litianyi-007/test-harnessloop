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
  },

  auth: {
    // x-todo：IdP 主体未选定，见 openapi /auth/browser/start
    idpAuthorizationEndpoint: process.env.AUTH_IDP_AUTHORIZATION_ENDPOINT,
  },
});
