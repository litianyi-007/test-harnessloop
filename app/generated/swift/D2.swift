// 本文件由 codegen 自动生成，不要手工编辑。
// 源：app/contracts/d2/schema/（scripts/lib/leaf-types.mjs 枚举的叶子类型清单）
// 生成命令：npm --prefix app/contracts/d2/codegen run gen:swift
// 生成器：quicktype-core（quicktype 26.x），JSON Schema -> Swift Codable struct/enum。
//
// 覆盖范围：全部『非顶层 oneOf』具名类型（8 个方法 request 消息 + 11 个事件消息 +
// res.unknown + 叶子 result/failure payload，共 30 个 top-level）。
//
// 不含：4 类顶层判别联合（RequestMessage/ResponseMessage/EventMessage/Message）与 8 个方法各自
// 的 *ResponseMessage——quicktype 无法保住这些 oneOf 判别联合（已验证坍缩，见
// ../../CODEGEN-FINDINGS.md），改在 DiscriminatedUnions.swift 手写（该文件同目录，非本文件生成，
// 由 generate-swift.mjs 逐字拷贝 scripts/handwritten/discriminated-unions.swift）。

// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let createSessionRequestMessage = try CreateSessionRequestMessage(json)
//   let sendRequestMessage = try SendRequestMessage(json)
//   let subscribeRequestMessage = try SubscribeRequestMessage(json)
//   let interruptRequestMessage = try InterruptRequestMessage(json)
//   let stopRequestMessage = try StopRequestMessage(json)
//   let respondApprovalRequestMessage = try RespondApprovalRequestMessage(json)
//   let capabilitiesRequestMessage = try CapabilitiesRequestMessage(json)
//   let queryBillingRequestMessage = try QueryBillingRequestMessage(json)
//   let messageDeltaEventMessage = try MessageDeltaEventMessage(json)
//   let thinkingEventMessage = try ThinkingEventMessage(json)
//   let toolCallEventMessage = try ToolCallEventMessage(json)
//   let toolResultEventMessage = try ToolResultEventMessage(json)
//   let approvalRequestEventMessage = try ApprovalRequestEventMessage(json)
//   let errorEventMessage = try ErrorEventMessage(json)
//   let turnCompleteEventMessage = try TurnCompleteEventMessage(json)
//   let sessionEndEventMessage = try SessionEndEventMessage(json)
//   let capabilityChangedEventMessage = try CapabilityChangedEventMessage(json)
//   let operationCompletedEventMessage = try OperationCompletedEventMessage(json)
//   let approvalBufferResolvedEventMessage = try ApprovalBufferResolvedEventMessage(json)
//   let unknownResponseMessage = try UnknownResponseMessage(json)
//   let createSessionResultPayload = try CreateSessionResultPayload(json)
//   let sendResultPayload = try SendResultPayload(json)
//   let interruptResultPayload = try InterruptResultPayload(json)
//   let stopResultPayload = try StopResultPayload(json)
//   let queryBillingResultPayload = try QueryBillingResultPayload(json)
//   let capabilityDescriptorPayload = try CapabilityDescriptorPayload(json)
//   let rejectionFailure = try RejectionFailure(json)
//   let protocolFailure = try ProtocolFailure(json)
//   let billingQueryFailure = try BillingQueryFailure(json)
//   let emptyPayload = try EmptyPayload(json)

import Foundation

/// SG-1 深化：直接内联 sentAt/direction（不用 allOf 复用
/// common/envelope.schema.json#/$defs/requestEnvelopeBase）——codegen 工具 quicktype 对『allOf
/// 引用外部 $ref 片段』存在已验证的缺陷（allOf 成员会被直接忽略，字段静默丢失，比 oneOf 坍缩更隐蔽；复现见
/// CODEGEN-FINDINGS.md），改为直接内联是规避写法，语义与 allOf 版本完全等价，Ajv 校验结果不变。
// MARK: - CreateSessionRequestMessage
public struct CreateSessionRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: CreateSessionRequestMessagePayload
    public let sentAt: Date
    /// 不适用——createSession 尚无 session 可寻址，见上方说明。
    public let sessionID: String?
    public let type: CreateSessionRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: CreateSessionRequestMessagePayload, sentAt: Date, sessionID: String?, type: CreateSessionRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: CreateSessionRequestMessage convenience initializers and mutators

