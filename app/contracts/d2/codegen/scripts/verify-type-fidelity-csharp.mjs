#!/usr/bin/env node
// Type-level 保真断言编排（SG-3 验收缺口，rounds/0007）——见
// verify/csharp-type-fidelity/TypeFidelity.cs 头部注释。该文件里两个负例分别包在同名
// `#if SG3_NEGATIVE_*` 编译条件后面，默认（不传 DefineConstants）不参与编译；本脚本用
// `dotnet build -p:DefineConstants=<FLAG>` 依次单独点燃每一个，并断言该次 build 必须以非零
// 退出码失败——若某次意外以 0 退出（负例编译通过了），说明生成产物对应的精度保证已被打破，
// 本脚本判定为 FAIL 并非零退出。
//
// dotnet 缺失时的行为与 verify-csharp.mjs 同款约定：本地如实报告『待验』，CI 下（CI=true）
// 硬失败，不软跳过。

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const verifyDir = join(__dirname, '..', 'verify', 'csharp-type-fidelity');

const which = spawnSync('which', ['dotnet']);
if (which.status !== 0) {
  if (process.env.CI === 'true') {
    console.error('[verify-type-fidelity-csharp] dotnet 不可用——CI 下硬失败（CI=true）。');
    process.exit(1);
  }
  console.log('[verify-type-fidelity-csharp] dotnet 不可用——type-level 负例待验（未安装/未在 PATH）。');
  process.exit(0);
}

const cases = [
  { flag: 'SG3_NEGATIVE_EMPTY_PAYLOAD_EXTRA_FIELD', label: 'EmptyPayload 拒绝额外字段' },
  {
    flag: 'SG3_NEGATIVE_WIRE_CAPABILITY_PROTOCOL_VERSION',
    label: 'WireCapabilityDescriptorPayload（生成产物中名为 Capabilit）排除 ProtocolVersion',
  },
];

let failures = 0;

for (const { flag, label } of cases) {
  const result = spawnSync('dotnet', ['build', `-p:DefineConstants=${flag}`, '--no-incremental'], {
    cwd: verifyDir,
    encoding: 'utf8',
  });
  if (result.status === 0) {
    console.error(
      `[verify-type-fidelity-csharp] FAIL —— 负例「${label}」（DefineConstants=${flag}）意外编译通过，说明该精度保证已被打破。`,
    );
    failures++;
  } else {
    console.log(
      `[verify-type-fidelity-csharp] PASS —— 负例「${label}」（DefineConstants=${flag}）如预期编译失败。`,
    );
  }
}

// 收尾：还原一次不带任何 DefineConstants 的 build，确认默认路径（positive control：EmptyPayload()
// 零参构造 + Capabilit 完整字段构造）依然通过——同时把项目恢复到干净的默认编译状态。
const restore = spawnSync('dotnet', ['build'], { cwd: verifyDir, encoding: 'utf8' });
if (restore.status !== 0) {
  console.error('[verify-type-fidelity-csharp] FAIL —— 默认（无 DefineConstants）build 未能通过，positive control 本身坏了。');
  console.error(restore.stdout);
  failures++;
} else {
  console.log('[verify-type-fidelity-csharp] PASS —— 默认（无 DefineConstants）positive control build 通过。');
}

if (failures > 0) {
  console.error(`[verify-type-fidelity-csharp] ${failures} 项未达预期。`);
  process.exit(1);
}
console.log('[verify-type-fidelity-csharp] 全部负例如预期编译失败 + positive control 通过，type-level 断言有牙齿。');
