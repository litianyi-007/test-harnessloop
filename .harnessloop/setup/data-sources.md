# Data Sources

## Static Sources

| Source | Access method | Freshness requirement | Drift risk | Validation method | Credential requirement |
| --- | --- | --- | --- | --- | --- |
| docs/harnessloop-review-20260716.md + docs/harnessloop-review-20260716.findings.json | 本地文件读取 | 80 条确认发现的审查快照，冻结基线（2026-07-16），不刷新——被新一轮审查取代时整体作废 | 修复推进后条目逐渐过时 | 与 findings.json 的 JSON 结构比对 | 无 |
| harnessloop/ submodule 源码 @ git HEAD（当前 66093fd） | 本地文件读取（git 工作树） | 刷新 = git commit | 会话内已加载的 SKILL 文本钉在会话启动快照，落后于磁盘（2026-07-16 实测：重装后 Skill 工具仍返回修复前 loop SKILL 文本） | git log + scripts/plugin-status.sh 内容级 diff | 无 |
| hopper-plugin/ submodule 源码 @ git HEAD（当前 eceee81） | 本地文件读取 | 刷新 = git commit | 与已装插件版本脱节（用 scripts/plugin-status.sh hopper 检测） | 内容级 diff | 无 (user-confirmed 2026-07-16) |
| kata/ submodule 源码 @ git HEAD（当前 1a120d4，v2.15.2） | 本地文件读取（git 工作树） | 刷新 = git commit | 与已装插件版本脱节（用 scripts/plugin-status.sh kata 检测） | git log + scripts/plugin-status.sh 内容级 diff | 无 (user-confirmed 2026-07-17：定位与既有两插件相同) |
| harnessloop/adversarial-review-p0.md 等作者自评文档 | 本地文件读取 | 基线 v0.9.0，已知落后当前版本，仅作历史对照 | 落后当前版本，不代表当前状态 | TODO (owner: user) | 无 |
| harnessloop/examples/mock-project/ | 本地文件读取 | 已知系统性落后模板 12+ 处（审查发现） | 禁止作为格式权威，模板目录 references/ 才是权威 | TODO (owner: user) | 无 |

## Dynamic Or Generated Sources

| Source | Generator/tool | Refresh expectation | Drift risk | Validation method | Credential requirement |
| --- | --- | --- | --- | --- | --- |
| npm run validate 输出 | npm run validate（harnessloop 仓库根运行） | 每次运行重新生成 | TODO (owner: user) | 全部阶段全绿（当前 8 阶段） | 无 (user-confirmed 2026-07-16, threshold revision per control contract) |
| scripts/plugin-status.sh 输出 | scripts/plugin-status.sh | TODO (owner: user) | TODO (owner: user) | 安装状态与内容级比对 | 无 |
| wizard 模拟运行 transcript（本 goal 的产物） | 脚本化 dry-run | 本 goal 的产物 | TODO (owner: user) | TODO (owner: user) | 无 |

## Runtime Validation Systems

