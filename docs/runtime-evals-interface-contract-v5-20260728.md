# runtime acceptance evals — 统一接口契约 v5（2026-07-28）

> **v5 是在新语义上的重建，不是 v4 的第五版补丁。**
>
> v1–v4 在 `docs/runtime-evals-interface-contract-20260728.md`（停在 v4，判据触发）。
> 用户裁决（`docs/runtime-evals-checkpoint-20260728.md`，user-confirmed）把硬门重定义为
> **「写入当轮硬门」**：已收盘轮只做冻结自洽核对与留痕，**机械门永不用今天的声明重判
> 它们**。
>
> v1–v4 的复杂度**大部分来自试图跨时间守门**。该目标被证明结构上不可实现后，
> 本文比 v4 短一半以上——**删掉的都是它**。
>
> **本文取代 v1–v4 作为权威**；旧文件保留供审计（它记录了为什么走到这里）。

---

## 0. 一条根规则（v5 的全部简化都从它导出）

> ### **判定的两个操作数必须来自同一个时间层。**
>
> | 象限 | 例 | 何时运行 |
> |---|---|---|
> | **(今天, 今天)** | 声明文件自身合法性、系统声明 ⇄ registry 的引用完整性 | 每次运行，**不挂任何轮**（项目/goal 级违规） |
> | **(轮 N, 轮 N)** | 账本条目自洽、账本 ⇄ 该轮 `decision.md`、账本 ⇄ 该轮冻结副本 | 每次运行，**对所有轮** |
> | **(今天, 轮 N)** | —— | **一律禁止** |
> | **(轮 M, 轮 N)** M≠N | —— | **一律禁止**（无例外；见 §5 对保留义务的处置） |

**这一条替代了 v4 的 4c′ 类、极性 2、`node_digest` 两种读法、4d 两形态、
`max_round(g)` 作为判定域边界——它们全部删除。**

**X9 由构造满足**：不存在 `(今天, 轮 N)` 判定，故今天的任何编辑都不可能改变已收盘轮的
违规集合。不再需要 X9 的专门规则、不需要 cutoff、不需要迁移的 preimage 摘要。

**可机械核**：`validate.py` 可对每条判定断言其两个操作数的时间层相同——这是一条
**meta-teeth**，且是 v5 唯一新增的横切约束（记为 **X10**）。

---

## 1. 权威分配

| 共享事物 | 唯一权威 | 备注 |
|---|---|---|
| eval 稳定 ID `^RAE-[0-9]{4}$` | **S3** | |
| goal registry（`<goal>/evals.json`）schema | **S3** | 普通数组，就地编辑合法（v3 已撤回追加式） |
| 轮内结果账本 schema | **S2** | 文件名 `evidence/runtime/acceptance-evals.json` |
| 外部系统声明 schema 与 `environments` | **S1** | |
| `binding_fingerprint` / `salt_id` 算法 | **S1** | 盐永不落盘 |
| `attempt_id` `^[0-9]{4}-a[0-9]{1,3}$` | **S2** | 前四位 = 所在轮目录名，由 S2 在账本加载时校验 |
| 严格 JSON 加载器 | **S2** | S1/S3/S4/S5 一律消费 |
| `decision.md` 字段解析器 | **S4** | 单一 `parse_decision_fields`；只新增一个必填行 |
| 测试资源授权注册表 | **S5** | setup 层第二份声明文件 |
| **节点字段取值域** | **各自的消费面**，由 owner 在 §4 步 2b 一次性校验 | `node_kind` → S2；`min_evidence` → S2；`clock_domains` → S2 |

**v5 删除的归属**：`max_round(g)`（不再是判定域边界，任何面不得用它做守卫）。

---

## 2. 共享数据模型

### 2.1 标识符（同 v4，不再重述）

`eval_id` / `attempt_id` / `system` id / `auth_id` / `round_id`。

### 2.2 三份声明 + 每轮一份账本

