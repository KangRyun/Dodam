#!/usr/bin/env bash
# ============================================================================
# infra/cron/lib.sh — 컷백(compose) 기간 정기작업 공통 라이브러리 (source 전용)
#
# 무엇을: k3s 를 내리면 함께 멈추는 k8s CronJob 4종을 호스트 cron + 셸 스크립트로
#         옮기기 위한 공통 부분(권한 검사·패스프레이즈·잠금·암호화·보관정리·로그).
# 왜:     백업과 TLS 갱신은 클러스터가 아니라 **데이터의 요구사항**이다. 운영 형태가
#         k3s → compose 로 바뀌었다고 아동 데이터의 보관·복구력이 비는 것은 허용되지
#         않는다(CLAUDE.md 9절).
#
# ⚠️ 이 스크립트들은 **호스트에서** 돈다. 컨테이너 안(예: Jenkins)에서 실행하지 말 것 —
#    `docker run -v "$STAGE:/stage"` 의 소스는 항상 **호스트 경로**로 해석되므로,
#    컨테이너 안 경로를 넘기면 도커가 호스트에 빈 디렉터리를 만들어 붙인다.
#    (2026-07-22 빈 conf 사고 · 2026-07-26 minio-init exit 127 과 같은 함정)
#
# ── 원본과의 관계 ───────────────────────────────────────────────────────────
# 번역 원본은 `infra/k8s/base/cronjobs.yaml` 이고, **관측 가능한 계약을 전부 보존**한다:
#   · 스케줄(KST) · 파일명 규약 · STAMP 형식 · 암호화 파라미터 · 보관 14일
#   · mongo 3분기 판정(collections=0 FAIL / bytes<200 FAIL / documents=0 WARN)
#   · minio `--exclude "tts-cache/*"` · tar 레이아웃
# 그래야 기존 복원 절차(mysql-restore.sh · minio-restore.sh)가 산출물에 그대로 먹는다.
#
# ── 종료 코드 (기존 호스트 스크립트 353/622 규약을 그대로 재사용) ─────────────
#   0 성공 / 2 root 아님 / 3 패스프레이즈 문제 / 4 백업 디렉터리·잠금 문제
#   5 대상 컨테이너 미기동 / 6 덤프·암호화 파이프라인 실패
# ============================================================================

# cron 의 PATH 는 최소(/usr/bin:/bin)다. docker(/usr/bin) 는 있지만 flock·openssl 경로가
#   배포판마다 갈리므로 여기서 못 박는다. 이걸 빠뜨리면 "command not found"(127)가 나서
#   위 종료코드 표와 어긋난 진단을 하게 된다.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ★ TZ 고정. k8s CronJob 은 `timeZone: Asia/Seoul` 로 **스케줄 해석**을 KST 로 맞추고,
#   컨테이너 `TZ=Asia/Seoul` 로 **파일명 STAMP** 를 KST 로 맞췄다(두 개는 다른 장치다).
#   호스트는 이미 KST 이지만 명시한다 — 서버 TZ 가 바뀌어도 파일명 규약이 흔들리지 않게.
export TZ="${TZ:-Asia/Seoul}"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/dodam}"     # k8s hostPath 와 동일 경로(복원 절차 한 벌 유지)
RETENTION_DAYS="${RETENTION_DAYS:-14}"             # 원본 `-mtime +14` 와 동일
COMPOSE_NETWORK="${COMPOSE_NETWORK:-dodam_dodam-net}"

# ★ 패스프레이즈 파일 — 컷백에서 가장 조심할 값.
#   원본 CronJob 은 k8s Secret `dodam-backup` 의 BACKUP_PASSPHRASE 를 `-pass env:` 로 썼다.
#   k3s 를 내리면 kubectl 로 꺼낼 수 없으므로 **컷오버 전에** 호스트로 빼 둔 파일을 쓴다.
#
#   ⚠️ `-pass file:` 은 파일의 **첫 줄**을 읽고 줄바꿈을 버린다. Secret 값(44바이트, 개행 없음)과
#     같은 결과가 되며, 이는 기존 복원 스크립트(mysql-restore.sh·minio-restore.sh)가 이미
#     쓰고 있는 방식과 동일하다. 즉 이 파일로 만든 백업은 기존 절차로 그대로 복원된다.
#     반대로 파일에 값 앞뒤로 다른 줄이 섞이면 **조용히 다른 키**가 된다 — 복원 불가.
#   ⚠️ 값을 잃으면 기존 백업 전부가 복호화 불가다. 앱 비밀과 수명주기가 다른 이유가 이것이다.
PASS_FILE="${PASS_FILE:-/home/kr/.dodam-backup-pass}"

