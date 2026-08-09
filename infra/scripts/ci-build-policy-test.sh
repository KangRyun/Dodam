#!/usr/bin/env bash
# Jenkins 빌드 최적화 정책의 변경 범위 판정과 캐시 가드레일을 검증한다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCOPE_SCRIPT="$REPO_ROOT/infra/scripts/ci-change-scope.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_scope() {
  local name="$1" files="$2" expected="$3" actual
  actual="$(printf '%s\n' "$files" | "$SCOPE_SCRIPT" --files-from-stdin | sort)"
  [ "$actual" = "$expected" ] || fail "$name\nexpected:\n$expected\nactual:\n$actual"
}

assert_contains() {
  local file="$1" pattern="$2"
  grep -Fq -- "$pattern" "$file" || fail "$file 에 '$pattern' 이 없다"
}

assert_not_contains() {
  local file="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    fail "$file 에 금지 패턴 '$pattern' 이 남아 있다"
  fi
}

[ -x "$SCOPE_SCRIPT" ] || fail "실행 가능한 ci-change-scope.sh가 필요하다"

assert_scope "backend only" "backend/src/main/java/App.java" \
  $'AI_CHANGED=false\nBACKEND_IMAGE_CHANGED=true\nBACKEND_TEST_REQUIRED=true\nBUILD_SERVICES=backend\nDEPLOY_REQUIRED=true\nMOBILE_TEST_REQUIRED=false\nNGINX_CHANGED=false\nWEB_CHANGED=false'

assert_scope "mobile only" "frontend/mobile/lib/main.dart" \
  $'AI_CHANGED=false\nBACKEND_IMAGE_CHANGED=false\nBACKEND_TEST_REQUIRED=false\nBUILD_SERVICES=\nDEPLOY_REQUIRED=false\nMOBILE_TEST_REQUIRED=true\nNGINX_CHANGED=false\nWEB_CHANGED=false'

assert_scope "docs only" "docs/api/example.md" \
  $'AI_CHANGED=false\nBACKEND_IMAGE_CHANGED=false\nBACKEND_TEST_REQUIRED=false\nBUILD_SERVICES=\nDEPLOY_REQUIRED=false\nMOBILE_TEST_REQUIRED=false\nNGINX_CHANGED=false\nWEB_CHANGED=false'

assert_scope "legal contract" "infra/nginx/html/legal/privacy/index.html" \
  $'AI_CHANGED=false\nBACKEND_IMAGE_CHANGED=false\nBACKEND_TEST_REQUIRED=true\nBUILD_SERVICES=nginx\nDEPLOY_REQUIRED=true\nMOBILE_TEST_REQUIRED=false\nNGINX_CHANGED=true\nWEB_CHANGED=false'

assert_scope "multiple services" $'ai/main.py\nfrontend/web/src/app/page.tsx' \
  $'AI_CHANGED=true\nBACKEND_IMAGE_CHANGED=false\nBACKEND_TEST_REQUIRED=false\nBUILD_SERVICES=ai web\nDEPLOY_REQUIRED=true\nMOBILE_TEST_REQUIRED=false\nNGINX_CHANGED=false\nWEB_CHANGED=true'

assert_scope "pipeline fail-safe" "Jenkinsfile" \
  $'AI_CHANGED=true\nBACKEND_IMAGE_CHANGED=true\nBACKEND_TEST_REQUIRED=true\nBUILD_SERVICES=backend ai web nginx\nDEPLOY_REQUIRED=true\nMOBILE_TEST_REQUIRED=true\nNGINX_CHANGED=true\nWEB_CHANGED=true'

assert_contains "$REPO_ROOT/Jenkinsfile" "./gradlew --build-cache"
assert_not_contains "$REPO_ROOT/Jenkinsfile" "./gradlew --no-daemon"
assert_contains "$REPO_ROOT/Jenkinsfile" 'docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build $BUILD_SERVICES'
assert_contains "$REPO_ROOT/Jenkinsfile" 'for svc in $BUILD_SERVICES; do set -- "$@" --service "$svc"; done'
assert_contains "$REPO_ROOT/Jenkinsfile" 'changed backend && kubectl -n dodam set image deployment/backend'
assert_contains "$REPO_ROOT/Jenkinsfile" 'expression { env.DEPLOY_REQUIRED == '\''true'\'' }'
assert_contains "$REPO_ROOT/Jenkinsfile" "(mergeRequestBuild || params.FORCE_FULL_TESTS) ? 'test' : 'quickTest'"
assert_contains "$REPO_ROOT/Jenkinsfile" "name: 'FORCE_FULL_TESTS'"

assert_contains "$REPO_ROOT/backend/build.gradle" "tasks.register('quickTest', Test)"
assert_contains "$REPO_ROOT/backend/gradle.properties" 'org.gradle.daemon=true'
assert_contains "$REPO_ROOT/backend/gradle.properties" 'org.gradle.caching=true'

assert_contains "$REPO_ROOT/infra/mobile/ci-test.sh" ':/src/.dart_tool'
assert_contains "$REPO_ROOT/infra/mobile/ci-test.sh" ':/src/build'
assert_not_contains "$REPO_ROOT/infra/mobile/ci-test.sh" 'rm -rf build .dart_tool android/.gradle android/app/build'

selected_images="$("$REPO_ROOT/infra/scripts/push-staging-images.sh" \
  --service backend --service web --list-images)"
[ "$selected_images" = 'dodam-backend dodam-web' ] \
  || fail "선택 이미지가 다르다: $selected_images"

printf 'PASS: CI 빌드 최적화 정책\n'
