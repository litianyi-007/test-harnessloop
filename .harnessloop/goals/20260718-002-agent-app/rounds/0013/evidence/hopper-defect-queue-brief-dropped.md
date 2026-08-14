# hopper 缺陷：queue.md 的 brief 在无 leader-tasklist 条目时被静默丢弃

**发现于**：rounds/0013 派 ★审查闸（T-090）时
**hopper 版本**：0.53.0（安装缓存 == submodule 工作区，已用 `plugin-status.sh` 确认）
**严重度**：高 —— 被派发的 vendor 收到一个**没有任务内容**的框架，却仍然 `exit 0` / `status: done`

## 症状

派 T-090 给 codex，44 秒后报 `done`、`exit_code: 0`。但 codex 的输出是：

> ## Open questions
> - What is the T-090 queue brief?
> - Which commit or working-tree diff should be reviewed?
>
> ## Verdict
> FAIL

## 根因

codex 实际收到的 prompt 里，`## Task spec` 段**只有一行占位符**：

```
## Task spec

(no detailed spec found for T-090 in leader-tasklist.md; using queue.md brief only)
```

**「using queue.md brief only」这句话是假的——brief 并没有被放进去。**

## 机械证据（不是靠读那一行字下的结论）

| 量 | 值 |
|---|---|
| `queue.md` 里 T-090 的 brief 长度 | **959 chars** |
| codex 实际收到的 prompt 段长度 | **2874 chars** |
| `--resolve T-090` 自报 composed prompt length | **2868 chars** |
| 若 brief 被包含，应约为 | **3833 chars** |
| `'RAE-0001' in prompt`（brief 特征串） | **False** |
| `'no detailed spec found' in prompt` | **True** |

`--resolve` 自己报的 composed 长度就等于「不含 brief」的长度 —— 说明**合成器在 compose 阶段就丢了 brief**，
不是传输截断。而 `--resolve` 的显示界面又**照常回显完整 Brief**，造成「看起来一切正常」的假象。

## 触发条件（对照组坐实）

| 任务 | `leader-tasklist.md` 中的条目数 | brief 是否到达 vendor |
|---|---|---|
| T-088 | 2 | ✅ 到达（prompt 中 `per-subscription` 命中 26 次） |
| T-089 | 2 | ✅ 到达 |
| **T-090** | **0** | ❌ **丢失** |

→ **仅当任务在 `leader-tasklist.md` 中没有详细 spec 时触发。** 有 spec 的路径正常，所以此前 89 个任务都没暴露它。

## 反证（确认不是环境问题）

同一 brief 改用 `--adhoc --brief "<text>"` 重派（T-090b）：
`Prompt: inline argv` 从 **3193B → 4753B**，brief 确实进入 prompt。
**同一 vendor、同一模型、同一 sandbox，唯一变量是走 queue 行还是走 adhoc。**

## 为什么这条特别值得记

`exit 0` + `status: done` + `Task completed successfully.` 三个信号全是绿的，
而实际上**任务内容根本没送到**。若不做 CLAUDE.md 规定的三项强制核对
（(a) 审查对象 (b) 产物落点 (c) 不得仅凭 exit 0 采信），这一轮会拿着一份
「codex 已评审通过」的假记录收盘。

**这正是那三条纪律存在的理由，本轮是它第一次真的救了场。**

## 处置

- **本轮不修**：`hopper-plugin/` 是三插件 submodule，scope-lock 明文禁止本轮改动。
- **待办**：在 hopper-plugin 内开 issue（建议文件名 `ISSUE-queue-brief-dropped-without-leader-tasklist.md`），
  并考虑两处修法：(1) 真的把 queue brief 拼进去；(2) 若确实拼不进去，占位符文案必须诚实说
  「brief 未包含」而不是「using queue.md brief only」——**静默的假陈述比缺失本身更危险**。
