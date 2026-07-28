# loop 停止落痕 — 规格 v3.1（2026-07-28）

> **v3.1 = v3 + T-078 的五条最小接线补丁 + 横切约束 X1/X6 两条。**
> 收敛守卫已于 v3 触发；**(A) 是主会话在用户「自裁并推进」授权下自选的**，
> 不是用户直接在 A/B 之间点选（附录 A.4 原文写明「主会话不代裁」，后被该授权覆盖）。
> **措辞订正 2026-07-28**：此处原写「由用户裁决放行」，读起来像用户点了 A，实际不是。
> 本版**不重开哲学**，只做接线；v3 的正文与裁决全部保留，改动集中在 §4/§5/§6 与新增 §10。
>
> **v3 是一次主动收窄，不是第三次补洞。** v1/v2 连挨两轮 REWORK（T-076/T-077），
> 两次的根因是同一个：**我让机械门去裁断"停止理由是否正当"，而那是它结构上做不到的**——
> agent 写记录，也控制记录被核对的每一个输入（可以真的留一个 open handoff、真的让
> environment self-check 不是 pass，从而"制造"一个合法停止理由）。
>
> T-077 的原话是"仍是可由同一 agent 自签、自证、**自造 blocker** 的观测底座"。
> 这个批评成立，且**加更多同层检查解决不了**。
>
> v3 因此把机械门的职责收窄到它真能验证的部分，其余明确降为**可审计的声明**，
> 并把执行力放到它真正所在的地方（异常消费 + 对抗评审）。
>
> 收敛计数：**已 2 轮 REWORK。第 3 轮若再 REWORK，触发收敛守卫——届时停下向用户
> checkpoint，不写 v4。**
> 授权：main-session ruling under user delegation 2026-07-28。机械门在 v0.26.0。

## 0. 先撤回 v2 的地基裁定（我错了）

v2 §0 裁定"Auto-Continue 只管 T1、不管 T2（修复/调查/回滚轮），故各档均可自动进 T2"。
**T-077 推翻了它，理由我无法反驳**：

| 我引的依据 | 它的判定 |
|---|---|
| `loop/SKILL.md:517` positive → next subgoal/task | 只证明 positive 通常对应 T1，**不证明**档位表仅管 T1 |
| `loop/SKILL.md:557` "propose **or** enter" | 那个 **or** 保留了 propose-only 分支，推不出"自动 enter" |
| `harnessloop-continue/SKILL.md:33` | 是 continue **被调用之后**的动作上界，不是无条件 auto 权限；`:31` 仍要求匹配控制契约 |
| `control-contract-profiles.md:15` | **直接反证**：该表的存在目的就是区分档位。lite 明文列出 T2、standard 只写 positive——若 T2 各档通用，lite 那一句就是废话 |

**订正裁定**：**T2 的自动进入是档位差异，不是通用权限。** lite 允许；standard/strict
按其字面只允许 positive 自动推进。

**后果（必须承担，不绕过）**：
- 枚举需要 `feedback-not-auto-continuable`——standard 档下 negative/neutral 且无需人
  决策时停下，是**合规行为**，不是偏离。
- standard 档项目若想要 T2 自主，正确做法是**在自己的 control-contract 里把 lite 的那
  一句写进 Feedback class**（契约本就是项目可改的），而不是靠规格重新解释档位表。
- 本项目 goal 001 的 round 0001（negative + 无需人决策 + safe）因此是**合规停止**，
  不是偏离——v2 把它算作偏离是错的。

## 1. v3 的收窄：机械门只做它能证明的

### 1.1 为什么收窄，而不是继续加检查

v2 设计了三层可验证性（A 可派生 / B 需引用 / C 做不到），并要求每个停止理由"有支撑"。
T-077 逐层击穿：层 A 的原因 agent 可以**真的制造**；层 B 的引用可以指向 decision.md
自身；`user-interrupt` 只有宿主 event ID 才可能为真，而宿主事件不在仓库里。

**关键认识**：这不是设计不够好，是**层次错位**。机械门读的是 agent 自己写的树，
它能验证**结构关系**（某文件是否存在、某 id 是否前向、某链是否成环），
**不能验证动机**（为什么停）。再加十条检查，agent 仍然控制所有输入。

**先例支持这个收窄**：B2a 的 `Review:` 字段自述得很清楚——它"accounts for the
review's existence and identity only; it never scans the file's prose"
（`loop/SKILL.md:466`）。它没有假装能判断评审质量，**而它被接受为有价值**。
停止记录应当照此办理。

