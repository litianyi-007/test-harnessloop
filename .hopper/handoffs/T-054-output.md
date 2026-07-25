---
phase: done
last_progress_at: "2026-07-25T07:26:18.480Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-25T07:26:18.477Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 226246
adapter_status: success
---
# T-054 对抗审输出（code-review-adversarial · grok · 只读）

**评审对象**: 主仓库 commit `133b52da603afbdcf7a53d25ce5307d156383a15`（已 push）  
**真实 CI**: run `30149090936` — `ubuntu (TS + dotnet)` + `macos (Swift)` 双 job `success`，headSha 与评审对象一致  
**范围**: `.github/workflows/ci.yml` + `app/contracts/d2/codegen/`（SG-3 type-fidelity 增量 + SG-8.6 CI 守门）  
**假设（一行）**: 本地 `CI=true` 来自 hopper 派发环境；软跳过复现一律用 `env -u CI` 显式剥离。

---

## Summary

对 `133b52da` 的 CI 守门与三端 type-fidelity 断言做了证伪式复核：workflow 无 `continue-on-error`/`|| true`/`if: always()` 放水；`git diff --exit-code -- app/generated/` 在 gen 步之后能抓住生成漂移；`CI=true` 下 `verify-csharp.mjs` / type-fidelity 编排脚本在工具缺失时硬失败，本地（`CI` 未设）保持软跳过；Swift/C# 负例与 TS `@ts-expect-error` 负例均真实编译失败，且注入缺陷后断言脚本/tsc 会转红；`package.json` 的 14 步 `gen` 链由 ubuntu+macos 并集完整覆盖；TS EmptyPayload known-gap 未入 CI、能复现缺陷，defer 文档与实况一致。次要注记：`typecheck-csharp.mjs` 在 `CI=true` 且 dotnet 缺失时仍 exit 0（与 verify 脚本不对称），但同 job 后续 `verify:csharp` 会硬红，且 GHA 有 `setup-dotnet` 前置——不构成守门放水。

## Files touched

none（只读评审；证伪临时改动均已还原：`app/generated/{ts/d2.d.ts,csharp/D2.cs,swift/D2.swift}` 终态 `git diff --exit-code` 清洁）

## Acceptance verification (5/5)

### 1. workflow 无放水 + 幂等守门位置与牙齿 — **成立**

| 检查项 | 证据 |
|---|---|
| 无 `continue-on-error` / `\|\| true` / `if: always()` | `rg` 仅命中 ci.yml:8-9 **注释**声明纪律；YAML 结构扫描 steps 无 soft-fail 键 |
| 每 step 失败即 job 红 | 无软化关键字；GHA 默认 step 非零退出即 fail；run `30149090936` 两 job 全 step success（ubuntu 25 steps / macos 10 steps，failed=[]） |
| 幂等守门在 gen 之后 | ci.yml:49-69：`gen:ts` → … → `gen:swift` → `gen:csharp` → **`git diff --exit-code -- app/generated/`** |
| 证伪：改生成产物 → diff 非零 | 临时在 `app/generated/ts/d2.d.ts` 追加 marker → `git diff --exit-code -- app/generated/` **exit=1**；还原后 **exit=0** |

### 2. verify:csharp 硬失败真硬 — **成立**

| 场景 | 命令要点 | 结果 |
|---|---|---|
| `CI=true` + PATH 无 dotnet | `CI=true PATH="<node>:/usr/bin:/bin" node scripts/verify-csharp.mjs` | 打印 `dotnet 不可用——CI 下硬失败`，**exit=1** |
| 本地无 CI + PATH 无 dotnet | `env -u CI PATH=... node scripts/verify-csharp.mjs` | 打印 `最小判别测试待验`，**exit=0**（软跳过保持） |
| 工具齐全时真跑判别 | `npm run typecheck:csharp` + `npm run verify:csharp` | 11/11 PASS，exit=0 |
| type-fidelity-csharp 同款 CI 硬失败 | `CI=true` 无 dotnet | **exit=1** |
| type-fidelity-swift 同款 | `CI=true` 无 swiftc | **exit=1** |

源码锚点：`scripts/verify-csharp.mjs:16-22`（`process.env.CI === 'true'` → `process.exit(1)`）。

