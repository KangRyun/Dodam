# S15P11B209

만 4세~12세 아동이 그림과 대화를 통해 생각과 감정을 표현하도록 돕고, 보호자와 전문가에게 활동 기록과 참고용 분석 결과를 제공하는 서비스입니다. 심리 진단이나 치료 결과를 제공하지 않습니다.

Flutter 모바일 앱과 Next.js 웹은 Spring Boot REST API를 공통으로 사용합니다. 그림 분석과 대화 생성을 담당할 FastAPI AI 서버, 파일 저장을 위한 AWS S3, 알림을 위한 Firebase는 후속 작업에서 연동합니다.

주요 사용자는 아동, 보호자, 전문가, 관리자입니다.

## 기술 스택

현재 백엔드 초기 구성에 적용한 기술은 다음과 같습니다.

- Java 21 LTS
- Spring Boot 3.5.16
- Gradle 8.14.3 Wrapper
- Spring Web MVC
- Jakarta Bean Validation
- JUnit 5, Mockito, Spring Boot Test
- Spotless 8.8.0과 Google Java Format
- SLF4J와 Logback

다음 기술은 후속 작업에서 필요한 시점에 추가합니다.

- Spring Data JPA, MySQL 8.4.10 LTS, Flyway
- Spring Security와 JWT
- AWS S3, Redis, Firebase Cloud Messaging
- FastAPI 연동
- springdoc-openapi, Testcontainers
- Actuator와 Micrometer

Actuator는 초기 Application Context와 서버 실행 확인에 필수적이지 않아 현재 의존성에서 제외했습니다.

## 저장소 구조

현재 생성된 구조는 다음과 같습니다.

```text
S15P11B209/
├── backend/
│   ├── build.gradle
│   ├── settings.gradle
│   ├── gradlew
│   ├── gradlew.bat
│   ├── gradle/wrapper/
│   └── src/
│       ├── main/
│       │   ├── java/com/ssafy/b209/B209Application.java
│       │   └── resources/
│       │       ├── application.yml
│       │       ├── application-local.yml
│       │       └── application-test.yml
│       └── test/java/com/ssafy/b209/B209ApplicationTests.java
├── frontend/
│   ├── mobile/
│   └── web/
├── ai/
├── infra/
├── docs/
└── .env.example
```

Java는 빈 패키지를 Git으로 관리하지 않습니다. 기능 구현 시 필요한 패키지만 생성하며, 빈 클래스·인터페이스·`package-info.java`로 예정 구조를 채우지 않습니다.

향후 백엔드 패키지는 다음 책임을 기준으로 확장합니다.

```text
com.ssafy.b209
├── global
│   ├── config
│   ├── response
│   ├── exception
│   └── util
├── domain
│   ├── auth
│   ├── user
│   ├── expert
│   ├── child
│   ├── consent
│   ├── drawing
│   ├── analysis
│   ├── conversation
│   ├── report
│   ├── history
│   ├── notification
│   ├── community
│   ├── admin
│   └── counseling
└── infrastructure
    ├── ai
    ├── storage
    ├── notification
    └── persistence
```

Controller는 HTTP 요청과 응답, Service는 비즈니스 로직과 트랜잭션, Repository는 데이터베이스 접근을 담당합니다. 외부 시스템 구현은 핵심 비즈니스 로직과 분리된 Client 경계 뒤에 둡니다.

## 실행 환경

```text
Java: 21
Spring Boot: 3.5.16
Gradle: 8.14.3 Wrapper
Default Profile: local
Default Port: 8080
```

로컬에 Java 21을 설치하고 `JAVA_HOME`을 설정해야 합니다. Gradle은 별도로 설치할 필요가 없습니다.

## 실행 방법

먼저 백엔드 디렉터리로 이동합니다.

```bash
cd backend
```

```bash
# macOS / Linux
./gradlew bootRun

# Windows
gradlew.bat bootRun
```

Profile을 명시하려면 다음 명령을 사용합니다.

```bash
# macOS / Linux
./gradlew bootRun --args='--spring.profiles.active=local'

# Windows
gradlew.bat bootRun --args="--spring.profiles.active=local"
```

## 테스트

```bash
# macOS / Linux
./gradlew clean test

# Windows
gradlew.bat clean test
```

## 코드 포맷

```bash
# macOS / Linux
./gradlew spotlessCheck
./gradlew spotlessApply

# Windows
gradlew.bat spotlessCheck
gradlew.bat spotlessApply
```

SonarLint는 프로젝트 의존성이 아닌 권장 IDE 플러그인으로 사용합니다.

## Javadoc

```bash
# macOS / Linux
./gradlew javadoc

# Windows
gradlew.bat javadoc
```

생성된 문서는 `build/docs/javadoc/index.html`에서 확인합니다. 저장소 루트 기준 경로는 `backend/build/docs/javadoc/index.html`입니다. Javadoc은 빌드 결과물이므로 `build/` 디렉터리와 함께 Git에 Commit하지 않습니다.

## API 버전과 외부 시스템 경계

외부 REST API는 `/api/v1` 경로를 사용합니다. `/api/v1`을 전역 Context Path로 설정하지 않고 향후 Controller의 Request Mapping 또는 공통 상수로 관리합니다. 따라서 Actuator나 Swagger 같은 비즈니스 API 외 경로에 API 버전이 강제로 붙지 않습니다.

- Flutter와 Next.js는 Spring Boot의 `/api/v1/**`만 호출합니다.
- Spring Boot만 FastAPI의 `/internal/v1/**`를 호출합니다.
- 클라이언트는 FastAPI 내부 API나 S3 `storageKey`를 직접 지정하지 않습니다.
- 그림과 음성 파일은 Spring Boot가 형식과 권한을 검증한 뒤 S3에 저장합니다.
- Firebase 연동은 알림 인프라 구현으로 분리합니다.

그림 활동 생성과 파일 등록 API에는 향후 `Idempotency-Key` Header를 적용합니다. 중복 요청 검사와 저장 방식은 해당 API 작업에서 설계합니다.

## 환경 변수와 보안

실제 비밀번호, Token, API Key, 인증서와 `.env` 파일은 Git에 저장하지 않습니다. 루트 `.env.example`은 향후 연동에 필요한 변수 이름을 공유하기 위한 예시이며 실제 Secret을 포함하지 않습니다.

- 개인정보와 아동 데이터는 애플리케이션 로그에 기록하지 않습니다.
- 아동의 음성 원문과 대화 원문을 로그에 기록하지 않습니다.
- 그림 파일 전체 URL과 Pre-signed URL을 불필요하게 기록하지 않습니다.
- AI 작업 로그에는 사용자 개인정보 대신 작업 ID를 사용합니다.

## 후속 작업

1. MySQL과 Spring Data JPA 연결
2. Flyway 기반 초기 DB 스키마 구성
3. 공통 API 응답 형식 구현
4. 전역 예외 처리 구현
5. Swagger UI와 CORS 설정
6. 그림 활동 생성 API 구현
7. `Idempotency-Key` 처리
8. Spring Security와 JWT 인증
9. S3 Pre-signed URL 업로드
10. FastAPI AI 서버 연동
