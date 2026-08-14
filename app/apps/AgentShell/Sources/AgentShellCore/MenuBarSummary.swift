// rounds/0021 Scope-Lock 修订 v1 -> v2（2026-08-14）：最小菜单栏项——显示 template 图标 + 连接状态 +
// 当前会话名。这两行文案的推导逻辑放在这里（不是写进 SwiftUI 视图代码里），理由与
// AppearanceSettings.swift 头注释完全一致，这里不重复整段论证,只重复其中直接适用的一句：
// `AgentShell`/`frame-replay-tests` 都是 `executableTarget`,SwiftPM 不允许两个 executable target
// 互相 import,SwiftUI 视图代码结构性地不可能被 frame-replay-tests 单测覆盖——可推导的判断逻辑必须
// 收在 `AgentShellCore` 这个两边都能 import 的 library target 里,才谈得上"入库测试覆盖"。
//
// 不 import SwiftUI/AppKit——纯字符串推导,任何输入组合的输出都是确定性的。

import Foundation

/// 菜单栏摘要——`MenuBarExtra` 内容视图只消费这里算出的两行文案,不再自己判断"这个连接状态该显示
/// 成什么字"。
public enum MenuBarSummary {
    /// 连接状态 -> 菜单栏展示文案。措辞与 `SessionListView.connectionText`（侧栏连接状态指示）保持
    /// 同一套用词("未连接"/"连接中…"/"已连接"/"连接失败：…"),但 `.connected` 态刻意不重复侧栏那样
    /// 展开完整的 `scopes` 列表——菜单栏是空间受限的摘要位置,"已连接"这一个事实已经完整回答了"当前
    /// 是否连上了内核"这个问题,scopes 明细仍然只在侧栏展示,不是被这里遗漏。
    ///
    /// `.failed(message)` 的 `message` 是真实 `NSError` 的描述文本（经 `OpenclawGatewayKernelClient`
    /// 透传）,实机见过整段类似 `transport error: Error Domain=NSURLErrorDomain Code=-1004 "Could
    /// not connect to the server." UserInfo={...}` 的完整错误描述——原样塞进一个 `.menu` 样式下拉菜单
    /// 的一行会把菜单宽度撑到远超屏幕（用户实测踩到的缺陷,不是假设场景）。因此这里在拼接前对
    /// `message` 做 `truncatedForMenuLine(_:)`（定义与取值理由见下）。`SessionListView.connectionText`
    /// （侧栏）是完全独立的另一份实现,不受这里影响——侧栏仍然原样展示完整错误文本,菜单栏和侧栏本就
    /// 不是同一处展示,菜单是"一眼扫过"的摘要面,完整诊断信息留在侧栏（主窗口内的行为一字不改，
    /// 这也是本轮修订的红线之一）。
    public static func connectionStatusText(_ status: ConnectionStatus) -> String {
        switch status {
        case .notConnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .failed(let message): return "连接失败：\(truncatedForMenuLine(message))"
        }
    }

    /// 当前会话名展示文案。`nil`——没有任何已选中的会话,可能是应用刚启动、还没创建过会话,也可能是
    /// 恢复流程尚未完成——给一个明确的占位文案,不是空字符串。空字符串在菜单里会呈现成一行看不出内容
    /// 的空白,用户分不清那是"确实没有会话"还是渲染出了 bug（呼应本壳"失败/异常可诊断"的既有原则,
    /// 同 `ChatSessionViewModel`/`SessionStore.swift` 对未知状态的一贯处理方式）。
    ///
    /// 会话名是用户自己起的、可以直接粘贴任意长文本进去——不受控的原因和上面的 NSError 消息不同
    /// （不是系统给的诊断串,是用户输入本身没有长度上限）,但会造成完全一样的后果（撑穿菜单宽度）,
    /// 所以同样过 `truncatedForMenuLine(_:)`。
    public static func sessionNameText(_ selectedSessionTitle: String?) -> String {
        truncatedForMenuLine(selectedSessionTitle ?? "无活动会话")
    }

    /// 菜单栏单行文案里"不受控输入"部分（NSError 全文 / 用户自定会话名）的最大展示字符数。这是
    /// 唯一有回归测试保护的截断点——`MenuBarExtraContent.swift` 里 `Text` 上另外叠了一层
    /// `lineLimit`+`frame(maxWidth:)`,但那是视图代码,结构性地不可测（本文件头注释已经讲过：
    /// `AgentShell`/`frame-replay-tests` 都是 executableTarget,SwiftPM 不允许互相 import）,只能
    /// 当第二道防线,不能当唯一防线。
    ///
    /// 取 40 的理由：这是一个**字符数**上限（Swift `Character`,即 extended grapheme cluster 计数,
    /// 见 `truncatedForMenuLine(_:)` 的实现),不是像素宽度——本文件刻意不 `import SwiftUI`（见文件
    /// 头注释："不 import SwiftUI/AppKit,纯字符串推导"）,没有条件做真实文本测量,也不该为了量宽度
    /// 破例引入视图框架。按系统菜单字体（13pt 常规）的经验估算：全 CJK 内容下单字符视觉宽度大致是
    /// 全 ASCII 字符的 1.6~2 倍,40 个 CJK 字符落在约两三百到五百点宽的区间,仍在常规菜单栏下拉菜单
    /// 的可视宽度内、不会像本次缺陷那样撑穿屏幕；英文为主的真实 NSError 文本（如任务书给出的
    /// "transport error: Error Domain=NSURLErrorDomain Code=-1004 ..." 示例）字符更窄,截断后观感
    /// 只会更紧凑,不会比 CJK 情形更宽。这是工程估算,不是实测像素值——如实标注,不假装测量过。
    private static let maxUncontrolledInputLength = 40

    /// 在 `Character`（Swift 的 extended grapheme cluster,不是 UTF-8 字节、也不是 UTF-16 code
    /// unit）边界上截断。`String.count`/`String.prefix(_:)` 本身就是按 `Character` 走的集合操作——
    /// 天然不会切碎单个汉字,也不会切碎需要 UTF-16 代理对或多个 Unicode scalar 组合而成的单个
    /// grapheme cluster（例如 emoji）。**不要**改成 `text.utf8.prefix(n)` 或 `text.utf16.prefix(n)`
    /// 这类写法——那两种视图分别按字节、按 UTF-16 code unit 计数,在这段文案"中文为主"的前提下极容易
    /// 切在字符中间,产出损坏的半个字符（已用独立探针实测过这个具体场景：39 个"中" + 1 个占 2 个
    /// UTF-16 code unit 的 emoji,naive UTF-16 code unit 截到 40 unit 恰好切在该 emoji 的代理对
    /// 中间,`String(utf16CodeUnits:count:)` 把断裂的高位代理转成了 U+FFFD replacement character——
    /// 不是猜测,是真实运行过的探针结果）。
    ///
    /// 长度未超上限时原样返回同一个 `String`（不做任何转换、不加省略号）——短字符串必须完全不受这个
    /// 函数影响,这是截断器自己最容易被破坏的一角（把不需要截断的输入也动了,是它自己的缺陷,不是在
    /// 修别的缺陷）。
    private static func truncatedForMenuLine(_ text: String) -> String {
        guard text.count > maxUncontrolledInputLength else { return text }
        return String(text.prefix(maxUncontrolledInputLength)) + "…"
    }
}
