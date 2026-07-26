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
          "stale_index_after_delete":{"match_after_delete":true,"target_exists":false},
          "submodule_parent_escape":{"dangling_count":0},
          "trailing_slash_file":{"dangling_count":0}}
b44deb4  {"broken_symlink":{"dangling_count":1},
          "noise_pruned_ambiguity":{"dangling_count":0},
          "stale_index_after_delete":{"match_after_delete":false,"target_exists":false},
          "submodule_parent_escape":{"dangling_count":1},
          "trailing_slash_file":{"dangling_count":1}}
```

- `trailing_slash_file`：修前假绿、修后报 1 条 dangling。`_exists_as()` 对尾斜杠使用 `is_dir()`，显式 base 和 suffix 两条路径都调用它（`verify_protocol.py:567-578,625-626,647-653`）。
- `broken_symlink`：修前假绿、修后报 1 条 dangling；唯一命中后会对具体路径重新 `exists()`（`:621-626`）。
- `stale_index_after_delete`：修前 `True/False`、修后 `False/False`；同一 match-time 复验生效（`:605-626`）。
- `submodule_parent_escape`：修前假绿、修后报 1 条 dangling；普通 `../` 被 `normpath` 后的词法 containment 拒绝（`:452-457,629-653`）。
- `noise_pruned_ambiguity`：T-062 原脚本创建的是非 Git 临时目录，所以修后仍只索引 `src/pkg/real.md` 并返回 resolved；把同一两个文件 `git add` 后，索引同时含 `src/pkg/real.md`、`build/pkg/real.md`，`suffix_unique_match=False`，端到端会报 dangling。也就是说 Git 主路径修复有效，但原始非 Git 反例没有消失；这与 docstring 的残留声明一致（`:84-100,527-564`），不能把字面的五项都报成“无条件已修”。

新增回归覆盖位于 `scripts/validate.py:919-1284`。基线命令：

```text
$ HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py
...
ok: verify (git-tracked index) reports the ambiguous `pkg/real.md` suffix ...
ok: submodule_roots rejects a .gitmodules `path =` entry that resolves outside ...
Plugin framework validation passed.
```

### 2. 索引换源 — **嵌套 submodule 与 tracked noise 正确；新增 untracked 伪唯一（MUST-FIX）**

`_git_tracked_index()` 只消费 `git ls-files -z --recurse-submodules`（`verify_protocol.py:461-524`）。对真实的 `top -> modules/middle -> deps/leaf` 两层 submodule 执行 recursive init 后：

```text
before_recursive_init_has_nested=false
after_recursive_init_has_nested=true
after_recursive_init_nested_file_exists=true
index_nested_matches=[
  ["modules","middle","deps","leaf","deep","pkg","nested.md"]
]
suffix_resolves=true
```

因此已 checkout/recursive-init 的嵌套 submodule 确实被覆盖；未 init 时文件本身也不存在于 worktree。非 Git 回退则精确复现 docstring 所述旧盲点：

```text
non_git_noise_fallback:
  indexed_matches=[["src","pkg","real.md"]]
  suffix_resolves=true
```

但是换源引入了新的可复现假阴性。Git 项目中同时存在 tracked `src/pkg/real.md` 和 untracked `scratch/pkg/real.md` 时，引用 `pkg/real.md` 被当作唯一命中而假绿；仅执行 `git add scratch/pkg/real.md`、不改变任何文件内容后，同一引用反而变为 dangling：

```text
untracked_collision_exists=true
tracked_only_index=[["src","pkg","real.md"]]
before_add_dangling=[]
after_add_dangling=["... reviews/case.md cites `pkg/real.md` which does not exist"]
```

最小复现（从仓库根运行）：

```bash
python3 - <<'PY'
import importlib.util, shutil, subprocess, tempfile
from pathlib import Path
s = Path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py").resolve()
sp = importlib.util.spec_from_file_location("vp", s)
vp = importlib.util.module_from_spec(sp); sp.loader.exec_module(vp)
r = Path(tempfile.mkdtemp(prefix="t063-untracked-"))
try:
    p = r/"project"; p.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=p, check=True)
    rd = p/".harnessloop/goals/g/rounds/0001"
    (rd/"reviews").mkdir(parents=True); (rd/"evidence").mkdir()
    (rd/"scope-lock.md").write_text(
        "# Scope Lock\n\n## Allowed Changes\n\n- `reviews/`\n- `evidence/`\n"
    )
    (rd/"reviews/case.md").write_text("- `pkg/real.md`\n")
    for rel in ("src/pkg/real.md", "scratch/pkg/real.md"):
        f = p/rel; f.parent.mkdir(parents=True, exist_ok=True); f.write_text(rel)
    subprocess.run(["git", "add", "src/pkg/real.md"], cwd=p, check=True)
    before, _ = vp.verify_project(p)
    subprocess.run(["git", "add", "scratch/pkg/real.md"], cwd=p, check=True)
    after, _ = vp.verify_project(p)
    dangling = lambda xs: [v["detail"] for v in xs if v["kind"] == "dangling-citation"]
    print("before_add", dangling(before))
    print("after_add", dangling(after))
