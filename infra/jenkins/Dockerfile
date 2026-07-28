# syntax=docker/dockerfile:1
# 도담 CI/CD — Jenkins 컨트롤러 이미지.
# 공식 jenkins 이미지엔 docker CLI가 없어서, docker-ce-cli + compose 플러그인을 얹는다.
#   → 호스트 docker.sock을 통해 이 컨테이너에서 이미지 빌드·compose 배포까지 수행(단일 호스트 CI/CD).
# 관련 이슈: S15P11B209-189 (Jenkins CI/CD)

FROM jenkins/jenkins:lts-jdk21

USER root

# 1) docker CLI + compose 플러그인 설치 (jenkins 이미지 = Debian bookworm 기반)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# 2) jenkins 유저에게 호스트 docker.sock 접근 권한 부여.
#    호스트 docker 그룹 GID(기본 988)와 같은 GID의 그룹에 jenkins 를 넣는다 → 마운트된 소켓 접근 가능.
#    (서버가 바뀌면: 호스트에서 `getent group docker` 로 GID 확인 후 build-arg DOCKER_GID 로 조정)
ARG DOCKER_GID=988
RUN if ! getent group "${DOCKER_GID}" >/dev/null; then groupadd -g "${DOCKER_GID}" hostdocker; fi \
 && usermod -aG "$(getent group "${DOCKER_GID}" | cut -d: -f1)" jenkins

# 3) kubectl — compose→k8s 배포 전환용 (S15P11B209-359)
#    ⚠️ 버전 고정. `stable.txt` 로 받으면 같은 Dockerfile 이 시점마다 다른 이미지를 만든다.
#    k8s 는 kubectl 과 서버 버전이 마이너 ±1 까지 호환된다 — k3s 를 올릴 때 이 값도 함께 본다.
#    (k3s v1.31.x 대상. 설치한 k3s 버전과 2 마이너 이상 벌어지면 명령이 조용히 실패할 수 있다)
ARG KUBECTL_VERSION=v1.31.4
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl" \
 && chmod 0755 /usr/local/bin/kubectl \
 && kubectl version --client=true

USER jenkins
