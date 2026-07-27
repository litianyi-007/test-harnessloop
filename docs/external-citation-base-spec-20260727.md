验证完毕。以下是合成规格。

---

# harnessloop 外部解析基准 —— 单一实施规格 v1

> 依据：五面设计 + 五面对抗证伪，加上我在 v0.17.0 源码与真实语料上自跑的复核（2026-07-27）。凡与facet 原文冲突处，以本文实测为准。所有被判 drop/redesign 的方案已从规格中移除，第 7 节逐条记录砍掉理由。

---

## 1. 一句话决定

采用 **`@@<alias>/<relpath>` 双 sigil** 语法（不是 `@`，不是 `alias:`）；声明**拆两个文件**——版本化 `.harnessloop/setup/reference-roots.json`（无绝对路径）+ 本机 `.harnessloop/local/reference-roots.local.json`（仅路径绑定，gitignored）；**存量一条不改写**，`.hopper/handoffs` 永久冻结，新写的评审从第一天用 alias，pilot 复制入树时人工改写。

---

## 2. 规格正文

### 2.1 语法：`@@<alias>/<relpath>`

**为什么不是单 `@`（facet 1/2/3/4 的共同提案）——实测证伪：**

```
'@types/node/index.d.ts'         cited=['@types/node/index.d.ts']          ← 今天就是 citation
'@app/services/user.service.ts'  cited=['@app/services/user.service.ts']   ← 今天就是 citation
'@babel/core/lib/index.js'       cited=['@babel/core/lib/index.js']        ← 今天就是 citation
```

npm scoped package 与 TS/Vite/Angular `compilerOptions.paths` 别名（`@app/` `@lib/` `@ui/` `@shared/`）密集占据 `@<小写名>/<带扩展名路径>` 这个精确文法。harnessloop 是通用协议，对整个 JS/TS 生态不成立。facet 1 的 shadow guard（`<project>/@alias` 是否存在）结构上抓不到 tsconfig 别名——它在磁盘上从不存在。

**为什么不是 `alias:relpath`（facet 5 的提案）——实测证伪：**

```
'wiki:index.md'   cited=[]   ← 静默丢弃，连 coverage 都看不见
'wiki:SCHEMA.md'  cited=[]
'wiki:kernel/x.md' cited=['wiki:kernel/x.md']   ← 只有带 / 的才行
```

不含 `/` 的 span 根本不进 `pathish_citations`。而真实外部 wiki 的根下恰好是 `SCHEMA.md` / `index.md` / `log.md` —— 顶层文件引用会**无痕消失**，这正是 facet 5 自己用来枪毙 `design://` 的那条理由。另外语料实测 **40 个不同的 `^[a-z][a-z0-9-]+:` 头**（`verify:` 28 次 —— harnessloop 自己的 `<!-- verify:ignore -->` 词汇、`provider:` 31、`hopper:` 7），冒号命名空间已被占满；`strip_locator_suffix('wiki:2026') -> 'wiki'` 还让 alias 分隔符与 locator 分隔符抢同一个字符。

**`@@` 实测零成本、零碰撞：**

```
'@@wiki/kernel/x.md'   cited=['@@wiki/kernel/x.md']     ✓
'@@wiki/SCHEMA.md'     cited=['@@wiki/SCHEMA.md']       ✓  顶层文件不丢
'@@wiki/kernel/'       cited=['@@wiki/kernel/']         ✓  目录形正确
strip_locator_suffix('@@wiki/x.md:12-20') -> '@@wiki/x.md'   ✓
strip_locator_suffix('@@wiki/x.md::anchor') -> '@@wiki/x.md' ✓
```

全语料（162 份 md，含 `.hopper/handoffs` + `.harnessloop`）**`@@`-开头 span = 0 个**。npm / TS paths / Bazel / GitHub 任一命名空间都不使用 `@@`。因此不需要 facet 1 critique 要求的「每项目扫 tsconfig/package.json 冲突」——文法层天然不碰撞。

**文法定义：**

```
alias        := [a-z][a-z0-9-]{1,31}          # 2–32 字符，小写起首，禁 . : _ 与单字符
citation     := "@@" alias "/" relpath
relpath      := 非空；不得以 "/" 或 "~" 开头；不得匹配 ^[A-Za-z]:/ ；
                任一路径段不得等于 ".."；允许以 "/" 结尾表示目录
```

**与既有消歧规则的关系（全部零改动，实测确认）：** `@@` 不触发 `PATH_META_CHARS`；`BARE_DOMAIN_RE` 要求首字符 `[A-Za-z0-9]`，`@` 不匹配；`WINDOWS_DRIVE_ABS_RE` 只在串首生效，`@@wiki/C:/x` 由 relpath 侧守卫拒绝（见 2.5）；`_looks_like_out_of_project` 不匹配 `@@` 开头；`~/...` `/...` `C:/...` 的既有豁免与 `citations_exempt_external` 语义**一字不改**。

**必须改 `pathish_citations`（放弃「零分类器改动」的承诺）：** 加两条分支——(a) `@@alias/` 形态无条件进 cited（含 `@@wiki/kernel` 这种 tail 无扩展名的，实测今天会被形状判定静默丢弃）；(b) 新增两个计数器（2.7）。理由：facet 1 用 sha256 钉死 `pathish_citations` 的做法，正是逼出 facet 4/facet 5 各起一个平行 span 扫描器的原因——把 T-063 惩罚过的「两份拷贝漂移」从 containment 复制到 extraction，且第二个扫描器不看 `<!-- verify:ignore -->`。零 diff 不是安全目标。

### 2.2 声明文件：两文件拆分

**版本化侧** `.harnessloop/setup/reference-roots.json`（进 git，**零绝对路径**）：

```json
{
  "version": 1,
  "roots": [
    {
      "alias": "wiki",
      "purpose": "external design wiki this project's reviews cite as upstream fact",
      "expect_present": ["SCHEMA.md", "kernel/", "research/"],
      "subpaths": ["kernel", "research", "product", "architecture", "server"],
      "approved_by": "user-confirmed 2026-07-27"
    }
  ]
}
```

**本机侧** `.harnessloop/local/reference-roots.local.json`（**绝不进 git**，沿用 `.harnessloop/local/channel-params.json` 既有先例）：

