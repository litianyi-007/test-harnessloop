---
phase: done
last_progress_at: "2026-07-26T18:16:29.124Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-26T18:16:29.123Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 380038
adapter_status: success
---
# T-064 · harnessloop v0.15.0 / T-063 MUST-FIX 确认审

## Summary

`1153b7f` 对 T-063 两个原始反例的字面复现均已闭合：untracked 冲突在 `git add` 前后都保持 dangling，普通 symlink 出界的直接 base、`.gitmodules` base、suffix hit 三路也都由假绿转为 dangling。真实 recursive-init 的二层 submodule untracked 覆盖完整，macOS `/tmp -> /private/tmp`、多级 symlink 和“经项目外中转但最终落回项目内”的正反例也符合预期。

但不能确认 TH-0008 fixed：gitignored 的真实冲突仍制造与 T-063 同形、且会被 `git add -f` 翻转的伪唯一；canonical containment 在 `symlink/..` 组合上因先 `normpath` 后 `resolve` 而把真实项目外路径改写为项目内同名路径，直接 base 与 `.gitmodules` base 均可端到端假绿。此外，`--cached` 把已从工作树删除的 tracked 项仍计入“真实存在”宇宙，制造新的假阳性并使索引 docstring 不实。

## Files touched

- `.hopper/handoffs/T-064-output.md`：本只读确认审交付物。
- 被评审的 `harnessloop` 源码：none；所有 Git/submodule/symlink fixture 均建于 `/tmp` 并已删除，结束时 `git -C harnessloop status --short` 无输出。

## Acceptance verification (4/4)

### 1. 两条 T-063 MUST-FIX 原始反例 — **字面反例均闭合**

从 `git show 1153b7f^:plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` 加载 v0.14.0，从 `git show 1153b7f:...` 加载 v0.15.0，原样复跑 `.hopper/handoffs/T-063-output.md` 第 2、3 节 fixture，结果：

```text
untracked_pseudo_unique:
  before git add scratch:
    v0.14 dangling=[]
    v0.15 dangling=["pkg/real.md"]
    v0.15 suffix hits=["src/pkg/real.md","scratch/pkg/real.md"]
  after git add scratch:
    v0.14 dangling=["pkg/real.md"]
    v0.15 dangling=["pkg/real.md"]

symlink_containment_escape:
  v0.14 helpers:
    direct_candidate_accepted=true
    submodule_roots=[".../project/link"]
    suffix_unique_match=true
    end_to_end_dangling=[]
  v0.15 helpers:
    direct_candidate_accepted=false
    submodule_roots=[]
    suffix_unique_match=false
    end_to_end_dangling=[
      "link/pkg/ghost.py",
      "pkg/ghost.py",
      "pkg/external.md"
    ]
  mutation targets:
    .../outside/pkg/ghost.py
    .../outside/pkg/ghost.py
```

对应实现调用点为 `verify_protocol.py:527`（`.gitmodules`）、`:765-768`（suffix hit）、`:792-795`（直接/任意 base）。新增官方守卫位于 `scripts/validate.py:1286-1539`，且基线全绿：

```text
$ HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py
...
ok: verify reports `pkg/real.md` as dangling ... untracked_pseudo_unique
ok: _resolve_in_project rejects ... direct base
ok: submodule_roots rejects ... .gitmodules base
ok: suffix_unique_match rejects ... suffix fallback
Plugin framework validation passed.
```

因此，“T-063 原始两个最小反例是否由修前假绿变为修后报错”这一窄问题答案是 **是**。

### 2. 新唯一性宇宙 — **普通 untracked 与二层 submodule 正确；仍有 ignored 伪唯一和 stale-tracked 假阳性**

实现确实使用三路 NUL 查询：tracked 为 `git ls-files -z --cached --recurse-submodules`（`verify_protocol.py:589-600`），顶层 untracked 为 `git ls-files -z --others --exclude-standard`（`:602-611`），已 checkout submodule 的 untracked 为 `git submodule foreach --recursive`（`:613-632`），最后按完整相对路径去重（`:634-648`）。

