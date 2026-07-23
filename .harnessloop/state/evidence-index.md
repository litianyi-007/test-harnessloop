# Evidence Index

| Evidence ID | Type | Path | Applies to | Freshness requirement | Observed timestamp | Validation method | Channel parameter references | Citation required | Artifact health | Claim support | Acceptance effect | Reproducibility | Sensitivity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| E1 | static | docs/harnessloop-review-20260716.md | goal 20260716-001-setup-wizard 需求依据（P1 #5/#6 guided-setup/auto-detection lens） | 冻结基线 2026-07-16，不刷新——被新一轮审查取代时整体作废 | 2026-07-16 | 与 findings.json 的 JSON 结构比对 | 无 | yes | valid | supports | neutral | 可重现（本地文件读取） | internal |
| E2 | static | docs/harnessloop-review-20260716.findings.json | 同 E1，80 条确认发现的机器可读版本 | 冻结基线 2026-07-16，不刷新 | 2026-07-16 | JSON 结构校验 / 与 E1 比对 | 无 | yes | valid | supports | neutral | 可重现（本地文件读取） | internal |
| E3 | source | harnessloop/plugins/harnessloop/skills/harnessloop-loop/references/ | 格式权威，本 goal 所有新文件/skill 结构依据 | 随 submodule HEAD 刷新（当前 3f17878） | 2026-07-23（HEAD 刷新复核） | git log + scripts/plugin-status.sh 内容级 diff | 无 | yes | valid | supports | pass | 可重现（git HEAD 固定，可重新 diff） | internal |
| E4 | runtime | npm run validate 输出（cwd=harnessloop/，命令输出非固定文件） | 全部 acceptance criteria 的 validate 断言 | 每次运行重新生成，不可复用旧输出 | TODO (owner: user)（本 goal 尚未运行） | 7/7 阶段全绿 | 无 | yes | missing | unknown | blocked | 可重现（命令可重跑） | internal |
| E5 | static | docs/validation-log.md（2026-07-16 P0 修复批次条目） | state/environment.md 与 state/self-check.md 的 delegation 自检依据 | 冻结（历史记录，特定批次的实证，不随后续批次自动刷新） | 2026-07-16 | 人工读取比对（记录内容与批次审查交互一致） | 无 | yes | valid | supports | pass | 可重现（文件常驻，可重读） | internal |
| E6 | static+runtime | app/contracts/d2/ + app/generated/{ts,swift,csharp}/ + app/contracts/d2/CODEGEN-FINDINGS.md + app/contracts/d2/codegen/verify/{swift,csharp} | goal 002 SG-1（D2 机器可读 schema + 三端 codegen TS/Swift/C# + 判别联合存活 + fixture runner 骨架） | 随 commit 0b4b79c 冻结；D2 schema/codegen 变更时重跑 npm run gen | 2026-07-23（补记；commit 0b4b79c，起步 08508d4） | tsc --strict + quicktype 三端生成 + 判别联合存活断言（详见 CODEGEN-FINDINGS.md） | 无 | yes | valid | supports | pass | 可重现（commit 固定；npm run gen 可重跑） | internal |
| E7 | runtime | app/server/src/ | goal 002 SG-2（NestJS server 骨架，8 模块据 D3 OpenAPI，TypeORM 实体 + JWT/Ed25519 license + newapi D3 代理桩，可编译） | 随 commit da95155 冻结；server 源码变更时重编译 | 2026-07-23（补记；commit da95155） | NestJS/tsc 编译通过（可编译级，非 e2e 运行） | 无 | yes | valid | supports | pass | 可重现（commit 固定；build 可重跑） | internal |
| E8 | runtime | app/server/src/（D3-proxy session-affinity 路由）；设计 spec ~/.llm-wiki/agent-app-design/architecture/sg6-openclaw-persession-patch-design.md | goal 002 SG-6（方案B：openclaw 主路径零改 + 辅助小 patch + D3-proxy session-affinity 路由；**code+对抗审级**，e2e wire defer 至 SG-8 build+run） | 随收口 commit c69041e 冻结；e2e wire 待 SG-8 build+run 补证 | 2026-07-23（补记；impl 5fcf9de→REWORK 362b04e→收口 c69041e→openclaw 指针 5b133b7→状态 399c793；openclaw fork 补丁 submodule 824adcf） | build 通过 + jest 18-19 pass + eslint 全过（静态级）；e2e wire 未证 | 无 | yes | valid（静态级；e2e 部分 blocked） | partial（code+对抗审级 supports；billingAttribution:session 端到端 defer） | pass（code 级） | 可重现（commit 固定；build/jest 可重跑） | internal |
| E9 | source | hopper handoff T-041（codex 对抗审 verdict）；D4 v2.3 定稿 commit c82d6bd/9795755/59cf86d + wiki eb3ca73 | goal 002 D4 v2.3 定稿（codegen 边界据 SG-1 代码修正）复核 | 随 D4 v2.3 定稿冻结；D4 再修订时重审 | 2026-07-23（补记；codex T-041 MUST-FIX→收口 confirmed） | hopper 派 codex 对抗审；三项强制核对（审查对象/产物路径/非仅凭 exit0）+ 收口 commit 核对 | 无 | yes | valid | supports | pass | 部分可重现（review 可重派；verdict 记录常驻） | internal |
| E10 | source | hopper handoff T-042（grok 对抗审 verdict）；SG-6 REWORK 362b04e→收口 c69041e | goal 002 SG-6 对抗审（verdict=REWORK→整改收口） | 随 SG-6 收口 c69041e 冻结 | 2026-07-23（补记；grok T-042 REWORK→收口；尾部 auth-fail=XAI_API_KEY 失效已恢复） | hopper 派 grok 对抗审 verdict=REWORK → 按整改收口 commit 核对 | XAI_API_KEY（grok；曾失效已恢复，后续需重新登录） | yes | valid | supports | pass | 部分可重现（review 可重派，需 grok 重新登录） | internal |
| E11 | source | ~/.llm-wiki/agent-app-design/research/pre1-openclaw-source-conformance.md + pre1-hermes-source-conformance.md | goal 002 PRE-①（内核源码一致性核验：C-3 path① 对两内核成立；发现 hermes 原生 soft steer） | 随 kernels/openclaw HEAD 824adcf / kernels/hermes HEAD 17155e3 冻结；submodule HEAD 变更时重核 | 2026-07-22（PRE-① 只读源码定向核验） | 只读源码定向核验（openclaw@824adcf / hermes@17155e3，非 live-probe） | 无 | yes | valid | supports | pass | 可重现（submodule HEAD 固定，可重读源码） | internal |
| E12 | runtime | app/kernel-client/（swift/、csharp/）+ app/kernel-client/RUN-EVIDENCE.md | goal 002 SG-4（kernel-client 对真实运行 openclaw 内核的 L1 连通闭环：`connect → createSession → subscribe 收真实 KernelEvent 流 → stop`） | 随本轮收盘冻结；内核重启/客户端代码变更时需重跑复验 | 2026-07-23（rounds/0002；对本项目自建隔离内核 `ws://127.0.0.1:18889` 的 live 试跑，未连/未干扰用户全局 gateway 18789/PID 5197） | swiftc 编译 exit 0 + dotnet build succeeded + 对隔离内核 live 闭环逐帧证据（exit 0）+ 主会话独立复验（重新编译 + 重跑一次闭环，结果一致） | 无 | yes | valid | supports（L1 连通闭环）；send/完整事件适配（10/11 变体）/gold parity 部分明确 defer，非本条 claim 覆盖范围 | pass（L1 级） | 可重现（recipe 在 `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md`，重启隔离内核可复跑） | internal |
| E13 | runtime | app/deploy/newapi/docker-compose.yml（版本控制的部署编排）+ `.harnessloop/local/channel-params.json`（gitignored，raspberry-pi-deploy channel + newapi channel 参数；密码/凭证值不入索引） | goal 002 SG-9（newapi 自托管部署到树莓派：Pi 装 Docker + new-api 容器起 + 管理面可达，L1 部署+管理面就绪级） | 随本轮收盘冻结；Pi 重启/容器重建/凭证轮换时需重跑复验 | 2026-07-23（rounds/0003；对树莓派 `10.244.132.76`(`olegpi`，Ubuntu 24.04.4 aarch64) 的 live 部署与跨机管理面访问） | Pi Docker `29.6.2`+compose `5.3.1` 装成 + 容器 running + 从开发本机 `10.244.132.185` 跨机 `GET /api/status` 200 + `GET /api/setup` 显示 `root_init` + root `POST /api/setup` 初始化成功 + root 登录成功（role 100 admin） | 无（凭证走 gitignored channel-params，不作为 channel parameter reference 登记值） | yes | valid | supports（L1 部署+管理面就绪）；渠道配置（L2）因缺 `NEWAPI_UPSTREAM_LLM_KEY` access-missing defer、完整计费链 e2e 结转 SG-8.5，均非本条 claim 覆盖范围 | pass（L1 级） | 可重现（compose 文件版本控制；registry 镜像加速器配置已解决 Docker Hub 连接重置问题，可复现部署） | internal |

## Artifact Health Values

- `valid`: evidence exists, is fresh enough, and can be cited.
- `stale`: evidence exists but violates freshness or drift rules.
- `missing`: evidence path or source is absent.
- `inconclusive`: evidence exists but cannot support acceptance.
- `blocked`: evidence requires human access or external setup.

## Claim Support Values

- `supports`: supports the claim being tested.
- `refutes`: refutes the claim being tested.
- `partial`: supports only part of the claim.
- `unrelated`: valid artifact but not relevant to the claim.
- `unknown`: claim relationship has not been assessed.

## Acceptance Effect Values

- `pass`: contributes to accepting a round.
- `fail`: contributes to rejecting a round.
- `neutral`: cited but not decisive.
- `blocked`: cannot be evaluated without access or human action.

## Evidence Types

- static
- dynamic
- runtime
- source
- human-confirmation