```json
{
  "version": 1,
  "bindings": {
    "wiki": { "path": "~/.llm-wiki/agent-app-design", "bound_at": "2026-07-27T10:12+08:00" }
  }
}
```

**完整 schema 约束（任一违反 → 该 alias fail-closed 不装载）：**

| 字段 | 归属 | 约束 |
|---|---|---|
| `version` | 两侧 | 必须 `1`；否则整份作废、加载零个 root |
| `alias` | 版本化 | `^[a-z][a-z0-9-]{1,31}$`；全局唯一；不得与 `PATHISH_PREFIXES` token 同名 |
| `purpose` | 版本化 | strip 后非空 |
| `expect_present` | 版本化 | 1..8 条 root 相对路径（身份 sentinel，见 2.3） |
| `subpaths` | 版本化 | 可选；首段白名单；判定作用于 **canonical relative path**，不是字面 relpath |
| `approved_by` | 版本化 | strip 后非空（机器只验非空，见第 4 节） |
| `path` | 本机 | 仅此一个键 + provenance 字符串；出现 `identity`/`available`/`optional`/`expect_present` 任一 → `reference-root-local-invalid` |
| — | 两侧 | **禁止任何 include / extends / 相对文件引用**；loader 只 `open` 两个字面常量路径，无间接层 |
| — | 两侧 | 未知 key → invalid；文件 > 64 KiB → invalid；root 数上限 8 |

**缺席 ≡ 空列表 ≡ 今天的行为**（零迁移）。**不进** `init_project.BASE_FILES`（避开 `validate.py` 的五文档骨架同步）、**不进** `check_setup.py::FILES_ORDER`（`total` 恒为 5，`complete`/`gate_blocking` 不受影响）。check_setup 若要报 advisory 行，**必须复用 `load_reference_roots(verify_identity=False)`**，不得自写第二个解析器（facet 3 critique 指出的「向导乐观读数覆盖机械门悲观事实」——本仓在 secret 守门上栽过同一跟头，commit `ec11c50`）。

**低信任半边不得影响可用性判定**：本机文件只回答「路径在哪」，永不回答「这是不是那棵树」。

### 2.3 身份：项目内 sentinel，不是外部树里的 marker

`expect_present` 的每条路径用**同一个** `_resolve_in_root` + `_exists_as` 逐条验证；任一缺失 → `reference-root-identity-mismatch`，该 alias 不装载。

**为什么不是 T-066 §3 建议的 git remote：** 实测本项目唯一真实实例 `~/.llm-wiki/agent-app-design` **是 git 仓但没有任何 remote**（`git remote -v` 空输出，root commit `001efb98…`，HEAD `2ee61d2`，clean）。该建议在第一个真实实例上就装载不了。

**为什么不是 marker 文件（facet 3 P2）：** 实测 `os.link(secret, marker)` → `is_symlink()=False`、`is_file()=True`、`st_nlink=2` —— 硬链接绕过 symlink 守卫，机械门会读取任意本地文件并把 sha256 打进 coverage → decision.md → **PUBLIC 仓**（`docs/security-incident-20260726.md` 同形）。而且 marker 挡不住宽度（`~/Library`、`~/go/pkg/mod` 一条 `touch` 即签），只挡住「你写不进去的树」。sentinel 严格更优：身份锚点落在**项目仓内可 diff 可评审**、**零新读取面**（只做存在性，不读内容）、只读/共享/网络挂载的树可以声明。

**可选增强** `git_root_commit`：若提供，必须比较**全部** root commit 的排序集合、要求恰好一个且相等（实测 `git merge --allow-unrelated-histories` 可让攻击树的 `rev-list --max-parents=0` 输出包含被声明的那个）。**绝不在外部树里执行 git**（外部 `.git/config` 的 `core.fsmonitor` / `filter.*.clean` / `include.path` 均是注入点）；改为直接读 `<root>/.git` 的引用/对象。查不了 → unverifiable（红），绝不 available。

### 2.4 解析顺序：没有顺序，因为两域不相交

域由**文本 + 已声明 alias 集合**决定，在任何文件系统访问之前：

- 匹配 `@@<alias>/` 且 alias 已声明 → **仅**在该 alias 的 root 内解析。不试 project bases、不试 `.harnessloop/`、不试 submodule roots、**不进 suffix hint**。
- 其他全部 → **仅**在 project bases 内解析（与今天逐字节相同）。
- `@@<alias>/` 但 alias **未声明** → **回落到既有项目相对判定**，沿用既有 `dangling-citation` kind 与 detail，detail 末尾追加纯展示提示 `` `@@foo` is not a declared reference-root alias; declared: wiki ``。

最后一条是 facet 1 critique 的 required change：它保证无声明项目的行为逐字节不变，且回落方向是「外部形 → 项目内」，与 T-066 禁止的方向相反，因此不构成任何 fallback。

**畸形 relpath 停在 alias 域内报错，绝不退回项目域**——否则「引用的形状在运行时决定它的域」这个反模式又回来了（`symlink_dotdot_normpath_order` 同族）。

**一个 alias 恰好一个 root，一个 root 恰好一个 base（root 本身）。** 禁止多 root（那就是顺序=fallback），禁止两 alias 指向同一 root（影子 alias 绕过审计）。**嵌套允许，但必须显式声明**（见第 7 节）。

> **修订 2026-07-27（user-confirmed，起因 T-069 F1.2）。** 本条初稿写的是「禁止两 alias 指向同一 **canonical** root」＋「不禁止嵌套」，两句放在一起是自相矛盾的：T-069 实测 `wiki` 绑整棵树、`kern` 绑 `wiki/kernel`，两套不同的 `purpose`/`approved_by`，`@@wiki/kernel/facts.md` 与 `@@kern/facts.md` 解析到**同一个文件**且零 violation——本条想防的审计绕过，走嵌套即可达成，禁令形同虚设。
>
> 两处同时修订：
>
> 1. **「canonical root」改为「同一 root」，同一性由文件系统身份（`samefile`：st_dev/st_ino）判定，不由 canonical 路径串相等判定。** 起因 T-069 F1.1：`Path.resolve()` 不折叠大小写，在大小写不敏感卷（APFS/HFS+ 默认、NTFS）上 `/x/Wiki` 与 `/x/wiki` 是同一目录却有两个不相等的 canonical 串，按串分组的守卫让两个 alias 同时 available、整门 exit 0。硬链接、bind mount、firmlink 属同一类，同一判据一并覆盖。
> 2. **嵌套的处置从「不禁止」改为「必须显式声明」。** 本条的目的是审计可见性，不是拓扑洁癖；靠禁止拿不到这个属性（禁止只会把「同一棵树的子目录用更紧的 `approved_by` 单独授权」这个合法用法一起杀掉），靠**让重叠成为 tracked 文件里可 diff 的事实**才拿得到。落法见 §7。


