import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * D3 自己维护的 session → newapi token 映射表——d6-newapi-integration.md §3.1 步骤②
 * "`name=session-<sessionId>` 铸造 token"、§4.2 职责4"session token 生命周期代理"
 * 均要求 D3 维护这张表；本表是 D3-proxy（session-proxy 模块，SG-6 C-3 path①的实质工作）
 * 据以查找"这个 session 该用哪把真实 newapi key"的唯一数据源。
 *
 * **写入方（mint）当前受阻，本表预期为空是诚实状态，不是本表设计的缺陷**：
 * `NewApiClientService.mintSessionToken` 因 newapi token 创建响应不含 `id`、
 * `GET/DELETE /api/token/:id` 反查机制未闭合（d6-newapi-integration.md §3.1 步骤②详注、
 * §7 #11）而抛 `NotImplementedException`，尚未真正调用 newapi 铸造 token、也尚未写入
 * 本表。x-todo：待该反查缺口解决、`SessionTokenService.mintSessionBillingToken` 真正
 * 落地后，应在铸造成功处调用 `SessionNewApiTokenMapService.upsert(...)` 写入本表；
 * 回收（`revokeSessionBillingToken`）应调用 `revoke(...)`。测试/开发环境下可通过
 * `upsert` 手工种入映射数据以验证 session-proxy 的转发链路。
 */
@Entity('session_newapi_tokens')
export class SessionNewApiTokenEntity {
  /** openclaw/D1 侧的 sessionId（d6-newapi-integration.md §3.1 步骤①的 adapter 本地 UUID）。 */
  @PrimaryColumn({ name: 'session_id', type: 'varchar' })
  sessionId!: string;

  /**
   * 该 session 对应的真实 newapi 明文 key（D6 §3.1 步骤③ `GetTokenKey` 取得）。
   *
   * x-todo（生产前必须处理，骨架阶段如实标注不遮掩）：生产环境应对该列做静态加密
   * （如 pgcrypto/应用层信封加密），当前骨架按明文列存储——这只是把"D3 是 newapi
   * 唯一凭证持有者"这一 D6 硬约束落到最小可用实现，不代表已完成加密静态存储这项
   * 安全加固；应用层（session-proxy）绝不把本字段值写入日志（见 session-proxy.service.ts）。
   */
  @Column({ name: 'newapi_key', type: 'varchar' })
  newapiKey!: string;

  /**
   * newapi token 的 `:id`（`GET/DELETE /api/token/:id` 所需）——D6 §3.1 步骤②该反查缺口
   * 未闭合前允许为 null（铸造侧尚无法取得）；缺口解决后写入方应回填，用于步骤⑥ DELETE 回收。
   */
  @Column({ name: 'newapi_token_id', type: 'varchar', nullable: true })
  newapiTokenId!: string | null;

  /**
   * token 生命周期代次（d6-newapi-integration.md §3.3 v2.2"去重键改为
   * `(sessionId, tokenGeneration)`"）：同一 sessionId 每次 resume 重新铸造应递增本字段，
   * 避免旧代次的终结信号误命中新代次的回收状态。首次铸造为 1。
   */
  @Column({ name: 'token_generation', type: 'int', default: 1 })
  tokenGeneration!: number;

  /** 回收时间戳；null 表示当前仍是该 session 的有效映射（session-proxy 只应使用未回收的行）。 */
  @Column({ name: 'revoked_at', type: 'timestamptz', nullable: true })
  revokedAt!: Date | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt!: Date;
}
