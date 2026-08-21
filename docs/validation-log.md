# harnessloop 验证与迭代记录

每一轮「发现问题 → 改插件 → 重装 → 复验」记一条。最新的记录放最上面。

条目模板：

```markdown
## YYYY-MM-DD <一句话标题>

- **场景**：在开发 app 的哪个环节、执行哪个 skill 时触发
- **现象**：框架实际行为（贴关键输出/文件状态）
- **预期**：框架应有的行为，依据（README/AGENTS.md/协议条款）
- **插件改动**：harnessloop submodule 中的 commit（`<sha> <subject>`），或"未改动，原因"
- **复验结果**：重装重启后同场景的行为；通过/未通过
- **遗留**：后续待办或新发现的关联问题
```

---

## 2026-08-22 rounds/0025：锁采样改轮询，macos frame-replay CI 绿

- **场景**：goal 002 rounds/0025，接 0024 negative。三条 §9.3 测试从固定 sleep 改为有界轮询；FAIL2 接受 unknown session 作为没偷锁
- **现象**：本机 174/174。Actions 32503486999 ubuntu+macos 全绿，含 frame-replay 与 Swift 13/0/0。产品实现 diff 空
- **预期**：macos 上 frame-replay 稳定绿，且不 skip、不改产品
- **插件改动**：未改动
- **复验结果**：✅ `Accepted: yes`
- **遗留**：SG-10 下一件产品工作待选；hopper 测试进 CI 仍另轮

## 2026-08-21 rounds/0024：frame-replay 进 CI 立刻红，两次失败集合不相交

- **场景**：goal 002 rounds/0024 把 `frame-replay-tests` 和 Swift 13/13 接进 GitHub Actions macos job
- **现象**：ubuntu 绿、SwiftPM 构建绿。frame-replay 两次 macos：32474120825 = 173/174（仅 0012 固定 200ms）；32474519871 = 171/174（0012 已过，三条 0023 锁采样红）。本机 174/174
- **预期**：一次坏提交会红；macos 稳定绿才接受。前者成立，后者不成立
- **插件改动**：未改动
- **复验结果**：❌ 本轮 `Accepted: no`。门有牙齿，测试窗口过紧
- **遗留**：0025 把三条 §9.3 采样改成有界轮询

## 2026-08-21 rounds/0023 收盘：steer + 原子交接；本轮未改插件

- **场景**：goal 002 rounds/0023 收盘。实现 `interrupt(mode:"steer")` 并把 `stop()` 遇 `interrupt_in_progress` 改成 confirmed D1 §9.3 的「等待，不抢占」。Claude 会话在返工完成后 `/resume` 取消，本 Grok 会话接续收盘。
- **现象**：T-116（codex）判 REWORK 三条——交接窗非原子、active-run 快照不完整、runner 入站仍按 cancel 翻译。返工后主会话复跑 `swift build` exit 0、帧回放 174/174、Swift 金标 13/0/0。`sessions.steer` 被源码坐实为 abort+resend，不是软 steer。
- **预期**：对抗审 REWORK 后主会话独立复核可收盘（rounds/0020 先例）；控制契约「Failed review acceptance: 仅用户」——用户 2026-08-21 授权。环境期望 claude-opus-5[1m]、实际 grok-4.6，用户接受本次不符且不改期望值。
- **插件改动**：未改动。hopper 0.59.0 idle false-kill 属于 rounds/0022。本轮范围明确禁止三个插件 submodule。
- **复验结果**：源文件 SHA 与返工收尾一致；C# diff 空；fixture 4 增 1 删（删 description）。已知缺口：会话恢复路径没有 active-run 信号，保持保守拒绝。
- **遗留**：CI 仍不跑 174 条帧回放、仍按「12 PASS + 1 DEGRADED」描述 Swift parity——0023 禁止改 `.github/`，结转 rounds/0024。

## 2026-08-13 kata 2.16.3 闭环：两个缺陷一起修，第二个是复核这件事本身挖出来的

- **场景**：修上一条记的 `wiki-lint` 假发现。**修完复核时，跑测试套件的动作本身炸出了第二个缺陷**
- **缺陷一（假发现）现象与根因**：见下一条。**修法比我交代的更好**——我说「别搞三份排除表」，实施方查出 **`wiki_lib.py:55` 早就有规范定义 `is_structural_page()`，而且 `graph_query.py:150-155` 一直在用它做完全相同的豁免**。所以 `lint_naive.py` 的 orphans 检查是**同一逻辑的第二份实现，只是从没跟上那次修复**。它没造第四份表，而是把三处都接到那个既有定义上。另外**刻意没有**把豁免下沉到 `discover_pages()`：`size`/`stale` 检查看见 `SCHEMA.md` 是**真信号**（膨胀或陈旧的 schema 文件该报），下沉会把这两个检查一起弄瞎
- **缺陷二（自我下毒）现象**：`tests/run_smoke.py` 的 `_windows_safe_rmtree` 在 POSIX 上**亲手制造它随后被噎死的那个状态**，且永久：
  ```python
  os.chmod(p, _stat.S_IWRITE)   # S_IWRITE == 0o200，整体覆盖 mode
  func(p)                        # POSIX 上 func 可能是 os.open，需要第二个 flags 参数
  except OSError: pass           # 抓不到 TypeError
  ```
  ① `chmod` 把目录 mode 覆盖成 `0o200`，剥掉 `r` 与 `x`——**反而更删不掉**（Windows 那套「清只读属性」的写法 translate 不到 POSIX 权限位）；② `shutil.rmtree` 在 POSIX 走 `_rmtree_safe_fd`，传进 `onerror` 的 `func` 包括 `os.scandir`/`os.lstat`/**`os.open`**/`os.rmdir`/`os.unlink`，其中 `os.open` 需要 `flags`，于是抛 `TypeError`；③ `except OSError` 抓不到它，**炸穿整个测试运行**，还把原始的 `PermissionError` 盖掉。实测影响：**269 ok / exit 0 → 此后每次都在 70/269 处 exit 1**，报一句跟权限毫无关系的 `TypeError`
- **预期**：清理助手不应把可恢复的权限错误升级成致命错误，更不应制造它自己处理不了的状态；测试套件必须可重复运行
- **实施方自己抓住的一次假修**：它的第一版只是给 `os.open` 补上缺失的 `flags` 参数——`TypeError` 消失了，**但目录压根没被删掉**（`onerror` 是 fire-and-forget，shutil 不会重试原调用）。它靠自己写的「是否真的删掉了」这条断言抓住了，而不是靠「没抛异常」。**「异常没了」不等于「事情做成了」**
- **插件改动**：kata **2.16.3**（`plugin/scripts/lint_naive.py` 接既有 `is_structural_page`；`tests/run_smoke.py` 的 `_onerror` 改为 `os.stat(p).st_mode | stat.S_IRWXU`**只加不减**权限位、并按 `p` 现在到底是什么自己收尾而不是重放 shutil 给的 `func`；Test 14 断言由 `>= 1` 收紧成精确集合相等 + 显式断言无脚手架文件；新增 Test 66 `T-rmtree-selfpoison-1`，且它自己的清理放在 `try/finally` 里——**一个测「不可重跑」的测试不能自己把树弄成不可重跑**）
- **复验结果**：✅ **全部由主会话独立复跑**。`lint --check all`：**7 → 0**，26 个内容页仍零漏报。自造毒化态调修复后的 helper：**无异常抛出且 `parent` 真被删除**（第二条断言正是假修会挂的地方）。测试套件**连跑三次，每次 270 ok / exit 0**，中间不清理，全仓 `0200` 目录残留 **0**。版本 4 处 + CHANGELOG 停在 2.16.3，未被二次 bump
- **遗留**：①**未查清是哪一次运行首先触发底层那个瞬时错误**——handler 的缺陷机制可独立证明、与触发时机无关，但触发条件本身没查清，如实标注为「未确定」而非「与修复无关」；②实施方主动点出一处它没解决的窄边界：Windows 上「指向目录的 symlink」有时需要 `os.rmdir` 而非 `os.unlink`，修前也没处理对，**不是回归**，但它选择说出来而不是默认没事；③本机 `~/.git-ai/bin/git` 会遮蔽真 git，任何重定向 `HOME` 的测试都会因此误报——**不是 kata 的问题**，但顺带发现 `wiki_sync.py` 的 `preflight()` 把 `git remote get-url` 的任何非零退出都当成「没配 remote」，**分不清「git 自己跑不起来」**，与本项目「空结果不等于不存在」同族

## 2026-08-13 kata：`wiki-lint` 对每个 kata wiki 恒报 7 条假发现，而它自己的测试**不可能失败**

- **场景**：按 CLAUDE.md「每 3 轮跑一次工程侧知识沉淀（kata 的主场）」的钩子，用 `/kata:wiki-ingest` 沉淀 rounds/0017–0020 与 hopper 0.55.1–0.57.0，收尾时跑 `wiki-lint` 体检
- **现象**：`lint_naive.py --check all` 在 26 页内容的 wiki 上报 **7 条 MEDIUM，全部落在 wiki 自己的脚手架三件套**（`SCHEMA.md` / `index.md` / `log.md`）上，**26 个内容页零发现**。退出码 1
  ```
  index       | SCHEMA.md                    | page not referenced in index.md
  orphans     | SCHEMA.md / log.md / index.md | true orphan: no inbound or outbound wikilinks
  frontmatter | SCHEMA.md / log.md / index.md | missing required field(s): ['title','type',...]
  ```
- **根因（读源码坐实，非推测）**：`kata/plugin/scripts/lint_naive.py` 的 `discover_pages()` 把这三个文件**当成内容页扫进来**。三个检查里**只有 `_check_index`（`:219`）做了排除，而且排得不全**——它排 `index.md` 与 `log.md`，**漏了 `SCHEMA.md`**；`orphans` 与 `frontmatter` 两个检查**一点排除都没有**。而这三个文件是 `wiki-init` 给**每个** kata wiki 无条件生成的（skill 步骤 ⑥⑦⑧），所以**这是每个 kata wiki、每次运行都会发生的恒定假发现**
- **更值得记的一层：它自己的测试为什么抓不到**。`kata/tests/run_smoke.py` Test 14 的 fixture **本身就复现了这个 bug**（`_lint/SCHEMA.md`、`_lint/index.md` 都在，实跑得到 `frontmatter=3`，其中 **2 条是假的**、只有 1 条真）。但断言写的是：
  ```python
  assert by_check.get("frontmatter", 0) >= 1
  assert by_check.get("links", 0) >= 1
  ```
  **`>= 1` 分不清「抓到了那条真的」和「抓到两条假的外加一条真的」，甚至分不清「只抓到假的」。** 如果 frontmatter 检查退化成只报脚手架、真的那条漏掉，`2 >= 1` 依然绿。另外 `orphans` **根本没进这个测试的 `--check` 列表**，`index=2` 算出来了却从不断言
- **预期**：体检工具的发现应当指向内容问题；脚手架文件不是内容页。测试断言应当能因「该抓的没抓到」而变红
- **插件改动**：见下一条闭环记录
- **复验结果**：见下一条
- **遗留**：**这是本项目那条老规律的又一例，而且是最锋利的一例**——不是「没有守卫」，是**守卫在跑、断言在绿、而它结构性地无法因为要防的那件事失败**。与 rounds/0019 的「测试把错误的 thinking 行为钉死」、hopper 的「三个绿灯全亮而任务没送到」同族。`>= 1` 这种下界断言是这个失效形状的典型载体

