#!/usr/bin/env bash
# ============================================================================
# dodam-minio-backup.sh — MinIO 오브젝트 백업 (컷백/compose 판)
#
# 원본: infra/k8s/base/cronjobs.yaml 의 CronJob `minio-backup`
#       (timeZone Asia/Seoul · schedule "30 */6 * * *" · 보관 14일)
# 스케줄: KST 00:30 · 06:30 · 12:30 · 18:30 — 원본과 동일.
#   ★ 6시간 주기인 이유(374): MySQL 은 잃어도 계정·설정이지만 MinIO 는 **아이가 그린 그림과
#     음성 원본**이다. 재생성할 수 없다. 하루 1회면 최대 24시간 공백이 생긴다.
#     데이터도 작아(2026-07-30 기준 8MB) 주기를 올리는 비용이 거의 없다.
#
# ⚠️ 백업 파일 = 아동 그림·음성·동의 증빙. 서버 밖 반출·전송 금지(CLAUDE.md 9절).
#
# 원본에서 **그대로 보존한 것**:
#   · 파일명   minio-<STAMP>.tar.gz.enc,  STAMP = date +%F-%H%M (KST)
#   · 제외     --exclude "tts-cache/*"  (TTS 로 재생성 가능한 파생물 — 설계 §1)
#   · tar 레이아웃  -C <stage> .   (minio-restore.sh 가 이 레이아웃을 전제로 푼다)
#   · 암호화   openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000
#   · 판정     objects == 0 → FAIL / bytes < 1024 → FAIL   (374 교훈: 빈 디렉터리도
#              tar+gzip 하면 수백 바이트가 나와 "OK size=4.0K" 로 성공처럼 보인다)
#   · 보관     -mtime +14 -delete
# 바뀐 것: 접근 경로. k8s 에서는 초기컨테이너(mc)가 클러스터 DNS 로 minio 에 붙었고,
#   여기서는 **compose 네트워크에 붙인 일회용 mc 컨테이너**가 같은 일을 한다.
#   (컷오버 이전 호스트 스크립트가 쓰던 `kubectl port-forward` 다리는 필요 없다.)
#
# ★ 왜 mc 컨테이너를 따로 띄우나 — minio/mc 이미지에는 mc 와 stat 밖에 없다.
#   tar·gzip·openssl·find 가 없어 한 컨테이너로 "받아서 묶고 암호화"를 끝낼 수 없다(733 실측).
#   그래서 mirror 만 컨테이너가 하고, 묶기·암호화는 호스트가 한다.
#
# 사용:
#   sudo /opt/dodam/cron/dodam-minio-backup.sh [--verify]
# ============================================================================
set -euo pipefail

JOB_NAME="dodam-minio-backup"
# shellcheck source=lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

CONTAINER="${MINIO_CONTAINER:-dodam-minio}"
MC_IMAGE="${MC_IMAGE:-minio/mc:RELEASE.2025-04-16T18-13-26Z}"   # latest 금지 — 원본과 동일 태그
BUCKET="${BUCKET:-dodam}"
EXCLUDE="${EXCLUDE:-tts-cache/*}"
VERIFY=0
[ "${1:-}" = "--verify" ] && VERIFY=1

backup_preamble "$CONTAINER"

docker network inspect "$COMPOSE_NETWORK" >/dev/null 2>&1 \
  || die 5 "[$JOB_NAME] FAIL 도커 네트워크가 없습니다: $COMPOSE_NETWORK (compose 프로젝트명 dodam 확인)"

STAMP="$(date +%F-%H%M)"
OUT="${BACKUP_DIR}/minio-${STAMP}.tar.gz.enc"

# ── 평문 스테이지 ───────────────────────────────────────────────────────────
# mirror 직후 이 디렉터리에는 **아이 그림·음성 원본이 평문으로** 놓인다.
#   · umask 077 로 700 생성 → root 만 읽는다
#   · trap 이 어떤 경로로 끝나든 지운다
#   · 시작할 때 12시간 넘은 잔여 스테이지도 함께 지운다(중간에 죽은 회차의 잔재 방지 —
#     원본이 emptyDir 를 택했던 이유가 바로 이 잔여물이다)
find /tmp -maxdepth 1 -type d -name 'dodam-minio-stage.*' -mmin +720 -exec rm -rf {} + 2>/dev/null || true
STAGE="$(mktemp -d /tmp/dodam-minio-stage.XXXXXX)"
MC_ENV="$(mktemp /tmp/dodam-mc-env.XXXXXX)"

cleanup() { rm -rf "$STAGE"; rm -f "$MC_ENV" "${OUT}.part"; }
trap cleanup EXIT

