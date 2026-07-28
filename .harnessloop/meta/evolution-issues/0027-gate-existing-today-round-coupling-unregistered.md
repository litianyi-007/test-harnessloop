# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0027
- Priority: P1
- Issue class: documentation / mechanical-gate
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28）
- Created at: 2026-07-28

**机械门已有的今天↔轮耦合未在 OUT 列完整登记**，导致「今天改不动已收盘轮」被当成现成
护栏引用。**2026-07-28 复扫（用户亲自重扫 `verify_round` 及其直接调用面并逐条实证）
把最初评审报的「至少三处」修订为「至少六类」，随后子代理在执行本条的文档改写任务时
顺带扫出第七类、经用户亲自动手实证成立，再次修订为「至少七类」**，其中最大的一条——
Rule B 引用解析，机械门的中心机制——此前根本没有被单独点名。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

`verify_round(project, round_dir, suffix_index, roots)` 的四个入参里，**三个是今天层
的**（`project`、`suffix_index`、`roots`），只有 `round_dir` 命名的是轮本身。这三个
今天层入参，加上 `verify_round` 内部对今天磁盘的直接调用，至少产出七类
`(今天层, 轮 N)` 耦合，都产出挂在轮上的违规（`"round": str(round_dir)`）——一条判定
的操作数一部分来自今天的磁盘状态（今天可以随便改），一部分来自某个已收盘轮的目录
内容（本应冻住）。⑦ 进一步说明：连 `round_dir` 命名的「轮本身」也不能免疫——它下面
的文件内容同样是每次运行时的现场读取，不是收盘时刻的冻结快照：

| 序号 | 代码位置 | 今天层操作数 | 后果 |
|---|---|---|---|
| ① **Rule B 引用解析（门的中心机制）** | `_resolve_in_project`（约 `:2046`）、`_any_base_resolves`，在 `verify_round` 内对该轮 `reviews/*.md` 的每条引用调用，走 `.exists()`/`.is_dir()` | 今天项目磁盘上被引用路径是否存在 | 轮内一字未动，今天删除/新增被引用文件即可让该轮的 `dangling-citation` 出现或消失。`rule_b_files`/`citations_checked` 是 IN 列里覆盖面最大的一组字段——这不是七类里的一条普通耦合，是门的日常工作方式本身。 |
| ② Rule A 的扫描面 | `container.is_dir()`（`evidence/`、`reviews/`）、`scope_lock.exists()`、`_scan_round_artifacts`（`:3134`，`rglob`） | 今天磁盘上这两个目录实际还有哪些文件 | 已收盘轮的 Rule A 实际检查了哪些文件，取决于今天磁盘上还有哪些文件——删除一个 artifact 会让原有的 `scope-lock-violation` 静默消失，新增一个会让检查扩大到轮内从未见过的文件。 |
| ③ 后缀索引 | `build_suffix_index(project)`（`:3725`，每次 `verify_project` 运行重扫整棵今天的树） | 今天项目树的完整文件索引 | T-064 之后不再翻转 pass/fail（后缀命中只附加 display-only 提示 + `citations_suffix_hinted` 计数，不会把 `dangling-citation` 变回 resolved）——但这条提示文本与这个计数本身就是该轮判定输出的一部分，且随今天的文件增删/改名漂移，对一个已收盘轮同样如此。 |
| ④ submodule 根 | `submodule_roots(project)`，在 `verify_round` 内每轮调用，读今天的 `.gitmodules` | 今天声明的 submodule 路径列表，直接并入 `citation_bases` | 与 ③ 不同，这一条**会**翻转 pass/fail：今天增删一个 submodule 声明，可以让已收盘轮的某条引用在 resolved 与 `dangling-citation` 之间切换。 |
| ⑤ reference roots | `load_reference_roots(project, verify_identity=True)`（`:3719`）→ 传入每次 `verify_round` 调用 | `.harnessloop/setup/reference-roots.json`（已版本化）+ **未版本化**的 `.harnessloop/local/reference-roots.local.json`（gitignored） | 删掉 local 绑定文件，已收盘轮的违规集从 `[]` 变 `['external-citation-unverifiable']`（`"round": str(round_dir)`）。**一个换机器就不存在的文件，决定着已收盘轮今天判红还是判绿**——换机器后第一次跑，若从未放过该本地绑定文件，历史上每一个引用过外部 root 的轮都会被判 unverifiable，不是从换机器那一刻才开始，是回溯到它们各自收盘的那一刻。 |
| ⑥ 轮自身文件的存在性 | `scope_lock.exists()`、`decision.exists()` | `round_dir` 下这两个文件今天是否还存在 | 删 `scope-lock.md` 今天就触发该轮的 `missing-scope-lock`；删 `decision.md` 则让 E4、B2a、两条 RAE declaration 检查对该轮整体失声——不是报告违规，是那些检查从此不再对这个轮运行。 |
| ⑦ **B2a 摘要自洽核对（内容级，非存在性级——子代理文档任务顺带扫出、用户亲自实证）** | `check_review_declaration` 的 digest 比对：`decision.md` 声明的 `Review digest:` ⇄ `Review:` 所指文件**此刻**的字节内容 | 该轮 `reviews/review.md`（或任何被 `Review:` 引用的文件）今天的实际字节内容 | 轮目录内不删文件、不移动、不改配置——只编辑一下被引用审查文件的正文（哪怕只是订正一个错别字），已收盘轮就从零违规变为 `review-digest-mismatch`。清红的唯一办法是回头把 `decision.md` 里的 digest 也改掉，而这正是 v0.12.0 E1 纪律明令禁止的「为了让门变绿去改被审产物」——①-⑥ 都不需要碰轮目录内一个字节，这一条恰好相反，且触发它所需的动作是七类里最弱的一个。 |

