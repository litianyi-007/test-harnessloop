# Data Contract

## Valid Evidence Sources

| 来源 | 说明 |
|---|---|
| 各插件的测试套输出 | `npm test`（hopper）、`npm run validate`（harnessloop）等，**须由主会话独立复跑** |
| 破坏性反证的**红**输出 | 拆掉修复后的实际失败输出，须留存原文 |
| `plugin-status.sh` / `plugin-reinstall.sh` 输出 | 证明安装缓存与 submodule 工作区一致 |
| **安装产物**的运行结果 | 从 `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` 直接调用得到的结果 |
| 真 vendor 的端到端产物 | `.hopper/handoffs/` 下的 output/raw/log |
| `verify_protocol.py --json` | harnessloop 自身的机械门 |
| `check-secrets.sh` 的**真实退出码** | 必须直接捕获，见下方「无效证据」 |

## Valid Tools And Systems

- 三个插件 submodule 及其 GitHub 远端（`litianyi-007/{harnessloop,hopper-plugin,kata}`）
- 本项目仓 `litianyi-007/test-harnessloop`
- hopper 已入选 vendor：**仅 codex 与 grok**（对抗/验收评审随机取一；研究以 grok 为主力）
- 隔离 openclaw 实例（scratchpad 下，`L1_ROOT` 指向 scratchpad）
- kata wiki：`~/.llm-wiki/test-harnessloop`（工程侧），**不与** `~/.llm-wiki/surebeli-ip`（史官）混用

## Local Channel Parameter Requirements

- 凭证只存在于 gitignored 的 `.harnessloop/local/channel-params.json` 与各服务自己的 `.env`。
- **任务 brief 里绝不写真实凭证**，一律给参数名 + 「从环境变量/channel-params 读」。
- **但该纪律必要而不充分**：2026-08-12 实测，brief 完全合规而凭证仍进了 vendor 输出——
  vendor 读了本地配置文件并原样回显。**handoff 入库前必须实跑 `--staged` 扫描。**

## Invalid Evidence

**以下一律不作为达成证据：**

- **`exit 0` / `status: done` / 「Task completed successfully.」** —— 本项目的原始缺陷
  正是三者全亮而任务没送到。
- **实现方自述的测试结果** —— 未经主会话复跑的不采信。
- **管道后的退出码** —— `cmd | tail` 的 `$?` 是 `tail` 的。判退出码必须直接捕获：
  `cmd > /tmp/out 2>&1; EC=$?`。（同日栽过一次，差点把「拦截」读成「通过」。）
- **裸 `grep -r` 的空结果** —— 本环境的 `grep` 是 ugrep 包装，带 `--ignore-files`
  会**静默跳过 gitignored 文件**、`-I` 跳过二进制。安全性搜索一律用
  `command grep` / `git grep` / `git log -S`。（同日实测：函数版 0 处 vs `command grep` 23 处。）
- **未先看到红的破坏性反证** —— 没红过就不知道它在测什么。
- **仅 submodule 工作区的验证** —— 不等于安装产物可用。

## Secret Handling

- 本仓 **PUBLIC**。凭证一旦进历史，轮换 + `filter-repo` 重写是唯一补救。
- 新 clone / 换机器后必须先装 pre-commit 钩子（`.git/hooks` 不版本化，装法见 `CLAUDE.md`）。
- 轮换任何凭证后重跑 `./scripts/check-secrets.sh --update-digests`。
- **隔离实例会把凭证落盘**，拆除后无人清理，副本随轮次线性累积——**已登记为 TH-0032，未修**。
  在它修好之前，每轮收尾须人工确认隔离实例的凭证残留已清。

## Revision Policy

- 本文件的「无效证据」清单**只增不减**：每次因测量方式出错而误判，把那种方式加进来。
  这份清单的价值正在于它是**踩出来的**，不是设计出来的。
- 证据来源变更须记入 `state/evidence-index.md`。
