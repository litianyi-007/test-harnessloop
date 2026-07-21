# Leader Tasklist

Full task specs live here. Each task in `queue.md` references a section below by
its ID (the dispatcher pulls this section as the task spec).

---

## T-EXAMPLE-001

**Goal**: Describe what to build or verify in one or two sentences.

**Acceptance criteria** (prefer machine-checkable — a shell command or grep that proves each):
1. ...
2. ...

**Files allowed to touch** (positive scope): ...

**Files MUST NOT touch** (negative scope): ...

**Budget**: time and vendor-cost ceiling.

---

## T-001

**Task-type**: `code-review-adversarial` · **Vendor**: codex (随机结果，见 `.hopper/AGENTS.md`)

**Goal**: 对 `/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop/harnessloop`
仓库的 commit `6936fbc`（setup wizard 完整实现：新 `harnessloop-setup` skill +
`check_setup.py` + `control-contract-profiles.md` + 四个既有 SKILL 的接线改动 +
`scripts/validate.py` 新增第 3 阶段）做一次**只读**对抗评审，不修改任何文件。

**评审对象**：
- Commit: `6936fbc63497ba7619acaccc177a13c976f4202e`，取 diff 用
  `git -C harnessloop show 6936fbc`（或 `git -C harnessloop show --stat 6936fbc`
  先看改动文件清单）。
- 涉及文件（相对 `harnessloop/` 仓库根）：
  1. `plugins/harnessloop/skills/harnessloop-setup/SKILL.md`（新增）
  2. `plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py`（新增）
  3. `plugins/harnessloop/skills/harnessloop-loop/references/control-contract-profiles.md`（新增）
  4. 四个既有 SKILL 的接线改动：
     `plugins/harnessloop/skills/harnessloop-continue/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-init/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-loop/SKILL.md`、
     `plugins/harnessloop/skills/harnessloop-status/SKILL.md`
  5. `scripts/validate.py`（新增 stage 3）

**评审焦点**（按重要性排序）：
1. **`check_setup.py` 的判定算法边界**：字段切片匹配逻辑、TODO/none-哨兵正则
   的边界条件（漏检/误检）、`gate_blocking` 判定的两档（模板/缺失 vs
   advisory-complete）是否有遗漏或误判分支。
2. **SKILL 文本与脚本行为的一致性**：`harnessloop-setup/SKILL.md`、
   `harnessloop-status/SKILL.md`、`harnessloop-continue/SKILL.md` 等文本描述
   的行为，是否与 `check_setup.py` 的实际输出（`--json` 契约、exit
   码 0/1/2、字段计数）一致，有无文档与实现漂移。
3. **`scripts/validate.py` 新增断言的证伪力**：新 stage 3 的 28 项断言是否
   真能在对应缺陷注入时失败（而非无论实现对错都通过的"假阳性绿灯"）。
4. **Python 3.9 兼容性**：`check_setup.py` 及 `validate.py` 改动是否使用了
   3.9 之后才引入的语法/标准库特性（本机 `python3 = 3.9.4`，见
   `.harnessloop/setup/data-sources.md` 底部注）。

**Read-only 要求（硬约束）**：
- 不得修改、创建或删除 `harnessloop/` 仓库或本仓库中的任何文件。
- 结论写入 hopper 产物文件——由 hopper 自动落盘到
  `.hopper/handoffs/T-001-output.md`，不要求 codex 自行创建该路径以外的文件。
- 结论中每一条问题必须引用具体 `文件路径:行号`（例如
  `plugins/harnessloop/skills/harnessloop-loop/scripts/check_setup.py:123`）。
- 语言：中文或英文均可。

**Files allowed to touch**：无（本任务是只读评审，不写任何文件；产物由 hopper
落盘机制处理，非评审者本人写文件）。

**Files MUST NOT touch**：`harnessloop/` 仓库全部文件、本仓库（test-harnessloop）
全部文件——评审者不得对任一文件做写操作。

**Budget**：单次 codex 评审，正常优先级；无额外时间/成本上限设定，超时按
hopper 默认 timeout 处理。

**元目的（本任务的第二重目标）**：本任务同时用于验证 hopper 的 codex 评审通路
本身是否可靠。评审完成后，派发方必须对照
`hopper-plugin/ISSUE-codex-review-hijack.md` 记录的已知问题，核对以下三项
（详见 `.hopper/AGENTS.md` 的"Codex 评审强制核对"一节）：
1. 实际审查对象是否确为上面列出的 commit `6936fbc` 及其涉及文件，而非被全局
   skill 劫持后审查的其他仓/其他 diff。
