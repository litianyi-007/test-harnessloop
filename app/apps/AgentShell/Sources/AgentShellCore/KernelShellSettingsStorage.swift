// Settings UI 落点：token 进 Keychain，endpoint 进 UserDefaults，env 变量继续优先于两者——
// 三条决策均为任务书明确给定，这里只记录"怎么落地"与"为什么这么落地"，不重新论证要不要这么做。
//
// 本文件与 KernelShellConfig.swift 是两个文件、同一个类型的关系：核心 struct 与只读环境变量的
// `fromEnvironment()` 留在原文件（保持那个文件此前就有、已被测试依赖的行为不动），本文件只新增
// ——`resolved()`（完整 env > 已保存设置 > 内建默认值 精度链）与 `isTokenPlaceholder`
// 作为 `extension KernelShellConfig`，以及两个独立的存储封装类型。

import Foundation
import Security

/// 单个可配置项（目前只有 endpoint、token 两个）的生效来源。Settings 面板与侧栏据此标注
/// "当前值来自哪里"——precedence 本身没有变化（env 一直优先），但用户第一次有了"新增的第二个
/// 可能来源"这件事后，必须能分清"我保存的设置为什么没生效"是不是因为环境变量仍在起作用，否则
/// Settings UI 本身就会变成一种新的静默失败（改了设置、界面却看起来什么都没发生）。
public enum KernelConfigValueSource: String, Sendable, Equatable {
    case environmentVariable
    case savedSetting
    case builtInDefault
}

/// Keychain 读写的错误类型——不吞掉底层 `OSStatus`，逐字交给调用方（Settings UI）展示
/// （任务书明确要求："surface Keychain errors to the UI rather than silently swallowing them"）。
public struct KeychainStoreError: Error, CustomStringConvertible, Sendable {
    public let status: OSStatus
    public let operation: String

    public var description: String {
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        return "\(operation)失败：\(message)（OSStatus \(status)）"
    }
}

/// token 的 Keychain 读写封装——本壳唯一允许落盘凭证的地方（其余一律环境变量/内存，尤其是
/// **绝不**经由 `UserDefaults`/plist，见 `KernelEndpointDefaultsStore` 的分工边界与本仓根
/// CLAUDE.md 凭证守门纪律：本仓 PUBLIC，且已有过一次真实凭证泄漏事件）。
///
/// 五条 Keychain 选型决策（任务书逐条点名要求说明理由）：
///
/// 1. **`kSecClassGenericPassword`**——token 是这个 app 私有的共享密钥，不对应任何互联网域名/协议
///    （不适用 `kSecClassInternetPassword`），generic password 是 Apple 对"app 自己的密钥/token"
///    这一类数据的标准分类。
/// 2. **显式、稳定的 service/account 命名**——`service` 复用 `SessionPersistenceStore
///    .bundleIdentifier` 这同一个命名空间前缀（不是巧合：两者都以"这是 AgentShell 这个具体 app
///    的数据"为准绳，同一个前缀便于人工用 `security`/`defaults` 工具核对时一眼认出归属）；
///    `account` 用固定字面量——当前只有一个 token 需要存，不需要按内核实例分账户，未来若要支持
///    多 profile，account 是天然的扩展点，不需要改 service 命名方案。
/// 3. **`kSecAttrAccessibleWhenUnlocked`（不是 `Always`/`AfterFirstUnlock`）**——token 只在用户
///    主动使用这个 app 时才需要被读取，此时设备必然已解锁；没有任何后台/锁屏场景需要访问它。
///    `Always`/`AfterFirstUnlock` 会把凭证暴露在"设备已开机但未解锁"的窗口期，对一个不需要这种
///    可用性的场景是不必要的风险敞口，选最窄的那个。
/// 4. **不设 `kSecAttrSynchronizable`**（即不启用 iCloud 钥匙串同步，留空=系统默认不同步）——
///    这是本机开发用的临时 token，跟随用户 iCloud 账户同步到其它设备既无必要，也是任务书明确
///    划定的红线；这里刻意不写 `kCFBooleanFalse` 之类的"看起来像特意关闭"的样板代码，因为那会
///    掩盖"这本来就是默认值、不是这里做了什么特殊处理"这件事的真相。
/// 5. **add-vs-update 两段式**——`SecItemAdd` 在条目已存在时返回 `errSecDuplicateItem`（不是
///    覆盖写入），必须显式退回 `SecItemUpdate`；这是任务书明确点名的一处常见易错点，见 `save()`。
///
/// **实测过的经验风险（未在此代码里"修复"，因为没有通用修法——只能靠实测）**：本 app 用
/// `codesign --force --deep --sign -` 做 ad-hoc 签名（`build-app-bundle.sh`），每次重新构建
/// 产出的代码身份都不同；如果未来某次 Keychain 读取在真机上表现为访问被拒绝/弹出确认框，这正是
/// ad-hoc 签名跨构建身份漂移的已知代价，而不是这段代码逻辑写错了。本轮任务报告里有一节专门记录
/// 针对**已构建的 `.app` bundle 本身**（不是这段代码在测试里跑）做的实测结果。
public struct KernelTokenKeychainStore: Sendable {
    public static let defaultService = "\(SessionPersistenceStore.bundleIdentifier).kernel-token"
    public static let defaultAccount = "kernel-token"

