// SG-5 Stage C：openclaw Gateway 原生 wire 协议的最小编解码帮助函数——镜像
// ../swift/OpenclawWire.swift（F2/F7 两处正确性属性的权威源）。
//
// 这不是 D2 契约的一部分——是 OpenclawGatewayKernelClient 内部用来跟"已经在运行的 openclaw
// 内核"直接对话的传输层。帧形状与握手/RPC 细节与 Swift 侧完全一致：
//   请求 {type:"req", id, method, params}
//   响应 {type:"res", id, ok, payload, error}
//   事件 {type:"event", event, payload, seq?, stateVersion?}
//
// Swift 侧用 `[String: Any]`（JSONSerialization 产物）表达任意 wire JSON；C# 没有天然等价物，这里用
// `Dictionary<string, object?>`（下方 JSONObject 别名）+ `List<object?>` 表达同样的"任意 JSON 值"结构，
// 解码走 `JsonDocument`/`JsonElement` 递归转换（ConvertElement），编码直接交给 System.Text.Json——
// 已用 scratchpad 验证过 `object` 声明类型的属性持有 `Dictionary<string,object?>`/`List<object?>` 时，
// System.Text.Json 会按运行时类型递归正确序列化嵌套结构（不需要自定义 JsonConverter）。
//
// F7（CRITICAL，镜像 Swift 侧同名章节）：递归脱敏的敏感字段名判定，整词/复合词匹配，不是裸子串匹配。

