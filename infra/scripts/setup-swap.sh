#!/usr/bin/env bash
# 도담(dodam) 호스트 메모리 방어 — 스왑 확대 + 커널 튜닝 + earlyoom (S15P11B209-356)
#
# 배경 (2026-07-28 실제 사고)
#   k3s 세팅 중 메모리가 고갈돼 EC2 가 응답 불능이 됐고 재부팅으로만 복구됐다.
#   당시 구성: RAM 15.6GB · 스왑 4GB · **모든 컨테이너 메모리 무제한** · earlyoom 없음.
#   리눅스는 메모리가 마르면 곧바로 프로세스를 죽이지 않고 페이지 회수에 매달린다.
#   스왑이 EBS(네트워크 디스크) 위라 회수가 느려 시스템 전체가 thrash 상태로 굳는다 —
#   "죽지도 살지도 않는" 상태가 되어 SSH 조차 안 붙는다. 재부팅 외 복구 수단이 없다.
#
# 이 스크립트가 막는 것 (세 겹)
#   1) 스왑 4GB → 16GB : 한계 순간에 버틸 시간을 번다 (근본 해결 아님 — 시간 벌기)
#   2) 커널 워터마크 상향 : kswapd 가 더 일찍 회수를 시작해 thrash 진입 자체를 늦춘다
#   3) earlyoom          : ★핵심. 커널이 굳기 **전에** 가장 큰 프로세스를 골라 죽인다.
#                          "서버가 멈춤" → "프로세스 하나가 죽고 서버는 산다"로 바꾼다.
#
#   ⚠️ 1·2 만으로는 이번 사고가 재발한다. 스왑을 늘리면 굳기까지 더 오래 걸릴 뿐이다.
#      실제 복구력은 3(earlyoom)에서 나온다.
#
# 실행 (root 필요 — 이 세션의 claude 는 sudo 암호가 없어 실행하지 못한다):
#   sudo bash infra/scripts/setup-swap.sh
#   sudo bash infra/scripts/setup-swap.sh --size 24    # 스왑 크기를 바꾸고 싶을 때(GB)
#
# 몇 번을 다시 돌려도 안전하다(멱등). 이미 적용된 항목은 건너뛴다.
# 운영 스택이 떠 있는 상태로 돌려도 된다 — 컨테이너를 만지지 않는다.

set -euo pipefail

SWAP_GB="${SWAP_GB:-16}"
SWAPFILE="${SWAPFILE:-/swapfile}"
SYSCTL_CONF="/etc/sysctl.d/99-dodam-memory.conf"
EARLYOOM_CONF="/etc/default/earlyoom"

while [ $# -gt 0 ]; do
  case "$1" in
    --size) SWAP_GB="$2"; shift 2 ;;
    --no-earlyoom) SKIP_EARLYOOM=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
  esac
done
SKIP_EARLYOOM="${SKIP_EARLYOOM:-0}"

bold() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { printf '   ✅ %s\n' "$*"; }
warn() { printf '   ⚠️  %s\n' "$*"; }
die()  { printf '\n❌ %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "root 로 실행해야 한다 — sudo bash $0"

# ─────────────────────────────────────────────────────────────────────────────
bold "0. 현재 상태"
free -h
swapon --show || echo "   (활성 스왑 없음)"

MEM_TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
MEM_AVAIL_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
SWAP_USED_MB=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print int((t-f)/1024)}' /proc/meminfo)
echo "   RAM 총 ${MEM_TOTAL_MB}MB / 가용 ${MEM_AVAIL_MB}MB · 스왑 사용중 ${SWAP_USED_MB}MB"

# ─────────────────────────────────────────────────────────────────────────────
bold "1. /etc/fstab 스왑 항목 정리"
# 2026-07-28 실측: '/swapfile none swap sw 0 0' 이 **두 줄** 중복돼 있었다.
#   부팅 때 두 번째 swapon 이 실패하지만 치명적이진 않다. 그래도 남겨두면
#   "왜 스왑이 두 개지?" 하는 오진을 부르고, 아래 크기 변경 로직도 헷갈린다.
FSTAB_BAK="/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
cp -a /etc/fstab "$FSTAB_BAK"
ok "백업: $FSTAB_BAK"

