# Scope Lock — rounds/0014

## Round Objective

**用户 2026-08-11 裁决 rounds/0013 的 Human Decision 第 1 项：「做 1，开一轮修会话持久化」。**

本轮只做这一件事：**让 mac 壳在重启后仍能看到并继续之前的会话**。这是 rounds/0013 D 探查
认定的、「基本使用」的**唯一阻断**。

## 已查清的机制（开工前完成，不是推断）

| 事实 | 出处 |
|---|---|
| `SessionStore.sessions` 是**纯内存数组**，启动只 connect，无任何恢复路径 | `SessionStore.swift:43-47`、`ContentView.swift:24-29` |
| 重启后的壳**连 wire trace 都不产生** —— 从不尝试拉取已有会话 | rounds/0013 `evidence/live/raw/d3-restart-transcript.txt` |
| 数据**没丢**：内核库 `sessions` 表 5 行，history 可查且 `(messageId, messageSeq)` 与实时帧同源同键 | rounds/0013 `evidence/itemC-rae0001-live.md` |
| **D1 `KernelClient` 的 7 个方法里没有一个能列会话或取历史** | `KernelClient.swift:82-100` |
| openclaw 侧有 `sessions.list` / `sessions.get` / `sessions.resolve`；history 另有已验通的 HTTP 路由 `GET /sessions/<key>/history` | `server-methods/*.ts`；rounds/0013 live 验证（无 token→401，错 key→404） |
| `SessionHandle` 是 `Codable`，可直接持久化（`billing`/`createdAt`/`kernel`/`kernelSessionID`/`sessionID`） | `app/generated/swift/D2.swift:3842-3855` |
| **但 history 需要的 openclaw `key` 存在适配器的私有 `kernelKeyBySessionID` 里**，重启即丢——光存 handle 不够 | `OpenclawGatewayKernelClient.swift:52` |
| `kernelSessionID` ≠ history 的 `key`（两个独立字段，用错会查到不存在的会话） | rounds/0013 已实证 |

## 架构约束（本轮的核心红线）

**不得修改 D1 `KernelClient` 协议既有的 7 个方法签名。** 它们有三语言 codegen、fixtures 与
CI 平价 runner 绑定；rounds/0012 有过「改 `subscribe()` 语义导致 fixtures 12/0/1 → 4/8/1」的先例。

**允许的做法**：新增一个**可选的、加法式的**能力协议（例如
`SessionRestoring` / `SessionHistoryProviding`），由 `OpenclawGatewayKernelClient` 遵循，
`SessionStore` 在对方支持时使用。**新增协议 ≠ 改 D1 七法**。

**若发现不动 D1 七法就做不成** → **停下记 blocker，归设计轮**，不硬来。

## 四块工作

### A. 会话清单持久化

壳自己记住它创建过的会话（至少：`SessionHandle` + openclaw `key` + 标题 + 创建时间），
重启后恢复列表。落点自定（`Application Support` 下的文件或等价物），但要：
- **可被删除/重置**，不得让坏数据永久卡死壳
- **不落任何凭证**（endpoint/token 仍走环境变量）

### B. 适配器状态重建

恢复的会话必须能重新参与 `send` / `subscribe` / `stop`——即适配器的
`kernelKeyBySessionID` 等必要映射要能被重新播种。**这是 A 之外必须单独做的一步**（见上表）。

### C. 消息历史恢复

恢复的会话要能显示之前的消息。通路二选一，**认准 `key` 不是 `sessionId`**，
并**必须真的翻页**——rounds/0013 的对账加固已证明「只读第一页」是真实的漏数据路径。

