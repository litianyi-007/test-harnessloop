# Scope Lock — goal 002 / rounds/0019

**开轮时间**：2026-08-13，**动手之前**写就。用户裁定按 2 → 1 → 3 顺序执行，本轮是第 2 件。

## Round Objective

**让用户能在 app 里填内核地址与 token，不必依赖环境变量。**

## 为什么这是距「可试用」最近的一块砖

MVP 盘点实测：`KernelShellConfig.swift:26` 的 token 默认值是
`"agentshell-local-placeholder-token"`，**对真内核必然鉴权失败**，而
**UI 里没有任何地方能填**。用户拿到 app、双击打开、看到「连接失败」，**没有任何出路**。

雪上加霜的是一条既有文档 gotcha：**`open` 不继承 shell 环境变量**，所以连
「先 export 再打开」这条路对普通用户也不通——必须 `open --env` 或直接跑二进制。
**有了设置界面，这个坑对终端用户就消失了。**

## 三个必须先定死的取舍

### 1. token 存哪里 → **Keychain，不是 UserDefaults**

token 是凭证。本仓是 PUBLIC 且有过泄漏事件（`docs/security-incident-20260726.md`），
把凭证写进 plist / UserDefaults 是错的——那是明文、会进备份、会被 `defaults read` 读出来。
**endpoint 存 UserDefaults 可以（它不是秘密），token 必须进 Keychain。**

### 2. 环境变量与界面设置谁优先 → **环境变量优先，但必须显示当前生效来源**

repro 脚本与 `CLIRunner` 都靠环境变量驱动，**不能让界面设置把脚本流程搞坏**。
所以 `env > 已存设置 > 默认值`。

但「设置了却不生效」是最难排查的一类问题，所以**界面上必须显示当前值来自哪里**
（环境变量 / 本机设置 / 默认占位符）。**只做优先级不显示来源 = 制造一个新的静默失败。**

### 3. 占位符 token 怎么处理 → **保留为最后兜底，但要显式可见**

不改默认值（repro 脚本与现有测试依赖当前行为），但**当生效 token 仍是占位符时，
侧栏必须显示明确提示并指向设置**——不能等到连接失败才用一句 `transport error` 打发用户。

## 本轮不做

- **不改变 `fromEnvironment()` 的既有语义**（环境变量存在时的行为一字不变）。
- **不实现停止按钮**（第 3 件，独立轮）。
- **不做真实 LLM 往返的内容态实拍**（第 1 件，独立轮，用户已授权但需单独跑）。
- 不碰三个插件 submodule、不碰 `app/kernel-client/` 非测试目录、不碰 `app/generated/`。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/apps/AgentShell/Sources/AgentShellCore/KernelShellConfig.swift` | 改 | 增加「来源」概念与设置读取；**不改环境变量已存在时的行为** |
| `app/apps/AgentShell/Sources/AgentShellCore/` | 写 | 新增 Keychain 存取与设置模型 |
| `app/apps/AgentShell/Sources/AgentShell/` | 改/写 | Settings 场景、来源提示、保存并重连 |
| `app/kernel-client/swift/frame-replay-tests/` | 写 | 回归测试 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0019/` | 写 | 本轮产物 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `app/kernel-client/` 下除 `frame-replay-tests/` 外任何文件
- `app/generated/`、`app/contracts/`、`app/server/`、`app/parity/`、`.github/`
- `Package.swift` 的 platforms、`Info.plist` 的最低版本
- **把 token 写进 UserDefaults / plist / 任何明文落盘位置**（红线，见下）

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| 构建 | `swift build --package-path app` exit 0 | 直接捕获退出码 |
| 回归 | 帧回放 **≥83/83** | 测试输出 |
| **token 不落明文** | 全仓搜确认 token 不出现在 UserDefaults/plist 写入路径；Keychain 项属性正确 | 代码引用 + 测试 |
| **环境变量优先级** | 设了 env 时界面设置不生效，且**界面如实显示「来自环境变量」** | 测试 |
| **来源显示正确** | 三种来源（env / 设置 / 默认占位符）各有对应显示 | 测试 + 截图 |
| **占位符提示** | 生效 token 为占位符时侧栏有明确提示并指向设置 | 截图 |
| 保存后重连 | 改完设置能重连而不必重启 app | 实拍或测试 |
| 实拍 | 设置界面 + 占位符提示各一张 | 截图路径 |

## 红线

- **token 绝不明文落盘。** 违反即本轮不接受，无论其它做得多好。
- **不得为了让「设置生效」而把环境变量优先级反过来** —— 那会悄悄破坏 repro 脚本与
  CLIRunner 的既有流程，属于用一个静默失败换另一个。
- **来源必须可见。** 只做优先级不显示来源，等于制造新的「设置了却没用上」类静默失败。

## 异构评审

改动完成后派**单路**只读评审，重点问：①token 是否真的只进 Keychain
②环境变量优先级是否真的没被破坏 ③「来源显示」是否真实反映生效值而非只是标签。
