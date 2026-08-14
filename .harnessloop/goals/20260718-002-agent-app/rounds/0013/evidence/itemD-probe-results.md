# rounds/0013 D —— 可用性探查结果（2026-08-11）

判据在观测**之前**已写死于 `itemD-probe-design.md`，本文件只填结果，不改判据。

## 一句话结论

**距「基本使用」只差一件事，但那件事是阻断级：会话不持久——app 一重启，全部会话从界面消失。**
scope-lock 里预设的两个降级面（审批、label）**都不是问题**：label 已由 B1 修掉；审批**根本不存在**。

---

## D-1 多会话 —— **通过**（B1 生效）

同一 state 目录内连建 **3 个会话全部成功**，侧栏并列「会话 1/2/3」，视觉可区分，切换正常。
截图 `ui-shot-03-three-sessions.png`。修复前第二次建会话必因 label 撞名失败。

**判级：不是阻断，也不难用。已解决。**

## D-2 工具调用 —— **假设 H1 证伪**，但换出来一个别的问题

预登记的假设是：`respondApproval()` 是桩 → 审批永远 pending → 卡满 `DEFAULT_EXEC_APPROVAL_TIMEOUT_MS`
（**30 分钟**）。**实测完全不是这样**：

| 事件 | 时刻 | 内容 |
|---|---|---|
| `evt.tool_call` | 19:23:28 | `name=exec` `status=started` |
| `evt.tool_result` | 19:23:34 | `isError=false` `durationMs=3011` `output=HELLO_FROM_TOOL` |
| `evt.message.delta` | 19:23:34 | "The exact output was: ```HELLO_FROM_TOOL```" |
| `evt.turn_complete` | 19:23:36 | `stopReason=completed` **`forceResolvedApprovals=-`** |

- 整回合 **约 8 秒**，远低于预登记的 5 分钟阻断阈值
- 全程 **0 条 approval 事件**
- **`exec` 直接执行成功，从未发起审批**

**所以 scope-lock 写的「审批 pending → openclaw 侧 timeout-deny → 工具调用被拒」也是错的**——
不是被拒，是**压根没有审批这一关**。`respondApproval()` 是桩这件事，在当前配置下是**死代码**。

**判级：不是阻断，也不难用。** 但它换出来一个**性质不同的问题**：

> **这个壳目前没有任何工具执行的确认关卡。** agent 可以直接跑 shell 命令，用户看不到、也拦不住。

### 2026-08-11 更正（★审查闸 T-090b 指出，主会话已独立核实）

本节初稿写的是「**在隔离实例 + 隔离 workspace 下这是可接受的**」，并把此项判为「不是阻断，也不难用」。
**这两点都不成立，此处更正。**

**(1) 机制已查清** —— 是**未配置时的默认行为**，不是隔离实例或 `--allow-unconfigured` 的特例：

| # | 事实 | 出处 |
|---|---|---|
| 1 | 启动配置只设 model/provider/logging，没有 `tools.exec` 也没有 sandbox | `repro/start-isolated-kernel.sh:81-89` |
| 2 | `--allow-unconfigured` **只跳过 gateway.mode 启动守门**，与 exec 策略无关 | `cli/gateway-cli/run.ts:245-253` |
| 3 | exec host 默认 `auto`；无 sandbox runtime 时解析为 `gateway` | `bash-tools.exec-runtime.ts:227-268` |
| 4 | **未配置时默认 `security=full`、`ask=off`** | `infra/exec-approvals.ts:317-318`（**主会话已逐字核实**：`const DEFAULT_SECURITY: ExecSecurity = "full"` / `const DEFAULT_ASK: ExecAsk = "off"`） |
| 5 | 审批只在 `ask=always` 或 `ask=on-miss + allowlist miss` 时发生 | `exec-approvals.ts:1840-1857` |
| 6 | Swift `respondApproval()` 仍立即抛 `notImplemented` | `OpenclawGatewayKernelClient.swift:990-991` |

→ 所以本轮观察到「0 条 approval 事件、exec 直接执行」是**必然结果**，不是偶然。

**(2) 「隔离环境下可接受」是错的** —— **独立的 state/workspace 目录不是进程 sandbox**。
exec 实际运行在 **gateway host** 上，可及宿主进程的权限范围。我把「openclaw 自身状态被隔离」
误当成了「被执行的命令被隔离」，这是两件事。