> **2026-08-11 中途更正（两处，主会话已逐条核实）**
>
> **(1) 通路：本节初稿写死「复用 rounds/0013 已验通的 HTTP 通路」，而主会话发给实现方的
> brief 写的是「通路你自己选，建议优先 WS 上的 `chat.history` RPC」——两份文件不一致。**
> 实现按 brief 选了 WS RPC，理由是复用既有已鉴权的 WS 连接、不引入第二套 HTTP+bearer 客户端，
> 且与 B/D 的「恢复这个会话」同流程。**该理由成立，此处按纪律第 4 条显式放宽本节措辞，
> 而非在验收时放宽解释。** 代价已知并记录：WS RPC 此前只做过源码验证，HTTP 那条才是 live 验通的
> ——**因此本轮的 live 验收必须实际跑通 WS 通路**，不能只靠单元测试。
>
> **(2) 分页字段：本节初稿与主会话的 brief 都写「`hasMore`/`nextCursor`」——引错了实现。**
> openclaw 里有**两套不同的 history 分页**：
> - **WS `chat.history` RPC**：`hasMore` + **`nextOffset`（数字偏移）**（`server-methods/chat-history-handler.ts:494-585`）
> - `session-history-state.ts:32-33,105-112`：**`nextCursor`（字符串游标）**，服务另一条通路
>
> 实现按 `nextOffset` 真实契约做分页是**正确的**，不是偏离。
> **记此一笔**：我在开轮时把 file:line 钉到了错误的实现上——两套实现字段名不同，
> 只看一处就下结论会把实现带偏。这属于「先查清机制」这一步没做透。

### D. 重新订阅

恢复的会话要重新接上事件流，之后的新消息能正常到达（不能只是只读的历史快照）。

## 本轮不做

- **exec 策略** —— 用户已于 2026-08-11 裁定：**直接把 `ask` + 审批 UI 提前做**（不走 allowlist 过渡）。**但不在本轮做**：0014 已聚焦会话持久化且接近完成，审批工作量独立且需先闭合 `respondApproval` RPC（现为桩，直接开 `ask` 会让会话挂到 30 分钟超时）。**排在 0014 之后单开一轮。**
- L2 其余项：stop 按钮、审批五态 UI、流式渲染精细化、成本面板。
- **rounds/0013 遗留的 Q3「收窄 `AgentShellCore` 的 public 暴露面」** —— 属重构建议；
  若本轮改动天然触及可顺带收窄，**但不得为此单独开工**。
- 改 `app/contracts/`（含 fixtures）、`app/generated/`、`kernels/`、三插件 submodule。

## 驱动模型

写码派 claude-sonnet-5 子代理（**必须显式传 `effort: "xhigh"`**）；主会话独立复验并亲跑重启验收。
**scope-lock / 验收判定不委派。** ★审查闸（hopper，**换 grok**——0013 是 codex 且连派两轮）。
收敛守卫：第 3 个 MUST-FIX → checkpoint。

**派 hopper 时注意**：queue.md 的 brief 在任务无 `leader-tasklist.md` 条目时**会被静默丢弃**
（rounds/0013 实证的 hopper 缺陷，未修）——**用 `--adhoc --brief` 通道**，或先在 leader-tasklist 里补条目。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/apps/AgentShell/` | 改 | A/B/C/D 四块的壳侧实现与本地存储 |
| `app/kernel-client/swift/` | 改 | **仅**新增加法式能力协议与其 openclaw 实现、必要的映射重建入口；**不改 D1 七法签名、不改帧映射语义** |
| `app/Package.swift` | 改 | 仅当新增 target/依赖确有必要 |
| `app/apps/AgentShell/repro/` | 改 | 复现步骤与对账工具随本轮变化同步 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0014/` | 写 | evidence + RAE 台账 + 收口 |
| `.harnessloop/state/`、`goal-breakdown.md` | 改 | 状态指针与 SG-10 行 |
| `docs/validation-log.md` | 改 | 收盘条目与插件缺陷条目（`CLAUDE.md` 沉淀钩子要求） |
| `~/.llm-wiki/test-harnessloop` | 写 | 若产生跨轮复用的内核/工具事实（kata 主场） |
| `.hopper/` | 写 | ★审查闸 |
| 隔离 openclaw 实例 | 起/停 | 预授权 test-resource；用 `repro/` 三件套，`L1_ROOT` 指向 scratchpad |

## Disallowed Changes