### 2.5 containment：每基准独立 canonical domain 的精确定义

**新增 `_is_contained_pinned(candidate, canonical_domain)`**，只 canonical `candidate` 一侧，入口 `assert _canonical(domain) == domain`。原因：现有 `_is_contained` 每次调用对**两侧**都 `_canonical`（`verify_protocol.py:406`），会把加载期「钉死 canonical root」的语义在每个调用点丢弃——运行中途被换掉的 `~/wiki` symlink 会让同一次 run 内判定不自洽。project 域继续走 `_is_contained`（一字不改）。

**加载期（`load_reference_roots`），顺序即安全，canonical 优先：**

```
expanduser（只做 ~ 展开，不做 env/glob 插值）
  → resolve(strict=True)  [包 try/except (OSError, RuntimeError)]   ← 实测 symlink 环抛 RuntimeError
  → 必须 is_dir()
  → 才过禁止名单（全部比较 canonical 值）
```

禁止名单（对 canonical 判，不对声明串判）：
- canonical == `Path(canonical.anchor)`（文件系统根）
- canonical == `Path.home().resolve()` 或其 parent
- `is_under(_canonical(project), canonical)` —— root 是项目祖先或等于项目
- `is_under(canonical, _canonical(project))` —— root 在项目内
- 声明串含 `*?[]$%` 或 `${` `$(`

`resolve` 抛异常 → `reference-root-unresolvable`。**每次运行重新校验**，不是「声明时校验一次就信」。

**解析期（`_resolve_in_root(root, rel)`），两道正交防线：**

```python
def _resolve_in_root(root: Path, rel: str) -> Path | None:
    # 防线 1 —— 字面 traversal 拒绝，作用于 join 之前的原始文本。
    #   `Path(root) / "/etc/passwd"` 静默丢弃 root（_looks_like_out_of_project
    #   docstring 记过同一个坑）；实测 @@wiki//etc/x.conf、@@wiki/~/x.md、
    #   @@wiki/C:/x.ini 今天全部能进 cited 列表。
    if (not rel or rel.startswith(("/", "~"))
            or WINDOWS_DRIVE_ABS_RE.match(rel)
            or any(seg == ".." for seg in rel.split("/"))):
        return None
    # 防线 2 —— 未折叠 raw join + 双侧已 canonical 的 containment。
    #   绝不 os.path.normpath 预折叠（T-064 MUST-FIX C 在新域的逐字复用）。
    candidate = root / rel
    if not _is_contained_pinned(candidate, root):
        return None
    return candidate
```

存在性由 `_exists_as(candidate, want_dir)` **单独**负责（T-063 MUST-FIX 2 纪律：containment 不兼作存在性检查，断链 symlink 的 `resolve(strict=False)` 不抛异常）。locator 剥离对 `rel` 做，与 project 侧同顺序（原形先试、剥离后再试）。

**大小写必须逐段精确匹配。** 实测 macOS 上 `@@wiki/KERNEL/FACTS.MD` → RESOLVED。项目内这个残留是**有界**的（文件名在 git 里、Linux CI 会打红）；外部树**完全无界**（不在项目 commit 控制下、永远不会被 CI checkout、没有第三方事实可裁决）。实现：`rel` 逐段用 `os.scandir` 做精确名匹配，宿主无关、确定性；外部树规模小，成本可忽略。**删掉 facet 1 P5「全小写 alias 让 case-sensitivity 残留不扩大」这句——它是假的，被小写归一化的只有 alias 名，`rel` 一个字节都没有。**

### 2.6 后缀提示：外部基准**不纳入**，理由四条

1. **提示会指向一个引用无法改写成的路径。** hint 文案是「cite it by a resolvable path」；对外部文件唯一可解析的写法是 `@@alias/...`，而索引存的是相对 project 的段元组，根本表达不出 alias。
2. **索引是歧义宇宙。** 把 N 棵外部树并进一张 basename→paths 表，等于在提示层复现并集 containment 的错误：一条项目引用会因为某人 home 里的文件而变成「歧义」或「唯一命中」。检查器输出将随未版本化、他人可写的内容而变。
3. **提示就是探测。** 「任何解析不了的引用都去外部树碰运气找候选」正是被钉死禁止的全局 unresolved fallback，换个名字而已。
4. 结构红利：外部树不进索引 → T-062 `noise_pruned`、T-063 `untracked_pseudo_unique`、T-064 `ignored_pseudo_unique` / `stale_tracked_ghost` 四个已修的洞在外部面上**没有对应物**（不是「已修」，是不适用）。建索引会一次性把它们在一棵无界的树上全部复活。

`build_suffix_index` / `_git_tracked_index` / `suffix_hint_target` / `suffix_unique_match` 四个函数**逐字节不改**。alias 引用未命中时 detail 只给 alias 名，**不给候选、不给绝对路径**。

**未来护栏写进 docstring：** 若日后要加 alias 域内提示，必须 (1) per-alias 独立索引、(2) 只回答带该 alias 的引用、(3) 纯展示永不参与 verdict。跨域共享索引 = 并集 containment bug 搬到提示层。

### 2.7 coverage 字段

**先行批（PR-0，独立于外部基准，T-066 §3 明令要求、五面全部遗漏或只有部分捕捉）：**

| 字段 | 语义 |
|---|---|
| `citations_ignored_explicit` | 被 `<!-- verify:ignore -->` 跳过的 span 数 |
| `review_files_with_ignore` | 含至少一个 ignore 标记的 review 文件数 |
| `citations_shape_dropped` | 含 `/` 但 tail 无扩展名、无尾斜杠、无 `..`，因而被形状判定静默丢弃的 span 数 |

