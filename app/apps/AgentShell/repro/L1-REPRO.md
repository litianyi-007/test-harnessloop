# SG-10 L1 复现步骤（无秘密）

**目的**：让任何人在一台干净机器上复现 rounds/0012 的 L1 验证——UI 起得来、对隔离 openclaw 真实往返、消息分组修复生效。

**本文件不含任何凭证。** 所有秘密以**参数名**给出，值从 `.harnessloop/local/channel-params.json`（gitignored）或环境变量注入。

---

## 0. 前置

| 依赖 | 版本/要求 | 检查 |
|---|---|---|
| macOS | **14+**（`app/Package.swift` 声明 `.macOS(.v14)`） | `sw_vers -productVersion` |
| Xcode CLT / Swift | 6.x（本轮实测 6.3.3） | `swift --version` |
| Node | **`>=22.22.3 <23 \|\| >=24.15.0 <25 \|\| >=25.9.0`**（`kernels/openclaw/package.json` 的 `engines`） | `node --version` |
| pnpm | **11.2.2**（openclaw 声明的 `packageManager`，**不是 npm**） | `pnpm --version` |
| provider | **openclaw 内建 provider id**（见下方 §provider） | — |

```bash
git submodule update --init --recursive
cd kernels/openclaw && pnpm install --frozen-lockfile && cd -
```

### §provider：内建 id 与自定义 id 的区别（**别照抄"任何 OpenAI 兼容 provider 都行"**）

`kernels/openclaw/src/config/zod-schema.core.ts` 的 `ModelProvidersSchema.superRefine`：**非内建 provider id 必须同时声明 `baseUrl` 与 `models`**，否则配置校验失败；内建 id（`isBuiltInModelProviderOverlayId`）豁免。

- **用内建 id**（`deepseek`/`openai`/`anthropic` 等，清单见 `src/config/types.models.ts`）：只需 `baseUrl` + `apiKey`。本轮实测即此路径。
- **用自定义 id**：还须补 `models: [{...}]` 数组。

> 原文写「任何 OpenAI 兼容 provider 都可替换」是**错的**（过宽）；评审提的「必须声明 models」也**不是无条件成立**（漏了内建豁免）。以上是实测 + 源码核对后的准确表述。

## 1. 构建

```bash
swift build --package-path app                    # 5 个 target
./app/.build/debug/frame-replay-tests             # 期望 40/40 PASS（rounds/0013 起，以实际输出为准）
./app/apps/AgentShell/build-app-bundle.sh         # 产出 app/.build/AgentShell.app
```

## 2–3. 起隔离 openclaw（用脚本，不要手抄命令）

手抄多步命令会踩三个坑：gateway 前台运行后无法继续、另开终端拿不到 `ISO/PORT/TOKEN`、`cd kernels/openclaw` 之后相对路径失效。**所以这两步已封装成脚本**：

```bash
export L1_PROVIDER_ID=deepseek                 # 必须是内建 id，见 §provider
export L1_PROVIDER_BASE_URL=...                # 从你的凭证来源注入，切勿写进任何 tracked 文件
export L1_PROVIDER_API_KEY=...
export L1_MODEL_ID=deepseek-v4-flash

./app/apps/AgentShell/repro/start-isolated-kernel.sh
source /tmp/l1-repro/conn.env                  # 导出 ISO / PORT / TOKEN / AGENT_SHELL_KERNEL_*
```

脚本做的事（读它本身，92 行，无隐藏行为）：**每次重建全新隔离目录**（干净起点的卫生默认值，见 §5）→ 自动选空闲端口 → 生成 `openclaw.json`（用 python 写，避免占位符不展开）→ **后台**起 gateway → 等 `[gateway] ready` → **隔离自检**（实例自报的 `log file:` 必须落在隔离目录内，否则报错退出）→ 写出 `conn.env`。

**`conn.env` 只在 gateway 就绪且隔离自检通过后才生成**——它存在即代表这两件事都成立。

## 4. 三个必须设、少一个就破隔离的配置

| 配置 | 不设的后果 | 实证出处 |
|---|---|---|
| `OPENCLAW_STATE_DIR` | state/config/oauth 落到 `~/.openclaw` | recipe §1 |
| `OPENCLAW_WORKSPACE_DIR` | **一 `send` 就伸向 `~/.openclaw/workspace`** 并报 `Legacy workspace setup state requires migration` | rounds/0011 实测 |
| `logging.file`（配置项，**不是 env**） | 日志写进与用户实例**共享**的 `/tmp/openclaw/openclaw-<date>.log` | rounds/0012 实测；`kernels/openclaw/src/logging/log-file-path.ts:17` |

