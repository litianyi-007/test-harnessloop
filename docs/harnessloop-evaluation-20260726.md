# harnessloop plugin 自主驱动能力评估调研报告

**日期**：2026-07-26
**范围**：goal `20260718-002-agent-app` 实现阶段 rounds/0001–0010（首批 SG-1..SG-9 全清）
**方法**：双轨异构独立调研（codex 轨 T-058、grok 轨 T-059，互不知晓对方产出）+ 主会话第一手执行侧观察，三方合成
**性质**：评估调研，非改进实施——本报告所有改进方向均为"候选"，不含实施计划

---

## 1. 执行摘要

**光谱定位结论**：三方一致判定 harnessloop 当前形态是**"有牙齿的证据化控制协议 / 高纪律文件型账本 + 控制门脚手架"，尚未跨过"由协议约束的 LLM 编排"到"由运行时驱动的自主 goal engine"的分界线**。在"纯记账协议 ←→ 真自主驱动引擎"光谱上：

- codex 轨给出 **40/100**
- grok 轨给出 **25–35/100**（约 30）
- 主会话第一手体验（未打分，但定性一致）：**"continue 驱动"的自主性来自 LLM 会话本身，协议只提供约束性（护栏），不提供驱动性（指路）**

三方对"是否越过纯记账"这一底线判断完全一致，但对具体分数存在约 10 点的分歧（见 §3 分歧点）。核心共识：goal 002 首批 SG 全清是"**纪律型主会话 × harnessloop 账本 × hopper 异构审查**"三方合力的结果，抽掉任何一方都会显著掉队——协议本身不具备自行规划、选路、收敛、验收的能力。

**Top 5 问题**（详见 §4 完整清单，本处仅摘要）：

1. **驱动力实为主会话补位，非协议产出**：选哪个 SG、怎么分阶段、审查闸设在哪、收敛守卫阈值、措辞纪律——五类关键决策协议均无机械依据，全靠当轮主会话自由裁量；换会话/换模型可能丢失轨迹。
2. **状态文件已从"控制面索引"退化为"叙事复写库"**：`current.md`（21 行/21,957 字节）、`goal-breakdown.md`（199 行/137,156 字节）等四份核心状态文件合计约 278KB，同一事实（如 SG-8）在 5–6 处文件重复出现，无 schema、无事务、随轮次线性膨胀。
3. **机械门只验协议文件卫生，不验业务真实性**，且存在双向缺口：`verify_protocol.py` 的 Rule A/B 既会对合法引用误报（历史 TH-0006 6/6 误报），也会对错误的 Allowed 路径放行（grok 实测该场景 exit 0）——这两个方向的证据在三方之间出现直接冲突（见分歧点）。SG-5 `stop()` 契约缺口曾被三轮审查漏过。
4. **收官"六件套"人工劳动量大且逐轮增长，无自动化/事务化支撑**：每轮收官约产生 15–25 万 subagent tokens（主会话估算）/ 2,052 行 rounds 三件套（grok 统计），内容 70%+ 是同一事实的多视角复述，一致性完全依赖回写 agent 一次性拿到主会话给出的真值——prompt 错则六处全错。
5. **feedback 四分类区分度不足，与审查 verdict 无协议映射**：10 轮实现阶段全部以 `positive` 收官（含轮内多次 REWORK/MUST-FIX 的场景），真正的质量信号在会话/hopper 自设的 verdict 体系（REWORK/MUST-FIX/PASS_WITH_NOTE/CONFIRMABLE），协议文本完全没有这套词汇。

**Top 3 保留价值**（详见 §5，三方交集）：

1. **scope-lock 前置 + Rollback Condition "先停后问"文化**：真实触发两次（SG-5 `stop()` 缺口停机确认；SG-2 无 mock/真实付费 LLM 停在 L1 defer），证明是可工作的安全机制，不应在重构中弱化。
2. **诚实分层 / defer 文化 + "机械 pass ≠ 协议 pass"分层声明**：防止假完成被三方一致列为核心价值，SG-8.1 措辞拆层、SG-9 defer 记录等均为实例。
3. **文件型审计轨迹 + evidence-index 可追溯性**：可 git diff、可跨会话恢复，是 chat 编排器做不到的；异构独立审查（hopper codex/grok）产生的真实增益（抓凭证泄漏、死锁、假测试）也被三方一致确认为无法被机械门替代的价值。

---

## 2. 方法与语料

### 2.1 双轨异构调研

| 轨 | 执行方 | 模型 | 输出 | 字数/行数规模 |
|---|---|---|---|---|
| T-058 | codex (hopper 派发) | gpt-5.6-sol | `.hopper/handoffs/T-058-output.md` | 375 行，8 核心问题逐项判断+置信度 |
| T-059 | grok (hopper 派发) | grok-4.5 | `.hopper/handoffs/T-059-output.md` | 491 行，8 核心问题逐项判断+13 项问题清单 |

两轨为同题独立执行（互不知晓对方产出），均为只读调研（不改插件源码/app/内核/`.harnessloop` 状态，仅落盘各自 output.md），均给出 `Verdict: PASS`。

### 2.2 主会话第一手观察

本报告的第三条语料来自主会话在 10 轮执行中的直接执行侧体验，是两个 vendor 轨（作为外部只读审计者）看不到的"驾驶感受"：驱动力实感、会话自创机制清单、收官真实劳动量、状态文件膨胀实感、机械门两面性、仪式成本、Rollback 实测触发、feedback 分类实况、delegation gate 实际拦截效果、hopper 交互面人肉易错模式。这十条以「主会话视角」身份并列引用，不因其非独立 vendor 产出而降权。

### 2.3 语料范围

- **plugin 源码**：`harnessloop/plugins/harnessloop/skills/`（harnessloop-loop/continue/status/goal/evidence/issue/delegation/setup/secrets/intake 等 SKILL.md + `harnessloop-loop/scripts/{check_setup.py,verify_protocol.py,round_cost.py}`）
- **真实使用记录**：`.harnessloop/goals/20260718-002-agent-app/`（goal.md/goal-breakdown.md/thresholds.md + rounds/0001–0010 各 scope-lock/round-summary/decision/evidence）、`.harnessloop/state/`（current.md/evidence-index.md/control-contract.md）、`.harnessloop/meta/self-audit.md`
- **旁证**：`.hopper/queue.md` + `handoffs/T-044..T-057`（异构审查闸真实运转记录）、`docs/validation-log.md`、git log

