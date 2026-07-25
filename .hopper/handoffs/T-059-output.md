---
task_id: T-059
adapter: grok
model: grok-4.5
status: done
task_type: prd-research
language: zh-CN
researched_at: 2026-07-26
phase: done
dual_track: grok
peer_task: T-058
last_progress_at: "2026-07-25T19:41:16.386Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-25T19:41:16.385Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 240178
adapter_status: success
---

# T-059 — harnessloop plugin 自主驱动能力评估调研（grok 轨）

## Summary

本报告以 goal 002 实现阶段 10 个执行轮（rounds/0001–0010）真实记录 + harnessloop plugin 源码（skills + `verify_protocol.py` / `check_setup.py`）为语料，评估「自主驱动 goal 达成」的真实成色。结论：**harnessloop 当前是高纪律的文件型协议账本 + 控制门脚手架，不是能自行规划/选路/收敛的自主驱动引擎**——协议产出反馈分类、阻断分类、scope-lock 形状、机械门与「须有对抗审」原则；主会话（+ 用户）补位了几乎全部战术决策（选哪个 SG、阶段切分、★审查闸位置、收敛守卫阈值、verdict 词汇映射、措辞纪律、teeth 反证）。首批 SG-1..SG-9 能全清，主要靠主会话工程纪律 + hopper 异构审查，而非 continue gate 的自动推进。

## Files touched

- `.hopper/handoffs/T-059-output.md` — 任务指定的唯一落盘产出（评估调研报告）

## Acceptance verification (8/8)

| # | 准则 | 证据 |
|---|------|------|
| 1 | 驱动力归属：协议 vs 主会话补位 | §1 + 证据表 |
| 2 | 状态文件工程性与膨胀 | §2 + 体积/重复计数 |
| 3 | 机械门能力边界 | §3 + `verify_protocol.py` 注释/TH-0006/TH-0010 |
| 4 | 收官成本 / 六件套重复 | §4 |
| 5 | feedback 分类与收敛机制归属 | §5 |
| 6 | 实效正面清单（scope-lock / rollback / defer / evidence） | §6 |
| 7 | 低使用率机制（issue / delegation / intake） | §7 |
| 8 | 自主性上限 + 问题清单 + 核心价值保留 + 光谱总评 | §8–§11；中文落盘本文件 |

## Decisions / deviations

1. **语料锚定 goal 002 实现 10 轮 + setup-wizard goal 001 作对照**（brief 写「10 轮」；goal 001 的 issue/机械门误报史作为机械门边界旁证，不计入「10 轮驱动」主样本）。
2. **brief 中「rounds/0009 路径缩写 false violation」**：本机现跑 `verify_protocol.py` exit 0；语料中可见多轮 Allowed 写了不存在的 `.harnessloop/rounds/NNNN/` 缩写路径（真实 round 在 `goals/.../rounds/`）。归因为 **Rule A 覆盖面过窄导致「错误 Allowed 路径不触发失败」**（见 §3），与 setup-wizard 期 Rule B 误报（TH-0006）是不同症状。
3. **只读硬约束**：未改 plugin / `.harnessloop/` 业务状态 / app；仅写本 handoff。未运行 app/内核。
4. **与 T-058 独立**：本轨未读 T-058 产出。

## Open questions

1. 「dead-reckoning 交付物计数守卫」（TH-0010 建议）的阈值 N 与误报边界，是否应做成项目可配 profile？（**未能从现有 10 轮反推默认值**）
2. 审查闸协议化时，verdict 枚举应绑定 harnessloop feedback 四分类，还是继续委托 hopper task-type 自管？（产品分叉，待用户）
3. 状态结构化（YAML/JSON frontmatter）与「全文可人读叙事」的兼容点——是否接受双轨（机器字段 + 可选长文 appendix）？

## Verdict

**PASS**

## Next recommendation

1. 将本报告 §9 问题清单作为 harnessloop evolution 候选 backlog 输入（**不要求立即实现**）；优先讨论 P0：round 绕开检测（TH-0010）与收官多写一致性。
2. 与 T-058（codex 轨）做双轨交叉：仅合并**两轨交集**问题为 must-fix 候选，分歧项标异构视角保留。
3. 若产品方向确认「更自主 continue」：先做 **state 结构化 + closeout 脚本** 两件最小机械改进，再谈 SG 选择策略；不要先加更多 prose 纪律。

---

## §0 语料与方法

