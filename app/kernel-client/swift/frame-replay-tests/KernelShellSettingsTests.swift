// Settings UI（endpoint/token 精度链 + Keychain/UserDefaults 存储层 + SessionStore.reconnect）
// 的入库回归测试。
//
// 隔离哲学与 SessionPersistenceTests.swift/SessionStoreGroupingTests.swift 完全一致："每个测试用
// 独立的临时命名空间，互不干扰，也绝不触碰开发者机器上真实的持久化状态"——只是这里除了
// `SessionPersistenceStore.directoryOverride`（文件系统维度）之外，还多了两个新维度：
//   - `KernelTokenKeychainStore.service`（Keychain 没有"临时目录"概念，用按 UUID 隔离的独立
//     service 名字代替，测试结束 `defer` 删除）；
//   - `UserDefaults(suiteName:)`（独立 suite，测试结束 `defer` 用
//     `removePersistentDomain(forName:)` 按**创建时记下的 suite 名字字符串**整体清除——**实测
//     坐实**：`UserDefaults.description` 不是 suite 名字（只是默认的 NSObject 地址描述），拿它当
//     key 传给 `removePersistentDomain` 不会清掉任何东西；必须自己把 suite 名字字符串留一份）。
// `KernelShellConfig.resolved(environment:userDefaults:tokenKeychain:)` 的三个参数正是为了让这种
// 隔离测试成为可能而设计（见该函数文档注释）。

import Foundation
@testable import AgentShellCore

// MARK: - 测试专用隔离小工具

private func freshSettingsTestKeychain(_ label: String) -> KernelTokenKeychainStore {
    KernelTokenKeychainStore(
        service: "dev.test-harnessloop.agent-shell.settings-tests.\(label).\(UUID().uuidString)",
        account: "kernel-token"
    )
}

/// 返回 suite 名字字符串本身（不是已经构造好的 `UserDefaults`）——调用方必须自己留着这个字符串
/// 用于 `defer` 清理，理由见本文件头注释。
private func freshSettingsSuiteName(_ label: String) -> String {
    "agent-shell-settings-tests-\(label)-\(UUID().uuidString)"
}

// MARK: - endpoint 精度链：env > 已保存设置 > 内建默认值

/// env 设置时必须赢——即便 UserDefaults 里也保存了一个不同的值。这是「env beats stored」这一半
/// 精度链的直接证据（后面的破坏性反证会针对性地把这条断言打红）。
func testResolvedEndpointPrefersEnvironmentOverStoredAndDefault() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 endpoint 精度——env 设置时优先于已保存设置与内建默认值"
    let suiteName = freshSettingsSuiteName("endpoint-env-wins")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    KernelEndpointDefaultsStore.save("ws://stored-should-lose:2222", userDefaults: defaults)

    let config = KernelShellConfig.resolved(
        environment: ["AGENT_SHELL_KERNEL_URL": "ws://env-should-win:1111"],
        userDefaults: defaults,
        tokenKeychain: freshSettingsTestKeychain("endpoint-env-wins-token")
    )

    guard config.endpoint.absoluteString == "ws://env-should-win:1111" else {
        return fail(name, "expected endpoint to be the env value, got \(config.endpoint.absoluteString)")
    }
    guard config.endpointSource == .environmentVariable else {
        return fail(name, "expected endpointSource == .environmentVariable, got \(config.endpointSource)")
    }
    return pass(name, "env 值 ws://env-should-win:1111 生效，source=.environmentVariable（已保存设置 ws://stored-should-lose:2222 被正确忽略）")
}

/// env 未设置时，已保存设置必须赢过内建默认值。
func testResolvedEndpointPrefersStoredOverDefaultWhenEnvAbsent() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 endpoint 精度——env 未设置时已保存设置优先于内建默认值"
    let suiteName = freshSettingsSuiteName("endpoint-stored-wins")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    KernelEndpointDefaultsStore.save("ws://stored-should-win:3333", userDefaults: defaults)

    let config = KernelShellConfig.resolved(
        environment: [:],
        userDefaults: defaults,
        tokenKeychain: freshSettingsTestKeychain("endpoint-stored-wins-token")
    )

    guard config.endpoint.absoluteString == "ws://stored-should-win:3333" else {
        return fail(name, "expected endpoint to be the stored value, got \(config.endpoint.absoluteString)")
    }
    guard config.endpointSource == .savedSetting else {
        return fail(name, "expected endpointSource == .savedSetting, got \(config.endpointSource)")
    }
    return pass(name, "已保存设置 ws://stored-should-win:3333 生效，source=.savedSetting")
}

