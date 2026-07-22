---
task_id: T-036
adapter: grok
model: grok-4.5
status: done
task_type: code-review-adversarial
language: zh-CN
reviewed_at: 2026-07-22
phase: done
last_progress_at: "2026-07-22T06:20:00.000Z"
last_progress: Adversarial review of D7 v1 completed.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-22T06:08:39.790Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 190537
adapter_status: success
---

# T-036 — D7 本地内核分发打包 v1 对抗评审（grok 轨）

## Summary

对 `~/.llm-wiki/agent-app-design/architecture/d7-kernel-packaging.md`（D7 v1，draft，约 300 行）做只读对抗评审，事实基线为 T-035 + kernel-ecosystem-facts / T-003 + D1 v3.5 / D2 v3 / D4 / X1。结论：T-035 分发事实大体保真且 7 处诚实结转与 open questions 对齐良好；X1/D4 定位与 D1 Transport / D2 CompatMatrix 口径切分正确。但作为「可执行实现输入」仍有若干中等缺口——尤其 **app-managed prefix 与官方 `install-cli`/LaunchAgent 路径的可组合性被写得过顺**、**首启下载失败/离线恢复未升格为 §7 结转（T-035 标为高风险）**、以及卸载清理 / Gateway 配对鉴权 / Windows 监督对等性偏薄。未发现把 T-035「未能确认」系统性升格为 confirmed 的硬造假。

## Files touched

- `.hopper/handoffs/T-036-output.md` — 本对抗评审唯一落盘产出（只读评审对象，未改 wiki/契约正文）

## Acceptance verification (5/5)

| # | 审查重点 | 结果 | 证据 |
|---|----------|------|------|
| 1 | T-035 保真：分发/运行时/启动事实有无臆造或把部分当确认 | **基本通过**，见 F-01/F-03 注 | 对照 T-035 §1–§6 与 D7 §1.2/§1.3/§2/§3；置信度标注大体一致 |
| 2 | 契约消费：KernelRuntimeLayout 启动命令 ↔ D1 §5 / D2；D4 打包关系；X1 定位 | **通过（有低优先级松散表述）** | D7 §0/§1.1/§2.4/§5.1/§8；D1 §5；D2 §7.1；D4 §1.3–§1.4；X1 连带① |
| 3 | 布局/分发/监督设计可执行性与关键失败边角 | **有中等缺口** | 见 F-01/F-02/F-04/F-05 |
| 4 | 7 处诚实标注是否恰当 | **通过（缺 1 项应结转）** | D7 §7 表 #1–#7 ↔ T-035 open q#1–#4 + Next #3；见 F-02 |
| 5 | 内部自洽 + 是否可作为实现输入 | **方向可用，落地前须补缺口** | 见 Findings；`design_status: draft` 自述与缺口程度匹配 |

## Decisions / deviations

1. **假设**：任务要求 T-036→本文件；「只读硬约束」解读为不改评审对象与契约源，仅写 handoff 产出。
2. **未做 live install / 包体积实测**——与 T-035 研究边界一致；本评审是文档对文档的契约交叉检查。
3. **Verdict 标尺**：存在可误导实现的中等设计缺口 → 记为 finding；若未发现 confirmed 级事实伪造或契约硬冲突 → 不定 FAIL；缺口未到「整页推倒重写」→ 不定 REWORK，给 **PASS_WITH_NOTE**。

## Open questions

1. `install-cli.sh --prefix <Application Support/...>` 生成的 LaunchAgent `ProgramArguments` 是否稳定指向 app-managed 前缀，还是隐含 `~/.openclaw`？（D7 当可直接复用，T-035 Next #3 要求实测但未钉死答案）
2. openclaw Gateway 在 app 托管实例上的 **device pairing / token / scope** 是否必须由 D7 规定，还是完全属于 D1 适配器层？
3. `HERMES_HOME` 是否为 hermes 官方一等环境变量，还是仅 T-035/D7 的命名约定？

## Verdict

**PASS_WITH_NOTE**

## Next recommendation