**`TMPDIR` 不是日志的开关**——rounds/0012 已实测证伪（`TMPDIR` 会被 jiti 缓存采纳，但日志路径不走那条链）。

## 5. 已修复：会话 label 硬编码（rounds/0013 B1）

**历史限制（rounds/0012 及之前，已修复，本节保留记录）**：`OpenclawGatewayKernelClient.swift` 曾把
会话 label **硬编码**为字面量 `sg4-kernel-client-l1`——openclaw 侧对同一 store 内全部会话强制 label
互不相同（`gateway/sessions-patch.ts:422-441`），硬编码字面量导致同一 state 目录下第二次「新建会话」
必失败：

```
rpc rejected [INVALID_REQUEST]: label already in use: sg4-kernel-client-l1
```

**rounds/0013 B1 修复**：`createSession()` 现在按 `"sg4-<UTC 时间戳>-<ourSessionID>"` 铸造 label（见
`OpenclawWire.swift` 的 `makeSessionLabel` 文档注释）——时间戳段落人眼可辨认，`ourSessionID` 段落保证
唯一且可与 `SessionHandle.sessionID` 互相反查。**同一 state 目录下现在可以连续建多个会话**，§2 起隔离
实例时仍然默认每次重建全新目录（见 `start-isolated-kernel.sh` 注释），但这现在只是干净起点的卫生
默认值，不再是规避 label 撞名的硬性要求。

## 6. 跑 UI

```bash
./app/apps/AgentShell/build-app-bundle.sh          # 产出 app/.build/AgentShell.app
export AGENT_KERNEL_WIRE_TRACE=/tmp/l1-repro/wire-trace.jsonl   # 可选：产出 wire→D2 对照 trace
open app/.build/AgentShell.app
```

> **必须用 `export`，不能用命令前缀**（`VAR=x open ...`）。`open` 通过 LaunchServices 启动，只带得过去**已导出**的环境变量；命令前缀设的变量到不了 app。本轮实测踩过这个坑。
>
> **跑 bundle 而不是裸二进制**：`build-app-bundle.sh` 的注释说明了 bundle 对窗口与焦点的必要性。裸二进制也能起，但那不是交付形态。
>
> **trace 文件不会立刻出现**——插桩只在 `session.message`/`agent`/`session.approval`/`shutdown` 四类事件分派时写盘。只连接、只建会话都不产生它；**发一条消息之后才有**。本轮实测因此误判过一次「env 没传过去」。

**操作**：点「新建会话」→ 输入框粘贴一句要求固定回复的话 → 发送。

> **输入法**：macOS 中文输入法会吃掉 AppleScript 的 `keystroke`（实测把 ASCII 转成中文词）。自动化驱动请用**剪贴板粘贴**（`pbcopy` + ⌘V）。
>
> **自动化点击别写死坐标**：窗口位置/尺寸每次启动可能不同（本轮实测 bundle 启动与裸二进制启动的窗口几何就不一样，照抄旧坐标点空了一次）。用 AX 读实际几何再按比例算。

**期望**：侧栏绿点「已连接」，右侧渲染出 assistant 回复。

## 7. 验证消息分组修复（本轮 ①' 的核心）

### 7a. 确定性判据（离线、不依赖 provider）—— **只覆盖 kernel-client 侧，不覆盖 UI 合并行为**

> ⚠️ **先说清它不是什么**：本节的测试**验的是 `messageID` 在 kernel-client 侧被正确传递**，
> **不验 `SessionStore` 的气泡合并行为**——`frame-replay-tests` 在 SwiftPM 依赖图上够不到 `AgentShell`
> （`Package.swift` 未声明该依赖，且 `appendAssistantDelta` 是 file-private），这一限制已登记为待办 D3。
>
> 所以：**把它称作「消息分组修复的主判据」是名不副实的**（T-085/T-086 双路复审均判 FAIL，主会话采纳）。
> 它是**前置条件的确定性判据**——`messageID` 传不过来，分组必然回退到旧缺陷；传得过来，
> 才轮到 UI 侧按它分组。**UI 合并行为本身目前只有 §7b 的现场观察，没有入库的确定性判据。**

```bash
swift build --package-path app && ./app/.build/debug/frame-replay-tests
```