| 类 | 路径 | 用途 |
|----|------|------|
| Plugin 协议意图 | `harnessloop/plugins/harnessloop/skills/harnessloop-{loop,continue,status,goal,evidence,issue,delegation,setup,secrets,intake}/SKILL.md` | 设计声称的自主边界 |
| 机械门 | `…/harnessloop-loop/scripts/{verify_protocol.py,check_setup.py,round_cost.py}` | 实际能挡什么 |
| 模板 | `…/references/{decision,round-summary,scope-lock,self-audit,feedback-policy}-template.md` | 协议最小形状 |
| Goal 002 实况 | `.harnessloop/goals/20260718-002-agent-app/{goal,goal-breakdown,feedback-policy,thresholds}.md` + `rounds/0001–0010/` | 10 轮驱动主样本 |
| 控制面 | `.harnessloop/state/{current,evidence-index,control-contract}.md`、`meta/self-audit.md`、`meta/evolution-issues/` | 状态工程 + 机制观察金矿 |
| 旁证 | `.hopper/queue.md`、T-044–T-057 handoffs、TH-0010 issue | 审查闸真实运转 / 绕开 round 事件 |

**方法**：对照「协议文本写了什么」vs「10 轮实际谁做了决策」；置信度：高=file:line 或可复现命令；中=多轮模式归纳；低=单点推断。

**假设（1 行）**：brief 中「收官六件套」按实操归纳为 scope-lock / round-summary / decision / current.md / evidence-index / self-audit（常叠加 goal-breakdown），非协议术语。

---

## §1 驱动力归属：协议产生 vs 主会话补位

### 判断

**continue gate 自主性真实成色 ≈「允许边界检查器」+「下一动作类型提示」，不是「下一业务步骤生成器」。**  
协议决定 *可否继续 / 哪一类动作被允许*；主会话决定 *具体做什么 / 怎么拆 / 审哪里 / 何时停问人*。

**置信度：高**

### 协议实际产生的东西

| 能力 | 协议出处 | 10 轮是否生效 |
|------|----------|---------------|
| feedback 四分类 + blocked 七分型 | `harnessloop-loop/SKILL.md` §Feedback / §Blocked；`feedback-policy.md` | 是（分类词被用；几乎总是 `positive`） |
| continue 前读 state / setup gate / verify_protocol | `harnessloop-continue/SKILL.md` steps 1–13 | 是（setup 已 complete；verify 被当作收盘纪律） |
| positive → 下一 subgoal；negative → 调查/最小修/回滚 | continue + loop SKILL | **类型层**是；**具体 subgoal 选择**否 |
| 必须对抗审才可接受 round | loop SKILL Verification Phase | 原则是；**闸点/vendor/brief 自创** |
| scope-lock 必填字段 | loop SKILL Round Structure | 是 |
| 机械门 Rule A/B | `verify_protocol.py` docstring | 部分（见 §3） |
| 死循环 / 矛盾 / drift 自审表 | loop SKILL Self-Audit + `self-audit.md` | 是（每轮写，但信号多为 LLM 填表） |

### 主会话（+ 用户）补位的东西（协议无硬依据）

| 决策 | 实例 | 协议有无？ |
|------|------|------------|
| 选哪个 SG / 第二批规划 | rounds/0009 decision「下一步待选」需用户参与；0010 选 SG-11 | **无**自动排序器；仅「continue to next subgoal」空话 |
| 阶段切分 A/B/C | rounds/0005–0006 scope-lock 阶段表 | **无** |
| ★审查闸设在哪、审什么主题 | 0005 起「continue 驱动 + 关键节点独立审查」；0007「CI 绿灯是否真红」 | 协议只说 *应* adversarial review，**不规定闸位/主题** |
| 收敛守卫「第 3 轮 MUST-FIX → checkpoint」 | 0005 self-audit；0006/0007/0009/0010 scope-lock 明文 | **会话自设**，非 skill 规则 |
| teeth 破坏性反证纪律 | 0006 起系统化；0007 T-054 延续 | **会话自设** |
| vendor verdict 词汇 REWORK / MUST-FIX / CONFIRMABLE / PASS_WITH_NOTE | hopper handoffs；再映射到 feedback=`positive` | **非 harnessloop 协议枚举**（协议只有 pos/neg/neutral/blocked） |
| 措辞纪律（SG-8.1④ 拆层） | 0009 decision 采纳 T-057 NOTE | 协议无「诚实措辞」机械门 |
| code-impl 永不派第三方 | 项目 `.hopper/AGENTS.md` / CLAUDE.md | harnessloop 委派矩阵允许 low-risk impl 委派；**项目策略更严** |
| 绕开 round 三个 SG 后补记 | TH-0010 + rounds/0001 | 协议**未检出**（见 §3/§7） |

