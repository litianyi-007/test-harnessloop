# D3 瘦控制面 server（SG-2：NestJS 骨架）

据 D3 定稿 OpenAPI 契约（`app/contracts/d3/openapi.yaml`+`README.md`，8 组 tag / 22 path /
23 operation）起的一个**可编译**的瘦控制面服务端骨架——本轮（SG-2）范围是骨架，不是完整业务实现：
路由/DTO 对齐契约、TypeORM 实体对齐 D3 领域模型、service 先桩（mock 或 `NotImplementedException`），
`npm install && npm run build` 必须通过。

## 怎么跑

```bash
npm install

# 起本地 PostgreSQL（server-stack-selection.md"部署：Docker Compose：api + postgres"）
docker compose up -d postgres

cp .env.example .env
# 至少要填：DB_*、JWT_ACCESS_SECRET、JWT_REFRESH_SECRET
# LICENSE_JWT_*/NEWAPI_*/AUTH_IDP_* 留空也能跑（对应端点会如实报 501/500，见下方「桩清单」）

npm run build      # nest build（tsc），本轮验收口径
npm run start:dev  # 需要 .env 配置完整 + postgres 已起，本轮任务范围不含这一步的验证
```

业务端点统一挂在 `api/d3/v1` 前缀下（对应 openapi `servers[0].url` 模板
`https://{host}/api/d3/v1`）；`GET /health` 是探活端点，特意排除在该前缀之外，不属于 D3 契约面。

## 模块 ↔ openapi tag 对应表

8 个业务模块对应 openapi.yaml 的 8 组 tag，`src/modules/` 下一模块一个目录
（module + controller + service + dto，License/SessionToken 另有专属 client/jwt service）：

| 模块目录 | openapi tag | 端点数 | 端点 |
|---|---|---|---|
| `auth` | Auth | 6 | `POST /auth/browser/start`、`GET /auth/browser/callback`、`POST /auth/token/refresh`、`POST /auth/logout`、`POST /auth/license-key/redeem`、`GET /me` |
| `license` | License | 3 | `GET /license/current`、`POST /license/refresh`、`GET /license/public-key` |
| `tenant`（含 seat/membership） | TenantSeat | 3 | `GET /tenant/current`、`GET /tenant/current/seat`、`POST /tenant/current/invitations` |
| `capabilities` | Capabilities | 1 | `GET /tenant/current/feature-flags` |
| `billing`（+newapi 代理） | Billing | 3 | `GET /billing/quota`、`GET /billing/usage`、`GET /tenant/current/newapi-endpoint-config` |
| `session-token`（代理） | SessionToken | 2（1 path） | `POST`/`DELETE /sessions/{sessionId}/billing-token` |
| `newapi-management`（代理） | NewApiManagement | 4 | `POST /admin/tenants/{tenantId}/newapi-tokens`、`DELETE /admin/newapi-tokens/{tokenId}`、`GET /admin/newapi/usage-logs`、`GET /admin/newapi/models` |
| `models` | ModelCatalog | 1 | `GET /models/catalog` |

**合计 23 个 operation，与 `app/contracts/d3/README.md`"合计：8 个 tag 分组，22 条 path，
23 个 operation"完全对齐**——逐路由核对方法见各 controller 文件头注（每个路由都标注了
对应的 openapi `operationId` 与 `security` 声明）。`newapi`（共享 client，见下）不对外暴露路由，
不计入这 23 个。

## Service 桩清单（哪些是真实逻辑、哪些是桩，及理由）

**纪律**：桩不假装完成——能写出真实逻辑的地方（JWT 签发/校验、DB 读取、config 读取）就写
真实逻辑；业务判断本身还未被 D3/D5/D6 任何 confirmed 文档裁定的地方，选择显式
`NotImplementedException`（501，body 里带 `code`+`message` 说明卡在哪个具体 x-todo），
不用编造的 mock 数值冒充"已实现"。

| 类别 | 端点 | 说明 |
|---|---|---|
| **真实逻辑**（10 个） | `POST /auth/token/refresh`、`POST /auth/logout`、`GET /me`、`GET /license/current`、`GET /license/public-key`、`GET /tenant/current`、`GET /tenant/current/seat`、`GET /tenant/current/feature-flags`、`GET /billing/quota`、`GET /tenant/current/newapi-endpoint-config` | JWT 签发/校验（`@nestjs/jwt`）、Ed25519 校验（`jose`）、TypeORM 仓库读取、env 配置读取——均为可运行代码，非占位 |
| **条件性**（1 个） | `POST /auth/browser/start` | 配置 `AUTH_IDP_AUTHORIZATION_ENDPOINT` 后即可生成真实授权 URL；未配置时如实 501（IdP 主体未选定是 openapi 本身的 x-todo，不是本骨架的疏漏） |
| **诚实空列表**（3 个） | `GET /admin/newapi/usage-logs`、`GET /admin/newapi/models`、`GET /models/catalog` | 200 + 空数组——"列表可以合法为空"与"标量数值不能编造"是两回事（后者见下一行），这几个端点尚未接入 newapi/Console 路由表，返回空列表是诚实的"尚未查询"状态 |
| **`NotImplementedException`（501，9 个）** | `GET /auth/browser/callback`、`POST /auth/license-key/redeem`、`POST /license/refresh`、`POST /tenant/current/invitations`、`GET /billing/usage`、`POST`/`DELETE /sessions/{sessionId}/billing-token`、`POST /admin/tenants/{tenantId}/newapi-tokens`、`DELETE /admin/newapi-tokens/{tokenId}` | 每个 501 响应体里的 `message` 都指向具体的 x-todo 来源（深链格式未定/License key 路径未裁决/newapi token id 反查缺口/…），见各 service 文件内联注释，不是笼统的"未实现" |

