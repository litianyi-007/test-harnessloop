---
phase: done
last_progress_at: "2026-07-28T02:34:04.666Z"
last_progress: Task completed successfully.
progress_seq: 10
last_stream_event: process_alive
last_update: "2026-07-28T02:33:56.848Z"
requested_selector: null
effective_selector: grok-4.5
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
end_time: "2026-07-28T02:34:04.664Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 247646
adapter_status: success
terminal_event_emitted: true
---
# T-078 — 批 2 规格 v3 对抗审第 3 轮

## Summary

v3 的层次收窄（强制结构 / 只记理由 / 异常消费）在方向上是对的：它诚实承认 agent 自签且控制输入时，机械门无法裁断动机，并把 B2a `Review:` 先例用对了。§0 对 T2 的档位订正有源码支持，不是又一次矫枉过正；§2.2 五条结构约束也真实堵上了 T-077 的倒指/环/空壳。但它仍不能进入实现：§4 作为唯一执行力来源在落地首日会因缺少 `Profile:` 字段而全量 skip；anomaly 触发条件在 lite 上有 false negative、在 `goal-achieved` 上有 false positive；acknowledgement 仍是无 schema 的 SKILL 散文；且 §3 把若干同文件可机械一致性检查误划到了“不能证明”。

## Files touched

none（只读评审；仅按任务协议写本交付物 `.hopper/handoffs/T-078-output.md`，未修改 `docs/loop-stop-record-spec-20260728.md`、harnessloop `b389eac`、`.harnessloop/` 语料或其他源码。）

## Acceptance verification (8/8)

### 1. §1 的收窄是否退得太多（允许判倒退）

**NOTE（不是原样复活，也不是已补齐）。收窄是进步，但“每个停止值都绿”在 exit 码层确实复活；§4 只部分补位，且补位本身在落地前是死的。**

T-076 原批评：任意 `stopped: <reason>` 均可 exit 0。v3 L9 明文要求：

> 任何合法 `stopped: <reason>` 均不判红（含 `unjustified-stop`）

因此机械门退出码层上，T-076 的“每个停止值都绿”**原样成立**。作者没有假装修好了这一层，而是改称执行力在 anomaly + acknowledgement。

§4 是否补上了？**仅对“契约允许自续却停了”这一子集**：

| 停止形态 | 机械门 | §4 anomaly |
|---|---|---|
| `stopped: user-interrupt` / 任意枚举 | 绿 | 不报（除非同时 positive+条件满足） |
| `stopped: unjustified-stop` | 绿（L9） | 不报（除非 positive+条件满足） |
| `stopped: open-handoff-blocking`（可自造） | 绿 | 不报（open handoff 使条件不满足） |
| positive + 健康 + 非 continued | 绿 | 应 +1（**唯一抓偏离的牙齿**） |
| `continued:` 假声明 | 五条结构约束可红 | 不涉及 |

所以：收窄**不是**把 v1 观测底座原样退回——`continued` 已有真实物证要求，`feedback-not-auto-continuable` 补了枚举缝。但“停了就绿”在 exit 码上确实回来了；整份规格的实践改变力几乎全部押在 §4 上。而 §4 在靶 4/5 下尚不可用，故**不能**说“anomaly + ack 已补上”。

**判定：收窄本身不是倒退；把执行力单点押在未落地的 §4 上是过度声称。** 详见独立节「收窄是进步还是倒退」。

### 2. §2.2 五条结构约束能否被绕过

**PASS（对已声明语义）/ FAIL（若目标是“实际自续”）。按 v3 自己的 `successor-observed` 语义，五条不可被廉价绕过；“建真 successor 再停”不是机械门绕过，而是语义诚实边界。**

T-077 三个反例在 v3 下的状态：

| T-077 反例 | v3 约束 | 结果 |
|---|---|---|
| `continued: 0009`（倒指） | (2) 严格前向 | 红 `successor-not-forward` |
| `0010→0010` / `A→B→A` | (2)+(3) 无环 | 红 |
| 仅 scope-lock 空壳 | (4) scope-lock **与** summary/decision 至少其一 | 红 |