### 「continue 驱动」成色一句话

从 rounds/0005 self-audit 起项目自称首次验证「continue 驱动 + 关键节点独立审查」——这里的 continue **是人为编排的阶段推进仪式**（scope-lock 已写好阶段表与闸），不是 skill 读 state 后生成阶段表。  
**自主性光谱位置见 §11：约在 25–35%（偏协议账本端）。**

---

## §2 状态文件工程性

### 判断

**状态面已从「控制面索引」退化成「叙事复写库」**：同一轮事实在 5–6 处长文重复；`current.md` 单元格承载整段 round 史诗；线性膨胀已威胁长期 goal 可持续性。

**置信度：高**

### 证据

| 文件 | 规模（约） | 观察 |
|------|------------|------|
| `state/current.md` | ~22 KB / **21 行** | 行级巨块：`Next proposed action` 单 bullet 含整轮收敛史 |
| `goal-breakdown.md` | ~137 KB / 199 行 | 议程表 + 大段决策叙事 |
| `meta/self-audit.md` | ~97 KB / 843 行 | 每轮完整 checklist 复写；**AUDIT 条目 ≥14** |
| `state/evidence-index.md` | ~22 KB | 相对克制，仍有长 Notes |
| rounds 三件套合计 | **2052 行**（0001–0010 的 summary+decision+scope-lock） | 随轮次增厚（summary 0001=87 行 → 0009=112 行） |

**重复度抽样**：词 `SG-8` 在同一收官窗口内出现次数：

| 文件 | 命中 |
|------|------|
| self-audit.md | 67 |
| goal-breakdown.md | 27 |
| rounds/0009/round-summary.md | 24 |
| rounds/0009/decision.md | 21 |
| current.md | 10 |
| evidence-index.md | 7 |

协议自称（loop SKILL State Files）：*「Keep state files as control-plane indexes. They are not the sole source of truth.」*——实操相反：current/self-audit 变成第二真相源，且与 round 文件互相粘贴。

### 机器可读性

- 模板字段存在（decision-template 的 Feedback/Blocker type 等），但实盘 decision/round-summary **大量散文段**，无稳定 frontmatter。
- 无 schema 校验「current.Active round 是否等于最新 rounds/ 目录」「goal-breakdown SG 状态是否与 decision 一致」。
- TH-0010 已坐实：三份 state 可集体滞后于 git 实交付而 **零机械报警**。

### 可持续性影响

| 风险 | 影响 |
|------|------|
| 上下文成本 | 主会话每次 continue 须吞 current + 最近 decision/summary → token 税随轮线性涨 |
| 一致性风险 | 六处手写，漏改即自相矛盾（self-audit 专查 Self-contradiction，但检查本身也是 LLM） |
| 检索成本 | 新会话 onboarding 读 current 21 行巨块 ≈ 读一篇短文，不是读状态机 |
| 自动化上限 | 无法可靠 script「列出所有 pending SG」「第几次 REWORK」 |

---

## §3 机械门能力边界

### 判断

**机械门守住的是「协议文件卫生」的窄子集，守不住「业务真实性 / 证据质量 / 是否绕开 round / 代码是否越 scope」。** 审查质量 100% 依赖会话自设的 hopper 异构闸。

**置信度：高**

### `verify_protocol.py` 实际挡什么

源码自述（`verify_protocol.py:1–41`）：

- **Rule A**：round 的 `evidence/` + `reviews/` 下文件路径 ⊆ scope-lock `## Allowed Changes`
- **Rule B**：review 中 pathish 反引号引用须存在（含豁免）
- **明确不做**：判断证据是否支持验收（*Judgment gates stay with the model*）

**挡不了 / 弱项（有语料）：**

| 缺口 | 证据 |
|------|------|
| **不扫业务代码改动** | `harnessloop/adversarial-review-p0.md` m7：Rule A 根本不看 agent 对真实源码的写入；scope-lock「心理预期」≫ 机械覆盖 |
| **Allowed 路径写错可不失败** | 0007/0008/0009/0010 Allowed 含 `` `.harnessloop/rounds/NNNN/` ``（磁盘上无此树；真路径在 `goals/.../rounds/`）。本机 verify **exit 0**——错误 Allowed 行不被罚，因 Rule A 只约束 evidence/reviews 落点是否∈某个 allowed span |
| **无 evidence/reviews 的轮次** | 0001–0008 多数无 reviews/ 或仅有极简结构时，Rule A 几乎空转；0009 才有 `evidence/track-*.md` |
| **历史 Rule B 误报** | TH-0006：setup-wizard round0001 评审 6/6 dangling 误报（后 fixed）；TH-0008 fragment 仍 open |
| **绕开整个 round 闭环** | TH-0010：SG-1/2/6 无 round 完成，continue/self-audit **无 dead-reckoning 信号** |

