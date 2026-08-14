# rounds/0013 D —— 可用性探查设计（**动手前预登记**）

先写下要测什么、判据是什么，再去测。理由：D 的产出是「阻断 vs 难用」的分类，
而这个分类**极容易在看到结果后被反向解释**。预登记把判据钉死在观测之前。

## 待测假设 H1（scope-lock 的前提可能是错的）

scope-lock「已知的降级面」一节写：

> `respondApproval()` 是桩 → 审批在客户端侧永远 pending；openclaw 侧 timeout-deny →
> **工具调用被拒**。coding agent 若频繁需要审批，可用性会很差，但**不挂死**。

**「不挂死」这个前提现在有反证嫌疑。** 2026-08-11 读内核得到：

| 常量 | 值 | 出处 |
|---|---|---|
| `DEFAULT_EXEC_APPROVAL_TIMEOUT_MS` | **1_800_000（30 分钟）** | `src/infra/exec-approvals.ts:315` |
| `DEFAULT_PLUGIN_APPROVAL_TIMEOUT_MS` | 120_000（2 分钟） | `src/infra/plugin-approvals.ts:50` |
| `SYSTEM_AGENT_APPROVAL_TIMEOUT_MS` | 600_000（10 分钟） | `src/infra/system-agent-approvals.ts:17` |

且 `repro/start-isolated-kernel.sh` 写入的 `openclaw.json` **没有设置任何审批策略**
（只设了 model / providers / logging），即**走内核默认值**。

**H1**：让 agent 做一件需要 exec 的事 → 客户端无法审批 → 会话**卡 30 分钟**才等到 deny。

若 H1 成立，「审批」就不是「难用」而是**阻断**——一个每次用工具就卡半小时的聊天壳不叫可用。

**注意这仍只是假设。** 尚未查清的分支：模型是否真的会触发 exec 审批路径（deepseek 在
`localModelLean` 下的工具使用行为未知）、是否有更早的拒绝路径抢先返回。
**不得据此直接改代码或改结论**（本轮纪律第 1 条）——要用实测计时来判。

### H1 的可测性前置（2026-08-11 补，测之前先排掉的一个坑）

隔离配置设了 `agents.defaults.experimental.localModelLean: true`。**若 lean 模式把 `exec` 裁掉，
D-2 根本触发不到审批路径，那就不是「H1 不成立」而是「没测到」**——两者结论完全相反，必须先分清。

实测 `src/agents/local-model-lean.ts`：

```js
:13  const LOCAL_MODEL_LEAN_DENY_TOOL_NAMES = new Set([...])   // 裁掉高延迟/依赖 channel 的工具
:23  const LOCAL_MODEL_LEAN_DIRECT_TOOL_NAMES = new Set(["exec"])
```

**`exec` 是 lean 模式下的直接工具，不在 deny 名单里** → 审批路径可达，H1 可测。

### 端点就绪（2026-08-11 live 验证，早于取数）

`GET /sessions/<key>/history` 在隔离实例上已验通：无 token → **401**；带 token + 不存在的 key →
**404** 且返回结构化 `{"ok":false,"error":{"type":"not_found",...}}`。
**先验端点再取数**，这样万一实跑对不上，可以直接排除「端点/鉴权不通」这一类解释。

## 测法（判据先定）

| # | 动作 | 记录什么 | 判据 |
|---|---|---|---|
| D-1 | 同一 state 目录连建 3 个会话，来回切换，各发数条消息 | 是否全部成功；UI 能否区分 | 任一失败 = 阻断 |
| D-2 | 让 agent 做一件**需要用工具**的事，**掐秒表** | 从发出到出现任何结果的**墙钟时间**；日志里的审批事件 | ≥ 5 分钟无任何反馈 = **阻断**；有反馈但被拒 = 难用 |
| D-3 | 重启 app | 会话列表、历史消息是否还在 | 历史全丢 = 阻断；需手动重连 = 难用 |
| D-4 | 全程 | 哪些操作没有任何进度指示 | 记录，不单独判级 |

**D-2 的 5 分钟阈值是此刻定的，不是看到结果后定的。** 超时不必等满 30 分钟，
观察到 ≥5 分钟无反馈即可判定并记录实际已等待时长。

## 边界（scope-lock 明文）

- **探查完停下报告，不擅自把 L2 项目拉进来。** 要不要提前做 stop 按钮 / 审批 UI，
  由用户看探查结果决定。
- 只做最小修补以让探查能进行；发现新阻断 → 记录，不当场开工修。
