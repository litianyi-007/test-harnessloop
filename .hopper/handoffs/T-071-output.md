---
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
status: done
phase: done
end_time: "2026-07-27T17:59:05.486Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 406562
adapter_status: success
last_progress_at: "2026-07-27T17:59:05.488Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
---
# T-071 — `verify:ignore` 收窄规格对抗审

## Summary

已完成六项只读对抗审；规格识别了真实问题，但当前设计不能准确度量其声称的 collateral，也没有在本规格内阻止新评审继续使用裸 marker。精确语法还存在逗号不可逆分词、HTML 注释终止符、两行作用域重复命中和未定义的诊断基数等规格缺口。结论为 **REWORK**：先修正并版本化遥测，以新旧 round 分流的既有裸语法约束解决本轮问题，暂缓 §3.2/§3.3。

## Files touched

none（评审对象、实现与规格均未修改；本交付文件不计入被评审范围）

## Acceptance verification (6/6)

### 1. §6 的五个靶子 — FAIL

1. **§6.1 字面比较 — FAIL。** `,` 同时是列表分隔符和合法引用文本的一部分；当前实现还明确支持逗号多区间 locator。反例：引用 `` `src/a.py:44-46,443-507` `` 是一个 citation，但 `verify:ignore=src/a.py:44-46,443-507` 按 §3.2 只能拆成两个错误名字。`-->` 也没有转义规则；反例 `@@wiki/a-->b.py` 会被当前 alias-first 分支认作 citation，却会在 marker 内提前终止 HTML comment。证据：`verify_protocol.py:341-350,598-614,698-714`，规格 `:70-81`。
2. **§6.2 unmatched — FAIL。** “目标只出现在本行或下一行之一”若把作用域定义为二者的并集，本身不误伤；缝在于同一清洗后文本出现两次。反例：marker 点名 `missing/x.py`，其本行是本意豁免，下一行又出现同名真实引用；两处都会被豁免、目标已命中，因而没有 `ignore-span-unmatched`。规格没有定义零次、一次、多次 occurrence 的不同语义。
3. **§6.3 collateral — FAIL。** 定义与示例直接矛盾：`:93` 规定“被豁免且未被精确点名”都计入，因此单引用 + 裸 marker 应为 1；`:95` 却规定为 0。裸 marker 不携带“本意豁免哪条”的信息，故无法推导真实 collateral。
4. **§6.4 保留裸形式 — FAIL。** 当前方案只是“可见”，不是“收窄”：规格明确不报违规（`:102-119`），B2b 的 `==0` 也只是建议且不属于本规格的 teeth（`:99-100,142`）。E1 并未造成“全局继续合法或修改历史评审”二选一；可对旧 round 维持旧语义、对启用新协议的 round 施加新规则。并且被引用的 E1 原文禁止的是修改 finding 的实质内容、结论或证据对象来躲门，不是证明“任何 marker 迁移都禁止”：`docs/rule-ab-pilot-budget-20260728.md:61-66`。
5. **§6.5 计数修正 — FAIL。** I5 只锁住 violation `kind/detail`，没有锁住 coverage。规格自己要求 coverage 逐字同步进 `decision.md`（`:140-141`），打印又直接包含该字段（`verify_protocol.py:2841-2849`）；重定义数值和新增字段都会使历史快照与新版重跑不同。这里需要显式的 telemetry schema 迁移，而不能称“零迁移”。

### 2. 精确形式 `verify:ignore=<span>` 的绕过面 — FAIL

可复现实测（直接加载当前 `pathish_citations`）：

```text
'src/a,b.py'                 -> ['src/a,b.py']
'src/a.py:44-46,443-507'     -> ['src/a.py:44-46,443-507']
'@@wiki/a-->b.py'            -> ['@@wiki/a-->b.py']
comma split                  -> ['src/a.py:44-46', '443-507']
HTML comment data            -> ' verify:ignore=@@wiki/a'
HTML residual data           -> 'b.py -->'
```

复现入口：

```bash
python - <<'PY'
import runpy
from html.parser import HTMLParser
m = runpy.run_path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py")
f = m["pathish_citations"]
for x in ("src/a,b.py", "src/a.py:44-46,443-507", "@@wiki/a-->b.py"):
    print(repr(x), "->", f(f"cite `{x}`")[0])
print("comma split ->", "src/a.py:44-46,443-507".split(","))
class H(HTMLParser):
    def handle_comment(self, x): print("HTML comment data ->", repr(x))
    def handle_data(self, x):
        if x.strip(): print("HTML residual data ->", repr(x))
H().feed("<!-- verify:ignore=@@wiki/a-->b.py -->")
PY
```

