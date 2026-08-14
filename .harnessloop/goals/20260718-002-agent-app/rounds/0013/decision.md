# Decision

- Feedback: neutral
- Blocker type: human-decision-required（D 探查发现的**会话不持久**是「基本使用」的唯一阻断，但它**不在** L2 清单里，是探查新发现的；另 exec 策略需产品裁决。两者均由用户定，不由主会话扩范围）
- Recovery eligible: yes（工作已交付并复验；下一步是**用户裁决 D 的三个事项**，不是重做）
- Accepted: no
- Review: .hopper/handoffs/T-091-output.md
- Reviewer: codex via hopper T-090b + T-091（scope-lock 指定轮换——rounds/0012 是 grok）
- Review verdict: rework
- Review digest: ea7abc771364d666b0e02fc17fe9e7493a5f75b9b881f765d6b6ea096f4b0105
- Acceptance evals: ran
- Acceptance evals detail: `evidence/runtime/acceptance-evals.json` —— RAE-0001 outcome=**pass**（四条件逐条有冻结原件；复审 T-091 明确「**当前 RAE-0001 的具体实跑可维持 pass**」）
- Active goal: 20260718-002-agent-app
- Active round: 0013（SG-10 L1，两个里程碑轮）
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-11

## Reason

> 前置评审轮产物：`.hopper/handoffs/T-090b-output.md`（同 vendor codex，判 REWORK）。
> 本轮 `Review:` 字段指向复审 T-091；两轮均为本轮 ★审查闸的组成部分。

**为什么 RAE-0001 判 pass，而本轮仍 `Accepted: no`——这是两件事。**

RAE-0001 判的是**这一次实跑**：四条件各自有冻结原件（25 个文件 / 2.99MB 落
`evidence/live/`），条件③ 的对账跑在一份 `hasMore: false` 的**可证完整**的 history 上，
破坏性反证先验 baseline 干净再删、新增差集精确等于被删键。复审逐条核过并明确认可。

本轮不 accepted 的原因是 **★审查闸两轮都判 `REWORK`**，而 scope-lock 写的通过线是
`PASS / PASS_WITH_NOTE`。**按纪律第 4 条「按自己写的字面标准验，不在验收时放宽解释」，
REWORK 就是没过。**

## 审查闸两轮都发现了真问题——这是本轮最有价值的部分

| 轮 | 发现 | 是否属实 | 处置 |
|---|---|---|---|
| T-090b | **RAE-0001 的 pass 靠叙述、不靠冻结证据** | ✅ 属实 | 已冻结全部原件 + 两份带退出码的命令 transcript |
| T-090b | **对账脚本五条假绿路径** | ✅ 属实（附内存合成复现） | 已修，主会话用**自造反例**独立复验 |
| T-090b | **D 把 exec 无审批判为非阻断不成立** | ✅ 属实 | 已更正（见下） |
| T-090b | `public` 暴露面过宽（4 处 + 更小方案） | 属建议非缺陷 | **刻意不做**：收敛守卫（第 3 个 MUST-FIX → checkpoint），登记为下轮候选 |
| T-091 | 条件④ 的 UI 层未覆盖 | ✅ 属实 | 已补：壳指向死端口 → UI 红色横幅（截图） |
| T-091 | 五条里**还剩两条**假绿（wire 侧 role 缺失被静默过滤 / bool 与 int 因 `True == 1` 混淆） | ✅ 属实 | 已修，主会话独立复验 |
| T-091 | 证据卫生：`<SESSION_KEY>` 字面量、0 字节日志、计数写错 | ✅ 属实 | 已逐条更正并注记 |

**未派第三轮评审**：收敛守卫已触发并已向用户 checkpoint。两条残留由主会话用**自己构造的**
反例独立复验（wire role 缺失 → 红；`seq=true` vs `seq=1` → 红；history 含合法 user → 仍绿，
未误杀；真实原件 → PASS exit 0；`--drop-one` → exit 1 精确捕获）。
**是否需要第三轮评审才算过，交用户裁决。**

## Main-Session Decision On Scope Boundary

