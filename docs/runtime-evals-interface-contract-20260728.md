# runtime acceptance evals — 统一接口契约 v2（2026-07-28）

> **这份文件是五面能否组合的那块缺失拼图。**
>
> 起因：五面并行设计 → 各自修订 → 三个窄镜头做跨面一致性检查，**三个镜头独立给出
> `does-not-compose`**，合计 **26 blocker / 27 major / 6 minor** 冲突。同一个产物有 3–4 套
> 互斥 schema，其中数处是**结构性无绿路**（没有任何取值组合能让三面同时为绿）。
>
> **根因是流程错误，不是设计能力问题**：我并行 fan-out 五个面时只给了散文式的「跨面依赖」
> 字段，**没有先钉死共享数据模型**。X1–X9 管的是*策略*，不管*接口*。五个面不是五个独立
> 机制，而是**一个机制的五个侧面**——共用一份 registry、一份账本、一套 ID 空间、一条激活
> 规则。并行设计它们本身就是错的。
>
> 本文件按三镜头**一致的**权威裁定，把共享数据模型钉死。综合规格在此之上写。
>
> **v2 修订说明**：v1 发布后，五面按契约做边界对齐，通过契约自留的「唯一允许挑战契约
> 的出口」提出 **20 条冲突**。其中数条**正是契约本身要防的那类错，而我犯了**——
> 例如 §2.3 把 `outcome` 写成「闭集四值」，而 owner 面定的是七值（S1/S2/S4 三面独立
> 指出；S1 的原话：「不要在契约里留一个与 owner 面不同的数字，**那正是本轮 26 个
> blocker 的成因形状**」）。全部 20 条的处置见 §7。
>
> 授权：main-session ruling under user delegation 2026-07-28。

---

## 1. 权威分配（三镜头一致，不再辩论）

| 共享事物 | **唯一权威** | 其余面的义务 |
|---|---|---|
| eval 稳定 ID 格式 | **S3**（TH-0024） | 一律用 `^RAE-[0-9]{4}$`；S2 删 `EVAL_ID_RE`，S5 删 `threshold_id` 改名 `eval_id` |
| goal registry（`<goal>/evals.json`）schema | **S3** | S2/S4 撤回各自的 schema；S3 扩表纳入 S2 需要的 node 字段与追加式记录 |
| 轮内结果账本 schema | **S2**（TH-0020） | S4 撤回自己的顶层 schema，改为「只读 S2 schema 的子集投影」 |
| 结果账本**文件名** | **S4 的取名** `evidence/runtime/acceptance-evals.json` | S2 逐字改名（S4 的 decision.md 摘要链与 Rule A 论证都挂在这个名字上） |
| 外部系统声明 schema 与 `environments` 枚举 | **S1**（TH-0019） | S2/S5 只消费；S1 补必填键 `environments` |
| `binding_fingerprint` 算法与 `salt_id` | **S1** | S2 只负责 schema 落点，删自己那套重算分支 |
| `attempt_id` 格式 | **S2**（生成方） | 统一 `^[0-9]{4}-a[0-9]{1,3}$`（采纳 S1 要的轮号内嵌性质） |
| eval ↔ system 绑定的**取值域与缺席语义** | **S1** | 载体在 S3 的 registry；S3 把该字段改为**必填无默认** |
| `enforcing` 的定义 | **S3 的 `A(g) = min(activation_round)`** | S4 的 `len(evals)>=1`、S2 的 `declared>=1` 一并撤回 |
| `thresholds.md` Runtime 行探测器 | **S3 的 `runtime_rows`**（fail-closed 更强） | S4 的第二个探测器删除；S4 §2 的 X1.3 分类作废 |
| **追溯判红的极性** | **S4**（X9.1 的字面要求） | S3 删除对 `N < max_round` 轮的 `rae-due-set-mismatch` |
| **墙钟的极性** | **S5**（门永不读墙钟） | S2 删除 `expires_at` 与项目级墙钟扫描，保留义务改轮次计数 |
| **严格 JSON 加载器** | **S2**（三份里最严：`object_pairs_hook` 拒重复键、`type(v) is int` 拒 bool、`parse_constant` 拒 NaN/Infinity、递归拒未知键） | S3/S4 一律消费、不得再写第二份。既有的 `_load_versioned_roots`/`_load_local_bindings` 同 PR 迁到它上面——**不把既有缺陷抄进新判定链的核心** |
| **`decision.md` 字段解析器** | **S4**（decision.md 是它的接线面） | 单一 `parse_decision_fields(text, labels)`，所有面的 label 在此注册；`None` vs `""` 可区分、含冒号匹配、遮蔽反例进 docstring。**decision.md 只新增一个必填行**（S4 的 `Acceptance evals:`），S3 的 `Runtime evals due:` 撤回 |
| **`max_round(g)`** | **共享 goal 上下文**（每 goal 计算一次，与 `verify_round` 今天接收同一 `roots` 字典同形） | 计算规则钉死：目录名匹配 `^[0-9]{4}$` 的轮取 max。非法轮名报 `rae-round-name-unparseable`（S3）。**这一条不补则 `mkdir rounds/9999` 同时抬高 I1 上界并把 today-due 义务移走** |

