# Round Summary — rounds/0015

**目标**：用户 2026-08-11 裁定 rounds/0013 Human Decision 第 2 项——**exec 策略 = `ask` + 审批 UI**。
rounds/0014 已解除功能阻断，本轮解除**信任边界**上的那个：壳里的 agent 此前可在宿主机
直接执行 shell、**无任何确认关卡**，且这是**未配置时的内核默认**（`exec-approvals.ts:317-318`）。

## 主判据：**达成**（live 实测，放行与拒绝两条路都验过）

| 环节 | 结果 |
|---|---|
| 审批卡渲染 | `⚡ exec @ gateway`、倒计时、等宽命令、`reqId`、按钮 —— 按钮数与内核 `allowedDecisions` 一致（`ask=always` 下只有「允许一次」「拒绝」，没有内核不认的第三个） |
| **允许 → 命令真执行** | `approval.resolve(decision:"allow-once")` 恰好 1 次；assistant 回 ``Done — output was `APPROVAL_GATE_OK`.`` |
| **拒绝 → 命令未执行** | assistant 回「The command was **not executed** … **Nothing ran**」；会话不挂死 |
| 返工后无回归 | 同一条路重跑，resolve 仍恰好 1 次 |

**硬判据全部由主会话独立复跑**：`swift build` 通过 · 帧回放 **68/68**（本轮起点 50/50）·
CI 平价 **12 PASS / 0 FAIL / 1 DEGRADED** · **D1 七法签名 `git diff` 为空** ·
三端 codegen 四项全绿 · **RAE-0001 不回归 pass**（3 轮往返、对账 exit 0、`--drop-one` exit 1）。

## 但本轮 `Accepted: no`：★审查闸两轮均 REWORK，且触发收敛守卫

| 轮 | 发现数 | 内容 |
|---|---|---|
| T-095 | 2 | D1 §6.2 审批 FSM 未实现（单 active/FIFO/溢出事件）；`stop()` 与人工决策竞态 |
| T-096 | 4 | 溢出 deny 的失败处理；强制 deny 失败后的持久状态；`approval.resolve` 无界等待 + timeout terminal 不结束 in-flight；active terminal 后 UI 卡片同步 |

**MUST-FIX 计数 = 6**，scope-lock 的守卫是「第 3 个 → checkpoint」，**越线两倍**。
主会话按纪律停下并向用户 checkpoint；用户裁定「**收 0015 开 0016**」。

T-095 的两条**已返工并复验**（68/68、两条破坏性反证各自先红后绿、live 无回归）；
T-096 的四条**未做**，转入 rounds/0016。

## 这一轮真正修掉的东西（不只是"加了个 UI"）

1. **`caps` 未声明** → 内核 `canDeliverApprovals` 筛不出我们 → `no-approval-route` 直接拒绝。
   补 `caps:["exec-approvals"]`（内核注释明写该通路是给「newer non-UI bridges」的）。
2. **审批关联采集与现实不符**：代码在 `case "approval"` 里找 `phase:"requested"`，
   实际帧是 `stream:"lifecycle"` + `phase:"waiting-approval"`，**代码从来没执行到那一行**。
   改为两条 stream 都接（判别键 `shouldAwaitGatewayApprovalInline`，两条都是活路径）。
3. **decision 映射**：D2 下划线 ↔ openclaw 连字符，显式写死 + 逐请求 `allowedDecisions` 校验。
4. **post-RPC 兑现核验**：`forceMalformedDeny` 会回 `ok:true`，只看 RPC 成功会被骗。
5. **D1 §6.2 FSM**：单 active + 深度 8 的 FIFO + 溢出 fail-closed deny + 提升。
6. **`stop()` 竞态**：per-reqID in-flight 槽位，drain 收敛条件收紧为「pending 空 **且** 无在途 resolve」。
7. **一个静默失败**：用户点"拒绝"而审批刚被 stop 强制 deny 时，旧代码**静默显示成功**。
   根因是 `approval_not_pending` 不是错误码——openclaw 回 `ok:true + applied:false`。

## 本轮被推翻的结论（继续留痕）

1. **主会话第一轮诊断整条方向错了。** 我把 `webchat`/`tui`/无 channel 三条候选分析得很细，
   **三条都在错误的那道门上**。真门是 `canDeliverApprovals`（客户端 caps），**grok 找到、codex 那路全程未提**。
   **该判断在看到任一方产物之前已登记**（`channel-decision-prereg.md`），故可确证不是事后追认。
   —— **双路异构派发在此显出价值**：单派 codex 这轮会继续在 channel 上打转。
2. **第二轮诊断不完整**：我说「代码找 `requested`、实际是 `waiting-approval`」属实但轻了——
   `stream` 是外层 switch，那些帧根本没走到我指的那一行。只改字符串修不好。
3. **量错了地方**：见 `session.approval` 那行 `producedEvents` 为空就判"映射未通"，
   实际产出挂在 `exec.approval.requested` 那一帧上，全表扫才看得到。
4. **我给了子代理一个不可能完成的核实指令**：「在 `app/contracts/` 下核实 D1 §6.2 原文」——
   那里只有 10 行占位符，D1 正文从未转录进仓库，权威原文在
   `~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md`。**它照实说了而不是编个出处。**

## 已确认缺陷（转入 0016 或登记）

| 缺陷 | 处置 |
|---|---|
| 审批 FSM 的失败/超时/持久化路径（4 条） | **转 rounds/0016** |
| `capabilities()` 仍是桩，D1 §2.6 规定 `approvalDecisionKinds` 由它门控 | 登记，未来落地时须与当前常量对齐否则漂移 |
| 超时态：openclaw `session.approval(phase:"terminal")` 无 D2 对应，壳只能本地推断 | 登记（需 D2 改动，超本轮范围） |
| `ApprovalBufferResolvedEvent.reason` 两值枚举无法表达 `cancelled`/`denied` 终态 | 登记（返工方选择如实打印而非拿 `buffered_timeout` 冒充） |
| **契约正文不在契约目录**：`app/contracts/d1/` 是 10 行占位 | 登记，属项目级落差 |
| `exec.approval.requested` 在 r15b 未到、r15c 到了 | 登记，疑似 `excludeConnId`，未查证，不阻断 |
