# harnessloop 审核：外部系统配置化 + runtime evals 硬门 + 单会话自主 loop（2026-07-28）

> **审核目标**（用户需求，2026-07-28）：通过 harnessloop 框架能支持通过配置链接外部
> 系统，补充静态分析和单元测试以外的 runtime / 多系统测试作为任务实现结果的 evals，
> 通过完整的设置保证 loop 尽可能自主化、安全地实现 harnessloop-goal。核心 skill 视角：
> `harnessloop-goal`（契约端）与 `harnessloop-continue`（推进/救援端）——**应更多依赖
> 自主完成 goal，continue 只做万不得已的人工推回**。
>
> **三项已裁决的语义**（user-confirmed 2026-07-28，审核基准）：
> ① evals = **硬门**（已声明的 eval 未跑或未过 → 该轮不得判 positive，机械门可见可拒）；
> ② 自主化 = **单会话多轮自续**为主线（跨会话调度只记附带观察）；
> ③ 外部写边界 = **已声明系统上的测试资源写 + 清理可被契约预授权**，生产/不可逆写仍停人。
>
> **修订 2026-07-28（T-074 对抗核实后）**：正文就地修正 5 处事实错误（轮数 14 非 20、
> Stop 清单 6 条非 5、verify_protocol 的 eval 命中 2 处非 3、GAP-1 读者范围过窄、
> GAP-4 行号偏宽）；资产清单按 T-074 反向核实降级表述；O-1..O-10 遗漏与修订后的
> 分步建议见文末附录 A。原始版本在 git `c40ff73`。
>
> **审核对象**：harnessloop **v0.26.0**（`b389eac`）源码 + 本项目 14 轮实践语料
> （goals 001/002 全部 round 文档、`.harnessloop/state/*`、goal 002 的 thresholds.md 实例）。
> 审核产出是**卡点清单**，不是修复；每条卡点带 file:line 证据。改进方向仅列候选，
> 是否立项待用户裁决。

## 1. 总判

**需求所需的概念，散文层几乎全有；机械门对它们全部失明。**

逐个点名散文层已存在的概念：

| 需求要素 | 散文层已有的对应物 | 机器读吗 |
|---|---|---|
| 外部系统登记 | `setup/data-sources.md` 的 Runtime Validation Systems 表（System/Access method/Validation method/Pass condition/Failure handling/Credential requirement/Local parameter reference 七列，`data-sources-template.md:16-19`）与 External Tools And Platforms 表（含 **Read/write scope** 列，`:21-24`） | **否**（仅 check_setup.py 查"填没填"，内容零解析） |
| runtime eval 声明 | 每 goal `thresholds.md` 的 **Runtime Thresholds 表**（Runtime surface/Validation method/**Pass condition**/Observation window/**Evidence path** 五列，`thresholds-template.md`）+ Verification Thresholds 表（含 **Command/check** 列） | **否**（零解析器） |
| 每轮验证命令 | scope-lock 必须定义 "**Verification commands or checks**"（loop SKILL.md:356） | **否** |
| runtime 证据落点 | 轮结构自带 `evidence/runtime/` 目录（loop SKILL.md:343） | 仅 Rule A 查容器包含，内容零解析 |
| 测试资源写的合法性 | write-safety-required blocker 定义是**条件式**："without **declared** dry-run/**test-resource**/rollback/human confirmation"（continue SKILL.md:46）——暗示"声明了就不阻塞" | **无处可做出那个 declared**（见 GAP-5） |
| 单会话多轮自续 | Loop Continuation step 6（loop SKILL.md:556）+ "**Stop only when**" 六条穷举清单（:560-567） | 停止**不落任何痕**（见 GAP-4） |
| goal 级验证选项 | `goal-breakdown-template.md:16` "Runtime validation options" 字段 + subgoal 表 Validation method 列 | **否** |

这个断裂形状与 **B2a 之前的 Review 断裂完全同形**：评审真实存在（.hopper/handoffs 里 70 份），
但 decision.md 不声明、机械门不知道——直到 v0.17.0 加了 `Review:` 字段 + 存在性/摘要核对。
**修复模板是现成的、已验证过两次的**（B2a 的声明字段接线、reference-roots 的两文件声明 +
探活 + coverage 可见）。

