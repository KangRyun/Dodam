#!/usr/bin/env bash
# 도담(dodam) 메모리 감시·단계적 차단기 (S15P11B209-356)
#
# 왜 있나
#   2026-07-28 호스트 OOM 때 Prometheus 는 정상 수집 중이었다. 그런데 **아무도 몰랐다.**
#   지표가 있는 것과 누가 알아채는 것은 다르다. 이 스크립트가 그 간극을 메운다.
#
# 설계 원칙 — "모든 실행 종료"는 하지 않는다
#   임계에서 전부 죽이면 장애를 자동화하는 셈이다. 메모리 압박의 원인은 거의 항상 빌드인데
#   그 대가로 운영 스택(mysqld·backend·nginx)을 죽이면 아동 데이터를 쥔 프로세스를 강제 종료하고
#   서비스까지 끊는다. 원인이 아닌 것을 죽이는 자동화는 사고를 늘린다.
#   → **희생 순서를 미리 정해 두고, 그 순서대로만 끊는다.** 운영 스택은 어떤 경우에도 대상이 아니다.
#
# 3단계 (한 겹씩 더 강해진다)
#   WARN (가용 < 15%) : 알림만. 사람이 판단할 시간을 준다
#   CRIT (가용 < 8%)  : 희생 목록을 **순서대로 하나씩** 정지 → 매번 재측정 → 회복되면 멈춘다
#   그 아래           : earlyoom 이 커널보다 먼저 개입한다(setup-swap.sh 가 설치)
#
# 이 스크립트는 earlyoom 을 대체하지 않는다. earlyoom 은 초 단위로 반응하는 최후 방어선이고,
# 이쪽은 분 단위로 도는 "알려주고, 원인부터 골라 끊는" 층이다. 역할이 다르다.
#
# 설치 (root 불필요):
#   infra/scripts/memory-guard.sh --install     # ~/bin 에 복사 + 사용자 crontab 등록(매분)
#   infra/scripts/memory-guard.sh --status      # 설치·최신 여부 확인
#   infra/scripts/memory-guard.sh --once        # 1회 판정(크론이 부르는 형태)
#   infra/scripts/memory-guard.sh --test        # 알림 경로만 시험 발송
#
# 알림 경로: infra/.env 의 MATTERMOST_WEBHOOK. 없으면 로그에만 남기고 그 사실을 알린다
#   (조용히 안 보내는 것이 제일 나쁘다).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." 2>/dev/null && pwd)"
[ -d "$REPO_ROOT/infra" ] || REPO_ROOT="${DODAM_REPO_ROOT:-$HOME/S15P11B209}"

STATE_DIR="${STATE_DIR:-$HOME/.local/state/dodam}"
LOG="$STATE_DIR/memory-guard.log"
COOLDOWN_FILE="$STATE_DIR/memory-guard.cooldown"
INSTALL_PATH="$HOME/bin/dodam-memory-guard.sh"

WARN_PCT="${WARN_PCT:-15}"     # 알림
CRIT_PCT="${CRIT_PCT:-8}"      # 희생 시작
RECOVER_PCT="${RECOVER_PCT:-20}"   # 여기까지 회복되면 더 안 끊는다
COOLDOWN_SEC="${COOLDOWN_SEC:-900}"  # 같은 알림 재발송 간격(15분) — 스팸이 되면 아무도 안 본다
LOG_MAX_BYTES="${LOG_MAX_BYTES:-5242880}"

