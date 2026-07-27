---
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
phase: done
end_time: "2026-07-27T18:11:24.265Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 443399
adapter_status: success
last_progress_at: "2026-07-27T18:11:24.268Z"
last_progress: Task completed successfully.
progress_seq: 16
terminal_event_emitted: true
---
# T-072 — `verify:ignore` 收窄规格 v2 对抗审（第 2 轮）

## Summary

已对 `docs/ignore-scoping-spec-20260728.md`（v2，commit `ed7b29c`）做只读对抗审，并对照 T-071、`verify_protocol.py` 的 `pathish_citations`/`IGNORE_MARKER`，以及当前语料里全部 `<!-- verify:ignore -->` 出现点。v2 正确撤回了 v1 精确语法，并把核心收敛成「目标行恰好 1 条引用」不变量，方向对；但摘要算法未写死、J11 与 §5.1 直接矛盾、J10 与 §5.2 定义打架、行内 marker 的子串检测会把「文档里提到 marker」当成真豁免，且 legacy 名单缺少冻结策略。结论 **REWORK**。

## Files touched

none（只读评审；本交付文件不计入被评审范围）

## Acceptance verification (5/5)

本任务五块验收要求均已作答；逐项结论如下。

### 1. §9 的 6 个靶子 — 混合（总评 FAIL：有阻断项）

#### 1.1 靶子 1：`恰好 1 条` 是否消灭 occurrence 歧义 — PASS_WITH_NOTE

**同类歧义（同一目标行、同一 cleaned 文本出现两次、只想豁免一次）被关死。**
目标行允许的引用候选数是 0/1/≥2 三态；两次 occurrence 必然 ≥2 → `ignore-scope-ambiguous`，两条都不豁免（J3）。不需要 v1 的文本点名。

**但歧义被推到别处（NOTE，非否决）：**

| 推到哪里 | 具体构造 | 结果 |
|---|---|---|
| 「引用候选」未定义 | 规格只说「引用」，未钉死是否 = 完整 classifier 之后会进 `cited` 的 occurrence，还是 `CODE_SPAN` / 形状过滤前集合 | 实现可各写各的，J3/J4 基数会漂 |
| 物理行 ≠ 语义句 | exclusive 只覆盖「下一物理行」；软换行把一句拆成两行时，第二行的真实引用不受保护，第一行 0 引用则 stale | fail-closed，但作者心智模型会错 |
| 文档性 marker 文本 | 见靶子 3 / §3 攻击：子串命中 + 恰 1 条引用 → 错误地「成功豁免」 | 数值不变量成立，意图不变量不成立 |

**判定：PASS_WITH_NOTE** — 对 T-071 指出的「同文本双 occurrence」类问题成立；须把「引用候选 = `pathish_citations` 在去掉 marker 子串后会进入 `cited` 的 occurrence（不去重）」写死。

#### 1.2 靶子 2：摘要按什么口径 — FAIL（规格缺口，必须写死）

规格只写 `"sha256": "<该文件当前内容摘要>"`，**完全没写**：

- 哈希输入是**原始字节**还是解码后的文本；
- 换行是否规范化（LF / CRLF / 末尾 newline）；
- 路径相对谁（`--project` 根？cwd？git toplevel？）；
- 路径是否经 `posix` 规范化、是否拒绝 `..` / 绝对路径 / 前导 `./`；
- 是否 `follow_symlinks`；
- 大小写：字符串键是否 case-sensitive（macOS 默认大小写不敏感 FS 上已多次咬过本项目）。

**可复现的口径分裂（同一逻辑文件三种摘要）：**

```text
sha256(b"hello\n")     = 5891b5b5…   # LF
sha256(b"hello\r\n")   = cd2eca35…   # CRLF
sha256(b"hello")       = 2cf24dba…   # 无尾 NL
```

**本审给出的应写死口径（直接可粘进 §4）：**