真实 `outer -> modules/middle -> deps/leaf` fixture 执行 `git -c protocol.file.allow=always submodule update --init --recursive` 后：

```text
recursive_init_rc=0
foreach:
  modules/middle|modules/middle
  deps/leaf|modules/middle/deps/leaf
tracked pkg/tracked.md:
  modules/middle/deps/leaf/deep/pkg/tracked.md
  modules/middle/mid/pkg/tracked.md
  top/pkg/tracked.md
untracked:
  modules/middle/fresh/pkg/middle.md
  modules/middle/deps/leaf/fresh/pkg/leaf.md
newline filename:
  "modules/middle/deps/leaf/fresh/pkg/line\nbreak.md"
ignored.md hits=[]
```

所以 recursive-init 后的嵌套 tracked/untracked 覆盖完整，NUL 边界也通过换行文件名实测；先前未 init 时 leaf 文件本身不在 worktree，不能算漏索引。

非 Git 回退也仍与文档一致：

```text
_git_tracked_index(non_git_project) = None
src/pkg/real.md exists
build/pkg/real.md exists
indexed hits=["src/pkg/real.md"]
suffix_unique_match("pkg/real.md")=true
```

即 `os.walk` 在 `verify_protocol.py:681-689` 继续剪掉 `NOISE_DIR_NAMES`；module docstring `:128-130` 和 `build_suffix_index` docstring `:662-675` 如实登记了这个旧盲点。

#### MUST-FIX A：gitignored 真实冲突仍是同形伪唯一

`--exclude-standard` 在 `verify_protocol.py:603-605` 明确排除 ignored 文件。构造 tracked `src/pkg/real.md`、真实且 ignored 的 `scratch/pkg/real.md` 与引用 `pkg/real.md`：

```text
git check-ignore scratch/pkg/real.md -> rc 0
before git add -f:
  suffix hits=["src/pkg/real.md"]
  dangling=[]
after git add -f scratch/pkg/real.md:
  suffix hits=["scratch/pkg/real.md","src/pkg/real.md"]
  dangling=["pkg/real.md"]
```

复现步骤：

```bash
T064_REPRO="$(mktemp -d /tmp/t064-ignore.XXXXXX)"
git -C "$T064_REPRO" init -q
mkdir -p "$T064_REPRO/src/pkg" "$T064_REPRO/scratch/pkg"
printf 'scratch/\n' >"$T064_REPRO/.gitignore"
printf tracked >"$T064_REPRO/src/pkg/real.md"
printf ignored >"$T064_REPRO/scratch/pkg/real.md"
git -C "$T064_REPRO" add .gitignore src/pkg/real.md
T064_REPRO="$T064_REPRO" python3 - <<'PY'
import importlib.util, os
from pathlib import Path
s = Path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py")
sp = importlib.util.spec_from_file_location("vp", s)
vp = importlib.util.module_from_spec(sp); sp.loader.exec_module(vp)
p = Path(os.environ["T064_REPRO"])
for label in ("before-force-add", "after-force-add"):
    idx = vp.build_suffix_index(p)
    hits = ["/".join(x) for x in idx.get("real.md", []) if x[-2:] == ("pkg", "real.md")]
    print(label, hits, vp.suffix_unique_match("pkg/real.md", idx, p))
    if label == "before-force-add":
        import subprocess
        subprocess.run(["git", "-C", str(p), "add", "-f", "scratch/pkg/real.md"], check=True)
PY
```

实测为 `before-force-add [...] True`、`after-force-add [...] False`。同一文件系统事实仅因 index 状态翻转，正是 T-063 判为 MUST-FIX 的核心性质；把边界从 “untracked” 平移到 “ignored” 并未消除该假阴性。module docstring `verify_protocol.py:120-122` 诚实披露 ignored 文件不可见，但披露不等于闭合。

