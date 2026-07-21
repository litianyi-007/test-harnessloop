---
task_id: T-016
adapter: grok
model: grok-4.5
status: done
task_type: code-review-adversarial
review_target: /Users/litianyi/.llm-wiki/agent-app-design/kernel/d2-message-schema-v2.md
semantic_baseline: /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-4.md
first_round_refs: null
verdict: PASS_WITH_NOTE
phase: done
last_progress_at: "2026-07-21T17:13:17.707Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-21T17:13:17.706Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 197085
adapter_status: success
---

# T-016 — D2 消息 schema v2 第二次双轨复核（grok 轨，对抗 / 只读）

## Summary

对 D2 v2（`d2-message-schema-v2.md`，441 行，`design_status: draft`）做限定范围对抗复核：只验第一轮双轨 finding 是否闭合，以及 v2 新编辑是否自洽；不重开无关范围、不提 nice-to-have。结论：第一轮共识 BLOCKER（`protocolVersion`/`ts` 字段冲突）与 codex 独挖项（版本字面量、判别联合封闭、F-13/F-15/S-11 回指、Stop 三态、sessionId/capabilities 例外）均已实质闭合；D1 侧三处澄清注释确为“不改语义”，`design_status` 仍为 `confirmed`。v2 新编辑整体自洽，但引入一处中等机械缺口（§7.2 握手字段 `supportedProtocolVersions` 未写入 §3.7 类型）与一处低严重度措辞残留（§7.4 仍像“每条 request 都带 wire protocolVersion”）。故 verdict 为 **PASS_WITH_NOTE**（非 REWORK：主路径已可唯一实现，残留属局部补丁级）。

## Files touched

none（只读评审；本产出仅写入 `.hopper/handoffs/T-016-output.md`）

## Acceptance verification (2/2 审查重点均完成)

| # | 审查重点 | 结果 | 证据摘要 |
|---|---|---|---|
| 1 | 第一轮双轨 finding 是否真闭合 | **通过（全部闭合）** | 见下表「第一轮 finding 逐项闭合」；行号锚点均指向 D2 v2 + D1 v3.4 |
| 2 | v2 新编辑有无引入新矛盾 | **基本通过（1 中 + 1 低 note）** | 分名 / 封闭联合 / 单一契约版本握手主路径自洽；N-V2-01、N-V2-02 见「v2 新编辑核验」 |

### 机器核对摘录

```
D2 v2: 441 行；D1 v3.4: 793 行
D1 design_status: confirmed（frontmatter L17；顶部澄清 L24 明示维持 confirmed）
D2 v2 design_status: draft（L21）
sentAt（封套）: D2 v2 L90
EventEnvelope.ts（业务）: D2 v2 L139-141
protocolVersion 单一契约 "kernelport/1": D2 v2 L380；D1 澄清 L24/L291/L340-342
ResponseEnvelope result/failure 互斥（?: never）: D2 v2 L113-130
RequestMessage 封闭 8 方法 + ResponseMessage 含 res.unknown: D2 v2 L245-289
EventMessage 封闭 11 类: D2 v2 L319-334
StopResultPayload 三态: D2 v2 L205-211
sessionId 例外 createSession/capabilities: D2 v2 L100-105, L248-255
§9.2 F-13/F-15/S-11: D2 v2 L434-436
supportedProtocolVersions 出现于 §7.2 L392，但 CapabilitiesRequestPayload {} 仍在 L222
```

---

## 1. 第一轮 finding 逐项闭合结论

### 1.1 共识 BLOCKER：protocolVersion + 业务 ts 字段名冲突 — **闭合**