1. **path**：相对 `verify_protocol.py --project` 根的 project-relative POSIX 路径；写入前必须 `PurePosixPath(path).as_posix()`，禁止绝对路径、禁止 `..` 段、禁止前导 `./`；匹配前对「验证器实际打开的文件」做同一规范化，**大小写敏感**逐字节比较 path 字符串。
2. **sha256**：对验证器即将 `read_text`/`read_bytes` 的**同一开档结果**的 **原始字节**做 SHA-256（hex 小写）；**不做**换行规范化、不剥 BOM、不 follow 与否分叉——统一 `Path.open("rb")` 读到的字节（symlink 则读 target 内容，与 `read_text` 一致）。
3. **匹配条件**：`canonical_path ∈ legacy ∧ sha256(bytes(file)) == entry.sha256` 才走旧语义；path 命中但 digest 不命中 → `ignore-legacy-digest-mismatch` + 严格规则（已有 J7）。
4. **生成命令**（写进规格，避免手算）：  
   `python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' <path>`

未写死就落地 = T-071 批过的「留给实现去猜」。**FAIL**。

#### 1.3 靶子 3：保留行内形式是否重新打开问题 — FAIL（理由成立，放宽有洞）

**表格理由：成立。**  
GFM 表格续行要求行呈现为 table row；**独占一行的 HTML 注释是 html block，不是 table row，会打断表格**（后续 `|` 行往往变成新表或普通段落）。语料反证：

```markdown
| S2 | … `plugins/harnessloop/.../check_setup.py` … | 与 §1.2 一致 <!-- verify:ignore --> （v1 笔误原文 `harnessloop-loop/.../` …） | 已修复 |
```

（`.harnessloop/goals/20260716-001-setup-wizard/rounds/0002/reviews/adversarial-review.md:53`）  
此处行内 marker 是合理需求；若只许独占行，必须拆表或把注释塞进单元格——作者说的摩擦真实。

**但放宽重新打开了这些面：**

1. **与独占行作用域重叠（具体构造）**

```markdown
<!-- verify:ignore -->
see `src/a.py` <!-- verify:ignore --> and prose
```

- exclusive@L1 目标 L2；inline@L2 目标 L2 → **同一目标被两个 marker 命中**。
- 若 L2 恰 1 条引用：两个都「OK」；不变量数值仍 ≤1，但诊断/计数/「一个 marker」语义未定义（双报？双计 unscoped？）。
- 规格零字处理相邻重叠。

2. **子串误触发（比重叠更严重）**

```markdown
See docs: <!-- verify:ignore --> is the opt-out; also check `src/exists.py`.
```

实测（当前 `IGNORE_MARKER in line` 语义，v2 若沿用子串检测）：

```text
pathish(line)  -> cited=[], ignored_explicit=1   # 整行已豁免
去掉 marker 后 -> cited=['src/exists.py']        # 恰 1 条
```

v2 判定：行内 + 1 条 → **合法豁免**。作者只是在说明语法，真实引用被关掉。  
**「一个 marker 至多豁免一条引用」在计数上成立，在意图上被旁路。**

3. **独占行定义过窄，反而弄坏 blockquote / 表内独占**

```text
'> <!-- verify:ignore -->'  → 非 exclusive（有 `>`）→ 行内 → 目标同行 0 引用 → stale
下一行 '> `src/a.py`' 在 v2 下不再被上一行覆盖
```

当前实现（`prev line has marker`）**会**豁免下一行。v2 在「收紧」的同时对 blockquote 前缀是**行为回退**，规格未提。

4. **表格多引用行并未因行内形式变好**  
L53 有 2 条 pathish 引用 + 行内 marker → v2 → `ignore-scope-ambiguous`，两条都不豁免。行内形式只救「表内单引用」，救不了 pilot 类「表内/行内多引用要豁免其一」——那仍要重排单元格（§7 已登记，但是放宽的收益上界要写清）。

