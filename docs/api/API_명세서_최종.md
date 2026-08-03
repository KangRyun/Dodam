# 아동_그림_대화_서비스_API_전체_명세서_v1.0

# 아동 그림·대화 기반 정서 표현 서비스 API 전체 명세서

> 문서 버전: v1.0
> 
> 
> 작성 기준일: 2026-07-21
> 
> 외부 API Base URL: `/api/v1`
> 
> 내부 AI API Base URL: `/internal/v1`
> 
> API 형식: REST/JSON, 일부 `multipart/form-data`
> 
> 기준 자료: 요구사항 명세서 V0.3.1 → 기능명세서 → 기존 API 명세 → 서비스 기획 → ERD
> 

---

## 1. 문서 목적

이 문서는 프론트엔드, Spring Boot 백엔드, FastAPI AI 서버가 동일한 API 계약을 사용하도록 전체 기능의 요청·응답 형식을 정의한다.

- 기존 API 문서의 URI·메서드만 나열된 부분을 보완한다.
- 같은 대상을 `activityId`, `sessionId` 등으로 다르게 부르던 문제를 제거한다.
- 각 API의 인증, 권한, Header, Path, Query, Body, 응답, 오류, 상태 전이와 담당 영역을 명시한다.
- 외부 앱 API와 백엔드-AI 서버 내부 API를 분리한다.
- 본 서비스의 AI 결과는 의료적·심리학적 진단이 아니라 그림·대화에서 관찰된 정보를 정리한 참고 자료이다.

우선순위 표시는 사용하지 않는다. 모든 API는 도메인별로 구분한다.

---

## 2. 확정된 설계 원칙

### 2.1 리소스 명칭

| 구분 | 표준 명칭 | 사용하지 않는 명칭 | 이유 |
| --- | --- | --- | --- |
| 그림 활동 전체 단위 | `drawingSession`, `drawingSessionId` | `activity`, `activityId`, 단독 `sessionId` | ERD의 `drawing_sessions.id`와 일치시킨다. |
| 저장된 그림 파일 | `drawingAsset`, `drawingAssetId` | `drawingImage`, `snapshot` 혼용 | ERD의 `drawing_assets.id`와 일치시킨다. `assetType`으로 용도를 구분한다. |
| AI 분석 단위 | `analysis`, `analysisId` | `resultId` | 한 활동에 중간·최종·재시도 분석이 여러 개 생길 수 있다. |
| AI 대화 단위 | `conversation`, `conversationId` | `chatId` | ERD의 `conversation_sessions.id`와 일치시킨다. |
| 대화 한 건 | `message`, `messageId` | `questionId`, `answerId` 혼용 | 질문과 답변을 `conversation_messages` 한 테이블에 저장한다. |
| 관찰 리포트 | `report`, `reportId` | `analysisReport` | 분석 원본과 보호자용 리포트를 분리한다. |

### 2.2 시스템 경계

| 호출 주체 | 호출 대상 | 허용 여부 |
| --- | --- | --- |
| Flutter/Next.js | Spring Boot `/api/v1/**` | 허용 |
| Flutter/Next.js | FastAPI `/internal/v1/**` | 금지 |
| Spring Boot | FastAPI `/internal/v1/**` | 허용 |
| FastAPI | MySQL 핵심 테이블 직접 접근 | 금지. 분석 결과는 Spring Boot가 저장한다. |
| 클라이언트 | S3 `storageKey` 직접 지정 | 금지. 업로드 파일은 Spring Boot가 검증하고 저장한다. |

### 2.3 역할 분리

| 영역 | 프론트엔드 | Spring Boot | AI 서버 |
| --- | --- | --- | --- |
| 인증·권한 | 토큰 전달, 401 시 재발급 | 토큰 발급·검증, 소유권 확인 | 외부 사용자 인증 처리 금지 |
| 파일 | 파일 선택, 크기·형식 사전 확인 | 최종 검증, S3 저장, 접근 URL 발급 | 제한 시간 URL로 읽기만 수행 |
| 그림 행동 | 배치 생성·재전송 | 순번·중복 검증 후 저장 | 행동 특징 계산 시 입력으로 사용 |
| AI 분석 | 분석 요청·폴링·상태 표시 | 분석 작업 생성, AI 호출, 결과 저장 | 객체·시각·행동·대화 특징 생성 |
| 대화 | TTS 재생, STT/선택지 입력 UI | 메시지 순서·상태 관리, AI 중계 | STT·TTS·다음 질문 생성 |
| 리포트 | 결과 표시, 근거와 주의문구 구분 | 권한 검증, 리포트 조립·저장 | 관찰 결과 초안 생성 |

### 2.4 리포트 신뢰성과 사용자별 공개 범위

RAG는 관련 논문·검사 지침·전문 자료를 검색해 근거를 연결하는 기술이지 AI의 해석을 진단으로 바꾸는 기술이 아니다. 검색된 문헌이 정확하더라도 개별 아동에게 적용하는 과정에서 오류가 생길 수 있으므로 다음 원칙을 강제한다.

| 구분 | 보호자용 활동 리포트 | 전문가용 검토 자료 |
| --- | --- | --- |
| 목적 | 아이의 실제 표현을 이해하고 대화를 이어가기 위한 기록 | 전문가의 사전 검토 시간 단축과 상담 질문 준비 |
| 제공 내용 | 활동 정보, 완성 그림, 아동이 직접 선택한 감정, 실제 발화, 객관적 행동 요약, 대화 가이드 | 보호자용 내용 + 객체·시각·행동 특징, 필압·멈춤·수정 데이터, AI 관찰 초안, 불확실성, 제외된 입력, 문헌 근거 |
| 제공 금지 | 진단명, 장애·질환 가능성 점수, 성격 단정, 원인 단정, 원시 위험 분류 점수 | AI 초안을 전문가 확정 의견처럼 표시하는 행위 |
| 공개 조건 | 활동 완료 후 보호자에게 제공 | 보호자 공유 동의 + 전문가 연결 승인 |
| 최종 판단 | 보호자에게 판단을 요구하지 않음 | 전문가가 원자료·맥락을 검토한 후 별도 의견 작성 |

#### RAG 근거 규칙

- 모든 RAG 기반 문장은 `evidenceReferences[]`와 연결한다.
- 근거 항목은 `sourceId`, `title`, `authors`, `publishedYear`, `section`, `evidenceType`, `applicability`, `limitations`를 포함한다.
- 검색 결과가 없거나 근거 연결이 실패한 문장은 전문가용 AI 초안에 포함하지 않는다.
- 문헌의 일반적 설명과 해당 아동에게서 실제 관찰된 사실을 문장과 화면 영역으로 분리한다.
- 문헌 제목만 인용하고 내용을 생성한 경우를 방지하기 위해 검색 문단 hash와 지식베이스 버전을 저장한다.
- 전문가 검토 전 상태는 `AI_DRAFT`, 검토 완료 후에는 `EXPERT_REVIEWED`로 표시한다.

#### 금지 표현 예시

| 금지 | 허용되는 대체 표현 |
| --- | --- |
| “아이는 불안장애가 있습니다.” | “그림의 이 부분에 대해 아이가 어떻게 느꼈는지 추가로 물어볼 수 있습니다.” |
| “필압이 강하므로 공격적입니다.” | “지원 기기에서 측정된 평균 필압이 이번 활동의 다른 구간보다 높았습니다.” |
| “검사 결과 우울 위험 82%입니다.” | 보호자 화면에는 제공하지 않음. 전문가 화면에서도 모델 신뢰도와 임상 판단을 동일시하지 않음. |
| “가정 문제 때문에 이런 그림을 그렸습니다.” | “아동의 발화만으로 원인을 확인할 수 없어 추가 맥락이 필요합니다.” |

#### 신뢰성 검증 원칙

- AI 결과와 전문가 평가의 일치도는 단순 정확도 하나로 표현하지 않는다.
- 객체 탐지는 precision·recall·mAP, STT는 WER, 근거 검색은 Recall@K·근거 적합성, 관찰 초안은 전문가 간 일치도와 오류 유형으로 분리한다.
- 전문가 검토 시 `AGREE`, `PARTIALLY_AGREE`, `DISAGREE`, `INSUFFICIENT_INFORMATION`을 기록하고 수정 문장과 사유를 남긴다.
- 검증용 데이터와 운영용 아동 데이터는 분리하고, 별도 동의 없이 운영 데이터를 검증·학습에 재사용하지 않는다.

---

## 3. 공통 API 규칙

### 3.1 환경별 URL

| 환경 | 예시 |
| --- | --- |
| Local | `http://localhost:8080/api/v1` |
| Development | `https://dev-api.example.com/api/v1` |
| Production | `https://api.example.com/api/v1` |

실제 호스트는 배포 환경 변수로 관리하며 코드에 고정하지 않는다.

### 3.2 요청 Header

| Header | 필수 | 적용 범위 | 예시 | 설명 |
| --- | --- | --- | --- | --- |
| `Authorization` | 조건부 | 인증 API를 제외한 외부 API | `Bearer eyJ...` | Access Token |
| `Content-Type` | 필수 | Body가 있는 요청 | `application/json` | 파일 API는 `multipart/form-data` |
| `Accept` | 권장 | 전체 | `application/json` | 응답 형식 |
| `Idempotency-Key` | 조건부 | 세션 생성, 분석 요청, 단계 완료, 결제성 없는 중복 위험 POST | UUID | 동일 키 재요청은 최초 결과 반환 |
| `X-Request-Id` | 선택 | 전체 | UUID | 누락 시 서버 생성 |
| `X-Device-Id` | 권장 | 로그인·재발급·로그아웃 | 앱 설치 단위 UUID | Refresh Token 세션 구분 |
| `X-Internal-Api-Key` | 필수 | `/internal/v1/**` | 서버 비밀값 | 외부 클라이언트 사용 금지 |

### 3.3 JSON·DB 명명 규칙

- URI는 복수 명사와 `kebab-case`를 사용한다: `/drawing-sessions`.
- JSON 필드는 `camelCase`를 사용한다: `drawingSessionId`.
- DB 컬럼은 `snake_case`를 사용한다: `drawing_session_id`.
- Enum은 `UPPER_SNAKE_CASE` 문자열로 전달한다.
- 식별자는 JSON `integer(int64)`로 전달한다.
- 금액은 없으며, 비율·신뢰도는 `0.0` 이상 `1.0` 이하의 number를 사용한다.
- 서버 시각은 UTC로 저장하고 ISO 8601로 응답한다: `2026-07-21T02:30:00.123Z`.
- 클라이언트가 보내는 표시용 시각에는 offset을 포함한다: `2026-07-21T11:30:00+09:00`.
- `null`, 빈 문자열 `""`, 빈 배열 `[]`은 의미가 다르므로 임의 변환하지 않는다.

### 3.4 성공 응답

```json
{
  "success": true,
  "code": "COMMON_200",
  "message": "요청이 성공했습니다.",
  "data": {}
}
```

- 생성 성공: `201 Created`
- 일반 조회·수정·처리 성공: `200 OK`
- 응답 Body가 필요 없는 삭제 성공: `204 No Content`
- 비동기 분석 접수: `202 Accepted`

### 3.5 실패 응답

```json
{
  "success": false,
  "code": "COMMON_400_001",
  "message": "요청 값이 올바르지 않습니다.",
  "data": {
    "fieldErrors": [
      {
        "field": "birthDate",
        "message": "생년월일이 올바르지 않습니다."
      }
    ],
    "globalErrors": []
  }
}
```

운영 환경에서는 내부 예외명, SQL, 저장소 경로, AI 프롬프트, 토큰을
`message`에 포함하지 않는다. 사용자 입력 원문인 `rejectedValue`도 반환하지
않는다. 상세 계약은 `common-response-error-contract-v1.md`를 따른다.

### 3.6 HTTP 상태 코드

| 상태 | 사용 기준 |
| --- | --- |
| `200` | 조회·수정·동기 처리 성공 |
| `201` | 사용자·아동·세션·게시글 등 리소스 생성 |
| `202` | AI 분석처럼 접수 후 비동기로 처리 |
| `204` | 삭제 또는 취소 성공, 응답 Body 없음 |
| `400` | JSON 형식, Enum, 필수값, 파일 형식 오류 |
| `401` | Access Token 누락·만료·위조 |
| `403` | 역할 또는 리소스 소유권 부족, 필수 동의 없음 |
| `404` | 리소스 없음 또는 권한상 존재를 숨겨야 하는 리소스 |
| `409` | 중복 가입, 중복 순번, 잘못된 상태 전이, 이미 처리된 요청 |
| `413` | 파일 용량 초과 |
| `422` | 문법은 맞지만 업무 규칙 위반 |
| `429` | 분석·로그인·대화 요청 제한 초과 |
| `500` | 처리되지 않은 서버 오류 |
| `502` | 외부 인증·AI·저장소 연동 실패 |
| `503` | AI 서버 또는 핵심 의존 서비스 일시 사용 불가 |

### 3.7 페이지 응답

Query 기본값은 `page=0`, `size=20`이며 `size`는 `1~100`이다.

```json
{
  "content": [],
  "page": 0,
  "size": 20,
  "totalElements": 0,
  "totalPages": 0,
  "first": true,
  "last": true,
  "hasNext": false
}
```

정렬은 API별 허용 필드만 사용한다. 임의 컬럼명 정렬은 받지 않는다.

### 3.8 파일 규칙

| 유형 | 허용 형식 | 최대 크기 | 추가 제한 |
| --- | --- | --- | --- |
| 그림 | JPEG, PNG, WEBP | 10 MiB | 최소 320×320, 최대 8192×8192 |
| 음성 | WEBM, M4A, WAV, MP3 | 20 MiB | 최대 60초 |
| 프로필 | JPEG, PNG, WEBP | 5 MiB | EXIF 위치정보 제거 |
| 자격 증빙 | PDF, JPEG, PNG | 10 MiB | 관리자 외 원본 접근 금지 |

클라이언트의 MIME 값과 실제 파일 signature를 모두 검사한다. S3의 영구 공개 URL은 응답하지 않으며 조회용 URL에는 만료 시간을 둔다.

### 3.9 멱등성과 중복 방지

- `Idempotency-Key`는 사용자·URI·요청 Body 해시와 함께 저장한다.
- 같은 키와 같은 Body: 최초 상태 코드와 응답을 반환한다.
- 같은 키와 다른 Body: `409 IDEMPOTENCY_KEY_REUSED`.
- 그림 세션 생성·그림 단계 완료·전체 활동 완료의 현재 구현 계약과 오류 코드는
  `drawing-idempotency-contract-v1.md`를 따른다.
- `stroke_batches`는 `(drawing_session_id, batch_sequence)`를 유일하게 관리한다.
- `analyses.idempotency_key`와 입력 이미지 checksum으로 중복 분석을 방지한다.
- 좋아요·팔로우는 사용자와 대상의 복합 unique 제약으로 중복을 방지한다.

### 3.10 공통 오류 코드

| 코드 | HTTP | 의미 |
| --- | --- | --- |
| `COMMON_400_001` | 400 | 요청 값 또는 Validation 오류 |
| `COMMON_400_002` | 400 | Path·Query 값 타입 변환 오류 |
| `COMMON_400_003` | 400 | JSON Body 읽기·역직렬화 오류 |
| `COMMON_400_004` | 400 | 필수 Query·Multipart Part 누락 |
| `COMMON_404_001` | 404 | API 또는 일반 리소스 없음 |
| `COMMON_405_001` | 405 | 지원하지 않는 HTTP Method |
| `COMMON_409_001` | 409 | 데이터 무결성 조건 충돌 |
| `COMMON_500_001` | 500 | 처리되지 않은 서버 오류 |

도메인 오류와 기존 의미 기반 코드의 호환성 규칙은
`common-response-error-contract-v1.md`를 따른다.

---

## 4. Enum 사전

| Enum | 허용값 |
| --- | --- |
| `UserRole` | `GUARDIAN`, `EXPERT`, `ADMIN` |
| `AccountStatus` | `PENDING`, `ACTIVE`, `SUSPENDED`, `DELETED` |
| `AuthProvider` | `KAKAO`, `GOOGLE`, `NAVER`, `APPLE` |
| `QuestionDifficulty` | `PRESCHOOL`, `LOWER_ELEMENTARY`, `UPPER_ELEMENTARY`, `SUPPORT` |
| `TutorialStatus` | `NOT_STARTED`, `IN_PROGRESS`, `COMPLETED`, `SKIPPED` |
| `ProfileStatus` | `ACTIVE`, `DELETED` |
| `ConsentAction` | `AGREE`, `WITHDRAW` |
| `DrawingCategory` | `ASSESSMENT`, `GENERAL` |
| `SelectableBy` | `GUARDIAN`, `CHILD`, `BOTH` |
| `InputMethod` | `CANVAS`, `UPLOAD` |
| `DrawingSessionStatus` | `IN_PROGRESS`, `COMPLETED`, `FAILED`, `ABANDONED`, `DELETED` |
| `DrawingStage` | `DRAWING`, `ANALYZING`, `CONVERSING`, `REFLECTION`, `REPORTING`, `COMPLETED` |
| `AssetType` | `DRAFT`, `INTERMEDIATE`, `FINAL`, `UPLOADED`, `THUMBNAIL`, `TIMELAPSE` |
| `AnalysisType` | `INTERMEDIATE`, `FINAL` |
| `AnalysisStatus` | `PENDING`, `PROCESSING`, `PARTIAL_SUCCESS`, `SUCCESS`, `FAILED` |
| `AnalysisTriggerReason` | `PAUSE`, `INTERVAL`, `STROKE_COUNT`, `CHANGE_RATIO`, `USER_REQUEST`, `DRAWING_COMPLETE`, `ACTIVITY_COMPLETE`, `RETRY` |
| `ConversationStatus` | `CONVERSING`, `COMPLETED`, `FAILED` |
| `MessageSenderType` | `AI`, `CHILD`, `GUARDIAN`, `SYSTEM` |
| `MessageType` | `QUESTION`, `VOICE_ANSWER`, `OPTION_ANSWER`, `TEXT_ANSWER`, `SYSTEM_NOTICE` |
| `SpeechStatus` | `NOT_REQUIRED`, `PENDING`, `PROCESSING`, `SUCCESS`, `FAILED` |
| `EmotionType` | `HAPPY`, `SAD`, `ANGRY`, `SCARED`, `CALM`, `UNKNOWN` |
| `ReportStatus` | `GENERATING`, `COMPLETED`, `FAILED`, `HIDDEN` |
| `PostType` | `GUARDIAN_STORY`, `ACTIVITY_REVIEW`, `EXPERT_COLUMN`, `ART_RESOURCE`, `DRAWING_GUIDE`, `EXPERT_QNA`, `NOTICE` |
| `PostStatus` | `ACTIVE`, `HIDDEN`, `DELETED` |
| `ComplaintTargetType` | `POST`, `COMMENT`, `REPORT`, `AI_QUESTION` |
| `ComplaintStatus` | `PENDING`, `IN_REVIEW`, `RESOLVED`, `REJECTED` |
| `NotificationType` | `ANALYSIS_COMPLETED`, `ANALYSIS_FAILED`, `REPORT_COMPLETED`, `NEW_EXPERT_POST`, `COMMENT_CREATED`, `CONSENT_UPDATED`, `RETENTION_NOTICE`, `ACTIVITY_REMINDER`, `RISK_REVIEW_GUIDE` |
| `DeliveryStatus` | `PENDING`, `SENT`, `FAILED` |
| `ExpertVerificationStatus` | `PENDING`, `VERIFIED`, `REJECTED`, `REVIEW_REQUIRED` |
| `ConsultationStatus` | `REQUESTED`, `ACCEPTED`, `REJECTED`, `CANCELLED`, `DISCONNECTED`, `COMPLETED` |
| `ObservationReviewStatus` | `AI_DRAFT`, `EXPERT_REVIEW_REQUIRED`, `EXPERT_REVIEWED`, `REJECTED` |
| `ExpertReviewStatus` | `DRAFT`, `COMPLETED` |
| `ExpertAgreement` | `AGREE`, `PARTIALLY_AGREE`, `DISAGREE`, `INSUFFICIENT_INFORMATION` |

