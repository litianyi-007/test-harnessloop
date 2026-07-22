// 手写的判别联合包装类型——非 quicktype 产物。
//
// 背景与范围声明同 Swift 侧 ../../generated/swift/DiscriminatedUnions.swift（源
// scripts/handwritten/discriminated-unions.swift）——quicktype-core 是 Swift/C# 两个后端共用的
// 同一个前端，JSON Schema oneOf 判别联合坍缩、allOf 静默丢字段两个缺陷在 C# 侧同样复现（已在
// CODEGEN-FINDINGS.md 记录）。本文件是 C# 侧对应的手写后处理，覆盖同样的最小判别测试三项：
//   ① result/failure 互斥（以 createSession 为代表）—— D2Response<TSuccess,TFailure> 泛型 + 工厂转换器。
//   ② 11 事件按 type 判别的联合 —— EventMessageUnion 抽象类 + 11 个具体 case 类。
//   ③ 三层错误联合 —— KernelFailure 抽象类 + 3 个具体 case 类。
//
// C# 没有 Swift 的『enum 关联值』，判别联合只能用『抽象基类 + 具体子类』搭配自定义
// System.Text.Json JsonConverter 手写实现——这本身也是一项发现：即便判别联合的『形状』问题解决了
// （不用 quicktype 生成的坍缩版本），C# 语言本身对判别联合的表达力也弱于 Swift/TS，需要更多样板
// 代码才能达到同等的『类型系统拒绝混用』效果（见 CODEGEN-FINDINGS.md 对三端判别联合表达力的对比）。
//
// 另记一处 quicktype C# 后端的 API 不一致：它为字符串枚举生成的自定义 JsonConverter（如
// D2.cs 里的 RejectionFailureCodeConverter）在遇到不认识的取值时抛裸 `System.Exception`，不是
// System.Text.Json 惯用的 `JsonException`——下方级联 try 的 catch 子句必须按 `Exception` 兜底，
// 若按更精确的 `JsonException` 写会形同虚设、异常直接向上传播（已实测复现）。

