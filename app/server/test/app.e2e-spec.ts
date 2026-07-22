import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';

// NOTE：本 e2e 骨架需要一个真实可连接的 PostgreSQL（DatabaseModule 用 TypeOrmModule.forRootAsync
// 真实连接，未 mock）+ 完整 env（见 config/env.validation.ts），本轮任务范围（SG-2 可编译骨架）
// 不含起数据库/填 env 跑通 e2e，`npm run build` 不执行本文件（tsconfig.build.json 已排除 test/）。
describe('AppController (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  it('/health (GET)', () => {
    return request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok', service: 'd3-control-plane' });
  });

  afterEach(async () => {
    await app.close();
  });
});