| 文件 | 时间层 | 权威 |
|---|---|---|
| `.harnessloop/setup/external-systems.json` | 今天 | S1 |
| `.harnessloop/setup/test-resource-authorizations.json` | 今天 | S5 |
| `<goal>/evals.json` | 今天 | S3 |
| `<goal>/rounds/<NNNN>/evidence/runtime/acceptance-evals.json` | 轮 N | S2 |

### 2.3 冻结副本：**让 (轮 N, 轮 N) 判定成为可能的唯一手段**

账本条目必须冻结该轮判定所需的**全部今天侧操作数**。这不再是「写入时刻捕获」的技巧
（那个说法已被证伪并撤回），而是根规则的直接推论：**若某判定需要一个声明侧的值，
该值必须在写入时进账本，否则该判定在已收盘轮上无法运行。**

**各面的冻结清单是本契约要求的交付物**（v5 新增义务）：每面必须列出
「本面在轮内判定用到的今天侧操作数」并为每一个指定冻结字段名（统一前缀 `frozen_`）。
**未冻结的，必须在该面 OUT 列逐条登记「该判定只在 `(今天, 今天)` 层存在，不挂轮次」。**

已知的最小集（各面据此扩展）：

| 冻结字段 | 冻结的是 | 使哪条判定可在轮内运行 |
|---|---|---|
| `frozen_system` | 写入时 registry 该 eval 的 `system` | 条目绑定自洽 |
| `frozen_node_digest` | 写入时该 registry 节点的规范化字节摘要 | 判据未被事后改动（**留痕 + 轮内自洽**，不与今天比对） |
| `frozen_due_set` | 写入时该轮的到期集合 | 「缺 ran」判定（S4） |
| `frozen_probe_spec` | 写入时该系统的探活断言与窗口 | S1 的 liveness 判定 |
| `frozen_auth_grant` | 写入时该授权记录的 grant 摘要 | S5 的授权判定 |

**恒必填，取值可以是 null**（v4 的「条件必填」极性与威胁模型相反，已订正）。

### 2.4 `enforcing`

`A(g) = min{ e.activation_round }`，`round N enforcing ⟺ A(g) 有定义且 N ≥ A(g)`。
`activation_round` 是**存储字段**，取值 ∈ `[1, max(1, 现存最大轮号)]`。

**注意**：`enforcing` 现在**只影响「该轮收盘时门是否要求 eval 账本」**，
不影响已收盘轮的自洽核对——后者对所有轮无条件运行。因此
v4 里「把 activation_round 推远即关门」这条旁路的收益大幅缩小：
它只能让**未来的**轮不被要求，改不了任何已有轮的判定。

### 2.5 「硬」在哪里

**不在机械门区分轮次，在协议的调用时机**：`Loop Continuation` step 1 要求写
`decision.md` 前跑门且 exit 0（`loop/SKILL.md:551`），exit code 与 coverage 行逐字进
`Mechanical gate` 字段。

**性质**：一个被判 positive 的轮，**在它收盘那一刻通过了门**。
**不是**「它今天重跑仍通过」——后者已被证明不可得。

**残留（如实登记，不新增声称）**：有人可以不跑门就写 positive。这由既有的
`Mechanical gate` 字段纪律承接——它是记录不是证明，协议本来就写明了这一点。

---

## 3. 违规 kind 命名空间

`external-system-*`（S1）/ `eval-ledger-*`（S2）/ `rae-*`（S3）/
`acceptance-eval-*`（S4）/ `eval-auth-*` `eval-cleanup-*`（S5）。

**每条 kind 必须标注其时间层**（`today` / `round`），并进 coverage 的分层计数——
这使 §0 的根规则在产物层可核。多面同发**不合并**，各报各的。

---

## 4. 判定链

