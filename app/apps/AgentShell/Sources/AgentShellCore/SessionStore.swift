// SG-10 L1 Mac UI 壳的应用状态中枢：持有一个 OpenclawGatewayKernelClient 连接、管理会话列表、
// 把 KernelClient 的 createSession/send/subscribe 适配成 SwiftUI 视图能直接绑定的可观察状态。
//
// 调用顺序照抄 app/kernel-client/swift/CLIRunner.swift 的 runL1CloseLoop()（任务书明确要求
// "照着它的调用序列走，不要自己另发明一套"）：connect() -> createSession() -> subscribe() ->
// send()。唯一的结构性差异：CLIRunner 是"一次性跑完就退出"的 CLI 脚本，用固定的观察窗口
// （几秒钟）后停止收事件；这里是常驻等待用户操作的 UI，没有天然的"该停止观察了"的时间点，所以
// subscribe() 拿到的事件流用一个不主动退出的 Task 持续消费，直到该流自己结束/出错。
//
// rounds/0012 ②（客户端窗口收口，见 evidence/item2-subscribe-race.md「返工结论」+
// OpenclawGatewayKernelClient.subscribe()/send() 文档注释——**本节 2026-08-09 三次返工后订正**：
// 上一版这里写的是"subscribe() 会一直 await 到服务端订阅 RPC 落地才返回，所以服务端订阅必然已经
// 建立"——那是被推翻的行为，`subscribe()` 已经改回 D1 契约要求的立即返回（不等任何 RPC 响应），这句
// 话不再成立，如实订正）：`createNewSession()` 里仍然 `await client.subscribe(...)`，仍然在拿到
// 返回的 `stream` 之后才把这个 session 加进 `sessions` 列表——但这一步现在只是一次几乎不悬挂的本地
// 调用（同步注册本地事件续体后立即返回），它保证的是"session 出现在侧栏、能被点选发送"之前，**本地
// 事件流已经就绪、consumeEvents() 有东西可读**，不是"服务端订阅已经确认"。真正防止 UI 的
// send（点击发送）跑到服务端订阅确认之前的屏障，现在在 `OpenclawGatewayKernelClient.send()` 内部
// （send 侧屏障，等"订阅 RPC 已 dispatch"，完整设计取舍见该方法文档注释）——两层各司其职：这里管
// "UI 何时把会话挂到列表上"，KernelClient 内部管"send 的底层 RPC 何时真正发出"。只有消费事件流本身
// 的 for-try-await 循环（没有天然终点）还留在背景 Task 里，见 createNewSession()/consumeEvents()
// 的文档注释。
//
// L1 明确不调用的三个 TODO 桩方法（interrupt/respondApproval/capabilities）——见
// app/kernel-client/swift/KernelClient.swift 头注释，本壳同样不碰。也不调用 stop()：L1 UI 最低
// 要求里没有"关闭会话"这个动作（stop 按钮明确归 L2），本壳的会话从创建到进程退出都保持开着，这是
// 有意的 scope 决定，不是遗漏——见交付报告"没做完的地方"一节。

import Foundation
import Observation
import D2Generated
import KernelClient

/// **可见性变更（rounds/0013 B2）**：类本身、以及 `AgentShell` 视图层实际调用/读取的成员改为
/// `public`（理由同 ChatModels.swift 头注释）。原有的 `private(set)` 一律保留为
/// `public private(set)`——外部只读、写入仍收在声明处所在文件内，封装边界和拆分前完全一致，只是
/// 加了 `public` 让"只读"这件事本身能跨模块生效。`client`/`consumeEvents`/`appendAssistantDelta`/
/// `connectionStatusSummary`/`describeError` 维持 private/维持现状——`AgentShell` 视图层不触碰，
/// 不放宽。`handle(_:for:)` 单独放宽到 internal（不是 public），理由见该方法自己的文档注释
/// （只为 `@testable import` 服务，`AgentShell` 视图层从不调用它）。
@MainActor
@Observable
public final class SessionStore {
    public private(set) var sessions: [ChatSessionViewModel] = []
    public var selectedSessionID: String?
    public private(set) var connectionStatus: ConnectionStatus = .notConnected
    public private(set) var isCreatingSession = false

    /// 新建会话失败等一次性错误，展示在侧栏底部——非模态：scope-lock 验收要求起窗口验证过程中
    /// 不能弹出任何模态对话框，所以本壳全程不用 .alert()/.sheet()/.confirmationDialog()，一律用
    /// 内嵌文字 + 背景色表达"有错误"，用户可以点掉但它不会自己弹出来挡住界面。
    public var globalErrorMessage: String?

    /// AGENT_SHELL_KERNEL_URL 环境变量若不是合法 URL，在此透传给侧栏展示（见
    /// KernelShellConfig.configWarning 的文档注释）。
    public let configWarning: String?

    private let client: OpenclawGatewayKernelClient

