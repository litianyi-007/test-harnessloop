// SG-8.7 Stage A：fixture DSL 的 Swift Codable 镜像——逐字对应 ../dsl.ts（本身逐字转录自 D4
// 跨平台架构 v2.2 §4.3）。与 dsl.ts 的关系：TS 那份是判别联合（TimelineOp 按 `op` 字段分 8 个
// 互斥变体，每个变体只声明自己需要的字段），本文件用一个「扁平化、按 op 决定哪些字段有意义」的单一
// struct 表达同一件事——这是刻意的、有注释交代的简化（不是 quicktype 坍缩 oneOf 那种因为工具局限
// 被迫接受的缺陷，见 ../CODEGEN-FINDINGS.md 对这个区别的界定）：本文件的字段全部可选，`op` 本身仍是
// 强类型枚举，读者按 `op` 的取值就知道该看哪些字段，不存在『解码后无法判别到底是哪个变体』的问题。
//
// 开放字段（args/pattern/message/expected/initialState）用 D2 codegen 产物 `JSONAny`
// （app/generated/swift/D2.swift 尾部，quicktype 标准 boilerplate）表达——本文件复用它而不是另起一个
// AnyCodable，保持『同一个 module 只有一份「任意 JSON 值」的 Codable 表达』。

import Foundation

/// D4 §4.3 TimelineOp 的 8 个判别取值——对应 dsl.ts 的 `op` 字面量。
public enum TimelineOpKind: String, Codable {
    case clientCall = "client_call"
    case expectOutbound = "expect_outbound"
    case mockResponse = "mock_response"
    case mockEvent = "mock_event"
    case disconnect
    case reconnect
    case advanceClock = "advance_clock"
    case assertState = "assert_state"
}

/// 单个 timeline 动作——字段并集，具体哪些字段有意义取决于 `op`（见上方文件头注释）。
public struct TimelineOp: Codable {
    public let t: Int
    public let op: TimelineOpKind

    // client_call
    public let id: String?
    public let call: String?
    public let args: JSONAny?

    // expect_outbound
    public let matches: String?
    public let pattern: JSONAny?

    // mock_response
    public let replyTo: String?
    public let message: JSONAny?

    // mock_event（可选）——翻译层专属驱动控制量，不属于 D2 wire 事件本身（`message` 是封闭 D2
    // 判别联合，容不下非 D2 字段）。逐字对应 ../dsl.ts 的 `MockEventDriverHint`（T-048 REWORK
    // #1/#2 收残：取代此前非法塞进 message 的 `_openclawJoinOrder`）。TS mock-kernel-client 忽略
    // 同名字段；Swift runner 在 `applyMockEvent` 的 `evt.approval_request` 分支读取
    // `driverHint.value["approvalJoinOrder"]`。
    public let driverHint: JSONAny?

    // advance_clock
    public let ms: Int?

    // assert_state（与顶层 ParityFixture.expected 共用同一种『ClientObservableState 子集』表达，
    // 这里同样用 JSONAny 承载，不另外声明一个强类型 ClientObservableState struct——原因见
    // SwiftFixtureRunner.swift 里 partialMatch 一节的文档注释：本 runner 对 actual/expected 两侧
    // 统一在 `[String: Any]` 层面做子集深度匹配，语义对齐 ts-runner 的 `partialMatch`，强类型化
    // ClientObservableState 反而会在『expected 只给部分字段』这个核心语义上增加不必要的摩擦）。
    public let expected: JSONAny?
}

/// 顶层 fixture——对应 dsl.ts 的 `ParityFixture`。
public struct ParityFixture: Codable {
    public let name: String
    public let description: String
    public let initialState: JSONAny?
    public let timeline: [TimelineOp]
    public let expected: JSONAny?
}
