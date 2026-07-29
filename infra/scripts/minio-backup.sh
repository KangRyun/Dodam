#!/usr/bin/env bash
# ============================================================================
# minio-backup.sh — 도담 파일 스토리지(MinIO 버킷 dodam) 자동 백업 (S15P11B209-622)
#
# ⚠️ 백업 파일 = 아동 민감정보(그림·음성·리포트·동의 증빙) — 복사·전송 금지.
#    서버 밖으로 반출하지 않는다. 열람·복원은 Infra 담당(root)만. (CLAUDE.md 9절)
#
# 무엇을: 버킷 dodam 을 mc mirror 로 받아(단, 재생성 가능한 tts-cache/ 는 제외)
#         tar+gzip+AES-256 암호화하여 /var/backups/dodam/ 에 저장, 14일 초과분 삭제.
# 왜:     단일노드 MinIO 디스크 장애 = 파일 전체 유실 → 유일한 복구 수단이 이 백업.
#         (docs/database/저장소-아키텍처.md §2·§7 — mysql-backup.sh(353) 취급규정 재사용)
#
# tts-cache 제외 근거: TTS 캐시는 원문에서 언제든 재생성되는 파생물 → 백업 대상 아님(설계 §1).
# evidences 포함 근거: 동의 증빙은 법적 보존 대상 → 백업 필수(설계 §1·§8).
#
# 실행 주체: root (cron: 0 4 * * * 권장 — mysql 백업과 시차. docs/인프라/MinIO백업-복원.md)
# reason: 패스프레이즈·백업 디렉토리가 root 전용(600/700)이라 root만 읽고 쓸 수 있게 함.
#
# 종료 코드 (실패 지점 구분 — cron 메일/알림 연동 대비):
#   0 성공 / 2 root 아님 / 3 패스프레이즈 문제 / 4 백업 디렉토리 문제
#   5 minio 컨테이너 미기동 / 6 mirror·암호화 파이프라인 실패
# ============================================================================
set -euo pipefail

# ── 설정 (값 변경 시 docs/인프라/MinIO백업-복원.md 도 함께 갱신) ──────────────
NAMESPACE="dodam"                           # k3s 네임스페이스
WORKLOAD="statefulset/minio"                # 대상 MinIO 워크로드 (준비 확인·자격증명 조회용)
SERVICE="svc/minio"                         # port-forward 대상 Service (ClusterIP:9000)
MC_IMAGE="minio/mc:RELEASE.2025-04-16T18-13-26Z"  # mc CLI (latest 금지 — init 과 동일 태그)
BUCKET="dodam"                              # 백업 대상 버킷

# cron 의 PATH 는 최소(/usr/bin:/bin)라 /usr/local/bin 이 없다. 절대경로로 고정한다.
KUBECTL="${KUBECTL:-/usr/local/bin/kubectl}"
# root cron 에는 KUBECONFIG 가 없다. k3s 기본 경로를 명시한다(root 전용 600 파일).
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# ★ mc 를 어떻게 MinIO 에 닿게 하는가 (S15P11B209-732)
#   MinIO Service 는 ClusterIP 전용이라 호스트에서 직접 못 닿는다(NodePort·hostPort 없음).
#   그렇다고 노출을 상설로 열면 아동 이미지 저장소가 호스트 포트에 늘 떠 있게 된다.
#   → 백업이 도는 동안만 port-forward 로 루프백에 붙였다가 끝나면 닫는다.
#   mc 자체는 여전히 Docker 로 돌린다 — MinIO 이미지에는 mc 가 있지만 tar·gzip 이 없어
#   파드 안에서 묶어 내보낼 수가 없다(07-29 MinIO 이관 때 확인된 제약).
PF_PORT="${PF_PORT:-19000}"                 # 9000 대신 19000 — 상설 서비스 포트와 겹치지 않게
PF_PID=""
EXCLUDE="tts-cache/*"                       # 재생성 가능 파생물 → 백업 제외(설계 §1)
BACKUP_DIR="/var/backups/dodam"             # 백업 저장 위치 (root 700, mysql 과 공용)
PASS_FILE="/etc/dodam/backup-passphrase"    # 암호화 패스프레이즈 (root 600, mysql 과 공용)
RETENTION_DAYS=14                           # 보관 기간 — 초과분 삭제(가드레일 9절)

