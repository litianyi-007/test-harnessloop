# hopper brief-drop 修法 —— 设计评审裁定（T-099 双路，2026-08-12）

用户要求「这部分改动要经过异构模型审核」，并选「**先审设计，再审代码**」两道。
本文件是第一道的裁定。Q1 用户明确「**交给异构评审裁**」。

## 两路在 Q2 / Q3 / Q4 完全一致

| 项 | 一致结论 |
|---|---|
| **Q2** `loadTaskSpec` | 两条缺失分支均返回 **`null`**（不再返回假陈述字符串）；**签名不变**（不收 `task`）；由 `resolveDispatch` 在调用点合成。理由：文件加载与回落策略职责分离 |
| **Q3** 占位符 | **从 vendor-facing 的 `taskSpec` 里删除**。若需诊断，作为独立 operator notice（stderr / `--resolve`），**不进 vendor prompt** |
| **Q4** fail-closed | spec 与 brief **皆空 → 抛错**，与 adhoc（`:148-149`）、swarm（`:191-192`）对齐。`resolve-and-model-hints.test.js` 会红 —— **是 fixture 债不是产品绿**，该给它补非空 Brief |

**grok 补的一处实现细节**：合并**不能用 `??`** —— `'' ?? brief` 仍是 `''`（nullish 只认 null/undefined）。
必须用空串感知的合并，并先 `.trim()`。

## Q1 分歧：grok 选甲、codex 选乙 —— **裁定为乙**

| | 主张 | 主要理由 |
|---|---|---|
| **grok** | **甲** 择一（`spec` 优先，无 spec 才用 brief） | leader-tasklist 是契约权威；合并会让陈旧 brief 与更新过的 AC 并列且无优先级规则；`taskTextRequestsReadOnly` 会重复计入；真正的 bug 是「无 section → 空任务」而非「有 AC 时少了一行标题」 |
| **codex** | **乙** 合并（spec 在前，brief 标注来源，冲突时 spec 优先） | **执行 guardrail 已明示 vendor 会同时收到 brief 与 Task spec**；权限判定本来就读两者，合并不新增权限语义、只产生无害文本重复；择一仍会静默丢失只写在 brief 里的约束 |

### 决定性依据（主会话逐字核实）

`cli/src/tasks.js:154-155` 的 guardrail 第 4 条原文：

> "This is a one-shot background dispatch; no reply will come.
> **The brief and Task spec below are the complete, closed loop.**"

**prompt 自己已经承诺 vendor 会拿到 brief 和 Task spec 两样。**

→ 选**甲**会让这句话在「有详细 spec」时变成假话，**与我们正在修的缺陷是同一类错误**
（prompt 里声称某事而代码不做）。而且今天两个分支下 brief 都不在，**这句话此刻就已经是假的**——
修复正该让它成真，而不是换一种方式继续让它假。

grok 反对乙的两条，被 codex 的形状化解：
- 「无优先级规则」→ 合并体里**明写**「冲突时详细 spec 优先」
- 「`taskTextRequestsReadOnly` 重复计入」→ 该函数是正则匹配，重复无害且不改变权限语义

**裁定：乙。** 形状 = 详细 spec 在前，brief 以 `### Queue brief` 标明来源，并写明冲突时 spec 优先。

## 两路各自补的、题面漏列的

- **codex**：`tests/unit/resolve-vendor-override.test.js` 有**同样的** `brief === ''` + 无 leader-tasklist 问题，题面没列
- **codex**：更正题面——`host-detect.test.js` 的 fixture **已有 `Brief = test`**，不是空（grok 同判）
- **grok**：`loadTaskSpec` 应 **export** 以便直测正则提取（codex 主张不 export，认为经 `resolveDispatch` 覆盖即可）
  → **主会话取 grok**：该函数有四条返回路径与三种正则形态，只经公共契约间接覆盖会让新增用例既长又脆
