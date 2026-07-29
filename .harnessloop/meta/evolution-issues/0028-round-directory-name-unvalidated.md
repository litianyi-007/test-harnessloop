# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0028
- Priority: P2
- Issue class: mechanical-gate
- Status: resolved（前提被证伪：不加全局要求，理由见文末）
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28）
- Created at: 2026-07-28

**轮目录名全仓零校验**：`verify_project` 会把 `rounds/` 下任何名字的目录当作一轮。

## Redaction Boundary

- Secrets removed / Private data removed / Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

`verify_project` 枚举轮目录时只做 `iterdir()` + `is_dir()` + 容器逃逸守卫，
**不校验目录名**。于是 `rounds/abc`、`rounds/0000`、`rounds/99999`、`rounds/０００７`
（全角）都会被当成合法的一轮参与全部判定与 coverage 计数。

**已实证的一次真实后果（v0.32.0，已在 v0.33.2 修）**：
`check_loop_predecessor_declaration` 用 `int(round_dir.name)` 取本轮轮号，
非数字名时 `except ValueError: return [], state` **静默放行**——把轮目录起名 `abc`
即可让 `Predecessor:` 的前向约束整个失效，零违规、exit 0。

v0.33.2 **只在原地收口**：声明了 `Predecessor:` 的轮，其目录名必须是 `^[0-9]{4}$`，
否则 `loop-predecessor-round-unnumbered`。**没声明该字段的轮仍然完全不校验。**

## Impact

- 任何**未来**用到轮序号的判定都会重新踩这个坑。已知会用到的地方：`ATTEMPT_ID_RE`
  的前四位与轮目录名做字符串比较（`eval-ledger-attempt-id-round-mismatch`）、
  TH-0026 的 scope-lock 轮号判据、v0.32.0 的 `Predecessor:`。
- coverage 的 `rounds=N` 会把非轮目录算进去，使「14 轮」这类数字本身不可靠。
- 这是**被守门方持有的开关**族（X1）：给目录改个名，就能让某些判定不适用。

## Proposed direction（含必须先裁的一点）

直觉解法是「轮目录名必须匹配 `^[0-9]{4}$`，否则违规」。**但它会追溯判红任何已有的
非标准命名轮**，撞 E1（唯一清红方式是重命名历史轮目录，那会同时打断所有指向它的引用）。

因此**必须先回答一个事实问题**：本仓（以及协议文档、`init_project.py`）是否已经
**事实上**要求四位数字？

- `init_project.py` 创建轮目录时用的命名格式是什么？（去读，别猜）
- 本仓现有 14 个轮是否全部匹配 `^[0-9]{4}$`？（**是**，已核）
- 协议文档里有没有明文规定？

若三者都指向「四位数字是既有约定」，则升为违规的**追溯风险为零**（没有存量违例），
可以直接做。**若存在存量违例，则照 TH-0026 的先例先落提示层。**

**判据必须用 `^[0-9]{4}$` 不是 `^\d{4}$`**——Python 的 `re` 里 `\d` Unicode 感知，
全角 `０００７` 会匹配且 `int()` 成功。这一点已由 v0.33.2 的 G35a 结构性守卫兜住
（AST 扫全仓，禁止字符类之外的裸 `\d`，白名单为空）。

## Residual

- 本条**不覆盖** goal 目录名（`YYYYMMDD-NNN-<slug>`）的校验，同族但另议。
- v0.33.2 的收口只对「声明了 `Predecessor:`」的轮生效，**这是刻意的最小改动**，
  不是本条的解决。

## Next Action

- Owner: 主会话
- 先决：回答上面三个事实问题（尤其 `init_project.py` 的实际命名格式）
- 与 TH-0026 的关系：那条也依赖轮号解析，若本条升为违规，TH-0026 的判据可相应简化


---

## 处置结果（2026-07-30）：**前提被证伪，明确不加全局四位要求**

本条的 Next Action 要求「实现前先答三个事实问题」。**答完之后，本条原本的直觉解法
（轮目录名必须匹配 `^[0-9]{4}$`，否则违规）被判为既不必要、又有害。**

### 三个事实问题的答案

| 问题 | 答案 |
|---|---|
| `init_project.py` 用什么格式创建轮目录？ | **它根本不创建轮目录**——全文 **0 次**提到 `rounds` |
| 协议文档有明文规定吗？ | 只有 `SKILL.md:337` 的一个**散文示例** `rounds/0001/`，外加各 gate 各自的四位断言 |
| 本仓 14 轮是否全合规？ | **是**（10 个不同名全部匹配 `^[0-9]{4}$`） |

**关键推论**：轮目录名**完全由 agent 自选**，只有一个散文示例引导，**没有任何代码生成或
强制它**。所以本仓零违例只说明「这里的 agent 照着示例做了」，**不说明四位是可依赖的约定**。
换一个项目完全可能是 `round-1` / `1` / `0001-setup`。
**升为违规会追溯判红别的项目的历史轮——只是从本仓内部看不见（E1 陷阱的远程版本）。**

### 更要紧的：真问题不是「该不该要求四位」，而是「非四位名在哪里造成静默错答」

逐点实测（fixture：`positive` + 账本里 due eval 为 `fail`）：

| 轮名 | 旗舰硬规则 `positive-without-pass` |
|---|---|
| `0007` | **触发** |
| `round-1` / `1` / `0007-setup` / `abc` | **全部触发** |

**非合规名不制造假绿。** 它额外产出一条 `eval-ledger-attempt-id-round-mismatch`
——**噪声，不是洞**。

而两处**真正会静默错答**的站点，**都已经修掉了**：

- `_latest_round_decision_text`（非四位名赢下「最新轮」→ 压制/伪造 anomaly）
  → **v0.38.0 已修**。实测复验：基线 anomaly=1；加 ASCII `0002 negative` → 0（正确压制）；
  加 `round-9 negative` → **仍 1**；加全角 `００１０ negative` → **仍 1**。
- `check_loop_predecessor_declaration`（`except ValueError: return` 静默放行）
  → **v0.33.2 已修**（`loop-predecessor-round-unnumbered`，且只对声明了该字段的轮生效）。

### 结论

**不加全局四位要求。** 理由三条，按分量：

1. **不必要**——已知的静默错答站点全部修完，剩余暴露是噪声不是洞；
2. **有害**——轮名由 agent 自选、无代码生成，全局违规会追溯判红其它项目的历史轮；
3. **本仓自己的零违例不构成证据**——它只证明本仓 agent 照示例做了。

### Residual（新登记）

- 一个**合法地**使用非四位轮名的项目（如 `round-1`），今天会因 `attempt_id` 前缀比对而
  **常年产生 `eval-ledger-attempt-id-round-mismatch` 假红**。这是本次核实新发现的，
  不在原 issue 内。**它是噪声方向，但噪声正是本项目判定为「会摧毁提示机制」的东西。**
  若将来真出现这类项目，处置方向应是**放宽 `attempt_id` 的前缀判据**（让它跟随实际轮名），
  **而不是**反过来强制轮名格式。
- 本条**不改变** SKILL.md:337 那个散文示例——它仍是唯一的格式引导。
  **是否把它升级为规范性要求，是协议撰写决策，不是机械门决策。**
