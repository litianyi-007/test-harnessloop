# harnessloop 进化定案计划（合成报告，2026-07-26）

> 语料基础：评估报告 + T-058/T-059 双轨 + 六簇「设计→对抗证伪」全量 + 本次在 HEAD `98d38e0` 上的现场实测。
> 18 个提案里 **1 个整体放行、1 个拆包后 2 个子项放行、16 个被证伪**。以下所有数字均为本次亲自跑出来的，不是转述。

---

## 1. 一句话结论

**这轮只做一件事：让已经存在的机械门停止说谎，并让「判断发生过」这件事留下可 grep 的痕迹。**
不做的是：任何新 DSL、新解析器、新单一事实源、新生成器、新账本、新计数仪表——本仓 10 个 evolution issue 里有 6 个（0001/0004/0006/0007/0008/0009）出自散文解析器，0008 至今 open，本轮**不新增第 7 个解析面**。

落地量：**6 个文件、约 145 行（其中 80 行是 CI fixture）**，`.harnessloop/` 侧**零迁移**（已实测 14/14 轮在新规则下不变红）。

---

## 2. 问题重核结果

### 2.1 重核后仍然属实（带本次实测证据）

| # | 问题 | 实测证据 | 本轮处置 |
|---|---|---|---|
| A | **机械门结构性空跑**：Rule A 挂在 `verify_protocol.py:260` 的 `if checked_files:` 下 | 全库 14 轮中 **9 轮**零工件受检；Rule A 历史累计只判过 **8 个文件**，Rule B 只扫过 **3 个文件**（全在 goal 001，goal 002 十轮 `reviews/` 为 0）。今天跑 `verify_protocol.py --project .` → **EXIT=0 + "All mechanical protocol gates passed"** | **本轮 P0，E1+E2 关闭** |
| B | **门被跑过与否在协议内不可查** | goal 002 十份 decision.md 对 `verify_protocol` 逐份 grep = **0/10 命中** | **本轮 E3** |
| C | **协议缺"部分 pass"词汇** | 10/10 轮 `Feedback: positive` + `Accepted: yes`，其中 0005/0006 是轮内多次 REWORK/MUST-FIX 后收盘；0001 写的是 `Accepted: yes（追认已交付工作、归位状态）`——诚实性靠往枚举里塞注解维持 | **本轮 E4（唯一进协议正文的自创机制）** |
| D | **Rule B 对真实审查文风不可用（TH-0008）** | 对 `.hopper/handoffs` 61 份产物模拟 Rule B：**1037 条引用 / 524 条判 dangling = 50%**。TH-0008 状态 `open`，其自身文本写明"持续性维护负担而非一次性缺陷" | **列为最高优先「后做」，且是一切扩面的硬前置** |
| E | 审查产物全在协议之外 | goal 002 rounds/0001–0010 **全部 `reviews/`=0**，约 20 次评审产物在 `.hopper/handoffs/` | 后做，前置 D |
| F | 状态文件巨块化 | `goal-breakdown.md` 139,537 B、单行最长 18,174 UTF-8 字节（码点 11,276）、`###` 标题行 5,838 UTF-8 字节（码点 3,744）；`current.md` 28,447 B | **本轮不做**（三个提案全被证伪，且落点与病灶错位，见 §3 不做栏） |
| G | `current.md:9` `Last accepted round` 与 10 份 `Accepted: yes` 不符 | 字段作用域协议从未定义；对 goal 001 而言该值**是正确的**，错的只是后面那句括号注解 | 记为 issue + 项目侧一次编辑，**不建门** |
| H | delegation gate 0 次触发 | `environment.md` 有 5 个字面 `TODO (owner: user)`、`## Result` 写 `Pass/fail: pass` | 记为 issue，**本轮不改**（真正的"门"根本不存在：`harnessloop-continue/` 下无任何脚本） |
| I | intake 0 次使用 | `self-check.md` 明写"不适用（非接管）" | 合理未用，**不改** |

### 2.2 经重核已消解 / 被降级（不要再按原命题立项）

| 原命题 | 证伪依据 |
|---|---|
| 「随轮线性膨胀，round 记录该只追加不重写」 | git churn 实测：`self-audit.md` +939/−36（96% 纯追加）、`evidence-index.md` +57/−1。真正的重写热点只有 `current.md`（+187/−165，88% 改写既有行）。按"膨胀"立项会打错靶子（去删 self-audit 这座观察金矿） |
| 「缺确定性 next-action resolver（DAG + 打分排序）是 S0」 | 10 轮零可指认选序错例；resolver 必须从 139KB 散文里解析 DAG 再输出自信排名，正是本仓翻车三次的同一模式 |
| 「round-summary 与 decision 70%+ 内容重复」 | 12-shingle 实测：containment 22–34%、Jaccard 10–17%。逐字重复只有约 1/5，其余是同批事实的不同措辞复述——**"用生成器消除重复"是错方向** |
| 「harnessloop-issue 使用 0 次、`.harnessloop/issues/` 为空」 | 该目录根本不存在；实际落点 `meta/evolution-issues/` 有 10 条（8 fixed / 2 open），实现期是 1 条不是 0 条 |
| 「10 轮全 positive ⇒ 四分类失效，应扩枚举」 | 跨阶段有区分度（goal 001/0001 是 negative）。缺的不是枚举宽度，是**轮内审查生命周期无协议载体** |
| 「可 git diff 的审计轨迹仍然有效」（保留清单第 4 条） | 字节层为真、评审层已假：一次 diff 输出的是两堵 1,000–3,900 字符的字符墙。**这条从"保留价值"降为"待修问题"**，但本轮不修 |