因此总判是：**满足需求的主体工作不是发明新概念，而是把已有散文概念逐个接上机械门**，
外加两处真正缺失的词汇（测试资源写预授权的落点、loop 停止落痕）。这决定了改造的风险
形状——接线类改造在本项目有成熟方法论（规格 → 对抗审 → teeth → 破坏性反证），而
"发明新概念"类改造才是高风险的。

**对初判的两处诚实修正**（展开阶段的假设被源码证伪）：
- 初判"loop 多轮自续语义不明"——**错**。协议明文要求自续（GAP-4 重新定性为"停止无痕"）。
- 初判"continue 把例行推进与救援合并是架构级卡点"——**降级**。continue 的输入契约措辞
  （"resume/advance"）确有合并，但 Loop Continuation 本身就是 loop 内部的推进机制，
  continue 在协议文本上主要是**重入门**。真正的问题在 GAP-4，不需要拆 skill。

## 2. 卡点清单

### GAP-1（R1）外部系统声明与执行层之间没有桥

**证据**：
- `data-sources-template.md:16-24`：Runtime Validation Systems / External Tools 两表全部自由文本。
- 全插件树 grep：**解析**它的代码为零。`check_setup.py` 只查填充度、`init_project.py` 只落模板；`channels`/`connectivity`/`secrets` 三个 skill 在协议层要求 agent 读它（模型侧 inventory/探活约定，见附录 A O-7），但同样**没有任何代码解析表格内容**；`verify_protocol.py` 仅在 docstring 里把它当
  PATHISH 前缀示例（:48、:2787）。
- setup SKILL.md 明文：data-sources **刻意排除**在 gate-blocking 三文件之外
  （"deliberately excluded... A fully-skipped data-sources file cannot make any
  continuation gate unevaluable"）。这个设计在"声明只是文档"的世界里是对的；
  在"声明要驱动执行"的世界里恰好是断点。

**为什么卡**：声明了 new-api/hermes gateway 这样的系统，loop 没有任何机制据此探活、
绑定本机端点、或在系统不可达时给出结构化的 `unavailable` 事实——每次 e2e 都靠会话
临场编排（本项目 SG-8/SG-9 的全部探针皆如此）。

**定性**：协议缺失（声明↔执行断裂）。
**改进方向候选**：把 reference-roots 的两文件模式从文件系统域扩展到服务端点域——
versioned 声明（system id、用途、探活方法、测试资源边界、清理契约、凭证参数名）+
gitignored 本机绑定（endpoint/端口）+ 探活 sentinel + `external_systems_declared/available`
进 coverage。该模式的 alias-only、fail-closed、G20 不泄漏本机路径等纪律全部可复用。

### GAP-2（R2）eval 契约有列名、无 schema、无解析器

**证据**：
- `thresholds-template.md`：Verification Thresholds（Command/check | Pass condition |
  Fail condition | Evidence path）、Runtime Thresholds（Validation method | Pass
  condition | Observation window | Evidence path）——**列名正是 eval 契约需要的**。
- 本项目实例 `.harnessloop/goals/20260718-002-agent-app/thresholds.md:30-38`：Runtime
  表已被真实内容填满（server API build+run 探针、D2 wire event schema 校验、内核健康
  底座……每行都有验证方法/pass 条件/evidence path）。**实践已经在按需求的形状声明
  runtime evals——机器从没读过任何一行。**
- `goal-breakdown-template.md:16,27,32`：goal 级 "Runtime validation options" 字段与
  subgoal 表 Validation method 列，同为散文。

**为什么卡**：同一条 threshold 无法被机器对应到某一轮的实际执行——"SG-8 的 runtime
threshold 这轮跑没跑、结果如何"没有机器可读的载体。

**定性**：协议缺失（schema 与结果载体缺失）。
**改进方向候选**：threshold 行获得稳定 ID；每轮产出机器可读的 eval 结果文件
（`evidence/runtime/eval-results.json`：threshold-id → ran/pass/fail + evidence 路径），
散文表保留为人读视图。

### GAP-3（R3，核心卡点）判定链在「eval ↔ 机械门」处断裂——硬门语义下的两类假绿全开着

