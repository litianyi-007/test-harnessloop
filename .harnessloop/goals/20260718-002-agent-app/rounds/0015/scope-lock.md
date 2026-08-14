# Scope Lock — rounds/0015

## Round Objective

**用户 2026-08-11 裁定 rounds/0013 Human Decision 第 2 项：exec 策略 = 「直接把 `ask` + 审批 UI 提前做」**
（不走 allowlist 过渡）。本轮做这件事。

**为什么是现在**：rounds/0013 实测发现壳里的 agent 可以在宿主机上**直接执行 shell，无任何确认关卡**，
且这不是隔离实例的特例——是**未配置时的内核默认**。rounds/0014 已解除「基本使用」的功能阻断，
本轮解除**信任边界**上的那个。

## 已查清的机制（开工前完成，不是推断）

| 事实 | 出处 |
|---|---|
| 未配置时 openclaw 默认 `security=full` / `ask=off` —— 所以**从不发起审批** | `kernels/openclaw/src/infra/exec-approvals.ts:317-318` |
| `ask` 是三档枚举 `off` / `on-miss` / `always` | `kernels/openclaw/src/config/zod-schema.agent-runtime.ts:518` |
| 审批只在 `ask=always`，或 `ask=on-miss` 且 allowlist miss 时发生 | `exec-approvals.ts:1840-1857` |
| **入站已就绪**：`session.approval` → `evt.approval_request` 的映射**已实现**，`reqID = approval.id` | `app/kernel-client/swift/EventMapping.swift:492-580` |
| **出站是桩**：`respondApproval()` 直接抛 `notImplemented` | `OpenclawGatewayKernelClient.swift:990-991` |
| **D1 的 `respondApproval` 签名本来就存在** —— 实现它**不改 D1 七法** | `KernelClient.swift:96-97` |
| openclaw 的响应 RPC 是 **`approval.resolve`**（另有 `approval.get` / `approval.history`） | `server-methods/approval.ts:436` |
| exec 审批默认超时 **30 分钟** | `exec-approvals.ts:315` |

### ⚠ 本轮最容易咬人的一处：decision 两侧取值不一致，且**错了会静默变 deny**

| 侧 | 取值 |
|---|---|
| D2 `ApprovalDecisionKindElement` | `allow_always` / `allow_once` / **`allow_session`** / `deny`（**下划线**） |
| openclaw `ApprovalDecision` | `allow-once` / `allow-always` / `deny`（**连字符**，**没有 session 档**） |

出处：`app/generated/swift/D2.swift:1231-1236`；`kernels/openclaw/src/mcp/channel-shared.ts:88`

而 `approval.resolve` 的校验逻辑（`approval.ts:476-486`）是：

```ts
const decisionAllowed =
  requestedDecision === "deny" ||
  (requestedDecision !== null &&
    record.presentation.allowedDecisions.includes(requestedDecision));
const kindMatches = resolveParams?.kind === record.presentation.kind;
const forceMalformedDeny = !validParams || !kindMatches || !decisionAllowed;
```

→ **三件事**：
1. `allowedDecisions` 是**每条请求各自携带**的，不是全局固定集合——不能硬编码；
2. `kind` 必须与该条请求的 `presentation.kind` 一致，响应要回传；
3. **参数不合法 / kind 不匹配 / decision 不在允许集内 → `forceMalformedDeny`，即
   用户点的「允许」会静默变成「拒绝」，而且不报错。**

**这是本轮的头号风险**，必须有专门的反证。

## 四块工作

### A. 实现 `respondApproval()`（出站）

把桩换成真调用 `approval.resolve`。**D1 签名不得变**（`respondApproval(session:reqID:decision:)`）。

### B. decision 映射与 `allowedDecisions` 协商

- D2 四值 ↔ openclaw 三值的映射必须**显式写死并有测试**，不得靠字符串替换碰运气
- **`allow_session` 在 openclaw 侧没有对应**——本轮必须**明确处置**：或映射到最近语义并记录代价，
  或在 UI 上不提供该选项。**不得静默降级成别的东西。**
- 响应必须回传该条请求的 `kind`，并**校验 decision 在该请求的 `allowedDecisions` 内**；
  不在集合内时**必须在客户端侧就报错**，而不是发出去让服务端 `forceMalformedDeny`

### C. 审批 UI

壳要能：呈现待审批请求（至少：工具/命令、请求原因、超时剩余）、让用户做出裁决、把结果回传。
**范围克制**：本轮只要求「五态」里真正必需的那几个，够用即可；不做成本面板、不做审批历史浏览。

### D. 配置 `ask` 并端到端 live 验证

`repro/start-isolated-kernel.sh` 写入的隔离配置目前**不设任何审批策略**。本轮要能起一个
`ask=always`（或 `on-miss`）的实例，跑通「agent 要执行 exec → UI 弹出审批 → 用户允许 → 命令执行」
与「用户拒绝 → 命令不执行」两条路。

## 本轮不做

- allowlist 维护界面、审批历史浏览、成本/用量面板、流式渲染精细化、stop 按钮。
- rounds/0014 遗留的三条审查闸 note（非布尔 `hasMore` 静默停止 / placeholder handle 的
  `kernelSessionID` / live 未覆盖多页历史）——**登记在此，若本轮改动天然触及可顺带修，
  但不得为此单独开工**。
- `repro` 就绪判据缺口（`[gateway] ready` ≠ `sessions.create` 可用）——同上，可顺带修。
- 改 `app/contracts/`、`app/generated/`、`kernels/`、三插件 submodule。

## 驱动模型

