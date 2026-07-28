#!/usr/bin/env bash
# ============================================================================
# sync-secrets.sh — .env → k8s Secret 동기화 (S15P11B209-357)
#
# 왜 kustomize 가 Secret 을 만들지 않는가 (이 스크립트가 존재하는 이유):
#   kustomize 가 Secret 을 관리하면, 값이 비어 있는 매니페스트를 실수로 apply 하는 순간
#   운영 비밀이 통째로 덮어써진다. 되돌릴 방법도 없다(k8s 는 이전 값을 보관하지 않는다).
#   그래서 Secret 은 kustomize 밖에 두고, 값이 있는 .env 를 들고 있을 때만 이 스크립트로 만든다.
#
# 무엇을 하나:
#   ① 필수 키가 있는지·비어 있지 않은지 검사 (compose 의 `${VAR:?}` fail-fast 대체)
#   ② 통과하면 Secret `dodam-secrets` 를 생성/갱신
#   ③ FCM 자격증명 파일이 있으면 Secret `dodam-fcm` 도 함께
#
# ⚠️ 값은 절대 출력하지 않는다. 키 "이름"만 찍는다(가드레일 9절).
# ⚠️ .env 자체는 커밋 금지. 이 스크립트도 .env 를 복사하거나 옮기지 않는다.
#
# 사용:
#   infra/scripts/sync-secrets.sh infra/.env
#   infra/scripts/sync-secrets.sh infra/.env --dry-run     # 검사만, 클러스터 미변경
#
# 종료 코드: 0 성공 / 2 인자·파일 / 3 필수 키 누락·형식 오류 / 4 kubectl 실패
# ============================================================================
set -euo pipefail

NAMESPACE="dodam"
SECRET_NAME="dodam-secrets"
FCM_SECRET_NAME="dodam-fcm"

# compose 에서 `${VAR:?}` 로 배포를 막던 것들 + 워크로드가 없으면 못 뜨는 것들.
# reason: 이 목록이 곧 "이게 없으면 서비스가 조용히 망가진다"의 정의다.
REQUIRED_KEYS=(
  JWT_SECRET
  REDIS_PASSWORD
  AI_INTERNAL_TOKEN
  MYSQL_ROOT_PASSWORD
  MYSQL_DATABASE
  MYSQL_USER
  MYSQL_PASSWORD
  MINIO_ROOT_USER
  MINIO_ROOT_PASSWORD
  MINIO_BE_USER
  MINIO_BE_PASSWORD
  GMS_KEY
  GMS_BASE_URL
)

ENV_FILE="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ -z "${ENV_FILE}" ]]; then
  echo "사용법: $0 <.env 경로> [--dry-run]" >&2
  exit 2
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[sync-secrets] FAIL: 파일이 없습니다: ${ENV_FILE}" >&2
  exit 2
fi

# ── ① 필수 키 검증 게이트 ────────────────────────────────────────────────────
# reason: 값이 "있다"와 "비어 있지 않다"는 다르다. KEY= 처럼 빈 값이면 파드는 뜨는데
#         기능만 조용히 죽는다 — 그게 compose 에서 `:?` 를 쓴 이유와 같다.
missing=()
empty=()
for key in "${REQUIRED_KEYS[@]}"; do
  line="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    missing+=("${key}")
    continue
  fi
  value="${line#*=}"
  # 앞뒤 따옴표·공백 제거 후 판정 (값 자체는 출력하지 않는다)
  value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"
  [[ -z "${value}" ]] && empty+=("${key}")
done