2. 产物是否落在 `.hopper/handoffs/T-001-output.md`，而非 codex 自身 skill
   约定的其他路径。
3. 不得仅凭 `adapter_status: success` / exit 0 / codex 自述完成即采信——以上
   两项核对通过之前，本任务视为未完成。

---

## T-002

**Task-type**: `prd-research` · **Vendor**: grok（研究主力，用户决策 2026-07-17）· **只读研究**

**背景（架构已定，勿推翻）**：一款仿 codex app 的 agent app，agent 内核在**客户端本地**运行（不在 server 跑）；所有内核 LLM 调用统一经 **newapi 网关**。因此 server 是一个**瘦业务控制面**，不承担 agent 计算。

**研究问题**：为这个瘦控制面 server 做技术选型调研。它需支撑：
1. License 管理（个人免费 / 企业付费；签发·校验·吊销）
2. 多租户（tenant 隔离）
3. 收费坐席（per-tenant seat 计费）
4. 租户级能力开关（plugin 开关 / skill 开关，下发到客户端）
5. 费用管理（消费 newapi 回传的用量数据做计费/账单）
6. newapi 集成与系统管理员设置面（供 console 调用）
关键约束：**开发者不是 server 专家**——优先生态成熟度、低运维负担、现成的多租户/认证/计费库、可维护性；成本敏感（倾向可自托管、开源、低资源）。

**产出要求（写入 output.md）**：给出 2-3 个**现实可落地**的技术栈方案（每个含：语言+框架+数据库+认证方案+多租户实现方式+计费实现路径），逐一列 tradeoff（学习曲线/生态/运维/成本），最后给一个带理由的推荐。每个关键论断引用来源（URL）。web search 开启。诚实标注不确定处。

**Read-only**：不修改任何文件，结论由 hopper 落盘到 `.hopper/handoffs/T-002-output.md`。语言：中文。

---

## T-003

**Task-type**: `prd-research` · **Vendor**: grok（研究主力）· **只读研究**

**研究问题**：调研以下 agent 内核与网关项目的**真实当前形态与集成接口**，为设计一层能同时跨越"本地进程型内核"与"SDK 型内核"的内核抽象（P2 窄腰）建立事实依据：
1. **openclaw**：确认它是什么（编码/agent 内核？）、最新稳定分支、如何被外部控制或嵌入（stdio/IPC/CLI/API？）、会话与流式输出/工具调用/审批的接口形态
2. **hermas**：确认它是什么（与 openclaw 相似的项目？）、集成接口形态
3. **new-api / newapi**：确认它是 one-api 式的 LLM 网关吗、其用于用量统计/计费/模型管理的 API、如何作为统一 LLM 入口
4. **codex app sdk** 与 **claude code sdk**：各自如何暴露 agent 能力——会话生命周期、流式、工具调用、审批（human-in-the-loop）
**目标**：识别每者的真实"集成面"，据此判断一个统一抽象的最小契约（会话 start/send/interrupt/stop、流式订阅、工具协商、审批回调、能力声明）在各内核上如何落地、哪里对不齐。

**产出要求（output.md）**：逐项给出确认到的事实（附来源 URL）；对每个内核标出其集成模型（本地进程 vs 托管 SDK）与关键接口；给一张"抽象窄腰 × 各内核落地/缺口"的对照。**信息稀缺处必须诚实标注"未能确认"，不得臆造接口**。web search 开启。语言：中文。

**Read-only**：不改文件，结论落盘 `.hopper/handoffs/T-003-output.md`。

---

## T-004

**Task-type**: `code-review-adversarial` · **Vendor**: codex（掷签结果，见 `.hopper/AGENTS.md`）· **只读设计评审**

**评审对象（绝对路径，在本仓库之外）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec.md`（356 行，D1 KernelPort 内核窄腰设计 spec）。
事实基线（同目录，供核对）：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md`（openclaw/hermes/new-api/codex-sdk/claude-sdk 的真实接口，含「未能确认」标注）。

**任务**：对这份内核抽象窄腰设计做一次**对抗性设计评审**，目标是证伪、找硬伤，而非背书。重点攻击面：
1. **窄腰是否真跨四内核**：逐一检验 openclaw(WebSocket JSON-RPC Gateway)/hermes(CLI+Gateway+ACP stdio)/codex-sdk(Thread/Turn JSON-RPC)/claude-sdk(进程内 query()+canUseTool) 上，7 个 KernelPort 方法能否落地；对照表有没有把「未能确认」当「能落地」。
2. **审批归一是否死锁**：Claude canUseTool 同步回调桥接成异步 approval_request+respondApproval，超时/竞态/与 Hooks 改写 input 的一致性。
3. **interrupt/steer 降级责任归属**是否自洽、有没有把难题踢给未定的 P3。
4. **newapi 边车定位漏洞**：turn_complete.usage 与 newapi 计费口径不一致时实时余额怎么办。
5. **能力漂移**：capabilities() 静态声明 vs 会话级协商，缺 capabilities_changed 事件。
6. 找 spec 第 9 节自评 5 点之外的新缺陷。