```
【今天层】每次运行一次，违规不挂任何轮
  1.  路径/容器链守卫（X2）
  2.  S1 加载 external-systems.json（all-or-nothing）
  2b. S2 校验 registry 节点字段取值域（node_kind / min_evidence / clock_domains）
  3.  S3 加载 <goal>/evals.json（all-or-nothing）→ 求 A(g)
  4.  S5 加载 test-resource-authorizations.json（all-or-nothing）
  5.  今天层的引用完整性：registry 的 system 绑定 ⇄ S1 声明；授权 ⇄ S1 声明
  6.  S3 的 runtime_rows 探测（thresholds.md 有 Runtime 行而 registry 零声明）

【轮层】对每一个 round N 运行，操作数全部来自轮 N
  7.  S2 加载该轮账本（all-or-nothing；含 attempt_id 轮号一致性）
  8.  S2 校验条目 schema（含各面并入字段与冻结字段）
  9.  S4 的自洽判定：frozen_due_set ⇄ 条目集合；outcome ⇄ 该轮 decision.md 的 Feedback
  10. S1 的自洽判定：条目 ⇄ frozen_system / frozen_probe_spec / liveness
  11. S5 的自洽判定：条目 ⇄ frozen_auth_grant / cleanup 闭环
```

**短路纪律**：任一 all-or-nothing 失败必须产出违规，不得静默进入零检查（X1）。
**今天层失败不阻止轮层运行**（它们时间层不同，互不为前提）——这是 v5 相对 v4 的又一处
简化：v4 里今天层的失败会让整条链短路，从而让「删声明文件」有额外收益。

---

## 5. 保留义务（唯一曾经的跨轮需求）

v4 把它作为「唯一获准的跨轮 join」。**v5 取消该例外**：跨轮 join 一律禁止。

**改法**：保留义务是一个**今天层**的状态，落在 `state/` 下由 S5 拥有的
`eval-obligations.json`——开立与销账都在**写入当轮**由执行者更新，
门在今天层核对其自洽（每条 open 义务必须能指回一个存在的轮目录与 `auth_id`）。

**代价（如实登记）**：该文件由被守门方维护，门只能核对自洽、不能核对它是否遗漏了
某条义务。这与 §2.5 的残留同族，**不新增声称**。

---

## 6. X10：时间层一致性（v5 新增的横切约束）

> **每条判定的两个操作数必须来自同一时间层；`(今天, 轮 N)` 与 `(轮 M, 轮 N)` 一律禁止。**

**meta-teeth**：`validate.py` 对每条判定断言其操作数的时间层标注一致；
新增判定若跨层，直接红。**这是 v5 唯一新增的横切约束，也是 §0 根规则的执行机制。**

---

## 7. 五面的重启义务

| 面 | 必做 |
|---|---|
| **全部** | ①产出**冻结清单**（§2.3）；②给每条判定标**时间层**；③把跨层判定要么冻结要么降为今天层并进 OUT 列 |
| S1 | 6 条声明比对全部降为今天层或靠 `frozen_probe_spec` 转轮层 |
| S2 | 账本 schema 纳入全部 `frozen_*` 字段；删 `node_digest` 的漂移读法 |
| S3 | due-set 冻结进账本（`frozen_due_set`）；删对已收盘轮的一切重判 |
| S4 | 删 `max_round` 守卫与 `in_scope` 装置（根规则已承担）；`Acceptance evals:` 冻结锚点保留 |
| S5 | 授权比对拆为今天层（注册表自洽）+ 轮层（`frozen_auth_grant`）；保留义务改 §5 |

---

## 8. 确认方式（v5 与前四版不同）

前四版由主会话独自钉、五面确认，连续四版在上一层引入类级遗漏。
**v5 的确认改为：五面确认 + 一轮 hopper 异构对抗审（codex/grok），两者都过才进综合规格。**

理由：五面是同一模型的五个实例，共享盲区；本项目对「异构轮换抓到自己人看不见的东西」
已有 7 次实测记录。