**判定：FAIL** — 表格理由属实，但「保留行内」在未定义 marker 识别（子串 vs 作为整段 HTML comment token）、重叠、以及 exclusive 的真实字形时，重新打开误豁免与行为回退。

#### 1.4 靶子 4：J3「两条都不豁免」vs「报违规仍按旧语义豁免」— PASS（选 fail-closed）

防御性收窄的正确语义是：**违规 ⇒ 本次不给予豁免**。

反例（若选「报违规仍豁免」）：

```markdown
<!-- verify:ignore -->
dangling `no/such/a.py` and also `no/such/b.py`
```

- 软语义：报 `ignore-scope-ambiguous` 的同时两条都不做存在性检查 → 门变红，但**两条悬空引用从 Rule B 消失**；作者可能只删 marker 或拆行应付 ambiguous，却已习惯「先 ignore 再收拾」。
- 硬语义（规格）：两条都进 `cited` 并照常 dangling，**外加** ambiguous → 修复路径唯一是拆行 / 去掉反引号 / 去掉 marker。

B2b 要的是「不能静默大面积关检查」。fail-closed 正确。**PASS**。

#### 1.5 靶子 5：`ignore-marker-stale` 是否过激 — PASS_WITH_NOTE

对**防御性出口**，「不起作用的 ignore」变成硬错误是合理的：陈旧 marker 会豁免**以后落到该行的任何东西**（规格自己的理由成立）。语料也有「marker 还在、引用已不是引用」的行（0002 L52：只剩正则 span，pathish 引用 0 条）——当前字段仍把它算进 ignore 使用量。

过激面（NOTE，应在 detail 与文档里消化，不必删 kind）：

- 文档/教学句提及 marker 且无 pathish 引用 → stale 红（应改写成不出现精确子串，或 code span 隔离且检测改为 token 级）；
- exclusive 下一行是空行 / ` ``` ` → stale（C6/C8 类）。

**PASS_WITH_NOTE** — 保留 kind；必须规定 detail 含目标行号、找到的引用数、两种合法形式示例（§7 已要求，保持）。

#### 1.6 靶子 6：是否仍然过度设计 — 见文末独立节「值不值得做」

（按任务要求独立成节；此处不重复结论。）

---

### 2. 攻 §3 不变量「一个 marker 至多豁免一条引用」— FAIL（有反例与未定义缝）

| # | 构造 | 不变量？ | 说明 |
|---|---|---|---|
| A | exclusive + 下一行 1 引用 | 成立 | 正常路径 |
| B | 下一行 ≥2 | 成立（0 条豁免） | J3 fail-closed |
| C | 同行两个 inline + 2 引用 | 成立（ambiguous） | 双 marker 诊断未定义 |
| D | exclusive 与 inline 叠在同一目标且 1 引用 | **计数成立，语义双重命中** | 规格未定义 |
| E | `See docs: <!-- verify:ignore --> … \`src/x.py\`` | **意图被绕过** | 文档子串 → 合法豁免唯一真实引用 |
| F | 代码围栏内 exclusive | 规格未排除 | 围栏内 marker 仍生效；围栏外其它引用不受影响 |
| G | `MARKER` 出现在 code span 内且同行另有路径 | 当前整行 ignore；strip 后 CODE_SPAN 可能错位 | 依赖检测是否先 token 化 |
| H | 多行 HTML `<!-- verify:ignore` / `-->` | 当前不识别（`has_marker=False`） | 不是绕过豁免，是 stale 形式不可用 |
| I | 表单元格内 marker | 行内形式；≥2 引用 → ambiguous | 与 §7 一致 |
| J | `&lt;!-- verify:ignore --&gt;` | 不触发 | 转义后无豁免（fail-closed） |
| K | legacy 文件 | **全局不变量不成立** | §4 显式允许旧行粒度多豁免；不变量只对非 legacy |

