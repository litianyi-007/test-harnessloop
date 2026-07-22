# D2 机器可读 Schema（PRE-②骨架 + SG-1 深化：全量覆盖 + codegen 三端打通）

对应 D4 跨平台架构 v2.2 §3「D2 codegen 管线（D4→D2 的核心依赖）」的**第 0 步、阻断性前置任务**：
D2 v3（`~/.llm-wiki/agent-app-design/kernel/d2-message-schema-v3.md`，`design_status: confirmed`）
目前只有 TS-in-markdown 表达，没有任何机器可读产物——本目录是补齐这条依赖的起点。

**SG-1 深化轮（本轮）**：在 PRE-② 骨架（3/8 方法 + 5/11 事件）基础上补齐剩余 5 方法 + 6 事件，
达到 D2 v3 §3.9/§4.1 的全量覆盖；打通 TS + Swift + C# 三端 codegen；验证封闭判别联合在三端能否
存活（**结论：TS 零后处理存活，Swift/C# 需手写判别联合包装层才能存活，quicktype 直接生成会
坍缩**）；补齐 fixture DSL 正式化 + 最小 TS runner。**最重要的产出是
`CODEGEN-FINDINGS.md`**——三端 codegen 对判别联合的存活结论、坍缩复现过程、D4 可行性 reopen
候选，务必先读。

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
    methods/                 # 全部 8 个方法 req/resp + res.unknown（见下方覆盖表）
      create-session.schema.json / send.schema.json / subscribe.schema.json /
      interrupt.schema.json / stop.schema.json / respond-approval.schema.json /
      capabilities.schema.json / query-billing.schema.json / unknown-response.schema.json
    events/                  # 全部 11 类 KernelEvent（见下方覆盖表）
      message-delta / thinking / tool-call / tool-result / approval-request / error /
      turn-complete / session-end / capability-changed / operation-completed /
      approval-buffer-resolved（各自 .schema.json）
    message.schema.json      # 顶层判别联合 Message = RequestMessage | ResponseMessage | EventMessage（全量覆盖）
  codegen/                   # schema -> TS/Swift/C# 的生成管线（见 codegen/README.md）
  fixtures/                  # 金标 parity fixture 骨架 + DSL 正式化 + 最小 TS runner（见 fixtures/README.md）
  CODEGEN-FINDINGS.md        # 【本轮最重要产出】三端判别联合存活结论 + D4 reopen 候选
```

## 覆盖范围（PRE-②骨架 + SG-1 深化：现已全量覆盖）

| 类别 | 覆盖 |
|---|---|
| 方法 req/resp（7+1） | createSession（§3.1）、send（§3.2）、subscribe（§3.3）、interrupt（§3.4）、stop（§3.5）、respondApproval（§3.6）、capabilities（§3.7）、queryBilling（§3.8）、`res.unknown`/`UnknownResponseMessage`（§3.9）—— **8/8 + res.unknown，全量** |
| KernelEvent（11 类） | message.delta/thinking/tool_call/tool_result/approval_request/error/turn_complete/session_end/capability_changed/operation_completed/approval_buffer_resolved（§4 #1-#11）—— **11/11，全量** |
| 封套模板 | `MessageEnvelopeBase`/`RequestEnvelope`/`ResponseEnvelope`/`EventEnvelope`（§2，`common/envelope.schema.json`）——**注**：具体消息类型改为直接内联封套字段而非 `allOf` 引用（规避 quicktype 缺陷，见 `CODEGEN-FINDINGS.md` 发现①），`common/envelope.schema.json` 的 `$defs` 片段本身保留供 `res.unknown`/文档引用 |
| 精确空对象/排除字段类型 | `EmptyPayload`（§3 Changelog 修复 2）、`WireCapabilityDescriptorPayload`（§4 v3-r1/r2） |
| 三层错误 + 第四层 | `KernelErrorCode`/`KernelPortRejectionCode`/`OperationOutcome`（D1 v3.5 §9.1）、`ProtocolFailure`（D2 v3 §7.4）、`BillingQueryFailure`（§3.8） |
| 能力协商 | `CapabilityDescriptorPayload`（§7，全字段） | 完整 |
| 顶层判别联合 | `Message`/`RequestMessage`/`ResponseMessage`/`EventMessage`（`message.schema.json`）—— **全量：8 方法 req + 8 方法 res + res.unknown + 11 事件** |

`stop()` 的 `outcome` 字段类型层面收窄为三态（`succeeded`/`timed_out`/`rejected`），不复用共享
的七态 `OperationOutcome`——忠实转录 D2 v2 §3.5 的更正结论，非本轮新裁决。

## 已知的 codegen 工具缺陷与规避写法

**这一节已被 SG-1 深化轮扩写，完整版本见 `CODEGEN-FINDINGS.md`（本轮最重要产出，务必先读）。**
本节只留一句索引，不重复展开：

- `json-schema-to-typescript`（TS 生成器）对「`oneOf` 分支内嵌 `allOf`」有坍缩缺陷（PRE-② 发现）
  ——已用「分支内直接内联 envelope 字段」规避，TS 侧判别联合本轮验证**全量正确、零坍缩**。
- `quicktype`（Swift/C# 生成器，SG-1 深化新增）有**两处**独立缺陷：①对纯 `allOf`（不涉及
  `oneOf`）会静默丢弃引用字段——已用同一条「直接内联」规避写法解决；②对 `oneOf` 判别联合本身
  做结构合并、**无法通过改写 schema 规避**——8 个方法的 `*ResponseMessage`、11 事件的
  `EventMessage`、三层错误联合，quicktype 直接生成全部坍缩，必须手写判别联合包装层
  （`codegen/scripts/handwritten/`）。这是本轮对 D4"共享 codegen"决策的一处可行性 reopen
  候选，详见 `CODEGEN-FINDINGS.md`「D4 reopen 候选」一节。