    /// rounds/0014 A 块：会话清单持久化读写入口，默认落 Application Support（见
    /// SessionPersistence.swift 文档注释）。构造器参数带默认值，本轮之前的既有调用点
    /// （`AgentShellApp.swift` 的 `SessionStore(config: .fromEnvironment())`、
    /// `SessionStoreGroupingTests.swift` 的 `SessionStore(config:)`）不需要改一个字符。
    private let persistence: SessionPersistenceStore

    /// sessionID -> openclaw kernelKey，供 A 块持久化用。只在这里维护一份内存副本（新建会话时查询
    /// 一次、恢复会话时直接从磁盘记录种入），避免每次持久化整个列表时都要重新 `await` actor 逐个
    /// 查询已经问过的 session（`kernelKey(for:)` 本身是 `KernelClient` target 的 internal 方法，
    /// `AgentShellCore` 也够不到——见 `currentKernelKey` 的存在理由，KernelClient.swift
    /// `SessionRestoring` 协议文档注释）。
    private var persistedKernelKeyBySessionID: [String: String] = [:]

    public init(config: KernelShellConfig, persistence: SessionPersistenceStore = SessionPersistenceStore()) {
        self.configWarning = config.configWarning
        self.client = OpenclawGatewayKernelClient(endpoint: config.endpoint, token: config.token)
        self.persistence = persistence
    }

    public func session(for id: String) -> ChatSessionViewModel? {
        sessions.first { $0.id == id }
    }

    /// 应用启动时（ContentView 的 .task）调用一次；已连接或正在连接时直接返回，不重复握手。
    public func connectIfNeeded() async {
        switch connectionStatus {
        case .connected, .connecting:
            return
        case .notConnected, .failed:
            break
        }
        connectionStatus = .connecting
        do {
            let scopes = try await client.connect()
            connectionStatus = .connected(scopes: scopes)
        } catch {
            connectionStatus = .failed(describeError(error))
        }
    }

    /// 对应任务书 UI 最低要求「新建会话」动作：调 createSession，新会话进入左侧列表并被选中。
    /// 这是本轮任务书明确要求的字面行为——D5.2（~/.llm-wiki/agent-app-design/product/
    /// d5-2-sessions.md §2.2）设计的是更精细的"草稿态 -> 首次发送时原子 create+send"，但那是留给
    /// 完整产品实现的设计，本轮 L1 按任务书要求走更简单直接的"点新建即 createSession"，两者不矛盾
    /// ——只是 L1 选了任务书明确要求的那一种时点。
    public func createNewSession() async {
        guard !isCreatingSession else { return }
        isCreatingSession = true
        defer { isCreatingSession = false }
        globalErrorMessage = nil

        await connectIfNeeded()
        guard case .connected = connectionStatus else {
            globalErrorMessage = "新建会话失败：底层连接未就绪（\(connectionStatusSummary)）"
            return
        }

        // 照 CLIRunner.swift STEP 2 的做法：不传 message/task，零模型调用；cwd/newapiEndpoint 是
        // 占位值——OpenclawGatewayKernelClient.createSession() 本轮只透传 label(+model)，这两个
        // 字段目前未接入 openclaw 原生 createSession（见该方法文档注释），如实沿用同样的占位约定，
        // 不臆造壳自己另一套"看起来更真实"的值。
        let config = Config(
            approvalProfile: nil,
            cwd: "/tmp/agent-shell-l1-stub-cwd",
            model: nil,
            newapiEndpoint: NewapiEndpoint(baseURL: "http://127.0.0.1:0/agent-shell-l1-unused", deploymentTokenRef: nil),
            resume: nil,
            sandbox: nil,
            toolset: nil
        )

        do {
            let handle = try await client.createSession(config: config)
            let viewModel = ChatSessionViewModel(handle: handle, title: "会话 \(sessions.count + 1)")

            // rounds/0012 ②（2026-08-09 三次返工后订正——上一版这里写的是"subscribe() 现在会一直
            // await 到服务端订阅 RPC 落地才返回"，那是被推翻的行为，已如实改写，见本文件头注释与
            // OpenclawGatewayKernelClient.subscribe()/send() 文档注释）：`subscribe()` 现在**立即
            // 返回**（同步注册本地事件续体后返回，D1 §2.3 契约），这次 `await` 不会有明显等待。这里
            // 仍然紧跟着直接 await 它，并且**在拿到 stream 之后才把这个 session 加进 `sessions` /
            // 设成 `selectedSessionID`**——理由不再是"等服务端确认"，而是保证"session 出现在侧栏
            // 列表里、能被点选发送"这一刻，**本地事件流已经就绪**（`consumeEvents` 有 stream 可读，
            // 不会读到一个还没创建出来的东西）。UI 只能对已经在 `sessions` 里的 session 调用
            // `sendMessage`（`sendMessage` 靠 `session(for:)` 在 `sessions` 里查找，查不到就静默
            // 返回），所以这个先后顺序仍然值得保留，只是理由变了。
            //
            // **服务端订阅是否已经确认，现在由 KernelClient 内部的 send 侧屏障负责**——
            // `OpenclawGatewayKernelClient.send()` 开头会等这个 session 的订阅 RPC 完成 dispatch
            // 才继续（完整设计取舍见该方法文档注释），`SessionStore` 这一层不需要、也不再尝试替
            // KernelClient 操心这件事。UI 侧因此不存在"点发送"跑到"服务端订阅已确立"之前的窗口——
            // 只是这道防线现在长在 KernelClient 里，不是这里的调用顺序。
            //
            // 真正没有天然终点、必须留在背景 Task 里的只有**事件消费循环本身**（下面
            // `consumeEvents` 里的 `for try await`）。
            //
            // 失败路径：`subscribe()` 协议签名不带 `throws`（不可改，见 KernelClient.swift），这次
            // await 本身不会抛错；订阅失败时错误已经被 `continuation.finish(throwing:)` 封进
            // `stream`，背景 Task 里 `consumeEvents` 现有的 `for try await` + `catch` 会在第一次
            // 迭代就捕获它、写进 `session.streamError`——`SessionDetailView` 已经把这个字段渲染成
            // 红色横幅（"事件流中断：…"），沿用既有路径，未新增错误通道。
            let stream = await client.subscribe(session: handle)

            sessions.append(viewModel)
            selectedSessionID = viewModel.id
            // rounds/0014 A：为持久化取得这个会话的 openclaw kernelKey——`client` 在这个类型里是
            // 具体的 `OpenclawGatewayKernelClient`（不是抽象的 `any KernelClient`），它总是遵循
            // `SessionRestoring`（见该 actor 文件底部的 extension），这里因此直接调用而不需要
            // `as?` 能力探测；`SessionRestoring` 本身仍然是加法式、可选的协议——如果未来 `client`
            // 的声明类型改成 `any KernelClient`，这里需要相应地改回 `as?` 分支。返回 nil（理论上
            // 不会发生：`createSession()` 刚刚成功过，映射表必然已经种好）时字典下标赋值会移除对应
            // 键，`persistSessionsSnapshot()` 的 `compactMap` 会据此正确地把这个 session 排除在
            // 持久化之外，而不是写一条 kernelKey 缺失的坏记录。
            persistedKernelKeyBySessionID[handle.sessionID] = await client.currentKernelKey(sessionID: handle.sessionID)
            persistSessionsSnapshot()
            // 长驻消费事件流，不等待、不 join——UI 场景没有"这次任务做完了"的天然终点。
            Task { await self.consumeEvents(for: viewModel, stream: stream) }
        } catch {
            globalErrorMessage = "新建会话失败：\(describeError(error))"
        }
    }

