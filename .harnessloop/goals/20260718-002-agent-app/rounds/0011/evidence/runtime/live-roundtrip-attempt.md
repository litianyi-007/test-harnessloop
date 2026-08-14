# rounds/0011 真实往返尝试 —— 实测记录（主会话亲跑）

日期：2026-08-05。执行者 = 主会话（非子代理）。

**结论先行（2026-08-05 收束后）：四条 Pass 条件全部达成。** 本文件 §1–§7 记录的是达成之前的完整过程（含一次阻断与用户裁决），§9 起是裁决后的收束。过程不删——阻断怎么被识别、怎么被绕过（而非被无视）本身就是证据。

## 1. 链路与进程

```
AgentShell / kernel-client-cli
  → 隔离 openclaw gateway  ws://127.0.0.1:18899
    → provider d3proxy (openclaw.json，api=openai-completions)
      → D3-proxy  http://127.0.0.1:3001  (app/server dist)
        → Pi new-api 10.244.132.76:3000 + Pi Postgres 10.244.132.76:5432
          → 上游模型 kimi-for-coding
```

| 端口 | PID | 归属 |
|---|---|---|
| 3001 | 25658 | D3-proxy（本轮新起） |
| 18899 | 29003 | 隔离 openclaw（本轮新起，wrapper 28765） |
| **18789** | **29071** | **用户全局 gateway —— 全程未动，前后一致** |

隔离目录：`scratchpad/round0011-openclaw-iso/`（gitignored），本轮全新创建，未复用 rounds/0009 的 `openclaw-iso3`。

## 2. 发现①：recipe 的隔离声明在 send 场景下不成立

**首次启动只设了 `OPENCLAW_STATE_DIR`**（严格照 `OPENCLAW-ISOLATED-RUN-RECIPE.md` §1 的说法）。`createSession`/`subscribe`/`stop` 全部正常，但一 `send` 就失败：

```
"errorMessage": "Error: Legacy workspace setup state requires migration for
                 /Users/litianyi/.openclaw/workspace; run openclaw doctor --fix."
```

隔离实例**解析到了用户全局的 `~/.openclaw/workspace`**。

recipe §1 的原话是：

> **只设 `OPENCLAW_STATE_DIR` 已经足够隔离本任务需要的 state/config/oauth**，更简单、副作用面更小，本轮就是只设了这一个就跑通的。

这句话在 SG-4 的范围内是真的——**SG-4 的 §4 明确把 `send` defer 掉了**。但一旦真的 send，workspace 解析就会伸向全局路径，该声明即失效。rounds/0009 的证据里其实写了它额外设了 `OPENCLAW_WORKSPACE_DIR`，但 recipe 从未据此更新。

**性质**：一个作用域受限的结论，读起来像通用结论。与本项目反复遇到的同一类问题同形（「清单会过时，发现式守卫不会」）。