期望 **40/40 PASS**（rounds/0013 起，以实际输出为准）。其中与本项直接相关的两条：

- `testDistinctAssistantMessagesInSameRunGetDistinctMessageIDs` —— 喂两条 `messageId` 不同、`runId` 相同、`index` 均为 0 的 `session.message` 帧（**就是造成重复的那个撞键形状**），断言二者拿到**不同且非 nil** 的 `messageID`。
- 破坏性反证已验：把 `EventMapping.swift` 里 `messageID` 的填充改成 `nil`，该条转红（30/31 → 现 35/36），恢复即绿。

**这条是确定性的**：固定帧输入、固定断言、不依赖任何真实 provider 或时序。

### 7b. 现场观察 —— **目前唯一覆盖 UI 合并行为的检查（但不确定性）**

把 §2 的 `L1_PROVIDER_BASE_URL` 改成死端口（如 `http://127.0.0.1:59999`），用**全新目录**重跑 §2–§6 并发任意消息：

| | 修复前（rounds/0011） | 修复后（rounds/0012） |
|---|---|---|
| UI | **一个**气泡，文本拼接两遍 | **两个**独立气泡，各自完整文本 |

```bash
python3 -c "
import json
for l in open('/tmp/l1-repro/wire-trace.jsonl'):
    o=json.loads(l)
    for e in o.get('producedEvents',[]):
        if e.get('wireType')=='evt.message.delta':
            p=e['payload']
            print(e.get('runID'), p.get('messageID'), p.get('index'), repr(p.get('delta'))[:50])
"
```

> ⚠️ **这条不能当判据，原因要说清楚**：「死端口 → 恰好两条 assistant 消息」**不是稳定保证**。本轮实测中那两条是 openclaw **failover/retry 的间接结果**（对应 openclaw 日志里 6 次 `ECONNREFUSED`）；换 provider、换配置、换版本都可能得到一条或更多条。
>
> 所以：**观察到两条时它能直观展示修复效果，观察到一条时不代表修复失效**。判据以 §7a 为准。

## 8. 收尾

```bash
./app/apps/AgentShell/repro/stop-isolated-kernel.sh      # 停实例 + 核实端口释放 + 删隔离目录
```

> **为什么要脚本而不是 `kill $(cat gateway.pid)`**：`node scripts/run-node.mjs gateway` 会**再 fork 一个子进程**真正监听端口，pid 文件记的是 **wrapper**。杀 wrapper 之后监听端口的子进程可能仍然活着——rounds/0012 实测撞过：kill 完 pid 文件里的进程，端口仍被占用。**该脚本以端口占用者为准**（先 TERM 后 KILL），并在退出前核实端口真的释放；未释放则 exit 1。
>
> 隔离目录属本次新建，脚本会整体删除（`L1_KEEP_DIR=1` 可保留）。**不删除任何非本次新建的东西。**

## 9. RAE-0001 条件③(b)(c) 对账取证

**目的**：证明受控会话内没有丢消息——比对**两个来源**的 assistant 消息集合，双向对账 +
破坏性反证。脚本：`repro/reconcile-history.py`（Python 3（本机基线 3.9），只用标准库，无第三方依赖）。

- **来源 A（wire）**：本地 wire trace JSONL。取每行 `producedEvents[]` 里含
  `wireType == "evt.message.delta"` 的帧，用 `wireFrame.payload.message.role == "assistant"`
  过滤，键取 `(wireFrame.payload.messageId, wireFrame.payload.messageSeq)`。
- **来源 B（history）**：`GET {base}/sessions/{sessionKey}/history?limit=N`（鉴权
  `Authorization: Bearer {token}`，shared-secret 模型，无需额外 scope 头），响应
  `{"messages": [...], "hasMore": bool, "nextCursor"?: str}`，取 `role == "assistant"` 的
  消息，键取 `(msg.__openclaw.id, msg.__openclaw.seq)`。**脚本会跟着 `nextCursor` 持续翻页
  直到 `hasMore` 为 `false`才认为读全**——见下方「断言与退出码」表格与 2026-08-11 加固说明；
  离线 `--history-file` 快照也要满足 `hasMore == false`，否则视为残缺快照、硬失败。

### 用法