# ── ⚠️ 이 스크립트의 사정거리 (2026-07-30, S15P11B209-746 에서 갱신) ──────────
# 360 컷오버 이후 **운영 스택은 k3s(containerd) 로 갔다.** 이 스크립트는 `docker` 만 보므로
# backend·mysql·ai·minio 파드는 **아예 보이지 않는다** — 잡을 수도, 지킬 수도 없다.
#
# 그러니 운영 워크로드의 메모리 방어는 더 이상 여기가 아니다:
#   · k8s `resources.limits` (파드별 상한 — 초과 시 OOMKill)
#   · `ContainerMemoryNearLimit` 경보 → Alertmanager → Mattermost (S15P11B209-733)
# 이 스크립트가 지금 하는 일은 **호스트에 남은 Docker 작업(빌드류)을 끊어 호스트를 살리는 것**뿐이다.
#
# ── 절대 건드리지 않는 것 ─────────────────────────────────────────────────────
# ★ 이 목록은 **두 번째 안전망**이다. 실제 방어선은 아래 `sacrificial_list()` 의 **허용목록**이고,
#   거기에 오르지 않은 컨테이너는 애초에 후보가 되지 않는다(예: `dodam-registry` —
#   k3s 가 이미지를 받아오는 곳이라 끊기면 배포가 멈춘다. 허용목록에 없어 안전하다).
#   그래도 이중으로 남겨 둔다 — 허용목록을 넓히는 사람이 실수하지 않도록.
#
#   reason: 아동 민감정보를 다루는 서비스다(가드레일 9절). 자동화가 서비스를 끊는 것보다
#   빌드 하나가 죽는 편이 언제나 낫다.
#
# ⚠️ 2026-07-30 이전에는 여기에 compose 시절 이름(dodam-mysql·dodam-backend·dodam-nginx…)이
#   적혀 있었다. 그 컨테이너들은 07-29 23:55 에 전부 정지했으므로 **이 정규식은 아무것도
#   매치하지 않는 죽은 코드**였다. 무해했지만("지키고 있다"는 착시만 남았다) 정정한다.
PROTECTED='^(dodam-registry|dodam-jenkins-agent)$'

mkdir -p "$STATE_DIR" 2>/dev/null

log() {
  local msg="[$(date '+%F %T')] $*"
  echo "$msg" >> "$LOG" 2>/dev/null
  [ "${VERBOSE:-0}" = "1" ] && echo "$msg"
  return 0
}

rotate_log() {
  [ -f "$LOG" ] || return 0
  local sz; sz=$(stat -c '%s' "$LOG" 2>/dev/null || echo 0)
  [ "$sz" -gt "$LOG_MAX_BYTES" ] && mv -f "$LOG" "$LOG.1" 2>/dev/null
  return 0
}