/// 两者都未设置时回退到内建默认值——default 生效值与 `KernelShellConfig.defaultEndpointString`
/// 字面量一致（间接验证：resolved() 与 fromEnvironment() 共享同一个默认值常量，不会各自漂出两个
/// "默认值"）。
func testResolvedEndpointFallsBackToBuiltInDefaultWhenNothingSet() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 endpoint 精度——env 与已保存设置均缺席时回退到内建默认值"
    let suiteName = freshSettingsSuiteName("endpoint-default-wins")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let config = KernelShellConfig.resolved(
        environment: [:],
        userDefaults: defaults,
        tokenKeychain: freshSettingsTestKeychain("endpoint-default-wins-token")
    )

    guard config.endpoint.absoluteString == "ws://127.0.0.1:18889" else {
        return fail(name, "expected built-in default endpoint, got \(config.endpoint.absoluteString)")
    }
    guard config.endpointSource == .builtInDefault else {
        return fail(name, "expected endpointSource == .builtInDefault, got \(config.endpointSource)")
    }
    return pass(name, "回退到内建默认值 ws://127.0.0.1:18889，source=.builtInDefault")
}

// MARK: - endpoint 精度链的级联行为（rounds/0019 评审 Q3）——env 存在但非法时必须级联，
// 且 source 必须反映"实际生效的是哪一级"，不能继续声称是环境变量

/// **评审给出的直接复现构造**：`env URL = "ht!tp://"`（语法非法，`URL(string:)` 在本机 Foundation
/// 上返回 nil——见 KernelShellSettingsTests 里 `testFromEnvironmentBehaviorUnchangedForInvalidURLWarningPath`
/// 同一个非法值的实测记录）、同时存在一个合法的已保存设置。修前的 bug：`endpointSource` 在看到
/// env 变量"存在"这个事实时就提前赋值成 `.environmentVariable`，而实际生效的 `endpointURL` 会跳过
/// 已保存设置、直接落到内建默认值——于是 `SettingsView` 会显示"生效值来自环境变量"，但真正在生效
/// 的其实是内建默认值，已保存的设置被无声跳过。这条测试钉住修复后的正确行为：env 非法时应该
/// **继续按精度链尝试下一级（已保存设置）**，且 `endpointSource` 必须等于实际选中的那一级。
func testResolvedEndpointCascadesToStoredSettingWhenEnvURLIsInvalid() -> Bool {
    let name = "rounds/0019 评审 Q3: env URL 非法但存在已保存设置时，resolved() 必须级联采用已保存设置，且 endpointSource 必须如实标注 .savedSetting（不能继续谎称 .environmentVariable）"
    let suiteName = freshSettingsSuiteName("endpoint-invalid-env-cascades-to-stored")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    KernelEndpointDefaultsStore.save("ws://saved.example:18889", userDefaults: defaults)

    let config = KernelShellConfig.resolved(
        environment: ["AGENT_SHELL_KERNEL_URL": "ht!tp://"],
        userDefaults: defaults,
        tokenKeychain: freshSettingsTestKeychain("endpoint-invalid-env-cascades-to-stored-token")
    )

    guard config.endpoint.absoluteString == "ws://saved.example:18889" else {
        return fail(name, "expected the cascade to fall through to the saved setting 'ws://saved.example:18889', got \(config.endpoint.absoluteString) — env being invalid must not silently strand the resolution at the built-in default while skipping a valid saved setting")
    }
    guard config.endpointSource == .savedSetting else {
        return fail(name, "expected endpointSource == .savedSetting (reflecting the value actually in effect), got \(config.endpointSource) — a source label that still claims .environmentVariable here is exactly the 'lying source label' defect: it points the user at the wrong place to fix things")
    }
    guard let warning = config.configWarning, warning.contains("AGENT_SHELL_KERNEL_URL") else {
        return fail(name, "expected configWarning to mention the invalid AGENT_SHELL_KERNEL_URL value so the user still learns their env var is broken, got \(config.configWarning ?? "nil")")
    }
    return pass(name, "env URL 'ht!tp://' 非法，正确级联到已保存设置 'ws://saved.example:18889'，source=.savedSetting（未继续谎称来自环境变量），且 configWarning 仍提示了 env 值非法：\(warning)")
}