---

## 5. 인증 `auth`

### 5.1 API 목록

| ID | Method | URI | 인증 | 설명 |
| --- | --- | --- | --- | --- |
| AUTH-01 | POST | `/auth/signup` | 불필요 | 자체 회원가입 |
| AUTH-02 | POST | `/auth/login` | 불필요 | 이메일·비밀번호 로그인 |
| AUTH-03 | POST | `/auth/oauth/{provider}` | 불필요 | 카카오·구글·네이버 소셜 로그인 |
| AUTH-04 | POST | `/auth/reissue` | Refresh Token | 토큰 재발급 및 Refresh Token rotation |
| AUTH-05 | POST | `/auth/logout` | Access Token | 현재 기기 로그아웃 |
| AUTH-06 | POST | `/auth/logout-all` | Access Token | 모든 기기 로그아웃 |

### 5.2 요청 DTO

#### `SignUpRequest`

| 필드 | 타입 | 필수 | 제약 |
| --- | --- | --- | --- |
| `email` | string | O | 이메일 형식, 최대 255자, 소문자 정규화 |
| `password` | string | O | 8~64자, 영문·숫자·특수문자 중 2종 이상 |
| `role` | `UserRole` | O | `GUARDIAN` 또는 `EXPERT`; `ADMIN` 금지 |
| `deviceId` | string | O | 최대 255자 |

#### `LoginRequest`

| 필드 | 타입 | 필수 | 제약 |
| --- | --- | --- | --- |
| `email` | string | O | 이메일 형식 |
| `password` | string | O | 평문은 TLS 요청에서만 전송, 로그 출력 금지 |
| `deviceId` | string | O | 앱 설치 단위 식별자 |

#### `OAuthLoginRequest`

| 필드 | 타입 | 필수 | 제약 |
| --- | --- | --- | --- |
| Path `provider` | `AuthProvider` | O | `KAKAO`, `GOOGLE`, `NAVER`, `APPLE` |
| `accessToken` | string | 조건부 | Kakao·Naver에서 필수, 최대 4096자 |
| `idToken` | string | 조건부 | Google·Apple에서 필수, 최대 4096자 |
| `rawNonce` | string | 조건부 | Apple에서만 필수, 최대 512자 |
| `deviceId` | string | O | 기기 식별자 |

#### `TokenReissueRequest`

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `refreshToken` | string | O | 서버에는 hash만 저장 |
| `deviceId` | string | O | 발급 기기와 일치해야 함 |

### 5.3 인증 응답

```json
{
  "grantType": "Bearer",
  "accessToken": "access-token",
  "accessTokenExpiresInSeconds": 1800,
  "refreshToken": "refresh-token",
  "refreshTokenExpiresInSeconds": 1209600,
  "user": {
    "userId": 1,
    "role": "GUARDIAN",
    "nickname": null,
    "accountStatus": "PENDING",
    "onboardingCompleted": false
  }
}
```

Apple 계정 처리 규칙:

- Apple 계정 식별자는 이메일이 아니라 `(APPLE, sub)` 조합이다.
- 최초 Apple 로그인에서 검증된 이메일은 인증 계정에 보존하며, 후속 Token에 이메일이 없어도 로그인 응답에 재사용한다.
- 온보딩에서 확정한 `users.email`이 있으면 인증 계정의 Provider 이메일보다 우선한다.
- 이메일이 같은 다른 OAuth Provider 계정과 자동 병합하지 않는다.
- 회원 탈퇴는 사용자 행을 `DELETED`로 전환하고 Apple 인증 계정 행은 삭제한다. 같은 `sub`로 다시 로그인하면 기존 삭제 계정을 복구하지 않고 신규 사용자로 가입한다.

### 5.4 처리 규칙과 오류

| API | 주요 처리 | 오류 코드 |
| --- | --- | --- |
| AUTH-01 | `users`와 `auth_accounts(provider=LOCAL)`를 한 트랜잭션으로 생성 | `EMAIL_ALREADY_EXISTS`, `PASSWORD_POLICY_VIOLATION`, `ROLE_NOT_ALLOWED` |
| AUTH-02 | 비밀번호 hash 검증, `last_login_at` 갱신, 토큰 발급 | `INVALID_CREDENTIALS`, `ACCOUNT_SUSPENDED` (`DELETED` 포함) |
| AUTH-03 | authorization code를 Provider token과 교환하고 `provider_subject`로 계정 식별 | `OAUTH_CODE_INVALID`, `OAUTH_PROVIDER_ERROR`, `ACCOUNT_LINK_CONFLICT` |
| AUTH-04 | hash·기기·만료·폐기 여부 검증 후 기존 Refresh Token 폐기 및 새 토큰 발급 | `REFRESH_TOKEN_INVALID`, `REFRESH_TOKEN_EXPIRED`, `DEVICE_MISMATCH` |
| AUTH-05 | 요청의 Refresh Token 또는 해당 기기의 활성 토큰 폐기 | `REFRESH_TOKEN_INVALID` |
| AUTH-06 | 사용자의 모든 활성 Refresh Token 폐기 | 공통 오류 |

---

## 6. 사용자 `user`

### 6.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| USER-01 | GET | `/users/me` | 로그인 사용자 | 내 정보 조회 |
| USER-02 | PUT | `/users/me/onboarding` | 로그인 사용자 | 최초 사용자 정보 등록·온보딩 완료 |
| USER-03 | PATCH | `/users/me` | 로그인 사용자 | 닉네임·프로필 이미지 수정 |
| USER-04 | PATCH | `/users/me/notification-settings` | 로그인 사용자 | 알림 수신 설정 변경 |
| USER-05 | DELETE | `/users/me` | 로그인 사용자 | 회원 탈퇴 |

### 6.2 요청 필드

| API | Body |
| --- | --- |
| USER-02 | `nickname:string(1~50)`, `role:GUARDIAN\|EXPERT`, `email:string(이메일 형식, 최대 255자)`, `profileImageFileId?:string` |
| USER-03 | 변경할 필드만 전달: `nickname?:string(1~50)`, `profileImageFileId?:string|null` |
| USER-04 | `analysisCompleted:boolean`, `community:boolean`, `serviceNotice:boolean`, `marketing:boolean` |
| USER-05 | `password?:string`(LOCAL 계정), `confirmation:string` 값은 `DELETE`, `deleteChildData:boolean` |

USER-02 연락 이메일 계약:

- `email:string`은 필수이며 이메일 형식, 최대 255자 제약을 적용한다.
- Backend는 이메일의 앞뒤 공백을 제거하고 `Locale.ROOT` 기준 소문자로 정규화한 뒤 `users.email`에 저장한다.
- `users.email`은 계정 식별자가 아닌 연락 이메일이다. 동일 이메일을 사용하는 서로 다른 OAuth 사용자를 허용하며 이메일을 기준으로 계정을 자동 병합하지 않는다.

### 6.3 `UserResponse`

```json
{
  "userId": 1,
  "role": "GUARDIAN",
  "nickname": "튼튼이엄마",
  "email": "guardian@example.com",
  "accountStatus": "ACTIVE",
  "profileImageUrl": "https://signed.example.com/profile/1",
  "notificationSettings": {
    "analysisCompleted": true,
    "community": true,
    "serviceNotice": true,
    "marketing": false
  },
  "onboardingCompleted": true,
  "lastLoginAt": "2026-07-21T02:00:00Z",
  "createdAt": "2026-07-20T01:00:00Z"
}
```

### 6.4 규칙

- USER-02는 멱등한 `PUT`이다. 이미 완료한 사용자가 동일 내용을 보내면 현재 정보를 반환한다.
- 역할을 `ADMIN`으로 변경하는 요청은 거부한다.
- USER-05는 사용자 행을 hard delete하지 않고 `account_status=DELETED`, `deleted_at`으로 전환한다. Access Token은 요청마다 상태를 확인해 즉시 차단하고, 모든 Refresh Token family를 폐기한다.
- USER-05는 단독 보호 아동만 Soft Delete하고 해당 그림·대화 음성·리포트·아동 프로필 이미지의 `storage_deletion_jobs`를 `PENDING`으로 적재한다. 공동 보호 아동은 삭제하지 않고 탈퇴 사용자와의 보호자 관계만 해제한다.
- Storage deletion worker의 claim·재시도·물리 객체 삭제, 보존 만료 purge, data export 파일·작업 삭제는 USER-05 범위에 포함하지 않는다. 성공한 파일 물리 삭제로 해석하면 안 된다.
- 아동·그림·음성·대화·리포트 삭제 범위와 법적 보존 데이터는 탈퇴 응답 전 확인 화면에 표시한다.
- 오류: `NICKNAME_ALREADY_EXISTS`, `ONBOARDING_REQUIRED`, `WITHDRAWAL_CONFIRMATION_MISMATCH`.

---

## 7. 전문가 프로필 `expert`

### 7.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| EXPERT-01 | POST | `/experts/me/profile` | EXPERT | 내 전문가 프로필 등록 |
| EXPERT-02 | PATCH | `/experts/me/profile` | EXPERT | 내 전문가 프로필 수정 |
| EXPERT-03 | GET | `/experts` | GUARDIAN, EXPERT | 공개 전문가 목록 조회 |
| EXPERT-04 | GET | `/experts/{expertId}` | GUARDIAN, EXPERT | 공개 전문가 상세 조회 |
| EXPERT-05 | POST | `/experts/me/credentials` | EXPERT | 자격 증빙 업로드 |
| EXPERT-06 | GET | `/experts/me/credentials` | EXPERT | 내 자격 증빙 목록 조회 |
| EXPERT-07 | DELETE | `/experts/me/credentials/{credentialId}` | EXPERT | 검토 전 자격 증빙 삭제 |
| EXPERT-08 | POST | `/experts/{expertId}/follow` | GUARDIAN | 전문가 팔로우 |
| EXPERT-09 | DELETE | `/experts/{expertId}/follow` | GUARDIAN | 전문가 팔로우 취소 |

`EXPERT-01`은 `S15P11B209-574`에서 구현되었다. 신규 프로필은 `PENDING`으로 생성하며 사용자당 하나만 허용한다.
`EXPERT-03`과 `EXPERT-04`는 `S15P11B209-575`에서 구현되었다. 목록은 기본적으로 `VERIFIED` 프로필만 반환하고,
상세 조회에서 검증 전 프로필은 해당 프로필 소유자만 확인할 수 있다. 팔로워 수와 `followedByMe`는 요청 시점의
`expert_follows`를 기준으로 계산한다.

### 7.2 목록 Query

| 필드 | 타입 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `specialty` | string | 없음 | 전문 분야 코드 |
| `consultationAvailable` | boolean | 없음 | 상담 가능 여부 |
| `verifiedOnly` | boolean | `true` | 검증 완료 전문가만 조회 |
| `keyword` | string | 없음 | 표시명·소속 검색, 최대 50자 |
| `page`, `size` | integer | `0`, `20` | 페이지 |

### 7.3 프로필 요청

```json
{
  "displayName": "마음숲 상담사",
  "organization": "마음숲 아동상담센터",
  "positionTitle": "상담사",
  "careerYears": 6,
  "specialties": ["CHILD_ART", "PARENT_COUNSELING"],
  "targetAgeMin": 4,
  "targetAgeMax": 12,
  "introduction": "아동의 표현을 존중하며 상담합니다.",
  "consultationAvailable": true,
  "workplace": "대전광역시"
}
```

`careerYears`는 `0~80`, 연령은 `0~19`, 소개는 최대 2,000자이다. 연락처와 이메일은 본인·관리자에게만 반환하고 공개 응답에서 제외한다.

### 7.4 공개 응답 핵심 필드

`expertId`, `displayName`, `profileImageUrl`, `organization`, `positionTitle`, `careerYears`, `specialties[]`, `targetAgeMin`, `targetAgeMax`, `introduction`, `consultationAvailable`, `verificationStatus`, `followerCount`, `followedByMe`.

### 7.5 자격 업로드

`multipart/form-data`

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `file` | binary | O | PDF/JPEG/PNG, 최대 10 MiB |
| `metadata` | JSON string | O | `credentialType`, `credentialName`, `issuer`, `issuedAt`, `credentialNumberMasked` |

증빙 업로드·프로필의 주요 정보 변경 시 `verificationStatus=REVIEW_REQUIRED`로 전환한다.

`EXPERT-05`는 `S15P11B209-577`에서 구현되었다. `file`의 선언 MIME Type·확장자·실제 Signature가 모두
PDF/JPEG/PNG 중 같은 형식이어야 하며 실제 Byte 기준 최대 크기는 10 MiB이다. 파일은 로컬 또는 MinIO의
`credentials/` 전용 영역에 저장하고, API 응답에는 내부 `storageKey`와 Checksum을 노출하지 않는다.
등록한 자격 자체의 `verificationStatus`는 `PENDING`이며, 기존 프로필이 이미 검증된 상태였다면 프로필은
`REVIEW_REQUIRED`로 전환한다.

성공 응답 `data`는 `credentialId`, `credentialType`, `credentialName`, `issuer`, `issuedAt`,
`credentialNumberMasked`, `verificationStatus`, `fileName`, `mimeType`, `fileSizeBytes`, `createdAt`을 포함한다.
파일 형식 불일치는 `CREDENTIAL_FILE_INVALID`, 10 MiB 초과는 `CREDENTIAL_FILE_TOO_LARGE`, Storage 오류는
`CREDENTIAL_STORAGE_FAILED`로 반환한다.

`EXPERT-06`과 `EXPERT-07`은 `S15P11B209-578`에서 구현되었다. 목록은 로그인 전문가가 소유한 자격만
`createdAt`, `credentialId` 내림차순으로 반환하며 업로드 성공 응답과 같은 공개 필드를 사용한다. 삭제는 관리자 검토가
시작되지 않은 `PENDING` 자격만 허용한다. `VERIFIED`, `REJECTED`, `REVIEW_REQUIRED`는 검토 이력 보존을 위해 삭제할 수
없으며 `CREDENTIAL_DELETE_NOT_ALLOWED`를 반환한다. 존재하지 않거나 다른 전문가가 소유한 자격은 소유권 정보를 숨기기
위해 모두 `CREDENTIAL_NOT_FOUND`로 반환한다. DB 삭제가 Commit된 다음 Local/MinIO 증빙 파일을 제거한다.

### 7.6 팔로우 응답·오류

- EXPERT-08: `201`, `{ "expertId": 10, "followed": true, "followerCount": 128 }`
- EXPERT-09: `204`
- 오류: `EXPERT_PROFILE_ALREADY_EXISTS`, `EXPERT_NOT_VERIFIED`, `CREDENTIAL_FILE_INVALID`, `FOLLOW_SELF_NOT_ALLOWED`, `FOLLOW_ALREADY_EXISTS`.

---

## 8. 아동 프로필 `child`

### 8.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| CHILD-01 | POST | `/children` | GUARDIAN | 아동 프로필 등록 |
| CHILD-02 | GET | `/children` | GUARDIAN | 연결된 아동 목록 조회 |
| CHILD-03 | GET | `/children/{childId}` | 연결 보호자 | 아동 상세 조회 |
| CHILD-04 | PATCH | `/children/{childId}` | 연결 보호자 | 아동 정보·질문 난이도 수정 |
| CHILD-05 | DELETE | `/children/{childId}` | 주 보호자 | 아동 프로필 삭제 |
| CHILD-06 | GET | `/children/{childId}/tutorial` | 연결 보호자 | 튜토리얼 상태 조회 |
| CHILD-07 | PATCH | `/children/{childId}/tutorial` | 연결 보호자 | 튜토리얼 상태 변경 |

### 8.2 등록·수정 요청

| 필드 | 타입 | 등록 필수 | 제약 |
| --- | --- | --- | --- |
| `nickname` | string | O | 1~50자, 실명 대신 별칭 허용 |
| `birthDate` | date | O | 요청일 기준 만 4~12세 |
| `relationshipType` | string | O | `MOTHER`, `FATHER`, `GRANDPARENT`, `GUARDIAN`, `OTHER` |
| `preferredCharacter` | string | X | `BASE`, `PRINCESS`, `DINO`, `OCTOPUS` |
| `questionDifficulty` | `QuestionDifficulty` | O | 연령 기본값을 제안하되 보호자가 변경 가능 |
| `responseModes` | string[] | O | `VOICE`, `EMOJI`, `COLOR`, `PICTURE`, `TEXT` 중 1개 이상 |
| `profileImageFileId` | string | X | 사전 업로드 파일 식별자 |

