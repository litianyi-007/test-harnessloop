#!/usr/bin/env bash
# SG-10 L1 复现：起一个隔离 openclaw 实例（后台），并把连接参数写进 .env 文件供后续步骤 source。
#
# 用法：
#   ./app/apps/AgentShell/repro/start-isolated-kernel.sh            # 用内建 provider（需 3 个 env）
#   source /tmp/l1-repro/conn.env                                   # 拿到 ISO / PORT / TOKEN
#
# 必需 env（值从 .harnessloop/local/channel-params.json 或你自己的来源注入，**不要写进任何 tracked 文件**）：
#   L1_PROVIDER_ID        provider id。**必须是 openclaw 内建 id**（如 deepseek/openai/anthropic）；
#                         用自定义 id 则还须自行补 models 数组，见 README §provider
#   L1_PROVIDER_BASE_URL  例：https://api.deepseek.com
#   L1_PROVIDER_API_KEY   provider 密钥
#   L1_MODEL_ID           例：deepseek-v4-flash
#
# 可选 env：
#   L1_PORT               默认自动选一个空闲端口
#   L1_ROOT               默认 /tmp/l1-repro（每次运行会重建，保证干净状态；rounds/0013 B1 修复
#                         label 硬编码之后，同一目录内已可连续建多个会话，重建不再是规避撞名的必需
#                         手段，只是默认的干净起点）
#   L1_EXEC_ASK           exec 工具的审批策略（rounds/0015 D 块）。**默认不设 = 行为与本轮之前
#                         逐字一致**：不写 tools.exec.ask，实例沿用内核默认 ask="off"
#                         （kernels/openclaw/src/infra/exec-approvals.ts:318 DEFAULT_ASK），
#                         `requiresExecApproval` 恒为 false，从不发起审批——也就是 agent 可以在
#                         宿主机上直接执行 shell 命令、没有任何确认关卡。这不是隔离实例的特例，
#                         是未配置时的内核默认。
#                         取值 always | on-miss | off（内核 enum，见
#                         config/zod-schema.agent-runtime.ts:518）：
#                           always  —— 每条命令都发起审批。这是 exec 审批 live 验收要用的档位。
#                           on-miss —— 仅 allowlist 未命中时审批；**还需要 security=allowlist**
#                                      才会真正生效（requiresExecApproval 的 on-miss 分支同时要求
#                                      `security === "allowlist"`，exec-approvals.ts:1855），
#                                      故本脚本在 on-miss 时一并写入 security=allowlist。
#                         注意（会直接影响审批 UI 呈现）：ask=always 时内核给出的 allowedDecisions
#                         是 ["allow-once","deny"]，**不含 allow-always**
#                         （resolveExecApprovalAllowedDecisions，exec-approvals.ts:2809-2813——
#                         "每次都问"与"永久放行"语义冲突）。壳的审批卡片按每条请求自带的
#                         allowedDecisions 渲染按钮，所以在这个档位下只会出现两个按钮。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

for v in L1_PROVIDER_ID L1_PROVIDER_BASE_URL L1_PROVIDER_API_KEY L1_MODEL_ID; do
  if [ -z "${!v:-}" ]; then echo "缺少必需环境变量：$v" >&2; exit 2; fi
done

umask 077   # provider key / gateway token / conn.env 都会落进 $ROOT，收紧权限

ROOT="${L1_ROOT:-/tmp/l1-repro}"
MARKER=".l1-repro-owned"   # 所有权标记：只删我们自己建过的目录

# 安全校验：绝不 rm -rf 一个我们没建过、或看起来不像临时目录的路径
case "$ROOT" in
  ""|"/"|"$HOME"|"$HOME"/) echo "拒绝：L1_ROOT=$ROOT 不是可安全清除的路径" >&2; exit 2;;
esac
if [ -e "$ROOT" ] && [ ! -e "$ROOT/$MARKER" ]; then
  echo "拒绝：$ROOT 已存在且没有 $MARKER 标记——不是本脚本建的，不动它。" >&2
  echo "      换一个 L1_ROOT，或先自行确认后手动删除。" >&2
  exit 2
