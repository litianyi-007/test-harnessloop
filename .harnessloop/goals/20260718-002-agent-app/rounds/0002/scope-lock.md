# Scope Lock

## Round Objective

**SG-4 打通真实运行内核（探索性 de-risk 轮）**——把 kernel-client 对着**真实运行的 openclaw Gateway**（本项目自建、`kernels/openclaw` submodule，`pnpm gateway:dev`，`ws://127.0.0.1:18789`）跑通一次 `createSession → subscribe 收 KernelEvent 流 →（send 视 provider 可用性）→ stop` 闭环，作为 SG-8 全部 runtime 探针（PRE-1/3/7）与 SG-6 e2e wire 的**依赖底座**。

本轮**探索性**：openclaw Gateway 首次在本机起、WS 是否需鉴权、`send` 是否需真实 model provider（真 LLM/api key）均为**未知**，须先 de-risk 探针摸清，再据发现定客户端形态与闭环边界——不预设一次做完。

**验收边界（诚实分层，避免"done 名不副实"重演）**：
- **本轮必达（L1 连通性）**：openclaw Gateway 真起、监听 18789、kernel-client 完成 WS 握手 + `createSession` + `subscribe` 收到真实 KernelEvent 流 + `stop`。
- **本轮尽力（L2 完整闭环）**：若 `send` 不需真 LLM（或可配 mock/echo/廉价 provider），补跑 `send`→收到 agent 输出事件的完整轮次；若需真 LLM 且不可得，则 `send` 部分明确 defer，记为待 provider 就绪。
- **本轮不做（依赖 SG-8.7）**：SG-4 验收列的"过 SG-1 fixture 审批五态/SessionLockState 金标 parity"——SG-1 只有 TS runner、Swift/C# runner 不存在、`app/parity/` 空（审计已坐实），该 parity 依赖 SG-8.7 parity runner 补齐，本轮不承载，明确标注结转。

## Allowed Changes

| Path/data/tool | Allowed action | Limit |
| --- | --- | --- |
| kernels/openclaw（submodule 工作区） | 运行（`pnpm gateway:dev` 等）+ 只读源码 | 仅**运行**内核 + 读 `packages/gateway-protocol` 等协议 schema；**不改**内核源码（SG-4 是连接内核，非改内核） |
| app/（新增 kernel-client 最小壳目录，如 `app/kernel-client/` 或 `app/mac-shell/`） | 新建 | kernel-client 骨架 + 最小壳（语言据 de-risk 探针结论定：优先 SG-4 spec 的 Swift；若 Swift WS 栈成本过高，先用能最快证闭环的探针级客户端并说明） |
| .harnessloop/goals/20260718-002-agent-app/rounds/0002/ | 写 | 本轮 round 三文件 |
| scratchpad | 写 | de-risk 探针脚本/日志（throwaway） |

## Disallowed Changes

- **改 `kernels/openclaw` / `kernels/hermes` 源码**——本轮是"连接真实运行内核"，不是改内核；如发现必须改内核才能连通，停下记为 blocker、退回主会话决策（不擅自改）。
- 三插件 submodule、`.hopper`、其它 goal。
- 借本轮之名启动 SG-3/5/7/SG-8 其它子项的编码。
- 把真实 provider 的 api key / 凭证写入任何 tracked 文件（若 `send` 需 provider，凭证走环境变量/本地 ignored，参照 `$harnessloop-secrets` 纪律）。

## One-Variable Strict Mode

- Enabled: no
- Variable: 不适用（探索性 de-risk + 最小壳打通轮，非单变量隔离验证）
- Reason: 首次打通真实运行内核含多个未知（起服务/鉴权/provider），须探针驱动、迭代式推进。

## Verification Commands Or Checks

| Check | Command or method | Expected result | Evidence path |
| --- | --- | --- | --- |
| Gateway 真起并监听 | `pnpm --dir kernels/openclaw gateway:dev`（后台）→ `lsof -iTCP:18789 -sTCP:LISTEN` 或日志 | 进程起、18789 LISTEN | scratchpad gateway 日志 + rounds/0002 evidence |
| WS 握手 + createSession + subscribe | kernel-client 连 `ws://127.0.0.1:18789` 完成握手（含鉴权若需）+ 发 `createSession` + `subscribe`，收到真实 KernelEvent | 收到内核 emit 的 KernelEvent 流（非 mock） | 客户端运行日志 + 抓包/事件转储 |
| stop 闭环 | 客户端发 stop/关闭 session | session 干净关闭，无悬挂 | 客户端日志 |
| （L2）send 完整轮 | 视 provider 结论：发 send → 收 agent 输出事件 | 若 provider 可得则收到输出；否则明确 defer | 客户端日志 或 defer 说明 |

## Runtime Recovery Limits

- Recovery round: 可能（若 Gateway 起不来/连不通，本轮允许只读诊断 + 调整启动配置的 recovery 迭代）
- Blocker type: 预期可能遇 `runtime-recoverable`（启动配置/端口/鉴权）或 `access-missing`（send 需真实 provider 凭证而不可得）
- Allowed observation targets: gateway 日志、`packages/gateway-protocol` schema、`lsof`/WS 探针
- Disallowed triggers or writes: 不改内核源码、不写凭证入 tracked 文件、不对外部系统（真 newapi/真 LLM）做计费调用除非用户确认
- Cleanup/write confirmation required before: 起长驻 gateway 进程属可回收（本地 loopback）；结束时须 kill 后台进程

## Rollback Condition

若打通过程中发现必须改 `kernels/openclaw` 源码、或 `send` 强依赖真实付费 LLM 且无安全的 mock/廉价路径，则停在 L1（连通性）边界，把 L2 明确 defer，不为求"完整闭环"而擅自改内核或发起付费调用。

## Human Confirmation Required

- 起本地 loopback gateway 进程：无需确认（可回收、无外部副作用）。
- 若 `send` 需发起**真实付费 LLM 调用**（经真 provider/newapi）：**需用户确认**后才发起（计费/外部调用）——否则 L2 的 send 部分 defer。
