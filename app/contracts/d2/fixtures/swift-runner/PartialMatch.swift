// 子集深度匹配——语义对齐 ../ts-runner/runner.ts 的 `partialMatch`：expected 里出现的每个字段都必须
// 在 actual 里以相等值出现；actual 多出的字段不算失败；数组要求长度相等（逐元素再做子集匹配）；
// expected 完全缺省（TS 的 `undefined`，Swift 侧对应 Optional.none）视为『不断言这个字段』，直接通过。
//
// T-048 REWORK #4：修正三类此前与 TS 不等价、会把真实 mismatch 放过的假阴性（codex 对抗审复现）：
//   1. 显式 JSON null 与『字段完全缺失』被旧版混为一谈——TS 对 `expected === null` 走严格
//      `actual === expected` 标量比较（`undefined === null` 是 false！），旧版一律放行。现在区分
//      『Optional.none（未提供这个断言字段，对应 TS undefined）』与『isExplicitNull（JSON 字面量
//      null，对应 JSONNull/NSNull 实例）』两种不同情形，只有前者才无条件跳过。
//   2. Foundation 把 `Bool` 桥接成 `NSNumber`后，旧版 `numericValue` 会把它当数字比较，导致
//      `true == 1`、`false == 0` 这类假阳性（TS `===` 对 boolean vs number 严格不等）。**实测发现
//      这个问题比最初判断的更深**：`v is Bool`/`v as? Bool` 本身就不可靠——在这台机器的 Swift
//      6.3.3 上实测 `NSNumber(value: 0) is Bool`/`NSNumber(value: 1) is Bool` 均为 `true`（哪怕
//      这个 NSNumber 明明是从 Codable `Int` 编码来的普通整数、`objCType` 是 `"q"` 不是
//      `"c"`），但 `NSNumber(value: 42) is Bool` 是 `false`——即 Swift 的 NSNumber<->Bool 桥接是
//      **按数值是否恰好等于 0/1 做的启发式判断，不是按类型**，`is Bool` 对『刚好是 0/1 的真整数』
//      同样会给出假阳性（复现：本文件改动后首次跑 basic fixture 的 `evt.message.delta.payload.
//      index:0` 被误报 mismatch）。修法：改查 `objCType`——CFBoolean 桥接来的 NSNumber（真正的
//      JSON `true`/`false`）恒为 `"c"`；经 Codable `Int`/`Int64` 编码的整数（即使数值是 0/1）
//      走 JSON 数字字面量，`objCType` 是 `"q"`，可靠区分（见 `isBoolValue`）。
//   3. 旧版把所有数字统一转 `Double` 比较，大整数经 Double 会丢失精度。现在优先尝试精确的 `Int64`
//      比较（两侧都能无损表示成整数时），只有出现非整数浮点值才落到 Double 比较。
//
// 输入的两侧类型不对称，如实反映两侧数据的来源不同：
//   - `expected` 来自 fixture JSON，经 `JSONAny.value` 解出，是 JSONDecoder 风格的
//     `String`/`Int64`/`Double`/`Bool`/`JSONNull`/`[String: Any]`/`[Any]`。
//   - `actual` 是 SwiftFixtureRunner 自己在跑 timeline 过程中拿真实 client 的可观察状态拼出来的
//     `[String: Any]`/`[[String: Any]]`/`String`/`Int`/`Bool`/`NSNull`——部分经由
//     `JSONSerialization.jsonObject` 往返（`encodeToJSONObject`），是 Foundation 风格的
//     `NSNumber`/`NSNull`，同样是普通 Swift 值，不经过 JSONAny。
// `scalarsEqual`/`integerValue` 负责抹平两侧数值类型的差异（Int vs Int64 vs Double vs NSNumber），
// 同时不引入新的假阳性。

import Foundation

public typealias Mismatch = String

/// 严格意义上的『值本身就是 JSON null 字面量』——不包括『字段完全缺失』（那是 Swift Optional.none，
/// 对应 TS 的 `undefined`，语义不同，见文件头注释 #1）。
func isExplicitNull(_ v: Any) -> Bool {
    if v is NSNull { return true }
    if v is JSONNull { return true }
    return false
}

/// 可靠判断某个值『语义上是不是 JSON 布尔』——**不能只查 `is Bool`/`as? Bool`**（文件头注释 #2
/// 实测记录的更深一层假阳性：Swift 的 NSNumber<->Bool 桥接按数值是否恰好是 0/1 做启发式判断，
/// 对『刚好是 0/1 的真整数』同样会误判为 Bool）。原生 Swift `Bool`（JSONAny/JSONDecoder 解出的
/// expected 一侧）与 CFBoolean 桥接来的 NSNumber（JSONSerialization 解出的 actual 一侧，真正的
/// JSON `true`/`false`）在转成 NSNumber 后 `objCType` 恒为 `"c"`；经 Codable `Int`/`Int64`
/// 编码的整数（即使数值是 0/1）`objCType` 是 `"q"`，可靠区分，不依赖数值本身。
func isBoolValue(_ v: Any) -> Bool {
    if let n = v as? NSNumber {
        return String(cString: n.objCType) == "c"
    }
    return v is Bool
}