/// 同一构造再往下一级：env 非法、且没有已保存设置——必须落到内建默认值，source 才应该是
/// `.builtInDefault`（这个分支在修前代码里巧合地已经"正确"，因为它本来就是级联的终点；这里补
/// 测试是为了让 env-非法 这一整条精度矩阵有完整覆盖，不只覆盖评审点名的那一格）。
func testResolvedEndpointFallsBackToDefaultWhenEnvURLIsInvalidAndNoStoredValue() -> Bool {
    let name = "rounds/0019 评审 Q3 补充: env URL 非法且没有已保存设置时，resolved() 级联到内建默认值，source=.builtInDefault"
    let suiteName = freshSettingsSuiteName("endpoint-invalid-env-no-stored")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let config = KernelShellConfig.resolved(
        environment: ["AGENT_SHELL_KERNEL_URL": "ht!tp://"],
        userDefaults: defaults,
        tokenKeychain: freshSettingsTestKeychain("endpoint-invalid-env-no-stored-token")
    )

    guard config.endpoint.absoluteString == "ws://127.0.0.1:18889" else {
        return fail(name, "expected the cascade to bottom out at the built-in default, got \(config.endpoint.absoluteString)")
    }
    guard config.endpointSource == .builtInDefault else {
        return fail(name, "expected endpointSource == .builtInDefault, got \(config.endpointSource)")
    }
    guard let warning = config.configWarning, warning.contains("AGENT_SHELL_KERNEL_URL") else {
        return fail(name, "expected configWarning to mention the invalid env value, got \(config.configWarning ?? "nil")")
    }
    return pass(name, "env URL 非法且无已保存设置，正确落到内建默认值 ws://127.0.0.1:18889，source=.builtInDefault，且 configWarning 提示了 env 值非法：\(warning)")
}

// MARK: - token 精度链：env > 已保存设置（Keychain） > 内建默认值

func testResolvedTokenPrefersEnvironmentOverStoredAndDefault() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 token 精度——env 设置时优先于 Keychain 已保存设置与内建默认值"
    let keychain = freshSettingsTestKeychain("token-env-wins")
    defer { try? keychain.delete() }
    // **rounds/0019 评审 Q2 修复**：修前这里是裸 `try? keychain.save(...)`，吞掉了失败——如果
    // Keychain 在跑测试的环境里不可写（比如受限 CI 沙箱），这一行悄悄失败，Keychain 里其实**没有**
    // 任何"应该被 env 压过去"的竞争值。而下面的断言只检查 `config.token == "env-token-should-win"`
    // ——env 设置时 `resolved()` 的 endpoint 逻辑压根不会碰 Keychain（见 resolved()：env 分支直接
    // return，Keychain 读取代码根本不会执行），所以这条断言在"根本没有竞争值"的情况下**照样会通过
    // **——测试是绿的，但它声称要验证的"env 真的赢过一个已存在的竞争值"这件事一次都没被验到，是一
    // 次空过（这与本项目一直在修的"守卫看起来在检查、其实什么都没检查"同一族）。
    //
    // 修法：预置后立即读回校验，读不到就说明预置本身失败（环境限制，不是被测代码的 bug），此时
    // 让测试**明确失败**并说明原因——不能吞掉继续往下走、也不能假装什么都没发生地悄悄通过。选择
    // "失败"而不是"跳过"：这个测试文件用的 `pass`/`fail` 返回 `Bool`、由 `runFrameReplayTests()`
    // 直接累计总数，没有第三种"跳过"状态可用；引入一种不进入最终 PASS/FAIL 计数的"跳过"会让
    // `真实通过数量/tests.count` 这个契约本身变得含糊，所以复用既有的 `fail` 通道，把"环境限制"
    // 与"真正的断言不符"用不同的措辞区分开，而不是新增一种此文件此前不存在的返回状态。
    guard (try? keychain.save(token: "stored-token-should-lose")) != nil,
          (try? keychain.read()) == "stored-token-should-lose"
    else {
        return fail(name, "precondition failed: could not seed a competing Keychain value in this environment (Keychain may not be writable here) — cannot verify env-over-stored precedence without a real competing value to lose against")
    }
    let suiteName = freshSettingsSuiteName("token-env-wins-defaults")
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let config = KernelShellConfig.resolved(
        environment: ["AGENT_SHELL_KERNEL_TOKEN": "env-token-should-win"],
        userDefaults: UserDefaults(suiteName: suiteName)!,
        tokenKeychain: keychain
    )

    guard config.token == "env-token-should-win" else {
        return fail(name, "expected token to be the env value, got \(config.token)")
    }
    guard config.tokenSource == .environmentVariable else {
        return fail(name, "expected tokenSource == .environmentVariable, got \(config.tokenSource)")
    }
    return pass(name, "env token 'env-token-should-win' 生效，source=.environmentVariable（Keychain 中的 'stored-token-should-lose' 被正确忽略）")
}

