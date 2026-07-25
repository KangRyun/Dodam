# S15P11B209-370 MinIO 파일 스토리지 전환 설계

## 목표

로컬 파일 시스템에 한정된 그림·음성 저장 계층을 MinIO의 S3 호환 API로 전환한다.
기존 Service가 구체 구현을 알지 않도록 `ImageStorage`와 `AudioStorage` 경계를 유지하고,
`app.storage.mode=local|s3` 설정만으로 저장 방식을 선택하거나 롤백할 수 있게 한다.

## 범위

- 기존 `ImageStorage.read`와 `StoredImageContent` 계약 재사용
- `AudioStorage`에 저장 객체를 스트리밍으로 읽는 계약 추가
- 기존 Local 그림 읽기 회귀 및 Local 음성 읽기 경로 안전성 검증
- AWS SDK for Java v2 기반 S3/MinIO 구현
- Local/S3 구현 선택을 위한 Spring Boot 설정
- Docker Compose의 Backend MinIO 환경 변수 배선
- Local 및 S3 구현의 저장·조회·삭제·오류 테스트
- 기존 파일 이관과 검증 절차 문서화

다음 작업은 후속 이슈로 분리한다.

- 그림 파일 공개 API와 보호자 인가: `S15P11B209-371`
- Flutter Draft 조회·화면 복원: `S15P11B209-253`
- 파일 수명주기 및 삭제 Queue 처리: `S15P11B209-373`

## 현재 구조와 충돌

`ImageStorage`는 S15P11B209-402에서 `StoredImageContent read(String)`까지
구현되어 AI 일회성 이미지 조회에 사용된다. `AudioStorage`는
`stage`·`promote`·`discard`·`delete`만 제공해 동일한 읽기 경계가 없다. MinIO
Container와 Bucket은 이미 `develop`에 포함되어 있지만 Backend 자격증명과 S3
Client는 연결되지 않았다.

`AudioStorage.stage`는 파일 형식과 재생 시간을 검증하기 위해 임시 로컬 파일을
사용한다. 이 검증을 S3에 위임하지 않고 기존 Local staging 과정을 유지하며,
`promote` 시 검증된 파일만 S3에 업로드한다.

## 저장 객체 읽기 계약

그림은 기존 `StoredImageContent`를 변경하지 않고 사용한다. 음성은 같은 소유권
규칙을 따르는 `StoredAudioContent`를 추가한다.

```java
public record StoredAudioContent(
    InputStream inputStream,
    String contentType,
    long size
) implements AutoCloseable {}
```

호출자는 `try-with-resources`로 결과를 닫아야 한다. Local 구현은
`Files.newInputStream`을 반환하고 S3 구현은 SDK의 `ResponseInputStream<GetObjectResponse>`
을 그대로 반환한다. 어느 구현도 전체 파일을 메모리에 적재하지 않는다.

Storage Key는 `/`로 구분된 상대 Key만 허용한다. 빈 Segment, `.`·`..`, 역슬래시,
절대 경로는 Local과 S3 모두 거부한다. S3 구현도 검증을 생략하지 않아 잘못된 Key가
다른 Prefix 접근으로 이어지지 않게 한다.

## S3 객체 구조

Bucket은 인프라에서 준비한 `dodam`을 사용한다.

- 그림: `images/{기존-image-storage-key}`
- 음성: `audio/{기존-audio-storage-key}`

DB에는 기존과 동일하게 Prefix를 제외한 Storage Key를 저장한다. 이 방식은 DB
Migration 없이 Local/S3 전환이 가능하고, 외부 API에 Bucket·Prefix·자격증명을
노출하지 않는다.

`S3ImageStorage.store`는 입력 Stream을 SDK의 `RequestBody.fromInputStream`으로
전송한다. 기존 Image signature·MIME type·크기·checksum 검증은 공통 검증 단계에서
끝낸 뒤 업로드한다. 업로드 실패 시 완료되지 않은 객체를 남기지 않으며, DB 저장
실패 시 기존 Service의 `delete` 보상 처리를 그대로 사용한다.

