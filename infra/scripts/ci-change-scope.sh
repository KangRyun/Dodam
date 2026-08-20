#!/usr/bin/env bash
# 두 커밋 사이의 변경 파일을 Jenkins 빌드·테스트 대상 플래그로 변환한다.
# 변경 범위를 판정할 수 없는 첫 빌드는 전체 검증으로 안전하게 폴백한다.

set -euo pipefail

MODE=git
if [ "${1:-}" = "--files-from-stdin" ]; then
  MODE=stdin
  shift
elif [ "${1:-}" = "--all" ]; then
  MODE=all
  shift
fi
[ "$#" -eq 0 ] || { echo "사용법: $0 [--files-from-stdin|--all]" >&2; exit 2; }

backend_test=false
backend_image=false
ai=false
web=false
mobile=false
nginx=false

mark_server_all() {
  backend_test=true
  backend_image=true
  ai=true
  web=true
  nginx=true
}

classify() {
  local file="$1"
  [ -n "$file" ] || return 0
  case "$file" in
    Jenkinsfile)
      mark_server_all
      mobile=true
      ;;
    backend/*)
      backend_test=true
      backend_image=true
      ;;
    ai/*)
      ai=true
      ;;
    frontend/web/*)
      web=true
      ;;
    frontend/mobile/*|infra/mobile/*)
      mobile=true
      ;;
    infra/nginx/html/legal/*)
      # 정적 약관은 nginx 산출물이면서 Backend 계약 테스트의 외부 입력이다.
      backend_test=true
      nginx=true
      ;;
    infra/nginx/*)
      nginx=true
      ;;
    infra/*)
      # compose·배포 스크립트·k8s 변경은 서비스 경계를 안전하게 추론하기 어렵다.
      mark_server_all
      ;;
  esac
}

if [ "$MODE" = "all" ]; then
  mark_server_all
  mobile=true
else
  files=""
  if [ "$MODE" = "stdin" ]; then
    files="$(cat)"
  else
    base="${CI_DIFF_BASE:-}"
    if [ -z "$base" ] && [ -n "${CHANGE_TARGET:-}" ] \
       && git rev-parse --verify --quiet "origin/${CHANGE_TARGET}^{commit}" >/dev/null; then
      base="$(git merge-base HEAD "origin/${CHANGE_TARGET}")"
    fi
    if [ -z "$base" ] && [ -n "${GIT_PREVIOUS_SUCCESSFUL_COMMIT:-}" ] \
       && git rev-parse --verify --quiet "${GIT_PREVIOUS_SUCCESSFUL_COMMIT}^{commit}" >/dev/null \
       && [ "$GIT_PREVIOUS_SUCCESSFUL_COMMIT" != "$(git rev-parse HEAD)" ]; then
      base="$GIT_PREVIOUS_SUCCESSFUL_COMMIT"
    fi
    # 멀티브랜치의 첫 빌드는 이전 성공 커밋이 없다. 이때 HEAD^만 보면 push 전에 쌓인 여러
    # 커밋 중 마지막 것만 검사하므로, 작업 브랜치는 develop과의 전체 차이를 기준으로 삼는다.
    if [ -z "$base" ] && [ "${BRANCH_NAME:-}" != "develop" ] \
       && git rev-parse --verify --quiet 'origin/develop^{commit}' >/dev/null; then
      base="$(git merge-base HEAD origin/develop)"
    fi
    if [ -z "$base" ] && git rev-parse --verify --quiet 'HEAD^' >/dev/null; then
      base="HEAD^"
    fi
    if [ -z "$base" ]; then
      mark_server_all
      mobile=true
    else
      files="$(git diff --name-only "$base" HEAD)"
      # 빈 diff는 중복 빌드일 수 있으므로 실제로 아무 대상도 실행하지 않는다.
    fi
  fi

  while IFS= read -r file; do
    classify "$file"
  done <<< "$files"
fi

services=()
[ "$backend_image" = true ] && services+=(backend)
[ "$ai" = true ] && services+=(ai)
[ "$web" = true ] && services+=(web)
[ "$nginx" = true ] && services+=(nginx)

deploy=false
[ "${#services[@]}" -gt 0 ] && deploy=true

printf 'BACKEND_TEST_REQUIRED=%s\n' "$backend_test"
printf 'BACKEND_IMAGE_CHANGED=%s\n' "$backend_image"
printf 'AI_CHANGED=%s\n' "$ai"
printf 'WEB_CHANGED=%s\n' "$web"
printf 'MOBILE_TEST_REQUIRED=%s\n' "$mobile"
printf 'NGINX_CHANGED=%s\n' "$nginx"
printf 'DEPLOY_REQUIRED=%s\n' "$deploy"
printf 'BUILD_SERVICES=%s\n' "${services[*]}"
