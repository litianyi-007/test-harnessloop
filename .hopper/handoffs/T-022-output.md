---
task_id: T-022
adapter: grok
model: grok-4.5
status: done
task_type: code-review-adversarial
effort: medium
language: zh-CN
reviewed_at: 2026-07-22
review_target: /Users/litianyi/.llm-wiki/agent-app-design/product/ (D5 全 9 页)
phase: done
last_progress_at: "2026-07-21T19:55:39.035Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-21T19:55:39.033Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 296969
adapter_status: success
---

# T-022 — D5 产品规格 v1 对抗复核（grok 轨）

## Summary

对 D5 九页（`d5-product-spec` + foundation + 7 子面）做只读对抗复核，对照 T-021 产品事实源与 D1 v3.5 / D2 v3 / D3 契约基线。总体质量高：T-021 置信度标签多数诚实、契约消费大体正确、C-1/C-3/Goal/Subagent/模型热切等诚实缺口标注到位、Personality 双向搁置与文件名对账已在总纲层收口。但合成页「8 页完全一致」的声称**不成立**——至少存在 D5.2 待审批计数 vs D5.3 缓冲不可见的语义冲突，以及 D5.6 残留建议文件名死链；另有 foundation 将 sandbox 三档与 Ask/Approve for me/Full access 三模式误对齐、总纲开放问题遗漏 D3 坐席模型等缺口。**Verdict：PASS_WITH_NOTE**——可作为实现与用户确认的工作基线，但在升 `design_status: confirmed` 前须做一次短合成修复 pass。

## Files touched

- `.hopper/handoffs/T-022-output.md` — 本评审交付物（任务指定落盘路径）
- 评审对象与全部契约/事实源：none（未修改 `~/.llm-wiki/`、D5 正文、D1/D2/D3 或仓库其它文件）

## Acceptance verification (4/4)

### 维度 1：T-021 保真

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 1.1 | 七子面是否逐一锚定 T-021 §2–§8 | **通过** | 总纲 §1 导航表 + 各子面 header 范围声明；与 T-021 acceptance #3–#9 映射一致 |
| 1.2 | 「直接仿 codex」是否有 T-021 章节+置信度 | **大体通过** | D5.1–D5.7 均有「仿/调整」汇总表；tool-call 像素标「部分」、task 账单标「未能确认」与 T-021 §2.3/§5.3 一致 |
| 1.3 | 有无超出 T-021 confidence 的臆造形态 | **通过（有纪律）** | Personality 三态、MCP Restart、Invite 入口、Sol/Terra/Luna 等均回指 confirmed；未捏造像素规范 |
| 1.4 | 「因差异调整」理由是否成立 | **通过** | 弱化 git/变更集、license-租户-newapi 账单、插件后端自有目录、Computer Use 分期均对齐 T-021 §10.2 + 用户 2026-07-22 参数 |
| 1.5 | 重大偏离是否诚实标注 | **通过** | D5.7 §3.4 将 T-021 confirmed 的「chat 内热切模型」MVP 降为只读（契约无热更新路径）——差异大但标注清楚，且已进总纲 §3/§4 待用户确认 |

**本维判定：PASS**（无把「部分/未能确认」抬成 confirmed 的系统性造假）。

