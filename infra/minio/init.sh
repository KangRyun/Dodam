#!/bin/sh
# MinIO 1회성 프로비저닝 — S15P11B209-620
# 버킷 dodam(private) + 앱 계정 1벌(be-rw 버킷 rw, 최소권한).
# minio-init 컨테이너(minio/mc 기반 dodam-minio-init:local)가 실행. 정책 JSON은 이 스크립트와 같은 디렉터리의 policies/.
#
# ※ ai-ro(images/ 읽기전용) 계정은 673 에서 회수했다 — AI 이미지 접근이 BE 프록시
#   1회용 토큰(402)으로 구현돼, 만들기만 하고 아무도 쓰지 않는 유휴 자격증명이었다.
#   직접 GET 방식을 되살리려면 저장소-아키텍처 §4 의 as-built 근거부터 뒤집어야 한다.
set -eu

# 정책 JSON 경로는 스크립트 위치 기준으로 잡는다(이미지 안 /opt/dodam, 로컬 직접 실행 모두 동일).
#   reason: 고정 절대경로(/init/...)는 마운트 방식이 바뀌면 그대로 깨진다 — 2026-07-26 장애의 잔재 제거.
SCRIPT_DIR=$(dirname "$0")

# 1) minio 준비될 때까지 alias 재시도 (healthcheck 무관하게 자체 대기)
echo "[minio-init] waiting for minio ..."
until mc alias set local "http://minio:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  sleep 2
done
echo "[minio-init] minio ready."

# 2) 버킷(private 기본) + 익명 접근 명시적 차단(default deny)
mc mb --ignore-existing local/dodam
mc anonymous set none local/dodam || true
#    프리픽스(images/ audio/ tts-cache/ reports/ evidences/)는 객체 PUT 시 생성됨.
#    정책은 프리픽스 스코프로 부여(아래).

# 3) 앱 계정 (이미 있으면 무시)
mc admin user add local "$MINIO_BE_USER" "$MINIO_BE_PASSWORD" || true

# 4) 최소권한 정책 생성·부착
#    ⚠️ mc 명령이 버전에 따라 create/attach ↔ add/set 로 다름 → 양쪽 폴백.
mc admin policy create local dodam-be-rw "$SCRIPT_DIR/policies/be-rw.json" 2>/dev/null || \
  mc admin policy add    local dodam-be-rw "$SCRIPT_DIR/policies/be-rw.json"

mc admin policy attach local dodam-be-rw --user "$MINIO_BE_USER" 2>/dev/null || \
  mc admin policy set    local dodam-be-rw "user=$MINIO_BE_USER"

# 5) 수명주기(ILM) — S15P11B209-622.
#    lifecycle.json 을 선언적으로 import(전체 교체 → 멱등). 현재 규칙은 tts-cache/ 만:
#      - tts-cache/  : 30일 자동 만료. TTS 캐시는 원문에서 재생성되는 파생물이라 안전(설계 §1).
#      - images/ audio/ reports/ : 보존기간이 동의정책·팀결정 대기(622 §D) → 만료 규칙 미부여.
#      - evidences/  : 법적 보존 → 자동 만료 구조적 제외(설계 §8) → 만료 규칙 미부여.
#    ⚠️ 첫 실행 검증(리눅스서 미검증): 이 mc 태그의 'mc ilm import' 지원 여부.
#       실패 시 프로비저닝은 계속(계정·버킷이 우선) — 경고만 남기고 수동 적용 안내.
if mc ilm import local/dodam < "$SCRIPT_DIR/lifecycle.json" 2>/dev/null; then
  echo "[minio-init] ILM applied: tts-cache/ expire 30d"
else
  echo "[minio-init] WARN: ILM import 실패(mc 버전 미지원?) — 수동 적용: mc ilm rule add local/dodam --prefix tts-cache/ --expire-days 30"
fi

echo "[minio-init] done: bucket=dodam, users=be-rw(rw), ilm=tts-cache/30d"
