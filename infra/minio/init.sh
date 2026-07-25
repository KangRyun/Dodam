#!/bin/sh
# MinIO 1회성 프로비저닝 — S15P11B209-620
# 버킷 dodam(private) + 앱 계정 2벌(be-rw 버킷 rw / ai-ro images/ 읽기전용, 최소권한).
# minio-init 컨테이너(minio/mc 기반 dodam-minio-init:local)가 실행. 정책 JSON은 이 스크립트와 같은 디렉터리의 policies/.
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
mc admin user add local "$MINIO_AI_USER" "$MINIO_AI_PASSWORD" || true

# 4) 최소권한 정책 생성·부착
#    ⚠️ mc 명령이 버전에 따라 create/attach ↔ add/set 로 다름 → 양쪽 폴백.
mc admin policy create local dodam-be-rw "$SCRIPT_DIR/policies/be-rw.json" 2>/dev/null || \
  mc admin policy add    local dodam-be-rw "$SCRIPT_DIR/policies/be-rw.json"
mc admin policy create local dodam-ai-ro "$SCRIPT_DIR/policies/ai-ro.json" 2>/dev/null || \
  mc admin policy add    local dodam-ai-ro "$SCRIPT_DIR/policies/ai-ro.json"

mc admin policy attach local dodam-be-rw --user "$MINIO_BE_USER" 2>/dev/null || \
  mc admin policy set    local dodam-be-rw "user=$MINIO_BE_USER"
mc admin policy attach local dodam-ai-ro --user "$MINIO_AI_USER" 2>/dev/null || \
  mc admin policy set    local dodam-ai-ro "user=$MINIO_AI_USER"

echo "[minio-init] done: bucket=dodam, users=be-rw(rw) / ai-ro(images:read)"
