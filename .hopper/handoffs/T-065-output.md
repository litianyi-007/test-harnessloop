---
phase: done
last_progress_at: "2026-07-26T18:46:43.609Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-07-26T18:46:43.608Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 347226
adapter_status: success
---
# T-065 · harnessloop v0.16.0 / TH-0008 终局确认审（异构视角 grok）

## Summary

对 `harnessloop` commit `77543d6`（v0.16.0）做了只读终局确认：这不是又一轮"修 bug 直到后缀宇宙刚好正确"，而是对**用户裁定的降级方案**做闭环验收。复跑了 T-064 的 MUST-FIX B/C 反例、全套伪唯一/逃逸场景、hint 精度与计数、本项目零迁移、以及 handoffs 语料误报率归因。结论：后缀回退**不再能把任何不可解析引用判为 pass**——假阴性面就判定路径而言归零；B/C 真 bug 已闭合且无残留预折叠；提示措辞与覆盖计数诚实；零迁移成立；误报率抬升应记为**降级的正确代价**（不是语料增长伪装）。TH-0008 应按 **fixed-by-demotion / 降级收口** 结案，不可写成"后缀问题已解决"。

## Files touched

- `.hopper/handoffs/T-065-output.md`：本只读确认审交付物。
- 被评审的 `harnessloop` 源码：none。
- 临时 fixture：全部建于 `/tmp/t065*` / `/tmp/t065b*` / `/tmp/t065-proot-*`，结束时已删除；`git -C harnessloop status --short` 为空；`HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py` 175 checks 全绿。

## Acceptance verification (5/5)

### 1. 假阴性面是否真归零 — **是（判定路径）**

评审对象：`77543d6` 的 `verify_round` 在 explicit base（含 locator 剥离）失败后**无条件** `dangling-citation`；`suffix_hint_target` 只拼 detail 提示 + `citations_suffix_hinted`，从不把 `resolved` 置真（`verify_protocol.py:1036-1060`）。

| 场景 | 期望 | 实测 |
|------|------|------|
| ignored 伪唯一（tracked `src/pkg/real.md` + ignored `scratch/pkg/real.md`，引 `pkg/real.md`） | dangling（可带 hint） | dangling + hint@`src/pkg/real.md`；`citations_suffix_hinted=1`。**不再 pass**（T-064 MUST-FIX A 从判定问题降为 hint 精度问题） |
| untracked 伪唯一（tracked + untracked 同后缀） | dangling，多命中无 hint | dangling；hits=2；`citations_suffix_hinted=0` |
| tracked-then-deleted 幽灵 | ghost 不进索引；真实项唯一 → dangling+hint | `lexists` 过滤后 hits=`[src/pkg/real.md]`；dangling+hint；deleted 仍在 `git ls-files --deleted` |
| 断链 symlink | dangling，无"存在"hint | dangling；`lexists=True` 仍入索引，但 match-time `_exists_as` 失败 → 无 hint |
| 尾斜杠文件 `pkg/real.md/` / `src/pkg/real.md/` | dangling | 两条均 dangling（dir semantics） |
| 非 git 剪枝（`build/` 在 NOISE） | 仍 dangling（后缀永不 resolve） | dangling；hint 可因剪枝而伪唯一（hint 精度残留，非 FN） |
| 多级 symlink 逃逸 `hop1→hop2→outside` | resolve None + dangling | `_resolve_in_project=None`；dangling |
| `link/../escape.md`（项目内 symlink 指向外 + 同名 coincidental） | dangling | helper=None；raw 解析到 `/private/tmp/.../outside/escape.md`；端到端 dangling |
| `.gitmodules path=smod/../mod` | submodule root 拒绝 + 引用 dangling | `submodule_roots=[]`；`pkg/modghost.md` dangling |
| project root 在 `/tmp`（macOS `/tmp→/private/tmp`） | 正常 inside 引用仍可 resolve | contained=True；`pkg/x.md` 不 dangling |
| 经项目外中转最终回项目内 | 应接受 | `_resolve_in_project` 接受，canonical 落在项目内 |

**有没有任何路径仍能让一个"不可解析"的引用 pass？**

