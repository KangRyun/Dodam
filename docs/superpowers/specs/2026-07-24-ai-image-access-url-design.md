# AI 그림 분석용 일회성 이미지 URL 설계

## 1. 목적

`POST /internal/v1/analyses`를 호출하는 Spring Boot가 AI 서버에서 한 번만 읽을 수 있는
짧은 만료의 이미지 URL을 발급한다. 현재 `LocalImageStorage`를 유지하면서 실제 HTTP 분석
경로를 열고, 이후 S15P11B209-370에서 MinIO/S3로 전환할 때 AI 요청 계약을 변경하지 않는다.

## 2. 현재 상태와 충돌

- 정본 `docs/api/API_명세서_최종.md` §19.3과 실제 `ai/internal_contracts.py`의
  `AnalysisRequest`는 `drawing.signedUrl`을 요구한다.
- AI 서버는 URL을 HTTP GET하고 최대 크기와 SHA-256 checksum을 검증한다.
- `DrawingAnalysisImageUrlProvider`는 존재하지만 실제 구현이 없어서 HTTP mode 요청이
  네트워크 호출 전에 실패한다.
- `ImageStorage`는 `store`와 `delete`만 제공하므로 저장된 파일을 안전하게 읽을 수 없다.
- S15P11B209-372의 `storageKey + MinIO 직접 GET` 설명은 현재 정본 및 배포된 AI 코드와
  충돌한다. S15P11B209-370도 아직 완료되지 않아 MinIO를 전제로 구현할 수 없다.

## 3. 대안

### 3.1 Redis 1회성 토큰 URL

무작위 토큰을 발급하고 Redis에는 토큰의 SHA-256 digest와 `storageKey`를 짧은 TTL로
저장한다. 이미지 조회 시 Lua Script로 값을 읽고 Key를 삭제해 한 번만 소비한다.

- 장점: 재사용 차단, 즉시 만료, 현재 로컬 저장소 사용 가능
- 단점: 이미지 다운로드 시 Redis 가용성이 필요

### 3.2 HMAC 서명 URL

`storageKey`와 만료 시각을 HMAC으로 서명해 상태 없이 검증한다.

- 장점: Redis가 필요하지 않음
- 단점: 만료 전 재사용을 차단할 수 없고 URL에 저장소 식별 정보가 포함될 가능성이 큼

### 3.3 MinIO/S3 Presigned URL

저장소 SDK로 Presigned URL을 발급한다.

- 장점: Backend가 이미지 Byte를 중계하지 않음
- 단점: S15P11B209-370과 MinIO 운영 구성이 선행되어야 하므로 현재 동작하지 않음

현재 아동 그림의 민감도, 로컬 저장소 상태와 구현 독립성을 고려해 **3.1 Redis 1회성 토큰
URL**을 채택한다.

## 4. 구성 요소

### 4.1 이미지 읽기 경계

`ImageStorage`에 `read(String storageKey)`를 추가한다. 반환값은 읽기 Stream, 검증된 MIME
Type과 실제 파일 크기를 포함한다. 호출자가 Stream을 닫으며, 구현체는 절대 경로를 반환하지
않는다.

`LocalImageStorage`는 저장·삭제와 같은 경로 검증을 재사용해 다음을 차단한다.

- 절대 경로와 `.`·`..` Segment
- Storage Root 밖으로 나가는 경로
- 중간 디렉터리 또는 대상 파일의 Symbolic Link
- 일반 파일이 아닌 대상

존재하지 않는 파일은 내부 이미지 API에서 외부와 구분되지 않는 `404`로 변환한다.

### 4.2 일회성 토큰 저장소

`AiImageAccessTokenStore`는 다음 두 작업만 제공한다.

- `issue(storageKey, ttl)`: 256-bit 무작위 토큰 발급
- `consume(token)`: Redis Lua Script의 `GET`과 `DEL`을 한 명령으로 실행

Redis Key에는 원문 토큰 대신 SHA-256 digest를 사용하고 `ai:image-access:` Prefix를 붙인다.
값에는 `storageKey`만 저장한다. 기본 TTL은 60초이며 양수만 허용한다. 잘못된 형식, 만료,
재사용, Redis에 없는 토큰은 모두 동일하게 조회 실패로 처리한다.

