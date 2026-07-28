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
while [ $# -gt 0 ]; do
  case "$1" in
    --need)  NEED_MB="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done

say()   { [ "$QUIET" = "1" ] || printf '%s\n' "$*"; }
ok()    { [ "$QUIET" = "1" ] || printf '   ✅ %s\n' "$*"; }
warn()  { printf '   ⚠️  %s\n' "$*" >&2; }
block() { printf '   ⛔ %s\n' "$*" >&2; }

BLOCKED=0
WARNED=0

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
else
  warn "earlyoom 이 없다 — 메모리가 마르면 호스트가 응답 불능이 될 수 있다(07-28 사고 재현)"
  warn "  sudo bash infra/scripts/setup-swap.sh"
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
    block "Jenkins 빌드가 진행중이다 (testcontainers 실행중) — 빌드는 단독 4.5GB 를 쓴다"
    block "  → 빌드가 끝난 뒤 다시 실행할 것: docker ps --format '{{.Image}}' | grep testcontainers"
    BLOCKED=1
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
