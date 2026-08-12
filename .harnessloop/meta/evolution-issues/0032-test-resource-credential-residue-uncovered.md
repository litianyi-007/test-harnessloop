# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0032
- Priority: P2
- Issue class: template-gap
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（现场观测，2026-08-12 轮换 `SESSION_PROXY_STATIC_AUTH_KEY` 时）
- Created at: 2026-08-12

**隔离测试实例把凭证落盘到自己的 state 目录，拆除后无人清理，副本随轮次线性累积。**
现有的 `Cleanup contract` 覆盖不到这条：它只对**已声明的外部系统**生效，且它问的是
「你创建的资源删干净了吗」，不是「它在本地盘上留下了什么凭证」。

## Redaction Boundary

- Secrets removed: yes（全文只出现参数名与副本计数，无任何凭证值）
- Private data removed: n/a
- Raw logs omitted: yes（定位过程的原始输出未收录）
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Active round path: n/a（发现于轮次之外的凭证轮换作业）
- State files: `.harnessloop/state/control-contract.md`
- Related evidence: `docs/security-incident-20260726.md`（2026-07-26 泄漏事件）；
  本仓 commit `c4e6ca0`（补交 82 个 handoff，入库前被 L1-exact 拦下一次）
- Related evolution issues: **TH-0025**（evidence 自动写入无 secret 守门）——
  **相关但不重复**，见下方「与 TH-0025 的边界」
- 观测对象版本: harnessloop（`references/control-contract-template.md` 的
  `## Pre-Authorized Test-Resource Writes (optional)` 一节，TH-0022 引入）

## Expected Harnessloop Behavior

框架让项目声明「哪些 test-resource 写是被预授权的」时，也应让项目声明
**「拆除后本地盘上不允许残留什么」**——尤其是凭证。因为框架本身就在鼓励
「起隔离实例 → 收集证据 → 拆掉」这个循环，而隔离实例天然会把它的运行配置写到盘上。

## Actual Harnessloop Behavior