```bash
# 在线：对着真实 gateway 取 history（token 走环境变量，不要用 --token 传）
export OPENCLAW_GATEWAY_TOKEN=...   # 从隔离实例 conn.env 或你的凭证来源注入，切勿写进任何 tracked 文件
python3 repro/reconcile-history.py \
  --trace /tmp/l1-repro/wire-trace.jsonl \
  --base "http://127.0.0.1:$PORT" \
  --session-key "agent:main:dashboard:<会话id>" \
  --limit 500

# 离线自测 / 存档取证：用 --history-file 代替 HTTP（也可用来把线上快照存档留证）
python3 repro/reconcile-history.py \
  --trace /tmp/l1-repro/wire-trace.jsonl \
  --history-file history-snapshot.json

# 破坏性反证（条件③(c)）：单次执行内先验证 baseline 是绿的，再从 wire 侧删一条 assistant
# 消息，验证对账必须精确变红（新增差集恰好等于被删的那个 key）
python3 repro/reconcile-history.py \
  --trace /tmp/l1-repro/wire-trace.jsonl \
  --history-file history-snapshot.json \
  --drop-one

# 需要更严格地校验「至少应该有 N 条 assistant」时（默认下限是 1，堵住两个空集直接 PASS）：
python3 repro/reconcile-history.py \
  --trace /tmp/l1-repro/wire-trace.jsonl \
  --history-file history-snapshot.json \
  --expect-min-assistant 3
```

`--session-key` 里的冒号不需要手动转义。`--limit` 是**单页** limit，默认 500，仅在走 HTTP 时
生效——总数超过一页时脚本会自动跟着响应里的 `nextCursor` 继续请求，直到 `hasMore` 为
`false`才停止，不会只读第一页就当作读全了。完整参数见 `reconcile-history.py --help`。

### 断言与退出码

| 断言 | 内容 |
|---|---|
| ① wire ⊆ history | wire 侧每个 `(id, seq)` 都能在 history 里找到 |
| ② history ⊆ wire（反向） | history 的 assistant 消息在 wire 侧全部出现——**这就是条件③(b) 的直接取证** |

PASS 除了①②两条断言，还需要以下校验同时成立（2026-08-11 加固；标 * 的两项是 2026-08-11
二轮加固新增，见脚本 docstring「二轮加固」小节）：wire/history 两侧解析出的行/消息里
**没有**异常——JSON 解析失败、顶层不是对象、缺失或类型不合法的 `messageId`/`messageSeq`
（wire 侧）或 `__openclaw.id`/`seq`（history 侧）*（seq 必须是真正的 `int` 且非 `bool`，
id 必须是非空 `str`，不再做任何类型转换或"非 None 即可"式的宽松判断）*、以及
*wire 侧一条已经产出了 `evt.message.delta` 的记录，其 `role` 却不是精确的 `"assistant"`
字符串*（这条只对 wire 侧生效，依据见 `EventMapping.swift:149-177`：wire 侧唯一产出
`evt.message.delta` 的路径本身就先决条件式地要求 `role == "assistant"`，已经产出了却
role 不对，只能是异常，不是正常流量）；history 侧**没有**任何 `(id, seq)` 重复的 key；
双方 assistant 消息数都不低于 `--expect-min-assistant`（默认且最小值 1，0 与负数会被
参数校验直接拒绝，二轮加固后不再允许关闭这条下限）。**history 侧**的
`role != assistant`（例如 user 消息）仍然是正常语义、不算异常，报告里会列出角色分布——
但这条规则只属于 history 侧，wire 侧不适用（两侧规则不对称，不能混用）。

| 退出码 | 含义 |
|---|---|
| 0 | PASS（正常模式，全部断言/校验都成立） |
| 1 | FAIL（正常模式不成立）；或 `--drop-one` 模式下**按预期精确变红**（baseline 干净、删除后差集精确等于被删的键——这正是 `--drop-one` 该有的结果——红是对的） |
| 2 | 用法/环境错误——参数缺失、trace/history 读取失败、HTTP 请求失败、**history 分页读不全**（离线快照 `hasMore` 非 `false`、在线翻页遇到重复 `nextCursor` 或缺失 `hasMore`/`nextCursor`）等，对账都还没跑起来就出的错 |
| 3 | `--drop-one` 完整性失败——删了一条消息对账却仍是全绿，或差集不精确等于被删的那个 key，脚本会打印具体是哪一种（条件③(c) 的安全网） |
| 4 | `--drop-one` 基线不干净——同一次执行内，删除前的数据本身就没通过全部校验（见上面 PASS 的完整条件），脚本会打印「无法反证：baseline 本身是红的」，不会假装完成了破坏性反证 |

