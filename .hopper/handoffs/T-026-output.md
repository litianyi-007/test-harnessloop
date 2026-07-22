---
task_id: T-026
adapter: grok
model: grok-4.5
status: done
task_type: prd-research
language: zh-CN
researched_at: 2026-07-22
phase: done
last_progress_at: "2026-07-22T03:15:00.000Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
end_time: "2026-07-22T02:34:14.779Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 254459
adapter_status: success
---

# T-026 — D4 跨平台原生架构调研 spike（PRD 输入）

## Summary

本任务对「Mac 原生优先 + Windows 跟随、非 Electron、共享业务/内核客户端核心」的主流架构方案做了只读 web 调研，覆盖 Rust+FFI、C/C++ 核心、TS/Node sidecar、KMP、.NET（MAUI/Uno/Avalonia）及其它现实选项，并归纳代码共享边界、Mac→Win 跟随工作流、以及 D1/D2 契约对选型的含义。结论：**对本项目（D2 已是语言中立 JSON-RPC 进程屏障、内核为独立本地进程、团队成本敏感且优先 Mac）最适配的是「契约驱动 + 双端原生 UI + 共享 TS kernel-client（可升 sidecar）」**；Rust/UniFFI 适合未来加重客户端核心时升级，不建议作为 Day-1 默认；MAUI/Avalonia/Uno/Electron/Tauri 均不满足「原生非 Electron」的严格读法。

## Files touched

- `.hopper/handoffs/T-026-output.md` — 任务指定的唯一落盘产出（调研结论）

## Acceptance verification (5/5)

| # | 准则 | 结果 | 证据 |
|---|------|------|------|
| 1 | 共享核心 + 原生 UI 主流方案逐项列出现状（FFI/绑定/案例） | **通过** | 见 §1 |
| 2 | 代码共享边界常见划法 | **通过** | 见 §2 |
| 3 | Mac 先行 / Windows 跟随工程工作流 | **通过** | 见 §3 |
| 4 | D1/D2 契约如何帮到跨平台 | **通过** | 见 §4 |
| 5 | 对「非专家 / Mac 优先 / 成本敏感」适配度排序 + D4 设计建议 | **通过** | 见 §5 + 「对 D4 设计的建议」 |
| 额外 | 每条事实带来源 URL + 置信度；中文；只读 | **通过** | 全文中文；仅写本文件；来源与置信度标注于各节 |

## Decisions / deviations

1. **「只读硬约束：不改任何文件」与「落盘 T-026-output.md」**：按既有 hopper 任务惯例，**仅写指定交付物**，不改 app 代码、不写 `~/.llm-wiki/`。
2. **「非 Electron 原生」判定口径**：将 Electron、Tauri/WebView 壳、Avalonia/Uno 默认 Skia 自绘 UI 归为**不满足严格原生 UI**；Node/TS **sidecar 进程**若 UI 仍是 SwiftUI/WinUI，则**可算原生 UI + 本地服务**（类似 VS Code 的 JSON-RPC sidecar 思路，但 UI 不用 Web）。
3. **D1/D2 以任务 brief 为权威**：未读取 `~/.llm-wiki` 正文；D1=进程内语义接口（TS 表达）、D2=跨 UI↔内核 JSON-RPC wire、内核=独立本地进程——按 brief 采用。
4. **1Password 案例边界**：公开材料证实 Rust Core + 薄原生前端目标，但 macOS 桌面最终部分走了 Electron；作「共享核心」案例有效，作「严格原生 Mac」反例亦有效。

## Open questions

1. Windows 端原生 UI 栈最终选 **WinUI 3 / WPF / 其它**？（影响 §1 .NET 绑定路径与 C# UniFFI 价值）
2. 共享 TS 客户端是否需要 **打包为无 Node 运行时依赖的 sidecar 二进制**（pkg/sea），还是开发期允许本机 Node？
3. D2 schema 是否已有（或计划有）**机器可读 JSON Schema / 多语言 codegen** 入口？这直接决定「共享实现」vs「各自实现 + 契约测试」的成本比。
4. openclaw/hermes 进程与「产品侧本地状态」（会话列表、审批队列展示缓存、用量汇总）是否允许 **同一 Node 进程共置**，还是必须严格三进程（UI / product-sidecar / kernel）？

## Verdict

**PASS**

## Next recommendation

1. 用本报告起草 **D4 架构 ADR**：推荐默认路径 = **SwiftUI(Mac) + WinUI/C#(Windows) + 共享 `packages/kernel-client`（TS，实现 D2 编解码与 D1 语义外观）+ 契约金标测试**；可选升级 = product sidecar。
2. 在 monorepo 骨架中先落：`contracts/d2/`（schema+fixtures）→ `packages/kernel-client` → `apps/mac` 最小壳打通 createSession/subscribe → Windows 仅消费同一 package 的 parity checklist。
3. **不要**在 D4 首版引入 Rust 核心或 KMP/.NET 跨端 UI；除非后续出现强加密/离线同步等「值得付 FFI 税」的客户端重逻辑。