### 1.2 收窄后的三分

| 层 | 内容 | 机械门 |
|---|---|---|
| **强制** | 字段存在、值合法、`continued` 的**结构关系** | **判红** |
| **记录** | 停止的**理由**（枚举值 + 可选说明） | 只记，不裁断 |
| **异常** | "契约允许自续、条件满足、却没续" | 报 anomaly + **必须被消费**（§4） |

**诚实声明（必须写进 SKILL.md，不只写在规格里）**：一个执意要停的 agent 可以写一个
合规的停止理由并拿到绿灯。本机制**不声称**能阻止它。它买到的是：
每一次停止都留下**具名、可 diff、可被对抗评审质问**的记录，且"本可以续却没续"
这一情形在每次运行时都以数字形式摆出来。**执行力在人和评审那里，不在退出码里。**

## 2. 强制层（判红）

### 2.1 字段

```
- Loop continuation: continued: <successor-round-id>
                   | stopped: <reason>[ — <说明>]
                   | historical-unrecorded
```

### 2.2 `continued` 的结构约束（T-077 finding 2 的三个反例全部堵上）

`continued: 0011` 判红当且仅当以下任一不成立：

1. `0011` 目录存在于**同一 goal** 的 `rounds/` 下；
2. **严格前向**：`0011` 的轮次序号 **>** 当前轮（堵 `continued: <上一轮>` 与 self-loop）；
3. **无环**：沿 `continued:` 链前向遍历不得回到任一已访问轮（堵双节点环）；
4. successor **最小完整性**：`scope-lock.md` **与** `round-summary.md` 或 `decision.md`
   至少其一存在（堵"只有 scope-lock 的空壳 successor"）；
5. successor 的 `decision.md`（若存在）声明 `Predecessor: <当前轮>`——**双向绑定**。

**诚实边界**：这些证明"下一轮真的存在且是真轮次"，**不证明**它在同一会话开启。
故字段语义定为 **`successor-observed`**（T-077 建议的措辞），SKILL.md 不得写成
"实际自续"。

### 2.3 `historical-unrecorded` 的激活边界（v2 无 cutoff，新轮可伪装）

`.harnessloop/setup/loop-continuation-legacy.json`：

```json
{"version": 1, "legacy_rounds": ["<goal-id>/rounds/0001", "..."]}
```

- 该值**仅**允许出现在清单内的 round；其他 round 使用 → `loop-continuation-illegal-legacy-value`。
- 清单由迁移工具一次写入。**诚实标注**：机械门无法防止有人事后往清单里追加
  （单次运行看不到历史）；但追加会出现在 git diff 里，且清单条目数进 coverage。
  **不声称机械门守住了追加。**

### 2.4 违规 kind

`loop-continuation-missing` / `loop-continuation-invalid-value` /
`loop-continuation-successor-missing` / `loop-continuation-successor-not-forward` /
`loop-continuation-successor-cycle` / `loop-continuation-successor-incomplete` /
`loop-continuation-predecessor-mismatch` / `loop-continuation-illegal-legacy-value`

## 3. 记录层（只记不裁断）

### 3.1 枚举

**协议 Stop 六条**（`loop/SKILL.md:560-567`）：`goal-achieved` / `missing-human-input` /
`missing-access-facts` / `write-safety-unconfirmed` / `data-contract-unsatisfiable` /
`threshold-unevaluable`

**契约 Auto-Continue 未满足**（`control-contract-profiles.md:15-19`）：
**`feedback-not-auto-continuable`**（§0 订正后新增） / `evidence-health-failed` /
`open-handoff-blocking` / `environment-selfcheck-failed` / `profile-requires-confirmation`

**契约 Stop Conditions 表**（`:34-43`）：`model-effort-mismatch` /
`external-system-unsafe` / `contract-unevaluable` / `evidence-missing-for-acceptance`

**此前无词汇**：`budget-checkpoint` / `user-interrupt`

**诚实标签**：`unjustified-stop`——停了且自知无正当理由。**不判红**（v2 判红是过度声称：
机械门分不清它与一个伪装成合规理由的停止，判红只惩罚诚实的人）。它进独立 coverage 计数，
**非零即评审信号**。

### 3.2 为什么不再要求"支撑"

