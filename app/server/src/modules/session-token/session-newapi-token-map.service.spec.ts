import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SessionNewApiTokenEntity } from '../../database/entities';
import { SessionNewApiTokenMapService } from './session-newapi-token-map.service';

describe('SessionNewApiTokenMapService', () => {
  let service: SessionNewApiTokenMapService;
  let repo: jest.Mocked<Repository<SessionNewApiTokenEntity>>;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SessionNewApiTokenMapService,
        {
          provide: getRepositoryToken(SessionNewApiTokenEntity),
          useValue: {
            findOne: jest.fn(),
            upsert: jest.fn(),
            update: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get(SessionNewApiTokenMapService);
    repo = module.get(getRepositoryToken(SessionNewApiTokenEntity));
  });

  describe('findActive', () => {
    it('命中未回收的映射时返回真实 newapi key（map 命中）', async () => {
      repo.findOne.mockResolvedValue({
        sessionId: 'sess-1',
        newapiKey: 'sk-real-newapi-key',
        newapiTokenId: null,
        tokenGeneration: 1,
        revokedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      const result = await service.findActive('sess-1');

      expect(result).toEqual({
        newapiKey: 'sk-real-newapi-key',
        newapiTokenId: null,
        tokenGeneration: 1,
      });
      // eslint-disable-next-line @typescript-eslint/unbound-method -- jest.Mocked 方法引用，非真实 this 绑定风险
      expect(repo.findOne).toHaveBeenCalledWith(
        expect.objectContaining({
          // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment -- expect.objectContaining 的既有 any 返回类型
          where: expect.objectContaining({ sessionId: 'sess-1' }),
        }),
      );
    });

    it('未查到映射时返回 null（map 未命中，交由调用方处理兜底）', async () => {
      repo.findOne.mockResolvedValue(null);

      const result = await service.findActive('unknown-session');

      expect(result).toBeNull();
    });

    it('T-042 NOTE：命中的行 newapiKey 是空字符串时按未命中处理，不放行脏数据', async () => {
      repo.findOne.mockResolvedValue({
        sessionId: 'sess-empty-key',
        newapiKey: '',
        newapiTokenId: null,
        tokenGeneration: 1,
        revokedAt: null,
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      const result = await service.findActive('sess-empty-key');

      expect(result).toBeNull();
    });
  });

  describe('upsert/revoke', () => {
    it('upsert 按 sessionId 冲突键写入，默认代次为 1', async () => {
      await service.upsert({ sessionId: 'sess-2', newapiKey: 'sk-2' });

      // eslint-disable-next-line @typescript-eslint/unbound-method -- jest.Mocked 方法引用，非真实 this 绑定风险
      expect(repo.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          sessionId: 'sess-2',
          newapiKey: 'sk-2',
          newapiTokenId: null,
          tokenGeneration: 1,
          revokedAt: null,
        }),
        ['sessionId'],
      );
    });

    it('T-042 NOTE：newapiKey 为空字符串时拒绝写入（400），不落脏数据', async () => {
      await expect(
        service.upsert({ sessionId: 'sess-3', newapiKey: '' }),
      ).rejects.toMatchObject({
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment -- expect.objectContaining 的既有 any 返回类型
        response: expect.objectContaining({
          code: 'session_newapi_token_map_invalid_key',
        }),
      });
      // eslint-disable-next-line @typescript-eslint/unbound-method -- jest.Mocked 方法引用，非真实 this 绑定风险
      expect(repo.upsert).not.toHaveBeenCalled();
    });

    it('revoke 标记 revokedAt，不物理删除', async () => {
      await service.revoke('sess-2');

      // eslint-disable-next-line @typescript-eslint/unbound-method -- jest.Mocked 方法引用，非真实 this 绑定风险
      expect(repo.update).toHaveBeenCalledWith(
        { sessionId: 'sess-2' },
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment -- expect.objectContaining 的既有 any 返回类型
        expect.objectContaining({ revokedAt: expect.any(Date) }),
      );
    });
  });
});