## 2026-08-13 rounds/0019 收盘：实拍抓到了单元测试不但没抓、还把它钉死的缺陷

- **场景**：goal 002 第 2 件（token 可填）+ 第 1 件（真实 LLM 往返的内容态实拍）。评审派 codex（T-112，单路，按 scope-lock）
- **现象**：①**实拍暴露思考流被撕成几十条碎行**——`TOOLROW_DEMO_OK` 一个词被拆到两行；而**单元测试里有一条专门断言「thinking 不合并」，等于把错误行为钉死了**。这是本项目第一次由实拍推翻测试。②评审 Q1 踩中本轮红线：`SelfTestHooks.swift` 从**生产 Keychain 条目**读出真实 token 并原样打印，`strings` 证实**已编进正式 app 包**。③`endpointSource` 在验证 URL 之前就被设成「来自环境变量」，env URL 非法时值回退成默认**而标签仍在说来自环境变量**
- **预期**：测试应当是行为的证据而非行为的定义；红线（token 绝不明文落盘）在任何路径上都成立
- **插件改动**：**无**——本轮是 app 轮，三插件均未改。**但它验到了一件插件相关的事**：单路评审（codex）在 UI/配置层改动上仍抓出三条真缺陷且其中一条踩红线，说明 scope-lock 里「重点问什么」写得越具体，单路评审的产出越接近双路
- **复验结果**：✅ 通过。`swift build` exit 0；帧回放 **102/102**（基线 83 → 99 → 101 → 102）；红线复核 `print(` **0 个文件**、二进制符号 **0 个**，**且对照检查 `KernelTokenKeychainStore` 搜到 1 个——证明 `strings` 本身在工作**；主会话自己的反证（打破 env 优先级）99 → 97 → 还原 99，零残留
- **遗留**：三条证据缺口如实登记（思考流合并后的实拍未取得——键入送不进 SwiftUI 输入框；工具调用行未被触发；无障碍设置无实拍），见 `rounds/0019/evidence/shots/README.md`。**另发现本仓 secret 门的一个真实边界**：`scripts/check-secrets.sh` 的 L2 把「一段解释自己做了什么脱敏的散文」也拦了下来——豁免词只对 `grep -Eo` **提取出的匹配串**生效，写在旁边的注释无效，所以标记必须长在值里

## 2026-08-13 rounds/0018 收盘：返工后补派异构确认审，判 PASS_WITH_NOTE 而不是 PASS

- **场景**：goal 002 UI/渲染层（工具调用行、思考行、审批卡视觉）。评审 codex（T-110，单路）判 REWORK 三条，主会话复核全部成立后返工，**返工后另派 grok（T-111）做确认审**
- **现象**：确认审四问三 PASS 一 NOTE——Q4「无障碍由构造保证」被判**只对本轮缺陷成立**（固定 alpha → material 确由构造消除），**全 UI 像素级实拍仍未验**，故记 NOTE 而非 PASS
- **预期**：确认审应当能独立判定「返工是否真的堵住」，而不是复述返工方的自述
- **插件改动**：**无**——本轮是 app 轮。**验到的插件事实**：hopper 的「返工后补派第二家做确认审」这一用法跑通了，且**第二家给出的不是橡皮图章**——它把一条本可以简单判 PASS 的问题拆成「本轮缺陷已消除／全量未验」两半，**记债不返工**
- **复验结果**：✅ 通过，`Accepted: yes`。`Review digest: 5840dfc1…`
- **遗留**：全 UI 像素级实拍（Reduce Transparency / Increase Contrast 等）仍未取得——这笔债延续到 rounds/0019 仍未还，两轮都如实登记未粉饰

## 2026-08-13 rounds/0017 的状态异常：有 scope-lock、有 evidence，**没有 decision.md**

- **场景**：清点 goal 002 各轮时发现——`rounds/0017/` 只有 `scope-lock.md`（且开头自述是「**事后补录，2026-08-12**」）与 `evidence/`，**既无 `decision.md` 也无 `round-summary.md`**
- **现象**：机械门对这一轮静默。`verify_protocol.py` 报 `violations 0`，且它自己的输出里写着：「passed, but not a clean sweep: 26 轮中有 11 轮在 `evidence/` 或 `reviews/` 下没有可检查的东西——对这些轮，干净退出的意思是『没得可查』而不是『查过且干净』」
- **预期**：一个轮次要么被正式收盘（有 decision），要么被明确标注为未收盘；不应存在「看起来做完了、协议上没结论」的第三态
- **查证后的订正（重要，不要照抄「机械门完全没有这条检查」）**：**框架其实已经有一条**——`eval-ledger-without-decision`（TH-0029 defect 2，`verify_protocol.py:486-504`）。但它**刻意是条件触发**：只在**该轮自己**有 `evidence/runtime/acceptance-evals.json` 台账、却没有 `decision.md` 时才报。文档原文明写「**This does not require every round to have a decision.md**」，理由是保持 E1 既定的零迁移极性——不追溯审判早于这些文件的旧轮。rounds/0017 无台账，**因此按设计静默，不是漏网**
- **插件改动**：**未改，原因**——上游对「要不要普遍要求 decision.md」已经做过取舍并明确拒绝了，我不应该在没有新论据的情况下把它翻过来。**真正的缺口比我最初写的更窄**：不是「没有守卫」，而是**判据锚在「有没有 eval 台账」上，而 0017 这类「有 scope-lock + evidence、无台账」的轮落在锚点之外**
- **复验结果**：n/a（尚未修）
- **遗留**：两条路——①给 0017 补一份如实的「未收盘，内容已迁往 goal 003」说明（**project 侧，成本极低，先做这个**）；②向上游提「锚点是否该从『有台账』放宽到『有 scope-lock 或 evidence』」，**但必须带着零迁移极性的答案去提**，否则会重蹈它当初拒绝的理由

## 2026-08-13 hopper 0.57.0：评审踩中的，正是我自己写死的那条红线

- **场景**：goal 003 / rounds/0003，修缺陷 ⑤——`loadTaskSpec` 用「marker 之后有无非空白字符」判定小节是否承载 spec，于是正文只有 `---`、表格分隔行或裸引用符的小节全部通过，vendor 会收到一份 Task spec 一节里只有一条水平线的任务书
- **scope-lock 里我写死了一条红线**：「**过度拒绝比欠拒绝更糟**」——合法 spec 被误判为无内容会让本能跑的任务 fail-closed 停掉，而缺陷本身只是偶尔送出一份空任务书
- **第一版实现恰恰踩了这条**：`hasSubstantiveContent` **先 `trim` 再判、把缩进信息毁掉**，于是一个用缩进代码块举例展示 `---` 的合法 spec 被整节判死。**评审（codex）找出来，主会话复现属实**
- **修法换原则而非打补丁**：代码块是作者显式标记的字面内容，**判据根本不该往里面看**。围栏行本身算结构，围栏内部与 4 空格/tab 缩进的行一律算内容、连判定都不进。推论——空围栏块（开闭相邻）仍应被拒，实测确实如此
- **同族第二条：诊断说谎**。`loadTaskSpec` 三种 null 成因（没文件/没小节/小节存在但纯结构）在调用链被 `|| ''` 抹平成一种，**小节明明在、只是被拒时用户看到的是「没有这个小节」**，排查被引到错方向。现由出参携带 `SPEC_MISS_REASON`，三种原因各说各的话
- **复验结果**：✅ 通过。评审两条发现**全部复现**（误拒 3 例 + 欠拒绝 6 例），返工后**那 9 例 9/9 全修、原有 14 例 14/14 不变**；unit **1416 pass / 0 fail**、integration **7/7**；**破坏性反证三块各一次、每次先打印注入命中数再看红**（21 行→5 红、6 行→2 红、11 行→10 红）；安装产物复验 4/4
- **反证反过来产出了信息**：第三块 11 个注入点里有一例证明该形状本来就被独立处理正确——**如实记为反证的产出，不是缺口**
- **残留不宣称穷尽**：CHANGELOG 明写「已知，不穷尽」并列出仍会通过的五类。**上上个版本正是因为夸大残留声明被抓过**
- **一条自定的迭代上界**：派返工时明写「若下一轮评审仍在误拒那一类上有发现，就登记残留、收轮，转去 app 线」。**用户的主诉求是 app，hopper 是手段**，不在支线上无限迭代
- **遗留**：返工后未再评审即发布（与 rounds/0002 同），**已并行补派确认审 T-109 不阻塞主线**；残留五类结构性形状未修；连续两轮「返工后未再评审」是否该固定为「返工必补审」未决

## 2026-08-13 hopper 0.56.0（BREAKING）：一个裸竖线能静默换掉派给谁、以及任务书写了什么

- **场景**：goal 003 简化后的第一轮真修复（rounds/0002）。用户要求**动手前先同步核实远端**——这一步逼出主会话两次测量失误（详见下）
- **现象（修复前）**：`parseRowCells` 用 `split('|')` 无脑切、`extractRow` 一律按下标取，**全程不校验行的 cell 数是否等于表头列数**。Brief 里出现字面量竖线时该行被多切出 cell、其后所有列整体右移。实测 `| … | 前半段任务 | codex | 后半段被吃掉的关键要求 |` → **`brief="前半段任务"`、`vendor="codex"`、零报错**。**Approved-Vendors 守卫拦不住**——它拦的是「vendor 名不认识」而非「brief 被截断」
- **用户裁定方案 A（强制等宽，BREAKING）**：主会话给了 A/B 两案与**精确到行的代价**（插件夹具 18 行需迁、外层仓 0 行）后由用户裁。**理由是 B 会让「等宽抵消」永久可用**——既有 6-cell 行加一个杂散竖线恰好变成 7，与合法行**不可分辨,任何基于数格子的规则都分辨不了**
- **评审判 REWORK，四条发现全部由主会话独立复现**：①插件**自己的** `.hopper/queue.md` 解析失败（第 19 行 6 vs 7）②集成测试 **3 pass / 4 fail** ③等宽抵消绕过 ④**重复 task ID 静默取第一条**（`findEligibleTask` 用 `Array.find`）——第 ④ 条是**同族第五处**，评审新发现
- **其中两条源于主会话自己的疏漏,如实记**：①**brief 写漏了**——只让实现方查**外层仓**的 `queue.md`、还特意注明「该文件在插件仓之外」，**从没提插件自己也有一个**；②**复核有盲区**——`npm test` **只跑 `tests/unit/`**，那 4 条集成失败在「1353 pass / 0 fail」里**完全看不见**，而 scope-lock 里还写了「不改 `tests/integration/`」，进一步强化了盲点
- **评审的论证比主会话原判更强**：关于「一行不合规该不该让整个文件失败」，主会话原判是「保持严格」，评审指出真正的问题**不是严格与否而是武断**——`| |` 抛错、`| | | | | | | |` 放过，同样不承载数据，仅因竖线数量不同就区别对待。采纳：全空行在守卫前跳过，有内容的行整文件 fail-closed
- **残留边界如实写进 CHANGELOG**：强制等宽**不等于完全消除**。真正的短行现在被拒；同样意图加一个杂散竖线仍会落在 7 格上静默错位；但**同一杂散竖线出现在本就写满 7 列的行里会自曝**（8 vs 7）。写成「**收窄到会自曝的角落**」。上一版正是因为夸大（称会产生「8 个及以上 cells」）被评审抓住
- **复验结果**：✅ 通过。unit **1359 pass / 0 fail**、**integration 7 pass / 0 fail**（修复前 3/4 fail）、主会话自建 **10 例探针 10/10**、**破坏性反证 ×3 各先验注入命中再看红**（PASS 掉到 9/8/9）、`tasks.js` diff 为空、`tests/integration/` 未被改动（只迁夹具）、**安装产物复验**从 `~/.claude/plugins/cache/.../0.56.0/` 导入三条判据全过、**端到端**真派 grok 原样回出两个字面量竖线与尾标记
- **遗留**：①**返工后的最终形态未再经独立评审即发布**——0.55.0 那次同情形是补派确认审的，此处如实留痕，补审建议记在 `rounds/0002/decision.md`；②缺陷 ⑤（结构性正文冒充有效 spec）未修，留独立轮；③**`npm test` 不含 integration 的盲区是流程性的**，是否固定要求两套都跑未决

