#!/bin/bash
# Steam Shelf 빌드 스크립트 — 기본값으로 ~/Applications/Steam Shelf.app 를 만든다.
#
#   ./build.sh                  # 유니버설(arm64 + x86_64) 빌드 → ~/Applications
#   ./build.sh /Applications    # 설치 위치 지정
#   ARCHS=arm64 ./build.sh      # 아키텍처 지정 (빠른 반복 개발용)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Steam Shelf"
VERSION="${VERSION:-1.0.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
DEST="${1:-$HOME/Applications}"
APP="$DEST/$APP_NAME.app"
BUILD=".build"

echo "▸ 정리"
rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SLICES=()
for arch in $ARCHS; do
    echo "▸ 컴파일 ($arch)"
    swiftc -O -parse-as-library \
        -target "${arch}-apple-macos14.0" \
        -framework AppKit -framework SwiftUI \
        -o "$BUILD/SteamShelf-$arch" \
        Sources/*.swift
    SLICES+=("$BUILD/SteamShelf-$arch")
done

if [ "${#SLICES[@]}" -gt 1 ]; then
    echo "▸ 유니버설 바이너리 결합"
    lipo -create "${SLICES[@]}" -output "$BUILD/SteamShelf"
else
    cp "${SLICES[0]}" "$BUILD/SteamShelf"
fi

echo "▸ 아이콘"
swift make_icon.swift "$BUILD/AppIcon.icns" >/dev/null

echo "▸ 번들 구성"
cp "$BUILD/SteamShelf" "$APP/Contents/MacOS/SteamShelf"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
        <string>ja</string>
        <string>zh-Hans</string>
    </array>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Steam Shelf</string>
</dict>
</plist>
PLIST

echo "▸ 서명 (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (서명 생략)"

echo "✅ 완료: $APP  ($VERSION, $(lipo -archs "$APP/Contents/MacOS/SteamShelf"))"
