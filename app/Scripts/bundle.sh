#!/bin/bash
# 把 SwiftPM 产出的可执行文件打成能双击运行的 .app。
#
# 为什么需要这一步：swift build 出来的是裸可执行文件，直接跑起来菜单栏图标不会正常出现——
# NSApplication 需要一个带 Info.plist 的 bundle 才能按 accessory 应用行为运行。
#
# 用法：./Scripts/bundle.sh [debug|release]        默认 debug
set -euo pipefail

CONFIG="${1:-debug}"
cd "$(dirname "$0")/.."

# 名字全是占位，等产品名定下来统一改这三行
APP_NAME="Image to Prompt"
EXECUTABLE="Image2Prompt"
BUNDLE_ID="com.raymond711xl.image2prompt"
VERSION="0.1.0"

swift build -c "$CONFIG"

BIN=".build/${CONFIG}/${EXECUTABLE}"
[ -f "$BIN" ] || { echo "找不到可执行文件：$BIN"; exit 1; }

APP=".build/${CONFIG}/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${EXECUTABLE}"

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

echo "已打包：$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
echo "运行：open \"$APP\""
