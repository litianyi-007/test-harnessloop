# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-108-codex-output.md
- Reviewer: codex via hopper T-108（单路，按 scope-lock）
- Review verdict: **REWORK**（两条发现主会话全部独立复现后返工；返工未再评审，见下）
- Review digest: 90c6eb81027f66b5b718d807d46e391e49d5b190c3697001801b6c1e3d2794ff
- Acceptance evals: none — 本 goal 无 runtime eval 台账；验收走 `goal.md` 七条标准
- Acceptance evals detail: n/a
- Active goal: 20260812-003-plugin-iteration
- Active round: 0003
- Decision maker: main session（claude-opus-5[1m]）
- Timestamp: 2026-08-13

## Reason

**`Accepted: yes`。** 缺陷 ⑤ 已修，七条验收标准逐条满足，硬判据全部由主会话独立复跑。

**本轮最有价值的一条是评审踩中了我自己写的红线。** scope-lock 明写「过度拒绝比
欠拒绝更糟」，而第一版实现恰恰过度拒绝了——`hasSubstantiveContent` 先 `trim` 再判，
**把缩进信息毁掉**，于是用缩进代码块举例展示 `---` 的合法 spec 被整节判死。

**修法换了原则而不是打补丁**：代码块是作者显式标记的字面内容，判据不该往里面看。
围栏行本身算结构，围栏内部与缩进行一律算内容、连判定都不进。

## 独立复核（全部主会话自己跑）

| 判据 | 结果 |
|---|---|
| 评审两条发现 | **全部复现属实**（误拒 3 例 + 欠拒绝 6 例） |
| 返工后 | 那 9 例 **9/9 全修**，原有 14 例 **14/14 不变** |
| unit / integration | **1416 pass / 0 fail** ／ **7/7** |
| P2 诊断可区分 | 三种原因各说各的话，成功路径不设 reason |
| `tasks.js` / `queue.js` | diff 均 0 行 |
| 安装产物复验 | 4/4 |

## Main-Session Decision On Scope Boundary

1. **给自己定了迭代上界** —— 派返工时明写：若下一轮评审仍在「误拒合法内容」那一类上
   有发现，就把残留如实登记、收轮，转去 app 线。**用户的主诉求是 app，hopper 是手段。**
2. **残留不宣称穷尽** —— CHANGELOG 明写「已知，不穷尽」，并列出裸子标题、孤立 `**`、
   HTML 注释、`===` setext 下划线、其它不可见 Unicode 五类仍会通过。
   上上个版本因夸大被抓过一次。
3. **返工后未再评审即发布** —— 与 rounds/0002 同。**已补派确认审 T-109（背景运行），
   若有发现按跟进轮处理，不回滚。** 这次不是「没做」，是「并行做、不阻塞主线」。

## Human Decision Required

- **无阻断项。**

## Open Questions Resolved

- **「什么算实质内容」的判据边界** → **代码块必须整体豁免**。作者用缩进或围栏标记的
  内容是显式的字面内容，任何「看起来像结构」的判定都不该进入其中。
- **一个 null 该不该携带原因** → **该**。三种成因（没文件/没小节/纯结构）在调用链里
  被抹平成一种时，用户拿到的诊断会把排查引到错方向——**这本身就是同族缺陷**。

## Open Questions Remaining

- 残留的五类结构性形状（见上）未修，如实登记。
- `composePrompt` 对空 spec 无纵深防御（`tasks.js:169`，该文件被逐字节断言锁死）。
- **连续两轮「返工后未再评审即发布」**——本轮已用并行补审缓解，但流程本身是否该
  固定为「返工必补审」，未决。
