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

注：本机 python3 = 3.9.4（pyenv），为本 goal 所有新增 python 代码的兼容性下限约束。

## External Tools And Platforms

| Tool/platform | Purpose | Read/write scope | Account role | Verification method | Failure handling | Local parameter keys |
| --- | --- | --- | --- | --- | --- | --- |
| GitHub（litianyi-007/harnessloop 与 litianyi-007/test-harnessloop）(user-confirmed) | 插件上游发布与项目备份，批次验收后 push 为既定授权流程 (user-confirmed) | push main（读写）(user-confirmed) | litianyi-007（凭证走本机 git credential helper，绝不写入 harnessloop 文件）(user-confirmed) | git ls-remote 与 push 回执 (user-confirmed) | push 失败人工介入 (user-confirmed) | 无（无需 channel-params 键） |
| hopper 第三方 agent 分发（本地 hopper CLI → 入选 vendor 仅 **codex + grok**；其余注册 vendor CLI 如 kimi/opencode/copilot/agy/mimo/claude 未入选，暂不路由） | 委派任务到第三方 agents：**codex** = 对抗/验收评审随机池成员 + 研究备选；**grok** = 对抗/验收评审随机池成员 + 研究主力；**实现类（写代码）禁止派发第三方 vendor**，一律由主会话 claude-sonnet-5 子代理承担 | 按任务而定（评审=只读；研究=只读+web-search） | vendor 凭证由各 CLI 自管，绝不入 harnessloop 文件 | hopper:setup 就绪表 + hopper:smoke | hopper:result/progress 排查后人工介入 | 无 (user-confirmed 2026-07-17) |
| kata `wiki-sync` 技能的 git remote push/pull（读 kata/README.md 确认存在：`/kata:wiki-sync` 对**独立的** wiki 备份仓——默认 `~/.llm-wiki/<project>`，非本仓——做 git push/pull/merge，需用户先 `wiki-init --enable-sync` 并手动 `git remote add origin`）(user-confirmed 2026-07-17) | 多机 wiki 同步（本项目未配置：未见 `--enable-sync` 或已设置的 wiki remote，此能力当前处于未启用/休眠状态）(user-confirmed 2026-07-17) | 读写该 wiki 备份仓 git remote（与本仓 `litianyi-007/test-harnessloop` 及插件仓无关，用户自行指定）(user-confirmed 2026-07-17) | 用户自有 git remote 凭证（走本机 git credential helper，绝不入 harnessloop 文件）(user-confirmed 2026-07-17) | `/kata:wiki-sync --dry-run` 预览 + push/pull 回执；内建 force-push 检测与 wiki_id identity 校验 (user-confirmed 2026-07-17) | 冲突/force-push 检测触发后人工介入 (user-confirmed 2026-07-17) | 无（本项目未配置，无需 channel-params 键）(user-confirmed 2026-07-17) |

注：以上 GitHub 条目来源 = setup wizard live 首跑 2026-07-16（用户确认）。

## Local Channel Parameters

Store reusable channel parameter keys in `.harnessloop/local/channel-params.json`, which must be ignored by `.harnessloop/local/.gitignore`.

| Channel ID | Parameter key | Sensitivity | Storage | Reference | Required for | Status |
| --- | --- | --- | --- | --- | --- | --- |

本 goal 无外部凭证需求：`.harnessloop/local/channel-params.example.json` 存在，无需填入真实参数。

## Secret Handling

Do not write secret values here. Record only secret names, storage locations, required scopes, and verification commands.
