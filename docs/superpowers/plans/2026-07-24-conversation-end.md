# Conversation End API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 진행 중인 대화를 멱등하게 종료하고 연결 그림 활동을 감정 회고 단계로 전환하며 Flutter 앱을 실제 Endpoint에 연결한다.

**Architecture:** Backend는 대화와 그림 세션을 같은 Transaction에서 잠그고 `COMPLETED/REFLECTION` 전이를 저장한다. Redis 기반 공통 대화 명령 멱등 처리로 최초 HTTP 응답을 재생하며, Flutter는 기존 Controller 계약을 유지하면서 Remote Repository만 실제 API에 연결한다.

**Tech Stack:** Java 21, Spring Boot 3.5.16, Spring Data JPA, Redis, Flyway, MySQL 8.x, JUnit 5, MockMvc, Flutter/Dart, Dio

## Global Constraints

- 기준 Branch는 최신 `origin/develop`이며 작업 Branch는 `codex/feature/S15P11B209-390-conversation-end`다.
- 기존 적용 Migration은 수정하지 않고 `V11` Migration을 추가한다.
- 공개 응답은 `ApiResponse<T>`, 오류는 `GlobalExceptionHandler`와 `ErrorCode`를 사용한다.
- Access Token, 아동 개인정보, 요청 Body 전체를 로그에 남기지 않는다.
- 종료 API는 감정 값 저장, 활동 완료 접수, AI 호출, 리포트 이벤트를 수행하지 않는다.
- 주요 Production Type과 공개 메서드 Javadoc은 실제 동작에 맞는 한국어로 작성한다.
- 구현은 테스트 우선으로 진행하고 기존 테스트를 삭제하거나 비활성화하지 않는다.

---

### Task 1: 종료 사유 Schema와 도메인 상태 전이

**Files:**
- Create: `backend/src/main/resources/db/migration/V11__support_conversation_completion.sql`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/domain/ConversationCompletionReason.java`
- Modify: `backend/src/main/java/com/ssafy/b209/conversation/domain/ConversationSession.java`
- Modify: `backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java`
- Create: `backend/src/test/java/com/ssafy/b209/conversation/domain/ConversationSessionCompletionTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingSessionReflectionTest.java`
- Modify: `backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java`

**Interfaces:**
- Produces: `ConversationSession.complete(ConversationCompletionReason, LocalDateTime)`
- Produces: `DrawingSession.enterReflection()`
- Produces: `ConversationCompletionReason`

- [ ] **Step 1: 실패하는 대화 완료 도메인 테스트를 작성한다**

```java
@Test
void completesConversingSessionOnlyOnce() {
  ConversationSession session =
      ConversationSession.start(10L, "LOW", 5, LocalDateTime.parse("2026-07-24T07:00:00"));
  LocalDateTime completedAt = LocalDateTime.parse("2026-07-24T07:30:00");

  session.complete(ConversationCompletionReason.GUARDIAN_REQUEST, completedAt);
  session.complete(
      ConversationCompletionReason.CHILD_REQUEST,
      LocalDateTime.parse("2026-07-24T07:31:00"));

  assertThat(session.isCompleted()).isTrue();
  assertThat(session.getCompletionReason())
      .isEqualTo(ConversationCompletionReason.GUARDIAN_REQUEST);
  assertThat(session.getCompletedAt()).isEqualTo(completedAt);
}
```

- [ ] **Step 2: 도메인 테스트가 실패하는지 확인한다**

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationSessionCompletionTest"
```

Expected: `complete`와 완료 필드가 없어 컴파일 실패.

- [ ] **Step 3: 종료 Enum과 대화 완료 전이를 최소 구현한다**

```java
public enum ConversationCompletionReason {
  QUESTION_LIMIT_REACHED,
  CHILD_REQUEST,
  GUARDIAN_REQUEST,
  NO_MORE_QUESTION
}
```

