# Drawing Types Start Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 원격 API 모드에서 아동에게 허용된 그림 유형을 조회하고 새 그림 세션을 생성해 그림 화면으로 이동할 수 있게 한다.

**Architecture:** Backend는 인증 사용자와 아동 관계를 검증한 뒤 `drawing_types`의 활성·연령·분류 조건을 적용해 공통 응답 봉투 안에 목록 페이지를 반환한다. Flutter는 최신 Query 계약을 사용하고 공통 응답의 `data`를 해제한 뒤 기존 `ApiPage`와 `DrawingSessionDto`로 역직렬화한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, MySQL 8/Flyway, JUnit 5/MockMvc, Flutter/Dart, Dio

## Global Constraints

- 기존 `ApiResponse<T>`, 인증 Resolver, `GuardianResourceAccessValidator`를 재사용한다.
- 적용된 Flyway Migration은 수정하지 않고 새 Migration만 추가한다.
- Entity를 API 응답으로 노출하지 않으며 공개 Java Type에는 실제 동작과 일치하는 한국어 Javadoc을 작성한다.
- `childId`는 필수이고 Query는 `category`, `activeOnly=true` 계약을 따른다.
- 아동 생년월일, Token, 서버 경로를 로그나 오류 응답으로 노출하지 않는다.

---

