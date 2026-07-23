#!/usr/bin/env bash
# ============================================================================
# mysql-backup.sh — 도담 운영 DB(b209) 자동 백업 (S15P11B209-353)
#
# ⚠️ 백업 파일 = 아동 민감정보(그림·대화·리포트 원본 데이터) — 복사·전송 금지.
#    서버 밖으로 반출하지 않는다. 열람·복원은 Infra 담당만. (CLAUDE.md 9절 가드레일)
#
# 무엇을: dodam-mysql 컨테이너의 b209 DB를 mysqldump → gzip → AES-256 암호화하여
#         /var/backups/dodam/ 에 저장하고, 14일 초과분을 삭제한다.
# 왜:     k3s 컷오버(Day 6) 안전망 + 가드레일 9절(데이터 수명주기·복구력) 대응.
#         8.0→8.4 업그레이드가 비가역이었듯, 유일한 롤백 수단은 dump 복원뿐.
#
# 실행 주체: root (cron: 0 4 * * * — KST 새벽 4시, docs/인프라/DB백업-복원.md 참조)
# reason: 패스프레이즈 파일이 root:root 600이라 root만 읽을 수 있게 하여
#         일반 계정 탈취 시에도 백업 복호화가 불가능하도록 함.
#
# 종료 코드 (cron 메일/후속 알림 연동 대비 — 실패 지점을 코드로 구분):
#   0 성공 / 2 root 아님 / 3 패스프레이즈 파일 문제 / 4 백업 디렉토리 문제
#   5 컨테이너 미기동 / 6 덤프·암호화 파이프라인 실패
# ============================================================================
set -euo pipefail

# ── 설정 (값 변경 시 docs/인프라/DB백업-복원.md 도 함께 갱신) ────────────────
CONTAINER="dodam-mysql"                     # 대상 MySQL 컨테이너
DB_NAME="b209"                              # 백업 대상 DB
BACKUP_DIR="/var/backups/dodam"             # 백업 저장 위치 (root 700)
PASS_FILE="/etc/dodam/backup-passphrase"    # 암호화 패스프레이즈 (root 600, git 외부)
RETENTION_DAYS=14                           # 보관 기간 — 초과분 삭제
                                            # reason: 가드레일 9절 "보관 기간 경과 시 자동 삭제"
                                            #         + 디스크 보호. 2주면 주간 릴리즈 2회분 복원 가능.

STAMP="$(date +%F-%H%M)"                    # 예: 2026-07-23-0400
OUT="${BACKUP_DIR}/${DB_NAME}-${STAMP}.sql.gz.enc"
SECONDS=0                                   # 소요 시간 측정 (bash 내장)

# ── 실패 시 정리 + 한 줄 로그 ────────────────────────────────────────────────
# reason: cron은 stdout/stderr를 메일로 보내므로, 성공/실패를 "한 줄"로 남겨
#         후속 알림(MM 웹훅 등) 연동 시 그대로 파싱할 수 있게 한다.
#         실패한 부분 파일(.part)은 반드시 지운다 — 깨진 백업이 정상 백업으로 오인되면
#         복구 시나리오 전체가 무너지기 때문.
cleanup_on_fail() {
  local code=$?
  rm -f "${OUT}.part" 2>/dev/null || true
  echo "[mysql-backup] FAIL db=${DB_NAME} exit=${code} elapsed=${SECONDS}s (부분 파일 정리 완료)"
  exit "${code}"
}
trap cleanup_on_fail ERR

# ── 사전 검증 ────────────────────────────────────────────────────────────────
# 1) root 확인 — 패스프레이즈(600)·백업 디렉토리(700)가 root 전용이므로
if [[ ${EUID} -ne 0 ]]; then
  echo "[mysql-backup] FAIL: root로 실행해야 합니다 (패스프레이즈·백업 디렉토리가 root 전용). sudo 또는 root cron 사용." >&2
  exit 2
fi

# 2) 패스프레이즈 파일 — 존재 + root 소유 + 권한 600 검증. 없으면 명확한 에러로 중단.
# reason: 파일이 없거나 권한이 느슨하면 "암호화가 무의미한 백업"이 생기므로 진행 자체를 막는다.
if [[ ! -f "${PASS_FILE}" ]]; then
  echo "[mysql-backup] FAIL: 패스프레이즈 파일이 없습니다: ${PASS_FILE}" >&2
  echo "  생성 방법: docs/인프라/DB백업-복원.md '사전 준비' 참조 (openssl rand -base64 32 > ${PASS_FILE})" >&2
  exit 3
