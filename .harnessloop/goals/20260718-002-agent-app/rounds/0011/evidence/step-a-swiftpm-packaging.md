# rounds/0011 Step A 证据 —— SwiftPM 包结构改造

范围：SG-10 L1 的地基步骤，**不含任何 UI 代码**。执行者 = claude-sonnet-5 子代理（`effort: xhigh`）；本文件记录的是**主会话独立复验**的实测输出，非子代理自述。

## 0. 改造前基线（主会话，派活前建立）

不先立基线，「别弄坏它」就无法证伪。按 `KernelClient.swift` 文件头注释记录的裸 `swiftc` 命令编译并运行帧回放测试：

```
=== 结果: 30/30 PASS ===
```

编译期有既有 `NSLock` 弃用告警（属既有噪声，未消）。

## 1. 包结构

`app/Package.swift`（`swift-tools-version: 5.9`，`platforms: [.macOS(.v14)]`，包名 `AgentAppKernel`），4 个 target：

| Target | 类型 | path | 依赖 |
|---|---|---|---|
| `D2Generated` | library | `generated/swift`（**原地不动，零改动**） | — |
| `KernelClient` | library | `kernel-client/swift`，`exclude: ["cli", "frame-replay-tests"]` | `D2Generated` |
| `kernel-client-cli` | executable | `kernel-client/swift/cli` | `KernelClient` |
| `frame-replay-tests` | executable | `kernel-client/swift/frame-replay-tests` | `KernelClient`, `D2Generated` |

**tools-version 取 5.9 而非 6.x 是有实测依据的取舍**（不是没跟上工具链）：6.0 会把新 target 切进 Swift 6 严格并发语言模式，立刻在 `OpenclawGatewayKernelClient`（actor，conforms to `KernelClient`）报 `non-Sendable parameter type 'Config' cannot be sent ... into actor-isolated implementation`——根因是 `app/generated/swift` 的 120 个 D2 类型均无 `Sendable` 标注。修它要么改生成文件（本轮硬禁），要么给 D2 面追加 `Sendable`（属语义相关改动，超出「纯结构重排」）。裸 `swiftc` 用的就是 Swift 5 语言模式，5.9 复现的正是既有行为。

**`-enable-testing` + `@testable import`** 替代「把 `testSupport*` 方法逐个改 public」：这批方法原本刻意保持 internal，裸 `swiftc` 时代靠「同一次编译=同一隐式 module」拿到同模块访问权，拆包后用 `-enable-testing` 是对等替代，**未改动任何符号的访问级别**。

## 2. 主会话独立复验（全部实跑，非采信自述）

| 检查 | 命令 | 实测结果 |
|---|---|---|
| 洁净重建 | `rm -rf app/.build && swift build --package-path app` | `Build complete! (7.13s)` |
| 帧回放测试 | `./app/.build/debug/frame-replay-tests` | **`=== 结果: 30/30 PASS ===`**（`grep -c [PASS]`=30，`[FAIL]`=0，与基线逐数吻合） |
| release 构建 | `swift build --package-path app -c release` | `Build complete! (18.11s)`——`-enable-testing` 是 `unsafeFlags`，release 下未破 |
| codegen 类型保真 | `node app/contracts/d2/codegen/scripts/verify-type-fidelity-swift.mjs` | 全部负例如预期编译失败，`type-level 断言有牙齿` |
| CI 平价 runner | 逐字复现 `.github/workflows/ci.yml:145-154` 的 flat-`swiftc` 命令 | **`=== 12 PASS / 0 FAIL / 1 DEGRADED （共 13 条 fixture） ===`**，与 CI 步骤名里写死的期望逐字吻合 |

后两项是**子代理自承没跑**的缺口（它如实报告了「只做代码推断，未实跑」），由主会话补齐。

## 3. `#if canImport(D2Generated)` 的双向证明