逐项判断：

- **逗号 — FAIL：** 除合法文件名 `src/a,b.py` 外，当前协议自己的多区间 locator 就是必现反例。没有 escaping/quoting grammar 时无法无歧义恢复原 span。
- **`-->` — FAIL：** 规格没有规定拒绝、编码或解析方式。即使实现选择从原始行取最后一个 `-->`，它也已偏离该构造的 HTML comment 语义；不能把关键行为留给实现猜测。
- **大小写、尾斜杠、`./` — NOTE（fail-closed，但须写清）：** 仅 `strip()` 和 `\`→`/` 意味着 `src/app.py`≠`SRC/App.py`、`rounds/0001`≠`rounds/0001/`、`src/app.py`≠`./src/app.py`。它们不会静默扩大豁免，因为应触发 unmatched，但会造成作者认为是同一路径却点名失败；错误 detail 必须打印 marker 原文、清洗后目标和候选。
- **反斜杠与外侧空白 — NOTE：** 若 marker entry 也逐项执行相同清洗，则 `src\app.py` 会匹配 `src/app.py`，外侧空白也会消失；规格只说比较对象是清洗后的 span，没有明确“先 split 再逐 entry 清洗”。反例 `verify:ignore=src/a.py, src/b.py` 的第二项是否保留前导空格，当前文字不能唯一决定。
- **反向误命中 — FAIL：** 同一 cleaned text 的所有 occurrence 都会命中，而不是只命中作者心中的那个 occurrence；这在同一行重复引用或 marker 的两个行位中重复引用时，会静默多豁免。

### 3. `ignore-span-unmatched` 是否误伤 — FAIL

- **只出现在两个行位之一：PASS。** 若规范明确“marker scope 是两个行位的并集”，存在于任一行就算命中是自洽的，不应按另一个空行再报错。
- **重复 occurrence：FAIL。** 具体反例：

  ```markdown
  本意是散文例子 `missing/x.py`。 <!-- verify:ignore=missing/x.py -->
  下一行却把同名文件当证据再次引用：`missing/x.py`
  ```

  按 `:77,85`，两处文本完全相等，均被豁免，unmatched 为 0；按 `:93` 两处又都属“精确点名”，collateral 仍为 0。该组合同时绕过 stale 检测和 collateral 监测。
- **违规基数未定义：FAIL。** 一个 marker 点名 3 个不同 span、只有 2 个存在，应产生 **1 条** `ignore-span-unmatched`（对唯一缺失目标逐目标报，detail 含 review、marker 行号和缺失的 cleaned target），不是对 3 个名字都报错。重复列出同一名字应另判 syntax error 或去重；规格必须二选一并加精确计数 fixture。

当前两行作用域的可复现依据是 `verify_protocol.py:689-691`；现有 fixture 也明确同时覆盖“上一行 marker”和“同行 marker”（`harnessloop/scripts/validate.py:1258-1280`）。

### 4. `citations_ignored_collateral` 的定义 — FAIL

该字段无法从现有语法度量“作者本意以外的豁免”，最多能度量“未作用域化的豁免”：

- **把本就该豁免的算成 collateral：** 裸 marker 下一行有 3 个均为散文例子的引用，实际 collateral=0；`:93/:96` 会报 3。
- **漏掉真实 collateral（裸形式）：** 裸 marker 已陈旧，下一行后来只有 1 个真实 dangling citation；`:95` 强制报 0，但实际 collateral=1。
- **漏掉真实 collateral（精确形式）：** 上一节的同名双 occurrence 反例中只想豁免第一个，第二个仍被文本级点名连带豁免；字段报 0，实际 collateral=1。
- **定义内部矛盾：** `:93` 对“单引用 + 裸 marker”算 1，`:95` 算 0；不存在同时满足两者的实现。

建议把字段改名并诚实定义为 `citations_ignored_unscoped`：逐 occurrence 统计所有由裸 marker 跳过、且按完整 classifier 本会进入 `cited` 的 citation。不要称其为实际 collateral；实际意图没有输入，机器无法恢复。

### 5. “零迁移” — FAIL（高严重度，实施前必须处理）

I5 只证明 violation 判定兼容，不证明输出契约兼容。当前纪律要求 coverage 行逐字入 `decision.md`，所以 §3.1 重定义旧字段会使同一历史 round 的新版重跑与当时记录不一致；§3.4 新增字段又会改变整行字节。它不要求改历史文件，但它是一次真实的 **coverage schema migration**。

此外，按规格 §3.1 的口径对当前 checkout 三份 setup-wizard 评审重算，结果是 **14→8，不是规格 `:31` 的 14→6**：

```text
rounds/0001/reviews/adversarial-review.md: old=2, citation_count=2
rounds/0002/reviews/adversarial-review.md: old=5, citation_count=2
rounds/0003/reviews/adversarial-review.md: old=7, citation_count=4
TOTAL: old=14, citation_count=8
```

复现命令：

```bash
python - <<'PY'
import runpy
from pathlib import Path
m = runpy.run_path("harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py")
f, marker = m["pathish_citations"], m["IGNORE_MARKER"]
root = Path(".harnessloop/goals/20260716-001-setup-wizard")
old_total = new_total = 0
for p in sorted(root.glob("rounds/*/reviews/*.md")):
    lines = p.read_text().splitlines()
    raw = "\n".join(lines)
    old = f(raw)[2]
    new = sum(
        len(f(line.replace(marker, ""))[0])
        for i, line in enumerate(lines)
        if marker in line or (i > 0 and marker in lines[i - 1])
    )
    old_total += old; new_total += new
    print(f"{p.relative_to(root)}: old={old}, citation_count={new}")
