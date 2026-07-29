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
end_time: "2026-07-28T08:25:18.571Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 201702
adapter_status: success
last_progress_at: "2026-07-28T08:25:18.572Z"
last_progress: Task completed successfully.
progress_seq: 8
terminal_event_emitted: true
---
# T-079 — runtime evals 接口契约 v5 异构对抗审

**Task-type**: `code-review-adversarial`（只读）  
**评审对象**: `docs/runtime-evals-interface-contract-v5-20260728.md`（196 行，权威）  
**源码锚点**: harnessloop `b389eac`（v0.26.0）  
**审阅方**: grok（异构；非五面同源确认）  
**角色**: 查**整个方向是否错**，不查五面内部一致性

**Assumption (1 line)**: runtime-eval 判定链在 `b389eac` 尚未实现；X10 / §0 的「可机械核」按契约字面 + 现有 `validate.py` 能力裁定，不以「将来会写」豁免。

---

## Summary

v5 在**语义方向**上正确吸收了用户裁决：放弃跨时间硬门、塌成 `(今天,今天)` / `(轮N,轮N)` 两象限，并如实登记「硬在协议调用时机」。但这套简化的**承重件**——§0 根规则「操作数同一时间层」+ §6 X10 meta-teeth——**本身不可机械判定**，且 X10 是与 v2 `attempt_id`「格式层即不可能」、v4「捕获点在写入时刻」**同形**的无实现承载声称。三线收敛部分真实、部分事后叙事。v1→v5 历史更像「问题被用纸面多面契约硬解」的信号，不是正常规格收敛。**Verdict: REWORK**——方向可保留，契约不得以现状进综合规格。

## Files touched

none（只读评审，未改任何代码/文档）

---

## 五问逐答

### Q1 — §0 根规则本身成立吗？

**判定: 否决（作为「可机械核」的根规则不成立；作为设计启发式可用）**

> 「判定的两个操作数必须来自同一时间层。」

#### 1.1 是否可判定

**不可机械判定**，除非先补齐契约未钉的三样东西。当前文本缺：

| 缺口 | 为什么致命 |
|---|---|
| **什么是「一条判定」** | 没有判定注册表 / 函数清单 / kind→判定映射。§4 的 1–11 步是散文流水线，不是枚举完备的判定集合。 |
| **什么是「操作数」** | 边界未定义。v4 正是在「gating 谓词算不算操作数」翻车（`docs/runtime-evals-interface-contract-20260728.md` §11.3：无轮次索引的装载/2b/尾扫既不适用 4c′ 也不豁免）。v5 删了 4c′ 却**没有**回答这个问题——只是换了句口号。 |
| **常量 / 代码字面量的时间层** | 未定义。`outcome == "pass"` 的 `"pass"`、`node_kind == "probe"` 的枚举、`A(g)=min{...}` 的算法本身，是「今天」「无时间层」还是「不计入操作数」？ |

**反例构造 A（gating 谓词）**

```
判定 J_due: 「若 frozen_due_set 含 RAE-0001 且账本无对应条目 → acceptance-eval-missing」
操作数候选:
  (a) frozen_due_set          — 轮 N 账本
  (b) 条目集合                — 轮 N 账本
  (c) 「条目是否存在」这个谓词 — ？
  (d) kind 字符串常量         — ？
```

若 (c)(d) 不算操作数，J_due 标 `(round,round)` 绿。  
若日后有人把 (c) 实现成「先读今天的 registry 再决定 due 是否生效」，**标注仍绿、实现已跨层**——根规则对这个变化不可见。

**反例构造 B（常量 / 配置代码）**

```
判定 J_probe: 「node_kind == 'probe' 时 liveness 子对象必填」
# v5 §4 步 2b 把 node_kind 取值域放在「今天层」一次性校验
# 但轮层步 10 的 liveness 自洽仍可能内嵌同一谓词
```