**处置**：补 `OPENCLAW_WORKSPACE_DIR` 后重启即通。**recipe 文件本身未改**——`app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 不在本轮 scope-lock 的 Allowed Changes 内，不擅自越界，留待用户裁决。

## 3. 条件②（隔离性可证）—— 达成，但证明方法换过

### 3.1 原方法被证不可用

原设计是「起服务前后各采一次 `~/.openclaw` 整树 `stat` 指纹，比对是否一致」。实测：

| 时点 | file_count | tree_digest |
|---|---|---|
| 起服务前 | 493 | `7fda8f62c4ec88f3…` |
| 两次往返后 | 493 | `4d24279c4f737a19…` |

**指纹变了**。追下去发现变的是 `logs/gateway.log`、`logs/gateway.err.log`、`agents/main/sessions/sessions.json`、`agents/main/sessions/63da95f3-….jsonl`，时间戳 **15:58:31-32**——而我最后一次跑批 15:56:31 就结束了，且 `63da95f3` 不是我任何一次的 session。

`lsof -p 29071` 确认：**用户自己的常驻 gateway 正持有并写入 `logs/gateway.log`、`logs/gateway.err.log`、`openclaw.json`**。

**方法学结论：整树指纹法对本场景无效**——目标目录有一个并发的第三方写者（用户自己的 gateway），指纹变化无法归因。这是我自己证据设计上的缺陷，不是隔离本身的问题。如实登记，不用"大概是用户自己写的"含糊过去。

### 3.2 改用正面归因，结论成立

| 检查 | 结果 |
|---|---|
| 我的隔离实例 PID 29003 在 `~/.openclaw` 下的打开文件 | **0 个**（`lsof -p 29003`） |
| 我的 4 个 session/run id（`415817b5`/`8c3a667e`/`372dbb43`/`1dab7dd3`）在 `~/.openclaw` 下的命中 | **全部 0** |
| 我的 session 产物落点 | 全在 `scratchpad/round0011-openclaw-iso/state/agents/main/sessions/` |
| 隔离 workspace | 25 个文件，确被使用 |
| 用户全局 gateway | PID 29071 前后一致，端口 18789 未受扰 |

**条件② 达成**，且这组正面证据比整树指纹更强：它证明的是「我的数据全在隔离区、我的进程没开过全局文件、我的 id 一个都没出现在全局树里」，而不是「全局树没变过」。

## 4. 条件③（事件序列与契约一致）—— CLI 层达成

补齐 `OPENCLAW_WORKSPACE_DIR` 后的跑批（`kernel-client-cli`，exit 0），断言模式输出：

```
=== [断言模式] 字段级不变量校验（共 5 条事件） ===
  [PASS] seq 单调：所有 run/session 作用域内 seq 严格递增，无倒退/重复（2 个作用域）
  [PASS] runId 一致：所有携带 runId 的事件均为期望值 1dab7dd3-f03a-47e1-802c-c37a337396e4
  [PASS] turnComplete 唯一：run=1dab7dd3-… 恰好 1 条
  [PASS] operationCompleted 唯一且 operationId 一致：op-stop-D7A62FD2-… outcome=succeeded
  [PASS] sessionEnd 唯一：reason=stopped
  [PASS] 终态唯一（综合三项）
