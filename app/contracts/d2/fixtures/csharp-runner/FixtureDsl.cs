// SG-8.7 Stage B：fixture DSL 的 C# Codable 镜像——逐字对应 ../dsl.ts / ../swift-runner/FixtureDSL.swift。
//
// 与 Swift 镜像同一个刻意简化：dsl.ts 的 `TimelineOp` 是一个按 `op` 判别的联合（8 个互斥变体，各自只
// 声明自己需要的字段）；本文件用一个「扁平化、字段并集、按 op 决定哪些字段有意义」的单一 class 表达同一件
// 事——`Op` 本身仍是强类型枚举（`TimelineOpKind` + 专属 JsonConverter），读者按 `Op` 的取值就知道该看
// 哪些字段，不存在『解码后无法判别到底是哪个变体』的问题（同 FixtureDSL.swift 文件头注释对这一区别的
// 界定：这不是 quicktype 坍缩 oneOf 那种因为工具局限被迫接受的缺陷）。
//
// 开放字段（args/pattern/message/driverHint/expected/initialState）用 `System.Text.Json.JsonElement?`
// 承载原始 JSON——C# 没有 Swift `JSONAny`/TS `unknown` 的直接等价物，`JsonElement?` 是 System.Text.Json
// 内建的『延迟解析的任意 JSON 值』表达，`HasValue == false` 精确对应『这个字段在 JSON 里完全缺失』
// （Swift Optional.none / TS undefined），`HasValue == true && ValueKind == Null` 精确对应『这个字段
// 显式是 JSON `null`』——两种情形的区分对 PartialMatch 的语义至关重要（见 PartialMatch.cs 文件头）。
// `FixtureJson.ToActual` 把 `JsonElement` 递归转换成与 PartialMatch 的 `actual` 侧同一个『统一 object?
// 值域』（Dictionary<string,object?>/List<object?>/string/long/double/bool/JsonNullMarker），这样
// PartialMatch 才能像 Swift/TS 那样对 actual/expected 两侧用同一个 `Match` 函数比较（见 PartialMatch.cs）。

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CSharpRunner
{
    /// <summary>D4 §4.3 TimelineOp 的 8 个判别取值——对应 dsl.ts 的 `op` 字面量。</summary>
    public enum TimelineOpKind
    {
        ClientCall,
        ExpectOutbound,
        MockResponse,
        MockEvent,
        Disconnect,
        Reconnect,
        AdvanceClock,
        AssertState,
    }

    internal sealed class TimelineOpKindConverter : JsonConverter<TimelineOpKind>
    {
        public override TimelineOpKind Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            return value switch
            {
                "client_call" => TimelineOpKind.ClientCall,
                "expect_outbound" => TimelineOpKind.ExpectOutbound,
                "mock_response" => TimelineOpKind.MockResponse,
                "mock_event" => TimelineOpKind.MockEvent,
                "disconnect" => TimelineOpKind.Disconnect,
                "reconnect" => TimelineOpKind.Reconnect,
                "advance_clock" => TimelineOpKind.AdvanceClock,
                "assert_state" => TimelineOpKind.AssertState,
                _ => throw new JsonException($"未知 TimelineOp.op 取值：'{value}'"),
            };
        }

        public override void Write(Utf8JsonWriter writer, TimelineOpKind value, JsonSerializerOptions options)
            => throw new NotSupportedException("csharp-runner 只读 fixture，不需要序列化 TimelineOp");
    }

    /// <summary>单个 timeline 动作——字段并集，具体哪些字段有意义取决于 <see cref="Op"/>（见文件头注释）。</summary>
    public sealed class TimelineOp
    {
        public int T { get; set; }

        [JsonConverter(typeof(TimelineOpKindConverter))]
        public TimelineOpKind Op { get; set; }

        // client_call
        public string? Id { get; set; }
        public string? Call { get; set; }
        public JsonElement? Args { get; set; }

        // expect_outbound
        public string? Matches { get; set; }
        public JsonElement? Pattern { get; set; }

        // mock_response
        public string? ReplyTo { get; set; }
        public JsonElement? Message { get; set; }

        // mock_event（可选）——翻译层专属驱动控制量，不属于 D2 wire 事件本身（`Message` 是封闭 D2
        // 判别联合，容不下非 D2 字段）。逐字对应 ../dsl.ts 的 `MockEventDriverHint`（T-048 REWORK
        // #1/#2 收残）；TS mock-kernel-client 忽略同名字段，csharp-runner 在 `ApplyMockEvent` 的
        // `evt.approval_request` 分支读取 `DriverHint.approvalJoinOrder`。
        public JsonElement? DriverHint { get; set; }

        // advance_clock
        public int? Ms { get; set; }

        // assert_state（与顶层 ParityFixture.Expected 共用同一种『ClientObservableState 子集』表达，
        // 都用 JsonElement? 承载——理由同 SwiftFixtureRunner.swift 的对应说明：本 runner 对 actual/
        // expected 两侧统一在『统一 object? 值域』层面做子集深度匹配，语义对齐 ts-runner 的
        // `partialMatch`，强类型化 ClientObservableState 反而会在『expected 只给部分字段』这个核心
        // 语义上增加不必要的摩擦）。
        public JsonElement? Expected { get; set; }
    }

    /// <summary>顶层 fixture——对应 dsl.ts 的 `ParityFixture`。</summary>
    public sealed class ParityFixture
    {
        public string Name { get; set; } = "";
        public string Description { get; set; } = "";
        public JsonElement? InitialState { get; set; }
        public List<TimelineOp> Timeline { get; set; } = new();
        public JsonElement? Expected { get; set; }
    }

    public static class FixtureLoader
    {
        private static readonly JsonSerializerOptions Options = new()
        {
            PropertyNameCaseInsensitive = true,
        };

        public static ParityFixture Parse(string json) =>
            JsonSerializer.Deserialize<ParityFixture>(json, Options)
            ?? throw new JsonException("fixture JSON 解析结果为 null");

        public static ParityFixture Load(string path) => Parse(File.ReadAllText(path));
    }

    /// <summary>
    /// `JsonElement` -&gt; PartialMatch『统一 object? 值域』的递归转换——同一份逻辑服务两个方向：
    /// (1) 把 fixture 作者写的 pattern/message/driverHint/expected/initialState 转成可与 runner 自己
    ///     拼出来的『actual』状态用同一个 `PartialMatch.Match` 比较（对应 Swift `JSONAny.value`）；
    /// (2) 把真实 D2 事件 payload（先用 `JsonSerializer.Serialize` 编码成 JSON 再回解）转成同一值域，
    ///     供 `observedEvents` 断言使用（对应 SwiftFixtureRunner.swift 的 `encodeToJSONObject`）。
    /// `JsonValueKind.Null` 显式转换成 <see cref="JsonNullMarker.Instance"/>（不是 C# `null`）——`null`
    /// 在这个值域里专门表示『字段整个缺失』（`JsonElement?` 的 `HasValue == false`，见文件头注释），
    /// 两者必须可区分，否则 PartialMatch 无法复现 T-048 修过的『显式 null vs 字段缺失』语义。
    /// </summary>
    public static class FixtureJson
    {
        public static object? ToActual(JsonElement? el) => el is { } value ? ToActual(value) : null;

        public static object? ToActual(JsonElement value)
        {
            switch (value.ValueKind)
            {
                case JsonValueKind.Null:
                case JsonValueKind.Undefined:
                    return JsonNullMarker.Instance;
                case JsonValueKind.True:
                    return true;
                case JsonValueKind.False:
                    return false;
                case JsonValueKind.String:
                    return value.GetString();
                case JsonValueKind.Number:
                    return value.TryGetInt64(out var l) ? (object)l : value.GetDouble();
                case JsonValueKind.Array:
                {
                    var list = new List<object?>();
                    foreach (var item in value.EnumerateArray()) list.Add(ToActual(item));
                    return list;
                }
                case JsonValueKind.Object:
                {
                    var dict = new Dictionary<string, object?>();
                    foreach (var prop in value.EnumerateObject()) dict[prop.Name] = ToActual(prop.Value);
                    return dict;
                }
                default:
                    return null;
            }
        }

        /// <summary>便利封装：期望一个 JSON 对象，转换失败/缺失时回退空字典（镜像 Swift
        /// `(op.pattern?.value as? [String: Any]) ?? [:]` 的既定简化——空字典意味着『不施加任何断言』，
        /// 不是伪造数据）。</summary>
        public static Dictionary<string, object?> ToActualObject(JsonElement? el) =>
            ToActual(el) as Dictionary<string, object?> ?? new Dictionary<string, object?>();
    }
}
