# Scope Lock — goal 003 / rounds/0003

**开轮时间**：2026-08-13，**动手之前**写就。

## Round Objective

**修 hopper 缺陷 ⑤：`loadTaskSpec` 把「正文只有结构性标记」的小节当成有效 spec。**

实测（当前代码，`otherTaskIds` 已传）：

| leader-tasklist 内容 | 现在的结果 |
|---|---|
| `## T-1` + `---` | 被接受，返回 `"## T-1\n\n---"` |
| `## T-1` + `\|---\|---\|` | 被接受 |
| `## T-1` + `>` | 被接受 |

vendor 会收到一份「Task spec」一节里只有一条分隔线的任务书。

## 这一条为什么单独开轮

rounds/0002 里我明确把它排在后面，理由是：**它的判据比 ④ 容易过度收紧**。
④ 是数格子，边界清晰；⑤ 要回答「什么算实质内容」，而**正文里合法包含表格、分隔线、
引用块的 spec 必须仍被接受**。

**判据方向**：不是「不含结构性标记」，而是「**除了结构性标记之外还有别的**」。

## 本轮不做

- **不改 `cli/src/tasks.js`** —— 其 `composePrompt` 形状被 4 条逐字节断言锁死。
  `composePrompt` 缺空 spec 纵深防御是同族的另一条，**已登记，本轮不修**。
- **不动 `cli/src/queue.js`** —— rounds/0002 刚改过，本轮不叠加。
- 不起隔离实例；不清理 TH-0032 的凭证残留（`write-safety-required`）。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `hopper-plugin/cli/src/dispatch.js` | 改 | 仅 `loadTaskSpec` 的实质内容判据 |
| `hopper-plugin/tests/unit/` | 写 | 回归测试 + 反证载体 |
| `hopper-plugin/docs/archive/ISSUES.md` | 改 | 仅 ⑤ 的 Open → Closed 与计数 |
| `hopper-plugin/CHANGELOG.md` | 改 | 新版本条目 |
| `hopper-plugin/package.json` | 改 | 版本 bump（其余位置由发现式守卫枚举） |
| `.harnessloop/goals/20260812-003-plugin-iteration/rounds/0003/` | 写 | 本轮全部产物 |
| `.harnessloop/state/current.md` | 改 | 轮次指针与收盘态 |
| `docs/validation-log.md` | 改 | 闭环条目 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `cli/src/tasks.js`、`cli/src/queue.js`、`tests/integration/`
- `harnessloop/`、`kata/` 两个 submodule；`app/` 下任何文件
- **为了让判据「好看」而牺牲合法 spec** —— 见下方红线

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| **欠拒绝**：结构性正文被拒 | `---`、`\|---\|---\|`、`>`、空列表符、多者组合，**全部返回 null** | 逐例输出 |
| **过度拒绝**：合法 spec 不受影响 | 正文含真实表格（有数据行）、含分隔线但也有正文、含引用块且有内容、纯一句话，**全部被接受且内容完整** | 逐例输出 |
| 破坏性反证 | **先看到红**，且**先验证注入命中** | 红的原文 + 注入命中数 |
| 主会话独立复跑 | unit **和** integration 两套都跑 | 退出码直接捕获 |
| vendored 同步 | `--check` exit 0 | 退出码 |
| 版本一致 | `version-discovery.test.js` 绿 | 输出 |
| 装上去复验 | `plugin-reinstall.sh` 后用**安装产物**复验 | 输出 |
| 端到端 | 真派一个 leader-tasklist 只有结构性正文的任务 → 应 fail-closed 拒绝派发 | 输出 |
| 机械门 | exit 0，**且读第 2 行** | 输出 |

**注**：`npm test` 只跑 `tests/unit/`。rounds/0002 已实证它能藏住 4 条集成失败，
**本轮两套都跑，不重蹈**。

## 红线

- **过度拒绝比欠拒绝更糟。** 一个合法 spec 被判成「无内容」会让本能跑的任务
  fail-closed 停掉，而缺陷 ⑤ 的现状只是「偶尔送出一份空任务书」。
  **若两者不可兼得，宁可保留少量欠拒绝，也不要误伤合法 spec**，并如实写进 CHANGELOG。
- **不得为了让判据通过而调整测试用例。** 用例先定，判据后写。

## 异构评审

改动完成后派**单路**只读评审。重点问三件事：①判据有无过度收紧
②有无可绕过的结构性标记组合 ③是否引入了新的静默失败形状。