---

## 3. 三方视角对照（8 个评估问题逐项）

### Q1. 驱动力归属：continue gate 产出了多少，主会话补位了多少？

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | continue 提供"合法动作类型约束"，非"下一任务求解器"。五类关键决策（选 SG/分阶段/审查闸位置/收敛守卫/措辞纪律）机械决定 **0/5**，协议提供原则性依据但最终选择仍 100% 由主会话完成 | `harnessloop-continue/SKILL.md:28-40`、`harnessloop-loop/SKILL.md:242-247,408-419,500-502`；置信度 0.93 |
| **grok** | continue 自主性 ≈"允许边界检查器"+"下一动作类型提示"，不是"下一业务步骤生成器"；光谱位置 25–35% | 五张对照表（协议产出 vs 会话补位），如"选哪个 SG"无自动排序器，仅"continue to next subgoal"空话 |
| **主会话** | ①"continue 驱动"的自主性来自 LLM 会话本身，协议是护栏，防坏事但不指路——协议提供约束性而非驱动性 | 逐轮实际决策：SG 选择/分阶段/审查闸位置/vendor 轮换/REWORK 收残范围 |

**合成裁定**：三方**完全一致**，无分歧。这是本报告最稳固的结论：协议层面 0 个自动化的"下一步业务决策"生成器，全部战术决策权在主会话。唯一的量级分歧是最终打分（见 §3 分歧点第①条）。

**额外分支——会话自创机制的两难（主会话独有观察 ②）**：主会话进一步指出，项目在协议空白处自创了一批实际支柱级机制——异构审查闸（用户指定+会话实现）、收敛守卫（3rd MUST-FIX checkpoint）、teeth 破坏性反证、措辞诚实性口径、`--ignored` 双查、file:line 逐条复核、双轨并行探针、"下游揭上游"处置模式——这些在协议文本中**无依据**。两个 vendor 轨也各自独立观察到了其中若干项（如 grok 明确列出"收敛守卫""teeth 破坏性反证纪律"均为"会话自设"），但没有像主会话这样把它们作为一份完整清单并提出开放辩题：**吸收进协议会僵化，不吸收则不可移植**（换会话/换模型就丢）。三方均未对这一开放辩题给出裁定倾向，本报告也不代为裁定，留作候选讨论项。

---

### Q2. 状态文件工程性：巨块化、重复书写、机器可读性

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | 当前状态适合人类审计，不适合长期机器运行 | `current.md` 21 行/21,957 字节，最长单行 3,537 字符；`goal-breakdown.md` 199 行/137,156 字节，最长单行 18,174 字符；四份核心文件合计 277,881 字节；round 0009 同一事实在 6 处文件重复；`current.md:9` 与 lines 4-15 存在索引语义自相矛盾（"尚无已接受轮次" vs 叙述多轮 positive 收官）；置信度 0.98 |
| **grok** | 状态面已从"控制面索引"退化成"叙事复写库" | 词 "SG-8" 重复计数：self-audit.md 67 次、goal-breakdown.md 27 次、round-summary.md 24 次、decision.md 21 次、current.md 10 次、evidence-index.md 7 次；rounds 三件套合计 2,052 行且逐轮增厚（0001=87 行→0009=112 行） |
| **主会话** | ④状态文件单行数千字、goal-breakdown SG-5/SG-6 行千字巨块；每轮 re.sub 大段散文；机器不可读，主会话自己都要 grep+cut 截断读 | 执行侧一手体验：连协议的"作者"本身在下一轮都需要靠 grep/cut 而非结构化查询来读取自己写的状态 |

**合成裁定**：三方**完全一致**，且互相佐证形成交叉验证的量化证据链（codex 给字节数，grok 给重复词频，主会话给"连自己都读不动"的直接体验）。协议自称 state 文件"only control-plane indexes, not sole source of truth"（`harnessloop-loop/SKILL.md:262-301`）与实操已经背离——这是三方共同标记的最高确定性发现之一。

---

### Q3. 机械门能力边界：`check_setup.py` / `verify_protocol.py` 挡什么、挡不了什么

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | 机械门能挡"格式/路径级协议错误"，不能挡"业务结论错误"；边界问题不只是漏检，还有误报 | Rule A 只查 evidence/reviews 路径是否 ⊆ Allowed Changes；Rule B 查反引号路径引用存在性；历史上 Rule B 曾对合法引用 6/6 误报（TH-0006）；round 0009 scope-lock 路径缩写 false violation 与此同类，均是"字符串启发式无法表达 path alias/semantic scope"；SG-5 `stop()` 契约缺口被三轮审查漏过，直到下轮形式化 parity 才发现；置信度 0.97 |
| **grok** | 机械门守住的是"协议文件卫生"的窄子集，守不住"业务真实性/证据质量/是否绕开 round/代码是否越 scope" | **本机实测重跑** `verify_protocol.py --project .` → **exit 0**；语料中多轮 Allowed 写了不存在的 `.harnessloop/rounds/NNNN/` 缩写路径（真实路径在 `goals/.../rounds/`），归因为 **Rule A 覆盖面过窄导致"错误 Allowed 路径不触发失败"**（漏报而非误报）——与 setup-wizard 期 TH-0006 Rule B 误报是**不同症状**；同时指出 Rule A 根本不扫业务代码改动（引 `harnessloop/adversarial-review-p0.md` m7） |
| **主会话** | ⑤机械门两面：rounds/0009 scope-lock `.../` 缩写触发 **false scope-lock-violation**（解析自由散文注定脆弱）；反面 exit 0 也不代表任何业务质量 | 执行侧直接体验到该缩写场景导致了一次误判阻断 |

**合成裁定：本题存在本报告最明确的三方事实性分歧，不做抹平处理，完整呈现如下**：

- 主会话的第一手记录是"该缩写**触发了**一次 false scope-lock-violation"（阻断/误报方向）。
- codex 将 round 0009 的这个缩写案例，与历史上 Rule B 6/6 误报（TH-0006）归为同一类问题，采信"误报/阻断"的方向，但**未在报告中给出本次重新运行的命令输出**作为独立佐证。
- grok **实际重新执行了** `verify_protocol.py`，得到 exit 0（**未阻断/放行**），并据此重新归因：这不是 Rule B 式误报，而是 **Rule A 覆盖面过窄导致的漏报**——错误的 Allowed 路径本身没有被校验，所以不会导致失败。

