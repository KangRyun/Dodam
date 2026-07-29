# HTP 사진 업로드 API 계약

## 1. 목적

종이에 그린 HTP 그림을 카메라 또는 앨범에서 선택해 현재 HTP 단계의 원본 그림으로 저장한다.
그림일기는 서비스 Canvas에서 직접 그리는 방식만 지원하며 이 API를 사용하지 않는다.

## 2. 적용 범위

- 허용 활동: HTP
- 허용 주제: `HOUSE`, `TREE`, `PERSON`
- 허용 입력 방식: `UPLOAD`
- 허용 세션 상태: `IN_PROGRESS`
- 허용 단계: `DRAWING`
- 그림일기와 일반 `CANVAS` 세션의 호출은 거부한다.
- Canvas 자동 저장인 `/snapshots`, `/draft` 계약은 변경하지 않는다.

## 3. Endpoint

```http
POST /api/v1/drawing-sessions/{drawingSessionId}/upload
Authorization: Bearer {accessToken}
Idempotency-Key: {8~100자 요청 식별자}
Content-Type: multipart/form-data
```

### Multipart Part

| Part | Content-Type | 필수 | 설명 |
| --- | --- | --- | --- |
| `image` | `image/jpeg`, `image/png` | O | 종이에 그린 현재 HTP 주제 그림. 최대 10 MiB |
| `metadata` | `application/json` | O | 클라이언트 촬영·보정 정보 |

```json
{
  "clientCapturedAt": "2026-07-29T13:00:00+09:00",
  "rotationDegrees": 0,
  "cropApplied": true
}
```

- `clientCapturedAt`: 선택값. 없으면 서버 저장 시각을 캡처 시각으로 사용한다.
- `rotationDegrees`: 선택값. `0`, `90`, `180`, `270`만 허용한다. 서버는 이 값을 파일 변환 지시로
  사용하지 않고 클라이언트가 수행한 보정을 기록·검증하는 용도로만 사용한다.
- `cropApplied`: 필수 Boolean. 사용자가 그림 영역을 확인했는지 나타낸다.

## 4. 저장·검증

1. Access Token의 보호자가 해당 HTP 세션에 접근할 수 있는지 확인한다.
2. 세션이 `inputMethod=UPLOAD`, `IN_PROGRESS/DRAWING`인지 확인한다.
3. 해당 세션이 실제 HTP Assessment의 `HOUSE`, `TREE`, `PERSON` 단계 중 하나인지 확인한다.
4. 파일 Signature, MIME Type, 확장자를 교차 검증한다.
5. 파일 크기는 10 MiB 이하, 가로·세로는 각각 320~8192px인지 확인한다.
6. EXIF Orientation을 픽셀에 반영하고 EXIF·XMP·IPTC·텍스트 Metadata 없이 다시 인코딩한다.
7. 정제된 파일을 Storage에 저장하고 `drawing_assets.asset_type=UPLOADED`로 기록한다.
8. 업로드만으로 AI 분석을 시작하지 않으며 세션의 `currentStage`는 `DRAWING`으로 유지한다.

흐림 정도와 실제 그림 영역 존재 여부는 신뢰 가능한 AI 품질 검증기가 연결되기 전에는 서버가 임의
판정하지 않는다. `IMAGE_TOO_BLURRY`, `DRAWING_REGION_NOT_FOUND`는 향후 검증기에서 사용하는 예약
오류 코드이며 현재 MVP는 `qualityWarnings=[]`를 반환한다.

## 5. 성공 응답

HTTP `201 Created`

```json
{
  "success": true,
  "code": "COMMON_201",
  "message": "요청에 성공했습니다.",
  "data": {
    "drawingSessionId": 101,
    "drawingAssetId": 501,
    "assetType": "UPLOADED",
    "drawingSubject": "HOUSE",
    "currentStage": "DRAWING",
    "previewUrl": "/api/v1/drawing-assets/501/file",
    "mimeType": "image/jpeg",
    "fileSizeBytes": 1425012,
    "widthPx": 1440,
    "heightPx": 1080,
    "capturedAt": "2026-07-29T04:00:00Z",
    "uploadedAt": "2026-07-29T04:00:01Z",
    "qualityWarnings": []
  }
}
```

