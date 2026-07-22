# Drawing Analysis Result Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저장된 그림 분석의 진행 상태와 객체 탐지 결과를 Session·Analysis 식별자로 안전하게 조회한다.

**Architecture:** 기존 분석 Aggregate를 Fetch Join으로 읽고 별도 `DrawingAnalysisQueryService`가 상태 정합성을 검증해 공개 DTO로 변환한다. Controller는 입력 검증과 공통 200 응답만 담당하며 AI Client와 파일 저장소에는 접근하지 않는다.

**Tech Stack:** Java 21, Spring Boot, Spring Data JPA, MySQL 8, JUnit 5, Mockito, MockMvc, Testcontainers

## Global Constraints

- Branch 이름에는 Jira 코드를 넣지 않는다.
- DB의 `SUCCESS`는 API의 `SUCCEEDED`로 변환한다.
- 존재하지 않는 Analysis·Detection Soft Delete 컬럼과 인증 방식을 추가하지 않는다.
- 기존 Migration은 수정하지 않고 이번 조회 기능에는 새 Migration을 추가하지 않는다.
- 새 공개 Java 타입과 메서드에는 실제 역할을 설명하는 한국어 Javadoc을 작성한다.
- Commit, push, merge는 사용자의 별도 요청 전에는 수행하지 않는다.

---

### Task 1: 상태 조회 Service와 DTO

**Files:**
- Create: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisQueryServiceTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisQueryService.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/dto/DrawingAnalysisDetailResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/analysis/dto/DrawingAnalysisFailureResponse.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/exception/DrawingAnalysisErrorCode.java`

**Interfaces:**
- Consumes: `DrawingAnalysisRepository.findDetailBySessionIdAndAnalysisId(Long, Long)`
- Produces: `DrawingAnalysisDetailResponse getDrawingAnalysis(Long drawingSessionId, Long drawingAnalysisId)`

- [ ] 상태별 응답과 모순 데이터 오류를 표현하는 실패 테스트를 먼저 작성한다.
- [ ] 해당 테스트가 신규 Service·DTO 부재로 실패하는지 확인한다.
- [ ] 최소 DTO, 오류 코드, 읽기 전용 Query Service를 구현한다.
- [ ] Service 테스트가 통과하는지 확인한다.

### Task 2: Fetch 조회와 Detection 순서

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/domain/DrawingAnalysis.java`
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/DrawingAnalysisIntegrationTest.java`

**Interfaces:**
- Produces: Session·Asset·Detection을 함께 읽는 `findDetailBySessionIdAndAnalysisId`

- [ ] 저장된 Detection 정렬, 다른 Session, 삭제된 Session 조회 실패 테스트를 추가한다.
- [ ] 새 조회 메서드가 없어 테스트가 실패하는지 확인한다.
- [ ] Fetch Join과 `displayOrder`, ID 순서를 적용한다.
- [ ] Repository·통합 테스트가 통과하는지 확인한다.

### Task 3: GET Controller와 Swagger

**Files:**
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/controller/DrawingAnalysisControllerTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/controller/DrawingAnalysisOpenApiTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/controller/DrawingAnalysisController.java`

**Interfaces:**
- Produces: `GET /api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}`

- [ ] 성공·FAILED 200, 잘못된 Path 400, 조회 실패 응답과 OpenAPI 테스트를 먼저 추가한다.
- [ ] GET Mapping 부재로 실패하는지 확인한다.
- [ ] Controller Mapping, 공통 `ApiResponse`, Swagger 설명을 구현한다.
- [ ] Controller·OpenAPI 테스트가 통과하는지 확인한다.

### Task 4: 문서와 전체 검증

**Files:**
- Modify: `docs/api/ai-drawing-analysis-contract.md`

- [ ] 공개 조회 Endpoint, Polling 상태, FAILED 200, 빈 Detection, AI 재호출·자동 재시도 없음 정책을 기록한다.
- [ ] `gradlew.bat clean test`를 실행한다.
- [ ] `gradlew.bat spotlessCheck`를 실행한다.
- [ ] `gradlew.bat javadoc`을 실행하고 `backend/build/docs/javadoc/index.html` 생성 여부를 확인한다.
- [ ] Git diff에서 비밀값, 범위 밖 변경, Migration 변경이 없는지 확인한다.
