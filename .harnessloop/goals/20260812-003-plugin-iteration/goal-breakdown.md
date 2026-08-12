# Goal Breakdown

## Long-Term Goal

三个自研插件在真实使用中坏了就修，每次修都走完整闭环。**常设，无终态。**

## Read-Only Discovery Plan

**不做前置调研轮。** 缺陷来源是 goal 002 的真实使用现场。

唯一的只读前置：动手前用 `scripts/plugin-status.sh all` 确认三个 submodule
**没落后上游**。这一步不是形式——2026-07-28 实测 hopper 落后 65 个提交无人察觉，
在陈旧基线上做完的一整版改动全部作废。

## Discovery Handoffs

| Handoff | Purpose | Inputs | Output path | Status |
| --- | --- | --- | --- | --- |
| （无） | 本 goal 不做前置调研 | — | — | n/a |

## Subgoals

**初版的 PG-1..PG-5 五个子目标已随简化作废**（PG-1 被两家评审判为「不该是独立计数轮」，
其余建立在已作废的计数框架上）。简单形式下不预设子目标——**缺陷暴露一条，开一轮修一条。**

下面是**已登记未修的缺陷清单**，不是子目标，没有先后依赖，按暴露顺序与严重度自然排序：

| ID | Subgoal | Depends on | Evidence required | Validation method | Risk |
| --- | --- | --- | --- | --- | --- |
| （无预设子目标） | 见下方待修清单 | — | 逐条按 `goal.md` 的七条验收标准 | 同左 | — |

## Tasks

| ID | Task | Parent subgoal | Scope boundary | Evidence required | Validation method |
| --- | --- | --- | --- | --- | --- |
| （无预设任务） | 见下方待修清单 | — | — | — | — |

## 待修清单（登记未修，2026-08-12）

**hopper**（`hopper-plugin/docs/archive/ISSUES.md`，open 10 条，以下为本项目直接撞到的）：

| # | 缺陷 | 严重度 |
|---|---|---|
| ④ | `queue.js` 列解析按下标静默取值；brief 内未转义的 `\|` 截断 brief 并顶掉 Vendor 列，竖线后若恰为已批准 vendor 名则**完全无声地派出半份任务书** | 中高 |
| ⑤ | 正文只有结构性标记（`---` 等）仍被当有效 spec | 低 |
| — | `composePrompt` 对空/纯空白 taskSpec 无纵深防御（`tasks.js:169`，该文件被 4 条逐字节断言锁死） | 低 |
| — | Closed 索引里 `prompt-artifact-lifecycle-and-windows-permissions` 一行状态文字仍写着 open（既存文档漂移） | 低 |

**harnessloop**：TH-0032（隔离实例凭证落盘无清理，副本随轮次线性累积）、
TH-0031，及 `evolution-issues/` 其余未闭条目。

**kata**：**无登记缺陷，但也几乎没被真实调用过**（rounds/0011–0012 期间 0 次）。
风险不是缺陷多，是**根本没被验过**。2026-08-12 已走通一次工程侧沉淀
（`~/.llm-wiki/test-harnessloop/lessons/non-empty-is-not-meaningful.md`），
使用中未暴露问题——**这条如实记为「用了一次没发现问题」，不是「验证通过」**。

**本项目自己的工具**（不属三插件，但同族）：`package-lock.json` 那类
「清单 vs 发现式守卫」缺口，需在三插件各查一遍。

## 「静默失败」这个概念的处置

初版把它当成可计数的验收指标，**已作废**。但它作为**描述工具**仍然有用——
本项目绝大多数插件缺陷都是这个形状：**功能没达成，而所有可观测通道都在说「成了」**。

两家评审对它的两点修正值得保留，供以后描述缺陷时参考：

1. **codex 指出原定义里有量词冲突**：「**所有**可见信号都显示成功」与
   「有没有**一个**绿灯在说谎」不是同一标准。更准的顶层表述是
   **「约定的后置条件未成立，而端到端决策仍被记录为成功」**。
2. **两个子族要分开编码**：`producer-silent`（工具没发出该发的失败信号）与
   `consumer-silent`（信号发了，有读取义务的消费方没读）。**修法完全不同**——
   前者修插件，后者改消费纪律。

**不再用它计数**，所以不需要判定标准的可证伪性——那正是初版把简单概念做复杂的地方。

## Main-Session Decision

- **简化是用户 2026-08-12 的裁定**，触发是双路评审判 REWORK。
- **`Active goal` 交还 002**：002 是使用现场，插件缺陷从那里暴露。
  「插件优先」以规则保留（缺陷一暴露就中断 app 工作先修），既执行裁定又不掐断样本源。
- **rounds/0001 判 neutral、不计任何数**，其唯一有效产出是那份把初版设计否掉的评审。
- **不为简化而销毁证据**：初版的 goal 文件由本次重写覆盖，但 rounds/0001 全部产物
  （scope-lock、预登记、评审）原样保留——**否则就没人知道这个 goal 为什么长这样。**
