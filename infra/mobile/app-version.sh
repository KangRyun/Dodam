#!/usr/bin/env bash
# 도담 앱 버전·빌드번호 산출 (S15P11B209-629)
#
# Android(AAB)·iOS(Archive)가 **같은 값**을 쓰도록 산출을 한 곳에 모은다.
# 호스트에서도 Jenkins 안에서도 같은 답이 나와야 한다 — build-aab.sh 와 같은 원칙이다.
#
#   versionName (build-name)   = pubspec.yaml 의 version 앞부분. 사람이 올린다(semantic).
#   versionCode (build-number) = develop 히스토리의 커밋 수. 자동으로 단조 증가한다.
#
# ⚠️ 왜 Jenkins BUILD_NUMBER 를 쓰지 않는가 (이 파일의 존재 이유)
#   BUILD_NUMBER 는 저장소 사실이 아니라 **잡에 딸린 상태**다. 잡이 지워지면 같이 사라진다.
#   2026-07-29 실제로 그 일이 있었다 — 브랜치 필터를 잘못 건드려 develop 잡이 삭제·재생성되면서
#   빌드 번호가 123 이상에서 1 로 되돌아갔다(잡 디렉터리 생성 12:14, 빌드 1..9 재시작).
#   Play 는 versionCode 가 기존보다 **반드시 커야** 업로드를 받는다. 한 번 큰 값을 올린 뒤
#   번호가 뒤로 구르면 그 앱은 영구히 업로드가 막힌다. 아직 Play 에 올린 적이 없어서
#   물리지 않았을 뿐이고, 626(Play 업로드) 전에 소스를 저장소 쪽으로 옮긴다.
#
# 사용:
#   infra/mobile/app-version.sh                 → BUILD_NAME=1.0.0
#                                                 BUILD_NUMBER=1023
#   infra/mobile/app-version.sh --build-number  → 1023
#   infra/mobile/app-version.sh --build-name    → 1.0.0
#   eval "$(infra/mobile/app-version.sh)"       → 두 변수를 셸에 주입

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC="$REPO_ROOT/frontend/mobile/pubspec.yaml"

die() { printf '\n❌ app-version: %s\n' "$*" >&2; exit 1; }

# ── build-name: pubspec 의 version 에서 '+' 앞부분 ─────────────────────────
#   pubspec 이 versionName 의 유일한 출처다. 릴리스 때 사람이 여기를 올린다.
[ -f "$PUBSPEC" ] || die "pubspec.yaml 을 찾을 수 없다: $PUBSPEC"

BUILD_NAME="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "$PUBSPEC" | head -1)"
[ -n "$BUILD_NAME" ] || die "pubspec.yaml 에서 version 을 읽지 못했다 (형식: 'version: 1.0.0+1')"

# ── build-number: 커밋 수 ──────────────────────────────────────────────────
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "git 저장소가 아니다 — 빌드번호를 산출할 수 없다: $REPO_ROOT"

# ★ shallow clone 금지.
#   reason: shallow 는 히스토리를 잘라내므로 커밋 수가 실제보다 **작게** 나온다.
#   그 값으로 Play 에 올리면 versionCode 가 뒤로 굴러 위 사고를 그대로 재현한다.
#   조용히 작은 값을 내느니 여기서 멈추는 게 낫다.
#   (2026-07-29 기준 Jenkins 잡에 depth 설정이 없어 전체 클론이다. 설정이 바뀌면 여기서 걸린다)
if [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  die "shallow clone 에서는 빌드번호를 낼 수 없다(커밋 수가 실제보다 작게 나온다).
   전체 히스토리로 클론하거나 'git fetch --unshallow' 후 다시 실행할 것."
fi

BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD)"
[ "$BUILD_NUMBER" -gt 0 ] 2>/dev/null || die "커밋 수를 산출하지 못했다 (값: '$BUILD_NUMBER')"

case "${1:-}" in
  --build-name)   printf '%s\n' "$BUILD_NAME" ;;
  --build-number) printf '%s\n' "$BUILD_NUMBER" ;;
  '')             printf 'BUILD_NAME=%s\nBUILD_NUMBER=%s\n' "$BUILD_NAME" "$BUILD_NUMBER" ;;
  *)              die "알 수 없는 인자: $1 (--build-name | --build-number | 없음)" ;;
esac
