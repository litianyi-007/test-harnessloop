// rounds/0017 Change 1 —— 把 D2Generated.JSONAny.value（`Any`，quicktype 解码规则见
// app/generated/swift/D2.swift 该类型定义：叶子值只可能是 Bool/Int64/Double/String/JSONNull，
// 容器只可能是 [Any]/[String: Any]，与 JSON 语法完全对应）转成 UI 可以直接渲染的字符串。
//
// 不能复用 kernel-client 的 jsonString/jsonObject 等小工具（EventMapping.swift 头部）——那些是
// `KernelClient` target 的 internal 符号，`AgentShellCore` 是独立 SwiftPM target，跨 target 看
// 不到 internal 符号；任务硬约束又不允许改 app/kernel-client/swift/ 把它们放宽成 public。这里
// 独立写一份最小实现，只服务"渲染预览"这一件事，不追求通用 JSON 序列化保真度（转义规则、数字
// 精度往返等）——那是 kernel-client 层 wire 往返的职责，与此处"人能看懂个大概"的目标不同。
import Foundation
import D2Generated

enum JSONPreview {
    /// 折叠态用的单行摘要：先取完整描述，压平换行/制表符成空格（避免摘要把一行 UI 撑成好几行），
    /// 再截断到 `maxLength`。
    static func summarize(_ value: Any, maxLength: Int = 120) -> String {
        let collapsed = describe(value)
            .split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        return "\(collapsed.prefix(maxLength))…"
    }

    /// 展开态用的完整文本——不截断、不压平换行（多行输出，例如 exec 工具的 stdout，展开后应该
    /// 保留原始换行,方便阅读)。字符串类型的叶子值直接原样返回(exec 工具的 output 本身就是一整段
    /// 已经是人类可读文本的 stdout，不应该再包一层引号")；其余类型按 JSON 字面量形状描述。
    static func describe(_ value: Any) -> String {
        switch value {
        case is JSONNull:
            return "null"
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int64:
            return String(int)
        case let int as Int:
            return String(int)
        case let double as Double:
            return describeDouble(double)
        case let array as [Any]:
            return "[" + array.map(describe).joined(separator: ", ") + "]"
        case let dict as [String: Any]:
            let entries = dict.keys.sorted().map { key in "\(key): \(describe(dict[key] as Any))" }
            return "{" + entries.joined(separator: ", ") + "}"
        default:
            // JSONAny.value 的解码规则不应该产出这个分支（见文件头注释），保留是防御性的——真出现
            // 未识别类型时如实用 String(describing:) 兜底，而不是崩溃或吞掉这条数据。
            return String(describing: value)
        }
    }

    private static func describeDouble(_ value: Double) -> String {
        guard value.isFinite, value == value.rounded(), abs(value) < 1e15 else {
            return String(value)
        }
        return String(Int64(value))
    }
}
