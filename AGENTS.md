# AGENTS.md

이 문서는 Codex가 이 Repository에서 Jira 이슈를 수행할 때 공통으로 따라야 하는 규칙이다.
각 이슈 프롬프트에는 목적, 핵심 요구사항, 제외 범위와 완료 조건만 작성하고 아래 규칙은 모든 작업에 공통 적용한다.

## 1. 작업 시작 전 확인

코드 수정 전에 다음을 확인하고 간단히 보고한다.

```bash
git branch --show-current
git status --short
```

확인 항목:

- Java, Spring Boot, Gradle 버전
- Base Package와 기존 Package 구조
- 관련 Controller, Service, Repository, DTO, Entity 존재 여부
- 기존 공통 응답·예외 처리·Swagger·CORS·Profile 설정
- 관련 DB Table과 최신 Flyway Migration
- 선행 Jira 이슈가 `develop`에 포함됐는지
- 생성 또는 수정 예정 파일
- 이번 이슈에서 제외할 작업

같은 역할의 클래스나 Endpoint가 있으면 중복 생성하지 않는다.
명세와 코드가 충돌하면 작업 전에 다음 형식으로 보고한다.

```text
충돌 항목:
기존 구현:
이슈 또는 최신 명세:
영향 범위:
권장 처리 방법:
```

## 2. Git 규칙

모든 Jira 작업은 최신 `develop`을 기준으로 시작한다.

```bash
git switch develop
git pull --ff-only origin develop
git switch -c <이슈별-feature-branch>
```

선행 이슈가 `develop`에 없으면 임의로 Merge, Rebase, Cherry-pick하거나 이전 Feature Branch에서 새 Branch를 만들지 않는다. 현재 상태와 권장 방법을 보고하고 중단한다.

Commit되지 않은 변경 사항이 있으면 다음을 임의로 수행하지 않는다.

- `git stash`
- `git reset`
- 파일 삭제 또는 덮어쓰기
- 강제 Branch 전환
- Merge, Rebase, Cherry-pick

사용자 요청 없이 다음 작업을 수행하지 않는다.

- Commit, Push
- Merge Request 생성
- Merge, Rebase, Cherry-pick, Force Push
- 기존 Commit 수정
- 원격 Branch 삭제
- `develop` 또는 `master` 직접 Commit

작업 완료 후 권장 Commit Message와 Merge Request 초안만 제공한다.

## 3. 구현 원칙

- 기존 Java, Spring Boot, Gradle 버전을 변경하지 않는다.
- 기존 Package 구조와 Naming Convention을 따른다.
- 기존 공통 응답, 예외 처리, Swagger, CORS, Profile 구조를 유지한다.
- 적용된 Flyway Migration을 수정하지 않는다.
- Schema 변경이 필요하면 새 Migration을 추가한다.
- 같은 역할의 Entity, DTO, Service, Repository, Client를 중복 생성하지 않는다.
- 대규모 Rename이나 관련 없는 Refactoring을 하지 않는다.
- 후속 Jira 범위를 미리 구현하지 않는다.
- Lombok, MapStruct, QueryDSL 등 새 Library를 요구 없이 추가하지 않는다.
- 불필요한 Base Class나 범용 Framework를 만들지 않는다.

Layer 책임:

- Controller: 요청 수신, Validation, Service 호출, 응답 반환
- Service: Use Case, Transaction, Domain 검증
- Repository: 데이터 조회·저장
- Entity: 상태와 불변 조건

금지 사항:

- Controller에서 Repository 직접 호출
- Controller에서 Entity 생성 또는 파일 저장
- Controller에서 `try-catch`로 Domain 오류 처리
- Repository에서 `BusinessException` 발생
- Entity 직접 API 응답
- 사용자 ID, 아동 ID, 상태값 하드코딩
- Public Setter와 `@Data` 남용

## 4. 인증 및 개인정보

기존 인증 인프라가 있으면 해당 방식을 사용한다.
인증이 없다면 Spring Security, JWT, 임의 사용자 Header, 가짜 Principal, 사용자 ID 하드코딩을 추가하지 않는다.

다음 정보를 로그나 API 오류 응답에 노출하지 않는다.

- Authorization Header와 Token
- 아동 이름과 생년월일
- 이미지·음성 원본 또는 Base64
- Request Body 전체
- 서버 절대 경로와 임시 경로
- SQL과 Constraint 이름
- Stack Trace와 Exception 클래스명

## 5. 이미지 저장