**证据**：
- `decision-template.md` 全字段：Feedback/Verdict/Residuals/Blocker/Review×4/
  Mechanical gate/……**没有任何 eval 或 threshold 结果字段**。
- `verify_protocol.py`：全文 grep "eval" 仅 **2** 处无关命中（PATHISH 前缀 `evals/` :310、英文 evaluated :1647）。
  机械门对 eval 的存在**零感知**。
- loop SKILL.md:442 明文分层："a round that exits verify_protocol.py clean still fails
  if adversarial review, **thresholds**, or feedback classification are not satisfied"
  ——thresholds 被划在**模型判断层**。
- Loop Continuation step 1（:551）：positive 的唯一机械否决是 verify_protocol exit
  非零；step 3（:553）声明的是 Review 字段——eval 不在任何否决路径上。
- 停止条件 "Verification thresholds cannot be evaluated"（:567）是散文自觉，无机器痕迹。

**为什么卡**：用户裁决 evals=硬门。当前"声明了没跑"（threshold 表有行、本轮无执行）
与"跑了改判据"（改 thresholds.md 让结果达标）两类假绿在机械层都不可见。后者甚至
连 Rule A 都看不见——thresholds.md 在 goal 目录，不在 round 的 scope-lock 检查域。

**定性**：协议缺失（判定链断裂）；**修复有已验证同形先例**（B2a Review 字段 wiring：
`parse_review_fields`/`check_review_declaration`，v0.17.0）。
**改进方向候选**：decision.md 增 `Evals:` 字段（指向本轮 eval 结果文件或
`none — <理由>`）；机械门核对：字段存在、路径 containment、结果文件 schema 合法、
**声明为本轮到期的 threshold-id 全部 ran**、pass/fail 与 Feedback 的一致性（fail 却判
positive → 违规）；thresholds.md 内容摘要进 coverage（防同轮改判据，同
`external_roots_declared` 防同轮换声明的既有做法）。可按 B2a 先例**分步**：先入账
（字段+存在性）再硬门（一致性否决）。

### GAP-4（R4）自主性的真卡点：协议要求自续，但**停止不落痕**——偏离免费且不可见

**证据**：
- loop SKILL.md:556：step 6 "If feedback is positive and the goal is not achieved,
  **continue to the next subgoal or task**"；:560-567 "**Stop only when**" 六条穷举（goal 达成/
  缺人输入/缺访问事实/写安全缺失/数据契约不可满足/阈值不可评估）。**"等用户敲 continue"
  不在清单里。**
- 实践语料：goal 002 全部 10 轮（+goal 001 的 4 轮）每轮收盘即停，`state/current.md`
  的 "Next proposed action" 一律以"下一 continue 开 SG-X"收尾——**14/14 轮**由人工推进（4+10，磁盘 rounds/ 目录实数）。
- 协议里没有任何机制记录"loop 为什么停"：决策文件无 stop-reason 字段，self-audit 的
  确定性信号清单（loop SKILL.md:330 附近）不含停止事件，coverage 无停止计数。
- 会话现实（上下文/成本压力——本项目单轮动辄数十万 token）没有对应的协议词汇：
  没有"round 预算/checkpoint 节奏"可声明，"为了上下文安全而停"只能以静默方式发生。

**为什么卡**：一个不在 "Stop only when" 清单里的停止**不会被任何机制标红**——偏离
零成本，于是实践必然漂向每轮停。这正是"绿灯≠真守门"的自主性版本：协议文本许诺了
自续，没有 teeth 保证它。

**定性**：**实践偏离 + 协议缺 teeth**（不是缺语义——初判在此被证伪）。
**改进方向候选**：①停止落痕——loop 停止时必须写 stop-record（停止原因 ∈ 枚举 +
对应哪条 Stop 条件；"用户主动打断"与"上下文/成本 checkpoint"成为**合法且显式**的
枚举值而非静默逃逸）；②control-contract 增加 round 预算词汇（连续自续的轮数/成本
上限，到达即合法 checkpoint 停）；③continue 的输入契约措辞收窄为重入/救援
（"resume after a stop"），例行推进归 Loop Continuation——文字层修正，非架构手术。

### GAP-5（R4+R5）测试资源写预授权：blocker 定义留了缝，但契约无落点、停人步骤无条件

