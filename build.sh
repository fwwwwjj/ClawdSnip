#!/bin/zsh
# 编译并打包 ClawdSnip.app，安装到 ~/Applications（单核、低优先级，避免发热）
# 桌面文件夹走 iCloud 同步，会给文件加 Finder 属性导致签名失败，所以在临时目录里打包签名。
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(mktemp -d)"
APP="$STAGE/ClawdSnip.app"
BIN="$APP/Contents/MacOS/ClawdSnip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

nice -n 10 swiftc -O -swift-version 5 -j1 -framework Cocoa -o "$BIN" main.swift

# 像素 Clawd 应用图标
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  "$BIN" --render-icon "$ICONSET/icon_${s}x${s}.png" "$s"
  "$BIN" --render-icon "$ICONSET/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
# 有固定签名（setup-signing.sh 生成）就用它，重新编译后系统授权不失效；没有就退回临时签名
SIGN_DIR="$HOME/Library/Application Support/ClawdSnip"
KC="$SIGN_DIR/signing.keychain-db"
if [[ -f "$KC" ]]; then
  security unlock-keychain -p "$(cat "$SIGN_DIR/signing.pass")" "$KC"
  codesign --force --keychain "$KC" --sign "ClawdSnip Local Signing" "$APP"
else
  echo "warning: 没有固定签名，用临时签名（重新编译后需要重新授权）。先运行 ./setup-signing.sh"
  codesign --force --sign - "$APP"
fi
codesign --verify "$APP"

DEST="$HOME/Applications/ClawdSnip.app"
pkill -x ClawdSnip 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
rm -rf "$STAGE"
echo "installed: $DEST"
