#!/usr/bin/env bash
# 도담(dodam) 무거운 작업 전 메모리 사전 점검 (S15P11B209-356)
#
# 왜 있나 — 2026-07-28 사고의 직접 재발 방지책.
#   k3s 세팅을 시작한 시점에 이미 여유 메모리가 얇았고(빌드 병행), 그대로 밀어붙이다
#   호스트가 응답 불능이 됐다. 사람이 매번 `free -h` 를 눈으로 보고 판단하는 대신,
#   **시작 자체를 막는** 관문을 둔다. 판단을 기억력에 맡기지 않는다.
#
# 쓰는 곳: k3s 설치(356·358) · Android AAB 빌드(623) · k6 부하테스트(355) 등
#   메모리를 GB 단위로 먹는 작업 직전.
#
# 사용:
#   infra/scripts/preflight-memory.sh                # 기본 4GB 필요
#   infra/scripts/preflight-memory.sh --need 6144    # 6GB 필요(k3s 설치 권장값)
#   infra/scripts/preflight-memory.sh --quiet && 무거운작업   # 통과할 때만 실행
#
# 종료코드: 0 = 진행해도 됨 / 1 = 막힘(이유 출력) / 2 = 사용법 오류
# root 불필요.

set -uo pipefail

NEED_MB=4096
QUIET=0
IN_CI=0
while [ $# -gt 0 ]; do
  case "$1" in
    --need)  NEED_MB="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    # CI 파이프라인 **안에서** 부를 때. 자기 자신을 "다른 빌드"로 오인하는 것을 막는다.
    #   (S15P11B209-642 — 앱 테스트 스테이지가 이것 때문에 상시 실패했다)
    --in-ci) IN_CI=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done
# 환경변수로도 켤 수 있게 — Jenkins 는 BUILD_ID 를 항상 준다.
[ -n "${PREFLIGHT_IN_CI:-}" ] && IN_CI=1

say()   { [ "$QUIET" = "1" ] || printf '%s\n' "$*"; }
ok()    { [ "$QUIET" = "1" ] || printf '   ✅ %s\n' "$*"; }
info()  { [ "$QUIET" = "1" ] || printf '   ·  %s\n' "$*"; }
warn()  { printf '   ⚠️  %s\n' "$*" >&2; }
block() { printf '   ⛔ %s\n' "$*" >&2; }

BLOCKED=0
WARNED=0

# ── 실행 위치 판별 ────────────────────────────────────────────────────────────
# 이 스크립트는 **호스트에서 사람이 돌리는 것**을 전제로 만들어졌다. 그런데 CI 가
# Jenkins 컨테이너 안에서 부르면 systemd·crontab·$HOME 이 전부 다른 세계다.
#   - /proc/meminfo 는 네임스페이스가 안 나뉘어 **메모리 숫자는 진짜**다.
#   - 반면 `systemctl is-active earlyoom` 은 systemd 자체가 없어 무조건 실패하고,
#     $HOME/bin 도 /var/jenkins_home/bin 이라 memory-guard 를 못 찾는다.
# → 그대로 두면 방어가 멀쩡한데 "없다"고 보고한다. 거짓 초록불의 정반대지만
#   위험은 같다: 매 빌드마다 뜨는 경고는 사람에게 "무시하는 법"을 가르친다.
#   진짜로 earlyoom 이 죽은 날에도 똑같이 보이게 된다.
IN_CONTAINER=0
if [ -f /.dockerenv ] || ! command -v systemctl >/dev/null 2>&1; then
  IN_CONTAINER=1
fi

MEM_TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
MEM_AVAIL_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
SWAP_TOTAL_MB=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
SWAP_FREE_MB=$(awk '/SwapFree/{print int($2/1024)}' /proc/meminfo)
SWAP_USED_MB=$((SWAP_TOTAL_MB - SWAP_FREE_MB))

say ""
say "═══ 메모리 사전 점검 (필요: ${NEED_MB}MB) ═══"
say "   RAM   ${MEM_AVAIL_MB}MB 가용 / ${MEM_TOTAL_MB}MB"
say "   스왑  ${SWAP_FREE_MB}MB 여유 / ${SWAP_TOTAL_MB}MB (사용중 ${SWAP_USED_MB}MB)"
say ""