#### MUST-FIX B：已删除 tracked 项不属于“真实存在”宇宙，却仍参与唯一性

`git ls-files --cached`（`verify_protocol.py:590-600`）会列出工作树中已删除但尚未从 index 删除的 tracked 文件。实现只在“索引恰好唯一”后复验该路径（`:761-768`）；一旦一个不存在项与一个真实项同后缀，`:763-764` 会先以 `len(matches) != 1` 返回，根本没有过滤不存在项：

```text
src/pkg/real.md exists=true
gone/pkg/real.md exists=false
git ls-files --deleted=["gone/pkg/real.md"]
index hits=["gone/pkg/real.md","src/pkg/real.md"]
suffix_unique_match=false
end_to_end dangling=["pkg/real.md"]
```

这不是假阴性，而是 TH-0008 所要减少的假阳性；也直接反驳 module docstring `:103-112` 和 `_git_tracked_index` docstring `:546-567` 的 “every file that genuinely exists in the worktree”。

### 3. canonical containment — **普通组合正确；`symlink/..` 可绕**

先验证要求中的正常组合：

```text
multi-level escape:
  project/hop1 -> project/hop2 -> outside
  hop1/pkg/out.md resolves outside
  _resolve_in_project(...) = None

outside intermediary, final target inside:
  project/reenter -> outside/return -> project/inside
  reenter/pkg/in.md resolves inside
  _resolve_in_project(...) accepted
  .gitmodules roots=["reenter"]  # escaping hop1 was dropped

project root under symlink:
  project argument=/tmp/.../project-alias
  project.resolve()=/private/tmp/.../project-real
  _is_contained(alias/pkg/x.md, alias)=true
  _resolve_in_project(...)=accepted
```

原始三路无 `..` escape 也确实分别在 `verify_protocol.py:527`、`:766`、`:793` 调用 `_is_contained`，并分别返回拒绝；suffix 路径对项目外 file symlink 保持安全。

#### MUST-FIX C：先词法折叠、后 canonicalize 改变了 symlink/`..` 的真实路径语义

`_is_contained` 本身在 `verify_protocol.py:277-309` 正确对两侧 `resolve(strict=False)`；但 `_resolve_in_project` 在把 candidate 交给它之前，先于 `:792` 执行 `os.path.normpath(base / cited)`。`normpath` 会把 `link/..` 纯词法消掉，而真实文件系统应先跟随 `link` 再处理 `..`。

最小复现：

```bash
python3 - <<'PY'
import importlib.util, shutil, tempfile
from pathlib import Path
s = Path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py")
sp = importlib.util.spec_from_file_location("vp", s)
vp = importlib.util.module_from_spec(sp); sp.loader.exec_module(vp)
r = Path(tempfile.mkdtemp(prefix="t064-order-", dir="/tmp"))
try:
    p, out = r/"project", r/"outside"
    (out/"sub").mkdir(parents=True); (out/"escape.md").write_text("outside")
    p.mkdir(); (p/"escape.md").write_text("coincidental inside")
    (p/"link").symlink_to(out/"sub", target_is_directory=True)
    raw = p/"link/../escape.md"
    got = vp._resolve_in_project(p, "link/../escape.md", p)
    print("raw_resolves_to", raw.resolve())
    print("raw_contained", vp._is_contained(raw, p))
    print("helper_returns", got)
    print("helper_target", got.resolve() if got else None)
finally:
    shutil.rmtree(r)
PY
```

实测：

```text
raw_resolves_to /private/tmp/.../outside/escape.md
raw_contained False
helper_returns /tmp/.../project/escape.md
helper_target /private/tmp/.../project/escape.md
```

把引用 `link/../escape.md` 放进 review 后，v0.14 与 v0.15 均 `dangling=[]`。也就是说 v0.15 没有 containment-check 原始 candidate，而是先把它改写成另一个项目内同名文件后再检查。

