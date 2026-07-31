#!/usr/bin/env bash
# 도담 Android 릴리스 AAB 빌드 — **Play 용** (S15P11B209-623)
#
# 실제 로직은 build-android.sh 에 있다(651 에서 APK 와 공용화). 이 파일은 형식만 정하는
# 진입점이다. Jenkins 의 BUILD_ANDROID_AAB 스테이지와 기존 문서가 이 경로를 부르므로
# **이름과 사용법은 그대로 유지한다** — 바뀐 것은 내부 구현 위치뿐이다.
#
# 사용:
#   KEYSTORE_FILE=~/dodam-secrets/upload-keystore.jks \
#   KEY_PROPERTIES_FILE=~/dodam-secrets/key.properties \
#   OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
#   infra/mobile/build-aab.sh
#
# 산출물: ./build-artifacts/app-release.aab (+ 서명 검증 로그)

set -euo pipefail
exec env BUILD_FORMAT=appbundle \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-android.sh" "$@"
