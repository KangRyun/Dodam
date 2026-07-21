# Spring Boot 백엔드 초기 구성 설계

## 목표

모노레포의 `backend/` 디렉터리에 Java 21과 Spring Boot 3.5.16 기반의 최소 실행 가능 프로젝트를 구성한다. 팀원은 별도 Gradle 설치 없이 Wrapper로 빌드, 테스트, 포맷 검사, Javadoc 생성, 로컬 실행을 수행할 수 있어야 한다.

## 기준 문서와 용어

- 서비스명은 API 명세서의 **아동 그림·대화 기반 정서 표현 서비스**를 사용한다.
- 외부 REST API의 Base URL은 `/api/v1`이며, 전역 Context Path가 아닌 향후 Controller Mapping으로 적용한다.
- 주요 사용자는 아동, 보호자, 전문가, 관리자이다.
- API 명세의 도메인 명칭인 `auth`, `user`, `expert`, `child`, `consent`, `drawing`, `analysis`, `conversation`, `report`, `history`, `notification`, `community`, `admin`, `counseling`을 향후 패키지 설계의 기준으로 사용한다.
- 별도 ERD 파일은 제공된 첨부 목록에서 확인되지 않아, API 명세서의 ERD 정합성 항목만 참고한다.

## 프로젝트 배치와 기본 정보

기존 README에 정의된 모노레포 구조를 유지하고 Spring Boot 프로젝트 전체를 `backend/`에 둔다.

```text
Group: com.ssafy
Artifact: b209
Base Package: com.ssafy.b209
Application Class: B209Application
Version: 0.0.1-SNAPSHOT
Packaging: Jar
```

저장소에 기존 Java, Spring Boot, Gradle 또는 Java 패키지 기준이 없으므로 작업 요청서의 기본값을 사용한다.

## 생성 구성

`backend/`에는 다음 실행 가능한 최소 파일만 생성한다.

```text
backend/
├── build.gradle
├── settings.gradle
├── gradlew
├── gradlew.bat
├── gradle/wrapper/
│   ├── gradle-wrapper.jar
│   └── gradle-wrapper.properties
└── src/
    ├── main/
    │   ├── java/com/ssafy/b209/B209Application.java
    │   └── resources/
    │       ├── application.yml
    │       ├── application-local.yml
    │       └── application-test.yml
    └── test/java/com/ssafy/b209/B209ApplicationTests.java
```

비어 있는 예정 패키지, 빈 클래스, 빈 인터페이스, `package-info.java`, Java 디렉터리의 `.gitkeep`은 만들지 않는다. 향후 패키지 구조는 루트 `README.md`에서 현재 구조와 구분해 문서화한다.

## 빌드와 의존성

- Gradle Groovy DSL과 Gradle 8.14.x Wrapper를 사용한다.
- Java Toolchain은 21로 고정한다.
- Spring Boot Plugin은 3.5.16, Spotless Plugin은 8.8.0을 사용한다.
- 의존성은 Spring Web, Spring Validation, Lombok, Spring Boot Test, JUnit Platform Launcher로 제한한다.
- Spring Framework, Jackson, JUnit, Mockito, Logback의 세부 버전은 Spring Boot Dependency Management에 위임한다.
- Actuator는 현재 초기 실행에 필수적이지 않으므로 제외하고 향후 기술로 문서화한다.

Javadoc Task에는 UTF-8 `encoding`, `charSet`, `docEncoding`과 `failOnError = true`를 적용한다. 전체 DocLint 비활성화와 `withJavadocJar()`는 추가하지 않는다.

## Application과 Javadoc

`B209Application`은 Spring Boot Application Context와 내장 웹 서버를 시작하는 진입점만 담당한다. 공개 클래스와 `main` 메서드에는 실제 책임과 실행 효과를 설명하는 한국어 Javadoc을 작성한다. 구현되지 않은 API, 외부 연동 또는 비즈니스 기능을 수행하는 것처럼 설명하지 않는다.

기본 `contextLoads()`는 역할이 자명하므로 형식적인 Javadoc을 작성하지 않는다. 이번 범위에는 설정 클래스, 공통 인터페이스, 외부 시스템 추상화 인터페이스를 생성하지 않는다.

## 설정과 실행 흐름

- `application.yml`은 애플리케이션 이름, 기본 Profile `local`, 포트 `8080`만 정의한다.
- `application-local.yml`과 `application-test.yml`은 해당 Profile 활성화 조건만 정의한다.
- DB, JPA, Redis, AWS, JWT, Firebase, AI 서버 주소, Secret, `/api/v1` Context Path는 설정하지 않는다.
- 테스트는 `test` Profile로 Application Context가 시작되는지만 확인한다.

실행 데이터 흐름은 다음과 같다.

```text
Gradle bootRun
  -> B209Application.main
  -> Spring Application Context 초기화
  -> local Profile 적용
  -> 내장 웹 서버가 8080 포트에서 시작
```

외부 시스템 호출과 비즈니스 데이터 흐름은 이번 단계에 존재하지 않는다.

## 향후 아키텍처 경계

향후 HTTP 요청은 Controller, 비즈니스 로직은 Service, 영속성은 Repository가 담당한다. FastAPI, S3, Firebase 등의 연동은 Service와 분리된 Client 추상화 및 `infrastructure` 구현체로 구성한다.

- Flutter와 Next.js는 Spring Boot의 `/api/v1/**`만 호출한다.
- Spring Boot는 FastAPI의 `/internal/v1/**`를 호출한다.
- 클라이언트는 FastAPI 내부 API나 S3 `storageKey`를 직접 제어하지 않는다.
- 그림·음성 파일은 Spring Boot가 검증한 뒤 외부 저장소에 보관한다.

이 경계는 README에 예정 구조로만 기록하며 관련 Java 코드는 만들지 않는다.

## 오류와 보안 원칙

전역 예외 처리나 API 오류 응답은 후속 작업으로 남긴다. 초기 구성 오류는 Gradle 빌드, Context 테스트, Javadoc Task, `bootRun` 실패로 확인한다.

`.gitignore`에는 Gradle 빌드 결과물, IDE 파일, `.env`, Secret 설정, 로그를 제외하는 규칙을 보완한다. 기존 `.env.example`은 샘플 파일로 유지하되 실제 Secret은 넣지 않는다. README에는 개인정보, 아동 음성·대화 원문, Pre-signed URL을 로그에 남기지 않는 원칙을 기록한다.

## 검증

Windows 환경에서 다음 순서로 검증한다.

```powershell
backend\gradlew.bat clean test
backend\gradlew.bat spotlessCheck
backend\gradlew.bat javadoc
backend\gradlew.bat bootRun
```

`bootRun`은 Java 21, Spring Boot 3.5.16, 기본 `local` Profile, 8080 포트, Application Context 시작을 로그로 확인한 뒤 종료한다. 8080 포트 충돌은 코드 오류와 구분해 보고한다.

Javadoc은 `backend/build/docs/javadoc/index.html` 생성 여부, UTF-8 한글 표시, 잘못된 태그·존재하지 않는 파라미터 참조·경고 발생 여부를 확인한다. `backend/build/`는 Git에 포함하지 않는다.

## 명시적 제외 범위

이번 작업에서는 MySQL, JPA, Flyway, Entity, Repository, 공통 API 응답, 전역 예외 처리, Swagger/OpenAPI, CORS, Security/JWT, 실제 Controller와 Endpoint, 그림 활동 API, FastAPI Client, S3, Redis, Firebase, Docker, CI/CD를 구현하거나 의존성으로 추가하지 않는다.
