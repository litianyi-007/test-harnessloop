import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import * as jose from 'jose';
import { Repository } from 'typeorm';
import { LicenseRevocationEntity } from '../../database/entities';

const ALG = 'EdDSA';

/**
 * License JWT（Ed25519）签发/校验骨架——对应 server-stack-selection.md"应用内签发 Ed25519
 * JWT"、openapi GET /license/public-key、d5-6-account-license.md §4.1"License JWT 回答
 * '有权用什么'"。
 *
 * **校验逻辑本身是真实实现**（用 `jose` 的 EdDSA 支持，非桩逻辑）；**公钥/私钥来源是 x-todo**
 * （openapi.yaml GET /license/public-key description："具体密钥分发/轮换格式（是否 JWKS 标准
 * 格式）未定"）——本骨架从环境变量读取单个 PEM 字符串占位，未来若改用 JWKS/KMS 需要替换本服务
 * 的 key 加载方式，不改变对外调用签名（`verify`/`sign`）。
 *
 * 吊销检查：查 `license_revocations` 表按 `jti`——这是 server-stack-selection.md 明确列出的
 * "`licenses` + `revocations` 两张表"里 revocations 的落地（见 license-revocation.entity.ts
 * 头注释，该表非任务给定 6 实体清单点名，但源自同一份 confirmed 文档，不是臆造）。
 */
@Injectable()
export class LicenseJwtService {
  private readonly logger = new Logger(LicenseJwtService.name);

  constructor(
    private readonly config: ConfigService,
    @InjectRepository(LicenseRevocationEntity)
    private readonly revocationRepo: Repository<LicenseRevocationEntity>,
  ) {}

  /**
   * 对应 openapi GET /license/public-key——真实实现，前提是已配置公钥。
   * 保持 `Promise` 返回类型（而非改成同步）：未来换成 JWKS/KMS 分发时这里会是真正的异步
   * I/O，提前固定异步契约，调用方不需要因为实现方式变化而改签名。
   */
  getPublicKeyInfo(): Promise<{
    publicKey: string;
    alg: 'EdDSA';
    keyId?: string;
  }> {
    const publicKeyPem = this.requirePublicKey();
    return Promise.resolve({
      publicKey: publicKeyPem,
      alg: 'EdDSA',
      keyId: this.config.get<string>('licenseJwt.keyId'),
    });
  }

  /**
   * 校验一枚 License JWT：验签（EdDSA/Ed25519）+ 查吊销表。
   * x-todo：离线宽限期/强制在线刷新策略本身未裁决（见 openapi License.status description），
   * 本方法只做"这枚 JWT 本身是否合法且未被吊销"，不代为决定 grace_period 分支是否成立
   * ——分支呈现逻辑留给 license.service.ts。
   */
  async verify(token: string): Promise<jose.JWTPayload> {
    const publicKeyPem = this.requirePublicKey();
    const publicKey = await jose.importSPKI(publicKeyPem, ALG);

    const { payload } = await jose.jwtVerify(token, publicKey, {
      algorithms: [ALG],
    });

    if (payload.jti) {
      const revoked = await this.revocationRepo.findOne({
        where: { licenseJti: payload.jti },
      });
      if (revoked) {
        throw new jose.errors.JWTClaimValidationFailed(
          'License JWT 已被吊销',
          payload,
          'jti',
          'invalid',
        );
      }
    } else {
      this.logger.warn(
        'License JWT 未携带 jti，无法核对吊销列表——签发端 TODO 补充 jti 声明。',
      );
    }

    return payload;
  }

  /** 签发一枚 License JWT——供未来 Console(P6)/内部签发流程使用，本契约未暴露对应 HTTP 端点。 */
  async sign(
    claims: Record<string, unknown>,
    options: { expiresIn: string; jti?: string },
  ): Promise<string> {
    const privateKeyPem = this.config.get<string>('licenseJwt.privateKey');
    if (!privateKeyPem) {
      throw new InternalServerErrorException(
        'LICENSE_JWT_PRIVATE_KEY 未配置，无法签发 License JWT（见 app/server/README.md）。',
      );
    }
    const privateKey = await jose.importPKCS8(privateKeyPem, ALG);

    let builder = new jose.SignJWT(claims)
      .setProtectedHeader({
        alg: ALG,
        kid: this.config.get<string>('licenseJwt.keyId'),
      })
      .setIssuedAt()
      .setExpirationTime(options.expiresIn);

    if (options.jti) {
      builder = builder.setJti(options.jti);
    }

    return builder.sign(privateKey);
  }

  private requirePublicKey(): string {
    const publicKeyPem = this.config.get<string>('licenseJwt.publicKey');
    if (!publicKeyPem) {
      throw new InternalServerErrorException(
        'LICENSE_JWT_PUBLIC_KEY 未配置，无法校验/分发 License JWT 公钥（见 app/server/README.md）。',
      );
    }
    return publicKeyPem;
  }
}