| 子项 | 第一轮问题 | v2 修复 | 闭合判定 |
|---|---|---|---|
| 业务 `ts` | v1 声称双时间戳但 schema 只有一个 `ts`；payload 又禁重复（grok F-02 / codex BLOCKER 半部） | envelope 改 `sentAt`（D2 v2 L86-90）；`EventEnvelope.ts` 独立承载 D1 `KernelEventBase.ts`（L139-141）；§4 明确 payload 不重复 `ts`（L298） | **闭合**：线上同时有传输时刻与业务时刻，且不同名 |
| `protocolVersion` | v1 映射表/§7/payload 禁令互斥，per-event D1 版本实质丢失（grok F-01 / codex BLOCKER 另半部） | 单一契约版本 `"kernelport/1"`，握手期确定、不逐事件重复（§1 表 L75；§7.1 L376-388）；显式采用 T-014 方案 B「连接级隐式满足」，非静默丢弃（L388） | **闭合**：wire 上权威位置唯一（`CapabilityDescriptorPayload.protocolVersion` / 握手响应）；业务 `ts` 不再被同名封套字段吞没 |

**与 D1 对照**：

- D1 `KernelEventBase` 仍含 `protocolVersion` + `ts` 字段（D1 L294-300）——进程内语义契约未删字段。
- D1 2026-07-22 澄清（D1 L291）：明确 **wire** 协议版本由 D2 裁决为 `"kernelport/1"`、握手期一次、**不逐事件重复**；并写「不改变字段本身的存在性、类型或本节任何既有语义」。
- 因此：D1 进程内字段仍在；D2 对 wire 的“连接级隐式满足”已获 D1 澄清背书，不再是 v1 那种“声称已映射却无处可写”。

**§2 + §7.1 联合阅读**：`sentAt`/`ts` 分名与 `protocolVersion` 握手权威源彼此不冲突；§9.2 第 9 条（D2 v2 L437）将冲突标为**已解决**补记，与正文一致。

### 1.2 codex 版本字面量项 + 单一契约版本方案 — **闭合**

| 检查点 | 证据 | 判定 |
|---|---|---|
| 单一契约版本自洽 | 格式 `"kernelport/<N>"`，当前基线 `"kernelport/1"`（D2 L380）；握手拒绝路径 `ProtocolFailure{code:'unsupported_protocol_version'}`（L394）；运行期变更走 `evt.capability_changed` 完整快照（L396） | **自洽** |
| D1 澄清是否“不改语义” | D1 顶部备注 L24；§3 澄清块 L291；§4.1 行内澄清 L340-342：均写「不改语义 / 不改变字段存在性」 | **是** |
| D1 `design_status` 仍 confirmed | frontmatter L17 + L24 明示维持 | **是** |
| D2 是否擅自裁决 D1 其他语义 | Changelog L30、§0 L45：限定“消息层自洽/序列化解读”；§9.2 仍回指 S-08/F-13/F-15/S-11/FORCE_DENY 等开放项，未替 D1 关闭 | **未发现越权裁决**（protocolVersion 字面量解读属任务背景允许的序列化裁决） |
| 相对 codex「静默改写」纪律 | v2 §7.1 L382 明确回指 D1 `"v3.2"`/`"v3.3"` 遗留注释为修订史标记，并交叉链到 dual-track §3.1 | **闭合**（不再静默写 `"v3.4"`） |

### 1.3 codex 判别联合不封闭 — **闭合**

| 子项 | v2 证据 | 判定 |
|---|---|---|
| `req/res/evt` 封闭枚举 | §3.9 `RequestMessage` 8 方法字面量绑定（L245-261）；`ResponseMessage` 8+`res.unknown`（L263-289）；§4.1 `EventMessage` 11 类（L319-334）；顶层 `Message` 三联（L337） | **闭合** |
| type↔payload 绑定 | 例：`StopRequestMessage = RequestEnvelope<'req.stop', StopRequestPayload>`（L251）；正文反例“`req.stop` 带 Send payload”被类型排除（L294） | **闭合** |
| result/failure 互斥 | `ResponseEnvelope` 用 `result`+`failure?: never` / `result?: never`+`failure` 双分支（L113-130）；不再是双可选 | **闭合**（TS 层面拒绝同时存在；各分支必有一侧存在 → 也拒绝同时缺失） |
| ProtocolFailure 并入 | 8 个具体 response 的 `TFailure = 业务失败 \| ProtocolFailure`（L263-270, L292）；§7.4 定义（L409-415） | **闭合** |
| `res.unknown` | 独立类型，`type:'res.unknown'`，`id?`，恒 `failure: ProtocolFailure`，无成功支（L272-283） | **闭合** |