## 2026-08-12 goal 003 收首轮：这一轮把自己的前提审掉了，双路首次收敛

- **场景**：用户裁定把插件迭代从 app goal 独立成 goal 003，并开首轮（PG-1 建判据 + PT-2 kata 闭环）。动手前按用户要求派双路设计审
- **结果**：**codex 与 grok 一致判 REWORK——本会话双路第一次收敛**（此前三轮每次都分裂）。计划范围**一项未执行**，因为评审否掉的是前提本身。用户随即裁定「退回更简单的形式」
- **两家独立撞到的同一处**：**goal 003 暂停了自己的真实使用来源**。设计声明缺陷来自 goal 002 的使用现场、`thresholds.md` 又要求「缺陷来源必须来自真实使用」，而「插件优先」被主会话落成「002 paused」，**把样本源冻结了**。这是主会话执行用户裁定时造成的——裁定没问题，是落地方式没意识到 003 的输入来自 002
- **grok 单独推到底**：成功条件与开轮规则**互相矛盾**——要达成需开满 5 个干净轮；要开轮按 Non-Goal 需有真实缺陷暴露；而暴露的缺陷往往本身就是静默失败 → 计数归零。三条合法路径全坏，**rounds/0001 自己就在违反 Non-Goal**
- **codex 单独抓到**：定义内部有**量词冲突**——「**所有**可见信号都显示成功」与「有没有**一个**绿灯在说谎」不是同一标准。**主会话用来论证「消费方没读也算静默失败」的那个例子，按自己的定义并不成立**。它给的更准表述已保留：「约定的后置条件未成立，而端到端决策仍被记录为成功」，其下分 `producer-silent` / `consumer-silent`
- **预登记对照**（派出评审前写死）：4 条命中（约束是装点 / PG-1 该降级 / 有反向激励 / 合并会不可证伪）、**1 条说错**（grok 更正「少开轮不会让 N=5 更易达成」）、**5 条完全没想到**（输入源被掐断、0001 自身违规、Status 与实际不符、量词冲突、拟议验收改动在本轮 scope-lock 下**根本非法**）。**若无预登记，这份对照无法成立**
- **处置**：goal 003 重写为常设无终态形式——**砍掉可计数的成功条件**（不可操纵的形式在此场景做不出来），**保留两家都认可的「每次修复七条验收标准」**；`Active goal` **交还 002**（修掉输入源被掐断的结构缺陷），「插件优先」以规则保留（缺陷一暴露就中断 app 工作先修）
- **一条关于「可复用」的结论**（用户当面质疑引出）：`.harnessloop/` 按定义是项目私产，只有三个插件会装到别处；但**「落进上游仓」本身不构成约束**——上游是同一人的仓、提出方即接受方，一行文案就能满足字面。**实质门槛只能是机器可检的「去掉会红、装上去会绿」**，与「没红过的反证不算反证」是同一句话
- **复验结果**：机械门 exit=0 / violations 0。**过程中门抓到主会话 decision.md 的三个格式错**（`Review:` 不支持多路径、`Acceptance evals: not-run` 非法取值、`Review digest` 必须匹配 `Review:` 指向的那一份），逐个改正
- **遗留**：rounds/0001 判 `neutral` / `Accepted: no`，不计任何数；PT-2（kata）未执行，另行安排；hopper ④⑤ 与两条文档漂移、TH-0031/TH-0032 仍未修

## 2026-08-12 hopper 0.55.1：守卫上岗第一件事是抓住了写它的人

- **场景**：0.55.0 发版过程中发现 `package-lock.json` 的 `version` 停在 0.50.0、落后 5 个版本。当时为保持插件树与被三轮评审审过的版本逐字节一致，只改了值、没补守卫，登记为遗留。用户随后指定补上
- **现象的要害不是"漏了一个文件"**：`package-lock.json` **白纸黑字写在 CLAUDE.md 的发版清单里**，照样漂了四次发版。所以根因不是清单不全，是**写下来的清单本身不构成任何检查**——这比此前 README 徽章、`.codex-plugin/plugin.json` 那两次都更锋利，那两次好歹还能归因于"清单没列全"
- **两条既有守卫为什么都看不见它**：`claude-code-host.test.js:180` 的 `version consistency` 与 `vendored-plugin-sync.test.js` 的 `release metadata` **都是硬编码枚举**——逐个点名 plugin.json / package.json / CLI / smoke.md / vendors.md，两条都从未提及 `package-lock.json`
- **插件改动**：0.55.0 → **0.55.1**。新增 `tests/unit/version-discovery.test.js`——递归走全仓 `*.json`（跳过 `node_modules`/`.git`），发现三种承载「本包自身版本」的形态并断言全部一致：顶层 `.version`、`.plugins[*].version`（marketplace 目录条目，它自己就有两处）、`.packages[""].version`（package-lock v2/v3 的自身条目）。**难点在第三种**：该文件有 **354 个第三方依赖条目各带 version，一个都不能收**，只有空字符串键那条是本包自己的；已实测确认恰好贡献 2 处
- **另加一条"防空扫也绿"的下限断言**：一个什么都没匹配到的发现式扫描会**静默通过**——而那正是本轮 0.55.0 反复在修的同一族错误：**看起来在检查，其实什么都没检查**
- **复验结果**：✅ 通过。主会话独立复跑 `npm test` **1348 pass / 0 fail / 2 skipped**（1350 总）、`sync --check` exit 0、`tasks.js` diff 为空、collector 实测 **2 处自身版本 / 354 个依赖条目一个未收**。**破坏性反证的两半都验了**：把 package-lock 改成 0.50.0 → 新守卫红，**而旧的 `version consistency` 守卫仍 17/17 全绿**——**后半才是要证明的东西**，它说明缺口真实存在而非碰巧没触发；嵌套的 `plugins[0].version` 单独改也能红
- **守卫上岗第一件事是抓住了写它的人**：主会话做反证时用 `git checkout --` 还原文件，**还原基准是 HEAD（0.55.0）而非工作区（0.55.1）**，等于静默撤销了两个文件的 bump，且 `git status` 里看不出异常（那两个文件正好回到了 HEAD 状态）。**是这条新守卫当场把 4 个位置逐条报出来的。** 它抓的正是"清单会过时"的同一族错误——我以为 `git checkout --` 是安全的还原动作，实际它的基准与我以为的不一样
- **版本号取 patch 而非 minor**：依据是 CHANGELOG 自己 Versioning 节的「patch is reserved for the rare non-functional tweak」。本仓 0.20.0 以来实际全走 minor，但**写下来的规则明确给非功能性改动留了 patch**，按写下来的走
- **遗留**：`docs/archive/ISSUES.md` 里 Closed 索引的 `prompt-artifact-lifecycle-and-windows-permissions` 一行状态文字仍写着 open（grok 在 T-103 指出，既存、非本轮引入；判它究竟开还是关需要单独查证，未顺手改）

## 2026-08-12 hopper 0.55.0：brief-drop 闭环——修好之后，双路评审又在「修好了」里各自挖出一层