**满足五条但“会话未自续”的构造**（规格自己提示的）：

```text
# 当前轮 0010 decision.md
- Loop continuation: continued: 0011

# 新建 rounds/0011/
scope-lock.md          # 最小合法
round-summary.md       # 可只写标题
# 无 decision.md → 约束 (5) 空真（if-exists）
```

五条全绿。agent 可立即结束会话。这**不算**绕过 v3 写下的判据——字段语义已定为 `successor-observed`，且诚实边界写明“不证明同一会话开启”。

**是否还算绕过“改变停等实践”的目的？** 算目的层绕过，但成本从“写一个词”升到“脚手架一整轮”。这与 B2a 一致：身份/存在可证，内容/动机不证。机械门无法区分“真的开了下一轮准备做”和“建了壳就跑”——**不可区分性已由语义承认，不是实现漏检。**

残余弱项（不推翻 PASS-on-stated-semantics）：

- 约束 (4) 未要求 summary/decision **非空实质内容**；空 `round-summary.md` 过关。
- 约束 (5) 仅在 successor 有 `decision.md` 时生效；选 summary 路径可跳过双向绑定。
- 不要求序号相邻（`0010 → 0012` 合法）。

这些是加固点，不是 T-077 级的确定性刷绿洞。

### 3. §0 订正裁定是否正确（地基；不得默认 T-077）

**PASS（订正正确；不是矫枉过正）。源码独立判定支持“T2 自动进入是档位差异”。但 §4 把订正误用成“anomaly 永不看 negative/neutral”，在 lite 上又矫枉了。**

四处原文（harnessloop `b389eaca1427af8e88248259e350d02b465434e4`，工作区无 diff）：

| 出处 | 原文要点 | 独立判定 |
|---|---|---|
| `loop/SKILL.md:517` | positive → next subgoal/task | 只定义 positive 路径，不谈档位 |
| `loop/SKILL.md:557` | negative/neutral → “propose **or** enter” T2 | **or** 保留 propose；非“必须 auto enter” |
| `harnessloop-continue/SKILL.md:33` | continue 被调用后 negative/neutral 仅允许 T2 集合 | 是**调用后动作上界**，`:31` 仍要匹配 control contract；非无条件 auto |
| `control-contract-profiles.md:15` | lite：positive **或** neg/neu 的 investigation/minimal-fix/rollback；standard：**仅 positive** | **直接证明档位差异**；若 T2 各档通用，lite 子句为废话 |

额外支持（T-077 已引、本次复核成立）：

- `control-contract-profiles.md:59-60`：runtime-recoverable / contract-insufficient 的 auto-recovery 是**显式例外表**，不能外推到“blocker=none 的 negative minimal-fix 在 standard 也 auto”。
- 本项目 `.harnessloop/state/control-contract.md:7` Feedback class 写 `feedback=positive`，与 standard 一致；round 0001（negative + minimal-fix + no human + safe）在 standard 下记 `feedback-not-auto-continuable` **合规**——v2 算偏离是错的，v3 订正对。

**结论：§0 地基正确。** 不是从“各档通用”跳到错误的“档位差异”，而是回到 profiles 表字面。

**订正的误用（§4，不推翻 §0）**：§4 触发条件写死 `Feedback: positive` 且注释“订正后不再包含 negative/neutral”。对 **standard** 正确；对 **lite** 错误——lite 明文允许 neg/neu remediation auto-continue，停了应报 anomaly。反例：

```markdown
# Profile: lite；健康 evidence/handoff/env
- Feedback: negative
- Blocker type: none
- Action type: minimal-fix
- Human confirmation required: no
- Safe without user input: yes
- Loop continuation: stopped: feedback-not-auto-continuable
```

按 profiles:15 应可 auto-continue；按 v3 §4 `loop_autocontinue_anomalies == 0`。这是 §4 的 false negative，不是 §0 订正本身错误。

另：§4 仍缺 `goal-achieved` 排除（T-077 已指出，v3 未收）。positive + 条件满足 + `stopped: goal-achieved` 会误报 anomaly，与 `loop/SKILL.md:556` “goal 未达成才 continue”冲突。

