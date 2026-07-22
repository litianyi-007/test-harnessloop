---
task_id: T-035
adapter: grok
model: grok-4.5
status: done
task_type: prd-research
language: zh-CN
researched_at: 2026-07-22
phase: done
last_progress_at: "2026-07-22T05:53:23.202Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-22T05:53:23.201Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 220890
adapter_status: success
---

# T-035 — D7 本地内核分发打包调研（PRD 输入）

## Summary

本任务在 T-003 / kernel-ecosystem-facts 已确认的「本地进程型内核 + 控制面」之上，只补**分发 / 打包 / 运行时启动 / 版本更新**层事实。结论：openclaw 与 hermes **都不是可直接塞进 .app 的单文件原生二进制**，而是 **Node（openclaw）/ Python+uv（hermes）运行时 + npm 或 git 布局**；官方原生 companion（OpenClaw macOS app）明确采用「**不内嵌 Node/Gateway，首启下载匹配版 CLI 到用户前缀 + LaunchAgent 托管**」。对 D7 的推荐是：**跟随该范式**——默认 openclaw 按稳定通道钉版、按需下载 hermes；app 与内核版本解耦但做兼容矩阵；非 App Store 沙箱、公证 DMG / 签名安装器分发。

## Files touched

- `.hopper/handoffs/T-035-output.md` — 任务指定的唯一落盘产出（调研结论）

## Acceptance verification (6/6)

| # | 准则 | 证据 |
|---|------|------|
| 1 | openclaw 真实分发形态 + 启动 + 版本钉法（来源+置信度） | §1 |
| 2 | hermes 等可切内核分发形态对照 | §2 |
| 3 | 嵌入原生桌面 app 的打包方式 + Mac/Windows 现实 + 范式案例 | §3 |
| 4 | 内核版本管理与更新 / 回滚 | §4 |
| 5 | 多内核可切的分发影响 | §5 |
| 6 | 适配度排序 + 对 D7 设计建议；中文落盘本文件 | §6 + 本文件 |

## Decisions / deviations

1. **「hermes」继续按 `NousResearch/hermes-agent` 处理**（与 T-003 一致）。
2. **研究范围锚定「分发层」**：协议方法名不重复 T-003/T-005/T-009；仅在需要解释启动方式时引用已确认的 Gateway/ACP 事实。
3. **Hermes Desktop**：官方文档推荐 Mac/Windows 下载 Desktop installer；社区另有 Electron 打包复述，本文以官方 install 文档为主，Electron 实现细节标「部分」。
4. **只读硬约束**：未写 `~/.llm-wiki/`；未改业务代码；仅写本 handoff 产出文件。

## Open questions

1. OpenClaw 官方 **Windows Hub** 是否与 macOS app 同样「首启下载 CLI、不内嵌 Node」？（mac 侧已 confirmed；Windows Hub 具体 payload 布局公开文档未完整展开 → **未能确认**）
2. Hermes **`hermes update` 是否支持精确 pin 到 tag/commit 并安全回滚**的一等命令（存在 `hermes update` 与 install-method 自检，精确 pin/rollback 契约未在本轮完整确认）。
3. 将 openclaw 作为 **app 托管子进程（非 LaunchAgent）** 时，官方是否支持/推荐「禁用 self-update」的稳定契约（存在 `OPENCLAW_NO_AUTO_UPDATE` 与 managed handoff 语义，但第三方 app 托管边界需实现期验证）。
4. 多内核并行时，openclaw 固定 `18789` 与 hermes messaging gateway / 其他端口是否会与用户已装实例冲突——需要 D7 设计 **端口/状态目录隔离策略**。

## Verdict

**PASS**

## Next recommendation

1. 用本文件 §6 作为 D7 设计草稿输入：采用 **「native shell + managed runtime prefix + 首启/按需下载 + 监督生命周期」**。
2. 起草 D7 规格时钉死：`KernelRuntimeLayout`（路径、钉版、校验、启动命令）、`CompatMatrix(appSemver × kernelId@version)`、更新/回滚状态机。
3. 实现前做一次 **live probe**：在干净 Mac 上用 `install-cli.sh --prefix` 类路径模拟 app 托管安装 openclaw stable，验证 LaunchAgent vs 子进程两种监督模型。

---

## §0 已有事实（本轮不重复深挖，仅作锚点）

| 项 | 已确认（来源：T-003 / kernel-ecosystem-facts） |
|----|-----------------------------------------------|
| openclaw 集成模型 | 本地 Gateway 守护进程；主控制面 **WS JSON-RPC**，默认 `127.0.0.1:18789` |
| hermes 集成模型 | 本地 CLI / Messaging Gateway / **ACP stdio JSON-RPC**（`hermes acp`） |
| X1 / D2 / D4 上下文 | 本地内核；独立本地进程；app 经 D2 JSON-RPC(Gateway) 通信；各端原生 client（Swift/C#） |