    public let service: String
    public let account: String

    /// - Parameters:
    ///   - service/account：默认指向生产用的固定命名；测试传入按 UUID 隔离的独立 service，
    ///     避免污染开发者本机真实登录钥匙串里的这一条目、也避免测试之间互相干扰——同
    ///     `SessionPersistenceStore.directoryOverride` 的隔离哲学，只是把"隔离维度"从文件系统
    ///     目录换成了 Keychain 的 service 命名空间（Keychain 没有"临时目录"这个概念可用）。
    public init(service: String = defaultService, account: String = defaultAccount) {
        self.service = service
        self.account = account
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 读取。找不到条目返回 `nil`——这是正常态（全新安装、从未保存过），不是错误。其它任何
    /// `OSStatus`（含数据无法解码成 UTF-8 字符串这种不该发生但仍需处理的形状）一律 `throw`。
    public func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError(status: status, operation: "读取 token（数据解码）")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError(status: status, operation: "读取 token")
        }
    }

    /// 写入。先尝试 `SecItemAdd`；条目已存在（`errSecDuplicateItem`）则改走 `SecItemUpdate`——
    /// Keychain 的标准 add-vs-update 两段式，见本类型文档注释第 5 条。
    public func save(token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainStoreError(status: errSecParam, operation: "写入 token（字符串编码）")
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainStoreError(status: addStatus, operation: "写入 token（新增）")
        }
        // 已存在——SecItemUpdate 的 query 只需定位条目本身（不带 kSecValueData），待更新的字段放
        // 在第二个参数（attributesToUpdate）。
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainStoreError(status: updateStatus, operation: "写入 token（更新）")
        }
    }

    /// 删除。找不到条目视为成功（幂等）——"清除已保存 token"这个操作不应该因为本来就没有条目
    /// 而报错给用户看。
    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status, operation: "删除 token")
        }
    }
}

/// endpoint 的 UserDefaults 读写封装——endpoint **不是凭证**，UserDefaults/plist 明文落盘对它是
/// 安全的（凭证只走上面的 `KernelTokenKeychainStore`，两个类型物理上分开，方便审计时一眼确认
/// "写 UserDefaults 的代码路径里从没出现过 token 这个词"）。
public enum KernelEndpointDefaultsStore {
    /// 带 bundle id 前缀，避免与其它潜在 key 撞名（即便目前是这个 app 唯一的 UserDefaults 键）。
    public static let userDefaultsKey = "\(SessionPersistenceStore.bundleIdentifier).kernelEndpoint"

