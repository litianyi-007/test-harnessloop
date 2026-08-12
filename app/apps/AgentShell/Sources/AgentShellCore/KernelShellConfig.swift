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

    static let defaultEndpointString = "ws://127.0.0.1:18889"
    static let defaultToken = "agentshell-local-placeholder-token"

    public static func fromEnvironment() -> KernelShellConfig {
        let env = ProcessInfo.processInfo.environment
        let urlString = env["AGENT_SHELL_KERNEL_URL"] ?? defaultEndpointString
        let token = env["AGENT_SHELL_KERNEL_TOKEN"] ?? defaultToken

        if let url = URL(string: urlString) {
            return KernelShellConfig(endpoint: url, token: token, configWarning: nil)
        }
        // URL(string:) 只有在字符串本身不是合法 URL 语法时才会返回 nil——force unwrap 这个
        // 编译期已知合法的字面量默认值是安全的，不是绕过错误处理。
        let fallback = URL(string: defaultEndpointString)!
        return KernelShellConfig(
            endpoint: fallback,
            token: token,
            configWarning: "AGENT_SHELL_KERNEL_URL 不是合法 URL（\(urlString)），已回退到 \(defaultEndpointString)"
        )
    }
}
