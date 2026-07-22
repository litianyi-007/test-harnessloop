---
task_id: T-027
adapter: grok
model: grok-4.5
status: done
task_type: code-review-adversarial
language: zh-CN
reviewed_at: 2026-07-22
review_target: /Users/litianyi/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md
phase: done
last_progress_at: "2026-07-22T03:20:00.000Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
assumption: 只读评审 D4；交付物仅写本文件。T-027=grok 轨；与 T-028 异构并行，非随机。
end_time: "2026-07-22T03:01:43.845Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 200518
adapter_status: success
---

# T-027 — D4 跨平台架构 v1 对抗复核（grok 轨）

## Summary

对 `architecture/d4-cross-platform-arch.md`（284 行，`design_status: draft`）做只读对抗复核，事实源为 T-026，契约基线为 D1 v3.5 / D2 v3 / D5 全 9 页 / D3。总体质量高：T-026 rank #2 与「零 Node sidecar」代价对照诚实；六否决方案公允；D2 无机器可读 schema 的阻断性前置判断**核实正确**；金标 parity + codegen + monorepo 骨架连贯可执行。主要缺口在**可执行细度**与**锚点精度**（codegen 覆盖面偏类别级、`KernelClient` 协议生成边界过宽、`SessionLockState` 章节锚点错误、fixture 对 `stop()` 三态子集与 D2 开放竞态覆盖不足）。**Verdict：PASS_WITH_NOTE**——架构方向可保留，升 `confirmed` 前做一次短修订 pass 即可，不需要推倒重写。

## Files touched

- `.hopper/handoffs/T-027-output.md` — 本评审指定交付物
- 评审对象与全部契约/事实源：none（未修改 D4、T-026、`~/.llm-wiki/` 或其它仓库文件）

## Acceptance verification (5/5)

### 维度 1：T-026 保真

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 1.1 | rank 排序是否忠实 | **通过** | D4 §1.3/§1.4：rank #1=双端原生 UI+共享 TS kernel-client（综合 5），rank #2=双写+共享 schema/fixtures（综合 4，跟随成本 3）。对照 T-026 §5 排序表 rank 1–2 行，分数与备注一致 |
| 1.2 | 1Password / Dropbox / UniFFI 案例是否超 confidence 臆造 | **通过** | D4 §1.2：UniFFI 官方 Swift/Kotlin + C# 第三方 `uniffi-bindgen-cs`（`confirmed`）；1Password「Rust Core 止于 UI」但桌面前端仍可能走 Electron（双刃剑）；Dropbox 2019 放弃 C++ 共享 model。均有 T-026 §1.1/§1.2 原文与置信度支撑，未把「未能确认」抬成 confirmed |
| 1.3 | 选定方案=rank #2 的诚实成本对照 | **通过** | D4 §1.4/§7.3 明确：跟随成本 4→3、写两遍 runtime 不因「用户已决定」而淡化；TS 仅作开发期 oracle 不打包。对齐 T-026 备选决策树「若禁止任何 Node 进用户机器 → 方案 2」与风险缓解表 |
| 1.4 | 有无 T-026 未覆盖却标为 confirmed 的架构事实 | **通过（有纪律）** | §3.2/§3.3 JSON Schema 选型明确标「本页作者工程判断、`部分`，T-026 不含此题」；§3.3 要求实现前冒烟验证——未伪装成 T-026 confirmed |

**本维判定：PASS**

---