- 若把 `'probe'` 标成无时间层：规则对「取值域从哪来」失明。  
- 若把 `'probe'` 标成今天：则任何含该字面量的轮层判定都变成 `(今天, 轮N)` 而被禁止——但 v5 又要求轮层做 liveness 自洽。  
- 契约**两边都没选**。

**反例构造 C（「两个」操作数）**

§0 写死「**两个**操作数」。§4 步 9 的 S4 判定至少涉及：`frozen_due_set`、条目集合、`decision.md` Feedback、（可能）`Acceptance evals:` 摘要——**≥3**。多元判定如何拆成二元对？未定义 ⇒ 元规则对真实判定形状不闭合。

#### 1.2 「操作数边界谁定」

v5 把它推给各面：§7「给每条判定标时间层」、§2.3「冻结清单是交付物」。  
**那是作者自签标注，不是机械推导。** 与 §11.6 定理同构：门（及 validate）读到的「标注」仍是被守门方/实现者写下的数据。

#### 1.3 对 v5 的含义

v5 自称「全部简化都从它导出」（§0）且「可机械核」（§0 / §6）。  
**若根规则不可机械判定，则 X9-by-construction、删 4c′/max_round/cutoff 等「由构造满足」的声称，失去可核验的地基——它们可能仍是好设计，但不是被 X10 守住的定理。**

---

### Q2 — §6 X10 meta-teeth 是不是又一句没有实现承载的话？

**判定: 是。明确否决。与 attempt_id / 4d 捕获点同形。**

#### 2.1 契约声称

v5 §0:34-35、§6:172-173：

> `validate.py` 可对每条判定断言其两个操作数的时间层标注一致；新增判定若跨层，直接红。

#### 2.2 现网能力（可复现）

```bash
# harnessloop @ b389eac
python3 -c "
from pathlib import Path
p = Path('harnessloop/scripts/validate.py').read_text()
for t in ['time_layer','operand','X10','frozen_','acceptance-eval','RAE-']:
    print(t, p.count(t))
"
# 输出: 全部 0
```

`validate.py` 模块 docstring（L1-18）写明职责：manifest / init smoke / check_setup / secrets / doc skeleton / **既有** `verify_protocol` fixtures / round_cost / claude strict。  
**零** runtime-eval 判定注册、零时间层标注 schema、零「操作数一致性」断言。

全插件 py 树：

```bash
rg -n 'time_layer|operand|X10|frozen_|RAE-' harnessloop --glob '*.py'
# 无命中
```

#### 2.3 即使「将来加上标注」，teeth 仍不咬实现

要实现 X10 字面，至少需要：

1. 每条判定的**权威清单**（谁维护？与实现同步谁保证？）  
2. 每条判定每个操作数的**时间层标注**  
3. validate 读标注并比一致性  

**(1)(2) 由实现者/规格作者产生**。攻击（或诚实疏忽）：

```
# 标注（给 X10 看）
J_bind.operands = [ledger.frozen_system@round, ledger.system@round]  # 一致 → X10 绿

# 实现（真实数据流）
def J_bind(entry, registry_today):  # 仍读今天 registry
    return entry.system == registry_today[entry.eval_id].system
```

X10 绿、跨层实锤。  
**标注≠数据流。** 真要咬实现，需要静态数据流/文件读集合分析，契约只字未提。

#### 2.4 同形对照（项目自承的两次）

| 事件 | 声称 | 为何无承载 |
|---|---|---|
| v2 §7.1-#2 | `attempt_id`「格式层即不可能」错绑轮号 | 正则只保证四位数字（v4 正文已订正） |
| v4 §10.2 / §11.1 | 「捕获点在写入时刻」 | 门是调用时纯函数，无写入钩子（5/5 面证伪） |
| **v5 §6 X10** | validate 断言操作数时间层一致 | 无判定枚举、无标注 schema、无数据流分析；标注可撒谎 |

**结论**: X10 是 v5「唯一新增横切约束」，却是**第三次**「声称了没有实现承载的保证」。应降级为：设计检查清单 / 五面交付物审查项——**不得**称 meta-teeth，不得写进「validate.py 直接红」。

