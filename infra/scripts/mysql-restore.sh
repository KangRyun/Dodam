#!/usr/bin/env bash
# ============================================================================
# mysql-restore.sh — 도담 운영 DB(b209) 백업 복원 (S15P11B209-353)
#
# ⚠️ 백업 파일 = 아동 민감정보 — 복사·전송 금지. 복원은 Infra 담당(root)만 수행.
# ⚠️ 복원은 대상 DB(b209)를 덤프 시점 상태로 "덮어쓴다" — 이후 데이터는 사라진다.
#    그래서 실행 전 확인 프롬프트를 강제하고, --dry-run으로 먼저 검증하게 한다.
#
# 사용법:
#   mysql-restore.sh [--dry-run] <백업파일(.sql.gz.enc)> [컨테이너명(기본: dodam-mysql)]
#
#   --dry-run : 복호화 + gzip 무결성 검증만 수행(DB는 건드리지 않음).
#               reason: 월 1회 백업 드릴에서 "이 백업이 정말 복원 가능한 파일인지"를
#               운영 DB에 손대지 않고 확인하기 위함 (docs/인프라/DB백업-복원.md 참조).
#
# 종료 코드: 0 성공 / 2 root 아님·인자 오류 / 3 패스프레이즈 파일 문제
#            4 백업 파일 문제 / 5 컨테이너 미기동 / 6 복호화·복원 파이프라인 실패
# ============================================================================
set -euo pipefail

