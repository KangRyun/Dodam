#!/usr/bin/env bash
# k3s 설치 전/후 상태 비교 (S15P11B209-358 · runbook 0단계·4단계 자동화)
#
# 왜 있나
#   356 runbook 의 성공 기준은 "k3s 가 떴다"가 아니라 **"k3s 를 깔았는데 기존 서비스가 그대로다"**
#   이다. 그런데 그 판정을 사람이 curl 세 줄과 docker ps 를 눈으로 비교해서 하게 되어 있었다.
#   눈으로 비교하면 놓친다 — 특히 "컨테이너 하나가 조용히 재시작됐다" 같은 것.
#   여기서는 설치 전 상태를 파일로 굳혀 두고, 설치 후 **기계가 대조**한다.
#
# 사용:
#   infra/scripts/k3s-baseline.sh capture before    # ← k3s 설치 전 (runbook 0단계)
#   ... k3s 설치 ...
#   infra/scripts/k3s-baseline.sh capture after     # ← 설치 후
#   infra/scripts/k3s-baseline.sh compare           # ← 판정 (통과 못 하면 롤백)
#
# root 불필요. 단 iptables 스냅샷만 sudo 가 필요해, 없으면 그 항목만 건너뛰고 나머지는 다 본다
#   (전부 아니면 전무로 만들면 sudo 없는 환경에서 이 스크립트를 아예 못 쓴다).

set -uo pipefail

SNAP_DIR="${SNAP_DIR:-$HOME/.local/state/dodam/k3s-baseline}"
BASE_URL="${BASE_URL:-https://i15b209.p.ssafy.io}"

ok()   { printf '   ✅ %s\n' "$*"; }
warn() { printf '   ⚠️  %s\n' "$*"; }
bad()  { printf '   🔴 %s\n' "$*"; }
bold() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die()  { printf '\n❌ %s\n' "$*" >&2; exit 1; }

mkdir -p "$SNAP_DIR"

# ─────────────────────────────────────────────────────────────────────────────
capture() {
  local label="$1"
  local d="$SNAP_DIR/$label"
  mkdir -p "$d"
  bold "상태 캡처: $label  → $d"

  # ── 1. 서비스 e2e — 이게 제일 중요하다. 나머지가 다 정상이어도 이게 바뀌면 실패다.
  #    runbook 기대값: landing 200 · ai 200 · api-401 401
  #    401 이 정상인 이유: 토큰 없이 보호 경로를 부른 것 = 인가가 살아 있다는 뜻.
  {
    printf 'landing %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$BASE_URL/")"
    printf 'ai %s\n'      "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$BASE_URL/ai/health")"
    printf 'api %s\n'     "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$BASE_URL/api/v1/users/me")"
    printf 'legal %s\n'   "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$BASE_URL/legal/")"
  } > "$d/e2e.txt"
  sed 's/^/     /' "$d/e2e.txt"

  # ── 2. 컨테이너 — 이름+상태. "하나도 죽지 않았는지"를 본다.
  #    Status 문자열에는 가동시간("Up 3 minutes")이 들어가 매번 달라지므로,
  #    비교는 이름과 상태 종류(Up/Exited/healthy)로만 한다.
  docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null \
    | sed -E 's/Up [^(]*/Up /; s/Exited \([0-9]+\).*/Exited/' \
    | sort > "$d/containers.txt"
  printf '     컨테이너 %s개\n' "$(wc -l < "$d/containers.txt")"

  # ── 3. 리슨 포트 — k3s 가 6443·10250 을 새로 잡는 건 정상이지만,
  #    기존 80/443/3306 등이 사라지면 사고다.
  (ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) \
    | awk 'NR>1 {print $4}' | grep -oE '[0-9]+$' | sort -un > "$d/ports.txt"
  printf '     리슨 포트 %s개\n' "$(wc -l < "$d/ports.txt")"

  # ── 4. iptables — sudo 필요. Docker 체인이 살아있는지 판정용.
  #    k3s(kube-proxy·flannel)가 규칙을 넣으면서 DOCKER 체인 순서를 망가뜨리는 것이 runbook 위험 1번.
  if sudo -n iptables-save > "$d/iptables.rules" 2>/dev/null; then
    printf '     iptables 규칙 %s줄\n' "$(wc -l < "$d/iptables.rules")"
  else
    rm -f "$d/iptables.rules"
    warn "iptables 스냅샷 생략 (sudo 필요) — 직접 받으려면:"
    printf '        sudo iptables-save > %s/iptables.rules\n' "$d"
  fi

  # ── 5. 메모리 — k3s 가 얼마나 먹었는지 사후 확인용(예산 재계산 근거).
  free -m | awk '/^Mem:/{print "mem_available "$7} /^Swap:/{print "swap_used "$3}' > "$d/memory.txt"
  sed 's/^/     /' "$d/memory.txt"

  date '+%F %T' > "$d/captured_at.txt"
  ok "캡처 완료"
}

