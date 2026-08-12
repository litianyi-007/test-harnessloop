// SG-10 L1 Mac UI 壳 —— 纯 UI 层的会话/消息模型。
//
// 这些类型不是 D1/D2 契约的一部分：D1 KernelPort 只暴露 SessionHandle（app/generated/swift/
// D2.swift:3829）与十一类事件（EventMessageUnion，app/generated/swift/DiscriminatedUnions.swift:
// 104-116），"一条聊天气泡""侧栏连接状态指示"这些是 UI 层自己的呈现模型，对应 D5.1/D5.2 产品
// 规格里"应用层自建、无 D1/D2 原生对应"的那一类字段（如 ~/.llm-wiki/agent-app-design/product/
// d5-2-sessions.md §1.2 列表项字段来源表的写法）。

import Foundation

/// **可见性变更（rounds/0013 B2）**：本文件所有类型/成员从（默认）internal 改为 `public`——不是
/// 为了测试，是模块拆分本身的必需后果：`AgentShellCore` 拆出后是独立 SwiftPM target，`AgentShell`
/// 视图层现在通过**普通** `import AgentShellCore`（不是 `@testable import`）消费这些类型，普通
/// import 只能看到 `public`/`open` 成员——`internal` 只在同一个 module 内可见，拆分前 view 层文件
/// 和这些类型同属一个 target 所以 `internal` 够用，拆分后不够用了。这是纯粹的"同一件事换个 target
/// 装"的机械后果，不是新增了什么公开 API 意图上的放宽。

/// 聊天气泡的发送方——只有三种：用户自己输入的、从 evt.message.delta 里取出的 assistant 文本、
/// 以及本壳用来呈现"错误/会话结束"等诊断信息的系统行（不是任何 D1/D2 概念，纯 UI 需要，呼应
/// scope-lock RAE-0001 条件④"失败可诊断"——错误必须在消息流里看得见，不能只 print 到控制台）。
public enum ChatRole {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable {
    public let id = UUID()
    public let role: ChatRole
    public var text: String
    public let createdAt = Date()

    /// rounds/0017 Change 1：`ChatSessionViewModel.timeline` 把这个数组与新增的 `toolCalls`/
    /// `thinkingItems` 两个独立数组合并成一条统一呈现顺序时使用的排序键——不用 `createdAt`
    /// （wall-clock），理由见 `ChatSessionViewModel.allocateLiveTimelineSeq()` 的文档注释。
    /// 不对外公开（同 `inProgressDeltaMessageID` 的先例）：`AgentShell` 视图层只消费
    /// `ChatSessionViewModel.timeline` 这个已经排好序的结果，不需要、也不应该自己再读这个键。
    let timelineSeq: Int

    /// 显式 public init——struct 是 public 不代表编译器会合成一个 public 的逐成员初始化器
    /// （Swift 对 public 类型的自动合成初始化器上限是 internal），沿用调用方一直在用的
    /// `ChatMessage(role:text:)` 两参数形状（`id`/`createdAt` 各自有默认值表达式，本就不进
    /// 逐成员初始化器的参数列表——这是原本 Swift 自动合成时的既有形状，这里显式声明只是把它从
    /// "自动合成、上限 internal" 换成"手写、public"，参数形状本身没变）。`timelineSeq` 给默认值
    /// 0——只有 `SessionStore`（同模块）需要传真实取号结果；测试/未来调用点若不关心跨数组排序，
    /// 两参数形式仍然可用，不因为这个新维度被强制牵连。
    public init(role: ChatRole, text: String, timelineSeq: Int = 0) {
        self.role = role
        self.text = text
        self.timelineSeq = timelineSeq
    }
}

/// 壳与 openclaw gateway 之间底层 WebSocket 连接的状态——对应 OpenclawGatewayKernelClient.connect()
/// 这一步。注意 `KernelClient` 协议本身（app/kernel-client/swift/KernelClient.swift）没有
/// connect/disconnect：这是 `OpenclawGatewayKernelClient` 这个具体实现类多出的握手步骤（见该文件
/// connect() 的文档注释），协议七方法本身不含连接管理。
public enum ConnectionStatus {
    case notConnected
    case connecting
    case connected(scopes: [String])
    case failed(String)
}
