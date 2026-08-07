#!/bin/bash
# 릴리스 아티팩트 생성 — dist/SteamShelf-<version>-universal.zip
#
#   ./release.sh                          # 서명·공증 없이 ad-hoc 빌드만
#   NOTARY_PROFILE=steamshelf ./release.sh # Developer ID 서명 + 공증 + 스테이플
#
# 환경 변수
#   VERSION          기본 1.1.0
#   SIGN_IDENTITY    비우면 키체인의 "Developer ID Application"을 자동으로 찾는다
#   NOTARY_PROFILE   xcrun notarytool store-credentials 로 저장한 프로필 이름
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-1.1.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
STAGE="$(mktemp -d)"
DIST="dist"
ZIP="$DIST/SteamShelf-$VERSION-universal.zip"

# 키체인에서 Developer ID Application 인증서를 자동으로 찾는다.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)".*/\1/') || true
fi

echo "▸ 유니버설 빌드 ($VERSION)"
VERSION="$VERSION" ./build.sh "$STAGE" >/dev/null
APP="$STAGE/Steam Shelf.app"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "▸ Developer ID 서명"
    echo "   $SIGN_IDENTITY"
    # hardened runtime + 타임스탬프는 공증의 전제 조건이다.
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ 서명 건너뜀 — Developer ID Application 인증서를 찾지 못했습니다."
    echo "   ad-hoc 서명 상태로 진행합니다. 받는 사람은 Gatekeeper에 막힙니다."
fi

echo "▸ 검증"
lipo -archs "$APP/Contents/MacOS/SteamShelf"
codesign --verify --deep --strict "$APP" && echo "  서명 확인"
ls "$APP/Contents/Resources" | grep -c lproj | xargs -I{} echo "  로케일 {}개"

echo "▸ 압축"
rm -rf "$DIST"
mkdir -p "$DIST"
# ditto는 번들의 확장 속성과 심볼릭 링크를 보존한다. zip 명령보다 안전하다.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [ -n "$NOTARY_PROFILE" ]; then
    echo "▸ 공증 제출 (수 분 걸립니다)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "▸ 스테이플"
    # 티켓은 .app에 박고, 그 상태로 다시 압축해야 배포본에 반영된다.
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

    echo "▸ Gatekeeper 최종 판정"
    spctl -a -vvv -t exec "$APP"
fi

rm -rf "$STAGE"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA  $(basename "$ZIP")" > "$DIST/SHA256SUMS.txt"

echo "✅ $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "   sha256: $SHA"