### 维度 2：ADR 合理性

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 2.1 | 六否决方案理由是否成立、公允 | **通过** | Rust+FFI：Windows 非一等 + 对已 JSON-RPC 的 D2 重复付税 + 1Password 正交性；C++：Dropbox 负案例；KMP：桌面大规模案例未能确认；.NET 跨端 UI：Skia/Catalyst 不满足「各自原生」；Electron/Tauri：硬约束 + 综合 1；TS sidecar：T-026 rank #1 但被用户约束否决——D4 明确「不是方案有缺陷，是约束优先」 |
| 2.2 | 选定方案对「原生非 Electron / Mac 先行 / 非专家 / 成本敏感」是否自洽 | **通过** | 学习曲线 5、原生符合 5、不引入第二语言税；Mac/Win 滞后锁在 UI+手写 client，协议层靠契约；与 T-026 成本敏感排序逻辑一致 |
| 2.3 | 否决 rank #1 是否扭曲 T-026 | **通过** | §1.4 整节专责诚实对照，引用决策树分支而非误读排序表 |

**本维判定：PASS**

---

### 维度 3：D4→D2 依赖刻画 + codegen

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 3.1 | 「D2 v3 无机器可读 schema」核实是否正确 | **通过** | 直接读 `d2-message-schema-v3.md`（527 行，`design_status: confirmed`）：类型均为 markdown 内 TS `interface`/`type`；全文无 `JSON Schema`/`codegen`/`机器可读` 产物入口。D4 §3.1/§7.1 结论成立。**注**：D4 写「528 行」与 `wc -l`=527 差 1 行，琐碎，见 F-06 |
| 3.2 | 方案 (a) 提升 JSON Schema vs (b) 从 TS 反抽 | **通过（设计判断合理）** | (b) 对 `EmptyPayload=Record<string,never>`、`WireCapabilityDescriptorPayload=Omit & {protocolVersion?: never}` 的保真风险与 D2 Changelog/T-019/T-020 修复动机一致；JSON Schema `additionalProperties:false` 论证自洽。置信度降级诚实 |
| 3.3 | codegen 覆盖面（11 事件 + 7+1 方法 + Empty/WireCap 等）是否完整 | **有缺口** | 顶层判别联合/方法/事件名 **正确**（对照 D2 §3 方法表 + §4 11 类 `evt.*`）。但 §3.5 表停在「类别级」：大量 **payload 字段级**类型在 D2 v3 中声明为「同 v1」未在本表枚举——`CreateSessionRequestPayload`/`SendRequestPayload`/`InterruptRequestPayload`/`MessageDeltaPayload`…/`file_ref` 变体、`StopResultPayload` 三态子集、`CapabilitiesRequestPayload.supportedProtocolVersions` 等。若第 0 步只转录表中列出的类别，字段级会漏。见 **F-02** |
| 3.4 | 「生成 KernelClient 协议骨架」是否可执行 | **部分过宽** | §3.6 称从「D1 语义 + D2 wire 双重约束」生成 Swift `protocol`/C# `interface`。机器可读对象若仅是 D2 JSON Schema，只能保证消息形状；`SessionLockState`、双通道 `operationId`、soft steer 二态 vs hard 五态、前置同步拒绝 vs `OperationOutcome` 等属 **D1 散文/状态机**，无法从 schema 直接 codegen。见 **F-03** |

**本维判定：PASS_WITH_NOTE**（阻断依赖判断正确；覆盖清单与协议生成边界需收紧）

---

### 维度 4：契约消费正确 + 金标 parity

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 4.1 | D1/D2/D5/D3 引用是否用对 | **大体通过** | 8 方法+queryBilling、11 事件、审批五态+中间态、`OperationOutcome` 七态、D3 排除 parity、D5 9 页组织 parity-matrix、C-1/C-3 措辞纪律、D5 §5.1 C-item 表与 §4 开放问题（14 项）引用真实存在 |
| 4.2 | 状态机来源锚点 | **有 1 处错误** | D4 §4.2：`SessionLockState` 来源写 `[[d5-00-foundation]] §2.5`——foundation **无 §2.5**（§2 仅 §2.1–§2.3）；正确锚点为 **D1 §9.3**（类型定义）+ foundation **§5.4**（产品面命名/门控）。见 **F-01** |
| 4.3 | 金标 fixture 关键契约边角 | **大体通过，有遗漏** | 审批转移（含中间态 3 分支）、handshake 3 类 + 禁热切、`res.unknown` 两分支、Empty/WireCap 边界、断线不补发、三层错误——均对齐 D1/D2。缺口：①`stop()` 可达 `OperationOutcome` **三态子集**未在 §4.2 与 interrupt 七态拆开要求（D1 §2.5 / D2 `StopResultPayload`）；②D2 §9.2 #4（`FORCE_DENY_PENDING_KERNEL_ACK` **之后**人工 `respondApproval`）未入 fixture；③组合场景 §7.3 已诚实标注持续成本。见 **F-05** |
| 4.4 | 多语言 runner + CI 闸 | **通过（可实现）** | 语言中立 JSON fixture + Swift XCTest / C# xUnit / TS oracle；两端 CI 全量 parity；Windows 开通门槛=主路径 fixture 绿——与 T-026 §3.4 一致，工程上可落地 |

