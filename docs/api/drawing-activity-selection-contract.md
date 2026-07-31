# 그림 활동 선택·재개·교체 계약

> 기준 이슈: `S15P11B209-696`
> 적용 범위: Flutter ↔ Spring Boot ↔ MySQL
> 출시 활동: `HTP`, `ART_DIARY`

## 1. 목적

보호자가 선택한 아동이 그림 활동을 시작할 때 HTP와 그림일기 중 하나를 선택한다.
진행 중인 활동이 있으면 가장 최근 활동 하나만 이어서 할 수 있으며, 새 활동을 선택하면 기존 활동은 삭제하지 않고 포기 상태로 보존한다.

HTP는 심리 진단이나 검사 결과를 제공하지 않는다. 집·나무·사람 그림과 대화를 관찰 자료로 정리하는 활동이며, 화면과 API 설명에서도 진단·판정 표현을 사용하지 않는다.

## 2. 사용자 흐름

```text
보호자 로그인
→ 아동 프로필 선택
→ 아동 홈
→ 그림 그리기
→ 그림일기 또는 HTP 카드 선택
→ 진행 중 활동 조회
   ├─ 없음: 선택한 활동의 안내 확인 후 시작
   └─ 있음
      ├─ 이어 그리기: 기존 세션의 현재 단계로 즉시 이동
      └─ 새로 그리기: 선택한 활동으로 기존 활동을 교체하고 새 Canvas로 즉시 이동
→ 그림일기: 그림 1장 → 대화 → 감정 → 완료
→ HTP: 집 → 대화 → 나무 → 대화 → 사람 → 대화 → 감정 → 완료
```

활성 활동이 있어도 사용자는 방금 누른 활동을 새로 시작할 수 있다. 팝업 뒤에 활동 선택 화면을 다시 열지 않으며, 새로 그리기를 확정하는 순간 기존 활동은 더 이상 재개할 수 없고 새 활동만 진행 중 상태가 된다.

그림일기는 `CANVAS` 전용이다. HTP는 HOUSE, TREE, PERSON 각 단계 시작 전에 `CANVAS`와 `UPLOAD` 중 입력 방식을 선택한다. 진행 중 활동 팝업의 `새로 그리기`는 사용자가 직접 그리겠다는 의사를 확정한 빠른 진입 동작이므로 새 활동을 `CANVAS`로 즉시 시작한다.

## 3. 활동 유형

`GET /api/v1/drawing-types?childId={childId}&activeOnly=true` 응답을 정본으로 사용한다.

| 코드 | 분류 | 화면 표시 | 세션 구조 |
| --- | --- | --- | --- |
| `ART_DIARY` | `GENERAL` | 그림일기 | Drawing Session 1개 |
| `HTP` | `ASSESSMENT` | 집·나무·사람 그리기 | HTP 묶음 1개 + Drawing Session 3개 |

- Flutter는 응답에 없는 활동을 임의로 추가하지 않는다.
- 이번 출시 화면은 `HTP`, `ART_DIARY`만 표시한다.
- 카드 순서는 `displayOrder`를 따른다.
- `recommendedAgeMin`, `recommendedAgeMax`는 보호자 안내용 참고값이며 카드 노출이나 활동 시작을 막는 조건으로 사용하지 않는다.
- 선택 주체가 `GUARDIAN`이면 보호자가 선택한 아동 모드 안에서만 시작한다.

## 4. 진행 중 활동 조회

### 4.1 API

```http
GET /api/v1/drawing-sessions/active?childId={childId}
Authorization: Bearer {accessToken}
```

진행 중 활동이 HTP 단계라면 별도 추측이나 추가 검색 없이 묶음을 복원할 수 있도록 `activityContext`를 제공한다.

```json
{
  "drawingSessionId": 100,
  "childId": 1,
  "drawingType": {
    "drawingTypeId": 5,
    "code": "HTP",
    "name": "집·나무·사람 그림"
  },
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "DRAWING",
  "activityContext": {
    "activityKind": "HTP",
    "htpAssessmentId": 41,
    "htpStatus": "IN_PROGRESS",
    "stepOrder": 2,
    "drawingSubject": "TREE"
  },
  "latestDraft": null
}
```