# ── 자격증명 ────────────────────────────────────────────────────────────────
# **돌고 있는 MinIO 컨테이너에서 직접 읽는다.** .env.compose 를 파싱하지 않는 이유가 둘 있다:
#   ① 그 파일의 값은 따옴표로 감싸여 있는데 `docker run --env-file` 은 따옴표를 벗기지 않는다.
#      그대로 넘기면 사용자명이 'user' 가 되어 **조용히 인증 실패**한다.
#   ② 백업 대상은 "지금 서비스가 쓰는 것"이어야 한다(732 교훈). 실행 중인 값이 진실이다.
# 값은 argv 에 절대 싣지 않는다(`-e K=V` 는 호스트 `ps` 에 보인다) → 600 임시 env 파일로 전달.
MINIO_USER="$(docker exec "$CONTAINER" sh -c 'printf "%s" "$MINIO_ROOT_USER"')"
MINIO_PASS="$(docker exec "$CONTAINER" sh -c 'printf "%s" "$MINIO_ROOT_PASSWORD"')"
[ -n "$MINIO_USER" ] && [ -n "$MINIO_PASS" ] \
  || die 5 "[$JOB_NAME] FAIL MinIO 자격증명을 컨테이너에서 읽지 못했습니다"
{
  printf 'MINIO_ROOT_USER=%s\n' "$MINIO_USER"
  printf 'MINIO_ROOT_PASSWORD=%s\n' "$MINIO_PASS"
  printf 'S3_BUCKET=%s\n' "$BUCKET"
  printf 'EXCLUDE=%s\n' "$EXCLUDE"
} > "$MC_ENV"
unset MINIO_USER MINIO_PASS

# ── 미러링 ──────────────────────────────────────────────────────────────────
# alias set 에 URL 을 쓰지 않고 **인자를 분리**한다. MC_HOST_<alias>=http://user:pass@host 형식은
#   비밀번호의 @ : / 를 퍼센트 인코딩해야 하고, 안 하면 조용히 다른 호스트를 가리킨다.
# --config-dir /tmp/mc : $HOME 쓰기 가능성에 의존하지 않는다.
# ⚠️ -v "$STAGE:/stage" 의 소스는 **호스트 경로**다. 이 스크립트를 컨테이너 안에서 돌리면
#   도커가 호스트에 빈 디렉터리를 만들어 붙여 objects=0 으로 떨어진다(DooD 경로 함정).
docker run --rm --network "$COMPOSE_NETWORK" --env-file "$MC_ENV" \
  -v "$STAGE:/stage" --entrypoint /bin/bash "$MC_IMAGE" -c '
    set -euo pipefail
    mc --config-dir /tmp/mc alias set src \
      "http://minio:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" >/dev/null
    mc --config-dir /tmp/mc mirror --quiet --overwrite \
      "src/${S3_BUCKET}" /stage --exclude "${EXCLUDE}"' \
  || die 6 "[$JOB_NAME] FAIL mc mirror 실패 (네트워크=$COMPOSE_NETWORK · 버킷=$BUCKET)"

# ★ 담긴 객체 수를 먼저 센다(374). 크기만 보면 빈 백업이 성공처럼 보인다.
OBJECTS="$(find "$STAGE" -type f | wc -l | tr -d '[:space:]')"
if [ "${OBJECTS}" -eq 0 ]; then
  die 6 "[minio-backup] FAIL 미러링 결과가 비었습니다 objects=0 — 버킷이 실제로 비었는지, 자격증명·버킷명이 어긋나지 않았는지 확인하세요."
fi

# ── 묶기 → 암호화 ───────────────────────────────────────────────────────────
# 레이아웃을 원본과 **똑같이**: -C <stage> 로 들어가서 "." 를 묶는다.
#   minio-restore.sh 가 이 레이아웃을 전제로 풀어 넣는다 — 여기서 어긋나면 복원 절차가 갈린다.
tar -C "$STAGE" -czf - . | encrypt_to "${OUT}.part" \
  || die 6 "[$JOB_NAME] FAIL tar·암호화 파이프라인 실패"
mv "${OUT}.part" "${OUT}"

BYTES="$(stat -c %s "${OUT}")"
if [ "${BYTES}" -lt 1024 ]; then
  rm -f "${OUT}"
  die 6 "[minio-backup] FAIL 백업이 비어 있습니다 bytes=${BYTES} objects=${OBJECTS}"
fi

if [ "$VERIFY" = "1" ]; then
  verify_backup "${OUT}" tar || die 6 "[$JOB_NAME] FAIL 복호화 검증 실패 — 패스프레이즈가 기존 백업과 다를 수 있습니다"
  log "[$JOB_NAME] VERIFY OK 복호화 + tar 목록 조회 통과"
fi

prune_old 'minio-*.tar.gz.enc'
log "[minio-backup] OK file=${OUT} bytes=${BYTES} objects=${OBJECTS} retention=${RETENTION_DAYS}d exclude=${EXCLUDE}"
