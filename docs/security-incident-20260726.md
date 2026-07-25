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

- [ ] 在 GitGuardian 控制台把该告警标记为 resolved（rotated + purged）。
- [ ] `channel-params.json` 的**参数名与实际 token 归属对齐**（本次删错 token 的直接诱因）——建议每个 token 参数补 `token_id` 与 `token_name` 字段。
- [ ] 评估 `.hopper/handoffs/*-raw.txt|*.log`（vendor 原始输出）是否仍适合进 public 仓：它们是审查可追溯性的核心证据，但也是本次泄漏的第二载体。
- [ ] 该事件已并入 `docs/harnessloop-evaluation-20260726.md` 的问题域（"evidence/vendor 日志无 secret 守门"属协议外系统性缺口）。