fi
PASS_STAT="$(stat -c '%u %a' "${PASS_FILE}")"
if [[ "${PASS_STAT}" != "0 600" ]]; then
  echo "[mysql-backup] FAIL: 패스프레이즈 파일 권한 오류 (uid/mode=${PASS_STAT}, 요구: root 소유 + 600)" >&2
  echo "  조치: chown root:root ${PASS_FILE} && chmod 600 ${PASS_FILE}" >&2
  exit 3
fi

# 3) 백업 디렉토리 — 존재 + 권한 700 검증
# reason: 아동 민감정보 백업이므로 root 외에는 목록조차 볼 수 없어야 한다.
if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "[mysql-backup] FAIL: 백업 디렉토리가 없습니다: ${BACKUP_DIR}" >&2
  echo "  생성 방법: install -d -m 700 -o root -g root ${BACKUP_DIR}" >&2
  exit 4
fi
DIR_STAT="$(stat -c '%u %a' "${BACKUP_DIR}")"
if [[ "${DIR_STAT}" != "0 700" ]]; then
  echo "[mysql-backup] FAIL: 백업 디렉토리 권한 오류 (uid/mode=${DIR_STAT}, 요구: root 소유 + 700)" >&2
  echo "  조치: chown root:root ${BACKUP_DIR} && chmod 700 ${BACKUP_DIR}" >&2
  exit 4
fi

# 4) 컨테이너 기동 확인 — 죽어 있으면 덤프 자체가 불가능하므로 먼저 명확히 알린다
if ! docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true; then
  echo "[mysql-backup] FAIL: 컨테이너 ${CONTAINER} 가 실행 중이 아닙니다" >&2
  exit 5
fi

# ── 백업 본체: mysqldump → gzip → AES-256-CBC 암호화 ────────────────────────
umask 077   # reason: 생성되는 백업 파일을 root 전용(600)으로 — 민감정보 접근 최소화

# mysqldump 옵션 reason (8.4 업그레이드 전 수동 백업 전례와 동일 방식):
#   MYSQL_PWD를 컨테이너 안 env에서 재사용     → 스크립트·프로세스 목록에 비밀번호 비노출
#   --single-transaction → InnoDB를 잠금 없이 일관된 스냅샷으로 덤프(운영 중 무중단)
#   --routines --triggers → 저장 프로시저·트리거까지 포함(스키마 완전 복원)
#   --databases b209     → CREATE DATABASE/USE 포함 → 빈 서버에도 복원 가능
# openssl 옵션 reason:
#   -pbkdf2              → 구식 키 유도(EVP_BytesToKey) 대신 표준 PBKDF2 사용
#   -pass file:...       → 패스프레이즈를 인자/env에 노출하지 않고 root 전용 파일에서 읽음
# ".part → mv" reason: 쓰다 만 파일이 정상 백업으로 보이지 않게 원자적으로 완성.
# if ! 로 감싼 reason: 파이프라인이 실패하면 set -o pipefail 이 "실패한 명령의 코드"를
#   그대로 전파해 문서의 종료코드 표(2~6)와 어긋난다(safety-review R-353-1).
#   조건문 안에서는 ERR trap·set -e가 발동하지 않으므로 정리·로그·정규화(6)를 직접 수행.
# openssl -md sha256 -iter 200000 reason: 버전 기본값 의존 금지 — 몇 년 뒤 openssl이
#   기본 해시/반복수를 바꿔도 복원(restore.sh의 동일 파라미터)이 깨지지 않게 명시 고정(R-353-2).
if ! docker exec "${CONTAINER}" sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --routines --triggers --databases '"${DB_NAME}" \
  | gzip \
  | openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -out "${OUT}.part"; then
  rm -f "${OUT}.part" 2>/dev/null || true
  echo "[mysql-backup] FAIL db=${DB_NAME} exit=6 elapsed=${SECONDS}s (dump/압축/암호화 파이프라인 실패 — 부분 파일 정리 완료)" >&2
  exit 6
fi
mv "${OUT}.part" "${OUT}"

# ── 보관 기간 초과분 삭제 (14일) ─────────────────────────────────────────────
# reason: -mtime +14 = 수정 후 14일 "초과"만 삭제. 이름 패턴을 좁혀 다른 파일 오삭제 방지.
find "${BACKUP_DIR}" -maxdepth 1 -type f -name "${DB_NAME}-*.sql.gz.enc" -mtime "+${RETENTION_DAYS}" -delete

# ── 결과 로그 한 줄 (민감정보 없음 — 파일명·크기·소요 시간만) ───────────────
SIZE="$(du -h "${OUT}" | cut -f1)"
echo "[mysql-backup] OK db=${DB_NAME} file=${OUT} size=${SIZE} elapsed=${SECONDS}s retention=${RETENTION_DAYS}d"