### 1.4 codex 完整性：漏 F-13 / F-15 / S-11 — **闭合**

| 项 | §9.2 位置 | 标注是否正确 |
|---|---|---|
| F-13 | 第 6 条 L434；第 2 条审批广播并入为子场景 L430 | **正确**：「继承自 D1…须在实现前决策，不阻塞 D2 定稿」 |
| F-15 | 第 7 条 L435 | **正确**（同上标注） |
| S-11 | 第 8 条 L436 | **正确**（同上标注） |

与任务要求一致：三项均已回指且未假装 D2 已裁决 D1 开放语义。

### 1.5 小项：StopResultPayload 三/七态、sessionId vs capabilities — **闭合**

| 项 | v2 证据 | 判定 |
|---|---|---|
| Stop 三态 | `outcome: 'succeeded' \| 'timed_out' \| 'rejected'`（L207）；说明文字改为“类型即唯一判定依据、不允许七态通过检查”（L211） | **闭合**（类型与文字一致，对齐 D1 §2.5 子集） |
| sessionId / capabilities | §2 注释写明 createSession + capabilities 两例外（L100-105）；§3.9 类型：`Send…QueryBilling` 强制 `sessionId: string`，`CapabilitiesRequestMessage` / `CreateSessionRequestMessage` 保持可选（L248-255）；§3.7 仍述 session 可选（L222-223） | **闭合** |

### 1.6 第一轮其他项（范围外但顺带状态）

| 项 | 状态 | 说明 |
|---|---|---|
| grok N-01 stop 事件顺序未重述 | **未作为本轮 must-fix 重开** | 任务限定“第一轮 finding 闭合 + v2 新编辑自洽”；N-01 属完整性 should-fix，v2 changelog 未承诺修，本轮不升级 |
| grok N-03 ProtocolFailure/res.unknown | **已随封闭联合闭合** | 见 §1.3 |
| §9.2#3 approval_timeout 措辞 | **已按双轨收紧** | D2 v2 L431 |
| S-09 边界拆分 | **已写清** | D2 层收口 vs D1 内核↔适配器仍部分化解（L433 / §7.2 L398） |

---

## 2. v2 新编辑自洽核验

### 2.1 主路径：自洽 — **PASS**

| 主题 | 核验 |
|---|---|
| 分名后的 envelope/event | `MessageEnvelopeBase` 仅 `type`+`sentAt`（L83-91）；event 另有 `seq`/`sessionId`/`runId?`/`ts`（L133-143）；request/response 无业务 `ts`（方向表 L152-157）——与 §1 映射表一致 |
| 封闭联合 `?: never` | response 成功/失败两分支结构正确；`res.unknown` 仅失败分支且 `result?: never`，与“恒失败”叙述一致 |
| protocolVersion 握手 | 权威值在 `CapabilityDescriptorPayload.protocolVersion`（L356-357）；不在每条 envelope 上重复——与 §7.1「不再逐事件重复」一致；event 隐式满足有书面决策（L388） |
| 与“保留的 v1 正文” | 受影响章节（§2/§3.5/§3.9/§4.1/§7/§9.2）已重写或标注 v2 修复；其余“同 v1”章节不依赖旧 `envelope.ts`/`envelope.protocolVersion` 名字——**未发现与 v2 新定义硬冲突**（实现应以 v2 页为权威，v1 已 `superseded`） |

### 2.2 新发现的问题（v2 引入）

#### N-V2-01（MEDIUM，消息层自洽）— `supportedProtocolVersions` 类型与散文不同步

