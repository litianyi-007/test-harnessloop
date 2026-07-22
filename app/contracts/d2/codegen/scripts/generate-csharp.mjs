#!/usr/bin/env node
// D2 JSON Schema -> C# 类型 codegen。选型/限制与 generate-swift.mjs 完全对称：quicktype-core
// 生成叶子 DTO（scripts/lib/leaf-types.mjs 枚举的 30 个非顶层-oneOf 具名类型），判别联合包装
// （result/failure 互斥、11 事件按 type 判别、三层错误）手写于 scripts/handwritten/
// DiscriminatedUnions.cs（quicktype 对 oneOf 的坍缩 + 对 allOf 的静默丢字段两个缺陷，Swift/C#
// 共用同一个 quicktype-core 前端，两个缺陷在 C# 侧同样复现，见 ../CODEGEN-FINDINGS.md）。

import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { quicktype, InputData, JSONSchemaInput } from 'quicktype-core';
import { FileJSONSchemaStore } from './lib/file-schema-store.mjs';
import { leafTypes } from './lib/leaf-types.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaRoot = join(__dirname, '..', '..', 'schema');
const outDir = join(__dirname, '..', '..', '..', '..', 'generated', 'csharp');
const outFile = join(outDir, 'D2.cs');
const handwrittenSrc = join(__dirname, 'handwritten', 'DiscriminatedUnions.cs');
const handwrittenDst = join(outDir, 'DiscriminatedUnions.cs');

const banner = `// 本文件由 codegen 自动生成，不要手工编辑。
// 源：app/contracts/d2/schema/（scripts/lib/leaf-types.mjs 枚举的叶子类型清单）
// 生成命令：npm --prefix app/contracts/d2/codegen run gen:csharp
// 生成器：quicktype-core（quicktype 26.x），JSON Schema -> C# record/enum + System.Text.Json。
//
// 覆盖范围：全部『非顶层 oneOf』具名类型（8 个方法 request 消息 + 11 个事件消息 + res.unknown +
// 叶子 result/failure payload，共 30 个 top-level）。
//
// 不含：4 类顶层判别联合与 8 个方法各自的 *ResponseMessage——quicktype 无法保住这些 oneOf 判别
// 联合（已验证坍缩，见 ../../CODEGEN-FINDINGS.md），改在 DiscriminatedUnions.cs 手写（该文件
// 同目录，非本文件生成，由 generate-csharp.mjs 逐字拷贝 scripts/handwritten/DiscriminatedUnions.cs）。

`;

async function main() {
  const schemaInput = new JSONSchemaInput(new FileJSONSchemaStore(schemaRoot));

  for (const { schema, def } of leafTypes) {
    const entryPath = join(schemaRoot, schema);
    const entryUri = pathToFileURL(entryPath).toString();
    const entryText = await readFile(entryPath, 'utf8');
    const name = def ?? schema.split('/').pop().replace('.schema.json', '');
    const uri = def ? `${entryUri}#/$defs/${def}` : entryUri;
    await schemaInput.addSource({ name, schema: entryText, uris: [uri] });
  }

  const inputData = new InputData();
  inputData.addInput(schemaInput);

  const result = await quicktype({
    inputData,
    lang: 'csharp',
    rendererOptions: { namespace: 'D2', density: 'normal' },
    combineClasses: false,
  });

  await mkdir(outDir, { recursive: true });
  await writeFile(outFile, banner + result.lines.join('\n') + '\n', 'utf8');
  console.log(`[generate-csharp] 写入 ${outFile}（${result.lines.length} 行，${leafTypes.length} 个叶子类型）`);

  await copyFile(handwrittenSrc, handwrittenDst);
  console.log(`[generate-csharp] 拷贝手写判别联合包装类型 -> ${handwrittenDst}（源：scripts/handwritten/DiscriminatedUnions.cs，非 quicktype 产物，见 CODEGEN-FINDINGS.md）`);
}

main().catch((err) => {
  console.error('[generate-csharp] 失败：', err);
  process.exit(1);
});
