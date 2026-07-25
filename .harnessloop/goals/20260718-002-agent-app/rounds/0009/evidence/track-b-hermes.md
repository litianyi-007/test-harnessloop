# rounds/0009 轨 B（hermes 侧）证据：SG-8.2 token 自查互验 + SG-8.3 PRE-7 replay 阈值 + hermes-steer 冒烟

> 执行者：写入子代理（Sonnet 5）。零内核源码改动（见文末核验）。全程只读
> `kernels/hermes` 源码坐实机制，探针本身用 hermes-agent 自己的公开库 API
> （`acp` client SDK、`hermes_state.SessionDB`）驱动，未绕过/未改写任何协议实现。
> 隔离环境复用 `app/kernel-client/HERMES-ISOLATED-RUN-RECIPE.md`（rounds/0008）留在
> scratchpad 的 `hermes-venv/`、`hermes-home/`（recipe 明确设计为可复用 throwaway）。
> 本轮**未启动 `hermes gateway run`**（HTTP api_server 平台），全程走 ACP stdio 传输
> （`hermes-acp` 二进制），**未占用任何 TCP 端口**，因此不存在与 18789/3000/3001/8646
> 撞端口的风险——ACP 是纯 stdio JSON-RPC，无网络监听。

---

## 0. 环境准备（补装 ACP 依赖）

rounds/0008 的 recipe 只为 `api_server` 平台装了 `aiohttp`，没有装 ACP 所需的
`agent-client-protocol` extra（`pyproject.toml:221` `acp = ["agent-client-protocol==0.9.0"]`）。
复用的 `hermes-venv` 里确认缺失（`import acp` → `ModuleNotFoundError`），本轮补装：

```
uv pip install --python <scratchpad>/hermes-venv/bin/python "agent-client-protocol==0.9.0"
# Resolved 6 packages, Installed 1 package: agent-client-protocol==0.9.0
```

`hermes-acp --check`（设 `HERMES_HOME` 后）→ `Hermes ACP check OK`。

补装前后均核验 `kernels/hermes` 零改动（`git status`/`--ignored --short` 均空，见 §6）——
这是一次纯 PyPI 包安装，不触碰 hermes 源码树,和 rounds/0008 recipe 记录的
"非 editable install 仍在源码目录留 build/+egg-info" 那个坑不是同一件事（那是装
`hermes-agent` 本体才会触发；装一个独立的第三方 extra 包不会）。

---

## 1. SG-8.2：token 自查互验（D1 §11 C-3 指定验法 vs new-api 实况）

### 1.1 指定验法核验：`GET /api/log/self` 不可行——权限模型与假设不符

D1 §11 C-3 指定的验法原文：「可通过各自查询 `/api/log/self?token_name=...` 互相验证隔离性」。
实测：

```
curl -H "Authorization: Bearer <sk-token-A>" \
  "http://10.244.132.76:3000/api/log/self?p=0&page_size=10"
→ {"message":"Unauthorized, invalid access token","success":false}
```

`/api/log/self` 需要的是**已登录用户会话**（cookie + `New-Api-User` header，经
`POST /api/user/login` 拿到），**不接受**裸 API token（`sk-...`）作为 `Authorization: Bearer`
凭证。对照实验：用 root 的登录 cookie 调同一端点 → `success:true`，5 条记录——证明该端点本身
工作正常，只是鉴权模型是"用户会话"级，不是"token 自持"级，与 D1 假设的"token 直接查自己"不符。

**判定：指定验法不可行——`/api/log/self` 的鉴权模型是 user-session，不是 token-self-service。**

### 1.2 替代验法：`GET /api/log/token`（`Authorization: Bearer <token>`）

同一份 new-api 实况调研（`.hopper/handoffs/T-005-output.md:361`）另外记录了一个端点
`GET /api/log/token?key=` 标注"公开（持 token key）"。实测发现该端点确实存在且按 token 自身
鉴权，但**鉴权方式与 T-005 描述不完全一致**：

```
curl "http://10.244.132.76:3000/api/log/token?key=<sk-token-A>"
→ {"message":"Token not provided","success":false}   # 裸 query 参数不work

curl -H "Authorization: Bearer <sk-token-A>" \
  "http://10.244.132.76:3000/api/log/token"
→ {"success":true,"data":[...三条记录...]}             # Bearer header 才work
```

