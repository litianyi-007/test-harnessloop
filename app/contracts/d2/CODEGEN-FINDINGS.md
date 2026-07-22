# D2 Codegen 三端（TS/Swift/C#）判别联合存活验证——诚实结论（SG-1 深化）

对应 D4 跨平台架构 v2.2 §3.5/§3.6（`~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md`，
`design_status: confirmed`）「codegen 覆盖面」「顶层判别联合」一行的可行性核验。本文档是本轮
（SG-1 深化）最重要的产出：如实记录三端 codegen 对 D2 v3 封闭判别联合的存活结论，不掩盖坍缩。

## 一句话结论

**TS 判别联合完整存活，零后处理。Swift/C# 用 quicktype 直接生成会发生两种独立坍缩（`allOf`
静默丢字段 + `oneOf` 结构合并丢判别），前者可通过改写 schema 规避（已改、已验证），后者
**无法通过改写 schema 规避**——必须手写判别联合包装层。三端最终都能让判别联合在类型系统里正确
存活，但 Swift/C# 需要真实的人工后处理成本，不是"改个生成器参数"就能解决的问题。这是
D4"共享 codegen"决策的一处必须正视的可行性缺口，详见文末「D4 reopen 候选」。**

## 工具链可用性

| 工具 | 可用性 | 版本 |
|---|---|---|
| node/npm | 可用 | node v22.22.3 / npm 10.9.8 |
| `json-schema-to-typescript` | 可用（PRE-② 已选型） | 15.0.4 |
| `quicktype-core`（Swift/C# 选型） | 可用，本轮新增安装 | 26.0.0 |
| `swiftc` | 可用 | swift-driver 1.148.6 / Apple Swift 6.3.3 |
| `dotnet` | 可用 | 7.0.401 |
| `csc`（Mono，未使用） | 可用但未采用——本轮用 `dotnet build`/`dotnet run` 走 SDK 风格项目，更贴近真实 C# 工程实践 | — |

三端工具链本轮**全部可用**，compile-verify 均为真实编译通过（非"待验"占位）。

## 方法论

1. 从同一份 `schema/message.schema.json`（$ref 递归覆盖 `methods/*`、`events/*`、`common/*`
   全部 25 个 schema 文件）生成 TS；Swift/C# 改为把 `scripts/lib/leaf-types.mjs` 枚举的 30 个
   "非顶层 oneOf" 具名类型逐个作为独立 top-level 喂给 `quicktype-core`（理由见下方「坍缩②」）。
2. 对每种语言做 compile-verify：TS 用 `tsc --strict`；Swift 用 `swiftc -typecheck`；C# 用
   `dotnet build`（SDK 项目 `verify/csharp/`，直接编译 `app/generated/csharp/` 的真实产物，不拷贝）。
3. 做「最小判别测试」：每语言构造 result 分支样例 + failure 分支样例 + 11 事件样例 + 三层错误
   样例，运行时断言解码结果落入正确 case、混用/畸形输入被拒绝。测试代码见
   `codegen/verify/{swift,csharp}/` 与 `codegen/scripts/handwritten/`（后者是 Swift/C# 手写的判别
   联合包装类型本身，前者是驱动它们跑断言的可执行程序）。

## 发现①：`allOf` 静默丢字段（quicktype，Swift 与 C# 共有，比坍缩②更隐蔽）

**复现**：JSON Schema `allOf: [{ $ref: "...#/$defs/Base" }]` + 自身 `properties`（D2 v3 §2 的
`RequestEnvelope`/`EventEnvelope` 模板套用方式）喂给 `quicktype-core` 的 `JSONSchemaInput`，
生成的 Swift/C# 类型**完全不包含 `allOf` 引用的 `Base` 字段**——不报错、不合并、不产生警告，
`allOf` 数组的每一个成员（无论 `$ref` 还是内联 schema）都被直接忽略，只保留该 schema 自身
`properties` 声明的字段。最小复现（保留在本文档旁证，非受版本控制的产物）：

```json
{ "allOf": [{ "type": "object", "properties": { "a": {"type":"string"} }, "required": ["a"] }],
  "type": "object", "properties": { "c": {"type":"string"} }, "required": ["c"] }
```
→ 生成的 Swift/C# 类型只有字段 `c`，字段 `a` 完全消失。

