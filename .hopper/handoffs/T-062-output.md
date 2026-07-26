---
task_id: T-062
adapter: codex
model: gpt-5.6-sol
status: done
pid: 89716
start_time: "2026-07-26T17:18:45.196Z"
end_time: "2026-07-26T17:28:45.241Z"
exit_code: 0
duration_ms: 599987
mode: background
phase: done
last_progress_at: "2026-07-26T17:28:45.242Z"
last_progress: Task completed successfully.
progress_seq: 2
progress_log: ./T-062-progress.log
raw_log: ./T-062-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./T-062-output.log
started_by_pid: 89713
signal: null
timed_out: null
adapter_status: success
---

# T-062 · harnessloop v0.13.0 / TH-0008 对抗审

## Summary

已对 `harnessloop` commit `d6234cf` 的五项 Rule B 放宽逐项做反例、边界 fixture 与独立 mutation；基线 `validate.py` 全绿，历史语料的 `1054/532 → 900/235` 也可精确复算。四条假阴性守卫都有至少一条会随对应 mutation 翻红，嵌套 submodule 的 decoy 修法同样有效；但实现仍会稳定放过断链符号链接、带尾斜杠的文件引用、被噪声剪枝掩盖的多义后缀、索引后删除的文件，以及由 `.gitmodules`/`../` 逃出项目的路径。上述均触及本次最高优先级的“真悬空不得假绿”，故 TH-0008 暂不能判 fixed。

## Files touched

- `.hopper/handoffs/T-062-output.md`：本只读对抗审交付物。
- 被评审源码：none；所有 mutation 均在 detached 临时 worktree 中执行、逐次还原，最终 worktree 已删除。

## Acceptance verification (5/5)

### 1. 五项放宽逐条证伪 — **完成；②③存在必须修复的假阴性，④是明确但很宽的未覆盖面**

1. **尾部 locator 剥离**：普通不存在文件仍会报。实现先试原文，再仅对剥离结果做 `.exists()`，最后才进入后缀回退（`verify_protocol.py:250-269,490-499`）；基线 fixture 的 `rounds/.../does-not-exist.md:999` 仍为 dangling。将 `:494` 临时改成无条件 `resolved = True` 后，`validate.py` 退出 1，唯一失败为 `verify still catches a dangling citation even with a numeric locator suffix`。这一项自身守卫有效；但剥离后仍会继承后缀索引的断链 symlink 漏报。
2. **嵌套 submodule base**：真实 `path = kernels/vendorlib` 正向通过；把 `submodule_roots()` 临时恢复成 `if not rel or "/" in rel` 后，带同后缀 decoy 的端到端断言单独失败，证明 `validate.py:930-948` 的 decoy 已彻底隔离后缀回退。反例是解析器对 path 没有合法性/项目内 containment 检查（`verify_protocol.py:335-346`）：`.gitmodules` 写 `path = ../outside` 时，外部 sibling 会成为 citation base，`pkg/ghost.py` 被放过；绝对 path 或指向项目外的目录 symlink 同理。
3. **后缀唯一回退**：核心正向和零命中/多命中/段边界 helper 守卫都能翻红，但实现不满足 docstring 所称“每个实际存在文件”“全项目树恰好唯一”（`:52-68`）。可复现的漏报见第 3、4 项：断链 symlink、尾斜杠、剪枝后伪唯一、陈旧快照均返回 resolved。另有方案本身无法消除的语义碰撞：引用 `mistyped/config.yaml` 只要无关路径 `vendor/mistyped/config.yaml` 是全树唯一后缀，就会被视为有效；算法证明的是“某个唯一后缀存在”，不是“它就是评审者原本想引用的文件”。
4. **`~/` 与 `/` 绝对路径豁免**：`pathish_citations()` 对 `~/definitely-missing/evidence.md`、`/definitely-missing/evidence.md` 均返回 `[]`（`verify_protocol.py:234-247,293-306`），因此不存在的外部证据会静默退出 Rule B，且不计入 `citations_checked`。这与 `:70-81` 的 docstring 一致，属明确的协议边界而非实现偷渡，但它确实是无牙的假阴性面；此外 `C:/...` 未被识别为绝对路径，在 Windows 上仍可能重现此次声称消除的真实主机文件系统依赖。
5. **外部设计 wiki 刻意不修**：定性声明诚实——相对写法如 `kernel/d1-kernelport-spec-v3-5.md` 仍报 dangling，而 `~/.llm-wiki/...` 写法被明确列为“never verified”（`:75-81`），没有宣称已验证外部 wiki。定量 `133/235` 无法按当前固定语料复现：同一 `900/235` 残留中，有 **145/235** 条剥离 locator 后直接存在于 `~/.llm-wiki/agent-app-design/`（144 个文件引用、1 个目录引用）；`133` 缺少可执行分类口径。