### 4. §4 acknowledgement 闭环是否可执行

**FAIL。当前写法仍是无人可机械强制的散文；可机械化的部分规格没有写成 schema。**

规格要求（§4.2）：

- `$harnessloop-status` / `$harnessloop-continue` 顶部显著显示未确认 anomaly
- 要求显式 acknowledgement，记入 `state/self-audit.md`
- 未确认数进 coverage，每轮累积

对照现源码：

| 组件 | 现状 | 缺口 |
|---|---|---|
| `harnessloop-status/SKILL.md` Output Contract | 固定字段列表，无 anomaly / ack | 散文改 skill 无测试守卫 |
| `harnessloop-continue/SKILL.md` Processing | 无 anomaly 读取、无 ack 门 | agent 可直接跳到业务 |
| `self-audit.md` / template | 无 `Anomaly acknowledgement` 槽位 | agent 可写假 ack 或根本不写 |
| `verify_protocol.py` coverage | 无 `loop_autocontinue_anomalies*` 键 | L10 的“计数 +1”尚未有机器落点定义之外的持久字段形状 |

**层次同构问题**：ack 写入 `self-audit.md` 仍由同一 agent 控制。一个执意忽略的 agent 可以：(a) 不读 status；(b) 写一行假 ack；(c) 从不调用 status/continue。规格自己也说 anomaly 不改退出码——于是“必须回应”没有与 exit 码/硬门绑定。

**可机械化却未写进规格的部分**（最低牙齿）：

1. `verify_protocol.py` coverage 固定键：`loop_autocontinue_anomalies`、`loop_autocontinue_anomalies_unacked`、`loop_anomaly_skipped_no_profile`（L10 已暗示后二者之一，但未给 schema）。
2. `meta/self-audit.md` 或 `state/current.md` 增加 canonical 块，例如：
   ```text
   ## Loop autocontinue anomalies
   - Unacked count: <int>
   - Last ack: <timestamp> | none
   - Last ack of anomaly ids: <list>
   ```
3. continue 的 Processing Contract **机械前置**：`unacked > 0` 时 decision 只能是 `needs-human`（或要求本次调用携带 ack 参数并落盘）——这才是“必须被消费”，而不是“顶部显著显示”。
4. 单测 fixture：造一条 anomaly → status 输出含字段 → 无 ack 时 continue 短路 → ack 后放行。

没有以上，§4.2 与 v2 的“coverage +1、exit 0、无人读取”**同构**，只是多了一句 skill 散文。

### 5. §5 canonical 字段是否让 §4 落地首日即死

**FAIL。会。现有模板、setup、本项目契约均无 `Profile:`；迁移 §6 不写 Profile；于是 anomaly 全 skip。**

证据：

```text
$ rg -n 'Profile:|Auto-continue on positive' harnessloop
# （无匹配）

$ rg -n 'Profile:' .harnessloop/state/control-contract.md
# NO Profile field

# control-contract-template.md 叶子仍是自由文本 Feedback class 等，无 Profile
# harnessloop-setup S4 选档后渲染的是 profiles 表散文，不写 Profile: 机器字段
```

v3 §5：

> 无 `Profile:` 字段时 §4 anomaly **不报**（不猜档位）——并在 coverage 记 `loop_anomaly_skipped_no_profile`

§6 迁移只回填 `Loop continuation: historical-unrecorded`，**不**给 `control-contract.md` 加 `Profile:` / 两个 Auto-continue boolean。

后果时间线：

1. 实现 L1–L12 + 跑迁移 → 14 轮有 continuation 字段。
2. 本项目（及一切既有项目）无 `Profile:` → 每次 gate `loop_anomaly_skipped_no_profile` 累加，anomaly 恒 0。
3. 实践中 “positive + 健康 + 停等” 仍零信号——§4 作为“唯一真正执行力”在首日是死的。
4. L10 的“anomaly 计数 +1”在本项目**无法用真实语料验收**，除非实现时额外改契约；但规格未把 Profile 回填列入迁移/启用前置。

**最小补丁（规格层）**：§6 迁移步骤 0 或并行步骤——由 setup 档案位或用户确认写入：

