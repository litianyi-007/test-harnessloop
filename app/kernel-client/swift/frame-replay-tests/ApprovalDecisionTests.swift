// rounds/0015 A/B/C：exec 工具审批的真 actor 级单测。
//
// 覆盖三件事，对应任务书四块工作里的 A/B/C：
//   A —— `respondApproval()` 真的打了 `approval.resolve` RPC（此前是 `throw .notImplemented` 的桩）
//   B —— D2 四值 <-> openclaw 三值的决策映射、`allow_session` 的处置、以及**每条请求各自携带的**
//        `allowedDecisions` 成员校验（本轮头号风险的拦截点）
//   C —— 审批在 `SessionStore` 层的卡片生命周期（产生 / 决策后移除 / 被 stop() 强制终态化后移除）
//
// **两条破坏性反证在本文件的落点**（任务书硬要求，实际红检查输出见交回报告）：
//   反证① —— `testRespondApprovalRejectsDecisionOutsideThisRequestsAllowedDecisions`
//             去掉 `makeApprovalResolveParams` 里那道 `allowedDecisionsFromRequest.contains(...)`
//             校验，本测试必须变红。它断言的不只是"抛错"，更是"**一个 RPC 都没发出去**"——因为
//             一旦发出去，openclaw 的 `forceMalformedDeny` 会把用户点的"允许"静默改写成 deny 并
//             **终态化**，没有第二次机会。测试里的 `approval.resolve` 桩刻意复刻了这个真实行为
//             （decision 不在允许集内就返回 denied/malformed-verdict 且 ok:true），所以红的时候
//             看到的就是真实事故的样子。
//   反证② —— `testOpenclawWireDecisionValuesAreExactlyTheKernelsThreeLiterals` 与
//             `testRespondApprovalSendsExactWireValuesForEachAllowedDecision`
//             把 `OpenclawApprovalDecisionWire` 任一 raw value 写错一个字母（下划线 <-> 连字符
//             是最容易犯的错）时必须变红。
//
// `@testable import`：同 FrameReplayTests.swift（两个 target 都带 `-enable-testing`），拿到
// `makeApprovalResolveParams` 等 internal 符号与 `SessionStore.handle(_:for:)`。

import Foundation
@testable import KernelClient
@testable import AgentShellCore
import D2Generated

// MARK: - 小工具：构造一条真实形状的 approval 现场

/// 把「agent(stream:"approval") 帧 + session.approval(phase:"pending") 帧」两条真实 wire 帧喂进
/// 适配器，走完整的 M1 双向 join，产出一条 `approval_request` 并让这个 reqId 进入"pending 等待决策"态。
///
/// 帧的形状照抄 EventMapping.swift ④ 记录的现场实测样本（含 `allowedDecisions` 字段——那正是本轮
/// 新增读取的字段）。`allowedDecisions` 默认 `["allow-once","deny"]`：这是 **`ask=always` 时内核
/// 真实给出的集合**（`resolveExecApprovalAllowedDecisions`，
/// kernels/openclaw/src/infra/exec-approvals.ts:2809-2813——"每次都问"与"永久放行"语义冲突，
/// 所以 allow-always 被排除），也是 rounds/0015 D 块起隔离实例做 live 验收时的实际档位。
@discardableResult
func feedRealApprovalRequest(
    _ client: OpenclawGatewayKernelClient,
    kernelKey: String,
    runID: String,
    approvalID: String,
    toolCallID: String,
    commandText: String = "rm -rf /tmp/some-scratch-dir",
    allowedDecisions: [String] = ["allow-once", "deny"],
    openclawKind: String = "exec",
    warningText: String? = nil
) async -> Bool {
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "approval",
            "data": ["phase": "requested", "toolCallId": toolCallID, "approvalId": approvalID] as JSONObject,
            "ts": 1_784_872_000_000,
        ] as JSONObject,
    ])
    var presentation: JSONObject = [
        "kind": openclawKind,
        "commandText": commandText,
        "host": "gateway",
        "agentId": "main",
        "allowedDecisions": allowedDecisions,
    ]
    if let warningText { presentation["warningText"] = warningText }
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_872_000_100, "phase": "pending",
            "approval": [
                "id": approvalID, "status": "pending",
                "presentation": presentation,
                "createdAtMs": 1_784_872_000_100,
                // expires - created = 1_800_000ms = 30min = openclaw exec 审批默认超时
                // （DEFAULT_EXEC_APPROVAL_TIMEOUT_MS，exec-approvals.ts:315）
                "expiresAtMs": 1_784_873_800_100,
            ] as JSONObject,
        ] as JSONObject,
    ])
    return await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID)
}

/// 复刻 openclaw `approval.resolve` handler 的**真实**判定逻辑
/// （`kernels/openclaw/src/gateway/server-methods/approval.ts:476-486`）的一个测试替身：
/// ```ts
/// const decisionAllowed = requestedDecision === "deny" ||
///   record.presentation.allowedDecisions.includes(requestedDecision);
/// const kindMatches = resolveParams?.kind === record.presentation.kind;
/// const forceMalformedDeny = !validParams || !kindMatches || !decisionAllowed;
/// ```
/// 关键在于：`forceMalformedDeny` 命中时**这条 RPC 仍然返回成功**，只是审批被终态化成
/// `denied / reason:"malformed-verdict"`。桩必须忠实复刻这一点，否则"静默变 deny"这个风险在测试里
/// 根本不会显形（返回一个错误的桩会让测试因为别的原因通过，那是假绿）。
func makeRealisticApprovalResolveStub(
    approvalID: String,
    presentationKind: String,
    allowedDecisions: [String],
    callLog: CallOrderLog,
    paramsBox: ParamsBox
) -> @Sendable (JSONObject) async throws -> JSONObject {
    return { params in
        await callLog.record("approval.resolve")
        await paramsBox.record(params)
        let requested = params["decision"] as? String
        let kind = params["kind"] as? String
        // closedObject{id,kind,decision}：多一个键就 !validParams（approvals.ts:245 + closed-object.ts）
        let validParams = Set(params.keys) == Set(["id", "kind", "decision"])
        let decisionAllowed = requested == "deny" || (requested.map { allowedDecisions.contains($0) } ?? false)
        let kindMatches = kind == presentationKind
        if !validParams || !kindMatches || !decisionAllowed {
            return [
                "applied": true,
                "approval": [
                    "id": approvalID, "status": "denied", "decision": "deny",
                    "reason": "malformed-verdict",
                ] as JSONObject,
            ] as JSONObject
        }
        if requested == "deny" {
            return ["applied": true, "approval": [
                "id": approvalID, "status": "denied", "decision": "deny", "reason": "user",
            ] as JSONObject] as JSONObject
        }
        return ["applied": true, "approval": [
            "id": approvalID, "status": "allowed", "decision": requested as Any, "reason": "user",
        ] as JSONObject] as JSONObject
    }
}

/// 记录每次 RPC 实际收到的 params——用于逐字断言 wire 上发出去的到底是什么（反证②）。
actor ParamsBox {
    private(set) var calls: [JSONObject] = []
    func record(_ params: JSONObject) { calls.append(params) }
}

func testHandleFor(_ sessionID: String, _ kernelKey: String) -> SessionHandle {
    testHandle(sessionID: sessionID, kernelKey: kernelKey)
}

// MARK: - B 块：决策映射（反证② 的直接靶子）

/// **反证② 靶子之一**：把 `OpenclawApprovalDecisionWire` 任一 raw value 写错一个字母（典型错误：
/// 沿用 D2 的下划线写法 `allow_once`，或把 `allow-always` 写成 `allow_always`）时本测试立刻变红。
///
/// 断言的是"逐字等于内核 schema 里的三个字面量"——权威源
/// `kernels/openclaw/packages/gateway-protocol/src/schema/approvals.ts:25-29`：
/// `ApprovalDecisionSchema = Union([Literal("allow-once"), Literal("allow-always"), Literal("deny")])`。
func testOpenclawWireDecisionValuesAreExactlyTheKernelsThreeLiterals() -> Bool {
    let name = "rounds/0015 B: openclaw wire decision literals are exactly [allow-once, allow-always, deny]（连字符，逐字对齐内核 schema）"
    let actual = OpenclawApprovalDecisionWire.allCases.map(\.rawValue)
    let expected = ["allow-once", "allow-always", "deny"]
    guard actual == expected else {
        return fail(name, "wire 取值与内核 ApprovalDecisionSchema 不一致：expected \(expected), got \(actual)")
    }
    // 逐个方向再钉一次，防止"集合对了但映射接错了"（比如 allowOnce 映到 allow-always）
    let pairs: [(ApprovalDecisionKindElement, String?)] = [
        (.allowOnce, "allow-once"),
        (.allowAlways, "allow-always"),
        (.deny, "deny"),
        (.allowSession, nil), // openclaw 没有 session 档位——见下方专门的测试
    ]
    for (d2, wire) in pairs {
        let mapped = openclawApprovalDecisionWire(forD2: d2)?.rawValue
        guard mapped == wire else {
            return fail(name, "D2 \(d2.rawValue) 应映射到 \(wire ?? "nil")，实际得到 \(mapped ?? "nil")")
        }
    }
    // 反向映射（供 UI 渲染按钮用）同样逐个钉住
    let reverse: [(String, ApprovalDecisionKindElement?)] = [
        ("allow-once", .allowOnce), ("allow-always", .allowAlways), ("deny", .deny),
        ("allow_once", nil),        // 下划线写法不是 openclaw 的合法取值，必须认不出
        ("allow-session", nil),     // 内核根本没有这个值
    ]
    for (raw, expectedKind) in reverse {
        let got = d2ApprovalDecisionKind(forOpenclawWire: raw)
        guard got == expectedKind else {
            return fail(name, "openclaw '\(raw)' 应反向映射到 \(expectedKind?.rawValue ?? "nil")，实际 \(got?.rawValue ?? "nil")")
        }
    }
    return pass(name, "四值 <-> 三值双向映射逐个 case 对齐内核 schema 字面量；下划线/session 写法均被正确判为不可映射")
}

