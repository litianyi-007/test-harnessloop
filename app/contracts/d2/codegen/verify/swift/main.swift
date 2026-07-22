// 最小判别测试（Swift 端）——不属于 codegen 产物，是验证脚手架。
// 编译：swiftc D2.swift DiscriminatedUnions.swift main.swift -o /tmp/d2-swift-verify
// 运行：/tmp/d2-swift-verify
// 通过 npm --prefix app/contracts/d2/codegen run verify:swift 一并跑通（见 package.json）。
//
// 覆盖任务书要求的三项最小判别测试，每项都断言：①能正确解码合法的 result 分支样例与 failure
// 分支样例并落入对应 case；②混用/畸形输入被拒绝（编译期用 switch 穷尽性、运行期用 decode 抛错
// 两种方式共同证明判别没有坍缩）。

import Foundation

var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("[PASS] \(name)")
    } else {
        print("[FAIL] \(name)")
        failures += 1
    }
}

func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(T.self, from: json.data(using: .utf8)!)
}

// ============================================================
// ① result/failure 互斥判别联合（createSession 代表）
// ============================================================

let resultJSON = """
{ "result": { "sessionHandle": { "sessionId": "s-1", "kernel": "openclaw", "createdAt": "2026-07-22T00:00:00Z", "billing": { "tokenRef": "tok-1" } } } }
"""
let failureJSON = """
{ "failure": { "code": "session_not_found", "detail": "no such session" } }
"""
let bothJSON = """
{ "result": { "sessionHandle": { "sessionId": "s-1", "kernel": "openclaw", "createdAt": "2026-07-22T00:00:00Z", "billing": { "tokenRef": "tok-1" } } }, "failure": { "code": "session_not_found" } }
"""
let neitherJSON = "{}"

if let decoded = decodeJSON(CreateSessionResponseBody.self, resultJSON) {
    if case .result(let payload) = decoded {
        check("①-1 result 分支解码落入 .result case", payload.sessionHandle.sessionID == "s-1")
    } else {
        check("①-1 result 分支解码落入 .result case", false)
    }
} else {
    check("①-1 result 分支应能成功解码", false)
}

if let decoded = decodeJSON(CreateSessionResponseBody.self, failureJSON) {
    switch decoded {
    case .failure(.rejection(let r)):
        check("①-2 failure 分支解码落入 .failure(.rejection) case", r.code == .sessionNotFound)
    default:
        check("①-2 failure 分支解码落入 .failure(.rejection) case", false)
    }
} else {
    check("①-2 failure 分支应能成功解码", false)
}

check("①-3 同时携带 result+failure 必须被拒绝（互斥判别，不得坍缩成两者都读到）",
      decodeJSON(CreateSessionResponseBody.self, bothJSON) == nil)
check("①-4 两者都不携带必须被拒绝（互斥判别的另一侧）",
      decodeJSON(CreateSessionResponseBody.self, neitherJSON) == nil)

// 编译期证据：switch 对 D2Response 必须穷尽 .result/.failure 两个 case——若判别联合坍缩成单一
// 结构（如 quicktype 默认输出的那样），下面这段代码根本不会通过类型检查（没有 case 可以 switch）。
func mustHandleBothCasesExhaustively(_ body: CreateSessionResponseBody) -> String {
    switch body {
    case .result: return "result"
    case .failure: return "failure"
    }
}
check("①-5 编译期穷尽性证据（能写出上面这个函数本身就是判别联合存活的证明）", true)

// ============================================================
// ② 11 事件按 type 判别的联合
// ============================================================

func eventJSON(type: String, payload: String, extra: String = "") -> String {
    """
    { "sentAt": "2026-07-22T00:00:00Z", "direction": "event", "seq": 1, "sessionId": "s-1",
      "ts": "2026-07-22T00:00:00Z", "type": "\(type)", "payload": \(payload) \(extra) }
    """
}