**注意最后两行**：S4 与 S5 各只赢了一条，但赢的都是**极性**（方向），不是载体。
极性冲突若不先裁，任何载体设计都可能被推翻——这是本契约先裁极性、再钉载体的理由。

---

## 2. 共享数据模型（钉死，任何面不得再自定义）

### 2.1 标识符

| 标识符 | 正则 | 生成方 | 说明 |
|---|---|---|---|
| `eval_id` | `^RAE-[0-9]{4}$` | S3 registry | 全 goal 内唯一；**大写前缀是刻意的**，与项目内既有小写 alias 空间不撞 |
| `attempt_id` | `^[0-9]{4}-a[0-9]{1,3}$` | S2 执行器 | 前四位**约定**为所在轮目录名。⚠️ **格式本身不交付这个性质**（正则只保证是四个数字）——一致性由 **S2 在判定链 4a 校验**：`attempt_id[:4] != <该轮目录名>` → 账本整份作废。v1 写「在格式层即不可能」是**声称了一个没有实现承载的保证**，已订正 |
| `system` id | `^[a-z][a-z0-9-]{1,31}$` | S1 声明 | 与 `ALIAS_RE` 同族 |
| `auth_id` | `^[a-z][a-z0-9-]{1,63}$` | S5 registry | |
| `round_id` | `^[0-9]{4}$` | 既有轮目录名 | |

**冲突根源的记录**：`RAE-0001` 不 match S2 原来的 `EVAL_ID_RE`（`^[a-z]...`，大写即失败），
于是一份引用权威 ID 的账本在 S2 的递归未知键/格式检查处**整份作废**，后续全部检查不跑。
这是「两个面各自合理、组合即死」的典型，也是本契约存在的理由。

### 2.2 三个共享文件

| 文件 | 权威 schema | 谁写 | 谁读 |
|---|---|---|---|
| `.harnessloop/setup/external-systems.json` | S1 | 用户/主会话 | 门（S1 判定）、S2/S5 做 join |
| `<goal>/evals.json` | S3 | 主会话 | 门（S3/S4 判定）、S1/S2/S5 做 join |
| `<goal>/rounds/<NNNN>/evidence/runtime/acceptance-evals.json` | S2 | 探针执行器 | 门（S2/S4/S5 判定）、S1 的 D-4 join |

**轮内不得有第四份账本。** S1 上一版的 liveness 独立账本并入 S2 的结果账本（作为
`kind: probe` 的条目 + `liveness` 子对象），否则同一轮有两份账本、两套 attempt 语义、
两处去重规则。

⚠️ **v1 的「没有第四个文件」说过头了**（S5/S2/S1 三面指出）：按字面读会连 setup 层的
`test-resource-authorizations.json`（S5）一起禁掉，而契约 §5 给 S5 的必改项恰恰要求
读它的 `admits_environments`。**setup 层声明文件为两份**：`external-systems.json`（S1）
与 `test-resource-authorizations.json`（S5）。该句的射程仅限**轮内产物**。

