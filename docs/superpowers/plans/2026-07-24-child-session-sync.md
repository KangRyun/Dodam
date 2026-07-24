# Child Session Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보호자 인증이 확정된 뒤에만 아동 목록을 조회하고 계정 전환 시 이전 아동 상태가 남지 않게 한다.

**Architecture:** `DodamApp`이 인증 생명주기와 `GuardianChildController`의 목록 동기화를 연결한다. Controller는 API 오류를 기존 화면 상태로 유지하며, 별도의 전체 초기화 연산으로 로그아웃 계정 경계를 보장한다.

**Tech Stack:** Flutter, Dart, Provider Token OAuth, Flutter Test

## Global Constraints

- Jira 이슈 `S15P11B209-399` 범위만 구현한다.
- Backend API와 DB Schema는 변경하지 않는다.
- `GET /api/v1/children`의 기존 공통 응답 계약과 `ChildRepository`를 재사용한다.
- 등록된 아동이 없으면 기존 아동 등록 안내 화면을 표시한다.
- 실제 OAuth Secret과 Token을 코드, 문서, 로그에 기록하지 않는다.
- 관련 테스트를 먼저 실패시키고 최소 구현으로 통과시킨다.

---

### Task 1: 계정 경계에서 아동 상태 전체 초기화

**Files:**
- Modify: `frontend/mobile/lib/app/state/guardian_child_controller.dart`
- Test: `frontend/mobile/test/features/guardian/guardian_child_entry_test.dart`

**Interfaces:**
- Consumes: 기존 `GuardianChildController` 상태 필드
- Produces: `void clear()` — 목록, 선택, 조회 상태, 등록 상태와 등록 오류를 초기화

- [ ] **Step 1: 실패하는 Controller 초기화 테스트 작성**

아동 목록을 불러오고 하나를 선택한 뒤 `clear()`를 호출하여 다음을 검증한다.

```dart
expect(controller.status, ChildListStatus.idle);
expect(controller.children, isEmpty);
expect(controller.selectedChild, isNull);
expect(controller.registrationStatus, ChildRegistrationStatus.idle);
expect(controller.registrationError, isNull);
```

- [ ] **Step 2: 대상 테스트가 실패하는지 확인**

Run:

```bash
cd frontend/mobile
flutter test test/features/guardian/guardian_child_entry_test.dart
```

Expected: `GuardianChildController.clear`가 없어 컴파일 실패

- [ ] **Step 3: 최소 초기화 구현**

`GuardianChildController`에 상태를 다음 초기값으로 되돌리고 한 번만
`notifyListeners()`를 호출하는 `clear()`를 추가한다.

```dart
void clear() {
  _status = ChildListStatus.idle;
  _children = const [];
  _selectedChild = null;
  _registrationStatus = ChildRegistrationStatus.idle;
  _registrationError = null;
  notifyListeners();
}
```

- [ ] **Step 4: Controller 테스트 통과 확인**

Run:

```bash
cd frontend/mobile
flutter test test/features/guardian/guardian_child_entry_test.dart
```

Expected: PASS

### Task 2: 인증 완료 시 아동 목록 동기화

**Files:**
- Modify: `frontend/mobile/lib/app/app.dart`
- Create: `frontend/mobile/test/app/child_session_sync_test.dart`

**Interfaces:**
- Consumes: `AuthState`, `AuthSession`, `UserRole.guardian`, `GuardianChildController.loadChildren()`
- Produces: 로그인·onboarding·세션 복원 완료 후 보호자 아동 목록이 준비된 앱 흐름

- [ ] **Step 1: 인증 전 조회 방지 테스트 작성**

`initialRoute: AppRoutes.authBootstrap`, 세션이 없는 Fake `AuthRepository`,
호출 횟수를 기록하는 Fake `ChildRepository`로 앱을 실행한다.

```dart
expect(childRepository.getChildrenCalls, 0);
expect(find.byKey(const ValueKey('social-login-kakao')), findsOneWidget);
```

- [ ] **Step 2: 저장 세션 복원 후 조회 및 빈 화면 테스트 작성**

완료된 보호자 세션을 반환하고 빈 목록 Repository를 주입한다.

```dart
expect(childRepository.getChildrenCalls, 1);
expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
```

- [ ] **Step 3: 기존 보호자 로그인 후 조회 테스트 작성**

세션 복원은 `null`, Provider 로그인은 완료된 보호자 세션을 반환하게 하고 로그인
버튼을 누른다.

```dart
expect(childRepository.getChildrenCalls, 1);
expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
```

- [ ] **Step 4: 대상 테스트가 현재 구현에서 실패하는지 확인**

Run:

```bash
cd frontend/mobile
flutter test test/app/child_session_sync_test.dart
```

Expected: 인증 전 호출 횟수가 1이고 인증 후 상태 동기화가 없어 FAIL

- [ ] **Step 5: 인증 생명주기 동기화 구현**

`DodamApp`에서 기본 보호자 홈 경로만 초기 목록을 조회하고,
`AuthState` 또는 `AuthSession`이 onboarding을 완료한 보호자일 때
`await _childController.loadChildren()`을 호출한다.

```dart
Future<void> _loadGuardianChildren(AuthSession? session) async {
  if (session == null ||
      session.requiresOnboarding ||
      session.user.role != UserRole.guardian) {
    return;
  }
  await _childController.loadChildren();
}
```

`_signIn`, `_completeOnboarding`, `_restoreSession`은 원래 반환값을 유지하면서 위
동기화를 수행한다. `_signOut`은 `clearSelection()` 대신 `clear()`를 호출한다.

- [ ] **Step 6: 인증 동기화 테스트 통과 확인**

Run:

```bash
cd frontend/mobile
flutter test test/app/child_session_sync_test.dart
flutter test test/features/guardian/guardian_child_entry_test.dart
```

Expected: PASS

### Task 3: 회귀 및 품질 검증

**Files:**
- Verify: `frontend/mobile/lib/app/app.dart`
- Verify: `frontend/mobile/lib/app/state/guardian_child_controller.dart`
- Verify: `frontend/mobile/test/app/child_session_sync_test.dart`
- Verify: `frontend/mobile/test/features/guardian/guardian_child_entry_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2의 최종 구현
- Produces: 정적 분석, 전체 테스트, Android Debug 빌드 검증 결과

- [ ] **Step 1: 변경 파일 포맷**

Run:

```bash
cd frontend/mobile
dart format lib/app/app.dart lib/app/state/guardian_child_controller.dart test/app/child_session_sync_test.dart test/features/guardian/guardian_child_entry_test.dart
```

Expected: 포맷 성공

- [ ] **Step 2: 정적 분석**

Run:

```bash
cd frontend/mobile
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: 전체 Flutter 테스트**

Run:

```bash
cd frontend/mobile
flutter test
```

Expected: 전체 PASS

- [ ] **Step 4: Android Debug 빌드**

Run:

```bash
cd frontend/mobile
flutter build apk --debug
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` 생성

- [ ] **Step 5: Secret 및 변경 범위 확인**

Run:

```bash
git status --short
git diff --check
git diff -- frontend/mobile docs/superpowers
```

Expected: 이슈 범위 파일만 변경되고 OAuth Secret 또는 Token 없음