/// **B 块 `allow_session` 处置的直接断言**：必须**同步拒绝**（`unsupported_approval_decision`），
/// 既不静默降级成 allow_once（那是**授权不足**，用户以为授了整段会话实际只放行一次），也不降级成
/// allow_always（那是**过度授权**，用户以为只授本会话实际被永久持久化）。
///
/// 依据：`app/contracts/d2/schema/methods/respond-approval.schema.json:34`（落到 D2.swift:1166-1167
/// `Decision` 的文档注释）原文——"由 capabilities().approvalDecisionKinds 门控，未声明支持时实现须
/// 同步拒绝 unsupported_approval_decision，**不得静默降级为 allow_once**"。
func testAllowSessionIsSynchronouslyRejectedNotSilentlyDowngraded() -> Bool {
    let name = "rounds/0015 B: allow_session 被同步拒绝为 unsupported_approval_decision，不静默降级"
    // 即便 allowedDecisions 是三值全集（最宽松的情况），allow_session 依然无处可去
    let decision = Decision(outcome: .allowSession, updatedInput: nil, scope: nil, reason: nil)
    do {
        let params = try makeApprovalResolveParams(
            reqID: "approval-x", openclawKind: "exec", decision: decision,
            allowedDecisionsFromRequest: ["allow-once", "allow-always", "deny"]
        )
        return fail(name, "allow_session 竟然构造出了 params \(params)——这意味着它被降级成了某个内核认识的值")
    } catch let error as ApprovalDecisionError {
        guard case .unsupportedApprovalDecision(let requested, let supports) = error else {
            return fail(name, "期望 .unsupportedApprovalDecision，实际 \(error)")
        }
        guard requested == .allowSession, supports == ["allow-once", "allow-always", "deny"] else {
            return fail(name, "错误负载不对：requested=\(requested.rawValue) supports=\(supports)")
        }
        print("  [evidence] allow_session 的处置：\(error.description)")
        return pass(name, "如实抛 unsupported_approval_decision，未降级为 allow_once/allow_always")
    } catch {
        return fail(name, "抛出了非 ApprovalDecisionError：\(error)")
    }
}

/// `allowedDecisions` **不能硬编码**的正面证据：同一段代码在两种不同的内核配置下必须给出不同结论。
/// `ask=always` -> `["allow-once","deny"]`（allow_always 非法）；其余配置 -> 三值全集（allow_always 合法）。
func testAllowedDecisionsIsPerRequestNotAHardcodedSet() -> Bool {
    let name = "rounds/0015 B: allowedDecisions 逐请求判定——同一个 allow_always 在 ask=always 下非法、在默认配置下合法"
    let allowAlways = Decision(outcome: .allowAlways, updatedInput: nil, scope: nil, reason: nil)

    // ① ask=always 的实例：内核只给 [allow-once, deny]
    do {
        _ = try makeApprovalResolveParams(
            reqID: "a1", openclawKind: "exec", decision: allowAlways,
            allowedDecisionsFromRequest: ["allow-once", "deny"]
        )
        return fail(name, "ask=always 场景下 allow_always 本应被拒绝，却通过了校验")
    } catch let error as ApprovalDecisionError {
        guard case .decisionNotAllowedForThisRequest = error else {
            return fail(name, "期望 .decisionNotAllowedForThisRequest，实际 \(error)")
        }
    } catch {
        return fail(name, "抛出了非 ApprovalDecisionError：\(error)")
    }

    // ② 默认配置的实例：DEFAULT_EXEC_APPROVAL_DECISIONS 三值全集，同一个决策必须放行
    do {
        let (params, wire) = try makeApprovalResolveParams(
            reqID: "a2", openclawKind: "exec", decision: allowAlways,
            allowedDecisionsFromRequest: ["allow-once", "allow-always", "deny"]
        )
        guard params["decision"] as? String == "allow-always", wire == .allowAlways else {
            return fail(name, "默认配置下 allow_always 应被放行并映射成 allow-always，实际 params=\(params)")
        }
    } catch {
        return fail(name, "默认配置下 allow_always 本应通过，却抛了 \(error)")
    }
    return pass(name, "同一决策在两种真实内核配置下分别被拒/被放行——证明判定确实取自每条请求自带的集合，不是固定集合")
}

/// params 必须**恰好**是 `{id, kind, decision}` 三个键：`ApprovalResolveParamsSchema` 是
/// `closedObject`（additionalProperties:false），多一个键 -> `!validParams` -> `forceMalformedDeny`。
func testApprovalResolveParamsShapeIsExactlyThreeKeys() -> Bool {
    let name = "rounds/0015 B: approval.resolve params 恰好是 {id,kind,decision}（closedObject，多一个键就会被服务端判 malformed）"
    let decision = Decision(outcome: .allowOnce, updatedInput: nil, scope: "session", reason: "用户在壳里点了允许")
    do {
        let (params, _) = try makeApprovalResolveParams(
            reqID: "req-42", openclawKind: "plugin", decision: decision,
            allowedDecisionsFromRequest: ["allow-once", "deny"]
        )
        guard Set(params.keys) == Set(["id", "kind", "decision"]) else {
            return fail(name, "params 键集合不对：\(Set(params.keys))")
        }
        guard params["id"] as? String == "req-42", params["kind"] as? String == "plugin",
              params["decision"] as? String == "allow-once" else {
            return fail(name, "params 取值不对：\(params)")
        }
        return pass(name, "恰好三个键，且 kind 透传的是这条请求真实的 openclaw kind（plugin，而不是 D2 收窄后的 .tool）；scope/reason 被安全忽略未混入 params")
    } catch {
        return fail(name, "本应成功构造，却抛了 \(error)")
    }
}

/// `Decision.updatedInput`（改写待执行内容后再放行）在 openclaw 的 params 里没有承载位置——
/// 静默丢弃会让"我改了命令再放行"变成"原样放行原始命令"，是比静默 deny 更危险的**静默 allow**。
func testUpdatedInputIsRejectedRatherThanSilentlyDropped() -> Bool {
    let name = "rounds/0015 B: Decision.updatedInput 无处承载时如实拒绝，不静默丢弃（否则等于原样放行原命令）"
    let decision = Decision(
        outcome: .allowOnce,
        updatedInput: makeJSONAny(["command": "echo 我改写过的安全命令"] as JSONObject),
        scope: nil, reason: nil
    )
    do {
        _ = try makeApprovalResolveParams(
            reqID: "req-ui", openclawKind: "exec", decision: decision,
            allowedDecisionsFromRequest: ["allow-once", "deny"]
        )
        return fail(name, "带 updatedInput 的决策竟然通过了——改写内容会被静默丢弃、原命令原样执行")
    } catch let error as ApprovalDecisionError {
        guard case .unsupportedUpdatedInput = error else {
            return fail(name, "期望 .unsupportedUpdatedInput，实际 \(error)")
        }
        return pass(name, "如实拒绝：\(error.description)")
    } catch {
        return fail(name, "抛出了非 ApprovalDecisionError：\(error)")
    }
}

// MARK: - A 块：respondApproval() 真的打 RPC（含反证①）