### `check_setup.py`

- 只挡 core 文件仍为 template/missing（environment / control-contract / cost-context-policy）
- goal 002 全程 `complete=true` 后，**对实现阶段漂移零贡献**

### 审查质量：协议有无内建支撑？

| 协议有 | 协议无 |
|--------|--------|
| 「Must assign adversarial review」原则 | 审查 brief 模板与「证伪式」主题生成 |
| adversarial-review-template.md | REWORK 闭环轮次计数与强制 checkpoint |
| 「机械 pass ≠ 协议 pass」分层声明（loop SKILL:442） | 与 hopper verdict 的正式映射 |
| 委派矩阵：对抗审 *Must delegate when mechanism exists* | 强制异构 vendor / 禁止自审验收的机械开关 |

**旁证**：T-048→T-053 多层假绿被抓、T-057 措辞诚实性 NOTE——**全部来自 hopper 任务 + 主会话编排**，不是 harnessloop skill 内建流水线。

---

## §4 收官成本与「六件套」重复

### 判断

**每轮收官是高认知负载的多文件人工一致性维护；模板有形状无自动化；重复劳动与不一致风险随轮次上升。**

**置信度：高**

### 实操六件套（归纳）

1. `rounds/NNNN/scope-lock.md`（开工前）  
2. `rounds/NNNN/round-summary.md`  
3. `rounds/NNNN/decision.md`  
4. `state/current.md`  
5. `state/evidence-index.md`  
6. `meta/self-audit.md`  
（常 +7）`goal-breakdown.md` / `thresholds.md` 行状态

协议 Loop Continuation（loop SKILL:491–502）要求：verify → summary(+cost) → decision → archive handoffs → self-audit 视情况 → 按 feedback 续。  
**未要求** current/evidence-index/goal-breakdown 的字段级同步脚本——全靠主会话记忆。

### 模板 vs 实盘

| 模板 | 实盘 |
|------|------|
| decision-template：短字段列表 | 0009 decision ~76 行，含完整双轨叙事 |
| round-summary-template：短节 | 0009 summary ~112 行 / 20KB+ |
| self-audit-template：表格式 | 每轮整表重填 + 长 Reason |

`round_cost.py` 是唯一接近「自动收官」的脚本（且依赖 Claude Code transcript）；**无 multi-file closeout 工具**。

### 成本量化（粗）

- 单轮三件套：~150–250 行手写/粘贴  
- 叠加 state/self-audit：再 +1–3KB 叙事  
- 10 轮仅 round 三件套 **2052 行**；self-audit 单文件近 **100KB**  
- 一致性检查完全非机械 → 主会话「收官税」是自主性的隐形上限

---

## §5 feedback 分类与收敛机制归属

### 判断

**四分类区分度在实现阶段被压扁为「几乎总是 positive + 长 Open Risks」；rework 收敛守卫与 vendor verdict 体系属于会话/hopper 层，非 harnessloop 协议内建。**

**置信度：高**

### 协议四分类

`feedback-policy.md` + loop SKILL：

- positive / negative / neutral / blocked（+ 本 goal 探索性否定→记 positive 的特款）

### 10 轮实际分布（实现阶段）

| 轮 | 名义 feedback | 实质 |
|----|---------------|------|
| 0001 | positive | 补记归位 |
| 0002–0004 | positive | 交付 + 偶发 access-missing 局部 |
| 0005–0009 | positive | **轮内**多 REWORK/MUST-FIX，收盘仍 positive |
| 0010 | in-progress | — |

**区分度问题**：轮内对抗审 REWORK 被当作 recovery，不改变 round 级 feedback → 四分类对「实现收敛过程」分辨率不足；真正有用的状态机在 **hopper task 状态 + scope-lock 阶段表**。

### 收敛守卫归属

- 文案：「同一阶段第 3 轮 MUST-FIX → 停下 checkpoint」  
- 出处：rounds/0005 起 scope-lock / self-audit（主会话写入）  
- **loop/continue SKILL 全文无 MUST-FIX、无「第 3 次」阈值**  
- 10 轮中守卫**设置但很少触发**（0006 Stage A/B 各在第 2 轮内收敛；0009 0 次 REWORK）——机制有价值，但是**项目惯例**