即该端点**真实鉴权机制是标准 `Authorization: Bearer` header**，不是 T-005 记录的裸
`?key=` 查询参数（该参数在本实例上无效）——这是本轮发现的 new-api 实况与既有调研文档的
一处细节出入，一并记入。

### 1.3 互查不串号（复用 SG-7 既有计费记录，未新调 Kimi）

复用 rounds/0008 SG-7 已产生的记录（`app/kernel-client/HERMES-RUN-EVIDENCE.md` B.3）：
new-api 全局 log id=43/44/45 属于 token_id=4（`sg7-hermes-session-a`），id=46 属于
token_id=5（`sg7-hermes-session-b`）。

| 查询方 | Authorization | 返回条数 | 返回记录的 token_id/token_name | 是否含对方数据 |
|---|---|---|---|---|
| token A（session-a） | `Bearer <token-A>` | 3 | 全部 `4 / sg7-hermes-session-a` | **否**（0 条 token_id=5） |
| token B（session-b） | `Bearer <token-B>` | 1 | 全部 `5 / sg7-hermes-session-b` | **否**（0 条 token_id=4） |

（注：该端点返回体里的 `id` 字段是查询结果集内的局部序号——本次 A 的结果里显示
`id:1,2,3`——不是 new-api 全局 log 主键；用 `request_id` 交叉核对确认这三条正是全局
`log id=43/44/45`，与 root 管理面 `GET /api/log/?p=0&page_size=60` 的全量记录逐字段吻合。
这是本轮发现的又一处 API 实况细节：消费该端点时不能用其自带的 `id` 字段做全局对账，
需要用 `request_id` 或 `token_id`/`token_name`。）

**对抗测试（参数注入）**：用 token A 的 Bearer，同时在 query string 里显式注入
`token_name=sg7-hermes-session-b` 试图扩大查询范围：

```
curl -H "Authorization: Bearer <token-A>" \
  "http://10.244.132.76:3000/api/log/token?token_name=sg7-hermes-session-b&p=0&page_size=20"
→ 仍然只返回 (token_id=4, token_name=sg7-hermes-session-a)，B 的数据未泄漏
```

参数被忽略，鉴权严格以 Bearer token 自身为准，无法通过查询参数扩大可见范围。

**全程未新调用 Kimi**——完全复用 SG-7 既有计费日志，符合"能不调 Kimi 就不调"的要求。

### 1.4 SG-8.2 判定

**指定验法不可行**（`/api/log/self` 是 user-session 鉴权，token 无法直接用）；**替代验法为
`GET /api/log/token`（`Authorization: Bearer <token>`）**；**结论：PASS**——互查不串号（含
参数注入对抗测试），token 级归因隔离在 new-api 侧真实生效。副产品：更正了 T-005 对该端点
鉴权方式（应为 header 而非 query 参数）与 `id` 字段语义（局部序号而非全局主键）的两处描述。

---

## 2. SG-8.3 · PRE-7：`session/load` 历史 replay 阈值判定

### 2.1 探针设计（零真实 LLM 调用注入历史）

Pre-1 研究 §1.7（`~/.llm-wiki/agent-app-design/research/pre1-hermes-source-conformance.md`）
指出 `_replay_session_history`（`acp_adapter/server.py:1023-1111`）是"尽力而为"设计，具体退化
边界"需要 runtime 才能定论"。本轮走 scope-lock 允许的最优路径——**不真调 LLM 注入历史**：

1. 用真实 ACP 会话（`initialize` + `new_session`）铸造一个真实 `session_id`。
2. 该进程退出后，用 hermes 自己的公开持久化 API `hermes_state.SessionDB.append_message`
   （`hermes_state.py:4985`——真实 AIAgent 每轮结束后写历史用的**同一个**方法，不是手写 SQL
   绕过 schema）向该 session 写入 20 条消息（10 组 user/assistant，内容带
   `[SEED-NN-USER/ASSISTANT]` 标记，全程零 LLM 调用）。
3. 用**全新的独立 `hermes-acp` 子进程**（每次都是冷启动，模拟编辑器断线重连）调用
   `session/load`，计时 + 收集 `session_update` 通知，核对条数/顺序/耗时。