```text
- Profile: lite | standard | strict | custom
- Auto-continue on positive: yes | no
- Auto-continue on negative/neutral remediation: yes | no
```

无 Profile 时**不得**启用 §4 相关 coverage 的“健康”解读；或 `check_setup` 对缺 Profile 报 non-blocking TODO，且 L10 验收固定 fixture 必须先写 Profile。否则“skipped 可见”只是换了一种静默。

### 6. §6 preimage 摘要是否真的可行

**NOTE。可行且优于 v2，但“工具自产 baseline”在对抗迁移工具场景下仍是自证；应用 git preimage 更干净。**

v3 相对 T-077 finding 6 的进步：

- 明确 baseline 来源：迁移工具写入前算 sha256 → `migration-manifest.json`
- 核对：除唯一固定行外逐字节不变
- 顺序：迁移 → 核对 → 再启用 gate

这足以防：手滑改 Feedback、漏改、重复追加。对本项目当前 clean tree 也足够：

```text
$ git ls-files '.harnessloop/goals/*/rounds/*/decision.md' | wc -l
14
```

**残留“自己证明自己”**：

- 单次运行内，被篡改的迁移器可先改文件再把改后内容写入 manifest 当 preimage——自检仍绿。
- 规格未要求：clean worktree、记录 `baseline_commit`、或 `git show HEAD:path` 作为权威 preimage。

更强协议（仍廉价）：

1. 要求 worktree clean 或显式 `--allow-dirty`；
2. manifest 记录 `baseline_commit` + 每文件 `git_blob_sha` / `sha256(preimage)`；
3. CI 用 `git show <baseline>:<path>` 复算，而不仅信 manifest 内嵌摘要。

对“诚实迁移 + 防事故”目标，v3 已够用；对“对抗迁移器”不够。规格语境是前者 → **NOTE 而非 FAIL**，但应补一行 baseline_commit 要求以免实现时偷懒。

### 7. 本规格是否仍不足以改变实践；是否该放弃 harnessloop 方向

**NOTE on 改变实践 / PASS on 不应放弃。** v3 仍不足以单独改变 14/14 停等，但问题**应当**由 harnessloop 协议承担可审计层，不是整方向放弃。宿主/调度层是增强，不是替代。详见独立节「是否该由 harnessloop 解决」。

确定性残留绕过（实现 v3 字面后仍成立）：

1. **无 Profile（现状）**：anomaly 全 skip → 与 v1 一样无牙齿。
2. **有 Profile 后**：写 `stopped: user-interrupt` 或任意枚举 → L9 绿；仅当 Feedback 恰为 positive 且条件满足才 anomaly。把 Feedback 改成 neutral 可躲 standard 的 anomaly（对 standard 合法；对 lite 是靶 3 的洞）。
3. **自造 blocker**：建无关 open handoff → 条件不满足 → 无 anomaly；`stopped: open-handoff-blocking` 绿。
4. **脚手架 successor**：`continued: 0011` 过五条 → 无 anomaly，会话仍结束。
5. **假 ack**：self-audit 写已确认 → 散文闭环闭合，exit 仍 0。

与 v1/v2 对比：

| 版本 | 能抓住 | 抓不住 |
|---|---|---|
| v1 | 缺字段/乱枚举 | 一切实质 |
| v2 | 部分 + 宣称支撑 | 自造/自引用支撑、倒指、环 |
| v3 | 倒指/环/空壳 continued；枚举缝；**设计意图上的** anomaly | 理由真伪；无 Profile 时 anomaly；ack 散文；lite T2；goal-achieved FP |

v3 是迄今最诚实的版本，但仍是**观测 + 弱信号**，不是行为改变器。要“下一可观察时点确定抓住虚假停止/虚假继续”，至少还要靶 4/5 的机械闭环 + 靶 8 的廉价一致性——否则实践改变仍依赖人主动读 coverage。

### 8. 收窄边界是否划在正确位置

**FAIL。主线（结构 vs 动机）划对了，但两侧都有错位：若干廉价可证的一致性被丢到“只记”；至少一条“能证明”声明在空文件上过宽。**

