---
phase: done
last_progress_at: "2026-07-27T19:32:13.051Z"
last_progress: Task completed successfully.
progress_seq: 10
last_stream_event: process_alive
last_update: "2026-07-27T19:32:08.577Z"
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
end_time: "2026-07-27T19:32:13.050Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 244485
adapter_status: success
terminal_event_emitted: true
---
# T-074 对抗核实：runtime-evals/自主化审核报告

**Task-type**: `code-review-adversarial`（只读；不改被审对象）  
**评审对象**: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（commit `c40ff73`）  
**对照**: harnessloop submodule `b389eac` / v0.26.0；实践语料 `.harnessloop/`（goal 001: 4 轮 + goal 002: 10 轮 = **14** 轮，非报告页眉写的 20）  
**评审者**: grok（hopper dispatch execution agent）  
**时间**: 2026-07-28

---

## Summary

对审核报告的 7 个 GAP 做了源码级证据复核：核心断裂判断（散文概念有、机械门盲）成立，两处「翻转初判」的实质引文也站得住。但报告有可核对的计数/行号瑕疵，对 8 条「已具备资产」的可迁移性偏乐观（尤其 B2a「先入账后硬门」与 reference-roots 扩到服务端点），且遗漏了多处会直接卡住「配置化外部系统 + runtime evals 硬门 + 单会话自主 loop」的点——其中「eval 由谁执行」与 check_setup/声明文件关系最关键。总体：**GAP 清单可作立项输入，但须并入本报告的遗漏与分步风险后再做 EV 裁决**。

## Files touched

none（只读评审；本文件为交付物，不计入被审变更）

## Acceptance verification (4/4)

### 1. 证据核实 — **PASS_WITH_NOTE**

逐 GAP 核对 file:line 与「结论是否跟随证据」：

| GAP | 证据真实性 | 结论跟随 | 注记 |
|---|---|---|---|
| GAP-1 | **PASS** | **PASS** | `data-sources-template.md:16-24` 两表自由文本成立；`check_setup.py` 只查表是否「填没填」、不解析单元格；setup SKILL 明文 data-sources 排除 gate-blocking 三文件（setup SKILL.md ~:129）成立。**NOTE**: 报告写「读 data-sources.md 的只有 check_setup.py 与 init_project.py」过窄——`channels`/`connectivity`/`secrets` SKILL 协议层也要求读该文件；准确说法是「**没有任何代码解析表格内容**」（报告后半句是对的）。 |
| GAP-2 | **PASS** | **PASS** | `thresholds-template.md` 三表列名存在；本项目实例 `goals/20260718-002-agent-app/thresholds.md` Runtime 表（约 :30-38 一带，现文件 Runtime 节在 Verification 之后）确有 server API / wire event / 内核健康等行；`goal-breakdown-template.md:16`「Runtime validation options」与 subgoal `Validation method` 列为散文成立。**NOTE**: 报告对 Verification 表列名有时缩写为四列，实际为六列（含 Threshold / Applies to）；不伤「列名≈契约形状、无 schema/解析器」结论。 |
| GAP-3 | **PASS** | **PASS** | `decision-template.md` 无 Evals/threshold 结果字段（仅有 Review× / Mechanical gate 等）；`verify_protocol.py` 对 `eval` 的命中仅为 PATHISH 前缀 `evals/`（:310）与英文 `evaluated`（:1647）——**2 处**，报告写「3 处」略虚，但「机械门对 runtime eval 零感知」成立。loop SKILL.md:442 把 thresholds 划在模型判断层成立；step 1 机械否决（:551）与 step 3 Review 字段（:553）不含 eval 成立。 |
| GAP-4 | **PASS**（实质）/ **NOTE**（行号与条数） | **PASS** | **关键引文复核**：loop SKILL.md **:556** step 6「If feedback is positive and the goal is not achieved, continue to the next subgoal or task」+ **:560-567**「Stop only when」清单——「等用户敲 continue」**不在**清单内。报告写 `552-567` 把 step 2（round_cost）也包进去了，行号偏宽；清单是 **6 条** 不是报告说的「五条」。实质翻转「协议要求自续、真卡在停止无痕」**成立**。Core Contract :65 亦有同向「Only stop the loop when…」。实践：`state/current.md` Next proposed action 以「下一 continue 开 SG-…」收尾属实；**轮数应为 14 不是 20**（见下）。 |
| GAP-5 | **PASS** | **PASS** | continue SKILL.md:46 条件式 write-safety-required vs :36 step 9 无条件 external mutation 停人——矛盾成立。`control-contract-template.md:25` 与 `control-contract-profiles.md:30` 三档均对「Irreversible or external-system write」= required 成立。本项目 `state/control-contract.md:22` git push 预授权例外手写条款存在，可作「预授权词汇能用、缺结构」的实践证明。 |
| GAP-6 | **PASS** | **PASS_WITH_NOTE** | 事故档案 `docs/security-incident-20260726.md` 确认探针 evidence 原样写真实配置；插件树无扫描器/脱敏实现；本仓 `scripts/check-secrets.sh` 不随插件走——成立。**NOTE**: 档案 §7 建议 1 原文指向 **hopper 写端**脱敏；报告 GAP-6 主线是 harnessloop evidence 路径（合理扩展），但与 §5「hopper 侧不在本审核对象」有轻微张力——应明确两条链（evidence 写端 vs vendor 日志写端）而非共用同一条「§7 建议 1」。 |
| GAP-7 | **PASS** | **PASS** | `init_project.py:35` 落 `.harnessloop/evals/matrix.md`；loop SKILL.md:545「The eval matrix is not a runtime gate by itself」；PATHISH 含 `evals/`（:310）。命名冲突判断成立。 |