---

## §1 openclaw 的真实分发形态

### 1.1 分发通道（是什么 / 不是什么）

| 形态 | 是否官方主路径 | 说明 | 置信度 |
|------|----------------|------|--------|
| **npm 包 `openclaw`** | **是（默认）** | 全局或前缀安装；dist-tag：`latest` / `beta` / `dev` / `extended-stable` | **confirmed** |
| **安装脚本** | **是（推荐）** | `install.sh`（macOS/Linux/WSL）、`install.ps1`（Windows）、`install-cli.sh`（本地前缀、可无系统 Node） | **confirmed** |
| **git 源码构建** | 是（dev/贡献者） | clone + `pnpm install && pnpm build`；`openclaw update --channel dev` 可切到 git | **confirmed** |
| **Docker / Podman / Nix / Ansible** | 是（可选/服务器） | 容器与声明式部署；非桌面默认 | **confirmed** |
| **单文件原生二进制（Go/Rust 一类）** | **否** | 公开安装文档以 Node 包为主，无「下载单一可执行文件即完整 Gateway」的官方主路径 | **confirmed（否定）** |
| **macOS `.dmg` / `.zip` companion app** | 是（**UI companion**，非完整内核本体） | GitHub Releases 上 `OpenClaw-<version>.dmg`；**不内嵌 Node/Gateway 运行时** | **confirmed** |
| **Windows Hub companion** | 是（文档提及） | 原生 Hub：setup、tray、chat、node、local MCP；与 CLI/WSL2 Gateway 并列 | **部分**（Hub 内部 payload 细节未完整确认） |

来源：
- https://docs.openclaw.ai/install
- https://docs.openclaw.ai/install/installer
- https://docs.openclaw.ai/platforms/macos
- https://docs.openclaw.ai/platforms/mac/bundled-gateway
- https://github.com/openclaw/openclaw

### 1.2 运行时依赖

| 依赖 | 要求 | 置信度 |
|------|------|--------|
| **Node.js** | **22.22.3+ / 24.15+ / 25.9+**；默认目标 **Node 24**；Node 23 不受支持 | **confirmed** |
| 包管理器 | 用户侧常用 npm；源码构建要 pnpm；bun 可装包但仍需 Node（`node:sqlite`） | **confirmed** |
| 系统库 | 无「单一系统 dylib 清单」作为桌面最小集；可选依赖含原生模块编译场景；Alpine/musl 有 SQLite 链接警告 | **部分** |
| 磁盘状态 | 用户态配置/会话/凭证在 `~/.openclaw`（或 `OPENCLAW_HOME` / prefix） | **confirmed** |

`install-cli.sh` 可把 **pinned Node tarball + openclaw** 装到本地前缀（默认 `~/.openclaw`），**无需系统级 Node**——这对「app 托管 runtime」极重要。

来源：https://docs.openclaw.ai/install/installer 、https://docs.openclaw.ai/install

### 1.3 作为本地 Gateway 进程如何启动

| 方式 | 命令 / 机制 | 说明 | 置信度 |
|------|-------------|------|--------|
| 前台运行 | `openclaw gateway` / `openclaw gateway run` | WebSocket 控制面；可 `--port 18789` | **confirmed** |
| 默认绑定 | `127.0.0.1:18789` | 本地环回；远程用 VPN/SSH 隧道（T-003 已述） | **confirmed** |
| 服务化（macOS） | LaunchAgent `ai.openclaw.gateway`；`openclaw gateway install` / onboard `--install-daemon` | **退出 companion app 不杀 Gateway** | **confirmed** |
| 服务化（Linux/WSL） | systemd user unit | 同上 daemon 路径 | **confirmed** |
| 服务化（Windows） | Scheduled Task；失败则 per-user Startup-folder 回退 | **confirmed** |
| 健康检查 | `openclaw gateway status`、`/readyz`、`openclaw health` | 更新后验证路径文档完备 | **confirmed** |
| **stdio 作为被嵌入主模型** | 否（主模型是 WS Gateway） | stdio JSON-RPC 用于**出站**接外部 CLI（T-003） | **confirmed** |

关键官方事实（对 D7 直接约束）：

> **OpenClaw.app does not bundle Node or the Gateway runtime.**  
> 它期望外部 `openclaw` CLI；**不把 Gateway 当作 app 子进程 spawn**；用 **per-user launchd** 保活，或 attach 已在跑的本地 Gateway。  
> 首启 Local 模式：跑**随 app 捆绑的 installer 脚本** → 下载 user-space Node + 匹配版 openclaw 到 `~/.openclaw` → 装 LaunchAgent。需要网络。