/// **反证① 的靶子（本轮最重要的一条）**：决策不在**这条请求**的 `allowedDecisions` 内时，必须
/// **在客户端就被拦下**——不只是"最终报错"，而是**一个 RPC 都不能发出去**。
///
/// 为什么"发出去再报错"不够：openclaw 的 `forceMalformedDeny` 会把这次请求终态化成
/// `denied / reason:"malformed-verdict"` 并**仍然返回 ok:true**（approval.ts:476-486 + applyForcedDeny）。
/// 审批一旦进终态就没有第二次机会——用户点的"总是允许"变成了永久的"拒绝"，且界面上看不出任何异常。
/// 所以本测试的核心断言是 `callLog.entries.isEmpty`。
///
/// **红检查方法**：删掉 `makeApprovalResolveParams` 里的
/// `guard allowedDecisionsFromRequest.contains(wire.rawValue) else { throw ... }` 三行，本测试变红
/// ——且因为桩复刻了内核真实行为，红的时候能直接看到"allow-always 被改写成了 denied/malformed-verdict"。
func testRespondApprovalRejectsDecisionOutsideThisRequestsAllowedDecisions() async -> Bool {
    let name = "rounds/0015 反证①: 决策不在该请求 allowedDecisions 内时，客户端拦下并报错，且一个 approval.resolve RPC 都不发出"
    let client = freshClient()
    let sessionID = "sess-approval-guard"
    let kernelKey = "kernel-key-approval-guard"
    let approvalID = "approval-guard-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)

    // ask=always 的真实现场：内核只允许 [allow-once, deny]
    let registered = await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: "run-guard-1", approvalID: approvalID,
        toolCallID: "tool-guard-1", allowedDecisions: ["allow-once", "deny"]
    )
    guard registered else { return fail(name, "审批未进入 pending-awaiting-decision 态，前置条件不成立") }

    let callLog = CallOrderLog()
    let paramsBox = ParamsBox()
    await client.testSupportStubRPC(
        method: "approval.resolve",
        responder: makeRealisticApprovalResolveStub(
            approvalID: approvalID, presentationKind: "exec",
            allowedDecisions: ["allow-once", "deny"], callLog: callLog, paramsBox: paramsBox
        )
    )

    // 用户点了"总是允许"——这个档位在 ask=always 下不被内核接受
    let decision = Decision(outcome: .allowAlways, updatedInput: nil, scope: nil, reason: nil)
    do {
        try await client.respondApproval(
            session: testHandleFor(sessionID, kernelKey), reqID: approvalID, decision: decision
        )
        return fail(name, "respondApproval 竟然成功返回——决策已被送进服务端，会被 forceMalformedDeny 静默改写成 deny")
    } catch let error as ApprovalDecisionError {
        guard case .decisionNotAllowedForThisRequest(let reqID, let requested, let allowed) = error else {
            return fail(name, "期望 .decisionNotAllowedForThisRequest，实际 \(error)")
        }
        guard reqID == approvalID, requested == "allow-always", allowed == ["allow-once", "deny"] else {
            return fail(name, "错误负载不对：reqID=\(reqID) requested=\(requested) allowed=\(allowed)")
        }
        print("  [反证① evidence] 客户端拦截信息：\(error.description)")
    } catch {
        return fail(name, "抛出了非 ApprovalDecisionError：\(error)")
    }

    // **核心断言**：没有任何 RPC 被发出——决策连内核的门都没碰到
    let calls = await callLog.entries
    guard calls.isEmpty else {
        return fail(name, "期望一个 RPC 都不发出，实际发出了 \(calls)——决策已经不可逆地进入内核（会被静默改写成 deny）")
    }
    // 审批仍然 pending：用户可以改选一个合法决策再试一次
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "被拦下的决策不应把审批从 pending 表里摘掉——用户改选后还要能再回应一次")
    }
    print("  [反证① evidence] 发出的 approval.resolve RPC 数：\(calls.count)（期望 0）；审批仍处于 pending，可改选重试")
    return pass(name, "客户端拦截生效：0 次 RPC、抛 decisionNotAllowedForThisRequest、审批保持 pending 可重试")
}

/// **反证② 的端到端靶子**：逐个合法决策走完整 `respondApproval()`，断言 wire 上发出去的
/// `decision` 字段**逐字**等于内核字面量。映射写错一个字母这里立刻变红。
/// 同时验证 A 块的基本事实：`respondApproval()` 真的打了 `approval.resolve`（此前是抛桩）。
func testRespondApprovalSendsExactWireValuesForEachAllowedDecision() async -> Bool {
    let name = "rounds/0015 A/反证②: respondApproval 对每个合法决策发出逐字正确的 wire 值（allow_once->allow-once / allow_always->allow-always / deny->deny）"
    // (D2 决策, 该请求的 allowedDecisions, 期望 wire 值)
    let cases: [(ApprovalDecisionKindElement, [String], String)] = [
        (.allowOnce, ["allow-once", "deny"], "allow-once"),
        (.allowAlways, ["allow-once", "allow-always", "deny"], "allow-always"),
        (.deny, ["allow-once", "deny"], "deny"),
    ]
    for (index, (outcome, allowed, expectedWire)) in cases.enumerated() {
        let client = freshClient()
        let sessionID = "sess-wire-\(index)"
        let kernelKey = "kernel-key-wire-\(index)"
        let approvalID = "approval-wire-\(index)"
        _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
        let registered = await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: "run-wire-\(index)", approvalID: approvalID,
            toolCallID: "tool-wire-\(index)", allowedDecisions: allowed
        )
        guard registered else { return fail(name, "[\(outcome.rawValue)] 审批未进入 pending 态") }

        let callLog = CallOrderLog()
        let paramsBox = ParamsBox()
        await client.testSupportStubRPC(
            method: "approval.resolve",
            responder: makeRealisticApprovalResolveStub(
                approvalID: approvalID, presentationKind: "exec",
                allowedDecisions: allowed, callLog: callLog, paramsBox: paramsBox
            )
        )
        do {
            try await client.respondApproval(
                session: testHandleFor(sessionID, kernelKey), reqID: approvalID,
                decision: Decision(outcome: outcome, updatedInput: nil, scope: nil, reason: nil)
            )
        } catch {
            return fail(name, "[\(outcome.rawValue)] respondApproval 抛错：\(error)")
        }
        let calls = await paramsBox.calls
        guard calls.count == 1 else {
            return fail(name, "[\(outcome.rawValue)] 期望恰好 1 次 approval.resolve，实际 \(calls.count) 次")
        }
        guard calls[0]["decision"] as? String == expectedWire else {
            return fail(name, "[\(outcome.rawValue)] wire decision 应为 '\(expectedWire)'，实际 '\(calls[0]["decision"] as? String ?? "nil")'")
        }
        guard calls[0]["id"] as? String == approvalID, calls[0]["kind"] as? String == "exec" else {
            return fail(name, "[\(outcome.rawValue)] id/kind 不对：\(calls[0])")
        }
        // 成功后必须从 pending 表摘掉——否则随后的 stop() 会对一个已终态的 reqId 再发一次强制 deny
        guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) == false else {
            return fail(name, "[\(outcome.rawValue)] 决策已被内核确认，reqId 却仍留在 pending 表里")
        }
        print("  [反证② evidence] D2 \(outcome.rawValue) -> wire params \(calls[0])")
    }
    return pass(name, "三个合法决策各自发出逐字正确的 wire 值，且成功后 reqId 从 pending 表摘除")
}

/// 内核**没有兑现**决策时不得当成功——`forceMalformedDeny` 之外，审批也可能在 RPC 在途期间超时
/// （`expired`）。这是与客户端前置校验互补的第二道防线：`ok:true` 本身不构成"决策被接受"的证据。
///
/// 构造方式：桩里刻意让服务端"收下 allow-once 却记成 denied/malformed-verdict"（真实场景对应
/// kind 不匹配等我们客户端来不及知道的服务端状态）。
func testRespondApprovalRejectsKernelResponseThatDidNotHonorTheDecision() async -> Bool {
    let name = "rounds/0015 A: approval.resolve 回 ok:true 但终态不是我们请求的决策时，如实报错（不凭 ok:true 采信）"
    let client = freshClient()
    let sessionID = "sess-not-honored"
    let kernelKey = "kernel-key-not-honored"
    let approvalID = "approval-not-honored-1"
    _ = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let registered = await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: "run-nh-1", approvalID: approvalID,
        toolCallID: "tool-nh-1", allowedDecisions: ["allow-once", "deny"]
    )
    guard registered else { return fail(name, "审批未进入 pending 态") }

    // 服务端"接受"了请求（ok:true），但记录的终态是 malformed-verdict 的 deny——这正是静默改写的样子
    await client.testSupportStubRPC(method: "approval.resolve") { _ in
        ["applied": true, "approval": [
            "id": approvalID, "status": "denied", "decision": "deny", "reason": "malformed-verdict",
        ] as JSONObject] as JSONObject
    }
    do {
        try await client.respondApproval(
            session: testHandleFor(sessionID, kernelKey), reqID: approvalID,
            decision: Decision(outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil)
        )
        return fail(name, "内核把 allow-once 记成了 denied，respondApproval 却当成功返回了")
    } catch let error as ApprovalDecisionError {
        guard case .kernelDidNotHonorDecision(_, let requested, let status, _, let reason, _) = error else {
            return fail(name, "期望 .kernelDidNotHonorDecision，实际 \(error)")
        }
        guard requested == "allow-once", status == "denied", reason == "malformed-verdict" else {
            return fail(name, "错误负载不对：requested=\(requested) status=\(status ?? "nil") reason=\(reason ?? "nil")")
        }
        print("  [evidence] 静默改写被识破：\(error.description)")
        return pass(name, "识别出 status=denied/reason=malformed-verdict 与请求的 allow-once 不符，如实抛错")
    } catch {
        return fail(name, "抛出了非 ApprovalDecisionError：\(error)")
    }
}

