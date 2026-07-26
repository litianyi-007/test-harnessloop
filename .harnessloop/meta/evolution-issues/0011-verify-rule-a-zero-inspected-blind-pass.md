# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0011
- Priority: P0（非官方模板字段，本批新增，见文末「分类说明」）
- Issue class: skill-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: claude-sonnet-5 subagent（write 任务，orchestrated by 主会话），落地 `docs/harnessloop-evolution-plan-20260726.md` §5 item 1 的定案条目
- Created at: 2026-07-26

分类说明：Record 阶段的 Issue class 枚举无 workflow-gap，比照 TH-0002（同类"SKILL.md/脚本未对某类失败给出信号"问题）的既有分类惯例，归为 skill-gap。Priority 字段非官方模板既有字段（既有 10 条均无此字段），是本批为承载 `docs/harnessloop-evolution-plan-20260726.md` 自带的优先级标注而新增的最小扩展（沿用 Summary 已有的 bullet-list 惯例，未新增章节）。

## Redaction Boundary

- Secrets removed: n/a（无涉密内容）
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（框架级发现，跨 goal 全库语料分析，非绑定单一 goal）
- Active round path: n/a
- State files: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py`（`verify_round()` 内 `if checked_files:` 守卫，原行号 :260 附近）；`harnessloop/adversarial-review-p0.md:164`（m7 发现原文）
- Related handoffs: `.hopper/handoffs/T-061-output.md`（code-review-acceptance，grok，对本条基础数字的独立复算确认）
- Related evidence: `docs/harnessloop-evolution-plan-20260726.md` §2.1 表格行 A、§3.1 E1/E2
- Related reviews: T-061（Verdict: CONFIRMABLE，逐项复算地基数字无出入）
- Related evolution issues: `.harnessloop/meta/evolution-issues/0002-verify-protocol-not-wired.md`（TH-0002：`verify_protocol.py` 当年完全未接入 loop，已修复；本条是接入之后暴露的更深一层缺陷——即便门被正确调用，Rule A 在"本轮零工件"场景下仍会给出与"工件全部合规"完全相同的 passed 信号）

## Expected Harnessloop Behavior

Rule A（scope-lock 包含性检查）及其配套的满分横幅，应当准确反映"本轮是否真的有工件被检查过"。一个从未产出 `evidence/`、`reviews/` 文件的 round，不应该与"产出了工件且全部合规"的 round 得到同一句不带限定条件的 "All mechanical protocol gates passed" 信号。

## Actual Harnessloop Behavior

`verify_protocol.py` 的 `verify_round()` 把 scope-lock 存在性检查与 Allowed Changes 可解析性检查都挂在 `:260` 附近的 `if checked_files:` 守卫之下——当某 round 的 `evidence/` 与 `reviews/` 目录下没有任何文件时（`checked_files` 为空），scope-lock 缺失、Allowed Changes 不可解析这两类问题完全不会被检出。今天（2026-07-26）对本项目实跑 `python3 -B .../verify_protocol.py --project .`，结果 **EXIT=0** 且打印无限定的 `"All mechanical protocol gates passed."`。

但本仓全库 **14 个 round**（goal 001 × 4 + goal 002 × 10）中，有 **9 轮** `evidence/`+`reviews/` 目录下零文件（001/0004 + 002/0001–0008）；Rule A 历史累计只真正判过 **8 个文件**（5 个有工件轮合计：001 为 2+2+1，002 为 2+1）；Rule B 只扫过 **3 个文件**（全部是 goal 001 的 `reviews/adversarial-review.md`，goal 002 十轮 `reviews/` 全部为 0）。也就是说，当前那句满分横幅在 9/14 的轮次里实际含义是"没有东西可检"，而不是"检查过且全部合规"，但横幅文本本身不做这个区分。

此外 Rule A/B 从不扫描 round 根目录、`state/` 目录或业务源码改动本身——这部分覆盖面缺口是本框架自身 P0 轮就已知悬而未决的 **m7**（见 `harnessloop/adversarial-review-p0.md:164`："Rule A 只扫 evidence/、reviews/；对 round 根、state/、项目源码的越界写入完全不可见；且某轮不写 evidence/reviews 时，畸形/缺失 scope-lock 不报错"），标注为"P0-5 不阻塞"后一直挂到今天，尚未有一次真正的正向（负例必红）fixture 关闭过它。

以上数字均由 `docs/harnessloop-evolution-plan-20260726.md` 现场实测给出，并经 T-061（grok 独立复算，`.hopper/handoffs/T-061-output.md`）逐项核对确认无出入。

**补充实测**（并入本条而非另开新 issue，理由见下方 Suggested Upstream Improvement 末尾说明——均出自 T-061 §5「遗漏（非阻塞）」的独立观察）：

1. `extract_allowed_spans` 目前只判"非空"，而真实数据里的 span 可能含脏串（如尾部反引号、`revise:` 前缀这类行文残留）。仅"非空"不足以证明 Allowed Changes 语义有效——这是拟定修复方案（E2）自身承认的已知局限，不应被误读为"E2 绿灯 = scope 声明语义正确"。
2. `rounds/0009` 的评审时序显示过一次"先出现 scope-lock-violation → 回写 agent 把省略号（`.../`）展开为完整路径 → 门变绿"的过程——即通过修改被检产物本身让机械门转绿，而不是被判违规后走 issue/豁免路径。这是 Rule A 结构性空跑这一根因之下，已经在真实语料中发生过的具体病理实例，而非仅仅是理论风险。

## Minimal Reproduction From Files

1. Read: `harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py`（`verify_round()` 内 `if checked_files:` 守卫）
2. Observe: 对本项目 `evidence/`+`reviews/` 为空的任一 round（如 `.harnessloop/goals/20260718-002-agent-app/rounds/0001/`）单独跑 `verify_protocol.py`，scope-lock 缺失或 Allowed Changes 不可解析均不会被报告为 violation
3. Expected next protocol action: 门至少应无条件报告"本轮实际检查了多少个工件"这一遥测事实，使 passed 信号可被正确解读
4. Actual next protocol action: 门无条件打印无限定的满分横幅，不携带覆盖面信息，9/14 轮的 "passed" 实际上是"没东西可检"

## Attempted Local Mitigation

- Evidence refresh: 本条记录时已用 `docs/harnessloop-evolution-plan-20260726.md` 现场实测数字 + T-061 独立复算双重核验，未再重新实跑
- Scope narrowing: n/a（框架级问题，非项目内证据问题）
- Contract revision: n/a
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 无需（本次仅为记录阶段，不涉及写操作）

## Suggested Upstream Improvement

- Candidate target: main skill（`harnessloop-loop` 的 `verify_protocol.py` 脚本）+ 配套 SKILL.md 文档说明
- Proposed smallest change（已定案，见 `docs/harnessloop-evolution-plan-20260726.md` §3.1 E1+E2，**尚未执行**）：
  1. `verify_round()` 把 scope-lock 存在性与 Allowed Changes 非空这两项检查移出 `checked_files` 守卫，对每个 round 无条件执行（包含性判定仍留在守卫内）；不新增 violation kind，沿用既有 `missing-scope-lock`/`unparseable-allowed-changes`。
  2. `verify_round`/`verify_project` 返回 `(violations, coverage)`，累计 `{rounds, rounds_zero_inspected, rule_a_files, rule_b_files, citations_checked}`；`main()` 无条件打印覆盖遥测行，且当 `rounds_zero_inspected > 0` 时禁止打印无限定的满分横幅，改为形如 `passed — rounds=14 rule_a_files=8 rule_b_files=3 citations=N zero_inspected=9` 的输出；`--json` 增 `coverage` 键。exit code 语义完全不变（不能新增绿灯，只能改变"绿的说法"）。
  3. 配套在 `harnessloop-loop/SKILL.md` "Verification Phase" 新增 "Mechanical Gate Boundary" 小节，显式声明机械门的 IN/OUT 范围（IN：scope-lock 存在性/Allowed Changes 可解析性/round 内 evidence·reviews 对 Allowed 的包含性/reviews 内反引号引用存在性；OUT：证据是否支持结论/阈值是否达成/pass 措辞是否诚实/业务代码改动是否越界），并写明"exit 0 不得读作全轮产物都被检过"。
  4. 配套 CI teeth（进 `harnessloop/scripts/validate.py`，不进协议正文）：正向必红——造一个无 scope-lock、无 evidence/reviews 的 fixture round，今天 EXIT=0，改后必须 EXIT=1 报 `missing-scope-lock`；反向必绿——14 个真实 round 跑完 violations 仍为 0；遥测承重反证——把某轮 evidence/ 临时移走，`rule_a_files`/`zero_inspected` 计数必须相应变化；既有 fixture 盲点必须同时修复（`validate.py` 现有每个 fixture 都先 `mkdir evidence/reviews`，与门盲点同构，是门空跑 9/14 轮而 CI 一直绿的根本原因）。
- Why this generalizes beyond this project: 任何安装该插件、且存在"设计/调研类轮次天然不产出 evidence/reviews 文件"这种正常场景的项目，都会撞上同一个"清白轮"与"未检轮"在退出码和横幅文本层面无法区分的问题——不是本项目特有的语料巧合，而是脚本自身的一个结构性守卫位置选择。
- Risks of overfitting: 低——覆盖遥测只新增信息通道，不改变任何现有 exit code 语义；scope-lock/Allowed Changes 脱离守卫后的检查在本仓 14/14 轮实测零新红。上面并入的两条补充（"spans 非空过弱""0009 改被检文件转绿病理"）本身不建议做成新的机械判定面——前者应写进上面第 3 点的 OUT 列作为一句免责声明；后者的应对方式是 E5(b) 审查必查项（"Scope-lock post-hoc edit" 检查，`git log -p -- <round>/scope-lock.md` 核对本轮 scope-lock 是否在 evidence 产出后被修改），而不是再造一个 mtime 类探测器（该类探测器在本仓 0009/0010 两轮实测 2/2 假阳性，已被计划证伪并砍掉，见计划 §3.1 E5 teeth）。

## Resolution

- Resolution status: open（计划已定案，尚未执行——`docs/harnessloop-evolution-plan-20260726.md` §3.1 PR1 = E1+E2，是"先做"五条的第一批）
- Upstream change: 待执行（harnessloop submodule 内尚无对应改动；E2 标注为"B 档：未经独立对抗轮，但结构上无法新增绿灯"，已由 T-061 独立复算确认真实语料零迁移）
- Backported to local policy: no（尚未执行）
- Backport path: 待定 → `harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py`、`harnessloop/plugins/harnessloop/skills/harnessloop-loop/SKILL.md`、`harnessloop/scripts/validate.py`
- Follow-up required: 是——(1) 执行 PR1（E1+E2）后复跑 `python3 -B .../verify_protocol.py --project .`，确认 stdout 含 `rounds=14 rule_a_files=8 rule_b_files=3 zero_inspected=9` 且不再出现无限定满分横幅；(2) 按 CLAUDE.md 既定流程 bump harnessloop 版本、push、`scripts/plugin-reinstall.sh harnessloop`、重启会话后复验；(3) m7（`harnessloop/adversarial-review-p0.md:164`）在本条修复后应可标记为"半闭合"——正向 fixture 首次关闭"某轮不写 evidence/reviews 时畸形/缺失 scope-lock 不报错"这一半，"round 根/state/源码越界不可见"另一半仍未修复，需在上面第 3 点的 OUT 列如实声明，不得过度宣称已全部关闭。
