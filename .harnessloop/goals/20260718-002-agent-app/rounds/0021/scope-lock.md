# Scope Lock — goal 002 / rounds/0021

**开轮时间**：2026-08-13，**动手之前**写就。用户裁定：二十轮汇报之后的第一轮做 UI 深度重构。

## Round Objective

**给 app 一个真正的视觉身份**：macOS 26 液态玻璃深化、透明度可自定义、配色优化，
并**从零设计一套图标**落地到 app 内 / Dock / 菜单栏三处。

## 动手前必须先定死的四个取舍

### 1. 液态玻璃用在哪 → **只用于 chrome，内容层永远不用**

这不是本轮新定的，是 HIG 的分层规则，且**本仓既有代码已经在守它**
（`SessionDetailView.swift` 的注释白纸黑字："消息流本身是内容层，永远不对气泡用 glassEffect"）。

**深化的含义是把 chrome 那一层做透**——窗口背景、工具栏、侧栏、输入区容器——
**不是把玻璃铺到消息气泡上**。铺到内容层会让长文本可读性下降，而且是 HIG 明确反对的。

### 2. **可自定义透明度 vs 系统无障碍 → 系统永远赢**（本轮红线）

用户要「透明度允许自定义」。**但 macOS 有 Reduce Transparency 这个无障碍开关**，
它存在的理由是有人会因为半透明背景而读不清文字。

**因此优先级只能是**：系统 Reduce Transparency 开启时，**无论用户滑块设到哪里，
一律降级为不透明材质**。用户滑块只在系统允许透明的前提下生效。

**反过来做（让用户滑块压过系统设置）等于出厂一个专门用来击穿无障碍功能的设置项**——
本轮不接受。同理 Increase Contrast 开启时也必须让路。

### 3. 图标 → **先出方案让用户挑，再落地**

图标是**用户决策**不是实现决策。本轮先用矢量出多版：
- 共同基底：**熊头**
- 方向 A：**圆润几何**（参考 DeepSeek 鲸鱼那种大块面、少细节、高辨识）
- 方向 B：**极简剪影**（参考 X 鸽子那种单色负空间）

**用户挑定之后才落地。** 三处的技术要求各不相同，不能用同一张图糊弄：

| 落点 | 要求 |
|---|---|
| Dock / Finder | `.icns`，多分辨率（16→1024），macOS 26 有新的图标外观规范 |
| **菜单栏** | **必须是 template image**（单色 + alpha），由系统自动跟随明暗反色；**给彩色图会在深色菜单栏里糊掉** |
| app 内 | 与 SF Symbols 共存，需保证同一视觉重量 |

### 4. 配色 → **语义色与强调色分开**

成功/警告/危险是**语义色**，不能被主题强调色吃掉——审批卡的「拒绝」在任何配色下
都必须一眼是危险色。本轮换配色时，**语义色单独定义、单独验**。

## 本轮不做

- **不改部署目标**（`Package.swift` 是 `.macOS(.v14)`）——**pre-26 回退分支必须全部保留**，
  本机是 26.6 能验 26 分支，**14/15 分支本轮无设备可实跑，如实登记为未验**。