### 8.3 응답

```json
{
  "childId": 1,
  "nickname": "별이",
  "birthDate": "2019-03-15",
  "age": 7,
  "relationshipType": "MOTHER",
  "preferredCharacter": "BASE",
  "questionDifficulty": "LOWER_ELEMENTARY",
  "responseModes": ["VOICE", "EMOJI", "COLOR"],
  "tutorialStatus": "NOT_STARTED",
  "profileStatus": "ACTIVE",
  "profileImageUrl": "/api/v1/child-profile-images/d20f42a9-6a55-4c91-b4b0-b6c79b8bd121/file",
  "createdAt": "2026-07-21T02:30:00Z"
}
```

`PATCH /api/v1/children/{childId}`는 JSON 필드 존재 여부를 구분한다.

- `preferredCharacter` 생략: 기존 캐릭터를 유지한다.
- `preferredCharacter: null`: 캐릭터 선택을 해제한다.
- `profileImageFileId` 생략: 기존 사진을 유지한다.
- `profileImageFileId: null`: 기존 사진을 삭제 큐에 등록하고 연결을 해제한다.
- `profileImageUrl`은 JWT 인증이 필요한 Backend proxy 상대 경로이며 Storage Key나 presigned URL이 아니다.

### 8.4 튜토리얼 변경

```json
{
  "status": "COMPLETED",
  "lastStep": 5
}
```

허용 전이는 `NOT_STARTED → IN_PROGRESS → COMPLETED`이며 `IN_PROGRESS → SKIPPED`가 가능하다. 완료 후 다시 보기는 상태를 되돌리지 않고 프론트에서 제공한다.

### 8.5 삭제 규칙·오류

- CHILD-05 Query `cascade`는 받지 않는다. 삭제 범위는 서버 정책으로 고정하고 Body의 `confirmation:"DELETE"`로 재확인한다.
- `children.deleted_at`, `profile_status=DELETED`로 전환한 뒤 그림·음성·대화·리포트 삭제 작업을 예약한다.
- 다른 보호자가 연결되어 있으면 단독 삭제를 금지하거나 관계 해제만 수행한다.
- 오류: `CHILD_AGE_OUT_OF_RANGE`, `CHILD_NOT_FOUND`, `CHILD_ACCESS_DENIED`, `CHILD_ALREADY_REGISTERED`, `CHILD_HAS_OTHER_GUARDIAN`.

---

## 9. 동의 관리 `consent`

### 9.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| CONSENT-01 | GET | `/consents/terms` | 로그인 사용자 | 활성 약관 목록 조회 |
| CONSENT-02 | GET | `/consents?childId={childId}` | 연결 보호자 | 사용자·아동 동의 현황 조회 |
| CONSENT-03 | POST | `/consents` | 연결 보호자 | 최초 동의 등록 |
| CONSENT-04 | PATCH | `/consents` | 연결 보호자 | 선택 동의 변경·철회·재동의 |
| CONSENT-05 | GET | `/consents/history` | 연결 보호자 | 동의 이력 조회 |

### 9.2 약관 목록 Query·응답

- Query: `targetScope=USER|CHILD`, `version?`.
- 응답 항목: `termId`, `termCode`, `targetScope`, `required`, `version`, `title`, `contentUrl`, `effectiveAt`.

### 9.3 동의 등록·변경 요청

```json
{
  "childId": 1,
  "agreements": [
    { "termId": 1, "action": "AGREE" },
    { "termId": 2, "action": "AGREE" },
    { "termId": 4, "action": "WITHDRAW" }
  ]
}
```

- `childId`는 사용자 대상 약관만 처리할 때 `null`이다.
- 최초 등록은 모든 활성 필수 약관의 `AGREE`가 필요하다.
- 변경 API도 현재 상태를 update하지 않고 `consent_records`에 새 이력을 append한다.
- AI 학습 동의 철회는 기본 서비스 사용을 차단하지 않는다.
- 음성 처리 동의가 없으면 음성 API는 `403 VOICE_CONSENT_REQUIRED`를 반환하고 선택형 답변을 사용한다.

### 9.4 현황 응답

```json
{
  "childId": 1,
  "requiredConsentsSatisfied": true,
  "items": [
    {
      "termId": 1,
      "termCode": "CHILD_PERSONAL_DATA",
      "required": true,
      "version": "1.0",
      "agreed": true,
      "recordedAt": "2026-07-21T02:30:00Z"
    }
  ]
}
```

### 9.5 이력 Query·오류

- Query: `childId?`, `termCode?`, `from?`, `to?`, `page=0`, `size=20`.
- 오류: `REQUIRED_CONSENT_MISSING`, `TERM_NOT_FOUND`, `TERM_VERSION_INACTIVE`, `CONSENT_ACTOR_NOT_GUARDIAN`, `VOICE_CONSENT_REQUIRED`.

---

## 10. 그림 유형·그림 활동 `drawing`

### 10.1 상태 모델

`drawing_sessions`의 전체 생명주기와 현재 화면 단계를 분리한다.

| 구분 | 값 | 의미 |
| --- | --- | --- |
| `sessionStatus` | `IN_PROGRESS` | 아직 완료되지 않은 활동 |
|  | `COMPLETED` | 그림·대화·감정 표현이 정상 완료됨 |
|  | `FAILED` | 복구 불가능한 업무 실패. 원본·임시 저장은 정책에 따라 유지 |
|  | `DELETED` | 보호자 삭제 요청으로 비노출 |
| `currentStage` | `DRAWING` | 캔버스 또는 그림 업로드 |
|  | `ANALYZING` | 중간·최종 그림 분석 진행 |
|  | `CONVERSING` | AI 질문과 아동 답변 진행 |
|  | `REFLECTION` | 감정 선택·그림 제목 입력 |
|  | `REPORTING` | 최종 분석과 리포트 생성 |
|  | `COMPLETED` | 전체 활동 종료 |

정상 흐름은 다음과 같다.

```
IN_PROGRESS/DRAWING
→ IN_PROGRESS/ANALYZING
→ IN_PROGRESS/CONVERSING
→ IN_PROGRESS/REFLECTION
→ IN_PROGRESS/REPORTING
→ COMPLETED/COMPLETED
```

중간 분석·대화 후 다시 그리기로 돌아갈 때는 `CONVERSING → DRAWING` 전이가 가능하다.

### 10.2 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| DRAWING-01 | GET | `/drawing-types` | 로그인 사용자 | 아동에게 노출할 그림 유형 목록 |
| DRAWING-02 | POST | `/drawing-sessions` | 연결 보호자 | 그림 활동 세션 생성 |
| DRAWING-03 | GET | `/drawing-sessions/{drawingSessionId}` | 연결 보호자, 공유 전문가 | 그림 세션 상태·요약 조회 |
| DRAWING-04 | POST | `/drawing-sessions/{drawingSessionId}/stroke-batches` | 연결 보호자 | 캔버스 행동 데이터 배치 저장 |
| DRAWING-05 | PUT | `/drawing-sessions/{drawingSessionId}/draft` | 연결 보호자 | 현재 임시 저장 전체본 upsert |
| DRAWING-06 | GET | `/drawing-sessions/{drawingSessionId}/draft` | 연결 보호자 | 임시 저장 복구 |
| DRAWING-07 | DELETE | `/drawing-sessions/{drawingSessionId}/draft` | 연결 보호자 | 임시 저장 삭제 |
| DRAWING-08 | POST | `/drawing-sessions/{drawingSessionId}/upload` | 연결 보호자 | 종이 그림 또는 기존 이미지 업로드 |
| DRAWING-09 | POST | `/drawing-sessions/{drawingSessionId}/drawing-complete` | 연결 보호자 | 그림 단계 완료 및 최종 그림 저장 |
| DRAWING-10 | PUT | `/drawing-sessions/{drawingSessionId}/reflection` | 연결 보호자 | 제목·감정 선택·직접 표현 저장 |
| DRAWING-11 | POST | `/drawing-sessions/{drawingSessionId}/complete` | 연결 보호자 | 전체 활동 완료 및 최종 분석·리포트 생성 요청 |
| DRAWING-12 | DELETE | `/drawing-sessions/{drawingSessionId}` | 연결 보호자 | 활동 기록 삭제 |

### 10.3 그림 유형 조회

#### Query

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `childId` | int64 | O | 연결 권한과 아동 상태를 확인할 식별자 |
| `category` | `DrawingCategory` | X | `ASSESSMENT`, `GENERAL` |
| `activeOnly` | boolean | X | 기본 `true` |

#### 응답 항목

`drawingTypeId`, `code`, `name`, `activityCategory`, `selectableBy`, `recommendedAgeMin`, `recommendedAgeMax`, `guideText`, `displayOrder`.

응답은 공통 성공 응답의 `data`에 `content`, `page`, `size`, `totalElements`, `totalPages`, `hasNext`를 포함하는 단일 페이지로 반환한다.
유형은 `displayOrder`, `drawingTypeId` 오름차순으로 정렬한다.
`recommendedAgeMin`, `recommendedAgeMax`는 보호자 화면 안내를 위한 참고 Metadata이며 목록 노출이나 활동 시작을 제한하지 않는다.
`activeOnly=false`이면 비활성 유형도 조회 대상에 포함한다.

검사형 코드를 지원하더라도 API·화면은 AI가 검사를 실시하거나 진단을 확정하는 것처럼 표현하지 않는다. 일반 활동 코드는 `ART_DIARY`, `FREE_DRAWING`, `EMOTION_COLORING`, `WEATHER_MIND` 등을 사용한다.
초기 기준 데이터로 위 네 가지 일반 활동 코드를 제공하며, 코드는 화면 표시명이 아닌 클라이언트와 서버 간 식별값으로 사용한다.

### 10.4 세션 생성

Header `Idempotency-Key` 필수.

```json
{
  "childId": 1,
  "drawingTypeId": 2,
  "inputMethod": "CANVAS",
  "clientStartedAt": "2026-07-21T11:30:00+09:00"
}
```

#### 검증

- 보호자-아동 연결과 필수 동의를 확인한다.
- `canvas`는 입력 방식과 무관하게 선택 필드이다. Flutter는 화면 렌더링 전에 세션을 생성하므로 임의의 고정 크기를 보내지 않고 생략한다.
- `canvas`를 전달할 때 `width`, `height`, `backgroundColor`는 각각 양수와 `#RRGGBB` 형식을 만족해야 한다. 이 값은 클라이언트의 논리 화면 설정이며 저장 이미지의 실제 픽셀 크기로 사용하지 않는다.
- 그림 유형의 활성 상태와 유형별 전용 시작 경로를 확인한다. 권장 연령은 활동 시작을 제한하지 않는다.
- 같은 아동에게 복구 가능한 `IN_PROGRESS` 세션이 있으면 `409 ACTIVE_DRAWING_SESSION_EXISTS`와 해당 `drawingSessionId`를 반환한다.

#### 응답 `201`

```json
{
  "drawingSessionId": 100,
  "childId": 1,
  "drawingType": {
    "drawingTypeId": 2,
    "code": "FREE_DRAWING",
    "name": "자유화 활동"
  },
  "inputMethod": "CANVAS",
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "DRAWING",
  "tutorialRequired": false,
  "startedAt": "2026-07-21T02:30:00Z"
}
```

### 10.5 캔버스 행동 배치 저장

#### 요청

```json
{
  "batchSequence": 3,
  "firstEventSequence": 101,
  "lastEventSequence": 101,
  "clientCreatedAt": "2026-07-21T11:32:10.120+09:00",
  "events": [
    {
      "sequence": 101,
      "eventType": "STROKE",
      "tool": "PEN",
      "color": "#FFCC00",
      "width": 8.0,
      "pressure": null,
      "points": [
        { "x": 0.1821, "y": 0.4202, "t": 0 },
        { "x": 0.1840, "y": 0.4230, "t": 16 }
      ]
    }
  ],
  "metrics": {
    "undoCountDelta": 1,
    "redoCountDelta": 0,
    "eraseCountDelta": 2,
    "pauseDurationMsDelta": 3200
  }
}
```

#### 규칙

- `x`, `y`는 캔버스 크기와 무관한 `0~1` 정규화 좌표이다.
- `t`는 이벤트 시작 기준 경과 ms이다.
- 필압 미지원 기기는 `pressure:null`; `0`으로 보내지 않는다.
- Flutter의 `STROKE_START`부터 `STROKE_END`까지는 하나의 `STROKE` 이벤트로 집약하고,
  `sequence`는 원본 `STROKE_END`의 순번을 사용한다.
- `firstEventSequence`와 `lastEventSequence`는 원본 journal 범위가 아니라 실제 전송한
  `events`의 첫 번째·마지막 `sequence`와 같아야 한다. 집약 과정에서 발생한 순번 간격은 허용한다.
- `UNDO`, `REDO`, `ERASE`는 독립 이벤트로 전송하며 `points`는 빈 배열을 허용한다.
  해당 이벤트를 보낸 배치의 `undoCountDelta`, `redoCountDelta`, `eraseCountDelta`도 함께 증가시킨다.
- Draft의 `lastEventSequence`는 Stroke뿐 아니라 `UNDO`, `REDO`, `ERASE`를 포함한 마지막
  journal 이벤트 순번을 사용한다.
- 이벤트 최대 500개, 압축 전 JSON 최대 1 MiB이다.
- 이미 저장된 `batchSequence`와 payload checksum이 같으면 기존 결과를 반환하고, 다르면 `409 STROKE_BATCH_CONFLICT`이다.
- 응답: `batchId`, `batchSequence`, `acceptedEventCount`, `lastEventSequence`, `receivedAt`.

### 10.6 임시 저장

`multipart/form-data`

Header `Idempotency-Key`는 필수이며 8~100자의 영문·숫자·`.`·`_`·`:`·`-`만 허용한다.

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `preview` | image binary | O | 현재 캔버스 미리보기. 서버가 이미지 Header에서 실제 픽셀 크기를 확인한다. |
| `canvasState` | JSON string | O | `lastEventSequence`, `toolState`, `viewport`, `clientSavedAt` |

PUT은 마지막 임시 저장 전체본을 교체한다. 응답은 `drawingAssetId`, `assetVersion`, `lastEventSequence`, `widthPx`, `heightPx`, `savedAt`, `expiresAt`이다.

멱등성 범위는 인증 사용자·HTTP Method·`drawingSessionId`·`Idempotency-Key` 조합이다. 요청
fingerprint에는 `preview` 전체 Byte와 `canvasState` 전체 JSON이 포함된다.

- 동일 Key와 동일 Multipart 요청: 최초 HTTP 200 응답을 재생하고 새 Asset을 만들지 않는다.
- 동일 Key와 다른 `preview` 또는 `canvasState`: `409 IDEMPOTENCY_KEY_REUSED`.
- 동일 요청이 처리 중인 경우 최대 3초 동안 최초 처리를 기다리고, 완료되지 않으면
  `409 DRAFT_SAVE_IN_PROGRESS`. 클라이언트는 잠시 후 동일 Key와 동일 요청으로 재시도한다.
- 완료 응답 보존 TTL은 24시간, 처리 중 선점 TTL은 30초다.
- 새 Snapshot에는 새 Key를 발급하고, 응답 유실 등 동일 Snapshot 재시도에만 기존 Key를 유지한다.
- 다른 Key로 이미 저장된 동일 sequence는 기존 `DRAWING_409_009`, 이전 sequence는
  `DRAWING_409_010` 계약을 유지한다.
- `preview`의 유효 최대 크기는 10 MiB이며 초과하면 `413 STORAGE_413_001`로 거부한다.

GET 응답에는 복구용 `previewUrl`, `canvasState`, `assetVersion`을 포함한다. DELETE는 DRAFT asset과 복구 메타데이터만 제거하고 stroke batch 원본의 보관 여부는 데이터 정책을 따른다.

`widthPx`, `heightPx`는 Storage에 저장한 이미지의 Header에서 검증한 값을 `drawing_assets`에 기록한 결과이다. 신규 업로드에는 값이 저장되지만 기존 데이터와 구버전 Storage Adapter의 호환을 위해 API 타입은 nullable이다. 객체 탐지와 분석에서는 세션 생성의 논리 `canvas`가 아니라 이 검증된 Asset 크기를 사용한다.

### 10.7 종이 그림 업로드

`multipart/form-data`

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `image` | image binary | O | JPEG/PNG/WEBP, 최대 10 MiB. 서버가 이미지 Header에서 실제 픽셀 크기를 확인한다. |
| `metadata` | JSON string | O | `clientCapturedAt?`, `rotationDegrees?`, `cropApplied:boolean` |

Spring Boot는 방향 보정, EXIF 제거, 그림 영역 기본 검증 후 `assetType=UPLOADED`로 저장한다.

```json
{
  "drawingAssetId": 501,
  "assetType": "UPLOADED",
  "previewUrl": "https://signed.example.com/assets/501",
  "width": 1440,
  "height": 1080,
  "mimeType": "image/jpeg",
  "fileSizeBytes": 1425012,
  "qualityWarnings": []
}
```

오류: `IMAGE_TOO_BLURRY`, `DRAWING_REGION_NOT_FOUND`, `IMAGE_DIMENSION_INVALID`, `UPLOAD_FAILED`.

### 10.8 그림 단계 완료

Header `Idempotency-Key` 필수. `multipart/form-data`로 요청한다.

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `finalImage` | image binary | 조건부 | CANVAS이며 기존 FINAL asset이 없을 때 필수 |
| `metadata` | JSON string | O | `sourceAssetId?`, `lastEventSequence?`, `drawingDurationMs`, `clientCompletedAt` |

처리 순서:

1. 최종 이미지와 미수신 stroke 순번을 검증한다.
2. `assetType=FINAL`을 저장한다.
3. `currentStage=ANALYZING`으로 변경한다.
4. `analysisType=OBJECT_DETECTION`, `scope=FINAL`인 대화 준비용 그림 분석을 동기 요청한다. 전체 관찰 리포트 생성은 DRAWING-11에서 시작한다.
5. 대화 준비용 분석의 성공 또는 실패 상태를 저장한 뒤 `currentStage=CONVERSING`으로 변경한다. 실패하면 저장한 FINAL 그림과 실패 이력을 유지하고 폴백 질문을 사용한다.
6. 실제 저장된 분석 결과와 감정 선택 화면으로 이동할 다음 동작을 반환한다.

