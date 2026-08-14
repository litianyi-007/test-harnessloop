# rounds/0013 C —— RAE-0001 四条件实跑（2026-08-11）

隔离实例：`openclaw-isolated`，gateway pid 27158，port 63814，state 根
`<scratchpad>/l1-repro`（`L1_ROOT` 覆盖默认 `/tmp/l1-repro`）。provider = deepseek，
model = `deepseek-v4-flash`，凭证从 gitignored `channel-params.json` 注入，未落任何 tracked 文件。

## 结论：**四条件全部达成 → RAE-0001 = pass**

---

## ① 真实往返 —— 达成

- **UI 侧**：`AgentShell.app` 连上隔离实例（左栏「● 已连接 (scopes: operator.admin)」），
  同一 state 目录内**连建 3 个会话全部成功**并在侧栏可区分（会话 1/2/3），
  发消息后渲染出 assistant 回复 `ALPHA` / `CHARLIE`。截图 `ui-shot-01..04`。
- **CLI 侧**：3 轮 send 全部完成，各自拿到不同 runId。

> **B1 反证的现实意义**：修复前第二次 `createSession()` 必因 label 撞名失败。本轮连建 4 个
> 会话（UI 3 + CLI 1）零冲突，隔离库 `sessions` 表 4 行。

## ② 隔离性 —— 达成（正面归因，证据强于 0011）

rounds/0011 已证「整树 `stat` 指纹前后比对」**不可用**——`~/.openclaw` 有并发第三方写者。
本轮把那个写者**指名道姓地抓出来了**：

| PID | 身份 | 启动时间 |
|---|---|---|
| 27158 | **本轮隔离实例** | 2026-08-11 02:58:19（本会话内） |
| 29071 | **用户自己的常驻 gateway** | **2026-07-31 09:58:07（早 11 天）** |

- `lsof +D ~/.openclaw` → 只有 **29071** 持有其中文件（`gateway.log` / `gateway.err.log` / `openclaw.json`）
- `lsof -p 27158 | grep .openclaw` → **0**
- 27158 实际打开的 state 文件全部在 `l1-repro/state/` 下（sqlite/shm/wal）
- 本轮 SESSION_KEY 与 messageId 在 `~/.openclaw` 全树 grep → **0 命中**
- 隔离库 `agents/main/agent/openclaw-agent.sqlite` 中 SESSION_KEY 命中 **24**

> 期间 `~/.openclaw/agents/main/sessions/sessions.json` 于 02:59 被修改过——**不是本轮实例干的**，
> 是 29071。这正是「整树指纹法」失效的原因，也是必须用正面归因的原因。
> **差一点又要误判**：只看时间戳会得出「隔离失败」的结论。

## ③ 事件序列 —— 四要素逐条达成

条件③ 于 2026-08-10 user-confirmed 修订为四要素（权威落点 `setup/data-sources.md`）。

### (a) 不乱序 —— 0 处倒退

| 指标 | 结果 |
|---|---|
| D2 `seq`（**每 run 内**递增） | run `9471e2c1`: 42 个值 1..42，倒退 **0**；run `a95294c8`: 1..2，倒退 **0**；run `c7ee4c77`: 1..2，倒退 **0** |
| wire `messageSeq` | `[1,1,2,3,3,4,5,5,6]`，倒退 **0** |

> **一处测法纠正**：初次把三个 run 的 `seq` 串成一条序列去查单调性，得到「2 处倒退」——
> **是测法错的**。D2 的 `seq` 是 per-run 语义，跨 run 重置属正常。按 run 分组后为 0。
> 记此一笔，因为「指标看起来红了」与「东西真坏了」是两件事。

### (b) 受控会话内与权威 history 对账 —— PASS

- 会话：`agent:main:dashboard:1be7cfd9-2835-429e-ab80-270157cc0798`（3 轮往返）
- wire 侧 assistant `(messageId, messageSeq)`：`(985c3d92,2) (9e9026bf,4) (18c28cec,6)` — unique 3
- history 侧（`GET /sessions/<key>/history?limit=200`）：6 条消息，3 条 user 被 role 过滤，assistant unique 3
- **两向差集均为 0** → PASS

### (c) 破坏性反证 —— 变红（守门有效）

`--drop-one` → **exit 1**，且**删除前逐字打印了被删记录**：
`id='18c28cec' seq=6 text[:60]='CHARLIE'`，随后断言② 精确捕获该缺失。

> 打印被删内容是硬要求：rounds/0012 有两次「破坏没生效却读成没问题」。

### (d) 协议级无丢帧 —— 按条件③ 显式列为**内核已知缺口**，不在本层验收

## ④ 失败可诊断 —— 达成（两次注入，两种定位）

| 注入 | 输出 | 定位到 |
|---|---|---|
| 指向错端口 `ws://127.0.0.1:1` | `FATAL: transport error: NSURLErrorDomain Code=-1004 "Could not connect to the server."` + 确切 URL | **传输/可达性层** |
| 对端口 + 错 token | `FATAL: rpc rejected [INVALID_REQUEST]: unauthorized: gateway token mismatch (set gateway.remote.token to match gateway.auth.token)` | **鉴权层**，且带修复提示 |

