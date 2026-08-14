# Round Summary — rounds/0011

**SG-10 L1 Mac UI 壳（主线，第二批第二轮）** · 2026-08-05 · **收盘 `Accepted: no` / `Feedback: negative`**

> 一句话：**东西做出来了，但证据不足以证明它，且过程中犯了三类本项目一直在猎捕的错误。**
> ★审查闸 codex T-080 判 REWORK，主会话逐条自验后采纳。代码不回滚，下一轮 0012 为限定修复轮。

## 交付

原生 macOS SwiftUI 壳 `app/apps/AgentShell/`（660 行，8 个源文件），做到 L1 要求的四件事——**窗口 / 会话列表 / 新建会话 / 消息流渲染**——并对隔离 openclaw 实例完成真实会话往返。地基是把此前靠裸 `swiftc` 编译的 Swift 代码打成 SwiftPM 包（`app/Package.swift`，5 个 target）。

**不含**：流式渲染精细化、stop、审批五态、成本面板、能力开关（均 L2/L3）。

## 本轮定案的两处遗留「待定」

`goal-breakdown.md` SG-10 行与 `data-sources.md` RAE-0001 Pass 栏当初都写死「首轮 scope-lock 时定」。本轮即那个首轮，经 AskUserQuestion 取得用户裁决（2026-08-05）后写入三处落点：

- **UI 验收方法 = 分层**：逻辑层自动化断言产 e2e 日志 + UI 层录屏/截图人工验收，**不建 XCUITest**。已知代价：UI 层 L1 无回归保护。
- **RAE-0001 Pass = 四条全要**，缺一即 fail。

**这两项是验收判据，未自行填写**——属 `human-decision-required`。`evals.json` 未动（其 schema 顶层只允许 `evals`，无 `pass_condition` 字段，Pass 条件的设计落点本就是 `data-sources.md`）。

## 四条 Pass 条件终态：**全部未达成**（RAE-0001 outcome=fail）

> **本节曾写作「全部达成」。★审查闸 codex T-080 判 REWORK，主会话逐条自验后采纳并撤回。** 完整理由见 `decision.md`；下表是撤回后的终态，原判定不保留为「曾达成」——它当时就不成立。

| # | 条件 | 终态 | 为什么不成立 |
|---|---|---|---|
| ① | 真实往返可见 | **未达成** | 往返**确实发生过**（CLI 侧 `delta='收到'`/`stopReason=completed`，UI 侧截图 `ROUNDTRIP OK`），但 scope-lock 要求的是「**录屏**可见」，实际 `video=0, raw_log=0`——只有静态截图，未绑定构建产物/gateway/runID/provider 日志 |
| ② | 隔离性可证 | **未达成** | 条件字面是「**全程**未触碰」，而本轮**首次 send 解析并读取了** `~/.openclaw/workspace`（错误文本 `Legacy workspace setup state requires migration` 证明它检查了目录内容）。后续干净重启抹不掉这次触达。且单次 `lsof` 只覆盖采样瞬间、只查了 gateway PID 29003 未查 wrapper 28765 及 descendant |
| ③ | 事件序列与契约一致 | **未达成** | 核心断言是空的：`nextSeq()`（`OpenclawGatewayKernelClient.swift:825-833`）是 kernel-client **自己的本地计数器**，wire 帧丢了本地序号照样连续——「seq 单调」对「无丢帧」一无所证。且本条曾被**无新证据**从「部分」改判为「达成」 |
| ④ | 失败可诊断 | **未达成** | 能力确实展示了（三种根因三种签名），但**原始日志一条未落进 evidence**（全在 gitignored scratchpad），无法关联时段/PID/runID；三个字符串单独也不构成唯一层级指纹，需组合日志才成立 |

## 三处实测发现（都不是顺利的部分，都留在证据里）

**① recipe 的隔离声明是作用域受限的结论，读起来像通用结论。** 严格照 `OPENCLAW-ISOLATED-RUN-RECIPE.md` §1 只设 `OPENCLAW_STATE_DIR`，`createSession`/`subscribe`/`stop` 全正常，**一 `send` 就伸向 `~/.openclaw/workspace`** 并报 `Legacy workspace setup state requires migration`。原文那句「只设这一个已经足够隔离」在 SG-4 范围内为真——SG-4 的 §4 明确 defer 了 send。rounds/0009 其实早就额外设了 `OPENCLAW_WORKSPACE_DIR`，但 recipe 从未更新，于是本轮又踩一次。**经用户授权扩入本轮 scope 后已修**，并在 recipe 里显式标注作用域限制与踩坑历史。

**② 我自己设计的隔离证明方法被实测证伪。** 原方法是「`~/.openclaw` 整树 stat 指纹前后比对」。实测指纹**真的变了**，追下去发现是**用户自己的常驻 gateway（PID 29071）在持续写 `logs/gateway.log` 等**（`lsof` 坐实）。该方法在目标目录有并发第三方写者时根本无法归因。改用正面归因后结论才站得住。**没有用「大概是用户自己写的」把它糊过去**，方法变更已写进 scope-lock 条件②栏。

**③ 撞上真阻断，上报而非绕过。** D3-proxy 默认对未映射 session `reject`，跑通需往 **Pi 的 Postgres** 写一行——而 `raspberry-pi-deploy` 被刻意排除在 `Pre-Authorized Test-Resource Writes` 之外。按协议归类 `write-safety-required` 停下问用户。用户裁决走 `aggregate` 兜底：**零 Pi 写入**，只改本机 gitignored `.env`，落在预授权表 `d3proxy` 行内。源码核实（`session-proxy.service.ts:134-180`）：aggregate 仍先查映射，未命中才用兜底 key 并打「无法归因到具体 session」警告——不是关掉检查，是换一个明示的计费主体。

