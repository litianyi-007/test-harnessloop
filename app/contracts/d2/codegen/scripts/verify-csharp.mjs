#!/usr/bin/env node
// C# 最小判别测试运行薄封装：`dotnet run` verify/csharp/Program.cs，跑最小判别测试三项
// （result/failure 互斥、11 事件判别、三层错误不串号），见该文件与 CODEGEN-FINDINGS.md。
// 若 dotnet 不可用：本地如实报告『待验』而非假装通过；CI 下（CI=true，见 rounds/0007
// scope-lock「verify:csharp 在 CI 下 dotnet 缺失从软跳过改硬失败」）视为硬失败——CI 环境本应
// 由 setup-dotnet 保证 dotnet 就绪，缺失即代表 CI 配置本身出了问题，不该被这一步悄悄放行。

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const verifyDir = join(__dirname, '..', 'verify', 'csharp');

const which = spawnSync('which', ['dotnet']);
if (which.status !== 0) {
  if (process.env.CI === 'true') {
    console.error('[verify-csharp] dotnet 不可用——CI 下硬失败（CI=true，见 rounds/0007 scope-lock）。');
    process.exit(1);
  }
  console.log('[verify-csharp] dotnet 不可用——最小判别测试待验（未安装/未在 PATH）。');
  process.exit(0);
}

const result = spawnSync('dotnet', ['run', '--no-build'], { cwd: verifyDir, stdio: 'inherit' });
process.exit(result.status ?? 1);
