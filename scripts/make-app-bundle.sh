#!/bin/bash
# make-app-bundle.sh — 把 swift build 产出的 CairnApp 可执行文件
# 组装成可被 `open` 打开的 Cairn.app bundle。
#
# 用法:
#   scripts/make-app-bundle.sh [debug|release] [--open | -o]
#
# 标志:
#   --open / -o    打包完成后自动 `open` 启动 app(默认只打包,不启动)
#
# 产物:
#   build/Cairn.app
set -euo pipefail

CONFIG="debug"
AUTO_OPEN=0

for arg in "$@"; do
    case "$arg" in
        debug|release)
            CONFIG="$arg"
            ;;
        --open|-o)
            AUTO_OPEN=1
            ;;
        *)
            echo "[make-app-bundle] ERROR: 未知参数 '$arg';用法见文件头注释" >&2
            exit 1
            ;;
    esac
done

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

if [[ "$AUTO_OPEN" -eq 1 ]]; then
    echo "[make-app-bundle] 启动中:open $BUNDLE"
    open "$BUNDLE"
else
    echo "[make-app-bundle] 要启动,请手动运行: open $BUNDLE"
    echo "[make-app-bundle] (或下次加 --open 标志自动启动)"
fi
