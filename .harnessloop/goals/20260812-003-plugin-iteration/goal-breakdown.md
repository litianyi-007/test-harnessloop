# Goal Breakdown

## Long-Term Goal

三个自研插件（harnessloop / hopper / kata）在真实使用中不再静默失败，
每条缺陷都有「发现 → 修 → 重装 → 复验」的完整证据链。

## Read-Only Discovery Plan

本 goal **不做前置调研轮**。缺陷来源是 goal 002 的真实使用现场，不是主动扫描——
主动扫描出来的问题往往是「构造得出来但用不到」的，与本 goal 的判据（静默失败）不符。

唯一的只读盘点：每轮开始前用 `scripts/plugin-status.sh all` 确认三个 submodule
**没落后上游**。这一步不是形式——2026-07-28 实测 hopper 落后 65 个提交无人察觉，
在陈旧基线上做完的一整版改动全部作废。

## Discovery Handoffs

| Handoff | Purpose | Inputs | Output path | Status |
| --- | --- | --- | --- | --- |
| （无） | 本 goal 不做前置调研 | — | — | n/a |

## Subgoals

| ID | Subgoal | Depends on | Evidence required | Validation method | Risk |
| --- | --- | --- | --- | --- | --- |
| PG-1 | **建立静默失败的判定与计数** —— 明确什么算一次静默失败，谁来判，怎么记 | — | 判定标准写入本文件；首次判定的实例记录 | 拿已知的五个实例（见下）回测该标准，能否全部判中 | 标准过宽会让计数永不清零；过窄会漏掉真缺陷 |
| PG-2 | **hopper 剩余 open issue 收敛** | PG-1 | 每条的修复或「不修 + 理由」 | 各条自带的破坏性反证 + 端到端 | hopper 的 open 已达 10 条，一次性做完会失焦 |
| PG-3 | **harnessloop evolution issue 收敛** | PG-1 | TH-xxxx 逐条处置 | `verify_protocol.py` + 破坏性反证 | 部分条目需改协议文本，影响面大 |
| PG-4 | **kata 的真实使用与验证** | — | kata 被实际调用的记录 | 产出可用 + 缺陷登记 | **kata 长期调用不足**——rounds/0011–0012 期间调用 0 次，「不用就等于不验」 |
| PG-5 | **把已确认的守卫缺口补成发现式守卫** | PG-1 | 每条守卫的红/绿反证 | 拆掉守卫必须变红 | 守卫本身可能空过（见「防空扫也绿」） |

## Tasks

| ID | Task | Parent subgoal | Scope boundary | Evidence required | Validation method |
| --- | --- | --- | --- | --- | --- |
| PT-1 | 把「静默失败」的判定标准写死，并用下方五个已知实例回测 | PG-1 | 只写标准与回测，不修代码 | 回测结果逐条 | 五个实例须全部被判中 |
| PT-2 | kata：把工程侧知识沉淀走通一次完整闭环并记录插件问题 | PG-4 | 只用不改；发现问题另开任务 | wiki 页 + 使用中暴露的问题 | 产出可用且沉淀判据符合 CLAUDE.md |
| PT-3 | `package-lock` 那类守卫缺口的横向排查（三插件各查一遍） | PG-5 | 只排查与登记，修法另议 | 各插件的「清单 vs 发现式」现状 | 每条结论须有 file:line |

## 已知的「静默失败」实例（PG-1 的回测集，2026-08-12 一轮内暴露）

**五个都属同一形状：「看起来有内容」被当成了「真的承载了任务」。**

| # | 实例 | 插件 | 状态 |
|---|---|---|---|
| ① | `loadTaskSpec` 无条目时返回自述文案冒充 spec，文案还写着「using queue.md brief only」而 brief 根本没进 prompt | hopper | 已修 0.55.0 |
| ② | 裸 marker（`## T-1` 光标题没正文）非空，通过 `section.length > 0` 的 fail-closed 判据 | hopper | 已修 0.55.0 |
| ③ | section-END 检测比 section-START 窄，粗体/表格行形态的后继任务从不构成边界 → **T-1 拿到 T-2 的正文** | hopper | 已修 0.55.0 |
| ④ | `queue.js` 列解析按下标静默取值；brief 内未转义的 `\|` 截断 brief 并顶掉 Vendor 列，竖线后若恰为已批准 vendor 名则**完全无声** | hopper | 登记未修 |
| ⑤ | 正文只有结构性标记（`---` 等）仍被当有效 spec | hopper | 登记未修 |

**另有一族「清单 vs 发现式守卫」，同日暴露两例**：README 版本徽章停在 0.50.0 落后 4 个版本
（无守卫覆盖，已补）、`package-lock.json` 停在 0.50.0 落后 5 个版本（**明明写在清单里**，
无守卫覆盖，已补 `version-discovery.test.js`）。

## Main-Session Decision

- **三插件合一而非拆三个 goal**（user-confirmed 2026-08-12）：失效形状同源，拆开会让
  「跨插件的共同教训」无处落脚。某插件重到需要独立节奏时再 `split`。
- **前史轮次留在原处只做交叉引用**（user-confirmed 2026-08-12）：rounds/0013 与 0017
  的路径已被大量文件引用，迁移会全部打断，而「保留可追溯」是协议明写的安全规则。
- **不设前置调研轮**：本 goal 的缺陷来源必须是真实使用，主动扫描出的问题不符合判据。
- **PG-4（kata）优先级被主会话上调**：它是三插件里**唯一长期缺乏真实调用**的一个，
  「不用就等于不验」——它的风险不是缺陷多，是**根本没被验过**。
