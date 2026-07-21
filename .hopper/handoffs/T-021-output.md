---
task_id: T-021
adapter: grok
model: grok-4.5
status: done
task_type: prd-research
effort: high
language: zh-CN
researched_at: 2026-07-22
primary_surface: ChatGPT desktop app（含 Codex 模式；原 Codex app 已并入）
phase: done
last_progress_at: "2026-07-21T18:59:01.834Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-21T18:59:01.833Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 241795
adapter_status: success
---

# T-021 — D5 codex app 产品形态调研 spike

## Summary

本任务对 **OpenAI Codex / ChatGPT desktop app** 的真实产品形态做只读调研，产出可直接服务 D5 七子面规格起草的事实基线。研究确认：「codex app」指 OpenAI 的 Codex 产品线中的**原生桌面聊天/任务工作台**（2026-02 以 Codex app 发布，2026-07-09 起并入 ChatGPT desktop app，仍保留独立 Codex 体验），而非 2021 年旧 API Codex 模型。九个子面均有官方文档与产品公告支撑；像素级细节（间距、颜色）有意不臆造，交互模式与信息架构以 confirmed 为主。

## Files touched

- `.hopper/handoffs/T-021-output.md` — 本调研交付物（任务指定落盘路径）
- 无其他文件改动（遵守只读硬约束；未写 `~/.llm-wiki/`）

## Acceptance verification (9/9)

| # | 准则 | 证据 |
|---|------|------|
| 1 | 对象消歧 + 多表面清单 | 见下文「对象确认」；主表面锚定 desktop app |
| 2 | D5 整体 IA | §1 含 Project/Chat/Thread 层级与布局 |
| 3 | D5.1 消息流 | §2 含 composer、流式、tool、diff、状态 |
| 4 | D5.2 会话管理 | §3 含列表/新建/恢复/并行/历史 |
| 5 | D5.3 审批权限 | §4 含模式、粒度、auto-review 状态 |
| 6 | D5.4 成本用量 | §5 含 plan 限额、Profile tokens、/status |
| 7 | D5.5 能力开关 | §6 含 Plugins/Skills/MCP 管理界面 |
| 8 | D5.6 账号 plan | §7 含登录、个人/企业、席位 |
| 9 | D5.7 模型切换 + 设计语言 + D5 建议 | §8–10 |

机器可检查：`test -f .hopper/handoffs/T-021-output.md && rg -n "D5\\.|置信度|对 D5 起草的建议|Verdict" .hopper/handoffs/T-021-output.md`

---

## 对象确认（先厘清「codex app」）

**判断：用户所说的「codex app」= OpenAI Codex 产品线中的原生桌面 agent 工作台。**