/// 精确整数值——只有两侧都能无损表示成 Int64 时才走这条路径，避免大整数经 Double 比较丢失精度
/// （文件头注释 #3）。刻意排除 Bool（`scalarsEqual` 用 `isBoolValue` 在调用本函数之前就已经短路
/// 处理，这里只应处理真正的数字，用同一套 `isBoolValue` 判断排除，不能再用不可靠的 `is Bool`）。
func integerValue(_ v: Any) -> Int64? {
    if isBoolValue(v) { return nil }
    if let i = v as? Int { return Int64(i) }
    if let i64 = v as? Int64 { return i64 }
    if let d = v as? Double, d.truncatingRemainder(dividingBy: 1) == 0, d.magnitude < 0x1p63 {
        return Int64(d)
    }
    if let n = v as? NSNumber {
        // objCType 的 'f'/'d' 是浮点表示——真正的浮点数交给下面的 numericValue/Double 比较处理，
        // 这里只接受整型表示，保留原始精度（不强制先转 Double 再转回来）。
        let objCType = String(cString: n.objCType)
        if objCType == "f" || objCType == "d" { return nil }
        return n.int64Value
    }
    return nil
}

func numericValue(_ v: Any) -> Double? {
    if isBoolValue(v) { return nil }
    if let i = v as? Int { return Double(i) }
    if let i64 = v as? Int64 { return Double(i64) }
    if let d = v as? Double { return d }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

func scalarsEqual(_ a: Any, _ b: Any) -> Bool {
    if let sa = a as? String, let sb = b as? String { return sa == sb }

    // Bool 必须两侧都是 Bool 才能比较——防止 Foundation 的 Bool<->NSNumber 桥接把
    // `true`/`1`、`false`/`0` 误判成相等（文件头注释 #2）。用 `isBoolValue`（基于 objCType），
    // 不用不可靠的 `is Bool`/`as? Bool`。
    let aIsBool = isBoolValue(a)
    let bIsBool = isBoolValue(b)
    if aIsBool || bIsBool {
        guard aIsBool, bIsBool, let ba = a as? Bool, let bb = b as? Bool else { return false }
        return ba == bb
    }

    if let ia = integerValue(a), let ib = integerValue(b) { return ia == ib }
    if let na = numericValue(a), let nb = numericValue(b) { return na == nb }
    return false
}

func describeAny(_ v: Any?) -> String {
    guard let v = v, !isExplicitNull(v) else { return "nil" }
    return "\(v)"
}

/// `expected`/`actual` 均已从各自来源解出为普通 Swift 值（`expected` 一侧调用方负责先做
/// `jsonAny?.value`，本函数不认得 `JSONAny` 本身，只认得它解出来的原始值）。
public func partialMatch(actual: Any?, expected: Any?, path: String) -> [Mismatch] {
    // Optional.none == TS 的 `expected === undefined`（调用方没有提供这个断言字段）——跳过，不
    // 产生任何 mismatch。**区别于**下面的显式 JSON null 分支：JSON 字面量 `null` 解出来是一个具体
    // 的 `JSONNull`/`NSNull` 实例（非 Optional.none），走 isExplicitNull 分支，语义不同。
    guard let expected = expected else { return [] }

    if isExplicitNull(expected) {
        // TS `expected === null` 走严格 `actual === expected` 标量比较：`actual` 必须也是显式
        // null，"字段完全缺失"（`undefined`）不算数——`undefined === null` 在 JS 里是 false，
        // 旧版这里把两者混同是一处真实假阴性（文件头注释 #1）。
        guard let actual = actual, isExplicitNull(actual) else {
            return ["\(path): 期望 null，实际 \(describeAny(actual))"]
        }
        return []
    }

    if let expDict = expected as? [String: Any] {
        guard let actDict = actual as? [String: Any] else {
            return ["\(path): 期望对象 \(describeAny(expected))，实际 \(describeAny(actual))"]
        }
        var out: [Mismatch] = []
        for (key, value) in expDict {
            out += partialMatch(actual: actDict[key], expected: value, path: "\(path).\(key)")
        }
        return out
    }

    if let expArr = expected as? [Any] {
        guard let actArr = actual as? [Any] else {
            return ["\(path): 期望数组，实际 \(describeAny(actual))"]
        }
        guard actArr.count == expArr.count else {
            return ["\(path): 期望长度 \(expArr.count)，实际长度 \(actArr.count)"]
        }
        var out: [Mismatch] = []
        for (index, item) in expArr.enumerated() {
            out += partialMatch(actual: actArr[index], expected: item, path: "\(path)[\(index)]")
        }
        return out
    }

    // 标量：actual 缺失（Optional.none）或本身是显式 null，都不能满足『expected 是某个具体标量』
    // 的比较——TS `actual === expected` 对 undefined/null 与任何非 null/undefined 标量比较恒为 false。
    guard let actual = actual, !isExplicitNull(actual) else {
        return ["\(path): 期望 \(describeAny(expected))，实际 \(describeAny(actual))"]
    }
    if !scalarsEqual(actual, expected) {
        return ["\(path): 期望 \(describeAny(expected))，实际 \(describeAny(actual))"]
    }
    return []
}