三种说法在"这次具体事件是阻断还是放行"上直接冲突。**合成裁定**：由于 grok 提供了可复现的命令与实测输出（`verify_protocol.py --project .` exit 0），证据强度上略高于另两方未附带重跑记录的定性判断；但也不能排除以下可能——(a) 主会话观察的是**不同轮次/不同缩写实例**（round 0009 存在多处 Allowed 路径写法，"false violation"与"exit 0 放行"可能分别对应不同具体行）；(b) verify_protocol.py 在两次调研之间可能已被修补（历史上确实多次因 TH-0006 等打过补丁）。**本报告不裁定谁"错"，而是将其本身作为 Top 问题呈现**：机械门的路径匹配逻辑本身既可能误报（对合法引用/缩写形式阻断），也可能漏报（对错误 Allowed 路径放行）——**两个方向的脆弱性同时存在，且外部审查者对同一类事件重新验证会得到不同结论**，这恰恰印证了"字符串/正则启发式无法可靠承载 scope 语义"这一根本诊断（三方对此根本诊断本身无分歧，分歧只在具体这一次事件是哪个方向）。

> **主会话补充裁定（合成后追记，2026-07-26，第一手时序证据）**：本分歧可以裁定——两个方向**先后都真**。时序：rounds/0009 收官回写时 `verify_protocol.py` 实测 **exit≠0、报 2 条 scope-lock-violation**（阻断/误报方向,主会话观察属实,出处:收官回写 agent 回执原文"initially failed with 2 scope-lock-violations…fixed by spelling out the path"）→ 回写 agent **改写了被检文件本身**（把 `.../` 缩写展开为全路径,无 scope 变更）→ 之后 exit 0。grok 重跑的是**修复后的文件**,故得放行——其重跑无误,但对象已非事发态。另:grok 指出的"其它轮次错误 Allowed 路径不触发失败"（Rule A 漏报方向）与此并存,同样成立。**因此双向脆弱性结论不变且更强**:同一机械门在同一轮里先误报、修复方式是改被检文件、而错误路径又从不报——"字符串启发式无法承载 scope 语义"的根本诊断由时序证据完全坐实。
>
**次要发现**（grok 独有，codex/主会话未提及）：grok 引用了插件内部文档 `harnessloop/adversarial-review-p0.md`（m7 条目）指出 Rule A **根本不扫描业务代码改动**，只查 evidence/reviews 目录下文件路径——scope-lock 的"心理预期"远大于其机械覆盖范围。这是三方中唯一给出的、指向具体源码内部批评文档的证据，建议在改进方向评估时重点参考。

---

### Q4. 收官成本：六件套重复劳动量、一致性风险、协议支撑

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | 模板齐全，但收官没有事务化或自动回写支持 | 协议只要求 verify→summary→decision→archive→self-audit→按 feedback 续（`harnessloop-loop/SKILL.md:491-502`）；实际固定回写 current.md/evidence-index.md/goal-breakdown.md，形成至少六处写入；round 0009 三份核心收官文件合计约 36KB 且大量互抄；无 closeout manifest/单一 canonical event/原子写入/派生索引重建/一致性校验脚本；置信度 0.96 |
| **grok** | 每轮收官是高认知负载的多文件人工一致性维护；模板有形状无自动化 | 单轮三件套约 150–250 行手写/粘贴；10 轮仅 round 三件套 2,052 行；self-audit 单文件近 100KB；`round_cost.py` 是唯一接近"自动收官"的脚本，且依赖 Claude Code transcript，无 multi-file closeout 工具 |
| **主会话** | ③每轮收官回写约 **15–25 万 subagent tokens**（round-summary/decision/E-entry/goal-breakdown 行/current.md/self-audit），内容 70%+ 是同一事实多视角复述；一致性靠回写 agent 一次拿到全部真值，而真值单源是主会话给的 prompt——**prompt 错则六处全错**的脆弱点 | 执行侧对"劳动量"给出了两个 vendor 均未测算的 token 级估算，并揭示了一个两个 vendor 都未点破的**根因层面的脆弱性**：一致性不是靠事务，而是靠单一 prompt 广播到六处，故障模式是"上游一处错、下游六处一起错"，而不只是"人工同步容易漏" |

**合成裁定**：三方一致确认收官成本高、无自动化，程度判断（行数/字节数/token 数）互补而非冲突，三组量化数据可拼接为更完整的成本画像（字节量→行数→token 量三级换算）。**主会话的"prompt 单源脆弱"框架是本题最有价值的新增视角**——两个 vendor 都停留在"重复劳动大"的现象层面，主会话进一步指出了这种重复劳动的**故障传播机制**（单点故障会放大成六点故障，而非六个独立校验点互相纠错），这对应到 §6 改进方向中"事务化 round closeout"建议的必要性论证，属于三方合成后新增的洞察，值得在候选 issue 中单独体现。

---

### Q5. feedback 分类与收敛：四分类区分度、rework-loop 收敛守卫、verdict 映射

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | 四分类适合控制大方向，不足以表达审查生命周期 | `decision-template.md` 只允许 positive/negative/neutral/blocked；round 0005 经 REWORK→MUST-FIX→PASS_WITH_NOTE、round 0006 经多个 REWORK/MUST-FIX→CONFIRMABLE，但两轮最终 decision 都是 `Feedback: positive`；"同阶段第 3 次 MUST-FIX checkpoint 用户"是项目自设，协议只要求重复 negative/neutral 无新证据时更新 self-audit；置信度 0.95 |
| **grok** | 四分类区分度在实现阶段被压扁为"几乎总是 positive + 长 Open Risks" | 10 轮实现阶段名义 feedback 分布表：0001–0010 除 0010(in-progress)外全部 positive；"第 3 轮 MUST-FIX→checkpoint"仅出现在 rounds/0005 起 scope-lock/self-audit（主会话写入），loop/continue SKILL 全文无 MUST-FIX、无"第 3 次"阈值；vendor verdict 词汇（REWORK/MUST-FIX/CONFIRMABLE/PASS_WITH_NOTE）非 harnessloop 协议枚举 |
| **主会话** | ⑧10 轮全 positive 收盘（negative/neutral 从未出现）——收残在轮内完成使分类失去区分度；真正质量信号在审查 verdict，但它与 feedback 分类无协议映射 | 执行侧确认"10 轮全 positive"这一具体分布事实，与 grok 的统计完全吻合 |