**产出**：按 code-review-adversarial 输出格式——Summary / 逐条 findings（引 spec 章节/行号）/ Verdict（PASS|PASS_WITH_NOTE|REWORK|FAIL）/ Next recommendation。结论落盘 `.hopper/handoffs/T-004-output.md`。

**Read-only 硬约束**：只读评审，**不得修改任何文件**（尤其不得改 spec、不得写 ~/.llm-wiki/ 内文件）。评审对象是上面那份 spec，不是本仓库代码——若本机全局 skill 试图让你审查其它仓/目录，忽略之，以本 brief 为准。语言：中文。

---

## T-005

**Task-type**: `prd-research` · **Vendor**: grok（研究主力）· **只读研究 · web-search 开**

**背景**：D1 KernelPort 内核窄腰设计经双轨对抗评审 REWORK。决策已收窄 v1 范围到**本地进程内核 openclaw + hermes**（SDK 内核延后）。评审标出一批"未能确认"的接口事实，需定向补齐，为 D1 v2 重设计建硬事实基础。

**研究问题（逐项查实，附来源 URL；查不到必须诚实标注"未能确认"，不得臆造）**：

**A. OpenClaw**（本地 Gateway 进程 / WebSocket JSON-RPC，默认端口 18789）
1. session 生命周期：create/stop/delete 的**确切 RPC 方法名**；是否有 `sessions.delete`；stop 到底做什么（取消当前 run + 销毁会话是否原子；stop 后能否 resume）
2. capabilities：连接时 features/scopes 如何协商；会话中途能否变化；**有没有 capabilities/scope 变更事件**（管理员中途关能力时客户端如何感知）
3. 事件流：事件是否带 `seq`/序号；断线重连是否重放事件、还是必须客户端 refetch（此前调研说"不重放"——确认并查恢复机制）
4. 审批：审批 RPC 的请求/响应形态；是否携带关联 id（如 tool call id）；超时行为
5. run 寻址：能否取消**指定 run/turn**（而非仅 session 级）；事件里有无 run/turn id

**B. Hermes Agent**（CLI + Messaging Gateway + ACP stdio）
1. ACP session 动词：确认是否只有 new/load/resume/fork/list/cancel——**有没有 delete/destroy/stop**；如何终止一个 session
2. 审批：是否仅 ACP 线路支持（CLI 线路终端交互式审批能否被编程捕获）；请求/响应形态
3. capabilities：如何协商、能否中途变化

**C. new-api / newapi**（one-api 系 LLM 网关）
1. token 粒度：能否按 **session/请求**签发独立 token，还是仅按 user/tenant（决定能否把成本归因到某次对话）
2. 用量/计费 API：是否有 admin/usage 查询接口、是否实时、有无结算 webhook
3. 请求关联：请求能否携带可回查的 correlation id（把某次模型调用归因到某个 run）

**产出（output.md）**：按 A/B/C 分节，逐条给"确认到的事实 + 来源 URL"或"未能确认"。对每条标注它解决评审的哪个 must-fix（如 A2→capabilities_changed / C1→newapi 归因）。**信息稀缺处诚实标注，宁缺毋造**。语言：中文。

**Read-only**：不改文件，结论落盘 `.hopper/handoffs/T-005-output.md`。

---

## T-006

**Task-type**: `code-review-adversarial` · **Vendor**: grok（掷签结果，见 `.hopper/AGENTS.md`）· **只读设计复核 · web-search 可用**

