// 右侧：当前会话的消息流渲染 + 输入框/发送（任务书 UI 最低要求第三、四条）。
//
// rounds/0017 两项改动都主要落在这个文件：
//   - Change 1（让 agent 看起来像 agent）：`messageList` 从只渲染 `session.messages`（纯文本气泡）
//     改成渲染 `session.timeline`（`ChatMessage`/`ToolCallItem`/`ThinkingItem` 按到达顺序合并的
//     统一视图，见 AgentShellCore/ConversationItems.swift），新增 `ToolCallRow`/`ThinkingRow` 两个
//     呈现组件。
//   - Change 2（Liquid Glass 视觉升级）：审批卡片与错误横幅换成标准 material（不是 glassEffect——
//     HIG 分层：消息流本身是内容层，审批卡片是内容层卡片，两者都不该用 glassEffect，见
//     LiquidGlassSupport.swift 头注释引用的任务书分层表）、滚动列表加滚动边缘效果、决策按钮用
//     Liquid Glass 按钮样式（颜色只落在按钮背景上，卡片本身不带色块）。

import SwiftUI
// rounds/0013 B2：SessionStore/ChatSessionViewModel/ChatMessage 移到 AgentShellCore target
// 后，本文件里 `@Environment(SessionStore.self)`、`let session: ChatSessionViewModel`、
// `let message: ChatMessage` 都直接具名引用这些类型，需要显式 import。
import AgentShellCore

struct SessionDetailView: View {
    @Environment(SessionStore.self) private var store
    // rounds/0021：composer 容器（chrome）+ streamErrorBanner（chrome 状态条）都要读同一份已解析的
    // `ChromeMaterialStyle`。
    @Environment(AppearanceSettingsStore.self) private var appearance
    let session: ChatSessionViewModel