- `previewUrl`은 JWT가 필요한 Backend Proxy 경로다.
- Storage Key, Bucket, 서버 파일 경로는 응답에 노출하지 않는다.
- Flutter는 `drawingAssetId`를 보관하고 그림 완료 요청의 `sourceAssetId`로 전달한다.

## 6. 그림 완료 연계

```http
POST /api/v1/drawing-sessions/{drawingSessionId}/drawing-complete
Idempotency-Key: {완료 요청 식별자}
Content-Type: multipart/form-data
```

UPLOAD 세션은 `finalImage`를 다시 전송하지 않고 Metadata의 `sourceAssetId`에 앞선
`UPLOADED` Asset ID를 전달한다. Backend는 같은 세션의 `UPLOADED` Asset만 허용하고 이를 AI 분석
원본으로 사용한다. 분석 접수 이후의 상태 전이는 기존 그림 완료 계약을 따른다.

## 7. 멱등성

- `Idempotency-Key`의 범위는 현재 보호자, Endpoint, `drawingSessionId`다.
- 서버는 정제된 이미지 Checksum과 정규화 Metadata로 요청 Fingerprint를 계산한다.
- 동일 Key와 동일 Fingerprint의 재시도는 새 Asset을 만들지 않고 최초 `201` 결과를 반환한다.
- 동일 Key를 다른 이미지 또는 Metadata에 재사용하면 HTTP `409`,
  `DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT`를 반환한다.
- 같은 세션에는 `UPLOADED` Asset을 하나만 허용한다. 다른 Key로 다시 올리려면 기존 업로드 세션을
  중단하고 새 세션을 생성한다.

## 8. 오류

| HTTP | 오류 코드 | 조건 |
| --- | --- | --- |
| 400 | `DRAWING_UPLOAD_FILE_REQUIRED` | `image` Part 누락 |
| 400 | `DRAWING_UPLOAD_METADATA_INVALID` | Metadata 누락 또는 필드 형식 오류 |
| 400 | `DRAWING_UPLOAD_NOT_SUPPORTED` | 그림일기·Canvas 또는 HTP가 아닌 세션 |
| 400 | `STORAGE_400_002` | JPEG/PNG 이외 형식 |
| 400 | `STORAGE_400_003` | MIME Type·확장자·Signature 불일치 |
| 401 | 공통 인증 오류 | Access Token 누락 또는 검증 실패 |
| 403 | 공통 접근 권한 오류 | 연결되지 않은 보호자의 세션 |
| 404 | `DRAWING_404_003` | 세션이 없거나 삭제됨 |
| 409 | `DRAWING_UPLOAD_NOT_ALLOWED` | 세션이 `IN_PROGRESS/DRAWING`이 아님 |
| 409 | `DRAWING_UPLOAD_ALREADY_EXISTS` | 다른 Key로 저장된 업로드 그림이 이미 존재 |
| 409 | `DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT` | 같은 Key에 다른 요청 사용 |
| 413 | `STORAGE_413_001` | 10 MiB 초과 |
| 422 | `STORAGE_422_001` | 가로·세로가 320~8192px 범위를 벗어남 |
| 500 | `DRAWING_UPLOAD_FAILED` | 파일 또는 Metadata 저장 실패 |

예약 오류:

- `IMAGE_TOO_BLURRY`: AI 품질 검증기가 흐림을 판정할 때 사용한다.
- `DRAWING_REGION_NOT_FOUND`: AI 품질 검증기가 그림 영역 부재를 판정할 때 사용한다.

## 9. 취소·재시도 정책

- 이미지 선택 화면에서 전송 전에 취소하면 Backend 호출을 하지 않는다.
- 세션 생성 후 활동을 취소하면 기존
  `DELETE /api/v1/drawing-sessions/{drawingSessionId}`와 `confirmation=DELETE`를 사용한다.
- 삭제는 Session과 Asset Metadata를 Soft Delete 대상으로 만들고 파일은 수명주기 정책으로 정리한다.
- 전송 오류는 같은 `Idempotency-Key`로 재시도한다.
- 새 이미지를 선택해 다시 시작하려면 기존 세션을 중단하고 새 HTP 세션을 생성한다.
