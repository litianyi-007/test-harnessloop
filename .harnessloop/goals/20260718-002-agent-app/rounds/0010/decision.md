# Decision

- Feedback: positive
- Blocker type: none（收盘时无 active blocker）
- Recovery eligible: 不适用（无收盘时 blocker）
- Accepted: yes
- Active goal: 20260718-002-agent-app
- Active round: 0010（SG-11 conformance 修正批，第二批首轮，轻量文档修订，已达成）
- Decision maker: main session（claude-sonnet-5）
- Timestamp: 2026-07-26

## Reason

rounds/0010 的验收边界由 scope-lock 明确为一件事：把 rounds/0008/0009 的 runtime 发现（openclaw ack 不可区分/interruptedActiveRun 不透出/hermes session-load 静默失败/new-api API 实况修正/D3 mint residual/validate-schemas 未验实例）回写进 design wiki conformance 文档，让文档重新对齐 runtime 实况——**不改任何协议契约语义**。执行结果：

- **7 项修正全落**：①openclaw ack 层不可区分（发现②）——D1 §11 C-1 决定性答案为"否"，回写 `pre1-openclaw-source-conformance.md` 新 §4 + `kernel-ecosystem-facts.md` 事实④，触发 D1 §11 自身预写的既有规则确认分支，不改契约文本；②`interruptedActiveRun` 失败路径不透出（发现③）——D1 §11 C-4 决定性答案为"不透出"，回写新 §5 + 事实⑤，同样落 D1 既定确认分支；③hermes session/load 静默失败根因链（发现④）——比 §1.7 原猜测"部分丢失"更严重的确定性 100% 复现 bug，回写 §1.7 postscript + 新 §4（根因链+PRE-7 阈值结论+§4.3 上游处置建议，报/不报中立并列、决策留用户）；④new-api 两处 API 实况修正——`GET /api/token/:id` 仅掩码（修正 T-009 N2 明文推断）、`/api/log/token` 真实鉴权为 Bearer 而非 `?key=`（修正 T-005 C2 推断），回写 `d6-newapi-integration.md` v4 blockquote + §4.1 两处；⑤D3 mint HTTP 501 residual 再确认（无契约变更，只再确认既有登记），回写 §7 #11 附注；⑥validate-schemas 未验实例——检索确认 wiki 无相关落点断言，wiki 不改，如实记录于修正对照表（唯一记载）；⑦修正对照表 `rounds/0010/evidence/correction-table.md`（105 行）逐条列旧表述→新事实→证据出处→落点 file:line，全部修订带标注（blockquote changelog + frontmatter `updated`/`sources`）。
- **零契约语义变更**：wiki diff 确认仅 4 个 Allowed 文件改动（`architecture/d6-newapi-integration.md`、`kernel/kernel-ecosystem-facts.md`、`research/pre1-hermes-source-conformance.md`、`research/pre1-openclaw-source-conformance.md`），`kernel/d1-kernelport-spec-v3-6.md`/`d2-message-schema-v3.md`/D5 文件 diff 均为空。

**★审查闸（hopper 派 codex，T-060，单人验收审）Verdict = MUST-FIX**：四项验收逐条核验——(1) 修正忠实性：7 项主体事实全部成立，file:line/数字均可复现（C-1/C-4 源码引用、hermes 根因链、new-api 两处修正、D3 501 residual 均逐条核实无误）；(2) 无契约语义夹带：`git diff-tree` 确认仅 4 允许文件，D1/D2/D5 零改动，C-1/C-4 落 D1 §11:817/820 预写分支的判断经核实成立；(3) 修订标注与出处：4 文件 frontmatter `updated` 全部由 `2026-07-22`→`2026-07-26`，出处齐全，Hermes §4.3 上游建议中立（报的要点/不报理由并列、决策留用户，无倾向性夹带）；(4) 无落点判定：D4/facts 定向检索确认可信，但指出全 wiki 反证检索命中 `log.md` 历史记录使"wiki 无落点"措辞略宽。**MUST-FIX 仅 2 处机械精度问题**：①修正对照表引用了父提交（`da764f8` 之前版本）的旧行号 `L103`/`L34`，当前 commit 实际行号为 `L112`/`L43`；②new-api 修正引文多写一个右花括号（`{key: fullKey}}`→应为 `{key: fullKey}`）。**7 项主体事实判定本身未被推翻**。

