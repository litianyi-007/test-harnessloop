# SG-7 hermes kernel 隔离运行 recipe（api_server HTTP 平台 + per-session key）

> **保全说明**：本文件产于 rounds/0008（SG-7：hermes per-session key 接线 e2e），格式对齐
> `app/kernel-client/OPENCLAW-ISOLATED-RUN-RECIPE.md` 的 recipe 惯例（前置/步骤/坑/验证命令）。
> 状态标注: `[源码]` = 读 `kernels/hermes/<path>:<line>` 坐实；`[实测]` = 本轮 throwaway 试跑实测
> （已清理，见文末）；`[推断]` = 未直接验证的推断。

范围: `kernels/hermes` submodule pin `17155e3ae04d376dd8eba2e65f3dd966e67ab1ba`（2026-07-22，
`pyproject.toml:10` `version = "0.19.0"`，与 PRE-① 源码核验的引用基线一致，本轮未发现该 pin 有漂移）。
隔离端口 8646，隔离 `HERMES_HOME` 在 scratchpad 下，全程未连接/未污染用户全局 `~/.hermes`（**除一处
已发现并清理的边界泄漏，见 §6**）。本轮验证的是 PRE-①裁定的「hermes 走 `api_server` HTTP 平台
per-session baseUrl/key = 原生零改动」claim；**未走** ACP 路径（PRE-① 判定该路径需要小 patch，本轮
不涉及）。

---

## 0. 关键结论先说

**PRE-① claim 成立，未证伪**：本轮全程 `git -C kernels/hermes status/diff` 保持干净（见 §7），
两个独立 session 各持独立 new-api token 的 per-session 归因 e2e 通过（完整证据见
`HERMES-RUN-EVIDENCE.md`）。机制入口是 `gateway/platforms/api_server.py` 的 `model_routes` 配置块，
**不是**环境变量、**不是**运行时 API——是 `config.yaml` 里 `platforms.api_server.extra.model_routes`
一段静态映射，gateway 启动时读入一次（见 §5）。

**诚实标注一个尺度落差**（PRE-① 已预见，本轮 e2e 证实）：这条路径实现的是「每个预先在 config.yaml
里登记的 alias 各自绑定一个 upstream key/base_url」，不是「运行时对任意新建 session 现铸现分配一个
key」。要新增一个 alias，需要编辑 `config.yaml` 后**重启整个 gateway 进程**——这是本轮唯一实测且
源码支持的路径。`gateway/platforms/api_server.py:5619` 附近的注释提到 `/platform resume
api_server`，但那是端口绑定失败（`EADDRINUSE`）后的恢复手段，`gateway/slash_commands.py:
1204-1237` 显示 `/platform resume` 只对已进入 `_failed_platforms` 且处于 paused 的平台生效，
对正常 connected 的 api_server 执行会直接返回"nothing to resume"（T-055 对抗复核纠正：**不存在**
靠这条命令热加载新 alias 的路径）。这与"运行时任意下发"之间仍有一步距离，PRE-① 原文已用"配置时静态
登记，不是运行时任意动态下发"准确预告过这一点，本轮 e2e 未推翻也未加宽这个判断，只是把"静态登记这条
路径本身能不能打通到真实计费归因"从理论坐实为实测。

---

## 1. 依赖安装（venv 隔离，非 editable install）

```bash
SCRATCH=<scratchpad>                      # 本轮用 .../scratchpad
cd "$SCRATCH"
uv venv --python 3.11 hermes-venv         # pyproject.toml:20 requires-python ">=3.11,<3.14"

# 非 editable install——用位置参数传源码路径（不是 -e .），
# 这样 setuptools 在临时目录构建 wheel，装进 venv 的 site-packages。
# 但这**不代表**源码目录一干二净：setuptools 仍会在源码目录本身留下
# build/ 与 hermes_agent.egg-info/（详见下方坑 1，装完必须清理并核对）。
uv pip install --python "$SCRATCH/hermes-venv/bin/python" \
  /path/to/kernels/hermes

# api_server 平台需要 aiohttp（gateway/platforms/api_server.py:77-81 try/except 兜底，
# 但不装就直接不可用）——aiohttp 只在 messaging/slack/matrix/sms/teams/homeassistant
# 几个 extra 里，装那些 extra 会连带拉 python-telegram-bot/discord.py 等一堆用不上的
# 依赖，本轮直接单独装 aiohttp 更干净：
uv pip install --python "$SCRATCH/hermes-venv/bin/python" "aiohttp==3.14.1"
```