---

## 3. 执行计划

### 3.1 先做（本轮五条，全部落在 harnessloop submodule）

统一原则：**本轮不新增任何"需要判断内容"的机械判定；新增的两处 exit≠0 面已在今天的真实语料上验过零新红。**

---

#### E1 · 机械门边界声明（含实测覆盖面事实）
*来源：簇3-P3 ①②（唯一整体 do-now），按对抗方要求加固*

**落点**：`/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md`，`## Verification Phase` 首段（现 :442 的 "A mechanical pass is not a protocol pass"）之后新增 `### Mechanical Gate Boundary`。

**改法**（约 22 行）：
- **IN**（当前由机械门判定）：scope-lock 存在性与 Allowed Changes 可解析性；round 内 `evidence/`、`reviews/` 下文件对 Allowed 的包含性；`reviews/*.md` 内反引号 path-ish 引用的存在性。
- **OUT**（措辞用 "currently not decided by the mechanical gate"，**不写"永远不可机械化"**）：证据是否支持结论 / 阈值是否达成 / 测试是否真的断言了东西 / pass 措辞是否诚实 / 业务代码改动是否越界。
- **覆盖面事实一句（对抗方加固项）**：Rule A 只看 `evidence/` 与 `reviews/`，Rule B 只看 round 内 `reviews/*.md`；两者都不看业务代码改动、不看 `.harnessloop/state/`。**因此 exit 0 不得读作"全轮产物都被检过"。**
- **一条操作性纪律**：机械门失败时，除非被检产物确实写错，**不得通过修改被检产物转绿**；门判错的正确修法是 `$harnessloop-issue` + 显式豁免标记。scope-lock 在本轮已产出 evidence 之后被修改的，必须在 decision.md 记一行理由。

**验收**：`grep -n 'Mechanical Gate Boundary'` 命中；小节含全部 OUT 项 + 覆盖面事实句 + 那条纪律。

**teeth（诚实版）**：**这条没有机械 teeth，它是纪律不是门**——不要假装它有。它的执行力全部来自 E3（留痕）与 E5（审查必查项）。唯一可测的一点：把 E2 输出的 coverage 字段与本小节 IN 列逐项对照，不一致即文档在撒谎。**任何声称它能拦住什么的说法都是假绿。**

**成本**：1 文件 ~22 行。**依赖**：与 E2 同 PR（IN 列必须与 coverage 字段一一对应）。

---

#### E2 · `verify_protocol.py` 两项最小改动：覆盖遥测 + scope-lock 检查脱离守卫
*来源：非任一提案原案。由簇3/簇5/簇6 三簇独立确诊同一病灶 + 簇3 对抗方 better_alternative 的最小交集推导得出。标注为 **B 档**：未经独立对抗轮，但它在结构上无法新增绿灯（不改 exit code 语义），假绿面为零。*

**落点**：`.../skills/harnessloop-loop/scripts/verify_protocol.py`

**改法 (a)**（约 8 行）：`verify_round()` 把 `scope_lock.exists()` 与 `extract_allowed_spans()` 非空这两项检查**移出 `:260` 的 `if checked_files:` 守卫**，改为对每个 round 目录无条件执行；包含性判定仍留守卫内（有 artifacts 才判包含）。**不新增 violation kind**（沿用 `missing-scope-lock` / `unparseable-allowed-changes`）。

**改法 (b)**（约 22 行）：`verify_round`/`verify_project` 返回 `(violations, coverage)`，累计 `{rounds, rounds_zero_inspected, rule_a_files, rule_b_files, citations_checked}`；`main()` **无条件打印一行 coverage**，且当 `rounds_zero_inspected > 0` 时**禁止**打印无限定的 `All mechanical protocol gates passed`，改打印：

```
passed — rounds=14 rule_a_files=8 rule_b_files=3 citations=N zero_inspected=9
(a clean exit for those 9 rounds means "nothing to check", not "checked and clean")
```
`--json` 增 `"coverage"` 键。**exit code 语义完全不变。**

**验收（数字已实测，今天就能对）**：
1. `python3 -B .../verify_protocol.py --project .` → EXIT=0，stdout 含 `rounds=14 rule_a_files=8 rule_b_files=3 zero_inspected=9`，且不出现无限定的满分横幅。
2. 改动前后 violations 逐项相等（14 轮全空）——**已实测**：14/14 轮 scope-lock 存在且 spans ≥2（最少 2、最多 18），脱离守卫零迁移、零新红。
3. `--json` 的 `coverage.rounds_zero_inspected == 9`。