1. **收残（不重写）**：在 D7 增补/升格——(a) 首启下载失败·重试·离线 SKU 策略进 §7 或独立失败矩阵；(b) 明确「跟随官方范式」= 架构级（managed prefix + 首启下载 + 监督），**不等于**路径级照搬 `~/.openclaw`，并写清自定义 prefix 下 LaunchAgent/plist 的生成责任；(c) 卸载/repair 与 Windows 监督对等各补一小节。
2. **实现前强制 live-probe 维持**（与 D7 §7 #3/#5 一致）：干净 Mac 上 `install-cli.sh --prefix` + LaunchAgent vs 子进程；顺带验证 OPENCLAW_HOME 隔离与 18789 冲突分配。
3. **双轨收齐后**再决定是否升 `design_status`；当前 draft 标签应保留。

---

## 五维逐条

### 1. T-035 保真

**总评：高保真，未见把「未能确认」整体洗成 confirmed。**

| D7 声称 | T-035 位置 | 置信度是否对齐 | 判定 |
|---------|------------|----------------|------|
| openclaw/hermes **非**单文件原生二进制；openclaw=npm+Node 22/24/25；hermes=Python3.11+uv | §1.1/§1.2/§2.1/§2.2 | confirmed | 对齐 |
| OpenClaw.app **不**内嵌 Node/Gateway；首启 installer → 下载到 `~/.openclaw` → LaunchAgent | §1.3 关键引文 | confirmed | 对齐（D7 L75 引文忠实） |
| 默认 `127.0.0.1:18789`；`openclaw gateway`/`gateway run`；健康检查 `/readyz` 等 | §1.3 | confirmed | 对齐 |
| 公证 DMG/Developer ID；非 App Store 沙箱 v1；Windows 签名安装器；loopback 防火墙「部分」 | §3.3/§3.4 | confirmed / 部分 | 对齐 |
| 推荐范式 MS-MKR / native shell + managed prefix + 首启下载 + 监督 | §6.1 rank#1、§6.2 | 推荐级 | 对齐 |
| auto-update 默认关；`update --tag` 精确钉版；state 与代码分离 | §1.4/§4.4 | confirmed | 对齐 |
| Windows Hub payload、hermes pin/rollback、NO_AUTO_UPDATE 第三方边界 | open q#1–#3 | 部分/未能确认 | D7 §7 诚实承接 |
| checksum-in-manifest | §3.2 IDE 行业惯例 confirmed；**非** openclaw 官方签名机制 | D7 §2.3 自标「设计判断/部分」 | 对齐，未伪造成 vendor 机制 |

**注意点（未升为阻断）**：

- D7 L87「**同一内核生态里唯一被官方验证过的嵌入范式**」——对 openclaw companion 成立；hermes 另有 Desktop installer 主路径（T-035 §2.1）。修辞略满，但不构成事实造假。
- frontmatter `tags` 含 `hermas`（历史拼写），与正文 hermes 并存——噪声级。

### 2. 契约消费正确性

**X1**：D7 明确落地「客户端须承担本地内核分发」（X1 连带影响①）——**准确**（D7 §1.1 ↔ X1 原文）。

**D4**：引用 §1.4「零 Node」收窄为**产品 client 层**、不重新裁决内核 Node/Python 栈；并论证 managed runtime 不构成第 3 个 sidecar 进程——与 D4 §1.3「2 进程（UI + 内核）」**一致**。D7 工作在 D4 主动划出的空白内——**定位正确**。

**D1 §5 Transport**：

- openclaw → WS Gateway `127.0.0.1:18789` 控制面：与 D1 方法映射（`sessions.*` / `chat.*` over WS）及 T-003/kernel-ecosystem-facts **一致**。
- hermes → `hermes acp` stdio：与 D1 表中 ACP 线路及 T-035「最贴合原生宿主」建议 **一致**。
- **松散处（F-03）**：D1 §5 是 **KernelPort 方法→底层机制** 表，并不规范性规定 OS 级启动命令字符串；D7 §2.4 写「严格对齐 D1 §5」同时把 `openclaw gateway` / `hermes acp` 列为启动命令——**协议/端点对齐正确，但「启动命令来自 D1」表述过紧**；启动命令真实来源是 T-035/T-003。

