#!/usr/bin/env bash
set -euo pipefail

# 组装 AgentShell.app —— SG-10 L1 Mac UI 壳。
#
# SwiftPM `swift build` 只产出一个裸 Mach-O 可执行文件，没有 Info.plist/bundle 目录结构；
# SwiftUI app 要正常拿到窗口与键盘焦点、被 Dock/App Switcher 当成一个"真正的 App"而不是命令行
# 进程，需要一个标准 `.app` bundle（本轮 scope-lock 硬约束1：不建 .xcodeproj，手工组装）。本脚本
# 只做"编译 + 拼 bundle 目录 + 塞 Info.plist + ad-hoc 签名"，不引入 Xcode 工程、不需要 GUI session。
#
# 用法（从仓库任意目录都可以跑，脚本自己定位 app/ 包根）：
#   app/apps/AgentShell/build-app-bundle.sh                          # debug 构建
#   CONFIGURATION=release app/apps/AgentShell/build-app-bundle.sh    # release 构建
#   AGENT_SHELL_APP_ROOT=/custom/path/AgentShell.app app/apps/AgentShell/build-app-bundle.sh
#
# 产出：$AGENT_SHELL_APP_ROOT，默认 app/.build/AgentShell.app——落在 app/.gitignore 已经忽略的
# app/.build/ 下，不需要新增 gitignore 规则。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$SCRIPT_DIR"
APP_PACKAGE_DIR="$(cd "$SHELL_DIR/../.." && pwd)"  # -> app/（SwiftPM 包根，见 app/Package.swift）
PRODUCT="AgentShell"
CONFIGURATION="${CONFIGURATION:-debug}"

echo "==> swift build --package-path $APP_PACKAGE_DIR --product $PRODUCT -c $CONFIGURATION"
swift build --package-path "$APP_PACKAGE_DIR" --product "$PRODUCT" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$APP_PACKAGE_DIR" -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BIN_DIR/$PRODUCT"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "ERROR: 构建产物未找到: $BIN_PATH" >&2
  exit 1
fi

APP_ROOT="${AGENT_SHELL_APP_ROOT:-$APP_PACKAGE_DIR/.build/$PRODUCT.app}"
echo "==> 组装 bundle: $APP_ROOT"
rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS"
mkdir -p "$APP_ROOT/Contents/Resources"

cp "$SHELL_DIR/Resources/Info.plist" "$APP_ROOT/Contents/Info.plist"
cp "$BIN_PATH" "$APP_ROOT/Contents/MacOS/$PRODUCT"
chmod +x "$APP_ROOT/Contents/MacOS/$PRODUCT"

if command -v codesign >/dev/null 2>&1; then
  echo "==> ad-hoc 签名整个 bundle（SwiftPM 产出的裸二进制签名在拼装后已失效，需要对整个 bundle 重签）"
  codesign --force --deep --sign - "$APP_ROOT"
fi

echo "OK: $APP_ROOT"
echo "   打开：open \"$APP_ROOT\""
