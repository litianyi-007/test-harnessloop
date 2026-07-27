# 引用豁免机制换层次 — 规格 v4（2026-07-28）

> **v4 不是 v3 的第四版补丁，是换层次。** 收敛守卫在 T-073 触发（同一工作项连续
> 第 3 个 REWORK 批次：T-071/T-072/T-073），主会话按纪律停下向用户 checkpoint，
> 用户裁决 **user-confirmed 2026-07-28：把豁免移出散文**。
>
> v1（`d5de1e3`，精确语法）、v2（`ed7b29c`，行内不变量）、v3（`11e0343`，token 级识别
> + 摘要冻结名单）全文在 git 历史。**它们的共同前提——「豁免是写在散文里、按行定位的
> 自由文本指令」——正是被换掉的那一层**，故不在此复述其细节。
>
> 状态：**规格草案，待对抗审**。实现未开始，机械门仍在 v0.25.0。
> 前置关系：本规格是 **B2b 的硬前置**。

## 1. 为什么是换层次，而不是第四版

三轮对抗审砍掉的东西，形状高度一致：

| 轮 | 砍掉什么 | 病根 |
|---|---|---|
| T-071 | `verify:ignore=<span>` 精确语法：`,` 分隔符与协议自己的多区间 locator `foo.py:10-20,30-40` 冲突，无法无歧义解析 | **在散文里发明一套微型语法** |
| T-072 | 摘要口径未写死、名单可追加、J10/J11 与正文自相矛盾、行内子串检测误伤 | **散文位置语义 + 为它打的补丁本身需要更多补丁** |
| T-073 | 词法仍未闭合、`引用候选` 仍无定义、hardlink 可取得 legacy identity、**`frozen:false` 把 T-072 指出的追加洞原样留着换了个门把手** | **同形缺陷在新边界重现** |

最后一条正是判据本身：**同一工作项连续第 3 个 MUST-FIX 批次 → 停下来问「这个机制是
不是放错了层次」，而不是补第四个洞。** 该判据来自 TH-0008（后缀唯一回退连挨三轮，
最终以 `fixed-by-demotion` 结案）。

**答案是放错了。** 让一个路径检查器去解释「散文里的、按行定位的、自由文本的」指令——
子串误判、行粒度连带、occurrence 歧义、陈旧标记静默失效，全是这个层次的必然产物，
不是可以逐个补掉的洞。

## 2. 新层次：豁免是声明，不是注释

与本项目已两次选择的形状一致：

| 先例 | 隐式的东西 | 变成 |
|---|---|---|
| 外部解析基准（v0.21.0） | 「这条引用其实指项目外」藏在读者脑子里 | `reference-roots.json` 两文件声明 + `@@alias/` 显式语法 |
| 嵌套 root 裁决（v0.24.0） | 「这两个 root 其实重叠」藏在文件系统里 | `nested_under` 显式声明，未声明即 fail-closed |
| **本规格** | 「这条引用不必检查」藏在散文的一行注释里 | **`citation-exemptions.json` 显式声明** |

### 2.1 落点与 schema

每轮一份：`.harnessloop/goals/<goal>/rounds/<id>/citation-exemptions.json`

```json
{
  "version": 1,
  "exemptions": [
    {
      "review": "reviews/T-056-review.md",
      "span": "hermes_agent.egg-info/",
      "reason": "引用的是 .gitignore:59 那一行的内容，不是一个路径引用"
    }
  ]
}
```

- `review`：**相对本 round 目录**的路径，必须解析进本 round 的 `reviews/`
  且不是 symlink（复用既有 `_canonical` / `_is_contained` / symlink 判据）。
- `span`：被豁免引用的**清洗后文本**，与 `cited` 里存放的形式逐字相同。
- `reason`：**非空**。机械门只检非空，**不声称它判断了理由是否充分**——
  与 `Review: none — <理由>` 同一纪律。

**每轮一份而不是全项目一份**：全项目一份会长成一张永久白名单；每轮一份随 round 收口
而冻结，且天然落在 round 目录内。

### 2.2 语义

- 一条声明压制该 `review` 内**所有** `span` 逐字相同的 `dangling-citation`。
- **occurrence 语义是刻意选择，不是遗留歧义**：同一份评审里同一段路径文本出现两次，
  是关于同一个路径的同一个断言；分别豁免其一在语义上没有意义，因此不提供该能力，
  也就不存在 T-071 在 v1 上抓到的那类歧义。
- **无通配、无前缀、无正则。** 逐字比较。硬约束：一旦支持模式匹配，
  它就退回成一张空白支票，本规格的意义归零。