**为什么必须先行：** 实测 `pathish_citations` 对 ignore 标记直接 `continue`，不计数、不上报——一个项目可以撒满 ignore 把 Rule B 完全掏空，而 coverage / exit code / `--json` 三者全显示正常。这与 v0.12.0「机械门停止说谎」修的 `citations_exempt_external` 完全同构，当时漏了这个豁免通道。而 `citations_shape_dropped` 堵的是最便宜的转绿手法：`@@wiki/kernel/x.md` 判红 → 删掉 `.md` 后缀 → 实测在**所有** coverage 字段里完全隐形。没有这三个字段，T-066 §1 判据 2（ignore 不得持续上升）今天根本无法验证，B2b 不具备可评估性。

**外部基准批（PR-3）：**

| 字段 | 语义 |
|---|---|
| `external_roots_declared` / `external_roots_available` | 项目级，**在轮次循环之后单次赋值**（放进逐轮累加字典会被乘以轮数） |
| `external_citations_checked` | alias 形态且 alias 已声明的 span 数 |
| `external_citations_resolved` | 解析成功 |
| `external_citations_not_found` | root 内不存在 |
| `external_citations_rejected` | traversal / escapes-root / outside-subpath |
| `external_citations_unverifiable` | root 不可用（未绑定 / identity 不符 / 不可解析） |

**守恒断言：** `checked == resolved + not_found + rejected + unverifiable`（五面原方案的四结局表漏了 malformed 那一类，守恒式当场为假）。

`citations_checked` 含义不变（含 alias 形态）；`citations_exempt_external` 口径与数值**完全不变**——两个数必须并存，否则「引入了声明基准」会被误读成「那个已知缺口关了」。

**安全约束（写死）：** violation detail、coverage 打印行、默认 `--json` 三处**均不得出现** root 绝对路径、`~/` 展开结果、或任何家目录片段。`root-rejected` / `identity-mismatch` / `unavailable` 的 detail 只印 alias + 拒绝原因枚举 + 一句 `run with --show-root-paths for the local path`。`--json` 做 schema 白名单断言（只有白名单内的键可出现）。

---

## 3. 机械守卫清单

| # | 检查什么 | violation kind | teeth（mutation → 必须翻红） |
|---|---|---|---|
| G1 | JSON 解析失败 / `version != 1` / 未知 key / 超 64 KiB / >8 roots / alias 重复 / alias 文法 | `reference-roots-invalid` | 每条一个 fixture，kind 精确匹配；改成「部分生效」→ 红 |
| G2 | 本机文件出现 `identity`/`available`/`optional`/`expect_present` | `reference-root-local-invalid` | 低信任侧自证身份 → 红 |
| G3 | 声明文件出现 include/extends/相对文件引用 | `reference-roots-invalid` | 锁死「只 open 两个字面常量路径」 |
| G4 | canonical root == `/` / home / home.parent / 项目祖先 / 项目内 / 含 glob | `reference-root-rejected` | **把名单挪到 canonical 之前** → 红（实测 `fakehome/w2 -> <项目父目录>` 可击穿全部字面检查） |
| G5 | `resolve(strict=True)` 抛 `OSError`/`RuntimeError` | `reference-root-unresolvable` | fixture 用 symlink 环 `a->b, b->a`（实测抛 RuntimeError） |
| G6 | `expect_present` 任一缺失 | `reference-root-identity-mismatch` | 删掉 sentinel 校验 → 「同名不同树」fixture 转绿 → 红 |
| G7 | 本机未绑定 / root 不可用 | `external-root-unavailable`（每 root 一条）+ `external-citation-unverifiable`（**每条引用一条**） | 改成 `continue` → violation 少 N 条、exit 0 → 红。**噪声正是唯一能随可疑面缩放的信号** |
| G8 | relpath 以 `/`/`~` 开头、drive/UNC、任一段为 `..` | `external-citation-rejected` | 删防线 1 → `@@wiki/../../etc/passwd.conf` 转绿 → 红 |
| G9 | canonical containment（未折叠 raw join） | `external-citation-rejected` | 换成 `Path(os.path.normpath(root/rel))` → `@@wiki/link/../escape.md`（root 内**恰有**同名诱饵）转绿 → 红。**fixture 必须断言解析到的具体路径**，不只断言 verdict |
| G10 | 逐段精确大小写 | `external-citation-not-found` | 换回 `.exists()` → `@@wiki/KERNEL/FACTS.MD` 转绿 → 红 |
| G11 | 尾斜杠目录语义 / 断链 symlink | `external-citation-not-found` | 用 `exists()` 代替 `_exists_as` → 红 |
| G12 | `subpaths` 白名单作用于 canonical 相对路径 | `external-citation-rejected` | `<root>/kernel/link -> <root>/raw` + `@@wiki/kernel/link/x.md` → 必须失败 |
| G13 | **alias-only（本设计第一条命）** | — | 声明 wiki 后，`kernel/kernel-ecosystem-facts.md`（裸前缀、root 下真实存在）必须**仍报 dangling**；把 root 塞进 `citation_bases` → 转绿 → 红。**必须端到端 fixture，不能是 helper 单测** |
| G14 | 外部树永不进索引 | — | monkeypatch 包住 `Path.resolve`/`os.walk`/`subprocess.run`，断言 `build_suffix_index` 期间**没有任何一次调用目标落在任一 declared root 的 canonical 根内**（比「函数没改」强，管得住未来的间接通路） |
| G15 | 未声明 alias 回落项目域 | 沿用 `dangling-citation` | 无声明项目的 `--json` 与 v0.17.0 **violations 多重集逐条相同**、coverage 仅新增全零 key |
| G16 | 声明前后全量不变 | — | **语料级断言**：`.hopper/handoffs` 全量，声明 wiki alias 之后 dangling 总数**一条不变**（语料里没有 `@@`）。任何隐式回退都会让这个数字下降 |
| G17 | round 容器 containment（PR-2） | `round-container-escapes-project` / `round-artifact-is-symlink` | 见 3.1 |
| G18 | coverage key ↔ SKILL.md IN 列 | — | 读 SKILL.md IN 列（窗口边界用 `find("What it does **not** decide")`，**不是 4000 字符魔数**）与 `_empty_coverage()` keys 做集合比对 |
| G19 | 无 escape 旋钮 | — | grep 断言 argparse 无 `allow-missing`/`skip-roots`/`no-external`；schema 无 `optional`/`required` 键。**防的不是今天的代码，是明天「为了让 CI 变绿」的补丁** |
| G20 | 路径不外泄 | — | violation detail + coverage 行 + 默认 `--json` 三处 grep `^/|~/|/Users/|/home/|[A-Za-z]:/` 零命中；`--json` 全量 schema 白名单 |