---

## §1 共享核心 + 原生 UI：主流架构方案

> 场景约束回顾：Mac 原生 UI 优先、Windows 跟随、非 Electron；业务内核（openclaw/hermes）已是**独立本地进程**，UI↔内核走 D2 JSON-RPC。故「共享核心」主要指 **app 侧内核客户端 + 产品逻辑**，不是重写 agent 内核。

### 1.1 Rust 核心 + FFI（→ Swift/SwiftUI、→ Windows）

| 维度 | 现状 |
|------|------|
| 模式 | 业务逻辑写在 Rust 静态库/动态库，经 FFI 被各端原生 UI 调用；UI 止于平台工具包。 |
| 绑定工具 | **UniFFI**（Mozilla）：一等支持 Kotlin/Swift/Python/Ruby；官方称 production-ready，但未到 1.0。第三方：**C#**（NordSecurity `uniffi-bindgen-cs`）、Go、Dart、Node（早期）等。另有 **swift-bridge**（Rust↔Swift 专用，社区认为 bus factor 较高、整体成熟度低于 UniFFI）、**Diplomat**（偏 C/C++）、**Interoptopus**（C#/C/Python）。 |
| 成熟度 | UniFFI 在 Firefox 移动/桌面组件广泛使用；Mozilla 明确「ready for production use」。Windows 路径依赖第三方 C# bindgen，成熟度 **低于** Swift/Kotlin 官方轨。 |
| 生产案例 | **1Password**：共享 Backend/Core 用 Rust，「止于 UI」；Windows 团队 2017 起试 Rust，Win7 时代约 70% 重逻辑在 Rust；1Password 8 把服务通信、DB、权限、密码学等放进 Core。**注意**：Linux/Windows 前端曾选 web/Electron，macOS 最终也曾为进度放弃 SwiftUI Mac 轨、用 Electron 覆盖——说明「Rust 核心 ≠ 全端原生 UI」。Mozilla Glean/应用服务：Rust + UniFFI → Swift/Kotlin。 |

**利弊（对本项目）**

- 利：性能与内存安全；单核心多端一致性（搜索/权限等「结果必须一致」的逻辑）；可同时喂 macOS Swift 与 Windows C#（借助 uniffi-bindgen-cs）。
- 弊：团队需 Rust + FFI 工程能力；Windows 绑定非一等公民；对 **已是 JSON-RPC 的 D2** 来说，用 Rust 再实现一层客户端可能「重复付税」——除非客户端有重计算/加密/本地索引。

**置信度**：**confirmed**（UniFFI 官方 README、1Password 官方博文、NordSecurity C# bindgen 仓库）  
**来源**

- https://github.com/mozilla/uniffi-rs  
- https://mozilla.github.io/uniffi-rs/  
- https://github.com/NordSecurity/uniffi-bindgen-cs  
- https://1password.com/blog/1password-8-the-story-so-far  
- https://dteare.medium.com/behind-the-scenes-of-1password-for-linux-d59b19143a23  
- https://serokell.io/blog/rust-in-production-1password  
- https://forums.swift.org/t/the-state-of-swift-rust-interoperability/72205  

---

### 1.2 C/C++ 核心 + 原生 UI 绑定

| 维度 | 现状 |
|------|------|
| 模式 | 非 UI 模型层用 C/C++，UI 用平台原生；接口常做成「进程内 client-server / 消息拷贝」而非共享可变对象。 |
| 工具链 | macOS：Objective-C++ 直接链 C++；Windows：常规 DLL/COM 或 C API。跨语言 IDL 历史工具如 Dropbox **Djinni**。 |
| 生产案例 | **Dropbox（2013–约 2019）** 在 iOS/Android 用 C++ 共享 model（Mailbox/Carousel）：UI 原生，C++ 当「永不离线的 server」，DataView/ChangeSet 驱动 UI。**2019 Dropbox 公开放弃**：非标准栈的框架自建、调试、平台分叉集成、招聘/留人成本 > 「写两遍」收益，改回 Swift/Kotlin 原生。 |
| Qt 路线 | C++ 核心 + Qt Widgets/QML 可跨 Mac/Win，但 UI **不是** AppKit/WinUI 原生控件路径，偏「统一 toolkit」，与「各自原生 UI」目标部分冲突。 |

**利弊**

- 利：编译到全平台；历史桌面软件传统；零 GC 运行时。
- 弊：现代团队招聘/DX 差；Dropbox 长文可视为**对共享 C++ 的负面证据**；与 D1 的 TS 契约表达距离最远。