---

### Q3 — 用户裁决是否实际上放弃了需求？

**判定: 部分放弃「跨时间可重判的硬」；未放弃「runtime 进验收路径」。对原需求①是语义收窄，不是静默删除——但若仍对外说「硬门」而不加限定，则是过度声称。**

（详见独立节 `## 是否放弃了需求`。）

---

### Q4 — 「三线收敛」是过度归纳吗？

**判定: 部分过度归纳。共享的是诚实上界口号；三条线的操作处方并不相同。**

#### 4.1 逐线核对实际结论

| 线 | 源 | **实际**结论 | 操作处方 |
|---|---|---|---|
| **批 2 停止落痕** | `docs/loop-stop-record-spec-20260728.md` §1.1–1.2 | 门验证**结构关系**，不能验证**动机**；同层加检查无效 | **收窄职责**：强制层只做结构；理由降记录层；执行力放异常消费+人/评审 |
| **ignore 收窄** | `docs/ignore-scoping-spec-20260728.md` §1 | 病根是**层次错**（散文微型语法），不是牙齿不够 | **换层次**：豁免迁到 JSON 声明；**不放弃检查**，改变载体 |
| **批 1 runtime evals** | 契约 v4 §11.6 + checkpoint | 对已收盘轮：门只见自签历史数据 + X9 ⇒ **历史硬门结构不可实现** | **放弃跨时间硬门**；保留写入当轮协议硬 + 轮内自洽 |

#### 4.2 共同边界 vs 编故事

**真的共同抽象**（可保留）:

> 机械门的力量止于它能独立观测的结构；凡输入完全由被守门方控制、且门又承诺不读「另一时间层权威」的地方，门只能做记录或自洽，不能做对抗性硬否决。

**过度归纳之处**:

1. **ignore 的处方是「换层仍检查」**，不是「力量止于控制范围所以只留痕」。checkpoint 表把 ignore 写成与批 1 同列「边界」，会暗示 ignore 也是认输——**与 ignore 规格正文相反**。  
2. **批 2 仍交付强制结构牙齿**（successor 前向/无环/双向绑定）。批 1 v5 对已收盘轮几乎只剩自洽+留痕。把两者都叫「同一边界」掩盖了**牙齿保留量**的差异。  
3. **批 1 的关键约束是时间+X9**，批 2 的关键约束是**认识论**（动机），ignore 的是**表示层**。三因不同；「独立收敛到同一句口号」有修辞力，**推不出**「因此 v5 的两象限+删 max_round 是唯一合法设计」。  
4. checkpoint §2 表把三条都收成一格「结论」，再在 §3 直接导出 v5 机制表——**从抽象上界跳到具体删除清单，中间缺独立论证**。删除 4c′ 可由 §11.6 单独推出；挂上「三线」是增强说服，不是必要前提。

**更诚实的表述**:

- 批 1：时间维上的自签定理（§11.6）——**充分**支撑写入当轮硬门。  
- 批 2 / ignore：同项目的**类比先例**（诚实边界 / 换层），有助于沟通，**不是**独立证明。

---

### Q5 — v1→v5 演进史指向什么？

**判定: 这段历史是「问题不该（只）这样解」的信号，不是正常规格收敛。**

（详见独立节 `## 演进史指向什么`。）

---

## Acceptance verification (5/5)

| # | 准则 | 结果 | 证据 |
|---|---|---|---|
| 1 | Q1 给判定 + 可复现证据/反例 | **是** | 反例 A/B/C；v4 §11.3 gating 先例；常量时间层未定义 |
| 2 | Q2 给判定 + 源码证据 | **是** | `validate.py` 对 `time_layer/operand/X10/frozen_/RAE-` 计数全 0；docstring 职责无 runtime-eval；同形表 |
| 3 | Q3 从需求方判是否放弃 | **是** | 见 `## 是否放弃了需求`；对照 audit 原裁决① vs checkpoint 修订表 |
| 4 | Q4 逐线核对三线 | **是** | loop-stop §1.2 / ignore §1 / v4 §11.6 逐行对照 |
| 5 | Q5 演进史信号 + 若否会怎么做 | **是** | 见 `## 演进史指向什么`；v4 §11.5 收敛表 + 停止判据 |

