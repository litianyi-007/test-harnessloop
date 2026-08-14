# Scope Lock — rounds/0016

## Round Objective

**用户 2026-08-12 裁定「收 0015 开 0016」**。本轮只做一件事：
**把 exec 审批 FSM 的失败路径、超时路径与持久化状态补完**，让 ★审查闸能过。

rounds/0015 的主判据（审批放行/拒绝端到端）**已达成并 live 验证**；
但 ★审查闸 T-095/T-096 共提 6 条，其中**四条属同一族且未做**——全是**边界失败态**，不是主路径。
本轮就是这四条。

## 待修四项（逐字取自 T-096 的 Next recommendation，主会话未改写）

1. **溢出事件的成功判据**：溢出 deny 必须以 `applied:true + status:denied` 为成功依据；
   **失败不可吞掉，也不可提前宣称已自动拒绝**。
2. **强制 deny 失败后的持久状态**：显式持久化 `FORCE_DENY_PENDING_KERNEL_ACK`，
   强制 deny 失败后**只允许幂等 deny 重试**。
3. **`approval.resolve` 的有界等待**：增加有界等待，并让**权威 timeout terminal 能结束对应 in-flight**。
4. **active terminal 后的 UI 同步**：active terminal 必须驱动 UI **先清除旧卡片再呈现提升项**；
   **队列徽标应接真实缓冲计数或删除**（不得显示编造的数字）。

## 已就位的基础（0015 交付，本轮不重做）

- `respondApproval` 实调 `approval.resolve`；decision 三值显式映射（D2 下划线 ↔ openclaw 连字符）
- **逐请求** `allowedDecisions` 校验（客户端先拦，不让服务端 `forceMalformedDeny` 静默改写）
- **post-RPC 兑现核验**（`forceMalformedDeny` 会回 `ok:true`，只看 RPC 成功会被骗）
- D1 §6.2 FSM 主干：单 active + 深度 8 FIFO + 溢出 fail-closed deny + 提升
- per-reqID in-flight 槽位；drain 收敛条件「pending 空 **且** 无在途 resolve」
- 握手 `caps:["exec-approvals"]`；两条 stream 的审批关联采集
- `approval_not_pending` 的真实形状是 `ok:true + applied:false`（**不是错误码**）

## 本轮不做

- 需要改 D2/D1 契约的项：超时态无 D2 对应、`ApprovalBufferResolvedEvent.reason` 词表表达力不足
  （0015 已登记，**属设计轮/上游议题**）
- `capabilities()` 落地（0015 登记的漂移风险）
- rounds/0014 遗留三项与 `[gateway] ready` 就绪判据缺口 —— 天然触及可顺带修，**不得为此单独开工**
- 改 `app/contracts/`、`app/generated/`、`kernels/`、三插件 submodule

## 驱动模型

写码派 claude-sonnet-5 子代理（**必须显式传 `effort: "xhigh"`**）；主会话独立复验并**亲跑 live**。
**scope-lock / 验收判定不委派。** ★审查闸（hopper，**换 grok**——0015 连派 codex 两轮）。

**收敛守卫：第 3 个 MUST-FIX → checkpoint。** 0015 越线两倍的教训在此：
**守卫也是标准，不能只在对自己有利时遵守。**

**派 hopper 必须走 `--adhoc --brief`**（queue brief 静默丢弃缺陷未修）；
**不要拿不同输出模式的 vendor 比 log 行数**判断评审是否真发生（grok 是 `bufferedOutput vendor`）。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/kernel-client/swift/` | 改 | 四项的实现；**不改 D1 七法签名、不改既有帧映射语义** |
| `app/apps/AgentShell/` | 改 | 第 4 项的 UI 同步与队列徽标 |
| `app/apps/AgentShell/repro/` | 改 | 复现步骤同步 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0016/` | 写 | evidence + RAE 台账 + 收口 |
| `.harnessloop/state/`、`goal-breakdown.md` | 改 | 状态指针与 SG 行 |
| `docs/validation-log.md` | 改 | 收盘条目与插件缺陷条目 |
| `~/.llm-wiki/test-harnessloop` | 写 | 跨轮可复用事实（kata 主场） |
| `.hopper/` | 写 | ★审查闸 |
| 隔离 openclaw 实例 | 起/停 | 预授权 test-resource；`L1_ROOT` 指向 scratchpad |