**最硬的反例是 E（意图绕过）与 K（作用域例外）**：K 可接受若写清「不变量仅对严格模式」；E 必须修检测。

**「引用候选」未定义**会让不变量本身不可测：同一行在「span 计数」与「cited 计数」下 0/1/≥2 分界不同（0002 L52：3 个 code span、0 条 cited）。

实测既有 **review** marker 在 v2 严格模式下：

| 文件 | 行 | 形式 | v2 |
|---|---|---|---|
| rounds/0001/.../adversarial-review.md | 68 | exclusive | ambiguous(2) |
| rounds/0002/.../adversarial-review.md | 52 | inline | stale(0) |
| rounds/0002/.../adversarial-review.md | 53 | inline | ambiguous(2) |
| rounds/0003/.../adversarial-review.md | 60 | exclusive | ambiguous(3) |
| rounds/0003/.../adversarial-review.md | 108 | exclusive | **OK(1)** |

与规格「7 个既有 marker 里只有 1 个满足」大致同向；但全 `.harnessloop` 下共 **17** 处 marker / **7** 文件，§7 写「4 份文件」——**名单范围未钉死**（Rule B 当前只扫到 3 个 review 文件，`review_files_with_ignore=3`）。

---

### 3. 攻 §4 legacy 摘要豁免 — FAIL（有可构造绕过 / 未写死口径）

**设计意图（内容寻址、改则失效、不用 mtime、不按 round）优于 T-071 的纯 round 分流**，能堵「legacy round 里新建评审自动旧语义」。这部分方向 **PASS**。

**绕过面与缺口：**

1. **摘要口径未写死**（靶子 2）→ 实现用「规范化后再哈希」或「git blob 哈希」或「工作区字节」会在跨平台 / dirty tree 上分叉；属规格缺陷。

2. **路径口径未写死**  
   下列键在字符串相等下是四条不同 legacy 项：  
   `rounds/0001/reviews/adversarial-review.md`  
   `./rounds/0001/reviews/adversarial-review.md`  
   `rounds/0001/reviews/../reviews/adversarial-review.md`  
   `rounds/0001/reviews/Adversarial-Review.md`（大小写）  
   匹配失败 → 严格模式（偏 fail-closed）；若实现 `resolve()` 后与清单比较不一致，可能**漏匹配或误匹配**。

3. **授权式绕过（具体构造，不是「可能」）**  
   规格**不**禁止往 `ignore-legacy.json` 追加条目。攻击步骤：

   ```json
   {"version":1,"legacy":[
     {"path":"rounds/0099/reviews/brand-new.md",
      "sha256":"<对含 20 个裸 marker 的新文件原始字节的 sha256>"}
   ]}
   ```

   J8 只焊死「不在名单 → 严格」，**不焊死「不得把新文件写进名单」**。  
   于是新评审可合法拿旧行粒度语义。安全完全依赖对 `ignore-legacy.json` diff 的人工评审——规格应加：

   - 只允许登记 **本规格落地日已存在** 的 path 快照；或  
   - `legacy` 追加必须附 cutoff 证据（blob 已在 commit `ed7b29c` 之前）；或  
   - 实现拒绝 path 在清单引入 commit 时尚不存在的条目。

4. **symlink**  
   若 path 不变、内容换成 symlink 指向「多 marker 文件」：按「读字节 = target 内容」→ digest 变 → mismatch → 严格。**此路径 OK**（须在规格写明 follow 读内容）。

5. **大小写不敏感卷**  
   清单写 `Foo.md`，磁盘 `foo.md`：walk 到的 path 字符串与清单不一致 → 当严格；作者以为在 legacy 里。偏运营事故，不是静默扩大，但要在 detail 里打印双方 path。

