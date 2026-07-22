# D2 codegen 管线

对应 D4 跨平台架构 v2.2 §3.5/§3.6：从 `contracts/d2/schema/` 的 JSON Schema 生成 Swift + C# +
TS 三种语言的**数据类型**（不含协议骨架/client stub——那部分按 D4 §3.6 v2 裁决是手写的，
authority 是 D1 散文，见 `~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`
§3.6「为何不生成机器可读 operation IDL」）。

**SG-1 深化轮（本轮）**：三端全部打通（PRE-② 只打通 TS）。**最重要的结论**：TS 判别联合零后处理
存活；Swift/C# 用 quicktype 直接生成会坍缩，需手写判别联合包装层才能存活——完整复现过程、
最小判别测试结果、D4 可行性 reopen 候选，见 `../CODEGEN-FINDINGS.md`（务必先读该文档）。

## 一键跑通

```bash
cd app/contracts/d2/codegen
npm install
npm run gen   # validate -> gen:ts -> typecheck:ts -> gen:swift -> typecheck:swift ->
              # verify:swift -> gen:csharp -> typecheck:csharp -> verify:csharp ->
              # typecheck:fixtures-runner -> run:fixtures
```

各步骤职责：

| 脚本 | 职责 |
|---|---|
| `npm run validate` | Ajv（draft 2020-12）加载全部 25 个 schema、编译顶层判别联合，确认 `$ref` 图无悬空引用；同时做 `fixtures/` 全部 fixture 的 JSON 语法自检 |
| `npm run gen:ts` | `json-schema-to-typescript` 从 `schema/message.schema.json` 生成 `app/generated/ts/d2.d.ts` |
| `npm run typecheck:ts` | `tsc --strict` 验证 `d2.d.ts` 本身合法可编译 |
| `npm run gen:swift` | `quicktype-core` 生成叶子 DTO（`app/generated/swift/D2.swift`）+ 拷贝手写判别联合包装层（`DiscriminatedUnions.swift`） |
| `npm run typecheck:swift` | `swiftc -typecheck` 验证两个 Swift 文件合法可编译 |
| `npm run verify:swift` | 编译 `verify/swift/main.swift` 并运行，跑最小判别测试三项 |
| `npm run gen:csharp` | `quicktype-core` 生成叶子 DTO（`app/generated/csharp/D2.cs`）+ 拷贝手写判别联合包装层（`DiscriminatedUnions.cs`） |
| `npm run typecheck:csharp` | `dotnet build` 编译 `verify/csharp/`（引用 `generated/csharp/` 真实产物，不拷贝） |
| `npm run verify:csharp` | `dotnet run` 跑最小判别测试三项 |
| `npm run typecheck:fixtures-runner` | `tsc --strict` 验证 fixture DSL 类型 + runner 本身合法 |
| `npm run run:fixtures` | 跑 `fixtures/ts-runner/runner.ts`，驱动 `fixtures/` 下全部 fixture |

**已验证跑通（本轮实测，2026-07-23）**：以上全部步骤零错误通过。TS 975 行、Swift
`D2.swift` 4845 行 + `DiscriminatedUnions.swift`、C# `D2.cs` 3703 行 +
`DiscriminatedUnions.cs`，三端最小判别测试（result/failure 互斥、11 事件判别、三层错误不串号）
各自 11 项断言全 PASS。

## Swift/C# 生成器选型（本轮定稿）

选型：`quicktype-core`（26.x）。D4 §3.3 第 2 条给出的候选里，Swift 一侧还有"Sourcery 插件链"、
C# 一侧还有 `NJsonSchema`/`JsonSchema.Net.Generation`——**本轮只验证了 quicktype**，未对比
其余候选，不应假设它们没有本文档记录的同类问题，也不应假设它们一定有同类问题（诚实标注为
未知，见 `../CODEGEN-FINDINGS.md`「D4 reopen 候选」第 3 条）。选 quicktype 的理由：同一个库
（`quicktype-core`）原生支持 Swift/C#/TS 三种目标语言，避免为 Swift/C# 分别引入两套不同的
生成器工具链与心智模型。

