# loop 停止落痕 + 轮次预算 + 档位分层 — 规格 v1（2026-07-28）

> 对应 **TH-0023**（loop 停止不落痕）。批 2 独立小规格，**不依赖批 1 的任何产出**。
> 起因：`docs/harnessloop-runtime-evals-autonomy-audit-20260728.md` GAP-4，
> 经 T-074 补 O-2/O-4、T-075 补 O-8 档位分层后定稿裁决（附录 C.4 批 2）。
>
> 状态：**规格草案，待异构对抗审**。实现未开始，机械门在 v0.26.0。
> 授权：main-session ruling under user delegation 2026-07-28（附录 B）。

## 1. 问题

协议**明文要求**单会话多轮自续，实践 **14/14 轮**全部停在等人——而这个偏离
**不留任何痕迹、不被任何机制标红**。

证据：
- `loop/SKILL.md:556` step 6：positive 且 goal 未达成 → `continue to the next subgoal
  or task`。`:560-567` "Stop only when" 六条穷举，**不含**「等用户敲 continue」。
- 本项目 `state/control-contract.md` 的 Auto-Continue 段逐字写着
  「不需要——满足以上条件时自动进入下一子目标」（standard 档），且 14 轮里
  绝大多数轮次 feedback=positive、无 open handoff 阻塞、environment self-check=pass
  ——**契约允许自续，实际没有自续，无人发现**。
- 协议无停止记录机制：`decision-template.md` 无停止原因字段；self-audit 确定性信号
  清单不含停止事件；coverage 无停止计数。
- `state/current.md` 的 `Next proposed action` 一律以「下一 continue 开 SG-X」收尾。

**偏离零成本 → 实践必然漂移。** 这是「绿灯≠真守门」的自主性版本：协议文本许诺了
自续，没有 teeth 保证它。

### 1.1 顺带暴露的协议内部不一致（本规格必须一并处理）

「协议的 Stop 条件」与「契约的 Auto-Continue 条件」是**两套**、且不同构：

| | 出处 | 内容 |
|---|---|---|
| 协议 Stop 条件 | `loop/SKILL.md:560-567` | goal 达成 / 缺人输入 / 缺访问事实 / 写安全未确认 / 数据契约不可满足 / 阈值不可评估 |
| 契约 Auto-Continue 条件 | `control-contract-profiles.md:15-19` | feedback class / evidence health / environment self-check / open handoffs / human confirmation |

一个「evidence health 不合格」或「有 open handoff」导致的停止，**合法**（契约不允许
自续），但它**不在协议的 Stop 清单里**——按 SKILL.md 字面读，它是非法停止。
枚举必须同时覆盖两套，否则合法停止会被新机制误判为违规。

## 2. 设计

### 2.1 `decision.md` 新增 `Loop continuation:` 字段

```
- Loop continuation: continued | stopped: <reason> | historical-unrecorded
```

`continued` 的含义**只有一个**：本会话内实际开启了下一轮（或 goal 已完成前的最后
一次推进）。**不是**「本可以继续」。

### 2.2 停止原因枚举（覆盖两套条件 + 三个此前静默的原因）

| 原因 | 来源 | 说明 |
|---|---|---|
| `goal-achieved` | 协议 Stop | goal 完成，正常终止 |
| `missing-human-input` | 协议 Stop | 需要业务/风险/验收判断 |
| `missing-access-facts` | 协议 Stop | 缺端点/凭证/权限/工具事实 |
| `write-safety-unconfirmed` | 协议 Stop | 需要写但缺 dry-run/回滚/确认 |
| `data-contract-unsatisfiable` | 协议 Stop | 数据契约无法满足 |
| `threshold-unevaluable` | 协议 Stop | 验证阈值无法评估 |
| `evidence-health-failed` | 契约 Auto-Continue | 证据健康度不满足自续条件 |
| `open-handoff-blocking` | 契约 Auto-Continue | 有未关闭/阻塞的 handoff（T-074 O-4） |
| `environment-selfcheck-failed` | 契约 Auto-Continue | 环境自检不为 pass（与 TH-0017 联动） |
| `profile-requires-confirmation` | 契约 Auto-Continue | **strict 档**逐 subgoal 人闸（T-075 O-8） |
| **`budget-checkpoint`** | **新增，合法** | 达到契约声明的轮次/成本预算，主动 checkpoint |
| **`user-interrupt`** | **新增，合法** | 用户主动打断 |
| `historical-unrecorded` | 迁移专用 | 本规格生效前的轮次，当时未记录——**不得**用于新轮 |