### Verdict → feedback 映射

| Vendor/项目 verdict | 协议 feedback | 谁映射 |
|---------------------|---------------|--------|
| REWORK / MUST-FIX | 通常不改 round feedback；进收残 | 主会话 |
| PASS_WITH_NOTE | positive + 采纳 NOTE | 主会话 |
| CONFIRMABLE | positive / 收官 | 主会话 |
| 过滤器中止（T-046） | 改派，非 blocked | 主会话 + 项目纪律 |

**协议无 REWORK 一词。** 对抗审模板也不定义与 feedback 的双射。

---

## §6 实效正面清单（被 10 轮证明有效）

| 机制 | 实效实例 | 置信度 |
|------|----------|--------|
| **scope-lock 先于执行** | 0002 起闭环；与 0001 前绕开形成对照（TH-0010 修复效果实测） | 高 |
| **Rollback / Disallowed 撞线停下问人** | 0004 两次 openclaw 补丁扩围 user-confirmed；0006 SG-5 `stop()` 缺口触发 Rollback Condition → AskUserQuestion 定向修 | 高 |
| **诚实分层 defer** | 0006 Stage C；0009 SG-8.4③ / mint 501 residual；不把 defer 写成 done | 高 |
| **evidence-index 可追溯** | E 编号回指 handoff/commit；审查可点路径 | 高 |
| **对抗审真抓缺陷** | T-048 臆造字段、T-050 表面绕过、T-052 remap 假绿、T-057 措辞拆层 | 高 |
| **self-audit 作为观察金矿** | AUDIT 条如实记 vendor 过滤器、绕开 round、teeth 纪律——**框架验证项目的核心产出形态** | 高 |
| **setup / check_setup 门** | 实现阶段前完成；后续无 setup 阻塞噪声 | 中（样本少） |
| **contract-insufficient 路径** | 0004 不擅自改内核，先修契约/授权 | 高 |
| **探索性否定→positive 特款** | 设计阶段 D1 多轮 REWORK 不计失败（goal.md 决策节） | 高（设计阶段） |

**这些是 harnessloop 的「协议压力」+ 主会话遵守的合成效果**——去掉协议文件纪律，单靠 chat 难以复现同等审计迹。

---

## §7 低使用率机制

| 机制 | 使用率（goal 002 实现 10 轮） | 原因判断 |
|------|------------------------------|----------|
| **harnessloop-issue** | 实现期仅 **TH-0010** 新增；0001–0009 共 10 个 issue 中 9 个集中在 2026-07-16/17 setup-wizard 爆发期；TH-0008 仍 open 但未再 analyze/propose-fix 流水线 | 实现期把问题标为「项目/设计」而非 framework；issue skill 的 analyze/propose-fix **几乎未作为常规步骤**；open issue 不阻断 continue |
| **`$harnessloop-delegation`** | **0 次**正式 skill 调用痕迹 | 委派规则固化在项目 AGENTS.md/CLAUDE.md；主会话直接派子代理/hopper，跳过 delegation 自检仪式 |
| **intake** | **0**（goal 002 非接管） | 场景不匹配；能力闲置属预期 |
| **`$harnessloop-evidence` add/check** | 低（evidence 多直接写文件 + index 手改） | skill 颗粒度与「写 markdown」重叠，会话倾向直写 |
| **`$harnessloop-status`** | 低（直接读 current.md） | 同上 |
| **evals/matrix.md** | 非运行门（协议自承） | 未观察到驱动决策 |

**issue 机制反差**：setup 期 issue→fix 闭环极强（TH-0001–0009 多数 fixed）；实现期 **发现问题 → 记 round Open Risks / self-audit Reason → 不升 issue** 成主路径。TH-0010 是例外且仍 **open**（框架守卫未落地）。

---

## §8 自主性上限与结构性改进方向

### 若要让 continue 更自主，缺什么（按杠杆排序）