**坑 1（`[实测]`，T-055 复核收窄）：普通（非 editable）install 仍会在 submodule 里留下
`build/` 目录**和** `hermes_agent.egg-info/` 目录，两者都要清理。**
`uv pip install <path>`（哪怕不带 `-e`）触发 setuptools 的标准 build 流程时，会在**源码目录本身**
（不是 venv、不是 scratchpad）创建 `build/bdist.*` + `build/lib/*` staging 目录（entire 源码树拷了一份
进去），**同时**也会生成 `hermes_agent.egg-info/`（`PKG-INFO`/`SOURCES.txt`/`entry_points.txt` 等）——
这不是只有 editable install 才有的问题，非 editable install 同样会落这个目录，此前 recipe 说"不会往
submodule 工作区写 egg-info 之类的东西"是**错误声称**（T-055 对抗复核现场反证：egg-info 目录留在
`kernels/hermes/` 直到本轮复核才发现并清理）。

`hermes_agent.egg-info/` 恰好被 `kernels/hermes/.gitignore:59` 一行遮蔽（`hermes_agent.egg-info/`），
所以**普通 `git status`/`git status --porcelain` 看不到它**，会造成"工作区干净"的假象。
**装完必须同时做三件事**：`rm -rf kernels/hermes/build kernels/hermes/hermes_agent.egg-info`，
然后核对 `git -C kernels/hermes status --porcelain`（应为空）**并且**
`git -C kernels/hermes status --ignored --short`（应为空，专门用来抓被 `.gitignore` 遮蔽的残留）。
只核对不带 `--ignored` 的 `git status` 不足以证明"submodule 工作区无残留"。

**坑 2（`[实测]`）：任何不带 `HERMES_HOME` 的 `hermes` CLI 调用都会碰用户全局 `~/.hermes`。**
本轮最初跑 `hermes --help`/`hermes gateway --help` 这类看起来"只读、不会有副作用"的命令时，**没有**
显式设置 `HERMES_HOME`，结果在 `~/.hermes/logs/` 下创建了两个空文件（`agent.log`/`errors.log`，
0 字节，见 `hermes_constants.py:56-64` `HERMES_HOME` 解析逻辑——未设时落到平台默认 `~/.hermes`）。
影响面很小（只有两个空日志文件，没有 config.yaml/state.db/凭证），但这是一个真实的隔离缝隙，已发现并
清理（精确删除那两个本轮产生的 0 字节日志文件后 `rmdir` 空目录，**不是** `rm -rf ~/.hermes`——那样会
误删宿主机既有用户状态；具体前置校验+精确删除脚本见 §7 收尾清理）。**教训：隔离 recipe 里的每一条
`hermes` 命令都要显式带 `HERMES_HOME`，包括看起来无害的 `--help`。** 类比 openclaw recipe 里记录的
"`/tmp/openclaw/openclaw-<date>.log` 是个不受 state dir 控制的全局固定路径"那条已知隔离缝隙
（`OPENCLAW-ISOLATED-RUN-RECIPE.md` §5 末尾），hermes 这边是同一类问题的另一个实例。

---

## 2. 隔离 `HERMES_HOME` + 配置文件

`HERMES_HOME` 是 hermes 的状态根目录 env var 覆盖（`[源码]` `hermes_constants.py:64`
`os.environ.get("HERMES_HOME", "")`），一旦显式设置，`config.yaml`/`.env`/`state.db`/`sessions/`
等全部落在它下面（`[源码]` `hermes_constants.py:1187` `config.yaml` 路径解析、`:1202` `.env` 路径解析
均以 `HERMES_HOME` 为根；`[实测]` `hermes config path`/`hermes config env-path` 在设置
`HERMES_HOME="$SCRATCH/hermes-home"` 后分别打印 `$SCRATCH/hermes-home/config.yaml` /
`$SCRATCH/hermes-home/.env`，与预期一致）。