**处方级收残**：主会话照 codex 给出的复现命令（`nl -ba research/pre1-hermes-source-conformance.md`、`git show da764f8^:architecture/d6-newapi-integration.md | nl -ba | sed -n '263p'`）逐条自验——对照表行号已更新为 `L112`/`L43`/`L263-304`，多余花括号已在对照表与 wiki（commit `2ee61d2b`）中删除。**按 T-030 先例，纯机械精度问题的处方级修正完成后不再触发二次送审 gate**——本轮未把 MUST-FIX 计入需要重跑探针或改内核的返工循环。

## Main-Session Decision On Scope Boundary（本轮关键裁决）

- **SG-11 done**：7 项修正全部回写 wiki（4 文件、+314/-12 主体 commit `da764f8` + 收残 commit `2ee61d2b`）+ 修正对照表交付，零契约语义变更，codex T-060 逐条确认忠实性/无夹带/标注齐全/上游建议中立，MUST-FIX 仅 2 处机械精度问题且已处方级收残——SG-11 判定为**done**。
- **处方级 MUST-FIX 不 gate 的判例再次沿用**：延续 rounds/0006 Stage A 收残 T-030 先例（当时是 codex 复核收残 commit 判 CONFIRMABLE 而非要求二次全量返工），本轮 codex T-060 的 MUST-FIX 本质是"交付物精度"而非"事实判断错误"——审查者自身也把两者分开评估（"将事实结论与交付物精度分开判断"，见 T-060 输出"Decisions/deviations"节）。用复现命令自验后确认修正到位，不需要重新派发第二次评审。
- **审查闸价值再次坐实，但焦点是引用精度而非事实**：与 rounds/0009 T-057 NOTE（措辞诚实性）不同，本轮 T-060 的核心贡献是**引用精度纪律**——修正对照表在多次修订过程中引用了修订前（父提交）的行号，是"引用行号必须在修订后的文档上重新核对"这一具体教训，已沉淀为对照表纪律（见 self-audit.md）。
- **residual/待决策清单（本轮裁定，供后续参照）**：
  - **hermes session/load 静默失败 bug 上游处置**（报/不报 hermes issue）→ 待用户决策，wiki `research/pre1-hermes-source-conformance.md` §4.3 已备中立建议草案。
  - **D3 mint HTTP 501**（`newapi_token_id_lookup_unresolved`）→ 本轮只再确认登记状态，解除仍是 D3 业务面（第二批候选）待办。
  - **validate-schemas 实例校验缺口**（发现⑤）→ 应用侧 codegen 工具链待办，建议登记独立 harnessloop evolution issue 或结转后续 SG，非本轮 scope。
- **side work（并行，非本轮 scope）**：用户指定的 harnessloop plugin 自主驱动能力评估调研（T-058 codex + T-059 grok + 主会话合成）与本轮同期完成，交付 `docs/harnessloop-evaluation-20260726.md`（commit `c6365aa7`）。与 SG-11 scope 无交叉，如实记录不计入本轮验证范围。
- **下一步**：第二批 SG 方向已于 rounds/0009 收盘时 user-confirmed（主线＝SG-10 Mac UI 壳优先；随行项全选＝SG-11 conformance 修正批+SG-12 defer 修复轮+SG-13 hermes ACP 适配器+SG-14 Stage C 产品行为 parity），SG-11 完成后**下一 continue 应开 SG-10 Mac UI 壳主线 L1**（第二批主线启动），SG-12/13 按批次序建议穿插其间，非本轮擅自新裁定。

## Open Questions Resolved

- **D1 §11 C-1「ack 层是否可机器区分注入成功 vs 静默降级」的 wiki 回写**：rounds/0009 已给出决定性答案"否"，本轮把该答案连同 file:line 出处正式回写进 `pre1-openclaw-source-conformance.md` §4 与 `kernel-ecosystem-facts.md` 事实④，供后续开发/设计参考，不再是"待验证"状态。
- **D1 §11 C-4「abort 成功但 resend 失败时是否透出 `interruptedActiveRun`」的 wiki 回写**：rounds/0009 已给出决定性答案"不透出"，本轮回写 §5 + 事实⑤，同上。
- **PRE-7 阈值结论的 wiki 沉淀**：本轮把 rounds/0009 的 PASS（有条件，`provider:custom` 前提）判定连同数据（20/20 条、0.792/0.815/0.803s、3/3 一致）正式写入 `pre1-hermes-source-conformance.md` 新 §4.2，与 thresholds.md 既有回填行一致，双处不矛盾。
- **T-005/T-009 早期推断是否需要批量整理**：本轮已完成——`GET /api/token/:id` 掩码 key（修正 T-009）、`/api/log/token` 真实鉴权 Bearer（修正 T-005）均已回写 `d6-newapi-integration.md` v4 blockquote，不再是待整理状态。
- **codex T-060 MUST-FIX 是否需要二次送审**：本轮判定**不需要**——2 处均为机械精度问题（父提交旧行号引用、多余花括号），主会话用 codex 给出的复现命令自验后确认收残到位，按 T-030 先例不再 gate。