| System | Access method | Validation method | Pass condition | Failure handling | Credential requirement | Local parameter reference |
| --- | --- | --- | --- | --- | --- | --- |
| npm run validate（cwd=harnessloop/，8 阶段） | 本地命令 | 全部阶段全绿（当前 8 阶段） | pass=exit 0 全绿 | 定位失败阶段修复后重跑 | 无 | 无 (user-confirmed 2026-07-16, threshold revision per control contract) |
| python3 <plugin-cache>/skills/harnessloop-loop/scripts/verify_protocol.py --project 本项目 | 本地命令 | 机械协议门 | pass=exit 0 | TODO (owner: user) | 无 | 无 |
| scripts/plugin-reinstall.sh（重装回路） | 本地命令 | 内容比对 | pass=内容比对一致 | TODO (owner: user) | 无 | 无 |
| `openclaw-isolated`（RAE-0001 绑定的外部系统；见 `setup/external-systems.json`） | 按 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 起隔离实例：独立 `OPENCLAW_STATE_DIR` + 独立 `OPENCLAW_GATEWAY_PORT` + `OPENCLAW_SKIP_CHANNELS`，**不触碰用户环境中既有的 openclaw 状态目录与 gateway** | SG-10 L1 的 UI 壳对该实例发起一次真实会话往返（新建会话 → 发送 → 收到消息流），取 app 侧 e2e 日志 + 实例侧日志两路对照 **四条全部成立才算 pass，缺一即 fail**（user-confirmed 2026-08-05，定于 rounds/0011 scope-lock，即当初约定的「首轮」）：①**真实往返可见**——UI 里渲染出 assistant 回复（**L1：截图 + wire trace 即可；录屏不作要求**——user-confirmed 2026-08-09 修订，理由见下方注）；②**隔离性可证**——全程未触碰用户环境既有 openclaw 状态目录与 gateway，前后比对留证；③**事件序列与契约一致**（**2026-08-10 user-confirmed 修订**，原文为「无丢帧、无乱序」）——**(a) 不乱序**：D2 `seq` 与 wire `messageSeq` 均不倒退，由断言而非肉眼判定；**(b) 受控会话内无缺失**：把收到的 assistant `session.message` 的 `(messageId, messageSeq)` 与运行结束后的**权威 history 快照对账**，确认预期消息全部出现；**(c) 破坏性反证**：从 wire 集合中删除一条 assistant 消息后，对账**必须变红**；**(d) 已知缺口**：协议级、任意连接生命周期的「无丢帧」保证**列为内核已知缺口，不在本层验收**。修订理由与三方依据见下方 2026-08-10 注；④**失败可诊断**——失败时日志足以定位到 UI / kernel-client / gateway 哪一层。④ 以主动注入失败反证，不以「没坏过」充当证据。UI 验收方法同轮定为**分层**：逻辑层自动化断言 + UI 层录屏/截图人工验收，不建 XCUITest（详见 `goals/20260718-002-agent-app/rounds/0011/scope-lock.md`） | 失败时不重试、不换实例；停下来把失败态（进程状态/端口/实例日志尾部）记进本轮 evidence，按 blocker 分类处理 | 无（隔离实例不需要凭证；`OPENCLAW_GATEWAY_TOKEN` 是本地自生成的进程内令牌，不是外部账号凭证） | `OPENCLAW_GATEWAY_PORT` / `OPENCLAW_GATEWAY_TOKEN` / `OPENCLAW_STATE_DIR` / `OPENCLAW_SKIP_CHANNELS`（参数**名**见 `setup/external-systems.json`；值不入库） |

注：本机 python3 = 3.9.4（pyenv），为本 goal 所有新增 python 代码的兼容性下限约束。

注（2026-08-04）：上表前三行是 **harnessloop 自身工具链**的校验命令，与 `setup/external-systems.json` 里声明的 5 个外部系统是两回事。本次补入 `openclaw-isolated` 一行，因为 RAE-0001 已绑定它；其余四个系统（`newapi` / `raspberry-pi-deploy` / `d3proxy` / `hermes-isolated`）**尚无对应 eval，故本表暂不为它们预写验证方法**——等各自的 eval 真被登记时再补，避免写下没有 eval 消费的条目。

## External Tools And Platforms

