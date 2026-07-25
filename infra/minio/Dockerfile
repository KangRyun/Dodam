# ───────────────────────────────────────────────────────────────
# minio-init 이미지 — 프로비저닝 스크립트·정책 JSON을 "이미지에 bake".
#
# ⚠️ 왜 bind 마운트(./minio:/init)를 쓰지 않는가 — 2026-07-26 전면 장애의 원인.
#   이 파이프라인은 Jenkins 컨테이너 안에서 호스트 도커 데몬을 호출한다(Docker-out-of-Docker).
#   compose의 상대경로는 "Jenkins 컨테이너 안 워크스페이스"(/var/jenkins_home/workspace/...) 기준으로
#   문자열 해석되지만, 실제 마운트는 호스트 데몬이 수행한다. 호스트엔 그 경로가 없으므로
#   도커가 빈 디렉터리를 만들어 마운트 → init.sh 가 사라져 exit 127 → backend·nginx 미기동(서비스 전면 중단).
#   같은 함정으로 2026-07-22 nginx 빈 conf 사고도 있었다.
#
#   반면 "빌드 컨텍스트"는 CLI가 tar 로 묶어 데몬에 전송하므로 실행 위치와 무관하다.
#   → nginx conf 와 동일하게 스크립트를 이미지에 굽는다(이 저장소의 표준 해법).
# ───────────────────────────────────────────────────────────────
FROM minio/mc:RELEASE.2025-04-16T18-13-26Z

# 스크립트와 정책을 같은 디렉터리에 둔다 — init.sh 는 $(dirname $0)/policies 로 참조하므로
# 이미지 안이든(아래 경로) 개발자가 로컬에서 직접 실행하든 동일하게 동작한다.
COPY init.sh      /opt/dodam/init.sh
COPY policies/    /opt/dodam/policies/

ENTRYPOINT ["/bin/sh", "/opt/dodam/init.sh"]