PASS_FILE="/etc/dodam/backup-passphrase"    # 백업 때와 동일한 패스프레이즈 (root 600)

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi
if [[ $# -lt 1 ]]; then
  echo "사용법: $0 [--dry-run] <백업파일(.sql.gz.enc)> [워크로드(기본: statefulset/mysql)]" >&2
  exit 2
fi
BACKUP_FILE="$1"
# S15P11B209-732 — 대상이 Docker 컨테이너에서 k3s 워크로드로 바뀌었다.
#   staging 복원 드릴을 하려면 두 번째 인자로 다른 워크로드를 넘긴다.
WORKLOAD="${2:-statefulset/mysql}"
NAMESPACE="${NAMESPACE:-dodam}"
KUBECTL="${KUBECTL:-/usr/local/bin/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# ── 사전 검증 ────────────────────────────────────────────────────────────────
# 1) root 확인 — 패스프레이즈(root 600)·백업 파일(root 600)을 읽어야 하므로
if [[ ${EUID} -ne 0 ]]; then
  echo "[mysql-restore] FAIL: root로 실행해야 합니다 (패스프레이즈·백업 파일이 root 전용)." >&2
  exit 2
fi

# 2) 패스프레이즈 파일 — 백업 스크립트와 동일 기준(존재 + root 소유 + 600)
if [[ ! -f "${PASS_FILE}" ]]; then
  echo "[mysql-restore] FAIL: 패스프레이즈 파일이 없습니다: ${PASS_FILE}" >&2
  exit 3
fi
PASS_STAT="$(stat -c '%u %a' "${PASS_FILE}")"
if [[ "${PASS_STAT}" != "0 600" ]]; then
  echo "[mysql-restore] FAIL: 패스프레이즈 파일 권한 오류 (uid/mode=${PASS_STAT}, 요구: root 소유 + 600)" >&2
  exit 3
fi

# 3) 백업 파일 존재 확인
if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "[mysql-restore] FAIL: 백업 파일이 없습니다: ${BACKUP_FILE}" >&2
  exit 4
fi

# ── --dry-run: 복호화 + gzip 무결성 검증만 ──────────────────────────────────
# reason: openssl 복호화가 성공하고 gzip 스트림이 끝까지 온전하면
#         "패스프레이즈가 맞고 파일이 손상되지 않았다"는 것까지 보장된다.
#         DB에는 일절 접근하지 않으므로 운영 중에도 안전하게 돌릴 수 있다.
if [[ ${DRY_RUN} -eq 1 ]]; then
  if openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -in "${BACKUP_FILE}" | gzip -t; then
    echo "[mysql-restore] DRY-RUN OK file=${BACKUP_FILE} (복호화·gzip 무결성 검증 통과 — DB 미접근)"
    exit 0
  else
    echo "[mysql-restore] DRY-RUN FAIL file=${BACKUP_FILE} (복호화 또는 gzip 검증 실패 — 패스프레이즈/파일 손상 확인)" >&2
    exit 6
  fi
fi

# ── 실제 복원 경로: 파드 준비 확인 → 사용자 확인 → 복원 ────────────────────
# 4) 클러스터 접근 → 대상 워크로드 준비 확인
#    접근성을 먼저 본다 — 리소스 조회부터 하면 kubeconfig 문제가 "대상이 없다"로 잘못 보인다.
if [[ ! -x "${KUBECTL}" ]]; then
  echo "[mysql-restore] FAIL: kubectl 을 실행할 수 없습니다: ${KUBECTL}" >&2
  exit 5
fi
if ! "${KUBECTL}" get --raw /version >/dev/null 2>&1; then
  echo "[mysql-restore] FAIL: k3s API 에 접근할 수 없습니다 (KUBECONFIG=${KUBECONFIG})" >&2
  exit 5
fi
READY="$("${KUBECTL}" -n "${NAMESPACE}" get "${WORKLOAD}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "[mysql-restore] FAIL: ${NAMESPACE}/${WORKLOAD} 에 준비된 파드가 없습니다 (readyReplicas=${READY:-0})" >&2
  exit 5
fi

# 5) 확인 프롬프트 — 대상 이름을 그대로 입력해야만 진행
# reason: 복원은 되돌릴 수 없는 덮어쓰기다. y/n 한 글자보다 "대상 이름을 직접 타이핑"이
#         오타·습관성 엔터로 인한 사고를 막는 데 훨씬 안전하다 (대상 오인 방지 겸용).
echo "⚠️  ${NAMESPACE}/${WORKLOAD} 의 DB를 아래 백업으로 덮어씁니다. 이후 데이터는 사라집니다."
echo "    백업 파일: ${BACKUP_FILE}"
printf '정말 복원하려면 워크로드명(%s)을 입력하세요: ' "${WORKLOAD}"
read -r CONFIRM
if [[ "${CONFIRM}" != "${WORKLOAD}" ]]; then
  echo "[mysql-restore] 취소됨 (입력 불일치)"
  exit 2
fi

# 6) 복원 본체: 복호화 → gunzip → mysql
# reason: 덤프가 --databases b209 로 만들어져 CREATE DATABASE/USE가 포함돼 있으므로
#         DB명을 지정하지 않고 mysql 클라이언트에 그대로 흘려보낸다.
#         MYSQL_PWD는 컨테이너 안 env 재사용 — 비밀번호가 스크립트·프로세스 목록에 안 남음.
SECONDS=0
# ★ -i 는 반드시 있어야 한다. 여기서는 덤프를 컨테이너 stdin 으로 "밀어넣는다".
#   백업 쪽(kubectl exec)은 받아오기만 해서 -i 가 필요 없지만, 복원은 반대 방향이다.
#   빠뜨리면 stdin 이 전달되지 않아 아무것도 복원하지 않고 조용히 성공한다.
#   -t 는 절대 붙이지 않는다 — TTY 가 개행을 CRLF 로 바꿔 SQL 스트림을 망가뜨린다.
openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -in "${BACKUP_FILE}" \
  | gunzip \
  | "${KUBECTL}" -n "${NAMESPACE}" exec -i "${WORKLOAD}" -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'

echo "[mysql-restore] OK workload=${NAMESPACE}/${WORKLOAD} file=${BACKUP_FILE} elapsed=${SECONDS}s"
echo "  후속 확인 제안: ${KUBECTL} -n ${NAMESPACE} exec ${WORKLOAD} -- sh -c 'MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" mysql -uroot -e \"SHOW TABLES IN b209;\"'"
