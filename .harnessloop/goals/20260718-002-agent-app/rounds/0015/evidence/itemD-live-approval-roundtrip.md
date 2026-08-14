# rounds/0015 D —— live 审批往返（主会话亲跑，2026-08-12）

## 结论：**主判据达成，放行与拒绝两条路都跑通**

隔离实例 `L1_EXEC_ASK=always`（配置实测落为 `tools = {"exec": {"ask": "always"}}`），
壳握手声明 `caps: ["exec-approvals"]`。

## 放行路径

| 环节 | 证据 |
|---|---|
| 审批卡渲染 | `shots/card-rendered.png` —— `⚡ exec @ gateway`、倒计时 `剩余 29:34`、等宽命令 `echo APPROVAL_GATE_OK`、`请求方 agent=main reqId=0de8c0c4-…`、**两个按钮「允许一次」「拒绝」** |
| 按钮数与内核一致 | `ask=always` 下 `allowedDecisions = ["allow-once","deny"]`，**没有 allow-always** —— UI 恰好两个按钮，不是三个 |
| 出站 RPC | `raw/r15c-approval-resolve-sends.txt`：`approval.resolve` **恰好 1 次**，`decision:"allow-once"`（连字符 wire 值）、`id:0de8c0c4-…`（与 reqID 一致）、`kind:"exec"`（回传正确） |
| 命令真的执行 | `shots/allow-executed.png` —— 系统行 `[审批] 允许一次: echo APPROVAL_GATE_OK`，assistant：``Done — output was `APPROVAL_GATE_OK`.`` |

## 拒绝路径

| 环节 | 证据 |
|---|---|
| 出站 RPC | 累计 2 次 resolve，最后一次 `decision:"deny"` |
| **命令未执行** | `shots/deny-not-executed.png` —— 系统行 `[审批] 拒绝: echo SHOULD_NOT_RUN_DENY`，assistant：「The command was **not executed** — the approval gate denied it (user-denied at the gateway). **Nothing ran.**」 |
| 会话未挂死 | 拒绝后 assistant 正常给出说明并提出可重新提交，界面可继续使用 |

## 事件链（`raw/r15c-approval-chain.json`，10 帧）

产出 `evt.approval_request` 的**载体帧是 `exec.approval.requested`**。
`session.approval(phase:pending)` 那一帧的 `producedEvents` 为空——**这是正常的**：
两条事件都指向同一次审批，去重闸门只让第一条产出。

> **一处我自己的测量错误**：最初只看 `session.approval` 那一行的 `producedEvents`，
> 见其为空就判「映射仍未通」。**产出挂在后到/先到的另一帧上**，要全表扫才看得到。
> 这是本会话第 N 次「量错地方，先怀疑被测对象」。

## 到达此处经历的三次纠正（都留痕）

1. **补 cap 之前**：内核判 `initiating-platform-unsupported`，`askFallback=deny` **直接拒绝**，
   审批请求从未产生（`shots/r15-headless-refusal.png`，前一次 live）。
2. **主会话的第一轮诊断（channel）全错**：我把 `webchat` / `tui` / 无 channel 三条候选分析得很细，
   **三条都在错误的那道门上**。真正的门是 `canDeliverApprovals`（客户端声明的 caps），
   由 **grok** 在异构双路里找到；codex 那一路全程未提。详见 `channel-decision-prereg.md`
   （**该判断在看到任一方产物之前已登记**，故可确证不是事后追认）。
3. **主会话的第二轮诊断（phase 值）不完整**：我说「代码找 `requested`、实际是 `waiting-approval`」，
   属实但轻了——实现方核实后指出 `stream` 是**外层 switch**，这些帧落进 `case "lifecycle"`
   被 end/error 守卫丢弃，**代码从来没执行到我指的那一行**。只改 phase 字符串修不好。
   幸而 brief 里写了「不要简单替换，先查清」。

## 遗留（不阻断，登记）

- `exec.approval.requested` 在前一次 live（r15b）**一条都没到**，本次到了。
  疑似 `approval-shared.ts:455` 的 `excludeConnId` 把请求方连接排除出广播，
  **未查证**。本次不阻断（lifecycle 关联帧已能独立完成 join）。
- `capabilities()` 仍是桩，而 D1 §2.6 规定 `approvalDecisionKinds` 由它门控；
  现为从 openclaw schema 推导的常量，**将来 `capabilities()` 落地时必须与之对齐，否则会漂移**。
- 超时态：openclaw 的 `session.approval(phase:"terminal")` 无 D2 对应，
  壳只能本地推断「已超时」，非内核确认。
