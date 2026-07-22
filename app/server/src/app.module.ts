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

/**
 * D3 瘦控制面 server 根模块——8 个业务模块对应 openapi.yaml 8 组 tag
 * （Auth/License/TenantSeat/Capabilities/Billing/SessionToken/NewApiManagement/ModelCatalog），
 * 见 app/server/README.md「模块 ↔ openapi tag 对应表」。
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
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
