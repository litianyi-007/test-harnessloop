# Hopper Queue

Anchor: `.hopper/queue.md::root`

- **Schema version**: 2 (Task-type column is the primary routing key)
- **Task spec source**: `.hopper/handoffs/leader-tasklist.md` (one section per task ID)
- **Status values**: `pending` / `in-progress` / `done` / `failed` / `removed`
- **Vendor routing**: each Task-type has a default vendor in `.hopper/AGENTS.md`;
  a row may override it via the optional `Vendor` column.

---

## Tasks

| ID | Task-type | Status | Depends | Priority | Brief | Vendor |
|----|-----------|--------|---------|----------|-------|--------|
| T-001 | code-review-adversarial | done | | normal | 对 harnessloop submodule commit 6936fbc（setup wizard 完整实现：新 skill+check_setup.py+profiles+四 SKILL 接线+validate 第 3 阶段）做只读对抗评审 | codex |
| T-002 | prd-research | done | | normal | agent app 的瘦业务控制面 server 技术选型调研（不跑 agent，管 license/多租户/坐席/能力开关/费用/newapi 集成；开发者非 server 专家，重生态成熟度·低运维·可维护性·成本敏感）——2-3 个现实栈方案对比+推荐 | grok |
| T-003 | prd-research | done | | normal | agent 内核与网关生态实况调研：openclaw/hermas 实际形态与控制接口、new-api/newapi 网关的用量·计费·模型管理 API、codex app sdk 与 claude code sdk 的 agent 能力暴露面——为 P2 内核抽象窄腰设计建立真实接口依据 | grok |
| T-004 | code-review-adversarial | done | | normal | 对 D1 KernelPort 内核窄腰设计 spec 做只读对抗性设计评审（窄腰能否真跨四内核·审批与 interrupt 收口是否手挥·newapi 边车漏洞·能力漂移）——异构第三方视角 | codex |
| T-005 | prd-research | done | | normal | D1 conformance spike：定向补 openclaw+hermes+newapi 的"未能确认"接口事实（session 生命周期/stop-delete/capabilities 协商与变更/事件 seq 与断线重放/审批 RPC 与关联 id/run 级取消寻址/newapi token 粒度与用量归因 API）——为 D1 v2 重设计建硬事实 | grok |
| T-006 | code-review-adversarial | done | | normal | 对 D1 KernelPort v2 spec 做只读对抗性设计复核（11 消解是否真消解·5 开放点 blocker-or-defer·SDK 延后是否干净·事实基线一致性）——异构第三方视角 | grok |
| T-007 | code-review-adversarial | done | | normal | 对 D1 KernelPort v3 定向复核：6 处修复是否落对（尤其 openclaw 原生 steer）+ openclaw sessions.steer 精确语义核实 + v3 有无新矛盾 + 5 残留点严重性 | grok |
| T-008 | code-review-adversarial | done | | normal | D1 v3 异构第二轨复核（刻意选 codex 求异构，非随机；grok 已 PASS_WITH_NOTE，独立复核+核实 grok 结论是否成立+找 grok 漏的+事实一致性） | codex |
| T-009 | prd-research | done | | high | D1 conformance spike（升 high：steer 精确 schema 已被 T-007/T-008 两次 web-search 未能确认，需 repo 级源码深挖；偏离 medium 默认已记录原因）——收两组硬事实：①openclaw sessions.steer 精确 RPC req/resp schema+runId 寻址+runtime 拒收时的结果态；②newapi 能否预分配 sessionId 并绑定专用 token 支撑 session 级成本归因 | grok |
| T-010 | code-review-adversarial | done | | normal | v3.1 聚焦复核（刻意选 codex：验证 codex 自己 T-008 提的 5 findings 是否真解 + 有无引入新矛盾 + steer 重映射是否与 T-009 事实一致 + 延后项是否真可延后；非随机，记录偏离原因） | codex |
| T-011 | code-review-acceptance | done | | normal | v3.2 定稿前 confirm-readiness gate（刻意选 codex：T-008/T-010 两轮 REWORK 最熟 finding 史；只验三件事：收窄是否诚实无残留过度声称 / 5 个 C-item 是否真属实现阶段无隐藏设计 blocker / v3.2 新编辑有无引入内部矛盾）——非开放重审 | codex |
| T-012 | code-review-acceptance | done | | normal | v3.3 定向重跑 confirm-readiness gate（刻意选 codex，接续 T-011）：只验 M1-M5 五项是否真闭合 + v3.3 为闭合它们的新编辑（aborted_effect_unknown 终态/ApprovalBufferResolvedEvent 第11类/两个新拒绝码/soft-cancel 遇 stop 锁规则）有无引入新矛盾——不重开 M1-M5 之外任何范围 | codex |
| T-013 | code-review-acceptance | done | | normal | v3.4 最终 gate（接续 T-012，只验 3 处残留闭合）：M1↔M4 soft 终态是否全文严格二态 / M5 失败通道同步-异步分层是否唯一确定 / §3 事件计数笔误是否勘正——+ 这 3 处修改有无引入新矛盾。不重开其他范围 | codex |
| T-014 | code-review-adversarial | done | | normal | D2 消息 schema v1 双轨复核（grok 轨）：是否忠实+完整序列化 D1 v3.4 定稿契约、有无语义漂移、封套/三层错误/审批流映射是否自洽、5 条回指 D1 待澄清点是否准确且无遗漏 | grok |
| T-015 | code-review-adversarial | done | | normal | D2 消息 schema v1 双轨复核（codex 轨）：同 T-014 同范围，异构独立视角 | codex |
| T-016 | code-review-adversarial | done | | normal | D2 v2 第二次双轨复核（grok 轨）：第一轮 REWORK 的 4 类 finding（字段分名/protocolVersion 单一契约版本/判别联合封闭/§9.2 补漏）是否真闭合 + v2 新编辑有无新矛盾 | grok |
| T-017 | code-review-adversarial | done | | normal | D2 v2 第二次双轨复核（codex 轨）：同 T-016 同范围，异构独立视角 | codex |
| T-018 | code-review-acceptance | done | | normal | D1 v3.5 + D2 v3 定向 re-verify（单 codex）：codex T-017 的 5 finding 是否真闭合（protocolVersion 连接级化诚实自洽/StopReq 真封闭/握手字段入schema/禁版本热切/res.unknown 统一）+ 新编辑有无新矛盾 | codex |
| T-019 | code-review-acceptance | done | | normal | D1 v3.5/D2 v3 收尾最终 re-verify（单 codex，接续 T-018）：D1 引用 PASS；capability_changed 的 Omit 不够严（一行 TS 加固），主会话直接补 `& {protocolVersion?:never}` 并自验，未再 gate | codex |
| T-020 | code-review-acceptance | done | | normal | D2 v3-r2 极简确认（单 codex，接续 T-019）：Verdict CONFIRMABLE——TS5.9.3 编译验证 `& {protocolVersion?:never}` 确关闭 Omit 结构化赋值缺口（完整 descriptor 被拒 TS2322），D2 v3+D1 v3.5 可定稿 | codex |
| T-021 | prd-research | done | | high | D5 codex app 产品形态调研 spike（升 high：全 7 子面产品规格质量依赖准确形态、需多面深挖，偏离已记录）——调研 OpenAI Codex 真实产品形态/信息架构/消息流/审批/成本/能力开关/账号坐席/模型切换，映射 D5 七子面，供起草取用避免臆造 | grok |
| T-022 | code-review-adversarial | done | | normal | D5 产品规格 v1 双轨复核（grok 轨）：T-021 保真（有无超 confidence 臆造）/ D1·D2·D3 契约消费正确（字段事件状态机是否真实用对、C-item 诚实标注准确）/ 产品完整性 / 跨子面连贯 | grok |
| T-023 | code-review-adversarial | done | | normal | D5 产品规格 v1 双轨复核（codex 轨）：同 T-022 同范围，异构独立视角 | codex |
| T-024 | code-review-acceptance | done | | normal | D5 v2.1 定向 re-verify（单 codex，接续 T-023）：F-01..F-10 是否逐条真闭合（createSession时点/billing snapshot/缓冲审批/能力toggle/License离线/archive/身份/模型热切confidence/缺失行为/死链）+ v2/v2.1 新编辑无新矛盾 | codex |
| T-025 | code-review-acceptance | done | | normal | D5 v2.2 最终 re-verify（单 codex，接续 T-024）：F-01/02/03/08/09 五处残留是否真闭合 + v2.2 编辑无新矛盾 → CONFIRMABLE 则 D5 定稿 | codex |
| T-026 | prd-research | done | | high | D4 跨平台原生架构调研 spike（升 high：基础性架构选型、需深度分析共享核心方案 FFI/成熟度）——Mac 原生优先/Windows 跟随+共享核心（Rust/C++/TS-sidecar/KMP/.NET 等），代码共享边界、Mac 先行 Win 跟随工作流、D1/D2 契约如何助跨平台 | grok |
| T-027 | code-review-adversarial | done | | normal | D4 跨平台架构 v1 双轨复核（grok 轨）：T-026 保真/ADR 合理性/D4→D2 依赖刻画/契约消费+金标parity/内部自洽 | grok |
| T-028 | code-review-adversarial | done | | normal | D4 跨平台架构 v1 双轨复核（codex 轨）：同 T-027 同范围，异构独立视角 | codex |
| T-029 | code-review-acceptance | done | | normal | D4 v2 定向 re-verify（单 codex，接续 T-028）：F-01..F-07 是否真闭合（fixture DSL/产品行为parity+D4→D3依赖/client stub手写/hard6态/Rust否决理由/capability_changed fixture/9页）+ v2 新编辑无新矛盾 | codex |
| T-030 | code-review-acceptance | done | | normal | D4 v2.1 最终 re-verify（单 codex，接续 T-029）：F-01/02/03/06 四残留是否真闭合 + v2.1 编辑无新矛盾 → CONFIRMABLE 则 D4 定稿 | codex |
| T-031 | code-review-adversarial | done | | normal | D6 newapi 集成 v1 双轨复核（grok 轨）：事实保真(有无臆造endpoint)/C-3处理诚实/契约消费正确/client直连vsD3代理叉口/内部自洽 | grok |
| T-032 | code-review-adversarial | done | | normal | D6 newapi 集成 v1 双轨复核（codex 轨）：同 T-031 同范围，异构独立视角 | codex |
| 
---

## Activity log

- queue initialized by `hopper-dispatch --init-tasks`
- 2026-07-17: T-001 added (code-review-adversarial, vendor=codex — 随机结果，见 .hopper/AGENTS.md 的随机机制说明；用户决策 2026-07-17）。Full spec in handoffs/leader-tasklist.md#T-001。
- 2026-07-17: T-001 首派失败——vendor 默认模型 gpt-5.6-sol 超出本机 codex CLI 版本，返回 400；教训=不信任 vendor 默认模型，须钉缓存模型名。
- 2026-07-17: T-001 重派成功——`--model gpt-5.5`，耗时 5 分钟，结果 REWORK + 3 findings，107,893 tokens。