STAMP="$(date +%F-%H%M)"                     # 예: 2026-07-26-0400
OUT="${BACKUP_DIR}/minio-${STAMP}.tar.gz.enc"
STAGE="${BACKUP_DIR}/.minio-stage-${STAMP}" # mirror 임시 적재(암호화 전) — 끝나면 삭제
TMP_ENV=""                                  # mc 자격증명 전달용 임시 env 파일
SECONDS=0

# ── 실패/종료 시 정리 + 한 줄 로그 ───────────────────────────────────────────
# reason: 자격증명 임시파일·부분 백업·mirror 스테이지는 어떤 경로로 끝나든 반드시 지운다.
#         깨진 부분 백업(.part)이 정상으로 오인되면 복구 시나리오가 무너진다.
cleanup() {
  local code=$?
  # port-forward 는 백그라운드 프로세스라 스크립트가 어떻게 끝나든 반드시 죽인다.
  #   남으면 다음 실행이 같은 포트를 못 잡고, 아동 이미지 저장소가 루프백에 계속 열려 있게 된다.
  [[ -n "${PF_PID}" ]] && kill "${PF_PID}" 2>/dev/null || true
  [[ -n "${TMP_ENV}" ]] && rm -f "${TMP_ENV}" 2>/dev/null || true
  rm -rf "${STAGE}" 2>/dev/null || true
  rm -f "${OUT}.part" 2>/dev/null || true
  if [[ ${code} -ne 0 ]]; then
    echo "[minio-backup] FAIL bucket=${BUCKET} exit=${code} elapsed=${SECONDS}s (임시파일 정리 완료)" >&2
  fi
  exit "${code}"
}
trap cleanup EXIT

# ── 사전 검증 ────────────────────────────────────────────────────────────────
# 1) root 확인 — 패스프레이즈(600)·백업 디렉토리(700)가 root 전용
if [[ ${EUID} -ne 0 ]]; then
  echo "[minio-backup] FAIL: root로 실행해야 합니다 (패스프레이즈·백업 디렉토리 root 전용). sudo/root cron." >&2
  exit 2
fi

# 2) 패스프레이즈 — 존재 + root 소유 + 600 (mysql 백업과 동일 파일 재사용)
if [[ ! -f "${PASS_FILE}" ]]; then
  echo "[minio-backup] FAIL: 패스프레이즈 파일이 없습니다: ${PASS_FILE}" >&2
  echo "  생성: openssl rand -base64 32 > ${PASS_FILE} && chown root:root ${PASS_FILE} && chmod 600 ${PASS_FILE}" >&2
  exit 3
fi
if [[ "$(stat -c '%u %a' "${PASS_FILE}")" != "0 600" ]]; then
  echo "[minio-backup] FAIL: 패스프레이즈 권한 오류 (요구: root 소유 + 600)" >&2
  exit 3
fi

# 3) 백업 디렉토리 — 존재 + 700 (root 외 목록조차 불가 — 아동 민감정보)
if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "[minio-backup] FAIL: 백업 디렉토리가 없습니다: ${BACKUP_DIR}" >&2
  echo "  생성: install -d -m 700 -o root -g root ${BACKUP_DIR}" >&2
  exit 4
fi
if [[ "$(stat -c '%u %a' "${BACKUP_DIR}")" != "0 700" ]]; then
  echo "[minio-backup] FAIL: 백업 디렉토리 권한 오류 (요구: root 소유 + 700)" >&2
  exit 4
fi