**本维判定：PASS_WITH_NOTE**

---

### 维度 5：内部自洽 + 完整性

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 5.1 | monorepo + 契约优先 + Mac→Win 流程 | **通过** | §5.1–5.5 骨架完整；「先 contracts+fixtures → codegen → Mac → Win」强制顺序正确采纳 T-026 §3.4；反模式原样采纳 |
| 5.2 | 落地顺序（含第 0 步） | **通过** | §6 第 0 步= schema 转录+初始 fixtures，阻断合理 |
| 5.3 | 写两遍成本与缓解是否如实 | **通过** | §7.3：codegen 消类型、不消 runtime；金标捕漂移不防漂移；组合场景持续投入；保留未来 Rust 换实现路径但不降成本估计 |
| 5.4 | T-026 四 open questions 裁决 | **通过** | #1 开放（UI 栈无关 kernel-client）恰当；#2/#4 moot（无 Node 生产路径）标注「前提移除」而非「已解决」诚实；#3 核实为空+补齐路径恰当 |
| 5.5 | 其它自洽风险 | **有 note** | 「零 Node 进用户机器」若字面读，可能与内核进程技术栈冲突——应收窄为产品 client 层（F-04）；本地传输适配位置（stdio/socket/pipe）未在 monorepo 点名，但不污染 D2 的纪律正确（F-07） |

**本维判定：PASS_WITH_NOTE**

---

## Decisions / deviations

1. **只读硬约束 vs 落盘交付物**：仅写 `.hopper/handoffs/T-027-output.md`，不改 D4 与 wiki。
2. **行数口径**：D2 以 `wc -l`=527 为准；D4 自称 528 记为 F-06 琐碎 note，不升级。
3. **Verdict 刻度**：架构方向与 T-026/约束自洽且无阻断性事实错误 → 不给 REWORK；但存在实现前应修的锚点/覆盖面缺口 → **PASS_WITH_NOTE**（非 PASS）。

## Open questions

1. 用户「零 Node」约束的**精确范围**：是否允许 openclaw/hermes 内核自身若为 Node/TS 运行时存在，仅禁止 **product sidecar / 共享 TS client 进程**？
2. `KernelClient` 协议骨架是否改为：**手写薄协议**（对照 D1）+ **仅数据 DTO 由 JSON Schema codegen**，避免暗示状态机可生成？
3. Windows UI 栈（WinUI 3 vs WPF）是否在下一轮与用户冻结（D4 已正确标开放）？

## Findings（关键）

### F-01 · MEDIUM · 错误章节锚点
- **位置**：D4 §4.2 `SessionLockState` 行「来源：`[[d5-00-foundation]] §2.5`」
- **问题**：`d5-00-foundation.md` 的 §2 仅有 §2.1 主界面 / §2.2 导航 / §2.3 对象层级，**不存在 §2.5**。`SessionLockState` 四态类型定义在 **D1 §9.3**（`idle`/`send_pending`/`interrupt_in_progress`/`stop_in_progress`）；产品面门控叙述在 foundation **§5.4**。
- **建议**：改为「D1 §9.3（类型）· foundation §5.4（产品命名/门控）」。