`control-contract-template.md` 的 `Pre-Authorized Test-Resource Writes` 表**确实有**
`Cleanup contract` 一列（模板原文：「states what must happen afterward (e.g. "delete
every resource this operation created, verified by listing the scope empty
afterward")」）。缺口不在「没有清理概念」，而在**两处覆盖边界**：

1. **只对已声明的外部系统生效。** 该表的 `System id` 必须匹配
   `.harnessloop/setup/external-systems.json` 里已声明的 id。一个在本机 scratchpad
   下起的隔离进程不是「外部系统」，于是这张表**根本不会被填**，`Cleanup contract`
   也就永远不附着到它身上。
2. **它问的是「资源」不是「残留」。** 示例语义是「把你创建的资源删干净并验证 scope
   为空」。隔离实例被删掉之后，**它写到本地盘上的凭证副本仍在**——那不是它「创建的
   资源」，是它运行时的落盘副产物。

同时**没有机械门**：`verify_protocol.py` 不检查任何已声明的 `Cleanup contract`
是否真的被兑现。

## Minimal Reproduction From Files

2026-08-12 轮换 `SESSION_PROXY_STATIC_AUTH_KEY`（d3proxy channel，openclaw→D3-proxy
的入站门禁）时，对该值做全仓比对：

| 位置 | 副本数 |
|---|---|
| `app/server/.env`（真正的配置落点） | 1 |
| `.harnessloop/local/channel-params.json`（登记表） | 1 |
| **`scratchpad/round001{1,2}-*/state/` 下的隔离实例** | **21** |

那 21 处形态固定：每个实例 3 份（`openclaw.json`、`openclaw.json.last-good`、
`agents/main/agent/models.json`）× 7 个实例。

**同一模式复现在另一把凭证上**：`DEEPSEEK_API_KEY`（真模型线路凭证）另有 4 份副本，
在 `scratchpad/round0012-*/state/agents/main/agent/plugins/deepseek/catalog.json`。

合计 **25 份凭证副本，全部由隔离实例自身写出，无一被任何收尾步骤清理**。

**这不是一次性失误，是结构性且会持续复发的**：每起一个隔离实例，凭证就多一份落盘
副本，而这些实例按轮次不断新建。副本数随轮次线性增长。

## Attempted Local Mitigation

- Evidence refresh: n/a
- Scope narrowing: n/a
- Contract revision: 未做（本 issue 即为此而开）
- Handoff change: n/a
- Rollback: n/a
- Human confirmation: 用户 2026-08-12 裁定轮换该凭证并删除 25 份副本；已执行，
  复验旧值在工作区与 git 全历史（四仓）均为 0

**现有防线的边界（实测）**：`.gitignore` + pre-commit 的 `check-secrets.sh` 守住了
「不进版本库」——`git log -S` 四仓全历史 0 命中，**这条线是有效的**。但它
**完全没有守「不无限扩散副本」**。两者是不同的威胁面：前者防泄漏到公开历史，
后者防本机上凭证副本面持续扩大。副本越多，任何一次误操作（打包、同步、备份、
换机器 rsync）的暴露面越大。

## 与 TH-0025 的边界（不要合并）

| | TH-0025 | 本条 TH-0032 |
|---|---|---|
| 侧面 | evidence **写入**侧 | test-resource **生命周期收尾**侧 |
| 问题 | 自动写入的 evidence 无插件层 secret 守门 | 隔离实例的凭证落盘无清理纪律 |
| 触发 | 框架写文件时 | 框架拆实例后 |

两者都属 security 族，但修法完全不同，合并会让任一条都无法收敛。

## Suggested Upstream Improvement

- Candidate target: **template**（优先），必要时加一条 validation script 断言
- Proposed smallest change：在 `control-contract-template.md` 的
  `Pre-Authorized Test-Resource Writes` 一节增加**一句说明 + 一列或一个声明位**，
  把「残留」与「资源」分开问：
  - 明确 `Cleanup contract` 除了「删除创建的资源」外，还须声明
    **「拆除后本地文件系统上不允许残留哪些凭证/敏感值，以及如何验证」**；
  - 并说明**本地隔离实例即使不在 `external-systems.json` 里，也应在此声明**——
    或者显式给出另一个落地位置。当前的 `System id` 必须匹配已声明外部系统这条
    硬约束，是本地实例被漏掉的直接原因。
- Why this generalizes beyond this project：**任何**用「起隔离实例 → 收证据 → 拆掉」
  循环的项目都会遇到——实例要能跑就得拿到凭证，拿到就会写盘。openclaw 只是本项目
  的载体，不是问题的来源。
- Risks of overfitting：不要把 openclaw 的具体路径形状（`state/openclaw.json` 等）
  写进模板；模板只该问「你的隔离实例会把凭证写到哪、拆完怎么验证它没了」，
  具体答案由项目填。

## 诚实标注

- **本条的具体载体是本项目自己的 openclaw 隔离实例脚本，不是 harnessloop 插件代码。**
  缺口在框架的 test-resource 纪律没有覆盖 teardown 的「残留」这一侧。
- **开 issue 前我的前提是错的**：起初认为模板「没有拆除时的清理条款」。实际读模板
  第 51 行发现 `Cleanup contract` 列早已存在。真实缺口比原判**更窄**——是覆盖边界
  与语义，不是缺失。此处如实留痕。
- **审计有未覆盖面**：`PI_SSH_KEY` 与 `NEWAPI_ADMIN_TOKEN` 是非内联值（一个指向
  `~/.ssh/` 下的文件、一个是对象结构），本次无法用值比对。这两条属
  **「未验证」而非「已验证安全」**。

## Resolution

- Resolution status: open
- Upstream change: 未提出
- Backported to local policy: no
- Backport path: 待定——若上游接受模板改动，本项目须在
  `.harnessloop/state/control-contract.md` 补填对应声明位，并考虑在
  `scripts/stop-isolated-kernel.sh` 增加一步凭证落盘清理并留证
- Follow-up required: yes