v2 要求每个理由 backed。T-077 证明支撑判据要么可被制造（层 A），要么可被自引用满足
（层 B）。**一个能被廉价满足的强制，只是把成本加给诚实的人，不加给不诚实的人。**
故 v3 取消强制支撑；`— <说明>` 保留为**可选自由文本**，供评审阅读。

## 4. 异常层：执行力真正所在（T-077 的核心处方）

### 4.1 触发

对**最新一轮**，当以下全部成立时报 `loop-autocontinue-anomaly`：

- 契约 `Profile:` 为 `lite` 或 `standard`（strict 排除）；
- `Feedback: positive`（**订正后不再包含 negative/neutral**——那在 standard 下本就合规停止）；
- evidence health / open handoff / environment self-check 均满足契约 Auto-Continue；
- 该轮 `Loop continuation:` 不是 `continued:`。

### 4.2 消费闭环（v2 缺这一环，"coverage +1、exit 0、无人读取"不叫不再绿）

- anomaly **不改变退出码**（它是观测信号，升级为硬门须经预登记与 pilot——B2b 的教训）；
- 但 `$harnessloop-status` 与 `$harnessloop-continue` **必须在输出顶部显著显示**未确认的
  anomaly，并要求一次显式 acknowledgement（记入 `state/self-audit.md`）；
- 未确认 anomaly 数进 coverage，**每轮累积**——它不会自己消失。

**这是本规格唯一真正的执行力来源**：不是让机械门抓住撒谎的 agent，而是让"本可以续
却没续"这件事**每次都摆在人眼前且必须被回应**。

## 5. 契约需要的机器字段（T-077 finding 4）

v2 依赖对 `control-contract.md` 自由文本的解析（中文"不需要"会击穿 substring 匹配）。
v3 要求契约增加 canonical 字段：

```
- Profile: lite | standard | strict | custom
- Auto-continue on positive: yes | no
- Auto-continue on negative/neutral remediation: yes | no    # 即 T2，§0 订正后必须显式
```

自由文本降为说明。无 `Profile:` 字段时 §4 anomaly **不报**（不猜档位）——
并在 coverage 记 `loop_anomaly_skipped_no_profile`，使"因为没声明档位所以没报"
本身可见。

## 6. 迁移

1. 迁移工具对清单内 round 添加**唯一固定行** `Loop continuation: historical-unrecorded`；
2. 机械核对：每份 `decision.md` 除该行外**逐字节不变**——**用迁移工具自己在写入前
   计算的 sha256 作为 baseline**（T-077 finding 6 指出 v2 没说 baseline 从哪来；
   答案是迁移工具产出一份 `migration-manifest.json` 记录 preimage 摘要）；
3. **然后**才启用 gate。

`decision.md` 确实是机械门读取的文件（`verify_protocol.py` 解析其 B2a 字段），
v1 的"它不是被检产物"论证是错的——本次以 **schema migration + preimage 摘要**
正面处理，不绕过。

## 7. 验收（teeth）

| # | 断言 | 破坏性反证 |
|---|---|---|
| L1 | 缺字段 → missing | 去掉检查 → 红 |
| L2 | 枚举外的值 → invalid | 放宽 → 红 |
| L3 | `continued: <不存在的轮>` → successor-missing | 允许裸 continued → 红 |
| **L4** | **`continued: <上一轮>` 或指向自身 → successor-not-forward** | 只查存在性 → 红 |
| **L5** | **A→B、B→A 双节点环 → successor-cycle** | 不做链遍历 → 红 |
| **L6** | **successor 只有 scope-lock → successor-incomplete** | 只查目录存在 → 空壳过关 → 红 |
| **L7** | **successor 的 decision 未声明 `Predecessor:` → predecessor-mismatch** | 单向绑定 → 红 |
| L8 | 清单外的 round 用 `historical-unrecorded` → illegal-legacy-value | 只在散文禁止 → 红 |
| **L9** | **任何合法 `stopped: <reason>` 均不判红**（含 `unjustified-stop`） | 把停止理由判红 → 红（**这条防止规格重蹈 v2 的过度声称**） |
| **L10** | **§4 anomaly：positive + 条件满足 + 非 continued → anomaly 计数 +1 且退出码不变**；strict 档不报；无 `Profile:` 字段时不报且计入 skipped | anomaly 恒 0 → 红；anomaly 改退出码 → 红 |
| L11 | 迁移：14 轮回填后全项目仍 0 违规；preimage 摘要比对通过 | 行为外溢 → 红 |
| L12 | continue 四分支（backed stopped / historical / continued+successor 存在 / continued+successor 缺失）均有定义且**不拒绝恢复** | 按 v1 字面收窄 → 崩溃恢复被挡 → 红 |

