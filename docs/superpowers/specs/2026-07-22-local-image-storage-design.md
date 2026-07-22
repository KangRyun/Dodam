# 로컬 이미지 저장 기능 설계

## 목적과 범위

Jira `S15P11B209-140`의 후속 그림 스냅샷 업로드 API가 사용할 파일 시스템 저장 경계를 제공한다. 이번 변경은 이미지 데이터를 안전하게 저장하고 상대 `storageKey`를 반환하는 내부 기능만 포함하며, Controller, `MultipartFile`, DB, AI, S3 및 조회·삭제 API는 포함하지 않는다.

## 기존 구조와 정합성

- Java 21, Spring Boot 3.5.16, Gradle 8.14.3과 현재 Layered Architecture를 유지한다.
- Base Package는 `com.ssafy.b209`이며 구현은 `storage.image` 패키지에 모은다.
- 시간은 기존 `Clock` Bean을 사용하고 오류는 기존 `ErrorCode`와 `BusinessException`으로 전달한다.
- 설정은 기존 CORS와 같은 `@ConfigurationProperties` + `@EnableConfigurationProperties` 방식으로 등록한다.
- 기존 Storage, 파일 저장 Service, `MultipartFile` 처리 또는 이미지 제한 구현은 없다.

## 문서 충돌 해소

이슈 프롬프트는 명세가 없을 때 JPEG·PNG·WEBP 지원을 제안하지만, 2026-07-21 API 공통 규약은 이미지 업로드를 `image/png|jpeg`, 최대 10 MB로 확정한다. 최신 공통 규약을 우선하여 이번 구현은 JPEG와 PNG만 허용한다. WEBP는 API 계약이 변경될 때 별도 확장한다.

공통 규약의 오류 응답과 성공 응답 형태는 현재 프로젝트의 `ApiResponse`/`ApiErrorResponse` 구현과 차이가 있다. 이번 저장 계층에는 HTTP Endpoint가 없으므로 전역 응답 구조를 변경하지 않고 기존 코드의 `ErrorCode` 규칙을 따른다. 이 차이는 별도 공통 API 계약 정합화 작업에서 해결해야 한다.

## 공개 계약

`ImageStorage.store(StoreImageCommand)`는 저장된 이미지의 안전한 Metadata를 `StoredImage`로 반환한다.

```java
public interface ImageStorage {
  StoredImage store(StoreImageCommand command);
}

public record StoreImageCommand(
    InputStream inputStream, long size, String contentType, String originalFilename) {}

public record StoredImage(
    String storageKey, String storedFileName, String contentType, long size) {}
```

호출자는 `store` 호출과 함께 `InputStream` 소유권을 넘긴다. 구현은 Stream을 한 번만 소비하며 성공과 실패 모두에서 닫는다. 반환된 `storageKey`는 `/` 구분자를 쓰는 `yyyy/MM/dd/{UUID}.{ext}` 상대 경로이고 절대 경로는 반환하지 않는다.

## 설정

`app.storage.image.root`는 `${LOCAL_IMAGE_STORAGE_ROOT:./storage/images}`, `max-size`는 `${LOCAL_IMAGE_MAX_SIZE:10485760}`로 Binding한다. `max-size`는 양수여야 한다. 구현 생성 시 Root를 절대·정규화하고, 없으면 생성하며, 일반 파일이거나 안전하게 사용할 수 없으면 시작을 실패시킨다.

## 검증과 저장 흐름

1. Command, Stream, 선언 크기, MIME Type과 원본 파일명을 검증한다.
2. 선언 크기는 1 이상이고 설정된 최대 크기 이하여야 한다.
3. UTC `Clock`으로 날짜 경로를 만들고 Root 하위인지 확인한다.
4. Root 내부 날짜 디렉터리에 임시 파일을 만들고 고정 Buffer로 Streaming한다.
5. 최대 크기보다 한 Byte라도 많으면 즉시 중단하며, 실제 Byte 수가 선언 크기와 다르면 거부한다.
6. 복사 중 수집한 Header로 PNG 또는 JPEG Signature를 판별한다.
7. 판별 결과가 전달 MIME Type과 원본 확장자에 모두 일치하는지 확인한다. `image/jpg`와 `.jpeg`는 JPEG 별칭으로 정규화한다.
8. 검증된 형식으로 UUID 파일명을 만들고 정규화된 최종 경로가 Root 내부인지 확인한다.
9. 경로 구성요소의 Symbolic Link를 따르지 않으며 Root 외부를 가리키는 경로를 거부한다.
10. 입력 Stream이 정상적으로 닫힌 것을 확인한 뒤에만 임시 파일을 최종 위치로 이동한다.
11. `ATOMIC_MOVE`를 우선하고 지원하지 않으면 덮어쓰기 없는 일반 Move로 대체한다. UUID 충돌은 제한된 횟수만 재시도한다.
12. 모든 실패에서 임시 파일과 Stream을 정리한다.

## 오류 계약

`ImageStorageErrorCode`는 다음 안전한 오류만 노출한다.

| Enum | HTTP Status | Code |
| --- | --- | --- |
| `EMPTY_IMAGE_FILE` | 400 | `STORAGE_400_001` |
| `UNSUPPORTED_IMAGE_FORMAT` | 400 | `STORAGE_400_002` |
| `INVALID_IMAGE_FILE` | 400 | `STORAGE_400_003` |
| `INVALID_STORAGE_PATH` | 400 | `STORAGE_400_004` |
| `IMAGE_STORAGE_CONFLICT` | 409 | `STORAGE_409_001` |
| `IMAGE_FILE_TOO_LARGE` | 413 | `STORAGE_413_001` |
| `IMAGE_STORAGE_FAILED` | 500 | `STORAGE_500_001` |

IOException 원문, 절대 경로, 원본 파일명과 이미지 내용은 응답이나 로그에 포함하지 않는다.

## 검증 전략

`@TempDir`과 고정 `Clock`을 사용해 PNG/JPEG 정상 저장, 상대 Key, UUID 파일명, Byte·크기 일치, Root 생성, 중복 방지, 빈 파일, 크기 초과, 선언 크기 불일치, MIME·확장자 위조, 임의 Binary, 경로 문자열 무해화, Symbolic Link 이탈 방지, 임시 파일 정리와 Stream 종료를 검증한다. 설정 Binding과 Spring Context 등록도 별도로 검증하고 전체 H2·Testcontainers·Flyway 회귀 테스트, Spotless와 Javadoc을 실행한다.
