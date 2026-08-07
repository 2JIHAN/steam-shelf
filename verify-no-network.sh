#!/bin/bash
# Steam Shelf가 밖으로 아무것도 보내지 않는지 검사한다.
#
#   ./verify-no-network.sh                       # 소스 + 빌드된 앱 정적 검사
#   ./verify-no-network.sh --runtime             # 실행시켜 커넥션까지 확인
#   ./verify-no-network.sh --runtime "/path/to/Steam Shelf.app"
#
# 실패하면 종료 코드 1.
set -uo pipefail

cd "$(dirname "$0")"

RUNTIME=0
APP="$HOME/Applications/Steam Shelf.app"
for arg in "$@"; do
    case "$arg" in
        --runtime) RUNTIME=1 ;;
        *) APP="$arg" ;;
    esac
done

FAILED=0
fail() { echo "  ❌ $1"; FAILED=1; }
pass() { echo "  ✅ $1"; }

# 앱이 여는 URL 중 허용된 것. 이 목록에 없는 원격 주소가 나오면 실패한다.
#
# store.steampowered.com — 우클릭 메뉴의 "상점 페이지 열기". 앱이 접속하는 게
# 아니라 NSWorkspace로 URL을 기본 브라우저에 넘긴다. 사용자가 그 메뉴를 눌렀을
# 때만 실행되고, 앱 프로세스는 어떤 소켓도 열지 않는다.
ALLOWED_HOSTS="store.steampowered.com"

# 앱이 여는 URL 스킴 중 원격이 아닌 것.
LOCAL_SCHEMES="steam://"

echo "▸ 1. 소스 코드"

# 네트워킹 API를 직접 쓰는지
NET_API=$(grep -rnE "URLSession|NWConnection|CFStream|CFSocket|NSURLConnection|getaddrinfo|socket\(|Network\.framework" Sources/ 2>/dev/null)
if [ -n "$NET_API" ]; then
    fail "네트워킹 API 사용:"; echo "$NET_API" | sed 's/^/     /'
else
    pass "네트워킹 API 없음 (URLSession, NWConnection, 소켓 등)"
fi

# 원격 URL 리터럴
SRC_URLS=$(grep -rhoE "https?://[a-zA-Z0-9._-]+" Sources/ 2>/dev/null | sort -u)
UNEXPECTED=""
for url in $SRC_URLS; do
    host="${url#*://}"
    echo "$ALLOWED_HOSTS" | tr ' ' '\n' | grep -qx "$host" || UNEXPECTED="$UNEXPECTED $url"
done
if [ -n "$UNEXPECTED" ]; then
    fail "허용 목록에 없는 원격 주소:$UNEXPECTED"
else
    pass "원격 주소는 허용 목록뿐 [${SRC_URLS:-없음}]"
fi

if [ ! -d "$APP" ]; then
    echo
    echo "▸ 앱을 찾을 수 없어 바이너리 검사를 건너뜁니다: $APP"
    exit $FAILED
fi

BIN="$APP/Contents/MacOS/SteamShelf"

echo
echo "▸ 2. 빌드된 바이너리"

# 네트워킹 프레임워크를 링크했는지. 소스 grep은 우회할 수 있지만 이건 어렵다 —
# 원격 접속을 하는 코드는 어떤 경로로 짜든 결국 CFNetwork를 끌고 온다.
LINKED=$(otool -L "$BIN" 2>/dev/null | grep -iE "CFNetwork|/Network\.framework|libnetwork")
if [ -n "$LINKED" ]; then
    fail "네트워킹 프레임워크 링크됨:"; echo "$LINKED" | sed 's/^/     /'
else
    pass "CFNetwork·Network.framework 링크 없음"
fi

# 참조하는 네트워킹 심볼
SYMS=$(nm -u "$BIN" 2>/dev/null | grep -iE "urlsession|nwconnection|cfsocket|cfstream|getaddrinfo|nsurlconnection")
if [ -n "$SYMS" ]; then
    fail "네트워킹 심볼 참조:"; echo "$SYMS" | sed 's/^/     /'
else
    pass "네트워킹 심볼 참조 없음"
fi

# 바이너리에 박힌 원격 주소
BIN_URLS=$(strings -a "$BIN" 2>/dev/null | grep -oE "https?://[a-zA-Z0-9._-]+" | sort -u)
UNEXPECTED=""
for url in $BIN_URLS; do
    host="${url#*://}"
    echo "$ALLOWED_HOSTS" | tr ' ' '\n' | grep -qx "$host" || UNEXPECTED="$UNEXPECTED $url"
done
if [ -n "$UNEXPECTED" ]; then
    fail "바이너리에 허용되지 않은 주소:$UNEXPECTED"
else
    pass "바이너리의 원격 주소는 허용 목록뿐 [${BIN_URLS:-없음}]"
fi

if [ "$RUNTIME" -eq 0 ]; then
    echo
    [ $FAILED -eq 0 ] && echo "✅ 정적 검사 통과 (--runtime 을 주면 실행 중 커넥션까지 확인)" \
                      || echo "❌ 실패"
    exit $FAILED
fi

echo
echo "▸ 3. 실행 중 커넥션"

pkill -x SteamShelf 2>/dev/null
sleep 1
open -a "$APP"
sleep 3
PID=$(pgrep -x SteamShelf | head -1)
if [ -z "$PID" ]; then
    fail "앱이 실행되지 않아 확인할 수 없음"
    exit 1
fi

echo "  pid $PID 를 20초간 관찰합니다"
FOUND=""
for _ in $(seq 1 40); do
    HIT=$(lsof -nP -i -a -p "$PID" 2>/dev/null | tail -n +2)
    [ -n "$HIT" ] && FOUND="$FOUND$HIT"$'\n'
    sleep 0.5
done

BYTES=$(nettop -P -L 1 -p "$PID" 2>/dev/null | tail -n +2 | head -3)
pkill -x SteamShelf 2>/dev/null

if [ -n "$FOUND" ]; then
    fail "소켓이 열렸습니다:"; echo "$FOUND" | sed 's/^/     /'
else
    pass "20초 동안 열린 소켓 0개"
fi
[ -n "$BYTES" ] && echo "  nettop: $BYTES"

echo
[ $FAILED -eq 0 ] && echo "✅ 전체 통과 — 앱은 네트워크로 아무것도 보내지 않습니다" || echo "❌ 실패"
exit $FAILED
