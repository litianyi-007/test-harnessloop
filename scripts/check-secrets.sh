#!/usr/bin/env bash
# 凭证泄漏守门（2026-07-26 GitGuardian 事件后新增）
#
# 背景：本项目的 evidence 文件与 vendor 原始日志（.hopper/handoffs/*-raw.txt|*.log）
# 由子代理/第三方 vendor 自动写入，会原样落真实运行配置。仓库是 PUBLIC，这条链此前
# 没有任何 secret 守门 —— 2026-07-26 一个真实 new-api token 因此进了公开历史
# （已轮换作废 + filter-repo 清史，详见 docs/security-incident-20260726.md）。
#
# 用法：
#   ./scripts/check-secrets.sh --staged   # pre-commit：只扫暂存内容
#   ./scripts/check-secrets.sh            # 全树扫描（CI 用）
#
# 判据两层：
#   L1 精确值（零误报，正是本次泄漏那一类）：读 gitignored 的
#      .harnessloop/local/channel-params.json，其中每个长度 >= 16 的参数值必须零命中。
#   L2 形态兜底：已知前缀/高熵模式，覆盖 channel-params 之外来源。
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

MODE="${1:-tree}"
PARAMS=".harnessloop/local/channel-params.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# ── 收集待扫内容到临时文件 ──────────────────────────────────────────────────
if [ "$MODE" = "--staged" ]; then
  git diff --cached --diff-filter=ACM -U0 > "$TMP/content" 2>/dev/null || true
  [ -s "$TMP/content" ] || { echo "✅ 无暂存内容"; exit 0; }
else
  # 只扫本仓自有文件，排除 submodule（各自独立仓、各自守门）
  git ls-files | grep -vE '^(kernels|hopper-plugin|harnessloop|kata)/' > "$TMP/filelist" || true
  : > "$TMP/content"
  while IFS= read -r f; do
    [ -f "$f" ] && cat "$f" >> "$TMP/content" 2>/dev/null
  done < "$TMP/filelist"
fi

# ── L1：channel-params 真实值 ───────────────────────────────────────────────
if [ -f "$PARAMS" ]; then
  python3 - "$PARAMS" > "$TMP/secrets" <<'PY'
import json,sys
cp=json.load(open(sys.argv[1]))
SKIP={'NEWAPI_BASE_URL','NEWAPI_UPSTREAM_BASE_URL','NEWAPI_UPSTREAM_TYPE',
      'PI_HOST','PI_USER','D3PROXY_LOCAL_PORT','D3_SEED_SESSION_ID'}
for ch,cfg in (cp.get('channels') or {}).items():
    for k,v in (cfg.get('parameters') or {}).items():
        val = v.get('value','') if isinstance(v,dict) else str(v)
        if val and len(val) >= 16 and k not in SKIP:
            print(k + "\t" + val)
PY
  while IFS=$'\t' read -r name val; do
    [ -z "${val:-}" ] && continue
    if grep -qF -- "$val" "$TMP/content" 2>/dev/null; then
      echo "❌ [L1] 命中真实凭证值：$name"
      if [ "$MODE" != "--staged" ]; then
        git grep -lF -- "$val" -- $(cat "$TMP/filelist" | tr '\n' ' ') 2>/dev/null | sed 's/^/     /'
      fi
      FAIL=1
    fi
  done < "$TMP/secrets"
fi

# ── L2：形态模式兜底（REDACTED 标注的显式放行） ─────────────────────────────
PATTERNS='\bsk-[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|\bAKIA[0-9A-Z]{16}|\bghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{12,}'
grep -Eo "$PATTERNS" "$TMP/content" 2>/dev/null \
  | grep -viE 'REDACTED|EXAMPLE|PLACEHOLDER|xxxx|your-|<.*>' \
  | sort -u > "$TMP/l2" || true
if [ -s "$TMP/l2" ]; then
  echo "⚠️  [L2] 疑似凭证形态串（确认为假值请加 REDACTED 标记）："
  sed 's/^/     /' "$TMP/l2" | head -8
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  cat <<'MSG'

——— 拦截：疑似凭证入库 ———
本仓库是 PUBLIC。真实凭证一旦进历史，轮换 + filter-repo 重写是唯一补救（代价高）。
处理：换占位符/脱敏，或把文件加进 .gitignore；确属假值时用 REDACTED 标注。
参考：docs/security-incident-20260726.md
MSG
  exit 1
fi
echo "✅ secret 扫描通过（L1 精确值 + L2 形态）"