### 3.1 G17 展开：round artifact containment（当前活洞，实测三层全通）

我实测的三条，**全部是活的**：

```
A: reviews/ext.md 是指向项目外的 symlink
   → violations=['dangling-citation'] rule_b_files=1 citations=1   ← 读了项目外内容，Rule A 无感
B: reviews/ 目录本身是 symlink
   → violations=['dangling-citation'] rule_b_files=1 citations=1   ← 每个条目 is_symlink()=False
C: rounds/0001 目录本身是 symlink
   → rounds=1 rule_b_files=1                                       ← 整轮（含 scope-lock）从项目外读入
```

`rglob` 的 `not entry.is_symlink()` 守卫作用于**条目**，从不作用于**起点路径**。facet 4 P6 只修了 A，B/C 完全落空。另实测断链 symlink `is_file()=False` → 根本不在 `checked_files` 里，若守卫建在 `checked_files` 上会漏掉最经典那一种（T-062 `broken_symlink` 在 artifact 侧原样重现）。

**修法：**
1. 枚举前逐级检查 `goals_dir` / `goal_dir` / `round_dir` / `evidence` / `reviews`：`is_symlink()` 或 `not _is_contained(...)` → `round-container-escapes-project`，其内容**一字节不读**。
2. 条目级 symlink 检查建在原始 `rglob("*")` 之上、`is_file()` 过滤**之前**（用 `os.path.lexists` + `is_symlink()`），断链与目录 symlink 都捕获 → `round-artifact-is-symlink`。
3. Rule A 的 allowed 改为 `is_under(...)` **AND** `_is_contained(file_path, project)` —— 词法管 scope 授权，canonical 管别出项目，两个正交条件都要，注释写死不可互相顶替。
4. `_is_contained` docstring 那句「all three must share this one definition」改成 four，作为 grep 硬验收（T-063 §4 已因同类过度声明判过一次 MUST-FIX）。

teeth：每条给「修前 0 violation / 修后 red」的洞证明；B 的断言必须是 **`dlink` 条目本身被报 kind**，不是「该目录下零文件」——后者在 Python 3.9 上恒真，是假绿。

---

## 4. 明确不做的（写进 SKILL.md 的 OUT 列，逐条诚实措辞）

> 措辞先于实现定稿，单独过一次对抗评审。T-063/T-064 各有一条 MUST-FIX 就是「docstring 比实现强」。

- **这棵外部树是否与本项目相关。** sentinel 只证明该树此刻含有声明中指名的若干路径；`approved_by` 机器只能验非空，验不了真。一棵完全不相干的树同样可以通过。这个判断归 round acceptance authority。
- **这棵树是否「过宽」。** 拒绝 `/`、家目录、项目祖先/内部是机械的；`~/Documents`、`~/go/pkg/mod` 这类合法但过宽的声明**无法机械拒绝**。唯一的约束是 alias-only（宽根也只能被显式写了 `@@alias/` 的引用够到）+ 声明可 diff + 每轮打印 alias 名。
- **alias 解析到的文件是不是评审者想引的那个。** 解析只证明「运行这次机械门的那台机器上、那一刻、按逐段精确大小写规则，被声明并批准的 root 下存在该路径」。它不证明作者意图，不证明内容支持结论。
- **外部内容是否可复现。** root 不在项目 git-of-record 内，没有 Rule A，没有 diff，没有版本化。`expect_present` 与可选 `git_root_commit` 只证明**同源**，不证明内容未变。round 5 通过的 `@@wiki/x.md`，在 wiki 于 round 6 删掉 x.md 之后重跑就是 not_found，而身份依旧通过。**旧轮的解析结果不可复现。**
- **本轮是否为了让自己的引用转绿而扩大了声明。** 声明落在 `setup/`（不是 scope-lock、不是 state/、不是 goal 级），Rule A 结构上看不见它。可用的只有三层非机械抑制：`external_roots_declared` 进 coverage 并逐字进 decision.md、`approved_by` 字段、control-contract 的人工确认条目。**只可见，不可防。**
- **不做跨轮 join**（读上一轮 decision.md 的声明摘要与本轮比对）。本仓自己的记录：跨文件 join 是十个 evolution issue 里六个的来源。用一个新的跨轮依赖去防一个治理问题很可能净负。
- **alias 引用没有后缀提示，这是设计而非疏漏。** 「没有提示」不得读成「检查过且没问题」。
- **`Review:` 与 scope-lock 的 Allowed Changes 永不接受 alias。** 评审产物必须留在项目内可版本化；scope-lock 里的 `@@alias/` span 报 `scope-lock-span-names-reference-root`（reference root 永不可授权写入），不静默丢弃。

---

## 5. 实施步骤（PR 粒度，严格顺序）

### PR-0 · v0.18.0 — ignore/shape 遥测 + coverage 契约 teeth（**独立于外部基准，先发**）

- 加 `citations_ignored_explicit` / `review_files_with_ignore` / `citations_shape_dropped`（`pathish_citations` 里 ignore 分支已经在跳行，加计数是 2 行；shape 分支末尾加 `else` 计一笔）。
- 加 G18（coverage key ↔ SKILL.md IN 列，窗口按标题切分而非 4000 魔数）。
- **验收**：三个新字段在 fixture 上精确计数；无 ignore 的既有项目三字段为 0 且 violations 逐条不变；G18 用哨兵串验证窗口真覆盖到 IN 列末尾（不留人工步骤）。
- **teeth**：删任一计数 → fixture 红；把 `reference-roots.json` 塞进 `FILES_ORDER` → `total` 从 5 变 6 → 红。
- **为什么先发**：T-066 §1 判据 2 今天不可验证，B2b 在它落地之前不具备可评估性；且它在「外部基准根本不做」的分支下仍然全额兑现。约 +40 LOC。

### PR-1 · v0.19.0 — locator 多区间扩展（3 个字符，先测再花 500 LOC）

`LINE_SUFFIX_RE` 扩成支持逗号分隔多区间（`app/x.swift:44-46,443-507` 这种）。

**实测收益**：公平代理集修好 **10 条**，其中**实现期 7 条**——与整个外部基准协议面在实现期修好的条数（7）**一模一样**。一边 3 个字符，一边 ~500 LOC + 一个全新信任域。

