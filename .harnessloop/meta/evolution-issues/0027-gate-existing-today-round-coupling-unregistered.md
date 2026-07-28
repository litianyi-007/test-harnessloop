# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0027
- Priority: P1
- Issue class: documentation / mechanical-gate
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28）
- Created at: 2026-07-28

**机械门已有的今天↔轮耦合未在 OUT 列完整登记**，导致「今天改不动已收盘轮」被当成现成护栏引用。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

2026-07-28 的对抗评审（activation_round 接法设计工作流）实测发现：`verify_protocol.py`
**至少有三处 (今天层, 轮 N) 耦合**，都产出挂在轮上的违规。主会话已逐条核实：

| 代码位置 | 今天层操作数 | 后果 |
|---|---|---|
| `:3719 load_reference_roots(project, verify_identity=True)` → `:3753 verify_round(...)` | `setup/reference-roots.json` + **未版本化**的 `local/reference-roots.local.json` | 删掉 local 绑定文件，已收盘轮的违规集从 `[]` 变 `['external-citation-unverifiable']`（`"round": str(round_dir)`，:3365/:3382） |
| `:3725 build_suffix_index(project)` | 每次运行**重扫今天的树** | Rule B 逐轮判定随今天的文件增删而变 |
| `submodule_roots(project)` | 今天的 `.gitmodules` | 同上 |

**「今天的编辑追溯判红已收盘轮」在 v0.28.0 就已经在发生**——不是将来要防的风险。

其中最尖锐的一条：`local/reference-roots.local.json` **不在版本库里**（`.harnessloop/local/`
下只有 `.gitignore` 与 `channel-params.example.json` 被跟踪）。也就是说**一个换机器就不
存在的文件，决定着已收盘轮今天判红还是判绿**。

## Impact

- SKILL.md 的 OUT 列此前只登记了其中一条的一个侧面（「外部树变动会让引用从 resolved
  变 not-found」），**没有登记这是一整类**，也没提 local binding 与 suffix index。
- 后果不是抽象的：评审实测中，**一份设计把「今天改不动已收盘轮」当成门的既有性质，
  并为它专门写了一条 fixture 当作"后续任何竖切的护栏"**。那条性质不成立，fixture 只测了
  一个文件却按全局不变量记账。**这是第四次同形错误的雏形：宣布一条性质，而承载它的机制
  不存在**（前三次：`attempt_id`「格式层即不可能」、v4「捕获点在写入时刻」、X10）。
- 主会话自己在 v0.27/v0.28 的 commit message 与对用户的汇报里也用了「跨层调用点不存在」
  这个说法。**就那两条规则而言准确**（评审确认），但表述方式让它读起来像整个门的性质。
  **已在 v5 §0 与本条内订正。**

## Proposed direction

**只改文档，不新增任何 check。** 具体两件事：

1. **SKILL.md OUT 列**逐条登记这三处耦合，写明「今天的编辑可以改变已收盘轮的判定结果」，
   并点名 local binding 文件不在版本库里这一条。
2. **把根规则的表述改对**：约束的是**不得新增**会追溯判红的跨层 join，
   **不是**声称门当前层纯净。（v5 §0 已订正，SKILL.md 需同步。）

**为什么不修代码**：这三处耦合各有其存在理由（外部引用基准本来就要对今天的树解析；
Rule B 的 suffix index 是为了容忍文件移动）。把它们改成层纯净是一次大重构，收益不明；
而**写在纸上的假前提会持续生产同形设计**，改文档的性价比高得多。若将来要上 CI 强制跑门，
这三处必须先处理——见下。

## Residual / 已知牵连

- **CI 顺序约束**：若先上 CI 强制跑门，这三条耦合会从「本地可忽略」抬成
  **阻断推送 + 只能靠改已收盘轮来清**（撞 E1）。因此 CI 必须排在本条之后。
- 本条**不承诺**枚举完了所有耦合。三处是评审实测到的，**不是穷举**。
  措辞上必须写「至少三处」，不得写「共三处」。

## Next Action

- Owner: 主会话
- 依赖：无
- 与 TH-0026 的关系：TH-0026 是**同一族的反面**——那条讲的是「不要**新增**磁盘存在性
  这类跨层判定」，本条讲的是「**已有的**要如实登记」。两条应一并读。