=== [断言模式] 结束 ===
```

对照首次（未隔离 workspace）那一跑：只有 2 条事件、`turnComplete` 0 条、两条 `[FAIL]`。同一断言集在坏环境下确实变红——**这组断言有牙齿，不是恒绿装饰**。

**条件③ 在 CLI 层达成；UI 层尚未跑**，故整体只能记为「部分」。

## 5. 条件④（失败可诊断）—— 实地达成，但不是 scope-lock 要求的那种反证

真实失败发生了，且被逐层精确归因：

| 层 | 观测 |
|---|---|
| kernel-client / 事件流 | `evt.message.delta` 内容为 `'The agent run failed before producing a reply.'`；`evt.turn_complete` 的 `stopReason=error` |
| openclaw | `502 status code (no body)` → `FailoverError` → `Embedded agent failed before reply: 502`；`model fallback decision: decision=candidate_failed` |
| **D3-proxy（根因）** | `session-proxy: sessionId=8c3a667e-… 未命中 session→newapi 映射，按默认策略（reject）拒绝转发` |

**从「UI 会看到什么」到「哪一层坏了」的链条是通的**，条件④的能力实地成立。

但 scope-lock 写的验法是「**主动注入一次失败**（如指向错端口）看日志是否真能定位到层」，即人为构造的反证。本次是**自然发生的真失败**。两者都能证明诊断能力，但严格按 scope-lock 的字面要求，主动注入那一次尚未做。**不把自然失败当成已完成的反证**，记为「实地达成，反证待补」。

## 6. 条件①（真实往返可见）—— 未达成，且撞上阻断

`evt.message.delta` 的内容是 openclaw 的错误占位文本，**不是模型回复**。把它渲染进 UI 不构成「assistant 回复」。条件① **未达成**。

### 阻断分析

根因是 D3-proxy 的默认策略：session 未在 `session_newapi_tokens` 映射表里命中即 `reject`。`CLIRunner.swift:65-74,96-102` 的注释确认这是既定设计——**壳本身不做 seed，需外部先 seed**（rounds/0009 用的 `scratchpad/openclaw-iso3/seed-upsert.cjs` 现已不存在）。

要跑通条件①，需要在 **Pi 的 Postgres**（`DB_HOST=10.244.132.76`）里写一条 session→token 映射行。对照 `state/control-contract.md` 的 `Pre-Authorized Test-Resource Writes` 表：

| 表内 System id | 覆盖范围 |
|---|---|
| `newapi` | 带 `test`/`sg`/`eval` 前缀的 **token 与 channel** |
| `openclaw-isolated` | 隔离目录与指定端口上的实例 |
| `hermes-isolated` | 同上 |
| `d3proxy` | **本机** `D3PROXY_LOCAL_PORT` 上的实例与其 gitignored `.env` |

**`raspberry-pi-deploy` 不在表内**（刻意排除，生产宿主）；`d3proxy` 行只覆盖本机实例与本机 `.env`，**不覆盖远端数据库行**；`newapi` 行覆盖的是 token/channel，不是映射表。

因此该写入**不具备预授权**，按协议归类为 **`write-safety-required`**，且契约明文：「生产系统与不可逆操作在任何情况下都不具备预授权资格，无论此表写了什么」。**停下待用户裁决，未擅自写入。**

## 7. 四条件当前状态

| # | 条件 | 状态 |
|---|---|---|
| ① | 真实往返可见 | **未达成** —— 阻断于 Pi Postgres 映射行写入（`write-safety-required`） |
| ② | 隔离性可证 | **达成**（正面归因；整树指纹法被证不可用，已换法并登记） |
| ③ | 事件序列与契约一致 | **部分** —— CLI 层 6 项断言全 PASS 且经坏环境反证有牙齿；UI 层未跑 |
| ④ | 失败可诊断 | **实地达成** —— 真实失败逐层归因成功；scope-lock 要求的主动注入反证待补 |

## 8. 运行中的进程（未清理，便于裁决后立即续跑）

- D3-proxy PID 25658（:3001）
- 隔离 openclaw PID 29003（:18899），wrapper 28765
- 用户全局 gateway PID 29071（:18789）**非本轮所起，勿动**

裁决后若不继续，需 `pkill` 前两者并按 scope-lock 的 Cleanup 条款收尾（隔离目录属本轮新建的 test-resource，可留可删；**删除非本轮新建的任何东西不在预授权内**）。

---

## 9. 用户裁决与收束（2026-08-05）

阻断经 AskUserQuestion 上报，用户两项裁决：

1. **走 aggregate，不写 Pi**——改本机 `app/server/.env`（gitignored）两项：`SESSION_PROXY_UNMAPPED_SESSION_POLICY=aggregate` + `SESSION_PROXY_AGGREGATE_FALLBACK_NEWAPI_KEY`（复用既有 `NEWAPI_D3PROXY_TOKEN`，**不铸新 token**）。落在预授权表 `d3proxy` 行「本机实例与其 gitignored `.env`」内，**Pi 写入为零**。代价：本次调用计费归聚合主体、无法按 session 归因——而 per-session 归因是 SG-8.5 的验收目标（已收官），非 L1 所考。
2. **扩本轮 scope 顺手修 recipe**——`OPENCLAW-ISOLATED-RUN-RECIPE.md` 加入 Allowed Changes。

两项均已写入 `scope-lock.md`（扩范围先改契约，未先斩后奏）。

源码依据（`session-proxy.service.ts:134-180`）：`aggregate` 仍**先查映射**，未命中才用兜底 key 转发并打警告「本次调用将无法归因到具体 session」；兜底 key 未配则 fail-closed 拒绝。即它不是「关掉检查」，是「换一个明示的计费主体」。

## 10. 条件①达成 —— UI 里真实往返

D3-proxy 带 aggregate 重启后：

**CLI 层**先验（`kernel-client-cli`，exit 0）：`delta = '收到'`（模型精确执行「请只回复两个字：收到」），`stopReason = completed`，6 项断言全 PASS。D3-proxy 侧日志确认走的是 aggregate 兜底路径。

**UI 层**（条件①只认这个）：`AgentShell` 指向 `ws://127.0.0.1:18899` 启动 →

| 证据文件 | 内容 |
|---|---|
| `screens/l1-shell-connected.png` | 侧栏绿点 `已连接 (scopes: operator.admin)`——真握手 |
| `screens/l1-after-newsession.png` | 点「新建会话」后：左侧出现「会话 1」并选中，右侧标题 `会话 1  kernel=openclaw`，空态提示 + 输入框聚焦 |
| **`screens/l1-roundtrip-assistant-reply.png`** | **我：`Reply with exactly two words: ROUNDTRIP OK`** → **assistant：`ROUNDTRIP OK`**；会话列表预览同步为 `ROUNDTRIP OK` |

L1 要求的四件事（窗口 / 会话列表 / 新建会话 / 消息流渲染）+ 真实往返，全部在 UI 上可见。**条件① 达成。**

