#!/usr/bin/env node
// C# 最小判别测试运行薄封装：`dotnet run` verify/csharp/Program.cs，跑最小判别测试三项
// （result/failure 互斥、11 事件判别、三层错误不串号），见该文件与 CODEGEN-FINDINGS.md。
// 若 dotnet 不可用，如实报告『待验』而非假装通过。

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const verifyDir = join(__dirname, '..', 'verify', 'csharp');

const which = spawnSync('which', ['dotnet']);
if (which.status !== 0) {
  console.log('[verify-csharp] dotnet 不可用——最小判别测试待验（未安装/未在 PATH）。');
  process.exit(0);
}

const result = spawnSync('dotnet', ['run', '--no-build'], { cwd: verifyDir, stdio: 'inherit' });
process.exit(result.status ?? 1);
