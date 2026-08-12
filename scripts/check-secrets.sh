#!/usr/bin/env bash
# 凭证泄漏守门（2026-07-26 GitGuardian 事件后新增；同日经语义级普查加固）
#
# 背景：本项目的 evidence 文件与 vendor 原始日志（.hopper/handoffs/*-raw.txt|*.log）
# 由子代理/第三方 vendor 自动写入，会原样落真实运行配置。仓库是 PUBLIC，这条链此前
# 没有任何 secret 守门 —— 2026-07-26 一个真实 new-api token 因此进了公开历史
# （已轮换作废 + filter-repo 清史，详见 docs/security-incident-20260726.md）。
#
# 用法：
#   ./scripts/check-secrets.sh --staged            # pre-commit：只扫暂存内容
#   ./scripts/check-secrets.sh                     # 全树扫描（CI 用）
#   ./scripts/check-secrets.sh --update-digests    # 由本地 channel-params 重生成可提交的摘要表
#
# 三层判据：
#   L1-exact  精确值（最强，零误报）：读 gitignored 的 channel-params.json 逐值比对。
#             仅本地可用 —— CI checkout 里没有该文件。
#   L1-digest 摘要比对（CI 可用）：比对已提交的 scripts/secret-digests.txt（加盐 SHA-256，
#             不含明文）。把内容切成候选串逐个哈希匹配，使 CI 无明文也能跑 L1。
#   L2        形态兜底：已知前缀/PEM/URL 内嵌口令等正则。
#
# 抗绕过：所有比对同时在“原文”和“去空白流”上各做一次 —— vendor 终端转储会按列宽把
#         长 token 硬折行，折断后 L1 整串比对与 L2 正则会同时失效（普查实证的现实绕过）。
#
# 诚实声明纪律：**任何一层未实际运行，成功横幅必须如实标注 SKIPPED**。
#         （本脚本首版就犯过“L1 在 CI 里空跑却照报通过”的假绿，见事件档案 §7。）
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

MODE="${1:-tree}"
PARAMS=".harnessloop/local/channel-params.json"
DIGESTS="scripts/secret-digests.txt"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAIL=0
L1_EXACT="skipped"; L1_DIGEST="skipped"

# ── --update-digests：由本地明文生成可提交的摘要表 ──────────────────────────
if [ "$MODE" = "--update-digests" ]; then
  [ -f "$PARAMS" ] || { echo "❌ 需要本地 $PARAMS 才能生成摘要"; exit 1; }
  python3 - "$PARAMS" "$DIGESTS" <<'PY'
import json,sys,hashlib,os,re
params,out=sys.argv[1],sys.argv[2]
SENSITIVE=re.compile(r'pass|pwd|secret|token|key',re.I)
# 放行规则必须与上面 L1-exact 那份 allowed() 完全一致——2026-08-08 的迁移只改了 L1-exact，
# 这里当时留了一份写死的 SKIP 名单没跟着改，导致「同一份 channel-params，两套判据」：
# 新增 deepseek 线路时，L1-exact 已按 sensitivity 正确放行 DEEPSEEK_BASE_URL/
# DEEPSEEK_DEFAULT_MODEL（均声明 internal），但这里的旧 SKIP 名单不认识它们，照样把两个
# 公开值（endpoint URL、模型名）摘要进了 scripts/secret-digests.txt，反过来又让 L1-digest
# 在 ~21 个引用了该模型名的文件上假阳性拦截。两处判据不一致，永远会有一处先坏——
# 所以这里不再自己维护名单，直接复用 L1-exact 的同一条 allowed() 规则。
def allowed(name, meta):
    if not isinstance(meta, dict): return False
    return meta.get('sensitivity') == 'internal' and not SENSITIVE.search(name)
salt=None
if os.path.exists(out):
    for ln in open(out):
        m=re.match(r'#\s*salt=([0-9a-f]+)',ln)
        if m: salt=m.group(1)
salt=salt or os.urandom(16).hex()
cp=json.load(open(params)); rows=[]
for ch,cfg in (cp.get('channels') or {}).items():
    for k,v in (cfg.get('parameters') or {}).items():
        val=v.get('value','') if isinstance(v,dict) else str(v)
        # 摘要只收高熵长值：短/弱口令做成摘要有被离线爆破的风险，它们只在本地 L1-exact 覆盖
        if val and len(val)>=16 and not allowed(k, v):
            rows.append((k,hashlib.sha256((salt+val).encode()).hexdigest()))