**置信度**：**confirmed**（Dropbox 官方 2019 复盘 + 2014 技术总结）  
**来源**

- https://dropbox.tech/mobile/the-not-so-hidden-cost-of-sharing-code-between-ios-and-android  
- https://oleb.net/blog/2014/05/how-dropbox-uses-cplusplus-cross-platform-development/  
- https://dropbox.tech/infrastructure/rewriting-the-heart-of-our-sync-engine（后续 sync 核心改 Rust，属服务端/引擎层，非 UI 共享范式）  

---

### 1.3 TS/Node 核心：嵌入原生壳 或 本地 sidecar

| 子方案 | 描述 | 是否算「非 Electron 原生」 |
|--------|------|---------------------------|
| **A. 原生 UI + Node/TS sidecar** | SwiftUI/WinUI 只做壳；产品逻辑与 D2 客户端在本地 Node（或打包二进制）进程，经 **localhost / Unix socket / named pipe / stdio + JSON-RPC** 通信 | **是**（UI 原生；TS 是本地服务，不是用 Chromium 画 UI） |
| **B. 原生 UI + 进程内嵌入 JS 引擎** | 如 JavaScriptCore / 自嵌 V8 跑 TS 编译产物 | **是**，但工程复杂度高，少见桌面生产默认 |
| **C. Electron / Tauri + Web UI** | UI 用 HTML/WebView | **否**（违反「非 Electron / 原生 UI」） |

**行业支撑**

- JSON-RPC over stdio 是 **LSP / VS Code 扩展宿主** 成熟范式；.NET `StreamJsonRpc` + Node `vscode-jsonrpc` 有公开互操作示例。  
- Tauri 文档明确支持 **Node.js sidecar**（打包为无 Node 安装依赖的二进制），IPC 可用 localhost/stdin/socket——模式可迁移到「Swift/WinUI 宿主 + sidecar」，不必用 Tauri UI。  
- 社区案例：Tauri + Node sidecar（Hono/pkg）做 local-first 后端；Evil Martians 文也描述 sidecar 任意语言 + TCP，上层可叠 JSON-RPC。

**与 D1/D2 贴合度（关键）**

- D1 以 **TS 表达**进程内语义；D2 wire **本就是 JSON-RPC**。  
- 用 **同一语言（TS）** 实现「D2 编解码 + 会话状态机 + 产品服务」，再让原生 UI 只做渲染与系统集成，是阻抗最小路径。  
- 进程模型可与内核对齐：`UI 原生进程` ↔（可选 product sidecar）↔ `kernel 进程`，全部语言中立消息。

**利弊**

- 利：复用 D1/D2 已有 TS 资产与人才；契约演进快；sidecar 可独立测；崩溃隔离。  
- 弊：多一进程与打包体积；需处理 sidecar 生命周期/升级；严格「零 Node 运行时」要 sea/pkg 等打包链；若错误地用 WebView 画 UI 则滑向 Electron 形态。

**置信度**：**confirmed**（模式与工具链）；对本 app 的最终进程切分 **部分**（需产品决策）  
**来源**

- https://v2.tauri.app/learn/sidecar-nodejs/  
- https://medium.com/ingeniouslysimple/building-an-electron-app-from-scratch-part-4-5d0906897bf1（JSON-RPC over stdio 跨语言）  
- https://evilmartians.com/chronicles/making-desktop-apps-with-revved-up-potential-rust-tauri-sidecar  
- https://www.npmjs.com/package/json-rpc-2.0  
- https://github.com/codeforreal1/Local-First-Desktop-App-Rust-NodeJS  

---

### 1.4 Kotlin Multiplatform（KMP）共享核心 + 原生 UI

| 维度 | 现状 |
|------|------|
| 模式 | `commonMain` 写共享逻辑（Kotlin）；`iosMain`/`androidMain`/`desktopMain` expect/actual；UI 可原生或 **Compose Multiplatform**。 |
| Desktop | Compose Multiplatform Desktop 宣称 production-ready，目标 Windows/macOS/Linux，**JVM 渲染**，非 AppKit/WinUI 控件。 |
| 原生 UI 路径 | 移动端常见「KMP 逻辑 + SwiftUI/UIKit/Jetpack」；**桌面双端各自原生 UI + 仅共享 KMP 逻辑**可行但生态案例弱于移动。 |
| 与 Mac 优先 | Mac 团队要学 Kotlin/Gradle；系统集成仍要 Swift 桥；对「优先 Mac 原生体验」的桌面产品，KMP 的主收益在移动多端，而非 Mac→Win 桌面。 |

**置信度**：**confirmed**（官方 Compose Multiplatform 定位）；桌面「KMP 逻辑 + 双端纯原生 UI」大规模案例 **未能确认**  
**来源**

