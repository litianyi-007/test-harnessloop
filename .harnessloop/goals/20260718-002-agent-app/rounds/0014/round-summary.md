# Round Summary — rounds/0014

**目标**：用户 2026-08-11 裁决「做 1，开一轮修会话持久化」。本轮只做这一件事——
rounds/0013 D 探查认定的、「基本使用」的**唯一阻断**：app 一重启，会话就从界面全部消失。

## 结论：**阻断已解除**

| 块 | 内容 | 终态 |
|---|---|---|
| **A** | 会话清单持久化 | 达成。`SessionPersistence.swift`，`SessionHandle`（Codable）+ openclaw `key` + 标题 + 时间，版本化文件，落 `Application Support`（`AGENT_SHELL_STATE_DIR` 可覆盖） |
| **B** | 适配器映射重建 | 达成。加法式 `SessionRestoring` 协议，`restoreSession` 重新播种 `kernelKeyBySessionID` 后复用**未修改的** `subscribe()` |
| **C** | 消息历史恢复 | 达成。WS `chat.history` RPC，按 `hasMore`/`nextOffset` 真翻页 |
| **D** | 重新订阅 | 达成。恢复的流与新建会话走同一条 `consumeEvents` 路径 |

## live 重启验收（主会话亲跑）

| 阶段 | 观察 |
|---|---|
| 重启前 | 建 2 个会话；会话 1 完成一轮往返（`SESSION-ONE`） |
| **重启后** | **两个会话都在列表里**；**会话 1 的完整对话恢复**（用户提问 + assistant 回复） |
| **恢复后继续用** | 发新消息拿到回复，`messageSeq` = **4** —— 接着重启前的 seq 2 往下走，**证明是同一个内核会话，不是新建的**。这坐实 B 与 D 真的生效 |

对比 rounds/0013 的现场：重启后列表全空、**连 wire trace 都不产生**（从不尝试拉取）。

## 两条破坏性反证（均由主会话亲手做，先看到红）

1. **坏持久化文件**：写入 59 字节非法 JSON（内容已逐字打印留证）→ 壳**未崩溃**，回到空列表、
   连接正常、可继续新建。
2. **翻页**：在 `fetchFullHistory` 收集完第一页后强制 `break` → **50/50 掉到 48/50**，
   两条同时变红（翻页断言 + 游标不推进守卫，后者本就依赖循环进入第二页）。恢复后回到 50/50，无残留。

## 硬判据（全部由主会话独立复跑）

`swift build` 通过 · 帧回放 **50/50**（基线 41 + 新增 9）· CI 平价 **12 PASS / 0 FAIL / 1 DEGRADED** ·
**D1 七法签名逐字未变**（新增三法在独立的加法式协议里）· `app/contracts`/`app/generated` 未动 ·
三端 codegen 四项全绿 · `.app` 可运行 · **RAE-0001 重跑 pass 不回归**（3 轮往返、history 6 条
`hasMore:false`、对账 PASS、`--drop-one` 守门）

## ★审查闸 T-093（grok）—— **PASS_WITH_NOTE，No MUST-FIX**

六问逐条通过：D1 红线未破且 `subscribe` 的发送屏障完好；持久化 fail-safe、`kernelKey` 与
`kernelSessionID` 正确区分、无凭证落盘；翻页经评审方独立构造反例验证；恢复语义与新建等价；
两处 scope-lock 中途更正「explicit and source-grounded，不是事后放宽」。

**三条 note（本轮不改，登记入下轮候选，以保持「被评审的状态 == 最终状态」）**：
1. `fetchFullHistory` 对**非布尔** `hasMore` 是**静默停止**而非报错——同一族的静默截断风险
   （后果是少读历史，属保守失败，但仍应 fail-closed）
2. 恢复用的 placeholder handle 把 `kernelSessionID` 设成了 `kernelKey`——潜在混淆
3. live 矩阵只完整证了**一个**会话的历史恢复；**多页历史**与**会话 2 非空历史**未实跑覆盖

## 本轮被推翻的结论（继续留痕）

1. **我在 scope-lock 里把分页字段钉成 `hasMore`/`nextCursor` 并给了 `session-history-state.ts` 的行号——引错了实现。**
   openclaw 有**两套** history 分页：WS `chat.history` 用 **`nextOffset`**（数字偏移），
   `nextCursor` 属另一条通路。实现方指出，主会话核实属实。
2. **我的 scope-lock 与我发给实现方的 brief 自相矛盾**：前者写死「复用已验通的 HTTP 通路」，
   后者写「通路你自己选，建议 WS RPC」。已按纪律第 4 条**显式改 scope-lock**，而非事后放宽解释。
3. **「CLI 0 轮完成」一度被我怀疑成 0014 的回归——不是。** 是
   `sessions.create unavailable during gateway startup` 的启动竞态：
   **`[gateway] ready` 不足以保证 `sessions.create` 可用**。这是 repro 工具的真实缺口（见下）。
4. **我差点判定 grok 的审查闸「根本没读代码」——错了。** 依据是它的 raw log 只有 29 行，
   而 codex 那三轮是 12006/6006/2712 行。真因是 hopper 对 grok 标了 `bufferedOutput vendor`，
   **raw log 只收尾部 JSON，不含中间工具调用**；那份 JSON 里 `num_turns: 11`、
   `input_tokens: 127339`、`cache_read: 893952` 表明它确实做了实质工作，产物里也有横跨全部
   目标文件的 file:line 引用。**拿不同输出模式的 vendor 比 log 行数，是错误的比法。**

## 已确认缺陷（待办）

| 缺陷 | 属谁 | 本轮处置 |
|---|---|---|
| `[gateway] ready` 不足以保证 `sessions.create` 可用（启动竞态） | `repro/start-isolated-kernel.sh` | **未修**，本轮以加延迟绕过。就绪判据应改为探测 `sessions.create` 真可用 |
| 非布尔 `hasMore` 静默停止 | app（`fetchFullHistory`） | 未修，登记（审查闸 note 1） |
| hopper：queue brief 在无 leader-tasklist 条目时被静默丢弃 | hopper | **已按 user-confirmed 授权建 issue**（`hopper-plugin/ISSUE-queue-brief-dropped-without-leader-tasklist.md`），**未改代码、未 bump、未 push** |
| `~/.local/bin/hopper-dispatch` shim 指向已不存在的旧路径 | 本机环境 | 未修，绕过（直调 submodule CLI） |