`ConversationSession`에는 `completion_reason`, 기존 `completed_at` 매핑과 다음 행위를 추가한다.

```java
public void complete(ConversationCompletionReason reason, LocalDateTime completedAt) {
  Objects.requireNonNull(reason, "reason must not be null");
  Objects.requireNonNull(completedAt, "completedAt must not be null");
  if (isCompleted()) {
    return;
  }
  if (!isConversing()) {
    throw new IllegalStateException("진행 중인 대화만 완료할 수 있습니다.");
  }
  conversationStatus = "COMPLETED";
  completionReason = reason;
  this.completedAt = completedAt;
}
```

- [ ] **Step 4: 그림 단계 전이 테스트와 구현을 추가한다**

```java
@Test
void entersReflectionFromConversingAndKeepsReflectionIdempotently() {
  DrawingSession session = ReflectionTestUtils.sessionAt(DrawingStage.CONVERSING);

  session.enterReflection();
  session.enterReflection();

  assertThat(session.getCurrentStage()).isEqualTo(DrawingStage.REFLECTION);
}
```

```java
public void enterReflection() {
  if (deletedAt != null || sessionStatus != DrawingSessionStatus.IN_PROGRESS) {
    throw new IllegalStateException("진행 중인 그림 활동만 감정 회고로 이동할 수 있습니다.");
  }
  if (currentStage == DrawingStage.REFLECTION) {
    return;
  }
  if (currentStage != DrawingStage.CONVERSING) {
    throw new IllegalStateException("대화 단계에서만 감정 회고로 이동할 수 있습니다.");
  }
  currentStage = DrawingStage.REFLECTION;
}
```

- [ ] **Step 5: V11 Migration과 MySQL 검증을 추가한다**

```sql
ALTER TABLE conversation_sessions
    ADD COLUMN completion_reason VARCHAR(30) NULL COMMENT '대화 종료 사유' AFTER question_count,
    ADD CONSTRAINT ck_conversation_sessions_completion_reason
        CHECK (
            completion_reason IS NULL
            OR completion_reason IN (
                'QUESTION_LIMIT_REACHED',
                'CHILD_REQUEST',
                'GUARDIAN_REQUEST',
                'NO_MORE_QUESTION'
            )
        );
```

`DatabaseMigrationIntegrationTest`의 현재 Version 기대값을 `11`로 올리고 컬럼·CHECK 존재 검증을 추가한다.