- https://kotlinlang.org/compose-multiplatform/  
- https://github.com/jetbrains/compose-multiplatform  
- https://www.marcogomiero.com/posts/2025/compose-desktop-macos-api-jni/  

---

### 1.5 .NET（MAUI / Uno / Avalonia）

| 框架 | 渲染/原生性 | Mac/Win 现状 | 与「原生非 Electron」适配 |
|------|-------------|--------------|---------------------------|
| **.NET MAUI** | 偏**原生控件映射**（移动出身） | macOS 路径常涉及 **Mac Catalyst** 社区/能力争议；桌面评价两极，有生产吐槽「Mac+Win+Linux 未就绪」 | UI 层有一定原生性，但 **Mac 优先桌面** 体验与工具链风险高；**不推荐作 D4 主 UI** |
| **Uno Platform** | 可选 **Native** 或 **Skia** 渲染；2025 起默认更偏 Skia 一致性 | Win/Mac/Linux/Web 全覆盖 | Skia 路径 = **跨平台自绘**，非 WinUI/AppKit 手感；与「各自原生」目标不符 |
| **Avalonia** | **自绘 UI**（WPF 血统），非 OS 原生控件 | 桌面三端口碑较好 | **明确是跨平台渲染框架**，不是「Mac 原生 + Win 原生」；不满足严格约束 |

**可取之处**：若 Windows UI 选 **WinUI 3 / C#**，.NET 仍是 Windows 端实现语言；**共享核心不必是 MAUI**——可以是「C# Win 客户端 + 其它共享层」。

**置信度**：**confirmed**（框架官方/社区对渲染模型的公开定位）  
**来源**

- https://docs.lextudio.com/blog/the-story-about-net-cross-platform-ui-frameworks-dd4a9433d0ea  
- https://avaloniaui.net/blog/wpf-modernization-in-2026  
- https://platform.uno/articles/best-cross-platform-frameworks-2026/  
- https://dev.to/biozal/the-net-cross-platform-showdown-maui-vs-uno-vs-avalonia-and-why-avalonia-won-ian  
- https://news.ycombinator.com/item?id=29407078  

---

### 1.6 其它现实方案

| 方案 | 要点 | 适配度（本项目） |
|------|------|------------------|
| **契约共享、实现双写** | 只共享 D2 schema + golden fixtures + OpenAPI/JSON-Schema；Mac/Win 各自写客户端 | 极高（Dropbox 2019 教训的「写两遍 UI+客户端」在 **协议已钉死** 时成本可控） |
| **Flutter 桌面** | 自绘 UI，非原生控件 | 低（同 Avalonia 类问题） |
| **Qt** | C++/QML 统一 toolkit | 中低（非各自原生） |
| **Go/Rust sidecar + 原生 UI** | 与 TS sidecar 同构，语言不同 | 中（若团队更熟 Go/Rust）；与 D1 TS 表达略疏远 |
| **Swift 全栈 + Windows 另起** | Mac 用纯 Swift；Windows 重写 | Mac 体验最好；跟随滞后风险大，除非契约测试极强 |

**置信度**：**部分**（行业常识 + HN/工程博文综合；无单一权威标准）

---

## §2 代码共享边界的常见划法

### 2.1 通常共享（高 ROI）

| 层 | 说明 | 证据/范式 |
|----|------|-----------|
| **协议/消息编解码** | D2 envelope、方法/事件类型、错误码、版本字段 | 语言中立 wire 的核心价值；JSON-RPC/LSP 生态 |
| **内核客户端** | 连接/重连、subscribe 流、req-id 相关、超时、能力协商 | 1Password Core「止于 UI」；Dropbox 共享 model |
| **一致性敏感的业务规则** | 搜索排序、权限判定、密码强度、审批状态机的**非 UI 迁移** | 1Password：搜索匹配逻辑进 Core，避免平台结果不一致 |
| **ViewModel / DataView 投影** | 把领域状态投影成 UI 可消费的不可变结构 + diff/ChangeSet | Dropbox Mailbox：ChangeSet 驱动列表动画 |
| **本地持久化策略（可选）** | 会话列表缓存、草稿、用量汇总算法 | 视是否要求跨端一致 |

### 2.2 必须各自原生（低共享 / 只做接口抽象）

| 层 | 说明 |
|----|------|
| **UI 渲染与交互范式** | SwiftUI/AppKit vs WinUI/WPF；导航、快捷键、窗口/多窗 |
| **通知 / 托盘 / 全局快捷键** | 各 OS API 差异大 |
| **文件系统与沙箱** | 书签权限、受控文件夹、安装目录约定 |
| **密钥链 / Credential Locker** | Keychain vs Windows Hello/Credential Manager |
| **无障碍、IME、拖放、打印** | 平台深度绑定 |
| **安装/更新/签名/公证** | pkg/dmg/notarization vs MSI/MSIX/SmartScreen |
| **后台执行策略** | launchd vs Windows 服务/后台任务 |

