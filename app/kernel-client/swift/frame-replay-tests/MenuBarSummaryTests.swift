// rounds/0021 Scope-Lock 修订 v1 -> v2：最小菜单栏项——`MenuBarSummary`（AgentShellCore/
// MenuBarSummary.swift）两个纯函数的入库回归测试。SwiftUI 视图代码本身（`MenuBarExtra` 内容、
// 图标加载）结构性地不可达 frame-replay-tests（`AgentShell`/`frame-replay-tests` 都是
// executableTarget，见该文件头注释），这里只覆盖挪出来的纯判断部分。

import Foundation
@testable import AgentShellCore

// MARK: - connectionStatusText：四个 ConnectionStatus case 各自的展示文案

func testMenuBarConnectionStatusTextForNotConnected() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.notConnected) == \"未连接\""
    let text = MenuBarSummary.connectionStatusText(.notConnected)
    guard text == "未连接" else {
        return fail(name, "expected \"未连接\", got \"\(text)\"")
    }
    return pass(name, "connectionStatusText(.notConnected) == \"未连接\"")
}

func testMenuBarConnectionStatusTextForConnecting() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.connecting) == \"连接中…\""
    let text = MenuBarSummary.connectionStatusText(.connecting)
    guard text == "连接中…" else {
        return fail(name, "expected \"连接中…\", got \"\(text)\"")
    }
    return pass(name, "connectionStatusText(.connecting) == \"连接中…\"")
}

/// **专门钉住的边界情形**：`.connected(scopes:)` 携带的 scopes 列表不应该泄漏进菜单栏文案——菜单栏
/// 空间受限，只需要"已连接"这一个事实（完整 scopes 仍只在侧栏展示，见 `MenuBarSummary` 文档注释）。
/// 用一个非空、多元素的 scopes 数组构造输入，直接证明输出没有把它们拼进字符串。
func testMenuBarConnectionStatusTextForConnectedOmitsScopesList() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.connected(scopes:)) == \"已连接\"（不泄漏 scopes 列表）"
    let text = MenuBarSummary.connectionStatusText(.connected(scopes: ["exec-approvals", "chat", "history"]))
    guard text == "已连接" else {
        return fail(name, "expected \"已连接\" (scopes 不应出现在菜单栏文案里), got \"\(text)\"")
    }
    return pass(name, "connectionStatusText(.connected(scopes: [3 项])) == \"已连接\"，scopes 明细未泄漏进菜单栏文案")
}

func testMenuBarConnectionStatusTextForFailedIncludesMessage() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.failed(message)) == \"连接失败：\\(message)\""
    let text = MenuBarSummary.connectionStatusText(.failed("timeout"))
    guard text == "连接失败：timeout" else {
        return fail(name, "expected \"连接失败：timeout\", got \"\(text)\"")
    }
    return pass(name, "connectionStatusText(.failed(\"timeout\")) == \"连接失败：timeout\"")
}

// MARK: - sessionNameText：nil vs 具体标题

/// **专门钉住的边界情形**：没有已选中会话时必须给出一个非空占位文案，不能是空字符串——空字符串在
/// 菜单里会呈现成一行看不出内容的空白（见 `MenuBarSummary.sessionNameText` 文档注释）。
func testMenuBarSessionNameTextForNilShowsPlaceholderNotEmptyString() -> Bool {
    let name = "菜单栏摘要: sessionNameText(nil) 返回非空占位文案（不是空字符串）"
    let text = MenuBarSummary.sessionNameText(nil)
    guard text == "无活动会话" else {
        return fail(name, "expected \"无活动会话\", got \"\(text)\"")
    }
    guard !text.isEmpty else {
        return fail(name, "占位文案不能是空字符串")
    }
    return pass(name, "sessionNameText(nil) == \"无活动会话\"，非空")
}

func testMenuBarSessionNameTextForSelectedSessionReturnsItsTitleVerbatim() -> Bool {
    let name = "菜单栏摘要: sessionNameText(某会话标题) 原样返回该标题（不加任何前后缀）"
    let text = MenuBarSummary.sessionNameText("会话 3")
    guard text == "会话 3" else {
        return fail(name, "expected \"会话 3\" verbatim, got \"\(text)\"")
    }
    return pass(name, "sessionNameText(\"会话 3\") == \"会话 3\"，原样透传")
}

