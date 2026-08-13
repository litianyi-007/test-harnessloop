# rounds/0019 实拍证据说明

**每张图拍到了什么、没拍到什么，如实标注。**

| 文件 | 内容 | 状态 |
|---|---|---|
| `01-placeholder-hint.png` | 主窗口，占位符 token 提示 | 有效 |
| `02-settings.png` | 设置面板（**修宽度前**，左侧标签被裁切） | 有效——它是那个视觉缺陷的证据 |
| `03-settings-fixed.png` | 设置面板（修宽度后，无裁切） | 有效 |
| `10-connected.png` | 连上隔离内核后的主窗口 | 有效 |
| `11-session-created.png` | 新建会话后 | 有效 |
| `12-composer-typed.png` | 输入框已键入待发 | 有效 |
| **`13-approval-card.png`** | **审批卡实拍**：`exec @ gateway`、命令、reqId、倒计时、两个按钮（`ask=always` 下内核只给 allow-once/deny） | **本轮最有说服力的一张** |
| **`14-tool-result.png`** | **命令真执行**：assistant 回出 `TOOLROW_DEMO_OK`；气泡用 material + 角色图标 | **有效，且它暴露了思考流碎片化缺陷** |
| `15-scrolled-top.png` | 与 14 同视图（自动锚底，滚动未生效） | 冗余，保留以示如实 |
| **`16-recapture-FAILED-empty-session.png`** | **空会话**——修复后的复验实拍**失败** | **无效证据。原名 `16-thinking-merged.png`，文件名在说谎，已改名** |

## 未能取得的证据（如实登记，不以测试冒充）

1. **思考流合并后的实拍** —— 修复已由单元测试保证（逐字重放 13/14 号图里抓到的碎片序列，
   断言合并成一条），但**修复后的界面没有拍到**：连试五种方法都无法把键入送进 SwiftUI
   输入框（第一次实拍时同样的路径是成功的，原因未查明）。**这是自动化问题，不是产品问题**，
   但不拿测试证据冒充实拍证据。
2. **工具调用 / 工具结果行的实拍** —— 本次 exec **没有产生 `tool_call` 事件**
   （隔离内核日志里 `tool_call` 出现 0 次，openclaw 的 exec 走审批路径）。
   该渲染仍只有单元测试证据。
3. **Reduce Transparency / Increase Contrast 的实拍** —— `defaults write
   com.apple.universalaccess` 被系统拒绝（受保护域），未去操作用户的系统设置界面。

## 现场纪律

隔离实例两次起停均已收干净（端口释放、目录删除），**用户常驻的 openclaw gateway
（pid 29071）全程未受影响**，每次收尾都单独核对过。

---

## 提交前脱敏留痕（本轮唯一一处改动过的原始日志）

pre-commit 的 secret 门（L2 形态兜底）拦下了一个 `sk-` 开头的串：
`sk-real-looking-…（原串，已改掉）`。**它是本轮新增测试里的假 fixture**——
`isTokenPlaceholder` 是 `token == Self.defaultToken` 的**精确相等**判定
（`KernelShellSettingsStorage.swift:284`），该 fixture 只是「任一非默认值」的代表，
不是任何真实凭证。

处置分两步，都留痕：

1. **测试源码里改名**为 `sk-EXAMPLE-not-a-real-token-abc123`。
   门的豁免词是对**提取出的匹配串本身**生效（`grep -Eo` 之后才过滤），
   所以标记必须长在值里、而不是写在旁边的注释里。改名后重跑：构建 exit 0、
   帧回放仍 **102/102**，该条断言语义未变（精确相等判定对任何非默认值结果相同）。
2. **`.hopper/handoffs/T-112-codex-output-raw.txt` 与 `T-112-codex-output.log`
   各替换 4 处**为 `sk-REDACTED-fake-test-fixture-abc123`。这两份是 codex 评审的
   verbose 转录；**被替换的串本身零证据价值**（一个假 token 字面量），
   而评审结论所引的 `T-112-codex-output.md` 未受影响、逐字节原样。

**如实标注**：这是本轮唯一一次改动 vendor 原始日志内容。