### 维度 2：契约消费正确

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 2.1 | 审批五态 + 中间态 | **通过** | D5.3 §5 / foundation §5.3 与 D1 §6.2：`PENDING`/`RESOLVED_*`/`TIMED_OUT_DENY`/`FORCE_DENIED_ON_STOP` + `FORCE_DENY_PENDING_KERNEL_ACK`；合法终态 4 个表述正确 |
| 2.2 | `OperationOutcome` 七态 | **通过** | foundation §5.4 七值与 D1 §2.4/§9.1 一致；`submitted` 不得写成「已成功打断」、`aborted_effect_unknown` 必须「状态不确定」纪律正确；对齐 C-1/C-4 |
| 2.3 | `CapabilityDescriptor` 字段 | **通过（有 1 处误映射，见 F-03）** | `approvalKinds` 五值、`approvalDecisionKinds` 内核差异、`interruptModes`、`sandboxLevels` 三档、`billingAttribution` 二分支、`usageReporting` 均真实存在于 D1 §4.1 |
| 2.4 | §7 billing / C-3 | **通过** | D5.4 §2.3/§4.3/§6#1 明确 C-3 未验 → 保守 `user_tenant_aggregate`；`fetchedAt`/`correlatable:false` 呈现纪律正确；`billing_query_subject_unresolved` 失败≠零用量 |
| 2.5 | D3 license/tenant/seat | **通过（状态机多为 D5 自建，已部分标注）** | D5.6 正确声明 D1/D2 无 license 概念；实体名对齐 D3；License/membership 细粒度 FSM 是产品层扩展，非 D3 字面枚举 |
| 2.6 | 有无发明契约没有的协议能力 | **通过（诚实缺口标注到位）** | Goal 无协议事件、Subagent 无 parentSessionId、Plugin 无 D1 分组、`model` 无 effort/目录字段、`ToolCallEvent.status` 仅 `'started'`（D1 v1 定义，v3.5 继承）——均未伪装成协议保证 |
| 2.7 | C-1~C-5 / F-13/F-15/S-08/S-11 | **通过** | 总纲 §5.1–5.2 映射准确；C-1→打断措辞保守、C-3→成本降级、F-13→多窗审批、S-11→模型措辞均与正文一致 |

**本维判定：PASS_WITH_NOTE**（契约主干正确；见 F-03 foundation 误对齐、F-05 D5.3 对 D1 `design_status` 元数据过时）。

### 维度 3：产品完整性

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 3.1 | 7 子面覆盖 T-021 v1 scope | **通过** | 消息流/会话/审批/成本/能力/账号/模型 全覆盖；admin 正确外置 Console |
| 3.2 | MVP vs 分期是否合理 | **通过** | 本地多会话、Computer Use 延后、L3 task 账单分期、内核默认隐藏、模型热切降级——与用户参数及契约边界自洽；补充分期点已列总纲 §4#1 待确认 |
| 3.3 | 关键交互/状态是否遗漏 | **有缺口（非阻断）** | 见 F-06：T-021 §2.5 桌面通知/Prevent sleep、§3.3 Remote handoff 未纳入；D3 Open Q「命名用户 vs 浮点坐席」未进总纲 §4（F-04） |
| 3.4 | Subagent / Goal 深度 | **可接受** | 诚实标注应用层自建 + MVP 三态徽标；未过度承诺协议进度条 |

**本维判定：PASS_WITH_NOTE**。

### 维度 4：跨子面连贯

| # | 检查点 | 结论 | 证据 |
|---|---|---|---|
| 4.1 | 命名/IA/对象模型 | **通过** | 项目/会话(chat)/thread=session/task=goal 长跑/Turn/Item 一致引用 foundation §3 |
| 4.2 | 状态机术语 | **大体通过，有硬冲突** | 审批五态、SessionLockState、OperationOutcome 用语一致；**D5.2 vs D5.3 缓冲计数矛盾 = F-01** |
| 4.3 | 总纲 §2 对账声称是否成立 | **部分不成立** | Personality 搁置、§6.4 编号、d5-3/5/7 死链修复属实；但「完全一致」过强（F-01/F-02/F-07） |
| 4.4 | 开放问题 8 条是否准确/完备 | **准确但不完备** | §4#1–8 均为真决策点；遗漏见 F-04/F-06 及 D5.1 新缺口（index/output 语义）未升总纲 |

**本维判定：REWORK 级别局部问题，整体 PASS_WITH_NOTE**。

## Findings（按严重度）

### F-01 · MEDIUM-HIGH · 跨子面硬冲突：D5.2「待审批计数含缓冲」vs D5.3「缓冲对 UI 不可见且无深度字段」

