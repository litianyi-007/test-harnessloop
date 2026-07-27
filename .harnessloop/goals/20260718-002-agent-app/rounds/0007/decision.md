# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Review: .hopper/handoffs/T-054-output.md
- Reviewer: grok via hopper T-054
- Review verdict: pass-with-note
- Review digest: c04f86001285c10c6a1ee8b7d871f3cd696ac6053c7de8e4a3d0700c5b95f95d
- Active goal: 20260718-002-agent-app
- Active round: 0007（SG-3 增量收口 + CI 守门——SG-8.6 主体，均已达成）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-25

## Reason

rounds/0007 的验收边界由 scope-lock 明确为两件事：①补 SG-3 验收缺口——`EmptyPayload`/`WireCapabilityDescriptorPayload` 精确空对象/排除字段类型的 type-level 保真断言（此前 grep 零命中）；②建 committed GitHub Actions（即 SG-8.6 主体）——codegen 冒烟+幂等无 diff、openapi 校验、`verify:csharp` CI 下硬失败、三端金标 parity runner（rounds/0006 交付）挂进 CI、`app/server` 测试挂入。执行结果：

- **type-level 保真断言**：三端（Swift/C#/TS）各自用编译负例断言精度——Swift `#if`+`swiftc -D` 期望编译失败、C# `DefineConstants` 期望 build 失败（`CS0117`）、TS `@ts-expect-error` 未触发即硬错（`TS2578`）；正例 control 组均过。teeth：注入缺陷临时改坏生成产物 → 断言必须 FAIL → 还原 diff clean，四组合全验，主会话独立复跑三端确认。
- **全仓首个 CI**（`.github/workflows/ci.yml`）：ubuntu job 20 步（codegen 全链拆 script[除 swiftc 三步]+ `git diff --exit-code` 幂等守门 + redocly openapi + `setup-dotnet` 7 + verify/typecheck/type-fidelity C# + TS/C# 金标 parity runner + `app/server` jest）+ macos job 6 步（仅 Swift 必需项，`needs: ubuntu` 控成本）。无 secret/无 `continue-on-error`/无 `|| true`。**deviation（已审查通过）**：ubuntu 不跑单条 `npm run gen`（含 swiftc 三步），拆逐 script 单独跑；grok T-054 核实 gen 链 14 步、ubuntu+macos 并集完整覆盖无遗漏。
- **CI 硬失败开关**：`verify-csharp.mjs`（初版即有）+ `typecheck-csharp.mjs`（T-054 NOTE 收残 `04837f82` 补的，与前者对称化）在 `CI=true` 时 dotnet 缺失硬失败，本地保持软跳过不变，主会话对三态（dotnet 在/不在 × CI=true/未设）亲手实测。
- **真实 CI 两次一把绿**：run `30149090936`（`133b52da`，2m12s：ubuntu 1m24s+macos 42s）+ run `30149357788`（`04837f82`，1m49s），均首绿未经迭代——本地逐步模拟 CI 步骤策略生效。

**★审查闸（grok T-054，PASS_WITH_NOTE）**：证伪式核验"CI 绿灯是否真的会红"——幂等守门真抓漂移（注 marker→exit 1）、CI 硬失败真硬、无放水字样、三端负例注缺陷全转红（grok 亲手给 Swift/C# 端加回被排除的 `protocolVersion` 字段，确认 verify 脚本真 FAIL）、gen 链两 job 并集无漏、known-gap defer 诚实。唯一 NOTE = `typecheck-csharp.mjs` 不对称，已收残。

**两个"下游揭上游"发现（defer，未擅修——scope-lock Rollback Condition 条款）**：
1. **TS `EmptyPayload` 精度缺陷（SG-1 codegen scope）**：生成的裸 `interface EmptyPayload {}` 因 TS 结构化类型系统不触发 excess-property check，接受任意非空值，实证（含对照组）成立。证据代码 `codegen/verify/ts/type-fidelity-known-gap.ts` 刻意不入 CI；CI 只断言成立的半边（`WireCapabilityDescriptorPayload` 排除 `protocolVersion` 三端全成立）。defer 至 SG-1 后续收尾。
2. **解码边界静默忽略未知键（跨语言运行时缺口）**：Swift `JSONDecoder`/C# `System.Text.Json` 默认设置在 wire 解码时静默忽略未知/被排除键（实测：`EmptyPayload` 解 `{"extra":1}` 两端成功；`capability_changed` 带泄漏 `protocolVersion` 两端静默解码成功）——"编译期构造保证"在生产解码边界不成立，与 D2 `additionalProperties:false` 语义有落差（fixture 层有 Ajv 校验，生产 client 解码层无）。属 D1/D2 级 strict-decode 设计决策，defer 记录待后续轮/设计修订。

