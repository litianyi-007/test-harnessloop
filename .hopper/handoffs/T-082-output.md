---
phase: done
last_progress_at: "2026-08-07T11:02:41.960Z"
last_progress: Task completed successfully.
progress_seq: 11
last_stream_event: process_alive
last_update: "2026-08-07T11:02:30.680Z"
requested_selector: null
effective_selector: grok-4.5
effective_selector_source: policy
selector_kind: unknown
catalog_source_kind: unknown
catalog_source_label: unknown
catalog_observed_at: null
catalog_freshness: unknown
binary_availability: unknown
binary_basename: null
observed_models_json: "[]"
model_attestation_source: null
model_attestation_observed_at: null
resolution_status: unverified
resolution_detail: selector-kind-unknown
diagnostic_code: selector-metadata-cache-missing
adapter_diagnostic_code: none
recovered_output: false
recovered_output_state: no-text
recovered_output_source: none
status: done
end_time: "2026-08-07T11:02:41.958Z"
exit_code: 0
signal: null
process_cleanup: not-needed
duration_ms: 281296
adapter_status: success
terminal_event_emitted: true
---
# T-082 · code-review-adversarial · SG-10 L1 两处设计裁决（grok 轨，异构独立）

**Task-type**: `code-review-adversarial` · **只读，未改任何代码/文档/状态文件**  
**Vendor**: grok · 与 T-081 同 brief、互不可见  
**Assumption (1 line)**: leader-tasklist 中 T-081/T-082 合并 brief 为唯一完整规格；裁决只基于 0012 证据 + 源码，不参照 T-081 产物。

---

## Summary

独立复核了 rounds/0012 的 wire 实测与壳侧分组实现：`(runID,index)` + `+=` 在同 run 多条 assistant 消息下必撞键，根因坐实。**问题一选 A**（壳侧不分组），并确认主会话对 B 的否决成立；A 在当前 `session.message` 全量投递语义下与 EventMapping 多 block 行为兼容，且零契约改动。**问题二不收窄条件②**——`/tmp/openclaw` 严格说不是 STATE_DIR，但共享写日志是真实隔离泄漏；主会话「找不到覆盖手段」**不成立**：openclaw 官方支持通过隔离配置的 `logging.file` 改日志落点（file:line 与验证方法见下）。整体 **Verdict: PASS_WITH_NOTE**。

## Files touched

none（只读评审）

## Acceptance verification (6/6)

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | 独立裁决问题一（A/B/C 或第四路），不和稀泥 | **PASS** | 见「问题一」；明确选 **A** |
| 2 | 核 (a) 多 content block (b) 是否零契约 (c) B 否决是否成立 | **PASS** | EventMapping.swift:197-206；SessionStore.swift:184-194；D2 MessageDelta 无 messageId |
| 3 | 独立裁决问题二：/tmp/openclaw 算不算状态目录 | **PASS** | 见「问题二 (a)」——术语上不算；隔离意图上不得靠收窄豁免 |
| 4 | 自行在 openclaw 源码找日志落点覆盖手段 | **PASS（找到）** | `logging.file`：logger.ts:540、docs/gateway/logging.md:30、zod-schema.root-shape.ts:105-108、paths.ts:159-167 |
| 5 | 若无手段则评估收窄是否重复 0011 放水 | **N/A→转为 (4) 的推论** | 手段存在 → **禁止以「找不到」为由收窄**；若强行收窄则同形 0011 |
| 6 | wire-trace 独立复核主会话转述 | **PASS** | 见下表；双失败帧同 run、同 index、不同 messageId |

### Wire-trace 独立复核（`rounds/0012/evidence/raw/wire-trace.jsonl`）

| line | role | messageId (prefix) | messageSeq | runID (prefix) | D2 index | delta (prefix) |
|------|------|--------------------|------------|----------------|----------|----------------|
| 12 | assistant | `25efe9b9` | 2 | `b53d403a` | 0 | `1\n2\n3…12`（全文一次） |
| 23 | assistant | `1cf68049` | 4 | `0700f2fb` | 0 | `The agent run failed…` |
| 31 | assistant | `0aaec118` | 6 | `0700f2fb` | 0 | 同上全文再次 |

键 `"\(runID)#\(index)"` 对 line 23/31 均为 `0700f2fb…#0` → `SessionStore.appendAssistantDelta` 走 `text +=` → 重复。主会话转述与 raw 一致。