/// 跨会话回应必须被拒绝：拿 session B 的 handle 去回应属于 session A 的审批是调用错误，不代打。
func testRespondApprovalRejectsCrossSessionAndUnknownReqID() async -> Bool {
    let name = "rounds/0015 A: respondApproval 拒绝未知 reqId 与跨会话回应"
    let client = freshClient()
    _ = await client.testSupportRegisterSession(ourSessionID: "sess-A", kernelKey: "kernel-key-A")
    _ = await client.testSupportRegisterSession(ourSessionID: "sess-B", kernelKey: "kernel-key-B")
    let approvalID = "approval-owned-by-A"
    let registered = await feedRealApprovalRequest(
        client, kernelKey: "kernel-key-A", runID: "run-A", approvalID: approvalID, toolCallID: "tool-A"
    )
    guard registered else { return fail(name, "审批未进入 pending 态") }

    // 这两条路径都应该在发 RPC 之前就被拦下——桩一旦被调用就说明拦截失效，直接抛错让测试红。
    let unexpectedCallLog = CallOrderLog()
    await client.testSupportStubRPC(method: "approval.resolve") { _ in
        await unexpectedCallLog.record("approval.resolve")
        throw KernelClientError.protocolMismatch("approval.resolve 不应在未知 reqId / 跨会话场景下被调用")
    }
    let allowOnce = Decision(outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil)

    // ① 未知 reqId
    do {
        try await client.respondApproval(
            session: testHandleFor("sess-A", "kernel-key-A"), reqID: "no-such-approval", decision: allowOnce
        )
        return fail(name, "未知 reqId 竟然成功了")
    } catch let error as ApprovalDecisionError {
        guard case .approvalNotPending = error else { return fail(name, "期望 .approvalNotPending，实际 \(error)") }
    } catch {
        return fail(name, "未知 reqId 抛出了非 ApprovalDecisionError：\(error)")
    }

    // ② 跨会话：用 sess-B 的 handle 回应属于 sess-A 的审批
    do {
        try await client.respondApproval(
            session: testHandleFor("sess-B", "kernel-key-B"), reqID: approvalID, decision: allowOnce
        )
        return fail(name, "跨会话回应竟然成功了")
    } catch let error as ApprovalDecisionError {
        guard case .approvalBelongsToAnotherSession(_, let owner, let requester) = error else {
            return fail(name, "期望 .approvalBelongsToAnotherSession，实际 \(error)")
        }
        guard owner == "sess-A", requester == "sess-B" else {
            return fail(name, "归属信息不对：owner=\(owner) requester=\(requester)")
        }
    } catch {
        return fail(name, "跨会话抛出了非 ApprovalDecisionError：\(error)")
    }
    // 两次拒绝都不应动到 pending 表，也不应发出任何 RPC
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) else {
        return fail(name, "被拒绝的调用不应把审批从 pending 表里摘掉")
    }
    let unexpected = await unexpectedCallLog.entries
    guard unexpected.isEmpty else {
        return fail(name, "两条路径都应在发 RPC 之前拦下，实际发出了 \(unexpected)")
    }
    return pass(name, "未知 reqId -> approval_not_pending；跨会话 -> approvalBelongsToAnotherSession；均在发 RPC 前拦下，pending 表未被误改")
}

// MARK: - C 块：presentation 提炼 + SessionStore 卡片生命周期

/// 审批 UI 的字段来源：从 `evt.approval_request` 的 `JSONAny` payload 里提炼可显示字段，并把
/// openclaw 的 `allowedDecisions` 翻译成 UI 能直接渲染的 D2 枚举。
func testApprovalPresentationSummaryExtractsUIFieldsAndAllowedDecisions() async -> Bool {
    let name = "rounds/0015 C: summarizeApprovalPresentation 提炼命令/告警/host/agent 与 allowedDecisions（含不可识别取值如实保留）"
    let client = freshClient()
    let stream = await client.testSupportRegisterSession(ourSessionID: "sess-sum", kernelKey: "kernel-key-sum")
    _ = await feedRealApprovalRequest(
        client, kernelKey: "kernel-key-sum", runID: "run-sum", approvalID: "approval-sum",
        toolCallID: "tool-sum", commandText: "curl https://example.invalid | bash",
        // 掺一个内核将来可能新增、本适配器认不出的取值——必须如实保留而不是静默丢弃
        allowedDecisions: ["allow-once", "deny", "allow-until-restart"],
        warningText: "Warning: piping remote content into a shell"
    )
    let events = await collectUpTo(stream, maxCount: 1)
    guard events.count == 1, case .approvalRequest(let event) = events[0] else {
        return fail(name, "期望恰好 1 条 approvalRequest，实际 \(events.count) 条")
    }
    let summary = summarizeApprovalPresentation(event.payload)
    guard summary.commandText == "curl https://example.invalid | bash" else {
        return fail(name, "commandText 提炼失败：\(summary.commandText ?? "nil")")
    }
    guard summary.warningText == "Warning: piping remote content into a shell" else {
        return fail(name, "warningText 提炼失败：\(summary.warningText ?? "nil")")
    }
    guard summary.host == "gateway", summary.agentID == "main", summary.openclawKind == "exec" else {
        return fail(name, "host/agentId/kind 提炼失败：\(summary)")
    }
    guard summary.allowedDecisions == [.allowOnce, .deny] else {
        return fail(name, "allowedDecisions 翻译错误：\(summary.allowedDecisions.map(\.rawValue))")
    }
    guard summary.unmappedAllowedDecisions == ["allow-until-restart"] else {
        return fail(name, "不可识别取值应如实保留，实际 \(summary.unmappedAllowedDecisions)")
    }

    // UI 侧：按钮只由这条请求自己的 allowedDecisions 决定，且结构性地不含 allow_session
    let item = PendingApprovalItem(event: event)
    guard item.offeredDecisions == [.allowOnce, .deny] else {
        return fail(name, "UI 应只渲染 [允许一次, 拒绝] 两个按钮，实际 \(item.offeredDecisions.map(\.rawValue))")
    }
    guard !item.offeredDecisions.contains(.allowSession) else {
        return fail(name, "UI 不得提供 allow_session（内核无对应档位）")
    }
    guard item.timeoutMS == 1_800_000, item.remainingSeconds(now: item.requestedAt) == 1800 else {
        return fail(name, "超时窗口应为 30 分钟，实际 timeoutMS=\(item.timeoutMS)")
    }
    guard item.bodyText == "curl https://example.invalid | bash", item.reasonText != nil else {
        return fail(name, "卡片正文/原因取值不对")
    }
    print("  [evidence] UI 卡片：headline=\(item.headline) 按钮=\(item.offeredDecisions.map { approvalDecisionButtonLabel($0) }) 剩余=\(item.remainingSeconds(now: item.requestedAt) ?? -1)s 不支持的选项=\(summary.unmappedAllowedDecisions)")
    return pass(name, "命令/告警/host/agent 提炼正确；allowedDecisions 翻译为 [allow_once, deny] 且认不出的取值如实保留；UI 只渲染这两个按钮、结构性不含 allow_session")
}