    /// rounds/0014 A 块：把当前内存态 `sessions` 里"已知 kernelKey"的部分写回磁盘。没有已知
    /// kernelKey 的 session（`persistedKernelKeyBySessionID` 里没有对应条目）被 `compactMap` 排除
    /// ——宁可这次不持久化这一条，也不写一条 kernelKey 缺失、重启后没法恢复的坏记录。
    private func persistSessionsSnapshot() {
        let records: [PersistedSession] = sessions.compactMap { vm in
            guard let kernelKey = persistedKernelKeyBySessionID[vm.id] else { return nil }
            return PersistedSession(handle: vm.handle, kernelKey: kernelKey, title: vm.title, createdAt: vm.handle.createdAt)
        }
        persistence.save(records)
    }

    /// rounds/0014 B/C/D：应用启动、`connectIfNeeded()` 已经跑过一次之后调用（见 ContentView.swift
    /// 的 `.task`）——把上一次进程持久化的会话清单（A 块）逐个变回可用会话：重新播种适配器映射 +
    /// 重新订阅（B/D，`SessionRestoring.restoreSession`）、并发拉取每个会话的历史消息回填 UI
    /// （C，`SessionHistoryProviding.fetchFullHistory`，见 `backfillHistory` 文档注释）。
    ///
    /// C 与 B/D 分别是独立的背景 `Task`——不互相等待：某个会话的历史拉取失败/慢不应该拖慢它重新
    /// 接入事件流的时机（D 的"不能只是只读快照"要求），也不应该拖慢其它会话各自的恢复进度。
    ///
    /// 幂等保护：`sessions` 非空时直接返回，不重复恢复——SwiftUI `.task` 修饰符本身理论上只在视图
    /// 首次出现时跑一次，这里的 guard 只是不依赖那个假设的防御性写法。
    public func restorePersistedSessionsIfNeeded() async {
        guard sessions.isEmpty else { return }
        let persisted = persistence.load()
        guard !persisted.isEmpty else { return }

        await connectIfNeeded()
        guard case .connected = connectionStatus else {
            // 连接本身失败——connectIfNeeded() 已经把原因写进 connectionStatus，侧栏横幅会显示，
            // 这里不用 globalErrorMessage 重复一遍。持久化文件原样留在磁盘上，不清除：这不是"坏
            // 数据"，只是这次连不上，下次连接成功（比如用户重开 app）时仍应该能从同一份记录恢复。
            return
        }

        for record in persisted {
            let viewModel = ChatSessionViewModel(handle: record.handle, title: record.title)
            let stream = await client.restoreSession(sessionID: record.handle.sessionID, kernelKey: record.kernelKey)
            persistedKernelKeyBySessionID[record.handle.sessionID] = record.kernelKey
            sessions.append(viewModel)
            Task { await self.consumeEvents(for: viewModel, stream: stream) }
            Task { await self.backfillHistory(for: viewModel, kernelKey: record.kernelKey) }
        }
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
    }

