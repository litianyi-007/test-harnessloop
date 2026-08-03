# Control Contract

## Auto-Continue

Allowed when:

- Feedback class: feedback=positive
- Evidence health: 无 stale
- Environment self-check: pass（见 state/environment.md）
- Open handoffs: 无 open handoff 阻塞
- Human confirmation: 不需要——满足以上条件时自动进入下一子目标；read-only 调查轮（runtime-recoverable）自动开启

## Human Confirmation Required

Required for:

- Scope-lock mutation: main session 自主（版本递增留痕）；但目标解释级变更需用户
- Evidence contract revision: 需用户
- Control contract revision: 需用户
- Failed review acceptance: 仅用户
- Rollback: main session 可执行已分类错误的回滚；跨仓库回滚需用户
- Test-resource write: **不需要逐次确认**（user-confirmed 2026-08-03）——对**测试资源**的写入
  （建库/建表/建 token/写测试数据/起隔离实例/建临时目录与 fixture）视为已预授权，
  main session 可直接执行，不必每次停下来问。

  **边界（超出即回落到上面的 `Irreversible or external-system write`，仍需用户）：**
  - 仅限**本轮 scope-lock 声明过的**外部系统与资源；未声明的系统不在此列。
  - 仅限**可识别为测试用途**的资源：隔离实例、专用测试 token、带测试前缀/后缀的库表与
    数据、临时目录。**共享或生产资源不在此列，即使写的是"测试数据"。**
  - **删除与覆盖不在预授权内**——预授权覆盖的是"新建"，清理既有资源仍需用户确认
    （对应 Blocker Classification 的 `write-safety-required`）。
  - 触发第三方计费的写入（真实 LLM 调用等）不在此列，按既有成本纪律另议。

  **理由**：runtime 验收 eval 必须真的把外部系统跑起来才有意义，而建测试资源是其前置。
  逐次确认会让"自主推进到 goal 完成"这条主线在每个 eval 前中断一次——这正是本项目
  「补充 runtime/多系统测试作为 evals」那条需求要解决的问题。**预授权换来的是自主度，
  代价是"测试资源"这个判断由 main session 自己做**，所以边界写死在上面，越界即回落。
- Irreversible or external-system write: 需用户（例外：git push 到 litianyi-007/harnessloop、litianyi-007/test-harnessloop、litianyi-007/hopper-plugin 与 litianyi-007/kata 四仓在批次验收通过后为既定授权流程，无需逐次确认；三个插件（harnessloop / hopper-plugin / kata）push 前均须同步 bump 版本信息，保持各自版本文件一致后才能 push——harnessloop 的版本 bump 已是既有发布惯例；hopper-plugin 版本文件以仓库实际布局为准：.claude-plugin/marketplace.json、package.json 及 CLI 版本串等全部一致；kata 版本文件为 plugin/.claude-plugin/plugin.json、.claude-plugin/marketplace.json、CHANGELOG.md，同样须全部一致；未 bump 版本不得 push（用户条件 2026-07-17）） (user-confirmed 2026-07-17：定位与既有两插件相同)

## Stop Conditions

Stop when:

- Blocking condition: human-decision-required / access-missing / write-safety-required 且下一安全动作需用户输入时
- Blocker type: 见下方 Blocker Classification（协议 7 类）
- Missing evidence: TODO (owner: user)
- Environment mismatch: TODO (owner: user)
- Model/effort mismatch: TODO (owner: user)
- Contract cannot be evaluated: TODO (owner: user)

## Blocker Classification

| Type | Continue behavior | User input required |
| --- | --- | --- |
| runtime-recoverable | Start read-only investigation or recovery-planning round | no |
| access-missing | Stop and ask for missing access/tool facts | yes |
| write-safety-required | Stop before mutation; ask for write safety and confirmation | yes |
| human-decision-required | Stop and ask for decision | yes |
| contract-insufficient | Repair contract before execution | maybe |
| external-system-unsafe | Allow bounded observation only | maybe |
| unknown | Ask for facts needed to classify | yes |

协议 7 类照录；其中 runtime-recoverable 与 contract-insufficient 可自恢复（后者限契约修复动作，不得借此扩大到业务执行）。

## Delegation Boundaries

Allowed delegated work: 只读发现/对抗审查（Workflow 多 agent 并行）；一切写入类任务（代码/文档）委派 claude-sonnet-5 子代理

Disallowed delegated work: 目标解释、breakdown 审批、scope-lock 变更、轮次验收、评审失败后的接受

Required handoff evidence: 结构化摘要 + 文件路径引用（原始 diff/日志走文件与 handoff，不进主会话上下文）

## Acceptance Authority

Round acceptance: main session（claude-fable-5）

Failed review escalation: 仅用户

Blocked state unblock requirement: human-decision-required / access-missing / write-safety-required 且下一安全动作需用户输入时停止，等待用户输入解除

Recoverable blocker auto-round policy: runtime-recoverable 与 contract-insufficient 可自恢复（后者限契约修复动作）；read-only 调查轮自动开启