**影响面**：本轮 SG-1 之前，8 个方法的 request 消息、11 个事件消息、`res.unknown` 全部用
`allOf` 复用 `common/envelope.schema.json` 的 `requestEnvelopeBase`/`eventEnvelopeBase`/
`responseEnvelopeBase` 片段——若不修复，quicktype 生成的 Swift/C# 类型会**完全丢失** `sentAt`/
`direction`（全部 request/event 消息）、`seq`/`sessionId`/`ts`（全部 event 消息）等 D2 wire
层核心传输元数据，且是**静默**丢失（编译通过、无警告），比"坍缩成公共基类"更危险——后者至少
字段还在（只是判别丢了），这个是字段本身凭空消失。

**是否可规避：可以，本轮已规避**。把全部 19 处（8 个方法 request + 11 个事件）`allOf` 改写为
直接内联对应字段（不再引用 `common/envelope.schema.json` 的 base fragment，改为在每个具体
`XxxRequestMessage`/`XxxEventMessage` schema 内联声明 `sentAt`/`direction`（request）或
`sentAt`/`direction`/`seq`/`sessionId`/`runId`/`ts`（event）），`unevaluatedProperties:false`
相应改回 `additionalProperties:false`。语义与 `allOf` 版本完全等价（Ajv 校验结果不变，见
`npm run validate` 通过），是纯粹的 codegen 工具缺陷规避写法，不改变 D2 v3 契约本身。TS 侧
`json-schema-to-typescript` 对 `allOf` 处理正确（PRE-②/本轮均验证过），本次改写不影响 TS 产物
正确性（`generated/ts/d2.d.ts` 改写前后均 `tsc --strict` 零错误，字段数从 780 行增到 975 行——
增量正是新纳入的 5 方法+6 事件+更完整字段展开，不是回归）。

**该发现本身要不要算"已绕过"**：算，但要诚实说明代价——这不是"生成器参数调整"就能解决的，
是**倒逼修改 schema authoring 方式**才能规避，且这条规避写法要求"以后任何新增方法/事件都必须
记得用内联而不是 `allOf`"——这是一条新的、需要长期维护纪律记住的隐性规则，不是一次性修复。

## 发现②：`oneOf` 判别联合结构合并（quicktype，Swift 与 C# 共有，**无法通过改写 schema 规避**）

**复现**（三个独立验证，规模从大到小）：

1. 全量 `ResponseMessage`（8 个方法 oneOf 的 union）喂给 quicktype → 生成**唯一一个** Swift
   `struct Message`/C# `class`，把全部 8+ 个方法变体的字段合并进同一个类型，`result`/`failure`
   两个属性同时存在、都是 optional，`type` 坍缩成一个包含全部方法字面量的单一枚举。
2. 单独把 `CreateSessionResponseMessage`（仅 2 分支：success/failure）喂给 quicktype → 依然
   合并成**一个** struct，`result: Result?` 与 `failure: Failure?` 同时作为可选字段并存——
   **没有任何机制阻止同时提供两者或都不提供**，D2 v3 §2"result/failure 互斥"的核心判别语义
   完全消失。这是最小复现，证明问题不是"太多分支太相似"，2 分支同样坍缩。
3. `EventMessage`（11 个事件类型的 oneOf）喂给 quicktype → 合并成一个 struct，`payload` 字段
   变成一个把 11 种事件 payload 结构揉在一起的单一（近乎 `Any`）类型，`type` 坍缩成包含全部
   11 个字面量的单一枚举——"payload 形状由 type 决定"这一核心判别关系完全消失。

**尝试的规避手段与结果**：
- `combineClasses: false`（quicktype-core 的 `InferenceFlags` 之一）——**无效**，坍缩发生在
  `oneOf` 解析阶段本身（`JSONSchemaInput` 内部的联合类型统一逻辑），不是 `combineClasses`
  控制的后续图重写阶段，加不加这个 flag 生成结果逐字节相同（已验证：diff 为空）。