**D2**：CompatMatrix（`kernelId@version` 二进制兼容）与 `protocolVersion`（`kernelport/1` wire 握手）正交切分（D7 §5.1）——与 D2 §7.1/§7.2 **一致**，未侵占 wire 协商。

**D5.7**：结转「本地内核分发打包属于 D7」——D7 承接正确。

### 3. KernelRuntimeLayout / 分发 / 监督可执行性

**连贯且可作方向输入的部分**：

- 路径布局（Mac Application Support / Win LOCALAPPDATA + 版本目录）清晰。
- 钉精确版本、禁止浮动 latest、更新状态机 `check→staging→verify→stop→swap→start→health→commit` + 保留 N-1 回滚，形状完整。
- 监督双模型表（LaunchAgent vs 子进程）优缺点与分内核推荐合理；二选一标 live-probe **诚实**。
- 多内核：默认 openclaw 首启下、hermes 按需、单活、禁会话热切换、ProcessManager 插件化——与 T-035 §5 一致。
- 端口占用探测 + 替代 loopback + 状态目录 `OPENCLAW_HOME` 隔离——正面回应 T-035 open q#4。

**关键缺口 / 边角（实现会踩）**：

| 场景 | D7 覆盖 | 缺口 |
|------|---------|------|
| 首启下载失败 / 离线 | 仅「未安装→触发下载」 | T-035 §6.4 **高**风险（重试/镜像/离线 SKU/清晰错误）未落入 D7 状态机或 §7（**F-02**） |
| 自定义 prefix + 官方 installer/LaunchAgent | 声称 install-cli「可直接复用」 | 官方 companion 默认 `~/.openclaw`；自定义 Application Support 下 plist/`gateway install` 是否认 prefix **未设计**（**F-01**） |
| 内核崩溃 | LaunchAgent KeepAlive 提及 | hermes 子进程中途崩溃后的会话/重连策略薄 |
| 版本不兼容 | `onMismatch: block-and-guide` | guide 的产品路径/双版本并存窗口未写 |
| 端口竞态 | §7#4 承认未实测 | TOCTOU 可接受为 live-probe |
| 卸载 | LaunchAgent「需显式卸载」一笔 | 无 uninstall/repair 流程：plist、runtime 目录、状态目录保留策略（**F-04**） |
| 签名/公证具体流程 | 分发格式 confirmed | 下载后 payload 的 quarantine/xattr、bootstrap 签名、TCC 粘性（T-035 中风险）未展开（**F-05**） |
| 内核↔app 首次配对 | 无 | openclaw device pair/token/scope 是否在 D7 范围不清（**Open q#2**） |
| Windows 监督 | §3.3 Scheduled Task 有事实 | §4 推荐几乎 Mac 中心；Win 服务化与 app 调度主权对等性不足（**F-05**） |

### 4. 诚实标注（7 处结转）

| # | D7 结转项 | 与 T-035 关系 | 是否恰当 |
|---|-----------|---------------|----------|
| 1 | Windows Hub payload | open q#1 | 恰当 |
| 2 | hermes pin/rollback | open q#2 / §2.4 未能确认 | 恰当 |
| 3 | 禁用 self-update 第三方边界 | open q#3 | 恰当；与更新主权前提绑定正确 |
| 4 | 端口/状态隔离需实测 | open q#4；D7 已给设计仍标未实测 | 恰当（设计回应 ≠ 已验证） |
| 5 | LaunchAgent vs 子进程 live-probe | Next recommendation #3 | 恰当；未假装收敛 |
| 6 | checksum/签名细节 | §3.2 惯例 ≠ vendor 签名 | 恰当 |
| 7 | migration epoch 具体值 | §4.4 概念要求 | 恰当，未臆造数字 |

**应结转却偏弱 / 未入表**：

- **首启网络失败与离线 SKU**（T-035 风险表高等级）——D7 正文几乎未写，§7 七项均未覆盖 → **F-02**。
- **自定义 prefix 与官方 daemon 安装路径的可组合性**——被 live-probe #5 间接覆盖，但正文「可直接复用」语气过强 → **F-01**。

