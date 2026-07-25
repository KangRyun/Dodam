# S15P11B209-538 그림 단계 완료 API 구현 계획

> 기준 설계: `docs/superpowers/specs/2026-07-25-drawing-stage-complete-design.md`

## Task 1. 세션 상태 전이 Domain 구현

**Files**

- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingSessionDomainTest.java`

1. `DRAWING -> ANALYZING`과 `ANALYZING -> CONVERSING` 정상 전이 테스트를 먼저 작성한다.
2. 삭제·완료·잘못된 단계에서 전이가 거부되는 테스트를 작성한다.
3. 필요한 최소 Domain 메서드와 실제 책임을 설명하는 한국어 Javadoc을 구현한다.
4. Domain 테스트를 실행해 통과를 확인한다.

## Task 2. 분석 요청 멱등 키와 FINAL 상태 전이 연계

**Files**

- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/repository/DrawingAnalysisRepository.java`
- Add: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisRequestSummary.java`
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisServiceTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/analysis/service/DrawingAnalysisPersistenceServiceTest.java`

1. 호출자가 지정한 `requestId`로 분석을 시작하는 실패 테스트를 작성한다.
2. FINAL 분석 시작 시 `ANALYZING`, 성공·실패 확정 시 `CONVERSING`이 되는 테스트를 작성한다.
3. `requestId`로 기존 분석의 세션·asset·상태를 조회하는 테스트를 작성한다.
4. 기존 무작위 UUID 기반 공개 분석 API 동작을 유지하면서 완료 흐름용 메서드를 최소 확장한다.
5. 분석 단위 테스트를 실행해 회귀가 없는지 확인한다.

## Task 3. 그림 단계 완료 Application Service 구현

**Files**

- Add: `backend/src/main/java/com/ssafy/b209/drawing/dto/request/CompleteDrawingStageRequest.java`
- Add: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingStageAnalysisResponse.java`
- Add: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/CompleteDrawingStageResponse.java`
- Add: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingStageCompletionService.java`
- Add: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingStageCompletionServiceTest.java`

1. 최초 완료, 동일 키 재시도, 다른 세션의 키 재사용, FINAL 중복, 잘못된 metadata 테스트를 작성한다.
2. 최초 요청에서는 기존 `DrawingSnapshotService`로 FINAL 이미지와 실제 크기를 저장한다.
3. 유효한 `sourceAssetId`가 있으면 같은 세션 FINAL asset인지 검증해 재사용한다.
4. `Idempotency-Key`로 `OBJECT_DETECTION`을 호출하고 실제 성공 상태를 응답한다.
5. AI 호출 실패 시 저장된 FAILED 분석을 조회해 `SELECT_EMOTION` 폴백 응답을 반환한다.
6. Service 단위 테스트를 실행한다.

## Task 4. Multipart Controller와 OpenAPI 구현

**Files**

- Add: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingStageCompletionController.java`
- Add: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingStageCompletionControllerTest.java`
- Add: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingStageCompletionOpenApiTest.java`

1. `finalImage`, JSON `metadata`, `Idempotency-Key` 수신과 공통 응답 테스트를 먼저 작성한다.
2. Header 누락·형식 오류, metadata 검증, 파일 Stream 오류 테스트를 작성한다.
3. Controller는 Multipart 변환, Validation, Service 호출과 `ApiResponse<T>` 조립만 담당한다.
4. MockMvc 및 OpenAPI 테스트를 실행한다.

## Task 5. 통합 흐름 및 명세 정합성 검증

**Files**

- Add: `backend/src/test/java/com/ssafy/b209/drawing/DrawingStageCompletionIntegrationTest.java`
- Modify: `docs/api/API_명세서_최종.md`

1. FINAL 저장, 이미지 크기, 분석 저장, 세션 단계와 멱등 재요청을 H2/MySQL 호환 통합 테스트로 검증한다.
2. 명세 10.8의 `INTERMEDIATE/PENDING/POLL_ANALYSIS` 예시를
   `OBJECT_DETECTION/SUCCEEDED/SELECT_EMOTION` 동기 계약으로 수정한다.
3. 기존 `/complete`와 그림·분석 관련 회귀 테스트를 실행한다.

## Task 6. 전체 검증과 Git 마무리

1. `backend/gradlew.bat clean test`를 실행한다.
2. `backend/gradlew.bat spotlessCheck`를 실행한다.
3. `backend/gradlew.bat javadoc`을 실행하고
   `backend/build/docs/javadoc/index.html` 생성 여부를 확인한다.
4. `git diff --check`, 변경 파일과 Secret 포함 여부를 확인한다.
5. 이슈 코드가 포함된 커밋으로 정리하고 Push 및 Merge Request를 생성한다.
6. Pipeline이 통과하면 Merge하고 Jira S15P11B209-538을 완료 처리한다.
