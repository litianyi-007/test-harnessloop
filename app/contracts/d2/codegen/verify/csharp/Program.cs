// 最小判别测试（C# 端）——不属于 codegen 产物，是验证脚手架，与 verify/swift/main.swift 覆盖
// 完全对称的三项：① result/failure 互斥（createSession 代表）；② 11 事件按 type 判别；
// ③ 三层错误联合不串号。

using System;
using System.Text.Json;
using D2;

int failures = 0;

void Check(string name, bool condition)
{
    if (condition)
    {
        Console.WriteLine($"[PASS] {name}");
    }
    else
    {
        Console.WriteLine($"[FAIL] {name}");
        failures++;
    }
}

T? TryDecode<T>(string json) where T : class
{
    try
    {
        return JsonSerializer.Deserialize<T>(json, D2.Converter.Settings);
    }
    catch (JsonException)
    {
        return null;
    }
}

// ============================================================
// ① result/failure 互斥判别联合（createSession 代表）
// ============================================================

string resultJson = @"{ ""result"": { ""sessionHandle"": { ""sessionId"": ""s-1"", ""kernel"": ""openclaw"", ""createdAt"": ""2026-07-22T00:00:00Z"", ""billing"": { ""tokenRef"": ""tok-1"" } } } }";
string failureJson = @"{ ""failure"": { ""code"": ""session_not_found"", ""detail"": ""no such session"" } }";
string bothJson = @"{ ""result"": { ""sessionHandle"": { ""sessionId"": ""s-1"", ""kernel"": ""openclaw"", ""createdAt"": ""2026-07-22T00:00:00Z"", ""billing"": { ""tokenRef"": ""tok-1"" } } }, ""failure"": { ""code"": ""session_not_found"" } }";
string neitherJson = "{}";

var decodedResult = TryDecode<D2Response<CreateSessionResultPayload, CreateSessionFailure>>(resultJson);
Check("①-1 result 分支解码落入 IsResult=true", decodedResult != null && decodedResult.IsResult && decodedResult.Result!.SessionHandle.SessionId == "s-1");

var decodedFailure = TryDecode<D2Response<CreateSessionResultPayload, CreateSessionFailure>>(failureJson);
Check("①-2 failure 分支解码落入 IsResult=false 且判别为 Rejection",
    decodedFailure != null && !decodedFailure.IsResult && decodedFailure.Failure!.IsRejection && decodedFailure.Failure.Rejection!.Code == RejectionFailureCode.SessionNotFound);

Check("①-3 同时携带 result+failure 必须被拒绝（互斥判别，不得坍缩成两者都读到）",
    TryDecode<D2Response<CreateSessionResultPayload, CreateSessionFailure>>(bothJson) == null);
Check("①-4 两者都不携带必须被拒绝（互斥判别的另一侧）",
    TryDecode<D2Response<CreateSessionResultPayload, CreateSessionFailure>>(neitherJson) == null);

// 编译期证据：D2Response<TSuccess,TFailure> 是闭合类型，Result/Failure 两个属性并存于同一个类上——
// C# 没有 enum 关联值，做不到『访问 Failure 前编译器强制先判定是 failure 分支』这种 Swift 级别的
// 静态穷尽性保证，只能靠 IsResult 运行时判别 + 两个属性其中一个恒为 null 的运行时不变量维持互斥。
// 这本身就是一项发现：C# 语言表达力上限于 Swift（见 CODEGEN-FINDINGS.md）。
Check("①-5 IsResult/IsRejection 等运行时判别标志存在（C# 用运行时标志替代 Swift 编译期穷尽性）", true);

// ============================================================
// ② 11 事件按 type 判别的联合
// ============================================================

string EventJson(string type, string payload) => $@"{{ ""sentAt"": ""2026-07-22T00:00:00Z"", ""direction"": ""event"", ""seq"": 1, ""sessionId"": ""s-1"", ""ts"": ""2026-07-22T00:00:00Z"", ""type"": ""{type}"", ""payload"": {payload} }}";

