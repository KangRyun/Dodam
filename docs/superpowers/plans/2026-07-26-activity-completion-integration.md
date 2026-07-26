# Activity Completion Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter에서 Conversation End, 회고 저장, Activity Complete 접수와 완료 상태 확인을 실제 Backend API로 연결한다.

**Architecture:** 기존 `ConversationEndController`는 대화 종료 요청의 멱등 재시도를 유지하고 Remote Repository만 추가한다. `DrawingRepository`에는 활동 완료 접수 메서드를 추가하며, 새 `ActivityCompletionController`가 완료 접수 키와 세션 상태 polling을 관리한다. 화면은 controller 상태를 렌더링하고 HTTP 계약을 직접 다루지 않는다.

**Tech Stack:** Flutter, Dart, Dio, ChangeNotifier, flutter_test

## Global Constraints

- 브랜치는 `feature/S15P11B209-644-activity-completion-integration`을 사용한다.
- Commit Message는 `[S15P11B209-644] type(scope): 설명` 형식을 사용한다.
- Conversation End와 Activity Complete는 서로 다른 `Idempotency-Key`를 사용한다.
- 동일 요청 재시도는 최초 생성한 `Idempotency-Key`를 유지한다.
- MVP Activity Complete는 `requestReport=true`만 전송한다.
- 기존 Stroke Batch, Draft, Drawing Complete multipart 계약은 변경하지 않는다.
- 실제 Token, 아동 개인정보, Request Body 전체를 로그에 남기지 않는다.

---

### Task 1: Conversation End 실제 API 계약

**Files:**
- Modify: `frontend/mobile/lib/features/conversation/domain/models/conversation_end.dart`
- Create: `frontend/mobile/lib/features/conversation/data/repositories/remote_conversation_end_repository.dart`
- Modify: `frontend/mobile/lib/features/conversation/application/conversation_end_controller.dart`
- Modify: `frontend/mobile/lib/features/conversation/conversation.dart`
- Modify: `frontend/mobile/lib/main.dart`
- Modify: `frontend/mobile/lib/app/app.dart`
- Modify: `frontend/mobile/lib/app/router/app_router.dart`
- Test: `frontend/mobile/test/features/conversation/remote_conversation_end_repository_test.dart`
- Test: `frontend/mobile/test/features/conversation/conversation_end_controller_test.dart`
- Test: `frontend/mobile/test/app/app_bootstrap_test.dart`

**Interfaces:**
- Produces: `ConversationCompletionReason`, `RemoteConversationEndRepository`
- Consumes: `ApiClient`, `envelopeObject`, 기존 `ConversationEndRepository`

- [ ] **Step 1: Remote 계약의 실패 테스트 작성**

```dart
test('대화 종료는 reason과 멱등 키를 실제 API에 전달한다', () async {
  final result = await repository.endConversation(
    conversationId: 31,
    request: const ConversationEndRequest(
      reason: ConversationCompletionReason.childRequest,
      lastQuestionMessageId: 77,
    ),
    idempotencyKey: 'end-key-1234',
  );

  expect(recorder.request.path, 'conversations/31/end');
  expect(recorder.request.headers['Idempotency-Key'], 'end-key-1234');
  expect(recorder.request.data['reason'], 'CHILD_REQUEST');
  expect(result.completed, isTrue);
});
```

- [ ] **Step 2: 테스트가 필수 reason/Remote 구현 부재로 실패하는지 확인**

Run: `flutter test test/features/conversation/remote_conversation_end_repository_test.dart test/features/conversation/conversation_end_controller_test.dart`

Expected: FAIL because `ConversationCompletionReason` and `RemoteConversationEndRepository` do not exist.

- [ ] **Step 3: 최소 계약과 Remote Repository 구현**

```dart
enum ConversationCompletionReason {
  questionLimitReached('QUESTION_LIMIT_REACHED'),
  childRequest('CHILD_REQUEST'),
  guardianRequest('GUARDIAN_REQUEST'),
  noMoreQuestion('NO_MORE_QUESTION');

  const ConversationCompletionReason(this.wireName);
  final String wireName;
}
```

`RemoteConversationEndRepository`는 `POST conversations/{id}/end`, `Idempotency-Key`, 공통 `data` 응답을 사용한다. Controller의 현재 종료 버튼 요청은 `childRequest`를 전달한다.

- [ ] **Step 4: 실제 앱 Repository 주입 테스트와 구현**

`createDefaultApp()`이 `RemoteConversationEndRepository`를 만들고 `DodamApp` → `AppRouter` → `DrawingScreen`으로 전달하는 테스트를 추가한다. 명시적 테스트 주입은 Mock을 유지한다.

