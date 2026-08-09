#!/usr/bin/env bash
# 도담 — 앱 계층(backend·ai·web) **단일 노드형 블루-그린 무중단 배포** 엔진
# 관련: docker-compose(infra/docker-compose.yml) · gateway(infra/nginx/conf.d.compose)
#
# ────────────────────────────────────────────────────────────────────────────
# 무엇을 하는가
#   서비스 하나를 유휴 색(idle)으로 새 이미지 태그에 띄워 **내부 헬스체크가 통과할 때까지**
#   기다린 뒤, nginx 의 활성 색 스위치(upstream-active.conf)만 유휴 색으로 다시 써
#   `nginx -t && nginx -s reload` 로 트래픽을 넘긴다. 그 다음 옛(직전 활성) 색을 정지한다.
#   → 사용자 입장에서 순단이 없다(무중단 *배포*). 단, 상시 이중화는 아니다 —
#     정상 상태에는 활성 색 1벌만 뜬다(RAM 제약). 유휴 색은 배포 순간에만 존재한다.
#
# 왜 "상시 두 색"이 아닌가
#   노드 RAM 15G·가용 8.2G. backend 1.5G·ai 2G·web 0.5G 를 두 벌 상시로 물면 예산을 넘는다.
#   단일 노드라 어차피 HA(상시 이중화)는 SPOF 를 못 없앤다. 목표는 무중단 *배포*뿐이다.
#
# 사용법
#   배포:   infra/scripts/bluegreen-deploy.sh <backend|ai|web> <이미지태그>
#   롤백:   infra/scripts/bluegreen-deploy.sh --rollback <backend|ai|web>
#           (= infra/scripts/bluegreen-rollback.sh <backend|ai|web>)
#   롤백은 "직전 색"으로 되돌린다 — 직전 색이 마지막에 돌던 태그(infra/.env.active 기록)로
#   다시 띄우고 스위치를 되돌린다.
#
# 상태의 단일 출처(source of truth) = infra/.env.active   (운영 상태 파일, git 비추적)
#   ACTIVE_BACKEND / ACTIVE_AI / ACTIVE_WEB   = 각 서비스의 현재 활성 색(blue|green)
#   IMAGE_TAG_<SVC>_<COLOR>                    = 그 색이 마지막에 뜬 이미지 태그(재부팅 복원용)
#   COMPOSE_PROFILES                           = 활성 색 profile 목록(= 기본 up -d 가 띄우는 색)
#   ⚠️ upstream-active.conf 는 이 파일에서 **파생**된다(이 스크립트가 다시 쓴다). 손으로 고치지 말 것.
#   템플릿·형식은 infra/.env.active.example 참조.
#
# ★★ 최초 컷오버(레거시 단일 서비스 → 블루-그린)는 이 스크립트가 아니라 사람이 런북으로 한다.
#   현재 운영은 단일 서비스(dodam-backend/ai/web, 컷백 compose)로 돌고 있고, 그 상태는
#   "blue" 도 "green" 도 아니다. 이 스크립트는 blue↔green 만 오간다. 최초 1회 절차:
#     0) (이미 반영됨) compose 는 blue/green 정의, default.conf 는 *_active 참조,
#        upstream-active.conf 는 **현재 떠 있는 레거시 이름(backend/ai/web)** 을 가리킨다.
#        → 이 상태는 지금 라우팅과 동일하고 재부팅에도 안전하다(스위치 파일 헤더 참조).
#     1) 활성 색을 blue 로 정하고 현재 태그로 세 색을 띄운다(순단 없음 — 레거시는 아직 살아 있다):
#          docker compose -f infra/docker-compose.yml \
#            --env-file infra/.env.compose --env-file infra/.env.active \
#            up -d --no-deps backend-blue ai-blue web-blue
#        (infra/.env.active 를 .example 로부터 만들어 두고 실행. ACTIVE_*=blue,
#         COMPOSE_PROFILES=backend-blue,ai-blue,web-blue, IMAGE_TAG_*_BLUE=<현재태그>)
#     2) 세 blue 가 healthy 인지 확인: docker ps / docker inspect health
#     3) upstream-active.conf 를 blue 로 바꾸고 reload:
#          (backend→backend-blue, ai→ai-blue, web→web-blue 로 server 줄 교체)
#          docker exec dodam-nginx nginx -t && docker exec dodam-nginx nginx -s reload
#        (blue 가 이미 떠 있으므로 -t 통과 · 순단 없음)
#     4) 레거시 정지·제거: docker rm -f dodam-backend dodam-ai dodam-web
#     ⚠️ 이 창(파일 반영~컷오버 완료) 동안에는 `docker compose ... up -d --remove-orphans`
#        나 전체 up -d 를 돌리지 말 것 — 레거시가 orphan 으로 제거돼 upstream(→backend)이 깨진다.
#   컷오버 이후에는 이 스크립트로 blue↔green 무중단 배포만 하면 된다.
#
# ⚠️ 이 스크립트는 서버 상태를 바꾼다(컨테이너 기동/정지·nginx reload). CI(Jenkins) 또는 사람이
#   실행한다. 파일만 만드는 단계에서는 실행하지 말 것.
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── 경로·상수 ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/infra/docker-compose.yml}"
ENV_COMPOSE="${ENV_COMPOSE:-$REPO_ROOT/infra/.env.compose}"
ENV_ACTIVE="${ENV_ACTIVE:-$REPO_ROOT/infra/.env.active}"
UPSTREAM_CONF="${UPSTREAM_CONF:-$REPO_ROOT/infra/nginx/conf.d.compose/upstream-active.conf}"
NGINX_CONTAINER="${NGINX_CONTAINER:-dodam-nginx}"