**teeth（双向，全部进 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop/scripts/validate.py`）**：
- **正向必红**：造一个无 `scope-lock.md`、无 evidence/reviews 的 fixture round → 今天 EXIT=0，改后**必须 EXIT=1 报 `missing-scope-lock`**。这是 m7（`harnessloop/adversarial-review-p0.md:101`，自 P0 轮标为"不阻塞"挂到今天）第一次被真正关闭。
- **反向必绿**：14 个真实 round 跑完 violations 仍为 0（防止拿误报换漏报——TH-0006 的 6/6 误报是本仓最贵的一次教训）。
- **遥测承重反证**：把 `rounds/0009/evidence/` 临时移走，`rule_a_files` 必须 8→6、`zero_inspected` 9→10；不变即遥测没接线。
- **既有 fixture 盲点必须同时修**：`validate.py` 现有每个 fixture 都先 `mkdir evidence/reviews`——**测试集盲点与门盲点同构**，这正是门空跑 10 轮而 CI 一直绿的原因。新增的"无 evidence/reviews"fixture 是本条不可省的一半。
- **假绿自省**：这条改动**不新增任何判定力**，只让绿灯说清自己检了什么。它唯一可能的假绿是"覆盖数字算错却无人察觉"，由上面三条反证兜底；它**不可能新增绿灯**，因为 exit code 语义未变。

**成本**：1 文件 ~30 行 + validate.py ~40 行。**依赖**：无（可最先落）。

---

#### E3 · 机械门执行留痕进 decision.md
*来源：簇3-P3 ③④（do-now），按对抗方要求改成硬性可 grep 格式*

**落点**：
- `.../references/decision-template.md`：`- Accepted:`(:9) 之后加一行
  `- Mechanical gate: <exit-code> / <verify_protocol.py 的 coverage 行原文> / <运行时刻>`
- `.../skills/harnessloop-loop/SKILL.md` Loop Continuation step 1 末尾加一句：`Record the gate's exit code and its coverage line verbatim in decision.md. A round whose decision.md lacks this line has not completed step 1.`

**验收**：模板 grep 命中；下一轮 decision.md 可 grep 到该行，且 coverage 数字与当轮实跑一致。

**teeth**：**基线是 0/10**——goal 002 全部十份 decision.md 对 `verify_protocol` 零命中，也就是说这个门十轮里连"被声称跑过"都没有。teeth 即：**下一轮若 decision.md 仍无此行，本条判失败并回滚**。
诚实承认它会退化成套话（模型会复制粘贴）。但即便退化成套话，也**严格优于无记录**：它第一次让"这轮到底跑没跑、检了几个工件"变成可 grep、可被 E5(b) 审查必查项抽查的事实。**它买的是审计轨迹，不是控制力，必须照这个卖。**

**成本**：2 文件 ~4 行。**依赖**：E2（coverage 行必须先存在，否则抄的是那句会撒谎的横幅）。

---

#### E4 · 措辞诚实性硬化：`Verdict` / `Residuals` 两字段 + 一条同文件枚举矛盾检查
*来源：簇6-P3 拆包后的 D1（对抗方逐条评为"全批最强的一项"），按其要求收缩到约 5 行脚本*

**落点**：
- `.../references/decision-template.md`：`- Feedback:`(:6) 之后加两行
  - `- Verdict: pass | pass-with-residual | fail | inconclusive`
  - `- Residuals: none | <一行一条：声称了什么 / 哪部分未覆盖 / defer 去向>`
- `.../scripts/verify_protocol.py`：加约 5 行规则——同一份 decision.md 内 `Verdict: pass` 且 `Residuals` 非 `none` → violation kind `verdict-residual-contradiction`。
  **硬性设计约束：只做同文件内两个枚举行的比较。不解析散文、不做路径解析、不跨文件 join、不做值归一化。**
- `.../skills/harnessloop-status/SKILL.md`：Output Contract 加 1 行，报本 goal 内 `pass` / `pass-with-residual` 的分布。

**验收**：
1. fixture `Verdict: pass` + `Residuals: L2 未覆盖` → EXIT=1、kind 精确匹配；改成 `pass-with-residual` → EXIT=0。
2. 对 14 个既有 round（无这两字段）→ **必须不报错**（缺字段不判违规，只在两字段都存在时比较）。这条保证零迁移成本。

**teeth**：
- 双向 mutation 进 validate.py，pass/fail 两个方向都必须翻转。
- **反向必绿**：14 个真实 round 仍 0 violations。
- **假绿自省（必须写进 SKILL 措辞）**：`pass-with-residual` 一定会沦为默认对冲词，**没有任何机械手段能防住**。所以本条买到的只有一件事——`Verdict: pass` 且 `Residuals` 非 none 成为一个**后来的读者/审查者能机械找到的矛盾**。status 的分布行只是让漂移可见，不是控制。

**为什么这是本轮唯一进协议正文的自创机制**：缺席可从协议本来就要求的工件里、用同文件内枚举比较这一级操作机械检出，**零内容判断、零解析器**。协议现有词表里没有"部分 pass"，项目自己发明成了 `PASS_WITH_NOTE`——这正是"不吸收即失传"代价最大的一条。