- [ ] **Step 5: 관련 테스트 통과 확인**

Run: `flutter test test/features/conversation test/app/app_bootstrap_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/mobile/lib frontend/mobile/test/features/conversation frontend/mobile/test/app/app_bootstrap_test.dart
git commit -m "[S15P11B209-644] feat(conversation): 대화 종료 실제 API 연동"
```

### Task 2: Activity Complete 접수와 멱등 재시도

**Files:**
- Modify: `frontend/mobile/lib/features/drawing/data/dto/drawing_dtos.dart`
- Modify: `frontend/mobile/lib/features/drawing/domain/repositories/drawing_repository.dart`
- Modify: `frontend/mobile/lib/features/drawing/data/repositories/remote_drawing_repository.dart`
- Modify: `frontend/mobile/lib/features/drawing/data/repositories/mock_drawing_repository.dart`
- Create: `frontend/mobile/lib/features/drawing/application/activity_completion_controller.dart`
- Test: `frontend/mobile/test/features/drawing/remote_drawing_repository_test.dart`
- Test: `frontend/mobile/test/features/drawing/activity_completion_controller_test.dart`
- Modify: DrawingRepository 테스트 Fake 구현 파일

**Interfaces:**
- Produces: `CompleteActivityRequestDto`, `DrawingCompletionResponseDto`, `ActivityCompletionController`
- Consumes: `DrawingRepository.completeActivity`, `DrawingRepository.getSession`

- [ ] **Step 1: Activity Complete 요청·응답 실패 테스트 작성**

```dart
test('활동 완료는 리포트를 요청하고 멱등 키를 전달한다', () async {
  final result = await repository.completeActivity(
    91,
    request: const CompleteActivityRequestDto(
      conversationSkipped: false,
      requestReport: true,
    ),
    idempotencyKey: 'activity-key-1234',
  );

  expect(recorder.request.path, 'drawing-sessions/91/complete');
  expect(recorder.request.data['requestReport'], isTrue);
  expect(result.currentStage, 'REPORTING');
});
```

- [ ] **Step 2: 테스트가 DTO와 메서드 부재로 실패하는지 확인**

Run: `flutter test test/features/drawing/remote_drawing_repository_test.dart`

Expected: FAIL because Activity Complete types and method do not exist.

- [ ] **Step 3: DTO와 Repository 최소 구현**

```dart
final class CompleteActivityRequestDto {
  const CompleteActivityRequestDto({
    required this.conversationSkipped,
    this.requestReport = true,
  });
  final bool conversationSkipped;
  final bool requestReport;
}
```

Remote 구현은 HTTP 202 응답의 공통 `data`를 해제해 `sessionStatus`, `currentStage`, `analysisStatus`, `reportStatus`를 파싱한다.

- [ ] **Step 4: 멱등 재시도 Controller 실패 테스트 작성**

실패 후 `submit()` 재호출 시 같은 키와 같은 요청이 전달되고, 접수 성공 후에만 pending key가 해제되는 테스트를 추가한다.

- [ ] **Step 5: ActivityCompletionController 최소 구현**

Controller는 `idle/submitting/accepted/failure` 접수 상태를 제공한다. `submit`은 회고 저장을 수행하지 않고 Activity Complete 접수만 담당한다.

- [ ] **Step 6: 관련 테스트 통과 확인**

Run: `flutter test test/features/drawing/remote_drawing_repository_test.dart test/features/drawing/activity_completion_controller_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/mobile/lib/features/drawing frontend/mobile/test/features
git commit -m "[S15P11B209-644] feat(activity): 전체 활동 완료 접수 구현"
```

### Task 3: 화면 순서와 Conversation 생략 정책

**Files:**
- Modify: `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`
- Modify: `frontend/mobile/lib/app/router/app_router.dart`
- Test: `frontend/mobile/test/features/drawing/activity_complete_emotion_test.dart`
- Test: `frontend/mobile/test/features/conversation/ai_question_bubble_overlay_test.dart`

**Interfaces:**
- Consumes: `ConversationEndController.completed`, `ActivityCompletionController.submit`
- Produces: `EmotionSelectRouteArguments.conversationSkipped`

- [ ] **Step 1: 종료 전 화면 이동 차단 테스트 작성**

Conversation이 생성됐지만 End가 성공하지 않은 상태에서 Drawing Complete 후 감정 화면으로 이동하지 않고 종료 안내를 보여주는 Widget 테스트를 추가한다.

- [ ] **Step 2: 테스트가 현재 무조건 이동하기 때문에 실패하는지 확인**

Run: `flutter test test/features/conversation/ai_question_bubble_overlay_test.dart`