public extension CreateSessionRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CreateSessionRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: CreateSessionRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String?? = nil,
        type: CreateSessionRequestMessageType? = nil
    ) -> CreateSessionRequestMessage {
        return CreateSessionRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CreateSessionRequestMessageDirection: String, Codable {
    case request = "request"
}

/// 逐字段对应 D1 CreateSessionConfig（D1 v3.5 §2.1），无新增/无精简。
// MARK: - CreateSessionRequestMessagePayload
public struct CreateSessionRequestMessagePayload: Codable {
    public let config: Config

    public enum CodingKeys: String, CodingKey {
        case config = "config"
    }

    public init(config: Config) {
        self.config = config
    }
}

// MARK: CreateSessionRequestMessagePayload convenience initializers and mutators

public extension CreateSessionRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CreateSessionRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        config: Config? = nil
    ) -> CreateSessionRequestMessagePayload {
        return CreateSessionRequestMessagePayload(
            config: config ?? self.config
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Config
public struct Config: Codable {
    public let approvalProfile: ApprovalProfile?
    public let cwd: String
    public let model: String?
    public let newapiEndpoint: NewapiEndpoint
    public let resume: Resume?
    public let sandbox: Sandbox?
    public let toolset: Toolset?

    public enum CodingKeys: String, CodingKey {
        case approvalProfile = "approvalProfile"
        case cwd = "cwd"
        case model = "model"
        case newapiEndpoint = "newapiEndpoint"
        case resume = "resume"
        case sandbox = "sandbox"
        case toolset = "toolset"
    }

    public init(approvalProfile: ApprovalProfile?, cwd: String, model: String?, newapiEndpoint: NewapiEndpoint, resume: Resume?, sandbox: Sandbox?, toolset: Toolset?) {
        self.approvalProfile = approvalProfile
        self.cwd = cwd
        self.model = model
        self.newapiEndpoint = newapiEndpoint
        self.resume = resume
        self.sandbox = sandbox
        self.toolset = toolset
    }
}

// MARK: Config convenience initializers and mutators

public extension Config {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Config.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        approvalProfile: ApprovalProfile?? = nil,
        cwd: String? = nil,
        model: String?? = nil,
        newapiEndpoint: NewapiEndpoint? = nil,
        resume: Resume?? = nil,
        sandbox: Sandbox?? = nil,
        toolset: Toolset?? = nil
    ) -> Config {
        return Config(
            approvalProfile: approvalProfile ?? self.approvalProfile,
            cwd: cwd ?? self.cwd,
            model: model ?? self.model,
            newapiEndpoint: newapiEndpoint ?? self.newapiEndpoint,
            resume: resume ?? self.resume,
            sandbox: sandbox ?? self.sandbox,
            toolset: toolset ?? self.toolset
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum ApprovalProfile: String, Codable {
    case auto = "auto"
    case manual = "manual"
    case plan = "plan"
}

// MARK: - NewapiEndpoint
public struct NewapiEndpoint: Codable {
    public let baseURL: String
    /// 条件必填——billingAttribution 为 user_tenant_aggregate 时缺失将触发 createSession 同步拒绝
    /// aggregate_billing_requires_deployment_token（D1 v3.5 §2.1 步骤 0）。JSON Schema
    /// 层面不表达跨字段条件必填，忠实标注为可选，业务前置校验在实现层完成（呼应 D2 v3 §3.6 respondApproval 段落同类边界说明）。
    public let deploymentTokenRef: String?

    public enum CodingKeys: String, CodingKey {
        case baseURL = "baseUrl"
        case deploymentTokenRef = "deploymentTokenRef"
    }

    public init(baseURL: String, deploymentTokenRef: String?) {
        self.baseURL = baseURL
        self.deploymentTokenRef = deploymentTokenRef
    }
}

// MARK: NewapiEndpoint convenience initializers and mutators

public extension NewapiEndpoint {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(NewapiEndpoint.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        baseURL: String? = nil,
        deploymentTokenRef: String?? = nil
    ) -> NewapiEndpoint {
        return NewapiEndpoint(
            baseURL: baseURL ?? self.baseURL,
            deploymentTokenRef: deploymentTokenRef ?? self.deploymentTokenRef
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Resume
public struct Resume: Codable {
    public let sessionID: String

    public enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
    }

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

// MARK: Resume convenience initializers and mutators

public extension Resume {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Resume.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        sessionID: String? = nil
    ) -> Resume {
        return Resume(
            sessionID: sessionID ?? self.sessionID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Sandbox: String, Codable {
    case fullAccess = "full-access"
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
}

// MARK: - Toolset
public struct Toolset: Codable {
    public let allow: [String]?
    public let deny: [String]?

    public enum CodingKeys: String, CodingKey {
        case allow = "allow"
        case deny = "deny"
    }

    public init(allow: [String]?, deny: [String]?) {
        self.allow = allow
        self.deny = deny
    }
}

// MARK: Toolset convenience initializers and mutators

public extension Toolset {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Toolset.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        allow: [String]?? = nil,
        deny: [String]?? = nil
    ) -> Toolset {
        return Toolset(
            allow: allow ?? self.allow,
            deny: deny ?? self.deny
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CreateSessionRequestMessageType: String, Codable {
    case reqCreateSession = "req.createSession"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - SendRequestMessage
public struct SendRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: SendRequestMessagePayload
    public let sentAt: Date
    public let sessionID: String
    public let type: SendRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: SendRequestMessagePayload, sentAt: Date, sessionID: String, type: SendRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: SendRequestMessage convenience initializers and mutators

public extension SendRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SendRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: SendRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: SendRequestMessageType? = nil
    ) -> SendRequestMessage {
        return SendRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// 逐字段对应 D1 KernelInput（D1 v3.5 §2），与 §3.4 interrupt 的 input 字段共享同一判别联合结构，无新增/无精简。
// MARK: - SendRequestMessagePayload
public struct SendRequestMessagePayload: Codable {
    public let input: Input

    public enum CodingKeys: String, CodingKey {
        case input = "input"
    }

    public init(input: Input) {
        self.input = input
    }
}

// MARK: SendRequestMessagePayload convenience initializers and mutators

public extension SendRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SendRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        input: Input? = nil
    ) -> SendRequestMessagePayload {
        return SendRequestMessagePayload(
            input: input ?? self.input
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// D1 v3.5 §2 KernelInput 判别联合，逐字对应 D2 v3 §3.2 SendRequestPayload.input 同款结构。
///
/// 仅 mode:'steer'（新内容）或 mode:'abort_and_resend'（重发内容）时需要；mode:'cancel' 应省略。
// MARK: - Input
public struct Input: Codable {
    public let kind: InputKind
    public let text: String?
    public let parts: [Part]?

    public enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case text = "text"
        case parts = "parts"
    }

    public init(kind: InputKind, text: String?, parts: [Part]?) {
        self.kind = kind
        self.text = text
        self.parts = parts
    }
}

// MARK: Input convenience initializers and mutators

public extension Input {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Input.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        kind: InputKind? = nil,
        text: String?? = nil,
        parts: [Part]?? = nil
    ) -> Input {
        return Input(
            kind: kind ?? self.kind,
            text: text ?? self.text,
            parts: parts ?? self.parts
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum InputKind: String, Codable {
    case structured = "structured"
    case text = "text"
}

// MARK: - Part
public struct Part: Codable {
    public let kind: PartKind
    public let text: String?
    public let mimeType: String?
    /// 文件系统坐标空间未裁决——D1 F-15 开放项，D2 已固化字段上线（D2 v3 §9.2 第 7 条）。
    public let path: String?

    public enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case text = "text"
        case mimeType = "mimeType"
        case path = "path"
    }

    public init(kind: PartKind, text: String?, mimeType: String?, path: String?) {
        self.kind = kind
        self.text = text
        self.mimeType = mimeType
        self.path = path
    }
}

// MARK: Part convenience initializers and mutators

public extension Part {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Part.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        kind: PartKind? = nil,
        text: String?? = nil,
        mimeType: String?? = nil,
        path: String?? = nil
    ) -> Part {
        return Part(
            kind: kind ?? self.kind,
            text: text ?? self.text,
            mimeType: mimeType ?? self.mimeType,
            path: path ?? self.path
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum PartKind: String, Codable {
    case fileRef = "file_ref"
    case text = "text"
}

public enum SendRequestMessageType: String, Codable {
    case reqSend = "req.send"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - SubscribeRequestMessage
public struct SubscribeRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: EmptyPayload
    public let sentAt: Date
    public let sessionID: String
    public let type: SubscribeRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: EmptyPayload, sentAt: Date, sessionID: String, type: SubscribeRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: SubscribeRequestMessage convenience initializers and mutators

public extension SubscribeRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SubscribeRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: EmptyPayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: SubscribeRequestMessageType? = nil
    ) -> SubscribeRequestMessage {
        return SubscribeRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - EmptyPayload
public struct EmptyPayload: Codable {

    public init() {
    }
}

// MARK: EmptyPayload convenience initializers and mutators

public extension EmptyPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(EmptyPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
    ) -> EmptyPayload {
        return EmptyPayload(
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum SubscribeRequestMessageType: String, Codable {
    case reqSubscribe = "req.subscribe"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - InterruptRequestMessage
public struct InterruptRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: InterruptRequestMessagePayload
    public let sentAt: Date
    public let sessionID: String
    public let type: InterruptRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: InterruptRequestMessagePayload, sentAt: Date, sessionID: String, type: InterruptRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: InterruptRequestMessage convenience initializers and mutators

public extension InterruptRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(InterruptRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: InterruptRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: InterruptRequestMessageType? = nil
    ) -> InterruptRequestMessage {
        return InterruptRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - InterruptRequestMessagePayload
public struct InterruptRequestMessagePayload: Codable {
    /// 仅 mode:'steer'（新内容）或 mode:'abort_and_resend'（重发内容）时需要；mode:'cancel' 应省略。
    public let input: Input?
    public let mode: Mode
    /// 仅在 mode:'abort_and_resend' 且需要精确定向某个 run 时有意义。
    public let runID: String?

    public enum CodingKeys: String, CodingKey {
        case input = "input"
        case mode = "mode"
        case runID = "runId"
    }

    public init(input: Input?, mode: Mode, runID: String?) {
        self.input = input
        self.mode = mode
        self.runID = runID
    }
}

// MARK: InterruptRequestMessagePayload convenience initializers and mutators

public extension InterruptRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(InterruptRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        input: Input?? = nil,
        mode: Mode? = nil,
        runID: String?? = nil
    ) -> InterruptRequestMessagePayload {
        return InterruptRequestMessagePayload(
            input: input ?? self.input,
            mode: mode ?? self.mode,
            runID: runID ?? self.runID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Mode: String, Codable {
    case abortAndResend = "abort_and_resend"
    case cancel = "cancel"
    case steer = "steer"
}

public enum InterruptRequestMessageType: String, Codable {
    case reqInterrupt = "req.interrupt"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - StopRequestMessage
public struct StopRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: EmptyPayload
    public let sentAt: Date
    public let sessionID: String
    public let type: StopRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: EmptyPayload, sentAt: Date, sessionID: String, type: StopRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: StopRequestMessage convenience initializers and mutators

public extension StopRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(StopRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: EmptyPayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: StopRequestMessageType? = nil
    ) -> StopRequestMessage {
        return StopRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum StopRequestMessageType: String, Codable {
    case reqStop = "req.stop"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - RespondApprovalRequestMessage
public struct RespondApprovalRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: RespondApprovalRequestMessagePayload
    public let sentAt: Date
    public let sessionID: String
    public let type: RespondApprovalRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: RespondApprovalRequestMessagePayload, sentAt: Date, sessionID: String, type: RespondApprovalRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: RespondApprovalRequestMessage convenience initializers and mutators

public extension RespondApprovalRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(RespondApprovalRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: RespondApprovalRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: RespondApprovalRequestMessageType? = nil
    ) -> RespondApprovalRequestMessage {
        return RespondApprovalRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - RespondApprovalRequestMessagePayload
public struct RespondApprovalRequestMessagePayload: Codable {
    public let decision: Decision
    public let reqID: String

    public enum CodingKeys: String, CodingKey {
        case decision = "decision"
        case reqID = "reqId"
    }

    public init(decision: Decision, reqID: String) {
        self.decision = decision
        self.reqID = reqID
    }
}

// MARK: RespondApprovalRequestMessagePayload convenience initializers and mutators

public extension RespondApprovalRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(RespondApprovalRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        decision: Decision? = nil,
        reqID: String? = nil
    ) -> RespondApprovalRequestMessagePayload {
        return RespondApprovalRequestMessagePayload(
            decision: decision ?? self.decision,
            reqID: reqID ?? self.reqID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// D1 v3.5 §2.6 新增：由 capabilities().approvalDecisionKinds 门控，未声明支持时实现须同步拒绝
/// unsupported_approval_decision，不得静默降级为 allow_once。
// MARK: - Decision
public struct Decision: Codable {
    public let outcome: ApprovalDecisionKindElement
    public let updatedInput: JSONAny?
    public let scope: String?
    public let reason: String?

    public enum CodingKeys: String, CodingKey {
        case outcome = "outcome"
        case updatedInput = "updatedInput"
        case scope = "scope"
        case reason = "reason"
    }

    public init(outcome: ApprovalDecisionKindElement, updatedInput: JSONAny?, scope: String?, reason: String?) {
        self.outcome = outcome
        self.updatedInput = updatedInput
        self.scope = scope
        self.reason = reason
    }
}

// MARK: Decision convenience initializers and mutators

public extension Decision {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Decision.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        outcome: ApprovalDecisionKindElement? = nil,
        updatedInput: JSONAny?? = nil,
        scope: String?? = nil,
        reason: String?? = nil
    ) -> Decision {
        return Decision(
            outcome: outcome ?? self.outcome,
            updatedInput: updatedInput ?? self.updatedInput,
            scope: scope ?? self.scope,
            reason: reason ?? self.reason
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum ApprovalDecisionKindElement: String, Codable {
    case allowAlways = "allow_always"
    case allowOnce = "allow_once"
    case allowSession = "allow_session"
    case deny = "deny"
}

public enum RespondApprovalRequestMessageType: String, Codable {
    case reqRespondApproval = "req.respondApproval"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - CapabilitiesRequestMessage
public struct CapabilitiesRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: CapabilitiesRequestMessagePayload
    public let sentAt: Date
    /// 可选——D1 capabilities(session?: SessionHandle) 的可选参数，同 createSession 并列为本联合仅有的两个例外。
    public let sessionID: String?
    public let type: CapabilitiesRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: CapabilitiesRequestMessagePayload, sentAt: Date, sessionID: String?, type: CapabilitiesRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: CapabilitiesRequestMessage convenience initializers and mutators

public extension CapabilitiesRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilitiesRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: CapabilitiesRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String?? = nil,
        type: CapabilitiesRequestMessageType? = nil
    ) -> CapabilitiesRequestMessage {
        return CapabilitiesRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - CapabilitiesRequestMessagePayload
public struct CapabilitiesRequestMessagePayload: Codable {
    /// UI 可选声明自己认识的 wire 协议版本集合（如 ["kernelport/1"]），供 §7.2 握手协商流程使用（v3 新增，消解 codex T-017 HIGH#3）。
    public let supportedProtocolVersions: [String]?

    public enum CodingKeys: String, CodingKey {
        case supportedProtocolVersions = "supportedProtocolVersions"
    }

    public init(supportedProtocolVersions: [String]?) {
        self.supportedProtocolVersions = supportedProtocolVersions
    }
}

// MARK: CapabilitiesRequestMessagePayload convenience initializers and mutators

public extension CapabilitiesRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilitiesRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        supportedProtocolVersions: [String]?? = nil
    ) -> CapabilitiesRequestMessagePayload {
        return CapabilitiesRequestMessagePayload(
            supportedProtocolVersions: supportedProtocolVersions ?? self.supportedProtocolVersions
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CapabilitiesRequestMessageType: String, Codable {
    case reqCapabilities = "req.capabilities"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref 片段』的已知缺陷（见
/// create-session.schema.json 同处注释），语义与 allOf 版本等价。
// MARK: - QueryBillingRequestMessage
public struct QueryBillingRequestMessage: Codable {
    public let direction: CreateSessionRequestMessageDirection
    public let id: String
    public let payload: QueryBillingRequestMessagePayload
    public let sentAt: Date
    public let sessionID: String
    public let type: QueryBillingRequestMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case id = "id"
        case payload = "payload"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: CreateSessionRequestMessageDirection, id: String, payload: QueryBillingRequestMessagePayload, sentAt: Date, sessionID: String, type: QueryBillingRequestMessageType) {
        self.direction = direction
        self.id = id
        self.payload = payload
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: QueryBillingRequestMessage convenience initializers and mutators

public extension QueryBillingRequestMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(QueryBillingRequestMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: CreateSessionRequestMessageDirection? = nil,
        id: String? = nil,
        payload: QueryBillingRequestMessagePayload? = nil,
        sentAt: Date? = nil,
        sessionID: String? = nil,
        type: QueryBillingRequestMessageType? = nil
    ) -> QueryBillingRequestMessage {
        return QueryBillingRequestMessage(
            direction: direction ?? self.direction,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - QueryBillingRequestMessagePayload
public struct QueryBillingRequestMessagePayload: Codable {
    public let window: Window?

    public enum CodingKeys: String, CodingKey {
        case window = "window"
    }

    public init(window: Window?) {
        self.window = window
    }
}

// MARK: QueryBillingRequestMessagePayload convenience initializers and mutators

public extension QueryBillingRequestMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(QueryBillingRequestMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        window: Window?? = nil
    ) -> QueryBillingRequestMessagePayload {
        return QueryBillingRequestMessagePayload(
            window: window ?? self.window
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Window
public struct Window: Codable {
    public let from: Date
    public let to: Date

    public enum CodingKeys: String, CodingKey {
        case from = "from"
        case to = "to"
    }

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }
}

// MARK: Window convenience initializers and mutators

public extension Window {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Window.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        from: Date? = nil,
        to: Date? = nil
    ) -> Window {
        return Window(
            from: from ?? self.from,
            to: to ?? self.to
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum QueryBillingRequestMessageType: String, Codable {
    case reqQueryBilling = "req.queryBilling"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（allOf 成员被直接忽略、字段静默丢失，见 methods/create-session.schema.json 同处注释 +
/// CODEGEN-FINDINGS.md），语义与 allOf 版本等价。
// MARK: - MessageDeltaEventMessage
public struct MessageDeltaEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: MessageDeltaEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: MessageDeltaEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: MessageDeltaEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: MessageDeltaEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: MessageDeltaEventMessage convenience initializers and mutators

public extension MessageDeltaEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(MessageDeltaEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: MessageDeltaEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: MessageDeltaEventMessageType? = nil
    ) -> MessageDeltaEventMessage {
        return MessageDeltaEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum MessageDeltaEventMessageDirection: String, Codable {
    case event = "event"
}

// MARK: - MessageDeltaEventMessagePayload
public struct MessageDeltaEventMessagePayload: Codable {
    public let delta: String
    public let index: Int
    public let role: Role

    public enum CodingKeys: String, CodingKey {
        case delta = "delta"
        case index = "index"
        case role = "role"
    }

    public init(delta: String, index: Int, role: Role) {
        self.delta = delta
        self.index = index
        self.role = role
    }
}

// MARK: MessageDeltaEventMessagePayload convenience initializers and mutators

public extension MessageDeltaEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(MessageDeltaEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        delta: String? = nil,
        index: Int? = nil,
        role: Role? = nil
    ) -> MessageDeltaEventMessagePayload {
        return MessageDeltaEventMessagePayload(
            delta: delta ?? self.delta,
            index: index ?? self.index,
            role: role ?? self.role
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Role: String, Codable {
    case assistant = "assistant"
}

public enum MessageDeltaEventMessageType: String, Codable {
    case evtMessageDelta = "evt.message.delta"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - ThinkingEventMessage
public struct ThinkingEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ThinkingEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ThinkingEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ThinkingEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ThinkingEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ThinkingEventMessage convenience initializers and mutators

public extension ThinkingEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ThinkingEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ThinkingEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ThinkingEventMessageType? = nil
    ) -> ThinkingEventMessage {
        return ThinkingEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ThinkingEventMessagePayload
public struct ThinkingEventMessagePayload: Codable {
    public let delta: String
    public let visibility: Visibility

    public enum CodingKeys: String, CodingKey {
        case delta = "delta"
        case visibility = "visibility"
    }

    public init(delta: String, visibility: Visibility) {
        self.delta = delta
        self.visibility = visibility
    }
}

// MARK: ThinkingEventMessagePayload convenience initializers and mutators

public extension ThinkingEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ThinkingEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        delta: String? = nil,
        visibility: Visibility? = nil
    ) -> ThinkingEventMessagePayload {
        return ThinkingEventMessagePayload(
            delta: delta ?? self.delta,
            visibility: visibility ?? self.visibility
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Visibility: String, Codable {
    case raw = "raw"
    case summary = "summary"
}

public enum ThinkingEventMessageType: String, Codable {
    case evtThinking = "evt.thinking"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - ToolCallEventMessage
public struct ToolCallEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ToolCallEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ToolCallEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ToolCallEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ToolCallEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ToolCallEventMessage convenience initializers and mutators

public extension ToolCallEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ToolCallEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ToolCallEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ToolCallEventMessageType? = nil
    ) -> ToolCallEventMessage {
        return ToolCallEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ToolCallEventMessagePayload
public struct ToolCallEventMessagePayload: Codable {
    public let input: JSONAny
    public let name: String
    public let status: Status
    public let toolCallID: String

    public enum CodingKeys: String, CodingKey {
        case input = "input"
        case name = "name"
        case status = "status"
        case toolCallID = "toolCallId"
    }

    public init(input: JSONAny, name: String, status: Status, toolCallID: String) {
        self.input = input
        self.name = name
        self.status = status
        self.toolCallID = toolCallID
    }
}

// MARK: ToolCallEventMessagePayload convenience initializers and mutators

public extension ToolCallEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ToolCallEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        input: JSONAny? = nil,
        name: String? = nil,
        status: Status? = nil,
        toolCallID: String? = nil
    ) -> ToolCallEventMessagePayload {
        return ToolCallEventMessagePayload(
            input: input ?? self.input,
            name: name ?? self.name,
            status: status ?? self.status,
            toolCallID: toolCallID ?? self.toolCallID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Status: String, Codable {
    case started = "started"
}

public enum ToolCallEventMessageType: String, Codable {
    case evtToolCall = "evt.tool_call"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - ToolResultEventMessage
public struct ToolResultEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ToolResultEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ToolResultEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ToolResultEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ToolResultEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ToolResultEventMessage convenience initializers and mutators

public extension ToolResultEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ToolResultEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ToolResultEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ToolResultEventMessageType? = nil
    ) -> ToolResultEventMessage {
        return ToolResultEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ToolResultEventMessagePayload
public struct ToolResultEventMessagePayload: Codable {
    public let durationMS: Int?
    public let isError: Bool
    public let output: JSONAny
    public let toolCallID: String

    public enum CodingKeys: String, CodingKey {
        case durationMS = "durationMs"
        case isError = "isError"
        case output = "output"
        case toolCallID = "toolCallId"
    }

    public init(durationMS: Int?, isError: Bool, output: JSONAny, toolCallID: String) {
        self.durationMS = durationMS
        self.isError = isError
        self.output = output
        self.toolCallID = toolCallID
    }
}

// MARK: ToolResultEventMessagePayload convenience initializers and mutators

public extension ToolResultEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ToolResultEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        durationMS: Int?? = nil,
        isError: Bool? = nil,
        output: JSONAny? = nil,
        toolCallID: String? = nil
    ) -> ToolResultEventMessagePayload {
        return ToolResultEventMessagePayload(
            durationMS: durationMS ?? self.durationMS,
            isError: isError ?? self.isError,
            output: output ?? self.output,
            toolCallID: toolCallID ?? self.toolCallID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum ToolResultEventMessageType: String, Codable {
    case evtToolResult = "evt.tool_result"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref
/// 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。runId 在本事件类型上必填（D2 v3 §4 表格），与其余 9 个 runId 可选的事件类型不同。
// MARK: - ApprovalRequestEventMessage
public struct ApprovalRequestEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ApprovalRequestEventMessagePayload
    public let runID: String
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ApprovalRequestEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ApprovalRequestEventMessagePayload, runID: String, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ApprovalRequestEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ApprovalRequestEventMessage convenience initializers and mutators

public extension ApprovalRequestEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ApprovalRequestEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ApprovalRequestEventMessagePayload? = nil,
        runID: String? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ApprovalRequestEventMessageType? = nil
    ) -> ApprovalRequestEventMessage {
        return ApprovalRequestEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ApprovalRequestEventMessagePayload
public struct ApprovalRequestEventMessagePayload: Codable {
    public let kind: KindElement
    public let payload: JSONAny
    public let proposedDecision: ProposedDecision?
    /// respondApproval() 的关联主键（= 内核 approval id，非 toolCallId）。
    public let reqID: String
    /// openclaw 'documented'；hermes 'best_effort'（约 60s，非官方承诺）——UI 不得在 'best_effort' 上做精确倒计时。
    public let timeoutAuthority: TimeoutAuthority
    public let timeoutMS: Int
    /// 关联到对应 evt.tool_call 的 toolCallId，审计/展示用，非 respondApproval 关联键。
    public let toolCallID: String

    public enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case payload = "payload"
        case proposedDecision = "proposedDecision"
        case reqID = "reqId"
        case timeoutAuthority = "timeoutAuthority"
        case timeoutMS = "timeoutMs"
        case toolCallID = "toolCallId"
    }

    public init(kind: KindElement, payload: JSONAny, proposedDecision: ProposedDecision?, reqID: String, timeoutAuthority: TimeoutAuthority, timeoutMS: Int, toolCallID: String) {
        self.kind = kind
        self.payload = payload
        self.proposedDecision = proposedDecision
        self.reqID = reqID
        self.timeoutAuthority = timeoutAuthority
        self.timeoutMS = timeoutMS
        self.toolCallID = toolCallID
    }
}

// MARK: ApprovalRequestEventMessagePayload convenience initializers and mutators

public extension ApprovalRequestEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ApprovalRequestEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        kind: KindElement? = nil,
        payload: JSONAny? = nil,
        proposedDecision: ProposedDecision?? = nil,
        reqID: String? = nil,
        timeoutAuthority: TimeoutAuthority? = nil,
        timeoutMS: Int? = nil,
        toolCallID: String? = nil
    ) -> ApprovalRequestEventMessagePayload {
        return ApprovalRequestEventMessagePayload(
            kind: kind ?? self.kind,
            payload: payload ?? self.payload,
            proposedDecision: proposedDecision ?? self.proposedDecision,
            reqID: reqID ?? self.reqID,
            timeoutAuthority: timeoutAuthority ?? self.timeoutAuthority,
            timeoutMS: timeoutMS ?? self.timeoutMS,
            toolCallID: toolCallID ?? self.toolCallID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum KindElement: String, Codable {
    case exec = "exec"
    case fileWrite = "file_write"
    case mcp = "mcp"
    case sandbox = "sandbox"
    case tool = "tool"
}

public enum ProposedDecision: String, Codable {
    case allowAlways = "allow_always"
    case allowOnce = "allow_once"
    case deny = "deny"
}

/// openclaw 'documented'；hermes 'best_effort'（约 60s，非官方承诺）——UI 不得在 'best_effort' 上做精确倒计时。
public enum TimeoutAuthority: String, Codable {
    case bestEffort = "best_effort"
    case documented = "documented"
}

public enum ApprovalRequestEventMessageType: String, Codable {
    case evtApprovalRequest = "evt.approval_request"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - ErrorEventMessage
public struct ErrorEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ErrorEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ErrorEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ErrorEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ErrorEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ErrorEventMessage convenience initializers and mutators

public extension ErrorEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ErrorEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ErrorEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ErrorEventMessageType? = nil
    ) -> ErrorEventMessage {
        return ErrorEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ErrorEventMessagePayload
public struct ErrorEventMessagePayload: Codable {
    public let code: PayloadCode
    public let message: String
    /// 调试参考，非契约稳定字段，UI 不得对其分支判断。
    public let nativeCode: String?
    public let recoverable: Recoverable

    public enum CodingKeys: String, CodingKey {
        case code = "code"
        case message = "message"
        case nativeCode = "nativeCode"
        case recoverable = "recoverable"
    }

    public init(code: PayloadCode, message: String, nativeCode: String?, recoverable: Recoverable) {
        self.code = code
        self.message = message
        self.nativeCode = nativeCode
        self.recoverable = recoverable
    }
}

// MARK: ErrorEventMessagePayload convenience initializers and mutators

public extension ErrorEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ErrorEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        code: PayloadCode? = nil,
        message: String? = nil,
        nativeCode: String?? = nil,
        recoverable: Recoverable? = nil
    ) -> ErrorEventMessagePayload {
        return ErrorEventMessagePayload(
            code: code ?? self.code,
            message: message ?? self.message,
            nativeCode: nativeCode ?? self.nativeCode,
            recoverable: recoverable ?? self.recoverable
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// ErrorEvent.code 的唯一契约稳定取值集合（D1 v3-kernel-spec §9，D1 v3.5 §9.1 声明本枚举『保持不变，同 v3.1』）。
public enum PayloadCode: String, Codable {
    case approvalTimeout = "approval_timeout"
    case authFailed = "auth_failed"
    case kernelCrashed = "kernel_crashed"
    case networkLost = "network_lost"
    case rateLimited = "rate_limited"
    case sandboxDenied = "sandbox_denied"
    case unknown = "unknown"
}

public enum Recoverable: String, Codable {
    case none = "none"
    case run = "run"
    case session = "session"
}

public enum ErrorEventMessageType: String, Codable {
    case evtError = "evt.error"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部 $ref
/// 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。runId 在本事件类型上必填（D2 v3 §4 表格），与其余 9 个 runId 可选的事件类型不同。
// MARK: - TurnCompleteEventMessage
public struct TurnCompleteEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: TurnCompleteEventMessagePayload
    public let runID: String
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: TurnCompleteEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: TurnCompleteEventMessagePayload, runID: String, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: TurnCompleteEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: TurnCompleteEventMessage convenience initializers and mutators

public extension TurnCompleteEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(TurnCompleteEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: TurnCompleteEventMessagePayload? = nil,
        runID: String? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: TurnCompleteEventMessageType? = nil
    ) -> TurnCompleteEventMessage {
        return TurnCompleteEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - TurnCompleteEventMessagePayload
public struct TurnCompleteEventMessagePayload: Codable {
    /// openclaw 走原生 sessions.steer 完成 mode:'abort_and_resend' 时同样产出本标注（该 RPC 本质也是
    /// abort+resend）；mode:'steer'（soft，仅 openclaw）不产生 degraded——它是真正的同 run
    /// 注入，没有『这次转向丢弃了未产出内容』需要告知。
    public let degraded: Degraded?
    public let forceResolvedApprovals: [String]?
    public let stopReason: StopReason
    public let usage: Usage?

    public enum CodingKeys: String, CodingKey {
        case degraded = "degraded"
        case forceResolvedApprovals = "forceResolvedApprovals"
        case stopReason = "stopReason"
        case usage = "usage"
    }

    public init(degraded: Degraded?, forceResolvedApprovals: [String]?, stopReason: StopReason, usage: Usage?) {
        self.degraded = degraded
        self.forceResolvedApprovals = forceResolvedApprovals
        self.stopReason = stopReason
        self.usage = usage
    }
}

// MARK: TurnCompleteEventMessagePayload convenience initializers and mutators

public extension TurnCompleteEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(TurnCompleteEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        degraded: Degraded?? = nil,
        forceResolvedApprovals: [String]?? = nil,
        stopReason: StopReason? = nil,
        usage: Usage?? = nil
    ) -> TurnCompleteEventMessagePayload {
        return TurnCompleteEventMessagePayload(
            degraded: degraded ?? self.degraded,
            forceResolvedApprovals: forceResolvedApprovals ?? self.forceResolvedApprovals,
            stopReason: stopReason ?? self.stopReason,
            usage: usage ?? self.usage
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// openclaw 走原生 sessions.steer 完成 mode:'abort_and_resend' 时同样产出本标注（该 RPC 本质也是
/// abort+resend）；mode:'steer'（soft，仅 openclaw）不产生 degraded——它是真正的同 run
/// 注入，没有『这次转向丢弃了未产出内容』需要告知。
// MARK: - Degraded
public struct Degraded: Codable {
    public let kind: DegradedKind

    public enum CodingKeys: String, CodingKey {
        case kind = "kind"
    }

    public init(kind: DegradedKind) {
        self.kind = kind
    }
}

// MARK: Degraded convenience initializers and mutators

public extension Degraded {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Degraded.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        kind: DegradedKind? = nil
    ) -> Degraded {
        return Degraded(
            kind: kind ?? self.kind
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DegradedKind: String, Codable {
    case abortAndResend = "abort_and_resend"
}

public enum StopReason: String, Codable {
    case cancelled = "cancelled"
    case completed = "completed"
    case error = "error"
    case maxTurns = "max_turns"
}

// MARK: - Usage
public struct Usage: Codable {
    public let inputTokens: Int?
    public let outputTokens: Int?

    public enum CodingKeys: String, CodingKey {
        case inputTokens = "inputTokens"
        case outputTokens = "outputTokens"
    }

    public init(inputTokens: Int?, outputTokens: Int?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: Usage convenience initializers and mutators

public extension Usage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Usage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        inputTokens: Int?? = nil,
        outputTokens: Int?? = nil
    ) -> Usage {
        return Usage(
            inputTokens: inputTokens ?? self.inputTokens,
            outputTokens: outputTokens ?? self.outputTokens
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum TurnCompleteEventMessageType: String, Codable {
    case evtTurnComplete = "evt.turn_complete"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - SessionEndEventMessage
public struct SessionEndEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: SessionEndEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: SessionEndEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: SessionEndEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: SessionEndEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: SessionEndEventMessage convenience initializers and mutators

public extension SessionEndEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SessionEndEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: SessionEndEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: SessionEndEventMessageType? = nil
    ) -> SessionEndEventMessage {
        return SessionEndEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - SessionEndEventMessagePayload
public struct SessionEndEventMessagePayload: Codable {
    public let reason: PurpleReason

    public enum CodingKeys: String, CodingKey {
        case reason = "reason"
    }

    public init(reason: PurpleReason) {
        self.reason = reason
    }
}

// MARK: SessionEndEventMessagePayload convenience initializers and mutators

public extension SessionEndEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SessionEndEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        reason: PurpleReason? = nil
    ) -> SessionEndEventMessagePayload {
        return SessionEndEventMessagePayload(
            reason: reason ?? self.reason
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum PurpleReason: String, Codable {
    case error = "error"
    case kernelExited = "kernel_exited"
    case stopped = "stopped"
    case transportClosed = "transport_closed"
}

public enum SessionEndEventMessageType: String, Codable {
    case evtSessionEnd = "evt.session_end"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - CapabilityChangedEventMessage
public struct CapabilityChangedEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: CapabilityChangedEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: CapabilityChangedEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: CapabilityChangedEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: CapabilityChangedEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: CapabilityChangedEventMessage convenience initializers and mutators

public extension CapabilityChangedEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilityChangedEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: CapabilityChangedEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: CapabilityChangedEventMessageType? = nil
    ) -> CapabilityChangedEventMessage {
        return CapabilityChangedEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - CapabilityChangedEventMessagePayload
public struct CapabilityChangedEventMessagePayload: Codable {
    public let capabilities: Capabilit
    public let reason: String?
    public let source: Source

    public enum CodingKeys: String, CodingKey {
        case capabilities = "capabilities"
        case reason = "reason"
        case source = "source"
    }

    public init(capabilities: Capabilit, reason: String?, source: Source) {
        self.capabilities = capabilities
        self.reason = reason
        self.source = source
    }
}

// MARK: CapabilityChangedEventMessagePayload convenience initializers and mutators

public extension CapabilityChangedEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilityChangedEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        capabilities: Capabilit? = nil,
        reason: String?? = nil,
        source: Source? = nil
    ) -> CapabilityChangedEventMessagePayload {
        return CapabilityChangedEventMessagePayload(
            capabilities: capabilities ?? self.capabilities,
            reason: reason ?? self.reason,
            source: source ?? self.source
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// evt.capability_changed 专属的 wire 快照类型（D2 v3 v3-r1/r2，消解 codex T-018/T-019）：排除
/// protocolVersion——该字段已在握手期传输过一次且连接内恒定，逐事件重复既无信息增量也违反
/// §7.1『不再逐事件重复』规则。反序列化时由适配器用同一连接协商值同时回填事件基字段与本嵌套 descriptor 的 protocolVersion（D2 v3 §4
/// 反序列化重建规则扩展）。
// MARK: - Capabilit
public struct Capabilit: Codable {
    public let approvalDecisionKinds: [ApprovalDecisionKindElement]
    public let approvalGranularity: ApprovalGranularity
    public let approvalKinds: [KindElement]
    public let billingAttribution: Attribution
    public let interruptModes: [Mode]
    public let kernel: Kernel
    public let kernelVersion: String?
    public let sandboxLevels: [Sandbox]?
    public let sessionResume: Bool
    public let snapshotAt: Date
    public let streamingGranularity: StreamingGranularity
    public let thinkingVisibility: ThinkingVisibility
    public let tools: CapabilitiesTools
    public let usageReporting: UsageReporting

    public enum CodingKeys: String, CodingKey {
        case approvalDecisionKinds = "approvalDecisionKinds"
        case approvalGranularity = "approvalGranularity"
        case approvalKinds = "approvalKinds"
        case billingAttribution = "billingAttribution"
        case interruptModes = "interruptModes"
        case kernel = "kernel"
        case kernelVersion = "kernelVersion"
        case sandboxLevels = "sandboxLevels"
        case sessionResume = "sessionResume"
        case snapshotAt = "snapshotAt"
        case streamingGranularity = "streamingGranularity"
        case thinkingVisibility = "thinkingVisibility"
        case tools = "tools"
        case usageReporting = "usageReporting"
    }

    public init(approvalDecisionKinds: [ApprovalDecisionKindElement], approvalGranularity: ApprovalGranularity, approvalKinds: [KindElement], billingAttribution: Attribution, interruptModes: [Mode], kernel: Kernel, kernelVersion: String?, sandboxLevels: [Sandbox]?, sessionResume: Bool, snapshotAt: Date, streamingGranularity: StreamingGranularity, thinkingVisibility: ThinkingVisibility, tools: CapabilitiesTools, usageReporting: UsageReporting) {
        self.approvalDecisionKinds = approvalDecisionKinds
        self.approvalGranularity = approvalGranularity
        self.approvalKinds = approvalKinds
        self.billingAttribution = billingAttribution
        self.interruptModes = interruptModes
        self.kernel = kernel
        self.kernelVersion = kernelVersion
        self.sandboxLevels = sandboxLevels
        self.sessionResume = sessionResume
        self.snapshotAt = snapshotAt
        self.streamingGranularity = streamingGranularity
        self.thinkingVisibility = thinkingVisibility
        self.tools = tools
        self.usageReporting = usageReporting
    }
}

// MARK: Capabilit convenience initializers and mutators

public extension Capabilit {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Capabilit.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        approvalDecisionKinds: [ApprovalDecisionKindElement]? = nil,
        approvalGranularity: ApprovalGranularity? = nil,
        approvalKinds: [KindElement]? = nil,
        billingAttribution: Attribution? = nil,
        interruptModes: [Mode]? = nil,
        kernel: Kernel? = nil,
        kernelVersion: String?? = nil,
        sandboxLevels: [Sandbox]?? = nil,
        sessionResume: Bool? = nil,
        snapshotAt: Date? = nil,
        streamingGranularity: StreamingGranularity? = nil,
        thinkingVisibility: ThinkingVisibility? = nil,
        tools: CapabilitiesTools? = nil,
        usageReporting: UsageReporting? = nil
    ) -> Capabilit {
        return Capabilit(
            approvalDecisionKinds: approvalDecisionKinds ?? self.approvalDecisionKinds,
            approvalGranularity: approvalGranularity ?? self.approvalGranularity,
            approvalKinds: approvalKinds ?? self.approvalKinds,
            billingAttribution: billingAttribution ?? self.billingAttribution,
            interruptModes: interruptModes ?? self.interruptModes,
            kernel: kernel ?? self.kernel,
            kernelVersion: kernelVersion ?? self.kernelVersion,
            sandboxLevels: sandboxLevels ?? self.sandboxLevels,
            sessionResume: sessionResume ?? self.sessionResume,
            snapshotAt: snapshotAt ?? self.snapshotAt,
            streamingGranularity: streamingGranularity ?? self.streamingGranularity,
            thinkingVisibility: thinkingVisibility ?? self.thinkingVisibility,
            tools: tools ?? self.tools,
            usageReporting: usageReporting ?? self.usageReporting
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum ApprovalGranularity: String, Codable {
    case batch = "batch"
    case perCommand = "per-command"
    case perTool = "per-tool"
}

public enum Attribution: String, Codable {
    case session = "session"
    case userTenantAggregate = "user_tenant_aggregate"
}

public enum Kernel: String, Codable {
    case hermes = "hermes"
    case openclaw = "openclaw"
}

public enum StreamingGranularity: String, Codable {
    case chunk = "chunk"
    case messageOnly = "message-only"
    case tokenDelta = "token-delta"
}

public enum ThinkingVisibility: String, Codable {
    case none = "none"
    case raw = "raw"
    case summary = "summary"
}

// MARK: - CapabilitiesTools
public struct CapabilitiesTools: Codable {
    public let discoverable: Bool
    public let names: [String]?

    public enum CodingKeys: String, CodingKey {
        case discoverable = "discoverable"
        case names = "names"
    }

    public init(discoverable: Bool, names: [String]?) {
        self.discoverable = discoverable
        self.names = names
    }
}

// MARK: CapabilitiesTools convenience initializers and mutators

public extension CapabilitiesTools {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilitiesTools.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        discoverable: Bool? = nil,
        names: [String]?? = nil
    ) -> CapabilitiesTools {
        return CapabilitiesTools(
            discoverable: discoverable ?? self.discoverable,
            names: names ?? self.names
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum UsageReporting: String, Codable {
    case authoritative = "authoritative"
    case bestEffort = "best-effort"
    case none = "none"
}

public enum Source: String, Codable {
    case kernelErrorInferred = "kernel_error_inferred"
    case serverOverride = "server_override"
}

public enum CapabilityChangedEventMessageType: String, Codable {
    case evtCapabilityChanged = "evt.capability_changed"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - OperationCompletedEventMessage
public struct OperationCompletedEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: OperationCompletedEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: OperationCompletedEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: OperationCompletedEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: OperationCompletedEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: OperationCompletedEventMessage convenience initializers and mutators

public extension OperationCompletedEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(OperationCompletedEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: OperationCompletedEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: OperationCompletedEventMessageType? = nil
    ) -> OperationCompletedEventMessage {
        return OperationCompletedEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - OperationCompletedEventMessagePayload
public struct OperationCompletedEventMessagePayload: Codable {
    public let affectedRunID: String?
    public let detail: String?
    public let newRunID: String?
    public let operationID: String
    public let operationKind: OperationKind
    public let outcome: PayloadOutcome

    public enum CodingKeys: String, CodingKey {
        case affectedRunID = "affectedRunId"
        case detail = "detail"
        case newRunID = "newRunId"
        case operationID = "operationId"
        case operationKind = "operationKind"
        case outcome = "outcome"
    }

    public init(affectedRunID: String?, detail: String?, newRunID: String?, operationID: String, operationKind: OperationKind, outcome: PayloadOutcome) {
        self.affectedRunID = affectedRunID
        self.detail = detail
        self.newRunID = newRunID
        self.operationID = operationID
        self.operationKind = operationKind
        self.outcome = outcome
    }
}

// MARK: OperationCompletedEventMessagePayload convenience initializers and mutators

public extension OperationCompletedEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(OperationCompletedEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        affectedRunID: String?? = nil,
        detail: String?? = nil,
        newRunID: String?? = nil,
        operationID: String? = nil,
        operationKind: OperationKind? = nil,
        outcome: PayloadOutcome? = nil
    ) -> OperationCompletedEventMessagePayload {
        return OperationCompletedEventMessagePayload(
            affectedRunID: affectedRunID ?? self.affectedRunID,
            detail: detail ?? self.detail,
            newRunID: newRunID ?? self.newRunID,
            operationID: operationID ?? self.operationID,
            operationKind: operationKind ?? self.operationKind,
            outcome: outcome ?? self.outcome
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum OperationKind: String, Codable {
    case interrupt = "interrupt"
    case stop = "stop"
}

/// 已铸造 operationId 的 operation 终态七态（D1 v3.5 §2.4/§9.1）。res.interrupt/res.stop 的
/// result.outcome 与 evt.operation_completed.outcome 共享同一词汇表；stop()
/// 只可达其中三态子集（succeeded/timed_out/rejected，D1 §2.5），hard abort_and_resend 可达六态子集（全集去掉仅 soft
/// 可达的 submitted，D4 §4.2）——本枚举忠实保留全部七态，子集约束是文档级约束，不在 schema 层面按 method 拆分（同 D2 v3 §3.5
/// stop() 的既有处理方式）。
public enum PayloadOutcome: String, Codable {
    case abortedEffectUnknown = "aborted_effect_unknown"
    case abortedNoResend = "aborted_no_resend"
    case abortedResendFailed = "aborted_resend_failed"
    case rejected = "rejected"
    case submitted = "submitted"
    case succeeded = "succeeded"
    case timedOut = "timed_out"
}

public enum OperationCompletedEventMessageType: String, Codable {
    case evtOperationCompleted = "evt.operation_completed"
}

/// SG-1 深化：直接内联 sentAt/direction/seq/sessionId/runId/ts，不用 allOf——规避 quicktype 对『allOf 引用外部
/// $ref 片段』的已知缺陷（见 methods/create-session.schema.json 同处注释 + CODEGEN-FINDINGS.md），语义与 allOf
/// 版本等价。
// MARK: - ApprovalBufferResolvedEventMessage
public struct ApprovalBufferResolvedEventMessage: Codable {
    public let direction: MessageDeltaEventMessageDirection
    public let payload: ApprovalBufferResolvedEventMessagePayload
    public let runID: String?
    public let sentAt: Date
    public let seq: Int
    public let sessionID: String
    public let ts: Date
    public let type: ApprovalBufferResolvedEventMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case payload = "payload"
        case runID = "runId"
        case sentAt = "sentAt"
        case seq = "seq"
        case sessionID = "sessionId"
        case ts = "ts"
        case type = "type"
    }

    public init(direction: MessageDeltaEventMessageDirection, payload: ApprovalBufferResolvedEventMessagePayload, runID: String?, sentAt: Date, seq: Int, sessionID: String, ts: Date, type: ApprovalBufferResolvedEventMessageType) {
        self.direction = direction
        self.payload = payload
        self.runID = runID
        self.sentAt = sentAt
        self.seq = seq
        self.sessionID = sessionID
        self.ts = ts
        self.type = type
    }
}

// MARK: ApprovalBufferResolvedEventMessage convenience initializers and mutators

public extension ApprovalBufferResolvedEventMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ApprovalBufferResolvedEventMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: MessageDeltaEventMessageDirection? = nil,
        payload: ApprovalBufferResolvedEventMessagePayload? = nil,
        runID: String?? = nil,
        sentAt: Date? = nil,
        seq: Int? = nil,
        sessionID: String? = nil,
        ts: Date? = nil,
        type: ApprovalBufferResolvedEventMessageType? = nil
    ) -> ApprovalBufferResolvedEventMessage {
        return ApprovalBufferResolvedEventMessage(
            direction: direction ?? self.direction,
            payload: payload ?? self.payload,
            runID: runID ?? self.runID,
            sentAt: sentAt ?? self.sentAt,
            seq: seq ?? self.seq,
            sessionID: sessionID ?? self.sessionID,
            ts: ts ?? self.ts,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - ApprovalBufferResolvedEventMessagePayload
public struct ApprovalBufferResolvedEventMessagePayload: Codable {
    public let reason: FluffyReason
    public let reqID: String

    public enum CodingKeys: String, CodingKey {
        case reason = "reason"
        case reqID = "reqId"
    }

    public init(reason: FluffyReason, reqID: String) {
        self.reason = reason
        self.reqID = reqID
    }
}

// MARK: ApprovalBufferResolvedEventMessagePayload convenience initializers and mutators

public extension ApprovalBufferResolvedEventMessagePayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ApprovalBufferResolvedEventMessagePayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        reason: FluffyReason? = nil,
        reqID: String? = nil
    ) -> ApprovalBufferResolvedEventMessagePayload {
        return ApprovalBufferResolvedEventMessagePayload(
            reason: reason ?? self.reason,
            reqID: reqID ?? self.reqID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum FluffyReason: String, Codable {
    case bufferedTimeout = "buffered_timeout"
    case queueOverflow = "queue_overflow"
}

public enum ApprovalBufferResolvedEventMessageType: String, Codable {
    case evtApprovalBufferResolved = "evt.approval_buffer_resolved"
}

/// SG-1 深化：直接内联 sentAt/direction，不用 allOf——原写法虽不含 oneOf（本类型只有一种形状），但 SG-1 深化验证发现 quicktype
/// 对『allOf 引用外部 $ref 片段』本身就有独立于 oneOf 坍缩的缺陷（allOf 成员被直接忽略、字段静默丢失，见
/// CODEGEN-FINDINGS.md），故本类型同样改为直接内联，规避写法，语义与 allOf 版本等价。
// MARK: - UnknownResponseMessage
public struct UnknownResponseMessage: Codable {
    public let direction: UnknownResponseMessageDirection
    public let failure: Failure
    /// 允许缺失——触发条件已收紧为『原 request 本身不可辨认』，天然没有 id 可回填。
    public let id: String?
    public let sentAt: Date
    public let sessionID: String?
    public let type: UnknownResponseMessageType

    public enum CodingKeys: String, CodingKey {
        case direction = "direction"
        case failure = "failure"
        case id = "id"
        case sentAt = "sentAt"
        case sessionID = "sessionId"
        case type = "type"
    }

    public init(direction: UnknownResponseMessageDirection, failure: Failure, id: String?, sentAt: Date, sessionID: String?, type: UnknownResponseMessageType) {
        self.direction = direction
        self.failure = failure
        self.id = id
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.type = type
    }
}

// MARK: UnknownResponseMessage convenience initializers and mutators

public extension UnknownResponseMessage {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(UnknownResponseMessage.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        direction: UnknownResponseMessageDirection? = nil,
        failure: Failure? = nil,
        id: String?? = nil,
        sentAt: Date? = nil,
        sessionID: String?? = nil,
        type: UnknownResponseMessageType? = nil
    ) -> UnknownResponseMessage {
        return UnknownResponseMessage(
            direction: direction ?? self.direction,
            failure: failure ?? self.failure,
            id: id ?? self.id,
            sentAt: sentAt ?? self.sentAt,
            sessionID: sessionID ?? self.sessionID,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum UnknownResponseMessageDirection: String, Codable {
    case response = "response"
}

/// D2 专属、不出现在 D1 任何地方的消息层协议错误（D2 v3 §7.4）。unsupported_protocol_version
/// 仅在握手路径触发（res.capabilities 的 failure，D2 v3 §7.2 第 3
/// 步）；malformed_message/unknown_message_type 适用于任意方法的 request 本身损坏或 type 不可辨认的场景。已并入 §3.9 全部
/// 8 个具体方法 response 的 failure 联合以及 res.unknown 的 failure 类型。
// MARK: - Failure
public struct Failure: Codable {
    public let code: FailureCode
    public let detail: String?

    public enum CodingKeys: String, CodingKey {
        case code = "code"
        case detail = "detail"
    }

    public init(code: FailureCode, detail: String?) {
        self.code = code
        self.detail = detail
    }
}

// MARK: Failure convenience initializers and mutators

public extension Failure {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Failure.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        code: FailureCode? = nil,
        detail: String?? = nil
    ) -> Failure {
        return Failure(
            code: code ?? self.code,
            detail: detail ?? self.detail
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum FailureCode: String, Codable {
    case malformedMessage = "malformed_message"
    case unknownMessageType = "unknown_message_type"
    case unsupportedProtocolVersion = "unsupported_protocol_version"
}

public enum UnknownResponseMessageType: String, Codable {
    case resUnknown = "res.unknown"
}

/// 逐字段对应 D1 SessionHandle（D1 v3.5 §2）。kernel 字段的已知张力见 D2 v3 §9.2 第 1 条（S-08 回指，D1 INV-1 未裁决）。
// MARK: - CreateSessionResultPayload
public struct CreateSessionResultPayload: Codable {
    public let sessionHandle: SessionHandle

    public enum CodingKeys: String, CodingKey {
        case sessionHandle = "sessionHandle"
    }

    public init(sessionHandle: SessionHandle) {
        self.sessionHandle = sessionHandle
    }
}

// MARK: CreateSessionResultPayload convenience initializers and mutators

public extension CreateSessionResultPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CreateSessionResultPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        sessionHandle: SessionHandle? = nil
    ) -> CreateSessionResultPayload {
        return CreateSessionResultPayload(
            sessionHandle: sessionHandle ?? self.sessionHandle
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - SessionHandle
public struct SessionHandle: Codable {
    public let billing: Billing
    public let createdAt: Date
    public let kernel: Kernel
    public let kernelSessionID: String?
    public let sessionID: String

    public enum CodingKeys: String, CodingKey {
        case billing = "billing"
        case createdAt = "createdAt"
        case kernel = "kernel"
        case kernelSessionID = "kernelSessionId"
        case sessionID = "sessionId"
    }

    public init(billing: Billing, createdAt: Date, kernel: Kernel, kernelSessionID: String?, sessionID: String) {
        self.billing = billing
        self.createdAt = createdAt
        self.kernel = kernel
        self.kernelSessionID = kernelSessionID
        self.sessionID = sessionID
    }
}

// MARK: SessionHandle convenience initializers and mutators

public extension SessionHandle {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SessionHandle.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        billing: Billing? = nil,
        createdAt: Date? = nil,
        kernel: Kernel? = nil,
        kernelSessionID: String?? = nil,
        sessionID: String? = nil
    ) -> SessionHandle {
        return SessionHandle(
            billing: billing ?? self.billing,
            createdAt: createdAt ?? self.createdAt,
            kernel: kernel ?? self.kernel,
            kernelSessionID: kernelSessionID ?? self.kernelSessionID,
            sessionID: sessionID ?? self.sessionID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Billing
public struct Billing: Codable {
    public let tokenRef: String

    public enum CodingKeys: String, CodingKey {
        case tokenRef = "tokenRef"
    }

    public init(tokenRef: String) {
        self.tokenRef = tokenRef
    }
}

// MARK: Billing convenience initializers and mutators

public extension Billing {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Billing.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        tokenRef: String? = nil
    ) -> Billing {
        return Billing(
            tokenRef: tokenRef ?? self.tokenRef
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - SendResultPayload
public struct SendResultPayload: Codable {
    public let runID: String

    public enum CodingKeys: String, CodingKey {
        case runID = "runId"
    }

    public init(runID: String) {
        self.runID = runID
    }
}

// MARK: SendResultPayload convenience initializers and mutators

public extension SendResultPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SendResultPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        runID: String? = nil
    ) -> SendResultPayload {
        return SendResultPayload(
            runID: runID ?? self.runID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// D1 OperationOutcome 七态逐字透传，D2 不裁剪（D2 v3 §3.4）。
// MARK: - InterruptResultPayload
public struct InterruptResultPayload: Codable {
    /// 仅确有 active run 被 abort 时出现，不得虚构。
    public let affectedRunID: String?
    /// 非稳定字段。
    public let detail: String?
    /// 仅 mode:'abort_and_resend'。
    public let interruptedActiveRun: Bool?
    /// 仅 mode:'abort_and_resend' 且 outcome:'succeeded' 时有意义。
    public let newRunID: String?
    public let operationID: String
    public let outcome: PayloadOutcome
    /// 非稳定字段，透传底层 ack 的 status，仅供调试。
    public let status: JSONAny?

    public enum CodingKeys: String, CodingKey {
        case affectedRunID = "affectedRunId"
        case detail = "detail"
        case interruptedActiveRun = "interruptedActiveRun"
        case newRunID = "newRunId"
        case operationID = "operationId"
        case outcome = "outcome"
        case status = "status"
    }

    public init(affectedRunID: String?, detail: String?, interruptedActiveRun: Bool?, newRunID: String?, operationID: String, outcome: PayloadOutcome, status: JSONAny?) {
        self.affectedRunID = affectedRunID
        self.detail = detail
        self.interruptedActiveRun = interruptedActiveRun
        self.newRunID = newRunID
        self.operationID = operationID
        self.outcome = outcome
        self.status = status
    }
}

// MARK: InterruptResultPayload convenience initializers and mutators

public extension InterruptResultPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(InterruptResultPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        affectedRunID: String?? = nil,
        detail: String?? = nil,
        interruptedActiveRun: Bool?? = nil,
        newRunID: String?? = nil,
        operationID: String? = nil,
        outcome: PayloadOutcome? = nil,
        status: JSONAny?? = nil
    ) -> InterruptResultPayload {
        return InterruptResultPayload(
            affectedRunID: affectedRunID ?? self.affectedRunID,
            detail: detail ?? self.detail,
            interruptedActiveRun: interruptedActiveRun ?? self.interruptedActiveRun,
            newRunID: newRunID ?? self.newRunID,
            operationID: operationID ?? self.operationID,
            outcome: outcome ?? self.outcome,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// D1 §2.5：stop() 可达的 OperationOutcome 子集，仅三态——succeeded/timed_out/rejected（其余四态对 stop()
/// 语义上不适用，D2 v2 §3.5 已更正 v1『类型层面允许全部七态通过检查』的自相矛盾表述）。
// MARK: - StopResultPayload
public struct StopResultPayload: Codable {
    public let operationID: String
    public let outcome: StopResultPayloadOutcome

    public enum CodingKeys: String, CodingKey {
        case operationID = "operationId"
        case outcome = "outcome"
    }

    public init(operationID: String, outcome: StopResultPayloadOutcome) {
        self.operationID = operationID
        self.outcome = outcome
    }
}

// MARK: StopResultPayload convenience initializers and mutators

public extension StopResultPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(StopResultPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        operationID: String? = nil,
        outcome: StopResultPayloadOutcome? = nil
    ) -> StopResultPayload {
        return StopResultPayload(
            operationID: operationID ?? self.operationID,
            outcome: outcome ?? self.outcome
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum StopResultPayloadOutcome: String, Codable {
    case rejected = "rejected"
    case succeeded = "succeeded"
    case timedOut = "timed_out"
}

/// 逐字段对应 D1 SessionBillingSnapshot（D1 §7）。correlatable 恒为字面量 false——D1 未来若确认可关联，须走版本升级，本
/// schema 不预先改变这个字面量类型。
// MARK: - QueryBillingResultPayload
public struct QueryBillingResultPayload: Codable {
    public let attribution: Attribution
    public let correlatable: Bool
    public let fetchedAt: Date
    public let requestCount: Double
    public let rpm: Double
    public let sessionID: String
    public let tokenRef: String
    public let totalQuota: Double
    public let tpm: Double
    public let windowEnd: Date
    public let windowStart: Date

    public enum CodingKeys: String, CodingKey {
        case attribution = "attribution"
        case correlatable = "correlatable"
        case fetchedAt = "fetchedAt"
        case requestCount = "requestCount"
        case rpm = "rpm"
        case sessionID = "sessionId"
        case tokenRef = "tokenRef"
        case totalQuota = "totalQuota"
        case tpm = "tpm"
        case windowEnd = "windowEnd"
        case windowStart = "windowStart"
    }

    public init(attribution: Attribution, correlatable: Bool, fetchedAt: Date, requestCount: Double, rpm: Double, sessionID: String, tokenRef: String, totalQuota: Double, tpm: Double, windowEnd: Date, windowStart: Date) {
        self.attribution = attribution
        self.correlatable = correlatable
        self.fetchedAt = fetchedAt
        self.requestCount = requestCount
        self.rpm = rpm
        self.sessionID = sessionID
        self.tokenRef = tokenRef
        self.totalQuota = totalQuota
        self.tpm = tpm
        self.windowEnd = windowEnd
        self.windowStart = windowStart
    }
}

// MARK: QueryBillingResultPayload convenience initializers and mutators

public extension QueryBillingResultPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(QueryBillingResultPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        attribution: Attribution? = nil,
        correlatable: Bool? = nil,
        fetchedAt: Date? = nil,
        requestCount: Double? = nil,
        rpm: Double? = nil,
        sessionID: String? = nil,
        tokenRef: String? = nil,
        totalQuota: Double? = nil,
        tpm: Double? = nil,
        windowEnd: Date? = nil,
        windowStart: Date? = nil
    ) -> QueryBillingResultPayload {
        return QueryBillingResultPayload(
            attribution: attribution ?? self.attribution,
            correlatable: correlatable ?? self.correlatable,
            fetchedAt: fetchedAt ?? self.fetchedAt,
            requestCount: requestCount ?? self.requestCount,
            rpm: rpm ?? self.rpm,
            sessionID: sessionID ?? self.sessionID,
            tokenRef: tokenRef ?? self.tokenRef,
            totalQuota: totalQuota ?? self.totalQuota,
            tpm: tpm ?? self.tpm,
            windowEnd: windowEnd ?? self.windowEnd,
            windowStart: windowStart ?? self.windowStart
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// 握手响应 res.capabilities 的成功 result（D2 v3 §7）——protocolVersion 在此出现一次是允许且必要的（§7.1
/// 权威值的唯一来源）。逐字段对应 D1 §4.1，无新增/无精简。
// MARK: - CapabilityDescriptorPayload
public struct CapabilityDescriptorPayload: Codable {
    public let approvalDecisionKinds: [ApprovalDecisionKindElement]
    public let approvalGranularity: ApprovalGranularity
    public let approvalKinds: [KindElement]
    public let billingAttribution: Attribution
    public let interruptModes: [Mode]
    public let kernel: Kernel
    public let kernelVersion: String?
    /// wire 层单一契约版本标识，握手期确定，唯一权威值（D1 v3.5：连接级契约版本，D2 v3 §7.1）。当前基线 'kernelport/1'。
    public let protocolVersion: String
    public let sandboxLevels: [Sandbox]?
    public let sessionResume: Bool
    public let snapshotAt: Date
    public let streamingGranularity: StreamingGranularity
    public let thinkingVisibility: ThinkingVisibility
    public let tools: CapabilityDescriptorPayloadTools
    public let usageReporting: UsageReporting

    public enum CodingKeys: String, CodingKey {
        case approvalDecisionKinds = "approvalDecisionKinds"
        case approvalGranularity = "approvalGranularity"
        case approvalKinds = "approvalKinds"
        case billingAttribution = "billingAttribution"
        case interruptModes = "interruptModes"
        case kernel = "kernel"
        case kernelVersion = "kernelVersion"
        case protocolVersion = "protocolVersion"
        case sandboxLevels = "sandboxLevels"
        case sessionResume = "sessionResume"
        case snapshotAt = "snapshotAt"
        case streamingGranularity = "streamingGranularity"
        case thinkingVisibility = "thinkingVisibility"
        case tools = "tools"
        case usageReporting = "usageReporting"
    }

    public init(approvalDecisionKinds: [ApprovalDecisionKindElement], approvalGranularity: ApprovalGranularity, approvalKinds: [KindElement], billingAttribution: Attribution, interruptModes: [Mode], kernel: Kernel, kernelVersion: String?, protocolVersion: String, sandboxLevels: [Sandbox]?, sessionResume: Bool, snapshotAt: Date, streamingGranularity: StreamingGranularity, thinkingVisibility: ThinkingVisibility, tools: CapabilityDescriptorPayloadTools, usageReporting: UsageReporting) {
        self.approvalDecisionKinds = approvalDecisionKinds
        self.approvalGranularity = approvalGranularity
        self.approvalKinds = approvalKinds
        self.billingAttribution = billingAttribution
        self.interruptModes = interruptModes
        self.kernel = kernel
        self.kernelVersion = kernelVersion
        self.protocolVersion = protocolVersion
        self.sandboxLevels = sandboxLevels
        self.sessionResume = sessionResume
        self.snapshotAt = snapshotAt
        self.streamingGranularity = streamingGranularity
        self.thinkingVisibility = thinkingVisibility
        self.tools = tools
        self.usageReporting = usageReporting
    }
}

// MARK: CapabilityDescriptorPayload convenience initializers and mutators

public extension CapabilityDescriptorPayload {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilityDescriptorPayload.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        approvalDecisionKinds: [ApprovalDecisionKindElement]? = nil,
        approvalGranularity: ApprovalGranularity? = nil,
        approvalKinds: [KindElement]? = nil,
        billingAttribution: Attribution? = nil,
        interruptModes: [Mode]? = nil,
        kernel: Kernel? = nil,
        kernelVersion: String?? = nil,
        protocolVersion: String? = nil,
        sandboxLevels: [Sandbox]?? = nil,
        sessionResume: Bool? = nil,
        snapshotAt: Date? = nil,
        streamingGranularity: StreamingGranularity? = nil,
        thinkingVisibility: ThinkingVisibility? = nil,
        tools: CapabilityDescriptorPayloadTools? = nil,
        usageReporting: UsageReporting? = nil
    ) -> CapabilityDescriptorPayload {
        return CapabilityDescriptorPayload(
            approvalDecisionKinds: approvalDecisionKinds ?? self.approvalDecisionKinds,
            approvalGranularity: approvalGranularity ?? self.approvalGranularity,
            approvalKinds: approvalKinds ?? self.approvalKinds,
            billingAttribution: billingAttribution ?? self.billingAttribution,
            interruptModes: interruptModes ?? self.interruptModes,
            kernel: kernel ?? self.kernel,
            kernelVersion: kernelVersion ?? self.kernelVersion,
            protocolVersion: protocolVersion ?? self.protocolVersion,
            sandboxLevels: sandboxLevels ?? self.sandboxLevels,
            sessionResume: sessionResume ?? self.sessionResume,
            snapshotAt: snapshotAt ?? self.snapshotAt,
            streamingGranularity: streamingGranularity ?? self.streamingGranularity,
            thinkingVisibility: thinkingVisibility ?? self.thinkingVisibility,
            tools: tools ?? self.tools,
            usageReporting: usageReporting ?? self.usageReporting
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - CapabilityDescriptorPayloadTools
public struct CapabilityDescriptorPayloadTools: Codable {
    public let discoverable: Bool
    public let names: [String]?

    public enum CodingKeys: String, CodingKey {
        case discoverable = "discoverable"
        case names = "names"
    }

    public init(discoverable: Bool, names: [String]?) {
        self.discoverable = discoverable
        self.names = names
    }
}

// MARK: CapabilityDescriptorPayloadTools convenience initializers and mutators

public extension CapabilityDescriptorPayloadTools {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CapabilityDescriptorPayloadTools.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        discoverable: Bool? = nil,
        names: [String]?? = nil
    ) -> CapabilityDescriptorPayloadTools {
        return CapabilityDescriptorPayloadTools(
            discoverable: discoverable ?? self.discoverable,
            names: names ?? self.names
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// 7 个真正的 KernelPort 方法共用的同步/立即拒绝失败形状（D2 v3 §3）。
// MARK: - RejectionFailure
public struct RejectionFailure: Codable {
    public let code: RejectionFailureCode
    /// 非稳定字段，透传调试信息。
    public let detail: String?

    public enum CodingKeys: String, CodingKey {
        case code = "code"
        case detail = "detail"
    }

    public init(code: RejectionFailureCode, detail: String?) {
        self.code = code
        self.detail = detail
    }
}

// MARK: RejectionFailure convenience initializers and mutators

public extension RejectionFailure {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(RejectionFailure.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        code: RejectionFailureCode? = nil,
        detail: String?? = nil
    ) -> RejectionFailure {
        return RejectionFailure(
            code: code ?? self.code,
            detail: detail ?? self.detail
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// 方法调用同步/立即拒绝码（D1 v3.5 §9.1）。billing_query_subject_unresolved 已于 v3.4 移出本枚举，改列 queryBilling
/// 专属异步失败码，见 BillingQueryFailure。
public enum RejectionFailureCode: String, Codable {
    case aggregateBillingRequiresDeploymentToken = "aggregate_billing_requires_deployment_token"
    case approvalNotPending = "approval_not_pending"
    case noActiveRunForSteer = "no_active_run_for_steer"
    case sessionAlreadyStopped = "session_already_stopped"
    case sessionLocked = "session_locked"
    case sessionNotFound = "session_not_found"
    case unsupportedApprovalDecision = "unsupported_approval_decision"
    case unsupportedInterruptMode = "unsupported_interrupt_mode"
}

/// D2 专属、不出现在 D1 任何地方的消息层协议错误（D2 v3 §7.4）。unsupported_protocol_version
/// 仅在握手路径触发（res.capabilities 的 failure，D2 v3 §7.2 第 3
/// 步）；malformed_message/unknown_message_type 适用于任意方法的 request 本身损坏或 type 不可辨认的场景。已并入 §3.9 全部
/// 8 个具体方法 response 的 failure 联合以及 res.unknown 的 failure 类型。
// MARK: - ProtocolFailure
public struct ProtocolFailure: Codable {
    public let code: FailureCode
    public let detail: String?

    public enum CodingKeys: String, CodingKey {
        case code = "code"
        case detail = "detail"
    }

    public init(code: FailureCode, detail: String?) {
        self.code = code
        self.detail = detail
    }
}

// MARK: ProtocolFailure convenience initializers and mutators

public extension ProtocolFailure {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ProtocolFailure.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        code: FailureCode? = nil,
        detail: String?? = nil
    ) -> ProtocolFailure {
        return ProtocolFailure(
            code: code ?? self.code,
            detail: detail ?? self.detail
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// queryBilling 专属的独立失败类型——不使用 RejectionFailure，不与 KernelPortRejectionCode 共享枚举空间（D1 v3.5
/// §9.1、D2 v3 §3.8）。
// MARK: - BillingQueryFailure
public struct BillingQueryFailure: Codable {
    public let code: BillingQueryFailureCode
    public let detail: String?

    public enum CodingKeys: String, CodingKey {
        case code = "code"
        case detail = "detail"
    }

    public init(code: BillingQueryFailureCode, detail: String?) {
        self.code = code
        self.detail = detail
    }
}

// MARK: BillingQueryFailure convenience initializers and mutators

public extension BillingQueryFailure {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(BillingQueryFailure.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        code: BillingQueryFailureCode? = nil,
        detail: String?? = nil
    ) -> BillingQueryFailure {
        return BillingQueryFailure(
            code: code ?? self.code,
            detail: detail ?? self.detail
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum BillingQueryFailureCode: String, Codable {
    case billingQuerySubjectUnresolved = "billing_query_subject_unresolved"
}

// MARK: - Helper functions for creating encoders and decoders

func newJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
        decoder.dateDecodingStrategy = .iso8601
    }
    return decoder
}

func newJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
        encoder.dateEncodingStrategy = .iso8601
    }
    return encoder
}

// MARK: - Encode/decode helpers

public class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public func hash(into hasher: inout Hasher) {
        // No-op
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

class JSONCodingKey: CodingKey {
    let key: String

    required init?(intValue: Int) {
        return nil
    }

    required init?(stringValue: String) {
        key = stringValue
    }

    var intValue: Int? {
        return nil
    }

    var stringValue: String {
        return key
    }
}

public class JSONAny: Codable {

    public let value: Any

    static func decodingError(forCodingPath codingPath: [CodingKey]) -> DecodingError {
        let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode JSONAny")
        return DecodingError.typeMismatch(JSONAny.self, context)
    }

    static func encodingError(forValue value: Any, codingPath: [CodingKey]) -> EncodingError {
        let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Cannot encode JSONAny")
        return EncodingError.invalidValue(value, context)
    }

    static func decode(from container: SingleValueDecodingContainer) throws -> Any {
        if let value = try? container.decode(Bool.self) {
            return value
        }
        if let value = try? container.decode(Int64.self) {
            return value
        }
        if let value = try? container.decode(Double.self) {
            return value
        }
        if let value = try? container.decode(String.self) {
            return value
        }
        if container.decodeNil() {
            return JSONNull()
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout UnkeyedDecodingContainer) throws -> Any {
        if let value = try? container.decode(Bool.self) {
            return value
        }
        if let value = try? container.decode(Int64.self) {
            return value
        }
        if let value = try? container.decode(Double.self) {
            return value
        }
        if let value = try? container.decode(String.self) {
            return value
        }
        if let value = try? container.decodeNil() {
            if value {
                return JSONNull()
            }
        }
        if var container = try? container.nestedUnkeyedContainer() {
            return try decodeArray(from: &container)
        }
        if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self) {
            return try decodeDictionary(from: &container)
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout KeyedDecodingContainer<JSONCodingKey>, forKey key: JSONCodingKey) throws -> Any {
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeNil(forKey: key) {
            if value {
                return JSONNull()
            }
        }
        if var container = try? container.nestedUnkeyedContainer(forKey: key) {
            return try decodeArray(from: &container)
        }
        if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key) {
            return try decodeDictionary(from: &container)
        }
        throw decodingError(forCodingPath: container.codingPath)
    }

    static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
        var arr: [Any] = []
        while !container.isAtEnd {
            let value = try decode(from: &container)
            arr.append(value)
        }
        return arr
    }

    static func decodeDictionary(from container: inout KeyedDecodingContainer<JSONCodingKey>) throws -> [String: Any] {
        var dict = [String: Any]()
        for key in container.allKeys {
            let value = try decode(from: &container, forKey: key)
            dict[key.stringValue] = value
        }
        return dict
    }

    static func encode(to container: inout UnkeyedEncodingContainer, array: [Any]) throws {
        for value in array {
            if let value = value as? Bool {
                try container.encode(value)
            } else if let value = value as? Int64 {
                try container.encode(value)
            } else if let value = value as? Double {
                try container.encode(value)
            } else if let value = value as? String {
                try container.encode(value)
            } else if value is JSONNull {
                try container.encodeNil()
            } else if let value = value as? [Any] {
                var container = container.nestedUnkeyedContainer()
                try encode(to: &container, array: value)
            } else if let value = value as? [String: Any] {
                var container = container.nestedContainer(keyedBy: JSONCodingKey.self)
                try encode(to: &container, dictionary: value)
            } else {
                throw encodingError(forValue: value, codingPath: container.codingPath)
            }
        }
    }

    static func encode(to container: inout KeyedEncodingContainer<JSONCodingKey>, dictionary: [String: Any]) throws {
        for (key, value) in dictionary {
            let key = JSONCodingKey(stringValue: key)!
            if let value = value as? Bool {
                try container.encode(value, forKey: key)
            } else if let value = value as? Int64 {
                try container.encode(value, forKey: key)
            } else if let value = value as? Double {
                try container.encode(value, forKey: key)
            } else if let value = value as? String {
                try container.encode(value, forKey: key)
            } else if value is JSONNull {
                try container.encodeNil(forKey: key)
            } else if let value = value as? [Any] {
                var container = container.nestedUnkeyedContainer(forKey: key)
                try encode(to: &container, array: value)
            } else if let value = value as? [String: Any] {
                var container = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key)
                try encode(to: &container, dictionary: value)
            } else {
                throw encodingError(forValue: value, codingPath: container.codingPath)
            }
        }
    }

    static func encode(to container: inout SingleValueEncodingContainer, value: Any) throws {
        if let value = value as? Bool {
            try container.encode(value)
        } else if let value = value as? Int64 {
            try container.encode(value)
        } else if let value = value as? Double {
            try container.encode(value)
        } else if let value = value as? String {
            try container.encode(value)
        } else if value is JSONNull {
            try container.encodeNil()
        } else {
            throw encodingError(forValue: value, codingPath: container.codingPath)
        }
    }

    public required init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            self.value = try JSONAny.decodeArray(from: &arrayContainer)
        } else if var container = try? decoder.container(keyedBy: JSONCodingKey.self) {
            self.value = try JSONAny.decodeDictionary(from: &container)
        } else {
            let container = try decoder.singleValueContainer()
            self.value = try JSONAny.decode(from: container)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if let arr = self.value as? [Any] {
            var container = encoder.unkeyedContainer()
            try JSONAny.encode(to: &container, array: arr)
        } else if let dict = self.value as? [String: Any] {
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            try JSONAny.encode(to: &container, dictionary: dict)
        } else {
            var container = encoder.singleValueContainer()
            try JSONAny.encode(to: &container, value: self.value)
        }
    }
}

