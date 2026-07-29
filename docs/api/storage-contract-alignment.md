# 파일·스트로크 저장소 계약 정합성 문서 (as-built)

> Jira: 실행 이슈 `S15P11B209-661` ~ `673` (§8 조치 목록에 항목별 매핑) · 스프린트 2차 MVP
> 범위: 파일 저장·조회·삭제 계약(그림·음성), 스트로크 배치 저장 계약, AI 내부 이미지 접근
> 기준 명세: `API_명세서_최종.md` §2.2 · §3.8 · §10.5 · §10.6 · §10.7 · §16 · §18 · §19.2 · §22.1 · §24
> 기준 구현: `develop` @ `7c9b31c` (2026-07-28 검증)
> 관련 설계: `docs/database/저장소-아키텍처.md`(368) · `docs/인프라/파일-수명주기-정책.md`(622)

명세서와 백엔드 구현이 갈라진 지점을 항목별로 확정하고, **각 항목을 명세 쪽으로 맞출지 코드 쪽으로 맞출지**를 정한다. 프론트엔드·백엔드·AI·인프라가 이 문서를 파일 관련 계약의 단일 기준으로 사용한다.

## 0. 이 문서가 확정한 것

명세서는 파일 접근을 **만료 시간이 있는 signed URL**(`https://signed.example.com/assets/501`)로 서술한다. 구현은 **JWT 프록시 스트리밍**이다. 이 차이가 URL 형태·만료 필드·프론트 렌더링 방식까지 연쇄적으로 갈라지게 했으므로 아래로 통일한다.

1. **파일 조회는 presigned URL이 아니라 인증 프록시 스트리밍이다.** 명세 §3.8의 "조회용 URL에는 만료 시간을 둔다"는 as-built로 대체한다.
   `reason`: presigned URL은 "URL 소지 = 접근"인 bearer 토큰이다. 아동 그림 URL이 로그·히스토리·공유로 새면 만료 전까지 누구나 열람할 수 있어 보호자-아동 관계 검증과 전문가 열람 범위 인가가 **요청별로 우회**된다(가드레일 9절). MinIO를 외부에 노출해야 하므로 "외부 노출면 80/443" 원칙도 깨진다. 결정 근거 전문은 저장소-아키텍처 §3.
2. **파일 URL 필드는 절대 URL이 아니라 상대 API 경로다.** 값은 `"/api/v1/drawing-assets/{drawingAssetId}/file"` 형태이며, 클라이언트가 API Base URL과 결합하고 `Authorization` Header를 붙여 호출한다.
   `reason`: 서버가 절대 URL을 만들면 환경별 도메인(로컬·EC2·k3s)이 응답에 박히고, 프론트가 인증 없이 열 수 있는 URL로 오인한다.
3. **`expiresAt`은 제거하지 않고 항상 `null`로 응답한다.** 만료 개념이 없어졌지만 필드는 유지한다.
   `reason`: 필드 제거는 프론트 파서 변경을 강제한다. 만료 정책이 없다는 사실을 `null`로 표현하는 편이 계약 호환을 깨지 않는다.
4. **`GET /api/v1/drawing-assets/{drawingAssetId}/file`을 공개 계약에 편입한다.** 이 엔드포인트는 명세서 엔드포인트 표에 없다.
   `reason`: 프론트가 실제로 호출해야 하는 API가 명세서에 없으면 계약이 아니라 구현 지식이 된다.
5. **삭제된 활동의 파일은 객체가 남아 있어도 접근이 차단된다.** 명세 §24의 "활동 삭제 후 URL 접근 불가"는 충족된다.
   `reason`: 접근 경로가 프록시뿐이고 매 요청 `session_status <> 'DELETED' and deleted_at is null and child.profile_status = 'ACTIVE'`를 검증한다(`GuardianResourceAccessRepository.java:55-75`). presigned 방식이면 발급된 URL이 삭제 후에도 만료까지 살아 있었을 것이다 — 1번 결정의 부수 이득이다.