- 不碰 `interrupt`/`stop`/审批等行为层逻辑——本轮是纯视觉层。
- 不碰三个插件 submodule、`app/generated/`、`app/contracts/`、`kernels/`。
- 不做 parity 金标、不做第二内核、不做 Windows（后续轮）。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/apps/AgentShell/Sources/AgentShell/LiquidGlassSupport.swift` | 改 | 玻璃能力深化 + 透明度接入 |
| `app/apps/AgentShell/Sources/AgentShell/*.swift` | 改 | 视图层配色与材质；**不改行为** |
| `app/apps/AgentShell/Sources/AgentShellCore/KernelShellSettingsStorage.swift` | 改 | 新增外观偏好持久化（与既有 token/endpoint 同机制） |
| `app/apps/AgentShell/Sources/AgentShellCore/` | 改 | 仅为外观偏好所需 |
| `app/apps/AgentShell/Resources/` | 写 | **新增**：图标源文件与生成产物 |
| `app/apps/AgentShell/Info.plist` | 改 | **仅加图标键**；**不改最低版本** |
| `app/apps/AgentShell/build-app-bundle.sh` | 改 | 打包图标资源 |
| `app/kernel-client/swift/frame-replay-tests/` | 写 | 外观偏好的回归测试 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0021/` | 写 | 本轮产物 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `Package.swift` 的 `platforms`、`Info.plist` 的最低版本
- `app/generated/`、`app/contracts/`、`app/server/`、`app/parity/`、`.github/`、`kernels/`
- `interrupt()`/`stop()`/`respondApproval()` 及审批 FSM 的**任何行为改动**
- **把 `glassEffect` 用到消息气泡等内容层元素上**

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 构建 | `swift build --package-path app` exit 0 | 直接捕获退出码 |
| 回归 | 帧回放 **≥124/124** | 测试输出 |
| **Reduce Transparency（红线）** | 系统开启时**滑块任意位置**均降级为不透明 | 测试 + **实拍** |
| **Increase Contrast（红线）** | 系统开启时让路 | 测试 + 实拍 |
| 内容层无玻璃 | 全仓搜确认 `glassEffect` 不出现在气泡/工具行/思考行 | 代码引用清单 |
| 语义色未被吃掉 | 换配色后「拒绝」仍是危险色 | 实拍 |
| pre-26 回退 | 每处 `#available(macOS 26)` 都有 else 分支 | 代码清单（**14/15 实跑无设备，如实登记未验**） |
| 图标三处 | Dock / 菜单栏 / app 内各一张实拍；菜单栏在**深浅两种**下都正确反色 | 实拍 |
| **破坏性反证** | 每条新断言先见红，**且打印注入命中数**；**先看 build exit 再看测试数** | 注入命中计数 + 红绿两次 |

## 红线

- **系统无障碍设置永远压过用户透明度滑块。** 违反即本轮不接受——
  那是出厂一个专门击穿无障碍功能的设置项。
- **不得把玻璃用到内容层。**
- **不得改部署目标、不得删 pre-26 回退分支。**
- **不得改任何行为逻辑**——本轮是纯视觉层，行为层的 124 条测试是护栏。
- **破坏性反证必须先看 `build exit`**——rounds/0020 有一次注入编译失败，
  测试数是旧二进制的读数，差点当成有效反证。

## 异构评审

改动完成后派只读评审，重点问：①Reduce Transparency / Increase Contrast 是否**真的**
压过用户设置（自己构造矛盾输入验证，不要只看代码意图）②有没有玻璃漏到内容层
③语义色是否仍与强调色分离 ④pre-26 分支是否完整 ⑤有没有新的静默失败路径。

## 分两段走

**第一段（本文件写就即开始）**：出图标方案 + 液态玻璃/透明度实现。
**图标方案出来后停下来交用户挑**，挑定再落地三处。

---

## Scope-Lock 修订 v1 → v2（2026-08-14，用户裁定）

**扩围：新增一个最小菜单栏项（`MenuBarExtra`）。**

**这是行为添加，不是视觉改动**——本文件「本轮不做」原写着「本轮是纯视觉层」，
所以必须显式扩围留痕，不能借「图标属于视觉」把它裹进去。

**为什么必须扩**：图标落地后发现一个**产物与宿主不匹配**的缺口——
`MenuBarIconTemplate.png`/`@2x` 已生成并打进 bundle，但
**`NSStatusBar`/`MenuBarExtra`/`statusItem` 全仓零命中**，该资源的所有引用都在
生成器与打包脚本里，**没有一行 app 代码使用它**。

**也就是说：我们为一个不存在的菜单栏做了一枚图标，资源随包发布但是死重。**
这正是本项目反复在抓的「看起来做完了、其实没生效」——只不过这次是产物侧而非守卫侧。

用户 2026-08-14 裁定：**本轮加**，理由是「系统栏图标」本就是本轮任务书的原始要求之一，
产物备好而宿主不建等于没交付。

**扩围边界（严格最小）**：
- 只加一个 `MenuBarExtra`：显示 template 图标 + 连接状态 + 当前会话名。
- **不加任何新的内核操作入口**——不在菜单栏里发消息、不停止、不审批。
  那些是行为面的实质扩张，超出「让图标有个宿主」这个理由所能支撑的范围。
- 既有窗口内的一切行为**一字不改**，124→134 的测试仍是护栏。

**新增验证项**：菜单栏图标必须在**深色与浅色菜单栏下各实拍一张**，
证明 template image 真的被系统自动反色（这是当初选 B1 而非 A1 做菜单栏的全部理由，
不实拍就等于没验）。

---

## Scope-Lock 修订 v2 → v3（2026-08-14，用户裁定「B」）

**产品身份变更：app 从「单窗口、关窗即退出」改为「常驻菜单栏、关窗不退出」。**
`applicationShouldTerminateAfterLastWindowClosed` 由 `true` 改为 `false`。

### 这条修订必须连同它的由来一起记，因为决策前提里有一个是错的

主会话报告过一个「主窗口关闭后再也回不来」的严重回归，并据此派了修复。
**那个报告的证据链是无效的**：

- 主会话用 `System Events` 枚举窗口得到 0，据此判定 app 无窗口。
- **对照实验（事后补做）**：当前屏幕状态下 `System Events` 对 **Finder 同样报 0**，
  而不受锁屏影响的 `CGWindowListCopyWindowInfo` 显示 Warp/Code/Chrome/System Information
  **各有 1 个在屏窗口**。**该接口在此状态下对所有 app 都返回 0。**
- 实施方在**未改动的代码**上走 `File > Close All` 真实路径，**进程干净退出**——
  原不变式成立。

**这是「空结果不等于不存在」的第四次，且是主会话自己踩的**——就在把这条规律写进
CLAUDE.md 之后。前三次是 `grep` 跳过文件，这次是 `System Events` 在受限屏幕状态下
枚举不到窗口。**工具返回 0，被读成了「不存在」。**

### 真实存在、与屏幕状态无关的两条缺陷（源码级坐实，各带反证）

1. `MenuBarWindowFocus.focusMainWindow()` 的 `guard … else { return }` 在无窗口时
   **静默什么都不做**，用户点了没有任何反馈。
2. 旧的「任何可见窗口」过滤会**把 Settings 面板误当成主窗口**——恢复旧逻辑后
   反证跑出 **4 条红**。

### 用户裁定 B 的理由（独立于上述错误前提，成立）

**菜单栏项唯一的动作是「显示主窗口」；若关窗即退出，那个动作永远没有意义**——
进程在用户想点它之前就已经没了。要么这个动作有意义（B），要么它不该存在（A）。
用户 2026-08-14 裁定 **B**。

### 因此本轮的产品定位正式变更

原注释写着不想「变成一个没有窗口、悬在 Dock 里的空壳」——**那句话现在作废**，
本 app 的定位是**常驻菜单栏的 agent 客户端**，无窗口是合法状态，
`显示主窗口` 用 `openWindow(id:)` 真正创建窗口（已实证不产生重复窗口）。

---

## Scope-Lock 修订 v3 → v4（2026-08-14，评审 T-114 FAIL-6 指出后补记）

**扩围：`⌘↩` 发送快捷键（`SessionDetailView.swift:277`）。**

**这条是补记，不是事前授权，如实标注。** 本文件「本轮不做」原写着「不改任何行为逻辑
——本轮是纯视觉层」，v2（菜单栏项）与 v3（窗口生命周期）两次扩围都**没有覆盖键盘快捷键**。
主会话在 UI 打磨的任务书里授权了它，**却没有回来改 scope-lock**，评审 T-114 第 6 条据此
判 FAIL——**判得对**。

**为什么它仍应保留**：这不是新增能力，是修一个**已被实拍坐实的缺陷**——
`TextField(..., axis: .vertical)` 让 Return 变成换行，`.onSubmit` 结构性永不触发，
rounds/0020 实拍时按回车无反应、只能点按钮。**发送这个能力本来就该有键盘路径，
之前是坏的。** 但「它该保留」与「它当时没被授权」是两件事，后者如实记在这里。

## 关于 T-114 产物路径（codex 三项强制核对第 (b) 条）

**产物未落在 brief 指定的 `.hopper/handoffs/T-114-codex-output.md`** —— 沙箱只读，
codex 写不了文件，评审正文落进了 `T-114-codex-progress.log`。
已按 CLAUDE.md 的 codex 核对纪律发现并回收，副本存于本轮
`evidence/T-114-codex-review-recovered-from-progress-log.md`。
**这是该纪律第一次真正拦下东西**——若只看「任务 exit 0」会以为评审产物已就位。