- **场景**：2026-08-11 已登记的 hopper 缺陷（见下方同名条目）单独开一轮修。用户裁定「插件优先」，并要求**改动经异构模型审核**，且明确要**先审设计、再审代码**两道
- **现象（修复前）**：queue.md 有行、`handoffs/leader-tasklist.md` 无该 task 条目时，`loadTaskSpec()` 的两条未命中分支**返回自述文案冒充 spec**（`(no detailed spec found …; using queue.md brief only)`、`(no leader-tasklist.md found …)`）。**那句「using queue.md brief only」是假话**——brief 根本没进 prompt。vendor 收到一份没有任务的任务书，照样 `exit 0` / `status: done`
- **根因的机械形状**：`loadTaskSpec(hopperDir, taskId)` **入参里没有 `task`**，函数内根本拿不到 brief；而调用点作用域里 `task` 早就在。**`--adhoc` 路径从无此问题**（`const taskSpec = brief`），坏的只有 queue 那条。**测试为什么没抓到**：`dispatch-governance.test.js` 的 fixture **总是写 leader-tasklist.md**，两条撒谎分支从未被走到
- **两道异构评审各自抓到不同的东西**：设计评审（T-099）裁了「有详细 spec 时 brief 要不要也并入」的甲/乙之争——**判乙（合并）**，决定性证据是 `tasks.js:154-155` 已明写「brief 和 Task spec 是完整闭环」；代码评审（T-100）**双路分裂，codex 是对的那一路**：codex 判 REWORK 并**实跑抽取函数**给出反例 `{"loaded": "## T-1"}`——修复后的 fail-closed 判据是「section 非空」，而 `## T-1` 这个**光标题没正文**的小节非空，于是照样被当 spec 派出去；grok 判 PASS_WITH_NOTE，**这条一句未提**
- **第三轮评审（T-102，用户要求"过一道评审再推"）又判 REWORK，双路再次分裂、codex 再次是对的那一路**：codex 给出可执行反例——leader-tasklist 里 `## T-1` 紧跟 `## T-2` 时，**T-1 拿到的 spec 装的是 T-2 的正文**。**这比原缺陷更糟：原缺陷是"没有任务"，这是"别人的任务"**。grok 判 PASS_WITH_NOTE，虽提到「pre-existing short-window section bleed」却**降级成了残留 note**
- **主会话复现后发现范围比 codex 报的更宽，是两个独立根因**：**(a)** `rest.slice(50)` 魔数跳过前 50 字符，短小节里的下一个标题看不见；**(b)** **边界正则只认 `^##\s+`，而 marker 正则认三种形态**——用粗体或表格行写的 leader-tasklist **一直在跨任务串内容，与小节长度无关**。(b) 两家评审都没点出
- **第一版边界修复被主会话打回**：实现方把边界改成「已知 id 的 marker」，但写成 **if/else 替代**而非并集，结果两条路径各坏在对方好的地方——真实路径（`resolveDispatch` 总是传 `otherTaskIds`）**丢掉了通用标题边界**，未在 queue.md 里的任务（本仓 T-091…T-100 全走 `--adhoc`、无 queue 行）不再能终止上一节；fallback 则把正则放宽成 `^##+\s+`，**把 spec 自己的 `###` 子标题当成了边界**。**真实路径一度比修复前更差**。改为并集后两半各配反证：拆掉 H2 那半 → `## T-91` 泄漏回来；放宽成 `##+` → `###` 被截断
- **同一个失败形状，本轮一共暴露出四个实例**：①无条目时返回自述文案冒充 spec（已修）②裸 marker 光标题没正文、非空即冒充 spec（已修）③跨任务边界失效、拿到别人的正文（已修）④**主会话自己发现的第四处，在 `queue.js`**：brief 里未转义的 `|` 会静默截断 brief 并顶掉 Vendor 列，竖线后若恰好是已批准的 vendor 名就**完全无声地派出半份任务书**（已登记，未修）。**共同形状：「看起来有内容」被当成了「真的承载了任务」**
- **codex 还额外指出**：`fileExists` 把 `access()` 的**所有**错误吞成 `false`，EACCES 会被误报成「文件不存在」——正是本项目反复踩的「找不到 ≠ 不存在」那一族。已收窄为仅 ENOENT 映射 false
- **插件改动**：hopper-plugin 0.54.0 → **0.55.0**（先 `pull --ff-only` 同步上游，CLAUDE.md 记着 2026-07-28「落后 65 提交、整版改动作废」的教训）。`loadTaskSpec` 导出并返回 `string | null`、新增 `composeTaskContent()` 合并 spec + `### Queue brief` 并声明优先级、两端皆空则抛错。**`cli/src/tasks.js` 一字未改**（其 `composePrompt` 形状被 4 条逐字节断言锁死）
- **顺手补了一条发现式守卫**：三个 README 的版本徽章**停在 0.50.0、落后 4 个版本且两条既有守卫都不覆盖**。新增 `readme-version-badge.test.js`。**这又是一次「清单会过时，发现式守卫不会」**
- **提交前又撞到同一课的第五个实例**：`package-lock.json` 的 `version` **停在 0.50.0、落后 5 个版本**。它**明明就写在 CLAUDE.md 的 7 处清单里**，照样漂了——**说明清单被写下来也没人真按它走**，而全仓唯一引用 `package-lock.json` 的测试是 `license-integrity.test.js`（且只为 license 字段特判），**版本字段无任何守卫**。本轮已随发版改正为 0.55.0，但**守卫没补**——为保持插件树与被三轮评审审过的版本逐字节一致，未在推送前扩范围。**留作下一轮：把 `readme-version-badge.test.js` 那种发现式守卫扩到 `package-lock.json`**
- **复验结果**：✅ 通过。主会话独立复跑 `npm test` **1345 pass / 0 fail / 2 skipped**（1347 总，基线 1331 + 16 条新增）、`sync-vendored-plugin.mjs --check` exit 0、`git diff cli/src/tasks.js` 为空、**主会话自建 15 例探针 15/15**（fail-closed 六形态 + 跨任务泄漏三例 + 未知 id 回归两例 + 不得过度截断四例）。**破坏性反证共四轮，每轮都先看到红**：判据改回 `section.length > 0` → 3 条红；拆掉「H2 永远算边界」→ `## T-91` 泄漏；放宽成 `^##+\s+` → `###` 子标题被截断；实现方侧另两轮 2/14、4/14 红。**端到端**用 queue 行（非 `--adhoc`）真派 codex + grok 双家，两家都原样回出指纹 `HOPPER-E2E-Q101-BRIEFREACHED-7F3A2C`——对照当初 T-090 的 vendor 输出是「What is the T-090 queue brief?」
- **一条关于"偶发失败"的纪律**：实现方两次报告「1 个无关测试偶发失败、重试未复现」。**第二次退回要求给证据而非归因**，它如实撤回了「已知 flakiness」的说法：连跑 8 次全绿、当时未存原始输出、`# fail 1` 但全文无任何 `not ok` 行、**无法指向任何具体失败项**。主会话另跑 4 次（原始输出全部落盘）均 exit 0。**结论是"查不出"而不是"没问题"，如实留痕**
- **一个附带消失的假象**：`--resolve` 过去自报的 composed 长度**恰好等于「不含 brief」的长度**（959 字 brief、自报 2868），这正是「看起来一切正常」的来源。现在自报 3005 与实际 prompt 长度**一致**
- **遗留**：①**尚未 `plugin-reinstall.sh` 重装**——本轮全部验证跑的是 submodule 内的 `cli/bin/hopper-dispatch`，**全局安装的仍是旧版**，重装需重启会话，留给用户决定时机；②尚未 push，用户要求「再决定是否提交」；③queue.md 第 107 行有一条残缺的 `| ` 行（既存，非本轮引入）；④**本轮新开三个 issue 均登记未修**——`queue-brief-truncated-by-unescaped-pipe`（第四实例，`queue.js` 列解析按下标静默取值，建议加「行 cell 数须等于表头列数」的 fail-closed 守卫）、`task-spec-structural-only-body-accepted`（正文只有 `---` 等结构性标记时仍被当有效 spec，grok 发现）、`composeprompt-no-fail-closed-on-empty-spec`（`tasks.js:169` 无纵深防御，唯一防线在上游；该文件被 4 条逐字节断言锁死，属本轮 scope 约束而非技术阻碍）。ISSUES.md Open 计数 6 → **10**

## 2026-08-12 rounds/0016 收盘：审批 FSM 四条边界失败态达成，`Accepted: yes`

- **场景**：0015 的审批主判据已达成但审查闸判 REWORK，用户裁定收 0015 开 0016 专做那四条边界失败态
- **harnessloop**：**「同一把尺子」这次给出了相反的结果**——0015 审查闸 REWORK + MUST-FIX 到 6（守卫阈值 3）→ `Accepted: no`；0016 PASS_WITH_NOTE 且四条 note 中三条是「别再动」→ `Accepted: yes`。**判定差异来自审查结论本身，不是标准松紧**。这是纪律第 4 条连续三轮（0014 yes / 0015 no / 0016 yes）给出可复现结果
- **hopper**：本轮换 grok（0015 连派 codex 两轮）。**双路轮换的第二个价值显现**：grok 不仅验了四项实现，还逐条裁定了实现方对 codex 的**四条纠正**，**全部判 Holds**——即前一位评审方在四处说错或说得不够，由后一位独立确认。**单派一家拿不到这层交叉校验**
- **实现方在自己第一版实现里抓到会回归主链的 bug**：codex 写「权威 **timeout** terminal」，实现方先按「任何权威 terminal」写，随后读内核发现 `applyApprovalDecision`（广播 terminal）**先于** `respond(true,…)`，同一条 WS——**用户点「允许」后 terminal 先于 RPC 响应到达**，宽读法会把用户自己在途的决议判死（命令实际执行了 UI 却报错）。收窄到 `status=="expired"` + 正反两向测试。**该顺序经主会话核源码偏移与 grok 追 durable path 两个独立来源确认**
- **一个 live 现场比任何构造测试都有说服力**：验拒绝路径时，agent **主动伸手去读用户真实的 `~/.openclaw`**（`ls ~/.openclaw`、`grep -ri "deny" ~/.openclaw/openclaw.json`），**审批关卡把它拦下来了**。rounds/0013 的现场是无关卡直接执行——同一条命令在那时会直接读到用户真实配置且无人被问过。同时印证 rounds/0013 的判断：**隔离的是 openclaw 自己的 state，不是被执行命令的可及范围**
- **安全纪律的一次真实执行**：live 复验中途用户回到机器前，前台被切走。主会话**主动中止 UI 自动化**（继续按坐标点击会点进用户正在用的窗口）、清理实例、等用户说方便再补完。这是用户「谨慎不要误操作」的直接落实
- **如实记的一处偏差**：拒绝路径的测试载体与设计不同——我发的是 `echo R16_DENY_SHOULD_NOT_RUN`，agent 看到命令名就自己决定不跑、转而查策略，我拒绝的是那次查询。**机制验证成立，但「验到了机制」与「验到了我打算验的那条」是两件事**，未重跑到"合意"为止
- **复验结果**：74/74（本轮 +6）、CI 平价 12/0/1、**D1 七法 git diff 为空**、三端 codegen 四项 exit 0、RAE-0001 pass、live 主链不回归、四条反证 **7 个拆除点**逐字冻结（两条的红是「测试进程挂死 35 秒」）
- **遗留**：非 `expired` 终态的 UI 清卡与 `ApprovalBufferResolvedEvent.reason` 词表均**需动 D2 契约**，★审查闸建议 **park 为显式设计轮议题、不是静默产品债**——采纳

## 2026-08-12 rounds/0015 收盘：exec 审批关卡立起来了，但审查闸两轮 REWORK、收敛守卫越线两倍

- **场景**：用户裁定 rounds/0013 Human Decision 第 2 项后开轮，做 exec 策略 = `ask` + 审批 UI
- **达成**：审批端到端 live 跑通——卡片渲染 → 点「允许一次」→ **命令真执行**；点「拒绝」→ **命令未执行**、会话不挂死。帧回放 50/50 → **68/68**，CI 平价 12/0/1，**D1 七法 git diff 为空**，RAE-0001 不回归 pass
- **harnessloop**：**收敛守卫第一次真正生效**。scope-lock 写「第 3 个 MUST-FIX → checkpoint」，本轮实际到 6，主会话按纪律停下向用户 checkpoint 而非自行迭代。**这条守卫此前从未被触发过，本轮证明它不是装饰**——若没有它，我会继续在同一轮里追边界失败态，把一个已达成主判据的轮次拖成无限返工
- **hopper**：**双路异构派发第一次成为决定性因素**。同一 brief 同时给 codex 与 grok 分析「审批为何送不到客户端」：主会话预登记的答案（channel = `webchat`）**错了**，三条候选全在错误的那道门上；**grok 找到正解**（`canDeliverApprovals` 的客户端 caps 通路，内核注释明写该通路是给「newer non-UI bridges」的），**codex 那一路全程未提**。单派一家这轮会继续在 channel 上打转
- **方法论：预登记**。主会话在看到任一方产物**之前**把自己的答案写进 `channel-decision-prereg.md`，含一句「Q3 这一条我没查——正是最容易只搜一处就下结论的地方」。事后证明答案正在那里。**不先登记就无法确证「不是被带过去的」**——这次复盘的可信度完全建立在这个动作上
- **runtime 审查 > 纯读源码**（用户 2026-08-12 提出）：本轮三个坑纯读源码都抓不到——代码与注释**自洽**，只是与现实不符。(1) 审批关联采集在 `case "approval"` 里找 `phase:"requested"`，实际帧是 `stream:"lifecycle"` + `phase:"waiting-approval"`，**代码从未执行到那一行**；(2) `approval_not_pending` **不是错误码**，openclaw 回 `ok:true + applied:false + 终态快照`，按错误码 catch 一条都抓不到；(3) 旧代码在「用户点拒绝、审批刚被 stop 强制 deny」时**静默显示成功**。全靠 wire trace 里的真实帧照出来
- **发现的项目级落差**：主会话让子代理「在 `app/contracts/` 下核实 D1 §6.2 原文」——**那是不可能完成的指令**。`app/contracts/d1/README.md` 只有 10 行占位，D1 正文从未转录进仓库，权威原文在 `~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md`。**「契约正文不在契约目录」**已登记
- **一处评审方的诚实值得记**：codex 在只读沙箱跑测试得 60/64，**自己标注**四条失败全是持久化测试因禁止写临时文件所致、「不能替代冻结验收日志」。主会话正常环境是 68/68。**它没把环境差异当发现来报**，否则会浪费一轮去追不存在的回归
- **复验结果**：主判据达成但 ★审查闸 REWORK → `Accepted: no`（scope-lock 通过线是 PASS/PASS_WITH_NOTE，纪律第 4 条不许在验收时放宽）
- **遗留**：T-096 的四条 FSM 边界失败态转 rounds/0016；`capabilities()` 桩的漂移风险、超时态无 D2 对应、`ApprovalBufferResolvedEvent.reason` 词表表达力不足均已登记

