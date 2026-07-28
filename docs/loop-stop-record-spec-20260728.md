# loop 停止落痕 + 轮次预算 + 档位分层 — 规格 v2（2026-07-28）

> **v2 起因 T-076 对抗审判 REWORK。** v1（commit `e9ed73c`）的致命缺陷已确认：
> **它的每一个停止值都是绿的**，且 v1 自己的 L5 明文要求裸 `continued` 直接通过——
> 于是 agent 可以实际停止、写 `continued`、保持 0 违规。v1 解决的是"字段有没有"，
> 不是"停止有没有真实落痕"。
>
> v2 的中心变化：**红灯不落在标签上，落在"没有可支撑的理由"上。**
>
> 授权：main-session ruling under user delegation 2026-07-28（审核报告附录 B）。
> 状态：规格草案，待第 2 轮异构对抗审。机械门在 v0.26.0。
> 收敛计数：本工作项已 1 轮 REWORK。

## 0. 先裁一条协议矛盾（v1 把它糊过去了）

T-076 用真实反例逼出这条：`.harnessloop/goals/20260716-001-setup-wizard/rounds/0001/decision.md`
是 `Feedback: negative` + `Blocker type: none` + `Human confirmation required: no` +
`Safe without user input: yes` + `Action type: minimal-fix`——契约的 Auto-Continue
`Feedback class` 只允许 positive（standard 档），但 `loop/SKILL.md:557` step 7 要求
negative/neutral 且无需人决策时"propose **or enter**"下一个修复轮。**该停还是该续，
协议自己没说清。**

### 裁定：Auto-Continue 管的是 T1，不是 T2

区分两种转移：

| | 含义 | 治理者 |
|---|---|---|
| **T1** | 推进到**下一个子目标/任务**（新 scope，本轮工作已被接受） | 契约 Auto-Continue 表 |
| **T2** | 进入**修复/调查/回滚轮**（当前工作尚未被接受，在其上继续处置） | `loop/SKILL.md:557` step 7 + `harnessloop-continue/SKILL.md:33` step 6 |

依据：
- `loop/SKILL.md:517` 对 positive 的定义逐字是 "archive and **continue to the next
  subgoal or task**"——这正是 T1，与 Auto-Continue 表同一措辞。
- `harnessloop-continue/SKILL.md:33` 允许 T2 时**不带任何 profile 限定词**。
- `control-contract-profiles.md:15` 的 **lite** 档 Feedback class 明文写着
  "positive; **or negative/neutral when the next step is read-only investigation,
  a minimal fix, or a rollback within this round's scope-lock**"——lite 只是把所有档
  本就允许的 T2 **说出来了**。

**因此 standard 的裸 "positive" 治理 T1，不禁止 T2。** 这个读法**消除**矛盾；
另一读法（standard 也禁 T2）会让 standard 禁止 step 7 强制要求的修复回路，是把矛盾
制度化。

**不追溯**：本裁定**不用于回判历史轮**。round 0001 在本规格生效前收口，其值一律是
`historical-unrecorded`（见 §5），不因本裁定被判为偏离。

## 1. 问题（不变）

协议明文要求单会话多轮自续（`loop/SKILL.md:556` + `:560-567` 六条穷举 Stop 清单，
不含"等用户敲 continue"），本项目 `state/control-contract.md` 的 Auto-Continue 段
逐字写着"不需要——满足以上条件时自动进入下一子目标"，而实践 **14/14 轮**全部停在
等人，**不留痕迹、不被标红**。偏离零成本 → 实践必然漂移。

## 2. 设计

### 2.1 `decision.md` 新增 `Loop continuation:` 字段

```
- Loop continuation: continued: <successor-round-id>
                   | stopped: <reason>[ — <backing-ref>]
                   | historical-unrecorded
```

**`continued` 必须带 successor**（T-076 findings 3/8）。v1 允许裸 `continued` 是它
最大的洞。

`continued: 0011` 是一条**关于世界的断言**，机械门在**此后每一次运行**核对它：
successor round 目录必须存在、属同一 goal、且其 `scope-lock.md` 存在。
这绕开了 v1 的写入时序难题（收口时写的是承诺、不是事实）——**不要求写入那一刻为真，
要求它最终为真且持续为真**。最高轮写 `continued` 却无 successor → 红。

### 2.2 停止原因枚举

**协议 Stop 六条**（`loop/SKILL.md:560-567`）：
`goal-achieved` / `missing-human-input` / `missing-access-facts` /
`write-safety-unconfirmed` / `data-contract-unsatisfiable` / `threshold-unevaluable`

**契约 Auto-Continue 未满足**（`control-contract-profiles.md:15-19`，T1 面）：
`evidence-health-failed` / `open-handoff-blocking` / `environment-selfcheck-failed` /
`profile-requires-confirmation`

