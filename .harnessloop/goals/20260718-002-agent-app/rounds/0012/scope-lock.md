# Scope Lock — rounds/0012

## Round Objective

**SG-10 L1 修复轮**（不是新功能轮）。rounds/0011 收成 `Accepted: no` / `Feedback: negative`——★审查闸 codex T-080 判 REWORK，主会话逐条自验后采纳，RAE-0001 outcome=`fail`。本轮修掉那些缺陷、重取证据，**再次判定 RAE-0001**。

**代码不回滚**：SwiftPM 打包（`app/Package.swift` 5 target）与 SwiftUI 壳（`app/apps/AgentShell/`）是有效交付——帧回放 30/30 与改造前基线逐数吻合、CI 三条 Swift 步骤全绿。本轮在其上修。

**blocker 分类**：`contract-insufficient`，`runtime-recoverable`。本轮全部动作限于缺陷修复 + 证据重取，不引入 L2/L3 任何功能。

## 六项限定范围（逐条来自 rounds/0011 decision.md）

### ① 修消息分组

**已核实的事实**（不是推测）：
- `message` 载荷**没有 `id` 字段**——实测 wire 帧的 `message.keys = ['content','role','timestamp']`，无服务端消息标识可直接用作分组键。
- openclaw 的 `event=chat` 有 `state` 生命周期：`status`（多条）→ `delta`（带 `deltaText` **且**带 `message`）→ `final`（带 `message` + `stopReason`）。
- **kernel-client 全仓没有任何一处按 `state` 分支**（`EventMapping.swift` 与 `OpenclawGatewayKernelClient.swift` 均 grep 无命中）——`delta` 与 `final` 走同一条映射路径。
- `EventMapping.swift:197` 的 `index` 来自 `blocks.enumerated()`，是**单条 message 内**的 content-block 下标，每条新消息从 0 重启；`SessionStore.swift:184-194` 按 `(runID,index)` 永久复用气泡。

**尚未搞清、本轮必须先查明的**：注入失败那次（`screens/l1-injected-failure-midchain.png`）错误文本**重复了两次**，而成功那次（`ROUNDTRIP OK`）**没有重复**。按「delta 与 final 都产出 messageDelta 且 index 同为 0」的推断，两次都该重复。**这个差异说明我对机制的理解还不完整。**

**本轮要求**：先定位真实机制（读 wire 帧 + 读映射代码 + 必要时加临时打点），**再**动手改。不得跳过定位直接按推断改——那正是 rounds/0011 「把既成缺陷记成待验假设」的反面翻版：这次不能反过来把未查清的机制当成已知根因。

---

### ①' 定位已完成 + 修法定案：**走 C（透传消息标识）**（user-confirmed 2026-08-08）

**定位结论已推翻上面 §21 的推断**（证据：`evidence/item1-mechanism-localization.md`、`evidence/instrumented-run-findings.md`、`evidence/raw/wire-trace.jsonl`）：

- `session.message` 层**不做增量投递**——一条 assistant 消息 = 一条帧 = 一个 `evt.message.delta`，`delta` 携带**完整全文**（实测 `'1\n2\n…\n12'` 单事件 `index=0`）。增量在 `chat` 旁路流上，kernel-client 不消费。故 `SessionStore` 的 `text += delta` **在这一层永远是错的**。
- 重复的真根因：注入失败时同一 run 产出**两条不同帧**（`messageId` 各为 `1cf68049`/`0aaec118`），同 `runID`、同 `index=0` → 撞 `"runID#index"` 键 → 追加 → 文本重复。上面 §21 那个「delta 与 final 同路径」的推断是**在错误的事件流（`chat`）上得出的**，已作废。

**hopper 双路异构评审**（T-081 codex / T-082 grok，同一 brief、互不可见）：两家**一致**认定根因是键空间错误、**B 否决成立**、**C 是正确解**；分歧只在要不要先上权宜的 A。

- codex 反对 A（主会话核实成立，**且是主会话原先漏掉的**）：A 在 schema 层确实零改动，但它**把 `evt.message.delta` 固化解释成「完整消息」**，与 D5.1 §3.1 明文的渲染契约相抵触——「按到达顺序把 `delta` **追加**进当前 assistant 消息气泡，粒度受 `capabilities().streamingGranularity` 门控」。违反的是**行为契约**，不是 schema。
- grok 支持 A 的关键反驳（主会话核实**亦成立**）：多 content-block 场景下**现状本就开多个气泡**（index 不同→键不同），A 与现状等价、不引入新缺陷。
- 主会话补充（两家均未提）：**`capabilities()` 当前是 TODO 桩**，壳根本读不到 `streamingGranularity`——D5.1 那条契约目前无任何实现能真正遵守。

