# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-097-output.md
- Reviewer: grok via hopper T-097（scope-lock 指定轮换——0015 连派 codex 两轮）
- Review verdict: pass-with-note
- Review digest: 8fac0e83836d915bd93077e7392c1a8bbdd6a1fa0532025bc5308ab123c8716b
- Acceptance evals: ran
- Acceptance evals detail: `evidence/runtime/acceptance-evals.json` —— RAE-0001 attempt `0016-a1` outcome=**pass**（3 轮往返、对账 exit 0、`--drop-one` exit 1）
- Active goal: 20260718-002-agent-app
- Active round: 0016（SG-10 L1 审批 FSM 边界失败态）
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-12

## Reason

**scope-lock 的验证表逐条满足，★审查闸 `PASS_WITH_NOTE`（通过线正是 `PASS / PASS_WITH_NOTE`）。**

四项边界失败态全部实现并各配破坏性反证（**7 个拆除点逐字冻结**，两条的红是「整个测试进程
挂死 35 秒」这种极硬证据）。硬判据全部由主会话独立复跑：74/74、CI 平价 12/0/1、
**D1 七法 `git diff` 为空**、三端 codegen 四项 exit 0、RAE-0001 pass、**live 主链不回归**。

**与 rounds/0015 的判定差异不是标准松了**：0015 审查闸 REWORK 且 MUST-FIX 到 6（守卫阈值 3），
故 `Accepted: no`；本轮 PASS_WITH_NOTE 且四条 note 中三条是「别再动」与「park 为设计轮议题」，
唯一待办（live 复验）已完成。**同一把尺子。**

## Main-Session Decision On Scope Boundary

1. **live 复验中途主动中止过一次** —— 用户回到机器前时前台切走，继续按坐标点击会点进用户
   正在用的窗口。**停止 UI 自动化并清理，等用户说方便再补完。** 这是用户 2026-08-12
   「谨慎不要误操作」的直接执行，也是本轮唯一一次为安全而中断的动作。
2. **拒绝路径的测试载体与设计不同** —— agent 自己换了命令。**如实记录而非重跑到"合意"为止**：
   机制验证成立，但「验到了机制」与「验到了我打算验的那条」是两件事。
3. **非 expired 终态的 UI 清卡不做** —— 需 D2 新增终态事件，属 scope-lock 明确排除的设计轮议题。
   ★审查闸建议「park 为显式设计轮议题，不是静默产品债」，采纳。

## Human Decision Required

- **无阻断项。**
- 可选：非 `expired` 终态的 D2 事件补全、`ApprovalBufferResolvedEvent.reason` 词表扩充
  —— 两者都需动 D2 契约，属设计轮/上游议题，由用户决定何时开。

## Open Questions Resolved

- **权威 terminal 该不该无差别结束 in-flight** → **不该**。`applyApprovalDecision` 广播 terminal
  先于 `respond(true,…)`，无差别处理会把用户自己在途的决议判死（命令执行了 UI 却报错）。
  收窄到 `status=="expired"`，两个独立来源确认。
- **溢出失败能否一律进持久态** → **不能**。`applied:false` 只在审批已终态时出现，
  deny 重试永远只会再拿 `applied:false` → 永远清不掉。已拆开处理。
- **队列徽标能否接真实缓冲计数** → **不能**。缓冲请求从不 yield，且与 D1 §6.2
  「不触发新的可见 pending 状态」直接抵触。只能删除。
- **有界等待能否用 task group** → **不能**。`request()` 的等待体是 `withCheckedThrowingContinuation`，
  非取消感知；task group 退出前要等全部子任务结束，写出来的"有界等待"会原封不动保留它本要修的洞。

## Open Questions Remaining

- 非 `expired` 终态的 UI 清卡、`ApprovalBufferResolvedEvent.reason` 词表（均需 D2 改动）
- `capabilities()` 桩与推导常量的漂移风险
- rounds/0014 遗留：非布尔 `hasMore` 静默停止、placeholder handle 的 `kernelSessionID`、
  live 未覆盖多页历史；`[gateway] ready` ≠ `sessions.create` 可用
- **契约正文不在契约目录**（`app/contracts/d1/` 是 10 行占位）
- 七处 `TODO (owner: user)`；TH-0031；三插件是否 bump 版本并 push