**两处翻转初判的专项结论**：

1. **loop SKILL.md 是否构成「协议要求单会话多轮自续」？**  
   **是（散文协议层）**。step 6 明示 positive 且 goal 未达成则 continue；Stop-only 穷举不含「等人敲 continue」。这是对 **仍在同一会话内执行协议的 agent** 的指令，不是宿主调度器保证——报告把「语义已有、teeth 没有」定成 GAP-4 正确；不宜再读成「已有可执行的多轮运行时」。

2. **thresholds-template 三表列名是否如报告所述？**  
   **大体是**。三表（Data / Verification / Runtime）存在；Runtime 五列与报告一致；Verification 实际多 Threshold、Applies to 两列。资产条「列名正确、差 schema」可保留。

**横切计数错误（应修）**：页眉「20 轮」与 GAP-4 正文「goal 002 全部 10 轮 + goal 001 的 4 轮」自相矛盾；磁盘为 **4+10=14**。`20/20 轮由人工推进` 应改为 `14/14`（方向仍对：未见协议层自续落痕）。

### 2. 反向核实「资产清单」— **PASS_WITH_NOTE**（多条资产需降级表述）

| # | 报告声称 | 反向核实 |
|---|---|---|
| 1 | `evidence/runtime/` 目录已在轮结构 | **可用作约定落点，不是能力**。目录在 loop SKILL.md:343 列出；Rule A 只在有文件时做 containment。空目录 + 无 schema ≠ runtime eval 就绪。**保留为弱资产**。 |
| 2 | thresholds 三表列名正确 | **成立**（见上）。实践已填 Runtime 行，机器未读。**保留**。 |
| 3 | reference-roots 两文件模式可同形扩到服务端点 | **迁移性被高估**。`expect_present` 是 **磁盘路径 sentinel 身份确认**（文件/目录存在），不是 HTTP/TCP 探活；reference-roots 语义是 **外部树 citation 解析**（`@@alias/relpath`），不是「声明系统 → 绑定本机 endpoint → 允许测试写/清理」。服务端点没有文件 sentinel 同构物；「available」语义从 samefile/stat 变成活探针（失败模式、超时、鉴权、非幂等副作用）完全不同。可复用的只有：**声明/本机绑定分离、versioned 零绝对路径、fail-closed、coverage 可见、不泄本机路径** 等纪律，不是代码同形搬迁。**应降为「纪律可借、机制不可照搬」**。 |
| 4 | B2a wiring 证明「先入账后硬门」可行 | **只证明了入账，没证明硬门**。B2a（v0.17）=`parse_review_fields`/`check_review_declaration`：字段存在 + 路径 containment/非 symlink；**明确不读 Review 内容、不对 Feedback 一致性否决**（loop SKILL.md:466 划 B2a/B2b 边界）。T-066 路径是「只入账 → pilot → 再 B2b」，且 B2b 至今 pilot-gated。对用户裁决 ①「evals=硬门」，把「字段先挂上」当成已验证的硬门分步，会 **正常化**「声明了没跑」假绿。接线形状（字段+解析+coverage）可借鉴；**硬门一致性否决仍是未验证工作**。 |
| 5 | runtime-recoverable 自动恢复轮 | **存在且有限**。continue:35 / loop:184 仅允许 **只读**调查/证据刷新/cleanup-plan **起草**；runtime eval 常需 test-resource 写（与 GAP-5 冲突）。对 e2e 自主化帮助窄。**保留为恢复路径资产，不写成 eval 执行路径**。 |
| 6 | control-contract auto-continue + push 例外 | **词汇骨架与手写先例在**；机器不解析 auto-continue 条件，也不执行预授权分支。push 例外是散文特例，恰证明 GAP-5「缺结构」。**保留为先例，不是可复用实现**。 |
| 7 | channel-params + secrets skill | **纪律在、写端机械守门不在**。事故仍发生在该纪律存在之后（子代理写 evidence）。与 GAP-6 一致：资产是参数名引用习惯，不是 evidence L1 比对。**半资产**。 |
| 8 | 「Round acceptance never delegate」兼容硬门 | **矩阵行成立**（loop SKILL.md:419）。但同表 **Acceptance testing = Should delegate**、**Evidence collection** 可委派——报告用「裁决权在主会话」掩盖了 **「谁跑 eval 命令/探针」** 未建模的问题。兼容性成立 ≠ 执行拓扑已清晰。 |