# 헬스체크 최대 대기(초) — compose healthcheck start_period 와 짝. backend 는 JVM+Flyway 로 길다.
declare -A HC_TIMEOUT=( [backend]=300 [ai]=180 [web]=180 )
declare -A SVC_PORT=(   [backend]=8080 [ai]=8000 [web]=3000 )

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "$*"; }

# ── 상태 파일 헬퍼 ──────────────────────────────────────────────────────────
require_env_active() {
  [ -f "$ENV_ACTIVE" ] || die "상태 파일이 없다: $ENV_ACTIVE
   → 최초 컷오버(레거시→blue)를 먼저 수행하고 infra/.env.active 를 만들 것(이 스크립트 헤더 ★★ 절)."
}

# infra/.env.active 에서 KEY 값을 읽는다(없으면 빈 문자열).
kv_get() { grep -E "^$1=" "$ENV_ACTIVE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\""; }

# KEY=VALUE 를 멱등 upsert. 값은 영숫자(색·태그·profile 목록)라 sed 구분자 안전.
kv_set() {
  local key="$1" val="$2"
  if grep -qE "^$key=" "$ENV_ACTIVE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=$val|" "$ENV_ACTIVE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_ACTIVE"
  fi
}

opposite() { [ "$1" = "blue" ] && echo green || echo blue; }
upper()    { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

read_active() { kv_get "ACTIVE_$(upper "$1")"; }               # 서비스 → 현재 색
read_tag()    { kv_get "IMAGE_TAG_$(upper "$1")_$(upper "$2")"; } # (서비스,색) → 기록 태그

# COMPOSE_PROFILES 를 ACTIVE_* 로부터 재계산해 기록(= 기본 up -d 가 활성 색만 띄우게).
recompute_profiles() {
  local be ai web
  be="$(read_active backend)"; ai="$(read_active ai)"; web="$(read_active web)"
  kv_set COMPOSE_PROFILES "backend-${be},ai-${ai},web-${web}"
}

# ── nginx 스위치(파생 파일) ─────────────────────────────────────────────────
# upstream-active.conf 를 (be,ai,web) 색으로 다시 쓴다. default.conf 는 이 세 upstream 을 참조.
write_upstream() {  # $1=backend색 $2=ai색 $3=web색
  cat > "$UPSTREAM_CONF" <<EOF
# 도담 게이트웨이 — 블루-그린 활성 색 스위치 (bluegreen-deploy.sh 가 생성 — 손으로 고치지 말 것)
#   상태의 출처: infra/.env.active. default.conf 의 /api/·/api/oauth/·/·/ai/ 가 아래를 참조한다.
upstream backend_active { server backend-$1:8080; }
upstream ai_active      { server ai-$2:8000; }
upstream web_active     { server web-$3:3000; }
EOF
}

nginx_test()   { docker exec "$NGINX_CONTAINER" nginx -t; }
nginx_reload() { docker exec "$NGINX_CONTAINER" nginx -s reload; }

# ── 헬스체크 ────────────────────────────────────────────────────────────────
# 컨테이너 자체 healthcheck(=compose 에 정의된 실측 경로)를 폴링한다.
wait_healthy() {  # $1=컨테이너 $2=최대초
  local c="$1" max="$2" n=0 st
  while [ "$n" -lt "$max" ]; do
    st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo missing)
    [ "$st" = "healthy" ] && { log "   ✅ $c healthy (${n}s)"; return 0; }
    sleep 5; n=$((n+5))
  done
  log "   ❌ $c 가 ${max}초 안에 healthy 가 되지 않았다 (마지막=$st) — docker logs --tail 100 $c"
  return 1
}