**合成裁定**：三方**完全一致**，且主会话的"10 轮全 positive"与 grok 的分布表逐轮吻合，形成强交叉验证。协议文本层面确认"无 REWORK 一词"，收敛守卫与 verdict 映射均为项目自设，这是继 Q1/Q2 后第三个三方零分歧的高确定性结论。

---

### Q6. 实效正面清单：哪些机制被 10 轮实际使用证明有效

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | 五项核心纪律均有真实正面证据：scope-lock 前置有效、Rollback Condition 真能刹车、诚实分层/defer 防止假完成、evidence-index 提供可追溯入口、setup 门有效但偏结构性、异构独立审查产生真实增益 | round 0002 首个 scope-lock 完整轮；round 0002 因真实付费 LLM/无 mock 停在 L1 defer；round 0006 SG-5 `stop()` 缺口触发 Rollback→AskUserQuestion；T-044 抓凭证泄漏、T-045 抓收残死锁和假测试、T-055 补挖 state.db 证据；置信度 0.98 |
| **grok** | 9 项机制清单被证明有效，含"探索性否定→positive 特款"（设计阶段专属） | scope-lock 先于执行（0002 起闭环）；Rollback/Disallowed 撞线停下问人（0004 两次 openclaw 扩围 user-confirmed；0006 SG-5 stop 缺口）；对抗审真抓缺陷（T-048 臆造字段、T-050 表面绕过、T-052 remap 假绿、T-057 措辞拆层）；self-audit 作为观察金矿（AUDIT 条如实记绕开 round/teeth 纪律）；contract-insufficient 路径（0004 不擅自改内核） |
| **主会话** | ⑦实测有效：Rollback Condition 两次真实触发（SG-5 stop 缺口停下问用户/零改动证伪即停机制）；诚实分层 defer 被协议文化强化到每个交付；evidence-index E1-E20 可追溯性真实有用 | 执行侧确认 Rollback 触发次数与两个 vendor 一致（均引用 SG-5 stop 缺口案例作为核心实例），并补充"零改动证伪即停"这一具体触发场景 |

**合成裁定**：三方**完全一致**，SG-5 `stop()` 缺口触发 Rollback Condition 这一具体事件被三方独立引用为同一核心证据，是全篇交叉验证最密集的单一事实点。唯一细微差异：主会话额外提到"零改动证伪即停"作为第二个 Rollback 实例，两个 vendor 未单独点出这一具体场景（但都提到了 round 0002/0004 的其他 Rollback 实例），不构成分歧，只是证据枚举详略不同。

---

### Q7. 低使用率机制：harnessloop-issue / delegation gate / intake 的实际使用率与原因

| 视角 | 判断 | 关键证据 |
|---|---|---|
| **codex** | issue 低频（约 1/10 round，明确新框架 issue 为 evolution issue 0010）；delegation gate 0/10 可证显式调用，但书面 pass 依赖"按参数指定"而非独立运行时探针；intake 0/10 但合理（本 goal 非接管，不应算缺陷） | `rg` 命令核验：`.harnessloop` 全域搜索 `$harnessloop-(issue\|delegation\|intake)` 仅命中 `environment.md:39` 的未来建议一处；置信度 issue 0.88，delegation 0.94，intake 0.99 |
| **grok** | issue 使用呈现明显阶段性反差：setup-wizard 期（2026-07-16/17）9/10 issue 集中爆发且多数 fixed，实现期仅 TH-0010 一例；delegation 0 次正式调用，委派规则固化在项目 AGENTS.md/CLAUDE.md，"skill 成为死文档"；intake 0（场景不匹配，预期内） | TH-0010（绕开 round dead-reckoning）是实现期唯一新增 issue 且仍 open；`$harnessloop-evidence`/`$harnessloop-status` 同样低频，倾向直接手改文件 |
| **主会话** | ⑨delegation gate **从未拦截过任何东西**；写码派 Sonnet 是 memory 惯例非协议强制 | 执行侧对 delegation gate 的实际拦截效果给出比两个 vendor 更强的定性断言 |

**合成裁定**：三方在"delegation gate 低使用/未真正生效"上方向一致，但**语气/结论强度存在梯度分歧**（非事实冲突，标注为分歧点）：codex 用"0/10 可证显式调用"的证据学谨慎措辞、留有"可能是记录方式问题"的余地；grok 直接判定为"死文档"；主会话给出最强断言"从未拦截过任何东西"。三者共同支持的结论是：delegation gate 在本 goal 中**没有一次真正改变了执行路径**，区别只在于如何归因（协议设计问题 vs 记录缺失 vs 项目策略绕过）。issue 机制方面，codex 更强调"合理未用 vs 机制失效需区分"的分析框架，grok 更强调"阶段性反差"这一具体模式，两者互补而非冲突。

---

### Q8. 自主性上限与结构性改进方向

| 视角 | 判断要点 |
|---|---|
| **codex** | 提出 8 项结构性改进方向：canonical structured state / 确定性 next-action resolver / 事务化 round closeout / 审查闸协议化（双向 coverage matrix）/ 正式收敛状态机 / 机械门语义化（canonical path + schema） / 成本压缩（history rollover） / 低频机制嵌入主路径。**独有贡献**：引用公开 prior art 支撑（LangGraph persistence/interrupts、OpenAI Agents SDK HITL RunState、Temporal durable execution、GitHub Actions artifacts/attestations），为"结构化运行时"提供外部参照系 |
| **grok** | 提出 7 项方向并按杠杆排序：结构化 state / closeout 脚本 / dead-reckoning 守卫（TH-0010）/ Rule A2 git 地基 scope 检查 / 审查闸协议化 / SG 选择策略（依赖图+启发式建议） / 成本感知 continue。**独有贡献**：明确列出"不应追求的假自主"清单——不应让 continue 自动接受 REWORK 后的 round、不应让机械门判断业务正确性、不应取消 scope-lock/人确认高风险写 |
| **主会话** | ②开放辩题（会话自创机制吸收进协议 vs 保持轻量）本身就是一种"自主性上限"框架，未直接给出改进方向列表，而是提出需要先回答的元问题 |