### 4.3 내부 이미지 API

`GET /internal/v1/ai-images/{token}`은 외부 공개 API가 아니다. Nginx에는 `/internal/**`
Route를 추가하지 않으며 같은 Docker Network의 AI 컨테이너만
`http://backend:8080`으로 접근한다.

처리 순서는 다음과 같다.

1. 토큰을 원자적으로 소비한다.
2. 연결된 `storageKey`로 `ImageStorage.read`를 호출한다.
3. `Content-Type`, `Content-Length`, `Cache-Control: no-store`와 이미지 Stream을 반환한다.

토큰과 URL, `storageKey`, 절대 경로, 이미지 Byte는 로그에 기록하지 않는다. 유효하지 않은
토큰과 존재하지 않는 파일은 모두 `404`로 응답한다. Redis 장애와 파일 시스템 장애는 안전한
공통 `5xx` 오류로 응답하며 내부 예외 상세를 노출하지 않는다.

### 4.4 AI Client 연결

`RedisDrawingAnalysisImageUrlProvider`는 토큰을 발급하고 다음 형식의 절대 URL을 만든다.

```text
{internal-base-url}/internal/v1/ai-images/{token}
```

기본 내부 Base URL은 배포 Docker DNS 기준 `http://backend:8080`이다. 로컬·테스트 환경은
환경 변수로 덮어쓴다. HTTP 분석 mode에서 이 Provider가 등록되므로 기존
`UnavailableDrawingAnalysisImageUrlProvider`는 선택되지 않는다.

## 5. 설정

`app.ai.image-access` 아래에 다음 설정을 추가한다.

| 설정 | 환경 변수 | 기본값 |
| --- | --- | --- |
| 내부 Base URL | `AI_IMAGE_ACCESS_BASE_URL` | `http://backend:8080` |
| 토큰 TTL | `AI_IMAGE_ACCESS_TOKEN_TTL` | `60s` |

실제 HTTP 분석 전환에는 기존 설정도 필요하다.

```text
AI_DRAWING_ANALYSIS_MODE=http
AI_DRAWING_ANALYSIS_BASE_URL=http://ai:8000
AI_DRAWING_ANALYSIS_ENDPOINT_PATH=/internal/v1/analyses
AI_INTERNAL_TOKEN=<BE와 AI가 공유하는 Secret>
```

Secret 값은 저장소, 문서와 로그에 기록하지 않는다.

## 6. 오류 처리

- 토큰 형식 오류·만료·재사용·없는 파일: `404`
- Redis 저장 또는 소비 실패: `503`
- 이미지 저장소 읽기 실패: `500`
- 안전하지 않은 저장 경로: 외부 응답에서는 파일 존재 여부를 숨기기 위해 `404`

이미지 조회는 재시도 가능한 공개 다운로드가 아니므로 `Range` 요청과 캐싱은 지원하지 않는다.

## 7. 테스트

- `LocalImageStorage` 정상 읽기, 없는 파일, 경로 이동, Symbolic Link 차단
- Redis 토큰 발급 TTL, digest Key, 원자적 1회 소비, 만료·재사용
- 내부 Controller 정상 Stream과 Header, 잘못된 토큰 및 저장소 오류
- `DrawingAnalysisImageUrlProvider`가 올바른 내부 URL을 만들고 원문 `storageKey`를 노출하지 않음
- HTTP AI Client 요청에 발급 URL이 포함되는지 확인
- Access Token Filter가 `/internal/**`에 적용되지 않는 기존 등록 범위 회귀 확인
- 전체 `test`, `spotlessCheck`, `javadoc`

## 8. 제외 범위와 후속

- MinIO/S3 구현과 기존 파일 이관은 S15P11B209-370에서 수행한다.
- AI 서버 계약과 `_fetch_drawing` 구현은 변경하지 않는다.
- S15P11B209-372는 현재 signed URL 정본에 맞게 설명과 의존 관계를 갱신해야 한다.
- 운영 HTTP mode 전환과 실제 배포 E2E는 AI·Redis·Docker Network가 준비된 환경에서
  별도로 검증한다.