with open(out,'w') as f:
    f.write("# 由 scripts/check-secrets.sh --update-digests 生成；仅含加盐 SHA-256，无明文。\n")
    f.write("# 用途：让 CI（拿不到 gitignored channel-params.json）也能跑 L1。\n")
    f.write("# 限制：只覆盖长度>=16 的高熵值；短口令仅本地 L1-exact 覆盖。轮换凭证后请重跑本命令。\n")
    f.write(f"# salt={salt}\n")
    for k,h in sorted(rows): f.write(f"{k}\t{h}\n")
print(f"已写 {out}：{len(rows)} 条摘要（salt 复用/新建）")
PY
  exit 0
fi

# ── 收集待扫内容（原文 + 去空白流） ────────────────────────────────────────
if [ "$MODE" = "--staged" ]; then
  git diff --cached --diff-filter=ACM -U0 > "$TMP/content" 2>/dev/null || true
  [ -s "$TMP/content" ] || { echo "✅ 无暂存内容"; exit 0; }
else
  git ls-files | grep -vE '^(kernels|hopper-plugin|harnessloop|kata)/' > "$TMP/filelist" || true
  : > "$TMP/content"
  while IFS= read -r f; do [ -f "$f" ] && cat "$f" >> "$TMP/content" 2>/dev/null; done < "$TMP/filelist"
fi
# 先剥 diff 行首 +/- 标记再去空白：否则 vendor 转储折行 + diff 前缀会把 token 粘断（实测绕过）
sed 's/^[+-]//' "$TMP/content" 2>/dev/null | tr -d '[:space:]' > "$TMP/content_nows" 2>/dev/null || : > "$TMP/content_nows"

hit_any() { # $1=待查值 —— 原文或去空白流命中都算
  grep -qF -- "$1" "$TMP/content" 2>/dev/null && return 0
  local stripped; stripped=$(printf '%s' "$1" | tr -d '[:space:]')
  [ -n "$stripped" ] && grep -qF -- "$stripped" "$TMP/content_nows" 2>/dev/null && return 0
  return 1
}

# ── L1-exact：本地明文逐值比对 ─────────────────────────────────────────────
if [ -f "$PARAMS" ]; then
  L1_EXACT="ran"
  python3 - "$PARAMS" > "$TMP/secrets" <<'PY'
import json,sys
cp=json.load(open(sys.argv[1]))
import re
SENSITIVE=re.compile(r'pass|pwd|secret|token|key',re.I)
# 放行规则：**发现式**，读 channel-params 自带的 `sensitivity` 声明，不再维护硬编码名单。
#
# 2026-08-08 改：此处原本是一份写死的 SKIP 名单
# （NEWAPI_BASE_URL/NEWAPI_UPSTREAM_BASE_URL/NEWAPI_UPSTREAM_TYPE/PI_HOST/PI_USER/
#  D3PROXY_LOCAL_PORT/D3_SEED_SESSION_ID）。问题是**每新增一条线路的非敏感参数都得手改这里**，
# 漏改就把 base-url、模型名之类当成凭证误报——加 deepseek 线路时就真误报了一次
# （`DEEPSEEK_DEFAULT_MODEL` 命中 L1-exact）。这与本仓一贯的「清单会过时，发现式守卫不会」相抵触。
#
# 新规则要求**两个条件同时成立**才放行，第二个是防自我声明失真的兜底：
#   1. 显式声明 `sensitivity == "internal"`；且
#   2. 参数名**不**像凭证（不含 pass/pwd/secret/token/key）。
# 于是把一个真凭证误标成 internal 但名字带 KEY/TOKEN 时，它仍然被守住——fail-closed。
# 已核对：原 7 条 SKIP 全部满足这两条，新规则完全覆盖旧名单，无放行面收缩。
def allowed(name, meta):
    if not isinstance(meta, dict): return False
    return meta.get('sensitivity') == 'internal' and not SENSITIVE.search(name)
for ch,cfg in (cp.get('channels') or {}).items():
    for k,v in (cfg.get('parameters') or {}).items():
        val=v.get('value','') if isinstance(v,dict) else str(v)
        if not val or allowed(k, v): continue
        # 名字像凭证的把门槛降到 8：短口令（如 DB/root 密码）此前从不被检查
        floor = 8 if SENSITIVE.search(k) else 16
        if len(val) >= floor:
            print(k+"\t"+val)
PY
  while IFS=$'\t' read -r name val; do
    [ -z "${val:-}" ] && continue
    if hit_any "$val"; then
      echo "❌ [L1-exact] 命中真实凭证值：$name"
      [ "$MODE" != "--staged" ] && git grep -lF -- "$val" 2>/dev/null | sed 's/^/     /'
      FAIL=1
    fi
  done < "$TMP/secrets"
fi

