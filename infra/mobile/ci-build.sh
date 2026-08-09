#!/usr/bin/env bash
# 컨테이너 **안에서** 도는 실제 빌드 절차 (S15P11B209-623)
# 호출: infra/mobile/build-aab.sh 가 docker cp 로 /src/ci-build.sh 에 넣고 실행한다.

set -euo pipefail
cd /src

REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-true}"

# 산출 형식 (S15P11B209-765 원스토어). 기본값이 appbundle 인 것은 **의도적이다** —
# 이 값을 넘기지 않는 기존 호출부(build-aab.sh · Jenkins BUILD_ANDROID_AAB)는
# 아무것도 바꾸지 않아도 종전과 똑같이 동작해야 한다.
#   appbundle → Play (Play App Signing 이 재서명하므로 업로드 키만 있으면 된다)
#   apk       → 원스토어 (재서명 위탁이 없어 **내가 서명한 키가 곧 앱 신원**이다)
BUILD_FORMAT="${BUILD_FORMAT:-appbundle}"

log() { printf '\n\033[1m── %s\033[0m\n' "$*"; }

# ── 0. 호스트에서 딸려온 찌꺼기 제거 ───────────────────────────────────────
# docker cp 는 .gitignore 를 모른다 — 작업 트리를 통째로 가져온다.
# 특히 android/local.properties 에는 **호스트의** flutter.sdk 경로(/home/kr/flutter)가 박혀 있어
# 컨테이너 안에서는 존재하지 않는 경로를 가리킨다. 지우면 flutter 가 자기 경로로 다시 만든다.
# build/·.dart_tool 도 호스트 산출물이라 남겨두면 "왜 옛 코드가 들어갔지"를 만든다.
log "호스트 잔재 정리"
rm -f  android/local.properties
rm -rf build .dart_tool android/.gradle android/app/build

# ── 1. 서명 설정 확인 ──────────────────────────────────────────────────────
if [ -f android/key.properties ]; then
  log "릴리스 서명 설정 감지 (android/key.properties)"
  # 값은 절대 출력하지 않는다 — 비밀번호가 들어 있다. 키 이름만 본다.
  echo "   포함 키: $(grep -oE '^[a-zA-Z]+' android/key.properties | tr '\n' ' ')"
elif [ "$REQUIRE_RELEASE_SIGNING" = "true" ]; then
  echo "❌ key.properties 가 없는데 REQUIRE_RELEASE_SIGNING=true 다." >&2
  echo "   debug 키로 서명된 AAB 는 Play 에 올릴 수 없다 — 조용히 통과시키지 않는다." >&2
  exit 1
else
  log "⚠️ key.properties 없음 — debug 서명으로 진행(검증 전용)"
fi

# ── 2. 의존성 ──────────────────────────────────────────────────────────────
log "flutter pub get"
flutter pub get

# ── 3. 빌드 ────────────────────────────────────────────────────────────────
BUILD_ARGS=(--release)
[ -n "${BUILD_NAME:-}" ]   && BUILD_ARGS+=(--build-name "$BUILD_NAME")
[ -n "${BUILD_NUMBER:-}" ] && BUILD_ARGS+=(--build-number "$BUILD_NUMBER")

case "$BUILD_FORMAT" in
  appbundle) ;;
  apk)       ;;
  *) echo "❌ BUILD_FORMAT 은 appbundle 또는 apk 다: '$BUILD_FORMAT'" >&2; exit 1 ;;
esac

