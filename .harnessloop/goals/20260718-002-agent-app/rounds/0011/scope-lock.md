# Scope Lock — rounds/0011

## Round Objective

**SG-10 L1 — Mac UI 壳最小可见 app（主线，第二批第二轮）**：起一个原生 macOS SwiftUI 壳，做到**窗口 + 会话列表 + 新建会话 + 消息流渲染**四件事，并对**隔离 openclaw 实例**完成一次真实会话往返。消费既有 `app/kernel-client/swift/`（8 个 `.swift`，当前靠裸 `swiftc` 编译）与 D5 产品规格。

**本轮不做**：流式渲染细节、stop、审批五态 UI（归 L2）；成本/用量面板与能力开关（归 L3）。L1 只要求「看得见、连得通、能复现」。

### 本轮裁定的两处遗留「待定」（user-confirmed 2026-08-05，AskUserQuestion）

`goal-breakdown.md` SG-10 行写的是「风险：UI 自动化验收方法待定，**首轮 scope-lock 时定**」，`data-sources.md` 的 RAE-0001 Pass 栏写的是「**TBD —— 首轮 scope-lock 时定**」。本轮即那个「首轮」，两处于此定案：

**① UI 验收方法 = 分层，不建 XCUITest**

| 层 | 手段 | 产出 |
|---|---|---|
| 逻辑层（kernel-client / 事件流） | 自动化断言，沿用既有 `swiftc` + `FrameReplayTests.swift` 的做法 | e2e 日志（事件序列） |
| UI 层（窗口/列表/消息流） | 真跑 app 录屏 + 关键截图，人工验收 | 录屏 + 截图 |

与 SG-10 证据列既有写法（「真实 app 运行录屏/截图 + e2e 日志」）一致。**代价已知并接受：UI 层本轮无回归保护**——L2 引入审批五态时若发现人工验收撑不住，届时再评估是否升级到 XCUITest，不在本轮预先建设。

**② RAE-0001 Pass 条件 = 以下四条全部成立**（缺一即 fail，不接受「三条过了算过」）

| # | 条件 | 判定依据 |
|---|---|---|
| 1 | 真实往返可见 | 隔离实例起得来 → 新建会话 → 发一条消息 → **UI 里渲染出 assistant 回复**（录屏可见） |
| 2 | 隔离性可证 | 全程未触碰用户环境既有 openclaw 状态目录与 gateway，**前后比对留证**。<br>**2026-08-05 实测修正**：原定的「整树 `stat` 指纹前后比对」被证**不可用**——`~/.openclaw` 有一个并发第三方写者（用户自己的常驻 gateway，`lsof` 坐实其持有 `logs/gateway.log` 等），指纹变化无法归因。改用**正面归因**：本轮实例 PID 在 `~/.openclaw` 下打开文件数为 0 + 本轮全部 session/run id 在该树命中数为 0 + 会话产物全落隔离目录。这组证据比「全局树没变过」更强 |
| 3 | 事件序列与契约一致 | 消息流事件序列符合 kernel-client 契约：**无丢帧、无乱序**，由 e2e 日志断言，不靠肉眼看录屏 |
| 4 | 失败可诊断 | 失败时日志足以定位到 UI / kernel-client / gateway **哪一层**，而不是只得到「没出来」 |

条件 2 不是锦上添花：`OPENCLAW-ISOLATED-RUN-RECIPE.md` 存在的全部理由就是隔离，不证等于 recipe 白写。条件 4 是把「失败也要是有信息的失败」写进验收，避免本轮真失败时只剩一句无法归因的结论。

## 驱动模型

