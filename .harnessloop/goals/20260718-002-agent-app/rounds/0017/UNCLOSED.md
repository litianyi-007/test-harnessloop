# rounds/0017 未收盘 —— 有意如此，不是遗漏

**写于 2026-08-13**，在清点 goal 002 各轮时发现本目录**只有 `scope-lock.md`（自述是事后补录）
与 `evidence/`，没有 `decision.md`、没有 `round-summary.md`**。这份文件把这个状态说清楚，
**不补一份事后的 decision——那会把「从未按协议收过盘」伪装成「收过」。**

## 为什么不补 decision.md

`decision.md` 记的是**当时**的裁决：feedback 分类、是否 accepted、评审 digest、
决策人与时间戳。这一轮的工作是 `/plan` 驱动的，**从头到尾没有走开轮流程**——
`state/current.md` 的 active round 当时仍指着已收盘的 `rounds/0016`。
现在补写，每一个字段都只能是追认，**而追认的裁决和当时做出的裁决不是一回事**。

同样的理由，`scope-lock.md` 自己开头就写着「这一份是在工作**完成之后**写的，
**它不具备那个作用**，不能被当成『本轮受过范围约束』的证据」——那份补录是诚实的，
因为它把自己的性质标在了第一行。这份文件沿用同一种诚实。

## 那这一轮的内容在哪里

**全部有归属，没有丢失**：

| 内容 | 落点 |
|---|---|
| 缺陷本身与修复闭环 | `docs/validation-log.md` 的 **hopper 0.55.0** 条目 |
| 发现式版本守卫（守卫上岗第一件事是抓住了写它的人） | `docs/validation-log.md` 的 **hopper 0.55.1** 条目 |
| 设计评审裁决 | `evidence/design-review-T099-decision.md` |
| 主会话自己的破坏性反证 | `evidence/counterproof-main-session.txt` |
| 三轮异构评审原始产物 | `.hopper/handoffs/T-099 / T-100 / T-102 / T-103` |
| 代码与发版 | `hopper-plugin` submodule，已 push |

**这一轮的性质是插件轮而非 app 轮**——它挂在 app goal 下本就不贴切，
正是这一点促成了 2026-08-12 另立 `20260812-003-plugin-iteration`。

## 机械门为什么没报（查证后的准确说法）

`verify_protocol.py` 有一条 `eval-ledger-without-decision`（TH-0029 defect 2，
`verify_protocol.py:486-504`），但它**刻意是条件触发**：只在**该轮自己**有
`evidence/runtime/acceptance-evals.json` 台账、却没有 `decision.md` 时才报。
脚本文档原文明写「**This does not require every round to have a decision.md**」，
理由是保持 E1 既定的**零迁移极性**——不追溯审判早于这些文件的旧轮。

本轮没有 eval 台账，**因此按设计静默，属于锚点之外，不是漏网**。

**不要把这条记成「框架没有守卫」**——它有，只是锚在「有没有 eval 台账」上。
真正可讨论的问题是：锚点该不该从「有台账」放宽到「有 scope-lock 或 evidence」。
**要提这个，必须带着零迁移极性的答案去提**，否则会正面撞上它当初拒绝普遍要求的理由。
