# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0030
- Priority: P3
- Issue class: mechanical-gate
- Status: open（**刻意保留，非遗漏**）
- Source project: test-harnessloop
- Created by: 主会话（评审价值配对实验的处置尾巴）
- Created at: 2026-07-30
- 基线版本: harnessloop v0.38.0（validate 758 项 0 失败，CI 三平台全绿）

**13 对异构评审处置后剩下的 8 条 low——全部 hint-only 或极性保守，不影响退出码。**

## Redaction Boundary

- Secrets removed / Private data removed / Raw logs omitted: n/a
- Safe evidence summaries only: yes

## 来源与已处置部分

13 对配对评审（`docs/review-value-experiment-result-20260729.md`）共约 115 条声称，
去重 26 个候选，五族并行**逐条对 HEAD 实测**：

| | 条数 |
|---|---|
| live | **23** |
| fixed（先前提交已修） | 3 |
| **not-verified** | **0**——每条都有实跑命令与输出，无一条凭读代码下判断 |

**已在 v0.38.0 修掉 13 条**（1 blocker + 7 high + 5 medium），并加了两条类级守卫
（G52 bool 陷阱 / G53 NUL 异常），validate 634 → 758。

## 本条保留的 8 条 low（**全部已实测复现**）

| # | 缺陷 | 为什么这次不修 |
|---|---|---|
| 1 | `_span_path_segments` 保留 `..` 而 Rule A 用 `normpath` → `.../rounds/0008/../../../../rounds/0008/` 折叠后落在缺 slug 的经典位置，TH-0026 判 mismatch=0（**纯路径代数假阴性，不需磁盘 join**） | hint-only，不影响退出码 |
| 2 | TH-0026 只查 span 里**第一对** `rounds/<NNNN>`（首次匹配即 break）→ `.harnessloop/rounds/0007/../rounds/0008/` 的第二对前缀永不被检查 | 同上 |
| 3 | TH-0026 **误报**：`app/game/rounds/0008/level.json`、`docs/rounds/0008/x.md` 也被标记（算法不要求 `rounds/<NNNN>` 位于 `.harnessloop` 命名空间内） | hint-only，但**本项目 app 侧若有此类目录会常年噪声** |
| 4 | `collect_zero_inspected_round_notes` 的容器逃逸洞：coverage `zero_inspected=0` 却产出 1 条 note，打破其 docstring 的承诺 | hint-only；整体仍被 `round-container-escapes-project` 兜住 |
| 5 | 逃逸的 `evidence/` symlink 下 `_is_contained` 两侧同时 canonical 到项目外 → `check_round_eval_ledger` 单独看是绿的 | **实跑确认 `verify_project` 整体仍红**（`round-container-escapes-project`，exit=1） |
| 6 | `Predecessor` 存在性用 `is_dir()` 跟随 symlink，指向项目外或另一 goal 都被接受 | 同上，整体被兜住 |
| 7 | `check_evidence_index_all_valid` 不是 Kleene 逻辑：已确定 False 后遇第一个非枚举单元格仍 `return None, True` | **极性保守**（漏报不误报），且污染的是计数器不是判定 |
| 8 | `rae-system-undeclared` 的 detail 文案在声明文件整份作废时**撒谎**：id 逐字写在文件里，文案仍写 "…is not declared in …" | 行为可论证（all-or-nothing），**文本是事实错误** |

## 为什么保留而不是清掉

三条理由，按分量排：

1. **它们都不改变退出码。** 前六条是 hint / 被上游违规兜住，第 7 条极性保守，
   第 8 条是文案。**没有一条构成假绿。**
2. **第 1–3 条落在 TH-0026 的提示层内**，而 TH-0026 结案时已写明：该提示的作用对象是
   **下一个写 scope-lock 的人**，不是历史；提示层的精度问题**不值得用判定层的成本去修**。
3. **本轮已在同一批里修了 13 条**。继续往下清边际收益递减，而每一次改动都要配破坏性反证
   与三平台 CI——**本轮已因为一条平台相关的反证前提挂过一次 Windows CI**。

## 但有两条建议将来一并处理

- **第 3 条（误报）**优先级实际高于它的 low 标签：**本项目 app 侧一旦出现 `rounds/NNNN`
  形状的业务目录，就会常年产生噪声**，而噪声正是本项目判定为「会摧毁提示机制」的东西
  （§4 异常层的极性裁决理由）。**若 app 侧真出现该形状，此条应立刻升级。**
- **第 8 条（文案撒谎）**成本极低（改一句 detail 文本），**下次碰到那段代码时顺手改掉**，
  不值得单独开一轮。

## Residual

- 本条**不覆盖** TH-0029 停止线以内的项（裸 HTML `<pre>`、tab 缩进围栏、G39 的词表绕过与
  结构性失明）——那些是**明确不修并已登记**，不是待办。
- 本条的 8 条**全部有实跑复现**，不是猜测。要清的时候不必重新论证存在性。