### 2.3 边界经验法则

1. **「行为必须跨端一致」→ 共享**；「必须感觉像本机 OS」→ 原生。  
2. **共享层通过消息/不可变快照与 UI 交互**（Dropbox 的 client-server in-process 心智），避免共享可变对象。  
3. **平台 API 差异不要硬塞进共享层**——共享层定义 port/interface，平台做 adapter（Dropbox 也承认网络/后台/文件系统常被迫平台化）。  
4. **共享并非免费**：Dropbox 结论是非标准栈开销可超过写两遍；**仅当共享物是「厚逻辑」或「强一致性」时才值得**。本项目的「厚逻辑」大半已在 **kernel 进程**，app 侧共享应偏 **薄但正确的客户端 + 产品规则**。

**置信度**：**confirmed**（1Password / Dropbox 原文可直接支撑）  
**来源**：同 §1.1、§1.2；另 https://www.ics.com/blog/heres-why-you-should-separate-ui-business-logic-your-application  

---

## §3 「Mac 先行、Windows 跟随」工程工作流

### 3.1 成熟范式（综合，非单一产品手册）

| 机制 | 做法 | 作用 |
|------|------|------|
| **Monorepo** | `apps/mac`、`apps/win`、`packages/*`、`contracts/*` 同仓 | 原子改契约+双端；避免版本漂移（monorepo 文献普遍强调 unified versioning / 共享库即时可见） |
| **契约驱动对齐** | D2 schema + golden JSON fixtures + 兼容性矩阵是「功能真相」 | Windows 不抄 Mac UI，只满足同一契约与产品验收表（D5 页） |
| **共享包语义化版本** | `kernel-client@x.y.z`；breaking = major | Mac 可先 bump；Windows 在 CI 显示「落后 major/minor」 |
| **功能切片顺序** | 先共享客户端 API → Mac UI 接通 → 契约测试绿 → Windows UI 跟 | 把滞后限制在 **渲染层**，不在协议层 |
| **Paradigm: Feature team 横向** | 1Password「feature team」同时推多前端 + Core | 适合有人力时；小团队可退化成「同一人先 Mac 后 Win，但 PR 必须带契约测」 |
| **Parity 看板** | 每 D5 页面/能力一行：Mac 状态 / Win 状态 / 阻塞依赖（共享包版本） | 可视化漂移 |
| **独立发布节奏** | monorepo 内独立 release tag（Microsoft ISE 等实践） | Mac 可先发；Win 跟随，不强制同日 |

### 3.2 反模式

- **无契约的「看 Mac 截图重做 Win」** → 行为漂移（1Password 早期四端独立的历史问题）。  
- **共享 UI 框架伪装成跟随**（Avalonia/Electron）→ 违反原生约束，且把 Mac 体验绑死在跨端最低公分母。  
- **共享层无限膨胀**（把通知/文件对话框也塞进共享）→ Dropbox 类开销重演。

### 3.3 建议的仓库骨架（示意，非实现）

```text
repo/
  contracts/
    d2/                 # schema, examples, compatibility notes
    d1/                 # semantic notes / TS types as source of truth
  packages/
    kernel-client/      # TS：D2 transport + D1-shaped facade
    kernel-client-fixtures/
  apps/
    mac/                # SwiftUI
    windows/            # WinUI 3 / C#
  tools/
    contract-tests/     # 对 mock kernel 跑双端或至少跑 TS client
  docs/
    parity-matrix.md    # Mac→Win 跟随表
```

### 3.4 最小滞后策略

1. **任何 Mac 功能若改 D2 用法**：必须先改 `contracts/` + `kernel-client` + 测试，再写 SwiftUI。  
2. **纯视觉/快捷键 Mac 特性**：允许 Win 滞后，parity 表标 `UI-only lag OK`。  
3. **Windows 启动门槛**：能连 mock kernel 跑完 D5 主路径（建会话/流式/审批/停止）即可算「跟随轨开通」，不必等视觉 polish。  
4. **版本门禁**：`apps/windows` CI 依赖 `kernel-client` 的最低版本；Mac  bump major 时自动开「Win 适配」issue。

**置信度**：**部分**（monorepo/版本化有充分公开实践；「Mac→Win 跟随」作为具名方法论无单一权威标准，上表为对 1Password 历史 + monorepo 工程常识的综合）  
**来源**

