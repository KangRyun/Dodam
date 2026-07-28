# 도담 Android 릴리스 빌드 툴체인 (S15P11B209-623)
#
# 왜 자체 이미지인가 — 기성 이미지를 못 쓴다:
#   ghcr.io/cirruslabs/flutter 는 3.44.0 까지만 있고(3.44.3·3.44.5·3.44.7 전부 404),
#   3.44.0 이 얹은 Dart 는 3.12.0 이다. 그런데 pubspec.yaml 은 `sdk: ^3.12.2` 라서
#   `flutter pub get` 이 그 자리에서 거절한다. 남은 `stable` 태그는 떠다니므로
#   "어제 성공한 빌드가 오늘 실패"를 만든다 — 재현성이 이 이슈의 목적이라 배제했다.
#   → 팀·호스트가 쓰는 3.44.7 을 고정한 이미지를 직접 만든다.
#
# 빌드:
#   docker build -t dodam-flutter-builder:3.44.7 infra/mobile
# 사용:
#   infra/mobile/build-aab.sh  (바인드 마운트 금지 — 아래 참조)
#
# ⚠️ 이 이미지를 bind mount 와 함께 쓰지 말 것.
#    Jenkins 는 호스트 도커 소켓을 부르는 DooD 구조이고 jenkins_home 은 named volume 이라
#    컨테이너 안 워크스페이스 경로가 호스트엔 없다. 마운트하면 도커가 빈 디렉터리를 만들어 붙여
#    "소스가 사라진 채" 빌드된다(2026-07-22·07-26 전면 중단 2회). 소스는 docker cp 로 넣는다.

FROM eclipse-temurin:17-jdk-noble

# 버전은 전부 인자로 고정한다 — latest 계열을 쓰면 같은 Dockerfile 이 다른 이미지를 만든다.
ARG FLUTTER_VERSION=3.44.7
ARG CMDLINE_TOOLS_BUILD=13114758
ARG ANDROID_API=36
ARG BUILD_TOOLS_VERSION=36.0.0

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    GRADLE_USER_HOME=/root/.gradle \
    PUB_CACHE=/root/.pub-cache \
    DEBIAN_FRONTEND=noninteractive

ENV PATH="${FLUTTER_ROOT}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# git: flutter 자체가 git 체크아웃으로 동작한다(버전 판별에 .git 을 읽는다).
# unzip/zip/xz-utils: sdkmanager 패키지 해제 + flutter 아티팩트 해제.
# NDK 는 일부러 설치하지 않았다 — 이 앱에 네이티브 모듈이 없어 약 1.5GB 를 아낀다.
#   플러그인이 늘어 NDK 가 필요해지면 아래 sdkmanager 줄에 "ndk;<버전>" 을 추가한다.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip zip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# ── Android SDK ────────────────────────────────────────────────────────────
# cmdline-tools 는 반드시 cmdline-tools/latest/ 로 옮겨야 한다. 압축을 푼 그대로 두면
# sdkmanager 가 자기 위치를 SDK 루트 기준으로 계산하지 못해 실패한다.
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
 && curl -fsSL -o /tmp/cmdline-tools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
 && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
 && mv /tmp/cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
 && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools

# 라이선스 동의는 대화형이라 CI 에서 통과할 수 없다 — 이미지 빌드 시점에 한 번 받아 둔다.
# `yes |` 의 SIGPIPE 로 파이프라인이 실패로 판정되지 않게 종료코드를 명시적으로 흡수한다.
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true \
 && sdkmanager --install \
      "platform-tools" \
      "platforms;android-${ANDROID_API}" \
      "build-tools;${BUILD_TOOLS_VERSION}" \
 && sdkmanager --list_installed

# ── Flutter ────────────────────────────────────────────────────────────────
# --depth 1 + 태그 지정: 전체 히스토리(수 GB)를 받지 않으면서 버전은 정확히 고정된다.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git "${FLUTTER_ROOT}" \
 && git config --global --add safe.directory "${FLUTTER_ROOT}"

# precache: 안드로이드 빌드 아티팩트(gen_snapshot 등)를 이미지에 미리 넣는다.
#   안 하면 컨테이너가 매 빌드마다 새로 받는다 — 컨테이너는 매번 폐기되므로 캐시가 남지 않는다.
# --version 을 먼저 불러 flutter 가 자기 도구를 부트스트랩하게 한다(첫 호출이 Dart SDK 를 받는다).
RUN flutter --version \
 && flutter config --no-analytics --android-sdk "${ANDROID_HOME}" \
 && flutter precache --android --no-ios --no-web --no-linux --no-windows --no-macos

# 플러그인들이 저마다 다른 compileSdk 로 컴파일된다 — AGP 가 빌드 도중 android-34·35 를
# 추가로 내려받는 것을 실측했다(2026-07-28 검증 빌드). 컨테이너는 매 빌드마다 폐기되므로
# 여기서 미리 넣지 않으면 **빌드마다 같은 걸 다시 받는다.**
#   ※ 앞의 sdkmanager 블록에 합치지 않고 별도 RUN 으로 둔 이유: flutter 레이어 캐시를
#     무효화하지 않기 위해서다(합치면 그 아래 clone·precache 가 통째로 다시 돈다).
RUN sdkmanager --install "platforms;android-34" "platforms;android-35" \
 && sdkmanager --list_installed

# 툴체인이 실제로 성립하는지 이미지 빌드 시점에 판정한다.
# "설치했다"와 "동작한다"는 다르다 — 여기서 걸러야 파이프라인이 아니라 이미지를 고칠 수 있다.
RUN flutter doctor -v | tee /tmp/doctor.txt \
 && grep -q '\[✓\] Android toolchain' /tmp/doctor.txt \
 || (echo "❌ Android toolchain 이 doctor 에서 ✓ 가 아니다 — 위 로그 확인"; cat /tmp/doctor.txt; exit 1)

WORKDIR /src
