#!/usr/bin/env node
// C# compile-verify 薄封装：`dotnet build` verify/csharp/ 下的最小项目（引用 app/generated/csharp/
// 的真实产物 D2.cs + DiscriminatedUnions.cs，不拷贝）。若 dotnet 不可用，如实报告『待验』而非假装
// 通过（见任务纪律）。

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const verifyDir = join(__dirname, '..', 'verify', 'csharp');

const which = spawnSync('which', ['dotnet']);
if (which.status !== 0) {
  console.log('[typecheck-csharp] dotnet 不可用——C# 生成完成，compile 待 dotnet（未安装/未在 PATH）。');
  process.exit(0);
}

const result = spawnSync('dotnet', ['build'], { cwd: verifyDir, stdio: 'inherit' });
if (result.status !== 0) {
  console.error('[typecheck-csharp] dotnet build 失败');
  process.exit(result.status ?? 1);
}
console.log('[typecheck-csharp] dotnet build 通过（D2.cs + DiscriminatedUnions.cs 编译成功）。');