---

## 是否放弃了需求

### 原需求（权威表述）

`docs/harnessloop-runtime-evals-autonomy-audit-20260728.md` 页首 + 三项裁决①：

> 补充静态分析和单元测试以外的 **runtime / 多系统测试作为任务实现结果的 evals**  
> ① evals = **硬门**（已声明的 eval 未跑或未过 → 该轮不得判 positive，**机械门可见可拒**）

GAP-3 点名两类假绿：**(i) 声明了没跑**；**(ii) 跑了改判据**。

### 修订后（checkpoint，user-confirmed）

| | 原① | 修订后 |
|---|---|---|
| 硬 | 未跑/未过 → 不得 positive | **仅在该轮收盘那一次门运行中** |
| 已收盘 | （主会话曾按每次重跑重判理解） | **只做冻结自洽与留痕；永不用今天声明重判** |

### 需求方视角：还满足吗？

| 需求切片 | 修订后是否覆盖 | 说明 |
|---|---|---|
| runtime 结果进验收路径（补静态+单测） | **是（条件式）** | 写入当轮要求 due eval 有账本、outcome 与 Feedback 一致——**这是静态/单测买不到的**（它们不探外部系统、不绑定 endpoint） |
| 机械门可见 | **弱是** | exit code + coverage 进 `Mechanical gate` 字段（`loop/SKILL.md:551`）；与既有门同形 |
| 机械门可拒 | **协议可拒、非强制可拒** | 可拒性依赖「写 positive 前真的跑了门」。v5 §2.5 自己登记：可不跑门就写 positive；字段是**记录不是证明** |
| 防 (i) 声明了没跑 | **写入当轮：是；事后：否** | 收盘后改账本/删 ran 只能靠冻结锚点与自洽，对抗性弱 |
| 防 (ii) 跑了改判据 | **写入当轮部分；跨轮：明确放弃** | `frozen_node_digest` 只留痕轮内自洽，**不与今天比对**（v5 §2.3） |
| 「硬」的日常语感（随时重跑仍红） | **放弃** | §11.6 定理 + 用户选 A |

### 相对「静态分析 + 单测」多买到了什么？

**多买到的（真实、有界）:**

1. **外部/runtime 观察**进入 round 验收叙事（探活、多系统、授权写清理）——静态+单测结构上不覆盖。  
2. **due-set 完整性**的机器形状（声明了的 eval 在收盘时须有 ran 记录）——thresholds 散文表至今零解析（audit GAP-2/3）。  
3. **可 diff 的账本 + decision 接线**，对抗评审可质问——同批 2 停止落痕买到的那类东西。

**没多买到的（必须直说）:**

1. **不依赖执行者诚实的硬否决。** 与现有 `Mechanical gate` / B2a `Review:` 同权力级：协议纪律 + 记录，不是宿主钩子或外部公证。  
2. **历史轮的对抗性重验。** 静态分析在 CI 里也是「对当前树」；但用户原话「硬门」在主会话实现里曾被做成跨轮重判——那部分被定理杀死后，**没有**用外部 oracle 补回。  
3. **相对「认真跑单测再合并」的额外对抗硬度 ≈ 0。** 多的是**检查种类**（runtime），不是**硬度等级**。

### 是否「放弃需求」一句话

- **放弃了**: 不依赖自签、可跨时间重放的「硬」。  
- **未放弃**: runtime eval 作为任务结果进入验收、在收盘路径上可被机械看见。  
- **危险点**: checkpoint §5 仍写「**仍是硬门**，只是硬在收盘那一刻」。对内诚实；对外若省略后半句，**等于用原词覆盖已收窄的语义**——这是需求方最该盯的沟通风险，不是实现细节。

