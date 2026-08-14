# rounds/0012 插桩跑 —— 实测结论

日期：2026-08-05。插桩代码 = claude-sonnet-5 子代理（`effort: xhigh`）；**跑与分析 = 主会话亲跑**。

原始产物全部落在 `evidence/raw/`（`wire-trace.jsonl` 36KB / `openclaw-gateway.log` / `d3proxy.log` / `agentshell-stdout.log` / `l1-doubling-reproduced.png`），已过 `check-secrets.sh`。

## 1. ① 分组机制 —— 定位完成，根因坐实

### 1.1 关键事实：`session.message` 层没有流式分段

正常回复（要求模型输出 1 到 12，每行一个数字）的 trace：

```
[11] case=session.message producedCount=1 msgSeq=2 msgId=25efe9b9 role=assistant
       → evt.message.delta seq=1 run=b53d403a index=0
         delta='1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12'
```

**一条帧、一个事件、完整全文。** `session.message` 层不做增量投递——增量在 `chat` 旁路流上，而 kernel-client 不消费它（见 `item1-mechanism-localization.md` §1）。

推论：`SessionStore.appendAssistantDelta` 里的 `session.messages[idx].text += event.payload.delta` **在这一层永远是错的**——`delta` 携带的是完整消息而非增量，追加只会重复。它没在正常路径暴露，只是因为正常路径每 run 恰好只有一条 assistant 消息。

### 1.2 根因：同 run 多条 assistant 消息时 `(runID, index)` 撞键

主动注入（壳保持连接、停掉 D3-proxy）后的 trace：

```
[22] case=session.message msgSeq=4 msgId=1cf68049
       → evt.message.delta seq=1 run=0700f2fb index=0
         delta='The agent run failed before producing a reply.'
[30] case=session.message msgSeq=6 msgId=0aaec118
       → evt.message.delta seq=2 run=0700f2fb index=0
         delta='The agent run failed before producing a reply.'
[33] case=agent
       → evt.turn_complete seq=3 run=0700f2fb
```

**两条不同的 wire 帧**（`messageId` 分别为 `1cf68049` / `0aaec118`），同 `runID`、同 `index=0` → `SessionStore` 的键 `"\(runID)#\(index)"` 相同 → 命中既有气泡 → `+=` 追加 → **文本重复两次**。

rounds/0011 截图里那段 `...reply.The agent run failed before producing a reply.` 的成因至此有数据支撑，不再是推断。

### 1.3 正确的分组键存在，但有契约边界问题

`payload.messageId` 每帧唯一（实测 `206ca108`/`8c1e63cc`/`25efe9b9`/`1cf68049`/`0aaec118` 两两不同），是天然正确的分组键。**但它目前在全仓被读取 0 次**，且 **D2 的 `MessageDeltaEventMessage` 不携带该字段**。

于是修法有边界问题：把 `messageId` 透传进 D2 事件需要改 D2 schema → 触碰 `app/generated/`（本轮禁区）与 D1/D2 契约语义（本轮禁区）。

**候选修法（本轮尚未选定，需用户裁决或下一步设计）**：
- **A. 壳侧不分组**：既然一条 assistant 消息 = 一个事件 = 完整文本，UI 每收到一个 `evt.message.delta` 就开新气泡，取消 `(runID,index)` 分组与 `+=`。**零契约改动**，与实测语义一致。风险：若将来 `session.message` 层引入真流式，需回头重做。
- **B. 壳侧改追加为覆盖**：保留分组键但把 `+=` 改成 `=`。能消除重复，但两条**不同**的消息仍会共用一个气泡（后者覆盖前者），会**丢失**第一条——比现在更糟。**不推荐**。
- **C. 透传 `messageId`**：正确但需动 D2 schema，超出本轮范围，须另开设计轮。

倾向 **A**：它是唯一既符合实测语义、又不碰契约的选项。

## 2. ③ messageSeq —— 可用，但缺口需要解释

