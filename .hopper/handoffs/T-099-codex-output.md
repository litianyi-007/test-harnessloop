---
task_id: T-099-codex
adapter: codex
model: gpt-5.6-sol
requested_selector: null
effective_selector: gpt-5.6-sol
effective_selector_source: policy
selector_kind: unknown
catalog_source_kind: unknown
catalog_source_label: unknown
catalog_observed_at: null
catalog_freshness: unknown
binary_availability: unknown
binary_basename: null
status: done
pid: 87680
start_time: "2026-08-12T07:16:35.597Z"
end_time: "2026-08-12T07:20:47.790Z"
exit_code: 0
duration_ms: 252140
mode: background
phase: done
last_progress_at: "2026-08-12T07:20:47.792Z"
last_progress: Task completed successfully.
progress_seq: 2
progress_log: ./T-099-codex-progress.log
raw_log: ./T-099-codex-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: claude-code
session_id: null
log: ./T-099-codex-output.log
started_by_pid: 87675
observed_models_json: "[]"
model_attestation_source: null
model_attestation_observed_at: null
resolution_status: unverified
resolution_detail: selector-kind-unknown
diagnostic_code: selector-metadata-cache-missing
adapter_diagnostic_code: none
recovered_output: false
recovered_output_state: no-text
recovered_output_source: none
signal: null
process_cleanup: not-needed
adapter_status: success
---

# T-099-codex — codex (background, done)

Output streaming to `T-099-codex-output.log`. Status updates here.

## Vendor output (parsed) _(preview 8000/238691 chars; complete parsed output is available through `hopper-dispatch --result T-099-codex --full`)_

```
Reading additional input from stdin...
OpenAI Codex v0.146.0
--------
workdir: /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: xhigh
reasoning summaries: none
session id: 019ff4d4-861d-7ce0-8e7d-9c9a5c1fff44
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

**设计评审（只读，不得改任何文件、不得启停进程）。** 仓 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/hopper-plugin/`（**基线已同步到上游 v0.54.0**）。**机器上有用户自己的常驻 gateway（pid 29071）与 `~/.openclaw`，绝对不要碰。**

用户明确要求本次改动经异构模型审核，**先审设计再审代码**。这是第一道：**动手之前**评审修法设计。

## 缺陷（已定位，不用重新找）

`cli/src/dispatch.js` 两条组装 prompt 的路径：
- **queue 行**（坏）：`:113` `const taskSpec = await loadTaskSpec(hopperDir, taskId)` → `:118` `composePrompt(frame, taskSpec, { governance })`
- **`--adhoc`**（好）：`:162` `const taskSpec = brief;` → `:164` 同上

`loadTaskSpec()`（`:208` 起，**未 export**）四条返回路径里**两条撒同一个谎**：
- `:220` 文件在、正则未命中 → `(no detailed spec found for ${taskId} in leader-tasklist.md; using queue.md brief only)`
- `:229` **ENOENT** → `(no leader-tasklist.md found at ${path}; using queue.md brief only)`

两句都声称「using queue.md brief only」，而**返回的字符串本身成了 spec**，queue 行的 `brief`（`cli/src/queue.js:140` 解析并随 task 对象返回）从未进入 prompt。被派发的 vendor 拿到一个没有任务内容的框架，而 RPC 返回 `exit 0` + `status: done` + `Task completed successfully.`。

**机械根因**：`loadTaskSpec(hopperDir, taskId)` 入参里没有 `task`，函数内拿不到 brief；而调用点 `:113` 处 `task` 早已在作用域内。

## 已查清的约束（直接用，不要重新推导）

1. **不能改 `composePrompt`**：`cli/src/tasks.js:143-154` 的拼装形状被 `tests/unit/tasks.test.js` 的**四条逐字节 `assert.equal`** 锁死（`:130`/`:138`/`:150`/`:155`）。在 dispatch 侧把 brief 并进 `taskSpec` 字符串则一条不动。
2. **`brief` 的空值是空字符串不是 null**（`queue.js:140`：无 Brief 列时给 `''`）。两处现存 fixture 正走这条路：`tests/unit/host-detect.test.js:138-180`、`tests/unit/resolve-and-model-hints.test.js:37-68`。
3. **`taskTextRequestsReadOnly`（`cli/src/dispatch.js` 内）已经**把 `resolved.task.brief` 与 `resolved.taskSpec` 拼起来判定只读——**brief 已经能影响 sandbox 权限，却进不了 prompt**。若把 brief 并入 taskSpec，这个函数会重复计入同一段文本。
4. **测试为什么没抓到**：`tests/unit/dispatch-governance.test.js:12-23` 的 fixture **总是写 leader-tasklist.md**，queue 路径所有用例都命中成功分支。
5. **adhoc 的对照断言**：`tests/unit/dispatch-governance.test.js:89-90`（`assert.equal(r.taskSpec, '...')` + `assert.ok(r.composedPrompt.includes('...'))`）——queue 路径修复后应镜像出同形断言。
6. `composePrompt` 对 `null`/`undefined` 的 taskSpec 会在 `.trim()` 抛 TypeError。

