# Thresholds

> **阶段标注**：本 goal 已进入**实现阶段（RA-L5 / IMPL）**（需求分析 RA-L1–L4 于 2026-07-22 收官签署，见 goal.md Status；2026-07-23 状态归位）。本文件验证口径按阶段区分——**需求分析阶段（RA-L1–L4）验证 = 用户逐级确认 + 各级规格自洽性检查**（历史口径，保留供审计）；**实现阶段（RA-L5 / IMPL）验证 = 静态编译/单测（build/jest/eslint/tsc/dotnet/swiftc）+ 对抗审级验收 + build+run 内核运行时探针/e2e（收编入 SG-8，见 goal-breakdown.md「SG-8 验收清单」）**。技术栈已定稿（D3=TypeScript+NestJS+PostgreSQL / D4 monorepo / D2 JSON Schema 2020-12 三端 codegen），下方 Verification/Runtime Thresholds 已回填 SG-1..SG-8 各行的命令/pass/fail/evidence path。

## Data Thresholds

| Threshold | Applies to | Required state | Freshness | Drift check | Evidence |
| --- | --- | --- | --- | --- | --- |
| 需求分析产出以用户确认留痕为准 | RA-L1–L4 各级展开文档 | 各级展开文档 + 对应用户确认记录（非会话内转述，须落盘） | 每级用户确认时冻结，不回改已确认级 | 与 `goal-breakdown.md` 各级状态字段（pending/confirmed）比对 | 各级展开文档路径 + AskUserQuestion 留痕 |
| RA-L3 设计研究以 hopper 产物文件为证据 | RA-L3 技术选型决策记录（goal.md Acceptance Criteria #3） | hopper dispatch 产物文件存在且非占位（非会话内转述） | RA-L3 轮次内新鲜产出，不复用旧研究 | 产物文件时间戳 vs RA-L3 轮次时间窗对比 | hopper 产物文件路径（`.hopper/` 下具体路径，RA-L3 执行时确定并回填本表） |
| 外部项目基线待确认 | openclaw / hermas / newapi / codex-app-sdk / claude-code-sdk 相关声称 | 不得凭记忆或训练知识臆造这些项目的能力、接口或版本；须以 RA-L3 调研产物为准（见 data-contract.md Invalid Evidence） | RA-L3 调研时确定，随外部项目自身版本变化需重新核实 | 调研产物 vs 实际项目文档/仓库比对 | RA-L3 调研文档（路径待 RA-L3 执行时回填） |

## Verification Thresholds

