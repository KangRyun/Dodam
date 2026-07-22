# 그림 스냅샷 업로드 API 설계

## 1. 목적과 범위

Jira `S15P11B209-141` 범위에서 그림 활동 중간본 또는 최종본 이미지를 `multipart/form-data`로 받아 로컬 파일 시스템과 `drawing_assets`에 함께 저장한다. 선행 이슈 `S15P11B209-140`의 `ImageStorage`를 재사용하며, AI 호출·분석 결과 생성·활동 상태 전환은 수행하지 않는다.

작업 브랜치는 최신 `develop`에서 분기한 로컬 전용 `feat/drawing-snapshot-upload`이다. 브랜치를 원격에 게시하지 않는다.

## 2. 기존 구조와 충돌 해소

- 최신 API 명세와 ERD는 저장된 그림 파일을 `DrawingAsset`, `drawingAssetId`, `assetType`으로 정의하므로 `DrawingSnapshot` Entity를 새로 만들지 않는다.
- HTTP URI는 Jira 프롬프트의 신규 계약인 `POST /api/v1/drawing-sessions/{drawingSessionId}/snapshots`를 사용한다. 동일 기능의 기존 Endpoint는 없다.
- Multipart Part는 `file`과 `metadata`를 사용한다. 최신 전체 API 명세의 `image` Part는 종이 그림 업로드 전용 계약이므로 이 Endpoint에 혼용하지 않는다.
- 요청은 기존 `drawing_assets.asset_type`, `asset_version`에 맞춰 `assetType`, `assetVersion`을 사용한다. `snapshotType`, `sequenceNumber`, `finalSnapshot`은 같은 의미를 중복 표현하므로 추가하지 않는다.
- 허용 `assetType`은 이번 API 범위에 필요한 `INTERMEDIATE`, `FINAL`뿐이다. `DRAFT`, `UPLOADED`, `THUMBNAIL`, `TIMELAPSE`는 다른 API의 책임이다.
- 이미지 형식은 확정된 공통 업로드 규약과 선행 Storage 구현에 맞춰 JPEG·PNG만 허용한다. WEBP는 이번 범위에서 추가하지 않는다.
- 인증 인프라가 없으므로 소유권 검증을 구현된 것처럼 처리하지 않는다. 사용자 ID Header, 가짜 Principal, 하드코딩 사용자 ID를 추가하지 않고 README에 제한을 기록한다.

## 3. API 계약

### 3.1 요청

```http
POST /api/v1/drawing-sessions/{drawingSessionId}/snapshots
Content-Type: multipart/form-data
```

| 위치 | 이름 | 타입 | 규칙 |
| --- | --- | --- | --- |
| Path | `drawingSessionId` | positive int64 | 필수, 1 이상 |
| Part | `file` | JPEG 또는 PNG binary | 필수, 비어 있지 않음, 최대 10 MiB |
| Part | `metadata` | `UploadDrawingSnapshotRequest` JSON | 필수 |

`UploadDrawingSnapshotRequest`는 다음 필드를 가진다.

| 필드 | 타입 | 규칙 |
| --- | --- | --- |
| `assetType` | `DrawingAssetType` | `INTERMEDIATE`, `FINAL`만 허용 |
| `assetVersion` | integer | 필수, 1 이상 |
| `capturedAt` | `OffsetDateTime` | 필수, Offset 포함 ISO-8601 |

클라이언트는 저장 Key, Checksum, 파일 크기, MIME Type, 서버 저장 시각, 분석 상태를 지정하지 않는다.

### 3.2 응답

정상 응답은 `201 Created`와 기존 `ApiResponse<UploadDrawingSnapshotResponse>`를 사용한다. `Location`은 `/api/v1/drawing-sessions/{drawingSessionId}/snapshots/{drawingAssetId}`다.

응답 데이터는 다음 필드만 포함한다.

| 필드 | 의미 |
| --- | --- |
| `drawingAssetId` | 생성된 `drawing_assets.id` |
| `drawingSessionId` | 소속 그림 활동 세션 ID |
| `assetType` | `INTERMEDIATE` 또는 `FINAL` |
| `assetVersion` | 자산 유형 안의 버전 |
| `mimeType` | Signature로 검증된 MIME Type |
| `fileSizeBytes` | 실제 저장된 Byte 수 |
| `checksumSha256` | 실제 저장 Byte의 SHA-256 Hex |
| `capturedAt` | 클라이언트 캡처 시각 |
| `uploadedAt` | 서버 UTC 저장 시각 |