**成本**：3 文件 ~11 行 + validate.py ~30 行。**依赖**：E2（同一脚本、同一 PR，避免两次改 verify_protocol）。

---

#### E5 · 反僵化护栏 + 审查必查项
*来源：簇6-P3 拆包后的 D4（对抗方评为"本批最好的主意，无条件保留"）+ 簇3-P3 ⑥*

**落点 (a)**：`harnessloop/scripts/validate.py` 加一条断言：grep 整个 `skills/` 与 `scripts/`，**不得存在任何断言"本轮执行过 falsification check / teeth"的规则或字段**。
**落点 (b)**：`.../references/adversarial-review-template.md` 的 Checks 表加两行：
```
| Scope-lock post-hoc edit | unknown | git log -p -- <round>/scope-lock.md | 若本轮 scope-lock 在 evidence 产出后被改，decision.md 必须已记理由 |
| Mechanical gate record | unknown | <round>/decision.md | 必须含 Mechanical gate 行且 coverage 与实跑一致 |
```

**验收**：(a) CI 断言存在且今天为绿；(b) grep 命中两行。

**teeth**：(a) 是构造性的——往 `skills/` 里塞一句 `The round must state that a falsification check was performed`，CI **必须挂**。(b) 没有机械 teeth，靠异构审查员判断——**这正是它相对被砍掉的 mtime 探测器的优势**：实测 0009/0010 两轮 scope-lock mtime 均晚于 evidence（2/2 假阳性），而两轮都是自审判定"全程未扩围"的干净轮；同时该轮全部产物落在同一个 commit `184d6a7` 里，按 commit time 判定则恒等哑火。**一个既会在干净轮乱叫、又会在真出事时沉默的信号，比没有更糟。**

**成本**：2 文件 ~10 行。**依赖**：(b) 依赖 E3。

---

**顺手可选项（不单独立项、不影响本轮结论）**：`harnessloop-continue/SKILL.md` 让 check_setup 在 JSON **全量指纹**与上轮一致时只打一行摘要（照跑不照抄）。前提是指纹必须基于全量 JSON 而非人工摘要，否则折叠本身会掩盖变化。

---

**落地顺序与总量**

| 顺序 | 内容 | 文件 | 行数 |
|---|---|---|---|
| PR1 | E1 + E2 | SKILL.md、verify_protocol.py、validate.py | ~92 |
| PR2 | E3 + E4 | decision-template.md、verify_protocol.py、SKILL.md、harnessloop-status/SKILL.md、validate.py | ~45 |
| PR3 | E5 | validate.py、adversarial-review-template.md | ~10 |

合计 **6 个文件、约 145 行（80 行是 CI fixture）**。落地后须按 CLAUDE.md 既定流程 bump harnessloop 版本再 push，并 `scripts/plugin-reinstall.sh harnessloop` + **重启会话**后复验——否则复验的是旧版本。

---

### 3.2 后做（第二批，每条带硬前置）

| ID | 内容 | 前置条件 | 为什么不是现在 |
|---|---|---|---|
| **B1** | **修 TH-0008**（Rule B 承接语境的相对片段引用误报） | 无，可立即排 | 这是解锁一切"把审查产物纳入协议账本"的**唯一钥匙**。实测 50% 误报（524/1037）。在它关闭前，任何扩大 Rule B 覆盖面的动作都是把已确诊的误报生成器指向仓库里最不受控的文本 |
| **B2** | 评估「decision.md 必须声明 `- Review: <path>` 或 `- Review: none — <reason>`」，让 `reviews/` 首次真正出现，从而**首次激活** Rule A/B | B1 关闭 **且** 对 `.hopper/handoffs` 同一语料复测误报率降到个位数百分比 | 现在做 = 每轮吃 50% 误报 = 立刻规模化复现"改被检文件转绿"的病理 |
| **B3** | `scope-lock-template.md` 加 `## Driving Model (optional — delete when not applicable; never write "N/A")`，正文是**三条提示句而非字段**（阶段与闸位 / 验收分层 must-besteffort-deferred+承接方 / 收敛守卫何时停下问人） | E1–E5 跑满 1 轮 | 属"增加可移植性"的第二主线，且它**没有 teeth**（纯提示句无法验证是否起作用）。与有 teeth 的五条混在一起会稀释本轮的验收纪律 |
| **B4** | `goal-breakdown-template.md` 承认「每阶段一张表」或独立 `## Implementation Subgoals`，**不配 lint、不配迁移脚本** | 无 | 实测本仓法定 `## Subgoals` 表（:176-185）装的是已死的 RA-L1..RA-L4，真实 SG-1..SG-14 住在两张自造中文表里。根因是**法定表是需求分析形状**，不是缺两列——补列改不了这个 |

---

### 3.3 不做（16 个被证伪提案 + 3 个被砍子项，逐条写明证伪理由）

