#!/usr/bin/env bash
# 도담 Android 릴리스 서명 자재 준비 (S15P11B209-623)
#
# 무엇을 하나 — build-aab.sh 가 요구하는 파일 2개를 대화형으로 만들고, **실제로 맞는지 검증**한다.
#   ~/dodam-secrets/key.properties   : keystore 비밀번호·별칭
#   ~/dodam-secrets/oauth.env        : 앱 OAuth 값 5개
#
# 왜 스크립트인가 — 손으로 쓰면 틀려도 그 자리에서 모른다.
#   비밀번호가 한 글자 틀리면 gradle 이 10분쯤 돌다가 죽고, 오타는 로그에 안 찍힌다.
#   여기서는 **입력한 비밀번호로 실제 keystore 를 열어 본 뒤에만** 파일을 쓴다.
#
# 사용 — 두 가지 경로가 있다
#
#   (1) 실제 터미널(SSH 셸)에서 — 권장. 비밀번호가 어디에도 안 남는다
#         infra/mobile/setup-signing.sh
#
#   (2) 값을 환경변수로 주입 — Claude Code 의 `!` 처럼 **제어 터미널이 없는** 곳에서 쓴다
#         STORE_PASSWORD='...' KEY_ALIAS=dodam-upload \
#         KAKAO_NATIVE_APP_KEY='...' GOOGLE_SERVER_CLIENT_ID='...' \
#         NAVER_CLIENT_ID='...' NAVER_CLIENT_SECRET='...' NAVER_APP_NAME='...' \
#         infra/mobile/setup-signing.sh
#       ⚠️ 이 경로는 비밀번호가 셸 히스토리·대화 기록에 남는다. 남는 게 싫으면 (1) 이나
#          STORE_PASSWORD_FILE=<600 권한 파일> 을 쓸 것.
#
#   --check : 아무것도 입력받지 않고 현재 상태만 점검한다(터미널 없어도 됨)
#
# 안전:  비밀번호는 화면에 찍지 않고, 만들어지는 파일은 600 으로 잠근다.
#        ★ 비밀번호로 **실제 keystore 를 열어 본 뒤에만** key.properties 를 쓴다.

set -uo pipefail

SECRETS_DIR="${SECRETS_DIR:-$HOME/dodam-secrets}"
KEYSTORE="${KEYSTORE:-$SECRETS_DIR/upload-keystore.jks}"
KEY_PROPS="$SECRETS_DIR/key.properties"
OAUTH_ENV="$SECRETS_DIR/oauth.env"
# keytool 을 돌릴 이미지. 호스트에 keytool 이 없을 때만 쓴다.
#   이미 있는 이미지를 재사용한다 — 검증 한 번 하자고 450MB 를 새로 받을 이유가 없다.
#   (dodam-backend:local 은 temurin 기반이라 keytool 을 갖고 있다 — 07-28 실측)
#   둘 다 없으면 eclipse-temurin 으로 폴백한다.
if [ -z "${JDK_IMAGE:-}" ]; then
  for cand in dodam-backend:local dodam-jenkins:local eclipse-temurin:17-jdk-noble; do
    docker image inspect "$cand" >/dev/null 2>&1 && { JDK_IMAGE="$cand"; break; }
  done
  JDK_IMAGE="${JDK_IMAGE:-eclipse-temurin:17-jdk-noble}"
fi

bold() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { printf '   ✅ %s\n' "$*"; }
warn() { printf '   ⚠️  %s\n' "$*"; }
die()  { printf '\n❌ %s\n' "$*" >&2; exit 1; }

MODE="${1:-}"
case "$MODE" in
  -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
  --check)   CHECK_ONLY=1 ;;
  "")        CHECK_ONLY=0 ;;
  *)         echo "알 수 없는 인자: $MODE (--check / --help)" >&2; exit 2 ;;
esac

# ── 입력 경로 판정 ────────────────────────────────────────────────────────────
# 제어 터미널이 있으면 프롬프트를, 없으면 환경변수를 쓴다.
#   reason: Claude Code 의 `!` 실행에는 제어 터미널이 없다(/dev/tty 열기 실패).
#   예전 버전은 여기서 그냥 죽었는데, 그러면 이 서버에서 쓸 방법이 아예 없어진다.
HAS_TTY=0
if ( exec </dev/tty ) 2>/dev/null; then HAS_TTY=1; fi

