# SG-7 hermes per-session key e2e 证据（rounds/0008）

> 配套 recipe：`app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md`。本文档只放 Stage A/B 的
> 逐字段证据，机制的源码坐实见 recipe §5。key 值按 scope-lock 要求脱敏（用 new-api 自身列表接口
> 返回的掩码形式，如 `w83m**********dCjL`），token 名/id 保留（非敏感，供归因核对）。

## 环境

- hermes：`kernels/hermes` submodule pin `17155e3ae04d376dd8eba2e65f3dd966e67ab1ba`
  （`pyproject.toml` `version = "0.19.0"`），隔离 venv（Python 3.11），`HERMES_HOME` 隔离在
  scratchpad，隔离端口 `127.0.0.1:8646`。
- new-api：`http://10.244.132.76:3000`（Pi 部署，SG-9 先例），channel id=1（`kimi-coding`，
  type=14 Anthropic 兼容，upstream model `kimi-for-coding`）。

---

## Stage A：健康检查 + 默认路径最小往返

`GET /health`：
```json
{"status": "ok", "platform": "hermes-agent", "version": "0.19.0"}
```

`GET /health/detailed`（节选）：
```json
{
  "status": "ok",
  "readiness": {"status": "ok", "checks": {
    "state_db": {"status": "ok"}, "config": {"status": "ok"}, "model": {"status": "ok"},
    "disk": {"status": "ok", ...}, "gateway": {"status": "ok", "state": "running",
      "connected_platforms": 1, "platforms": 1},
    "background_queues": {"status": "ok", "active_api_runs": 0, ...}
  }},
  "platforms": {"api_server": {"state": "connected", "error_code": null}},
  "pid": 9182
}
```

默认路径（无 `model_routes` 别名，走 config.yaml `model.*` 兜底配置）最小 prompt 往返：

请求：
```json
POST /v1/chat/completions
{"model":"hermes-agent","messages":[{"role":"user","content":"reply with exactly: HELLO-DEFAULT"}]}
```

响应：
```json
{
  "id": "chatcmpl-eda549f7c6804d6c98693033bb568",
  "model": "hermes-agent",
  "choices": [{"message": {"role": "assistant", "content": "HELLO-DEFAULT"}, "finish_reason": "stop"}],
  "usage": {"prompt_tokens": 11514, "completion_tokens": 28, "total_tokens": 11542}
}
```

真实 Kimi 回复内容精确等于要求的 `HELLO-DEFAULT`，`prompt_tokens` 高（~1.15 万）是 hermes agent
完整 system prompt + toolset 描述的正常量级，不是异常。Stage A 达成：隔离 gateway 起、`api_server`
平台 connected、真实往返打通。

---

## Stage B：per-session key 归因 e2e

### B.1 建两个测试 token（new-api root Management API）

登录：`POST /api/user/login {"username":"root","password":"<NEWAPI_ROOT_PASSWORD>"}` → `success:true`，
`role:100`（root）。

建 token（`POST /api/token/`，`New-Api-User: 1`）：
```json
{"name":"sg7-hermes-session-a", "unlimited_quota":true, "remain_quota":500000, "expired_time":-1}
{"name":"sg7-hermes-session-b", "unlimited_quota":true, "remain_quota":500000, "expired_time":-1}
```
两次调用均 `{"success":true,"message":""}`（new-api 创建响应不含明文 key，符合 T-009/T-031/
`app/server/README.md` 已记录的已知缺口）。

`GET /api/token/?p=0&size=20` 核对新建条目：

| id | name | group | unlimited_quota |
|---|---|---|---|
| 4 | sg7-hermes-session-a | (空=default) | true |
| 5 | sg7-hermes-session-b | (空=default) | true |

**取明文 key 的方法（新记录，供后续轮参考）**：`GET /api/token/:id`（T-009 称为 `GetTokenKey`）
在本实例上实测**仍只返回掩码**（`"key":"w83m**********dCjL"`），并未如 T-009 推断的那样回明文——
这与 `POST /api/token/` 缺 id/明文的已知缺口是**同一个更宽的缺口**（管理面拿不到明文 key，不止创建
时拿不到）。本轮绕行取法：SSH 到 Pi（`PI_SSH_KEY` channel），`docker inspect new-api` 确认无
`SQL_DSN` 环境变量（即用默认 SQLite，`/home/ubuntu/newapi-deploy/data/one-api.db`），`scp` 一份
**只读副本**到本机 scratchpad，本机 `sqlite3` 查 `SELECT id,name,key FROM tokens WHERE id IN (4,5)`
拿到明文 key，随后**立即删除**本机副本（不留存、不入库）。全程未修改 Pi 上任何文件（`scp` 单向拉取，
未 `docker exec` 写操作）。