`storageKey`, 원본 파일명, 저장 파일명, 절대 경로, 사용자·아동 정보와 AI 결과는 응답하지 않는다.

## 4. Domain과 DB 설계

### 4.1 Entity

`DrawingAsset` Entity를 `drawing_assets`에 매핑한다. Entity는 `DrawingSession`, `DrawingAssetType`, `assetVersion`, `storageKey`, `mimeType`, `fileSizeBytes`, `checksumSha256`, `capturedAt`, `createdAt`을 관리한다. 현재 API에서 사용하지 않는 `fileUrl`, 크기, 만료 시각, Stroke 순번과 Object 코드는 DB 기본값 또는 `null`로 유지한다.

`DrawingAsset.upload(...)` Factory는 필수값과 허용 자산 유형을 검증하고 공개 Setter를 제공하지 않는다. 파일 시스템 호출과 AI 호출은 Entity에서 수행하지 않는다.

### 4.2 V4 Migration

기존 V1~V3는 수정하지 않고 `V4__add_drawing_asset_upload_constraints.sql`을 추가한다.

1. `drawing_assets.captured_at DATETIME(6)`을 nullable로 추가한다.
2. 기존 행의 `captured_at`을 `created_at`으로 채운다.
3. `captured_at`을 `NOT NULL`로 변경한다.
4. `(drawing_session_id, asset_type, asset_version)` UNIQUE를 추가한다.
5. `asset_type='FINAL'`일 때만 `drawing_session_id`를 반환하는 generated column `final_drawing_session_id`를 추가한다.
6. `final_drawing_session_id`에 UNIQUE를 적용해 세션당 FINAL 자산을 하나만 허용한다.

버전은 자산 유형별로 관리한다. 따라서 같은 세션의 `INTERMEDIATE` 1과 `FINAL` 1은 공존할 수 있지만 같은 세션·유형·버전은 중복될 수 없다. Soft Delete와 자산 교체는 이번 범위에 없으므로 삭제된 행을 제외하는 복잡한 유일성 모델을 추가하지 않는다.

## 5. Storage 계약 보강

`StoredImage`에 `checksumSha256`을 추가한다. `LocalImageStorage`는 기존 단일 Streaming 과정에서 `MessageDigest`를 함께 갱신해 파일을 다시 읽지 않고 SHA-256을 계산한다.

파일 저장 후 DB 저장 실패를 보상하기 위해 `ImageStorage.delete(String storageKey)`를 추가한다. 삭제 구현은 다음을 보장한다.

- 상대 Key만 허용한다.
- 정규화한 대상이 설정된 Storage Root 내부인지 검증한다.
- Symbolic Link 경로를 거부한다.
- 존재하는 일반 파일만 삭제하며 디렉터리를 삭제하지 않는다.
- 절대 경로와 Storage 내부 경로를 오류 응답에 노출하지 않는다.
- 파일이 이미 없으면 보상 완료로 간주한다.

범용 조회·다운로드·파일 관리 API는 추가하지 않는다.

## 6. Service 처리와 일관성

`DrawingSnapshotService.uploadSnapshot(...)`은 다음 순서로 처리한다.

1. 파일 존재 여부와 빈 파일 여부를 확인한다.
2. 삭제되지 않은 `DrawingSession`을 조회한다.
3. `sessionStatus=IN_PROGRESS`, `currentStage=DRAWING`인지 확인한다.
4. 같은 세션·유형·버전과 기존 FINAL 자산을 사전 확인한다.
5. `MultipartFile`의 Stream을 `StoreImageCommand`로 변환해 `ImageStorage.store(...)`에 전달한다.
6. 검증된 `StoredImage`와 서버 `Clock`으로 `DrawingAsset`을 생성한다.
7. `saveAndFlush`로 DB UNIQUE 위반을 Commit 이전에 확인한다.
8. DB 저장 실패 시 방금 저장한 `storageKey`를 보상 삭제한다.
9. 보상 삭제 실패는 원래 DB 오류를 덮어쓰지 않고 경로 없이 내부 경고만 남긴다.

