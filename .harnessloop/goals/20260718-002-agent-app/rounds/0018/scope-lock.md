# Scope Lock — goal 002 / rounds/0018

**开轮时间**：2026-08-13，**动手之前**写就。用户 2026-08-13 睡前裁定：
「回到正轨，确认 demo 是否将达到可试用（MVP）阶段，并优化 UI 视觉、加入最新 macOS 风格」。

## Round Objective

**两件事同轮做，因为它们改的是同一批 view 文件：**

1. **让 agent 看起来像 agent** —— 渲染工具调用 / 工具结果 / 思考过程。
2. **视觉升级到当前 macOS 设计语言（Liquid Glass）**。

## 为什么第 1 件排在视觉前面

MVP 盘点实测：`SessionStore.swift:432-433` 一行把五类事件全丢了——

```swift
case .thinking, .toolCall, .toolResult, .capabilityChanged, .operationCompleted:
    break
```

映射层 `EventMapping.swift` **已经产出全部 11 种 D2 事件**，是 UI 这层扔的。
于是演示时看到的只是「你一句、它一句」，**中间调了什么工具、读了什么文件、
执行了什么命令一概不可见**——除非恰好触发审批弹卡。

**对一个 agent 产品，这是「看不出它是 agent」的差距，比任何视觉问题都致命。**
视觉做得再漂亮，演示时也只是个聊天框。

## 视觉方向的依据（T-107 联网调研，非凭印象）

- 设计语言是 **Liquid Glass**，WWDC25 发布，随 macOS 26 Tahoe；
  **当前最新是 macOS 27「Golden Gate」**（WWDC26 预览，今秋发布）——**没有改名**，
  是同一套的精修：uniform toolbars、edge-to-edge sidebars、更均匀折射、
  用户可调 ultraclear → fully tinted。
- **用户提到的「动态颗粒砂」查无官方对应物**。grok 核实：那是社区实践
  （Flutter 等叠 noise 防色带），**不是苹果推荐**，且与 Reduce Transparency、
  性能、可读性冲突。**本轮不做自制 grain。**
- 「磨砂」的官方对应是 **Liquid Glass（功能层）/ standard materials（内容层）**。

### 官方分层（HIG，直接决定本轮怎么改）

| 区域 | 材质层 | 依据 |
|---|---|---|
| 会话侧栏、工具栏 | **Liquid Glass 功能层** | HIG Materials |
| 消息流正文 | **内容层** —— **不要给每条气泡加 `glassEffect`** | HIG Materials「Don't use LG in the content layer」 |
| 审批卡 | 内容层卡片用 **standard material**，着色只落在按钮背景 | HIG Color「Apply color sparingly」 |

## 本轮不做

- **不做自制颗粒/噪点纹理** —— 查无官方依据，且与无障碍设置冲突。
- **不改 D1 七法签名、不改 `EventMapping.swift` 的映射语义** —— 数据已经够用，
  本轮只在 UI 层消费。
- **不实现 `interrupt()`（停止按钮）** —— 它是内核客户端的桩，属独立议题。
- **不做登录/license/租户/Console/newapi 计费** —— 均为 L3 及以后。
- **不碰三个插件 submodule。**
- **不改 `.github/workflows/ci.yml`** —— CI 不构建 app 是已知缺口，另议。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/apps/AgentShell/Sources/AgentShell/` | 改 | 四个 view 文件：工具调用渲染 + 视觉 |
| `app/apps/AgentShell/Sources/AgentShellCore/` | 改 | 仅为渲染工具调用所需的模型/状态扩展 |
| `app/apps/AgentShell/Resources/` | 写 | 如需 app 图标或资源目录 |
| `app/kernel-client/swift/frame-replay-tests/` | 写 | 新行为的回归测试 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0018/` | 写 | 本轮全部产物 |
| `.harnessloop/state/current.md` | 改 | 轮次指针与收盘态 |
| `docs/validation-log.md` | 改 | 收盘条目 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `app/kernel-client/swift/` 下除 `frame-replay-tests/` 外的任何文件
- `app/generated/`、`app/contracts/`（codegen 产物与契约）
- `app/server/`、`app/parity/`、`.github/`
- 三个插件 submodule
- **不得为了视觉效果牺牲可读性** —— 见红线

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 构建 | `swift build --package-path app` exit 0 | 直接捕获退出码 |
| 回归 | 帧回放 **≥74/74**（当前基线 74） | 测试输出 |
| **工具调用可见** | 构造含 `toolCall`/`toolResult`/`thinking` 的事件序列，UI 产出对应元素 | 新增测试 + 截图 |
| **不误伤既有** | 现有消息分组规则不变（`SessionStoreGroupingTests` 仍绿） | 测试输出 |
| **深浅色** | Light / Dark 两种外观下均可读 | 截图 |
| **无障碍** | **Increase Contrast** 与 **Reduce Transparency** 打开后仍可读、不塌陷 | 截图 |
| 视觉实拍 | 至少 3 张：默认、Dark、Reduce Transparency | 截图路径 |

## 红线

- **可读性优先于观感。** HIG 明写内容层不该用 Liquid Glass；消息气泡若因玻璃效果
  导致文字对比度下降，**一律回退到实心或 standard material**。
- **必须适配 Reduce Transparency / Increase Contrast** —— 官方反模式里点名了
  「忽略无障碍与用户 LG 偏好」。**不测就等于没做。**
- **不得堆叠 glass on glass**、不得给控件加自定义背景盖住系统效果。

## 异构评审

改动完成后派**单路**只读评审，重点问：①有没有把 Liquid Glass 用到内容层
②工具调用渲染是否真消费了那五类事件而非只做样子 ③无障碍适配是否只是声称。

## 主会话的开轮判断

- **两件事同轮**：它们改同一批文件，分两轮会重复劳动并制造冲突。
- **工具渲染优先于视觉**：视觉再好，看不出是 agent 就不是这个产品。
- **视觉严格按调研的官方分层做**，用户提到但查无依据的效果（动态颗粒砂）
  **如实不做并说明**，而不是找个近似物糊弄过去。