# 값 하나를 얻는다: 환경변수 우선 → 터미널 프롬프트 → 실패
#   $1=변수명  $2=프롬프트 문구  $3=secret 여부(1이면 화면에 안 찍는다)  $4=기본값
get_value() {
  local var="$1" prompt="$2" secret="${3:-0}" default="${4:-}" cur
  cur="${!var:-}"
  if [ -n "$cur" ]; then printf '%s' "$cur"; return 0; fi
  # <VAR>_FILE 로 파일에서 읽는 경로 — 히스토리에 남기기 싫은 비밀번호용
  local fvar="${var}_FILE" fpath
  fpath="${!fvar:-}"
  if [ -n "$fpath" ] && [ -f "$fpath" ]; then head -1 "$fpath"; return 0; fi
  if [ "$HAS_TTY" = "1" ]; then
    local val
    if [ "$secret" = "1" ]; then read -r -s -p "   $prompt" val </dev/tty; echo >&2
    else read -r -p "   $prompt" val </dev/tty; fi
    printf '%s' "${val:-$default}"; return 0
  fi
  return 1
}

need_tty_or_env() {
  die "제어 터미널이 없고 환경변수도 비어 있다 — 값을 받을 방법이 없다.

   방법 A) 실제 터미널(SSH 셸)에서 실행 — 비밀번호가 어디에도 안 남는다
       infra/mobile/setup-signing.sh

   방법 B) 값을 환경변수로 주입 (⚠️ 셸 히스토리·대화 기록에 남는다)
       STORE_PASSWORD='<keystore 비밀번호>' KEY_ALIAS=dodam-upload \\
       KAKAO_NATIVE_APP_KEY='...' GOOGLE_SERVER_CLIENT_ID='...' \\
       NAVER_CLIENT_ID='...' NAVER_CLIENT_SECRET='...' NAVER_APP_NAME='...' \\
       infra/mobile/setup-signing.sh

   방법 C) 비밀번호만 파일로 (기록에 안 남김)
       STORE_PASSWORD_FILE=~/dodam-secrets/.pw  ← 600 으로 만들어 둘 것

   현재 상태만 보려면:  infra/mobile/setup-signing.sh --check"
}

bold "0. keystore 확인"
[ -f "$KEYSTORE" ] || die "keystore 가 없다: $KEYSTORE
   먼저 만들 것 — 절차는 infra/mobile/README.md 2절."
ok "발견: $KEYSTORE"

# 소유·권한 점검. README 절차가 docker(root)로 keytool 을 돌리는 탓에 root:root 644 로 생긴다.
#   644 = 이 서버의 다른 사용자도 읽을 수 있다는 뜻이다(상위 디렉터리 700 이 막고는 있다).
#   업로드 키는 잃어버리면 앱을 영원히 업데이트할 수 없는 자재라 느슨하게 두지 않는다.
OWNER="$(stat -c '%U' "$KEYSTORE")"
PERM="$(stat -c '%a' "$KEYSTORE")"
if [ "$OWNER" != "$(id -un)" ] || [ "$PERM" != "600" ]; then
  warn "소유=$OWNER 권한=$PERM — 아래 한 줄로 정리할 것(root 필요):"
  echo "     sudo chown $(id -un):$(id -gn) '$KEYSTORE' && chmod 600 '$KEYSTORE'"
  warn "(지금 계속 진행해도 빌드는 된다. 다만 정리 전에는 팀 공유·백업하지 말 것)"
else
  ok "소유·권한 정상 ($OWNER, $PERM)"
fi

mkdir -p "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR" 2>/dev/null

# ─────────────────────────────────────────────────────────────────────────────
bold "1. key.properties"
[ "$CHECK_ONLY" = "1" ] && SKIP_PROPS=1
if [ -f "$KEY_PROPS" ] && [ "${FORCE:-0}" != "1" ]; then
  ok "이미 있다 — 유지한다 (다시 만들려면 FORCE=1)"
  SKIP_PROPS=1
fi

