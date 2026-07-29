#!/bin/bash
# 把 SwiftPM 产出的可执行文件打成能双击运行的 .app。
#
# 为什么需要这一步：swift build 出来的是裸可执行文件，直接跑起来菜单栏图标不会正常出现——
# NSApplication 需要一个带 Info.plist 的 bundle 才能按 accessory 应用行为运行。
#
# 用法：
#   ./Scripts/bundle.sh                 debug 构建，产物留在 .build/
#   ./Scripts/bundle.sh release         release 构建
#   ./Scripts/bundle.sh release install 顺便装进 /Applications
set -euo pipefail

CONFIG="${1:-debug}"
INSTALL="${2:-}"
cd "$(dirname "$0")/.."

# 名字全是占位，等产品名定下来统一改这三行
APP_NAME="Image to Prompt"
EXECUTABLE="Image2Prompt"
BUNDLE_ID="com.raymond711xl.image2prompt"
VERSION="0.1.0"

swift build -c "$CONFIG"

# SwiftPM 在有资源的情况下把产物放进 arch 子目录，用 --show-bin-path 拿准确位置
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="${BIN_DIR}/${EXECUTABLE}"
[ -f "$BIN" ] || { echo "找不到可执行文件：$BIN"; exit 1; }

APP="${BIN_DIR}/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${EXECUTABLE}"

# 资源 bundle 必须一起搬进去，否则分析指令和 schema 读不到
for bundle in "${BIN_DIR}"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${EXECUTABLE}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- 菜单栏常驻工具：不要 Dock 图标，不要主菜单栏 -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# ad-hoc 签名。分发给别人需要开发者证书 + 公证，那要等装了 Xcode。
codesign --force --sign - "$APP" 2>/dev/null || echo "警告：ad-hoc 签名失败，本机自用不影响"

echo "已打包：$APP"

if [ "$INSTALL" = "install" ]; then
    TARGET="/Applications/${APP_NAME}.app"
    # 装新版之前先退掉在跑的，否则会替换一个正在运行的 bundle
    pkill -f "${APP_NAME}.app" 2>/dev/null || true
    sleep 1
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    echo "已安装：$TARGET"
    echo "双击启动，或：open \"$TARGET\""
else
    echo "运行：open \"$APP\""
fi
