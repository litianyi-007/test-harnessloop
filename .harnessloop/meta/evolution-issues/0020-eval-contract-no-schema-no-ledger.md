# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0020
- Priority: P1
- Issue class: missing-capability
- Status: resolved (需求链闭合，v0.27.0–v0.35.0)
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**runtime eval 契约有列名、无 schema、无结果账本**：thresholds 三表列名已接近 eval 契约形状，但无稳定 ID、无机器可读结果、无 attempt/freshness/cleanup 绑定。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0019（系统载体）、TH-0022（授权联结）、TH-0024（due-set）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

每条 threshold 有稳定 ID；每轮产出机器可读的 eval 结果账本，字段至少含 threshold-id、ran/pass/fail、round/attempt id、起止时间、threshold digest、plan digest、系统绑定指纹（无 secret）、executor/provenance、command digest、evidence digest、freshness 评估、cleanup 状态。多系统 eval 可表达依赖 DAG、并发组、资源锁与组合结果语义。

## Actual Harnessloop Behavior

`thresholds-template.md` 三表无 ID、Runtime 表无 due 字段；本项目实例 `goals/20260718-002-agent-app/thresholds.md` 已被真实 runtime eval 声明填满而机器从未读过；工作区不存在任何 eval 结果文件。无 DAG/并发/锁语义（T-075 M-2）；无 attempt/freshness/config 快照绑定，上轮 pass 可被复制（M-3）；cleanup 只有预授权计划、无 acceptance outcome，探针可 pass 而遗留测试资源（M-4）。

## Minimal Reproduction From Files

1. Read `harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/thresholds-template.md`
2. Read `.harnessloop/goals/20260718-002-agent-app/thresholds.md`（Runtime 表已填满）
3. `find .harnessloop -name 'eval-result*'` → 空

## Proposed Direction

先定结果账本 schema（含 M-2 DAG/并发/锁、M-3 attempt+freshness+config 指纹、M-4 cleanup outcome），再给 threshold 行加稳定 ID。散文表保留为人读视图。cycle 判 `contract-insufficient`。带写 eval 的 positive 须同时要求 cleanup=pass，或引用有期限的 retention 授权（到期变硬义务）。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。


---

## 需求链闭合（2026-07-29，harnessloop v0.35.0，CI 三平台全绿）

用户需求一句话：**配置链接外部系统 → 补充 runtime/多系统测试作为 evals → loop 尽可能自主 →
安全达成 goal**。按此逐环对照实际代码，六环现已全部落地：

| 环 | 版本 | 机制 |
|---|---|---|
| ① 声明外部系统 | v0.34.0 | `setup/external-systems.json`（schema 里**没有任何 URL/主机/路径形状字段**） |
| ② eval 绑定系统 | v0.34.0 | `evals.json` 的 `system` + 今天层引用完整性 |
| ③ eval 引用运行产物 | **v0.35.0** | 账本 `evidence` 恒必填；`pass` 时不得为 null；须在本轮 `evidence/` 下且叶子是普通文件 |
| ④ 结果入账 | v0.27.0 | `acceptance-evals.json` |
| ⑤ 到期未过 ⇒ 不得 positive | v0.27.0 | `acceptance-eval-positive-without-pass`（三操作数同轮） |
| ⑥ 声明跑了却没账本 ⇒ 红 | v0.28.0 | `Acceptance evals: ran` + 八行判定表 |

**闭合的是「可审计链条」，不是「执行力」。** 门在结构上证明不了 eval 真跑过——③ 只证明
账本点名了一份存在于本轮 `evidence/` 下的普通文件，**伪造文件同样通过**（已钉成可执行断言
G38j）。它买到的是：每一次 eval 声称都留下**具名、可 diff、可被对抗评审质问**的记录。
**执行力在人和评审那里，不在退出码里**——与批 2 §1.2 的诚实声明同源。
