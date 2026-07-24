# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0006（SG-8.7 金标 parity runner 补齐——横切，continue 驱动 + 关键节点独立审查，延续 rounds/0005 机制）
- Scope-lock: rounds/0006/scope-lock.md（v1）
- Started: 2026-07-24
- Completed: 2026-07-25

## What Changed

本轮交付 **SG-8.7（金标 parity runner 补齐）主体达成**：把此前只有 TS 金标 runner、Swift/C# 不存在、`app/parity/` 空目录的状态，正式化为**三端（TS/Swift/C#）金标 parity runner 基建**，fixture 从 2 个扩到三组全集 13 个，三端在同一批 fixture 上逐字段一致。全程由 `$harnessloop-continue` 逐阶段驱动，写码派主会话 claude-sonnet-5 子代理、主会话只读审+验收，关键节点（★审查闸）hopper 派 codex/grok 随机池对抗审——是本项目第二次完整走完这套机制，本轮进一步验证了其在"绿灯是否等于真 parity"这类容易被表面正确性蒙混的场景下的纠错力度。

**流水线（Stage A → ★审查闸1（2 轮 rework） → 副产 SG-5 stop() 修复 → Stage B → ★审查闸2（1 轮 rework） → Stage C defer）**：

- **Stage A**（Swift runner + fixture 三组扩全）：初版驱动 SG-5 真实 client（非 mock）+ fixture 2→12 + `advance_clock` 真实推进虚拟时钟触发 `timed_out`。主会话独立复验 11 PASS/1 DEGRADED，**但当时漏了跨端验证**（只验了 Swift 单端）。
  - **codex T-048** 判 **REWORK**：确认真驱动 client/真时钟/覆盖缺口真被 SG-5 桩卡住属实（二次独立确认），但揪出 7 条 fixture 塞了臆造的 `_openclaw*` 私有字段（违反 D2 全封闭判别联合约束）——Swift 端自己跑绿，但**TS 金标 runner 对同一批 fixture 仅 2/12 PASS**（主会话独立复现 2/10 FAIL），根因是"Swift 实现和它自己的 fixture 是照着彼此写的"，跨端 parity 从根上没有成立。
  - **rework1（`1c320553`）**：删除全部臆造字段（审批 join-order 逻辑移到 DSL 层 `driverHint`）、修正非法 D2 形状、把 `ts-runner` 的 mock 从覆盖 2 个 spec 方法扩到 13 个、`expect_outbound` 断言从字段抽样改为全 pattern 匹配、`advance_clock` 从脆弱 sleep 改为轮询、修复 soft-steer fixture 缺 `createSession` 前置调用、Swift 端 `NSLock`→`actor` 消除并发风险。TS 侧恢复 13/13。
  - **codex T-050** 确认性再审判 **MUST-FIX**——这次揪出的是更隐蔽的"绿灯≠真 parity"表面绕过（5 处）：①`expect_outbound` 仍在匹配 runner 自己构造的 request 而非真捕获的 native params；②TS force-deny 断言只是回显 `expected` 值的空转 oracle，并非独立执行 D1 §6.2 spec 算出来的；③gold fixture 从不断言 RPC 调用顺序，防不住"顺序错但字段对"的回归；④1 条 fixture 的 `failure.code` 写了非法枚举值 `"unknown"`；⑤`expandEventShorthand` 遗漏必填的 `seq` 字段展开。
  - **rework2（`98d38e0e`，治根 + 每处逐一"有牙齿"自验）**：真实捕获 native params 并做规范化 key 反查匹配（`sessionId`/`message`→`text` 映射）；TS force-deny 改为真正执行 D1 §6.2 spec 独立算出 `forceResolvedApprovals` 后再比对（而非回显期望值）；新增 `nativeCallOrder` 记录真实调用时刻并在 fixture 里断言顺序；`failure.code` 改为合法枚举 `malformed_message`（Ajv 34/34 通过）；补齐遗漏的 `seq`。**每一处收残都做了临时破坏性反证**（改反顺序断言、去掉字段、破坏匹配逻辑）确认目标 fixture 真的会 FAIL、还原后确认 diff 干净——主会话亲手做了其中一次 teeth（改反顺序断言→确认 FAIL→还原）。
  - **grok T-051**（换异构视角）判 **CONFIRMABLE**：用证伪法逐条确认五处真闭合、都"有牙齿"（非表面绕过）、无新的表面绕过引入，`includeApprovals` 未做跨端断言属诚实 defer（非遗漏型假闭合）。**Stage A 终收**——两轮 rework、三次异构审查（T-048 REWORK→T-050 MUST-FIX→T-051 CONFIRMABLE）才真正收敛。