---

## 问题一：消息分组的修法

### 裁决：**选 A（壳侧不分组）**

删除 `(runID,index)` 查找与 `+=`；每个 `evt.message.delta` **开新气泡、整段写入**。

### 为什么 A（攻击后仍成立）

1. **与实测 wire 语义同构**  
   `session.message` 层每条 assistant 帧 → 恰好一个 `messageDelta`，`delta` 是**完整全文**（line 12: `1…12` 一次给出）。增量在 `chat` 旁路，kernel-client 不消费（`item1-mechanism-localization.md` §1；OpenclawGateway 分派无 `chat` case）。在此语义下「追加」没有合法被加数。

2. **根因是键空间错误，不是 `+=` 单独的问题**  
   `EventMapping.swift:197`：`index` = **单条 message 内** `blocks.enumerated()` 的 content-block 下标，每条新 message 从 0 重启。  
   `SessionStore.swift:186-189`：却按 `(runID,index)` **跨 message 永久复用气泡**。  
   同 run 第二条 assistant 必撞 `…#0`。A 直接废除错误键，不靠修补键。

3. **C 正确但本轮禁区**  
   `payload.messageId` 每帧唯一（trace 中 `25efe9b9`/`1cf68049`/`0aaec118` 互异），是正确分组键；全仓读取 0 次；`MessageDeltaEventMessagePayload` 仅 `{delta,index,role}`（`D2.swift:1642-1657`）**无 messageId**。透传 = 改 D2 + `app/generated/` → 0012 scope-lock Disallowed。C 应开独立设计轮，不进本修复轮。

### (a) A 在「一条 assistant 多 content block」会不会坏？

**不会比现状更坏；与现状在多 block 路径上行为等价。**

同帧多 block 时 mapper 产出多个事件、**不同 index**（0,1,2…）：

```text
// EventMapping.swift:197-206
for (index, block) in blocks.enumerated() {
  case "text": → messageDelta(delta: text, index: index, ...)
```

- **现状**：键 `run#0`、`run#1`… → **已是多个气泡**（不同 index 不会合并）。  
- **A**：每事件新气泡 → 仍是多个气泡。  

本轮 trace 三条 assistant 的 content 均为单 `text` block，未观察到多 text block；但源码注释（EventMapping.swift:153-155）承认 text+toolCall 同帧。多 block 的「视觉是否应合并为一条气泡」是**产品问题**，现状也没做合并；A 不引入新缺陷。

**真正的 A 风险**（主会话已写、这里加重）：若将来消费真流式（同逻辑消息多帧增量、同 index），A 会碎成多气泡。那是 **L2 + 契约升级（C）** 的触发条件，不是否决 L1 修缺陷的理由。L1 应在代码注释写死前提：

> 前提：`session.message` 映射出的每个 `messageDelta` 是完整消息文本，不是 token 增量。若开始消费 `chat` 流式或同 messageId 多帧，必须改用 messageId 分组（方案 C）。

### (b) A 是否真零契约改动？

**是。** 只动 `app/apps/AgentShell/.../SessionStore.swift`（及可删的 `inProgressDeltaMessageID` 字典，`ChatSessionViewModel.swift:37`）。  
不改 D1/D2、不改 `app/generated/`、不改 `EventMapping` 产出形状。仍消费既有 `evt.message.delta`。

### (c) B 的否决成立吗？

**成立，且比主会话说的更硬一点。**

B = 保留 `(runID,index)`，`+=` 改 `=`：

| 场景 | B 行为 | 判定 |
|------|--------|------|
| 本轮双失败（两帧同文） | 后者覆盖前者 → UI 显示一条正确文案 | **碰巧**看起来「修了重复」，实为丢帧 |
| 两帧**不同**文案同 run | 只保留最后一条 | **消息丢失** |
| 真流式同 index 多增量 | 只保留最后一块 token | **正文残缺** |

B 用「覆盖」掩盖「键冲突」，把 **duplication bug** 换成 **drop bug**。验收截图若只看「不重复」会假绿。否决 B。

### 有没有第四条路？