### 2.3 结果条目的键集（S2 拥有，但必须容纳其余面的必填字段）

S2 的闭合键集**必须**逐字并入以下字段，否则 S1 的条件阻塞与 S5 的授权检查
在结构上不可计算（S2 的递归未知键拒绝会让整份账本作废）：

| 字段 | 来源面 | 必填条件 |
|---|---|---|
| `eval_id` | S3 格式 | 恒必填 |
| `attempt_id` | S2 | 恒必填 |
| `system` | S1 取值域 | 恒必填，`str \| null`（**标量，不是列表**——S1 的 D-4 join 是一对一） |
| `binding_fingerprint` / `salt_id` | S1 算法 | `system != null` 时必填 |
| `external_effects` | S5 | `system != null` 时必填（tagged union：`read-only` \| `authorized-write`） |
| `outcome` | S2 | 恒必填，**闭集；取值域与基数由 S2 的 schema 定义**（v1 写死「四值」与 owner 面的七值冲突，已订正）。其余面一律**全域二分**：`== "pass"` 为通过，其余一切取值（含 S2 日后新增）为不通过——使 S2 扩枚举不会让别面静默失效 |
| `evidence` | S2 | **键**恒必填（缺键即整份作废）；**非空**为条件必填：`outcome ∈ {pass, fail}` 时 `role: primary` 条数 ≥ 节点 `min_evidence`（≥1）。`outcome` 为未产出类取值时允许空数组——要求「探针崩了什么都没产出」的执行者凭空造一个文件只惩罚诚实（X5.3），且会让「不写这一行」比「如实写」更省事 |
| `provenance` | S2 容器 | `system != null` 时必填，闭键集 `{executor_kind, handoff, command_digest}`。S5 消费 `executor_kind`（委派预授权写不可采纳的唯一输入，附录 C.3-3） |
| `liveness` | S1 语义 / S2 落点 | `object \| null`，闭合子键集 10 项。**当且仅当**该 Result 的 registry 节点 `kind == "probe"` 时必填，其余 kind 必须为 `null`。子键集与枚举取值域由 S1 发布、S2 在 4b 执行 |

### 2.4 `enforcing` 的唯一定义

```
A(g) = min{ e.activation_round : e ∈ registry(g).evals, e.activation_round is not None }
round N of goal g 处于 enforcing  ⟺  A(g) 有定义 且 N ≥ A(g)
```

配套不等式 **I1′**：任一记录的轮号字段 ∈ `[1, max(1, max_round(g))]`。

⚠️ **v1 的 I1 带 `+1`，被 S3 证伪**：上界随 `max_round` 单调增长，于是「把激活轮每轮 +1」
是一条**永远满足 I1 的合法配置**；叠加只判 `N == max_round` 后，`A(g) = max_round+1`
意味着**没有任何一轮处于 enforcing**，全套齿静默关闭且零违规。去掉 `+1` 后，写下第一条
active 记录的那一次运行当前轮即 enforcing，「差一轮」这个状态在结构上不存在。
**代价**：不能预声明「下一轮起激活」——激活必须写在它生效的那一轮（已进诚实边界）。

**`activation_round` 是派生量，不是存储字段**（S3 指出与追加式载体互斥）：
`activation_round(e) := min{ r.state_from_round : r.eval_id == e, r.disposition == "active" }`。
于是 `A(g) = min_e activation_round(e)` 与「N ≥ A(g) 即 enforcing」逐字保持成立，
同时「永不就地编辑既有记录」的追加式性质不被破坏。

**与附录 E.2 的关系**：E.2 裁定「激活是派生的，不是开关」。本定义是它的机械替身——
`activation_round` 不是一个 `enabled` 布尔，而是一个**必须落在真实轮次序列附近**的
序号；配 I1 后它无法被拨到无穷远。E.2 的**下界锚点**（`thresholds.md` 有 Runtime 行
而 registry 零声明即违规）由 **S3 的 `runtime_rows` 探测器**承载。