写码派 claude-sonnet-5 子代理（**必须显式传 `effort: "xhigh"`**）；主会话独立复验并**亲跑 live 审批往返**。
**scope-lock / 验收判定不委派。** ★审查闸（hopper，**换 codex**——0014 是 grok）。
收敛守卫：第 3 个 MUST-FIX → checkpoint。

**派 hopper 必须走 `--adhoc --brief` 通道**——queue.md 的 brief 在任务无 `leader-tasklist.md`
条目时会被静默丢弃（rounds/0013 实证的 hopper 缺陷，已开 issue，未修）。
**另注**：grok 属 `bufferedOutput vendor`，raw log 只收尾部 JSON，**不能用 log 行数判断它有没有真干活**
（rounds/0014 我据此误判过一次）。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/kernel-client/swift/` | 改 | `respondApproval` 实现、decision 映射；**不改 D1 七法签名、不改既有帧映射语义** |
| `app/apps/AgentShell/` | 改 | 审批 UI 与其状态 |
| `app/apps/AgentShell/repro/` | 改 | 隔离实例的 `ask` 配置与复现步骤 |
| `app/Package.swift` | 改 | 仅当确有必要 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0015/` | 写 | evidence + RAE 台账 + 收口 |
| `.harnessloop/state/`、`goal-breakdown.md` | 改 | 状态指针与 SG 行 |
| `docs/validation-log.md` | 改 | 收盘条目与插件缺陷条目 |
| `~/.llm-wiki/test-harnessloop` | 写 | 跨轮可复用事实（kata 主场） |
| `.hopper/` | 写 | ★审查闸 |
| 隔离 openclaw 实例 | 起/停 | 预授权 test-resource；`L1_ROOT` 指向 scratchpad |

## Disallowed Changes

- **改 D1 七法签名**、改帧映射/协议语义、手改 `app/generated/`、改 `app/contracts/`。
- 改 `kernels/`、`app/server/`、`app/deploy/`、`app/parity/`、三插件 submodule
  （rounds/0014 的 hopper issue 例外**不延续到本轮**）。
- **写 Pi 的 Postgres 或任何 `raspberry-pi-deploy` 资源** —— `write-safety-required`，未授权。
- 凭证进任何 tracked 文件（含 evidence 原件）。
- 在未查清机制的情况下按推断改代码。

## One-Variable Strict Mode

- Enabled: no（A/B/C/D 四块彼此耦合）。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 基线不破 | `swift build` 通过；帧回放 **≥50/50** | 构建 + 测试输出 |
| CI 平价 runner | **12 PASS / 0 FAIL / 1 DEGRADED**（硬判据） | 逐字复现 `ci.yml:145-155` |
| D1 契约未动 | `KernelClient.swift` 七法签名逐字未变 | diff |
| 三端 codegen | `typecheck:swift`/`verify:swift`/`verify:type-fidelity-swift`/TS runner 全绿 | 逐条实跑 |
| **审批放行（主判据）** | `ask` 开启下，agent 要执行 exec → UI 呈现审批 → 用户允许 → **命令真的执行且回结果** | 截图 + wire trace + 冻结原件 |
| **审批拒绝** | 用户拒绝 → **命令不执行**，且会话不挂死、有明确反馈 | 同上 |
| **反证①：静默变 deny** | 故意发一个不在该请求 `allowedDecisions` 内的 decision → **必须在客户端就被拦下报错**，不得发出去被服务端悄悄转成 deny | 反证记录（先看到红） |
| **反证②：`allow_session` 缺口** | D2 的 `allow_session` 在 openclaw 无对应——处置方式必须可被验证（要么 UI 不给该选项，要么映射有显式记录），**不得静默降级** | 反证/设计记录 |
| **不挂死** | 审批未响应时的行为可预期；30 分钟超时不得成为唯一出路 | 观察记录 |
| RAE-0001 不回归 | 重跑仍 pass | `evidence/runtime/acceptance-evals.json` |
| ★审查闸 | PASS / PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits

- Recovery：审批不弹 / 回传被拒 / decision 映射对不上 → 诊断迭代（runtime-recoverable）。
- Cleanup：隔离实例用 `repro/stop-isolated-kernel.sh` 收；**删除非本轮新建的东西不在预授权内**。

## Rollback Condition

- **若必须改 D1 七法签名或 `app/contracts/` 才能做成** → 停下记 blocker，归设计轮。
- 若 `ask` 开启后出现新的挂死路径且短期修不回 → 回滚配置改动，如实记录「审批未达成」，
  **不得为了让流程跑通而把 `ask` 关掉当作通过**。

## Human Confirmation Required

- 自动化 + ★审查闸：既定授权。
- **UI 层人工验收的「人」是用户** —— 审批弹窗与放行/拒绝两条路的截图须呈交过目。
- **`allow_session` 的处置方式**若涉及产品语义取舍（例如决定不提供该选项），呈交用户确认。

## 本轮纪律（承接 0011–0014）

1. **不得在未查清机制时按推断改代码。**
2. **每次状态提升要指向新增证据**，不得无证据改判。
3. **破坏性反证是硬要求，且必须先看到红**，并**打印出实际被破坏的内容**。
4. **按自己写的字面标准验**；标准不合适先改 scope-lock，不在验收时放宽解释。
5. **「我没找到」不等于「不存在」**——先换一个搜索维度再下「没有/做不到」的结论。
6. **证据必须当场冻结进 `rounds/0015/evidence/`**，不许留在 scratchpad 靠转述。
7. **（0014 新增）不要拿不同输出模式的 vendor 比 log 行数**判断评审是否真发生；
   看产物里有没有可复核的 file:line 引用与 JSON 信封的 turn/token 计数。
