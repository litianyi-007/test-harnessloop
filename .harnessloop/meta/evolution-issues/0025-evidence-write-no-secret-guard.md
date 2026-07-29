# Harnessloop Evolution Issue

## Summary

- Issue ID: TH-0025
- Priority: P2
- Issue class: security
- Status: open
- Source project: test-harnessloop (/Users/litianyi/Documents/Code/_ai-goods/test-harnessloop)
- Created by: 主会话（main-session ruling under user delegation 2026-07-28（附录 B 授权；非 user-confirmed，用户可推翻））
- Created at: 2026-07-28

**evidence 自动写入无插件层 secret 守门**——自主化 runtime evals 会放大已发生过事故的那条链。

## Redaction Boundary

- Secrets removed: n/a
- Private data removed: n/a
- Raw logs omitted: n/a
- Safe evidence summaries only: yes

## Context

- Active goal path: n/a（协议级，非单一 goal 绑定）
- Related evidence: `docs/harnessloop-runtime-evals-autonomy-audit-20260728.md`（审核 + 附录 C 裁决）、`.hopper/handoffs/T-074-output.md`（grok）、`.hopper/handoffs/T-075-output.md`（codex）
- Related evolution issues: 无
- 审核对象版本: harnessloop v0.26.0（`b389eac`）

## Expected Harnessloop Behavior

harnessloop 自身应对 evidence 写入提供最低限度的凭证守门或显式告警，使换一个项目使用时该防线仍在。

## Actual Harnessloop Behavior

`docs/security-incident-20260726.md` §2：泄漏路径正是「探针子代理把真实运行配置原样写进 evidence → vendor 原始日志回显 → public 仓」。插件树内无任何 secret 扫描/脱敏实现；本项目的三层守门是 test-harnessloop 仓的脚本（`scripts/check-secrets.sh`），不随插件走。**注**：事故档案 §7 建议 1 指向 hopper vendor 日志写端，与本条（harnessloop evidence 写端）相邻但不同链。

## Minimal Reproduction From Files

1. Read `docs/security-incident-20260726.md` §2
2. `grep -ril 'secret\|redact' harnessloop/plugins/` → 无扫描器实现
3. 观察：`scripts/check-secrets.sh` 在被测项目仓内，非插件能力

## Proposed Direction

最低限度：setup 自检对「未装 evidence secret 守门」给显式 warning。进一步：evidence 写入纪律进协议 + 机械抽查（对 channel-params 已登记值做 L1 摘要比对——摘要不含明文，本项目已验证该做法可行）。

## Status Notes

- 归属执行批次见审核报告附录 C.4。
- 本条由主会话受托裁决入册；实现前须按既定回路走规格 → 异构对抗审 → teeth → 破坏性反证。


---

## 处置进展（2026-07-29，harnessloop v0.36.0，CI 三平台全绿）—— **保持 open**

### 裁决：不加任何扫描器

三条思路（声明字段 / L1 摘要比对 / 改协议）各出设计、各过两重对抗核（安全剧场 / 误报代价），
**全部否决**。跨方案重复出现的发现收敛到一句结构性属性：

> **插件既不拥有这道门所需的数据，也不拥有时刻，更不拥有强制力。**

两条实证：

1. **数据不归插件所有。** 插件自己的 CLI 造不出一个「可扫描」的 store——实测新项目里
   `channel_params.py add` + `set --value-stdin`（均不传 `--sensitivity`）产出
   `{"sensitivity": "unknown", "value": "<明文>"}`。任何按 `sensitivity == "secret"` 选值的
   扫描器会零覆盖并报绿，**而明文 token 就躺在旁边**。这将是本项目**第二次**把「绿灯≠真守门」
   犯在安全功能上（第一次见 `docs/security-incident-20260726.md` §7：`check-secrets.sh`
   首版的 L1 在 CI 里空跑却照报通过，**而本次泄漏恰恰只有 L1 抓得住**）。
2. **形态扫描的误报代价已实测。** 事故后的五镜头普查产出 38 条原始信号 → **0 条真实风险**
   （`sk-` 多为 `task-`/`risk-` 子串；高熵串多为 git SHA / npm integrity / UUID；
   内网 IP 多为 semver）。而本项目已把 §4 异常层的极性定成保守/漏报，理由写在代码里：
   **误报造成告警疲劳，人开始盲目 ack，机制就废了**。

### 已做的：删掉插件自带的两句假保证

对抗核刨出一个**比本 issue 原标题更尖锐**的问题：插件被分发到**任意宿主项目**，
却在断言宿主仓有 secret 扫描钩子，并点名一个**只存在于 test-harnessloop** 的文件
（`find plugins -name 'check-secrets.sh'` → **0 命中**）：

- `SKILL.md:480`：「Secret-shaped text ... is **this repository's own secret-scanning hook's job**」
- `verify_protocol.py:2494`：「secret-shaped text is **this project's own `check-secrets.sh`'s job**」

