#!/bin/bash
# Steam Shelf 빌드 스크립트 — ~/Applications/Steam Shelf.app 를 만든다.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Steam Shelf"
DEST="${1:-$HOME/Applications}"
APP="$DEST/$APP_NAME.app"
BUILD=".build"

echo "▸ 정리"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 컴파일"
swiftc -O -parse-as-library \
    -target arm64-apple-macos14.0 \
    -framework AppKit -framework SwiftUI \
    -o "$BUILD/SteamShelf" \
    Sources/*.swift

echo "▸ 아이콘"
swift make_icon.swift "$BUILD/AppIcon.icns" >/dev/null

echo "▸ 번들 구성"
cp "$BUILD/SteamShelf" "$APP/Contents/MacOS/SteamShelf"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SteamShelf</string>
    <key>CFBundleIdentifier</key><string>com.steamshelf.launcher</string>
    <key>CFBundleName</key><string>Steam Shelf</string>
    <key>CFBundleDisplayName</key><string>Steam Shelf</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Steam Shelf</string>
</dict>
</plist>
PLIST

echo "▸ 서명 (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (서명 생략)"

echo "✅ 완료: $APP"