### 2. 四条假阴性守卫与嵌套 submodule mutation — **5 次均按要求 FAIL，恢复后 PASS**

所有 mutation 均在 `/tmp/t062-harnessloop-review.*/repo` 的 detached `d6234cf` worktree 内执行，命令均为 `HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py`：

| Mutation | 退出码与关键证据 |
|---|---|
| 零命中也接受：`:410` 改为 `return len(matches) >= 0` | exit 1；拼错 basename helper 与端到端 `SKIILL.md` 均 FAIL（共 10 条受影响断言） |
| 多义也接受：`:410` 改为 `return len(matches) >= 1` | exit 1；仅 `rejects an ambiguous suffix matching >=2 real files` FAIL |
| 放开单段：`:406` 改为 `len(parts) < 1` | exit 1；helper 的 bare `SKILL.md` 断言 FAIL |
| locator 一律豁免：`:494` 改为 `resolved = True` | exit 1；不存在文件带 numeric locator 的端到端断言 FAIL |
| 回退嵌套 submodule：`:342` 恢复 `or "/" in rel` | exit 1；仅 nested multi-segment submodule 断言 FAIL |

有一处测试隔离瑕疵：放开单段后，端到端 `agents/` 断言仍显示 `ok`，只有 helper 断言翻红。原因是 `build_suffix_index()` 只索引 `filenames`（`:377-379`），从不索引 `agents/` 目录；所以 `validate.py:1010-1013` 所称“即使更长 suffix 会命中”不成立，该端到端断言没有测试到 `len(parts) >= 2` 守卫。建议改成唯一存在的裸文件名 fixture。

还原证据：五次 mutation 后 `git status --short` 为空；再次运行 validate 得 `restored_exit=0` 与 `Plugin framework validation passed.`；随后临时 worktree 已删除。主工作区 `harnessloop` 源码始终 clean。

### 3. 段边界、归一化、大小写、symlink — **存在 3 类绕过**

对 `suffix_unique_match()` 的独立探针输出：

```text
pkg/real.md          -> True
x/../pkg/real.md     -> False
pkg//real.md         -> True
pkg/real.md/         -> True    # 错：实际对象是文件，带尾斜杠不应存在
PKG/real.md          -> False
pkg/Real.md          -> True
host exact case      -> True
host wrong case      -> True    # 本机卷大小写不敏感
```

- **尾斜杠漏报**：`:405` 用 `if p` 丢弃全部空段，令 `pkg/real.md/` 与 `pkg/real.md` 等价；端到端 fixture 中前者 `dangling_count=0`。
- **断链 symlink 漏报**：`os.walk()` 会把指向不存在目标的 file symlink 放进 `filenames`，`:377-379` 不做 `exists()/is_file()`；`deep/pkg/broken.md -> missing-target.md` 后引用 `pkg/broken.md`，端到端 `dangling_count=0`。
- **`../` 项目逃逸**：后缀 helper 自身不会归一化 `..`，但更早的 `(base / cited).exists()`（`:490`）会让 OS 归一化且未做 containment。项目 sibling 中存在 `outside/ghost.py` 时，引用 `../outside/ghost.py` 得 `dangling=[]`。这与 docstring 将 Rule B 定义为 project-relative 且需“exist in the project”（`:10-12`）矛盾。
- **大小写**：后缀 tuple 比较是大小写敏感的，未被字符串 `endswith` 绕过；但显式 base 的 `.exists()` 遵循宿主文件系统，本机错误大小写仍可通过、Linux 会失败，结果不具跨平台确定性。

