# Round Summary

## Round

- Goal: 20260718-002-agent-app
- Round: 0007（SG-3 增量收口 + CI 守门——SG-8.6 主体，continue 驱动 + 关键节点独立审查，本项目第三次完整走该机制；单阶段轮）
- Scope-lock: rounds/0007/scope-lock.md（v1）
- Started: 2026-07-25
- Completed: 2026-07-25

## What Changed

本轮交付 **SG-3 增量收口（type-level 保真断言）+ 全仓首个 CI 守门（SG-8.6 主体）**：把此前"三端 codegen 主体已随 SG-1 交付、但 `EmptyPayload`/`WireCapabilityDescriptorPayload` 精确空对象/排除字段类型在生成产物中的保真从未被断言过（grep 零命中）"与"全仓从未有任何 `.github/workflows/`"两处验收缺口，一次性补齐。单阶段轮，写码派主会话 claude-sonnet-5 子代理、主会话本地逐步复验 + push 后看真实 CI run，关键节点（★审查闸）hopper 派 codex/grok 随机池对抗审——重点证伪"**CI 绿灯是否真的会红**"。

**交付内容（commit `133b52da` 主体实现 + `04837f82` 收 T-054 NOTE 收残，均已随批次 push）**：

- **type-level 保真断言（SG-3 验收缺口，此前零命中）**：三端各自用编译负例断言精度——Swift 用 `#if` 开关切负例场景 + `swiftc -D` 编译期望**失败**；C# 同款用 `DefineConstants` 切负例场景 + 期望 `dotnet build` **失败**（`CS0117` 成员不存在错误）；TS 用 `@ts-expect-error` 断言，未真触发编译错误则该行自身在 `tsc --strict` 下报 `TS2578`（硬错，无需额外脚本判定）。三端正例 control 组均照常编译通过。**teeth**：临时改坏生成产物注入缺陷（人为让 `EmptyPayload`/`WireCapabilityDescriptorPayload` 精度失守）→ 断言必须 FAIL → 还原确认 diff 干净，四种组合（Swift/C# × EmptyPayload/排除字段）全部验证过一遍，且主会话独立复跑三端确认。
- **全仓首个 CI**：新建 `.github/workflows/ci.yml`（此前全仓无任何 CI）。**ubuntu job**（20 步）：codegen 全链（除 swiftc 相关三步）+ `git diff --exit-code -- app/generated/` 幂等守门（真抓生成产物漂移）+ redocly openapi 校验 + `setup-dotnet` 装 .NET 7 + `verify`/`typecheck` + type-fidelity C# 断言 + TS 金标 parity runner（13/13）+ C# 金标 parity runner（12/13）+ `app/server` jest（19/19）。**macos job**（6 步，`needs: ubuntu` 控成本）：仅 Swift 相关——typecheck/verify/type-fidelity + Swift 金标 parity runner（12/13）。全程无 secret、无 `continue-on-error`、无 `|| true` 之类的静默放水写法。**已审查通过的 deviation**：ubuntu 侧不是直接跑单条 `npm run gen`（该链含 swiftc 三步，ubuntu 无 Swift 工具链），而是拆逐个 script 单独跑；grok T-054 核实过 gen 链共 14 步，ubuntu+macos 两个 job 并集完整覆盖，无遗漏步骤。
- **`verify-csharp.mjs` + `typecheck-csharp.mjs` 的 `CI=true` 硬失败开关**：本地跑时 dotnet 缺失仍保持既有的软跳过（不打断本地开发），但 CI 环境下（`CI=true`）dotnet 缺失会硬失败而非静默跳过。`typecheck-csharp.mjs` 的这一开关是 T-054 NOTE 收残（`04837f82`）补的——初版 `verify-csharp.mjs` 已对称，`typecheck-csharp.mjs` 当时遗漏，收残后两脚本行为一致，含主会话对三态（dotnet 在/不在 × CI=true/未设）的亲手实测。
- **真实 CI 两次一把过绿**：push `133b52da` 后触发 run `30149090936`（ubuntu 1m24s + macos 42s，总耗时 2m12s）全绿；push `04837f82` 后触发 run `30149357788`（1m49s）全绿。两次均**首绿未经迭代**——本地先逐步模拟 CI 每一步（含用 `CI=true` 本地预跑硬失败开关）确认无误后才 push，策略在两次 push 上都直接命中。