6. **스트로크 저장소는 명세 계약의 대상이 아니다.** 명세서에 "MongoDB"는 0회 등장하며, 요구는 §10.5 배치 API 계약과 §22.1 `stroke_batches(drawing_session_id, batch_sequence)` unique뿐이다. 현재 MySQL 구현으로 이 계약은 충족된다. Mongo 전환(365)은 계약 변경이 아니라 내부 저장소 교체다.
7. **아래 5건은 명세 미이행이며 코드 쪽을 맞춘다** — 이미지 픽셀 크기 검증, EXIF 제거, 기록·리포트의 파일 URL 부재, 스트로크 배치 1 MiB 상한, 삭제 큐 워커. §8 조치 목록에서 주체와 우선순위를 지정한다.

---

## 1. 저장소 매핑 as-built

| 데이터 | 명세 요구 | 저장소 (mode=s3) | 프리픽스 | 판정 |
| --- | --- | --- | --- | --- |
| 그림 원본·미리보기 | §2.2 "최종 검증, S3 저장, 접근 URL 발급" | MinIO 버킷 `dodam` | `images/` | 일치 |
| 아동 음성 답변 | §12 음성 업로드 | MinIO `dodam` | `audio/` | 일치 |
| TTS 캐시 | §13 `audioUrl` | MinIO `dodam` | `tts-cache/` | 일치 — 30일 ILM·백업 제외 정책 적용 |
| PDF 리포트 | REPORT-04·05 | 미구현 | (`reports/` 미사용) | 범위 외 — 엔드포인트 자체가 없다 |
| 전문가 자격 증빙 | §17 | 미구현 | (`evidences/` 미사용) | 범위 외 |
| 스트로크 배치 | §10.5 · §22.1 | MySQL `stroke_batches`·`stroke_events`·`stroke_event_points` | — | 일치(저장소 중립) |
| 대화 원문 | §11 | MySQL `conversation_messages` | — | 일치 — Mongo 이중 저장 금지 원칙 준수 |

`mode=local`(기본값)에서는 그림·음성이 컨테이너 로컬 볼륨에 저장된다. 저장 Key 구조가 두 모드에서 동일하므로 DB 값은 모드와 무관하다(`S3ImageStorage.java:138-140`).

## 2. 파일 규칙 정합성 (§3.8)

| 항목 | 명세 | 구현 | 판정 |
| --- | --- | --- | --- |
| 그림 형식 | JPEG, PNG, **WEBP** | PNG, JPEG (`LocalImageStorage.java:467-469`) | **결정 필요** — §9-1 |
| 그림 크기 | 10 MiB | 10 MiB (`app.storage.image.max-size`) | 일치 |
| 그림 픽셀 | 최소 320×320, 최대 8192×8192 | `> 0`만 검증 (`LocalImageStorage.java:370-387`) | **BE 조치** |
| `IMAGE_DIMENSION_INVALID` | DRAWING-08 오류 목록 | 코드 전체에 미구현 | **BE 조치** |
| 음성 형식 | WEBM, M4A, WAV, MP3 | 동일 (`AudioFormat.java:10-13`) | 일치 |
| 음성 크기·길이 | 20 MiB, 최대 60초 | 20 MiB, 60초 (`LocalAudioStorage.java:36`) | 일치 |
| MIME + signature 교차 검증 | 필수 | 선언 MIME·확장자·실제 signature 3중 검증 | 일치 |
| EXIF 위치정보 제거 | 프로필 필수, §24 "서버에서 재검증" | 미구현(코드 내 EXIF 처리 0건) | **BE 조치** — 가드레일 |
| storageKey 클라이언트 지정 | 금지 | 서버가 날짜/UUID로 생성, 원본 파일명 미사용 | 일치 |
| 영구 공개 URL 미응답 | 필수 | 프록시 경로만 응답, storageKey·절대경로 미노출 | 일치 |
| 프로필 이미지 5 MiB | USER-02·03 | `profileImageFileId`를 받기만 하고 미처리 | 범위 외 — 업로드 API 자체가 없다 |

픽셀 검증 부재의 실제 영향: 1×1 PNG나 20000×20000 이미지가 업로드를 통과하며, `drawing_assets.width_px/height_px`에 그대로 기록된다. 객체 탐지·분석이 이 값을 좌표 기준으로 사용하므로(§10.6) 분석 입력이 오염된다.