- **经由后缀回退：没有。** 代码路径上 suffix 已退出 pass/fail；所有"伪唯一"系列在端到端上均为 dangling。
- **经由显式 base 的已知宿主残留（已登记，非本轮回归）**：本机 macOS 上错误大小写 `case/file.md` 对 `Case/File.md` 的 `Path.exists()` 为 True → 0 dangling。docstring `:221-231` 已写明 case 宿主依赖。这不是后缀回退制造的 FN，也不被降级方案声称关闭。
- **语义碰撞**（`mistyped/config.yaml` 碰巧唯一命中 `vendor/mistyped/config.yaml`）：**dangling + 可能错误指向的 hint**，不再 pass（`:232-248`）。

结论：就 T-062→T-064 一直在追的"后缀唯一回退假阴性面"而言，**归零成立**。

### 2. MUST-FIX B/C 是否真闭合 — **是**

#### MUST-FIX C（`symlink_dotdot_normpath_order`）

T-064 原反例复现：

```text
raw_resolves_to /private/tmp/.../dotdot-out/escape.md
raw_contained False
helper_returns None
end_to_end dangling=["link/../escape.md"]
```

mutation control（故意复现旧顺序）：

```text
old_cand = Path(os.path.normpath(str(p/"link/../escape.md")))  # → .../escape.md
old_contained True   # 会错收 coincidental 项目内文件
new = _resolve_in_project(...) → None
```

`.gitmodules path=smod/../mod`：`submodule_roots=[]`（修前会接纳逃逸 base 导致假绿）。

**残留预折叠审计**：生产代码中 `os.path.normpath` 仅出现于

1. docstring 叙述（说明"故意不做"）；
2. `norm()` 辅助函数（`:338`，对**已经** canonical 的两侧做 `normcase/normpath` 字符串比较，**不是** join 前预折叠）；
3. 无 `candidate = Path(os.path.normpath(str(base / cited)))` / `Path(os.path.normpath(str(project / rel)))`。

`_resolve_in_project` 现为 `candidate = base / cited`（`:933`）；`submodule_roots` 现为 `candidate = project / rel`（`:609`）。**无第二处同类预折叠残留。**

#### MUST-FIX B（`stale_tracked_ghost_ambiguity`）

```text
git ls-files --deleted = gone/pkg/real.md
index hits after lexists filter = [src/pkg/real.md]
suffix unique → hint only; citation still dangling
```

`os.path.lexists` 过滤在 `_git_tracked_index` 出口（`:745-751`）；断链 symlink 仍保留（1d 实测 `lexists=True` 入索引、match-time 无 hint）——不回归 `broken_symlink` 守卫。

官方守卫：`HARNESSLOOP_SKIP_CLAUDE=1 python3 scripts/validate.py` → **175 ok / 0 fail**，含 T-064 B/C/ demotion 全套 mutation control。

### 3. 提示是否准确无误导 — **是**

| 条件 | 期望 | 实测 |
|------|------|------|
| 唯一后缀命中 | 给 hint，路径正确 | `harnessloop-setup/SKILL.md` → `plugins/harnessloop/skills/harnessloop-setup/SKILL.md`；yaml 同理 |
| 多义 | 不给 hint | `dup/file.md`（a/ 与 b/）无 "unique suffix" |
| 零命中 | 不给 hint | `no/such/path.md` 纯 dangling |
| 本就可解析 | 不进 dangling | `only/one.md` 不在 dangling 列表 |
| 计数一致 | `citations_suffix_hinted` == 实际 hint 条数 | fixture：cov=2 / actual=2 |

措辞模板（`:1049-1052`）：

> `— a unique suffix match exists at <rel>; if that is the intended file, cite it by a resolvable path or mark the line <!-- verify:ignore -->`

- 用 **"if that is the intended file"**（条件语气），不是 "is the file" / "must be"。
- 主句仍是 **`which does not exist`** → 评审者读到的首义是失败，hint 是附注。
- 给出两条合法出口：写成可解析路径，或 `verify:ignore`——不诱导"看见 hint 就当通过"。

### 4. 零迁移与误报归因是否诚实 — **大体成立；+96 与本机复测 +91 有小差，归因方向正确**

#### 零迁移（本机实测，与 commit message 一致）

```text
$ python3 harnessloop/.../verify_protocol.py --project .
Harnessloop verify: .../test-harnessloop
passed, but not a clean sweep: 9 of 14 round(s) had nothing under evidence/ or reviews/ ...
coverage: rounds=14 rule_a_files=8 rule_b_files=3 citations=12
          citations_exempt_external=0 citations_suffix_hinted=0 zero_inspected=9
EXIT:0
```