# ─────────────────────────────────────────────────────────────────────────────
compare() {
  local b="$SNAP_DIR/before" a="$SNAP_DIR/after"
  [ -d "$b" ] || die "before 스냅샷이 없다 — 먼저: $0 capture before"
  [ -d "$a" ] || die "after 스냅샷이 없다 — 먼저: $0 capture after"

  bold "판정 — before($(cat "$b/captured_at.txt")) vs after($(cat "$a/captured_at.txt"))"
  local fail=0

  # ── 1. 서비스 e2e (★ 이게 틀리면 나머지는 볼 것도 없이 롤백)
  if diff -q "$b/e2e.txt" "$a/e2e.txt" >/dev/null; then
    ok "서비스 응답 동일: $(tr '\n' ' ' < "$a/e2e.txt")"
  else
    bad "서비스 응답이 바뀌었다 — 즉시 롤백 대상"
    diff "$b/e2e.txt" "$a/e2e.txt" | sed 's/^/     /'
    fail=1
  fi

  # ── 2. 컨테이너
  if diff -q "$b/containers.txt" "$a/containers.txt" >/dev/null; then
    ok "컨테이너 목록·상태 동일 ($(wc -l < "$a/containers.txt")개)"
  else
    bad "컨테이너가 변했다 (사라짐/죽음/재시작)"
    diff "$b/containers.txt" "$a/containers.txt" | sed 's/^/     /'
    fail=1
  fi

  # ── 3. 포트 — 늘어난 건 정상(k3s 6443·10250), 사라진 게 문제다.
  #    ⚠️ comm 은 **사전순** 정렬을 전제한다. ports.txt 는 사람이 읽기 좋게 숫자순(sort -un)으로
  #    저장돼 있어 그대로 넘기면 comm 이 오작동한다 — 같은 포트가 "추가"와 "사라짐"에 동시에
  #    나오는 오판이 실제로 나왔다(2026-07-29 자체 검증에서 발견). 비교 직전에 사전순으로 다시 정렬한다.
  local gone; gone=$(comm -23 <(sort "$b/ports.txt") <(sort "$a/ports.txt") | sort -n | tr '\n' ' ')
  local added; added=$(comm -13 <(sort "$b/ports.txt") <(sort "$a/ports.txt") | sort -n | tr '\n' ' ')
  [ -n "$added" ] && ok "새로 열린 포트(정상): $added"
  if [ -n "$gone" ]; then
    bad "사라진 포트: $gone — 기존 서비스가 죽었을 수 있다"
    fail=1
  else
    ok "사라진 포트 없음"
  fi

  # ── 4. iptables — 규칙 수가 느는 건 정상. DOCKER 체인 소멸이 사고다.
  if [ -f "$b/iptables.rules" ] && [ -f "$a/iptables.rules" ]; then
    printf '   규칙 수: %s → %s (증가는 정상)\n' \
      "$(wc -l < "$b/iptables.rules")" "$(wc -l < "$a/iptables.rules")"
    if grep -q '^:DOCKER ' "$a/iptables.rules"; then
      ok "DOCKER 체인 유지됨"
    else
      bad "DOCKER 체인이 사라졌다 — 컨테이너 네트워킹이 깨진다"
      fail=1
    fi
  else
    warn "iptables 비교 생략 (스냅샷 없음 — sudo 로 캡처하지 않았다)"
  fi

  # ── 5. 메모리 — 판정 대상은 아니고 참고값(k3s 실제 소비량 = 예산 재계산 근거)
  printf '   메모리: %s → %s\n' \
    "$(awk '/mem_available/{print $2"MB"}' "$b/memory.txt")" \
    "$(awk '/mem_available/{print $2"MB"}' "$a/memory.txt")"

  echo
  if [ "$fail" -eq 0 ]; then
    printf '\033[1m✅ 판정 통과 — k3s 설치가 기존 서비스를 건드리지 않았다\033[0m\n'
    return 0
  fi
  printf '\033[1m🔴 판정 실패 — runbook 롤백 절차를 실행할 것\033[0m\n'
  printf '   /usr/local/bin/k3s-uninstall.sh  후 위 항목 재확인\n'
  return 1
}

case "${1:-}" in
  capture) [ -n "${2:-}" ] || die "라벨이 필요하다: $0 capture before|after"
           capture "$2" ;;
  compare) compare ;;
  *) sed -n '2,25p' "$0"; exit 2 ;;
esac