mem_avail_pct() { awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%d", a*100/t}' /proc/meminfo; }
mem_avail_mb()  { awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo; }
swap_used_mb()  { awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{printf "%d", (t-f)/1024}' /proc/meminfo; }

# ── 알림 ─────────────────────────────────────────────────────────────────────
webhook_url() {
  [ -f "$REPO_ROOT/infra/.env" ] || return 1
  sed -n 's/^MATTERMOST_WEBHOOK=//p' "$REPO_ROOT/infra/.env" | head -1 | tr -d '"'"'"' \r'
}

notify() {
  local level="$1" text="$2" url
  url="$(webhook_url)"
  if [ -z "${url:-}" ]; then
    log "알림 미발송(웹훅 미설정) [$level] $text"
    log "  → infra/.env 에 MATTERMOST_WEBHOOK=<URL> 을 넣으면 발송된다"
    return 1
  fi
  # 알림 실패가 차단 동작을 막으면 안 된다 — 실패해도 계속 진행한다.
  local payload; payload=$(python3 -c '
import json,sys
print(json.dumps({"text": sys.argv[1]}))' "$text" 2>/dev/null) || payload="{\"text\":\"$level\"}"
  if curl -fsS -m 10 -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null 2>&1; then
    log "알림 발송 [$level]"
  else
    log "⚠️ 알림 발송 실패(웹훅 응답 없음) [$level] $text"
  fi
  return 0
}

cooled_down() {  # 같은 등급 알림을 COOLDOWN_SEC 안에 또 보내지 않는다
  local level="$1" now last
  now=$(date +%s)
  last=$(sed -n "s/^${level}=//p" "$COOLDOWN_FILE" 2>/dev/null | head -1)
  [ -z "${last:-}" ] && return 1
  [ $((now - last)) -lt "$COOLDOWN_SEC" ]
}
mark_sent() {
  local level="$1" now; now=$(date +%s)
  { grep -v "^${level}=" "$COOLDOWN_FILE" 2>/dev/null; echo "${level}=${now}"; } > "$COOLDOWN_FILE.tmp" 2>/dev/null \
    && mv -f "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE" 2>/dev/null
  return 0
}

top_consumers() {
  docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null \
    | sort -k2 -hr | head -4 | sed 's/^/  - /'
}

# ── 희생 목록 (끊는 순서) ─────────────────────────────────────────────────────
# 앞에서부터 하나씩 끊고, 끊을 때마다 다시 잰다. 회복되면 거기서 멈춘다.
#   1) AAB 빌더 컨테이너 — 원인일 가능성이 가장 높고, 다시 돌리면 그만이다
#   2) Testcontainers — 빌드 중 임시 DB. 끊으면 그 빌드만 실패한다
#   3) Jenkins — 이 서버 최대 소비자. 마지막 수단(빌드 이력·설정은 볼륨에 남는다)
sacrificial_list() {
  {
    # 1) AAB 빌더 — 이미지 이름으로 판별(컨테이너 이름은 docker create 가 무작위로 붙인다)
    docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null \
      | awk '$2 ~ /flutter-builder/ {print "1 " $1}'

    # 2) Testcontainers — ★이미지가 아니라 **라벨**로 잡는다.
    #    실측(07-28): 메모리를 먹는 쪽은 `mysql:8.4.10` 이라 이미지에 'testcontainers' 가 없다.
    #    이미지 이름으로 거르면 reaper(ryuk)만 걸리고 정작 큰 놈들(개당 약 330MB)을 놓친다.
    #    Testcontainers 는 자기가 만든 컨테이너 전부에 org.testcontainers=true 를 붙인다.
    #    ⚠️ 여기서 mysql:8.4.10 을 이미지로 매칭하면 **운영 dodam-mysql 까지 잡힌다** — 절대 금지.
    docker ps --filter 'label=org.testcontainers=true' --format '{{.Names}}' 2>/dev/null \
      | awk '{print "2 " $1}'

    # 3) Jenkins — 이 서버 최대 소비자. 마지막 수단(설정·빌드 이력은 볼륨에 남는다)
    docker ps --format '{{.Names}}' 2>/dev/null | awk '$1=="dodam-jenkins" {print "3 " $1}'
  } | sort -n -k1,1 | awk '{print $2}'
}

do_once() {
  rotate_log
  local pct mb swap
  pct=$(mem_avail_pct); mb=$(mem_avail_mb); swap=$(swap_used_mb)

  if [ "$pct" -ge "$WARN_PCT" ]; then
    log "정상 (가용 ${pct}% / ${mb}MB, 스왑사용 ${swap}MB)"
    return 0
  fi

  # ── CRIT: 순서대로 끊는다 ───────────────────────────────────────────────
  if [ "$pct" -lt "$CRIT_PCT" ]; then
    log "🔴 CRIT 가용 ${pct}% (${mb}MB) — 희생 목록 순서대로 정지 시작"
    local stopped=() name after
    while read -r name; do
      [ -z "$name" ] && continue
      if echo "$name" | grep -qE "$PROTECTED"; then
        log "  건너뜀(보호 대상): $name"; continue
      fi
      log "  정지: $name"
      docker stop -t 20 "$name" >/dev/null 2>&1 && stopped+=("$name")
      sleep 3
      after=$(mem_avail_pct)
      log "  → 가용 ${after}%"
      if [ "$after" -ge "$RECOVER_PCT" ]; then
        log "  회복(${after}% ≥ ${RECOVER_PCT}%) — 여기서 멈춘다"; break
      fi
    done < <(sacrificial_list)

    after=$(mem_avail_pct)
    if [ ${#stopped[@]} -eq 0 ]; then
      log "  ⚠️ 끊을 수 있는 대상이 없다 — 남은 소비자는 전부 보호 대상이거나 호스트 프로세스다"
      notify CRIT "$(printf '🔴 **메모리 위험** 가용 %d%% (%dMB) · 스왑사용 %dMB\n끊을 수 있는 희생 대상이 없다 — 보호 대상만 남았다. 사람이 봐야 한다.\n%s' \
        "$pct" "$mb" "$swap" "$(top_consumers)")"
    else
      notify CRIT "$(printf '🔴 **메모리 위험 — 자동 정지 실행** 가용 %d%% → %d%%\n정지: %s\n(운영 스택은 대상이 아니다. 원인 확인 후 재기동할 것)' \
        "$pct" "$after" "${stopped[*]}")"
    fi
    mark_sent CRIT
    return 0
  fi

  # ── WARN: 알림만 ────────────────────────────────────────────────────────
  log "⚠️ WARN 가용 ${pct}% (${mb}MB, 스왑사용 ${swap}MB)"
  if cooled_down WARN; then
    log "  (쿨다운 중 — 알림 생략)"
  else
    notify WARN "$(printf '⚠️ **메모리 주의** 가용 %d%% (%dMB) · 스왑사용 %dMB\n가용 %d%% 밑으로 더 떨어지면 빌드부터 자동 정지된다.\n%s' \
      "$pct" "$mb" "$swap" "$CRIT_PCT" "$(top_consumers)")"
    mark_sent WARN
  fi
  return 0
}

# ── 설치 ─────────────────────────────────────────────────────────────────────
# ⚠️ 크론이 **git 작업 트리의 스크립트를 직접 실행하면** 브랜치를 바꿀 때 내용이 바뀌거나
#    파일이 사라진다(이 저장소에서 이미 겪은 함정). 그래서 ~/bin 으로 **복사**해 실행한다.
#    복사본이 낡는 문제는 preflight-memory.sh 가 체크섬으로 잡아준다.
do_install() {
  mkdir -p "$HOME/bin" "$STATE_DIR"
  cp -f "$(readlink -f "${BASH_SOURCE[0]}")" "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
  echo "✅ 복사: $INSTALL_PATH"

  local entry="* * * * * DODAM_REPO_ROOT=$REPO_ROOT $INSTALL_PATH --once >/dev/null 2>&1"
  if crontab -l 2>/dev/null | grep -qF "dodam-memory-guard.sh"; then
    crontab -l 2>/dev/null | grep -vF "dodam-memory-guard.sh" | { cat; echo "$entry"; } | crontab -
    echo "✅ crontab 갱신(매분)"
  else
    { crontab -l 2>/dev/null; echo "$entry"; } | crontab -
    echo "✅ crontab 등록(매분)"
  fi
  echo
  echo "확인: $0 --status"
  echo "로그: $LOG"
}

do_status() {
  echo "═══ memory-guard 상태 ═══"
  local pct; pct=$(mem_avail_pct)
  echo "  현재 가용 ${pct}% ($(mem_avail_mb)MB) · 스왑사용 $(swap_used_mb)MB"
  echo "  임계: WARN<${WARN_PCT}% · CRIT<${CRIT_PCT}% · 회복 ${RECOVER_PCT}%"
  if [ -x "$INSTALL_PATH" ]; then
    if [ "$(sha256sum < "$INSTALL_PATH")" = "$(sha256sum < "$(readlink -f "${BASH_SOURCE[0]}")")" ]; then
      echo "  ✅ 설치됨 · 저장소 버전과 동일"
    else
      echo "  ⚠️ 설치본이 저장소 버전과 다르다 — $0 --install 로 갱신할 것"
    fi
  else
    echo "  ⛔ 미설치 — $0 --install"
  fi
  crontab -l 2>/dev/null | grep -q dodam-memory-guard && echo "  ✅ crontab 등록됨(매분)" || echo "  ⛔ crontab 미등록"
  if webhook_url >/dev/null && [ -n "$(webhook_url)" ]; then
    echo "  ✅ 알림 경로: Mattermost 웹훅 설정됨"
  else
    echo "  ⚠️ 알림 경로 없음 — infra/.env 에 MATTERMOST_WEBHOOK=<URL> 필요(현재는 로그만 남는다)"
  fi
  [ -f "$LOG" ] && { echo "  최근 로그:"; tail -3 "$LOG" | sed 's/^/    /'; }
}

case "${1:---once}" in
  --once)    do_once ;;
  --install) do_install ;;
  --status)  do_status ;;
  --test)    notify TEST "🧪 도담 memory-guard 알림 시험 — 이 메시지가 보이면 경로가 살아 있다." \
               && echo "발송 시도 완료(로그: $LOG)" ;;
  --loop)    while :; do do_once; sleep "${2:-30}"; done ;;
  -h|--help) sed -n '2,40p' "$0" ;;
  *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
esac