    /// 每页拉取的历史消息条数——参照 openclaw `chat.history` 服务端默认值 200
    /// （`kernels/openclaw/src/gateway/server-methods/chat-history-handler.ts`：
    /// `const requested = typeof limit === "number" ? limit : 200`），不是本壳凭空选的数字。
    private static let historyPageLimit = 200

    /// rounds/0014 C 块：拉取一个已恢复会话的历史消息，插入到消息列表最前面。用
    /// `insert(contentsOf:at:0)` 而不是整体覆盖 `session.messages`——`consumeEvents` 的背景 Task
    /// 与本方法各自独立并发运行，理论上一个新事件有可能在这次历史回填完成之前就先到达并 append
    /// 了一条消息（不常见，但不是不可能）；"插入到已有内容之前"而不是"整体替换"，无论谁先谁后都
    /// 不会丢内容——最坏情况只是历史消息与这条"抢跑"的实时消息在时间上略微交错，而不是二选一地
    /// 丢掉其中一边。
    ///
    /// **C 通路选择：WS `chat.history` RPC（不是 HTTP `GET /sessions/<key>/history`）——理由：**
    ///   1. **复用现有传输**：`client` 已经是一条常驻的、鉴权过的 WebSocket 连接，`chat.history`
    ///      只是这条连接上的又一个 RPC method；HTTP 通路需要壳新增一套独立的 HTTP 客户端 +
    ///      第二份 `Authorization: Bearer` 鉴权逻辑，本壳目前没有任何 HTTP 调用代码。
    ///   2. **与 D 块共享同一次恢复动作**：恢复流程本来就要为这个 session 调用
    ///      `restoreSession()`/`subscribe()`，历史拉取用同一条连接上的 RPC，概念上更贴合"这是同
    ///      一个恢复动作的两个子步骤"，而不是另开一条完全独立的 HTTP 请求路径。
    ///   3. **明知的代价（如实登记）**：任务书证据表写明 WS 这条通路"仅被源码验证过"，HTTP 那条是
    ///      rounds/0013 live 验通的——这里选了验证覆盖更弱的一条。降低风险的做法：
    ///      `fetchFullHistory`（OpenclawGatewayKernelClient.swift）内部的翻页/异常处理照抄
    ///      reconcile-history.py 已经两轮对抗评审加固过的纪律（游标不推进即拒绝继续、`hasMore`
    ///      语义拿到就当真、迭代次数硬上限），把"这条 RPC 没有 live 跑过"限定成一个明确、有限的
    ///      残留风险（字段名/响应形状可能与源码判断有出入），而不是让这个假设静默传播成"翻页逻辑
    ///      抄过来了应该没事"。这个风险原样记在交回报告里，不掩盖。
    ///   4. **失败处理**：`fetchFullHistory` 抛错时只把这一个会话标成 `streamError`（复用既有的
    ///      "事件流出错"展示通道，见 `SessionDetailView` 的红色横幅），不影响其它会话的恢复、也不
    ///      影响这个会话本身继续接收新的实时消息（B/D 已经独立完成，不依赖 C 是否成功）。
    private func backfillHistory(for session: ChatSessionViewModel, kernelKey: String) async {
        do {
            let records = try await client.fetchFullHistory(kernelKey: kernelKey, pageLimit: Self.historyPageLimit)
            let restored = records.map(Self.historyChatMessage(from:))
            guard !restored.isEmpty else { return }
            session.messages.insert(contentsOf: restored, at: 0)
        } catch {
            session.streamError = "历史回填失败：\(describeError(error))"
        }
    }

    /// 历史消息的 role 字符串（openclaw 原始取值，见 `HistoryRecord.role` 文档注释）映射到 UI 的
    /// 三态 `ChatRole`。"user"/"assistant" 是仅有的两个已知、有把握的取值；其它任何取值（包括
    /// `HistoryRecord` 解析层在 role 缺失时填的 "unknown"）一律归入 `.system`，且把原始 role 字面
    /// 值前缀进文本——不是把未知内容悄悄吞掉，也不是错误地冒充成 user/assistant 说的话，呼应本壳
    /// "失败/异常可诊断"的既有原则（`ChatModels.swift` 对 `.system` 角色的定位）。
    private static func historyChatMessage(from record: HistoryRecord) -> ChatMessage {
        switch record.role {
        case "user": return ChatMessage(role: .user, text: record.text)
        case "assistant": return ChatMessage(role: .assistant, text: record.text)
        default: return ChatMessage(role: .system, text: "[\(record.role)] \(record.text)")
        }
    }

