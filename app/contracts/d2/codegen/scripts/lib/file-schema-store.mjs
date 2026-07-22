// 供 quicktype-core 使用的文件系统 JSONSchemaStore：把 schema 内部的相对 $ref
// （如 "../common/envelope.schema.json#/$defs/eventEnvelopeBase"）解析为对
// app/contracts/d2/schema/ 目录下真实文件的读取。quicktype 在解析 $ref 时会把
// 地址解析成相对路径字符串（未必是完整 file:// URL），故 fetch() 同时兼容两种形式。

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { JSONSchemaStore } from 'quicktype-core';

export class FileJSONSchemaStore extends JSONSchemaStore {
  constructor(schemaRoot) {
    super();
    this.schemaRoot = schemaRoot;
  }

  async fetch(address) {
    let filePath;
    try {
      filePath = fileURLToPath(address);
    } catch {
      filePath = join(this.schemaRoot, address);
    }
    const text = await readFile(filePath, 'utf8');
    return JSON.parse(text);
  }
}