# 유휴 색의 **실측 헬스 경로**를 컨테이너 안에서 직접 한 번 더 확인(문서화 겸 이중 확인).
#   backend=9404 /actuator/health/readiness · ai=8000 /health · web=3000 / (statusCode<400)
probe_path() {  # $1=서비스 $2=컨테이너
  case "$1" in
    backend) docker exec "$2" curl -fsS -o /dev/null "http://127.0.0.1:9404/actuator/health/readiness" ;;
    ai)      docker exec "$2" python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)" ;;
    web)     docker exec "$2" node -e "require('http').get('http://127.0.0.1:3000/',r=>process.exit(r.statusCode<400?0:1)).on('error',()=>process.exit(1))" ;;
  esac
}

# ── 핵심: 서비스를 반대 색으로 전환 ─────────────────────────────────────────
# deploy 와 rollback 이 공유한다. 차이는 대상 색과 태그를 어떻게 정하느냐 뿐.
do_switch() {  # $1=서비스 $2=대상색(idle) $3=이미지태그(비면 ${IMAGE_TAG} 폴백)
  local svc="$1" target="$2" tag="${3:-}"
  local svc_u col_u current idle_service idle_container idle_profile old_container hc
  svc_u="$(upper "$svc")"; col_u="$(upper "$target")"
  current="$(read_active "$svc")"
  [ -n "$current" ] || die "ACTIVE_${svc_u} 값이 비어 있다 — infra/.env.active 확인(컷오버 필요할 수 있음)."
  if [ "$target" = "$current" ]; then
    log "ℹ️  $svc 는 이미 $target 이다 — 할 일 없음."; return 0
  fi
  idle_service="${svc}-${target}"
  idle_container="dodam-${svc}-${target}"
  idle_profile="${svc}-${target}"
  old_container="dodam-${svc}-${current}"
  hc="${HC_TIMEOUT[$svc]}"

  log "▶ 블루-그린 전환: [$svc] $current → $target  (태그=${tag:-'(폴백 ${IMAGE_TAG})'})"
  log "  · 유휴 색 컨테이너=$idle_container · 옛 색=$old_container · 포트=${SVC_PORT[$svc]}"

  # ── 게이트 1: 유휴 색을 새 태그로 기동 ───────────────────────────────────
  # --no-deps: 데이터 계층(mysql·mongo·redis·minio)을 절대 건드리지 않는다(배포=데이터사고 방지).
  # --force-recreate: 유휴 색은 트래픽이 없으므로 재생성해 **정확히 새 태그**임을 보장한다
  #   (정지 상태로 남아 있던 옛 컨테이너를 그대로 start 해 낡은 이미지로 뜨는 함정 차단).
  # COMPOSE_PROFILES 를 유휴 profile 로 셸에서 덮어 유휴 색만 선택되게 한다(서브셸로 격리).
  log "  ① 유휴 색 기동 ($idle_service @ ${tag:-'${IMAGE_TAG}'})"
  if ! (
        export COMPOSE_PROFILES="$idle_profile"
        [ -n "$tag" ] && export "IMAGE_TAG_${svc_u}_${col_u}=$tag"
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_COMPOSE" --env-file "$ENV_ACTIVE" \
          up -d --no-deps --force-recreate "$idle_service"
      ); then
    log "  ❌ 유휴 색 기동 실패 — 전환 중단(활성 색 그대로)."
    docker stop "$idle_container" >/dev/null 2>&1 || true
    return 1
  fi

  # ── 게이트 2: 유휴 색 내부 헬스체크 통과 대기 ─────────────────────────────
  log "  ② 유휴 색 헬스체크 대기(최대 ${hc}s)"
  if ! wait_healthy "$idle_container" "$hc"; then
    log "  ❌ 헬스체크 실패 — 유휴 색 정지 후 중단(활성 색 그대로)."
    docker stop "$idle_container" >/dev/null 2>&1 || true
    return 1
  fi
  log "  ②' 실측 경로 재확인"
  if ! probe_path "$svc" "$idle_container"; then
    log "  ❌ 실측 경로 확인 실패 — 유휴 색 정지 후 중단(활성 색 그대로)."
    docker stop "$idle_container" >/dev/null 2>&1 || true
    return 1
  fi
  log "     ✅ 유휴 색 준비 완료"

  # ── 게이트 3: nginx 스위치(파생 파일 재작성 → -t → reload) ────────────────
  # 이 지점부터가 "커밋 구간". 실패 시 자동 롤백(파일 원복 + reload).
  cp -f "$UPSTREAM_CONF" "$UPSTREAM_CONF.prev"
  local be_c ai_c web_c
  be_c="$(read_active backend)"; ai_c="$(read_active ai)"; web_c="$(read_active web)"
  case "$svc" in backend) be_c="$target";; ai) ai_c="$target";; web) web_c="$target";; esac
  write_upstream "$be_c" "$ai_c" "$web_c"

  rollback_nginx() {   # 직전 upstream 으로 원복 + reload
    if [ -f "$UPSTREAM_CONF.prev" ]; then
      mv -f "$UPSTREAM_CONF.prev" "$UPSTREAM_CONF"
      log "  ↩︎ upstream-active.conf 원복"
      if nginx_test >/dev/null 2>&1 && nginx_reload >/dev/null 2>&1; then
        log "  ↩︎ nginx 원복 reload 완료 — 활성 색은 $current 로 유지"
      else
        log "  ⚠️ nginx 원복 reload 실패 — 수동 확인 필요: docker exec $NGINX_CONTAINER nginx -t"
      fi
    fi
    docker stop "$idle_container" >/dev/null 2>&1 && log "  ↩︎ 유휴 색 $idle_container 정지" || true
  }

  log "  ③ nginx -t"
  if ! nginx_test; then
    log "  ❌ nginx -t 실패 — 자동 롤백."
    rollback_nginx; return 1
  fi
  log "  ④ nginx -s reload (트래픽 전환)"
  if ! nginx_reload; then
    log "  ❌ nginx reload 실패 — 자동 롤백."
    rollback_nginx; return 1
  fi

  # ── 게이트 4: 전환 후 확인(게이트웨이·유휴 색이 여전히 정상인가) ──────────
  log "  ⑤ 전환 후 확인"
  if ! wait_healthy "$NGINX_CONTAINER" 30 || ! wait_healthy "$idle_container" 30; then
    log "  ❌ 전환 후 확인 실패 — 자동 롤백."
    rollback_nginx; return 1
  fi

  # ── 커밋: 상태 반영 + 옛 색 정지 ─────────────────────────────────────────
  rm -f "$UPSTREAM_CONF.prev"
  kv_set "ACTIVE_${svc_u}" "$target"
  [ -n "$tag" ] && kv_set "IMAGE_TAG_${svc_u}_${col_u}" "$tag"
  recompute_profiles
  log "  ⑥ 상태 반영(infra/.env.active): ACTIVE_${svc_u}=$target"

  # 옛(직전 활성) 색 정지 — graceful(SIGTERM, stop_grace_period 준수). RAM 회수.
  #   실패해도 배포는 성공이다(두 색이 잠깐 함께 떠 RAM 만 더 쓸 뿐, 순단 아님).
  if docker stop "$old_container" >/dev/null 2>&1; then
    log "  ⑦ 옛 색 $old_container 정지(RAM 회수)"
  else
    log "  ⚠️ 옛 색 $old_container 정지 실패 — 수동 정지 권장: docker stop $old_container"
  fi

  log "✅ [$svc] 블루-그린 배포 완료 — 활성 색=$target"
  return 0
}

