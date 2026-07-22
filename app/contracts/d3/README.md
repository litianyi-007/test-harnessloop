# D3 OpenAPI 契约草案（PRE-③）

## 这是什么

`openapi.yaml` 是 D3（瘦业务控制面 server，TypeScript + NestJS + PostgreSQL，见
`server/server-stack-selection.md`，`design_status: confirmed`）面向 client（Mac/Windows 原生 app，
见 D4 `d4-cross-platform-arch.md`）的 REST API 契约**草案**——本轮任务（PRE-③）的产出目的是把
D3 从"只有栈选型 + 领域模型"补齐到"有 endpoint/OpenAPI 契约"这一步，闭合 D4→D3 阻断依赖：

- [[d4-cross-platform-arch]] §7.1a/§8：D3 目前**没有** endpoint/OpenAPI/schema 契约，这是阻断
  D5.4（成本/用量）、D5.6（License/账号/坐席）两个产品面开工的**阻断性前置依赖**（不阻断
  `createSession`/`send`/审批等核心流程主路径）。
- [[d6-newapi-integration]] §4.3/§7/§8：D6 v2.2 正式定稿新增登记的**两项 D4→D3 依赖扩展**——
  ① session token 生命周期代理（安全默认方案 B：D3 全程代理 newapi Management API，client 不直连）；
  ② 模型/效力档位目录（供 D5.7 composer 消费）。这两项已经**独立于**既有的 D5.4/D5.6 依赖范围，
  单独登记，本契约同样覆盖。

**本轮范围是契约草案，不是完整实现**：覆盖 D3/D5/D6 已定稿文档里明确提到的核心端点面，
不追求穷尽所有 D3 未来可能需要的 endpoint（如 Console 侧的坐席分配/邀请审批/能力开关管控等
admin 操作面，明确不在 D5 范围，归 Console/P6，本契约不覆盖）。

## 端点组与对应关系

| OpenAPI tag | 端点数 | 对应产品/架构面 | 主要来源 |
|---|---|---|---|
| Auth | 6 | 登录（浏览器回流 + License key 直填）、JWT access/refresh、身份查询 | d5-6-account-license.md §3 |
| License | 3 | Ed25519 License JWT 校验、状态只读、公钥分发 | server-stack-selection.md、d5-6-account-license.md §4 |
| TenantSeat | 3 | 租户/坐席/角色只读呈现、邀请发起 | server-stack-selection.md、d5-6-account-license.md §5/§6 |
| Capabilities | 1 | tenant_features allowed 层拉取 | d5-5-capabilities.md §4.0、d5-6-account-license.md §7.3 |
| Billing | 3 | L1 席位/plan 额度、L2 newapi 用量查询（经 D3 代理）、newapiEndpoint 配置分发 | d5-4-cost-usage.md、d6-newapi-integration.md §5 |
| SessionToken | 1 路径（2 操作：POST/DELETE） | per-session newapi token 铸造+取key / 回收（方案 B 安全默认，path①专属） | d6-newapi-integration.md §3/§4.2 |
| NewApiManagement | 4 | newapi Management API 的 D3 代理面：租户级 token CRUD、用量/日志对账、渠道模型目录（server/console 用） | d6-newapi-integration.md §4.1/§4.2 |
| ModelCatalog | 1 | composer 模型/效力档位目录（D6→D3 新增依赖 2） | d6-newapi-integration.md §6.2/§6.3，d5-7-model-kernel.md §3.5 |

**合计：8 个 tag 分组，22 条 path，23 个 operation**（`/sessions/{sessionId}/billing-token`
一个 path 下有 POST 铸造 + DELETE 回收两个 operation；`GET /billing/usage` 一个端点同时覆盖
path①/path② 两条归因分支，不拆成两个端点，见该端点 description）。

## 与 D3/D5/D6 定稿的对应关系（不臆造声明）

- **不发明契约没有的 endpoint/字段**：所有 endpoint 与 schema 字段均能追溯到
  `server-stack-selection.md`（D3 六项能力→领域模型表）、`d5-4-cost-usage.md`、
  `d5-6-account-license.md`、`d6-newapi-integration.md`、`d1-kernelport-spec-v3-5.md` §7/§2.1
  的明确表述。凡源文档未给出具体字段名/端点形状之处（例如 `usage_ledger` 的 Chat/Turn 关联键、
  newapi 渠道/模型管理的精确 REST 路径、License 的具体角色枚举等），本契约在对应 schema
  property/endpoint description 里用 `x-todo` 前缀内联标注，不写死不存在的字段名。
- **path①/path② 与 C-3 的关系**：session-token 代理端点组（`POST`/`DELETE
  /sessions/{sessionId}/billing-token`）与 `GET /billing/usage`/`GET
  /tenant/current/newapi-endpoint-config` 的 `attribution`/`deploymentTokenRef` 具体取值，
  取决于 [[d1-kernelport-spec-v3-5]] §11 **C-3**（openclaw/hermes 是否支持 per-session 换模型
  出口 key/baseUrl）的探针结果，这几处均在 description 里显式标注**"待 PRE-① C-3 结果裁定"**，
  当前按 D5.4/D6 已确立的"保守假设处于 `user_tenant_aggregate` 降级分支"建模。

## TODO / 待裁决清单（按出现位置摘录，非穷尽——完整标注见 `openapi.yaml` 内 `x-todo`/description）