## 2026-08-11 rounds/0014 收盘：会话持久化解除「基本使用」唯一阻断，首次 `Accepted: yes`（自 0010 以来）

- **场景**：用户裁决 rounds/0013 Human Decision 第 1 项后开轮，只做会话持久化一件事
- **harnessloop**：协议闸再次先于人发现问题——`Review:` 字段写两个路径导致 `review-path-not-found`（0013 也踩过同一处）。收盘 0 violations。**值得记的是判定对比**：0013 审查闸 REWORK → `Accepted: no`；0014 PASS_WITH_NOTE → `Accepted: yes`。**同一把尺子（纪律第 4 条「按字面标准验」），两个结果**——这正是标准有效的证据，而不是标准松紧不一
- **hopper**：本轮换 grok 派审查闸，**必须走 `--adhoc` 通道**绕开 0013 实证的 queue-brief 静默丢弃缺陷（该缺陷已按 user-confirmed 授权在 `hopper-plugin/` 内建 issue，未改代码未 bump 未 push）。**另发现一处 vendor 输出模式差异**：hopper 对 grok 标 `bufferedOutput vendor`，raw log **只收尾部 JSON、不含中间工具调用**（29 行），而 codex 是全量转录（12006/6006/2712 行）。我据此差点判定「grok 根本没读代码」——**错了**，其 JSON 里 `num_turns: 11`/`input_tokens: 127339`/`cache_read: 893952` 表明做了实质工作，产物里也有横跨全部目标文件的 file:line 引用。**拿不同输出模式的 vendor 比 log 行数是错误的比法**
- **kata**：本轮产生三条跨轮可复用事实（两套 history 分页实现、`ready` ≠ `sessions.create` 可用、bufferedOutput vendor 的 log 语义），按沉淀钩子记入工程 wiki
- **发现的框架/工具缺陷**：(1) `repro/start-isolated-kernel.sh` 的就绪判据是日志里的 `[gateway] ready`，**不足以保证 `sessions.create` 可用**——实测该 RPC 仍返回 `UNAVAILABLE: sessions.create unavailable during gateway startup`，我一度把它误判成 0014 引入的回归。本轮以加延迟绕过，**未修**；(2) `fetchFullHistory` 对非布尔 `hasMore` 是静默停止而非报错（审查闸 note）
- **复验结果**：✅ 重启后两个会话都回到列表、会话 1 完整对话恢复、恢复的会话发新消息 `messageSeq` 从 2 接到 4（**同一内核会话**）。两条破坏性反证均由主会话亲手做到先看到红（坏文件→不崩溃；强制只取第一页→50/50 掉到 48/50）。50/50、CI 平价 12/0/1、**D1 七法签名逐字未变**、三端 codegen 全绿、RAE-0001 重跑 pass
- **遗留**：审查闸三条 note（非布尔 hasMore 静默停止 / placeholder handle 把 kernelSessionID 设成 kernelKey / live 未覆盖多页历史与会话2非空历史）均**刻意不当轮改**，以保持「被评审的状态 == 最终状态」——这是 0013 的直接教训

## 2026-08-11 rounds/0013 收盘：三插件同轮受验，★审查闸两轮都抓到真问题

- **场景**：SG-10 L1 的两个里程碑轮（学习点 + mac app 基本使用），B→C→D 三块
- **harnessloop**：协议闸全程可用，`verify_protocol.py` 抓到两次真实违规——(1) 我在 scope-lock 的 Allowed Changes 里把路径写成缩写 `.../rounds/0013/`，守卫按字面解析判 scope-lock-violation（**守卫是对的，缩写是我的错**）；(2) `Review:` 字段里塞了两个路径导致 `review-path-not-found`。**两次都是守卫先于人发现问题**。收盘时 0 violations
- **kata**：工程侧沉淀钩子（2026-08-11 加入 CLAUDE.md）**首次实跑**。teach-back 经 `wiki-ingest` 归档进 `~/.llm-wiki/test-harnessloop`，新建 4 页 + 更新 7 页，18 → 22 页。kata 在 rounds/0011–0012 期间调用 0 次，本轮恢复。产出一条待批 schema 提案（tag taxonomy 加 `deepseek`，未自行应用）
- **hopper**：**发现两个缺陷**（各已单独记条），其中 queue brief 静默丢弃那条是本项目「codex 评审三项强制核对」第一次真的救场——`exit 0` + `status: done` + `Task completed successfully.` 三个绿灯全亮，而任务内容根本没送到。改走 `--adhoc` 通道后评审正常，两轮共读 18000 行、给出三项实质发现
- **审查闸的实际价值（本轮最值得记的）**：两轮都判 REWORK，**且都对**。T-090b 指出「RAE-0001 的 pass 靠叙述不靠冻结证据」——属实，我把结果写进了 md，原件却全在 scratchpad；还实证了对账脚本五条假绿路径（附内存合成复现）。T-091 复审又指出五条里还剩两条（wire 侧 role 缺失被静默过滤、bool 与 int 因 `True == 1` 混淆）。**没有这两轮，本轮会拿着一份「看起来很完备」的假证据收盘**
- **复验结果**：RAE-0001 四条件逐条有冻结原件（25 文件 / 2.99MB），对账跑在 `hasMore:false` 的可证完整 history 上，判 **pass**；★审查闸 **REWORK**，故本轮 `Accepted: no`（scope-lock 写的通过线是 PASS/PASS_WITH_NOTE，纪律第 4 条不许在验收时放宽解释）
- **遗留**：会话不持久（「基本使用」唯一阻断，不在原 L2 清单内）、exec 策略产品裁决、是否需第三轮评审——均交用户。详见 `rounds/0013/decision.md` 的 Human Decision Required

## 2026-08-11 hopper：queue.md 的 brief 在无 leader-tasklist 条目时被静默丢弃（exit 0 且自称成功）

- **场景**：rounds/0013 收盘前派 ★审查闸（T-090，`code-review-adversarial`，vendor=codex）
- **现象**：44 秒返回 `status: done` / `exit_code: 0` / `Task completed successfully.`，但 codex 的输出是 `## Open questions — What is the T-090 queue brief?` 与 `Verdict: FAIL`。实际收到的 prompt 里 `## Task spec` 段只有一行占位符 `(no detailed spec found for T-090 in leader-tasklist.md; using queue.md brief only)` —— **那句「using queue.md brief only」是假的，brief 并没有被拼进去**
- **机械证据**：queue.md 里 brief 长 959 chars；codex 实收 prompt 段 2874 chars；`--resolve T-090` 自报 composed length **2868 chars**（≈ 不含 brief 的长度）；若含 brief 应约 3833 chars。`'RAE-0001' in prompt` = False，`'no detailed spec found' in prompt` = True。**合成阶段就丢了，不是传输截断**；而 `--resolve` 的显示界面照常回显完整 Brief，制造「一切正常」的假象
- **触发条件**：仅当任务在 `.hopper/handoffs/leader-tasklist.md` 中没有详细 spec 时。对照组：T-088/T-089 各有 2 处条目 → brief 正常到达（prompt 中特征词命中 26 次）；T-090 有 0 处 → 丢失。**这就是前 89 个任务都没暴露它的原因**
- **反证**：同一 brief 改用 `--adhoc --brief` 重派，`Prompt: inline argv` 从 3193B → **4753B**，brief 确实进入。同 vendor / 同模型 / 同 sandbox，唯一变量是 queue 行 vs adhoc
- **预期**：要么真的把 queue brief 拼进去；要么占位符如实说「brief 未包含」。**静默的假陈述比缺失本身更危险**
- **插件改动**：**本轮未修** —— `hopper-plugin/` 是三插件 submodule，rounds/0013 scope-lock 明文禁止改动。待办：在 hopper-plugin 内开 `ISSUE-queue-brief-dropped-without-leader-tasklist.md`
- **复验结果**：n/a（未修）。审查闸改走 adhoc 通道重派后正常工作
- **遗留**：这条是 CLAUDE.md「codex 评审三项强制核对」（(a) 审查对象 (b) 产物落点 (c) 不得仅凭 exit 0 采信）**第一次真的救场**——三个绿灯全亮而任务内容根本没送到。完整取证见 `.harnessloop/goals/20260718-002-agent-app/rounds/0013/evidence/hopper-defect-queue-brief-dropped.md`

## 2026-08-11 本机环境：`~/.local/bin/hopper-dispatch` shim 指向已不存在的旧安装路径

- **场景**：同上，首次调用 `hopper-dispatch` 派发
- **现象**：`Error: Cannot find module '/Users/litianyi/.claude/plugins/marketplaces/agent-hopper/cli/bin/hopper-dispatch'`。该 shim 写于 2026-06-18，硬编码 marketplace 目录路径
- **根因**：`scripts/plugin-reinstall.sh` 已把全局 marketplace 重指为 `directory <本项目>/hopper-plugin`，安装缓存落在 `~/.claude/plugins/cache/agent-hopper/hopper/0.53.0`；旧的 `marketplaces/agent-hopper/` 目录不复存在。**shim 不在任何重指流程的覆盖范围内**
- **插件改动**：无 —— shim 在仓外、不在本轮 Allowed Changes 内，**不动**；改为直接调 `node hopper-plugin/cli/bin/hopper-dispatch`
- **遗留**：**本项目插件迭代回路的缺口**——`plugin-reinstall.sh` 重指 marketplace，但没有任何东西重指用户 PATH 上的 shim。同类问题第二次出现（前一次见另一项目的 `ISSUE-stale-dispatch-binary.md`），说明这不是偶发

## 2026-08-11 补记 rounds/0011–0012（本条是钩子缺失的直接证据）

> **补记说明**：本文件停在 2026-07-16，其后跑了 12 轮、三插件全审、统一 MIT、提上游 PR、开 TH-0031，**一条未记**。
> 根因不是纪律而是机制——史官有五个触发节点所以一直活着，本文件**一个钩子都没有**。
> 2026-08-11 已在 `CLAUDE.md` 加「工程侧学习/沉淀钩子」一节。**本条即为补欠。**

- **场景**：goal 002 SG-10（Mac UI 壳 L1）rounds/0011（首轮）与 rounds/0012（修复轮），全程走 harnessloop 协议 + hopper 异构评审。
- **现象/发现（按插件分）**：
  - **harnessloop**：开新轮会让 `loop_anomaly_skipped_unparsable` 从 2 掉到 1，**下降与状况改善无关**——新轮无 `decision.md` 时 `_latest_round_decision_text` 返回 None、整个 goal 被跳过计数。已开 **TH-0031**（P3）。另：`Review:` 与 `Acceptance evals:` 两字段严格解析，加括号注解即红——**守卫正确**，非缺陷。
  - **hopper**：① `~/.local/bin/hopper-dispatch` shim 指向已不存在的 marketplace 路径（插件更新后未跟上），改用 submodule 内 CLI 派发；② **runner 异常终止后状态文件停在 `in-progress`/`phase: starting`，而产出早已完整落在 raw log**——差点导致第三次重派（每次都是真实 vendor 花费），已开 `ISSUE-stale-status-on-runner-death.md`；③ codex 基线 timeout 300s 对「搜源码+答四问」型 brief 不够，需 `--timeout` 显式加大。
  - **kata**：**整个 rounds/0011–0012 期间调用 0 次**。CLAUDE.md 既定验证方式是「边用边验证」，**没用就是没验**——这是本次最该记的一条，也是加钩子的直接动因。