两者 exit 均为 1，但错误信息把层次分得很清——这正是条件④ 要的「失败也要是有信息的失败」。

---

## 一个必须记下的纠正：`kernelSessionID` ≠ history 的 `key`

对账差点跑错对象。openclaw `sessions.create` 同时返回两个**独立字段**：

- `key` —— 形如 `agent:main:dashboard:<uuid>`，**`GET /sessions/<key>/history` 要的是这个**
- `sessionId` —— 另一个独立生成的 id

而 `SessionHandle.kernelSessionID` 存的是 `sessionId ?? key`，实际几乎总是 `sessionId`。
CLI 原先只打印 `kernelSessionID`——**照它去查 history 会查到一个不存在的会话**。
现已改为打印 `[C] SESSION_KEY=` 并附一行说明二者区别。

本轮实测两值：`key=agent:main:dashboard:1be7cfd9-...`，`sessionId=8f0a808f-...`，**确实不同**。

## 主会话自查：一条被堵住的假绿路径，与一条**残余风险**

对账最危险的失败模式不是「报红」，是「本该红却绿」。自查了 history 分页截断这条路径：

**实测**：把 `--limit` 从 200 压到 **2**（少于该会话的 6 条消息）→
wire 侧 3 条、history 侧只剩 1 条 → **断言① 被违反 2 条 → FAIL（exit 1）**。

**结论**：截断使 history 变小，虽然让断言②（history ⊆ wire）更容易通过，
但必然从**断言①**（wire ⊆ history）那一侧暴露。**两向断言的设计堵住了这条假绿路径。**

### 残余风险（未消除，如实登记）

脚本**不会**在 `返回条数 == limit` 时发出「history 可能被截断」的警告。
存在一个理论上的窄缝：**当 wire 真正丢失的消息，恰好就是被截断掉的那几条最旧消息，
且没有其他消息落在截断区**——此时两个断言可同时通过。

- 本轮不构成问题：`--limit 200` 对 6 条消息，无截断。
- **未修的原因**：发现时 ★审查闸正在只读评审这个文件，中途改动会使评审失效。
- **建议修法**：`len(messages) >= limit` 时打印显式警告并计入报告头。

---

# ★审查闸 T-090b（codex）判 REWORK —— 处置记录（2026-08-11）

**评审是对的。** 三项发现主会话逐条核过，两项属实、一项为建议：

## Q1「pass 靠叙述、不靠冻结证据」—— **成立，已修**

原稿把结果写进本文件，但**原件全在 scratchpad，没进证据树**（当时树里只有 5 个 md +
两个更早的 B1 产物）。这与 rounds/0011 判 negative 的毛病同形。

**已冻结**：`evidence/live/` 下 25 个文件（**总字节数随后续文字修订会漂移，此处不再钉死具体数值**——★审查闸 T-092 指出该数字易失准）。整个 `evidence/` 树含 md 与台账。
下表列冻结位置：

| 条件 | 冻结的原件 |
|---|---|
| ① | `shots/ui-shot-03..05`（三会话并列 / 消息往返 / 重启后）、`raw/cli-run.log`、`raw/cli-wire-trace.jsonl`、`raw/ui-stdout.log` |
| ② | **`raw/isolation-transcript.txt`** —— **10 个命令块**逐条带 stdout 与 `exit=`，含 `ps -o lstart`（两个 gateway 的启动时间）、`lsof -p`、`lsof +D`、全树 grep、sqlite 计数。**注**：文件内 echo 行里的 `<SESSION_KEY>` 是字面量占位符，实际 grep 用的是变量真值，可在 `raw/cli-run.log` 搜 `[C] SESSION_KEY=` 复核（见该文件末尾的证据卫生注记） |
| ③ | `raw/history-snapshot.json`、`raw/reconcile-hardened-pass.txt`、`raw/reconcile-hardened-droponme.txt`、`raw/reconcile-limit2.txt` |
| ④ | `raw/diag-badport.log`、`raw/diag-badtoken.log`、**`raw/ui-diag-badport.log` + `shots/ui-shot-06-diag-ui-layer.png`** |

## Q2「对账脚本有假绿路径」—— **成立，已修并复验**

评审给的五条经复现全部属实，已全部加固。**主会话独立复验**（用自己造的反例，不用子代理的 fixture）：

| 检查 | 结果 |
|---|---|
| 本轮真实原件重跑 | **PASS，exit 0**，两侧异常计数均 0 |
| 真实原件 `--drop-one` | **exit 1**；先验 baseline 干净，再删，新增差集**精确等于**被删键 `id='18c28cec' seq=6` |
| 把真实快照 `hasMore` 改成 `true` | **exit 2 硬失败**：「拒绝在残缺数据上对账」 |
| 把 `hasMore` 字段删掉 | **exit 2 硬失败**：「无法判断是否已读全，拒绝对账」 |