### 2.5 两条极性（先于一切载体）

| 极性 | 裁定 | 可执行反证 |
|---|---|---|
| **门永不读墙钟** | **S5** | `TZ=UTC+14` / `TZ=UTC-11` / `faketime +400d` 三跑，`--json` 输出**逐字节相同** |
| **今天的 registry 不得判红已收盘轮** | S4 | 只对 `N == max_round(g)` 求值 today-due；对 `N < max_round` 的判定只用该轮当时的账本与 `from_round` 留痕 |

第一条同时解决了 S2 的 `expires_at`：保留义务从「墙钟到期」改为
**`retention_rounds` 轮次计数**（S5 修订版已如此，S2 跟随）。

---

## 3. 违规 kind 命名空间（防撞名）

| 前缀 | 归属 |
|---|---|
| `external-system-*` | S1 |
| `eval-ledger-*` / `eval-result-*` | S2 |
| `rae-registry-*` / `rae-due-*` | S3 |
| `acceptance-eval-*` | S4 |
| `eval-auth-*` / `test-auth-*` / `eval-cleanup-*` | S5 |

**至少四个 kind 名此前被两面各自定义**（不同 owner、不同触发条件、不同判定位置），
使违规集合在合成后不可解析、各面的 teeth 无法断言「恰好一条 X」。本表钉死后，
**任一面新增 kind 必须落在自己的前缀内**。

**多面同发的合并语义**（此前只有 S1 表过态、其余四面沉默）：**各报各的，不合并**。
理由：它们是不同事实（系统不可用 vs due 未跑 vs 授权越域），合并会让「哪一层出的问题」
在 detail 里丢失。teeth 因此可以断言「恰好一条某 kind」。

---

## 4. 判定顺序（跨五面合成一条链）