```json
{
  "drawingSessionId": 100,
  "finalAssetId": 502,
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "CONVERSING",
  "analysis": {
    "analysisId": 700,
    "analysisType": "OBJECT_DETECTION",
    "status": "SUCCEEDED"
  },
  "nextAction": "SELECT_EMOTION"
}
```

분석 서버 호출이 실패한 경우에도 HTTP 요청 자체가 유효하고 실패 이력이 저장되면 `200 OK`를 반환한다.
이때 `analysis.status=FAILED`, `currentStage=CONVERSING`, `nextAction=SELECT_EMOTION`이며 이후 대화는
기존 폴백 질문 정책을 사용한다. 분석 생성 이전의 요청 검증·저장 실패는 해당 오류 응답을 반환한다.

### 10.9 감정·제목 저장

```json
{
  "title": "우리 가족의 공원",
  "selectedEmotions": ["HAPPY", "CALM"],
  "expressedEmotionText": "다 같이 있어서 좋았어",
  "skipped": false
}
```

- 감정은 복수 선택 가능하다.
- `UNKNOWN`은 유효한 응답이며 다른 감정과 동시에 선택할 수 없다.
- 건너뛴 경우 `skipped=true`, 감정 배열은 `[]`, 직접 표현은 `null`이다.
- 보호자가 아동 대신 감정을 추정해 입력하지 않도록 UI에 안내한다.
- 성공 시 `currentStage=REPORTING` 직전 준비 상태인 `REFLECTION`을 반환한다.

### 10.10 전체 활동 완료

Header `Idempotency-Key` 필수. Body는 다음과 같다.

```json
{
  "conversationSkipped": false,
  "requestReport": true
}
```

현재 전체 활동 완료는 관찰 리포트 생성을 포함하는 단일 흐름만 지원하므로 `requestReport`는 반드시 `true`여야 한다. `false`는 `400 DRAWING_400_012`로 거절하며 Analysis, Report, Drawing Session 상태를 변경하지 않는다.

처리 순서:

1. 최종 그림, 종료되었거나 건너뛴 대화, 감정 입력 상태를 검증한다.
2. `currentStage=REPORTING`으로 변경한다.
3. 최종 종합 분석을 `202 Accepted`로 접수한다.
4. 성공 시 리포트를 생성하고 세션을 `COMPLETED/COMPLETED`로 전환한다.
5. 실패해도 그림·대화 원본은 유지하며 재시도 가능 상태를 반환한다.

```json
{
  "drawingSessionId": 100,
  "sessionStatus": "IN_PROGRESS",
  "currentStage": "REPORTING",
  "analysisId": 701,
  "analysisStatus": "PENDING",
  "reportId": 900,
  "reportStatus": "GENERATING"
}
```

### 10.11 세션 조회 응답

`drawingSessionId`, `child`, `drawingType`, `inputMethod`, `title`, `selectedEmotions`, `sessionStatus`, `currentStage`, `latestAsset`, `latestAnalysis`, `conversationId`, `reportId`, `startedAt`, `completedAt`, `recoverableDraft`를 반환한다.

### 10.12 삭제 규칙·오류

- DRAWING-12는 `confirmation:"DELETE"` Body를 받으며 soft delete 후 비동기 파일 삭제를 수행한다.
- 공유 중인 전문가 접근 권한을 즉시 중단한다.
- 오류: `DRAWING_SESSION_NOT_FOUND`, `DRAWING_SESSION_ACCESS_DENIED`, `ACTIVE_DRAWING_SESSION_EXISTS`, `DRAWING_TYPE_NOT_AVAILABLE`, `FINAL_ASSET_REQUIRED`, `STROKE_SEQUENCE_GAP`, `STROKE_BATCH_CONFLICT`, `REFLECTION_REQUIRED`, `DRAWING_SESSION_ALREADY_COMPLETED`, `DRAWING_400_012`(리포트 미요청 완료 거절).

---

## 11. AI 분석 `analysis`

### 11.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| ANALYSIS-01 | POST | `/drawing-sessions/{drawingSessionId}/analyses` | 연결 보호자 | 중간 또는 최종 분석 요청 |
| ANALYSIS-02 | GET | `/analyses/{analysisId}` | 연결 보호자, 공유 전문가 | 분석 상태 폴링·결과 조회 |
| ANALYSIS-03 | POST | `/analyses/{analysisId}/retry` | 연결 보호자 | 실패 분석 재요청 |

### 11.2 분석 요청

Header `Idempotency-Key` 필수.

```json
{
  "analysisType": "INTERMEDIATE",
  "drawingAssetId": 502,
  "triggerReason": "PAUSE",
  "clientContext": {
    "lastEventSequence": 150,
    "changeRatio": 0.23
  }
}
```

`triggerReason`은 공개 API에서 `PAUSE`, `USER_REQUEST`만 허용한다. 마지막 입력 후 3초 무입력
자동 분석은 `PAUSE`를 사용하며, 생략하면 기존 Client 호환을 위해 `USER_REQUEST`로 처리한다.
그림 단계 완료·활동 완료·재시도는 Backend가 각각 `DRAWING_COMPLETE`·`ACTIVITY_COMPLETE`·
`RETRY`로 기록한다.

#### 요청 제어

- `INTERMEDIATE`: 최근 성공 분석 후 기본 5초 이내 재요청을 제한한다.
- 같은 `drawingAssetId`·checksum·analysisType의 중복 요청을 방지한다.
- `FINAL`: 전체 활동 완료 흐름에서만 요청하며 대화·행동 데이터를 포함한다.
- 중간 분석 결과는 질문 생성에 활용할 수 있으나 보호자 리포트로 직접 노출하지 않는다.

#### 응답 `202`

```json
{
  "analysisId": 700,
  "drawingSessionId": 100,
  "analysisType": "INTERMEDIATE",
  "status": "PENDING",
  "pollAfterMs": 1000,
  "requestedAt": "2026-07-21T02:35:00Z"
}
```

### 11.3 분석 조회

진행 중 응답:

```json
{
  "analysisId": 700,
  "analysisType": "INTERMEDIATE",
  "analysisTaskType": "OBJECT_DETECTION",
  "analysisStatus": "PROCESSING",
  "requestedAt": "2026-07-21T02:35:00Z",
  "completedAt": null,
  "detectedObjects": [],
  "errorCode": null,
  "message": null
}
```

완료 응답의 공개 범위는 역할에 따라 다르다.

#### 보호자에게 반환 가능한 필드

```json
{
  "analysisId": 701,
  "analysisType": "FINAL",
  "analysisTaskType": "ACTIVITY_REPORT",
  "analysisStatus": "SUCCESS",
  "detectedObjects": [
    {
      "detectedObjectId": 1,
      "objectCode": "PERSON",
      "objectName": "사람",
      "confidence": 0.95,
      "boundingBox": { "x": 0.15, "y": 0.20, "width": 0.25, "height": 0.50 }
    }
  ],
  "completedAt": "2026-07-21T02:35:04Z",
  "errorCode": null,
  "message": null
}
```

`analysisStatus`는 `PENDING`, `PROCESSING`, `PARTIAL_SUCCESS`, `SUCCESS`, `FAILED` 중 하나다.
`FAILED`도 폴링이 완료된 정상 조회 결과이므로 HTTP 200으로 반환하며, 내부 오류 상세 대신 안전한
`errorCode`와 `message`만 제공한다. 기존 세션 하위 분석 상세 API의 `SUCCEEDED` 상태는 호환을 위해
유지하며 이 정본 URI에서는 사용하지 않는다.

보호자 응답에는 진단형 감정 추정, 질환 가능성, raw risk score, 문헌을 개별 아동에게 적용한 AI 해석 초안을 포함하지 않는다.

#### 공유된 전문가에게 추가 반환하는 필드

- `visualFeatures`: 화면 점유율, 주요 색상, 밝기, 채도, 선 굵기, 밀도 등 객관적 수치.
- `behaviorFeatures`: 소요 시간, 활성 그리기 시간, pause·undo·erase·도구 변경·색상 변경·필압 통계.
- `conversationSummary`: 주제·실제 대표 발화·미응답 항목. 실제 발화와 AI 요약을 구분.
- `observationDraft`: `overallSummary`, `attentionPoints`, `followUpQuestions`, `uncertainty`, `reviewStatus=AI_DRAFT`.
- `evidenceReferences`: RAG 출처와 적용 한계.
- `unusedInputs`: 제외한 입력과 제외 사유.
- `modelInfo`: 객체 탐지·VLM·LLM·RAG knowledge base 버전.

### 11.4 부분 성공

`PARTIAL_SUCCESS`일 때 `usedInputs[]`, `unusedInputs[]`, `limitations[]`를 반드시 반환한다. 예를 들어 STT가 실패했으면 음성 내용을 추정하지 않고 선택형 답변과 그림만 사용한다.

### 11.5 재시도

`POST /api/v1/analyses/{analysisId}/retry`는 `Idempotency-Key` Header를 필수로 받는다.
같은 Key와 같은 원본 분석의 재호출은 최초 결과를 반환하며 다른 원본 분석에 같은 Key를 사용하면
`ANALYSIS_409_004`로 거부한다.

```json
{
  "reason": "USER_REQUEST",
  "useLatestInputs": true
}
```

- 원본 분석 ID는 `retryOfAnalysisId`에 저장한다.
- 실패 분석의 재시도 이력은 선형으로 유지하며 최초 분석 이후 최대 3회까지만 허용한다.
- 네 번째 재시도는 `ANALYSIS_409_005`로 거부하고 성공한 최종 분석은 재시도하지 않는다.
- 재시도가 새 리포트를 만들면 `reportVersion`을 증가시키고 이전 버전을 감사 목적으로 유지한다.

### 11.6 오류

| 코드 | HTTP | 의미 |
| --- | --- | --- |
| `ANALYSIS_NOT_FOUND` | 404 | 분석 없음 |
| `ANALYSIS_THROTTLED` | 429 | 너무 짧은 간격의 중간 분석 |
| `ANALYSIS_DUPLICATED` | 409 | 동일 입력이 이미 접수됨 |
| `ANALYSIS_INPUT_INSUFFICIENT` | 422 | 분석 가능한 그림 요소 부족 |
| `IMAGE_QUALITY_INSUFFICIENT` | 422 | 이미지 품질 부족 |
| `AI_SERVER_UNAVAILABLE` | 503 | AI 서버 사용 불가 |
| `ANALYSIS_LOW_CONFIDENCE` | 200 | 실패가 아니라 제한사항으로 반환. 진단을 생성하지 않음 |
| `ANALYSIS_RETRY_NOT_ALLOWED` | 409 | 현재 상태에서 재시도 불가 |

---

## 12. AI 대화 `conversation`

### 12.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| CONV-01 | POST | `/drawing-sessions/{drawingSessionId}/conversations` | 연결 보호자 | 대화 세션 시작 |
| CONV-02 | GET | `/conversations/{conversationId}/messages` | 연결 보호자, 공유 전문가 | 대화 기록 페이지 조회 |
| CONV-03 | POST | `/conversations/{conversationId}/next-question` | 연결 보호자 | 다음 질문 생성 |
| CONV-04 | POST | `/conversation-messages/{messageId}/tts` | 연결 보호자 | 질문 음성 생성·조회 |
| CONV-05 | POST | `/conversations/{conversationId}/answers/voice` | 연결 보호자 | 음성 답변·STT 제출 |
| CONV-06 | POST | `/conversations/{conversationId}/answers/option` | 연결 보호자 | 이모지·색상·그림·문장 선택 답변 |
| CONV-07 | GET | `/conversations/{conversationId}/fallback-questions` | 연결 보호자 | AI·STT 실패 시 기본 질문 조회 |
| CONV-08 | POST | `/conversations/{conversationId}/skip` | 연결 보호자 | 질문 건너뛰기·다시 그리기 |
| CONV-09 | POST | `/conversations/{conversationId}/end` | 연결 보호자 | 대화 세션 종료 |

### 12.2 대화 시작

```json
{
  "analysisId": 700,
  "maxQuestionCount": 5
}
```

- 현재 단계가 `ANALYZING` 또는 `CONVERSING`일 때만 가능하다.
- 아동의 `questionDifficulty`를 `difficultySnapshot`으로 저장한다.
- `maxQuestionCount`는 서버 상한 10을 넘을 수 없다.
- 기존 진행 중 대화가 있으면 새로 만들지 않고 `409 ACTIVE_CONVERSATION_EXISTS`와 기존 ID를 반환한다.

```json
{
  "conversationId": 800,
  "drawingSessionId": 100,
  "status": "CONVERSING",
  "difficulty": "LOWER_ELEMENTARY",
  "maxQuestionCount": 5,
  "questionCount": 0,
  "nextAction": "REQUEST_NEXT_QUESTION"
}
```

#### 12.2-A 282번 구현 반영 사항 (문서 기준)

- 구현 기준 경로는 `POST /api/v1/drawing-sessions/{drawingSessionId}/conversations`이다. 구형 단수형 경로(`/conversation`)는 사용하지 않는다.
- 구현 DTO는 `analysisId`(양의 정수)와 `maxQuestionCount`(양의 정수, 최대 10)를 보유하며, `maxQuestionCount` 생략 시 서버 기본값 10을 적용한다.
- 성공은 `201 Created`이며 `Location: /api/v1/conversations/{conversationId}`를 반환한다. 응답에는 `conversationId`, `drawingSessionId`, `status`, `difficulty`, `maxQuestionCount`, `questionCount`, `nextAction`, `startedAt`이 포함된다.
- 기존 진행 대화는 `409 ACTIVE_CONVERSATION_EXISTS`와 `data.conversationId`로 기존 ID를 반환한다. 세션 생성 경합은 `409 CONVERSATION_START_CONFLICT`로 처리한다.
- `Idempotency-Key`는 구현상 필수다. 동일 보호자·URI·키·Body는 최초 HTTP 응답을 재생하고, 다른 Body 재사용은 `409 IDEMPOTENCY_KEY_REUSED`다. 처리 중 요청은 제한 시간 후 `409 CONVERSATION_START_CONFLICT`가 된다. Redis 장애 시 DB의 `uk_conversation_sessions_drawing_session_id`가 중복 생성을 최종 방어한다.
- 구현에는 정식 JWT 도입 전 임시 `X-Guardian-User-Id` 식별 경계가 남아 있다. 이 Header는 최종 외부 인증 계약이 아니며, 정식 JWT `Authentication` 전환 전까지 보안 검증 완료로 판정하지 않는다.

#### 12.2-B 구현과 추가 확인이 필요한 차이

- Controller가 `@RequestBody(required=false)`를 사용하고 DTO의 `analysisId`에 `@NotNull`이 없어 body/analysisId 누락이 Bean Validation에서 차단되지 않을 수 있다. 최종 계약에서 두 필드의 필수 여부를 확정하고 DTO 검증을 일치시켜야 한다.
- `startedAt`은 구현 응답에 추가된 필드다. 공개 응답에 유지할지 버전 호환성을 문서 담당자와 백엔드 검증자가 확인한다.

### 12.3 다음 질문

Header `Idempotency-Key` 필수.

```json
{
  "basisAnalysisId": 700,
  "previousAnswerMessageId": 802,
  "preferredResponseModes": ["VOICE", "EMOJI", "COLOR"]
}
```

응답은 생성된 AI 질문 메시지이다.

```json
{
  "messageId": 803,
  "conversationId": 800,
  "sequence": 3,
  "senderType": "AI",
  "messageType": "QUESTION",
  "text": "이 사람은 지금 어떤 기분인 것 같아?",
  "options": [
    { "optionId": "happy", "type": "EMOTION", "label": "기뻐요", "value": "HAPPY", "emoji": "🙂" },
    { "optionId": "unknown", "type": "EMOTION", "label": "잘 모르겠어요", "value": "UNKNOWN", "emoji": "🤔" }
  ],
  "targetObject": {
    "detectedObjectId": 1,
    "objectCode": "PERSON",
    "boundingBox": { "x": 0.15, "y": 0.20, "width": 0.25, "height": 0.50 }
  },
  "ttsAvailable": true,
  "createdAt": "2026-07-21T02:36:00Z"
}
```

질문은 한 번에 하나, 짧은 문장, 비유도·비단정이어야 한다. 개인정보, 죄책감, 진단을 유도하는 질문은 생성하지 않는다.

### 12.4 TTS

```json
{
  "voice": "CHILD_FRIENDLY_01",
  "speed": 0.95
}
```

- `speed`는 `0.8~1.2`.
- 같은 메시지·voice·speed 결과는 캐시한다.
- 응답: `audioUrl`, `expiresAt`, `durationMs`, `subtitle`.
- TTS 재생 중 프론트는 마이크를 비활성화하고 재생 종료 후 입력을 활성화한다.

### 12.5 음성 답변

`multipart/form-data`

| Part | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `audio` | audio binary | O | 최대 20 MiB·60초 |
| `metadata` | JSON string | O | `questionMessageId`, `clientStartedAt`, `clientEndedAt`, `stopReason` |

`stopReason`: `SILENCE`, `USER_FINISH`, `TIMEOUT`.

```json
{
  "messageId": 804,
  "parentMessageId": 803,
  "sequence": 4,
  "senderType": "CHILD",
  "messageType": "ANSWER_VOICE",
  "rawText": null,
  "sttText": "친구랑 같이 있어서 좋아",
  "speechStatus": "SUCCESS",
  "sttConfidence": 0.91,
  "needsGuardianConfirmation": false,
  "createdAt": "2026-07-21T02:36:12Z"
}
```

음성 원본 보관 정책은 동의 설정에 따른다. 원본을 삭제해도 STT 텍스트와 삭제 시각을 감사 가능한 형태로 남긴다.

> ✅ **정정 (2026-07-26)**: 위 응답 예시의 `messageType`을 DB 값 `VOICE_ANSWER` → 공개 값 `ANSWER_VOICE`로 수정했다. `docs/api/conversation-option-answer-contract.md` §3 확정(2026-07-23, QA 반영) "공개 API는 공개 Enum 값을 노출한다"와 §4 공개↔DB 매핑표를 따른 것이며, 같은 문서가 이 예시를 명세 측 불일치로 지목하고 통일을 권고했다. DB `conversation_messages.message_type` CHECK 값은 `VOICE_ANSWER`로 그대로다(§Enum 사전). 조회·폴링 응답은 이미 공개 값을 노출했고 업로드 201 응답만 DB 값을 내보내던 불일치를 코드에서도 함께 정합화했다(S15P11B209-158 후속).

