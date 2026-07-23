# syntax=docker/dockerfile:1
# 도담 backend(Spring Boot, Java 21) 이미지 — 멀티스테이지로 빌드/런타임 분리해 이미지 최소화.
# 관련 이슈: S15P11B209-185 (docker-compose 서비스 골격)

##### 1) build stage — Gradle로 실행 가능한 jar(bootJar) 생성 #####
FROM eclipse-temurin:21-jdk-jammy AS build
WORKDIR /app

# 의존성 캐시 레이어를 살리기 위해 빌드 스크립트/래퍼를 소스보다 "먼저" 복사한다.
#   → src만 바뀌면 아래 의존성 다운로드 레이어는 캐시 재사용(빌드 빨라짐).
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies || true

# 소스 복사 후 실제 빌드. 테스트는 CI 단계에서 별도 수행하므로 여기선 제외(-x test)해 빌드 단축.
COPY src ./src
RUN ./gradlew --no-daemon clean bootJar -x test

##### 2) runtime stage — JRE만 담아 실행(이미지 크기↓) #####
FROM eclipse-temurin:21-jre-jammy AS runtime
WORKDIR /app

# 루트가 아닌 전용 유저로 실행 — 권한 최소화(가드레일).
RUN useradd -r -u 1001 spring

# 그림 저장 볼륨 마운트 지점 사전 생성 + 소유권 부여 — S15P11B209-349.
#   reason: 네임드 볼륨은 최초 root:root로 초기화되는데 앱은 비루트(uid 1001)라
#           첫 업로드의 디렉토리 생성이 EACCES로 조용히 실패한다(부팅은 성공 — 사각지대).
#           빈 볼륨 최초 마운트 시 도커가 이미지 쪽 내용·소유권을 볼륨에 복사하므로
#           이미지에서 미리 소유해 두면 볼륨도 spring 소유로 시작한다.
RUN mkdir -p /app/storage/images && chown -R spring:spring /app/storage

USER spring

# 빌드 스테이지 산출물 jar만 가져온다(버전 무관하게 app.jar로 고정 → 태그 바뀌어도 ENTRYPOINT 불변).
COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