- https://1password.com/blog/1password-8-the-story-so-far（早期平台割裂 vs Core 后 feature team）  
- https://devblogs.microsoft.com/ise/streamlining-development-through-monorepo-with-independent-release-cycles/  
- https://www.gitkraken.com/blog/monorepos-benefits-costs-tools  
- https://amarchenko.dev/blog/2023-09-26-versioning/  

---

## §4 D1/D2 契约如何帮到跨平台

### 4.1 分层含义

| 契约 | 性质 | 跨平台含义 |
|------|------|------------|
| **D1 KernelPort** | **进程内语义接口**，TS 表达 | 定义「客户端外观」：方法、事件、错误、能力。是 **产品与 UI 编程模型**，不是 wire。可有多语言实现，但 **TS 是权威叙述语言** → 共享参考实现天然偏向 TS。 |
| **D2 Message Schema** | **JSON-RPC 风格 envelope**，跨 UI↔内核屏障 | **语言中立 wire**。任何能说 JSON + 本地传输的语言都可做客户端。内核 openclaw/hermes 已是独立进程 → **app 不被绑死在内核实现语言**。 |

### 4.2 对「共享核心 vs 各自实现客户端」的含义

1. **不强制共享实现语言**  
   D2 只强制 **消息形状与语义**。Mac 用 Swift 手写客户端、Windows 用 C# 手写客户端，只要通过同一套 fixture，就是合法架构。

2. **强烈鼓励共享「参考客户端」**  
   因 D1 以 TS 表达，维护一份 **TS `kernel-client`（D1 facade over D2）** 成本最低，可作为：  
   - Mac/Win 的 sidecar；或  
   - 契约测试中的 oracle；或  
   - 未来其它壳（CLI/调试器）的复用件。

3. **共享核心的正确厚度**  
   - **薄共享（推荐默认）**：D2 codec + 连接生命周期 + 与 D1 对齐的 API 外观 + 少量产品规则。  
   - **厚共享（可选升级）**：本地会话库、用量聚合、离线队列——仅当双端都需要且一致性敏感时再抽。  
   - **不要共享**：像素级 UI、系统集成。

4. **「各自实现客户端」何时合理**  
   若团队 Swift/C# 极强、不愿运维 Node，可 **双端原生客户端 + 共享 contracts 与 golden tests**。代价是每个 D2 变更改两处实现；用契约测试控制漂移。Dropbox 2019 的「写两遍」在 **协议层已由 D2 钉死** 时比「无协议四端乱写」便宜得多。

5. **进程边界可递归复用 D2 风格**  
   UI ↔ product-sidecar 也可使用与 D2 同风格的 JSON-RPC（或直接复用子集），降低心智模型数量。

**置信度**：**confirmed** 对 D1/D2 角色（任务 brief）；架构推论 **部分**（工程推理，非某官方跨平台指南）

---

## §5 对「非 server/跨平台专家、优先 Mac、成本敏感」的适配度排序

评分维度：学习曲线、与 D1/D2 贴合、原生约束符合度、Windows 跟随成本、招聘/长期维护。分数 1–5，**越高越适配**。

| 排名 | 方案 | 综合 | 学习曲线 | D1/D2 贴合 | 原生符合 | 跟随成本 | 备注 |
|------|------|------|----------|------------|----------|----------|------|
| **1** | **双端原生 UI + 共享 TS kernel-client（库或 sidecar）+ 契约测试** | **5** | 4 | 5 | 5 | 4 | 默认推荐 |
| **2** | **双端原生客户端双写 + 仅共享 D2 schema/fixtures** | **4** | 5 | 4 | 5 | 3 | 无 Node 运行时偏好时 |
| **3** | **Rust core + UniFFI（Swift + C#）** | **2.5** | 1 | 2 | 5 | 3 | 仅当客户端重逻辑出现 |
| **4** | **KMP 共享逻辑 + 双端原生 UI** | **2** | 2 | 2 | 4 | 2 | 桌面案例弱；Kotlin 税 |
| **5** | **C/C++ 共享核心** | **1.5** | 1 | 1 | 5 | 2 | Dropbox 负案例 |
| **6** | **.NET MAUI 一套 UI** | **1.5** | 3 | 2 | 2 | 4 | Mac 原生性质疑 |
| **7** | **Avalonia / Uno (Skia) / Flutter** | **1** | 3 | 2 | 1 | 5 | 跨端渲染 ≠ 原生 |
| **8** | **Electron / Tauri Web UI** | **1** | 4 | 3 | 0 | 5 | 直接违反约束 |

**排序理由（成本敏感视角）**

- 最大成本不是「多写一个 WinUI 页面」，而是 **错误抽象 + 冷门工具链 + 招聘**（Dropbox 已付过学费）。  
- 本项目已支付的「架构税」在 **D1/D2 契约**；应吃尽契约红利，而不是再引入 Rust/KMP 第二套税。  
- Mac 优先 → SwiftUI 是体验与 Apple 生态的默认最优；Windows 用平台主流（WinUI/C#）跟随，而不是找「一个 UI 框架统治两端」。

