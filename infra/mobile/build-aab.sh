#!/usr/bin/env bash
# 도담 Android 릴리스 AAB 빌드 (S15P11B209-623)
#
# 호스트에서도 Jenkins 안에서도 **똑같이** 동작한다. 그게 이 스크립트의 존재 이유다.
#
# ⚠️ bind mount 를 쓰지 않는 이유(이 파일에서 제일 중요한 설계 결정)
#   Jenkins 는 컨테이너 안에서 호스트 도커 소켓을 부른다(Docker-out-of-Docker).
#   `-v "$PWD:/src"` 를 쓰면 경로 해석은 Jenkins 컨테이너 안에서, 실제 마운트는 호스트가 한다.
#   jenkins_home 은 named volume 이라 /var/jenkins_home/workspace/... 는 호스트에 없고,
#   도커는 없는 경로에 **빈 디렉터리를 만들어 붙인다.** 그러면 소스가 사라진 채 빌드된다.
#   (실제 사고 2회: 2026-07-22 nginx 빈 conf, 2026-07-26 minio-init exit 127)
#   → 소스·키는 `docker cp` 로 넣고 산출물도 `docker cp` 로 꺼낸다. 둘 다 클라이언트 측
#     스트리밍이라 호스트 경로 해석이 끼어들지 않는다. named volume(캐시)은 데몬이 관리하므로 안전하다.
#
# 사용:
#   KEYSTORE_FILE=~/dodam-secrets/upload-keystore.jks \
#   KEY_PROPERTIES_FILE=~/dodam-secrets/key.properties \
#   OAUTH_ENV_FILE=~/dodam-secrets/oauth.env \
#   infra/mobile/build-aab.sh
#
# 산출물: ./build-artifacts/app-release.aab (+ 서명 검증 로그)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${BUILDER_IMAGE:-dodam-flutter-builder:3.44.7}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/build-artifacts}"
GRADLE_CACHE_VOLUME="${GRADLE_CACHE_VOLUME:-dodam-android-gradle}"
PUB_CACHE_VOLUME="${PUB_CACHE_VOLUME:-dodam-android-pub}"

# 릴리스 서명 자재. 없으면 debug 키로 서명된 AAB 가 나오는데 그건 Play 에 올릴 수 없다.
#   → CI 에서는 REQUIRE_RELEASE_SIGNING=true 로 두어 조용한 debug 서명을 금지한다.
KEYSTORE_FILE="${KEYSTORE_FILE:-}"
KEY_PROPERTIES_FILE="${KEY_PROPERTIES_FILE:-}"
OAUTH_ENV_FILE="${OAUTH_ENV_FILE:-}"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-true}"

# 버전·빌드번호 (S15P11B209-629)
#   지정하지 않으면 app-version.sh 가 산출한다 — pubspec 의 version(이름) + 커밋 수(번호).
#   호출부(Jenkins·호스트)가 각자 다른 값을 넘겨 versionCode 가 어긋나는 걸 막으려고
#   산출을 한 곳에 모았다. 이유·사고 이력은 app-version.sh 헤더 참조.
#   명시적으로 넘긴 값은 그대로 존중한다(핫픽스로 번호를 손으로 올려야 할 때가 있다).
BUILD_NAME="${BUILD_NAME:-$("$REPO_ROOT/infra/mobile/app-version.sh" --build-name)}"
BUILD_NUMBER="${BUILD_NUMBER:-$("$REPO_ROOT/infra/mobile/app-version.sh" --build-number)}"

log() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }

# ── 사전 점검 ──────────────────────────────────────────────────────────────
# ★ 메모리 관문 (S15P11B209-356). 2026-07-28 에 이 빌드가 돌던 중 호스트가 응답 불능이 됐다.
#   Gradle 데몬 + Kotlin 컴파일 데몬 + dart 스냅샷이 겹치면 수 GB 를 쓰는데, 당시엔
#   이 컨테이너에 상한이 없었고 Jenkins 도 같이 떠 있었다. 눈으로 판단하지 말고 관문을 통과시킨다.
#   SKIP_PREFLIGHT=1 로 건너뛸 수 있게 둔 이유: 관문 자체가 고장 났을 때 빌드까지 막히면 안 된다.
if [ "${SKIP_PREFLIGHT:-0}" != "1" ] && [ -x "$REPO_ROOT/infra/scripts/preflight-memory.sh" ]; then
  # --in-ci 이유는 infra/mobile/ci-test.sh 의 같은 자리 주석 참조(S15P11B209-642).
  "$REPO_ROOT/infra/scripts/preflight-memory.sh" --need 7168 --in-ci \
    || die "메모리 사전 점검 실패 — 위 이유를 해소하고 다시 실행할 것.
   (관문을 무시하려면 SKIP_PREFLIGHT=1, 단 07-28 사고와 같은 경로다)"
fi

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || die "빌더 이미지가 없다: $IMAGE
   → docker build -t $IMAGE infra/mobile
   ⚠️ 이 이미지는 태그가 붙어 있어도 '사용 안 하는 이미지'다 —
      docker image prune -af / docker system prune -a 를 돌리면 지워진다(07-28 실제 소실).
      재빌드에 10~20분이 드니, 정리 명령을 쓸 때는 -a 를 빼거나 이 이미지를 확인할 것."

if [ "$REQUIRE_RELEASE_SIGNING" = "true" ]; then
  [ -n "$KEYSTORE_FILE" ] && [ -f "$KEYSTORE_FILE" ] \
    || die "KEYSTORE_FILE 이 없다: '${KEYSTORE_FILE:-(미지정)}'
   릴리스 서명 없이 만든 AAB 는 Play 에 올릴 수 없다. 검증 목적이라면
   REQUIRE_RELEASE_SIGNING=false 로 명시적으로 낮춰서 실행할 것."
  [ -n "$KEY_PROPERTIES_FILE" ] && [ -f "$KEY_PROPERTIES_FILE" ] \
    || die "KEY_PROPERTIES_FILE 이 없다: '${KEY_PROPERTIES_FILE:-(미지정)}'"