| 候选对象 | 是否匹配 | 依据 |
|----------|----------|------|
| **Codex / ChatGPT desktop app（原生桌面）** | **主匹配** | 官方文 [Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/)（2026-02-02 发布 macOS；2026-03-04 Windows）；changelog 写明 **2026-07-09 Codex app 并入 ChatGPT desktop app**，仍保留专用 Codex 体验（inline diff 编辑、侧栏 PR review、Computer Use、多仓库项目等）[developers.openai.com/codex 文档合集](https://developers.openai.com/codex/llms-full.txt) / [ChatGPT desktop app](https://learn.chatgpt.com/docs/codex/app) |
| Codex CLI | 次要表面 | 终端消息流；与目标「原生桌面 app」形态不同，但权限/thread 模型同源 |
| Codex IDE 扩展 | 次要表面 | 编辑器内嵌 chat；无完整 Projects 桌面导航 |
| Codex cloud（chatgpt.com/codex） | 次要表面 | Web 云端并行任务 + diff/PR；任务列表形态强，本地文件/OS sandbox 弱 |
| ChatGPT 内 Work mode | 同源 | 与 Codex **共享用量与能力包**；web/desktop 的 Work 与 Codex 在插件/子代理上高度重叠 |
| 2021 OpenAI Codex API 模型 | **否** | 已废弃的 completions 模型，无桌面消息流产品 |

**产品表面总表（2026-07 文档）：**

| 表面 | 用户可见形态 | 与目标 app 接近度 |
|------|--------------|-------------------|
| **ChatGPT desktop app（macOS/Windows）** | 侧栏 + 主消息流 + composer + review/terminal 面板 | **最高**（D5 主仿对象） |
| ChatGPT web Work / Codex cloud | 浏览器任务列表、云环境、diff/PR | 高（会话管理/并行） |
| Codex CLI | TUI 会话、/ 命令 | 中（权限与协议参考） |
| Codex IDE extension | 侧边 chat | 中 |
| ChatGPT iOS Remote | 远程监督/审批/diff | 低–中（移动监督） |
| GitHub / Slack / Linear 集成 | 从 issue/PR/频道起云任务 | 低（入口） |

**假设（一行）**：D5 规格应以 **desktop 消息流 app** 为功能对齐主锚，CLI/cloud 仅作协议与并行任务补强参考。

---

## 1. 整体产品形态与信息架构

**置信度：confirmed（官方产品页 + 桌面文档 + app-server 对象模型）**

### 1.1 产品定位

- 官方定位：从「coding agent」演进为 **complex work 的 command center**——并行项目、文件产物、浏览器/本机 Computer Use、长任务持续运行。  
  来源：[learn.chatgpt.com/docs/codex/app](https://learn.chatgpt.com/docs/codex/app)、[Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/)
- 桌面端现为 **统一 ChatGPT desktop app**：可选 **ChatGPT（Chat / Work toggle）** 与 **Codex**；可设 Codex 为默认视图、换 Codex 图标。  
  来源：changelog 片段（llms-full.txt，2026-07-09 merge 说明）

### 1.2 主界面布局（desktop）

| 区域 | 职责 | 证据 |
|------|------|------|
| **左侧 sidebar** | Projects / chats 导航；可 pin；可 toggle（⌘/Ctrl+B） | [Projects and chats](https://developers.openai.com/codex/projects)、键盘快捷键表 |
| **主工作区** | 当前 chat 的消息流 + 流式 agent 输出 | app 定位「Keep every chat in view」 |
| **底部 composer** | 用户输入；下方挂 **model/reasoning** 与 **permission mode** | [Models](https://developers.openai.com/codex/models)、[Permissions](https://developers.openai.com/codex/permission-modes) |
| **Review 面板/页签** | Git/diff/PR 审查（⌘/Ctrl+Alt+B；Ctrl+Shift+G open review tab） | desktop commands 表 |
| **Bottom panel / Terminal** | 终端与底部面板（⌘/Ctrl+J；Ctrl+`） | 同上 |
| **Chat sidebar（任务运行时）** | 展示 plan、sources、generated files、chat summary | [Work with files](https://developers.openai.com/codex/artifacts-viewer) |
| **可弹出独立窗口** | 聊天弹出 + Always on top，贴着 IDE/浏览器工作 | desktop settings「Keep a chat near your work」 |
| **Command menu** | ⌘/Ctrl+K 或 ⌘/Ctrl+Shift+P | desktop commands |

### 1.3 核心对象与层级（命名）

| 用户可见名 | 技术/协议名 | 层级含义 |
|------------|-------------|----------|
| **Project** | project / local project / workspace folder | 组织相关 chats；本地 project 绑定本机文件夹；ChatGPT project 带 sources/instructions |
| **Chat** | **thread**（`codex://threads/<id>`） | 一次会话/任务轨迹；sidebar 列表单元 |
| **Turn** | turn | 一轮用户输入触发的 agent 工作单元（app-server：`turn/start`） |
| **Item** | item（agentMessage delta、tool 进度等） | 消息流内的原子块 |
| **Goal** | goal（`/goal`） | 长任务完成标准 + 进度条控件 |
| **Subagent / agent thread** | child thread | 从主 thread 派生的并行 worker 会话 |
| **Worktree / environment** | local env / cloud env | 代码隔离与依赖环境（Codex 偏编码） |

来源：  
- 用户文案：[Projects and chats](https://developers.openai.com/codex/projects)  
- 技术对象：[App Server thread APIs](https://developers.openai.com/codex/app-server)（llms-full 中 `thread/start|list|archive|fork`）  
- 早期社区/教程仍把 sidebar 项叫 **threads**，与 deep link 一致

### 1.4 导航结构要点

- **Projects 视图**：ChatGPT 云端 project + **local projects（连本机文件夹）** 合一。  
- 一条清晰原则：**「一个明确 outcome 开一个 chat」**；project 只负责共享上下文，不把所有对话塞进同一 thread。  
- 历史：搜索 chats（⌘/Ctrl+G，可匹配内容与 git branch）、archive、Settings > Archived chats 恢复。  
- 深度链接：`codex://threads/new?prompt=&path=&originUrl=`、`codex://settings`、`codex://skills`、`codex://plugins/...`、`codex://automations`。

---

## 2. D5.1 核心消息流

**置信度：confirmed（文档 + app-server 事件模型）；部分像素级 tool-call 卡片样式依赖 UI 截图，标为「部分」**

### 2.1 用户输入

- 主输入：**composer**（底部）。  
- 支持：附件/上下文、dictation（Ctrl+Shift+D）、slash 命令、`@` 提技能/插件（ChatGPT）或 Codex 的 `$` skill 提及。  
- **Follow-up behavior**（设置）：在 agent 运行中发消息，可选 **steer 当前 run** 或 **等下一次 run**。  
- **Quick chat** vs **New chat**：快捷新建；Quick chat 用于轻量提问。  
  来源：desktop app quickstart、settings、skills 文档

### 2.2 Agent 流式输出

- 协议层明确支持 **`item/agentMessage/delta` 流式**与 `item/started|completed`、tool progress 通知（app-server）。  
- 用户侧：消息流中持续展开 agent 回复；长任务有 **goal progress row（composer 上方）** 可 pause/resume/edit/clear。  
  来源：[Long-running work](https://developers.openai.com/codex/long-running-work)、app-server 事件列表

### 2.3 Tool-call / 命令执行展示

- 安全模型：**OS sandbox 限制写范围与网络**；超界动作触发 **审批 UI**（见 §4）。  
- 运行时 UI：**chat sidebar** 可显示 plan、sources、生成文件；terminal 面板可观察命令。  
- MCP/connector 工具：有副作用的 tool 会 **elicit approval**；destructive 标注强制审批。  
- Computer Use / Browser：设置中启用；浏览器站点默认「先问再允许」。  
  来源：[Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)、browser settings

**部分确认**：单条 shell tool-call 卡片是折叠/展开、是否内联 stdout 的像素形态，官方 prose 未给组件级规范；实现时应以「可折叠工具块 + 进度 + 审批插入点」为模式，而非抄像素。

### 2.4 Diff / 文件改动呈现

- **Codex 模式特有**：inline editing in **diffs**；**review side panel** 看 PR/变更。  
- Cloud 任务列表展示 **+N/−N** 风格 diff 摘要。  
- **Artifacts / 文件预览**：生成的 doc/sheet/slide/PDF 在 workspace 内预览；**annotations** 点选区域后要求局部修改（代码、Markdown、网站、文档通用）。  
- 侧栏可列出 generated files，引导「说明保存路径 + 如何验证」。  
  来源：changelog（inline diffs）、[Work with files / artifacts](https://developers.openai.com/codex/artifacts-viewer)、cloud UI 描述

### 2.5 运行状态

| 状态面 | 呈现 |
|--------|------|
| Thread runtime | app-server：`idle` / `active` / `systemError` / `notLoaded` |
| Goal | progress row：pause / resume / edit / clear |
| Subagents | composer **上方** activity 面板：状态、stop all、打开子 thread |
| Auto-review | Reviewing / Approved / Denied / Aborted / Timed out（+ risk） |
| Notifications | 回合完成桌面通知（可配置） |
| Sleep | 「Prevent sleep while running」设置 |

---

## 3. D5.2 会话 / 任务管理

**置信度：confirmed**

### 3.1 列表

- Sidebar：**projects → chats**；可 pin project / pin chat；rename 为 outcome 导向标题。  
- Projects 视图可搜索 project；⌘G 搜历史 chat（含内容、branch 名）。  
- 技术列表：`thread/list` 支持 archived、cwd、searchTerm、sourceKinds、分页。

### 3.2 新建

- New chat / Quick chat 快捷键。  
- 可从 project 内新建，继承 sources/instructions 或本地 folder workspace。  
- Deep link 带 `prompt` 预填 composer、`path` 指定 workspace、`originUrl` 按 git remote 匹配。  
- `/plan` → 澄清 → `/goal` 启动长任务。

### 3.3 恢复

- 点选历史 chat；CLI：`/resume` / `codex resume`；协议：`thread/resume`。  
- 归档恢复：Settings > Archived chats。  
- **Remote / handoff**：chat + git state 在本机与 remote host 间移交；移动端 Remote 可继续监督。

### 3.4 并行任务

- **产品级默认**：多 chat/thread 并行（Codex app 发布文案：multiple agents, parallel workflows）。  
- 同一 project 下多个 chats 各自 outcome。  
- **Subagents**：主 thread 派生子 agent threads（默认 `max_threads=6`，`max_depth=1`）。  
- Cloud：多环境并行跑长任务，列表展示 Merged/Closed/+diff。  
- Worktrees：并行改代码时隔离 checkout。

### 3.5 历史

- 本地 thread 持久化（JSONL rollout）；可 archive/delete/fork。  
- 搜索：跨 chat（⌘G）与 chat 内 find（⌘F）。  
- Profile 侧有 activity insights（见用量）。

---

## 4. D5.3 审批 / 权限 UX

**置信度：confirmed（官方 Permissions + Approvals 长文）**

### 4.1 双层模型（必仿概念）

1. **Sandbox**：技术上能做什么（读/写路径、网络）。  
2. **Approval policy**：何时必须停下来问人（或 auto-review）。

默认本地：`workspace-write` + **网络关闭**；可写当前 workspace；出界写文件或需网络的命令 → 请求批准。

### 4.2 Desktop 用户可见模式

Composer **下方 permissions 控件**：

| 模式（用户文案） | 行为摘要 |
|------------------|----------|
| **Ask for approval**（推荐默认） | workspace 内自动；越界/网络/敏感动作询问 |
| **Approve for me**（设置里称 Auto-review） | 同一 sandbox 边界；eligible 请求交给 **reviewer agent** |
| **Full access** | 危险全开（需设置中显式 enable 才进菜单） |

首次使用须在 **Settings > General > Permissions** **启用**后模式才出现在菜单（启用 ≠ 选中）。组织策略可禁用某些模式。

来源：[Permissions / permission-modes](https://developers.openai.com/codex/permission-modes)、[Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)

### 4.3 批准粒度

- **按动作**：出 workspace 写文件、网络、untrusted 命令、side-effect MCP/app tools。  
- **Destructive MCP**：有 destructive 注解则 **始终**要批。  
- **Granular policy**（配置）：可分别控制 sandbox_approval / rules / mcp_elicitations / request_permissions / skill_approval。  
- **Profiles**：`:read-only` / `:workspace` / `:danger-full-access` + 自定义 filesystem/network 规则。  
- **会话/目录信任**：非 git 目录更倾向 read-only；可 onboarding 信任 cwd。  
- 子代理：**继承** parent turn 在 composer 下选的 permission mode。  
- 审批 overlay：可显示 **source thread**；快捷键打开源 thread 再批。  
- iOS Remote：changelog 提到 **per-chat 或 cross-chat MCP approval** 选项。

### 4.4 超时 / 拒绝呈现

- Auto-review 状态：**Reviewing / Approved / Denied / Aborted / Timed out**；可附 risk level 与 user-authorization assessment。  
- 失败闭环：prompt-build / review-session / parse 失败 **fail closed**（不执行）。  
- 用户拒绝：tool_decision telemetry 记录 approved/denied 与来源（user vs config）。

### 4.5 CLI 对照（协议可复用）

- `/permissions`；预设 Auto / read-only / untrusted / never / yolo。  
- 配置：`approval_policy`、`sandbox_mode`、`approvals_reviewer=auto_review`。

---

## 5. D5.4 成本 / 用量展示

**置信度：confirmed（plan 与限额表）；「单 task 精确 token 账单」在 UI 中为部分/社区反馈缺口**

### 5.1 是否展示

**是，但以 plan 额度/rate limit 为主，而非每条消息美元账单。**

| 位置 | 展示内容 | 来源 |
|------|----------|------|
| **Settings > Profile** | activity insights、**lifetime tokens**、peak tokens、streaks、longest task、token activity；可生成 profile card | desktop settings |
| **CLI `/status`** | 会话内 token/context 占用、5h/weekly 限额剩余 | 社区与第三方指南一致指向官方 /status |
| **Settings → Usage**（社区描述 + 计费文档） | remaining credit/limits | [Community](https://community.openai.com/t/how-can-we-clearly-see-token-usage-per-codex-conversation-task-especially-in-codex-web/1381431) |
| **Pricing 页** | 按 plan 的 5h 窗口 message 区间估算表（随模型变） | [Pricing](https://developers.openai.com/codex/pricing) |
| **Enterprise** | Workspace analytics、Compliance/Analytics API | 企业文档导航 |

### 5.2 粒度

- **账号 / plan 级**：Plus / Pro（5x 或 20x）/ Business 每席 / Enterprise（credits 或 per-seat）。  
- **共享池**：**Work mode 与 Codex 共用** pricing、credits、usage limits。  
- **窗口**：滚动 **5 小时** + 可能的 **weekly**；复杂任务、长上下文、工具、Fast mode、模型选择都会加速消耗。  
- **模型档位影响额度**：Sol 少、Luna 多（官方区间表）。  
- **Credits**：可扩展用量。  
- **API key 路径**：按 API token 计价，无云功能。  
- **Fast mode**：约 1.5× 速度，更高 credit 倍率。  
- **Auto-review**：额外模型调用，计入用量。

### 5.3 未能确认 / 缺口

- **按单 chat/task 的清晰 token 账单**在官方 UI 中不突出——社区明确抱怨 web/per-task 可见性不足。D5 若要做「任务级成本」，属于 **超越 Codex 的产品差异点**，不是简单仿。

---

## 6. D5.5 能力 / 工具开关

**置信度：confirmed**

### 6.1 Plugins

- 入口：desktop **Plugins**（Work 或 Codex 上下文）；Directory 分 tab：OpenAI / workspace / Personal；Installed 行。  
- 安装：详情页 plus → install；可能要求连接外部服务。  
- 插件可含：skills、connectors、MCP、browser extension、hooks、scheduled task templates。  
- 不可用：纯 Chat 模式、IDE 扩展、mobile（文档声明）。  
- Deep link：`codex://plugins/install/...`、`codex://plugins/<id>`。  
  来源：[Plugins](https://developers.openai.com/codex/plugins)

### 6.2 Skills

- 可复用 workflow 包（指令 + 资源）。  
- 触发：模型自动匹配，或 composer **显式选择**；`@`（ChatGPT）/ `$`（Codex）。  
- 构建：聊天「Build me a skill…」、Record & Replay（演示→skill）。  
- Deep link：`codex://skills`。  
  来源：[Skills & Plugins](https://developers.openai.com/codex/skills-and-plugins)

### 6.3 MCP

- Desktop：**Settings > MCP servers** → Add server（STDIO / Streamable HTTP）→ Save → Restart。  
- 列表显示 enabled / 需 OAuth；Authenticate 按钮。  
- Composer：`/mcp` 查看已连接。  
- 配置与 CLI/IDE **共享** `~/.codex/config.toml` 或项目 `.codex/config.toml`。  
- Web：通过 Plugins 的 remote MCP，不读本地 config。  
  来源：MCP 文档（llms-full）

### 6.4 其他能力开关

| 能力 | 开关位置 |
|------|----------|
| Browser / Chrome extension | Settings > Browser；站点 allow/block |
| Computer Use | Settings > Computer Use；OS 隐私权限 |
| Memories | Settings > Memories；单 chat 控制 |
| Personality | Settings > Personalization 或 `/personality` |
| Ultra / Max | Settings 启用后出现在 model slider |
| Suggested prompts | Settings |
| Pets | Settings > Pets（可选装饰） |
| Hooks | 插件/配置；需信任后启用 |
| AGENTS.md / Rules | 仓库与全局配置层 |

企业侧：admin 可管控 plugins、skills、connectors、permission profiles、model availability（managed configuration）。

---

## 7. D5.6 账号 / plan / 坐席

**置信度：confirmed**

### 7.1 登录

- **Sign in with ChatGPT**（浏览器 OAuth 回流）— 订阅路径；desktop 签出屏 **Continue to sign in**。  
- **API key** — 用量计费路径；CLI/IDE/desktop 本地可用；**无** cloud 集成功能。  
- Codex cloud **必须** ChatGPT 登录。  
- 登录方式决定 admin/数据 retention 策略归属（ChatGPT workspace vs API org）。

### 7.2 个人 vs 团队/企业

| Plan | 产品化呈现要点 |
|------|----------------|
| Free / Go | 限时或基础纳入 Codex（发布期促销曾扩展）；desktop 全球可用含 Free（2026-07 merge 后说明） |
| **Plus** ~$20/mo | web/CLI/IDE/iOS Codex；GPT-5.6 家族；credits |
| **Pro** from $100/mo | 5× 或 20× 限额；Codex-Spark 等 |
| **Business** ~$20/user/mo（年付） | 专用 workspace、SSO/MFA、admin、更大云 VM、数据默认不训练 |
| **Enterprise & Edu** | SCIM、EKM、RBAC、audit、residency、analytics、priority |

来源：[Pricing](https://developers.openai.com/codex/pricing)、[Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/)

### 7.3 席位 / 工作区

- Business/Enterprise：**per-user seat** + **workspace** 成员/角色。  
- 文档明确：workspace membership 决定能否登录；**seats + roles** 决定可用表面与功能。  
- 邀请：Profile 菜单 **Invite a friend / Invite a coworker**（个人 vs Business 分轨；Enterprise 无 referral）。  
- Admin：plugin/skill 控制、permission profiles allowlist、model availability、governance。

### 7.4 与目标 app 差异预告

目标 app 有 **license / 租户 / newapi** 自有计费时，应 **仿「workspace + seat + role」信息架构**，勿硬绑 ChatGPT Plus 价格带。

---

## 8. D5.7 模型 / 内核切换

**置信度：confirmed**

### 8.1 是否暴露给用户

**是。** Desktop：composer **下方 model + reasoning 控件**（与 permissions 同区）。

### 8.2 选择 UX

- 推荐路径：默认 **Power** ≈ `gpt-5.6-sol` + medium；UI 向 **Smarter / Faster** 滑动；**Advanced** 选具体模型/effort/speed。  
- 模型家族叙事：  
  - **Sol**：复杂、开放、高价值  
  - **Terra**：日常默认平衡  
  - **Luna**：高吞吐、清晰可重复任务  
- Reasoning effort：Light/Medium/High/Extra High；**Max**（单任务更深，可能要设置开启）；**Ultra**（子代理并行，Settings > Configuration 打开 slider）。  
- CLI：`/model`、`-m`。  
- Fast mode / Codex-Spark：速度档或独立快模型（Pro 预览）。  
- Personality：**Friendly / Pragmatic / None**（非模型权重，但是「内核语气」开关）。  
- 高级：可配任意 Chat Completions/Responses 兼容 provider；Bedrock 企业路径（无 ChatGPT 登录）。

来源：[Models](https://developers.openai.com/codex/models)、Speed/Subagents 文档

### 8.3 对 D5 含义

- 模型选择应是 **composer 一级控件**，不是埋在深层设置。  
- 若目标 app 走 newapi/多供应商，可保留「推荐档位 + Advanced 选具体模型」双层 UX。

---

## 9. 可复用交互模式 / 设计语言要点

**置信度：confirmed（模式级）；非 pixel-clone**

1. **Project 工作区 + Chat 任务单元**：上下文共享与 outcome 隔离拆开。  
2. **并行为默认**：多 thread 同屏可切换，而非单会话阻塞。  
3. **Composer 控制条三位一体**：输入 + **权限** + **模型/effort**。  
4. **Sandbox 与 Approval 分离**：自动不等于无限权。  
5. **审批插入消息流**：action 前停顿；auto-review 显示可解释状态机。  
6. **产物一等公民**：diff/review 面板、文件预览、annotation 局部改，而不是纯文本聊天。  
7. **长任务 Goal 模式**：完成标准外置 + progress 控件 + 可 steer。  
8. **Subagent 可见性**：子工作可点进独立 thread，主线程收摘要。  
9. **深度链接与 slash**：`codex://` 与 `/goal` `/mcp` `/permissions` 降低导航成本。  
10. **可弹出 Always-on-top 小窗**：agent 陪伴式贴边，而非占满主屏。  
11. **设置分层**：日常偏好 / 能力连接 / 危险模式需二次 enable。  
12. **企业托管配置**：用户 UI 与 admin requirements 双轨。  
13. **用量以额度进度为主**：5h/weekly + profile tokens；非强制每 token 美元。  
14. **人格与模型解耦**：personality 独立开关。  
15. **扩展三件套**：Skill（流程）/ Plugin（分发）/ MCP（工具协议）。

---

## 10. 对 D5 起草的建议

### 10.1 建议直接可仿（功能对齐）

| D5 子面 | 建议采用的形态 |
|---------|----------------|
| **整体 IA** | 左栏 Project → Chat 列表；主栏消息流；composer 底栏；可选 review/terminal/产物侧栏 |
| **D5.1 消息流** | 流式文本 + 可折叠 tool 块 + 审批卡片插入 + 运行状态条；产物/diff 侧通道 |
| **D5.2 会话** | 新建/搜索/pin/rename/archive；一 outcome 一 chat；多 chat 并行 |
| **D5.3 权限** | 双层 sandbox+approval；composer 下模式切换；默认 Ask；危险模式设置内 enable；auto-review 可选 |
| **D5.5 能力** | 设置内 MCP；插件目录；skill 提及；能力默认最小权限 |
| **D5.7 模型** | composer 旁模型+effort；推荐档 + Advanced |
| **设计语言** | 「监督并行 agents 的 command center」，不是单轮 chatbot |

### 10.2 因目标 app 差异必须调整

| 差异点 | Codex 现状 | D5 建议调整 |
|--------|------------|-------------|
| **领域** | 强编码（git、worktree、PR review、repo） | 通用 agent：保留「本地 folder project + 产物预览」，弱化强制 git；diff 泛化为「变更集/工具副作用摘要」 |
| **计费** | ChatGPT plan + credits + 5h 窗口 | 对接 **license / 租户 / newapi**：账号用量按租户配额；可借鉴 Profile tokens + 窗口进度条，但账单语义用自有 credit |
| **坐席** | ChatGPT Business/Enterprise seat | 显式 **租户 → 席位 → 角色 → 可用工具/模型**；admin 托管策略可仿 managed configuration |
| **登录** | ChatGPT OAuth 或 API key | 自有 IdP/许可证；保留「浏览器登录回流」模式即可 |
| **模型供应** | OpenAI 家族主推 | newapi 多模型路由；UI 仍用 Sol/Terra/Luna 式 **能力档位隐喻** 降低选择成本 |
| **插件生态** | OpenAI marketplace | 可仿目录/安装 UX，后端换成自有或 MCP 清单；不必仿 Pets 等装饰 |
| **Computer Use** | OS 级桌面控制 | 按合规分期；权限模型必先于功能 |
| **任务级成本** | 弱 | 可作为差异化：task 级 token/费用（Codex 社区缺口） |
| **Cloud 并行** | OpenAI 托管 VM | 可选；本地并行 chat 优先 |

### 10.3 D5 规格书写纪律（防臆造）

1. 每个 UI 控件写清 **状态机**（尤其审批、goal、subagent），勿只贴线框。  
2. 对象命名在规格中固定一套中英文：建议用户文案用 **项目 / 会话(chat)**，协议层保留 **thread**。  
3. 标明 **surface 范围**：MVP = desktop 消息流；CLI/cloud 为后续表面。  
4. 引用本文件 URL 与置信度标签；**部分/未能确认**项用 spike 二次验证（真机截图）再进 pixel 规格。

---

## Decisions / deviations

1. **主仿对象**：以 2026-07 后的 **ChatGPT desktop app（Codex 模式）** 为准；历史「独立 Codex.app」与现产品连续，不另立过时规格。  
2. **未做真机截图像素测量**（无本地 Codex 安装强制依赖）；交互模式以官方文档/发布文为准，像素级标为非目标。  
3. 旧「Codex API 模型」明确排除，避免 PRD 串台。

## Open questions

1. 目标 app MVP 是否必须包含 **Computer Use / 浏览器操控**，还是仅 shell+文件+MCP？  
2. 租户计费是 **seat 订阅** 还是 **newapi 按量** 为主？是否要做 task 级账单（超越 Codex）？  
3. 「会话」产品名用 chat / task / thread 哪一个中文主名？（建议 chat=会话，task=有 goal 的长跑会话）  
4. 是否需要 cloud 托管并行，还是仅本地多会话？  
5. 企业 admin 是否与 app 同仓交付，还是二期？

## Verdict

**PASS**

九个子面均有可引用事实与来源 URL；对象消歧完成；给出 D5 可仿 vs 必改清单。未写入 wiki 或其它工程文件。

## Next recommendation

1. 直接启动 **D5 产品规格起草**，以本文件 §1–9 为 data-contract 事实源。  
2. 对「tool-call 卡片像素」与「Usage 面板精确字段」开一个 **真机 UI 截图 spike**（可选 T-0xx），补齐「部分」项。  
3. 同步冻结命名：`Project / Chat(thread) / Turn / Goal / Approval`。  
4. PRD 中单列 **租户-席位-配额** 与 Codex plan 的映射表，避免实现时绑死 ChatGPT 计费语义。

---

## 主要来源索引

| URL | 用途 |
|-----|------|
| https://openai.com/index/introducing-the-codex-app/ | 桌面 app 发布、并行 agents、sandbox 默认、plan 可用性 |
| https://openai.com/codex/ | 产品总览 |
| https://learn.chatgpt.com/docs/codex/app | desktop 形态、quickstart、能力叙事 |
| https://learn.chatgpt.com/docs/agent-approvals-security | sandbox + approval 完整策略 |
| https://developers.openai.com/codex/llms-full.txt | 全量文档合集（projects/permissions/pricing/models/plugins/MCP/app-server/changelog） |
| https://developers.openai.com/codex/projects | Project/Chat 组织 |
| https://developers.openai.com/codex/permission-modes | 权限模式 UX |
| https://developers.openai.com/codex/pricing | plan/seat/limits |
| https://developers.openai.com/codex/models | 模型选择 UX |
| https://developers.openai.com/codex/plugins | 插件目录 |
| https://developers.openai.com/codex/skills-and-plugins | skills |
| https://developers.openai.com/codex/long-running-work | Goal 模式 |
| https://community.openai.com/t/how-can-we-clearly-see-token-usage-per-codex-conversation-task-especially-in-codex-web/1381431 | 用量可见性缺口（对照） |

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "开始执行 T-021：调研 OpenAI Codex 的真实产品形态，聚焦与目标桌面 agent 消息流 app 最接近的表面，并按 D5 七子面整理可引用事实基线。已确认存在官方 **Codex desktop app**（macOS/Windows）。继续深挖官方文档与产品页面上的各子面细节。材料已齐：确认 Codex app 于 2026-07-09 并入 ChatGPT desktop app。正在撰写完整调研产出。# T-021 完成 · Verdict: **PASS**\n\n## Summary\n\n已完成 OpenAI **Codex / ChatGPT desktop app** 产品形态只读调研，落盘：\n\n**`.hopper/handoffs/T-021-output.md`**（约 500 行）\n\n## 核心结论\n\n| 点 | 结论 |\n|----|------|\n| **对象** | 「codex app」= OpenAI Codex 原生桌面工作台（2026-02 发布 → **2026-07-09 并入 ChatGPT desktop app**，仍保留 Codex 模式） |\n| **主仿表面** | Desktop 消息流 app（非 2021 API Codex，非纯 CLI） |\n| **IA** | **Project → Chat(thread) → Turn/Item**；composer 下挂 **权限 + 模型** |\n| **可直接仿** | 并行 chat、sandbox+approval 双层、goal 进度、产物/diff 侧通道、Plugins/Skills/MCP |\n| **必须改** | 编码偏置 → 通用 agent；计费改为 **租户/席位/newapi**；task 级成本可做成差异点（Codex 偏弱） |\n\n## Files touched\n\n- `.hopper/handoffs/T-021-output.md` — 调研交付物  \n- 无其它文件改动（未写 `~/.llm-wiki/`）\n\n## Acceptance verification\n\n**9/9** 子面均有来源 URL + 置信度（confirmed / 部分）；含「对 D5 起草的建议」。\n\n## Next recommendation\n\n直接用本文件作 data-contract 起草 **D5 规格**；可选再开真机截图 spike 补 tool-call 卡片像素与 Usage 面板字段。",
  "stopReason": "EndTurn",
  "sessionId": "019f8608-0eb1-7420-97f6-dc2dca1760ba",
  "requestId": "3bd968be-f0dc-4031-8cd8-453bcbad6e91",
  "thought": "The user wants me to execute a research task about the Codex app product form. This is a prd-research task - I need to research OpenAI's Codex product forms and produce findings about product morpholo...Let me fetch more documentation pages for detailed product form.Interesting - the docs seem to have evolved. The Codex app appears to have been rebranded or integrated into the \"ChatGPT desktop app\" with Codex as a mode. Let me dig deeper into the specific pages f...The learn.chatgpt.com docs seem to have path issues - many pages 404. Let me try open_page tool and also try developers.openai.com paths more carefully. Also try the llms-full.txt and official pages.Great progress - I have a lot of good material. Let me extract more from the llms-full.txt about projects, models, pricing, plugins, MCP, skills, and the desktop app specifically.Let me extract more specific sections about the desktop app, projects, pricing, plugins, skills, models, and message stream UI.I'm getting excellent material. Let me extract more specific sections - desktop app settings, pricing, models, projects, plugins, skills, permission modes, artifacts.Let me extract the most important sections for the D5 product form research.The file is huge. Let me extract specific sections more carefully with smaller ranges.I have enough material. Let me read the remaining critical slices completely.Let me get pricing and projects details more carefully.I have enough high-quality material to write a comprehensive research report. Let me also quickly check the projects section and official announcement for IA layout details, and the desktop intro page...**Summary**  \nI researched OpenAI's Codex/ChatGPT desktop app (the closest match to D5's target surface) using public sources. Key findings cover layout, message flow, session management, approvals, usage display, tools, accounts, model switching, and design patterns. All facts are sourced with confidence levels.There's already a T-021-output.md stub - let me check it, then write the full research deliverable.I have comprehensive information. Now I'll write the full T-021-output.md research deliverable in Chinese with all 9 sections plus the D5 recommendations, and the required output shape structure.\nLet me verify the acceptance criteria with a quick grep command as mentioned.The deliverable is complete. I'll provide a concise summary for the hopper dispatcher as the final response.",
  "usage": {
    "input_tokens": 166195,
    "cache_read_input_tokens": 1410688,
    "output_tokens": 12621,
    "reasoning_tokens": 3616,
    "total_tokens": 1589504
  },
  "num_turns": 16,
  "total_cost_usd": 0.8663224,
  "total_cost_usd_ticks": 8663224000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 166195,
      "outputTokens": 12621,
      "cacheReadInputTokens": 1410688,
      "modelCalls": 16,
      "costUSD": 0.8663224
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 241795
- end_time: 2026-07-21T18:59:01.833Z
- log: see `T-021-output.log` for raw output