**契约 Stop Conditions 表**（`:34-43`——v1 只比了 Auto-Continue，**漏了这整张表**，
T-076 finding 7）：
`model-effort-mismatch` / `external-system-unsafe` / `contract-unevaluable` /
`evidence-missing-for-acceptance`

**合法但此前无词汇**：
`budget-checkpoint` / `user-interrupt`

**偏离**（新增，**判红**）：
`unjustified-stop` —— 停止且没有可支撑的理由。

**迁移专用**：`historical-unrecorded` —— 仅迁移工具可写（§5）。

### 2.3 红灯落在"没有可支撑的理由"上，不落在标签上

这是 v2 与 v1 的分水岭。

- 每个 `stopped: <reason>` 必须**有支撑**（§3 定义每个 reason 的支撑判据）。
- **支撑不成立 → `loop-stop-reason-unbacked`（红）**，无论写的是哪个标签。
- `unjustified-stop` 是这同一红灯的**诚实标签**：它让"我确实无正当理由地停了"
  可以被如实说出，而不是逼人从别的标签里挑一个撒谎。

**设计后果（有意）**：agent 靠换标签得不到任何好处——不写字段是红
（`loop-continuation-missing`），写没支撑的理由是红，诚实写 `unjustified-stop` 也是红。
**能拿到绿灯的唯一途径是：要么真的继续了，要么停止理由真的成立。**

### 2.4 `control-contract.md` 的 `Round Budget` 块（v1 可被 `unbounded` 架空）

```
## Round Budget

- Max consecutive auto-continued rounds: <正整数>   # unbounded 时不得用作停止理由
- Budget checkpoint action: stop-and-report | ask-user
- Cost budget: <说明> | not-used
```

v1 的洞（T-076 finding 2）：`Max: unbounded` + `Cost: not-used` 满足 v1 的"块存在且
Max 非空"，于是永远到不了的预算成了合法停止理由。

v2：`budget-checkpoint` 要求 **Max 为有限正整数**，**且**机械门从前序轮的
`continued:` 链**推导出实际连续自续轮数 ≥ Max**。推导可做——`continued: <id>` 形成
一条可追的链。

**成本维度仍不作主判据**：`round_cost.py` 依赖本机 transcript，本项目 14 轮中多数
轮次至少一个 cost 字段 `unavailable`。轮数可靠、成本提示性（T-074 O-2）。

### 2.5 档位分层（不变）

lite/standard 满足条件即应自续（T1）；T2 各档均可（§0 裁定）。strict 的逐 subgoal
人闸不动，`profile-requires-confirmation` 是它的正常停止值（T-075 O-8）。

### 2.6 `harnessloop-continue` 三个兼容分支（v1 只写了收窄、没写恢复）

T-076 finding 5：按 v1 字面实施会同时切断 legacy 与异常恢复——最新轮 0010 迁移后是
`historical-unrecorded`，既非 `stopped:` 也非 `continued`，v1 无分支可走；宿主在收口
后、字段写入前崩溃时更是恰恰需要 continue 救援，却被"没有记录在案的停止"挡在门外。

| 最近一轮的值 | continue 行为 |
|---|---|
| `stopped: <backed reason>` | 正常重入 |
| `historical-unrecorded` 或字段缺失 | **允许恢复**，同时报 legacy/unrecorded anomaly |
| `continued: <id>` 且该 round 存在 | 转到该 successor 继续，而非任意推进 |
| `continued: <id>` 但该 round 不存在 | 报矛盾 + 按恢复分支处理（这也是 §2.1 的红） |

"例行推进不推荐人工调用"是**文档语义**，不是"无恢复分支的前置条件"。

## 3. 三层可验证性（v1 的能/不能清单不诚实，T-076 finding 8）

v1 把弱存在性包装成"支撑"，又把多项廉价可做的检查写成"不能"。v2 分三层：

### 层 A — 机械门可从仓库派生（必须做）

| reason | 支撑判据 |
|---|---|
| `continued:<id>` | successor round 目录存在、同 goal、有 scope-lock |
| `budget-checkpoint` | Max 为有限正整数 **且** 由 `continued:` 链推导的连续自续轮数 ≥ Max |
| `goal-achieved` | 该 goal 的 `goal.md` 声明了完成/归档状态 |
| `open-handoff-blocking` | 本 round `handoffs/` 内存在非 archived 且状态非 closed 的 handoff |
| `evidence-health-failed` / `evidence-missing-for-acceptance` | `state/evidence-index.md` 存在 artifact health 非 valid 的条目 |
| `environment-selfcheck-failed` | `state/environment.md` 的 `Pass/fail` 声明值不是 `pass` |
| `profile-requires-confirmation` | 契约 Auto-Continue 的 `Human confirmation` 字段声明需要确认 |
| `contract-unevaluable` | 契约或 evidence-index 存在必填字段缺失 |