Expected: FAIL because the current screen does not enforce Conversation End.

- [ ] **Step 3: Conversation 생성 여부와 종료 상태 전달 구현**

Conversation Controller가 없으면 `conversationSkipped=true`, 존재하고 완료됐으면 `false`를 Route argument에 기록한다. 존재하지만 미완료이면 화면 이동을 중단한다.

- [ ] **Step 4: 회고→완료 호출 순서 실패 테스트 작성**

```dart
expect(calls, ['saveReflection', 'completeActivity']);
expect(completionRequest.conversationSkipped, isFalse);
expect(completionRequest.requestReport, isTrue);
```

Activity Complete 실패 시 완료 화면으로 이동하지 않고 선택값과 pending key를 유지하는 경우도 검증한다.

- [ ] **Step 5: EmotionSelectScreen 최소 구현**

회고 저장 성공 후 `ActivityCompletionController.submit`을 호출하고 accepted인 경우에만 sessionId와 repository를 포함해 완료 화면으로 이동한다.

- [ ] **Step 6: 관련 Widget 테스트 통과 확인**

Run: `flutter test test/features/drawing/activity_complete_emotion_test.dart test/features/conversation/ai_question_bubble_overlay_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/mobile/lib/features/activity frontend/mobile/lib/app/router frontend/mobile/test/features
git commit -m "[S15P11B209-644] feat(activity): 완료 상태 전이 순서 연결"
```

### Task 4: REPORTING polling과 terminal 화면

**Files:**
- Modify: `frontend/mobile/lib/features/drawing/application/activity_completion_controller.dart`
- Modify: `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`
- Modify: `frontend/mobile/lib/app/router/app_router.dart`
- Test: `frontend/mobile/test/features/drawing/activity_completion_controller_test.dart`
- Test: `frontend/mobile/test/features/drawing/activity_complete_emotion_test.dart`

**Interfaces:**
- Produces: `ActivityCompletionStatus.processing/completed/failed/checkFailed`
- Consumes: `DrawingRepository.getSession`

- [ ] **Step 1: polling 상태 실패 테스트 작성**

REPORTING 두 번 후 COMPLETED를 반환하는 Repository로 controller가 최종 완료되는지 검증한다. Backend `FAILED`, 통신 실패, 최대 횟수 도달도 각각 검증한다.

- [ ] **Step 2: 테스트가 polling 미구현으로 실패하는지 확인**

Run: `flutter test test/features/drawing/activity_completion_controller_test.dart`

Expected: FAIL because status polling does not exist.

- [ ] **Step 3: 제한 polling 최소 구현**

Delay 함수를 주입 가능하게 만들고 기본 1초 간격, 최대 30회로 조회한다. `COMPLETED/COMPLETED`와 `FAILED`만 terminal로 처리한다.

- [ ] **Step 4: 화면 상태 실패 테스트 작성**

처리 중에는 완료 문구를 숨기고 Progress UI를 표시하며, 완료 시 기존 완료 화면, 실패나 확인 오류 시 재확인 버튼을 표시하는 테스트를 작성한다.

- [ ] **Step 5: Stateful 완료 화면 구현**

`ActivityCompleteScreen`이 Controller를 생성·해제하고 상태에 따라 처리 중, 완료, 실패 및 수동 재확인 UI를 렌더링한다.

- [ ] **Step 6: 관련 테스트 통과 확인**

Run: `flutter test test/features/drawing/activity_completion_controller_test.dart test/features/drawing/activity_complete_emotion_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/mobile/lib frontend/mobile/test/features/drawing
git commit -m "[S15P11B209-644] feat(activity): 완료 처리 상태 확인 추가"
```

### Task 5: 전체 회귀 검증과 통합

**Files:**
- Verify: `frontend/mobile/lib/**`
- Verify: `frontend/mobile/test/**`

- [ ] **Step 1: Format**

Run: `dart format lib test`

- [ ] **Step 2: 정적 분석**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: 전체 테스트**

Run: `flutter test`

Expected: All tests passed.

- [ ] **Step 4: 변경 범위 확인**

Run: `git diff origin/develop...HEAD --check`

Expected: whitespace error 없음, S15P11B209-644 범위 밖 변경 없음.

- [ ] **Step 5: Push 및 MR**

```bash
git push -u origin feature/S15P11B209-644-activity-completion-integration
```

MR 제목은 `[S15P11B209-644] [FE] 대화 종료·회고·전체 활동 완료 API 통합`, target은 `develop`로 지정한다.

- [ ] **Step 6: MR pipeline 성공 후 merge**

Pipeline과 충돌 여부를 확인하고 merge한다. Jira S15P11B209-644를 완료로 전환한다.