实测 `messageSeq` 序列（仅 `session.message` 帧）：`1`(user) → `1`(user) → `2`(assistant) → `4`(错误消息) → `6`(错误消息)。

~~**缺口真实存在**（缺 3、5）~~ —— **本节结论已于 2026-08-09 作废，见 `item3-messageseq.md`。**

**实际没有缺口。** 完整插桩下的序列是 `1,1,2,3,3,4,5,6`——连续、单调非递减、带合法重复。
先前「缺 3、5」是**观测偏差**：那次观测在插桩存在之前，`handleSessionMessageEvent` 只在映射失败时打日志，于是日志里只有 `role=user` 帧、**assistant 帧一条不留痕**，我把「没看见的号」当成了「缺失的号」。
缺的那些号正是 assistant 帧，它们一直都在。

另：`messageSeq` 是 **transcript 侧计数**（`server-session-events.ts:189-215` 源码坐实），**不承载「本订阅收到几条」的信息**——所以即便真有缺口也合法，**该字段单独无法用于丢帧检测**。

**在查清之前不得据此写丢帧断言**——这正是 scope-lock ③ 写死「两种解释导出完全不同的断言，不许在没查清前二选一」的原因。

## 3. 条件② 隔离性 —— 发现一处**被证明存在**的泄漏

### 3.1 `/tmp/openclaw` 泄漏，直接归因

| 时点 | `/tmp/openclaw` 指纹 |
|---|---|
| 起服务前 | `1276c93fe545…` |
| 收尾后 | `96dbbe3dd9d0…` |

**归因不靠推测**（rounds/0011 的教训）：
- 隔离实例自己的启动日志逐字写着 `[gateway] log file: /tmp/openclaw/openclaw-2026-08-05.log`
- 本轮 run id 在该全局文件里命中：`b53d403a` × 1、`0700f2fb` × 7
- 本轮隔离目录路径 `round0012-openclaw-iso` 在该文件里命中 1 次

**结论：`OPENCLAW_STATE_DIR` + `OPENCLAW_WORKSPACE_DIR` 都覆盖不到日志路径，隔离实例确实写入了与用户实例共享的全局文件。** recipe §5 当年记的「未深挖其覆盖 env」，现在有实测坐实它确实是个真泄漏面。

### 3.2 `TMPDIR` 假设 —— **已证伪**

`resolvePreferredOpenClawTmpDir`（`kernels/openclaw/src/infra/tmp-openclaw-dir.ts:40`）的 fallback 走 `getOsTmpDir()`，而 `os.tmpdir()` 确实受 `TMPDIR` 控制（实测：默认 `/var/folders/…`，设 `TMPDIR=/tmp/probe-tmpdir-test` 后即返回该值）。据此我假设设 `TMPDIR` 可把日志重定向进隔离目录。

**实测推翻**：起一个 `TMPDIR=<隔离>/tmp` 的探针实例，它仍自报 `log file: /tmp/openclaw/openclaw-2026-08-05.log`，隔离 tmp 下无任何 `.log`，而全局文件里出现该探针的 2 处命中。

**附带观察**：`TMPDIR` **被部分组件采纳**——探针的隔离 tmp 下生成了 `tmp/jiti/openclaw/2026.7.2/…` 缓存。所以不是「TMPDIR 完全无效」，而是**日志路径的解析不走那条链**。

**该项仍未解决**：目前没有找到能隔离 openclaw 日志路径的 env。条件② 若要求「全程未触碰用户环境既有 openclaw 相关全局路径」，本轮**尚不能达成**，除非：(a) 找到真正的覆盖手段，或 (b) 由用户裁决把 `/tmp/openclaw` 明确排除在条件② 的范围之外并写明理由。**这是需要用户决定的判据问题，不由我单方面收窄。**

### 3.3 其余隔离维度成立

| 检查 | 结果 |
|---|---|
| `~/.openclaw` 文件数 | 493 → 493，未变 |
| 本轮 5 个 run/session/message id 在 `~/.openclaw` 命中 | **全部 0** |
| 用户全局 gateway | PID **29071** 前后一致，端口 18789 未受扰 |