print(f"TOTAL: old={old_total}, citation_count={new_total}")
PY
```

该命令对每个满足 `marker in line or marker in previous_line` 的行，移除同行 marker 后把该行重新送入当前 `pathish_citations`，累计返回的 `cited` occurrence。这个口径正是 `:64-68` 所写的“本来会进入 cited”；差异说明实施前必须重跑并公布 corpus 基线。

处置应为：

1. 冻结 `citations_ignored_explicit` 的旧语义，新增名字准确的新字段；不要静默重定义已有字段。
2. coverage 输出增加 `coverage_schema=v2` 及 verifier 版本/commit；明确历史 `decision.md` 是与当时版本绑定的快照，新版 replay 不做跨 schema 字节比较。
3. 若“历史重跑字节相同”真是硬要求，则必须用旧 verifier/schema replay 旧 round，或按 round 协议版本输出旧 schema。
4. I5 扩为两组 fixture：violation parity，以及明确列出 v1→v2 预期字段差异的 telemetry migration 测试。

## 第 6 项：值不值得做 — FAIL（否决当前 §3.2/§3.3）

**取舍：本轮不值得引入当前精确语法。** pilot 的实测是 1 条 collateral、绝对量小；规格自己的语料是 679 个引用行中 79% 单引用、存量 marker 仅 4 份。与此同时，新语法已经引入任意合法路径分隔、HTML 终止、两行 occurrence、重复目标和诊断基数五类新状态，而它仍不能表达“同文本两个 occurrence 只豁免一个”。

“只修 (b) + 加一个字段”如果仍然只记录不阻断，**不够**；但无需为此引入 payload 语法。建议本轮采用更小的防御性规则：

1. 按第 5 项做 versioned telemetry；新增 `citations_ignored_unscoped`，统计真实被裸 marker 跳过的 citation occurrence。
2. 对启用新协议的 round，沿用现有裸 marker，但要求它是独立行、只作用于紧邻下一行，且下一行必须恰有 1 个 citation candidate；0 个报 stale，>1 个报 `ignore-scope-ambiguous`。作者可把罕见的多引用句拆行，不需要新 escaping grammar。
3. 历史 round 保持旧语义；用明确的 round/protocol version 或不可变 legacy baseline 分流，禁止依赖 mtime。这样不改 4 份历史评审，也能拦住新 round 的大面积连带豁免。
4. 只有后续实测证明“拆行”形成显著负担，才另立精确语法；届时必须先定义可逆编码和 occurrence 作用域。

这比当前方案更贴合风险规模：它机械阻止一个 marker 跳过多条 citation，却不为 1 个已观测 collateral 引入一套尚未闭合的字符串协议。

## Decisions / deviations

判断口径：citation 按 v0.25.0 `pathish_citations` 会送入 `cited` 的 **occurrence**（不按唯一文本去重）计；无范围偏离。

## Open questions

- 新旧 round 的不可伪造/不可误判分流键是什么：round protocol version、项目 activation baseline，还是固定 legacy digest manifest？
- 历史 `decision.md` coverage 被定义为“当时版本的审计快照”，还是要求用未来 verifier 仍可逐字 replay？两者需要不同实现。

## Verdict

REWORK

核心阻断项是：精确语法对合法 citation 文本不可无歧义解析；unmatched/collateral 对 occurrence 的语义不闭合；`collateral` 定义自相矛盾且不能恢复作者意图；I5 漏掉 coverage schema 迁移；本规格没有真正拦截新裸 marker。

## Next recommendation

先撤下 §3.2/§3.3，重写 §3.1/§3.4/§3.5 为“版本化准确遥测 + 新 round 的独立行/单 citation 裸 marker 规则 + 历史 round grandfathering”，并重跑 73 份 corpus 核对 14→6/8 与 marker 数。下一轮验收至少加入：逗号文件名、多区间 locator、`-->` alias、大小写/尾斜杠/`./`、同行与跨行同名双 occurrence、3 名仅 1 名缺失、以及 v1/v2 coverage replay fixtures。

## Vendor output (parsed) _(preview 8000/266782 chars; complete parsed output is available through `hopper-dispatch --result T-071 --full`)_

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
session id: 019fa4b4-cacd-7371-a7f1-7866b812f80d
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

## T-071（`verify:ignore` 收窄规格 — 对抗审第 1 轮）

**Task-type**: `code-review-adversarial` · **只读评审，不改任何代码/规格**

**评审对象**：`docs/ignore-scoping-spec-20260728.md`（规格草案，实现尚未开始）。
**背景必读**：`docs/rule-ab-pilot-report-20260728.md` §5.1（起因，含一次自我更正）、
`harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py` 的
`pathish_citations`（当前实现，`IGNORE_MARKER` 在 :689 附近）。机械门当前版本 v0.25.0。

**评审语境**：这是**防御性机制的收窄**——目的是让豁免出口不能被无意间大面积滥用，
不是攻击工具。

**本轮六项**：

1. **§6 那 5 个靶子逐条回答**（规格作者自己列的，不得跳过）。其中第 4 个最重要：
   保留裸形式等于"只测不拦"——如果新评审作者继续用裸形式，collateral 只被记录、
   没被阻止。这个选择对不对？E1 约束（不得为迁移改历史评审）是否真的把这条路堵死了，
   还是存在第三条路（例如：裸形式在**新建**的 round 里判违规、在历史 round 里不判）？
2. **精确形式 `verify:ignore=<span>` 的绕过面**。逐条攻：
   - 能否构造一个 span，让「作者以为点名了、实际没命中」或反之？（清洗规则：`strip()`
     + 反斜杠转正斜杠；比较对象是清洗后文本）
   - `,` 作分隔符——span 文本里本身含 `,` 怎么办？（路径含逗号是合法的）
   - `-->` 出现在 span 文本里会怎样？
   - 大小写、尾斜杠、`./` 前缀这些等价写法，是否会让点名失效而作者不自知？
3. **`ignore-span-unmatched` 是否会误伤**。规格 §3.3 让未命中报违规。但 marker 服务
   「本行或下一行」两个作用域——若 span 只出现在其中一个，当前设计判命中。这里有没有
   缝？另：一个 marker 点名 3 个 span、只有 2 个存在，是报 1 条还是 3 条？规格没写。
4. **`citations_ignored_collateral` 的定义是否真的度量了它声称度量的东西**。它是否会
   把「本就该被豁免的」也算成 collateral？反过来，有没有真实的连带豁免会被它漏掉？
5. **零迁移是否真的成立**。规格 I5 声称 4 份含裸 marker 的既有评审「违规 kind 与
   detail 逐字节不变」。计数口径修正（§3.1）会改变 coverage 数值——这算不算破坏零
   迁移？该字段已进过历史 `decision.md` 的逐字记录，口径一改，历史记录与重跑结果就
   对不上了。规格没处理这一点，请判定它的严重性与处置方式。
6. **规格有没有解决错问题**。pilot 实测连带率 25%、绝对数 1 条；语料里 79% 的含引用
   行只有 1 条引用。**这个体量值得引入一套新语法吗？** 请独立判断：
   - 只修 (b)（计数口径）+ 加 collateral 字段、**完全不引入新语法**，是否已经足够？
   - 还是说新语法确实必要，理由是什么？
   给出你的取舍，并说明你会怎么做。这一问允许否决整个 §3.2/§3.3。

**验收**：逐项 PASS / FAIL / NOTE + 可复现证据。规格类问题须给出**具体的反例构造**
（例如"这样写的 span 会绕过"），不接受"可能存在风险"。产物落
`.hopper/handoffs/T-071-output.md`，含 `## Verdict`（`PASS` / `PASS_WITH_NOTE` /
`REWORK`）、`## Files touched`（应为 none）、以及独立成节的 `## 第 6 项：值不值得做`。