### 2.3 未命中即违规 `citation-exemption-unused`

声明了却没有对应的 dangling 引用 → 违规。

这消灭的是旧机制最阴的失效模式：引用被修好或删掉后，标记留在原地，**继续豁免此后
落到那一行的任何东西**。在声明层，这个模式不再需要"检测"——它就是一条对不上的声明，
下一次运行即红。

## 3. 散文标记整体移除

`<!-- verify:ignore -->` **不再有任何效果**。同时消失的是它带来的全部问题：

| 旧机制的问题 | 在新层次的处境 |
|---|---|
| 子串匹配：「讨论标记」=「启用标记」（v3 §1(c)，已复现的现网假绿） | **不存在**——声明在 JSON 里，散文写什么都只是文本 |
| 行粒度连带豁免（pilot 实测 1 条） | **不存在**——单位是 (review, span)，与行无关 |
| occurrence 歧义 | **不存在**——见 §2.2 |
| 陈旧标记静默失效 | **不存在**——见 §2.3，变成一条会红的声明 |
| legacy 摘要冻结名单、hardlink identity、CI 历史断言（v3 §4 整节） | **整节删除**——见 §4 |

## 4. 迁移：3 个新文件，0 处评审改动

移除散文标记后，Rule B 扫描范围内 3 份历史评审的 8 条引用会变成 dangling。迁移方式是
**为它们各写一份 `citation-exemptions.json`**：

| round | 需声明的 span |
|---|---|
| `20260716-001-setup-wizard/rounds/0001` | `harnessloop-loop/skills/harnessloop-loop/scripts/check_setup.py`、`plugins/harnessloop/` |
| `.../rounds/0002` | `plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py`、`harnessloop-loop/skills/harnessloop-loop/scripts/` |
| `.../rounds/0003` | `plugins/harnessloop/skills/harnessloop-setup/agents/openai.yaml`、`agents/`、`.codex-plugin/plugin.json`、`harnessloop-setup/agents/openai.yaml` |

**这是换层次最大的附带收益**：v3 需要一整节（摘要算法、路径口径、冻结状态机、
CI 历史断言、hardlink identity）来绕开 E1「不得为让机械门通过而修改历史评审」，
而在声明层，**声明是关于文件的、不在文件里**——迁移天然不碰评审一个字节。
v3 §4 整节因此删除。

**如实标注**：这是一次**有迁移的变更**，不是零迁移。violations 会先增 8 条、
写完 3 份声明后回到 0。规格不假装它是零迁移。

## 5. coverage

`coverage_schema` 推到 **2**。

| 字段 | 处置 |
|---|---|
| `citations_ignored_explicit` | **移除**（schema 2）。其口径（数 code span 而非引用）本就在说谎，实测高估 2.3×–5.3×；schema 版本正是让这种移除安全的机制 |
| `review_files_with_ignore` | **移除**（schema 2） |
| `citation_exemptions_declared` | 新增：声明总条数 |
| `citations_exempted_declared` | 新增：实际被声明压制的 dangling 引用条数 |
| `citation_exemptions_unused` | 新增：声明了却没命中的条数（同时报 §2.3 违规；此处保留为可监测量） |

**schema 1 的历史记录不改、不追认、不重算**，但从此可判读。

**一处必须纠正的历史数字**：v3 §6 的 J11b 写「14 → 6」，**错**。正确是 **14 → 8**
（T-073 指出）。主会话的复算方法本身有 bug——`pathish_citations` 内部就会跳过含标记
的行，拿它当探针去测行内标记那一行必然算出 0，漏掉 2 条。这是本会话第 4 个同形测量
错误：**拿一个自带过滤逻辑的函数当探针**。

## 6. 验收（teeth）