### 2.2 首次发现：阻断性 bug——`model.provider: auto` 下 session/load 首次成功、此后必现失败

用 rounds/0008 recipe 原样的 `model.provider: auto` 配置起步，第一次 `session/load`
（进程 A，session 刚种好 20 条消息后的首次冷加载）**成功**：20/20 条、顺序正确、耗时 1.217s。
但**此后所有独立子进程的 `session/load` 调用（无论是否与第一次同进程）全部返回 0 条历史**，
**100% 复现**（先后用同进程连续 3 次、以及 3 个完全独立的 OS 进程分别单独验证，结果一致）。

**根因定位（源码级，非猜测）**——用 `stderr` 继承打开子进程日志直接抓到完整 traceback：

```
WARNING agent.auxiliary_client: resolve_provider_client: openrouter requested but OPENROUTER_API_KEY not set
WARNING acp_adapter.session: Failed to recreate agent for ACP session <id>
Traceback (most recent call last):
  File ".../acp_adapter/session.py", line 551, in _restore
    agent = self._make_agent(...)
  File ".../acp_adapter/session.py", line 651, in _make_agent
    agent = AIAgent(**kwargs)
  File ".../run_agent.py", line 499, in __init__
    init_agent(...)
  File ".../agent/agent_init.py", line 1226, in init_agent
    raise RuntimeError(
RuntimeError: No LLM provider configured. Run `hermes model` to select a provider, ...
WARNING acp_adapter.server: load_session: session <id> not found
```

机制链条（逐文件 `file:line` 核对）：

1. `_make_agent`（`acp_adapter/session.py:590-659`）在**创建**会话时（`create_session`，
   无 `requested_provider` 参数）调用 `resolve_runtime_provider(requested=config_provider)`
   = `"auto"`；`runtime_provider.py:1649-1684` 的"auto + 自定义 base_url"旁路命中
   （`cfg_provider in ("auto","")`），走 `_resolve_openrouter_runtime`，其内部
   `requested_norm=="auto"` → `use_config_base_url=True` → 正确取用 `config.yaml` 里的
   `base_url`/`api_key`（我们的 Pi new-api），**成功**。
2. 但 `_resolve_openrouter_runtime` 对**任何**非字面 `"custom"` 的 `requested` 值，一律把
   `effective_provider` 标记成字面量 `"openrouter"`（`runtime_provider.py:1165-1169`
   注释原文"instead of silently relabeling to 'openrouter'"——这行注释描述的是"custom"该被
   保留，隐含"其余情况都会被 relabel 成 openrouter"这一事实）——即便实际走的是我们自己的
   Pi 而非真·OpenRouter。
3. `_persist`（`session.py` 约 410-470，PRE-1 §2.2 已引用其片段）把这个**内部标签**
   `state.agent.provider == "openrouter"` 原样写回 `model_config` JSON 持久化。
4. 下一次 `_restore`（`session.py:497-576`）从这条持久化记录读出
   `requested_provider = "openrouter"`（不再是 `"auto"`！）传给 `_make_agent`，
   `resolve_runtime_provider(requested="openrouter")` 里 `requested_norm=="openrouter"`
   （非 `"auto"`），**不再命中**第 1 步那条"auto+自定义 base_url"旁路——落入
   `should_use_pool` 分支，要求真实 `OPENROUTER_API_KEY`（我们的部署里没有，也不该有，
   因为从未真正打算连 OpenRouter），最终 `init_agent` 抛
   `RuntimeError: No LLM provider configured`。
5. 该异常被 `_restore` 自己的 `except Exception: return None` 吞掉（`session.py:559-561`），
   `get_session`/`update_cwd` 因此返回 `None`，`load_session`（`server.py:1140-1143`）打印
   `"load_session: session <id> not found"` 后 `return None`——但 ACP 客户端收到的**不是**
   一个能感知失败的错误响应，而是一个字段全 `None` 但**非 `None` 对象本身**的
   `LoadSessionResponse(field_meta=None, config_options=None, models=None, modes=None)`，
   与"加载成功但会话恰好没有历史"在结构上**无法区分**——一个只检查"resp is not None"的朴素
   客户端会误判为成功。