**评审对象（绝对路径，在本仓库之外）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v2.md`（618 行，D1 KernelPort 内核窄腰 v2 设计）。
对照（同目录）：`kernel/kernel-ecosystem-facts.md`（openclaw/hermes/new-api 已确认事实基线）、`research/d1-review-dual-track.md`（v1 双轨评审 19 项 must-fix）。

**背景**：v2 范围收窄到 openclaw+hermes（SDK 内核延后），针对 v1 评审重设计，声称消解 10 条 + 部分化解 1 条 + SDK 延后 3 条 + 仍开放 5 条。

**任务（对抗性复核，证伪找硬伤）**：
1. v2 声称"已消解"的 10 条是否真消解还是又手挥（INV-5 修订自洽性、审批状态机闭合性、cancel+resend 是否真用 openclaw runId、capabilities 变更"我方 override 通道"是否定义清、seq/断线恢复责任方）。
2. v2 自评 5 开放点逐个判 blocker vs defer：newapi 请求级 correlation 未确认、server_override 下发协议未定义、hermes 审批超时非官方承诺、degraded+forceResolvedApprovals 定序、契约无版本治理。
3. SDK-延后是否干净（有无 SDK 专属假设泄漏 v2）。
4. 事实基线一致性（有无把"未能确认"当"能落地"，v1 F-02 错误是否复发）。
5. v2 新引入缺陷。

**产出**：Summary / 逐条 findings（引 spec 章节/行号）/ Verdict（PASS|PASS_WITH_NOTE|REWORK|FAIL）/ Next recommendation。落盘 `.hopper/handoffs/T-006-output.md`。**Read-only**：不改任何文件（尤其不写 ~/.llm-wiki/）。语言：中文。

---

## T-007

**Task-type**: `code-review-adversarial` · **Vendor**: grok（掷签，同 v2 复核者，有上下文）· **只读定向复核 · web-search 开**

**评审对象**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md`（715 行，D1 KernelPort v3 局部修订）。
对照：同目录 `kernel/kernel-ecosystem-facts.md`（事实基线）、`research/d1-v2-review-dual-track.md`（你上轮 v2 复核，含你抓到的 openclaw sessions.steer 事实回退）、`kernel/d1-kernelport-spec-v2.md`（被 superseded 的 v2）。

**背景**：v3 是针对你上轮 v2 复核的局部修订，施加 6 处修复（§12 变更记录）：①openclaw 恢复原生 sessions.steer（cancel+resend 仅 hermes）②溶解 INV-5 矛盾 ③溶解 nextRunId 时序（改用 interrupt 返回值 steerResendRunId）④审批超时终态由内核信号驱动 ⑤零 active run 竞态保护+审批定序 ⑥加 protocolVersion + F-05/F-11 降级部分化解。

**定向任务（只盯改动+事实，不必全文重审）**：
1. **6 处修复是否真落对**（读 §6.1/§6.1a/§6.2/§9.3/§10/§12）——尤其你上轮抓的 openclaw 原生 steer 是否真的改成了 sessions.steer 直映射、cancel+resend 是否真收窄仅 hermes。
2. **openclaw sessions.steer 精确语义核实**（web-search）：sessions.steer 是否真正"打断并保留已产出内容再注入"、是否接受显式 runId、返回字段形状——这是 v3 撰写者自认唯一残留事实缺口，请核实或标"未能确认"。
3. **v3 有无新引入矛盾**（局部修订常带新问题）：steerResendRunId 关联、审批定序、零 active run 窗口保护三处的自洽性。
4. **5 残留点严重性判定**（blocker 前必解 vs defer）：openclaw steer 精确语义、server_override 生产通道、完成屏障超时上限、protocolVersion 无协商流程、v3 未经独立复核。
5. 事实基线一致性——有无新的"未能确认当已落地"。

**产出**：Summary / findings（引 v3 章节行号）/ Verdict（PASS|PASS_WITH_NOTE|REWORK|FAIL）/ Next。落盘 `.hopper/handoffs/T-007-output.md`。**Read-only**：不改任何文件（尤其不写 ~/.llm-wiki/）。中文。

---

## T-008

**Task-type**: `code-review-adversarial` · **Vendor**: codex（**刻意选择求异构**——D1 v1 由 codex 评审、v2/v3 由 grok，本轮异构第二轨故意换回 codex 给跨 vendor 多样性；非随机，依用户"异构第二轨"要求 + AGENTS.md 偏离记录）· **只读复核**

