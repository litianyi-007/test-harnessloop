#!/usr/bin/env bash
set -euo pipefail

# AgentShell 图标生成驱动 —— round 0021。
#
# 本机没有任何 SVG 光栅化工具（rsvg-convert / inkscape / ImageMagick / cairosvg 均未装，已实测
# 确认），改用「Swift + Core Graphics 直接画精确像素尺寸的 PNG，iconutil 拼 .icns」这条路径
# （同样已实测确认可行）。这个目录不是 SwiftPM target（app/Package.swift 没有任何 target 的
# path 指向这里）——图标生成器是构建期工具，不是 app 运行时代码，所以用裸 swiftc 编译，
# 不进包依赖图。
#
# 用法：
#   app/apps/AgentShell/Resources/icon-source/generate-icons.sh
#
# 产出落两处：
#   1. app/apps/AgentShell/Resources/{AppIcon.icns,MenuBarIconTemplate.png,MenuBarIconTemplate@2x.png}
#      —— 随 build-app-bundle.sh 打进 app bundle 的最终资产（本脚本负责拷贝到位，
#      入库哪些文件由 git 决定，这里不碰 git）。
#   2. <repo-root>/.harnessloop/goals/20260718-002-agent-app/rounds/0021/evidence/icon-contact-sheet.png
#      —— 人工核验用的对照表，不参与打包。
#
# 中间产物（.iconset 目录、iconutil round-trip 目录、编译出的生成器二进制）全部留在
# icon-source/.build/ 下——这个名字特意选的：app/.gitignore 里已经有一条不带前导斜杠的
# `.build/` 规则（对 SwiftPM 的 app/.build/ 生效），按 gitignore 语义那条规则在任意深度都生效，
# 所以这里不需要再加一条新规则。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

BUILD_DIR="$SCRIPT_DIR/.build"
GENERATOR_BIN="$BUILD_DIR/generate-icons"
OUT_DIR="$BUILD_DIR/out"

mkdir -p "$BUILD_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> 编译图标生成器"
xcrun swiftc -O \
  "$SCRIPT_DIR/IconGeometry.swift" \
  "$SCRIPT_DIR/IconRenderer.swift" \
  "$SCRIPT_DIR/main.swift" \
  -o "$GENERATOR_BIN"

echo "==> 运行生成器 -> $OUT_DIR"
"$GENERATOR_BIN" "$OUT_DIR"

ICONSET_DIR="$OUT_DIR/AppIcon.iconset"
ICNS_PATH="$OUT_DIR/AppIcon.icns"

echo "==> iconutil：iconset -> icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "==> iconutil round-trip 校验：icns -> iconset，比对文件清单"
ROUNDTRIP_DIR="$OUT_DIR/AppIcon-roundtrip.iconset"
rm -rf "$ROUNDTRIP_DIR"
iconutil -c iconset "$ICNS_PATH" -o "$ROUNDTRIP_DIR"
echo "--- round-trip iconset 实际包含的尺寸（不是"意图"，是 iconutil 从 .icns 里读回来的） ---"
sips -g pixelWidth -g pixelHeight "$ROUNDTRIP_DIR"/*.png | grep -E "^/|pixelWidth|pixelHeight"

ORIGINAL_LIST="$(cd "$ICONSET_DIR" && ls | sort)"
ROUNDTRIP_LIST="$(cd "$ROUNDTRIP_DIR" && ls | sort)"
if [[ "$ORIGINAL_LIST" != "$ROUNDTRIP_LIST" ]]; then
  echo "ERROR: round-trip 文件清单与原始 iconset 不一致" >&2
  diff <(echo "$ORIGINAL_LIST") <(echo "$ROUNDTRIP_LIST") >&2 || true
  exit 1
fi
echo "OK: round-trip 文件清单一致（10/10）"

echo "==> 安装最终资产到 $RESOURCES_DIR"
cp "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"
cp "$OUT_DIR/MenuBarIconTemplate.png" "$RESOURCES_DIR/MenuBarIconTemplate.png"
cp "$OUT_DIR/MenuBarIconTemplate@2x.png" "$RESOURCES_DIR/MenuBarIconTemplate@2x.png"

EVIDENCE_DIR="$REPO_ROOT/.harnessloop/goals/20260718-002-agent-app/rounds/0021/evidence"
mkdir -p "$EVIDENCE_DIR"
cp "$OUT_DIR/icon-contact-sheet.png" "$EVIDENCE_DIR/icon-contact-sheet.png"

echo "OK"
echo "  $RESOURCES_DIR/AppIcon.icns"
echo "  $RESOURCES_DIR/MenuBarIconTemplate.png"
echo "  $RESOURCES_DIR/MenuBarIconTemplate@2x.png"
echo "  $EVIDENCE_DIR/icon-contact-sheet.png"
