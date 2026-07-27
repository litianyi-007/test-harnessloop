#!/usr/bin/env bash
# 对照显示：submodule 当前状态 vs 全局实际安装的插件（harnessloop / hopper / kata），
# 并做内容级比对（diff），确认「编辑 → 重装」是否真正生效。
#
# 用法: scripts/plugin-status.sh [harnessloop|hopper|kata|all]
#       无参数默认 all（依次展示三个插件）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="$HOME/.claude/plugins"

# 插件配置表（bash 3.2 无关联数组，用 case 函数代替）。
# 新增被测插件时：在这三个函数里各加一个 case 分支，并把 key 加进 PLUGIN_ORDER。
plugin_submodule() {
  case "$1" in
    harnessloop) echo "harnessloop" ;;
    hopper) echo "hopper-plugin" ;;
    kata) echo "kata" ;;
  esac
}
plugin_marketplace() {
  case "$1" in
    harnessloop) echo "harnessloop" ;;
    hopper) echo "agent-hopper" ;;
    kata) echo "kata" ;;
  esac
}
plugin_id() {
  case "$1" in
    harnessloop) echo "harnessloop@harnessloop" ;;
    hopper) echo "hopper@agent-hopper" ;;
    kata) echo "kata@kata" ;;
  esac
}
PLUGIN_ORDER="harnessloop hopper kata"

TARGET="${1:-all}"
case "$TARGET" in
  harnessloop|hopper|kata) PLUGINS_TO_SHOW="$TARGET" ;;
  all) PLUGINS_TO_SHOW="$PLUGIN_ORDER" ;;
  *)
    echo "error: 未知参数 '$TARGET'，用法: scripts/plugin-status.sh [harnessloop|hopper|kata|all]" >&2
    exit 1
    ;;
esac