- **D5.2** `d5-2-sessions.md` §1.2 表「待审批计数」行：声称计数 = FSM `PENDING`（**含缓冲队列**），置信度写 **D1/D2 confirmed**。
- **D5.3** `d5-3-approvals.md` §6：缓冲请求**不**触发 `evt.approval_request`、不同屏多卡片；队列深度 **D1/D2 不暴露**；队列徽标明确标为 **D5 自行设计**，非仿 codex、非协议强制。
- **D1 §6.2**：pending 上限=1，#2 本地 FIFO 缓冲，仅 active pending 经 `approval_request` 呈现。
- **影响**：实现者若按 D5.2 会假定「可协议级读取缓冲深度」；按 D5.3 则最多显示 0/1。总纲 §2.5 声称 SessionLockState/审批术语无冲突，**漏查此点**。
- **建议**：D5.2 改为「仅 active pending：0 或 1」；若要做「+N 排队」必须与 D5.3 §6 同款标注「应用层/适配器扩展，非 D1 字段」，并移出「D1/D2 confirmed」。

### F-02 · MEDIUM · 合成修复未扫全：D5.6 仍含 foundation 建议文件名死链

- **位置**：`d5-6-account-license.md` §6.2 表跳转列仍写 `` `d5-05-capabilities-tools.md` `` / `` `d5-07-model-switching.md` `` / `` `d5-04-cost-usage.md` ``（后两者数字位数/后缀与实际 `d5-4`/`d5-5`/`d5-7` 不一致）。
- **对照**：总纲 §2.1 声称已修 d5-3/d5-5/d5-7 死链并给出对照表，**未覆盖 d5-6**。
- **建议**：统一改为实际落盘名或 `[[d5-5-capabilities]]` 等 wiki 链。

### F-03 · MEDIUM · foundation 将 `sandboxLevels` 三档误对齐 T-021 三权限模式

- **位置**：`d5-00-foundation.md` §5.5 `sandboxLevels` 行：「对应 T-021 §4.2 三档 Ask for approval / Approve for me / Full access」。
- **事实**：T-021 §4.2 三档是 **sandbox × approval policy 组合** 的用户文案；D5.3 §3.1 正确写明「Approve for me」**不放宽 sandbox**、且 `approvalProfile` 无 auto-review 字面量。Ask vs Approve for me 的差异在审批决策主体，不在 `sandboxLevels` 枚举值。
- **影响**：读 foundation 映射表的实现者可能把 Auto-review 误绑到某个 sandbox 档位。
- **建议**：改写为「sandbox 档位供权限模式组合使用；三用户模式完整映射见 D5.3 §3」。

### F-04 · MEDIUM · 总纲 §4 开放问题遗漏 D3 坐席模型关键决策

- **D3** `server-stack-selection.md` Open questions #2：「企业坐席是命名用户还是并发浮点？」直接影响 license/membership 模型。
- **D5.6** 默认呈现命名坐席/membership 状态机（`invited`/`active`/`suspended`/`removed`），未把「浮点坐席」作为分支。
- **总纲 §4** 未收录该项；若实现按命名坐席做 UI，后续 D3 选浮点将导致 D5.6 返工。
- **建议**：§4 增补「命名 vs 浮点坐席」；D5.6 加一句「当前 FSM 假设命名坐席」。

### F-05 · LOW · D5.3 对 D1 `design_status` 元数据过时/自相矛盾

- **位置**：`d5-3-approvals.md` 导语：D1 标 `design_status: draft`，待 codex re-verify。
- **事实**：`d1-kernelport-spec-v3-5.md` frontmatter 与顶部定稿段为 **`design_status: confirmed`**（正文历史段仍残留 draft 叙述，属 D1 页自身文档债）。
- **影响**：不改变审批 FSM 正文正确性，但损害 D5 作为契约消费方的引用可信度。
- **建议**：统一引用 frontmatter confirmed；若需说明「仅 protocolVersion 曾 draft」则写一句历史脚注。