**不该结转却当已定**：未发现；监督模型与 checksum 均未伪称为已收敛。

### 5. 内部自洽 + 完整性

**自洽**：

- openclaw=服务化 / hermes=ACP 子进程与各自协议面匹配。
- 状态目录与 runtime 二进制分离贯穿更新与隔离章节。
- §6.2 单活 vs §6.3「hermes messaging gateway 若同时运行」略有张力——产品路径已选 ACP 单活时，messaging gateway 并行更多是「用户全局实例」边角，建议实现时标明「非产品主路径」。

**完整性（相对「实现输入」）**：

已具备：布局、钉版、manifest 字段方向、监督模型选择框架、更新回滚、多内核矩阵、与 D1/D2/D4/X1 依赖表。

仍缺或过薄：离线/失败恢复、卸载、配对鉴权边界、下载源权威（npm 直连 vs 自建镜像）、磁盘预检、多 app 实例并发启动、Windows 监督对等、公证后下载组件信任链。

作为 **draft v1 + 明确未送审**，结构足以进入双轨收残，**尚不足以直接编码而不再开设计补丁**。

---

## Findings（关键）

### F-01 · MEDIUM · app-managed prefix 与官方 installer/LaunchAgent「可直接复用」过顺

- **D7**：§2.1 L106「openclaw 官方 install-cli.sh 路径可直接复用」；§4.2 优先 LaunchAgent 且对齐 `openclaw gateway install`。
- **T-035**：官方 companion 下载到 **`~/.openclaw`**（§1.3）；Next #3 要求用 `install-cli.sh --prefix` **实测**两种监督模型——说明可组合性**尚未确认**。
- **风险**：实现者可能假设「换 prefix + 调官方 install-daemon」即可，实际 plist 工作目录、PATH、OPENCLAW_HOME、与用户全局实例冲突处理都可能破功。
- **建议**：改写为「**意图**复用 install-cli 的 pinned Node+包安装能力；LaunchAgent 的 ProgramArguments/EnvironmentVariables 必须由 app 按 managed prefix **显式生成或修补**」；并与 §7#5 live-probe 绑定验收标准。

### F-02 · MEDIUM · 首启下载失败 / 离线未升格结转

- **T-035** §6.4：首启需网络失败 = **高**，缓解含重试、镜像、离线 SKU、清晰错误。
- **D7**：§3.1/§4.3 有「触发下载」，无失败状态机；§7 七项未列。
- **风险**：「可执行」状态机在最常见失败路径上断裂。
- **建议**：§3 或 §5 增加 `download-failed | verify-failed | offline-blocked` 及用户可见恢复；§7 增第 8 项或并入风险表。

### F-03 · LOW · 「严格对齐 D1 §5」对启动命令表述过紧

- **D7** §2.4 L124–129。
- **D1** §5 是方法→机制映射表，不规定 `openclaw gateway` 进程监督方式。
- **建议**：改为「**端点与协议面**对齐 D1 §5；**进程启动命令**取自 T-035/T-003（confirmed）」。

### F-04 · LOW–MEDIUM · 卸载 / repair / orphan 清理未成流程

- **D7** §4.1 提到 LaunchAgent 不能靠杀父进程隐式清理；§4.3 有启动对账。
- **缺**：用户卸载 app 时是否 remove LaunchAgent、是否保留 `OPENCLAW_HOME` 状态、runtime 多版本 GC。
- **建议**：补「安装 / 修复 / 卸载」三态责任表（即使 v1 只定义最小行为）。

### F-05 · LOW · Windows 监督与下载信任链偏 Mac 中心

- Mac：LaunchAgent 推荐完整；Windows：§3.3 有 Scheduled Task 事实，§4 未给出与「更新主权在 app」对等的 Win 监督选择与 live-probe。
- 下载 payload 的 Gatekeeper quarantine / SmartScreen 与「bootstrap 进 bundle、runtime 外置」的签名边界未写（T-035 已提示中风险）。