- **验收**：`:44-46,443-507` 形态解析；单区间/anchor 行为逐字节不变。
- **teeth**：既有 `strip_locator_suffix` 全部 fixture 保持绿。
- **落地后重测语料**，把新数字带进 PR-3 的决策。

### PR-2 · v0.20.0 — round artifact / 容器 containment（**BREAKING，与外部基准无因果关系，单独发**）

见 3.1。CHANGELOG 必须覆盖 **symlink 目录**（含 round/reviews/evidence 目录本身），不能只写「evidence/reviews 下的 symlink 文件」。**不给 opt-out**（可关的 containment 守卫在对抗场景下等于不存在）。

- **验收**：A/B/C 三条各有「修前 0 violation / 修后 red」对照；本项目全量 14 轮零变化（先跑 `find .harnessloop -type l` 普查并记进 evidence——「应零变化」是假设不是判据）。
- **teeth**：AND 改 OR → A 转绿且既有 scope-lock fixture 仍绿（证明两条件各司其职）。

### PR-3 · v0.21.0 — 外部解析基准本体

按 2.1–2.7 全量落地。**scope-lock 只允许 `verify_protocol.py` + `validate.py` + 声明模板 + 两处 SKILL.md**。

- **验收**：G1–G16、G19、G20 全部 fixture 通过；无声明项目 `--json` 与 v0.20.0 violations 多重集逐条相同；本项目声明 wiki 后 `.hopper/handoffs` 全量 dangling **一条不变**（G16）。
- **teeth**：每条守卫配一次可信的错误写法 mutation。**禁止「删掉整段调用」型 mutation**——那会 NameError 让所有 fixture 因崩溃而红，无法区分「接线正确」与「守卫根本不存在」；必须用「返回全部准入、零 violation 的 stub」。
- **CI 自洽**：所有 fixture 用 `tempfile.mkdtemp` 现造，grep 断言 validate.py 无任何 fixture 引用 `~/` 或本机真实目录。
- **至少预留 2 轮对抗评审**（参照 T-062→T-066：containment 连挨 4 轮 MUST-FIX），brief 必须点名复跑 G9（symlink-then-`..`）与 G6/G13。
- 版本 bump：`plugin.json` + `marketplace.json` + CHANGELOG 三处一致（CLAUDE.md 迭代回路第 5 步硬约束）。

---

## 6. 迁移与收益（实测，带口径）

**口径行**：`verify_protocol.py` v0.17.0；bases = 项目根 + `.harnessloop/` + 5 个 submodule root；locator 剥离开启；外部根 `~/.llm-wiki/agent-app-design`（HEAD `2ee61d2`, clean, 无 remote）；2026-07-27 自跑。

### 6.1 今天真实被检的语料

```
rounds=14  rule_a_files=8  rule_b_files=3  citations=12
dangling=0  exit 0
```

**外部基准对本项目当前实际被检语料的贡献是零。** `.hopper/handoffs` 的 316/189 是**压力代理**，不是任何一条真实红灯。三条 in-tree dangling（历史上）全是**项目内**引用了不存在的文件。这必须写进 evolution plan 的头一行。

### 6.2 压力代理集

| 语料 | 文档 | citations | 现状 dangling | 外部后 | zero | p50 | p75 | p90 | max | mean |
|---|---:|---:|---:|---:|---|---|---|---|---|---|
| 全量 | 66 | 792 | 316 | 241 | — | — | — | — | — | — |
| **公平代理**（剔 T-058/062/063/064/065/066） | **60** | — | **189** | **115** | 19→**35** | 2→**0** | 5→**3** | 8→**6** | 16→**16** | 3.15→**1.92** |

命中 74 处 occurrence / **30 个不同字符串**（`kernel/d1-kernelport-spec-v3-5.md` 12 次、`kernel/kernel-ecosystem-facts.md` 9、`server/server-stack-selection.md` 8 …）。

> 任务书给的「133 条 / 189→120 / zero 18→34」是旧口径。以本表为准。

### 6.3 按纪元拆开——这才是 pilot 预算

| 纪元 | 文档 | dangling | 外部后 | 降幅 | 归零 |
|---|---:|---:|---:|---:|---|
| 设计评审期 T-004..T-041 | 41 | 92 | 25 | **73%** | 32/41 |
| **实现期 T-042..** | **19** | **97** | **90** | **7%** | **3/19** |

最差三份实现期：T-059=16、T-050=14、T-048=11。

**B2b pilot 抽的是实现期。** 所以「−39%、p50 2→0」是一个**已经结束的设计阶段的产物**，在 pilot 队列上不会复现。预登记基线必须用实现期：19 份 / 外部后 90 条 / 3-19 归零 / 最差 16。

### 6.4 pilot 通过条件（预登记，事后不得调）

(a) 真实入树评审 p50 ≤ 1 且 p90 ≤ 6；
(b) `citations_ignored_explicit / citations_checked` ≤ 5% 且 pilot 期间不单调上升；
(c) 每份评审人工处置中位数 ≤ 10 分钟（实测记录，不是估计）；
(d) 「改引用写法 : 加 ignore」≥ 3:1，**只在残留处置上按文档逐份计算**（否则可被批量改写刷分）。

任一不满足 → 保持 B2a 已拿到的账本收益，B2b 继续留在可选 pilot，**不得用批量 ignore 强行收绿**。路径检查器自评类文档单独成层报告。

### 6.5 存量引用：不改写

**`.hopper/handoffs/*.md` 从来不在 Rule B 检查范围内**（Rule B 只扫 `.harnessloop/goals/*/rounds/*/reviews/*.md`），而且实测 `git log --diff-filter=M -- '.hopper/handoffs/*-output.md'` = **0**：至今没有任何一份 handoff 被修改过。它们是 vendor 原始产出、是审计痕迹。为了让一个**根本不检查它们**的门好看而批量改写，是纯粹的负收益。

**迁移动作：**
1. 存量 **零改写**。CI 加一步：`git log --diff-filter=M -- '.hopper/handoffs/*-output.md'` 必须为空（glob 用 `T-*` 不用 `T-0??`，否则 T-100 就漏）。
2. B2b pilot 复制评审入树时**人工**改写外部引用（实测公平代理集 23 文件 / 32 行 / 30 个不同字符串，一次性）。
3. 新写的评审从第一天用 `@@alias/`，靠 `adversarial-review-template.md` 一行文案 + SKILL.md External reference roots 小节。
4. **可选只读报告** `--external-migration-report`：exit code 恒 0、不打印 violations、不做任何写、不接受 glob 参数（只扫已在 `rounds/*/reviews/` 内的文件）。它只列「这些 dangling 的字面路径在已声明 root 下存在」，供作者人工判断。**绝不提供批量 applier**。