### 2-1. 저장소 모드에 따라 갈라져야 하는 경계 전수 점검 (2026-07-29 추가)

이 문서의 최초 점검은 `ImageStorage`·`AudioStorage`만 봤고 **별 인터페이스로 존재하는 읽기 경계를 놓쳤다.** 그 결과 `STORAGE_MODE=s3`에서 STT가 전부 실패했다(S15P11B209-723 — 업로드는 201인데 STT만 즉시 FAILED, AI 서버에 요청 0건 도달).

| 경계 | 모드 분기 | 상태 |
| --- | --- | --- |
| `ImageStorage` | `ImageStorageConfig`(local) / `S3StorageConfig`(s3) | ✅ 정상 |
| `AudioStorage` | `AudioStorageConfig`(local) / `S3StorageConfig`(s3) | ✅ 정상 |
| `AudioStorage("ttsAudioStorage")` | s3 전용 프리픽스 분리 | ✅ 정상(S15P11B209-668) |
| **`StoredAudioReader`** (내부 STT 전용 읽기) | **분기 없음 — `@Component`로 로컬 구현만 등록** | ❌ **723에서 수정** |

**점검 규칙**: 저장 위치를 아는 경계를 새로 만들 때는 `@Component`로 무조건 등록하지 않는다. 모드별 Config에 등록하거나 `@ConditionalOnProperty(prefix = "app.storage", name = "mode", ...)`를 붙인다. 무조건 등록은 s3 모드에서 **조용히 로컬을 읽어** 쓰기는 성공하고 읽기만 실패하는, 원인 추적이 어려운 형태로 나타난다.

## 3. 파일 조회 계약 (as-built · 명세 §3.8 대체)

### 3.1 엔드포인트

```http
GET /api/v1/drawing-assets/{drawingAssetId}/file
Authorization: Bearer {accessToken}
```

- 역할: 연결 보호자. 매 요청 그림 활동 세션 소유권을 검증한 뒤에만 Storage를 읽는다(`DrawingAssetFileQueryService.java:56-64`).
- 응답: `200`, 원본 `Content-Type`, `Content-Length`, **`Cache-Control: private, no-store`**, 본문은 `StreamingResponseBody`(메모리 버퍼링 없음).
- 오류: `401` Access Token 누락·검증 실패 / `404` 파일 없음 또는 접근 불가 활동. 존재 여부와 권한 없음을 구분하지 않는다.
- `Idempotency-Key` 미사용. 만료·재발급 개념 없음.

### 3.2 URL 필드 현황

| 응답 필드 | API | 현재 값 | 판정 |
| --- | --- | --- | --- |
| `previewUrl` | DRAWING-06/07 임시저장 조회 | `/api/v1/drawing-assets/{id}/file` | 일치 |
| `previewUrl` | 활성 세션 조회 | 동일 | 일치 |
| `thumbnailUrl` | ACTIVITY 기록 목록 (§16) | **항상 `null`** | **BE 조치** |
| `finalImageUrl`·`thumbnailUrl` | REPORT-02 리포트 상세 (§18) | **항상 `null`** | **BE 조치** |

기록 목록과 리포트 상세는 프록시 URL Factory를 쓰지 않고 `drawing_assets.file_url` 컬럼을 그대로 반환한다(`DrawingSessionHistoryQueryService.java:173`, `ReportDetailQueryService.java:186-188`). 이 컬럼은 **어디에서도 값이 설정되지 않는다** — 생성 시 `null`로만 초기화된다(`DrawingAsset.java:97`). 추가로 `THUMBNAIL` 자산을 만드는 코드가 없어서 조회 대상 자체가 존재하지 않는다.

결과: 보호자는 임시저장 복구 화면에서는 그림을 볼 수 있지만 **기록 목록과 리포트에서는 볼 수 없다.** 저장소-아키텍처 §0이 지목한 "프론트가 그린 그림을 다시 볼 수 없음" 문제가 Draft 경로에서만 해소된 상태다.