### F-06 · LOW · `HERMES_HOME` 官方性

- T-035 §5.2 将 `HERMES_HOME` 与 `OPENCLAW_*` 并列作隔离建议；OPENCLAW_HOME 在 T-035 §1.2 confirmed。
- D7 将两者对称写入 §2.1——**合理设计**，但应标「hermes 环境变量名实现前核实」（可并入 §7#4）。

### 非 Finding（明确通过）

- 未把 Windows Hub / hermes rollback / NO_AUTO_UPDATE 写成已确认。
- 未把 checksum 伪造成 openclaw 官方签名机制。
- 未破坏 D4「2 进程」或把 Node 内核误判为违规 sidecar。
- 未把 D7 CompatMatrix 与 D2 `protocolVersion` 混为一谈。
- X1 连带①定位正确。

---

## Verdict 理由（浓缩）

| 维度 | 判定 |
|------|------|
| T-035 保真 | 通过 |
| 契约消费 | 通过（F-03 措辞级） |
| 设计可执行 | 方向通过，F-01/F-02 中等缺口 |
| 诚实结转 | 7 项恰当；缺离线/失败项 |
| 完整性 | draft 可评审；实现前需收残 |

故：**PASS_WITH_NOTE**（非 REWORK：无 confirmed 事实伪造、无 D1/D2/D4 硬冲突、结构可收残而非推倒；非 PASS：F-01/F-02 若不改，实现期易按错误假设编码）。

## Vendor output (parsed)

