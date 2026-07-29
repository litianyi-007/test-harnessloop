# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0029
- Priority: P0
- Issue class: mechanical-gate / false-green
- Status: open
- Created by: 主会话（由 exp-p1/exp-p2 配对实验的 grok 评审发现）
- Created at: 2026-07-29
- 影响版本: v0.27.0 起，**v0.36.0 仍活着**

**RAE 旗舰硬规则有两条总开关，均已在 v0.36.0 上实测复现。**

## 发现来源（值得记）

不是自查发现的，是**评审价值配对实验的副产品**。两条分别来自：

- **A 臂（最小自动合成 brief）与 B 臂（21 行手写 brief）各自独立**报出全角冒号那条；
- **仅 B 臂**报出 decision.md 缺席那条，A 臂对该提交判 all-PASS。

## 缺陷 1：全角冒号在**标签侧** ⇒ 规则静默

```
- Feedback: positive   → acceptance-eval-positive-without-pass  ✅ 触发
- Feedback：positive   → 无                                      ❌ 静默
```

（账本相同：`frozen_due_set:["RAE-0042"]` 且该 eval `outcome:"fail"`）

**这是同一族的第三个变种**：
1. v0.26.0 修「讨论 ignore 标记 == 启用它」（行内代码 span）
2. v0.29.0 修代码围栏藏 Feedback 行
3. **本条：标签分隔符本身**

根因：v0.29.0 修的是**值侧**归一（`positive。` → `unparsable`，fail-closed），
**从未处理标签侧的分隔符**。`- Feedback：positive` 压根匹配不上 `- <label>:` 前缀 →
被当成「字段缺席」→ 迁移静默 → 绿。

**教训与 v0.22.0、v0.32.0 同构**：**teeth 防的是回归，防不住把同一个错犯在同族的新位置。**
本仓 decision.md 大量使用中文全角标点，这不是理论构造。

## 缺陷 2：`decision.md` 整个缺席 ⇒ 全部静默

```
有 decision.md（Feedback: positive）+ fail 账本 → 判红 ✅
无 decision.md                      + fail 账本 → 零违规 ❌
```

**删掉 decision.md 就是 RAE 硬规则的总开关。** 同时也让 E4、B2a、两条 acceptance-eval
declaration 检查对该轮整体失声——这一点 TH-0027 的第 ⑥ 类已登记过，
**但当时没意识到它同时是旗舰硬规则的旁路**。

## 共同形状

两条都是「**被守门方持有开关**」（X1）。批 1 的五面设计曾 5/5 各自独立发现该属性，
TH-0025 的结论是「插件既不拥有数据、也不拥有时刻、更不拥有强制力」。本条是它在
旗舰规则上的第二次具体化。

## 处置方向（未实施，先记）

- **缺陷 1**：`- <label>:` 一族解析器的分隔符归一——**但要极其小心**：把全角冒号一律
  当半角会引入新的解析面。更稳的方向可能是**探测到全角分隔符即报
  `*-label-unparsable` 违规**（fail-closed，与值侧同极性），而不是宽容地接受它。
  **两种做法的取舍需要先想清楚，不要顺手选一个。**
- **缺陷 2**：`decision.md` 缺席时，若该轮存在账本，应报违规而非静默。
  注意别做成「所有轮必须有 decision.md」——那会追溯判红历史轮（撞 E1）。
  **条件应锚在「该轮有账本」这个轮内事实上**，保持操作数同轮。

**两条都必须配破坏性反证 fixture，并先在当前树上跑红。**