## 8. 显式不做

| 提案 | 理由 |
|---|---|
| 要求停止理由"有支撑"（v2 的层 A/B） | §3.2：可被制造或自引用满足，只惩罚诚实的人 |
| `unjustified-stop` 判红（v2） | 机械门分不清它与伪装成合规的停止；判红只惩罚诚实标注 |
| 强制自续 / anomaly 改退出码 | 协议管不了 agent 行为；升级为硬门须预登记 + pilot |
| 核对 `continued` 同一会话 | 做不到，故字段语义是 `successor-observed` 而非"实际自续" |
| 用成本做硬预算 | 观测系统性失真（多数轮 cost unavailable） |
| 把 T2 权限统一到各档 | §0：那是我 v2 犯的错，档位差异是有意设计 |
| 记录轮内中止 | 无 decision.md 可写；§4 的 continue 恢复分支覆盖其后果 |

## 9. 给第 3 轮对抗审的靶子

> **收敛守卫已在待命位：本工作项已 2 轮 REWORK，第 3 轮再 REWORK 即停下向用户
> checkpoint。请照常判——该 REWORK 时照判，不要因为这个提醒放水。**

1. **§1 的收窄是否退得太多**：取消支撑要求后，T-076 最初的批评（"每个停止值都绿"）
   是否原样复活？§4 的 anomaly + acknowledgement 真的补上了吗，还是只是把绿灯换了个
   地方？**这一问允许判定 v3 是倒退。**
2. **§2.2 的五条结构约束能否被绕过**：构造一个满足全部五条、但实际并未自续的
   `continued` 声明（提示：agent 可以真的建一个 successor round 再停在那里——
   这算不算绕过？如果算，它可被机械门区分吗？）。
3. **§0 的订正裁定是否正确**：standard 真的禁止 T2 自动进入吗？还是我这次又矫枉过正
   （从"各档通用"跳到"档位差异"）？请给源码判定。若又错，§3.1 枚举与 §4 触发条件全要改。
4. **§4 的 acknowledgement 闭环**是否可执行：SKILL 层的"必须显示并要求确认"没有机械
   强制力，会不会又是一句无人遵守的散文？有没有可机械化的部分？
5. **§5 的 canonical 字段**是否引入新的迁移负担（既有项目契约都没有 `Profile:` 字段，
   于是 anomaly 全被 skip）——这会不会让整个 §4 在落地首日就是死的？
6. **§6 的 preimage 摘要**是否真的可行：迁移工具自产 baseline 算不算"自己证明自己"？
7. **本规格是否仍不足以改变实践**。v1 观测底座、v2 过度声称、v3 收窄 + 异常消费。
   **若 v3 仍不够，请明确说：这个问题是不是根本不该由 harnessloop 协议解决**
   （例如它属于宿主/调度层）。这一问允许判定整个方向应当放弃。

---

## 附录 A：收敛守卫触发 — 停在 v3，等待用户裁决（2026-07-28）

**T-078（grok，第 3 轮）判 REWORK。本工作项连挨 3 轮 REWORK（T-076/077/078），
收敛守卫触发。主会话按既定纪律与对用户的明示承诺停止，不写 v4。**

T-078 自己也明确要求这样做：「不要进入实现，也不要因为收敛守卫而『改个措辞算 v4
硬过』。向用户 checkpoint 时建议带最小可 ship 补丁清单。」

### A.1 与上一次守卫触发（ignore 收窄）的关键差别

上次守卫触发时，三轮的结论指向「层次错了」，用户裁决换层次。**这次不是。**
T-078 对两个可否决问的判定都是正面的：

- **「v3 是倒退吗」→ 进步，附硬条件。** 诊断正确（自签是层次问题，加同层检查无效）、
  先例对齐（B2a 只核存在与身份）、结构牙齿真变硬（L4-L7 针对倒指/环/空壳/前驱）、
  地基订正与 `profiles:15` 一致、L9 防止再写成可实现的道德审判。
- **「该不该由 harnessloop 解决」→ 应当解决可审计层，方向不应放弃。**
  停止是否落痕、successor 是否可观察、契约是否允许自续，全是协议状态机问题；
  但「agent 是否在同一次采样里继续」最终由宿主会话生命周期决定，SKILL 文本无法
  强制模型不结束 turn。