func testResolvedTokenPrefersStoredOverDefaultWhenEnvAbsent() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 token 精度——env 未设置时 Keychain 已保存设置优先于内建默认值"
    let keychain = freshSettingsTestKeychain("token-stored-wins")
    defer { try? keychain.delete() }
    // 同 testResolvedTokenPrefersEnvironmentOverStoredAndDefault 的 Q2 修复理由——这条测试的主
    // 断言（`config.token == "stored-token-should-win"`）本身在预置失败时会正确变红（不是空过：
    // env 缺席时 resolved() 确实会去读 Keychain，读不到就落到内建占位符，与期望值不符），但仍然
    // 加同一道precondition 检查，让"环境限制导致预置失败"与"精度链逻辑真的有 bug"在失败信息里
    // 一眼可辨，不必让人去猜一条"expected X got 内建占位符"的断言失败到底是哪一种原因。
    guard (try? keychain.save(token: "stored-token-should-win")) != nil,
          (try? keychain.read()) == "stored-token-should-win"
    else {
        return fail(name, "precondition failed: could not seed the Keychain value in this environment (Keychain may not be writable here) — cannot verify stored-over-default precedence without a real stored value")
    }
    let suiteName = freshSettingsSuiteName("token-stored-wins-defaults")
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let config = KernelShellConfig.resolved(
        environment: [:],
        userDefaults: UserDefaults(suiteName: suiteName)!,
        tokenKeychain: keychain
    )

    guard config.token == "stored-token-should-win" else {
        return fail(name, "expected token to be the Keychain-stored value, got \(config.token)")
    }
    guard config.tokenSource == .savedSetting else {
        return fail(name, "expected tokenSource == .savedSetting, got \(config.tokenSource)")
    }
    return pass(name, "Keychain 已保存 token 'stored-token-should-win' 生效，source=.savedSetting")
}

func testResolvedTokenFallsBackToBuiltInDefaultWhenNothingSet() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 token 精度——env 与 Keychain 均缺席时回退到内建占位符默认值"
    let keychain = freshSettingsTestKeychain("token-default-wins")
    defer { try? keychain.delete() }
    let suiteName = freshSettingsSuiteName("token-default-wins-defaults")
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let config = KernelShellConfig.resolved(
        environment: [:],
        userDefaults: UserDefaults(suiteName: suiteName)!,
        tokenKeychain: keychain
    )

    guard config.token == "agentshell-local-placeholder-token" else {
        return fail(name, "expected built-in placeholder token, got \(config.token)")
    }
    guard config.tokenSource == .builtInDefault else {
        return fail(name, "expected tokenSource == .builtInDefault, got \(config.tokenSource)")
    }
    guard config.isTokenPlaceholder else {
        return fail(name, "expected isTokenPlaceholder == true for the built-in default token")
    }
    return pass(name, "回退到内建占位符 token，source=.builtInDefault，isTokenPlaceholder=true")
}