// MARK: - 截断：菜单是空间受限的摘要面，NSError 全文/用户自定会话名都不受长度控制，必须在
// `MenuBarSummary` 内部截断（见该文件 `truncatedForMenuLine` 的文档注释），不能指望视图层兜底——
// 视图层结构性地不可测。以下测试覆盖：真实长度量级的 NSError 文案、用户粘贴的长会话名、一个 naive
// UTF-8/UTF-16 截断会切碎的 CJK+emoji 组合、以及"截断上限"两侧的边界值（40/41 字符），最后专门钉住
// "短字符串必须完全不受影响"——截断器把不需要截断的输入也改了，是它自己的缺陷。

/// **真实量级**：任务书给出的示例错误串（`transport error: Error Domain=NSURLErrorDomain
/// Code=-1004 "Could not connect to the server." UserInfo={...}`）在真机上完整长度远超一行菜单能
/// 容纳的宽度。这里用同形状、234 字符的串验证：`connectionStatusText(.failed(...))` 输出的
/// "连接失败：" 前缀原样保留（不被截断吃掉半个字），`message` 部分被截到 40 个 `Character` 再加一个
/// 省略号——不是三个句点。
func testMenuBarConnectionStatusTextForFailedTruncatesRealisticLongNSErrorMessage() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.failed(超长 NSError 文案)) 截断到上限并加省略号,不把整段错误塞进菜单"
    let message = "transport error: Error Domain=NSURLErrorDomain Code=-1004 \"Could not connect to the server.\" UserInfo={NSErrorFailingURLStringKey=https://kernel.internal.example.com/v1/gateway, NSLocalizedDescription=Could not connect to the server.}"
    guard message.count > 40 else {
        return fail(name, "测试前提失败：示例消息只有 \(message.count) 字符，没有超过截断上限，测不出截断行为")
    }
    let text = MenuBarSummary.connectionStatusText(.failed(message))
    let cap = 40
    let expected = "连接失败：" + String(message.prefix(cap)) + "…"
    guard text == expected else {
        return fail(name, "expected \"\(expected)\", got \"\(text)\"")
    }
    guard text.hasPrefix("连接失败：") else {
        return fail(name, "固定前缀「连接失败：」不应该被截断吃掉")
    }
    guard text.hasSuffix("…"), !text.hasSuffix("...") else {
        return fail(name, "应该用单个省略号字符「…」收尾，不是三个句点")
    }
    return pass(name, "\(message.count) 字符的 NSError 文案截到含前缀共 \(text.count) 字符: \"\(text)\"")
}

/// **用户粘贴的长会话名**：会话名没有系统给的长度上限，用户可以把任意长文本粘贴进标题（比如误粘贴
/// 了一整段话当会话名）。验证 `sessionNameText` 同样把它截到 40 个 `Character` 再加省略号。
func testMenuBarSessionNameTextTruncatesLongPastedSessionName() -> Bool {
    let name = "菜单栏摘要: sessionNameText(超长会话名) 截断到上限并加省略号,不把整段粘贴内容塞进菜单"
    let longName = String(repeating: "这是一个用户随手粘贴进来的超长会话标题片段", count: 5)
    guard longName.count > 40 else {
        return fail(name, "测试前提失败：示例会话名只有 \(longName.count) 字符，没有超过截断上限，测不出截断行为")
    }
    let text = MenuBarSummary.sessionNameText(longName)
    let cap = 40
    let expected = String(longName.prefix(cap)) + "…"
    guard text == expected else {
        return fail(name, "expected \"\(expected)\", got \"\(text)\"")
    }
    return pass(name, "\(longName.count) 字符的会话名截到含省略号共 \(text.count) 字符: \"\(text)\"")
}

