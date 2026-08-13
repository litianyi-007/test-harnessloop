// Settings 面板——⌘, 唤出，标准 macOS `Settings` scene（注册见 AgentShellApp.swift）。
//
// 三条既定决策在这里的落地：
//   1) token 只写 Keychain，永不落 UserDefaults/plist——本文件对 token 字段只调用
//      `KernelTokenKeychainStore`，endpoint 字段只调用 `KernelEndpointDefaultsStore`，两条代码
//      路径物理上分开（见 KernelShellSettingsStorage.swift 的分工注释），方便审计时一眼确认。
//   2) 生效值来源（环境变量/已保存设置/内建默认值）显式展示在两个字段下方，而不是"存起来就当
//      用户看得到"——尤其是来源为环境变量时，额外提示"这里保存的值当前不会生效"，抢在用户困惑
//      之前把原因说清楚。
//   3) 占位符 token 的主动提示在侧栏（SessionListView.tokenPlaceholderHint），本面板只负责
//      "把它换掉"这个动作本身，不重复渲染同一条提示。
//
// 全程不用 `.alert()`/`.sheet()`——沿用本壳一贯的"错误内嵌可见、不模态打断"原则（SessionListView
// 头注释）。

import SwiftUI
import AgentShellCore

/// **rounds/0019 评审 Q4a 修复**：Keychain 读取的三种结果——"确实没保存过"与"读取本身失败"是
/// 两件不同的事，不能像修前那样用 `(try? ...) != nil` 把两者都折叠成同一个 `false`/"未保存"。
/// 读取失败（比如 ad-hoc 签名跨构建身份漂移导致访问被拒）必须能在 UI 上单独显示出来，不能悄悄
/// 冒充成"你从来没存过 token"——那会让用户以为自己需要重新输入，实际上是权限/环境出了问题。
private enum TokenKeychainReadStatus: Equatable {
    case notSaved
    case saved
    case readError(String)
}

struct SettingsView: View {
    @Environment(SessionStore.self) private var store

    @State private var endpointText: String = ""
    @State private var tokenText: String = ""
    @State private var isTokenRevealed = false
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var tokenKeychainStatus: TokenKeychainReadStatus = .notSaved