| 代号 | 做法 | 评价 |
|------|------|------|
| **D** | 以 D2 `seq` 为分组键 | 当前 mapper 每事件 `nextSeq()` 递增 → 永不合并 → **与 A 运行时等价**，多一套无意义状态 |
| **E** | 在 shell 旁路读 wire `messageId`（不进 D2） | 破坏「壳只吃 D2 事件」边界，比 C 更脏 |
| **F** | `turn_complete` 时清空 `inProgressDeltaMessageID` | **救不了本缺陷**：双失败帧均在 `turn_complete`（trace line 34）**之前**到达 |
| **C′**（延后） | 设计轮做 C | 正确长期解；非本轮 |

**无优于 A 的本轮可落路径。** 长期：A 修 L1 + 登记「流式/messageId → C」。

### 问题一附带攻击（主会话倾向 A 仍应记下）

- **注释债务**：`SessionStore.swift:177-183` 大段为错误的 `(runId,index)` 策略辩护（「两种解释都不会拼错」）。实测已证伪。选 A 时**必须删/改这段注释**，否则后人会按注释把 bug 加回。  
- **A 不是「永远正确的消息模型」**，只是「对当前 mapper 语义的最小忠实修复」。

---

## 问题二：条件② 要不要收窄

### (a) `/tmp/openclaw` 算不算「用户环境既有 openclaw 状态目录」？

**术语答案：不算。**  
**隔离答案：不得以「不算」换 pass。**

依据：

| 概念 | 源码/文档定义 | `/tmp/openclaw`？ |
|------|----------------|-------------------|
| **状态目录 STATE_DIR** | `paths.ts:60-73`：`OPENCLAW_STATE_DIR` 或 `~/.openclaw` | **否** |
| **Preferred temp / 默认日志根** | `tmp-openclaw-dir.ts:7` `DEFAULT_POSIX_TMP_ROOT = "/tmp/openclaw"`；`logger.ts:37-48` 默认 rolling log 落此树 | **是这个** |
| 条件②原文（0011 scope-lock） | 「全程未触碰用户环境既有 openclaw **状态目录** 与 gateway」 | 字面只钉 STATE_DIR + gateway |

因此：把 `/tmp/openclaw` **硬说成「状态目录」** 是概念混淆，对抗审不应靠改术语扩权。

但同时：

1. 隔离实例**已写入**与用户常驻实例共享的 `/tmp/openclaw/openclaw-2026-08-05.log`（启动行自报；run id `b53d403a`×1、`0700f2fb`×7；`round0012-openclaw-iso`×1）——**交叉污染坐实**。  
2. 0012 scope-lock §⑤ **明文要求**审计 `/tmp/openclaw/`——本轮隔离证据范围已包含它。  
3. 0011 已因把「触碰」收成「写入」被 T-080/decision 打回；这次若把「未触碰」再收成「只看 STATE_DIR、共享日志无所谓」，是**同形放水**（改解释而非改事实）。

**明确裁决：**

- **不要**把 `/tmp/openclaw` 重新定义进「状态目录」一词。  
- **不要**为达成条件②而把 `/tmp/openclaw` 排除出验收范围。  
- **要**在条件②的*举证*中继续覆盖共享日志路径（0012 已要求），并用下面 (b) 的手段**消掉泄漏**，再谈 pass。  
- 若产品上只想守字面 STATE_DIR：必须先 **改 scope-lock 原文并 user-confirm**（诚实加高/改判据），禁止在验收时静默窄化。

### (b) 覆盖手段 —— **存在（主会话漏查）**

主会话只试了 `OPENCLAW_STATE_DIR` / `OPENCLAW_WORKSPACE_DIR` / `TMPDIR`。  
**日志路径不走 TMPDIR 链是对的**（`resolvePreferredOpenClawTmpDir` 在 POSIX 上优先 `/tmp/openclaw`，可用则永不 fallback 到 `os.tmpdir()`，见 `tmp-openclaw-dir.ts:158-161`）。  
但 **配置项 `logging.file` 才是官方改落点的入口**：