## 断言有牙齿的旁证

同一套 6 项断言，在 workspace 未隔离的坏环境下跑出 **2 条 `[FAIL]`**（`turnComplete` 0 条、终态不唯一），补齐隔离后全 PASS。**不是恒绿装饰**。

## 主会话独立复验（未采信子代理自述）

- 洁净重建（`rm -rf app/.build`）→ `Build complete!`；帧回放 **30/30 PASS**，与改造前基线逐数吻合
- release 构建通过（`-enable-testing` 是 `unsafeFlags`，release 下未破）
- 子代理**自承没跑**的两项由主会话补齐：`verify-type-fidelity-swift`（全部负例如预期编译失败）、CI flat-`swiftc` 平价 runner（**12 PASS / 0 FAIL / 1 DEGRADED**，与 CI 步骤名写死的期望逐字吻合）
- `#if canImport(D2Generated)` 的**双向证明**：SwiftPM 构建成功 ⇒ 该分支取真；flat 构建成功 ⇒ 取假。两次构建互为反证，非「碰巧都没报错」
- `.messageDelta` 是唯一 assistant 文本载体一说，对生成产物**逐字核对**：11 个变体确认，`Role` 枚举确实只有 `assistant` 一个合法值

## 证据瑕疵（如实登记，未清场）

截图里第一条用户消息是 `aaaaaaaaaa`——AppleScript `keystroke` 打不出中文（10 汉字变 10 个 a），改 ASCII 又被系统中文 IME 吃掉（`ly`→旅游）。**是驱动手段问题，不是 app 缺陷**（模型确实收到并回复了）。最终靠剪贴板粘贴拿到干净配对。那条脏消息留在图里没清——清掉等于隐藏证据是怎么取到的。

## 收尾

D3-proxy / 隔离 openclaw / AgentShell 均已停止，端口释放。`app/server/.env` **逐字节还原**（`diff -q` 确认）——aggregate 是本轮临时配置，不留成静默改变计费归因的脚枪。用户全局 gateway PID 29071 全程未变。隔离目录 `scratchpad/round0011-openclaw-iso/`（gitignored）保留，属本轮新建 test-resource；未删除任何非本轮新建的东西。

## 开轮时记的框架 issue

**TH-0031**（P3，open）：开新轮会让 `loop_anomaly_skipped_unparsable` 从 2 掉到 1，而下降与底层状况改善无关——只因新轮尚无 `decision.md`，`_latest_round_decision_text` 返回 None 导致整个 goal 被跳过计数。与 TH-0011 / TH-0026 同族：门是绿的、数字是好看的，而好看的原因不是它看起来的那个原因。

## 遗留待办

1. `(runID, index)` 分组假设已现粗糙边缘——注入失败时错误占位文本被**重复拼接两次**。需用真实多段 delta 流验证正确分组语义。
2. UI 不显示失败层级，分层归因只在日志成立——L2 候选。
3. `.env` 还原后，当前仓库状态下无法直接复现本轮成功往返；复现需重设那两项配置（已在证据里写明具体键名）。
4. AX 未暴露按钮标题（`AXTitle` 为 `missing value`），UI 自动化只能几何点击；系统中文 IME 会干扰键盘驱动。若后续要做 UI 自动化，两条都要先解决。
5. `~/.local/bin/hopper-dispatch` shim 指向已不存在的 marketplace 路径（插件更新后未跟上），本轮改用 submodule 内 CLI 派发。该 shim 自己的注释就引了 `ISSUE-stale-dispatch-binary.md`——同一问题复发。
6. `stop()` 从未被 UI 调用（stop 按钮属 L2），会话保持订阅至进程退出。
7. `ErrorEventMessagePayload.recoverable` 三态被压平，任何 `.error` 都只清等待态。
8. 未按 D5.2 §2.2 的「草稿态 → 原子 create+send」设计，走的是更简单的「点新建即 createSession」。

## 两处新确认的真实代码缺陷（评审发现，主会话已独立验证成立）

1. **`(runID, index)` 分组是既成缺陷，不是待验假设。** `EventMapping.swift:197` 的 `for (index, block) in blocks.enumerated()` —— `index` 是**单条 `session.message` 内**的 content-block 下标，每条新消息从 0 重启；`SessionStore.swift:184-194` 却按 `(runID,index)` 永久复用气泡，同一 run 内不相关消息会被合并。`screens/l1-injected-failure-midchain.png` 里两条完整错误被无缝拼接就是现场照片。缺 runID 时还会持续碰撞 `no-run#0`。
2. **订阅竞态**（评审发现，**主会话未独立复验**，需构造快速发送时序才能证）：`OpenclawGatewayKernelClient.subscribe`（`:391-422`）先返回 stream、再由未 await 的 `Task` 发订阅 RPC；`SessionStore.swift:97-103` 也未等待消费任务建立。人工操作够慢不等于快速发送不会丢早期事件。

## 下一轮（0012）限定范围

修复轮，非新功能轮（runtime-recoverable）：①修 `(runID,index)` 分组 ②查证并修订阅竞态 ③把空的 `seq` 断言换成真能证伪丢帧的检查（需 wire watermark 或期望事件清单）④补 recipe 文末那条仍遗漏 `OPENCLAW_WORKSPACE_DIR` 的复制命令 ⑤从全新隔离目录重跑，把**录屏 + 原始日志**落进 evidence ⑥给出无秘密的可复现步骤（真实建立 session 映射，或把 aggregate 冻结成有完整重放步骤的 L1 测试 profile）。