- **14 轮 / 12 条引用 / `citations_suffix_hinted=0` / 0 dangling violation**：属实。
- 本项目协议账本**从未依赖**后缀回退消解；降级无需迁移。
- `reviews/` 中 3 处 `verify:ignore` 均在 setup-wizard rounds 0001–0003，是 TH-0008 **原始手工止血**（issue 正文已记），**不是** v0.16.0 降级后新加。

#### 误报率 28.7%→37.8%（+96，87 带 hint）

对 `.hopper/handoffs/**/*.md`（当前 66 文件）用同一套 `pathish_citations` + 项目根/`.harnessloop`/submodule bases，分别加载 `77543d6^`（v0.15.0）与 `77543d6`（v0.16.0）复测：

```text
v0.15: cites=1003 dang=289 resolved=714 (of which suffix_resolved=87) rate=28.8%
v0.16: cites=1003 dang=380 resolved=623 (suffix_resolved=0) hinted=87 rate=37.9%
demoted_from_suffix_resolve: 87 (全部 87 带 hint)
delta_dang = +91
```

| 声称 | 本机复测 | 判定 |
|------|----------|------|
| 28.7% → 37.8% | 28.8% → 37.9% | 一致（±0.1pp，语料/计口径可解释） |
| 87 条带唯一后缀提示 | 87/87 demoted 全带 hint | **完全一致** |
| +96 条 | +91 条 | **方向一致，数值差 5** |

**归因诚实性**：

1. **主体是降级代价，不是语料增长**：同一 1003 条引用、同一文件集上，仅换实现就 +91 dangling；其中 **87 条是"曾经靠后缀 resolve、现在改 dangling 并带 hint"**——与"87/96(91%) 带提示"的结构一致。
2. **+91 中多出的 ~4 条**更可能来自 MUST-FIX C 的真实 containment 收紧（以前被 `normpath` 预折叠错收的引用），应记为 **bugfix 收益（少假绿）**，不宜全部算进"降级代价"。commit message 写 +96 全部为降级代价，**略粗**，但不构成误导级不诚实——数量级与"绝大多数带 hint"均成立。
3. **不可与语料增长混谈**：本复测 cites 两侧相同（1003），排除了"文件变多所以率变高"的混淆。

### 5. 措辞诚实性 — **docstring 诚实；结案应写降级收口，不可写 fixed**

docstring（`:93-136, 221-254`）关键句：

- ✅ **"the false-negative surface this fallback can create is now exactly zero"**——限定在 *this fallback*，不是"Rule B 再无假阴性"。
- ✅ 明确 **does *not* mean** "genuinely exists" 问题已 solved；索引边界问题只影响 **hint 是否/是否准确**。
- ✅ **不**写"后缀问题已解决"。
- ✅ 两条固有残留仍登记：
  - 大小写宿主依赖（`:221-231`；本机 5e 复验 wrong-case 仍可 pass）。
  - 后缀语义碰撞 / 错误 hint 指向（`:232-248`；5f 仍 dangling+hint@`vendor/...`）。
- ✅ MUST-FIX A（ignored 伪唯一 hint）被明确降级为 **hint-accuracy residual**（`:249-254`）。

对照 TH-0008 原文 Expected Behavior（"唯一后缀命中则豁免、不报 dangling"）：该期望已被用户裁定**主动放弃**。因此：

| 结案措辞 | 是否可用 | 理由 |
|----------|----------|------|
| `fixed` / "后缀问题已解决" | **否** | 原文期望的"后缀 resolve 豁免"未实现；误报率反而上升 |
| `wontfix` | 过贬 | 做了真修复（B/C）+ 有意识的风险面收缩 |
| **`fixed-by-demotion` / 降级收口** | **是（推荐）** | 判定路径假阴性面归零；B/C 真 bug 闭合；原方案目标以 demotion 关闭；残留只在 hint 精度与宿主 case |

**建议的 TH-0008 Resolution 措辞（可直接粘贴）**：