**(3) 分类更正** —— 原判「不是阻断，也不难用」把**任务完成性**与**产品安全性**压成了同一维度。
按任务完成性，它确实不阻断（8 秒完成）；但**在安全/信任维度上，模型能在用户不可见、不可拦截的
情况下直接执行宿主机 shell，是阻断级**。

**(4) 因此这成为交用户裁决的第 2 项，性质由「要不要做审批 UI」升级为「日常壳采用哪种 exec 策略」**：
`deny` / `allowlist` / `ask + 审批 UI`（需先闭合审批 RPC，否则会真挂起）/ 或在真实 sandbox 中显式 `full`。
**未配置的 `full/off` 不能当作安全默认，也不能替代这个产品决策。**

## D-3 重启 app —— **阻断**

| 侧 | 重启后 |
|---|---|
| 内核库 `sessions` 表 | **5 行**（会话都还在） |
| app 侧栏 | **空**，回到「选择左侧会话，或点击"新建会话"开始」 |
| 重启后 app 的 wire trace | **文件根本没生成** —— 零会话相关通信 |

连接本身是好的（「● 已连接 (scopes: operator.admin)」）。问题是
**`SessionStore.sessions` 是纯内存本地状态，从不向内核拉取已有会话**——重启后它不知道自己有过会话，
也从没试过去问。

按预登记判据「历史全丢 = 阻断」→ **阻断**。

**这是「mac app 可以基本使用」目前唯一的真阻断。** 一个每次开机都失忆的聊天壳不能用。

**好消息是数据没丢**：C 已经证明 `GET /sessions/<key>/history` 能拿到权威历史，
且 `(messageId, messageSeq)` 与实时帧完全对得上。**缺的是壳去拉，不是内核没有。**

## D-4 其它观察（记录，不单独判级）

- **无流式渲染**：`evt.thinking` 在 wire 上是**逐 token 流式**的（单轮 36 条），
  但 assistant 正文只有**一条** `evt.message.delta`，所以界面上文本一次性出现。
  这是 `session.message` 层的行为，非壳缺陷。**难用，不阻断。**
- **思考过程不可见**：36 条 `evt.thinking` 全被丢弃，用户看不到 agent 在想什么，
  长任务期间界面无声。**难用，不阻断。**
- **发送后无进度指示**：等待期间除了 `isWaitingForReply` 无更多反馈。**难用，不阻断。**
- **壳不写任何本地日志**（2026-08-11 补，由 ★审查闸 T-091 指出 `raw/ui-diag-badport.log` 为
  0 字节而暴露）：把壳指向死端口启动，它**向 stdout/stderr 写零字节**，失败只呈现在 UI 上。
  好处是条件④ 的 UI 呈现很干净；代价是**用户事后无法排查**——界面关掉，线索就没了。
  **难用，不阻断**；但若将来要让用户自助报障，这是必补的一环。

---

## 交给用户裁决的事项

scope-lock 明文：「**探查完停下报告，不擅自把 L2 项目拉进来。** 要不要提前做 stop 按钮 /
审批 UI，由用户看探查结果决定。」现在的裁决点与 scope-lock 预想的**不一样**：

1. **会话持久化**（D-3，阻断）—— 这**不在** L2 清单里，是探查新发现的。要不要开一轮做？
   技术上已铺平：history 接口可用、对账已验证、`SESSION_KEY` 的坑已踩掉。
2. **审批 UI**（L2 项目）—— 探查显示当前**没有审批关卡**。是要补上这道关卡（信任边界），
   还是接受「隔离环境下直接执行」？这不是可用性裁决，是安全裁决。
3. **stop 按钮 / 流式渲染**（L2 项目）—— 探查显示均为「难用」而非阻断，可按原计划留在 L2。

## 一处预设被推翻的记录

scope-lock「已知的降级面」一节列的三条里，**两条经实测不成立**：

| scope-lock 原文 | 实测 |
|---|---|
| 审批 pending → timeout-deny → **工具调用被拒** | **没有审批，工具直接执行成功** |
| 「可用性会很差，但**不挂死**」 | 不挂死是对的，但理由完全不同 |
| 无流式渲染 | ✅ 属实 |

而真正的阻断（会话不持久）**一条都没被预设到**。
这正是 scope-lock 写「本轮不预设『基本使用』还缺什么——先探查」的价值所在。
