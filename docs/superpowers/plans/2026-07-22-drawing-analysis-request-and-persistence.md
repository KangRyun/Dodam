# Drawing Analysis Request and Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최종 그림 스냅샷을 Mock AI Client로 분석하고 실행 이력과 객체 탐지 결과를 저장하는 동기식 REST API를 구현한다.

**Architecture:** `DrawingAnalysisService`가 Transaction 밖에서 Client 호출을 조율하고, `DrawingAnalysisPersistenceService`가 시작·성공·실패 저장을 독립 Transaction으로 처리한다. 기존 ERD 의미는 유지하며 V5는 신규 API에 필요한 연결 컬럼과 중복 방지 제약, 픽셀 좌표 정밀도만 순방향으로 보강한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Bean Validation, Flyway, MySQL 8.4, JUnit 5, Mockito, MockMvc, Testcontainers

**Execution Status:** 2026-07-22 구현 및 검증 완료. `DrawingDetectedObject`는 `DrawingAnalysis`의 Cascade로 함께 저장되므로 사용되지 않는 별도 Repository는 생성하지 않았다.

## Global Constraints

- Repository 루트 `AGENTS.md`와 한국어 Javadoc 규칙을 따른다.
- V1~V4 및 `docs/database/erd-cloud-schema-v1.2.sql`을 수정하지 않는다.
- Branch 이름에는 Jira 코드를 넣지 않고 Commit 제안에는 `S15P11B209-147`을 포함한다.
- 실제 Commit, Push, Merge는 사용자가 명시적으로 요청하기 전 수행하지 않는다.
- Service는 `DrawingAnalysisClient` Interface만 참조하고 실제 AI 네트워크 호출은 추가하지 않는다.
- Entity, 응답, 로그에 내부 저장 경로와 AI 원문 오류를 노출하지 않는다.

---

### Task 1: V5 분석 저장 스키마

**Files:**
- Create: `backend/src/main/resources/db/migration/V5__support_drawing_analysis_requests.sql`
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Consumes: V1 `analyses`, `analysis_detected_objects`, `drawing_assets`; V4의 최종 스냅샷 Unique 정책
- Produces: `analyses.drawing_asset_id`, `analyses.analysis_task_type`, 활성 분석 Unique Index와 픽셀 Bounding Box 컬럼

- [ ] **Step 1: V5 구조를 기대하는 실패 테스트 작성**

  Flyway 최신 버전 `5`, 신규 컬럼·FK·Check·Unique Index, `DECIMAL(12,3)` Bounding Box를 `information_schema`로 검증한다. 동일 자산·작업의 `PROCESSING`/`SUCCESS`는 충돌하고 `FAILED` 이후 재시도는 허용하는 SQL Fixture를 추가한다.

- [ ] **Step 2: Migration 테스트 RED 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.database.DatabaseMigrationIntegrationTest`

  Expected: V5가 없어 최신 버전 또는 신규 컬럼 Assertion이 실패한다.

- [ ] **Step 3: 최소 V5 Migration 작성**

  `drawing_asset_id`와 `analysis_task_type`을 Nullable로 추가하고 명확히 추론 가능한 Legacy 자산만 역채움한다. FK, 작업 유형 Check, 중복 조회 Index, `PROCESSING`/`SUCCESS` 전용 생성 컬럼과 Unique Index를 추가하고 Bounding Box 타입과 범위 Check를 보강한다.

- [ ] **Step 4: Migration 테스트 GREEN 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.database.DatabaseMigrationIntegrationTest`

  Expected: PASS, 기존 63개 업무 테이블 수는 유지된다.

### Task 2: 분석 및 Detection Domain

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysis.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysisScope.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysisState.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingDetectedObject.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/domain/DrawingAnalysisDomainTest.java`

**Interfaces:**
- Consumes: `DrawingSession`, `DrawingAsset`, 계약 enum `DrawingAnalysisType`
- Produces: `DrawingAnalysis.processing(...)`, `succeed(...)`, `fail(...)`와 Detection 값 객체 생성 규칙

- [ ] **Step 1: 상태 전이와 값 검증 실패 테스트 작성**

  PROCESSING 생성, SUCCESS 전이, FAILED 전이, 잘못된 confidence/좌표 거부, 빈 Detection 성공을 각각 검증한다.

- [ ] **Step 2: Domain 테스트 RED 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.domain.DrawingAnalysisDomainTest`

  Expected: Domain 타입이 없어 컴파일이 실패한다.

- [ ] **Step 3: 최소 Domain 구현**

  Public Setter 없이 Factory와 상태 변경 Method만 제공한다. DB `analysis_type`은 `DrawingAnalysisScope`, `analysis_status`는 `DrawingAnalysisState.SUCCESS`, `analysis_task_type`은 계약 `DrawingAnalysisType`에 매핑한다.

- [ ] **Step 4: Domain 테스트 GREEN 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.domain.DrawingAnalysisDomainTest`

  Expected: PASS.

### Task 3: Repository와 분리 Transaction 저장

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceService.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/service/StartedDrawingAnalysis.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingAssetRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceServiceTest.java`

**Interfaces:**
- Consumes: Domain Factory/전이 Method와 Session Pessimistic Lock
- Produces: `start(...)`, `complete(...)`, `fail(...)` 독립 Transaction API

- [ ] **Step 1: 저장 규칙 실패 테스트 작성**

  세션 없음, 분석 불가 상태, 자산 없음, 다른 세션 자산, FINAL이 아닌 자산, 진행·성공 중복, FAILED 재요청, 성공 저장과 실패 상태 보존을 검증한다.