- **副产（下游揭上游，第 6+ 例）**：形式化 parity 给 `FORCE_DENIED_ON_STOP` 写 fixture 时，揪出 **SG-5 `stop()` 一个真实的 D1 §6.2 force-deny 缺口**——`stop()` abort 前未先 force-deny 待决审批（未执行 M3 定序：①先推进 `FORCE_DENIED_ON_STOP`+deny+确认生效→②才 abort），且 Swift/C# 两端 `EventMapping` 均硬编 `forceResolvedApprovals: nil`，`stop()` 被标记"完整"却无 TODO 声明缺口——**此前 rounds/0005 三轮对抗审（T-044/T-045/T-047）全部漏掉这一缺口**，因为它们审的是"stop 做了什么"而非"D1 要求 stop 做什么"。主会话独立核实 D1 spec line 515 M3 定序描述确认此缺口属实，**用户 2026-07-24 通过 AskUserQuestion 现场确认扩围**，定向修复该项：
  - **`ed90f138`**：新增 `forceDenyPendingApprovalsBeforeStop`（复用 openclaw 既有 `approval.resolve` RPC，`status==denied` 才确认生效否则 throw）先于 `sessions.abort` 执行，并正确填充 `forceResolvedApprovals`。**grok T-049** 判 **PASS_WITH_NOTE**：定序确认为真、确认屏障非伪造（`status!=denied` 会 throw 而非静默通过）、未引入 rounds/0005 NOTE-1 挂起回归；残留 **NOTE-A**（force-deny await 窗口期间新到达的审批可逃逸本轮强制终态化）。
  - **NOTE-A 收残**：drain-loop 加固为有界形式（`stopInProgress` 标志阻断新 run 进入、轮次上限 50，超限如实 throw 而非静默吞掉）。Swift/C# 两端测试 28→30，late-arrival 场景修复前 fail、修复后 pass（回归护栏）。Swift 30/30 + C# 30/30。

- **Stage B**（C# runner + 三端跨端 parity）——★审查闸2 经 1 轮 rework + 2 次审查收敛：
  - **初版（`505202a5`）**：`csharp-runner` 镜像 Stage A 已 validated 的 `swift-runner` 全套纪律（真实驱动 C# client、真捕获 native params、`nativeCallOrder` 断言、轮询式结算、诚实 DEGRADED 标注、`PartialMatch` 与 Swift/TS 对称统一值域），3 处临时破坏性反证确认非空转。三端矩阵：TS 13/13 + Swift 12/13 + C# 12/13（同一 `expected`，DEGRADED 同因于 `interrupt()` 仍是 SG-5 桩）。主会话独立复跑三端并亲手验证 C# 端 teeth。
  - **codex T-052** 判 **REWORK**（四项过、1 处阻断）：`NormalizeNativeParams` 存在条件 remap 假绿旁路——当真实 client 发送的字段名恰好错拼成 `text`（而非规范的 `message`）时，规范化逻辑会原样放行该 payload，让 fixture 断言自证 PASS 而实际未捕获到真实错误（codex 实证复现）；**Swift 权威端同病**（T-051 的证伪只覆盖了字段"错值"未覆盖字段"错名"，异构对抗审每轮补上一轮的盲区，本轮由 codex 补上 T-051 遗漏的这一类）。
  - **收残（`2a60b010`）**：两端改为 strict 剥键——无条件剥离 `message`/`text` 两个候选键后，再按真实捕获到的 `message` 值重新写回，杜绝"字段名对不上也能蒙混过关"的通路。两端 + 主会话亲手做 teeth（故意发错字段名→确认实际取值变 nil→FAIL）。三端矩阵恢复。
  - **codex T-053** 确认性再审判 **CONFIRMABLE**：用 codex 自己 T-052 的原始复现步骤在两端验证——修复前 PASS（旁路存在）→ 修复后确定性 FAIL（旁路已堵死），diff 到 blob hash 级别还原确认，三端矩阵保持不变，未引入新缺陷。**★审查闸2 通过。**