**已实证的复现步骤（① 的实测，不是推测）**：

1. 造一个已收盘轮（例如 `0001`），其 `reviews/*.md` 里有一条 backtick 引用
   `` `notes/design.md` ``，且 `notes/design.md` 在项目里确实存在。
2. 跑 `verify_protocol.py`：该轮零违规，正常收盘。
3. **不touch该轮目录下任何一个字节**，把 `notes/design.md` 从今天的磁盘删掉。
4. 再跑一次 `verify_protocol.py`：同一个轮——目录内容与上一步完全相同——现在
   报 `dangling-citation`。

**已实证的复现步骤（⑦ 的实测，用户亲自动手，2026-07-28）**：

1. 造一个已收盘轮（例如 `0001`），其 `reviews/review.md` 内容为「审查结论：通过」，
   `decision.md` 声明 `- Review: <该文件路径>` 与 `- Review digest: <当时内容的
   sha256>`。
2. 跑 `verify_protocol.py`：该轮零违规，正常收盘。
3. **只往 `review.md` 末尾追加两行文字**（不删文件、不动轮内其它任何字节，
   也不动 `decision.md`）。
4. 再跑一次：同一个轮——`decision.md` 与轮内其它文件完全未动——现在报
   `review-digest-mismatch`。用户实测的对照输出：

   ```
   收盘时（digest 匹配）      : 无违规
   今天改了被引审查文件的内容 : ['review-digest-mismatch']
   ```

**「今天的编辑追溯判红已收盘轮」在 v0.28.0 就已经在发生**——不是将来要防的风险，
是门今天、现在的行为。

**结论（如实表述，不软化）**：**机械门本质上是一个「今天层扫描器，把发现归属到
轮上」。** 今天层↔轮层耦合不是三处例外，也不是七处例外，而是**它的常态**——上面
七类只是主会话重扫 `verify_round` 及其直接调用面、加上子代理在文档任务中顺带扫出
并经用户实证的第七类，合起来实测到的，不是穷举。v0.27.0 /
v0.28.0 那两条纯轮层规则（RAE 硬规则 `acceptance-eval-positive-without-pass`、
第二条 acceptance-eval declaration 校验——全部操作数来自同一轮的两个文件）在这个
门里是**罕见的例外，不是代表**。`docs/runtime-evals-interface-contract-v5-20260728.md`
§0 的 2026-07-28 订正已同步这个结论。

**⑦ 与 ①-⑥ 的性质差异（必须单独点明，不得并进 ①）**：①-⑥ 都是**存在性级**——
触发它们需要删除、移动，或改一份配置（`.gitmodules`、local binding 文件）。⑦ 是
**内容级**：不删除、不移动、不改任何配置，只需编辑一下被引用的审查文件正文（哪怕
只是订正一个错别字、补一句说明），一个早已收盘的轮就会翻红。⑦ 的触发动作因此比
其余六类都更弱、更接近「日常会无意发生的操作」，且被改的那个文件通常就在轮目录
本身里面。⑦ 的唯一清红路径——回头把 `decision.md` 里的 digest 也改掉——正面撞上
v0.12.0 的 E1 纪律（绝不为了让门变绿去改被审产物）：这意味着「编辑一份历史轮的
审查记录」这个看起来最无害的动作，会让门与协议纪律直接冲突，而不是像 ①-⑥ 那样
只是判定结果漂移。

## Impact

- SKILL.md 的 OUT 列此前只登记了 ⑤ 的一个侧面（「外部树变动会让引用从 resolved
  变 not-found」），**没有登记这是一整类**，也没提 local binding 文件不在版本库里、
  ①（Rule B 本体，最大的一条）、②③④⑥ 完全未提。
