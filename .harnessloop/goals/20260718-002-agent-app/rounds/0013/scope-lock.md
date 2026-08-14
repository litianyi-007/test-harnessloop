# Scope Lock — rounds/0013

## Round Objective

**用户 2026-08-11 给了两个里程碑,本轮以它们为目标:**

1. **学习点** —— 本轮是 `CLAUDE.md`「工程侧学习/沉淀钩子」(2026-08-11 加入)的**第一次实跑**,必须产出一份 teach-back 落进 `~/.llm-wiki/test-harnessloop`(kata 主场)。
2. **Mac app 可以基本使用** —— 这是**产品目标**,不是修复清单。本轮据此重排优先级。

**路径** = 用户裁定的 **B→C**:先清 L1 遗留(B),再按新条件③ 重跑 RAE-0001(C)。**但「基本使用」会撑破原 B→C 的范围**,故本轮显式加入第三块:**可用性探查**。

## 关于「基本使用」:已知一条,其余待实测

**唯一确知的阻断**:会话 label 硬编码 `"sg4-kernel-client-l1"`(`OpenclawGatewayKernelClient.swift:337`),openclaw 侧删会话后 label 仍被占 → **每个 state 目录只能建一次会话**。一个「新建会话第二次必失败」的聊天壳不叫可用。本轮已两次实证(UI 侧 + CLI 侧同一错误)。

**已知的降级面(非阻断,待实测确认严重度)**:
- `respondApproval()` 是桩 → 审批在客户端侧永远 pending;openclaw 侧 timeout-deny → **工具调用被拒**。coding agent 若频繁需要审批,可用性会很差,但**不挂死**。
- `interrupt()` 是桩 → 无法中断单次 run(只能 `stop()` 整个会话)。
- 无流式渲染 → 文本一次性出现(这是 `session.message` 层的行为,非壳缺陷)。
- `capabilities()` 是桩 → 读不到 `streamingGranularity`。

**本轮不预设「基本使用」还缺什么**——先探查、再由用户决定要不要把 L2 项目提前。**这一条是刻意的**:rounds/0011 的教训是不要在未查清时下确定结论。

## 三块工作

### B. 清 L1 遗留(优先做,因为它挡着一切重复实验)

**B1 — 会话 label 硬编码(必做)**：让 label 可区分,使同一 state 目录可建多个会话。
- 命名方案自定,但要能**在 UI 上区分多个会话**,且不与既有会话冲突。
- **不得**改 `KernelClient` 协议 7 方法签名;`createSession` 的 `Config` 已有字段够不够用要先看。

**B2 — `FrameReplayTests` 够不到 `SessionStore`(D3)**：本轮**允许**改 `app/Package.swift` 的依赖声明或放宽 `private`,以便给 UI 分组行为建入库确定性判据。
- **这是 rounds/0012 明确未获授权、本轮定向解除的一项。**
- 若解不开(例如引入循环依赖),**停下报告**,不硬来。

**B3 — 服务端 dispatch 竞态**：**本轮不修**。已登记为需 ack 版修法(scope blocker,要改 `app/contracts/`)。**仅在 teach-back 里记录其现状**,不动代码。

### C. 按新条件③ 重跑 RAE-0001

条件③ 已于 2026-08-10 user-confirmed 修订(权威落点 `setup/data-sources.md`),四要素:
- **(a) 不乱序** —— D2 `seq` 与 wire `messageSeq` 均不倒退
- **(b) 受控会话内无缺失** —— 收到的 assistant `(messageId, messageSeq)` 与**权威 history 快照对账**
- **(c) 破坏性反证** —— 从 wire 集合删一条 assistant 消息,对账**必须变红**
- **(d) 已知缺口** —— 协议级无丢帧列为内核缺口,不在本层验收

对账可行性依据(codex 已给,主会话未复核**,本轮须先复核**):实时帧 `server-session-events.ts:238-255` 与 history 读取 `session-transcript-readers.ts:214-226` 携带同一套 `messageId/messageSeq`。**先验证这两处确实能对上,再动手建对账。**

四条件其余三条(①真实往返 ②隔离性 ④失败可诊断)rounds/0012 已达成,本轮**重跑确认**即可,不必重新设计取证方式。

### D. 可用性探查(新增,为里程碑 2)

在 B1 完成后,**以真实使用的方式**跑一遍壳,回答:**除 label 外,还有什么挡着「基本使用」?**

- 建 ≥3 个会话、来回切换、各发数条消息
- 让 agent 做一件**需要用工具**的事(观察审批路径实际后果)
- 重启 app,看会话状态如何
- **如实记录哪些卡住、哪些只是难用**

**探查完停下报告,不擅自把 L2 项目拉进来。** 要不要提前做 stop 按钮 / 审批 UI,由用户看探查结果决定。

## 驱动模型