### 3. 审核遗漏 — 见下方独立节 **## 审核遗漏**（本项 **FAIL→报告缺口**；遗漏本身已补全于本交付物）

任务要求从若干面找「会卡 R1–R5 的点」：报告原件 **未覆盖** round_cost 交互、eval 执行者、handoff 堆积与 auto-continue 的耦合、check_setup 与新声明文件、intake 路径、strict 档与自续冲突等。**作为「卡点清单完备性」判据：原报告 FAIL；作为对抗审交付：遗漏已在本文件独立成节列出。**

### 4. 依赖图与分步判断 — **PASS_WITH_NOTE**

**依赖图（EV-A..G）**：

```
GAP-7 ──先行          合理（命名零依赖）
GAP-1 + GAP-2 ──→ GAP-3   合理（硬门要有系统载体 + 结果 schema）
GAP-5 ↔ GAP-1         合理（预授权绑定已声明系统）
GAP-4 独立并行        大体合理；与 continue 重入、round 预算/cost 有弱耦合
GAP-6 独立且应先于大规模 e2e   合理
```

**遗漏的依赖边**（应补进图，不必否定原图）：

- **GAP-3 →「eval runner 契约」**（见遗漏 O-1）：硬门只能核对产物；产物由谁、在何权限边界产生未定义，则 EV-D 可能空转。
- **GAP-4 ↔ round_cost / cost-context**（O-2）：多轮自续放大每轮强制 cost 结算与上下文压力，却无「预算到点合法停」机械链。
- **GAP-1 新文件 ↔ check_setup FILES_ORDER / gate_blocking**（O-4）：声明文件落点会改变 setup 完备性语义。
- **GAP-5 / 预授权 ↔ 委派矩阵写边界**（O-3）：eval 若委派执行，handoff 必须携带预授权范围，否则子代理要么停人要么越权。

**「GAP-3 走 B2a 式先入账后硬门」是否成立？**

