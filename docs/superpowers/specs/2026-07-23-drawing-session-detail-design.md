# 그림 활동 상세 조회 설계

## 1. 목적

`GET /api/v1/drawing-sessions/{drawingSessionId}`로 인증된 보호자가 접근할 수 있는 그림 활동의 현재 상태와 연관 리소스 요약을 조회한다.

조회는 화면 복구와 활동 내역 진입에 필요한 식별자와 Metadata만 제공한다. 세션 상태를 변경하거나 AI 분석, 파일 다운로드, 리포트 생성을 실행하지 않는다.

## 2. 범위

### 포함

- 연결 보호자의 그림 활동 접근 권한 검증
- 삭제되지 않은 그림 활동, 아동, 그림 유형 조회
- 선택 감정 목록 조회
- 최신 그림 Asset과 최신 분석 요약 조회
- 최신 대화 및 최신 리포트 식별자 조회
- 복구 가능한 DRAFT 존재 여부 계산
- 공통 성공·오류 응답과 Swagger 문서
- Service, Repository, Controller 테스트

### 제외

- 공유 전문가의 조회 권한
- 전문가 공유·승인 정책과 상담 도메인 구현
- 이미지 파일 다운로드 URL 생성
- 분석 또는 리포트 생성·재시도
- 세션 상태 변경
- DB Schema 및 Flyway Migration 변경

최신 API 명세는 공유 전문가의 조회도 허용하지만, 현재 Repository에는 보호자 접근 권한만 구현되어 있다. 전문가 조회는 공유 승인 인프라가 마련되는 별도 이슈에서 추가한다.

## 3. API 계약

```http
GET /api/v1/drawing-sessions/{drawingSessionId}
Authorization: Bearer <access-token>
```

성공 시 기존 `ApiResponse<DrawingSessionDetailResponse>` 형식으로 HTTP 200을 반환한다.

응답은 다음 정보를 포함한다.

- `drawingSessionId`
- `child`
- `drawingType`
- `inputMethod`
- `title`
- `selectedEmotions`
- `sessionStatus`
- `currentStage`
- `latestAsset`
- `latestAnalysis`
- `conversationId`
- `reportId`
- `startedAt`
- `completedAt`
- `recoverableDraft`

연관 데이터가 없으면 객체와 식별자는 `null`, 감정 목록은 빈 배열로 반환한다. 시각은 UTC `Instant` 문자열로 직렬화한다.

## 4. 접근 권한과 오류

1. `CurrentAuthenticatedUserResolver`로 현재 사용자 ID를 확인한다.
2. `GuardianResourceAccessValidator.requireDrawingSessionAccess`로 연결 보호자 권한을 검증한다.
3. 삭제되지 않은 세션을 조회한다.

접근 권한이 없거나 세션이 존재하지 않거나 삭제된 경우 모두 기존 `DRAWING_SESSION_NOT_FOUND` 오류를 사용한다. 이 방식으로 자원 존재 여부를 노출하지 않는다.

양수가 아닌 `drawingSessionId`는 Bean Validation으로 HTTP 400 처리한다.

## 5. 조회와 조립

`DrawingSessionQueryService`가 읽기 전용 Transaction에서 다음 결과를 조합한다.

1. 그림 활동과 아동·그림 유형
2. 선택 감정 목록
3. 가장 최근 생성된 그림 Asset
4. 가장 최근 요청된 분석
5. 가장 최근 생성된 대화 세션 ID
6. 가장 최근 생성된 리포트 ID
7. 복구 가능한 최신 DRAFT 존재 여부

Repository마다 하나의 조회 책임을 유지한다. 여러 1:N 관계를 한 번에 Join하는 대형 Projection은 중복 행과 복잡한 집계를 피하기 위해 사용하지 않는다.

### 최신 데이터 선택 기준

- Asset: `createdAt` 내림차순, 동률이면 `id` 내림차순
- 분석: `requestedAt` 내림차순, 동률이면 `id` 내림차순
- 대화: `startedAt` 내림차순, 동률이면 `id` 내림차순
- 리포트: `createdAt` 내림차순, 동률이면 `id` 내림차순

Soft Delete 대상은 제외한다. 현재 Soft Delete 컬럼이 없는 분석·대화·리포트는 세션이 삭제되지 않았다는 전제 아래 조회한다.

### recoverableDraft

`recoverableDraft`는 해당 세션에 DRAFT Asset이 하나 이상 존재할 때 `true`다. 상세 API에서는 파일 내용이나 내부 `storageKey`를 노출하지 않는다. 실제 복구 Metadata는 기존 `GET /api/v1/drawing-sessions/{drawingSessionId}/draft`가 담당한다.

## 6. 응답 요약 객체

응답 DTO는 Entity를 직접 노출하지 않고 필요한 필드만 제공한다.

- `child`: 아동 식별자와 화면 표시에 필요한 최소 프로필 요약
- `drawingType`: 기존 그림 유형 요약 구조 재사용
- `latestAsset`: Asset 식별자, 유형, 버전, MIME Type, 파일 크기, 촬영·생성 시각
- `latestAnalysis`: 분석 식별자, 분석 범위, 작업 유형, 상태, 요청·완료 시각

절대 파일 경로, 내부 `storageKey`, 이미지 Byte/Base64, 아동 생년월일은 반환하지 않는다.

## 7. 구성 요소 변경

- `DrawingSessionController`: Path 기반 상세 조회 Endpoint 추가
- `DrawingSessionQueryService`: 권한 검증과 조회 결과 조립
- `DrawingSessionRepository`: 상세 조회용 Fetch Query
- `DrawingSessionEmotionRepository`: 세션별 감정 코드 조회
- `DrawingAssetRepository`: 세션별 최신 Asset 및 DRAFT 존재 조회
- `DrawingAnalysisRepository`: 세션별 최신 분석 조회
- `ConversationSessionRepository`: 세션별 최신 대화 ID 조회
- `ReportRepository`: 세션별 최신 리포트 ID 조회
- `drawing.dto.response`: 상세 및 중첩 요약 DTO 추가

같은 역할의 Controller, Service, Entity는 새로 만들지 않는다.

## 8. 테스트

### Service 단위 테스트

- 모든 연관 데이터가 있는 상세 응답 조립
- 선택 감정이 없으면 빈 배열
- Asset·분석·대화·리포트가 없으면 nullable 필드 처리
- DRAFT 존재 여부에 따른 `recoverableDraft`
- 권한 검증과 삭제 세션 오류
- 조회 중 외부 AI Client나 Storage가 호출되지 않음

### Repository 테스트

- 각 최신 데이터 조회의 정렬과 동률 처리
- 다른 세션 데이터가 섞이지 않음
- 삭제된 세션 제외

### Controller 테스트

- 정상 HTTP 200과 공통 응답 구조
- 잘못된 Path 변수 HTTP 400
- 권한 없음 또는 미존재 HTTP 404

## 9. 완료 조건

- 최신 명세의 상세 응답 필드를 보호자 권한 범위에서 제공한다.
- 연관 데이터 부재를 정상 응답으로 처리한다.
- 개인정보와 내부 저장 경로를 노출하지 않는다.
- DB 변경 없이 기존 Schema를 사용한다.
- `clean test`, `spotlessCheck`, `javadoc`이 성공한다.