그림일기에는 다음과 같이 일반 활동 문맥을 반환한다.

```json
{
  "activityContext": {
    "activityKind": "GENERAL",
    "htpAssessmentId": null,
    "htpStatus": null,
    "stepOrder": null,
    "drawingSubject": null
  }
}
```

진행 중 활동이 없으면 기존 오류 계약인 `404 DRAWING_404_005`를 사용한다.

## 5. 새 활동 시작과 기존 활동 교체

### 5.1 공통 정책

- `replaceActive` 기본값은 `false`다.
- 진행 중 활동이 있는데 `replaceActive=false`면 기존 `409` 충돌을 반환한다.
- `replaceActive=true`면 아동 행을 잠근 동일 트랜잭션에서 기존 활동을 포기 처리하고 새 활동을 생성한다.
- 기존 활동의 그림, 획, Draft, 대화는 즉시 삭제하지 않는다.
- 이전 활동은 `ABANDONED` 상태가 되어 활성 조회와 보호자 일반 활동 기록에서 제외된다.
- 파일 삭제 Queue는 새 활동 시작 과정에서 등록하지 않는다.
- 같은 `Idempotency-Key`와 같은 요청을 재전송하면 처음 생성한 새 활동을 반환한다.
- 같은 Key를 다른 아동·활동에 사용하면 `409`로 거부한다.

### 5.2 그림일기 시작

```http
POST /api/v1/drawing-sessions
Authorization: Bearer {accessToken}
Idempotency-Key: {uuid}
Content-Type: application/json
```

```json
{
  "childId": 1,
  "drawingTypeId": 7,
  "inputMethod": "CANVAS",
  "clientStartedAt": "2026-07-29T10:00:00+09:00",
  "replaceActive": true
}
```

`HTP` 유형을 이 API로 시작할 수 없다.

### 5.3 HTP 시작

```http
POST /api/v1/htp-assessments
Authorization: Bearer {accessToken}
Idempotency-Key: {uuid}
Content-Type: application/json
```

```json
{
  "childId": 1,
  "inputMethod": "CANVAS",
  "clientStartedAt": "2026-07-29T10:00:00+09:00",
  "replaceActive": true
}
```

응답의 `currentStep.drawingSubject`와 `drawingSessionId`가 현재 단계의 정본이다. Flutter가 주제나 다음 세션 식별자를 생성하지 않는다.

`inputMethod`는 HOUSE 단계에서 선택한 입력 방식이다. `UPLOAD`를 선택하면 생성된 세션에
`POST /api/v1/drawing-sessions/{drawingSessionId}/upload`를 호출하고, 반환된
`drawingAssetId`를 `drawing-complete.metadata.sourceAssetId`로 전달한다. 상세 multipart와
오류 계약은 [HTP 사진 업로드 계약](./htp-image-upload-contract.md)을 따른다.

## 6. 포기 상태

`drawing_sessions.session_status`에 `ABANDONED`를 추가한다.

| 상태 | 의미 | 활성 조회 | 일반 활동 기록 |
| --- | --- | --- | --- |
| `IN_PROGRESS` | 이어서 할 수 있는 최신 활동 | 포함 | 정책에 따라 포함 |
| `COMPLETED` | 정상 완료 | 제외 | 포함 |
| `FAILED` | 처리 실패 | 제외 | 포함 |
| `ABANDONED` | 새 활동 시작으로 재개가 종료된 활동 | 제외 | 제외 |
| `DELETED` | 사용자가 명시적으로 삭제한 활동 | 제외 | 제외 |

`ABANDONED`와 `DELETED`는 다르다.

- `ABANDONED`: 새 활동을 위해 재개 권한만 종료한다. 원본 데이터와 운영 이력을 보존한다.
- `DELETED`: 사용자의 명시적 삭제 요청이며 Soft Delete와 파일 삭제 예약을 수행한다.