if [ "${SKIP_PROPS:-0}" != "1" ]; then
  ALIAS="$(get_value KEY_ALIAS '키 별칭(alias) [dodam-upload]: ' 0 dodam-upload)" || need_tty_or_env
  ALIAS="${ALIAS:-dodam-upload}"
  STOREPASS="$(get_value STORE_PASSWORD 'keystore 비밀번호: ' 1)" || need_tty_or_env
  KEYPASS="$(get_value KEY_PASSWORD '키 비밀번호(같으면 그냥 Enter): ' 1)" || KEYPASS=""
  KEYPASS="${KEYPASS:-$STOREPASS}"
  [ -n "$STOREPASS" ] || die "비밀번호가 비었다."

  # ★ 쓰기 전에 실제로 열어 본다. "파일을 만들었다"와 "그 값이 맞다"는 다르다.
  #   호스트에 keytool 이 없을 수 있어 컨테이너로 검증한다(README 의 생성 절차와 같은 이미지).
  bold "   검증 — 입력한 비밀번호로 keystore 를 실제로 열어 본다"
  if command -v keytool >/dev/null 2>&1; then
    VERIFY_OUT=$(keytool -list -keystore "$KEYSTORE" -storepass "$STOREPASS" -alias "$ALIAS" 2>&1); RC=$?
  else
    # --entrypoint : 재사용하는 이미지(dodam-backend 등)에는 자기 ENTRYPOINT 가 있다.
    # --user       : ★필수. 이 이미지들은 비-root 사용자(예: spring, uid 1001)로 돈다.
    #   keystore 는 600 이라 그 사용자는 읽지 못하고, **java 는 그걸 "파일 없음"이라고 보고한다**
    #   ("Keystore file does not exist") — 비밀번호가 맞아도 틀렸다고 나온다. 07-28 실측으로 잡음.
    #   호출자 uid 로 돌려 소유자 권한 그대로 읽게 한다.
    VERIFY_OUT=$(docker run --rm -i --entrypoint keytool --user "$(id -u):$(id -g)" \
      -v "$KEYSTORE:/ks.jks:ro" "$JDK_IMAGE" \
      -list -keystore /ks.jks -storepass "$STOREPASS" -alias "$ALIAS" 2>&1); RC=$?
  fi
  if [ "$RC" -ne 0 ]; then
    echo "$VERIFY_OUT" | sed 's/^/     /' | head -5
    die "비밀번호 또는 별칭이 맞지 않는다. key.properties 를 쓰지 않고 중단한다.
   (틀린 채로 진행하면 gradle 이 10분쯤 돌다가 죽는다 — 여기서 잡는 게 낫다)"
  fi
  ok "검증 통과 — $(echo "$VERIFY_OUT" | grep -iE '^dodam|별칭|Alias' | head -1)"

  umask 077
  cat > "$KEY_PROPS" <<EOF
# S15P11B209-623 — infra/mobile/setup-signing.sh 가 생성. 저장소에 절대 커밋 금지.
# storeFile 은 **컨테이너 안 경로 기준 상대경로**다. build-aab.sh 가 keystore 를
# /src/android/upload-keystore.jks 로 넣고, gradle 이 rootProject(=android/) 기준으로 푼다.
# 호스트 절대경로를 적으면 컨테이너 안에서 못 찾는다.
storeFile=upload-keystore.jks
storePassword=$STOREPASS
keyAlias=$ALIAS
keyPassword=$KEYPASS
EOF
  chmod 600 "$KEY_PROPS"
  ok "생성: $KEY_PROPS (600)"
  unset STOREPASS KEYPASS
fi

# ─────────────────────────────────────────────────────────────────────────────
bold "2. oauth.env (앱 OAuth 값 5개)"
echo "   값 출처: 각 콘솔(카카오·구글·네이버) 또는 팀원의 android/oauth.properties."
echo "   ⚠️ 빈 값으로 두면 build.gradle.kts 의 requireOAuthValue 가드가 빌드를 세운다"
echo "      (빈 값으로 서명된 앱이 배포되는 것보다 낫다는 판단 — 그대로 둔다)."

VARS=(KAKAO_NATIVE_APP_KEY GOOGLE_SERVER_CLIENT_ID NAVER_CLIENT_ID NAVER_CLIENT_SECRET NAVER_APP_NAME)

# 팀원이 이미 쓰던 android/oauth.properties 가 있으면 그대로 옮긴다(재입력 오타 방지).
REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
SRC_PROPS="$REPO_ROOT/frontend/mobile/android/oauth.properties"
if [ "$CHECK_ONLY" = "1" ]; then
  ok "(--check) 입력받지 않고 상태만 본다"
