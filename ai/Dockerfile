# syntax=docker/dockerfile:1
# 도담 AI 분석 서버(FastAPI, Python) 이미지 — 멀티스테이지로 의존성 설치/런타임을 분리해 이미지 최소화.
# 관련 이슈: S15P11B209-188 (AI 서버 컨테이너화)
#
# 시크릿(GMS_KEY 등)은 이미지에 넣지 않는다. 런타임에 compose가 환경변수로 주입하고
# config.py가 os.environ으로 읽는다(override=False → 주입값 우선). .dockerignore로 .env 배제.

##### 1) build stage — 의존성만 /install 아래에 설치(컴파일 도구·캐시는 이 스테이지에 격리) #####
FROM python:3.11-slim-bookworm AS build
WORKDIR /app

# 의존성 캐시 레이어를 살리기 위해 requirements를 소스보다 "먼저" 복사한다.
#   → 소스만 바뀌면 아래 pip install 레이어는 캐시 재사용(빌드 빨라짐).
COPY requirements.txt ./
# --prefix=/install: 설치물을 한 디렉터리에 모아 런타임 스테이지로 통째 복사하기 위함.
# --no-cache-dir: pip 다운로드 캐시를 이미지에 남기지 않아 크기↓.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

##### 2) runtime stage — 실행에 필요한 것만 담는다(빌드 잔여물 없음) #####
FROM python:3.11-slim-bookworm AS runtime
WORKDIR /app

# 로그가 버퍼링 없이 바로 stdout에 흐르게(=docker logs에 즉시 보임), .pyc 미생성으로 이미지 청결.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 루트가 아닌 전용 유저로 실행 — 권한 최소화(가드레일). backend Dockerfile과 동일 패턴.
RUN useradd -r -u 1001 dodam
USER dodam

# build 스테이지에서 설치한 파이썬 패키지를 표준 prefix(/usr/local)로 가져온다 → PATH·site-packages에 자동 포함.
COPY --from=build /install /usr/local

# 앱 소스 복사(의존성 이후 → 소스 변경이 의존성 레이어 캐시를 깨지 않음).
COPY . .

# uvicorn은 컨테이너 밖(nginx 등 다른 컨테이너)에서 닿아야 하므로 0.0.0.0에 바인딩.
# (127.0.0.1이면 컨테이너 내부에서만 접속 가능 → nginx 프록시 불가). --reload 없음(운영용).
# 포트 8000: compose 내부망에서 nginx가 이 포트로 프록시한다(외부 노출 X).
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