6. **蹭旧语义的「新写评审」**  
   - 不能靠「同 round 新文件」自动蹭（J8 在名单不扩时成立）。  
   - **能**靠改名单蹭（上条 3）。  
   - **不能**靠改文件内容保持 digest（除非碰撞）。  
   - **能**靠把文件 **revert 回** legacy 字节后再加业务（git checkout 旧 blob）——那是内容寻址的本意，不是旁路。

**判定：FAIL** — 缺算法+path 规范 + 名单膨胀旁路；修完这三项后设计可成立。

---

### 4. §6 十一条 teeth — FAIL（含名不副实与自相矛盾）

| # | 断言对象 | 性质 | 结论 |
|---|---|---|---|
| J1 | exclusive 作用域 | 规格要的性质 | PASS |
| J2 | inline 作用域 | 规格要的性质（绑定设计选择） | PASS |
| J3 | ambiguous 双不豁免 | 规格要的性质 | PASS |
| J4 | stale | 规格要的性质 | PASS |
| J5 | 计数改 cited | 规格要的性质（§5.1） | PASS |
| J6 | legacy 下违规 kind/detail 不变 | **半是「锁当前实现形状」** | NOTE：对 violation 合理；勿扩成 coverage 字节不变 |
| J7 | digest 绑定 | 规格要的性质 | PASS（实现时依赖靶子 2 口径） |
| J8 | 非名单 path 严格 | 规格要的性质（焊 §4） | PASS；**挡不住名单追加** |
| J9 | `coverage_schema==2` | **断言输出形状** | NOTE：合理迁移标记，但是 schema 形状齿 |
| J10 | unscoped 字段 | **与 §5.2 矛盾** | **FAIL** |
| J11 | 零迁移 coverage | **与 §5.1 矛盾** | **FAIL** |

#### J10 矛盾（具体）

§5.2 定义：`citations_ignored_unscoped` = 由**旧语义（行粒度）**豁免的引用条数，并写「严格规则下…等价于来自 legacy 文件的豁免量」。  
⇒ 严格模式 marker（即使豁免 1 条）**不应**计入 unscoped，应计 **0**。

J10 却写：「严格规则下任何 marker → **至多 1**」。  
那是把 unscoped 写成了「忽略条数上限」而不是「旧语义豁免量」。  
破坏性反证「字段恒 0」也无法区分「实现漏计 legacy」与「严格全 0 的正确行为」。

**应改为：** legacy 文件中一行粒度 marker 豁免 3 条 → 报 3；**任意严格模式文件 → 恒 0**（B2b 阈值 `==0` 才有意义）。

#### J11 与 §5.1 直接矛盾（具体）

J11：「coverage **除新增字段外逐字段不变**」。  
§5.1：重定义 `citations_ignored_explicit` 为真引用计数 → **该字段数值必变**。

本机对 setup-wizard 三份 review 重算（与 T-071 同口径）：

```text
rounds/0001/reviews/adversarial-review.md: old=2, new=2
rounds/0002/reviews/adversarial-review.md: old=5, new=2
rounds/0003/reviews/adversarial-review.md: old=7, new=4
TOTAL: old=14, new=8
```

当前全项目 coverage 行：`citations_ignored_explicit=14`。schema 2 重跑后该字段应为 **8**（若只计 review 且口径一致），**不是 14**。  
同时 J11 前半「0 违规 → 0 违规」依赖 legacy 名单罩住 0001/0002/0003 中 4 处将变红的 marker——与「coverage 字段不变」不是同一命题。

**J11 必须拆成：**

1. violation 集合在 legacy 罩住的当前语料上仍为空；  
2. coverage：**允许** `citations_ignored_explicit` 按 §5.1 变化；新增 `coverage_schema`、`citations_ignored_unscoped`；  
3. 禁止静默改其它字段的语义。

**名不副实齿：** J6 后半 / J9 / 旧 J11 偏「锁输出形状」；真正锁性质的是 J1–J5、J7–J8、修正后的 J10–J11。

---

