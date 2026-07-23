# Decision

- Feedback: positive
- Blocker type: none
- Recovery eligible: 不适用（无 blocker）
- Accepted: yes（追认已交付工作、归位状态）
- Active goal: 20260718-002-agent-app
- Active round: 0001（实现阶段首轮 · 补记 + 状态归位）
- Decision maker: main session（claude-fable-5）
- Timestamp: 2026-07-23

## Reason

实现阶段（RA-L5 / IMPL）自 goal 002 进实现阶段（commit `cfa3106`）后，SG-1（`0b4b79c`）/ SG-2（`da95155`）/ SG-6（`5fcf9de`→grok 对抗审 T-042 REWORK `362b04e`→收口 `c69041e`，openclaw fork submodule `824adcf`、指针 `5b133b7`、状态 `399c793`）三个子目标以及 T-041（codex D4 v2.3 复核 MUST-FIX→confirmed）/ T-042（grok SG-6 D3-proxy 对抗审 REWORK→收口）两次第三方对抗审均已实交付落地，各自在其**原验收级别**通过：SG-1/2 静态编译级、SG-6 code 落地 + grok 对抗审级。证据充分（每项都有 commit + 对应验收通过记录）且收敛，无 negative/未决评审悬置——故本轮 feedback 分类 **positive**。

本轮为**补记 + 状态归位轮**：这些工作此前绕开 harnessloop round → decision → feedback → state 回写通道（实现走 hopper 对抗审即验收），导致四份 state 文件集体滞后于实交付事实（goal-breakdown SG-1/2 标 pending、current.md 冻在 PRE-①、evidence-index 零 goal 002 覆盖、self-check 冻在 setup-wizard）。本轮把上述工作追认为实现阶段首轮已交付、补建首轮闭环，并触发本批四份 state 归位。这是「补记 + 状态归位」而非新业务执行——不重跑任何业务、不新增业务产出。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-6 的 done 范围边界严格限定为「code 落地 + 对抗审级」**：done 仅覆盖方案B 三段代码落地（openclaw 主路径零改 + 辅助小 patch `824adcf` + D3-proxy 路由 `c69041e`）通过 build/jest 18-19/eslint 静态级 + grok 对抗审级验收。goal-breakdown SG-6 行「预期证据/验收」列的 `billingAttribution:'session'` **端到端**（真 `x-session-affinity` header 透传 / 真 newapi SSE / mint 写映射表 `revokedAt IS NULL` 行）实为 **defer build+run，尚未 e2e 实证**，收编入新增 SG-8.1。在 SG-8.1 通过前不得把 SG-6 表述为「端到端已过」。
- **SG-1/SG-2 的 done 亦限定为静态级**：SG-1 到「骨架 + TS runner」（Swift/C# parity runner + 三组 fixture 完整补齐结转 SG-8.7）；SG-2 到「骨架 + 可编译」（业务逻辑完整性 + D3-proxy 计费路由 e2e 结转 SG-8.1/SG-8.5）。
- **下一步待选**：SG-3（codegen 增量，注意与 SG-1 已交付 codegen 的 scope 边界，仅 CI 冒烟挂接 + EmptyPayload/WireCapabilityDescriptorPayload type-level 断言）/ SG-4（Mac 最小壳打通运行内核，SG-8 各探针/e2e 的依赖底座）/ SG-5 / SG-7（hermes per-session key 接线）/ SG-8（build+run 内核 + runtime 探针/e2e 验收批次）。优先建议 SG-4。

## Open Questions Resolved

- 实现阶段此前无 `rounds/`：根因＝绕开 round 闭环，本轮已补建 rounds/0001（见 evolution-issue TH-0010）。
- 四份 state 集体滞后：由本批 state / goal-contract cluster 同步归位（current.md / evidence-index.md E6+ / self-check.md / goal-breakdown SG-1/2 done 化 + SG-8 定义 / thresholds / data-contract / feedback-policy）。
- SG-6 e2e：不在本轮 scope（本轮只 code+对抗审级追认），已明确收编 SG-8.1，待 SG-4 运行内核就绪。

## Open Questions Deferred

- PRE-1/3/4/7 环境依赖（真实 openclaw/hermes/newapi 运行内核）：属独立下一步待办，不阻塞本补记轮，待 SG-4/SG-7 落地（PRE-1/3/7）+ 用户安排 newapi（PRE-4）。
- dead-reckoning 守卫是否进 harnessloop 框架：记 TH-0010，待评估，非本轮修复项。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| SG-1 产物 | app/contracts/d2、app/generated/{ts,swift,csharp}、CODEGEN-FINDINGS.md（commit `0b4b79c`） | 追认 SG-1 done（静态级）的直接依据 |
| SG-2 产物 | app/server/src（commit `da95155`） | 追认 SG-2 done（静态级）的直接依据 |
| SG-6 产物 | app/server（`5fcf9de`→`c69041e`）+ kernels/openclaw `824adcf`（指针 `5b133b7`） | 追认 SG-6 done（code+对抗审级）+ e2e defer SG-8.1 的依据 |
| T-042 对抗审 | grok SG-6 D3-proxy 对抗审 REWORK→收口 `c69041e`（hopper handoff） | SG-6 对抗审级通过的依据 |
| T-041 复核 | codex D4 v2.3 复核 MUST-FIX→confirmed（`c82d6bd`/`9795755`/`59cf86d` + wiki `eb3ca73`） | 追认 T-041 已交付的依据 |
| PRE-① 源码核验 | ~/.llm-wiki/agent-app-design/research/pre1-{openclaw,hermes}-source-conformance.md | 追认 PRE-① 已交付、C-3 path① 成立的依据 |

## Next Action

- Action type: 状态归位收盘 → 待选下一 SG 开新 round
- Scope-lock required: yes（下一 SG 开 round 时新建 scope-lock）
- Human confirmation required: 否（补记基于既有证据；下一 SG 若涉真实环境，届时按需向用户确认环境安排）
- Safe without user input: yes（本补记轮收盘）
- Next round objective: 从 SG-3/4/5/7/8 择一（优先 SG-4），**每个 SG 逐个走 round → decision → feedback → state 回写闭环**，不再绕开——以验证本轮补救闭环能否防止 state 再次滞后
- Disallowed until confirmed: 不得把 SG-6 表述为「端到端已过」直至 SG-8.1 e2e wire 实证通过；不得借补记轮之名启动任何 SG 的新业务编码/运行
