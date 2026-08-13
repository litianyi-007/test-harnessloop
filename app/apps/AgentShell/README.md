# AgentShell —— SG-10 L1 Mac UI 壳

原生 macOS SwiftUI 壳，消费 `app/kernel-client/swift/`（`KernelClient` 协议 +
`OpenclawGatewayKernelClient` 实现）。L1 范围：窗口 + 会话列表 + 新建会话 + 消息流渲染。**不含**
流式渲染精细化、stop 按钮、审批五态 UI、成本/用量面板、能力开关——这些归 L2/L3。

## 构建（纯 SwiftPM，不建 `.xcodeproj`）

从仓库根目录：

```bash
swift build --package-path app --product AgentShell
```

`swift build --package-path app`（不带 `--product`）会连同 `kernel-client-cli`/
`frame-replay-tests` 一起构建全部 5 个 target。

## 组装并打开 `.app`

```bash
app/apps/AgentShell/build-app-bundle.sh
open app/.build/AgentShell.app
```

`build-app-bundle.sh` 自己会先跑一遍 `swift build`，再把裸二进制拼成标准 `.app` bundle
（`Contents/MacOS/AgentShell` + `Contents/Info.plist`）并做 ad-hoc 签名——SwiftPM 本身不产出
bundle，SwiftUI app 要正常拿到窗口焦点、被当成常规前台 App（而不是后台命令行进程）需要这一层，
细节见脚本内注释。可选环境变量：

- `CONFIGURATION=release` —— release 构建（默认 debug）
- `AGENT_SHELL_APP_ROOT=<自定义输出路径>` —— 默认 `app/.build/AgentShell.app`

## 连接的 openclaw 内核实例

壳通过环境变量指定要连接的 openclaw gateway，不写死、不带真实凭证：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `AGENT_SHELL_KERNEL_URL` | `ws://127.0.0.1:18889` | 与 `app/kernel-client/swift/cli/` 的 `SG4_KERNEL_URL` 默认值一致——本项目隔离 openclaw 内核实例的约定端口，不是用户全局 18789 实例 |
| `AGENT_SHELL_KERNEL_TOKEN` | `agentshell-local-placeholder-token` | 本地占位符，不是真凭证；对着真实隔离实例跑时用该实例自己生成的 token 覆盖 |

直接跑二进制（继承当前 shell 环境，最直接）：

```bash
AGENT_SHELL_KERNEL_URL=ws://127.0.0.1:18889 \
AGENT_SHELL_KERNEL_TOKEN=<隔离实例 token> \
app/.build/AgentShell.app/Contents/MacOS/AgentShell
```

或用 `open` 的 `--env`（macOS `open` 原生支持、已验证，可重复传；注意 `open` 默认**不会**透传
当前 shell 的环境变量给被打开的 app，必须用 `--env` 显式传）：

```bash
open app/.build/AgentShell.app --env AGENT_SHELL_KERNEL_URL=ws://127.0.0.1:18889 \
  --env AGENT_SHELL_KERNEL_TOKEN=<隔离实例 token>
```

不设置这两个变量时，壳会尝试连接 `ws://127.0.0.1:18889`——如果没有本项目的隔离 openclaw 实例在
监听，连接会失败，侧栏顶部状态条会变红并显示失败原因（这是"失败可见"要求的预期行为，不是 bug）。

## Settings 面板（⌘,）——无需环境变量的配置方式

上表两个环境变量仍然是**最高优先级**（脚本化/repro 场景不受影响），但**日常双击打开 app 的用户**
现在不再需要环境变量：⌘,（或 app 菜单"设置…"）打开标准 macOS Settings 面板，可以直接填写
endpoint、粘贴 token，点"保存并重连"立即生效，不需要重启整个 app。

**生效值精度：环境变量 > 已保存设置 > 内建默认值**——三层来源，面板上每个字段下方都标注当前生效值
来自哪一层；来源是环境变量时会额外提示"在此保存的值当前不会生效"，避免用户改了设置却摸不清为什么
没反应。

**token 只进 Keychain，endpoint 进 UserDefaults**——token 是凭证，本仓是 PUBLIC 仓库，不落任何
明文（`security find-generic-password -s dev.test-harnessloop.agent-shell.kernel-token`
可查，`defaults read dev.test-harnessloop.agent-shell` 不会包含它）。Keychain 条目属性：
`kSecClassGenericPassword` + `kSecAttrAccessibleWhenUnlocked`，不启用 iCloud 同步。

**尚未配置任何设置时**（全新安装、没有环境变量、Keychain 里也没存过）：内建占位符 token
（`agentshell-local-placeholder-token`）无法通过真实内核鉴权——侧栏会主动提示"尚未配置有效的内核
token"并给出前往设置的链接，不需要先撞见一次连接失败才发现。

实现细节、Keychain 选型理由、精度链解析逻辑见 `Sources/AgentShellCore/KernelShellSettingsStorage.swift`；
入库回归测试见 `app/kernel-client/swift/frame-replay-tests/KernelShellSettingsTests.swift`。

## L1 UI 说明

- 左侧栏顶部一条彩色状态条：灰=未连接、黄=连接中、绿=已连接、红=失败（附错误文本）。
- 「新建会话」调 `KernelClient.createSession`，成功后新会话进入左侧列表并被自动选中；失败在
  侧栏底部以红色内嵌文字显示。**全程不用 `.alert()`/`.sheet()`/`.confirmationDialog()` 等模态
  UI**——默认连接目标在没有本地实例监听时会自然连接失败，如果错误呈现走模态框，仅仅打开这个
  app 就会自动弹出对话框。
- 选中会话后右侧渲染消息流：用户发出的消息（本地回显）+ 从 `subscribe()` 事件流中
  `evt.message.delta`（`role:'assistant'`）解析出的 assistant 文本，按 `messageID` 分组、
  每帧携带完整全文覆盖（不是按 `(runId, index)` 分组累积增量——那是 rounds/0012 之前已被实测
  证明会撞键导致文本重复的旧实现，本节此前一直没跟着改，rounds/0013 B2 订正；分组理由见
  `SessionStore.appendAssistantDelta` 的文档注释，入库回归测试见
  `frame-replay-tests` 的 `SessionStoreGroupingTests.swift`）。
- `evt.turn_complete`/`evt.error`/`evt.session_end` 驱动"是否在等回复"指示（顶部小圈 + 文案）；
  `evt.error`/`evt.session_end` 另外在消息流里插入一条系统行。事件流本身中断（不是单条错误事件，
  而是整条 `AsyncThrowingStream` 抛错结束）时，在会话底部单独一条红色横幅显示，和"会话内某次
  run 报错"区分开。
- 输入框支持 Enter 发送（Shift+Enter 换行，`TextField(axis: .vertical)` 默认行为）。

## L1 不做（如实标注，归 L2/L3 或后续轮次）

流式渲染细节（如逐字符动画/`streamingGranularity` 门控）、stop 按钮、interrupt、
respondApproval、capabilities（三个 TODO 桩方法本壳未调用，见 `SessionStore.swift` 头注释）、
成本/用量面板、能力开关、跨会话搜索、pin/rename/archive、D5.2 §2.2 的"草稿态 -> 首次发送时原子
create+send"创建时点设计（本轮按任务书明确要求做的是更简单的"点新建即 createSession"）。也没有
"关闭/停止会话"这个动作——会话从创建到进程退出都保持订阅打开，不调用 `stop()`。