**划对的部分**

- 动机类（为何停、是否真被用户打断、是否同会话）→ 不能证：正确。
- `continued` 的存在/前向/无环/最小文件集 → 能证：正确。
- 取消“支撑引用”强制（层 B 自引用）→ 正确（T-077 已击穿）。
- `unjustified-stop` 不判红 → 正确（判红只惩罚诚实标注）。

**被划到“不能证明”、其实廉价可证（同文件结构关系，不是动机）**

这些不需要外部真相，只读 `decision.md` 自身字段枚举：

| 停止理由 | 廉价一致性（应至少 NOTE/独立 coverage，不必升红） |
|---|---|
| `missing-human-input` | 与 `Human confirmation required: yes` **或** `Blocker type: human-decision-required` **或** `Safe without user input: no` 至少一项一致；若三者皆反（round 0001 形态却标此理由）→ 结构矛盾 |
| `write-safety-unconfirmed` | 与 `Blocker type: write-safety-required` 一致 |
| `missing-access-facts` | 与 `Blocker type: access-missing` 一致 |
| `open-handoff-blocking` | 同 goal 是否存在非 closed handoff（存在性，非“是否真阻塞”——存在性仍是结构） |
| `goal-achieved` | 与 goal 生命周期字段交叉（若 goal 仍无 canonical status 则降级；有则做） |
| `feedback-not-auto-continuable` | Feedback ∈ {negative, neutral, blocked} 或契约 boolean 为 no；**positive + 此理由** 为结构矛盾 |

反例（v3 L9 全绿，但同文件自相矛盾）：

```markdown
- Feedback: positive
- Blocker type: none
- Human confirmation required: no
- Safe without user input: yes
- Loop continuation: stopped: missing-human-input
```

这不是“动机审查”，是 **B2a 式字段身份一致性**。v3 用“支撑可被制造”一刀切掉它们，把婴儿和洗澡水一起倒了。制造 open handoff 仍能满足存在性——那只说明存在性检查的**力度有上限**，不说明“连同文件 enum 对齐都不要做”。

**被划到“能证明”、其实证不牢**

- 约束 (4) “summary 或 decision 存在”：空文件也“存在”，不证明是真轮次工作产物。
- 约束 (5) 双向绑定可选（无 decision 则跳过）：最小完整性声明过满。
- §4 “evidence health / open handoff / environment 均满足契约 Auto-Continue”：在无 canonical 机器字段时，仍可能滑回自由文本解析（§5 只加了 Profile 与两个 boolean，未把 evidence/handoff/env 收成 enum）。v3 对停止理由放弃解析，却对 anomaly 触发仍依赖这些谓词——触发侧同样面临 TH-0017 类假绿（environment `Pass/fail: pass` + TODO）。

**边界修正建议（保持收窄哲学）**

1. 强制层保持结构关系（可加：非空 summary/decision 最小标题+objective；successor decision 强制存在以启用双向绑定）。
2. 记录层保留自由理由；增加**可选** `reason-consistency` coverage（矛盾计数，不改 exit 码）——与 `unjustified-stop` 一样是信号不是红灯。
3. anomaly 触发谓词只使用 §5 canonical 字段 + decision 的 Feedback enum + continuation 字段；不解析中文散文。

## 收窄是进步还是倒退

**进步，附硬条件。**

进步的证据：

1. **诊断正确**：T-077“自签自造 blocker”是层次问题；继续加同层检查无效。v3 前言与 §1.1 把这一点写清楚了。
2. **先例对齐**：B2a `loop/SKILL.md:466` 只核存在与身份、不扫 prose——停止记录照此办理，避免 v2 过度声称。
3. **结构牙齿变硬**：L4–L7 针对倒指/环/空壳/前驱，是 v1/v2 没有的真约束。
4. **地基订正**：§0 与 profiles:15 一致；枚举补 `feedback-not-auto-continuable` 闭合 T-076 round 0001 缝。
5. **诚实标签**：L9 防止再把“停止理由判红”写成可实现的道德审判。

倒退风险的证据：

