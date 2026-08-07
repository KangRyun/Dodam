#!/usr/bin/env bash
# ============================================================================
# dodam-certbot-renew.sh — Let's Encrypt 인증서 갱신 (컷백/compose 판)
#
# 원본: infra/k8s/base/cronjobs.yaml 의 CronJob `certbot-renew`
#       (schedule "17 3,15 * * *" · concurrencyPolicy Forbid · certbot/certbot:v2.11.0)
#
# ★ 스케줄 해석이 원본과 다르다 — 의도된 차이다.
#   원본 CronJob 에는 timeZone 이 **없어서** "17 3,15" 가 UTC 로 해석됐다(= KST 12:17 · 00:17).
#   호스트 cron 은 KST 로 해석하므로 같은 문자열이 KST 03:17 · 15:17 에 돈다.
#   원본 주석이 명시했듯 **여기서는 시각이 중요하지 않다**: renew 는 만료 30일 전이 아니면
#   no-op 이고, 하루 두 번 중 한 번만 걸려도 충분하다. 그래서 문자열(하루 2회·정시 회피)을
#   그대로 유지했다. 백업 3종은 시각이 중요해서 반대로 **시각**을 맞췄다(그쪽은 원본에
#   timeZone: Asia/Seoul 이 있어 KST 로 일치한다).
#
# 무엇을: 인증서 저장소·ACME webroot 를 **실행 중인 nginx 컨테이너의 마운트에서 알아내어**
#         certbot 컨테이너에 rw 로 물리고 renew 를 돌린다. 갱신이 실제로 일어났을 때만
#         nginx 를 reload 한다.
# 왜 경로를 하드코딩하지 않나: 두 경로는 k3s local-path PVC 의 uuid 디렉터리라
#         (`/var/lib/rancher/k3s/storage/pvc-…_dodam_letsencrypt`) 사람이 옮겨 적으면 틀린다.
#         compose 가 실제로 물린 것을 읽는 편이 언제나 맞다.
#
# ⚠️ compose 의 nginx 는 두 경로를 **:ro** 로 물고 있다(읽기만 하면 되므로 정상이다).
#    쓰는 쪽은 이 스크립트가 띄우는 certbot 컨테이너이며 rw 로 물린다.
#
# 현재 인증서 만료: 2026-10-20 → 갱신 창(만료 30일 전) 진입은 2026-09-20.
#   그전까지 이 잡은 매번 "no-op" 을 로그에 남기는 것이 정상이다.
#
# 사용: sudo /opt/dodam/cron/dodam-certbot-renew.sh [--dry-run]
#   --dry-run 은 certbot 의 --dry-run(스테이징 서버로 리허설)으로 넘어간다. 실제 인증서를
#   건드리지 않으므로 배선 점검에 안전하다. LE 스테이징에도 레이트리밋이 있으니 남용 금지.
# ============================================================================
set -euo pipefail

JOB_NAME="dodam-certbot-renew"
# shellcheck source=lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

NGINX_CONTAINER="${NGINX_CONTAINER:-dodam-nginx}"
CERTBOT_IMAGE="${CERTBOT_IMAGE:-certbot/certbot:v2.11.0}"   # latest 금지 — 원본과 동일 태그
DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && DRY_RUN="--dry-run"

require_root                       # /etc/letsencrypt 계열은 root 만 읽는다
command -v docker >/dev/null 2>&1 || die 5 "[$JOB_NAME] FAIL docker 를 찾을 수 없습니다(PATH=$PATH)"
# nginx 가 떠 있어야 한다 — HTTP-01 챌린지는 **80 포트로 서비스되는 webroot** 를 통해 검증된다.
#   nginx 가 없으면 갱신은 반드시 실패한다. 그 사실을 갱신을 시도한 뒤가 아니라 먼저 말한다.
require_container "$NGINX_CONTAINER"
acquire_lock

# ── 마운트 발견 ─────────────────────────────────────────────────────────────
mount_source() {   # $1=컨테이너  $2=컨테이너 안 경로
  docker inspect "$1" --format "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Source}}{{end}}{{end}}"
}
LE_DIR="$(mount_source "$NGINX_CONTAINER" /etc/letsencrypt)"
WEBROOT_DIR="$(mount_source "$NGINX_CONTAINER" /var/www/certbot)"
[ -n "$LE_DIR" ] && [ -d "$LE_DIR" ] \
  || die 4 "[$JOB_NAME] FAIL nginx 컨테이너에서 /etc/letsencrypt 마운트를 찾지 못했습니다"
[ -n "$WEBROOT_DIR" ] && [ -d "$WEBROOT_DIR" ] \
  || die 4 "[$JOB_NAME] FAIL nginx 컨테이너에서 /var/www/certbot 마운트를 찾지 못했습니다"
log "[$JOB_NAME] letsencrypt=$LE_DIR webroot=$WEBROOT_DIR"

# ── 갱신 여부 판정용 지문 ───────────────────────────────────────────────────
# live/<도메인>/fullchain.pem 은 archive/<도메인>/fullchainN.pem 을 가리키는 심링크다.
#   갱신되면 N 이 올라가 **가리키는 실체 경로가 바뀐다** → 그것으로 판정한다.
#   (파일 mtime 은 touch 등으로도 바뀌므로 심링크 대상이 더 정확한 신호다)
cert_fingerprint() {
  find "$LE_DIR/live" -maxdepth 2 -name 'fullchain.pem' -exec readlink -f {} \; 2>/dev/null | sort | sha256sum
}
BEFORE="$(cert_fingerprint)"

# ── 갱신 ────────────────────────────────────────────────────────────────────
# 인자는 원본 CronJob 과 동일: renew --webroot -w /var/www/certbot
#   renew 는 **기존 인증서만** 갱신한다. 최초 발급(certonly)은 하지 않는다.
docker run --rm \
  -v "$LE_DIR:/etc/letsencrypt" \
  -v "$WEBROOT_DIR:/var/www/certbot" \
  "$CERTBOT_IMAGE" renew --webroot -w /var/www/certbot $DRY_RUN \
  || die 6 "[$JOB_NAME] FAIL certbot renew 실패 — 위 로그의 challenge 결과를 확인하세요"

AFTER="$(cert_fingerprint)"

if [ "$BEFORE" != "$AFTER" ]; then
  # ★ 갱신됐으면 nginx 가 **파일을 다시 읽어야** 새 인증서를 쓴다. reload 없이는 만료된
  #   인증서를 계속 제시한다 — "갱신은 됐는데 브라우저는 만료라고 한다"의 전형적 원인.
  docker exec "$NGINX_CONTAINER" nginx -s reload \
    && log "[certbot-renew] RENEWED 인증서가 갱신되어 nginx 를 reload 했습니다" \
    || warn "[certbot-renew] WARN 인증서는 갱신됐으나 nginx reload 에 실패했습니다 — 수동으로: docker exec $NGINX_CONTAINER nginx -s reload"
else
  log "[certbot-renew] OK 갱신 대상 없음(만료 30일 전이 아니면 no-op 인 것이 정상입니다)"
fi

# 만료일을 매 회차 로그에 남긴다 — "언제까지 안전한가"를 사람이 로그만 보고 알 수 있게.
find "$LE_DIR/live" -maxdepth 2 -name 'fullchain.pem' | while read -r c; do
  end="$(openssl x509 -enddate -noout -in "$c" 2>/dev/null | cut -d= -f2)"
  log "[certbot-renew] cert=$(basename "$(dirname "$c")") notAfter=${end:-?}"
done