```bash
mkdir -p "$SCRATCH/hermes-home"
```

`$SCRATCH/hermes-home/.env`：

```bash
# API_SERVER_ENABLED/KEY/PORT/HOST 官方文档明确标注只走 env var（config.yaml 暂不支持这几个字段，
# website/docs/user-guide/features/api-server.md:427-432 "Not yet supported — use environment
# variables"）。
API_SERVER_ENABLED=true
API_SERVER_KEY=<openssl rand -hex 24 生成，本轮示例见 evidence 文档>
API_SERVER_PORT=8646
API_SERVER_HOST=127.0.0.1
```

`$SCRATCH/hermes-home/config.yaml`：

```yaml
# 默认 model 块只是给 _resolve_runtime_agent_kwargs() 无路由匹配时的兜底
# （gateway/platforms/api_server.py 里这个函数在 route 解析之前无条件调用一次，
# 见 §5），本轮两个真实 session 全部走下面 model_routes 别名，会完整覆盖
# api_key/base_url，不吃这个默认值。
model:
  provider: auto            # 必须是 auto/空——runtime_provider.py:1650-1682 的
                             # "provider auto 但 config.yaml 有显式 base_url 且不是
                             # 已知云厂商域名 → 走 OpenAI 兼容解析器" 分支靠这个触发
  base_url: "http://<newapi-host>:3000/v1"
  api_key: "<任一默认 token，仅用于兜底路径，不影响两个真实测试 session>"
  default: "kimi-for-coding"

platforms:
  api_server:
    enabled: true
    extra:
      # 官方 features/api-server.md 文档原文写"config.yaml: Not yet supported"，
      # 但那句话说的是 host/port/key 这几个 env-only 字段——model_routes 反而
      # *只能*走 config.yaml（源码 gateway/platforms/api_server.py:1024 docstring
      # 原文 "Config format (platforms.api_server.extra in the gateway config)"，
      # 且全仓搜索没有任何 MODEL_ROUTES 环境变量），文档这句话不覆盖这个字段，
      # 别被误导成"model_routes 也没法配"。
      model_routes:
        session-a:
          model: "kimi-for-coding"     # upstream 实际要打的模型名
          api_key: "<newapi token A>"  # per-route upstream 凭证，本轮即 per-session 归因载体
          base_url: "http://<newapi-host>:3000/v1"
        session-b:
          model: "kimi-for-coding"
          api_key: "<newapi token B>"
          base_url: "http://<newapi-host>:3000/v1"
```

`platforms.api_server.enabled: true` 这一行在源码里其实是多余的（真正决定平台是否启动的是
`.env` 的 `API_SERVER_ENABLED`，`[源码]` `gateway/config.py:2005-2006` `is_truthy_value(getenv(
"API_SERVER_ENABLED", ""))`），留着无害，图个配置自解释。

---

## 3. 起隔离 gateway

```bash
source "$SCRATCH/hermes-venv/bin/activate"
export HERMES_HOME="$SCRATCH/hermes-home"
hermes gateway run > "$SCRATCH/hermes-gw.log" 2>&1 &
```

`gateway run` 是前台命令（`hermes gateway --help` 里的说明："Run gateway in foreground (recommended
for WSL, Docker, Termux)"），适合隔离场景手动控制生命周期，对齐 openclaw recipe 用
`node scripts/run-node.mjs gateway`（同样前台跑 + 手动 kill）的做法。

`[实测]` 启动日志只有一行 WARNING（无 Telegram/Discord 等平台配置时的正常提示，不是错误）：
```
WARNING gateway.run: No env user allowlists configured. Messaging platforms default to
pairing/allowlist policies and will deny unknown senders unless you configure platform
allowlists...
```
`[实测]` 约 8 秒后端口进入 LISTEN：`lsof -iTCP:8646 -sTCP:LISTEN` 能看到该 Python 进程。