/// **naive 截断会切碎的场景**：前 39 个"中"（每个都是 1 个 `Character`、1 个 UTF-16 code unit）+ 1 个
/// 需要 UTF-16 代理对的 emoji（`\u{1F600}`，占 2 个 UTF-16 code unit，但仍然只是 1 个
/// `Character`）+ 10 个"文"。这个 emoji 恰好落在第 40 个 `Character` 的位置——如果按 UTF-16 code
/// unit 计数截到 40 个 unit（39 个来自"中" + emoji 的高位代理项），会恰好切在这个 emoji 的代理对
/// 中间，留下一个不成对的高位代理。已用独立探针实测过这个具体输入：`String(utf16CodeUnits:count:)`
/// 会把这个断裂的代理对转成 U+FFFD replacement character，产出与正确结果不同的损坏字符串。
/// `MenuBarSummary` 是按 `Character` 截断，不会有这个问题——这条测试断言的是"正确结果"本身，
/// naive 版本会给出什么由本轮的破坏性反证环节实际注入验证（见交付报告）。
func testMenuBarSessionNameTextTruncatesCJKStringWithoutSplittingASurrogatePairEmojiAtTheBoundary() -> Bool {
    let name = "菜单栏摘要: sessionNameText 在 Character 边界截断,不切碎横跨 UTF-16 代理对的 emoji（naive UTF-16 截断会切在这里）"
    let emoji = "\u{1F600}"
    let longName = String(repeating: "中", count: 39) + emoji + String(repeating: "文", count: 10)
    guard longName.count == 50 else {
        return fail(name, "测试前提失败：构造的输入应该是 50 个 Character（39+1+10），实际是 \(longName.count)")
    }
    let text = MenuBarSummary.sessionNameText(longName)
    let expected = String(repeating: "中", count: 39) + emoji + "…"
    guard text == expected else {
        return fail(name, "expected \"\(expected)\", got \"\(text)\"")
    }
    guard text.unicodeScalars.contains(where: { $0.value == 0xFFFD }) == false else {
        return fail(name, "截断结果里出现了 U+FFFD replacement character，说明切碎了一个字符")
    }
    guard text.contains(emoji) else {
        return fail(name, "截断结果应该完整保留这个 emoji（要么整个保留、要么整个舍弃，不能切一半）")
    }
    return pass(name, "39 个中文字符 + 1 个占 2 UTF-16 code unit 的 emoji + 10 个中文字符，截断结果完整保留了 emoji、未产生 U+FFFD: \"\(text)\"")
}

/// **边界：恰好等于截断上限**——40 个 `Character` 不应该被截断，也不应该被加上省略号（`guard text.count
/// > maxUncontrolledInputLength` 是严格大于，不是大于等于；这条测试专门钉住这个 off-by-one）。
func testMenuBarSessionNameTextAtExactCapPassesThroughWithoutEllipsis() -> Bool {
    let name = "菜单栏摘要: sessionNameText 输入长度恰好等于截断上限（40 字符）时原样透传,不加省略号"
    let exactlyAtCap = String(repeating: "字", count: 40)
    let text = MenuBarSummary.sessionNameText(exactlyAtCap)
    guard text == exactlyAtCap else {
        return fail(name, "expected 原样透传 \"\(exactlyAtCap)\"（\(exactlyAtCap.count) 字符）, got \"\(text)\"（\(text.count) 字符）")
    }
    guard !text.hasSuffix("…") else {
        return fail(name, "恰好等于上限不应该被加上省略号")
    }
    return pass(name, "长度恰好 40 字符时原样透传，未误加省略号")
}

/// **边界：比截断上限多一个字符**——41 个 `Character` 才应该真正触发截断，截到 40 个 `Character` 再
/// 加省略号。与上一条互为镜像，一起钉死 40/41 这条分界线两侧的行为。
func testMenuBarSessionNameTextOneCharacterOverCapGetsTruncated() -> Bool {
    let name = "菜单栏摘要: sessionNameText 输入比截断上限多 1 个字符（41 字符）时才开始截断"
    let oneOverCap = String(repeating: "字", count: 41)
    let text = MenuBarSummary.sessionNameText(oneOverCap)
    let expected = String(repeating: "字", count: 40) + "…"
    guard text == expected else {
        return fail(name, "expected \"\(expected)\", got \"\(text)\"")
    }
    return pass(name, "41 字符输入被截到 40 字符 + 省略号: \"\(text)\"")
}

/// **短字符串必须完全不受截断器影响**——这是截断器自己最容易犯的缺陷：把不需要截断的输入也动了
/// （比如无条件加省略号、或者做了不必要的字符串重建）。任务书原话："a truncator that mangles short
/// input is its own defect, and this assertion is the one most likely to be missing." 这里用一条
/// 中文短消息直接验证 `connectionStatusText(.failed(...))` 的输出必须逐字符等于未截断的原值。
func testMenuBarConnectionStatusTextForFailedShortMessagePassesThroughCompletelyUnchanged() -> Bool {
    let name = "菜单栏摘要: connectionStatusText(.failed(短消息)) 短消息原样透传,截断器不应该动它一个字符"
    let text = MenuBarSummary.connectionStatusText(.failed("网络不可达"))
    guard text == "连接失败：网络不可达" else {
        return fail(name, "expected \"连接失败：网络不可达\", got \"\(text)\"")
    }
    guard !text.hasSuffix("…") else {
        return fail(name, "短消息不应该被加上省略号")
    }
    return pass(name, "短消息「网络不可达」原样透传，未被截断器误伤")
}