- **把每个 `oneOf` 分支拆开、作为独立 top-level 分别喂给 quicktype**——**有效，但代价是绕开
  quicktype 对 oneOf 的处理本身，等于放弃让它生成判别联合**。验证：把结构高度相似的
  `RejectionFailure`/`ProtocolFailure`/`BillingQueryFailure`（均为 `{code,detail?}`）分别作为
  3 个独立 top-level（不经过任何 oneOf）喂给 quicktype，三者被正确保留为独立类型，未被合并——
  证明 quicktype 本身有能力保持结构相似的类型独立，问题的根源确实、只在于"它自己解析 oneOf
  时选择做结构合并"，而不是"结构太相似导致的必然误判"。
- **规避写法本身不能让 quicktype "生成"判别联合，只能让它生成判别联合的"零件"（各分支各自的
  叶子类型），判别联合的包装层必须手写**（下方「后处理方案」）。

**结论：这是 quicktype 对 Swift/C# 后端的一处结构性限制，不是本项目 schema 写法问题**，也
**不是**像发现①那样"改一下 schema authoring 方式就能规避"——因为问题根源在于 quicktype 对
`oneOf` 语义的实现方式本身（结构相容即合并），不是我们喂给它的 schema 形状选择。TS 的
`json-schema-to-typescript` 走的是完全不同的代码路径（直接把 `oneOf` 翻译成 TS 联合类型
`A | B | C`），天生没有这个问题（PRE-② 发现的 TS 缺陷是"`oneOf` 分支内嵌 `allOf`"这个更窄的
问题，且已用内联规避；TS 对"纯 `oneOf`，分支内联无 `allOf`"的判别联合处理是正确的，本轮
`ResponseMessage`/`EventMessage`/`Message` 全量生成并 `tsc --strict` 通过可证）。

## 后处理方案：手写判别联合包装层（Swift/C# 均已实现并验证）

既然 quicktype 无法"生成"判别联合本身，本轮采用的架构是：

1. **quicktype 只负责生成"叶子 DTO"**——8 个方法的 request 消息、11 个事件消息、`res.unknown`、
   以及只被 response oneOf 分支引用而需要显式列出的 result/failure payload（`RejectionFailure`/
   `ProtocolFailure`/`BillingQueryFailure`/`CapabilityDescriptorPayload` 等），共 30 个
   top-level，逐个独立喂给 quicktype（`codegen/scripts/lib/leaf-types.mjs` 是这份清单的唯一
   来源）。这些叶子类型本身**不含 oneOf**，quicktype 生成正确、字段完整（发现①修复后）。
2. **判别联合包装层手写**（`codegen/scripts/handwritten/discriminated-unions.swift` /
   `DiscriminatedUnions.cs`，由 `generate-swift.mjs`/`generate-csharp.mjs` 原样拷贝进
   `app/generated/{swift,csharp}/`，不是 quicktype 产物）：
   - **Swift**：`enum` 关联值天然是判别联合的正确表达——`D2Response<Success,Failure>`
     （泛型，`result`/`failure` 两个 case，自定义 `Codable` 显式检查"恰好一个键存在"）、
     `EventMessageUnion`（11 个 case，按 `type` 路由）、`KernelFailure`（3 个 case，靠三层
     `code` 枚举值集合互不相交实现级联 `try?` 判别）。
   - **C#**：C# **没有 Swift 的 enum 关联值**，只能用"抽象基类 + 具体子类 + 自定义
     `JsonConverter`"表达同一件事——`D2Response<TSuccess,TFailure>`（`JsonConverterFactory`
     支持任意泛型实参组合）、`EventMessageUnion`（抽象类 + 11 个 `XxxCase` 子类）、
     `KernelFailure`（抽象类 + 3 个子类）。**这本身是本轮的一项独立发现**：即便"判别联合能否
     生成"这个问题解决了，C# 语言本身对判别联合的表达力也弱于 Swift/TS，需要更多样板代码
     （抽象类层级 + 类型判别 `switch` + 手写 converter）才能达到 Swift "编译期穷尽性"同等的
     保证——C# 版本的互斥保证主要靠**运行时**的 `IsResult`/`IsRejection` 标志与 `Read()` 里的
     显式校验，不是编译器强制的模式匹配穷尽性。

## 最小判别测试结果（逐语言）