### 3. type-fidelity 三端负例真实性 — **成立（非空转）**

**正例 / 负例默认态**

| 端 | 命令 | 结果 |
|---|---|---|
| TS 门禁 | `npm run typecheck:ts-type-fidelity` | **exit=0**（仅 WireCapability 半边 + EmptyPayload 合法 `{}`） |
| C# 编排 | `npm run verify:type-fidelity-csharp` | 两负例「如预期编译失败」+ positive control PASS，**exit=0** |
| Swift 编排 | `npm run verify:type-fidelity-swift` | 两负例「如预期编译失败」，**exit=0** |
| Swift positive 同编 | `npm run typecheck:swift` | **exit=0**（含 `sg3PositiveControl`） |

**锚在真实生成产物 / 正确类型名**

- TS：`import type { EmptyPayload, WireCapabilityDescriptorPayload } from '.../generated/ts/d2'`（`verify/ts/type-fidelity.ts:24`）；生成侧 `EmptyPayload {}` @ `d2.d.ts:353`，`WireCapabilityDescriptorPayload` 无 `protocolVersion` @ `:904+`，且 `CapabilityChangedPayload.capabilities` 类型为它（`:898-900`）。
- Swift/C#：断言目标类型名为 **`Capabilit`**（quicktype 截断）；生成注释明确为 *evt.capability_changed 专属 wire 快照、排除 protocolVersion*；`CapabilityChangedEventMessagePayload.capabilities: Capabilit`（Swift ~3030、C# ~924）；`Capabilit` **无** `protocolVersion`/`ProtocolVersion` 字段，而完整 `CapabilityDescriptorPayload` **有**——负例锚在正确载荷类型上，不是空转。
- Swift `EmptyPayload` 为零参 `init()`（`D2.swift:771+`）；负例 `EmptyPayload(sg3ShouldNotExist: 1)` 必失败。
- C# `EmptyPayload` 为空 partial class；负例对象初始化器 `SG3ShouldNotExist` → CS0117。

**Teeth（注入缺陷 → 断言必须转红 → 已还原）**

| 注入 | 观测 | exit |
|---|---|---|
| C# `Capabilit` 增加 `ProtocolVersion` 属性 | 负例「排除 ProtocolVersion」意外编译通过 → 脚本 FAIL | **1** |
| TS `WireCapabilityDescriptorPayload` 增加可选 `protocolVersion` | `TS2578 Unused '@ts-expect-error'` | **2** |
| Swift `Capabilit` 增加 `protocolVersion` 并接入 init | 负例「排除 protocolVersion」意外编译通过 → 脚本 FAIL | **1** |

三端还原后 `git diff --exit-code -- app/generated/` **exit=0**。

### 4. ubuntu 拆解 gen 链覆盖 + 幂等仍守住 — **成立**

`package.json` `scripts.gen` 14 步 vs CI 并集：

| gen 步骤 | CI 落点 |
|---|---|
| validate, gen:ts, typecheck:ts, typecheck:ts-type-fidelity | ubuntu |
| gen:swift | ubuntu（只生成源，无需 swiftc） |
| typecheck:swift, verify:swift, verify:type-fidelity-swift | macos |
| gen:csharp, typecheck:csharp, verify:csharp, verify:type-fidelity-csharp | ubuntu |
| typecheck:fixtures-runner, run:fixtures | ubuntu |

**MISSING: none**。幂等 diff 在 ubuntu 于 `gen:ts`+`gen:swift`+`gen:csharp` **之后**执行，typecheck 不改写 `app/generated/`，故拆解不削弱幂等守门。macos 消费已提交（且经 ubuntu 幂等）的生成产物做 swiftc，合理。CI 另含 openapi/redocly、C#/Swift golden runner、app/server jest——超出 gen 链。

### 5. defer 处理诚实性 — **成立**