写码派 claude-sonnet-5 子代理（**必须显式传 `effort: "xhigh"`**，见 `state/environment.md`：effort 结构上不可验证，只能靠每次显式传参 + 声明）；主会话独立复验（读代码 + 亲自跑一次往返 + 核对四条 Pass 条件）。**scope-lock / goal-breakdown / 验收判定不委派**（`$harnessloop-delegation` 安全规则明文禁止）。★审查闸（hopper，codex/grok 随机）：L1 代码忠实性 + 四条 Pass 条件是否真被证据支撑（而非被声明支撑）。收敛守卫：第 3 个 MUST-FIX → checkpoint。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `app/apps/`（当前为空目录） | 建 | Mac 壳落点；L1 范围内的 SwiftUI 源码与构建脚本 |
| `app/kernel-client/swift/` | 改 | **仅为让壳能消费而做的结构调整**（如拆库/加 Package.swift）；不改帧映射与协议语义 |
| `app/kernel-client/RUN-EVIDENCE.md` | 改 | 若构建方式变更，同步更新其中记录的 `swiftc` 复现命令——不得留下跑不通的历史命令 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0011/` | 写 | evidence（录屏/截图/e2e 日志/隔离性比对）+ `evidence/runtime/acceptance-evals.json` 台账 + round 收口 |
| `.harnessloop/setup/data-sources.md`、`goals/.../goal-breakdown.md`、`state/current.md` | 改 | 仅回填本轮定案的两处「待定」与状态指针 |
| `.hopper/` | 写 | ★审查闸派发与产物 |
| 隔离 openclaw 实例（`openclaw-isolated`） | 起/停 | 按 recipe 起独立实例；属 `control-contract.md` 已预授权的 test-resource 写 |
| `app/server/.env`（gitignored） | 改 | **2026-08-05 user-confirmed 扩入**：设 `SESSION_PROXY_UNMAPPED_SESSION_POLICY=aggregate` + `SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY`（复用既有 `NEWAPI_D3PROXY_TOKEN`，不铸新 token）。落在预授权表 `d3proxy` 行「本机实例与其 gitignored `.env`」内，**零 Pi 写入** |
| `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` | 改 | **2026-08-05 user-confirmed 扩入**：补 `OPENCLAW_WORKSPACE_DIR`，并标明原「只设 `OPENCLAW_STATE_DIR` 已足够」声明的作用域限制（该声明在 SG-4 defer 掉 send 的前提下成立，一旦真 send 即失效） |

**构建方式 —— 已 user-confirmed（2026-08-05）：SwiftPM + 手工组装 `.app` bundle**。原为显式假设（依据是验收法预览里的「新建 Xcode 工程：否」），开工前已向用户点明「若本意仅指不建 XCUITest target、app 本体仍可用 `.xcodeproj`，现在改成本最低」，用户明确答复「按 SwiftPM 推」。**本轮不引入任何 `.xcodeproj`**；与现有裸 `swiftc` 的无-IDE 风格一致，且不需要 GUI session 即可构建。

## Disallowed Changes

- 建 XCUITest target 或为 UI 自动化引入 `.xcodeproj`（本轮裁定不做；要做需改本 scope-lock）。
- L2/L3 范围：流式渲染、stop、审批五态 UI、成本/用量面板、能力开关。
- 改 D1/D2/D5 契约文本语义；改 kernel-client 的帧映射/协议行为（结构调整 ≠ 语义变更；若发现必须动语义才能跑通 → 停下记 blocker）。
- 触碰用户环境既有 openclaw 状态目录与 gateway（这正是 Pass 条件 2 要证伪的事）。
- 改三插件（`harnessloop/`、`hopper-plugin/`、`kata/`）。
- 凭证进任何文件（evidence 引用一律脱敏；隔离实例的 `OPENCLAW_GATEWAY_TOKEN` 是进程内自生成值，也不落库）。

## One-Variable Strict Mode

- Enabled: no（L1 是从零起壳，天然多文件多变量；单变量约束在此不可执行，硬套只会变成形式主义）。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 构建 | 壳可构建产出可运行 `.app`（或等价可执行） | 构建日志 |
| 既有帧回放断言 | **仍全绿**——结构调整不得打断既有断言 | e2e 日志 |
| RAE-0001 ①真实往返 | UI 渲染出 assistant 回复 | 录屏 + 截图 |
| RAE-0001 ②隔离性 | 用户既有 openclaw 状态目录/gateway 前后无变化 | 前后比对留证 |
| RAE-0001 ③事件序列 | 无丢帧、无乱序，符合 kernel-client 契约 | e2e 日志断言 |
| RAE-0001 ④失败可诊断 | 注入一次人为失败，日志能定位到层 | 诊断性反证记录 |
| RAE 台账 | `evidence/runtime/acceptance-evals.json` 含 RAE-0001，`frozen_system` = `openclaw-isolated` | 台账文件 |
| ★审查闸 | PASS/CONFIRMABLE | `.hopper/handoffs/` |

条件 ④ 用**反证**验：不是等它恰好失败，而是主动注入一次失败（如指向错端口）看日志是否真能定位到层。「没坏过所以可诊断」不算证据——这是本项目一贯的「破坏性反证」纪律。

## Runtime Recovery Limits

- Recovery：构建失败 / 往返不通 / 事件序列不符 → 诊断迭代（runtime-recoverable），可在本轮内反复起停隔离实例。
- Cleanup：隔离实例用完即停；`OPENCLAW_STATE_DIR` 是本轮新建的临时目录，属预授权 test-resource 范围。**删除既有资源不在预授权内**（`control-contract.md` 的预授权表只含 `test-resource-create`，无 delete/cleanup 行）——若确需删除任何非本轮新建的东西，停下问用户。

## Rollback Condition

四条 Pass 条件缺任一 → 本轮不得判 positive。若失败原因指向 kernel-client 契约本身而非壳（即必须动协议语义才能跑通）→ 该项停下记 blocker，归 SG-12 或独立设计轮，L1 其余部分照常收口并如实标注「往返未达成」。若 kernel-client 结构调整打断了既有帧回放断言且短期修不回 → 回滚结构调整，L1 改用不动 kernel-client 的接法。

## Human Confirmation Required

- 自动化 + ★审查闸：既定授权。
- UI 层为人工验收，**录屏/截图由主会话产出并呈交用户过目**——人工验收的「人」是用户，不是我自己看一眼就算过。
- 构建方式假设（SwiftPM vs `.xcodeproj`，见 Allowed Changes 末尾）：若与用户本意不符，开工前提出即改。

---

## 后记（2026-08-09，取证方式修订，user-confirmed）

本文件条件① 写的是「UI 里渲染出 assistant 回复（**录屏可见**）」。**该要求已修订：L1 用截图 + wire trace，录屏改为 L2 硬要求。**

**本轮不改写**（已收盘轮次是历史记录），此处仅登记指向：权威落点是 `setup/data-sources.md` 的 2026-08-09 注，含完整理由与一句不好看的时序说明——**修订发生在 rounds/0012 尝试录屏失败之后**。

**溯源**：「录屏」这个收紧是主会话起草 AskUserQuestion 选项时自己加的。`goal-breakdown.md` 定义 SG-10 时写的是「真实 app 运行**录屏/截图**」——**斜杠、二选一**。用户选的是那个选项，但把二选一变成两者都要，是起草失误，非用户裁决。