- **Stage C（D4 §4.6 产品行为 parity 首批）**：**明确 defer**（主会话按 scope-lock 授权的诚实 defer 边界判断，2026-07-25）。Stage A/B（三端 runner 基建 + 三组 FSM 全集 fixture + 跨端逐字段 parity）已达成 scope-lock 判定的 SG-8.7 主体 pass 条件；Stage C 需要先读 D5 产品规格多页并对 D4 §4.6 三分类（fixture 化/手工 checklist/OPEN-deferred）逐一落地，是独立工作包，本轮已经历 3 次收残、5 次异构审查，成本已超单轮承载范围，诚实结转后续轮，不硬塞进本轮。

**收敛守卫**：Stage A 经历 2 个 MUST-FIX（T-048、T-050）、Stage B 经历 1 个 MUST-FIX（T-052），均未达到"同一阶段第 3 轮 MUST-FIX 即停下 checkpoint"的阈值，收敛守卫本轮**未被触发**。

**hopper vendor 观察点（本轮新增正面数据点）**：codex T-048/T-050/T-052/T-053 跑 Swift/node/dotnet 的 build+run 评审均**未触发**安全过滤器中止（对照 rounds/0005 T-046 跑 C# `csi` 命令被自身 cybersecurity 过滤器拦截中止的先例）；T-052/T-053 沿用"评审时禁跑 `csi`"这一工具约束，有效避免了同类中止。

**最终产物态**：`app/contracts/d2/fixtures/`——`dsl.ts`（含 `driverHint`/`nativeCallOrder` 扩展）+ 13 条 fixture（`approval/` 3 条、`basic/` 1 条、`operation-outcome/` 6 条、`session-lock/` 3 条，全部为合法 D2 canonical 形状，Ajv 2020 严格校验 34/34 通过）+ `ts-runner/`（spec oracle 驱动的假内核）+ `swift-runner/` + `csharp-runner/`（均驱动 SG-5 交付的真实 client，非探针）+ 两处 `OPEN.md`（诚实标注 `respondApproval`/`interrupt`/`capabilities` 仍是桩、被卡住无法驱动的 fixture 状态）+ `README.md`（三端 parity 矩阵、fixture 覆盖清单、rework 记录、teeth 反证记录）。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E17 | `app/contracts/d2/fixtures/`（`dsl.ts` + 13 fixtures + `ts-runner/`/`swift-runner/`/`csharp-runner/` + `README.md` + 2 处 `OPEN.md`）；关键 commits `1c320553`/`98d38e0e`（Stage A）、`ed90f138`（SG-5 stop 副产修复）、`505202a5`/`2a60b010`（Stage B）、`0a6b06df`（state） | static+runtime | 三端 parity 矩阵 TS 13/13 + Swift 12/13 + C# 12/13（同一 `expected`，1 条 DEGRADED 同因于 `interrupt()` SG-5 桩，非三端不一致）+ Ajv 34/34 + 5 次异构对抗审（T-048 codex REWORK→T-050 codex MUST-FIX→T-051 grok CONFIRMABLE；T-052 codex REWORK→T-053 codex CONFIRMABLE）+ 多轮"有牙齿"破坏性反证（含主会话亲手验证）+ SG-5 stop() D1 §6.2 缺口修复链（`ed90f138`，T-049 grok PASS_WITH_NOTE + NOTE-A drain-loop 加固，Swift/C# 26→30 测试）；已登记 `state/evidence-index.md` E17 |

## Handoffs Closed

- hopper 派发 6 次，均已闭合（`.hopper/queue.md` 对应行 status=done）：
  - **T-048**（codex，code-review-adversarial）：Stage A 初版对抗审，Verdict REWORK（7 条 fixture 塞臆造 `_openclaw*` 字段致 TS 金标 2/12 PASS）→ 已收残 `1c320553`。
  - **T-049**（grok，code-review-adversarial）：SG-5 `stop()` D1 §6.2 force-deny 缺口修复对抗审，Verdict PASS_WITH_NOTE（残留 NOTE-A）→ NOTE-A 已收残（drain-loop 有界加固）。
  - **T-050**（codex，code-review-acceptance）：Stage A rework1（`1c320553`）确认性再审，Verdict MUST-FIX（5 处"绿灯≠真 parity"表面绕过）→ 已收残 `98d38e0e`。
  - **T-051**（grok，code-review-acceptance）：Stage A rework2（`98d38e0e`）确认性再审（换异构视角），Verdict CONFIRMABLE——**Stage A 终收**。
  - **T-052**（codex，code-review-adversarial）：★审查闸2 Stage B 初版（`505202a5`）对抗审，Verdict REWORK（`NormalizeNativeParams` 条件 remap 假绿旁路，两端同病）→ 已收残 `2a60b010`。
  - **T-053**（codex，code-review-acceptance）：Stage B 收残（`2a60b010`）确认性再审，Verdict CONFIRMABLE（用 T-052 原始复现两端验证修复前后 PASS/FAIL 翻转）——**★审查闸2 通过，SG-8.7 主体达成**。