**`budget-checkpoint` 与 `user-interrupt` 是本规格的核心产出之一**：它们此前是
*静默逃逸*——真实发生、协议无词汇、于是不留痕。给它们合法枚举值，等于把「实践里
真正发生的停止」从暗处搬到台面，而不是假装它们不该发生。

### 2.3 `control-contract.md` 新增 `Round Budget` 块

```
## Round Budget

- Max consecutive auto-continued rounds: <int> | unbounded
- Budget checkpoint action: stop-and-report | ask-user
- Cost budget: <说明> | not-used
```

**诚实标注**：成本维度**不作为主判据**。`round_cost.py` 依赖本机 transcript 窗口，
本项目 14 轮中多数轮次至少一个 cost 字段为 `unavailable`（子代理/回写会话无窗口，
`loop/SKILL.md:552` 本就允许记 unavailable）。**轮数是可靠维度，成本是提示性维度**
——规格不假装能用一个系统性失真的信号做硬约束（T-074 O-2）。

### 2.4 档位分层：自续词汇不得越过 profile

- **lite / standard**：满足契约 Auto-Continue 条件即应自续；停止必须落痕。
- **strict**：`control-contract-profiles.md:9,:60` 明文要求逐 subgoal 人工确认、
  且不允许连续无人轮。strict 档下 `stopped: profile-requires-confirmation` 是
  **正常且预期**的停止，不构成偏离。

**本规格不修改 strict 的语义**，只要求它把停止说出来。用户裁决②的「单会话多轮自续」
是对 lite/standard 的承诺，不是对 strict 的（T-075 O-8 裁定）。

### 2.5 `harnessloop-continue` 输入契约措辞收窄

现状（`harnessloop-continue/SKILL.md:12`）："asking to resume/advance a Harnessloop
task" —— **推进**与**救援**合并。

改为：continue 是**记录在案的停止之后的重入门**。例行推进属 Loop Continuation
（loop 自己的 step 6），不经 continue。

配套：continue 运行时读最近一轮的 `Loop continuation:`——若为 `continued`，
说明 loop 自称已续但人却在敲 continue，**这本身是一个矛盾信号**，应在输出里点明
（不阻断，因为可能是新会话重入）。

## 3. 机械门核对（能做什么、不能做什么）

**能核对**（写进 `verify_protocol.py`）：
1. `Loop continuation:` 字段**存在**（同 `Review:` 的既有做法）。
2. 值在枚举内（`stopped:` 后的 reason 必须是已定义值）。
3. **有契约支撑的原因必须真有支撑**：`stopped: budget-checkpoint` 要求
   `control-contract.md` 存在 `Round Budget` 块且 `Max consecutive...` 非空；
   `stopped: profile-requires-confirmation` 要求契约的 Auto-Continue
   `Human confirmation` 字段声明了需要确认。
4. `historical-unrecorded` 计入 coverage，使其用量可见。

**不能核对，且规格必须明写**（本项目最恨"声称守住了实际没守住"）：
- **无法验证停止原因是真的**。写 `missing-human-input` 而实际是嫌麻烦，机械门看不出来。
  这个字段的价值是**让偏离可见、可在 round 间 diff、可被评审质问**，不是自动判真伪。
- **无法验证 `continued` 属实**——机械门看不到会话历史。同理，它的价值在于把一个
  此前无处安放的断言变成一条**可被追责的书面记录**。
- **无法强制自续**。协议不能让 agent 必须继续；它只能让「没继续」这件事留下痕迹。

违规 kind（命名沿用既有风格）：
`loop-continuation-missing` / `loop-continuation-invalid-value` /
`loop-stop-reason-unbacked`。

coverage 新增：`loop_stops_by_reason`（原因→计数）、`loop_stops_unbacked`、
`loop_rounds_historical_unrecorded`。

## 4. 迁移

14 个既有 `decision.md` 回填 `Loop continuation: historical-unrecorded`。

