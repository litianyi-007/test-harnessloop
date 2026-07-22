#!/usr/bin/env node
// D2 JSON Schema -> TypeScript 类型 codegen——本轮打通的样板管线（"先打通 schema→TS 这一条
// 作为样板，最易验证"，见任务书）。用 json-schema-to-typescript 的 compileFromFile，从
// message.schema.json 出发（它 $ref 了 methods/*、events/*、common/* 全部 schema），
// 一次性 bundle + 生成本轮覆盖的全部具名类型。
//
// 生成的 TS 仅供开发期 fixture 工具/oracle 使用，不进产品打包（D4 §3.5"生成目标语言"小节：
// TS 是"重新生成"的产物之一，用于消除手写 D2 markdown TS 与机器可读 schema 的双重真相线）。
// Swift/C# 生成器是下一步，见 codegen/README.md。

import { compileFromFile } from 'json-schema-to-typescript';
import { writeFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaEntry = join(__dirname, '..', '..', 'schema', 'message.schema.json');
const outDir = join(__dirname, '..', '..', '..', '..', 'generated', 'ts');
const outFile = join(outDir, 'd2.d.ts');

const banner = `/**
 * 本文件由 codegen 自动生成，不要手工编辑。
 * 源：app/contracts/d2/schema/message.schema.json（+ 其 $ref 的 methods/*、events/*、common/*）
 * 生成命令：npm --prefix app/contracts/d2/codegen run gen:ts
 * 覆盖范围（本轮 PRE-②/SG-1 骨架，非全量）：见 message.schema.json 顶层 $comment 的 TODO 清单。
 * 仅供开发期 fixture 工具 / TS oracle 使用（D4 §1.4/§4.4），不进任何产品打包。
 */
`;

async function main() {
  const ts = await compileFromFile(schemaEntry, {
    bannerComment: '',
    style: { singleQuote: true },
    additionalProperties: false,
    unreachableDefinitions: true,
  });
  await mkdir(outDir, { recursive: true });
  await writeFile(outFile, banner + '\n' + ts, 'utf8');
  console.log(`[generate-ts] 写入 ${outFile}（${ts.split('\n').length} 行）`);
}

main().catch((err) => {
  console.error('[generate-ts] 失败：', err);
  process.exit(1);
});