    /// 对应 UI 最低要求「输入框 + 发送动作：调 send」。真正的回复文本不从这里的返回值来——
    /// send() 只回一个 runId 确认 RPC 已受理（OpenclawGatewayKernelClient.swift send() 文档注释：
    /// "不是模型的最终输出"），内容全部走 consumeEvents() 里已经在跑的事件流异步到达。
    public func sendMessage(_ text: String, in sessionID: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = session(for: sessionID) else { return }

        session.messages.append(ChatMessage(role: .user, text: trimmed))
        session.isWaitingForReply = true
        do {
            _ = try await client.send(session: session.handle, input: Input(kind: .text, text: trimmed, parts: nil))
        } catch {
            session.isWaitingForReply = false
            session.messages.append(ChatMessage(role: .system, text: "[发送失败] \(describeError(error))"))
        }
    }

    /// rounds/0012 ②：`subscribe()` 已经在 `createNewSession()` 里 await 过（见那里的文档注释），
    /// 这里只负责消费拿到手的 `stream`，不再自己调用 `subscribe()`。这段 `for try await` 才是真正
    /// "没有天然终点"、必须留在背景 Task 里的部分。
    private func consumeEvents(for session: ChatSessionViewModel, stream: AsyncThrowingStream<EventMessageUnion, Error>) async {
        do {
            for try await event in stream {
                handle(event, for: session)
            }
        } catch {
            session.streamError = describeError(error)
        }
    }

