import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Repository } from 'typeorm';
import { SessionNewApiTokenEntity } from '../../database/entities';

export interface ActiveSessionNewApiToken {
  newapiKey: string;
  newapiTokenId: string | null;
  tokenGeneration: number;
}

/**
 * D3 自己维护的 session → newapi token 映射（d6-newapi-integration.md §3.1/§4.2 职责4）——
 * `session-proxy` 模块（SG-6 C-3 path①，openclaw 出站请求换真实 newapi 凭证转发）唯一的
 * 查表来源；`SessionTokenService`（openapi `mintSessionBillingToken`/`revokeSessionBillingToken`
 * 骨架，铸造侧因 newapi token id 反查缺口未闭合而 501）与本 service 是两个不同关注点——
 * 本 service 只负责"D3 自己这张表"的 CRUD，不直接调用 newapi。
 *
 * x-todo：`SessionTokenService.mintSessionBillingToken`/`revokeSessionBillingToken` 真正
 * 接入 newapi 之后，应分别调用本 service 的 `upsert`/`revoke` 保持本表与 newapi 侧一致——
 * 当前铸造链路整体 501，本表在生产环境下预期为空，这是诚实的"上游未接通"状态。
 */
@Injectable()
export class SessionNewApiTokenMapService {
  constructor(
    @InjectRepository(SessionNewApiTokenEntity)
    private readonly repo: Repository<SessionNewApiTokenEntity>,
  ) {}

  /**
   * session-proxy 转发前的查表——只返回未回收（`revokedAt IS NULL`）的映射。
   *
   * T-042 对抗审 NOTE：若行存在但 `newapiKey` 是空字符串（脏数据，理论上不该发生，
   * 但 `upsert` 曾经没有守卫），当作"未命中"处理而不是原样返回——否则调用方
   * （`SessionProxyService.resolveNewApiKey`）会把空串当有效 key 换上去，最终发出
   * `Authorization: Bearer `（空 token）这种半放行的脏请求，而不是走 fail-closed 的
   * 拒绝分支。
   */
  async findActive(
    sessionId: string,
  ): Promise<ActiveSessionNewApiToken | null> {
    const row = await this.repo.findOne({
      where: { sessionId, revokedAt: IsNull() },
    });
    if (!row || !row.newapiKey) return null;
    return {
      newapiKey: row.newapiKey,
      newapiTokenId: row.newapiTokenId,
      tokenGeneration: row.tokenGeneration,
    };
  }

  /**
   * 写入/更新该 session 的映射（供未来 mint 流程接线，也供测试/开发环境手工种入数据）。
   * `tokenGeneration` 对应 D6 §3.3 v2.2 的 resume 新代次语义——resume 铸造应传入递增值，
   * 不传则按 1 处理（首次铸造）。
   *
   * T-042 对抗审 NOTE：拒绝空 `newapiKey` 写入——空串不是"未配置"，是脏数据，会让
   * `findActive` 命中一条看似有效实则无凭证的映射（见上）。fail-closed 应该发生在
   * "根本没有这条映射"，不是"映射存在但 key 是空的"。
   */
  async upsert(params: {
    sessionId: string;
    newapiKey: string;
    newapiTokenId?: string | null;
    tokenGeneration?: number;
  }): Promise<void> {
    if (!params.newapiKey) {
      throw new BadRequestException({
        code: 'session_newapi_token_map_invalid_key',
        message: 'newapiKey 不能为空字符串',
      });
    }
    await this.repo.upsert(
      {
        sessionId: params.sessionId,
        newapiKey: params.newapiKey,
        newapiTokenId: params.newapiTokenId ?? null,
        tokenGeneration: params.tokenGeneration ?? 1,
        revokedAt: null,
      },
      ['sessionId'],
    );
  }

  /** 回收（供未来 revoke 流程接线）——标记 `revokedAt`，不物理删除行（保留审计轨迹）。 */
  async revoke(sessionId: string): Promise<void> {
    await this.repo.update({ sessionId }, { revokedAt: new Date() });
  }
}