elif [ -f "$SRC_PROPS" ]; then
  ok "android/oauth.properties 발견 — 여기서 값을 가져온다"
  umask 077; : > "$OAUTH_ENV"
  for v in "${VARS[@]}"; do
    val=$(sed -n "s/^${v}=//p" "$SRC_PROPS" | head -1)
    [ -z "$val" ] && warn "$v 가 비어 있다 — 콘솔에서 확인 필요"
    printf '%s=%s\n' "$v" "$val" >> "$OAUTH_ENV"
  done
else
  if [ -f "$OAUTH_ENV" ] && [ "${FORCE:-0}" != "1" ]; then
    ok "oauth.env 가 이미 있다 — 유지한다 (다시 만들려면 FORCE=1)"
    SKIP_OAUTH=1
  fi
  if [ "${SKIP_OAUTH:-0}" != "1" ]; then
    # 5개 중 하나라도 환경변수/터미널로 못 받으면, 반쪽짜리 파일을 만들지 않고 안내하고 끝낸다.
    #   reason: 빈 값이 섞인 oauth.env 는 "파일은 있는데 빌드는 실패"라는 최악의 상태다.
    declare -A GOT=()
    MISSING=()
    for v in "${VARS[@]}"; do
      if val="$(get_value "$v" "$v: " 0)"; then GOT[$v]="$val"; else MISSING+=("$v"); fi
      [ -n "${GOT[$v]:-}" ] || { [ ${#MISSING[@]} -eq 0 ] && MISSING+=("$v"); }
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
      warn "받지 못한 값: ${MISSING[*]}"
      warn "oauth.env 를 만들지 않고 넘어간다(빈 값 섞인 파일이 제일 나쁘다)."
      if [ "$HAS_TTY" != "1" ]; then
        echo
        echo "   값을 아신다면 이렇게 한 번에 넣을 수 있다:"
        echo "     KAKAO_NATIVE_APP_KEY='...' GOOGLE_SERVER_CLIENT_ID='...' \\"
        echo "     NAVER_CLIENT_ID='...' NAVER_CLIENT_SECRET='...' NAVER_APP_NAME='...' \\"
        echo "     infra/mobile/setup-signing.sh"
        echo "   (팀원의 frontend/mobile/android/oauth.properties 가 있으면 그 파일만 갖다 놓아도 된다)"
      fi
    else
      umask 077; : > "$OAUTH_ENV"
      for v in "${VARS[@]}"; do printf '%s=%s\n' "$v" "${GOT[$v]}" >> "$OAUTH_ENV"; done
    fi
  fi
fi
[ -f "$OAUTH_ENV" ] && chmod 600 "$OAUTH_ENV"

# ─────────────────────────────────────────────────────────────────────────────
bold "3. 최종 점검"
FAIL=0
for f in "$KEY_PROPS" "$OAUTH_ENV"; do
  if [ -f "$f" ]; then ok "$(basename "$f") 있음 ($(stat -c '%a' "$f"))"; else warn "$(basename "$f") 없음"; FAIL=1; fi
done
if [ -f "$OAUTH_ENV" ]; then
  EMPTY=$(grep -cE '^[A-Z_]+=$' "$OAUTH_ENV" || true)
  [ "$EMPTY" -gt 0 ] && { warn "oauth.env 에 빈 값 ${EMPTY}개 — 빌드가 실패한다"; FAIL=1; } || ok "oauth.env 값 5개 모두 채워짐"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1m✅ 준비 완료 — 이제 빌드할 수 있다\033[0m\n\n'
  cat <<EOF
  # 1) 빌더 이미지(최초 1회, 10~20분)
  docker build -t dodam-flutter-builder:3.44.7 infra/mobile

  # 2) AAB 빌드
  KEYSTORE_FILE=$KEYSTORE \\
  KEY_PROPERTIES_FILE=$KEY_PROPS \\
  OAUTH_ENV_FILE=$OAUTH_ENV \\
  infra/mobile/build-aab.sh
EOF
else
  printf '\033[1m⚠️  아직 빠진 값이 있다 — 위 항목을 채운 뒤 다시 실행할 것\033[0m\n'
fi