    /// EventMessageUnion 十一个变体（app/generated/swift/DiscriminatedUnions.swift:104-116）里，
    /// L1 只据此驱动两类 UI 效果：
    ///   - evt.message.delta（.messageDelta）：assistant 文本的唯一来源，见
    ///     appendAssistantDelta 的文档注释。
    ///   - evt.turn_complete / evt.error / evt.session_end：不渲染成消息气泡本身（除了 error/
    ///     sessionEnd 额外插入一条系统行用于"失败可见"），但驱动"是否在等回复"这个状态位——
    ///     UI 最低要求里"有没有在等回复"这一条需要它们。
    /// 其余 7 个变体（thinking/toolCall/toolResult/approvalRequest/capabilityChanged/
    /// operationCompleted/approvalBufferResolved）按 D5.1（~/.llm-wiki/agent-app-design/product/
    /// d5-1-message-flow.md §1 分工表）本就分属其它子面（如 approvalRequest 的完整呈现是 D5.3
    /// 审批五态 UI，L1 任务书明确排除），也不在任务书列出的"UI 最低要求"范围内（该范围字面写的是
    /// "用户发出的消息 + 从 subscribe 事件流里解析出的 assistant 文本"）——L1 故意不渲染，这是
    /// scope 决定，不是漏做。
    ///
    /// **可见性变更（rounds/0013 B2，最小化放宽）**：原为 `private`，本轮改为 internal（去掉
    /// `private`，不是加 `public`/`open`）——唯一理由是让 `frame-replay-tests` target 能通过
    /// `@testable import AgentShellCore` 直接驱动这个方法，喂真实 `EventMessageUnion` 事件、断言
    /// `session.messages` 的分组结果（见 SessionStoreGroupingTests.swift）。这是本轮任务书明确
    /// 建议的测试打点位置——比直接测 `appendAssistantDelta` 更忠实，因为它走的是
    /// `consumeEvents()` 实际分发事件时经过的同一个入口，不是绕过 `handle` 的 switch-case 直接
    /// 摆一个已知会命中 `.messageDelta` 分支的调用。没有放宽 `appendAssistantDelta`/
    /// `consumeEvents`——这两个仍是 `private`，只放宽了 `handle` 这一处（`SessionStore` 类本身
    /// 也从 internal 改成了 public，但那是模块拆分本身的必需后果，不是为测试做的，理由见本类型
    /// 上方的头注释，和这里的"最小化"是两回事——两者的放宽幅度独立评估）。`@testable import`
    /// 本身也不会把 `handle` 暴露成模块外可见（不加 `-enable-testing` 编译的调用方看不到它，
    /// 仍然是"事实上的 private，仅测试可达"）。
    func handle(_ event: EventMessageUnion, for session: ChatSessionViewModel) {
        switch event {
        case .messageDelta(let e):
            appendAssistantDelta(e, to: session)
        case .turnComplete(let e):
            session.isWaitingForReply = false
            // rounds/0015 C：`stop()` 在 abort 之前强制 deny 掉的审批，其 reqId 由 D1 §6.2 M3 要求
            // 列在这里（`forceResolvedApprovals`，见 OpenclawGatewayKernelClient
            // `forceDenyPendingApprovalsBeforeStop`）——这是壳能**契约性地**得知"这条审批已经被
            // 终态化、不必再等用户裁决"的唯一推送通道（openclaw 的 session.approval(phase:terminal)
            // 在 D2 十一变体里没有对应位置，收不到）。据此清掉卡片，避免留下永远点不动的僵尸审批。
            if let forceResolved = e.payload.forceResolvedApprovals, !forceResolved.isEmpty {
                let resolved = Set(forceResolved)
                session.pendingApprovals.removeAll { resolved.contains($0.reqID) }
            }
        case .approvalRequest(let e):
            // ---- rounds/0016（T-096 第 4 项）：**先清除旧卡片，再呈现这一条** ----
            //
            // 修前是无条件 `append`。在 D1 §6.2 的 FSM 下，一条新的 `approval_request` 到达**只能**
            // 意味着"上一条 active 已经终态化、这一条是被提升上来的 #2"（适配器保证同一 session 同一
            // 时刻只暴露一个 active pending）。而 UI 只渲染队头（SessionDetailView 的串行呈现）——
            // append 的后果是：**用户看到的仍然是那张已经死掉的旧卡，提升项被挤在它后面，在界面上
            // 根本不浮现**。这正是 T-096 第 4 项点名的失败态。
            //
            // 两条语句的**顺序就是要求本身**：先移除所有 reqId 不同的旧卡（清），再让这一条落位
            // （呈现）。被清掉的旧卡在会话流里留一条系统行——不能让一张卡片无声消失，用户需要知道
            // "刚才那条我还没来得及点的审批，已经不在了"。
            let staleReqIDs = session.pendingApprovals.filter { $0.reqID != e.payload.reqID }.map(\.reqID)
            session.pendingApprovals.removeAll { $0.reqID != e.payload.reqID }
            if !staleReqIDs.isEmpty {
                session.messages.append(ChatMessage(
                    role: .system,
                    text: "[审批] 上一条审批已在内核侧终态化，卡片已清除（reqId=\(staleReqIDs.joined(separator: ", "))）；"
                        + "下面呈现的是队列中提升上来的下一条"
                ))
            }
            // 同一个 reqId 重复到达（例如断线重连后 subscribe 响应里的 approvalReplay 重放了一条
            // 我们已经在显示的审批）不重复插卡片——按 reqId 去重，保留先到的那条（它的
            // requestedAt 才是真正的产出时刻，重放帧的时间戳没有更权威）。
            if !session.pendingApprovals.contains(where: { $0.reqID == e.payload.reqID }) {
                session.pendingApprovals.append(PendingApprovalItem(event: e))
            }
        case .error(let e):
            // ErrorEventMessagePayload.recoverable 是三态（none/run/session，D2.swift:2517-2521），
            // 不是简单布尔；L1 采用保守简化：任何 evt.error 都先把"等待中"状态收掉，宁可指示提前
            // 消失（后续如果真的还有 turnComplete 到达，会被再次置 false，幂等无害），也不要让
            // composer 因为一次不会再有后续 turnComplete 的错误而永久卡在"等待中"。这是一处已知
            // 简化，未按 recoverable 三态精细区分恢复行为（那属于 L2 审批/恢复 UI 的范畴）。
            session.isWaitingForReply = false
            session.messages.append(ChatMessage(role: .system, text: "[错误] \(e.payload.message)"))
            // rounds/0016（T-096 第 4 项）：`approval_timeout` 是 D2 `KernelErrorCode` 里**字面
            // 对应**"审批被内核判超时"的那个取值（common/errors.schema.json:10-18），适配器在
            // active pending 被内核终态化时产出它（`handleApprovalTerminalSignal`）。它就是"先
            // 清旧卡"的那一步——**必须在提升项的 approval_request 之前处理**，而事件流上它确实
            // 排在前面（适配器先 yield error 再 yield 提升项，顺序是可观察的）。
            //
            // **为什么可以清整张列表而不是按 reqId 定点清**：`ErrorEventMessagePayload` 只有
            // code/message/nativeCode/recoverable 四个字段，**没有 reqId 承载位**，而 `nativeCode`
            // 按 D2 的字段注释"非契约稳定，UI 不得对其分支判断"——从消息文本里抠 reqId 更是不能做。
            // 依据是 D1 §6.2 的**单 active 不变量**：同一时刻这个 session 至多有一张卡片，所以
            // "清掉当前这张"与"按 reqId 清掉超时的那张"在这里是同一件事。这是不变量推出的结论，
            // 不是"差不多就这样"的近似。
            if e.payload.code == .approvalTimeout, !session.pendingApprovals.isEmpty {
                let cleared = session.pendingApprovals.map(\.reqID)
                session.pendingApprovals.removeAll()
                session.messages.append(ChatMessage(
                    role: .system,
                    text: "[审批] 该请求已被内核判定超时（fail-closed 拒绝），卡片已清除（reqId=\(cleared.joined(separator: ", "))）"
                ))
            }
        case .sessionEnd(let e):
            session.isWaitingForReply = false
            session.messages.append(ChatMessage(role: .system, text: "[会话结束] reason=\(e.payload.reason.rawValue)"))
        case .approvalBufferResolved(let e):
            // rounds/0015 返工①（D1 §6.2「缓冲生命周期的独立可见性」）：一条**从未被呈现给用户**的
            // 审批请求，因为排在 FIFO 缓冲队列里超时、或因为队列溢出被适配器 fail-closed 拒绝，而
            // 直接进了终态。D1 原文要求"不得让一条从未被看见的请求静默消失"——壳这边唯一诚实的落点
            // 就是在会话流里留一条系统行：卡片是不可能有的（它从来没被 yield 成 approval_request），
            // 但"这台机器上有一次操作被自动拒绝了"这件事必须能被用户看到。
            //
            // **刻意不弹模态、也不并进红色横幅**：沿用本壳既有的"错误必须可见但不打断"原则（同
            // ApprovalModels.swift 对审批卡片行内错误的定位）。这不是错误，是一次 fail-closed 的
            // 自动决策，系统行是它合适的分量。
            let bufferReason: String
            switch e.payload.reason {
            case .bufferedTimeout: bufferReason = "在等待队列中超时（内核侧计时器不因排队而暂停）"
            case .queueOverflow: bufferReason = "等待队列已满，按 fail-closed 策略自动拒绝"
            }
            session.messages.append(ChatMessage(
                role: .system,
                text: "[审批] 一条未及呈现的请求已被自动拒绝：\(bufferReason)（reqId=\(e.payload.reqID)）"
            ))
            // 防御性：这条 reqId 结构性地不该出现在卡片列表里（缓冲期的请求从未产出过
            // approval_request），万一因为将来的改动出现了，也要跟着清掉，不留点不动的僵尸卡片。
            session.pendingApprovals.removeAll { $0.reqID == e.payload.reqID }
        case .thinking, .toolCall, .toolResult, .capabilityChanged, .operationCompleted:
            break
        }
    }

