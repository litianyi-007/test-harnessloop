# rounds/0015 —— 触发收敛守卫，停下等用户裁决（2026-08-12）

scope-lock 的驱动模型写着「**收敛守卫：第 3 个 MUST-FIX → checkpoint**」。
本轮实际计数已到 **6**，越线两倍。按纪律停下，不继续自行迭代。

## 已达成的（live 实测，证据已冻结）

**exec 审批端到端跑通，放行与拒绝两条路都验过：**

| 环节 | 证据 |
|---|---|
| 审批卡渲染 | `live/shots/card-rendered.png`、返工后 `postrework-card.png` |
| 允许 → 命令真执行 | `allow-executed.png`；`approval.resolve(decision:"allow-once")` 恰好 1 次；assistant 回 ``Done — output was `APPROVAL_GATE_OK`.`` |
| 拒绝 → 命令未执行 | `deny-not-executed.png`；assistant 回「**not executed** … **Nothing ran**」 |
| 返工后无回归 | `postrework-executed.png`；resolve 仍恰好 1 次 |

**硬判据**：`swift build` 通过 · 帧回放 **68/68**（起点 50/50）· CI 平价 **12/0/1** ·
**D1 七法签名 git diff 为空** · 三端 codegen 全绿 · 主会话独立复验全部通过。

**过程中修掉的真问题**：`caps` 未声明导致内核 `no-approval-route` 直接拒绝；
审批关联采集的 stream/phase 与现实不符；decision 映射与逐请求 `allowedDecisions` 校验；
post-RPC 兑现核验（`forceMalformedDeny` 会回 `ok:true`）；D1 §6.2 的单 active + FIFO 状态机；
`stop()` 与人工决策的竞态。

## 未达成的：审批 FSM 的**失败路径与超时路径**

★审查闸两轮共提 6 条，第二轮的四条集中在同一族——**都不是主路径，是边界失败态**：

1. 溢出事件须以 `applied:true + status:denied` 为成功依据；失败不可吞掉，也不可提前宣称已自动拒绝
2. 显式持久化 `FORCE_DENY_PENDING_KERNEL_ACK`；强制 deny 失败后只允许幂等 deny 重试
3. `approval.resolve` 需有界等待；权威 timeout terminal 应能结束对应 in-flight
4. active terminal 必须驱动 UI 清除旧卡片再呈现提升项；队列徽标应接真实缓冲计数或删除

评审方要求补四组反例（overflow 三种失败响应、强制 deny 失败后人工 allow、in-flight timeout、
active timeout → #2 UI 浮现）后再过闸。

## 主会话的建议：**收 0015，另开 0016 专做 FSM 失败路径**

理由：

1. **主判据已达成且可验证**——审批关卡真的立起来了，这是 rounds/0013 认定的信任边界问题的实质解决。
2. **剩下四条是一个自洽的族**（FSM 的失败/超时/持久化路径），值得一个**自己的 scope-lock 与反例矩阵**，
   而不是塞在一个已经越线两倍的轮次尾巴上。
3. **继续在 0015 里迭代违反本轮自己写的守卫**——纪律第 4 条要求按字面标准验，
   守卫也是标准的一部分，不能只在对自己有利时才遵守。
4. 每一轮评审往返都有成本，且发现在收窄但未穷尽（2 → 4，均为真）。

**替代方案**（若用户偏好）：继续在 0015 内修完四条再过闸。技术上可行，代价是本轮进一步拉长，
且守卫形同虚设。

## 安全面（全程）

只读 `kernels/openclaw/`；未碰用户常驻 gateway（pid 29071，全程存活）与 `~/.openclaw`；
隔离实例全部走 scratchpad 并已收干净；凭证守门通过；改动未提交。