### 12.6 선택형 답변

```json
{
  "questionMessageId": 803,
  "selectedOptions": [
    { "optionId": "happy", "type": "EMOTION", "value": "HAPPY", "labelSnapshot": "기뻐요" }
  ],
  "directText": null
}
```

질문에 포함되지 않은 option은 거부한다. `labelSnapshot`은 화면에 실제 노출된 문구를 기록하기 위한 값이며 서버의 option과 일치해야 한다.

### 12.7 폴백 질문

Query: `drawingTypeCode?`, `difficulty?`, `reason=STT_FAILED|AI_FAILED|TIMEOUT`, `limit=3`.

응답 질문은 `ai_question_templates(templateType=FALLBACK)`에서 조회한다. 프론트에서 하드코딩하지 않는다.

### 12.8 건너뛰기·종료

건너뛰기 요청:

```json
{
  "questionMessageId": 803,
  "reason": "CHILD_REQUEST",
  "returnToDrawing": true
}
```

`returnToDrawing=true`이면 세션의 `currentStage=DRAWING`, 아니면 대화 상태를 유지한다.

건너뛰기 as-built(2026-07-29 · `S15P11B209-699`): `Idempotency-Key` Header는 필수이며 같은 키·같은 Body 재전송은
최초 응답을 재생한다. 저장은 `conversation_messages.is_skipped=TRUE` 하나이며 질문 수·대화 상태·그림 단계는 바뀌지 않는다.
응답은 `conversationId`, `questionMessageId`, `skipped`, `alreadySkipped`, `skippedQuestionCount`, `conversationStatus`다.
이미 건너뛴 질문의 재요청은 오류가 아니라 같은 결과를 반환한다. `reason`은 저장 컬럼이 없어 이력으로 남지 않는 관측 정보다.
**`returnToDrawing=true`는 아직 지원하지 않고 `409 QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED`로 거절한다** —
대화에서 그림 단계로의 역방향 전이는 이어그리기 저장 경로(`S15P11B209-682`)와 함께 다뤄야 한다.

대화 종료 요청:

```json
{
  "reason": "QUESTION_LIMIT_REACHED",
  "lastQuestionMessageId": 803
}
```

`Idempotency-Key` Header는 필수다. 허용 reason은 `QUESTION_LIMIT_REACHED`, `CHILD_REQUEST`, `GUARDIAN_REQUEST`, `NO_MORE_QUESTION`이다.
`lastQuestionMessageId`는 선택 필드이며 전달하면 해당 대화의 최신 질문과 일치해야 한다. 성공 시 대화 `COMPLETED`, 그림 세션
`currentStage=REFLECTION`으로 변경한다.

### 12.9 메시지 조회

Query: `page=0`, `size=50`, `afterSequence?`. 응답은 sequence 오름차순이며 `rawText`, `sttText`, `options`, `selectedResponse`, `targetObject`, `boundingBox`, `isSkipped`, `createdAt`을 포함한다. 전문가는 유효한 리포트 공유 권한이 있을 때만 조회한다.

### 12.10 오류

`CONVERSATION_NOT_FOUND`, `ACTIVE_CONVERSATION_EXISTS`, `QUESTION_LIMIT_REACHED`, `QUESTION_MESSAGE_NOT_FOUND`, `ANSWER_ALREADY_SUBMITTED`, `OPTION_NOT_ALLOWED`, `STT_FAILED`, `TTS_FAILED`, `VOICE_CONSENT_REQUIRED`, `CONVERSATION_ALREADY_COMPLETED`, `CONVERSATION_NOT_CONVERSING`, `QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED`, `QUESTION_SKIP_CONFLICT`.

---

## 13. 리포트 `report`

### 13.1 리포트 계층

| 계층 | 상태·용도 | 접근자 |
| --- | --- | --- |
| `ParentActivityReport` | 아동의 활동 사실·실제 표현·보호자 대화 가이드 | 연결 보호자 |
| `ExpertReviewMaterial` | raw feature, AI 관찰 초안, RAG 근거, 불확실성 | 공유 승인을 받은 검증 전문가 |
| `ExpertReview` | 전문가가 작성한 별도 검토 의견 | 작성 전문가와 공유 보호자 |

AI 초안과 전문가 의견을 같은 필드에 덮어쓰지 않는다. `reports`는 보호자용 조립 결과를 저장하고, 전문가용 원자료는 `analyses` 하위 특징·근거 데이터에서 조회한다.

### 13.2 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| REPORT-01 | GET | `/children/{childId}/reports` | 연결 보호자 | 아동별 리포트 목록 |
| REPORT-02 | GET | `/reports/{reportId}` | 연결 보호자 | 보호자용 활동 리포트 상세 |
| REPORT-03 | GET | `/expert/reports/{reportId}` | 공유 승인 EXPERT | 전문가용 검토 자료 상세 |
| REPORT-04 | POST | `/reports/{reportId}/exports` | 연결 보호자 | PDF 내보내기 생성 요청 |
| REPORT-05 | GET | `/reports/{reportId}/exports/{exportId}` | 연결 보호자 | PDF 생성 상태·다운로드 URL 조회 |
| REPORT-06 | GET | `/reports/{reportId}/generation-status` | 연결 보호자 | 리포트 생성 상태·재시도 가능 여부 조회 |
| REPORT-07 | POST | `/reports/{reportId}/regenerate` | 연결 보호자 | 실패한 최신 리포트 생성 재접수 |

부적절한 리포트 신고는 공통 신고 API `POST /complaints`를 사용한다.

REPORT-04는 `Idempotency-Key` Header를 필수로 받고 HTTP 202로 내보내기 상태를 반환한다.
보호자용 리포트가 `COMPLETED`가 아니면 `REPORT_EXPORT_409_001`로 거부한다. 현재 PDF는
보호자 안전 필드만 포함하는 확정 리포트 버전에서 즉시 생성할 수 있으므로 상태는
`COMPLETED`이며, 동일 리포트의 `reportId`를 안정적인 `exportId`로 사용한다.

```json
{
  "reportId": 900,
  "exportId": 900,
  "status": "COMPLETED",
  "downloadUrl": "/api/v1/reports/900/exports/900/file"
}
```

REPORT-05의 `downloadUrl`은 presigned URL이 아니라 JWT 인증이 필요한 Backend proxy URI다.
`GET /reports/{reportId}/exports/{exportId}/file`은 `application/pdf`와 attachment
`Content-Disposition`으로 파일을 반환한다. 모든 상태 조회와 파일 조회에서 보호자-아동
연결 관계를 다시 검증하며 URL 자체의 만료 시각은 없지만 유효한 인증 없이는 사용할 수 없다.

### 13.3 리포트 목록 Query

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `from`, `to` | date | 활동일 범위. `from <= to`, 최대 1년 |
| `drawingTypeCode` | string | 그림 유형 코드 |
| `reportStatus` | `ReportStatus` | 상태 필터 |
| `page`, `size` | integer | 기본 0, 20 |

목록 항목은 `reportId`, `reportVersion`, `drawingSessionId`, `drawingType`, `title`, `thumbnailUrl`, `activityDate`, `durationMs`, `selectedEmotions`, `reportStatus`, `expertReviewAvailable`을 반환한다.

### 13.4 보호자용 리포트 응답

```json
{
  "reportId": 900,
  "reportVersion": 1,
  "reportStatus": "COMPLETED",
  "drawingSession": {
    "drawingSessionId": 100,
    "childId": 1,
    "drawingTypeCode": "FREE_DRAWING",
    "drawingTypeName": "자유화 활동",
    "title": "우리 가족의 공원",
    "inputMethod": "CANVAS",
    "startedAt": "2026-07-21T02:30:00Z",
    "completedAt": "2026-07-21T02:40:00Z",
    "durationMs": 600000
  },
  "drawing": {
    "finalImageUrl": "https://signed.example.com/assets/502",
    "thumbnailUrl": "https://signed.example.com/assets/503"
  },
  "childExpression": {
    "selectedEmotions": ["HAPPY", "CALM"],
    "expressedEmotionText": "다 같이 있어서 좋았어",
    "representativeUtterances": [
      {
        "messageId": 804,
        "text": "친구랑 같이 있어서 좋아",
        "source": "STT",
        "sttNeedsConfirmation": false
      }
    ]
  },
  "activityFacts": {
    "detectedObjects": ["사람", "나무", "해"],
    "drawingDurationMs": 600000,
    "pauseCount": 4,
    "eraseCount": 3,
    "pressureAvailable": false,
    "notes": ["필압을 지원하지 않는 기기에서 그렸습니다."]
  },
  "conversationSummary": {
    "questionCount": 4,
    "answeredCount": 3,
    "skippedCount": 1,
    "summary": "아동은 공원과 함께 있는 사람들에 관해 이야기했습니다."
  },
  "guardianConversationGuide": [
    "그림에서 가장 즐거웠던 장면을 아이에게 다시 물어보세요.",
    "아이의 답을 맞거나 틀리다고 판단하지 말고 그대로 들어주세요."
  ],
  "limitations": [
    "이 리포트는 아동의 심리 상태를 진단하는 자료가 아닙니다.",
    "한 번의 그림 활동만으로 아동의 상태나 원인을 판단할 수 없습니다."
  ],
  "expertReview": {
    "status": "NOT_REQUESTED",
    "available": false
  },
  "createdAt": "2026-07-21T02:40:05Z"
}
```

#### 보호자 응답 금지 필드

- `observedEmotion`, `emotionConfidence`처럼 AI가 추정한 감정과 확률.
- 질환·장애·가정 문제·성격에 대한 분류나 점수.
- 전문가 검토 전 `attentionPoints`, raw risk score, 내부 프롬프트.
- RAG 문헌을 해당 아동에 직접 적용한 해석 문장.
- 보호자가 확인할 방법이 없는 모델 내부 지표.

행동 수치는 객관적 활동 기록으로만 설명한다. 예: “멈춤 4회”는 가능하지만 “망설임이 많아 불안함”은 금지한다.

### 13.5 전문가용 검토 자료 응답

REPORT-03은 `CONSENT_EXPERT_REPORT_SHARE` 동의, 유효한 공유 기간, 전문가 검증 상태를 모두 확인한다.

```json
{
  "reportId": 900,
  "reportVersion": 1,
  "parentReport": { "reportId": 900 },
  "sourceData": {
    "drawingAsset": {
      "drawingAssetId": 502,
      "imageUrl": "https://signed.example.com/assets/502",
      "width": 1920,
      "height": 1080
    },
    "detectedObjects": [],
    "visualFeatures": {},
    "behaviorFeatures": {
      "drawingDurationMs": 600000,
      "activeDrawingDurationMs": 410000,
      "pauseCount": 4,
      "totalPauseDurationMs": 52000,
      "undoCount": 2,
      "eraseCount": 3,
      "averagePressure": null,
      "pressureDeviation": null,
      "pressureAvailable": false
    },
    "conversation": {
      "messages": [],
      "summary": {},
      "unrecognizedSpeechCount": 1
    },
    "unusedInputs": [
      {
        "sourceType": "PRESSURE",
        "reasonCode": "DEVICE_NOT_SUPPORTED",
        "retryable": false
      }
    ]
  },
  "aiObservationDraft": {
    "status": "AI_DRAFT",
    "summary": "그림과 대화에서 확인된 내용을 검토용으로 정리한 초안입니다.",
    "observations": [],
    "followUpQuestions": [],
    "uncertainty": "한 번의 활동이며 필압 데이터가 없어 해석 범위가 제한됩니다.",
    "expertReviewRequired": true
  },
  "evidenceReferences": [
    {
      "sourceId": "KB-ART-001",
      "title": "아동 그림 면담 시 비유도 질문 지침",
      "authors": ["Author A"],
      "publishedYear": 2024,
      "section": "3.2",
      "evidenceType": "PRACTICE_GUIDELINE",
      "applicability": "추가 질문 문장 구성에만 사용",
      "limitations": "개별 아동의 진단 근거로 사용할 수 없음",
      "knowledgeBaseVersion": "2026.07",
      "retrievedChunkHash": "sha256-value"
    }
  ],
  "modelInfo": {
    "objectDetection": "yolo-model:1.0.0",
    "vision": "vision-model:1.0.0",
    "language": "llm-model:1.0.0",
    "knowledgeBase": "2026.07"
  }
}
```

### 13.6 전문가 검토 표시 규칙

- 전문가 검토 의견은 AI 초안과 다른 카드·색상·제목으로 표시한다.
- 검토 완료 전 보호자 화면에는 `전문가 검토 대기 중`만 표시하며 AI 초안을 노출하지 않는다.
- 검토자가 `INSUFFICIENT_INFORMATION`을 선택할 수 있어야 하며 억지로 결론을 작성하게 하지 않는다.
- 전문가 의견도 의료 진단이 필요한 경우 적절한 의료·상담 절차를 안내할 뿐 서비스 내에서 진단명으로 저장하지 않는다.

### 13.7 PDF 내보내기

REPORT-04 요청:

```json
{
  "includeExpertReview": true,
  "maskChildNickname": true
}
```

- 전문가 의견을 포함하려면 검토가 완료되었고 보호자가 해당 의견의 수신자여야 한다.
- `202` 응답: `exportId`, `status=GENERATING`, `pollAfterMs`.
- REPORT-05 완료 응답: `exportId`, `status=COMPLETED`, `downloadUrl`, `expiresAt`.
- PDF 모든 페이지에 “진단 결과가 아닌 참고용 활동 기록” 문구를 표시한다.

### 13.8 생성 상태 조회·재생성

REPORT-06은 상세 리포트 본문을 조립하지 않고 생성 작업 확인에 필요한 다음 필드만 반환한다.

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `reportId` | long | 조회한 리포트 ID |
| `drawingSessionId` | long | 리포트가 속한 그림 활동 세션 ID |
| `analysisId` | long | 리포트 생성에 사용되는 최종 분석 ID |
| `reportVersion` | integer | 세션 내 리포트 버전 |
| `reportStatus` | `ReportStatus` | `GENERATING`, `COMPLETED`, `FAILED`, `HIDDEN` |
| `retryable` | boolean | 해당 리포트가 최신 버전의 `FAILED` 리포트인지 여부 |
| `failureReason` | string, nullable | 개인정보를 포함하지 않는 실패 분류 코드 |
| `createdAt`, `updatedAt` | datetime | 생성 접수·최종 상태 변경 시각 |
| `failedAt` | datetime, nullable | 실패 시각 |

REPORT-07은 Request Body 없이 `Idempotency-Key` Header를 필수로 받는다.

- 최신 버전이면서 `FAILED`인 리포트만 재생성할 수 있다.
- 성공 시 기존 리포트를 덮어쓰지 않고 `reportVersion`을 1 증가시킨 `GENERATING` 리포트와 재시도 분석을 생성한다.
- 동일한 `Idempotency-Key`와 동일한 원본 리포트로 재호출하면 최초 접수 결과를 반환한다.
- `202 Accepted`와 새 리포트 상태를 반환하며 `Location` Header는 `/api/v1/reports/{newReportId}/generation-status`이다.
- 생성 작업은 Transaction Commit 후 기존 비동기 리포트 생성 흐름으로 전달된다.

### 13.9 오류

`REPORT_NOT_FOUND`, `REPORT_NOT_READY`, `REPORT_ACCESS_DENIED`, `EXPERT_SHARE_CONSENT_REQUIRED`, `EXPERT_SHARE_EXPIRED`, `EXPERT_NOT_VERIFIED`, `REPORT_EXPORT_FAILED`, `REPORT_400_001`(Idempotency-Key 누락), `REPORT_400_002`(Idempotency-Key 형식 오류), `REPORT_409_002`(멱등 키 충돌), `REPORT_409_003`(재생성 불가 상태), `REPORT_409_004`(FINAL Asset 없음), `REPORT_409_005`(동시 재생성 충돌).

---

## 14. 활동 기록 `history`

활동 기록은 별도 `activities` 테이블이 아니라 `drawing_sessions`를 기준으로 조회하는 read model이다.

### 14.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| HISTORY-01 | GET | `/children/{childId}/drawing-sessions` | 연결 보호자 | 활동 목록 조회·필터 |
| HISTORY-02 | GET | `/drawing-sessions/{drawingSessionId}` | 연결 보호자, 공유 전문가 | 활동 상세 조회. DRAWING-03과 동일 계약 |
| HISTORY-03 | DELETE | `/drawing-sessions/{drawingSessionId}` | 연결 보호자 | 활동 삭제. DRAWING-12와 동일 계약 |

### 14.2 목록 Query

| 필드 | 타입 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `from`, `to` | date | 없음 | 활동 시작일 범위 |
| `drawingTypeCode` | string | 없음 | 그림 유형 |
| `sessionStatus` | `DrawingSessionStatus` | 없음 | 상태 |
| `reportStatus` | `ReportStatus` | 없음 | 리포트 상태 |
| `page`, `size` | integer | `0`, `20` | 페이지 |
| `sort` | string | `startedAt,desc` | `startedAt`, `completedAt`만 허용 |

목록 항목: `drawingSessionId`, `thumbnailUrl`, `drawingType`, `title`, `inputMethod`, `sessionStatus`, `currentStage`, `selectedEmotions`, `analysisStatus`, `reportId`, `reportStatus`, `startedAt`, `completedAt`.

---

## 15. 알림 `notification`

### 15.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| NOTI-01 | POST | `/notifications/device-tokens` | 로그인 사용자 | 푸시 디바이스 토큰 등록·갱신 |
| NOTI-02 | DELETE | `/notifications/device-tokens/{deviceId}` | 로그인 사용자 | 기기 토큰 해제 |
| NOTI-03 | GET | `/notifications` | 로그인 사용자 | 알림 목록 조회 |
| NOTI-04 | PATCH | `/notifications/{notificationId}/read` | 수신자 | 단건 읽음 처리 |
| NOTI-05 | PATCH | `/notifications/read-all` | 로그인 사용자 | 전체 또는 유형별 읽음 처리 |