- **形状层：可分步。** 字段 + 路径存在性 + schema 合法性 可先接线，与 B2a 同形。
- **硬门语义层：裸「先入账」危险。** 用户裁决 ① 已把 eval 定为硬门。若阶段一只要求 `Evals:` 字段存在、允许 `none — <理由>` 且 **不** 核对「本轮到期 threshold-id 是否全部 ran」，则「声明了没跑」假绿被 **协议背书** 地保留——比现状更糟（现状至少没有「我已声明 eval」的假账本）。B2a 之所以可先入账，是因为评审社会实践已在 `.hopper/handoffs` 大量存在、入账主要消灭「有评审无账」；runtime eval 实践是「thresholds 有行、常不跑/不入 decision」，入账若可 `none` 逃逸，等于给假绿开正规出口。
- **更安全的分步（对抗建议）**：  
  - **D0**：命名（EV-A）+ 结果文件 schema（EV-C 子集），无 gate。  
  - **D1（最小 teeth，仍叫入账）**：`Evals:` 必填；若 goal `thresholds.md` 存在带 Evidence path/Command 的到期行，则不得用空 `none` 除非 `none — deferred:<id-list>` 且 deferred 集合机器可解析；结果文件路径 containment + schema。**缺 ran 记录 → 不得 positive**（这已是硬门的一半）。  
  - **D2**：pass/fail 与 Feedback 一致性；thresholds 内容摘要进 coverage 防同轮改判据。  
  - 不要宣传「纯 B2a 只入账」为已验证安全路径。

## 审核遗漏

下列点会卡住「配置化外部系统 + runtime evals 硬门 + 单会话自主 loop」，**原报告未单列**（或部分被一笔带过）：

### O-1. eval 执行者未建模（主会话 vs 子代理 vs 外部命令）— **最严重遗漏**

- 协议有：Acceptance testing「Should delegate」、Evidence collection 可委派、External connectivity「Usually keep in main / `$harnessloop-connectivity`」、Round acceptance never delegate。
- **没有**：「本轮 threshold-id X 的 Command/check 由谁在什么 cwd/凭证边界执行、stdout 落哪、失败如何变成 ran=fail」。
- 硬门（verify_protocol）**只能读产物**；若执行仍靠会话临场编排，则 EV-D 只是把临场结果多写一个 JSON——假绿从「没字段」变成「字段写 none / 伪造 pass」。
- **卡点定性**：执行拓扑缺失（协议 + 可能的 runner 脚本缺口），与 GAP-2/3 同级，应进依赖图。

### O-2. `round_cost.py` 与多轮自续的交互

- Loop Continuation step 2（loop SKILL.md:552）在 claude-code 环境 **强制** 每轮跑 `round_cost.py` 并粘贴 `## Cost`；脚本依赖本机 transcript + `cost-marker.json` 结算窗口。
- 单会话多轮自续 ⇒ 连续结算、marker 推进、成本可观测——但 **没有任何「预算触顶 → 合法 checkpoint 停」的机械链**（GAP-4 提到上下文/成本压力缺词汇，未点名与 step 2 强制脚本、marker、以及实践中大量 `Cost: unavailable` 的组合）。
- 本项目多轮 `round-summary.md` 常见 cost unavailable（子代理/回写会话无 transcript 窗口）——自续若跨子代理执行，**成本账本系统性失真**，反而削弱「用预算约束自续」的前提。
- **卡点定性**：观测已有、止损没有；跨会话执行时观测还假。

### O-3. 委派矩阵对 eval 执行者的约束未展开

- Runtime eval 常需 **非只读**（建测试 token、打真实 API、删自建资源）→ 触碰 write-safety / GAP-5，与「Evidence collection: 仅当 bounded and read-only」冲突。
- 若 eval 走 Acceptance testing 委派：brief 必须含预授权系统 id、允许操作类、清理契约、证据路径——**今日 handoff 模板无这些字段的机械要求**。
- 若 eval 留主会话：与「保护主会话上下文」的 cost-context 政策冲突，多轮自续更易爆上下文。
- **卡点定性**：矩阵有行，无「runtime-eval 执行」专用行；与 GAP-5/O-1 耦合。

### O-4. handoff 机制在自主多轮下的堆积