**因此这次的守卫结论是「方向对、文本未到可实现」，不是「层次错」。**

### A.2 三轮的形状（与 TH-0008 / ignore 收窄对照）

| 轮 | 形状 |
|---|---|
| v1（T-076） | 观测底座：每个停止值都绿，且自己的 L5 保证了绕过 |
| v2（T-077） | 过度声称：要求每个理由「有支撑」，支撑可被制造或自引用满足；地基裁定错误 |
| v3（T-078） | 收窄方向正确，但执行力单点（§4 anomaly）在无 Profile 字段、无 ack schema 时**等于零** |

三轮不是同形复发（那是换层次的信号），而是**依次收敛的三个不同缺陷**：先太松、
再太满、现在方向对但接线未闭合。这是守卫应当放行继续、而非换层次的形态——
**但按纪律仍须由用户裁定，不由主会话自判。**

### A.3 T-078 给出的最小可 ship 补丁清单（未实施，待裁决）

1. **§6 迁移补 canonical `Profile:` 三字段**，作为启用 gate 的硬前置；本项目先写入
   `Profile: standard` + 两个 Auto-continue boolean。**无此不做 anomaly**
   （否则 §4 在落地首日就是死的——这正是我在 §9 靶 5 自问的那条）。
2. **§4 触发按 Profile 分支**：lite 包含 negative/neutral + remediation action types；
   各档均排除 `goal-achieved`；blocked + runtime-recoverable 未进恢复轮另计。
3. **§4.2 机械化**：coverage 键 + `self-audit`/`current.md` 的 canonical ack 块 +
   continue 在 `unacked > 0` 时返回 `needs-human`；skill 散文降为说明。
   —— 这一条把「执行力」从散文承诺变成机械可判，是 §4 从零变成非零的关键。
4. **§3 边界微移**：同文件内 reason ↔ `Feedback`/`Blocker type`/`Human confirmation
   required`/`Safe without user input` 的一致性作为 **coverage 信号**（不判红），
   收回 v3 靶 8 指出的误伤（v3 把一批廉价可证的一致性检查一并砍掉了）。
5. **§2.2 小加固**：successor 强制 `decision.md` 存在（使双向 predecessor 绑定真正
   生效）或要求 `round-summary.md` 含非空 `Objective:`；迁移 manifest 增
   `baseline_commit`。

### A.4 待用户裁决的两个选项（T-078 建议的决策点，主会话不代裁）

- **(A)** 接受 A.3 五条最小补丁 → 出 v3.1 → 进入实现（规格已过三轮审，补丁均为接线级）。
- **(B)** 降级为「纯观测字段 + `continued` 结构约束」，**砍掉 §4 的执行力声称**——
  即明确承认协议层只提供可审计记录，自主性执行交给宿主/调度层与人。

**主会话倾向 (A)**，理由：A.3 第 3 条把执行力从散文变成机械可判（continue 在
`unacked > 0` 时返回 `needs-human`），这恰好补上 T-078 判定的那个「单点等于零」；
且 (B) 会把这一步降回 v1 的观测底座，而 T-076 已经判过那不够。**但这是裁决，
不是执行细节，按附录 B 的授权边界留给用户。**

### A.5 状态

- 规格停在 v3（commit `58e360b`），**不进入实现**。
- 三轮评审产物：`.hopper/handoffs/T-076-output.md` / `T-077-output.md` / `T-078-output.md`。
- TH-0023 保持 open，Status Notes 已指向本附录。

---

## 附录 B：v3.1 的五条接线补丁 + 两条横切约束（2026-07-28）

> 依据：用户裁决「自裁并推进」→ 审核报告附录 E.1 采 **(A)**；T-078 的最小可 ship 清单；
> 横切约束 `docs/mechanical-gate-cross-cutting-constraints-20260728.md`。
> **本附录的内容优先于 v3 正文中被它修改的部分。**

### B.1 补丁 1 — `Profile:` 三字段是启用 gate 的**硬前置**（X1 收口，改 §5）

v3 §5 写「无 `Profile:` 字段时 §4 anomaly 不报（不猜档位）」。**按 X1 这是一个被守门者
持有的开关**：不写字段 = anomaly 永不触发 = 零违规关门。

**v3.1 改为**：

