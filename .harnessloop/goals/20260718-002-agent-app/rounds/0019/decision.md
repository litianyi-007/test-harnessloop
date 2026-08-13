# Decision

- Feedback: positive
- Blocker type: 无
- Recovery eligible: n/a
- Accepted: yes
- Review: .hopper/handoffs/T-112-codex-output.md
- Reviewer: codex via hopper T-112（单路，按 scope-lock）
- Review verdict: **REWORK**（三条 FAIL，主会话全部复核成立后返工；**其中 Q1 踩中本轮红线**）
- Review digest: dcbf6ec8eae5505ddb32dca3cbd820b7ff3975da39592294f92283d51614bac8
- Acceptance evals: none — 本轮为 UI/配置层改动，无 runtime eval 台账
- Acceptance evals detail: n/a
- Active goal: 20260718-002-agent-app
- Active round: 0019
- Decision maker: main session（claude-opus-5[1m]）；用户 2026-08-13 裁定按 2→1→3 顺序执行，并在看过实拍后确认
- Timestamp: 2026-08-13

## Reason

**「token 可填」达成**：新增 Settings 场景（⌘,），token 存 Keychain、endpoint 存
UserDefaults，优先级 `env > 已存设置 > 默认`，且**界面显示当前生效值来自哪一个来源**。

此前的处境是：token 默认值是占位符字符串，**对真内核必然鉴权失败，而 UI 里没有任何
地方能填**——用户双击打开只看到「连接失败」，没有出路。更糟的是本仓文档记着
**`open` 不继承 shell 环境变量**，连「先 export 再打开」对普通用户也不通。

## 评审判 REWORK 三条，其中一条踩中红线

| # | 发现 | 性质 |
|---|---|---|
| **Q1** | `SelfTestHooks.swift` 从**生产 Keychain 条目**读出真实 token 并**原样打印**，且 `strings` 证实**已编进正式 app 包** | **踩中本轮红线**「token 绝不明文落盘」 |
| Q3 | `endpointSource` 在**验证 URL 之前**就被设成「来自环境变量」；env URL 非法时实际值回退成默认，**标签却仍说来自环境变量** | 标签说谎，比不显示更糟 |
| Q4 | `(try? read()) != nil` 把 Keychain 读错误**吞成「未保存」**；endpoint 先落盘、token 保存失败时不回滚也不提示 | 两处静默 |

**Q1 的讽刺之处**：实现方自己在报告里写过该文件「turned out not strictly necessary
since GUI automation worked, but kept」——**既然不是必需的，就不该以「能打印真 token」
的形态留在正式二进制里**。返工选择**整文件删除**，不是禁用、不是挪到测试 target。

**Q2 主会话与评审判定不同**：评审把「预置 token 失败被 `try?` 吞掉」标为环境受限。
**主会话判它是一条真实的空过**——在 Keychain 不可写的环境里，那条「env 胜过已保存
token」的测试根本没建立起竞争值，**测试绿了但想验的东西一次都没验到**。这与本项目
一直在修的「守卫看起来在检查、其实什么都没检查」同族，遂要求修掉而非记为环境问题。

## 独立复核（全部主会话自己跑）

| 判据 | 结果 |
|---|---|
| **红线** | `SelfTestHooks.swift` 已删；app 源码 `print(` **0 个文件**；二进制符号 **0 个**；**对照检查 `KernelTokenKeychainStore` 搜到 1 个，证明 `strings` 本身有效** |
| 唯一 `userDefaults.set` | 传的是 `urlString`，token 全程只走 `SecItem*` |
| 构建 / 帧回放 | exit 0 ／ **102/102**（基线 83 → 99 → 101 → 102） |
| **我自己的反证** | 打破 env 优先级 → 99 掉到 97；还原 99/99、零残留 |
| Q3 矛盾构造 | 评审给的 `env="ht!tp://"` + 有已保存值，**已成为一条测试并 PASS**（`source=.savedSetting`） |
| 禁改路径 | `Package.swift`/`Info.plist`/`generated`/`contracts`/`server`/`parity`/`.github` diff 全 0 |

## 本轮的额外收获：实拍抓到测试抓不到的缺陷

用户裁定的第 1 件（真实 LLM 往返的内容态实拍）在本轮一并做了。**它立刻兑现了价值**：

实拍发现**思考流被撕成几十条碎行**——`TOOLROW_DEMO_OK` 一个词被拆到两行里。
**而单元测试不但没抓到，还把错误行为钉死了**（有一条测试专门断言「thinking 不合并」）。

修复的合并语义**由实证确定**：`EventMapping.swift:616` 注释明写 `data.delta` 是增量、
`data.text` 是累计，代码刻意取增量——**与 assistant 文本的「整段覆盖」正好相反**，
搞反会产出垃圾。合并键只能是 `runId`（thinking 载荷里没有 messageId）。

**实现方还纠正了主会话的一个错**：我说「两条钉错行为的测试」，它查出只有一条真在断言
不合并，另一条只发单个事件、断言的是 visibility——**没有盲从指令去改一个本来没错的测试**。

## Main-Session Decision On Scope Boundary

1. **第 1 件与第 2 件合并在本轮做** —— 实拍需要一个能配置 token 的 app 才好跑，
   两者天然咬合；且实拍立刻反哺出了思考流缺陷。
2. **动过用户系统外观设置并还原**（拍浅色时切过 dark mode）；
   **隔离实例两次起停均收干净**，用户常驻 pid 29071 全程未受影响，每次单独核对。
3. **一张误导性文件名已改** —— `16-thinking-merged.png` 拍的是空会话，
   改名为 `16-recapture-FAILED-empty-session.png`。**文件名不该说谎。**

## Human Decision Required

- **无阻断项。** 用户已看过实拍并确认。

## Open Questions Resolved

- **token 该存哪里** → **Keychain**。UserDefaults/plist 是明文、进备份、可被 `defaults read` 读出。
- **env 与界面设置谁优先** → **env 优先**，否则会静默破坏 repro 脚本与 CLIRunner；
  **但必须显示来源**，只做优先级不显示来源等于造一个新的静默失败。
- **thinking 该 append 还是 overwrite** → **append**（与 assistant 相反），有源码注释与实拍双重佐证。

## Open Questions Remaining（三条证据缺口）

1. **思考流合并后的实拍未取得** —— 连试五种方法都无法把键入送进 SwiftUI 输入框
   （第一次实拍时同样路径成功过，原因未查明）。**属自动化问题非产品问题，
   但不拿测试证据冒充实拍证据。**
2. **工具调用/结果行未被实拍触发** —— 本次 exec 没产生 `tool_call` 事件
   （内核日志 0 次，openclaw 的 exec 走审批路径）。
3. **Reduce Transparency / Increase Contrast 无实拍** —— 系统拒绝程序化开启受保护域。

详见 `evidence/shots/README.md`，每张图拍到什么、没拍到什么逐条标注。
