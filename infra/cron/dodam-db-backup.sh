#!/usr/bin/env bash
# ============================================================================
# dodam-db-backup.sh — MySQL 백업 (컷백/compose 판)
#
# 원본: infra/k8s/base/cronjobs.yaml 의 CronJob `db-backup`
#       (timeZone Asia/Seoul · schedule "0 4 * * *" · 보관 14일)
# 스케줄: KST 04:00 — 원본과 동일 시각. 설치는 infra/cron/dodam-compose.cron.
#
# ⚠️ 백업 파일 = 아동 민감정보(그림·대화·리포트 원본). 서버 밖 반출·전송 금지(CLAUDE.md 9절).
#
# 원본에서 **그대로 보존한 것**(바꾸면 기존 복원 절차가 갈라진다):
#   · 파일명   b209-<STAMP>.sql.gz.enc,  STAMP = date +%F-%H%M (KST)
#   · 덤프     --single-transaction --routines --triggers --databases "$MYSQL_DATABASE"
#   · 암호화   openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000
#   · 판정     bytes < 1024 → FAIL (빈 백업을 성공으로 보고하지 않는다 — 374 교훈)
#   · 보관     -mtime +14 -delete
# 바뀐 것은 **접근 경로 하나뿐**이다: `mysqldump -h mysql`(k8s Service) → 컨테이너 안 127.0.0.1.
#
# 사용:
#   sudo /opt/dodam/cron/dodam-db-backup.sh            # 평시(cron 이 부르는 형태)
#   sudo /opt/dodam/cron/dodam-db-backup.sh --verify   # 산출물을 실제로 복호화해 검증
# ============================================================================
set -euo pipefail

JOB_NAME="dodam-db-backup"
# shellcheck source=lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

CONTAINER="${MYSQL_CONTAINER:-dodam-mysql}"
VERIFY=0
[ "${1:-}" = "--verify" ] && VERIFY=1

backup_preamble "$CONTAINER"

STAMP="$(date +%F-%H%M)"
# ★ 접두사 b209- 는 **하드코딩이 맞다.** 원본 CronJob·기존 호스트 스크립트·보관 정리 패턴·
#   복원 문서가 전부 이 이름을 전제한다. DB명을 따라가게 만들면 이름이 갈리는 순간
#   옛 산출물을 아무도 정리하지 않고, 복원 절차도 두 벌이 된다.
OUT="${BACKUP_DIR}/b209-${STAMP}.sql.gz.enc"
trap 'rm -f "${OUT}.part"' EXIT   # 부분 파일을 정상 백업으로 오인하지 않게 한다

# 이름 규약과 실제 DB 가 어긋나면 경고만 남긴다(실패로 막지는 않는다 — 덤프에는 --databases 로
#   DB명이 들어가므로 복원은 여전히 된다. 다만 파일명이 내용과 다르면 사람이 헷갈린다).
DB_IN_CONTAINER="$(docker exec "$CONTAINER" sh -c 'printf "%s" "$MYSQL_DATABASE"' 2>/dev/null || true)"
[ "$DB_IN_CONTAINER" = "b209" ] || warn "[$JOB_NAME] WARN 컨테이너의 MYSQL_DATABASE=$DB_IN_CONTAINER 인데 파일명 접두사는 b209- 입니다"

# ── 덤프 → gzip → 암호화 ────────────────────────────────────────────────────
# MYSQL_PWD 로 넘긴다: -p 로 주면 비밀번호가 컨테이너 프로세스 목록(argv)에 남고,
#   mysqldump 가 경고를 stderr 로 뱉어 성공 로그를 더럽힌다.
# --databases 는 ★빠뜨리면 안 된다 — mysql-restore.sh 가 "DB명을 지정하지 않고 클라이언트에
#   그대로 흘려보낸다"는 전제로 짜여 있다(그 스크립트 109행). 없으면 절차가 두 벌이 된다.
# pipefail 덕에 mysqldump 가 죽으면 파이프 전체가 실패한다(암호화만 성공하는 일이 없다).
docker exec "$CONTAINER" sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -h 127.0.0.1 -u root \
     --single-transaction --routines --triggers --databases "$MYSQL_DATABASE"' \
  | gzip \
  | encrypt_to "${OUT}.part" \
  || die 6 "[$JOB_NAME] FAIL 덤프·암호화 파이프라인 실패 (컨테이너=$CONTAINER)"

mv "${OUT}.part" "${OUT}"

# ★ 크기가 아니라 "내용이 있는가"를 본다. 2026-07-28 에는 `OK size=4.0K` 로 성공을 알리던
#   백업이 실제로는 빈 파일이었다(374). 그 사고의 교훈은 "비었다"가 아니라
#   **"비었다는 걸 아무도 몰랐다"** 이다.
BYTES="$(stat -c %s "${OUT}")"
if [ "${BYTES}" -lt 1024 ]; then
  rm -f "${OUT}"
  die 6 "[$JOB_NAME] FAIL 백업이 비어 있습니다 bytes=${BYTES}"
fi

if [ "$VERIFY" = "1" ]; then
  verify_backup "${OUT}" gz || die 6 "[$JOB_NAME] FAIL 복호화 검증 실패 — 패스프레이즈가 기존 백업과 다를 수 있습니다"
  log "[$JOB_NAME] VERIFY OK 복호화 + gzip 무결성 통과"
fi

prune_old 'b209-*.sql.gz.enc'
log "[db-backup] OK file=${OUT} bytes=${BYTES} retention=${RETENTION_DAYS}d"
