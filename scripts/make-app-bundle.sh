#!/bin/bash
# make-app-bundle.sh — 把 swift build 产出的 CairnApp 可执行文件
# 组装成可被 `open` 打开的 Cairn.app bundle。
#
# 用法:
#   scripts/make-app-bundle.sh [debug|release]
#
# 产物:
#   build/Cairn.app
set -euo pipefail

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "[make-app-bundle] ERROR: config 必须是 debug 或 release,收到 $CONFIG" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[make-app-bundle] swift build -c $CONFIG ..."
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/CairnApp"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "[make-app-bundle] ERROR: $BIN_PATH 不存在,check swift build 输出" >&2
    exit 1
fi

BUNDLE="build/Cairn.app"
echo "[make-app-bundle] 组装 $BUNDLE ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/CairnApp"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

chmod +x "$BUNDLE/Contents/MacOS/CairnApp"

echo "[make-app-bundle] 完成:$BUNDLE"
echo "[make-app-bundle] 启动:open $BUNDLE"