`.github/workflows/ci.yml` 的 Swift golden parity runner 用一条裸 `swiftc` 把 4 个 kernel-client 文件与 fixture runner **平铺同编**。拆包后新增的 `import D2Generated` 会让这条命令 `no such module` 而红。子代理的处置是把 5 处 import 包进 `#if canImport(D2Generated)`。

这个开关成立与否**不靠读代码判断，靠两次构建互为反证**：

- SwiftPM 构建下若 `canImport` 取假 → import 被跳过 → `Config`/`SessionHandle` 等类型解析不到 → **必编译失败**。实测成功 ⇒ 该分支取真。
- flat `swiftc` 构建下若 `canImport` 取真 → 发出 import → **必 `no such module` 失败**。实测成功 ⇒ 该分支取假。

两次构建都成功，即证明同一处 `#if` 在两种构建下确实取了相反的值，而不是「碰巧都没报错」。

## 4. 改动范围核对（逐项 git 核实，非声明）

- `app/generated/`：`git diff --stat` 空 + `git status --porcelain` 空 ⇒ **零改动坐实**。
- 禁区 `app/server` / `app/contracts` / `app/deploy` / `app/parity` / `harnessloop` / `hopper-plugin` / `kata` / `.github`：**逐一 `git status` 干净**。
- `kernels/openclaw` 显示 `M`：**本步之前即已存在**（本会话早前 openclaw PR 线留下的未提交状态，派活前的 git status 已见），非本步产物。

实际改动：

```
 M app/kernel-client/RUN-EVIDENCE.md
 M app/kernel-client/swift/{CLIRunner,EventMapping,KernelClient,OpenclawGatewayKernelClient,OpenclawWire}.swift
RM app/kernel-client/swift/main.swift -> .../cli/main.swift
RM app/kernel-client/swift/FrameReplayTestMain.swift -> .../frame-replay-tests/FrameReplayTestMain.swift
RM app/kernel-client/swift/FrameReplayTests.swift -> .../frame-replay-tests/FrameReplayTests.swift
?? app/.gitignore
?? app/Package.swift
```

**非注释代码改动全量**（`git diff` 剔除纯注释行后的完整结果，无遗漏）：

```
+#if canImport(D2Generated) / +import D2Generated / +#endif   × 5 处
-func runL1CloseLoop()  →  +public func runL1CloseLoop()      × 1 处
+import KernelClient / +@testable import KernelClient / +import D2Generated   （三个被 git mv 的文件各一）
```

零 D1/D2 契约语义改动：`KernelClient` 7 方法签名、`EventMapping` 映射行为、wire 帧格式一行未动——由上表逐行 diff 与 30/30 帧回放断言（这些断言正是在考映射/协议行为）双向坐实。

## 5. 残留与判断

- **`.unsafeFlags` 的已知后果**：使用 `unsafeFlags` 的包**不能被其它包当作远程依赖消费**。本轮 Mac 壳将作为**同一个包内的 target**，不受影响；但若将来有人想跨包依赖 `KernelClient`，这里会挡住。登记为已知约束，本轮不处理。
- `app/.gitignore` 为新增文件，落在 `app/` 根而非 scope-lock 逐字写的 `app/kernel-client/swift/` 行内——子代理主动标注为范围判断项。主会话判定：`Package.swift` 的必要配套（`.build/` 是大体积机器产物），落在 scope-lock「`app/apps/` 建 + Mac 壳落点」与本轮构建方式裁决的合理延伸内，予以接受并在此如实登记。
- `app/contracts/d2/fixtures/swift-runner/SwiftRunnerMain.swift` 有一句散文提到旧路径 `app/kernel-client/swift/main.swift`（现已移至 `cli/`）——纯描述性、非可执行命令，且该路径属本轮禁区，**故意未改**，在此登记以免日后被当成遗漏。
- 子代理未跑 CI 的 ubuntu job（TS/C#/jest）步骤，其「无文本重叠」结论来自 grep 而非实跑。本轮 Swift 侧三条 CI 步骤已由主会话逐条实跑坐实，ubuntu 侧留待 CI 自身验证。