### 5. §7 已知摩擦是否遗漏 — FAIL（有遗漏）

已登记 3 条真实。遗漏至少：

1. **文档/评论中的 marker 子串**（靶子 3-E）：教学句、evolution issue 正文大量出现该字符串（本仓 meta 里多处），一旦某行顺带有 1 条 pathish 引用即「合法豁免」或 stale。  
2. **exclusive 字形过窄**：`>` / `|` 前缀使「视觉上独占」变成行内，blockquote/表行行为回退。  
3. **EOF / 空行 / fence 行作目标**：目标行不存在或 0 引用 → stale；作者以为「段落前标记」可用。  
4. **双 marker 重叠诊断**：未定义。  
5. **legacy 名单维护**：§7 只说「人工维护一次 4 份」；未说 Rule B 作用域外文件、也未说防追加。  
6. **coverage schema 与历史 decision.md 对照纪律**：§5.3 有字段，§7 未提醒「禁止用 schema1 数字与 schema2 横比」。  
7. **「引用候选」与 pattern/alias 豁免的交互**：一行仅有被 pattern 豁免的 span + marker → stale（0002 L52）；作者以为仍在 ignore 正则。

---

## 值不值得做

**独立结论：值得做 §5；§3 的不变量值得以更薄的形式做；当前 §3+§4 全文仍略重于风险规模，但远好于 v1。不允许在「完全不碰作用域」上停住就解锁 B2b。**

事实锚点（不可用「感觉」替换）：

- pilot 实测 collateral **绝对量 1 条**、连带率 25%（`docs/rule-ab-pilot-report-20260728.md` §5.1）；  
- v1 语料：79% 含引用行只有 1 条引用（v1 §2；本轮未复扫 73 份，沿用该已提交基线）；  
- 尺子谎言 (b) 是系统性的：本仓 review 上 `citations_ignored_explicit` **14→8** 量级修正。

分层取舍：

| 块 | 与风险是否相称 | 裁决 |
|---|---|---|
| §5.1 计数修正 | 必须 | **做**。否则 B2b 阈值仍盯着说谎字段 |
| §5.2 `citations_ignored_unscoped` + 定义修正 | 必须 | **做**。严格模式应恒贡献 0 |
| §5.3 `coverage_schema` | 必须 | **做**。T-071 已证零迁移漏 schema |
| §3 不变量（目标行恰 1） | 与「B2b 后门」相称；与「1 条历史 collateral」单独比略重 | **做，但收薄** |
| §3 行内形式 | 表格真实，但打开子串/重叠洞 | **可保留，必须改 token 级识别并定义重叠** |
| §4 摘要名单 | 比 round 分流好；算法与防膨胀未写完 | **概念保留，规格 REWORK 后再做** |
| v1 精确语法 | 已证实不相称 | 维持撤回 |

**若只能二选一：**  
「只做 §5、完全不碰作用域」**不够**作为 B2b 硬前置——大面积连带在多引用行上仍然静默、只是被测得更准。T-071 已说「只记录不阻断不够」。  
但「当前 §3+§4 全文一次性落地」也不应在缺口未修时开工。

**推荐最小闭合集（否决的是未写完的部分，不是不变量本身）：**

1. 落地 §5 全套（含 schema=2；**不要**宣称 J11 式 coverage 逐字段不变）。  
2. 严格模式：marker 识别改为「行内 HTML 注释 token 等于 `verify:ignore`」（或整行 strip 后仅含该 comment），**禁止**裸子串匹配，以免文档句误伤/误豁免。  
3. 作用域：保留 exclusive→下一行、inline→本行；目标行 cited occurrence 恰为 1 才豁免；0→stale；≥2→ambiguous 且不豁免。  
4. 重叠：同一目标被多 marker 命中 → 额外 kind 或合并为一条诊断，仍只豁免 ≤1。  
5. legacy：按本审靶子 2 的字节 sha256 + canonical path；清单 **冻结** 为落地时 Rule B 已扫描且需要 grandfather 的文件（当前证据是 3 个 adversarial-review，不是含糊的「4」）；禁止无 cutoff 追加。  
6. 修 J10/J11 文案与齿。