### 3.3 클라이언트 규칙

- 상대 경로를 API Base URL과 결합하고 `Authorization` Header를 반드시 붙인다.
- **인증 Header를 붙일 수 없는 렌더링 API에 이 URL을 그대로 넘기지 않는다.** Flutter `Image.network`, 웹 `<img src>`가 해당한다.
- 앱 현황: Draft 미리보기는 규칙을 지킨다(`remote_drawing_repository.dart:262-278` — 절대 URL·query를 거부하고 Dio 경로로 변환). 반면 기록 목록 썸네일은 `Image.network(url)`을 직접 사용하므로(`history_screens.dart:627-633`) 3.2의 `null` 문제가 해결되는 순간 **인증 없이 요청해 401로 실패한다.** → **FE 조치**
- Mock fixture는 절대 URL(`https://storage.i15b209.example/...`)을 쓰고 있어 실 API 형태와 다르다. 전환 시 함께 교정한다.

## 4. AI 내부 이미지 접근 (§19.2)

명세와 구현이 일치한다. 변경 없음.

- BE가 분석 요청 직전에 발급하는 **1회용 Redis 토큰** URL: `http://backend:8080/internal/v1/ai-images/{token}` (`RedisAiImageAccessTokenStore.consume`)
- 기본 TTL **60초** (`AiImageAccessProperties.java:20`), Docker 내부망 전용
- AI 서버는 URL·토큰·이미지 bytes를 로그에 남기지 않는다(`ai/internal_contracts.py:320`의 `repr=False`)

문서 정정 필요: 저장소-아키텍처 §4는 "AI가 `dodam-ai-ro` 자격증명으로 MinIO를 직접 GET" 방식을 채택했다고 기록하지만, 구현은 위의 BE 프록시 토큰 방식이다. `MINIO_AI_USER`는 `minio-init` 프로비저닝에만 주입되고 AI 서비스는 사용하지 않으므로 **현재 ai-ro는 유휴 자격증명**이다. 저장소-아키텍처 §4를 as-built로 정정하고, ai-ro를 유지할지 회수할지 결정한다(§9-4).

## 5. 스트로크 배치 저장 계약 (§10.5)

| 명세 규칙 | 구현 | 판정 |
| --- | --- | --- |
| `(drawing_session_id, batch_sequence)` unique | `uk_stroke_batches_session_sequence` (`StrokeBatch.java:22-26`) | 일치 |
| 같은 순번 + 같은 checksum → 기존 결과 반환 | 구현됨 (`StrokeBatchService.java:86-108`) | 일치 |
| 같은 순번 + 다른 payload → `409 STROKE_BATCH_CONFLICT` | 구현됨 (`:102-103`, DB 제약 위반도 같은 코드로 변환 `:113`) | 일치 |
| 이벤트 최대 500개 | `@Size(max = 500)` (`SaveStrokeBatchRequest.java:28`) | 일치 |
| **압축 전 JSON 최대 1 MiB** | 전용 HTTP Filter가 역직렬화 전에 실제 Body Byte 제한, Service가 표준 JSON 재검증 | 일치 — 초과 시 `413 DRAWING_413_001` |
| 배치당 좌표 행 안전 상한 | 최대 20,000개 | 초과 시 `413 DRAWING_413_002`; 앱은 이벤트 배치를 분할 재전송 |
| `x`,`y` 0~1 정규화 좌표 | `DECIMAL(8,6)` 컬럼 | 일치 |
| 필압 미지원은 `null` | nullable `DECIMAL(6,5)` | 일치 |

저장 구조는 좌표 1개 = 1행(`StrokeEventPoint.java:31-41`)이다. 저장소-아키텍처 §5는 이 구조를 "**BE 코드 미구현이므로 스키마 v1.3에서 제거**"할 대상으로 기록했지만, 그 사이 MySQL로 구현되어 운영에 들어갔다. 365 전환은 이제 스키마 제거가 아니라 **기존 데이터 이관**을 포함한다 — 저장소-아키텍처 §5·§6의 전제와 공수 추정을 정정해야 한다.

## 6. 삭제·수명주기 정합성 (§24)