**★审查闸（grok T-054，PASS_WITH_NOTE）**：证伪式审查主题"CI 绿灯是否真的会红"——逐项核实：幂等守门是否真有牙齿（人为在 `app/generated/` 塞一个 marker 后重跑 `git diff --exit-code`，确认 exit 1）；`verify:csharp`/`typecheck-csharp` 的 `CI=true` 硬失败是否真硬；有无 `continue-on-error`/`|| true` 之类的字样放水；三端 type-level 负例是否真的会在注入缺陷后转红（grok 亲手给 Swift 端和 C# 端的 `Capabilit...` 相关字段加回本应被排除的 `protocolVersion`，确认 verify 脚本真的 FAIL）；ubuntu 拆解 gen 链这一 deviation 是否有遗漏步骤（核实 gen 链共 14 步、ubuntu+macos 并集完整覆盖）；TS `EmptyPayload` 已知精度缺陷的 defer 处理是否诚实（未被悄悄断言掉、也未被隐瞒）。**Verdict = PASS_WITH_NOTE**：证伪全项均"有牙齿"（幂等守门真抓漂移、硬失败真硬、三端负例注缺陷后真转红、gen 链两 job 并集无漏、known-gap defer 诚实），仅 1 处 NOTE——`typecheck-csharp.mjs` 当时的 `CI=true` 硬失败开关与 `verify-csharp.mjs` 不对称（`typecheck-csharp` 在 dotnet 缺失时仍软过，同一 job 内虽有 `setup-dotnet` 且后续步骤会硬红、非放水，但不对称本身该修）——已收残（`04837f82`）。

**两个"下游揭上游"发现（defer，未擅自修改——scope-lock Rollback Condition 条款）**：

1. **TS `EmptyPayload` 精度缺陷（SG-1 codegen scope）**：生成的 `interface EmptyPayload {}` 在 TypeScript 类型系统里就是裸 `{}` 类型，会接受任意非空对象值——零属性 interface 不触发 TS 的 excess-property check（结构化类型系统的固有行为，非某处代码 bug）。经实证（含对照组）证实该缺陷成立。已保留证据代码 `codegen/verify/ts/type-fidelity-known-gap.ts`（刻意不接入 CI，避免用一个已知会失败的断言污染绿灯），CI 中只断言成立的半边——`WireCapabilityDescriptorPayload` 排除 `protocolVersion` 字段这一约束在三端全部成立。此项 defer 至 SG-1 后续收尾，不在本轮 scope 内擅自改 schema/codegen 生成器。
2. **解码边界静默忽略未知键（跨语言运行时缺口）**：Swift `JSONDecoder`/C# `System.Text.Json` 在默认配置下，解码 wire 消息时会**静默忽略**未知或本应被排除的键——实测证明：`EmptyPayload` 解码 `{"extra":1}` 两端均成功（不报错、`extra` 被静默丢弃）；`capability_changed` 事件即使 wire 上泄漏了 `protocolVersion` 字段，两端解码也照样成功、静默忽略该多余字段。这说明"编译期构造保证"（即生成的强类型无法表达该字段）在**解码边界**上并不真正成立——fixture 测试层有 Ajv 做 `additionalProperties:false` 的严格校验，但生产 client 的实际解码路径缺这一层校验，与 D2 的 additionalProperties:false 语义存在落差。这是 D1/D2 级的 strict-decode 设计决策问题（是否要求两端解码器也做严格模式），非本轮 CI/type-level 断言 scope 能处理，defer 记录，留待后续轮次或设计修订评估。