- [ ] **Step 6: Task 1 테스트를 통과시킨다**

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationSessionCompletionTest" --tests "*DrawingSessionReflectionTest"
```

Expected: PASS.

- [ ] **Step 7: Task 1을 커밋한다**

```powershell
git add backend/src/main/resources/db/migration/V11__support_conversation_completion.sql backend/src/main/java/com/ssafy/b209/conversation/domain backend/src/main/java/com/ssafy/b209/drawing/domain/DrawingSession.java backend/src/test/java/com/ssafy/b209/conversation/domain backend/src/test/java/com/ssafy/b209/drawing/domain/DrawingSessionReflectionTest.java backend/src/test/java/com/ssafy/b209/database/DatabaseMigrationIntegrationTest.java
git commit -m "[S15P11B209-390] feat(conversation): 대화 종료 상태 전이 추가"
```

### Task 2: 대화 종료 Service와 권한·마지막 질문 검증

**Files:**
- Create: `backend/src/main/java/com/ssafy/b209/conversation/dto/EndConversationRequest.java`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/dto/EndConversationResponse.java`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/exception/ConversationEndErrorCode.java`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/repository/ConversationEndAuthorizationRepository.java`
- Modify: `backend/src/main/java/com/ssafy/b209/conversation/repository/ConversationMessageRepository.java`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/service/ConversationEndService.java`
- Create: `backend/src/test/java/com/ssafy/b209/conversation/service/ConversationEndServiceTest.java`

**Interfaces:**
- Consumes: `ConversationSession.complete`, `DrawingSession.enterReflection`
- Produces: `ConversationEndService.end(EndConversationRequest)`
- Produces: `EndConversationResponse`

- [ ] **Step 1: Service 실패 테스트를 작성한다**

핵심 정상 사례는 다음 구조로 작성한다.

```java
@Test
void completesConversationAndMovesDrawingSessionToReflection() {
  given(currentUserResolver.requireUserId()).willReturn(7L);
  given(authorizationRepository.hasConversationAccess(7L, 20L)).willReturn(true);
  given(conversationRepository.findByIdForUpdate(20L)).willReturn(Optional.of(conversation));
  given(drawingRepository.findNotDeletedByIdForUpdate(100L)).willReturn(Optional.of(drawing));
  given(messageRepository.findLatestQuestionId(20L)).willReturn(Optional.of(803L));

  EndConversationResponse response =
      service.end(
          20L,
          new EndConversationRequest(
              ConversationCompletionReason.GUARDIAN_REQUEST, 803L));

  assertThat(response.completed()).isTrue();
  assertThat(conversation.isCompleted()).isTrue();
  assertThat(drawing.getCurrentStage()).isEqualTo(DrawingStage.REFLECTION);
}
```

추가 사례는 접근 불가 404, 대화 없음 404, 그림 상태 충돌, 마지막 질문 불일치, 질문 ID 미지정 허용, 이미 완료된 세션의
사유·시각 보존을 각각 독립 테스트로 작성한다.

- [ ] **Step 2: Service 테스트가 실패하는지 확인한다**

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationEndServiceTest"
```

Expected: 종료 DTO와 Service가 없어 컴파일 실패.

- [ ] **Step 3: 요청·응답 DTO와 오류 코드를 구현한다**

```java
public record EndConversationRequest(
    @NotNull ConversationCompletionReason reason,
    @Positive Long lastQuestionMessageId) {}
```

```java
public record EndConversationResponse(
    Long conversationId,
    String conversationStatus,
    boolean completed,
    ConversationCompletionReason completionReason,
    LocalDateTime completedAt,
    DrawingStage nextStage) {}
```

오류 코드는 `CONVERSATION_NOT_FOUND`, `CONVERSATION_NOT_CONVERSING`,
`CONVERSATION_LAST_QUESTION_MISMATCH`를 각각 404/409/409로 정의한다.

- [ ] **Step 4: 권한과 최신 질문 조회 Repository를 구현한다**

`ConversationEndAuthorizationRepository.hasConversationAccess`는
`conversation_sessions → drawing_sessions → guardian_child_relations → children`을 조인하고 활성·미삭제 아동인지
`exists`만 반환한다.

`ConversationMessageRepository`에는 Spring Data 파생 조회를 추가한다.

```java
Optional<ConversationMessage>
    findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
        Long conversationSessionId, String messageType);
```

Service는 반환된 메시지의 `getId()`와 요청 ID를 비교하며 `messageType`에는 상수 `QUESTION`만 전달한다.

- [ ] **Step 5: Transaction Service를 구현한다**

```java
@Transactional
public EndConversationResponse end(Long conversationId, EndConversationRequest request) {
  Long guardianId = currentUserResolver.requireUserId();
  if (!authorizationRepository.hasConversationAccess(guardianId, conversationId)) {
    throw new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND);
  }
  ConversationSession conversation =
      conversationRepository
          .findByIdForUpdate(conversationId)
          .orElseThrow(
              () -> new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));
  if (conversation.isCompleted()) {
    return response(conversation);
  }
  DrawingSession drawing =
      drawingRepository
          .findNotDeletedByIdForUpdate(conversation.getDrawingSessionId())
          .orElseThrow(
              () -> new BusinessException(ConversationEndErrorCode.CONVERSATION_NOT_FOUND));
  validateLatestQuestion(conversationId, request.lastQuestionMessageId());
  conversation.complete(request.reason(), LocalDateTime.now(clock));
  drawing.enterReflection();
  return response(conversation);
}
```