| 명세 요구 | 구현 | 판정 |
| --- | --- | --- |
| DB soft delete | 구현됨 (아동·세션·Draft) | 일치 |
| 삭제 후 URL 접근 불가 | 프록시 인가로 차단 (§0-5) | 일치 |
| **S3 삭제 작업** | `storage_deletion_jobs`에 **적재만** 하고 소비하는 워커가 없다 | **BE 조치(373)** |
| 전문가 공유 해제 | 범위 외 | — |

삭제 큐 INSERT는 3곳(`ChildDeletionRepository.java:97`, `DrawingSessionDeletionRepository.java:34`, `DrawingDraftDeletionRepository.java:37`)에 있고, `@Scheduled` 워커는 STT 복구용 하나뿐이다. **잠정 계약**: 삭제 API는 "접근 차단 + 삭제 예약"까지만 보장하고, 객체 실삭제 시점은 보장하지 않는다. 373 완료 시 이 절을 갱신한다.

즉시 삭제 보상 경로는 별개로 동작한다 — 업로드 트랜잭션 실패 시 `imageStorage.delete()`를 직접 호출한다(`DrawingDraftService.java:196`, `DrawingSnapshotService.java:146`).

## 7. 환경변수 계약 (드리프트 정정)

`application.yml`이 읽는 키와 `.env.example`이 제시하는 키가 다르다. 예시대로 채우고 `STORAGE_MODE=s3`로 올리면 access key가 빈 값이 되어 `S3StorageProperties` 생성자에서 `IllegalArgumentException`으로 **기동 실패**한다.

| application.yml이 읽는 키 | `.env.example` | 조치 |
| --- | --- | --- |
| `STORAGE_MODE` | 없음 | 추가 (`local`\|`s3`, 기본 `local`) |
| `S3_ENDPOINT` | 없음 | 추가 (`http://minio:9000`) |
| `MINIO_BE_USER` | `S3_ACCESS_KEY` | 키 이름 교정 |
| `MINIO_BE_PASSWORD` | `S3_SECRET_KEY` | 키 이름 교정 |
| `S3_BUCKET`·`S3_REGION` | 있음 | 유지 |

부수 항목: nginx `client_max_body_size 20m`이 음성 상한 20 MiB와 같아서, 상한 근처 파일은 multipart 오버헤드 때문에 명세 계약인 앱 `413`(JSON 오류 본문) 대신 nginx 기본 HTML 413을 받는다. nginx 상한을 22m 정도로 올려 앱이 판정하게 한다.

## 8. 조치 목록

| # | 항목 | Jira | 담당 | 우선순위 | 근거 절 |
| --- | --- | --- | --- | --- | --- |
| 1 | EXIF 위치정보 제거 | `661` | 강병구 | **Highest(가드레일)** | §2 |
| 2 | 이미지 픽셀 하한·상한 검증 + `IMAGE_DIMENSION_INVALID` | `663` | 강병구 | High | §2 |
| 3 | 기록 목록·리포트 상세의 파일 URL을 프록시 URL Factory로 통일 + `THUMBNAIL` 자산 생성 | `665` | 강병구 | High(기능 부재) | §3.2 |
| 4 | 인증 이미지 로딩 위젯 + 기록 목록 썸네일 적용 | `666` | 장우창 | High(3번과 동시 배포) | §3.3 |
| 4b | 리포트 상세 그림 표시 + mock 절대 URL 정리 | `667` | 안윤주 | High(666 선행) | §3.2·§3.3 |
| 5 | `.env.example` 키 정정 | `662` | 강병구 | High(기동 실패) | §7 |
| 6 | 삭제 큐 워커 | `373`(기존) | 이강륜 | 3차 | §6 |
| 7 | TTS를 `tts-cache/` 프리픽스로 분리 | `668` | 강병구 | **완료** — 생성·질문 재생 저장소 분리 | §1 |
| 8 | 명세서 §3.8·§10.6·§16·§18의 URL 문구·예시를 프록시 방식으로 갱신 + 파일 조회 엔드포인트 등재 | `672` | 이강륜 | Medium | §0-1·§0-4 |
| 9 | 저장소-아키텍처 §4(AI 접근)·§5(스트로크 스키마 제거 전제) 정정 | `671` | 이강륜 | Medium | §4·§5 |
| 10 | nginx 업로드 상한 조정 | `670` | 이강륜 | Low | §7 |
| 11 | 스트로크 배치 1 MiB·좌표 20,000개 상한 | `669` | 강병구 | **완료** | §5 |
| 12 | MinIO ai-ro 자격증명 회수 판단 | `673` | 이강륜 | Low(372 선행) | §4 |

