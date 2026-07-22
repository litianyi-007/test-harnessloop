import { Injectable } from '@nestjs/common';
import { ModelCatalogEntryDto } from './dto/model-catalog.dto';

/**
 * composer 模型选择器消费的模型/效力档位目录（D6→D3 新增依赖 2，供 D5.7）。
 *
 * 对应 d6-newapi-integration.md §6.3——"这张路由表的自然归属是 D3……应该是 Console（P6）
 * 的一个配置面，而不是硬编码在客户端里"。本骨架尚未建立"档位 → 具体 newapi 模型标识"
 * 路由表的持久化实体（不在本轮 TypeORM 实体范围内，且该路由表本身待 Console/P6 实现），
 * 如实返回空列表而非编造档位数据——`CreateSessionConfig.model → 内核透传 → newapi 路由`
 * 这条路径本身仍是"待冒烟确认"的推测性路径（D6 §6.2/§6.4，D1 §12 S-11 未消解），
 * 本骨架不代 D1/D6 裁决。
 */
@Injectable()
export class ModelsService {
  getModelCatalog(): { tiers: ModelCatalogEntryDto[] } {
    // TODO：接入 Console 侧路由表（档位 → newapi model 标识），见 d6-newapi-integration.md §6.3。
    return { tiers: [] };
  }
}
