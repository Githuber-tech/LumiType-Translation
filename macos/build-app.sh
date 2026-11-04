#!/usr/bin/env bash
# 打包 .app：编译 → 组 bundle → 生成 icns → ad-hoc 签名 → 压缩 DMG 用的 zip。
#
# 用法：
#   bash build-app.sh            # release 构建 + 打包
#   bash build-app.sh debug      # debug 构建 + 打包
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
SCRATCH="${LUMITYPE_SCRATCH:-$HOME/Library/Caches/LumiTypeBuild}"
APP_NAME="LumiType"
VERSION="2.0.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> 构建 ($CONFIG)"
# 默认出通用二进制（Apple Silicon + Intel），单架构可用 LUMITYPE_ARCHS=arm64 覆盖。
ARCHS="${LUMITYPE_ARCHS:-arm64 x86_64}"
BINS=()
for arch in $ARCHS; do
  echo "    - $arch"
  swift build -c "$CONFIG" --arch "$arch" --scratch-path "$SCRATCH-$arch"
  candidate="$SCRATCH-$arch/$CONFIG/LumiTypeMac"
  if [[ ! -x "$candidate" ]]; then
    echo "构建产物不存在：$candidate" >&2
    exit 1
  fi
  BINS+=("$candidate")
done
mkdir -p "$DIST"
BIN="$DIST/.LumiType-$CONFIG"
if [[ ${#BINS[@]} -gt 1 ]]; then
  lipo -create "${BINS[@]}" -output "$BIN"
else
  cp "${BINS[0]}" "$BIN"
fi
chmod +x "$BIN"
lipo -info "$BIN"

echo "==> 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
rm -f "$BIN"        # 中间产物（lipo 结果）不留在 dist 里

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.lumitype.mac</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>LumiType 灵译</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "==> 生成图标"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$APP/Contents/MacOS/$APP_NAME" --make-icon "$DIST/AppIcon-1024.png" 1024 >/dev/null
for size in 16 32 64 128 256 512; do
  sips -z $size $size "$DIST/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$DIST/AppIcon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> 签名（ad-hoc）"
# Developer ID 可用时优先用它，否则 ad-hoc —— 两者都能本机运行，
# 区别只在 Gatekeeper 对下载文件的处理。
IDENTITY="${LUMITYPE_SIGN_IDENTITY:--}"
codesign --force --deep --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "签名校验通过"

echo "==> 生成分发包"
ditto -c -k --keepParent "$APP" "$DIST/LumiType-$VERSION-macOS.zip"

# DMG：拖拽安装的常规形态。没有 Developer ID 时 hdiutil 仍可生成，
# 只是首次打开需要「右键 → 打开」绕过 Gatekeeper。
DMG="$DIST/LumiType-$VERSION-macOS.dmg"
# 暂存目录必须放在 /tmp：把 .dmg 的源目录放在 OneDrive 同步盘里，
# hdiutil 会报 "create failed - 无此文件或目录"（实测）。
STAGE="$(mktemp -d /tmp/lumitype-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "LumiType $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "完成："
echo "  $APP"
echo "  $DIST/LumiType-$VERSION-macOS.zip"
echo "  $DMG"
echo "运行： open \"$APP\""
echo "安装： open \"$DMG\" 然后把 LumiType 拖进「应用程序」"
