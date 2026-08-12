// rounds/0014 A 块：会话清单持久化——mac 壳重启后从磁盘找回"自己创建过哪些会话"。
//
// 这不是消息内容的持久化（消息文本从不写到这个文件里，见下方 `PersistedSession` 文档注释）——
// 只是"曾经存在过这些会话，它们的 openclaw 寻址方式是什么"这一份最小清单。消息历史的回填走另一条
// 独立通路（`SessionHistoryProviding.fetchFullHistory`，见 KernelClient.swift 与
// SessionStore.swift 恢复流程的文档注释），两者刻意不耦合：清单持久化失败不影响历史回填，历史回填
// 失败也不影响清单本身仍然可用（下次仍能凭清单里的 kernelKey 重新拉一次）。
//
// 任务书对这一块的两条硬约束：
//   1. 落点自定，但必须可删除/重置，坏数据不得永久卡死壳——`load()` 对任何读取失败/JSON
//      解析失败/schema 不匹配都返回空数组，绝不 crash、绝不 throw；`reset()` 提供显式清除。
//   2. 绝不落任何凭证——本类型持久化的字段（`SessionHandle`、kernelKey、title、createdAt）都不是
//      endpoint/token，这两者继续只从环境变量读（见 KernelShellConfig.fromEnvironment()）。
//      `SessionHandle.billing.tokenRef` 在当前 SG-4 实现里恒为占位字符串
//      "TODO-sg4-no-newapi-token-minted"（OpenclawGatewayKernelClient.createSession() 已有注释
//      坐实，未接入真实 newapi 铸造），不是真凭证——但如实记录这一点，以防未来它开始携带敏感值时，
//      这里成为一个容易被忽略的泄漏点（见根 CLAUDE.md 凭证守门纪律）。

import Foundation
import D2Generated

/// 磁盘上持久化的单条会话记录——`SessionStore` 找回一个会话、让它重新可用所需的最小字段集合。
///
/// 刻意**不包含** `messages: [ChatMessage]`——消息内容从不写进这个文件。两个理由：(a) 会制造第二个
/// 会漂移的事实来源（真正的历史在内核 transcript 里，见 `SessionHistoryProviding`）；(b) 任务书把
/// "消息历史恢复"单独列为 C 块、要求走 `chat.history`/HTTP history 通路而不是本地缓存，说明这本来
/// 就该是权威来源现查，不是本地副本。
public struct PersistedSession: Codable {
    /// D1 §2.1 `createSession()` 的返回值（app/generated/swift/D2.swift:3842，已经是 `Codable`）——
    /// `sessionID` 是 UI 层 `ChatSessionViewModel.id` 的来源，`kernelSessionID`
    /// （**不是**下面的 `kernelKey`，两者是 openclaw 侧两个独立字段，见
    /// OpenclawGatewayKernelClient.createSession() 文档注释）随手一起存好，不额外处理。
    public let handle: SessionHandle
    /// openclaw 原生 `key`——`OpenclawGatewayKernelClient.kernelKeyBySessionID` 那张适配器私有映射表
    /// 重启即丢的字段（见 rounds/0014 任务书证据表倒数第三行）。没有它，`send()`/`stop()`/
    /// `fetchFullHistory()` 全部无法为这个会话工作——这是本记录里最不可或缺的一个字段。
    public let kernelKey: String
    public var title: String
    public let createdAt: Date

    public init(handle: SessionHandle, kernelKey: String, title: String, createdAt: Date) {
        self.handle = handle
        self.kernelKey = kernelKey
        self.title = title
        self.createdAt = createdAt
    }
}

/// 磁盘上的顶层持久化形状——数组外包一层版本号，预留未来 schema 演进的余地（本轮 `version` 只写不
/// 读，不做任何按版本分支的迁移逻辑；解码失败一律统一走 `load()` 的"忽略、回退空列表"路径，不区分
/// "版本不认识"与"格式彻底损坏"，两者对调用方而言是同一个"这份数据不可信"结论）。
private struct PersistedSessionFile: Codable {
    var version: Int = 1
    var sessions: [PersistedSession]
}