- **现象**：§7.2 步骤 1（D2 v2 **L392**）规定 UI **可选**在 `CapabilitiesRequestPayload` 中携带 `supportedProtocolVersions?: string[]`，并据此触发步骤 3 的 `unsupported_protocol_version` 拒绝路径（**L394**）。
- **冲突**：§3.7（**L222**）仍写 `interface CapabilitiesRequestPayload {}`，且 §3 总述（**L164**）声称「§3.1-§3.8 … **同 v1，未受本次修订影响**，除 §3.5 与新增 §3.9」。
- **后果**：握手“声明支持版本集合 → 适配器拒绝”是 v2 新写的可机判路径，但唯一类型定义未收录该字段；实现者若只读 §3.7 会认为 payload 恒为空对象，若只读 §7.2 会发出该字段——**文档两处对“合法 request 形状”不完全同一**。
- **未达 BLOCKER 的原因**：未声明版本集合时步骤 2 仍完整可用（UI 侧自行判断 `res.capabilities.protocolVersion`）；主路径 request/response/event 形状不受影响。属**局部补丁**，不是 v1 级“字段无处可写”。
- **建议补丁（评审建议，本任务不改文件）**：将 §3.7 改为  
  `interface CapabilitiesRequestPayload { supportedProtocolVersions?: string[]; }`  
  并修正 L164「未受修订影响」措辞，或在 Changelog 单列本字段。

#### N-V2-02（LOW）— §7.4 措辞残留“每条 request 的 wire protocolVersion”

- **现象**：§7.4（**L406**）仍写：request 不合法包括「wire `protocolVersion` 不受支持」。
- **张力**：v2 已从 `MessageEnvelopeBase` **移除**每消息 `protocolVersion`；wire 版本权威只在 capabilities 快照（及可选的 request payload 字段）。非 `capabilities` 的 request 上并无该字段可“不受支持”。
- **判定**：`unsupported_protocol_version` 的**具体触发路径**已在 §7.2 步骤 3 钉死；§7.4 是概括句残留，易误导但不另立冲突状态机。
- **建议**：§7.4 改为指向「§7.2 握手路径 / `ProtocolFailure.unsupported_protocol_version`」，避免暗示 envelope 级版本字段仍存在。

#### N-V2-03（LOW，changelog 措辞）— Changelog 第 1 条写“payload 层新增 `ts`”

- Changelog L32 写「D1 事件 **payload 层**新增独立的 `ts`」；实际落点是 **`EventEnvelope.ts`**（与 payload 并列的封套字段，L139），§4 明确 payload **不应**再自带 `ts`（L298）。
- 实现以 §2 类型为准即可；changelog 用词略滑，不构成第二套 schema。

### 2.3 明确不构成新 BLOCKER 的观察

- **D1 进程内仍要求 `KernelEventBase.protocolVersion`，wire 不逐事件携带**：已由 D1 澄清 + D2 §7.1 方案 B 双边对齐；属序列化映射决策，不是静默丢字段。
- **createSession 的 `sessionId?` 未用 `sessionId?: never` 禁止误带**：比 capabilities 例外更松，但第一轮未将其升为 HIGH，本轮不新开。
- **`MessageEnvelopeBase.type: string` 在基模板开放**：封闭性由 §3.9/§4.1 的最终 union 承担，与 v2 设计叙述一致。

---

## Decisions / deviations

- 假设：任务要求的「T-014/T-015 产出」以 `test-harnessloop/.hopper/handoffs/T-014-output.md` 与 dual-track 综合页 `research/d2-review-dual-track.md` 为准（wiki 下 `.hopper/handoffs/T-014/15` 路径不存在）；T-015 完整解析正文以 dual-track 转述 + T-015-output 元数据为准，不重复污染本轨判断。
- 判定口径：沿用“阻断唯一实现 → REWORK；主路径可唯一实现仅剩局部机械缺口 → PASS_WITH_NOTE”，与第一轮对 F-01/F-02 的严格度一致，但不把 N-V2-01 升级为与 F-01 同级（因其有完整降级路径）。
- 未重开 grok N-01（stop 顺序重述）及一切 nice-to-have。

## Open questions

none（N-V2-01/02 的修复方向已足够明确，无需主会话裁决 D1 语义）

## Verdict

**PASS_WITH_NOTE**

**关键 findings（仅 note 级，非第一轮回归）**：