**证据**（三处文本互相矛盾）：
- continue SKILL.md:46：write-safety-required 定义**条件式**——"without **declared**
  dry-run/**test-resource**/rollback/human confirmation"。暗示：声明了测试资源边界的
  写不构成该 blocker。
- continue SKILL.md:36（step 9）：**无条件**——"If the blocker requires write cleanup,
  **external mutation**, ... stop and ask the user"。
- `control-contract-template.md:25` + `control-contract-profiles.md:30`：
  "Irreversible or external-system write: required"——**三档 profile（含 lite）一致
  要求人工确认**，无任何"已声明测试系统上的测试资源写"分支。
- 唯一能容纳"Read/write scope"的地方是 data-sources External Tools 表的散文列
  （`data-sources-template.md:23`）——机器不读（GAP-1）。
- **预授权模式可行的实践证明已存在**：本项目 `state/control-contract.md:22` 的 git push
  例外条款（user-confirmed 2026-07-17，四仓批次验收通过后免逐次确认 + bump 前置条件）
  ——一条手写的、带条件的外部写预授权，运转至今。它证明这个词汇**能用**，缺的是结构。

**为什么卡**：按字面协议，e2e 的每一次测试写（建测试 token、发探针请求、删自建资源）
都应停人——与"单会话多轮自续"直接冲突。本项目 SG-8/8.5/9 的实际做法是 scope-lock 写
一行 + 用户轮前确认，属逐次人工，不可复用。

**定性**：契约词汇缺失（缝已留、落点没有）+ 协议文本自相矛盾（:36 vs :46）。
**改进方向候选**：control-contract 增结构化预授权块——(已声明系统 id × 操作类
{probe-read, test-resource-create, test-resource-delete, cleanup} × 资源域声明 ×
清理契约)；与 GAP-1 的系统声明联动（只有已声明系统可被预授权）；生产/不可逆写保持
三档一致停人；同时修 :36/:46 的矛盾（step 9 改为"未被契约预授权的外部写才停人"）。

### GAP-6（R5）evidence 自动写入无插件层 secret 守门——自主化会放大已出过事故的那条链

**证据**：
- `docs/security-incident-20260726.md` §2：泄漏路径正是"探针子代理把真实运行配置原样
  写进 evidence → vendor 原始日志回显 → public 仓"。§7 遗留建议 1（"在写的一端脱敏"）
  至今未做。
- 插件树内 grep：无任何 secret 扫描/脱敏能力。本项目的三层守门
  （`scripts/check-secrets.sh` L1-exact/L1-digest/L2 + pre-commit + CI）是
  **test-harnessloop 仓的脚本**，不随插件走——换一个项目用 harnessloop，这条防线不存在。

**为什么卡**：runtime evals 自主化 = 更多子代理自动写 evidence、更多外部系统真实
配置流经 evidence——事故面的系统性放大，而防线在插件层为零。

**定性**：插件能力缺失（安全）。**注**（T-074）：事故档案 §7 建议 1 原文指向 hopper
vendor 日志**写端**；本 GAP 的主线是 harnessloop 自己的 evidence 写端——两条链相邻但
不同，hopper 侧仍按 §5 排除在本审核外、在事故档案挂账。
**改进方向候选**：evidence 写入纪律进协议（brief 级"只写参数名"已有，可加机械抽查：
evidence 文件对 channel-params 已登记值做 L1 摘要比对——摘要不含明文的做法本项目已
验证）；或最低限度把"未装 secret 守门"变成 setup 自检的一个显式 warning 项。

### GAP-7（术语）`evals/` 命名空间已被占用且语义不同

**证据**：`init_project.py:35` 把 `eval-matrix-template.md` 落到
`.harnessloop/evals/matrix.md`；loop SKILL.md:545 明文 "The eval matrix is **not a
runtime gate** by itself"——它是 loop **policy 健壮性自查清单**（13 个维度的场景覆盖表），
与用户语义的"任务验收 evals"完全不同；且 `evals/` 是 verify_protocol 的 PATHISH 前缀
（:310）。

**为什么卡**：本审核落地时若沿用 "evals" 命名，同一项目里会有两个同名异义的机制，
文档、记忆、评审语料全部两义。