### 一处测试手段缺陷，如实登记

截图里第一条用户消息显示为 `aaaaaaaaaa`——AppleScript `keystroke` 打不出中文（10 个汉字变 10 个 a），第二次改 ASCII 又被系统中文 IME 吃掉（`ly`→旅游）。**这是我驱动 UI 的手段问题，不是 app 的缺陷**（模型确实收到并回复了）。最终改用**剪贴板粘贴**绕开 IME，才拿到干净配对的请求/回复。该失败消息保留在截图里未清场，因为清掉它等于隐藏「这次证据是怎么取到的」。

## 11. 条件④达成 —— 主动注入反证

按 scope-lock 要求主动构造失败：**在壳保持连接的状态下停掉 D3-proxy**（链路中段），再发一条消息。

UI 表现（`screens/l1-injected-failure-midchain.png`）：连接横幅**仍为绿色「已连接」**（gateway 链路完好），但消息流里该条回以 `The agent run failed before producing a reply.`。

与另一种失败**可区分**：

| 失败点 | UI 表现 | 日志签名 |
|---|---|---|
| 传输层（端口无监听） | **红** banner `连接失败：NSURLErrorDomain Code=-1004`，会话建不起来 | `URLSession` 层错误 |
| 链路中段（D3-proxy 停） | **绿** banner + 单条消息级错误 | `FailoverError: LLM request failed: **network connection error**` |
| 链路中段（D3-proxy 在、映射未命中） | 同上 | `**502** status code (no body)` + D3-proxy 侧 `未命中 session→newapi 映射` |

**三种根因给出三种不同签名**，且 UI 层能区分「连不上内核」与「内核连上了但下游坏了」。条件④ 达成。

**同时登记一处 UI 侧不足**：UI 显示的是 openclaw 的通用占位文本，**不告诉用户是哪一层坏的**——分层归因目前只在日志里成立，不在界面上。scope-lock 的字面要求是「失败时**日志**足以定位到层」，故判达成；但「界面上也能看出是哪层」是 L2 值得补的。另外该占位文本在截图里**重复出现两次**（`...reply.The agent run failed...`），是 `(runID, index)` 分组假设的粗糙边缘首次现形——两条 delta 落进同一分组键被拼接。已记入待办。

## 12. 四条件终态

| # | 条件 | 状态 | 关键证据 |
|---|---|---|---|
| ① | 真实往返可见 | **达成** | `l1-roundtrip-assistant-reply.png`：`ROUNDTRIP OK` 请求与回复配对 |
| ② | 隔离性可证 | **达成** | 正面归因：本轮 PID 在 `~/.openclaw` 打开文件 0 个、4 个 session/run id 命中 0、产物全在隔离目录；用户全局 gateway PID 29071 全程未变 |
| ③ | 事件序列与契约一致 | **达成** | 6 项断言全 PASS；且在坏环境下确实变红（2 条 FAIL），证明断言有牙齿 |
| ④ | 失败可诊断 | **达成** | 主动注入 + 三种根因三种签名；UI 能区分传输层与中段失败 |

## 13. 收尾核对

- D3-proxy（:3001）、隔离 openclaw（:18899）、AgentShell **均已停止**，端口已释放。
- **用户全局 gateway PID 29071 全程未变**（基线采集时即为 29071，收尾时仍是 29071）。
- `app/server/.env` **已逐字节还原**至本轮改动前（`diff -q` 确认一致）——aggregate 是本轮临时配置，不留成静默改变计费归因的脚枪。要重现需重新设那两项。
- 隔离目录 `scratchpad/round0011-openclaw-iso/`（gitignored）保留，属本轮新建 test-resource，可留可删；**未删除任何非本轮新建的东西**（删除不在预授权内）。

## 14. 遗留待办

1. `OPENCLAW-ISOLATED-RUN-RECIPE.md` 补 `OPENCLAW_WORKSPACE_DIR` 并标注原声明的作用域限制（用户已授权扩入本轮 scope，**尚未执行**）。
2. `(runID, index)` 分组假设已现粗糙边缘（错误文本重复拼接），需用真实多段 delta 流验证正确分组语义。
3. UI 不显示失败层级，仅日志可归因——L2 候选。
4. AX 未暴露按钮标题，UI 自动化只能靠几何点击；且系统中文 IME 会干扰键盘驱动。若后续要做 UI 自动化，这两条都要先解决。