## 要你裁的四件事

**Q1（用户点名交评审）**：有详细 spec 时，queue brief 要不要**也**并入？
- **甲** `taskSpec ?? brief`（择一）：与 adhoc 路径对称，也是那句占位符文案所暗示的原意。风险：brief 里若有 spec 没写的约束会丢。
- **乙** `[spec, brief]` 合并：与既有 `taskTextRequestsReadOnly` 的做法一致。风险：两者矛盾时 vendor 拿到双份指令；且该函数会重复计入。
**请给出你的选择与理由，不要两边都说有道理。**

**Q2**：`loadTaskSpec` 该怎么改？返回 `null` 让调用方回落？改签名收 `task`？还是导出它以便直测（现未 export，只能经 `resolveDispatch` 间接覆盖）？**注意约束 6。**

**Q3**：两条撒谎路径（`:220`/`:229`）的**文案**该怎么写才诚实？占位符还该不该保留在 prompt 里？

**Q4 fail-closed 边界**：spec 与 brief **皆空**时该抛错还是放行？考虑约束 2 里那两处现存 fixture（它们正是 `brief === ''` 且无 leader-tasklist）——**抛错会不会把它们打红？如果会，那是真红还是该改 fixture？**

## 另外

- 有没有我**没列出来**的受影响面？（例如 `cli/bin/hopper-dispatch` 里 `--resolve` 的回显、background/swarm 路径）
- 这个修法有没有可能引入**新的静默失败**？
- **不要因为搜不到就下「不存在」的结论**——先换搜索维度。

codex
我会严格只读评审：核对两条 dispatch 路径、queue 解析、只读判定、回显与 background/swarm 调用链，并用现有测试定位兼容性边界；不会修改文件，也不会触碰常驻 gateway 或 `~/.openclaw`。
exec
/bin/zsh -lc 'pwd && git -C hopper-plugin status --short && rg -n "loadTaskSpec|composePrompt|taskTextRequestsReadOnly|taskSpec|brief|resolveDispatch|background|swarm" hopper-plugin/cli/src/dispatch.js hopper-plugin/cli/src/queue.js hopper-plugin/cli/src/tasks.js hopper-plugin/cli/bin/hopper-dispatch hopper-plugin/tests/unit/dispatch-governance.test.js hopper-plugin/tests/unit/host-detect.test.js hopper-plugin/tests/unit/resolve-and-model-hints.test.js' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 2141ms:
2026-08-12 15:16:49.915 xcodebuild[90123:34359118]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-12 15:16:50.076 xcodebuild[90123:34359117] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
git: warning: confstr() failed with code 5: couldn't get path of DARWIN_USER_TEMP_DIR; using /tmp instead
git: error: couldn't create cache file '/tmp/xcrun_db-emWKVEXF' (errno=Operation not permitted)
2026-08-12 15:16:50.652 xcodebuild[90125:34359133]  DVTFilePathFSEvents: Failed to start fs event stream.
2026-08-12 15:16:50.833 xcodebuild[90125:34359132] [MT] DVTDeveloperPaths: Failed to get length of DARWIN_USER_CACHE_DIR from confstr(3), error = Error Domain=NSPOSIXErrorDomain Code=5 "Input/output error". Using NSCachesDirectory instead.
 M package-lock.json
?? ISSUE-queue-brief-dropped-without-leader-tasklist.md
?? ISSUE-stale-status-on-runner-death.md
hopper-plugin/tests/unit/host-detect.test.js:22:import { resolveDispatch } from '../../cli/src/dispatch.js';
hopper-plugin/tests/unit/host-detect.test.js:138:// resolveDispatch + validateHostVendorSeparation.
hopper-plugin/tests/unit/host-detect.test.js:168:    // Layer 1 (Approved Vendors) passes — resolveDispatch does not throw.
hopper-plugin/tests/unit/host-detect.test.js:169:    const resolved = await resolveD

... [truncated, 230691 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 252140
- end_time: 2026-08-12T07:20:47.790Z
- log: see `T-099-codex-output.log` for raw output