来源：
- https://docs.openclaw.ai/cli/gateway
- https://docs.openclaw.ai/platforms/mac/bundled-gateway
- https://docs.openclaw.ai/start/wizard

### 1.4 稳定分支 / 发布节奏 / 版本钉法

| 通道 | 语义 | 钉法 | 置信度 |
|------|------|------|--------|
| **stable** | npm dist-tag `latest`；推荐生产 | `openclaw update --channel stable` | **confirmed** |
| **extended-stable** | 拖尾「支持月」包通道；**仅 package**；不自动 apply | `openclaw update --channel extended-stable` | **confirmed** |
| **beta** | npm `beta`；可先于 stable 验证 | `--channel beta` | **confirmed** |
| **dev** | git `main` 移动头；npm `dev` 少见 | `--channel dev` | **confirmed** |
| 精确版本 | 一次性 | `openclaw update --tag <version>`（不持久改 channel） | **confirmed** |
| 标签惯例 | 稳定 `vYYYY.M.PATCH`；beta `vYYYY.M.PATCH-beta.N` | git tag 不可变 | **confirmed** |
| 自更新 | `openclaw update` 检测 install kind、doctor、重启 Gateway；auto-updater **默认关** | 配置 `update.auto.enabled` | **confirmed** |
| 回滚 | `openclaw update --tag <known-good>`；或停 Gateway + 手动 npm pin；git checkout 旧 tag | 文档有完整 rollback 章；跨 session SQLite migration 有特殊 doctor 路径 | **confirmed** |

来源：
- https://docs.openclaw.ai/install/development-channels
- https://docs.openclaw.ai/install/updating

### 1.5 对本项目的分发含义（openclaw）

- **不能**假设「把一个静态二进制拷进 `Contents/MacOS` 就完事」。
- **可以**假设「钉 npm 版本 + 自带/下载 Node 运行时 + 监督 Gateway 进程」是官方已验证路径。
- companion 官方选择是 **首启下载 + LaunchAgent**，不是 app bundle 内嵌完整 runtime。

---

## §2 hermes 等可切内核的分发形态（对照）

### 2.1 分发通道

| 形态 | 是否主路径 | 说明 | 置信度 |
|------|------------|------|--------|
| **curl 安装脚本（git layout）** | **是（CLI 默认）** | `curl …/install.sh \| bash`；Windows：`install.ps1` | **confirmed** |
| **Hermes Desktop installer** | **是（Mac/Windows 推荐）** | 官网下载安装器，装 CLI + Desktop | **confirmed** |
| **git clone + uv/pip 可编辑安装** | 是（开发） | `~/.hermes/hermes-agent/` + venv | **confirmed** |
| **pip `git+https://github.com/NousResearch/hermes-agent.git`** | 是（库嵌入） | Python library 路径 | **confirmed** |
| **npm 单包** | 否 | 内核主体是 Python；Node 是侧车 | **confirmed（否定）** |
| **单文件原生二进制** | 否（主路径） | 安装器组装 Python/uv/依赖，非单一 agent binary | **confirmed（否定）** |
| **Docker** | 可选（社区/部署文） | 非官方「唯一」桌面路径 | **部分** |

**Install layout（per-user）**：

| 项 | 路径 |
|----|------|
| 代码 | `~/.hermes/hermes-agent/` |
| 启动器 | `~/.local/bin/hermes`（symlink） |
| 数据 | `~/.hermes/` |

Root-mode 另有 FHS：`/usr/local/lib/hermes-agent` 等。

来源：
- https://hermes-agent.nousresearch.com/docs/getting-started/installation
- https://github.com/NousResearch/hermes-agent
- https://hermes-agent.nousresearch.com/docs/guides/python-library

### 2.2 运行时依赖

| 依赖 | 要求 | 置信度 |
|------|------|--------|
| 安装器前置 | 非 Windows：**Git**（+ Linux `curl`/`xz-utils`）；Desktop 可能要 g++/build-essential | **confirmed** |
| **Python** | **3.11**（via **uv**，安装器自动） | **confirmed** |
| **Node.js** | v22（浏览器自动化 / WhatsApp bridge）；开发文档写 20+ | **confirmed** |
| 工具 | ripgrep、ffmpeg（安装器可装） | **confirmed** |
| Windows | 便携 Git Bash（MinGit）解到 `%LOCALAPPDATA%\hermes\git` | **confirmed** |

### 2.3 作为本地内核如何启动（相对 openclaw）

