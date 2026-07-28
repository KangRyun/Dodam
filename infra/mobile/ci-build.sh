#!/usr/bin/env bash
# 컨테이너 **안에서** 도는 실제 빌드 절차 (S15P11B209-623)
# 호출: infra/mobile/build-aab.sh 가 docker cp 로 /src/ci-build.sh 에 넣고 실행한다.

set -euo pipefail
cd /src

REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-true}"

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

# ── 3. AAB 빌드 ────────────────────────────────────────────────────────────
BUILD_ARGS=(--release)
[ -n "${BUILD_NAME:-}" ]   && BUILD_ARGS+=(--build-name "$BUILD_NAME")
[ -n "${BUILD_NUMBER:-}" ] && BUILD_ARGS+=(--build-number "$BUILD_NUMBER")

log "flutter build appbundle ${BUILD_ARGS[*]}"
# gradle 쪽 가드에도 같은 뜻을 전달한다 — 스크립트가 아니라 빌드가 직접 판정하게 한다.
export DODAM_REQUIRE_RELEASE_SIGNING="$REQUIRE_RELEASE_SIGNING"
flutter build appbundle "${BUILD_ARGS[@]}"

AAB=build/app/outputs/bundle/release/app-release.aab
[ -f "$AAB" ] || { echo "❌ AAB 가 생성되지 않았다: $AAB" >&2; exit 1; }

# ── 4. ★ 서명 실검증 ───────────────────────────────────────────────────────
# "빌드가 성공했다"와 "제대로 서명됐다"는 다르다. AAB 가 나왔어도 debug 키로 서명돼 있으면
# Play 업로드에서 거절당한다 — 그걸 여기서 잡지 못하면 배포 직전에 안다.
log "서명 검증"
keytool -printcert -jarfile "$AAB" > /tmp/signing-report.txt 2>&1 \
  || { echo "❌ AAB 에서 인증서를 읽지 못했다 = 서명되지 않았다" >&2; cat /tmp/signing-report.txt >&2; exit 1; }

OWNER="$(grep -m1 '^소유자:\|^Owner:' /tmp/signing-report.txt || true)"
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

log "완료: $AAB ($(du -h "$AAB" | cut -f1))"