**hopper 边用边验证观察点（新）**：本轮排查中发现 `.hopper/queue.md` 里某任务 Brief 文本含 `||` 字面量，被 markdown 表格解析成了新的表格列，导致对应行的 `Vendor` 列错位、vendor binding 解析失败，报错信息为泛化的 "No vendor binding"、未提示真实原因（列错位），排查成本较高。记为 hopper 可用性改进候选，是否升级为 evolution issue 留待主会话/用户后续决定。

**CI 成本观察**：macos 步骤仅 42s（成本拆分策略——ubuntu 承载绝大多数步骤、macos 只跑 Swift 必需项——生效）；`net7.0`/Node20 actions 弃用警告为未来维护项，非阻断本轮。

**收敛守卫**：本轮 0 次 REWORK/MUST-FIX（T-054 直接判 PASS_WITH_NOTE），收敛守卫（第 3 个 MUST-FIX 即 checkpoint 用户）未被触发。

## Evidence Produced

| Evidence ID | Path | Type | Notes |
| --- | --- | --- | --- |
| E18 | `.github/workflows/ci.yml` + `app/contracts/d2/codegen/`（`verify/`、type-fidelity 断言、`scripts/`）；关键 commits `133b52da`（主体）、`04837f82`（T-054 NOTE 收残） | static+runtime | 全仓首个 CI 守门有牙齿：真实 CI run `30149090936`（2m12s，ubuntu 1m24s+macos 42s）+ `30149357788`（1m49s）双绿 + grok T-054 证伪式对抗审 PASS_WITH_NOTE + teeth 多组（含 grok 审查者亲手注缺陷转红）+ 主会话独立复验（本地逐步模拟 CI 步骤 + 三态硬失败开关实测）；已登记 `state/evidence-index.md` E18 |

## Handoffs Closed

- hopper 派发 1 次，已闭合（`.hopper/queue.md` 对应行 status=done）：
  - **T-054**（grok，code-review-adversarial）：rounds/0007 SG-3 增量+CI 守门对抗审，证伪式核验"CI 绿灯是否真的会红"，Verdict **PASS_WITH_NOTE**（幂等/硬失败/负例/gen 链覆盖/defer 诚实均有牙齿；唯一 NOTE=`typecheck-csharp.mjs` 硬失败开关不对称）→ NOTE 已收残 `04837f82`。
- 按 CLAUDE.md「codex 评审三项强制核对」（本次评审 vendor 为 grok，仍按同等纪律核对）：(a) 实际审查对象为 brief 指定的 rounds/0007 commit `133b52da` + CI run `30149090936`，一致；(b) 产物落在 `.hopper/handoffs/T-054-output.md`；(c) 未仅凭 exit code 或 vendor 自述采信——T-054 verdict 附有具体证伪操作记录（幂等 marker 注入、字段加回等），非空转自述。
- goal-breakdown.md「Discovery Handoffs」表为空，本轮无新增/闭合项。

## Review Result

**positive**——SG-3 增量缺口 + SG-8.6 CI 守门主体均已交付，证据充分且收敛：

- **type-level 保真断言**从零命中到三端全部落地，且用 teeth（临时破坏生成产物精度→确认断言真 FAIL→还原）验证过非空转，主会话独立复跑三端确认。
- **CI 守门**是全仓首个 `.github/workflows/`，两 job 共 26 步，无 secret/无放水写法，两次真实 push 均一把绿，且首绿未经迭代（本地逐步模拟 CI 策略生效）。
- **★审查闸（grok T-054）**用证伪法逐项核验"CI 绿灯是否真的会红"这一核心叙事，判 PASS_WITH_NOTE——幂等守门/硬失败开关/三端负例/gen 链覆盖/defer 诚实性全部证实有牙齿，grok 亲手做了破坏性反证（人为加回被排除字段确认 verify 脚本转红）。唯一 NOTE（`typecheck-csharp.mjs` 不对称）已当场收残，非遗留残留。
- **两个"下游揭上游"发现**（TS `EmptyPayload` 精度缺陷、解码边界静默忽略未知键）均按 scope-lock Rollback Condition 条款如实记录、未擅自扩围修复，是本项目"下游连环证伪上游"模式的延续（第 7/8 例）。
- **收敛守卫**（第 3 个 MUST-FIX 即 checkpoint）设置但全程未触发（0 次 MUST-FIX）。
- hopper `||` 表格解析观察点已如实记录为可用性改进候选，未影响本轮本身的交付。

