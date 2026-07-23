# Drawing Reflection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 연결 보호자가 그림 활동의 제목과 감정 표현을 PUT 방식으로 저장하고 세션을 REFLECTION 단계로 전이한다.

**Architecture:** `DrawingReflectionService`가 인증·소유권·상태 검증과 Transaction을 조율한다. 세션 상태는 `DrawingSession`, 정규화된 선택 감정은 `DrawingSessionEmotion`과 전용 Repository가 관리한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Jakarta Validation, MySQL 8.4, JUnit 5, Mockito, MockMvc, Testcontainers

## Global Constraints

- Endpoint는 `PUT /api/v1/drawing-sessions/{drawingSessionId}/reflection` 하나만 추가한다.
- 기존 `ApiResponse`, `GlobalExceptionHandler`, 인증 Resolver와 `GuardianResourceAccessValidator`를 재사용한다.
- 기존 Flyway Migration을 수정하거나 새 Migration을 추가하지 않는다.
- 후속 그림 단계 완료, 전체 활동 완료와 리포트 생성을 구현하지 않는다.
- 사용자의 별도 요청 전에는 Commit, Push, Merge Request를 수행하지 않는다.

---

### Task 1: 감정 요청 계약과 도메인 모델

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingEmotionCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSessionEmotion.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/request/SaveDrawingReflectionRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/dto/response/DrawingReflectionResponse.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/dto/request/SaveDrawingReflectionRequestTest.java`

**Interfaces:**
- Produces: `DrawingEmotionCode`, `DrawingSessionEmotion.create(DrawingSession, DrawingEmotionCode, int)`, 요청·응답 record

- [ ] 요청 조합 검증 테스트를 먼저 작성한다.

```java
assertThat(request.validationError()).isEmpty();
assertThat(invalidUnknownCombination.validationError())
    .contains(DrawingErrorCode.DRAWING_REFLECTION_INVALID);
```

- [ ] 테스트를 실행해 새 타입 부재로 실패하는지 확인한다.

```powershell
gradlew.bat test --tests "*SaveDrawingReflectionRequestTest"
```

- [ ] 감정 Enum, 감정 Entity와 요청 정규화·교차 검증을 구현한다.

```java
public enum DrawingEmotionCode {
  HAPPY, SAD, ANGRY, SCARED, CALM, UNKNOWN
}
```

- [ ] 요청 계약 테스트를 다시 실행해 통과시킨다.

### Task 2: 세션 상태 전이와 저장 Service

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/repository/DrawingSessionEmotionRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingReflectionService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/exception/DrawingErrorCode.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/service/DrawingReflectionServiceTest.java`

**Interfaces:**
- Consumes: Task 1의 요청·응답·감정 타입
- Produces: `DrawingReflectionService.save(Long, SaveDrawingReflectionRequest)`

- [ ] 정상 저장, 건너뛰기, 권한 거부, 단계 거부와 기존 감정 교체 단위 테스트를 작성한다.

```java
DrawingReflectionResponse response = service.save(10L, request);
assertThat(response.currentStage()).isEqualTo(DrawingStage.REFLECTION);
verify(accessValidator).requireDrawingSessionAccess(41L, 10L);
```

- [ ] Service 테스트를 실행해 구현 부재로 실패하는지 확인한다.

- [ ] `DrawingSession.canSaveReflection()`과 `saveReflection(title, text)`를 구현하고 Service에서 쓰기 잠금과 감정 교체를 수행한다.

```java
emotionRepository.deleteAllByDrawingSessionId(drawingSessionId);
emotionRepository.saveAll(requestedEmotions);
session.saveReflection(normalizedTitle, normalizedText);
```

- [ ] Service 테스트를 다시 실행해 통과시킨다.

### Task 3: HTTP API와 MySQL 영속성 검증

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/drawing/controller/DrawingReflectionController.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/controller/DrawingReflectionControllerTest.java`
- Test: `backend/src/test/java/com/ssafy/b209/drawing/DrawingReflectionIntegrationTest.java`

**Interfaces:**
- Consumes: `DrawingReflectionService.save`
- Produces: `PUT /api/v1/drawing-sessions/{drawingSessionId}/reflection`

- [ ] MockMvc 계약 테스트를 작성해 200 공통 응답과 요청 Validation 오류를 고정한다.

```java
mockMvc.perform(put("/api/v1/drawing-sessions/10/reflection")
    .contentType(APPLICATION_JSON)
    .content(requestJson))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.data.currentStage").value("REFLECTION"));
```

- [ ] Controller 테스트를 실행해 404 또는 Bean 부재로 실패하는지 확인한다.

- [ ] Controller와 OpenAPI 설명을 구현하고 공통 `ApiResponse.ok`를 반환한다.

- [ ] Testcontainers MySQL 통합 테스트를 작성해 제목·직접 표현·단계와 감정 선택 순서가 저장되고 재요청 시 목록이 교체되는지 검증한다.

- [ ] Controller 및 통합 테스트를 실행해 통과시킨다.

### Task 4: 회귀와 품질 검증

**Files:**
- Verify: `backend/src/main/java/com/ssafy/b209/drawing/**`
- Verify: `backend/src/test/java/com/ssafy/b209/drawing/**`

- [ ] 전체 테스트를 실행한다.

```powershell
gradlew.bat --no-daemon clean test
```

- [ ] Spotless를 검사하고 import·서식 오류를 수정한다.

```powershell
gradlew.bat --no-daemon spotlessCheck
```

- [ ] UTF-8 Javadoc을 생성하고 새 공개 타입의 오류가 없는지 확인한다.

```powershell
gradlew.bat --no-daemon javadoc
```

- [ ] `build/docs/javadoc/index.html`, `git diff --check`, 변경 파일 범위와 DB 변경 없음 여부를 확인한다.