`S3AudioStorage.stage`는 기존 검증 로직으로 임시 파일을 만든다. `promote`는
검증 완료 파일을 `audio/` Prefix에 업로드하고 성공한 뒤 임시 파일을 삭제한다.
업로드 실패 시 임시 파일을 정리하고 성공 결과를 반환하지 않는다.

## 설정

기본값은 개발 환경 호환성을 위해 Local로 유지한다.

```yaml
app:
  storage:
    mode: ${STORAGE_MODE:local}
    s3:
      endpoint: ${S3_ENDPOINT:http://localhost:9000}
      region: ${S3_REGION:ap-northeast-2}
      bucket: ${S3_BUCKET:dodam}
      access-key: ${MINIO_BE_USER:}
      secret-key: ${MINIO_BE_PASSWORD:}
      path-style-access-enabled: true
```

`local` 모드에서는 기존 `LocalImageStorage`와 `LocalAudioStorage`를 등록한다.
`s3` 모드에서는 자격증명·Endpoint·Bucket이 비어 있거나 잘못되면 Application
Context 초기화 단계에서 실패시킨다. Secret은 환경 변수에서만 주입하며 로그,
README, 오류 응답에 값을 기록하지 않는다.

Docker Compose Backend에는 다음만 전달한다.

- `STORAGE_MODE`
- `S3_ENDPOINT=http://minio:9000`
- `S3_REGION`
- `S3_BUCKET`
- `MINIO_BE_USER`
- `MINIO_BE_PASSWORD`

## 오류 처리

- 잘못된 Storage Key: 기존 `INVALID_STORAGE_PATH`
- 존재하지 않거나 읽을 수 없는 객체: Storage read 실패 코드
- S3 연결·권한·전송 실패: 외부 상세를 숨긴 Storage 실패 코드
- 사용자 API에는 Bucket, Key, 서버 경로, SDK Exception, Stack Trace를 노출하지 않음

후속 그림 조회 API에서는 DB에 Asset이 없을 때만 404를 반환한다. DB에는 Asset이
있지만 객체가 없는 경우는 데이터 무결성 문제이므로 일반적인 사용자 404로
위장하지 않고 서버 Storage 오류로 처리한다.

## 테스트

- Local Image/Audio read 성공, Stream close, Content-Type과 길이 검증
- Local 경로 순회·Symbolic Link·존재하지 않는 파일 오류
- S3 Image 저장·조회·삭제 및 Prefix 검증
- S3 Audio stage·promote·조회·삭제와 실패 시 임시 파일 정리
- `app.storage.mode`별 Bean 선택 및 S3 필수 설정 검증
- MinIO Testcontainers 통합 테스트는 Docker 사용 가능 환경에서 실행
- Docker가 없는 환경에서는 테스트를 삭제하거나 비활성화하지 않고 미실행 사유를 보고

## 배포와 기존 파일 이관

1. 새 Backend를 `STORAGE_MODE=local`로 먼저 배포해 회귀를 확인한다.
2. Backend 쓰기를 잠시 중단한 상태에서 기존 `/app/storage/images`와
   `/app/storage/audio`를 각각 `dodam/images`, `dodam/audio`로 복사한다.
3. Prefix별 객체 수와 전체 Byte 크기, 표본 checksum을 원본과 대조한다.
4. `STORAGE_MODE=s3`로 전환하고 업로드·조회·삭제 종단 테스트를 수행한다.
5. 구 Local Volume은 1주간 읽기 전용으로 보존한 뒤 별도 승인하에 정리한다.

파일 이관은 운영 데이터 변경이므로 애플리케이션 MR에서 자동 실행하지 않는다.
검증 결과를 남긴 수동 배포 절차로 수행한다.