JOB_NAME="${JOB_NAME:-dodam-cron}"

# ── 로그 ────────────────────────────────────────────────────────────────────
# stdout(= cron 리다이렉트 대상)과 journald 양쪽에 남긴다.
#   reason: cron 메일이 꺼져 있어도(MAILTO="") journald 에는 남아 `journalctl -t dodam-db-backup`
#   으로 조회된다. 로그 파일만 두면 회전·삭제 시 이력이 통째로 사라진다.
log()  { printf '%s %s\n' "$(date '+%F %T')" "$*"; command -v logger >/dev/null 2>&1 && logger -t "$JOB_NAME" -- "$*" || true; }
warn() { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; command -v logger >/dev/null 2>&1 && logger -p user.warning -t "$JOB_NAME" -- "$*" || true; }
die()  { local code="$1"; shift; printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; command -v logger >/dev/null 2>&1 && logger -p user.err -t "$JOB_NAME" -- "$*" || true; exit "$code"; }

# ── 관문 ────────────────────────────────────────────────────────────────────

require_root() {
  # /var/backups/dodam 이 root 700 이고 패스프레이즈도 root 만 읽게 두는 것이 전제다.
  # 일반 계정이 탈취돼도 백업을 복호화할 수 없게 하려는 설계(353 의 규정을 그대로 승계).
  [ "$(id -u)" = "0" ] || die 2 "[$JOB_NAME] FAIL root 로 실행해야 합니다 (현재 uid=$(id -u))"
}

require_pass_file() {
  # ★ 여기서 fail-fast 하는 것이 이 라이브러리에서 가장 중요한 한 줄이다.
  #   패스프레이즈가 없을 때 "그냥 무암호로라도 백업을 남기는" 폴백을 절대 두지 않는다.
  #   아동 그림·음성·대화 원문이 들어가는 파일이다 — 암호화 없는 산출물은 백업이 아니라 사고다.
  [ -f "$PASS_FILE" ] || die 3 "[$JOB_NAME] FAIL 패스프레이즈 파일이 없습니다: $PASS_FILE
   → 컷오버 프리플라이트에서 k8s Secret dodam-backup 을 빼두는 절차를 수행했는지 확인할 것.
     (infra/cron/README.md §2)"
  [ -s "$PASS_FILE" ] || die 3 "[$JOB_NAME] FAIL 패스프레이즈 파일이 비었습니다: $PASS_FILE"
  # 첫 줄이 비어 있으면 `-pass file:` 이 빈 암호로 암호화한다 — 파일은 생기고 복원은 안 된다.
  [ -n "$(head -n 1 "$PASS_FILE")" ] || die 3 "[$JOB_NAME] FAIL 패스프레이즈 첫 줄이 비었습니다: $PASS_FILE"
  # 권한은 경고만 한다(막지 않는다) — 권한이 느슨하다고 백업을 아예 안 남기는 편이 더 위험하다.
  local mode; mode="$(stat -c %a "$PASS_FILE")"
  case "$mode" in 600|400) : ;; *) warn "[$JOB_NAME] WARN 패스프레이즈 파일 권한이 $mode 입니다 — 600 을 권장합니다: $PASS_FILE" ;; esac
}

require_backup_dir() {
  [ -d "$BACKUP_DIR" ] || die 4 "[$JOB_NAME] FAIL 백업 디렉터리가 없습니다: $BACKUP_DIR
   → sudo install -d -m 700 -o root -g root $BACKUP_DIR"
  [ -w "$BACKUP_DIR" ] || die 4 "[$JOB_NAME] FAIL 백업 디렉터리에 쓸 수 없습니다: $BACKUP_DIR"
}