### F-06 · LOW · 产品面小遗漏（相对 T-021，非 v1 阻断）

| 遗漏 | T-021 位置 | 建议 |
|---|---|---|
| 回合完成桌面通知、Prevent sleep while running | §2.5 | D5.1 或 foundation IA 表加 MVP 可选行 |
| Remote / handoff（本机↔remote host） | §3.3 | 明确「非 MVP / 外置后续表面」 |
| ChatGPT 统一壳层 Chat/Work toggle | 对象确认/§1.1 | 可一句声明 D5 只规格「agent/Codex 模式工作台」，不仿 Chat 模式 |

### F-07 · LOW · 总纲 §2「完全一致」措辞过强

- §2 开篇「命名/IA/状态机术语在 8 个页面间**完全一致**」在 F-01/F-02 面前不成立。
- **建议**：改为「命名与主 FSM 术语一致；已知残差见 §2.x / 开放问题」。

### 正面清单（对抗审查中确认**未**发现的问题）

1. **未**发明 `approvalKinds` 第 6 值 computer-use；Computer Use 预留纪律在 foundation/D5.3/D5.5/D5.7 互证。
2. **未**把 C-3 当已验证；L2/L3 降级路径可执行。
3. **未**把 Goal/Subagent 写成 D1 原生对象。
4. `approvalProfile?: 'auto'|'manual'|'plan'`（D1 约 L143）真实存在；D5.3 未与 Ask/Auto-review 假官方映射，开放项正确。
5. OperationOutcome 七态措辞表被 D5.1/D5.2 复用，无第二套文案。
6. Personality 归属已在 D5.5 §3.4 ↔ D5.7 §1/§7 双向闭合。
7. 行数速览与 `wc -l` 实测一致（foundation 313 … D5.7 289；总纲 166）。

## Decisions / deviations

- **只读解释**：不修改 D5/契约/事实源；唯一写入为任务指定的 `.hopper/handoffs/T-022-output.md`。
- **假设（一行）**：D1 权威状态以 frontmatter `design_status: confirmed` 为准（与任务 brief 一致）；正文残留 draft 叙述视为文档债，不单独否决 D5 对审批 FSM 的消费。
- **未**按 pixel-clone 标准审 UI 间距/颜色——与 T-021/clone-boundary 一致，只审交互模式与契约映射。
- **Vendor 偏离记录**：任务刻意指定 T-022=grok（非随机池抽取），本输出遵守该偏离。

## Open questions

1. F-01 缓冲计数：产品是否要「+N 排队」徽标？若要，权威数据源定在适配器扩展还是仅 0/1？
2. 总纲 §4#1 四项补充分期（模型热切降级、内核隐藏、Goal 三态、Personality）用户是否正式批准？
3. tenant 中文名冻结（工作区 vs 组织/团队）以避开 `workspace-write` 撞车（总纲 §2.4/§4#2）？
4. D3 命名坐席 vs 浮点坐席（F-04）？
5. Auto-review 落地字面量：`approvalProfile` 复用 `'manual'`+应用层 vs D1 扩枚举（总纲 §4#6）？
6. C-3 真机验证排期（总纲 §4#7）——阻塞 L2「本会话成本」产品承诺。

## Verdict

**PASS_WITH_NOTE**

理由：D5 v1 作为「仿 codex 产品规格 + 诚实契约消费」的成稿质量达到可进入用户确认与实现拆分的水准；T-021 保真与 C-item 纪律总体可靠，无系统性契约伪造。但合成页一致性声称有可证伪硬冲突（F-01）与未扫尽死链（F-02），另有 foundation 映射笔误（F-03）与开放问题缺口（F-04）——在升 `confirmed` 前必须短修复，不构成推倒重写。

若门禁把「总纲 §2 完全一致」当作硬验收，可降为 **REWORK**（范围仅合成修复，非七子面重写）。

## Next recommendation