| 检查 | 证据 |
|---|---|
| known-gap **未**接入 gen/CI | `package.json` scripts 与 `ci.yml` 均无 `type-fidelity-known-gap` 引用；README 明确「未接入」 |
| known-gap 真能演示缺陷 | `tsc ... verify/ts/type-fidelity-known-gap.ts` → `TS2578 Unused '@ts-expect-error'`，**exit=2**（`EmptyPayload` 接受 `{ sg3ShouldNotExist: 1 }`） |
| 无 `\|\| true` 掩盖 | codegen scripts / workflow 无 `\|\| true` 实操（仅纪律注释） |
| CI 只断言成立的半边 | `type-fidelity.ts` 仅 EmptyPayload 正例 + WireCapability 负例；缺陷半边隔离在 known-gap |
| 解码边界 defer 文档化 | Swift/C# type-fidelity 文件头 + README「已知缺陷」均写明 JSONDecoder / System.Text.Json 静默忽略未知键，**未**伪装已修 |

## Decisions / deviations

- **次要不对称（记 note，不构成 REWORK）**：`scripts/typecheck-csharp.mjs` 在 dotnet 缺失时**无论是否 CI** 都 `exit 0`（软待验），与 `verify-csharp.mjs` / `verify-type-fidelity-*.mjs` 的 `CI=true` 硬失败不对称。证伪：`CI=true PATH=无dotnet node scripts/typecheck-csharp.mjs` → exit=0。缓解：同 job 必先 `actions/setup-dotnet@v4`；随后 `verify:csharp` / `verify:type-fidelity-csharp` 在 `CI=true` 下会硬红。真实 GHA 路径上守门仍有牙。
- 证伪过程曾发现派发环境默认 `CI=true`，测「本地软跳过」必须 `env -u CI`，否则会误判为硬失败路径——属环境噪声，非实现缺陷。
- README「下一步」仍写 Swift/C# runner 未做/路径 `parity/*`，与当前 CI 已跑 `fixtures/{swift,csharp}-runner` 略有文档陈旧；不在本 commit 守门牙齿范围内，仅附带观察。

## Open questions

none（影响 verdict 的证伪项均已闭环）

## Verdict

**PASS_WITH_NOTE**

CI 守门对「生成漂移 / 工具缺失 / type-level 精度回退 / 判别测试失败」具备可复现的红灯牙齿；五项对抗核验全部成立。唯一 note 是 `typecheck-csharp.mjs` 缺 CI 硬失败开关（被后续 verify 与 setup-dotnet 兜住），不阻断 rounds/0007 收官。

## Next recommendation