**这是一个确定性（非"高延迟/大历史场景下尽力而为"式的偶发丢失）、100% 可复现的 ACP 会话
持久化↔恢复往返 bug，且失败被静默吞掉，比 Pre-1 §1.7 原本担心的"部分丢失"更严重（是
"零复原"且"看起来像成功"）。** 影响面：任何用 `model.provider: auto` + 非知名云厂商域名
`base_url`（自建/自代理场景的典型配置，例如本项目一直在用的 new-api）部署、且未配置真实
`OPENROUTER_API_KEY` 的 hermes ACP 部署，**首次连接正常，任何后续重连（`session/load`/
`session/resume`）都会静默拿到空历史**。

**与 rounds/0008 (SG-7) 结论的关系（不矛盾）**：SG-7 验证的是 `api_server` HTTP 平台
`model_routes` 路径，该路径的凭证覆盖发生在 `_run_agent` 里按请求读取
`route.get("api_key")`/`route.get("base_url")`（`api_server.py:1900-1913`），**完全不经过**
本节这条 `_make_agent`→`_persist`→`_restore` 往返链路——两者是 hermes 里两条独立的会话/凭证
管理路径，SG-7 的"零改动、归因可靠"结论不受本发现影响，本发现是 **ACP 会话持久化路径**
特有的问题。

**建议**：登记为 harnessloop evolution issue / PRE-①-conformance 修正候选（面向 hermes
上游或本项目部署文档：ACP 部署若用 `model.provider: auto` + 自定义 base_url，必须避免
provider 标签被回写覆盖，或部署时显式设 `provider: custom` 规避）。

### 2.3 变通复测（配置层规避，零内核改动）

把 `hermes-home/config.yaml`（scratchpad throwaway 配置，非 recipe 交付物）的
`model.provider` 由 `auto` 改成 `custom`（纯数据/配置改动，不碰 `kernels/hermes` 一行代码）。
原理：`custom` 是字面量，`_resolve_openrouter_runtime` 内 `effective_provider = "custom" if
requested_norm == "custom" else "openrouter"`（`runtime_provider.py:1169`）不会被 relabel，
`_persist`/`_restore` 往返写回读回的都还是 `"custom"`，create 与 restore 走同一分支，
不再有非对称性。

**验证**：新建一个干净 session（`c11e1093-a061-4244-a280-ac8d22c26df9`），种入同样 20 条
消息，随即 `session/load` 一次确认可用（日志 `Restored ACP session ... from DB (20 messages)`
+ `Loaded session ...`），随后连续 3 次**独立冷启动**子进程做正式阈值测量。

### 2.4 阈值测量结果（3 次独立冷加载）

| 轮次 | 消息条数（应=20） | 顺序 | 耗时 | ≤10s |
|---|---|---|---|---|
| 1 | 20/20 | 正确（SEED-01..10，user→assistant 交替） | 0.792s | ✅ |
| 2 | 20/20 | 正确 | 0.815s | ✅ |
| 3 | 20/20 | 正确 | 0.803s | ✅ |

三轮一致（条数、顺序完全相同），耗时稳定在 ~0.8s，远低于 10s 阈值。

**PRE7_REPLAY_VERDICT: PASS**（对照 scope-lock 阈值：≥20 条不丢顺序保持 / ≤10s / 连续 3 次
一致，三项全部满足）。**但本判定成立的前提是规避了 §2.2 记录的 provider-relabel bug**——
若不做这个配置层变通，用 recipe 原始的 `provider: auto` 配置，阈值判定会是
**FAIL（0/20，非部分丢失而是完全空载）**，这一点必须与 PASS 判定一并读、不能只读 PASS。

---

## 3. SG-8.3 · hermes-steer-runtime 冒烟（对照 D1 v3.6 hermes-steer 修订）

背景对照（D1 v3.6，`~/.llm-wiki/agent-app-design/kernel/d1-kernelport-spec-v3-6.md`）：
ACP 线路 `interruptModes` 含 `'steer'`，映射 `/steer <text>` → `state.is_running` 时走
`_cmd_steer`（`acp_adapter/server.py:1989-2006`）真实调用 `AIAgent.steer()`（同 run 软注入，
非中断）；空闲时命中 `prompt()` 顶部的 idle-rewrite（`server.py:1323-1354`），整段重写成一次
全新 prompt turn。v3.6-r1（T-040）额外澄清：`PromptResponse`（ACP 0.9.0）虽有 `_meta`/
`user_message_id` 字段，但 hermes server 全部 6 处构造点从未填充，真注入/idle 降级在
RPC 层"无机器可读判别字段"，只能靠人类可读的 `session_update` 文本与耗时区分。