`GET /billing/usage` 单独说明：这是唯一一个"即便写了也不能真的返回内容"的端点——
d5-4-cost-usage.md §4.4 强约束"不得静默展示一个字段齐全但数值虚构/为零的
`SessionBillingSnapshot`"，本骨架尚未真正接入 newapi，若在此处 mock 一个 `requestCount:0` 的
快照，会被 UI 误读为"这个部署真的没有用量"——这正是该强约束明确禁止的行为，因此选择 501
而非 mock，见 `src/modules/billing/billing.service.ts` 注释。

## TypeORM 实体清单（PostgreSQL，共享 schema 多租户）

任务给定 6 实体（均带 `tenant_id`，除 `TenantEntity` 自身——见下方说明），另加 1 个源自
confirmed 文档、支撑 License 吊销校验的补充实体：

| 实体 | 表名 | 对应 D3 概念 | 备注 |
|---|---|---|---|
| `TenantEntity` | `tenants` | `tenant` | 租户本身，不带 `tenant_id`（它自己就是那个 id），server-stack-selection.md 原文"`tenant` + 所有业务表 `tenant_id`"——其余表才带 |
| `UserEntity` | `users` | 认证身份（D1/D2 无原生对应） | `currentTenantId` 是"假设单一有效工作区"的实现简化，见文件头注释 |
| `SeatEntity` | `seats` | `seat`（P0"`memberships` + `seat_limit`"里的 `seat_limit` 半） | 租户级坐席容量配置，与 `MembershipEntity` 是"容量 vs 个人成员关系"两个粒度，见该文件头注释 |
| `MembershipEntity` | `memberships` | `membership`（role/状态） | 对应 openapi `Seat` schema（命名沿用契约） |
| `TenantFeatureEntity` | `tenant_features` | `tenant_features`/`feature_flags` | JSONB `flags`，allowed 层准入开关 |
| `LicenseEntity` | `licenses` | `license`（plan/entitlements/exp/status） | 个人 free license 的 `tenantId` 为 null |
| `LicenseRevocationEntity`（补充） | `license_revocations` | `revocations`（server-stack-selection.md"`licenses` + `revocations` 两张表"） | 未在任务给定 6 实体清单逐条点名，但源自同一份 confirmed 文档，`LicenseJwtService.verify()` 用它做吊销检查，不是臆造 |

**迁移**：本轮留 TODO——`DatabaseModule` 用 `synchronize: NODE_ENV !== 'production'` 做开发期
schema 同步，生产环境落地前必须换成 TypeORM migration 文件（当前无 `migrations/` 目录）。

## TypeORM vs Prisma：选 TypeORM

server-stack-selection.md 方案 A 原文并列"PostgreSQL + Prisma 或 TypeORM"，未强制二选一。
本骨架选 TypeORM，理由：

1. **NestJS 官方一等公民**——`@nestjs/typeorm` 是 Nest 官方维护的集成包，`@InjectRepository`/
   `TypeOrmModule.forFeature` 与 Nest DI 容器契合度高于社区维护的 `nestjs-prisma` 之类的桥接层。
2. **Active Record / Data Mapper 双模式**，本骨架用 Data Mapper（`Repository<Entity>` 注入），
   与"共享 schema + `tenant_id`"的多租户读取模式（各 service 按 `tenantId`/`userId` 过滤查询）
   写法自然。
3. Prisma 的强项（生成式 client、更强的迁移 DX）在"骨架阶段可留 TODO 迁移"的当前范围内收益有限，
   TypeORM 的装饰器实体定义（`@Entity`/`@Column`）与本骨架"实体先行、迁移留 TODO"的任务顺序更匹配。

## Auth 脚手架

- **认证 JWT（access/refresh）**：`@nestjs/passport` + `@nestjs/jwt`，`JwtStrategy`
  （`src/modules/auth/strategies/jwt.strategy.ts`）+ `JwtAuthGuard`——真实签发/校验逻辑，
  非占位；具体有效期数值（`JWT_ACCESS_EXPIRES_IN`/`JWT_REFRESH_EXPIRES_IN`）是"可运行的默认值"，
  不是 D3/D5.6 confirmed 的产品参数（这两份文档均明确标注"未定"，见 `env.validation.ts` 类注释）。
