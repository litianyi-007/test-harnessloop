# Decision

- Feedback: negative
- Blocker type: none
- Recovery eligible: yes
- Accepted: no
- Review: .harnessloop/goals/20260716-001-setup-wizard/rounds/0001/reviews/adversarial-review.md
- Reviewer: independent adversarial design-review subagent via main session (handoff 0001-02)
- Review verdict: rework
- Review digest: 7c177d889f663370d59ab6fb71b6e785671ab466eb3990655fe5268d39d1b386
- Active goal: 20260716-001-setup-wizard
- Active round: 0001
- Decision maker: main session（claude-fable-5）
- Timestamp: 2026-07-16

## Reason

设计轮（round 0001）产出的 706 行设计稿经独立对抗性评审判定 negative：3 处必须修复项——M1（continue/loop 门语义与"每步可跳过"承诺自相矛盾，实测锁死本项目自身的 continue，且字面 `TODO (owner: user)` 值可零成本刷穿完整度门）、M2（cost-context-policy 模板同名标签在无小节作用域约束下使 §4.3 29 槽位判定算法不可无歧义求值）、M3（lite 档 Evidence contract revision 条款与 harnessloop-evidence SKILL 的强制人工确认硬约束冲突）；另有 10 项建议修复（S1-S10）。8 条 acceptance criteria 判定 5 covered / 3 partial / 0 missing，三个 partial 均收敛为 M1、M2 两处设计文本缺陷，可最小修复，不需要推翻五步架构、check_setup 接口或接线方案。故障定位为本轮执行故障（设计文本本身的缺陷），非 goal 定义或业务假设错误——goal.md 的 8 条 acceptance criteria 与 non-goals 均未被评审证伪。

## Main-Session Decision On Fix Direction

- M1：采用双层门方案——check_setup 增加 `gate_blocking` 判定：仅当 environment.md / control-contract.md / cost-context-policy.md 等核心文件任一处于 template 或 missing 时才阻断 continue；partial 且 self-check.md 有对应 `TODO (owner: user)` 记录时降级为警告，不阻断；TODO 字段计入 `todo_count`，由 status 显性呈现，消除静默刷门通道。
- M2：§4.3 判定算法补充按小节容器路径（如 `Model Policy > Codex > Adversarial review`）的作用域匹配规则，替代裸标签匹配。
- M3：lite 档 Evidence contract revision 条款对齐 harnessloop-evidence SKILL:31/:49 的硬性人工确认约束（该约束不可通过档位关闭）。
- S1–S10：全部采纳，随 M1-M3 一并并入设计修订。

## Open Questions Resolved

- goal.md 行号勘误：待设计修订时一并订正
- 本项目 .harnessloop/setup/data-sources.md 的 External Tools 哨兵行缺失：由用户 live 首跑 wizard 时补齐，非本轮设计修订的阻塞项
- lite 档具体取值的最终措辞：待用户验收确认（goal.md Required Human Decisions 已列）
- profiles 引用行 + init:35 + codex defaultPrompt 同步方案：已获批准，随实现轮落地
- 漂移检测（drift detection）：延后，非本 goal 范围
- provenance 回填：不做
- 插件版本号 bump 至 0.11.0：已获批准

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E1 | .harnessloop/goals/20260716-001-setup-wizard/rounds/0001/reviews/adversarial-review.md | negative 判定的直接依据：M1-M3 必须修复项、S1-S10 建议修复项、8 条 AC 逐条判定（covered 5/partial 3/missing 0） |
| E2 | .harnessloop/goals/20260716-001-setup-wizard/rounds/0001/evidence/dynamic/setup-wizard-design.md | 被评审的设计稿原文，M1-M3 引用行号均指向此文件 |
| E3 | verify_protocol.py 输出（exit=1，6 条 dangling-citation，全部误报） | 机械门结果；6 条误报判定不影响本轮 negative 决策有效性（详见 round-summary.md Mechanical Gate 节、evolution issue TH-0006） |
| E4 | round_cost.py 输出（见 round-summary.md Cost 节） | 本轮成本记账留痕 |

## Next Action

- Action type: minimal-fix
- Scope-lock required: yes（round 0002 新 scope-lock）
- Human confirmation required: no（修复方向已由主会话拍板；档位默认值最终措辞待用户验收确认，但不阻塞开修订轮）
- Safe without user input: yes
- Recovery round objective: 按本决定的修复方向修订设计稿至可实现状态（M1 双层门方案、M2 小节作用域匹配、M3 lite 档对齐 evidence SKILL 硬约束，S1-S10 全部采纳），另存为 rounds/0002/evidence/dynamic/setup-wizard-design-v2.md（不改 0001 原稿，保留审计链）
- Disallowed until confirmed: 实现轮（round 0003 及以后）不得开工，直至 design-v2 的独立复审结论为 positive