| Tool/platform | Purpose | Read/write scope | Account role | Verification method | Failure handling | Local parameter keys |
| --- | --- | --- | --- | --- | --- | --- |
| GitHub（litianyi-007/harnessloop 与 litianyi-007/test-harnessloop）(user-confirmed) | 插件上游发布与项目备份，批次验收后 push 为既定授权流程 (user-confirmed) | push main（读写）(user-confirmed) | litianyi-007（凭证走本机 git credential helper，绝不写入 harnessloop 文件）(user-confirmed) | git ls-remote 与 push 回执 (user-confirmed) | push 失败人工介入 (user-confirmed) | 无（无需 channel-params 键） |
| hopper 第三方 agent 分发（本地 hopper CLI → 入选 vendor 仅 **codex + grok**；其余注册 vendor CLI 如 kimi/opencode/copilot/agy/mimo/claude 未入选，暂不路由） | 委派任务到第三方 agents：**codex** = 对抗/验收评审随机池成员 + 研究备选；**grok** = 对抗/验收评审随机池成员 + 研究主力；**实现类（写代码）禁止派发第三方 vendor**，一律由主会话 claude-sonnet-5 子代理承担 | 按任务而定（评审=只读；研究=只读+web-search） | vendor 凭证由各 CLI 自管，绝不入 harnessloop 文件 | hopper:setup 就绪表 + hopper:smoke | hopper:result/progress 排查后人工介入 | 无 (user-confirmed 2026-07-17) |
| kata `wiki-sync` 技能的 git remote push/pull（读 kata/README.md 确认存在：`/kata:wiki-sync` 对**独立的** wiki 备份仓——默认 `~/.llm-wiki/<project>`，非本仓——做 git push/pull/merge，需用户先 `wiki-init --enable-sync` 并手动 `git remote add origin`）(user-confirmed 2026-07-17) | 多机 wiki 同步（本项目未配置：未见 `--enable-sync` 或已设置的 wiki remote，此能力当前处于未启用/休眠状态）(user-confirmed 2026-07-17) | 读写该 wiki 备份仓 git remote（与本仓 `litianyi-007/test-harnessloop` 及插件仓无关，用户自行指定）(user-confirmed 2026-07-17) | 用户自有 git remote 凭证（走本机 git credential helper，绝不入 harnessloop 文件）(user-confirmed 2026-07-17) | `/kata:wiki-sync --dry-run` 预览 + push/pull 回执；内建 force-push 检测与 wiki_id identity 校验 (user-confirmed 2026-07-17) | 冲突/force-push 检测触发后人工介入 (user-confirmed 2026-07-17) | 无（本项目未配置，无需 channel-params 键）(user-confirmed 2026-07-17) |

注：以上 GitHub 条目来源 = setup wizard live 首跑 2026-07-16（用户确认）。

注（2026-08-10，**RAE-0001 条件③ 修订**，user-confirmed）：原文要求「无丢帧」，现改为「不乱序 + 受控会话内与 history 对账 + 破坏性反证 + 协议级保证列为已知缺口」。

**为什么改**：「无丢帧」在 kernel-client 这一层**结构上不可断言**——
- `session.message` 走 **targeted** 投递，而 `server-broadcast.ts:257` 显式写 `const eventSeq = isTargeted ? undefined : nextSeq`，**targeted 帧不带 `seq`**，官方客户端的 `onGap`（`protocol-client.d.ts:91`，给出 `expected`/`received`）对这条路径永不触发；
- 无订阅者时事件在 `server-session-events.ts:186-188` **直接 early-return，静默丢弃**，不排队不记录；
- wire `messageSeq` 是 **transcript 行号**（`:189-215` 回落 `readSessionMessageCountAsync`），未投递条目合法占号，缺口天然合法。

**为什么这个替代判据成立**：实时帧与 history 读取**携带同一套 `messageId/messageSeq` 元数据**（`server-session-events.ts:238-255` 与 `session-transcript-readers.ts:214-226`），因此可以对账。**这是一个真的缺失检测，且零协议改动。**

**为什么不去建投递序号**（hopper 双路异构讨论 T-088 codex / T-089 grok，两家独立结论一致）：
- 单加序号**只能检测 `dropIfSlow` 型丢弃，检测不到订阅注册前的 early-return 丢失**——后者要等 subscribe ACK 才能解决；
- 真正「不丢」需要 ACK + 背压 + 持久重放 + 重连恢复，远超本项目范围；
- **codex 的决定性理由**：「修改第三方内核后再据此验收，会把『验证 OpenClaw 适配』悄悄变成『验证定制 fork』」——直接违背本项目目的；
- 上游路径：openclaw `CONTRIBUTING.md:17-22` 明写新特性须先开 Issue 讨论且「**Most features are not accepted**」。若将来产品化需要，先开 issue 给最小复现，**不在本轮阻塞**。

**若将来真要建**（codex Q3，存档备用）：**不新增 payload 字段**，复用**已存在的可选协议字段** `EventFrame.seq`（`packages/gateway-protocol/src/schema/frames.ts:168`，`Type.Optional(Type.Integer)`）；作用域是 **connection incarnation**；且**必须配套修订阅竞态**（`send/stop` 等 subscribe RPC 成功响应而非仅等 dispatch），否则事件在注册前 early-return，**任何序号都无从占号**。

