# Scope Lock — rounds/0010

## Round Objective

**SG-11 conformance 修正批（第二批首轮，轻量文档修订）**：把 rounds/0008/0009 的 runtime 发现与早期推断修正**回写进 design wiki**（`~/.llm-wiki/agent-app-design`，独立 git 仓），让 conformance/设计文档重新与 runtime 实况对齐——后续 SG-10 UI 壳等开发建立在修正过的事实上。**不改任何协议契约语义**（D1/D2 行为规范变更不属本轮；strict-decode 裁决在 SG-12）。

**修正清单（真值来源 = rounds/0009/evidence/track-{a,b}.md + rounds/0008 evidence + T-055/T-057 复核）**：
1. **openclaw ack 层不可区分**（发现②）：`chat.send` ack 在 steer-注入 vs 空闲新 run 结构完全相同——回写 `research/pre1-openclaw-source-conformance.md`（C-1 段）+ 视引用链需要同步 `kernel/kernel-ecosystem-facts.md`；D1 相关 caveat 如需备注只做"事实注记"不改契约文本。
2. **`interruptedActiveRun` 失败路径不透出**（发现③）：`sessions-messaging.ts:379-389` 三元仅 ok===true 拼接——回写 PRE-1 openclaw conformance（C-4 段）。
3. **hermes session/load 静默失败伪装成功**（发现④）：provider:auto+自定义端点 100% 复现（`acp_adapter/session.py:551/651`→`runtime_provider.py:1169`）,比 §1.7 原猜测"部分丢失"更糟——回写 `research/pre1-hermes-source-conformance.md` §1.7 + PRE-7 阈值结论（20/20、0.79-0.82s、3/3 一致,provider:custom 前提）;**附上游处置建议段**（报 hermes 上游 issue 的草案要点 vs 不报的理由,处置决策留给用户,本轮只写建议）。
4. **new-api API 实况修正**（rounds/0008/0009）：`GET /api/token/:id` 仅掩码 key（修正 T-009 推断）;`/api/log/self` 需 cookie 会话、token 侧真实等价 `/api/log/token`+Bearer（修正 T-005 的 `?key=` 推断）——回写 `kernel/d6-newapi-integration*.md` 或 kernel-ecosystem-facts 的对应事实行（按引用实况落点）。
5. **D3 mint HTTP 501 residual**（发现①）：如实登记为 D3 业务面已知缺口再确认（映射层可用,HTTP 端点 stub）——落点按 wiki 内 D3/server 相关文档实况;若 wiki 无对应落点,记录于修正对照表即可（app 侧 rounds/0009 evidence 已载）。
6. **validate-schemas 未验实例**（发现⑤）：wiki 内若有 codegen 断言相关叙述（D4 §3.5a/CODEGEN 引用）需对齐;若无 wiki 落点,如实记录"app 侧文档已载,wiki 无需改"。
7. 每处修正带**修订标注**（依 wiki 既有惯例：changelog/revise 注记 + 引用 rounds/0009 evidence 与 T-055/T-057 出处）;产出**修正对照表**（旧表述→新事实→证据出处→落点 file:line）。

## 驱动模型
写码/写文档派 claude-sonnet-5 子代理;主会话独立复验(抽查修正与证据一致性 + wiki diff);**★审查闸**(hopper codex,轮换):修正忠实性(是否与 evidence 逐条一致、无漂移、无夹带契约语义变更)+ 修订标注完整 + 上游处置建议中立性。收敛守卫:第 3 个 MUST-FIX → checkpoint。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| `~/.llm-wiki/agent-app-design/research/pre1-{openclaw,hermes}-source-conformance.md` | 改 | 修正清单 1/2/3 |
| `~/.llm-wiki/agent-app-design/kernel/`（kernel-ecosystem-facts / d6-newapi-integration 等） | 改 | 修正清单 4/5 落点按实况 |
| `~/.llm-wiki/agent-app-design/architecture/`（D4 codegen 相关叙述,若需） | 改 | 修正清单 6 |
| wiki 仓 git commit | commit | 修订完成后在 wiki 仓 commit（`revise:` 前缀惯例）;不 push wiki（wiki push 策略随既有惯例由主会话收官定） |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0010/` + state、`.hopper/` | 写 | 修正对照表 + round 收口 + 审查闸 |

## Disallowed Changes

- 改 D1/D2/D5 等**契约文本的语义**（行为规范/字段定义/状态机——本轮只改 conformance 事实记载与 caveat 注记;若发现某修正必须动契约语义 → 停下记 blocker,归 SG-12 或独立设计轮）。
- 改本仓 `app/`/`kernels/`/三插件;凭证入任何文档（evidence 引用脱敏）。
- 报上游 issue（本轮只写建议草案,发不发由用户决策）。

## One-Variable Strict Mode
- Enabled: no（多文档修订批,同一类操作）。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| 修正对照表 | 每处:旧表述→新事实→证据出处→落点,与 rounds/0009 evidence 逐条一致 | rounds/0010/evidence/ 对照表 |
| wiki diff | 仅 Allowed 文件;修订标注齐;无契约语义变更 | `git -C ~/.llm-wiki/agent-app-design diff` |
| ★审查闸 | PASS/CONFIRMABLE | `.hopper/handoffs/` |

## Runtime Recovery Limits
- Recovery：落点判断偏差/引用链遗漏 → 修订迭代（runtime-recoverable）。
- Cleanup：无运行时资源。

## Rollback Condition
若某修正被审查判定与 evidence 不符或夹带语义变更 → 收残修正;若发现必须动契约语义才能自洽 → 该项停下记 blocker（归 SG-12/独立设计轮），其余项照常收口。

## Human Confirmation Required
- 自动化 + 审查闸：既定授权。
- **hermes 上游 issue 报不报**：本轮产出建议草案,决策在收官时交用户（AskUserQuestion 或收官报告中列明）。