| 入口 | 形态 | 与 openclaw 对照 | 置信度 |
|------|------|------------------|--------|
| `hermes` | 交互 CLI/TUI | openclaw 也有 CLI，但「产品主集成」不同 | **confirmed** |
| `hermes gateway` / `hermes gateway start` | Messaging Gateway 长驻 | 类似 openclaw Gateway **常驻**，但协议面不同（messaging 为主，非 openclaw WS 协议） | **confirmed** |
| `hermes gateway install` | launchd / systemd 服务 | 与 openclaw `gateway install` 同范式 | **confirmed**（文档与教程；细节以版本为准） |
| **`hermes acp`** | **stdio JSON-RPC** | **更适合「IDE/宿主 spawn 子进程」嵌入**；openclaw 主模型是 WS | **confirmed** |
| Python library | 进程内 | openclaw 无对等「官方一等 in-process SDK 主路径」 | **confirmed** |

### 2.4 版本 / 更新

| 项 | 事实 | 置信度 |
|----|------|--------|
| 发布 | GitHub Releases 有版本标签（T-003 曾见 `v2026.7.x` / 产品版本号） | **confirmed**（节奏随时间变） |
| 更新命令 | `hermes update`；**按安装布局自动检测** pip / git installer / Homebrew / Nix | **confirmed** |
| 配置迁移 | 更新后可能 `hermes config check` / `hermes config migrate` | **confirmed** |
| 精确 pin / 有监督回滚 | 公开安装页未展开与 openclaw 同级的 channel + staged swap 文档 | **未能确认**（需源码/CLI help 再钉） |

### 2.5 对照小结

| 维度 | openclaw | hermes |
|------|----------|--------|
| 语言/runtime | **Node** | **Python 3.11 + uv**（+ 可选 Node） |
| 默认分发 | npm + installer | git+uv installer / Desktop |
| 桌面 companion | 官方 macOS app + Windows Hub | 官方 Desktop installer |
| 与原生 app 最贴合的控制面 | **WS localhost Gateway** | **ACP stdio**（或自管 gateway 进程） |
| 自更新成熟度（文档） | 很高（channel/tag/rollback/handoff） | 中等（有 update + method 检测） |
| 嵌入成本 | 需托管 Node+包+端口+服务 | 需托管 Python venv+依赖；ACP 子进程模型更轻 | 

---

## §3 把本地进程内核嵌入原生桌面 app 的打包方式

### 3.1 三种打包策略

| 策略 | 做法 | 优点 | 缺点 | 与 openclaw/hermes 匹配度 |
|------|------|------|------|---------------------------|
| **A. 随 app bundle 全量内嵌** | Node/Python tree + 内核装进 `.app`/`Program Files` | 离线、版本强绑定 | 体积大；签名/公证难；内核更新=app 更新；沙箱冲突 | **低**（openclaw 官方明确不这么做） |
| **B. 独立安装器 / 首启下载（managed prefix）** | app 只带 bootstrap；首次把 runtime 装到 `~/Library/Application Support/...` 或 `~/.openclaw` | 体积可控；内核可独立更新；符合官方 companion | 需网络；需校验与失败恢复 | **高（推荐基线）** |
| **C. 假设用户已全局安装** | app 只探测 PATH 上的 CLI | 实现最简单 | 非专家用户失败率高；版本不可控 | **低**（与「开发者非专家」冲突） |

### 3.2 成熟范式

| 范式 | 做法摘要 | 对 D7 的启发 | 置信度 |
|------|----------|--------------|--------|
| **OpenClaw macOS companion** | app **不** bundle Node/Gateway；首启装 user-space Node+CLI 到 `~/.openclaw`；**LaunchAgent** 保活；WS 连接；版本兼容检查；Sparkle 协调 app+Gateway 更新 | **最直接对标**（同内核生态） | **confirmed** |
| **Ollama** | 发布 **平台原生二进制** + macOS DMG；模型权重**另下**；本地 HTTP API | 若内核是单二进制则最理想；**openclaw/hermes 不是这种** | **confirmed**（分发形态）；嵌入第三方 app 时常「依赖用户已装 Ollama」| **部分** |
| **VS Code / LSP** | 扩展 **spawn 独立 language server 进程**；stdio/socket/JSON-RPC；二进制可随扩展下载 | 与 hermes **ACP**、与「独立进程内核」同构 | **confirmed** |
| **IDE 扩展下发 server**（通用） | 首启下载平台相关 server 到扩展目录，校验 hash，再 spawn | 即策略 B 的标准工程化 | **confirmed**（行业惯例） |

### 3.3 macOS 现实

| 主题 | 现实做法 | 置信度 |
|------|----------|--------|
| 分发格式 | 公证（notarized）**DMG/ZIP** + Developer ID 签名；Gatekeeper | **confirmed** |
| App Store 沙箱 | 子进程**继承沙箱**；agent 要跑 shell/文件系统/本地服务时，**App Store 沙箱通常过严** | **confirmed**（Apple 文档 + 工程常识） |
| 网络 entitlement | 沙箱 app 若做 server/client 需 `network.client` / `network.server` 等 | **confirmed** |
| 对 D7 建议 | **优先非 App Store 直发 + notarization**；内核跑在**用户空间 managed prefix**，不必塞进 sandbox container | **建议（基于事实）** |
| 服务模型 | LaunchAgent（openclaw 官方）vs app 子进程（LSP 式）；LaunchAgent 利：app 退出内核仍在；弊：生命周期/权限归因更复杂 | **confirmed**（openclaw 选择 LaunchAgent） |
| 状态目录 | openclaw 明确：**勿放 iCloud 同步目录** | **confirmed** |