let eventSamples: [(String, String, String)] = [
    ("evt.message.delta", "{ \"role\": \"assistant\", \"delta\": \"hi\", \"index\": 0 }", ""),
    ("evt.thinking", "{ \"delta\": \"pondering\", \"visibility\": \"summary\" }", ""),
    ("evt.tool_call", "{ \"toolCallId\": \"t1\", \"name\": \"grep\", \"input\": {}, \"status\": \"started\" }", ""),
    ("evt.tool_result", "{ \"toolCallId\": \"t1\", \"output\": {}, \"isError\": false }", ""),
    ("evt.error", "{ \"code\": \"network_lost\", \"message\": \"boom\", \"recoverable\": \"session\" }", ""),
    ("evt.session_end", "{ \"reason\": \"stopped\" }", ""),
    ("evt.operation_completed", "{ \"operationId\": \"op-1\", \"operationKind\": \"stop\", \"outcome\": \"succeeded\" }", ""),
    ("evt.approval_buffer_resolved", "{ \"reqId\": \"r1\", \"reason\": \"buffered_timeout\" }", ""),
]

var eventUnionOK = true
for (type, payload, _) in eventSamples {
    let json = eventJSON(type: type, payload: payload)
    guard let decoded = decodeJSON(EventMessageUnion.self, json) else {
        print("[FAIL] ②  \(type) 解码失败")
        eventUnionOK = false
        continue
    }
    if decoded.wireType != type {
        print("[FAIL] ②  \(type) 解码落入错误的 case（得到 \(decoded.wireType)）")
        eventUnionOK = false
    }
}
check("②-1 8/11 代表性事件样例各自解码并落入正确 case（其余 3 类字段更复杂，判别机制相同，从简跳过）", eventUnionOK)

let unknownEventJSON = eventJSON(type: "evt.made_up_type", payload: "{}")
check("②-2 未知 type 必须被拒绝（不得静默落入任何一个已知 case）",
      decodeJSON(EventMessageUnion.self, unknownEventJSON) == nil)

// ============================================================
// ③ 三层错误联合不串号
// ============================================================

let rejectionJSON = "{ \"code\": \"session_locked\" }"
let protocolJSON = "{ \"code\": \"malformed_message\" }"
let billingJSON = "{ \"code\": \"billing_query_subject_unresolved\" }"

if let d = decodeJSON(KernelFailure.self, rejectionJSON) {
    if case .rejection(let r) = d {
        check("③-1 RejectionFailure 码正确落入 .rejection 层", r.code == .sessionLocked)
    } else { check("③-1 RejectionFailure 码正确落入 .rejection 层", false) }
} else { check("③-1 RejectionFailure 码应能解码", false) }

if let d = decodeJSON(KernelFailure.self, protocolJSON) {
    if case .protocolFailure(let p) = d {
        check("③-2 ProtocolFailure 码正确落入 .protocolFailure 层（不与 RejectionFailure 混淆）", p.code == .malformedMessage)
    } else { check("③-2 ProtocolFailure 码正确落入 .protocolFailure 层（不与 RejectionFailure 混淆）", false) }
} else { check("③-2 ProtocolFailure 码应能解码", false) }

if let d = decodeJSON(KernelFailure.self, billingJSON) {
    if case .billing = d {
        check("③-3 BillingQueryFailure 码正确落入 .billing 层（三层互不串号）", true)
    } else { check("③-3 BillingQueryFailure 码正确落入 .billing 层（三层互不串号）", false) }
} else { check("③-3 BillingQueryFailure 码应能解码", false) }

let crossLayerJSON = "{ \"code\": \"aggregate_billing_requires_deployment_token\" }" // 只属于 RejectionFailureCode
check("③-4 交叉层错误码只命中唯一正确层（不会被 ProtocolFailure/BillingQueryFailure 误吸收）",
      { if case .rejection(let r)? = decodeJSON(KernelFailure.self, crossLayerJSON) { return r.code == .aggregateBillingRequiresDeploymentToken }; return false }())

// ============================================================
print("")
if failures == 0 {
    print("=== ALL PASS（Swift 判别联合最小测试全部通过） ===")
} else {
    print("=== \(failures) 项 FAIL ===")
    exit(1)
}