| # | 断言 | 破坏性反证 |
|---|---|---|
| K1 | 声明命中 → 该条 dangling 被压制；**同一评审其它 dangling 照常报** | 压制整份评审 → 红 |
| K2 | 声明未命中 → `citation-exemption-unused` | 去掉未命中检查 → 陈旧声明静默存活 → 红 |
| K3 | 散文里的 `<!-- verify:ignore -->` **完全无效**：含标记的行，其 dangling 照常报 | 保留旧路径 → 红 |
| K4 | 散文里 code span 内提到标记（v3 §1(c) 的复现输入）→ 无任何特殊效果 | 同 K3 |
| K5 | `span` 逐字比较：声明 `build/` 不匹配 `kernels/hermes/build/`，也不匹配 `Build/` | 引入任何模糊匹配 → 红 |
| K6 | 通配拒绝：声明 `*.md` / `build*` → 不匹配任何引用 → `citation-exemption-unused` | 引入模式匹配 → 红 |
| K7 | `review` 指向本 round `reviews/` 之外、或是 symlink → 拒绝该条 + 报 `citation-exemption-path-rejected`，**不压制任何东西** | 只比字符串 → 声明成为跨 round / 跨项目压制通道 → 红 |
| K8 | `reason` 为空或缺失 → schema 错误，**整份声明不生效**（all-or-nothing，同 `reference-roots.json`） | 允许空理由 → 红 |
| K9 | 一份声明只作用于本 round：round A 的声明不压制 round B 的同名 span | 全局匹配 → 红 |
| K10 | 迁移后全项目 **0 违规**；且**移除 3 份声明中的任意一份 → 恰好红回该 round 的那几条** | 声明不起作用 / 起过头 → 红 |
| K11 | `coverage_schema == 2`；`citations_ignored_explicit` 与 `review_files_with_ignore` **不再出现** | 残留旧字段 → 红 |
| K12 | occurrence：同一 span 在同一评审出现 2 次且都 dangling → 一条声明压制两条（§2.2 的刻意选择） | 只压第一条 → 红 |

## 7. 已知代价（如实登记）

- **要多写一个文件。** 旧机制敲一行注释即可。这是换层次的真实成本，不掩饰。
  缓解：豁免本就罕见（pilot 实测 7 份评审共 3 条）。
- **有迁移**（§4）：3 个新文件。不是零迁移。
- **声明与评审分离，读评审的人看不到「这条被豁免了」。** 缓解方向（本规格不做）：
  违规 detail 或 round 收口时提示"本轮有 N 条声明豁免"。列为后续独立议题。
- **`citations_ignored_explicit` 被移除**，任何读历史 coverage 的工具须按
  `coverage_schema` 分支。

## 8. 显式不做

| 提案 | 理由 |
|---|---|
| 保留散文标记做双机制 | 双机制意味着 (c) 的子串 bug 必须继续维护，且两套语义会漂移。换层次的收益正来自**只剩一层** |
| 通配 / 前缀 / 正则 span | 空白支票换个写法 |
| 全项目一份豁免文件 | 会长成永久白名单；每轮一份随 round 冻结 |
| 分别豁免同一 span 的不同 occurrence | §2.2：语义上无意义，且正是 v1 被否决的那类歧义 |
| 强制理由须"充分" | 机械门只检非空，不声称判断充分性（同 `Review: none —`） |
| 对 `citation_exemptions_declared` 直接设阈报违规 | 阈值由 B2b 重新预登记决定；本规格只负责测准并暴露 |

## 9. 给对抗审的靶子

> **背景**：本工作项前三版连挨 3 轮 REWORK，收敛守卫已触发一次，用户裁决换层次。
> **v4 是换层次后的第一版，不是第四个补丁。** 请照常判——若 v4 本身仍不闭合，
> 说明换层次也没救对，那是必须知道的事。

1. **§2.2 的 occurrence 选择**：把「同一 span 的全部 occurrence 一起豁免」定为刻意
   语义，是否真的没有反例？构造：同一路径文本在一份评审里，一处是真引用、一处是散文
   举例。
2. **§2.1 的 `span` 口径**：要求作者写「清洗后文本」。作者怎么知道清洗后长什么样？
   `\` → `/`、`strip()` 之外还有别的吗？未命中时的 detail 是否必须打印实际的 `cited`
   列表以便作者自纠？
3. **§4 的迁移是否真的不碰评审**：写 3 份 `citation-exemptions.json` 会不会触发
   Rule A？——注意 pilot 已发现 **6/7 的 scope-lock 覆盖不到自己的 round 目录**
   （报告 §5.2）。这两件事会不会撞车？
4. **K7 的路径检查**是否足够：hardlink？大小写不敏感卷？`reviews/` 本身是 symlink？
5. **移除 `citations_ignored_explicit` 是否过激**：历史 `decision.md` 逐字记录了它。
   schema 分支是否足以让那些记录仍可判读，还是应保留字段并置 0？
6. **换层次是否真的消灭了那一族问题，还是把它们搬进了 JSON**。请独立判断：
   §2/§3 声称「不存在」的四类问题（子串误判、行粒度、occurrence 歧义、陈旧标记），
   在声明层是否真的不存在，还是换了形态。**这一问允许判定换层次失败。**