### F-02 · MEDIUM · codegen 覆盖面清单不完整（类别级 vs 字段级）
- **位置**：D4 §3.5 覆盖面表
- **问题**：11 `evt.*` + 7+1 方法 + 封套 + Empty/WireCap + 失败类型 + 顶层联合 **正确**，但 D2 v3 大量 payload 定义为「同 v1/同 v2 未受修订影响」——`CreateSessionRequestPayload`、`SendRequestPayload`（含 `file_ref`）、`InterruptRequestPayload`、`RespondApprovalRequestPayload`、11 类 event payload、`StopResultPayload`（**仅三态**）、`CapabilitiesRequestPayload` 等未列入「必须进入机器可读 schema」的显式清单。第 0 步执行者可能只转录表内行，导致字段级二次漂移。
- **建议**：§3.5 增加「完整类型闭包」要求：以 D2 v3 + 回溯 v1 的全部 `type`/`interface` 为 inventory 清单，或写「凡出现在 Request/Response/Event 判别联合闭包内的类型均须转录」。

### F-03 · MEDIUM · `KernelClient` 协议「可 codegen」边界过宽
- **位置**：D4 §3.6
- **问题**：JSON Schema 擅长 **wire DTO**；D1 的 Promise/流、锁矩阵、双通道镜像、mode 可达 outcome 子集等是 **语义状态机**。声称「方法签名从 D1+D2 双重约束生成」易让实现者低估手写面，也与 §7.3「runtime 必须写两遍」的诚实口径略张力。
- **建议**：拆成 (i) codegen：**消息类型 + 可选 codec**；(ii) 手写/半手写：`IKernelClient` 方法与状态机（可用代码生成模板，但权威仍是 D1 文本 + fixtures）。

### F-04 · LOW · 「零 Node 运行时进用户机器」措辞可能过强
- **位置**：D4 §1.2/§1.4（继承 T-026 决策树用语）
- **问题**：若 openclaw Gateway 等内核组件本身带 Node/TS 运行时，字面「禁止任何 Node 进用户机器」与已钉死的本地内核进程模型冲突。D4 实际意图是 **否决 product 层 TS sidecar**，而非重开内核栈。
- **建议**：收窄为「产品 client 层 / 共享 kernel-client 不引入额外 Node 运行时或 sidecar；内核进程栈另按 X1/D1 既定」。

### F-05 · LOW · 金标 fixture 边角遗漏
- **位置**：D4 §4.2
- **问题**：(a) `OperationOutcome` 行写 soft 二态 + hard 五态，未单列 **`stop()` 仅 `succeeded|timed_out|rejected`**（D1 §2.5 / D2 §3.5）；(b) 未覆盖 D2 §9.2 第 4 条开放竞态（中间态 **之后** 的 `respondApproval`）——即便 D1 未裁决，fixture 至少应标 `SKIP/OPEN` 或「实现前冻结」；(c) 组合场景已在 §7.3 诚实承认，可保留为持续成本。
- **建议**：§4.2 增 `stop-outcome-subset` 行；对 D2 §9.2 未决项建 `parity/fixtures/open-or-deferred/` 登记。

### F-06 · TRIVIAL · D2 行数
- **位置**：D4 §3.1「528 行」
- **问题**：当前文件 `wc -l`=527。
- **建议**：改为「约 527 行」或不写死行数。

### F-07 · LOW · 本地传输适配落点未点名
- **位置**：§5.1 monorepo 骨架
- **问题**：两端原生 client 直连内核需 stdio/Unix socket/named pipe/localhost 等适配；INV-3 禁止写入 D2 schema 正确，但 monorepo 未预留 `apps/*/transport` 或 `packages/transport-adapters` 位置，Windows 跟随时可能各自发明。
- **建议**：在 §5.1 加一行「传输适配各自原生、不进 contracts/d2」。

---

## Verdict

