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
#   ①-b 값에 선두/꼬리 공백이 붙은 키를 검출 (S15P11B209-730)
#   ② 통과하면 Secret `dodam-secrets` 를 생성/갱신
#   ③ FCM 자격증명 파일이 있으면 Secret `dodam-fcm` 도 함께
#
# ⚠️ 값은 절대 출력하지 않는다. 키 "이름"과 길이만 찍는다(가드레일 9절).
# ⚠️ .env 자체는 커밋 금지. 이 스크립트도 .env 를 복사하거나 옮기지 않는다.
#
# 사용:
#   infra/scripts/sync-secrets.sh infra/.env
#   infra/scripts/sync-secrets.sh infra/.env --dry-run     # 검사만, 클러스터 미변경
#   infra/scripts/sync-secrets.sh infra/.env --strict      # 알려진 오염도 실패 처리
#
# 종료 코드: 0 성공 / 2 인자·파일 / 3 필수 키 누락·형식 오류·미확인 오염 / 4 kubectl 실패
#
# ── ①-b 가 왜 생겼나 (S15P11B209-730) ──────────────────────────────────────
#   2026-07-30 새벽 카카오·구글 OAuth 가 전면 실패했다. 원인은 .env 값 뒤의 공백·탭이었다.
#   `kubectl create secret --from-env-file` 은 `=` 뒤를 한 글자도 건드리지 않고 그대로 싣고,
#   그 값이 파드 env 까지 도달해 `String.equals` 비교에서 깨졌다.
#
#   같은 날 오전에는 같은 원인으로 GMS(LLM·STT·TTS) 호출이 전부 502 였다.
#   `GMS_KEY` 는 HTTP 헤더로 가서 `Illegal header value`, `GMS_BASE_URL` 은 URL 로 가서
#   후행 공백이 `%20` 으로 인코딩됐다. 하루에 두 번, 같은 결함이 다른 얼굴로 나왔다.
#
#   ★ 이 게이트는 **필수 키만이 아니라 .env 의 모든 키**를 본다.
#     새벽에 터진 GOOGLE_CLIENT_ID·KAKAO_APP_ID 는 REQUIRED_KEYS 에 없다.
#     필수 키만 검사했다면 그 장애를 그대로 놓쳤을 것이다.
#
#   ★ 자동 trim 은 하지 않는다. 검출하고 멈추기만 한다.
#     양쪽이 같은 오염값을 쓰면 동작한다 — 조용히 고치면 그쪽이 깨진다.
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
  # MongoDB (S15P11B209-634) — MinIO 와 동일 원칙: 관리 계정과 앱 계정을 분리한다.
  #   root 는 백업·인덱스 관리용, 앱은 해당 DB 에만 readWrite.
  #   ⚠️ 이 키들이 없으면 mongodb 파드의 init 스크립트가 fail-fast 로 죽는다(조용한 반쪽 성공 방지).
  MONGO_ROOT_USERNAME
  MONGO_ROOT_PASSWORD
  MONGO_DATABASE
  MONGO_APP_USERNAME
  MONGO_APP_PASSWORD
)

# ── 알려진 오염 키 (S15P11B209-731 에서 추적) ────────────────────────────────
# 이 목록에 있는 키는 오염돼 있어도 **경고만** 하고 진행한다. 목록에 없는 키가 오염되면
# 실패시킨다 — 잡으려는 것은 "새로 생긴 오염"이지 "이미 알고 남겨둔 오염"이 아니다.
#
# 왜 통과시키는가: 아래 셋은 **값을 주고받는 양쪽이 똑같이 오염된 값을 쓰고 있어 정상 동작한다.**
#   지금 trim 하면 오히려 깨진다. 정리는 순서를 맞춰 점검 창에서 한다(731).
#     JWT_SECRET        → 서명키가 바뀌어 로그인 세션 전원 만료
#     REDIS_PASSWORD    → redis·backend 동시 재시작 필요
#     AI_INTERNAL_TOKEN → backend·ai 동시 재시작 필요
#   나머지 둘은 ConfigMap `dodam-config` 가 clean 한 값으로 덮어써서 파드에 닿지 않는다.
#   다만 ConfigMap 에서 그 키가 사라지면 오염값이 드러난다 — 그래서 목록에 남겨 계속 보이게 한다.
#     AI_OBSERVATION_MODE · AI_DRAWING_ANALYSIS_MODE
#
# ⚠️ 여기에 키를 추가하는 것은 "고쳤다"가 아니라 "미루기로 했다"는 선언이다.
#    추가할 때는 731 에 사유를 남길 것. 목록이 길어지면 게이트가 무의미해진다.
KNOWN_POLLUTED=(
  JWT_SECRET
  REDIS_PASSWORD
  AI_INTERNAL_TOKEN
  AI_OBSERVATION_MODE
  AI_DRAWING_ANALYSIS_MODE
)

ENV_FILE="${1:-}"
DRY_RUN=0
STRICT=0
for arg in "${@:2}"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    --strict)  STRICT=1 ;;
    *) echo "[sync-secrets] FAIL: 알 수 없는 옵션: ${arg}" >&2; exit 2 ;;
  esac
done

if [[ -z "${ENV_FILE}" ]]; then
  echo "사용법: $0 <.env 경로> [--dry-run] [--strict]" >&2
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

