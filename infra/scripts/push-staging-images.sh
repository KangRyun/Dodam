#!/usr/bin/env bash
# 스테이징 이미지 로컬 레지스트리 푸시 (S15P11B209-359)
#
# k3s 의 containerd 는 **도커 데몬의 이미지 저장소를 보지 못한다.** 같은 호스트에 있어도
# `dodam-backend:local` 은 containerd 입장에서 존재하지 않는 이미지다(356 에서 확인).
# 그래서 로컬 레지스트리(127.0.0.1:5000)를 거쳐 넘긴다.
#
# 사용:
#   infra/scripts/push-staging-images.sh                  # :local → :staging
#   infra/scripts/push-staging-images.sh --tag 5298a8ff   # :local → :5298a8ff
#   infra/scripts/push-staging-images.sh --with-ai        # ai(2.36GB) 포함
#
# ai 를 기본에서 뺀 이유: staging-min overlay 가 ai 를 replicas 0 으로 두므로 pull 되지 않는다.
#   2.36GB 를 매번 밀 이유가 없다. 전체 스테이징으로 갈 때 --with-ai 로 켠다.

set -euo pipefail

REGISTRY="${REGISTRY:-127.0.0.1:5000}"
SRC_TAG="${SRC_TAG:-local}"
TAG="staging"
WITH_AI=0

log() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die() { printf '\n❌ %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)      TAG="${2:?--tag 에 값이 필요하다}"; shift 2 ;;
    --with-ai)  WITH_AI=1; shift ;;
    *)          die "알 수 없는 인자: $1 (--tag TAG | --with-ai)" ;;
  esac
done

IMAGES=(dodam-backend dodam-nginx)
[ "$WITH_AI" = "1" ] && IMAGES+=(dodam-ai)

# ── 레지스트리 HTTP 조회 ───────────────────────────────────────────────────
# ★ 여기가 이 스크립트에서 제일 헷갈리는 지점이다.
#   레지스트리는 **호스트 루프백에만** 붙어 있다(127.0.0.1:5000 → HostIp=127.0.0.1).
#   - 호스트에서 실행하면 curl 로 그냥 닿는다.
#   - Jenkins 컨테이너 안에서는 127.0.0.1 이 **자기 자신**이라 닿지 않는다.
#     (2026-07-29 빌드 18 이 정확히 이걸로 죽었다 — 같은 함정을 NodePort 주석에
#      적어놓고 이 조회에서 다시 밟았다)
#
#   반면 `docker push` 는 클라이언트가 아니라 **데몬**이 수행한다. 데몬은 호스트에
#   있으므로 127.0.0.1:5000 을 제대로 해석한다 → push 주소는 바꿀 필요가 없다.
#   조회만 호스트 네트워크로 우회하면 된다.
PROBE_IMAGE="${PROBE_IMAGE:-dodam-nginx:local}"
registry_get() {
  # 1) 호스트에서 실행된 경우
  curl -fsS -m 5 "http://${REGISTRY}$1" 2>/dev/null && return 0
  # 2) 컨테이너 안인 경우 — 호스트 네트워크에 붙인 일회용 컨테이너로 조회
  docker run --rm --network host "$PROBE_IMAGE" \
    wget -q -O - -T 5 "http://${REGISTRY}$1" 2>/dev/null
}

# ── 1. 레지스트리가 살아 있는가 ────────────────────────────────────────────
# reason: 죽어 있으면 push 가 한참 재시도하다 죽는다. 앞에서 끊고 이유를 말해준다.
log "레지스트리 확인: $REGISTRY"
registry_get "/v2/" >/dev/null 2>&1 \
  || die "레지스트리에 닿지 않는다: http://${REGISTRY}/v2/
   호스트·컨테이너 두 경로 모두 실패했다.
   → 기동 확인: docker ps | grep dodam-registry (S15P11B209-356)
   → 컨테이너에서 실행 중이라면 조회용 이미지도 확인: ${PROBE_IMAGE}"

# ── 2. 원본 이미지가 있는가 ────────────────────────────────────────────────
for img in "${IMAGES[@]}"; do
  docker image inspect "${img}:${SRC_TAG}" >/dev/null 2>&1 \
    || die "원본 이미지가 없다: ${img}:${SRC_TAG}
   → 먼저 빌드할 것: docker compose -f infra/docker-compose.yml build"
done

# ── 3. 태그 + 푸시 ─────────────────────────────────────────────────────────
for img in "${IMAGES[@]}"; do
  log "푸시: ${img}:${SRC_TAG} → ${REGISTRY}/${img}:${TAG}"
  docker tag  "${img}:${SRC_TAG}" "${REGISTRY}/${img}:${TAG}"
  docker push "${REGISTRY}/${img}:${TAG}"
done

# ── 4. 레지스트리에 실제로 올라갔는지 확인 ─────────────────────────────────
# ★ push 의 종료코드만 믿지 않는다. "존재한다"와 "동작한다"는 따로 검증한다 —
#   이 저장소에서 거짓 초록불로 두 번 데였다(07-22 빈 conf, 07-29 grep 오판).
log "레지스트리 태그 확인"
fail=0
for img in "${IMAGES[@]}"; do
  if registry_get "/v2/${img}/tags/list" | grep -q "\"${TAG}\""; then
    printf '   ✅ %s:%s\n' "$img" "$TAG"
  else
    printf '   ❌ %s:%s — 레지스트리에서 확인되지 않는다\n' "$img" "$TAG"
    fail=1
  fi
done
[ "$fail" = "0" ] || die "푸시는 끝났다고 했지만 레지스트리에 없는 이미지가 있다."

printf '\n✅ 푸시 완료 — %s (태그: %s)\n' "${IMAGES[*]}" "$TAG"