**若问「没多买到什么吗」**:  
相对「静态+单测」——**多买到检查种类与账本形状**；相对原词「硬门」的对抗强度——**没多买到硬度，只买到与既有机械门同级的协议时序约束**。直说：**硬度维度接近零增量；覆盖维度有增量。**

---

## 演进史指向什么

### 轨迹（契约自述 + §11.5）

| 版 | 结果 | 修复轴 |
|---|---|---|
| v1 前 | 26 blocker does-not-compose | （并行无接口） |
| v1 | 20 冲突 | 字段/归属 |
| v2 | 8 不可执行 | 载体/派生 |
| v3 | 11（4 同源） | 减法撤回追加式 |
| v4 | 11 structural + 招牌论证 5/5 证伪 | 判定轴 4c′ 升类 |
| **停止** | 判据触发 | — |
| **用户 A** | 硬门→写入当轮 | 语义 |
| v5 | 196 行重建 + X10 | 时间象限 |

v4 §11.5 自评：「**不是在收敛**」——每一版修复在上一抽象层引入新的类级遗漏。  
该自评在 v5 仍适用：**删掉跨时间机制后，立刻钉上一条不可核的元规则当「唯一横切」**——遗漏从「4c′ 类不穷举」换成「操作数/标注不可判定」。

### 正常收敛 vs 错误解法

**正常收敛**的签名：缺陷计数下降、**新缺陷位于更窄的实现边角**、招牌论证可被破坏性反证重复通过。  
**本轨迹**的签名：冲突计数表面波动，**类级洞换层复发**；两次无承载保证（attempt_id、write-time capture）；停止判据正确触发；用户改语义后纸面契约仍塞进第三句无承载保证（X10）。

**指向**:  

1. **产品语义**（写入当轮硬 + 轮内自洽）可以是对的——用户已确认 §11.6。  
2. **解法形态**（主会话独自钉五面共享接口契约 → 多轮确认 → 再综合规格）对这个问题**反复失败**；v5 换确认流程（+异构审）是进步，但**仍先写满元理论再实现**。  
3. 根问题不是「少一个 X10」，而是：**试图用纯函数 + 自签树 + 纸面标注，模拟一个跨时间、对抗性的验收 oracle。**

### 若是后者，我会怎么做

1. **冻结语义，停止扩写元规则。** 用户 A 已够用。删除或降级 X10 为「非 teeth 的审查清单」。§0 改写为**构造约束**（判定链只允许两象限调用），不声称 validate 可判定。  
2. **一条竖切实现 > 五面契约。** 最小可跑：  
   - S3 子集：`evals.json` + due-set  
   - S2 子集：`acceptance-evals.json` + 恒必填 `frozen_*`  
   - S4 子集：`Acceptance evals:` + 「due 缺 ran ⇒ 不得 positive」  
   - 接入既有 `verify_protocol` / coverage，**用破坏性 fixture 当 teeth**（不是标注一致性）  
3. **硬度若要升级，换权力来源，不换纸面。** 例如：宿主在写 `decision.md` 前强制跑门；或探针 runner 出具**非 agent 可写**的 receipt（CI artifact / 签名）；不要再发明第四个「捕获点」。  
4. **方法**: 综合规格前必须有**可红的 fixture**；五面确认只审实现边界，不再审「下一层元定理」。连续类级洞 → 停写契约，先竖切。  
5. **沟通**: 对外改称 **「收盘时序门 + 轮内自洽账本」**，保留「硬门」仅当加限定「写入当轮、协议时序」。

---

## Decisions / deviations

- 将「方向对不对」与「契约文本能否进综合规格」拆开：前者 **条件通过**（写入当轮语义），后者 **REWORK**。  
- 未复跑五面一致性（明确 out of scope）。  
- 未修改任何被审文件。  
- 将 X10 与历史两次无承载声称对齐，作为否决主因之一（高于文风/详略问题）。

## Open questions