/// `SessionStore` 层的卡片生命周期：`evt.approval_request` -> 卡片出现（且 reqId 重复到达不重复插）；
/// `evt.turn_complete` 带 `forceResolvedApprovals` -> 卡片移除（stop() 强制终态化后不留僵尸卡片）。
@MainActor
func testSessionStoreShowsApprovalCardAndClearsItOnForceResolved() async -> Bool {
    let name = "rounds/0015 C: SessionStore 收到 approval_request 显示卡片（重复 reqId 不重复插），turn_complete.forceResolvedApprovals 清除卡片"
    let store = SessionStore(config: KernelShellConfig(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "t", configWarning: nil))
    let handle = testHandle(sessionID: "sess-ui", kernelKey: "kernel-key-ui")
    let session = ChatSessionViewModel(handle: handle, title: "审批卡片测试")

    let payload = ApprovalRequestEventMessagePayload(
        kind: .exec,
        payload: makeJSONAny([
            "kind": "exec", "commandText": "sudo rm -rf /", "host": "gateway", "agentId": "main",
            "allowedDecisions": ["allow-once", "deny"],
        ] as JSONObject),
        proposedDecision: nil, reqID: "approval-ui-1", timeoutAuthority: .documented,
        timeoutMS: 1_800_000, toolCallID: "tool-ui-1"
    )
    let event = EventMessageUnion.approvalRequest(ApprovalRequestEventMessage(
        direction: .event, payload: payload, runID: "run-ui-1", sentAt: Date(), seq: 1,
        sessionID: "sess-ui", ts: Date(), type: .evtApprovalRequest
    ))

    store.handle(event, for: session)
    guard session.pendingApprovals.count == 1, session.pendingApprovals[0].reqID == "approval-ui-1" else {
        return fail(name, "approval_request 后应有 1 张卡片，实际 \(session.pendingApprovals.count) 张")
    }
    // 同一 reqId 再来一次（断线重连后 approvalReplay 重放的真实场景）——不得重复插卡
    store.handle(event, for: session)
    guard session.pendingApprovals.count == 1 else {
        return fail(name, "重复 reqId 不应重复插卡，实际 \(session.pendingApprovals.count) 张")
    }
    guard session.pendingApprovals[0].bodyText == "sudo rm -rf /" else {
        return fail(name, "卡片正文应是命令全文，实际 \(session.pendingApprovals[0].bodyText)")
    }

    // stop() 强制 deny 后，D1 §6.2 M3 要求被终态化的 reqId 列在 turn_complete.forceResolvedApprovals
    let turn = EventMessageUnion.turnComplete(TurnCompleteEventMessage(
        direction: .event,
        payload: TurnCompleteEventMessagePayload(
            degraded: nil, forceResolvedApprovals: ["approval-ui-1"], stopReason: .cancelled, usage: nil
        ),
        runID: "run-ui-1", sentAt: Date(), seq: 2, sessionID: "sess-ui", ts: Date(), type: .evtTurnComplete
    ))
    store.handle(turn, for: session)
    guard session.pendingApprovals.isEmpty else {
        return fail(name, "被 stop() 强制终态化的审批应从卡片列表移除，实际仍有 \(session.pendingApprovals.count) 张")
    }
    print("  [evidence] 卡片生命周期：approval_request x2 -> 1 张卡片（去重）；turn_complete(forceResolvedApprovals=[approval-ui-1]) -> 0 张")
    return pass(name, "卡片按 reqId 去重出现，并在 stop() 强制终态化后被清除，不留点不动的僵尸卡片")
}

// MARK: - 注册

func runApprovalDecisionTests() async -> [Bool] {
    var results: [Bool] = []
    results.append(testOpenclawWireDecisionValuesAreExactlyTheKernelsThreeLiterals())
    results.append(testAllowSessionIsSynchronouslyRejectedNotSilentlyDowngraded())
    results.append(testAllowedDecisionsIsPerRequestNotAHardcodedSet())
    results.append(testApprovalResolveParamsShapeIsExactlyThreeKeys())
    results.append(testUpdatedInputIsRejectedRatherThanSilentlyDropped())
    results.append(await testRespondApprovalRejectsDecisionOutsideThisRequestsAllowedDecisions())
    results.append(await testRespondApprovalSendsExactWireValuesForEachAllowedDecision())
    results.append(await testRespondApprovalRejectsKernelResponseThatDidNotHonorTheDecision())
    results.append(await testRespondApprovalRejectsCrossSessionAndUnknownReqID())
    results.append(await testApprovalPresentationSummaryExtractsUIFieldsAndAllowedDecisions())
    results.append(await testSessionStoreShowsApprovalCardAndClearsItOnForceResolved())
    // rounds/0015 返工（对抗审 ★ 两条实质发现）：D1 §6.2 审批 FSM + approval.resolve 竞态串行化，
    // 两条破坏性反证 A/B（B 拆成两个到达顺序）。
    results.append(await testApprovalFSMSerializesToSingleActivePendingAndOverflowsBeyondDepth())
    results.append(await testStopForceDenyAndManualRespondOnSameReqIDEmitExactlyOneResolve())
    results.append(await testManualRespondInFlightBlocksStopAbortAndIsNotCountedAsForceResolved())
    results.append(await testSessionStoreSurfacesApprovalBufferResolvedAsSystemLine())
    return results
}

// MARK: - rounds/0015 返工：D1 §6.2 审批状态机 + approval.resolve 竞态串行化
//
// 本节两条测试就是任务书硬要求的两条**破坏性反证**，各自的拆除点已在生产代码里用注释标出：
//   反证 A —— `OpenclawGatewayKernelClient.emitApprovalRequestIfPossible` 里那道
//              `guard activeApprovalReqIDBySessionID[sid] != nil else { present...; return }`
//              （注释原文标了"破坏性反证 A 的拆除点"）。把它改成恒真（即恢复"每条都直接 yield"的
//              修前行为），本节 `testApprovalFSMSerializes...` 必然变红。
//   反证 B —— `beginApprovalResolveInFlight`/`awaitApprovalResolveSettled` 这对 in-flight 串行化
//              原语。把 `respondApproval()` 里的 `awaitApprovalResolveSettled` + `begin...` 两处
//              去掉（恢复"直接发 RPC"的修前行为），本节两条竞态测试必然变红——红的形态正是
//              "同一个 reqId 出现了两条 approval.resolve"。

/// 一道可以被测试**精确按住再放开**的闸门——让 `approval.resolve` 的桩停在"RPC 已发出、响应未回"
/// 这个精确时刻，从而确定性地构造"人工决策与 stop 强制 deny 撞在同一个 reqId 上"的竞态。
///
/// 不靠 `Task.sleep` 猜时序：竞态测试如果靠睡眠去"大概率撞上"，绿了也不能证明什么（可能只是这次
/// 没撞上）。闸门让"两条路径确实同时在场"变成结构性事实。
/// 一个**全程只建立一次**的事件流旁听器。
///
/// 不能用现成的 `collectUpTo` 分阶段读：`AsyncThrowingStream` 是单消费者流，`collectUpTo` 每次调用
/// 都 `makeAsyncIterator()` 并在超时后 `cancelAll()`——第二次调用拿到的迭代器面对的是一条已经被
/// 取消消费者终结掉的流，之后 yield 的事件一条都读不到（实测：FSM 测试的"提升"阶段读到空数组，
/// 而同一时刻 actor 内部状态显示提升确实发生了）。本 tap 全程只 `for try await` 一次，测试按阶段
/// `drain()` 取走已到达的事件。
actor FSMEventTap {
    private var events: [EventMessageUnion] = []
    func append(_ event: EventMessageUnion) { events.append(event) }
    /// 取出并清空——让每个阶段的断言只面对"这个阶段新产生的事件"。
    func drain() -> [EventMessageUnion] {
        let snapshot = events
        events = []
        return snapshot
    }
}

func startFSMEventTap(_ stream: AsyncThrowingStream<EventMessageUnion, Error>) -> (FSMEventTap, Task<Void, Never>) {
    let tap = FSMEventTap()
    let task = Task {
        do {
            for try await event in stream { await tap.append(event) }
        } catch {
            // 流以错误收尾（session 终结等）——旁听器安静退出，已收到的事件仍可 drain。
        }
    }
    return (tap, task)
}

actor ApprovalResolveGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters = []
        for w in pending { w.resume() }
    }
}