# ── 3-b. 앱 설정 주입 (S15P11B209-765) ─────────────────────────────────────
# ★ Flutter 의 String.fromEnvironment 는 **컴파일 타임 dart-define** 만 읽는다.
#   컨테이너 환경변수(build-android.sh 의 --env-file / -e)는 Dart 코드에 닿지 않는다.
#   여기서 옮겨 싣지 않으면 앱 안에서는 전부 빈 문자열이 된다.
#
#   "build.gradle.kts 가 oauth 5개를 검사하니 괜찮다"가 **성립하지 않는 이유**:
#   그 가드가 채우는 건 네이티브 manifestPlaceholders(kakaoScheme 등)이고,
#   Dart 의 fromEnvironment 와는 완전히 다른 경로다. 두 경로를 같은 것으로 착각하면
#   "gradle 검사 통과 → 그런데 앱은 빈 값" 이 그대로 만들어진다.
#
# ⚠️ 2026-08-04: 이 주입이 없어 원스토어 등록용 APK 가 실행 즉시 종료됐다.
#   api_environment.dart:24 가 빈 값에 StateError 를 던지고, 그 호출(main.dart:79)이
#   runApp 앞이라 첫 화면도 못 그린다.
[ -n "${API_BASE_URL:-}" ] || {
  echo "❌ API_BASE_URL 이 비었다 — 이 값 없이 만든 앱은 실행 즉시 종료된다." >&2
  echo "   api_environment.dart 가 빈 값에 StateError 를 던지고 그 호출은 runApp 앞에 있다." >&2
  exit 1
}

DART_DEFINES=(--dart-define "API_BASE_URL=${API_BASE_URL}")
DART_DEFINE_KEYS=(API_BASE_URL)

# 나머지는 있을 때만 싣는다.
#   KAKAO_NATIVE_APP_KEY·GOOGLE_SERVER_CLIENT_ID → Dart 쪽 소셜 로그인이 읽는다
#     (없으면 build.gradle.kts 의 preReleaseBuild 가드가 먼저 끊는다)
#   COMMUNITY_WEB_URL·LEGAL_WEB_URL → Dart 에 defaultValue 가 있어 선택이다.
#     넘기지 않으면 종전과 똑같이 기본값(운영 주소)으로 동작한다.
for _k in KAKAO_NATIVE_APP_KEY GOOGLE_SERVER_CLIENT_ID COMMUNITY_WEB_URL LEGAL_WEB_URL; do
  _v="${!_k:-}"
  if [ -n "$_v" ]; then
    DART_DEFINES+=(--dart-define "${_k}=${_v}")
    DART_DEFINE_KEYS+=("$_k")
  fi
done

# ⚠️ 값은 절대 로그에 남기지 않는다(가드레일 9절) — KAKAO 키·GOOGLE client id 가 섞여 있다.
#   그래서 BUILD_ARGS 와 합치지 않고 따로 둔다. 합치면 아래 log 줄이 전부 뱉는다.
log "flutter build $BUILD_FORMAT ${BUILD_ARGS[*]} (+dart-define: ${DART_DEFINE_KEYS[*]})"
# gradle 쪽 가드에도 같은 뜻을 전달한다 — 스크립트가 아니라 빌드가 직접 판정하게 한다.
export DODAM_REQUIRE_RELEASE_SIGNING="$REQUIRE_RELEASE_SIGNING"
flutter build "$BUILD_FORMAT" "${BUILD_ARGS[@]}" "${DART_DEFINES[@]}"

# 산출 경로는 형식마다 다르다. APK 는 gradle 이 build/app/outputs/apk/release/ 에 쓰고
# flutter 가 build/app/outputs/flutter-apk/ 로 복사한다 — 둘 다 볼 수 있어야 한다.
# (flutter 버전에 따라 어느 쪽만 남기도 해서, 있는 쪽을 집는다)
if [ "$BUILD_FORMAT" = "appbundle" ]; then
  ARTIFACT=build/app/outputs/bundle/release/app-release.aab
else
  ARTIFACT=""
  for c in build/app/outputs/flutter-apk/app-release.apk \
           build/app/outputs/apk/release/app-release.apk; do
    [ -f "$c" ] && { ARTIFACT="$c"; break; }
  done
  [ -n "$ARTIFACT" ] || { echo "❌ APK 를 찾지 못했다 (flutter-apk/·apk/release/ 둘 다 없음)" >&2; exit 1; }
fi
[ -f "$ARTIFACT" ] || { echo "❌ 산출물이 생성되지 않았다: $ARTIFACT" >&2; exit 1; }

