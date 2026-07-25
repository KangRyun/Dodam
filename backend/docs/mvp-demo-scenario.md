# MVP 시연 대본 — Swagger UI 그리기 루프 Happy-Path

도담 MVP 핵심 그리기 루프(로그인 → 아동 등록 → 그림 세션 → 스트로크/스냅샷 → 분석 → 대화 → 회고 → 완료 → 리포트 확인)를
**Swagger UI에서 위에서 아래로 순서대로 눌러** 시연하기 위한 대본이다.

각 단계의 요청 경로·인증·요청 body·기대 상태코드·다음 단계로 넘길 응답 필드를 그대로 붙여넣을 수 있게 정리했다.
이 대본의 요청/응답 값은 형제 이슈 **S15P11B209-156** 의 통합 테스트 `MvpFlowIntegrationTest`(실제 요청/응답으로 검증된 관통 happy-path)를 **정본**으로 한다.

> ⚠️ 먼저 읽어라 — 라이브 Swagger만으로는 이 흐름을 100% 관통할 수 없다. 세부 사유는 문서 말미 [데모 제약 요약](#데모-제약-요약) 참고.

---

## 0. Swagger UI 접속 및 인증

### 접속
- OpenAPI 도구: **springdoc-openapi 2.8.17** (`org.springdoc:springdoc-openapi-starter-webmvc-ui`).
- Swagger UI: `http://<host>:8080/swagger-ui.html` (기본 포트 `8080`, `application.yml`의 `server.port`).
- OpenAPI 문서(JSON): 전체 `http://<host>:8080/v3/api-docs`, 그룹 `api-v1` 은 `http://<host>:8080/v3/api-docs/api-v1`.
- 그룹 `api-v1` = `/api/v1/**` 경로만 포함(`OpenApiConfig.apiV1Group`). 이 대본의 모든 호출은 이 그룹에 있다.
- 태그는 시연 흐름 순서(인증 → 아동 → 그림 세션 → 스트로크 → 스냅샷 → 그림 분석 → 대화 → 회고 → 완료)로 정렬되어 있어 위에서 아래로 진행하면 된다(`OpenApiConfig` 태그 정렬 커스터마이저).

### 인증 흐름 (한 번만)
1. 아래 **1단계(카카오 로그인)** 를 먼저 실행해 응답의 `data.accessToken`(서비스 JWT)을 복사한다.
2. Swagger UI 우측 상단 **Authorize** 버튼 클릭 → `bearerAuth (http, Bearer)` 입력란에 복사한 `accessToken` 만 붙여넣는다(`Bearer ` 접두사는 UI가 자동으로 붙이므로 **토큰 값만** 입력).
3. Authorize 후에는 이후 모든 호출에 `Authorization: Bearer <accessToken>` 이 자동 적용된다.
4. `Idempotency-Key` 가 필요한 단계는 각 요청 UI의 헤더 입력란에 임의의 유일 문자열(예: `mvp-create-session-key`)을 넣는다.

---

## 시연 시퀀스 (경로 접두사 `/api/v1`)

| # | 목적 | METHOD 경로 | 인증 | 기대 코드 | 다음으로 넘길 응답 필드 |
|---|------|-------------|------|-----------|------------------------|
| 1 | 카카오 로그인 | POST `/auth/oauth/kakao` | 없음 | 200 | `data.accessToken`, `data.user.userId`, `data.grantType`(=Bearer) |
| 2 | 아동 등록 | POST `/children` | Bearer | 201 | `data.childId` |
| 3 | 그림 세션 생성 | POST `/drawing-sessions` | Bearer + Idempotency-Key | 201 | `data.drawingSessionId` |
| 4 | 스트로크 배치 제출 | POST `/drawing-sessions/{id}/stroke-batches` | Bearer | 201 | — |
| 5 | 최종 스냅샷 업로드 | POST `/drawing-sessions/{id}/snapshots` (multipart) | Bearer | 201 | `data.drawingAssetId` (FINAL) |
| 6 | 그림 분석 요청 | POST `/drawing-sessions/{id}/analyses` | Bearer | 201 | `data.drawingAnalysisId` |
| 7 | 그림 분석 조회 | GET `/drawing-sessions/{id}/analyses/{analysisId}` | Bearer | 200 | — (⚠️ 제약 A) |
| 8 | 대화 시작 | POST `/drawing-sessions/{id}/conversations` | Bearer + Idempotency-Key | 201 | `data.conversationId` |
| 9 | 다음 질문 요청 | POST `/conversations/{conversationId}/next-question` | Bearer + Idempotency-Key | 200 | `data.messageId`, `data.options[]` |
| 10 | 선택형 답변 제출 | POST `/conversations/{conversationId}/answers/option` | Bearer + Idempotency-Key | 201 | — |
| 11 | 대화 내역 조회 | GET `/conversations/{conversationId}/messages` | Bearer | 200 | — (⚠️ 제약 B) |
| 12 | 회고 저장 | PUT `/drawing-sessions/{id}/reflection` | Bearer | 200 | — |
| 13 | 완료 접수 | POST `/drawing-sessions/{id}/complete` | Bearer + Idempotency-Key | 202 | — |
| 14 | 세션 상세(리포트 확인) | GET `/drawing-sessions/{id}` | Bearer | 200 | `data.reportId`, `data.currentStage`(=COMPLETED) |

`{id}` = 3단계에서 받은 `drawingSessionId`, `{conversationId}` = 8단계에서 받은 `conversationId`.

---

### 1. 카카오 로그인 — POST `/auth/oauth/kakao`
- 인증: **없음** (`@SecurityRequirements` 로 인증 제외).
- 요청 body:
```json
{
  "accessToken": "provider-token",
  "deviceId": "mvp-device-001"
}
```
- 기대: **200**. 확보: `data.accessToken`(→ Authorize에 등록), `data.user.userId`, `data.grantType`(=`Bearer`).
- ⚠️ 라이브 주의: 실 서버는 카카오 Provider Token을 **실제로 검증**한다. 위 `"provider-token"` 더미 값은 실 카카오에서 401이 난다. 데모에서는 유효한 카카오 accessToken을 준비하거나 Provider 검증을 mock한 프로필로 기동해야 한다(156 통합 테스트는 `OAuthProviderClient` 를 mock). [데모 제약](#데모-제약-요약) 참고.

### 2. 아동 등록 — POST `/children`
- 인증: Bearer.
- 요청 body:
```json
{
  "nickname": "별이",
  "birthDate": "2018-05-10",
  "relationshipType": "MOTHER",
  "preferredCharacter": "MONGLE",
  "questionDifficulty": "LOWER_ELEMENTARY",
  "responseModes": ["EMOJI", "VOICE"]
}
```
- 기대: **201**. 확보: `data.childId`.

### 3. 그림 세션 생성 — POST `/drawing-sessions`
- 인증: Bearer + 헤더 `Idempotency-Key`(예: `mvp-create-session-key`).
- 요청 body:
```json
{
  "childId": <childId>,
  "drawingTypeId": 1,
  "inputMethod": "CANVAS",
  "clientStartedAt": "2026-07-21T11:30:00+09:00",
  "canvas": {"width": 1920, "height": 1080, "backgroundColor": "#FFFFFF"}
}
```
- 기대: **201**, `sessionStatus=IN_PROGRESS`, `currentStage=DRAWING`. 확보: `data.drawingSessionId`.
- 사전 조건: `drawing_types` 에 `id=1` 행이 존재해야 한다(156 테스트는 `FREE_DRAWING` 유형 1행을 시드). 데모 DB에 활성 그림 유형이 없으면 먼저 시드 필요.

### 4. 스트로크 배치 제출 — POST `/drawing-sessions/{id}/stroke-batches`
- 인증: Bearer.
- 요청 body:
```json
{
  "batchSequence": 1,
  "firstEventSequence": 1,
  "lastEventSequence": 1,
  "clientCreatedAt": "2026-07-21T11:32:10.120+09:00",
  "events": [{
    "sequence": 1,
    "eventType": "STROKE",
    "tool": "PEN",
    "color": "#FFCC00",
    "width": 8.0,
    "points": [{"x": 0.18, "y": 0.42, "t": 0}, {"x": 0.19, "y": 0.43, "t": 16}]
  }],
  "metrics": {
    "undoCountDelta": 0,
    "redoCountDelta": 0,
    "eraseCountDelta": 0,
    "pauseDurationMsDelta": 0
  }
}
```
- 기대: **201**(신규 배치). 같은 순번·payload 재전송 시 200.

### 5. 최종 스냅샷 업로드 — POST `/drawing-sessions/{id}/snapshots`
- 인증: Bearer. `multipart/form-data` 로 두 Part 전송:
  - `file`: `image/png` 이미지 파일(임의의 작은 PNG).
  - `metadata`: `application/json` Part =
```json
{"assetType": "FINAL", "assetVersion": 1, "capturedAt": "2026-07-21T11:40:00+09:00"}
```
- 기대: **201**, `data.assetType=FINAL`, `storageKey` **미노출**(내부 저장 위치는 응답에 포함하지 않음). 확보: `data.drawingAssetId`.
- Swagger UI 팁: multipart Part 두 개(`file`, `metadata`)를 각각 지정한다. `metadata` Part는 JSON 텍스트로 위 값을 넣는다.

### 6. 그림 분석 요청 — POST `/drawing-sessions/{id}/analyses`
- 인증: Bearer.
- 요청 body(`drawingAssetId` = 5단계의 FINAL 자산):
```json
{"drawingAssetId": <finalAssetId>, "analysisType": "OBJECT_DETECTION"}
```
- 기대: **201**. 확보: `data.drawingAnalysisId`.
- ⚠️ 라이브 주의: 실제 분석은 AI 분석 클라이언트 호출을 수반한다. mock 프로필(`app.ai.*.mode=mock`)이 아니면 AI 서버가 필요.

### 7. 그림 분석 조회 — GET `/drawing-sessions/{id}/analyses/{analysisId}`
- 인증: Bearer. `{analysisId}` = 6단계 `drawingAnalysisId`.
- 기대: **200**. 상태(PENDING/PROCESSING/SUCCEEDED/FAILED)와 저장된 결과를 조회한다.
- ⚠️ **데모 제약 A — 여기서 라이브 Swagger 흐름이 막힐 수 있음.** 다음 단계(대화 시작)의 사전 조건은 세션 단계가 `ANALYZING` 또는 `CONVERSING` 인 것이다. 그러나 그림 단계 `DRAWING → ANALYZING` 로 전이하는 **HTTP 경로가 현재 없다**(분석 요청도 세션 단계를 바꾸지 않는다). 156 통합 테스트는 이 지점을 `UPDATE drawing_sessions SET current_stage='ANALYZING'` 로 우회했다. 데모에서는 **DB 보정(수동 UPDATE) 또는 후속 이슈**가 필요하다.

### 8. 대화 시작 — POST `/drawing-sessions/{id}/conversations`
- 인증: Bearer + 헤더 `Idempotency-Key`(예: `mvp-conversation-start-key`).
- 요청 body:
```json
{"analysisId": <analysisId>, "maxQuestionCount": 5}
```
- 기대: **201**, `status=CONVERSING`. 확보: `data.conversationId`.
- 사전 조건: 제약 A(7단계)의 `ANALYZING` 전이가 선행되어야 한다.

### 9. 다음 질문 요청 — POST `/conversations/{conversationId}/next-question`
- 인증: Bearer + 헤더 `Idempotency-Key`(예: `mvp-next-question-key`).
- 요청 body:
```json
{"basisAnalysisId": <analysisId>, "preferredResponseModes": ["EMOJI"]}
```
- 기대: **200**, `data.senderType=AI`, `data.messageType=QUESTION`, `data.options[]` 존재. 확보: `data.messageId`, `data.options[]`.
- ⚠️ 라이브 주의: 다음 질문 생성은 **AI 질문 클라이언트가 실연동**(`RestClientAiQuestionClient`, mock 프로필 없음)이라 데모 시 **AI 서버가 반드시 필요**하다. 156 테스트는 `AiQuestionClient` 를 mock으로 대체해 `HOUSE/TREE` 선택지를 반환했다.

### 10. 선택형 답변 제출 — POST `/conversations/{conversationId}/answers/option`
- 인증: Bearer + 헤더 `Idempotency-Key`(예: `mvp-option-answer-key`).
- 요청 body(9단계 응답 `options[]` 의 첫 선택지를 회신):
```json
{
  "questionMessageId": <messageId>,
  "selectedOptions": [
    {"optionId": "HOUSE", "type": "STATIC", "value": "HOUSE", "labelSnapshot": "집"}
  ]
}
```
- 기대: **201**, `data.messageType=ANSWER_OPTION`.
- ⚠️ **선택지 Snapshot 완전 일치 필수 + 응답 `type` 함정.** 답변은 저장된 질문 선택지 Snapshot(`conversation_message_options`)의 네 값과 **모두 일치**해야 저장된다:
  - `optionId` = 저장 `option_key` = 선택지 코드(예: `HOUSE`) — 9단계 응답 `options[].optionId` 와 동일.
  - `type` = 저장 `option_type` = **항상 `"STATIC"`**. **9단계 응답의 `options[].type` 은 `"OPTION"` 으로 노출되지만, 이 값을 그대로 쓰면 매칭 실패한다. 반드시 `"STATIC"` 으로 보낸다.**
  - `value` = 저장 `option_value` = 선택지 코드(코드와 동일, 예: `HOUSE`) — 9단계 응답 `options[].value` 와 동일.
  - `labelSnapshot` = 저장 `label`(예: `집`) — 9단계 응답 `options[].label` 과 동일.
  - 요약: 라이브 AI가 반환한 실제 코드/라벨을 쓰되 `type` 만 `"STATIC"` 으로 바꿔야 한다.

### 11. 대화 내역 조회 — GET `/conversations/{conversationId}/messages`
- 인증: Bearer.
- 기대: **200**. `data.totalElements=2`, `content[0]`=AI/QUESTION, `content[1]`=CHILD/ANSWER_OPTION.
- ⚠️ **데모 제약 B — 다음 완료 단계가 막힐 수 있음.** 완료(13단계, `conversationSkipped=false`)는 대화 상태가 `COMPLETED` 여야 하는데, 대화 상태 `CONVERSING → COMPLETED` 전이 **HTTP 경로가 현재 없다**(대화 컨트롤러에 상태를 COMPLETED로 바꾸는 API 없음). 156 테스트는 `UPDATE conversation_sessions SET conversation_status='COMPLETED'` 로 우회했다. 데모에서는 **DB 보정 또는 후속 이슈**가 필요하다.

### 12. 회고 저장 — PUT `/drawing-sessions/{id}/reflection`
- 인증: Bearer.
- 요청 body:
```json
{
  "title": "우리 가족",
  "selectedEmotions": ["HAPPY"],
  "expressedEmotionText": "재밌었어요",
  "skipped": false
}
```
- 기대: **200**, `data.currentStage=REFLECTION`.
- 참고: 실제 상태머신은 대화(→CONVERSING) 후 회고(CONVERSING→REFLECTION)만 허용하므로, 회고는 대화(제약 B 우회 포함) 이후에 호출한다.

### 13. 완료 접수 — POST `/drawing-sessions/{id}/complete`
- 인증: Bearer + 헤더 `Idempotency-Key`(예: `mvp-complete-key`).
- 요청 body:
```json
{"conversationSkipped": false, "requestReport": true}
```
- 기대: **202**, `data.currentStage=REPORTING`, `data.reportStatus=GENERATING`.
- 동작: 완료 커밋 직후 동기 `@TransactionalEventListener(AFTER_COMMIT)` 리스너가 리포트를 생성하며, 세션을 COMPLETED로 전이한다.

### 14. 세션 상세(리포트 확인) — GET `/drawing-sessions/{id}`
- 인증: Bearer.
- 기대: **200**, `data.currentStage=COMPLETED`, `data.reportId` 존재.
- 이 응답의 `reportId` 로 리포트 생성 완료를 확인하며 시연을 마친다.

---

## 데모 제약 요약

발표자가 라이브 시연 전에 반드시 인지해야 할 제약이다. 이 중 전이 2건은 순수 HTTP(Swagger)만으로 관통 불가하다.

1. **DRAWING → ANALYZING 전이 HTTP 부재 (제약 A, 7→8단계 사이).** 대화 시작 사전 조건인 `ANALYZING` 단계로 올리는 HTTP 경로가 없다. 데모 시 DB 수동 UPDATE 또는 후속 이슈 필요.
2. **CONVERSING → COMPLETED 대화 상태 전이 HTTP 부재 (제약 B, 11→13단계 사이).** 완료(대화 미생략) 사전 조건인 대화 `COMPLETED` 로 바꾸는 HTTP 경로가 없다. 데모 시 DB 수동 UPDATE 또는 후속 이슈 필요.
3. **AI 서버 의존.** 6단계(그림 분석)와 9단계(다음 질문 생성)는 AI 연동을 수반한다. 특히 다음 질문은 실연동 클라이언트(mock 프로필 없음)라 **AI 서버 없이는 라이브 진행 불가**. mock 프로필로 기동하거나 AI 서버를 준비해야 한다.
4. **선택지 Snapshot 일치 + 응답 `type` 함정 (10단계).** 답변 선택지는 저장 Snapshot의 `optionId/type/value/labelSnapshot` 네 값과 완전 일치해야 저장된다. 특히 **응답이 노출하는 `type="OPTION"` 을 그대로 쓰면 실패**하며, 저장 값 `type="STATIC"` 으로 보내야 한다.
5. **카카오 Provider 실검증 (1단계).** 실 서버는 카카오 accessToken을 실제 검증하므로 더미 토큰으로는 로그인되지 않는다. 유효 토큰 또는 Provider mock 프로필 필요.
6. **기준 데이터 시드 (3단계).** 활성 그림 유형(`drawing_types`, 예: `id=1`)이 DB에 있어야 세션 생성이 가능하다.

## 참고
- 정본 통합 테스트: `backend/src/test/java/com/ssafy/b209/mvp/MvpFlowIntegrationTest.java` (S15P11B209-156).
- 태그 정렬·인증 스킴: `backend/src/main/java/com/ssafy/b209/global/config/OpenApiConfig.java`.