来源：
- https://docs.openclaw.ai/platforms/mac/bundled-gateway
- https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- https://docs.openclaw.ai/platforms/macos

### 3.4 Windows 现实

| 主题 | 现实做法 | 置信度 |
|------|----------|--------|
| 分发 | 签名安装器（EXE/MSI）或 **MSIX** sideload；SmartScreen 需信誉/签名 | **confirmed** |
| 防火墙 | **Loopback（127.0.0.1）** 通常**不**被默认防火墙拦；绑定 `0.0.0.0` 或非 loopback 才更需要规则/用户提示 | **部分**（社区/运维共识；环境策略可变） |
| MSIX | 可声明 firewall 扩展；桌面 agent 全功能时常更偏 **经典安装器** | **部分** |
| openclaw Windows | 原生 install.ps1；daemon=Scheduled Task（+ Startup 回退）；另有 Windows Hub；WSL2 为可选推荐路径之一 | **confirmed** |
| hermes Windows | 原生 PowerShell 安装器 + 便携 Git Bash；不强制 WSL | **confirmed** |

### 3.5 与「非 Electron / 原生 Swift·C#」的关系

- Electron 的「随 app 带 Node」**不能**直接平移：你们的 **app 是原生 UI**，内核仍是 **另一套 Node/Python runtime**。
- 正确类比是 **「原生 shell + 外置 managed runtime」**（OpenClaw.app、多数 LSP 宿主），不是「把 UI 写成 Electron 以便共用 Node」。

---

## §4 内核版本管理与更新

### 4.1 解耦模型

| 模型 | 描述 | openclaw 官方倾向 | 建议给 D7 |
|------|------|-------------------|-----------|
| **强绑定** | app 版本 = 内核版本，随 app 升级 | 签名 app 有「Update Mac app + Gateway」协调路径，**偏好匹配版本** | 可作 **默认体验** |
| **弱解耦** | app 声明兼容范围；内核可独立升 | CLI/`openclaw update` 可独立；app 做兼容检查，不兼容则引导安装 | **应支持**（修内核不必发整包 app） |
| **完全独立** | 内核自行 auto-update，app 不管 | auto-update 默关；managed handoff 存在 | **默认关闭内核无人值守自更新**，由 app 调度 |

### 4.2 稳定钉版

| 动作 | openclaw | hermes |
|------|----------|--------|
| 钉通道 | `update.channel = stable` / extended-stable | 安装后跟 git/tag 或 Desktop 通道（文档弱于 openclaw） |
| 钉精确版本 | `openclaw update --tag x.y.z` 或安装时 `--version` | git checkout / pip VCS pin；精确产品化 **部分/未能确认** |
| 兼容矩阵 | app checks Gateway version vs app version | 需自建 |

### 4.3 更新路径对比

| 路径 | 说明 | 风险 |
|------|------|------|
| **内核自更新** | openclaw `update.run` / CLI update；detached handoff 停服务→换包→重启 | 与 app 监督器竞态；扩展-stable 不自动 apply |
| **随 app 更新** | Sparkle/自研 updater 升 app，再拉匹配内核 | 发布节奏慢；但用户心智简单 |
| **app 调度内核更新** | app 调官方 updater 或自己下载到 prefix 后原子替换 | **最可控**；推荐 D7 主路径 |
| **回滚** | openclaw 文档完备（tag 回退、备份、SQLite 迁移注意） | hermes 回滚契约弱于 openclaw → 实现时要自建备份 |

### 4.4 状态 vs 代码

- **代码/runtime** 可替换；**会话/凭证/配置** 在 state 目录——更新不应抹 state（openclaw updater 明确保留 `~/.openclaw` state）。
- 重大 schema 迁移可能阻止裸降级（openclaw session SQLite 案例）→ D7 必须记录 **kernel migration epoch**。

来源：https://docs.openclaw.ai/install/updating 、https://docs.openclaw.ai/platforms/macos

---

## §5 多内核可切的分发影响

### 5.1 打包策略选择

