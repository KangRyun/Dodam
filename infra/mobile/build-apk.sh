#!/usr/bin/env bash
# 도담 Android 릴리스 APK 빌드 — **원스토어(ONE Store) 용** (S15P11B209-765)
#
# 실제 로직은 build-android.sh 에 있다. AAB 와 컨테이너 수명·시크릿 주입·버전 산출·
# 서명 검증이 **같은 코드**를 탄다. 다른 것은 형식 하나뿐이다.
#
# ★ 원스토어는 왜 APK 인가
#   Play 는 AAB 를 받아 Play App Signing 이 기기별 APK 를 만들고 **구글이 재서명**한다.
#   원스토어에는 그 위탁 구조가 없다 — 올린 APK 가 그대로 배포되고, **내가 서명한 키가
#   곧 앱의 신원**이 된다. 그래서 업로드 키/앱 서명 키를 나눌 이유도 없고, 산출물이
#   그 자체로 설치 파일이라 `adb install` 로 바로 검증할 수 있다.
#
# ⚠️ keystore 를 잃으면 이 앱은 **이후 업데이트를 영원히 올릴 수 없다.**
#   구글처럼 대신 보관해 주는 곳이 없다. upload-keystore.jks 와 비밀번호를
#   팀 비밀 저장소 + 오프라인 매체에 이중으로 보관할 것.
#
# 사용:
#   KEYSTORE_FILE=~/dodam-secrets/upload-keystore.jks \
#   KEY_PROPERTIES_FILE=~/dodam-secrets/key.properties \
#   OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
#   infra/mobile/build-apk.sh
#
# 산출물: ./build-artifacts/app-release.apk (+ apksigner 서명 검증 로그)

set -euo pipefail
exec env BUILD_FORMAT=apk \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-android.sh" "$@"
