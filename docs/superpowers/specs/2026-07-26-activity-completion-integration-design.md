# 전체 활동 완료 API 통합 설계

## 목적

Flutter의 화면 전환만으로 끝나던 활동 완료 흐름을 Backend 상태 전이와 연결한다. 대화를 시작한 활동은 Conversation End, 회고 저장, Activity Complete 순서를 지키며, HTTP 202 이후 처리 중·완료·실패 상태를 구분한다.

## 확인된 기존 구현

- Backend `POST /api/v1/conversations/{conversationId}/end`는 `develop`에 병합됐으며 성공 시 Conversation을 `COMPLETED`, Drawing Session을 `REFLECTION`으로 전환한다.
- Backend `POST /api/v1/drawing-sessions/{drawingSessionId}/complete`는 완료 작업을 접수하고 HTTP 202를 반환한다.
- Flutter `ConversationEndController`는 멱등 키 재사용 구조를 이미 갖췄지만 요청의 필수 `reason`이 없고 Mock Repository만 연결돼 있다.
- Flutter 회고 화면은 `saveReflection` 성공 직후 완료 화면으로 이동하며 Activity Complete를 호출하지 않는다.
- Backend의 `requestReport=false` 경로는 별도 S15P11B209-645에서 보완하며, 이 이슈에서는 `true`만 사용한다.

## 접근 방법 비교

### 화면에서 API와 polling을 직접 처리

변경 파일 수는 적지만 Widget이 HTTP 계약, 멱등 키, 재시도와 polling 정책을 모두 소유한다. 화면 테스트가 복잡해지고 재사용하기 어렵기 때문에 채택하지 않는다.

### DrawingRepository 확장과 ActivityCompletionController 사용

기존 Drawing Session 조회 기능을 재사용하고, Activity Complete 요청 DTO와 메서드만 `DrawingRepository`에 추가한다. `ActivityCompletionController`가 요청 키 유지와 상태 polling을 담당하고 화면은 상태만 렌더링한다. 기존 구조와 가장 잘 맞고 변경 범위가 명확해 이 방식을 채택한다.

### Conversation End부터 완료까지 단일 Coordinator 사용

전체 순서를 한 객체가 보장할 수 있지만 DrawingScreen과 EmotionSelectScreen 사이에서 상태를 장기간 전달해야 한다. 화면 생명주기와 도메인 흐름이 강하게 결합되므로 현재 범위에는 과도하다.

## 확정 설계

### Conversation End

- `ConversationCompletionReason` Dart enum을 Backend 문자열과 동일하게 정의한다.
- 아동이 종료 버튼을 누르는 현재 UI는 `CHILD_REQUEST`를 전송한다.
- `lastQuestionMessageId`는 화면이 알고 있을 때만 전송한다.
- `RemoteConversationEndRepository`는 공통 응답의 `data`를 해제하고 `completed`를 검증한다.
- `DodamApp`과 `AppRouter`가 Repository를 주입하며 실제 앱은 Remote, 테스트 기본값은 Mock을 유지한다.
- Conversation End 재시도는 `ConversationEndController`가 보관한 동일 키와 동일 요청을 사용한다.

### 화면 간 완료 정보 전달

- DrawingScreen에 Conversation이 생성됐다면 완료 전에 종료 성공을 요구한다.
- Conversation이 생성되지 않은 활동만 `conversationSkipped=true`다.
- EmotionSelect route arguments에 `conversationSkipped`를 추가한다.
- Conversation이 존재하지만 종료되지 않은 상태에서는 감정 화면으로 이동하지 않고 종료 안내를 표시한다.

### 회고 저장과 Activity Complete

- EmotionSelectScreen은 회고 저장 성공 후 Activity Complete를 호출한다.
- 요청은 `conversationSkipped`와 `requestReport=true`를 포함한다.
- Activity Complete용 멱등 키는 Conversation End 키와 별개이며, 실패 재시도 동안 유지한다.
- HTTP 202가 접수되기 전에는 완료 화면으로 이동하지 않는다.
- 회고 저장은 재시도 시 다시 호출될 수 있으나 동일 세션의 회고를 덮어쓰는 기존 Backend 계약을 이용한다.

### 완료 상태 확인

- ActivityCompleteScreen은 `ActivityCompletionController`를 사용한다.
- 화면 진입 후 `GET /api/v1/drawing-sessions/{sessionId}`를 조회한다.
- `IN_PROGRESS/REPORTING`은 처리 중, `COMPLETED/COMPLETED`는 최종 완료, `FAILED`는 실패로 표시한다.
- polling은 간격을 둔 제한 횟수 방식으로 수행하고, 제한 도달 시 처리 중 상태와 수동 재확인 버튼을 유지한다.
- 처리 중에는 최종 완료 문구를 표시하지 않는다.
- 최종 완료 전 보호자 홈으로 이동하는 것은 허용하되, 새 활동 시작 시 기존 활성 세션 재개 정책이 계속 적용된다.

## 오류 처리

- Conversation End 실패 시 현재 그림과 대화 화면을 유지하고 동일 키로 재시도한다.
- 회고 저장 또는 Activity Complete 접수 실패 시 선택한 감정과 제목을 유지하고 동일 Activity Complete 키로 재시도한다.
- polling 통신 실패는 완료 실패로 단정하지 않고 재확인 가능한 처리 중 상태로 표시한다.
- Backend가 `FAILED`를 반환한 경우에만 명시적인 후속 처리 실패 화면을 표시한다.
- 토큰, 요청 본문, 아동 개인정보를 로그나 사용자 오류 문구에 포함하지 않는다.

## 테스트

- RemoteConversationEndRepository의 URI, Header, reason, 공통 응답 parsing을 검증한다.
- ConversationEndController가 실패 재시도에서 같은 키와 reason을 유지하는지 검증한다.
- Conversation이 생성된 상태에서 종료 전 감정 화면 이동이 차단되는지 검증한다.
- 회고 저장 다음에 Activity Complete가 호출되고 `requestReport=true`가 전달되는지 검증한다.
- Activity Complete 실패 재시도에서 같은 키를 사용하는지 검증한다.
- 202 이후 REPORTING, COMPLETED, FAILED 및 polling 통신 실패 UI를 검증한다.
- 기존 Flutter 전체 테스트와 `flutter analyze`를 실행한다.

## 제외 범위

- Backend Conversation End API 재구현
- Backend `requestReport=false` 상태 전이 수정
- Stroke Batch, Draft 업로드, Drawing Complete multipart 계약 변경
- 리포트 상세 화면 구현