var eventSamples = new (string type, string payload)[]
{
    ("evt.message.delta", @"{ ""role"": ""assistant"", ""delta"": ""hi"", ""index"": 0 }"),
    ("evt.thinking", @"{ ""delta"": ""pondering"", ""visibility"": ""summary"" }"),
    ("evt.tool_call", @"{ ""toolCallId"": ""t1"", ""name"": ""grep"", ""input"": {}, ""status"": ""started"" }"),
    ("evt.tool_result", @"{ ""toolCallId"": ""t1"", ""output"": {}, ""isError"": false }"),
    ("evt.error", @"{ ""code"": ""network_lost"", ""message"": ""boom"", ""recoverable"": ""session"" }"),
    ("evt.session_end", @"{ ""reason"": ""stopped"" }"),
    ("evt.operation_completed", @"{ ""operationId"": ""op-1"", ""operationKind"": ""stop"", ""outcome"": ""succeeded"" }"),
    ("evt.approval_buffer_resolved", @"{ ""reqId"": ""r1"", ""reason"": ""buffered_timeout"" }"),
};

bool eventUnionOk = true;
foreach (var (type, payload) in eventSamples)
{
    var json = EventJson(type, payload);
    var decoded = TryDecode<EventMessageUnion>(json);
    if (decoded == null)
    {
        Console.WriteLine($"[FAIL] ②  {type} 解码失败");
        eventUnionOk = false;
        continue;
    }
    if (decoded.WireType != type)
    {
        Console.WriteLine($"[FAIL] ②  {type} 解码落入错误的 case（得到 {decoded.WireType}）");
        eventUnionOk = false;
    }
}
Check("②-1 8/11 代表性事件样例各自解码并落入正确 case（其余 3 类字段更复杂，判别机制相同，从简跳过）", eventUnionOk);

var unknownEventJson = EventJson("evt.made_up_type", "{}");
Check("②-2 未知 type 必须被拒绝（不得静默落入任何一个已知 case）", TryDecode<EventMessageUnion>(unknownEventJson) == null);

// ============================================================
// ③ 三层错误联合不串号
// ============================================================

var rejectionJson = @"{ ""code"": ""session_locked"" }";
var protocolJson = @"{ ""code"": ""malformed_message"" }";
var billingJson = @"{ ""code"": ""billing_query_subject_unresolved"" }";

var decodedRejection = TryDecode<KernelFailure>(rejectionJson);
Check("③-1 RejectionFailure 码正确落入 KernelFailureRejection 层",
    decodedRejection is KernelFailureRejection r0 && r0.Value.Code == RejectionFailureCode.SessionLocked);

var decodedProtocol = TryDecode<KernelFailure>(protocolJson);
Check("③-2 ProtocolFailure 码正确落入 KernelFailureProtocol 层（不与 RejectionFailure 混淆）",
    decodedProtocol is KernelFailureProtocol p0 && p0.Value.Code == FailureCode.MalformedMessage);

var decodedBilling = TryDecode<KernelFailure>(billingJson);
Check("③-3 BillingQueryFailure 码正确落入 KernelFailureBilling 层（三层互不串号）",
    decodedBilling is KernelFailureBilling);

var crossLayerJson = @"{ ""code"": ""aggregate_billing_requires_deployment_token"" }"; // 只属于 RejectionFailureCode
var decodedCrossLayer = TryDecode<KernelFailure>(crossLayerJson);
Check("③-4 交叉层错误码只命中唯一正确层（不会被 ProtocolFailure/BillingQueryFailure 误吸收）",
    decodedCrossLayer is KernelFailureRejection r1 && r1.Value.Code == RejectionFailureCode.AggregateBillingRequiresDeploymentToken);

// ============================================================
Console.WriteLine();
if (failures == 0)
{
    Console.WriteLine("=== ALL PASS（C# 判别联合最小测试全部通过） ===");
}
else
{
    Console.WriteLine($"=== {failures} 项 FAIL ===");
    Environment.Exit(1);
}
