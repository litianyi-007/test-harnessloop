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

---

## Activity log

- queue initialized by `hopper-dispatch --init-tasks`
- 2026-07-17: T-001 added (code-review-adversarial, vendor=codex — 随机结果，见 .hopper/AGENTS.md 的随机机制说明；用户决策 2026-07-17）。Full spec in handoffs/leader-tasklist.md#T-001。
- 2026-07-17: T-001 首派失败——vendor 默认模型 gpt-5.6-sol 超出本机 codex CLI 版本，返回 400；教训=不信任 vendor 默认模型，须钉缓存模型名。
- 2026-07-17: T-001 重派成功——`--model gpt-5.5`，耗时 5 分钟，结果 REWORK + 3 findings，107,893 tokens。
