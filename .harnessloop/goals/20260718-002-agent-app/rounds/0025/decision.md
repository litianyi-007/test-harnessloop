# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: none — 测试改动对照 rounds/0024 两次失败日志由主会话自审；macos job 绿即本轮验收（scope-lock 不强制 hopper）
- Reviewer: main-session
- Review verdict: not-applicable
- Acceptance evals: none — 本轮为测试采样修复，无 runtime eval 台账
- Mechanical gate: 0 / coverage: rounds=32 rule_a_files=276 rule_b_files=3 citations=12 citations_exempt_external=0 citations_suffix_hinted=0 citations_ignored_explicit=14 citations_shape_dropped=1 review_files_with_ignore=3 decision_field_label_not_ascii=0 zero_inspected=11 scope_lock_round_path_mismatch=6 review_declared=25 review_none=6 review_missing_fields=0 review_digest_declared=25 goals_eval_registry_present=1 rounds_eval_ledger_present=6 rounds_eval_ledger_without_decision=0 eval_entries_checked=6 eval_entries_with_evidence=6 eval_entries_evidence_null=0 evals_with_system=1 evals_system_undeclared=0 eval_declaration_ran=6 eval_declaration_none=11 eval_declaration_absent=14 predecessor_declared=0 stop_recorded=0 stop_unjustified=0 mechanical_gate_declared=2 mechanical_gate_nonzero=0 loop_autocontinue_anomaly=0 loop_anomaly_skipped_unparsable=3 external_roots_declared=0 external_roots_available=0 external_citations_checked=0 external_citations_resolved=0 external_citations_not_found=0 external_citations_rejected=0 external_citations_unverifiable=0 external_systems_declared=5 / 2026-08-22
- Active goal: 20260718-002-agent-app
- Active round: 0025
- Decision maker: main session（grok-4.6）；用户 2026-08-22 裁定开本轮
- Timestamp: 2026-08-22

## Reason

**macos 上 frame-replay 从两次不相交的红变成一次全绿。** 修的是采样，不是产品。

0024 已经把门接上。本轮只动 `InterruptTests.swift` / `SteerTests.swift`：
两条仲裁测试不再先睡 60ms 再采锁；FAIL2 不再把 `unknown session` 当成失败
（`sessions.send#2` 未 dispatch 仍在）。`OpenclawGatewayKernelClient.swift` diff 为空。

| 检查 | 结果 |
|---|---|
| 本机 frame-replay | 174/174，`evidence/00-local-frame-replay.log` |
| Actions | [32503486999](https://github.com/litianyi-007/test-harnessloop/actions/runs/32503486999) **success** — ubuntu + macos；frame-replay step 绿；Swift 金标 13/0/0 绿 |
| C# | 仍 12+1 DEGRADED（未改） |

一次 Actions 绿不能证明永不 flake，但失败形状正是本轮改掉的那两类，且 0024 的门没有被拆掉。

## Next Action

- Action type: next-subgoal
- Scope-lock required: yes
- Human confirmation required: yes — SG-10 主线上下一件产品工作需选择（L3 成本 / HermesACP / C# 桩 / abort_and_resend / respondApproval parity）
- Safe without user input: no
- Recovery round objective: n/a
- Disallowed until confirmed: 不得默认开 L3 或第二内核；hopper 1424 条进 CI 仍另轮
