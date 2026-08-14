# Decision

- Feedback: neutral
- Blocker type: contract-insufficient（RAE-0001 条件③ 的「无丢帧」在当前内核下**结构上不可满足**——需 openclaw 不提供的 per-subscription 投递计数）
- Recovery eligible: yes（下一步是**用户裁决条件③措辞**，不是重做工作）
- Accepted: no
- Review: .hopper/handoffs/T-087-output.md
- Reviewer: grok via hopper T-087（scope-lock 指定轮换——rounds/0011 是 codex）
- Review verdict: pass-with-note
- Review digest: 18e76342bbd31b1ab051663e979ee6eca2c8601d7cd7f8f8dc7c73dd7f50eea8
- Acceptance evals: ran
- Acceptance evals detail: `evidence/runtime/acceptance-evals.json` —— RAE-0001 outcome=**fail**（条件③ 未完全达成，按 user-confirmed 的「缺一即 fail」）
- Active goal: 20260718-002-agent-app
- Active round: 0012（SG-10 L1 修复轮）
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-09

## Reason

**六项限定范围基本做完、经三轮异构评审推翻—返工—再验，审查闸判 PASS_WITH_NOTE；但 RAE-0001 因条件③ 判 fail。**

**关键区别（与 rounds/0011 不同）**：0011 是**声称超出证据**；本轮是**条件本身不可满足**——「无丢帧」需要 openclaw 不提供的 per-subscription 投递计数。`messageSeq` 已被源码坐实是 transcript 侧计数（`server-session-events.ts:189-215`），不承载投递信息。

**没有在验收时重新解释条件③。** grok T-087 明确指出：不同于条件① 的录屏（那次是 user-confirmed 的显式契约修订），**「无丢帧」这条文本未经用户修订**。所以本轮如实判 fail，把措辞问题作为**用户裁决**提出，而不是自己改标准过关——这正是 rounds/0011 教训的正面应用。

## Main-Session Decision On Scope Boundary

- **RAE-0001 = fail**，本轮 `Accepted: no`。
- **代码不回滚**：①②③④⑤⑥ 的产出均经独立复验（38/38、CI 平价 12/0/1、三端 codegen 全绿、禁区无越界），是有效交付。
- **不重开 subscribe 等 ack**（grok 明确建议不要）；服务端竞态与 ack 版修法作为独立后续。
- **下一步不是重做工作，是一个用户裁决**（见下）。

## Human Decision Required

**RAE-0001 条件③ 的「无丢帧」该如何处置？**

事实基础（均已源码 + 实测坐实）：
- `messageSeq` 是 transcript 侧计数，**不承载「本订阅收到几条」**
- openclaw **不提供** per-subscription 投递序号
- 因此「无丢帧」**在 kernel-client 这一层无法断言**，不是本轮偷懒

三条路（主会话不预设）：
1. **改条件③措辞**为「无乱序（可断言）+ 丢帧检测列为已知缺口」——与 2026-08-09 录屏那次同形，**显式改契约**
2. **保留原措辞**，则 RAE-0001 在获得内核侧投递计数之前**永远 fail**——需接受这一后果
3. **向 openclaw 上游提需求/PR** 增加投递序号，再回来满足原条件

## Open Questions Resolved

- ② 竞态是否真实存在：**是**（源码判定），客户端窗口已关，服务端窗口未关且已登记
- ③ messageSeq 缺口成因：**不存在缺口**，先前记录是观测偏差
- ①的正确修法：C（透传 messageId），第一版 ack 方案被 CI 正确否决

## Open Questions Remaining

- 上述条件③ 用户裁决
- D1（label 硬编码）、D2（服务端竞态）、D3（SessionStore 无入库判据）、D4（丢帧检测）、D5（capabilities 桩）—— 见 round-summary 待办表

---

## 后记（2026-08-10）：条件③ 已修订，但**本轮维持 `fail`，不追溯**

上方 `Human Decision Required` 提出的三条路，经 hopper 双路异构讨论（T-088 codex / T-089 grok，两家独立结论一致）与用户裁决，选定 **路 1 的加强版**：

**改条件③ 措辞，但不只是删掉丢帧要求**——新判据为「不乱序 + 受控会话内与权威 history 快照对账 + 破坏性反证 + 协议级保证列为内核已知缺口」。权威落点与完整理由见 `setup/data-sources.md` 的 2026-08-10 注。

**本轮 RAE-0001 维持 `outcome: fail`，`Accepted: no` 不变。** 条件修订**只对此后的执行生效**——不用新标准去追认已收盘的轮次。这一条是刻意的：rounds/0011 的教训是「不要为了过关而放宽解释」，那么修订后回头追认同样不可接受。**下一轮按新条件重新执行，才产生新 verdict。**

### 调查中被推翻的一处主会话结论（第三次）

decision 正文写「需要 openclaw 不提供的 per-subscription 投递计数」——**方向对，描述不准**。实际是：**openclaw 已完整实现该机制并发货**（`server-broadcast.ts:157/229/242-259` 的 per-connection `clientSeq`、丢帧时序号照进、客户端 `onGap` 给出 `expected`/`received`），**只是 `:257` 一行 `isTargeted ? undefined : nextSeq` 把 targeted 投递显式排除**。

所以「新增协议字段」的提案成本估高了——真要做只是**复用已有的可选字段 `EventFrame.seq`**。详见 `evidence/item3b-delivery-seq-upstream.md`。

**这是本轮第三次「主会话说没有、实际有」**（前两次：`logging.file`、D2 §3.3 subscribe 响应定义），**三次都由异构评审纠正**。共同模式：搜索维度选错，把「我没找到」当成「不存在」。

### 另一处配套认识（codex 指出，主会话先前分开看待）

**订阅竞态与投递序号必须配套**：只加序号**只能检测 `dropIfSlow` 型丢弃**，检测不到 `connIds.size === 0` 的订阅注册前丢失——那段根本没有帧被发出，序号无从占号。当前屏障等的是「RPC 已发出」，**不足以覆盖该窗口**；完整版需等 subscribe ACK，仍被 scope blocker 挡着。两条线在此合流。
