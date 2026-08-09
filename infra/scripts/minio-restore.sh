#!/usr/bin/env bash
# ============================================================================
# minio-restore.sh — 도담 파일 스토리지(MinIO 버킷 dodam) 백업 복원 (S15P11B209-622)
#
# ⚠️ 백업 파일 = 아동 민감정보 — 복사·전송 금지. 복원은 Infra 담당(root)만.
# ⚠️ 복원은 백업에 담긴 파일을 버킷 dodam 에 "되돌려 덮어쓴다".
#    - 되돌리는 대상: images/ audio/ reports/ evidences/  (백업에 포함된 것)
#    - tts-cache/ 는 백업에서 제외됐으므로 건드리지 않는다(원문에서 재생성됨).
#    - 백업 이후 새로 추가된 객체는 지우지 않는다(mirror --remove 미사용 — 비파괴).
#    그래서 실행 전 확인 프롬프트를 강제하고, --dry-run 으로 먼저 검증하게 한다.
#
# 사용법:
#   minio-restore.sh [--dry-run] <백업파일(minio-*.tar.gz.enc)>
#   --dry-run : 복호화 + tar 무결성 검증 + 담긴 프리픽스 목록만(버킷 미변경).
#               reason: 월 1회 백업 드릴에서 "이 백업이 복원 가능한 파일인지"를
#               운영 버킷에 손대지 않고 확인 (docs/인프라/MinIO백업-복원.md).
#
# 종료 코드: 0 성공 / 2 root 아님·인자 오류 / 3 패스프레이즈 문제
#            4 백업 파일 문제 / 5 minio 컨테이너 미기동 / 6 복호화·복원 파이프라인 실패
# ============================================================================
set -euo pipefail

# S15P11B209-732 — 대상이 Docker 컨테이너에서 k3s 워크로드로 바뀌었다.
#   MinIO Service 는 ClusterIP 전용이라 호스트에서 직접 못 닿는다.
#   복원이 도는 동안만 port-forward 로 루프백에 붙였다가 닫는다(minio-backup.sh 와 동일 방식).
NAMESPACE="dodam"
WORKLOAD="statefulset/minio"
SERVICE="svc/minio"
MC_IMAGE="minio/mc:RELEASE.2025-04-16T18-13-26Z"
BUCKET="dodam"
PASS_FILE="/etc/dodam/backup-passphrase"    # 백업 때와 동일한 패스프레이즈 (root 600)
KUBECTL="${KUBECTL:-/usr/local/bin/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
PF_PORT="${PF_PORT:-19001}"                 # 백업(19000)과 다른 포트 — 동시 실행 시 충돌 방지
PF_PID=""
STAGE=""; TMP_ENV=""

cleanup() {
  local code=$?
  [[ -n "${PF_PID}"  ]] && kill "${PF_PID}"    2>/dev/null || true
  [[ -n "${STAGE}"   ]] && rm -rf "${STAGE}"   2>/dev/null || true
  [[ -n "${TMP_ENV}" ]] && rm -f  "${TMP_ENV}" 2>/dev/null || true
  exit "${code}"
}
trap cleanup EXIT