---

## 对 D4 设计的建议

### 推荐方案（默认）

**「契约驱动的双原生壳 + 共享 TS Kernel Client」**

```text
┌─────────────────┐     ┌─────────────────┐
│  Mac SwiftUI    │     │  Win WinUI/C#   │
│  (原生 UI/系统)  │     │  (原生 UI/系统)  │
└────────┬────────┘     └────────┬────────┘
         │  本地 IPC（可选同构 JSON-RPC）    │
         └────────────┬────────────────────┘
                      ▼
         ┌────────────────────────┐
         │ packages/kernel-client │  ← TS：D2 codec + D1 facade
         │ （进程内库 或 sidecar）  │     + 产品侧薄逻辑
         └────────────┬───────────┘
                      │ D2 JSON-RPC / 本地传输
                      ▼
         ┌────────────────────────┐
         │ openclaw / hermes 内核  │  （已定：独立进程）
         └────────────────────────┘
```

**边界划法**

| 共享 | 不共享 |
|------|--------|
| D2 编解码、传输适配、重连、req/事件分发 | SwiftUI / WinUI 视图与导航 |
| D1 形状的客户端 API（createSession/send/subscribe/…） | 通知、托盘、Keychain、文件选择器 |
| 契约 fixtures、mock kernel、兼容矩阵 | 安装器与签名 |
| 产品规则中「必须一致」的部分（如审批状态解释、用量聚合算法） | 视觉设计与平台交互习惯 |

**Mac→Win 跟随工作流**

1. Monorepo + `contracts/d2` 为唯一协议真相。  
2. 功能开发顺序：**契约 → kernel-client → Mac UI →（并行）Windows UI**。  
3. `parity-matrix.md` 按 D5 九页跟踪；允许 UI-only 滞后，禁止协议层双真相。  
4. `kernel-client` 语义化版本；Windows CI 钉最低版本。  
5. 小团队可不设 1Password 式大型 feature team，但 **禁止「只在 Swift 里写死 D2 字段」**——字段必经共享包或共享 schema。

### 取舍理由

| 为何选它 | 为何不选它者 |
|----------|--------------|
| 最大化吃 D1(TS)/D2(JSON-RPC) 已有投资 | Electron/Tauri UI：违反原生 |
| Mac 体验不受跨端 UI 框架拖累 | Avalonia/Uno/Flutter：自绘 UI |
| 学习曲线对「非跨平台专家」最低（多半已在用 TS） | Rust Day-1：FFI/Windows 绑定/招聘税过高 |
| Windows 跟随被限制在 UI 层 | C++ 共享：Dropbox 已证明隐性成本 |
| 可渐进：先 TS 库 + 双端直接链（若嵌入方案成熟）或 sidecar；以后可换 Rust 实现同一 D2 客户端接口 | MAUI：Mac 桌面优先级与成熟度存疑 |

### 主要风险与缓解

| 风险 | 缓解 |
|------|------|
| Node sidecar 打包/升级复杂 | MVP 可先 **仅共享 TS 源码包 + 双端各自跑测试**；sidecar 作二期。或使用 sea/pkg 产出无 Node 依赖二进制。 |
| 双端 UI 仍双倍工时 | 接受「UI 双写」；用 D5 范围控制页面数；parity 允许视觉滞后。 |
| TS 客户端与原生 UI 线程/生命周期难搞 | 明确：UI 主线程只收不可变快照；重活用 actor/队列；参考 Dropbox ChangeSet 心智。 |
| 将来需要重客户端逻辑 | 保留 **port 接口**：`KernelClient` 可有 TS 与 Rust 两实现，UI 不感知。 |
| 误把 WebView 塞进「原生壳」 | D4 ADR 写死：UI toolkit ∈ {SwiftUI/AppKit, WinUI/WPF}；WebView 仅允许用于沙箱预览等局部，不作为主壳。 |

### 备选决策树（一句话）

- 若 **禁止任何 Node 进用户机器** → 方案 2：Swift + C# 双客户端 + 共享 schema/fixtures（TS 仅开发期 oracle）。  
- 若 **出现强一致/重计算客户端核心** → 在 `KernelClient` 接口后换 **Rust + UniFFI（Swift 官方 + C# 第三方）**。  
- 若 **放弃「各自原生」**（需产品改约束）→ 再评估 Avalonia/Compose Desktop；**当前约束下不推荐**。

---

## 调研范围与局限