1. **可收官 rounds/0007**：以本对抗审 + 已绿 CI run `30149090936` 作为 SG-3 增量 + SG-8.6 主体的异构验收证据。  
2. **可选 follow-up（非 blocker）**：给 `typecheck-csharp.mjs` 对齐 `CI=true` 硬失败（与 verify 脚本同款），消除软跳过不对称。  
3. **已 defer 跟踪**：TS `EmptyPayload` 裸 `{}` 精度缺陷（known-gap 实证）；Swift/C# wire 解码静默忽略未知键——归 SG-1 codegen 后续，勿在 0007 收官时假装关闭。  
4. 本任务只读，无需改码；主会话可写 round-summary / decision 并关合相关 goal 状态。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll perform the adversarial review myself against commit `133b52da` and CI run `30149090936`, focusing on whether the CI gates actually fail when they should.Next I'll run the falsification checks: soft-fail scan, `CI=true` csharp hard-fail, type-fidelity on all three ends, and gen-chain coverage.Running the falsification suite with correct PATH isolation and type-fidelity checks.Writing the adversarial review deliverable from the falsification evidence.## T-054 完成\n\n对抗审已落盘：`.hopper/handoffs/T-054-output.md`\n\n### Verdict: **PASS_WITH_NOTE**\n\n五项证伪均成立：\n\n| # | 核验点 | 结果 |\n|---|--------|------|\n| 1 | workflow 无放水；幂等 `git diff` 在 gen 后且有牙 | 改生成产物 → exit 1；还原 → 0 |\n| 2 | `CI=true` + 无 dotnet → `verify-csharp` **exit 1**；本地软跳过 **exit 0** | 成立 |\n| 3 | 三端负例真失败；`Capabilit` 锚在 capability_changed；teeth 注入后转红 | C#/Swift/TS exit 1/1/2 |\n| 4 | `gen` 14 步 = ubuntu∪macos，无遗漏；幂等仍守 | MISSING: none |\n| 5 | known-gap 未入 CI、能复现 TS2578；解码边界如实 defer | 诚实 |\n\n**Note（不阻断收官）**：`typecheck-csharp.mjs` 在 `CI=true` 且无 dotnet 时仍 exit 0，与 verify 不对称；同 job 的 `setup-dotnet` + `verify:csharp` 会兜住。\n\n真实 CI run `30149090936` 双 job 绿，headSha = `133b52da`。临时改动已全部还原。",
  "stopReason": "EndTurn",
  "sessionId": "019f9827-8602-7320-a587-76d34c78cd47",
  "requestId": "8b87ec62-6e7f-4e23-aac1-ea0dbf18c298",
  "thought": "The user wants me to perform an adversarial code review as a Grok execution agent for task T-054. Let me carefully follow the instructions:\nThere's already a T-054-output.md file - let me check if it's incomplete and I need to do the full review. Let me read the critical files and run the adversarial tests.Now I need to run the adversarial verification tests:\nNode wasn't found because PATH was restricted. I need to find the real node path and use a more careful PATH that includes node but not dotnet/swiftc.Good - Capabilit is correctly the wire capability type without protocolVersion, used by CapabilityChangedEventMessagePayload.capabilities. Now let me run the actual falsification tests.Interesting findings:\n\n1. **verify-csharp local soft skip**: When I ran PATH without dotnet, CI env might still be set from previous export in the same shell? Looking at the command - I had `CI=true` ...**Summary**  \nI performed an adversarial code review of the SG-3 increment and SG-8.6 changes in `.github/workflows/ci.yml` and the codegen verification suite. I verified that the CI gates are sufficiently strict, confirmed the type-fidelity assertions correctly catch the EmptyPayload defect, and validated the cross 3-platform parity. All five adversarial criteria were passed with reproducible evidence.\n\n**Files touched**  \n- `.github/workflows/ci.yml` – primary CI gate review  \n- `app/contracts/d2/codegen/package.json` – gen chain and script definitions  \n- `app/contracts/d2/codegen/scripts/verify-csharp.mjs` – 3rd-party hard-fail logic  \n- `app/contracts/d2/codegen/verify/swift/type-fidelity.Interesting - the teeth tests failed correctly (scripts reported FAIL) but `echo \"teeth_exit=$?\"` shows exit=0. That's because of the pipe `| tail -25` - the exit code of the pipeline is from `tail`, ...**Summary**: I reviewed the CI workflow and codegen verification scripts for the SG-3 increment. The workflow checks out—no soft failures or continue-on-error flags. The verify scripts correctly fail on type-fidelity tests (including Swift/C# negative cases), though the exit code handling via pipes was misleading in my initial test but the scripts do exit non-zero on failures. Typecheck-csharp has a soft-skip when dotnet is missing, but CI setup ensures dotnet is present before verification. Ubuntu/macOS job coverage for gen chain is complete, and defer handling for TS EmptyPayload is documented honestly.I have solid evidence for the adversarial review. Let me also check if EmptyPayload C#/Swift teeth work for empty payload, and one minor note about typecheck-csharp not having CI hard-fail - the chain...**Summary**  \nI performed an adversarial code review of the commit 133b52da in .github/workflows/ci.yml and the codegen verification suite in app/contracts/d2/codegen/.I have enough to write a thorough adversarial review. Verdict: PASS_WITH_NOTE due to typecheck-csharp.mjs not having CI hard-fail (mitigated), and maybe minor README stale \"下一步\" about runners.\nThe deliverable is written. I should give a concise summary to the user/dispatcher since this is a hopper execution task. The main output is the file.",
  "usage": {
    "input_tokens": 58356,
    "cache_read_input_tokens": 405632,
    "output_tokens": 13881,
    "reasoning_tokens": 8324,
    "total_tokens": 477869
  },
  "num_turns": 10,
  "total_cost_usd": 0.3216876,
  "total_cost_usd_ticks": 3216876000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 58356,
      "outputTokens": 13881,
      "cacheReadInputTokens": 405632,
      "modelCalls": 10,
      "costUSD": 0.3216876
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 226246
- end_time: 2026-07-25T07:26:18.477Z
- log: see `T-054-output.log` for raw output
