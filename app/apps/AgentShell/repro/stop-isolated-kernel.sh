#!/usr/bin/env bash
# 停掉 start-isolated-kernel.sh 起的隔离实例，并核实端口真的释放了。
#
# 为什么需要这个脚本而不是 `kill $(cat gateway.pid)`：
#   `node scripts/run-node.mjs gateway` 会**再 fork 一个子进程**真正监听端口。
#   pid 文件记的是 wrapper，杀 wrapper 之后**监听端口的子进程可能仍然活着**——
#   rounds/0012 实测撞过：kill 完 pid 文件里的进程，端口 53709 仍被占用。
#   所以这里以**端口占用者**为准，而不是以 pid 文件为准。
set -uo pipefail

ROOT="${L1_ROOT:-/tmp/l1-repro}"
[ -f "$ROOT/conn.env" ] && . "$ROOT/conn.env"
PORT="${PORT:-${1:-}}"

if [ -z "${PORT:-}" ]; then
  echo "无法确定端口：既没有 $ROOT/conn.env，也没有作为参数传入" >&2
  exit 2
fi

# 只杀"本次启动时真正在监听该端口的那个进程"，避免误杀后来占用同一端口的无关服务。
#
# 为什么不用 PPID 链：`node scripts/run-node.mjs gateway` 的 wrapper 会先退出，
# 真正监听的子进程被 reparent 到 1——rounds/0012 实测（wrapper 56076 已退出，
# 监听者 56313 的父进程也已 reparent 到 1），PPID 链追不回 wrapper，判定必然失败。
# 所以以 start 脚本落盘的 listener.pid 为准。
owned_by_us() {  # $1=pid
  [ -f "$ROOT/listener.pid" ] || return 1
  [ "$1" = "$(cat "$ROOT/listener.pid")" ]
}

kill_port() {  # $1=port  —— 先 TERM 后 KILL，以端口占用者为准（且须通过 owned_by_us）
  local p="$1" pid
  pid="$(lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | head -1)"
  [ -z "$pid" ] && return 0
  if ! owned_by_us "$pid"; then
    echo "✗ 端口 $p 的占用者 PID $pid 不在本次启动的进程树内——拒绝杀，可能是无关服务。" >&2
    echo "   （若确认可杀，请自行处理；本脚本不替你做这个决定。）" >&2
    return 1
  fi
  kill -TERM "$pid" 2>/dev/null
  for _ in $(seq 1 10); do
    sleep 1
    lsof -tiTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 || return 0
  done
  pid="$(lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | head -1)"
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  sleep 1
}

# wrapper 也顺手收掉（它自己不监听端口，但留着是僵进程）
[ -f "$ROOT/gateway.pid" ] && kill -TERM "$(cat "$ROOT/gateway.pid")" 2>/dev/null
kill_port "$PORT"

if lsof -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "✗ 端口 $PORT 仍被占用：$(lsof -tiTCP:"$PORT" -sTCP:LISTEN | head -1)" >&2
  exit 1
fi
echo "✓ 端口 $PORT 已释放"

# 隔离目录属本次新建，可整体删除；**不删除任何非本次新建的东西**
if [ "${L1_KEEP_DIR:-}" = "1" ]; then
  echo "  保留隔离目录 ${ROOT}（L1_KEEP_DIR=1）"
else
  rm -rf "$ROOT" && echo "  已删除隔离目录 $ROOT"
fi
