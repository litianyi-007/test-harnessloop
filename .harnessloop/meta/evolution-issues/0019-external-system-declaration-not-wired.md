# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0019
- Priority: P1
- Issue class: missing-capability
- Status: resolved (v0.34.0)
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**外部系统声明与执行层之间没有桥**：`setup/data-sources.md` 的 Runtime Validation Systems / External Tools 两表是自由文本，无任何代码解析其内容。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: TH-0021（本条是其载体前置）
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

项目声明一个外部系统（endpoint、探活方法、测试资源边界、清理契约、凭证参数名）后，loop 应能据此机械探活、绑定本机地址、并在不可用时给出结构化 `unavailable` 事实。

## Actual Harnessloop Behavior

`data-sources-template.md:16-24` 两表全自由文本；`check_setup.py` 只查填充度；`init_project.py` 只落模板；`verify_protocol.py` 仅在 docstring 里把它当 PATHISH 前缀示例（:48、:2787）。`channels`/`connectivity` 在协议层要求 agent 读它，但同样无表格解析器。setup SKILL 明文把 data-sources 排除在 gate-blocking 之外。

## Minimal Reproduction From Files

1. Read `.harnessloop/setup/data-sources.md`
2. `grep -rn 'data-sources' harnessloop/plugins/harnessloop/skills/*/scripts/` → 仅 check_setup / init_project / verify_protocol docstring
3. 观察：无任何代码读取表格单元格

## Proposed Direction

独立 versioned JSON 声明 + gitignored 本机绑定（**控制面**仿 reference-roots：声明/绑定分离、每门重判 available、fail-closed、coverage 可见、不泄本机路径）；**探针执行器全新建**（method/timeout/TLS/鉴权/重试/副作用等级），不复用 `_exists_as`/`samefile`。不做全局 gate_blocking，改为「active due eval 绑定的系统未声明/不可用 → 违规」的条件阻塞；data-sources 表降为人读视图。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。


---

## 处置结果（2026-07-29，harnessloop v0.34.0，CI 三平台全绿）

**需求链第一环已落地。** `.harnessloop/setup/external-systems.json`（今天层、版本化、进 git）
+ `evals.json` 的可选 `system` 字段 + 今天层引用完整性判定 `rae-system-undeclared`。
两个操作数都是今天层文件，**不挂任何轮**——今天删掉声明文件不会追溯判红任何轮。

### 安全设计：不是加检测，是不留那个面

批 1 的对抗评审曾证伪过一条同类 teeth——某设计声称「版本化声明在构造上装不下 endpoint」，
**实际是假的**：它留了个 `probe.path`，写 `"//evil.example.com/api/status"` 就能在标准 URL
拼接下把主机整个换掉，且 bearer token 会被发到那个主机。

本设计的 schema 里**没有任何 URL / 主机 / 路径形状的字段**，只有 `id` / `kind` /
`description` / `params`（**参数名**列表，须匹配 `^[A-Z][A-Z0-9_]{0,63}$`）。
该正则天然排除 `/` `:` `.`，**URL 塞不进参数名位置**。已实测：
`params: ["https://evil.example.com/x"]` → 整份文件作废。

### 刻意不做（记录，免得后来者当成遗漏）

- **不建 local binding 文件**：门不需要它；跑 eval 的 runner 需要，但那不在门的职责里。
- **不给 ledger 加 `frozen_system`**：目前**没有任何轮层判定会用它**。加一个没人用的字段
  正是本项目栽过三次的「宣布性质但无实现承载」（`attempt_id`「格式层即不可能」/
  v4「捕获点在写入时刻」/ X10）。**等有判定用它时再加。**
- 门不发网络请求、不做探活；声明文件缺席 = 零行为，不做 gate_blocking。

### 上界（已进 SKILL.md OUT 列）

`description` 是本文件**唯一的自由文本面**，门**不检查它是否含凭证**——**刻意不加正则检测，
那种检测必然既漏又误**；凭证守门由项目自身的 secret 钩子承担（本仓有
`scripts/check-secrets.sh` + pre-commit + CI，**插件本身没有**，见 TH-0025）。
门只核对 id 引用完整性，不核对该系统是否真实存在、可达、或与描述相符。

### 需求链现状

| 环 | 状态 |
|---|---|
| ① 声明外部系统 | **✅ v0.34.0** |
| ② eval 绑定到系统 | **✅ v0.34.0** |
| ③ eval 真的跑过 | **仍不存在**——账本里 `outcome: "pass"` 仍是纯自述 |
| ④ 结果入账 | ✅ v0.27.0 |
| ⑤ 到期未过 ⇒ 不得 positive | ✅ v0.27.0 |
| ⑥ 声明跑了却没账本 ⇒ 红 | ✅ v0.28.0 |

**③ 是剩下唯一必须的一环**：门**证明不了**某个 eval 真跑过（自签问题），但能要求账本条目
**引用一份 evidence 产物**，而 Rule B 已经会检查引用是否解析得到。这不证明跑过，但让
「跑过」这个声称**可引用、可被对抗评审质问**——正是 B2a `Review:` 已被接受的那个形状。