- [ ] **Step 6: Service 테스트를 통과시킨다**

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationEndServiceTest"
```

Expected: PASS.

- [ ] **Step 7: Task 2를 커밋한다**

```powershell
git add backend/src/main/java/com/ssafy/b209/conversation backend/src/test/java/com/ssafy/b209/conversation/service/ConversationEndServiceTest.java
git commit -m "[S15P11B209-390] feat(conversation): 대화 종료 유스케이스 구현"
```

### Task 3: 공통 멱등 처리와 종료 Controller

**Files:**
- Move: `backend/src/main/java/com/ssafy/b209/conversation/service/ConversationQuestionIdempotencyStore.java` → `backend/src/main/java/com/ssafy/b209/conversation/service/ConversationCommandIdempotencyStore.java`
- Move: `backend/src/test/java/com/ssafy/b209/conversation/service/ConversationQuestionIdempotencyStoreTest.java` → `backend/src/test/java/com/ssafy/b209/conversation/service/ConversationCommandIdempotencyStoreTest.java`
- Modify: `backend/src/main/java/com/ssafy/b209/conversation/controller/ConversationNextQuestionController.java`
- Modify: `backend/src/test/java/com/ssafy/b209/conversation/controller/ConversationNextQuestionControllerTest.java`
- Create: `backend/src/main/java/com/ssafy/b209/conversation/controller/ConversationEndController.java`
- Create: `backend/src/test/java/com/ssafy/b209/conversation/controller/ConversationEndControllerTest.java`

**Interfaces:**
- Consumes: `ConversationEndService.end`
- Produces: `POST /api/v1/conversations/{conversationId}/end`
- Produces: `ConversationCommandIdempotencyStore.execute(...)`

- [ ] **Step 1: 공통 명령 멱등 저장소로 이름을 일반화하고 회귀 테스트를 실행한다**

클래스·테스트 파일과 생성자 이름을 `ConversationCommandIdempotencyStore`로 변경한다. Redis Key, fingerprint, TTL,
오류 코드는 변경하지 않는다. 다음 질문 Controller의 주입 타입만 새 이름으로 바꾼다.

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationCommandIdempotencyStoreTest" --tests "*ConversationNextQuestionControllerTest"
```

Expected: 기존 다음 질문 멱등 테스트 PASS.

- [ ] **Step 2: 종료 Controller 실패 테스트를 작성한다**

```java
mockMvc
    .perform(
        post("/api/v1/conversations/20/end")
            .header("Idempotency-Key", "conversation-end-key")
            .contentType(MediaType.APPLICATION_JSON)
            .content(
                """
                {
                  "reason": "GUARDIAN_REQUEST",
                  "lastQuestionMessageId": 803
                }
                """))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.data.conversationId").value(20))
    .andExpect(jsonPath("$.data.completed").value(true))
    .andExpect(jsonPath("$.data.nextStage").value("REFLECTION"));
```

Header 없음·7자·101자·제어 문자, 잘못된 reason, 음수 ID, Service 오류 전달도 추가한다.

- [ ] **Step 3: 종료 Controller를 구현한다**

```java
@PostMapping("/{conversationId}/end")
public ResponseEntity<?> end(
    @PathVariable @Positive Long conversationId,
    @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
    @Valid @RequestBody EndConversationRequest request) {
  requireIdempotencyKey(idempotencyKey);
  Long guardianId = currentUserResolver.requireUserId();
  String uri = "/api/v1/conversations/" + conversationId + "/end";
  return idempotencyStore.execute(
      guardianId,
      uri,
      idempotencyKey,
      request,
      () -> ResponseEntity.ok(ApiResponse.ok(conversationEndService.end(conversationId, request))));
}
```

