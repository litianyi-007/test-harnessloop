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
> **审核对象**：harnessloop **v0.26.0**（`b389eac`）源码 + 本项目 20 轮实践语料
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
| 单会话多轮自续 | Loop Continuation step 6 + "**Stop only when**" 五条穷举清单（loop SKILL.md:552-567） | 停止**不落任何痕**（见 GAP-4） |
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
- 全插件树 grep：读 `data-sources.md` 的只有 `check_setup.py`（填充度检查）与
  `init_project.py`（初始化落模板）；`verify_protocol.py` 仅在 docstring 里把它当
  PATHISH 前缀示例（:48、:2787）。**没有任何代码解析表格内容。**
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
- `verify_protocol.py`：全文 grep "eval" 仅 3 处无关命中（PATHISH 前缀、注释用词）。
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
- loop SKILL.md:552-567：step 6 "If feedback is positive and the goal is not achieved,
  **continue to the next subgoal or task**"；"**Stop only when**" 五条穷举（goal 达成/
  缺人输入/缺访问事实/写安全缺失/数据契约或阈值不可评估）。**"等用户敲 continue"
  不在清单里。**
- 实践语料：goal 002 全部 10 轮（+goal 001 的 4 轮）每轮收盘即停，`state/current.md`
  的 "Next proposed action" 一律以"下一 continue 开 SG-X"收尾——20/20 轮由人工推进。
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

**定性**：插件能力缺失（安全）。
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

## 3. 已具备的资产（诚实记账——这些不是卡点）

1. **`evidence/runtime/` 目录**已在轮结构（loop SKILL.md:343）——runtime 证据有指定落点。
2. **thresholds 三表列名正确**（差的是 schema 与解析，不是概念）。
3. **reference-roots 两文件模式**（v0.21-v0.25，三轮对抗审收敛）——GAP-1 的域内同形
   先例：声明/绑定分离、探活 sentinel、fail-closed、coverage 可见、不泄本机路径。
4. **B2a Review 字段 wiring**（v0.17.0）——GAP-3 的接线先例，且证明了"先入账后硬门"
   的分步路径可行。
5. **runtime-recoverable 自动恢复轮**（continue SKILL.md:35、loop SKILL.md:184）——
   自主性保留路径已存在：可恢复阻塞不停人，自动开只读调查轮。
6. **control-contract 的 auto-continue 区块** + 本项目 push 例外条款实例——预授权
   模式的词汇骨架与实践先例都在。
7. **channel-params + secrets skill**：凭证按参数名引用的纪律已存在且经受过事故检验。
8. **委派矩阵 "Round acceptance never delegate"**（loop SKILL.md:419）——与硬门 evals
   兼容：机械门提供事实，裁决权仍在主会话，无授权冲突。

## 4. 依赖关系与候选 evolution issues（待用户裁决，未立项）

```
GAP-7 命名   ──（先行，零依赖，动手前处置）
GAP-1 系统声明层 ──┐
GAP-2 eval schema ─┼──→ GAP-3 机械门接线（核心；依赖 1/2 的载体）
GAP-5 预授权词汇 ──┘      （5 与 1 联动：只有已声明系统可被预授权）
GAP-4 停止落痕   ──（独立，可并行）
GAP-6 secret 守门 ──（独立，可并行；但应先于大规模自主 e2e）
```

| 候选 | 对应 | 一句话 |
|---|---|---|
| EV-A | GAP-7 | evals 术语撞名处置（先行小项） |
| EV-B | GAP-1 | 外部系统两文件声明 + 探活 + coverage（仿 reference-roots） |
| EV-C | GAP-2 | threshold 行 ID 化 + 每轮机器可读 eval 结果文件 |
| EV-D | GAP-3 | decision.md `Evals:` 字段 + 机械门核对（B2a 同形，分步：先入账后硬门） |
| EV-E | GAP-5 | 测试资源写预授权的结构化落点 + 修 continue :36/:46 矛盾 |
| EV-F | GAP-4 | 停止落痕 + round 预算词汇 + continue 措辞收窄为重入门 |
| EV-G | GAP-6 | evidence secret 守门插件化（或最低限度 setup 显式 warning） |

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