---

## 7. 被证伪而砍掉的（不得偷偷复活）

| 方案 | 出处 | 砍掉理由 |
|---|---|---|
| **prefix-alias**（裸 `kernel/foo.md` 映射外部根） | facet 5 P4，判 adopt（=采纳否决） | 实测项目根有 `kernels/openclaw`、`kernels/hermes`，与 wiki 顶层 `kernel/` 只差一字母，字符串前缀匹配会把 7 条今天正确解析的项目内引用改道外部域。更本质：**引用文本本身不携带它属于哪个信任域的信息**——项目日后新增 `research/` 目录，同一条引用的含义静默改变且无任何机械信号。它重开的正是 v0.16 刚关掉的「它恰好存在于别处，所以算解析成功」那一族。诚实标注：本语料实测意外解析面 = 0，否决理由是**结构性的不是经验性的**（这句必须写进 docstring，不得夸大证据） |
| **单 `@` sigil** | facet 1/2/3/4 共同提案，facet 1 critique 判 adopt-with-changes | 实测 `@types/node/index.d.ts`、`@app/services/user.service.ts`、`@babel/core/lib/index.js` 今天全部是 citation。npm scope / TS `compilerOptions.paths` 结构性撞车；shadow guard 抓不到磁盘上不存在的 tsconfig 别名。改 `@@` |
| **`alias:` / `alias://` 冒号形** | facet 5 P1 | 实测 `wiki:index.md`、`wiki:SCHEMA.md` → `cited=[]` 静默丢弃（真实 wiki 根下恰好是 `SCHEMA.md`/`index.md`/`log.md`）；`wiki://x` 命中 `"://" in cleaned` 无痕丢弃；`strip_locator_suffix('wiki:2026')->'wiki'`；语料 40 个冒号头 token 含 harnessloop 自己的 `verify:` |
| **外部树 marker 同意文件 `.harnessloop-reference-root`** | facet 3 P2，判 redesign | 实测 `os.link` 硬链接 → `is_symlink()=False`、`st_nlink=2`，绕过 symlink 守卫让机械门读任意本地文件并把 sha256 打进 PUBLIC 仓；且它挡的是「你写不进去的树」而非「宽的树」（`~/go/pkg/mod` 一条 touch 即签）；只读/共享挂载无法声明。改项目内 sentinel |
| **`external-alias-hint`（全局探测提示）** | facet 5 P2，判 adopt-with-changes 但依赖 P3 | 它 + `--rewrite-plan` 批量 applier 合起来的输入输出与被禁的全局 fallback 逐字相同，只是拆成两个进程。且实测其探测路径缺 containment 时是任意路径存在性预言机（`../../.zshrc` 可达），命中结果拼进 detail → decision.md → PUBLIC 仓 |
| **`--rewrite-plan` 批量改写 + `--rewrite-plan-scan` glob** | facet 5 P3，判 redesign | 由机器（不是作者）判定 146 次「这条引用属于外部域」；`.hopper/handoffs/` 同目录有子代理自动写入的 vendor 原始日志，glob 读取面直接接在 2026-07-26 事故上；且它依赖 harnessloop 协议里不存在的「账本外评审暂存区」，对直接写进 `rounds/*/reviews/` 的项目退化成纯粹的「改被检文件转绿」，违反 SKILL.md 现行纪律行 |
| **`citations_exempt_external_aliasable`** | facet 2 P5，判 drop | 只覆盖三条转绿出口里**最贵**的一条（`~/` 改写）；最便宜的两条（删扩展名、加 ignore）它看不见；未绑定机器上恒为 0——恰恰是最有逃逸动机的场景。同样预算换 `citations_ignored_explicit` + `citations_shape_dropped` 价值高一个量级 |
| **`external_roots_digest` / `marker_digest` 进 coverage** | facet 3 P5 / P2 | 只写数字：无验证方、无跨轮比对（P5 自己排除 join）、可被 `git diff` 完全替代，代价是 coverage 行变长危及「decision.md 逐字记录」纪律的可执行性 |
| **root 之间禁止嵌套（第 7 闸）** | facet 4 P3 | 自述理由是「万一将来有人误改成并集语义」。在 per-alias 单域 + 字面 `..` 拒绝之下它买不到任何东西，却让 `@@design -> ~/.llm-wiki/agent-app-design` + `@@notes -> ~/.llm-wiki` 这种诚实声明非法，**把用户推向「只声明一个宽根」**——恰好放大唯一无法机械关闭的残留。改为 AST 级单域结构断言（断言 `resolve_external_citation` 内 containment 调用点恰好一处且实参是 `root.root`））。**后续（2026-07-27，user-confirmed，起因 T-069 F1.2）：本行的否决依然成立——一刀切禁止嵌套仍会把用户推向只声明一个宽根。但「不禁止」被实测证明让 §2.4 的影子 alias 禁令形同虚设（父 root 与子 root 各有一套 `purpose`/`approved_by`，却解析到同一个文件，零 violation）。裁决为第三条路：**嵌套合法，但必须在版本化声明里写 `nested_under: "<最近声明祖先的 alias>"`**；未声明的祖先/后代关系报 `reference-root-undeclared-nesting`，声明了但这台机器上并非真嵌套报 `reference-root-nesting-mismatch`，两者都只 fail-closed **后代**（祖先自己的声明是完整的，连坐它是拿邻居的疏漏罚它）。审计属性由此靠「重叠是 diff 里可见的事实」实现，而不是靠禁止——`@@design -> ~/.llm-wiki/agent-app-design` + `@@notes -> ~/.llm-wiki` 这个本行当初要保住的诚实声明，现在写一行 `nested_under: "notes"` 即合法。祖先判定与同一性判定同用 `samefile` 而非字符串前缀（大小写不敏感卷上 `/x/Wiki` 不是 `/x/wiki/kernel` 任何 parent 的字符串，却确实是它的父目录）。** |
| **canonical root 深度 ≥ N 的宽度代理** | facet 3 P1 | `/Users/x`、`/Volumes/ext` 深度都是 2 都放行；挡不住任何有意义的「过宽」，却误杀 `/srv`、`/data` 这类合法扁平布局。N 是魔数 |
| **`external-root-unavailable` 降级为非阻断 / 两层状态机 / `optional: true` / `--allow-missing-roots`** | facet 2 critique required change 4 | 一旦不可用不判红，「声明一个本机永不存在的 root」就是一条**完全静默的批量豁免通道**，且比现状更糟（现状 `~/x.md` 至少每条计入 `citations_exempt_external`）。保持 fail-closed，改用**每条引用一条** violation 让噪声随可疑面缩放 |
| **`reference-roots.json` 进 `check_setup.py` 五文件门 / `N/6`** | facet 2 P3 一致否决 | 为一个绝大多数项目用不上的可选能力，全局污染向导头条数字；且同一份工件两个门是漂移温床。焊死断言：`len(FILES_ORDER)==5 and not any('reference' in f for f in FILES_ORDER)` |
| **`pathish_citations` sha256 / 字节不变验收** | facet 1 P1 判据 4 | 它断言的是非目标（源码没变）而不是行为，必然永远通过；正是它逼出 facet 4/5 各起一个平行 span 扫描器（第二个扫描器不看 `<!-- verify:ignore -->`），把 T-063 惩罚过的「两份拷贝漂移」从 containment 复制到 extraction。改为对 `build_suffix_index`/`_git_tracked_index`/`suffix_hint_target`/`suffix_unique_match`/`_resolve_in_project`/`_is_contained`/`submodule_roots` 七个函数 diff 为空 |
| **`inspect.getsource` 含 `_is_contained(`、不含 `normpath` 的结构断言当漂移防线** | facet 3 P3 | `_is_contained(root, root)` 恒为 True 是彻底逃逸却同时满足两个子串条件。降级标注为「只防整段删除」，行为 fixture 才是防线 |
| **在外部树里执行 `git remote`/`rev-parse`/`status`** | facet 2 P1 | 让机械门在一个未经评审、gitignored 文件指定的目录里跑 git，读它的 `.git/config`（`core.fsmonitor`/`filter.*.clean`/`include.path` 均是注入点，`safe.directory` 就是为这个存在）；共享机器上他人拥有的 wiki 会被直接拒绝 → 永久 unbound |
| **scope-lock 里 `@` 开头 span 静默丢弃** | facet 1 P2 | 实测 `extract_allowed_spans` 今天返回 `['@scope/pkg/', 'packages/@scope/ui/']`；无条件过滤会让声明 0 个 root 的 JS monorepo 假红，且 `packages/@scope/ui/` 因不以 `@` 开头而幸存，前后不一致。改为**只对已声明 alias 触发、且响亮报 `scope-lock-span-names-reference-root`** |