#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace KernelClient
{
    using JSONObject = Dictionary<string, object?>;

    public sealed class OpenclawWireException : Exception
    {
        public OpenclawWireException(string message) : base($"invalid wire frame: {message}") { }
    }

    /// <summary>
    /// 便于书写 `obj.Get("key")`（不存在时返回 null，等价于 Swift 字典下标天然返回 Optional）——
    /// C# `Dictionary` 下标在 key 缺失时会抛异常，需要这个扩展方法补上同样的"安全取值"语义。
    /// </summary>
    public static class JsonObjectExtensions
    {
        public static object? Get(this JSONObject? obj, string key)
            => obj != null && obj.TryGetValue(key, out var v) ? v : null;
    }

    public static class OpenclawWire
    {
        // MARK: - JSON 取值小工具（镜像 EventMapping.swift 的 jsonInt/jsonString/jsonBool/jsonObject/jsonArray）

        public static long? JsonInt(object? any) => any switch
        {
            long l => l,
            int i => i,
            short s => s,
            double d => (long)d,
            _ => null,
        };

        public static string? JsonString(object? any) => any as string;

        public static bool? JsonBool(object? any) => any as bool?;

        public static JSONObject? JsonObj(object? any) => any as JSONObject;

        public static List<object?>? JsonArr(object? any) => any as List<object?>;

        /// <summary>
        /// 把 openclaw wire 上的毫秒 epoch 数字字段转成 <see cref="DateTimeOffset"/>——镜像 Swift 侧
        /// `msEpochToDate`（F3：D2 KernelEventBase.ts 语义是"事件发生时刻"，必须取 openclaw 原始
        /// payload/message 自带的时间戳，不能用 `DateTimeOffset.UtcNow`）。缺失时退化到当前时刻，只发生在
        /// openclaw 自己也没有提供任何时间戳的合成事件上（如 transport_closed）。
        /// </summary>
        public static DateTimeOffset MsEpochToDate(long? ms) =>
            ms.HasValue ? DateTimeOffset.FromUnixTimeMilliseconds(ms.Value) : DateTimeOffset.UtcNow;

        // MARK: - wire 帧编解码

        public static byte[] EncodeFrame(JSONObject obj) => JsonSerializer.SerializeToUtf8Bytes(obj);

        public static JSONObject DecodeFrame(byte[] data)
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
                throw new OpenclawWireException("top-level JSON is not an object");
            return (JSONObject)ConvertElement(doc.RootElement)!;
        }

        /// <summary>
        /// 把 `JsonElement`（`JsonDocument.Parse` 产物）递归转换成 `Dictionary&lt;string,object?&gt;` /
        /// `List&lt;object?&gt;` / 标量——对应 Swift 侧 `JSONSerialization.jsonObject(with:)` 直接产出
        /// `[String: Any]` 的效果（C# 没有天然等价物，需要这一步显式转换）。整数值优先解成 `long`（不是
        /// `double`），保持跟 openclaw 原生 ms epoch/exitCode 等整数字段在比较时的直觉一致。
        /// </summary>
        public static object? ConvertElement(JsonElement el) => el.ValueKind switch
        {
            JsonValueKind.Object => ConvertObject(el),
            JsonValueKind.Array => ConvertArray(el),
            JsonValueKind.String => el.GetString(),
            JsonValueKind.Number => el.TryGetInt64(out var l) ? (object)l : el.GetDouble(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => null,
            _ => null,
        };

        private static JSONObject ConvertObject(JsonElement el)
        {
            var result = new JSONObject();
            foreach (var prop in el.EnumerateObject()) result[prop.Name] = ConvertElement(prop.Value);
            return result;
        }

        private static List<object?> ConvertArray(JsonElement el)
        {
            var result = new List<object?>();
            foreach (var item in el.EnumerateArray()) result.Add(ConvertElement(item));
            return result;
        }

        // MARK: - F2：附件编码（镜像 Swift 侧 `encodeAttachmentForWire`）

        /// <summary>
        /// 把一个非文本 <see cref="D2.Part"/>（`Kind == FileRef`，携带本地 `Path`）编码成 openclaw
        /// `normalizeRpcAttachmentsToChatAttachments` 期望的 wire 形状 `{content, mimeType?, fileName?}`。
        /// `content` 是文件内容的 base64 编码。读不到文件——诚实跳过这一个 attachment，不编造 content，
        /// 也不让整个 send() 失败。
        /// </summary>
        public static JSONObject? EncodeAttachmentForWire(D2.Part part)
        {
            if (part.Path == null) return null;
            byte[] data;
            try
            {
                data = File.ReadAllBytes(part.Path);
            }
            catch
            {
                return null;
            }

            var obj = new JSONObject { ["content"] = Convert.ToBase64String(data) };
            if (part.MimeType != null) obj["mimeType"] = part.MimeType;
            obj["fileName"] = Path.GetFileName(part.Path);
            return obj;
        }

        // MARK: - F7（CRITICAL）：递归脱敏——镜像 Swift 侧同名章节逐字段判定逻辑

        private static readonly HashSet<string> UnambiguousSensitiveSingulars = new(StringComparer.Ordinal)
        {
            "auth", "authorization", "secret", "password", "credential",
        };

        private static readonly HashSet<string> TokenCountingQualifiers = new(StringComparer.Ordinal)
        {
            "context", "input", "output", "total", "max", "budget", "count", "limit", "usage", "remaining",
        };

        /// <summary>
        /// 把一个 camelCase/snake_case/kebab-case 的 key 拆成小写单词列表——`"contextTokens"` ->
        /// `["context","tokens"]`，`"authToken"` -> `["auth","token"]`，`"api_key"` -> `["api","key"]`。
        /// </summary>
        private static List<string> LowercasedWords(string key)
        {
            var words = new List<string>();
            var current = new StringBuilder();
            foreach (var ch in key)
            {
                if (ch == '_' || ch == '-')
                {
                    if (current.Length > 0) { words.Add(current.ToString()); current.Clear(); }
                    continue;
                }
                if (char.IsUpper(ch) && current.Length > 0)
                {
                    words.Add(current.ToString());
                    current.Clear();
                    current.Append(char.ToLowerInvariant(ch));
                }
                else
                {
                    current.Append(char.ToLowerInvariant(ch));
                }
            }
            if (current.Length > 0) words.Add(current.ToString());
            return words;
        }

        /// <summary>简单的英语复数去除——只处理"末尾加 s"这一种最常见形态。</summary>
        private static string Singularized(string word) =>
            word.Length > 1 && word.EndsWith("s", StringComparison.Ordinal) ? word[..^1] : word;

        private static bool IsSensitiveKey(string key)
        {
            var words = LowercasedWords(key);

            // ① 无歧义凭证词（含复数）——整词命中（去掉可能的末尾 "s" 再比较）。
            if (words.Any(w => UnambiguousSensitiveSingulars.Contains(Singularized(w)))) return true;

            // ② apiKey/apiKeys 复合词——"api" 后紧跟 "key"/"keys" 才算敏感。
            for (int i = 0; i < words.Count; i++)
            {
                if (words[i] == "api" && i + 1 < words.Count && Singularized(words[i + 1]) == "key") return true;
            }

            // ③ token/tokens——裸字段或与 auth/api 复合视为敏感；与计数类限定词相邻则明确排除。
            for (int i = 0; i < words.Count; i++)
            {
                if (Singularized(words[i]) != "token") continue;
                bool hasCountingNeighbor =
                    (i > 0 && TokenCountingQualifiers.Contains(words[i - 1])) ||
                    (i + 1 < words.Count && TokenCountingQualifiers.Contains(words[i + 1]));
                if (hasCountingNeighbor) continue; // 明确排除：token 计数字段，不脱敏
                return true; // 裸 token(s) 或与其它未知限定词复合——默认敏感（安全的一侧）
            }

            return false;
        }

        /// <summary>
        /// 递归构造一份脱敏副本，供日志/打印使用——原始 `value` 不被修改。
        /// </summary>
        public static object? RedactedCopy(object? value)
        {
            if (value is JSONObject dict)
            {
                var outDict = new JSONObject();
                foreach (var (key, nested) in dict)
                    outDict[key] = IsSensitiveKey(key) ? "***REDACTED***" : RedactedCopy(nested);
                return outDict;
            }
            if (value is List<object?> list)
                return list.Select(RedactedCopy).ToList();
            return value;
        }

        /// <summary>
        /// 把收发的每一帧打印出来——F7 rework：打印前统一走 <see cref="RedactedCopy"/>，递归脱敏
        /// auth/token/secret 等凭证字段，这是唯一的调用路径。
        /// </summary>
        public static void PrettyPrint(string label, JSONObject obj)
        {
            var safe = RedactedCopy(obj) as JSONObject ?? obj;
            string text;
            try
            {
                text = JsonSerializer.Serialize(safe, new JsonSerializerOptions { WriteIndented = true });
            }
            catch
            {
                text = "<unprintable>";
            }
            Console.WriteLine($"\n--- {label} ---\n{text}");
        }
    }
}