/// **独立性检验**：endpoint 走已保存设置、token 走 env——防止一个字段的解析逻辑意外"抄"了另一个
/// 字段的分支（比如复制粘贴时改错了变量名，导致两个字段实际上被同一个条件耦合在一起）。
func testEndpointAndTokenSourcesResolveIndependently() -> Bool {
    let name = "Settings UI: KernelShellConfig.resolved() 的 endpoint/token 精度链彼此独立解析（一个来自已保存设置、另一个来自 env，互不影响）"
    let suiteName = freshSettingsSuiteName("independent-resolution")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    KernelEndpointDefaultsStore.save("ws://only-endpoint-is-stored:4444", userDefaults: defaults)
    let keychain = freshSettingsTestKeychain("independent-resolution-token")
    defer { try? keychain.delete() }
    // 故意不往 Keychain 里存任何东西——token 只靠 env 提供。

    let config = KernelShellConfig.resolved(
        environment: ["AGENT_SHELL_KERNEL_TOKEN": "only-token-is-env"],
        userDefaults: defaults,
        tokenKeychain: keychain
    )

    guard config.endpoint.absoluteString == "ws://only-endpoint-is-stored:4444", config.endpointSource == .savedSetting else {
        return fail(name, "expected endpoint from saved setting, got value=\(config.endpoint.absoluteString) source=\(config.endpointSource)")
    }
    guard config.token == "only-token-is-env", config.tokenSource == .environmentVariable else {
        return fail(name, "expected token from env, got value=\(config.token) source=\(config.tokenSource)")
    }
    return pass(name, "endpoint 独立地从已保存设置解析（ws://only-endpoint-is-stored:4444），token 独立地从 env 解析（only-token-is-env），两者互不干扰")
}

// MARK: - 占位符判定谓词

func testIsTokenPlaceholderTrueForDefaultTokenAndFalseForRealToken() -> Bool {
    let name = "Settings UI: KernelShellConfig.isTokenPlaceholder 精确匹配内建占位符字符串，真实 token 与空字符串均判 false"
    let placeholderConfig = KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!, token: "agentshell-local-placeholder-token", configWarning: nil
    )
    guard placeholderConfig.isTokenPlaceholder else {
        return fail(name, "expected isTokenPlaceholder == true for the literal default token string")
    }

    let realConfig = KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!, token: "sk-EXAMPLE-not-a-real-token-abc123", configWarning: nil
    )
    guard !realConfig.isTokenPlaceholder else {
        return fail(name, "expected isTokenPlaceholder == false for a real-looking token")
    }

    // 空字符串不是占位符字符串本身——精确匹配谓词如实报告 false，不做"看起来也不像真 token"的
    // 额外启发式判断（这是本谓词的既定 scope 边界，见 KernelShellSettingsStorage.swift 该属性的
    // 文档注释；resolved() 的正常解析链路本就不会产出空字符串 token，见该函数对空 Keychain 值的
    // 处理）。
    let emptyConfig = KernelShellConfig(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "", configWarning: nil)
    guard !emptyConfig.isTokenPlaceholder else {
        return fail(name, "expected isTokenPlaceholder == false for an empty string (documented scope boundary)")
    }

    return pass(name, "占位符字面量 -> true；真实 token 'sk-EXAMPLE-not-a-real-token-abc123' -> false；空字符串 -> false（既定 scope 边界）")
}

// MARK: - fromEnvironment() 行为未变回归锁