**簇1 驱动力归属**
1. **提案1（scope-lock 三节可选脚手架）— redesign→不做**。因果论证被证伪：`rounds/0005/scope-lock.md:9` 原文写着"驱动模型…（用户 2026-07-24 指定）"，阶段/闸模型来自用户指令，不是"模板里看不到这个选项"。"已收敛的形状"实测只在 2/10 轮以表格出现，0009 是并行双轨散文；teeth #3 实测已死（self-audit 对 0002–0010 每轮各有一条，旧措辞下 0006 已触发）。→ 缩水版移入 B3。
2. **提案2（next_candidates.py 就绪集脚本）— drop**。解析目标在唯一真实语料里不存在（有 Status 的表脚本找不到，能找到的是死表）；真实决策粒度是 SG-8.1/SG-10-L1 这类单元格内子项，不是行；软依赖（"不阻塞骨架搭建"）与跨阶段依赖（"SG-10 各阶段"）会被自信解析成错误结论。
3. **提案3（审查闸放置四条触发条件）— redesign→不做**。判据从零反例数据集拟合而来，无可测增量；条件 4（executor 同时写自己的验证）在本项目委派模式下**恒真**——恒真的条件不是启发式，是强制令；且落点悬挂依赖提案1 的可选表。

**簇2 状态文件**
4. **P1（state_view.py 派生视图）— redesign→不做**。"只读枚举行不解析散文"实测为假：14 份 decision.md 中 `Recovery eligible` 11/14、`Action type` 9/14、`Blocker type` 8/14 为"枚举+中文注解"；把 `yes（追认已交付工作、归位状态）` 归一化成 `true`，正是把本项目最有效的纪律（措辞诚实性）反向做进工具里。
5. **P2（current.md frontmatter + state_lint 派生一致性门）— drop**。设计上豁免正文，稳定态是"门全绿、人读的那句仍然是假的"；`active_round`/`active_goal` 结构上不可从目录派生（archive/cancel 保留目录）；最坏故障模式是"derive 判错时唯一转绿的办法是把错值写进被检文件"。
6. **P3（goal-breakdown Status/Rounds 列 + 迁移脚本）— drop**。落点是本项目已废弃的死表；法定 `## Subgoals` 内 >600 字符行 = **0**，可迁移单元格 = 0，teeth(a) 的断言循环一次都不执行。→ 根因移入 B4。

