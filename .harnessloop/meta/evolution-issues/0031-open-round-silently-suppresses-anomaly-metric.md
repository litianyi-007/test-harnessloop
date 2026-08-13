# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0031
- Priority: P3
- Issue class: mechanical-gate / observability
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（现场观测，2026-08-05 开 rounds/0011 时）
- Created at: 2026-08-05

**开一个新轮会让 `loop_anomaly_skipped_unparsable` 立刻下降,而下降与底层状况改善无关。** 指标读起来像「说不清的情况变少了」,实际只是「这个 goal 暂时不参与计数了」。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

2026-08-05 开 `goals/20260718-002-agent-app/rounds/0011` 时现场观测到:

| 时点 | `loop_anomaly_skipped_unparsable` |
|---|---|
| 开轮前(最新轮=0010,有 decision.md) | **2** |
| 写完 `rounds/0011/scope-lock.md` 后(最新轮=0011,无 decision.md) | **1** |

两次跑的都是 `verify_protocol.py --project .`,均 exit 0 / 零违规。期间**没有任何一条既有轮次的可判定性发生变化**——我只是新建了一个尚未收口的轮。

## Root Cause

`verify_protocol.py` 的 anomaly 评估按 **goal** 迭代,每个 goal 只看它的**最新一轮**:

```python
decision_text = _latest_round_decision_text(goal_dir, project)
if decision_text is None:
    # ... the latest one's decision.md is missing/unreadable --
    # nothing to evaluate for this goal, and not itself an
    # "unparsable precondition" ...
    continue
```

新轮开出来时只有 `scope-lock.md`、没有 `decision.md`,于是该 goal 被整体 `continue` 跳过:既不计入 `loop_autocontinue_anomaly`,也不计入 `loop_anomaly_skipped_unparsable`。本项目有 2 个 goal,原本两个各计 1;goal 002 一开新轮就退出计数,总数即 2→1。等 0011 收口写出 `decision.md`,goal 002 会重新被评估,数字大概率回到 2。

**跳过本身是有道理的**——一个还没收口的轮确实没有 feedback 可判,把它算成「说不清」会制造假信号。有问题的不是这个 `continue`,而是**它对外表现为计数下降**。

## Why It Matters

这个指标的设计意图,代码注释自己写得很清楚:

> making "this could not be judged" visible rather than silently collapsing into an ordinary zero.

即它存在的全部理由是**不让「无法判定」塌缩成一个普通的 0**。但当前实现里,开新轮恰好就把某个 goal 的「无法判定」塌缩成了「不计数」,和它要防的那件事同形——只不过触发条件从「解析失败」换成了「轮次进行中」。

危害面窄但真实:
- 指标**在轮次生命周期内周期性抖动**(开轮降、收口升),不是单调的健康信号。
- 有人拿它做趋势观察时,「2→1」会被读成进展;**做出这个下降的动作恰恰是「开始了新工作」,而不是「解决了旧问题」**。
- 该字段没有任何 violation 与之配套(按 §4.2 设计就是观察信号而非硬门),所以没有第二条线索能戳破这个误读。

## Repro

1. 任取一个有 ≥2 个 goal、且 `loop_anomaly_skipped_unparsable ≥ 1` 的项目,跑 `verify_protocol.py --project . --json`,记下该值。
2. 在其中一个**当前贡献了计数**的 goal 下新建一个轮目录,只放 `scope-lock.md`,**不放 `decision.md`**。
3. 重跑同一命令。该值下降 1,violations 仍为 0,exit 仍为 0。
4. 给新轮补上 `decision.md`(feedback 可判定即可),重跑,该值回升。

## Candidate Fixes

未定,列可能方向供后续裁决:

- **A. 分离计数**:新增 `loop_anomaly_rounds_in_progress`(或类似),把「最新轮未收口」这一类从「不计数」改成「计入另一个明确的桶」。总量守恒,读者能一眼看出下降来自哪。
- **B. 回退到上一收口轮**:goal 的最新轮未收口时,改判它的**上一个已收口轮**,使指标在轮次生命周期内稳定。代价是语义从「最新轮」变成「最新已收口轮」,需同步文档。
- **C. 只改文档**:在字段说明里写明「进行中的轮不参与计数,故该值会随开轮下降」。成本最低,但把责任推给读者,与本项目「发现式守卫优于人工记忆」的一贯取向相反。

倾向 A——它保住了「跳过未收口轮」的正确性,同时不让这个正确性表现为一个会误导的下降。

## Notes

- 本条是**观测记录,不是阻断项**:P3,不挡 rounds/0011 推进。
- 与 TH-0011(`zero_inspected` 盲绿)、TH-0026(scope-lock 误写路径致静默零覆盖)同族:**门是绿的,数字是好看的,而好看的原因不是它看起来的那个原因**。

## 后记（2026-08-05，rounds/0011 收口后）

上文「Root Cause」末尾预测「等 0011 收口写出 `decision.md`，goal 002 会重新被评估，数字大概率回到 2」。**实测没回到 2，仍是 1。**

原因：0011 收成 **`Feedback: negative`**（对抗审 REWORK）。带 decision.md 后 goal 002 确实重新进入评估，但 `condition_positive` 为假 → `_kleene_and` 结果是**确定的 False**（不是 `None`），于是既不计入 `loop_autocontinue_anomaly`，也不计入 `loop_anomaly_skipped_unparsable`。

**本 issue 的核心论点不受影响**（开一个未收口的轮会让该 goal 退出计数，且下降与底层状况改善无关）；受影响的只是那句预测——它隐含了「收成 positive」这个未言明的前提。记在这里，因为一条没兑现的预测如果不写下来，下次读这份 issue 的人会以为它已被实测确认过。

顺带得到一个原文没覆盖的观察：**该指标为 0 至少有三种成因**——(a) 真的没有无法判定的条件；(b) 最新轮未收口，整个 goal 被跳过；(c) 最新轮收成非 positive，条件确定为假。三者在输出上完全不可区分。这加强了候选修复 **A（分离计数）**：不区分这三种「0」，读者就无法判断一个 0 意味着健康、意味着进行中、还是意味着刚失败过。
