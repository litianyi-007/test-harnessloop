# Scope Lock — rounds/0009

## Round Objective

**SG-8 验收清单收尾批次（SG-8.1 / SG-8.2 / SG-8.3 / SG-8.4①②）**——把首批 SG 最后悬着的 runtime 探针/e2e 验证项一次清干净。全部为**探针/验证型**工作（跑真实内核收证据,不写产品代码);两内核两侧相互独立,**并行双子代理**执行。

**诚实边界(先定)**:SG-8.4③(hermes ACP 线路的 kernel-client `createSession`/`subscribe` 闭环)需要**新写 HermesACP kernel-client 适配器**——实现级工作,不属探针批,本轮**明确 defer**(候选第二批 SG);SG-8.4 本轮只做 ①②(openclaw 侧 wire event schema 校验 + protocolVersion round-trip)。

### 轨 A(openclaw 侧,子代理 A)
- **SG-8.1 四项**(SG-6 e2e wire 实证,承接 defer):起隔离 openclaw(recipe 现成,`sendSessionAffinityHeaders` 开)+ D3-proxy(app/server)+ 指真 newapi(Pi)。pass:① `x-session-affinity` header 真到达 D3-proxy(proxy 日志可见);② header 里 sessionId 与 openclaw `Agent.sessionId` **逐字节同源**;③ 真 newapi SSE 帧透传(帧序不乱、不缓冲);④ mint 成功→映射表出现 `revokedAt IS NULL` 行且 `findActive` 命中。注:①③ 在 SG-8.5/SG-5 已有强证据,本轮聚焦②④的**显式断言**+①③引用既有证据或轻量复证,不重复烧调用。
- **SG-8.3 openclaw 探针**(PRE-1/PRE-3):PRE-1(C-1)soft `chat.send`+`queueMode:"steer"` 精确 ack/hard-abort error 信号(成功注入/拒收/静默 fallback 三场景响应体差异);PRE-3(C-4)`sessions.steer` abort 成功但 `chat.send` 失败时 error 是否透 `interruptedActiveRun`。
- **SG-8.4①②**:隔离 openclaw 真实 emit 的 wire event 逐条过 D2 JSON Schema(Ajv,复用 fixtures 校验基建);protocolVersion 握手期单传→事件回填重建 round-trip 断言一致。

### 轨 B(hermes 侧,子代理 B)
- **SG-8.2**(hermes per-session 归因**自查互验**,SG-7 admin 路径之外的指定验法):各 session 用**自己的 token** 查 `/api/log/self?token_name=...` 互验——A token 只能看到 A 的调用、查不到 B 的(互查不串号,D1 §11 C-3 验法)。复用 SG-7 已建 token(id=4/5)与既有计费记录,能不调 Kimi 就不调;若 self API 行为与假设不符(如权限/参数不支持),如实记录实况+替代验法。
- **SG-8.3 hermes 探针**(PRE-7 + hermes-steer 冒烟):PRE-7 hermes ACP `session/load` 历史 replay 可靠性——**PASS 阈值(本 scope-lock 定,主会话提案)**:≥20 条消息历史 `session/load` 完整 replay(条数不丢、顺序保持)、replay 完成 ≤10s、连续 3 次一致;hermes-steer-runtime 冒烟:`interrupt(mode:'steer')` 在 `state.is_running` 真软注入 vs 空闲时按降级分类的真实行为。ACP 探针用 stdio 传输(探针级,零改内核;若探针本身被内核缺陷挡住→如实记录=合格产出)。

### ★审查闸(两轨齐后)
hopper 异构对抗审:探针证据充分性/断言真实(逐字节同源怎么证的/schema 校验真跑了/阈值判定诚实)/零内核改动核验(两 submodule git 全空)/defer(SG-8.4③)与实况相符。

## Allowed Changes

| Path | Action | Limit |
|---|---|---|
| scratchpad | 写 | 隔离运行/探针脚本 throwaway |
| `.harnessloop/goals/20260718-002-agent-app/rounds/0009/evidence/` | 新建 | 探针证据(A/B 轨各自文件,SG-8 清单指定落点) |
| `.harnessloop/goals/20260718-002-agent-app/thresholds.md` | 改 | PRE-7 replay 阈值落档 |
| new-api(Pi) | 只读为主 | 日志/自查 API;轨 A ④ mint 经 D3-proxy 正常业务路径产生的映射写入允许 |
| `.harnessloop/local/channel-params.json` | 写 | 如需新参数名 |
| `.harnessloop/rounds/0009/` + state、`.hopper/` | 写 | round 收口+审查闸 |

## Disallowed Changes

- 改 `kernels/openclaw`/`kernels/hermes` 源码(探针被内核缺陷挡住=如实记录,合格产出)。
- 改 `app/`(server/kernel-client/contracts/fixtures 均只用不改;若探针暴露真 bug→记 blocker)。
- 凭证入 tracked;动用户全局服务(18789 等)/Pi 部署本体;三插件/wiki。

## One-Variable Strict Mode
- Enabled: no(探针批,两轨并行)。

## Verification Commands Or Checks

| Check | Expected | Evidence |
|---|---|---|
| SG-8.1 ②④(+①③引用/复证) | sessionId 逐字节同源;mint 后 `revokedAt IS NULL` + findActive 命中 | proxy 日志/DB 查询,rounds/0009/evidence/ |
| SG-8.3 PRE-1/PRE-3 | 三场景响应体差异表;error 透传实况 | 探针输出 |
| SG-8.4①② | 真实 wire event 全过 D2 schema;protocolVersion round-trip 一致 | Ajv 输出+断言日志 |
| SG-8.2 | token 自查互验不串号(或 self API 实况+替代验法) | API 查询输出 |
| SG-8.3 PRE-7+steer 冒烟 | replay 阈值判定(≥20条/≤10s/3次一致);steer 真实行为分类 | 探针输出+阈值对照 |
| 零改动 | 两 submodule git(含 --ignored)全空 | git 输出 |
| ★审查闸 | PASS/PASS_WITH_NOTE | `.hopper/handoffs/` |

## Runtime Recovery Limits
- Recovery:内核起不来/探针环境问题→调隔离配置迭代(runtime-recoverable);探针暴露内核/组件真缺陷→**不是 blocker 是发现**,如实记录进证据与 conformance 修正候选;须改已收口组件才能跑通探针=contract-insufficient 停下。
- Cleanup:收尾 kill 隔离进程;`--ignored` 双查两 submodule(rounds/0008 新纪律)。

## Rollback Condition
探针结果与 D1/D2 契约或 PRE-① conformance 结论**矛盾**时:如实记录矛盾点(file:line/响应体),不改契约不改内核,标 conformance 修正候选交主会话走设计修订;SG-8.x 各子项按实况独立判 pass/fail/defer,不互相绑定。

## Human Confirmation Required
- 自动化+审查闸+最小真实调用(若需):既定授权。
- PRE-7 阈值为主会话提案,证据显示阈值明显失当时如实报请调整,不硬判。