### 15.2 디바이스 토큰

```json
{
  "deviceId": "installation-uuid",
  "platform": "ANDROID",
  "pushToken": "fcm-or-apns-token",
  "appVersion": "1.0.0"
}
```

`platform`: `ANDROID`, `IOS`, `WEB`. 동일 deviceId는 upsert한다. 로그아웃 시 해당 기기 토큰을 비활성화할지 사용자 설정에 따라 처리하되 Refresh Token과 Push Token을 혼동하지 않는다.

### 15.3 목록 Query·응답

- Query: `type?`, `unreadOnly=false`, `page=0`, `size=20`.
- 항목: `notificationId`, `type`, `title`, `content`, `relatedResourceType`, `relatedResourceId`, `data`, `deliveryStatus`, `readAt`, `sentAt`, `createdAt`.
- 알림의 이동 경로는 서버가 임의 URL 대신 `relatedResourceType`과 `relatedResourceId`로 제공하고 프론트가 라우팅한다.

### 15.4 위험 관련 알림

- `RISK_REVIEW_GUIDE`는 위험을 확정하는 알림이 아니다.
- 보호자에게 관찰된 실제 표현, 중립적인 확인 질문, 전문가 상담 또는 긴급 지원 안내만 제공한다.
- 아동 화면에는 위험 분류나 보호자 알림 발송 여부를 노출하지 않는다.
- raw risk score는 알림 `data`에 포함하지 않는다.

### 15.5 오류

`DEVICE_TOKEN_INVALID`, `NOTIFICATION_NOT_FOUND`, `NOTIFICATION_ACCESS_DENIED`.

---

## 16. 커뮤니티 `community`

커뮤니티는 보호자·전문가 중심이며 아동이 게시글·댓글·채팅을 직접 작성하지 않는다. AI 분석 결과와 대화 원문은 게시글 첨부로 허용하지 않는다.

### 16.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| COMM-01 | GET | `/posts` | 로그인 사용자 | 게시글 목록·팔로우 피드 |
| COMM-02 | POST | `/posts` | GUARDIAN, EXPERT, ADMIN | 게시글 작성 |
| COMM-03 | GET | `/posts/{postId}` | 로그인 사용자 | 게시글 상세 |
| COMM-04 | PATCH | `/posts/{postId}` | 작성자 | 게시글 수정 |
| COMM-05 | DELETE | `/posts/{postId}` | 작성자, ADMIN | 게시글 삭제 |
| COMM-06 | POST | `/posts/{postId}/likes` | GUARDIAN, EXPERT | 좋아요 등록 |
| COMM-07 | DELETE | `/posts/{postId}/likes` | GUARDIAN, EXPERT | 좋아요 취소 |
| COMM-08 | POST | `/posts/{postId}/comments` | 권한 보유 사용자 | 댓글·전문가 답변 작성 |
| COMM-09 | PATCH | `/comments/{commentId}` | 작성자 | 댓글 수정 |
| COMM-10 | DELETE | `/comments/{commentId}` | 작성자, ADMIN | 댓글 삭제 |
| COMM-11 | POST | `/complaints` | 로그인 사용자 | 게시글·댓글·리포트·AI 질문 신고 |
| COMM-12 | GET | `/activity-templates` | 로그인 사용자 | 미술 활동 템플릿 목록 |
| COMM-13 | GET | `/activity-templates/{templateId}` | 로그인 사용자 | 템플릿 상세 |
| COMM-14 | POST | `/activity-templates` | VERIFIED EXPERT, ADMIN | 템플릿 등록 |
| COMM-15 | PATCH | `/activity-templates/{templateId}` | 작성 전문가, ADMIN | 템플릿 수정·비활성화 |
| COMM-16 | GET | `/posts/{postId}/comments` | 로그인 사용자 | 게시글 댓글 목록 조회 |

전문가 팔로우는 전문가 도메인의 EXPERT-07·08을 사용한다.

### 16.2 게시글 목록 Query

| 필드 | 타입 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `type` | `PostType` | 없음 | 유형 필터 |
| `keyword` | string | 없음 | 제목·내용 검색, 최대 100자 |
| `feed` | string | `ALL` | `ALL`, `FOLLOWING` |
| `authorRole` | `UserRole` | 없음 | GUARDIAN 또는 EXPERT |
| `page`, `size` | integer | `0`, `20` | 페이지 |
| `sort` | string | `createdAt,desc` | `createdAt`, `likeCount`만 허용 |

목록 응답 항목: `postId`, `postType`, `title`, `contentPreview`, `author`, `anonymous`, `likeCount`, `commentCount`, `likedByMe`, `createdAt`, `updatedAt`.

익명 글이어도 서버·관리자 감사 기록에는 작성자 ID를 유지한다. 일반 응답은 `authorId:null`, `displayName:"익명 보호자"`로 반환한다.

#### 16.2-A COMM-01 구현 정합성 보완 (S15P11B209-165)

- 구현 기준 Query 이름은 `feed`이다. 구형 `following=true` 표현은 문서·클라이언트 호환을 위해 deprecated로만 기록하며 신규 구현에서 사용하지 않는다.
- `type`은 DB v1.2 `community_posts.post_type` CHECK와 동일한 `GUARDIAN_STORY`, `ACTIVITY_REVIEW`, `EXPERT_COLUMN`, `ART_RESOURCE`, `DRAWING_GUIDE`, `EXPERT_QNA`, `NOTICE`만 허용한다. 구형 `STORY`, `COLUMN`, `QNA` 값은 변환하지 않고 `VALIDATION_FAILED`로 거부한다.
- 일반 목록의 기본 조건은 `post_status=ACTIVE AND is_visible=true AND deleted_at IS NULL`이다. `HIDDEN`, `DELETED`, 비공개 글은 COMM-01에서 제외하며 관리자 moderation 예외는 별도 관리자 API에서 정의한다.
- `feed=FOLLOWING`은 보호자(`GUARDIAN`)가 팔로우한 전문가의 게시글만 조회한다. `expert_follows.guardian_user_id → expert_profiles.user_id → community_posts.author_user_id` 관계를 사용한다. 전문가·관리자 요청의 FOLLOWING 피드는 지원하지 않으며 `VALIDATION_FAILED`로 처리한다.
- `keyword`는 제목·내용 부분 검색이며 trim 후 빈 값은 미적용으로 취급하고 100자를 초과하면 `VALIDATION_FAILED`를 반환한다. DB/문자열 검색 방식의 세부 최적화는 구현자가 선택하되 API 의미를 변경하지 않는다.
- `page`는 0 이상, `size`는 1~100이며 기본값은 각각 0·20이다. `sort`는 `createdAt` 또는 `likeCount`와 `asc|desc` 조합만 허용하고 기본은 `createdAt,desc`이다. 같은 정렬값의 tie-breaker는 `postId` 내림차순을 사용해 페이지 중복·누락을 방지한다.
- 목록 항목의 `likeCount`는 `post_likes` 집계, `commentCount`는 `comments.comment_status=ACTIVE AND is_visible=true` 집계, `likedByMe`는 현재 인증 사용자와 `(post_id,user_id)` 존재 여부로 계산한다. 별도 count 컬럼은 추가하지 않는다.
- `author`는 비익명 글에서만 역할에 맞는 공개 표시 정보를 제공한다. 익명 글은 `authorId:null`, `displayName:"익명 보호자"`로 마스킹하며 원 작성자 ID는 서버 감사·관리 목적에만 보존한다. AI 분석·대화·리포트 원문은 목록 응답에 포함하지 않는다.
- `contentPreview`는 `content` 전체를 노출하지 않는 목록용 미리보기다. 최대 길이와 말줄임 표시는 클라이언트 표시 정책과 확인 후 고정하며, 구현자는 임의로 API 필드 의미를 변경하지 않는다.
- 성공 응답은 공통 페이지 형식(`content`, `page`, `size`, `totalElements`, `totalPages`, `first`, `last`, `hasNext`)을 사용한다. 결과가 없으면 404가 아니라 200과 빈 `content`를 반환한다.

### 16.3 게시글 작성·수정

```json
{
  "postType": "GUARDIAN_STORY",
  "title": "아이와 자유화를 해본 후기",
  "content": "오늘은 아이가 고른 주제로 그림을 그렸습니다.",
  "anonymous": true,
  "templateData": null,
  "attachments": [
    { "fileId": "community-file-uuid", "type": "IMAGE" }
  ]
}
```

- 제목 1~200자, 내용 1~20,000자, 이미지 최대 5개.
- `NOTICE`는 ADMIN만 작성한다.
- `EXPERT_COLUMN`, `ART_RESOURCE`, `DRAWING_GUIDE`는 검증 전문가 또는 ADMIN만 작성한다.
- 아동 실명·학교·주소·연락처, 분석 리포트 원문, 대화 원문을 탐지해 경고·차단한다.
- 아동 그림 첨부는 별도 공개 동의가 있는 복사본만 허용하고 분석·대화 메타데이터를 제거한다.

### 16.4 게시글 상세

`postId`, `postType`, `title`, `content`, `author`, `anonymous`, `attachments`, `templateData`, `likeCount`, `commentCount`, `likedByMe`, `editableByMe`, `createdAt`, `updatedAt`을 반환한다.

### 16.5 좋아요

- 등록 응답 `201`: `{ "postId": 1, "liked": true, "likeCount": 12 }`.
- 취소 `204`.
- 중복 등록은 `409 LIKE_ALREADY_EXISTS`; 삭제 재호출은 멱등하게 `204`로 처리할 수 있다.

### 16.6 댓글과 전문가 Q&A

댓글 요청:

```json
{
  "content": "아이의 답을 정답처럼 교정하지 않고 들어주는 것이 좋습니다.",
  "anonymous": false
}
```

- 일반 보호자 게시글 댓글은 정책에 따라 검증 전문가만 작성한다.
- `postType=EXPERT_QNA`에서는 검증 전문가 댓글을 전문가 답변으로 취급한다.
- Q&A 답변의 `accepted`가 필요하면 comment 확장 필드로 관리하며 하나의 게시글에 한 건만 채택한다.
- 댓글 수정·삭제 권한은 작성자와 관리자에게만 있다.

#### 16.6-A 댓글 목록 조회 (COMM-16, S15P11B209-520)

게시글 상세(COMM-03)는 `commentCount`만 반환하므로, 댓글 본문 목록은 이 API로 분리 조회한다. 댓글 작성·수정·삭제(COMM-08/09/10) 후 목록을 다시 받아 화면을 갱신하는 읽기 경로다.

- `GET /posts/{postId}/comments`
- Query: `page`(0 이상, 기본 0), `size`(1~100, 기본 20), `sort`(`createdAt`만 허용, 기본 `createdAt,asc`). 같은 정렬값의 tie-breaker는 `commentId` 오름차순을 사용한다.
- 대상은 `comment_status=ACTIVE AND is_visible=true`인 댓글만이다(16.2-A의 `commentCount` 집계 기준과 동일). 삭제·숨김 댓글은 제외한다.
- 성공 응답은 공통 페이지 형식(`content`, `page`, `size`, `totalElements`, `totalPages`, `first`, `last`, `hasNext`)을 사용한다. 결과가 없으면 404가 아니라 200과 빈 `content`를 반환한다.
- 게시글이 없거나 비공개(`POST_NOT_FOUND`)면 404, 잘못된 `page`·`size`·`sort`는 공통 `VALIDATION_FAILED`(422)를 반환한다.

목록·작성·수정 응답의 댓글 항목 형식:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `commentId` | long | 댓글 식별자 |
| `postId` | long | 소속 게시글 식별자 |
| `author` | object\|null | 비익명은 `{userId, nickname, role, profileImageUrl}`. 익명·삭제 작성자는 `authorId:null`, `displayName:"익명 보호자"`로 마스킹하며 원 작성자 ID는 서버 감사·관리 목적에만 보존한다 |
| `anonymous` | boolean | 익명 댓글 여부 |
| `content` | string | 공개 가능한 댓글 본문 |
| `expertAnswer` | boolean | 검증 전문가가 작성한 전문가 답변 여부 |
| `accepted` | boolean | `EXPERT_QNA`에서 채택된 답변 여부(게시글당 1건) |
| `editableByMe` | boolean | 현재 인증 사용자의 수정·삭제 가능 여부(작성자 또는 ADMIN) |
| `createdAt` | string | 생성 UTC 시각 |
| `updatedAt` | string | 수정 UTC 시각 |

- COMM-08 작성 성공은 `201`, COMM-09 수정 성공은 `200`으로 생성·수정된 댓글 1건을 위 항목 형식으로 반환한다. COMM-10 삭제는 `204`다.
- 본 절은 S15P11B209-520 진행을 위해 추가된 초안이며, 팀 협약(Notion 반영·MM 공지·FE/BE 확인)을 거쳐 최종 병합한다.

### 16.7 신고

```json
{
  "targetType": "POST",
  "targetId": 10,
  "reasonCode": "PERSONAL_INFORMATION",
  "description": "아동의 학교 정보가 포함되어 있습니다."
}
```

`reasonCode`: `INAPPROPRIATE_CONTENT`, `PERSONAL_INFORMATION`, `MISLEADING_DIAGNOSIS`, `HARASSMENT`, `COPYRIGHT`, `OTHER`.

신고자는 자신의 신고만 조회할 수 있고, 신고 대상 작성자에게 신고자 정보를 공개하지 않는다. 같은 사용자의 동일 대상·사유 중복 신고는 `409 COMPLAINT_ALREADY_EXISTS`이다.

### 16.8 활동 템플릿

목록 Query: `age`, `activityType`, `authorExpertId`, `page`, `size`.

등록·수정 DTO:

```json
{
  "name": "오늘 마음 날씨 그리기",
  "recommendedAgeMin": 6,
  "recommendedAgeMax": 10,
  "activityType": "WEATHER_MIND",
  "purpose": "아동이 오늘의 느낌을 날씨로 표현하도록 돕습니다.",
  "materials": ["종이", "색연필"],
  "instructions": ["오늘 마음과 닮은 날씨를 골라요.", "그 날씨를 자유롭게 그려요."],
  "questionExamples": ["오늘 마음 날씨는 어떤 날씨야?"],
  "estimatedMinutes": 20,
  "active": true
}
```

목적·질문 예시는 치료 효과나 진단을 약속하지 않는다.

### 16.9 오류

`POST_NOT_FOUND`, `POST_ACCESS_DENIED`, `POST_TYPE_NOT_ALLOWED`, `POST_CONTENT_REJECTED`, `LIKE_ALREADY_EXISTS`, `COMMENT_NOT_FOUND`, `COMMENT_ROLE_NOT_ALLOWED`, `COMPLAINT_ALREADY_EXISTS`, `TEMPLATE_NOT_FOUND`, `TEMPLATE_AUTHOR_NOT_VERIFIED`.

COMM-01 목록 조회에서 인증 누락·만료는 공통 401, 역할·피드 권한 거부는 403, 잘못된 `type`·`feed`·`authorRole`·`page`·`size`·`sort`·`keyword`는 공통 `VALIDATION_FAILED`(422)를 사용한다. 목록 0건은 200 빈 페이지이며 `POST_NOT_FOUND`를 사용하지 않는다.

### 16.10 COMM-01 변경 이력

- 2026-07-23: S15P11B209-165 결정안 반영. 최신 DB v1.2의 게시글 유형·상태·관계 테이블을 기준으로 Query, 피드, 익명, 집계, 페이지·오류 규칙을 보완했다.
- 구현 기준: 본 문서와 `erd-cloud-schema-v1.2-spec.md`/`erd-cloud-schema-v1.2.sql`.
- 구형 `following`·`STORY/COLUMN/QNA`·`COMMUNITY_INVALID_PARAM(400)` 표현은 신규 구현 기준에서 제외하고 deprecated/충돌 사실을 기록했다.
- 본 변경은 API 문서 초안 반영이며, 팀 협약에 따른 Notion 수정·MM 공지·FE/BE/AI 확인 후 최종 병합한다.

---

## 17. 관리자 `admin`

모든 관리자 조회·수정 요청은 `audit_logs`에 관리자 ID, 행위, 리소스, 변경 전·후 값, IP, 시각을 기록한다. 비밀번호·토큰·자격 증빙 원본·아동 음성 원본은 감사 snapshot에 넣지 않는다.

### 17.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| ADMIN-01 | GET | `/admin/users` | ADMIN | 사용자 검색·상태 조회 |
| ADMIN-02 | PATCH | `/admin/users/{userId}/status` | ADMIN | 계정 이용 제한·해제·역할 변경 |
| ADMIN-03 | GET | `/admin/complaints` | ADMIN | 신고 목록 조회 |
| ADMIN-04 | GET | `/admin/complaints/{complaintId}` | ADMIN | 신고 상세 조회 |
| ADMIN-05 | PATCH | `/admin/complaints/{complaintId}` | ADMIN | 신고 처리 |
| ADMIN-06 | GET | `/admin/question-templates` | ADMIN | AI·폴백 질문 템플릿 목록 |
| ADMIN-07 | POST | `/admin/question-templates` | ADMIN | 질문 템플릿 등록 |
| ADMIN-08 | PATCH | `/admin/question-templates/{templateId}` | ADMIN | 질문 템플릿 수정·비활성화 |
| ADMIN-09 | GET | `/admin/expert-verifications` | ADMIN | 전문가 검증 대기 목록 |
| ADMIN-10 | PATCH | `/admin/experts/{expertId}/verification` | ADMIN | 전문가 자격 검증 처리 |
| ADMIN-11 | GET | `/admin/audit-logs` | ADMIN | 감사 로그 조회 |

### 17.2 사용자 검색

Query: `keyword?`, `role?`, `status?`, `page=0`, `size=20`, `sort=createdAt,desc`.

응답은 `userId`, `nickname`, `loginEmailMasked`, `role`, `accountStatus`, `reportCount`, `complaintCount`, `lastLoginAt`, `createdAt`을 반환한다. 아동 이름·그림·대화는 사용자 목록에서 반환하지 않는다.

### 17.3 사용자 상태 변경

```json
{
  "accountStatus": "SUSPENDED",
  "role": null,
  "reasonCode": "REPEATED_POLICY_VIOLATION",
  "reasonDetail": "개인정보가 포함된 게시물을 반복 등록함",
  "suspendUntil": "2026-08-21T00:00:00Z"
}
```