## 4. 一处过程失误（如实登记）

第一次 `TMPDIR` 探针我等了 14 秒就 `pkill`，而实例因新状态目录要做 DB 迁移，只跑到 `starting...` 就被杀——**那次测试无效**，我据此差点得出「日志未生成」的错误结论。已重做并等到 `log file:` 行出现才判读。

同一轮里还有一次：`rm -rf` 探针目录因进程占用而**失败**，但我的脚本用 `&&` 链接了成功消息、照打「已清」。第二次才真正清干净。**两次都是「没验就报」**，与本轮要修的毛病同形。

## 5. 本轮至此的产出与未决

**已完成**：①机制定位（根因坐实，修法待定）、⑤原始日志落 evidence（`raw/` 5 个文件，含 JSON Lines wire trace）、③的 `messageSeq` 可用性确认（缺口待解释）。

**未开始**：②订阅竞态查证、④recipe 文末补漏、⑥可复现步骤。

**需用户裁决**：
1. ① 的修法选 A / B / C（倾向 A，理由见 §1.3）
2. ② 条件②要不要把 `/tmp/openclaw` 排除在外——**这是验收判据的收窄，必须用户定**

---

## 6. ④ recipe 补漏 —— 完成（含一次「我自己的检查是空的」）

### 6.1 发现式排查，而非人眼逐处记

全文枚举 `OPENCLAW_STATE_DIR` 的每一处出现，逐条核对是否伴随 `OPENCLAW_WORKSPACE_DIR`。命令块内共 3 处：

| 行 | 位置 | 状态 |
|---|---|---|
| 40 | §1 主命令 | ✓ rounds/0011 已补 |
| 264 | 文末「回主会话摘要」的复制命令 | **✗ → 本轮补齐** |
| 90 | §1 的 `[实测]` 历史记录 | ✗ **有意保留**，见 §6.3 |

第 264 行就是 codex T-080 指出的那处：rounds/0011 修了 §1 就以为改完了，没做全文枚举。**「改了主文、漏了摘要」是同一份文档内的清单过时**——比跨文件版本清单更容易漏，因为它看起来已经改过了。已在该处就地登记这次漏改本身。

### 6.2 我的第一版检查是空的，被它自己的反证抓出来

第一版检查取 `OPENCLAW_STATE_DIR` 所在行起的 **6 行窗口**判断有无 `WORKSPACE_DIR`。破坏性反证（删掉命令里的 `OPENCLAW_WORKSPACE_DIR=<fresh-empty-dir-2> ` 再跑）结果**与破坏前完全相同**——说明检查根本没检出删除。

根因：6 行窗口把紧随代码块之后**散文里**提到的 `OPENCLAW_WORKSPACE_DIR` 也算了进去。**一条看起来在守门、实则永远为真的检查**——与本轮起因（rounds/0011 把守 F3 的断言引用成「无丢帧」证据）是同一类毛病的不同形态。