| 项目状态 | 契约缺 `Profile:` 三字段 |
|---|---|
| **未启用**本机制（无 `loop-continuation-legacy.json`，且无任何 round 带 `Loop continuation:`） | 无影响（零行为，符合 X1 第 3 条：缺席让被检方**能力更小**） |
| **已启用**（迁移已跑，或任一 round 带该字段） | **违规** `loop-contract-profile-missing`；不再有「skip + 计数」这一档 |

`loop_anomaly_skipped_no_profile` 这个 coverage 键**删除**——它记录的是一个从此不该存在
的状态。

**为什么这不违反 X1 的例外条款**：本机制启用后，「缺 Profile」让被检方获得的是**更多
自由**（anomaly 永不报），故必须阻断。这与 reference-roots「缺席≡不读外部树≡能力更小」
是相反方向，判据见 X1 第 3 条。

### B.2 补丁 2 — anomaly 触发按 profile 分支（改 §4.1）

v3 §4.1 的四条件对 lite 与 standard 一视同仁，与 §0 的订正裁定（**T2 自动进入是档位
差异**）不一致。

**v3.1 触发条件**：

| profile | 触发 anomaly 的条件 |
|---|---|
| `lite` | `Feedback` ∈ {positive, negative, neutral} 且 `Next Action.Action type` ∈ {next-subgoal, investigation, minimal-fix, rollback} 且其余自续条件满足 且非 `continued:` |
| `standard` | `Feedback: positive` 且其余自续条件满足 且非 `continued:` |
| `strict` | **不报**（逐 subgoal 人闸是其设计，不是偏离） |
| `custom` | 按契约的 `Auto-continue on positive` / `Auto-continue on negative/neutral remediation` 两个 boolean 求值 |

**各档一律排除 `goal-achieved`**：goal 已达成时不续是终止，不是偏离。

**另计一类（不进 anomaly，进独立 coverage）**：`Feedback: blocked` +
`Blocker type: runtime-recoverable` 而未进入恢复轮——协议明文允许自动开恢复轮
（`loop/SKILL.md:184`、`harnessloop-continue/SKILL.md:35`），故它也是一种「本可以续
却没续」，但性质不同（恢复而非推进），记 `loop_recoverable_not_recovered`。

### B.3 补丁 3 — anomaly 消费的机械化（改 §4.2，本版最关键的一条）

v3 §4.2 把消费闭环写成 SKILL 散文（「必须在输出顶部显著显示」），**散文没有机械强制力**
——T-078 判定 §4 的执行力「单点等于零」正是指这个。

**v3.1 机械化为三件事**：

1. **canonical ack 块**：`state/self-audit.md` 新增固定格式段落
   ```
   ## Loop Continuation Anomalies
   | Round | Anomaly kind | Acknowledged at | Note |
   |---|---|---|---|
   ```
   一行 = 一次显式确认。格式机器可解析。
2. **coverage 键**：`loop_anomalies_total` / `loop_anomalies_acknowledged` /
   `loop_anomalies_unacked`（= 前两者之差，**每轮累积，不自动消失**）。
3. **`$harnessloop-continue` 的门**：`loop_anomalies_unacked > 0` 时，continuation
   decision **返回 `needs-human`**，并在输出里列出未确认的轮次与 kind。

第 3 条是 v3.1 的**唯一真执行力**：它不改 `verify_protocol.py` 的退出码（X5 的克制
仍然成立、B2b 的教训仍然有效），但它让「本可以续却没续」在**下一次 continue 时挡住
自动推进**，直到有人写下一行确认。SKILL 散文降为对该机械规则的说明。

**诚实边界**：写一行 ack 的成本很低，一个执意要停的 agent 可以每轮自己 ack。
**本机制不声称阻止它**——它买到的是「每一次都必须留下一条具名、可 diff、可被对抗评审
质问的确认记录」。执行力仍在人和评审那里（v3 §1.2 的诚实声明不变）。

### B.4 补丁 4 — 同文件一致性作为 coverage 信号（改 §3，收回 v3 靶 8 的误伤）

v3 §3.2 取消强制支撑时，把一批**廉价可证的同文件一致性**一并砍掉了。v3.1 补回，
但**只作 coverage 信号、不判红**（X5 第 3 条：不强制可被廉价满足的形式）：

`loop_stop_reason_inconsistent` 计数以下情形——