失败时报告会逐条列出缺失记录的 `id`、`seq`、文本前 60 字符（两个方向都覆盖），history 侧的
重复 key 会把每次出现的文本都列出来（不做去重覆盖），不只说「对不上」。`--drop-one` 会在删除
前原样打印被删记录——没打印出来这次反证不算数。

**2026-08-11 加固**：异构对抗评审（codex，只读）实证发现了 5 条脚本本该判红却判绿的路径
（去重覆盖掩盖 history 侧基数丢失、解析异常/缺 metadata 静默跳过不进 PASS 判定、空集直接
PASS、history 分页截断可能与真实丢帧巧合、`--drop-one` 不验证删除前的 baseline 是否干净），
均已修复，细节见脚本顶部 docstring 与 `--help`。上面表格已按修复后的行为更新；`--limit`
现在是分页 limit 而不是一次性取全部的 limit。

**2026-08-11 二轮加固**：同一 codex 只读评审复验第一轮修复后，仍实证发现 2 条残留假绿：
(1) wire 侧一条已经产出 `evt.message.delta` 的记录，只要 `role` 缺失/非字符串/不是
`"assistant"`，就被当成"非 assistant，正常忽略"静默放过，异常计数不动——但依据
`EventMapping.swift:149-177`，wire 侧唯一产出 `evt.message.delta` 的路径本身就要求
`role == "assistant"`，已经产出了却 role 不对只能是异常；(2) `id`/`seq` 以前只检查
"非 `None`"，没有做类型校验——Python 里 `True == 1` 且 `hash(True) == hash(1)`，wire 侧
一个非法的 JSON boolean seq 能借此冒充成 history 侧合法的整数 seq 被判定"匹配"，float
还会被 `int()` 静默截断。均已修复：id 现在必须是非空 `str`，seq 必须是真正的 `int`
（显式排除 `bool`），不满足则计入该侧原有的 metadata 异常统计，不再进入对账集合。顺带
把 `--expect-min-assistant` 的下限从"默认 1、可传 0 关闭"收紧为"最小值 1，0 与负数直接
拒绝"——作为 RAE 专用取证工具，允许关闭这条下限校验本身就是漏洞，不再保留开关。细节见
脚本顶部 docstring「2026-08-11 二轮加固」小节与 `--help`。

### 凭证

token 只从环境变量 `OPENCLAW_GATEWAY_TOKEN` 读；`--token` 可覆盖但会留痕在 shell history / `ps`，
能用环境变量就不要用它。脚本任何时候（含出错时）都不打印 token 本身。

### 自测记录（假数据，不含真实 gateway 往返；真 gateway 未起时做的）

> **这份记录是 2026-08-11 加固之前做的历史记录，原样保留，不重写，但按当前脚本行为已经
> 不能直接复现出同样的结论**，有两处会不一样：(1) 下面 `fake-history.json` 缺顶层 `hasMore`
> 字段，现在会被判定为「无法确认完整性」而硬失败（退出码 2）——先补一行 `"hasMore": false`
> 才能往下走；(2) 补完之后，下面故意造的那条「缺 `__openclaw` 的畸形条目」在旧脚本里只计数
> 不影响 PASS，在新脚本里会被计入 history 侧异常、**直接让整体判定变成 FAIL**——这正是
> 2026-08-11 修复第②条要堵的洞（异常计数以前不参与判定），不是回归。要看按当前行为跑出来
> 的红/绿证据，见交付说明里的 5 组「假绿→变红」构造用例 + 1 组绿 + rounds/0013 真实数据
> 回归，不在本文件内（fixture 按要求放在会话 scratchpad，未入库）。

**解析路径**：用真实的 `rounds/0012/evidence/live/raw/wire-trace.jsonl`（46 行）跑
`parse_wire_trace()`，正确提取到唯一 1 条 assistant 记录 `id='faef4e40' seq=2
text='FIX VERIFIED'`，与该文件已知内容一致；该 trace 只有 1 条 assistant，只够验解析，
不够验完整对账。

**完整对账**（全绿 + `--drop-one` 变红）用手造数据，两份文件形状如下（可原样复制粘贴复现；
自测时二者存在会话 scratchpad，未入库）：

`fake-wire-trace.jsonl`（9 行：2 空行、1 行非法 JSON、1 行无 delta 的 lifecycle 噪声、
1 行 role=user 的合成 delta、3 条不同 `(id,seq)` 的 assistant 消息，其中 `aaa111/1` 跨两帧
模拟流式增长）：

