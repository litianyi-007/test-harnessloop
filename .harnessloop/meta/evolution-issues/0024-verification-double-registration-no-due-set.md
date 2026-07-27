# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0024
- Priority: P1
- Issue class: contract-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**scope-lock 的 Verification commands 与 thresholds 双登记、无共同 ID、无权威 due-set**——硬门无法计算「本轮到期集合」。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0021（本条是其硬前置）、TH-0020（ID 与 schema 同源）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

「本轮到期的验证集合」应有唯一权威来源与稳定 ID，使机械门能判定「该跑的是否都跑了」。

## Actual Harnessloop Behavior

`scope-lock-template.md:21-24` 与 `thresholds-template.md:11-19` 都声明验证，无共同 ID、无优先级、无哪份为准。硬门若只读其一，另一份可漂移。本项目 goal 002 的 thresholds 混有历史/已完成/defer/未来批次/每轮规则五类行，无字段可区分。

## Minimal Reproduction From Files

1. Read `references/scope-lock-template.md:21-24` 与 `references/thresholds-template.md:11-19`
2. Read `.harnessloop/goals/20260718-002-agent-app/thresholds.md` → 五类行混在一起，无 due 字段

## Proposed Direction

定义单一权威 due-set 来源与稳定 ID；每 threshold 行可标 `due | future | retired | historical` 与 `activation_round`；scope-lock 的 Verification 列改为引用 threshold ID（或明确其为该轮 due-set 的子集声明）。**这是 TH-0021 的硬前置**（T-075 裁定）。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。