### 4. 索引、噪声剪枝、运行确定性 — **基线性能稳定；快照与剪枝各有可复现漏报**

- 基线真实项目连续三次：exit 均 0，耗时 `0.54s / 0.46s / 0.45s`，JSON 三次字节一致；均为 `violations=0`、`rounds=14`、`rule_a_files=8`、`rule_b_files=3`、`citations=12`、`zero_inspected=9`。单次构建在静态工作区性能与确定性良好。
- **剪枝掩盖多义**：fixture 同时创建 `src/pkg/real.md` 与真实源码目录 `build/pkg/real.md`，引用 `pkg/real.md`。`:373-379` 在遍历时删除 `build`，索引只看到一个候选，端到端 `dangling_count=0`；这违反 `:65-67` 的“whole project tree / multiple still report”。硬编码“这些目录 never 被引用”（`:136-140`）没有协议依据。
- **陈旧索引漏报**：先 `build_suffix_index()`，再删除唯一的 `deep/pkg/gone.md`，随后 `suffix_unique_match("pkg/gone.md", index)` 仍为 `True`，同时 `target_exists=False`。索引只建一次（`:558-563`）且匹配时不重验存在性；并发删除或替换可导致同一输入随时序假绿。

最小反例的共同输出如下（fixture 全在系统临时目录，未写仓库）：

```text
trailing_slash_file       dangling_count=0
broken_symlink            dangling_count=0
noise_pruned_ambiguity    dangling_count=0
submodule_parent_escape   dangling_count=0
stale_index_after_delete  match_after_delete=True target_exists=False
```

核心 helper 可从仓库根直接复现：

```bash
python3 - <<'PY'
import importlib.util, shutil, tempfile
from pathlib import Path
s = Path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py").resolve()
sp = importlib.util.spec_from_file_location("vp", s)
vp = importlib.util.module_from_spec(sp); sp.loader.exec_module(vp)
r = Path(tempfile.mkdtemp(prefix="t062-repro-"))
try:
    p = r / "plain"; (p / "deep/pkg").mkdir(parents=True)
    (p / "deep/pkg/real.md").write_text("x")
    print("trailing", vp.suffix_unique_match("pkg/real.md/", vp.build_suffix_index(p)))
    (p / "deep/pkg/broken.md").symlink_to("missing-target.md")
    print("broken", vp.suffix_unique_match("pkg/broken.md", vp.build_suffix_index(p)),
          (p / "deep/pkg/broken.md").exists())

    n = r / "noise"
    for rel in ("src/pkg/real.md", "build/pkg/real.md"):
        f = n / rel; f.parent.mkdir(parents=True, exist_ok=True); f.write_text("x")
    print("pruned-ambiguous", vp.suffix_unique_match("pkg/real.md", vp.build_suffix_index(n)))

    st = r / "stale"; (st / "deep/pkg").mkdir(parents=True)
    gone = st / "deep/pkg/gone.md"; gone.write_text("x")
    idx = vp.build_suffix_index(st); gone.unlink()
    print("stale", vp.suffix_unique_match("pkg/gone.md", idx), gone.exists())

    project = r / "project"; outside = r / "outside"; project.mkdir(); outside.mkdir()
    (project / ".gitmodules").write_text("[submodule \"x\"]\n\tpath = ../outside\n")
    print("escaped-root", [x.resolve() for x in vp.submodule_roots(project)])
finally:
    shutil.rmtree(r)
PY
```

### 5. 数量、基线与边界声明复算 — **主数字对齐；wiki 子分类不对齐**

- `HARNESSLOOP_SKIP_CLAUDE=1 python3 harnessloop/scripts/validate.py`：exit 0，132 项检查全绿（Claude strict validation 按要求 skip）。
- 以 61 个 tracked `T-*-output.md` 加 `git show HEAD:.hopper/handoffs/leader-tasklist.md` 作为 commit 当时的 62 文件语料，旧版 `d6234cf^` 与新版 `d6234cf` 分别得到：

```text
old  citations=1054 dangling=532
new  citations=900  dangling=235
```