/// **任务书硬要求的直接证据**："KernelShellConfig.fromEnvironment()'s behavior when the env vars
/// are set must not change at all"——这条测试把两个 env 变量都设成自定义值，断言 endpoint/token/
/// configWarning 三个字段与"这两个字段加入 source 标注之前"的历史行为逐字节一致（configWarning
/// 为 nil，token/endpoint 直接取 env 值），只多断言两个新 source 字段确实被正确标成
/// `.environmentVariable`（新增能力，不影响前三者）。
func testFromEnvironmentBehaviorUnchangedWhenBothEnvVarsSet() -> Bool {
    let name = "Settings UI 回归锁: fromEnvironment() 在两个 env 变量都设置时，endpoint/token/configWarning 与加入 source 标注之前逐字节一致"
    // 用真实 setenv/unsetenv（不是 resolved() 的可注入 environment 参数——fromEnvironment() 本身
    // 一直读的就是 ProcessInfo.processInfo.environment，要测它就必须测这条真实路径）。
    setenv("AGENT_SHELL_KERNEL_URL", "ws://regression-lock-host:9999", 1)
    setenv("AGENT_SHELL_KERNEL_TOKEN", "regression-lock-token", 1)
    defer {
        unsetenv("AGENT_SHELL_KERNEL_URL")
        unsetenv("AGENT_SHELL_KERNEL_TOKEN")
    }

    let config = KernelShellConfig.fromEnvironment()

    guard config.endpoint.absoluteString == "ws://regression-lock-host:9999" else {
        return fail(name, "endpoint changed: got \(config.endpoint.absoluteString)")
    }
    guard config.token == "regression-lock-token" else {
        return fail(name, "token changed: got \(config.token)")
    }
    guard config.configWarning == nil else {
        return fail(name, "configWarning changed: expected nil, got \(config.configWarning ?? "")")
    }
    guard config.endpointSource == .environmentVariable, config.tokenSource == .environmentVariable else {
        return fail(name, "expected both sources == .environmentVariable, got endpoint=\(config.endpointSource) token=\(config.tokenSource)")
    }
    return pass(name, "endpoint/token/configWarning 三个既有字段逐字节未变；新增的两个 source 字段正确标为 .environmentVariable")
}

/// 同上，覆盖"两个 env 变量都未设置"路径——必须仍然回退到原始的内建默认值常量。
func testFromEnvironmentBehaviorUnchangedWhenNeitherEnvVarSet() -> Bool {
    let name = "Settings UI 回归锁: fromEnvironment() 在两个 env 变量都未设置时，回退到与加入 source 标注之前逐字节一致的内建默认值"
    unsetenv("AGENT_SHELL_KERNEL_URL")
    unsetenv("AGENT_SHELL_KERNEL_TOKEN")

    let config = KernelShellConfig.fromEnvironment()

    guard config.endpoint.absoluteString == "ws://127.0.0.1:18889" else {
        return fail(name, "default endpoint changed: got \(config.endpoint.absoluteString)")
    }
    guard config.token == "agentshell-local-placeholder-token" else {
        return fail(name, "default token changed: got \(config.token)")
    }
    guard config.configWarning == nil else {
        return fail(name, "configWarning changed: expected nil, got \(config.configWarning ?? "")")
    }
    guard config.endpointSource == .builtInDefault, config.tokenSource == .builtInDefault else {
        return fail(name, "expected both sources == .builtInDefault, got endpoint=\(config.endpointSource) token=\(config.tokenSource)")
    }
    return pass(name, "回退到内建默认值逐字节未变（ws://127.0.0.1:18889 / agentshell-local-placeholder-token）；新增 source 字段正确标为 .builtInDefault")
}

/// 同上，覆盖 env URL 非法时的告警回退路径——`configWarning` 的具体文案是这条路径里"行为"的一
/// 部分（SessionListView 会把它逐字展示给用户），必须与加入 source 标注之前的原始文案逐字节一致。
func testFromEnvironmentBehaviorUnchangedForInvalidURLWarningPath() -> Bool {
    let name = "Settings UI 回归锁: fromEnvironment() 在 env URL 非法时，configWarning 文案与加入 source 标注之前逐字节一致"
    // **实测选定的非法值**：`URL(string:)` 在本机 Foundation 上比直觉宽松得多——连
    // "not a valid url at all with spaces"、控制字符包裹的字符串都会被解析成功（自动
    // percent-encode），最初选的带 BEL 字符的候选值反而被判定"合法"，让这条测试自己先假绿。用一个
    // 小脚本枚举候选值实测过（`URL(string:)` 空字符串/`"ht!tp://"`/`"ws://\0"`/
    // 一个残缺 IPv6 主机的字符串确认返回 nil），"ht!tp://"——协议名里混入非法字符——被选中：
    // 语义上也贴近"用户手滑打错了协议名"这个真实场景，不是一个刻意构造的边角字符串。
    setenv("AGENT_SHELL_KERNEL_URL", "ht!tp://", 1)
    unsetenv("AGENT_SHELL_KERNEL_TOKEN")
    defer { unsetenv("AGENT_SHELL_KERNEL_URL") }

    let config = KernelShellConfig.fromEnvironment()

    let expectedWarning = "AGENT_SHELL_KERNEL_URL 不是合法 URL（ht!tp://），已回退到 ws://127.0.0.1:18889"
    guard config.configWarning == expectedWarning else {
        return fail(name, "configWarning text changed: expected '\(expectedWarning)', got '\(config.configWarning ?? "nil")'")
    }
    guard config.endpoint.absoluteString == "ws://127.0.0.1:18889" else {
        return fail(name, "fallback endpoint changed: got \(config.endpoint.absoluteString)")
    }
    guard config.token == "agentshell-local-placeholder-token" else {
        return fail(name, "default token changed: got \(config.token)")
    }
    return pass(name, "非法 URL 告警文案逐字节未变：'\(expectedWarning)'")
}