1. **合成微修（建议同一会话 30–60min）**  
   - 修 F-01（D5.2 待审批计数）+ F-02（D5.6 文件名）+ F-03（foundation sandbox 映射）+ F-07（措辞）。  
   - 总纲 §4 补 F-04 坐席模型 +（可选）F-06 明确非 MVP 项。  
2. **用户确认批次**：总纲 §4#1–2 与 F-04 一并过审。  
3. **实现前**：排期 C-3 live probe；Auto-review 字面量技术决策（§4#6）。  
4. **双轨**：待 T-023（codex）产出后 diff findings；若两轨对 F-01/F-03 同判，直接按上列微修收口，无需第三轮全量起草。

## 机器可复查入口

```sh
# 评审对象行数
wc -l /Users/litianyi/.llm-wiki/agent-app-design/product/d5-*.md

# F-01
rg -n "待审批计数|含缓冲队列|队列深度|队列徽标" \
  /Users/litianyi/.llm-wiki/agent-app-design/product/d5-2-sessions.md \
  /Users/litianyi/.llm-wiki/agent-app-design/product/d5-3-approvals.md

# F-02
rg -n "d5-05-capabilities-tools|d5-07-model-switching|d5-04-cost-usage" \
  /Users/litianyi/.llm-wiki/agent-app-design/product/d5-6-account-license.md

# F-03
rg -n "sandboxLevels|Ask for approval|Approve for me" \
  /Users/litianyi/.llm-wiki/agent-app-design/product/d5-00-foundation.md \
  /Users/litianyi/.llm-wiki/agent-app-design/product/d5-3-approvals.md

# 契约锚点
rg -n "approvalProfile|FORCE_DENY_PENDING_KERNEL_ACK|billingAttribution|OperationOutcome" \
  /Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-5.md

# T-021 置信度锚点
rg -n "未能确认|部分确认|置信度" \
  /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/.hopper/handoffs/T-021-output.md
```

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "执行 T-022 对抗评审：只读审阅 D5 全 9 页与 T-021/D1/D2/D3 契约基线，产出四维 findings 与 verdict。先拉取评审对象与事实源。正在并行读取 D5 九页与契约/事实源关键文件。继续读取剩余子面与 T-021/契约关键段落。对照 T-021 与 D1/D2/D3 关键字段做事实核验。已完成四维核验。正在写入 T-022 评审交付物。已完成四维核验。结论为 **PASS_WITH_NOTE**：主干可用，但有跨子面矛盾与未收口项。正在写入 `T-022-output.md`。# T-022 完成 · Verdict: **PASS_WITH_NOTE**\n\n交付：`.hopper/handoffs/T-022-output.md`\n\n## 结论摘要\n\nD5 九页作为「仿 codex + 诚实消费 D1/D2/D3」的 v1 规格**总体可用**，不必推倒重写。T-021 置信度纪律、审批五态 / OperationOutcome 七态 / C-1·C-3 降级、Goal·Subagent 无协议对象、模型热切 MVP 降级等关键点均消费正确且标注诚实。\n\n但总纲 §2「8 页完全一致」**不成立**，升 `confirmed` 前需一次短合成修复。\n\n## 关键 findings\n\n| ID | 严重度 | 问题 |\n|---|---|---|\n| **F-01** | MEDIUM-HIGH | **D5.2** 待审批计数「含缓冲、标 D1 confirmed」与 **D5.3**「缓冲不可见、无深度字段」硬冲突 |\n| **F-02** | MEDIUM | **D5.6** 仍残留 `d5-05/d5-07/d5-04` 建议文件名死链（合成只修了 3/5/7） |\n| **F-03** | MEDIUM | **foundation** 把 `sandboxLevels` 三档误对齐 Ask / Approve for me / Full access |\n| **F-04** | MEDIUM | 总纲开放问题漏 **D3 命名坐席 vs 浮点坐席** |\n| F-05–07 | LOW | D5.3 对 D1 status 元数据过时、T-021 小遗漏、措辞过强 |\n\n## Next\n\n1. 同会话微修 F-01/02/03/07 + 补 F-04  \n2. 用户确认总纲 §4#1–2 与坐席模型  \n3. 与 **T-023（codex）** findings 对账后再升 confirmed",
  "stopReason": "EndTurn",
  "sessionId": "019f863b-0e2e-7b02-ba77-126a984f783a",
  "requestId": "0c0d232c-7089-4797-9a57-56074c964d61",
  "thought": "The user wants me to perform an adversarial code review of D5 product specification documents. I'm acting as the execution agent for T-022 (grok vendor) - a read-only adversarial review of product spe...Let me read all D5 product pages and the key source documents in parallel.I need to continue reading the remaining D5 pages (5, 6, 7) and the source documents (T-021, key sections of D1/D2/D3).I need to verify key claims against T-021 and D1/D2/D3. Let me read the critical sections from these source documents for adversarial verification.Let me dig deeper into a few potential issues I've identified:\n**Summary**  \nI performed an adversarial code-review on the D5 product specification set (d5-product-spec.md + 7 sub-pages) against the four review axes: T-021 fidelity, contract consumption accuracy, product completeness, and cross-subface coherence. I focused on the three inconsistencies you surfaced—design_status mismatch, dead-link references in d5-6, and the pending-count vs buffer-queue conflict—plus three additional contract-surface gaps I found while reading. Verdict is PASS_WITH_NOTE because the spec is mostly faithful but contains three clear internal contradictions that would break downstream implementation.\n\n**Files touched**  \n- d5-product-spec 166 lines (total-gov §2, C-item table, open-problem list)  \n- d5-3-approvals.md (design_status, buffer-queue visibility)  \n- d5-6-account-license.md (dead-link references, membership/license FSM)  \n- d5-2-sessions.I found solid findings. Let me also verify ToolCallEvent status from d1 v3 (definitions are \"同 v3.1\"). Let me check v3 or v1 for ToolCallEvent definition.\nI have enough material to write a thorough adversarial review. Let me structure the findings:\n**Summary**  \nI performed an adversarial code-review on the D5 product specification set (9 pages) for T-022, cross-checked against T-021, D1/D2/D3 contracts, and the provided acceptance criteria. The review uncovered several cross-surface inconsistencies and synthesis gaps that could mislead implementers, but 80 % of the content is accurate and well-annotated. Verdict is PASS_WITH_NOTE; the work is production-ready once the flagged items are fixed.\n\n**Files touched**  \n- /Users/litianyi/.llm-wiki/agent-app-design/product/d5-product-spec.Looking at prior review outputs for format, and assessing severity:\n**Summary**  \nI performed an adversarial code-review on the D5 product specification package (9 pages) against the T-021 codex-app baseline, D1/D2/D3 contracts, and cross-surface consistency rules. The review confirmed strong fidelity, correct contract usage, and mostly coherent structure, but identified three medium issues that violate the synthesis claim of full consistency.\n\n**Files touched**  \nnone (review object is external spec; no files modified)\n\n**Acceptance verification (N/N)**  \n1. T-021 fidelity: PASS – D5 correctly cites T-021 sections with confidence tags; no invented features (e.g.I'll write a comprehensive T-022 output following the required shape.The task is complete. I've written the adversarial review to T-022-output.md. Let me provide a concise summary for the user/hopper.",
  "usage": {
    "input_tokens": 148046,
    "cache_read_input_tokens": 812672,
    "output_tokens": 10115,
    "reasoning_tokens": 8445,
    "total_tokens": 970833
  },
  "num_turns": 9,
  "total_cost_usd": 0.6005836,
  "total_cost_usd_ticks": 6005836000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 148046,
      "outputTokens": 10115,
      "cacheReadInputTokens": 812672,
      "modelCalls": 9,
      "costUSD": 0.6005836
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 296969
- end_time: 2026-07-21T19:55:39.033Z
- log: see `T-022-output.log` for raw output