- **改 D1 `KernelClient` 七法签名**、改帧映射/协议语义、手改 `app/generated/`、改 `app/contracts/`。
- 改 `kernels/`、`app/server/`、`app/deploy/`、`app/parity/`、三插件 submodule。
  > **2026-08-11 user-confirmed 例外（仅一项）**：用户裁定「只授权在 hopper-plugin 内开 issue，修留独立轮」。故**允许**在 `hopper-plugin/` 内**新建一个 ISSUE markdown 文件**记录 brief-drop 缺陷；**不得改其代码、不得 bump 版本、不得 push**。除此之外三插件 submodule 仍全面禁改。
- **写 Pi 的 Postgres 或任何 `raspberry-pi-deploy` 资源** —— `write-safety-required`，未授权。
- 凭证进任何 tracked 文件（含 evidence 原件）。
- 在未查清机制的情况下按推断改代码。

## One-Variable Strict Mode

- Enabled: no（A/B/C/D 四块彼此耦合，单变量在此不可执行）。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 基线不破 | `swift build --package-path app` 通过；帧回放 **≥41/41** | 构建 + 测试输出 |
| CI 平价 runner | **12 PASS / 0 FAIL / 1 DEGRADED**（硬判据） | 逐字复现 `ci.yml:145-155` |
| D1 契约未动 | `KernelClient.swift` 七法签名逐字未变 | diff |
| 三端 codegen 校验 | `typecheck:swift`/`verify:swift`/`verify:type-fidelity-swift`/TS runner 全绿 | 逐条实跑 |
| **重启恢复（主判据）** | 建 ≥2 个会话各发数条消息 → 退出 app → 重启 → **两个会话都在列表里，且各自的历史消息都在** | 截图 + 冻结原件 |
| **恢复后可继续用** | 恢复的会话能再发一条并收到回复（证明 B/D 真的接上了） | wire trace + 截图 |
| **破坏性反证** | 删掉/损坏本地持久化文件 → 壳**不得崩溃**，应回到空列表并可继续新建 | 反证记录 |
| **翻页反证** | 构造 `hasMore: true` 的历史 → 恢复逻辑**必须翻页**，不得只取第一页 | 反证记录 |
| RAE-0001 不回归 | 重跑仍 pass | `evidence/runtime/acceptance-evals.json` |
| ★审查闸 | PASS / PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits

- Recovery：恢复不通 / 映射重建失败 / 翻页对不上 → 诊断迭代（runtime-recoverable）。
- Cleanup：隔离实例用 `repro/stop-isolated-kernel.sh` 收；**删除非本轮新建的东西不在预授权内**。

## Rollback Condition

- **若必须改 D1 七法签名才能做成** → 停下记 blocker，归设计轮，本轮如实标注「未达成」。
- 若本地持久化引入崩溃/坏数据卡死且短期修不回 → 回滚该部分，如实记录。

## Human Confirmation Required

- 自动化 + ★审查闸：既定授权。
- **UI 层人工验收的「人」是用户** —— 重启前后的截图须呈交过目。
- rounds/0013 未裁决的四项（exec 策略 / 是否需第三轮评审 / kata `deepseek` tag / hopper 缺陷是否授权修）
  **本轮不代为决定**。

## 本轮纪律（承接 0011/0012/0013）

1. **不得在未查清机制时按推断改代码。**
2. **每次状态提升要指向新增证据**，不得无证据改判。
3. **破坏性反证是硬要求，且必须先看到红**，并**打印出实际被破坏的内容**——0012 两次、0013 一次
   都栽在「破坏没生效却读成没问题」。
4. **按自己写的字面标准验**；标准不合适先改 scope-lock，不在验收时放宽解释。
5. **「我没找到」不等于「不存在」** —— 0012 三次、0013 一次（`head -10` 截断）。凡要下
   「没有/做不到」结论，先换一个搜索维度。
6. **证据必须当场冻结进 `rounds/0014/evidence/`，不许留在 scratchpad 里靠转述**
   —— 这是 rounds/0011 与 0013 **两次**栽在同一处的教训，0013 由 ★审查闸抓出。