    /// rounds/0015 C：把用户在审批卡片上点的决策回传给内核（D1 §2.6 `respondApproval`）。
    ///
    /// **本方法自己不做任何决策合法性判断**——`allowedDecisions` 成员校验、D2/openclaw 决策值映射、
    /// 以及"内核是否真的兑现了这次决策"的核对，全部在 kernel-client 层
    /// （`OpenclawGatewayKernelClient.respondApproval` 的四道关卡 + `makeApprovalResolveParams`）。
    /// UI 层重复实现一遍那套校验只会制造第二个可能与内核脱节的真相来源；这里的职责只有三件：
    /// 防重复提交、成功后移除卡片、失败时把错误**留在这张卡片上**让用户能改选再试。
    ///
    /// 失败时刻意**不移除**卡片：决策被客户端拦下（例如选了这条请求不允许的档位）时审批在内核侧
    /// 仍然 pending，用户改选一个合法选项后应该还能再点一次。真正已经终态化的情况（内核没兑现、
    /// 或 RPC 报 approval_not_pending），错误文案会说明，用户可以手动关掉卡片。
    public func respondToApproval(
        reqID: String, decision outcome: ApprovalDecisionKindElement, in sessionID: String
    ) async {
        guard let session = session(for: sessionID),
              let index = session.pendingApprovals.firstIndex(where: { $0.reqID == reqID }) else { return }
        guard !session.pendingApprovals[index].isSubmitting else { return }

        session.pendingApprovals[index].isSubmitting = true
        session.pendingApprovals[index].errorMessage = nil
        // D1 `Decision` 的另外三个字段：`updatedInput` 传 nil（openclaw 的 approval.resolve 参数里
        // 没有承载位置，传了会被 respondApproval 显式拒绝而不是静默丢弃——见
        // ApprovalDecisionError.unsupportedUpdatedInput）；`scope`/`reason` 同样留 nil，内核自己
        // 记录 resolver 归属与 reason:"user"，客户端指定不了。
        let decision = Decision(outcome: outcome, updatedInput: nil, scope: nil, reason: nil)
        do {
            try await client.respondApproval(session: session.handle, reqID: reqID, decision: decision)
            let resolved = session.pendingApprovals.first { $0.reqID == reqID }
            session.pendingApprovals.removeAll { $0.reqID == reqID }
            // 在消息流里留一条系统行——审批是"这台机器上真的执行了什么"的关键节点，裁决结果必须
            // 在会话记录里留痕，而不是随卡片一起消失（卡片本身是瞬态的，本轮不做审批历史）。
            session.messages.append(ChatMessage(
                role: .system,
                text: "[审批] \(approvalDecisionButtonLabel(outcome))：\(resolved?.bodyText ?? reqID)"
            ))
        } catch {
            guard let stillThere = session.pendingApprovals.firstIndex(where: { $0.reqID == reqID }) else { return }
            session.pendingApprovals[stillThere].isSubmitting = false
            session.pendingApprovals[stillThere].errorMessage = describeError(error)
        }
    }