- [ ] **Step 2: Persistence 테스트 RED 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.service.DrawingAnalysisPersistenceServiceTest`

  Expected: 저장 Service와 Repository가 없어 컴파일이 실패한다.

- [ ] **Step 3: 최소 저장 Service 구현**

  각 Public Method에 `REQUIRES_NEW`를 적용한다. 시작 시 세션을 잠그고 FINAL 자산과 중복을 검증한 뒤 `saveAndFlush`하며, 완료 시 Detection을 순서대로 연결하고 `SUCCESS`, 실패 시 안전한 코드·메시지로 `FAILED`를 저장한다.

- [ ] **Step 4: Persistence 테스트 GREEN 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.service.DrawingAnalysisPersistenceServiceTest`

  Expected: PASS.

### Task 4: Client 조율 Service와 API DTO

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/analysis/dto/CreateDrawingAnalysisRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/dto/CreateDrawingAnalysisResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/exception/DrawingAnalysisErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisServiceTest.java`

**Interfaces:**
- Consumes: `DrawingAnalysisPersistenceService`, `DrawingAnalysisClient`, `Clock`, UUID Supplier, Bean `Validator`
- Produces: `CreateDrawingAnalysisResponse request(Long, CreateDrawingAnalysisRequest)`

- [ ] **Step 1: 조율 동작 실패 테스트 작성**

  서버 UUID 생성, Client 요청의 Storage Key·MIME 전달, 정상 성공, 빈 Detection, requestId 불일치, 잘못된 응답, Client 실패, 결과 저장 실패와 각 FAILED 기록 호출을 검증한다.

- [ ] **Step 2: Service 테스트 RED 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.service.DrawingAnalysisServiceTest`

  Expected: Service/DTO/ErrorCode가 없어 컴파일이 실패한다.

- [ ] **Step 3: 최소 조율 Service 구현**

  UUID와 UTC 시각을 생성하고 시작 행 저장 후 Transaction 밖에서 Interface를 호출한다. 동기식 API는 `SUCCEEDED`만 성공으로 수용하며 계약 위반과 Client 예외를 502 오류로 변환하고, 결과 저장 오류는 안전한 500 오류로 변환한다.

- [ ] **Step 4: Service 테스트 GREEN 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.service.DrawingAnalysisServiceTest`

  Expected: PASS.

### Task 5: Controller와 OpenAPI

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/analysis/controller/DrawingAnalysisController.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/controller/DrawingAnalysisControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/analysis/controller/DrawingAnalysisOpenApiTest.java`

**Interfaces:**
- Consumes: `DrawingAnalysisService.request(...)`, 공통 `ApiResponse`와 `CommonSuccessCode.CREATED`
- Produces: `POST /api/v1/drawing-sessions/{drawingSessionId}/analyses`, HTTP 201, 분석 리소스 Location

- [ ] **Step 1: Controller 계약 실패 테스트 작성**

  정상 201 Body/Location, Path 양수 검증, 필수 필드 누락, 잘못된 enum, 404/409/502 공통 오류, Swagger 응답 코드와 Tag를 검증한다.

- [ ] **Step 2: Controller 테스트 RED 확인**

  Run: `gradlew.bat test --tests 'com.ssafy.b209.analysis.controller.*'`

  Expected: Controller가 없어 Context 또는 Endpoint Assertion이 실패한다.

- [ ] **Step 3: 최소 Controller 구현**

  Controller는 입력 검증, Service 호출, `Location` 조립과 공통 응답 변환만 수행한다. 공개 클래스와 Method에는 실제 책임에 맞는 한국어 Javadoc을 작성한다.

- [ ] **Step 4: Controller 테스트 GREEN 확인**

  Run: `gradlew.bat test --tests 'com.ssafy.b209.analysis.controller.*'`

  Expected: PASS.

### Task 6: MySQL 통합과 전체 품질 검증

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/analysis/DrawingAnalysisIntegrationTest.java`
- Modify: 구현 중 형식 또는 Javadoc 오류가 발견된 이번 이슈 파일만 수정

**Interfaces:**
- Consumes: 실제 Flyway V5, JPA Entity, Mock Client Bean, REST Endpoint
- Produces: API부터 MySQL 분석·Detection 저장까지의 회귀 증거

- [ ] **Step 1: 통합 실패 테스트 작성**

  FINAL 자산 Fixture로 201과 두 Detection 저장, 후속 409, Client 실패 시 FAILED 보존 및 이후 재요청 허용을 검증한다. 외부 HTTP 요청은 발생하지 않는 `mock` 설정을 사용한다.

- [ ] **Step 2: 통합 테스트 RED 확인**

  Run: `gradlew.bat test --tests com.ssafy.b209.analysis.DrawingAnalysisIntegrationTest`

  Expected: 누락된 Endpoint 또는 저장 동작으로 실패한다.

- [ ] **Step 3: 통합 실패 원인에 필요한 최소 수정**

  새 기능 범위 안에서만 Mapping, Transaction 경계 또는 Test Fixture를 수정하고 기존 SQL 의미는 변경하지 않는다.

- [ ] **Step 4: 전체 검증**

  Run: `gradlew.bat clean test`

  Run: `gradlew.bat spotlessCheck`

  Run: `gradlew.bat javadoc`

  Expected: 모두 BUILD SUCCESSFUL이며 `backend/build/docs/javadoc/index.html`이 존재한다.

- [ ] **Step 5: Commit 제안만 준비**

  Suggested: `[S15P11B209-147] feat(analysis): 그림 분석 요청 및 결과 저장 API 구현`

  사용자의 별도 요청 전에는 Commit, Push, Merge를 실행하지 않는다.