/// **破坏性反证 A**：D1 §6.2「pending #2 缓冲策略」四条规则的一次性验证。
///
/// 修前（对抗审 ★ 实质发现①）：`emitApprovalRequestIfPossible` 对每一条到达的审批都直接
/// `continuation.yield`，没有 active/FIFO/有限深度任何一个概念——喂 4 条就会看到 4 条
/// `approval_request`，`ApprovalBufferResolvedEvent` 一条都不会有（该事件的构造函数当时没有任何
/// 调用点）。
///
/// 本测试把缓冲深度覆盖成 2（生产默认 8，见 `approvalBufferDefaultDepth` 的取值论证；本测试同时
/// 断言那个默认值本身，防止有人把它改成 0/负数让"缓冲"名存实亡），然后喂 4 条审批：
///   A -> active（唯一被 yield 的那条）  B,C -> 缓冲队列（队列满）  D -> 溢出
/// 逐条断言 D1 的四个 bullet：
///   ① 单 active + 串行呈现   ② 第二条起进 FIFO 且**不以任何形式**呈现给调用方
///   ③ 溢出不进队列、直接强制 deny 并产出 `ApprovalBufferResolvedEvent(queue_overflow)`
///   ④ #1 终态后 #2 浮现（提升）；缓冲期内被内核判超时的条目终态化并产出
///      `ApprovalBufferResolvedEvent(buffered_timeout)`，**不可再提升**
func testApprovalFSMSerializesToSingleActivePendingAndOverflowsBeyondDepth() async -> Bool {
    let name = "rounds/0015 返工 反证A (D1 §6.2): 单 active pending + 有限深度 FIFO + 溢出 queue_overflow + 提升/buffered_timeout"

    guard OpenclawGatewayKernelClient.approvalBufferDefaultDepth >= 1 else {
        return fail(name, "生产默认缓冲深度必须 >=1（否则 D1『不丢弃，缓冲/排队』形同虚设），实际 \(OpenclawGatewayKernelClient.approvalBufferDefaultDepth)")
    }
    guard OpenclawGatewayKernelClient.approvalBufferDefaultDepth == 8 else {
        return fail(name, "生产默认缓冲深度应为已文档化的 8，实际 \(OpenclawGatewayKernelClient.approvalBufferDefaultDepth)——改动请同步更新该常量的取值论证")
    }

    let client = freshClient()
    let sessionID = "sess-approval-fsm"
    let kernelKey = "kernel-key-approval-fsm"
    let runID = "run-approval-fsm"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let (tap, tapTask) = startFSMEventTap(stream)
    defer { tapTask.cancel() }
    await client.testSupportSetApprovalBufferDepth(2)

    let callLog = CallOrderLog()
    let paramsBox = ParamsBox()
    await client.testSupportStubRPC(method: "approval.resolve") { params in
        await callLog.record("approval.resolve")
        await paramsBox.record(params)
        let id = (params["id"] as? String) ?? ""
        let requested = (params["decision"] as? String) ?? ""
        if requested == "deny" {
            return ["applied": true, "approval": [
                "id": id, "status": "denied", "decision": "deny", "reason": "user",
            ] as JSONObject] as JSONObject
        }
        return ["applied": true, "approval": [
            "id": id, "status": "allowed", "decision": requested, "reason": "user",
        ] as JSONObject] as JSONObject
    }

    // ---- 喂 4 条审批：A(active) / B,C(缓冲满) / D(溢出) ----
    for approvalID in ["fsm-a", "fsm-b", "fsm-c", "fsm-d"] {
        _ = await feedRealApprovalRequest(
            client, kernelKey: kernelKey, runID: runID,
            approvalID: approvalID, toolCallID: "tool-\(approvalID)",
            commandText: "echo \(approvalID)"
        )
    }
    // 溢出 deny 是一个 detached Task（同步占住 in-flight 槽位之后才派生，见 beginQueueOverflowDeny），
    // 给它一个往返窗口。
    try? await Task.sleep(nanoseconds: 80_000_000)

    // ① 单 active
    let active1 = await client.testSupportActiveApprovalReqID(sessionID: sessionID)
    guard active1 == "fsm-a" else {
        return fail(name, "期望 active pending 恒为最早到达的 fsm-a，实际 \(active1 ?? "nil")——单 active 约束被拆除时这里会是 fsm-d 或 nil")
    }
    // ② FIFO 缓冲（顺序即到达顺序），D 不在队列里（溢出不入队）
    let buffered1 = await client.testSupportBufferedApprovalReqIDs(sessionID: sessionID)
    guard buffered1 == ["fsm-b", "fsm-c"] else {
        return fail(name, "期望缓冲队列 [fsm-b, fsm-c]（深度 2 已满，fsm-d 溢出不入队），实际 \(buffered1)")
    }
    // ②' 只有 active 那条进了"pending 等待决策"表——B/C/D 都没有
    for buffered in ["fsm-b", "fsm-c", "fsm-d"] {
        guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: buffered) == false else {
            return fail(name, "\(buffered) 尚未被呈现，不该进入 pending-awaiting-decision 表")
        }
    }
    // ③ 溢出：恰好一条 approval.resolve(deny) 发给 fsm-d
    let overflowCalls = await paramsBox.calls
    guard overflowCalls.count == 1,
          overflowCalls[0]["id"] as? String == "fsm-d",
          overflowCalls[0]["decision"] as? String == "deny" else {
        return fail(name, "期望恰好一条针对 fsm-d 的强制 deny（D1 fail-closed），实际 \(overflowCalls)")
    }

    // ---- 事件流：到此为止**只应有两条**事件 ----
    let phase1 = await tap.drain()
    guard phase1.count == 2 else {
        let types = phase1.map { describeEventKindForFSMTest($0) }
        return fail(name, "喂了 4 条审批，事件流却有 \(phase1.count) 条事件 \(types)——期望恰好 2 条（approval_request(fsm-a) + approval_buffer_resolved(fsm-d)）。单 active 约束被拆除时这里会看到 4 条 approval_request")
    }
    guard case .approvalRequest(let reqA) = phase1[0], reqA.payload.reqID == "fsm-a" else {
        return fail(name, "第一条事件应是 approval_request(fsm-a)，实际 \(describeEventKindForFSMTest(phase1[0]))")
    }
    guard case .approvalBufferResolved(let overflowEvent) = phase1[1],
          overflowEvent.payload.reqID == "fsm-d",
          overflowEvent.payload.reason == .queueOverflow else {
        return fail(name, "第二条事件应是 approval_buffer_resolved(fsm-d, queue_overflow)，实际 \(describeEventKindForFSMTest(phase1[1]))")
    }

    // ---- ④ #1 终态（人工 allow-once）-> #2 浮现 ----
    let handle = testHandleFor(sessionID, kernelKey)
    do {
        try await client.respondApproval(session: handle, reqID: "fsm-a", decision: Decision(
            outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil
        ))
    } catch {
        return fail(name, "对 active pending 的人工 allow-once 本应成功，却抛了 \(error)")
    }
    let active2 = await client.testSupportActiveApprovalReqID(sessionID: sessionID)
    guard active2 == "fsm-b" else {
        return fail(name, "active pending 终态后应提升队头 fsm-b，实际 \(active2 ?? "nil")")
    }
    let buffered2 = await client.testSupportBufferedApprovalReqIDs(sessionID: sessionID)
    guard buffered2 == ["fsm-c"] else {
        return fail(name, "提升后缓冲队列应只剩 [fsm-c]，实际 \(buffered2)")
    }
    try? await Task.sleep(nanoseconds: 40_000_000)
    let phase2 = await tap.drain()
    guard phase2.count == 1, case .approvalRequest(let reqB) = phase2[0], reqB.payload.reqID == "fsm-b" else {
        return fail(name, "提升应恰好产出一条 approval_request(fsm-b)，实际 \(phase2.map { describeEventKindForFSMTest($0) })")
    }
    // 提升不得虚构一个"刚刚开始计时"的假象：ts/timeoutMs 全部沿用内核时间戳，与 fsm-a 逐字一致
    guard reqB.payload.timeoutMS == reqA.payload.timeoutMS, reqB.ts == reqA.ts else {
        return fail(name, "提升时 ts/timeoutMs 应据实沿用内核时间戳（D1：不得虚构『刚刚开始计时』），实际 ts=\(reqB.ts) timeoutMs=\(reqB.payload.timeoutMS)")
    }

    // ---- ④' 仍在缓冲队列里的 fsm-c 被内核判超时 -> buffered_timeout，且不可再提升 ----
    await client.testSupportFeedFrame([
        "type": "event", "event": "session.approval",
        "payload": [
            "sessionKey": kernelKey, "updatedAtMs": 1_784_873_900_000, "phase": "terminal",
            // openclaw TerminalApprovalSnapshot：status:"expired" 的 reason 由 schema 收窄为唯一
            // 取值 "timeout"（approvals.ts:59-60），即 D1 五态的 TIMED_OUT_DENY 内核侧信号。
            "approval": [
                "id": "fsm-c", "status": "expired", "reason": "timeout", "resolvedAtMs": 1_784_873_900_000,
            ] as JSONObject,
        ] as JSONObject,
    ])
    let buffered3 = await client.testSupportBufferedApprovalReqIDs(sessionID: sessionID)
    guard buffered3.isEmpty else {
        return fail(name, "缓冲期内被内核判超时的 fsm-c 应立即移出队列（D1：不可再提升），实际队列 \(buffered3)")
    }
    guard await client.testSupportActiveApprovalReqID(sessionID: sessionID) == "fsm-b" else {
        return fail(name, "fsm-c 的超时不应影响仍然 active 的 fsm-b")
    }
    try? await Task.sleep(nanoseconds: 40_000_000)
    let phase3 = await tap.drain()
    guard phase3.count == 1, case .approvalBufferResolved(let timeoutEvent) = phase3[0],
          timeoutEvent.payload.reqID == "fsm-c", timeoutEvent.payload.reason == .bufferedTimeout else {
        return fail(name, "应恰好产出一条 approval_buffer_resolved(fsm-c, buffered_timeout)，实际 \(phase3.map { describeEventKindForFSMTest($0) })")
    }

    print("  [evidence] FSM: 喂 4 条审批(深度=2) -> 事件流只有 approval_request(fsm-a) + approval_buffer_resolved(fsm-d,queue_overflow)；" +
          "active=fsm-a，缓冲=[fsm-b,fsm-c]；fsm-d 收到唯一一条强制 deny")
    print("  [evidence] FSM: 人工 allow-once(fsm-a) -> 提升 fsm-b（ts/timeoutMs 逐字沿用内核时间戳，未重置计时）；" +
          "缓冲中的 fsm-c 收到内核 expired/timeout -> approval_buffer_resolved(fsm-c,buffered_timeout) 且不再提升")
    return pass(name, "D1 §6.2 四条规则（单 active 串行呈现 / 有限深度 FIFO 不呈现 / 溢出 fail-closed deny + queue_overflow / 提升 + buffered_timeout）逐条成立")
}

