// 子集深度匹配——语义对齐 ../ts-runner/runner.ts 的 `partialMatch` / ../swift-runner/PartialMatch.swift：
// expected 里出现的每个字段都必须在 actual 里以相等值出现；actual 多出的字段不算失败；数组要求长度相等
// （逐元素再做子集匹配）；expected 完全缺省（C# `null`，对应 TS `undefined`/Swift `Optional.none`）视为
// 『不断言这个字段』，直接通过；expected 显式是 JSON `null`（<see cref="JsonNullMarker.Instance"/>）走
// 严格『actual 也必须显式是 null』比较——`null`（缺失）≠ `JsonNullMarker.Instance`（显式 null），这正是
// Swift 侧 T-048 REWORK #4 第 1 类假阴性修的那处区分（`isExplicitNull`），本文件从第一行就按这个纪律写，
// 不是事后打补丁。
//
// 输入的两侧类型对称——与 Swift 不同，本文件对 actual/expected 两侧统一使用同一个『object? 值域』
// （Dictionary<string,object?>/List<object?>/string/long/double/bool/JsonNullMarker.Instance）：
//   - `expected` 来自 fixture JSON，经 `FixtureDsl.cs` 的 `FixtureJson.ToActual` 从 `JsonElement`
//     解出。
//   - `actual` 是 CSharpFixtureRunner 自己在跑 timeline 过程中，用真实 client 的可观察状态拼出来的
//     同一套值域（构造时遵循同一纪律：显式 JSON null 用 `JsonNullMarker.Instance`，字段不适用/未计算
//     就整个不放进 Dictionary，绝不用裸 `null` 表达『这里其实是 JSON null』——那样会和『键缺失』的
//     C# `null` 语义混淆，见 `JsonNullMarker` 的文档注释）。
//
// C# 与 Swift 的一处真实差异（刻意记录，不是遗漏）：Swift 侧 `PartialMatch.swift` 花了大篇幅处理
// Foundation 把 `Bool` 桥接成 `NSNumber` 之后的假阳性（`NSNumber(value:0) is Bool` 在 Swift 6.3.3
// 上实测为 `true`，见该文件文档注释 #2）——这是 Objective-C/Foundation 运行时特有的『NSNumber 按数值
// 是否恰好是 0/1 做启发式桥接』的历史包袱。C# 没有这个问题：`object` 装箱后的运行时类型精确保留，装箱的
// `bool` 恒为 `System.Boolean`，装箱的 `long`/`int`/`double` 恒为对应的数值类型，`is bool` 模式匹配
// 可靠区分两者，不会把数值 0/1 误判成布尔（也不会反过来）。因此 `ScalarsEqual` 不需要 Swift 那样的
// `objCType` workaround；这是语言运行时差异带来的合理简化，不是抄近路漏掉了 T-048 那一课。

using System;
using System.Collections.Generic;
using System.Linq;

namespace CSharpRunner
{
    /// <summary>
    /// 显式 JSON `null` 的哨兵值——与『字段完全缺失』（C# `null`，对应 TS `undefined`/Swift
    /// `Optional.none`）语义不同，必须可区分（PartialMatch 文件头注释）。
    ///
    /// 边界（务必遵守，否则会把这套纪律做反）：这个哨兵只活在 CSharpFixtureRunner 自己的『actual/expected
    /// 统一值域』里，供 `PartialMatch.Match` 消费。任何要喂给真实 `OpenclawGatewayKernelClient`（比如
    /// `ApplyMockResponse`/`ApplyMockEvent` 构造的 wire 帧 `JSONObject`）的字典，如果需要表达 JSON
    /// `null`，一律用裸 C# `null`——那是 `OpenclawWire`/`System.Text.Json` 认得的『JSON null』表达
    /// （`OpenclawWire.ConvertElement` 把 `JsonValueKind.Null` 转成 C# `null`，`JsonObjectExtensions.Get`
    /// / `OpenclawWire.JsonString` 等取值助手也按这个假设工作），绝不能把 `JsonNullMarker.Instance`
    /// 泄漏进那些字典——那样真实 client 的 `is string`/`as string` 转换只会静默拿到 null（不崩溃，但
    /// 语义错了），且 F7 脱敏/PrettyPrint 序列化也认不得这个哨兵类型。
    /// </summary>
    public sealed class JsonNullMarker
    {
        public static readonly JsonNullMarker Instance = new();
        private JsonNullMarker() { }
        public override string ToString() => "null";
    }

    public static class PartialMatch
    {
        public static bool IsExplicitNull(object? v) => v is JsonNullMarker;

