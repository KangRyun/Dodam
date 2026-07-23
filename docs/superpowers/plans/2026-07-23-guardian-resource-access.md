# Guardian Resource Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 인증된 보호자만 연결 아동과 그 아동의 삭제되지 않은 그림 활동에 접근하도록 공통 검증을 구현하고 현재 그림 활동 Use Case에 적용한다.

**Architecture:** JDBC 존재 여부 Query를 담당하는 `GuardianResourceAccessRepository`와 Domain 오류로 변환하는 `GuardianResourceAccessValidator`를 분리한다. 각 Application Service는 `CurrentAuthenticatedUserResolver`로 사용자 ID를 얻고 Validator를 호출한 뒤 기존 작업을 수행한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring JDBC/JPA, MySQL 8.x, JUnit 5, Mockito, Testcontainers

## Global Constraints

- 기존 `ApiResponse`, `GlobalExceptionHandler`, JWT `SecurityContext` 구조를 유지한다.
- Schema와 적용된 Flyway Migration은 변경하지 않는다.
- 권한 없음과 자원 없음은 같은 404 Domain 오류로 처리한다.
- 전문가 공유와 ADMIN 정책은 구현하지 않는다.
- 사용자 요청 전에는 Commit, Push, Merge를 수행하지 않는다.

---

### Task 1: 공통 Repository와 Validator

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/auth/authorization/GuardianResourceAccessRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/auth/authorization/GuardianResourceAccessValidator.java`
- Create: `backend/src/test/java/com/ssafy/b209/auth/authorization/GuardianResourceAccessValidatorTest.java`
- Create: `backend/src/test/java/com/ssafy/b209/auth/authorization/GuardianResourceAccessRepositoryIntegrationTest.java`

**Interfaces:**
- Produces: `boolean hasChildAccess(Long guardianUserId, Long childId)`
- Produces: `boolean hasDrawingSessionAccess(Long guardianUserId, Long drawingSessionId)`
- Produces: `void requireChildAccess(Long guardianUserId, Long childId)`
- Produces: `void requireDrawingSessionAccess(Long guardianUserId, Long drawingSessionId)`

- [ ] **Step 1: Validator 실패 테스트 작성**

```java
assertThatThrownBy(() -> validator.requireChildAccess(41L, 7L))
    .isInstanceOfSatisfying(BusinessException.class,
        error -> assertThat(error.getErrorCode()).isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));
