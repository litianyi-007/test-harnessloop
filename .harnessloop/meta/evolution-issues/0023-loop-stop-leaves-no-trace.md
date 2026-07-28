# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0023
- Priority: P2
- Issue class: missing-teeth
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**loop 停止不落痕**：协议明文要求单会话多轮自续，但任何偏离都不留痕迹、不被标红——偏离零成本，实践 14/14 轮漂向每轮停。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0017（环境自检 pass 语义影响 auto-continue 条件）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

loop 停止时必须留下机器可读的停止记录（原因 ∈ 枚举 + 对应哪条 Stop 条件）；「用户主动打断」与「上下文/成本 checkpoint」是**合法且显式**的枚举值，而非静默逃逸。自续词汇按 control-contract 档位分层。

## Actual Harnessloop Behavior

loop SKILL.md:556 step 6 要求 positive 且 goal 未达成即续；:560-567 「Stop only when」六条穷举**不含**「等用户敲 continue」。但协议无任何停止记录机制：decision.md 无 stop-reason 字段、self-audit 确定性信号清单不含停止事件、coverage 无停止计数。实践：goal 001 的 4 轮 + goal 002 的 10 轮，14/14 由人工推进。另：strict 档明文禁止连续无人轮（`control-contract-profiles.md:9,:60`），与自续主线冲突但报告未分层。

## Minimal Reproduction From Files

1. Read loop SKILL.md:556 与 :560-567
2. `grep -rn 'stop' references/decision-template.md` → 无停止原因字段
3. 观察 `.harnessloop/state/current.md` 的 Next proposed action 一律以「下一 continue 开 SG-X」收尾

## Proposed Direction

①停止落痕（枚举含 goal-achieved / missing-human-input / missing-access / write-safety / contract-unsatisfiable / threshold-unevaluable / **open-handoff-blocking** / **budget-checkpoint** / **user-interrupt**）；②control-contract 增 round 预算词汇（连续自续轮数/成本上限，到点即合法 checkpoint 停）——预算信号接 `round_cost.py` 既有结算链，但须承认其观测质量（本项目 14 轮中多数 cost 字段 unavailable）；③按档位分层：lite/standard 可自续、strict 保持逐 checkpoint 人闸；④continue 输入契约措辞收窄为重入/救援。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。


---

## 2026-07-28 状态更新：规格三轮对抗审后触发收敛守卫，停在 v3 待用户裁决

规格 `docs/loop-stop-record-spec-20260728.md` 经 v1→v2→v3 三版、三轮异构对抗审
（T-076 codex / T-077 codex / T-078 grok），**全部判 REWORK**，收敛守卫触发。

**与上次守卫触发（ignore 收窄）的关键差别**：那次三轮指向「层次错了」；这次
T-078 明确判定「收窄方向是**进步**」且「**方向不应放弃**——harnessloop 应当解决
可审计层」。三轮是依次收敛的三个不同缺陷（太松 → 太满 → 方向对但接线未闭合），
不是同形复发。

**停在 v3，不进入实现。** 待用户在两个选项间裁决（详见规格附录 A.4）：
(A) 接受五条最小接线补丁出 v3.1 后实现；(B) 降级为纯观测字段、砍掉执行力声称。

**本轮最有价值的两条认识**（无论最终选哪个都成立）：
1. 「agent 自签且控制所有输入」是**层次问题**——机械门能验证结构关系（successor
   存在/前向/无环/双向绑定），不能验证动机（为什么停）。再加同层检查无效。
2. 一个**能被廉价满足的强制，只把成本加给诚实的人**——v2 要求每个停止理由「有支撑」，
   而支撑判据可被真实制造（真留一个 open handoff）或自引用满足。故 v3 取消该强制。