codex
我将按只读对抗审执行：先逐行核对规格、pilot §5.1 与当前 `pathish_citations` 实现，再用最小可复现实验验证边界案例，最后只写入指定评审产物。
exec
/bin/zsh -lc 'pwd && rg -n "T-071|''^#|''^##|''^###|verify:ignore|pathish_citations|IGNORE_MARKER|citations_ignored_collateral|ignore-span-unmatched" .hopper/handoffs/leader-tasklist.md docs/ignore-scoping-spec-20260728.md docs/rule-ab-pilot-report-20260728.md harnessloop/plugins/harnessloop/skills/harnessloop-loop/scripts/verify_protocol.py' in /Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
 succeeded in 0ms:
/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop
docs/ignore-scoping-spec-20260728.md:1:# `verify:ignore` 收窄 — 规格（2026-07-28）
docs/ignore-scoping-spec-20260728.md:7:## 1. 问题陈述（两个，不是一个）
docs/ignore-scoping-spec-20260728.md:9:### (a) marker 的作用域是「整行」，会连带豁免无关引用
docs/ignore-scoping-spec-20260728.md:14:if IGNORE_MARKER in line or (i > 0 and IGNORE_MARKER in lines[i - 1]):
docs/ignore-scoping-spec-20260728.md:24:### (b) `citations_ignored_explicit` 数的是 code span，不是引用——它在说谎
docs/ignore-scoping-spec-20260728.md:40:## 2. 语料实测（决定取舍的依据，不靠直觉）
docs/ignore-scoping-spec-20260728.md:57:## 3. 设计
docs/ignore-scoping-spec-20260728.md:62:### 3.1 修 (b)：计数口径改为「引用」
docs/ignore-scoping-spec-20260728.md:70:### 3.2 新增精确形式 `verify:ignore=<span>`
docs/ignore-scoping-spec-20260728.md:73:<!-- verify:ignore=hermes_agent.egg-info/ -->
docs/ignore-scoping-spec-20260728.md:74:<!-- verify:ignore=build/,hermes_agent.egg-info/ -->
docs/ignore-scoping-spec-20260728.md:83:### 3.3 精确形式的名字必须命中：`ignore-span-unmatched`
docs/ignore-scoping-spec-20260728.md:85:若某个被点名的 span 在其作用域内**不存在**，报违规 `ignore-span-unmatched`。
docs/ignore-scoping-spec-20260728.md:91:### 3.4 新增 coverage 字段 `citations_ignored_collateral`
docs/ignore-scoping-spec-20260728.md:102:### 3.5 裸形式保留
docs/ignore-scoping-spec-20260728.md:104:裸 `<!-- verify:ignore -->` 继续合法、行为不变。理由是**硬约束而非偏好**：历史评审
docs/ignore-scoping-spec-20260728.md:108:裸形式的代价现在由 `citations_ignored_collateral` 记账。新评审用精确形式即可让该值
docs/ignore-scoping-spec-20260728.md:111:### 3.6 显式不做
docs/ignore-scoping-spec-20260728.md:121:## 4. 验收（teeth）
docs/ignore-scoping-spec-20260728.md:128:| I2 | 精确 marker 点名一个该行不存在的 span → `ignore-span-unmatched` | 去掉命中检查 → 陈旧 marker 静默通过 → 红 |
docs/ignore-scoping-spec-20260728.md:130:| I4 | collateral：一行 3 条引用 + 裸 marker → `citations_ignored_collateral == 3`；换精确 marker 点名 1 条 → collateral 0 且另 2 条被检查 | 字段恒 0 → 红 |
docs/ignore-scoping-spec-20260728.md:132:| I6 | 无通配：精确 marker 里写 `*.md` / `build*` → **不**匹配任何 span（按字面比较），且因未命中报 `ignore-span-unmatched` | 引入任何模式匹配 → 红 |
docs/ignore-scoping-spec-20260728.md:135:## 5. 迁移与影响面
docs/ignore-scoping-spec-20260728.md:140:- **新增字段**：`citations_ignored_collateral` 进 coverage，须同步进 `decision.md`
docs/ignore-scoping-spec-20260728.md:142:- **B2b 预登记**：应对 `citations_ignored_collateral` 设阈（建议 `== 0`）。
docs/ignore-scoping-spec-20260728.md:144:## 6. 待对抗审的点（给评审者的靶子）
docs/rule-ab-pilot-report-20260728.md:1:# 真实评审 pilot — 结果报告（2026-07-28）
docs/rule-ab-pilot-report-20260728.md:8:## 结论
docs/rule-ab-pilot-report-20260728.md:14:- 另有 **2 个预算完全没有覆盖的维度**在 pilot 中暴

... [truncated, 258782 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 406562
- end_time: 2026-07-27T17:59:05.486Z
- log: see `T-071-output.log` for raw output