# ── ①-b 공백 오염 검출 게이트 (S15P11B209-730) ──────────────────────────────
# .env 의 **모든** 키를 본다(필수 키만이 아니다 — 파일 상단 주석의 이유 참조).
# 값은 출력하지 않는다. 줄번호·키 이름·바이트 수만 찍는다.
#
# 판정 대상은 `=` 뒤에 오는 원문 그대로다 — `--from-env-file` 이 싣는 것이 정확히 그것이기 때문.
# (따옴표 안쪽 공백은 다른 문제다. --from-env-file 은 따옴표도 값의 일부로 싣는다.)
pollution_report="$(
  KNOWN="${KNOWN_POLLUTED[*]}" python3 - "${ENV_FILE}" <<'PY'
import os, re, sys
known = set(os.environ.get("KNOWN", "").split())
for lineno, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="replace"), 1):
    s = line.rstrip("\n")
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', s)
    if not m:
        continue
    key, val = m.group(1), m.group(2)
    trimmed = val.strip()
    if len(val) == len(trimmed):
        continue
    kind = "KNOWN" if key in known else "NEW"
    # 값은 절대 싣지 않는다. 줄번호·키·길이·차이만.
    print("%s\t%d\t%s\t%d\t%d" % (kind, lineno, key, len(val), len(trimmed)))
PY
)"

new_pollution=(); known_pollution=(); fix_lines=()
while IFS=$'\t' read -r kind lineno key raw trim; do
  [[ -z "${kind:-}" ]] && continue
  entry="$(printf '%4s행 %-26s raw=%-4s trim=%-4s (차 %sB)' \
            "${lineno}" "${key}" "${raw}" "${trim}" "$((raw - trim))")"
  if [[ "${kind}" == "NEW" ]]; then
    new_pollution+=("${entry}")
    fix_lines+=("${lineno}")
  else
    known_pollution+=("${entry}")
  fi
done <<< "${pollution_report}"

if ((${#known_pollution[@]} > 0)); then
  echo "[sync-secrets] 알려진 오염 ${#known_pollution[@]}건 (S15P11B209-731 에서 추적 중):"
  printf '  %s\n' "${known_pollution[@]}"
  if (( STRICT == 1 )); then
    echo "[sync-secrets] FAIL: --strict — 알려진 오염도 실패로 처리합니다." >&2
    exit 3
  fi
  echo "  → 양쪽이 같은 오염값을 써서 지금은 동작한다. 정리는 731 의 점검 창에서."
fi

if ((${#new_pollution[@]} > 0)); then
  {
    echo "[sync-secrets] FAIL: 값에 선두/꼬리 공백이 붙은 키 ${#new_pollution[@]}건 — Secret 을 만들지 않습니다."
    printf '  %s\n' "${new_pollution[@]}"
    echo
    echo "  이 공백은 --from-env-file 이 그대로 실어 파드 env 까지 간다."
    echo "  값이 살아 있으므로 hasText() 류의 검사는 통과하고, **비교만** 깨진다."
    echo "  (2026-07-30 OAuth 전면 장애·GMS 502 가 모두 이 결함이었다)"
    echo
    echo "  조치 — 해당 줄의 꼬리 공백만 제거:"
    echo "    sed -i -E '$(IFS=,; echo "${fix_lines[*]}")s/[[:space:]]+$//' ${ENV_FILE}"
    echo
    echo "  ⚠️ 다른 곳과 값을 맞춰 쓰고 있어 지금 고치면 깨지는 키라면, 고치는 대신"
    echo "     이 스크립트의 KNOWN_POLLUTED 에 추가하고 S15P11B209-731 에 사유를 남길 것."
    echo "  (값은 출력하지 않습니다. 길이만으로 판단하세요 — 눈으로 대조하면 통과합니다.)"
  } >&2
  exit 3
fi

# JWT_SECRET 길이 — 백엔드가 32바이트 미만이면 AUTH_CONFIGURATION_INVALID 로 거부한다.
#   배포는 성공했는데 인증 API 전체가 503 이 되는 상황을 여기서 막는다(D-190-1 재발 방지).
#
# ★ trim 후 길이로 판정한다(730). 예전에는 `tr -d '\n'` 만 해서 **꼬리 공백을 길이로 셌다.**
#   20자짜리 시크릿에 탭 15개가 붙으면 35 로 계산돼 게이트를 통과한다 — 실엔트로피는 20이다.
#   지금 무사한 건 값이 마침 64자 hex 라서였지 게이트가 막아서가 아니었다.
jwt_len="$(grep -E '^JWT_SECRET=' "${ENV_FILE}" | tail -n 1 \
  | sed -e 's/^JWT_SECRET=//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" \
  | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().strip())' | wc -c)"
if (( jwt_len < 32 )); then
  echo "[sync-secrets] FAIL: JWT_SECRET 이 (공백 제외) ${jwt_len}바이트 — 32바이트 이상이어야 합니다." >&2
  echo "  생성 예: openssl rand -hex 32" >&2
  exit 3
fi

echo "[sync-secrets] 검증 통과: 필수 키 ${#REQUIRED_KEYS[@]}개 존재·비어 있지 않음, JWT_SECRET ${jwt_len}바이트(공백 제외), 미확인 오염 0건"

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