# ── 1. 가용 RAM ───────────────────────────────────────────────────────────────
# 스왑 여유는 계산에 넣지 않는다. 스왑이 EBS 위라 "스왑으로 버틴다"는 곧 thrash 이고,
# 이번 사고가 정확히 그 경로였다. 판정은 실제 RAM 으로만 한다.
if [ "$MEM_AVAIL_MB" -ge "$NEED_MB" ]; then
  ok "가용 RAM ${MEM_AVAIL_MB}MB ≥ 필요 ${NEED_MB}MB"
else
  block "가용 RAM 부족: ${MEM_AVAIL_MB}MB < ${NEED_MB}MB"
  block "  → 무엇이 먹고 있는지: docker stats --no-stream / ps aux --sort=-rss | head"
  BLOCKED=1
fi

# ── 2. 스왑이 이미 잠식됐는지 ─────────────────────────────────────────────────
# 스왑을 절반 넘게 쓰고 있다면 이미 RAM 이 마른 상태로 오래 버틴 것이다.
# 여기서 무거운 작업을 더하면 남은 여유가 순식간에 사라진다.
if [ "$SWAP_TOTAL_MB" -gt 0 ] && [ "$SWAP_USED_MB" -gt $((SWAP_TOTAL_MB / 2)) ]; then
  block "스왑을 이미 절반 넘게 쓰고 있다 (${SWAP_USED_MB}/${SWAP_TOTAL_MB}MB) — 시스템이 이미 압박 상태"
  BLOCKED=1
else
  ok "스왑 사용량 정상 (${SWAP_USED_MB}/${SWAP_TOTAL_MB}MB)"
fi

# ── 3. 스왑 총량 (setup-swap.sh 실행 여부) ────────────────────────────────────
if [ "$SWAP_TOTAL_MB" -ge 15000 ]; then
  ok "스왑 ${SWAP_TOTAL_MB}MB — 확대 적용됨"
else
  warn "스왑이 ${SWAP_TOTAL_MB}MB 뿐이다 (권장 16GB). 아직 안 돌렸다면:"
  warn "  sudo bash infra/scripts/setup-swap.sh"
  WARNED=1
fi

# ── 4. earlyoom ───────────────────────────────────────────────────────────────
# ★ 이게 없으면 메모리가 마를 때 호스트가 굳는다(2026-07-28 실제 사고).
#   경고에 그치는 이유: 이것 때문에 작업 자체를 못 하게 막으면 우회 습관이 생긴다.
#   대신 문구를 강하게 남긴다.
if systemctl is-active --quiet earlyoom 2>/dev/null; then
  ok "earlyoom 실행중 — 고갈 시 호스트 대신 프로세스가 죽는다"
elif [ "$IN_CONTAINER" = "1" ]; then
  # "없다"가 아니라 "모른다". 둘을 섞으면 진짜 사고를 못 알아본다.
  info "earlyoom 확인 불가 (컨테이너 안 — systemd 미접근). 호스트에서 확인할 것"
else
  warn "earlyoom 이 없다 — 메모리가 마르면 호스트가 응답 불능이 될 수 있다(07-28 사고 재현)"
  warn "  sudo bash infra/scripts/setup-swap.sh"
  WARNED=1
fi

# ── 4-b. memory-guard 설치·최신 여부 ─────────────────────────────────────────
# 크론이 도는 것은 ~/bin 의 **복사본**이다(git 작업 트리에서 직접 돌리면 브랜치 전환 때
# 내용이 바뀌거나 사라진다). 복사본이 낡는 것을 여기서 잡는다 —
# "설치는 돼 있는데 옛날 버전이 돌고 있는" 상태가 이 저장소의 단골 실패 양상이다.
GUARD_REPO="$(dirname "$(readlink -f "$0")")/memory-guard.sh"
GUARD_INSTALLED="$HOME/bin/dodam-memory-guard.sh"
if [ -x "$GUARD_INSTALLED" ] && crontab -l 2>/dev/null | grep -q dodam-memory-guard; then
  if [ -f "$GUARD_REPO" ] && ! cmp -s "$GUARD_REPO" "$GUARD_INSTALLED"; then
    warn "memory-guard 설치본이 저장소 버전과 다르다 — infra/scripts/memory-guard.sh --install"
    WARNED=1
  else
    ok "memory-guard 설치·등록됨 (매분 감시 · WARN 알림 / CRIT 시 빌드부터 정지)"
  fi
