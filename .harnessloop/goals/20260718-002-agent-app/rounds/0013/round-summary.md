# Round Summary — rounds/0013

**目标**：用户 2026-08-11 给的两个里程碑 —— ① 学习点（工程侧沉淀钩子的首次实跑）
② mac app 可以基本使用。路径 = 用户裁定的 **B→C**，外加为里程碑 2 新增的 **D 可用性探查**。

## 三块工作的终态

| 块 | 内容 | 终态 |
|---|---|---|
| **B1** | 会话 label 硬编码 | **达成**。label 改为 `sg4-<timestamp>-<uuid>`，同一 state 目录连建 4 个会话（UI 3 + CLI 1）零冲突 |
| **B2** | `FrameReplayTests` 够不到 `SessionStore` | **达成**。抽出 `AgentShellCore` 库 target，新增 `SessionStoreGroupingTests`，帧回放 40/40 → **41/41** |
| **B3** | 服务端 dispatch 竞态 | **按 scope-lock 本轮不修**，仅记录现状 |
| **C** | 按新条件③ 重跑 RAE-0001 | **达成，判 pass**（四条件逐条见 `evidence/itemC-rae0001-live.md`） |
| **D** | 可用性探查 | **完成，发现一条阻断**（见下） |

## RAE-0001 四条件（本轮 pass）

| # | 条件 | 结果 |
|---|---|---|
| ① | 真实往返 | UI 渲染出 assistant 回复（ALPHA/CHARLIE 截图）；CLI 3 轮往返各拿到不同 runId |
| ② | 隔离性 | **正面归因**：本轮实例 pid 27158 在 `~/.openclaw` 打开文件数 0；SESSION_KEY/messageId 全树 0 命中；隔离库命中 24 |
| ③ | 事件序列 | (a) D2 seq 每 run 内 0 倒退、wire messageSeq 0 倒退 (b) 对账两向差集均 0 → PASS (c) `--drop-one` 变红且删前逐字打印被删记录 (d) 协议级丢帧按条件显式列为内核缺口 |
| ④ | 失败可诊断 | 两次注入 → 两种可区分定位：错端口 → 传输层 `NSURLErrorDomain -1004`；错 token → 鉴权层 `gateway token mismatch` 且带修复提示 |

## D 探查：预设几乎全错，真阻断没被预设到

scope-lock「已知的降级面」列的三条里**两条经实测不成立**：

| scope-lock 原文 | 实测 |
|---|---|
| 审批 pending → timeout-deny → **工具调用被拒** | **没有审批，`exec` 直接执行成功**（0 条 approval 事件，整回合 ~8 秒） |
| 唯一确知的阻断是 label | label 已修；**真阻断是「会话不持久」——没被预设到** |
| 无流式渲染 | ✅ 属实（`evt.thinking` 逐 token 流式但被丢弃，正文只有 1 条 delta） |

**唯一阻断**：app 重启后会话全部从界面消失（内核库 5 行，UI 0 行，重启后的 app **连 wire trace 都没生成**——从不尝试拉取已有会话）。数据没丢，缺的是壳去拉。

**详见 `evidence/itemD-probe-results.md`，含交用户裁决的三个事项。**

## 本轮被推翻的结论（继续留痕）

1. **`kernelSessionID` ≠ history 的 `key`** —— 二者是 `sessions.create` 返回的两个**独立字段**。
   CLI 原先只打印 `kernelSessionID`，照它查 history 会查到一个不存在的会话。**对账差点跑错对象。**
2. **「`src/gateway/` 里没有 `chat.history` handler」是错的** —— 真 handler 在
   `src/gateway/server-methods/chat-history-handler.ts:615`。根因不是搜索维度，是**我自己的 `head -10` 把结果截掉了**。
3. **「D2 seq 有 2 处倒退」是错的** —— `seq` 是 per-run 语义，跨 run 重置属正常。**是测法错的**，按 run 分组后为 0。
4. **「UI 侧丢了一条消息」是错的** —— 界面显示第 2、3 条被 `keystroke` 连成了一条发出（`Replywithexactly:  BRAVOReply with exactly: CHARLIE`）。**是我的自动化把回车吞了**，实际发 2 收 2，一条没丢。

> 前两条属 rounds/0012 已记的「我没找到 ≠ 不存在」族；后两条是**新的一族：测量工具本身出错，
> 却被读成被测对象出错**。四次都是**打印实际内容**之后才归到自己身上的。

## 已确认缺陷（待办）

| 缺陷 | 属谁 | 是否本轮修 |
|---|---|---|
| 会话不持久（壳不向内核拉取已有会话） | app（L1/L2 边界待裁决） | 否 —— **交用户裁决** |
| `~/.local/bin/hopper-dispatch` shim 指向已不存在的旧安装路径 | 本机环境（非 hopper 仓内文件） | 否 —— 绕过（直调 submodule CLI）。**本项目迭代回路的缺口：`plugin-reinstall.sh` 重指 marketplace，但没有任何东西重指用户 PATH 上的 shim**，这是同类问题第二次出现 |
| runner 死后 hopper 状态文件停在 `in-progress` | hopper | 已开 `ISSUE-stale-status-on-runner-death.md` |
| B3 服务端 dispatch 竞态 | app/contracts（需 ack 版修法） | 否 —— scope blocker |

## 里程碑 1（学习点）

工程侧沉淀钩子首次实跑：teach-back 落进 `~/.llm-wiki/test-harnessloop`（kata 主场），
新建 4 页 + 更新 7 页，wiki 18 → 22 页。kata 在 rounds/0011–0012 期间调用 0 次，本轮恢复使用。
另提一条 schema 提案（给 tag taxonomy 加 `deepseek`），**未自行应用，待用户批**。