# swap 항목만 뽑아 중복 제거 후 되쓴다. swap 이 아닌 줄(루트·부팅 파티션)은 손대지 않는다.
python3 - "$SWAPFILE" <<'PY'
import sys, re
swapfile = sys.argv[1]
path = "/etc/fstab"
lines = open(path).read().splitlines()
out, seen_swap = [], False
for ln in lines:
    fields = ln.split()
    is_swap_entry = (
        len(fields) >= 3 and not ln.lstrip().startswith("#")
        and fields[2] == "swap" and fields[0] == swapfile
    )
    if is_swap_entry:
        if seen_swap:
            continue          # 중복 — 버린다
        seen_swap = True
    out.append(ln)
if not seen_swap:
    out.append(f"{swapfile} none swap sw 0 0")
open(path, "w").write("\n".join(out) + "\n")
print(f"   fstab swap 항목 정규화 완료 (중복 제거, 1줄 유지)")
PY

# ─────────────────────────────────────────────────────────────────────────────
bold "2. 스왑 ${SWAP_GB}GB 로 조정"

CUR_BYTES=0
[ -f "$SWAPFILE" ] && CUR_BYTES=$(stat -c '%s' "$SWAPFILE")
WANT_BYTES=$((SWAP_GB * 1024 * 1024 * 1024))

if [ "$CUR_BYTES" -eq "$WANT_BYTES" ] && swapon --show=NAME --noheadings | grep -qx "$SWAPFILE"; then
  ok "이미 ${SWAP_GB}GB 로 활성 — 건너뜀"
else
  # 디스크 여유 확인. 스왑 파일 + 최소 20GB 여유는 남긴다(빌드 산출물·도커 이미지용).
  AVAIL_KB=$(df --output=avail -k / | tail -1)
  NEED_KB=$(( (WANT_BYTES / 1024) - (CUR_BYTES / 1024) + 20 * 1024 * 1024 ))
  [ "$AVAIL_KB" -ge "$NEED_KB" ] || die "디스크 부족: 가용 $((AVAIL_KB/1024/1024))GB, 필요 $((NEED_KB/1024/1024))GB"

  # ★ 스왑을 내리면 스왑에 있던 페이지가 전부 RAM 으로 돌아온다.
  #   RAM 여유보다 스왑 사용량이 크면 이 순간에 OOM 이 난다 — 고치려다 사고를 낸다.
  if [ "$SWAP_USED_MB" -gt 0 ]; then
    [ "$MEM_AVAIL_MB" -gt $((SWAP_USED_MB + 1024)) ] \
      || die "스왑에 ${SWAP_USED_MB}MB 가 올라가 있는데 RAM 여유가 ${MEM_AVAIL_MB}MB 뿐이다.
   지금 swapoff 하면 그 자리에서 OOM 이 난다. 부하가 없는 시간에 다시 실행할 것."
    warn "스왑 사용중 ${SWAP_USED_MB}MB → RAM 으로 회수하며 내린다(수십 초 걸릴 수 있음)"
  fi

  swapoff "$SWAPFILE" 2>/dev/null || true
  rm -f "$SWAPFILE"

  echo "   ${SWAP_GB}GB 파일 생성중…"
  # fallocate 가 빠르다(수 초). 다만 ext4 의 unwritten extent 를 swapon 이 거부하는
  # 경우가 있어, 실패하면 dd 로 실제 기록해 되돌린다. "빠른 길 먼저, 확실한 길 폴백".
  if fallocate -l "${SWAP_GB}G" "$SWAPFILE" 2>/dev/null; then
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
    if ! swapon "$SWAPFILE" 2>/dev/null; then
      warn "fallocate 산출물을 swapon 이 거부 → dd 로 재생성(수 분)"
      rm -f "$SWAPFILE"
      dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_GB * 1024)) status=progress
      chmod 600 "$SWAPFILE"
      mkswap "$SWAPFILE" >/dev/null
      swapon "$SWAPFILE"
    fi
  else
    dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_GB * 1024)) status=progress
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
    swapon "$SWAPFILE"
  fi
  ok "스왑 활성화 완료"