HTP를 교체하면 `htp_assessments.status=ABANDONED`로 전환하고 현재 단계의 진행 중 Drawing Session도 `ABANDONED`로 전환한다. 이미 완료된 이전 단계 세션은 완료 상태를 유지하지만 일반 활동 기록에는 개별 활동으로 노출하지 않는다.

## 7. HTP 화면·단계 계약

HTP 순서는 다음 세 단계로 고정한다.

| 순서 | 주제 | 화면 |
| --- | --- | --- |
| 1 | `HOUSE` | 집 그리기 |
| 2 | `TREE` | 나무 그리기 |
| 3 | `PERSON` | 사람 그리기 |

- 화면 상단에 완료·진행 중·대기 중 상태를 표시한다.
- 그림을 그리는 동안 질문하지 않는다.
- 각 그림 완료 후 해당 그림에 관한 대화를 진행한다.
- 현재 단계의 대화가 끝나면 다음 단계의 입력 방식을 선택한 뒤
  `/htp-assessments/{id}/steps/next`를 호출한다.

```json
{
  "inputMethod": "CANVAS"
}
```

- `inputMethod`는 다음 TREE 또는 PERSON 세션에만 적용하며 `CANVAS`, `UPLOAD`를 허용한다.
- 사진 업로드는 JPEG·PNG만 허용하고, 서버가 실제 이미지의 크기와 형식을 검증한다.
- `UPLOAD` 단계는 업로드 응답의 `drawingAssetId`로 완료하며 별도 `finalImage`를 보내지 않는다.
- 세 그림을 모두 마친 뒤 활동 단위 감정을 한 번 저장한다.
- 최종 완료는 `/htp-assessments/{id}/complete`로 단일 종합 리포트를 접수한다.

그림일기는 HTP 단계 표시나 `drawingSubject`를 사용하지 않는다.

## 8. 동시성·오류 처리

- 새 활동 시작은 아동 단위 비관적 잠금 안에서 실행한다.
- 동시에 두 요청이 도착해도 활성 활동은 하나만 남아야 한다.
- 교체 대상이 요청 처리 중 이미 완료되었다면 완료 상태를 변경하지 않고 새 활동만 생성할 수 있다.
- 다른 요청이 더 최신 활동을 생성했다면 `replaceActive=false` 요청은 충돌로 종료한다.
- HTP 묶음과 일반 Drawing Session의 포기 및 새 활동 생성은 하나의 트랜잭션으로 처리한다.
- 포기 처리 후 새 활동 생성이 실패하면 전체 트랜잭션을 Rollback하여 기존 활동을 계속 재개할 수 있어야 한다.

## 9. 검증 기준

- 활성 활동이 없을 때 HTP·그림일기 유형을 조회하고 선택할 수 있다.
- 그림일기 선택 시 선택한 `drawingTypeId`로 세션을 만든다.
- HTP 선택 시 HOUSE 단계부터 시작하고 TREE, PERSON 순서를 건너뛰지 않는다.
- HTP 각 단계에서 Canvas 그리기 또는 사진 업로드를 독립적으로 선택할 수 있다.
- 사진 업로드 완료 시 서버가 반환한 `sourceAssetId`로 해당 단계의 분석을 요청한다.
- 활성 활동이 있으면 이어 그리기와 새로 그리기를 모두 제공한다.
- 이어 그리기는 기존 `drawingSessionId`, Draft, `currentStage`를 유지한다.
- 새로 그리기는 선택한 카드 정보를 유지해 중간 활동 선택 화면 없이 새 Canvas로 이동한다.
- 새 활동 시작은 기존 활동을 `ABANDONED`로 남기고 새 활동만 활성화한다.
- 앱 재실행 후 HTP의 `htpAssessmentId`, 현재 주제, 현재 세션을 복원한다.
- 포기된 활동은 일반 활동 기록과 이어 그리기에 나타나지 않는다.
- 네트워크 재시도와 동시 요청에도 중복 활성 활동이 생기지 않는다.
