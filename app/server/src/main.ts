import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // 对应 openapi.yaml servers[0].url 模板 `https://{host}/api/d3/v1`——业务端点均落在这个前缀下；
  // /health 是基础设施探活端点，不属于 D3 契约面，特意排除在外（见 app.controller.ts 注释）。
  app.setGlobalPrefix('api/d3/v1', { exclude: ['health'] });

  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.useGlobalFilters(new HttpExceptionFilter());

  await app.listen(process.env.PORT ?? 3000);
}
void bootstrap();
