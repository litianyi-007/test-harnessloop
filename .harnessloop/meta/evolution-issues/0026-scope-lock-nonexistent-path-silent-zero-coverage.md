# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0026
- Priority: P1
- Issue class: mechanical-gate
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28）
- Created at: 2026-07-28

**scope-lock 授权一个不存在的路径 ⇒ Rule A 静默零覆盖，门照绿。** 本仓自查发现两例真实误写。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

对本仓自身跑机械门（`verify_protocol.py --project .`，exit 0，零违规）时，coverage 行显示：

```
rounds=14  rule_a_files=8  zero_inspected=9
```

**14 轮里 9 轮 Rule A 一个文件都没查**，而门是绿的。追下去发现其中两例是**误写路径**：

| 轮 | scope-lock 里声明的 span | 该路径是否存在 | scope-lock 自己的位置 |
|---|---|---|---|
| 0008 | `.harnessloop/rounds/0008/` | **否** | `.harnessloop/goals/20260718-002-agent-app/rounds/0008/scope-lock.md` |
| 0009 | `.harnessloop/rounds/0009/` | **否** | `.harnessloop/goals/20260718-002-agent-app/rounds/0009/scope-lock.md` |

真实轮目录路径中间有 `goals/<goal>/` 一段，被漏掉了。**授权指向空气**：Rule A 在该 span
下找不到任何文件，因而零违规、零覆盖，exit 0。

写 scope-lock 的人以为自己授权了本轮目录；机械门以为自己检查了；**两边都"通过"了，
实际什么都没发生。** 这正是本项目反复命中的「绿灯 ≠ 真守门」。

## Impact

- `zero_inspected` 这个计数**已经存在**并如实报了 9，但它**不产生违规、不进任何判定**，
  实践中没人看。诚实的计数器 + 无人消费 = 与不存在几乎等价。
- scope-lock 的**核心用途就是限定本轮可改范围**。一个指向不存在路径的 scope-lock，
  等于该轮**没有范围约束**——而门对此完全沉默。
- 这不是 0008/0009 两轮的偶发笔误：路径里带 `goals/<goal-slug>/` 一段，**手写极易漏**，
  且漏了之后**没有任何反馈**。

## Proposed direction（含一条必须避开的陷阱）

### ❌ 陷阱：不要用「声明的路径在磁盘上是否存在」来判

那是一条 **(今天层, 轮 N) join**：scope-lock 属于轮 N，磁盘存在性属于今天。后果有二——

1. 今天删掉/移动一个目录，就会**追溯判红已收盘轮**，撞 v0.12.0 的 E1 纪律；
2. 这正是 2026-07-28 两路独立评审（五面 5/5 + T-079 grok）判定并从 v5 契约撤回的那类判定。

### ✅ 层内做法：拿 scope-lock 的 span 和 **scope-lock 自己的位置** 比

两个操作数都在轮 N（span 文本 + 该文件自身的路径），**跨层调用点不存在**——与 v0.27.0
（三操作数同轮）、v0.28.0（两操作数同轮）同一形状。可判的性质：

> 一个**形如轮目录**的 span（匹配 `.../rounds/<NNNN>/`），其 `<NNNN>` 若等于本轮编号，
> 则该 span 必须**就是**本轮目录路径；不是则说明写错了。

0008/0009 两例都会被这条抓到：它们声明 `.harnessloop/rounds/0008/`，而本轮目录是
`.harnessloop/goals/20260718-002-agent-app/rounds/0008/`——**同一个轮号，不同的路径**。

### 落地层次：先做 hint，不做违规

直接判违规会**追溯判红 0008/0009 两个已收盘轮**，唯一"修法"是改历史产物（撞 E1）。
按 TH-0008 的 `fixed-by-demotion` 先例，**先落在提示层**：
新增 coverage 计数 + 门输出一条非阻断 note，让下一轮写 scope-lock 的人当场看到。
**待本仓不再有存量误写后**，再评估是否升为违规（升级要另开 issue，不在本条内顺手做）。

## Residual（如实登记，不藏）

- 本条只抓「**轮号对得上但路径不对**」这一种形状。scope-lock 里其它写错的路径（打错的
  目录名、已改名的模块）**抓不到**——抓它们需要磁盘存在性，即上面那条被禁的 join。
- 另外 7 个 `zero_inspected` 轮**不是**这个原因（`Allowed Changes` 段本就没有 span，
  或 span 是 `$harnessloop-setup` 这类 skill 名、`~/.llm-wiki/...` 这类项目外路径）。
  **本条不覆盖它们**，是否要管另议。
- `zero_inspected=9` 这个数**本身就是既有的诚实上界**——它一直如实在报，只是没人消费。
  本条的价值主要在于**让其中一类变得当场可见**，不在于把 9 变成 0。

## Next Action

- Owner: 主会话
- 依赖：无（与 runtime-evals 竖切线互不相干，可并行）
- 先决：实现前先确认「形如轮目录的 span」正则不会误伤合法写法
  （如同时授权本轮目录与另一轮目录的证据——**这种写法是否合法本身需要先裁**）