# ── 진입점 ──────────────────────────────────────────────────────────────────
usage() {
  cat >&2 <<USAGE
사용법:
  $0 <backend|ai|web> <이미지태그>     # 배포(유휴 색으로 새 태그 무중단 전환)
  $0 --rollback <backend|ai|web>       # 롤백(직전 색으로 되돌림)
USAGE
  exit 2
}

main() {
  local mode="deploy" svc tag
  if [ "${1:-}" = "--rollback" ]; then mode="rollback"; shift; fi
  svc="${1:-}"; [ -n "$svc" ] || usage
  case "$svc" in backend|ai|web) ;; *) die "서비스는 backend|ai|web 중 하나여야 한다: '$svc'";; esac

  require_env_active
  [ -x "$(command -v docker)" ] || die "docker 를 찾을 수 없다."
  docker inspect "$NGINX_CONTAINER" >/dev/null 2>&1 || die "$NGINX_CONTAINER 가 실행 중이 아니다 — 게이트웨이가 있어야 전환할 수 있다."

  local current target
  current="$(read_active "$svc")"
  [ -n "$current" ] || die "ACTIVE_$(upper "$svc") 가 비어 있다 — infra/.env.active 확인(컷오버 필요할 수 있음)."
  target="$(opposite "$current")"

  if [ "$mode" = "deploy" ]; then
    tag="${2:-}"; [ -n "$tag" ] || { echo "배포에는 이미지태그가 필요하다." >&2; usage; }
    do_switch "$svc" "$target" "$tag"
  else
    # 롤백: 직전 색(=반대 색)이 마지막에 돌던 태그로 되돌린다. 기록이 없으면 ${IMAGE_TAG} 폴백.
    tag="$(read_tag "$svc" "$target")"
    log "↩︎ 롤백 요청: [$svc] $current → $target (되돌릴 태그=${tag:-'(폴백 ${IMAGE_TAG})'})"
    do_switch "$svc" "$target" "$tag"
  fi
}

main "$@"