- 时间点：2026-07-22 web 公开资料；未做本地 POC 编译验证。  
- 未读取 `~/.llm-wiki` 中 D1/D2/D5 全文（任务禁止写入；brief 足够支撑架构层结论）。  
- UniFFI C#、Compose Desktop 生产占有率等量化数据 **未能确认**；以官方定位与代表性案例为准。  
- 「Mac→Win 跟随」无单一业界标准名；§3 为可执行综合范式，而非某公司注册商标级方法论。

## Vendor output (parsed)

```
hopper-runner: idle watchdog disabled (bufferedOutput vendor) — ceiling-only timeout applies (1800000ms)
{
  "text": "I'll research D4 cross-platform native architecture options (Mac→Windows follow) and write findings to the handoff deliverable. Gathering sources and local D1/D2 context first.Synthesizing findings and writing the T-026 deliverable.# T-026 完成\n\nD4 跨平台原生架构调研已落盘：`.hopper/handoffs/T-026-output.md`（约 437 行，中文）。\n\n## Summary\n\n对 Mac 原生优先、Windows 跟随、非 Electron 的共享核心方案做了只读调研（Rust+FFI、C/C++、TS sidecar、KMP、.NET 等），并覆盖共享边界、Mac→Win 工作流、D1/D2 含义与成本敏感排序。**推荐默认：双端原生 UI（SwiftUI + WinUI）+ 共享 TS `kernel-client`（实现 D2/D1 facade）+ 契约金标测试**；Rust/UniFFI 仅作后续重逻辑升级，不作为 Day-1。\n\n## Files touched\n\n- `.hopper/handoffs/T-026-output.md` — 指定交付物\n\n## Verdict\n\n**PASS**\n\n## 对 D4 的核心建议（摘录）\n\n| 项 | 建议 |\n|----|------|\n| 共享核心 | TS `packages/kernel-client`（D2 编解码 + D1 外观）；可升 sidecar |\n| 不共享 | UI、通知、Keychain、安装器等系统集成 |\n| 跟随工作流 | monorepo；契约 → client → Mac UI → Win UI；parity 矩阵允许 UI-only 滞后 |\n| 明确排除 | Electron/Tauri 主 UI、Avalonia/Uno Skia、MAUI 当 Mac 主壳、Day-1 C++/Rust 核心 |\n\n## Next recommendation\n\n用本报告写 **D4 ADR**，并先落 monorepo 骨架：`contracts/d2` → `packages/kernel-client` → `apps/mac` 最小接通 → Windows parity checklist。",
  "stopReason": "EndTurn",
  "sessionId": "019f87a8-a58f-70f0-960c-b88b6e099818",
  "requestId": "f51cf807-a25b-494f-b305-d50623edcf3b",
  "thought": "The user wants me to execute a research task (T-026) about cross-platform native architecture for Mac→Windows follow development. This is a prd-research task that should:\nLet me continue research with more specific sources and browse key documentation pages.I need more specific info on:There's already a T-026-output.md - let me check if it's empty or incomplete, and also look at acceptance criteria from the tasklist and a sample previous research output for format.Important context: D1 is KernelPort (in-process semantic interface, TS expressed), D2 is JSON-RPC style wire between UI and kernel (openclaw/hermes as separate local process). So the app architecture ...Let me also look at a prd-research output for better format matching, and get a couple more specific details.I have enough material to write a comprehensive research report. Let me also quickly check T-003 or T-021 for prd-research format structure.I have enough material to write a comprehensive T-026 research report. Key synthesis for D4 given project constraints:\n**Summary**  \nI researched mainstream native cross-platform architectures that align with the D4 Mac→Windows follow development model, non-Electron constraint, and existing D1/D2 contracts. The analysis shows that a contract-first shared TypeScript kernel client package paired with native UI layers is the most practical fit, balancing maturity, 0-1 lag, and team skill alignment. This approach keeps the kernel as an independent process while enabling rapid Mac delivery with minimal Windows drift.\n\n**Files touched**  \n.I've written the deliverable. Let me update todos and verify the file is complete.The deliverable is complete. As a hopper execution agent I should return the finished deliverable summary. The task asked me to produce the research and land it at T-026-output.md - done.\n",
  "usage": {
    "input_tokens": 92485,
    "cache_read_input_tokens": 404864,
    "output_tokens": 12014,
    "reasoning_tokens": 2724,
    "total_tokens": 509363
  },
  "num_turns": 9,
  "total_cost_usd": 0.4585132,
  "total_cost_usd_ticks": 4585132000,
  "modelUsage": {
    "grok-4.5-build": {
      "inputTokens": 92485,
      "outputTokens": 12014,
      "cacheReadInputTokens": 404864,
      "modelCalls": 9,
      "costUSD": 0.4585132
    }
  }
}
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 254459
- end_time: 2026-07-22T02:34:14.779Z
- log: see `T-026-output.log` for raw output
