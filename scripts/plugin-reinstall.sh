#!/usr/bin/env bash
# 从本项目的插件 submodule 重装被测插件（harnessloop / hopper-plugin）。
#
# 作用：把全局 marketplace 的源指向本地 submodule，
# 然后卸载并重新安装插件，使 submodule 中的最新编辑生效
# （安装复制的是工作区内容，编辑无需先 commit）。
# 注意：安装完成后需要重启 Claude Code 会话才会加载新版本。
#
# 前提：claude CLI（支持 `claude plugin` 子命令）、python3。
#
# 用法: scripts/plugin-reinstall.sh [harnessloop|hopper|kata|all]
#       无参数默认 all（依次重装三个插件）。
set -Eeuo pipefail
# -E (errtrace)：核心逻辑在 reinstall_one() 函数里，默认 ERR trap 不会传入函数体，
# 必须显式 errtrace 否则函数内失败时 on_error 恢复提示不会触发（已用 bash 3.2 实测验证）。

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 插件配置表（bash 3.2 无关联数组，用 case 函数代替）。
# 新增被测插件时：在这四个函数里各加一个 case 分支，并把 key 加进 PLUGIN_ORDER。
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
plugin_github_fallback() {
  case "$1" in
    harnessloop) echo "surebeli/harnessloop" ;;
    hopper) echo "surebeli/hopper-plugin" ;;
    kata) echo "surebeli/kata" ;;
  esac
}
PLUGIN_ORDER="harnessloop hopper kata"

command -v claude >/dev/null || { echo "error: 未找到 claude CLI" >&2; exit 1; }

TARGET="${1:-all}"
case "$TARGET" in
  harnessloop|hopper|kata) PLUGINS_TO_RUN="$TARGET" ;;
  all) PLUGINS_TO_RUN="$PLUGIN_ORDER" ;;
  *)
    echo "error: 未知参数 '$TARGET'，用法: scripts/plugin-reinstall.sh [harnessloop|hopper|kata|all]" >&2
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

# 卸载/移除之后、安装成功之前中断，系统会处于「无插件」中间态——给出恢复指引。
CURRENT_PLUGIN=""
on_error() {
  echo >&2
  if [[ -n "$CURRENT_PLUGIN" ]]; then
    local id gh
    id="$(plugin_id "$CURRENT_PLUGIN")"
    gh="$(plugin_github_fallback "$CURRENT_PLUGIN")"
    echo "error: 重装中断（当前插件: ${CURRENT_PLUGIN}），该插件可能处于已卸载/未注册状态。" >&2
    echo "恢复: 修复上方报错后重跑 scripts/plugin-reinstall.sh ${CURRENT_PLUGIN}；" >&2
    echo "      或回退到 GitHub 源: claude plugin marketplace add $gh && claude plugin install $id" >&2
  else
    echo "error: 重装中断。" >&2
  fi
}
trap on_error ERR

# 上游新鲜度提醒（与 plugin-status.sh 的 show_upstream 同源判据）。重装是
# 「编辑 → 生效」链条的中点，此时若 submodule 落后 upstream，装进去的就是一个
# 陈旧基线上的版本；真实踩坑见 2026-07-28 hopper 落后 65 提交那次。
# 只警告不阻断：本地实验性改动本来就可能有意停在旧基线上。
warn_if_behind() {
  local submodule="$1" ref behind fetched="fresh"
  git -C "$submodule" fetch --quiet origin 2>/dev/null || fetched="stale"
  ref="$(git -C "$submodule" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [[ -z "$ref" ]] && ref="origin/main"
  git -C "$submodule" rev-parse --verify -q "$ref" >/dev/null 2>&1 || return 0
  behind="$(git -C "$submodule" rev-list --count "HEAD..${ref}" 2>/dev/null || echo 0)"
  if [[ "$behind" != 0 ]]; then
    echo "warn: 落后 ${ref} ${behind} 个提交$([[ "$fetched" == stale ]] && echo "（fetch 失败，该数字可能偏小）")"
    echo "      在陈旧基线上改动 → push 会撞 non-fast-forward，版本号也会与上游已发布版冲突"
    echo "      建议先 git -C ${submodule} pull --ff-only"
  elif [[ "$fetched" == stale ]]; then
    echo "warn: fetch 失败/离线——无法确认是否落后 upstream，下面的重装基于本地状态"
  fi
}

reinstall_one() {
  local key="$1"
  CURRENT_PLUGIN="$key"
  local submodule marketplace pid plugin_name
  submodule="$REPO_ROOT/$(plugin_submodule "$key")"
  marketplace="$(plugin_marketplace "$key")"
  pid="$(plugin_id "$key")"
  plugin_name="${pid%%@*}"

  echo "===== [$key] ====="

  if [[ ! -f "$submodule/.claude-plugin/marketplace.json" ]]; then
    echo "error: $submodule 不是有效的 marketplace（缺少 .claude-plugin/marketplace.json）" >&2
    echo "提示: 先执行 git submodule update --init" >&2
    exit 1
  fi

  local rel_source plugin_src_dir
  rel_source="$(resolve_plugin_source "$submodule" "$plugin_name")"
  plugin_src_dir="$(cd "$submodule" && cd "$rel_source" && pwd)"

  warn_if_behind "$submodule"

  echo "==> 校验 manifest"
  claude plugin validate "$submodule"
  if [[ "$plugin_src_dir" != "$submodule" ]]; then
    claude plugin validate "$plugin_src_dir"
  fi

  echo "==> 卸载旧插件并重指 marketplace 到本地 submodule"
  # 「本来就未安装/未注册」是正常情况，其余失败原因保留 stderr 供排查。
  claude plugin uninstall "$pid" \
    || echo "warn: uninstall 未成功（若本来未安装可忽略，否则看上方报错）"
  claude plugin marketplace remove "$marketplace" \
    || echo "warn: marketplace remove 未成功（若本来未注册可忽略，否则看上方报错）"
  claude plugin marketplace add "$submodule"

  echo "==> 从本地 marketplace 安装"
  claude plugin install "$pid"
  echo
}

for p in $PLUGINS_TO_RUN; do
  reinstall_one "$p"
done

trap - ERR
CURRENT_PLUGIN=""
"$REPO_ROOT/scripts/plugin-status.sh" "$TARGET" || echo "warn: 状态展示失败（不影响上面已完成的安装）"
echo
echo "完成。重启 Claude Code 会话后生效。"