> **Resolution status: fixed-by-demotion（降级收口，v0.16.0 / `77543d6`）**  
> 三轮对抗审（T-062→T-064）证明：后缀唯一回退的"唯一性宇宙"无法稳定等于"评审者可能指的真实文件"，边界每扩一次，同形伪唯一跟着换一次。用户裁定停止扩边界，**将后缀匹配从 pass/fail 降级为 display-only hint**（`citations_suffix_hinted`）。  
> **关闭了什么**：后缀回退可制造的判定假阴性面 = 0；T-064 MUST-FIX B（stale tracked ghost）与 C（normpath 预折叠在 containment 前）作为真 bug 已修。  
> **没有关闭什么（且诚实登记）**：(1) 后缀语义碰撞导致的错误 hint；(2) 存在性检查的宿主大小写依赖；(3) ignored/剪枝等边界上的 hint 精度问题——它们只影响提示，不影响判定。  
> **代价**：handoffs 语料 Rule B 误报率约 28.7%→37.8%，新增 dangling 中绝大多数带唯一后缀提示，可读可诊断；本项目 14 轮 12 引用零迁移。  
> **不可写作**："TH-0008 fixed / 后缀回退已修好"。

## Decisions / deviations

- Verdict 使用任务专用枚举 `CONFIRMABLE`（非通用 PASS）。
- 假阴性归零的口径：**仅就后缀回退这条判定路径**；宿主 case 残留单独登记，不计入"未归零"。
- 误报 +96 vs 本机 +91：不因此改判 MUST-FIX；在 §4 注明归因可再精细化，但不否定降级代价主体。
- 忽略跨仓/全局 skill；未改 harnessloop 工作区。

## Open questions

none（可选后续、非阻塞：把 commit message 的 +96 改成"约 +90–96，其中 87 为纯 demotion、余量为 C 类 containment 收紧"以更精确——属于文案打磨，不是代码缺陷。）

## Verdict

**CONFIRMABLE**

TH-0008 可按上文 **fixed-by-demotion / 降级收口** 结案；不可写 fixed。

## Next recommendation

1. 在 `.harnessloop/meta/evolution-issues/0008-*.md` 的 Resolution 写入上述结案措辞，status 从 `open` → `fixed-by-demotion`（或项目惯用等价字段），Upstream change 指向 `harnessloop@77543d6` / v0.16.0。  
2. 同步进化计划 B1 状态：TH-0008 以降级收口关闭后，**误报率并未降到个位数**（反升至 ~38%）——B2（强制 reviews/ 入账）的硬前置若仍写"误报率降到个位数"，应显式改写为新门槛（例如：假阴性面归零 + 提示可诊断 + 接受 ~30–40% 片段误报并靠 `verify:ignore`/完整路径纪律），避免计划文本与现实脱节。  
3. 无需再开 T-066 类"继续扩唯一性宇宙"的对抗轮；若再动 Rule B，应是**引用书写规范/显式 base 扩展**，而不是复活后缀 resolve。

## Evidence anchors（file:line）

| 主题 | 位置 |
|------|------|
| 降级决策与 FN=0 声明 | `verify_protocol.py:93-136` |
| 固有残留（case / 语义碰撞 / ignored hint） | `:221-254` |
| lexists 过滤幽灵（MUST-FIX B） | `:745-751`, docstring `:651-665` |
| 无 normpath 预折叠（MUST-FIX C） | `_resolve_in_project:933-936`, `submodule_roots:609-612` |
| hint-only 接线 + 计数 | `verify_round:1036-1060`, `_empty_coverage:1104` |
| SKILL coverage 字段 | `SKILL.md` Mechanical Gate Boundary `citations_suffix_hinted` |
| 版本 | `package.json` / `plugin.json` / `marketplace.json` → `0.16.0` |
| 官方守卫 | `scripts/validate.py` T-064 block ~1577–1822；全量 175 ok |

---