---

## 4. 健康判据

`[实测]`：
```bash
curl http://127.0.0.1:8646/health
# → {"status": "ok", "platform": "hermes-agent", "version": "0.19.0"}

curl http://127.0.0.1:8646/health/detailed -H "Authorization: Bearer $API_SERVER_KEY"
# → readiness.checks.{state_db,config,model,disk,gateway,background_queues} 全 "ok"，
#   platforms.api_server.state == "connected"
```
`/health` 不需要鉴权（公开存活探针），`/health/detailed` 需要 `API_SERVER_KEY`（`[源码]`
`website/docs/.../api-server.md:230-238` 描述与实测行为一致）。

---

## 5. per-session key 机制的源码坐实（零改动路径）

请求发到 `/v1/chat/completions`，body 里的 `"model"` 字段就是 alias 名（不是真实要打的模型名）：

1. `_resolve_route(model_alias)`（`[源码]` `gateway/platforms/api_server.py:1795-1799`）在
   `self._model_routes`（gateway 启动时由 `_parse_model_routes(extra.get("model_routes"))` 解析，
   `[源码]` `:1037-1039` 构造函数里调用）里查 alias，命中则返回该条目的
   `{model, provider?, api_key?, base_url?}`。
2. 三处 HTTP handler 都在派发前调用这个方法（T-055 对抗复核纠正映射错误）：
   `_handle_chat_completions` 的 `:2863`（`/v1/chat/completions`，本轮 e2e 实测走的正是这条）、
   `_handle_responses` 的 `:3983`（`/v1/responses`）、`_handle_runs` 的 `:5025`（`/v1/runs`）。
   **`/api/sessions/{session_id}/chat`**（`_handle_session_chat`，`gateway/platforms/api_server.py:
   2550-2575`）调用 `_run_agent` 时**不解析、也不传入 `route`**——这条路径不受 `model_routes`
   覆盖，**不在**本轮 e2e 闭合范围内，不要把"api_server 三个主 HTTP 入口都覆盖"误读成
   "api_server 下所有端点都覆盖"。
3. 拿到 `route` 后，在 `_run_agent`（构造 `AIAgent` 之前）里：
   - `route.get("model")` → 覆盖 `model`（`:1905`）
   - `route.get("api_key")` → 覆盖 `runtime_kwargs["api_key"]`（`:1910`）
   - `route.get("base_url")` → 覆盖 `runtime_kwargs["base_url"]`（`:1912`）
   - 若还给了 `route.get("provider")`（本轮未用），额外重新解析该 provider 的凭证链（`:1889-1901`）
   - 这一整段判断的前提是 `route and not session_override`（`:1885-1888`）——只有当会话没有显式
     `/model` 覆盖时，route 配置才生效，符合"静态路由是默认值、用户显式操作优先"的直觉
4. 最终 `AIAgent(model=model, **runtime_kwargs, ...)`（`:1930` 附近）拿到的就是这一路由专属的
   `api_key`/`base_url`——**这条链路里没有任何一步碰 `kernels/hermes` 源码，是配置驱动的既有生产
   代码路径**，PRE-① 报告 §2.4 的判定在本轮 e2e 里精确复现。

---

## 6. 已知隔离缝隙（诚实记录，非阻断项）

- **`~/.hermes/logs/` 边界泄漏**（见 §1 坑 2）：任何不带 `HERMES_HOME` 的裸 `hermes` 调用都会摸到
  用户全局家目录，哪怕只是 `--help`。本轮已发现两个空日志文件并**精确清理**（前置校验确认
  `~/.hermes` 内没有 config.yaml/state.db/sessions/ 等既有用户状态，只删本轮产生的 0 字节
  `agent.log`/`errors.log`，目录清空后才 `rmdir`——**不是** `rm -rf ~/.hermes`，那样在复用场景下
  可能连带删掉宿主机既有用户数据；具体脚本见 §7）。**后续复用本 recipe 时，每一条 `hermes ...`
  命令前都应显式 `export HERMES_HOME=...` 或用 `HERMES_HOME=... hermes ...` 内联形式，不留任何
  窗口期。**
