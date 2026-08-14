# rounds/0011 Step B 证据 —— SwiftUI Mac 壳 L1 本体

范围：SG-10 L1 的 UI 本体（窗口 / 会话列表 / 新建会话 / 消息流渲染）。执行者 = claude-sonnet-5 子代理（`effort: xhigh`）；本文件记录**主会话独立复验**的实测输出。

**本步不含真实往返**——按分工，起隔离实例、连 D3-proxy 与远端 new-api、发真实模型调用由主会话在下一步主持。子代理全程未连任何真实服务。

## 1. 交付结构

`app/Package.swift` 新增第 5 个 target：`.executableTarget(name: "AgentShell", dependencies: ["KernelClient", "D2Generated"], path: "apps/AgentShell/Sources/AgentShell")`。

```
app/apps/AgentShell/
├── README.md                       构建/运行说明、env 变量、L1 范围界定
├── build-app-bundle.sh             .app 组装脚本
├── Resources/Info.plist            bundle 元数据
└── Sources/AgentShell/             8 个文件，660 行 Swift
    ├── AgentShellApp.swift         @main App + AppDelegate（activation policy）
    ├── ContentView.swift           NavigationSplitView 根
    ├── SessionListView.swift       侧栏：连接状态横幅 + 列表 + 新建会话
    ├── SessionDetailView.swift     消息流 + 输入框
    ├── SessionStore.swift          @MainActor @Observable 状态与编排
    ├── ChatSessionViewModel.swift  单会话 UI 状态
    ├── ChatModels.swift            ChatMessage / ChatRole / ConnectionStatus
    └── KernelShellConfig.swift     env 变量配置
```

## 2. assistant 文本取自哪个事件变体 —— 主会话逐字核验

子代理声称「只有 `.messageDelta` 承载 assistant 文本」。**这是实质性协议主张，不能读注释就信**，主会话对生成产物逐字核对：

- `EventMessageUnion`（`app/generated/swift/DiscriminatedUnions.swift`）**确认 11 个变体**：`messageDelta` / `thinking` / `toolCall` / `toolResult` / `approvalRequest` / `error` / `turnComplete` / `sessionEnd` / `capabilityChanged` / `operationCompleted` / `approvalBufferResolved`。
- `MessageDeltaEventMessagePayload`（`app/generated/swift/D2.swift:1642-1657`）字段 **`delta: String` / `index: Int` / `role: Role`** —— 确认。
- `Role`（`D2.swift:1699-1701`）**只有一个合法值 `case assistant = "assistant"`** —— 确认。

结论成立，且成立方式比「设计如此」更强：`.messageDelta` 在**类型系统层面**就是唯一能承载 assistant 文本的变体，`Role` 结构上无法取到别的值。

**分组键 `(runID, payload.index)` 是一处诚实的假设，不是已证事实**：D1/D2 从未说明 `index` 是「单条消息的分段序号」还是「并行流的通道 id」。子代理在代码内联注明了这一点，并指出 `~/.llm-wiki/agent-app-design/product/d5-1-message-flow.md` §3.1 独立地把同一处标为「诚实缺口」。按两种读法该分组都安全，故 L1 采纳并显式登记为待真实帧验证项。

其余 7 个变体本轮不渲染（`approvalRequest` 归 D5.3/L2 等），`turnComplete`/`error`/`sessionEnd` 仅用于驱动等待态与插入一行系统提示，**不当作 assistant 文本**。

## 3. 主会话独立复验（全部实跑）