| 策略 | 内容 | 体积/成本 | 适合 |
|------|------|-----------|------|
| **默认 + 按需** | 首装只 bootstrap **openclaw stable**；hermes 在用户切换时下载 | 初装小；切换时需网络 | **推荐** |
| **全量预装** | openclaw Node tree + hermes Python tree 全打进安装器 | 大；双运行时维护噩梦 | 不推荐成本敏感场景 |
| **仅清单** | app 只带 manifest/URL/hash，全运行时按需 | 最小安装器 | 与推荐等价（工程更彻底） |

### 5.2 切换内核时的进程管理

| 关注点 | 要求 |
|--------|------|
| **单活 vs 多活** | 建议 **同时只跑一个「活动内核」**（降端口冲突与资源）；允许预装多 runtime 目录 |
| **传输差异** | openclaw：**连已有 WS** 或启动 LaunchAgent；hermes：**spawn `hermes acp`** 或启 messaging gateway——**ProcessManager 必须插件化** |
| **状态隔离** | `OPENCLAW_*` / `HERMES_HOME` 分目录；禁止共用 session DB |
| **已装实例探测** | 用户机器可能已有全局 openclaw/hermes → 策略：优先 **app-managed prefix**，避免污染用户全局；可选「检测并提示接管」 |
| **迁移** | 存在 `hermes claw migrate`（配置/记忆），**不是 runtime 协议兼容**（T-003）→ 切换内核 ≠ 会话无损迁移 |

### 5.3 分发矩阵（建议默认）

| 内核 | 初装 | 下载触发 | 监督 |
|------|------|----------|------|
| openclaw（默认） | 首启或安装器可选组件 | 首次需要本地内核时 | LaunchAgent 或 app 监督服务 |
| hermes | 不预装 | 用户在设置中启用/切换 | ACP 子进程（优先）或 gateway 服务 |
| 未来内核 | 插件 manifest | 同按需 | 按 `describeCapabilities().model` |

---

## §6 适配度排序 + 对 D7 设计的建议

### 6.1 对目标用户画像的适配度排序

画像：**开发者非专家、优先 Mac、成本敏感、非 Electron、原生 Swift/C# client、X1 本地内核**。

| 排名 | 方案 | 适配分（1–5） | 理由 |
|------|------|---------------|------|
| **1** | **Managed prefix + 首启/按需下载 + 官方 updater 契约（openclaw 范式）** | **5** | 与 openclaw 官方 companion 一致；无系统 Node 门槛（install-cli 路径）；可钉 stable；体积与成本可控 |
| **2** | **Hermes 作第二内核：ACP 子进程 + 按需安装** | **4** | ACP 对原生宿主友好；但 Python/uv 栈与更新契约弱于 openclaw；非默认 |
| **3** | **依赖用户全局 CLI** | **2** | 实现便宜，非专家失败率高，版本漂移 |
| **4** | **全量内嵌双 runtime 进 .app** | **2** | 体积/签名/更新成本高；违背官方路径 |
| **5** | **Docker 桌面内核** | **1** | 与「非专家 Mac」冲突；桌面体验与权限差 |
| **6** | **App Store 沙箱内跑全能 agent Gateway** | **1** | 工具执行与文件/网络模型冲突概率高 |

### 6.2 对 D7 的推荐方案

#### 推荐架构名：**Native Shell + Managed Kernel Runtime（MS-MKR）**

```text
[Swift Mac app / C# Win app]
        |  监督 / 健康 / 更新编排 / 兼容矩阵
        v
[Kernel Runtime Manager]  ——  app-managed prefix
        |                         e.g. ~/Library/Application Support/<App>/runtimes/
        |                              openclaw/<version>/
        |                              hermes/<version>/
        +-- start/stop/status
        +-- pin channel + exact version + sha256
        +-- update / rollback / quarantine
        v
[openclaw Gateway]  WS 127.0.0.1:<port>     (默认)
[hermes acp]        stdio JSON-RPC          (可选第二内核)
        ^
        |  D2 KernelPort 适配
[App Gateway/JSON-RPC 客户端]
```

#### 打包

1. **安装器/DMG 只带**：原生 UI + bootstrap 脚本/小工具 + **manifest**（内核 id、兼容范围、下载 URL 模板、校验和）。
2. **不**把完整 Node/Python 树打进签名的主 bundle（可把 **bootstrap** 打进 bundle，payload 外置）——对齐 OpenClaw.app。
3. **Mac**：Developer ID + **notarized DMG**；默认 **非沙箱** 或仅 UI 轻沙箱、内核在沙箱外 managed 目录。
4. **Windows**：签名安装器优先；Gateway **bind loopback**；避免无意义的防火墙弹窗。

#### 默认内核与更新

1. 默认 **openclaw `@stable`（npm `latest` 或发布时钉死的精确版本）**。
2. 生产发布建议：**钉精确版本号**（可复现），而不是浮动 `latest` 无 pin；extended-stable 可作保守企业档。
3. **关闭**内核无人值守 auto-update（openclaw 本就默认关）；由 app 在用户确认或「安全补丁策略」下触发。
4. 更新状态机：`check → download to staging → verify → stop → atomic swap → start → health → commit`；失败回滚 staging。
5. app 与内核 **兼容矩阵**：`app >= X` requires `openclaw in [a,b]`；不兼容则阻断并引导。