1. exit 码层“停止全绿”复活（L9）——若读者只看 gate exit，信号弱于 v2 的 unjustified 红灯。
2. 执行力单点 §4 在无 Profile、无 ack schema 时等于零——比 v2“至少有 anomaly 数字设计位置”好不了多少。
3. 误删廉价一致性（靶 8）使记录层比必要更哑。

**总判：收窄方向是进步；当前文本作为可实现规格仍不够。不是退回 v1，也不是可 ship 的完成态。**

## 是否该由 harnessloop 解决

**应当由 harnessloop 解决可审计层；不应当指望它单独解决“agent 不自续”的宿主生命周期问题。方向不应放弃。**

**依据——协议层该管的：**

- harnessloop 已经拥有 round/`decision.md`/control-contract/机械门/`status`/`continue` 语义。停止是否落痕、successor 是否可观察、契约是否允许自续，全是协议状态机问题。
- 把该问题丢给“纯宿主”会丢失与 Feedback、scope-lock、handoff、profile 的接合；宿主不知道 `feedback-not-auto-continuable` 与 lite T2 的差异。
- B2a 已证明：协议内“只入账、不判内容”的机制有工程价值且可维护。

**依据——协议层不该独扛的：**

- agent 是否在**同一次采样**里继续写下一轮，最终由宿主会话生命周期、用户是否再调 `$harnessloop-continue`、调度器是否自动 re-invoke 决定。SKILL 文本无法强制模型不结束 turn。
- `user-interrupt` 的事件 ID 若宿主不提供，协议无法变出真相。

**分层处方（保留方向，划清边界）：**

| 层 | 职责 |
|---|---|
| harnessloop 协议 | continuation 字段、结构约束、Profile canonical、anomaly 计数、status/continue 消费门、coverage |
| 宿主/调度（可选增强） | 会话未达 goal 且 anomaly unacked 时自动再拉起；提供 user-message event id |
| 人 | 读 unjustified/一致性信号；checkpoint 预算与业务决策 |

放弃整个方向会丢掉已收敛的结构约束与枚举缝修复，回到 14/14 零痕迹。正确结论是：**收窄后的协议层值得做完（修好靶 3§4/4/5/8），再视需要加宿主钩子——而不是 checkpoint 后弃坑。**

## Decisions / deviations

- 评审基线：工作区 `docs/loop-stop-record-spec-20260728.md`（v3）+ harnessloop `b389eaca1427af8e88248259e350d02b465434e4`（v0.26.0，相对该 commit 无 diff）。
- `Acceptance verification (8/8)` 表示八个靶子均已独立作答，不表示八项通过。
- 假设“绿灯”= 机械门 exit 0 / 无 violation；按 L10 anomaly 不改退出码，故 anomaly 单独计为观测信号。
- 未跑破坏性 fixture；反例均可由规格判据 + 现有路径/源码文本确定。
- 不因收敛守卫放水：第 3 轮仍判 REWORK。

## Open questions

- Profile 回填的权威来源：用户确认 / setup 历史 / 从自由文本启发式（规格已禁猜测）？实现前必须选一个并写入 §6。
- anomaly unacked 时 continue 是硬拦（needs-human）还是仅 warning？硬拦才配得上“必须消费”；warning 则与 v2 同构。
- `reason-consistency` 矛盾是只进 coverage 还是升 violation？建议只 coverage，以保持 L9 哲学。
- 宿主能否提供 session/message event id？不能则 `user-interrupt` 永远只是声明。

## Verdict

REWORK

## Next recommendation

不要进入实现，也不要因为收敛守卫而“改个措辞算 v4 硬过”。向用户 checkpoint 时建议带如下**最小可 ship 补丁清单**（仍叫 v3.1 或 checkpoint 修订，不必重开哲学）：