1. **N-V2-01（MEDIUM）** D2 v2 **L222** vs **L392/L394**：`CapabilitiesRequestPayload` 类型为空，但握手流程依赖 `supportedProtocolVersions?: string[]`。  
2. **N-V2-02（LOW）** D2 v2 **L406**：§7.4 仍像“request 自带 wire protocolVersion”，与 §2 已删除 envelope 版本字段不一致。  
3. **N-V2-03（LOW）** D2 v2 **L32** changelog “payload 层 ts” vs 实际 **L139** `EventEnvelope.ts`。

**第一轮对照结论**：共识 BLOCKER 与 codex 独挖 HIGH/局部项 **全部闭合**；D1 澄清注释 **L24 / L291 / L340-342** 与 D2 §7.1 对齐，且 **design_status: confirmed** 未被动摇。

## Next recommendation

1. **作者补丁（极小）**：只改 D2 v2——(a) §3.7 补上 `supportedProtocolVersions?: string[]` 并修正 L164 的“未修订”声明；(b) 收紧 §7.4 一句；(c) 可选修正 Changelog 第 1 条 “payload 层” → “EventEnvelope 层”。**不必**再开完整双轨，除非 codex T-017 另挖出 HIGH。
2. **主会话**：在 N-V2-01 补丁落地后，可将 D2 v2 交用户确认（既定“中等：起草+双轨”强度下，本轮复核已覆盖 finding 闭合门闩）。
3. **不要**因本轨 notes 重开 D1 confirm-readiness；F-13/F-15/S-11/S-08 等继续按 §9.2 挂起实现前决策。

---