| 方向 | 解决什么 | 注意 |
|------|----------|------|
| **1. 结构化 state**（YAML/JSON 字段：active_round, feedback, sg_status[], rework_count, blockers[]） | 膨胀/重复/机器决策 | 保留可选 narrative appendix；勿只加更长 markdown 规范 |
| **2. closeout 脚本**（一次命令生成/校验六件套字段一致性 + diff 提示） | 收官税、漏写 | 不自动编造业务叙述 |
| **3. dead-reckoning 守卫**（TH-0010：实现阶段 N 交付无 round → warn/block） | 绕开闭环 | 阈值可配；仅 IMPL 阶段 |
| **4. Rule A2：git 地基 scope 检查**（adversarial-review-p0 已建议） | scope-lock 名实相符 | 需 round 起始 HEAD marker |
| **5. 审查闸协议化**（最小：verdict 枚举 + 与 feedback 映射 + 第 k 次 REWORK 强制 human-confirm） | 收敛守卫从会话惯例升协议 | 避免绑死单一 vendor |
| **6. SG 选择策略**（goal-breakdown 依赖图 + risk/evidence 启发式建议 next） | 「下一 subgoal」空话落地 | **最终批准仍应人/主会话**（协议已规定 goal breakdown 不委派） |
| **7. 成本感知 continue**（聚合 round_cost + 预算阈值） | cost runaway 真闸 | 现 round_cost 环境绑定 Claude Code |

### 不应追求的「假自主」

- 让 continue **自动接受**对抗审 REWORK 后的 round  
- 让机械门判断「业务是否正确」  
- 取消 scope-lock / 人确认高风险写  

---

## §9 问题清单（按严重度）

### P0 — 结构性（自主性/正确性根基）

| ID | 现象 | 根因 | 影响 | 改进方向 |
|----|------|------|------|----------|
| P0-1 | 实现阶段可长时间无 round 交付，state 静默滞后（TH-0010） | continue/self-audit 无「活动 vs round」一致性信号 | 协议账本失真；验证项目一度自欺「已在 harnessloop 内」 | dead-reckoning 守卫；impl 阶段强制 per-SG round |
| P0-2 | 驱动力名「continue 驱动」实为会话编排 | continue 只做 gate，不生成下一动作内容 | 用户/外部高估自主性；换会话后惯例丢失 | 产品叙事诚实分层；或增强 next-action 建议器 |
| P0-3 | 状态六处手写巨块重复 | 无结构化 SSOT + closeout 工具 | 长期 goal 不可持续；矛盾与 token 税 | 结构化索引 + 单次 closeout 校验 |

### P1 — 机械门与质量

| ID | 现象 | 根因 | 影响 | 改进方向 |
|----|------|------|------|----------|
| P1-1 | Rule A 不检查业务代码越界 | 设计只扫 evidence/reviews | scope-lock 心理安全虚高 | Rule A2 git diff ⊆ Allowed |
| P1-2 | Allowed 路径缩写错误不失败 | Rule A 不验证 allowed span 自身可解析/存在 | 错误契约沉睡；brief 所称 false violation 同类卫生问题 | 校验 allowed 路径存在或可解析；禁 `.harnessloop/rounds/` 幽灵路径 |
| P1-3 | 审查质量全靠会话+hopper | 协议只要求「有对抗审」 | 无 hopper 的项目降级为自审 | 审查闸最小协议（输出路径、verdict 枚举、与 feedback 映射） |
| P1-4 | vendor verdict ≠ protocol feedback | 两套词汇未桥接 | 审计时「positive round 内多次 REWORK」难机读 | 映射表 + rework_count 字段 |

### P2 — 机制闲置与成本

| ID | 现象 | 根因 | 影响 | 改进方向 |
|----|------|------|------|----------|
| P2-1 | issue analyze/propose-fix 流水线实现期停用 | 成本与「先记 Open Risks」竞争 | 框架进化变慢（仅靠验证项目自觉） | 收盘 self-audit 若 Reason 含 framework → 提示 issue record |
| P2-2 | delegation skill 零调用 | 项目侧已硬编码委派策略 | skill 成为死文档 | 合并进 continue 的可选检查，或降级为参考 |
| P2-3 | 收官散文过重 | 模板过简 + 项目文化求全 | 收官失败/敷衍风险 | 强制短字段 + 长文仅链到 evidence |
| P2-4 | TH-0008 等 open issue 不挡 continue | issue 与 gate 无耦合 | 已知缺陷可无限期漂 | open packaging/skill-gap 可选 warn |

### P3 — 体验与边角

| ID | 现象 | 根因 | 影响 | 改进方向 |
|----|------|------|------|----------|
| P3-1 | feedback 四分类对实现收敛分辨率不足 | 轮级 feedback 过粗 | 状态机实际外置到 hopper | 允许 round 内 phase 状态或子 feedback |
| P3-2 | round_cost 绑定 Claude Code | 环境假设 | grok/codex 轨成本不可比 | 多 vendor cost adapter 或统一 unavailable 策略文档化 |

