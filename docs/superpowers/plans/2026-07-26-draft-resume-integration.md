# 진행 중 그림 재개 및 Draft 복원 통합 구현 계획

## 목표

활성 그림 세션을 재사용하고 최신 Draft 이미지를 인증된 Backend API에서
다운로드하여 기존 Drawing 화면에 복원한다.

## 작업 1: 활성 세션 API 계약

**수정 파일**

- `frontend/mobile/lib/features/drawing/data/dto/drawing_dtos.dart`
- `frontend/mobile/lib/features/drawing/domain/repositories/drawing_repository.dart`
- `frontend/mobile/lib/features/drawing/data/repositories/remote_drawing_repository.dart`
- `frontend/mobile/lib/features/drawing/data/repositories/mock_drawing_repository.dart`
- `frontend/mobile/test/features/drawing/remote_drawing_repository_test.dart`

**절차**

1. 활성 세션 공통 응답 역직렬화와 `DRAWING_404_005`의 `null` 변환 테스트를
   작성한다.
2. 테스트 실패를 확인한다.
3. `ActiveDrawingSessionDto`와 `getActiveSession(childId)` 계약을 최소 구현한다.
4. 대상 테스트 통과를 확인한다.

## 작업 2: 시작·재개 결정 로직

**생성·수정 파일**

- `frontend/mobile/lib/features/drawing/application/drawing_session_start_controller.dart`
- `frontend/mobile/lib/features/child_mode/presentation/screens/child_mode_screens.dart`
- `frontend/mobile/test/features/drawing/drawing_session_start_controller_test.dart`
- Repository Test Double 구현 파일

**절차**

1. 활성 세션 재사용, 활성 세션 없음 시 신규 생성, 신규 생성 `409` 후 재조회
   테스트를 작성한다.
2. 테스트 실패를 확인한다.
3. 화면과 무관한 Application Controller를 구현한다.
4. Child Mode 화면의 기존 생성 로직을 Controller 호출로 교체한다.
5. 대상 단위·위젯 테스트 통과를 확인한다.

## 작업 3: Draft 조회 오류 계약과 인증 이미지 다운로드

**수정 파일**

- `frontend/mobile/lib/features/drawing/domain/repositories/drawing_repository.dart`
- `frontend/mobile/lib/features/drawing/data/repositories/remote_drawing_repository.dart`
- `frontend/mobile/lib/features/drawing/data/repositories/mock_drawing_repository.dart`
- `frontend/mobile/test/features/drawing/remote_drawing_repository_test.dart`

**절차**

1. `DRAWING_404_004`의 `null` 변환 테스트를 작성한다.
2. 허용 URL 다운로드, 바이트 반환, 외부 URL·query·잘못된 경로 차단 테스트를
   작성한다.
3. 테스트 실패를 확인한다.
4. URL 검증 및 `ResponseType.bytes` 다운로드를 최소 구현한다.
5. 대상 테스트 통과를 확인한다.

## 작업 4: Draft 이미지 복원

**수정 파일**

- `frontend/mobile/lib/features/drawing/application/drawing_draft_restore_controller.dart`
- `frontend/mobile/test/features/drawing/drawing_draft_restore_test.dart`

**절차**

1. Repository 바이트 다운로드 후 `MemoryImage`를 제공하는 테스트를 작성한다.
2. 다운로드 실패·재시도·빈 preview URL 테스트를 작성한다.
3. 테스트 실패를 확인한다.
4. `continueDrawing`을 비동기 다운로드 흐름으로 변경한다.
5. 기존 Drawing 화면 위젯 테스트와 신규 복원 테스트 통과를 확인한다.

## 작업 5: Repository 계약 적용 및 E2E 경로

**수정 파일**

- DrawingRepository를 구현하는 Test Double 파일
- `frontend/mobile/test/features/drawing/drawing_draft_restore_test.dart`
- 관련 Child Mode 위젯 테스트

**절차**

1. 모든 Mock과 Test Double에 새 Repository 메서드를 반영한다.
2. 활성 세션 조회부터 Draft 조회·이미지 다운로드·화면 복원까지 통합 테스트를
   추가한다.
3. 기존 공통 응답 파싱 및 Drawing 회귀 테스트를 실행한다.

## 작업 6: 검증 및 통합

1. `dart format --output=none --set-exit-if-changed lib test`
2. `flutter analyze`
3. `flutter test test/features/drawing`
4. `flutter test`
5. 최신 `origin/develop`을 확인하고 변경이 있으면 안전하게 반영한다.
6. 동일 검증을 다시 실행한다.
7. Jira 이슈 코드가 포함된 Commit과 Merge Request를 생성하고 target이
   `develop`인지 확인한다.
8. Pipeline과 Merge 가능 상태를 확인한 뒤 Merge한다.
