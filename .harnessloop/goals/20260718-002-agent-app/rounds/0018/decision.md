# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-110-codex-output.md
- Reviewer: codex via hopper T-110（单路，按 scope-lock）
- Review verdict: **REWORK**（三条，主会话全部复核成立后返工）
- Confirmation review: **PASS_WITH_NOTE** — grok via hopper T-111（返工后补派，2026-08-13 回）。Q1 result-before-call 原地补全 **PASS**（两方向都只产生 1 条 `ConversationItem`）；Q2 固定 alpha 残留 **PASS**（**生效代码 0 处 `Color.*.opacity`**，全部背景为 `.regularMaterial` 或 `.fill.tertiary`）；Q3 角色区分的无障碍 **PASS**（对齐 + 文案标签 + 小图标，不单靠颜色）；Q4 「无障碍由构造保证」的诚实性 **NOTE** —— 判定「对本轮缺陷（固定 alpha → material）由构造消除成立；全 UI 像素级实拍仍未验，**记债不返工**」
- Review digest: 5840dfc1fd400ff41db26fb51a6611898bd351b237aa0470748994938ebf9685
- Acceptance evals: none — 本轮为 UI/渲染层改动，无 runtime eval 台账
- Acceptance evals detail: n/a
- Active goal: 20260718-002-agent-app
- Active round: 0018
- Decision maker: main session（claude-opus-5[1m]）；用户 2026-08-13 睡前授权自主推进
- Timestamp: 2026-08-13

## Reason

**两件事都达成，且硬判据全部由主会话独立复跑。**

**其一：让 agent 看起来像 agent。** `SessionStore.swift` 此前一行把 `toolCall` /
`toolResult` / `thinking` / `capabilityChanged` / `operationCompleted` 五类事件全部
`break` 丢弃——映射层早已产出全部 11 种事件，**是 UI 这层扔的**。现在工具调用渲染成
独立行、结果按 `toolCallID` 配对回其调用、思考默认折叠。

**其二：视觉升级到 Liquid Glass。** 依据是 T-107 的联网调研而非印象：设计语言是
**Liquid Glass**（WWDC25 随 macOS 26 Tahoe 发布），**当前最新的 macOS 27「Golden Gate」
没有改名**，是同一套的精修版。

## 独立复核

| 判据 | 结果 |
|---|---|
| `swift build --package-path app` | **exit 0**，警告数 24（与基线一致，零新增） |
| 帧回放 | **83/83 PASS**（基线 74 → 82 → 83） |
| **我自己的破坏性反证** | 第一次注入猜错字段名**编译失败**——**反证无效，不能拿实现方结论顶替**；改成让 `firstIndex` 永远落空后：注入命中 1、编译通过、**83 → 82（1 红，正是 P1 那条）**、还原 83/83、零残留 |
| `glassEffect` 实调用（`app/` 范围） | **0**（仅注释里出现，解释为何不用） |
| 自制噪点/颗粒 | **0** |
| `Package.swift` / `Info.plist` | **一字未改**，保持 macOS 14 兼容 |
| 禁改路径 | `app/generated`、`app/contracts`、`app/server`、`app/parity`、`.github` diff 全为 0 |
| 实拍 | 深色 / 浅色各一张，哈希不同 |

## Main-Session Decision On Scope Boundary

1. **用户提的「动态颗粒砂」如实不做** —— 调研查无任何官方 API 或 HIG 概念，
   属社区实践（Flutter 等叠 noise 防色带），且与 Reduce Transparency、性能、可读性
   冲突。**不找近似物糊弄，直接说查不到依据。**
2. **部署目标保持 macOS 14** —— Liquid Glass API 需 macOS 26+，全部走
   `if #available(macOS 26, *)` 分支、旧系统退回 standard materials。
   **可逆，且符合官方渐进采用建议。**
3. **返工时选了「严格 material」而非「层级填充色」** —— 后者只是缓解，前者
   **从构造上消除**固定 alpha 不随对比度提升的问题。发言者改由对齐、角色标签、
   小尺寸前景图标区分。
4. **动过用户的系统外观设置并已还原** —— 拍浅色时切过 dark mode，拍完还原为深色
   （用户原设置），已核实。

## Human Decision Required

- **无阻断项。** 但下方两条证据缺口需要用户授权才能补。

## Open Questions Resolved

- **「磨砂 / 动态颗粒砂」的官方对应物是什么** → 磨砂对应 **Liquid Glass（功能层）
  / standard materials（内容层）**；**动态颗粒砂查无官方对应物**。
- **agent 对话 app 的官方分层** → 侧栏与工具栏是 Liquid Glass 功能层，
  **消息流是内容层，永远不给气泡加 `glassEffect`**；审批卡用 standard material，
  颜色只落在按钮背景。
- **固定 alpha 的颜色能不能算无障碍达标** → **不能**。它虽是动态系统色，
  但**固定 alpha 不随 Increase Contrast 提升对比度**。系统 material 会。

## Open Questions Remaining（两条证据缺口，需用户授权）

1. **Reduce Transparency / Increase Contrast 无实拍证据。**
   `defaults write com.apple.universalaccess` 被系统拒绝（受保护域），
   主会话不去操作用户的系统设置界面。**本轮该项是「由构造保证」而非「实拍确认」**——
   返工后所有内容层表面要么是系统 material、要么是仅作前景 tint 的动态系统色，
   已无固定 alpha 背景。**如实标注，不粉饰为已验证。**
2. **工具行 / 审批卡的内容态截图缺失。** 要拍到它们需要一次真实 LLM 往返，
   而**触发第三方计费的写入不在本项目预授权范围内**（control-contract 明写）。
   当前该行为由帧回放的 9 条新测试保证（含 result-before-call 的顺序回补），
   **但没有视觉实拍**。

## 其它遗留

- MVP 盘点查出的其余缺口未动：**停止按钮**（`interrupt()` 是桩）、
  **token 默认是占位符且无 UI 可填**（对真内核必然鉴权失败）、**无 app 图标**。
- **CI 从不构建 app、也从不跑那 83 个帧回放测试** —— 已知缺口，本轮未改
  （scope-lock 明列不碰 `.github/`）。