**合成裁定**：codex 与 grok 在具体改进方向上**高度重叠**（结构化 state、closeout 自动化、审查闸协议化三项在两轨的排序中都居前列），差异主要在于**独有补充**而非矛盾——codex 补充外部 prior art 参照，grok 补充"不应追求的假自主"边界清单与"dead-reckoning 守卫"的具体优先级（grok 将其列为 P0，codex 未单列为顶级项，见 §3 分歧点）。主会话的开放辩题为两者提供了一个更上位的框架性问题：任何结构化改进都要先回答"哪些会话自创机制值得固化，哪些应保持会话自由裁量"。

---

### 3.9 主会话独有观察（vendor 范围外，未被两轨评估）

以下两条来自主会话第一手体验，超出两个 vendor 轨的调研范围（vendor 仅评估 harnessloop 插件本身，未涉及 continue 输出的用户体验成本与 hopper 交互面）：

- **⑥ 仪式成本**：continue 输出契约的大 block 结构对用户实际信息价值有限——用户真正阅读的是会话给出的自然语言报告而非契约格式化输出；`check_setup.py` 每轮都会运行，但 10 轮下来其判定结果从未变化过。这一观察与 grok 在 Q3 中"check_setup 对实现阶段漂移零贡献"的判断方向一致，但角度不同：grok 关注的是机械门**检测能力**的边界，主会话关注的是重复执行带来的**仪式性成本**（跑了但没有信息增量）。
- **⑩ hopper 交互面人肉易错**：`.hopper/queue.md` 手写表格用 `\|\|` 切列、`failed` 状态需手工重置、`--search` 版本存在漂移——这些虽是 hopper 侧问题、超出两个 vendor 轨对 harnessloop 本体的评估范围，但反映了与 harnessloop 状态文件"靠手写 Markdown 表格承载结构化数据"相同的共性模式（呼应 Q2 的"机器可读性"发现）。建议在候选改进中作为跨插件的共性观察记录，而非 harnessloop 专属问题。

---

## 4. 合并问题清单（按严重度排序，去重，标注提出方）

标注：**[C]** = codex 独立提出/量化，**[G]** = grok 独立提出/量化，**[M]** = 主会话独立提出，多方标注表示交叉印证。

### S0 / P0 — 结构性根基问题

| # | 现象 | 根因 | 影响 | 改进方向（候选） | 提出方 |
|---|---|---|---|---|---|
| 1 | "continue 驱动"的关键决策（选 SG/分阶段/审查闸位置/收敛守卫/措辞纪律）实际 0/5 由协议机械产生，全由主会话补位 | 协议只约束合法动作类别，无 planner/next-action resolver | 自主性完全取决于当前 LLM 会话的判断与记忆；换会话/换模型可能丢失既有轨迹 | 确定性 next-action resolver（结构化 state + 依赖图 + risk/evidence 打分，LLM 提案+resolver 校验） | [C][G][M] |
| 2 | 状态文件（current/goal-breakdown/self-audit/evidence-index）已退化为叙事复写库，同一事实 5–6 处重复，无 schema/事务，随轮次线性膨胀 | Markdown 同时承担数据库、日志、报告三重角色；无原子写入/单一事实源 | 长 goal 必然积累不一致；解析器无法稳定寻址状态字段；已有实例（current.md 索引语义自相矛盾） | canonical structured state（versioned JSON/YAML/SQLite）+ Markdown 仅做派生 human view | [C][G][M] |
| 3 | 实现阶段可长时间绕开 round 闭环交付，state 静默滞后且零机械报警（evolution issue TH-0010） | continue/self-audit 无"实际交付 vs round 完成"一致性信号 | 协议账本可能失真；验证项目一度自欺"已在 harnessloop 内" | dead-reckoning 守卫：impl 阶段 N 笔交付无 round → warn/block（阈值可配 profile） | [G]（codex 提及同一 issue 0010 但未列为独立顶级项，仅作为 S0/S1 的支持性证据） |

### S1 / P1 — 机械门与审查质量

| # | 现象 | 根因 | 影响 | 改进方向（候选） | 提出方 |
|---|---|---|---|---|---|
| 4 | 机械门路径匹配同时存在误报与漏报两个方向：既可能对合法引用/缩写形式误判违规，也可能对错误 Allowed 路径本身放行不查 | Rule A/B 基于自然语言反引号猜测路径存在性/containment，字符串启发式无法表达 path alias/语义 scope；Rule A 不校验 allowed span 自身可解析/存在 | 假绿业务结论漏过（错误契约沉睡），真引用又可能被阻断（开发摩擦） | scope path 先 normalize/resolve alias 再比较 canonical path；Rule A2：allowed span 存在性/可解析性校验 | [C][G][M]（**具体这次事件的方向本身三方有分歧，见 §3 分歧点，但"字符串启发式两面脆弱"这一根本诊断三方一致**） |
| 5 | Rule A 只查 evidence/reviews 目录路径，根本不扫描业务代码改动本身 | 机械门设计范围窄于 scope-lock 的"心理预期" | scope-lock 心理安全感虚高；实际代码是否越界完全靠人/审查员目视 | Rule A2：round 起始 HEAD marker + git diff ⊆ Allowed Changes 校验 | [G]（引用插件内部文档 `harnessloop/adversarial-review-p0.md` m7） |
| 6 | 审查质量无协议内建支撑，全靠会话自设的异构审查闸（hopper codex/grok 随机池）；SG-5 `stop()` 契约缺口被三轮审查漏过 | 协议只有"必须有 adversarial review"的原则性要求，无逐条契约 coverage matrix、无 verdict 枚举、无独立性强制校验 | 审查质量完全依赖 prompt 与 reviewer 能力；协议本身无法保证审查覆盖面 | 双向 requirements↔implementation coverage matrix；审查闸协议化（gate ID、时点、独立性要求、verdict enum） | [C][G][M]（②会话自创机制清单印证协议空白） |
| 7 | verdict（REWORK/MUST-FIX/PASS_WITH_NOTE/CONFIRMABLE）与 feedback 四分类（positive/negative/neutral/blocked）无协议映射；轮内多次 REWORK 仍以单一 positive 收官 | 两套语义体系分属不同层（协议层 vs 会话/hopper 层）从未桥接 | 自动 continuation 无法可靠判断"可收残/可接受/需人"；审计时"positive 轮内多次 REWORK"难以机器识别 | 分层状态机：`review_verdict` / `round_feedback` / `rework_count_by_gate` / `acceptance_effect` 分栏，映射表+禁止叙事映射 | [C][G][M] |