这比 v1 轻一个数量级，比「只改计数」多一道真门闩，和 1 条已观测 collateral + B2b 升硬门的组合是相称的。

---

## Decisions / deviations

- 判断口径：citation = 当前 v0.25.0 `pathish_citations` 在移除 `IGNORE_MARKER` 子串后进入 `cited` 的 occurrence（不去重）；与 T-071 一致。  
- GFM 表格打断：本地无 cmark/markdown-it，按 GFM「非 table row 的 HTML block 会中断表格」规则判定作者理由成立。  
- 未修改任何规格/实现/语料。

## Open questions

- Rule B 的扫描集合是否永远只有 `rounds/*/reviews/*.md`？legacy 名单应按该集合冻结，还是按全树 `IGNORE_MARKER` 出现点？  
- marker 是否必须对 CommonMark HTML comment 词法负责（多行注释、注释内 `--`）？  
- `ignore-legacy.json` 的变更是否要走与 scope-lock 同级的人工确认门？

## Verdict

REWORK

阻断项：§4 摘要/路径口径未写死；legacy 名单可追加导致新评审合法蹭旧语义；J11 与 §5.1 矛盾；J10 与 §5.2 矛盾；行内/子串检测使文档性 marker 合法豁免真实引用；「引用候选」与双 marker 重叠未定义。  
非阻断但须改：exclusive 字形与 blockquote/表前缀；§7 摩擦表补遗；「4 份文件」与实测 3 个 Rule B ignore 文件不一致。

## Next recommendation

1. 重写 §4 为完整 digest/path 算法 + 冻结策略（采纳本审靶子 2 口径）。  
2. 重写 J10/J11；§3 补：引用候选定义、token 级 marker 识别、重叠规则、exclusive 的 strip 规则（是否允许 `>`/`|` 包装）。  
3. 不恢复 v1 精确语法。  
4. 实现前用本审 A–K 构造 + setup-wizard 三份 review 作 fixture；覆盖 14→8 的 telemetry 迁移断言。  
5. 修完后开第 3 轮对抗审，焦点只剩：token 识别与 legacy 冻结是否焊死。

## Vendor output (parsed)

```
I'll execute T-072 as a read-only adversarial review of the v2 ignore-scoping spec: load the task frame, prior review, and the v2 document first.Next I'll inspect the current ignore-marker implementation, pilot data, and corpus markers to test v2's invariants against concrete counterexamples.I'll simulate the v2 scope rules against real marker files and probe table/adjacency edge cases next.I have enough concrete counterexamples. Writing the T-072 adversarial review deliverable.## T-072 complete

Adversarial review is in `.hopper/handoffs/T-072-output.md`.

**Verdict: `REWORK`**

### High-signal findings

| Area | Result |
|---|---|
| §9 六个靶子 | 混合；阻断在摘要口径、行内放宽、过度设计取舍 |
| §3 不变量 | 同文本双 occurrence 被关死；**文档子串** `See docs: <!-- verify:ignore --> … \`src/x.py\`` 会合法豁免真实引用 |
| §4 legacy | 内容寻址方向对；**sha256/path 未写死**；名单可追加 → 新评审合法蹭旧语义 |
| J10 / J11 | **与 §5.2 / §5.1 直接矛盾**（unscoped 严格应恒 0；`citations_ignored_explicit` 实测 14→8） |
| 值不值得做 | **§5 必做**；§3 不变量应收薄后做；不能只改计数就解锁 B2b；不恢复 v1 精确语法 |

**Files touched:** none（只读）
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 443399
- end_time: 2026-07-27T18:11:24.265Z
- log: see `T-072-output.log` for raw output