#nullable enable
using System;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace D2
{
    // ============================================================
    // ① result/failure 互斥判别联合（createSession 代表）
    // ============================================================

    [JsonConverter(typeof(CreateSessionFailureConverter))]
    public sealed class CreateSessionFailure
    {
        public RejectionFailure? Rejection { get; }
        public ProtocolFailure? ProtocolFailure { get; }
        public bool IsRejection => Rejection != null;

        private CreateSessionFailure(RejectionFailure? rejection, D2.ProtocolFailure? protocolFailure)
        {
            Rejection = rejection;
            ProtocolFailure = protocolFailure;
        }

        public static CreateSessionFailure OfRejection(RejectionFailure value) => new CreateSessionFailure(value, null);
        public static CreateSessionFailure OfProtocolFailure(D2.ProtocolFailure value) => new CreateSessionFailure(null, value);
    }

    internal sealed class CreateSessionFailureConverter : JsonConverter<CreateSessionFailure>
    {
        public override CreateSessionFailure Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var raw = doc.RootElement.GetRawText();
            try
            {
                var r = JsonSerializer.Deserialize<RejectionFailure>(raw, D2.Converter.Settings);
                if (r != null) return CreateSessionFailure.OfRejection(r);
            }
            catch (Exception) { } // 见文件顶部说明：quicktype 生成的枚举转换器抛裸 Exception，非 JsonException
            try
            {
                var p = JsonSerializer.Deserialize<D2.ProtocolFailure>(raw, D2.Converter.Settings);
                if (p != null) return CreateSessionFailure.OfProtocolFailure(p);
            }
            catch (Exception) { } // 见文件顶部说明：quicktype 生成的枚举转换器抛裸 Exception，非 JsonException
            throw new JsonException("CreateSessionFailure: code 既不属于 RejectionFailureCode 也不属于 ProtocolFailure 的 FailureCode");
        }

        public override void Write(Utf8JsonWriter writer, CreateSessionFailure value, JsonSerializerOptions options)
        {
            if (value.IsRejection) JsonSerializer.Serialize(writer, value.Rejection, D2.Converter.Settings);
            else JsonSerializer.Serialize(writer, value.ProtocolFailure, D2.Converter.Settings);
        }
    }

    /// <summary>
    /// 通用的 result/failure 互斥判别联合包装——对应 D2 v3 §2 ResponseEnvelope 的判别语义。
    /// 用 JsonConverterFactory 支持任意 TSuccess/TFailure 组合的闭合泛型。
    /// </summary>
    [JsonConverter(typeof(D2ResponseConverterFactory))]
    public sealed class D2Response<TSuccess, TFailure>
    {
        public TSuccess? Result { get; }
        public TFailure? Failure { get; }
        public bool IsResult => Result != null;

        private D2Response(TSuccess? result, TFailure? failure)
        {
            Result = result;
            Failure = failure;
        }

        public static D2Response<TSuccess, TFailure> OfResult(TSuccess value) => new D2Response<TSuccess, TFailure>(value, default);
        public static D2Response<TSuccess, TFailure> OfFailure(TFailure value) => new D2Response<TSuccess, TFailure>(default, value);
    }

    public sealed class D2ResponseConverterFactory : JsonConverterFactory
    {
        public override bool CanConvert(Type typeToConvert) =>
            typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(D2Response<,>);

        public override JsonConverter CreateConverter(Type typeToConvert, JsonSerializerOptions options)
        {
            var args = typeToConvert.GetGenericArguments();
            var converterType = typeof(D2ResponseConverter<,>).MakeGenericType(args);
            return (JsonConverter)Activator.CreateInstance(converterType)!;
        }
    }

    internal sealed class D2ResponseConverter<TSuccess, TFailure> : JsonConverter<D2Response<TSuccess, TFailure>>
    {
        public override D2Response<TSuccess, TFailure> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var root = doc.RootElement;
            bool hasResult = root.TryGetProperty("result", out var resultEl);
            bool hasFailure = root.TryGetProperty("failure", out var failureEl);
            if (hasResult == hasFailure)
            {
                throw new JsonException($"D2Response 必须恰好携带 result 或 failure 之一（互斥判别联合），实际 hasResult={hasResult} hasFailure={hasFailure}");
            }
            if (hasResult)
            {
                var value = JsonSerializer.Deserialize<TSuccess>(resultEl.GetRawText(), D2.Converter.Settings)!;
                return D2Response<TSuccess, TFailure>.OfResult(value);
            }
            else
            {
                var value = JsonSerializer.Deserialize<TFailure>(failureEl.GetRawText(), D2.Converter.Settings)!;
                return D2Response<TSuccess, TFailure>.OfFailure(value);
            }
        }

        public override void Write(Utf8JsonWriter writer, D2Response<TSuccess, TFailure> value, JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            if (value.IsResult)
            {
                writer.WritePropertyName("result");
                JsonSerializer.Serialize(writer, value.Result, options);
            }
            else
            {
                writer.WritePropertyName("failure");
                JsonSerializer.Serialize(writer, value.Failure, options);
            }
            writer.WriteEndObject();
        }
    }

    public static class CreateSessionResponseBody
    {
        // C# 没有 TS/Swift 的类型别名（type alias）语法能直接给一个封闭泛型实例化起别名，
        // 这个静态类仅用于把具体类型摆在一起、方便调用方按名字找到它：
        // D2Response<CreateSessionResultPayload, CreateSessionFailure>
    }

    // ============================================================
    // ② 11 事件按 type 判别的联合（D2 v3 §4.1 EventMessage）
    // ============================================================

    /// <summary>
    /// D2 v3 §4.1 EventMessage 的完整判别联合。C# 没有 Swift 的 enum 关联值，只能用『抽象基类 +
    /// 具体子类』表达——这本身就是判别联合在 C# 里表达力弱于 Swift/TS 的直接证据。
    /// </summary>
    [JsonConverter(typeof(EventMessageUnionConverter))]
    public abstract class EventMessageUnion
    {
        public abstract string WireType { get; }
    }

    public sealed class MessageDeltaEventMessageCase : EventMessageUnion { public MessageDeltaEventMessage Value { get; init; } = null!; public override string WireType => "evt.message.delta"; }
    public sealed class ThinkingEventMessageCase : EventMessageUnion { public ThinkingEventMessage Value { get; init; } = null!; public override string WireType => "evt.thinking"; }
    public sealed class ToolCallEventMessageCase : EventMessageUnion { public ToolCallEventMessage Value { get; init; } = null!; public override string WireType => "evt.tool_call"; }
    public sealed class ToolResultEventMessageCase : EventMessageUnion { public ToolResultEventMessage Value { get; init; } = null!; public override string WireType => "evt.tool_result"; }
    public sealed class ApprovalRequestEventMessageCase : EventMessageUnion { public ApprovalRequestEventMessage Value { get; init; } = null!; public override string WireType => "evt.approval_request"; }
    public sealed class ErrorEventMessageCase : EventMessageUnion { public ErrorEventMessage Value { get; init; } = null!; public override string WireType => "evt.error"; }
    public sealed class TurnCompleteEventMessageCase : EventMessageUnion { public TurnCompleteEventMessage Value { get; init; } = null!; public override string WireType => "evt.turn_complete"; }
    public sealed class SessionEndEventMessageCase : EventMessageUnion { public SessionEndEventMessage Value { get; init; } = null!; public override string WireType => "evt.session_end"; }
    public sealed class CapabilityChangedEventMessageCase : EventMessageUnion { public CapabilityChangedEventMessage Value { get; init; } = null!; public override string WireType => "evt.capability_changed"; }
    public sealed class OperationCompletedEventMessageCase : EventMessageUnion { public OperationCompletedEventMessage Value { get; init; } = null!; public override string WireType => "evt.operation_completed"; }
    public sealed class ApprovalBufferResolvedEventMessageCase : EventMessageUnion { public ApprovalBufferResolvedEventMessage Value { get; init; } = null!; public override string WireType => "evt.approval_buffer_resolved"; }

    internal sealed class EventMessageUnionConverter : JsonConverter<EventMessageUnion>
    {
        public override EventMessageUnion Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var raw = doc.RootElement.GetRawText();
            var type = doc.RootElement.GetProperty("type").GetString();
            switch (type)
            {
                case "evt.message.delta":
                    return new MessageDeltaEventMessageCase { Value = JsonSerializer.Deserialize<MessageDeltaEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.thinking":
                    return new ThinkingEventMessageCase { Value = JsonSerializer.Deserialize<ThinkingEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.tool_call":
                    return new ToolCallEventMessageCase { Value = JsonSerializer.Deserialize<ToolCallEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.tool_result":
                    return new ToolResultEventMessageCase { Value = JsonSerializer.Deserialize<ToolResultEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.approval_request":
                    return new ApprovalRequestEventMessageCase { Value = JsonSerializer.Deserialize<ApprovalRequestEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.error":
                    return new ErrorEventMessageCase { Value = JsonSerializer.Deserialize<ErrorEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.turn_complete":
                    return new TurnCompleteEventMessageCase { Value = JsonSerializer.Deserialize<TurnCompleteEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.session_end":
                    return new SessionEndEventMessageCase { Value = JsonSerializer.Deserialize<SessionEndEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.capability_changed":
                    return new CapabilityChangedEventMessageCase { Value = JsonSerializer.Deserialize<CapabilityChangedEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.operation_completed":
                    return new OperationCompletedEventMessageCase { Value = JsonSerializer.Deserialize<OperationCompletedEventMessage>(raw, D2.Converter.Settings)! };
                case "evt.approval_buffer_resolved":
                    return new ApprovalBufferResolvedEventMessageCase { Value = JsonSerializer.Deserialize<ApprovalBufferResolvedEventMessage>(raw, D2.Converter.Settings)! };
                default:
                    throw new JsonException($"EventMessageUnion: 未知事件 type '{type}'，不属于 D2 v3 §4.1 的 11 类判别联合之一");
            }
        }

        public override void Write(Utf8JsonWriter writer, EventMessageUnion value, JsonSerializerOptions options)
        {
            switch (value)
            {
                case MessageDeltaEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ThinkingEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ToolCallEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ToolResultEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ApprovalRequestEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ErrorEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case TurnCompleteEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case SessionEndEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case CapabilityChangedEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case OperationCompletedEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                case ApprovalBufferResolvedEventMessageCase c: JsonSerializer.Serialize(writer, c.Value, D2.Converter.Settings); break;
                default: throw new JsonException("EventMessageUnion: 未知 case 类型，无法序列化");
            }
        }
    }

    // ============================================================
    // ③ 三层错误联合（D1 v3.5 §9.1 / D2 v3 §6）
    // ============================================================

    [JsonConverter(typeof(KernelFailureConverter))]
    public abstract class KernelFailure { }

    public sealed class KernelFailureRejection : KernelFailure { public RejectionFailure Value { get; init; } = null!; }
    public sealed class KernelFailureProtocol : KernelFailure { public D2.ProtocolFailure Value { get; init; } = null!; }
    public sealed class KernelFailureBilling : KernelFailure { public BillingQueryFailure Value { get; init; } = null!; }

    internal sealed class KernelFailureConverter : JsonConverter<KernelFailure>
    {
        public override KernelFailure Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var raw = doc.RootElement.GetRawText();
            try
            {
                var r = JsonSerializer.Deserialize<RejectionFailure>(raw, D2.Converter.Settings);
                if (r != null) return new KernelFailureRejection { Value = r };
            }
            catch (Exception) { } // 见文件顶部说明：quicktype 生成的枚举转换器抛裸 Exception，非 JsonException
            try
            {
                var p = JsonSerializer.Deserialize<D2.ProtocolFailure>(raw, D2.Converter.Settings);
                if (p != null) return new KernelFailureProtocol { Value = p };
            }
            catch (Exception) { } // 见文件顶部说明：quicktype 生成的枚举转换器抛裸 Exception，非 JsonException
            try
            {
                var b = JsonSerializer.Deserialize<BillingQueryFailure>(raw, D2.Converter.Settings);
                if (b != null) return new KernelFailureBilling { Value = b };
            }
            catch (Exception) { } // 见文件顶部说明：quicktype 生成的枚举转换器抛裸 Exception，非 JsonException
            throw new JsonException("KernelFailure: code 不属于三层错误模型（KernelPortRejectionCode / ProtocolFailure 码 / billing_query_subject_unresolved）中的任何一层");
        }

        public override void Write(Utf8JsonWriter writer, KernelFailure value, JsonSerializerOptions options)
        {
            switch (value)
            {
                case KernelFailureRejection r: JsonSerializer.Serialize(writer, r.Value, D2.Converter.Settings); break;
                case KernelFailureProtocol p: JsonSerializer.Serialize(writer, p.Value, D2.Converter.Settings); break;
                case KernelFailureBilling b: JsonSerializer.Serialize(writer, b.Value, D2.Converter.Settings); break;
                default: throw new JsonException("KernelFailure: 未知 case 类型，无法序列化");
            }
        }
    }
}
