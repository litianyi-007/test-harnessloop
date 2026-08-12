# Scope Lock — rounds/0017（**事后补录，2026-08-12**）

## 这份文件的性质：补录，不是契约

**先说清楚它不是什么。** scope-lock 的作用是在动手**之前**把范围钉死，让越界当场可见。
这一份是在工作**完成之后**写的，**它不具备那个作用**，不能被当成「本轮受过范围约束」的证据。

**为什么会有这个目录**：hopper 的 brief-drop 缺陷修复是走 `/plan` 驱动的，
**没有按协议开轮**——`state/current.md` 的 active round 至今仍是已收盘的 `rounds/0016`，
`goal-breakdown.md` 里也没有 0017 的任何登记。这个目录是主会话归档 evidence 时
顺手建出来的，随后 `verify_protocol.py` 报 `missing-scope-lock`。

**两种收法，用户 2026-08-12 裁定补 scope-lock**（另一种是把 evidence 移出 `rounds/`
让 0017 不存在）。补的理由：那批工作确有明确范围与验收，如实记录比抹掉痕迹好。

## 实际做了什么（据实回填，非计划）

**被测插件 hopper 自身的高严重度缺陷修复与发版**，不是 app 侧工作。

queue.md 有行、`handoffs/leader-tasklist.md` 无该 task 条目时，`loadTaskSpec()` 的两条
未命中分支**返回自述文案冒充 spec**，其中一句还写着「using queue.md brief only」，
而 brief 根本没进 prompt。vendor 收到一份没有任务的任务书，照样
`exit 0` / `status: done`。**三个绿灯全亮而任务没送到。**

## Allowed Changes

> 据实回填（本节标题必须逐字为 `## Allowed Changes`——`verify_protocol.py:924`
> 用 `stripped.lower() == "## allowed changes"` 精确匹配，加任何后缀都会让整节
> 不被解析，报 `unparseable-allowed-changes`。本文件初稿就栽在这上面。）

| Path | Action | Limit |
| --- | --- | --- |
| `hopper-plugin/cli/src/dispatch.js` | 改 | 缺陷修复主体；**`cli/src/tasks.js` 一字未改**（其 `composePrompt` 形状被 4 条逐字节断言锁死） |
| `hopper-plugin/tests/unit/` | 写 | 新增回归测试与发现式守卫 |
| `hopper-plugin/docs/archive/ISSUES.md` | 改 | issue 登记与闭合 |
| `hopper-plugin/CHANGELOG.md` + 各版本文件 | 改 | 发版 |
| `.hopper/queue.md`、`.hopper/handoffs/` | 写 | 三轮异构评审（T-099 设计审、T-100 代码审、T-102/T-103 复审）+ 端到端探针 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0017/` | 写 | 设计裁决记录、主会话破坏性反证、本 scope-lock（**路径必须写全：`…` 省略号是字面量，词法匹配不上，初稿因此报了两条 `scope-lock-violation`**） |
| `docs/validation-log.md` | 改 | 闭环条目 |
| `~/.llm-wiki/test-harnessloop` | 写 | 跨轮可复用事实（kata 主场） |

## Disallowed Changes

- **不改 `cli/src/tasks.js` 的拼装形状** —— 已核：`git diff` 为空
- **不改 `tests/integration/`**
- **实现类不派第三方 vendor** —— 一律主会话 Sonnet 子代理（用户决策 2026-07-17）
- **push 前必须 bump 版本** —— 已执行（0.54.0 → 0.55.0）

## Verification Commands Or Checks

| Check | Expected | 实际 |
| --- | --- | --- |
| 单元测试 | 全绿 | **1345 pass / 0 fail / 2 skipped** |
| vendored 同步 | exit 0 | exit 0 |
| `tasks.js` 未改 | diff 为空 | 为空 |
| 边界形态探针 | 全过 | 主会话自建 **15 例 15/15** |
| 破坏性反证 | **先看到红** | **四轮，每轮先红**（判据回退 3 红 / 拆 H2 边界泄漏 / 放宽 `##+` 截断 / 实现方侧 2 红与 4 红） |
| 端到端 | brief 真达 vendor | **queue 行**真派 codex + grok，两家都回出指纹 |

## 本轮的实际问题与如实记录

- **三轮评审在「修好了」里又挖出两层**：codex 两判 REWORK 且两次都对；第二层
  （跨任务边界失效，T-1 拿到 T-2 的正文）**比原缺陷更糟**。
- **第一版边界修复被主会话打回**：实现方把边界写成「替代」而非「并集」，
  **真实派发路径一度比修复前更差**。
- **根因 (b)（边界正则与 marker 正则形态不一致）两家评审都没点出**，是主会话复现时发现的。

## 与协议的偏离（必须留痕）

1. **未按协议开轮** —— 无 `scope-lock`（本文件事后补）、无 `decision.md`、
   `state/current.md` 未指向本轮。
2. **本轮无 `decision.md`，且不补** —— 补一份事后的验收裁决会比补 scope-lock 更失真：
   scope-lock 至少能如实回填「做了什么」，而 `decision.md` 的语义是「依据当时证据作出的
   验收判断」，事后写等于伪造判断时点。**本轮的验收结论以 `docs/validation-log.md`
   的条目与三轮评审产物为准。**
3. **归属存疑** —— 本轮是插件修复轮，挂在 app goal（`20260718-002-agent-app`）下
   并不贴切。留此一笔，供后续决定是否该为「插件迭代」另立 goal。
