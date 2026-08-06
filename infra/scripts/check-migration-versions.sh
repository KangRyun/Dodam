#!/usr/bin/env bash
# Flyway 마이그레이션 번호 충돌 검사 (S15P11B209-986)
#
# 왜 있나 — 2026-08-06 사고의 재발 방지책.
#   982 와 983 이 각각 `V43__...sql` 을 만들었다. 파일명이 달라서 **git 은 충돌로 보지 않는다** —
#   양쪽 다 "새 파일 추가"라 조용히 병합된다. 그대로 머지됐다면 Flyway 가
#   `Found more than one migration with version 43` 으로 던져 **애플리케이션 기동 자체가 실패**한다.
#   배포가 아니라 기동이 죽는 종류라, MR 단계에서 잡지 못하면 develop 이 통째로 멈춘다.
#
#   `DatabaseMigrationIntegrationTest` 가 결국은 잡지만 Testcontainers 를 띄우는 무거운 테스트라
#   로컬에서 자주 안 돌리고, 무엇보다 **머지된 뒤에** develop CI 에서 터진다. 그때는 늦다.
#
# 왜 구조적으로 재발하나
#   번호는 브랜치를 딸 때 정해지는데 머지는 며칠 뒤다. **분기 시점에 비어 있던 번호가 머지 시점에는
#   차 있다.** 사람이 "머지 직전에 다시 확인"하는 것에 기대는 한 계속 난다.
#
# 사용:
#   infra/scripts/check-migration-versions.sh                  # develop 과 비교
#   infra/scripts/check-migration-versions.sh --base origin/main
#   infra/scripts/check-migration-versions.sh --quiet          # 통과 시 조용히
#
# 종료코드: 0 = 통과 / 1 = 충돌(머지 금지) / 2 = 사용법 오류
# root·도커·컨테이너 불필요. 수 초 안에 끝난다.

set -uo pipefail

MIGRATION_DIR="backend/src/main/resources/db/migration"
BASE_REF="origin/develop"
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base)  BASE_REF="${2:-}"; shift 2 || exit 2 ;;
    --quiet) QUIET=1; shift ;;
    --dir)   MIGRATION_DIR="${2:-}"; shift 2 || exit 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; }

[ -d "$MIGRATION_DIR" ] || { fail "❌ 마이그레이션 디렉터리가 없다: $MIGRATION_DIR"; exit 2; }

# ── 버전 추출 ────────────────────────────────────────────────────────────
# Flyway 규칙: V<버전>__<설명>.sql. 이 저장소는 전부 정수를 쓴다.
#   버전만 뽑되 파일명을 함께 들고 다녀야 "누구와 겹쳤는지"를 사람에게 보여 줄 수 있다.
version_of() { basename "$1" | sed -n 's/^V\([0-9][0-9.]*\)__.*\.sql$/\1/p'; }

declare -A BRANCH_FILE=()   # 버전 → 파일명
DUPES=0

while IFS= read -r path; do
  v="$(version_of "$path")"
  [ -n "$v" ] || continue
  name="$(basename "$path")"
  if [ -n "${BRANCH_FILE[$v]:-}" ]; then
    fail "❌ 같은 번호가 이 브랜치 안에 둘 있다 — V$v"
    fail "     ${BRANCH_FILE[$v]}"
    fail "     ${name}"
    DUPES=1
  else
    BRANCH_FILE[$v]="$name"
  fi
done < <(find "$MIGRATION_DIR" -maxdepth 1 -name 'V*__*.sql' | sort)

[ "${#BRANCH_FILE[@]}" -gt 0 ] || { fail "❌ 마이그레이션 파일을 하나도 못 찾았다 — 경로를 확인할 것: $MIGRATION_DIR"; exit 2; }

# 다음에 쓸 수 있는 번호 (정수 버전만 고려 — 이 저장소 관례)
next_free() {
  local max=0 v
  for v in "${!BRANCH_FILE[@]}"; do
    case "$v" in *.*) continue ;; esac      # 소수점 버전은 최대값 계산에서 제외
    [ "$v" -gt "$max" ] 2>/dev/null && max="$v"
  done
  echo $((max + 1))
}

