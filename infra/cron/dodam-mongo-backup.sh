#!/usr/bin/env bash
# ============================================================================
# dodam-mongo-backup.sh — MongoDB 백업 (컷백/compose 판)
#
# 원본: infra/k8s/base/cronjobs.yaml 의 CronJob `mongo-backup`
#       (timeZone Asia/Seoul · schedule "30 4 * * *" · 보관 14일)
# 스케줄: KST 04:30 — MySQL(04:00)과 30분 띄운다. 동시 실행 시 I/O·메모리 경합.
#
# ⚠️ 이 백업에는 **아이 발화 원문·그리기 좌표**가 들어간다. 평문 덤프를 호스트에 남기지
#    않는 것이 이 스크립트의 설계 제약이다(가드레일 9절) — 아래 §덤프 위치 참조.
#
# 원본에서 **그대로 보존한 것**:
#   · 파일명   mongo-<STAMP>.tar.gz.enc,  STAMP = date +%F-%H%M (KST)
#   · 덤프     --authenticationDatabase admin (root 는 admin DB 에 있다 — 빠뜨리면
#              "인증 실패"가 아니라 "사용자 없음"으로 나와 원인을 헷갈린다)
#   · tar 레이아웃  -C <work> dump   (복원 절차를 한 벌로 유지)
#   · 암호화   openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000
#   · ★ 3분기 판정 (733 에서 정의):
#        collections == 0 → FAIL. DB 를 아예 읽지 못했다(DB명·자격증명·접속).
#        bytes      < 200 → FAIL. tar/암호화 파이프라인 자체가 망가졌다.
#        documents  == 0  → WARN(exit 0). DB 가 정말 비었다 — 유효한 백업이다.
#   · 보관     -mtime +14 -delete
#
# ── §덤프 위치: 컨테이너 안 /tmp → tar 를 stdout 으로 받아 호스트에서 암호화 ──────
#   원본은 파드 안 mktemp -d 에 덤프하고 같은 컨테이너에서 tar+암호화했다. compose 판도
#   같은 성질을 유지한다: 평문은 **컨테이너 안에서만** 존재하고, 호스트로는 이미 압축된
#   스트림이 파이프로만 흐른다(호스트 디스크에 평문 덤프 파일이 생기지 않는다).
#   trap 이 어떤 경로로 끝나든 컨테이너 안 덤프를 지운다.
#
# ── 원본과 다르게 한 것 하나 ────────────────────────────────────────────────
#   mongodump 진행 로그를 컨테이너 안 파일이 아니라 **호스트 파일로 받아** 문서 수를 센다.
#   중첩 따옴표(sh -c 안의 sed/awk)를 없애기 위한 것이고, 세는 값과 판정은 원본과 같다.
#   로그에는 컬렉션 이름과 건수만 들어가며(아동 데이터 본문 아님) trap 이 지운다.
#
# 사용:
#   sudo /opt/dodam/cron/dodam-mongo-backup.sh [--verify]
# ============================================================================
set -euo pipefail

JOB_NAME="dodam-mongo-backup"
# shellcheck source=lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"

CONTAINER="${MONGO_CONTAINER:-dodam-mongodb}"
WORK_IN_CONTAINER="/tmp/dodam-mongo-backup"
VERIFY=0
[ "${1:-}" = "--verify" ] && VERIFY=1

backup_preamble "$CONTAINER"

STAMP="$(date +%F-%H%M)"
OUT="${BACKUP_DIR}/mongo-${STAMP}.tar.gz.enc"
LOG="$(mktemp /tmp/dodam-mongodump-log.XXXXXX)"