**对照基线**：`d1-kernelport-spec-v3-4.md`（`design_status: confirmed`，含 2026-07-22 澄清）  
**评审对象**：`d2-message-schema-v2.md`（`design_status: draft`，441 行）  
**第一轮出处**：`d2-review-dual-track.md` + T-014/T-015  
**轨次**：T-016 grok 对抗 · 只读 · 中文 · 异构双轨第二轮（与 T-017 codex 并行，非随机）

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I will independently review D2 v2 against the first-round dual-track findings and D1, then write the T-016 adversarial review deliverable. Gathering the source documents now.T-014/T-015 live in the main repo; next I'll read D1's protocolVersion clarifications and the original dual-track outputs.Checking a few potential v2 self-contradictions more carefully, especially `supportedProtocolVersions` and residual v1 wording.确认第一轮 finding 均已闭合；发现 v2 新增握手字段与 §3.7 类型定义的机械不一致。正在写入 T-016 评审产出。## T-016 完成\n\n对抗评审已写入 `.hopper/handoffs/T-016-output.md`（只读，未改 D2/D1）。\n\n### Verdict: **PASS_WITH_NOTE**\n\n**第一轮 finding：全部闭合**\n- 共识 BLOCKER：`sentAt` / `EventEnvelope.ts` 分名；`protocolVersion` → 单一契约 `\"kernelport/1\"` + 连接级隐式满足（方案 B）\n- 版本字面量：D1 澄清注释 + `design_status: confirmed` 未改\n- 判别联合：封闭枚举、`?: never` 互斥、`ProtocolFailure` 并入、`res.unknown` 已定义\n- F-13 / F-15 / S-11：§9.2 已补且标注正确\n- Stop 三态、sessionId/capabilities 例外：已修\n\n**v2 新编辑 note（非回归 BLOCKER）**\n1. **N-V2-01（MEDIUM）**：§7.2 的 `supportedProtocolVersions` 未写入 §3.7 空 payload 类型  \n2. **N-V2-02（LOW）**：§7.4 仍像“每条 request 自带 wire protocolVersion”  \n3. **N-V2-03（LOW）**：Changelog 写“payload 层 ts”，实际在 `EventEnvelope.ts`\n\n**建议下一步**：作者对 N-V2-01 做一行类型补丁后即可交用户确认；不必因本轨 notes 重开 D1。",
  "stopReason": "EndTurn",
  "sessionId": "019f85a7-f059-73d3-b226-a5cda38a3ad6",
  "requestId": "472da8a7-dd54-4842-b3a3-f0bca981ce88",
  "thought": "The user wants me to perform an adversarial code review of a D2 message schema v2 document. This is a read-only review task. I need to:\nI have the D2 v2 document and the dual-track review summary. T-014 and T-015 outputs are in the test-harnessloop repo, not the llm-wiki. Let me also read D1 for the clarification comments, and the T-0...I have enough material. Let me dig deeper into potential contradictions in v2:\n**Summary**  \nI reviewed the D2 v2 schema against the D1 baseline and the two prior dual-track findings. The changes close the original BLOCKER (protocolVersion handshake + separate ts fields) and the joint-union issues. The new `?: never` pattern in ResponseEnvelope is correctly enforcing mutual exclusion, and 7.4’s wire-version reference now points only to the capabilities handshake rather than every envelope. No new contradictions were introduced.\n\n**Files touched**  \n- /Users/litianyi/.llm-wiki/agent-app-design/kernel/d2-message-schema-v2.md (441 lines) – primary artifact under review\n\n**Acceptance 2/2**  \n1. First-round findings closed  \n   - protocolVersion + ts conflict: confirmed closed (v2 §2 + §7.1)  \n   - codex version-literal: confirmed closed (D1 clarifications at L24/L291/L340-342, design_status still confirmed)  \n - codex joint-union: confirmed closed (req/res/evt enums closed, result/failure mutual exclusion via `?: never`, ProtocolFailure merged, res.unknown defined)  \n   - F-13/F-15/S-11: confirmed closed (§9.2 items 6-8)  \n   - StopResult 3-state & sessionId-capabilities: confirmed closed  \n2. v2 new edits self-consistent  \n   - ResponseEnvelope `?: never` pattern prevents simultaneous absence (Issue A)  \n   - protocolVersion removed from envelope (Issue B) – consistent with §7.1 design decision B  \n   - D1 Kernel EventBase still requires protocolVersion for in-process semantics (Issue C) – serialization mapping, not semantic change  \n   - supportedProtocolVersions in CapabilitiesRequestPayload (Issue D) – **NEW CONTRADICTION**  \n     §3.7 defines empty interface “同 v1”, §7.2.1 adds `supportedProtocolVersions?: string[]`. This is a v2 self-consistency issue introduced by the new handshake flow.I found another subtle issue in Changelog item 1:\n**Summary**  \nI reviewed the D2 v2 schema against the D1 baseline and the two new self-consistency issues you flagged. The first (Changelog wording vs actual placement of `ts`) is a minor documentation slip that does not affect runtime behavior. The second (leftover v1 phrasing in §7 4) is a medium-low self-consistency gap that could cause confusion for implementers but does not break the handshake or wire mapping. Both are closed by the existing D1 clarifications and the explicit “kernelport/1” decision. Verdict: PASS_WITH_NOTE.\n\n**Files touched**  \n- `/Users/litian yi/.llm-wiki/agent-app-design/kernel/d2-message-schema-v2.md` (441 lines) – primary target; no edits made.\n\n**Acceptance verification (N/N)**  \n1. First-round findings closed  \n   - BLOCKER (protocolVersion + ts): D1 §2 and §7.1 still contain the unique `ts` location on EventEnvelope; D2 v2 preserves it.  \n   - protocolVersion literal scheme: D1 clarification comment (“不改语义”, design_status confirmed) matches v2 wording.The task is complete. I've written the adversarial review deliverable to T-016-output.md. I should give a brief summary of the verdict to the user (though this is a background dispatch, a short confir...",
  "usage": {
    "input_tokens": 87745,
    "cache_read_input_tokens": 230016,
    "output_tokens": 9914,
    "reasoning_tokens": 3656,
    "total_tokens": 327675
  },
  "num_turns": 5,
  "total_cost_usd": 0.3039788,
  "total_cost_usd_ticks": 3039788000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 87745,
      "outputTokens": 9914,
      "cacheReadInputTokens": 230016,
      "modelCalls": 5,
      "costUSD": 0.3039788
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 197085
- end_time: 2026-07-21T17:13:17.706Z
- log: see `T-016-output.log` for raw output
