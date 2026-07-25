#!/usr/bin/env node
// Type-level 保真断言编排（SG-3 验收缺口，rounds/0007）——见
// verify/swift/type-fidelity.swift 头部注释。该文件里两个负例分别包在同名 `#if SG3_NEGATIVE_*`
// 编译条件后面，默认（无 -D 标志）不参与编译；本脚本用 `swiftc -typecheck -D <FLAG>` 依次单独
// 点燃每一个，并断言该次编译必须以非零退出码失败——若某次意外以 0 退出（负例编译通过了），
// 说明生成产物对应的精度保证已被打破，本脚本判定为 FAIL 并非零退出（不是"待验"，是真失败，
// swiftc 本身缺失时才是真的环境问题，见下）。

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const codegenDir = join(__dirname, '..');
const genSwiftDir = join(codegenDir, '..', '..', '..', 'generated', 'swift');
const typeFidelityFile = join(codegenDir, 'verify', 'swift', 'type-fidelity.swift');

const which = spawnSync('which', ['swiftc']);
if (which.status !== 0) {
  if (process.env.CI === 'true') {
    console.error('[verify-type-fidelity-swift] swiftc 不可用——CI 下硬失败（CI=true）。');
    process.exit(1);
  }
  console.log('[verify-type-fidelity-swift] swiftc 不可用——type-level 负例待验（未安装/未在 PATH）。');
  process.exit(0);
}

const cases = [
  { flag: 'SG3_NEGATIVE_EMPTY_PAYLOAD_EXTRA_FIELD', label: 'EmptyPayload 拒绝额外字段' },
  {
    flag: 'SG3_NEGATIVE_WIRE_CAPABILITY_PROTOCOL_VERSION',
    label: 'WireCapabilityDescriptorPayload（生成产物中名为 Capabilit）排除 protocolVersion',
  },
];

let failures = 0;

for (const { flag, label } of cases) {
  const result = spawnSync(
    'swiftc',
    [
      '-typecheck',
      '-D',
      flag,
      join(genSwiftDir, 'D2.swift'),
      join(genSwiftDir, 'DiscriminatedUnions.swift'),
      typeFidelityFile,
    ],
    { encoding: 'utf8' },
  );
  if (result.status === 0) {
    console.error(
      `[verify-type-fidelity-swift] FAIL —— 负例「${label}」（-D ${flag}）意外编译通过，说明该精度保证已被打破。`,
    );
    failures++;
  } else {
    console.log(`[verify-type-fidelity-swift] PASS —— 负例「${label}」（-D ${flag}）如预期编译失败。`);
  }
}

if (failures > 0) {
  console.error(`[verify-type-fidelity-swift] ${failures} 项负例未能如预期失败。`);
  process.exit(1);
}
console.log('[verify-type-fidelity-swift] 全部负例如预期编译失败，type-level 断言有牙齿。');