### 层 B — 需要引用（reference）才算 backed

`user-interrupt` / `missing-human-input` / `missing-access-facts` /
`write-safety-unconfirmed` / `data-contract-unsatisfiable` / `threshold-unevaluable` /
`model-effort-mismatch` / `external-system-unsafe`

这些无法从仓库单独派生，必须写成 `stopped: <reason> — <backing-ref>`，其中
`backing-ref` 是一条**项目内可解析的引用**（证据路径、handoff 路径、issue ID、
或 decision.md 内某字段）。

**诚实边界**：机械门只能核对该引用**存在且可解析**，**不能**核对它是否真的支持这个
理由。这一层买到的是"必须指出一个可被追问的对象"，不是自动判真。
无引用 → `loop-stop-reason-unbacked`（红）。

### 层 C — 只能人工复核（明写机械门做不到）

- 用户是否真的打断过（宿主会话事件不在仓库内）。
- `continued` 的 successor 是否在**同一会话**开启（机械门只能证明它存在）。
- 停止理由是否为**真实动机**（写 `missing-human-input` 而实际是嫌麻烦，看不出来）。
- 引用是否**真的支持**该理由（层 B 只验存在性）。

**不得声称守住了这一层。** 本项目的病灶就是"声称守住了实际没守住"。

## 4. 异常报告：让"不续"不能保持绿灯（T-076 的核心处方）

除违规外，机械门在满足以下全部条件时对**最新一轮**报 anomaly（进 coverage，
不阻断退出码——它是观测信号不是安全门）：

- 档位为 lite 或 standard（strict 排除）；
- `Feedback: positive`；
- evidence health、open handoff、environment self-check 均满足契约 Auto-Continue；
- 且该轮的 `Loop continuation:` 不是 `continued:`。

即：**契约允许自续、条件全满足、却没有续**。这不强制宿主继续（协议管不了 agent
行为），但让这一情形从**不可见**变成**每次运行都摆在 coverage 里的数字**。

本项目当下若启用，该 anomaly 会立刻非零——这正是它该有的样子。

## 5. 迁移（v1 的 E1 论证是错的）

**先纠正 v1 的事实错误**：v1 称 `decision.md` "不是被检产物"。**错**——
`verify_protocol.py:2006` 起解析其 B2a 字段、E4 读同文件枚举对比
（`verify_protocol.py` 内 `decision = round_dir / "decision.md"`）。它确实是机械门读取
的文件，"改它转绿"的形状成立，必须正面处理而不是绕过。

**处置：明定为 schema migration，顺序写死**：

1. 迁移工具对**激活点之前**的全部 round 添加**唯一固定值** `historical-unrecorded`；
2. 核对：除该行外，每份 `decision.md` **逐字节不变**（可机械验证）；
3. **然后**才启用 gate。

**为什么这不是"改被检产物转绿"**（与 v1 的错误论证不同）：`historical-unrecorded`
不改动任何 feedback、verdict、finding 或引用对象，它**如实陈述"当时的 schema 没有
这个字段"**——这是 schema 演进的记录，不是对历史判断的修改。与 B2a 回填 14 轮
`Review:` 字段（v0.17.0 已验证）同形。

**`historical-unrecorded` 仅迁移工具可写**：激活点之后的任何 round 使用该值 →
`loop-continuation-illegal-legacy-value`（红）。v1 只在散文里禁止，等于没禁。

## 6. 违规 kind 与 coverage

**违规 kind**：
`loop-continuation-missing` / `loop-continuation-invalid-value` /
`loop-stop-reason-unbacked` / `loop-continuation-successor-missing` /
`loop-continuation-illegal-legacy-value`

**coverage**：
`loop_stops_by_reason`（原因→计数）/ `loop_continued_with_successor` /
`loop_continued_without_successor` / `loop_stops_backed` / `loop_stops_unbacked` /
`loop_stops_unjustified` / `loop_rounds_historical_unrecorded` /
`loop_autocontinue_anomalies`（§4）

## 7. 验收（teeth）

