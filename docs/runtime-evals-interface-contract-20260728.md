# runtime acceptance evals — 统一接口契约（2026-07-28）

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

**注意最后两行**：S4 与 S5 各只赢了一条，但赢的都是**极性**（方向），不是载体。
极性冲突若不先裁，任何载体设计都可能被推翻——这是本契约先裁极性、再钉载体的理由。

---

## 2. 共享数据模型（钉死，任何面不得再自定义）

### 2.1 标识符

| 标识符 | 正则 | 生成方 | 说明 |
|---|---|---|---|
| `eval_id` | `^RAE-[0-9]{4}$` | S3 registry | 全 goal 内唯一；**大写前缀是刻意的**，与项目内既有小写 alias 空间不撞 |
| `attempt_id` | `^[0-9]{4}-a[0-9]{1,3}$` | S2 执行器 | **轮号内嵌**（前四位 = round id），使跨轮混淆在格式层即不可能 |
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

**没有第四个文件。** S1 上一版的 liveness 独立账本并入 S2 的结果账本（作为
`kind: probe` 的条目），否则同一轮有两份账本、两套 attempt 语义、两处去重规则。

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
| `outcome` | S2 | 恒必填，闭集四值 |
| `evidence` | S2 | 恒必填（**S2 修订版已把「允许空数组」收口**） |

### 2.4 `enforcing` 的唯一定义

```
A(g) = min{ e.activation_round : e ∈ registry(g).evals, e.activation_round is not None }
round N of goal g 处于 enforcing  ⟺  A(g) 有定义 且 N ≥ A(g)
```

配套不等式 **I1**：任何 `activation_round ≤ max_round(g) + 1`
（防「声明一个永远到不了的激活轮」这条无痕退休路径）。

**与附录 E.2 的关系**：E.2 裁定「激活是派生的，不是开关」。本定义是它的机械替身——
`activation_round` 不是一个 `enabled` 布尔，而是一个**必须落在真实轮次序列附近**的
序号；配 I1 后它无法被拨到无穷远。E.2 的**下界锚点**（`thresholds.md` 有 Runtime 行
而 registry 零声明即违规）由 **S3 的 `runtime_rows` 探测器**承载。

### 2.5 两条极性（先于一切载体）

| 极性 | 裁定 | 可执行反证 |
|---|---|---|
| **门永不读墙钟** | S5 | `TZ=UTC+14` / `TZ=UTC-11` / `faketime +400d` 三跑，`--json` 输出**逐字节相同** |
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
4. 对每个 round N（N ≥ A(g) 才进入 eval 判定域）：
   4a. S2 加载该轮账本（all-or-nothing）
   4b. S2 校验条目 schema（含 S1/S5 的并入字段）
   4c. S3 求该轮 due-set；S4 判「due 但账本无」「跑了没过却判 positive」
   4d. S1 的条件阻塞：due eval 绑定的系统未声明/不可用
   4e. S5 的授权与清理检查
5. 项目级尾扫：保留义务逾期（**轮次计数，不读墙钟**）
```

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