- 每次 codex 评审完成后均按 CLAUDE.md「codex 评审三项强制核对」核对：(a) 实际审查对象与 brief 指定目标一致（T-048 对 Stage A 初版、T-050 对 `1c320553`、T-052 对 `505202a5`、T-053 对 `2a60b010`）；(b) 产物落在 brief 指定路径（`.hopper/handoffs/T-0xx-output.md`）；(c) 未仅凭 exit code 或 codex 自述采信——本轮 codex 全部正常产出 verdict，未复现 rounds/0005 T-046 的安全过滤器中止情况（已记为 hopper 正面观察点）。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-8.7 主体达成（Stage A + Stage B 完整交付并通过两个 ★审查闸），Stage C 诚实结转，证据充分且收敛：

- **★审查闸1（Stage A）**：经**2 轮 rework + 3 次异构审查**才真正收敛，是本项目迄今收残轮次最多的一次——T-048（codex）判 REWORK 揪出臆造字段致跨端假绿；rework1 后 T-050（codex，确认性再审）判 MUST-FIX，未被表面"字段已删净"糊弄过去，反而揪出 5 处更隐蔽的"绿灯≠真 parity"表面绕过（自构 request 而非真捕获、空转 oracle、不断言顺序、非法枚举、漏字段）；rework2 治根 + 每处逐一有牙齿自验后，T-051（grok，换异构视角）用证伪法逐条确认真闭合，判 CONFIRMABLE。**"绿灯≠真 parity"这一核心叙事在本轮被三轮审查层层挤干**——第一轮揪出臆造数据，第二轮揪出更深层的断言空转与顺序盲区，第三轮独立证伪确认真正闭合。
- **副产（SG-5 stop() D1 §6.2 缺口）**：形式化 parity 的下游工作揭出了上游 rounds/0005 三轮对抗审全部漏掉的真实缺口——这是本项目"下游实现连环证伪上游设计/审查"模式的第 6+ 例（此前已有 D4 codegen 证伪、D1 hermes-steer 证伪等先例）。用户现场确认后定向修复，grok T-049 判 PASS_WITH_NOTE，残留 NOTE-A 已收残，两端测试 26→30。
- **★审查闸2（Stage B）**：经 1 轮 rework + 2 次审查收敛——T-052（codex）判 REWORK，精确定位 `NormalizeNativeParams` 条件 remap 假绿旁路，并指出**这一缺陷在 Swift 权威端同样存在**（T-051 的证伪范围未覆盖"错字段名"这一类，是异构对抗审"每轮补上一轮盲区"机制的又一次实证）；收残后 T-053（codex，确认性再审）用自己 T-052 的原始复现步骤在两端做修复前后 PASS/FAIL 翻转验证，判 CONFIRMABLE。
- **Stage C** 按 scope-lock 授权的诚实 defer 边界判断结转，未硬塞进本轮，亦未把结转表述为"已完成"或"已充分覆盖"。
- **收敛守卫**（同一阶段第 3 轮 MUST-FIX 即停下 checkpoint）设置但全程**未被触发**——Stage A 2 个 MUST-FIX、Stage B 1 个，均未达 3 阈值。
- **hopper vendor 观察点**：本轮新增正面数据点——codex 跑 Swift/node/dotnet 相关评审均未触发安全过滤器中止（对比 rounds/0005 T-046 先例），"禁跑 `csi`"工具约束延续有效。
- 诚实 defer 项（Stage C 产品行为 parity、`interrupt`/`respondApproval`/`capabilities` 仍是桩、`includeApprovals` 未跨端断言）均已如实标注，未顺带声称已完成。

无 negative / 未决评审悬置，故本轮 feedback 分类 **positive**。