| 锚点 | 内容 |
|------|------|
| `kernels/openclaw/docs/gateway/logging.md:30` | Configure via `openclaw.json`: **`logging.file`**, `logging.level` |
| `kernels/openclaw/src/logging/logger.ts:534-542` | `file = cfg?.file ?? resolveDefaultActiveLogFile()` |
| `kernels/openclaw/src/logging/config.ts:26-46` | `readLoggingConfig()` 从 **`resolveConfigPath()`** 读 `logging` 块 |
| `kernels/openclaw/src/config/paths.ts:159-167` | 配置默认 `$OPENCLAW_STATE_DIR/openclaw.json`；可被 `OPENCLAW_CONFIG_PATH` 覆盖 |
| `kernels/openclaw/src/config/zod-schema.root-shape.ts:105-108` | schema：`logging.file: z.string().optional()` |
| `kernels/openclaw/src/logging/logger-redaction-behavior.test.ts`（"uses logging.file from the active config path"） | 设 `OPENCLAW_CONFIG_PATH` + `logging.file` → 日志写入指定文件（**有测试牙齿**） |
| env | **`OPENCLAW_LOG_LEVEL`** 只控级别（`env-log-level.ts`）；**无 `OPENCLAW_LOG_FILE` env**——手段是 config，不是 env |

**推荐隔离启动补丁（验证方法）：**

```bash
PROFILE_DIR=/path/to/round0012-openclaw-iso   # 全新目录
mkdir -p "$PROFILE_DIR/state" "$PROFILE_DIR/workspace" "$PROFILE_DIR/logs"
# 最小配置：只钉日志路径（--allow-unconfigured 仍需要，因无 gateway.mode=local）
cat > "$PROFILE_DIR/state/openclaw.json" <<EOF
{ "logging": { "file": "$PROFILE_DIR/logs/openclaw.log", "level": "info" } }
EOF

# 记录 /tmp/openclaw 基线指纹与 inode
BASE_TMP=$(cksum /tmp/openclaw/openclaw-$(date +%F).log 2>/dev/null || echo absent)

OPENCLAW_STATE_DIR="$PROFILE_DIR/state" \
OPENCLAW_WORKSPACE_DIR="$PROFILE_DIR/workspace" \
OPENCLAW_GATEWAY_PORT=18889 \
OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
OPENCLAW_SKIP_CHANNELS=1 \
node scripts/run-node.mjs gateway --port 18889 --allow-unconfigured --token "$TOKEN"

# 期望：
# 1) 启动日志含：log file: $PROFILE_DIR/logs/openclaw.log
# 2) $PROFILE_DIR/logs/ 下有内容；本轮 run id 可在该文件 grep 到
# 3) /tmp/openclaw/openclaw-DATE.log 中本轮 run id 命中为 0（或文件指纹相对 BASE 无本轮增量）
```

等价：`OPENCLAW_CONFIG_PATH=$PROFILE_DIR/state/openclaw.json` 显式指定（与 STATE_DIR 推导一致时冗余但更可审计）。

**不推荐**：靠 chmod/chown 搞坏 `/tmp/openclaw` 逼 fallback——会伤用户常驻实例，且与「不触碰用户环境」冲突。

**结论**：问题二在找到 `logging.file` 后**不必做「算不算状态目录」的牺牲打**——先修 recipe 写入 `logging.file`，泄漏面关闭后条件②的共享日志关切自然消失。主会话「目前没有找到能隔离 openclaw 日志路径的 env」这句话：**env 层面基本对，config 层面错了**。

### (c) 收窄条件②会不会变成「按需放宽」？

**会。禁止。**

| 0011 放水形态 | 本次若收窄的同形 |
|---------------|------------------|
| 条件③ §4「部分」→ §12「达成」无新证据 | 条件②字面「全程未触碰」→ 验收时把已证实的共享写排除 |
| 用「没坏过」代替反证 | 用「状态目录定义上不含日志」代替「隔离成立」 |
| 标准不合适却不改 scope-lock | 不改 user-confirmed 原文、只在证据解释里缩范围 |

0012 scope-lock 纪律第 4 条已写死：「标准若不合适，**先改 scope-lock 再执行**，不在验收时放宽解释。」  
在已存在 `logging.file` 修复路径时，收窄是**最差选项**（既有手段不用，又降标准）。

---

## Decisions / deviations

- 未跑 live gateway 复现 `logging.file`（只读 + 源码/官方测试/文档三角坐实）；主会话落地 recipe 时应用上文验证方法亲跑一次。  
- 未读取 T-081 产物（brief 要求互不可见）。  
- 第四路径 D/E/F 仅作否决对照，不推荐实施。

## Open questions

1. 隔离 `openclaw.json` 仅含 `logging` 时，当前 pin 的 schema 是否还要求其它键才能通过非 `--allow-unconfigured` 路径——recipe 继续 `--allow-unconfigured` 即可，但应用实测确认启动行。  
2. `logging.file` 设为固定文件名 vs 目录下 rolling：`logger.ts` 对配置路径的 rolling 行为以实测启动行为为准（测试用固定 path 已证明可写）。  
3. 方案 A 落地后，是否在 RAE/范围外单开「messageId → D2」设计条目（推荐：是，避免 L2 流式时无路可退）。