#### 多内核

1. 首装 **只保证 openclaw 可运行**。
2. hermes：**设置页启用 → 下载 → 健康检查 → 可切换**。
3. 切换 = 停旧进程 + 起新 transport；**不做**虚假的「会话协议热切换」。

#### 进程监督（Mac 优先）

| 选项 | 建议 |
|------|------|
| openclaw | **优先 LaunchAgent 式用户服务**（官方路径）或等价「app 安装的 user service」；app 负责 install/repair，不假设自己是父进程 |
| hermes ACP | **app spawn 子进程**（stdio），生命周期跟会话/app 策略绑定 |
| 端口 | openclaw 使用 **可配置 loopback 端口**，避免与用户已有 18789 实例冲突；探测占用后分配 |

### 6.3 取舍理由（浓缩）

| 取舍 | 选择 | 为什么 |
|------|------|--------|
| 内嵌 vs 下载 | **下载到 managed prefix** | openclaw/hermes 非单二进制；官方 companion 已验证；安装包小 |
| 服务 vs 子进程 | **openclaw 服务化，hermes ACP 子进程** | 贴各自官方集成模型 |
| 默认内核 | **openclaw** | 任务已定默认；更新/钉版/文档最成熟；与 D2 WS 叙述一致 |
| 第二内核 | **hermes 按需** | 双 runtime 成本；ACP 适合后装 |
| 更新主权 | **app 编排，内核不裸奔 auto-update** | 非专家用户；可回滚；兼容矩阵 |
| 分发渠道 | **直发公证/签名，不走严格沙箱商店当 v1** | agent 本地权限模型 |

### 6.4 风险清单

| 风险 | 等级 | 缓解 |
|------|------|------|
| 首启需网络下载 Node/包失败 | 高 | 重试、镜像、离线安装包 SKU、清晰错误 |
| 用户已装全局 openclaw 版本冲突 | 中 | 强制 app-managed prefix；探测并提示 |
| 内核 breaking change / schema 迁移 | 高 | 钉版 + 兼容矩阵 + 备份 state |
| hermes 更新/回滚契约弱 | 中 | 自建 tarball 镜像与校验，不裸依赖 `hermes update` |
| Mac 签名/TCC/公证导致 helper 权限不粘 | 中 | 稳定签名 identity；参考 openclaw permissions 文档 |
| Windows 安全软件误报 Node/脚本 | 中 | 签名、信誉、减少「curl \| bash」用户可见路径（改 app 内 HTTPS 下载） |
| 体积与磁盘（双 runtime） | 中 | 按需；清理未用版本 |
| 把 Docker 当地桌面默认 | 低（若误选则高） | D7 明确非默认 |

### 6.5 D7 规格应写下的硬字段（PRD 输入草稿）

```text
KernelDistribution
  defaultKernel: openclaw
  layout: app-managed-prefix
  openclaw:
    package: npm:openclaw
    channel: stable | extended-stable
    pin: exact-version
    start: gateway-service (loopback WS)
    update: app-orchestrated | openclaw-update-cli
  hermes:
    package: git+uv | desktop-equivalent-layout
    install: on-demand
    start: acp-stdio | gateway-service
  appBundle: no-full-runtime-payload
  mac: notarized-dmg, non-app-store-v1
  win: signed-installer, loopback-first
  multiKernel: single-active-runtime, multi-installed-ok
  rollback: required
  offlineSku: optional later
```

---

## 主要来源索引

| 主题 | URL | 置信度 |
|------|-----|--------|
| OpenClaw 安装总览 | https://docs.openclaw.ai/install | confirmed |
| Installer 内幕 | https://docs.openclaw.ai/install/installer | confirmed |
| 更新与回滚 | https://docs.openclaw.ai/install/updating | confirmed |
| 发布通道 | https://docs.openclaw.ai/install/development-channels | confirmed |
| Gateway CLI | https://docs.openclaw.ai/cli/gateway | confirmed |
| macOS app | https://docs.openclaw.ai/platforms/macos | confirmed |
| macOS bundled gateway（**不内嵌 runtime**） | https://docs.openclaw.ai/platforms/mac/bundled-gateway | confirmed |
| OpenClaw GitHub | https://github.com/openclaw/openclaw | confirmed |
| Hermes 安装 | https://hermes-agent.nousresearch.com/docs/getting-started/installation | confirmed |
| Hermes GitHub | https://github.com/NousResearch/hermes-agent | confirmed |
| Hermes Python library | https://hermes-agent.nousresearch.com/docs/guides/python-library | confirmed |
| Hermes ACP / quickstart | https://hermes-agent.nousresearch.com/docs/getting-started/quickstart | confirmed |
| Ollama 分发 | https://ollama.com/download/mac 、https://github.com/ollama/ollama | confirmed |
| VS Code LSP 独立进程 | https://code.visualstudio.com/api/language-extensions/language-server-extension-guide | confirmed |
| macOS App Sandbox | https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox | confirmed |
| 既有内核接口事实 | `~/.llm-wiki/agent-app-design/kernel/kernel-ecosystem-facts.md`、`.hopper/handoffs/T-003-output.md` | confirmed（前序任务） |

