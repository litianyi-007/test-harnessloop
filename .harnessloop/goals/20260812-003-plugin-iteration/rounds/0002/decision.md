# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-106-codex-output.md
- Reviewer: codex via hopper T-106（单路，按 scope-lock 既定——改动面小且判据清晰，双路留给设计类或大改动）
- Review verdict: **REWORK**（四条发现全部由主会话独立复现后返工，返工结果见下方「返工后未再评审」一节）
- Review digest: 29f7d24b3c33702f2fabbdf3d66831581d96a086ce423b6ce5c7c3cebf6e1d41
- Acceptance evals: none — 本 goal 无 runtime eval 台账；验收走 `goal.md` 的七条标准
- Acceptance evals detail: n/a
- Active goal: 20260812-003-plugin-iteration
- Active round: 0002
- Decision maker: main session（claude-opus-5[1m]）；方案 A（强制等宽）由用户 2026-08-12 裁定
- Timestamp: 2026-08-13

## Reason

**`Accepted: yes`。** `goal.md` 的七条验收标准逐条满足，且**硬判据全部由主会话独立复跑**：

1. **破坏性反证先看到红** —— 三处守卫各拆一次，**注入均先验证命中**（上一轮我有一次
   注入命中 0 处、差点把假绿当通过，这次先验注入再看红），PASS 数掉到 9/8/9。
2. **主会话独立复跑** —— unit 1359/0/2、**integration 7/0**、自建 10 例探针 10/10。
3. **端到端** —— 真派 grok，vendor 原样回出含两个字面量竖线的完整串与尾标记。
4. **用安装的那一份复验** —— 从 `~/.claude/plugins/cache/agent-hopper/hopper/0.56.0/`
   导入 `queue.js`，三条判据全过、真实 queue 解析 100 条。
5. **版本 bump** —— 0.56.0，位置由发现式守卫枚举而非清单。
6. **异构评审** —— codex T-106 判 REWORK，返工（见下方保留项）。
7. **记入 validation-log** —— 已记。

判 `positive` 而非 `negative`：`feedback-policy.md` 的 `negative` 要求
「评审判 REWORK **且未收敛**」。本轮 REWORK 的四条发现**全部复现、全部修掉、
并各配反证**，属已收敛。

## 返工后未再评审（必须留痕的一条）

**T-106 审的是返工前的代码；返工后的最终形态没有再派任何评审就发布了。**

同一情形在 v0.55.0 那次的处置是**补派 T-103 确认审再推**。本轮没有——用户在验证
结果呈报后直接裁定「推」，主会话据此执行。

**这不是流程等价物**：主会话的自验（3 处反证 + 10 例探针 + 两套测试 + 安装产物
+ 端到端）覆盖面很宽，但它**不是独立第三方**。如实记此一笔，不粉饰为「已评审」。

**处置建议**：补派一轮确认审。若发现问题，按 0.55.x 的先例开跟进轮修复，不回滚。

## Main-Session Decision On Scope Boundary

1. **删除外层 `.hopper/queue.md` 的残行** —— 新守卫使该行让整个文件解析失败。
   按 scope-lock 红线「**改的是那些行，不是判据**」删行、未放宽守卫。
   复验：解析 100 条、0 行无 id，与文件行数对得上，**无任务被少解析**。
2. **迁移插件自带夹具 18 行** —— 属 scope-lock 未预见的必要动作（`.hopper/queue.md`
   不在 Allowed Changes 表内）。**范围扩张，此处明记**。只改夹具，
   `tests/integration/real-fixtures.test.js` 一字未改（已核 `git diff --stat` 为 0）。
3. **顺带修 ISSUES.md 计数** —— `prompt-artifact-lifecycle-and-windows-permissions`
   正文状态是 open 却被列在 Closed。**这条 grok 在 T-103 就提过，我当时判「既存不动」**；
   本轮它造成了实际计数错误，遂修。实现方**先读正文确认再改**，未照我给的数字盲改。
4. **BREAKING 的取舍由用户裁定** —— 主会话给了 A/B 两案与代价，用户选 A。
   代价已精确到行呈报后才裁。

## Human Decision Required

- **无阻断项。** 但上方「返工后未再评审」的补审建议待用户定。

## Open Questions Resolved

- **列数校验能不能堵住静默错位** → **不能完全堵住**。允许省略末尾列时，
  「等宽抵消」使 6-cell 意图 + 一个杂散竖线恰好落在 7 格，**与合法行不可分辨**。
  强制等宽消灭了合法 6-cell 行这一人群，把洞收窄到**会自曝的角落**——
  但这是「收窄」不是「归零」，CHANGELOG 按此精度写。
- **一行不合规该不该让整个文件失败** → **有内容的行：该**（忽略它可能改变依赖图、
  状态或目标任务）；**全空占位行：不该**（不承载数据，旧行为本来也忽略）。
  评审的论证比主会话的原判更强：问题不是「严格 vs 宽松」，是**武断**——
  同样全空，仅因竖线数量不同而区别对待。
- **短内容行要不要自动补空 cell** → **不要**。无法可靠区分「漏了末尾 Vendor」
  与「漏了中间 Depends」。

## Open Questions Remaining

- **返工后的最终形态未经独立评审**（见上）。
- **缺陷 ⑤**（结构性正文冒充有效 spec）未修，留独立轮；`composePrompt` 无空 spec
  纵深防御同族。
- **`npm test` 不含 integration 的盲区是流程性的** —— 本轮已实证它能藏住产品失败。
  是否该把 integration 纳入常规复核，或在 scope-lock 模板里固定要求两套都跑，未决。
