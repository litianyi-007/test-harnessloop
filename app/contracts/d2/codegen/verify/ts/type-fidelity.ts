/**
 * Type-level 保真断言（SG-3 验收缺口，rounds/0007）——对真实生成产物
 * app/generated/ts/d2.d.ts 做编译期负例验证，不是注释式自证：用 `@ts-expect-error`，tsc 对
 * "下一行其实没有报错"的 `@ts-expect-error` 指令本身会报 `TS2578 Unused '@ts-expect-error'
 * directive` 错误——所以这是编译器强制的负例检查，负例行如果不再真的出错，本文件本身就编译
 * 不过，不依赖任何人工判断。
 *
 * 覆盖 ②：WireCapabilityDescriptorPayload —— protocolVersion 必须被排除
 * （CapabilityDescriptorPayload 去掉该字段的版本，evt.capability_changed 专用，见
 * common/capability-descriptor.schema.json）。验证：完整字段的合法字面量可以赋值；额外携带
 * protocolVersion 的字面量必须报错（即使其余字段全部合法）。
 *
 * 不覆盖 ①：EmptyPayload 精确空对象——本轮探针实测确认，`export interface EmptyPayload {}`
 * 是 TS 的裸 `{}` 结构类型，TS 编译器对"赋值给声明为零属性的接口"这一特定情形不做多余属性
 * 检查（TS 语言本身把裸空接口 `{}` 当作"任意非 null/undefined 值"，而不是"零属性的精确形状"
 * ——对照组：`Record<string, never>`、或任意"至少一个属性"的接口都会正常拒绝多余属性，唯独
 * 裸空接口不会）。也就是说 `const bad: EmptyPayload = { extra: 1 };` 在当前生成产物上编译
 * 通过，不会报错。这是 SG-1 codegen 的真实精度缺陷（TS 侧），不是断言写错，也不该被"换一种
 * 更弱的断言让它看起来通过"糊弄过去——本文件只断言"合法值可赋值"这一半，缺陷的证据留在
 * `type-fidelity-known-gap.ts`（未接入 npm run gen / CI：接入的话要么强行用 `|| true` 之类
 * 软放水掩盖一个已知未修的缺陷，要么让 CI 永久卡红在一个本轮明确不修、已如实上报 blocker 的
 * 问题上，两者都不对，所以单独留档），详见 round 0007 handoff「blocker」章节。
 */
import type { EmptyPayload, WireCapabilityDescriptorPayload } from '../../../../../generated/ts/d2';

// ① EmptyPayload —— 只断言"合法值（唯一合法值就是 {}）可以赋值"这一半，另一半见上。
const emptyOk: EmptyPayload = {};
void emptyOk;

// ② WireCapabilityDescriptorPayload —— 完整合法字面量必须能赋值（对照组）。
const wireOk: WireCapabilityDescriptorPayload = {
  kernel: 'openclaw',
  snapshotAt: '2026-07-22T00:00:00Z',
  tools: { discoverable: true },
  approvalGranularity: 'per-tool',
  approvalKinds: ['exec'],
  approvalDecisionKinds: ['allow_once'],
  interruptModes: ['steer'],
  streamingGranularity: 'token-delta',
  sessionResume: true,
  thinkingVisibility: 'none',
  usageReporting: 'none',
  billingAttribution: 'session',
};
void wireOk;

// ② 负例：protocolVersion 必须被拒绝，即使其余字段全部合法（排除字段类型保真）。
const wireBad: WireCapabilityDescriptorPayload = {
  ...wireOk,
  // @ts-expect-error — WireCapabilityDescriptorPayload 必须排除 protocolVersion（D2 v3 §4/§7.1）
  protocolVersion: 'kernelport/1',
};
void wireBad;