cleanup() {
  rm -f "${OUT}.part" "${LOG}"
  # 평문 덤프는 반드시 지운다 — 남으면 컨테이너 안에 아이 발화 원문이 무기한 방치된다.
  docker exec "$CONTAINER" sh -c "rm -rf ${WORK_IN_CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── 덤프 ────────────────────────────────────────────────────────────────────
# ⚠️ --password 가 컨테이너 프로세스의 argv 에 실린다. 원본 CronJob 도 동일하며,
#   mongodump 에는 MYSQL_PWD 같은 우회로가 없다. 노출 범위는 그 컨테이너 안 `ps` 이고,
#   실질 통제는 호스트 docker 접근 최소화다(compose 파일 redis 주석과 같은 결).
docker exec "$CONTAINER" sh -c "rm -rf ${WORK_IN_CONTAINER} && mkdir -p ${WORK_IN_CONTAINER}" \
  || die 6 "[$JOB_NAME] FAIL 작업 디렉터리 생성 실패"

docker exec "$CONTAINER" sh -c '
    mongodump --host 127.0.0.1 --port 27017 \
      --username "$MONGO_INITDB_ROOT_USERNAME" \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --db "$MONGO_INITDB_DATABASE" \
      --out '"${WORK_IN_CONTAINER}"'/dump' >"$LOG" 2>&1 \
  || { warn "[$JOB_NAME] mongodump 로그(마지막 20줄):"; tail -20 "$LOG" >&2 || true; die 6 "[$JOB_NAME] FAIL mongodump 실패"; }

# ── 관측값 수집 (판정 근거) ─────────────────────────────────────────────────
COLLECTIONS="$(docker exec "$CONTAINER" sh -c "find ${WORK_IN_CONTAINER}/dump -name '*.bson' | wc -l" | tr -d '[:space:]')"
# mongodump 의 "done dumping X (N documents)" 를 합산한다.
#   컬렉션 개수보다 문서 수가 실제 관측값이다 — 빈 DB 를 조용히 넘기지 않는 근거.
DOCUMENTS="$(sed -n 's/.*(\([0-9]\+\) document[s]*)$/\1/p' "$LOG" | awk '{s+=$1} END {print s+0}')"

# ── tar → 암호화 ────────────────────────────────────────────────────────────
# 레이아웃을 원본과 똑같이 맞춘다: 작업 디렉터리로 -C 해서 "dump" 를 묶는다.
docker exec "$CONTAINER" tar -czf - -C "${WORK_IN_CONTAINER}" dump \
  | encrypt_to "${OUT}.part" \
  || die 6 "[$JOB_NAME] FAIL tar·암호화 파이프라인 실패"
mv "${OUT}.part" "${OUT}"
BYTES="$(stat -c %s "${OUT}")"

# ── 판정 ────────────────────────────────────────────────────────────────────
if [ "${COLLECTIONS}" -eq 0 ]; then
  rm -f "${OUT}"
  die 6 "[mongo-backup] FAIL 컬렉션을 하나도 읽지 못했습니다 bytes=${BYTES} — DB명·자격증명·접속을 확인하세요(빈 DB 와는 다른 상황입니다)."
fi
if [ "${BYTES}" -lt 200 ]; then
  rm -f "${OUT}"
  die 6 "[mongo-backup] FAIL 산출물이 깨졌습니다 bytes=${BYTES} collections=${COLLECTIONS} — tar/암호화 파이프라인을 확인하세요."
fi

if [ "$VERIFY" = "1" ]; then
  verify_backup "${OUT}" tar || die 6 "[$JOB_NAME] FAIL 복호화 검증 실패 — 패스프레이즈가 기존 백업과 다를 수 있습니다"
  log "[$JOB_NAME] VERIFY OK 복호화 + tar 목록 조회 통과"
fi

prune_old 'mongo-*.tar.gz.enc'

if [ "${DOCUMENTS}" -eq 0 ]; then
  # ★ 실패가 아니다. 앱이 아직 쓰지 않은 DB 의 빈 백업은 복원하면 빈 DB 가 나오는 유효한 백업이다.
  #   다만 조용히 넘기지 않는다 — 374 의 교훈은 "비었다"가 아니라 "몰랐다"였다.
  warn "[mongo-backup] WARN file=${OUT} bytes=${BYTES} collections=${COLLECTIONS} documents=0 retention=${RETENTION_DAYS}d — DB 가 비어 있습니다. 앱이 Mongo 에 쓰고 있는지 확인하세요(365)."
else
  log "[mongo-backup] OK file=${OUT} bytes=${BYTES} collections=${COLLECTIONS} documents=${DOCUMENTS} retention=${RETENTION_DAYS}d"
fi