**架构（叶子 DTO 生成 + 判别联合手写包装，理由见 `CODEGEN-FINDINGS.md` 发现②）**：

- `scripts/lib/leaf-types.mjs` 是"哪些具名类型交给 quicktype 生成"的唯一清单（30 个
  top-level，均为非顶层-oneOf 的具体请求/事件消息 + 叶子 result/failure payload）。
- `scripts/lib/file-schema-store.mjs` 是供 quicktype-core `JSONSchemaInput` 使用的文件系统
  `JSONSchemaStore` 实现，负责把 schema 内部的相对 `$ref` 解析到 `schema/` 目录下的真实文件。
- `scripts/handwritten/discriminated-unions.swift` / `DiscriminatedUnions.cs`
  是手写的判别联合包装层（`D2Response<Success,Failure>`/`EventMessageUnion`/`KernelFailure`，
  覆盖任务要求的最小判别测试三项，非全部 8 个方法），由 `generate-swift.mjs`/
  `generate-csharp.mjs` 原样拷贝进 `app/generated/{swift,csharp}/`，**不是** quicktype 产物。

## TS（PRE-② 打通，本轮扩到全量覆盖）

`npm run gen:ts` 用 `json-schema-to-typescript` 的 `compileFromFile`，从
`schema/message.schema.json` 出发（它 `$ref` 了全部 25 个 schema 文件）一次性 bundle + 生成
全量类型，写入 `app/generated/ts/d2.d.ts`。生成的 TS **仅供开发期 fixture 工具 / TS oracle
使用**（D4 §1.4/§4.4：TS 参考实现可在开发阶段交叉验证 fixture 期望值，但不打包、不运行在
用户机器上），不进任何产品打包。

## 目录结构

```
codegen/
  package.json               # 全部 npm script 入口
  scripts/
    generate-ts.mjs           # schema -> TS
    generate-swift.mjs        # schema -> Swift 叶子 DTO + 拷贝手写判别联合包装层
    generate-csharp.mjs       # schema -> C# 叶子 DTO + 拷贝手写判别联合包装层
    validate-schemas.mjs      # Ajv 结构校验 + fixture JSON 语法自检
    typecheck-csharp.mjs      # dotnet build 薄封装（dotnet 不可用时如实报告"待验"）
    verify-csharp.mjs         # dotnet run 薄封装（同上）
    lib/
      leaf-types.mjs          # Swift/C# 叶子类型注册表（唯一来源）
      file-schema-store.mjs   # quicktype JSONSchemaStore 的文件系统实现
    handwritten/
      discriminated-unions.swift  # 手写 Swift 判别联合包装层（唯一来源）
      DiscriminatedUnions.cs      # 手写 C# 判别联合包装层（唯一来源）
  verify/
    swift/main.swift          # Swift 最小判别测试可执行程序
    csharp/
      verify-csharp.csproj    # 最小 .NET 7 项目，直接编译 app/generated/csharp/ 真实产物
      Program.cs              # C# 最小判别测试可执行程序
```

## 下一步（本轮未做，占位）

- 8 个方法里只有 createSession 的 result/failure 判别联合被手写包装（最小判别测试的代表性
  子集）；其余 7 个方法若要投入实际使用，需要按同一模式（`D2Response<Success,Failure>` 复用，
  只需新增对应 Failure 判别类型）补齐，是机械重复劳动，非本轮范围。
- Swift/C# runner（`parity/swift-runner/`、`parity/csharp-runner/`，D4 §4.4）未做，TODO，
  见 `../fixtures/README.md`。
- 未对比 quicktype 之外的 Swift/C# 候选生成器（Sourcery、NJsonSchema 等），见
  `../CODEGEN-FINDINGS.md`「D4 reopen 候选」第 3 条。