/// 只给上面那条测试的失败信息用——把事件变体名打出来，不然 fail 消息里只能看到一个不可读的枚举。
func describeEventKindForFSMTest(_ event: EventMessageUnion) -> String {
    switch event {
    case .approvalRequest(let e): return "approval_request(\(e.payload.reqID))"
    case .approvalBufferResolved(let e): return "approval_buffer_resolved(\(e.payload.reqID),\(e.payload.reason.rawValue))"
    case .turnComplete: return "turn_complete"
    case .sessionEnd: return "session_end"
    case .operationCompleted: return "operation_completed"
    case .error: return "error"
    case .messageDelta: return "message_delta"
    case .thinking: return "thinking"
    case .toolCall: return "tool_call"
    case .toolResult: return "tool_result"
    case .capabilityChanged: return "capability_changed"
    }
}

/// **破坏性反证 B（上半：stop 的强制 deny 在途，人工决策随后到达）**。
///
/// 修前（对抗审 ★ 实质发现②）：`forceDenyPendingApprovalsBeforeStop` 的每次
/// `await request("approval.resolve")` 都是一个 actor 重入点；用户在这个窗口里点按钮，
/// `respondApproval()` 看到的 `pendingApprovalsByReqID[reqID]` **仍然存在**（该表要等 RPC 返回才摘
/// 条目），于是对**同一个 reqId** 并行发出第二条 `approval.resolve`——两条决议对同一次审批赛跑，
/// 结果由到达顺序决定，且调用方两边都会被告知"成功"。
///
/// 本测试用闸门把强制 deny 精确按在"RPC 已发出、响应未回"的那一刻，在此时发起人工 allow-once，
/// 断言三件事：**只有一条 `approval.resolve` 发出**、人工那一侧拿到**明确错误**
/// （`approval_not_pending`，不是静默成功）、强制 deny 的结果确定（reqId 进
/// `forceResolvedApprovals`）。
func testStopForceDenyAndManualRespondOnSameReqIDEmitExactlyOneResolve() async -> Bool {
    let name = "rounds/0015 返工 反证B①: stop 强制 deny 在途时人工响应同一 reqId —— 只发一条 approval.resolve，人工侧拿到 approval_not_pending"
    let client = freshClient()
    let sessionID = "sess-race-stop-first"
    let kernelKey = "kernel-key-race-stop-first"
    let runID = "run-race-stop-first"
    let approvalID = "approval-race-stop-first"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    let paramsBox = ParamsBox()
    let gate = ApprovalResolveGate()

    guard await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: runID,
        approvalID: approvalID, toolCallID: "tool-race-1", commandText: "rm -rf /tmp/race"
    ) else {
        return fail(name, "前置：审批未能进入 pending-awaiting-decision 态")
    }

    await client.testSupportStubRPC(method: "approval.resolve") { params in
        await callLog.record("approval.resolve")
        await paramsBox.record(params)
        // 按住：模拟"RPC 已发出、内核尚未回应"的真实窗口。
        await gate.wait()
        let requested = (params["decision"] as? String) ?? ""
        if requested == "deny" {
            return ["applied": true, "approval": [
                "id": approvalID, "status": "denied", "decision": "deny", "reason": "user",
            ] as JSONObject] as JSONObject
        }
        return ["applied": true, "approval": [
            "id": approvalID, "status": "allowed", "decision": requested, "reason": "user",
        ] as JSONObject] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }

    let handle = testHandleFor(sessionID, kernelKey)
    let stopTask = Task { try await client.stop(session: handle) }
    try? await Task.sleep(nanoseconds: 80_000_000)

    // 结构性事实（不是靠睡眠碰运气）：强制 deny 此刻确实卡在 in-flight 状态。
    let inFlight = await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID)
    guard inFlight == [approvalID] else {
        return fail(name, "期望强制 deny 此刻正卡在 in-flight，实际在途集合 \(inFlight)")
    }
    guard await callLog.entries == ["approval.resolve"] else {
        return fail(name, "此刻 sessions.abort 不应已被调用（D1 §6.2 M3 定序），实际 \(await callLog.entries)")
    }

    // 用户此刻点了"允许一次"。
    let manualTask = Task {
        try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
            outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil
        ))
    }
    try? await Task.sleep(nanoseconds: 80_000_000)
    await gate.open()

    // stop() 放行后会等 aborted lifecycle 终态——喂真实形状的帧唤醒它。
    try? await Task.sleep(nanoseconds: 80_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_000_500,
        ] as JSONObject,
    ])

    let manualOutcome = await manualTask.result
    let stopOutcome = await stopTask.result

    // ① 只有一条 approval.resolve —— 反证的核心断言。
    let resolveCalls = await paramsBox.calls
    guard resolveCalls.count == 1 else {
        return fail(name, "同一个 reqId 竟然发出了 \(resolveCalls.count) 条 approval.resolve：\(resolveCalls) —— 串行化被拆除时正是这个形态")
    }
    guard resolveCalls[0]["decision"] as? String == "deny" else {
        return fail(name, "唯一那条决议应是 stop 的强制 deny（它先抢到 in-flight 槽位），实际 \(resolveCalls[0])")
    }
    // ② 人工侧必须拿到明确错误，不是静默成功
    switch manualOutcome {
    case .success:
        return fail(name, "人工 allow-once 竟然报告成功——但这次审批实际是被 stop 强制 deny 掉的，这正是『静默成功』")
    case .failure(let error):
        guard let approvalError = error as? ApprovalDecisionError,
              case .approvalNotPending(let erroredReqID) = approvalError, erroredReqID == approvalID else {
            return fail(name, "人工侧应拿到 approval_not_pending，实际 \(error)")
        }
    }
    // ③ 强制 deny 的结果确定
    guard let stopResult = try? stopOutcome.get(), stopResult.outcome == .succeeded else {
        return fail(name, "stop() 应正常 succeeded，实际 \(stopOutcome)")
    }
    let order = await callLog.entries
    guard order == ["approval.resolve", "sessions.abort", "sessions.delete"] else {
        return fail(name, "RPC 顺序应是 [approval.resolve, sessions.abort, sessions.delete]，实际 \(order)")
    }
    let events = await collectUpTo(stream, maxCount: 6)
    guard let turn = events.compactMap({ event -> TurnCompleteEventMessage? in
        if case .turnComplete(let e) = event { return e }
        return nil
    }).first else {
        return fail(name, "事件流缺少 turn_complete：\(events.map { describeEventKindForFSMTest($0) })")
    }
    guard turn.payload.forceResolvedApprovals == [approvalID] else {
        return fail(name, "被强制 deny 的 reqId 应列在 forceResolvedApprovals，实际 \(turn.payload.forceResolvedApprovals ?? [])")
    }
    guard await client.testSupportHasPendingApprovalAwaitingDecision(reqID: approvalID) == false else {
        return fail(name, "该 reqId 应已从 pending 表移除")
    }

    print("  [evidence] 竞态①(stop 先抢到槽位)：approval.resolve 调用 1 次（decision=deny）；" +
          "人工 allow-once -> ApprovalDecisionError.approvalNotPending；forceResolvedApprovals=[\(approvalID)]")
    return pass(name, "两条路径撞同一 reqId 时只发出一条 approval.resolve，结果确定，落败方拿到明确错误而非静默成功")
}