# 插件源码目录不硬编码——从各自 submodule 的 .claude-plugin/marketplace.json
# 的 plugins[].source 动态读取（不同插件的 source 可能不同：例如 harnessloop
# 是 ./plugins/harnessloop 子目录，hopper 是 ./ 即 submodule 根目录本身）。
resolve_plugin_source() {
  local submodule="$1" name="$2"
  python3 - "$submodule/.claude-plugin/marketplace.json" "$name" <<'PYEOF'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as e:
    print(f"error: 读取 {path} 失败: {type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
plugins = data.get('plugins') or []
match = next((p for p in plugins if p.get('name') == name), None)
if match is None and len(plugins) == 1:
    match = plugins[0]
if match is None:
    print(f"error: marketplace.json 中未找到名为 {name} 的插件条目", file=sys.stderr)
    sys.exit(1)
src = match.get('source')
if not src:
    print("error: 插件条目缺少 source 字段", file=sys.stderr)
    sys.exit(1)
print(src)
PYEOF
}

# 从 installed_plugins.json 按 plugin id 取第一条已装记录的 installPath 字段
# （直接用该字段，不自行拼版本号路径——避免命名/版本目录结构假设错误）。
resolve_install_path() {
  local pid="$1"
  python3 - "$PLUGINS_DIR" "$pid" <<'PYEOF'
import json, sys, os
d, pid = sys.argv[1], sys.argv[2]
try:
    with open(os.path.join(d, 'installed_plugins.json')) as f:
        inst = json.load(f)
except Exception:
    sys.exit(0)
entries = (inst.get('plugins') or {}).get(pid) or []
if entries:
    ip = entries[0].get('installPath')
    if ip:
        print(ip)
PYEOF
}

# 上游新鲜度。这个回路的真实踩坑点（2026-07-28）：hopper submodule 落后
# upstream 65 个提交而无人察觉，在陈旧基线上做完的一版改动整个作废、必须在
# 上游最新提交之上重做。CLAUDE.md 的「直接改 submodule 再 push」隐含假设了
# submodule 是最新的，这一步把那个假设变成可见事实。
#
# 诚实横幅纪律（同 check-secrets.sh）：fetch 可能失败（离线/无权限/超时），
# 失败时必须如实说明对比基准是本地缓存的远端 ref、可能过时——绝不把「没刷新」
# 报成「已是最新」。
show_upstream() {
  local submodule="$1" ref fetched="fresh" behind ahead note
  if ! git -C "$submodule" fetch --quiet origin 2>/dev/null; then
    fetched="stale"
  fi
  ref="$(git -C "$submodule" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [[ -z "$ref" ]] && ref="origin/main"
  if ! git -C "$submodule" rev-parse --verify -q "$ref" >/dev/null 2>&1; then
    echo "upstream  (无 ${ref} 引用，跳过对比)"
    return 0
  fi
  behind="$(git -C "$submodule" rev-list --count "HEAD..$ref" 2>/dev/null || echo '?')"
  ahead="$(git -C "$submodule" rev-list --count "$ref..HEAD" 2>/dev/null || echo '?')"
  if [[ "$fetched" == fresh ]]; then
    note="基准 ${ref}（本次已 fetch）"
  else
    note="基准 ${ref}（fetch 失败/离线，可能过时）"
  fi
  echo "upstream 落后 ${behind} / 领先 ${ahead} —— ${note}"
  if [[ "$behind" != 0 && "$behind" != '?' ]]; then
    echo "警告     先 git -C $submodule pull --ff-only 再动手；在陈旧基线上做的"
    echo "         改动会撞 non-fast-forward，且版本号会与上游已发布版本冲突"
  fi
}

show_one() {
  local key="$1" submodule_name marketplace pid plugin_name submodule
  submodule_name="$(plugin_submodule "$key")"
  marketplace="$(plugin_marketplace "$key")"
  pid="$(plugin_id "$key")"
  plugin_name="${pid%%@*}"
  submodule="$REPO_ROOT/$submodule_name"

  echo "===== [$key] ====="
  echo "== submodule ($submodule_name/) =="
  if ! git -C "$submodule" rev-parse HEAD >/dev/null 2>&1; then
    echo "(submodule 未初始化，先执行 git submodule update --init)"
    echo
    return 0
  fi
  git -C "$submodule" log -1 --format='commit   %h  %s'
  show_upstream "$submodule"
  local dirty
  dirty=$(git -C "$submodule" status --short | wc -l | tr -d ' ')

  local rel_source plugin_src_dir version
  plugin_src_dir=""
  version="?"
  rel_source="$(resolve_plugin_source "$submodule" "$plugin_name")" && {
    plugin_src_dir="$(cd "$submodule" && cd "$rel_source" && pwd)"
  }
  if [[ -n "$plugin_src_dir" && -f "$plugin_src_dir/.claude-plugin/plugin.json" ]]; then
    version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
      "$plugin_src_dir/.claude-plugin/plugin.json" 2>/dev/null || echo '?')
  fi
  echo "version  $version"
  echo "dirty    $dirty 个未提交变更"
  if [[ "$dirty" != 0 ]]; then
    echo "注意     安装缓存复制的是工作区内容；上面的 commit sha 不代表缓存内容"
  fi

  echo
  echo "== 全局注册 =="
  python3 - "$PLUGINS_DIR" "$marketplace" "$pid" <<'EOF' || echo "(读取插件注册表失败，见上方诊断)"
import json, sys, os
d, marketplace, pid = sys.argv[1], sys.argv[2], sys.argv[3]

def load(name):
    p = os.path.join(d, name)
    try:
        with open(p) as f:
            return json.load(f)
    except Exception as e:
        print(f"{name}: 读取失败 ({type(e).__name__}: {e})")
        return None

mk = load('known_marketplaces.json')
if mk is not None:
    entry = mk.get(marketplace) if isinstance(mk, dict) else None
    if entry:
        src = entry.get('source', {})
        print(f"marketplace source: {src.get('source')} {src.get('repo') or src.get('path') or ''}".rstrip())
    else:
        print("marketplace: 未注册")

inst = load('installed_plugins.json')
if inst is not None:
    entries = (inst.get('plugins') or {}).get(pid) or []
    for e in entries:
        print(f"installed: v{e.get('version')}  sha {str(e.get('gitCommitSha'))[:7]}  at {e.get('lastUpdated')}")
        ip = e.get('installPath')
        if ip:
            print(f"installPath: {ip}")
    if not entries:
        print("plugin: 未安装")
EOF

  echo
  echo "== 内容比对 (submodule 插件源码 ↔ 安装缓存) =="
  local install_path
  install_path="$(resolve_install_path "$pid")"
  # -x 排除的是安装/仓库日常目录（.git 工作树元数据、node_modules 依赖、
  # .in_use 安装态标记、__pycache__ 编译缓存），非源码内容——不排除会把这些
  # 目录差异误报成「源码漂移」，掩盖真正需要关注的信号。
  local diff_excludes=(-x .git -x node_modules -x .in_use -x __pycache__)
  if [[ -n "$plugin_src_dir" && -n "$install_path" && -d "$install_path" ]]; then
    if diff -rq "${diff_excludes[@]}" "$plugin_src_dir" "$install_path" >/dev/null 2>&1; then
      echo "一致：缓存内容 == submodule 工作区"
    else
      echo "不一致（有编辑尚未重装，或安装不完整）："
      # diff 有差异时退出码非 0；配合 set -e/pipefail 若不吞掉会中断整个脚本
      # （差异是预期展示内容，不是脚本错误，故这里显式吞掉退出码）。
      diff -rq "${diff_excludes[@]}" "$plugin_src_dir" "$install_path" 2>&1 | head -10 || true
    fi
  else
    echo "(缓存目录不存在或未安装: ${install_path:-未知})"
  fi
  echo
}

for p in $PLUGINS_TO_SHOW; do
  show_one "$p"
done
