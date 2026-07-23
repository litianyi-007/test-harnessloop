# Feedback Policy

## Feedback Classes

Positive:

- Expected behavior: 验收标准（见 `goal.md` Acceptance Criteria）达成，或——按本 goal 特有的探索性条款——获得有充分证据支撑的"可行性否定结论"（见下方补充条款）
- Required evidence: 各验收标准对应的验证方法产出（见 `thresholds.md` Verification Thresholds）
- Next action: **实现阶段（RA-L5 / IMPL，2026-07-23 起当前语境）**——单个 SG 子目标验收通过（证据齐、命令 pass，见 `goal.md` Acceptance Criteria 准则 7 + `goal-breakdown.md` SG-1..SG-8 议程表 + `thresholds.md` SG 各行）后：推进 goal-breakdown 议程表下一待选 SG（SG-3/SG-4/SG-5/SG-7/SG-8），并在交付达成本轮 scope-lock 时**收盘当前 round**（`rounds/NNNN/round-summary.md`）→ 经 `$harnessloop-continue` 开下一轮。（历史语境，保留供审计：需求分析阶段 = 按 RA-L1→RA-L2→RA-L3→RA-L4→dev-readiness gate 逐级归档；dev-readiness 签署后 `$harnessloop-goal update` 注入 dev 分解——已于 2026-07-22 完成。）

Negative:

- Execution-fault checks: 先查本轮执行（本轮改动/脚本/委派是否有误）
- Goal/business-fault checks: 再查契约（`goal.md`/`thresholds.md`/`data-contract.md` 是否本身有缺陷）
- Default priority: 先排查执行故障，后排查契约故障

Neutral:

- Why evidence may be inconclusive: TODO (owner: user)
- Treat as negative until: 证据被证实为 conclusive 之前，按 negative 处理

## Negative Feedback Actions

Allowed next actions:

- continue-investigation
- minimal-fix
- rollback-prior-execution
- revise-contract-with-human-confirmation
- blocked-human-decision

## Blocked Feedback Actions

Classify before stopping:

- runtime-recoverable: enter read-only investigation or recovery-planning round.
- access-missing: ask for missing endpoint, credential reference, local parameter, permission, account role, or tool.
- write-safety-required: ask for dry-run, test resource, rollback path, and human confirmation before mutation.
- human-decision-required: ask for product, business, risk, policy, acceptance, or cleanup decision.
- contract-insufficient: repair goal, threshold, evidence, or control contract.
- external-system-unsafe: allow only bounded observation until safety is established.
- unknown: ask for facts needed to classify.

## Round Decision Format

Feedback class:

Blocker type:

Recovery eligible:

Evidence paths:

Fault hypothesis:

Chosen next action:

Next scope-lock:

## 补充条款：探索性否定结论（本 goal 特有）

- 若某项探索性结论——尤其是 Success Condition ①"可行性结论"——判定为**否定**（例如：内核抽象/消息流屏障设计不可行、Mac→Windows 跟随开发机制不可行、server 选型无可行方案、agent app 三端整体可行性证伪），且该否定结论**有充分证据支撑**（证据路径可追溯、结论基于本 goal 实际产出而非臆测），则该反馈按 **positive**（探索成功）处理，而非 negative。
- 理由：本 goal 的 Success Condition 明确将"诚实的失败分析"列为可行性结论的合法形式之一（见 `goal.md`）；探索性 goal 的价值在于获得有证据支撑的结论（无论正负），而非强制达成预设的技术结果。
- 边界（不得滥用本条款）：
  - 本条款仅适用于探索性结论本身（`goal.md` Success Condition ①"可行性结论"），**不适用于**协议执行故障——例如 `verify_protocol.py` 失败、证据缺失、evidence 路径不可达等，此类情形仍按标准 negative 流程处理（先查执行故障，见上方 Negative 分类）
  - 不得以"探索性否定"为由回避执行故障排查，或跳过 `thresholds.md` 中定义的验证阈值
  - 否定结论仍须满足 Acceptance Criteria 中对应条目的 Evidence/Verification 要求，不能仅凭主观判断记为"已否定"