        /// <summary>供诊断消息 + `RunFixtureFileAsync` 的 initialState 拒绝消息使用的简易 JSON 风格
        /// 字符串化——不追求转义完整性，只追求可读，镜像 Swift `describeAny`/TS
        /// `JSON.stringify` 在诊断消息里的角色。</summary>
        public static string Stringify(object? v)
        {
            switch (v)
            {
                case null:
                    return "nil";
                case JsonNullMarker:
                    return "null";
                case string s:
                    return $"\"{s}\"";
                case bool b:
                    return b ? "true" : "false";
                case Dictionary<string, object?> dict:
                    return "{" + string.Join(",", dict.Select(kv => $"\"{kv.Key}\":{Stringify(kv.Value)}")) + "}";
                case List<object?> list:
                    return "[" + string.Join(",", list.Select(Stringify)) + "]";
                default:
                    return v.ToString() ?? "nil";
            }
        }

        private static bool TryIntegerValue(object v, out long result)
        {
            switch (v)
            {
                case long l:
                    result = l;
                    return true;
                case int i:
                    result = i;
                    return true;
                case short s:
                    result = s;
                    return true;
                case double d when Math.Truncate(d) == d && Math.Abs(d) < 9.2e18:
                    result = (long)d;
                    return true;
                default:
                    result = 0;
                    return false;
            }
        }

        private static bool TryNumericValue(object v, out double result)
        {
            switch (v)
            {
                case long l:
                    result = l;
                    return true;
                case int i:
                    result = i;
                    return true;
                case double d:
                    result = d;
                    return true;
                default:
                    result = 0;
                    return false;
            }
        }

        private static bool ScalarsEqual(object actual, object expected)
        {
            if (actual is string sa && expected is string sb) return sa == sb;

            // Bool 必须两侧都是 bool 才能比较——C# 装箱运行时类型精确（不像 Swift 需要 objCType
            // workaround，见文件头注释），`is bool` 足够可靠。
            var actualIsBool = actual is bool;
            var expectedIsBool = expected is bool;
            if (actualIsBool || expectedIsBool)
                return actualIsBool && expectedIsBool && (bool)actual == (bool)expected;

            if (TryIntegerValue(actual, out var ia) && TryIntegerValue(expected, out var ib)) return ia == ib;
            if (TryNumericValue(actual, out var na) && TryNumericValue(expected, out var nb)) return na == nb;
            return false;
        }

        /// <summary>`expected`/`actual` 均已从各自来源解出为『统一 object? 值域』（见文件头注释）。</summary>
        public static List<string> Match(object? actual, object? expected, string path)
        {
            var mismatches = new List<string>();

            // C# `null` == TS `expected === undefined` / Swift `Optional.none`（调用方没有提供这个
            // 断言字段）——跳过，不产生任何 mismatch。**区别于**下面的显式 JSON null 分支。
            if (expected is null) return mismatches;

            if (IsExplicitNull(expected))
            {
                if (actual is null || !IsExplicitNull(actual))
                    mismatches.Add($"{path}: 期望 null，实际 {Stringify(actual)}");
                return mismatches;
            }

            if (expected is Dictionary<string, object?> expDict)
            {
                if (actual is not Dictionary<string, object?> actDict)
                {
                    mismatches.Add($"{path}: 期望对象 {Stringify(expected)}，实际 {Stringify(actual)}");
                    return mismatches;
                }
                foreach (var (key, value) in expDict)
                {
                    var actualValue = actDict.TryGetValue(key, out var v) ? v : null;
                    mismatches.AddRange(Match(actualValue, value, $"{path}.{key}"));
                }
                return mismatches;
            }

            if (expected is List<object?> expArr)
            {
                if (actual is not List<object?> actArr)
                {
                    mismatches.Add($"{path}: 期望数组，实际 {Stringify(actual)}");
                    return mismatches;
                }
                if (actArr.Count != expArr.Count)
                {
                    mismatches.Add($"{path}: 期望长度 {expArr.Count}，实际长度 {actArr.Count}");
                    return mismatches;
                }
                for (var i = 0; i < expArr.Count; i++)
                    mismatches.AddRange(Match(actArr[i], expArr[i], $"{path}[{i}]"));
                return mismatches;
            }

            // 标量：actual 缺失（C# null）或本身是显式 null，都不能满足『expected 是某个具体标量』的
            // 比较——TS `actual === expected` 对 undefined/null 与任何非 null/undefined 标量比较恒为
            // false。
            if (actual is null || IsExplicitNull(actual))
            {
                mismatches.Add($"{path}: 期望 {Stringify(expected)}，实际 {Stringify(actual)}");
                return mismatches;
            }
            if (!ScalarsEqual(actual, expected))
                mismatches.Add($"{path}: 期望 {Stringify(expected)}，实际 {Stringify(actual)}");
            return mismatches;
        }
    }
}