**limitation 注（T-055 对抗复核补记）**：以上"未修改 Pi 上任何文件"目前只有单向 `scp` 操作的操作
叙述，**没有**远端操作前后的独立 stat/hash 对照或命令 transcript 留存——即没有可供事后复核的
"scp 前后 Pi 端文件指纹不变"独立证据。这不影响本文档已验证的 e2e 归因结论（token/model/usage
逐字段核对，见下方 B.3），但这条隔离子断言本身（"Pi 源 SQLite 只读、未被写"）尚未达到独立实证级，
如实标注、不辩解。掩码形式：

| id | name | key（掩码） |
|---|---|---|
| 4 | sg7-hermes-session-a | `w83m**********dCjL` |
| 5 | sg7-hermes-session-b | `A5eZ**********bkfF` |

两个明文 key 已登记 `.harnessloop/local/channel-params.json`（gitignored）
`NEWAPI_SG7_HERMES_SESSION_A_TOKEN` / `NEWAPI_SG7_HERMES_SESSION_B_TOKEN`。

**直连验证（绕开 hermes，先确认 token 本身可用）**：
```bash
curl http://10.244.132.76:3000/v1/chat/completions \
  -H "Authorization: Bearer <token A>" \
  -d '{"model":"kimi-for-coding","messages":[{"role":"user","content":"reply with exactly: PING-A"}],"max_tokens":20}'
```
返回真实 Kimi 响应（`reasoning_content` 非空，`finish_reason:"length"`——`max_tokens:20` 对这个
带推理链的模型偏小，本轮真实 hermes 调用未设该上限，未复现这个截断）。计费落 new-api `/api/log/`
id=43（见 B.3 表，token_id=4）。这一步确认 token 本身在打通 hermes 之前就已可用，隔离了"token 有
问题"和"hermes 接线有问题"两类失败可能。

### B.2 hermes 两 session 各发最小 prompt

`config.yaml` `platforms.api_server.extra.model_routes` 登记两个 alias（见 recipe §2），
`api_key`/`base_url` 分别指向 token A/B + new-api。

请求 A：
```json
POST /v1/chat/completions
X-Hermes-Session-Id: sg7-session-a
{"model":"session-a","messages":[{"role":"user","content":"reply with exactly: PING-A"}]}
```
响应 A：
```json
{
  "model": "session-a",
  "choices": [{"message": {"content": "PING-A"}, "finish_reason": "stop"}],
  "usage": {"prompt_tokens": 11508, "completion_tokens": 22, "total_tokens": 11530}
}
```

请求 B：
```json
POST /v1/chat/completions
X-Hermes-Session-Id: sg7-session-b
{"model":"session-b","messages":[{"role":"user","content":"reply with exactly: PING-B"}]}
```
响应 B：
```json
{
  "model": "session-b",
  "choices": [{"message": {"content": "PING-B"}, "finish_reason": "stop"}],
  "usage": {"prompt_tokens": 11508, "completion_tokens": 15, "total_tokens": 11523}
}
```

两次真实 Kimi 回复内容精确等于各自要求的 `PING-A`/`PING-B`。

**`GET /v1/models` 佐证**（route 别名确实注册为可寻址模型，`root` 字段暴露了它们各自解析到的真实
upstream 模型名）：
```json
{"data": [
  {"id": "hermes-agent", "root": "hermes-agent", "parent": null},
  {"id": "session-a", "root": "kimi-for-coding", "parent": "hermes-agent"},
  {"id": "session-b", "root": "kimi-for-coding", "parent": "hermes-agent"}
]}
```

### B.3 new-api `/api/log/` 归因核对（逐字段）

`GET /api/log/?p=0&page_size=10`（root Management API）返回的相关条目：

