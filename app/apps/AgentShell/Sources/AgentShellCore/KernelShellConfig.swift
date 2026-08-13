// 环境变量读取——沿用既有 SG4_KERNEL_URL/SG4_KERNEL_TOKEN 风格但用壳自己的变量名
// （AGENT_SHELL_KERNEL_URL/AGENT_SHELL_KERNEL_TOKEN），默认值指向本项目 kernels/openclaw
// submodule 起的隔离内核实例默认端口（ws://127.0.0.1:18889，与 app/kernel-client/swift/
// CLIRunner.swift 的 SG4_KERNEL_URL 默认值一致，不是用户全局 18789 实例），token 默认值是明显的
// 本地占位符字符串，不是真凭证——本仓是 PUBLIC 仓库，见根 CLAUDE.md 凭证守门纪律。

import Foundation

/// **可见性变更（rounds/0013 B2）**：struct 本身与 `fromEnvironment()` 改为 `public`——
/// `AgentShellApp.swift`（现在是独立的 `AgentShell` target）要跨模块调用
/// `SessionStore(config: .fromEnvironment())`，即使 `.fromEnvironment()` 是隐式成员表达式、没有
/// 在调用处拼出 `KernelShellConfig` 这个类型名，Swift 的访问控制仍然按"被引用的声明本身"而非
/// "调用处有没有拼出类型名"来判定，所以类型和这个静态工厂方法都必须是 public。三个存储属性
/// （endpoint/token/configWarning）维持 internal 不变——它们只在 `AgentShellCore` 模块内部被读取
/// （`SessionStore.init` 与本文件自己），`AgentShell` 视图层从不直接touch 这几个字段，不需要放宽。
public struct KernelShellConfig {
    let endpoint: URL
    let token: String

    /// AGENT_SHELL_KERNEL_URL 被设成非法 URL 时的诊断信息——不 fatalError 整个 app（那样"失败不可
    /// 诊断"，用户只会看到进程消失/闪退），而是回退到默认端点，把这条诊断信息交给 SessionStore
    /// 在侧栏上展示，走和其它连接失败一致的"UI 可见"路径。
    let configWarning: String?

    /// **新增（Settings UI）**：endpoint/token 各自的生效值来自哪一层——环境变量 > 已保存设置
    /// （UserDefaults/Keychain，见 KernelShellSettingsStorage.swift）> 内建默认值。Settings 面板
    /// 与侧栏据此标注"当前值来源"，避免"改了设置却看起来什么都没发生"（常见原因是环境变量仍在
    /// 覆盖，用户如果看不到来源标注就无从诊断）。
    ///
    /// 默认值 `.builtInDefault`——不是断言"没指定来源就等于用了默认值"，而是让这两个字段加入
    /// *之前*就已经存在的调用点（`frame-replay-tests` 里 6 处直接
    /// `KernelShellConfig(endpoint:token:configWarning:)` 构造，用于跟 Settings 完全无关的
    /// SessionStore 单测）不需要跟着改一个字符就能继续编译——同 `ChatMessage.timelineSeq` 默认值
    /// `0`（ChatModels.swift 的文档注释）的先例，是这个代码库对"加字段不强制牵连既有调用点"的
    /// 既有解法，不是本文件首创。那些调用点从不断言 source，默认值给哪个 case 都不影响它们的判定。
    public let endpointSource: KernelConfigValueSource
    public let tokenSource: KernelConfigValueSource

    static let defaultEndpointString = "ws://127.0.0.1:18889"
    static let defaultToken = "agentshell-local-placeholder-token"

    /// 显式 init——**实测坐实**（不是靠读文档猜的）：Swift 对"带默认值表达式的 `let` 存储属性"
    /// 的逐成员初始化器合成规则是**整个排除在参数列表之外**（不是"排除但仍可传"，也不是"included
    /// with that default"）——同 `ChatMessage.swift` 里 `id`/`createdAt` 的先例（那两个字段同样是
    /// 带默认值的 `let`，该文件文档注释原话："本就不进逐成员初始化器的参数列表"）。`endpointSource`/
    /// `tokenSource` 需要在 `fromEnvironment()`/`resolved()` 里被显式传参覆盖默认值，所以不能指望
    /// 编译器合成的隐式 init——手写一个，参数默认值直接写在参数列表上（`= .builtInDefault`），效果
    /// 上等价于"没传就用默认值、传了就用传入值"，只是不再依赖那条被证伪的合成规则。访问级别不标
    /// `public`（沿用原本合成 init 的 internal 级别）——`frame-replay-tests` 一直是通过
    /// `@testable import AgentShellCore` 拿到 internal 级别的可见性，不是靠这个 init 本身 public。
    init(
        endpoint: URL, token: String, configWarning: String?,
        endpointSource: KernelConfigValueSource = .builtInDefault,
        tokenSource: KernelConfigValueSource = .builtInDefault
    ) {
        self.endpoint = endpoint
        self.token = token
        self.configWarning = configWarning
        self.endpointSource = endpointSource
        self.tokenSource = tokenSource
    }

    /// **任务书硬要求**：这个函数在 env 变量已设置时的行为不得有任何变化——下面前 6 行（到
    /// `token` 那一行为止）与新增的两个 source 局部变量互不干扰，`endpoint`/`token`/
    /// `configWarning` 三个字段的取值逻辑与新增 source 字段之前逐字节相同，只是把"这一次到底
    /// 是不是从环境变量拿到的"这个已经算出来的事实也带进返回值里，不影响前者。
    public static func fromEnvironment() -> KernelShellConfig {
        let env = ProcessInfo.processInfo.environment
        let urlString = env["AGENT_SHELL_KERNEL_URL"] ?? defaultEndpointString
        let token = env["AGENT_SHELL_KERNEL_TOKEN"] ?? defaultToken
        let endpointSource: KernelConfigValueSource =
            env["AGENT_SHELL_KERNEL_URL"] != nil ? .environmentVariable : .builtInDefault
        let tokenSource: KernelConfigValueSource =
            env["AGENT_SHELL_KERNEL_TOKEN"] != nil ? .environmentVariable : .builtInDefault

        if let url = URL(string: urlString) {
            return KernelShellConfig(
                endpoint: url, token: token, configWarning: nil,
                endpointSource: endpointSource, tokenSource: tokenSource
            )
        }
        // URL(string:) 只有在字符串本身不是合法 URL 语法时才会返回 nil——force unwrap 这个
        // 编译期已知合法的字面量默认值是安全的，不是绕过错误处理。
        let fallback = URL(string: defaultEndpointString)!
        return KernelShellConfig(
            endpoint: fallback,
            token: token,
            configWarning: "AGENT_SHELL_KERNEL_URL 不是合法 URL（\(urlString)），已回退到 \(defaultEndpointString)",
            endpointSource: endpointSource,
            tokenSource: tokenSource
        )
    }
}