# 4) 클러스터 접근 → MinIO 파드 준비 순으로 확인
# ★ 순서가 중요하다. 리소스 조회부터 하면 kubeconfig·권한 문제가 "MinIO 가 없다"로
#   잘못 보고된다 — 07-29 deployer kubeconfig 진단에서 실제로 겪은 오진.
if [[ ! -x "${KUBECTL}" ]]; then
  echo "[minio-backup] FAIL: kubectl 을 실행할 수 없습니다: ${KUBECTL}" >&2
  exit 5
fi
if ! "${KUBECTL}" get --raw /version >/dev/null 2>&1; then
  echo "[minio-backup] FAIL: k3s API 에 접근할 수 없습니다 (KUBECONFIG=${KUBECONFIG})" >&2
  exit 5
fi
READY="$("${KUBECTL}" -n "${NAMESPACE}" get "${WORKLOAD}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${READY:-0}" -lt 1 ]]; then
  echo "[minio-backup] FAIL: ${NAMESPACE}/${WORKLOAD} 에 준비된 파드가 없습니다 (readyReplicas=${READY:-0})" >&2
  exit 5
fi

# ── 백업 본체: mc mirror → tar+gzip → AES-256 암호화 ─────────────────────────
umask 077   # 생성 파일 root 전용(600)

# 자격증명은 실행 중 minio 컨테이너의 env(root 계정)에서 읽는다 — .env 파싱·평문 노출 회피.
#   reason: mysql-backup.sh 가 컨테이너 안 $MYSQL_ROOT_PASSWORD 를 쓰는 것과 동일 원칙.
MINIO_USER="$("${KUBECTL}" -n "${NAMESPACE}" exec "${WORKLOAD}" -- printenv MINIO_ROOT_USER)"
MINIO_PASS="$("${KUBECTL}" -n "${NAMESPACE}" exec "${WORKLOAD}" -- printenv MINIO_ROOT_PASSWORD)"

# mc 컨테이너에 자격증명을 argv 아닌 env-file 로 전달(프로세스 목록 비노출). 파일은 600·즉시 삭제.
#   alias set 은 URL 이 아닌 "분리 인자"로 넘겨 비밀번호 특수문자(@:/) 인코딩 문제를 원천 차단.
TMP_ENV="$(mktemp)"; chmod 600 "${TMP_ENV}"
{ printf 'MINIO_ROOT_USER=%s\n' "${MINIO_USER}"
  printf 'MINIO_ROOT_PASSWORD=%s\n' "${MINIO_PASS}"; } > "${TMP_ENV}"

install -d -m 700 "${STAGE}"

# ── MinIO 를 백업 동안만 루프백에 노출 ───────────────────────────────────────
"${KUBECTL}" -n "${NAMESPACE}" port-forward "${SERVICE}" "${PF_PORT}:9000" >/dev/null 2>&1 &
PF_PID=$!
# ★ 프로세스가 떴다고 포트가 열린 게 아니다. 실제로 응답할 때까지 기다린다.
#   "존재한다"와 "동작한다"를 따로 확인한다 — 이 저장소가 반복해서 데인 지점이다.
PF_OK=0
for _ in $(seq 1 30); do
  if curl -sf -m 2 "http://127.0.0.1:${PF_PORT}/minio/health/live" >/dev/null 2>&1; then
    PF_OK=1; break
  fi
  # 포워더가 이미 죽었으면 30초를 기다릴 이유가 없다(포트 충돌 등)
  kill -0 "${PF_PID}" 2>/dev/null || break
  sleep 1
done
if [[ "${PF_OK}" -ne 1 ]]; then
  echo "[minio-backup] FAIL: port-forward 로 MinIO(127.0.0.1:${PF_PORT}) 에 닿지 못했습니다" >&2
  exit 5
fi