**用户裁决 2026-08-08：选 C，扩本轮 scope 承载。** 本轮由此从纯修复轮变为**「修复 + 契约面设计」轮**，以下两处禁区**定向解除**，其余禁区一律不变。

| 原禁区 | 解除后允许 | 仍然禁止 |
|---|---|---|
| `app/generated/` 不得改 | 允许**经 codegen 重新生成**（改 schema 源 → 跑既有 codegen → 产物随之更新） | **手改生成产物**——下次 codegen 会丢失，且破坏 `app/contracts/d2/codegen` 的 verify 契约 |
| D1/D2 契约语义不得动 | 允许为 `MessageDeltaEventMessagePayload` **新增一个可选的消息标识字段** | 改既有字段的语义/类型/必选性；改 `KernelClient` 协议 7 方法签名；改 `EventMapping` 既有映射行为（新增字段的填充除外） |

**C 的硬要求**：

1. **改 schema 源，不手改产物**（源在 `app/contracts/d2/`）。
2. **新增字段必须可选**：不得让既有消费方（C#/TS 端、`FrameReplayTests` 既有帧）因缺该字段而失败。
3. **既有校验逐条全绿、缺一不可**：`swift build` 全 5 target、帧回放 **30/30**、`typecheck:swift`、`verify:swift`、`verify:type-fidelity-swift`、CI flat-`swiftc` 平价 runner **12/0/1**。
4. **壳侧改用新字段分组**，删除 `(runID,index)` 键与 `+=` 的错误组合。
5. **破坏性反证**：构造「同 run 两条不同 assistant 消息」，确认**修前真的重现重复**、修后不重复。修前那次没重现出来，就说明反证场景没构造对，不得跳过。
6. **不得声称本轮实现了 D5.1 的渲染契约**：`capabilities()` 仍是桩，`streamingGranularity` 缺口本轮不碰。C 解决的是**消息身份**，不是流式粒度——把这个缺口显式写进 evidence，别让它随 C 一起"看起来解决了"。

### ② 查证并修订阅竞态

评审指出：`OpenclawGatewayKernelClient.subscribe`（`:391-422`）先返回 stream、再由**未 await 的 `Task`** 发订阅 RPC；`SessionStore.swift:97-103` 也未等待消费任务建立，UI 随后即可 send。

**这一条主会话在 0011 未独立复验**，按评审结论登记。本轮先**构造快速发送时序**证明它真会丢早期事件（或证明它不会），再决定改法。**证不出来就不改**——不接受「看起来危险所以改一改」。

### ③ 把空的 seq 断言换成真能证伪丢帧的检查

**已核实的事实**：
- `nextSeq()`（`OpenclawGatewayKernelClient.swift:825-833`）是 kernel-client **自己的本地计数器**（`seqByRunID[runID] ?? 0) + 1`），结构上不可能倒退。现有「seq 单调」断言对丢帧一无所证。
- **openclaw 的 wire 帧自带 `payload.seq`**——而 `payload["seq"]` 在整个 kernel-client 里被读取 **0 次**（五个 `.swift` 文件 grep 全为 0）。服务端序号被完整丢弃。
- rounds/0011 成功那次的 wire seq 实测为 **`1,2,3,4,6,7,10`——缺 5、8、9**。

**本轮要求**：让检查建立在 **wire `seq`** 上而非本地计数器。**并且必须先查清那些缺口是什么**——可能是真丢帧，也可能是 seq 作用域比本订阅更宽（例如含未投递给本订阅者的事件）。**两种解释导出完全不同的断言**，不许在没查清前二选一。

**破坏性反证是硬要求**：断言写完后必须人为丢弃一帧，确认它**变红**。做不到就说明这条断言和被它取代的那条一样空。

### ④ 补 recipe 文末遗漏