### S2 / P2 — 收官成本与机制闲置

| # | 现象 | 根因 | 影响 | 改进方向（候选） | 提出方 |
|---|---|---|---|---|---|
| 8 | 收官"六件套"人工劳动量大且逐轮增长（约 15–25 万 subagent tokens/轮，2,052 行 rounds 三件套累计），70%+ 内容重复，一致性依赖单一 prompt 广播到六处（prompt 错则六处全错） | 只有模板，无 closeout manifest/单一 canonical event/原子写入/派生索引重建/跨文件一致性校验 | 上下文/时间成本随轮数线性上升；维护者倾向绕开协议；单点故障放大为多点故障 | 一键收官工具（差量生成+一致性校验+历史 rollup）；事务化 round closeout（单一操作校验后写 immutable event，自动重建派生文件） | [C][G][M]（③"prompt 单源脆弱"根因框架为主会话独有贡献） |
| 9 | delegation gate 在高频委派场景中从未真正拦截任何执行；书面 pass 依赖"按参数指定"而非独立运行时观测；写码派 Sonnet 是项目 memory 惯例，非协议强制生效 | delegation skill 未嵌入 dispatch 路径；委派规则实际固化在项目 CLAUDE.md/AGENTS.md 而非协议 gate | 观察到的 model/effort 元数据不可验证；delegation skill 沦为可绕过的书面仪式 | dispatch adapter 自动采集 observed model/effort 元数据并产出 gate result，嵌入实际派发路径 | [C][G][M] |
| 10 | issue 机制使用呈现明显阶段性反差：setup-wizard 期活跃（9/10 issue 集中且多数 fixed），实现阶段近乎停用（仅 TH-0010 一例，仍 open）；open issue 不阻断 continue | 实现期问题倾向记入 round Open Risks/self-audit Reason 而非升级为 evolution issue；issue 与 gate 无耦合 | 框架进化速度依赛主会话自觉，缺少系统性触发；已知缺陷（TH-0008 等）可无限期悬挂 | self-audit 命中框架类规则时自动生成 issue draft 提示；open packaging/skill-gap 可选 warn | [C][G] |

### S3 / P3 — 体验、口径与边角问题

| # | 现象 | 根因 | 影响 | 改进方向（候选） | 提出方 |
|---|---|---|---|---|---|
| 11 | issue/delegation/intake 使用率口径混淆：无法区分"合理未用（N/A）"与"机制可用但被绕过（bypassed）" | 无 eligible/invoked/bypassed/not-applicable 的 telemetry 分类 | 产品侧无法判断低使用率是否代表设计问题 | 机制适用性与调用指标分开统计，四态而非二态 | [C] |
| 12 | 仪式成本：continue 输出契约大 block 对用户信息价值有限（用户实际读的是自然语言报告）；check_setup 每轮跑但 10 轮结果从未变化 | 协议要求每轮固定跑一遍结构性检查，无"结果未变则跳过展示"的短路逻辑 | 用户注意力被低信息量的固定格式输出稀释 | 结果不变时折叠/简化展示；仅在状态变化时展示完整契约 block | [M]（vendor 范围外，见 §3.9） |
| 13 | hopper 交互面人肉易错（queue.md 手写表 `\|\|` 切列、failed 重置手工、--search 版本漂移），反映"协议靠手写 Markdown 表"的共性模式 | 与 harnessloop 状态文件同源问题：结构化数据被承载在自由格式 Markdown 表格中 | 人工编辑易出错，缺少机械校验；虽是 hopper 侧问题但值得作为跨插件共性记录 | （跨插件观察，非 harnessloop 专属改进对象；建议记录但不纳入 harnessloop evolution issue） | [M]（vendor 范围外，见 §3.9） |
| 14 | round_cost.py 成本统计绑定 Claude Code 环境假设，grok/codex 轨执行的轮次成本不可比 | 工具设计时假设单一执行环境 | 多 vendor 混合执行时成本口径不统一 | 多 vendor cost adapter，或明确文档化 "unavailable" 策略 | [G] |

**合计：14 条问题**（S0/P0 三条、S1/P1 四条、S2/P2 三条、S3/P3 四条）。

---

## 5. 核心价值保留清单（三方交集优先）

以下按"三方交集 > 两方交集 > 单方独有但有实测证据支撑"排序：

### 三方交集（改进时绝对不能丢）

1. **scope-lock 前置执行 + 明确 allowed/disallowed/rollback**：round 0002 起闭环，与更早的绕开形成对照（TH-0010 反证了缺失时的后果）。
2. **Rollback Condition"先停后问"真能刹车**：SG-5 `stop()` 缺口触发 AskUserQuestion 定向修复，是三方共同引用的最强单一证据；另有 round 0002 真实付费 LLM/无 mock 停在 L1 defer 场景。
3. **诚实分层 / defer 文化 + "机械 pass ≠ 协议 pass"分层声明**：防止假完成，SG-4 只宣告 L1、SG-9 defer 缺凭证的 L2、SG-8.1 拆分"映射层 pass"与 mint HTTP 501 residual，均为实例。
4. **evidence-index 可追溯性**：E1-E20 串联审查、阈值数据、handoff 与可复现路径，跨会话可恢复。
5. **异构独立审查（hopper codex/grok 随机池）产生的真实增益**：T-044 抓凭证泄漏、T-045 抓收残死锁和假测试、T-055 补挖 state.db 证据、T-057 措辞拆层——均非机械门能发现，也非单一模型自审能发现。

### 两方交集

6. **实现者与 adversarial reviewer 分离，委派矩阵禁止自卖自夸**（codex+grok）。
7. **文件型审计轨迹本身（可 git diff、跨会话恢复）**（codex+grok，主会话隐含认同但未单独强调）。
8. **setup 门确保控制字段存在（结构性有效，非内容真实性保障）**（codex+grok）。
9. **feedback/blocker 分类词汇提供共用语言，即便需要扩展**（codex+grok）。
10. **evolution issue 的"先本地缓解、再抽象框架问题"原则 + 脱敏/不拷项目私货的跨项目进化通道**（codex+grok）。