    /// - Parameter userDefaults：默认 `.standard`；测试传入 `UserDefaults(suiteName:)` 构造的
    ///   独立 suite，不触碰开发者机器上真实的 `defaults` 数据库（同 Keychain store 的隔离哲学）。
    public static func save(_ urlString: String, userDefaults: UserDefaults = .standard) {
        userDefaults.set(urlString, forKey: userDefaultsKey)
        // `synchronize()` 在现代 UserDefaults 文档里标注"通常不需要手动调用"——但那句话描述的是
        // "进程继续正常运行，系统有机会在后台完成落盘同步"这个场景。Settings 面板保存后用户可能
        // 立刻退出整个 app（本轮验证脚本甚至会立刻用外部 `defaults read` 命令核对落盘），不覆盖
        // "写完几乎立刻整进程退出"这个边界情形；显式调用的成本只是几毫秒，换来"确定已落盘"这个
        // 更强的保证，这里选择保守。
        userDefaults.synchronize()
    }

    public static func clear(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: userDefaultsKey)
        userDefaults.synchronize()
    }

    /// 空字符串按"未设置"处理（和 `nil` 同等对待）——防御性地对齐 Settings UI 里"不允许保存空
    /// endpoint"的输入校验，即便未来出现绕过校验的写入路径，读取侧也不会把空字符串当成一个
    /// "已保存"的有效来源。
    public static func load(userDefaults: UserDefaults = .standard) -> String? {
        guard let value = userDefaults.string(forKey: userDefaultsKey), !value.isEmpty else { return nil }
        return value
    }
}

extension KernelShellConfig {
    /// endpoint 精度链的级联实现——**rounds/0019 评审 Q3 修复**。
    ///
    /// 修前的 bug：`source` 在"env 变量存在"这个条件一确认就立刻赋值成 `.environmentVariable`，
    /// 早于"这个 env 值到底是不是合法 URL"的判断。后果：env 设了一个非法 URL（如
    /// `"ht!tp://"`）时，生效的 `endpointURL` 会跳过已保存设置、直接落到内建默认值，但
    /// `endpointSource` 仍然错误地报告 `.environmentVariable`——`SettingsView` 会显示"生效值来自
    /// 环境变量"，而真正生效的其实是内建默认值（如果同时存在一个合法的已保存设置，那条设置会被
    /// 无声跳过，更糟：用户以为自己保存的 endpoint 生效了，其实一直在用别的值）。这正是任务书
    /// 硬约束③要防的"只做优先级不显示来源"的加强版——显示一个**错误**的来源比完全不显示更糟，
    /// 因为它把用户导向错误的排查方向。
    ///
    /// 修法：改成显式级联——每一级只有在**能产出一个合法值**时才 `return`（此时 source 与 value
    /// 在同一处一起确定，不可能不一致）；不合法/缺失只追加告警、继续尝试下一级，从不提前假设
    /// "这一级存在就等于这一级会被采用"。
    private static func resolveEndpointCascade(
        environment: [String: String], userDefaults: UserDefaults, warnings: inout [String]
    ) -> (url: URL, source: KernelConfigValueSource) {
        if let envURLString = environment["AGENT_SHELL_KERNEL_URL"] {
            if let url = URL(string: envURLString) {
                return (url, .environmentVariable)
            }
            // 不假设接下来会落到哪一级——已保存设置可能是合法的，源标注要等实际选中的那一级才赋值。
            warnings.append(
                "AGENT_SHELL_KERNEL_URL 不是合法 URL（\(envURLString)），已忽略并继续按精度链尝试已保存设置/内建默认值"
            )
        }
        if let storedURLString = KernelEndpointDefaultsStore.load(userDefaults: userDefaults) {
            if let url = URL(string: storedURLString) {
                return (url, .savedSetting)
            }
            // 正常 Settings UI 写入前会校验 URL 合法性，这里不该发生；防御性覆盖仍然给出明确警示，
            // 而不是让一条脏数据卡死连接（呼应 SessionPersistenceStore.load() "坏数据不得永久卡死
            // 壳"的同一条项目级原则）。已保存设置是级联的最后一级之前那一级，这里下一步确定会落到
            // 内建默认值，可以明确说"回退到默认值"。
            warnings.append(
                "已保存的 endpoint 设置不是合法 URL（\(storedURLString)），已忽略并回退到默认值 \(defaultEndpointString)"
            )
        }
        return (URL(string: defaultEndpointString)!, .builtInDefault)
    }