写码派 claude-sonnet-5 子代理(**必须显式传 `effort: "xhigh"`**);主会话独立复验并亲跑 live 与探查。**scope-lock / 验收判定 / teach-back 的「Inferred」部分不委派**。★审查闸(hopper,**换 codex**——0012 是 grok)。收敛守卫:第 3 个 MUST-FIX → checkpoint。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/kernel-client/swift/` | 改 | B1 的 label;C 的对账所需读取;**不改协议签名、不改既有映射语义** |
| `app/apps/AgentShell/` | 改 | B1 的多会话 UI;D 探查所需的最小修补 |
| `app/Package.swift` | 改 | **B2 定向解除**:仅为让测试够到 `SessionStore` |
| `app/apps/AgentShell/repro/` | 改 | 若 B1 改变了复现步骤则同步 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0013/` | 写 | evidence + RAE 台账 + 收口 |
| `.harnessloop/state/`、`goal-breakdown.md` | 改 | 状态指针与 SG-10 行 |
| `~/.llm-wiki/test-harnessloop` | 写 | **里程碑 1 的 teach-back**(kata 主场) |
| `.hopper/` | 写 | ★审查闸 |
| `docs/validation-log.md` | 改 | **2026-08-11 中途补入**：`CLAUDE.md`「工程侧学习/沉淀钩子」（2026-08-11 加入）规定「轮次收盘」与「插件缺陷被确认」两个触发点都要写这个文件。起草本 scope-lock 时漏列——**是起草失误，不是本轮扩范围**。按本轮纪律第 4 条（标准不合适先改 scope-lock，不在验收时放宽解释）显式补入而非默默越界 |
| 隔离 openclaw、本机 D3-proxy | 起/停 | 预授权 test-resource;用 `repro/` 三件套 |

## Disallowed Changes

- **L2/L3 功能**:流式渲染精细化、stop 按钮、审批五态 UI、成本面板、能力开关。**D 探查若显示它们是「基本使用」的阻断,停下报告等裁决,不擅自开工。**
- 改 D1/D2/D5 契约语义;手改 `app/generated/`;改 `app/contracts/`(含 fixtures)。
- 改 `kernels/`、`app/server/`、`app/deploy/`、`app/parity/`、三插件 submodule。
- **写 Pi 的 Postgres 或任何 `raspberry-pi-deploy` 资源** —— `write-safety-required`,未授权。
- 凭证进任何 tracked 文件。
- 在未查清机制的情况下按推断改代码。

## One-Variable Strict Mode

- Enabled: no(B/C/D 三块彼此独立)。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 基线不破 | `swift build --package-path app` 通过;帧回放 **≥38/38** | 构建 + 测试输出 |
| CI 平价 runner | **12 PASS / 0 FAIL / 1 DEGRADED** | 逐字复现 CI 命令 |
| 三端 codegen 校验 | `typecheck:swift`/`verify:swift`/`verify:type-fidelity-swift`/TS runner 全绿 | 逐条实跑 |
| **B1 多会话** | 同一 state 目录**连续建 ≥3 个会话全部成功**;UI 上可区分 | 截图 + wire trace |
| **B1 反证** | 改回硬编码 label → 第二次新建**必须失败** | 破坏性反证记录 |
| **B2 测试可达** | 有一条**入库**测试直接验 `SessionStore` 的分组行为;破坏分组逻辑该测试变红 | 红→绿两段输出 |
| **C 对账** | 受控会话的 `(messageId, messageSeq)` 与 history 快照逐条对上 | 对账输出 |
| **C 反证** | 删一条 assistant 消息 → 对账**变红** | 红→绿两段输出 |
| RAE-0001 | 四条件逐条判定 | `evidence/runtime/acceptance-evals.json` |
| **D 探查** | 一份「还缺什么」的清单,区分**阻断** vs **难用** | 探查记录 |
| **里程碑 1** | teach-back 落进 `~/.llm-wiki/test-harnessloop`,含 Observed/Inferred/Deferred/Mastery | wiki 页面 |
| ★审查闸 | PASS / PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits

- Recovery:B1 方案不通 / 对账对不上 / 探查发现新阻断 → 诊断迭代(runtime-recoverable)。
- Cleanup:隔离实例用 `repro/stop-isolated-kernel.sh` 收;**删除非本轮新建的东西不在预授权内**。

## Rollback Condition

- B1 若必须动协议签名才能做 → 停下记 blocker,归设计轮。
- B2 若解依赖会引入循环依赖或破坏既有 target → 回滚,如实记录「UI 层仍无入库判据」。
- C 若 history 与实时帧的 `(messageId, messageSeq)` **对不上**(codex 的依据不成立)→ 停下报告,**不改条件③ 去迁就**,按 rounds/0012 的先例交用户裁决。

## Human Confirmation Required

- 自动化 + ★审查闸:既定授权。
- **D 探查的结果** —— 是否把 L2 项目提前,由用户定。
- **UI 层人工验收的「人」是用户** —— 截图与探查记录须呈交过目。

## 本轮纪律(承接 0011/0012 的教训)

1. **不得在未查清机制时按推断改代码**。
2. **每次状态提升要指向新增证据**,不得无证据改判。
3. **破坏性反证是硬要求**,且**必须先看到红**——0012 有两次「破坏没生效却读成没问题」,均因未核对实际内容。
4. **按自己写的字面标准验**;标准不合适先改 scope-lock,不在验收时放宽解释。
5. **「我没找到」不等于「不存在」** —— 0012 里这个错误犯了三次(`logging.file`、D2 §3.3、targeted 帧的 `EventFrame.seq`),三次都由异构评审纠正。**本轮凡要下「没有/做不到」结论,先换一个搜索维度再说。**