**定性**：命名冲突（小，但必须在动手前处置）。
**改进方向候选**：新机制命名避开（如 `runtime-checks` / `acceptance-evals` 择一），
或将 policy matrix 改名（有迁移成本，init 落点与 PATHISH 前缀都要动）。

## 3. 已具备的资产（T-074 反向核实后的降级表述——诚实记账）

> 初版此节偏乐观；T-074 逐条反向核实后，多条从"可复用机制"降为"可借纪律/先例"。
> **降级不改变总判**（接线为主仍成立），但改变各 EV 的工作量估计。

1. **`evidence/runtime/` 目录**（loop SKILL.md:343）——**弱资产**：是约定落点，不是能力；
   空目录 + 无 schema ≠ runtime eval 就绪。
2. **thresholds 三表列名正确**且本项目实例已被真实 runtime eval 声明填满——成立，保留。
3. **reference-roots 两文件模式**——**纪律可借、机制不可照搬**（T-074 降级）：
   `expect_present` 是磁盘路径 sentinel，服务端点没有同构物；"available" 从
   samefile/stat 变成活探针（超时、鉴权、非幂等副作用），失败模式完全不同。可复用的
   是声明/本机绑定分离、versioned 零绝对路径、fail-closed、coverage 可见、不泄本机
   路径这些**纪律**，不是代码搬迁。
4. **B2a Review wiring**——**只证明了入账，没证明硬门**（T-074 降级）：B2a 明确不读
   Review 内容、不做一致性否决（loop SKILL.md:466 划界），且 B2b 至今 pilot-gated。
   接线形状（字段+解析+coverage）可借鉴；**硬门一致性否决是未验证的新工作**。
   分步风险见附录 A 的 D0/D1/D2。
5. **runtime-recoverable 自动恢复轮**——存在但**只读**（只允许调查/证据刷新/清理计划
   起草），runtime eval 常需测试写，对 e2e 自主化帮助窄。是恢复路径资产，不是 eval
   执行路径。
6. **control-contract auto-continue 区块 + push 例外条款**——词汇骨架与手写先例在；
   机器不解析 auto-continue 条件、不执行预授权分支。**是先例，不是可复用实现**。
7. **channel-params + secrets skill**——**半资产**：参数名引用纪律在，写端机械守门
   不在；事故正是在该纪律存在之后发生的。
8. **"Round acceptance never delegate"**（loop SKILL.md:419）——矩阵行成立、与硬门
   兼容；但同表 Acceptance testing = Should delegate、Evidence collection 可委派——
   裁决权清晰**不等于**"谁跑 eval"已清晰（见附录 A O-1）。

## 4. 依赖关系与候选 evolution issues（待用户裁决，未立项）

```
GAP-7 命名   ──（先行，零依赖，动手前处置）
GAP-1 系统声明层 ──┐
GAP-2 eval schema ─┼──→ O-1 eval 执行者契约 ──→ GAP-3 机械门接线（核心）
GAP-5 预授权词汇 ──┘      （5 与 1 联动；O-1 与 O-3 耦合：委派执行须携带预授权范围）
GAP-4 停止落痕   ──（独立；与 O-2 round_cost/预算、O-4 handoff 门闩、O-8 strict 档耦合）
GAP-6 secret 守门 ──（独立，可并行；但应先于大规模自主 e2e）
```

> **T-074 补边**（原图漏掉的依赖）：①GAP-3 依赖 **O-1（eval 执行者契约）**——硬门只能
> 核对产物，产物由谁在什么权限边界产生若未定义，EV-D 只是把临场结果多写一个 JSON；
> ②GAP-1 的新声明文件必须回答与 check_setup 五文件门的关系（O-5）；③GAP-4 的预算
> 词汇必须接 round_cost 的既有结算链（O-2），且须处理 strict 档明文禁止连续无人轮
> 的冲突（O-8）。