- 기존 `ImageStorage` Interface와 구현을 재사용한다.
- 원본 파일명을 실제 저장 파일명으로 사용하지 않는다.
- 절대 경로를 DB나 API 응답에 저장하지 않는다.
- 이미지 Byte나 Base64를 DB에 저장하지 않는다.
- 이미지 Signature 검증을 여러 계층에 중복 작성하지 않는다.
- 저장 실패 시 부분 파일과 임시 파일을 정리한다.
- DB 저장 실패 시 고아 파일 보상 처리 여부를 확인한다.
- Service는 구체적인 Local 구현이 아니라 Storage Interface에 의존한다.

## 6. AI 연동

현재 AI 서버는 연동되지 않은 상태다.
별도 이슈 지시가 없는 한 다음을 적용한다.

- 실제 AI 서버와 FastAPI를 호출하지 않는다.
- AI URL을 하드코딩하지 않는다.
- 분석 성공 결과나 완료 상태를 임의 생성하지 않는다.
- 기존 AI Interface는 테스트에서 Mock으로 대체할 수 있다.
- Mock 분석 결과는 해당 Jira 이슈에서만 구현한다.
- API 계약, AI Client, Mock 결과, 분석 저장은 서로 다른 Jira 범위로 분리한다.
- AI 미연동 때문에 작업할 수 없으면 임의 구현하지 말고 충돌을 보고한다.

기본 분리:

```text
계약 정의: DTO, Enum, JSON 구조
AI Client: HTTP Client Interface와 Adapter
Mock 분석: 외부 호출 없는 Mock 결과
분석 저장: Application Service와 DB 저장
```

## 7. DB 및 API

- MySQL 8.x 문법을 사용한다.
- H2 전용 SQL을 운영 Migration에 작성하지 않는다.
- `DROP TABLE`이나 데이터 손실 변경을 하지 않는다.
- Java Enum은 `EnumType.STRING`을 사용한다.
- Java Enum과 DB 문자열을 일치시킨다.
- 같은 기능의 Endpoint를 두 개 만들지 않는다.
- 최신 명세와 코드의 URI가 충돌하면 보고한다.
- 성공 응답은 기존 `ApiResponse<T>`를 사용한다.
- 오류 응답은 기존 `ApiErrorResponse<T>`와 `GlobalExceptionHandler`를 사용한다.
- Entity를 Swagger Schema로 노출하지 않는다.
- 존재하지 않는 인증 Scheme을 Swagger에 추가하지 않는다.

## 8. 테스트 및 검증

이슈 범위에 따라 다음 테스트를 작성한다.

- Service 단위 테스트
- Repository 테스트
- Controller MockMvc 테스트
- JSON 직렬화·역직렬화 테스트
- 필요한 경우 Testcontainers MySQL 통합 테스트
- 오류와 경계값 테스트

기존 테스트를 삭제하거나 비활성화하지 않는다.
Docker가 없어 Testcontainers를 실행하지 못하면 테스트를 제거하지 말고 미실행 사유를 보고한다.

검증 명령:

### Windows

```bash
gradlew.bat clean test
gradlew.bat spotlessCheck
gradlew.bat javadoc
```

### macOS / Linux

```bash
./gradlew clean test
./gradlew spotlessCheck
./gradlew javadoc
```

실행하지 못하거나 실패한 검증을 성공했다고 보고하지 않는다.

## 9. README 및 Javadoc

- README 전체를 재작성하지 않는다.
- 현재 이슈의 Endpoint, 환경 변수, 사용 예시와 제한 사항만 보완한다.
- 구현하지 않은 기능을 구현된 것처럼 작성하지 않는다.
- 인증이나 AI가 미연동이면 제한 사항을 명시한다.
- 실제 Secret, Token, 사용자 PC 절대 경로를 작성하지 않는다.
- 주요 Production Type에는 실제 구현과 일치하는 한국어 Javadoc을 작성한다.
- 의미 없는 TODO, `@author`, 빈 `package-info.java`를 추가하지 않는다.

## 10. 완료 보고

작업 완료 후 최소한 다음 내용을 보고한다.

```text
작업 요약:
기존 관련 구현:
최종 API 또는 계약:
생성·수정 파일:
DB 변경:
테스트 결과:
clean test:
spotlessCheck:
javadoc:
미실행 또는 실패 사유:
제외한 작업:
현재 Branch:
Commit 수행 여부:
Push 수행 여부:
권장 Commit Message:
```

판단 우선순위:

1. 현재 Repository의 실제 코드
2. 적용된 DB Schema와 최신 Flyway Migration
3. 최신 확정 API 명세와 ERD
4. 현재 Jira 요구사항
5. 이 공통 규칙

서로 충돌하면 임의로 병행 구현하지 말고 먼저 보고한다.
