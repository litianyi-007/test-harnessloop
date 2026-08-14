# rounds/0012 live 闭环 —— ①' C 方案的红→绿实证

日期：2026-08-08。**主会话亲跑**（子代理只写代码，不碰 live）。

## 结论

**C 方案在真实链路上证实有效。** 同一撞键形状下，rounds/0011 的重复缺陷不再出现。

## 1. 链路与一处被迫的调整

原计划走 `隔离 openclaw → D3-proxy → Pi new-api → 上游模型`。**跑不通**——隔离实例日志给出确切原因：

```
FailoverError: ⚠️ You've reached your usage limit for this billing cycle.
Embedded agent failed before reply: ⚠️ You've reached your usage limit...
```

即 **kimi 上游额度已耗尽**（正是用户 2026-08-08 说的「已经不在订阅」）。Pi 侧 channel 仍指 kimi，改它属生产宿主写、未获授权。

**处置：让隔离 openclaw 直连 deepseek，绕开整条计费链。** 只改隔离目录内的 `openclaw.json`（预授权 `openclaw-isolated` 行覆盖），**零 Pi 写入**：

```json
"models": {"providers": {"deepseek": {"baseUrl": "https://api.deepseek.com", "apiKey": "<从 channel-params 读>", "api": "openai-completions"}}}
"agents": {"defaults": {"model": {"primary": "deepseek/deepseek-v4-flash"}}}
```

实例自报 `agent model: deepseek/deepseek-v4-flash`，往返成功。

## 2. 正常往返（fix 后）

```
→ messageID=faef4e40  index=1  delta='FIX VERIFIED'
```

模型精确执行「Reply with exactly two words: FIX VERIFIED」。**`messageID` 真传过来了**（非 nil）。

**注意 `index=1` 而非 0**——旧的 `(runID,index)` 键连"index 恒为 0"这个隐含前提都不成立，进一步佐证该键不可靠。

## 3. 注入反证：撞键形状精确复现，UI 不再合并

注入方式：**把 provider `baseUrl` 指向死端口 `http://127.0.0.1:59999`**（全新隔离目录，避开下面 §5 的 label 限制）。

产出事件：

```
→ messageID=a34542e8  index=0  run=5c989156  delta='The agent run failed before producing a reply.'
→ messageID=84a19277  index=0  run=5c989156  delta='The agent run failed before producing a reply.'
```

**同 runID、同 index=0、不同 messageID** —— 与 rounds/0011 造成重复的形状逐字段一致。

UI 表现（`l1-inject-after-fix.png`）：**两个独立的 assistant 气泡，各自完整文本**。

对照 rounds/0011（`../screens/l1-injected-failure-midchain.png`）：**一个气泡，文本拼接两遍**（`...reply.The agent run failed before producing a reply.`）。

**红→绿闭环成立**，且红的那半是既有历史证据、绿的这半是本轮实测，两者形状可逐字段对照。

## 4. 条件② 隔离性 —— `logging.file` 关闭了泄漏面

| 检查 | 结果 |
|---|---|
| 用户全局 gateway PID | **29071 前后一致** |
| `~/.openclaw` 文件数 | **496 → 496 未变** |
| 本轮 8 个 id/目录名/端口在全局 `/tmp/openclaw/*.log` 的命中 | **全部 0 次** |
| 隔离日志文件 | 23KB + 52KB；注入 run id `5c989156` 在其中命中 **7 次** |

`/tmp/openclaw` 整树指纹仍有变化（`809ba635…` → `9017c68d…`），但**归因明确**：用户自己的常驻 gateway 持续写该文件，与我的实例无关——**本轮 0 命中**即证据。对照：同轮早前不设 `logging.file` 的实例，`round0012-openclaw-iso` 在全局日志里**命中 1 次**。

**结论：设 `logging.file` 后，隔离在所有可测维度上完整。**

## 5. 途中发现的两处真实局限（登记，不掩盖）

**① 壳把会话 label 写死**：同一 state 目录下第二次「新建会话」必失败，UI 如实透出
`rpc rejected [INVALID_REQUEST]: label already in use: sg4-kernel-client-l1`。
这是 L1 的真实限制（也是条件④诊断能力的一次正面例证——UI 给出了可操作的确切原因）。
本轮未修（属功能改动，超出修复轮范围），登记为待办。

**② 插桩本身漏了新字段**：`OpenclawWire.swift` 的 trace 记录器只输出 `["index","delta"]`，
`messageID` 加进 D2 后**没同步**。第一次 live 分析因此读到 `messageID=None`，
**我差点据此报「映射没传过来」——那是错的**，真相是插桩没跟上。已修（trace 现输出 messageID）。
**这是「工具与被测对象一起演进时，工具会悄悄落后」的实例**，与本轮 recipe 漏改摘要、
`check-secrets.sh` 硬编码名单是同一族问题。

## 6. 未达成：录屏

scope-lock ⑤ 要求**录屏**。`screencapture -v` 三次尝试均**不产出任何 `.mov`**，进程收到
SIGINT 也不退出——macOS 屏幕录制权限未放行的典型表现。

scope-lock 的 Human Confirmation 栏自己写了：「录屏需系统权限授权，可能需要用户在系统设置中放行
——**撞上就停下说明，不绕过**」。**据此停下，未用截图冒充录屏。**

本轮 UI 证据仍为静态截图 + JSON Lines wire trace + 三侧原始日志。**条件① 的「录屏可见」字面要求
仍未满足**，需用户在「系统设置 → 隐私与安全性 → 屏幕录制」中为终端放行后重跑。

## 7. 收尾

四个端口（3001/18939/18949/18959）全部释放，AgentShell 无残留，用户全局 gateway PID 29071 未受扰。
`app/server/.env` 逐字节还原（`diff -q` 确认）。隔离目录 `scratchpad/round0012-*`（gitignored）保留，
属本轮新建 test-resource；未删除任何非本轮新建的东西。