证据充分（type-level 断言 teeth 四组合 + 真实 CI run 双绿 + grok T-054 证伪式对抗审 PASS_WITH_NOTE + 两处 defer 均如实标注、未擅改）且收敛（收敛守卫全程未触发，0 次 MUST-FIX），故本轮 feedback 分类 **positive**。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **"写断言"本身就是一种审查行为**：本轮给 `EmptyPayload`/`WireCapabilityDescriptorPayload` 写 type-level 保真断言这一相对机械的动作，揪出了两处此前从未被验证过的真实缺陷——TS 结构化类型系统层面的精度缺陷、以及更深一层的跨语言运行时解码边界缺口。这与 rounds/0005/0006 反复出现的"下游实现连环证伪上游设计/审查"模式一致（第 7/8 例），进一步印证"补验收缺口"不是纯粹的机械劳动，而是持续在给已交付部分做事后审查。
- **CI 守门的核心叙事是"绿灯是否真的会红"，本轮证实会**：grok T-054 用证伪法逐项验证——不是简单看 CI 面板是否绿，而是亲手做破坏性反证（加回被排除字段、注入 marker）确认每一道守门确实会在该红的时候红。teeth 纪律（rounds/0006 起成为标配）在本轮延续到 type-level 断言与 CI 守门两处，均有具体的"改坏→FAIL→还原"记录，非空转自证。
- **首绿未经迭代的价值**：两次真实 push 均一把过绿，是本地逐步模拟 CI 每一步（含 `CI=true` 硬失败开关的三态实测）这一策略的直接产出，避免了"先 push 试错再迭代修 CI 环境差异"的常见反模式，也说明本地复验的充分性经过了两次独立验证（`133b52da`、`04837f82` 各一次）。
- **两处新发现均按 scope-lock 明确写好的 Rollback Condition 处置**：Rollback Condition 原文即预判"若 type-level 断言暴露 SG-1 生成产物真实精度缺陷——这是断言揪出上游的正常产出：停下报 blocker（属 SG-1 codegen scope，不在本轮擅修 schema/生成器），断言如实标 FAIL 或 defer，不 fudge"，本轮两处发现均严格按此执行，未借机扩围修 codegen/schema。
- **hopper `||` 表格解析观察点**：queue.md Brief 文本里的字面量 `||` 被 markdown 表格语法误解析为新增列，导致对应行 Vendor 列错位、vendor binding 解析失败，且报错信息未指向真实原因（列错位）而是泛化的"No vendor binding"，排查成本较高。已如实记录为 hopper 可用性改进候选，是否升级为正式 evolution issue 留待主会话/用户后续决定，本轮不擅自处理。
- **下一步待选**：**SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/PRE-3/PRE-7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转项）/ 两个本轮新发现的 defer 项修复轮 / hopper `||` 表格观察点处理。

## Open Questions Resolved

- **CI 绿灯是否真的会红**：本轮证实会——grok T-054 对幂等守门/CI 硬失败开关/三端 type-level 负例逐项做破坏性反证，均确认在该失败的场景下真实失败，非表面绿灯。
- **type-level 断言是否会像功能实现一样揭出上游遗留缺口**：本轮证实——给两个此前从未断言过的类型写保真断言，揪出了 TS `EmptyPayload` 精度缺陷与跨语言解码边界缺口两项真实问题，延续本项目"下游连环证伪上游"的既有模式。
- **本地逐步模拟 CI 步骤的策略是否能实现首绿不经迭代**：本轮证实——两次独立 push（`133b52da`、`04837f82`）均一把过绿，未经任何 CI 环境差异导致的迭代修复。

## Open Questions Deferred

- **TS `EmptyPayload` 精度缺陷修复方案**：是否需要引入 runtime 校验层，或调整 codegen 生成策略以规避结构化类型系统对空 interface 的固有行为，留待 SG-1 后续收尾轮裁定。
- **解码边界是否需要引入 strict-decode（Swift/C# 生产解码路径的严格模式）**：属 D1/D2 级设计决策，涉及跨语言运行时行为变更的成本/收益权衡，留待后续轮或设计修订评估，非本轮裁定。
- **hopper `||` 表格解析观察点是否升级为 evolution issue**：留待主会话/用户后续决定。
- **`net7.0`/Node20 actions 弃用警告**：CI 当前正常运行，升级窗口留待后续维护轮处理，非本轮阻断项。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E18 | `.github/workflows/ci.yml` + `app/contracts/d2/codegen/`（verify/type-fidelity+scripts）；commits `133b52da`/`04837f82` | SG-3 增量+SG-8.6 主体 done 的直接依据：真实 CI run 双绿 + grok T-054 证伪式对抗审 PASS_WITH_NOTE + teeth 多组反证 + 主会话独立复验 |
| E17 | `app/contracts/d2/fixtures/`（含 13 fixtures + ts/swift/csharp-runner）；rounds/0006 commits | 本轮 CI 挂接的三端金标 parity runner 的交付基座，追溯依据 |

## Next Action

- Action type: 收盘 → 待选下一 SG 开新 round（或续做 defer 项/结转项）
- Scope-lock required: yes（下一 SG 或 defer 项/结转项开 round 时新建 scope-lock）
- Human confirmation required: 否（SG-3 增量 + SG-8.6 主体本身已完整交付，闭合不需用户进一步确认）
- Safe without user input: yes（本轮收盘）；下一步若改推 SG-7/SG-8.x/Stage C/两个 defer 项，一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: 从 **SG-7**（hermes per-session key 接线）/ **SG-8.x**（PRE-1/3/7 runtime 探针）/ **Stage C**（D4 §4.6 产品行为 parity 首批，rounds/0006 结转项）/ 两个本轮新发现的 defer 项（TS `EmptyPayload` 精度缺陷/解码边界 strict-decode 设计决策）/ hopper `||` 表格观察点中择一或并行，继续逐个走 round → decision → feedback → state 回写闭环
- Disallowed until confirmed: 不得把 TS `EmptyPayload` 精度缺陷或解码边界跨语言缺口表述为"已修复"（均明确 defer，未裁定修复方案）；不得把 Stage C（D4 §4.6 产品行为 parity）表述为"已完成"（rounds/0006 结转项，独立工作包，本轮未触碰）
