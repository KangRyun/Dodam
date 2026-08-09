# syntax=docker/dockerfile:1
# 도담 backend(Spring Boot, Java 21) 런타임 이미지.
# 관련 이슈: S15P11B209-185(compose 골격) · S15P11B209-391 Phase 2(이중 컴파일 제거)
#
# ⚠️ 빌드 전제: CI(Jenkins)가 이 이미지를 빌드하기 전에 `./gradlew test bootJar`로
#   backend/build/libs/*.jar 를 먼저 산출한다. 그 jar를 COPY만 하므로 이미지 빌드에
#   Gradle 컴파일이 없다(테스트 단계에서 이미 컴파일한 결과를 재사용 — 이중 컴파일 제거).
#   로컬에서 이 이미지를 단독/compose로 빌드하려면 먼저 `cd backend && ./gradlew bootJar`.
#   (jar가 없으면 아래 COPY가 실패 → "먼저 bootJar 하라"는 신호.)

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

# CI가 산출한 실행 가능 jar만 가져온다(버전 무관하게 app.jar로 고정 → 태그 바뀌어도 ENTRYPOINT 불변).
#   .dockerignore가 build/libs 를 예외로 포함하고 plain jar(*-plain.jar)는 제외하므로
#   와일드카드는 bootJar 하나만 매칭한다.
COPY build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