    var body: some View {
        Form {
            Section {
                TextField("ws://127.0.0.1:18889", text: $endpointText)
                    .textFieldStyle(.roundedBorder)
                sourceCaption(for: store.endpointSource, envVarName: "AGENT_SHELL_KERNEL_URL")
            } header: {
                Text("内核 Endpoint")
            }

            Section {
                HStack {
                    Group {
                        if isTokenRevealed {
                            TextField("输入新 token 以保存…", text: $tokenText)
                        } else {
                            SecureField("输入新 token 以保存…", text: $tokenText)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button {
                        isTokenRevealed.toggle()
                    } label: {
                        Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .help(isTokenRevealed ? "隐藏" : "显示")
                }
                Text(tokenStatusText)
                    .font(.caption)
                    .foregroundStyle(store.isTokenPlaceholder ? .orange : .secondary)
                sourceCaption(for: store.tokenSource, envVarName: "AGENT_SHELL_KERNEL_TOKEN")
                // rounds/0019 评审 Q4a：读取错误单独一行、红色——不与"未保存"共用同一句灰色文字。
                if case .readError(let message) = tokenKeychainStatus {
                    Text("读取 Keychain 中是否已保存 token 时出错：\(message)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Text("留空并保存 = 不修改已保存的 token（不会清空 Keychain 里已有的值）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("清除已保存 token", role: .destructive) {
                        Task { await clearSavedToken() }
                    }
                    // 读取出错时不确定 Keychain 里到底有没有东西——保守地不提供"清除"这个动作
                    // （而不是猜一个默认态），错误本身已经在上面单独展示，用户能看到发生了什么。
                    .disabled(isBusy || tokenKeychainStatus != .saved)
                }
            } header: {
                Text("内核 Token（存入 Keychain，从不写入 UserDefaults/plist）")
            }

            Section {
                HStack(spacing: 8) {
                    Circle().fill(connectionColor).frame(width: 8, height: 8)
                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Button("保存并重连") {
                        Task { await saveAndReconnect() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                }
            }
        }
        .padding(20)
        // 实测确定的最小宽度（rounds/0019 视觉缺陷修复）：macOS `Form` 里 `TextField`/
        // `SecureField` 的 title 参数在 Form 上下文里被渲染成**行首标签**（不是 iOS 风格的内联
        // placeholder）——这是本次裁切 bug 的真实成因，不是"随便一个数字不够宽"。实测二分：
        // 480 裁切（原始 bug，协调者截图坐实）；490 不裁切但贴边贴得很紧（几乎没有安全边际）；
        // 500/540/600/700 均干净、留白正常；完全不加 frame 约束时 Form 自身的自然宽度约
        // 912（见交付报告，`open`+`osascript`+`screencapture` 实拍验证）。560 选在已验证裁切
        // 阈值（490）之上留出约 70px 安全边际，同时明显小于自然宽度（不会反而把这个约束变成"总是
        // 生效的固定宽度"——多数情况下窗口实际渲染宽度仍由内容自身的自然宽度决定，接近 900+，
        // 560 只是防止未来内容变化（文案变短/换语言）导致自然宽度意外收窄到不安全区间的下限保护）。
        //
        // `minWidth`（不是 `width`）：允许窗口比这个值更宽（当前内容本就需要更宽），但绝不会比它
        // 窄——用户也可以手动把窗口拖得更窄，但不会窄过这个不裁切下限。已实测确认 `.frame(minWidth:)`
        // 在 SwiftUI `Settings` scene 上真实生效（不是被系统忽略）：单独把这个值临时设到
        // 1100（明显超过内容自然宽度 912）时，实测窗口确实按 1100 渲染，证明该约束是主动生效的
        // 下限，不是摆设。
        .frame(minWidth: 560)
        .task { refreshFromStore() }
    }

    private var tokenStatusText: String {
        if store.isTokenPlaceholder {
            return "当前生效 token 仍是内建占位符——无法完成真实内核鉴权。"
        }
        // rounds/0019 评审 Q4a：三态分别给出准确的文案——尤其 `.readError` 不能被误说成"未保存"。
        switch tokenKeychainStatus {
        case .saved:
            return "Keychain 中已保存 token（当前生效值并非占位符）。"
        case .notSaved:
            return "当前生效 token 并非占位符（来自环境变量，Keychain 中未保存）。"
        case .readError:
            return "当前生效 token 并非占位符；读取 Keychain 是否已保存 token 时出错，见下方红字。"
        }
    }

    @ViewBuilder
    private func sourceCaption(for source: KernelConfigValueSource, envVarName: String) -> some View {
        switch source {
        case .environmentVariable:
            Text("生效值来自环境变量 \(envVarName)——在此保存的值要等该环境变量被取消设置后才会生效。")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .savedSetting:
            Text("生效值来自已保存的设置。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .builtInDefault:
            Text("生效值为内建默认值（尚未保存过设置）。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionColor: Color {
        switch store.connectionStatus {
        case .notConnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var connectionText: String {
        switch store.connectionStatus {
        case .notConnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected(let scopes): return "已连接（scopes: \(scopes.joined(separator: ", "))）"
        case .failed(let message): return "连接失败：\(message)"
        }
    }

    private func refreshFromStore() {
        endpointText = store.effectiveEndpointDisplay
        // rounds/0019 评审 Q4a 修复：修前 `(try? ...) != nil` 把"读取失败"与"确实没保存过"
        // 折叠成同一个 `false`——这里改成 do/catch，让失败单独进 `.readError`，UI 才能把它显示成
        // 错误而不是误报"未保存"。
        do {
            let value = try KernelTokenKeychainStore().read()
            tokenKeychainStatus = value != nil ? .saved : .notSaved
        } catch {
            tokenKeychainStatus = .readError("\(error)")
        }
    }

    private func saveAndReconnect() async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }

        // rounds/0019 评审 Q4b 修复：Endpoint 写 UserDefaults 与 Token 写 Keychain 是两次独立、
        // 不共享事务的写入——修前如果 Endpoint 先成功、Token 后失败，函数直接 `return`，用户只看到
        // 一句 Keychain 报错，却不知道 Endpoint 那一半其实已经生效了（一条静默的部分成功）。这里
        // 不做跨存储的回滚（Endpoint 已经落盘，撤销它本身又是一次新的写入、可能又失败，反而更复杂
        // 更不可靠）——改成任务书允许的另一条路："明确告诉用户哪一半成了哪一半没成"，用
        // `savedParts` 累积已经成功的部分，失败时把它揉进错误文案里。
        var savedParts: [String] = []

        let trimmedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEndpoint.isEmpty {
            guard URL(string: trimmedEndpoint) != nil else {
                errorMessage = "Endpoint 不是合法 URL：\(trimmedEndpoint)（未保存任何改动）"
                return
            }
            KernelEndpointDefaultsStore.save(trimmedEndpoint)
            savedParts.append("Endpoint")
        }

        let trimmedToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            do {
                try KernelTokenKeychainStore().save(token: trimmedToken)
                tokenText = ""
                savedParts.append("Token")
            } catch {
                // 任务书要求："surface Keychain errors to the UI rather than silently
                // swallowing them"——直接把 KeychainStoreError.description（内含 OSStatus 与系统
                // 错误文案）原样展示，不改写成一句更"友好"但丢信息的通用提示；同时明确交代
                // Endpoint 那一半的真实状态，不留一个用户看不见的部分成功。
                let partialNote = savedParts.isEmpty
                    ? "Token 未保存，其余设置也未受影响。"
                    : "\(savedParts.joined(separator: "、")) 已保存；Token 未保存。"
                errorMessage = "Keychain 保存失败：\(error)（\(partialNote)）"
                return
            }
        }

        let resolved = KernelShellConfig.resolved()
        await store.reconnect(with: resolved)
        refreshFromStore()
        statusMessage = "已保存，正在按新设置重连。"
    }

    private func clearSavedToken() async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            try KernelTokenKeychainStore().delete()
            let resolved = KernelShellConfig.resolved()
            await store.reconnect(with: resolved)
            refreshFromStore()
            statusMessage = "已清除 Keychain 中保存的 token。"
        } catch {
            errorMessage = "清除失败：\(error)"
        }
    }
}