三项测试见 `codegen/verify/swift/main.swift`（`swiftc` 编译+运行）、
`codegen/verify/csharp/Program.cs`（`dotnet build && dotnet run`），均**全部通过**：

| # | 测试项 | TS | Swift | C# |
|---|---|---|---|---|
| ① | result/failure 互斥（同时提供两者/都不提供 → 拒绝） | 存活，零后处理（`tsc --strict` 判别联合原生正确） | 存活，需手写 `D2Response<S,F>` + 自定义 `Codable`（quicktype 默认输出坍缩，见发现②） | 存活，需手写 `D2Response<TS,TF>` + `JsonConverterFactory`（quicktype 默认输出坍缩） |
| ② | 11 事件按 `type` 判别 | 存活，零后处理 | 存活，需手写 `EventMessageUnion`（11 case + `type` 路由，quicktype 默认输出坍缩成 1 个合并 struct） | 存活，需手写 `EventMessageUnion`（抽象类 + 11 子类 + converter，quicktype 默认输出坍缩） |
| ③ | 三层错误不串号 | 存活，零后处理（`RejectionFailure \| ProtocolFailure \| BillingQueryFailure` 直接是合法 TS 联合） | 存活，需手写 `KernelFailure`（3 case 级联 `try?`，quicktype 默认把三者的 `code` 合并成一个 12 值大枚举，见下方「附带发现」） | 存活，需手写 `KernelFailure`（3 子类级联 try-catch，quicktype 同样合并） |

**如实记录一处 C# 特有小插曲**：quicktype 为字符串枚举生成的自定义 `JsonConverter`
（如 `RejectionFailureCodeConverter`）在遇到不认识的取值时抛的是裸 `System.Exception`，不是
`System.Text.Json` 惯用的 `JsonException`——手写的级联 `try/catch` 若按更符合直觉的
`catch (JsonException)` 写会完全捕获不到，级联判别逻辑形同虚设（已实测复现：程序在第三项
测试直接抛出未捕获异常崩溃），必须改用 `catch (Exception)` 兜底。这是 quicktype C# 后端一处
不遵循 `System.Text.Json` 惯例的 API 不一致，非本项目 schema 问题，但如实记录为"用 quicktype
生成 C#"这条路径上的一个真实踩坑点。

## 附带发现：quicktype 把语义不同、结构相同的类型合并成一个大类型/大枚举

未拆分为独立 top-level 之前，`RejectionFailure`（8 个 code 值）、`ProtocolFailure`（3 个 code
值）、`BillingQueryFailure`（1 个 code 值）若同时出现在同一份被 quicktype 解析的 oneOf/联合
上下文里，会被合并成一个共享同一个 12 值大 `FailureCode` 枚举的单一类型——D1/D2 两轮评审
专门强调的"三层严格不混淆的失败通道"（D1 v3.5 §9.1）在这种路径下会被 quicktype 悄悄拉平。
本轮采用「发现②」的规避手段（三者作为独立 top-level 分别喂给 quicktype）后验证三者保持独立
（各自的 `RejectionFailureCode`/`FailureCode`/`BillingQueryFailureCode` 三个不同枚举），
但这再次印证：**只要某处仍让 quicktype 自己解析一个把它们放在一起的 oneOf/联合，合并就会
重新发生**——独立 top-level 是本轮为规避坍缩而人工设计的喂入方式，不是 quicktype 的默认/
推荐用法，任何后续改动如果不小心把三层错误类型重新放回一个 oneOf 里喂给 quicktype，坍缩
会无声回归。

## D4 reopen 候选（可行性风险，明确标注，不掩盖）

D4 §3.5「codegen 覆盖面」表格把「顶层判别联合」（`RequestMessage`/`ResponseMessage`/
`EventMessage`/`Message` + 8 个方法各自的 `*ResponseMessage`）列为**与其余类别同等地位的
"生成"产物**（数量"4"，与"11 类事件""7+1 方法""3 个共享失败类型"并列于同一张表，未做区分
标注）。本轮验证证明：**这条假设对 TS 成立，对 Swift/C#（至少对 quicktype 这一具体工具选型）
不成立**——Swift/C# 的判别联合包装层是本轮工程师手写的产物，不是 codegen 管线的自动产出物。

