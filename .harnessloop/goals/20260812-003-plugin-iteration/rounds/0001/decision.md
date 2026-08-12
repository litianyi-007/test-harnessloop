# Decision

- Feedback: neutral
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: no
- Review: .hopper/handoffs/T-104-codex-output.md
- Reviewer: codex via hopper T-104-codex **+ grok via hopper T-104-grok**（异构双路，同一 brief、独立作答互不可见；grok 产物在 `.hopper/handoffs/T-104-grok-output.md`。`Review:` 字段按既有约定只填单一路径，双路在此说明）
- Review verdict: **REWORK（两家一致——本会话双路第一次收敛）**
- Review digest: b093a5ae587cc521e372a507e41bcde0b701d628efbb05b53484fea6ed1ce3f7
- Second reviewer digest: 34259dfd9b2ba7da0088ac9a3d620ec0b506d54579e7679ea33d4910a9c82cb9（`.hopper/handoffs/T-104-grok-output.md`。机械门只对账 `Review:` 指向的那一份，第二路在此自记——**这是自觉留痕，不是机械门要求的**）
- Acceptance evals: none — 本轮无插件代码改动，无可跑的验收 eval
- Acceptance evals detail: n/a
- Active goal: 20260812-003-plugin-iteration
- Active round: 0001
- Decision maker: main session（claude-opus-5[1m]），简化方向由用户 2026-08-12 裁定
- Timestamp: 2026-08-12

## Reason

**`Accepted: no` 且 `Feedback: neutral`。**

计划范围（PG-1 + PT-2）**一项未执行**——动手前的双路设计审判 REWORK，
且两家独立指出的缺陷直接否掉了 PG-1 的存在理由与整个计数框架。

判 `neutral` 而非 `negative` 的依据是 `feedback-policy.md` 的分类文本：
`negative` 要求「修复引入回归，或反证从未变红，或**评审判 REWORK 且未收敛**」。
本轮评审确判 REWORK，但**已收敛**——用户当轮裁定简化方向，契约已按评审结论重写。
无回归（本轮零代码改动）。

**不判 `positive`**：本轮的既定目标确实没达成，不能因为「意外收获有价值」就改判。

## Main-Session Decision On Scope Boundary

1. **双路而非计划中的单路** —— scope-lock 写的是单路。改派双路是因为实际审查对象从
   「PG-1 的判定标准」变成了「goal 设计本身」。**派出前已向用户明说，非事后补记。**
2. **本轮不执行 PT-2（kata）** —— 前提作废后再跑一次 kata 只是为了让轮次「有产出」，
   属空转。kata 的真实使用另行安排。
3. **不销毁初版证据** —— 初版 goal 文件被重写覆盖，但 rounds/0001 的 scope-lock、
   预登记、评审产物**原样保留**。否则没人知道这个 goal 为什么长成现在这样。
4. **本轮不计入任何统计** —— 计数指标本身已作废；即便保留，本轮也不该计入
   （两家评审一致：0001 是 meta 轮）。

## Human Decision Required

- **无阻断项。** 简化方向已由用户裁定并落盘。

## Open Questions Resolved

- **可计数的成功条件能不能做出不可操纵的形式** → **在本场景下不能**。计数单位（轮）
  可被任意切分、样本源可被冻结、判定边界可事后收窄，且确认人与受益人同一。**遂不做。**
- **「落进上游仓」算不算可复用的证明** → **不算**。上游是同一人的仓，提出方即接受方。
  实质门槛只能是机器可检的「**去掉会红、装上去会绿**」——与七条验收标准第 1 条同一句话。
- **`Active goal` 该指向谁** → **交还 002**。002 是使用现场，插件缺陷从那里暴露；
  把 003 设为排他性 active goal 等于冻结自己的样本源。「插件优先」以规则保留。
- **「静默失败」这个概念要不要留** → **留作描述工具，不留作验收指标**。
  并采纳 codex 的更准表述与 `producer-silent`/`consumer-silent` 二分。

## Open Questions Remaining

- **kata 仍几乎没被真实调用过**（2026-08-12 走通一次沉淀，未暴露问题——
  如实记为「用了一次没发现问题」，**不是「验证通过」**）。
- **hopper 待修 ④⑤ 与两条文档漂移**；**harnessloop 的 TH-0031 / TH-0032**。
- **`package-lock` 那类「清单 vs 发现式守卫」缺口需在三插件各查一遍**（仅 hopper 已补）。
- **TH-0032 的清理动作属 `write-safety-required`**（控制契约明写「删除与覆盖不在预授权内」），
  意味着隔离实例的凭证残留清理**无法自动化，每次都要用户确认**。