/// 会话清单持久化的读写入口。
///
/// 落点默认在 `~/Library/Application Support/<bundle id>/sessions.json`；可用
/// `AGENT_SHELL_STATE_DIR` 环境变量整体覆盖（风格同 `KernelShellConfig` 的
/// `AGENT_SHELL_KERNEL_URL`/`AGENT_SHELL_KERNEL_TOKEN`）——测试与破坏性反证据此指向临时目录，不触碰
/// 开发者机器上真实的 Application Support 目录。
public struct SessionPersistenceStore {
    /// 与 `app/apps/AgentShell/Resources/Info.plist` 的 `CFBundleIdentifier` 保持一致的字面量，而
    /// 不是运行时读 `Bundle.main.bundleIdentifier`——本轮 L1 壳既可能以裸 SwiftPM 可执行文件运行
    /// （`swift run`/`.build/debug/AgentShell`），也可能以 `build-app-bundle.sh` 拼出的 `.app`
    /// 运行，前者 `Bundle.main.bundleIdentifier` 多半是 nil（没有真正的 bundle），用字面量保证两种
    /// 运行方式落到同一个目录，行为确定、不随启动方式漂移。
    public static let bundleIdentifier = "dev.test-harnessloop.agent-shell"

    public let fileURL: URL

    /// - Parameter directoryOverride: 显式指定持久化目录（测试/破坏性反证用）。为 `nil` 时依次尝试
    ///   `AGENT_SHELL_STATE_DIR` 环境变量、再回退到标准 Application Support 路径。
    public init(directoryOverride: URL? = nil) {
        let baseDir: URL
        if let directoryOverride {
            baseDir = directoryOverride
        } else if let envPath = ProcessInfo.processInfo.environment["AGENT_SHELL_STATE_DIR"], !envPath.isEmpty {
            baseDir = URL(fileURLWithPath: envPath, isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            baseDir = appSupport.appendingPathComponent(Self.bundleIdentifier, isDirectory: true)
        }
        self.fileURL = baseDir.appendingPathComponent("sessions.json", isDirectory: false)
    }

    /// 读取持久化的会话清单。**任何**失败——文件不存在、读取权限错误、JSON 语法错误、JSON 形状与
    /// `PersistedSessionFile` 不匹配——都返回空数组，绝不 `throw`、绝不崩溃（任务书反证1的硬要求：
    /// 坏数据不得永久卡死壳，壳应回到空列表并可继续新建会话）。失败原因写一行到 stderr 供人工诊断，
    /// 不静默吞掉——但绝不把这行诊断信息升级成异常。
    public func load() -> [PersistedSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let file = try Self.makeDecoder().decode(PersistedSessionFile.self, from: data)
            return file.sessions
        } catch {
            let message = "[AgentShellCore] 会话清单解析失败，已忽略并回退到空列表（不影响继续新建会话）：" +
                "\(fileURL.path) — \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return []
        }
    }

    /// 覆盖写入完整的会话清单（不是增量 append——调用方每次传入当前完整的内存态列表）。写入用
    /// `.atomic`，避免进程在写一半时被杀掉留下截断的半份 JSON（那本身也会被下一次 `load()` 当成
    /// "解析失败"安全忽略，但用 atomic 写更直接地避免制造这种情况）。写入失败（磁盘满/权限问题等）
    /// 只记录到 stderr、不抛错——持久化是尽力而为的增强，不是当前这次操作的关键路径，写失败不应该
    /// 打断用户正在做的事（比如新建会话本身仍然成功，只是这次没能记到磁盘上）。
    public func save(_ sessions: [PersistedSession]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let file = PersistedSessionFile(sessions: sessions)
            let data = try Self.makeEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            let message = "[AgentShellCore] 会话清单持久化写入失败（已忽略，不影响当前会话继续使用）：" +
                "\(fileURL.path) — \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    /// 显式重置——删除持久化文件本身。任务书"必须可删除/重置"的字面实现；文件本不存在时静默成功
    /// （`try?`），不是错误。
    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 独立的 encoder/decoder 工厂（不复用 D2Generated 内部的 `newJSONEncoder()`/`newJSONDecoder()`
    /// ——那两个是 `internal`，`AgentShellCore` 普通 `import D2Generated` 看不到，只有
    /// `@testable import` 才能看到，生产代码不应该依赖测试专用的可见性放宽）。`.iso8601` 日期策略
    /// 与 D2Generated 那一对保持一致的编码约定，确保内嵌的 `SessionHandle.createdAt`/本类型自己的
    /// `createdAt` 往返一致；`.sortedKeys` 只是让磁盘文件人类可读、便于本轮破坏性反证手工验伤。
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