---

## 8. 残留风险（消不掉，如实登记）

1. **声明侧扩权无法机械拒绝。** 一个宽 root（`~/Documents`、`~/go/pkg/mod`）+ 一个愿意写 `@@wiki/` 的作者，仍然可以让一条本该指向项目内证据的引用绿灯。三层防线的能力边界：alias-only 保证宽根只能被显式引用够到（G16 是这条的机械证明）；G4 只挡极端声明；sentinel 与 `approved_by` 是记账不是判断。

2. **同轮自肥只可见不可防。** 声明落 `setup/`，Rule A 结构上看不见。`external_roots_declared` 进 coverage、逐字进 decision.md，「凭空多一个 root」在轮间 diff 里可见——但**同轮内删掉 root A 换成更宽的 root B，计数恒为 1，coverage 行逐字不变**。可选缓解：coverage 带两个声明文件的 sha256（约 5 行）；但那与「不要只写数字」的第 7 节判词冲突，且 `git diff` 已能完全替代。**建议不做，写进 OUT。**

3. **外部树内容可被任意创建，且无项目侧痕迹。** 项目域里把 dangling 改绿必须在树内建文件——出现在 `git status`、受 scope-lock 管辖、进 commit diff、评审可见。alias 域里只需 `touch ~/.llm-wiki/agent-app-design/research/notes.md`：零项目侧痕迹、无 scope-lock、无 diff、sentinel 仍报 ok。这是**项目域没有对应物**的一条不对称，机械层挡不住。

4. **解析结果是「某台机器、某一刻」的局部事实。** root 不在 git-of-record 内 → 今天绿的评审明天可能因 wiki 改动而 not_found，而身份依旧通过。要真可复现，唯一办法是把被引外部内容快照进 round（vendor 进树，T-066 §3 第 6 点对 `reviews/*.md` 已经这么裁过）。本规格**不做**，明写进 OUT。

5. **CI / 新机器首跑满屏红。** 声明了 alias 的项目，任何未绑定的机器每条引用一条 `external-citation-unverifiable`。这是 fail-closed 的刻意代价，也是「把 `@@wiki/x.md` 改回 `~/.llm-wiki/.../x.md` 换取既有豁免」这条残留逃逸的**动力源**。缓解只有：CLAUDE.md 加一条与 pre-commit hook 并列的「新 clone 后须绑定 reference root」说明；以及**持续的、必须被抵抗的压力**——把机械门移出 CI，或给 `external-root-unavailable` 加降级开关（G19 就是为此存在的防御性 teeth）。

6. **`~/...` 与 `/...` 的既有豁免原样保留。** 同一个文件永远有「被检查的写法」和「不被检查的写法」两种拼法并存。本规格不假装关掉这个洞，也**不**新增「落在已声明 root 下的绝对路径引用必须改写成 alias」的收紧（那会把既有豁免变成红，属于 T-066 授权范围外的行为收紧，应作为独立议题另开）。

7. **`@@wiki/kernel`（无扩展名、无尾斜杠）今天被形状判定静默丢弃。** PR-3 修掉 alias 形态这一半；但**项目域的同类丢弃仍在**（`src/foo`），由 `citations_shape_dropped` 计数使其可见，不由本规格关闭。

8. **弱 teeth 如实标注：** G19 的 grep 黑名单挡不住改写、G18 的字符串包含断言可能巧合命中、`no-overclaim` 关键词黑名单本质挡不住改写。真正的防线是 OUT 列措辞先于实现定稿并由评审逐条核对——把弱 teeth 当成「这块有覆盖」而降低人工核对强度，净效应为负。