전 항목 스프린트 `2차 MVP`(2026-07-27 ~ 07-30), 합계 26 SP. 의존: `665 relates 666`(동시 배포) · `666 blocks 667` · `665 blocks 667` · `668 blocks 373` · `372 blocks 673` · `671 relates 365`.

## 9. 결정 필요

1. **WEBP** — 명세를 JPEG/PNG로 좁힐지, BE가 WEBP를 추가할지. 현재 앱은 캔버스 스냅샷을 `image/png`로만 업로드한다(`remote_drawing_repository.dart:39`). 종이 그림 촬영 경로에서 기기 카메라가 WEBP를 낼 가능성만 확인하면 결정할 수 있다. 권고: **명세를 좁힌다** — 쓰이지 않는 형식의 signature 검증을 유지하는 것은 공격면만 늘린다.
2. **스트로크 1 MiB 상한** — 명세 문구대로 BE가 실제 HTTP Body를 역직렬화 전에 검사한다. 이벤트 500개 상한만으로는 좌표 행 폭증을 막지 못하므로 배치당 좌표를 20,000개로 함께 제한한다. 둘 중 어느 상한을 초과했는지 별도 오류 코드로 반환해 앱이 배치를 나눠 재전송할 수 있게 한다.

## 10. TTS 기존 객체 이관 정책

`S15P11B209-668` 배포 전 `audio/`에 생성된 TTS 객체는 `tts-cache/`로 이관하지 않는다. TTS는 질문 원문에서 재생성할 수 있는 캐시이며, DB의 기존 성공 상태가 가리키는 객체를 일괄 이동하면 배포 중 재생 경로가 갈리는 위험이 더 크다. 질문 재생은 먼저 `tts-cache/`를 조회하고 없으면 기존 `audio/`를 한시적으로 조회해 배포 전 캐시도 재생한다. 신규 TTS는 항상 `tts-cache/`에 생성한다. 아동 음성 답변은 보존 대상이므로 계속 `audio/`에 유지한다.
3. **명세서 갱신 주체** — 8번 조치를 이 문서로 갈음할지(명세서는 그대로 두고 as-built 문서가 우선), 명세서 본문을 고칠지. `child-delete-contract.md`는 "명세 보강은 문서 담당자 몫"으로 남기는 선례를 만들었다.
4. **ai-ro 자격증명** — BE 프록시 방식이 확정이면 `dodam-ai-ro`를 회수할지, 372(AI 이미지 접근) 재검토 여지를 남겨 유지할지.
5. **THUMBNAIL 생성 시점** — 서버가 FINAL 저장 시 리사이즈로 만들지, 클라이언트가 함께 업로드할지(3번 조치의 선행 결정).

## 10. 재검증 방법

```bash
# MongoDB 부재 확인 (명세서·구현 양쪽)
grep -c -i mongo docs/api/API_명세서_최종.md            # 0
grep -rn -i mongo backend/build.gradle backend/src/main # 0건

# 파일 URL 필드가 실제로 채워지는지
grep -rn "fileUrl" backend/src/main/java --include="*.java" | grep -v test
# DrawingAsset.java:97 의 null 초기화 외에 대입이 없으면 §3.2 문제 유효

# EXIF·픽셀 검증 구현 여부
grep -rni exif backend/src ai                            # 0건이면 미구현
grep -rn "IMAGE_DIMENSION_INVALID" backend/src/main      # 0건이면 미구현

# 삭제 큐 소비자 존재 여부
grep -rn "@Scheduled" backend/src/main/java --include="*.java"
```
