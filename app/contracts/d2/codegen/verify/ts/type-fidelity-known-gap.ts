/**
 * NOT wired into `npm run gen` / CI — this file is evidence, not a gate.
 *
 * SG-3 rounds/0007 type-level 断言在跑 EmptyPayload 的负例时，如实"揪出"了一个 SG-1 codegen
 * 精度缺陷（见 round 0007 handoff「blocker」章节，附本文件 tsc 输出作证据）：
 *
 *   `export interface EmptyPayload {}`（app/generated/ts/d2.d.ts，json-schema-to-typescript
 *   从 `additionalProperties:false + properties:{}` 翻译而来）在 TS 类型系统里不是"零属性的
 *   精确形状"，而是 TS 对裸空接口 `{}` 的特殊处理——等价于"任意非 null/undefined 值"。下面这行
 *   `@ts-expect-error` 期待的编译错误不会发生，于是 tsc 会把"没用上的 @ts-expect-error 指令"
 *   本身报成一个编译错误（TS2578）。这不是这份探针写错了，是生成产物真的不精确——见文件头引用的
 *   round 0007 handoff 全文，以及 schema 文件
 *   app/contracts/d2/schema/common/empty-payload.schema.json 自己的 $comment（其中提到 TS 手写
 *   代码需要 `Record<string, never>` 才能封闭 `{}`——但 json-schema-to-typescript 实际生成的
 *   就是未封闭的裸 `{}`，两者的落差正是这个缺陷）。
 *
 * 跑法（手工，不接入任何 npm script）：
 *   cd app/contracts/d2/codegen
 *   ./node_modules/.bin/tsc --noEmit --strict --target es2022 --module esnext \
 *     --moduleResolution bundler --allowImportingTsExtensions \
 *     verify/ts/type-fidelity-known-gap.ts
 *   # 预期：非零退出，报 TS2578 Unused '@ts-expect-error' directive ——这正是"缺陷被断言揪出"
 *   # 的实证，不是这份文件本身写错。
 *
 * 修复方向留给 SG-1（本轮范围之外，不得擅改 schema/生成器脚本）：把 generate-ts.mjs 对
 * `properties:{} + additionalProperties:false` 的 leaf schema 翻译成
 * `Record<string, never>`（或等价的封闭空对象类型），而不是原样透传 json-schema-to-typescript
 * 对空 properties 的默认输出。
 */
import type { EmptyPayload } from '../../../../../generated/ts/d2';

const emptyOk: EmptyPayload = {};
void emptyOk;

// 下面这行 ts-expect-error 指令预期会被 tsc 判定为「Unused」而编译失败——EmptyPayload 应该
// 拒绝额外字段（additionalProperties:false），但当前生成的裸 `export interface EmptyPayload {}`
// 不会报错，这正是待记录的 SG-1 精度缺陷，编译失败本身就是证据。
// @ts-expect-error
const emptyBad: EmptyPayload = { sg3ShouldNotExist: 1 };
void emptyBad;
