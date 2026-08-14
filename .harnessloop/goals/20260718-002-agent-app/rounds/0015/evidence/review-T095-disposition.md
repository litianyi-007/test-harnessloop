# rounds/0015 ★审查闸 T-095（codex）—— **REWORK**，处置记录

三项强制核对：(a) 产物 11051 bytes、raw log **17265 行**（真审）；(b) 落点正确
（注：codex 自述因只读沙箱未能实际写入 `.hopper/handoffs/T-095-output.md`，hopper 侧已落盘）；
(c) 不凭 exit 0 —— 逐条核过内容。

## 两条实质发现，**都属实**

### ① D1 §6.2 审批状态机未实现（主要项）

契约要求：每个 session **最多一个 active pending**；后续进**有限 FIFO**；
溢出/缓冲超时产出 `ApprovalBufferResolvedEvent`。

**主会话独立核实**：`evt.approval_buffer_resolved` / `ApprovalBufferResolvedEventMessage`
确实是 D2 已定义事件——`app/contracts/d2/schema/events/approval-buffer-resolved.schema.json`
有 schema，`app/contracts/d2/codegen/scripts/lib/leaf-types.mjs:41` 已登记，
`app/generated/swift/D2.swift` 中 22 处命中。**契约依据成立，不是评审方臆造。**

现状（codex 给的 file:line）：
- `OpenclawGatewayKernelClient.swift:268,1941-1981` —— 每条请求直接登记并 yield，无 active/FIFO/深度
- `SessionDetailView.swift:87-98` —— UI 把所有 pending 平铺
- `EventMapping.swift:747-756` —— **注释自己承认**该状态机没接入，且仍写着 `respondApproval()` 是 TODO（陈旧）

### ② `stop()` 与人工决策的竞态

`stop()` 进 `stopInProgress` 后对 pending 发强制 deny，**RPC 等待期间 actor 重入**，
用户此刻仍可点按钮 → 同一 reqID 可能被两条路径同时 resolve。
需给 reqID 加 in-flight 状态并串行化，且按 D1 正确处理 `approval_not_pending`。

## 评审方明确认可的部分（不是全盘否定）

- 七法签名逐字未变（`SIGNATURES_IDENTICAL=yes`）
- decision 显式映射三值（`EventMapping.swift:846-901`）
- **逐请求** `allowedDecisions` 校验、params 恰好三键（`:991-1013`）
- post-RPC 兑现核验：allow 必须终态 `allowed` 且 decision 精确相等（`:1029-1048`）
- 冻结反证 `counterproof1-main-session.txt` 被认可，事故形状
  `status=denied decision=deny reason=malformed-verdict applied=true` 复现属实
- live 主链（卡片→允许→执行；拒绝→未执行）基本成立

## 一处评审方自己标注的限制（诚实，值得记）

codex 在只读沙箱里跑测试得到 **60/64**，四条失败**全部是持久化测试因禁止写临时文件所致**，
它自己明说「该运行只能作为补充信息，不能替代冻结验收日志」。
**主会话在正常环境下的读数是 64/64。** 这是「环境差异导致的假红」，不是回归。

## 处置

已派子代理返工（两条实质项 + 陈旧注释订正），要求：
- 自己核实 D1 §6.2 原文，**若 codex 引错条款照实说**
- 两条破坏性反证（FSM 单 active 约束、竞态串行化）各须先看到红
- 硬判据 ≥64/64、CI 12/0/1、七法未变

**收敛守卫**：本轮 MUST-FIX 计数 = 2（未达第 3 个 checkpoint 阈值），故继续修而非停下。
