#!/usr/bin/env bash
# ============================================================================
# mysql-backup.sh — 도담 운영 DB(b209) 자동 백업 (S15P11B209-353)
#
# ⚠️ 백업 파일 = 아동 민감정보(그림·대화·리포트 원본 데이터) — 복사·전송 금지.
#    서버 밖으로 반출하지 않는다. 열람·복원은 Infra 담당만. (CLAUDE.md 9절 가드레일)
#
# 무엇을: k3s 의 mysql StatefulSet 에서 b209 DB를 mysqldump → gzip → AES-256 암호화하여
#         /var/backups/dodam/ 에 저장하고, 14일 초과분을 삭제한다.
# 왜:     k3s 컷오버(Day 6) 안전망 + 가드레일 9절(데이터 수명주기·복구력) 대응.
#         8.0→8.4 업그레이드가 비가역이었듯, 유일한 롤백 수단은 dump 복원뿐.
#
# ⚠️ 2026-07-30 (S15P11B209-732) — 대상을 Docker 컨테이너에서 k3s 파드로 옮겼다.
#    360 컷오버로 MySQL 이 k3s 로 넘어갔는데 이 스크립트는 `docker exec dodam-mysql` 을
#    보고 있었다. 옛 compose 컨테이너가 07-29 23:55 에 정지하면서 04:00 실행부터
#    exit 5 로 실패할 상태였다.
#
#    ★ dodam-mysql 컨테이너를 "다시 켜서" 고치면 안 된다. 그 컨테이너에는 컷오버
#      이전 데이터가 들어 있어, 암호화되고 크기도 정상이고 보관 정책도 도는데
#      내용만 틀린 백업이 매일 쌓인다. 복원해야 하는 날에야 안다.
#      백업 대상은 "지금 서비스가 쓰는 데이터"여야 한다.
#
# 실행 주체: root (cron: 0 4 * * * — KST 새벽 4시, docs/인프라/DB백업-복원.md 참조)
# reason: 패스프레이즈 파일이 root:root 600이라 root만 읽을 수 있게 하여
#         일반 계정 탈취 시에도 백업 복호화가 불가능하도록 함.
#         root 는 /etc/rancher/k3s/k3s.yaml 도 읽을 수 있어 kubectl 접근에 추가 설정이 없다.
#
# 종료 코드 (cron 메일/후속 알림 연동 대비 — 실패 지점을 코드로 구분):
#   0 성공 / 2 root 아님 / 3 패스프레이즈 파일 문제 / 4 백업 디렉토리 문제
#   5 MySQL 파드 미준비(또는 클러스터 접근 불가) / 6 덤프·암호화 파이프라인 실패
# ============================================================================
set -euo pipefail

# ── 설정 (값 변경 시 docs/인프라/DB백업-복원.md 도 함께 갱신) ────────────────
NAMESPACE="dodam"                           # k3s 네임스페이스
WORKLOAD="statefulset/mysql"                # 대상 MySQL 워크로드 (파드명 mysql-0 은 직접 쓰지 않는다 —
                                            #   파드가 재생성돼도 이름이 안 바뀌지만, 워크로드로 지정하면
                                            #   kubectl 이 알아서 준비된 파드를 고른다)
# cron 의 PATH 는 최소(/usr/bin:/bin)라 /usr/local/bin 이 없다. 절대경로로 고정한다.
#   이걸 빠뜨리면 "kubectl: command not found" 로 exit 127 이 나고, 종료코드 표(2~6)와 어긋난다.
KUBECTL="${KUBECTL:-/usr/local/bin/kubectl}"
# root cron 에는 KUBECONFIG 가 없다. k3s 기본 경로를 명시한다(root 만 읽을 수 있는 600 파일).
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
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

# 4) 클러스터 접근 → MySQL 파드 준비 순으로 확인
# ★ 순서가 중요하다. "접근 가능한가"를 먼저 본다.
#   리소스 조회부터 하면 kubeconfig·권한 문제가 "MySQL 이 없다"로 잘못 보고된다
#   — 07-29 deployer kubeconfig 진단에서 실제로 겪은 오진(권한 거부를 SA 부재로 읽었다).
if [[ ! -x "${KUBECTL}" ]]; then
  echo "[mysql-backup] FAIL: kubectl 을 실행할 수 없습니다: ${KUBECTL}" >&2
  exit 5
fi
if ! "${KUBECTL}" get --raw /version >/dev/null 2>&1; then
  echo "[mysql-backup] FAIL: k3s API 에 접근할 수 없습니다 (KUBECONFIG=${KUBECONFIG})" >&2
  exit 5
fi
# readyReplicas 로 판정한다 — 파드가 Running 이어도 Ready 가 아니면 mysqld 는 아직
#   연결을 받지 않는다. "존재한다"와 "동작한다"는 다르다(이 저장소가 반복해 데인 지점).
READY="$("${KUBECTL}" -n "${NAMESPACE}" get "${WORKLOAD}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "[mysql-backup] FAIL: ${NAMESPACE}/${WORKLOAD} 에 준비된 파드가 없습니다 (readyReplicas=${READY:-0})" >&2
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
# kubectl exec reason:
#   -t(TTY)를 절대 붙이지 않는다 — TTY 를 붙이면 개행이 CRLF 로 변환돼 gzip 스트림이 깨진다.
#     화면에 찍는 명령이 아니라 바이너리를 파이프로 넘기는 명령이다.
#   -i(stdin)도 필요 없다 — 컨테이너로 넣어줄 입력이 없고, 받아오기만 한다.
#   MYSQL_ROOT_PASSWORD 는 파드 env 에 이미 있다(Secret 주입). 호스트로 꺼내지 않는다.
if ! "${KUBECTL}" -n "${NAMESPACE}" exec "${WORKLOAD}" -- sh -c \
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