**评审对象确认**：`git -C harnessloop rev-parse HEAD` = `77543d6f8023cb691c519d731aa75d0410086b2a`。  
**Read-only 声明**：未修改 submodule；临时目录已清理。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll execute T-065 as a read-only acceptance review of harnessloop `77543d6` (v0.16.0): first load the chain background and the commit, then run the five checks and write `.hopper/handoffs/T-065-output.md`.Next I'll load the v0.16.0 implementation and re-run the escape/counterexample suite from T-064.I'll run a comprehensive end-to-end verification script covering all five criteria.Sections 1–2 passed. Finishing hint accuracy, zero-migration, and validate.py.Next I'll re-check the false-positive rate attribution claim and any remaining residual wording.I'll remeasure the handoffs corpus FP rate for v0.15.0 vs v0.16.0 to check the +96 / 87-hint attribution.Cleaning leftover temp fixtures from the interrupted first run, then writing the deliverable.Writing the final T-065 acceptance report.## T-065 完成\n\n交付物：`.hopper/handoffs/T-065-output.md`\n\n### Verdict: **CONFIRMABLE**\n\n对 `harnessloop@77543d6`（v0.16.0）五项终局确认均通过：\n\n| # | 结论 |\n|---|------|\n| 1 假阴性面 | 后缀回退**不再能 resolve**；ignored/untracked/幽灵/断链/尾斜杠/剪枝/多级 symlink/`link/..`/`.gitmodules ../` 等一律 dangling |\n| 2 MUST-FIX B/C | B：`lexists` 滤幽灵；C：无 join 前 normpath 预折叠残留；validate **175/175** |\n| 3 提示 | 唯一才 hint、路径正确、多义/零命中无 hint；`citations_suffix_hinted` 与条数一致；措辞为 \"if that is the intended file\" |\n| 4 零迁移/归因 | 本项目 14 轮 12 引用 `hinted=0`；handoffs 复测 28.8%→37.9%，**87 条 demotion 全带 hint**（声称 +96 vs 本机 +91，方向正确） |\n| 5 措辞 | docstring 写的是「假阴性面归零」而非「后缀已解决」；两条固有残留仍登记 |\n\n### 建议结案措辞\n\n**`fixed-by-demotion` / 降级收口** — 不可写 `fixed` /「后缀问题已解决」。",
  "stopReason": "EndTurn",
  "sessionId": "019f9fba-f99c-7f30-a061-b227d8b9a5c9",
  "requestId": "1186ee85-bb2d-4367-98ab-163402ab7490",
  "thought": "The user wants me to perform a code-review-acceptance task (T-065) for harnessloop v0.16.0. This is a read-only acceptance review. Let me understand what I need to do:\nGood, I found the relevant files. Let me read the chain outputs (especially T-064 which is most relevant), the evolution issue, and the actual code changes.I have a good understanding of the chain. Now I need to thoroughly verify the five acceptance criteria against the actual code in v0.16.0. Let me:\nLet me read more critical code sections and write a comprehensive verification script that tests all the scenarios.Now I need to run a comprehensive verification script covering all 5 acceptance criteria. Let me write and execute a thorough test script.The command timed out - likely because verify_project on the real project is slow due to submodules. Let me check the output.Good progress - sections 1 and 2 all passed. Failed on section 3 because I forgot to mkdir agents. Let me continue with remaining tests, and also run validate.py and real project verification more car...Let me wait for this to complete - validate.py and real project verify can take a while.Excellent! All tests passed. Now I need to verify the FP rate attribution claim (28.7% → 37.8%, +96, 87 with hints). Let me search for how they computed this and re-verify if possible.I need to independently remeasure the FP rate claim 28.7% → 37.8% (+96, 87 with hints). This was measured on `.hopper/handoffs` corpus. Let me try to re-run that simulation using v0.15.0 vs v0.16.0.Interesting - my measurement shows:**Summary**: I reviewed the harnessloop v0.16.0 commit 77543d6 against the five acceptance criteria for TH-0008 demotion. The changes appear to have successfully closed the false-negative surface by ensuring all pseudo-unique/escape scenarios now dangle, and the MUST-FIX B/C cases (link/../escape.md and .gitmodules path=smod/../mod) are resolved via the new containment pre-fold normpath logic. Prompt wording is accurate and non-misleading, zero migration verified, and residual wording in the docstring accurately reflects the demotion.There are leftover /tmp/t065 directories from the first run that crashed before cleanup. I should clean those up since the task says temporary mutations must be restored.175 checks match the commit message. Now write T-065-output.md comprehensively in Chinese.I should also update the hopper task metadata if needed - looking at T-065-output.md structure from T-064, they have a frontmatter with status. The hopper system may update this automatically. The tas...Task complete. Provide a brief summary for the completion.",
  "usage": {
    "input_tokens": 116187,
    "cache_read_input_tokens": 1144960,
    "output_tokens": 20477,
    "reasoning_tokens": 2848,
    "total_tokens": 1281624
  },
  "num_turns": 15,
  "total_cost_usd": 0.698724,
  "total_cost_usd_ticks": 6987240000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 116187,
      "outputTokens": 20477,
      "cacheReadInputTokens": 1144960,
      "modelCalls": 15,
      "costUSD": 0.698724
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 347226
- end_time: 2026-07-26T18:46:43.608Z
- log: see `T-065-output.log` for raw output