fi

# ─────────────────────────────────────────────────────────────────────────────
bold "3. 커널 메모리 파라미터"
cat > "$SYSCTL_CONF" <<'EOF'
# 도담 호스트 메모리 방어 (S15P11B209-356) — 2026-07-28 k3s OOM 사고 대응
# 이 파일은 infra/scripts/setup-swap.sh 가 생성한다. 직접 고치지 말고 스크립트를 고칠 것.

# 스왑을 조금 더 적극적으로 쓴다(기본 60, 종전 10 → 20).
#   reason: 10 은 "웬만하면 RAM 유지"라 여유가 급격히 마를 때 한꺼번에 회수하려다 굳는다.
#   20 은 차갑게 식은 익명 페이지를 미리 내보내 급락 구간을 완만하게 만든다.
#   ※ 스왑이 EBS(네트워크 디스크)라 크게 올리면 오히려 IO 로 느려진다 — 20 이 절충점.
vm.swappiness = 20

# 커널이 항상 남겨두는 예비 메모리 (66MB → 256MB).
#   reason: 예비가 얇으면 원자적 할당(네트워크·드라이버)이 실패하며 stall 이 겹쳐 굳는다.
vm.min_free_kbytes = 262144

# kswapd 회수 시작 지점을 앞당긴다 (기본 10 = 0.1%, → 200 = 2%).
#   reason: ★이번 사고의 핵심. 기본값은 "거의 다 쓸 때까지" 기다렸다가 회수를 시작해
#   회수 속도가 소비 속도를 못 따라가는 순간 thrash 로 진입한다. 미리 시작하면 여유가 생긴다.
vm.watermark_scale_factor = 200

# 디렉터리/inode 캐시 회수 성향 — 기본 유지(명시적으로 박아 둔다).
vm.vfs_cache_pressure = 100

# 오버커밋은 휴리스틱(기본) 유지.
#   reason: 2(strict)로 바꾸면 JVM·Go 런타임의 대형 예약 할당이 거부돼 앱이 뜨지 않는다.
#   메모리 고갈 방어는 earlyoom 이 담당한다 — 여기서 조이지 않는다.
vm.overcommit_memory = 0

# OOM 시 커널 패닉 금지(기본) — 프로세스만 죽고 호스트는 살아남아야 한다.
vm.panic_on_oom = 0
EOF
sysctl -p "$SYSCTL_CONF"
ok "적용: $SYSCTL_CONF"

# ─────────────────────────────────────────────────────────────────────────────
bold "4. earlyoom (★ 실제 복구력은 여기서 나온다)"
if [ "$SKIP_EARLYOOM" = "1" ]; then
  warn "--no-earlyoom 지정 — 건너뜀"
else
  if ! command -v earlyoom >/dev/null 2>&1; then
    echo "   apt 로 설치중…"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "apt-get update 실패(네트워크?) — 설치를 계속 시도한다"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq earlyoom \
      || die "earlyoom 설치 실패. 네트워크·apt 소스를 확인할 것.
   설치 없이 계속하려면: sudo bash $0 --no-earlyoom
   (단, 그 경우 이번 사고의 재발을 막는 핵심 장치가 빠진다)"
  fi

  cat > "$EARLYOOM_CONF" <<'EOF'