| # | 缺口 | 影响端点 | 来源 |
|---|---|---|---|
| 1 | **待 PRE-① C-3 结果裁定**：per-session 换 key 是否可行，决定 session-token 代理端点组是否实际被调用、`attribution` 实际取值 | `POST/DELETE /sessions/{sessionId}/billing-token`、`GET /billing/usage`、`GET /tenant/current/newapi-endpoint-config` | d1 §11 C-3、d6 §2.2/§5.2 |
| 2 | newapi `POST /api/token/` 创建响应不含新 token 的 `id`，`GET/DELETE /api/token/:id` 所需 `id` 反查机制未闭合——**实现前阻断性冒烟确认项** | `POST /sessions/{sessionId}/billing-token`、`DELETE /admin/newapi-tokens/{tokenId}` | d6 §3.1 步骤②详注、§7 #11 |
| 3 | License 离线/吊销/到期执行策略整体（是否设 `grace_period`、宽限范围、强制在线刷新时机）——**待产品+安全决策的开放项**，非仅参数未定 | `GET /license/current`（`status` 枚举含 `grace_period`，已在 schema 内标注为"本页提案，非 D3 confirmed"） | d5-6-account-license.md §4.2 v2.1 收尾 |
| 4 | License key 直填路径是否单独构成身份，还是必须配合登录 | `POST /auth/license-key/redeem` | d5-6-account-license.md §3.1/§9（消解 T-023 F-07） |
| 5 | 深链回调具体线上参数格式（token 直接带回 vs 一次性 code + exchange）未定，本契约按前者假设建模 | `GET /auth/browser/callback` | d5-6-account-license.md §3.2 状态机注释 |
| 6 | JWT access/refresh 具体有效期数值、refresh 失败重试策略未定 | `POST /auth/token/refresh` | d5-6-account-license.md §3.2 诚实缺口 |
| 7 | 一账号是否可属于多个 tenant / 是否需要工作区切换器——**未能确认**，本契约假设单一有效工作区，未加 `GET /tenants` 列表+切换端点 | `GET /tenant/current` | d5-6-account-license.md §6.4 |
| 8 | 邀请是否需管理员审批 / 用户如何被通知被邀请——均**未能确认** | `POST /tenant/current/invitations` | d5-6-account-license.md §4.3/§5.3/§9 |
| 9 | `suspended`/`removed` 坐席状态变更的实时传播机制——**未能确认**，且确认 D1 协议层无此类事件 | `GET /tenant/current/seat`（schema 内标注） | d5-6-account-license.md §6.3 |
| 10 | `usage_ledger` 缺 Chat/Turn 关联键与计价（单位/币种/模型价格版本）字段——L3 task 级成本差异化的阻断依赖，本轮**不设计** L3 端点 | 无对应端点（明确不做，见 d5-4-cost-usage.md §2.4/§3"MVP 明确不做"） | d5-4-cost-usage.md §2.4、d6 §5.3 |
| 11 | newapi 渠道/模型管理精确 REST 路径、Management API 长期 admin token 形态/RBAC/webhook——均**未能确认**，仅能力面 confirmed | `GET /admin/newapi/models`、`POST /admin/tenants/{tenantId}/newapi-tokens` | server-stack-selection.md 风险#1、d6 §4.1 |
| 12 | `CreateSessionConfig.model → 内核透传 → newapi 路由` 是否成立——**推测性澄清，待冒烟确认**，D1 §12 S-11 仍开放 | `GET /models/catalog` | d6 §6.2/§6.4 |
| 13 | Ed25519 公钥分发/轮换的具体格式（是否 JWKS）未定 | `GET /license/public-key` | server-stack-selection.md（应用内签发 Ed25519 JWT） |
| 14 | 调额/计价单位（token/credit/USD/CNY）未定 | `POST /admin/tenants/{tenantId}/newapi-tokens` | d5-4-cost-usage.md §2.4 依赖表第 1 行 |
| 15 | D3 不可达时 `createSession`/`stop()`/用量查询应如何降级（拒绝新建 session？允许无计费降级模式？）——本契约未设计降级响应码，留待架构侧裁决 | `GET /billing/usage`、session-token 代理端点组 | d6 §3.2 代价段落、§7 #13 |

## 语法校验

- `python3 -m openapi_spec_validator app/contracts/d3/openapi.yaml` → `OK`
- `npx @redocly/cli lint app/contracts/d3/openapi.yaml` → 0 error，17 个非阻断性风格警告
  （主要是只读/重定向端点缺 4XX 响应、`info.license` 字段缺失——草案阶段不强制补全，
  不影响契约本身的语法有效性与可解析性）。

## 明确不覆盖的范围（避免误读为"D3 全量 API"）

- Console（P6）专属的 admin 操作面：坐席分配/邀请审批、能力开关管控（enable/disable）、
  License 签发/吊销操作按钮——D5.6/D5.5 明确排除在 app 端契约之外。
- L3 task 级成本精确账单 UI 依赖的 endpoint——`usage_ledger` 关联键/计价字段本身是 D3 未闭合
  契约缺口，本轮不代 D3 裁决具体字段名，因此不设计对应端点。
- newapi 结算 webhook、请求级 correlation id 回查——均是 D6 标注为"未能确认"的 newapi 能力面，
  不是 D3 自己的 API，本契约不涉及。
- 方案 A（client 直连 newapi Management API）对应的"租户级 newapi 凭证下发/轮换"端点——
  D6 §3.2 明确方案 A 当前不推荐，仅当用户明确改选方案 A 时才需要补充登记，本契约不预先设计。