**PASS_WITH_NOTE**

架构 ADR 主体成立：选定 rank #2、诚实成本、D2 机器可读 schema 阻断前置、金标 parity 作为唯一行为一致性机制、D3 排除 scope、T-026 OQ 裁决——均经得起对抗审查。不构成方向性 REWORK。升 `design_status: confirmed` 前建议短修订闭合 **F-01、F-02、F-03**（其余 F-04–F-07 可并入同一 pass）。

## Next recommendation

1. **短修订 pass（作者）**：修 F-01 锚点；扩 §3.5 类型闭包；收窄 §3.6 codegen 边界；可选收窄「零 Node」措辞 + 补 stop 子集 fixture 行 + transport 落点。
2. **不要**因本轨 findings 回退到 rank #1 或重开 Rust/KMP/Electron——否决链与用户约束仍然成立。
3. 修订后可与 **T-028（codex 轨）** 对照：若双轨共识集中在 F-01–F-03 同类问题，合并一次编辑即可；若 codex 挖出更高严重度（例如 D2 依赖误判），再评估是否升 REWORK。
4. 第 0 步落地前做 D4 §3.3 已要求的 **JSON Schema 冒烟**（Request/Response/Event 判别联合 + EmptyPayload + WireCapabilityDescriptorPayload → Swift/C# codegen）。

## 五维总表

| 维 | 判定 | 一句话 |
|---|---|---|
| 1 T-026 保真 | **PASS** | rank/案例/代价/决策树无超 confidence 臆造 |
| 2 ADR 合理性 | **PASS** | 六否决公允；rank #2 与约束自洽且诚实 |
| 3 D4→D2 + codegen | **PASS_WITH_NOTE** | 「无 schema」核实正确；覆盖清单与协议生成边界不足 |
| 4 契约消费 + 金标 | **PASS_WITH_NOTE** | 主干状态机正确；§2.5 锚点错 + fixture 边角漏 |
| 5 自洽完整 | **PASS_WITH_NOTE** | 流程可执行；措辞/传输落点可 sharpen |