1. **`docs/validation-log.md` 中途补入 Allowed Changes** —— `CLAUDE.md` 的沉淀钩子规定收盘要写它，
   起草 scope-lock 时漏列。**显式改 scope-lock 而非默默越界**（纪律第 4 条）。
2. **hopper 缺陷未在 submodule 内开 issue** —— scope-lock 明文禁改三插件 submodule，
   缺陷完整取证落在本轮 evidence + `docs/validation-log.md`，开 issue 留待授权。
3. **Q3 的 public 收窄不做** —— 收敛守卫。

## Human Decision Required

1. **会话不持久（阻断）** —— app 重启后会话从界面全部消失（内核库 5 行 / UI 0 行 /
   重启后的壳**连 wire trace 都没生成**，即从不尝试拉取）。**不在原 L2 清单内。**
   数据没丢：history 接口可用、对账已验证、`SESSION_KEY` 的坑已踩掉。**要不要开一轮做？**
2. **exec 策略（性质已升级）** —— 不再是「要不要做审批 UI」，而是「日常壳采用哪种 exec 策略」：
   `deny` / `allowlist` / `ask + 审批 UI`（须先闭合审批 RPC，否则真挂起）/ 真实 sandbox 内显式 `full`。
   **未配置的 `full/off` 不能当安全默认。**
3. **是否需要第三轮 ★审查闸**才认为本轮通过。
4. **kata schema 提案**：tag taxonomy 加 `deepseek`（未自行应用）。
5. **hopper 缺陷是否授权在 submodule 内开 issue / 修**。

## Open Questions Resolved

- **条件③ 的对账在技术上可行吗** → 可行且已跑通。两侧 `(messageId, messageSeq)` 同源同键
  （同一个 `attachOpenClawTranscriptMeta`），在真实录制数据上三处 id 全等。
- **`kernelSessionID` 能不能当 history 的 key** → **不能**，是两个独立字段，用错会查到不存在的会话。
- **exec 无审批是隔离配置的特例还是默认** → **是未配置时的默认**（`exec-approvals.ts:317-318`
  `DEFAULT_SECURITY="full"` / `DEFAULT_ASK="off"`），且**独立 state/workspace 不是进程 sandbox**。
- **「基本使用」还缺什么** → 只缺一件，但那件是阻断：会话持久化。

## Open Questions Remaining

- B3 服务端 dispatch 竞态（需改 `app/contracts/`，scope blocker）。
- 协议级无丢帧（条件③(d) 显式列为内核已知缺口）。
- 七处 `TODO (owner: user)`；TH-0031 修法方向。
- 三插件是否 bump 版本并 push。

---

## 后记（2026-08-11）：★审查闸第三轮 T-092 判 **PASS_WITH_NOTE**

用户裁定补派第三轮。codex 复验后判 `PASS_WITH_NOTE`：

> 两条影响可信度的假绿已真正闭合，合法输入与冻结原件均无回归；剩余问题仅是证据说明中的
> 字节数和「本文件为空」措辞不精确，不足以要求再次 REWORK。

两条 note 已处置（`ui-diag-badport.log` 首句自相矛盾已改；易漂移的总字节数已去掉）。

**三轮轨迹**：T-090b REWORK → T-091 REWORK → **T-092 PASS_WITH_NOTE**。
三轮提出的每一条主会话都逐条核过，**无一条是错的**。

### 但本轮 `Accepted:` 维持 `no`，不回填为 yes

理由与 rounds/0012 的先例一致：**收盘时的判定记录收盘时的事实。**
0013 收盘那一刻，审查闸确实是 REWORK、证据确实没冻结、脚本确实有假绿。
事后把它改成 yes，等于让「验收结论」变成可回溯调整的量——那正是 0012
「改标准不追溯」要防的东西。

**这不影响任何东西的推进**：0014 已开轮并接近完成，`Accepted` 只是历史标签。
真正有意义的是这条轨迹本身——它记录了「一次实跑合格、但论证不合格」是什么样子。

**若用户认为应回填，说一声即可改**；主会话不自行翻案。