### 3.1 运行中注入（`state.is_running == True`）

新建干净 session（`c59eb3a4-d7bc-4d50-b661-0b9bf153c399`），并发发出两个 `prompt()`：

- 主 turn：`"Please write a short (150-200 word) paragraph explaining what a
  write-ahead log is..."`（无工具调用，纯文本作答）。
- 0.6s 后（主 turn 仍在 `is_running`，此时刚开始等待上游响应）：`"/steer please also
  mention the word PINEAPPLE-7d4414a3 in your reply"`。

实测结果：

| 请求 | 起始(相对 t0) | 返回(相对 t0) | 耗时 | stop_reason |
|---|---|---|---|---|
| 主 turn | 0.000 | 9.335 | 9.335s | `end_turn` |
| steer | 0.602 | 0.604 | **0.002s** | `end_turn` |

steer 请求在主 turn 仍在跑（远未到 9.3s 完成点）时**几乎瞬时返回**，且返回前先收到一条
`session_update`（`agent_message_chunk`）：

```
t=0.604 text='⏩ Steer queued for the active turn: please also mention the word PINEAPPLE-7d4414a3 in your reply'
```

与源码 `_cmd_steer` 第 1996-1998 行的字面拼接 `f"⏩ Steer queued for the active turn: {preview}"`
逐字节吻合——**确认真软注入路径被触发**（`state.is_running` 为真时命中
`state.agent.steer(steer_text)` 分支，不是排队/拒绝）。

**但**：主 turn 最终产出的完整回答文本里**未出现** `PINEAPPLE` 标记——只在上面的 ack 回显里
出现过。这与 `AIAgent.steer()` 文档化语义完全一致：注入文本"stashed and appended to the
LAST tool result's content once the current tool batch finishes"——而本次主 turn **全程没有
调用任何工具**（模型判断"doesn't require any tools"），没有"下一次工具结果"这个挂载点可用，
所以注入在 RPC/state 层面"被接受"（`submitted`）但从未真正影响到最终输出——**这正是
D1 v3.2/v3.6 反复强调的"`submitted` 不承诺已注入生效，只承诺 RPC 被接受"的真实、可观察实例**，
不是矛盾，是对该设计约束的一次运行时坐实。

### 3.2 空闲注入（`state.is_running == False`）

全新 session（`38852a82-f66c-4a01-8245-1d405fb144dc`），从未发过任何 prompt，直接把
`/steer reply with exactly the single word MANGO-a539c56c and nothing else` 作为**第一条**
消息发出。

实测：耗时 **4.117s**（`stop_reason=end_turn`），事件流里**没有**"Steer queued for the active
turn"文本，也**没有**`_cmd_steer` else 分支的"No active turn — queued for the next turn"
文本——说明请求根本没有进入 `_cmd_steer`。逐条 `agent_thought_chunk`/`agent_message_chunk`
显示模型把 `/steer` 之后的内容当成了一句**普通用户消息**在理解并执行（reasoning 里明确写
"The user wants me to reply with exactly the single word 'MANGO-a539c56c' and nothing else"），
最终输出的 `agent_message_chunk` 拼接结果精确等于 `MANGO-a539c56c`。

行为分类：**降级（idle-rewrite）**，与源码 `server.py:1323-1354` 预期完全一致——`/steer` 在
空闲会话上被整体重写为一次全新的普通 prompt turn，不经过 `_cmd_steer`，无 ack 文案，耗时是
完整一次真实 LLM 轮次（4.1s，对照运行中注入场景的 0.002s，两者耗时差 3 个数量级，是清晰、
可复现的可观测分野）。

### 3.3 机器可读判别字段核验（v3.6-r1/T-040 澄清点的运行时坐实）

直接打印两种响应的完整 repr：

```
主 turn: PromptResponse(field_meta=None, stop_reason='end_turn',
          usage=Usage(cached_read_tokens=..., ...), user_message_id=None)
steer  : PromptResponse(field_meta=None, stop_reason='end_turn',
          usage=None, user_message_id=None)
```