- **License JWT（Ed25519）**：`LicenseJwtService`（`src/modules/license/license-jwt.service.ts`）
  用 `jose` 实现真实的 EdDSA 验签 + 吊销表查询（`LicenseRevocationEntity`）；公钥/私钥来源
  （PEM 环境变量 vs JWKS/KMS）是 openapi `GET /license/public-key` 本身标注的 x-todo，本骨架
  从环境变量读取单个 PEM 字符串占位，替换 key 加载方式不影响对外 `verify`/`sign` 签名。

## newapi Management 代理（D6 安全默认方案 B）

`src/modules/newapi/newapi-client.service.ts`（`NewApiClientService`）是全站唯一被允许持有
newapi 凭证、直接调用其 Management API 的组件——对应 d6-newapi-integration.md §3.2/§4.2
"D3 全程代理，client 不直连"的安全默认。`billing`/`session-token`/`newapi-management` 三个模块
均通过 `NewApiModule` 导入并消费同一个 client，不各自重复实现 HTTP 调用。

client 的 HTTP 基础设施（`baseURL`/`Authorization` header 走 `NEWAPI_ADMIN_TOKEN`）已经接好，
但每个业务方法目前均 `NotImplementedException`，理由逐条写在方法体注释里，核心是两个尚未闭合的
契约缺口（均非本骨架发明，来自 d6-newapi-integration.md 已定稿的诚实标注）：

1. newapi `POST /api/token/` 创建响应不含新 token 的 `id`，而 `GET`/`DELETE /api/token/:id`
   恰恰需要这个 `id`——反查机制未闭合，**实现前阻断性冒烟确认项**（D6 §3.1 步骤②详注、§7 #11）。
2. newapi 渠道/模型管理精确 REST 路径、Management API 长期 admin token 形态/RBAC——
   仅能力面 confirmed，精确路径需实现前对目标 newapi 版本做一次 API 冒烟（D6 §4.1）。

**`path①` session-token 依赖 SG-6**：`POST`/`DELETE /sessions/{sessionId}/billing-token`
这组端点即便补齐上述 newapi 调用链，仍只在 `billingAttribution:'session'`（path①）下才会被
client-local adapter 调用；per-session 换 key 真正在内核侧生效，openclaw 部署还依赖主仓库 goal
`20260718-002-agent-app` **SG-6**（openclaw per-session 凭证 patch）落地，hermes 部署对应
**SG-7**（接线已有的 `resolve_runtime_provider` 通道）——本骨架只交付 D3 一侧的 API 形状，
不代表整条注入链已经打通，见 `src/modules/session-token/session-token.service.ts` 头注释。

## 与 D3/D5/D6 契约的对应

- **D3 endpoint 形状**：`app/contracts/d3/openapi.yaml`——路由装饰器路径字面量、DTO 字段
  均手写对齐（未跑 codegen；contracts/d2 已有 schema→TS codegen 先例，但 D3 是 REST+OpenAPI
  而非 D2 那种消息 schema，本轮选手写对齐并逐 controller 加 `operationId`/`security` 注释，
  以便未来若要接 `openapi-typescript`/NestJS Swagger codegen 时能对照复核）。
- **D3 领域模型**：`server/server-stack-selection.md`——六项能力→实体表，见上方「TypeORM 实体清单」。
- **D6 安全默认**：`architecture/d6-newapi-integration.md` §3.2 方案 B——见「newapi Management 代理」节。
- **D5.4/D5.6 产品面**：`product/d5-4-cost-usage.md`/`d5-6-account-license.md`——本骨架的 DTO 字段
  （`SessionBillingSnapshotDto`/`LicenseDto`/`SeatDto` 等）逐字段对齐这两份文档展开的 D1/D3 字段表，
  未发明文档外字段。

## 已知缺口（不臆造，逐条见代码内联注释，此处只做索引）

完整清单见 `app/contracts/d3/README.md`「TODO / 待裁决清单」，本骨架代码内联注释均引用其编号。
最关键的几条（决定哪些 service 方法目前必须是桩）：

- newapi token 创建响应缺 `id`，反查机制未闭合（阻断 session-token/newapi-management 两个模块的真实实现）。
- IdP 主体未选定（阻断 `authBrowserStart`/`authBrowserCallback` 的真实实现）。
- License key 直填路径的身份归属未裁决（阻断 `authLicenseKeyRedeem`）。
- License 离线宽限/强制在线刷新策略待产品+安全决策（阻断 `refreshLicense`）。
- 邀请审批/通知机制未确认（阻断 `createInvitation`）。
- newapi 渠道/模型管理精确 REST 路径待冒烟确认（阻断 `getNewApiModels`/`getModelCatalog` 的真实数据源）。