// MARK: - KernelTokenKeychainStore

/// add-vs-update 两段式的直接证据：先 save() 一个值（走 SecItemAdd），再 save() 一个不同的值
/// （必须走 errSecDuplicateItem -> SecItemUpdate 分支，而不是抛错或悄悄失败）。
func testKeychainTokenStoreSavesReadsUpdatesAndDeletes() -> Bool {
    let name = "Settings UI: KernelTokenKeychainStore 完整往返——save（新增）-> read -> save（更新，走 add-vs-update 的 update 分支）-> read -> delete -> read"
    let store = freshSettingsTestKeychain("roundtrip")
    defer { try? store.delete() }

    do {
        try store.save(token: "first-token-value")
        guard try store.read() == "first-token-value" else {
            return fail(name, "expected 'first-token-value' after first save (add path)")
        }

        // 第二次 save()：条目已存在，必须走 update 分支（SecItemAdd 会返回 errSecDuplicateItem）。
        try store.save(token: "second-token-value-after-update")
        guard try store.read() == "second-token-value-after-update" else {
            return fail(name, "expected 'second-token-value-after-update' after second save (update path)")
        }

        try store.delete()
        guard try store.read() == nil else {
            return fail(name, "expected nil after delete()")
        }
    } catch {
        return fail(name, "unexpected throw: \(error)")
    }
    return pass(name, "新增 -> 读回一致 -> 更新（覆盖同一 service/account）-> 读回新值 -> 删除 -> 读回 nil，全部符合预期")
}

func testKeychainTokenStoreReadReturnsNilForNeverUsedServiceAccount() -> Bool {
    let name = "Settings UI: KernelTokenKeychainStore.read() 对从未写过的 service/account 返回 nil（不是抛错）"
    let store = freshSettingsTestKeychain("never-used")
    do {
        guard try store.read() == nil else {
            return fail(name, "expected nil for a never-used service/account")
        }
    } catch {
        return fail(name, "expected no throw, got \(error)")
    }
    return pass(name, "从未写过的 service/account 上 read() 安全返回 nil，未抛错")
}

func testKeychainTokenStoreDeleteIsIdempotentWhenNothingStored() -> Bool {
    let name = "Settings UI: KernelTokenKeychainStore.delete() 在条目本不存在时是幂等的（不抛错）——「清除已保存 token」不应该因为本来就没有条目而向用户报错"
    let store = freshSettingsTestKeychain("idempotent-delete")
    do {
        try store.delete()
        try store.delete()  // 再删一次，必须仍然不抛错
    } catch {
        return fail(name, "expected delete() to be idempotent, got throw \(error)")
    }
    return pass(name, "对不存在的条目连续 delete() 两次均未抛错")
}

// MARK: - KernelEndpointDefaultsStore

func testKernelEndpointDefaultsStoreRoundTripsAndClears() -> Bool {
    let name = "Settings UI: KernelEndpointDefaultsStore save/load/clear 往返正确，且 load() 对从未写过的 suite 返回 nil"
    let suiteName = freshSettingsSuiteName("endpoint-store-roundtrip")
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    guard KernelEndpointDefaultsStore.load(userDefaults: defaults) == nil else {
        return fail(name, "expected nil before any save()")
    }
    KernelEndpointDefaultsStore.save("ws://roundtrip-endpoint:5555", userDefaults: defaults)
    guard KernelEndpointDefaultsStore.load(userDefaults: defaults) == "ws://roundtrip-endpoint:5555" else {
        return fail(name, "expected round-tripped value after save()")
    }
    KernelEndpointDefaultsStore.clear(userDefaults: defaults)
    guard KernelEndpointDefaultsStore.load(userDefaults: defaults) == nil else {
        return fail(name, "expected nil after clear()")
    }
    return pass(name, "save() 前 load()==nil -> save() 后 load() 取回原值 -> clear() 后 load() 再次为 nil")
}

