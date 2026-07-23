import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import configuration from './config/configuration';
import { validateEnv } from './config/env.validation';
import { DatabaseModule } from './database/database.module';
import { AuthModule } from './modules/auth/auth.module';
import { LicenseModule } from './modules/license/license.module';
import { TenantModule } from './modules/tenant/tenant.module';
import { CapabilitiesModule } from './modules/capabilities/capabilities.module';
import { BillingModule } from './modules/billing/billing.module';
import { SessionTokenModule } from './modules/session-token/session-token.module';
import { NewApiManagementModule } from './modules/newapi-management/newapi-management.module';
import { ModelsModule } from './modules/models/models.module';
import { SessionProxyModule } from './modules/session-proxy/session-proxy.module';

/**
 * D3 瘦控制面 server 根模块——8 个业务模块对应 openapi.yaml 8 组 tag
 * （Auth/License/TenantSeat/Capabilities/Billing/SessionToken/NewApiManagement/ModelCatalog），
 * 见 app/server/README.md「模块 ↔ openapi tag 对应表」。
 *
 * `SessionProxyModule` 是第9个模块，但**不对应任何 openapi tag**——它是 SG-6（C-3 path①
 * session 级计费归因）的 D3-proxy 反向代理面，鉴权/契约形状与前8个模块（JWT bearer +
 * 结构化 DTO）完全不同，见 session-proxy.controller.ts 头注释。
 */
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      validate: validateEnv,
    }),
    DatabaseModule,
    AuthModule,
    LicenseModule,
    TenantModule,
    CapabilitiesModule,
    BillingModule,
    SessionTokenModule,
    NewApiManagementModule,
    ModelsModule,
    SessionProxyModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
