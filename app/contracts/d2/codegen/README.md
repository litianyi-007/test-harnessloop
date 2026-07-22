# D2 codegen 管线

对应 D4 跨平台架构 v2.2 §3.5/§3.6：从 `contracts/d2/schema/` 的 JSON Schema 生成 Swift + C# +
TS 三种语言的**数据类型**（不含协议骨架/client stub——那部分按 D4 §3.6 v2 裁决是手写的，
authority 是 D1 散文，见 `~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`
§3.6「为何不生成机器可读 operation IDL」）。

## 本轮打通的样板：schema → TS

选型：`json-schema-to-typescript`（D4 §3.3 第 2 条推荐的 TS 生成工具之一）。

```bash
cd app/contracts/d2/codegen
npm install
npm run gen        # = validate（Ajv 结构校验）+ gen:ts（生成）+ typecheck:ts（tsc --strict 验证产物）
```

- `npm run validate` —— 用 Ajv（draft 2020-12）加载全部 schema，编译顶层判别联合
  `message.schema.json`，确认 `$ref` 图无悬空/循环引用；同时做 fixtures/ 下全部 fixture 的
  JSON 语法自检。
- `npm run gen:ts` —— 用 `json-schema-to-typescript` 的 `compileFromFile` 从
  `schema/message.schema.json` 出发（它 `$ref` 了 `methods/*`、`events/*`、`common/*` 全部
  schema），一次性 bundle + 生成本轮覆盖的全部具名类型，写入
  `app/generated/ts/d2.d.ts`（仓库根目录下 `generated/ts/`，与 D4 monorepo 骨架
  `generated/{swift,csharp,ts}` 对应）。
- `npm run typecheck:ts` —— 用 `tsc --noEmit --strict` 验证生成产物本身是合法、可编译的
  TypeScript（已实测：TypeScript 5.9.3，`--strict` 下零错误）。

**已验证跑通**：三步命令均已实际执行成功（见 `app/generated/ts/d2.d.ts`，417 行，含正确的
`ResponseMessage` 判别联合——`result`/`failure` 互斥分支均被保留，不是坍缩后的公共基类）。

生成的 TS **仅供开发期 fixture 工具 / TS oracle 使用**（D4 §1.4/§4.4：TS 参考实现可在开发阶段
交叉验证 fixture 期望值，但不打包、不运行在用户机器上），不进任何产品打包。

## 下一步（本轮未做，占位）

Swift 与 C# 生成器选型已在 D4 §3.3 第 2 条给出候选（未经本轮验证，`置信度：部分`——D4 原文
明确标注这是工程判断，非已核实事实，实现前应做小范围技术验证）：

| 语言 | 候选工具 | 状态 |
|---|---|---|
| Swift | `quicktype`（多语言生成器，支持 JSON Schema → Swift `Codable`）或 Sourcery 插件链 | 未实现，TODO |
| C# | `NJsonSchema`、`JsonSchema.Net.Generation`、或同样用 `quicktype` | 未实现，TODO |

落地时建议复用本轮验证过的心得：**先跑一个最小 schema（如本轮的 `EmptyPayload`/
`WireCapabilityDescriptorPayload`）过一遍目标工具，确认判别联合（`oneOf`/`const`）与精确空
对象（`additionalProperties:false`）两个关键约束在生成的 Swift/C# 类型里被正确表达**，再决定
是否需要为该工具单独准备一份规避写法（本轮为 `json-schema-to-typescript` 发现的
"oneOf 分支内嵌 allOf 坍缩" 缺陷就是一个具体先例，见 `../README.md`「已知的一处 codegen
工具缺陷」一节）——不同工具的 bug 面不同，不能假设同一份 schema 写法对所有生成器都友好。

产物落点（未来）：`app/generated/swift/`、`app/generated/csharp/`（当前为空/未创建，见仓库根
`app/README.md` 骨架规划）。