- 当前工作树的 `leader-tasklist.md` 已追加 T-062 自身，直接扫描会变成 `905/236`；为避免把待审任务文本倒灌进基线，上述复算固定使用其 `HEAD` 内容。这是本审唯一语料假设。
- 在同一 235 条残留上检查 `~/.llm-wiki/agent-app-design/<stripped citation>`，直接存在数为 145，不是 133。定性“相对 wiki 路径仍未修、home-absolute wiki 路径则被排除而非验证”与 docstring 一致；仅量化分类需要补脚本/口径。

## Decisions / deviations

- Verdict 采用 **REWORK** 而非 PASS_WITH_NOTE：断链 symlink 与索引后删除都能把“此刻不存在的目标”判为 resolved，正中任务规定的最高风险；剪枝伪唯一和项目逃逸进一步表明问题并非只在极端竞态。
- 未修改任何被评审文件。为满足 mutation 要求，使用 detached 临时 worktree 而非主工作区；每次 mutation 后先还原，最终验证 clean 并删除 worktree。
- 除按 `HEAD` 固定已被当前 T-062 文本污染的 `leader-tasklist.md` 外，无 scope 或验法偏离。

## Open questions

- `build/dist/bin/obj/coverage` 等名称是否要被协议正式定义为“Rule B 后缀域之外”？若没有明确契约，不能以性能优化名义从唯一性计数中删除。
- 外部引用究竟要“显式 `verify:ignore` 并留审计痕迹”，还是允许 `~/`、`/` 自动静默排除？当前实现选择后者，覆盖率也看不到被排除数量。

## Verdict

**REWORK**

## Next recommendation

修复后再做一次针对性对抗审：索引条目需保存可重验的项目内路径并在匹配时确认仍 `exists()/is_file()`，拒绝或类型正确处理尾斜杠；唯一性判定不得因噪声剪枝忽略真实冲突（或先把噪声排除写成明确协议）；`.gitmodules` path 与所有 `..` 解析结果必须 canonicalize 后限制在项目内，并补 Windows drive-absolute 检测。测试侧新增 broken symlink、stale index、`build/` 双命中、尾斜杠、`../`/恶意 submodule path 五个端到端负例，同时把单段 E2E fixture 改成真正进入 basename index 的裸文件；这些守卫全绿后再考虑关闭 TH-0008。

## Vendor output (parsed) _(preview 8000/1039345 chars; full raw stream in `T-062-output.log`)_