### 单方独有但有实测证据支撑

11. **self-audit 作为框架验证探针本身是本项目存在目的之一**（grok 明确强调"不要为干净 state 删掉观察金矿，可归档不可无"）。
12. **探索性 goal 的否定结论合法化（feedback 特款）**：保护诚实研究，设计阶段多轮 REWORK 不计失败（grok）。

---

## 6. 改进方向 roadmap（候选，非实施计划）

以下所有条目均为**候选讨论方向**，不构成实施承诺；每项标注预期收益与风险，供后续决策参考。

### 6.1 协议结构性（影响大、改动深，需谨慎评估）

| 方向 | 内容 | 预期收益 | 风险 |
|---|---|---|---|
| 结构化 canonical state | 用 versioned JSON/YAML/SQLite 承载 goal/SG DAG/round/gate/feedback/evidence ref/blocker/rework counters；Markdown 只做派生 human view，每个事实一个 owner/id | 消除六处重复书写与状态漂移；可支持机械查询（"列出所有 pending SG"） | 破坏现有"纯 Markdown 可读可 diff"文化；需要设计迁移路径，兼容现有 10 轮历史数据；结构本身若设计不当会重蹈"schema 又不够用"覆辙 |
| 确定性 next-action resolver | 输入 canonical state + control profile，输出候选/硬阻断/排序分数/required human decision；LLM 可提案，resolver 校验落盘 | 减少主会话自由裁量的不可复现性；换会话/模型时保留轨迹 | 排序算法本身的"正确性"仍是主观判断，可能只是把决策权从"主会话此刻的判断"转移到"resolver 设计者此刻的判断"，未必真正提升自主性，只是把裁量点前移 |
| 事务化 round closeout | 单一 `closeout-round` 操作校验 scope/review/evidence 后写一条 immutable event，自动重建 current/breakdown projection/evidence index/audit counters；失败整批回滚 | 消除"prompt 错则六处全错"的脆弱点；一致性由工具保证而非人工记忆 | 需要设计失败回滚语义与部分完成状态的处理；对现有非结构化历史数据的兼容成本高 |
| 审查闸协议化 | scope-lock 声明 gate ID/时点/审查类型/独立性要求/逐条 threshold coverage/verdict enum/acceptance effect；双向 requirements↔implementation coverage matrix | 直接针对 SG-5 stop() 三轮漏审问题；使审查质量可被结构性校验而非仅靠 prompt | 若 coverage matrix 定义过细可能变成新的仪式负担；verdict enum 若绑死单一 vendor 词汇会牺牲灵活性（grok 已提示此风险） |
| 正式收敛状态机 | 将 REWORK/MUST-FIX/PASS_WITH_NOTE/CONFIRMABLE 与 feedback 分层，按 gate 计数，配置 max attempts/同类 finding fingerprint/无新证据检测/checkpoint/escalation | 使"3rd MUST-FIX checkpoint"等会话自设纪律获得协议层支撑，不因换会话而丢失 | 固化当前的"3 次"等阈值可能不适配所有场景，需要可配置而非硬编码；过度状态机化有过早优化风险 |
| Rule A2：git 地基 scope 检查 | 需要 round 起始 HEAD marker，校验实际 git diff ⊆ Allowed Changes，而非只查 evidence/reviews 路径 | 直接堵住"机械门不扫业务代码改动"的已知缺口 | 需要设计 HEAD marker 的记录时点与跨 round 边界情况（如中途 rebase/多轮并行分支）的处理 |

### 6.2 工具性（影响中等、改动相对局部，风险较低）

| 方向 | 内容 | 预期收益 | 风险 |
|---|---|---|---|
| dead-reckoning 守卫（TH-0010 直接对应） | impl 阶段 N 笔交付无 round 完成 → warn/block，阈值可配置 profile | 直接堵住"绕开 round 闭环 state 静默滞后"的已证实缺口 | 阈值 N 目前无法从现有 10 轮反推默认值（grok 已提出为 open question），需要更多样本或人工试错定阈 |
| 机械门语义化（canonical path + schema） | scope path 先 normalize/resolve alias 再比较；引用使用显式 evidence ID/link 字段而非从任意 Markdown backtick 猜路径 | 同时降低误报（缩写形式被误判违规）与漏报（错误路径被放行）两个方向的脆弱性 | 需要为现有引用方式设计迁移路径；短期内新旧两种引用方式共存会增加复杂度 |
| 收官自动化（closeout 脚本） | 一次命令生成/校验六件套字段一致性 + diff 提示，不自动编造业务叙述 | 降低收官人工负载，减少不一致风险 | 若脚本生成内容质量不足，可能被主会话当作"够用了"而降低审查投入，需保留人工复核环节 |
| dispatch 自动化委派检查嵌入 | dispatch adapter 自动采集 observed model/effort 元数据，产出 gate result，嵌入实际派发路径而非事后书面记录 | 让 delegation gate 从"从未拦截任何东西"转为真正可拦截的运行时校验 | 需要 hopper/dispatch 侧配合暴露可信元数据，属于跨插件协作依赖 |
| 成本感知 continue | 聚合 round_cost 数据 + 预算阈值，形成真实的 cost runaway 闸 | 目前 round_cost 只生成可粘贴片段，无实际阈值控制 | round_cost 环境绑定 Claude Code 的问题需先解决（多 vendor 场景不可比） |

### 6.3 文档性（影响小、改动轻，可低成本尝试）

| 方向 | 内容 | 预期收益 | 风险 |
|---|---|---|---|
| 产品叙事诚实分层 | 对外称"evidence-backed control loop / 抗漂移协议"而非"自主驱动引擎"（grok 明确建议） | 更诚实地设定用户预期，也更利于改进优先级排序（先机械一致性与 scope 真闸，后动作生成） | 可能被解读为"降低产品卖点"，需要与产品叙事目标平衡 |
| 使用率四态 telemetry 文档化 | 明确区分 not-applicable / eligible-but-bypassed / invoked / N/A 四态，而非笼统的"使用率低" | 澄清 issue/delegation/intake 低使用率背后是设计问题还是场景不匹配 | 纯文档层面改动，几乎无风险，但也不能单独解决根本问题 |
| 会话自创机制的去留讨论（呼应 ②开放辩题） | 明确记录哪些会话自创机制（异构审查闸/收敛守卫/teeth 反证/措辞诚实性口径等）计划吸收进协议、哪些保持轻量会话惯例 | 为后续结构化改进提供明确的"哪些要固化"清单，避免协议无限膨胀 | 讨论本身不产生代码变更风险，但若迟迟不决策会持续拖累可移植性 |

