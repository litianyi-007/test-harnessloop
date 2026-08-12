// swift-tools-version: 5.9
// SG-10 L1 Mac UI 壳地基：把此前靠裸 swiftc 编译的 app/kernel-client/swift + app/generated/swift
// 打包成 SwiftPM 包，供后续 SwiftUI 壳（app/apps/）依赖。
//
// 包根必须是 app/kernel-client/swift 与 app/generated/swift 的共同祖先，即 app/ 本身
// （SwiftPM target 的 path 必须落在包根内）。
//
// tools-version 选 5.9（不是本机 Swift 6.3.3 工具链支持的更高版本）是有意为之，不是没跟上：
// 实测 tools-version 6.0 默认把新 target 切进 Swift 6 严格并发语言模式，会立刻在
// OpenclawGatewayKernelClient（actor，conforms to KernelClient）上报
// "non-Sendable parameter type 'Config' cannot be sent from caller of protocol requirement...
// into actor-isolated implementation" —— 因为 app/generated/swift 里的 120 个 D2 类型都没有
// Sendable 标注。修这个需要动 app/generated/swift（被硬性禁止）或者给 D2 类型追加 Sendable 一类的
// 语义相关改动，超出本步"纯结构重排"的范围。裸 swiftc（无 -swift-version 参数）用的是 Swift 5
// 语言模式，不做这层强制检查——tools-version 5.9 复现的正是这个既有行为，两者在本机 Swift 6.3.3
// 工具链下都能正常编译、消费同一套源码，无需触碰任何生成文件或补 Sendable。
import PackageDescription