/// **破坏性反证 B（下半：人工决策在途，stop 的强制 deny 随后到达）**——与上半是同一竞态的另一个
/// 到达顺序，断言的却是 D1 §6.2 **失败分支 3** 的原文行为：
///
/// > "适配器尝试强制 deny 之前，approval 已经被人工 `respondApproval` 抢先进入 `RESOLVED_ALLOW`/
/// > `RESOLVED_DENY` 终态……这是真正的竞态，不是失败。适配器……直接放弃这一步，照常推进到②
/// > （abort/cancel）——run 本身仍需按 interrupt/stop 的原始意图被中止。该 reqId **不**出现在
/// > `TurnCompleteEvent.forceResolvedApprovals` 里。"
///
/// 三件事：`sessions.abort` **必须等**在途人工决议落地才发出（否则"cancel 已生效、审批还在被异步
/// 决策"）；只发一条 `approval.resolve`；该 reqId **不**进 `forceResolvedApprovals`。
func testManualRespondInFlightBlocksStopAbortAndIsNotCountedAsForceResolved() async -> Bool {
    let name = "rounds/0015 返工 反证B②: 人工决议在途时 stop 必须等它落地（D1 §6.2 分支3）—— 只发一条 resolve，且不计入 forceResolvedApprovals"
    let client = freshClient()
    let sessionID = "sess-race-manual-first"
    let kernelKey = "kernel-key-race-manual-first"
    let runID = "run-race-manual-first"
    let approvalID = "approval-race-manual-first"
    let stream = await client.testSupportRegisterSession(ourSessionID: sessionID, kernelKey: kernelKey)
    let callLog = CallOrderLog()
    let paramsBox = ParamsBox()
    let gate = ApprovalResolveGate()

    guard await feedRealApprovalRequest(
        client, kernelKey: kernelKey, runID: runID,
        approvalID: approvalID, toolCallID: "tool-race-2", commandText: "echo race-2"
    ) else {
        return fail(name, "前置：审批未能进入 pending-awaiting-decision 态")
    }

    await client.testSupportStubRPC(method: "approval.resolve") { params in
        await callLog.record("approval.resolve")
        await paramsBox.record(params)
        await gate.wait()
        let requested = (params["decision"] as? String) ?? ""
        if requested == "deny" {
            return ["applied": true, "approval": [
                "id": approvalID, "status": "denied", "decision": "deny", "reason": "user",
            ] as JSONObject] as JSONObject
        }
        return ["applied": true, "approval": [
            "id": approvalID, "status": "allowed", "decision": requested, "reason": "user",
        ] as JSONObject] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.abort") { _ in
        await callLog.record("sessions.abort")
        return ["ok": true, "abortedRunId": runID, "status": "aborted"] as JSONObject
    }
    await client.testSupportStubRPC(method: "sessions.delete") { _ in
        await callLog.record("sessions.delete")
        return ["deleted": true] as JSONObject
    }

    let handle = testHandleFor(sessionID, kernelKey)
    // 用户先点了"允许一次"，RPC 卡在闸门上。
    let manualTask = Task {
        try await client.respondApproval(session: handle, reqID: approvalID, decision: Decision(
            outcome: .allowOnce, updatedInput: nil, scope: nil, reason: nil
        ))
    }
    try? await Task.sleep(nanoseconds: 80_000_000)
    guard await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID) == [approvalID] else {
        return fail(name, "期望人工决议此刻卡在 in-flight，实际 \(await client.testSupportInFlightApprovalResolveReqIDs(sessionID: sessionID))")
    }

    // 此刻 stop() 到来。
    let stopTask = Task { try await client.stop(session: handle) }
    try? await Task.sleep(nanoseconds: 120_000_000)

    // ① sessions.abort 必须还没发——drain 收敛条件把它挡在在途决议之后。
    let orderBeforeGate = await callLog.entries
    guard orderBeforeGate == ["approval.resolve"] else {
        return fail(name, "在途人工决议尚未落地，sessions.abort 不应已被发出，实际调用序列 \(orderBeforeGate) —— in-flight 收敛条件被拆除时正是这个形态")
    }

    await gate.open()
    try? await Task.sleep(nanoseconds: 100_000_000)
    await client.testSupportFeedFrame([
        "type": "event", "event": "agent",
        "payload": [
            "runId": runID, "sessionKey": kernelKey, "stream": "lifecycle",
            "data": ["phase": "end", "status": "cancelled", "aborted": true, "stopReason": "rpc"] as JSONObject,
            "ts": 1_784_872_000_500,
        ] as JSONObject,
    ])

    let manualOutcome = await manualTask.result
    let stopOutcome = await stopTask.result

    // ② 只有一条 approval.resolve，且是人工那条（allow-once）
    let resolveCalls = await paramsBox.calls
    guard resolveCalls.count == 1, resolveCalls[0]["decision"] as? String == "allow-once" else {
        return fail(name, "期望恰好一条人工 allow-once 决议，实际 \(resolveCalls)")
    }
    guard (try? manualOutcome.get()) != nil else {
        return fail(name, "人工 allow-once 先抢到槽位，应正常成功，实际 \(manualOutcome)")
    }
    // ③ stop 照常推进，但该 reqId 不计入 forceResolvedApprovals（D1 §6.2 分支 3）
    guard let stopResult = try? stopOutcome.get(), stopResult.outcome == .succeeded else {
        return fail(name, "stop() 应照常推进并 succeeded（D1：run 仍需被中止），实际 \(stopOutcome)")
    }
    let order = await callLog.entries
    guard order == ["approval.resolve", "sessions.abort", "sessions.delete"] else {
        return fail(name, "RPC 顺序应是 [approval.resolve, sessions.abort, sessions.delete]，实际 \(order)")
    }
    let events = await collectUpTo(stream, maxCount: 6)
    guard let turn = events.compactMap({ event -> TurnCompleteEventMessage? in
        if case .turnComplete(let e) = event { return e }
        return nil
    }).first else {
        return fail(name, "事件流缺少 turn_complete：\(events.map { describeEventKindForFSMTest($0) })")
    }
    let forceResolved = turn.payload.forceResolvedApprovals ?? []
    guard !forceResolved.contains(approvalID) else {
        return fail(name, "被人工抢先终态化的 reqId 不得出现在 forceResolvedApprovals（D1 §6.2 分支3 原文），实际 \(forceResolved)")
    }

    print("  [evidence] 竞态②(人工先抢到槽位)：sessions.abort 被 in-flight 收敛条件挡住直到人工决议落地；" +
          "approval.resolve 调用 1 次（decision=allow-once）；forceResolvedApprovals=\(forceResolved)（不含 \(approvalID)）")
    return pass(name, "在途人工决议阻塞 sessions.abort 直至落地；只发一条决议；D1 §6.2 分支 3 的『不计入 forceResolvedApprovals』成立")
}

/// rounds/0015 返工①的 UI 侧落点：D1 §6.2「缓冲生命周期的独立可见性」要求"不得让一条从未被看见的
/// 请求静默消失"。壳这边唯一可能的落点是会话流里的一条系统行——卡片是结构性不可能有的（缓冲期的
/// 请求从未被 yield 成 `approval_request`）。修前 `SessionStore.handle` 把 `.approvalBufferResolved`
/// 和 thinking/toolCall 一起丢进 `break`，这条事件到达后**界面上没有任何痕迹**。
@MainActor
func testSessionStoreSurfacesApprovalBufferResolvedAsSystemLine() async -> Bool {
    let name = "rounds/0015 返工 (D1 §6.2 可见性): SessionStore 把 approval_buffer_resolved 呈现为系统行，不再静默丢弃"
    let store = SessionStore(config: KernelShellConfig(endpoint: URL(string: "ws://127.0.0.1:1")!, token: "t", configWarning: nil))
    let handle = testHandle(sessionID: "sess-buffer-ui", kernelKey: "kernel-key-buffer-ui")
    let session = ChatSessionViewModel(handle: handle, title: "缓冲可见性测试")

    for (reqID, reason) in [("buf-overflow-1", FluffyReason.queueOverflow), ("buf-timeout-1", FluffyReason.bufferedTimeout)] {
        store.handle(.approvalBufferResolved(ApprovalBufferResolvedEventMessage(
            direction: .event,
            payload: ApprovalBufferResolvedEventMessagePayload(reason: reason, reqID: reqID),
            runID: nil, sentAt: Date(), seq: 1, sessionID: "sess-buffer-ui", ts: Date(),
            type: .evtApprovalBufferResolved
        )), for: session)
    }

    let systemLines = session.messages.filter { $0.role == .system }.map(\.text)
    guard systemLines.count == 2 else {
        return fail(name, "两条 approval_buffer_resolved 应各留下一条系统行，实际 \(systemLines)")
    }
    guard systemLines[0].contains("buf-overflow-1"), systemLines[0].contains("队列已满"),
          systemLines[1].contains("buf-timeout-1"), systemLines[1].contains("超时") else {
        return fail(name, "系统行必须点明 reqId 与两种 reason 各自的真实原因，实际 \(systemLines)")
    }
    guard session.pendingApprovals.isEmpty else {
        return fail(name, "缓冲期请求从未产出过卡片，这里不该凭空多出卡片")
    }
    print("  [evidence] 缓冲可见性：\(systemLines.joined(separator: " | "))")
    return pass(name, "queue_overflow / buffered_timeout 各自留下一条点明 reqId 与真实原因的系统行，不再静默丢弃")
}
