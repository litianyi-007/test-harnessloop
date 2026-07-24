# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0006（SG-8.7 金标 parity runner 补齐——主体达成，Stage C 结转）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-25

## Reason

SG-8.7 的验收边界由 scope-lock 明确为"三端（TS 已有/Swift/C# 新建）金标 parity runner，读同一批 fixture、驱动各自真实 client、产出同一 `ClientObservableState`，逐字段比对；fixture 从 2 扩到三组全集"，并显式声明 **Stage A/B 达成即满足 SG-8.7 主体 pass 条件**，Stage C（D4 §4.6 产品行为 parity）可诚实 defer。执行结果：

- **Stage A**（Swift runner + fixture 三组扩全）经 **2 轮 rework + 3 次异构审查**收敛：初版驱动真实 client + fixture 2→12 + `advance_clock` 真实触发 `timed_out`，但 codex T-048 判 REWORK，揪出 7 条 fixture 塞了违反 D2 封闭判别联合的臆造字段，致 TS 金标 runner 对同批 fixture 仅 2/12 PASS（"Swift 和它的 fixture 是照着彼此写的"）；rework1（`1c320553`）删净臆造字段、修非法形状、TS mock 扩至 13；codex T-050 确认性再审未被表面修复糊弄，判 MUST-FIX，揪出 5 处更隐蔽的"绿灯≠真 parity"表面绕过（自构 request 非真捕获、force-deny 空转 oracle、不断言 RPC 顺序、非法枚举、漏 `seq`）；rework2（`98d38e0e`）治根 + 每处逐一破坏性反证自验；grok T-051（换异构视角）用证伪法确认真闭合，判 CONFIRMABLE，Stage A 终收。
- **副产**：形式化 parity 揭出 SG-5 `stop()` 一个真实的 D1 §6.2 force-deny 缺口（rounds/0005 三轮对抗审全部漏掉），用户 2026-07-24 现场确认扩围，定向修复（`ed90f138`），grok T-049 判 PASS_WITH_NOTE，残留 NOTE-A 已收残（drain-loop 有界加固，Swift/C# 26→30 测试）。
- **Stage B**（C# runner + 三端跨端 parity）经 **1 轮 rework + 2 次审查**收敛：初版（`505202a5`）镜像 Stage A validated 的 swift-runner 纪律，三端矩阵 TS 13/13 + Swift 12/13 + C# 12/13；codex T-052 判 REWORK，精确定位 `NormalizeNativeParams` 条件 remap 假绿旁路（且指出 Swift 权威端同病，是 T-051 证伪范围未覆盖的盲区）；收残（`2a60b010`）两端 strict 剥键；codex T-053 用 T-052 原始复现步骤在两端做修复前后 PASS/FAIL 翻转验证，判 CONFIRMABLE，★审查闸2 通过。
- **Stage C**（D4 §4.6 产品行为 parity 首批）：按 scope-lock 授权的诚实 defer 边界判断，明确结转，未硬塞。

证据充分（三端 parity 矩阵 + Ajv 34/34 + 5 次异构对抗审 verdict + 多轮"有牙齿"破坏性反证，含主会话亲手验证）且收敛（收敛守卫全程未触发第 3 轮 MUST-FIX；Stage A 2 个 MUST-FIX、Stage B 1 个，均未达阈值；defer 项均如实标注），故本轮 feedback 分类 **positive**。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **"绿灯≠真 parity"是本轮核心叙事，被三轮审查层层挤干**：T-048 揪出的是数据层面的臆造（fixture 塞了非法私有字段让 Swift 自绿）；T-050 揪出的是断言机制层面更深的问题（表面上字段已删净、advance_clock 已修，实则 runner 的断言逻辑本身在自证——自构 request 而非真捕获、force-deny oracle 回显期望值而非独立算出、fixture 不断言调用顺序）；T-052 揪出的是同一类问题在 Stage B 的变体（`NormalizeNativeParams` 条件 remap 让错误字段名蒙混过关），且明确指出 Swift 权威端同病、是上一轮证伪范围的盲区。**三轮审查每轮都往更深一层的"表面正确性 vs 真实覆盖"挖，且每次收残都配上了破坏性反证（临时改坏→确认 fixture 真 FAIL→还原）**，这是本轮相对 rounds/0005 的机制升级——teeth 纪律从这里开始成为收残交付的标配。
- **下游揭上游模式再添一例（第 6+ 例）**：形式化 parity 想给 `FORCE_DENIED_ON_STOP` 写 fixture 时，发现 SG-5 `stop()` 从未真正执行 D1 §6.2 的 force-deny 定序——且这个缺口在 rounds/0005 三轮对抗审（T-044/T-045/T-047）中全部被漏过，因为那三轮审的是"stop 实现做了什么"，而非"逐条对照 D1 契约条款核验"。发现后未擅自扩围代码，而是停下用 AskUserQuestion 交给用户裁定，用户确认后才动手，符合 scope-lock 的 Rollback Condition 处置路径。
- **异构对抗审"每轮补上一轮盲区"机制再次实证**：T-051（grok）证伪了 T-048/T-050 揪出的全部问题，但其证伪范围只覆盖了字段"错值"这一类，未覆盖字段"错名"（`text` vs `message`）这一类；T-052（codex）恰好补上了这个盲区，且明确指出 Swift 权威端有同样的问题。这不是某个 vendor 更强，而是异构视角轮换本身在起作用——同一 vendor 连续两轮容易延续同一套盲区，换人才能补上。
- **收敛守卫（同一阶段第 3 轮 MUST-FIX 即停下 checkpoint）设置但未触发**：Stage A 经 T-048（REWORK）→ 第一次收残 → T-050（MUST-FIX）→ 第二次收残即彻底收敛（未进入第三轮）；Stage B 经 T-052（REWORK）→ 收残 → T-053（CONFIRMABLE）一次收敛。
- **Stage C 结转是诚实 defer，非回避**：scope-lock 已预先声明 Stage A/B 达成即满足 SG-8.7 主体，Stage C 是独立工作包（需读 D5 多页 + D4 §4.6 三分类判断落地），本轮已消耗 3 次收残 + 5 次异构审查的成本，继续硬塞会牺牲审查质量，故按 scope-lock 既定的诚实分层判断结转，已在 round-summary/decision 中明确标注，非本轮遗漏。
- **hopper vendor 观察点**：本轮新增正面数据点——codex 跑 Swift/node/dotnet 相关的 T-048/T-050/T-052/T-053 均正常产出 verdict，未复现 rounds/0005 T-046 的安全过滤器中止（跑 C# `csi` 被拦）；"评审时禁跑 `csi`"这一工具约束延续有效。
- **下一步待选**：**SG-3**（codegen CI 冒烟挂接 + type-level 断言）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批结转项）/ 副发现处理。

