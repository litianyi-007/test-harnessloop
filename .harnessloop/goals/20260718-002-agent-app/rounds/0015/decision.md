# Decision

- Feedback: neutral
- Blocker type: 无（工作已交付并复验；剩余项转入 rounds/0016，非阻断）
- Recovery eligible: yes
- Accepted: no
- Review: .hopper/handoffs/T-096-output.md
- Reviewer: codex via hopper T-095 + T-096（scope-lock 指定轮换——rounds/0014 是 grok）
- Review verdict: rework
- Review digest: ed9821488e08098b917129c9e564399b3a6de211374c19169a947fb546b2c650
- Acceptance evals: ran
- Acceptance evals detail: `evidence/runtime/acceptance-evals.json` —— RAE-0001 attempt `0015-a1` outcome=**pass**（不回归复验：3 轮往返、对账 exit 0、`--drop-one` exit 1）
- Active goal: 20260718-002-agent-app
- Active round: 0015（SG-10 L1 exec 审批）
- Decision maker: main session（claude-opus-5[1m]），**收/开由用户 2026-08-12 裁定**
- Timestamp: 2026-08-12

## Reason

**主判据达成，但审查闸未过——两件事，都如实记。**

**达成**：exec 审批端到端跑通，放行（命令真执行）与拒绝（命令未执行、会话不挂死）
两条路均 live 实测并冻结原件。这实质解决了 rounds/0013 认定的信任边界问题——
那时是**无任何关卡直接在宿主机执行 shell**，且那是内核未配置时的默认。

**未过**：★审查闸 T-095/T-096 均判 REWORK，共提 **6 条 MUST-FIX**。
T-095 的两条已返工复验（68/68、两条反证先红后绿、live 无回归）；
T-096 的四条（溢出 deny 失败处理 / 强制 deny 失败后持久状态 / `approval.resolve` 有界等待与
timeout terminal / active terminal 后 UI 同步）**未做**。

scope-lock 写的通过线是 `PASS / PASS_WITH_NOTE`，实际是 REWORK → **按纪律第 4 条判 `Accepted: no`**。

## 关于收敛守卫

scope-lock 的驱动模型写着「收敛守卫：第 3 个 MUST-FIX → checkpoint」。本轮计数到 **6**，
**越线两倍**。主会话在此停下并向用户 checkpoint（`evidence/checkpoint-convergence-guard.md`），
**未自行决定继续迭代**——守卫也是标准的一部分，不能只在对自己有利时遵守。

用户 2026-08-12 裁定：**收 0015，开 0016 专做 FSM 失败路径**。

## Main-Session Decision On Scope Boundary

1. **T-096 的四条不在本轮修** —— 它们自成一族（FSM 的失败/超时/持久化路径），
   值得自己的 scope-lock 与反例矩阵，而不是塞在已越线两倍的轮次尾巴上。
2. **异构双路派发**（T-094 同一 brief 同时给 codex 与 grok）—— 用户 2026-08-12 明确要求
   「执行前建议异构模型参与分析和提供决策依据」。**这一次双路是决定性的**：
   grok 找到了正解（`canDeliverApprovals` 的 caps 通路），codex 那一路全程未提。
3. **主会话答案先行登记再对照** —— `channel-decision-prereg.md` 在看到任一方产物之前写下，
   事后证明主会话三条候选全错。**不先登记就无法确证不是被带过去的。**

## Human Decision Required

- **无阻断项。** 下一轮（0016）方向已由用户裁定。

## Open Questions Resolved

- **不改 D1 七法能不能做成审批** → 能。`respondApproval` 的签名本就在协议里，只是实现是桩。
- **审批为什么送不到客户端** → **不是 channel 问题**（我最初三条候选全错），
  是客户端未在握手声明 `caps:["exec-approvals"]`，被 `canDeliverApprovals` 筛掉，
  内核随即 `expire(id,"no-approval-route")`。
- **审批关联采集为什么失效** → `stream` 外层 switch 使那些帧落进 `case "lifecycle"` 被丢弃，
  代码从未执行到 phase 判定。两条 stream 都是活路径，须都接。
- **`allow_session` 怎么处置** → D1 §2.6 本就规定同步拒绝 `unsupported_approval_decision`、
  不得静默降级；openclaw 侧是封闭三值 schema，结构上不可能出现 session 语义。**不是产品取舍。**

## Open Questions Remaining

- T-096 的四条（→ rounds/0016）。
- `capabilities()` 仍是桩，与当前推导常量存在漂移风险。
- 超时态无 D2 对应；`ApprovalBufferResolvedEvent.reason` 词表表达力不足（均需 D2 改动）。
- **契约正文不在契约目录**（`app/contracts/d1/` 是 10 行占位）——项目级落差。
- rounds/0014 遗留：非布尔 `hasMore` 静默停止、placeholder handle 的 `kernelSessionID`、
  live 未覆盖多页历史；`[gateway] ready` ≠ `sessions.create` 可用。
- 七处 `TODO (owner: user)`；TH-0031；三插件是否 bump 版本并 push。