---

## §10 核心价值保留清单（改进时不能丢）

1. **文件型审计迹**：goal/round/decision/evidence 可 git  diff、可跨会话恢复——这是 chat 编排器做不到的。  
2. **scope-lock + Rollback Condition 的「先停后问」文化**：0004/0006 已证明能防止静默越界。  
3. **诚实 defer / 不粉饰 pass**：0009 措辞纪律与 T-057 NOTE——协议「机械 pass ≠ 协议 pass」分层必须保留。  
4. **反馈与阻断分类词汇**（即便需扩展）：提供共用语言。  
5. **self-audit 作为框架验证探针**：本项目存在的目的之一；不要为「干净 state」删掉观察金矿（可归档，不可无）。  
6. **对抗审与主会话控制决策分离**：委派矩阵「Never delegate round acceptance」——防自卖自夸。  
7. **探索性 goal 的否定结论合法化**（feedback 特款）：保护诚实研究。  
8. **setup 门与 secrets 本地化**：低运维安全底线。  
9. **evolution-issue 红线（脱敏、不拷项目私货）**：跨项目进化通道。  
10. **「索引非唯一真相」原则**——改进结构化时仍应能指向 round/evidence 原件，避免 current.md 篡权。

---

## §11 总评：光谱位置

```
纯记账协议          半自主编排脚手架              真自主驱动引擎
|<------●==========================================>|
        ^
        本评估定位：约 25–35%
        （强协议账本 + 弱动作生成 + 零业务判定机械门）
```

**一句话**：harnessloop 今天最擅长的是 **逼主会话把工作写进可审计文件，并在继续前经过一串可读门禁**；它不擅长 **自己决定下一步业务、自己保证证据为真、自己维持状态一致性**。goal 002 首批 SG 全清是 **「纪律型主会话 × harnessloop 账本 × hopper 异构审」** 的三方成功，任一抽掉都会显著掉队。

**对产品叙事的建议**：对外称「evidence-backed control loop / 抗漂移协议」比「自主驱动引擎」更诚实，也更利于改进优先级（先机械一致性与 scope 真闸，后动作生成）。

---

## §12 来源索引（主）

| 来源 | 用途 |
|------|------|
| `harnessloop/.../harnessloop-loop/SKILL.md` | 协议主合同、verification 双门、continuation 步骤 |
| `harnessloop/.../harnessloop-continue/SKILL.md` | continue gate 步骤 |
| `harnessloop/.../scripts/verify_protocol.py` | 机械门边界 |
| `harnessloop/adversarial-review-p0.md` | Rule A 覆盖面批评（m7） |
| `.harnessloop/meta/evolution-issues/0010-*.md` | 绕开 round 框架级观察 |
| `.harnessloop/meta/evolution-issues/0006-*.md` | Rule B 误报史 |
| `.harnessloop/meta/self-audit.md` AUDIT-20260723…0009 | 机制观察主矿 |
| `.harnessloop/goals/.../rounds/0005–0009/scope-lock.md` | continue 驱动模型、收敛守卫、Rollback |
| `.harnessloop/goals/.../rounds/0006/scope-lock.md` L40–44 | stop() Rollback 实例 |
| `.harnessloop/goals/.../rounds/0009/{decision,round-summary}.md` | 收官六件套样本、措辞纪律 |
| `.harnessloop/state/current.md` | 巨块状态样本 |
| `.hopper/handoffs/T-048`–`T-057`（queue 摘要） | 审查闸实效旁证 |
| 本机 `python3 …/verify_protocol.py --project .` → exit 0 | 当前机械门绿、路径缩写未失败 |

---

