import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ModelCatalogEntryDto } from './dto/model-catalog.dto';
import { ModelsService } from './models.service';

/** tag: ModelCatalog（openapi.yaml）。 */
@Controller()
export class ModelsController {
  constructor(private readonly modelsService: ModelsService) {}

  /** operationId: getModelCatalog — openapi 全局 bearerAuth（无覆盖）。 */
  @UseGuards(JwtAuthGuard)
  @Get('models/catalog')
  getModelCatalog(): { tiers: ModelCatalogEntryDto[] } {
    return this.modelsService.getModelCatalog();
  }
}