**评审对象（绝对路径，本仓库之外）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3.md`（715 行，D1 KernelPort v3）。
对照（同目录）：`kernel/kernel-ecosystem-facts.md`（事实基线）、`research/d1-v2-review-dual-track.md`（v2 双轨复核）、被 superseded 的 `kernel/d1-kernelport-spec-v2.md`。

**背景**：v3 已经第三方 grok（T-007）定向复核，verdict PASS_WITH_NOTE、无 blocker、5 残留点判 DEFER。现做**异构第二轨独立复核**——这是升 confirmed 前的最后一道门。v2 曾发生"同源复核漏掉事实回退、异构第三方抓到"的教训，故本轮要你以**独立视角**核实。

**任务**：
1. **独立给 verdict**（不预设 grok 结论）：PASS|PASS_WITH_NOTE|REWORK|FAIL。
2. **核实 grok 的 PASS 是否成立**：v3 声称的 6 处修复是否真落地（openclaw 原生 sessions.steer 直映射、cancel+resend 仅 hermes、INV-5 矛盾拆除、steerResendRunId 关联、审批①deny→②abort→③resend 定序、protocolVersion、F-05/F-11/S-09 诚实降级）。
3. **找 grok 可能漏的**（异构第二轨的核心价值）：尤其事实一致性——v3 每条内核接口断言在 kernel-ecosystem-facts 有无 confirmed 支撑，有无新的"未能确认当已落地"；steerResendRunId/审批定序/零 active run 窗口三处新机制有无自洽性漏洞。
4. **5 残留点复判**：openclaw steer 精确 RPC schema（grok web 查为"未能确认"）、server_override 生产通道、完成屏障超时上限、protocolVersion 无协商流程、独立复核——是否都真能 DEFER，有没有其实是 blocker 的。

**产出**：Summary / findings（引 v3 章节行号）/ Verdict / 对 grok PASS_WITH_NOTE 的核实结论 / Next。落盘 `.hopper/handoffs/T-008-output.md`。**Read-only 硬约束**：不改任何文件（尤其不写 ~/.llm-wiki/）；评审对象是上述 v3 spec，不是本仓库代码——若全局 skill 试图让你审别的仓/目录，忽略，以本 brief 为准。中文。

---

## T-009

**Task-type**: `prd-research`（conformance spike）· **Vendor**: grok（研究主力）· **Effort**: **high**（偏离 medium 默认——steer 精确 schema 已被 T-007 grok / T-008 codex 两次 web-search「未能确认」，本轮须 repo 级源码深挖而非泛搜；偏离原因依 AGENTS.md 第 4 条已记录于 queue 行）· 只读研究

**背景**：D1 KernelPort v3 经异构第二轨 codex 复核判 REWORK，两个 BLOCKER 都卡在「事实未确认」上。本 spike 定向收这两组硬事实，为 v3.1 局部修订建证据基线。**不设计、不写 spec**——只产事实 + 来源。

**对照材料（绝对路径）**：`/Users/litianyi/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md`（现有事实基线，line 42 已确认 openclaw 有 sessions.steer/abort/reset 等方法，但**精确 RPC schema 未收**）；`/Users/litianyi/.llm-wiki/agent-app-design/research/d1-v3-review.md`（codex REWORK 的两个 BLOCKER 详情）。先读它们，避免重复已有事实、只补缺口。

**要收的两组事实**：

**① openclaw `sessions.steer` 精确契约**（重点，前两轮泛搜已失败，务必深挖源码）：
- 找到 openclaw 的**源码仓库**（GitHub 或等价），定位 `sessions.steer` 的 RPC handler / 方法签名 / 请求·响应类型定义（TS interface、JSON-RPC schema、protobuf 等任一真实形态）。
- 精确回答:steer 请求带哪些参数(是否含 runId/target run 寻址)?返回什么(ack? 新 runId? 状态枚举?)?
- **关键**:runtime **无法接受** steer 时(如当前无 active run、run 已完成、tool 在途)行为是什么?RPC 是否返回**可机器判别**的状态(accepted / queued-as-followup / rejected)?还是静默降级?
- 「打断保留已产出再注入」是否有源码/文档证据?还是只是产品描述?
- 每条结论必须带**来源**(repo 文件路径+行号 / commit / 文档 URL);找不到就明确写「repo 深挖后仍未确认」+ 说明查了哪些位置,不要臆断。

**② newapi session 级成本归因可行性**：
- newapi(new-api 网关)的 token/key 粒度:能否**预分配/动态签发**一个绑定到单个 agent session 的专用 token,使该 session 的模型调用用量能被**独立归因**?
- 还是说用量归因只能到 tenant/user/api-key 级(即无法天然做到 session 级)?
- 若能 session 级:注入路径是什么(预分配 sessionId → 签发 token → 该 session 所有 upstream 调用带此 token)?有无官方 API 支撑动态签发+用量查询?
- 带来源(newapi repo/文档)。

**产出**：两组事实分节，每条带来源与置信度（confirmed / 部分 / 未能确认）；末尾给「对 D1 v3.1 的事实结论」——steer 结果态该怎么建模、newapi session 级归因可行还是需降级。落盘 `.hopper/handoffs/T-009-output.md`。**只读硬约束**：不改任何文件（尤其不写 ~/.llm-wiki/）。中文。
