#!/usr/bin/env bash
# 도담 Flutter 앱 테스트 실행 (S15P11B209-642)
#
# 호스트에서도 Jenkins 안에서도 **똑같이** 동작한다 — build-aab.sh 와 같은 설계다.
#
# ⚠️ bind mount 를 쓰지 않는 이유 (build-aab.sh 와 동일, 이 저장소에서 두 번 터진 함정)
#   Jenkins 는 컨테이너 안에서 호스트 도커 소켓을 부른다(Docker-out-of-Docker).
#   `-v "$PWD:/src"` 를 쓰면 경로 해석은 Jenkins 컨테이너 안에서, 실제 마운트는 호스트가 한다.
#   jenkins_home 은 named volume 이라 /var/jenkins_home/workspace/... 는 호스트에 없고,
#   도커는 없는 경로에 **빈 디렉터리를 만들어 붙인다.** 그러면 소스가 사라진 채
#   "테스트 0건 통과"라는 최악의 초록불이 나온다.
#   (실제 사고 2회: 2026-07-22 nginx 빈 conf, 2026-07-26 minio-init exit 127)
#   → 소스는 docker cp 로 넣는다. 캐시만 named volume(데몬이 관리하므로 DooD 안전).
#
# 사용:
#   infra/mobile/ci-test.sh                 # 전체 테스트
#   TEST_TARGET=test/app infra/mobile/ci-test.sh   # 일부만
#
# 종료코드: flutter test 의 종료코드를 그대로 전달한다(0=통과).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${BUILDER_IMAGE:-dodam-flutter-builder:3.44.7}"
GRADLE_CACHE_VOLUME="${GRADLE_CACHE_VOLUME:-dodam-android-gradle}"
PUB_CACHE_VOLUME="${PUB_CACHE_VOLUME:-dodam-android-pub}"
TEST_MEMORY="${TEST_MEMORY:-4g}"
TEST_MEMORY_SWAP="${TEST_MEMORY_SWAP:-6g}"
TEST_TARGET="${TEST_TARGET:-}"

log() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }

# ── 메모리 관문 (S15P11B209-356) ──────────────────────────────────────────────
# 07-28 호스트 OOM 과 같은 부하 계열이라 시작 전에 관문을 통과시킨다.
# SKIP_PREFLIGHT=1 은 관문 자체가 고장 났을 때의 탈출구다.
#
# --in-ci: 이 스크립트는 Jenkins 빌드 **안에서** 돈다. 그게 없으면 preflight 가
#   자기 파이프라인의 testcontainers 를 "다른 빌드"로 보고 막아버린다(S15P11B209-642 —
#   팀원이 동시에 푸시하기만 하면 이 스테이지가 상시 실패했다).
#   RAM 검사는 그대로 유효하다 — 자기참조인 항목만 정보로 낮춘다.
#
# ★ --need 2048 의 근거 (2026-07-29 실측, 591 테스트 전량 통과 기준):
#     피크 993MiB · 평균 872MiB · 샘플 36개(2초 간격)
#   이전 값 4096 은 "컨테이너 상한 4g 만큼 미리 확보"에서 나온 것이었는데,
#   **상한은 예약이 아니라 폭주 방지 안전장치다.** 1GB 면 되는 작업 때문에 4GB 가
#   비기를 기다리느라 빌드가 막혔다(실패 사례: 가용 3973MB < 4096MB).
#   2048 = 실측 피크의 약 2배 — 1회 측정·2초 샘플링의 한계를 감안한 여유.
#   ⚠️ 앱 테스트 수가 크게 늘거나 통합 테스트가 붙으면 다시 재서 갱신할 것.
if [ "${SKIP_PREFLIGHT:-0}" != "1" ] && [ -x "$REPO_ROOT/infra/scripts/preflight-memory.sh" ]; then
  "$REPO_ROOT/infra/scripts/preflight-memory.sh" --need 2048 --in-ci \
    || die "메모리 사전 점검 실패 — 위 이유를 해소하고 다시 실행할 것."
fi

# ── 빌더 이미지 ──────────────────────────────────────────────────────────────
# 없으면 **실패시킨다.** 조용히 건너뛰면 "앱 코드를 고쳤는데 테스트는 안 돌고 초록불"이 되는데,
# 이 저장소에서 반복된 실패 양상이 정확히 그것이다("존재한다"와 "동작한다"는 다르다).
docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || die "빌더 이미지가 없다: $IMAGE
   → docker build -t $IMAGE infra/mobile   (10~20분)
   ⚠️ 이 이미지는 태그가 있어도 '사용 안 하는 이미지'라 docker image prune -af 로 지워진다
      (2026-07-28 실제 소실)."

CID=""
cleanup() { [ -n "$CID" ] && docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

log "테스트 컨테이너 생성 (메모리 상한 ${TEST_MEMORY})"
# 캐시는 named volume — pub 패키지 재다운로드를 막아 2회차부터 크게 짧아진다.
CID="$(docker create \
  --memory "$TEST_MEMORY" \
  --memory-swap "$TEST_MEMORY_SWAP" \
  -v "${GRADLE_CACHE_VOLUME}:/root/.gradle" \
  -v "${PUB_CACHE_VOLUME}:/root/.pub-cache" \
  "$IMAGE" \
  bash -c "
    set -e
    cd /src
    # 호스트 잔재 정리 — docker cp 는 .gitignore 를 모르고 작업 트리를 통째로 가져온다.
    #   android/local.properties 에는 **호스트의** flutter.sdk 경로가 박혀 있어
    #   컨테이너 안에서는 없는 경로를 가리킨다.
    rm -f android/local.properties
    rm -rf build .dart_tool android/.gradle android/app/build
    echo '── flutter pub get'
    flutter pub get
    echo '── flutter test ${TEST_TARGET}'
    flutter test ${TEST_TARGET} --reporter compact
  ")"

log "소스 주입 (docker cp — bind mount 아님)"
docker cp "$REPO_ROOT/frontend/mobile/." "$CID:/src/" >/dev/null

log "테스트 실행"
docker start -a "$CID"
RC=$?

if [ "$RC" -eq 0 ]; then
  printf '\n✅ 앱 테스트 통과\n'
else
  printf '\n❌ 앱 테스트 실패 (종료코드 %s) — 위 로그의 [E] 항목 확인\n' "$RC"
fi
exit "$RC"