Controller는 Repository를 직접 호출하지 않고 요청 검증, 현재 사용자 식별, 멱등 실행, Service 호출과 응답 조립만 담당한다.

- [ ] **Step 4: Controller와 멱등 테스트를 통과시킨다**

Run:

```powershell
backend\gradlew.bat -p backend test --tests "*ConversationEndControllerTest" --tests "*ConversationCommandIdempotencyStoreTest" --tests "*ConversationNextQuestionControllerTest"
```

Expected: PASS.

- [ ] **Step 5: Task 3을 커밋한다**

```powershell
git add backend/src/main/java/com/ssafy/b209/conversation backend/src/test/java/com/ssafy/b209/conversation
git commit -m "[S15P11B209-390] feat(conversation): 종료 API와 멱등 처리 연결"
```

### Task 4: Flutter Remote Repository와 Composition 연결

**Files:**
- Modify: `frontend/mobile/lib/features/conversation/domain/models/conversation_end.dart`
- Modify: `frontend/mobile/lib/features/conversation/application/conversation_end_controller.dart`
- Create: `frontend/mobile/lib/features/conversation/data/repositories/remote_conversation_end_repository.dart`
- Modify: `frontend/mobile/lib/features/conversation/conversation.dart`
- Modify: `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`
- Modify: `frontend/mobile/lib/app/app.dart`
- Modify: `frontend/mobile/lib/app/router/app_router.dart`
- Modify: `frontend/mobile/lib/main.dart`
- Create: `frontend/mobile/test/features/conversation/remote_conversation_end_repository_test.dart`
- Modify: `frontend/mobile/test/features/conversation/conversation_end_controller_test.dart`
- Modify: `frontend/mobile/test/app/app_bootstrap_test.dart`

**Interfaces:**
- Consumes: `POST /api/v1/conversations/{conversationId}/end`
- Produces: `RemoteConversationEndRepository`
- Produces: 기본 앱에서 종료 Remote 주입

- [ ] **Step 1: 요청·응답 모델과 Controller 실패 테스트를 작성한다**

```dart
final request = ConversationEndRequest(
  reason: ConversationCompletionReason.guardianRequest,
  lastQuestionMessageId: 803,
);
expect(request.toJson(), {
  'reason': 'GUARDIAN_REQUEST',
  'lastQuestionMessageId': 803,
});
```

Controller `submit`은 `reason`을 필수 인자로 받고 실패 재시도에서 같은 Key를 유지하는 기존 테스트를 확장한다.

- [ ] **Step 2: Remote Repository HTTP 계약 테스트를 작성한다**

`Dio` Mock Adapter로 URI, JSON Body, `Idempotency-Key`를 검증하고 다음 공통 응답을 반환한다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {
    "conversationId": 20,
    "conversationStatus": "COMPLETED",
    "completed": true,
    "completionReason": "GUARDIAN_REQUEST",
    "completedAt": "2026-07-24T07:30:00",
    "nextStage": "REFLECTION"
  }
}
```

Run:

```powershell
flutter test test/features/conversation/remote_conversation_end_repository_test.dart test/features/conversation/conversation_end_controller_test.dart
```

Expected: Remote 구현과 reason 필드가 없어 FAIL.

- [ ] **Step 3: 모델과 Remote Repository를 구현한다**

```dart
enum ConversationCompletionReason {
  questionLimitReached('QUESTION_LIMIT_REACHED'),
  childRequest('CHILD_REQUEST'),
  guardianRequest('GUARDIAN_REQUEST'),
  noMoreQuestion('NO_MORE_QUESTION');