| 候选 | 对应 | 一句话 |
|---|---|---|
| EV-A | GAP-7 | evals 术语撞名处置（先行小项） |
| EV-B | GAP-1 | 外部系统两文件声明 + 探活 + coverage（仿 reference-roots） |
| EV-C | GAP-2 | threshold 行 ID 化 + 每轮机器可读 eval 结果文件 |
| EV-D | GAP-3 | decision.md `Evals:` 字段 + 机械门核对（B2a 同形，分步：先入账后硬门） |
| EV-E | GAP-5 | 测试资源写预授权的结构化落点 + 修 continue :36/:46 矛盾 |
| EV-F | GAP-4 | 停止落痕 + round 预算词汇 + continue 措辞收窄为重入门 |
| EV-G | GAP-6 | evidence secret 守门插件化（或最低限度 setup 显式 warning） |
| **EV-H** | **O-1/O-3** | **eval 执行者契约**：threshold 的 Command 由谁（主会话/只读子代理/预授权子代理）在什么 cwd/凭证边界执行、stdout 落哪、失败如何变成 ran=fail；委派时 handoff 须携带预授权范围（T-074 判其与 GAP-2/3 同级） |
| EV-I | O-9 | scope-lock "Verification commands" 与 thresholds 的双登记合一：单一"本轮到期集合"来源 |
| EV-J | O-5 | 新声明文件与 setup 门的关系显式化（gate_blocking 与否、wizard 是否加步、缺失语义） |

## 附录 A（2026-07-28）：T-074 对抗核实的吸收记录

T-074（grok，判 PASS_WITH_NOTE）对本报告做了证据核实、资产反向核实、遗漏挖掘与
依赖图复核。verdict：7 GAP 与总判成立、两处翻转初判实质正确；不给 PASS 的原因是
本报告的事实错误（已就地修正，见页首修订说明）、资产偏乐观（§3 已降级重写）、
分步建议在硬门裁决下不安全（见 A.2）、以及完备性缺口（A.1）。

### A.1 十条审核遗漏（O-1..O-10）及处置

| # | 遗漏 | 处置 |
|---|---|---|
| **O-1** | **eval 执行者未建模**（最严重）：协议只有委派矩阵的粗粒度行，没有"threshold X 的 Command 由谁在什么权限边界执行、失败如何变成 ran=fail"。硬门只能读产物；执行拓扑缺失时 EV-D 会空转——假绿从"没字段"变成"字段写 none / 伪造 pass" | **升为一等卡点**，立 EV-H，插进依赖图（GAP-3 的前置） |
| O-2 | round_cost 与多轮自续的交互：每轮强制结算但无"预算触顶→合法 checkpoint 停"机械链；跨子代理执行时 cost 常 unavailable，账本失真反而削弱"用预算约束自续"的前提 | 并入 EV-F 规格范围 |
| O-3 | 委派矩阵无 "runtime-eval 执行"专用行；委派执行时 handoff 无预授权字段的机械要求 | 并入 EV-H/EV-E |
| O-4 | auto-continue 的散文条件含 "Open handoffs 无阻塞"，自主多轮下 handoff 未关会导致合法停或静默违例，皆无痕 | 并入 EV-F（stop-record 的枚举须含此项） |
| O-5 | check_setup 五文件门与新增声明文件的关系未回答（reference-roots 已是"游离于 setup 完备性"的先例，运维上"setup complete 但系统未声明"体验割裂） | 立 EV-J |
| O-6 | intake 路径（第二条进 loop 的口子）对"带着已跑 e2e 证据接管"无 eval 导入/新鲜度定义，假绿可从 intake 绕入 | **defer**：单会话主线闭环后再处理，记录在案 |
| O-7 | channels/connectivity 已有模型侧 inventory/探活约定——桥不是"无"而是"有约定无 schema 无接线"；EV-B 须决定强化这两 skill 还是另起 JSON，避免三套登记 | 并入 EV-B 设计输入 |
| O-8 | **strict 档明文禁止连续无人轮**（profiles:9、:60）——恰是外部系统/敏感数据场景该选的档位，与"单会话多轮自续"正面冲突 | 并入 EV-F：自续词汇必须按档位分层（lite/standard 可自续、strict 保持人闸），不得越过 profile 体系 |
| O-9 | scope-lock "Verification commands" 与 thresholds 双登记、无 ID 对齐、无哪份为准 | 立 EV-I（EV-C 的姊妹项） |
| O-10 | 硬门 = **核对 eval 结果账本**，不是 verify_protocol 内嵌 test runner（它从不执行业务命令，这是设计边界不是缺陷） | 写进 EV-D 规格的显式边界声明 |

