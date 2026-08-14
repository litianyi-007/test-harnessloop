# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-093-output.md
- Reviewer: grok via hopper T-093（scope-lock 指定轮换——rounds/0013 是 codex 且连派三轮）
- Review verdict: pass-with-note
- Review digest: 438cfeb73b14ce2bdbdec028a6ba26af3995cc1dea2c9bb8fbe00412c97a9fa6
- Acceptance evals: ran
- Acceptance evals detail: `evidence/runtime/acceptance-evals.json` —— RAE-0001 attempt `0014-a1` outcome=**pass**（不回归复验：3 轮往返、history 6 条 `hasMore:false`、对账 PASS exit 0、`--drop-one` exit 1 精确捕获）
- Active goal: 20260718-002-agent-app
- Active round: 0014（SG-10 L1 会话持久化）
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-11

## Reason

**rounds/0013 D 探查认定的「基本使用」唯一阻断已解除。**

主判据（重启恢复）由主会话亲跑并冻结原件：重启后两个会话都回到列表、会话 1 的完整对话恢复、
且在恢复的会话里发新消息拿到回复——`messageSeq` 从重启前的 2 接到 4，**证明是同一个内核会话
而非新建**，这同时坐实了 B（映射重建）与 D（重新订阅）。

scope-lock 的验证表**逐条满足**：基线 50/50、CI 平价 12/0/1、**D1 七法签名逐字未变**、
三端 codegen 四项全绿、`.app` 可运行、两条破坏性反证均由主会话亲手做到先看到红、
RAE-0001 重跑 pass、★审查闸 **PASS_WITH_NOTE**（scope-lock 写的通过线正是 `PASS / PASS_WITH_NOTE`）。

**与 rounds/0013 的判定差异不是标准松了，是结果不同**：0013 的审查闸判 REWORK，
按同一条纪律（第 4 条，按字面标准验）判 `Accepted: no`；本轮判 PASS_WITH_NOTE 且 No MUST-FIX，
故 `Accepted: yes`。**同一把尺子，两个结果。**

## Main-Session Decision On Scope Boundary

1. **审查闸的三条 note 本轮不改** —— 保持「被评审的状态 == 最终状态」。三条均非 MUST-FIX，
   已登记入下轮候选（见 round-summary）。这与 rounds/0013 的教训一致：那轮我在评审进行中改动
   被审文件，导致评审失效风险。
2. **`hopper-plugin/` 内新建 ISSUE 文件** —— user-confirmed 的单项例外（2026-08-11），
   已写进本轮 scope-lock 的 Disallowed 段。**只建文档，未改代码、未 bump 版本、未 push。**
3. **exec 策略（user 已裁定 ask + 审批 UI）不在本轮做** —— 需先闭合 `respondApproval` RPC
   （现为桩，直接开 `ask` 会让会话挂到 30 分钟超时，比现状更糟）。**排在下一轮。**
4. **scope-lock 中途两处更正**（通路 HTTP→WS RPC、分页字段引错实现）—— 按纪律第 4 条
   **显式改标准**而非在验收时放宽解释。评审方独立确认「explicit and source-grounded」。

## Human Decision Required

- **无阻断项。** 下一轮的方向已由用户 2026-08-11 裁定：**exec 策略 = ask + 审批 UI**
  （需先做 `respondApproval` RPC）。
- 遗留待裁（非阻断）：kata 分类法里 opencode/copilot/agy/mimo 四个未入选标签是否按新原则
  「用则列、停则摘」一并清理（本次只按裁决动了 kimi→deepseek，**已在 SCHEMA 里标注为已知不一致**）。

## Open Questions Resolved

- **不动 D1 七法能不能做成会话持久化** → **能**。加法式能力协议（`SessionRestoring` /
  `SessionHistoryProviding`）+ 同文件 extension 触达 actor 私有状态，未拓宽任何既有访问级别。
- **history 走 WS RPC 还是 HTTP** → WS RPC 可行且已 live 跑通（此前只有源码验证）。
- **openclaw 的 history 分页字段** → **两套**：WS `chat.history` 用 `nextOffset`（数字），
  `session-history-state.ts` 用 `nextCursor`（字符串）。**不可互换。**
- **重启后能否续用同一内核会话** → 能，`messageSeq` 连续（2 → 4）即证。

## Open Questions Remaining

- 非布尔 `hasMore` 的静默停止（审查闸 note 1）。
- 多页历史与「会话 2 非空历史」未在 live 覆盖（审查闸 note 3）。
- `[gateway] ready` 不足以保证 `sessions.create` 可用——repro 工具的就绪判据待改。
- rounds/0013 遗留的 Q3「收窄 `AgentShellCore` 的 public 暴露面」。
- B3 服务端 dispatch 竞态（需改 `app/contracts/`，scope blocker）；协议级无丢帧（内核已知缺口）。
- 七处 `TODO (owner: user)`；TH-0031 修法方向；三插件是否 bump 版本并 push。