1. **§6 迁移补 Profile 三字段**（或启用 gate 的硬前置）；本项目先写入 `Profile: standard` + 两个 Auto-continue boolean。无此不做 anomaly。
2. **§4 触发修正**：按 Profile 分支——lite 包含 neg/neu + remediation action types；各档排除 `goal-achieved`；blocked+runtime-recoverable 未进恢复轮另计（可第二刀）。
3. **§4.2 机械化**：coverage 键 + self-audit/current canonical ack 块 + continue 在 unacked>0 时 `needs-human`；skill 散文降为说明。
4. **§3 边界微移**：增加同文件 reason↔Feedback/Blocker/Human/Safe 一致性为 **coverage 信号**（不判红），收回靶 8 的误伤。
5. **§2.2 加固（小）**：successor 强制 `decision.md`（启用双向绑定）或要求 summary 含非空 `Objective:`；manifest 增加 `baseline_commit`。

checkpoint 问用户的决策点只有两个：**(A)** 接受上述最小补丁后进入实现；**(B)** 降级为“纯观测字段 + continued 结构约束、砍掉 anomaly 执行力声称”。不要在无用户裁定时写 v4 大改。

## 源码核对摘录

```text
$ git -C harnessloop rev-parse HEAD
b389eaca1427af8e88248259e350d02b465434e4

$ git -C harnessloop status --short
# （空）

# profiles Auto-Continue Feedback class
# harnessloop/.../control-contract-profiles.md:15
# lite: positive; or negative/neutral when ... investigation|minimal fix|rollback
# standard: positive

# B2a 边界
# loop/SKILL.md:466 — Review accounts for existence and identity only; never scans prose

# 本项目契约无 Profile
$ rg -n 'Profile:' .harnessloop/state/control-contract.md
# （无匹配）

# round 0001 合规停止形态（standard）
# Feedback: negative; Blocker: none; Action: minimal-fix; Human: no; Safe: yes
```

## Vendor output (parsed)

```
I'll execute the adversarial review myself: read the v3 spec, prior REWORK findings, and harnessloop source, then write the T-078 deliverable.Prior reviews and the v3 spec are in hand. Next I’ll verify the profile/T2 claims and structure constraints against harnessloop source.I have enough source evidence to judge all eight targets. Drafting the adversarial review deliverable.## T-078 complete

Adversarial review of `docs/loop-stop-record-spec-20260728.md` **v3** is written to `.hopper/handoffs/T-078-output.md`.

### Verdict: **REWORK**

(Third consecutive REWORK → convergence guard: main session should checkpoint the user, not write v4 casually.)

### Target scores (8/8 answered)

| # | Target | Result |
|---|--------|--------|
| 1 | Narrowing too far? | **NOTE** — progress, not pure regression; “all stops green” returns at exit-code layer; §4 only partly covers it and is not shippable yet |
| 2 | §2.2 five constraints bypassable? | **PASS** on stated `successor-observed` semantics; building a real successor is not a mechanical bypass |
| 3 | §0 T2 profile ruling? | **PASS** — source supports profile difference (not overcorrection); §4 misapplies it (lite T2 false negative) |
| 4 | Acknowledgement loop executable? | **FAIL** — still SKILL prose; no schema / continue hard gate |
| 5 | Profile fields kill §4 day-1? | **FAIL** — template/setup/this project have no `Profile:`; migration does not add it → anomaly always skipped |
| 6 | Preimage digest self-proving? | **NOTE** — better than v2; prefer `baseline_commit` + git preimage |
| 7 | Abandon harnessloop direction? | **No** — keep protocol audit layer; host/scheduler is complement, not substitute |
| 8 | Proveable/unproveable boundary? | **FAIL** — same-file reason↔blocker consistency is cheap and was wrongly dropped |

### Independent sections

- **收窄是进步还是倒退** — progress with hard caveats  
- **是否该由 harnessloop 解决** — yes for audit layer; not alone for session lifecycle  

### Files touched

**none** (review-only; only the handoff output was written)

### Minimal ship checklist for checkpoint

1. Migrate/add `Profile:` + two auto-continue booleans before enabling §4  
2. Fix §4 triggers (lite T2; exclude `goal-achieved`)  
3. Mechanize ack (coverage keys + continue `needs-human` when unacked)  
4. Optional `reason-consistency` coverage (not red)  
5. Small §2.2 harden + `baseline_commit`
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 247646
- end_time: 2026-07-28T02:34:04.664Z
- log: see `T-078-output.log` for raw output