`.gitmodules` 有同一顺序错误：`submodule_roots` 先在 `verify_protocol.py:525-527` 对 candidate 做 `normpath` 后才 containment-check，却在 `:529-530` 对未折叠的原 candidate 做 `is_dir()` 并返回它。fixture：

```text
project/smod -> outside/sub
.gitmodules path = smod/../mod
raw .gitmodules path resolves to outside/mod
_is_contained(raw_path, project)=false
submodule_roots nevertheless returns [".../project/smod/../mod"]

project/mod/pkg/modghost.md exists
project/other/pkg/modghost.md exists
suffix hits=2
suffix_unique_match=false
review cites pkg/modghost.md
end_to_end dangling=[]   # 只能是错误接纳的 .gitmodules base 使其假绿
```

因此直接 base 与 `.gitmodules` base 都可独立绕过；suffix hit 这一条仍安全，但“三条路径统一受 canonical containment 保护”的整体声明不成立。

### 4. 诚实性 — **索引边界与固有残留诚实；canonical 与“真实存在”两处过强**

- canonical module docstring `verify_protocol.py:52-64` 声称 candidate 会直接经 `Path.resolve(strict=False)` 且项目外 symlink/`..` “never treated as resolved”；实际 `:792` 与 `:525-527` 会先词法折叠，以上反例假绿。`--help` 在 `:982-990` 同步了相同的绝对声明，因此同步了文字，但没有同步到真实能力。
- 索引关于 “tracked + untracked-not-ignored” 的边界描述与查询一致（module docstring `:103-130`，helper docstring `:546-567`，`--help :987-990`），ignored 不可见也在 `:120-122` 明说。可是“every file that genuinely exists” 不准确：`:590-600` 纳入 deleted tracked，且多命中时不会做存在性过滤。
- 非 Git 回退仍按 `:128-130,662-689` 的文字剪枝，实测一致。
- 两条既有固有残留未被悄悄改称已修，登记仍在 `:163-185`。行为复验：

```text
only vendor/mistyped/config.yaml exists
suffix_unique_match("mistyped/config.yaml")=true

actual Case/File.md; citation case/file.md on this macOS volume
Path.exists()=true
_any_base_resolves(...)=true
```

后者正体现文档所述宿主大小写依赖，前者正体现后缀语义碰撞；两项均仍诚实。

## Decisions / deviations

- Verdict 使用任务专用枚举 `MUST-FIX`，而不是通用模板的 `REWORK`。
- 判定口径：gitignored 文件虽可被排除为正向解析目标，但只要它真实存在并与一个可解析候选同后缀，就至少应阻止 suffix fallback 声称“唯一”；否则 `git add -f` 仍会翻转同一 worktree 事实。这是沿用 T-063 的保守假阴性口径。
- T-063 原始两例与扩展反例分开结论：不抹杀原始修复已经生效，也不以原始守卫全绿代替组合审计。
- 未修改被评审源码；全部临时 fixture 已清理。

## Open questions

none

## Verdict

**MUST-FIX**

## Next recommendation

先修 canonical 顺序：`_resolve_in_project` 与 `submodule_roots` 都应对未经词法折叠的 `base / cited`、`project / rel` 做 canonical containment，并让后续存在性检查沿用同一原始路径语义；新增 `symlink/../file` 的直接 base 与 `.gitmodules path` 两个端到端红测。索引侧应在判唯一之前过滤当前不存在的 tracked 项，并把 ignored 同后缀项至少作为 ambiguity-only 候选（不可用于正向 resolved，但可阻止伪唯一），分别加入 ignored-before/after-`git add -f` 稳定性和 deleted-tracked+one-real 回归守卫。完成后重跑 T-063 原始两例、上述三条新反例、真实 recursive submodule/NUL fixture 与全量 `HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py`，再确认 TH-0008 fixed。