fi

# oauth 5개 키는 build.gradle.kts 의 preReleaseBuild 가드가 검사한다.
# 여기서 미리 못 채우면 gradle 이 한참 돌다 죽으므로 앞에서 잘라낸다.
if [ -z "$OAUTH_ENV_FILE" ] || [ ! -f "$OAUTH_ENV_FILE" ]; then
  die "OAUTH_ENV_FILE 이 없다: '${OAUTH_ENV_FILE:-(미지정)}'
   KAKAO_NATIVE_APP_KEY·GOOGLE_SERVER_CLIENT_ID·NAVER_CLIENT_ID·NAVER_CLIENT_SECRET·NAVER_APP_NAME
   5개를 KEY=VALUE 형식으로 담은 파일이 필요하다(android/oauth.properties 와 같은 값).
   Jenkins 에서는 Credentials(secret file)로 주입한다."
fi

CID=""
cleanup() {
  # 컨테이너에는 keystore 와 비밀번호가 들어간다. 성공·실패 무관하게 반드시 지운다.
  [ -n "$CID" ] && docker rm -f "$CID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── 1. 컨테이너 생성 (아직 실행하지 않는다 — 파일을 먼저 넣어야 한다) ────────
log "빌더 컨테이너 생성: $IMAGE"

# 캐시는 named volume 으로 붙인다. 컨테이너는 매번 폐기되지만 gradle 배포판(약 200MB)과
# pub 패키지는 볼륨에 남아 2회차부터 빌드가 크게 짧아진다. 데몬이 관리하므로 DooD 안전.
#
# ★ --memory (S15P11B209-356). 상한 없이 돌린 것이 07-28 호스트 응답 불능의 직접 조건이었다.
#   이 안에서 도는 것: Gradle 데몬(-Xmx3G) + Kotlin 컴파일 데몬 + dart 스냅샷 + JVM 비힙 영역.
#   android/gradle.properties 의 -Xmx 와 **짝**이다 — 한쪽만 올리면 다른 쪽이 죽인다.
#
#   기본값 7g 의 근거 — 2026-07-29 첫 성공 빌드 실측:
#     빌더 컨테이너 피크 5.64GiB · 호스트 최저 가용 3.2GB · 스왑 152MB 사용 · OOMKilled 없음
#   처음엔 6g 로 뒀는데 피크가 상한의 **94%** 였다. 코드가 조금만 늘어도 exit 137(컨테이너
#   OOM-kill)로 죽고, 그 로그는 "왜 죽었는지 안 보이는" 형태다. 20% 여유를 두려고 7g 로 올린다.
#   더 올리는 건 호스트 여유를 먹는 것이니 preflight(--need 7168)와 같이 판단할 것.
CID="$(docker create \
  --memory "${BUILD_MEMORY:-7g}" \
  --memory-swap "${BUILD_MEMORY_SWAP:-9g}" \
  --env-file "$OAUTH_ENV_FILE" \
  -e "BUILD_NAME=${BUILD_NAME}" \
  -e "BUILD_NUMBER=${BUILD_NUMBER}" \
  -e "REQUIRE_RELEASE_SIGNING=${REQUIRE_RELEASE_SIGNING}" \
  -v "${GRADLE_CACHE_VOLUME}:/root/.gradle" \
  -v "${PUB_CACHE_VOLUME}:/root/.pub-cache" \
  "$IMAGE" \
  bash /src/ci-build.sh)"

# ── 2. 소스·서명자재 주입 ──────────────────────────────────────────────────
log "소스 주입 (docker cp — bind mount 아님)"
# frontend/mobile 의 **내용물**을 /src 로 넣는다. `.../mobile/.` 의 마침표가 그 의미다.
docker cp "$REPO_ROOT/frontend/mobile/." "$CID:/src/"
docker cp "$REPO_ROOT/infra/mobile/ci-build.sh" "$CID:/src/ci-build.sh"

if [ -n "$KEYSTORE_FILE" ] && [ -f "$KEYSTORE_FILE" ]; then
  log "릴리스 keystore 주입"
  docker cp "$KEYSTORE_FILE" "$CID:/src/android/upload-keystore.jks"
  docker cp "$KEY_PROPERTIES_FILE" "$CID:/src/android/key.properties"
else
  log "⚠️ keystore 없음 — debug 키로 서명된다(Play 업로드 불가)"
fi

# ── 3. 빌드 ────────────────────────────────────────────────────────────────
log "AAB 빌드 시작 (첫 회는 gradle 배포판·의존성 내려받느라 오래 걸린다)"
docker start -a "$CID"

# ── 4. 산출물 회수 ─────────────────────────────────────────────────────────
log "산출물 회수"
mkdir -p "$OUT_DIR"
docker cp "$CID:/src/build/app/outputs/bundle/release/app-release.aab" "$OUT_DIR/app-release.aab"
docker cp "$CID:/tmp/signing-report.txt" "$OUT_DIR/signing-report.txt" 2>/dev/null || true

SIZE="$(du -h "$OUT_DIR/app-release.aab" | cut -f1)"
printf '\n✅ AAB 생성: %s (%s)\n' "$OUT_DIR/app-release.aab" "$SIZE"
[ -f "$OUT_DIR/signing-report.txt" ] && {
  printf '   서명 확인:\n'
  sed 's/^/     /' "$OUT_DIR/signing-report.txt"
}