---

## 研究边界（诚实声明）

- 未在本机实际执行 install 或测量包体积（纯 web/文档调研）。
- Windows Hub 与 Hermes Desktop 的**内部文件树/是否 Electron**未做安装包逆向。
- npm `latest` 的**当日精确版本号**未锁定（动态）。
- 防火墙在企业强化策略下的表现标为部分确认。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "执行 T-035：先读已有内核生态事实，再围绕分发/打包/更新做调研并落盘产出。已有事实只覆盖接口形态；接下来补分发、打包与更新层的一手来源。事实已齐：openclaw 官方即「原生 companion + 首启下载 runtime」范式。正在落盘完整调研产出。# T-035 完成\n\n调研已落盘：`.hopper/handoffs/T-035-output.md`\n\n## 核心结论\n\n**openclaw / hermes 都不是「单文件塞进 .app」型内核**，而是：\n\n| 内核 | 分发 | 运行时 | 主启动 |\n|------|------|--------|--------|\n| **openclaw** | npm + install 脚本（Docker/git 可选） | **Node 22/24/25** | `openclaw gateway` → WS `127.0.0.1:18789`；LaunchAgent/systemd/计划任务 |\n| **hermes** | git+uv 安装器 / Desktop installer | **Python 3.11 + uv**（+ 可选 Node） | CLI / `hermes gateway` / **`hermes acp`（stdio）** |\n\n## 对 D7 最关键的官方事实\n\nOpenClaw **macOS companion 明确不内嵌 Node/Gateway**：首启下载到 `~/.openclaw`，用 **LaunchAgent** 保活，app 只做监督与版本匹配。这是 D7 最直接的对标范式。\n\n## 推荐方案（摘要）\n\n**Native Shell + Managed Kernel Runtime**\n\n1. 安装包只带原生 UI + bootstrap/manifest  \n2. 默认 **按需下载并钉住 openclaw stable 精确版本**  \n3. hermes **切换时再下**（ACP 子进程优先）  \n4. 内核更新由 **app 编排**（默认关闭内核裸 auto-update）  \n5. Mac：公证 DMG、非 App Store 沙箱 v1；Windows：签名安装器 + loopback  \n\n**Verdict: PASS**",
  "stopReason": "EndTurn",
  "sessionId": "019f885f-7567-7370-9068-075fdbf917e1",
  "requestId": "451a7232-a9e0-458f-8c35-051a75cc1dd8",
  "thought": "The user wants me to execute a research task (T-035) about local kernel distribution packaging for an agent app. Let me carefully read the requirements:\nI have good context from T-003 and the kernel ecosystem facts. Now I need to research the distribution/packaging/update layer for openclaw and hermes, plus how similar products embed local process run...Excellent detail on openclaw. Let me fetch more pages on updating, docker, development channels, hermes install, and packaging patterns.I have excellent detail on openclaw and hermes distribution. Let me get a few more details on:I have enough material to write a comprehensive research document. Let me also quickly check the bundled gateway docs and hermes gateway start commands for completeness.This is gold - OpenClaw.app itself does NOT bundle Node/Gateway - it downloads them on first run under ~/.openclaw. This is exactly the pattern for D7.\n**Summary**  \n我完成了 T-035 的 PRD 研究，针对 D7 本地内核分发打包方案调研了 openclaw 和 hermes 的真实形态。核心发现：openclaw 采用 npm 包 + 下载式分发（~/.The task is complete. I've written the full research deliverable. Let me give a concise summary of what was delivered.",
  "usage": {
    "input_tokens": 94319,
    "cache_read_input_tokens": 418304,
    "output_tokens": 11145,
    "reasoning_tokens": 1666,
    "total_tokens": 523768
  },
  "num_turns": 7,
  "total_cost_usd": 0.4509992,
  "total_cost_usd_ticks": 4509992000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 94319,
      "outputTokens": 11145,
      "cacheReadInputTokens": 418304,
      "modelCalls": 7,
      "costUSD": 0.4509992
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 220890
- end_time: 2026-07-22T05:53:23.201Z
- log: see `T-035-output.log` for raw output