    /// Settings UI 的生效值解析入口——**env > 已保存设置 > 内建默认值**。`AgentShellApp.swift`
    /// 用它（不是 `fromEnvironment()`）构造壳启动时的 `SessionStore`；`fromEnvironment()` 本身
    /// 保持"只读环境变量、不知道 UserDefaults/Keychain 存在"的原始行为完全不变（任务书硬要求：
    /// env 变量已设置时 `fromEnvironment()` 的行为不得有任何变化）——两个函数并存、互不调用、
    /// 互不影响，`resolved()` 是新增的更完整入口，不是 `fromEnvironment()` 的替换实现。
    ///
    /// 三个参数均可注入（`environment`/`userDefaults`/`tokenKeychain`）——不是生产代码需要换
    /// 实现，是让 `frame-replay-tests` 能在不碰真实进程环境变量、不碰开发者机器真实
    /// UserDefaults/登录钥匙串的前提下，驱动 env×已保存设置×默认值的全部精度组合并保持测试互相
    /// 隔离（同 `SessionPersistenceStore.directoryOverride`/`KernelTokenKeychainStore.service`
    /// 的隔离哲学）。
    public static func resolved(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard,
        tokenKeychain: KernelTokenKeychainStore = KernelTokenKeychainStore()
    ) -> KernelShellConfig {
        var warnings: [String] = []

        // ---- endpoint：env > 已保存设置 > 内建默认值 ----
        let (endpointURL, endpointSource) = resolveEndpointCascade(
            environment: environment, userDefaults: userDefaults, warnings: &warnings
        )

        // ---- token：env > 已保存设置（Keychain） > 内建默认值 ----
        let token: String
        let tokenSource: KernelConfigValueSource
        if let envToken = environment["AGENT_SHELL_KERNEL_TOKEN"] {
            token = envToken
            tokenSource = .environmentVariable
        } else {
            do {
                if let stored = try tokenKeychain.read(), !stored.isEmpty {
                    token = stored
                    tokenSource = .savedSetting
                } else {
                    token = defaultToken
                    tokenSource = .builtInDefault
                }
            } catch {
                // Keychain 读取失败（不是"没找到"，是真错误——比如 ad-hoc 签名跨构建身份漂移
                // 导致访问被拒）：不让这个错误直接掀翻整个 app 的启动路径，回退到占位符，但通过
                // 既有的 configWarning 通道把原因带到侧栏——这正是任务书"surface Keychain errors
                // to the UI rather than silently swallowing them"在启动路径上的落地方式。
                token = defaultToken
                tokenSource = .builtInDefault
                warnings.append("读取已保存 token 失败，已回退到内建占位符：\(error)")
            }
        }

        return KernelShellConfig(
            endpoint: endpointURL,
            token: token,
            configWarning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"),
            endpointSource: endpointSource,
            tokenSource: tokenSource
        )
    }

    /// token 是否仍是内建占位符（`defaultToken` 字面量）——精确匹配这一个已知字符串，不是"token
    /// 看起来是否可疑"的通用启发式（空字符串等其它"看起来也不像真 token"的取值不在这个判据的
    /// 覆盖范围内，正常解析链路本就不会产出空字符串 token，见 `resolved()` 对空 Keychain 值的
    /// 处理）。Settings 面板与侧栏据此判断要不要展示"请配置 token"提示。
    public var isTokenPlaceholder: Bool { token == Self.defaultToken }
}