（本机直接执行对抗评审并落盘；无额外 vendor JSON 包装。）

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll perform the adversarial review of D7 kernel packaging myself: first load the review target and its contract baselines, then write findings to the T-036 output.Next I'll cross-check D7 against D1 Transport, D2, D4, X1, and the kernel ecosystem facts.I have enough cross-checks; drafting the five-dimension adversarial review and writing `T-036-output.md`.# T-036 完成\n\n对抗评审已落盘：`.hopper/handoffs/T-036-output.md`\n\n## Verdict: **PASS_WITH_NOTE**\n\n### 五维摘要\n\n| 维度 | 结果 |\n|------|------|\n| **T-035 保真** | 通过 — Node/Python 非单文件、首启下载+LaunchAgent、18789、公证 DMG 等与 T-035 对齐；未发现把「未能确认」洗成 confirmed |\n| **契约消费** | 通过 — X1/D4 定位准；D1 Transport 端点正确；CompatMatrix ⊥ D2 `protocolVersion` |\n| **可执行性** | 方向可用，有中等缺口 |\n| **7 处诚实结转** | 恰当；缺「首启失败/离线」应结转项 |\n| **完整性** | draft 可双轨收残，尚不可直接当完整实现说明书 |\n\n### 关键 findings\n\n1. **F-01 MEDIUM** — `install-cli` + 自定义 Application Support prefix + LaunchAgent 被写成「可直接复用」，与官方默认 `~/.openclaw` 及 T-035 要求实测之间张力未钉死  \n2. **F-02 MEDIUM** — T-035 标为**高**风险的首启下载失败/离线恢复，D7 未写入状态机或 §7  \n3. **F-03–F-06 LOW** — D1 启动命令表述过紧、卸载流程薄、Windows 监督偏 Mac、`HERMES_HOME` 官方性待核实  \n\n### Next\n\n收残补 F-01/F-02（不必推倒重写）→ 维持 §7 live-probe → 再考虑升 `design_status`。",
  "stopReason": "EndTurn",
  "sessionId": "019f886d-e826-7df2-afcf-3c07b5b3005c",
  "requestId": "09ba606b-b115-4849-af6e-4ae9b618f44a",
  "thought": "The user wants me to perform an adversarial code review of a design document. This is a code-review-adversarial task (T-036) where I need to review the D7 kernel packaging document against various sou...I have the D7 document and T-035. Now I need to read the contract baselines: D1, D2, D4, X1, kernel-ecosystem-facts, T-003. Let me extract the relevant sections.I need to read D1 §5 Transport mapping more carefully to verify the launch commands and endpoints claimed in D7.I have enough material to perform a thorough adversarial review. Let me systematically go through the five dimensions.\n**Summary**  \nI performed an adversarial code review of `~/.llm-wiki/agent-app-design/architecture/d7-kernel-packaging.md` against the T-035 baseline and supporting contracts. The document faithfully reproduces the distribution and runtime facts from T-035, correctly maps the KernelRuntimeLayout to the D1/D 2/D4 contracts, and surfaces honest partial marks for Windows Hub and hermes pinning. Minor overclaims exist around “唯一被官方验证过的” and HERMES_HOME usage, but these are clearly labeled and do not introduce fabrication. The design is executable once the noted gaps are closed.\n\n**Files touched**  \n- 1. `~/.llm-wiki/agent-app-design/architecture/d7-kernel-packaging.md` – primary artifact under adversarial review\n\n**Acceptance verification (N/N)**  \n1. T-035 fidelity – PASS (all 8 core facts confirmed; HERMES_HOME and “唯一” claims are partial and explicitly marked 部分)  \n2. Contract consumption – PASS (D1 transport, D2 protocolVersion, D4 kernel-process placement all aligned; D1 launch-command attribution is the only loose point)  \n3. Design executability – PASS_WITH_NOTE (layout/pin/checksum/first-run download/dual supervision/update state machine/multi kernel isolation are coherent; first-run download failure UX, kernel-crash recovery, initial pairing, uninstall cleanup, and notarization flow are missing)  \n4. Honest annotation – PASS (7 honest结转 correctly labeled 部分 or 设计判断)  \n5. Internal self-consistency + completeness – PASS_WITH_NOTE ( 整体可作为实现输入; missing concrete notarization steps, pairing protocol, and Windows Scheduled Task details)\n\n**Decisions / deviations**  \n- None – review stayed strictly read-only and followed the five-dimensional frame.\n\n**Open questions**  \n- None\n\n**Verdict**  \nPASS_WITH_NOTE\n\n**Next recommendation** Add explicit failure-UX for download, initial pairing spec, and uninstall flow to close the executability gaps before v1 implementation.  \n(Review complete – output will be written to `.hopper/handoffs/T-036-output.md`.)  \n\n**Summary**  \nI performed an adversarial code review of `~/.llm wiki/agent-app-design/architecture/d7-kernel-packaging.md` against the T-035 baseline and supporting contracts. The document faithfully reproduces the distribution and runtime facts from T-035, correctly maps the KernelRuntimeLayout to the D1/D2/D4 contracts, and surfaces honest partial marks for Windows Hub and hermes pinning. Minor overclaims exist around “唯一被官方验证过的” and HERMES_HOME usage, but these are clearly labeled and do not introduce fabrication. The design is executable once the noted gaps are closed.\n\n**Files touched**  \n- 1. `~/.llm-wiki/agent-app-design/architecture/d7 kernel-packaging.md` – primary artifact under adversarial review\n\n**Acceptance verification (N/N)**  \n1. T-035 fidelity – PASS (all 8 core facts confirmed; HERMES_HOME and “唯一” claims are partial and explicitly marked 部分)  \n2. Contract consumption – PASS (D1 transport, D2 protocolVersion, D4 kernel-process placement all aligned; D1 launch-command attribution is the only loose point)  \n3.I've written the deliverable. Let me mark the todo complete and give a concise summary to the user. The task said read-only and produce output - done.Task complete. Provide a concise summary for the user/dispatcher.",
  "usage": {
    "input_tokens": 83522,
    "cache_read_input_tokens": 305408,
    "output_tokens": 10146,
    "reasoning_tokens": 4169,
    "total_tokens": 399076
  },
  "num_turns": 6,
  "total_cost_usd": 0.3195424,
  "total_cost_usd_ticks": 3195424000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 83522,
      "outputTokens": 10146,
      "cacheReadInputTokens": 305408,
      "modelCalls": 6,
      "costUSD": 0.3195424
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 190537
- end_time: 2026-07-22T06:08:39.790Z
- log: see `T-036-output.log` for raw output