**不追溯**：rounds/0012 的 RAE-0001 **维持 `fail`**。条件修订只对**此后**的执行生效——不用改标准去追认已收盘的轮次。

注（2026-08-09，**RAE-0001 条件① 的取证方式修订**，user-confirmed）：原文要求「录屏可见」，现改为
**L1 用截图 + wire trace，录屏留给 L2**。

**为什么改**：`goal-breakdown.md` 定义 SG-10 时写的是「真实 app 运行**录屏/截图** + e2e 日志」——
**斜杠，二选一**。2026-08-05 主会话拟 AskUserQuestion 选项时写成「录屏 + 关键截图」，
**把二选一收紧成两者都要**；这个收紧是起草失误，既非经过论证的决定，也不是用户裁决或 goal-breakdown 原意。

**为什么二选一对 L1 够用**：L1 要证的是窗口渲染 / 会话列表 / 新建会话 / 消息流渲染 / 真实往返——
全是**终态事实**，截图足以承载；而 wire trace（JSON Lines，含精确 delta 文本、messageID、事件顺序与时间戳）
在严谨度上**强于录屏**，不是弱于。

**为什么 L2 必须录屏**：L2 的考察对象是**流式渲染**，那是时间行为——文字逐步流入还是一次性出现、
中间有无闪过坏状态，**静态截图原理上拍不到**。届时录屏承载不可替代的证据，定为硬要求。

**记一句不好看的**：本次修订发生在 rounds/0012 尝试录屏失败之后（macOS 屏幕录制权限未放行），
即**「没做到之后才提议放宽」**——正是 hopper T-081 评审专门警告过的模式。之所以仍然成立：
收紧本是起草失误、实交证据强于录屏、且走的是**显式改契约**而非验收时放宽解释。
如实登记这个时序，不粉饰。

注（2026-08-08）：**新增 `deepseek` 线路，替代已退订的 kimi 线路**（用户 2026-08-08 决策）。参数名见
`.harnessloop/local/channel-params.json` 的 `channels.deepseek`：`DEEPSEEK_API_KEY`（secret）/
`DEEPSEEK_BASE_URL` / `DEEPSEEK_DEFAULT_MODEL`。**值一律不入本文件**（本仓 PUBLIC）。

已实测坐实（2026-08-08 直连探针，未经 Pi）：

| 事实 | 值 | 来源 |
| --- | --- | --- |
| Endpoint | `POST <BASE>/chat/completions` | 官方文档 |
| 默认模型 | `deepseek-v4-flash`（文档另列 `deepseek-v4-pro`） | 用户指定 + 文档 |
| 鉴权 header | `Authorization: Bearer <key>` | **文档未写，实测坐实**（HTTP 200） |
| 响应形状 | **OpenAI 兼容**（`choices[0].message.content` + `usage`） | **文档未写，实测坐实** |
| 流式 | `"stream": true` → SSE，以 `data: [DONE]` 结尾 | 官方文档 |

**接法提示**：kimi 那条线在 new-api 里是 **type 14（Anthropic）**；deepseek 既然是 OpenAI 兼容形状，
**不应照搬该类型**，应建 OpenAI 类型的 channel。

**尚未做的**：Pi 侧 new-api 的 channel 仍是 `kimi-coding`。改它属**生产宿主写**
（`raspberry-pi-deploy` 被刻意排除在 `Pre-Authorized Test-Resource Writes` 之外）；
`newapi` 预授权行只覆盖「名称带 `test`/`sg`/`eval` 前缀的 token 与 channel 的**创建**」，
不覆盖修改既有生产 channel。**需用户授权后才能动。**

## Local Channel Parameters

Store reusable channel parameter keys in `.harnessloop/local/channel-params.json`, which must be ignored by `.harnessloop/local/.gitignore`.

| Channel ID | Parameter key | Sensitivity | Storage | Reference | Required for | Status |
| --- | --- | --- | --- | --- | --- | --- |

本 goal 无外部凭证需求：`.harnessloop/local/channel-params.example.json` 存在，无需填入真实参数。

## Secret Handling

Do not write secret values here. Record only secret names, storage locations, required scopes, and verification commands.