- **预期**：三个插件都应在真实使用中被持续验证（CLAUDE.md「插件迭代回路」与「边用边验证」）。实际只有 harnessloop 与 hopper 被高频使用，kata 完全空转。
- **插件改动**：
  - harnessloop：**未改**——TH-0031 为 P3 观测项，不阻断，登记待裁决。
  - hopper：**未改**——两条 issue 均登记未修（`ISSUE-stale-status-on-runner-death.md` 新增）。
  - kata：**未改**——未使用，无从发现问题。
- **复验结果**：机械门（`verify_protocol.py` / `check_setup.py`）全程 exit 0；三轮异构评审（T-081..T-087）逐轮推翻—返工—再验；rounds/0012 收盘 `Accepted: no`（RAE-0001 条件③ 结构上不可满足，非执行失败）。
- **遗留**：
  1. **kata 的验证仍是空白**——新钩子把「每 3 轮沉淀一次」绑到 kata，靠它自然产生使用。
  2. TH-0031 待裁决修复方向（A 分离计数 / B 回退上一收口轮 / C 只改文档）。
  3. hopper 两条 issue 未修。
  4. **本项目反复出现同一类错误**：搜索维度选错，把「我没找到」当成「不存在」——`logging.file`、D2 §3.3 subscribe 响应、targeted 帧的 `EventFrame.seq`，**三次都由异构评审纠正**。此条已列入新钩子的「值得沉淀」判据。

## 2026-07-22 D5 产品规格弧：三条过程教训（Workflow 并行起草/finding 转述编号漂移/改了一半留残留）

- **场景**：D5（仿 codex app 产品规格，9 页）完整弧——T-021 调研 spike → workflow 并行起草（foundation+7 子面+总纲）→ 双轨对抗复核（grok T-022 PASS_WITH_NOTE / codex T-023 REWORK，F-01~F-10）→ v2/v2.1/v2.2 三批修复 → codex T-024/T-025 两轮定向 re-verify → T-025 判 CONFIRMABLE(7/7) 正式定稿
- **现象（三条独立教训，均在同一条 D5 弧内暴露）**：
  1. **Workflow 并行起草的文件名互猜**——v1 阶段多个子面 agent 并行写作时，foundation 给出的是"建议文件名"，各子面页写作时只能猜测其余页最终会叫什么名字，导致 d5-3/d5-5/d5-7 多处正文出现指向"从未真正存在过的文件名"的死链接（如 `[[d5-05-capabilities-tools]]`）；根因是并行起草流程本身，不是任何单页的设计缺陷
  2. **主会话转述 finding 的编号漂移**——v2 批次整理 codex T-023 的 finding 时，把原文真正的 F-05（License grace period 误称"D3 confirmed"）与 F-10（死链+protocolVersion 元数据）的对照表格 label 混淆，导致真正的 F-05 从未被处理，却被内部整理表格误记为"已收口"，直到 v2.1 批次核对原文 file:line 证据才发现
  3. **"改了一半留残留"在本弧复现 3 轮（验证范围不完整）**——v2/v2.1/v2.2 三批修复中，"核验闭合"判断本身的核对范围反复不完整：每轮只重读作者认为的"主要修订段落"，遗漏同一页内容易被忽略的旁支位置（状态图、范围边界表、跨页引用行），codex T-024 定向 re-verify 判 MUST-FIX（5/11）抓到 F-01/F-02/F-03/F-08/F-09 五项残留，直到独立于修订执行方的 T-025 才最终确认无残留
- **预期**：①Workflow 工具支持多 agent 并行起草时，理想情况应有文件名映射机制或抽象引用规范，避免死链；②评审 finding 的转述应可锚定原文编号与证据、不产生漂移；③修订与 re-verify 应有机制或纪律保证"改了一半"不被误判为"已闭合"
- **插件改动**：无（本轮均为使用观察/纪律教训，未触及 harnessloop/hopper-plugin/kata 任何 submodule 文件；①是 Workflow 工具的一个使用观察，暂未形成具体改动提案；②③是设计弧自身的过程纪律问题，非插件缺陷）
- **复验结果**：✅ 三项教训均已在 D5 弧内被后续批次（v2.1 修正②、v2.2+T-025 修正③）实际验证闭合；①暂无独立复验场景，留待下次并行起草批次观察是否复发
- **遗留**：①建议——若采用并行起草多个子面页，foundation 应等所有子面页落盘后再回填文件名映射表，或子面页统一用抽象引用而非猜测具体文件名，可考虑作为 Workflow 工具后续迭代候选（尚未开 evolution issue）；②教训固化——转述第三方评审 finding 必须逐条锚定原文 F-编号+file:line 证据，不可凭内部整理表格的编号或印象改写；③教训固化——多面互依的产品规格修订须"删旧+加新"成对，re-verify 须对每条 finding 涉及的关键词/字段名做全文 grep 逐条验闭合而非抽样重读，定稿判断本身也应被视为需要独立验证的一个断言

---

## 2026-07-22 hopper 使用观察：queue.md 写入/状态回写两个工程侧问题（D2 双轨派发时发现）

- **场景**：D2 消息 schema 双轨复核（T-014 grok / T-015 codex）派发过程中，边用 hopper 边记录的观察
- **现象**：①用 Python heredoc（`open(...).write()`）编辑 `.hopper/queue.md` 时曾出现改动未持久化的情况（疑似未 `flush`/未真正落盘，进程退出前缓冲区丢失）——换用 Edit 工具编辑 queue.md 后写入可靠、问题不再出现；②hopper 任务（T-014/T-015）在 vendor 侧完成、`.hopper/handoffs/T-0XX-output.md` 落盘 `status: done` 后，`queue.md` 表格里对应行的 `Status` 字段**不会自动**回写为 `done`——需要主会话手工核对 handoffs 产物后自行改字段，否则 queue.md 与实际任务终态之间存在状态漂移窗口
- **预期**：queue.md 作为 hopper 任务队列的单一事实源，编辑应可靠落盘；任务终态应能被追踪到而不依赖人工同步（依据 `.hopper/queue.md` 自身"Status values"字段设计意图）
- **插件改动**：无（本轮为纯使用观察，未触及 hopper-plugin/ 任何文件；是否需要在 hopper-dispatch 侧加自动状态回写机制留待后续评估）
- **复验结果**：✅ 观察成立——Edit 工具编辑 queue.md 全程可靠；status 字段本轮靠手工核对 `.hopper/handoffs/T-014-output.md`/`T-015-output.md` 的 `status: done` 后手动标记两行为 done
- **遗留**：教训固化——"queue.md 编辑用 Edit 工具、不要用 python heredoc 写入；派发/状态变更后建议尽快 commit 落盘"；hopper 任务完成后 queue.md 状态字段的自动回写（或至少一个"核对并同步"辅助命令）可作为 hopper-plugin 后续迭代候选，暂未开 evolution issue，先记录观察

---

## 2026-07-18 kata 第二迭代（2.15.4）：装机版校验缺陷根除 + 图误报豁免 + standalone 章节补齐

- **场景**：用户批准的四项候选批次，双 Sonnet 代理并行（A=三代码修复+版本，B=standalone 三章节），Fable 审查验收
- **现象**：①头号修复=schema/wiki-schema.json 未打包致装机版 schema_validate.py 从未能跑——单源迁入 plugin/schema/（全部活引用同步更新），模拟安装布局固化为 Test 63；终验从安装缓存路径（2.15.4 cache）命中原始 FileNotFoundError 复现路径→valid ②图误报两类豁免共享 STRUCTURAL_FILENAMES 单一事实源（Tests 64/65 注坏验证）③B 组 standalone 章节降级语义诚实（mcp-server 直接标 standalone 完全不可用并给替代方案）④版本判定：Sonnet 以先例分析（minor 仅留新技能能力）推翻主会话预设的 2.16.0，定 2.15.4 patch——委派模式中实现者反向纠正协调者的实例 ⑤新发现：Test 17 解析器测试不密封（被本机真实 wiki 绑定污染，git stash 基线确认既有）→下批候选
- **预期**：装机版与源码版行为一致
- **插件改动**：kata dada4fb（2.15.4，push 57d3e3d..dada4fb，版本同步条件满足）；Tests 63/64/65 新增
- **复验结果**：✅ 终验（缓存路径 schema_validate valid）、重装内容一致、smoke 套件除既有 Test 17 外全绿、build_skill_md --check 过
- **遗留**：Test 17 密封性（下批候选）；史官触发节点纪律本次首实战（版本 push→SendMessage 事件提示）

---

## 2026-07-17 Chronicler 史官体系建立：haiku 常驻记录角色 + 独立 PR wiki，首跑即产出三项发现

- **场景**：用户需求=为个人与产品 IP/PR 积累素材；设计并落地常驻轻量记录角色——.claude/agents/chronicler.md（haiku）+ 独立 PR wiki ~/.llm-wiki/surebeli-ip（milestones/stories/metrics/drafts/queries 五分类，audience/maturity 维度素材状态机）+ CLAUDE.md 五类触发节点纪律；关键设计=拉取式采集（tail 协议产物文件，harnessloop 协议零侵入）+ haiku 捕获/Sonnet 成稿两级流水
- **现象**：①首跑回填 15 页（7 milestones/4 stories/4 metrics）质量合格（PR 钩子成立、数据带出处、schema 全过）②haiku 层两个真实缺陷：index 计数虚报 18（实数 15，已修 1f1e7cf，记账规则补入章程）与回执语言漂移到日文（语言纪律补入章程）——两级流水设计的必要性首日即验证 ③用户定语言政策=中文主（SCHEMA Language Policy 落盘 4182224，15 页转换进行中）④意外发现 kata 真实打包缺陷：已安装缓存的 schema_validate.py 因 schema/wiki-schema.json 在仓库根未被打包（marketplace source=./plugin）而无法运行——装机版校验形同虚设，此前未暴露因一直用 submodule 源码路径；记为 kata 下轮迭代候选（与 standalone 三技能章节缺口并列）
- **预期**：记录零负担、素材可检索、协议不受污染
- **插件改动**：无；新 agent 定义 + PR wiki 三 commit（fe70f4d 回填/1f1e7cf 计数修正/4182224 语言政策）
- **复验结果**：✅ 角色卡生效（回退方式运行，reload 后成一等类型）、拉取式采集准确（页面事实与工程文件核对无臆造）、schema/维度合规
- **遗留**：15 页中文转换在途；chronicler 作为一等 agent 类型待 reload 验证；kata 打包缺陷待修（候选批次：schema 打包 + orphan 结构文件豁免 + 示例文本悬空链豁免 + standalone 三章节）

---

## 2026-07-17 kata 第二轮 ingest：update-vs-create 纪律验证通过 + 一次有教育意义的假警报