> **一条反过来加强原结论的事实**：冻结的 `history-snapshot.json` 自身
> `hasMore: false`、`nextCursor: null`、6 条消息 —— **说明本轮对账当时就跑在一份可证完整的
> history 上**，截断风险在本轮实际未发生。这一点原稿没能证明，现在能了。

## Q3「`public` 暴露面过宽」—— **属重构建议，本轮只记录不动手**

评审指出 4 处确属多余（`ChatMessage.createdAt`/`.init`、`ChatSessionViewModel.init`、
`AgentShellCore` 的 library product），并提了更小的方案（feature library + 薄 `@main` shim）。
**不在本轮动**：scope-lock 的收敛守卫是「第 3 个 MUST-FIX → checkpoint」，且这是重构不是缺陷。
登记为下一轮候选。

### 二轮加固的第三处改动（超出那两条残留，记录完整性）

复审另提「`--expect-min-assistant 0` 仍可显式恢复空集 PASS，RAE 专用工具不应保留无约束绕过」。
处置：**直接把下限硬定为 1**，传 `0` 或负数 → `exit 2` 拒绝执行（实测确认）。
**没有**改成加一个 `--allow-empty` 双重确认开关，理由是：

> 再加一个 flag 不消除这个洞，只把它挪低一层——原本需要传 `--expect-min-assistant 0` 的调用，
> 同样会把 `--allow-empty` 一并固化进脚本里带着走，而没人会去复核已经写死在调用串里的参数。
> 这正是本轮一系列修复要消灭的「有文档的绕过，但没人注意」模式。

本轮真实原件用默认值 1 即可通过，去掉这个逃生口零成本。

**主会话独立复验的最终态**（用自己构造的反例，不用子代理的 fixture）：

| 用例 | exit | 期望 |
|---|---|---|
| wire 侧产出了 delta 但 role 缺失 | 1 | 红 ✓ |
| wire `seq=true` vs history `seq=1`（`True == 1` 别名） | 1 | 红 ✓ |
| history 含合法 `role='user'` 消息 | 0 | **绿**（未修过头）✓ |
| 本轮真实原件 | 0 | 绿 ✓ |
| 本轮真实原件 `--drop-one` | 1 | 红且精确捕获 `18c28cec`/6 ✓ |
| `--expect-min-assistant 0` | 2 | 拒绝 ✓ |

## 条件④ 的 UI 层缺口 —— **成立，已补**

评审指出原稿两例都是 CLI 摘录，「没有证明错误最终在 UI 可见」。**属实。**
补做：把壳指向死端口启动 → UI 左栏直接出红色横幅
`● 连接失败: transport error: Error Domain=NSURLErrorDomain Code=-1...`
（`shots/ui-shot-06-diag-ui-layer.png`）。三层（UI / kernel-client / gateway）现已各有一例。

## 复现命令

```bash
# 起隔离实例（L1_PROVIDER_* 从 channel-params.json 注入，勿写进任何 tracked 文件）
L1_ROOT=<scratchpad>/l1-repro ./app/apps/AgentShell/repro/start-isolated-kernel.sh > start.log 2>&1
source <scratchpad>/l1-repro/conn.env

# 多轮取数（保留会话供事后查 history）
SG4_KERNEL_URL="ws://127.0.0.1:$PORT" SG4_KERNEL_TOKEN="$TOKEN" \
AGENT_KERNEL_WIRE_TRACE=cli-wire-trace.jsonl \
SG5_SEND_MESSAGES="…||…||…" SG5_SEND_WAIT_MS=25000 SG5_SKIP_STOP=1 \
  ./app/.build/debug/kernel-client-cli > cli-run.log 2>&1

# 对账（KEY 取 cli-run.log 里的 [C] SESSION_KEY=）
OPENCLAW_GATEWAY_TOKEN="$TOKEN" python3 app/apps/AgentShell/repro/reconcile-history.py \
  --trace cli-wire-trace.jsonl --base "http://127.0.0.1:$PORT" --session-key "$KEY" --limit 200
# 破坏性反证：同上加 --drop-one，必须 exit 非 0
```


---

# ★审查闸第三轮 T-092（用户 2026-08-11 裁定补派）—— **PASS_WITH_NOTE**

原话：「两条影响可信度的假绿已真正闭合，合法输入与冻结原件均无回归；剩余问题仅是证据说明中的字节数和『本文件为空』措辞不精确，不足以要求再次 REWORK。」

两条 note 均已处置：
- `live/raw/ui-diag-badport.log` 首句原写「本文件为空（0 字节）」，而我随后往里写了说明——自相矛盾。已改为「【说明文件，非原始日志】原始采集结果是 0 字节」。
- 本文件里钉死的总字节数已去掉（会随文字修订漂移）。

**三轮评审的轨迹**：T-090b REWORK → T-091 REWORK → **T-092 PASS_WITH_NOTE**。三轮共提出的每一条我都逐条核过，无一条是错的。