### A.2 分步建议修订：撤回"纯 B2a 式先入账"

原文 GAP-3 建议"可按 B2a 先例分步：先入账（字段+存在性）再硬门"。T-074 指出该类比
在硬门裁决下不安全：**B2a 能先入账，是因为评审实践已大量存在，入账消灭的是"有评审
无账"；而 runtime eval 的实践是"thresholds 有行、常不跑"——入账若允许 `none — <理由>`
自由逃逸，等于给"声明了没跑"开一个协议背书的正规出口，比现状更糟。**

修订为三段（采 T-074 的对抗建议，细节留给 EV-D 规格）：

- **D0**：命名（EV-A）+ 结果文件 schema（EV-C 子集），无 gate。
- **D1（最小 teeth——从第一天就带硬门的一半）**：`Evals:` 必填；若 goal thresholds
  存在到期行，`none` 只允许 `none — deferred:<threshold-id 列表>` 且列表机器可解析；
  结果文件 containment + schema 校验；**缺 ran 记录 → 不得 positive**。
- **D2**：pass/fail 与 Feedback 一致性否决；thresholds 内容摘要进 coverage（防同轮改判据）。

### A.3 T-074 留给用户的开放问题（原样转记，立项时须裁决）

1. EV-D 的最小可接受 teeth 是"到期 threshold 必须 ran"（D1）还是必须到 D2 一致性
   才算满足硬门裁决？
2. 外部系统声明落 data-sources 的结构化扩展，还是独立 JSON（仿 reference-roots）？
   是否进 gate_blocking？
3. runtime eval 的默认执行者：主会话 / 只读子代理+主会话写 / 预授权子代理写？
4. 本项目 control-contract 实质档位与自续主线的匹配：若实际接近 strict，自续是否应
   降格为"checkpoint 密、人确认密"？

## 5. 边界外（按裁决不入主线，记录在案）

- **跨会话自动重入**（调度器/cron/hook）：单会话自续闭环后才有意义；且其中一半属
  宿主环境能力而非 harnessloop。附带观察：GAP-4 的 stop-record 恰好是跨会话重入的
  天然输入（重入 = 读上一次停止原因），先做 GAP-4 不会白费。
- **生产系统写预授权**：裁决明确排除，三档 profile 的无条件停人在该域保持不动。
- **hopper 侧 vendor 日志写端脱敏**（事故档案 §7 建议 1 的另一半）：属 hopper-plugin
  改造面，不在本审核对象内，已在事故档案挂账。

## 6. 方法与状态

- 审核方式：主会话源码级审读（v0.26.0 `b389eac`），全部证据 file:line 可复核；
  实践语料为本项目 20 轮 round 文档与 goal 002 thresholds 实例。
- 独立复核：本报告将按项目既定纪律派一轮异构对抗审（核实证据真实性、结论是否跟随、
  以及**审核遗漏**——还有哪些会卡 R1-R5 的点没被列出），结果另附。
- 本报告只是卡点清单；任何 EV 立项、优先级、以及是否走"规格 → 对抗审 → teeth"的
  完整回路，待用户裁决。

## 附录 B：执行授权记录（2026-07-28）

**用户原话**："最后你来裁决 并推动执行，我去休息了。"

**授权范围**（主会话解读，从窄）：
- T-075 回来后的**终版合成与三争议点/O 清单/A.3 四问的裁决**由主会话做出，不再
  AskUserQuestion；裁决须书面落档并标注 `main-session ruling under user delegation
  2026-07-28`，与 user-confirmed 区分。
- **EV 立项、优先级排序、按既定回路执行**（规格 → 异构对抗审 → 实现 → teeth →
  破坏性反证 → 版本 bump → push）。四仓 push 走既有批次授权（control-contract:22）。

**不在授权内（继续停人）**：生产系统写；hopper-plugin 侧超出观察记录的改造；
GitGuardian 控制台操作；任何触及用户全局环境（18789 网关等）的动作；以及裁决中
发现"两个方向都合理且不可逆"的分叉——此类留 AskUserQuestion 待用户回来。