require_container() {
  # "컨테이너가 있다"가 아니라 **"돌고 있다"** 를 본다.
  #   2026-07-30(732) 교훈: 대상이 옮겨갔는데 스크립트가 옛 컨테이너를 보고 있으면,
  #   암호화되고 크기도 정상이고 보관 정책도 도는데 **내용만 틀린** 백업이 매일 쌓인다.
  #   복원해야 하는 날에야 안다. 그래서 대상 부재는 성공이 아니라 실패다.
  local c="$1"
  local st; st="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)"
  [ "$st" = "running" ] || die 5 "[$JOB_NAME] FAIL 컨테이너가 실행 중이 아닙니다: $c (status=$st)
   → docker compose -f infra/docker-compose.yml --env-file infra/.env.compose ps"
}

# ── 동시 실행 방지 (k8s concurrencyPolicy: Forbid 대응) ───────────────────────
# 이전 회차가 안 끝났으면 이번 회차를 **건너뛴다(exit 0)**. 실패로 보지 않는 이유:
#   Forbid 의 의미가 "겹치면 이번 것을 버린다"이지 "장애"가 아니기 때문이다.
#   다만 로그에는 남긴다 — 매번 건너뛰고 있다면 그건 그것대로 조사 대상이다.
acquire_lock() {
  local lock="/var/lock/dodam-${JOB_NAME}.lock"
  exec 9>"$lock" || die 4 "[$JOB_NAME] FAIL 잠금 파일을 열 수 없습니다: $lock"
  flock -n 9 || { log "[$JOB_NAME] SKIP 이전 회차가 아직 실행 중입니다(concurrencyPolicy: Forbid 대응)"; exit 0; }
}

# ── 암호화 ──────────────────────────────────────────────────────────────────
# 원본 CronJob·기존 호스트 스크립트·복원 스크립트가 **모두 같은 파라미터**를 쓴다.
#   openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000
# 하나라도 바꾸면 그 시점 이후 산출물만 복원 절차가 달라진다 — 절대 손대지 말 것.
# 표준입력을 받아 $1 로 쓴다.
encrypt_to() {
  openssl enc -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -out "$1"
}

# 산출물이 실제로 **복호화되는지** 확인한다(--verify 로만 실행).
#   "백업이 돌았다"는 검증이 아니다. 복원되는 것만이 검증이다(733 의 규정).
#   상시로 돌리지 않는 이유: 전량 복호화라 비용이 크고, 원본 CronJob 에도 없던 단계다.
#   컷백 직후 1회, 그리고 하루를 넘기면 다시 한 번 수동으로 돌릴 것.
verify_backup() {   # $1=파일  $2=gz|tar
  local f="$1" kind="$2"
  case "$kind" in
    gz)  openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -in "$f" | gzip -t ;;
    tar) openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -iter 200000 -pass "file:${PASS_FILE}" -in "$f" | tar -tzf - >/dev/null ;;
    *)   return 2 ;;
  esac
}

# ── 보관 정리 ───────────────────────────────────────────────────────────────
# 원본과 동일한 패턴·기간. 패턴이 갈리면 기존 산출물을 아무도 정리하지 않고 무한 적재된다.
prune_old() {   # $1=glob 패턴
  find "$BACKUP_DIR" -maxdepth 1 -name "$1" -mtime "+${RETENTION_DAYS}" -delete
}

# ── 공통 초기화 ─────────────────────────────────────────────────────────────
# umask 077: 산출물을 root 600 으로 만든다(아동 민감정보 — 가드레일 9절).
backup_preamble() {   # $1=대상 컨테이너
  umask 077
  require_root
  require_pass_file
  require_backup_dir
  command -v docker >/dev/null 2>&1 || die 5 "[$JOB_NAME] FAIL docker 를 찾을 수 없습니다(PATH=$PATH)"
  require_container "$1"
  acquire_lock
}