```
0. 路径/容器链守卫（X2）：.harnessloop → setup → 叶子；任一层 symlink 逃逸即整体拒绝
1. S1 加载 external-systems.json（all-or-nothing）
2. S3 加载 <goal>/evals.json（all-or-nothing）→ 求 A(g)
3. S3 的 runtime_rows 探测：thresholds.md 有 Runtime 行而 registry 零声明 → 违规
4. 对每个 round N：
   **域过滤只约束 today-due 派生的义务**（「今天的 registry 说这一轮欠什么」需 `N ≥ A(g)`）；
   **自洽类判定无条件运行**（认领形态、摘要↔字节绑定、Feedback↔账本投影——它们的操作数
   全部是该轮自己的产物）。⚠️ v1 把域过滤写成对整个第 4 步生效，被 S4 指出会重开 X1 堵死的
   静默关门路径：把全部 `activation_round` 设为 `max_round+1` 则判定域为空，已落盘的账本
   一次都不被读。配一条 goal 级违规 `acceptance-eval-ledger-outside-enforcement`。
   4a. S2 加载该轮账本（all-or-nothing）
   4b. S2 校验条目 schema（含 S1/S5 的并入字段）
   4c. S3 求该轮 due-set；S4 判「due 但账本无」「跑了没过却判 positive」
   4d. **S1** 判 `entry.system != registry(g).evals[eval_id].system` → `external-system-binding-mismatch`
       （含 null 与非 null 的任一方向；缺这条 join 则任一账本条目写 `system: null` 即可
       静默脱离 S1 全部判定）；再判条件阻塞：due eval 绑定的系统未声明/不可用
   4e. S5 的授权与清理检查
5. 项目级尾扫：保留义务逾期（**轮次计数，不读墙钟**）。
   ⚠️ 这是**唯一获准的跨轮 join**（S2 指出：契约既删了承载跨轮状态的第四个文件、又保留
   了尾扫，则它只能靠跨轮 join 重建状态）。**范围锁死**：同一 goal 下
   `rounds/*/evidence/runtime/acceptance-evals.json` 的 `cleanup.retention` 与
   `cleanup.discharges` 两棵子树；判据 `max_round(g) - opened_round > retention_rounds`。
   须同步写进 SKILL.md 的机械门边界表 OUT 列的例外说明。
```

**冻结锚点**（S5 指出的洞：已收盘轮的账本被 `git rm` 后无人判红——S4 的「due 但账本无」
按极性 2 只对 `max_round` 求值，S2 的 all-or-nothing 只在文件存在时触发）：
每轮 `decision.md` 新增 leaf **`Acceptance evals: <sha256> | none`**（形状照
`decision-template.md` 的 `Review digest:`，检查照 `verify_protocol.py:2197-2213`），
值为该轮 `acceptance-evals.json` 的字节摘要。它**不读墙钟、不读今天的 registry**，
与两条极性都相容。判定归属 S4（decision.md 接线面）。

**短路纪律**：任一步的 all-or-nothing 失败**必须产出违规**，不得静默进入零检查
（X1）。第 2 步失败尤其关键——它是唯一的根锚点，也是唯一的全局短路点。

---

## 5. 五面各自要改什么（可直接派工）

| 面 | 必改 |
|---|---|
| **S1** | 补必填键 `environments`；`eval_ref` 措辞改 `RAE-####`；liveness 账本并入 S2；`attempt_id` 采用统一格式 |
| **S2** | 删 `EVAL_ID_RE` 改用 `RAE-####`；账本改名 `acceptance-evals.json`；闭合键集并入 §2.3 全部字段；删 `expires_at` 与墙钟扫描；`systems[]` 收窄为标量 `system`；删自己的 `binding_fingerprint` 重算分支 |
| **S3** | registry 扩表（纳入 S2 的 node 字段 + 追加式记录 + `clock_domains`）；`system_refs` → 必填无默认的标量 `system`；删对 `N < max_round` 轮的追溯判红 |
| **S4** | 撤回自己的账本 schema 与 registry schema；`enforcing` 改用 `A(g)`；删第二个 runtime_rows 探测器；迁移改写 `disposition` 词汇 |
| **S5** | `threshold_id` → `eval_id`（`RAE-####`）；`environment` 单值改「该 system 的 environments **全部**元素 ∈ admits」（fail-closed 方向） |

---

## 6. 记账：这次流程错误的教训

**并行设计五个共享同一份数据的面，在没有先钉死接口契约时，必然产出不可组合的部件。**
三个镜头独立判 `does-not-compose` 不是五个设计者水平不够——它们各自的面都被独立核查
判为 `partially-closed`（即质量可用），**冲突全部发生在边界上**。

正确顺序应当是：**先定共享数据模型 → 再并行设计各面的判定逻辑**。X1–X9 覆盖了策略
横切面，但没覆盖**数据横切面**，这是本次的具体缺口。

**已沉淀进 `.harnessloop/meta/self-audit.md`。** 本文件即补上的那一层；后续任何多面
并行设计，须先产出同类接口契约。

---

## 7. v2 修订日志：20 条契约冲突的处置

五面按 v1 对齐时，通过契约自留的「唯一允许挑战契约的出口」提出 20 条冲突。
**全部采纳或部分采纳，无一条被驳回**——这本身说明 v1 的质量水位。

### 7.1 我自己犯的、契约本身要防的错（4 条，全部订正）

| # | v1 的错 | 谁提 | 处置 |
|---|---|---|---|
| 1 | §2.3 把 `outcome` 写成**闭集四值**，而 owner 面 S2 定的是七值 | **S1/S2/S4 三面独立** | 契约只钉**归属**不钉基数；其余面改**全域二分**（`=="pass"` 通过，其余一切不通过），使 owner 扩枚举不会让别面静默失效 |
| 2 | §2.1 称 `attempt_id` 轮号内嵌「在格式层即不可能」 | S1 | **这是声称了一个没有实现承载的保证**（正则只保证四位数字）。改为诚实措辞 + S2 在 4a 落实际校验 |
| 3 | §2.5 极性 2 只写 registry | S1 | 完全相同的危害来自 `external-systems.json`。**推广为「今天的任何 versioned 声明」** |
| 4 | §2.2「没有第四个文件」说过头 | S5/S2/S1 | 按字面会禁掉 S5 自己的 setup 层注册表，而 §5 又要求读它。**射程限定为轮内产物** |

第 1 条尤其值得记：**S1 的原话是「不要在契约里留一个与 owner 面不同的数字，那正是本轮
26 个 blocker 的成因形状」**——我写契约是为了消灭这类错，然后在契约里犯了一次。

### 7.2 v1 遗漏的归属（5 条，全部补上）

| # | 遗漏 | 谁提 | 补法 |
|---|---|---|---|
| 5 | `max_round(g)` 无归属、无计算规则 | S4 | 归共享 goal 上下文；规则钉死；非法轮名报 kind。**不补则 `mkdir rounds/9999` 同时抬高 I1 上界并移走 today-due 义务** |
| 6 | 严格 JSON 加载器三面各写一份 | S4 | 归 S2（最严）；既有两个 loader 同 PR 迁移，不把既有缺陷抄进新链核心 |
| 7 | `decision.md` 两面各加一个必填行 + 两套解析器 | S4 | 解析器归 S4 单一实现；**字段只留一个** |
| 8 | `entry.system` vs registry 绑定的 join 未判给任何面 | S5 | 归 S1（§4 4d）。**不补则任一条目写 `system: null` 即静默脱离 S1 全部判定** |
| 9 | §2.3 未列 `provenance` / `liveness` | S5/S1 | 两键补入。前者是 S5 判委派写的唯一输入，后者是探针 10 个观测的唯一落点 |

### 7.3 v1 的机制缺陷（6 条）

| # | 缺陷 | 谁提 | 处置 |
|---|---|---|---|
| 10 | I1 的 `+1` 使「每轮 +1」成为永远合法的关门配置 | S3 | 改 **I1′**（去 `+1`）。代价：不能预声明「下一轮起激活」，已进诚实边界 |
| 11 | `activation_round` 存储字段与追加式载体互斥 | S3 | 改**派生量** |
| 12 | 域过滤对整个第 4 步生效 → 重开 X1 堵死的静默关门路径 | S4 | 域过滤**只约束 today-due 派生义务**，自洽类判定无条件运行 |
| 13 | 已收盘轮账本被 `git rm` 无人判红 | S5 | `decision.md` 加 **`Acceptance evals:` 冻结锚点**（不读墙钟、不读今天 registry，与两极性相容） |
| 14 | 删了承载跨轮状态的文件却保留项目级尾扫 | S2 | 声明保留义务尾扫为**唯一获准的跨轮 join**，范围锁死并写进 SKILL.md OUT 列例外 |
| 15 | `evidence` 恒必填若读成「恒非空」 | S2 | 改「**键**恒必填、**非空**条件必填」——要求「探针崩了什么都没产出」的人凭空造文件只惩罚诚实（X5.3） |

### 7.4 五面自行落实、契约仅记账（5 条）

16–20：S1 的 `salt` 永不落盘与传递路径写死、S1 的 19 个 kind 归一前缀、S1 补 X7 扫描集
第四个字段（`tls.verify_false_reason`）、S1 的探针条目按 registry 节点 `kind` 识别而非
结果行自报、S1 把覆盖探针的选择改为**全称量化**（追加一条合格记录不再能洗白一条不合格的）。

### 7.5 对齐产出规模

五面合计：对齐 delta **100** 处、最终字段 **182**、违规 kind **163**、
coverage 键 **100**、teeth **61**。

---

## 8. 下一步

综合规格在 v2 之上写。**写之前须确认**：五面对 v2 的 7.1–7.3 各条无新的不可执行主张
（v2 改动了 15 处语义，其中 §2.4 I1′、§4 域过滤、§4 4d 新 join 三处会改变各面的判定逻辑）。