两者 `field_meta`/`user_message_id` 均为 `None`——确认 hermes server 未在任何一次
`PromptResponse` 构造里填充这两个 steer 可能相关的结构化字段，与 D1 v3.6-r1（T-040 收残）
的源码结论逐字吻合，本轮属运行时独立复核确认，**未发现矛盾**。

### 3.4 hermes-steer 冒烟判定

**PASS**——两场景真实行为与 D1 v3.6 hermes-steer 修订（三入口设计里的 ACP 入口、"二态
`submitted`/`rejected`"、"idle 时整段重写为新 turn"、"无机器可读判别字段，只能靠
`session_update` 文本+耗时区分"）**完全吻合，未发现矛盾**。额外的运行时观察（"submitted 不
保证真的影响到最终输出，取决于该 turn 是否有工具调用作挂载点"）不是对 D1 的推翻，是对 D1
既有"`submitted` 只承诺 RPC 被接受"这条声明的一次具体、可复现的实例佐证。

---

## 4. 零内核源码改动核验

补装 `agent-client-protocol` 前后、全部探针跑完后：

```
$ git -C kernels/hermes status --short
（空）
$ git -C kernels/hermes status --ignored --short
（空）
$ git -C kernels/hermes diff --stat
（空）
$ git -C kernels/hermes log -1 --oneline
17155e3ae chore(contributors): add email mappings for slack thread-lifecycle salvage
```

pin 与 rounds/0008 一致（`17155e3ae04d376dd8eba2e65f3dd966e67ab1ba`），未漂移。

---

## 5. 收尾

- 进程：全部探针均以 `async with acp.spawn_agent_process(...)` context manager 驱动子进程，
  退出时自动关闭；`ps aux | grep -i hermes` 收尾核对**无残留进程**。
- 端口：本轮全程 ACP stdio 传输，**未监听/占用任何 TCP 端口**（`lsof -iTCP:8646` 等收尾核对
  均无输出）——与 openclaw 轨 A 的端口占用完全无交集。
- `hermes-venv/`、`hermes-home/` 按 recipe 惯例留在 scratchpad（throwaway，自然回收）；
  本轮往 `hermes-home/config.yaml` 做的 `provider: auto → custom` 改动**只影响这份
  scratchpad throwaway 配置**，不是对 `HERMES-ISOLATED-RUN-RECIPE.md`（已交付文档）的修改，
  该 recipe 文件本身未改动。
- `.harnessloop/local/channel-params.json` 未新增参数，全程复用已登记的
  `NEWAPI_SG7_HERMES_SESSION_A/B_TOKEN`。
- 本轮新建的 4 个 ACP session（seed-broken 用于复现 §2.2 bug、seed-custom 用于 §2.4 正式
  测量、steer-running、steer-idle）均落在 scratchpad `hermes-home/state.db`，throwaway，
  不做进一步清理（与 recipe 惯例一致）。

---

## 6. 报告摘要（供主会话/审查闸引用）

| 子项 | 判定 | 关键数据 |
|---|---|---|
| SG-8.2 token 自查互验 | **PASS**（指定验法不可行,替代验法为 `GET /api/log/token`+Bearer,结论 PASS） | A/B 互查零串号,含参数注入对抗测试;零新 Kimi 调用 |
| SG-8.3 PRE-7 replay 阈值 | **PASS**（但发现前置阻断 bug,已记录+规避,见下） | 20/20 条,顺序保持,0.79-0.82s(≤10s),3 次一致 |
| **发现**：ACP `provider: auto`+自定义 base_url 下 session/load 首次成功、此后 100% 静默返回 0 条历史 | **conformance 修正候选**（比 Pre-1 §1.7 预期的"部分丢失"更严重） | 根因 `session.py:551/651`→`runtime_provider.py:1169`→`server.py:1140-1143`,traceback 见 §2.2;不影响 SG-7 api_server 路径结论 |
| SG-8.3 hermes-steer 冒烟 | **PASS**（与 D1 v3.6 完全吻合,无矛盾） | 运行中:0.002s 返回+确定性 ack 文案;空闲:4.1s 全新 turn 无 ack;两者 `field_meta`/`user_message_id` 均 None |
| 零内核改动 | **PASS** | `git status`/`--ignored --short`/`diff --stat` 三查均空 |