## Disallowed Changes

- **改 D1 七法签名**、改帧映射/协议语义、手改 `app/generated/`、改 `app/contracts/`
- 改 `kernels/`、`app/server/`、`app/deploy/`、`app/parity/`、三插件 submodule
- **写 Pi 的 Postgres 或任何 `raspberry-pi-deploy` 资源** —— `write-safety-required`，未授权
- 凭证进任何 tracked 文件（含 evidence 原件）
- 在未查清机制的情况下按推断改代码
- **不得为了让流程跑通而放宽失败判据**（例如把溢出 deny 的失败当成功）

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 基线不破 | `swift build` 通过；帧回放 **≥68/68** | 构建 + 测试输出 |
| CI 平价 runner | **12 PASS / 0 FAIL / 1 DEGRADED**（硬判据） | 逐字复现 `ci.yml:145-155` |
| D1 契约未动 | 七法签名 `git diff` 为空 | diff 自证 |
| 三端 codegen | 四项全绿 | 逐条实跑 |
| **反证① 溢出失败** | 构造 overflow deny 的**三种失败响应**（RPC 失败 / `applied:false` / 终态非 denied），各须被如实报错，**不得吞掉、不得提前宣称已拒绝** | 红→绿 |
| **反证② 强制 deny 失败后人工 allow** | 强制 deny 失败 → 持久态存在 → 人工 allow 必须被正确处理（幂等 deny 重试语义） | 红→绿 |
| **反证③ in-flight timeout** | `approval.resolve` 有界等待到期 / 权威 timeout terminal 到达 → in-flight 必须被结束，不得永久占位 | 红→绿 |
| **反证④ active timeout → #2 浮现** | active 超时后 UI **先清旧卡再呈现提升项**；队列徽标数字与真实缓冲计数一致 | 红→绿 + 截图 |
| **live 主链不回归** | 审批卡渲染 → 允许 → 命令执行；拒绝 → 命令未执行 | 截图 + wire trace |
| RAE-0001 不回归 | 重跑仍 pass | `evidence/runtime/acceptance-evals.json` |
| ★审查闸 | PASS / PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits

- Recovery：反证构造不出 / 失败态复现不了 → 诊断迭代（runtime-recoverable）。
- Cleanup：隔离实例用 `repro/stop-isolated-kernel.sh` 收；**删除非本轮新建的东西不在预授权内**。

## Rollback Condition

- 若某一项必须改 D1/D2 契约才能做成 → **停下记 blocker**，归设计轮，本轮如实标注该项未达成。
- 若修复引入 live 主链回归且短期修不回 → 回滚该项，如实记录。

## Human Confirmation Required

- 自动化 + ★审查闸：既定授权。
- **UI 层人工验收的「人」是用户** —— 反证④ 的截图须呈交过目。
- **第 3 个 MUST-FIX 触发 checkpoint 时停下等裁决**（0015 的直接教训）。

## 本轮纪律（承接 0011–0015）

1. **不得在未查清机制时按推断改代码。**
2. **每次状态提升要指向新增证据。**
3. **破坏性反证必须先看到红**，并**打印实际被破坏的内容**。
4. **按自己写的字面标准验**；标准不合适先改 scope-lock，不在验收时放宽解释。**守卫也是标准。**
5. **「我没找到」不等于「不存在」** —— 先换搜索维度。
6. **证据当场冻结进 `rounds/0016/evidence/`**，不许留在 scratchpad 靠转述。
7. **不要拿不同输出模式的 vendor 比 log 行数**判断评审是否真发生。
8. **（0015 新增）分歧/不确定处启用异构模型，且主会话的判断先登记再对照** ——
   0015 里主会话三条候选全错、正解由 grok 单独找到；**预登记是唯一能确证「不是被带过去」的手段**。
9. **（0015 新增）给子代理的核实指令要确保可执行** —— 0015 让它「在 `app/contracts/` 下核实 D1 原文」，
   而那里只有 10 行占位符。**指令不可能完成时，好的执行方会照实说；但出这种指令是委派方的错。**