| # | 断言 | 破坏性反证 |
|---|---|---|
| L1 | 缺字段 → `loop-continuation-missing` | 去掉检查 → 红 |
| L2 | 枚举外的值 → `loop-continuation-invalid-value` | 放宽为任意字符串 → 红 |
| **L3** | **`continued: 0011` 而 0011 不存在 → `loop-continuation-successor-missing`**；存在则通过 | 允许裸 `continued`（v1 的 L5）→ 红。**这条直接焊死 v1 的头号绕过** |
| **L4** | **`stopped: budget-checkpoint` + `Max: unbounded` → unbacked**；`Max: 3` 但 `continued:` 链只连 1 轮 → 同样 unbacked；链达 3 轮才通过 | 只查"块存在且 Max 非空"（v1 的 L3）→ 红 |
| **L5** | **`stopped: user-interrupt` 无 `— <backing-ref>` → unbacked**；有可解析引用则通过 | 层 B 不要求引用 → 14/14 停止 + 全绿的构造复活 → 红 |
| L6 | 层 A 每个 reason 各一条：支撑不成立即 unbacked（如 `open-handoff-blocking` 但 `handoffs/` 全 closed） | 任一 reason 退化为"标签即通过" → 红 |
| **L7** | **`unjustified-stop` 判红**（与 unbacked 同级），且**不**因为它"诚实"而豁免 | 把它判绿 → 偏离重新变成零成本 → 红 |
| L8 | 枚举覆盖三套来源的并集：用 round 0001 的形状（negative + blocker none + no human + safe）构造——按 §0 裁定它属 T2 可续，若仍停则唯一合法值是 `unjustified-stop`（红） | 枚举只抄协议 Stop 六条 → 无值可填 → 红 |
| L9 | §4 anomaly：构造一个 positive + 全条件满足 + `stopped: user-interrupt`（backed）的最新轮 → `loop_autocontinue_anomalies == 1` 且**退出码不变** | anomaly 恒 0 → 红；anomaly 改变退出码 → 红（防越权成硬门） |
| L10 | 激活后的 round 写 `historical-unrecorded` → `loop-continuation-illegal-legacy-value` | 只在散文禁止 → 红 |
| L11 | 迁移：14 轮回填后全项目**仍 0 违规**；每份 `decision.md` 除新增行外**逐字节不变**（机械验证） | 任何行为外溢 → 红 |
| L12 | continue 三分支：`historical-unrecorded` 与字段缺失时**允许恢复**并报 anomaly（不是拒绝） | 按 v1 字面收窄 → 异常恢复被挡 → 红 |

## 8. 显式不做（含 v1 已否决项）

| 提案 | 理由 |
|---|---|
| 强制自续（不续即违规） | 协议管不了 agent 行为。§4 的 anomaly 是"让不续不能保持绿灯"，不是强制 |
| 让 anomaly 改变退出码 | 它是观测信号；升级为硬门须经预登记与 pilot（B2b 的教训） |
| 用成本做硬预算 | 观测系统性失真，拿失真信号做硬约束是新的假绿 |
| 核对 `continued` 是否**同一会话** | 层 C，做不到。只验 successor 存在 |
| 核对 backing-ref 是否**真的支持**该理由 | 层 C，只验可解析 |
| 修改 strict 档语义 | strict 的人闸是它存在的理由 |
| 记录轮内中止 | 单位是"已收口的轮次"；轮内中止无 decision.md 可写，且 §2.6 的恢复分支已覆盖其后果 |
| 与 `Review:` 共用解析器 | 语义无关；过度耦合是本项目惩罚过的"两份拷贝漂移"的反面 |

## 9. 给第 2 轮对抗审的靶子

> 背景：v1 判 REWORK（每个停止值都绿、L5 保证绕过、`unbounded` 架空、
> E1 论证错误、continue 无恢复分支）。**v2 的中心主张是"红灯落在没有可支撑的理由上"。**
> 请照常判——收敛计数已 1 轮。

1. **§2.3 的中心主张能否被架空**：构造一个 agent，它每轮实际停止却能拿到绿灯。
   （提示攻击面：层 A 的每条派生判据能否被廉价伪造？比如故意留一个 open handoff 来
   合法化 `open-handoff-blocking`？故意让 environment self-check 不是 pass？
   **"制造一个真实的停止理由"算不算绕过？**）
2. **§2.1 的 successor 链**：`continued: <id>` 指向一个**空壳** round 目录
   （只有 scope-lock、没有任何工作）能否骗过？链能否成环？
3. **§0 的 T1/T2 裁定**是否站得住？另一读法（standard 也禁 T2）有没有源码支持是我漏掉的？
   若裁错，§2.2 枚举与 L8 全部要改。
4. **§3 三层划分**是否仍有"声称能、实际不能"或"声称不能、其实廉价可做"的？
5. **§4 anomaly 的条件**能否被规避（例如把 feedback 写成 neutral 就不触发）？
   这个规避算不算问题？
6. **§5 迁移顺序**：步骤 2 的"逐字节不变"如何机械验证（需要迁移前快照，那快照从哪来）？
   这是不是又一个"声称可验证实际做不到"？
7. **本规格是否仍不足以改变实践**。T-076 说 v1 是"观测底座不是完成态"，v2 加了
   successor 物证、backing 要求、unjustified 判红与 anomaly。**够了吗？**
   若仍不够，请说明**什么才够**——这一问允许判定 v2 仍无效。
