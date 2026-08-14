# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .harnessloop/goals/20260718-002-agent-app/rounds/0021/evidence/T-114-codex-review-recovered-from-progress-log.md
- Review artifact note: **产物未落在 brief 指定的 `.hopper/handoffs/T-114-codex-output.md`**（沙箱只读），已按 codex 三项强制核对回收，见下方专节
- Reviewer: codex（gpt-5.6-sol）via hopper T-114（单路，按 scope-lock）
- Review verdict: **REWORK**（4 FAIL / 4 PASS / 1 NOT-VERIFIED；主会话复核后全部返工或如实登记）
- Review digest: a35fa244e888eb1870bfb0024289f6eaf043661068874df00a654362afb842be
- Acceptance evals: none — 本轮为视觉/交互层改动，无 runtime eval 台账
- Acceptance evals detail: n/a
- Active goal: 20260718-002-agent-app
- Active round: 0021
- Decision maker: main session（claude-opus-5[1m]）；用户 2026-08-13/14 多次裁定（图标方向、菜单栏项、产品身份 B、水印位置）
- Timestamp: 2026-08-14

## Reason

**给 app 一套真正的视觉身份**：macOS 26 液态玻璃深化（仅 chrome）、透明度可自定义、
配色语义分离、从零设计并落地图标三处、熊头水印、按钮 Mac 化。帧回放 **124 → 163**。

## 用户四次裁定

| 裁定 | 内容 |
|---|---|
| 图标方向 | **Dock 用 A1 圆熊、菜单栏用 B1 剪影熊**（不四选一，两者共享同一套头身比例） |
| 图标尺寸 | 撑满画框，**边缘残缺当作有意的设计** |
| 菜单栏项 | 本轮加（v2 扩围） |
| 产品身份 | **B：常驻菜单栏，关窗不退出**（v3 扩围） |
| 水印位置 | 从侧栏移到右侧面板，顺时针 30°、右下角、约 1/4 画面 |

## 评审判 REWORK 四条，两条是阻断

| # | 发现 | 处置 |
|---|---|---|
| **1** | **无障碍变更订阅错了通知中心**（`NotificationCenter.default` 而非 `NSWorkspace.shared.notificationCenter`）——运行期收不到变更 | 已修（订阅与**注销**两处） |
| **2** | **macOS 26 玻璃分支丢弃滑块强度**——在本机这个系统上透明度设置**静默无效** | 已修，强度→透明度的算法抽进 `AgentShellCore` 获得测试覆盖 |
| 6 | `⌘↩` 是行为添加但**未记 scope-lock 扩围** | **判得对**，已补记 v4（如实标注为补记非事前授权） |
| 7 | `MenuBarExtra` 未用 `isInserted`；防重复窗口依赖**未文档化**的 `NSWindow.identifier` 前缀 | 已改为 `MenuBarExtra(isInserted:)` + `Window` scene |

**PASS 四条**：内容层无 `glassEffect`、语义色与强调色分离、部署目标与 pre-26 回退完整、图标静态打包（`codesign --verify --deep --strict` 通过）。

## 评审戳破了主会话一份「已证明」的证据

主会话做过一次定量实拍：滑块拉到最大不动，用户开启 Reduce Transparency 后
侧栏平均色由 **R=45.3 G=43.3 B=40.8**（三通道不等 = 半透明材质透出暖色壁纸）
变为 **R=G=B=25.0**（零方差中性灰 = 不透明），据此宣称红线成立。

**评审指出订阅错了中心之后，这份证据的归因就站不住了**——SwiftUI 的 `Material`
**本身就自动尊重 Reduce Transparency**，所以那个变化**可能完全是系统干的，与我们的解析器无关**。
**两个原因被混淆，定量测量分不开它们。**

返工方把两个命题拆开并给出诚实结论：
- **(A) 解析器判定正确** —— 已由单测的矛盾矩阵证明，与像素无关。
- **(B) 截图能否把结果归因到我们的代码** —— **未解决**。它设计了更具诊断性的实验
  （保持 Reduce Transparency 开启、只变滑块，看像素是否不变），**但因屏幕锁定无法执行，
  且明确拒绝拿一次锁屏截图充数**。

## 主会话本轮自己犯的错，全部记下

1. **把 `System Events` 返回 0 读成「没有窗口」**，据此报了一个「严重回归」并派了修复。
   对照实验（事后补做）：同一时刻它对 **Finder 也报 0**，而 `CGWindowListCopyWindowInfo`
   显示其它 app 各有窗口。**该接口在受限屏幕状态下对所有 app 都返回 0。**
2. **把 grep 空结果读成「消息没发出去」**，还据此向用户道歉说可能误注入到别人的会话。
   实际两条消息都发出去了、都跑通了——**grep 模式与日志格式不匹配**。
3. **自写探针也报了同一个错误的零**——它按 owner name `"AgentShell"` 过滤，
   而进程实际叫 `Agent Shell (SG-10 L1)`。**两个不同工具、两种不同原因、同一个错误结论。**

**这三条都是「空结果不等于不存在」**，是本项目该族的第 4/5/6 次，**且都发生在主会话
把这条规律写进 CLAUDE.md 之后**。真正的教训不是「记住这条」，而是：
**凡「没找到 ⇒ 没发生」的推断，必须先用一个已知存在的正样本验证搜索本身有效**——
主会话对 `System Events` 做过这个对照（拿 Finder 验），对 grep 和自写探针都没做。

## codex 三项强制核对第一次真正拦下东西

**产物未落在 brief 指定的 `.hopper/handoffs/T-114-codex-output.md`** —— 沙箱只读，
codex 写不了文件，评审正文落进了进度日志。**若只看任务 exit 0 会以为产物已就位。**
已按纪律发现并回收，副本存于 `evidence/`。

## 独立复核（全部主会话自己跑）

| 判据 | 结果 |
|---|---|
| 构建 / 帧回放 | exit 0 ／ **163/163**（124 → 134 → 146 → 149 → 158 → 163） |
| 红线：内容层无玻璃 | `command grep` 全仓 `glassEffect` **只有一处真实调用**（输入区 chrome），其余全是注释 |
| 红线：无障碍压制 | 解析器把判断放在函数**最前面提前返回**；**主会话反证**拆掉 `increaseContrast` 那一半 → 134 掉到 133 |
| FAIL-1 修复 | 订阅与注销均指向 `NSWorkspace.shared.notificationCenter` |
| FAIL-2 修复 | `case .translucent(let intensity)` 已绑定 |
| 图标 | `.icns` **实测 10 文件完整**（`iconutil` 反解），bundle 三资源齐，`LSMinimumSystemVersion` 仍 14.0 |
| 菜单栏 | **真菜单栏实拍**熊头；菜单项实拍带省略号、宽度约 365pt |
| 水印 | **真内容实拍**（会话 5 有推理行/工具行/assistant 回复）+ 最终 `Window` scene 实拍 |
| 证据落盘 | `evidence/verification/` **12 份**（含探针源码与输出、两条反证红绿原始记录、可区分性分析） |

## Open Questions Remaining

1. **Increase Contrast 实拍未取得** —— 受保护域，app 只读，需用户手动切换；用户 2026-08-14 明确选择暂缓。
2. **审批「拒绝」语义色实拍未取得**。
3. **菜单栏图标反色成白色未实拍** —— 本机壁纸为浅色，菜单栏取壁纸有效外观，切换系统深浅无效。
4. **(B) 归因可区分性未解决** —— 见上，返工方明确标注未解决而非给一个混淆的答案。
5. **macOS 14/15 回退分支无设备可实跑** —— 代码层清单完整，实跑未验。