| 情形 | 说明 |
|---|---|
| `stopped: missing-human-input` 而同文件 `Human confirmation required: no` | 自相矛盾 |
| `stopped: write-safety-unconfirmed` 而 `Safe without user input: yes` | 自相矛盾 |
| `stopped: <任意>` 而 `Blocker type: none` 且 `Next Action.Action type: next-subgoal` | 声称停止却声称下一步是推进 |
| `continued:` 而 `Blocker type` ∈ {access-missing, human-decision-required, write-safety-required} | 声称续了却声称被这类阻塞挡住 |

**这些字段的取值必须按 X6 规范化后再比较**（见 B.6）。

### B.5 补丁 5 — successor 最小完整性收紧 + manifest 加 `baseline_commit`（改 §2.2、§6）

- §2.2 第 4 条改为：successor 必须**同时**有 `scope-lock.md` **与** `decision.md`
  （原「二者之一」允许一个只有 scope-lock + round-summary 的空壳）；且其 `decision.md`
  的 `Objective`/`Round` 字段非空。
- §6 迁移 manifest 增 `baseline_commit`（迁移执行时的 `git rev-parse HEAD`），
  使 preimage 摘要可被第三方独立复算——回应 T-078「迁移工具自产 baseline 算不算
  自己证明自己」的质疑：**加了 commit 锚点后，任何人可 checkout 该 commit 重算**。

### B.6 横切约束补丁 — X6 枚举规范化（新增，v3 完全没有）

**病灶**：本项目 14 轮 `decision.md` 的枚举字段**几乎全部**写成「值 +（中文说明）」——
`Human confirmation required` **14/14**、`Scope-lock required` **14/14**、
`Safe without user input` 11/14、`Recovery eligible` 11/14。任何精确枚举匹配在 14/14 轮
上都会命中未知值分支。

**规则**：

1. **规范化**：取值截断到首个 `（`、`(`、`——`、`—` 之前，再 `strip()`、转小写。
2. 规范化后仍不在枚举内 → **违规** `<field>-unrecognized-value`。
   **绝不允许**「不认识 → 跳过依赖它的检查」（X6 的核心）。
3. 规范化**只用于比较**，原文逐字保留在文件里（不改被检产物，E1）。

**适用字段**：`Feedback` / `Blocker type` / `Recovery eligible` / `Accepted` /
`Human confirmation required` / `Safe without user input` / `Scope-lock required` /
`Loop continuation`。

### B.7 v3.1 的 teeth 增补

| # | 断言 | 破坏性反证 |
|---|---|---|
| **L13** | 已启用状态下契约缺 `Profile:` → `loop-contract-profile-missing`；未启用状态下无影响 | 退回「skip + 计数」→ 零违规关门旁路复活 → 红 |
| **L14** | strict 档不报 anomaly；lite 档在 negative + minimal-fix 时**报**；standard 档同情形**不报** | 三档一视同仁 → 红（这条焊死 §0 的订正裁定） |
| **L15** | `loop_anomalies_unacked > 0` → continue 返回 `needs-human`；写一行 ack 后转 `allowed` | continue 不读该计数 → §4 执行力归零 → 红 |
| **L16** | `Human confirmation required: no（说明）` 规范化后匹配 `no`；`no（说明）` 写成 `nope（说明）` → `unrecognized-value` | 不做规范化 → 14/14 轮全部 unrecognized；做了规范化但对未知值 fail-open → 下游检查静默失效 → 两个方向各一条反证 |
| **L17** | successor 只有 `scope-lock.md` + `round-summary.md`（无 decision）→ `successor-incomplete` | 沿用「二者之一」→ 空壳过关 → 红 |
| **L18** | 迁移 manifest 含 `baseline_commit`，且在该 commit 上复算 preimage 摘要一致 | 无 commit 锚点 → 第三方无法复算 → 红 |

### B.8 与 X1-X9 的对照（更新综合文档末尾那张表的「批2 v3.1」列）

| 约束 | v3.1 |
|---|---|
| X1 锚点不可删 | ✓ B.1 |
| X2 路径身份 | 不涉及（本面无新路径比较；`legacy_rounds` 条目按既有 `_is_contained` 校验） |
| X3 解析纪律 | ✓ `loop-continuation-legacy.json` 按 X3 加重复键/类型/递归未知键校验 |
| X4 teeth 断言性质 | ✓ v3 的 L9 已是正例；B.7 六条均配破坏性反证 |
| X5 极性 + 反向限制 | ✓ B.3/B.4 均止步于「记录并暴露」，不强制可被廉价满足的形式 |
| X6 未知枚举 | ✓ B.6 |
| X7 输入侧泄漏 | ✓ `legacy_rounds` 为项目内相对路径，加载期拒绝 `://`、`~/`、绝对路径 |
| X8 门不发网络 | 不涉及 |
| X9 追溯 vs E1 | ✓ v3 §6 + B.5 的 `baseline_commit` |