- ADMIN 역할 부여는 별도 최고 관리자 정책이 없으면 API로 허용하지 않는다.
- 자기 계정 정지·역할 박탈은 금지한다.
- 정지 시 활성 Refresh Token을 전부 폐기한다.
- 오류: `ADMIN_SELF_ACTION_NOT_ALLOWED`, `ACCOUNT_STATUS_TRANSITION_INVALID`, `ROLE_CHANGE_NOT_ALLOWED`.

### 17.4 신고 조회·처리

목록 Query: `targetType?`, `status?`, `reasonCode?`, `assignedToMe?`, `page`, `size`.

처리 요청:

```json
{
  "status": "RESOLVED",
  "action": "HIDE_CONTENT",
  "resolutionNote": "아동 개인정보가 포함되어 게시물을 숨김 처리했습니다.",
  "notifyReporter": true,
  "notifyTargetAuthor": true,
  "requestReanalysis": false
}
```

`action`: `NO_ACTION`, `HIDE_CONTENT`, `DELETE_CONTENT`, `WARN_USER`, `SUSPEND_USER`, `HIDE_REPORT`, `REQUEST_REANALYSIS`.

신고 처리와 대상 상태 변경은 한 트랜잭션으로 처리하고 before/after를 감사 로그에 남긴다.

### 17.5 질문 템플릿

Query: `drawingTypeCode?`, `ageGroup?`, `difficulty?`, `templateType?`, `active?`, `page`, `size`.

등록·수정 DTO:

```json
{
  "drawingTypeId": 2,
  "templateType": "FALLBACK",
  "ageGroup": "LOWER_ELEMENTARY",
  "difficulty": "LOWER_ELEMENTARY",
  "questionPurpose": "OBJECT_CONFIRMATION",
  "questionText": "이건 무엇을 그린 거야?",
  "options": [],
  "riskResponse": {
    "enabled": false,
    "guardianGuideTemplate": null
  },
  "active": true
}
```

- 진단·감정 단정·정답 유도·죄책감·과도한 개인정보 요구 표현을 금지한다.
- 이미 사용된 템플릿 문구는 대화 메시지에 snapshot으로 남으므로 수정해도 과거 기록이 바뀌지 않는다.
- 비활성화는 hard delete하지 않는다.

### 17.6 전문가 검증

목록 Query: `status=PENDING|REVIEW_REQUIRED`, `keyword?`, `page`, `size`.

처리 요청:

```json
{
  "status": "VERIFIED",
  "verifiedCredentialIds": [11, 12],
  "rejectionReason": null,
  "internalNote": "제출된 자격 증빙 확인 완료"
}
```

자격 증빙 원본 URL은 짧은 만료시간으로 관리자에게만 제공한다. 검증 결과 변경 시 전문가에게 알림을 생성한다.

### 17.7 감사 로그

Query: `actorUserId?`, `actionType?`, `resourceType?`, `resourceId?`, `from?`, `to?`, `page`, `size`.

응답: `auditLogId`, `actor`, `actionType`, `resourceType`, `resourceId`, `before`, `after`, `ipAddressMasked`, `createdAt`.

---

## 18. 전문가 연결·검토 `counseling`

이 도메인은 전문가가 AI의 초안을 승인하는 기능이 아니라, 보호자의 명시적 요청을 받아 원자료를 독립적으로 검토하고 별도 의견을 작성하는 기능이다.

### 18.1 API 목록

| ID | Method | URI | 역할 | 설명 |
| --- | --- | --- | --- | --- |
| COUNSEL-01 | POST | `/consultation-requests` | GUARDIAN | 전문가 연결·리포트 공유 요청 |
| COUNSEL-02 | GET | `/consultation-requests` | GUARDIAN, EXPERT | 내 요청 목록 |
| COUNSEL-03 | GET | `/consultation-requests/{requestId}` | 당사자 | 요청 상세 |
| COUNSEL-04 | PATCH | `/consultation-requests/{requestId}/status` | 당사자 | 승인·거절·취소·연결 해제 |
| COUNSEL-05 | GET | `/expert/review-queue` | VERIFIED EXPERT | 검토 가능한 리포트 목록 |
| COUNSEL-06 | POST | `/consultation-requests/{requestId}/reviews` | 승인된 EXPERT | 전문가 검토 의견 작성 |
| COUNSEL-07 | GET | `/reports/{reportId}/expert-reviews` | 연결 보호자, 작성 전문가 | 검토 의견 조회 |
| COUNSEL-08 | PATCH | `/expert-reviews/{reviewId}` | 작성 전문가 | 검토 의견 수정·완료 |

### 18.2 연결 요청

```json
{
  "expertId": 10,
  "childId": 1,
  "reportIds": [900, 901],
  "shareScope": ["DRAWING", "CONVERSATION", "ANALYSIS_FEATURES", "PARENT_REPORT"],
  "message": "상담 전에 최근 두 활동을 검토받고 싶습니다.",
  "shareExpiresAt": "2026-08-21T00:00:00Z"
}
```

#### 검증

- 전문가 리포트 공유 선택 동의가 활성 상태여야 한다.
- 요청자는 아동의 연결 보호자여야 한다.
- 전문가는 `VERIFIED` 상태여야 한다.
- `shareExpiresAt`은 현재 이후이며 서버 최대 공유기간을 넘지 않는다.
- 공유 범위에 없는 데이터는 전문가 API에서 반환하지 않는다.

응답: `requestId`, `status=REQUESTED`, `expert`, `child`, `reportIds`, `shareScope`, `shareExpiresAt`, `createdAt`.

### 18.3 요청 상태 변경

```json
{
  "status": "ACCEPTED",
  "reason": null
}
```

| 요청자 | 허용 전이 |
| --- | --- |
| EXPERT | `REQUESTED → ACCEPTED`, `REQUESTED → REJECTED` |
| GUARDIAN | `REQUESTED → CANCELLED`, `ACCEPTED → DISCONNECTED` |
| EXPERT | `ACCEPTED → DISCONNECTED`, 검토 완료 후 `ACCEPTED → COMPLETED` |

연결이 해제되거나 만료되면 신규 조회를 즉시 차단한다. 이미 작성된 검토 의견의 보호자 공개 여부와 보관기간은 별도 정책을 따른다.

### 18.4 검토 대기 목록

Query: `childAlias?`, `requestStatus=ACCEPTED`, `reviewStatus?`, `page`, `size`.

목록에는 최소 정보만 반환한다: `requestId`, `reportId`, `childAlias`, `drawingType`, `activityDate`, `shareExpiresAt`, `reviewStatus`.

### 18.5 전문가 검토 요청 DTO

```json
{
  "reportId": 900,
  "overallStatus": "DRAFT",
  "reviewItems": [
    {
      "aiObservationId": "obs-1",
      "agreement": "PARTIALLY_AGREE",
      "correctedText": "행동 수치는 확인되지만 정서적 의미를 단정하기 어렵습니다.",
      "reasonCode": "CONTEXT_INSUFFICIENT",
      "reasonDetail": "가정·학교·발달 맥락에 대한 정보가 없음"
    }
  ],
  "additionalQuestions": ["최근 아이가 이 장면과 관련해 이야기한 경험이 있나요?"],
  "guardianGuidance": "그림의 의미를 먼저 설명하기보다 아이의 이야기를 그대로 들어보세요.",
  "consultationRecommendation": "OPTIONAL",
  "professionalOpinion": "제공된 활동 기록만으로 진단적 판단을 할 수 없습니다."
}
```

`agreement`: `AGREE`, `PARTIALLY_AGREE`, `DISAGREE`, `INSUFFICIENT_INFORMATION`.

`consultationRecommendation`: `NOT_REQUIRED`, `OPTIONAL`, `RECOMMENDED`, `URGENT_EXTERNAL_HELP`. 마지막 값은 서비스 내 진단이 아니라 즉시 외부 도움을 고려하라는 안전 안내이다.

### 18.6 검토 완료

COUNSEL-08 요청 예시:

```json
{
  "status": "COMPLETED",
  "guardianVisible": true
}
```

- 완료 전 모든 검토 항목에 agreement와 근거가 필요하다.
- 완료 이후 수정은 새 `reviewVersion`을 만들고 이전 버전을 보존한다.
- 보호자 화면은 전문가 의견과 AI 활동 요약을 명확히 구분한다.
- 검토 의견에 진단명이 필요하다고 판단되는 경우 서비스에 진단명 필드를 추가하지 않고 적절한 외부 평가 절차를 안내한다.

### 18.7 오류

`CONSULTATION_REQUEST_NOT_FOUND`, `CONSULTATION_STATUS_INVALID`, `EXPERT_NOT_VERIFIED`, `REPORT_SHARE_CONSENT_REQUIRED`, `REPORT_SHARE_SCOPE_DENIED`, `REPORT_SHARE_EXPIRED`, `EXPERT_REVIEW_ALREADY_COMPLETED`, `EXPERT_REVIEW_ACCESS_DENIED`.

---

## 19. 내부 AI 연동 `internal-ai`

외부 프론트엔드는 이 API를 호출하지 않는다. Spring Boot가 사용자 권한·동의·상태를 검증한 후 필요한 최소 데이터만 전달한다.

### 19.1 API 목록

| ID | Method | URI | 호출자 | 설명 |
| --- | --- | --- | --- | --- |
| AI-01 | POST | `/internal/v1/analyses` | Spring Boot | 객체·시각·행동·대화 종합 분석 |
| AI-02 | POST | `/internal/v1/conversations/next-question` | Spring Boot | 다음 질문 생성 |
| AI-03 | POST | `/internal/v1/speech/stt` | Spring Boot | 아동 음성 STT |
| AI-04 | POST | `/internal/v1/speech/tts` | Spring Boot | 질문 TTS |
| AI-05 | GET | `/internal/v1/health` | Spring Boot, 운영 | AI 서버·모델 준비 상태 |

### 19.2 공통 내부 규칙

- `X-Internal-Api-Key`, mTLS 또는 사설망 중 최소 2개로 보호한다.
- `X-Request-Id`와 `analysisId`를 전체 로그 상관관계 키로 사용한다.
- 아동 이름·생년월일·보호자 정보는 전달하지 않는다. 연령대·질문 난이도만 전달한다.
- AI 서버는 외부 공개 URL이나 DB 자격 증명을 받지 않는다. 이미지·음성 URL은 짧은 만료시간의 읽기 전용 URL이다.
- Mock AI와 실제 AI는 동일한 요청·응답 DTO를 사용한다.
- AI 서버는 MySQL에 직접 저장하지 않고 결과를 Spring Boot에 반환한다.

### 19.3 종합 분석 요청

```json
{
  "analysisId": 701,
  "drawingSessionId": 100,
  "analysisType": "FINAL",
  "triggerReason": "ACTIVITY_COMPLETE",
  "childContext": {
    "age": 7,
    "ageGroup": "LOWER_ELEMENTARY",
    "questionDifficulty": "LOWER_ELEMENTARY"
  },
  "drawing": {
    "drawingAssetId": 502,
    "signedUrl": "http://backend:8080/internal/v1/ai-images/opaque-one-time-token",
    "mimeType": "image/png",
    "width": 1920,
    "height": 1080,
    "inputMethod": "CANVAS",
    "checksumSha256": "sha256-value"
  },
  "behavior": {
    "strokeBatchUrls": [],
    "summary": {
      "drawingDurationMs": 600000,
      "pauseCount": 4,
      "undoCount": 2,
      "eraseCount": 3,
      "pressureAvailable": false
    }
  },
  "conversation": {
    "messages": [
      { "messageId": 803, "senderType": "AI", "messageType": "QUESTION", "text": "이 사람은 어떤 기분인 것 같아?" },
      { "messageId": 804, "senderType": "CHILD", "messageType": "VOICE_ANSWER", "text": "친구랑 있어서 좋아" }
    ]
  },
  "reflection": {
    "selectedEmotions": ["HAPPY", "CALM"],
    "expressedEmotionText": "다 같이 있어서 좋았어"
  },
  "rag": {
    "knowledgeBaseVersion": "2026.07",
    "allowedSourceTypes": ["PEER_REVIEWED_PAPER", "PRACTICE_GUIDELINE"],
    "maxReferences": 5
  }
}
```

`drawing.signedUrl`은 외부 공개 URL이 아니다. Backend가 분석 요청 직전에 발급하는 Docker 내부망
전용 URL이며 기본 60초 안에 최초 한 번만 조회할 수 있다. AI 서버는 URL, Token 또는 원본 이미지
Byte를 로그에 기록하지 않는다.

`drawing.inputMethod`는 그림 세션에 저장된 입력 방식이며 Backend가 항상 전달한다. `CANVAS`는 앱
Canvas에서 직접 그린 그림이고, `UPLOAD`는 카메라 촬영·스캔·갤러리 선택·외부 디지털 이미지처럼
파일로 입력된 그림 전체를 뜻한다. AI 서버는 순차 배포 중 필드가 없는 구버전 요청만 `CANVAS`로
간주한다. `UPLOAD`가 촬영 사진임을 보장하지 않으므로 사진 보정은 조명·그림자·원근·종이 질감 등
촬영 흔적을 확인한 경우에만 선택적으로 적용한다.

### 19.4 종합 분석 응답

```json
{
  "analysisId": 701,
  "status": "PARTIAL_SUCCESS",
  "modelInfo": {
    "objectDetection": { "name": "yolo", "version": "1.0.0" },
    "vision": { "name": "vision-model", "version": "1.0.0" },
    "language": { "name": "llm-model", "version": "1.0.0" },
    "knowledgeBaseVersion": "2026.07"
  },
  "detectedObjects": [
    {
      "objectCode": "PERSON",
      "objectName": "사람",
      "confidence": 0.92,
      "boundingBox": { "x": 0.15, "y": 0.20, "width": 0.25, "height": 0.50 },
      "areaRatio": 0.125,
      "detectionOrder": 1
    }
  ],
  "visualFeatures": {},
  "behaviorFeatures": {
    "pressureAvailable": false,
    "drawingDurationMs": 600000,
    "pauseCount": 4,
    "eraseCount": 3
  },
  "conversationSummary": {
    "summaryText": "아동은 함께 있는 사람들에 대해 이야기했습니다.",
    "representativeUtterance": "친구랑 있어서 좋아",
    "questionCount": 4,
    "responseCount": 3,
    "skippedQuestionCount": 1,
    "unrecognizedSpeechCount": 1
  },
  "observationDraft": {
    "status": "AI_DRAFT",
    "overallSummary": "전문가 검토를 위한 관찰 내용 초안입니다.",
    "observations": [],
    "followUpQuestions": [],
    "expertReviewRequired": true,
    "disclaimer": "진단 결과가 아니며 개별 맥락에 대한 전문가 검토가 필요합니다."
  },
  "evidenceReferences": [],
  "unusedInputs": [
    {
      "sourceType": "PRESSURE",
      "reasonCode": "DEVICE_NOT_SUPPORTED",
      "reasonDetail": "입력 기기가 필압을 지원하지 않음",
      "retryable": false
    }
  ],
  "warnings": ["PRESSURE_DATA_UNAVAILABLE"],
  "processingTimeMs": 3840
}
```

AI 응답에 진단명, 질환 확률, 가정환경 원인 단정이 포함되면 Spring Boot 안전 필터가 저장·노출을 거부하고 `AI_OUTPUT_POLICY_VIOLATION`으로 기록한다.

### 19.5 다음 질문 요청·응답

요청 핵심 필드: `conversationId`, `ageGroup`, `difficulty`, `questionCount`, `maxQuestionCount`, `detectedObjects`, `previousMessages`, `allowedResponseModes`, `safetyRulesVersion`.

응답:

```json
{
  "question": {
    "text": "이 사람은 누구와 함께 있는 것 같아?",
    "purpose": "OBJECT_RELATION",
    "options": [],
    "targetObject": {
      "objectCode": "PERSON",
      "boundingBox": { "x": 0.15, "y": 0.20, "width": 0.25, "height": 0.50 }
    }
  },
  "fallbackUsed": false,
  "safety": {
    "passed": true,
    "blockedReasons": []
  },
  "modelVersion": "llm-model:1.0.0"
}
```

### 19.6 STT

`multipart/form-data`: `audio`, `metadata` JSON(`requestId`, `language=ko-KR`, `ageGroup`, `maxDurationMs`).

```json
{
  "status": "SUCCESS",
  "text": "친구랑 있어서 좋아",
  "confidence": 0.91,
  "language": "ko-KR",
  "segments": [],
  "needsConfirmation": false,
  "modelVersion": "stt-model:1.0.0",
  "processingTimeMs": 620
}
```

인식 실패는 추측 문장을 만들지 않고 `status=FAILED`, `failureReason=NO_SPEECH|LOW_CONFIDENCE|UNSUPPORTED_AUDIO|TIMEOUT`을 반환한다.

### 19.7 TTS

```json
{
  "text": "이 그림에서 가장 마음에 드는 곳은 어디야?",
  "voice": "CHILD_FRIENDLY_01",
  "speed": 0.95,
  "format": "MP3"
}
```

응답은 `audio/mpeg` binary이며 `X-Audio-Duration-Ms`, `X-TTS-Model-Version` Header를 포함한다. 실패 시 JSON 공통 오류를 반환한다.

### 19.8 Health

```json
{
  "status": "UP",
  "models": {
    "objectDetection": "READY",
    "vision": "READY",
    "language": "READY",
    "stt": "READY",
    "tts": "READY",
    "rag": "READY"
  },
  "knowledgeBaseVersion": "2026.07",
  "timestamp": "2026-07-21T02:30:00Z"
}
```

---

## 20. 권한 매트릭스

| 리소스 | GUARDIAN | EXPERT | ADMIN |
| --- | --- | --- | --- |
| 내 사용자 정보 | 본인 | 본인 | 운영 정책에 따른 제한 조회 |
| 아동 프로필 | 연결된 아동 관리 | 접근 불가 | 민원·삭제 처리에 필요한 최소 조회 |
| 그림·대화 | 연결된 아동 | 유효한 공유 승인 범위만 조회 | 원칙적으로 내용 조회 금지, 신고 처리 시 최소 범위 |
| 보호자 리포트 | 연결된 아동 | 공유 승인 시 조회 | 상태·신고 정보 중심 |
| 전문가 검토 자료 | 접근하지 않음 | 공유 승인·검증 상태 충족 시 조회 | 접근 감사와 신고 처리 최소 범위 |
| 전문가 의견 | 공유받은 보호자 | 본인이 작성한 의견 | 신고 처리·감사 |
| 커뮤니티 | 작성·조회·좋아요 | 작성·조회·좋아요·정책상 댓글 | 숨김·삭제·공지 |
| 전문가 프로필 | 공개 정보 조회·팔로우 | 본인 관리 | 검증·제한 |
| 관리자 API | 접근 불가 | 접근 불가 | 접근 가능 |

