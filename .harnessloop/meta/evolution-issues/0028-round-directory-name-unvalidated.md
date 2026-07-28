# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0028
- Priority: P2
- Issue class: mechanical-gate
- Status: open
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