## Vendor output (parsed) _(preview 8000/344374 chars; full raw stream in `T-064-output.log`)_

````
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
session id: 019f9f9e-c3c4-77c2-93fa-0a6b7c052f5b
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

# Task-type: code-review-acceptance

Anchor: `.hopper/tasks/code-review-acceptance.md::root`

## Purpose

Verify a change against its stated acceptance criteria. Review only — no edits.

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

## T-064（harnessloop v0.15.0 收 T-063 MUST-FIX 确认审，单 codex，接续 T-063）

**Task-type**: `code-review-acceptance` · **Vendor**: codex（接续自己 T-062/T-063，持有全部原始反例）· 只读

**评审对象**：`harnessloop` submodule commit `1153b7f`（v0.15.0）。`git -C harnessloop show 1153b7f`。对照你 T-063 的两条 MUST-FIX 与其复现（`.hopper/handoffs/T-063-output.md` 第 2、3 节）。

**背景（本修复链已走三轮）**：v0.13.0 降误报 50%→26% → 你 T-062 判 REWORK（5 个假阴性）→ v0.14.0 收 → 你 T-063 判 MUST-FIX（2 个更深的假阴性）→ v0.15.0 收：
- **untracked 伪唯一**：唯一性宇宙从 git-tracked 改为「工作区里真实存在且未被 gitignore」= tracked + untracked-but-not-ignored。注意实现方发现 `git ls-files --cached --others --recurse-submodules` 组合 git 不支持（`unsupported mode`），改用三次 NUL 安全查询合并去重 + `git submodule foreach --recursive` 覆盖嵌套 submodule 的未跟踪文件。
- **symlink containment 逃逸**：新 `_canonical`/`_is_contained` 对候选与 project root **两边**都 `resolve(strict=False)` 后比较；三条路径（`_resolve_in_project`/`_any_base_resolves`、`submodule_roots`、`suffix_unique_match` 命中复验）统一走同一套；containment 与存在性刻意分两步。
- docstring 三处过强声称改准 + `--help` 同步。

**只验四件事**：
1. **两条 MUST-FIX 是否真闭合**：**复跑你 T-063 的原始反例**（untracked_pseudo_unique、symlink_containment_escape 的三条路径），逐个报修前修后。
2. **新宇宙有无新洞**：tracked+untracked-not-ignored 作为唯一性宇宙——gitignored 但真实存在的文件现在仍不参与歧义，会不会构成新的伪唯一面（与 T-063 那条同形但换了边界）？`submodule foreach --recursive` 对嵌套 submodule 的未跟踪文件覆盖是否完整？非 git 回退路径现在处于什么状态、docstring 是否仍如实？
3. **canonical containment 是否可绕**：多级 symlink、symlink 指向 project root 内但经项目外中转、`.gitmodules` 里 path 是 symlink、以及 project root 本身在 symlink 下（macOS `/tmp`）的组合。三条路径是否**各自独立**受保护（T-063 曾发现两层防御其实共享盲点的情形）。
4. **诚实性**：docstring 三处修正（canonical containment / 索引宇宙 / --help）与实现实况是否逐字一致；两条既有固有残留（后缀语义碰撞、大小写宿主依赖）是否仍如实登记、未被悄悄升级为"已修"。

**Verdict**：`CONFIRMABLE`（TH-0008 可判 fixed）| `MUST-FIX`（逐条 file:line + 可复现）。
**产出**：四项逐条 + verdict。落盘 `.hopper/handoffs/T-064-output.md`。**Read-only**：反例/mutation 临时改动必须还原并说明；忽略跨仓/别目录全局 skill。中文。

