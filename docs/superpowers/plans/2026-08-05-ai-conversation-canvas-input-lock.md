# AI Conversation Canvas Input Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AI 질문 말풍선이 실제로 표시되는 동안 대화 UI를 제외한 캔버스 작업 입력을 모두 차단한다.

**Architecture:** `DrawingScreen`이 기존 말풍선 가시성 계약을 `_isConversationFocusMode`라는 단일 파생 상태로 제공한다. 캔버스는 `inputEnabled`에서, 툴바와 보조 조작은 `AbsorbPointer`에서 같은 상태를 사용하며 AI 말풍선은 잠금 계층 밖에 둔다.

**Tech Stack:** Flutter, Dart, flutter_test, 기존 `AiQuestionDisplayController`와 `DrawingDocumentController`

## Global Constraints

- 기존 캔버스 시각 디자인과 AI 대화 흐름을 변경하지 않는다.
- AI 말풍선의 선택지·음성·건너뛰기·대화 종료 입력은 유지한다.
- 시스템 뒤로가기는 유지한다.
- 백그라운드 저장·동기화는 중단하지 않는다.
- 새 패키지 의존성을 추가하지 않는다.

---

### Task 1: 대화 집중 모드 회귀 테스트

**Files:**
- Modify: `frontend/mobile/test/features/conversation/ai_response_state_screen_test.dart`

**Interfaces:**
- Consumes: `DrawingScreen`, `DrawingObjectDetectionController`, `DrawingDocumentController.actions`
- Produces: AI 말풍선 표시 전에는 획이 생성되고 표시 중에는 동일 제스처가 문서에 기록되지 않는 위젯 테스트

- [ ] **Step 1: 테스트용 문서 컨트롤러 주입 경로 추가**

`_pumpConversation`에 `DrawingDocumentController? documentController` 인자를 추가하고 `DrawingScreen(documentController: documentController)`로 전달한다.

- [ ] **Step 2: 실패하는 입력 잠금 테스트 작성**

```dart
testWidgets('AI 질문이 보이는 동안 캔버스 입력을 막고 대화 입력만 유지한다', (tester) async {
  final document = DrawingDocumentController();
  final detection = _detectionController();
  await _pumpConversation(
    tester,
    conversationId: null,
    activityContext: const DrawingActivityContextDto.general(),
    objectDetectionController: detection,
    documentController: document,
  );

  await _drawOnCanvas(tester);
  expect(document.actions, hasLength(1));

  await _detectAnalysis(tester, detection, 701);
  expect(find.byKey(const ValueKey('ai-question-option-1')), findsOneWidget);

  await _drawOnCanvas(tester);
  expect(document.actions, hasLength(1));

  await _tap(tester, const ValueKey('ai-question-option-1'));
  expect(find.byKey(const ValueKey('ai-question-answer-submitting')), findsOneWidget);
});
```

- [ ] **Step 3: 테스트가 현재 구현에서 실패하는지 확인**

Run: `flutter test test/features/conversation/ai_response_state_screen_test.dart --plain-name "AI 질문이 보이는 동안 캔버스 입력을 막고 대화 입력만 유지한다"`

Expected: FAIL — AI 질문 표시 중 두 번째 획이 `document.actions`에 추가된다.

---

### Task 2: 단일 대화 집중 상태로 작업 UI 잠금

**Files:**
- Modify: `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`
- Test: `frontend/mobile/test/features/conversation/ai_response_state_screen_test.dart`

**Interfaces:**
- Consumes: `AiQuestionDisplayController.isVisible`, `_activePointer`, `_canvasLocked`, `DrawingDraftRestoreController.canDraw`
- Produces: `bool get _isConversationFocusMode`와 `ValueKey('drawing-conversation-input-lock')`

- [ ] **Step 1: 기존 말풍선 표시 계약을 getter로 추출**

```dart
bool get _isConversationFocusMode =>
    _questionDisplayController.isVisible &&
    _activePointer == null &&
    (_canvasLocked || _draftRestoreController.canDraw);
```

말풍선, 완료 CTA, 캔버스 입력이 모두 이 getter를 사용하게 하여 가시성과 잠금이 어긋나지 않게 한다.

- [ ] **Step 2: 캔버스 이벤트 진입을 이중 차단**

`_CanvasPanel.inputEnabled`에 `!_isConversationFocusMode`를 추가하고 `_startStroke` 시작부에도 같은 방어 조건을 둔다. 호버와 포인터 종료 시 집중 모드라면 `DrawingCursorController.hide()`를 호출한다.

- [ ] **Step 3: 툴바와 보조 작업 입력 흡수**

```dart
AbsorbPointer(
  key: const ValueKey('drawing-conversation-input-lock'),
  absorbing: _isConversationFocusMode,
  child: toolbar,
)
```

캔버스 튜토리얼 도움말과 stage chrome에도 동일 상태를 적용하되 `AiQuestionBubbleOverlay`는 흡수 계층 밖에 유지한다. 완료 CTA는 기존처럼 집중 모드 동안 렌더링하지 않는다.

- [ ] **Step 4: 집중 잠금 테스트 통과 확인**

Run: `flutter test test/features/conversation/ai_response_state_screen_test.dart --plain-name "AI 질문이 보이는 동안 캔버스 입력을 막고 대화 입력만 유지한다"`

Expected: PASS

- [ ] **Step 5: 관련 회귀 테스트 실행**

Run: `flutter test test/features/conversation/ai_response_state_screen_test.dart test/features/drawing/drawing_toolbar_accessibility_test.dart test/features/drawing/drawing_complete_cta_test.dart test/features/drawing/drawing_responsive_layout_test.dart`

Expected: 모든 테스트 PASS

- [ ] **Step 6: 정적 분석과 전체 테스트 실행**

Run: `flutter analyze`

Expected: `No issues found!`

Run: `flutter test`

Expected: 모든 테스트 PASS

- [ ] **Step 7: 구현 커밋**

```bash
git add frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart frontend/mobile/test/features/conversation/ai_response_state_screen_test.dart
git commit -m "feat(canvas): [S15P11B209-915] AI 대화 중 입력을 잠근다"
```