**为什么这是 E1-safe**：`decision.md` 是**主会话自己写的协议记录**，不是被检的
评审产物；且回填值是 `historical-unrecorded`——它**如实陈述"当时没记"**，
不追认任何未发生的事实。这与 B2a 回填 14 轮 `Review:` 字段是同一形状（v0.17.0
已验证）。

**不引入激活状态机**（与批 1 不同）：`historical-unrecorded` 这个自证的枚举值
已经足够，再加 `activation_round` 只是多一层可被误用的状态。其用量进 coverage，
**计数不降反升就是一个评审信号**——不设硬门，因为它不是安全面。

## 5. 验收（teeth）

| # | 断言 | 破坏性反证 |
|---|---|---|
| L1 | 缺 `Loop continuation:` → `loop-continuation-missing` | 去掉字段检查 → 红 |
| L2 | `stopped: 乱写的原因` → `loop-continuation-invalid-value` | 放宽为任意字符串 → 红 |
| L3 | `stopped: budget-checkpoint` 但契约无 `Round Budget` 块 → `loop-stop-reason-unbacked` | 去掉支撑核对 → 无预算也能声称预算停 → 红 |
| L4 | `stopped: profile-requires-confirmation` 但契约 Auto-Continue 声明「不需要人工确认」→ `loop-stop-reason-unbacked` | 同上 → 红 |
| L5 | `continued` 与合法 `stopped:` 均通过，**不因值本身判红**（本规格不强制自续） | 把 stopped 判成违规 → 红（这条防止规格越权） |
| L6 | `historical-unrecorded` 计入 `loop_rounds_historical_unrecorded`，且**不**计入 `loop_stops_by_reason` | 混计 → 历史轮污染停止原因分布 → 红 |
| L7 | 迁移：14 轮回填后全项目**仍 0 违规**；violations 的 kind 与 detail 除本规格新增外**逐字节不变** | 任何行为外溢 → 红 |
| L8 | 枚举同时覆盖协议 Stop 六条与契约 Auto-Continue 五条：构造一个「evidence health 不合格」的停止，必须有合法枚举值可用（不得被迫写 `missing-human-input` 之类的错误原因） | 枚举只抄协议 Stop 清单 → 合法停止无值可填 → 红 |

## 6. 显式不做

| 提案 | 理由 |
|---|---|
| 让机械门强制自续（不续即违规） | 协议管不了 agent 的行为，只能管记录。强制会逼出"假 continued" |
| 用成本做硬预算 | 观测系统性失真（多数轮 cost unavailable），拿失真信号做硬约束是新的假绿 |
| 修改 strict 档语义 | strict 的人闸是它存在的理由（T-075 O-8） |
| 引入激活状态机 | `historical-unrecorded` 自证已够；多一层状态多一个被误用的面 |
| 记录**轮内**中止（round 未收口就停） | 本规格的单位是"已收口的轮次"。轮内中止是另一类事（无 decision.md 可写），留作独立议题 |
| 把 `Loop continuation:` 与 `Review:` 合并解析器 | 两者语义无关；共用解析器是本项目已惩罚过的"两份拷贝漂移"的反面——过度耦合 |

## 7. 给对抗审的靶子

1. **§2.2 枚举是否完备**：构造一个真实发生过、但在枚举里**没有正确值可填**的停止。
2. **§3 的"有契约支撑"核对是否可被架空**：写一个空的 `Round Budget` 块骗过 L3？
   契约文本怎么解析（新解析面）？会不会重蹈"路径字面量 ≠ 事实"那一族？
3. **`continued` 的不可验证性**是否让整个字段沦为装饰？本规格辩称"可追责的书面记录"
   有价值——这个辩护成立吗，还是自我安慰？
4. **§4 迁移的 E1 论证**：`decision.md` 真的不算"被检产物"吗？Rule A 检查
   `evidence/` 与 `reviews/`，`decision.md` 确实不在其中——但它是机械门**读**的文件
   （Review 字段、Mechanical gate 字段）。改它算不算"改被检产物转绿"？
5. **§2.5 continue 措辞收窄**会不会破坏既有用法？本项目 14 轮全靠 continue 推进，
   收窄后这些用法变成什么？
6. **本规格是否解决了真问题**：停止落痕真的会改变实践吗，还是只是多一个字段、
   人照样每轮停（只不过现在写着 `stopped: user-interrupt`）？**这一问允许判定
   本规格无效**——若结论是"落痕不足以改变行为"，请说明什么才够。
