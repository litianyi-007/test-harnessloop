# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0019
- Priority: P1
- Issue class: missing-capability
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**外部系统声明与执行层之间没有桥**：`setup/data-sources.md` 的 Runtime Validation Systems / External Tools 两表是自由文本，无任何代码解析其内容。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0021（本条是其载体前置）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

项目声明一个外部系统（endpoint、探活方法、测试资源边界、清理契约、凭证参数名）后，loop 应能据此机械探活、绑定本机地址、并在不可用时给出结构化 `unavailable` 事实。

## Actual Harnessloop Behavior

`data-sources-template.md:16-24` 两表全自由文本；`check_setup.py` 只查填充度；`init_project.py` 只落模板；`verify_protocol.py` 仅在 docstring 里把它当 PATHISH 前缀示例（:48、:2787）。`channels`/`connectivity` 在协议层要求 agent 读它，但同样无表格解析器。setup SKILL 明文把 data-sources 排除在 gate-blocking 之外。

## Minimal Reproduction From Files

1. Read `.harnessloop/setup/data-sources.md`
2. `grep -rn 'data-sources' harnessloop/plugins/harnessloop/skills/*/scripts/` → 仅 check_setup / init_project / verify_protocol docstring
3. 观察：无任何代码读取表格单元格

## Proposed Direction

独立 versioned JSON 声明 + gitignored 本机绑定（**控制面**仿 reference-roots：声明/绑定分离、每门重判 available、fail-closed、coverage 可见、不泄本机路径）；**探针执行器全新建**（method/timeout/TLS/鉴权/重试/副作用等级），不复用 `_exists_as`/`samefile`。不做全局 gate_blocking，改为「active due eval 绑定的系统未声明/不可用 → 违规」的条件阻塞；data-sources 表降为人读视图。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。