- control-contract Auto-Continue 条件含 **Open handoffs: 无 open 阻塞**（本项目实例与模板骨架皆然）。
- Loop Continuation step 4 要求 archive closed handoffs；self-audit 有 handoff stagnation。
- 自主多轮 + 每轮对抗审 handoff（实践上大量评审在 `.hopper/handoffs`，round 内 handoffs/ 有时很瘦）——若 open handoff 未关，**auto-continue 散文条件不满足**，自续合法停或静默违例，皆无 stop-record（接 GAP-4）。
- **卡点定性**：自主性与 handoff 门闩的耦合未写进卡点清单。

### O-5. check_setup 五文件门与新增声明文件的关系

- `check_setup.py` `FILES_ORDER` 固定五文件：environment / data-sources / cost-context-policy / control-contract / self-check；`GATE_BLOCKING_FILES` 仅三文件（environment、control-contract、cost-context-policy）。
- `reference-roots.json` **已不在** MANIFEST 中——先例是「新声明文件可完全游离于 setup 完备性」。
- EV-B 若新增 external-systems 声明：要么挤进 data-sources（继续散文）、要么新 JSON（是否 gate_blocking？是否 wizard 第六步？缺失时 complete/warning 语义？）。
- 报告 GAP-1 改进方向未回答 **setup 门如何感知新文件**；若仿 reference-roots 游离，则「系统未声明」可能只在 verify 时 fail-closed，setup 仍显示 complete——运维体验与「配置化」目标不一致。

### O-6. intake 路径

- 既有会话 takeover：intake-gate → intake-review → 正式 goal；要求外部工具/权限/凭证描述，**不要求** runtime eval 结果 schema 或 threshold 映射。
- 若未来「带着已跑过的 e2e 证据」intake：如何导入 `eval-results`、哪些 threshold 算已 ran、新鲜度如何——空白。单会话主线之外，intake 是第二条进入 loop 的口子，硬门必须定义，否则假绿从 intake 绕入。

### O-7. `channels` / `connectivity` 中间层被低估

- 二者协议上已读 data-sources 并做 inventory / 声明式探活（仍靠模型，无表格解析器）。
- 报告把桥完全画成「无」容易导向「从零发明 EV-B」；更精确是：**有 agent 技能层 inventory/probe 约定，无机器 schema 与 continue/verify 接线**。改造应决定是强化这两 skill 的结构化 I/O，还是另起 JSON 声明——避免三套登记（data-sources 表、channels 输出、新 JSON）。

### O-8. control-contract **strict** 档与「单会话多轮自续」直接冲突

- `control-contract-profiles.md:9,19`：strict 下即使一切 automatic 条件满足，**下一 subgoal 仍要人确认**。
- 用户裁决 ② 主线是单会话多轮自续。对选了 strict 的项目（外部系统/敏感数据——恰是 runtime eval 场景），**协议 profile 层已禁止散文式 auto-continue**。报告未区分 lite/standard 可自续 vs strict 不可，导致 EV-F 与 profile 体系可能对撞。

### O-9. scope-lock「Verification commands or checks」与 thresholds 双登记

- scope-lock 强制字段（loop SKILL.md:356）与 thresholds 表可能描述同一检查，无 ID 对齐、无哪份为准。
- 硬门若只读 thresholds 或只读 scope-lock，会出现「一轮过门、另一份契约漂移」。应与 GAP-2/3 一并规定 **单一到期集合** 的来源。

### O-10. 机械门「不跑命令」的边界

- `verify_protocol.py` 设计边界是路径/声明/coverage，**从不执行**业务验证命令（与 thresholds「Command/check」列目标能力正交）。
- 报告暗示接上机械门即硬门，但未写明：**硬门 = 核对 eval 结果账本，不是内嵌 test runner**。否则读者会误期待 verify_protocol 直接 curl 服务端点——那是另一类改造面（权限、网络、非确定性、时长）。

## Decisions / deviations

- 假设：被审对象以工作区当前 `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md` + git log `c40ff73` 为准；submodule HEAD `b389eac` 与报告一致。
- 轮数按磁盘 `rounds/` 目录计数（001→4，002→10）；不把非 round 文档算进「20 轮」。
- 对抗审不修改审核报告正文；遗漏与分步风险仅写入本交付物。