无 negative/未决评审悬置，故本轮 feedback 分类 **positive**。

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

见 rounds/0007/decision.md：feedback = **positive**；裁决 = **SG-3 done（增量边界：type-level 保真断言三端落地 + CI codegen 冒烟挂接）+ SG-8.6 主体 done（committed GHA 双 job：codegen 幂等/openapi 校验/dotnet 硬失败/三端 parity runner+server jest 挂 CI）**；两个"下游揭上游"发现（TS `EmptyPayload` 精度缺陷、解码边界静默忽略未知键）如实 defer，未擅改；收敛守卫全程未触发；下一步待选 **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转项）/ 两个 defer 发现的修复轮 / hopper `||` 表格观察点处理。

## Blocker Classification

- Blocker type: none（本轮收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Safe next action: 待选 **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针，待重启隔离内核后执行）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转的独立工作包）/ 两个本轮新发现的 defer 项（TS `EmptyPayload` 精度缺陷修复归 SG-1；解码边界 strict-decode 设计决策归后续轮/设计修订）/ hopper `||` 表格解析观察点（是否升级为 evolution issue 待定）
- User input required: 否（SG-3 增量 + SG-8.6 主体已完整交付，闭合不需用户进一步确认）

## Open Risks

- **TS `EmptyPayload` 精度缺陷未修复，仅 defer**——生成的裸 `{}` 类型结构性地无法通过 TS 类型系统本身拒收非空对象，需要额外的 runtime 校验层或 codegen 策略调整才能真正收口，留待 SG-1 后续收尾轮。
- **解码边界静默忽略未知键——跨语言运行时缺口**——Swift/C# 两端生产解码路径均未做类似 Ajv `additionalProperties:false` 的严格校验，"编译期构造保证在 wire 解码边界成立"这一假设不成立；是否需要引入 strict-decode 是 D1/D2 级设计决策，未在本轮裁定，留待后续轮或设计修订评估。
- **`net7.0`/Node20 actions 弃用警告**——CI 当前可正常运行，但目标框架/actions 版本已进入弃用窗口，需在后续维护窗口升级（非本轮阻断项，如实记录）。
- **hopper `||` 表格解析观察点**——queue.md Brief 含 `||` 字面量会切歪 markdown 表格列，导致 vendor 绑定解析失败且报错信息不指向真实原因，排查成本较高，是否升级为 hopper 插件 evolution issue 待主会话/用户后续决定。
- **CI 覆盖边界诚实标注**——CI 目前只覆盖 D1/D2 kernel-client 层的三端金标 parity（TS 13/13、Swift 12/13、C# 12/13，1 条 DEGRADED 沿用 rounds/0006 已知的 `interrupt()` 桩缺口），不覆盖 D5 产品逻辑层（Stage C，rounds/0006 结转），非本轮新增缺口，仅重申既有边界。

## Next Proposed Scope

**SG-3 增量 + SG-8.6 CI 守门主体已达成**。下一步从以下几项中择一或并行：**SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转的独立工作包）/ 两个本轮新发现的 defer 项修复轮（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计决策）/ hopper `||` 表格观察点处理。每个 SG 继续逐个走 round → decision → feedback → state 回写闭环（本项目起 rounds/0002 兑现，不再绕开）。