// MARK: - SessionStore.reconnect(with:) —— 「保存并重连」的落地验证

/// `reconnect(with:)` 必须：(a) 用新 config 更新四个展示态属性（effectiveEndpointDisplay/
/// endpointSource/tokenSource/isTokenPlaceholder）；(b) 清空 sessions/selectedSessionID（旧会话
/// 绑定在旧连接上，换目标后不再有效）；(c) 触发一次新的连接尝试（connectionStatus 从初始配置的
/// 状态变成基于新 endpoint 的连接结果，而不是原地不动）。用 `ws://127.0.0.1:1`（该代码库既有测试
/// 里"必然连接失败"的既定用法——见 ApprovalDecisionTests.swift 等既有调用点）保证连接尝试快速失败
/// 而不是挂起，这里只关心状态是否被正确更新，不关心连接是否真的成功。
// `@MainActor`——`SessionStore` 本身是 `@MainActor`（见该类型声明），构造实例、读它的属性都必须
// 在主 actor 上下文里做；同 SessionStoreGroupingTests.swift 里既有测试的写法。
@MainActor
func testSessionStoreReconnectUpdatesDisplayStateAndResetsSessions() async -> Bool {
    let name = "Settings UI: SessionStore.reconnect(with:) 用新 config 更新展示态并清空旧会话列表"
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-shell-settings-reconnect-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let initialConfig = KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:1")!, token: "initial-token", configWarning: nil,
        endpointSource: .builtInDefault, tokenSource: .builtInDefault
    )
    let store = SessionStore(config: initialConfig, persistence: SessionPersistenceStore(directoryOverride: tempDir))

    guard store.effectiveEndpointDisplay == "ws://127.0.0.1:1", store.tokenSource == .builtInDefault else {
        return fail(name, "precondition failed: initial display state not as constructed")
    }

    let newConfig = KernelShellConfig(
        endpoint: URL(string: "ws://127.0.0.1:2")!, token: "reconnected-real-token", configWarning: nil,
        endpointSource: .savedSetting, tokenSource: .savedSetting
    )
    await store.reconnect(with: newConfig)

    guard store.effectiveEndpointDisplay == "ws://127.0.0.1:2" else {
        return fail(name, "expected effectiveEndpointDisplay to update to the new endpoint, got \(store.effectiveEndpointDisplay)")
    }
    guard store.endpointSource == .savedSetting, store.tokenSource == .savedSetting else {
        return fail(name, "expected both sources to update to .savedSetting, got endpoint=\(store.endpointSource) token=\(store.tokenSource)")
    }
    guard !store.isTokenPlaceholder else {
        return fail(name, "expected isTokenPlaceholder == false for 'reconnected-real-token'")
    }
    guard store.sessions.isEmpty, store.selectedSessionID == nil else {
        return fail(name, "expected sessions/selectedSessionID to be cleared after reconnect(), got \(store.sessions.count) sessions, selectedSessionID=\(store.selectedSessionID ?? "nil")")
    }
    // 连接目标是 127.0.0.1:2（无人监听），reconnect() 内部 await 了 connectIfNeeded()，此时应已
    // 观察到一次明确的失败态（不是仍停留在 .connecting，也不是没被触碰过的 .notConnected）。
    guard case .failed = store.connectionStatus else {
        return fail(name, "expected connectionStatus to have reached .failed after reconnect() awaited connectIfNeeded(), got \(store.connectionStatus)")
    }
    return pass(name, "reconnect() 后展示态全部更新为新 config 的值，旧会话列表被清空，connectionStatus 已推进到 .failed（新地址确实连不上，这是预期结果，不是测试环境问题）")
}