1. 用户是否接受对外改名（放弃无限定「硬门」）？若否，最小限定措辞以谁为准？  
2. 竖切是否允许先只做 S2+S4（due/ran/positive），S1/S5 延后——以打破「五面必须齐契约」？  
3. 若需要真·对抗硬度，是否立项「非 agent 控制的 probe receipt」，还是明确永不做、只做审计账本？

## Verdict

**REWORK**

（语义方向：接受用户 A / §11.6 的写入当轮硬门，**PASS_WITH_NOTE 级**；  
契约文本作为权威进综合规格：**REWORK**——§0 不可机械判定 + X10 无实现承载为否决项。）

## Next recommendation

1. **不要**把 v5 原文当综合规格输入。  
2. 出 **v5.1 或勘误页**，仅含：  
   - §0 降为构造约束 + 明确常量/gating/多元操作数规则，或删「可机械核」；  
   - **删除 X10 meta-teeth 声称**（或改为非自动的设计审查项）；  
   - 三线收敛改为「§11.6 充分 + 两线类比」；  
   - 「硬门」一律带「写入当轮」限定。  
3. 并行启动**单面竖切 + 破坏性 fixture**，用代码牙齿替换纸面元牙齿。  
4. 五面确认应基于 v5.1 + 竖切边界，而不是再确认一遍 X10。  
5. 通过后再进综合规格；本异构审对**未修订的 v5** 保持 REWORK。

---

## 附录：关键引用索引

| 声明 | 位置 |
|---|---|
| v5 根规则 + X10 可机械核 | `docs/runtime-evals-interface-contract-v5-20260728.md:19-35,168-173` |
| 写入当轮硬 / 残留自述 | 同文件 §2.5；`docs/runtime-evals-checkpoint-20260728.md` 全文 |
| §11.6 定理 + 三线收敛原文 | `docs/runtime-evals-interface-contract-20260728.md:549-562` |
| 三条绕过 / 捕获点证伪 | 同文件 §11.1 |
| 原需求硬门① | `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md:9-12,100-126` |
| 批 2 机械门边界 | `docs/loop-stop-record-spec-20260728.md:45-73` |
| ignore 换层次 | `docs/ignore-scoping-spec-20260728.md:14-30` |
| Mechanical gate 记录纪律 | `harnessloop/.../harnessloop-loop/SKILL.md:551` |
| validate.py 现状 | `harnessloop/scripts/validate.py:1-18`；runtime-eval 词项计数 0 @ `b389eac` |

## Vendor output (parsed)

```
I'll execute the adversarial review myself: read the v5 contract and the required background, then write the five-question verdict into `.hopper/handoffs/T-079-output.md`.Background docs are in hand. Next I'll check `validate.py` and related source for whether X10 is actually enforceable.Enough evidence for all five questions. Writing the full T-079 adversarial review deliverable.## T-079 complete

Deliverable: `.hopper/handoffs/T-079-output.md` (353 lines)

### Verdict: **REWORK**

| 问 | 判定 |
|---|---|
| **Q1** §0 根规则 | **否决**（作「可机械核」）：操作数边界、常量时间层、多元判定均未定义；不可机械判定 |
| **Q2** X10 meta-teeth | **否决**：`validate.py` 对 `time_layer/operand/X10/frozen_/RAE-` 全 0；与 attempt_id / 写入捕获同形无承载声称 |
| **Q3** 是否放弃需求 | **部分放弃**：放弃跨时间对抗硬；未放弃 runtime 进验收路径；相对静态+单测只多买覆盖种类，硬度≈0 增量 |
| **Q4** 三线收敛 | **部分过度归纳**：§11.6 自洽；ignore 处方是换层仍查，不是认输；口号≠同一操作处方 |
| **Q5** 演进史 | **「不该（只）这样解」**：类级洞换层复发；应竖切+破坏性 fixture，删/降 X10 |

**方向**（写入当轮硬门）可保留；**契约原文**不得进综合规格。  
`## Files touched`: none
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 201702
- end_time: 2026-07-28T08:25:18.571Z
- log: see `T-079-output.log` for raw output