- **`build/` + `hermes_agent.egg-info/` 构建产物**（见 §1 坑 1）：`uv pip install <源码路径>`
  （非 editable）仍会在源码目录里同时留下 `build/` 和 `hermes_agent.egg-info/`——后者被
  `.gitignore:59` 遮蔽，普通 `git status` 看不到。装完必须 `rm -rf` 两者，并且核对同时用
  `git status`（tracked）**和** `git status --ignored --short`（ignored）两条命令确认干净，
  才算隔离达标；只查前者会漏看 egg-info 残留（T-055 对抗复核现场即抓到这个漏洞）。
- **model_routes 是静态配置**（见 §0 结论）：新增一个 per-session alias 需要重启整个 gateway
  进程；`gateway/platforms/api_server.py:5619` 注释里的 `/platform resume api_server` 只是端口
  绑定失败（`EADDRINUSE`）后的恢复手段，`gateway/slash_commands.py:1204-1237` 显示 `/platform
  resume` 只对已进入 `_failed_platforms` 且处于 paused 状态的平台生效——正常 connected 的
  `api_server` 执行它会直接返回"nothing to resume"，**不能**用来热加载新增的 model_routes
  alias（T-055 对抗复核纠正：recipe 早期版本误将这条端口恢复路径当成配置热重载手段）。这不是
  hermes 的缺陷，是 PRE-① 报告已预告的"配置时静态登记 vs 运行时任意下发"之间的既有差距，本轮
  e2e 的作用是坐实"静态登记这条路径本身能不能打通到真实计费归因"，答案是能。

---

## 7. 收尾清理（`[实测]`）

```bash
kill -TERM <gateway PID>     # 优雅退出，$SCRATCH/hermes-home/.clean_shutdown 会被写入
lsof -iTCP:8646 -sTCP:LISTEN # 应无输出（端口已释放）
ps aux | grep -i hermes | grep -v grep   # 应无残留进程

# submodule 工作区核对——tracked + ignored 都要查（见坑 1，egg-info 被 .gitignore 遮蔽）：
rm -rf kernels/hermes/build kernels/hermes/hermes_agent.egg-info
git -C kernels/hermes status                        # nothing to commit, working tree clean
git -C kernels/hermes diff                          # 空
git -C kernels/hermes status --ignored --short       # 空（专门确认无被忽略的残留）

# 清理 §6 提到的 ~/.hermes 边界泄漏——不要粗暴 rm -rf 整个目录，它可能是宿主机
# 既有的用户状态目录。先做前置校验：只有当里面看起来只是本轮裸 CLI 意外创建的
# 空日志文件时才精确删除，目录清空后才 rmdir；一旦发现 config.yaml/state.db/
# sessions/ 等既有用户状态迹象，就不要动，只报告。
if [ -f ~/.hermes/config.yaml ] || [ -f ~/.hermes/state.db ] || [ -d ~/.hermes/sessions ]; then
  echo "~/.hermes 存在既有用户状态，跳过自动清理，人工确认后再处理 logs/ 下的空文件" >&2
else
  for f in ~/.hermes/logs/agent.log ~/.hermes/logs/errors.log; do
    # -s 判断非空——只删本轮产生的 0 字节文件，非空文件一律不碰。
    [ -f "$f" ] && [ ! -s "$f" ] && rm -f "$f"
  done
  rmdir ~/.hermes/logs 2>/dev/null   # 目录非空会静默失败，不会误删仍有内容的目录
  rmdir ~/.hermes 2>/dev/null
fi
```
`hermes-venv/` 与 `hermes-home/` 均留在 scratchpad，自然回收（throwaway，不入版本控制）。

完整 e2e 归因证据（新建的两个 new-api token、两次真实 Kimi 往返、`new-api /api/log/` 逐字段核对）
见 `app/kernel-client/HERMES-RUN-EVIDENCE.md`。