finally:
    shutil.rmtree(r)
PY
```

实测 `before_add []`，`after_add` 出现 `pkg/real.md` dangling。

实现和 docstring 都诚实地把唯一性改定义为“tracked 文件”（`:84-100,501-524`），但 Rule B 检查的是当前 worktree 的 review/evidence，未跟踪文件完全可能是本轮刚产生的真实候选；仅改变 index 状态便翻转同一文件系统事实，仍是后缀放宽带来的伪唯一，不能因已登记而视为闭合。

### 3. 两层 containment — **`..`/POSIX 绝对路径闭合；symlink 可同时绕过两层（MUST-FIX）**

独立探针结果：

```text
_resolve_in_project(project, "../outside/pkg/ghost.py", project) -> None
_resolve_in_project(project/"a/b", "../../../outside/pkg/ghost.py", project) -> None
_resolve_in_project(project, "/tmp/t063-absolute", project) -> None
submodule_roots(path="../outside" or path="/tmp/...") -> rejected
```

但 `is_under()` 只比较 `os.path.normpath` 后的字符串，从不 canonicalize symlink（`verify_protocol.py:238-244`）。`submodule_roots()` 同样只做词法检查，再以会跟随 symlink 的 `is_dir()` 接受 base（`:452-457`）；`_resolve_in_project()` 也是词法 `normpath`（`:641-644`）；suffix 命中最终用会跟随 symlink 的 `exists()`（`:567-578,625-626`）。端到端 Git fixture 让 `project/link -> ../outside`，并在项目内再放一个已 `git add`、指向外部文件的 `deep/pkg/external.md` symlink，三个已被 Rule B 计入检查的引用全部假绿：

```text
citations:
  `link/pkg/ghost.py`  # 直接 project base
  `pkg/ghost.py`       # .gitmodules path = link，base 自身为 symlink
  `pkg/external.md`    # suffix index 中的文件 symlink
coverage.citations_checked=3
dangling=[]
resolved target for all three = .../outside/pkg/ghost.py
```

这也使 module docstring 的“Every base resolution ... is containment-checked”以及“must land inside the project root”（`:52-59`）成为过度声明。最小复现（从仓库根运行）：

```bash
python3 - <<'PY'
import importlib.util, shutil, subprocess, tempfile
from pathlib import Path
s = Path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py").resolve()
sp = importlib.util.spec_from_file_location("vp", s)
vp = importlib.util.module_from_spec(sp); sp.loader.exec_module(vp)
r = Path(tempfile.mkdtemp(prefix="t063-symlink-"))
try:
    p, out = r/"project", r/"outside"
    rd = p/".harnessloop/goals/g/rounds/0001"
    (rd/"reviews").mkdir(parents=True); (rd/"evidence").mkdir()
    (out/"pkg").mkdir(parents=True); (out/"pkg/ghost.py").write_text("outside")
    (p/"link").symlink_to(out, target_is_directory=True)
    (p/"deep/pkg").mkdir(parents=True)
    (p/"deep/pkg/external.md").symlink_to(out/"pkg/ghost.py")
    (p/".gitmodules").write_text('[submodule "x"]\n\tpath = link\n')
    (rd/"scope-lock.md").write_text(
        "# Scope Lock\n\n## Allowed Changes\n\n- `reviews/`\n- `evidence/`\n"
    )
    (rd/"reviews/case.md").write_text(
        "- `link/pkg/ghost.py`\n- `pkg/ghost.py`\n- `pkg/external.md`\n"
    )
    subprocess.run(["git", "init", "-q"], cwd=p, check=True)
    subprocess.run(["git", "add", "-A"], cwd=p, check=True)
    violations, coverage = vp.verify_project(p)
    print("checked", coverage["citations_checked"])
    print("dangling", [v["detail"] for v in violations if v["kind"] == "dangling-citation"])
    print("outside", (p/"link/pkg/ghost.py").resolve(), (p/"deep/pkg/external.md").resolve())