**总 verdict：PASS_WITH_NOTE**

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll perform the T-027 adversarial review of the D4 cross-platform architecture spec against T-026 and the D1/D2/D5/D3 baselines—read-only on the targets, deliverable written to the handoff output.Next I'll verify D4's claims against D1/D2/D5/D3—event types, state machines, and whether D2 is only TS-in-markdown.I have enough evidence for the five-dimension review. Writing the T-027 deliverable.# T-027 完成\n\nD4 跨平台架构 v1 对抗复核已落盘：`.hopper/handoffs/T-027-output.md`（中文，只读，未改 D4/wiki）。\n\n## Verdict：**PASS_WITH_NOTE**\n\n架构方向可保留，升 `confirmed` 前做一次短修订即可，无需推倒。\n\n## 五维摘要\n\n| 维 | 判定 | 要点 |\n|---|---|---|\n| T-026 保真 | **PASS** | rank #1/#2、1Password/Dropbox/UniFFI、跟随成本 3 对照均有 T-026 支撑 |\n| ADR 合理性 | **PASS** | 六否决公允；选定 rank #2 与「零 Node sidecar」约束自洽且诚实 |\n| D4→D2 + codegen | **PASS_WITH_NOTE** | 「D2 无机器可读 schema」核实正确；覆盖清单偏类别级 |\n| 契约 + 金标 | **PASS_WITH_NOTE** | 11 事件/7+1 方法/五态/七态主干正确；有锚点与边角缺口 |\n| 自洽完整 | **PASS_WITH_NOTE** | monorepo/第 0 步/OQ 裁决连贯；措辞可 sharpen |\n\n## 关键 findings\n\n1. **F-01 MEDIUM**：`SessionLockState` 引 foundation §2.5——该节不存在；应为 **D1 §9.3 + foundation §5.4**\n2. **F-02 MEDIUM**：codegen 覆盖面停在类别级，缺 payload 字段闭包（`SendRequestPayload`/`file_ref`/`StopResultPayload` 三态等）\n3. **F-03 MEDIUM**：`KernelClient`「可从 schema 生成」边界过宽——状态机/双通道属 D1 语义，不能假装 codegen 消解\n4. **F-04–F-07 LOW**：零 Node 措辞过强、`stop()` 三态 fixture 未单列、行数 528→527、传输适配落点未点名\n\n## Next\n\n修 F-01–F-03 后可与 T-028（codex 轨）对账；不要因本轨回退到 rank #1 或重开 Rust/KMP/Electron。",
  "stopReason": "EndTurn",
  "sessionId": "019f87c2-9c57-7543-ac9d-3d5e939b736e",
  "requestId": "501da50c-bcf1-471a-9461-7bc4dcecc5b3",
  "thought": "The user wants me to perform an adversarial code review of a D4 cross-platform architecture document. This is a code-review-adversarial task (T-027 for grok). I need to:\nI have the D4 arch document and T-026 research. Now I need to verify against D1, D2, D5, and D3 contracts for accuracy of citations and claims. Let me read the key contract documents systematically.I need more specific verification on several points:\nLet me dig into more potential issues:\n**Summary**  \nI reviewed the D4 cross-platform architecture spec against the provided baselines (T-026 output, D1/D2/D3/D5 contracts, and kernel specs). The document is largely faithful to the source material, with accurate citations and reasonable rejection of alternative architectures. Minor issues exist around section references and 1-line discrepancies in D2 line counts, but these do not undermine the core claims. The codegen and parity testing design appears feasible and covers the key state machines.\n\n**Files touched**  \n- ~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.I've found several findings. Let me also check:\n**Summary**  \nI reviewed the D4 cross-platform architecture spec (284 lines) against the T-026 baseline and supporting contracts. I found two medium-severity issues: an incorrect internal reference to SessionLockState and an incomplete codegen inventory for payload types. Both are citation and completeness gaps rather than architectural flaws. 6 of 7 review criteria are satisfied; the remaining two are minor and do not affect the overall design direction.\n\n**Files touched**  \n- .hopper/handoffs/T-027-output.md (new)\n\n**Acceptance verification (N/N)**  \n1.I have enough material for a thorough adversarial review. Let me also check one more potential issue: D4 says \"D2 v3 全文,528 行\" but actual is 527 - trivial.\n**Summary**  \nI performed an adversarial code review of the D4 cross-platform architecture specification (284 lines) against the T-026 baseline and supporting contracts. The review confirmed that the architecture faithfully reflects the chosen native-client + shared-contract approach, correctly rejected alternatives, and accurately mapped dependencies to D1/D2/D3 契约. Minor gaps exist in payload coverage, state-machine fixtures, and one citation, but these do not undermine the overall design. Verdict is PASS_WITH_NOTE.\n\n**Files touched**  \n- ~/.llm-wiki/agent-app-design/architecture/d4-cross-platform-arch.md (284 lines) – primary spec under review (rationale: direct target of adversarial review)\n\n**Acceptance verification (N/N)**  \n1. T-026 fidelity – PASS  \n   Evidence: grep “rank #2” in D4 §2.The deliverable is written. Let me mark the todo as complete and provide a summary to the user.Task complete. I'll give a concise summary of the review results.",
  "usage": {
    "input_tokens": 189256,
    "cache_read_input_tokens": 613632,
    "output_tokens": 11394,
    "reasoning_tokens": 5073,
    "total_tokens": 814282
  },
  "num_turns": 8,
  "total_cost_usd": 0.6309656,
  "total_cost_usd_ticks": 6309656000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 189256,
      "outputTokens": 11394,
      "cacheReadInputTokens": 613632,
      "modelCalls": 8,
      "costUSD": 0.6309656
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 200518
- end_time: 2026-07-22T03:01:43.845Z
- log: see `T-027-output.log` for raw output
