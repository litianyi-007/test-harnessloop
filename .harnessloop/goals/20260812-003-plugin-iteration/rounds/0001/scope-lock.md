# Scope Lock — goal 003 / rounds/0001

**开轮时间**：2026-08-12，**动手之前**写就（对照 002/rounds/0017 的事后补录）。

## Round Objective

**PG-1：把「静默失败」的判定标准写死，并用 5 个已知实例回测它。**
**PT-2：kata 走通一次真实使用闭环，同时记录 kata 自身暴露的问题。**

### 为什么 PG-1 必须是第一轮

本 goal 的成功条件是**按轮计数**的（连续 5 轮无静默失败）。**判据不先立，
计数从第一轮起就悬空**——没有标准就无法判「这一轮算不算达成」。
所以先让判据自证：拿它去判 5 个已知实例，判不中就说明标准不成立。

### 为什么同轮做 PT-2

kata 是三插件里**唯一长期没被真实调用过**的（rounds/0011–0012 期间 0 次）。
它的风险不是缺陷多，是**根本没被验过**。而 PG-1 的产出（判定标准）本身就是
一份「跨轮可复用的事实」——正好是 kata 的沉淀对象，两件事天然咬合。

## 本轮不做

- **不改任何插件源码**（harnessloop / hopper-plugin / kata 三个 submodule 均不动）。
  本轮是判据建立 + 真实使用，发现的问题**只登记不修**。
- **不清理隔离实例的凭证残留**（TH-0032）。控制契约明写「删除与覆盖不在预授权内」，
  该动作属 `write-safety-required`，须用户逐次确认——**本轮不申请**。
- **不起 openclaw / hermes / d3proxy 隔离实例**。PT-2 用 kata 不需要。
- **不派第三方 vendor 做实现类任务**（既定纪律）。本轮是否需要异构评审见下。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `.harnessloop/goals/20260812-003-plugin-iteration/rounds/0001/` | 写 | 本轮全部产物：scope-lock、evidence、round-summary、decision |
| `.harnessloop/goals/20260812-003-plugin-iteration/goal-breakdown.md` | 改 | 仅 PG-1 / PT-2 的状态列与回测结论 |
| `.harnessloop/state/current.md` | 改 | 活动轮指针与收盘态 |
| `.harnessloop/state/evidence-index.md` | 改 | 本轮证据登记 |
| `.harnessloop/meta/self-audit.md` | 写 | 本轮自审 |
| `docs/validation-log.md` | 改 | 收盘条目 |
| `~/.llm-wiki/test-harnessloop` | 写 | PT-2 的沉淀产物（kata 主场） |

**注**：路径一律写全，不用 `…` 省略号——省略号是字面量，词法匹配不上，
002/rounds/0017 初稿因此报过两条 `scope-lock-violation`。

## Disallowed Changes

- **三个插件 submodule 的任何文件**（`harnessloop/`、`hopper-plugin/`、`kata/`）
- **`app/` 下任何文件** —— 那属 paused 的 goal 002
- **删除或覆盖任何既有文件** —— 不在预授权内
- **`.harnessloop/local/`、任何 `.env`** —— 凭证区，本轮无需触碰
- **为了让判定标准「好看」而调整标准本身** —— 回测判不中就如实记判不中，
  不得反过来改标准去迁就结果。**这是本轮最关键的一条红线**：判据的价值全在于
  它是先立后用的。

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| PG-1 判定标准可操作 | 标准能被第三方按字面执行，不依赖「我觉得」 | 标准文本 + 逐条判定理由 |
| PG-1 回测 | **5 个已知实例全部被判中**；判不中的如实记录并说明标准的不足 | 逐实例的判定过程与结论 |
| PG-1 反向检验 | 至少 1 个**不属于**静默失败的真实缺陷被正确排除 | 该缺陷的判定过程 |
| PT-2 kata 真实调用 | 至少 1 次完整的 kata skill 调用产出可用结果 | 调用记录 + 产出文件路径 |
| PT-2 沉淀落地 | `~/.llm-wiki/test-harnessloop` 新增/更新页，符合 teach-back 形状 | 页面路径 + index/log 更新 |
| PT-2 问题登记 | kata 使用中暴露的问题逐条登记（无问题则明说「无」） | 问题列表或「无」的明确记录 |
| 机械门 | `verify_protocol.py` exit 0 / violations 0 | 直接捕获退出码，不经管道 |
| 未越界 | 三插件 submodule `git status` 干净 | `git -C <each> status --porcelain` 为空 |

## 异构评审

**本轮预计需要一道**：PG-1 的判定标准是后续所有轮次的基础，标准本身若有盲区，
后面每一轮都会继承。拟在标准写成后派**单路**只读评审（codex 或 grok 随机），
问三件事：①标准有无可被绕过的表述；②5 个实例的判定理由是否成立；
③有没有第 6 类静默失败形状是这份标准覆盖不到的。

**不派双路**：本轮无代码改动，风险面小于 hopper 那批；双路留给有代码改动的轮次。

## 主会话的开轮判断

- **本轮不设成功/失败的二元验收**：PG-1 若回测判不中某个实例，**那也是有效产出**——
  它说明标准需要修，而不是本轮失败。**真正的失败是「改标准去迁就回测结果」。**
- **PT-2 若 kata 用起来没暴露任何问题，如实记「无」**，不为了凑「验证了插件」而编问题。
  「用了一次没发现问题」本身就是一条关于 kata 的信息。
