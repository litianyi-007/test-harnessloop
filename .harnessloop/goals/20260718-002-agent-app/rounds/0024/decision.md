# Decision

- Feedback: negative
- Blocker type: runtime-recoverable
- Recovery eligible: yes
- Accepted: no
- Review: none — CI yaml 由主会话自审；macos job 未稳定绿，不派确认审
- Reviewer: main-session
- Review verdict: not-applicable
- Acceptance evals: none — 本轮为 CI 接线，无 runtime eval 台账
- Mechanical gate: 0 / coverage: rounds=31 rule_a_files=273 rule_b_files=3 citations=12 citations_exempt_external=0 citations_suffix_hinted=0 citations_ignored_explicit=14 citations_shape_dropped=1 review_files_with_ignore=3 decision_field_label_not_ascii=0 zero_inspected=11 scope_lock_round_path_mismatch=6 review_declared=25 review_none=5 review_missing_fields=0 review_digest_declared=25 goals_eval_registry_present=1 rounds_eval_ledger_present=6 rounds_eval_ledger_without_decision=0 eval_entries_checked=6 eval_entries_with_evidence=6 eval_entries_evidence_null=0 evals_with_system=1 evals_system_undeclared=0 eval_declaration_ran=6 eval_declaration_none=10 eval_declaration_absent=14 predecessor_declared=0 stop_recorded=0 stop_unjustified=0 mechanical_gate_declared=1 mechanical_gate_nonzero=0 loop_autocontinue_anomaly=0 loop_anomaly_skipped_unparsable=2 external_roots_declared=0 external_roots_available=0 external_citations_checked=0 external_citations_resolved=0 external_citations_not_found=0 external_citations_rejected=0 external_citations_unverifiable=0 external_systems_declared=5 / 2026-08-21
- Active goal: 20260718-002-agent-app
- Active round: 0024
- Decision maker: main session（grok-4.6）；用户 2026-08-21 授权接续含「返工后补 CI」
- Timestamp: 2026-08-21

## Reason

**CI 门接上了，并且立刻兑现了价值——但 macos job 还不是稳定绿，本轮不接受。**

ubuntu 全程绿。C# 金标仍是 12 PASS + 1 DEGRADED（未改，诚实分歧）。SwiftPM 整包构建两次都绿。
Swift 金标步骤因 frame-replay 先红而未跑到，但 0023 那次（旧 workflow、无 frame-replay）已经
13/0/0 绿过：https://github.com/litianyi-007/test-harnessloop/actions/runs/32473965579

frame-replay 两次 Actions macos 跑出**两套不同的失败**：

| run | 结果 | 失败 |
|---|---|---|
| [32474120825](https://github.com/litianyi-007/test-harnessloop/actions/runs/32474120825) | 173/174 | 仅 0012 subscribe 固定 200ms 窗口 |
| [32474519871](https://github.com/litianyi-007/test-harnessloop/actions/runs/32474519871) | 171/174 | 0012 已过；三条 0023 §9.3/FAIL2 的 40–100ms 窗口 |

v2 把 0012 改成有界轮询，第二次 run 证明那条修对了。剩下三条是同一形状：用 `Task.sleep(40/60ms)`
去采一个本就只有一两百毫秒的锁窗口，GitHub runner 上过冲就看到 `stop_in_progress` 或
`unknown session`。本机 174/174 稳定，Actions 不稳定——**正是「所有绿都是本机绿」这句话要防的东西。**

红线守住了：无 `continue-on-error`、无 `|| true`、C# 期望未改、产品实现未改。
第一次红没有被洗成绿。

不把第二次的 171/174 当回归、也不把第一次 0023 测试的绿当稳定。下一步是把那三条采样改成
与 v2 同类的有界轮询，而不是再赌一次 Actions。

## Next Action

- Action type: investigation
- Scope-lock required: yes（已有 v2；再动那三条测试需 v3）
- Human confirmation required: no
- Safe without user input: yes
- Recovery round objective: 把 InterruptTests/SteerTests 里三条 §9.3 采样从固定 sleep 改成有界轮询，使 frame-replay 在 macos Actions 上稳定 174/174
- Disallowed until confirmed: 不得为了绿而 skip/重试这些测试，不得改 `subscribe()`/`interrupt()`/`stop()` 产品实现
