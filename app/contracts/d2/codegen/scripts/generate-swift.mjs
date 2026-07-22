#!/usr/bin/env node
// D2 JSON Schema -> Swift 类型 codegen。
//
// 选型：quicktype（quicktype-core，26.x），JSON Schema -> Swift Codable struct/enum。
// **不））**把顶层判别联合（RequestMessage/ResponseMessage/EventMessage/Message，及 8 个方法各自
// 的 *ResponseMessage）整体喂给 quicktype——已验证 quicktype 对 oneOf 判别联合会做『结构相容即
// 合并』的类型统一，我们的 envelope 字段在所有分支间高度重叠，导致合并成一个『所有字段都可选』
// 的单一 struct，`result`/`failure` 互斥、11 事件按 type 判别、三层错误互不相通——三项判别联合
// 全部坍缩（`combineClasses:false` 对此无效，坍缩发生在 oneOf 解析阶段本身，不是后续图重写阶段）。
// 详见 ../CODEGEN-FINDINGS.md。
//
// 本脚本改为：把 scripts/lib/leaf-types.mjs 枚举的『非顶层 oneOf』具名类型逐个作为独立 top-level
// 喂给 quicktype（已验证：只要不经过 quicktype 自己解析 oneOf，即便结构高度相似的类型如
// RejectionFailure/ProtocolFailure/BillingQueryFailure 也能保持独立，不会被错误合并）。
// 判别联合本身（4 类顶层 + 8 个方法 response）改为手写 Swift enum 包装类型，
// 见 discriminated-unions.swift（随本脚本一并写出）——这是『需要后处理才能存活』的具体产物。

import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { quicktype, InputData, JSONSchemaInput } from 'quicktype-core';
import { FileJSONSchemaStore } from './lib/file-schema-store.mjs';
import { leafTypes } from './lib/leaf-types.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaRoot = join(__dirname, '..', '..', 'schema');
const outDir = join(__dirname, '..', '..', '..', '..', 'generated', 'swift');
const outFile = join(outDir, 'D2.swift');
const handwrittenSrc = join(__dirname, 'handwritten', 'discriminated-unions.swift');
const handwrittenDst = join(outDir, 'DiscriminatedUnions.swift');

const banner = `// 本文件由 codegen 自动生成，不要手工编辑。
// 源：app/contracts/d2/schema/（scripts/lib/leaf-types.mjs 枚举的叶子类型清单）
// 生成命令：npm --prefix app/contracts/d2/codegen run gen:swift
// 生成器：quicktype-core（quicktype 26.x），JSON Schema -> Swift Codable struct/enum。
//
// 覆盖范围：全部『非顶层 oneOf』具名类型（8 个方法 request 消息 + 11 个事件消息 +
// res.unknown + 叶子 result/failure payload，共 30 个 top-level）。
//
// 不含：4 类顶层判别联合（RequestMessage/ResponseMessage/EventMessage/Message）与 8 个方法各自
// 的 *ResponseMessage——quicktype 无法保住这些 oneOf 判别联合（已验证坍缩，见
// ../../CODEGEN-FINDINGS.md），改在 DiscriminatedUnions.swift 手写（该文件同目录，非本文件生成，
// 由 generate-swift.mjs 逐字拷贝 scripts/handwritten/discriminated-unions.swift）。

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
    lang: 'swift',
    rendererOptions: { 'struct-or-class': 'struct', 'access-level': 'public' },
    combineClasses: false,
  });

  await mkdir(outDir, { recursive: true });
  await writeFile(outFile, banner + result.lines.join('\n') + '\n', 'utf8');
  console.log(`[generate-swift] 写入 ${outFile}（${result.lines.length} 行，${leafTypes.length} 个叶子类型）`);

  await copyFile(handwrittenSrc, handwrittenDst);
  console.log(`[generate-swift] 拷贝手写判别联合包装类型 -> ${handwrittenDst}（源：scripts/handwritten/discriminated-unions.swift，非 quicktype 产物，见 CODEGEN-FINDINGS.md）`);
}

main().catch((err) => {
  console.error('[generate-swift] 失败：', err);
  process.exit(1);
});