# 도담 earlyoom 설정 (S15P11B209-356) — infra/scripts/setup-swap.sh 가 생성
#
# 무엇을 하나: 메모리·스왑 여유가 임계 아래로 떨어지면 커널이 굳기 **전에**
#   earlyoom 이 가장 큰 프로세스에 SIGTERM(→ 더 나빠지면 SIGKILL)을 보낸다.
#   서버가 멈추는 대신 프로세스 하나가 죽는다. 그게 이 도구의 전부이자 목적이다.
#
# -m 10,5 : 가용 RAM 이 10% 미만이면 TERM, 5% 미만이면 KILL (15.6GB 기준 약 1.6GB / 0.8GB)
# -s 10,5 : 스왑도 함께 임계 미만일 때만 발동 — 스왑이 넉넉하면 성급히 죽이지 않는다
# -r 3600 : 1시간마다 현재 최대 메모리 프로세스를 syslog 에 기록(사후 분석용)
#
# --avoid : 죽으면 서비스가 무너지는 것들. 여기 있어도 '마지막 수단'으로는 선택될 수 있다.
#   dockerd/containerd 를 죽이면 컨테이너 전체가 날아가고, mysqld 는 아동 데이터를 쥐고 있다.
#   sshd 가 죽으면 원격 복구 수단 자체가 사라진다(이번 사고에서 겪은 그 상황).
# --prefer : 죽어도 되는 것들 — 빌드·실험 프로세스. 다시 돌리면 그만이다.
#   gradle/kotlin = 백엔드 빌드, dart/flutter = 앱 AAB 빌드, k3s = 아직 실험 단계.
#   ※ java 는 넣지 않았다 — 백엔드(운영)와 Jenkins(빌드)가 둘 다 java 라 구분되지 않는다.
EARLYOOM_ARGS="-m 10,5 -s 10,5 -r 3600 --avoid '^(systemd|sshd|dockerd|containerd|mysqld|nginx|redis-server)$' --prefer '^(gradle|kotlin.*|dart|flutter.*|k3s.*|node|python3)$'"
EOF

  systemctl enable earlyoom >/dev/null 2>&1 || true
  systemctl restart earlyoom
  ok "earlyoom 활성화"
fi

# ─────────────────────────────────────────────────────────────────────────────
bold "5. 검증 — '설정했다'가 아니라 '동작한다'를 본다"
FAIL=0

SWAP_NOW_GB=$(awk '/SwapTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo)
if [ "$SWAP_NOW_GB" -ge "$SWAP_GB" ]; then ok "스왑 ${SWAP_NOW_GB}GB 활성"; else warn "스왑이 ${SWAP_NOW_GB}GB 뿐 (기대 ${SWAP_GB}GB)"; FAIL=1; fi

for kv in "vm.swappiness=20" "vm.min_free_kbytes=262144" "vm.watermark_scale_factor=200"; do
  k="${kv%%=*}"; want="${kv##*=}"; got=$(sysctl -n "$k")
  if [ "$got" = "$want" ]; then ok "$k = $got"; else warn "$k = $got (기대 $want)"; FAIL=1; fi
done

if [ "$SKIP_EARLYOOM" != "1" ]; then
  if systemctl is-active --quiet earlyoom; then
    ok "earlyoom 실행중 — $(systemctl show earlyoom -p MainPID --value) "
  else
    warn "earlyoom 이 실행중이 아니다: systemctl status earlyoom"; FAIL=1
  fi
fi

# 재부팅 후에도 유지되는지 = fstab 에 정확히 1줄
SWAP_LINES=$(grep -c "^${SWAPFILE}[[:space:]]" /etc/fstab || true)
if [ "$SWAP_LINES" = "1" ]; then ok "fstab 스왑 항목 1줄 — 재부팅 후에도 유지"; else warn "fstab 스왑 항목이 ${SWAP_LINES}줄"; FAIL=1; fi

echo
free -h
echo
[ "$FAIL" -eq 0 ] && printf '\033[1m✅ 완료 — 검증 전부 통과\033[0m\n' \
                  || printf '\033[1m⚠️  완료했으나 확인이 필요한 항목이 있다(위 ⚠️ 참조)\033[0m\n'
echo
echo "다음: 무거운 작업(k3s 설치·AAB 빌드·k6) 전에는 아래로 사전 점검할 것"
echo "  infra/scripts/preflight-memory.sh"
