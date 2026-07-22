import { Injectable } from '@nestjs/common';
import { NewApiClientService } from '../newapi/newapi-client.service';
import { BillingTokenMintResponseDto } from './dto/session-token.dto';

/**
 * per-session newapi token 生命周期代理（D6 §3/§4.2 职责 4，安全默认方案 B）——
 * client-local kernel adapter 只调用这组 D3 API，不直连 newapi Management API。
 *
 * **仅 path①（`billingAttribution:'session'`）下会被调用**（D6 §2.2）；path②
 * （aggregate，openclaw 侧 per-session 凭证 patch 落地前的临时状态）应跳过铸造/取key/回收
 * ——这是 client-local adapter 侧的调用纪律，本 service 本身对两条 path 呈现相同的接口形状，
 * 不在 D3 侧做 path 判断（D3 无法得知 adapter 是否会调用自己）。
 *
 * **依赖 SG-6 openclaw patch 落地才能真跑通 per-session 注入**：即便本服务的 newapi 调用链
 * 补齐（见 NewApiClientService 的 :id 反查缺口），openclaw 部署仍需要主仓库 goal
 * `20260718-002-agent-app` SG-6（openclaw per-session 凭证 patch）落地，才能让内核侧真正
 * 使用本服务下发的 scoped key 完成步骤④注入；hermes 侧对应 SG-7。本骨架只负责 D3 一侧的
 * API 形状，不代表整条注入链已经打通。
 */
@Injectable()
export class SessionTokenService {
  constructor(private readonly newApiClient: NewApiClientService) {}

  /** 对应 openapi mintSessionBillingToken（铸造+取key，原子操作，见 §3.1 步骤②③）。 */
  mintSessionBillingToken(
    sessionId: string,
  ): Promise<BillingTokenMintResponseDto> {
    return this.newApiClient.mintSessionToken(sessionId);
  }

  /** 对应 openapi revokeSessionBillingToken（回收，绑定真正终结节点，见 §3.1 步骤⑥）。 */
  revokeSessionBillingToken(sessionId: string): Promise<void> {
    return this.newApiClient.revokeSessionToken(sessionId);
  }
}