# ── 4. ★ 서명 실검증 ───────────────────────────────────────────────────────
# "빌드가 성공했다"와 "제대로 서명됐다"는 다르다. 산출물이 나왔어도 debug 키로 서명돼 있으면
# 스토어 업로드에서 거절당한다 — 그걸 여기서 잡지 못하면 배포 직전에 안다.
#
# ★ 형식마다 검증 도구가 다르다 (2026-07-31)
#   AAB : keytool -printcert -jarfile — AAB 는 JAR 서명(v1)만 쓰므로 이걸로 읽힌다.
#   APK : **apksigner** 를 쓴다. 최신 APK 는 v2/v3(APK Signature Scheme)로만 서명될 수 있고,
#         그 경우 v1 서명 블록이 없어 keytool 은 "서명되지 않았다"고 **잘못** 말한다.
#         릴리스 키로 제대로 서명된 APK 를 실패로 판정하는 것이라 반드시 갈라 써야 한다.
log "서명 검증 ($BUILD_FORMAT)"

if [ "$BUILD_FORMAT" = "appbundle" ]; then
  keytool -printcert -jarfile "$ARTIFACT" > /tmp/signing-report.txt 2>&1 \
    || { echo "❌ AAB 에서 인증서를 읽지 못했다 = 서명되지 않았다" >&2; cat /tmp/signing-report.txt >&2; exit 1; }
  OWNER="$(grep -m1 '^소유자:\|^Owner:' /tmp/signing-report.txt || true)"
else
  # apksigner 는 build-tools 안에 있고 **PATH 에 없다**(Dockerfile 은 cmdline-tools·platform-tools 만
  # PATH 에 넣는다). 버전을 박아 두면 BUILD_TOOLS_VERSION 을 올리는 순간 조용히 깨지므로
  # 설치된 것 중 가장 높은 버전을 고른다.
  APKSIGNER="$(command -v apksigner 2>/dev/null || true)"
  [ -n "$APKSIGNER" ] || APKSIGNER="$(ls -1 "${ANDROID_HOME:-/opt/android-sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
  [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ] \
    || { echo "❌ apksigner 를 찾지 못했다 — 이미지에 build-tools 가 설치돼 있는지 확인할 것" >&2; exit 1; }

  # verify 는 서명이 없거나 깨졌으면 0 이 아닌 코드로 끝난다 = 검증이 곧 판정이다.
  # -v 를 붙이면 어떤 스킴(v1/v2/v3)으로 서명됐는지도 리포트에 남아 나중에 되짚기 좋다.
  "$APKSIGNER" verify --print-certs -v "$ARTIFACT" > /tmp/signing-report.txt 2>&1 \
    || { echo "❌ APK 서명 검증 실패 = 서명되지 않았거나 깨졌다" >&2; cat /tmp/signing-report.txt >&2; exit 1; }
  OWNER="$(grep -m1 'Signer #1 certificate DN' /tmp/signing-report.txt || true)"
fi

echo "   $OWNER"

if [ "$REQUIRE_RELEASE_SIGNING" = "true" ]; then
  # debug keystore 의 인증서 주체는 항상 CN=Android Debug 다. 이게 보이면 릴리스 서명이 아니다.
  if grep -qi 'CN=Android Debug' /tmp/signing-report.txt; then
    echo "❌ debug 키로 서명됐다 — key.properties 가 실제로 적용되지 않았다." >&2
    echo "   android/app/build.gradle.kts 의 release signingConfig 배선을 확인할 것." >&2
    exit 1
  fi
  echo "   ✅ 릴리스 키로 서명됨 (debug 키 아님)"
fi

# ── 5. 산출물을 고정 위치로 모은다 ─────────────────────────────────────────
# 호스트 스크립트가 flutter 의 내부 디렉터리 구조를 알 필요가 없게 한다.
# flutter 가 산출 경로를 바꾸면(실제로 버전마다 바뀐다) 여기 한 곳만 고치면 된다.
mkdir -p /src/build-out
cp "$ARTIFACT" "/src/build-out/$(basename "$ARTIFACT")"

log "완료: $ARTIFACT ($(du -h "$ARTIFACT" | cut -f1))"