let package = Package(
    name: "AgentAppKernel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "D2Generated", targets: ["D2Generated"]),
        .library(name: "KernelClient", targets: ["KernelClient"]),
        .library(name: "AgentShellCore", targets: ["AgentShellCore"]),
        .executable(name: "kernel-client-cli", targets: ["kernel-client-cli"]),
        .executable(name: "frame-replay-tests", targets: ["frame-replay-tests"]),
        .executable(name: "AgentShell", targets: ["AgentShell"]),
    ],
    targets: [
        // quicktype 生成的 D2 DTO + 手写判别联合（DiscriminatedUnions.swift）。目录内容本身
        // 不受本次改造影响——path 直接指向既有 app/generated/swift，不挪不改任何文件。
        .target(
            name: "D2Generated",
            path: "generated/swift"
        ),

        // kernel-client 可复用部分：D1 KernelPort 协议 + openclaw wire 适配 + 事件映射 +
        // actor 实现 + CLI 跑批逻辑。exclude 掉的两个子目录各自是独立的 executable target
        // （见下），不属于这个 library。
        //
        // -enable-testing：让 frame-replay-tests target 可以对这个模块做
        // `@testable import KernelClient`，从而不必把 OpenclawGatewayKernelClient.swift 里那一批
        // `testSupport*` 方法（本来就刻意保持 internal，不想污染公开 API 面）逐个改成 public——
        // 这批方法在裸 swiftc 时代靠"同一次编译=同一个隐式 module"拿到同模块访问权限，拆包后用
        // `-enable-testing` + `@testable import` 是对等的替代，不改变任何一个符号原本的访问级别。
        .target(
            name: "KernelClient",
            dependencies: ["D2Generated"],
            path: "kernel-client/swift",
            exclude: ["cli", "frame-replay-tests"],
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),

        // 原来的 CLI 入口（main.swift）。挪进独立子目录是因为它和 FrameReplayTestMain.swift
        // 都曾直接躺在 kernel-client/swift/ 下、都是各自 target 的顶层可执行入口，SwiftPM 要求
        // 同一个 target 的源码落在同一目录，两个入口不能共享 kernel-client/swift/ 这一个 target。
        .executableTarget(
            name: "kernel-client-cli",
            dependencies: ["KernelClient"],
            path: "kernel-client/swift/cli"
        ),

        // rounds/0013 B2：AgentShell 壳的"模型层"单独拆成一个 library target——ChatModels/
        // ChatSessionViewModel/KernelShellConfig/SessionStore 四个文件天然不 `import SwiftUI`
        // （壳自己的状态/视图模型，D1/D2 事件如何驱动 UI 状态的判断逻辑全在这四个文件里），
        // 只是历史上和视图层文件（AgentShellApp/ContentView/SessionDetailView/SessionListView，
        // 都 `import SwiftUI`）躺在同一个 executableTarget 里。问题：`AgentShell` 是
        // executableTarget（还带 `@main`），`frame-replay-tests` 也是 executableTarget——两个
        // executableTarget 之间 SwiftPM 不允许干净地互相 import（可执行产物不能被当库使用），
        // 导致 `frame-replay-tests` 结构性够不到 `SessionStore`，UI 的消息分组行为（按 messageID
        // 分组、`=` 覆盖而非 `+=` 追加，见 SessionStore.appendAssistantDelta 文档注释）此前只能
        // 在 kernel-client 的 wire-mapping 层间接验证（testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs
        // 只验证 messageID 透传正确，验不到 SessionStore 是否真的用它正确分组/不合并），
        // rounds/0012 §7a 因此被两路评审判"名不副实"。
        //
        // 拆成 library target 后 `frame-replay-tests`（同为 executableTarget，但可以依赖 library
        // target）可以直接依赖它，`AgentShell` 也依赖它、只保留视图层文件——这是 SwiftPM 里
        // "executable 之间无法互相依赖，但都能依赖同一个 library" 的标准解法，不是绕过限制。
        //
        // -enable-testing：和 `KernelClient` target 同样的理由（该 target 定义处的注释已经讲过，
        // 不重复）——让 `frame-replay-tests` 能 `@testable import AgentShellCore` 拿到
        // `SessionStore.handle(_:for:)` 这个本来是 `private`、本轮为了让测试够到分组行为改成
        // internal 的方法（改动理由见 SessionStore.swift 该方法上方的文档注释）。
        .target(
            name: "AgentShellCore",
            dependencies: ["KernelClient", "D2Generated"],
            path: "apps/AgentShell/Sources/AgentShellCore",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),

        // Frame-replay 单测。保持"自写断言 + 独立 @main 入口"的既有形态（不迁 XCTest）——
        // 这是本步唯一决策点之一，理由见任务报告：迁 XCTest 会引入"测试是否等价"的新问题，
        // 而这里只是把同样的代码换个 target 装，跑出来的判定逻辑一行没动。
        //
        // rounds/0013 B2：新增对 `AgentShellCore` 的依赖——本 target 新增的
        // SessionStoreGroupingTests.swift 需要 `@testable import AgentShellCore` 直接驱动
        // `SessionStore.handle(_:for:)`，验证 UI 层的消息分组行为（不是 kernel-client 的
        // wire-mapping 层）。这正是本轮任务的核心目的：让"入库测试"够得到 `SessionStore`。
        .executableTarget(
            name: "frame-replay-tests",
            dependencies: ["KernelClient", "D2Generated", "AgentShellCore"],
            path: "kernel-client/swift/frame-replay-tests"
        ),

        // SG-10 L1 Mac UI 壳：原生 SwiftUI executable target，同样落在这个包内（不是独立
        // .xcodeproj，见 app/apps/AgentShell/README.md）。rounds/0013 B2 起只剩视图层四个文件
        // （AgentShellApp/ContentView/SessionDetailView/SessionListView，均 `import SwiftUI`）——
        // 模型层（ChatModels/ChatSessionViewModel/KernelShellConfig/SessionStore）已拆进
        // `AgentShellCore`（见上）。依赖只列 `AgentShellCore`：视图层文件里对 `SessionStore`/
        // `ChatSessionViewModel`/`ChatMessage` 等类型的直接具名引用（如
        // `@Environment(SessionStore.self)`、`let session: ChatSessionViewModel`）都来自这个
        // 新 target，实测（`swift build --package-path app`）不需要再显式列 `KernelClient`/
        // `D2Generated`——视图层文件从未直接具名引用这两个模块的类型（比如
        // `session.handle.kernel.rawValue` 全程走成员访问链，没有一处把 `SessionHandle`
        // 这个类型名写在 AgentShell 目录的文件里），Swift 允许对"类型从别的 target 推断得到、
        // 但从未在本文件里被具名引用"的值做成员访问而不需要本文件也 import 那个更底层的
        // target——`AgentShellCore` 自己 import 了 KernelClient/D2Generated 就够。
        .executableTarget(
            name: "AgentShell",
            dependencies: ["AgentShellCore"],
            path: "apps/AgentShell/Sources/AgentShell"
        ),
    ]
)
