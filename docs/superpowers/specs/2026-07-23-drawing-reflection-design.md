# S15P11B209-142 그림 활동 감정·제목 저장 설계

## 범위

최신 API 명세의 DRAWING-10 계약에 따라 연결 보호자가 그림 활동의 제목, 선택 감정과 직접 표현을 저장하는 API를 구현한다.

- `PUT /api/v1/drawing-sessions/{drawingSessionId}/reflection`
- 기존 `drawing_sessions`와 정규화된 `drawing_session_emotions`를 사용한다.
- 그림 단계 완료, 전체 활동 완료, 리포트 생성은 후속 이슈 범위로 제외한다.
- 기존 Flyway Migration은 수정하지 않으며 새 Migration도 필요하지 않다.

## 요청과 응답

요청 필드는 다음과 같다.

- `title`: 선택 입력이며 공백만 있으면 `null`로 정규화한다. 최대 200자이다.
- `selectedEmotions`: `HAPPY`, `SAD`, `ANGRY`, `SCARED`, `CALM`, `UNKNOWN` 중 선택한다.
- `expressedEmotionText`: 선택 입력이며 공백만 있으면 `null`로 정규화한다.
- `skipped`: 감정 선택을 건너뛰었는지 나타낸다.

성공 응답은 `drawingSessionId`, `currentStage`, `selectedEmotions`, `skipped`를 반환한다. 저장이 끝난 세션의 `currentStage`는 `REFLECTION`이다.

## 검증 규칙

- `skipped=false`이면 감정을 하나 이상 선택해야 한다.
- 감정 코드는 중복할 수 없다.
- `UNKNOWN`은 다른 감정과 함께 선택할 수 없다.
- `skipped=true`이면 감정 배열은 비어 있고 `expressedEmotionText`는 `null`이어야 한다.
- 삭제되지 않은 `IN_PROGRESS` 세션만 수정할 수 있다.
- 최초 저장은 `CONVERSING`, 재시도와 수정은 `REFLECTION` 단계에서 허용한다.

잘못된 요청은 400, 허용되지 않는 상태 전이는 409로 응답한다. 존재하지 않거나 다른 보호자의 자원은 기존 권한 정책에 따라 동일한 404로 처리한다.

## 구조와 처리 흐름

Controller는 요청 검증과 공통 응답 조립만 담당한다. Service는 현재 인증 사용자 확인, 소유권 검증, 세션 쓰기 잠금, 상태 전이와 감정 목록 교체를 하나의 Transaction에서 수행한다.

`DrawingSession`은 제목, 직접 표현과 `REFLECTION` 단계 전이를 책임진다. `DrawingSessionEmotion`은 정규화된 감정 코드와 선택 순서를 표현한다. 전용 Repository는 PUT 요청마다 기존 목록을 삭제하고 요청 순서대로 새 목록을 저장한다.

처리 순서는 다음과 같다.

1. 요청 형식과 감정 조합을 검증한다.
2. 인증 사용자와 그림 활동 소유 관계를 확인한다.
3. 세션에 쓰기 잠금을 획득한다.
4. 세션 상태와 단계를 검증한다.
5. 기존 감정 목록을 제거하고 새 선택을 순서대로 저장한다.
6. 제목과 직접 표현을 저장하고 단계를 `REFLECTION`으로 변경한다.
7. 저장 결과를 공통 `ApiResponse`로 반환한다.

## 테스트

- Service 단위 테스트: 정상 저장, 건너뛰기, 재저장, 권한 거부, 상태 거부
- 요청 검증 테스트: 빈 선택, 중복, `UNKNOWN` 혼합, 잘못된 건너뛰기 조합
- Controller MockMvc 테스트: URI, JSON 계약, 공통 응답
- MySQL 통합 테스트: 기존 목록 교체, 선택 순서, 세션 필드와 단계 저장
