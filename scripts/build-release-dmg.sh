#!/bin/bash
# build-release-dmg.sh — release 构建 + app bundle + 未签名 DMG
#
# 产物:dist/Cairn-v${VERSION}-macos-arm64.dmg
#       dist/Cairn-v${VERSION}-macos-arm64.sha256
#
# 依赖:
#   - macOS 14+(Apple Silicon arm64)
#   - Xcode 15+(swift toolchain)
#   - hdiutil(macOS 原生)
#
# 不签名、不公证(spec §A9/A14)。
# 用户首次运行需:`sudo xattr -rd com.apple.quarantine /Applications/Cairn.app`
#
# 用法:
#   scripts/build-release-dmg.sh          # 默认 0.1.0-beta
#   CAIRN_VERSION=0.2.0 scripts/build-release-dmg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# v0.1 Beta 只支持 arm64(spec §8.5)。Intel Mac 上 build 会产 x86_64 bin
# 但 DMG 名字会误导。拒绝在非 arm64 上跑。
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "[build-dmg] ERROR: v0.1 Beta 只支持 Apple Silicon (arm64),当前 $ARCH" >&2
    echo "[build-dmg]   Intel Universal Binary 留 v0.2+" >&2
    exit 1
fi

VERSION="${CAIRN_VERSION:-0.1.0-beta}"
DMG_NAME="Cairn-v${VERSION}-macos-arm64"
DIST_DIR="dist"
BUILD_DIR="build"
STAGING_DIR="$BUILD_DIR/dmg-staging"

echo "[build-dmg] 1/5 Release build ..."
./scripts/make-app-bundle.sh release

if [[ ! -d "$BUILD_DIR/Cairn.app" ]]; then
    echo "[build-dmg] ERROR: $BUILD_DIR/Cairn.app 不存在" >&2
    exit 1
fi

echo "[build-dmg] 2/5 准备 staging 目录 ..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$BUILD_DIR/Cairn.app" "$STAGING_DIR/Cairn.app"
ln -s /Applications "$STAGING_DIR/Applications"

# INSTALL.txt 提示 xattr
cat > "$STAGING_DIR/INSTALL.txt" <<'EOF'
Cairn v0.1 Beta — 安装说明
===========================

1. 把 Cairn.app 拖到右侧 Applications 文件夹

2. 首次运行前,打开 Terminal.app 执行:

       sudo xattr -rd com.apple.quarantine /Applications/Cairn.app

3. 正常双击打开 Cairn.app

(Cairn 走永不签名路线 — MIT 项目不购买 Apple Developer 账号)

更多见 README:https://github.com/fps144/cairn
反馈 bug:https://github.com/fps144/cairn/issues
EOF

echo "[build-dmg] 3/5 生成 DMG ..."
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/${DMG_NAME}.dmg"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "Cairn" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "[build-dmg] 4/5 计算 SHA256 ..."
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
SHA_PATH="$DIST_DIR/${DMG_NAME}.sha256"
echo "$SHA256  ${DMG_NAME}.dmg" > "$SHA_PATH"

echo ""
echo "[build-dmg] 5/5 产物:"
ls -lh "$DIST_DIR" | grep -E "$DMG_NAME"
echo ""
echo "DMG:    $DMG_PATH"
echo "SHA256: $SHA256"
echo ""
echo "[build-dmg] 完成 — 可以 \`open $DMG_PATH\` 验证"
