# syntax=docker/dockerfile:1
# 도담 nginx 게이트웨이 이미지 — 리버스 프록시 conf를 이미지에 "굽는다"(bind 마운트 제거).
# 관련 이슈: S15P11B209-300 (nginx 하드닝 + 배포 방식 교정)
#
# 왜 bake 하나: bind 마운트 경로는 compose를 실행한 위치(호스트 repo vs Jenkins 컨테이너 워크스페이스)에
#   따라 달라진다. Jenkins가 배포하면 호스트 데몬이 모르는 경로가 마운트돼 "빈 conf.d"로 게이트웨이가
#   조용히 죽는 사고가 실제로 발생(2026-07-22). 이미지에 conf를 포함하면 빌드 컨텍스트는 CLI가 직접
#   전송하므로 어디서 빌드·배포해도 동일하다(이식성 + SHA 태그로 버전 추적).

FROM nginx:1.27-alpine
COPY conf.d/ /etc/nginx/conf.d/