# ── base 브랜치와 비교 ───────────────────────────────────────────────────
# 이게 986 의 본체다. 브랜치 안에서는 번호가 유일해도, base 에 이미 있는 번호를 쓰면
#   머지된 순간 중복이 된다. 982 사고가 정확히 이 형태였다.
CROSS=0
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  say "⚠️  base 참조를 찾을 수 없어 교차 검사를 건너뛴다: $BASE_REF"
  say "    (얕은 클론이거나 fetch 가 안 된 경우다. 브랜치 내부 중복 검사는 그대로 수행했다.)"
elif [ "$(git rev-parse HEAD)" = "$(git rev-parse "$BASE_REF")" ]; then
  say "· HEAD 가 $BASE_REF 와 같다 — 교차 검사는 의미가 없어 건너뛴다"
else
  while IFS= read -r name; do
    v="$(version_of "$name")"
    [ -n "$v" ] || continue
    mine="${BRANCH_FILE[$v]:-}"
    # 같은 번호인데 파일이 다르다 = 서로 다른 마이그레이션이 한 번호를 쓴다
    if [ -n "$mine" ] && [ "$mine" != "$name" ]; then
      fail "❌ V$v 이 $BASE_REF 와 겹친다 — 서로 다른 마이그레이션이 같은 번호를 쓴다"
      fail "     $BASE_REF : $name"
      fail "     이 브랜치  : $mine"
      CROSS=1
    fi
  done < <(git ls-tree --name-only "$BASE_REF" "$MIGRATION_DIR/" 2>/dev/null | xargs -r -n1 basename | sort)
fi

if [ "$DUPES" -ne 0 ] || [ "$CROSS" -ne 0 ]; then
  fail ""
  fail "→ 파일명을 다음 번호로 바꿔라: V$(next_free)__<설명>.sql"
  fail "  파일명만 바꾸면 끝이 아니다. 함께 확인할 것:"
  fail "   · DatabaseMigrationIntegrationTest 의 스키마 버전 기대값"
  fail "   · 같은 테스트의 tableCount() — CREATE TABLE 이 있을 때만 움직인다(컬럼 추가는 그대로)"
  fail "   · 문서·주석에 남은 옛 번호"
  fail ""
  fail "  Flyway 는 버전이 겹치면 마이그레이션이 아니라 **애플리케이션 기동**이 실패한다."
  exit 1
fi

say "✅ 마이그레이션 번호 검사 통과 — ${#BRANCH_FILE[@]}개, 중복 없음 (다음 번호: V$(next_free))"

# ── 참고 경고: 마이그레이션이 늘었는데 검증 테스트가 그대로다 ────────────
# 실패로 만들지 않는다 — 컬럼만 더하는 마이그레이션은 tableCount() 가 안 바뀌는 것이 정상이라
#   거짓 양성이 잦다. 960 이 이 두 숫자를 빠뜨려 CI 를 깨뜨린 적 있어 눈에는 띄게 해 둔다.
TEST_PATH="backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java"
if git rev-parse --verify --quiet "$BASE_REF" >/dev/null \
   && [ "$(git rev-parse HEAD)" != "$(git rev-parse "$BASE_REF")" ]; then
  added="$(git diff --name-only --diff-filter=A "$BASE_REF...HEAD" -- "$MIGRATION_DIR" 2>/dev/null | wc -l)"
  touched="$(git diff --name-only "$BASE_REF...HEAD" -- "$TEST_PATH" 2>/dev/null | wc -l)"
  if [ "$added" -gt 0 ] && [ "$touched" -eq 0 ]; then
    say "⚠️  마이그레이션 ${added}개를 더했는데 DatabaseMigrationIntegrationTest 는 그대로다."
    say "    스키마 버전 기대값을 올려야 하는지 확인할 것 (960 에서 이걸 빠뜨려 CI 가 깨졌다)."
  fi
fi