| Threshold | Applies to | Command/check | Pass condition | Fail condition | Evidence path |
| --- | --- | --- | --- | --- | --- |
| 需求分析阶段验证 | RA-L1–L4 全部 | 用户逐级确认门 + 各级规格自洽性走查（无跨级矛盾、TODO 均有明确 owner、无未标注的臆造能力声称） | 用户明确确认通过，且自洽性走查未发现未解决冲突 | 用户要求修改，或自洽性走查发现矛盾/遗漏/臆造声称 | 各级展开文档 + 用户确认记录 |
| 实现阶段静态验证（已回填，2026-07-23） | SG-1/SG-2/SG-3/SG-6 静态级交付 | `npm run gen`（codegen 幂等无 diff）+ `tsc --strict`（TS）+ codegen/verify（Swift `swiftc` / C# `dotnet build`）+ `npm run build` + `npm run test`（jest）+ `npm run lint`（eslint） | 相关命令全 exit 0、codegen 无 diff、判别联合三端保真 | 任一命令非 0、codegen 有 diff、或生成类型失真 | `app/contracts/d2/CODEGEN-FINDINGS.md` / `app/generated/` / `app/server/` 各命令输出（commit `0b4b79c`/`da95155`/`c69041e`） |
| SG-3 codegen 冒烟（增量，主体已随 SG-1 交付） | SG-3 剩余增量 | CI `npm run gen` 后 `git diff --exit-code`（幂等）+ `EmptyPayload`/`WireCapabilityDescriptorPayload` 精确空对象/排除字段类型的 type-level 断言编译过 | 冒烟 job 绿、无 diff、两类精确类型断言编译通过 | 有 diff、断言不编译、或精确类型失真 | CI 日志 + `app/generated/{ts,swift,csharp}/` |
| SG-4 Mac 最小壳 createSession/subscribe 闭环（**L1 已回填，2026-07-23，rounds/0002**） | SG-4 | **L1（已达成）**：命令＝`swiftc KernelClient.swift OpenclawWire.swift EventMapping.swift OpenclawGatewayKernelClient.swift CLIRunner.swift main.swift ../../generated/swift/D2.swift ../../generated/swift/DiscriminatedUnions.swift -o kernel-client-cli` 编译 + 对本项目自建隔离 openclaw 内核（`ws://127.0.0.1:18889`，recipe 见 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`）执行 `connect → createSession → subscribe 收 KernelEvent 流 → stop`；**L2/parity（仍 defer）**：`send`→SG-8.1、两组金标 parity（审批五态/`SessionLockState`）→SG-8.7（Swift/C# parity runner 未建） | **L1**：swiftc exit 0 + 闭环收到真实 KernelEvent 流并正常 stop（退出码 0）+ 主会话独立复验一致。**L2/parity**：待 SG-8.1/SG-8.7 各自 pass 判据 | L1 闭环任一步失败或编译非 0；L2/parity 任一项不达（尚未评估，非本轮 fail 判据） | `app/kernel-client/RUN-EVIDENCE.md`（L1 evidence，evidence-index E12）+ SG-8.1/SG-8.7 各自 evidence（L2/parity，待补） |
| SG-5 Windows C# kernel-client parity 追赶 | SG-5 | Windows C# 客户端复用与 Mac 相同金标 fixture 集合运行 parity 回归 | 两端在全部已落地 fixture 上产生逐字段一致的可观察状态 | 任一 fixture 两端状态不一致 | parity runner 报告（Swift/C#/TS 三端，落 `app/parity/`） |
| SG-6 D3-proxy e2e wire（defer build+run，收编 SG-8.1） | SG-6 方案B e2e | 起真 openclaw（开 `sendSessionAffinityHeaders`）+ D3-proxy + 真 newapi：① `x-session-affinity` header 真到达 proxy；② sessionId 与 openclaw `Agent.sessionId` 逐字节同源；③真 newapi SSE 帧透传；④mint→映射表 `revokedAt IS NULL` 行 + `findActive` 命中 | 四项全达 | 任一项不达 | SG-8.1 evidence（proxy 日志/抓包/DB 查询） |
| SG-7 hermes per-session key e2e（收编 SG-8.2） | SG-7 | 先定死传输路径（`model_routes` 零改 / ACP <50 行 patch），各 session 查 `/api/log/self?token_name=session-<id>` 互验（D1 §11 C-3 验法） | 各 session 归因隔离、互查不串号 | 归因串号或路径未打通 | SG-8.2 evidence（newapi 日志查询输出） |
| PRE-7 hermes ACP `session/load` 历史 replay 阈值（**已回填，2026-07-26，rounds/0009**） | SG-8.3 PRE-7 | 全新 `hermes-acp` 子进程（每次冷启动）对已种入 20 条消息（`hermes_state.SessionDB.append_message` 真实持久化 API，零 LLM 调用）的 session 调用 `session/load`，计时+核对条数/顺序，连续 3 次独立测量 | **≥20 条不丢、顺序保持 + ≤10s + 连续 3 次一致**；三项在 `model.provider:custom`（或等价防 provider-relabel 配置）前提下全达：20/20 条×3、耗时 0.792s/0.815s/0.803s、顺序（SEED-01..10 交替）3 次一致 → **PRE7_REPLAY_VERDICT: PASS（有条件）** | 任一项不达；或使用 `model.provider:auto`+自定义 base_url 且未配置真实 `OPENROUTER_API_KEY`（本轮发现④：100% 复现 `session/load` 静默返回 0 条历史，根因 `acp_adapter/session.py:551/651`→`runtime_provider.py:1169`→`server.py:1140-1143` provider 标签被 relabel 覆盖持久化，`_restore` 异常被 `except Exception: return None` 静默吞掉，导致"零复原"且"看起来像成功"，比 PRE-1 §1.7 猜测的"部分丢失"更严重）——**PASS 判定不可脱离该前提单独引用**，登记为上游 hermes bug 候选 + conformance 修正候选；不影响 SG-7 api_server `model_routes` 路径结论（两条是 hermes 内独立的会话/凭证管理路径） | `rounds/0009/evidence/track-b-hermes.md` §2；hopper 派 grok T-057 证伪式对抗审确认数据支持 pass（`.hopper/handoffs/T-057-output.md`） |
| SG-8 build+run 内核验收批次 | SG-8 七项子项（SG-8.1~SG-8.7） | 见 goal-breakdown.md「SG-8 验收清单」各子项 build/run + 健康判据（端口/健康检查/版本 pin）+ pass/fail | 各子项按其 pass 判据全达 | 任一子项 fail | 各子项 evidence path（见 SG-8 清单）+ CI 日志 |
| 每轮 adversarial review 引用证据路径 | 每个执行轮（RA-L1 起所有 round） | 对抗性评审走查证据路径是否可达、是否为本 goal 实际产出 | 证据路径存在且可验证，无臆测/未落盘结论 | 证据路径缺失、不可达，或引用未经调研的外部项目能力假设 | 各轮 `rounds/NNNN/reviews/adversarial-review.md` |
| 连载文章成稿需用户发布确认 | goal.md Acceptance Criteria #6（里程碑文章 ≥ 3 篇） | 用户逐篇确认发布 | 用户明确确认通过 | 用户未确认、要求修改，或未走确认流程即视为发布 | PR wiki `drafts/` 文件 + 用户确认记录（human-confirmation） |
| 协议门 | 每轮收盘/continue 门 | `verify_protocol.py`（本项目协议门） | exit 0 | 非 0 或协议门报错 | `verify_protocol.py` 命令输出 |

## Runtime Thresholds

| Runtime surface | Validation method | Pass condition | Observation window | Evidence path |
| --- | --- | --- | --- | --- |
| `verify_protocol.py` | 本地命令（机械协议门） | exit 0 | 每轮收盘/continue 门 | 脚本输出 |
| server API（NestJS，D3=TS+NestJS+PostgreSQL 已定稿，2026-07-23 回填） | build+run：`npm run start`（app/server）起进程，探 `/health`（或 license/tenant/seat 端点）+ D3-proxy session-affinity 转发探针 | 进程起、端口就绪、`/health` 200、D3-proxy 按 `x-session-affinity` 命中映射并换 Authorization 转发成功 | SG-4/SG-6 e2e 期 + 每次 build+run 内核冒烟 | SG-8.1/SG-8.5 evidence + proxy 日志 |
| agent app 消息流屏障 / 内核切换（D1 KernelPort v3.6 / D2 v3 已定稿，2026-07-23 回填） | build+run：真实内核 emit 的 wire event 逐条过 D2 JSON Schema + protocolVersion 握手期单传→逐事件回填重建 round-trip 断言 + 两内核（openclaw/hermes ACP）createSession/subscribe 闭环切换 | 全事件 schema-valid、round-trip 重建一致、两内核闭环均收到 KernelEvent 流 | SG-4/SG-8 build+run 内核冒烟 | SG-8.4 evidence + fixture runner 输出 |
| console 管理端（第二批，依赖 SG-4 kernel-client 与 D3-proxy 就绪） | build+run（第二批开门后定，非首批缺口）：起 console + 对 server API 冒烟 | console 起、对 server 六项能力面读写冒烟通过 | 第二批开门（不阻塞首批 SG-1..SG-8） | 第二批 evidence path（待开门回填） |
| build+run 内核健康（运行时探针底座，2026-07-23 新增） | 端口就绪探测 + 健康检查 + 版本 pin（openclaw HEAD `824adcf` / hermes HEAD `17155e3`，记于 evidence-index E3；node/pnpm/dotnet/swift 工具链版本 pin） | 内核进程起、监听端口 accept、健康检查通过、运行版本与 pin 一致 | SG-4 打通后每次 build+run + SG-8 各探针前 | SG-8.3 runtime 探针 evidence + `research/pre1-*-source-conformance.md` |

## Threshold Change Policy

- Requires human confirmation: yes（技术选型与阈值变更需用户确认，见 goal.md Required Human Decisions）
- Requires new round: TODO (owner: 待 RA-L3 定)
- Drift risk: TODO (owner: 待 RA-L3 定，需评估技术选型对既有阈值的漂移影响)