finally:
    shutil.rmtree(r)
PY
```

实测输出为 `checked 3`、`dangling []`，两个 resolve 结果均在 `project` 外。

### 4. 诚实性 — **coverage 与两条固有残留诚实；containment 声明不诚实**

构造 5 个外部 span（`~/`、POSIX absolute、`C:/`、反斜杠 drive path、UNC）、1 个普通悬空引用，再加 1 个 `verify:ignore` 外部 span：

```text
coverage={
  "rounds":1,
  "rounds_zero_inspected":0,
  "rule_a_files":2,
  "rule_b_files":2,
  "citations_checked":1,
  "citations_exempt_external":5
}
dangling=["... cites `relative/missing.md` which does not exist"]
```

忽略标记的 span 没有错误计入 external，五种真正因 external 规则跳过的 span 恰好计 5。`_empty_coverage()` 的六个键与 `harnessloop-loop/SKILL.md` Mechanical Gate Boundary IN 的六个字段集合完全相等：

```text
["citations_checked","citations_exempt_external","rounds",
 "rounds_zero_inspected","rule_a_files","rule_b_files"]
one_to_one=true
```

实现证据为 `verify_protocol.py:315-336,361-413,728-745,785-796`，文档为 `harnessloop-loop/SKILL.md:444-451`。两条登记的固有残留也与实况一致：唯一的 `vendor/mistyped/config.yaml` 会让误写的 `mistyped/config.yaml` 返回 `True`；本机大小写不敏感卷上 `Case/File.md` 与 `case/file.md` 都通过显式 base existence。对应 docstring `verify_protocol.py:133-155` 没有把它们说成已修。诚实性缺口仅在另一个更强的 containment 声明：`:52-59` 没有承认 symlink canonical escape，而实现确实可绕过。

## Decisions / deviations

- Verdict 按任务专用枚举采用 `MUST-FIX`，而不是通用 review 模板的 `REWORK`：两个反例都能让真正多义或项目外的引用在 `citations_checked > 0` 时无 dangling，正中本审最重的假阴性风险。
- “五个原始反例”同时按原脚本的非 Git 字面环境和 v0.14.0 声明的 Git 主路径报告；没有把非 Git 残留偷换成 Git fixture 后再声称无条件 5/5。
- 除新版 helper 的必需第三参数外未改动 T-062 原始反例逻辑。所有临时 Git repo、submodule 和 symlink fixture 均已删除；未修改被评审源码。

## Open questions

none

## Verdict

**MUST-FIX**

## Next recommendation

先把 containment 改为 canonical 路径判定：对 project、每个 base、显式 candidate、`.gitmodules` candidate 以及 suffix 命中的具体目标做 `resolve(strict=False)`（或等价的 symlink-aware containment），再做类型/存在性检查，并新增上述三路 symlink 出界端到端负例。索引侧至少把当前未跟踪、非 ignored 文件纳入歧义宇宙（或明确采用不会因 `git add` 翻转同一 worktree 事实的等价方案），新增“tracked + untracked 同后缀”守卫；保留真实两层 submodule 与非 Git 残留声明测试。两项假阴性均翻红后再重跑 T-063，TH-0008 才可判 fixed。

## Vendor output (parsed) _(preview 8000/355296 chars; full raw stream in `T-063-output.log`)_

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
session id: 019f9f8c-2860-72d2-af1e-b57b280facfb
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

## T-063（harnessloop v0.14.0 收 T-062 REWORK 确认审，单 codex，接续 T-062）

**Task-type**: `code-review-acceptance` · **Vendor**: codex（接续自己 T-062，持有原始最小反例脚本）· 只读

**评审对象**：`harnessloop` submodule commit `b44deb4`（v0.14.0）。`git -C harnessloop show b44deb4`。对照你自己 T-062 的五个最小反例与判定（`.hopper/handoffs/T-062-output.md`）。

**背景**：v0.13.0 把 Rule B 误报 50%→26%；你 T-062 判 REWORK，指出 5 个可复现假阴性。v0.14.0 逐条收：`_exists_as`（尾斜杠须 `is_dir()` + 命中后复验具体路径，一并修断链 symlink 与陈旧索引）、索引换源为 `git ls-files --recurse-submodules`（修剪枝伪唯一，并去掉无协议依据的噪声目录硬编码；非 git 回退保留旧盲点且 docstring 已声明）、`_resolve_in_project`/`_any_base_resolves` + `submodule_roots` 双层 containment（修父目录逃逸）、Windows 盘符/UNC 识别为项目外。新增 coverage 字段 `citations_exempt_external` 把 `~/`、绝对路径豁免这块此前静默的无牙面计出来。

**只验四件事**：
1. **五个反例是否真闭合**：**直接复跑你 T-062 的原始最小反例脚本**（trailing_slash_file / broken_symlink / noise_pruned_ambiguity / submodule_parent_escape / stale_index_after_delete），逐个报修前修后。注意 `suffix_unique_match` 签名已变为 `(cleaned, index, project)`。
2. **换源有无引入新洞**：`git ls-files` 作为唯一性宇宙——真实存在但**未被 git 跟踪**的文件现在不参与歧义判定，会不会因此产生新的伪唯一？`--recurse-submodules` 对嵌套 submodule 是否真覆盖？非 git 回退路径的盲点是否与 docstring 声明**完全一致**（不得声称已修）？
3. **containment 两层是否可绕**：symlink 指向项目外、`..` 多层、`.gitmodules` 里的绝对路径或 `../` path、以及 base 自身是 symlink 的情形。
4. **诚实性**：`citations_exempt_external` 计数是否正确且与 `harnessloop-loop/SKILL.md` 的 Mechanical Gate Boundary IN 列一一对应；docstring 登记的两条固有残留（后缀语义碰撞、大小写宿主依赖）是否与实现实况一致，有无把"未修"说成"已修"。

**Verdict**：`CONFIRMABLE`（TH-0008 可判 fixed）| `MUST-FIX`（逐条 file:line + 可复现）。
**产出**：四项逐条 + verdict。落盘 `.hopper/handoffs/T-063-output.md`。**Read-only**：mutation/反例用的临时改动必须还原并说明；忽略跨仓/别目录全局 skill。中文。

codex
我将只读核验 `harnessloop` 的 `b44deb4`，直接复跑 T-062 的五个最小反例，并补测索引换源、两层 containment 与 coverage 诚实性；仅写入指定评审报告，不改产品代码。
  → 读取 T-062 原始反例与 b44deb4 变更，定位验收点
  • 复跑五个原始反例并记录修前/修后证据
  • 补测 git 索引边界、两层 containment 与 coverage 诚实性
  • 整理证据并写入 T-063-output.md
exec
/bin/zsh -lc "git status --short && git -C harnessloop status --short && git -C harnessloop rev-parse HEAD && git -C harnessloop show --stat --oneline --decorate --no-renames b44deb4 && sed -n '1,260p' .hopper/handoffs/T-062-output.md" in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 450ms:
 M .hopper/handoffs/leader-tasklist.md
 M .hopper/queue.md
 M harnessloop
 m hopper-plugin
 ? kernels/openclaw
?? .hopper/handoffs/T-062-output-raw.txt
?? .hopper/handoffs/T-062-output.log
?? .hopper/handoffs/T-062-output.md
?? .hopper/handoffs/T-062-progress.log
?? .hopper/handoffs/T-063-output.log
?? .hopper/handoffs/T-063-output.md
?? .hopper/handoffs/T-063-progress.log
b44deb47c13ef9cab6223ed22d1e0f04466221b7
b44deb4 (HEAD -> main, origin/main, origin/HEAD) fix(v0.14.0): 收 codex T-062 REWORK——Rule B 五个假阴性 + 项目外豁免可见化
 .claude-plugin/marketplace.json                    |   2 +-
 package.json                                       |   2 +-
 plugins/harnessloop/.claude-plugin/plugin.json     |   2 +-
 .../harnessloop/skills/harnessloop-loop/SKILL.md   |   1 +
 .../harnessloop-loop/scripts/verify_protocol.py    | 392 +++++++++++++++++----
 scripts/validate.py                                | 319 +++++++++++++++--
 6 files changed, 617 insertions(+), 101 deletions(-)
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
2. **嵌套 submodule base**：真实 `path = kernels/vendorlib` 正向通过；把 `submodule_roots()` 临时恢复成 `if not rel or "/" in rel` 后，带同后缀 decoy 的端到端断言单独失败，证明 `validate.py:930-948` 的 decoy 已彻底隔离后缀回退。反例是解析器对 path 没有合法性/项目内 containment 检查（`ve

... [truncated, 347296 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 410275
- end_time: 2026-07-26T17:56:39.615Z
- log: see `T-063-output.log` for raw output
