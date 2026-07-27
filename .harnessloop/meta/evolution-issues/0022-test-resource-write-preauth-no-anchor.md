# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0022
- Priority: P2
- Issue class: contradiction
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**测试资源写预授权：blocker 定义留了缝，但契约无落点，且协议文本自相矛盾**。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0019（只有已声明系统可预授权）、TH-0020（cleanup outcome 进账本）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

已声明系统上的测试资源写与清理，可由 control-contract 结构化预授权（用户裁决③）；生产/不可逆写仍停人。协议文本对此应一致。

## Actual Harnessloop Behavior

三处互相矛盾：`harnessloop-continue/SKILL.md:46` 的 write-safety-required 定义是**条件式**（"without **declared** dry-run/**test-resource**/rollback/human confirmation"）；同文件 :36 step 9 **无条件**要求 external mutation 停人；`control-contract-template.md:25` 与 `control-contract-profiles.md:30` 三档（含 lite）均对外部写 required。唯一能容纳 Read/write scope 的是 data-sources 散文列（机器不读，见 TH-0019）。

## Minimal Reproduction From Files

1. Read `harnessloop-continue/SKILL.md:36` 与 `:46` → 无条件 vs 条件式
2. Read `references/control-contract-profiles.md:30` → 三档一致 required
3. 观察：无任何结构化落点可做出 :46 所说的那个 declared

## Proposed Direction

control-contract 增结构化预授权块（已声明系统 id × 操作类 {probe-read, test-resource-create, test-resource-delete, cleanup} × 资源域 × 清理契约 × 授权 ID）；与 TH-0019 联动（只有已声明系统可被预授权）；handoff 委派时须携带授权 ID 与资源域；修 continue :36/:46 矛盾（step 9 改为「未被契约预授权的外部写才停人」）。**实践先例**：本项目 `state/control-contract.md:22` 的 git push 例外条款证明该词汇能用、缺的是结构。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。