# mc mirror: 버킷 dodam → 스테이지(빈 디렉토리). tts-cache 제외.
#   ⚠️ 첫 실행 검증(리눅스서 미검증): --exclude 패턴("tts-cache/*")이 실제로 해당 프리픽스를
#      건너뛰는지 · mc 이미지 태그 실존 여부. 최초 드릴에서 스테이지에 tts-cache 없음 확인할 것.
# --network host reason: port-forward 가 호스트 루프백에 붙어 있으므로 mc 컨테이너도
#   같은 네트워크 네임스페이스를 써야 127.0.0.1 이 "호스트의 127.0.0.1"이 된다.
#   기본 브리지 네트워크였다면 컨테이너의 127.0.0.1 은 자기 자신이라 닿지 않는다.
if ! docker run --rm --network host --env-file "${TMP_ENV}" \
      -v "${STAGE}:/backup" --entrypoint /bin/sh "${MC_IMAGE}" -c \
      'mc alias set local http://127.0.0.1:'"${PF_PORT}"' "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 \
        && mc mirror --quiet --overwrite local/'"${BUCKET}"' /backup --exclude "'"${EXCLUDE}"'"'; then
  echo "[minio-backup] FAIL bucket=${BUCKET} exit=6 elapsed=${SECONDS}s (mc mirror 실패)" >&2
  exit 6
fi

# ── 담긴 객체 수 확인 (S15P11B209-374) ───────────────────────────────────────
# reason: 크기만 남기면 "성공했지만 내용이 빈" 백업을 알아챌 수 없다.
#   2026-07-27·28 백업이 이틀 연속 `OK size=4.0K`(빈 tar) 로 성공 기록을 남겼는데,
#   당시 버킷이 비어 있었다는 사실을 아무도 몰랐다. 크기가 4.0K 로 "고정"이라
#   오히려 안정적으로 보였다. 개수를 함께 남기면 한눈에 드러난다.
OBJECTS="$(find "${STAGE}" -type f | wc -l)"
if [[ "${OBJECTS}" -eq 0 ]]; then
  # 백업 파일 자체는 정상 생성되므로 실패(exit≠0)로 다루지 않는다. 다만 조용히 넘기지 않는다.
  #   버킷이 실제로 비어 있는 초기 구축 시점에는 정상이지만, 운영 중이라면 이상 신호다.
  echo "[minio-backup] WARN bucket=${BUCKET} objects=0 — 내용이 빈 백업입니다." \
       "버킷이 실제로 비었는지, 자격증명·프리픽스가 어긋나지 않았는지 확인하세요." >&2
fi

# tar → gzip → AES-256-CBC 암호화 (mysql-backup.sh 와 동일 파라미터로 복원 호환 고정)
#   openssl -pbkdf2 -md sha256 -iter 200000: 버전 기본값 의존 금지(복원 파라미터와 반드시 일치).
if ! tar -C "${STAGE}" -czf - . \
     | openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -out "${OUT}.part"; then
  echo "[minio-backup] FAIL bucket=${BUCKET} exit=6 elapsed=${SECONDS}s (tar/암호화 파이프라인 실패)" >&2
  exit 6
fi
mv "${OUT}.part" "${OUT}"
rm -rf "${STAGE}"

# ── 보관 기간 초과분 삭제 (14일) ─────────────────────────────────────────────
# reason: -mtime +14 = 14일 초과만. 이름 패턴을 좁혀 mysql 백업 등 타 파일 오삭제 방지.
find "${BACKUP_DIR}" -maxdepth 1 -type f -name "minio-*.tar.gz.enc" -mtime "+${RETENTION_DAYS}" -delete

# ── 결과 로그 한 줄 (민감정보 없음 — 파일명·크기·소요만) ──────────────────────
SIZE="$(du -h "${OUT}" | cut -f1)"
echo "[minio-backup] OK bucket=${BUCKET} file=${OUT} objects=${OBJECTS} size=${SIZE} elapsed=${SECONDS}s retention=${RETENTION_DAYS}d exclude=${EXCLUDE}"