# ── 인자 파싱 ────────────────────────────────────────────────────────────────
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
if [[ $# -lt 1 ]]; then
  echo "사용법: $0 [--dry-run] <백업파일(minio-*.tar.gz.enc)>" >&2
  exit 2
fi
BACKUP_FILE="$1"

# ── 사전 검증 ────────────────────────────────────────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
  echo "[minio-restore] FAIL: root로 실행해야 합니다." >&2
  exit 2
fi
if [[ ! -f "${PASS_FILE}" || "$(stat -c '%u %a' "${PASS_FILE}")" != "0 600" ]]; then
  echo "[minio-restore] FAIL: 패스프레이즈 파일 없음/권한오류: ${PASS_FILE} (root 600 필요)" >&2
  exit 3
fi
if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "[minio-restore] FAIL: 백업 파일이 없습니다: ${BACKUP_FILE}" >&2
  exit 4
fi

umask 077
STAGE="$(mktemp -d)"

# ── 복호화 + 해제 (dry-run 은 여기까지) ──────────────────────────────────────
# reason: 복호화·gzip·tar 무결성이 깨졌는지 여기서 먼저 걸러낸다(운영 버킷 손대기 전).
if ! openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -in "${BACKUP_FILE}" \
     | tar -C "${STAGE}" -xzf -; then
  echo "[minio-restore] FAIL: 복호화/해제 실패 (패스프레이즈 불일치 또는 파일 손상)" >&2
  exit 6
fi

if [[ ${DRY_RUN} -eq 1 ]]; then
  # 프리픽스 목록만으로는 "빈 백업"을 구분하지 못한다 — 프리픽스별 객체 수를 함께 낸다.
  #   reason: 복원 드릴의 목적은 "복호화가 되는가"가 아니라 "이 백업으로 되살릴 수 있는가"다.
  #   담긴 개수를 DB(drawing_assets)나 현재 버킷과 대조해야 판정이 끝난다(S15P11B209-374).
  TOTAL="$(find "${STAGE}" -type f | wc -l)"
  echo "[minio-restore] DRY-RUN OK: 복호화·해제 정상. objects=${TOTAL}"
  echo "  프리픽스별 객체 수:"
  find "${STAGE}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort | while read -r prefix; do
    printf '  - %-14s %s\n' "${prefix}/" "$(find "${STAGE}/${prefix}" -type f | wc -l)"
  done
  if [[ "${TOTAL}" -eq 0 ]]; then
    echo "[minio-restore] WARN: 담긴 객체가 없습니다 — 이 백업으로는 아무것도 복원되지 않습니다." >&2
  fi
  echo "  대조: 현재 버킷·DB 객체 수와 비교해 누락이 없는지 확인하세요."
  echo "  (실복원: --dry-run 없이 재실행)"
  exit 0
fi

# ── 실복원: 확인 프롬프트 → mc mirror(스테이지 → 버킷, 비파괴 overwrite) ──────
if [[ ! -x "${KUBECTL}" ]]; then
  echo "[minio-restore] FAIL: kubectl 을 실행할 수 없습니다: ${KUBECTL}" >&2
  exit 5
fi
if ! "${KUBECTL}" get --raw /version >/dev/null 2>&1; then
  echo "[minio-restore] FAIL: k3s API 에 접근할 수 없습니다 (KUBECONFIG=${KUBECONFIG})" >&2
  exit 5
fi
READY="$("${KUBECTL}" -n "${NAMESPACE}" get "${WORKLOAD}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "[minio-restore] FAIL: ${NAMESPACE}/${WORKLOAD} 에 준비된 파드가 없습니다 (readyReplicas=${READY:-0})" >&2
  exit 5
fi
echo "⚠️  버킷 '${BUCKET}' 에 백업 파일을 되돌려 덮어씁니다(비파괴 — 신규 객체·tts-cache 유지)."
read -r -p "정말 진행하려면 'RESTORE' 입력: " CONFIRM
if [[ "${CONFIRM}" != "RESTORE" ]]; then
  echo "[minio-restore] 취소됨 (확인 문자열 불일치)"
  exit 0
fi

MINIO_USER="$("${KUBECTL}" -n "${NAMESPACE}" exec "${WORKLOAD}" -- printenv MINIO_ROOT_USER)"
MINIO_PASS="$("${KUBECTL}" -n "${NAMESPACE}" exec "${WORKLOAD}" -- printenv MINIO_ROOT_PASSWORD)"
TMP_ENV="$(mktemp)"; chmod 600 "${TMP_ENV}"
{ printf 'MINIO_ROOT_USER=%s\n' "${MINIO_USER}"
  printf 'MINIO_ROOT_PASSWORD=%s\n' "${MINIO_PASS}"; } > "${TMP_ENV}"

# 복원 동안만 MinIO 를 루프백에 노출한다.
"${KUBECTL}" -n "${NAMESPACE}" port-forward "${SERVICE}" "${PF_PORT}:9000" >/dev/null 2>&1 &
PF_PID=$!
PF_OK=0
for _ in $(seq 1 30); do
  if curl -sf -m 2 "http://127.0.0.1:${PF_PORT}/minio/health/live" >/dev/null 2>&1; then PF_OK=1; break; fi
  kill -0 "${PF_PID}" 2>/dev/null || break
  sleep 1
done
if [[ "${PF_OK}" -ne 1 ]]; then
  echo "[minio-restore] FAIL: port-forward 로 MinIO(127.0.0.1:${PF_PORT}) 에 닿지 못했습니다" >&2
  exit 5
fi

# --network host: port-forward 가 호스트 루프백에 있으므로 mc 도 같은 네임스페이스를 써야 한다.
if ! docker run --rm --network host --env-file "${TMP_ENV}" \
      -v "${STAGE}:/restore:ro" --entrypoint /bin/sh "${MC_IMAGE}" -c \
      'mc alias set local http://127.0.0.1:'"${PF_PORT}"' "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 \
        && mc mirror --quiet --overwrite /restore local/'"${BUCKET}"; then
  echo "[minio-restore] FAIL: mc mirror 복원 실패" >&2
  exit 6
fi

echo "[minio-restore] OK: '${BACKUP_FILE}' → 버킷 ${BUCKET} 복원 완료(비파괴 overwrite)."