리소스 소유권 실패는 다른 사용자가 ID 존재 여부를 추측하지 못하도록 일반적으로 `404`를 반환한다.

---

## 21. 기존 API → 정리된 API 변경표

| 기존 | 정리된 계약 | 변경 이유 |
| --- | --- | --- |
| `POST /auth/kakao` | `POST /auth/oauth/KAKAO` | 소셜 로그인 DTO 통일 |
| `POST /auth/google` | `POST /auth/oauth/GOOGLE` | 동일 |
| `POST /auth/naver` | `POST /auth/oauth/NAVER` | 동일 |
| `POST /users` | `PUT /users/me/onboarding` | 로그인 사용자 온보딩임을 명확히 하고 멱등성 확보 |
| `DELETE /children/{childId}?cascade=` | `DELETE /children/{childId}` + 확인 Body | 삭제 정책을 클라이언트 Query로 임의 변경하지 못하게 함 |
| `POST /drawing-sessions/{sessionId}/strokes` | `POST /drawing-sessions/{drawingSessionId}/stroke-batches` | 실제 저장 단위가 batch이고 ID 명칭을 통일 |
| `POST /drawing-sessions/{sessionId}/draft` | `PUT /drawing-sessions/{drawingSessionId}/draft` | 최신 임시 저장 전체본 upsert 의미 |
| `POST /drawing-sessions/{sessionId}/upload` | `POST /drawing-sessions/{drawingSessionId}/upload` | Path 변수 명칭을 `drawingSessionId`로 통일 |
| `POST /drawing-sessions/{sessionId}/complete` | `POST /drawing-sessions/{drawingSessionId}/drawing-complete` | 그림 단계 완료와 전체 활동 완료를 분리 |
| 없음 | `POST /drawing-sessions/{drawingSessionId}/complete` | 대화·감정까지 포함한 전체 활동 완료 |
| `POST /analyses/realtime` | `POST /drawing-sessions/{drawingSessionId}/analyses` + `analysisType=INTERMEDIATE` | 분석을 세션 하위 리소스로 통일 |
| `POST /drawing-sessions/{sessionId}/analysis` | 동일 URI + `analysisType=FINAL` | 중간·최종 DTO 통일 |
| `POST /drawing-sessions/{sessionId}/conversation` | `POST /drawing-sessions/{drawingSessionId}/conversations` | 리소스 복수형 통일 |
| `POST /conversations/{conversationId}/next` | `POST /conversations/{conversationId}/next-question` | 동작 의미 명확화 |
| `GET /conversations/{conversationId}/questions/{questionId}/tts` | `POST /conversation-messages/{messageId}/tts` | 질문은 message이며 음성 생성은 생성성 작업 |
| `GET /children/{childId}/activities` | `GET /children/{childId}/drawing-sessions` | `activities` 테이블이 없고 ERD와 불일치 |
| `GET /activities/{activityId}` | `GET /drawing-sessions/{drawingSessionId}` | 동일 리소스 중복 제거 |
| `DELETE /activities/{activityId}` | `DELETE /drawing-sessions/{drawingSessionId}` | 동일 |
| `POST /posts/{postId}/complaints` | `POST /complaints` | 게시글·댓글·리포트·AI 질문 신고 DTO 통일 |
| `POST /reports/{reportId}/complaints` | `POST /complaints` | 동일 |
| `GET/POST /admin/questions` | `GET/POST /admin/question-templates` | ERD `ai_question_templates`와 의미 일치 |
| `PATCH /admin/questions/{questionId}` | `PATCH /admin/question-templates/{templateId}` | 대상이 대화 message가 아니라 질문 템플릿임을 명확히 함 |
| Query `following=true` | Query `feed=FOLLOWING` | boolean보다 피드 유형 확장 가능 |

백엔드 구현 전에 기존 경로를 제거하거나, 한 릴리스 동안 deprecated adapter를 둘지 팀에서 결정한다. 두 URI가 서로 다른 Service 로직을 호출하게 만들면 안 된다.

---

## 22. ERD 정합성 수정 필요 사항

첨부 ERD에서 API 구현 전에 수정해야 할 항목이다.

| 현재 항목 | 수정안 | 이유 |
| --- | --- | --- |
| `conversation_sessions.conversation_id` | `drawing_session_id` | 주석과 관계상 그림 활동 FK이며 명칭이 잘못됨 |
| `expert_follows.Key` 및 `(id, Key)` 복합 PK | `Key` 삭제, PK는 `id`, unique `(guardian_user_id, expert_profile_id)` | 의미 없는 Key와 중복 팔로우 방지 |
| `analysis_detected_objects.drawing_image_id` | `drawing_asset_id` | `drawing_images` 테이블이 없고 탐지 입력은 asset |
| `analysis_behavior_features.tool_chnage_count` | `tool_change_count` | 오탈자 |
| `analysis_conversation_summaries.conversation_sumaary_id` | `conversation_summary_id` | 오탈자 |
| `reports.report_status` 기본 `GENERATING` | Enum을 문서의 `ReportStatus`로 고정 | FE·BE 상태 불일치 방지 |
| `drawing_sessions.session_status`, `current_stage` | 10.1 상태값 적용 | 생명주기와 화면 단계 분리 |
| `conversation_messages.bounding_box`와 `target_object_json` | `target_object_json` 안에 boundingBox 통합 또는 역할 명확화 | 중복 데이터 불일치 방지 |
| `analysis_observation_results.observed_emotion`, `emotion_confidence` | 전문가 내부 초안으로 제한하거나 제거 | 보호자에게 진단형 감정 추정을 노출할 위험 |

### 22.1 필수 unique 제약

- `auth_accounts(provider, provider_subject)`
- `auth_accounts(login_email)` where provider=`LOCAL`
- `stroke_batches(drawing_session_id, batch_sequence)`
- `guardian_child_relations(guardian_user_id, child_id)`
- `analyses(idempotency_key)`
- `conversation_messages(conversation_session_id, message_sequence)`
- `post_likes(post_id, user_id)`
- `expert_follows(guardian_user_id, expert_profile_id)`
- `reports(drawing_session_id, report_version)`

### 22.2 현재 ERD에 추가 또는 확장 검토가 필요한 저장 구조

| API 기능 | 저장 구조 |
| --- | --- |
| 전문가 자격 증빙 | `expert_credentials` 별도 테이블 권장. `credentials_json`만 사용할 경우 버전·검증 이력 관리가 어려움 |
| 푸시 기기 토큰 | `notification_device_tokens` |
| 커뮤니티 신고·리포트 신고 | `complaints`, `complaint_actions` |
| 미술 활동 템플릿 | `activity_templates` 또는 `community_posts.template_data_json`의 명확한 단일 선택 |
| 전문가 연결 | 확장 스키마 `consultation_requests`, `consultation_report_shares`, `expert_reviews` |
| RAG 근거 | `analysis_evidence_sources` 권장. 최소한 `reports.evidence_json`에 필수 출처 schema 고정 |
| 전문가 AI 검토 평가 | `expert_review_items` 또는 `expert_reviews.review_items_json` |
| 리포트 조회 감사 | `audit_logs`에 `REPORT_VIEW` 기록 또는 별도 접근 로그 |

---

## 23. 전체 사용자 흐름과 호출 순서

### 23.1 캔버스 활동

```
1. GET  /consents?childId=1
2. GET  /drawing-types?childId=1
3. POST /drawing-sessions
4. POST /drawing-sessions/{id}/stroke-batches          반복
5. PUT  /drawing-sessions/{id}/draft                   자동 저장
6. POST /drawing-sessions/{id}/analyses                선택: 그리는 중간 분석
7. GET  /analyses/{analysisId}                         선택: 중간 분석 폴링
8. POST /drawing-sessions/{id}/conversations           선택: 중간 대화 시작
9. POST /conversations/{id}/next-question              선택: 중간 질문
10. POST /conversations/{id}/answers/voice|option      선택: 답변
11. POST /conversations/{id}/skip                      다시 그리기로 복귀 가능
12. POST /drawing-sessions/{id}/drawing-complete       최종 그림 저장
13. GET  /analyses/{analysisId}                        대화 준비 분석 폴링
14. POST /drawing-sessions/{id}/conversations          기존 대화가 없을 때만 생성
15. POST /conversations/{id}/next-question
16. POST /conversation-messages/{messageId}/tts
17. POST /conversations/{id}/answers/voice|option      반복
18. POST /conversations/{id}/end
19. PUT  /drawing-sessions/{id}/reflection
20. POST /drawing-sessions/{id}/complete
21. GET  /analyses/{analysisId}                        최종 종합 분석 폴링
22. GET  /reports/{reportId}
```

중간 대화를 사용하지 않으면 6~11단계를 생략한다. 중간 대화 후 다시 그림을 그리면 4~11단계를 반복하되 대화 세션을 새로 만들지 않고 기존 `conversationId`를 재사용한다. 프론트는 서버가 반환한 `currentStage`를 기준으로 화면을 복구한다.

### 23.2 종이 그림 업로드

```
POST /drawing-sessions                 inputMethod=UPLOAD
POST /drawing-sessions/{id}/upload
POST /drawing-sessions/{id}/drawing-complete
POST /drawing-sessions/{id}/conversations
... 대화 ...
PUT  /drawing-sessions/{id}/reflection
POST /drawing-sessions/{id}/complete
GET  /reports/{reportId}
```

### 23.3 전문가 검토

```
보호자: PATCH /consents
보호자: POST  /consultation-requests
전문가: PATCH /consultation-requests/{id}/status       ACCEPTED
전문가: GET   /expert/reports/{reportId}
전문가: POST  /consultation-requests/{id}/reviews
전문가: PATCH /expert-reviews/{reviewId}               COMPLETED
보호자: GET   /reports/{reportId}/expert-reviews
```

---

## 24. 포지션별 구현 체크리스트

### 24.1 프론트엔드

- API Base URL과 Token 저장소를 환경별로 분리한다.
- 요청·응답 DTO를 임의로 재정의하지 않고 OpenAPI 생성 타입 또는 공용 schema를 사용한다.
- `activityId` 대신 전 화면에서 `drawingSessionId`를 사용한다.
- 서버 Enum에 없는 한글 값을 API로 보내지 않는다. 한글은 UI label에만 사용한다.
- `401 TOKEN_EXPIRED` 시 한 번만 재발급 후 원 요청을 재시도하며 무한 루프를 막는다.
- AI 분석은 `pollAfterMs`를 따르고 화면 이탈 시 polling을 중단한다.
- TTS 재생 중 마이크 OFF, 재생 종료 후 마이크 ON을 보장한다.
- STT 실패 시 선택지·다시 말하기·건너뛰기를 제공한다.
- `pressure:null`을 0으로 변환하지 않는다.
- 보호자 화면에서 전문가용 AI 초안·raw score·진단형 필드를 표시하지 않는다.
- signed URL 만료 시 리소스 상세 API를 재조회한다.

### 24.2 Spring Boot 백엔드

- 모든 아동·세션·리포트 요청에 사용자-아동 소유권을 검증한다.
- Controller DTO와 AI 내부 DTO를 분리한다.
- 파일 signature, 용량, 이미지 크기, EXIF 제거를 서버에서 재검증한다.
- 상태 변경은 Service 한 곳에서 관리하고 Controller별로 상태값을 직접 수정하지 않는다.
- 분석·완료 POST에 멱등성을 적용한다.
- 외부 API는 AI 서버 장애 시 `502/503`과 재시도 가능한 상태를 구분한다.
- AI 결과를 schema와 안전 정책으로 검증한 뒤 저장한다.
- 보호자 DTO와 전문가 DTO를 별도 mapper로 생성해 민감 필드 누출을 방지한다.
- 삭제는 DB soft delete, S3 삭제 작업, 전문가 공유 해제를 함께 처리한다.
- Swagger에 성공·검증 실패·권한 실패·상태 충돌 예시를 등록한다.

### 24.3 AI 서버

- Spring Boot 내부 요청만 허용한다.
- 입력에 없는 아동 정보나 맥락을 추정하지 않는다.
- 필압 미지원·STT 실패 등 누락 입력을 `unusedInputs`에 명시한다.
- 객체 탐지 confidence와 정서·진단 confidence를 혼동하지 않는다.
- RAG 문장마다 근거 ID와 검색 chunk hash를 반환한다.
- 검색 근거가 없으면 문장을 생성하지 않고 제한사항을 반환한다.
- 진단명, 질환 확률, 원인 단정, 치료 효과 보장을 생성하지 않는다.
- 모델·프롬프트·knowledge base 버전을 결과에 남긴다.
- Mock과 실제 구현이 동일 DTO와 Enum을 사용하도록 contract test를 통과시킨다.

### 24.4 공통 협업

- API 변경은 먼저 본 문서와 OpenAPI schema를 수정한 뒤 FE·BE·AI가 함께 검토한다.
- 필드 삭제·이름 변경은 즉시 적용하지 않고 버전 변경 또는 deprecation 기간을 둔다.
- Swagger example과 프론트 mock fixture는 같은 JSON 파일에서 생성한다.
- 상태·Enum·오류 코드는 문자열 상수로 공유하고 각 포지션이 별도 한글 상태를 만들지 않는다.

---

## 25. 계약 테스트 필수 시나리오

| 시나리오 | 기대 결과 |
| --- | --- |
| 같은 Idempotency-Key로 세션 생성 2회 | 동일 `drawingSessionId` 반환 |
| 같은 Idempotency-Key에 다른 Body | `409 IDEMPOTENCY_KEY_REUSED` |
| 다른 보호자의 childId 조회 | `404` |
| 만 4세 미만·12세 초과 등록 | `422 CHILD_AGE_OUT_OF_RANGE` |
| 음성 처리 동의 없이 voice answer | `403 VOICE_CONSENT_REQUIRED` |
| batchSequence 중복, payload 동일 | 최초 저장 결과 반환 |
| batchSequence 중복, payload 다름 | `409 STROKE_BATCH_CONFLICT` |
| 진행 중 세션에 전체 완료 호출 | `409 INVALID_STATE_TRANSITION` |
| AI 서버 중단 중 그림 저장 | 그림 저장 성공, 분석은 재시도 가능 실패 상태 |
| AI 응답에 진단 문장 포함 | 저장·보호자 노출 차단, `AI_OUTPUT_POLICY_VIOLATION` 기록 |
| 보호자가 전문가용 리포트 URI 호출 | `403` 또는 정책상 `404` |
| 공유 만료 후 전문가 리포트 조회 | `403 EXPERT_SHARE_EXPIRED` |
| 필압 미지원 기기 | `pressureAvailable=false`, 평균 필압 `null` |
| STT low confidence | 추정 텍스트 확정 금지, 폴백 선택지 제공 |
| 활동 삭제 후 signed URL 접근 | 접근 불가 |
| 전문가 검토 완료 후 수정 | 새 review version 생성 |

---

## 26. 신뢰성 검증 데이터 계약

AI 초안과 전문가 검토의 품질 비교는 운영자·연구 검증 영역이며 보호자 리포트에 점수로 노출하지 않는다.

### 26.1 검토 레코드

| 필드 | 설명 |
| --- | --- |
| `analysisId` | 검토한 분석 버전 |
| `modelVersions` | 객체·Vision·LLM·RAG 버전 |
| `expertId` | 검증된 평가자 |
| `agreement` | `AGREE`, `PARTIALLY_AGREE`, `DISAGREE`, `INSUFFICIENT_INFORMATION` |
| `errorTypes` | `UNSUPPORTED_INFERENCE`, `MISSING_EVIDENCE`, `WRONG_EVIDENCE`, `OVERGENERALIZATION`, `MISSING_CONTEXT`, `UNSAFE_WORDING` |
| `correctedText` | 전문가 수정 문장 |
| `reasonDetail` | 수정 근거 |
| `reviewedAt` | 검토 시각 |

### 26.2 지표 분리

| 구성요소 | 지표 예시 |
| --- | --- |
| 객체 탐지 | class별 precision, recall, mAP, false positive 유형 |
| 시각·행동 특징 | 정답 데이터 대비 오차, 측정 불가 비율 |
| STT | 연령대·소음 조건별 WER, low confidence 탐지율 |
| RAG | Recall@K, 출처 적합성, 인용 정확성, 근거 없는 생성률 |
| 관찰 초안 | 전문가 agreement 분포, unsupported inference 비율, 수정률 |
| 안전성 | 진단형 표현·낙인 표현·근거 없는 위험 판단 차단율 |

“실제 검사 진단과 AI 진단의 일치율”이라는 단일 수치로 서비스 신뢰성을 주장하지 않는다. 본 서비스는 진단 시스템이 아니므로 구성요소별 성능과 전문가 검토 결과를 분리해 보고한다.

---

## 27. 최종 계약 요약

1. 클라이언트는 Spring Boot만 호출한다.
2. 그림 활동 식별자는 모든 영역에서 `drawingSessionId`로 통일한다.
3. 그림 단계 완료, 대화 종료, 감정 저장, 전체 활동 완료를 분리한다.
4. 중간·최종 분석은 같은 분석 리소스와 DTO를 사용하되 `analysisType`으로 구분한다.
5. 분석 원본, 보호자용 활동 리포트, 전문가용 검토 자료, 전문가 의견을 분리한다.
6. RAG는 출처를 연결하지만 진단 권한을 만들지 않는다.
7. 보호자에게 진단형 점수·AI 감정 추정·raw risk score를 노출하지 않는다.
8. 전문가 상세 자료는 보호자 공유 동의와 전문가 검증을 모두 확인한다.
9. 파일·분석·완료 요청은 중복과 재시도를 고려해 설계한다.
10. ERD 오탈자·FK·unique 제약을 수정한 뒤 Entity와 Swagger DTO를 확정한다.
