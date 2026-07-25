# Scope Lock — rounds/0007

## Round Objective

**SG-3 增量收口 + CI 守门（SG-8.6 主体）**：全仓当前无任何 CI（无 `.github/workflows/`）。本轮：①补 SG-3 验收缺口——`EmptyPayload` 精确空对象 / `WireCapabilityDescriptorPayload` 排除字段类型在三端生成产物中的 **type-level 保真断言**（现状：`codegen/verify/{swift,csharp}` 无任何相关断言，grep 零命中）；②建 committed GitHub Actions（SG-8.6 主体）——codegen 冒烟（`npm run gen` + 幂等无 diff）、openapi 校验、`verify:csharp` 在 CI 下 dotnet 缺失从软跳过（`verify-csharp.mjs:15` 现状）改**硬失败**、**三端金标 parity runner（TS/Swift/C#，rounds/0006 交付）挂进 CI** 作为回归防线、app/server 测试如有则挂入；③push 后真实 CI run 绿作为 runtime 证据。

**与 SG-8.6 的关系（诚实边界）**：SG-8.6 pass 条件（gen 幂等 / openapi 校验 / 测试全绿 / dotnet 硬失败）与 SG-3 的"CI 新增 codegen 冒烟步骤"是同一个 workflow 文件的工作包，本轮一并做即 SG-8.6 主体；若 app/server 测试基建缺失（jest 未配等），如实标注该子项状态，不硬凑。

## 驱动模型：continue 驱动 + 关键节点独立审查（延续 0005/0006 机制）

单阶段轮。写码派 claude-sonnet-5 子代理；主会话独立复验（本地逐步模拟 CI 步骤 + push 后 `gh` 看真实 run）；**★审查闸**（hopper codex/grok）在 CI 绿后审——重点证伪"**CI 绿灯是否真的会红**"（幂等 diff 检查真有牙齿 / 硬失败真硬 / 无 step 被 `|| true`、`continue-on-error` 静默放水 / type-level 断言破坏精度后真 FAIL）。收敛守卫：第 3 个 MUST-FIX → checkpoint 用户。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `.github/workflows/` | 新建 | CI workflow（runner 成本审慎：ubuntu 承载 node/dotnet/TS 步骤，macos 仅 Swift 必需步骤；net7.0 经 setup-dotnet） |
| `app/contracts/d2/codegen/verify/{swift,csharp}/` + `scripts/` | 写 | type-level 断言 + verify:csharp 的 CI 硬失败开关（如 `CI=true` 时 exit 非零） |
| `app/contracts/d2/codegen/package.json` | 改 | 如需新增 script 入口 |
| 主仓库 push（origin surebeli/test-harnessloop） | push | 既定授权流程（批次验收通过后无需逐次确认，见 control-contract 例外条款）；仅主仓库，不动三插件 submodule 版本 |
| `.harnessloop/rounds/0007/` + state、`.hopper/` | 写 | round 收口 + 审查闸派发 |

## Disallowed Changes

- 改 `app/generated/`（生成产物只能由 `npm run gen` 再生,不得手改）、`app/contracts/d2/schema/`（若断言暴露 schema 缺陷 → 停下记 blocker）、`app/kernel-client/`、`app/contracts/d2/fixtures/`（rounds/0006 已收口,CI 只消费）。
- 内核/server 源码、三插件 submodule、wiki。
- CI 中不得引入凭证(全部步骤不需要任何 secret;不配任何 repo secret)。

## One-Variable Strict Mode
- Enabled: no（CI workflow + 断言两件小事,单阶段）。

## Verification Commands Or Checks

| Check | Method | Expected | Evidence |
|---|---|---|---|
| type-level 断言 | 本地跑 verify 三端 + **teeth**（临时破坏 EmptyPayload/排除字段精度 → 断言必须 FAIL → 还原） | 修前无断言,交付后断言在且有牙齿 | verify 输出 + teeth 记录 |
| CI 步骤本地模拟 | 逐 step 本地跑（gen 幂等 diff/openapi/三端 runner/verify） | 全绿 | 命令输出 |
| 真实 CI run | push → `gh run watch/view` | CI 绿（首次可能迭代修 runner 环境差异,属本轮 recovery） | GH run URL/日志 |
| ★审查闸 | hopper codex/grok 审"绿灯是否真的会红" | PASS/CONFIRMABLE | `.hopper/handoffs/T-05x-output.md` |

## Runtime Recovery Limits
- Recovery: CI 环境差异（runner 工具链/版本）→ 修 workflow 迭代,属 runtime-recoverable;若须改已收口组件（fixtures/kernel-client/schema）才能过 CI = contract-insufficient 停下上报。
- Cleanup: 无长驻资源（CI 是 GH 托管）。

## Rollback Condition
若 type-level 断言暴露 SG-1 生成产物真实精度缺陷（EmptyPayload 不精确/排除字段泄漏）——这是"断言揪出上游"的正常产出：停下报 blocker（属 SG-1 codegen scope,不在本轮擅修 schema/生成器）,断言如实标 FAIL 或 defer,不 fudge。

## Human Confirmation Required
- 自动化执行 + 审查闸派发 + 主仓库 push：均已有既定授权（continue 驱动 + push 批次授权）,无需逐步确认。
- 若 CI 需要付费资源超出常规（如大量 macos 分钟）：workflow 已按成本审慎拆分,不需额外确认;若实测 macos 步骤显著超预期,收官时如实报告成本观察。
