# Goal

## Goal

**通过真实使用，持续发现并修复三个自研插件的缺陷，直到它们不再静默失败。**

被测对象（三个独立仓，均为 git submodule）：

| 插件 | 仓 | 安装 id |
|---|---|---|
| harnessloop | `harnessloop/` → `litianyi-007/harnessloop` | `harnessloop@harnessloop` |
| hopper | `hopper-plugin/` → `litianyi-007/hopper-plugin` | `hopper@agent-hopper` |
| kata | `kata/` → `litianyi-007/kata` | `kata@kata` |

**验证方式是「边用边验」**：插件缺陷由真实使用暴露，不靠构造测试场景。goal 002
（agent-app）是使用现场，本 goal 是被验证的对象——`CLAUDE.md` 首行的定位
「**app 是手段，harnessloop 的迭代验证才是目的**」在此落为独立 goal。

**每条缺陷必须走完整闭环**：发现 → 改插件源码 → `plugin-reinstall.sh` 重装 →
用**安装的那一份**复验 → 记入 `docs/validation-log.md`。

### 为什么从 002 独立出来（2026-08-12，user-confirmed）

此前插件迭代**寄生在 app goal 的轮次里**：rounds/0013 三插件同轮受验、rounds/0017
整轮是 hopper 缺陷修复，都挂在 `20260718-002-agent-app` 下。**目的寄生在手段里**，
后果有三：

1. 插件轮的 scope-lock / decision 语义与 app 轮不同，却共用一套模板；
2. 插件迭代的进度无法独立看；
3. 「插件验证是否达成」没有独立的成功条件与阈值。

触发点是 rounds/0017 补 scope-lock 时留下的那条痕：「本轮是插件修复轮，挂在 app
goal 下并不贴切」。

## Non-Goals

- **不承担 app 功能开发** —— 那是 goal 002。本 goal 只在 app 开发过程**暴露出插件
  缺陷时**介入。
- **不追求插件功能扩张** —— 以缺陷修复与守卫加固为主。新功能需单独提案，不默认属本 goal。
- **不为提高数字而制造轮次** —— 没有真实使用暴露出的缺陷，就不开轮。空转的轮次比没有轮次更糟。
- **不接管三个插件的上游路线** —— 它们是独立仓，本 goal 只推本项目使用中发现的问题。

## Success Condition

**连续 N 轮真实使用中，不再出现「静默失败」类缺陷**（user-confirmed 2026-08-12）。

- **N = 5**（**user-confirmed 2026-08-12**）。调整属 goal 契约变更，须用户重新确认并在此注明理由。
- **「静默失败」的定义**：功能未达成，但所有可见信号都显示成功——退出码 0、状态
  `done`、日志无异常、守卫为绿。**判据是「有没有一个绿灯在说谎」，不是「有没有 bug」。**
- **计数从 2026-08-12 之后开的轮次起算**，本 goal 建立前的轮次不计入连续段。
- **任一轮出现该类缺陷，连续计数归零**，并在 `goal-breakdown.md` 记明归零原因。

### 为什么不用「清零 open issue」

issue 数量受「有没有人去登记」影响——hopper 的 open 数今天从 6 涨到 10，**恰恰是因为
排查得更仔细**。把它当验收线会**鼓励少登记**，与本 goal 的目的相反。

### 为什么不用「探索式不设终点」

与 002 的探索性质不同：插件缺陷是**可判定**的（要么静默失败，要么不），不设终点会让
「什么时候算完」永远悬空。

## Acceptance Criteria

每一条插件修复要被接受，须**全部**满足：

1. **破坏性反证，且先看到红** —— 把修复拆掉，对应测试必须变红并留下实际输出。
   **没红过的反证不算反证。**
2. **主会话独立复跑** —— 不采信实现方自述的测试结果；硬判据由主会话自己跑一遍。
3. **端到端判据** —— 单元测试证明不了「东西真的送出去了」。须有一条非单测的现场
   证据（真 vendor、真安装产物、真运行实例）。
4. **用安装的那一份复验** —— submodule 工作区跑通不等于装上去的那份跑通；
   `plugin-reinstall.sh` 之后用安装产物复验。
5. **push 前 bump 版本** —— 三插件各自的版本文件须一致，以各仓的发现式守卫为准，
   不以清单为准。
6. **异构评审** —— 按 `.hopper/AGENTS.md` 既定纪律；实现类绝不派第三方 vendor。
7. **记入 `docs/validation-log.md`** —— 闭环条目，含未修项与其原因。

## Required Human Decisions

**以下三项已全部裁定（user-confirmed 2026-08-12），本节暂无待决项。**

- ~~N 的取值~~ → **N = 5**，已确认。
- ~~本 goal 与 002 的优先级~~ → **插件优先**，已确认。含义：**本 goal 成为
  `Active goal`**，002（agent-app）在其 `rounds/0016` 收盘的干净点上**暂停（paused，非取消）**，
  其全部状态原样保留。app 侧工作在插件线达成阶段性目标、或用户另行裁定前不推进。
- ~~是否为某个插件 split 出独立 goal~~ → **三插件合一**，已确认。若某插件重到需要
  独立节奏，用 `$harnessloop-goal split` 拆出。

**后续新增的待决项写在这里。**

## Source Of Truth

- `CLAUDE.md` —— 项目定位、三插件迭代回路、版本文件清单、凭证守门纪律
- `docs/validation-log.md` —— 每一轮闭环的权威记录
- `.harnessloop/meta/evolution-issues/` —— harnessloop 自身的缺陷登记（TH-xxxx）
- `hopper-plugin/docs/archive/ISSUES.md` —— hopper 的缺陷登记
- `~/.llm-wiki/test-harnessloop` —— 跨轮可复用的内核/工具事实（kata 主场）
- 各插件仓的 CHANGELOG 与发现式守卫测试

### 前史（留在原处，本 goal 只交叉引用，user-confirmed 2026-08-12）

本 goal 建立前的插件相关轮次**不迁移**，避免打断已有大量引用（decision、
round-summary、validation-log、commit message 都指向它们；「保留可追溯」是协议明写的
安全规则）：

- `goals/20260718-002-agent-app/rounds/0013/` —— 三插件同轮受验
- `goals/20260718-002-agent-app/rounds/0017/` —— hopper brief-drop 修复（scope-lock 为事后补录）

## Status

- 状态：**active —— 本 goal 为当前 `Active goal`**（创建并接管于 2026-08-12，user-confirmed「插件优先」）
- 已开轮次：无
- 连续无静默失败轮数：**0 / 5**（自本 goal 建立起算）
- goal 002（agent-app）：**paused**，停在 `rounds/0016` 收盘的干净点（无在途轮次），状态原样保留