  const ConversationCompletionReason(this.apiValue);
  final String apiValue;
}
```

```dart
final class RemoteConversationEndRepository implements ConversationEndRepository {
  const RemoteConversationEndRepository(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<ConversationEndResult> endConversation({
    required int conversationId,
    required ConversationEndRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'conversations/$conversationId/end',
      data: request.toJson(),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return ConversationEndResult.fromJson(envelopeObject(response.data));
  }
}
```

- [ ] **Step 4: 종료 버튼과 Composition Root를 연결한다**

현재 UI의 확인 버튼은 `ConversationCompletionReason.guardianRequest`를 Controller에 전달한다. `DodamApp`,
`AppRouter`, `DrawingScreen`에 `ConversationEndRepository?`를 전달하고 기본 앱은
`RemoteConversationEndRepository(apiClient)`를 주입한다.

- [ ] **Step 5: Flutter 테스트를 통과시킨다**

Run:

```powershell
flutter test test/features/conversation/remote_conversation_end_repository_test.dart test/features/conversation/conversation_end_controller_test.dart test/app/app_bootstrap_test.dart
```

Expected: PASS.

- [ ] **Step 6: Task 4를 커밋한다**

```powershell
git add frontend/mobile/lib frontend/mobile/test
git commit -m "[S15P11B209-390] feat(conversation): 앱 대화 종료 API 연동"
```

### Task 5: 계약 문서와 전체 검증

**Files:**
- Create: `docs/api/conversation-end-contract.md`
- Modify: `README.md`
- Modify: `backend/README.md`

**Interfaces:**
- Documents: 종료 요청·응답·오류·후속 처리 순서·환경 제한

- [ ] **Step 1: API 계약 문서를 작성한다**

`docs/api/conversation-end-contract.md`에 설계 문서의 URI, Header, Body, 응답, 오류와 다음 순서를 기록한다.

```text
대화 종료 → 감정·제목 저장 → 전체 활동 완료 접수 → 리포트 생성 이벤트
```

실제 Secret, 사용자 PC 절대 경로, 구현하지 않은 스킵 Endpoint는 작성하지 않는다.

- [ ] **Step 2: README의 Endpoint 목록과 제한 사항을 최소 보완한다**

Backend README에는 `POST /api/v1/conversations/{conversationId}/end`와 `Idempotency-Key` 필수 조건만 추가하고,
루트 README는 관련 계약 문서 링크만 추가한다.

- [ ] **Step 3: Backend 형식과 전체 테스트를 검증한다**

Run:

```powershell
backend\gradlew.bat -p backend clean test
backend\gradlew.bat -p backend spotlessCheck
backend\gradlew.bat -p backend javadoc
```

Expected: 세 명령 모두 `BUILD SUCCESSFUL`, Javadoc은 새 변경 경로에 오류 없음.

- [ ] **Step 4: Flutter 형식과 전체 테스트를 검증한다**

Run from `frontend/mobile`:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: format 변경 없음, analyze `No issues found`, 전체 테스트 PASS.

- [ ] **Step 5: 변경 범위와 보안 회귀를 확인한다**

Run:

```powershell
git diff --check origin/develop...HEAD
git diff --name-only origin/develop...HEAD
rg -n "Authorization: Bearer [A-Za-z0-9]|NAVER_CLIENT_SECRET|KAKAO_NATIVE_APP_KEY" .
```

Expected: 공백 오류 없음, S390 관련 파일만 표시, 실제 Secret 검색 결과 없음.

- [ ] **Step 6: 최종 문서와 검증 보완을 커밋한다**

```powershell
git add docs/api/conversation-end-contract.md README.md backend/README.md
git commit -m "[S15P11B209-390] docs(conversation): 종료 API 계약 문서화"
```

- [ ] **Step 7: GitLab MR과 Jira 완료 보고를 준비한다**

권장 MR 제목:

```text
[S15P11B209-390] feat: 대화 종료 API 및 앱 연동
```

MR 본문에는 상태 전이, Schema 변경, Idempotency 동작, FE 연결, 검증 결과와 제외 범위를 기록한다. MR 병합 후에만
Jira를 완료로 전환한다.