---

## 7. 候选 evolution issues（可直接转 `harnessloop-issue` 的条目清单）

1. continue gate 缺少确定性 next-action resolver：SG 选择/阶段切分/审查闸位置/收敛守卫/措辞纪律五类关键决策机械层面 0/5 由协议产生，全部依赖当轮主会话自由裁量。
2. 核心状态文件（current.md/goal-breakdown.md/self-audit.md/evidence-index.md）叙事化膨胀且同一事实 5–6 处重复书写，无 schema/事务/一致性校验。
3. TH-0010 类"绕开 round 闭环 dead-reckoning"缺口：实现阶段可长时间无 round 交付，state 静默滞后且零机械报警，需评估是否补一道 impl 阶段活动量守卫。
4. `verify_protocol.py` Rule A/B 路径匹配同时存在误报（合法引用/缩写被判违规）与漏报（错误 Allowed 路径本身不被校验）两个方向风险，需评估 canonical path normalize 方案。
5. Rule A 未校验业务代码改动本身（只查 evidence/reviews 路径），scope-lock 的"心理预期"与机械覆盖范围存在落差（引用 `harnessloop/adversarial-review-p0.md` m7）。
6. 审查质量缺少协议内建支撑：无逐条契约 coverage matrix、无独立性强制校验，SG-5 `stop()` 契约缺口曾被三轮审查漏过。
7. 审查 verdict（REWORK/MUST-FIX/PASS_WITH_NOTE/CONFIRMABLE）与协议 feedback 四分类（positive/negative/neutral/blocked）无正式映射，轮内收敛过程对协议不可见。
8. 收官"六件套"无自动化/事务化支撑，一致性依赖单一 prompt 广播到多处文件，存在"prompt 错则多处全错"的单点故障放大风险。
9. delegation gate 未嵌入实际 dispatch 路径，10 轮内无一次真正拦截执行，书面 pass 与运行时观测脱节。
10. harnessloop-issue 机制使用率在实现阶段与 setup-wizard 阶段呈现明显反差（活跃 vs 近乎停用），且 open issue 不与 continue gate 耦合，已知缺陷可无限期悬挂。
11. issue/delegation/intake 的"使用率"缺少 eligible/invoked/bypassed/not-applicable 四态区分，产品侧无法判断低使用率的真实含义。
12. continue 输出契约与 check_setup 存在仪式性成本：check_setup 结果多轮不变仍逐轮全量运行/展示，缺少"结果未变则折叠"的短路逻辑（主会话观察，vendor 范围外）。

---

## 8. 附录

### 8.1 两轨原始报告指针

- codex 轨完整报告：`.hopper/handoffs/T-058-output.md`（含核验命令输出、evidence 引用、公开 prior art 链接）
- grok 轨完整报告：`.hopper/handoffs/T-059-output.md`（含 §0–§12 完整结构、来源索引表）
- 两轨原始日志：`.hopper/handoffs/T-058-output.log`、`.hopper/handoffs/T-059-output.log`

### 8.2 主会话观察原文（逐条保留，未做转译）

> ①**驱动力实感**：continue gate 每次给的只有"允许/不允许"框架；每步实际决策（选 SG/分阶段/审查闸位置/vendor 选择轮换/REWORK 收残范围）全是会话自由裁量——协议提供**约束性**而非**驱动性**，防坏事但不指路；"continue 驱动"的自主性来自 LLM 会话本身，协议是护栏。
>
> ②**会话自创机制清单**（协议文本无依据但成了项目支柱）：异构审查闸（用户指定+会话实现）/收敛守卫（3rd MUST-FIX checkpoint）/teeth 破坏性反证/措辞诚实性口径/--ignored 双查/file:line 逐条复核/双轨并行探针/"下游揭上游"处置模式。**开放辩题**：这些吸收进协议会僵化，不吸收则不可移植（换会话/换模型就丢）。
>
> ③**收官六件套真实劳动量**：每轮收官回写约 15-25 万 subagent tokens（round-summary/decision/E-entry/goal-breakdown 行/current.md/self-audit），内容 70%+ 是同一事实多视角复述；一致性靠回写 agent 一次拿到全部真值，而真值单源是主会话给的 prompt——**prompt 错则六处全错**的脆弱点。
>
> ④**状态文件膨胀实感**：current.md 单行数千字、goal-breakdown SG-5/SG-6 行千字巨块；每轮 re.sub 大段散文；机器不可读，主会话自己都要 grep+cut 截断读。
>
> ⑤**机械门两面**：rounds/0009 scope-lock `.../` 缩写触发 false scope-lock-violation（解析自由散文注定脆弱）；反面 exit 0 也不代表任何业务质量。
>
> ⑥**仪式成本**：continue 输出契约大 block 对用户信息价值有限（用户实际读的是会话自然语言报告）；check_setup 每轮跑但 10 轮结果从未变过。
>
> ⑦**实测有效**：Rollback Condition 两次真实触发（SG-5 stop 缺口停下问用户/零改动证伪即停机制）；诚实分层 defer 被协议文化强化到每个交付；evidence-index E1-E20 可追溯性真实有用。
>
> ⑧**feedback 四分类实况**：10 轮全 positive 收盘（negative/neutral 从未出现）——收残在轮内完成使分类失去区分度；真正质量信号在审查 verdict（REWORK/PASS_WITH_NOTE/CONFIRMABLE），但它与 feedback 分类无协议映射。
>
> ⑨delegation gate 从未拦截过任何东西；写码派 Sonnet 是 memory 惯例非协议强制。
>
> ⑩hopper 交互面人肉易错（queue.md 手写表 `||` 切列/failed 重置手工/--search 版本漂移）——虽是 hopper 侧，但反映"协议靠手写 markdown 表"共同模式。

---

*本报告为评估调研产出，不含实施承诺。所有 §6/§7 中的改进方向与候选 issue 均待后续用户决策是否、以何种优先级推进。*