assertThatThrownBy(() -> validator.requireDrawingSessionAccess(41L, 9L))
    .isInstanceOfSatisfying(BusinessException.class,
        error -> assertThat(error.getErrorCode()).isEqualTo(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
```

- [ ] **Step 2: 테스트가 타입 부재로 실패하는지 확인**

Run: `gradlew.bat test --tests "*GuardianResourceAccessValidatorTest"`

Expected: `GuardianResourceAccessValidator`를 찾을 수 없어 실패

- [ ] **Step 3: Repository와 Validator 최소 구현**

```java
public void requireChildAccess(Long guardianUserId, Long childId) {
  if (!repository.hasChildAccess(guardianUserId, childId)) {
    throw new BusinessException(ChildErrorCode.CHILD_NOT_FOUND);
  }
}

public void requireDrawingSessionAccess(Long guardianUserId, Long drawingSessionId) {
  if (!repository.hasDrawingSessionAccess(guardianUserId, drawingSessionId)) {
    throw new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND);
  }
}
```

Repository Query는 활성·미삭제 아동과 미삭제 그림 활동을 `guardian_child_relations`에 연결해 `exists`만 반환한다.

- [ ] **Step 4: Validator 단위 테스트 통과 확인**

Run: `gradlew.bat test --tests "*GuardianResourceAccessValidatorTest"`

Expected: 허용 2건과 거부 2건 모두 통과

- [ ] **Step 5: 실제 MySQL Schema Repository 테스트 작성·실행**

```java
assertThat(repository.hasChildAccess(guardianId, childId)).isTrue();
assertThat(repository.hasChildAccess(otherGuardianId, childId)).isFalse();
assertThat(repository.hasDrawingSessionAccess(guardianId, drawingSessionId)).isTrue();
```

Run: `gradlew.bat test --tests "*GuardianResourceAccessRepositoryIntegrationTest"`

Expected: MySQL Testcontainers 사용 가능 시 통과, Docker 미사용 가능 시 기존 정책에 따라 skip

### Task 2: 현재 그림 활동 Use Case에 검증 적용

**Files:**
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSessionQueryService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingDraftService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/service/DrawingSnapshotService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisService.java`
- Modify: `backend/src/main/java/com/ssafy/b209/analysis/service/DrawingAnalysisQueryService.java`
- Modify: 해당 Service 단위 테스트

**Interfaces:**
- Consumes: `CurrentAuthenticatedUserResolver.requireUserId()`
- Consumes: Task 1의 `GuardianResourceAccessValidator`
- Produces: 기존 공개 Service 메서드 Signature와 응답을 유지하면서 소유권을 선검증하는 Use Case

- [ ] **Step 1: 비소유 자원에서 기존 Repository·파일·AI 작업이 호출되지 않는 실패 테스트 작성**

```java
given(currentUserResolver.requireUserId()).willReturn(41L);
willThrow(new BusinessException(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND))
    .given(accessValidator).requireDrawingSessionAccess(41L, drawingSessionId);

assertThatThrownBy(() -> service.getLatest(drawingSessionId))
    .isInstanceOf(BusinessException.class);
then(drawingAssetRepository).shouldHaveNoInteractions();
```

- [ ] **Step 2: 새 테스트가 검증 의존성 부재로 실패하는지 확인**

Run: `gradlew.bat test --tests "*DrawingSessionServiceTest" --tests "*DrawingSessionQueryServiceTest" --tests "*DrawingDraftServiceTest" --tests "*DrawingSnapshotServiceTest" --tests "*DrawingAnalysisServiceTest" --tests "*DrawingAnalysisQueryServiceTest"`

Expected: 생성자 또는 검증 호출 기대 불일치로 실패

- [ ] **Step 3: 각 Service 시작 지점에 인증·권한 검증 적용**

```java
Long guardianUserId = currentUserResolver.requireUserId();
accessValidator.requireChildAccess(guardianUserId, childId);
```

그림 활동 ID 기반 Use Case에는 다음을 적용한다.

```java
Long guardianUserId = currentUserResolver.requireUserId();
accessValidator.requireDrawingSessionAccess(guardianUserId, drawingSessionId);
```

- [ ] **Step 4: 대상 Service 회귀 테스트 통과 확인**

Run: `gradlew.bat test --tests "*DrawingSessionServiceTest" --tests "*DrawingSessionQueryServiceTest" --tests "*DrawingDraftServiceTest" --tests "*DrawingSnapshotServiceTest" --tests "*DrawingAnalysisServiceTest" --tests "*DrawingAnalysisQueryServiceTest"`

Expected: 기존 성공·오류 테스트와 신규 소유권 테스트 모두 통과

### Task 3: 문서와 전체 검증

**Files:**
- Modify: `backend/README.md`가 존재하고 현재 인증 제한사항을 설명하는 경우에만 권한 검증 내용을 최소 보완

- [ ] **Step 1: 코드 형식 적용**

Run: `gradlew.bat spotlessApply`

- [ ] **Step 2: 전체 테스트**

Run: `gradlew.bat clean test`

Expected: 실패 0건

- [ ] **Step 3: 형식 검증**

Run: `gradlew.bat spotlessCheck`

Expected: 성공

- [ ] **Step 4: Javadoc 검증**

Run: `gradlew.bat javadoc`

Expected: 성공하고 `backend/build/docs/javadoc/index.html` 생성

- [ ] **Step 5: 변경 범위 확인**

Run: `git diff --check` 및 `git status --short`

Expected: 관련 코드·테스트·문서만 변경되고 Commit·Push는 수행되지 않음