## Cost

Paste the output of `<skill-dir>/scripts/round_cost.py` here (claude-code
environments only; other environments record cost as `unavailable: no local
transcript source`). Do not read transcript files into the session; only the
script's summary enters context.

- Transcript window: unavailable — 本轮回写子代理无独立执行 transcript 窗口访问权限
- Input tokens: unavailable
- Cache write tokens: unavailable
- Cache read tokens: unavailable
- Output tokens: unavailable
- Protocol-attributed (heuristic): unavailable
- Estimated cost: unavailable（执行子代理的实际编码/审查驱动成本已在其原执行会话消耗，未在本次状态回写中单独记账）

## Decision

见 rounds/0006/decision.md：feedback = **positive**；裁决 = **SG-8.7 主体 done（三端金标 parity runner 基建 + 三组 FSM 全集 fixture + 跨端逐字段 parity，经两个 ★审查闸、共 5 次异构审查、2 轮+1 轮 rework 收敛）**；副产 **SG-5 `stop()` D1 §6.2 force-deny 缺口已定向修复**（`ed90f138`，含 NOTE-A 加固）；**Stage C（D4 §4.6 产品行为 parity 首批）诚实结转后续轮**；收敛守卫全程未触发第 3 轮 MUST-FIX；下一步待选 **SG-3**（codegen CI 冒烟挂接）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针）/ **Stage C 结转项** / 副发现处理。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待选 **SG-3**（codegen 增量：CI 冒烟挂接 + type-level 断言）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针待重启隔离内核后执行）/ **Stage C**（D4 §4.6 产品行为 parity 首批，本轮结转的独立工作包）/ 副发现（`app/server` body-parser limit 调大、`OPENCLAW-ISOLATED-RUN-RECIPE.md` 补 `OPENCLAW_WORKSPACE_DIR`、SG-5 kernel-client 内既有 async-await 无害警告待清）
- User input required: 否（SG-8.7 主体已完整交付，闭合不需用户进一步确认）

## Open Risks

- **Stage C（D4 §4.6 产品行为 parity 首批）未做，明确结转**——三端 runner 基建目前只覆盖 D1/D2 kernel-client 层的 13 条 fixture，D5 产品逻辑层（草稿态 Chat 生命周期/archive 正交语义/能力 toggle 两层模型等）尚无自动一致性验证，按 D4 §4.6 三分类落地留待后续轮。
- **`interrupt()`/`respondApproval()`/`capabilities()` 仍是桩**——两端一致，`soft-steer-then-stop.json` fixture 因此在 Swift/C# 两端均诚实 DEGRADED（非三端不一致，是两个 native 端遇到同一已知产品缺口），如实记录，非本轮 scope。
- **`includeApprovals` 等 openclaw 原生特有字段未做跨端断言**——C# 真实 `Subscribe()` 确实会发送该字段，但 fixture 的 `expect_outbound` 从未在 `req.subscribe` payload 里断言它，Stage A/B 均判定"保持不断言更诚实"（强行断言会打穿 TS 假内核与两个 native 端的语义差），非遗漏型假闭合，但仍是一处诚实的覆盖边界。
- **`csharp-runner/` 未纳入既有 SG-5 frame-replay 测试范围**——是本轮新写的独立可执行程序，三端 parity"跨端一致"结论仅覆盖本轮的 13 条金标 fixture，不代表覆盖 D1/D2 全部方法/事件类型。
- **SG-5 stop() D1 §6.2 缺口被此前 3 轮对抗审全部漏掉**——已记录为"下游实现连环证伪上游审查"模式的第 6+ 例，是否需要在评审 brief 里显式要求"对照契约条款逐条核验，而非只审实现做了什么"，留待框架侧后续评估，非本轮直接修改 harnessloop 协议文本。
- **两个 hopper vendor 观察点延续记录**：rounds/0005 grok 尾部 auth-fail 先例（本轮未复现）、codex 安全过滤器中止评审先例（T-046，本轮 codex 全部正常产出 verdict，新增正面数据点）。

## Next Proposed Scope

**SG-8.7 主体已达成**（Stage A + Stage B），Stage C 诚实结转独立后续轮。下一步从以下几项中择一或并行：**SG-3**（codegen 增量：CI 冒烟挂接 + type-level 断言）/ **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批，独立工作包）/ 副发现处理。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