**簇3 机械门**
7. **P1（fenced ```scope 块 DSL）— redesign→不做**。真实条目 `{swift,csharp}` 在 git pathspec 下匹配零文件；"祖先目录必须存在"对"本轮新建目录"是结构性误报；且 `.harnessloop/** + app/**` 三行完全良构、三项校验全绿而判定力为零。→ 最小交集（脱守卫 + 遥测）已提取进 E2。
8. **P2（Rule A2 真实改动集包含性）— redesign→不做**。方向矛盾：Rule A 奖励窄声明、A2 惩罚窄声明，唯一稳定均衡是把声明写宽到 A2 闭嘴，同时 A1 失去全部判定力。实测在最干净的 0009 轮打出 ~47% 违规率，其中 6/7 是**协议自己强制要求写的文件**。
9. **簇3-P3 的 ⑤（scope-lock-modified-after-evidence 探测器）— 砍**。理由见 E5 teeth（2/2 假阳性 + commit-time 恒等哑火 + mtime 被 clone/checkout 抹平）。**这是 P3 里唯一伪装成机械证据的部分，正好违反 P3 自己第②条的精神。**

**簇4 收官成本**
10. **方案B（Rule C 跨文件字段一致性）— redesign→不做**。原型实测 current.md 每个叶字段是 53–2030 字散文（`Current feedback` 2030 字），要同时过真实项目与 mock-project 就必须写路径 normalizer + 散文前缀 token 抽取器——正是反面教材本身。且它对"prompt 错则六处全错"的均匀广播**完全免疫**。
11. **方案C（收官写入集枚举 + 引用不复述禁令 + delta self-audit）— redesign→不做**。自我证伪：`SKILL.md:499` 原文就是条件触发规则，项目照样写了 15 个全量块 106KB；AC2 的 shingle 判据口径不明且方向反了（字面 n-gram 重叠主要由共享标识符驱动，而"引用不复述"恰恰引用这些 token）。→ 其中唯一不可移植的知识（"收官到底写哪七处"）降级为 evolution issue #7，本轮只记录不修。
12. **方案A（round-record.md 单一事实源 + closeout.py）— drop**。700 行打的是最不值钱的 20%；`--apply` 后 `--check` 必绿是同义反复；optional 填 `n/a` 即可产出全协议最强的绿灯。

**簇5 feedback/verdict**
13. **P1（Review Gates 闸账 + verdict 出处校验 C2）— redesign→不做**。C2 在真语料上被跑穿：`T-045-output.md:119` 是 brief 菜单行、逐字含 `MUST-FIX`；`T-048-output.md` 中 `REWORK` 出现在 L63/L73/L148/L179 四处，对 C2 完全等价。**该案自称的"验收演示"是假的，teeth(b) 在真语料形态下必然零告警。**
14. **P2（Rule D 收口方式声明 + 阈值下沉 profile）— drop**。teeth(b) 可被"加一行自撰的更高 Attempt 通过行"一招拆掉，逃逸成本 = 一行表格；且验收判据要求"0006 = 3 attempts"，而 0006 自己写的是"2 个 MUST-FIX"，人读历史本身就有两个数。
15. **P3（review_ledger.py 只读仪表）— drop**。验收循环（用闸账验证闸账）；"零协议表面积"是假的（改随包 status 契约）；teeth 挂在一个已被证伪的 teeth 上。**四个数今天用 `.hopper/queue.md` 一条 grep 就能拿到，且来源是 dispatch 时刻写入而非收盘时刻自报。**

**簇6 低使用率**
16. **P1（issue 三态 + seed 层 + 老化面）— drop**。这个机制已经在本仓跑过并失败了：`field_todo_count: 12` 每轮被协议强制展示、10 轮响应 **0**（goal 002 目录内 grep 命中 0）。**用自报数替代"自动算出来还被无视的数"，方向是反的。**
17. **P2（delegation 来源枚举化）— redesign→不做**。它要硬化的那道门**没有机器**（`harnessloop-continue/` 下只有 SKILL.md 和 agents/openai.yaml），所以只是把"LLM 读的散文"换成"含枚举的、仍由 LLM 读的散文"；且 ack 被设计成一次 commit 后永远不再响。→ 记为 issue #8，先裁定语义再谈改脚本。
18. **簇6-P3 的 D2（Review artifacts 字段 + Rule B 扩到树外）— 砍**。自愿声明基率实测 0/10；真列了则吃 50% 误报。→ 前置条件化后移入 B2。
19. **簇6-P3 的 D3（Review reject count 进 self-audit）— 砍**。自报抄自报，与 D1 的 Verdict 之间无任何一致性约束。

---

## 4. 核心辩题裁定

**统一判据（本次进化的方向性结论）**：

> 当且仅当某机制的缺席可以从**协议本来就要求的工件**里、用**同文件内枚举比较**这一级的操作机械检出时，才吸收进协议正文。
> 凡执行它需要**内容判断**的，一律不吸收。
> 凡需要**新解析器、跨文件 join、路径归一化**的，本轮一律不吸收——本仓 10 个 evolution issue 里 6 个出自这类解析器（0001/0004/0006/0007/0008/0009），其中 0008 至今 open 且实测 50% 误报。

| 自创机制 | 裁定 | 理由 |
|---|---|---|
| **措辞诚实性**（不得把"部分 pass + residual"折叠成纯 pass） | **吸收，协议硬约束**（E4） | 唯一满足全部三条判据的一条：缺席可从 decision.md 机械检出，判定是纯枚举矛盾，零内容判断、零解析器。实测 10/10 轮塌缩成 `positive`+`yes`，"不吸收即失传"的代价最大。**本轮唯一进协议正文的自创机制。** |
| **teeth（破坏性反证）** | **不吸收进协议正文；吸收进插件自己的 CI 测试集**（E2/E4 双向 mutation + E5(a) 反仪式护栏） | 这是本轮最重要的方向性区分。作为**每轮用户仪式**不可吸收——任何机械版本只能退化成"你有没有写一句说自己做了 teeth"，那是保证产生假绿的写法。作为**插件测试纪律**应当吸收，边际仪式成本为零（CI 跑一次），且它正好治本仓已确诊的病：`validate.py` 每个 fixture 都先 `mkdir evidence/reviews`，**测试集盲点与门盲点同构**，所以门空跑 10 轮而 CI 一直是绿的。 |
| **异构轮换审查** | **记录应吸收、策略永不吸收；但本轮不落**（B2） | 记录（审查产物在哪、审查者是谁）本该吸收——实测 goal 002 十轮 `reviews/`=0、约 20 次评审全在协议账本之外。但落地会让 `reviews/` 被填满，而实测 Rule B 对真实审查文风误报 50%、TH-0008 open。**前置写死：TH-0008 关闭 + 误报率复测降到个位数。** 轮换策略（必须换 vendor）永不吸收：它需要一份 harnessloop 并不拥有的 vendor 名册，等于把 hopper 形状焊进协议；留在项目 control-contract / CLAUDE.md。 |
| **诚实分层 defer**（L1 / L2 / 本轮不做+承接方） | **吸收，但只以"一句提示"的形态，且排到第二批**（B3） | 不吸收为字段/必填节：0005 的阶段模型来自用户指令而非模板缺失；表格形状只在 2/10 轮出现，0009 是并行双轨——把品味硬化成顺序表会**逼真实轮次撒谎**。它是三方公认 top-3 保留价值，但它是叙事纪律，而本轮裁定原则是"叙事纪律不硬化"。 |
| **收敛守卫**（同阶段第 3 个 MUST-FIX 停下问人） | **明确不吸收，连 self-audit 计数行也不加** | 10 轮触发 **0** 次；同一会话内阈值措辞漂移三种写法、计数口径漂移两种（0006 把 REWORK 当 MUST-FIX 计，0008/0009 按 REWORK 计）；self-audit 的计数将是"自报抄自报"。此刻把一个未被检验、口径未稳的数字写进随包 profile，是**以"有阈值"冒充"有收敛控制"**。保持项目级实例。 |
| **驱动力归属**（选 SG / 分阶段 / 闸位判据） | **不吸收任何硬约束，也不做 resolver** | 10 轮零选序错例，要修的是"理由不落盘"不是"选得不对"；resolver 必然要从 139KB 散文解析 DAG 再输出自信排名。闸位四条判据从零反例数据集归纳而来，无可测增量。 |

**总账**：6 条里 **1 条吸收进协议正文、1 条吸收进插件 CI、2 条附前置条件后置、2 条明确不吸收**。
一句话概括：**吸收「记录的形状」，不吸收「判断的内容」；且本轮只吸收那些用同文件内枚举比较就能检出的记录。**

---

## 5. 应记为 evolution issue 的条目

可直接用 `harnessloop:harnessloop-issue` 逐条记录（格式：`[优先级] class · 一行症状 · 处置`）：

1. `[P0] skill-gap` · Rule A 在 round 无 evidence/reviews 文件时整体空跑：全库 14 轮中 9 轮零工件受检，仍打印 "All mechanical protocol gates passed"（m7 自 2026-06 P0 轮挂至今） · **由 E1+E2 关闭**
2. `[P0] skill-gap` · TH-0008 未关闭导致 Rule B 不可用于真实审查文风：实测 `.hopper/handoffs` 61 文件 / 1037 条引用 / 524 条判 dangling（50%） · **已有 issue，建议升级优先级并附本次量化数据；它是 B2 的唯一钥匙**
3. `[P1] template-gap` · 协议缺"部分 pass"词汇：feedback 四分类 + Accepted 二值无法表达"轮内多次 REWORK 后收盘"，10/10 轮塌缩为 positive/yes，诚实性靠往枚举里塞中文注解维持 · **由 E4 关闭**
4. `[P1] workflow-gap` · 机械门执行无留痕：10/10 份 decision.md 对 `verify_protocol` 零命中，门是否被跑过在协议内不可查 · **由 E3 关闭**
5. `[P1] template-gap` · 法定 `## Subgoals` 表是需求分析形状，实现阶段装不下，导致项目另起 5 张自造表（含自造"状态"中文列） · **B4**
6. `[P2] template-gap` · scope-lock 模板无"驱动模型 / 阶段与闸位 / 验收分层"的合法落点，6 轮自创且形态三种（表 / 三行散文 / 并行轨小节） · **B3**
7. `[P2] workflow-gap` · 收官写入集实为 7 处（round-summary / decision / self-audit / current.md / evidence-index / goal-breakdown / thresholds），协议 Loop Continuation 只编号了 3 个写入动作，其余只活在主会话 prompt 里，换会话即失传 · **本轮只记录不修**（方案 C 的执行力已被"条件触发规则被无视 15 次"实证证伪）
8. `[P2] 待定` · `environment.md` `## Result` 写 `Pass/fail: pass`，而同文件 5 个叶字段值为字面 `TODO (owner: user)`；`check_setup.py` 报 `state: filled 21/21` + `complete: true` 同时 `field_todo_count: 12` · **需先裁定这是项目侧数据错误还是脚本语义缺口——`TODO (owner: user)` 是设计上的 owner 归属占位符，裁定前不要改脚本**
9. `[P3] state-hygiene` · `current.md:9` 的括号注解"本 goal 尚无已接受轮次"与 goal 002 的 10 份 `Accepted: yes` 矛盾（字段值本身对 goal 001 是正确的，作用域协议从未定义） · **项目侧一次编辑清账 + `current-state-template.md` 加 1 行口径注释；不建门**

---

## 6. 风险与回退

**回退边界**：E1–E5 全部落在 `harnessloop/` submodule，一次 `git revert` 即整批退回。`.harnessloop/` 侧**零迁移**（已实测 14/14 轮在新规则下不变红），所以回退**不需要回填任何状态文件**——这是本轮刻意压到"零迁移"的原因。

**三个具体失败面与各自回退**：

| 失败面 | 观测手段 | 回退动作 |
|---|---|---|
| E2 遥测数字算错 | coverage 与手算不符（今天的基线是 `rounds=14 rule_a=8 rule_b=3 zero=9`） | 只还原 `main()` 的打印分支；violations 逻辑与遥测在代码上解耦，不受影响 |
| E4 的 `pass-with-residual` 沦为默认对冲词 | `$harnessloop-status` 的分布行；连续 3 轮 `pass` 占比为 0 即判失效 | 保留 `Residuals` 字段、删掉 Verdict 规则（5 行） |
| E3 退化成套话 | coverage 数字与实跑不符（说明是抄的不是跑的）；E5(b) 的审查必查项应报出来 | 若审查也报不出来，则本条无牙齿，**当场降级为纯建议并记入 self-audit**——不留着当假绿 |

**硬前置（不得违反）**：任何会导致 `rounds/*/reviews/` 被填充的改动，**在 TH-0008 关闭前一律不落**。否则 50% 误报会立刻把"改被检文件转绿"的病理规模化——那正是 rounds/0009 已经发生过一次的事（同一张 Allowed 表里只有 Rule A 真正触达的那一行被拼全，其余行照错不误）。

**本轮新增的 exit≠0 判定面只有两处，且都已在真实语料上验过零新红**：
- E2(a) 的 `missing-scope-lock` / `unparseable-allowed-changes` 脱离守卫 → 实测 14/14 轮 scope-lock 存在且 spans ≥2，零新红；
- E4 的 `verdict-residual-contradiction` → 缺字段不判违规，14 个既有 round 零新红。

**这是"不拿误报换漏报"的前置证据**——TH-0006 的 6/6 误报教训是：误报比漏报更快摧毁对门的信任，而一旦信任崩塌，下一步就是学会编辑被检文件让它闭嘴。

---

## B2 口径重述与四步解锁（2026-07-27，codex T-066 评估确认 + user-confirmed）

**原前置失效**：B2 原写「B1(TH-0008) 关闭 **且** 误报率降到个位数百分比」。TH-0008 已按 `fixed-by-demotion` 结案（v0.16.0），但降级的正确代价是误报率**升到 37.8%**——原数值判据与事实冲突。它本是「防止 reviews/ 被填满后每轮吃一堵误报墙、逼出『改被检文档转绿』病理」的**代理指标**，降级后该代理与风险的相关性已断。

**主会话原提案被 codex T-066 修正两处**（如实记录）：
1. 提案称「91% 可诊断」——**混用分母**。91% 只描述「降级新增的 96 条里 87 条带提示」；全语料 401 条 dangling 中带提示的仅 **88 条 = 21.9%**（声明外部基准后 33.8%）。该判据据此**否决**。
2. 提案的「中位数 ≤1 **且** 多数为 0」**冗余**（后者蕴含前者），且**未约束长尾与 `verify:ignore` 滥用**。应按分层指标记录：zero-rate / p50 / p75 / p90 / max / 非零文档均值。

**修正后的四步解锁顺序**（codex T-066 Next recommendation）：

| 步 | 内容 | 状态 |
|---|---|---|
| **B2a** | **只入账、不入树**：`decision.md` 必须声明 `Review: <项目内路径>` 或 `Review: none — <非空理由>` + `Reviewer` + `Review verdict`（+ 可选 `Review digest` sha256）。机械门**只**验字段存在、canonical containment、存在性、普通文件非 symlink、digest 匹配；**不扫其文本、不计入 Rule A/B**。`none` 的理由只机械检查非空，**不声称机器判断了理由是否充分** | **done（v0.17.0，2026-07-27）**；14 个历史 round 已回填（10 条指向真实评审产物、4 条 `none —` 附准确理由），门 `review_missing_fields=0` |
| **外部解析基准协议面** | 项目声明额外 citation 解析基准。**硬约束**：alias-only + 独立 canonical domain；**不允许**全局 unresolved fallback；**不允许**声明落在 scope-lock；须计入 coverage 可见 | **done（v0.21.0→v0.25.0，2026-07-27）**；`@@<alias>/<relpath>` 两域不相交，三轮对抗审 T-068/069/070 收敛（第 2 轮 REWORK），核心命题「alias-only 能否被架空」三轮未破；规格 §9 有实施与验收记录 |
| **真实评审 pilot** | 少量真实评审复制进 `rounds/*/reviews/`，按分层指标记录负担；**路径检查器自评单独成层**（不拿它的 fixture 长尾否决普通评审，也不拿普通评审的中位数掩盖它） | **第 1 轮已跑，判不通过（2026-07-28）**；预算先于测量冻结（`docs/rule-ab-pilot-budget-20260728.md`），结果见 `docs/rule-ab-pilot-report-20260728.md`。§2 五阈值中 2 项不达标；暴露 2 个预算未覆盖维度（**ignore 连带压制**、**6/7 scope-lock 覆盖不到自己的 round 目录**）。须先处置后重新预登记再跑第 2 轮 |
| **B2b** | 入树并首次真正激活 Rule A/B。仅当 pilot 的分层负担、p90、人工处置时间、ignore 使用**均在预先记录的预算内**才升为全 round 硬要求 | **blocked**（pilot 第 1 轮不通过）。额外前置：`verify:ignore` 的行粒度连带压制须先在规格层处置——实测 2 个 marker 静默豁免 18 条无关引用，B2b 若在此之前生效，解锁的是一个可被一行注释大面积关掉的门 |

**代理语料的公平性**（codex T-066 §2）：`.hopper/handoffs` 混层——剔除 `leader-tasklist.md` 与"评审路径检查器自身"的元文档（T-058/062/063/064/065）后，公平代理集 59 份 / 603 引用 / dangling 189；声明外部基准后降至 120，zero-rate 18→34，p50 2→0。**但仍有 25/59 非零、非零均值 4.8、p90=7**——只支持「中央负担显著下降」，**不支持**「负担已全面可承受」，故 B2b 必须经 pilot 才能解锁。
