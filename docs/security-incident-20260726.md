# 凭证泄漏事件 2026-07-26（GitGuardian 告警）

> 状态：**已处置闭环**（轮换 ✅ / 清史 ✅ / 防线 ✅ / 滥用审计：零）。
> 触发：GitGuardian 向 litianyi@corp.netease.com 告警 `Generic High Entropy Secret`，
> repository `surebeli/test-harnessloop`（**PUBLIC**），pushed 2026-07-25 20:14:13 UTC。

## 1. 泄漏了什么

| 项 | 内容 |
|---|---|
| 凭证 | 自托管 new-api 实例的 API token（`sk-ZnBRy2M8…`，48+3 字符） |
| 真实归属 | new-api token **id=3 `sg8.5-kimi-e2e`**（`used_quota=10318472`，SG-8.5/SG-5 e2e 实际在用的那个） |
| 标签错位 | `channel-params.json` 里该值挂在 `NEWAPI_D3PROXY_TOKEN` 名下——**参数名与实际 token 归属不符**，事故处置初期据此删错了 token（id=1/2，两个零用量同名副本），经 SQLite `select … where key=` 权威比对才定位到 id=3 |
| 其余凭证 | **全部安全**：Kimi 上游付费 key、new-api root 密码、D3 static auth key、SG-7 两个 hermes token、Pi SSH key —— 全树 + 全历史零命中（`git log -S` 逐个验证） |

## 2. 泄漏路径（系统性，不是一次手滑）

| commit（旧 SHA） | 时间 | 载体 | 成因 |
|---|---|---|---|
| `e0a85e9` | 07-26 02:49 +0800 | `rounds/0009/evidence/track-a-openclaw.md:80,87` | 探针子代理把 seed 映射 JSON **原样**写进证据文件 |
| `d8d55a7` | 07-26 04:09 +0800 | `.hopper/handoffs/T-060-output-raw.txt` / `.log` | codex 审查读了那份证据，**vendor 原始输出回显**同一段 → 该次 push 触发 GG 告警 |

**根因**：子代理写的 evidence 与第三方 vendor 的原始日志会原样落真实运行配置，而这条链一路进 public 仓**此前没有任何 secret 守门**（本地无钩子、CI 无扫描）。这次是 D3/e2e token，下次可能是上游付费 key。

## 3. 风险评估

- **可达性有界**：new-api 实例在 `10.244.132.76:3000`（RFC1918 私网），公网不可直达，利用需先进局域网。
- **一旦可达则影响不小**：该 token `unlimited_quota=true`，且背后直连真实 Kimi 付费上游。
- **暴露拼图完整**：public 仓同时暴露内网 IP、端口、服务类型、用法。

## 4. 滥用审计：**零**

token id=3 全部 35 条调用逐条核对，全部可归因于本项目自身轮次：
07-23 16:xx–18:07（SG-9/SG-8.5）、07-24 13:xx–17:15（SG-5 Stage B / SG-8.5 e2e）、
07-26 02:02–02:17（rounds/0009 track-A 探针，**早于** 02:49 的泄漏 push）、
07-26 04:27（事件处置中的一次验证调用，本人发起）。
**泄漏窗口内无任何第三方调用。**

## 5. 处置动作

1. **轮换（首要，已生效）**
   - 删除泄漏 token id=3 `sg8.5-kimi-e2e`；另将两个零用量同名副本 id=1/2 一并清理；新建替代 token id=6 `d3proxy-token-v2`，明文经 Pi SQLite 只读副本取出后写入 gitignored `channel-params.json`（副本用后即删，Pi 侧临时文件同步删除）。
   - **失效验证**：用泄漏串直调 new-api → 首次仍 `HTTP 200`（new-api 内存缓存未刷新，这一步很关键，否则会误判轮换已生效）→ 重启容器 + 删对 token 后复验 → **`HTTP 401 Invalid token`**。
2. **清历史（已完成）**
   - `git filter-repo --replace-text`，泄漏串在**全历史 + 工作树**替换为 `***REDACTED-ROTATED-TOKEN-20260726***`；`git log --all -S<串>` 命中数 **0**。
   - 受影响 5 个 commit 的 SHA 变更（`e0a85e9→184d6a70`、`3bd9e4d→ce282153`、`567d6bc→c6365aa7`、`d8d55a7→cd400d23`、`b638499→e32a62de`），文档内旧 SHA 引用已同步修正；重写前留本地备份分支 `backup-pre-purge-20260726`。
   - 注：GitHub 对已 push 的旧 commit 存在缓存/可达期，**因此轮换才是根本补救，清史是卫生**。
3. **防线（已落地，三层）**
   - `scripts/check-secrets.sh`：**L1** 精确值（读 gitignored channel-params，长度 ≥16 的值必须零命中，零误报）+ **L2** 形态兜底（`sk-`/JWT/AKIA/ghp_/xox*，带词边界，REDACTED 类显式放行）。
   - **pre-commit 钩子**（`--staged` 模式，本地拦在入库前；与既有钩子共存，原钩子已备份）。
   - **CI job**（ubuntu job checkout 后首步全树扫描），漏网也能在 push 后即刻变红。
   - 双向反证：真实 Kimi key 入暂存 → 拦截；干净内容 → 放行。