if ((${#missing[@]} > 0)) || ((${#empty[@]} > 0)); then
  echo "[sync-secrets] FAIL: 필수 키 문제 — Secret 을 만들지 않습니다." >&2
  ((${#missing[@]} > 0)) && echo "  누락: ${missing[*]}" >&2
  ((${#empty[@]} > 0))   && echo "  빈 값: ${empty[*]}" >&2
  echo "  (값은 출력하지 않습니다. ${ENV_FILE} 를 직접 확인하세요)" >&2
  exit 3
fi

# JWT_SECRET 길이 — 백엔드가 32바이트 미만이면 AUTH_CONFIGURATION_INVALID 로 거부한다.
#   배포는 성공했는데 인증 API 전체가 503 이 되는 상황을 여기서 막는다(D-190-1 재발 방지).
jwt_len="$(grep -E '^JWT_SECRET=' "${ENV_FILE}" | tail -n 1 | sed -e 's/^JWT_SECRET=//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" | tr -d '\n' | wc -c)"
if (( jwt_len < 32 )); then
  echo "[sync-secrets] FAIL: JWT_SECRET 이 ${jwt_len}바이트 — 32바이트 이상이어야 합니다." >&2
  echo "  생성 예: openssl rand -hex 32" >&2
  exit 3
fi

echo "[sync-secrets] 검증 통과: 필수 키 ${#REQUIRED_KEYS[@]}개 존재·비어 있지 않음, JWT_SECRET ${jwt_len}바이트"

if (( DRY_RUN == 1 )); then
  echo "[sync-secrets] --dry-run — 클러스터를 변경하지 않고 종료합니다."
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[sync-secrets] FAIL: kubectl 이 없습니다 (k3s 설치 전이거나 PATH 문제)." >&2
  exit 4
fi

# ── ② Secret 생성/갱신 ───────────────────────────────────────────────────────
# create --dry-run=client | apply — 이미 있으면 갱신, 없으면 생성(멱등).
#
# ⚠️ kubectl --from-env-file 의 파서는 compose 의 dotenv 파서와 다르다.
#    특히 `KEY=value # 주석` 같은 인라인 주석 처리 규칙이 같지 않다.
#    값에 `#` 나 따옴표가 들어간다면 적용 후 반드시 확인할 것:
#      kubectl -n dodam get secret dodam-secrets -o jsonpath='{.data.KEY}' | base64 -d | wc -c
#    (값 자체를 화면에 찍지 말고 길이만 볼 것)
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl create secret generic "${SECRET_NAME}" \
      --namespace "${NAMESPACE}" \
      --from-env-file="${ENV_FILE}" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
  echo "[sync-secrets] FAIL: Secret ${SECRET_NAME} 적용 실패" >&2
  exit 4
fi

count="$(kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data}' | tr ',' '\n' | wc -l)"
echo "[sync-secrets] OK: ${NAMESPACE}/${SECRET_NAME} 적용 완료 (키 ${count}개)"

# ── ③ FCM 자격증명 (선택) ────────────────────────────────────────────────────
# 파일이 없으면 조용히 건너뛴다 — 미발급 상태에서도 배포가 깨지지 않아야 한다.
# backend 의 secret 볼륨이 optional: true 라 Secret 이 없어도 파드는 뜬다(681 설계와 동일).
FCM_PATH="$(grep -E '^FCM_CREDENTIALS_HOST_PATH=' "${ENV_FILE}" | tail -n 1 | sed -e 's/^FCM_CREDENTIALS_HOST_PATH=//' -e 's/^"\(.*\)"$/\1/' || true)"
if [[ -n "${FCM_PATH}" && -s "${FCM_PATH}" ]]; then
  if kubectl create secret generic "${FCM_SECRET_NAME}" \
        --namespace "${NAMESPACE}" \
        --from-file=fcm-service-account.json="${FCM_PATH}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
    echo "[sync-secrets] OK: ${NAMESPACE}/${FCM_SECRET_NAME} 적용 완료"
  else
    echo "[sync-secrets] WARN: ${FCM_SECRET_NAME} 적용 실패 — 푸시만 비활성으로 동작합니다." >&2
  fi
else
  echo "[sync-secrets] SKIP: FCM 자격증명 없음 — 푸시는 비활성으로 뜹니다(정상)."
fi

echo "[sync-secrets] 다음: kubectl apply -k infra/k8s/overlays/staging"