### Task 1: Backend 그림 유형 조회 계약

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingType.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingTypeRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingTypeResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingTypePageResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingTypeQueryService.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingTypeController.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingTypeQueryServiceTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingTypeControllerTest.java`

**Interfaces:**
- Consumes: `CurrentAuthenticatedUserResolver.requireUserId()`, `GuardianResourceAccessValidator.requireChildAccess(userId, childId)`, `Child.ageOn(LocalDate)`
- Produces: `DrawingTypeQueryService.getDrawingTypes(Long childId, DrawingActivityCategory category, boolean activeOnly)`

- [ ] **Step 1: 서비스 실패 테스트 작성**

  연결되지 않은 아동은 조회하지 않고 실패하며, 연결된 아동은 만 나이·분류·활성 조건에 맞는 유형만 `displayOrder`, `id` 순으로 반환하는 테스트를 작성한다.

- [ ] **Step 2: 서비스 RED 확인**

  Run: `gradlew.bat test --tests "*DrawingTypeQueryServiceTest"`

  Expected: `DrawingTypeQueryService`가 없어 컴파일 또는 테스트가 실패한다.

- [ ] **Step 3: Controller 실패 테스트 작성**

  `GET /api/v1/drawing-types?childId=1&category=GENERAL&activeOnly=true`가 인증 사용자 기준 Service를 호출하고 `{success, code, message, data:{content,...}}`를 반환하는 MockMvc 테스트를 작성한다. 누락·음수 `childId`, 잘못된 Enum도 검증한다.

- [ ] **Step 4: Controller RED 확인**

  Run: `gradlew.bat test --tests "*DrawingTypeControllerTest"`

  Expected: `/api/v1/drawing-types` Mapping 부재로 404 또는 컴파일 실패가 발생한다.

- [ ] **Step 5: 최소 구현**

  `DrawingType`에 `guideText`, `displayOrder`를 매핑하고 필요한 Getter를 추가한다. Repository는 필터 조합을 명시적으로 조회하고, Service는 인증·아동 권한·나이 계산 후 응답 DTO를 만든다. Controller는 검증과 공통 응답 조립만 담당한다.

- [ ] **Step 6: Backend GREEN 확인**

  Run: `gradlew.bat test --tests "*DrawingTypeQueryServiceTest" --tests "*DrawingTypeControllerTest"`

  Expected: 두 테스트 클래스가 모두 통과한다.

### Task 2: 운영 기준 데이터

**Files:**
- Create: `backend/src/main/resources/db/migration/V12__seed_drawing_types.sql`
- Test: `backend/src/test/java/com/ssafy/b209/database/MigrationVersionTest.java`

**Interfaces:**
- Consumes: `drawing_types` V1 Schema
- Produces: 안정적인 업무 코드 `ART_DIARY`, `FREE_DRAWING`, `EMOTION_COLORING`, `WEATHER_MIND`

- [ ] **Step 1: Migration 계약 실패 테스트 작성**

  Migration 파일명이 중복되지 않고 필수 코드, 사용자 안내, 노출 순서를 포함하는지 검증한다.

- [ ] **Step 2: RED 확인**

  Run: `gradlew.bat test --tests "*MigrationVersionTest"`

  Expected: V12 파일 또는 필수 기준 데이터가 없어 실패한다.

- [ ] **Step 3: 멱등 Seed Migration 작성**

  업무 코드 Unique Key를 기준으로 기존 운영 데이터를 덮어쓰지 않으면서 누락된 기준 데이터만 추가한다. 검사·진단을 암시하는 문구는 사용하지 않는다.

- [ ] **Step 4: GREEN 확인**

  Run: `gradlew.bat test --tests "*MigrationVersionTest"`

  Expected: Migration 버전과 Seed 계약 테스트가 통과한다.

### Task 3: Flutter Query 및 공통 응답 해제

**Files:**
- Modify: `frontend/mobile/lib/features/drawing/domain/repositories/drawing_repository.dart`
- Modify: `frontend/mobile/lib/features/drawing/data/repositories/remote_drawing_repository.dart`
- Modify: `frontend/mobile/lib/features/drawing/data/repositories/mock_drawing_repository.dart`
- Modify: `frontend/mobile/test/features/guardian/guardian_child_entry_test.dart`
- Create: `frontend/mobile/test/features/drawing/remote_drawing_repository_test.dart`

**Interfaces:**
- Consumes: Backend 공통 응답 `{success, code, message, data}`
- Produces: `getDrawingTypes({required int childId, String? category, bool activeOnly = true})`

- [ ] **Step 1: 원격 Repository 실패 테스트 작성**

  Dio Adapter로 봉투에 감싼 그림 유형 페이지와 세션 생성 응답을 반환한다. Query가 `childId`, `category`, `activeOnly`을 보내고 결과 DTO가 역직렬화되는지 검증한다.

- [ ] **Step 2: Flutter RED 확인**

  Run: `flutter test test/features/drawing/remote_drawing_repository_test.dart`

  Expected: 기존 구현이 `data`를 해제하지 않거나 `ageGroup`을 전송해 실패한다.

- [ ] **Step 3: 최소 구현**

  `envelopeObject()`를 사용해 두 응답의 `data`를 해제하고 Repository 계약과 Mock 구현을 최신 Query에 맞춘다.

- [ ] **Step 4: Flutter GREEN 확인**

  Run: `flutter test test/features/drawing/remote_drawing_repository_test.dart`

  Expected: 응답 봉투 및 Query 계약 테스트가 통과한다.

### Task 4: 문서·회귀 검증 및 통합

**Files:**
- Modify: `docs/api/API_명세서_최종.md`
- Modify: `README.md` only if a new operational note is required

- [ ] **Step 1: API 문서 보완**

  `GET /api/v1/drawing-types`의 공통 페이지 응답, 기본 정렬, `activeOnly=false` 동작과 기준 데이터 코드를 실제 구현에 맞게 기록한다.

- [ ] **Step 2: Backend 전체 검증**

  Run:
  - `gradlew.bat clean test`
  - `gradlew.bat spotlessCheck`
  - `gradlew.bat javadoc`

  Expected: 모두 성공하고 Javadoc이 `backend/build/docs/javadoc/index.html`에 생성된다.

- [ ] **Step 3: Flutter 전체 검증**

  Run:
  - `dart format --output=none --set-exit-if-changed lib test`
  - `flutter analyze`
  - `flutter test`

  Expected: 모두 성공한다.

- [ ] **Step 4: Commit, Push, MR**

  Commit: `[S15P11B209-404] fix(drawing): 그림 활동 시작 계약 복구`

  최신 `origin/develop`과의 충돌 여부를 다시 확인하고 Push 및 Merge Request 생성 후 Pipeline이 성공하면 Merge한다.