| 检查 | 实测结果 |
|---|---|
| 洁净重建全 5 target（`rm -rf app/.build && swift build --package-path app`） | `Build complete! (10.26s)` |
| **Step A 基线未破** | `./app/.build/debug/frame-replay-tests` → **`=== 结果: 30/30 PASS ===`** |
| 三个可执行产物 | `AgentShell` / `frame-replay-tests` / `kernel-client-cli` 均在 `app/.build/debug/` |
| `.app` 组装 | `./app/apps/AgentShell/build-app-bundle.sh` → `OK: app/.build/AgentShell.app`；bundle 内 `Contents/{Info.plist,MacOS/AgentShell,_CodeSignature}` 齐备 |
| **真起窗口** | `open app/.build/AgentShell.app` → `pgrep -fl AgentShell` 命中真实 PID（路径落在 bundle 内）；AX 查询 `windows=1 / title=Agent Shell (SG-10 L1) / frontmost=true / modalSheet=false` |
| 截图 | `evidence/screens/l1-shell-disconnected.png`（仅截 app 窗口区域） |
| 凭证扫描 | `./scripts/check-secrets.sh app/apps app/Package.swift` → `✅ secret 扫描通过（L1-digest + L1-exact + L2）` |
| 收尾 | `pkill -x AgentShell` 后 `pgrep` 无输出，无残留进程 |

## 4. 截图读出来的事实（人工验收依据）

`evidence/screens/l1-shell-disconnected.png` 可见：

- 标题栏 `Agent Shell (SG-10 L1)`，左右分栏成立
- 左侧栏顶部**红色横幅**：`连接失败：transport error: Error Domain=NSURLErrorDomain Code=-1...`——当时本机 `127.0.0.1:18889` 无人监听，属预期失败
- 左下角 `新建会话` 按钮
- 右侧空态：`选择左侧会话，或点击"新建会话"开始`

**这张图对 Pass 条件④（失败可诊断）是正面证据**：连接失败没有被吞进控制台，而是带着具体 `NSURLErrorDomain Code` 呈现在 UI 上。子代理另外用 AX 几何定位点了一次「新建会话」，触发 `createNewSession() → connectIfNeeded()` 再次失败并弹出第二条含完整诊断文本的红色横幅（可关闭，无模态框）——证明按钮接线、async Task、`@Observable` 状态传播、错误呈现整条链路通，不只是窗口画得出来。

## 5. 改动范围核对

新增 `app/apps/`（整目录）+ 修改 `app/Package.swift`（加第 5 个 target/product）。禁区 `app/generated` / `app/server` / `app/contracts` / `app/deploy` / `app/parity` / 三个插件 submodule 经 `git status` 逐一确认**干净**。Step A 已验过的 `app/kernel-client/swift/**` 本步**未再改动**。

## 6. 残留与已知缺口（子代理主动申报，主会话照登不删）

1. **未做任何真实端到端运行**——消息渲染逻辑的正确性目前建立在「读懂 D1/D2 类型 + 照抄 `CLIRunner.runL1CloseLoop()` 已验证的调用序列」上，**没有观测过真实 `evt.message.delta` 流量**。这正是下一步要补的。
2. **`(runID, index)` 分组是假设，未经真实帧验证**（见 §2）。
3. **`stop()` 从未被调用**——L1 无关闭会话入口（stop 按钮属 L2），会话保持订阅至进程退出。属范围选择，但显式登记。
4. **`ErrorEventMessagePayload.recoverable` 的三态（`none`/`run`/`session`，`D2.swift:2517-2521`）被压平**——任何 `.error` 都只清等待态，不按可恢复层级区分。代码内已注明为 L1 简化。
5. **未按 D5.2 §2.2 的「草稿态 → 原子 create+send」设计**，走的是任务书里更简单的「点新建即 createSession」。与产品规格的这处差异显式登记，避免评审以为是遗漏。
6. **成功路径完全未验**——会话真的出现在列表里、assistant 文本真的流进来，这两件事子代理一次都没见过。
7. AX 按钮标题为空（`AXTitle`/`AXDescription` 均 `missing value`），点击靠几何定位。L1 不要求无障碍，登记为粗糙边缘。
8. 未验证在其它 GUI app 占据前台时启动的激活行为（仅验了终端 `open` 一种路径）。

第 1、2、6 条共同指向同一件事：**本步交付的是「能编译、能起窗口、错误能看见」，不是「往返能跑通」**。四条 Pass 条件目前一条也未达成——条件④只拿到了「连接失败可见」这个侧面证据，真正的失败可诊断反证要等真实链路接上后主动注入才算。
