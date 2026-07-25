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
npm run gen   # validate -> gen:ts -> typecheck:ts -> typecheck:ts-type-fidelity -> gen:swift ->
              # typecheck:swift -> verify:swift -> verify:type-fidelity-swift -> gen:csharp ->
              # typecheck:csharp -> verify:csharp -> verify:type-fidelity-csharp ->
              # typecheck:fixtures-runner -> run:fixtures
```

各步骤职责：

| 脚本 | 职责 |
|---|---|
| `npm run validate` | Ajv（draft 2020-12）加载全部 25 个 schema、编译顶层判别联合，确认 `$ref` 图无悬空引用；同时做 `fixtures/` 全部 fixture 的 JSON 语法自检 |
| `npm run gen:ts` | `json-schema-to-typescript` 从 `schema/message.schema.json` 生成 `app/generated/ts/d2.d.ts` |
| `npm run typecheck:ts` | `tsc --strict` 验证 `d2.d.ts` 本身合法可编译 |
| `npm run typecheck:ts-type-fidelity` | `tsc --strict` 编译 `verify/ts/type-fidelity.ts`（SG-3 type-level 保真断言，见下「type-level 保真断言」一节） |
| `npm run gen:swift` | `quicktype-core` 生成叶子 DTO（`app/generated/swift/D2.swift`）+ 拷贝手写判别联合包装层（`DiscriminatedUnions.swift`） |
| `npm run typecheck:swift` | `swiftc -typecheck` 验证两个 Swift 文件 + `verify/swift/type-fidelity.swift`（positive control）合法可编译 |
| `npm run verify:swift` | 编译 `verify/swift/main.swift` 并运行，跑最小判别测试三项 |
| `npm run verify:type-fidelity-swift` | 用 `swiftc -typecheck -D <FLAG>` 分别点燃 `type-fidelity.swift` 里两个负例，断言各自编译失败（见下「type-level 保真断言」一节） |
| `npm run gen:csharp` | `quicktype-core` 生成叶子 DTO（`app/generated/csharp/D2.cs`）+ 拷贝手写判别联合包装层（`DiscriminatedUnions.cs`） |
| `npm run typecheck:csharp` | `dotnet build` 编译 `verify/csharp/`（引用 `generated/csharp/` 真实产物，不拷贝） |
| `npm run verify:csharp` | `dotnet run` 跑最小判别测试三项；CI 下（`CI=true`）dotnet 缺失硬失败，本地软跳过 |
| `npm run verify:type-fidelity-csharp` | 用 `dotnet build -p:DefineConstants=<FLAG>` 分别点燃 `verify/csharp-type-fidelity/TypeFidelity.cs` 里两个负例，断言各自编译失败；CI 下 dotnet 缺失同样硬失败 |
| `npm run typecheck:fixtures-runner` | `tsc --strict` 验证 fixture DSL 类型 + runner 本身合法 |
| `npm run run:fixtures` | 跑 `fixtures/ts-runner/runner.ts`，驱动 `fixtures/` 下全部 fixture |

**已验证跑通（本轮实测，2026-07-23）**：以上全部步骤零错误通过。TS 975 行、Swift
`D2.swift` 4845 行 + `DiscriminatedUnions.swift`、C# `D2.cs` 3703 行 +
`DiscriminatedUnions.cs`，三端最小判别测试（result/failure 互斥、11 事件判别、三层错误不串号）
各自 11 项断言全 PASS。

## type-level 保真断言（SG-3 验收缺口，rounds/0007）

`EmptyPayload`（精确空对象）与 `WireCapabilityDescriptorPayload`（排除 `protocolVersion`）两处
经 JSON Schema `additionalProperties:false` 表达的精确性，此前在三端生成产物上零断言覆盖。本轮
在 `verify/{swift,csharp,ts}/type-fidelity.*` 补齐了**编译期构造/字面量级**的负例断言（真实
`swiftc`/`dotnet build`/`tsc` 负例必须失败，不是注释式自证），并用 teeth（临时手改
`app/generated/` 真实产物注入缺陷 → 断言必须转 FAIL → `git checkout` 还原 → 再确认 PASS）验证
过断言确实有牙齿，过程记录在 round 0007 handoff。

- `verify/swift/type-fidelity.swift`：`sg3PositiveControl()` 是对照组；两个负例包在同名
  `#if SG3_NEGATIVE_*` 编译条件后，默认不参与编译，由 `scripts/verify-type-fidelity-swift.mjs`
  用 `-D` 逐一点燃并断言必须编译失败。
