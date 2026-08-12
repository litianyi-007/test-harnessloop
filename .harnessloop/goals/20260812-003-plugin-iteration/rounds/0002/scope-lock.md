# Scope Lock — goal 003 / rounds/0002

**开轮时间**：2026-08-12，**动手之前**写就。

## Round Objective

**修 hopper 缺陷 ④：`queue.js` 的列解析按下标静默取值，brief 内未转义的 `|`
会截断 brief 并顶掉 Vendor 列。**

## 开轮前的同步核实（用户要求，CLAUDE.md 第 0 步）

| 项 | 结果 |
|---|---|
| submodule vs 上游 | **0 落后 / 0 领先**（`2ea97aa` / v0.55.1），工作区干净，安装缓存一致 |
| 远端未合入分支 | 两个（`codex/grok-recovered-…`、`fix/copilot-agy-connectivity`），**经 `merge-base --is-ancestor` 判定均已合入 main** |
| ④ 是否仍在代码里 | **是**，实测 brief 被截成 `"前半段任务"`、vendor 仍解析成 `codex`、**零报错** |

## 缺陷定位

`cli/src/queue.js`：

- `:84` `parseRowCells` —— `trimmed.split('|').map(c => c.trim())`，**按竖线无脑切**
- `:110` `extractRow(cells, map)` —— 之后一律**按下标取**：`cells[map.briefIdx]`（`:140`）、
  `cells[map.vendorIdx]`（`:141`）等
- **没有任何一处校验「行的 cell 数是否等于表头列数」**

后果：brief 里出现字面量 `|` 时，该行被多切出若干 cell，`briefIdx` 之后的所有列
整体右移。**竖线后若恰好是一个已批准的 vendor 名，`assertVendorApproved` 也拦不住
（它拦的是「vendor 名不认识」，不是「brief 被截断」）**，于是静默派出半份任务书。

## 修法方向（实现方可提出更好的，但须说明理由）

**行的 cell 数与表头列数不一致时 fail-closed 拒绝该行，并报明确错误**，
错误信息须提示「brief 里的 `|` 需转义为 `\|`」。**不要**按下标继续取值。

**必须一并考虑**：现有 `.hopper/queue.md` 里是否有行会因此变红——若有，
**如实报告并停下问，不得为了让它绿而放宽判据**。

## 本轮不做

- **不修缺陷 ⑤**（结构性正文冒充有效 spec）—— 它的判据设计更容易过度收紧，
  留独立轮。本轮若顺手发现 ⑤ 的更多信息，只登记不修。
- **不改 `cli/src/tasks.js`** —— 其 `composePrompt` 形状被 4 条逐字节断言锁死。
- **不清理隔离实例的凭证残留**（TH-0032）—— 属 `write-safety-required`，本轮不申请。
- **不起隔离实例**。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `hopper-plugin/cli/src/queue.js` | 改 | 仅列数校验与相关错误信息 |
| `hopper-plugin/tests/unit/` | 写 | 回归测试 + 破坏性反证载体 |
| `hopper-plugin/docs/archive/ISSUES.md` | 改 | 仅把 ④ 由 Open 移入 Closed 并注明版本 |
| `hopper-plugin/CHANGELOG.md` | 改 | 新版本条目 |
| `hopper-plugin/package.json` | 改 | 版本 bump（其余版本位置由发现式守卫枚举） |
| `.harnessloop/goals/20260812-003-plugin-iteration/rounds/0002/` | 写 | 本轮全部产物 |
| `.harnessloop/state/current.md` | 改 | 轮次指针与收盘态 |
| `docs/validation-log.md` | 改 | 闭环条目 |
| `.hopper/queue.md` | 写 | 异构评审任务行 |

**版本位置不逐个列举**——以 `tests/unit/version-discovery.test.js` 这条**发现式守卫**
为准。**清单会过时，发现式守卫不会**（本项目已四次证明）。

## Disallowed Changes

- `cli/src/tasks.js`、`tests/integration/`
- `harnessloop/`、`kata/` 两个 submodule
- `app/` 下任何文件（属 goal 002）
- **为了让既有 `.hopper/queue.md` 通过而放宽判据** —— 若既有行触发新校验，
  **改的是那些行，不是判据**

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 破坏性反证 | **先看到红**：拆掉列数校验，新测试必须变红并留下实际输出 | 红的原文 |
| 主会话独立复跑 | `npm test` 全绿，由主会话自己跑 | 退出码**直接捕获**，不经管道 |
| 端到端 | **真派一个 brief 含转义竖线的 queue 行任务**，vendor 收到完整 brief | vendor 产物 |
| 反向：非法行被拒 | 构造未转义竖线的行 → 明确报错而非静默截断 | 错误输出原文 |
| 既有 queue 不破 | 本仓 `.hopper/queue.md` 全部行仍可解析（或如实报告哪些需转义） | 解析结果 |
| vendored 同步 | `sync-vendored-plugin.mjs --check` exit 0 | 退出码 |
| 版本一致 | `version-discovery.test.js` 绿 | 测试输出 |
| 装上去复验 | `plugin-reinstall.sh hopper` 后用**安装产物**复验 ④ 已修 | 复验输出 |
| 机械门 | `verify_protocol.py` exit 0 | **含读第 2 行** |

## 异构评审

代码改动完成后派**单路**只读评审（codex 或 grok 随机）。改动面小且判据清晰，
双路留给设计类或大改动。**评审若判 REWORK，按 feedback-policy 处理，不绕过。**

## 主会话的开轮判断

- **④ 先于 ⑤**：④ 严重度中高且修法边界清晰（列数校验）；⑤ 的判据容易过度收紧，
  需要单独想清「除结构性标记外还有别的」怎么表达才不误伤合法 spec。
- **既有 queue.md 若因新校验变红，那是发现不是障碍** —— 说明本仓一直有行在
  依赖这个静默行为。如实报告。