fi
# 若旧实例还活着，先停掉，避免留下无法再定位的 gateway
if [ -f "$ROOT/conn.env" ]; then
  echo "发现旧的 $ROOT/conn.env，先停旧实例…"
  "$(dirname "${BASH_SOURCE[0]}")/stop-isolated-kernel.sh" || true
fi
# 每次运行起一个全新 state 目录——干净起点，避免上一轮遗留状态干扰这一轮观察（rounds/0013 B1 之前
# 这也是规避会话 label 撞名的唯一手段；B1 已修复该硬编码，现在纯粹是卫生默认值，不再是硬要求）。
rm -rf "$ROOT"; mkdir -p "$ROOT"/{state,workspace,logs}; : > "$ROOT/$MARKER"
ISO="$ROOT"

# 失败即清理：启动超时/隔离自检不过时，不留后台残骸
cleanup_on_fail() {
  [ -f "$ROOT/gateway.pid" ] && kill -TERM "$(cat "$ROOT/gateway.pid")" 2>/dev/null
  [ -n "${PORT:-}" ] && { pid="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1)"; [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null; }
}
trap 'rc=$?; [ $rc -ne 0 ] && { echo "启动失败（exit $rc），清理残骸…" >&2; cleanup_on_fail; }' EXIT

pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
}
# 端口选择存在 bind-close-use 竞态（选中到 gateway 真正 bind 之间可能被别人抢走）——
# 故重试若干次，且启动后会核实监听者确实是我们起的进程。
PORT=""
for _ in $(seq 1 8); do
  cand="${L1_PORT:-$(pick_free_port)}"
  if ! lsof -tiTCP:"$cand" -sTCP:LISTEN >/dev/null 2>&1; then PORT="$cand"; break; fi
  [ -n "${L1_PORT:-}" ] && { echo "指定端口 $L1_PORT 已被占用" >&2; exit 2; }
done
[ -z "$PORT" ] && { echo "连续 8 次都没选到空闲端口" >&2; exit 2; }
TOKEN="$(openssl rand -hex 24)"

# rounds/0015 D：审批策略开关，默认空 = 不写任何审批配置 = 与本轮之前逐字同构（见文件头 L1_EXEC_ASK）
EXEC_ASK="${L1_EXEC_ASK:-}"
case "$EXEC_ASK" in
  ""|always|on-miss|off) ;;
  *) echo "L1_EXEC_ASK 只接受 always / on-miss / off（内核 enum），收到：$EXEC_ASK" >&2; exit 2;;
esac

# 生成 openclaw.json —— 用 python 写，避免 shell 里手拼 JSON 与占位符不展开的问题
python3 - "$ISO" "$L1_PROVIDER_ID" "$L1_PROVIDER_BASE_URL" "$L1_PROVIDER_API_KEY" "$L1_MODEL_ID" "$EXEC_ASK" <<'PY'
import json, sys, pathlib
iso, pid, base, key, model, exec_ask = sys.argv[1:7]
cfg = {
  "agents": {"defaults": {
      "model": {"primary": f"{pid}/{model}"},
      "experimental": {"localModelLean": True}}},
  "models": {"providers": {pid: {"baseUrl": base, "apiKey": key, "api": "openai-completions"}}},
  # logging.file 必须设：不设则日志写进与用户实例共享的全局 /tmp/openclaw/（见 README §隔离三要素）
  "logging": {"file": f"{iso}/logs/openclaw-isolated.log"},
}
# 空字符串 = 这个键完全不出现在配置里（不是写一个 "off"）——保证「不设开关时生成的 openclaw.json
# 与 rounds/0015 之前逐字节相同」，默认行为零变化。
if exec_ask:
    # 落点 tools.exec.ask：`resolveExecDefaults` 读的是 `cfg.tools?.exec`
    # （kernels/openclaw/src/agents/exec-defaults.ts:90 `const globalExec = cfg.tools?.exec`），
    # 最终 ask = maxAsk(配置层求得的值, exec-approvals.json 求得的值)（同文件 :195）——approvals
    # 文件只能收紧不能放宽，所以这里配 always 一定生效。
    exec_cfg = {"ask": exec_ask}
    # on-miss 只在 security=allowlist 时才会触发审批（requiresExecApproval 的 on-miss 分支同时
    # 要求 security === "allowlist"，exec-approvals.ts:1855）；不一并设 security 的话这个档位
    # 会静默地什么都不做——那正是本项目反复吃过亏的那类"配了但没生效还以为配好了"。
    if exec_ask == "on-miss":
        exec_cfg["security"] = "allowlist"
    cfg["tools"] = {"exec": exec_cfg}