elif [ "$IN_CONTAINER" = "1" ]; then
  # $HOME 이 /var/jenkins_home 이고 crontab 도 컨테이너 것이라 판정 자체가 성립하지 않는다.
  info "memory-guard 확인 불가 (컨테이너 안 — 호스트 \$HOME·crontab 미접근)"
else
  warn "memory-guard 미설치 — 메모리가 마를 때 알림도, 자동 정지도 없다"
  warn "  infra/scripts/memory-guard.sh --install"
  WARNED=1
fi

# ── 5. 무제한 컨테이너 ────────────────────────────────────────────────────────
# 상한 없는 컨테이너 하나가 호스트 전체를 끌고 갈 수 있다.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  UNLIMITED=""
  for c in $(docker ps --format '{{.Names}}'); do
    lim=$(docker inspect -f '{{.HostConfig.Memory}}' "$c" 2>/dev/null || echo 0)
    [ "$lim" = "0" ] && UNLIMITED="$UNLIMITED $c"
  done
  if [ -n "$UNLIMITED" ]; then
    warn "메모리 상한 없는 컨테이너:$UNLIMITED"
    warn "  → infra/docker-compose.yml 의 mem_limit 반영 후 재생성하거나,"
    warn "    즉시 적용은: docker update --memory <크기> --memory-swap <크기> <이름>"
    WARNED=1
  else
    ok "실행중 컨테이너 전부 메모리 상한 있음"
  fi

  # ── 6. Jenkins 빌드 진행중? ────────────────────────────────────────────────
  # 빌드는 단독으로 4.5GB 를 쓴다(07-28 실측). 빌드와 k3s 를 겹치면 이번 사고가 재현된다.
  # 컨테이너 이름이 무작위라 이미지로 판별한다.
  if docker ps --format '{{.Image}}' | grep -q 'testcontainers'; then
    if [ "$IN_CI" = "1" ]; then
      # ★ 자기참조 방지 (S15P11B209-642).
      #   이 검사는 "사람이 호스트에서 무거운 작업을 시작하기 전"을 위한 것이다.
      #   그런데 CI 스테이지가 빌드 **안에서** 부르면 "빌드가 돌고 있다"는 항상 참이고,
      #   "빌드가 끝난 뒤 다시 실행할 것"은 CI 에서 실행 불가능한 지시다.
      #   결과: 팀원이 동시에 푸시하기만 하면 앱 테스트 스테이지가 상시 실패했다.
      #   여기서는 사실만 알리고 막지 않는다 — RAM 검사(1번)는 그대로 유효하다.
      info "빌드 컨테이너 실행중 (CI 모드 — 자기 자신일 수 있어 차단하지 않음)"
    else
      block "Jenkins 빌드가 진행중이다 (testcontainers 실행중) — 빌드는 단독 4.5GB 를 쓴다"
      block "  → 빌드가 끝난 뒤 다시 실행할 것: docker ps --format '{{.Image}}' | grep testcontainers"
      BLOCKED=1
    fi
  else
    ok "Jenkins 빌드 미진행"
  fi
fi

say ""
if [ "$BLOCKED" -eq 1 ]; then
  printf '\033[1m⛔ 진행 금지 — 위 조건을 먼저 해소할 것\033[0m\n' >&2
  exit 1
fi
if [ "$WARNED" -eq 1 ]; then
  [ "$QUIET" = "1" ] || printf '\033[1m⚠️  진행 가능하나 방어가 미완성이다 — 위 경고 확인\033[0m\n'
else
  [ "$QUIET" = "1" ] || printf '\033[1m✅ 진행해도 좋다\033[0m\n'
fi
exit 0
