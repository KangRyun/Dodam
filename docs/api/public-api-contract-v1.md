# Flutter-Backend 공개 API 계약 동결본 v1

> Jira: S15P11B209-525
>
> 기준일: 2026-07-27
>
> 기준 Commit: `9138eccdd832cba9063f7b017b22c94e0194846a`
>
> 외부 Base URL: `/api/v1`

## 1. 문서 역할

이 문서는 현재 `develop`에서 실행 가능한 Spring Boot 공개 API와 Flutter의
소비 상태를 한 목록으로 고정한다. Backend의 실제 Controller와
`/v3/api-docs/api-v1`을 구현된 계약의 정본으로 사용한다.

`docs/api/API_명세서_최종.md`에 정의됐더라도 Controller가 없으면 이 문서에서
`미구현`으로 표시한다. Flutter가 다른 URI를 호출하면 두 URI를 모두
지원하지 않고 `불일치`로 기록해 후속 Jira에서 하나의 계약으로 정합화한다.
Spring Boot와 AI 서버 사이의 `/internal/v1/**`는 이 문서의 범위가 아니다.

## 2. 공통 계약

### 2.1 인증

- `POST /api/v1/auth/oauth/{provider}`와 `POST /api/v1/auth/reissue`,
  CORS `OPTIONS`만 Access Token 없이 호출할 수 있다.
- 그 외 `/api/v1/**`는 `Authorization: Bearer {accessToken}`이 필수다.
- Controller에 남은 `X-Guardian-User-Id`는 OpenAPI에서 숨긴 전환기 입력이며
  공개 클라이언트 계약이 아니다. Flutter는 이를 전송하지 않는다.
- 현재 OAuth `provider`는 `KAKAO`, `GOOGLE`, `NAVER`다. Apple은
  S15P11B209-528과 S15P11B209-529에서 별도로 추가한다.

### 2.2 요청과 응답

- JSON Body는 `Content-Type: application/json`을 사용한다.
- 파일 API의 개별 표에 `multipart`가 표시된 경우
  `multipart/form-data`를 사용한다.
- `Idempotency-Key` 표시가 있는 요청은 동일 업무 요청을 재시도할 때 같은
  값을 유지해야 한다.
- 일반 성공 응답은 현재 다음 Envelope를 사용한다.

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

- 일반 오류 응답은 현재 다음 Envelope를 사용한다.

```json
{
  "success": false,
  "code": "DOMAIN_STATUS_SEQUENCE",
  "message": "외부에 공개해도 되는 오류 메시지",
  "data": null
}
```

- HTTP 204와 이미지·음성 Binary 응답에는 Envelope를 사용하지 않는다.
- 공통 Envelope와 Validation 상세, 오류 코드 호환성은
  `common-response-error-contract-v1.md`를 정본으로 사용한다.

### 2.3 상태 표기

| 표기 | 의미 |
| --- | --- |
| `구현` | Backend Controller와 공개 Mapping이 존재함 |
| `연동` | Flutter Remote Repository가 같은 Method·URI를 호출함 |
| `미연동` | Backend는 구현됐지만 Flutter 호출 코드가 없음 |
| `불일치` | Flutter 호출과 Backend Method·URI가 다르거나 Backend가 없음 |
| `미구현` | 확정 명세 또는 Flutter 호출은 있지만 Backend Controller가 없음 |

## 3. 인증·사용자·동의 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| POST | `/api/v1/auth/oauth/{provider}` | Provider Token, `deviceId` | 구현 | 연동 | Kakao·Naver `accessToken`, Google `idToken` |
| POST | `/api/v1/auth/reissue` | Refresh Token, `deviceId` | 구현 | 연동 | Access·Refresh Token 회전 |
| POST | `/api/v1/auth/logout` | Bearer | 구현 | 미연동 | 현재 앱은 로컬 세션 정리만 수행 |
| GET | `/api/v1/users/me` | Bearer | 구현 | 미연동 | 사용자 본인 조회 |
| PATCH | `/api/v1/users/me` | Bearer, JSON | 구현 | 미연동 | 사용자 본인 수정 |
| PUT | `/api/v1/users/me/onboarding` | Bearer, JSON | 구현 | 연동 | 프로필과 약관 동의 제출 |
| DELETE | `/api/v1/users/me` | Bearer, JSON | 구현 | 미연동 | 사용자 즉시 탈퇴 |
| GET | `/api/v1/consents/terms` | Bearer | 구현 | 연동 | 가입 시 약관 목록 조회 |
| GET | `/api/v1/consents` | Bearer | 구현 | 미연동 | 현재 동의 상태 조회 |
| GET | `/api/v1/consents/history` | Bearer | 구현 | 미연동 | 동의 이력 조회 |
| POST | `/api/v1/consents` | Bearer, JSON | 구현 | 미연동 | 최초 동의 저장 |
| PATCH | `/api/v1/consents` | Bearer, JSON | 구현 | 미연동 | 선택 동의 변경 |