    /// 用户手动关掉一张已经无法再操作的卡片（本地判定已超时、或决策失败后确认审批已终态）。
    /// **纯本地移除，不发任何 RPC**——不假装替用户做了什么决策。
    public func dismissApproval(reqID: String, in sessionID: String) {
        session(for: sessionID)?.pendingApprovals.removeAll { $0.reqID == reqID }
    }

    /// evt.message.delta 的 payload 形状是 {delta: String, index: Int, messageID: String?, role: Role}
    /// （app/generated/swift/D2.swift:1642-1667，`messageID` 是 rounds/0012 新增的可选字段）；role
    /// 字段类型 `Role` 目前只有一个合法取值 `.assistant`（D2.swift 同结构体，没有 user/system 枚举
    /// 成员，解码到其它取值会直接抛 DecodingError）——也就是说这个事件类型从协议层面就只可能携带
    /// assistant 的流式文本，这正是任务书里"assistant 文本"的唯一取用点，本壳没有从其它变体里取过
    /// assistant 文本。
    ///
    /// **rounds/0012 ①' C 方案——分组键与追加语义均已改写，取代上一轮按 (runId,index) 分组 + `+=`
    /// 追加的实现**（旧实现见 git 历史）：
    ///
    /// - **分组键改为 `messageID`**（wire `session.message` 事件 payload.messageId 经 EventMapping
    ///   透传而来，见 EventMapping.swift `mapOpenclawSessionMessageToKernelEvents` 的 text 分支）。
    ///   旧键 `(runID, index)` 已被实测坐实为错误：`index` 只是单条 assistant 消息内的
    ///   content-block 下标，每条新消息都从 0 重新计数；同一个 run 产出两条不同的 assistant 消息时
    ///   二者 `(runID, index)` 相同（均为 `(runID, 0)`），旧键因此撞车、被误判成"同一条消息的后续
    ///   分段"（rounds/0012 evidence/instrumented-run-findings.md §1.2 实测：两条不同 messageId 的
    ///   帧被拼进同一个气泡，文本重复）。`messageID` 每帧互异（同上 evidence §1.3 实测），是协议层
    ///   面唯一能可靠标识"这是不是同一条消息"的字段。
    /// - **`+=` 追加改为 `=` 覆盖**：rounds/0012 实测坐实（同上 evidence §1.1）`session.message` 层
    ///   不做增量投递——一条 assistant 消息 = 一条帧 = 一个 evt.message.delta，`delta` 携带的是
    ///   **完整全文**，不是相对上一条的增量。因此"同一 messageID 再次到达"（例如未来协议改动带来的
    ///   重放/补发）该用最新全文覆盖旧文本，`+=` 会把全文错误地拼接两遍——那正是本轮要修的重复
    ///   bug 本身（旧 (runId,index) 键撞车时表现出的错误现象）。
    /// - **`messageID` 缺失时的回退**：不复用任何既有分组键，直接开一条新气泡，且不写回
    ///   `inProgressDeltaMessageID`（反正不会再被同一个 nil 命中）。缺失只会发生在旧版协议/未来
    ///   协议变化未提供该字段的场景，本壳没有能力判断"这条没有 messageID 的 delta 是否该并入某条
    ///   已有气泡"——瞎猜一个键去分组，正是本轮要修的原始缺陷的同构重演（拿一个不能唯一标识消息的
    ///   键去分组，两条不同消息撞键、互相污染）。"缺 identity 时宁可多开一条气泡"严格安全于
    ///   "缺 identity 时瞎猜一个键"：前者最坏情况是多一条冗余气泡，后者最坏情况是内容被错误合并/
    ///   覆盖。
    private func appendAssistantDelta(_ event: MessageDeltaEventMessage, to session: ChatSessionViewModel) {
        session.isWaitingForReply = true
        if let messageID = event.payload.messageID,
           let existingID = session.inProgressDeltaMessageID[messageID],
           let idx = session.messages.firstIndex(where: { $0.id == existingID }) {
            session.messages[idx].text = event.payload.delta
        } else {
            let message = ChatMessage(role: .assistant, text: event.payload.delta)
            session.messages.append(message)
            if let messageID = event.payload.messageID {
                session.inProgressDeltaMessageID[messageID] = message.id
            }
        }
    }

    private var connectionStatusSummary: String {
        switch connectionStatus {
        case .notConnected: return "未连接"
        case .connecting: return "连接中，请稍候再试一次"
        case .connected: return "已连接"
        case .failed(let message): return "连接失败：\(message)"
        }
    }

    private func describeError(_ error: Error) -> String {
        if let kernelError = error as? KernelClientError {
            return kernelError.description
        }
        // rounds/0015：审批决策层自己的错误（决策档位不被内核支持 / 不在这条请求的 allowedDecisions
        // 内 / 内核未兑现决策……）同样有可读的 description，不要落到下面的 `"\(error)"` 去打印一个
        // 枚举 case 的原始拼写——审批错误正是最需要用户看懂的一类。
        if let approvalError = error as? ApprovalDecisionError {
            return approvalError.description
        }
        return "\(error)"
    }
}