---

## 附录 F：v3.2 订正 —— `continued:` 方向反转（2026-07-28，实现前发现）

> **本附录发现于实现启动时，晚于 T-076/T-077/T-078 三轮对抗审，三轮均未触及。**
> 它推翻的是 §2.2 的载体与方向，不是 §2.2 想守的性质。

### F.1 致命的时序问题

协议规定机械门在 **Loop Continuation step 1、写 `decision.md` 之前**跑且须 exit 0
（`loop/SKILL.md:442`）。于是当轮 0010 收盘、要写 `- Loop continuation: continued: 0011` 时：

**轮 0011 还不存在。** §2.2 约束 1（successor 目录存在）与约束 4（successor 最小完整性）
当场不成立 → `loop-continuation-successor-missing` → 判红 → 该轮不得 positive。

**`continued:` 在收盘那一刻结构上写不出来。** 两条出路都不通：

| 出路 | 问题 |
|---|---|
| 收盘先写 `stopped:`，以后再改 `continued:` | **改已收盘轮的 decision.md，撞 v0.12.0 E1** |
| 收盘前先建好 0011 的骨架 | 轮 0011 在没干活前就有 round-summary，时序倒置 |

**规格自身的语义词是 `successor-observed`——「observed」本就暗示事后记录**，
而规格全文**没有一处说该字段何时写**（grep「写入时/收盘/何时写/时序」零命中）。
这个缺口就是问题的来源。

### F.2 订正：方向反转

> **不在前一轮写 `continued: <后继>`；改在后继轮写 `Predecessor: <前一轮>`。**

**依据一条更一般的规律（本次总结，值得单独记住）**：

> **向后引用安全，向前引用不安全。**
> 轮 N 引用轮 M<N：M 早已存在且冻住，判定在 N 收盘时即可完成，且此后永不改变。
> 轮 N 引用轮 M>N：M 尚不存在，判定在 N 收盘时必然失败，只能事后补写（撞 E1）；
> 且一旦补写成功，M 的任何后续变动又会追溯改变 N 的判定。

反转后 §2.2 五条约束的处置：

| 原约束 | 反转后 |
|---|---|
| 1. successor 目录存在 | → **前驱目录存在**（收盘时已成立） |
| 2. 严格前向 | → **前驱轮号 < 本轮**（纯算术） |
| 3. 无环 | → 由 2 直接蕴含（严格递减不可能成环），**整条删除** |
| 4. successor 最小完整性 | → **前驱完整性**（前驱已收盘，本就完整） |
| 5. 双向绑定 | → **不再需要**：只有一个方向，无从不一致 |

**五条变两条，且两条都在收盘时可判、此后永不翻转。**

### F.3 对其余各节的影响

- **§3 记录层**不变（`stopped: <reason>` 仍写在停下的那一轮）。
- **§4 异常层不受影响**：它问的是「最新一轮本该续却没续」，判据是「该轮之后有没有出现
  更晚的轮」，**压根不需要 `continued:` 字段**——反而比原设计更直接。
- **§2.3 `historical-unrecorded` 与 §6 迁移**：反转后，历史轮不再需要写任何东西
  （前驱引用只由**新轮**写），**整个 legacy manifest + 迁移工具可以删除**。
  这同时消掉了 §6「迁移要逐字节改 14 份历史 decision.md」与 E1 的紧张关系。

### F.4 如实登记

- 本订正**缩小**了机制的声称范围：原设计声称能表达「我续到了哪一轮」，反转后只能表达
  「我接自哪一轮」。**一个从不写 `Predecessor:` 的新轮，链条上就是断的，门抓不到**——
  与 v0.28.0 `Acceptance evals:` 的上界同族（「一旦声明就必须自洽，保证不了必须声明」）。
- 反转后仍是**跨轮读取**（本轮读前驱目录），但方向决定了它**不会追溯判红**：
  前驱已冻结，本轮判定一次成立后不再受未来影响。这与 TH-0027 记录的七类**性质不同**——
  那七类是今天的编辑改变已收盘轮的结论。