- **场景**：ingest harnessloop 严格审查报告（213 行 + findings.json 外部引用）到已有 15 页的 wiki——本轮考点是 update-vs-create 判定（防重复页堆）
- **现象**：①更新 4 页 / 新建 3 页，判定标准清晰（实体是否已有专属页 × 信息结构是否新概念——如 design-debt 活 backlog 与主页"版本演化叙事"是不同信息结构故新建）②零 schema 演化需求——首轮钉住的枚举当轮即发挥治理作用 ③新建 harnessloop-design-debt.md 活 backlog（P2 逐项 open/已修状态 + m7/nm11/nm12/n9 复测表），后续迭代可直接消费 ④主会话验收时一次假警报：graph neighbors 返回 0 被疑为断链，实为输出契约是 layers BFS 分层而非 neighbors 键——消费方读错契约，非 kata 缺陷；教训=断言工具缺陷前先核对输出 schema ⑤两个真实噪音级观察点：orphan 检测将 SCHEMA/log/index 结构文件计入 true_orphans、log.md 头部格式示例的字面 [[wikilink]] 被计为 dangling link——kata 候选小改进（结构文件豁免/示例文本豁免）
- **预期**：wiki 生长而非重复
- **插件改动**：无；wiki commit 51be94f（18 页，hub 网增强：harnessloop.md in/out 10→13）
- **复验结果**：✅ schema valid、更新纪律合规（updated bump + sources 追加）、design-debt 邻居网完整
- **遗留**：两个噪音级观察点作为 kata 下轮迭代候选；下一步候选=两份 capability-map ingest 或 wiki-query 回填闭环实测

---

## 2026-07-17 kata wiki 启动与首次 ingest：全链路 live 验证零缺陷，复利效应实证

- **场景**：用户主导、主会话引导完成 kata 完整启动链——wiki-init 向导（域=AI 插件工程验证知识库、6 分类、plugin enum 维度、sync 就绪、git 化）→ 项目绑定（.llm-wiki.yaml + gitignore，实测绑定解析未回落 common）→ 首次 wiki-ingest（源=docs/validation-log.md 8 条记录）
- **现象**：①单源触达 15 页 + 38 对双向交叉引用——复利效应首次实证 ②kata 行为验证零缺陷：orientation guard 未跳过、自定义维度提示如期触发（用户答 cross）、raw 不可变捕获、schema guard 生效（写页代理对 3 处边界提案而非漂移）③验收三连全绿：schema_validate 0 错、三段检索命中排序合理（vendors/codex.md 居首）、图 hub 结构符合预期（plugins/harnessloop.md in/out 各 10）④首轮 schema 演化即发生：用户批准 type 枚举钉住、vendor 8 家全量预列（含 claude 标签作用域消歧）、sources 双形式约定——"SCHEMA 与 wiki 共演化"的设计当天走通 ⑤init 硬规则（wiki 不入源仓）纠正了我们此前"docs 文档 wiki 化"的直觉
- **预期**：kata 核心闭环（init→bind→ingest→search/graph/validate→schema 演化）全部可用
- **插件改动**：无（纯使用验证）；wiki 仓库三 commit：88cdd68（init）/0e4a496（首批 15 页）/7582f8d（schema 演化）
- **复验结果**：✅ 全链路通过
- **遗留**：sync remote 未配（休眠通道，多机需求出现时启用）；wiki-query 回填闭环与 session-ingest 待后续实战；下一步候选源=harnessloop-review-20260716.md（80 条发现）与两份 capability-map

---

## 2026-07-17 kata 首次迭代：版本漂移修复 + 内容审计发现两处协议文本缺口（2.15.3）

- **场景**：能力图谱发现的 kata 仓库版本漂移（根 SKILL.md frontmatter 2.13.0 vs 四处 manifest 2.15.2），用户指示优先修复；kata 首次走三插件迭代回路
- **现象**：①漂移为单点（仅根 SKILL.md frontmatter），但 CHANGELOG 内容审计（2.13.1→2.15.2 逐条判定）发现两处真实协议文本缺口——wiki-spec 的路径穿越防护说明（v2.13.1 安全加固）与 wiki-skill-create 的 --supplement-action 目录（v2.15.1）从未同步进 standalone 协议文本 ②注坏验证：精确复现原始漂移场景（SKILL.md 改回 2.13.0）新 Test 62 必挂并列出四源值 ③主会话验收时复现修复代理预警的既有环境问题（~/.git-ai/bin/git 封装在 fake-HOME 下 exit 126 致 sync 测试假性失败，真实 git 绕行后全绿）——顺带定位了本会话所有 git 操作报 syntax error 的根源 ④发现遗留结构缺口：session-ingest/federate/mcp-server 三技能在 standalone SKILL.md 从无独立章节（早于基线，记入 CHANGELOG 留后续）
- **预期**：版本单一事实源 + 机械防复发
- **插件改动**：kata 57d3e3d（v2.15.3，push 1a120d4..57d3e3d，四仓授权+版本同步条件满足）；Test 62 版本一致性守卫自动纳入 pre-commit 与 CI
- **复验结果**：✅ run_smoke.py 全绿（真实 git 下）、build_skill_md --check、dreaming eval gate precision/recall 1.0；重装 v2.15.3 内容级一致
- **遗留**：三技能 standalone 章节缺口（kata 后续迭代候选）；本机 git-ai 封装脚本自身的 bash 语法错误（用户环境，非本项目范围，建议用户抽空修）

---

## 2026-07-17 kata 引入：第三个被测插件入回路，同名碰撞排障与旧版退役

- **场景**：kata（surebeli/kata v2.15.2，LLM wiki 文档维护插件）按既有模式引入 test-harnessloop（submodule + 本地 marketplace 重指 + 脚手架脚本扩为三插件）——继 harnessloop、hopper-plugin 之后第三个纳入"边用边验证"回路的插件
- **现象**：①CHANGELOG 揭示 kata 即 ak-wiki 的改名后继（v2.0.0 rebrand，原文 "previously ak-wiki"），与本机已装旧版 ak-wiki@ak-llm-wiki v1.8.0 技能全同名碰撞（wiki-init/ingest/search/... 等 13 个同名），会话启动时只加载旧版 ak-wiki:* 前缀技能，新装的 kata:* 技能被压制、不可见 ②用户决策卸载旧版 ak-wiki 插件，reload 后确认 kata:* 前缀 v2.15.2 全部 18 个技能正确加载（含 session-ingest/spec/skill-create/federate/mcp-server 5 个新增技能）③三路并行深读同时发现 kata 的一条休眠外部通道（wiki-sync 依赖的 git remote，当前未配置/未激活）与仓库自身的版本漂移（SKILL.md frontmatter 停在 2.13.0，而 plugin.json/marketplace.json 已是 2.15.2）——后者被列为候选的首个 kata 迭代项 ④能力图谱生成过程中遭遇 API 529（服务端持续过载）连续 5 次重试才完成，累计中断约 40 分钟，期间 Workflow 的 resume 机制与退避重试策略均生效，最终三路读取任务完整拿到结果
- **预期**：kata 应能沿用此前 hopper-plugin 的引入模式顺利接入——submodule 落地、本地 marketplace 重新指向、脚手架脚本从两插件扩为三插件，且会话内 kata:* 技能前缀与仓库文档能力集（18 个 skill）一致，不受本机已装同源旧插件影响
- **插件改动**：无（本轮为纯引入，未触及 kata/ submodule 或 harnessloop/hopper-plugin 任何文件）
- **复验结果**：✅ `plugin-status` 显示 kata 内容级一致（与 submodule commit `1a120d4` / v2.15.2 一致）；卸载旧版 ak-wiki 并 reload 后，kata:* 全部 18 个技能实际调用可见（非仅静态清单），同名碰撞问题解除
- **遗留**：仓库自身版本漂移（SKILL.md frontmatter 2.13.0 vs plugin.json 2.15.2）待修，是候选的首个 kata 迭代项；把项目知识 wiki 化（`docs/validation-log.md`、`docs/*-capability-map.md` 等文档编译进 kata wiki）作为 kata 首个实战使用场景候选，尚待真实执行；`wiki-session-ingest` 涉密会话随 `wiki-sync` 外发的观察点（`--scrub-secrets` 未实现）目前仅为静态读到的风险点，待真实多机同步场景实战验证

---

## 2026-07-17 hopper-plugin 0.31.0 发布：首次授权 push，政策层从纪律升级为机制

- **场景**：hopper 边用边验证进入迭代阶段——用户采纳"effort 预制 + model 选择规则"三层政策方案并授权 push（附版本同步硬条件）；同一发布收拢三个批次：脚手架抽象档位化、--check-model 三档断言器、政策层机械化四项（dispatcher 政策消费/clamp 可见化/verified-latest 哨兵/setup 政策 lint）
- **现象**：①全 vendor probe 实测 8/8 连通，codex bundled 目录含本机旧 CLI 不可用的 5.6 代——"目录收录≠本机可用"成为 --check-model 三档语义的设计依据 ②codex CLI 升级到 0.144.5 后 gpt-5.6-sol/terra/luna 三模型 live 微测全部可用，knownGood 更新（版本门槛注记）③项目 AGENTS.md 政策列迁移为机器语法后 lint 零 unparseable 零警告，迁移中发现两个真实解析陷阱（转义竖线列错位、反引号破坏 OOB 判定）④批次 2 顺带修复 --write frontmatter 记录未解析字面量的真 bug ⑤API 中断两次（会话额度/服务端错误），SendMessage 续跑机制两次成功恢复
- **预期**：政策三层结构（frame 抽象档位 → AGENTS.md 项目政策 → 派发实例落盘）自洽运转
- **插件改动**：hopper-plugin 6fbcf3a（v0.31.0，首次授权 push eceee81..6fbcf3a）；定向单测批次合计 250+ 全绿，全量回归 845/852（7 失败为环境缺 express 的既有 dashboard 测试）
- **复验结果**：✅ 重装 v0.31.0 内容级一致；--setup 政策段在真实项目三态判定正确；--check-model 六案例全对；回落链/clamp/哨兵实跑验证
- **遗留**：评审行 Effort policy 静态 lint 显示 unbound（设计使然——vendor 派发时随机绑定，届时 per-vendor 表生效）；dashboard 测试的 express 环境缺口（上游既有）；README 版本徽章 0.12.0 历史遗留漂移（未在本批范围）

---

## 2026-07-17 hopper 首次实战：T-001 第三方对抗评审全链路走通，抓到 harnessloop 两个真缺陷

- **场景**：hopper 引入后首个真实派发——`.hopper/queue.md` T-001，codex 对 harnessloop submodule commit 6936fbc（setup wizard 完整实现）做只读对抗评审，兼验证 `hopper-plugin/ISSUE-codex-review-hijack.md` 记录的观察点
- **现象**：①首派 400 失败——vendor 默认模型 `gpt-5.6-sol` 超出本机 codex CLI 版本；新观察点：vendor 默认模型不可信，须钉缓存模型名而非依赖 vendor 默认值 ②重派 `--model gpt-5.5`（xhigh）成功，5 分钟（299.8s），结果 REWORK + 3 findings，107,893 tokens ③派发方按 `.hopper/AGENTS.md`「Codex 评审强制核对」三项逐一核对，全部通过：审查对象确为 brief 指定的目标（真实 commit/路径）、产物落在 brief 指定路径、两条 findings 经独立复现成立 ④跨仓劫持（ISSUE-codex-review-hijack 记录的已知问题）本次未复发——EXECUTION MODE 前导有效 ⑤同时坐实该 ISSUE 的另一半已知问题：review 任务在 codex 落地时仍是 `danger-full-access`，实证「不可靠地降级为只读」——只读性目前只能靠 brief 约定，没有机械保证 ⑥`--watch` 两次（首派失败、重派成功）均在终态正确退出，无悬挂
- **预期**：hopper 的 dispatch 生命周期（init-tasks → 预检三连 → dispatch → watch → result → 强制核对）应在真实任务上端到端可用，且暴露的观察点应可沉淀为后续验证清单（依据 `.hopper/AGENTS.md` Codex 评审强制核对条款、`hopper-plugin/ISSUE-codex-review-hijack.md`）
- **插件改动**：hopper 无改动（本轮为纯使用验证，未触及 hopper-plugin/ 任何文件）；harnessloop 因本次 findings 另开修复任务 TH-0009（见对应 evolution issue）
- **复验结果**：✅ 全链路走通——init-tasks → 预检三连 → dispatch → watch → result → 三项强制核对，均按预期完成
- **遗留**：finding 3（validate fixture 自证性问题）记录为已知局限，暂不重构；codex 默认模型不可信问题可考虑上报 hopper 上游，建议增加缓存模型名的 fallback 机制，避免 vendor 端默认值漂移导致派发直接 400