```
<空行>
{not valid json
{"producedEvents":[],"wireFrame":{"event":"agent","payload":{"data":{"phase":"start"}}}}
{"producedEvents":[{"wireType":"evt.message.delta","seq":1,"payload":{"index":0,"delta":"hi","messageID":"userxxx"}}],"wireFrame":{"event":"session.message","payload":{"messageId":"userxxx","messageSeq":1,"message":{"role":"user","content":"hi"}}}}
{"producedEvents":[{"wireType":"evt.message.delta","seq":2,"payload":{"index":0,"delta":"Hello","messageID":"aaa111"}}],"wireFrame":{"event":"session.message","payload":{"messageId":"aaa111","messageSeq":1,"message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}}}
{"producedEvents":[{"wireType":"evt.message.delta","seq":3,"payload":{"index":0,"delta":" from A","messageID":"aaa111"}}],"wireFrame":{"event":"session.message","payload":{"messageId":"aaa111","messageSeq":1,"message":{"role":"assistant","content":[{"type":"text","text":"Hello from A"}]}}}}
{"producedEvents":[{"wireType":"evt.message.delta","seq":4,"payload":{"index":1,"delta":"Second reply B...","messageID":"bbb222"}}],"wireFrame":{"event":"session.message","payload":{"messageId":"bbb222","messageSeq":2,"message":{"role":"assistant","content":[{"type":"text","text":"Second reply B, a bit longer than sixty characters to test the preview truncation logic works correctly end to end"}]}}}}
{"producedEvents":[{"wireType":"evt.message.delta","seq":5,"payload":{"index":2,"delta":"Third and final C","messageID":"ccc333"}}],"wireFrame":{"event":"session.message","payload":{"messageId":"ccc333","messageSeq":3,"message":{"role":"assistant","content":[{"type":"text","text":"Third and final C"}]}}}}
<空行>
```

`fake-history.json`（5 条：1 条 user、3 条匹配的 assistant、1 条故意缺 `__openclaw` 的畸形条目）：

```json
{
  "messages": [
    {"role": "user", "content": "hi", "__openclaw": {"id": "userxxx", "seq": 1}},
    {"role": "assistant", "content": [{"type": "text", "text": "Hello from A"}], "__openclaw": {"id": "aaa111", "seq": 1}},
    {"role": "assistant", "content": [{"type": "text", "text": "Second reply B, a bit longer than sixty characters to test the preview truncation logic works correctly end to end"}], "__openclaw": {"id": "bbb222", "seq": 2}},
    {"role": "assistant", "content": [{"type": "text", "text": "Third and final C"}], "__openclaw": {"id": "ccc333", "seq": 3}},
    {"role": "assistant", "content": [{"type": "text", "text": "malformed entry missing __openclaw, must be counted not silently dropped"}]}
  ]
}
```

结果：

- 全绿路径（无 `--drop-one`）：解析统计与手造数据逐项吻合（空行 2、解析失败 1 行、无 delta 1 行、
  非 assistant 1 行、匹配帧 4、去重后 unique 3、重复键 1；history 侧 5 条、非 assistant 1、
  畸形 1、去重后 unique 3），差集两个方向均为 0，**`PASS`，exit 0**。
- `--drop-one` 路径：按 `(id, seq)` 排序从 wire∩history 中确定性选取第一个键，删除前原样打印
  `id='aaa111' seq=1 text[:60]='Hello from A'`；删除后断言②正确捕获该缺失（history 有、wire
  没有 = 1 条），报告标注「结果：FAIL（符合预期）—— [DROP-ONE 自证] 断言②正确捕获了被删除的
  消息」，**exit 1**。
- 额外用一个临时本地 HTTP server（stdlib `http.server`，非交付物，仅自测用）验证了
  `--base`/`--session-key` 路径本身：URL 拼接为
  `http://127.0.0.1:<port>/sessions/agent:main:dashboard:fake-selftest/history?limit=500`、
  `Authorization: Bearer <token>` 头与 `limit` 查询参数均按预期送达并被服务端校验通过——
  这只证明脚本这一侧的 HTTP 客户端逻辑没写错，**不构成对真实 openclaw gateway 的验证**。
- 负向路径：环境变量与 `--token` 均未提供时，`exit 2` 并给出清晰诊断（不崩溃、不裸抛
  traceback）；故意传错 token 触发 HTTP 401 时，错误信息包含 URL 与响应 body，**两次均确认
  token 本身未出现在任何输出中**。