## Open Questions Resolved

- **"绿灯≠真 parity"这类表面绕过是否会被 continue 驱动 + 关键节点独立审查机制层层挤出**：本轮证实会——三轮审查（T-048/T-050/T-052）每轮都揪出上一轮未闭合或新引入的表面绕过，最终经证伪法确认的收残才真正站得住（T-051/T-053 CONFIRMABLE）。
- **异构对抗审换人是否真的能补上同一 vendor 连续审查的盲区**：本轮证实——T-052（codex）补上了 T-051（grok）证伪范围里"字段错值 vs 错名"这一类未覆盖的盲区，且发现该问题在权威 Swift 端同样存在。
- **形式化 parity 这类"补基建"性质的任务是否也会像功能实现一样揭出上游遗留缺口**：本轮证实——给 `FORCE_DENIED_ON_STOP` 写 fixture 这一看似机械的动作，揭出了 rounds/0005 三轮对抗审全部漏掉的 SG-5 `stop()` D1 §6.2 真实缺口，延续本项目"下游连环证伪上游"的既有模式（第 6+ 例）。

## Open Questions Deferred

- **Stage C（D4 §4.6 产品行为 parity 首批）**：D5 产品逻辑层的三分类落地（fixture 化/手工 checklist/OPEN-deferred）留待独立后续轮。
- **`interrupt()`/`respondApproval()`/`capabilities()` 三桩何时做实**：待后续 SG，非本轮 scope；两端一致，`soft-steer-then-stop.json` fixture 因此在 Swift/C# 均诚实 DEGRADED。
- **`includeApprovals` 等 openclaw 原生特有字段跨端断言**：Stage A/B 均判定保持不断言更诚实（强行断言会打穿 TS 假内核语义），是否需要专门为 native-only 字段设计新的断言层级，留待后续评估。
- **csharp-runner 是否应纳入既有 SG-5 frame-replay 测试范围**：目前是独立可执行程序，是否合并/如何合并留待后续。
- **是否需在评审 brief 模板中显式要求"对照契约条款逐条核验"以减少下游揭上游模式重复出现**：属框架侧观察，留待后续 self-audit 或专项评估，非本轮直接改动 harnessloop 协议文本。
- **两个 hopper vendor 观察点（grok auth-fail 先例、codex 安全过滤器中止评审先例）是否需要插件侧适配**：本轮未复现，延续记录，非本轮 scope。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E17 | `app/contracts/d2/fixtures/`（含 13 fixtures + ts/swift/csharp-runner + README）；commits `1c320553`/`98d38e0e`/`ed90f138`/`505202a5`/`2a60b010`/`0a6b06df` | SG-8.7 主体 done 的直接依据：三端 parity 矩阵逐字段一致 + Ajv 34/34 + 5 次异构对抗审（T-048/T-050/T-051/T-052/T-053）+ 多轮有牙齿反证 |
| E16 | `app/kernel-client/{swift,csharp}`（含 tests）；commits 见 rounds/0005 | SG-5 kernel-client（本轮 runner 驱动的真实 client 基座，及 `ed90f138` stop() 修复的直接承载对象），追溯依据 |

## Next Action

- Action type: 收盘 → 待选下一 SG 开新 round（或续做 Stage C 结转项）
- Scope-lock required: yes（下一 SG 或 Stage C 开 round 时新建 scope-lock）
- Human confirmation required: 否（SG-8.7 主体本身已完整交付，闭合不需用户进一步确认）
- Safe without user input: yes（本轮收盘）；下一步若改推 SG-3/SG-7/SG-8.x/Stage C，一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 从 **SG-3**（codegen 增量）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批）/ 副发现中择一或并行，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 Stage C（D4 §4.6 产品行为 parity）表述为"已完成"（明确结转，独立工作包）；不得把 `interrupt`/`respondApproval`/`capabilities` 三桩默认为"已做实"；不得把 `includeApprovals` 等 native-only 字段默认为"已跨端断言"——均明确 deferred，未裁定