서비스는 `@Transactional` 범위에서 Metadata를 저장하되 파일 저장 중 DB Row Lock을 잡지 않는다. 사전 조회는 사용자 친화적인 오류를 위한 것이고, 동시 요청의 최종 방어선은 DB UNIQUE다. 동시 충돌은 `DRAWING_SNAPSHOT_CREATION_CONFLICT` 409로 변환하고 두 번째 요청 파일을 정리한다.

파일 저장 실패 시 Entity를 만들거나 Repository를 호출하지 않는다. 업로드 성공 후에도 `DrawingSession`의 상태·단계·완료 시각을 변경하지 않는다.

## 7. 오류 계약

기존 `DrawingErrorCode`에 이번 범위의 오류만 추가한다.

| Enum | HTTP | Code | 조건 |
| --- | ---: | --- | --- |
| `DRAWING_SESSION_NOT_FOUND` | 404 | `DRAWING_404_003` | 세션이 없거나 Soft Delete됨 |
| `DRAWING_SESSION_NOT_UPLOADABLE` | 409 | `DRAWING_409_004` | 진행 중·그림 단계가 아님 |
| `DRAWING_SNAPSHOT_SEQUENCE_CONFLICT` | 409 | `DRAWING_409_005` | 같은 세션·유형·버전 존재 |
| `DRAWING_FINAL_SNAPSHOT_EXISTS` | 409 | `DRAWING_409_006` | 같은 세션에 FINAL 존재 |
| `DRAWING_SNAPSHOT_CREATION_CONFLICT` | 409 | `DRAWING_409_007` | 동시 DB 제약 충돌 |
| `DRAWING_SNAPSHOT_FILE_REQUIRED` | 400 | `DRAWING_400_005` | 파일이 없거나 비어 있음 |

MIME, Signature, 크기와 파일 시스템 오류는 기존 `ImageStorageErrorCode`를 그대로 사용한다. SQL, 제약 이름, 경로, 원본 파일명과 예외 클래스는 응답에 포함하지 않는다.

## 8. Controller와 문서

기존 `DrawingSessionController`에 업로드 책임을 섞지 않고 `DrawingSnapshotController`를 추가한다. Controller는 Multipart 수신, Bean Validation, Service 호출, `201 Created`와 Location 조립만 담당한다.

Springdoc에는 201, 400, 404, 409, 413, 500을 문서화한다. 인증이 아직 없으므로 401·403이나 Bearer Scheme을 추가하지 않는다. `application.yml`에는 Storage 최대 크기와 맞춘 `max-file-size: 10MB`, Metadata 여유를 둔 `max-request-size: 11MB`를 추가한다.

README에는 실제 cURL, JPEG·PNG, 중복 규칙, 로컬 저장 한계, 소유권 검증 미연결, AI 미호출과 상태 미변경을 기록한다.

## 9. 테스트 전략

구현은 TDD로 진행한다.

- Storage: SHA-256 계산, 안전한 삭제, 없는 파일 삭제, 절대·이탈·Symbolic Link Key 거부
- Entity: Factory 필수값, 허용 유형, Entity 필드 매핑
- Repository: 저장, 유형·버전 중복, FINAL 존재, 다른 유형·세션 허용, MySQL UNIQUE
- Service: 정상 JPEG·PNG, 세션 상태·단계, 중복, Storage 실패, DB 실패 보상 삭제, 보상 실패 시 원래 오류 유지, 상태 미변경
- Controller: Multipart 201와 Location, Part·Metadata Validation, 404·409·Storage 오류 응답
- Migration: Flyway V4, `captured_at`, 복합 UNIQUE, FINAL generated UNIQUE, JSON 0개와 기존 V3 계약 유지
- 전체 회귀: `clean test`, `spotlessCheck`, `javadoc`

## 10. 제외 범위

- WEBP, S3, Presigned URL, 조회·다운로드
- 이미지 리사이징·압축·EXIF·썸네일
- DRAFT 자동 저장, 종이 그림 업로드, 활동 완료
- Soft Delete·자산 교체·최신 자산 조회
- AI 호출, Mock 분석 결과, 분석 상태 Row
- 인증·JWT·소유권 인프라
- Redis, Message Queue, 분산 Lock