---

## 2026-07-17 setup wizard goal 完结：S4 live 验收通过，首个 dogfooding goal 达成

- **场景**：用户亲自 live 首跑 setup wizard（goal 20260716-001-setup-wizard round 0004，S4 live acceptance）——`/reload-plugins` 热加载插件后直接运行 `$harnessloop-setup`，无需重启会话
- **现象**：wizard 审阅模式正确识别既有五文件完成度 4/5，仅追问缺失类别（External Tools），用户选择记录 GitHub 条目；哨兵写入符合设计（`.harnessloop/setup/data-sources.md` External Tools 表新增 GitHub 行，user-confirmed）；完成度报告全部符合设计预期。另有一项新发现值得记录：`/reload-plugins` 热加载即刻生效，无需重启整个会话——这是比"重启会话"更快的插件生效路径，此前 round 0002 evidence-index.md E4 曾记录"已加载的 SKILL 文本钉在会话启动快照，落后于磁盘"的局限，本次实测 `/reload-plugins` 可绕开该局限，值得在后续 dogfooding 中优先尝试
- **预期**：wizard 五步流程（含审阅模式的"仅问缺口"设计）应在真实项目上端到端可用，而非仅在骨架项目/dry-run 中验证（依据 goal.md Success Condition 与 rounds/0003 round-summary.md Next Proposed Scope）
- **插件改动**：未改动（本条为纯验收记录，round 0003 已完成全部实现交付，round 0004 仅为 S4 live 验收 + 三项 Required Human Decisions 收口，未触及 harnessloop/ submodule 任何文件）
- **复验结果**：✅ 通过。`check_setup.py` 复核本项目返回完成度 5/5、`complete: true`，exit 0；收盘门 `verify_protocol.py` exit 0
- **遗留**：无。goal 20260716-001-setup-wizard 三项 Required Human Decisions（live 首跑、三档预设默认值"保持默认"、"7/7→8/8"阈值表述更新）全部解决，goal 判定 achieved 并归档（见 `.harnessloop/goals/20260716-001-setup-wizard/goal.md` ## Status、`.harnessloop/goals/20260716-001-setup-wizard/rounds/0004/decision.md`）。TH-0008（第三类 Rule B 误报，框架级问题）仍 open，与本 goal 归档无关，留待独立处理

---

## 2026-07-16 P1 setup wizard：harnessloop 首个 dogfooding goal 三轮完成

- **场景**：用 harnessloop 自身协议开发 setup wizard（goal 20260716-001-setup-wizard，rounds 0001-0003：round 0001 design 首次对抗评审 negative → round 0002 design-v2 复审 positive → round 0003 implement 先对抗评审 negative 后 minimal-fix 复核通过）
- **现象**：对抗评审两轮 negative 各拦下真实缺陷——设计轮（round 0001）M1（continue/loop 门语义与"每步可跳过"承诺自相矛盾，实测锁死本项目自身 continue）、M2（cost-context-policy 29 槽位判定算法无小节作用域定义、不可无歧义求值）、M3（lite 档 Evidence contract revision 条款与 harnessloop-evidence SKILL 强制人工确认硬约束冲突）三处必修项，另有 S1-S10 十项建议修复；实现轮（round 0003）M-A（wizard SKILL 引用不存在的 `todo_count` 字段、保留已废弃合并语义）、M-B（表格数据行判定过松、S1 哨兵锚定被任意杂文本旁路，实测证伪）、M-C（新技能家族配套缺口——`agents/openai.yaml` 与三处文档技能清单，scope-lock 规划遗漏）三处必修项，均按 minimal-fix 修复。机械门（verify_protocol.py Rule B）三类实战误报全部处置：TH-0006（正则/glob/裸域名等 6 条误报，已修复）、TH-0007（解析基准缺 `.harnessloop` 根导致 6 条误报，已修复，且是 round 0002 严格审查提前预测方案的逐字应验）、TH-0008（第三类——讨论语境中间目录相对片段误报，仍 open，已提出"项目树后缀匹配回退"增强提案，当前以 `verify:ignore` 手工止血 3 条）。文件契约两次纠正主会话转述漂移：一次是 round 0001 对协议硬约束的核对过程中，manifest "90 槽位"总数以设计文档原文为准较正，未被会话转述带偏；另一次是 round 0002 decision.md 裁决 (a) 纠正的"等核心文件"被主会话简化转述为"任一文件"（round 0001 decision.md:18 原文核实后以文件原文为准）。scope-lock 在 round 0003 内从 v1 扩围至 v2，走的是 control-contract.md 既定的"Scope-lock mutation: main session 自主（版本递增留痕）"授权路径，而非临时越权。另沉淀一条委派模式经验：批准的规格偏离（todo 双字段方案）必须同步广播给全部并行代理——本轮因未同步广播致 3 处接缝失配，主会话集成审查抓 2 处、对抗评审补抓 1 处
- **预期**：协议各机制（评审门/机械门/scope-lock/self-audit/决策留痕）应在真实 goal 中全部被触发且有效，而非仅存在于文档描述（依据 harnessloop/AGENTS.md 与 harnessloop-loop SKILL 协议条款）
- **插件改动**：harnessloop submodule 待提交 0.11.0（新增 `harnessloop-setup` skill + `check_setup.py` + `control-contract-profiles.md`；四个既有 SKILL.md 接线；`validate.py` 新增第 3 阶段共 8 阶段 28 断言；`harnessloop-setup/agents/openai.yaml`；README.md/docs/usage.md/docs/harnessloop-framework.md 三处技能清单更新）
- **复验结果**：✅ `npm run validate` 8/8（含新增断言，合计 28 断言全绿）；`claude plugin validate --strict` 通过；`verify_protocol.py` exit 0（TH-0008 三条 `verify:ignore` 豁免不影响判定）；所有新增 Python 代码在本机 Python 3.9.4（pyenv）实测无异常
- **遗留**：S4 live acceptance 待用户重启会话运行 `$harnessloop-setup` 首跑（round 0004，见 `.harnessloop/goals/20260716-001-setup-wizard/rounds/0004/scope-lock.md`）；TH-0008 增强提案待上游评估假阴性风险后决定是否实现；三档预设（lite/standard/strict）默认值最终措辞与 thresholds.md/setup/data-sources.md 中"7/7→8/8"阈值表述两项 Required Human Decisions 待用户确认

## 2026-07-16 P0 修复批次：审查驱动的四组框架缺陷闭环（Sonnet 执行 / Fable 审查模式首次运行）

- **场景**：docs/harnessloop-review-20260716.md 严格审查（80 条确认发现）后的 P0 修复批次；首次采用「写入任务委派 Sonnet 5 子代理、主会话 Fable 5 只读审查验收」工作模式，三个子代理并行修复
- **现象（修复前）**：①verify_protocol.py 机械门在已安装项目中零触发路径（12 个 SKILL.md 无一运行它）；②round_cost.py 按行累加同一 message 的多行 usage，实测 3.03x 虚高（审查报告区间 2.3–4.1x）；③secrets SKILL 硬编码仓库相对路径在安装后不可达，脚本调用写法三种并存；④channel_params.py 明文 store 0644 非原子写、二次 add 重置元数据、set→add 转换残留明文、audit 对 git 已跟踪 store 全盲
- **预期**：机械门在每轮收盘与 continue 门运行；成本账单按 message 计费一次；所有脚本路径用 <skill-dir>/<plugin-root> 占位符可解析；明文值 0600 原子落盘且绝不进入 git 可见区
- **插件改动**：submodule 三个 commit——0829b03（A 组：verify_protocol 接线 + 路径统一）、c221273（B 组：message.id 分组去重 + marker v2 跨窗口 pending 携带 + validate 阶段 6 回归断言）、66093fd（C 组：channel_params 加固 + channel-params.json.* 通配 ignore）
- **审查交互**：主会话审查共退回三轮补修——A 组 2 处同主题路径残留 + evolution issue 的 Created by 元数据不实（写成 fable-5，实为 sonnet-5 执行）；B 组 1 处注释与行为不符（stale pending 实为携带而非丢弃）；C 组 3 处新引入的泄露面（临时文件/损坏备份/.bak 均不被 gitignore 模式覆盖、备份继承 0644 权限）。三个代理均一次性完成补修
- **复验结果**：✅ 通过。`npm run validate` 7/7 全绿（含 B 组 6 条新增去重断言，修复前必挂）；plugin-reinstall.sh 重装后缓存与 submodule 工作区内容级一致（sha 66093fd）；B 组用本机真实 transcript 独立复算与修复后输出精确一致
- **遗留**：channel_params 并发写为 last-writer-wins（无文件锁，超出本批范围）；round_cost 尾部开放 message 延迟计费为有意取舍；validate 阶段 3 尚无 C 组五项新行为的固定 fixture；对应 evolution issue：TH-0002~TH-0005（.harnessloop/meta/evolution-issues/0002-0005）

## 2026-07-16 init 首触即崩：init_project.py 不兼容 Python 3.9

- **场景**：首次执行 `harnessloop:harnessloop-init` skill，按其 Preferred Setup 调用插件缓存内的 `init_project.py --project <本项目>`
- **现象**：`TypeError: write_text() got an unexpected keyword argument 'newline'`（init_project.py:76），退出码 1；7 个目录已建、0 个文件写入，项目半初始化。本机 python3 = 3.9.4（pyenv）
- **预期**：init 一次成功，产出 7 目录 + 12 文件骨架（依据 harnessloop-init SKILL.md Output Contract 与 init_project.py 设计）
- **插件改动**：init_project.py:76 改用 `path.open("w", encoding="utf-8", newline="\n")` 写入（`Path.write_text(newline=)` 是 3.10+ API，`open(newline=)` 全版本可用且语义等价）；submodule 内 commit 见 git log
- **复验结果**：✅ 通过。harnessloop 自身 `npm run validate` 7/7（其中第 2 关 init 冒烟正是用本机 3.9.4 执行，修复前必挂）；`scripts/plugin-reinstall.sh` 重装后重跑 initializer，12 个文件全部写入、幂等补齐半初始化状态、退出 0
- **遗留**：上游未声明最低 Python 版本（作者对抗性审查中的已知问题 n9），本例实际把隐性门槛抬到了 3.10；已记 evolution issue `.harnessloop/meta/evolution-issues/0001-init-project-py39-write-text-crash.md`，submodule 修复待 push 上游