- 后果不是抽象的：2026-07-28 的对抗评审实测中，**一份设计把「今天改不动已收盘轮」
  当成门的既有性质，并为它专门写了一条 fixture 当作"后续任何竖切的护栏"**。那条
  性质不成立，fixture 只测了一个文件却按全局不变量记账。**这是第四次同形错误的
  雏形：宣布一条性质，而承载它的机制不存在**（前三次：`attempt_id`「格式层即不可
  能」、v4「捕获点在写入时刻」、X10）。
- 主会话自己在 v0.27/v0.28 的 commit message 与对用户的汇报里也用了「跨层调用点
  不存在」这个说法。**就那两条 RAE 规则而言准确**（评审确认），但表述方式让它读
  起来像整个门的性质。**已在 v5 §0 与本条内订正。**
- 2026-07-28 二次复扫进一步发现：初版评审报的「至少三处」本身也低估了——遗漏了
  门的中心机制（①）以及 ②⑥ 两类。这不是评审失职，是「先枚举再核实」这个方法本身
  在一个「几乎处处耦合」的门上天然会漏——这一点本身也应作为教训记入，而不是简单
  归咎某一次评审不够仔细。

## Proposed direction

**只改文档，不新增任何 check。** 具体两件事：

1. **SKILL.md OUT 列**用一条统领性条目登记这七类耦合，写明「今天的编辑可以改变
   一个已收盘轮的判定结果——多数情况下（①-⑥）该轮目录内一个字节都没动，少数
   情况下（⑦）只有被引用的审查文件正文变了、`decision.md` 本身分毫未动」，逐条
   点名代码位置与机制，特别点名 ⑤ 的 local binding 文件不在版本库里、⑦ 的清红
   路径撞 E1，并与已有的「外部引用 resolved→not-found」条目交叉引用而不重复。
2. **把根规则的表述改对**：约束的是**不得新增**会追溯判红的跨层 join，
   **不是**声称门当前层纯净。（v5 §0 已订正，SKILL.md 需同步。）

**为什么不修代码**：不是「七类各有各的理由」这种可以逐条辩护、逐条拔除的清单——
机械门的构造本身就是「每次运行重新扫描今天的磁盘、把发现挂到某个轮的目录名下」，
七类耦合是这个构造**直接、必然的推论**，不是七个可以独立修掉的例外。把它们改
成层纯净，等于把 Rule B 的引用解析、Rule A 的文件枚举、reference-roots 的新鲜度
校验、submodule 基准……全部推倒重写，去发明一套「今天」与「某个历史轮」之间的
全新取数方式——这是一次收益不明、风险极高的大重构。而**写在纸上的假前提（"门
已经是层纯净的"）会持续生产同形设计**——评审已经实测到一次真实发生的案例。改
文档的性价比高得多。

## Residual / 已知牵连

- **CI 顺序约束（本次复扫后加强）**：若先上 CI 强制跑门，这七类耦合会从「本地可
  忽略」抬成**阻断推送 + 只能靠改已收盘轮来清**（撞 E1）。耦合面比最初评审报的
  「至少三处」大得多——覆盖 Rule A 与 Rule B 两条最基本的规则、外部引用可用性、
  轮自身文件的存在性，以及（⑦）轮自身被引用文件的内容——CI 强制跑门的风险相应
  更大：几乎任何一次纯粹「今天」层面的清理（删无用文件、清 local 绑定、改
  `.gitmodules`、重命名一个被引用过的文件），乃至一次看起来最无害的内容编辑
  （订正一份已被引用审查文件里的错别字，⑦），都可能让一个早已收盘的轮——多数
  情况下轮目录一字未动（①-⑥），少数情况下只有被引用的审查文件正文变了、
  `decision.md` 分毫未动（⑦）——在 CI 里突然变红，且报错信息读起来像是那个轮
  出了问题。因此 CI 必须排在本条被充分理解、且相关操作规程建立之后，不得抢跑。
- 本条**不承诺**枚举完了所有耦合。七类中的前六类是主会话重扫 `verify_round` 及
  其直接调用面（四个入参：`project`、`round_dir`、`suffix_index`、`roots`）实测
  到的；**第七类是子代理在执行本条的文档改写任务时顺带扫出来的，不在主会话那轮
  重扫的范围内**——这本身进一步印证了「先枚举再核实」这个方法在这个门上必然会漏：
  即便主会话亲自逐条实测过一次，覆盖面依然不是全部，下一次揭出新类别的执行者也
  未必还是同一个人。措辞上必须写「至少七类」，不得写「共七类」。

## Next Action

- Owner: 主会话
- 依赖：无
- 与 TH-0026 的关系：TH-0026 是**同一族的反面**——那条讲的是「不要**新增**磁盘存在性
  这类跨层判定」，本条讲的是「**已有的**要如实登记」。两条应一并读。