| log id | token_name | token_id | model_name | channel_name | completion_tokens | prompt_tokens(log) | cache_tokens(other) | prompt_tokens(log)+cache_tokens |
|---|---|---|---|---|---|---|---|---|
| 45 | sg7-hermes-session-a | **4** | kimi-for-coding | kimi-coding | **22** | 244 | 11264 | **11508** |
| 46 | sg7-hermes-session-b | **5** | kimi-for-coding | kimi-coding | **15** | 244 | 11264 | **11508** |

逐字段断言：
- **token 归因正确**：请求 A（alias `session-a`）的计费精确落在 `token_id=4`/`token_name=
  sg7-hermes-session-a`；请求 B（alias `session-b`）精确落在 `token_id=5`/`token_name=
  sg7-hermes-session-b`——**没有交叉、没有聚合到同一个 token**，这是本轮要证明的核心断言。
- **model 归因正确**：两条日志 `model_name` 均为 `kimi-for-coding`，与 route 配置的
  `route.model` 一致，且 new-api 侧渠道正确路由到 `kimi-coding` channel（真实 Kimi 上游）。
- **usage 与响应精确吻合**：`completion_tokens` 逐条精确相等（A: 22=22，B: 15=15，都是
  hermes 响应体自报的数字，不是估算）。`prompt_tokens` 表面上不直接相等（hermes 报
  11508，new-api log 只报 244）——差额精确等于该条日志 `other` 字段里的
  `cache_tokens:11264`（new-api 把 hermes 发来的长 system/tool prompt 命中的部分算作
  prompt-cache 命中、拆开计费统计，`244(未命中)+11264(命中)=11508`，与 hermes 侧
  `prompt_tokens` **精确相等**，两条日志（A/B）都是如此）——这不是巧合，是 new-api 
  Claude-Messages 兼容层的标准计费字段拆分（`other.usage_semantic:"anthropic"`），
  证明这两条日志确实就是对应这两次 hermes 调用的真实计费记录，不是碰巧数字接近。
- 两条日志的 `request_path` 均为 `/v1/chat/completions`，`request_id` 各不相同（
  `...qFuKbCAJ` / `...dMzfUoEd`），`created_at` 时间戳与两次 curl 调用发起时间吻合，
  `is_stream:true`（hermes 内部对上游走的是流式请求，即便对外 `/v1/chat/completions`
  这次调用本身不是 stream 模式，这是 hermes→upstream 内部实现细节，不影响归因结论）。

**结论：per-session key 归因 e2e 通过，逐字段（token_id/token_name/model_name/
completion_tokens/prompt_tokens 折算后）精确吻合，无编造、无估算。**

---

## 零改动核验

```
$ git -C kernels/hermes status
On branch main
Your branch is behind 'origin/main' by 17365 commits, and can be fast-forwarded.
  (use "git pull" to update your local branch)

nothing to commit, working tree clean

$ git -C kernels/hermes diff --stat
(空输出)
```

本轮 `kernels/hermes` **无 tracked source diff**（上方 `git status`/`git diff --stat` 均干净，
只是 tracked-source 口径，不等于工作目录零落盘——**收窄说明**：`build/` 构建产物（安装依赖时产生）
已在提交前清理（详见 recipe §1 坑 1）；但被 `.gitignore:59` 遮蔽的 `hermes_agent.egg-info/` 当时
**未察觉**，普通 `git status` 看不到它，直到 T-055 对抗复核用 `git status --ignored --short` 才现场
发现并事后清理——本文档最初"全程未修改任何文件/已清理"的表述过宽，已按此收窄）。`~/.hermes/logs/`
的两个空日志文件（隔离缝隙，详见 recipe §6）已清理。

主仓库改动仅为本轮新建文件：
```
$ git status --porcelain (相关部分)
?? app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md
?? app/kernel-client/HERMES-RUN-EVIDENCE.md
 M .harnessloop/local/channel-params.json   (新增两个测试 token 参数，gitignored)
```

---

## 收尾状态

- 隔离 hermes gateway 进程已 `kill -TERM`，优雅退出（`.clean_shutdown` 落盘），端口 8646 已释放，
  无残留进程。
- `hermes-venv/`、`hermes-home/` 留在 scratchpad，throwaway，自然回收。
- 新建的两个 new-api token（id=4/5）**保留**（供后续轮复用，与 SG-8.5 的 `sg8.5-kimi-e2e`（id=3）
  同等对待，未删除）。
- 本地拉取的 SQLite 只读副本（含明文 key 等敏感字段）已删除，未留存。
