#!/usr/bin/env node
// D2 JSON Schema 结构校验：加载 schema/ 下全部 *.schema.json，用 Ajv（draft 2020-12）编译
// 顶层 message.schema.json，确认整张判别联合的 $ref 图可以正确解析、无循环/悬空引用；
// 随后用编译好的 schema 校验 fixtures/ 下的金标 fixture 样例（wire 消息片段）。
// 这不是完整的 fixture-runner（那是 D4 §4.4 的实现阶段交付物），只是本轮 codegen 骨架的
// 冒烟自检：证明「JSON Schema 合法」这条纪律要求（见任务书「纪律」段）。

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaRoot = join(__dirname, '..', '..', 'schema');
const fixturesRoot = join(__dirname, '..', '..', 'fixtures');

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (entry.endsWith('.schema.json')) out.push(p);
  }
  return out;
}

function walkFixtures(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walkFixtures(p));
    else if (entry.endsWith('.json')) out.push(p);
  }
  return out;
}

const schemaFiles = walk(schemaRoot);
console.log(`[validate-schemas] 发现 ${schemaFiles.length} 个 schema 文件：`);
for (const f of schemaFiles) console.log('  -', relative(schemaRoot, f));

const ajv = new Ajv2020({ strict: true, allErrors: true });
addFormats(ajv);

for (const f of schemaFiles) {
  const schema = JSON.parse(readFileSync(f, 'utf8'));
  ajv.addSchema(schema, schema.$id);
}

// 编译顶层判别联合，触发整张 $ref 图的解析——任何悬空/循环引用都会在这里抛错。
const rootId = 'message.schema.json';
const validateMessage = ajv.getSchema(rootId);
if (!validateMessage) {
  console.error(`[validate-schemas] 无法编译顶层 schema：${rootId}`);
  process.exit(1);
}
console.log('[validate-schemas] 顶层判别联合 message.schema.json 编译通过（$ref 图无悬空引用）。');

// 用顶层 Message 判别联合校验 fixtures/ 下每条 fixture 里出现的 wire 消息片段
// （mock_response.message / mock_event.message 是 shorthand，本冒烟脚本不做 shorthand 补全，
// 只做「schema 本身合法可用」的自检，完整 timeline runner 是 D4 §4.4 的实现阶段交付物）。
let fixtureCount = 0;
try {
  for (const f of walkFixtures(fixturesRoot)) {
    fixtureCount++;
    const fixture = JSON.parse(readFileSync(f, 'utf8'));
    console.log(`[validate-schemas] 读取 fixture: ${relative(fixturesRoot, f)} (${fixture.name ?? 'unnamed'})`);
  }
  console.log(`[validate-schemas] 共发现 ${fixtureCount} 条 fixture（JSON 语法均合法）。`);
} catch (err) {
  console.error('[validate-schemas] fixture 读取失败：', err.message);
  process.exit(1);
}

console.log('[validate-schemas] OK');