## 4. 아동 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| POST | `/api/v1/children` | Bearer, JSON | 구현 | 연동 | 아동 등록 |
| GET | `/api/v1/children` | Bearer | 구현 | 연동 | 연결 아동 목록 |
| GET | `/api/v1/children/{childId}` | Bearer | 구현 | 연동 | 아동 상세 |
| PATCH | `/api/v1/children/{childId}` | Bearer, JSON | 구현 | 연동 | 아동 수정 |
| DELETE | `/api/v1/children/{childId}` | Bearer, JSON | 구현 | 연동 | 아동 삭제 |

## 5. 그림 활동·분석 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| GET | `/api/v1/drawing-types` | `childId`, 선택 `category`, `activeOnly` | 구현 | 연동 | 현재 활성 시드는 GENERAL 4종 |
| POST | `/api/v1/drawing-sessions` | JSON, `Idempotency-Key` | 구현 | 연동 | 선택한 `drawingTypeId`로 생성 |
| GET | `/api/v1/drawing-sessions/active` | `childId` | 구현 | 연동 | 활성 세션 Resume 기준 |
| GET | `/api/v1/drawing-sessions/{drawingSessionId}` | Bearer | 구현 | 연동 | 세션 상세 |
| DELETE | `/api/v1/drawing-sessions/{drawingSessionId}` | Bearer, JSON | 구현 | 불일치 | Flutter는 `/activities/{id}` 호출 |
| GET | `/api/v1/children/{childId}/drawing-sessions` | Paging Query | 구현 | 불일치 | Flutter는 `/children/{id}/activities` 호출 |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/stroke-batches` | JSON | 구현 | 연동 | Stroke·Undo 이벤트 배치 |
| PUT | `/api/v1/drawing-sessions/{drawingSessionId}/draft` | multipart | 구현 | 연동 | `preview`, JSON `canvasState` |
| GET | `/api/v1/drawing-sessions/{drawingSessionId}/draft` | Bearer | 구현 | 연동 | 최신 Draft Metadata |
| DELETE | `/api/v1/drawing-sessions/{drawingSessionId}/draft` | Bearer | 구현 | 연동 | Draft 삭제 |
| GET | `/api/v1/drawing-assets/{drawingAssetId}/file` | Bearer, Binary | 구현 | 연동 | Draft·그림 파일 Proxy |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/drawing-complete` | multipart, `Idempotency-Key` | 구현 | 연동 | `finalImage`, JSON `metadata` |
| PUT | `/api/v1/drawing-sessions/{drawingSessionId}/reflection` | JSON | 구현 | 연동 | 감정 돌아보기 저장 |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/complete` | JSON, `Idempotency-Key` | 구현 | 연동 | 활동 완료 접수, HTTP 202 |
| GET | `/api/v1/drawing-sessions/{drawingSessionId}/snapshots` | Bearer | 구현 | 미연동 | Snapshot 목록 |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/snapshots` | multipart | 구현 | 불일치 | Flutter는 `/upload` 호출 |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/analyses` | JSON | 구현 | 연동 | Draft 객체 탐지 또는 Final 분석 |
| GET | `/api/v1/drawing-sessions/{drawingSessionId}/analyses` | Bearer | 구현 | 미연동 | 분석 이력 |
| GET | `/api/v1/drawing-sessions/{drawingSessionId}/analyses/{drawingAnalysisId}` | Bearer | 구현 | 불일치 | Flutter는 `/analyses/{analysisId}` 호출 |
| POST | `/api/v1/analyses/{analysisId}/retry` | JSON | 구현 | 연동 | 실패 분석 재시도, Client 멱등 Header 미적용 |

## 6. 대화 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| POST | `/api/v1/drawing-sessions/{drawingSessionId}/conversations` | `Idempotency-Key` | 구현 | 연동 | 대화 시작 |
| POST | `/api/v1/conversations/{conversationId}/next-question` | JSON, `Idempotency-Key` | 구현 | 연동 | 다음 질문 생성 |
| POST | `/api/v1/conversations/{conversationId}/answers/option` | JSON, `Idempotency-Key` | 구현 | 연동 | 선택형 답변 |
| POST | `/api/v1/conversations/{conversationId}/answers/voice` | multipart, `Idempotency-Key` | 구현 | 연동 | 음성 답변 |
| POST | `/api/v1/conversations/{conversationId}/end` | JSON, `Idempotency-Key` | 구현 | 연동 | 대화 종료 |
| GET | `/api/v1/conversations/{conversationId}/messages` | Bearer | 구현 | 연동 | 메시지·STT 상태 목록 |
| GET | `/api/v1/conversation-messages/{messageId}` | Bearer | 구현 | 미연동 | 메시지 상세 |
| GET | `/api/v1/conversation-messages/{messageId}/audio` | Bearer, Binary | 구현 | 미연동 | 음성 Proxy |
| POST | `/api/v1/conversation-messages/{messageId}/tts` | JSON | 구현 | 미연동 | 질문 음성 합성 |

## 7. 알림 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| POST | `/api/v1/notifications/device-tokens` | JSON | 구현 | 미연동 | FCM Device Token 등록 |
| DELETE | `/api/v1/notifications/device-tokens/{deviceId}` | Bearer | 구현 | 미연동 | Device Token 삭제 |
| GET | `/api/v1/notifications` | Paging Query | 구현 | 미연동 | 알림 목록 |
| PATCH | `/api/v1/notifications/{notificationId}/read` | Bearer | 구현 | 미연동 | 알림 읽음 |

## 8. 커뮤니티 API

| Method | URI | 요청 특이사항 | Backend | Flutter | 비고 |
| --- | --- | --- | --- | --- | --- |
| POST | `/api/v1/posts` | JSON | 구현 | 미연동 | 게시글 생성 |
| GET | `/api/v1/posts` | Paging Query | 구현 | 미연동 | 게시글 목록 |
| GET | `/api/v1/posts/{postId}` | Bearer | 구현 | 미연동 | 게시글 상세 |
| PATCH | `/api/v1/posts/{postId}` | JSON | 구현 | 미연동 | 게시글 수정 |
| DELETE | `/api/v1/posts/{postId}` | Bearer | 구현 | 미연동 | 게시글 삭제 |

## 9. 알려진 미구현·불일치 계약

아래 항목은 Flutter 코드 또는 전체 명세에 있지만 현재 Backend 공개
Controller가 없다. 이번 이슈에서 호환 Endpoint를 추가하지 않는다.

| Flutter 또는 명세 계약 | Backend 정본 또는 상태 | 후속 처리 |
| --- | --- | --- |
| `GET /api/v1/children/{childId}/activities` | `GET /api/v1/children/{childId}/drawing-sessions` | Flutter 활동 이력 경로 정합화 |
| `GET /api/v1/activities/{activityId}` | `GET /api/v1/drawing-sessions/{drawingSessionId}` | Flutter 상세 경로 정합화 |
| `DELETE /api/v1/activities/{activityId}` | `DELETE /api/v1/drawing-sessions/{drawingSessionId}` | Flutter 삭제 Body 포함 정합화 |
| `POST /api/v1/drawing-sessions/{id}/upload` | `POST /api/v1/drawing-sessions/{id}/snapshots` | Snapshot 계약으로 정합화 |
| `GET /api/v1/analyses/{analysisId}` | 세션 하위 분석 상세 URI만 구현 | Flutter가 `drawingSessionId`를 함께 사용 |
| `GET/PATCH /api/v1/children/{childId}/tutorial` | 미구현 | Tutorial Backend Jira |
| `GET /api/v1/children/{childId}/reports` | 미구현 | Report 조회 Backend Jira |
| `GET /api/v1/reports/{reportId}` | 미구현 | Report 조회 Backend Jira |

## 10. 변경 규칙

공개 API의 Method, URI, Header, Content-Type, 요청·응답 DTO를 바꿀 때는
다음을 한 Jira 범위에서 함께 반영한다.

1. 이 계약 문서와 관련 상세 명세
2. Backend Controller·DTO·OpenAPI와 정상·오류·권한·경계 테스트
3. Flutter Remote Repository·DTO와 테스트
4. 배포 후 `/v3/api-docs/api-v1` 및 실제 앱 E2E

같은 기능의 구 URI와 신 URI를 동시에 추가하지 않는다. 미구현 또는 불일치
항목은 실제 구현과 소비자 정합화가 모두 끝난 뒤에만 `구현`·`연동`으로
변경한다.
