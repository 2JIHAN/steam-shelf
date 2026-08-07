#!/bin/bash
# 릴리스 아티팩트 생성 — dist/SteamShelf-<version>-universal.zip
#
#   ./release.sh            # build.sh의 기본 버전으로 패키징
#   VERSION=1.2.0 ./release.sh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
STAGE="$(mktemp -d)"
DIST="dist"
ZIP="$DIST/SteamShelf-$VERSION-universal.zip"

echo "▸ 유니버설 빌드 ($VERSION)"
VERSION="$VERSION" ./build.sh "$STAGE" >/dev/null

APP="$STAGE/Steam Shelf.app"
echo "▸ 검증"
lipo -archs "$APP/Contents/MacOS/SteamShelf"
codesign --verify --deep --strict "$APP" && echo "  서명 확인"
ls "$APP/Contents/Resources" | grep -c lproj | xargs -I{} echo "  로케일 {}개"

echo "▸ 압축"
rm -rf "$DIST"
mkdir -p "$DIST"
# ditto는 번들의 확장 속성과 심볼릭 링크를 보존한다. zip 명령보다 안전하다.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -rf "$STAGE"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA  $(basename "$ZIP")" > "$DIST/SHA256SUMS.txt"

echo "✅ $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "   sha256: $SHA"
