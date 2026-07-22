import { Injectable, NotImplementedException } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { AxiosInstance } from 'axios';
import type { SessionBillingSnapshotDto } from '../billing/dto/billing.dto';
import type { BillingTokenMintResponseDto } from '../session-token/dto/session-token.dto';
import type {
  NewApiModelChannelDto,
  NewApiTokenAdminDto,
  NewApiUsageLogEntryDto,
} from '../newapi-management/dto/newapi-management.dto';

/**
 * 封装"server 持 newapi admin 凭证 → 代理 token CRUD/用量查询"这一 D6 §3.2/§4.2 安全默认
 * （方案 B：D3 全程代理，client 不直连 newapi Management API）——本 client 是全站唯一被允许
 * 持有 newapi 凭证并直接调用其 Management API 的组件，billing/session-token/newapi-management
 * 三个模块均通过它间接访问 newapi，不重复各自实现 HTTP 调用。
 *
 * **本骨架现状**：HTTP client 本身已按 D6 §4.1"已核对的 Management API 端点清单"接好
 * baseURL/鉴权头（真实基础设施，非桩）；但具体业务方法**全部 NotImplementedException**——
 * 每个方法体内引用的缺口均来自 d6-newapi-integration.md 已定稿的诚实标注，不是本骨架
 * 自己发明的借口：
 * - `POST /api/token/` 创建响应不含新 token `id`，`GET/DELETE /api/token/:id` 需要的 `id`
 *   反查机制未闭合（D6 §3.1 步骤②详注、§7 #11，实现前阻断性冒烟确认项）。
 * - per-session 换 key 落地依赖 openclaw patch（SG-6）/hermes 接线（SG-7）落地，见
 *   d6-newapi-integration.md §2.2 v3 收口；patch 落地前 path①在 openclaw 侧仍不可真正生效。
 * - newapi 渠道/模型管理精确 REST 路径、Management API 长期 admin token 形态/RBAC——
 *   均标注"仅能力面 confirmed，精确路径未能确认"（D6 §4.1），需实现前对目标 newapi 版本
 *   做一次 API 冒烟。
 */
@Injectable()
export class NewApiClientService {
  private readonly client: AxiosInstance;

  constructor(
    private readonly httpService: HttpService,
    private readonly config: ConfigService,
  ) {
    this.client = this.httpService.axiosRef;
    this.client.defaults.baseURL = this.config.get<string>('newapi.baseUrl');
    const adminToken = this.config.get<string>('newapi.adminToken');
    if (adminToken) {
      this.client.defaults.headers.common['Authorization'] =
        `Bearer ${adminToken}`;
    }
  }

  /**
   * 对应 D1 §7 注入链步骤②③——`POST /api/token/` + `GET /api/token/:id`（`GetTokenKey`）。
   * **仅 path①（`billingAttribution:'session'`）下应被调用**（D6 §2.2）；path②下应在
   * 调用方（session-token.service.ts）跳过本方法，见该 service 注释。
   */
  mintSessionToken(_sessionId: string): Promise<BillingTokenMintResponseDto> {
    throw new NotImplementedException({
      code: 'newapi_token_id_lookup_unresolved',
      message:
        'newapi POST /api/token/ 创建响应不含新 token 的 id，GET/DELETE /api/token/:id ' +
        '所需 id 的反查机制未闭合（见 d6-newapi-integration.md §3.1 步骤②详注、§7 #11），' +
        '这是实现前阻断性冒烟确认项，本骨架不臆造反查机制。另注：per-session 注入真正生效' +
        '依赖 openclaw per-session 凭证 patch（主仓库 goal SG-6）落地，patch 落地前 openclaw ' +
        '部署侧按 §2.2 应跳过本方法。',
    });
  }

  /** 对应 D1 §7 注入链步骤⑥——`DELETE /api/token/:id`。仅 path①下应被调用（同上）。 */
  revokeSessionToken(_sessionId: string): Promise<void> {
    throw new NotImplementedException({
      code: 'newapi_token_id_lookup_unresolved',
      message:
        '回收同样依赖上方 mintSessionToken 标注的 :id 反查缺口，暂无法执行 DELETE。',
    });
  }

  /**
   * 对应 D6 §5.1 字段级映射——组合 `GET /api/usage/token` + `GET /api/log/self`。
   * **强约束（d5-4-cost-usage.md §4.4）**：不得返回字段齐全但数值虚构的快照，
   * 调用方（billing.service.ts）据此选择在本方法未真正实现时整体 501，而不是让本方法
   * 编造一个"看起来完整"的返回值。
   */
  queryUsage(_params: {
    sessionId?: string;
    windowStart?: string;
    windowEnd?: string;
  }): Promise<SessionBillingSnapshotDto> {
    throw new NotImplementedException({
      code: 'newapi_usage_query_not_wired',
      message:
        '组合 GET /api/usage/token + GET /api/log/self 映射为 SessionBillingSnapshot 的规则' +
        '仍是近似（见 d6-newapi-integration.md §5.1"仍有缺口"段落），且 windowStart/windowEnd/' +
        'requestCount 均非 newapi 原生字段，需要实现阶段针对目标 newapi 版本做字段级验证后' +
        '再接入，本骨架不伪造这些数值。',
    });
  }

  /** 对应 server-stack-selection.md"控制面 → new-api 用 admin 凭证...创建...token"。 */
  createTenantToken(
    _tenantId: string,
    _quota: number | undefined,
    _note: string | undefined,
  ): Promise<NewApiTokenAdminDto> {
    throw new NotImplementedException({
      code: 'newapi_admin_token_id_unresolved',
      message:
        '调额单位（token/credit/USD/CNY）未定（d5-4-cost-usage.md §2.4 依赖表第 1 行），' +
        '且新建 token 的 id 反查缺口同 mintSessionToken 标注，本骨架不臆造。',
    });
  }

  /** 对应 server-stack-selection.md"...吊销...token"。 */
  revokeTenantToken(_tokenId: string): Promise<void> {
    throw new NotImplementedException({
      code: 'newapi_admin_token_id_unresolved',
      message:
        'tokenId 取值来源（D3 内部 id 还是 newapi 侧 id）取决于同一个未闭合的反查机制。',
    });
  }

  /**
   * 对应 D6 §4.1"用量/日志查询（admin，全站）"——`GET /api/log/`/`/stat`/`/search`。
   * 返回空列表而非编造条目：这是一个诚实的"尚未真正查询"状态，不是伪造的用量数据
   * （与 queryUsage 选择 501 的差异在于：这里是"列表可以合法地为空"，那里是"标量数值
   * 不能被伪造为 0 或任意值"，见 billing.dto.ts SessionBillingSnapshotDto 注释）。
   */
  getUsageLogs(_filters: {
    tenantId?: string;
    tokenName?: string;
    since?: string;
    until?: string;
  }): Promise<NewApiUsageLogEntryDto[]> {
    // TODO：接入 D6 §4.1 admin 面 GET /api/log/ 系列端点（精确路径待 API 冒烟确认）。
    return Promise.resolve([]);
  }

  /**
   * 对应 D6 §4.1"渠道/模型管理"——精确 REST 路径未能确认（仅能力面 confirmed）。
   * 同样返回空列表作为诚实的"尚未接入"状态。
   */
  getModelChannels(): Promise<NewApiModelChannelDto[]> {
    // TODO：newapi 渠道/模型管理精确 REST 路径待实现前 API 冒烟确认（D6 §4.1）。
    return Promise.resolve([]);
  }
}