重写为「只在 ``` 代码块内、只看命令自身（含 `\` 续行、向上回溯到命令首行）、不看任何散文」后：

```
现状  ✓伴随:[40, 264]  ✗缺:[90]
破坏后 ✓伴随:[40]      ✗缺:[90, 264]
→ 检查有牙齿
```

**如果不是把破坏性反证当硬要求，这条空检查会以「全部通过」的姿态留在证据里。**

### 6.3 第 90 行有意保留为 flagged

那是 SG-4 的 `[实测]` 记录，记的是「当时真跑了什么」，改动它等于篡改记录；且 SG-4 场景不含 `sessions.send`（见 §4），当时缺该变量不构成问题。已在该处加就地告警：**这是历史记录、不是可复制模板，要跑请用 §1 顶部那条**。

**没有教检查去豁免它**——一旦检查学会忽略特例，它就开始自我满足。保留这一条 flagged 的代价是数字不为 0，收益是：将来若有人新增一条缺变量的命令，数字会从 1 变 2，肉眼可见。

### 6.4 顺带把 `/tmp/openclaw` 的结论写回 recipe

§5 原文「本轮未深挖其覆盖 env」旁补了后续块：泄漏已被直接归因坐实、`TMPDIR` 假设已被实测证伪、`TMPDIR` 被部分组件采纳（jiti 缓存）但日志路径不走那条链、**目前仍无已知隔离手段**。

---

## 7. 本轮确认的缺陷汇总（截至 2026-08-09，待办）

均为**已实证**、非推测；本轮范围内未修的，逐条说明为什么。

| # | 缺陷 | 实证 | 本轮为何未修 |
|---|---|---|---|
| D1 | **会话 label 硬编码** `sg4-kernel-client-l1`（`OpenclawGatewayKernelClient.swift:274`），openclaw 侧删会话后 label 仍占用 → **每个 state 目录只能建一次会话** | UI 侧与 CLI 侧**各撞一次**，同一条 `rpc rejected [INVALID_REQUEST]: label already in use`；CLI 竞态实验 7 轮里 6 轮死于此 | 属功能改动（要引入 label 生成/配置），超出修复轮范围。**但它已实际阻碍本轮工作**——任何重复实验都要新起实例 |
| D2 | **服务端 dispatch 竞态未关闭**：`message-handler.ts:475-479` 的 `void` fire-and-forget，无跨帧串行化 | 源码判定 | 关它需要 `subscribe` 等 ack（当前 CI 契约模型下不可行，实测会死锁）或改服务端。两者都超范围 |
| D3 | **`FrameReplayTests` 在依赖图上够不到 `SessionStore`** → UI 层分组行为无法被入库测试覆盖 | 两个子代理独立撞到同一限制 | 解它要改 `Package.swift` 依赖或放宽 `private`，属结构决策，未获授权 |
| D4 | **`capabilities()` 仍是 TODO 桩** → `streamingGranularity` 读不到 → D5.1 §3.1 的渲染契约**目前无任何实现能遵守** | `KernelClient.swift` 文件头自述 | 属功能实现，L2 范围 |
| D5 | **`ErrorEventMessagePayload.recoverable` 三态被压平** | 代码内已注明 | L1 简化，登记 |
| D6 | `~/.local/bin/hopper-dispatch` shim 指向已不存在的 marketplace 路径 | 本轮改用 submodule 内 CLI 派发 | 属本机环境，非本仓代码 |

### 已修并验的（本轮内）

| 缺陷 | 修法 | 反证 |
|---|---|---|
| `(runID,index)` 撞键致消息合并 | 透传 `messageId` 进 D2（走 codegen），壳侧改按 `messageID` 分组、`+=` 改覆盖 | live 注入复现同一撞键形状，UI 由「一个气泡拼接两遍」变为「两个独立气泡」 |
| 客户端写序竞态 | send 侧屏障（等订阅 RPC **已发出**） | 注释掉屏障 → 36/36 变 34/36，恰好两条屏障测试红 |
| recipe 文末命令漏 `OPENCLAW_WORKSPACE_DIR` | 补齐 + 就地登记漏改本身 | 发现式检查（只看命令体、不看散文），破坏后由 ✓ 转 ✗ |
| `/tmp/openclaw` 日志泄漏 | `logging.file` 配置项 | 设了之后本轮 8 个标识在全局日志命中 **0 次**；同轮未设的对照命中 1 次 |
| `check-secrets.sh` 硬编码非凭证名单 | 改为读 `sensitivity` 的发现式规则 + 名字兜底 | 误标 `internal` 但名字带 KEY 的仍被拦住 |
| 复现脚本用 pid 文件杀进程杀不干净 | `stop-isolated-kernel.sh` 以**端口占用者**为准 | 实测 wrapper pid 49666 ≠ 端口占用者 49916；只杀 wrapper 后端口仍占，脚本则释放成功 |
| 脚本中 `$VAR` 紧跟全角标点被吞 | 全部改 `${VAR}` | `set -u` 下原写法直接 unbound variable；实跑抓出 |
