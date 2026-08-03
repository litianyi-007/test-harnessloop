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
- Irreversible or external-system write: 需用户（例外：git push 到 litianyi-007/harnessloop、litianyi-007/test-harnessloop、litianyi-007/hopper-plugin 与 litianyi-007/kata 四仓在批次验收通过后为既定授权流程，无需逐次确认；三个插件（harnessloop / hopper-plugin / kata）push 前均须同步 bump 版本信息，保持各自版本文件一致后才能 push——harnessloop 的版本 bump 已是既有发布惯例；hopper-plugin 版本文件以仓库实际布局为准：.claude-plugin/marketplace.json、package.json 及 CLI 版本串等全部一致；kata 版本文件为 plugin/.claude-plugin/plugin.json、.claude-plugin/marketplace.json、CHANGELOG.md，同样须全部一致；未 bump 版本不得 push（用户条件 2026-07-17）） (user-confirmed 2026-07-17：定位与既有两插件相同)

## Pre-Authorized Test-Resource Writes

TH-0022 用户裁决 ③ 的唯一合法落点。此表**只能收窄**，不能放宽上面
`Human Confirmation Required` 的 `Irreversible or external-system write` 那一行：
生产系统与不可逆操作在任何情况下都不具备预授权资格，无论此表写了什么。

**2026-08-03 更正**：本条最初被写成 `Human Confirmation Required` 下的一个 bullet
（「不需要逐次确认」写在「Required for:」清单里，语义正好是反的），且当时
`setup/external-systems.json` 尚不存在、无 System id 可引。机械门对此全绿
（verify_protocol exit 0 / 0 violations）——契约在语义上是坏的但机械上合规，
是插件自身文档承认的那类边界。用户裁决的**实质未变**，此处只是改成合法形状。

| System id | Operation class | Resource scope | Cleanup contract | Authorized by |
| --- | --- | --- | --- | --- |
| `newapi` | `test-resource-create` | 仅名称带 `test`/`sg`/`eval` 前缀的 token 与 channel；**不含**管理员账号、系统设置、既有生产 token | 本轮结束时列出该前缀下的资源并记入 evidence；**删除不在预授权内**（见下） | user-confirmed 2026-08-03 |
| `openclaw-isolated` | `test-resource-create` | 仅 `OPENCLAW_STATE_DIR` 指向的隔离目录与 `OPENCLAW_GATEWAY_PORT` 指定端口上的实例；**不得**触碰用户环境中既有的 openclaw 状态目录或 gateway | 轮次结束时停进程、并以 `git status --ignored` 证明 submodule 工作区为空 | user-confirmed 2026-08-03 |
| `hermes-isolated` | `test-resource-create` | 仅 `HERMES_HOME` 指向的隔离目录与 `API_SERVER_PORT` 指定端口上的实例 | 同上 | user-confirmed 2026-08-03 |
| `d3proxy` | `test-resource-create` | 仅本机 `D3PROXY_LOCAL_PORT` 上的实例与其 gitignored `.env` | 轮次结束时停进程 | user-confirmed 2026-08-03 |

**边界（超出即回落 `write-safety-required`，仍需用户）：**

- **删除与覆盖不在预授权内。** 上表 `Operation class` 一律是 `test-resource-create`；
  没有任何一行是 `test-resource-delete` 或 `cleanup`。清理既有资源仍需用户确认。
- `raspberry-pi-deploy` **不在表内**——它承载 newapi 生产实例，属宿主机写入，不具备预授权资格。
- 触发第三方计费的写入（真实 LLM 调用）不在此列，按既有成本纪律另议。
- 表中未列的 System id 一律无预授权，即使它已在 `external-systems.json` 里声明。

**为什么要这条**：runtime 验收 eval 必须真把外部系统跑起来才有意义，而建测试资源是其前置。
逐次确认会让「自主推进到 goal 完成」在每个 eval 前中断一次——正是本项目「补充 runtime/
多系统测试作为 evals」那条需求要解决的问题。预授权换来自主度，代价是「是否测试资源」
这个判断由主会话自己做，所以 `Resource scope` 逐行写死，越界即回落。

## Stop Conditions

Stop when:

- Blocking condition: human-decision-required / access-missing / write-safety-required 且下一安全动作需用户输入时
- Blocker type: 见下方 Blocker Classification（协议 7 类）
- Missing evidence: TODO (owner: user)
- Environment mismatch: **停下来报告，不自动继续**（user-confirmed 2026-08-04）——当
  `state/environment.md` 的 `Expected model` / `Expected effort/reasoning` 与本会话实际
  不符时，主会话须在继续门输出里显式点出「声称 X / 实际 Y」，并停止，等用户裁决
  （改期望值 / 换回原模型 / 明确接受本次不符）。**不得自行把期望值改成实际值当作"已解决"**
  ——那是把不符消除在记录里而不是解决它。此前本字段为 TODO，2026-08-04 的
  AUDIT-20260804-PRECONTINUE-SG10 首次实际撞上不符（声称 claude-fable-5、实际
  claude-opus-5[1m]）时无规则可依，故补此条
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