codex
我会按 T-063 的原始反例逐项复跑，并额外覆盖 gitignored 边界、嵌套 submodule 与多种 symlink 组合；评审过程只读目标代码，所有反例放在临时目录，最终仅写入指定的 T-064 评审输出。
exec
/bin/zsh -lc "pwd && rg --files .hopper | sort && git status --short && git -C harnessloop status --short && git -C harnessloop rev-parse --show-toplevel && git -C harnessloop rev-parse HEAD && git -C harnessloop show --stat --oneline --decorate --no-renames 1153b7f && sed -n '1,260p' .hopper/handoffs/T-063-output.md" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 511ms:
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 M harnessloop
 m hopper-plugin
 ? kernels/openclaw
?? .hopper/handoffs/T-062-output-raw.txt
?? .hopper/handoffs/T-062-output.log
?? .hopper/handoffs/T-062-output.md
?? .hopper/handoffs/T-062-progress.log
?? .hopper/handoffs/T-063-output-raw.txt
?? .hopper/handoffs/T-063-output.log
?? .hopper/handoffs/T-063-output.md
?? .hopper/handoffs/T-063-progress.log
?? .hopper/handoffs/T-064-output.log
?? .hopper/handoffs/T-064-output.md
?? .hopper/handoffs/T-064-progress.log
/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop
1153b7f11aeea2e01882be2dd5e8d726e21e2b57
1153b7f (HEAD -> main, origin/main, origin/HEAD) fix(v0.15.0): 收 codex T-063 MUST-FIX——untracked 伪唯一 + symlink 逃逸两层 containment
 .claude-plugin/marketplace.json                    |   2 +-
 package.json                                       |   2 +-
 plugins/harnessloop/.claude-plugin/plugin.json     |   2 +-
 .../harnessloop-loop/scripts/verify_protocol.py    | 265 ++++++++++++++++-----
 scripts/validate.py                                | 255 ++++++++++++++++++++
 5 files changed, 467 insertions(+), 59 deletions(-)
---
phase: done
last_progress_at: "2026-07-26T17:56:39.616Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-26T17:56:39.615Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 410275
adapter_status: success
---
# T-063 · harnessloop v0.14.0 / T-062 REWORK 确认审

## Summary

已对 `harnessloop` commit `b44deb4` 逐项复跑 T-062 的五个原始最小反例，并补测 Git/untracked 唯一性宇宙、真实两层嵌套 submodule、非 Git 回退、symlink/`..`/绝对路径 containment，以及 coverage/文档诚实性。尾斜杠文件、断链 symlink、父目录逃逸和陈旧索引均已闭合；`noise_pruned_ambiguity` 在声明的 Git tracked 主路径闭合、在原始非 Git fixture 中仍按文档保留。不能确认 TH-0008 fixed：新索引会把真实未跟踪冲突漏出唯一性宇宙而制造伪唯一，且所谓“双层 containment”仅做词法 `normpath`，项目内 symlink 指向项目外时，直接 base、`.gitmodules` base 和 suffix fallback 三条路径都会假绿。

## Files touched

- `.hopper/handoffs/T-063-output.md`：本只读确认审交付物。
- 被评审源码：none；所有 fixture 均在系统临时目录中创建并自动删除，结束时 `git -C harnessloop status --short` 为空。

## Acceptance verification (4/4)

### 1. 五个 T-062 原始反例 — **4/5 在原脚本字面环境闭合；Git 主路径下 5/5 闭合**

直接从 `git show b44deb4^:.../verify_protocol.py` 加载修前实现、从当前文件加载 `b44deb4`，复跑 `.hopper/handoffs/T-062-output.log:4431-4440` 的原始 fixture。唯一适配是按任务说明给新版 `suffix_unique_match(cleaned, index, project)` 补第三个参数：

```text
b44deb4^ {"broken_symlink":{"dangling_count":0},
          "noise_pruned_ambiguity":{"dangling_count":0},
          "stale_index_after_delete":{"match_aft

... [truncated, 336374 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 380038
- end_time: 2026-07-26T18:16:29.123Z
- log: see `T-064-output.log` for raw output
