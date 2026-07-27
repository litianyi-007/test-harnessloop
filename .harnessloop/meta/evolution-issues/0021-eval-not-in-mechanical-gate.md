# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0021
- Priority: P1
- Issue class: false-green
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**判定链在 eval↔机械门处断裂**：decision.md 无 eval 字段、`verify_protocol.py` 对 eval 零感知，「声明了没跑」与「跑了改判据」两类假绿在机械层不可见。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0019/TH-0020（载体前置）、TH-0024（**硬前置**，无权威 due-set 则「缺 ran 不得 positive」不可计算）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

已声明且本轮到期的 eval 未跑或未过 → 该轮不得判 positive，机械门可见可拒（用户裁决①：evals = 硬门）。

## Actual Harnessloop Behavior

`decision-template.md` 无任何 eval/threshold 结果字段；`verify_protocol.py` 全文 grep `eval` 仅 2 处无关命中（PATHISH 前缀 :310、英文 evaluated :1647）；loop SKILL.md:442 把 thresholds 划在模型判断层；Loop Continuation step 1 的唯一机械否决是 verify_protocol exit 非零。thresholds.md 在 goal 目录，连 Rule A 都看不见同轮改判据。

## Minimal Reproduction From Files

1. Read `references/decision-template.md` → 无 eval 字段
2. `grep -c eval .../verify_protocol.py` → 2（均无关）
3. 观察：声明了 runtime threshold 的轮次仍可 exit 0 并判 positive

## Proposed Direction

decision.md 增 `Evals:` 字段 + 机械门核对（字段存在、路径 containment、账本 schema 合法、本轮 due 的 threshold-id 全部 ran、pass/fail 与 Feedback 一致）；thresholds 内容摘要进 coverage 防同轮改判据。**分步按裁决 C.1-B**：D0 shadow（schema+ID+due-set+eval_gate_version，无门）→ per-goal 显式激活清单（每 threshold 标 due/future/retired/historical + activation_round）→ 激活后 **D2 全硬门**（ran 完整性与 pass/fail 一致性同次生效）。新 goal 默认激活，存量 opt-in，不追溯改判旧轮。**不走「先入账后硬门」**（该路径已撤回：入账若允许自由 `none` 逃逸，等于给假绿开协议背书的出口）。机械门是**账本核对器，不是 test runner**（`verify_protocol.py` 从不执行业务命令，此为设计边界）。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。