## Open questions

- EV-D 最小可接受 teeth 是「到期 threshold 必须 ran」还是必须等到「pass/fail↔Feedback 一致」才算满足用户裁决 ①？
- external-systems 声明落 data-sources 结构化扩展，还是独立 JSON（仿 reference-roots）？是否进入 gate_blocking？
- runtime eval 默认执行者：主会话 / 只读子代理 + 主会话写 / 预授权子代理写——产品默认选哪个？
- 本项目 profile 意图是 standard 还是「standard + 外部系统」？若实质接近 strict，自续主线是否应降级为「checkpoint 密、人确认密」？

## Verdict

**PASS_WITH_NOTE**

核心 7 GAP 与「散文有、机械盲」总判经得起源码与语料复核；两处翻转初判实质正确。不得给 PASS 的原因：轮数自相矛盾、资产迁移性偏乐观、硬门分步建议在用户裁决 ① 下不安全边界未写清，以及 **O-1..O-10 类完备性缺口**（尤其 eval 执行者与 setup/新文件关系）。不给 REWORK 的原因：既有 GAP 无需推翻重写，遗漏可并入修订附录或 EV 规格前置条件，不阻断「以本报告 + 本对抗审」进入用户裁决。

## Next recommendation

1. **作者修订（小）**：页眉 20→14；Stop 条数 五→六；GAP-4 行号改为 :556-567；verify_protocol eval 命中数；GAP-1「唯一读者」措辞；GAP-6 与 hopper §7 链拆分。  
2. **作者修订（中）**：资产 §3 降级 reference-roots / B2a 表述；§4 分步改为上文 D0–D2；依赖图补 O-1/O-2/O-5 边。  
3. **用户裁决前**：将 **O-1（eval runner）** 与 **GAP-3** 绑定讨论；**GAP-6 先于** 大规模自主 e2e；**EV-F** 显式写清与 lite/standard/strict 的兼容矩阵。  
4. **不要**在仅有 `Evals:` 字段、无「到期必须 ran」teeth 时宣称已满足硬门裁决 ①。  
5. 本文件可直接作为异构对抗审附录挂到审核报告 §6「独立复核」下，无需改 harnessloop 源码。

## Vendor output (parsed)

```
I'll adversarially verify the autonomy audit report against the harnessloop source and practice corpus, then write the review deliverable.I'll verify the report's critical citations against harnessloop source and practice corpus next.Pulling exact cited line ranges and checking reverse-claims against the source.I have enough evidence. Writing the adversarial review deliverable.## T-074 complete

Adversarial verification is written to `.hopper/handoffs/T-074-output.md`.

### Verdict: **PASS_WITH_NOTE**

**What holds**
- All **7 GAPs** are real; the core claim (“prose has it, mechanical gates are blind”) follows the source.
- Flip #1 is right: loop SKILL.md **:556** + **Stop only when :560–567** does require in-session multi-round continue; “wait for user continue” is not a stop reason.
- Flip #2 is right: thresholds **three tables** exist with the right column *shape* (Verification has two extra columns the report sometimes drops).

**Material notes**
| Issue | Detail |
|---|---|
| Round count | Header says 20; body says 10+4; disk is **14** |
| Line range | Claimed 552–567 includes `round_cost` step; substance is **556–567**; stop list is **6** items, not 5 |
| Assets overstated | **B2a only proved accounting**, not hard-gate; **reference-roots ≠ service health** (`expect_present` is disk sentinels) |
| Staging risk | Pure “field first, hard gate later” is **unsafe** under user decision ① unless due thresholds must `ran` |

**审核遗漏 (new section in output)** — highest value: eval **runner topology** unmodeled; `round_cost` vs multi-round self-continue; handoff open vs auto-continue; check_setup vs new declaration files; intake path; strict profile vs self-continue; who executes evals.

**Files touched:** none (review-only).
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 244485
- end_time: 2026-07-27T19:32:13.050Z
- log: see `T-074-output.log` for raw output
