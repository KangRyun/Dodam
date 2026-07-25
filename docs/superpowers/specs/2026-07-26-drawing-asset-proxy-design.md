# S15P11B209-371 그림 파일 프록시 설계

## 목적

보호자가 자신에게 연결된 아동의 그림 파일을 애플리케이션에서 다시 불러올 수 있도록 인증 기반 프록시 API를 제공한다. Storage Key와 서버 파일 경로는 외부에 노출하지 않으며 Local Storage와 MinIO 모두 기존 `ImageStorage` 계약으로 처리한다.

## 확정 API

```http
GET /api/v1/drawing-assets/{drawingAssetId}/file
Authorization: Bearer <access-token>
```

성공 응답은 저장소가 확인한 `Content-Type`, `Content-Length`와 다음 Cache Header를 포함한다.

```http
Cache-Control: private, no-store
```

본문은 `StreamingResponseBody`로 전달하며 파일 전체를 `byte[]`로 적재하지 않는다.

## 요청 처리 순서

1. 기존 `CurrentAuthenticatedUserResolver`에서 보호자 사용자 ID를 구한다.
2. `DrawingAssetRepository`에서 Asset Metadata를 조회한다.
3. Asset이 속한 Drawing Session ID로 `GuardianResourceAccessValidator`를 호출한다.
4. 권한 확인 후에만 `ImageStorage.read(storageKey)`를 호출한다.
5. Controller가 열린 Stream을 응답으로 복사하고 작업 완료 시 닫는다.

Asset 또는 연결 관계가 없으면 기존 자원 은닉 정책에 따라 `DRAWING_SESSION_NOT_FOUND` 또는 그림 Asset 전용 404를 반환한다. 타인 Asset에 403을 반환하라는 Jira 문구보다 권한 없음과 자원 없음을 구분하지 않는 기존 정책을 우선한다.

Storage 파일이 Metadata와 불일치하여 없으면 기존 `ImageStorageErrorCode.IMAGE_NOT_FOUND`를 사용한다. SDK·파일시스템의 내부 오류 메시지, Bucket, Key, 절대 경로는 응답에 포함하지 않는다.

## 응답 URL 계약

`DrawingDraftResponse.previewUrl`과 `LatestDrawingDraftResponse.previewUrl`은 다음 상대 경로를 반환한다.

```text
/api/v1/drawing-assets/{drawingAssetId}/file
```

상대 URL은 만료되지 않지만 매 요청 Access Token이 필요하다. Flutter는 일반 `Image.network`가 아니라 기존 인증 HTTP Client로 Byte를 내려받아 복원해야 한다.

URL 조립은 별도 `DrawingAssetFileUrlFactory` 한 곳에서 담당해 최신 Draft 단독 조회와 활성 Session 조회가 같은 값을 반환하게 한다.

## 구성 요소

- `DrawingAssetFileQueryService`: 인증 사용자 확인, Asset 조회, 소유권 검증, Storage Stream 개방
- `DrawingAssetFileResource`: Controller에 전달할 Content Metadata와 소유권 있는 `StoredImageContent`
- `DrawingAssetFileController`: HTTP Header 구성과 Stream 복사
- `DrawingAssetFileUrlFactory`: 공개 API 상대 경로 생성

Controller는 Repository에 직접 접근하지 않는다. Service는 Local/MinIO 구현체가 아니라 `ImageStorage`에만 의존한다.

## 테스트

- Service: 정상 Asset 조회 시 권한 검증 후 Storage Stream 반환
- Service: 존재하지 않는 Asset은 Storage를 호출하지 않고 404
- Service: 타인 Asset은 기존 자원 은닉 정책의 404이며 Storage를 호출하지 않음
- Controller: Content-Type, Content-Length, `private, no-store`, 실제 Stream Body 확인
- Draft Service 및 활성 Session 조회: 동일한 상대 `previewUrl` 반환
- 회귀: Local/S3 `ImageStorage.read`, 기존 Draft 조회와 AI 이미지 접근 테스트

## 제외 범위

- Stroke Batch DTO와 sequence 변환
- Draft 업로드 multipart MIME
- Drawing Complete metadata와 성공 단계
- Flutter 다운로드·Canvas 복원
- presigned URL과 공개 CDN
- DB Schema 및 Flyway Migration