# ── L1-digest：摘要比对（CI 无明文也能跑） ─────────────────────────────────
if [ -f "$DIGESTS" ] && grep -q '^# salt=' "$DIGESTS" 2>/dev/null; then
  L1_DIGEST="ran"
  python3 - "$DIGESTS" "$TMP/content" "$TMP/content_nows" <<'PY' > "$TMP/dighits" || true
import sys,re,hashlib
dg,c1,c2=sys.argv[1],sys.argv[2],sys.argv[3]
salt=None; want={}
for ln in open(dg):
    m=re.match(r'#\s*salt=([0-9a-f]+)',ln)
    if m: salt=m.group(1); continue
    if ln.startswith('#') or not ln.strip(): continue
    k,h=ln.rstrip('\n').split('\t'); want[h]=k
if not salt: sys.exit(0)
text=open(c1,encoding='utf-8',errors='ignore').read()+"\n"+open(c2,encoding='utf-8',errors='ignore').read()
# 候选串：长度>=16 的 token 形字符集连续段（覆盖折行后被拼回的去空白流）
cands=set(re.findall(r'[A-Za-z0-9_\-\.]{16,}',text))
for c in cands:
    # 长串的每个 >=16 的前后缀切片也算候选，抗前后粘连（如 "key:"+token 或 token+","）
    variants={c, c.strip('.-_')}
    for v in list(variants):
        h=hashlib.sha256((salt+v).encode()).hexdigest()
        if h in want: print(want[h])
PY
  if [ -s "$TMP/dighits" ]; then
    sort -u "$TMP/dighits" | while read -r n; do echo "❌ [L1-digest] 命中已登记凭证摘要：$n"; done
    FAIL=1
  fi
fi

# ── L2：形态兜底 ───────────────────────────────────────────────────────────
PATTERNS='\bsk-[A-Za-z0-9_-]{20,}'
PATTERNS="$PATTERNS"'|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'
PATTERNS="$PATTERNS"'|-----BEGIN [A-Z ]*PRIVATE KEY-----'
PATTERNS="$PATTERNS"'|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]{6,}@'
PATTERNS="$PATTERNS"'|\bgithub_pat_[A-Za-z0-9_]{22,}|\bghp_[A-Za-z0-9]{36}|\bglpat-[A-Za-z0-9_-]{20,}'
PATTERNS="$PATTERNS"'|\bAKIA[0-9A-Z]{16}|\bASIA[0-9A-Z]{16}|\bAIza[0-9A-Za-z_-]{35}'
PATTERNS="$PATTERNS"'|hooks\.slack\.com/services/[A-Za-z0-9/]{20,}|xox[baprs]-[A-Za-z0-9-]{12,}'
PATTERNS="$PATTERNS"'|\bhf_[A-Za-z0-9]{30,}|\bnpm_[A-Za-z0-9]{30,}|\bdop_v1_[a-f0-9]{60,}|\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
{ grep -Eo "$PATTERNS" "$TMP/content" 2>/dev/null; grep -Eo "$PATTERNS" "$TMP/content_nows" 2>/dev/null; } \
  | grep -viE 'REDACTED|EXAMPLE|PLACEHOLDER|xxxx|your-|change-me|<.*>' \
  | sort -u > "$TMP/l2" || true
if [ -s "$TMP/l2" ]; then
  echo "⚠️  [L2] 疑似凭证形态串（确认为假值请加 REDACTED 标记）："
  sed 's/^/     /' "$TMP/l2" | head -8
  FAIL=1
fi

# ── 结论：如实声明哪几层真的跑了 ───────────────────────────────────────────
LAYERS="L2"
[ "$L1_EXACT" = "ran" ] && LAYERS="L1-exact + $LAYERS"
[ "$L1_DIGEST" = "ran" ] && LAYERS="L1-digest + $LAYERS"
if [ "$FAIL" -ne 0 ]; then
  cat <<'MSG'

——— 拦截：疑似凭证入库 ———
本仓库是 PUBLIC。真实凭证一旦进历史，轮换 + filter-repo 重写是唯一补救（代价高）。
处理：换占位符/脱敏，或把文件加进 .gitignore；确属假值时用 REDACTED 标注。
参考：docs/security-incident-20260726.md
MSG
  exit 1
fi
echo "✅ secret 扫描通过（实际运行层：${LAYERS}）"
if [ "$L1_EXACT" != "ran" ] && [ "$L1_DIGEST" != "ran" ]; then
  echo "⚠️  警告：L1 两种模式均未运行（无 ${PARAMS} 也无 ${DIGESTS}）——本次只有 L2 形态兜底，覆盖面显著弱化。"
fi