*End of T-059 report (grok track).*

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll execute the prd-research task directly: pull the queue brief and task frame, then research and write the deliverable.Gathering the 10-round drive records, plugin source, and a prior prd-research output for format.Digging into protocol skills, mechanical gates, self-audit, and round artifacts for evidence.Synthesizing findings into the T-059 deliverable from the corpus evidence.# T-059 complete (grok track)\n\n## Summary\n\nEvaluated harnessloop’s real “autonomous goal driving” using goal 002 rounds 0001–0010 plus plugin skills/mechanical gates. **Verdict: strong file-backed control ledger + gate scaffolding (~25–35% on the pure-ledger → full-autonomy spectrum), not a self-planning engine.** Protocol owns feedback/blocker taxonomies, scope-lock shape, narrow mechanical checks, and “must adversarial-review”; the main session owns SG choice, stage cuts, review gates, convergence guards, verdict mapping, and wording discipline. Full report: `.hopper/handoffs/T-059-output.md`.\n\n## Files touched\n\n- `.hopper/handoffs/T-059-output.md` — sole deliverable (research report)\n\n## Acceptance verification (8/8)\n\n| # | Criterion | Where |\n|---|-----------|--------|\n| 1 | Drive-force attribution | §1 |\n| 2 | State-file engineering | §2 (~22KB/21-line `current.md`, ~97KB self-audit, SG-8 multi-file duplication) |\n| 3 | Mechanical-gate bounds | §3 (`verify_protocol` Rule A/B, TH-0010, path abbreviation) |\n| 4 | Closeout / six-piece cost | §4 |\n| 5 | Feedback + convergence ownership | §5 (3rd MUST-FIX = session, not skill) |\n| 6 | Effective positives | §6 (scope-lock, rollback, defer, evidence, reviews) |\n| 7 | Low-use mechanisms | §7 (issue/delegation/intake) |\n| 8 | Autonomy ceiling + problem list + keep-list + spectrum | §8–§11 |\n\n## Decisions / deviations\n\n- Goal 001 issue history used only as mechanical-gate side evidence.\n- Brief “0009 path false violation” → observed as wrong Allowed path form with **verify still exit 0** (Rule A too narrow), not a live Rule B false positive.\n- Did not read T-058 (independent dual track).\n\n## Open questions\n\n- Dead-reckoning threshold N (TH-0010); whether review verdicts should map into protocol feedback; structured state vs narrative dual-track.\n\n## Verdict\n\n**PASS**\n\n## Next recommendation\n\nCross with T-058 on **intersection-only** P0s; if product wants “more autonomous continue,” prioritize structured state + closeout consistency + TH-0010 guard before richer next-action generation.",
  "stopReason": "EndTurn",
  "sessionId": "019f9ac8-30c4-7c40-b5b0-c02ddce29e92",
  "requestId": "66de51d9-7fe8-4671-9492-bf91dbf6c0ac",
  "thought": "The user wants me to execute a prd-research task as a hopper-dispatched execution agent. Let me gather the task details from the queue and related files.I have a clear picture of T-059. It's a research evaluation of harnessloop plugin's autonomous driving capability, based on:I need to read the full T-058/T-059 task spec from leader-tasklist.md, then systematically analyze the 10 rounds and plugin source.I need deep analysis of protocol source, self-audit, continue skill, loop skill, verify_protocol, feedback-policy, and sample round docs. Let me systematically gather evidence for the 8 evaluation que...I need more specific evidence for:I have strong evidence. Let me also check:The brief mentioned \"rounds/0009 scope-lock 路径缩写触发 false violation\" - let me search more specifically for that.I have enough material to write a comprehensive research report. Note: task says research only, no code/edits - but the output must land at `.hopper/handoffs/T-059-output.md`. Writing the handoff outp...**Summary**  \nI researched the protocol-driven development framework used by Hopper, focusing on feedback classes, blocker taxonomy, continue gates, adversarial review, and state-file engineering patterns. Key findings include high-confidence drive forces for SG-next and ★审查闸 placement, plus sustainability risks from linear growth in self-audit files (SG 67 mentions). Mechanical gates show limited code-change validation, and closure costs average 2-3K lines per round. Effective positives center on scope-lock timing and evidence-index traceability, while low-usage mechanisms highlight setup-wizard issues.\n\n**Files touched**  \n.hopper/handoffs/T-059-output.md — generated 4-sentence summary, acceptance verification, decisions, open questions, verdict, and next recommendation per prd-research output shape.\n\n**Acceptance verification (N/N)**  \n- Research synthesis complete: all key findings from queue.md brief covered.The deliverable is written. Let me verify the acceptance criteria are met and the file is complete. The task said research only - I only wrote the output file which is required. I should not update qu...",
  "usage": {
    "input_tokens": 131126,
    "cache_read_input_tokens": 598912,
    "output_tokens": 13178,
    "reasoning_tokens": 3462,
    "total_tokens": 743216
  },
  "num_turns": 9,
  "total_cost_usd": 0.5209936,
  "total_cost_usd_ticks": 5209936000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 131126,
      "outputTokens": 13178,
      "cacheReadInputTokens": 598912,
      "modelCalls": 9,
      "costUSD": 0.5209936
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 240178
- end_time: 2026-07-25T19:41:16.385Z
- log: see `T-059-output.log` for raw output
