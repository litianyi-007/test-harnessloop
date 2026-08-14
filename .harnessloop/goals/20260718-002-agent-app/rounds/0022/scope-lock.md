# Scope Lock — goal 002 / rounds/0022

**开轮时间**：2026-08-14，**动手之前**写就。这是「Windows 端 + 第二内核」方案的第 1 步。

## Round Objective

**把金标 parity 套件里那个会静默失效的开关修掉**——`DEGRADED` 判定由**硬编码方法名单**
改为**运行时发现**，并让两端的能力分歧在报告里显式可见。

## 为什么这一步必须先于一切

跨端一致性的全部指望都在这套 fixture 上。而它现在有一份硬编码名单：

```
["interrupt", "respondApproval", "capabilities"]
```

（Swift 在 `swift-runner/SwiftFixtureRunner.swift:941`，C# 在
`csharp-runner/CSharpFixtureRunner.cs:1008`，**两端逐字相同**）

凡 timeline 调用这三个之一的 fixture **整条跳过**，还打印一段言之凿凿的理由说它们
「方法体均为 `throw notImplemented`」。**而事实是**：

| 方法 | 名单声称 | Swift 实际 | C# 实际 |
|---|---|---|---|
| `respondApproval` | TODO 桩 | **rounds/0015 已实现** | 仍是桩（`:839`） |
| `interrupt` | TODO 桩 | **rounds/0020 已实现** | 仍是桩（`:421`） |
| `capabilities` | TODO 桩 | 确实是桩（`:2187`） | 仍是桩（`:842`） |

**Swift 那份名单从 rounds/0015 起就过期了，五轮无人察觉。** 而
`SwiftRunnerMain.swift:20` 写明「DEGRADED 不计入失败」——**退出码保持 0**。
**套件报成功，却静默跳过了恰恰是新实现能力的那些 fixture。**

**放到跨平台语境里它更危险**：parity 套件本该是「让两端保持同步」的唯一机制，
而**最可能分歧的正是新实现的能力，也正是它不检查的那些**。

## 三个必须先定死的取舍

### 1. 「运行时发现」怎么发现 → **跑它，看它抛什么**

不做「先探测再决定」的两段式（那仍是一种查表，只是表变成了探测结果缓存）。
**直接执行 timeline；若 client 抛 `notImplemented`，标 DEGRADED；其它任何结果都是真实的 PASS/FAIL。**

这样名单彻底消失，**新实现一个方法，它的 fixture 下一次运行就自动开始被真正检查**，
没有任何人需要记得去改名单。

### 2. **分歧必须显式可见** → 报告要能回答「哪一端覆盖了、哪一端没有」

改完之后 Swift 会真跑 interrupt/respondApproval 的 fixture、C# 仍会 DEGRADE 它们。
**这个差异本身就是最有价值的输出**——它是 Mac↔Windows 能力分歧的第一份机器判据。
两端 runner 的摘要行要能让人一眼看出这件事，而不是各自打印一个 `12 PASS / 1 DEGRADED` 了事。

### 3. **不为了让数字好看而实现 C# 的三个方法** → 本轮不做

本轮只修**判定机制**。C# 的 interrupt/respondApproval 该不该实现是下一步的事，
**在本轮把它们实现掉会掩盖这次改动的全部意义**——正是要让分歧显出来。

## 本轮不做

- **不实现 C# 端的 `interrupt`/`respondApproval`/`capabilities`**（见取舍 3）。
- **不改任何 fixture JSON**——判定机制变了，用例不变，否则无法对照改动前后。
- 不改 Swift/C# 的 kernel client 本身。
- 不做 `HermesKernelClient`、不做 Windows UI（后续轮）。

## Allowed Changes

| Path | Action | Limit |
| --- | --- | --- |
| `app/contracts/d2/fixtures/swift-runner/` | 改 | DEGRADED 判定改为运行时发现；摘要显式化 |
| `app/contracts/d2/fixtures/csharp-runner/*.cs` | 改 | 同上；**不改 `.csproj` 的编译项清单** |
| `app/contracts/d2/fixtures/README.md` | 改 | 更新「三端 parity」一节的说明 |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0022/` | 写 | 本轮产物与证据 |
| `.harnessloop/state/current.md`、`docs/validation-log.md` | 改 | 收盘 |
| `.hopper/queue.md` | 写 | 评审任务行 |

## Disallowed Changes

- `app/contracts/d2/fixtures/**/*.json`（**任何 fixture 用例**）
- `app/kernel-client/swift/`、`app/kernel-client/csharp/`（**两端 client 本体**）
- `app/generated/`、`app/apps/`、`app/server/`、`app/parity/`、`.github/`、`kernels/`
- `Package.swift`、`CSharpRunner.csproj` 的编译项

## Verification Commands Or Checks

| Check | Expected | Evidence |
| --- | --- | --- |
| Swift runner 构建 | `swiftc … -o /tmp/swift-fixture-runner` exit 0 | 直接捕获退出码 |
| C# runner 构建 | `dotnet run` exit 0 | 同上 |
| **名单已消失** | 两端源码中不再有 `["interrupt","respondApproval","capabilities"]` 这类方法名硬编码 | `command grep` |
| **Swift 侧行为变化** | interrupt/respondApproval 的 fixture **不再 DEGRADED**，而是给出真实 PASS 或 FAIL | 改动前后两份运行输出对照 |
| **C# 侧行为不变** | 三者仍 DEGRADED，**但理由来自实际捕获的 `notImplemented`，不是查表** | 运行输出 |
| **分歧可见** | 两端摘要能回答「哪一端覆盖了这条 fixture」 | 运行输出 |
| app 侧无回归 | `swift build --package-path app` exit 0，帧回放 **≥163/163** | 先看 build exit |
| **破坏性反证** | 把发现逻辑改回硬编码 → 必须能观察到差异；**注入命中数 > 0** | 红绿两份输出 |

## 红线

- **不得为了让数字好看而实现 C# 的三个方法**——本轮的价值就在于让分歧显出来。
- **不得改任何 fixture JSON**——改动前后必须可对照。
- **不得让 DEGRADED 继续「不计入失败且无人可见」**：即便仍不计入退出码，
  摘要也必须让分歧一眼可见。
- **破坏性反证必须先看 build exit 再看统计数**（本项目已两次栽在读旧二进制上）。

## 异构评审

改动完成后派只读评审，重点问：①「运行时发现」是否真的没有残留查表
②interrupt/respondApproval 的 fixture 这次是真跑了还是换了个方式跳过
③两端分歧是否真的在报告里可见 ④有没有新的静默失败路径。