`app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 的「回主会话摘要」节（`:250-251`）那条供复制的一行命令**仍然缺 `OPENCLAW_WORKSPACE_DIR`**，至今能复现已知越界。rounds/0011 修了 §1 却漏了这里。

**同时**：全文再扫一遍还有没有第三处（`grep -n OPENCLAW_STATE_DIR` 逐条比对）——**这次不靠人眼一处一处记**。

### ⑤ 从全新隔离目录重跑，把 UI 证据与原始日志落进 evidence

rounds/0011 的 evidence 目录 `video=0, raw_log=0`，而 scope-lock 自己写的是「**录屏**可见」。CLI 断言输出、openclaw 日志、D3-proxy 日志全留在 gitignored scratchpad——**换个会话就复核不了**。

**本轮要求**：
- ~~**录屏**（不是截图）落进 `rounds/0012/evidence/`~~ → **2026-08-09 user-confirmed 修订：L1 用截图 + wire trace，录屏不作要求**（理由与时序说明见 `setup/data-sources.md` 的 2026-08-09 注）。**录屏改为 L2 的硬要求**——流式渲染是时间行为，静态截图原理上拍不到。
- openclaw / D3-proxy / CLI 三侧**原始日志**落进 evidence，且能按时段 / PID / runID 相互关联
- 隔离审计要覆盖 **wrapper PID 与其 descendant**（0011 只查了 gateway PID，漏了 wrapper），以及**瞬时访问**（单次 `lsof` 只覆盖采样瞬间）
- recipe 自承不受 `OPENCLAW_STATE_DIR` 控制的 `/tmp/openclaw/openclaw-<date>.log` 也要纳入审计视野

**日志脱敏**：原始日志入 evidence 前必须过 `./scripts/check-secrets.sh`。本仓是 PUBLIC。

### ⑥ 给出无秘密的可复现步骤

rounds/0011 收尾把 `app/server/.env` 还原了，当前仓库状态下**无法直接复现成功往返**，与 round objective 的「能复现」冲突。

两条路二选一（本轮内定，不预设）：
- 真实建立 session→newapi 映射（**注意：这要写 Pi 的 Postgres，属 `write-safety-required`，未获授权前不得执行**）
- 或把 aggregate 冻结成一个有**完整、无秘密**重放步骤的 L1 测试 profile（秘密由外部注入，步骤与非秘密配置必须齐全）

## 驱动模型

写码派 claude-sonnet-5 子代理（**必须显式传 `effort: "xhigh"`**）；主会话独立复验并亲跑重取证据。**scope-lock / 验收判定不委派**。★审查闸（hopper，**换 grok**——0011 是 codex，轮换以免同源盲区）。收敛守卫：第 3 个 MUST-FIX → checkpoint。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/kernel-client/swift/` | 改 | 仅①②③涉及的分组/竞态/seq 三处；**不得动 D1/D2 契约语义**（协议签名、帧格式、映射语义） |
| `app/apps/AgentShell/` | 改 | 仅①②涉及的 UI 侧分组与订阅时序 |
| `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` | 改 | ④ |
| `app/server/.env`（gitignored） | 改 | ⑥ 若选 aggregate profile 路线；沿用 2026-08-05 user-confirmed 授权，落在预授权表 `d3proxy` 行内 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0012/` | 写 | evidence（**截图 + 三侧原始日志 + wire trace + 隔离审计**；录屏已于 2026-08-09 改为 L2 要求）+ RAE 台账 + round 收口 |
| `.harnessloop/state/`、`goal-breakdown.md` | 改 | 状态指针与 SG-10 行状态 |
| `.hopper/` | 写 | ★审查闸 |
| 隔离 openclaw 实例、本机 D3-proxy | 起/停 | 预授权 test-resource；**全新隔离目录，不复用 0011 的** |

## Disallowed Changes

- **L2/L3 任何功能**：流式渲染精细化、stop 按钮、审批五态 UI、成本/用量面板、能力开关。
- 改 D1/D2/D5 契约语义；改 `app/generated/`（codegen 产物）。
  > **2026-08-08 定向解除（user-confirmed，走 C）**：本行的两项禁止**仅对以下一件事解除**——为 `MessageDeltaEventMessagePayload` 新增**一个可选的消息标识字段**，途径必须是「改 `app/contracts/d2/` 的 schema 源 → 跑既有 codegen → 产物随之更新」。**手改 `app/generated/` 下任何文件仍然禁止**；D5 契约、`KernelClient` 7 方法签名、既有字段的语义/类型/必选性、`EventMapping` 既有映射行为，**一律仍在禁止之列**。完整解除表与硬要求见 §①'。
- **写 Pi 的 Postgres 或任何 `raspberry-pi-deploy` 上的资源**——`write-safety-required`，本轮未获授权，撞上即停下问用户。
- 改三插件 submodule；引入 `.xcodeproj`；建 XCUITest。
- 凭证进任何 tracked 文件。
- **在未查清机制的情况下按推断改代码**（针对①③，见各条正文）。

## One-Variable Strict Mode

- Enabled: no（六项限定修复，彼此独立，不是同一变量的对照实验）。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 基线不破 | `swift build --package-path app` 通过；帧回放 **30/30 PASS** | 构建 + 测试输出 |
| CI 三条 Swift 步骤 | `typecheck:swift` / `verify:swift` / flat-swiftc 平价 runner **12/0/1** 均不变 | 逐条实跑输出 |
| ① 分组 | 先给出**机制定位**（wire 帧 + 代码 file:line），再给出修法；修后同一注入场景**不再重复拼接** | 定位记录 + 修后截图 + wire trace |
| ② 竞态 | 快速发送时序下**能否复现丢帧**的明确结论（是/否，附构造方法） | 复现记录 |
| ③ seq | 基于 wire `seq` 的检查 + **人为丢帧后该检查变红** | 断言输出 + 破坏性反证 |
| ③ 缺口成因 | `1,2,3,4,6,7,10` 缺 5/8/9 的**明确解释**（真丢帧 vs 作用域更宽） | 分析记录 |
| ④ recipe | 全文 `grep -n OPENCLAW_STATE_DIR` 逐条比对，**每处都有 `OPENCLAW_WORKSPACE_DIR` 或明确说明为何不需要** | grep 输出 |
| ⑤ 证据自足 | evidence 内 `video≥1`、三侧 `raw_log≥1` 且可按时段/PID/runID 关联；过 `check-secrets.sh` | 文件清单 |
| ⑤ 隔离审计 | 覆盖 wrapper PID + descendant + 瞬时访问 + `/tmp/openclaw/` | 审计记录 |
| ⑥ 可复现 | 给出无秘密的完整重放步骤，**由主会话照步骤实跑一次验证** | 步骤文档 + 实跑记录 |
| ★审查闸 | PASS / PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits

- Recovery：定位失败 / 修后仍复现 → 诊断迭代（runtime-recoverable），可反复起停隔离实例。（原列的「录屏权限受阻」已不适用——2026-08-09 起 L1 不要求录屏。）
- Cleanup：隔离实例用完即停；`.env` 若改动，收尾**要么还原、要么把当前态明确写进证据**——不留「还原了但没说」这种既不可复现也无记录的中间状态（这正是 0011 的教训之一）。
- **删除非本轮新建的任何东西不在预授权内。**

## Rollback Condition

- ①③ 若查清机制后发现**必须动 D1/D2 契约语义**才能修 → 该项停下记 blocker，归独立设计轮，其余项照常收口。
- ② 若证不出竞态会丢帧 → **不改**，如实记录「未能复现」，不做无证据的防御性修改。
- ⑥ 若两条路都走不通 → 如实记录「成功路径仍不可复现」，本轮不得判 RAE-0001 pass。

## Human Confirmation Required

- 自动化 + ★审查闸：既定授权。
- **写 Pi 的 Postgres（⑥ 的第一条路）**：`write-safety-required`，需用户显式授权，未授权不得执行。
- ~~**录屏**：macOS 屏幕录制需要系统权限授权……~~ → **本轮已撞上（三次尝试均不产出 `.mov`，进程收 SIGINT 亦不退），已按此条停下说明、未绕过**；随后 user-confirmed 2026-08-09 把录屏改为 **L2** 要求，L1 用截图 + wire trace。届时 L2 做录屏仍需先放行该权限。
- 证据产出后**呈交用户过目**：scope-lock 明定 UI 层人工验收的「人」是用户。

## 本轮自身的纪律要求（针对 0011 暴露的问题）

1. **不得把未查清的机制写成已知根因**（①③ 明文要求先定位后动手）。
2. **不得无新证据改判任何条件的达成状态**——0011 把条件③从「部分」改成「达成」而中间没加任何断言，这次每一次状态提升都要指向具体新增证据。
3. **不得用「没坏过」当反证**——③ 的破坏性反证是硬要求。
4. **按自己写的字面标准验**——写「全程」就按全程验；标准若不合适，**先改 scope-lock 再执行**，不在验收时放宽解释。
   > 2026-08-09 的录屏修订正是走这条：显式改契约（并如实登记「在失败之后才提议放宽」这个不好看的时序），而**不是**在验收时把「录屏」解释成「截图也算」。两者的区别就是这一轮要守的东西。