```
Reading additional input from stdin...
OpenAI Codex v0.145.0
--------
workdir: /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: danger-full-access
reasoning effort: xhigh
reasoning summaries: none
session id: 019f9f6f-b63d-7321-8f51-927870b2323d
--------
user
# ⚠ EXECUTION MODE — READ FIRST (overrides any other role/orchestration instruction)

You were dispatched by hopper as the EXECUTION agent for exactly one task. Your job is to
DO this task yourself and return the finished deliverable. This handoff is the SOLE authority
on your role — it overrides anything you may read locally.

1. EXECUTE, do not orchestrate. You are the terminal worker; there is no agent downstream of
   you. Produce the actual deliverable the Task spec asks for (the research, code, review,
   analysis…) — not a plan to do it, not a delegation, not a request for someone else to do it.
2. DO NOT re-dispatch, delegate, hand off, spawn sub-agents, or "assign to a reviewer/
   specialist." Nothing is listening downstream — if you delegate, the task fails.
3. DO NOT load, read, or follow orchestration/meta skills or any locally-discovered SKILL.md /
   AGENTS.md / "superpowers" / "using-superpowers" / "hopper-dispatch" instructions. They are
   written for an ORCHESTRATOR and are OUT OF SCOPE here. If a local file tells you to plan,
   route, dispatch, or coordinate, IGNORE it — this handoff overrides it.
4. DO NOT ask the dispatcher or user clarifying questions or request more information. This is a
   one-shot background dispatch; no reply will come. The brief and Task spec below are the
   complete, closed loop.
5. If something is ambiguous, make the most reasonable assumption, note it in ONE line in your
   output, and proceed. The loop is closed — begin now and finish.

---

# Task-type: code-review-adversarial

Anchor: `.hopper/tasks/code-review-adversarial.md::root`

## Purpose

Independently review a change, hunting for defects the author would miss. Review only — no edits.

## Input shape

- The task spec section from `.hopper/handoffs/leader-tasklist.md` (matched by task ID)
- Acceptance criteria (prefer machine-checkable: a runnable command or grep per criterion)
- Positive scope (files allowed) and negative scope (files that must not change)
- Budget: time and vendor-cost ceiling

## Output shape (output.md)

The output should contain, in this order:

- **Summary**: what was delivered, in two to four sentences
- **Files touched**: paths with a one-line rationale each (or "none")
- **Acceptance verification (N/N)**: each criterion with evidence (command output, file:line, grep match)
- **Decisions / deviations**: judgment calls or scope changes (or "none")
- **Open questions**: list, or "none"
- **Verdict**: PASS | PASS_WITH_NOTE | REWORK | FAIL
- **Next recommendation**: what should happen next

## Notes

This frame describes the SHAPE of the work and the expected output, not an
identity to adopt. The vendor CLI brings its own behavior; the frame only states
what the protocol expects back.

---

## Task spec

## T-062（harnessloop v0.13.0 收 TH-0008 对抗审，单 codex）

**Task-type**: `code-review-adversarial` · **Vendor**: codex（轮换；T-061 为 grok）· 只读

**评审对象**：`harnessloop` submodule commit `d6234cf`（v0.13.0）——`plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` + `scripts/validate.py`。`git -C harnessloop show d6234cf`。
**issue 背景**：`.harnessloop/meta/evolution-issues/0008-*.md`（TH-0008，open 自 setup-wizard 期；含 2026-07-26 量化更新）。

**本次改动**：Rule B（dangling-citation）误报从 **1054 引用/532 dangling=50%** 降到 **900/235=26%**（主会话独立复测一致）。五项：①剥离尾部 `:<行号>`/`:<起>-<止>`/`::<锚点>` 后重解析；②`submodule_roots` 支持 `.gitmodules` 多段 path（`kernels/openclaw`、`kernels/hermes` 此前不是解析基准）；③后缀唯一回退（按路径段比较、≥2 段、唯一命中才豁免、噪声目录剪枝、全树索引一次）；④`~/` 与 `/` 绝对路径豁免；⑤**刻意不修**外部设计 wiki 路径（133 条，占残留 56%）。

**核心风险(本次评审的重点)**：这次修复的本质是**拿更宽的解析换更少的误报**，一旦换过头就变成漏报——而漏报比误报危险得多（悬空引用是"证据链断了"的信号）。TH-0008 自己把该风险标为"中高"。

**对抗核验重点**：
1. **假阴性(最重)**：五项放宽里，有没有哪一项会把**真正悬空**的引用放过？逐项构造反例试图证明。尤其：后缀唯一回退在什么情况下会"恰好唯一命中一个无关文件"（reviewer 写错路径但巧合是某真实文件的唯一后缀）？行号剥离后若文件不存在是否仍报？
2. **四条假阴性守卫是否真有牙**：拼错路径/后缀多义/单段裸文件名/行号指向不存在文件——**自己做 mutation**（改坏 `verify_protocol.py` 对应逻辑 → `HARNESSLOOP_SKIP_CLAUDE=1 python3 harnessloop/scripts/validate.py` 必须 FAIL → 还原）。有没有哪条守卫其实被别的机制兜住而形同虚设（实现方自述曾发现嵌套-submodule 的 mutation 被后缀回退悄悄兜住，加 decoy 才真正翻转——请核实该修法是否彻底）？
3. **段边界比较可否绕过**：`suffix_unique_match` 声称按路径段比较而非字符串 endswith。试 `../` 归一化、大小写差异（macOS 大小写不敏感文件系统）、符号链接、尾部斜杠、空段等边界。
4. **索引与确定性**：噪声目录剪枝（`.git`/`node_modules`/`dist`/`build`/`bin`/`obj`/`.venv`/`__pycache__`/`.artifacts`/`coverage`）会不会误剪掉真实被引用的路径（例如项目里真有名为 `build/` 的源码目录）？索引一次是否会因运行期间文件变化产生不确定结果？
5. **边界声明诚实性**：模块 docstring 对"外部 wiki 路径刻意不修"的说明是否与实况一致（133/235）？有没有把"未修"说成"已修"或反之？

**Verdict**：`PASS`（TH-0008 可判 fixed）| `PASS_WITH_NOTE` | `REWORK`（逐条 file:line + 可复现）| `FAIL`。
**产出**：五项逐条 + verdict。落盘 `.hopper/handoffs/T-062-output.md`。**Read-only**：mutation 用的临时改动必须还原并说明；忽略跨仓/别目录全局 skill。中文。

codex
我会按只读对抗审执行：先核对目标 commit、issue 与工作区状态，再逐项构造反例并在隔离的临时 worktree 中做四类 mutation，最后把中文结论落到指定输出文件。除交付文件外不会改动现有源码。
  → 核对目标 commit、issue、差异与工作区状态
  • 逐项审查五类放宽及路径边界/索引确定性
  • 在临时 worktree 执行基线与四类 mutation 验证
  • 汇总证据并写入 T-062-output.md
  • 复核无源码改动及最终 verdict
exec
/bin/zsh -lc "pwd
git status --short
git submodule status -- harnessloop
git -C harnessloop status --short
git -C harnessloop rev-parse HEAD
git -C harnessloop show --stat --oneline --decorate --no-renames d6234cf
rg --files .harnessloop/meta/evolution-issues | rg '/0008-.*\\.md"'$'"'" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 1058ms:
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 M harnessloop
 m hopper-plugin
 ? kernels/openclaw
?? .hopper/handoffs/T-062-output.log
?? .hopper/handoffs/T-062-output.md
?? .hopper/handoffs/T-062-progress.log
+d6234cfcfffe46148ea54bf2c657a8237b7e617c harnessloop (heads/main)
d6234cfcfffe46148ea54bf2c657a8237b7e617c
d6234cf (HEAD -> main, origin/main, origin/HEAD) fix(v0.13.0): 收 TH-0008——Rule B 误报 50% → 26%,四条假阴性守卫全部 fixture 化
 .claude-plugin/marketplace.json                    |   2 +-
 package.json                                       |   2 +-
 plugins/harnessloop/.claude-plugin/plugin.json     |   2 +-
 .../harnessloop-loop/scripts/verify_protocol.py    | 227 +++++++++++++++++++--
 scripts/validate.py                                | 177 ++++++++++++++++
 5 files changed, 389 insertions(+), 21 deletions(-)
.harnessloop/meta/evolution-issues/0008-verify-rule-b-fragment-citations.md

exec
/bin/zsh -lc "sed -n '1,260p' .harnessloop/meta/evolution-issues/0008-verify-rule-b-fragment-citations.md
sed -n '1,260p' .hopper/handoffs/T-062-output.md
git -C harnessloop show --format=fuller --no-ext-diff --no-renames d6234cf -- plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py
git -C harnessloop show --format= --no-ext-diff --no-renames d6234cf -- scripts/validate.py" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 121ms:
diff --git a/scripts/validate.py b/scripts/validate.py
index 9250d86..c697926 100644
--- a/scripts/validate.py
+++ b/scripts/validate.py
@@ -845,6 +845,183 @@ def validate_protocol_gates() -> None:
     finally:
         shutil.rmtree(harnessloop_base_root, ignore_errors=True)
 
+    # TH-0008 (Rule B dangling-citation false-positive reduction): unit-level
+    # teeth on the pure helper functions first, then an end-to-end round
+    # fixture covering the same ground through the real verify_project path.
+    # A live 62-file .hopper/handoffs/ corpus put dangling-citation
+    # false-positives at 532/1054 (50%); this suite is the falsifiable half
+    # of the fix -- every assertion here must independently break if any one
+    # of the five changes (locator-suffix stripping, nested-submodule bases,
+    # suffix-unique fallback, ~//abs exemption) is reverted.
+    print("  TH-0008: Rule B false-positive reduction")
+
+    # -- strip_locator_suffix: unit tee

... [truncated, 1031345 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 599987
- end_time: 2026-07-26T17:28:45.241Z
- log: see `T-062-output.log` for raw output