## Verdict

**PASS_WITH_NOTE**

- **问题一**：**A**（可直接进 0012 实现）；B 否决成立；C 正确但本轮禁区。  
- **问题二**：**不收窄**；`/tmp/openclaw` 术语上≠状态目录，但共享日志必须纳入隔离举证；**覆盖手段 = `logging.file`（+ 可选 `OPENCLAW_CONFIG_PATH`）**，主会话「无手段」结论应撤回。  
- NOTE：A 的反流式前提必须写进代码注释；`logging.file` 须并入 recipe 与 ⑤ 审计后再判条件②/RAE。

## Next recommendation

1. **立刻改 recipe**：在 `OPENCLAW_STATE_DIR` 下预置 `openclaw.json` 的 `logging.file` 指向隔离目录；更新 `OPENCLAW-ISOLATED-RUN-RECIPE.md`（含文末复制命令，避免再漏第三处）。  
2. **实现 A**：改 `SessionStore.appendAssistantDelta` 为每事件新气泡；删除 `inProgressDeltaMessageID`；改掉错误分组注释；用同一注入失败场景确认不再重复（对照 `l1-doubling-reproduced.png`）。  
3. **不要**改条件②原文去「排除 /tmp/openclaw」；**不要**实现 B。  
4. 修完 ①+日志隔离后，再继续 ②竞态 / ③ messageSeq / ⑥ 可复现；★审查闸用**轮换 vendor** 验证据，不验「我们同意自己」。  
5. 另开设计轮登记 C（`messageId` 进 D2），作为流式/多段消息的正确模型，与 L1 的 A 脱钩。

## Vendor output (parsed)

```
I'll execute the adversarial code review for T-082 myself: pull the queue brief and related context, then write the review deliverable.T-082 shares T-081's brief; I'll pull the full leader-tasklist section and related SG-10 materials next.Pulling the full T-081/T-082 brief and the code paths for message grouping and `/tmp/openclaw` logging.Next I'll verify message grouping in the shell and hunt openclaw for any real log-path override.Found a `logging.file` config hint in openclaw — digging into that and verifying wire-trace multi-message behavior.`logging.file` looks like a real override — confirming how it resolves and whether isolated runs can set it.I have enough evidence: `logging.file` is a real log-path override, and wire-trace confirms the double-bubble root cause. Writing the independent adjudication to `T-082-output.md`.# T-082 complete

Adversarial design adjudication written to `.hopper/handoffs/T-082-output.md` (read-only; no other paths touched).

## Verdict: **PASS_WITH_NOTE**

### 问题一 — 消息分组
**选 A**（每条 `evt.message.delta` 新气泡；去掉 `(runID,index)` 与 `+=`）。

| 检查 | 结论 |
|------|------|
| wire 复核 | 双失败帧同 run `0700f2fb`、同 `index=0`、不同 `messageId` → 撞键复现成立 |
| (a) 多 content block | 与现状等价（mapper 已按不同 index 拆事件） |
| (b) 零契约 | 只动 AgentShell；不碰 D2 / generated |
| (c) B 否决 | **成立**——`=` 把 duplication 换成 drop，假绿风险更高 |
| C | 正确长期解，本轮禁区 |

### 问题二 — 条件② / `/tmp/openclaw`
- **术语上不算** STATE_DIR（`paths.ts` vs `DEFAULT_POSIX_TMP_ROOT`）。
- **禁止收窄验收范围**（同形 0011 放水）。
- **主会话「无覆盖手段」不成立**：应用隔离配置的 **`logging.file`**（`logger.ts:540`、`docs/gateway/logging.md:30`、官方测试已咬住该路径），不是 env/`TMPDIR`。

### Next
1. Recipe 预置 `logging.file` 进隔离 `openclaw.json`  
2. 实现 A + 删错误分组注释  
3. 不要 B、不要静默排除 `/tmp/openclaw`
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- adapter_diagnostic_code: none
- exit_code: 0
- process_cleanup: not-needed
- duration_ms: 281296
- end_time: 2026-08-07T11:02:41.958Z
- log: see `T-082-output.log` for raw output
