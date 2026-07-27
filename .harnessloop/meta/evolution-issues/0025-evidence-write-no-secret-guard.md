# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0025
- Priority: P2
- Issue class: security
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**evidence 自动写入无插件层 secret 守门**——自主化 runtime evals 会放大已发生过事故的那条链。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: 无
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

harnessloop 自身应对 evidence 写入提供最低限度的凭证守门或显式告警，使换一个项目使用时该防线仍在。

## Actual Harnessloop Behavior

`docs/security-incident-20260726.md` §2：泄漏路径正是「探针子代理把真实运行配置原样写进 evidence → vendor 原始日志回显 → public 仓」。插件树内无任何 secret 扫描/脱敏实现；本项目的三层守门是 test-harnessloop 仓的脚本（`scripts/check-secrets.sh`），不随插件走。**注**：事故档案 §7 建议 1 指向 hopper vendor 日志写端，与本条（harnessloop evidence 写端）相邻但不同链。

## Minimal Reproduction From Files

1. Read `docs/security-incident-20260726.md` §2
2. `grep -ril 'secret\|redact' harnessloop/plugins/` → 无扫描器实现
3. 观察：`scripts/check-secrets.sh` 在被测项目仓内，非插件能力

## Proposed Direction

最低限度：setup 自检对「未装 evidence secret 守门」给显式 warning。进一步：evidence 写入纪律进协议 + 机械抽查（对 channel-params 已登记值做 L1 摘要比对——摘要不含明文，本项目已验证该做法可行）。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。