## 6. 待办与遗留

- [ ] **（用户待办）** 在 GitGuardian 控制台把该告警标记为 resolved（rotated + purged）——仅账号持有人可操作。
- [x] `channel-params.json` **参数名与实际 token 归属对齐**（本次删错 token 的直接诱因）：已给每个 token 参数补 `owner_note`（真实 `token id` + `name`），并新增 `_naming_discipline` 条目要求新增/轮换时同步更新。当前对齐状态：`NEWAPI_D3PROXY_TOKEN` → id=6 `d3proxy-token-v2`；`NEWAPI_SG7_HERMES_SESSION_A/B_TOKEN` → id=4/5。
- [x] **决策（user-confirmed 2026-07-26）：`.hopper/handoffs/*-raw.txt|*.log` 继续进 public 仓。** 理由：它们是异构审查可追溯性的核心证据（本项目"用插件验证插件"的关键语料）。风险由新增的三层守门（L1 精确值 + L2 形态 + pre-commit/CI 双执行点）承接；并已就此决定做了一次**语义级敏感内容普查**（多镜头并行 + 对抗核实 + 扫描器盲区评估），结论见下方 §7。
- [x] 该事件已并入 `docs/harnessloop-evaluation-20260726.md` 的问题域（"evidence/vendor 日志无 secret 守门"属协议外系统性缺口）。

## 7. 语义级普查（2026-07-26，决定"vendor raw log 继续进 public"后立即执行）

**方法**：5 镜头并行扫全部 tracked 语料（533 文件；重点 `.hopper/handoffs/` 159 个 raw/log 共 38MB）→ 原始信号 38 条 → 逐条对抗核实（默认立场"这不是真风险"）→ 合成。

**结论：存量语料 0 条真实风险。** 无有效 key/token、无 JWT、无私钥/PEM、无 URL 内嵌凭证、无公网 IP/MAC/序列号、无第三方隐私数据。被证伪的典型误报已存档（`sk-` 多为 `task-`/`risk-` 子串；`DB_PASSWORD=postgres`/`change-me-*` 是开发默认值；"高熵串"多为 git SHA / npm integrity / UUID；"内网 IP"多为 semver）。三项阈下知情项（家用 Pi 内网拓扑、一处 mDNS 主机名快照、日志里的本人 commit 邮箱）经核实不构成可利用风险，无需处置。

**但普查抓到守门自身的假绿（比存量风险严重得多）**：`check-secrets.sh` 首版的 L1 依赖 gitignored 的 `channel-params.json`，**CI checkout 里没有该文件 → 整个 L1 静默跳过 → 却仍打印"✅ L1+L2 通过"**。即面向公网那道防线实际只有 L2，而本次泄漏恰恰只有 L1 抓得住。**这与本项目反复抓到的"绿灯≠真守门"是同一病灶，只不过这次犯在自己的安全脚本上。**

**同日加固（均已实测）**：
- **L1-digest**：新增 `scripts/secret-digests.txt`（加盐 SHA-256，**不含明文**，由 `--update-digests` 生成），CI 无明文也能跑 L1；轮换凭证后需重跑生成。短/弱口令不入摘要（防离线爆破），仅本地 L1-exact 覆盖。
- **诚实横幅**：成功信息改为声明**实际运行层**（如 `L1-digest + L2`）；两种 L1 都没跑时显式告警。
- **抗折行绕过**：所有比对同时在"原文"与"去空白流"上做；去空白前先剥 `git diff` 的 `+/-` 行首标记——实测正是这个 `+` 会把折行 token 粘断，使 L1/L2 同时失效。
- **短口令门槛**：参数名含 `pass|pwd|secret|token|key` 的把长度门槛从 16 降到 8。
- **L2 前缀扩表**：补 PEM 私钥块、URL 内嵌口令（含 `postgres://user:pass@`）、`github_pat_`、`glpat-`、`AIza`、Slack webhook、`hf_`、`npm_`、`dop_v1_`、SendGrid。
- **钩子安装写进 CLAUDE.md**（`.git/hooks` 不版本化，换机器会静默裸奔）。

**四场景铁齿验证**：本地全树 → `L1-exact + L1-digest + L2` 全跑通过；模拟 CI（隐藏明文）→ 如实标注 `L1-digest + L2`；真实 key 入暂存 → L1-digest 拦截；**token 被折成两行** → L1-digest 仍拦截；干净内容 → 放行。

**仍建议但未做（留给你定）**：
1. **在"写"的一端脱敏**：在 hopper 捕获 vendor stdout 的位置串一个 filter，落盘前就把已知凭证替换为 `***REDACTED***`（预防 > 检测，属 `hopper-plugin` 侧改动）。
2. **`*-raw.txt` 与 `*-output.log` 逐字节重复**（实测约 20 对）：只 track 其中一种可使暴露面与仓库体积同时减半，且不损失信息。
3. warn-only 的语义 lint（高熵兜底 + `/Users/<name>`、RFC1918、`*.local`、企业邮箱域），只在新增 handoffs 上跑、输出到 job summary 不阻断。
