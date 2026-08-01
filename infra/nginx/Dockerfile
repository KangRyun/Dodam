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
# 정적 페이지 — /legal/(개인정보처리방침·이용약관) · /download/(APK 안내).
#   S15P11B209-383 에서 루트 임시 페이지(302)는 걷어내고 `/` 는 web 컨테이너로 프록시한다.
#   ⚠️ 그렇다고 이 COPY 를 지우면 안 된다. 루트만 웹으로 넘어갔을 뿐 /legal/·/download/ 는
#      여전히 이 이미지의 정적 파일이 서빙한다(conf 에 전용 location 이 있다).
#      스토어 심사에 등록된 URL 이라 사라지면 심사가 막힌다.
COPY html/  /usr/share/nginx/html/