## Open Questions Deferred

- **hermes session/load 静默失败 bug 报不报上游 issue**：wiki §4.3 已备中立建议草案（报的要点 vs 不报理由并列），决策权留给用户，非本轮阻断，本轮不擅自代为决定。
- **D3 mint HTTP 端点 501 解除**：真实业务路径的 newapi token id 反查机制未闭合，结转 D3 业务面第二批，本轮只再确认登记状态未变。
- **validate-schemas.mjs 实例校验缺口的正式修复**：留待后续轮次补进正式 codegen/parity 基建或登记独立 evolution issue，非本轮 scope。
- **openclaw ack 层不可区分/interruptedActiveRun 不透出的产品/契约层面处置**：延续 rounds/0009 记录，是否需要额外状态查询或事件观察机制满足未来产品需求，留待后续设计决策。
- **SG-8.4②回填重建子项/SG-8.4③ hermes ACP kernel-client 适配器**：延续 rounds/0009 记录，SG-13 承接 SG-8.4③，本轮未触碰。
- **两个 rounds/0007 defer 项**（TS `EmptyPayload` 精度缺陷修复方案 / 解码边界是否需要 strict-decode）：SG-12 承接，本轮未触碰。
- **side work 评估调研（`docs/harnessloop-evaluation-20260726.md`）产出的 12 条候选 evolution issues**：是否登记为正式 harnessloop evolution issues，留待后续处理，非本轮 scope。

## Evidence Cited

| Evidence ID | Path | Role in decision |
| --- | --- | --- |
| E21 | wiki commits `da764f8`/`2ee61d2b` + `rounds/0010/evidence/correction-table.md` | SG-11 done 的直接依据：7 项修正全部回写 4 个 wiki 文件、零契约语义变更、修正对照表逐条列 file:line 出处；hopper T-060 逐条确认审 + 主会话处方级收残自验 |
| E20 | `rounds/0009/evidence/track-a-openclaw.md` + `track-b-hermes.md` | rounds/0009 交付的 5 处发现（②③④⑤ + PRE-7 阈值）是本轮回写的真值来源，本轮所有修正内容均以此为出处 |
| — | `.hopper/handoffs/T-055/T-057-output.md` | rounds/0008/0009 对抗复核结论，作为本轮 new-api 修正与 D3 501 residual 再确认的交叉引用来源 |
| — | `app/kernel-client/HERMES-RUN-EVIDENCE.md` | rounds/0008 token 掩码原始记录，new-api 修正项④的独立佐证来源 |

## Next Action

- Action type: 收盘 → SG-11 done 宣告 → 下一 continue 开 SG-10 Mac UI 壳主线 L1
- Scope-lock required: yes（SG-10 启动时新建 scope-lock）
- Human confirmation required: 否（第二批 SG 方向已于 rounds/0009 收盘时 user-confirmed，本轮收盘不需要用户就方向再次确认）；是（hermes 上游 issue 报不报为独立决策类待办，非本轮收盘阻断项，见收官报告）
- Safe without user input: yes（本轮收盘、SG-11 done、下一步开 SG-10 均不需要用户进一步确认）；下一步一旦启动实际编码，一律由主会话 claude-sonnet-5 子代理执行（code-impl 绝不派第三方，既定规则）
- Next round objective: SG-10 Mac UI 壳主线 L1（最小可见 app：窗口+会话列表+新建会话+消息流渲染，连隔离 openclaw 真实往返），SG-12/13 按批次序建议穿插，SG-14 随 SG-10 各阶段同步
- Disallowed until confirmed: 不得把 SG-11 的 7 项修正表述为已改动契约语义（D1/D2/D5 文本零改动，均为事实记载/caveat 注记）；不得代用户决定 hermes session/load bug 报不报上游 issue；不得把 validate-schemas「wiki 无落点」判定表述为该缺口已修复（脚本本身待办仍存在，只是 wiki 无需改）