pathlib.Path(iso, "state", "openclaw.json").write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
PY

( cd kernels/openclaw && \
  OPENCLAW_STATE_DIR="$ISO/state" \
  OPENCLAW_WORKSPACE_DIR="$ISO/workspace" \
  OPENCLAW_GATEWAY_PORT="$PORT" \
  OPENCLAW_GATEWAY_TOKEN="$TOKEN" \
  OPENCLAW_SKIP_CHANNELS=1 \
  node scripts/run-node.mjs gateway --port "$PORT" --allow-unconfigured --token "$TOKEN" --no-color \
    > "$ISO/logs/gateway-stdout.log" 2>&1 & echo $! > "$ISO/gateway.pid" )

for _ in $(seq 1 60); do
  grep -q '\[gateway\] ready' "$ISO/logs/gateway-stdout.log" 2>/dev/null && break
  sleep 1
done
if ! grep -q '\[gateway\] ready' "$ISO/logs/gateway-stdout.log" 2>/dev/null; then
  echo "gateway 未在 60s 内就绪，日志尾部：" >&2; tail -20 "$ISO/logs/gateway-stdout.log" >&2; exit 1
fi

# 隔离自检：实例自报的日志落点必须在隔离目录内，不能是全局 /tmp/openclaw
if ! grep -m1 'log file:' "$ISO/logs/gateway-stdout.log" | grep -q "$ISO"; then
  echo "隔离检查失败：日志未落在 $ISO —— logging.file 没生效" >&2
  grep -m1 'log file:' "$ISO/logs/gateway-stdout.log" >&2; exit 1
fi

# 记录**真正监听端口的那个 PID**。不能只记 wrapper：
# `node scripts/run-node.mjs gateway` 起的 wrapper 会先退出，真正监听的子进程被 reparent 到 1，
# PPID 链因此追不回 wrapper（rounds/0012 实测：wrapper 56076 已退出，监听者 56313 的父进程也已 reparent）。
# 所以 stop 脚本的归属判定以**这个记录下来的 PID** 为准。
LISTENER_PID="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1)"
if [ -z "$LISTENER_PID" ]; then
  echo "gateway 报告 ready 但端口 $PORT 无监听者——异常" >&2; exit 1
fi
echo "$LISTENER_PID" > "$ISO/listener.pid"

cat > "$ISO/conn.env" <<ENV
export ISO="$ISO"
export PORT="$PORT"
export TOKEN="$TOKEN"
export AGENT_SHELL_KERNEL_URL="ws://127.0.0.1:$PORT"
export AGENT_SHELL_KERNEL_TOKEN="$TOKEN"
ENV

echo "gateway ready (pid $(cat "$ISO/gateway.pid")), port $PORT"
echo "隔离目录 ${ISO}；日志已确认落在隔离目录内"
if [ -n "$EXEC_ASK" ]; then
  echo "exec 审批策略：tools.exec.ask=$EXEC_ASK（已写入 $ISO/state/openclaw.json）"
  [ "$EXEC_ASK" = "always" ] && echo "  提示：ask=always 时内核给出的 allowedDecisions 是 [allow-once, deny]，不含 allow-always"
else
  echo "exec 审批策略：未配置 —— 内核默认 ask=off，agent 可直接执行 shell 命令而不发起任何审批"
  echo "  要做审批验收请设 L1_EXEC_ASK=always 重跑本脚本"
fi
echo "下一步： source $ISO/conn.env"
