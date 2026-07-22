# Child Detail Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 연결 보호자가 삭제되지 않은 아동 상세 프로필을 조회하는 `GET /api/v1/children/{childId}` API를 구현한다.

**Architecture:** 기존 임시 보호자 식별 경계를 재사용하고, `children`, `guardian_child_relations`, `child_response_modes`를 조회 전용 Projection으로 조합한다. Service가 만 나이와 UTC 응답 시각을 계산하며 Controller는 Validation과 공통 응답만 담당한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Jakarta Validation, springdoc-openapi, JUnit 5, Mockito, MockMvc, Gradle

## Global Constraints

- 루트 `AGENTS.md`와 최신 API 명세를 따른다.
- 기존 Flyway Migration은 수정하지 않으며 이번 이슈에는 Schema 변경이 없다.
- 신규 인증 인프라를 만들지 않고 기존 `TemporaryGuardianResolver`를 재사용한다.
- Production public Type과 의미가 필요한 public Method에는 실제 동작과 일치하는 한국어 Javadoc을 작성한다.
- 성공 응답은 `ApiResponse<T>`, 오류는 `BusinessException`과 `GlobalExceptionHandler`를 사용한다.
- 사용자 요청 전에는 Commit, Push, Merge를 수행하지 않는다.

---

### Task 1: 조회 Service 계약을 TDD로 구현

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/child/dto/response/ChildDetailResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/child/exception/ChildErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/child/repository/ChildDetailProjection.java`
- Modify: `backend/src/main/java/com/ssafy/b209/child/repository/ChildRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/child/service/ChildQueryService.java`
- Test: `backend/src/test/java/com/ssafy/b209/child/service/ChildQueryServiceTest.java`

**Interfaces:**
- Consumes: `ChildRepository`, `Clock`, `BusinessException`
- Produces: `ChildDetailResponse getChild(Long guardianUserId, Long childId)`

- [ ] **Step 1: Write the failing Service tests**

정상 Projection을 응답으로 변환하고, 생일 전후 만 나이, 정렬된 `responseModes`, 조회 실패 시 `ChildErrorCode.CHILD_NOT_FOUND`를 검증한다.

- [ ] **Step 2: Run tests to verify RED**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.service.ChildQueryServiceTest"`

Expected: 신규 Service와 DTO가 없어 test compilation이 실패한다.

- [ ] **Step 3: Implement the minimal query contract**

`ChildDetailProjection`, `ChildDetailResponse`, `ChildErrorCode`, Repository Query, `ChildQueryService`를 추가한다. Query는 연결 관계, 삭제 시각, 활성 상태를 한 번에 제한하고 응답 방식은 표시 순서로 별도 조회한다.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.service.ChildQueryServiceTest"`

Expected: 모든 Service 테스트가 통과한다.

### Task 2: HTTP 및 OpenAPI 계약을 TDD로 구현

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/child/controller/ChildController.java`
- Test: `backend/src/test/java/com/ssafy/b209/child/controller/ChildControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/child/controller/ChildOpenApiTest.java`

**Interfaces:**
- Consumes: `TemporaryGuardianResolver.resolve(String, String)`, `ChildQueryService.getChild(Long, Long)`
- Produces: `GET /api/v1/children/{childId}`

- [ ] **Step 1: Write failing MockMvc and OpenAPI tests**

HTTP 200 공통 응답, 0 이하 Path의 400, 인증 누락의 401, Service 404 및 OpenAPI 응답 코드를 검증한다.

- [ ] **Step 2: Run tests to verify RED**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.controller.*"`

Expected: `ChildController`가 없어 Endpoint 또는 Spring Bean 검증이 실패한다.

- [ ] **Step 3: Implement the minimal Controller**

`@Validated`, `@Positive`, 기존 임시 Header 계약, `ApiResponse.ok`, 정확한 OpenAPI 응답 설명을 추가한다. Controller는 Repository를 직접 호출하지 않는다.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.controller.*"`

Expected: Controller와 OpenAPI 테스트가 모두 통과한다.

### Task 3: Repository 계약과 문서를 검증

**Files:**
- Test: `backend/src/test/java/com/ssafy/b209/child/repository/ChildRepositoryTest.java`
- Modify: `README.md`

**Interfaces:**
- Consumes: 현재 MySQL 8.x `children`, `guardian_child_relations`, `child_response_modes` Schema
- Produces: 소유권·Soft Delete·활성 상태·응답 순서 회귀 테스트와 API 사용 안내

- [ ] **Step 1: Write failing Repository tests**

연결된 보호자 조회 성공, 다른 보호자/삭제/비활성 아동 제외, 응답 방식의 `display_order`, `id` 정렬을 실제 Query로 검증한다.

- [ ] **Step 2: Run tests to verify RED or expose query defects**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.repository.ChildRepositoryTest"`

Expected: Query 또는 테스트용 Schema가 계약을 충족하기 전 실패한다.

- [ ] **Step 3: Complete repository mapping and README**

DB Alias와 Projection Type을 맞추고 README에 Endpoint, 임시 인증 제한, 성공/오류 예시, 조회의 무부수효과를 추가한다.

- [ ] **Step 4: Run repository and focused child tests**

Run: `gradlew.bat test --tests "com.ssafy.b209.child.*"`

Expected: 아동 조회 관련 테스트가 모두 통과한다.

### Task 4: 전체 품질 검증

**Files:**
- Modify only if verification identifies an issue in files introduced by Tasks 1-3.

**Interfaces:**
- Consumes: 모든 구현·테스트·문서 변경
- Produces: Commit 가능한 검증 완료 작업 트리

- [ ] **Step 1: Run full tests**

Run: `gradlew.bat clean test`

Expected: BUILD SUCCESSFUL, 실패 테스트 0건.

- [ ] **Step 2: Run formatting verification**

Run: `gradlew.bat spotlessCheck`

Expected: BUILD SUCCESSFUL. 실패 시 `spotlessApply` 후 변경 범위를 검토하고 다시 실행한다.

- [ ] **Step 3: Generate Javadoc**

Run: `gradlew.bat javadoc`

Expected: BUILD SUCCESSFUL and `backend/build/docs/javadoc/index.html` exists.

- [ ] **Step 4: Review scope and Git diff**

Run: `git diff --check`, `git status --short`, `git diff --stat`

Expected: 공백 오류가 없고 S15P11B209-137 범위 파일만 변경돼 있다.

- [ ] **Step 5: Stop before Git mutations**

권장 Commit Message `feat: S15P11B209-137 아동 정보 조회 API 구현`을 보고하고 사용자 요청 전에는 Commit, Push, Merge를 수행하지 않는다.