**这两行是主会话自己写的**——`SKILL.md:480` 正是 v0.34.0 那次为「诚实登记门不做什么」而写的
OUT 列。**在写一条诚实边界的同时，顺手发布了一句关于「谁在做」的假声明。**
缺防线是没人守；假声明是让人**以为**有人守，更糟。

判据（比逐句清单干净）：**关于 Harnessloop 自己不做什么的第一人称陈述是自指规则，合法；
声称别的当事方正在守门的陈述，一律删。** 祈使句（`must verify:` / `Never write…`）**不动**
——给祈使句贴「无人检查」是负收益。

**G39** 用计算式期望集（`rglob("*.sh")` 实跑算出，当前为空）钉住不复发；红→绿→红→绿全程已验。

### 为什么保持 open

**该守门归宿主仓所有，插件侧只负责停止虚假声明。** 本条的原始诉求（插件层提供 evidence
凭证守门）经论证在插件层**不存在可承载的位置**，但风险本身没有消失——v0.35.0 起
runtime eval 的产物**必须**写进 `evidence/`，事故走过的链现在是机制强制要求的。
宿主项目必须自备仓库级钩子与 CI。

**可迁移的资产是 digest 生成器，不是扫描器**：`check-secrets.sh --update-digests` 产出
加盐 SHA-256 表、不含明文、CI 无本地 store 也能跑，且**完全不受 `sensitivity` 默认值影响**
（它作用于值，不作用于标签）。但它属于**宿主仓配方**，不是插件运行时——
**插件没有任何办法让人去跑它**，这一点必须写明，否则又是一次「宣布性质无实现承载」。

---

## 订正（2026-07-29，harnessloop v0.38.0 批次）—— 更正上面 §94 的「红→绿→红→绿」记录

**上面 v0.36.0 处置进展里写的「红→绿→红→绿全程已验」是不准确的，予以订正**：

实测重新核对：那次红→绿→红→绿测的是 `verify_protocol.py:2494`（含字面 `check-secrets.sh`
文件名）那一句，**不是** `SKILL.md:480` 的原句。`SKILL.md:480` 的原始假保证——
「Secret-shaped text ... is this repository's own secret-scanning hook's **job**」——
本身就**不含任何 `.sh` 文件名 token**（只说 "hook"，不点名 "check-secrets.sh"）。
G39 的 `sh_reference_pat` 只在文本里出现具体 `<name>.sh` token 时才会触发；这句话没有
这样的 token，所以从未、也不可能被 G39 的红→绿→红→绿实测覆盖到——commit message
里那句断言（暗示两处假保证都过了同一条红→绿→红→绿）夸大了实际验证范围。

同批（v0.38.0）另外发现并修了 G39 自身的三个问题（不属于这条订正，见 harnessloop
CHANGELOG / commit）：
- 对上面这个「不含 `.sh` token 的假保证」结构性看不见（本订正描述的这条）；
- 词表一绕就穿（`performed by` / `duty of` / `protects` / `enforced via` /
  `responsible for` / `takes care of` 六种改写均可绕过，仍 exit=0，**未修**——已在
  `scripts/validate.py` G39 注释里如实登记为已知上界，不继续加词表打补丁）；
- 一处真误报（`\bowns?\b` 撞上 "its own" 这类合法的第一人称自指否认——**已修**，
  收窄正则排除 "its/my/our/their/his/her/your own"）。

**结论**：G39 从这批起被重新定位为「只对孤儿 `.sh` 文件名做提示的弱检查」，不再声称
「防复发」；它对 `SKILL.md:480` 这一类不含具体文件名的散文假保证从未提供、也不可能
提供保护。


---

## G39 降级（v0.38.0，2026-07-30）

v0.36.0 加的 G39 被 13 对配对评审**实测证明双向错**：

- **看不见它本该防的原句**：SKILL.md:480 的原始假保证**不含任何 `.sh` token**，
  逐字塞回去 validate **全绿**；
- **词表一绕就穿**：六种指名孤儿 `check-secrets.sh` 的假保证（performed by / duty of /
  protects / enforced via / responsible for / takes care of）一次性塞进去仍 exit=0；
- **误报本条裁决明文判为合法的第一人称否认**：`Harnessloop does not ship its own
  check-secrets.sh` → 红（`\bowns?\b` 撞上 "its own"）。

**处置：只修误报，不加词表。** 对散文做**语义**检测，是本项目已判定不可机械化的那一类
（X10、本条自身的结论）。继续加词表就是在解析边界打补丁，**与 TH-0029 的停止线同族**。
G39 的真实覆盖面已如实改写为「孤儿 `.sh` 名 + 有限词表」，**不再声称防复发**。

**并更正 v0.36.0 的一条错误记录**：那次 commit message 写的「主会话独立把假保证塞回
SKILL.md 重新变红」——**塞回去测的是 `verify_protocol.py` 那句（含 `check-secrets.sh`），
不是 SKILL.md 那句原文**。原句不含 `.sh`，用那种方式根本测不到。
**当时的反证证明的东西，比当时声称的窄。**
