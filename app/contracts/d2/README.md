# D2 机器可读 Schema（PRE-②/SG-1 骨架）

对应 D4 跨平台架构 v2.2 §3「D2 codegen 管线（D4→D2 的核心依赖）」的**第 0 步、阻断性前置任务**：
D2 v3（`~/.llm-wiki/agent-app-design/kernel/d2-message-schema-v3.md`，`design_status: confirmed`）
目前只有 TS-in-markdown 表达，没有任何机器可读产物——本目录是补齐这条依赖的起点。

**忠实纪律**：本目录只把 D2 v3 已经钉死的 wire 类型转录为 JSON Schema，不改语义、不裁决 D1/D2
任何未决问题（D2 v3 §9.2 回指 D1 的待澄清点、D1 C-item 等，均原样保留为"未决"，不在 schema 层
面强行补全）。D2 md 本身仍是权威叙述（协议版本协商流程、反序列化重建规则、`res.unknown` 分流
条件等只能用散文表达的不变量，继续留在 D2 md 里——machine schema 只负责"消息长什么样"）。

## 目录结构

```
d2/
  schema/
    common/                  # 可复用片段：envelope 模板、三层错误模型、CapabilityDescriptor
      envelope.schema.json
      errors.schema.json
      empty-payload.schema.json
      capability-descriptor.schema.json
    methods/                 # 代表性方法 req/resp（本轮 3/8，见下方覆盖表）
      create-session.schema.json
      interrupt.schema.json
      respond-approval.schema.json
    events/                  # 代表性 KernelEvent（本轮 5/11，见下方覆盖表）
      message-delta.schema.json
      tool-call.schema.json
      approval-request.schema.json
      capability-changed.schema.json
      operation-completed.schema.json
    message.schema.json      # 顶层判别联合 Message = RequestMessage | ResponseMessage | EventMessage（部分覆盖）
  codegen/                   # schema -> Swift/C#/TS 的生成管线（见 codegen/README.md）
  fixtures/                  # 金标 parity fixture 骨架（见 fixtures/README.md）
```

## 覆盖范围（本轮 PRE-②/SG-1）

| 类别 | 覆盖 | 未覆盖（TODO，D2 v3 章节引用） |
|---|---|---|
| 方法 req/resp | createSession（§3.1）、interrupt（§3.4）、respondApproval（§3.6） | send（§3.2）、subscribe（§3.3）、stop（§3.5）、capabilities（§3.7）、queryBilling（§3.8）、`res.unknown`/`UnknownResponseMessage`（§3.9） |
| KernelEvent（11 类） | evt.message.delta（§4 #1）、evt.tool_call（§4 #3）、evt.approval_request（§4 #5）、evt.capability_changed（§4 #9）、evt.operation_completed（§4 #10） | evt.thinking（#2）、evt.tool_result（#4）、evt.error（#6）、evt.turn_complete（#7）、evt.session_end（#8）、evt.approval_buffer_resolved（#11） |
| 封套模板 | `MessageEnvelopeBase`/`RequestEnvelope`/`ResponseEnvelope`/`EventEnvelope`（§2，`common/envelope.schema.json`） | 完整 |
| 精确空对象/排除字段类型 | `EmptyPayload`（§3 Changelog 修复 2）、`WireCapabilityDescriptorPayload`（§4 v3-r1/r2） | 完整 |
| 三层错误 + 第四层 | `KernelErrorCode`/`KernelPortRejectionCode`/`OperationOutcome`（D1 v3.5 §9.1）、`ProtocolFailure`（D2 v3 §7.4）、`BillingQueryFailure`（§3.8） | 完整 |
| 能力协商 | `CapabilityDescriptorPayload`（§7，全字段） | 完整 |
| 顶层判别联合 | `Message`/`RequestMessage`/`ResponseMessage`/`EventMessage`（骨架，部分成员，见 `message.schema.json` 顶层 `$comment`） | 剩余 5 方法 + 6 事件类型补齐后并入 |

未覆盖处均在 schema 文件内用 `$comment` 显式标 TODO + 引用 D2 v3/D1 v3.5 具体章节，不臆造字段
（呼应 D4 §3.5「完整类型闭包要求」：下一轮补齐时必须做递归闭包核对，不能只抄类别名）。

## 已知的一处 codegen 工具缺陷与规避写法

`json-schema-to-typescript`（本轮 schema→TS 样板用的生成器，见 `codegen/README.md`）对
**「`oneOf` 分支内部再用 `allOf` 组合基类字段」**存在已验证的缺陷：会把分支特有字段丢失、
坍缩成公共基类本身（例如 `ResponseMessage` 会被错误生成为 `ResponseEnvelopeBase`，丢失全部
`result`/`failure` 判别）。复现与验证过程见 git history；本目录的三个方法 response schema
（`methods/*.schema.json` 的 `*ResponseMessage`）改为在每个 `oneOf` 分支内直接内联
`sentAt`/`direction` 字段（不用 `allOf` 引用 `common/envelope.schema.json`），语义与
`allOf` 版本完全等价（Ajv 校验结果不变），只是规避这个工具缺陷的写法选择。Swift/C# 生成器
选型时需要重新验证是否存在同类问题，不能假设这条规避对其它工具也成立。