- `verify/csharp-type-fidelity/TypeFidelity.cs`：同构，用 `#if SG3_NEGATIVE_*` + `dotnet build
  -p:DefineConstants=<FLAG>`，由 `scripts/verify-type-fidelity-csharp.mjs` 编排。
- `verify/ts/type-fidelity.ts`：用 `@ts-expect-error`（tsc 对"下一行其实没报错"的
  `@ts-expect-error` 本身会报 `TS2578 Unused directive`，是编译器强制检查，不是注释）。
  **只覆盖 WireCapabilityDescriptorPayload 一侧**——EmptyPayload 那一半是已知缺陷，见下。

**已知缺陷（SG-1 codegen scope，本轮未修，如实记录不 fudge）**：`app/generated/ts/d2.d.ts` 的
`export interface EmptyPayload {}` 是 TS 对裸空接口的特殊处理（等价于"任意非
null/undefined 值"，不是"零属性的精确形状"）——`const bad: EmptyPayload = { extra: 1 }` 在当前
生成产物上不会报错。对照：`Record<string, never>` 或任意"至少一个属性"的接口都会正常拒绝多余
属性，唯独裸空接口不会（`WireCapabilityDescriptorPayload` 有 12 个必填字段，不触发这个特例，
所以它的负例断言正常成立）。证据与手工跑法见
`verify/ts/type-fidelity-known-gap.ts`（**未接入** `npm run gen`/CI：接入的话要么要用被本轮明确
禁止的 `|| true` 之类软放水掩盖一个已知未修的缺陷，要么让 CI 永久卡红在一个本轮明确不修、已如实
上报 blocker 的问题上，两者都不对）。Swift/C# 的编译期构造断言本身是真实、成立的（nominal 类型
系统天然拒绝多余/排除字段），但另有一个不在本轮"type-level"断言范围内、额外探针发现的**运行期**
缺陷：两端生成的 `Codable`/`System.Text.Json` 默认反序列化对多余键/被排除键（如
wire 上真的携带 `protocolVersion`）一律静默丢弃，不拒绝——同一份 blocker，详见 round 0007
handoff。

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
    verify-csharp.mjs         # dotnet run 薄封装（同上；CI=true 时 dotnet 缺失改硬失败）
    verify-type-fidelity-swift.mjs   # SG-3 type-level 断言编排（Swift 侧，-D 逐一点燃负例）
    verify-type-fidelity-csharp.mjs  # SG-3 type-level 断言编排（C# 侧，DefineConstants 逐一点燃负例）
    lib/
      leaf-types.mjs          # Swift/C# 叶子类型注册表（唯一来源）
      file-schema-store.mjs   # quicktype JSONSchemaStore 的文件系统实现
    handwritten/
      discriminated-unions.swift  # 手写 Swift 判别联合包装层（唯一来源）
      DiscriminatedUnions.cs      # 手写 C# 判别联合包装层（唯一来源）
  verify/
    swift/
      main.swift               # Swift 最小判别测试可执行程序
      type-fidelity.swift      # SG-3 type-level 断言（positive control + 两个 #if 负例）
    csharp/
      verify-csharp.csproj    # 最小 .NET 7 项目，直接编译 app/generated/csharp/ 真实产物
      Program.cs              # C# 最小判别测试可执行程序
    csharp-type-fidelity/
      verify-csharp-type-fidelity.csproj  # 独立小项目，专做 SG-3 编译期负例验证（不需要运行）
      TypeFidelity.cs                     # positive control + 两个 #if 负例
    ts/
      type-fidelity.ts             # SG-3 type-level 断言（CI 门禁，见上「type-level 保真断言」）
      type-fidelity-known-gap.ts   # 未接入 CI 的已知缺陷证据（EmptyPayload TS 侧不精确）
```

## 下一步（本轮未做，占位）

- 8 个方法里只有 createSession 的 result/failure 判别联合被手写包装（最小判别测试的代表性
  子集）；其余 7 个方法若要投入实际使用，需要按同一模式（`D2Response<Success,Failure>` 复用，
  只需新增对应 Failure 判别类型）补齐，是机械重复劳动，非本轮范围。
- Swift/C# runner（`parity/swift-runner/`、`parity/csharp-runner/`，D4 §4.4）未做，TODO，
  见 `../fixtures/README.md`。
- 未对比 quicktype 之外的 Swift/C# 候选生成器（Sourcery、NJsonSchema 等），见
  `../CODEGEN-FINDINGS.md`「D4 reopen 候选」第 3 条。