**具体影响**：
1. **codegen 管线本身不是"改一下 schema 就能重新生成一切"的单一真相线**——判别联合包装层
   （`discriminated-unions.swift`/`DiscriminatedUnions.cs`）与 quicktype 生成的叶子 DTO
   是**两条独立维护的产物**，schema 每新增/修改一个方法或事件，除了重跑 `npm run gen:swift`/
   `gen:csharp`，还需要**手工同步修改**判别联合包装层（新增一个 `case`、新增一个 `switch`
   分支）——这条同步纪律目前只靠人工记住，没有任何自动化检查会在"schema 加了一个新事件类型
   但判别联合包装层忘了加对应 case"时报错（本轮只覆盖了 3 处代表性判别联合的最小子集，**尚未
   覆盖全部 8 个方法的 result/failure 判别**，若真要投入生产，另外 7 个方法都需要重复这个手写
   套路，是持续的工程成本，不是一次性投入）。
2. **三端"编译期防漂移"的强度并不对等**——TS 的判别联合是语言原生特性，Swift 用 `enum`
   关联值接近但仍需要手写 `Codable`，C# 连语言层面的判别联合都没有，只能靠约定
   （抽象类+运行时标志）逼近，实际防漂移强度 TS > Swift > C#。D4 决策"各端原生 client + 共享
   D2 schema codegen"隐含假设三端能拿到"同等质量"的生成类型，本轮证明这一假设**对判别联合
   这一子类别不成立**，是 D4 架构文本需要更新以如实反映的一处缺口。
3. **工具选型本身可能需要重新评估**——本轮验证的是 `quicktype`（D4 §3.3 第 2 条给出的候选
   之一）；D4 同一条也列出了 C# 的 `NJsonSchema`/`JsonSchema.Net.Generation`、Swift 的
   "Sourcery 插件链"作为备选，这些工具**本轮未验证**，有可能对 `oneOf` 判别联合的支持更好
   （或同样有限）——不应假设"换个工具就没有这个问题"，但也不应假设"quicktype 的限制就是
   全部候选工具共同的限制"，这是一个诚实的未知，建议标注为后续轮次的技术验证候选项。

**建议处置**：不建议因此推翻 D4"各端原生 client + 共享 D2 schema codegen"的整体方向（本轮
证明"叶子 DTO 类型"这一大类在三端都能正确共享，这是 D4 决策的主体价值所在，仍然成立）；
但 D4 §3.5/§3.6 关于"顶层判别联合"是否属于可无脑"生成"的产物这一具体断言，应该 reopen 修订为
"Swift/C# 的判别联合包装层是半自动产物——叶子类型生成、包装层手写，需要一次性工程投入 + 每次
schema 演进的同步维护纪律"，而不是与其余类别一视同仁地归入"生成"一栏。

## 文件清单（本轮产出，供复核）

- `schema/`：8 个方法 + 11 个事件 + `res.unknown` 全量 JSON Schema（25 个文件）。
- `codegen/scripts/lib/leaf-types.mjs`：Swift/C# 叶子类型注册表（30 个 top-level）。
- `codegen/scripts/generate-swift.mjs` / `generate-csharp.mjs`：codegen 脚本。
- `codegen/scripts/handwritten/discriminated-unions.swift` / `DiscriminatedUnions.cs`：手写判别
  联合包装层（唯一来源，`generate-*.mjs` 原样拷贝进 `generated/`，不是 quicktype 产物）。
- `codegen/verify/swift/main.swift`、`codegen/verify/csharp/`（`Program.cs` +
  `verify-csharp.csproj`）：最小判别测试可执行程序。
- `generated/ts/d2.d.ts`（975 行）、`generated/swift/{D2.swift,DiscriminatedUnions.swift}`
  （4845 行）、`generated/csharp/{D2.cs,DiscriminatedUnions.cs}`（3703 行）：三端生成产物。
- `fixtures/dsl.ts`、`fixtures/ts-runner/{runner.ts,mock-kernel-client.ts}`：fixture DSL 正式化
  + 最小 TS runner（见该目录说明，Swift/C# runner 未做，标 TODO）。