    @State private var draftText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            if !session.pendingApprovals.isEmpty {
                Divider()
                approvalSection
            }
            if let streamError = session.streamError {
                streamErrorBanner(streamError)
            }
            Divider()
            composer
        }
        .background(watermarkBackground)
        .navigationTitle(session.title)
        .onAppear { inputFocused = true }
    }

    // MARK: - 熊头水印（视觉/交互打磨任务，2026-08-14 从 SessionListView 搬到这里）
    //
    // **为什么背景挂在整个 `VStack` 上、不需要类似旧版 `.scrollContentBackground(.hidden)` 的动作**：
    // `messageList` 是这个 `VStack` 的一个子视图，它内部的 `ScrollView` 在自己的坐标空间里滚动
    // 内容；`.background(...)` 挂在 `VStack`（`messageList` 的父容器）上，与 `ScrollView` 内部的
    // 滚动偏移量完全无关——`ScrollView` 滚动改变的是它自己内部 `LazyVStack` 的可见区域，不改变
    // `VStack` 本身的大小/位置，水印因此天然"不随消息列表滚动"，不需要手写滚动偏移量补偿。这里
    // 甚至比 `SessionListView` 旧版更简单：`VStack` 没有系统绘制的默认内容背景（不像 `List`/
    // `Form`），不需要先关掉什么才能让水印透出来。
    //
    // 背景挂在整个面板（header/消息流/审批卡/streamErrorBanner/composer 全部在内）而不是只挂在
    // `messageList` 后面——任务书原话"put it in the right session detail panel"，取的是"panel"
    // 最直接的读法：这一整块右侧详情区。水印锚定右下角，视觉上大部分落在消息流下半区背后；
    // composer/审批卡/错误横幅各自有自己的标准 material 背景（`composerChromeBackground`/
    // `contentCardBackground`/`chromeMaterialBackground`），天然盖住水印在它们那一小片区域的
    // 部分——这正是"水印必须在内容层背后、绝不能与卡片/气泡抢注意力"这条要求在 z-order 上的自然
    // 结果，不需要额外写任何"排除某个区域"的逻辑。
    //
    // **为什么用 `GeometryReader` + `.position(...)` 而不是 `alignment: .bottomTrailing` +
    // padding**：`.rotationEffect` 只改变视觉渲染，不改变 SwiftUI 布局系统用来对齐/堆叠的那个
    // frame——把**旋转前**的方形 frame 用 `alignment: .bottomTrailing` 对齐到容器角上，旋转之后
    // 视觉边缘离容器角的实际距离会因为旋转角度而变化，这个距离不是能直接从 `alignment` 参数读出来
    // 的值，所以改用显式算出中心点坐标再 `.position(x:y:)`，把这层几何换算写清楚而不是隐式依赖
    // 堆叠对齐凑出来的近似结果。
    //
    // 换算本身：把一个边长 `side` 的正方形旋转 30°，视觉包围盒会变成边长
    // `side * (|cos30°| + |sin30°|) ≈ side * 1.366` 的正方形，即每边比旋转前多出约 18.3% 的
    // `side`。这里把水印方形 frame 的角预先朝容器角内收 `watermarkCornerInsetFraction`（12%）的
    // `side`，与旋转多出的 18.3% 相抵之后，旋转后的视觉边缘大约还会越过容器角外沿约 6% 的
    // `side`——一点点、左右对称的溢出，读成"贴着角摆放、边角自然出血"，不是"图形被硬生生切掉一
    // 块"（任务书原话："read as an intentional crop, not as a shape that ran out of room"）。
    // 熊头形状自己在这个方形 frame 内部本来就留了一圈透明边距（耳朵/下巴到 frame 边缘还有一段
    // 距离，见 `BearHeadOutline`/`BearHeadHoles` 的设计坐标），多数窗口尺寸下这 6% 的溢出落在这
    // 圈透明边距里，实际可见的熊形轮廓大概率完整，不会被硬切——即便被切到，也只是耳朵/下巴的
    // 外缘一点点，不会切进眼洞/口鼻洞这些辨认度最高的地方。
    //
    // **尺寸——"面板的大约 1/4"落成的公式**：熊头形状在一个正方形设计画布里作画（`BearHeadOutline`/
    // `BearHeadHoles` 内部按 `min(rect.width, rect.height)` 定标居中，非正方形 frame 只会内切出
    // 正方形，不会拉伸变形），这里直接给水印一个正方形 frame，边长取面板短边的一半
    // （`min(width, height) * watermarkSizeFraction`，`watermarkSizeFraction = 0.5`）。面板接近
    // 方形时这块面积正好是面板面积的 0.5² = 1/4；这个 app 的详情面板通常是宽矩形，实际占比会比
    // 1/4 略小——"roughly"允许的偏差，不追求对任意宽高比都精确等于 25%。用 `GeometryReader` 读
    // 面板此刻的真实尺寸而不是写死数字，窗口/侧栏被用户拖动改变详情面板宽度时这个比例仍然成立。
    //
    // **不透明度——为什么比 SessionListView 旧版（0.06）更淡**：侧栏版本背后大多是空白的会话行
    // 列表；这个面板背后是消息气泡/工具调用行/思考行/审批卡，密度高得多，且这里选的锚点（右下角）
    // 就在输入框正上方，是用户打字时视线停留最久的区域之一。两个因素都指向"更该克制、不是更该
    // 炫耀"：这里选 0.04（约为旧版 0.06 的三分之二）。仍然用 `.primary.opacity(...)` 而不是写死
    // RGB——`Color.primary` 本身是随浅/深色模式变化的系统动态色，理由与旧版相同。
    //
    // **无障碍 + 不加玻璃**：`appearance.showsDecorativeWatermark` 复用未改动的
    // `WatermarkVisibilityResolver`（Increase Contrast 开启时整个不渲染，不是"渲染但更透明"——
    // 判断逻辑在 `AgentShellCore/AppearanceSettings.swift`，搬家没有改变"给定无障碍状态该不该
    // 显示水印"这个判断本身，该文件不需要跟着改）。`.allowsHitTesting(false)`——纯装饰，不该
    // 截获任何本该落在消息流/composer 上的点击。全程只有一次 `Color`/`.opacity` 填充，不调用
    // `glassEffect`/`Material`——本轮红线"glass belongs to chrome, never the content layer"在
    // 这里没有例外空间。
    @ViewBuilder
    private var watermarkBackground: some View {
        if appearance.showsDecorativeWatermark {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * SessionDetailView.watermarkSizeFraction
                let inset = side * SessionDetailView.watermarkCornerInsetFraction
                BearHeadWatermark(color: .primary.opacity(SessionDetailView.watermarkOpacity))
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(30))
                    .position(
                        x: proxy.size.width - inset - side / 2,
                        y: proxy.size.height - inset - side / 2
                    )
            }
            .allowsHitTesting(false)
        }
    }

    /// 水印方形 frame 的边长相对"面板短边"的比例——见 `watermarkBackground` 文档注释"尺寸"一节。
    private static let watermarkSizeFraction: CGFloat = 0.5
    /// 水印方形 frame 的角相对面板角的内收比例（乘的是 `side`，不是面板尺寸）——见
    /// `watermarkBackground` 文档注释"为什么用 GeometryReader"一节的推导。
    private static let watermarkCornerInsetFraction: CGFloat = 0.12
    /// 水印不透明度——见 `watermarkBackground` 文档注释"不透明度"一节。
    private static let watermarkOpacity: Double = 0.04

    private var header: some View {
        HStack(spacing: 8) {
            Text(session.title).font(.headline)
            Text("kernel=\(session.handle.kernel.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // rounds/0020：`isInterrupting` 优先于 `isWaitingForReply` 判断——理由同
            // `composerActionButton` 文档注释「为什么外层判断条件」一节：中止在途窗口内
            // `isWaitingForReply` 有可能已经提前变回 false（被中止的 run 恰好在这一刻自然结束），
            // 若这里仍只按它判断，这行指示会在 composer 的按钮还显示"停止中…"的同时先一步消失，
            // 两处状态互相矛盾——用户会看到"composer 说还在停，标题栏却什么都不说了"。
            if session.isInterrupting {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("正在停止…").font(.caption).foregroundStyle(.secondary)
                }
            } else if session.isWaitingForReply {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("等待回复…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
    }

    /// rounds/0017 Change 1：渲染 `session.timeline`（消息/工具调用/thinking 按到达顺序合并的
    /// 统一视图）而不是此前只渲染 `session.messages`（纯文本气泡）——这是"让 agent 看起来像
    /// agent"这条改动的核心落点：工具调用/结果/思考现在和对话文本出现在同一条时间线里，而不是
    /// 只有"你说一句它说一句"。
    ///
    /// Change 2：`.softScrollEdgeEffect` 让滚动到顶部/底部时内容在 header/composer 下方自然虚化
    /// （任务书 concrete 项 4），macOS 26+ 生效、更早系统是 no-op（见 LiquidGlassSupport.swift）。
    private var messageList: some View {
        let items = session.timeline
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text("还没有消息，在下方输入并发送")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(items) { item in
                        TimelineRow(item: item).id(item.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .softScrollEdgeEffect([.top, .bottom])
            .onChange(of: items.count) {
                if let last = items.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    /// rounds/0015 C：待审批请求区。放在消息流与输入框**之间**——它是阻塞性的（agent 正卡在这条
    /// 审批上等人回答），比输入框更需要被看到，但又不该盖住上方的对话上下文（用户往往要看了前文
    /// 才知道这条命令合不合理）。刻意不用 `.alert`/`.sheet`：本壳全程不弹模态（见
    /// SessionStore.globalErrorMessage 的注释——scope-lock 验收要求起窗口验证过程中不能有模态挡住
    /// 界面），审批也不例外；何况模态会把"看前文再决定"这件事变得不可能。
    ///
    /// **rounds/0015 返工①（D1 §6.2）：改为串行呈现——只渲染队头那一条卡片。**
    ///
    /// 此前这里把 `session.pendingApprovals` **全部平铺**，注释还把它写成一个刻意的产品选择
    /// （"用户需要知道总共有几条在等，而不是被一条条推着做决定"）。那个选择与 D1 §6.2 直接冲突：
    /// "同一 session 同一时刻只暴露一个 active pending 审批请求"，且 D1 末句明写这**不是** UI
    /// 呈现优化而是运行时并发分支。真正的收口做在适配器层（`OpenclawGatewayKernelClient` 的审批
    /// FSM：第二条及以后的请求进 FIFO 缓冲队列，根本不 yield `approval_request`），所以正常情况下
    /// `pendingApprovals` 里本就只会有一条。
    ///
    /// **rounds/0016（T-096 第 4 项）：删掉了那行"另有 N 条审批在排队"的队列徽标。**
    ///
    /// T-096 原文："队列徽标应接真实缓冲计数或删除（不得显示编造的数字）。"这里选**删除**，理由是
    /// "接真实缓冲计数"在当前架构下做不到、也不该做：
    ///  - 那个 N 取的是 `session.pendingApprovals.count - 1`，而这个数组里**只可能**装适配器真正
    ///    yield 过 `approval_request` 的条目。缓冲队列里的请求按 D1 §6.2 从不被 yield，所以这个
    ///    数字与真实缓冲深度**没有任何关系**——rounds/0016 起 `SessionStore` 对 `.approvalRequest`
    ///    改为"先清旧卡再呈现"之后，它更是恒为 0，这一行连触发的机会都没有了。
    ///  - 要拿到真实缓冲计数，只能让壳绕过 D2 事件流去问适配器要内部状态——那要么改 D1 七法窄腰
    ///    （本轮红线明令禁止），要么在契约之外另开一条侧信道（架构上更糟）。而且 D1 §6.2 原文要求
    ///    缓冲中的请求"不立即以任何形式呈现给调用方，**不触发新的可见 pending 状态**"，一个实时
    ///    队列徽标恰恰是它要防的那种可见状态。
    ///  - 缓冲请求的可见性由 D1 指定的通道负责，不由徽标负责：它们终态化时会经
    ///    `approval_buffer_resolved`（buffered_timeout / queue_overflow）在会话流里留下系统行。
    ///
    /// rounds/0017 Change 2：外层此前自带一层 `Color.orange.opacity(0.08)` 背景，和内层
    /// `ApprovalCard` 自己的卡片背景形成"色块套色块"的双重着色——删掉外层背景，卡片视觉身份完全
    /// 交给 `ApprovalCard` 自己的 `contentCardBackground()`（标准 material，任务书对审批卡片的
    /// 明确要求），这里只做纯布局（padding），不再重复上色。
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let head = session.pendingApprovals.first {
                ApprovalCard(approval: head, sessionID: session.id)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// rounds/0017 Change 2 concrete 项 8：此前是 `Color.red` 实心背景 + 白字——换成标准 material
    /// （自动适配 Dark Mode/Increase Contrast/Reduce Transparency）+ 语义红前景色 + 图标（给不依赖
    /// 颜色的第二条信号）。这是一条贯穿整个内容区宽度的状态横幅，不是一张"嵌套在窗口里的卡片"，
    /// 所以不用 `contentCardBackground()`（那个方法专为"需要圆角、可能嵌套同心圆角"的卡片设计）——
    /// 直接铺满宽度的 material，不裁形状。
    ///
    /// rounds/0021：背景从固定的 `.regularMaterial` 换成 `chromeMaterialBackground(appearance
    /// .resolvedStyle)`（用户滑块 + 无障碍红线解析结果，与 composer/侧栏各条 chrome 横幅共享同一个
    /// 已解析状态，见 ContentView.swift 该行注释的"coherent"论证）；前景色从字面量 `.red` 换成
    /// `.semanticDanger`（AppearanceEnvironment.swift，固定系统红，不从 accentColor 派生）。
    private func streamErrorBanner(_ message: String) -> some View {
        Label("事件流中断：\(message)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.semanticDanger)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .chromeMaterialBackground(appearance.resolvedStyle)
    }

    /// rounds/0021：composer 容器——四个既定 chrome 表面里唯一一个"此前完全没有背景"的（见
    /// `composerChromeBackground` 文档注释）。左右/底部各留一点 padding，让浮动圆角背景真的"浮"在
    /// 窗口内容区里（不贴边），呼应新样式想要的"悬浮玻璃卡片"观感，而不是紧贴窗口边缘的直角通栏。
    ///
    /// **实测确认的缺陷（视觉/交互打磨任务）：按 Return 不发送。** `axis: .vertical` 让这个
    /// `TextField` 变成会自动长高的多行输入框——Apple 对这个模式的文档行为是 Return 插入换行，
    /// **不**触发提交，`.onSubmit(send)` 因此在按 Return 时结构性地不会被调用（不是概率性的偶发
    /// bug，是这个 API 模式本身的既定行为）。这里仍然保留 `.onSubmit(send)`——它对 Return 这条
    /// 主要路径确实是死代码，但留着零成本，且是"如果这个字段以后被改回单行"的一层免费保险；真正的
    /// 修复是下面 `composerActionButton` 里发送按钮新增的 `⌘↩` 快捷键。
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入消息…", text: $draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)
            composerActionButton
        }
        .padding(10)
        .composerChromeBackground(appearance.resolvedStyle)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// rounds/0020 取舍 #5（scope-lock「有 active run 时替换发送按钮，而不是并排多一个」）：这个
    /// HStack 槽位始终只有一个 `Button`，按会话状态切换它的内容/可用性——不是"发送旁边再摆一个
    /// 停止"，用户不需要判断此刻该点哪一个。
    ///
    /// **为什么外层判断条件是 `isWaitingForReply || session.isInterrupting`，不是只判
    /// `isWaitingForReply`**——中止请求本身也有一段在途窗口（`session.isInterrupting`，见该属性
    /// 文档注释）：从 `interruptCurrentRun` 发起到 `client.interrupt(...)` 真正返回之间，
    /// `OpenclawGatewayKernelClient` 把这个 session 的锁钉在 `.interruptInProgress`，这段时间里
    /// 任何 send()/第二个 interrupt() 都会被内核拒绝 `session_locked`。而 `isWaitingForReply` 有
    /// 可能在这段窗口**内部**提前变回 false——例如被中止的 run 恰好在这一刻自然结束，
    /// `evt.turn_complete` 抢在 `client.interrupt()` 自己的 await 返回之前就被 `handle()` 处理掉
    /// （两者是并发的：一个在 `SessionStore.consumeEvents` 的背景 Task 里，一个在
    /// `interruptCurrentRun` 自己的 Task 里，完整推理见 `SessionStore.interruptCurrentRun` 文档
    /// 注释）。若只按 `isWaitingForReply` 二态切换，按钮会在中止调用还没返回之前就提前跳回"发送"态
    /// 且可点——用户这时点下去会撞上仍然持有的 `session_locked`，这正是任务书要求"不可能通过正常
    /// UI 交互产出 session_locked"要堵的那个洞。用 `||` 而不是只信 `isWaitingForReply`，把这段窗口
    /// 也钉死成不可交互，这个洞在 UI 层被结构性地堵死，不依赖"用户手速不够快点不到"这种运气。
    ///
    /// 三种可见状态：
    ///  - 空闲（两个条件都不成立）——"发送"，可点性只取决于输入框是否为空。
    ///  - 等待回复、中止未发起——"停止"（`stop.fill`），可点，点击调用 `interruptCurrentRun`。
    ///  - 中止在途（`isInterrupting`，不论此刻 `isWaitingForReply` 读到什么）——同一个按钮换成
    ///    进度指示、`.disabled(true)`：不接受任何点击。双保险——`SessionStore.interruptCurrentRun`
    ///    自己也有一道等价的 guard（见其文档注释），这里是 UI 层不依赖那道 guard 的独立防线，两层
    ///    任何一层单独失效都不会真的产出 `session_locked`。
    ///
    /// **视觉/交互打磨任务新增的三处**：
    ///
    ///  1. `⌘↩` 发送快捷键（`.keyboardShortcut(.return, modifiers: .command)`，只挂在"发送"分支
    ///     上）。选 `⌘↩` 而不是"裸 Return 发送、⇧Return 换行"：这个输入框是 `axis: .vertical` 的
    ///     多行框，裸 Return 换行是它当前的默认行为，也是 macOS 上 Messages/Mail 处理多行合成框的
    ///     惯例（Mail 写信、Messages 输入框都是"裸 Return 换行、⌘Return 发送"），改成"裸 Return
    ///     发送"会是一次不符合平台惯例的行为大改（用户已经在用换行组织多行消息的场景下会被打断），
    ///     `⌘↩` 是任务书点名的"safe choice"，这里认同并采用。
    ///  2. **快捷键只挂在"发送"这个 `Button` 上，不是挂在整个 composer 上**——`@ViewBuilder` 的
    ///     if/else 决定了"停止"状态下这个 `Button` 根本不在视图树里，`⌘↩` 的按键等价物自然也就没有
    ///     注册，中止在途/等待回复期间按 `⌘↩` 什么都不会发生，不需要额外一层"是否正在等待回复"的
    ///     判断——用一个视图树结构上的事实（没有登记就不可能触发）替代一条需要手写维护的布尔条件，
    ///     两者在这里等价，前者不会因为将来漏改一处条件而与实际按钮状态脱节。`.disabled(...)` 同理
    ///     ——SwiftUI 对被禁用的 `Button` 自动让它关联的键盘快捷键失效，不需要另外对快捷键单独判
    ///     disabled 条件。
    ///  3. `.help(...)`——发送/停止此前都没有 tooltip，而工具栏新建会话（`ContentView.swift`
    ///     `newSessionButton`）、token 可见性切换（`SettingsView.swift`）这些次要控件反而有。这里
    ///     补齐这两个最高频控件的 tooltip，文案说的是"这个操作做什么"（"发送这条消息"/"停止当前
    ///     生成，不会丢弃已收到的内容"），不是复述控件叫什么名字（"发送按钮"这种同义反复没有信息
    ///     量）；发送态的 tooltip 顺带写出 `⌘↩` 快捷键，帮助这条新绑定被发现。
    @ViewBuilder
    private var composerActionButton: some View {
        if session.isWaitingForReply || session.isInterrupting {
            Button(action: interruptCurrentRun) {
                if session.isInterrupting {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("停止中…")
                    }
                } else {
                    Label("停止", systemImage: "stop.fill")
                }
            }
            .disabled(session.isInterrupting)
            // 视觉/交互打磨任务：此前这个分支和"发送"分支共用 `.prominentActionButtonStyle()`——
            // 同一种突出玻璃/填充样式、同一个 tint,中止操作在视觉上读成了和发送同等重量的"主要
            // 动作"。macOS 的惯例是突出/着色按钮留给肯定性的主动作,插入性/次要动作用不带强调色的
            // 边框样式区分权重（不是颜色）——因此这里换成同一份 LiquidGlassSupport.swift 里已有的
            // `peerActionButtonStyle()`（"平级选项"玻璃/边框样式，本文件另一处用它渲染审批卡片上
            // 并列的决策按钮，同属"不该有默认强调色"的语境）。**刻意不使用语义危险色**——中止生成
            // 不是破坏性操作（不丢弃已经收到的内容，`interruptCurrentRun` 的既有文档注释就是这么
            // 写的），本轮之前刚刚确立"语义色只对应真正的成功/警告/危险状态,不能被挪作它用"
            // （`AppearanceEnvironment.swift` `SemanticColorRole` 文档注释），把停止按钮染成
            // `.semanticDanger` 会是对这条规则的一次新违反，不是延续。降低视觉权重（去掉 prominent/
            // 强调色）足够传达"这不是当前的主要动作"，不需要额外借用一个本该表示"危险"的颜色语义。
            .peerActionButtonStyle()
            .help(
                session.isInterrupting
                    ? "正在停止，请稍候"
                    : "停止当前生成（不会丢弃已经收到的内容）"
            )
        } else {
            Button("发送", action: send)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .prominentActionButtonStyle()
                .keyboardShortcut(.return, modifiers: .command)
                .help("发送这条消息（⌘↩）")
        }
    }

    private func send() {
        let text = draftText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // rounds/0020：中止在途窗口内不派发新的 send()——理由见 `composerActionButton` 文档注释
        // 「为什么外层判断条件」一节。这道 guard 挡的是 TextField 的 `.onSubmit(send)` 这条独立
        // 触发路径（此刻按钮本身已经不再调用 `send`，见上方三态分支），双保险不依赖用户只从按钮
        // 触发提交。
        guard !session.isInterrupting else { return }
        draftText = ""
        Task { await store.sendMessage(text, in: session.id) }
    }

    private func interruptCurrentRun() {
        Task { await store.interruptCurrentRun(in: session.id) }
    }
}

/// rounds/0017 Change 1：`session.timeline` 的每个条目按类型分派到对应的呈现组件。
private struct TimelineRow: View {
    let item: ConversationItem

    var body: some View {
        switch item {
        case .message(let message):
            MessageBubble(message: message)
        case .toolCall(let tool):
            ToolCallRow(tool: tool)
        case .thinking(let thinking):
            ThinkingRow(thinking: thinking)
        }
    }
}

/// 一条 evt.tool_call/evt.tool_result 呈现——任务书原话："a distinct, compact row … visually
/// different from user/assistant bubbles"；"Pair toolResult with its originating toolCall …
/// show success/failure plus a collapsed result preview that can be expanded."
///
/// 内容层元素——背景用标准 material（`contentCardBackground`），不用 `glassEffect`：HIG 分层表
/// 明确"消息流本身是内容层，永远不对气泡用 glassEffect"，工具调用行是消息流的一部分，同一条规则
/// 适用，不因为它是新加的就单独破例。
private struct ToolCallRow: View {
    let tool: ToolCallItem
    @State private var isResultExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tool.name)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                    if !tool.argumentSummary.isEmpty {
                        Text(tool.argumentSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if let result = tool.result {
                    resultDisclosure(result)
                } else {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("运行中…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCardBackground(cornerRadius: 8)
    }

    @ViewBuilder
    private func resultDisclosure(_ result: ToolResultSummary) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isResultExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isResultExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                // rounds/0021：字面量 `.red`/`.green` 换成语义色常量（AppearanceEnvironment.swift）
                // ——视觉数值不变（两者底层都是 NSColor.systemRed/systemGreen），变化的是"这两个
                // 颜色现在有名字、且与 accentColor 结构性独立"这件事本身。
                Text(result.isError ? "失败" : "成功")
                    .font(.caption2)
                    .foregroundStyle(result.isError ? .semanticDanger : .semanticSuccess)
                if let ms = result.durationMS {
                    Text("\(ms)ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !isResultExpanded, !result.preview.isEmpty {
                    Text(result.preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)

        if isResultExpanded {
            Text(result.full.isEmpty ? "(空结果)" : result.full)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .insetContentBackground()
        }
    }

    private var statusIconName: String {
        guard let result = tool.result else { return "wrench.and.screwdriver" }
        return result.isError ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        guard let result = tool.result else { return .secondary }
        // rounds/0021：同上，字面量换成语义色常量。
        return result.isError ? .semanticDanger : .semanticSuccess
    }
}

/// 一条 evt.thinking 呈现——任务书原话："Show thinking in a visually de-emphasized way, collapsed
/// by default. Respect thinkingVisibility if the payload carries it." D2 payload 的 `visibility`
/// 字段就是 wire 层对"thinkingVisibility 协商结果"的落地（D2 schema events/thinking.schema.json
/// 的 `$comment`：'visibility 对应 CapabilityDescriptorPayload.thinkingVisibility 协商结果'）——
/// "尊重"体现在：`.raw`/`.summary` 都默认折叠、弱化展示，但标签如实区分两者（`.summary` 对应
/// `redacted_thinking` 内容块，见 EventMapping.swift ①，即内核自己对这段内容做过脱敏/摘要），不
/// 把"摘要"包装成"完整原始推理"冒充。
private struct ThinkingRow: View {
    let thinking: ThinkingItem
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(thinking.text.isEmpty ? "(空)" : thinking.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                Text(visibilityLabel)
                if !isExpanded, !thinking.text.isEmpty {
                    Text(thinking.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
    }

    private var visibilityLabel: String {
        switch thinking.visibility {
        case .raw: return "推理"
        case .summary: return "推理摘要"
        }
    }
}

/// 一条待裁决审批的卡片：呈现「要执行什么 + 为什么要问 + 还剩多久 + 允许哪些决策」四件事，并把
/// 用户的选择回传。字段来源与取舍见 `PendingApprovalItem`（AgentShellCore/ApprovalModels.swift）。
///
/// rounds/0017 Change 2：内容层卡片，标准 material（`contentCardBackground`），不是
/// `glassEffect`——任务书对审批卡片的明确硬约束。颜色只落在决策按钮的 tint 上
/// （`peerActionButtonStyle(tint:)`），卡片本身、命令预览、错误提示都不再用固定不透明度的
/// `Color.orange`/`Color.red` 色块，换成语义色前景 + material/层级填充背景，跟随 Dark Mode/
/// Increase Contrast 自动适配。
///
/// rounds/0021：字面量 `.orange`/`.red` 换成语义色常量（`.semanticWarning`/`.semanticDanger`，
/// AppearanceEnvironment.swift）——**这张卡片是这一轮"deny 必须一眼是危险色"红线要求的直接落点**
/// （`decisionButtons` 的 tint，见下），卡片内其它几处警示/危险文字一并对齐同一套语义色常量，不再
/// 各自散落字面量。
private struct ApprovalCard: View {
    @Environment(SessionStore.self) private var store
    let approval: PendingApprovalItem
    let sessionID: String

    var body: some View {
        // TimelineView 每秒重算一次剩余时间——倒计时是 UI 的呈现职责，模型层不持有定时器
        // （PendingApprovalItem.remainingSeconds(now:) 是纯函数，把"现在几点"当参数传进去）。
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = approval.hasLocallyExpired(now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.semanticWarning)
                    Text(approval.headline).font(.headline)
                    Spacer()
                    Text(countdownLabel(now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(expired ? .semanticDanger : .secondary)
                }

                // 要执行的东西本身——等宽字体 + 可选中，命令必须能被逐字读清、能复制出去核对。
                Text(approval.bodyText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetContentBackground()

                if let reason = approval.reasonText {
                    Text("原因：\(reason)").font(.caption).foregroundStyle(.semanticWarning)
                }
                if let agentID = approval.summary.agentID {
                    Text("请求方 agent=\(agentID)  reqId=\(approval.reqID)")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }

                // 内核声明了、但本适配器认不出的决策取值——如实显示，不假装它不存在（见
                // ApprovalPresentationSummary.unmappedAllowedDecisions 的文档注释）。
                if !approval.summary.unmappedAllowedDecisions.isEmpty {
                    Text("内核还允许本壳不支持的决策：\(approval.summary.unmappedAllowedDecisions.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let error = approval.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.semanticDanger)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentCardBackground(cornerRadius: 4)
                        .textSelection(.enabled)
                }

                decisionButtons(expired: expired)
            }
            .padding(10)
            .contentCardBackground(cornerRadius: 8)
        }
    }

    /// **按钮完全由这条请求自己的 `allowedDecisions` 决定**，不是固定的一组按钮——`ask=always` 的
    /// 实例上内核只给 `["allow-once","deny"]`（`resolveExecApprovalAllowedDecisions`），此时就只
    /// 渲染两个按钮。渲染一个内核不接受的选项，点下去的后果是被服务端 `forceMalformedDeny` 静默
    /// 改写成 deny（见 makeApprovalResolveParams 文档注释），所以"不渲染"本身就是一道防线。
    ///
    /// rounds/0017 Change 2：每个决策按钮用 `peerActionButtonStyle(tint:)`——"平级选项"玻璃样式
    /// （不是 `prominentActionButtonStyle`：这几个按钮谁都不比谁更"首选"，D1 契约允许任意子集/顺序
    /// 出现，硬编码其中一个更突出是编造了一个协议没有承诺的优先级），tint 按语义区分允许/拒绝——
    /// 这正是任务书"颜色只出现在按钮背景上"的落点。
    ///
    /// rounds/0021：**本轮"拒绝必须一眼是危险色"红线的直接落点**。tint 此前是内联三元表达式
    /// （`decision == .deny ? .red : .accentColor`）——改成调用
    /// `ApprovalDecisionSemantics.colorRole(for:)`（AgentShellCore/AppearanceSettings.swift 的纯
    /// 函数，`frame-replay-tests` 直接覆盖了"deny -> .danger，其余 -> .accent"这条映射，见该文件
    /// 测试）。调用点写法与修前的 `approvalDecisionButtonLabel(decision)` 完全同构——`decision`
    /// 的类型仍然只靠 `approval.offeredDecisions` 的元素类型推断得到，本文件依旧不需要（也没有）
    /// `import D2Generated` 就能把它递给一个 `AgentShellCore` 里声明、参数类型来自 `D2Generated`
    /// 的函数，这是这个文件里已经在用的既有能力，不是本轮新引入的限制或例外。
    @ViewBuilder
    private func decisionButtons(expired: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(approval.offeredDecisions, id: \.rawValue) { decision in
                Button(approvalDecisionButtonLabel(decision)) {
                    Task { await store.respondToApproval(reqID: approval.reqID, decision: decision, in: sessionID) }
                }
                .peerActionButtonStyle(tint: ApprovalDecisionSemantics.colorRole(for: decision).color)
                .disabled(approval.isSubmitting || expired)
            }
            if approval.isSubmitting {
                ProgressView().controlSize(.small)
            }
            Spacer()
            // 两种情况下这张卡片可能已经没法再操作了，各留一个"关掉"的出口，避免卡片永久赖在界面上：
            //   - 已过本地倒计时：内核大概率已 timeout-deny，再点决策无意义；
            //   - 出过错：错误可能是"决策已在内核侧终态化"（例如内核没兑现、或审批在 RPC 在途期间
            //     被 stop() 强制 deny），此时再点任何按钮都只会得到 approval_not_pending。
            //     **不自动移除**——错误信息必须先被用户看到，由用户自己确认后关掉。
            if expired || approval.errorMessage != nil {
                Button("关闭") { store.dismissApproval(reqID: approval.reqID, in: sessionID) }
            }
        }
    }

    private func countdownLabel(now: Date) -> String {
        guard let remaining = approval.remainingSeconds(now: now) else {
            return "超时未知" // timeoutMS 不可算时如实说，不显示一个假的 00:00
        }
        if remaining == 0 { return "已超时（本地判断）" }
        return String(format: "剩余 %02d:%02d", remaining / 60, remaining % 60)
    }
}

/// **rounds/0017 返工（code-review-adversarial 判 REWORK，P2）**：修前这里仍是
/// `Color.accentColor/.gray/.orange.opacity(...)` 三个固定不透明度色块当气泡背景——不只是没有
/// 严格执行任务书"内容层必须 standard material"的硬约束，更实际的问题是**无障碍**：固定 alpha
/// 的颜色叠加不会随用户打开的 Increase Contrast 设置自动提高对比度（系统 material/层级前景色会，
/// 手写的 `Color(...).opacity(...)` 不会——两者是完全不同的渲染路径），评审判定这是阻断项。
///
/// 修法选了"严格执行硬约束"这一支（而不是退而求其次换层级填充色）：背景统一换成
/// `contentCardBackground()`（标准 material，和工具调用行/审批卡同一个助手，Dark Mode/Increase
/// Contrast/Reduce Transparency 全部由系统负责，不再有任何一处手写不透明度）；发言者的区分改由
/// **对齐 + 角色标签 + 小图标**三重信号共同承担，不再依赖气泡底色——图标本身的着色是小号前景
/// 字形而不是大面积背景填充，不重演同一类问题。
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: roleIconName)
                        .font(.caption2)
                        .foregroundStyle(roleIconColor)
                    Text(roleLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.text.isEmpty ? " " : message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .contentCardBackground(cornerRadius: 10)
            }
            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "我"
        case .assistant: return "assistant"
        case .system: return "系统"
        }
    }

    private var roleIconName: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "info.circle.fill"
        }
    }

    /// 沿用修前三种气泡底色本来的语义配色（accent/中性/橙），只是把着色对象从"大面积背景填充"
    /// 换成"一个小号图标字形"——小号前景字形不会重演"固定 alpha 背景不随 Increase Contrast 提升
    /// 对比度"这个问题：文字本体的对比度由它下面的 `contentCardBackground()`（标准 material）
    /// 保证，图标只是一个锦上添花的、不承载必读信息的辅助扫视线索。
    private var roleIconColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .secondary
        case .system: return .orange
        }
    }
}
